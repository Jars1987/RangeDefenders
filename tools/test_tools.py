#!/usr/bin/env python3
"""Offline regression checks for QR generation and reproducibility."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import make_qr as qr

ROOT = Path(__file__).resolve().parent.parent
URL = ('https://www.range.org/product/transaction-screening?utm_source=event-breakpoint'
       '&utm_medium=qr&utm_campaign=always-on&utm_content=badge-invaders')


class ToolsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='range-tools-')
        self.addCleanup(self.tmp.cleanup)
        self.main = Path(self.tmp.name) / 'main.lua'
        self.main.write_text((ROOT / 'tools/fixtures/invaders.lua').read_text())

    def command(self, tool, *args):
        return subprocess.run([sys.executable, str(ROOT / 'tools' / tool), *map(str, args)],
                              capture_output=True, text=True, cwd=ROOT)

    def test_qr_write_check_stale_and_pgm(self):
        result = self.command('make_qr.py', '--url', URL, '--write', self.main)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.main.read_text()
        url, rows = qr.parse(text)
        self.assertEqual(url, URL)
        self.assertEqual(len(rows), 45)
        before = (self.main.read_bytes(), self.main.stat().st_mtime_ns)
        self.assertEqual(self.command('make_qr.py', '--check', self.main).returncode, 0)
        self.assertEqual(self.command('make_qr.py', '--url', URL, '--write', self.main).returncode, 0)
        self.assertEqual(before, (self.main.read_bytes(), self.main.stat().st_mtime_ns))
        out = Path(self.tmp.name) / 'qr.pgm'
        self.assertEqual(self.command('make_qr.py', '--pgm', out, self.main).returncode, 0)
        image = out.read_bytes()
        header, pixels = image.split(b'\n255\n', 1)
        side = (len(rows) + 8) * 4
        self.assertEqual(len(pixels), side * side)
        self.assertEqual(pixels[:side * 16], b'\xff' * (side * 16))
        self.main.write_text(text.replace(rows[0], ('0' if rows[0][0] == '1' else '1') + rows[0][1:], 1))
        old = self.main.read_bytes()
        self.assertEqual(self.command('make_qr.py', '--check', self.main).returncode, 1)
        self.assertEqual(old, self.main.read_bytes())

    def test_qr_rejects_non_square_matrix(self):
        with self.assertRaises(ValueError):
            qr.parse('-- BEGIN GENERATED QR\nlocal QR = {url="x", size=2, rows={"1","10"}}\n-- END GENERATED QR')


if __name__ == '__main__':
    unittest.main()
