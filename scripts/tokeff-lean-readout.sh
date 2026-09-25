#!/bin/bash
# tokeff-lean-readout.sh — the 7-day realized-savings readout for the workflow-lean worker type
# (token-efficiency wave 2, item 8). It reports itself: a backlog row's falsifier runs `--falsify`,
# which after the window closes starts the readout, appends it to REPORT.md and lands it, and exits 0
# once origin/main carries it (which closes the row).
#
#   tokeff-lean-readout.sh [--since YYYY-MM-DD] [--until YYYY-MM-DD]   print the readout (markdown)
#   tokeff-lean-readout.sh --falsify            the row's probe: 1 = not yet / in progress, 0 = landed
#   tokeff-lean-readout.sh --append-and-land    compute, append to REPORT.md on a fresh worktree off
#                                               origin/main, commit, land with scripts/ship-land.sh
#
# THE ESTIMATE. `cc-token-ledger --by-agent-type` prices every worker context in the window by its
# agentType (from the transcript's .meta.json). The saving is estimated from the lean contexts' OWN
# measured spend and the re-gate's measured per-slot ratio (eval/GATE.md § Re-gate: workflow-lean cost
# 15.6% of the default workflow agent per slot, i.e. -84.4%): the same work on the default type would
# have cost spend / 0.156, so saving = spend x (1/0.156 - 1). The observed mean $ per default
# workflow-agent slot is printed beside it as a cross-check only: task mix differs between the types.
#
# WHY --falsify DETACHES. cc-premise runs a falsifier with a 20 s bound from the repo root, and a
# 7-day ledger scan plus a land does not fit. So the probe starts `--append-and-land` detached
# (scripts/lib/detach.sh) under a lock, returns 1 ("still live") while it runs, and returns 0 only when
# origin/main's REPORT.md carries the readout. A failed attempt is retried at most every 6 h; its log
# is ~/.claude/autonomy/tokeff/lean-readout.log.
# bash 3.2-safe.
set -uo pipefail

SELF="$(/usr/bin/python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")"
REPO="${TOKEFF_LEAN_REPO:-$(cd "$(dirname "$SELF")/.." && pwd)}"   # seam: tests point it at a fixture
SINCE="${TOKEFF_LEAN_SINCE:-2026-09-24}"
UNTIL="${TOKEFF_LEAN_UNTIL:-2026-10-01}"
GATE_RATIO="0.156"   # lean $ / default $ per slot, eval/GATE.md § Re-gate (-84.4%)
BASELINE_USD="32517" # list-weighted fleet spend per 14.96-day baseline window (REPORT.md § 1)
REPORT_REL="docs/research/token-efficiency-2026-09-23/REPORT.md"
MARK="Realized lean-worker saving, $SINCE"
STORE="${TOKEFF_LEAN_STORE:-$HOME/.claude/autonomy/tokeff}"
LEDGER="${TOKEFF_LEDGER_BIN:-$REPO/bin/cc-token-ledger}"
RETRY_S="${TOKEFF_LEAN_RETRY_S:-21600}"

MODE=print
while [ $# -gt 0 ]; do
  case "$1" in
    --since) [ $# -ge 2 ] || { echo "--since needs a date" >&2; exit 2; }; SINCE="$2"; MARK="Realized lean-worker saving, $SINCE"; shift 2 ;;
    --until) [ $# -ge 2 ] || { echo "--until needs a date" >&2; exit 2; }; UNTIL="$2"; shift 2 ;;
    --falsify) MODE=falsify; shift ;;
    --append-and-land) MODE=land; shift ;;
    -h|--help) sed -n '2,12p' "$SELF"; exit 0 ;;
    *) echo "tokeff-lean-readout: unknown argument $1" >&2; exit 2 ;;
  esac
done

epoch_of() { /usr/bin/python3 -c 'import sys,datetime; print(int(datetime.datetime.strptime(sys.argv[1], "%Y-%m-%d").timestamp()))' "$1"; }

# Eval traffic is not realized saving: the offline gates and probes run lean slots from scratch repos
# under /tmp and from the tokeff research worktrees, so those project slugs are left out.
EXCLUDE_SLUG="${TOKEFF_LEAN_EXCLUDE_SLUG:--private-tmp-|-tmp-|tokeff}"

