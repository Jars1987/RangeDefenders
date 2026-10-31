#!/usr/bin/env python3
"""Inject a byte-mode, error-correction L QR, or render its actual stored matrix.

Install segno in your Python environment. --check never modifies the Lua file.
--pgm OUT MAIN_LUA needs no encoder and renders 4px modules, 4-module quiet zone.
"""
import argparse
import json
from pathlib import Path
import re
import sys

BEGIN = "-- BEGIN GENERATED QR"
END = "-- END GENERATED QR"


def block(text):
    if text.count(BEGIN) != 1 or text.count(END) != 1:
        raise ValueError("expected exactly one QR marker pair")
    match = re.search(re.escape(BEGIN) + r"\n(.*?)\n" + re.escape(END), text, re.S)
    if not match:
        raise ValueError("QR markers are reversed or malformed")
    return match


def parse(text):
    body = block(text).group(1)
    match = re.fullmatch(r'local QR\s*=\s*\{\s*url\s*=\s*("(?:[^"\\]|\\.)*")\s*,\s*size\s*=\s*(\d+)\s*,\s*rows\s*=\s*\{([\s\S]*)\}\s*\}\s*', body)
    if not match:
        raise ValueError("malformed generated QR statement")
    url, size = json.loads(match[1]), int(match[2])
    rows = re.findall(r'"([01]+)"', match[3])
    if re.sub(r'"[01]+"|[\s,]', '', match[3]) or len(rows) != size or any(len(r) != size for r in rows):
        raise ValueError("QR rows must be a square binary matrix")
    return url, rows


def encode(url):
    import segno
    qr = segno.make(url, mode="byte", error="L", micro=False, boost_error=False)
    rows = [''.join('1' if bit else '0' for bit in row) for row in qr.matrix]
    return ('local QR = { url = ' + json.dumps(url, ensure_ascii=True) + ', size = ' + str(len(rows))
            + ', rows = {\n' + ',\n'.join('  "' + r + '"' for r in rows) + '\n} }')


def pgm(path, rows):
    side = (len(rows) + 8) * 4
    pixels = bytearray([255]) * (side * side)
    for y, row in enumerate(rows):
        for x, bit in enumerate(row):
            if bit == '1':
                for dy in range(4):
                    pos = ((y + 4) * 4 + dy) * side + (x + 4) * 4
                    pixels[pos:pos + 4] = b'\x00' * 4
    Path(path).write_bytes(f'P5\n{side} {side}\n255\n'.encode() + pixels)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--url')
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument('--write', metavar='MAIN_LUA')
    mode.add_argument('--check', metavar='MAIN_LUA')
    mode.add_argument('--pgm', metavar='OUT.pgm')
    ap.add_argument('main_lua', nargs='?')
    a = ap.parse_args()
    path = a.write or a.check or a.main_lua
    if not path or (a.main_lua and not a.pgm):
        ap.error('use --write MAIN_LUA, --check MAIN_LUA, or --pgm OUT MAIN_LUA')
    try:
        source = Path(path).read_text()
        if a.pgm:
            _, rows = parse(source)
            pgm(a.pgm, rows)
            print(f'QR rendered: {a.pgm}')
            return
        url = a.url
        if not url:
            if a.write:
                ap.error('--write requires --url')
            url, _ = parse(source)
        if not url.isascii() or any(ord(c) < 32 or c in '"\\' for c in url):
            raise ValueError('URL must be printable ASCII without quotes or backslashes')
        match = block(source)
        updated = source[:match.start(1)] + encode(url) + source[match.end(1):]
        if a.check and updated != source:
            sys.exit(f'stale QR: {path}')
        if a.write and updated != source:
            temp = Path(str(path) + '.tmp')
            temp.write_text(updated)
            temp.replace(path)
        print(f'QR {"checked" if a.check else "written"}: {path}')
    except (OSError, ValueError, ImportError) as e:
        sys.exit(f'error: {e}')


if __name__ == '__main__':
    main()
