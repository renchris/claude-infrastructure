#!/usr/bin/env bats
# worktree-gc-infra-run.sh — the launchd wrapper that finally schedules the janitor for THIS repo
# (126 worktrees / 1,193 branches, swept by nothing, because the only scheduled reaper on the box
# hardcodes the reso repo).
#
# Harness laws:
#   L1 the SUT is the wrapper, never the janitor. worktree-gc.sh is stubbed, so every assertion is
#      about the wrapper's own decisions (kill switch, observe, exclude, fetch, verdict) and a
#      change to the janitor's gates can never silently pass or fail this file.
#   L2 assertions key on the failure-DISTINCT outcome. The two that cost real incidents elsewhere:
#      a fake success (lock contention rendered as `ok removed=0`) and a new janitor exit code
#      landing in a success arm.
#   L3 every keep-rule has a paired act-rule, so a wrapper that simply never invokes the janitor is
#      RED rather than trivially green.
#   L4 hermetic: fixtured $HOME, stubbed git, stubbed janitor. This subject writes to
#      ~/.claude/autonomy and ~/.claude/logs and takes a lock under ~/.claude/state, so an
#      unfixtured $HOME would reach real state — and it schedules a DELETER, so "reaches real
#      state" is not a theoretical leak class here.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO_ROOT/scripts/worktree-gc-infra-run.sh"

  # A stand-in repo directory — the wrapper only needs it to EXIST (the janitor, which is stubbed,
  # is what would need it to be a git checkout).
  export CC_WTGC_INFRA_REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$CC_WTGC_INFRA_REPO"

  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  ARGV="$BATS_TEST_TMPDIR/gc.argv"        # janitor invocation record; ABSENT ⇒ never invoked
  ENVFILE="$BATS_TEST_TMPDIR/gc.env"
  GITARGV="$BATS_TEST_TMPDIR/git.argv"

  export CC_WTGC_INFRA_GC="$BIN/gc-stub.sh"
  export CC_WTGC_GIT="$BIN/git"
  stub_git 0
  stub_gc 0 'worktree-gc: removed 3 worktree(s) · disposed 0 abandoned · kept 7 · deleted 41 branch(es) · 2 refusal(s)'

  LAST="$HOME/.claude/autonomy/worktree-gc-infra.last"
  DISABLED="$HOME/.claude/autonomy/worktree-gc-infra.disabled"
  LOG="$HOME/.claude/logs/worktree-gc-infra.log"
}

stub_git() { # <exit-code>
  cat > "$BIN/git" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$GITARGV"
exit $1
EOF
  chmod +x "$BIN/git"
}

stub_gc() { # <exit-code> <stdout...>
  local rc="$1"; shift
  cat > "$CC_WTGC_INFRA_GC" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$ARGV"
printf 'EXCLUDE=%s\nTRUNK=%s\nREPO=%s\n' "\$CC_WTGC_EXCLUDE" "\$CC_WTGC_TRUNK" "\$CC_WTGC_REPO" >> "$ENVFILE"
cat <<'PAYLOAD'
$*
PAYLOAD
exit $rc
EOF
  chmod +x "$CC_WTGC_INFRA_GC"
}

field() { # <key> → the value from the verdict line
  sed -n "s/.*[[:space:]]$1=\([^[:space:]]*\).*/\1/p" "$LAST"
}

# ── the kill switch ──────────────────────────────────────────────────────────────────────────────

@test "kill switch: nothing is swept, verdict=disabled, exit 0" {
  mkdir -p "$(dirname "$DISABLED")"; : > "$DISABLED"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "disabled" ]
  [ ! -f "$ARGV" ]        # L3's paired keep-rule: the janitor was never invoked at all
  [ ! -f "$GITARGV" ]     # and no fetch was attempted either
}

@test "kill switch does NOT gate observe mode — observe removes nothing by construction" {
  mkdir -p "$(dirname "$DISABLED")"; : > "$DISABLED"
  export WTGC_OBSERVE=1
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "ok" ]
  [ -f "$ARGV" ]
}

@test "without the kill switch the janitor IS invoked (the paired act-rule for L3)" {
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ -f "$ARGV" ]
  grep -q -- '--prune-branches' "$ARGV"
}

# ── observe mode ─────────────────────────────────────────────────────────────────────────────────

@test "WTGC_OBSERVE=1 passes --dry-run and takes no lock; live mode passes neither" {
  export WTGC_OBSERVE=1
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q -- '--dry-run' "$ARGV"
  grep -q -- '--prune-branches' "$ARGV"
  [ ! -d "$HOME/.claude/state/worktree-gc-infra.lock" ]
  grep -q 'observe=1' "$LAST"

  unset WTGC_OBSERVE
  : > "$ARGV"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  ! grep -q -- '--dry-run' "$ARGV" || false
  grep -q 'observe=0' "$LAST"
}

@test "--dispose-abandoned is NEVER passed by the cron" {
  run bash "$SUT"
  ! grep -q -- '--dispose-abandoned' "$ARGV"
}

# ── the exclude list ─────────────────────────────────────────────────────────────────────────────
# Asserted BEHAVIOURALLY (what the janitor actually receives), not by grepping the wrapper's source:
# a source grep passes just as well when the export is dead code.

