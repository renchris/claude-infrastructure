#!/usr/bin/env bash
# alarm-polarity-lint.sh — the recurrence guard for row 10's signature bug class.
#
#   scripts/alarm-polarity-lint.sh [<file>...]        # default: the declared alarm-emitting set
#
# THE BUG CLASS (OPERATOR_SURFACE_V2 §4 F1/F10; coordinator-ruled row 10's on 2026-07-29).
# `bin/cc-blockers` gated its PERSISTENT-RED alarm on `[ "$red" -eq "$seen" ]` — equality against ONE
# NAMED FAILURE across a window — so a single `cut` or `hung` stamp anywhere in the newest five
# DISABLED the alarm that exists to catch exactly that state. Reproduced live: newest five
# red/hung/red/red/red, seen=5, red=4, 4 != 5, row SUPPRESSED, while 0 of 33 stamps had EVER been
# green.
#
# The vocabulary was never wrong. `red`/`cut`/`hung`/`green` mean what the verifier says they mean,
# and a non-verdict genuinely is NOT a red. The polarity INVERTS one layer down, inside an alarm,
# because a hung run is WORSE than a red one for "is this persistently failing" — yet only the red
# test silences on it.
#
#   For a VERDICT ask "is it red?".  For an ALARM ask "is it green?".
#
# WHAT THIS DETECTS (pattern A, and deliberately only pattern A). A counter incremented ONLY under an
# equality test against a literal failure name, which is then compared for EQUALITY against a
# window/total counter. That is the exact shape, it is textually decidable, and it currently has zero
# false positives on this tree.
#
# WHAT IT DELIBERATELY DOES NOT DETECT, and why saying so matters more than shipping it: the sibling
# shape — existence evidence taken from the SUBJECT'S OWN SUCCESS HISTORY rather than from a
# DECLARATION (row 12's law; `deploy-lag` gated on a green stamp of which there are 0 in 33). Its
# textual signature is `[ -z "$<success-cursor>" ] … return 0`, which is ALSO the correct shape for a
# never-certified backstop — `bin/cc-blockers`'s own `never-green` row is written that way and is
# right. A lint that fires on correct code gets suppressed everywhere it is installed, which would
# cost more than the check is worth. That one stays a review rule, recorded in the plan's §3 I1.
#
# SUPPRESSION, for a genuinely deliberate verdict-equality: put `# alarm-polarity-ok: <reason>` on the
# line or the line above. A reason is required — a bare marker is reported as an unexplained
# suppression, because "someone typed the magic word" is not evidence.
#
# SCOPE: blocks on the files it is GIVEN. Callers pass a diff, never the whole tree — a blocking lint
# scoped to the tree makes every author answerable for every other's (memory
# whole-tree-lint-is-a-fleet-wide-hard-stop). With no arguments it lints the declared default set,
# which is what the bats suite does.
#
# EXIT: 0 = clean (or nothing in scope) · 1 = findings · 2 = the check could not run. A "could not
# run" is a THIRD state and never a pass (memory named-failure-vs-no-verdict).
# Kill switch: CC_ALARM_POLARITY_LINT=off → exit 0 with a stated ABSTAIN line, never silence.
# shellcheck disable=SC2016  # file-wide: the report text quotes shell identifiers in `backticks` for
#   the human reading it. shellcheck reads those as command substitution; nothing here is expanded.
set -uo pipefail

FAILNAMES='red|cut|hung|fail|failed|failing|error|refused|blocked|denied|timeout'
# The declared alarm-emitting surfaces. A list, not a glob: the check is only meaningful where an
# ALARM predicate lives, and a glob would drag in every verdict producer, where the polarity is
# correct by definition.
DEFAULT_SET="bin/cc-blockers bin/cc-fleet hooks/activation-watch.sh hooks/operator-readout.sh"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)" || ROOT=""
[ -n "$ROOT" ] || { echo "alarm-polarity-lint: cannot resolve repo root" >&2; exit 2; }

if [ "${CC_ALARM_POLARITY_LINT:-on}" = off ]; then
  echo "alarm-polarity-lint: ABSTAIN — disabled by CC_ALARM_POLARITY_LINT=off (this is not a pass)."
  exit 0
fi
command -v awk >/dev/null 2>&1 || { echo "alarm-polarity-lint: awk required" >&2; exit 2; }

