"""Source syntax and PNG integrity checks, without executing production scripts."""

import ast
from html.parser import HTMLParser
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
import zlib


ROOT = Path(__file__).resolve().parents[1]


class ScriptCollector(HTMLParser):
    def __init__(self):
        super().__init__()
        self.collecting = False
        self.current = []
        self.scripts = []
        self.kind = ""

    def handle_starttag(self, tag, attrs):
        if tag != "script":
            return
        attrs = dict(attrs)
        kind = attrs.get("type", "").lower()
        self.kind = kind
        self.collecting = "src" not in attrs and kind in (
            "", "text/javascript", "application/javascript", "module",
        )
        self.current = []

    def handle_data(self, data):
        if self.collecting:
            self.current.append(data)

    def handle_endtag(self, tag):
        if tag == "script" and self.collecting:
            self.scripts.append(("".join(self.current), self.kind))
            self.collecting = False


class RepositoryChecks(unittest.TestCase):
    def test_python_syntax(self):
        paths = sorted(
            path for folder in ("recorders", "uploaders", "analysis", "tests")
            for path in (ROOT / folder).glob("*.py")
        )
        self.assertEqual(len([p for p in paths if p.parent.name != "tests"]), 7)
        for path in paths:
            with self.subTest(file=str(path.relative_to(ROOT))):
                ast.parse(path.read_text(encoding="utf-8"), filename=str(path))

    def test_lua_syntax(self):
        try:
            from luaparser import ast as lua_ast
        except ImportError:
            self.skipTest("Optional luaparser not installed")
        paths = sorted((ROOT / "mods").glob("*.lua"))
        self.assertEqual(len(paths), 6)
        for path in paths:
            with self.subTest(file=path.name):
                lua_ast.parse(path.read_text(encoding="utf-8"))

    def test_inline_javascript_syntax(self):
        node = shutil.which("node")
        if not node:
            self.skipTest("Node.js not installed")
        paths = sorted((ROOT / "viewers").glob("*.html"))
        self.assertEqual(len(paths), 3)
        for path in paths:
            parser = ScriptCollector()
            parser.feed(path.read_text(encoding="utf-8"))
            self.assertTrue(parser.scripts, path.name)
            for index, (script, kind) in enumerate(parser.scripts):
                with self.subTest(file=path.name, script=index):
                    with tempfile.TemporaryDirectory() as tmp:
                        source = Path(tmp) / ("inline.mjs" if kind == "module" else "inline.js")
                        source.write_text(script, encoding="utf-8")
                        result = subprocess.run(
                            [node, "--check", str(source)],
                            capture_output=True, text=True, timeout=30,
                        )
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_all_ship_png_chunk_checksums(self):
        images = sorted((ROOT / "assets" / "ships").glob("*.png"))
        self.assertEqual(len(images), 100)
        for path in images:
            with self.subTest(file=path.name):
                data = path.read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                offset = 8
                kinds = []
                while offset < len(data):
                    self.assertGreaterEqual(len(data) - offset, 12)
                    length = struct.unpack(">I", data[offset:offset + 4])[0]
                    end = offset + 12 + length
                    self.assertLessEqual(end, len(data))
                    kind = data[offset + 4:offset + 8]
                    payload = data[offset + 8:offset + 8 + length]
                    expected = struct.unpack(">I", data[offset + 8 + length:end])[0]
                    self.assertEqual(zlib.crc32(kind + payload) & 0xFFFFFFFF, expected)
                    kinds.append(kind)
                    if kind == b"IHDR":
                        width, height = struct.unpack(">II", payload[:8])
                        self.assertGreater(width, 0)
                        self.assertGreater(height, 0)
                    offset = end
                    if kind == b"IEND":
                        break
                self.assertEqual(kinds[0], b"IHDR")
                self.assertIn(b"IDAT", kinds)
                self.assertEqual(kinds[-1], b"IEND")
                self.assertEqual(offset, len(data))


if __name__ == "__main__":
    unittest.main()
