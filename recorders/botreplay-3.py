"""
Galcon 2 -- Bot Room Recorder (continuous, unattended)

Adapted from the PvP recorder (galcon.py). Same proven chunk-accumulation
logic, but built for the bot room's actual usage pattern: games start and
end back-to-back forever with nobody clicking "Save and Quit", so this
never stops on its own and never opens the matplotlib replay viewer
(that's a blocking GUI -- fine for reviewing one PvP match, wrong for an
unattended farm producing dozens of games in a row).

Run this, then start the bot room. Leave it running. Ctrl+C to stop.
Each completed game gets its own .jsonl file in OUTPUT_DIR, in the exact
same format the PvP recorder produces -- so both your HTML viewer and
galcon.py's own replay mode can open any of these files unmodified,
e.g.:  python galcon.py galcon_recordings/botroom/botgame_20260730_120501.jsonl
"""

import json, os, time
from datetime import datetime

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG
# ─────────────────────────────────────────────────────────────────────────────
# NOTE: filename mapping is by mod SLOT, not by mod filename -- confirmed
# by inspection on 2026-07-19 that mod_botroom.lua's g2.data actually lands
# in mod2.bin, not mod_botroom.bin. If you reinstall/reorder mods this may
# shift -- if this recorder silently never sees a new game, check
# `ls -la` on the remote folder for whichever .bin file's mtime is moving.
BIN_FILE = ("/Users/phillipcall/Library/Application Support/Steam/userdata/"
            "1208075763/294160/remote/mod2.bin")
OUTPUT_DIR = "galcon_recordings/botroom"

POLL_INTERVAL = 0.05  # seconds between checks -- bot room flushes roughly
                       # once/second, so this leaves comfortable margin


def read_bin():
    try:
        with open(BIN_FILE, "r") as f:
            return json.load(f)
    except Exception:
        return None


def record_one_game(last_chunk):
    """
    Watches for one game's worth of chunks, starting from whatever chunk
    index is currently in the file. Returns (session_file, last_chunk,
    winner, duration) once a final chunk is written, or (None, last_chunk,
    None, None) if interrupted before completion.
    """
    session_file = None
    game_started = False
    winner = None
    duration = None

    while True:
        data = read_bin()
        if data is None:
            time.sleep(POLL_INTERVAL)
            continue

        payload = data.get("payload")
        if payload is None:
            time.sleep(POLL_INTERVAL)
            continue

        chunk_index = payload.get("chunk", -1)

        if chunk_index == last_chunk:
            time.sleep(POLL_INTERVAL)
            continue

        last_chunk = chunk_index

        if chunk_index == 0:
            game_started = True
            session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
            session_file = os.path.join(
                OUTPUT_DIR, f"botgame_{session_id}.jsonl")
            with open(session_file, "w") as f:
                json.dump({
                    "type":     "init",
                    "map":      payload.get("map", []),
                    "player_n": payload.get("player_n"),
                    "enemy_n":  payload.get("enemy_n"),
                    "version":  payload.get("version"),
                    "w":        payload.get("w"),
                    "h":        payload.get("h"),
                    "session":  session_id,
                    "player_name": payload.get("player_name"),
                    "enemy_name":  payload.get("enemy_name"),
                }, f)
                f.write("\n")
            print(f"  [NEW GAME] {len(payload.get('map', []))} planets"
                  f"  {payload.get('player_name','?')} vs "
                  f"{payload.get('enemy_name','?')}  (session {session_id})")

        elif game_started and session_file:
            events = payload.get("events", [])
            pos    = payload.get("pos", [])
            final  = payload.get("final", False)

            with open(session_file, "a") as f:
                rec = {
                    "type":   "chunk",
                    "chunk":  chunk_index,
                    "events": events,
                    "pos":    pos,
                    "final":  final,
                }
                if final:
                    raw = read_bin()
                    if raw and raw.get("summary"):
                        rec["summary"] = raw["summary"]
                    winner = raw.get("winner") if raw else None
                    if raw and raw.get("summary"):
                        last_t = raw["summary"][-1].get("t")
                        duration = last_t
                json.dump(rec, f)
                f.write("\n")

            if final:
                return session_file, last_chunk, winner, duration

        time.sleep(POLL_INTERVAL)


def run():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 60)
    print("  GALCON 2 -- BOT ROOM RECORDER (continuous)")
    print("=" * 60)
    print(f"  Watching : {BIN_FILE}")
    print(f"  Output   : {OUTPUT_DIR}/")
    print(f"  This runs forever, recording every game the bot room")
    print(f"  plays back-to-back. Ctrl+C to stop.")
    print("=" * 60)

    last_chunk = -999  # sentinel guaranteeing the first read is treated as new
    games_recorded = 0

    while True:
        try:
            session_file, last_chunk, winner, duration = record_one_game(last_chunk)
            if session_file:
                games_recorded += 1
                dur_str = f"{duration:.1f}s" if duration is not None else "?"
                print(f"  [DONE] game #{games_recorded}  winner={winner}  "
                      f"duration={dur_str}  -> {session_file}")
        except KeyboardInterrupt:
            print(f"\n  Stopped. Recorded {games_recorded} game(s) this session.")
            return
        except Exception as ex:
            print(f"  [error] {ex}  (continuing...)")
            time.sleep(0.5)


if __name__ == "__main__":
    run()
