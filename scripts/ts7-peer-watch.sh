#!/bin/bash
# ts7-peer-watch.sh — the standing watch that replaced reso backlog row 9d64a995322a
# ("TypeScript 7 coexistence — READY, waiting on ONE upstream trigger").
#
# ── WHY THIS EXISTS ───────────────────────────────────────────────────────────────────────────────
# reso can add TS 7 (`@typescript/native`) beside TS 6 the day typescript-eslint's peer range admits
# it: TS 7 type-checks reso's unmodified tsconfig with 0 errors (~7.7x faster), and the only blocker
# is typescript-eslint, whose `peerDependencies.typescript` was '>=4.8.4 <6.1.0' on 8.71.0 and whose
# dist throws on `versionMajor >= 7`. The groundwork landed in reso already: every gate call site runs
# node_modules/typescript/bin/tsc by path, so a second tsc bin cannot swap the gate compiler. What was
# left was a WAIT, and a blocked row nobody re-reads is a wait nobody ends (the
# filed-blocker-is-never-revalidated class). So the row closed and this watch owns the trigger:
# autonomy-sweep §2b-iii-e runs `--arm` every sweep and pages the desk when it exits 0.
#
# ── EXIT CODES (0 = SIGNAL · 1 = no signal · 2 = NON-VERDICT) ─────────────────────────────────────
#   --arm     0 = typescript-eslint@latest's peer range ADMITS typescript 7.0.0 — go add TS 7.
#             1 = observed, still capped below 7 — keep waiting.
#             2 = NON-VERDICT: the registry could not be read or the range could not be parsed.
#                 Means "could not ask", never "still capped".
#   --report  prints the observed range, the verdict, and the reso recipe; exits like --arm.
#
# 🚨 NEVER store `--arm` as a backlog row's --falsifier: exit 0 means "the work just became
# actionable", which cc-premise would read as "close it" (docs/lessons/
# arming-and-mootness-cannot-share-one-falsifier.md). It pages; it writes no store.
#
# Env (test seams): CC_TS7_PEER_JSON=<file> reads the package document from a file instead of the
# registry; CC_TS7_REGISTRY_URL overrides the URL; CC_TS7_FETCH_TIMEOUT_S bounds the fetch (10).
set -uo pipefail

MODE="${1:---arm}"
case "$MODE" in --arm|--report) ;; *) echo "usage: ts7-peer-watch.sh --arm|--report" >&2; exit 2 ;; esac

URL="${CC_TS7_REGISTRY_URL:-https://registry.npmjs.org/typescript-eslint/latest}"
if [ -n "${CC_TS7_PEER_JSON:-}" ]; then
  doc="$(cat "$CC_TS7_PEER_JSON" 2>/dev/null)" || doc=""
else
  doc="$(curl -fsS --max-time "${CC_TS7_FETCH_TIMEOUT_S:-10}" "$URL" 2>/dev/null)" || doc=""
fi

# The verdict is computed in ONE python process and printed as "<rc> <version> <range>" so the rc
# survives (an assignment inside $( ) never escapes it) and the report reads the same answer.
verdict="$(printf '%s' "$doc" | python3 -c '
import json, re, sys

def parse(v):
    m = re.match(r"^v?(\d+)(?:\.(\d+|x|\*))?(?:\.(\d+|x|\*))?", v.strip())
    if not m:
        raise ValueError(v)
    return tuple(int(p) if p and p.isdigit() else 0 for p in m.groups())

def ok(op, bound, t):
    return {"<": t < bound, "<=": t <= bound, ">": t > bound, ">=": t >= bound, "=": t == bound}[op]

def comparator(c, t):
    c = c.strip()
    if c in ("", "*", "x", "X"):
        return True
    m = re.match(r"^(<=|>=|<|>|=|\^|~)?\s*(.+)$", c)
    op, ver = m.group(1) or "=", m.group(2)
    b = parse(ver)
    if op == "^":
        upper = (b[0] + 1, 0, 0) if b[0] > 0 else ((0, b[1] + 1, 0) if b[1] > 0 else (0, 0, b[2] + 1))
        return b <= t < upper
    if op == "~":
        return b <= t < (b[0], b[1] + 1, 0)
    if op == "=" and re.search(r"\.(x|\*)|^\d+$|^\d+\.\d+$", ver.strip()):
        parts = ver.strip().split(".")
        return all(p in ("x", "*") or int(p) == t[i] for i, p in enumerate(parts))
    return ok(op, b, t)

try:
    d = json.loads(sys.stdin.read())
    rng = d["peerDependencies"]["typescript"]
    version = d.get("version", "?")
    target = (7, 0, 0)
    admitted = any(
        all(comparator(c, target) for c in re.sub(r"(<=|>=|<|>|=)\s+", r"\1", alt).split())
        for alt in rng.split("||")
    )
    print("%d %s %s" % (0 if admitted else 1, version, rng))
except Exception:
    print("2 ? ?")
' 2>/dev/null)"
[ -n "$verdict" ] || verdict="2 ? ?"
rc="${verdict%% *}"
rest="${verdict#* }"
version="${rest%% *}"
range="${rest#* }"

if [ "$MODE" = "--report" ]; then
  case "$rc" in
    0) word="ADMITTED — typescript-eslint@${version} accepts TypeScript 7" ;;
    1) word="still capped — typescript-eslint@${version} requires typescript '${range}'" ;;
    *) word="NO VERDICT — could not read or parse ${URL} (this is not 'still capped')" ;;
  esac
  echo "ts7-peer-watch: ${word}"
  if [ "$rc" = "0" ]; then
    echo "next, in reso-management-app: add \"@typescript/native\": \"npm:typescript@^7\" to devDependencies,"
    echo "pnpm install, and keep the gate on node_modules/typescript/bin/tsc (already pinned at every call site)."
    echo "then re-file the work: cc-backlog add --project reso-management-app --title 'add TS 7 beside TS 6 (typescript-eslint admits it)'"
  fi
fi
exit "$rc"
