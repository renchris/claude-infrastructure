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

# ── --dispose-landed-dirt: OFF by default, and its OFF state must pass NO argument ───────────────
# The switch ships off on purpose (32 candidates exist and the janitor has never printed the class,
# so the first ON night would remove all of them before anyone read a line of evidence). What these
# pin is that BOTH states are well-formed — the off state especially, because an empty switch that
# expanded to an empty STRING would reach worktree-gc.sh's flag loop as `unknown flag ''` and turn
# the entire nightly sweep into an exit-2 no-op. A default that silently disables the whole janitor
# is a far worse bug than the feature it was guarding.
@test "landed-dirt disposal is OFF by default and passes NO empty argument" {
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ -f "$ARGV" ]
  ! grep -q -- '--dispose-landed-dirt' "$ARGV" || false
  # the off state must not smuggle an empty arg in: the recorded argv is exactly the one flag
  [ "$(tr -s ' ' '\n' < "$ARGV" | grep -c .)" -eq 1 ]
}

@test "WTGC_DISPOSE_LANDED_DIRT=1 passes the flag through (the RED-PROOF of the default)" {
  export WTGC_DISPOSE_LANDED_DIRT=1
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q -- '--dispose-landed-dirt' "$ARGV"
  grep -q -- '--prune-branches' "$ARGV"
}

@test "the flag rides alongside --dry-run in observe mode, never instead of it" {
  export WTGC_OBSERVE=1 WTGC_DISPOSE_LANDED_DIRT=1
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q -- '--dry-run' "$ARGV"
  grep -q -- '--dispose-landed-dirt' "$ARGV"
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

@test "the JANITOR's own kill switch is a disabled row here, never the parse error above it" {
  # worktree-gc.sh gained CC_WTGC_DISABLE, and a disabled janitor exits 0 printing no summary —
  # which is exactly the shape the test above files as `error`. Without this arm, an operator who
  # used the janitor's switch would be paged by the cron every night for having used it.
  stub_gc 0 'worktree-gc: verdict=disabled env=CC_WTGC_DISABLE — nothing inspected, nothing mutated.'
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "disabled" ]
  [ "$(field switch)" = "janitor" ]
  grep -q 'env=CC_WTGC_DISABLE' "$LAST"
}

@test "the janitor's FILE switch reaches the same row, carrying which switch fired" {
  stub_gc 0 'worktree-gc: verdict=disabled file=/x/worktree-gc.disabled — nothing inspected, nothing mutated.'
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "disabled" ]
  grep -q 'file=/x/worktree-gc.disabled' "$LAST"
}

@test "CONTRACT: the disabled arm matches what the REAL janitor prints, not a hand-written guess" {
  # L1 stubs the janitor everywhere — which means the ONLY thing joining these two files is a
  # string literal, and a typo on either side leaves BOTH suites green while the nightly row reads
  # `error` (second-transport / ambient-E2E: an arm nothing exercises end-to-end). So replay the
  # REAL artifact. The janitor's disabled path is the one path that is safe to run for real here:
  # it exits 0 above its first git call, so it can touch no repo, no lock and no worktree — which
  # is the property under test, asserted by running it rather than by trusting it.
  real="$(CC_WTGC_DISABLE=1 bash "$REPO_ROOT/scripts/worktree-gc.sh" 2>&1 | head -1)"
  printf '%s\n' "$real" | grep -q 'verdict=disabled'
  stub_gc 0 "$real"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "disabled" ]
  [ "$(field switch)" = "janitor" ]
}

@test "RED-PROOF: the disabled arm keys on the TOKEN, not on the word 'disabled' anywhere in output" {
  # A janitor that merely MENTIONS the word — a KEEP reason, a future message — must still be an
  # error when it printed no summary. The arm greps an anchored `worktree-gc: verdict=disabled`.
  stub_gc 0 'worktree-gc: KEEP wt-x (owner disabled the team)'
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

# ── EFFECT, NOT EXIT CODE (master 66ef300dd0b4 — fleet footprint) ────────────────
# The wrapper already refuses to call lock contention a success. These pin the same instinct on
# the quantity that actually matters: `verdict=ok removed=65 kept=126` was TRUE on 2026-08-06 and
# the population was 558 three days later, so a sweep's own numbers cannot stand in for the count.
# Every case below fixtures the worktree root, so none of them reads the real box.

# The shared root holds THREE repos' worktrees and only ours are reapable here, so `pop_root` sets
# the FOOTPRINT and `own_root` sets how many of them git reports as OURS. Keeping them separate is
# the whole point of the correction: a ceiling on the total alarmed on a healthy box for 142
# directories this janitor cannot touch.
own_root() { # <n> — make the stubbed git report n registered worktrees under the fixtured root
  cat > "$BIN/git" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$GITARGV"
if [ "\$*" = "${CC_WTGC_INFRA_REPO:-x} worktree list --porcelain" ] || case "\$*" in *"worktree list"*) true ;; *) false ;; esac; then
  i=0; while [ "\$i" -lt $1 ]; do echo "worktree $CC_WTGC_INFRA_WT_ROOT/w\$i"; i=\$((i+1)); done
