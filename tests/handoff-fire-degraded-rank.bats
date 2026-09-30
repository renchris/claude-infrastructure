#!/usr/bin/env bats
# handoff-fire.sh — the DEGRADED account rank must not prefer an account the router last saw exhausted.
#
# Incident 2026-09-30: two post-reboot fires in a row ranked by the activity proxy (router off PATH,
# then its single-flight lock wedged at load 194). An exhausted account is the least active one, so
# the proxy put next2, at 100% weekly, first; both sessions hit the limit on their first turn.
# ranked_accounts and hf_lastgood_exhausted are extracted with sed; nothing here runs the fire path.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  # Nothing here runs the fire path, but the ratchet binds every suite that names handoff-fire.sh.
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_ACCOUNTS_LASTGOOD="$BATS_TEST_TMPDIR/lastgood.json"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  FN="$BATS_TEST_TMPDIR/fn.sh"
  { sed -n '/^ranked_accounts() {/,/^}/p' "$HF"; sed -n '/^hf_lastgood_exhausted() {/,/^}/p' "$HF"; } > "$FN"
  grep -q '^hf_lastgood_exhausted() {' "$FN" || { echo "hf_lastgood_exhausted not found"; false; }
  # Router absent (PATH has no claude-accounts) and every account equally idle, so the proxy ranks
  # in this order, next2 FIRST, which is the incident's shape: the exhausted account on top.
  export CC_ACCT_NAMES="next2 next next3 next4"
  FUT="$(/usr/bin/python3 -c 'import datetime as d;print((d.datetime.now(d.timezone.utc)+d.timedelta(days=2)).isoformat())')"
  PAST="$(/usr/bin/python3 -c 'import datetime as d;print((d.datetime.now(d.timezone.utc)-d.timedelta(days=2)).isoformat())')"
}

rank() { /bin/bash -c "PATH=/usr/bin:/bin; activity(){ echo 0; }; MODEL=x; . '$FN'; ranked_accounts" 2>"$BATS_TEST_TMPDIR/err"; }
lastgood() { printf '%s\n' "$1" > "$CC_ACCOUNTS_LASTGOOD"; }

@test "RED-PROOF: an account at 100% weekly with a future reset is dropped from the degraded rank" {
  lastgood "{\"next2\":{\"weekly_pct\":100,\"weekly_reset_at\":\"$FUT\"},\"next\":{\"weekly_pct\":81,\"weekly_reset_at\":\"$FUT\"}}"
  run rank
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"activity-proxy (DEGRADED"* ]] || false
  [[ "$output" != *"next2"* ]] || { echo "$output"; false; }
  [ "${lines[1]}" = "next 0" ]
  grep -q 'skipping next2' "$BATS_TEST_TMPDIR/err"
}

@test "an exhausted 5-hour window with a future reset is dropped too" {
  lastgood "{\"next2\":{\"session_pct\":100,\"session_reset_at\":\"$FUT\"}}"
  run rank
  [[ "$output" != *"next2"* ]] || { echo "$output"; false; }
}

@test "a reset already PASSED keeps the account: the reading is stale, not a limit" {
  lastgood "{\"next2\":{\"weekly_pct\":100,\"weekly_reset_at\":\"$PAST\"}}"
  run rank
  [ "${lines[1]}" = "next2 0" ] || { echo "$output"; false; }
}

@test "every account exhausted → the rank is unchanged, never an empty list" {
  lastgood "{\"next\":{\"weekly_pct\":100,\"weekly_reset_at\":\"$FUT\"},\"next2\":{\"weekly_pct\":100,\"weekly_reset_at\":\"$FUT\"},\"next3\":{\"weekly_pct\":100,\"weekly_reset_at\":\"$FUT\"},\"next4\":{\"weekly_pct\":100,\"weekly_reset_at\":\"$FUT\"}}"
  run rank
  [ "${#lines[@]}" -eq 5 ] || { echo "$output"; false; }
}

@test "no last-good file, or a malformed one → the rank is exactly the proxy's" {
  run rank
  [ "${lines[1]}" = "next2 0" ] || { echo "$output"; false; }
  [ "${#lines[@]}" -eq 5 ] || { echo "$output"; false; }
  printf 'not json' > "$CC_ACCOUNTS_LASTGOOD"
  run rank
  [ "${lines[1]}" = "next2 0" ] || { echo "$output"; false; }
  [ "${#lines[@]}" -eq 5 ] || { echo "$output"; false; }
}
