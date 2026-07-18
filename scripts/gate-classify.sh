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
#     → "<A|B|C> <reason>" on stdout, exit 0.  (-h/--help; exit 2 on usage error)
#
# BSD+GNU grep-portable (no \b — uses (^|[^a-z]) boundaries); no eval; fail-loud.
set -uo pipefail

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }

if [ $# -gt 0 ]; then
  case "$1" in -h|--help) usage; exit 0 ;; esac
  TEXT="$*"
else
  TEXT="$(cat 2>/dev/null || true)"
fi

command -v grep >/dev/null 2>&1 || { echo "gate-classify: grep required" >&2; exit 1; }

# ── C-surface — the authority-ceiling nouns/verbs. Over-inclusive on purpose. The money
#    branch matches a COMMITMENT (pay/purchase/raise-the-cap), NOT a spend-LIMIT event
#    (a monthly-spend cap reached is a rate-limit-shaped B, per operator decision #3). ──
C_SURFACE='settings\.json|\.claude/settings|(edit|modify|change|tweak|patch|symlink|touch|update)[a-z ]{0,24}settings|settings[a-z ]{0,12}(file|json|in place|symlink)|symlink[a-z ]{0,20}settings|(^|[^a-z])hooks?(/|[^a-z]|$)|(edit|modify|change|patch)[a-z ]{0,20}hook|hook[a-z ]{0,12}(in place|edit|file)|launchd|launchctl|launchagent|launchdaemon|plist|permission|allow.?list|allowlist|deny.?(rule|list)|(credit|debit) card|enter[a-z ]{0,12}card|authoriz[a-z]*[a-z ]{0,12}payment|make a payment|purchase|pay(ing)? (for|the|a|\$)|charge the card|raise (the )?(spend|billing) (cap|limit)|increase (the )?(spend|billing) (cap|limit)|invoice|checkout|credential|password|api.?key|secret|token|ssh key|oauth|keychain|login|log ?in|cookie|self.?modif|self.?persist|(^|[^a-z])sudo([^a-z]|$)|chmod|wiring-all|activat[a-z]*[a-z ]{0,16}(plist|hook|daemon|launchd|reaper)'

# ── A-settled — the standing-value SETTLED patterns. Reached ONLY when C did not match. ──
A_SETTLED='ship[a-z ]{0,20}green|autonomous at green|land[a-z ]{0,20}verified|verified[a-z ]{0,20}(green|net.?positive|diff)|ship the verified|net.?positive|do both|time.?zero|act now|100th (pct|percentile)|do not wait'

first_match() { printf '%s' "$TEXT" | grep -ioE "$1" 2>/dev/null | head -1 | tr -d '\n'; }

mC="$(first_match "$C_SURFACE")"
if [ -n "$mC" ]; then
  printf 'C matches a C10/authority-ceiling surface ("%s") — human-only, never demotable to A\n' "$mC"
  exit 0
fi

mA="$(first_match "$A_SETTLED")"
if [ -n "$mA" ]; then
  printf 'A the standing values settle it ("%s") — auto-decide + audit trail\n' "$mA"
  exit 0
fi

printf 'B no settled ruling and no hard surface — any doubt routes B (asymmetric: a false-A is catastrophic)\n'
exit 0
