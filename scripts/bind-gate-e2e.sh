#!/bin/bash
# bind-gate-e2e — regression gate for the BIND tier (bin/cc-bind).
#
# Deliberately exercises the DEPLOYED tool (`which cc-bind`), not the repo copy: a repo commit
# is not a live tool. `cc-board` shipped committed-but-un-symlinked and only the operator's
# effect-check caught it (blueprint §4, Deploy DoD clause 1).
#
# Clause 1: the tool resolves, points at this repo, and RUNS.
# Clause 2: the CHECK IS SEEN TO FIRE — cc-bind's selftest proves the gate goes RED on a missing
#           ack (4 negatives) and GREEN on a present one (1 positive control). A gate that has
#           never fired is UNPROVEN, not "quiet" (detector D9, audit §7).
set -uo pipefail
pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

echo "bind-gate-e2e:"

# --- clause 1: deployed, not merely committed ---------------------------------------------------
BIN="$(command -v cc-bind 2>/dev/null || true)"
if [ -n "$BIN" ]; then ok "cc-bind resolves on PATH ($BIN)"; else
  bad "cc-bind NOT on PATH — committed but not deployed (ln -s bin/cc-bind ~/.claude/bin/)"
fi

if [ -n "$BIN" ]; then
  tgt="$(readlink "$BIN" 2>/dev/null || echo "$BIN")"
  case "$tgt" in
    */claude-infrastructure/bin/cc-bind) ok "deployed tool points at this repo (edits are live)" ;;
    *) bad "deployed tool resolves to '$tgt' — NOT this repo (a drifted copy: the statusline trap)" ;;
  esac
fi

# --- clause 2: the check is seen to FIRE ---------------------------------------------------------
# The selftest itself asserts 4 RED cases + 1 GREEN control in a throwaway repo. If it ever
# reports 0 failures while silently running 0 checks, that is the D9 bug in the TEST — so we also
# assert the expected check COUNT, not merely a zero-failure claim.
if [ -n "$BIN" ]; then
  out="$("$BIN" selftest 2>&1)"; rc=$?
  n_ok="$(printf '%s' "$out" | grep -c '^  ok ')"
  if [ "$rc" -eq 0 ]; then ok "selftest exits 0"; else bad "selftest exits $rc"; fi
  if [ "$n_ok" -eq 8 ]; then ok "selftest ran all 8 checks (7 RED + 1 GREEN control)"; else
    bad "selftest ran $n_ok/8 checks — a suite that runs no checks 'passes' too (D9)"
  fi
  # the marquee red: an issued-but-UNACKED ruling MUST fail closed
  if printf '%s' "$out" | grep -q 'ok   issued but UNACKED -> FAIL CLOSED'; then
    ok "the marquee RED fires: issued-but-UNACKED fails closed"
  else
    bad "the marquee RED did NOT fire — the gate cannot detect a missing ack"
  fi
fi

echo "bind-gate-e2e: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
