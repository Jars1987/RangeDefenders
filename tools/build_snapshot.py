#!/usr/bin/env python3
"""Build the invader snapshot for the badge game from Range Risk API verdicts.

Every seed address is checked with a DIRECT call to
GET https://api.range.org/v1/risk/address?address=<addr>&network=solana
and kept only if riskScore >= 7 and the address's OWN attribution maps to one
invader type. Flags on neighbours never count.

Python 3 standard library only.

Live run (needs RANGE_API_KEY in the environment, never on the command line):
    build_snapshot.py --seeds seeds.txt --date 2026-10-31 \
        --out-lua snapshot.lua --out-json snapshot.json [--save-responses DIR]

Offline replay (no key; DIR holds <address>.json raw responses):
    build_snapshot.py --seeds seeds.txt --dry-run responses/ --date 2026-10-31 \
        --out-lua snapshot.lua --out-json snapshot.json

Output keeps three fields per entry: address (a), type (t), score (s).
name_tag, entity and reasoning are read for typing only and never written.
"""

# ---------------------------------------------------------------------------
# Mapping table (edit here). Tokens are matched lowercase, "_" == "-".
#
# Where tokens come from, for the address's own attribution only:
#   category        attribution.category (the API's primary label)
#   risk_categories attribution.risk_categories
#   label           attribution.name_tag, whole-word keyword match only
#                   (never emitted)
#
# Precedence, first rule that yields a type wins:
#   1. DRAINER if any token or label keyword says drainer. A drainer is
#      usually also tagged "hack", so it must be checked first.
#   2. The primary category, if it maps (table below).
#   3. risk_categories, in type precedence SCAM > MIXER > EXPLOIT
#      (most specific behaviour first; hack/exploit is the generic case).
#   4. Label keywords, same precedence.
#   Otherwise the address is excluded: "sanctions-only" when every token is a
#   sanctions/blacklist token, else "unmapped".
#
# SCAM covers scams and rug pulls, and folds in phishing, address poisoning
# and impersonation so future phishing labels land there too.
# Deliberately unmapped: pump-dump, fraud-risk, spam-dusting, and
# sanctions/blacklist tokens (a listing says who someone is, not what they did).
# ---------------------------------------------------------------------------
TYPE_TOKENS = {
    "DRAINER": {"drainer", "wallet-drainer"},
    "SCAM": {"scam", "rug-pull", "phishing", "address-poisoning", "impersonating"},
    "MIXER": {"mixer", "tumbler", "money-laundering", "laundering", "obfuscation"},
    "EXPLOIT": {"hack", "exploit", "stolen-funds"},
}
# Regexes matched against the lowercased label.
LABEL_KEYWORDS = {
    "DRAINER": (r"\bdrainer",),
    "SCAM": (r"\bscam", r"\brug\b", r"\brug-?pull", r"\bphish", r"\bpoison"),
    "MIXER": (r"\bmixer", r"\btumbler", r"\blaunder"),
    "EXPLOIT": (r"\bexploit", r"\bhack"),
}
RISK_PRECEDENCE = ("SCAM", "MIXER", "EXPLOIT")
SANCTION_TOKENS = {
    "ofac-sanctioned", "sanctioned", "sanctions", "ofac", "blacklisted",
    "blacklist", "compliance-risk", "eu-sanctioned", "eu-sanction-ru",
    "uk-sanctioned", "japan-sanctioned", "france-sanctioned",
    "nbctf-terror-financing",
}
# A category string containing any of these is also a sanctions token
# (e.g. "Multi-Provider Blacklist & OFAC Sanctioned").
SANCTION_WORDS = ("sanction", "blacklist", "ofac")
# Tokens that say nothing about type and are ignored when typing.
NEUTRAL_TOKENS = {"security-risk", "individual", "entity", "none", ""}

MIN_SCORE = 7
TYPE_ORDER = ("EXPLOIT", "SCAM", "MIXER", "DRAINER")
MIN_PER_TYPE = 4
SOURCE = "Range Risk API"
API = "https://api.range.org/v1/risk/address"

