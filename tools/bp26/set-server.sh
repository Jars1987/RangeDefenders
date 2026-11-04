#!/bin/sh
# Configure both packages together. Origins must be HTTPS without paths.
set -eu
[ "$#" -eq 2 ] || { echo 'Usage: set-server.sh <https-origin> <short-origin>' >&2; exit 2; }
bp26_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
python3 - "$bp26_root" "$1" "$2" <<'PY'
import json, re, sys
from pathlib import Path
from urllib.parse import urlsplit
root = Path(sys.argv[1])
origins = sys.argv[2:]
for value in origins:
    u = urlsplit(value)
    if not re.fullmatch(r'https://[A-Za-z0-9.-]+(?::[0-9]+)?', value) or not u.hostname:
        raise SystemExit('Expected HTTPS origins without paths, credentials or query strings')
if len(origins[1] + '/r/123456') > 40:
    raise SystemExit('Short origin exceeds the 40-byte result QR budget')
changes = []
for app in ('lazarus', 'defenders'):
    directory = root / 'apps' / app
    main = directory / 'main.lua'
    text = main.read_text()
    for name, origin in zip(('SERVER', 'SHORT_ORIGIN'), origins):
        text, count = re.subn(r'local ' + name + r' = "[^"]+"', 'local ' + name + ' = "' + origin + '"', text)
        if count != 1:
            raise SystemExit(f'{main}: expected one {name} constant')
    manifest = directory / 'app.json'
    data = json.loads(manifest.read_text())
    data['hosts'] = list(dict.fromkeys(urlsplit(v).netloc for v in origins))
    changes += [(main, text), (manifest, json.dumps(data, indent=2) + '\n')]
for path, text in changes:
    path.write_text(text)
PY
