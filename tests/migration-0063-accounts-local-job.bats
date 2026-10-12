#!/usr/bin/env bats
# shellcheck disable=SC2016  # stub bodies carry literal $ on purpose
# Migration 0063 — loads com.claude.accounts-local (docs/plans/ACCOUNTS_BOARD_FRESHNESS.md D9).
#
# Pinned: a bare run is a dry run that changes nothing; a real run refuses until the live layer's
# claude-accounts answers `local: disabled` to a CC_ACCOUNTS_LOCAL=off probe; identical bytes on a
# loaded job are a no-op; a running tick is never booted out; a reload goes bootout → bootstrap →
# print and waits for the job to move its stamp; the header carries every field the converger reads.
#
# Hermetic: scratch HOME and LaunchAgents, a claude-accounts stub, and a launchctl STUB that records
# every call and answers `print` from a scratch state dir (loaded = the bootstrapped plist, running =
# a tick in flight). Everything runs under /bin/bash, the interpreter the operator's line uses.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIG="$REPO/migrations/0063-accounts-local-job.sh"
  SRC="$REPO/launchd/staged/com.claude.accounts-local.plist"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_MIGRATION_REPO="$REPO" CC_MIGRATION_LA_DIR="$BATS_TEST_TMPDIR/LaunchAgents"
  export CC_0063_LAUNCHCTL="$BATS_TEST_TMPDIR/launchctl" CC_0063_CA_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_0063_WAIT_S=2 CC_0063_STAMP_WAIT_S=3 CC_0063_POLL_S=1
  export LC_DIR="$BATS_TEST_TMPDIR/lc"; mkdir -p "$LC_DIR" "$CC_MIGRATION_LA_DIR" "$HOME/.claude"
  export STAMP="$HOME/.claude/logs/accounts-local.stamp"
  export LC_TICK_STAMP="$STAMP"   # the stub's bootstrap ticks once and touches the stamp, as RunAtLoad does
  DST="$CC_MIGRATION_LA_DIR/com.claude.accounts-local.plist"
  cat > "$CC_0063_LAUNCHCTL" <<'STUB'
#!/bin/bash
# launchctl stub: every call is recorded; state is $LC_DIR/loaded (the plist) and $LC_DIR/running
verb="$1"; shift
echo "$verb $*" >> "$LC_DIR/calls"
case "$verb" in
  print) [ -f "$LC_DIR/loaded" ] || exit 113
         if [ -f "$LC_DIR/running" ]; then echo "	state = running"; else echo "	state = not running"; fi
         echo "	run interval = 20 seconds"; exit 0 ;;
  bootout) [ -f "$LC_DIR/running" ] && echo "KILLED-A-RUNNING-TICK" >> "$LC_DIR/calls"
           rm -f "$LC_DIR/loaded"; exit 0 ;;
  bootstrap) cp "$2" "$LC_DIR/loaded"
             if [ -n "${LC_TICK_STAMP:-}" ]; then mkdir -p "$(dirname "$LC_TICK_STAMP")"; touch "$LC_TICK_STAMP"; fi
             exit 0 ;;
esac
exit 64
STUB
  chmod +x "$CC_0063_LAUNCHCTL"
  ca_stub good
}

# good: the live layer has the verb (prints `local: disabled` under the off switch and touches the
# stamp, as the real one does). old: a live layer from before the verb existed.
ca_stub() {
  if [ "$1" = good ]; then
    cat > "$CC_0063_CA_BIN" <<'CA'
#!/bin/bash
echo "CC_ACCOUNTS_LOCAL=${CC_ACCOUNTS_LOCAL:-unset} args:$*" >> "$LC_DIR/ca_calls"
[ "${CC_ACCOUNTS_LOCAL:-}" = off ] || { echo "REAL PASS RAN" >> "$LC_DIR/ca_calls"; exit 0; }
mkdir -p "$(dirname "$STAMP")"; touch "$STAMP"; echo "local: disabled"
CA
  else
    cat > "$CC_0063_CA_BIN" <<'CA'
#!/bin/bash
echo "CC_ACCOUNTS_LOCAL=${CC_ACCOUNTS_LOCAL:-unset} args:$*" >> "$LC_DIR/ca_calls"
echo "claude-accounts: error: unrecognized arguments: $*" >&2; exit 2
CA
  fi
  chmod +x "$CC_0063_CA_BIN"
}

mig() { /bin/bash "$MIG" "$@"; }
# count of `pattern` lines in a file, 0 when the file is absent (a bare `! grep` is errexit-exempt in bats)
count() { cat "$2" 2>/dev/null | grep -cE "$1" || true; }
mutations() { count '^(bootout|bootstrap) ' "$LC_DIR/calls"; }
# an installed-and-loaded older copy of the job (different bytes from the repo plist)
old_job() {
  sed 's/<integer>20<\/integer>/<integer>60<\/integer>/' "$SRC" > "$DST"
  if cmp -s "$SRC" "$DST"; then echo "old_job: the mutation did not apply"; return 1; fi
  cp "$DST" "$LC_DIR/loaded"
}

@test "0063: a bare run and --dry-run change nothing; --confirm must name launchd" {
  for m in "" --dry-run; do
    # shellcheck disable=SC2086  # the empty mode must vanish, not become an empty argument
    run mig $m
    [ "$status" -eq 0 ] || { echo "mode '$m': $output"; false; }
    [[ "$output" == *"dry run — nothing changed"* ]] || { echo "$output"; false; }
  done
  [ ! -e "$DST" ]
  [ "$(mutations)" -eq 0 ]
  [ ! -e "$LC_DIR/ca_calls" ] || { echo "the dry run ran the probe: $(cat "$LC_DIR/ca_calls")"; false; }
  [ ! -e "$HOME/.claude/state/accounts-local" ]
  run mig --confirm everything
  [ "$status" -eq 2 ]
  [ "$(mutations)" -eq 0 ]
}

