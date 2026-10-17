# Galcon Replay Engine

A Galcon 2 replay workflow spanning the mod room, local recording, Discord sharing, replay playback, and move analysis. The main room/recorder pair is designed to turn a completed match into a saved replay and queue it for Discord automatically, without a manual export step.

```text
Galcon mod room
    -> g2.data / Steam mod-slot save
    -> Python recorder
    -> local JSONL replay
    -> Discord upload
    -> replay viewer / move review / analysis
```

The source has been organized by role, not rewritten. Existing filenames, configuration values, and source contents are preserved in this reorganization. Numbered filename suffixes do not establish version order or Steam mod-slot assignments.

## Repository layout

```text
mods/           Lua replay rooms, bot rooms, and a standalone bot
recorders/      Combined recorder/uploader, bot recorder, desktop replay tool
uploaders/      Two standalone Discord folder-watcher variants
viewers/        HTML replay, move-review, and map-analysis tools
analysis/       Python trajectory analysis and move grading
assets/ships/   100 ship PNG assets
docs/           Architecture, complete file guide, and source-review findings
tests/          Offline recorder regression tests and source/asset checks
```

Start with the [architecture and file guide](docs/ARCHITECTURE.md). The [source review](docs/REVIEW.md) separates strengths, known gaps, and validation limits.

## Main recording-to-Discord workflow

The pairing documented here is [`mods/mod1.lua`](mods/mod1.lua) with [`recorders/main.py`](recorders/main.py), based on their supplied configuration. Other room and recorder variants are retained, not declared obsolete.

- **Room:** `mod1.lua` provides the 1v1 room and writes initial map data, event/position chunks, and the final-game flag through `g2.data`.
- **Recorder:** `main.py` polls `mod1.bin`, appends the JSONL recording locally, closes a quick-play replay on its final chunk, then queues the file for Discord.
- **Batch recording:** The room's batch controls group games into one recording; the recorder queues that file when it receives the end-batch sentinel, or closes an open batch when a non-batch game begins.
- **Playback:** `Replay_Viewer_Pro-3-5.html` provides the main browser replay interface; the other HTML tools support move review and map exploration.

### Configure and launch

Run these commands from the repository root:

```sh
python3 -m pip install discord.py
python3 recorders/main.py
```

Before launching:

1. Load the intended Lua room in Galcon 2.
2. Check `BIN_FILE`, `OUTPUT_DIR`, and `CHANNEL_ID` in `recorders/main.py` against the local setup.
3. Set `DISCORD_BOT_TOKEN` securely in the local process environment. The script reads it at import time; it is required even before Discord startup.
4. Ensure the configured Discord bot can see the intended channel and send messages/attachments.

The previously attached token was removed before its first GitHub commit. Reset that token before use. Never place a real token in tracked source, documentation, shell scripts, or committed configuration; `.gitignore` excludes local `.env` files, but the scripts do not automatically load them.

The supplied machine-specific paths remain unchanged. Moving the scripts does not move Steam saves or existing recordings, and existing shortcuts pointing at root-level scripts need to be updated to the paths above. Running relative-output tools from the repository root preserves their working-directory behavior.

### Confirmed Steam save locations

The owner's confirmed macOS directory is:

```text
~/Library/Application Support/Steam/userdata/1208075763/294160/remote/
```

- **Slot 1:** `mod1.bin`, confirmed by the owner and configured in `recorders/main.py`.
- **Slot 2:** `mod2.bin` in the same directory, confirmed by the owner and configured in `recorders/botreplay-3.py`.
- **Slot 3:** `mod3.bin` remains unconfirmed. Having a `mod3-3.lua` source file does not establish that save file's existence.

Lua writes to `g2.data`; the local `.bin` filename is associated with the installed mod slot, not inferred from these source filenames.

## Other tools

- **Continuous bot recording:** Run `python3 recorders/botreplay-3.py` for the configured `mod2.bin` source. It writes to `galcon_recordings/botroom` relative to the working directory and does not itself upload to Discord.
- **Standalone uploaders:** `uploaders/replaybot-2.py` and `uploaders/discord_bot-7.py` use `discord.py` plus `watchdog`. Configure their placeholders and watched directories locally; these are alternatives, not prerequisites for `main.py`, which already uploads completed recordings. Do not run both approaches on the same output folder unless duplicate uploads are intended.
- **HTML tools:** Open the files under `viewers/` in a browser and select local replay/CSV files using their controls. They remain source files in GitHub, not deployed websites. Decompress Discord `.jsonl.gz` exports before selecting them in these text-file readers.
- **Move grading:** Install NumPy, then run `python3 analysis/grade_moves-6.py "/path/to/replays" --evaluator v2`. CSV outputs are written in the current working directory. The optional v3/ensemble evaluators require an external evaluator JSON file that is not included.
- **Trajectory analysis:** `analysis/analyze_replay-4.py` requires `geometry_engine.py`, which is not included. Its supplied `/home/claude` import-path setting is unchanged.
- **Desktop replay:** `recorders/galcon (28).py` uses Matplotlib's `MacOSX` backend and retains a placeholder recording path. Its recorder expects a different final-payload shape; do not assume recording compatibility with every included room.

Several source-file header comments still show their historical filenames. Use the paths in this README; those comments were left unchanged to preserve the supplied code.

## Validation and current limits

Run the offline tests without a Discord token, a game client, or network access:

```sh
python3 -m unittest discover -s tests -v
```

Python syntax and PNG integrity checks use the standard library. JavaScript syntax checks run when Node.js is installed; Lua parsing runs when the optional `luaparser` package is installed. Skipped checks are reported explicitly.

The recorder tests exercise the existing functions with synthetic payloads and temporary files. They do not run the Galcon engine, authenticate a bot, send Discord messages, prove lossless capture, or validate analysis accuracy. In particular, the [review](docs/REVIEW.md) documents an oversized-file cleanup risk, metadata handoff gaps, and the absence of durable upload retries. No production logic was changed to fix those issues during this folder cleanup.