# shellcheck disable=SC2016  # the python program is single-quoted on purpose; $ there is Python's
readout() { # prints one markdown paragraph, or fails
  local js
  js="$("$LEDGER" --by-agent-type --exclude-slug="$EXCLUDE_SLUG" --since "$SINCE" --until "$UNTIL" --json)" || return 1
  printf '%s' "$js" | /usr/bin/python3 -c '
import json, sys
d = json.load(sys.stdin)
since, until, ratio, base = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
rows = d["agent_types"]
lean = [r for r in rows if r["agent_type"] == "workflow-lean"]
n = sum(r["contexts"] for r in lean)
nw = sum(r["contexts"] for r in lean if r["ctx_type"] == "workflow_agent")
spend = sum(r["usd_total"] for r in lean)
spend_re = sum(r["usd_total_reprice"] for r in lean)
save = spend * (1 / ratio - 1)
save_re = spend_re * (1 / ratio - 1)
from datetime import date
days = (date.fromisoformat(until) - date.fromisoformat(since)).days or 1
per_window = save / days * 14.96
heavy = [r for r in rows if r["ctx_type"] == "workflow_agent" and r["agent_type"] == "workflow-subagent"]
hn = sum(r["contexts"] for r in heavy)
hmean = (sum(r["usd_total"] for r in heavy) / hn) if hn else None
lw = [r for r in lean if r["ctx_type"] == "workflow_agent"]
lmean = (sum(r["usd_total"] for r in lw) / nw) if nw else None
fmt = lambda x: "n/a" if x is None else "$%.2f" % x
print(("- **Realized lean-worker saving, %s to %s** (measured by `cc-token-ledger --by-agent-type --since %s --until %s "
       "--exclude-slug=\x27" + sys.argv[5] + "\x27`, which leaves out %d eval/probe worker contexts): "
       "%d `workflow-lean` worker contexts (%d workflow slots, %d subagents) cost $%.2f at list weights ($%.2f at Opus 5.5). "
       "At the re-gate'"'"'s measured per-slot ratio (lean = %.1f%% of the default worker), the same work on the default type would "
       "have cost $%.2f more: **saving about $%.2f list ($%.2f at Opus 5.5) over %d days, about $%.0f per 14.96-day window, "
       "%.1f%% of the $%s baseline** (estimated from measured spend x the gated ratio). Cross-check, not the estimate: mean "
       "per workflow slot %s lean vs %s for `workflow-subagent` (%d slots); task mix differs between the two.") % (
    since, until, since, until, d.get("excluded_contexts", 0), n, nw, n - nw, spend, spend_re, ratio * 100, save, save, save_re, days, per_window,
    100 * per_window / base, "{:,}".format(int(base)), fmt(lmean), fmt(hmean), hn))
' "$SINCE" "$UNTIL" "$GATE_RATIO" "$BASELINE_USD" "$EXCLUDE_SLUG"
}

landed() { # 0 when origin/main's REPORT.md already carries this window's readout
  timeout 15 git -C "$REPO" fetch -q origin main 2>/dev/null
  git -C "$REPO" show "origin/main:$REPORT_REL" 2>/dev/null | grep -qF "$MARK"
}

case "$MODE" in
print)
  readout ;;

falsify)
  now="$(date +%s)"; due="$(epoch_of "$UNTIL")"
  if [ "$now" -lt "$due" ]; then
    echo "not yet: the $SINCE..$UNTIL window closes at $UNTIL"; exit 1
  fi
  if landed; then echo "landed: origin/main $REPORT_REL carries \"$MARK\""; exit 0; fi
  mkdir -p "$STORE"
  if [ -f "$STORE/lean-readout.pid" ] && kill -0 "$(cat "$STORE/lean-readout.pid" 2>/dev/null)" 2>/dev/null; then
    echo "in progress: pid $(cat "$STORE/lean-readout.pid"), log $STORE/lean-readout.log"; exit 1
  fi
  last="$(cat "$STORE/lean-readout.last-attempt" 2>/dev/null || echo 0)"
  case "$last" in ''|*[!0-9]*) last=0 ;; esac
  if [ $((now - last)) -lt "$RETRY_S" ]; then
    echo "retry pending: last attempt $(( (now - last) / 60 )) min ago failed, see $STORE/lean-readout.log"; exit 1
  fi
  echo "$now" > "$STORE/lean-readout.last-attempt"
  # shellcheck disable=SC1091  # resolved at run time from this script's real path
  . "$REPO/scripts/lib/detach.sh"
  pid="$(detach "$STORE/lean-readout.log" bash "$SELF" --append-and-land)" || { echo "could not start the readout"; exit 1; }
  echo "$pid" > "$STORE/lean-readout.pid"
  echo "started: readout + land as pid $pid, log $STORE/lean-readout.log"; exit 1 ;;

land)
  echo "── $(date '+%Y-%m-%dT%H:%M:%S%z') tokeff-lean-readout --append-and-land ($SINCE..$UNTIL)"
  if landed; then echo "already landed"; exit 0; fi
  line="$(readout)" || { echo "readout FAILED (cc-token-ledger)"; exit 1; }
  [ -n "$line" ] || { echo "readout empty"; exit 1; }
  printf '%s\n' "$line"
  br="tokeff/lean-readout-$SINCE"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/tokeff-lean-readout.XXXXXX")/wt"
  git -C "$REPO" worktree add -q -B "$br" "$wt" origin/main || { echo "worktree add FAILED"; exit 1; }
  /usr/bin/python3 - "$wt/$REPORT_REL" "$line" <<'PY'
import sys
path, line = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
head = "## 6. Realized savings (post-ship readouts)"
if head not in text:
    text = text.rstrip("\n") + "\n\n" + head + "\n\n"
else:
    text = text.rstrip("\n") + "\n"
open(path, "w", encoding="utf-8").write(text + line + "\n")
PY
  git -C "$wt" add "$REPORT_REL" \
    && git -C "$wt" commit -q -m "docs(research): realized workflow-lean saving, $SINCE to $UNTIL" \
         -m "Appended by scripts/tokeff-lean-readout.sh --append-and-land (the backlog row's falsifier)." \
    || { echo "commit FAILED"; exit 1; }
  (cd "$wt" && bash scripts/ship-land.sh); rc=$?
  echo "ship-land rc=$rc"
  if [ "$rc" -eq 0 ] && landed; then
    git -C "$REPO" worktree remove --force "$wt" 2>/dev/null; git -C "$REPO" branch -D "$br" 2>/dev/null
    rm -f "$STORE/lean-readout.pid"; echo "LANDED"; exit 0
  fi
  rm -f "$STORE/lean-readout.pid"; echo "NOT landed; worktree kept at $wt"; exit 1 ;;
esac