@test "0063: refuses until claude-accounts prints 'local: disabled', and probes only with CC_ACCOUNTS_LOCAL=off" {
  ca_stub old
  run mig --confirm launchd
  [ "$status" -eq 1 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"local: disabled"* ]] || false
  [ ! -e "$DST" ]
  [ "$(mutations)" -eq 0 ]
  grep -qx 'CC_ACCOUNTS_LOCAL=off args:--local-refresh' "$LC_DIR/ca_calls"

  ca_stub good
  run mig --confirm launchd
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  [ "$(count 'REAL PASS RAN' "$LC_DIR/ca_calls")" -eq 0 ]
  [ "$(grep -vc 'CC_ACCOUNTS_LOCAL=off args:--local-refresh' "$LC_DIR/ca_calls")" -eq 0 ]
  [ -d "$HOME/.claude/state/accounts-local" ]
}

@test "0063: identical bytes on a loaded job are a no-op — no bootout, no bootstrap" {
  run mig --confirm launchd
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  cmp -s "$SRC" "$DST"
  : > "$LC_DIR/calls"
  run mig --confirm launchd
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"skip"* ]] || false
  [ "$(mutations)" -eq 0 ]
}

@test "0063: never boots out a running tick — exits busy within its wait and changes nothing" {
  old_job; touch "$LC_DIR/running"
  local before; before="$(shasum < "$DST")"
  s=$SECONDS; run mig --confirm launchd; el=$(( SECONDS - s ))
  [ "$status" -eq 75 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"busy: re-run"* ]] || false
  # 60, not ~3: it proves the 2 s seam bounded the wait rather than the 130 s default, and a loaded
  # box measured 12 s here (every poll forks the stub several times).
  [ "$el" -lt 60 ] || { echo "took ${el}s against a 2 s wait"; false; }
  [ "$(mutations)" -eq 0 ]
  [ "$(count KILLED-A-RUNNING-TICK "$LC_DIR/calls")" -eq 0 ]
  [ "$(shasum < "$DST")" = "$before" ]   # the old bytes stay, so the re-run is not skipped as identical
  # the tick ends: the re-run reloads
  rm -f "$LC_DIR/running"
  run mig --confirm launchd
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  cmp -s "$SRC" "$LC_DIR/loaded"
}

@test "0063: an old job is backed up, booted out, bootstrapped and read back in that order; the stamp must move" {
  old_job
  run mig --confirm launchd
  [ "$status" -eq 0 ] || { echo "rc=$status $output"; false; }
  local out_ln in_ln pr_ln
  out_ln="$(grep -n '^bootout ' "$LC_DIR/calls" | head -1 | cut -d: -f1)"
  in_ln="$(grep -n '^bootstrap ' "$LC_DIR/calls" | head -1 | cut -d: -f1)"
  pr_ln="$(grep -n '^print ' "$LC_DIR/calls" | tail -1 | cut -d: -f1)"
  [ -n "$out_ln" ] || { cat "$LC_DIR/calls"; false; }
  [ -n "$in_ln" ] || { cat "$LC_DIR/calls"; false; }
  [ -n "$pr_ln" ] || { cat "$LC_DIR/calls"; false; }
  [ "$out_ln" -lt "$in_ln" ] || { cat "$LC_DIR/calls"; false; }
  [ "$in_ln" -lt "$pr_ln" ] || { cat "$LC_DIR/calls"; false; }
  grep -q "^bootstrap gui/$(id -u) $DST\$" "$LC_DIR/calls"
  cmp -s "$SRC" "$DST"
  cmp -s "$SRC" "$LC_DIR/loaded"
  ls "$CC_MIGRATION_LA_DIR"/com.claude.accounts-local.plist.bak-* >/dev/null
  [ -z "$(find "$CC_MIGRATION_LA_DIR" -name '*.tmp.*')" ]
  [[ "$output" == *"agent: flip the fleet.manifest row staged→run"* ]] || false

  # Negative control: a job that loads but never ticks is NOT reported loaded-and-working.
  old_job; unset LC_TICK_STAMP
  run mig --confirm launchd
  [ "$status" -eq 1 ] || { echo "rc=$status $output"; false; }
  [[ "$output" == *"did not move"* ]]
}

@test "0063: the header carries class, step, run, subject (the repo arm), verify and batch-hold" {
  h() { sed -n "s/^# *migration-$1: *//p" "$MIG" | head -1; }
  [ "$(h class)" = c10 ]
  [[ "$(h step)" == "load com.claude.accounts-local "* ]] || false
  [ "$(h run)" = "bash ~/Development/claude-infrastructure/migrations/0063-accounts-local-job.sh --confirm launchd" ]
  # shellcheck disable=SC2088  # the header holds a literal ~, compared as text
  [ "$(h subject)" = "~/Development/claude-infrastructure/launchd/staged/com.claude.accounts-local.plist" ]
  [[ "$(h verify)" == *"com.claude.accounts-local"*"run interval = 20"*"accounts-local.stamp"* ]] || false
  [[ "$(h batch-hold)" == "manual — "* ]] || false
  [ -x "$MIG" ]
}
