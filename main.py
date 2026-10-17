"""
Galcon 2 — Always-On Recorder + Discord Uploader

Run once and leave it running. Automatically records every game.

QUICK PLAY (default): each game → separate .jsonl file → uploaded to Discord
BATCH MODE (toggle /batch in room): all games → one .jsonl → uploaded when toggled off

Install: pip install discord.py
Run:     python3 galcon_recorder.py
Stop:    Ctrl+C
"""

import json, os, re, time, asyncio, threading, math
from datetime import datetime
import discord

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────
BIN_FILE   = "/Users/phillipcall/Library/Application Support/Steam/userdata/1208075763/294160/remote/mod1.bin"
OUTPUT_DIR = "/Users/phillipcall/PycharmProjects/galconreplay/galcon_recordings"
BOT_TOKEN  = os.environ["DISCORD_BOT_TOKEN"]
CHANNEL_ID = 1515123696099000492   # integer channel ID

# ─────────────────────────────────────────────────────────────────────────────
# STATS PERSISTENCE  (room_stats.json in OUTPUT_DIR)
# ─────────────────────────────────────────────────────────────────────────────
STATS_FILE = os.path.join(os.path.dirname(OUTPUT_DIR) or '.', 'room_stats.json')

def load_stats():
    try:
        with open(STATS_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

def save_stats(stats):
    try:
        with open(STATS_FILE, 'w') as f:
            json.dump(stats, f, indent=2)
    except Exception as ex:
        print(f"[stats] save error: {ex}")

def calc_elo_change(winner_elo, loser_elo, K=32):
    exp = 1 / (1 + 10 ** ((loser_elo - winner_elo) / 400))
    return max(1, int(K * (1 - exp)))

def record_result(p1_uid, p1_name, p2_uid, p2_name, winner_uid, is_warmup, timestamp=None):
    """Update room_stats.json with game result."""
    stats = load_stats()
    ts = timestamp or datetime.now().isoformat()

    for uid, name in [(p1_uid, p1_name), (p2_uid, p2_name)]:
        if uid and uid not in stats:
            stats[uid] = {'name': name, 'elo': 1200, 'wins': 0, 'losses': 0,
                          'streak': 0, 'h2h': {}, 'elo_history': [
                              {'t': ts, 'elo': 1200, 'label': 'Start'}
                          ]}
        if uid and name:
            stats[uid]['name'] = name

    if not winner_uid or winner_uid not in (p1_uid, p2_uid):
        save_stats(stats); return  # draw / abort — no ELO change

    loser_uid = p2_uid if winner_uid == p1_uid else p1_uid
    ws, ls = stats[winner_uid], stats[loser_uid]

    # H2H
    ws.setdefault('h2h', {})
    ls.setdefault('h2h', {})
    wh = ws['h2h'].setdefault(loser_uid,  {'w': 0, 'l': 0})
    lh = ls['h2h'].setdefault(winner_uid, {'w': 0, 'l': 0})
    wh['w'] += 1; lh['l'] += 1

    # W/L
    ws['wins']   = ws.get('wins', 0) + 1
    ls['losses'] = ls.get('losses', 0) + 1

    # Streak
    ws['streak'] = (ws.get('streak', 0) + 1) if ws.get('streak', 0) >= 0 else 1
    ls['streak'] = (ls.get('streak', 0) - 1) if ls.get('streak', 0) <= 0 else -1

    if not is_warmup:
        delta = calc_elo_change(ws['elo'], ls['elo'])
        ws['elo'] += delta
        ls['elo'] = max(100, ls['elo'] - delta)
        ws.setdefault('elo_history', []).append({
            't': ts, 'elo': ws['elo'],
            'label': f"+{delta} vs {ls['name']}"
        })
        ls.setdefault('elo_history', []).append({
            't': ts, 'elo': ls['elo'],
            'label': f"-{delta} vs {ws['name']}"
        })
        print(f"[stats] ELO: {ws['name']} +{delta} ({ws['elo']})  {ls['name']} -{delta} ({ls['elo']})")

    save_stats(stats)
    print(f"[stats] recorded: {ws['name']} beat {ls['name']}{'  [warmup]' if is_warmup else ''}")

# ─────────────────────────────────────────────────────────────────────────────
# DISCORD
# ─────────────────────────────────────────────────────────────────────────────
intents = discord.Intents.default()
dc = discord.Client(intents=intents)
upload_queue: asyncio.Queue = None

def sanitize(name):
    return re.sub(r"[^\w]", "", str(name))[:20] or "Player"


def split_batch_for_discord(path, max_compressed_bytes=7 * 1024 * 1024):
    """
    Split a batch JSONL into Discord-uploadable parts.
    Measures each game's compressed size individually, then greedily packs
    games into parts — the moment adding another game would exceed the limit,
    that part is closed and a new one starts.
    """
    import gzip

    with open(path) as f:
        raw_lines = f.readlines()

    header = raw_lines[0]   # {"type":"batch_header",...}

    # ── Group lines by game ────────────────────────────────────────────────
    games = []      # list of lists-of-lines, one per game
    cur   = None
    for line in raw_lines[1:]:
        stripped = line.strip()
        if not stripped:
            continue
        try:
            obj = json.loads(stripped)
        except Exception:
            continue
        if obj.get('type') == 'game_divider':
            if cur is not None:
                games.append(cur)
            cur = [line]
        elif cur is not None:
            cur.append(line)
    if cur:
        games.append(cur)

    if not games:
        return [path]   # nothing to split

    # ── Measure compressed size of each game individually ─────────────────
    # compresslevel=1 is fast; gives a good enough estimate for bin-packing
    header_gz = len(gzip.compress(header.encode(), compresslevel=1))
    game_gz   = []
    for g in games:
        raw = ''.join(g).encode()
        game_gz.append(len(gzip.compress(raw, compresslevel=1)))

    print(f"[discord] {len(games)} games, "
          f"avg compressed size {sum(game_gz)/len(game_gz)/1024:.0f} KB/game")

    # ── Greedy bin-packing into parts ─────────────────────────────────────
    parts_plan = []     # list of lists of game indices
    current    = []
    cur_size   = header_gz

    for i, gz in enumerate(game_gz):
        if current and cur_size + gz > max_compressed_bytes:
            parts_plan.append(current)
            current  = [i]
            cur_size = header_gz + gz
        else:
            current.append(i)
            cur_size += gz

    if current:
        parts_plan.append(current)

    # ── Write part files ───────────────────────────────────────────────────
    base    = path.rsplit('.', 1)[0]
    n_parts = len(parts_plan)
    paths   = []

    for pi, indices in enumerate(parts_plan):
        part_path = f"{base}_part{pi+1}of{n_parts}.jsonl"
        with open(part_path, 'w') as f:
            f.write(header)
            for gi in indices:
                for line in games[gi]:
                    f.write(line)
        size_mb = os.path.getsize(part_path) / 1024 / 1024
        print(f"[discord] part {pi+1}/{n_parts}: {len(indices)} games, {size_mb:.1f} MB raw")
        paths.append(part_path)

    return paths

DISCORD_MAX_MB = 9.5   # safe limit below Discord's 10MB cap (as set by user)

async def uploader_loop():
    await dc.wait_until_ready()
    ch = dc.get_channel(CHANNEL_ID)
    if not ch:
        print(f"[discord] ERROR: channel {CHANNEL_ID} not found")
        return
    print(f"[discord] ready → #{ch.name}")
    while True:
        path, label = await upload_queue.get()
        if not os.path.exists(path):
            print(f"[discord] file missing: {path}")
            continue
        try:
            fname   = os.path.basename(path)
            size_mb = os.path.getsize(path) / 1024 / 1024

            if size_mb <= DISCORD_MAX_MB:
                # Normal upload
                msg = "🎮 " + label + "`" + fname + "`"
                await ch.send(content=msg, file=discord.File(path, filename=fname))
                print(f"[discord] uploaded: {fname}  ({size_mb:.1f} MB)")

            else:
                # File too large — split into parts at game boundaries, gzip each
                import gzip, shutil
                print(f"[discord] {size_mb:.0f} MB — splitting into parts for upload")
                try:
                    parts = split_batch_for_discord(path)
                    n = len(parts)
                    for i, part_path in enumerate(parts):
                        gz_path = part_path + '.gz'
                        try:
                            with open(part_path,'rb') as fi, gzip.open(gz_path,'wb') as fo:
                                shutil.copyfileobj(fi, fo)
                            gz_mb  = os.path.getsize(gz_path) / 1024 / 1024
                            gz_fn  = os.path.basename(gz_path)
                            part_lbl = label + "[Part " + str(i+1) + "/" + str(n) + "] "
                            part_msg = "🎮 " + part_lbl + "`" + gz_fn + "` (" + f"{gz_mb:.1f}" + " MB compressed)"
                            await ch.send(content=part_msg, file=discord.File(gz_path, filename=gz_fn))
                            print(f"[discord] uploaded part {i+1}/{n}: {gz_fn}  ({gz_mb:.1f} MB)")
                        finally:
                            for tmp in (part_path, gz_path):
                                if os.path.exists(tmp): os.remove(tmp)
                except Exception as split_err:
                    print(f"[discord] split failed: {split_err} — file at: {path}")
                    msg = "🎮 " + label + "`" + fname + "` — too large (" + f"{size_mb:.0f}" + " MB). File saved at:\n" + path
                    await ch.send(content=msg)

        except Exception as ex:
            print(f"[discord] upload error: {ex}")
            print(f"[discord] file still saved at: {path}")

@dc.event
async def on_ready():
    print(f"[discord] logged in as {dc.user}")

def queue_upload(path, label, loop):
    if CHANNEL_ID and BOT_TOKEN != "YOUR_BOT_TOKEN_HERE":
        asyncio.run_coroutine_threadsafe(upload_queue.put((path, label)), loop)
    else:
        print(f"[discord] (not configured) would upload: {os.path.basename(path)}")

# ─────────────────────────────────────────────────────────────────────────────
# RECORDER
# ─────────────────────────────────────────────────────────────────────────────
def read_bin():
    try:
        with open(BIN_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return None

def recorder_thread(loop):
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"[recorder] watching: {BIN_FILE}")
    print(f"[recorder] saving to: {OUTPUT_DIR}")
    print(f"[recorder] mode: QUICK PLAY (use /batch in room to switch)")

    # ── state ─────────────────────────────────────────────────────────────
    last_chunk   = -1         # last chunk index processed
    game_file    = None       # current quick-play file handle
    batch_file   = None       # current batch file handle
    batch_path   = None       # path to the open batch file
    batch_count  = 0          # how many games in the current batch
    in_batch     = False      # True while a batch session is open
    in_game      = False      # True while a game is being recorded
    saw_batch_end = False      # True after processing batch_end sentinel

    def close_game_file():
        nonlocal game_file
        if game_file:
            game_file.close()
            game_file = None

    def close_batch(path):
        nonlocal batch_file, batch_path, batch_count, in_batch
        if batch_file:
            batch_file.close()
            batch_file = None
        batch_path  = None
        batch_count = 0
        in_batch    = False

    def write_line(obj, fh):
        fh.write(json.dumps(obj) + "\n")
        fh.flush()

    while True:
        try:
            data = read_bin()
            if not data:
                time.sleep(0.1); continue

            # ── batch_end sentinel (from /endbatch button in room) ─────
            if data.get("batch_end") and not saw_batch_end:
                saw_batch_end = True
                close_game_file()
                if batch_file:
                    batch_file.close(); batch_file = None
                if batch_path and batch_count > 0:
                    print(f"[recorder] batch ended ({batch_count} games) \u2192 {os.path.basename(batch_path)}")
                    print(f"[recorder] file saved at: {batch_path}")
                    queue_upload(batch_path, f"**[BATCH \u2014 {batch_count} games]** ", loop)
                close_batch(batch_path)
                in_game = False; last_chunk = -1
                print("[recorder] back to Quick Play mode")
                time.sleep(0.2); continue

            payload = data.get("payload")
            if not payload:
                time.sleep(0.1); continue

            chunk_idx = payload.get("chunk", -1)
            if chunk_idx == last_chunk:
                time.sleep(0.05); continue


            is_batch_mode = payload.get("batch_mode", False)

            # ── New game (chunk 0) ─────────────────────────────────────────
            if chunk_idx == 0:
                close_game_file()  # close any open quick-play file
                in_game    = True
                saw_batch_end = False
                last_chunk = 0

                session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
                p1 = sanitize(payload.get("player_name", "Player1"))
                p2 = sanitize(payload.get("enemy_name",  "Player2"))

                init_obj = {
                    "type":         "init",
                    "map":          payload.get("map", []),
                    "player_n":     payload.get("player_n"),
                    "enemy_n":      payload.get("enemy_n"),
                    "player_name":  payload.get("player_name", "Player 1"),
                    "enemy_name":   payload.get("enemy_name",  "Player 2"),
                    "player_color": payload.get("player_color", "00ff88"),
                    "enemy_color":  payload.get("enemy_color",  "ff4455"),
                    "version":      payload.get("version"),
                    "w":            payload.get("w"),
                    "h":            payload.get("h"),
                    "session":      session_id,
                }

                if is_batch_mode:
                    # ── BATCH MODE ─────────────────────────────────────────
                    if not in_batch:
                        # Start a new batch file
                        fname = f"BATCH_{p1}v{p2}_{session_id}.jsonl"
                        batch_path = os.path.join(OUTPUT_DIR, fname)
                        batch_file = open(batch_path, "w")
                        write_line({"type": "batch_header", "batch_id": session_id}, batch_file)
                        in_batch    = True
                        batch_count = 0
                        print(f"\n[recorder] BATCH started → {fname}")

                    batch_count += 1
                    divider = {
                        "type":         "game_divider",
                        "game_index":   batch_count,
                        "player_name":  payload.get("player_name", "Player 1"),
                        "enemy_name":   payload.get("enemy_name",  "Player 2"),
                        "player_color": payload.get("player_color", "00ff88"),
                        "enemy_color":  payload.get("enemy_color",  "ff4455"),
                        "timestamp":    session_id,
                    }
                    write_line(divider, batch_file)
                    write_line(init_obj, batch_file)
                    print(f"[recorder] batch game #{batch_count} started  ({p1} vs {p2})")

                else:
                    # ── QUICK PLAY MODE ────────────────────────────────────
                    # If a batch was open and we're now back to quick play, upload it
                    if in_batch:
                        if batch_file:
                            batch_file.close(); batch_file = None
                        if batch_path and batch_count > 0:
                            print(f"[recorder] batch auto-closed ({batch_count} games)")
                            queue_upload(batch_path, f"**[BATCH — {batch_count} games]** ", loop)
                        close_batch(batch_path)

                    fname    = f"{p1}v{p2}_{session_id}.jsonl"
                    qpath    = os.path.join(OUTPUT_DIR, fname)
                    game_file = open(qpath, "w")
                    write_line(init_obj, game_file)
                    print(f"\n[recorder] game started → {fname}")

            # ── Ongoing chunks ─────────────────────────────────────────────
            elif in_game:
                last_chunk = chunk_idx
                is_final   = payload.get("final", False)
                fh         = batch_file if in_batch else game_file  # in_batch stays True all game; is_batch_mode only True on chunk-0
                if not fh:
                    time.sleep(0.05); continue

                chunk_obj = {
                    "type":    "chunk",
                    "chunk":   chunk_idx,
                    "events":  payload.get("events", []),
                    "pos":     payload.get("pos",    []),
                    "final":   is_final,
                    "winner":  payload.get("winner") if is_final else None,
                }
                # Clean None values
                chunk_obj = {k:v for k,v in chunk_obj.items() if v is not None}
                if is_final and data.get("summary"):
                    chunk_obj["summary"] = data["summary"]

                write_line(chunk_obj, fh)

                if is_final:
                    last_chunk = -1   # reset so next game's chunk 0 is detected
                    in_game    = False

                    # Persist game result to room_stats.json
                    try:
                        w_uid  = payload.get('winner_uid')
                        warmup = payload.get('warmup', False)
                        record_result(
                            payload.get('player_n_uid', ''), payload.get('player_name', ''),
                            payload.get('enemy_n_uid',  ''), payload.get('enemy_name',  ''),
                            w_uid, warmup,
                        )
                    except Exception as ex:
                        print(f"[stats] error: {ex}")

                    if in_batch:
                        print(f"[recorder] batch game #{batch_count} complete")
                        # Don't upload yet — stay open for next game
                    else:
                        # Quick play — close and upload immediately
                        qpath = game_file.name
                        close_game_file()
                        fname = os.path.basename(qpath)
                        print(f"[recorder] saved → {fname}")
                        queue_upload(qpath, "New Galcon replay: ", loop)

            time.sleep(0.05)

        except KeyboardInterrupt:
            print("\n[recorder] stopping...")
            close_game_file()
            if in_batch and batch_file:
                batch_file.close()
                if batch_path and batch_count > 0:
                    print(f"[recorder] uploading open batch ({batch_count} games)...")
                    queue_upload(batch_path, f"**[BATCH — {batch_count} games]** ", loop)
            return
        except Exception as ex:
            print(f"[recorder] error: {ex}")
            time.sleep(0.5)

# ─────────────────────────────────────────────────────────────────────────────
# ENTRY POINT
# ─────────────────────────────────────────────────────────────────────────────
async def main():
    global upload_queue
    upload_queue = asyncio.Queue()
    loop = asyncio.get_event_loop()

    t = threading.Thread(target=recorder_thread, args=(loop,), daemon=True)
    t.start()

    if BOT_TOKEN == "YOUR_BOT_TOKEN_HERE" or CHANNEL_ID == 0:
        print("[discord] not configured — running recorder only")
        while t.is_alive():
            await asyncio.sleep(1)
    else:
        async with dc:
            dc.loop.create_task(uploader_loop())
            await dc.start(BOT_TOKEN)

if __name__ == "__main__":
    print("=" * 56)
    print("  GALCON 2 — RECORDER + DISCORD UPLOADER")
    print("  Quick Play: each game → separate file")
    print("  Batch REC:  all games → one file (toggle in room)")
    print("=" * 56)
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nStopped.")