fi
exit 0
EOF
  chmod +x "$BIN/git"
}

pop_root() { # <n> — a fixtured worktree root holding n directories
  export CC_WTGC_INFRA_WT_ROOT="$BATS_TEST_TMPDIR/wtroot"
  rm -rf "$CC_WTGC_INFRA_WT_ROOT"; mkdir -p "$CC_WTGC_INFRA_WT_ROOT"
  local i=0; while [ "$i" -lt "$1" ]; do mkdir -p "$CC_WTGC_INFRA_WT_ROOT/w$i"; i=$((i+1)); done
}

@test "population is on EVERY verdict row, including the ones that swept nothing" {
  pop_root 4
  mkdir -p "$(dirname "$DISABLED")"; touch "$DISABLED"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q 'verdict=disabled' "$LAST"
  grep -q 'pop=4' "$LAST"          # the row that read healthy for three days now carries the count
}

@test "population counts DIRECTORIES, not the janitor's registrations" {
  pop_root 6
  run bash "$SUT"
  grep -q 'pop=6' "$LAST"
}

@test "a sweep that leaves the population over the ceiling is over-ceiling, NEVER ok" {
  pop_root 9; own_root 9
  export CC_WTGC_INFRA_CEILING=5
  run bash "$SUT"
  [ "$status" -eq 3 ]
  grep -q 'verdict=over-ceiling' "$LAST"
  grep -q 'pop_after=9' "$LAST"
  ! grep -q 'verdict=ok' "$LAST" || false
}

# THE CORRECTION, pinned. The root is shared; a total over the ceiling that is entirely OTHER
# repos' worktrees is reported and NOT alarmed on — this janitor cannot reap them, and an alarm
# over something it cannot act on is the polarity defect that fires forever and carries no bits.
@test "over-ceiling judges OUR worktrees, never the shared root's foreign ones" {
  pop_root 9; own_root 1
  export CC_WTGC_INFRA_CEILING=5
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q 'verdict=ok' "$LAST"
  grep -q 'pop=9' "$LAST"
  grep -q 'pop_owned=1' "$LAST"
  grep -q 'pop_foreign=8' "$LAST"      # the footprint is still REPORTED, just not alarmed on
}

@test "the same sweep UNDER the ceiling is a plain ok carrying the before/after delta" {
  pop_root 3
  export CC_WTGC_INFRA_CEILING=50
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q 'verdict=ok' "$LAST"
  grep -q 'pop_before=3' "$LAST"
  grep -q 'pop_delta=0' "$LAST"
}

# The ceiling must be a CEILING, not a target: worktree-gc.sh legitimately KEEPs live, dirty and
# owned trees, so an alarm that fires at the normal resting count carries no bits at all
# (memory: alarm-polarity-and-attention-budget). This is that alarm's negative control.
@test "over-ceiling does not fire in observe mode (a dry run removes nothing by construction)" {
  pop_root 9
  export CC_WTGC_INFRA_CEILING=5 WTGC_OBSERVE=1
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q 'verdict=ok' "$LAST"
}

@test "a previous run that died mid-sweep is REPORTED, not silently self-healed away" {
  pop_root 2
  mkdir -p "$HOME/.claude/state/worktree-gc-infra.lock"
  echo 999999 > "$HOME/.claude/state/worktree-gc-infra.lock/pid"      # above PID_MAX ⇒ never live
  echo "2026-08-08 04:15:00" > "$HOME/.claude/state/worktree-gc-infra.lock/started"
  run bash "$SUT"
  grep -q 'prev=died-mid-sweep' "$LAST"
  grep -q 'prev_pid=999999' "$LAST"
  grep -q 'prev_started=2026-08-08' "$LAST"
}

@test "a CLEAN previous run leaves no death note (the positive control for the rung above)" {
  pop_root 2
  run bash "$SUT"
  ! grep -q 'died-mid-sweep' "$LAST" || false
}

@test "missed windows are measured from the last row's AGE — absence leaves no row to read" {
  pop_root 2
  mkdir -p "$(dirname "$LAST")"
  echo "2026-08-06 04:15:00  verdict=ok" > "$LAST"
  touch -t 202608060415 "$LAST"
  export CC_WTGC_INFRA_STALE_HOURS=1
  run bash "$SUT"
  grep -q 'missed_windows_h=' "$LAST"
}

