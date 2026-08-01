#!/bin/bash
# gate-classify.sh — route a STOP-ASK boundary to EXACTLY ONE decision class + reason.
# The missing router of the unattended-escalation protocol (P15 §3.1, axis c).
#
#   A  AUTO-DECIDE   the standing values or a pre-signed ruling class SETTLE it
#                    (ship-at-green verified work · do-both-if-net-positive · time-zero).
#   B  QUEUE-REVIEW  DEFAULT — a value-fork/external-info the values don't settle.
#   C  HARD-BLOCK    a C10/authority-ceiling surface: settings.json · live hooks · launchd ·
#                    plist · permissions · money-path (a payment/spend commitment) · credentials.
#
# ── THE ASYMMETRY (load-bearing) ──────────────────────────────────────────────
# C is checked FIRST and can NEVER be demoted to A: a peer-agent ruling is not human
# consent (invariant 6). ANY doubt routes B, never A — a false-A ACTS on an unratified
# decision (catastrophic); a false-B merely queues a decision that could have auto-fired
# (cheap). So the bias is deliberately over-inclusive on C and B, never on A.
#
#   gate-classify.sh "<decision text>"      (or pipe the text on stdin)
#     → "<A|B|C> <reason>" on stdout, exit 0.  (-h/--help)
#   gate-classify.sh --selftest             → RED-proves the routing table above; exit 1 on any
#     failed assertion. There is NO usage-error exit: every other argv is the decision text.
#
# BSD+GNU grep-portable (no \b — uses (^|[^a-z]) boundaries); no eval; fail-loud.
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }

command -v grep >/dev/null 2>&1 || { echo "gate-classify: grep required" >&2; exit 1; }

# ── C-surface — the authority-ceiling nouns/verbs. Over-inclusive on purpose. The money
#    branch matches a COMMITMENT (pay/purchase/raise-the-cap), NOT a spend-LIMIT event
#    (a monthly-spend cap reached is a rate-limit-shaped B, per operator decision #3). ──
C_SURFACE='settings\.json|\.claude/settings|(edit|modify|change|tweak|patch|symlink|touch|update)[a-z ]{0,24}settings|settings[a-z ]{0,12}(file|json|in place|symlink)|symlink[a-z ]{0,20}settings|(^|[^a-z])hooks?(/|[^a-z]|$)|(edit|modify|change|patch)[a-z ]{0,20}hook|hook[a-z ]{0,12}(in place|edit|file)|launchd|launchctl|launchagent|launchdaemon|plist|permission|allow.?list|allowlist|deny.?(rule|list)|(credit|debit) card|enter[a-z ]{0,12}card|authoriz[a-z]*[a-z ]{0,12}payment|make a payment|purchase|pay(ing)? (for|the|a|\$)|charge the card|raise (the )?(spend|billing) (cap|limit)|increase (the )?(spend|billing) (cap|limit)|invoice|checkout|credential|password|api.?key|secret|token|ssh key|oauth|keychain|login|log ?in|cookie|self.?modif|self.?persist|(^|[^a-z])sudo([^a-z]|$)|chmod|wiring-all|activat[a-z]*[a-z ]{0,16}(plist|hook|daemon|launchd|reaper)'

# ── A-settled — the standing-value SETTLED patterns. Reached ONLY when C did not match. ──
A_SETTLED='ship[a-z ]{0,20}green|autonomous at green|land[a-z ]{0,20}verified|verified[a-z ]{0,20}(green|net.?positive|diff)|ship the verified|net.?positive|do both|time.?zero|act now|100th (pct|percentile)|do not wait'

first_match() { printf '%s' "$TEXT" | grep -ioE "$1" 2>/dev/null | head -1 | tr -d '\n'; }

