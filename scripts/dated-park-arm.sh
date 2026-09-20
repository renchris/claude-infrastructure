#!/bin/bash
# dated-park-arm.sh — the standing watch over DATED PARKS in the backlog.
#
# ── WHAT A DATED PARK IS ──────────────────────────────────────────────────────────────────────────
# A `not-yet-true` row whose precondition is a CLOCK and nothing else: the work is fully specified
# and an agent could do it, but not until a named date. The house disposition for such a row is
# `cc-backlog block <id> --needs "On or after YYYY-MM-DD, ..."` — `blocked` is what removes it from
# the dispatch wave (`cc-dispatch` filters `status=="open"` at step 1, and its own comment calls
# `blocked` "the re-dispatch loop `blocked` exists to break").
#
# ── WHY THE WATCH EXISTS: A PARK WITH NO OWNER IS AN ABANDONMENT ──────────────────────────────────
# Blocking stops the loop and creates a second problem in its place. NOTHING in the tree reads a
# blocked row's `needs` prose, so a dated park is invisible on the day it becomes actionable: the
# date passes, no sensor fires, and the row waits on a human who has no reason to look. That is the
# measured failure class `filed-blocker-is-never-revalidated` — a blocked row is filed once and
# never re-checked, so a dead premise demands action forever and a LIVE one demands none.
# A detector with no owner is not an actuator. This script is the owner.
#
# 🚨 THIS IS AN ARMING PROBE AND MUST NEVER BE STORED AS A ROW'S `--falsifier`. The two questions
# have OPPOSITE polarity and the `--falsifier` field holds only the other one. `cc-premise` reads a
# falsifier's exit 0 as "the condition this row was filed for is GONE — close it". This probe exits
# 0 when a parked row's date ARRIVES, i.e. at the exact instant the row becomes actionable. Stored
# as a falsifier it would DELETE every row it was meant to wake. That is not hypothetical: backlog
# `2a65b9bf722d` shipped precisely that inverted gate and was repointed to `--moot` on 2026-09-17,
# and `b1432e348362` (D1) shipped it again and was cleared at the 2026-09-20 close-out.
# Record: docs/lessons/arming-and-mootness-cannot-share-one-falsifier.md.
# This arm PAGES and touches no store — same disposition as autonomy-sweep §2b-iii-b.
#
# ── THE ANCHOR PHRASE, AND WHY IT IS ANCHORED AT THE START ────────────────────────────────────────
# A park is recognised by its `needs` prose BEGINNING with `On or after <YYYY-MM-DD>`. Anchoring at
# the start is deliberate and conservative: a blocked row may mention a date anywhere in its prose
# for a hundred reasons, and matching those would page on rows nobody parked. The failure direction
# is therefore a MISS (a park worded differently is unwatched), never a false page — the right
# polarity for an alarm whose budget is the operator's attention. Rows written by the close-out
# convention already conform; write new dated parks with this phrase FIRST.
#
# ── EXIT CODES (0 = SIGNAL · 1 = no signal · 2 = NON-VERDICT) ─────────────────────────────────────
# The 2 is load-bearing and is the same contract propose-goal-flag-watch.sh states: a mode that
# CANNOT answer must not spend the "no" code. A consumer reading only `rc != 0` would otherwise read
# "the ledger was unreadable" as "no park has armed", and the watch would go blind in exactly the
# silent direction — an unreadable store is not an empty one.
#   0  at least one dated park has ARMED (its date is today or past)  → the sweep pages
#   1  dated parks exist (or none do) and NONE has armed              → healthy steady state
#   2  NON-VERDICT: the ledger is absent/unreadable, or python3 is missing
#
# Modes: --arm (detector, default) · --report (human listing of every dated park and its state)
# CC_DATED_PARK_TODAY overrides "today" (YYYY-MM-DD) — the test seam; unset in production.

set -uo pipefail

MODE=arm
for a in "$@"; do
  case "$a" in
    --arm)    MODE=arm ;;
    --report) MODE=report ;;
    -h|--help) sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'dated-park-arm: unknown argument: %s\n' "$a" >&2; exit 2 ;;
  esac
done

LEDGER="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
TODAY="${CC_DATED_PARK_TODAY:-$(date -u +%Y-%m-%d)}"

command -v python3 >/dev/null 2>&1 || {
  printf 'dated-park-arm: python3 not found — NON-VERDICT\n' >&2; exit 2; }
[ -r "$LEDGER" ] || {
  printf 'dated-park-arm: ledger unreadable: %s — NON-VERDICT\n' "$LEDGER" >&2; exit 2; }

MODE="$MODE" LEDGER="$LEDGER" TODAY="$TODAY" python3 - <<'PY'
import json, os, re, sys

ledger, today, mode = os.environ["LEDGER"], os.environ["TODAY"], os.environ["MODE"]
if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", today):
    print(f"dated-park-arm: bad today '{today}' — NON-VERDICT", file=sys.stderr); sys.exit(2)

# The fold: the ledger is append-only and an item's state is its LAST transition. `needs` is carried
# forward from whichever record last set it, exactly as cc-backlog's own fold does.
TRANSITIONS = ("add", "done", "block", "reopen", "unblock", "needs")
fold, parse_fail, total = {}, 0, 0
try:
    with open(ledger, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if not line.strip():
                continue
            total += 1
            try:
                d = json.loads(line)
            except Exception:
                parse_fail += 1          # a parse failure is a VERDICT, never noise
                continue
            i = d.get("id")
            if not i:
                continue
            r = fold.setdefault(i, {})
            if d.get("event") in TRANSITIONS:
                r["st"] = d["event"]
            for k in ("needs", "title"):
                if d.get(k):
                    r[k] = d[k]
except OSError as e:
    print(f"dated-park-arm: cannot read ledger: {e} — NON-VERDICT", file=sys.stderr); sys.exit(2)

# Every line unparseable over a non-empty file means the store is not what we think it is.
if total and parse_fail == total:
    print(f"dated-park-arm: all {total} ledger lines unparseable — NON-VERDICT", file=sys.stderr)
    sys.exit(2)

# NO `^` IN THE PATTERN, DELIBERATELY. `re.match` already anchors at position 0, so a `^` here
# would be a SECOND, redundant guard — and two independent guards over one assertion make that
# assertion unreachable by single-point mutation: tests/dated-park-arm.bats M1 was tried against
# both spellings and could kill neither while the redundancy stood. One mechanism, one mutant, a
# suite that can actually prove the anchoring is live.
ANCHOR = re.compile(r"On or after (\d{4}-\d{2}-\d{2})")
parks = []
for i, r in fold.items():
    if r.get("st") != "block":
        continue
    # `.match` is what anchors this at position 0 — the pattern's `^` is documentation, not the
    # mechanism, and swapping in `.search` is the derangement tests/dated-park-arm.bats M1 kills.
    m = ANCHOR.match((r.get("needs") or "").lstrip())
    if m:
        parks.append((m.group(1), i, r.get("title", "")))
parks.sort()

armed = [p for p in parks if p[0] <= today]     # string compare is correct on zero-padded ISO dates

if mode == "report":
    print(f"dated parks: {len(parks)}   armed (date <= {today}): {len(armed)}")
    if parse_fail:
        print(f"  note: {parse_fail}/{total} ledger lines unparseable (reported, not dropped)")
    for date, i, title in parks:
        state = "ARMED" if date <= today else "waiting"
        print(f"  {state:7s} {date}  {i}  {title[:64]}")
else:
    for date, i, title in armed:
        print(f"ARMED {date} {i} {title[:80]}")

sys.exit(0 if armed else 1)
PY
