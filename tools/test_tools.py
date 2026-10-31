#!/usr/bin/env python3
"""Offline regression checks for marker replacement, typing and reproducibility."""
import copy
import hashlib
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import build_snapshot as snapshot
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

    def builder(self, *args, allow=True):
        flags = ['--seeds', 'tools/fixtures/seeds.txt', '--dry-run', 'tools/fixtures/responses',
                 '--date', '2026-10-31']
        if allow:
            flags += ['--allow-missing', 'DRAINER']
        return self.command('build_snapshot.py', *flags, *args)

    def test_snapshot_replay_check_and_stale(self):
        result = self.builder('--write', self.main)
        self.assertEqual(result.returncode, 0, result.stderr)
        text = self.main.read_text()
        self.assertIn('EXPLOIT=1, SCAM=1, MIXER=1, DRAINER=0', result.stderr)
        self.assertNotIn('name_tag', text)
        self.assertNotIn('42RLPAC', text)
        before = (hashlib.sha256(self.main.read_bytes()).digest(), self.main.stat().st_mtime_ns)
        result = self.builder('--check', self.main)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.builder('--write', self.main).returncode, 0)
        self.assertEqual(before, (hashlib.sha256(self.main.read_bytes()).digest(), self.main.stat().st_mtime_ns))
        self.main.write_text(text.replace('generated = "2026-10-31"', 'generated = "2026-10-30"'))
        old = self.main.read_bytes()
        self.assertEqual(self.builder('--check', self.main).returncode, 1)
        self.assertEqual(self.main.read_bytes(), old)

    def test_empty_type_fails_without_touching_file(self):
        before = self.main.read_bytes()
        self.assertNotEqual(self.builder('--write', self.main, allow=False).returncode, 0)
        self.assertEqual(self.main.read_bytes(), before)

    def test_date_and_read_only_flags(self):
        for args in [('--check', self.main, '--date', '2026-02-30'),
                     ('--check', self.main, '--out-json', str(self.main)+'.json')]:
            self.assertNotEqual(self.builder(*args).returncode, 0)
        self.assertFalse(Path(str(self.main)+'.json').exists())
        result = self.command('build_snapshot.py', '--check', self.main)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('--date', result.stderr)

    def test_typing_precedence_and_own_attribution_only(self):
        addr = 'Htp9MGP8Tig923ZFY7Qf2zzbMUmYneFRAhSp7vSg4wxV'
        body = {'address': addr, 'riskScore': 10,
                'attribution': {'category': 'hack', 'risk_categories': ['scam', 'money-laundering']}}
        self.assertEqual(snapshot.classify(addr, body)[0], 'EXPLOIT')
        body['attribution']['risk_categories'].append('drainer')
        self.assertEqual(snapshot.classify(addr, body)[0], 'DRAINER')
        body['attribution']['risk_categories'] = ['exploit', 'money-laundering']
        body['attribution']['category'] = None
        self.assertEqual(snapshot.classify(addr, body)[0], 'MIXER')
        body.pop('attribution')
        body['maliciousAddressesFound'] = [{'address': addr, 'distance': 1, 'category': 'hack'}]
        self.assertIsNone(snapshot.classify(addr, body)[0])
        body['maliciousAddressesFound'][0]['distance'] = 0
        self.assertEqual(snapshot.classify(addr, body)[0], 'EXPLOIT')

    def test_score_sanctions_victim_and_scrubbing(self):
        addr = 'Htp9MGP8Tig923ZFY7Qf2zzbMUmYneFRAhSp7vSg4wxV'
        body = {'riskScore': 10, 'attribution': {'category': 'exchange', 'risk_categories': ['hack']}}
        self.assertIsNone(snapshot.classify(addr, body)[0])
        body['attribution'] = {'category': 'sanctioned', 'name_tag': 'hack unrelated label'}
        self.assertIsNone(snapshot.classify(addr, body)[0])
        body['attribution'] = {'category': 'hack'}
        for score in [True, 6, 11, 7.5, None]:
            body['riskScore'] = score
            self.assertIsNone(snapshot.classify(addr, body)[0])
        data = {'name_tag': 'private', 'items': [{'entity': 'private', 'category': 'hack'}], 'reasoning': 'private'}
        original = copy.deepcopy(data)
        self.assertEqual(snapshot.scrub(data), {'items': [{'category': 'hack'}]})
        self.assertEqual(data, original)

    def test_marker_validation_and_order(self):
        for s in ['', '-- END GENERATED SNAPSHOT\n-- BEGIN GENERATED SNAPSHOT',
                  '-- BEGIN GENERATED SNAPSHOT\n-- BEGIN GENERATED SNAPSHOT\n-- END GENERATED SNAPSHOT']:
            with self.assertRaises(ValueError):
                snapshot.replace_snapshot(s, 'local SNAPSHOT = {}')
        entries = [{'a': 'z', 't': 'SCAM', 's': 7}, {'a': 'b', 't': 'EXPLOIT', 's': 9},
                   {'a': 'a', 't': 'EXPLOIT', 's': 9}, {'a': 'c', 't': 'EXPLOIT', 's': 10}]
        self.assertEqual([e['a'] for e in snapshot.build(entries, '2026-10-31')[0]], ['c', 'a', 'b', 'z'])

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
