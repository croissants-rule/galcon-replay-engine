# Architecture and File Guide

The main product is a connected workflow, not just an isolated replay viewer: a hosted match produces a local replay that can be shared automatically and examined using dedicated playback and analysis tools. This guide describes the supplied source, not a claim that every variant has been tested together.

## Match-to-Discord lifecycle

```text
mods/mod1.lua
  game starts  -> payload.chunk = 0, map, player identities, room metadata
  game runs    -> event/position chunks replace payload in g2.data
  game ends    -> flush_chunk(true, winner_info), summary, winner fields
                        |
                        | Galcon persists the mod-slot save
                        v
Steam remote/mod1.bin
                        |
                        | recorders/main.py polls the current payload
                        v
local JSONL file
  quick play   -> init, chunks, final chunk/summary -> close -> queue
  batch        -> header, game divider, init, chunks; repeat per game
                  /endbatch sentinel -> close -> queue
                        |
                        | thread-safe handoff to asyncio upload queue
                        v
Discord uploader task
  normal file  -> attach JSONL
  large file   -> attempt game-boundary splitting + gzip attachments
                        |
                        v
viewers/ + analysis/
```

The recorder runs in a background thread while Discord delivery runs asynchronously. A final-chunk flag, rather than a guess that a file has stopped growing, triggers the quick-play handoff. This separation lets local recording progress independently of the asynchronous upload task, but the queue is in memory and is not a durable delivery guarantee.

### Payload and replay format

- **Initial payload:** The room supplies the planet map, player numbers/names/colors, dimensions, and additional room metadata. The Python recorder writes a selected subset as a JSONL `init` record.
- **Incremental payload:** `events` captures fleet and planet changes; `pos` captures timestamped fleet positions. Each replacement payload has a chunk index.
- **Final payload:** The room flushes pending records with `final = true` and a summary. The room's top-level winner field and the recorder's nested winner lookup are not aligned; see the review before relying on result labels.
- **Batch wrapper:** `batch_header` identifies the file, and `game_divider` separates games, each with its own `init`. Viewers and analyzers must not reuse one game's map for subsequent games.

`g2.data` is a latest-payload mailbox, not an append-only event log. The current source does not implement acknowledgements or retransmission if an intermediate payload is overwritten before the recorder polls it.

## Complete source file guide

### Mod rooms and bot

| Current path | Role |
| --- | --- |
| `mods/mod1.lua` | Main documented 1v1 room: queue/lobby, map selection, customization, recording, surrender/disconnect handling, and spectator controls. |
| `mods/mod2-2.lua` | Bot-room variant with configurable behavior, stochastic choices, map regimes, unattended match progression, and recording. |
| `mods/mod2-4.lua` | Separate bot-room variant with Philbuff map selection and automatic match countdown. Retained independently of `mod2-2.lua`. |
| `mods/mod3-3.lua` | Additional 1v1 replay-room variant. Its source filename does not confirm a `mod3.bin` installation. |
| `mods/mod1_server-5.lua` | Alternative 1v1 server/recorder with its own lobby, player/spectator handling, and recording implementation. |
| `mods/MeanMachine-6.lua` | Standalone `bots_mean(params)` agent implementation. It is not automatically wired into the other Lua files by the repository layout. |

### Recording and sharing

| Current path | Role and configuration |
| --- | --- |
| `recorders/main.py` | Combined always-on recorder and uploader; configured for `mod1.bin`, absolute local recording directory, batch controls, and room-stat persistence code. Requires `DISCORD_BOT_TOKEN`; stat metadata handoff needs attention. |
| `recorders/botreplay-3.py` | Continuous bot-room JSONL recorder for `mod2.bin`; relative output directory `galcon_recordings/botroom`; no built-in Discord upload. |
| `recorders/galcon (28).py` | Original combined recorder/Matplotlib replay tool; Mac-specific GUI backend and placeholder save path; different final-recording format expectations. |
| `uploaders/replaybot-2.py` | Standalone folder watcher configured for the owner's recording directory, with a placeholder token. |
| `uploaders/discord_bot-7.py` | Standalone folder watcher defaulting to `~/Downloads`, with placeholder token/channel settings. |

### Playback and analysis

| Current path | Role and dependencies |
| --- | --- |
| `viewers/Replay_Viewer_Pro-3-5.html` | Single/batch replay playback, timeline controls, fleet/planet reconstruction, economy and fleet analysis, simulation/search features, and CSV export. |
| `viewers/Move_Review-2-7.html` | Combines replay JSONL with decision-grade CSV; session matching, move selection, grade filtering, playback, and simulation-error gating. |
| `viewers/ring_structure_terrain_aware-28-8.html` | Map-structure and terrain-aware exploration, traffic/route visualization, timeline/sandbox modes, and search controls. |
| `analysis/analyze_replay-4.py` | Segments trajectories at redirects and evaluates transit prediction against recordings, including stalls and obstruction/pathing diagnostics. Requires the missing `geometry_engine.py`. |
| `analysis/grade_moves-6.py` | Counterfactual move grading, chained moves, landing-time perturbations, simulation-vs-reality checks, and CSV summaries. Requires NumPy; optional evaluators need external JSON. |

### Assets and supporting files

- **`assets/ships/ship-*.png`:** All 100 existing ship images were moved without renaming or modifying their bytes. The Lua room uses Galcon ship asset identifiers; the supplied Python/HTML sources do not reference these PNGs by their old root paths.
- **`README.md`:** Entry points, local setup, confirmed Steam paths, and validation commands.
- **`.gitignore`:** Excludes local credential files and Python bytecode/cache files.
- **`docs/REVIEW.md`:** Source-review findings and scope limits.
- **`tests/`:** Isolated regression checks, syntax checks, and PNG integrity validation.

## Migration notes

Existing Lua, Python, HTML, and PNG file contents are unchanged from the pre-organization commit. The repository move does not install mods, relocate local save files, change Discord channel settings, or rewrite any configured absolute paths.

Update shortcuts, IDE run configurations, bookmarks, and automation that referred to files at the repository root. Run Python commands from the repository root when retaining the supplied relative recording/output paths. External consumers of raw GitHub file URLs must also use the new folders.

There are no internal Python imports between the moved scripts that need rewriting. The missing geometry module remains missing; changing its import behavior would be a separate functional change. The replay viewer's optional `?replay=` fetch uses the supplied URL, so any relative replay URL will now resolve against the viewer's new location.