# 2026-08-07 exactly: reso's 03:15 sweep ran past 04:15, this one exited `skipped`, and the next
# chance was 24 hours away. A bounded backoff recovers that night; unbounded would be a spin.
@test "janitor-lock contention is RETRIED, and the contended-attempt count is recorded" {
  pop_root 2
  stub_gc 0 'worktree-gc: another pass holds /tmp/x.lock — skipping (no concurrent worktree mutation).'
  export CC_WTGC_INFRA_LOCK_RETRIES=3 CC_WTGC_INFRA_LOCK_BACKOFF=0
  run bash "$SUT"
  [ "$(grep -c . "$ARGV")" -eq 3 ]                 # invoked 3x, not once
  grep -q 'verdict=skipped' "$LAST"
  grep -q 'lock_attempts=3' "$LAST"
}

@test "the retry is BOUNDED — a permanently held lock can never become a spin" {
  pop_root 2
  stub_gc 0 'worktree-gc: another pass holds /tmp/x.lock — skipping (no concurrent worktree mutation).'
  export CC_WTGC_INFRA_LOCK_RETRIES=2 CC_WTGC_INFRA_LOCK_BACKOFF=0
  run bash "$SUT"
  [ "$(grep -c . "$ARGV")" -eq 2 ]
}

@test "only CONTENTION is retried — a real janitor error falls straight through" {
  pop_root 2
  stub_gc 3 'worktree-gc: no liveness oracle'
  export CC_WTGC_INFRA_LOCK_RETRIES=3 CC_WTGC_INFRA_LOCK_BACKOFF=0
  run bash "$SUT"
  [ "$(grep -c . "$ARGV")" -eq 1 ]
  grep -q 'verdict=blind' "$LAST"
}

# ── --assert: the on-demand effect read ─────────────────────────────────────────
@test "--assert is READ-ONLY: it sweeps nothing, takes no lock and writes no verdict row" {
  pop_root 2
  run bash "$SUT" --assert
  [ ! -f "$ARGV" ]                                  # janitor never invoked
  [ ! -e "$HOME/.claude/state/worktree-gc-infra.lock" ]
  [ ! -f "$LAST" ]
}

@test "--assert is OK only when the population is bounded AND the verdict is fresh" {
  pop_root 3
  export CC_WTGC_INFRA_CEILING=50
  mkdir -p "$(dirname "$LAST")"; echo "x verdict=ok" > "$LAST"
  run bash "$SUT" --assert
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK bounded and fresh"* ]]
}

@test "--assert BREACHES on an over-ceiling population" {
  pop_root 9; own_root 9
  export CC_WTGC_INFRA_CEILING=5
  mkdir -p "$(dirname "$LAST")"; echo "x verdict=ok" > "$LAST"
  run bash "$SUT" --assert
  [ "$status" -eq 3 ]
  [[ "$output" == *"BREACH our worktrees 9 > ceiling 5"* ]]
}

@test "--assert reports the foreign share but does not breach on it" {
  pop_root 9; own_root 2
  export CC_WTGC_INFRA_CEILING=5
  mkdir -p "$(dirname "$LAST")"; echo "x verdict=ok" > "$LAST"
  run bash "$SUT" --assert
  [ "$status" -eq 0 ]
  [[ "$output" == *"(ours=2 foreign=7)"* ]]
}

# A stale sensor is NOT a healthy one. This is the exact state the box was in for three days.
@test "--assert BREACHES on a stale verdict even when the population is fine" {
  pop_root 3
  export CC_WTGC_INFRA_CEILING=50 CC_WTGC_INFRA_STALE_HOURS=1
  mkdir -p "$(dirname "$LAST")"; echo "x verdict=ok" > "$LAST"; touch -t 202608060415 "$LAST"
  run bash "$SUT" --assert
  [ "$status" -eq 3 ]
  [[ "$output" == *"the janitor is not running"* ]]
}

# "Never ran" and "ran and was fine" must not share an exit code — one value meaning both
# "answered no" and "could not ask" is what fabricated 80/156 findings elsewhere in this repo.
@test "--assert BREACHES when the janitor has NEVER recorded a verdict" {
  pop_root 3
  export CC_WTGC_INFRA_CEILING=50
  run bash "$SUT" --assert
  [ "$status" -eq 3 ]
  [[ "$output" == *"has never demonstrably run"* ]]
}

# The regression the kill-switch case caught (2026-08-09): pop_owned needs `git worktree list`,
# and a switch whose whole promise is inertness must not start shelling out because a new field
# wanted a number. The rows that fire before the run commits to sweeping say pop_owned=n-a — an
# honest "not measured", never a 0 that would read as "we own none of them".
@test "the kill switch stays git-free, and its row says n-a rather than a fake 0" {
  pop_root 4
  mkdir -p "$(dirname "$DISABLED")"; touch "$DISABLED"
  run bash "$SUT"
  [ ! -f "$GITARGV" ]                     # the contract tests/worktree-gc-infra.bats:79 pins
  grep -q 'pop=4' "$LAST"
  grep -q 'pop_owned=n-a' "$LAST"
  ! grep -q 'pop_owned=0' "$LAST" || false
}

