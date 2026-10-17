# Galcon Replay Engine

Galcon 2 Lua mods, a Python recorder/replay viewer, a Discord replay uploader, and ship image assets.

## Files

- `mod1.lua`: Updated 1v1 replay-room mod. Replaces the earlier repository version; that version remains available in Git history.
- `mod2-2.lua`: Bot-room variant with configurable bot behavior and recording.
- `mod2-4.lua`: Separate bot-room variant using Philbuff maps. Preserved alongside `mod2-2.lua`, not treated as a replacement.
- `mod3-3.lua`: Additional 1v1 replay-room variant.
- `mod1_server-5.lua`: Alternative 1v1 server recorder.
- `MeanMachine-6.lua`: `bots_mean(params)` bot implementation.
- `discord_bot-7.py`: Watches a local folder for `.jsonl` files and uploads them to Discord when run and configured.
- `galcon (28).py`: Existing Python recorder/replay viewer.
- `ship-*.png`: Existing ship image assets.

The seven uploaded source files retain their supplied names and contents. Their numbered suffixes do not establish which version is newest or which Galcon mod slot should load them.

## Local recording files

The owner's confirmed macOS Steam save directory is:

```text
~/Library/Application Support/Steam/userdata/1208075763/294160/remote/
```

Here `~` means the current macOS user's home directory.

- Mod slot 1: `mod1.bin`, confirmed by the owner.
- Mod slot 2: `mod2.bin` in the same directory, confirmed by the owner.
- Mod slot 3: `mod3.bin` is a possible filename, but its existence/location has not been confirmed. A `mod3-3.lua` source file is included; that does not verify a local `.bin` file.

The Lua recorders use `g2.data`; they do not hard-code these macOS paths. The existing `galcon (28).py` still has its original placeholder `BIN_FILE` path. Set that configuration to the appropriate local `.bin` file before recording. No recorder configuration or gameplay logic was changed as part of this upload, and compatibility between the existing viewer and every supplied mod variant has not been tested.

## Discord uploader

Install the dependencies with `pip install discord.py watchdog`, then configure the token, channel ID, and watched directory locally before running `python discord_bot-7.py`.

The supplied token and channel ID are placeholders. Do not commit a real bot token to this public repository. The default watched directory is `~/Downloads`, whereas the existing recorder writes to `galcon_recordings` relative to its working directory; align these locations if using the two scripts together.
