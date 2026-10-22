"""
Galcon 2 — Always-On Recorder + Discord Uploader + Replay Browser

Run once and leave it running. Automatically records every game.

QUICK PLAY (default): each game → separate .jsonl file → uploaded to Discord
BATCH MODE (toggle /batch in room): all games → one .jsonl → uploaded when toggled off

REPLAY BROWSER: the bot posts a pinned panel with three buttons
    📅 By date   👤 By player   🕐 All games
Each opens a private list (only the clicker sees it). Pick games, hit Export,
and the bot sends one batch .jsonl back privately for download. The list is
built from every replay in the channel (backfilled once on startup) plus
each new upload as it is posted.

Install: pip install discord.py
Token:   paste it into PASTE_TOKEN_HERE below (or set DISCORD_BOT_TOKEN)
Run:     python3 main.py
Stop:    Ctrl+C
"""

import json, os, re, time, asyncio, threading, math, gzip, shutil, sqlite3
from datetime import datetime
import discord

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────
BIN_FILE   = "/Users/phillipcall/Library/Application Support/Steam/userdata/1208075763/294160/remote/mod1.bin"
OUTPUT_DIR = "/Users/phillipcall/PycharmProjects/galconreplay/galcon_recordings"
PASTE_TOKEN_HERE = ""   # paste your bot token between the quotes — never commit/upload this file with it filled in
BOT_TOKEN  = (PASTE_TOKEN_HERE or os.environ.get("DISCORD_BOT_TOKEN", "")).strip()
CHANNEL_ID = 1515123696099000492   # replays channel: uploads go here, history is indexed from here

PANEL_CHANNEL_ID   = CHANNEL_ID   # where the Replay Browser panel is posted (can be a separate channel)
TIME_LABEL         = "ET"         # game times are shown in this Mac's local time
MAX_EXPORT_GAMES   = 0            # 0 = no cap; big exports are gzipped and split into several files
STICKY_PANEL       = True         # re-post the browser panel as the newest message after each upload
READ_OTHER_AUTHORS = False        # True = also index replays posted by people/other bots
                                  # (requires "Message Content Intent" ON in the Developer Portal)

DATA_DIR   = os.path.dirname(OUTPUT_DIR) or '.'
INDEX_DB   = os.path.join(DATA_DIR, 'replay_index.db')
CACHE_DIR  = os.path.join(DATA_DIR, 'replay_cache')     # attachments downloaded for exports
EXPORT_DIR = os.path.join(DATA_DIR, 'replay_exports')   # temporary export files

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
# REPLAY PARSING  (pure functions — no Discord, no database)
# ─────────────────────────────────────────────────────────────────────────────
def sanitize(name):
    return re.sub(r"[^\w]", "", str(name))[:20] or "Player"


def is_replay_attachment(filename):
    f = filename.lower()
    return f.endswith('.jsonl') or f.endswith('.jsonl.gz')


def decode_replay_bytes(filename, data):
    """Attachment/file bytes → text, transparently un-gzipping."""
    if filename.lower().endswith('.gz') or data[:2] == b'\x1f\x8b':
        data = gzip.decompress(data)
    return data.decode('utf-8', errors='replace')


def split_replay_text(text):
    """
    Split a replay file into games.
    Returns a list of {'meta': divider dict or {}, 'lines': [raw JSON lines]}.
    A quick-play file is one game whose lines start at its init record.
    A batch file yields one game per game_divider; the divider itself is the
    meta and is not repeated in 'lines'.
    """
    lines = [l for l in text.splitlines() if l.strip()]
    if not lines:
        return []
    try:
        first = json.loads(lines[0])
    except Exception:
        first = {}
    if not isinstance(first, dict) or first.get('type') != 'batch_header':
        return [{'meta': {}, 'lines': lines}]

    games, cur = [], None
    for line in lines[1:]:
        try:
            obj = json.loads(line)
        except Exception:
            continue
        t = obj.get('type') if isinstance(obj, dict) else None
        if t == 'game_divider':
            if cur is not None:
                games.append(cur)
            cur = {'meta': obj, 'lines': []}
        elif t != 'batch_header' and cur is not None:
            cur['lines'].append(line)
    if cur is not None:
        games.append(cur)
    return games


def _winner_from_summary(summary, p1, p2):
    """Port of the viewer's detectWinnerFromLines() summary fallback."""
    last = summary[-1] if summary else None
    if not isinstance(last, dict):
        return None
    ps, es = last.get('ps', 0) or 0, last.get('es', 0) or 0
    pp, ep = last.get('pp', 0) or 0, last.get('ep', 0) or 0
    p_score, e_score = ps + pp * 0.5, es + ep * 0.5
    if ps > 0 and es == 0:                         return p1
    if es > 0 and ps == 0:                         return p2
    if p_score > e_score * 1.35 and pp >= ep:      return p1
    if e_score > p_score * 1.35 and ep >= pp:      return p2
    if ps > es * 1.5:                              return p1
    if es > ps * 1.5:                              return p2
    return None


def parse_stamp(stamp):
    """Recorder session stamp 'YYYYMMDD_HHMMSS' → datetime, else None."""
    try:
        return datetime.strptime(str(stamp), "%Y%m%d_%H%M%S")
    except Exception:
        return None