classify() {
  if [ $# -gt 0 ]; then TEXT="$*"; else TEXT="$(cat 2>/dev/null || true)"; fi

  mC="$(first_match "$C_SURFACE")"
  if [ -n "$mC" ]; then
    printf 'C matches a C10/authority-ceiling surface ("%s") — human-only, never demotable to A\n' "$mC"
    return 0
  fi

  mA="$(first_match "$A_SETTLED")"
  if [ -n "$mA" ]; then
    printf 'A the standing values settle it ("%s") — auto-decide + audit trail\n' "$mA"
    return 0
  fi

  printf 'B no settled ruling and no hard surface — any doubt routes B (asymmetric: a false-A is catastrophic)\n'
  return 0
}

# ════ selftest — RED-prove the routing table against the REAL artifact ═════════════════════════
# WHY THIS EXISTS: nightly-regression.sh step 4 globs scripts/*gate*.sh and, for any script with no
# --selftest dispatch, BARE-RUNS it. A bare run of this file reads an empty stdin, routes B and
# exits 0 — an `ok` that can never fail, i.e. a deleted check (cc-backlog 94f0b1fcc5c8). Every
# assertion below re-invokes $SELF as a SUBPROCESS, so what is proved is the shipped artifact and
# never a hand-copied approximation of its logic.
#
# The set is chosen to kill the three degenerate regressions a shape-only check would pass:
# always-B (what the vacuous bare-run looks like), always-C, and C silently demoted to A.
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
want() { # <expected-class> <decision text…> — routes via argv, asserts the first token
  local exp="$1"; shift
  local got; got="$("$SELF" "$@" 2>/dev/null | awk '{print $1}')"
  [ "$got" = "$exp" ] && okp "$exp ← $*" || badp "$exp ← $* (got '${got:-<empty>}')"
}
# shellcheck disable=SC2317
selftest() {
  local got line rc u
  echo "gate-classify --selftest:"

  # C — the authority ceiling, one probe per surface family. Over-inclusive by design.
  want C 'edit settings.json to add an allow rule'
  want C 'just symlink the settings into place, it is trivial'
  want C 'modify the anti-deference hook in place'
  want C 'quickly tweak the launchd plist to add the job'
  want C 'add a permission to the allowlist and reload'
  want C 'I need your API key to proceed'
  want C 'run sudo to rebind the port'
  want C 'chmod the reaper so it can run'

  # A — the standing values settle it.
  want A 'ship the verified green diff — autonomous at green'
  want A 'this is net-positive, do both'
  want A 'act now, time-zero, do not wait'

  # B — the default, reached two ways: an unmatched value-fork, and the money ASYMMETRY (a spend
  # LIMIT reached is a rate-limit-shaped B; only a spend COMMITMENT is the C money-path).
  want B 'should the module naming scheme be snake or camel here'
  want B 'monthly spend cap reached on next2 — no reset time'
  want C 'raise the spend cap on the billing account'

  # THE ASYMMETRY (invariant 6): C is checked FIRST and can never be demoted to A. Only text
  # carrying BOTH signals proves the ORDER rather than re-proving the two tables.
  want C 'ship the settings.json change at green'
  want C 'landing the verified net-positive launchctl change now'

  # The bare-run case this selftest exists for: empty input is a DELIBERATE B, not an accident.
  got="$("$SELF" </dev/null 2>/dev/null | awk '{print $1}')"
  [ "$got" = B ] && okp "empty stdin routes B (the bare-run case, pinned as deliberate)" \
                 || badp "empty stdin → '${got:-<empty>}' (want B)"

  # Two entry points, one table.
  got="$(printf 'edit settings.json\n' | "$SELF" 2>/dev/null | awk '{print $1}')"
  [ "$got" = C ] && okp "stdin path routes identically to argv" \
                 || badp "stdin path → '${got:-<empty>}' (want C)"

  # Shape + exit contract: exactly one class token, a non-empty reason, exit 0.
  line="$("$SELF" 'edit settings.json' 2>/dev/null)"; rc=$?
  printf '%s' "$line" | grep -qE '^[ABC] .+' \
    && okp "shape: '<class> <reason>' with a non-empty reason" || badp "shape: got '$line'"
  [ "$rc" -eq 0 ] && okp "exit 0 on a classified decision" || badp "exit $rc on a classified decision (want 0)"

  u="$("$SELF" --help 2>/dev/null)"; rc=$?
  [ "$rc" -eq 0 ] && [ -n "$u" ] && okp "--help prints the usage block, exit 0" \
                                 || badp "--help rc=$rc, $(printf '%s' "$u" | wc -c) bytes (want 0 + non-empty)"

  echo "gate-classify --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || return 1
  echo "gate-classify --selftest: GREEN — C-first asymmetry held, both entry points agree, empty input is a deliberate B."
  return 0
}

case "${1:-}" in
  -h|--help)  usage; exit 0 ;;
  --selftest) selftest; exit $? ;;
esac
classify "$@"
exit 0
