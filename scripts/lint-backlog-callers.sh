#!/bin/bash
# lint-backlog-callers.sh — every `cc-backlog block` / `cc-backlog needs` CALL LINE names its class.
#
# BACKLOG_MASTER W0 ledger-admission.3. `block` and `needs` now carry one of the four impossibility
# classes (needs-credential | needs-human | not-yet-true | no-capacity) — by `--class C`, or needs text
# opening "C:" or "On or after YYYY-MM-DD" — warn-only first, enforced once 7 days pass with no
# unclassed transition (bin/cc-backlog class_gate_block). This lint finds the callers that would
# break at the flip, BEFORE it happens, instead of from the gate log after.
#
# A CALL LINE is a hit of either grep below whose verb is followed by an argument — an executable
# invocation, or a runnable command a hook or brief hands to an agent. A bare mention (`cc-backlog
# needs`, "cc-backlog block/needs") is prose and is not linted. A call line passes when it carries
# `--class`, a class-opening needs text, or a `class-gate: exempt(<why>)` annotation on that line.
#
# usage: lint-backlog-callers.sh [--ref <commit-ish>]   (default: the working tree)
# exit 0 all call lines classed · 1 unclassed call lines listed · 2 usage/grep failure
set -uo pipefail
REF=""
case "${1:-}" in
  --ref) REF="${2:-}"; [ -n "$REF" ] || { echo "usage: $0 [--ref <commit-ish>]" >&2; exit 2; } ;;
  "") ;;
  *) echo "usage: $0 [--ref <commit-ish>]" >&2; exit 2 ;;
esac
# resolve $0 through its symlinks FIRST (~/.claude/scripts/* are per-file links into the checkout)
p="$0"
while [ -L "$p" ]; do d="$(cd "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"; case "$p" in /*) ;; *) p="$d/$p" ;; esac; done
cd "$(dirname "$p")/.." || exit 2

PATHSPEC=(-- . ':!tests' ':!bin/cc-backlog' ':!docs' ':!*.md' ':!bus' ':!scripts/lint-backlog-callers.sh')   # bus/: a message log, not code
TEMPLATES=(-- 'scripts/*.template.md')   # briefs hand agents runnable commands, so they are linted too
# literal spelling (the plan's grep) + a variable holding the binary ("$BACKLOG_BIN" block, [BACKLOG, "needs", …])
PAT_LIT='cc-backlog.{0,3}(block|needs)'   # the plan's grep; the word boundary is checked per line below
PAT_VAR='([Bb][Aa][Cc][Kk][Ll][Oo][Gg][A-Za-z_]*|\$\{?(CB|cb|BL|bl)\}?)["'"'"'}]?[[:space:],]+["'"'"']?(block|needs)([^[:alnum:]_]|$)'

hits="$(git grep -nE -e "$PAT_LIT" -e "$PAT_VAR" ${REF:+"$REF"} "${PATHSPEC[@]}" 2>/dev/null)"
rc=$?
[ "$rc" -le 1 ] || { echo "lint-backlog-callers: git grep failed (rc $rc)" >&2; exit 2; }
thits="$(git grep -nE -e "$PAT_LIT" ${REF:+"$REF"} "${TEMPLATES[@]}" 2>/dev/null)"
rc=$?
[ "$rc" -le 1 ] || { echo "lint-backlog-callers: git grep failed (rc $rc)" >&2; exit 2; }
hits="$hits${thits:+$'\n'$thits}"

bad=0; calls=0
while IFS= read -r h; do
  [ -n "$h" ] || continue
  line="${h#"${REF:+$REF:}"}"
  rest="${line#*:}"; text="${rest#*:}"
  # a comment line in code is prose unless it is a runnable template the code prints (not linted)
  case "$text" in *[![:space:]]*) ;; *) continue ;; esac
  printf '%s' "$text" | grep -E '^[[:space:]]*(#|//)' >/dev/null && continue
  # CALL LINE: the verb is followed by an argument token
  # (`unblock` is not `block`; the argument must look like one: a variable, a quote, a <placeholder>,
  # or a 12-hex row id — "cc-backlog needs timed out" is a message ABOUT the verb, not a call.)
  printf '%s' "$text" | grep -E '(^|[^[:alnum:]_])(block|needs)["'"'"']?[[:space:],]+(["'"'"'$<]|\\"|[0-9a-f]{12}([^[:alnum:]]|$)|(step|id)([^[:alnum:]_]|$))' >/dev/null || continue
  calls=$((calls + 1))
  if printf '%s' "$text" | grep -E -- '--class([[:space:]=]|["'"'"'])|class-gate: exempt\(|(needs-credential|needs-human|not-yet-true|no-capacity):|On or after [0-9]{4}-[0-9]{2}-[0-9]{2}' >/dev/null; then
    continue
  fi
  bad=$((bad + 1))
  printf 'UNCLASSED %s\n' "$(printf '%s' "$line" | cut -c1-220)"
done <<< "$hits"
printf 'lint-backlog-callers: %d call line(s), %d unclassed\n' "$calls" "$bad"
[ "$bad" -eq 0 ]
