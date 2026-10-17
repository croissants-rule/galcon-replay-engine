# Source Review

This review covers the supplied Lua, Python, and HTML source files, their cross-file handoffs, and the ship-asset inventory. Findings are based on source inspection and isolated tests, not a live Galcon-to-Discord session or independent validation of the analysis models.

## What the product already brings together

- **An explicit game-completion handoff:** The room flushes a final recording chunk, and the combined recorder closes the local quick-play file before enqueueing it. This is more specific than relying on a folder watcher to infer completion from file size.
- **A full room lifecycle:** The main room includes queues, settings, cosmetics, spectator controls, surrender/disconnect handling, and a route back to the lobby. The recording logic is integrated into that lifecycle rather than added only to a separate viewer.
- **Careful surrender handling:** `mod1.lua` uses a shared handler for surrender and leaving, ignores repeat handling for the same player, excludes spectators, records an explicit event, and handles a second player's departure within the pending-end window.
- **Separate capture and delivery:** The recorder thread writes local files while an asynchronous task handles Discord delivery. Quick-play and batch mode have different completion boundaries.
- **A usable review surface:** The main HTML viewer handles single/batch playback and analysis, while the move-review tool combines replay data with grade CSVs. These are distinct parts of a replay product, not just raw log exports.
- **Explicit analytical uncertainty:** The move grader perturbs landing times, checks simulation against recorded outcomes, and can mark a move `unclear`. Its documentation also acknowledges hindsight and fixed-opponent-response assumptions; those caveats should remain visible.
- **Multiple experiments retained:** Alternative rooms, bot behaviors, uploaders, and the desktop viewer are preserved. Filename suffixes alone do not justify deleting or marking a variant obsolete.

## Reliability findings

These are follow-up candidates, not fixes included in the folder reorganization. Source inspection establishes the code paths; it does not establish that a particular loss or incorrect result occurred in the owner's sessions.

### Protect the original replay during oversized uploads

**Priority: high.** In `recorders/main.py`, `split_batch_for_discord()` returns `[path]` when it finds no batch game dividers. The oversized-file branch treats every returned path as temporary and deletes both `part_path` and its gzip file in `finally`.

For an oversized single-game replay, `part_path` can therefore be the original local replay. Cleanup can delete it even if sending the attachment raises an exception, while a later log message can still claim the file is saved.

Recommended separate fix: distinguish owned temporary files from the original path, never remove the original during attachment cleanup, and test both successful and failed sends. This is a source-confirmed path; the offline suite deliberately does not run a real Discord upload.

### Preserve canonical winner and room metadata

**Priority: high.** The main Lua room writes `existing.winner` at the top level and `winner_name`/`winner_uid` inside the final payload. The Python recorder instead reads `payload.get("winner")` when writing its final JSONL record, so it does not carry the canonical top-level winner through that handoff.

The recorder also tries to read both player UIDs and names from the final payload for `record_result()`, but that payload is rebuilt as a chunk and does not include the expected player identity fields. The room-stat implementation should not be treated as verified working result persistence for this pairing.

The initial record writes only selected fields, dropping room fields such as map style/ranked metadata. The bot recorder similarly drops additional bot-room configuration. Recommended separate fix: define a shared schema, retain initial identities per game, propagate the explicit result and abort status, and test that metadata survives into JSONL.

### Detect missed payloads and rapid game restarts

**Priority: medium to high for unattended bot capture.** `g2.data` is overwritten with each new payload. Polling approximately every 50 ms does not by itself guarantee capture of every chunk, and the current code lacks acknowledgements, retransmission, and sequence-gap reporting.

The `mod2-2.lua` path can flush a final chunk, enter the lobby, and immediately start another game when its countdown is zero. That creates a source-level risk of replacing the final or initial payload before an external poll observes it.

Recommended separate fix: test actual save timing under the installed game, log chunk gaps and game identities, and consider an acknowledgement or retained-chunk protocol. A longer start delay is a mitigation, not proof of lossless recording.

### Make upload delivery recoverable

**Priority: medium.** The combined uploader uses an in-memory queue and logs upload exceptions without a persistent outbox or retry/reconciliation pass. A restart can therefore lose pending delivery work even when local recordings remain.

Recommended separate fix: preserve original files, persist pending upload state, retry with bounded backoff, and record a durable success marker or message ID. Avoid claiming exactly-once delivery without testing reconnects and failure recovery.

### Treat standalone watchers as alternatives

**Priority: medium if these variants are in use.** The two folder watchers infer completion from a quiet file size, not a final-game signal. A long pause in recording can look like completion, and each `on_ready()` starts a new observer without a reconnect guard.

Their file-disappearance path also breaks out of the size-wait loop and then reaches another `getsize()` outside that guard. Keep these variants, but do not assume they have the same lifecycle guarantees as the integrated recorder or run them alongside it without considering duplicate posts.

## Dependencies and compatibility limits

- **Trajectory engine:** `geometry_engine.py` is absent. The analyzer retains a machine-specific import search path and cannot be fully exercised from this repository alone.
- **Evaluator models:** v3/ensemble grading requires external evaluator JSON. v2 is available in the source, but model calibration and grade quality were not independently verified.
- **Original desktop recorder:** Its final-payload expectations differ from the incremental room/recorder workflow, and it selects Matplotlib's `MacOSX` backend. Preserving it does not certify compatibility with every room or platform.
- **Compressed replay imports:** The HTML tools read selected files as text. Decompress `.jsonl.gz` attachments before loading them; automatic gzip import is not provided by those readers.
- **Credentials:** The combined recorder reads `DISCORD_BOT_TOKEN` at import time. The previously attached token was removed before its first commit; it should still be reset because it was shared outside the local environment.
- **Environment:** Steam saves, a running Galcon host, a configured Discord bot/channel, real replay fixtures, the missing geometry module, and optional evaluator artifacts are not part of the offline tests.

## Validation scope

The added tests extract selected existing functions through Python's AST, avoiding module-level Discord initialization and token reads. They exercise synthetic quick-play/batch payloads, local file completion, duplicate-chunk handling, malformed mailbox reads, sanitization, and game-boundary splitting.

Repository checks parse Python, optionally parse Lua, optionally check inline JavaScript using Node.js, and verify PNG chunk checksums. These checks establish syntax and isolated behavior, not GUI correctness, actual game save timing, Discord permission/attachment limits, complete replay fidelity, or strategic accuracy.

Production source files and assets were moved without content changes. Functional repairs should be separate commits with targeted regression tests and representative recordings, so the working setup remains easy to compare and roll back.

### Offline check result

On October 17, 2026, `python3 -m unittest discover -s tests -v` passed all 13 tests with no skipped checks in the review environment. That run included Python parsing, all six Lua files, inline JavaScript in all three HTML files, and chunk-checksum validation of all 100 PNG assets, as well as the isolated recorder tests described above.

The checks ran without a game client, Discord authentication, or outbound messages. Passing them does not resolve the source-level reliability findings in this document.
