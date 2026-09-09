#!/usr/bin/env python3
"""Read one fact out of a schema-1 harvest proposal, for a bats arm to compare against.

WHY NOT jq. Three of the questions these suites ask are not selections but ARITHMETIC over the
document — do the MECE buckets sum to `inputs.rows`, which gate verdict does a rule carry whether
it was proposed or refused, is a head present under any token count — and a jq program long enough
to answer them is unreadable inside a `[ "$(...)" = x ]`. Worse, a jq filter that matches NOTHING
prints `null` and exits 0, so a typo'd path and a genuinely-absent field are the same observation:
the arm goes green over a question it never asked. Every subcommand here is EXPLICIT about absence
(it prints a distinguishable token and exits non-zero) so a missing field fails the arm instead of
passing it.

Absence tokens, deliberately not empty strings: `MISSING` (no such rule anywhere), `NOGATE` (rule
found, gate not recorded). Exit 0 = answered, 1 = the object asked for is absent, 2 = usage.

Usage:
  qjson.py <proposal.json> proposed                 → every proposed rule, one per line
  qjson.py <proposal.json> refused                  → every refused rule, one per line
  qjson.py <proposal.json> has <RULE>               → exit 0 iff RULE is proposed
  qjson.py <proposal.json> head-proposed <HEAD>     → exit 0 iff some proposed rule has this head
  qjson.py <proposal.json> code <RULE>              → the refusal code, or MISSING
  qjson.py <proposal.json> gate <RULE> <GATE>       → the gate verdict, or MISSING/NOGATE
  qjson.py <proposal.json> get <dotted.path>        → a compact JSON value (absent ⇒ exit 1)
  qjson.py <proposal.json> receipt <RULE> <FIELD>   → one field of a proposed rule's receipt
  qjson.py <proposal.json> bucketsum                → "rows=<n> sum=<n>"
  qjson.py <proposal.json> consolidation <SUBSTR>   → matching entries as "<file>\t<prefix>"
  qjson.py <proposal.json> cons-gate <SUBSTR> <G>   → that cluster's gate verdict
  qjson.py <proposal.json> cons-shadows <SUBSTR>    → the entries a consolidation prefix shadows
  qjson.py <proposal.json> unretirable <HEAD>       → that residue cluster's reason
  qjson.py <proposal.json> unretirable-entries <HEAD> → that residue cluster's entry count
  qjson.py <proposal.json> scopes                   → "fleet=<n> project=<n> worktree=<n>"
"""

from __future__ import annotations

import json
import sys

MISSING = "MISSING"
NOGATE = "NOGATE"


def _head_of(rule):
    """`Bash(gh pr view:*)` → `gh pr view`. Non-Bash / non-prefix rules yield their raw content."""
    r = rule.strip()
    if r.startswith("Bash(") and r.endswith(")"):
        r = r[5:-1]
    for suffix in (":*", " *", "*"):
        if r.endswith(suffix):
            return r[: -len(suffix)].strip()
    return r.strip()


def _find(doc, rule):
    for entry in doc.get("proposed") or []:
        if entry.get("rule") == rule:
            return entry
    for entry in doc.get("refused") or []:
        if entry.get("rule") == rule:
            return entry
    for entry in doc.get("consolidation") or []:
        if entry.get("prefix") == rule:
            return entry
    return None