@test "the exclude list carries the repo root and the postland verifier's worktrees" {
  run bash "$SUT"
  [ "$status" -eq 0 ]
  ex="$(sed -n 's/^EXCLUDE=//p' "$ENVFILE")"
  [ -n "$ex" ]
  printf '%s\n' "$ex" | tr ':' '\n' | grep -qxF "$CC_WTGC_INFRA_REPO"
  printf '%s\n' "$ex" | tr ':' '\n' | grep -qxF "$HOME/.claude/autonomy/postland"
  grep -qx 'TRUNK=origin/main' "$ENVFILE"
  grep -qx "REPO=$CC_WTGC_INFRA_REPO" "$ENVFILE"
}

# ── the fetch, and why it is not optional ────────────────────────────────────────────────────────

@test "origin/main is fetched BEFORE the sweep" {
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q 'fetch .*origin main' "$GITARGV"
}

@test "a failed fetch is verdict=nofetch and the sweep does NOT run" {
  stub_git 1
  run bash "$SUT"
  [ "$status" -eq 3 ]
  [ "$(field verdict)" = "nofetch" ]
  [ ! -f "$ARGV" ]        # a stale origin/main makes every branch read unlanded ⇒ sweeping is useless
}

# ── the verdict token ────────────────────────────────────────────────────────────────────────────

@test "verdict=ok carries the janitor's own numbers, parseably" {
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "ok" ]
  [ "$(field removed)" = "3" ]
  [ "$(field disposed)" = "0" ]
  [ "$(field kept)" = "7" ]
  [ "$(field branches)" = "41" ]
  [ "$(field refusals)" = "2" ]
  [ "$(field rc)" = "0" ]
  # the last file is exactly ONE line, and the log accumulates
  [ "$(wc -l < "$LAST" | tr -d ' ')" = "1" ]
  grep -q 'verdict=ok' "$LOG"
  grep -q 'removed 3 worktree' "$LOG"       # the janitor's full output is preserved for a human
}

@test "lock contention is verdict=skipped, NEVER a fake ok removed=0" {
  # worktree-gc.sh:324 exits 0 with no summary line when another pass holds its lock. Reducing that
  # to `ok removed=0` would be indistinguishable from a clean sweep that found nothing — the exact
  # claimed-vs-checked defect this token exists to prevent.
  stub_gc 0 'worktree-gc: another pass holds /x/worktree-gc.lock — skipping (no concurrent worktree mutation).'
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "skipped" ]
  ! grep -q 'verdict=ok' "$LAST"
}

@test "rc 0 with neither a summary nor a lock message is an error, not a success" {
  stub_gc 0 'something entirely unexpected'
  run bash "$SUT"
  [ "$status" -eq 1 ]
  [ "$(field verdict)" = "error" ]
}

@test "the janitor's REFUSAL (rc 3, no liveness oracle) surfaces as verdict=blind" {
  stub_gc 3 'worktree-gc: no liveness oracle available'
  run bash "$SUT"
  [ "$status" -eq 3 ]
  [ "$(field verdict)" = "blind" ]
}

@test "a NEW janitor exit code falls into the fail-closed arm, never a success one" {
  # A future worktree-gc.sh exit code must not be able to read as healthy just because nothing
  # here enumerates it (new-enum-member-falls-into-fail-closed-default).
  stub_gc 7 'worktree-gc: some future state'
  run bash "$SUT"
  [ "$status" -eq 7 ]
  [ "$(field verdict)" = "error" ]
  ! grep -q 'verdict=ok' "$LAST"
}

@test "a missing janitor script is an error, not a silent no-op" {
  rm -f "$CC_WTGC_INFRA_GC"
  run bash "$SUT"
  [ "$status" -eq 1 ]
  [ "$(field verdict)" = "error" ]
}

# ── the wrapper's own lock ───────────────────────────────────────────────────────────────────────

@test "a LIVE wrapper-lock holder makes the pass skip; a dead one is self-healed" {
  mkdir -p "$HOME/.claude/state/worktree-gc-infra.lock"
  echo $$ > "$HOME/.claude/state/worktree-gc-infra.lock/pid"   # this bats process is alive
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "skipped" ]
  [ ! -f "$ARGV" ]

  # dead holder → break and retake
  mkdir -p "$HOME/.claude/state/worktree-gc-infra.lock"
  echo 999999 > "$HOME/.claude/state/worktree-gc-infra.lock/pid"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "ok" ]
  [ -f "$ARGV" ]
}

# ── the plist and the fleet declaration ──────────────────────────────────────────────────────────

@test "the plist is valid, calendar-scheduled off reso's slot, and does not run at load" {
  P="$REPO_ROOT/launchd/com.claude.worktree-gc-infra.plist"
  plutil -lint "$P" >/dev/null
  [ "$(plutil -extract StartCalendarInterval.Hour raw -o - "$P")" = "4" ]
  [ "$(plutil -extract StartCalendarInterval.Minute raw -o - "$P")" = "15" ]
  [ "$(plutil -extract RunAtLoad raw -o - "$P")" = "false" ]
  [ "$(plutil -extract Label raw -o - "$P")" = "com.claude.worktree-gc-infra" ]
}

@test "the label is DECLARED in launchd/fleet.manifest (a plist without a row reds cc-fleet)" {
  grep -q '^com.claude.worktree-gc-infra *|' "$REPO_ROOT/launchd/fleet.manifest"
}