def summarize_game(game):
    """
    One pass over a game's lines → the fields the browser lists.
    Winner: an explicit `winner` field (newest line wins), otherwise the
    viewer's summary heuristic, flagged as inferred.
    """
    meta = game.get('meta') or {}
    init, explicit_winner, winner_uid, last_summary, max_t = {}, None, None, None, 0.0
    for line in game['lines']:
        try:
            obj = json.loads(line)
        except Exception:
            continue
        if not isinstance(obj, dict):
            continue
        if not init and obj.get('type') == 'init':
            init = obj
        if obj.get('winner'):
            explicit_winner = obj['winner']
            winner_uid = obj.get('winner_uid') or winner_uid
        sm = obj.get('summary') or obj.get('sm')
        if isinstance(sm, list) and sm:
            last_summary = sm
            t = sm[-1].get('t') if isinstance(sm[-1], dict) else None
            if isinstance(t, (int, float)):
                max_t = max(max_t, float(t))
        for ev in obj.get('events') or []:
            t = ev.get('t') if isinstance(ev, dict) else None
            if isinstance(t, (int, float)):
                max_t = max(max_t, float(t))

    p1 = meta.get('player_name') or init.get('player_name') or 'Player 1'
    p2 = meta.get('enemy_name')  or init.get('enemy_name')  or 'Player 2'
    winner, inferred = explicit_winner, False
    if not winner and last_summary:
        winner = _winner_from_summary(last_summary, p1, p2)
        inferred = winner is not None
    return {
        'p1_name':  str(p1),
        'p2_name':  str(p2),
        'p1_uid':   str(meta.get('player_uid') or init.get('player_uid') or ''),
        'p2_uid':   str(meta.get('enemy_uid')  or init.get('enemy_uid')  or ''),
        'p1_color': str(meta.get('player_color') or init.get('player_color') or '00ff88'),
        'p2_color': str(meta.get('enemy_color')  or init.get('enemy_color')  or 'ff4455'),
        'stamp':    meta.get('timestamp') or init.get('session') or '',
        'winner':   str(winner) if winner else '',
        'winner_uid': str(winner_uid or ''),
        'winner_inferred': 1 if inferred else 0,
        'duration': max_t,
    }


def write_export_file(path, label, games):
    """
    games: list of (summary_dict, game_dict, source_filename) in output order.
    Writes a batch file the viewer opens like any other batch.
    """
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    with open(path, 'w') as f:
        f.write(json.dumps({"type": "batch_header", "batch_id": stamp,
                            "export": True, "label": label, "games": len(games)}) + "\n")
        for k, (s, g, src) in enumerate(games, 1):
            divider = dict(g.get('meta') or {})
            divider.update({
                "type": "game_divider", "game_index": k,
                "player_name": s['p1_name'], "enemy_name": s['p2_name'],
                "player_color": s['p1_color'], "enemy_color": s['p2_color'],
                "player_uid": s['p1_uid'], "enemy_uid": s['p2_uid'],
                "timestamp": s['stamp'], "source_file": src,
            })
            if s['winner'] and not s['winner_inferred']:
                divider["winner_name"] = s['winner']
            f.write(json.dumps(divider) + "\n")
            for line in g['lines']:
                f.write(line.rstrip('\n') + "\n")


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


def fit_for_discord(path, max_mb=None):
    """
    Return a list of files ready to send, each under the size limit:
    the file itself, else a gzip of it, else gzipped parts split at game
    boundaries. Never deletes `path`; every other returned file is new.
    """
    max_mb = max_mb or DISCORD_MAX_MB
    limit = max_mb * 1024 * 1024
    if os.path.getsize(path) <= limit:
        return [path]
    gz_path = path + '.gz'
    with open(path, 'rb') as fi, gzip.open(gz_path, 'wb') as fo:
        shutil.copyfileobj(fi, fo)
    if os.path.getsize(gz_path) <= limit:
        return [gz_path]
    os.remove(gz_path)
    out = []
    for part in split_batch_for_discord(path, max_compressed_bytes=int(limit * 0.9)):
        if part == path:          # single game too big to split — send it gzipped anyway
            with open(path, 'rb') as fi, gzip.open(gz_path, 'wb') as fo:
                shutil.copyfileobj(fi, fo)
            return [gz_path]
        with open(part, 'rb') as fi, gzip.open(part + '.gz', 'wb') as fo:
            shutil.copyfileobj(fi, fo)
        os.remove(part)
        out.append(part + '.gz')
    return out

