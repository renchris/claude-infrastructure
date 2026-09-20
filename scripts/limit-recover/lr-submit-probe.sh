#!/bin/bash
# lr-submit-probe.sh — did THIS run's prompt actually REACH the resumed session?
#
#   lr-submit-probe.sh <cfg-dir> <sid> <t0> <token>
#
# stdout, exactly one line:
#   submitted <ts>   a type:"user" record NEWER than <t0> whose content carries <token>
#   queued <ts>      a queue-operation/enqueue record carrying it (typed, but a turn is running)
#   none             neither — the prompt is not in the transcript at all
# rc 0 for all three. Non-zero ONLY when the question could not be asked:
#   2 usage · 3 no readable transcript for <sid> under <cfg> · 4 no python3.
#
# ══ WHY "none" AND "UNREADABLE" MUST NOT BE THE SAME ANSWER ══════════════════════════════════════
# `none` is a MEASUREMENT: the transcript was read and the token is not in it, so the prompt was
# never submitted and the caller must act (re-CR, or name the failure). An unreadable transcript is
# a REFUSAL: nothing was measured, and the same action taken on it types into a session whose state
# is unknown. This repo has paid for that conflation repeatedly — memory
# predicate-error-exit-is-indistinguishable-from-false and predicate-refusal-is-not-a-negative —
# most recently as a `||`-suppressed rc that read as a clean "no" for 20 of 20 rows. So the refusal
# leaves stdout EMPTY and exits non-zero, and every caller here tests for the word, never for rc.
#
# ══ THE SCAN IS TAIL-BOUNDED, AND THAT IS A CORRECTNESS CHOICE, NOT A SPEED ONE ══════════════════
# The question is only ever about the CURRENT run — a record newer than <t0>, which is captured
# immediately before the relaunch spawns. A transplanted transcript is tens of MB of history that
# predates <t0> by construction, and the expect poll runs this once a second for up to 30 s inside
# the pane. Measured (U08 §6): 19 ms at 400 KB on a 12 MB transcript. A `tail -c` starts MID-RECORD,
# so the first line is routinely a fragment — it fails to parse and is SKIPPED, exactly as
# lr_last_api_error does; a partial line is not a verdict.
#
# READ-ONLY AND RE-RUNNABLE BY CONSTRUCTION: it opens files, writes none, and holds no state, so the
# 1 s poll and the watcher's own call can both run it without interfering.
set -uo pipefail

CFG="${1:-}"; SID="${2:-}"; T0="${3:-}"; TOK="${4:-}"
if [ -z "$CFG" ] || [ -z "$SID" ] || [ -z "$TOK" ]; then
  echo "lr-submit-probe: usage: lr-submit-probe.sh <cfg-dir> <sid> <t0> <token>" >&2
  exit 2
fi
command -v /usr/bin/python3 >/dev/null 2>&1 || {
  echo "lr-submit-probe: /usr/bin/python3 is not available — submission CANNOT be measured (this is not 'none')" >&2
  exit 4
}

# The transcript glob is lr_engaged_after's, verbatim: Claude Code writes
# $cfg/projects/<project-slug>/<sid>.jsonl, one level down, and a session that moved worktrees has
# more than one slug. Every readable copy is scanned and the NEWEST hit wins.
LRP_TAIL="${LR_PROBE_TAIL_BYTES:-400000}"
case "$LRP_TAIL" in ''|*[!0-9]*) LRP_TAIL=400000 ;; esac
found=0
best_sub=""; best_q=""
for f in "$CFG"/projects/*/"$SID".jsonl; do
  [ -f "$f" ] && [ -r "$f" ] || continue
  found=1
  hit="$(tail -c "$LRP_TAIL" "$f" 2>/dev/null | /usr/bin/python3 -c '
import json, sys
t0, tok = sys.argv[1], sys.argv[2]
sub = q = ""
for line in sys.stdin:
    if tok not in line:            # cheap prefilter: the token is plain ASCII, so JSON escaping
        continue                   # cannot alter it and a substring miss is a real miss
    try:
        d = json.loads(line)
    except Exception:
        continue                   # a tail starts mid-record; a partial line is not a verdict
    ts = d.get("timestamp") or ""
    if ts <= t0:
        continue
    kind = d.get("type")
    if kind == "user":
        if d.get("isSidechain"):   # a subagent-thread record is not THIS session submitting
            continue
        m = d.get("message") if isinstance(d.get("message"), dict) else {}
        c = m.get("content")
        txt = c if isinstance(c, str) else (json.dumps(c) if c else "")
        if tok in txt and ts > sub:
            sub = ts
    elif kind == "queue-operation" and d.get("operation") == "enqueue":
        c = d.get("content")
        txt = c if isinstance(c, str) else (json.dumps(c) if c else "")
        if tok in txt and ts > q:
            q = ts
print(sub)
print(q)
' "$T0" "$TOK" 2>/dev/null)" || hit=""
  # TWO LINES, never one tab-separated line: a literal tab in shell source is the kind of byte an
  # editor, a patch tool or a copy-paste silently turns into spaces, and the split would then read
  # the WHOLE output as the submitted ts — a fabricated verdict rather than a parse error.
  s="$(printf '%s\n' "$hit" | sed -n 1p)"
  qq="$(printf '%s\n' "$hit" | sed -n 2p)"
  [ -n "$s" ] && [ "$s" \> "$best_sub" ] && best_sub="$s"
  [ -n "$qq" ] && [ "$qq" \> "$best_q" ] && best_q="$qq"
done

if [ "$found" = 0 ]; then
  echo "lr-submit-probe: no readable transcript at $CFG/projects/*/$SID.jsonl — submission NOT measured (this is not 'none')" >&2
  exit 3
fi
# SUBMITTED OUTRANKS QUEUED, and the order is not cosmetic: a prompt is enqueued first and becomes a
# user record when the running turn ends, so both records exist for every prompt that made it. The
# caller's two actions differ — `queued` means keep waiting, `submitted` means start the engagement
# clock — and reporting the earlier state of a prompt that has already landed would restart the wait.
if [ -n "$best_sub" ]; then
  printf 'submitted %s\n' "$best_sub"
elif [ -n "$best_q" ]; then
  printf 'queued %s\n' "$best_q"
else
  printf 'none\n'
fi
exit 0