import argparse
import datetime
import json
import os
import random
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE58 = re.compile(r"^[1-9A-HJ-NP-Za-km-z]{32,44}$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


B58_ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"


def is_solana_pubkey(addr):
    """Base58 that decodes to exactly 32 bytes (rejects e.g. Bitcoin addresses)."""
    if not BASE58.match(addr):
        return False
    n = 0
    for ch in addr:
        n = n * 58 + B58_ALPHABET.index(ch)
    pad = len(addr) - len(addr.lstrip("1"))
    return pad + (n.bit_length() + 7) // 8 == 32


def read_seeds(path):
    out, seen = [], set()
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            addr = line.split("#", 1)[0].strip()
            if not addr:
                continue
            if not is_solana_pubkey(addr):
                sys.exit(f"error: {path}:{n}: not a Solana address: {addr!r}")
            if addr not in seen:
                seen.add(addr)
                out.append(addr)
    return out


def fetch(addr, key):
    url = API + "?" + urllib.parse.urlencode({"address": addr, "network": "solana"})
    last = None
    for attempt in range(5):
        req = urllib.request.Request(url, headers={
            "Authorization": "Bearer " + key,
            "Accept": "application/json",
            "User-Agent": "range-invaders-snapshot/1.0",
        })
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                return json.loads(r.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            last = f"HTTP {e.code}"
            if e.code == 429 or e.code >= 500:
                time.sleep(2 ** attempt + random.random())
                continue
            break
        except (urllib.error.URLError, TimeoutError, ValueError) as e:
            last = str(e)
            time.sleep(2 ** attempt + random.random())
    raise RuntimeError(f"{addr}: request failed ({last})")


def load_saved(directory, addr):
    path = os.path.join(directory, addr + ".json")
    if not os.path.exists(path):
        raise RuntimeError(f"{addr}: no saved response at {path}")
    with open(path, encoding="utf-8") as fh:
        body = json.load(fh)
    # Tolerate a {"http": ..., "body": ...} wrapper.
    if isinstance(body, dict) and "body" in body and "http" in body:
        body = body["body"]
    return body


def own_attributions(addr, body):
    """The address's own attribution records; neighbour flags are ignored."""
    recs = []
    att = body.get("attribution")
    if isinstance(att, dict) and att.get("address", addr) == addr:
        recs.append(att)
    for m in body.get("maliciousAddressesFound") or []:
        if isinstance(m, dict) and m.get("distance") == 0 and m.get("address") == addr:
            recs.append(m)
    return recs


def _tok(v):
    """Lowercase, and treat "_" and "-" alike (money_laundering == money-laundering)."""
    return str(v).strip().lower().replace("_", "-") if v is not None else ""


def _is_sanction(t):
    return t in SANCTION_TOKENS or any(w in t for w in SANCTION_WORDS)


def classify(addr, body):
    """Return (type, None) or (None, reason)."""
    if not isinstance(body, dict) or "riskScore" not in body:
        return None, "no valid response"
    if body.get("address") not in (None, addr):
        return None, "response is for a different address"
    score = body.get("riskScore")
    if type(score) is not int or not MIN_SCORE <= score <= 10:
        return None, f"score {score} outside {MIN_SCORE}..10"
    recs = own_attributions(addr, body)
    if not recs:
        return None, "no own attribution (neighbour exposure only)"
    if any(_tok(r.get("category")) in {"exchange", "centralized-exchange", "cex", "victim", "victim-exchange"}
           for r in recs):
        return None, "victim/exchange attribution"
    cats = {_tok(r.get("category")) for r in recs} - {""}
    risks = {_tok(c) for r in recs for c in (r.get("risk_categories") or [])} - {""}
    labels = " ".join(_tok(r.get("name_tag")) for r in recs)
    tokens = cats | risks

    def label_has(t):
        return any(re.search(k, labels) for k in LABEL_KEYWORDS[t])

    # 1. drainer wins outright
    if tokens & TYPE_TOKENS["DRAINER"] or label_has("DRAINER"):
        return "DRAINER", None
    # 2. primary category
    for t in RISK_PRECEDENCE:
        if cats & TYPE_TOKENS[t]:
            return t, None
    # 3. risk categories
    for t in RISK_PRECEDENCE:
        if risks & TYPE_TOKENS[t]:
            return t, None
    meaningful = tokens - NEUTRAL_TOKENS
    if meaningful and all(_is_sanction(t) for t in meaningful):
        return None, "sanctions-only"
    # 4. label keywords
    for t in RISK_PRECEDENCE:
        if label_has(t):
            return t, None
    if not meaningful:
        return None, "unmapped (no own category)"
    return None, "unmapped (" + ",".join(sorted(meaningful)) + ")"


def build(entries, date):
    rank = {t: i for i, t in enumerate(TYPE_ORDER)}
    entries = sorted(entries, key=lambda e: (rank[e["t"]], -e["s"], e["a"]))
    rows = ",\n".join(f'    {{a="{e["a"]}", t="{e["t"]}", s={e["s"]}}}' for e in entries)
    lua = (f'local SNAPSHOT = {{ generated = "{date}", source = "{SOURCE}", entries = {{\n'
           f"{rows}\n}} }}\n")
    js = json.dumps({"generated": date, "source": SOURCE, "entries": entries}, indent=1) + "\n"
    return entries, lua, js


def write(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    os.replace(tmp, path)


def replace_snapshot(text, lua):
    """Require one marker pair; never append a second local declaration."""
    begin, end = "-- BEGIN GENERATED SNAPSHOT", "-- END GENERATED SNAPSHOT"
    if text.count(begin) != 1 or text.count(end) != 1:
        raise ValueError("expected exactly one SNAPSHOT marker pair")
    pattern = re.compile(re.escape(begin) + r"\n.*?" + re.escape(end), re.S)
    result, count = pattern.subn(lambda _: begin + "\n" + lua.rstrip() + "\n" + end, text)
    if count != 1:
        raise ValueError("SNAPSHOT markers are reversed or malformed")
    return result


def scrub(value):
    if isinstance(value, dict):
        return {k: scrub(v) for k, v in value.items() if k not in {"name_tag", "entity", "reasoning"}}
    if isinstance(value, list):
        return [scrub(v) for v in value]
    return value


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seeds", default=os.path.join(os.path.dirname(__file__), "seeds.txt"), help="one Solana address per line, # comments allowed")
    ap.add_argument("--dry-run", metavar="DIR", help="replay saved <address>.json responses; no key needed")
    ap.add_argument("--save-responses", metavar="DIR", help="live mode: save each scrubbed response as DIR/<address>.json")
    ap.add_argument("--out-lua")
    ap.add_argument("--out-json")
    mode = ap.add_mutually_exclusive_group()
    mode.add_argument("--write", metavar="MAIN_LUA", help="replace the generated SNAPSHOT block")
    mode.add_argument("--check", metavar="MAIN_LUA", help="read-only comparison, exit 1 if stale")
    ap.add_argument("--allow-missing", action="append", default=[], choices=TYPE_ORDER)
    ap.add_argument("--date", required=True, help="YYYY-MM-DD, written as `generated`")
    ap.add_argument("--sleep", type=float, default=0.5, help="seconds between live calls (default 0.5)")
    a = ap.parse_args()

    try:
        if not DATE.fullmatch(a.date):
            raise ValueError()
        datetime.date.fromisoformat(a.date)
    except ValueError:
        ap.error("--date must be a valid YYYY-MM-DD")
    if a.check and (a.out_lua or a.out_json or a.save_responses):
        ap.error("--check is read-only; output flags are not allowed")
    seeds = read_seeds(a.seeds)
    key = None
    if not a.dry_run:
        key = os.environ.get("RANGE_API_KEY", "").strip()
        if not key:
            sys.exit("error: RANGE_API_KEY is not set. Export it in the environment "
                     "(never pass it on the command line), or use --dry-run DIR.")
        if a.save_responses:
            os.makedirs(a.save_responses, exist_ok=True)

    entries, excluded, failures = [], [], []
    for i, addr in enumerate(seeds):
        try:
            if a.dry_run:
                body = load_saved(a.dry_run, addr)
            else:
                if i:
                    time.sleep(a.sleep)
                body = fetch(addr, key)
                if a.save_responses:
                    write(os.path.join(a.save_responses, addr + ".json"), json.dumps(scrub(body), indent=1) + "\n")
        except (RuntimeError, OSError, ValueError) as e:
            failures.append((addr, str(e)))
            continue
        t, reason = classify(addr, body)
        if t:
            entries.append({"a": addr, "t": t, "s": body["riskScore"]})
        else:
            excluded.append((addr, reason))

    entries, lua, js = build(entries, a.date)

    counts = {t: sum(1 for e in entries if e["t"] == t) for t in TYPE_ORDER}
    print(f"kept {len(entries)} of {len(seeds)}: " + ", ".join(f"{t}={counts[t]}" for t in TYPE_ORDER), file=sys.stderr)
    for addr, reason in excluded:
        print(f"excluded {addr}: {reason}", file=sys.stderr)
    for t in TYPE_ORDER:
        if counts[t] < MIN_PER_TYPE:
            print(f"warning: {t} has {counts[t]} entries (target {MIN_PER_TYPE})", file=sys.stderr)
    for addr, reason in failures:
        print(f"error: {addr}: {reason}", file=sys.stderr)
    missing = [t for t in TYPE_ORDER if not counts[t] and t not in a.allow_missing]
    if failures or missing:
        sys.exit("error: response failures or empty types: " + ", ".join(missing))
    path = a.write or a.check
    if path:
        try:
            with open(path, encoding="utf-8") as fh:
                original = fh.read()
            updated = replace_snapshot(original, lua)
        except (OSError, ValueError) as e:
            sys.exit(f"error: {e}")
        if a.check and original != updated:
            sys.exit(f"stale SNAPSHOT: {path}")
        if a.write and original != updated:
            write(path, updated)
        print(f"SNAPSHOT {'checked' if a.check else 'written'}: {path}")
    if a.out_lua:
        write(a.out_lua, lua)
    if a.out_json:
        write(a.out_json, js)
    if not path and not a.out_lua and not a.out_json:
        print(lua, end="")


if __name__ == "__main__":
    main()