# ─────────────────────────────────────────────────────────────────────────────
# REPLAY INDEX  (SQLite; only touched from the Discord event loop)
# ─────────────────────────────────────────────────────────────────────────────
_SCHEMA = """
CREATE TABLE IF NOT EXISTS games (
    id              INTEGER PRIMARY KEY,
    message_id      INTEGER NOT NULL,
    channel_id      INTEGER NOT NULL,
    attachment      TEXT    NOT NULL,
    game_index      INTEGER NOT NULL,
    started         TEXT    NOT NULL,   -- 'YYYY-MM-DD HH:MM:SS' local time
    day             TEXT    NOT NULL,   -- 'YYYY-MM-DD'
    p1_name TEXT, p2_name TEXT, p1_uid TEXT, p2_uid TEXT,
    p1_color TEXT, p2_color TEXT, stamp TEXT,
    winner TEXT, winner_uid TEXT, winner_inferred INTEGER,
    duration REAL,
    local_path TEXT,
    UNIQUE(message_id, attachment, game_index)
);
CREATE INDEX IF NOT EXISTS games_day     ON games(day);
CREATE INDEX IF NOT EXISTS games_started ON games(started);
CREATE TABLE IF NOT EXISTS scanned (message_id INTEGER PRIMARY KEY);
CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);
"""

_db = None

def db():
    global _db
    if _db is None:
        os.makedirs(DATA_DIR, exist_ok=True)
        _db = sqlite3.connect(INDEX_DB)
        _db.row_factory = sqlite3.Row
        _db.executescript(_SCHEMA)
    return _db


def meta_get(key):
    r = db().execute("SELECT value FROM meta WHERE key=?", (key,)).fetchone()
    return r[0] if r else None


def meta_set(key, value):
    db().execute("INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)", (key, str(value)))
    db().commit()


def mark_scanned(message_id):
    db().execute("INSERT OR IGNORE INTO scanned(message_id) VALUES(?)", (message_id,))
    db().commit()


