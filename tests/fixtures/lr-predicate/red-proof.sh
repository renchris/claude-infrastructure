#!/bin/bash
# red-proof.sh — the RED-PROOF for tests/lr-predicate.bats, and the reason W0 exists at all.
#
# A new SSOT cannot be red-proofed the usual way. The convention in this repo is to run each new
# row against pristine trunk and paste its RED output into the suite's footer — but `lr_predicate`
# does not exist on pristine trunk, so every row would error identically and the run would carry no
# information about which BEHAVIOUR each row pins. The load-bearing proof for a CONSOLIDATION is
# against the predicates it replaces. So this script puts each row's verbatim string through the
# five shipped copies, VERBATIM, and prints the matrix.
#
# Each copy below is extracted from its shipped site and the file:line is printed beside it, so a
# reader can diff the extract against the original rather than trusting this file. They drift: the
# plan's anchors were read at a59b53e55 and lr-fleet.sh has moved 3 lines since, which is itself the
# argument for one module instead of sixteen line numbers.
#
# Read-only. Forks python and grep; touches nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
LR="$ROOT/scripts/limit-recover"

# ── the five shipped copies, verbatim from their sites ───────────────────────────────────────────
# lr-fleet.sh:111
LIMIT_RE="You've (hit|reached) your (session|weekly|fast|monthly spend|Fable)? ?limit"
# lr-reset-poller.sh:746
POLLER_RE="You've hit your (session|weekly) limit"
# bin/cc-classify:303-312  (recent_api_limit's text confirmation, grep -qiE)
CCCLS_RE='session limit|weekly limit|usage limit|limit ·|resets|monthly spend limit|spend limit|billing'

c_fleet()  { printf '%s' "$1" | grep -qE "$LIMIT_RE"  && echo MATCH    || echo no-match; }
c_poller() { printf '%s' "$1" | grep -qE "$POLLER_RE" && echo MATCH    || echo no-match; }
c_cccls()  { printf '%s' "$1" | grep -qiE "$CCCLS_RE" && echo MATCH    || echo no-match; }
# lr-lib.sh:172 — the `kind` field of lr_last_api_error
c_lrlib()  { printf '%s' "$1" | /usr/bin/python3 -c \
  'import sys; t=sys.stdin.read(); print("limit" if "You'"'"'ve hit your" in t else "other")'; }
# lr-audit.py:244 classify_limit_text — imported from the real file, never re-typed
c_audit()  { printf '%s' "$1" | /usr/bin/python3 -c '
import importlib.util, sys
spec = importlib.util.spec_from_file_location("lr_audit", sys.argv[1])
mod  = importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
print(mod.classify_limit_text(sys.stdin.read()))' "$LR/lr-audit.py"; }

printf '%-5s %-38s %-10s %-10s %-7s %-16s %-10s\n' \
  row string 'fleet:111' 'poller:746' 'lib:172' 'audit:244' 'cc-cls:312'
printf '%s\n' '--------------------------------------------------------------------------------------------------------'

row() { # $1=label $2=string
  printf '%-5s %-38s %-10s %-10s %-7s %-16s %-10s\n' "$1" "$(printf '%.36s' "$2")" \
    "$(c_fleet "$2")" "$(c_poller "$2")" "$(c_lrlib "$2")" "$(c_audit "$2")" "$(c_cccls "$2")"
}

F1="You've reached your Fable limit. Run /usage-credits to continue or switch models with /model."
F3="You've hit your Sonnet limit. Run /usage-credits to continue."
F4="You've hit your session limit"
F6="You've hit your monthly spend limit · raise it at claude.ai/settings/usage"
F7="API Error: 529 Overloaded. This is a server-side issue, usually temporary — try again in a moment."
F8="API Error: getaddrinfo ENOTFOUND api.anthropic.com"
F10="Not logged in · Please run /login"

row F1  "$F1"
row F3  "$F3"
row F4  "$F4"
row F6  "$F6"
row F7  "$F7"
row F8  "$F8"
row F10 "$F10"

printf '\n'
printf 'and what lr_predicate answers for the same strings (cap, via the shim):\n'
for r in "F1:$F1" "F3:$F3" "F4:$F4" "F6:$F6" "F7:$F7" "F8:$F8" "F10:$F10"; do
  # Through classify-text WITH the envelope its record carries, which is the comparison that is
  # fair: the copies above are all text-only and the module is not.
  case "${r%%:*}" in
    F7)      err=server_error; sta=529 ;;
    F8)      err=server_error; sta=""  ;;
    F10)     err=authentication_failed; sta="" ;;
    *)       err=rate_limit;   sta=429 ;;
  esac
  printf '%-5s %s\n' "${r%%:*}" \
    "$(bash "$LR/lr-predicate.sh" classify-text "${r#*:}" "$err" "$sta" \
       | jq -r '"limit=\(.limit) kind=\(.kind) cap=\(.cap) wait=\(.recoverable_by_waiting)"')"
done
