#!/usr/bin/env bash
# bg-fd-inherit-lint.sh — a backgrounded child in a HOOK must not inherit stdout.
#
# THE FAILURE THIS EXISTS FOR (backlog 50627335fe9b). A hook's stdout is a PIPE the harness reads,
# and the read does not see EOF until every descriptor on the write end is closed. Backgrounding a
# command does not close one, and `disown` does not either — it removes the job from the shell's
# table and leaves the file descriptor exactly where it was. So a hook can exit cleanly, its own
# frame complete, while a detached grandchild holds the pipe open and the harness blocks on a
# writer that is no longer a hook and no longer anyone's child.
#
# Measured: pane 113 wedged 54 MINUTES with an advancing hook timer and ZERO hook children,
# recovered only by a human pressing Escape. It presented as "hook #12 of 13 is slow" and was
# nothing of the kind — every Stop hook carries a 5-10s timeout (~75s for the whole chain) against
# a 54-minute stall, 43x, because a timeout cannot reach a descriptor. The culprit was
# `afplay … 2>>LOG &` in hooks/notify.sh: stderr resolved, stdout inherited.
#
# WHY A STATIC LINT AND NOT A RUNTIME DETECTOR. The row asked for a runtime alarm keyed on the
# conjunction "hook frame displayed AND no hook child". Axis A does not exist: measured against the
# 2.1.220 binary every pane on this box runs, the only hook frame it renders is the PAST-TENSE
# `Ran <N> <Label> hooks` — a count with no denominator — and there are zero hits for
# hooksRunning / runningHooks / pendingHooks / hookProgress. There is no in-flight fraction
# anywhere in the hook render path, so the prescribed anchor cannot be keyed on at all. A detector
# built on it would be a heuristic wearing an exact detector's clothes. The condition IS statically
# visible in the source, so it is checked there instead — and unlike a runtime alarm this one
# cannot fire on a healthy machine.
#
# ALARM BUDGET — and the first estimate here was WRONG, which is worth recording rather than
# quietly editing. This header predicted "expected fire rate exactly 1 (hooks/notify.sh)", on the
# strength of a census that had looked only at the twelve Stop hooks. The first live run over all
# 73 hook files found FIVE, and every one of them is real:
#   hooks/notify.sh              afplay … 2>>LOG &   — the measured pane-113 culprit
#   hooks/session-start.sh:46    "$PRUNE_SCRIPT" &   — wholly unredirected background script
#   hooks/plan-version-commit.sh ( … git commit … ) & — git commit WRITES to the inherited stdout
#   hooks/session-end.sh × 2     ( … ) &             — backgrounded subshells holding the pipe
#   hooks/session-index-start.sh ( … ) &             — same shape
# All five are fixed in the same commit, so the steady-state rate is 0 and any future finding is
# news. The correction matters beyond the number: the class was FIVE TIMES more common than the
# single incident suggested, so "one bad line" was never the right model of it — and a subshell
# holds the descriptor whether or not it ever writes, which is why four of the five look harmless.
# hooks/session-beat.sh remains the standing positive control: it backgrounds and redirects BOTH
# descriptors, so a lint that flagged it would be over-wide.
#
# Usage: bg-fd-inherit-lint.sh [--dir hooks] [--selftest]
# Exit: 0 clean · 1 finding(s) · 2 could not run (a NON-VERDICT, never a clean claim).
set -uo pipefail

DIR="${1:-}"; [ "$DIR" = "--dir" ] && { DIR="${2:?--dir needs a path}"; shift 2; } || DIR=""
SELFTEST=0
for a in "$@"; do [ "$a" = "--selftest" ] && SELFTEST=1; done
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${DIR:-$REPO/hooks}"