# ── STRANDED VALUE (M4, backlog 0328e7cc5742) ────────────────────────────────────────────────────
# The KEEP side of the janitor had no counter-pressure: "unlanded ⇒ KEEP" is correct and is what
# stops finished work being deleted, but it is also an accumulator, and `kept=112` reports a
# worktree kept because it holds 17 unlanded patches identically to one kept because a session is
# live in it. These pin the balance being REPORTED and, past a ceiling, being called a breach.
# L1 still holds: git is stubbed, so these assert the WRAPPER's arithmetic and never real branches.

# <n-branches> [dup] — a git stub that answers the three calls stranded_scan actually makes.
# `dup` makes branch 2 carry branch 1's exact shas, which is the case that made a per-branch sum
# report 111 for 95 real patches on the live checkout.
stub_git_stranded() {
  local n="$1" dup="${2:-}"
  cat > "$BIN/git" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$GITARGV"
args=("\$@"); [ "\${args[0]}" = "-C" ] && args=("\${args[@]:2}")
case "\${args[0]}" in
  rev-parse)
    case "\${args[*]}" in *origin/main*) exit ${TRUNK_RC:-0} ;; esac; exit 0 ;;
  worktree)
    for i in \$(seq 1 $n); do printf 'worktree /w/b%s\nbranch refs/heads/b%s\n\n' "\$i" "\$i"; done; exit 0 ;;
  cherry)
    b="\${args[2]}"; src="\${b##*/}"
    [ -n "$dup" ] && [ "\$src" = "b2" ] && src=b1
    for i in \$(seq 1 3); do printf '+ %s%s\n' "\$src" "\$i"; done; exit 0 ;;
esac
exit 0
EOF
  chmod +x "$BIN/git"
}

@test "the verdict row carries the stranded balance the KEEP side accumulates" {
  pop_root 5
  stub_git_stranded 4
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q 'stranded_patches=12' "$LAST"        # 4 branches x 3 unique shas
  grep -q 'stranded_branches=4' "$LAST"
  grep -q 'stranded_ceiling=40' "$LAST"
}

@test "stranded patches are counted by UNIQUE sha — a duplicate branch is not a second strand" {
  pop_root 5
  stub_git_stranded 3 dup                      # b2 carries b1's exact shas
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q 'stranded_patches=6' "$LAST"         # 3 branches, but only b1+b3's 6 unique shas
  grep -q 'stranded_branches=3' "$LAST"
  # RED-PROOF: a per-branch SUM would have said 9 here, and would breach a ceiling nobody crossed.
  ! grep -q 'stranded_patches=9' "$LAST" || false
}

@test "past the ceiling the sweep is a stranded-over-ceiling BREACH, not a clean ok" {
  pop_root 5
  export CC_WTGC_STRANDED_CEILING=5
  stub_git_stranded 4                          # 12 unique > 5
  run bash "$SUT"
  [ "$status" -eq 3 ]
  grep -q 'verdict=stranded-over-ceiling' "$LAST"
}

# The paired keep-rule (L3): a ceiling that fired on any population would carry no bits at all.
@test "RED-PROOF: the same 12 patches UNDER the ceiling stay verdict=ok" {
  pop_root 5
  export CC_WTGC_STRANDED_CEILING=50
  stub_git_stranded 4
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q 'verdict=ok' "$LAST"
  ! grep -q 'stranded-over-ceiling' "$LAST" || false
}

# `git cherry` of 0 means LANDED; an ABSENT trunk means the question could not be asked. One value
# for both is the fabrication mode this repo has already paid for, so unmeasurable is n-a, and n-a
# never breaches — an alarm nobody can action is worse than no alarm.
@test "an unresolvable trunk reports n-a and never breaches on a question it could not ask" {
  pop_root 5
  export CC_WTGC_STRANDED_CEILING=1
  TRUNK_RC=1 stub_git_stranded 4
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q 'stranded_patches=n-a' "$LAST"
  ! grep -q 'stranded-over-ceiling' "$LAST" || false
}

# Same contract as pop_owned's n-a arm, re-pinned for the new field: stranded_scan is a per-branch
# `git cherry` loop, so an ungated row would make the DISABLED janitor the most git-expensive path
# in the file — inertness is the kill switch's entire promise.
@test "the kill switch stays git-free even with the stranded field on the row" {
  pop_root 4
  mkdir -p "$(dirname "$DISABLED")"; touch "$DISABLED"
  run bash "$SUT"
  [ ! -f "$GITARGV" ]
  grep -q 'stranded_patches=n-a' "$LAST"
  ! grep -q 'stranded_patches=0' "$LAST" || false
}
