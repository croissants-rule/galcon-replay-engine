"""Offline tests of selected, unmodified recorder functions.

AST extraction avoids importing Discord, evaluating the token, or starting a bot.
Inputs are synthetic; these are not game/Discord integration tests.
"""

import ast
import contextlib
import io
import json
import os
from pathlib import Path
import re
import tempfile
import unittest
from datetime import datetime
from types import SimpleNamespace


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "recorders" / "main.py"


def load_functions():
    tree = ast.parse(SOURCE.read_text(encoding="utf-8"), filename=str(SOURCE))
    names = {"sanitize", "read_bin", "split_batch_for_discord", "recorder_thread"}
    selected = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
    namespace = {"json": json, "os": os, "re": re, "datetime": datetime}
    exec(compile(ast.Module(body=selected, type_ignores=[]), str(SOURCE), "exec"), namespace)
    return namespace


class EndOfFixture(BaseException):
    """End a polling loop without entering its application exception handlers."""


def initial(batch=False):
    return {"payload": {
        "chunk": 0, "batch_mode": batch,
        "map": [{"n": 1, "x": 20, "y": 30, "r": 8, "prod": 100, "ships": 50, "owner": 1}],
        "player_n": 1, "enemy_n": 2,
        "player_name": "Player A", "enemy_name": "Player B",
        "w": 520, "h": 360, "version": 1,
    }}


def chunk(index=1, final=False):
    return {"payload": {
        "chunk": index, "final": final,
        "events": [{"e": "pn", "t": index, "n": 1, "s": 51}],
        "pos": [],
    }, "summary": [{"t": index, "p": 51, "e": 30}]}


class RecorderTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.output = Path(self.tmp.name)
        self.ns = load_functions()
        self.uploads = []
        self.ns["OUTPUT_DIR"] = str(self.output)
        self.ns["BIN_FILE"] = str(self.output / "mod1.bin")
        self.ns["time"] = SimpleNamespace(sleep=lambda _: None)
        self.ns["record_result"] = lambda *args, **kwargs: None

        def queue_upload(path, label, loop):
            # Read at handoff time: the replay must already be visible on disk.
            records = [json.loads(line) for line in Path(path).read_text().splitlines()]
            self.uploads.append((path, label, records))

        self.ns["queue_upload"] = queue_upload

    def feed(self, values):
        sequence = iter(values)

        def read_bin():
            try:
                return next(sequence)
            except StopIteration:
                raise EndOfFixture

        self.ns["read_bin"] = read_bin
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(EndOfFixture):
                self.ns["recorder_thread"](None)

    def test_quick_game_uploads_final_replay_once(self):
        self.feed([initial(), chunk(1), chunk(1), chunk(2, True), chunk(2, True)])
        self.assertEqual(len(self.uploads), 1)
        path, _, records = self.uploads[0]
        self.assertTrue(Path(path).exists())
        self.assertEqual([r["type"] for r in records], ["init", "chunk", "chunk"])
        self.assertEqual([r["chunk"] for r in records[1:]], [1, 2])
        self.assertTrue(records[-1]["final"])
        self.assertIn("summary", records[-1])

    def test_quick_game_queues_only_after_file_is_closed(self):
        handles = []

        def tracked_open(*args, **kwargs):
            handle = open(*args, **kwargs)
            handles.append(handle)
            return handle

        original_queue = self.ns["queue_upload"]

        def check_closed(*args):
            self.assertTrue(handles)
            self.assertTrue(all(h.closed for h in handles))
            original_queue(*args)

        self.ns["open"] = tracked_open
        self.ns["queue_upload"] = check_closed
        self.feed([initial(), chunk(final=True)])
        self.assertEqual(len(self.uploads), 1)

    def test_incomplete_reads_do_not_prevent_capture(self):
        self.feed([None, {}, {"payload": None}, initial(), None, chunk(final=True)])
        self.assertEqual(len(self.uploads), 1)

    def test_batch_waits_for_end_and_keeps_two_games(self):
        # Test both game finals before allowing an end sentinel.
        observed_before_end = []
        original_read = iter([
            initial(True), chunk(final=True),
            initial(True), chunk(final=True),
        ])
        tail = iter([{"batch_end": True}, {"batch_end": True}])

        def read_bin():
            try:
                return next(original_read)
            except StopIteration:
                if not observed_before_end:
                    observed_before_end.append(len(self.uploads))
                try:
                    return next(tail)
                except StopIteration:
                    raise EndOfFixture

        self.ns["read_bin"] = read_bin
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaises(EndOfFixture):
                self.ns["recorder_thread"](None)
        self.assertEqual(observed_before_end, [0])
        self.assertEqual(len(self.uploads), 1)
        records = self.uploads[0][2]
        self.assertEqual(records[0]["type"], "batch_header")
        self.assertEqual(sum(r["type"] == "game_divider" for r in records), 2)
        self.assertEqual(sum(r["type"] == "init" for r in records), 2)
        self.assertEqual(sum(r.get("final", False) for r in records), 2)

    def test_nonbatch_game_closes_batch_then_uploads_own_replay(self):
        self.feed([initial(True), chunk(final=True), initial(False), chunk(final=True)])
        self.assertEqual(len(self.uploads), 2)
        self.assertEqual(self.uploads[0][2][0]["type"], "batch_header")
        self.assertEqual(self.uploads[1][2][0]["type"], "init")
        self.assertNotEqual(self.uploads[0][0], self.uploads[1][0])

    def test_sanitize_removes_path_characters_and_has_fallback(self):
        self.assertEqual(self.ns["sanitize"]("../../Player A"), "PlayerA")
        self.assertEqual(self.ns["sanitize"]("///"), "Player")
        self.assertEqual(len(self.ns["sanitize"]("x" * 50)), 20)

    def test_read_bin_tolerates_missing_and_partial_json(self):
        path = self.output / "mod1.bin"
        self.ns["BIN_FILE"] = str(path)
        self.assertIsNone(self.ns["read_bin"]())
        path.write_text('{"payload":', encoding="utf-8")
        self.assertIsNone(self.ns["read_bin"]())
        path.write_text(json.dumps(initial()), encoding="utf-8")
        self.assertEqual(self.ns["read_bin"](), initial())

    def test_batch_splits_only_at_game_boundaries(self):
        path = self.output / "batch.jsonl"
        records = [{"type": "batch_header", "batch_id": "fixture"}]
        for index in range(1, 4):
            records.extend([
                {"type": "game_divider", "game_index": index},
                {"type": "init", "session": str(index)},
                {"type": "chunk", "chunk": 1, "final": True},
            ])
        path.write_text("".join(json.dumps(r) + "\n" for r in records), encoding="utf-8")
        with contextlib.redirect_stdout(io.StringIO()):
            parts = self.ns["split_batch_for_discord"](str(path), max_compressed_bytes=1)
        self.assertTrue(path.exists())
        self.assertEqual(len(parts), 3)
        for index, part in enumerate(parts, 1):
            data = [json.loads(line) for line in Path(part).read_text().splitlines()]
            self.assertEqual(data[0], records[0])
            self.assertEqual(data[1]["game_index"], index)
            self.assertEqual([r["type"] for r in data[1:]], ["game_divider", "init", "chunk"])

    def test_single_game_split_returns_original_path(self):
        # Characterizes the helper, NOT safe uploader cleanup.
        # The caller's deletion risk is documented in docs/REVIEW.md.
        path = self.output / "single.jsonl"
        path.write_text('{"type":"init"}\n{"type":"chunk","final":true}\n', encoding="utf-8")
        self.assertEqual(self.ns["split_batch_for_discord"](str(path)), [str(path)])
        self.assertTrue(path.exists())


if __name__ == "__main__":
    unittest.main()