def index_replay_text(message_id, channel_id, filename, text, local_path, fallback_dt):
    """Add every game in one attachment to the index. Returns games added."""
    added = 0
    for gi, game in enumerate(split_replay_text(text)):
        s = summarize_game(game)
        dt = parse_stamp(s['stamp']) or fallback_dt
        cur = db().execute(
            """INSERT OR IGNORE INTO games
               (message_id, channel_id, attachment, game_index, started, day,
                p1_name, p2_name, p1_uid, p2_uid, p1_color, p2_color, stamp,
                winner, winner_uid, winner_inferred, duration, local_path)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (message_id, channel_id, filename, gi,
             dt.strftime("%Y-%m-%d %H:%M:%S"), dt.strftime("%Y-%m-%d"),
             s['p1_name'], s['p2_name'], s['p1_uid'], s['p2_uid'],
             s['p1_color'], s['p2_color'], str(s['stamp']),
             s['winner'], s['winner_uid'], s['winner_inferred'], s['duration'],
             local_path))
        added += cur.rowcount
    db().commit()
    return added


def fetch_games(ids):
    if not ids:
        return {}
    q = "SELECT * FROM games WHERE id IN (%s)" % ",".join("?" * len(ids))
    return {r['id']: r for r in db().execute(q, list(ids))}


def ids_where(clause="1=1", params=()):
    q = f"SELECT id FROM games WHERE {clause} ORDER BY started DESC, id DESC"
    return [r[0] for r in db().execute(q, params)]


def player_uids(name):
    """Every UID a lobby name has been recorded with."""
    n = name.strip().lower()
    return {r[0] for r in db().execute(
        "SELECT p1_uid FROM games WHERE lower(p1_name)=? AND p1_uid!='' "
        "UNION SELECT p2_uid FROM games WHERE lower(p2_name)=? AND p2_uid!=''", (n, n))}


def player_clause(name):
    """
    SQL matching games a player was in: exact (case-insensitive) name, widened
    to every UID that name has used — so renames/alias spellings are found too.
    """
    n = name.strip().lower()
    uids = player_uids(name)
    clause = "lower(p1_name)=? OR lower(p2_name)=?"
    params = [n, n]
    if uids:
        marks = ",".join("?" * len(uids))
        clause += f" OR p1_uid IN ({marks}) OR p2_uid IN ({marks})"
        params += list(uids) + list(uids)
    return f"({clause})", params


def find_player_ids(name):
    return ids_where(*player_clause(name))


def find_h2h_ids(name_a, name_b):
    """Only games between these two players."""
    ca, pa = player_clause(name_a)
    cb, pb = player_clause(name_b)
    return ids_where(f"{ca} AND {cb}", pa + pb)


def opponents_of(name, ids, limit=24):
    """[(opponent name, games)] for a player's games, most-played first."""
    n, uids = name.strip().lower(), player_uids(name)
    counts, shown = {}, {}
    for r in fetch_games(ids).values():
        p1_is_me = r['p1_name'].lower() == n or (r['p1_uid'] and r['p1_uid'] in uids)
        opp = r['p2_name'] if p1_is_me else r['p1_name']
        key = opp.lower()
        counts[key] = counts.get(key, 0) + 1
        shown.setdefault(key, opp)
    top = sorted(counts.items(), key=lambda kv: -kv[1])[:limit]
    return [(shown[k], c) for k, c in top]


def similar_names(name, limit=25):
    like = f"%{name.strip().lower()}%"
    rows = db().execute(
        "SELECT name, COUNT(*) AS n FROM ("
        " SELECT p1_name AS name FROM games WHERE lower(p1_name) LIKE ?"
        " UNION ALL SELECT p2_name FROM games WHERE lower(p2_name) LIKE ?)"
        " GROUP BY lower(name) ORDER BY n DESC LIMIT ?", (like, like, limit))
    return [(r['name'], r['n']) for r in rows]

# ─────────────────────────────────────────────────────────────────────────────
# DISCORD
# ─────────────────────────────────────────────────────────────────────────────
intents = discord.Intents.default()
if READ_OTHER_AUTHORS:
    intents.message_content = True
dc = discord.Client(intents=intents)
tree = discord.app_commands.CommandTree(dc)
upload_queue: asyncio.Queue = None
BACKFILL_STATE = "not started"
_started = False


def cache_path(message_id, filename):
    return os.path.join(CACHE_DIR, f"{message_id}_{filename}")


async def get_channel(cid):
    return dc.get_channel(cid) or await dc.fetch_channel(cid)


async def send_and_index(ch, content, send_path, index_text, local_path):
    """Post one replay file, then index the games it contains."""
    fname = os.path.basename(send_path)
    msg = await ch.send(content=content, file=discord.File(send_path, filename=fname))
    try:
        if local_path is None:   # file is temporary — keep a copy so exports don't re-download it
            os.makedirs(CACHE_DIR, exist_ok=True)
            shutil.copyfile(send_path, cache_path(msg.id, fname))
        n = index_replay_text(msg.id, ch.id, fname, index_text, local_path,
                              msg.created_at.astimezone().replace(tzinfo=None))
        mark_scanned(msg.id)
        print(f"[index] +{n} game(s) from {fname}")
    except Exception as ex:
        print(f"[index] error indexing {fname}: {ex}")
    return msg


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
                with open(path) as f:
                    text = f.read()
                msg = "🎮 " + label + "`" + fname + "`"
                await send_and_index(ch, msg, path, text, path)
                print(f"[discord] uploaded: {fname}  ({size_mb:.1f} MB)")

            else:
                # File too large — split into parts at game boundaries, gzip each.
                # The original replay is never deleted; only the temporary parts are.
                print(f"[discord] {size_mb:.0f} MB — splitting into parts for upload")
                try:
                    parts = split_batch_for_discord(path)
                    n = len(parts)
                    for i, part_path in enumerate(parts):
                        gz_path = part_path + '.gz'
                        try:
                            with open(part_path) as f:
                                text = f.read()
                            with open(part_path, 'rb') as fi, gzip.open(gz_path, 'wb') as fo:
                                shutil.copyfileobj(fi, fo)
                            gz_mb  = os.path.getsize(gz_path) / 1024 / 1024
                            gz_fn  = os.path.basename(gz_path)
                            part_lbl = label + "[Part " + str(i+1) + "/" + str(n) + "] "
                            part_msg = "🎮 " + part_lbl + "`" + gz_fn + "` (" + f"{gz_mb:.1f}" + " MB compressed)"
                            await send_and_index(ch, part_msg, gz_path, text, None)
                            print(f"[discord] uploaded part {i+1}/{n}: {gz_fn}  ({gz_mb:.1f} MB)")
                        finally:
                            if part_path != path and os.path.exists(part_path):
                                os.remove(part_path)
                            if os.path.exists(gz_path):
                                os.remove(gz_path)
                except Exception as split_err:
                    print(f"[discord] split failed: {split_err} — file at: {path}")
                    msg = "🎮 " + label + "`" + fname + "` — too large (" + f"{size_mb:.0f}" + " MB). File saved at:\n" + path
                    await ch.send(content=msg)

            # keep the browser panel at the bottom of the channel
            if STICKY_PANEL and PANEL_CHANNEL_ID == CHANNEL_ID and upload_queue.empty():
                try:
                    await refresh_panel()
                except Exception as ex:
                    print(f"[browser] panel refresh failed: {ex}")

        except Exception as ex:
            print(f"[discord] upload error: {ex}")
            print(f"[discord] file still saved at: {path}")


async def backfill(ch):
    """Index every replay already in the channel (once; resumable)."""
    global BACKFILL_STATE
    BACKFILL_STATE = "running"
    scanned = {r[0] for r in db().execute("SELECT message_id FROM scanned")}
    seen = added = 0
    try:
        async for msg in ch.history(limit=None, oldest_first=True):
            if msg.id in scanned:
                continue
            if msg.author.id != dc.user.id and not READ_OTHER_AUTHORS:
                continue
            for att in msg.attachments:
                if not is_replay_attachment(att.filename):
                    continue
                try:
                    local = os.path.join(OUTPUT_DIR, att.filename)
                    if os.path.exists(local):
                        with open(local, 'rb') as f:
                            data = f.read()
                    else:
                        local = None
                        data = await att.read()
                    text = decode_replay_bytes(att.filename, data)
                    added += index_replay_text(msg.id, ch.id, att.filename, text, local,
                                               msg.created_at.astimezone().replace(tzinfo=None))
                except Exception as ex:
                    print(f"[backfill] skipped {att.filename}: {ex}")
            mark_scanned(msg.id)
            seen += 1
            if seen % 25 == 0:
                print(f"[backfill] {seen} messages scanned, {added} games added")
        BACKFILL_STATE = "done"
        print(f"[backfill] done — {seen} new messages, {added} games added")
    except Exception as ex:
        BACKFILL_STATE = f"failed ({ex})"
        print(f"[backfill] error: {ex}")


async def load_source_text(row):
    """Full text of the file a game lives in: local copy, cache, else Discord."""
    for p in (row['local_path'], cache_path(row['message_id'], row['attachment'])):
        if p and os.path.exists(p):
            with open(p, 'rb') as f:
                return decode_replay_bytes(p, f.read())
    ch = await get_channel(row['channel_id'])
    msg = await ch.fetch_message(row['message_id'])
    for att in msg.attachments:
        if att.filename == row['attachment']:
            data = await att.read()
            os.makedirs(CACHE_DIR, exist_ok=True)
            with open(cache_path(row['message_id'], row['attachment']), 'wb') as f:
                f.write(data)
            return decode_replay_bytes(att.filename, data)
    raise FileNotFoundError(row['attachment'])


async def build_export(ids, label):
    """Selected game ids → list of files to send (each under the size limit)."""
    if MAX_EXPORT_GAMES and len(ids) > MAX_EXPORT_GAMES:
        raise ValueError(f"{len(ids)} games selected — the limit is {MAX_EXPORT_GAMES} per export.")
    rows = sorted(fetch_games(ids).values(), key=lambda r: (r['started'], r['id']))  # oldest first
    sources = {}
    games = []
    for r in rows:
        key = (r['message_id'], r['attachment'])
        if key not in sources:
            sources[key] = split_replay_text(await load_source_text(r))
        split = sources[key]
        if r['game_index'] >= len(split):
            continue
        g = split[r['game_index']]
        s = {k: r[k] for k in ('p1_name', 'p2_name', 'p1_uid', 'p2_uid', 'p1_color',
                               'p2_color', 'stamp', 'winner', 'winner_inferred')}
        games.append((s, g, r['attachment']))
    if not games:
        raise ValueError("None of the selected games could be loaded.")

    os.makedirs(EXPORT_DIR, exist_ok=True)
    slug = re.sub(r"[^\w-]", "", label.replace(" ", "-"))[:40] or "games"
    path = os.path.join(EXPORT_DIR, f"EXPORT_{slug}_{len(games)}games_"
                                    f"{datetime.now().strftime('%Y%m%d_%H%M%S')}.jsonl")

    def work():
        write_export_file(path, label, games)
        return fit_for_discord(path)

    files = await asyncio.to_thread(work)
    return path, files, len(games)

# ── Browser UI ───────────────────────────────────────────────────────────────
def fmt_time(started):
    return datetime.strptime(started, "%Y-%m-%d %H:%M:%S").strftime("%b %d %H:%M")


def fmt_day(day):
    return datetime.strptime(day, "%Y-%m-%d").strftime("%a %b %d, %Y")


def fmt_dur(sec):
    if not sec:
        return ""
    m, s = divmod(int(sec), 60)
    return f"{m}m {s:02d}s"


def game_option(r, selected):
    label = f"{fmt_time(r['started'])} · {r['p1_name']} vs {r['p2_name']}"
    if r['winner']:
        desc = f"{r['winner']} won" + (" (est.)" if r['winner_inferred'] else "")
    else:
        desc = "winner unknown"
    if r['duration']:
        desc += f" · {fmt_dur(r['duration'])}"
    return discord.SelectOption(label=label[:100], description=desc[:100],
                                value=str(r['id']), default=selected)


class GameListView(discord.ui.View):
    """
    A private, paged list of games with selection and export.
    If `player` is set, an opponent dropdown narrows the list to one matchup.
    """
    PAGE = 25

    def __init__(self, title, ids, player=None, opponent=None):
        super().__init__(timeout=900)
        self.title, self.ids, self.page, self.selected = title, ids, 0, set()
        self.player, self.opponent = player, opponent
        self.opponents = opponents_of(player, find_player_ids(player)) if player else []
        self.rebuild()

    def page_ids(self):
        return self.ids[self.page * self.PAGE:(self.page + 1) * self.PAGE]

    def n_pages(self):
        return max(1, math.ceil(len(self.ids) / self.PAGE))

    def content(self):
        return (f"**{self.title}** — {len(self.ids)} game(s) · page {self.page + 1}/{self.n_pages()}"
                f" · {len(self.selected)} selected\n"
                f"-# Newest first. Times are {TIME_LABEL}. \"(est.)\" = winner inferred from the end state.")

    async def redraw(self, interaction):
        self.rebuild()
        await interaction.response.edit_message(content=self.content(), view=self)

    def set_opponent(self, opponent):
        self.opponent = opponent
        if opponent:
            self.ids = find_h2h_ids(self.player, opponent)
            self.title = f"{self.player} vs {opponent}"
        else:
            self.ids = find_player_ids(self.player)
            self.title = f"Games with {self.player}"
        self.page, self.selected = 0, set()

    def rebuild(self):
        self.clear_items()

        # row 0 — the games on this page
        rows = fetch_games(self.page_ids())
        opts = [game_option(rows[i], i in self.selected) for i in self.page_ids() if i in rows]
        if opts:
            sel = discord.ui.Select(placeholder="Select games to export…", min_values=0,
                                    max_values=len(opts), options=opts, row=0)

            async def on_select(interaction, sel=sel):
                page = set(self.page_ids())
                self.selected = (self.selected - page) | {int(v) for v in sel.values}
                await self.redraw(interaction)
            sel.callback = on_select
            self.add_item(sel)

        # row 1 — opponent filter (player lists only)
        if self.player and self.opponents:
            o_opts = [discord.SelectOption(label="All opponents", value="__all__",
                                           default=self.opponent is None)]
            o_opts += [discord.SelectOption(label=f"vs {n}"[:100], description=f"{c} game(s)",
                                            value=n[:100],
                                            default=bool(self.opponent) and n.lower() == self.opponent.lower())
                       for n, c in self.opponents]
            osel = discord.ui.Select(placeholder="Filter by opponent…", options=o_opts, row=1)

            async def on_opp(interaction, osel=osel):
                v = osel.values[0]
                self.set_opponent(None if v == "__all__" else v)
                await self.redraw(interaction)
            osel.callback = on_opp
            self.add_item(osel)

        # row 2 — paging and select all
        prev = discord.ui.Button(label="◀ Prev", disabled=self.page == 0, row=2)
        nxt  = discord.ui.Button(label="Next ▶", disabled=self.page >= self.n_pages() - 1, row=2)
        all_on = bool(self.ids) and len(self.selected) == len(self.ids)
        sel_all = discord.ui.Button(label="Clear selection" if all_on else f"Select all ({len(self.ids)})",
                                    disabled=not self.ids, row=2)

        # row 3 — export
        exp_sel = discord.ui.Button(label=f"Export selected ({len(self.selected)})",
                                    style=discord.ButtonStyle.primary,
                                    disabled=not self.selected, row=3)
        exp_all = discord.ui.Button(label=f"Export all ({len(self.ids)})",
                                    style=discord.ButtonStyle.success,
                                    disabled=not self.ids, row=3)

        async def on_prev(interaction):
            self.page -= 1; await self.redraw(interaction)

        async def on_next(interaction):
            self.page += 1; await self.redraw(interaction)

        async def on_sel_all(interaction):
            self.selected = set() if len(self.selected) == len(self.ids) else set(self.ids)
            await self.redraw(interaction)

        async def on_exp_sel(interaction):
            await export_to_user(interaction, [i for i in self.ids if i in self.selected], self.title)

        async def on_exp_all(interaction):
            await export_to_user(interaction, list(self.ids), self.title)

        prev.callback, nxt.callback, sel_all.callback = on_prev, on_next, on_sel_all
        exp_sel.callback, exp_all.callback = on_exp_sel, on_exp_all
        for b in (prev, nxt, sel_all, exp_sel, exp_all):
            self.add_item(b)


async def export_to_user(interaction, ids, label):
    await interaction.response.defer(ephemeral=True, thinking=True)
    path = None
    try:
        path, files, n = await build_export(ids, label)
        note = (f"**{n} game(s)**" + (f" in {len(files)} files" if len(files) > 1 else "") +
                " — download now (private messages vanish when Discord reloads), "
                "then open in Replay Viewer Pro.")
        if any(f.endswith('.gz') for f in files):
            note += "\n-# Compressed to fit Discord's size limit: double-click each .gz to unzip it first."
        for i in range(0, len(files), 10):       # Discord allows 10 attachments per message
            await interaction.followup.send(
                content=note if i == 0 else None, ephemeral=True,
                files=[discord.File(p, filename=os.path.basename(p)) for p in files[i:i + 10]])
        print(f"[export] {interaction.user} exported {n} game(s) in {len(files)} file(s): {label}")
    except Exception as ex:
        print(f"[export] failed: {ex}")
        await interaction.followup.send(f"Export failed: {ex}", ephemeral=True)
    finally:
        try:
            for p in os.listdir(EXPORT_DIR):
                if path and p.startswith(os.path.basename(path)[:-len('.jsonl')]):
                    os.remove(os.path.join(EXPORT_DIR, p))
        except Exception:
            pass


def empty_index_text():
    if BACKFILL_STATE == "running":
        return "Still indexing the channel's replay history — try again in a minute."
    return "No games are indexed yet."


class DayPickView(discord.ui.View):
    PAGE = 25

    def __init__(self, page=0):
        super().__init__(timeout=900)
        self.page = page
        self.days = [(r[0], r[1]) for r in db().execute(
            "SELECT day, COUNT(*) FROM games GROUP BY day ORDER BY day DESC")]
        self.rebuild()

    def rebuild(self):
        self.clear_items()
        chunk = self.days[self.page * self.PAGE:(self.page + 1) * self.PAGE]
        if chunk:
            sel = discord.ui.Select(placeholder="Pick a day…", row=0, options=[
                discord.SelectOption(label=fmt_day(d), description=f"{n} game(s)", value=d)
                for d, n in chunk])

            async def on_pick(interaction, sel=sel):
                day = sel.values[0]
                view = GameListView(fmt_day(day), ids_where("day=?", (day,)))
                await interaction.response.edit_message(content=view.content(), view=view)
            sel.callback = on_pick
            self.add_item(sel)
        if len(self.days) > self.PAGE:
            newer = discord.ui.Button(label="◀ Newer days", disabled=self.page == 0, row=1)
            older = discord.ui.Button(label="Older days ▶", row=1,
                                      disabled=(self.page + 1) * self.PAGE >= len(self.days))

            async def on_newer(interaction):
                self.page -= 1; self.rebuild()
                await interaction.response.edit_message(view=self)

            async def on_older(interaction):
                self.page += 1; self.rebuild()
                await interaction.response.edit_message(view=self)
            newer.callback, older.callback = on_newer, on_older
            self.add_item(newer); self.add_item(older)


async def reply(interaction, text, view=None, edit=False):
    if edit:
        await interaction.response.edit_message(content=text, view=view)
    elif view is not None:
        await interaction.response.send_message(text, view=view, ephemeral=True)
    else:
        await interaction.response.send_message(text, ephemeral=True)


async def show_player(interaction, name, opponent=None, edit=False):
    """One player's games, or only their games against `opponent`."""
    missing = [n for n in (name, opponent) if n and not find_player_ids(n)]
    if missing:
        bad = missing[0]
        names = similar_names(bad)
        if names and not opponent:
            await reply(interaction, f"No player named **{bad}** exactly. Did you mean:",
                        NamePickView(names), edit)
        elif names:
            hint = ", ".join(n for n, _ in names[:8])
            await reply(interaction, f"No player named **{bad}** exactly. Close matches: {hint}", None, edit)
        else:
            extra = "" if BACKFILL_STATE == "done" else " " + empty_index_text()
            await reply(interaction, f"No games found for **{bad}**.{extra}", None, edit)
        return
    view = GameListView(f"Games with {name}", find_player_ids(name), player=name)
    if opponent:
        view.set_opponent(opponent)
        view.rebuild()
        if not view.ids:
            await reply(interaction, f"**{name}** and **{opponent}** have no recorded games together.",
                        None, edit)
            return
    await reply(interaction, view.content(), view, edit)


class NamePickView(discord.ui.View):
    def __init__(self, names):
        super().__init__(timeout=900)
        sel = discord.ui.Select(placeholder="Pick a player…", options=[
            discord.SelectOption(label=n[:100], description=f"{c} game(s)", value=n[:100])
            for n, c in names])

        async def on_pick(interaction):
            await show_player(interaction, sel.values[0], edit=True)
        sel.callback = on_pick
        self.add_item(sel)


class PlayerModal(discord.ui.Modal, title="Find games by player"):
    name = discord.ui.TextInput(label="Lobby username", placeholder="the name used in the Galcon lobby",
                                max_length=40)
    opponent = discord.ui.TextInput(label="Opponent (optional — only games between the two)",
                                    placeholder="leave empty for all of their games",
                                    max_length=40, required=False)

    async def on_submit(self, interaction):
        opp = str(self.opponent.value or "").strip() or None
        await show_player(interaction, str(self.name.value).strip(), opp)


class PanelView(discord.ui.View):
    """The browser panel. Persistent: buttons keep working across restarts."""
    def __init__(self):
        super().__init__(timeout=None)

    @discord.ui.button(label="📅 By date", style=discord.ButtonStyle.primary, custom_id="rb:date")
    async def by_date(self, interaction, button):
        view = DayPickView()
        if not view.days:
            await interaction.response.send_message(empty_index_text(), ephemeral=True); return
        await interaction.response.send_message("Pick a day:", view=view, ephemeral=True)

    @discord.ui.button(label="👤 By player", style=discord.ButtonStyle.primary, custom_id="rb:player")
    async def by_player(self, interaction, button):
        await interaction.response.send_modal(PlayerModal())

    @discord.ui.button(label="🕐 All games", style=discord.ButtonStyle.secondary, custom_id="rb:all")
    async def all_games(self, interaction, button):
        ids = ids_where()
        if not ids:
            await interaction.response.send_message(empty_index_text(), ephemeral=True); return
        view = GameListView("All games", ids)
        await interaction.response.send_message(view.content(), view=view, ephemeral=True)


def panel_embed():
    return discord.Embed(
        title="🎮 Replay Browser",
        description=("Find and download replays from this channel.\n\n"
                     "**📅 By date** — every game played on a day\n"
                     "**👤 By player** — a player's games, or only two players' games against each other\n"
                     "**🕐 All games** — everything, newest first\n\n"
                     "Lists are private to you. Select games (or Select all) and Export — the bot sends "
                     "you a batch file to open in Replay Viewer Pro.\n"
                     "-# Lost this message? Type **/replays** anywhere in the server."),
        color=0x00ff88)


_panel_lock = asyncio.Lock()


async def refresh_panel(force_new=False):
    """
    Make sure the panel exists. With STICKY_PANEL, it is re-posted so it is
    always the newest message in its channel (the old copy is deleted).
    """
    async with _panel_lock:
        ch = await get_channel(PANEL_CHANNEL_ID)
        mid, cid = meta_get('panel_message_id'), meta_get('panel_channel_id')
        old = None
        if mid and cid and int(cid) == ch.id:
            try:
                old = await ch.fetch_message(int(mid))
            except discord.NotFound:
                old = None
        if old and not force_new:
            if not STICKY_PANEL or ch.last_message_id == old.id:
                return
        if old:
            try:
                await old.delete()
            except discord.HTTPException:
                pass
        msg = await ch.send(embed=panel_embed(), view=PanelView())
        meta_set('panel_message_id', msg.id)
        meta_set('panel_channel_id', ch.id)
        if not STICKY_PANEL:
            try:
                await msg.pin()
            except discord.Forbidden:
                print("[browser] posted panel but couldn't pin it (bot needs Manage Messages) — pin it by hand")
        print(f"[browser] panel posted in #{ch.name}")


@tree.command(name="replays", description="Open the replay browser (only you see it)")
async def replays_command(interaction: discord.Interaction):
    await interaction.response.send_message(embed=panel_embed(), view=PanelView(), ephemeral=True)


@dc.event
async def on_ready():
    global _started
    print(f"[discord] logged in as {dc.user}")
    if _started:
        return        # reconnect — everything is already running
    _started = True
    dc.add_view(PanelView())
    try:
        ch = await get_channel(PANEL_CHANNEL_ID)
        tree.copy_global_to(guild=ch.guild)        # guild sync shows /replays immediately
        await tree.sync(guild=ch.guild)
        print("[browser] /replays command ready")
    except Exception as ex:
        print(f"[browser] couldn't register /replays: {ex}")
    try:
        await refresh_panel()
    except Exception as ex:
        print(f"[browser] panel error: {ex}")
    try:
        dc.loop.create_task(backfill(await get_channel(CHANNEL_ID)))
    except Exception as ex:
        print(f"[backfill] could not start: {ex}")

def queue_upload(path, label, loop):
    if CHANNEL_ID and BOT_TOKEN:
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
    cur_players  = {}         # identities from chunk 0, used for the final result

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
                    print(f"[recorder] batch ended ({batch_count} games) → {os.path.basename(batch_path)}")
                    print(f"[recorder] file saved at: {batch_path}")
                    queue_upload(batch_path, f"**[BATCH — {batch_count} games]** ", loop)
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
                cur_players = {
                    "p1_uid":  str(payload.get("player_uid") or ""),
                    "p2_uid":  str(payload.get("enemy_uid")  or ""),
                    "p1_name": payload.get("player_name", ""),
                    "p2_name": payload.get("enemy_name",  ""),
                }

                init_obj = {
                    "type":         "init",
                    "map":          payload.get("map", []),
                    "player_n":     payload.get("player_n"),
                    "enemy_n":      payload.get("enemy_n"),
                    "player_name":  payload.get("player_name", "Player 1"),
                    "enemy_name":   payload.get("enemy_name",  "Player 2"),
                    "player_uid":   cur_players["p1_uid"],
                    "enemy_uid":    cur_players["p2_uid"],
                    "player_color": payload.get("player_color", "00ff88"),
                    "enemy_color":  payload.get("enemy_color",  "ff4455"),
                    "version":      payload.get("version"),
                    "w":            payload.get("w"),
                    "h":            payload.get("h"),
                    "session":      session_id,
                }
                # Room settings the mod sends (map style, mode, ranked) — keep them.
                for k in ("style", "style_ver", "distance_change", "game_mode", "ranked"):
                    if k in payload:
                        init_obj[k] = payload[k]

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
                        "player_uid":   cur_players["p1_uid"],
                        "enemy_uid":    cur_players["p2_uid"],
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

                # The room writes the winner's name at the top level of g2.data
                # and the uid inside the final payload.
                winner_name = (data.get("winner") or payload.get("winner_name")) if is_final else None
                winner_uid  = payload.get("winner_uid") if is_final else None
                chunk_obj = {
                    "type":       "chunk",
                    "chunk":      chunk_idx,
                    "events":     payload.get("events", []),
                    "pos":        payload.get("pos",    []),
                    "final":      is_final,
                    "winner":     winner_name,
                    "winner_uid": str(winner_uid) if winner_uid else None,
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
                        warmup = payload.get('warmup', False)
                        record_result(
                            cur_players.get('p1_uid', ''), cur_players.get('p1_name', ''),
                            cur_players.get('p2_uid', ''), cur_players.get('p2_name', ''),
                            str(winner_uid) if winner_uid else None, warmup,
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

    if not BOT_TOKEN or CHANNEL_ID == 0:
        print("[discord] no bot token (PASTE_TOKEN_HERE is empty) — running recorder only (no uploads, no browser)")
        while t.is_alive():
            await asyncio.sleep(1)
    else:
        async with dc:
            dc.loop.create_task(uploader_loop())
            await dc.start(BOT_TOKEN)

if __name__ == "__main__":
    print("=" * 56)
    print("  GALCON 2 — RECORDER + DISCORD UPLOADER + BROWSER")
    print("  Quick Play: each game → separate file")
    print("  Batch REC:  all games → one file (toggle in room)")
    print("  Browser:    pinned panel in the replays channel")
    print("=" * 56)
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nStopped.")