# A line is a FINDING when it backgrounds a command (`&` at end, not `&&`) and redirects neither
# stdout explicitly (`>`/`1>`/`&>`/`>&`) nor everything to a file. Deliberately narrow: the cost of
# a false positive here is a developer arguing with a lint, and the cost of over-matching is that
# the lint gets disabled and the wedge comes back.
# FD-QUALIFIED REDIRECTS ARE STRIPPED BEFORE THE STDOUT TEST, and getting that backwards is how the
# first draft shipped a lint that could not catch its own motivating bug. The test was
# `/(^|[^0-9&])1?>[^&]/ ⇒ not a finding`, which matches the SECOND `>` of `2>>` (its predecessor is
# `>`, not a digit) — so `afplay … 2>>"$LOG" &`, the exact line that wedged pane 113 for 54
# minutes, was read as having stdout redirected and waved through. The selftest's positive control
# is what surfaced it; without that control this lint would have run clean over the live tree and
# certified the defect it was written for.
scan_file() { # $1=path → prints "line:text" per finding
  awk '
    # Strip comments before matching: a commented-out example must never be a finding, and this
    # file itself quotes the bad shape in its own header.
    { line = $0; sub(/[[:space:]]*#.*$/, "", line) }
    line !~ /&[[:space:]]*$/ { next }          # not backgrounded
    line ~ /&&[[:space:]]*$/ { next }          # a line-continuation AND, not a background
    line ~ /&>/              { next }          # both descriptors redirected
    line ~ />&/              { next }          # fd duplication (>&1, >&2)
    {
      # Remove every fd-QUALIFIED redirect (2> 2>> 3> …). What survives can only be a bare stdout
      # redirect, so the presence test afterwards is exact rather than a pattern guess.
      probe = line
      gsub(/[0-9]+>>?/, "", probe)
    }
    probe ~ />/              { next }          # stdout goes somewhere explicit
    line ~ /^[[:space:]]*$/  { next }
    { printf "%d:%s\n", NR, $0 }
  ' "$1"
}

if [ "$SELFTEST" = 1 ]; then
  # POSITIVE CONTROL FIRST — a lint that cannot fail certifies nothing. The fixture replays the
  # exact pre-fix notify.sh line, and the control asserts it is CAUGHT before anything asserts the
  # real tree is clean.
  t="$(mktemp -d)" || { echo "bg-fd-inherit-lint: selftest could not mktemp" >&2; exit 2; }
  trap 'rm -rf "$t"' EXIT
  # shellcheck disable=SC2016
  # These are LITERAL SHELL SOURCE being written into fixture files; expanding $S/$LOG here would
  # write the harness's own empty values and destroy the shape under test.
  printf '%s\n' '#!/bin/bash' 'afplay "$S" 2>> "$LOG" &' 'disown' > "$t/bad.sh"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/bash' 'afplay "$S" >/dev/null 2>> "$LOG" &' > "$t/good.sh"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/bash' 'sleep 1 >>"$OUT" 2>&1 &' > "$t/good2.sh"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/bash' '# afplay "$S" 2>>"$LOG" &' > "$t/comment.sh"
  # A backgrounded SUBSHELL — the shape four of the five live findings actually had, and the one a
  # line-oriented lint is most likely to miss, since the redirects live on the inner lines.
  printf '%s\n' '#!/bin/bash' '(' '  git commit -m x 2>/dev/null' ') &' > "$t/subshell.sh"
  printf '%s\n' '#!/bin/bash' '(' '  git commit -m x 2>/dev/null' ') >/dev/null &' > "$t/subshell-ok.sh"
  fail=0
  [ -n "$(scan_file "$t/bad.sh")" ]        || { echo "SELFTEST FAIL: the pre-fix shape was NOT caught"; fail=1; }
  [ -n "$(scan_file "$t/subshell.sh")" ]   || { echo "SELFTEST FAIL: an unredirected background SUBSHELL was NOT caught"; fail=1; }
  [ -z "$(scan_file "$t/good.sh")" ]       || { echo "SELFTEST FAIL: >/dev/null flagged"; fail=1; }
  [ -z "$(scan_file "$t/good2.sh")" ]      || { echo "SELFTEST FAIL: file redirect flagged"; fail=1; }
  [ -z "$(scan_file "$t/subshell-ok.sh")" ] || { echo "SELFTEST FAIL: a redirected subshell flagged"; fail=1; }
  [ -z "$(scan_file "$t/comment.sh")" ]    || { echo "SELFTEST FAIL: a COMMENT flagged"; fail=1; }
  [ "$fail" = 0 ] && echo "bg-fd-inherit-lint: selftest 6/6 GREEN (positive controls caught the real pre-fix line AND the subshell shape)"
  exit "$fail"
fi

[ -d "$DIR" ] || { echo "bg-fd-inherit-lint: no such directory $DIR — NON-VERDICT" >&2; exit 2; }

n_files=0 n_find=0
while IFS= read -r f; do
  n_files=$((n_files + 1))
  hits="$(scan_file "$f")"
  [ -n "$hits" ] || continue
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    n_find=$((n_find + 1))
    printf '  %s:%s\n' "$f" "$h"
  done <<<"$hits"
done <<EOF
$(find "$DIR/" -maxdepth 1 -name '*.sh' -type f 2>/dev/null | sort)
EOF

if [ "$n_find" -gt 0 ]; then
  printf 'bg-fd-inherit-lint: %d backgrounded child(ren) inheriting stdout across %d hook file(s).\n' \
    "$n_find" "$n_files"
  printf '  A hook stdout is a pipe the harness reads; a detached grandchild holding it open wedges\n'
  printf '  the chain with no live hook child and no timeout able to reach it.\n'
  printf '  FIX: add >/dev/null (or a file redirect) to the backgrounded command.\n'
  exit 1
fi
printf 'bg-fd-inherit-lint: clean — %d hook file(s) scanned, 0 backgrounded child inherits stdout.\n' "$n_files"
exit 0