FILES=()
if [ "$#" -gt 0 ]; then
  for f in "$@"; do
    case "$f" in /*) FILES+=("$f") ;; *) FILES+=("$ROOT/$f") ;; esac
  done
else
  for f in $DEFAULT_SET; do [ -f "$ROOT/$f" ] && FILES+=("$ROOT/$f"); done
fi
[ "${#FILES[@]}" -gt 0 ] || { echo "alarm-polarity-lint: nothing in scope — 0 file(s)."; exit 0; }

FINDINGS=0
SCANNED=0
SUPPRESSED=0

for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  SCANNED=$((SCANNED + 1))
  # Two passes in ONE awk, because pass 2's question ("is this counter compared for equality?") needs
  # pass 1's answer ("which counters are failure-name-only?"), and a shell loop over grep would fork
  # per candidate.
  out="$(awk -v names="$FAILNAMES" -v file="$f" '
    function suppressed(n) { return (n in supp) || ((n - 1) in supp) }
    # SAME one-line lookback for the bare form. Keyed on the exact line only, the BARE-SUPPRESSION
    # branch was UNREACHABLE for the adjacent-comment case that is the only way anyone writes it —
    # a code path that cannot fire, in the lint whose whole subject is code paths that cannot fire.
    function bare_marked(n) { return (n in bare) || ((n - 1) in bare) }
    { line[NR] = $0
      if ($0 ~ /#[[:space:]]*alarm-polarity-ok:[[:space:]]*[^[:space:]]/) supp[NR] = 1
      else if ($0 ~ /#[[:space:]]*alarm-polarity-ok/) bare[NR] = 1
    }
    END {
      # PASS 1 — counters incremented ONLY under an equality test against a literal failure name.
      # Shape:  [ "$v" = "red" ] && red=$((red + 1))      (or  = red  unquoted)
      for (i = 1; i <= NR; i++) {
        L = line[i]
        if (L !~ ("=[[:space:]]*\"?(" names ")\"?[[:space:]]*\\]")) continue
        if (match(L, /[A-Za-z_][A-Za-z_0-9]*=\$\(\([[:space:]]*[A-Za-z_][A-Za-z_0-9]*[[:space:]]*\+/)) {
          v = substr(L, RSTART, RLENGTH); sub(/=.*/, "", v)
          fail_only[v] = fail_only[v] + 1
          where[v] = i
        }
      }
      # PASS 2 — any of those compared for EQUALITY against another counter.
      for (i = 1; i <= NR; i++) {
        L = line[i]
        for (v in fail_only) {
          if (L !~ ("\\$" v "\"?[[:space:]]*-eq")) continue
          if (suppressed(i)) { print "SUPP\t" file "\t" i "\t" v; continue }
          if (bare_marked(i)) { print "BARE\t" file "\t" i "\t" v; continue }
          print "HIT\t" file "\t" i "\t" v "\t" where[v]
        }
      }
    }' "$f" 2>/dev/null)" || { echo "alarm-polarity-lint: awk failed on $f" >&2; exit 2; }

  [ -n "$out" ] || continue
  while IFS="$(printf '\t')" read -r kind path ln var inc; do
    [ -n "$kind" ] || continue
    case "$kind" in
      SUPP) SUPPRESSED=$((SUPPRESSED + 1)) ;;
      BARE)
        FINDINGS=$((FINDINGS + 1))
        printf '  BARE-SUPPRESSION  %s:%s  `%s` — `# alarm-polarity-ok` needs a REASON after the colon.\n' \
          "${path#"$ROOT"/}" "$ln" "$var" ;;
      HIT)
        FINDINGS=$((FINDINGS + 1))
        printf '  POLARITY  %s:%s  `%s` is incremented ONLY on a named failure (%s:%s) and then tested for EQUALITY here.\n' \
          "${path#"$ROOT"/}" "$ln" "$var" "${path#"$ROOT"/}" "$inc"
        printf '            An ALARM must test ABSENCE OF SUCCESS, not presence of one named failure: count NOT-<success>\n'
        printf '            so a third state (cut / hung / no-verdict) STRENGTHENS the case instead of silencing it.\n'
        printf '            Deliberate? `# alarm-polarity-ok: <why this really is a verdict, not an alarm>`\n' ;;
    esac
  done <<EOF
$out
EOF
done

if [ "$FINDINGS" -gt 0 ]; then
  printf 'alarm-polarity-lint: %s finding(s) across %s file(s).\n' "$FINDINGS" "$SCANNED"
  exit 1
fi
printf 'alarm-polarity-lint: clean — %s file(s) scanned; %s explained suppression(s), 0 inverted alarm predicates.\n' \
  "$SCANNED" "$SUPPRESSED"
exit 0
