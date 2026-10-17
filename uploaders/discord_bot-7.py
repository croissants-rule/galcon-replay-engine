"""
Galcon Replay Discord Bot
Watches ~/Downloads for new .jsonl replay files and uploads them to a Discord channel.

Usage:
    pip install discord.py watchdog
    python discord_bot.py
"""

import os
import time
import asyncio
import discord
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# ── CONFIG ────────────────────────────────────────────────────────────────────
DISCORD_TOKEN   = "YOUR_BOT_TOKEN_HERE"
CHANNEL_ID      = 123456789012345678   # Right-click channel → Copy ID
WATCH_DIR       = os.path.expanduser("~/Downloads")
REPLAY_EXT      = ".jsonl"             # Change to ".bin" etc. if needed
STABLE_WAIT_SEC = 2.0                  # Seconds to wait before uploading (let write finish)
MAX_FILE_MB     = 25                   # Discord free-tier file size limit
# ──────────────────────────────────────────────────────────────────────────────

intents = discord.Intents.default()
client  = discord.Client(intents=intents)
upload_queue: asyncio.Queue = asyncio.Queue()


class ReplayHandler(FileSystemEventHandler):
    """Watchdog handler — fires when a new file appears in Downloads."""

    def on_created(self, event):
        if event.is_directory:
            return
        path = event.src_path
        if path.endswith(REPLAY_EXT):
            print(f"[watchdog] Detected: {path}")
            # Schedule upload via the async queue (thread-safe)
            asyncio.run_coroutine_threadsafe(
                upload_queue.put(path),
                client.loop,
            )

    # Also catch files moved/renamed into the watch dir (e.g. browser "save as")
    def on_moved(self, event):
        if event.is_directory:
            return
        dest = event.dest_path
        if dest.endswith(REPLAY_EXT):
            print(f"[watchdog] Moved in: {dest}")
            asyncio.run_coroutine_threadsafe(
                upload_queue.put(dest),
                client.loop,
            )


async def upload_worker():
    """Pulls paths off the queue and uploads them one at a time."""
    await client.wait_until_ready()
    channel = client.get_channel(CHANNEL_ID)
    if channel is None:
        print(f"[error] Channel {CHANNEL_ID} not found — check CHANNEL_ID and bot permissions.")
        return

    print(f"[bot] Watching {WATCH_DIR} for *{REPLAY_EXT} files → #{channel.name}")

    while True:
        path = await upload_queue.get()

        # Wait for the file to finish writing
        await asyncio.sleep(STABLE_WAIT_SEC)
        prev_size = -1
        while True:
            try:
                size = os.path.getsize(path)
            except FileNotFoundError:
                print(f"[warn] File disappeared before upload: {path}")
                break
            if size == prev_size:
                break
            prev_size = size
            await asyncio.sleep(0.5)
        else:
            upload_queue.task_done()
            continue

        # Size guard
        size_mb = os.path.getsize(path) / (1024 * 1024)
        filename = os.path.basename(path)
        if size_mb > MAX_FILE_MB:
            print(f"[warn] {filename} is {size_mb:.1f} MB — too large for Discord, skipping.")
            await channel.send(f"⚠️ Replay `{filename}` is too large to upload ({size_mb:.1f} MB).")
            upload_queue.task_done()
            continue

        # Upload
        try:
            print(f"[bot] Uploading {filename} ({size_mb:.2f} MB) …")
            await channel.send(
                content=f"🎮 **New Galcon replay:** `{filename}`",
                file=discord.File(path, filename=filename),
            )
            print(f"[bot] ✓ Uploaded {filename}")
        except Exception as e:
            print(f"[error] Upload failed for {filename}: {e}")

        upload_queue.task_done()


@client.event
async def on_ready():
    print(f"[bot] Logged in as {client.user} (ID: {client.user.id})")
    # Start the file-system watcher in a background thread
    handler  = ReplayHandler()
    observer = Observer()
    observer.schedule(handler, WATCH_DIR, recursive=False)
    observer.start()
    print(f"[watchdog] Observer started on {WATCH_DIR}")


async def main():
    asyncio.get_event_loop().create_task(upload_worker())
    await client.start(DISCORD_TOKEN)


if __name__ == "__main__":
    asyncio.run(main())