def _cons(doc, substr):
    return [
        e
        for e in (doc.get("consolidation") or [])
        if substr in (e.get("prefix") or "") or substr in (e.get("file") or "")
    ]


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    with open(argv[1], encoding="utf-8") as fh:
        doc = json.load(fh)
    op = argv[2]
    rest = argv[3:]

    if op == "proposed":
        for e in doc.get("proposed") or []:
            print(e.get("rule", ""))
        return 0
    if op == "refused":
        for e in doc.get("refused") or []:
            print(e.get("rule", ""))
        return 0
    if op == "has":
        found = any(e.get("rule") == rest[0] for e in (doc.get("proposed") or []))
        print("yes" if found else "no")
        return 0 if found else 1
    if op == "head-proposed":
        found = any(
            _head_of(e.get("rule", "")) == rest[0] for e in (doc.get("proposed") or [])
        )
        print("yes" if found else "no")
        return 0 if found else 1
    if op == "code":
        for e in doc.get("refused") or []:
            if e.get("rule") == rest[0]:
                print(e.get("code", NOGATE))
                return 0
        print(MISSING)
        return 1
    if op == "gate":
        entry = _find(doc, rest[0])
        if entry is None:
            print(MISSING)
            return 1
        gates = entry.get("gates") or {}
        if rest[1] in gates:
            print(gates[rest[1]])
            return 0
        # A refused entry carries ONE `code` rather than a gate map — that IS the verdict.
        if entry.get("code") == rest[1]:
            print("refuse")
            return 0
        print(NOGATE)
        return 1
    if op == "receipt":
        entry = None
        for e in doc.get("proposed") or []:
            if e.get("rule") == rest[0]:
                entry = e
                break
        if entry is None:
            print(MISSING)
            return 1
        cur = entry
        for part in rest[1].split("."):
            if not isinstance(cur, dict) or part not in cur:
                print(MISSING)
                return 1
            cur = cur[part]
        print(json.dumps(cur) if isinstance(cur, (dict, list)) else cur)
        return 0
    if op == "get":
        cur = doc
        for part in rest[0].split("."):
            if isinstance(cur, list):
                try:
                    cur = cur[int(part)]
                    continue
                except (ValueError, IndexError):
                    print(MISSING)
                    return 1
            if not isinstance(cur, dict) or part not in cur:
                print(MISSING)
                return 1
            cur = cur[part]
        print(json.dumps(cur) if isinstance(cur, (dict, list)) else cur)
        return 0
    if op == "bucketsum":
        buckets = doc.get("buckets") or {}
        rows = (doc.get("inputs") or {}).get("rows")
        if rows is None or not buckets:
            print("rows=MISSING sum=MISSING")
            return 1
        print("rows=%s sum=%s" % (rows, sum(int(v) for v in buckets.values())))
        return 0
    if op == "consolidation":
        hits = _cons(doc, rest[0])
        for e in hits:
            print("%s\t%s" % (e.get("file", ""), e.get("prefix", "")))
        return 0 if hits else 1
    if op == "cons-gate":
        hits = _cons(doc, rest[0])
        if not hits:
            print(MISSING)
            return 1
        gates = hits[0].get("gates") or {}
        print(gates.get(rest[1], NOGATE))
        return 0 if rest[1] in gates else 1
    if op == "cons-shadows":
        hits = _cons(doc, rest[0])
        if not hits:
            print(MISSING)
            return 1
        for s in hits[0].get("shadows") or []:
            print(s)
        return 0
    if op == "unretirable":
        for e in doc.get("unretirable") or []:
            if e.get("head") == rest[0]:
                print(e.get("reason", NOGATE))
                return 0
        print(MISSING)
        return 1
    if op == "unretirable-entries":
        for e in doc.get("unretirable") or []:
            if e.get("head") == rest[0]:
                print(e.get("entries", MISSING))
                return 0 if "entries" in e else 1
        print(MISSING)
        return 1
    if op == "scopes":
        files = (doc.get("inputs") or {}).get("settings_files")
        if not isinstance(files, list):
            print(MISSING)
            return 1
        counts = {"fleet": 0, "project": 0, "worktree": 0}
        for f in files:
            s = (f or {}).get("scope")
            counts[s] = counts.get(s, 0) + 1
        print(" ".join("%s=%d" % (k, counts[k]) for k in sorted(counts)))
        return 0

    sys.stderr.write("unknown op: %s\n" % op)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
