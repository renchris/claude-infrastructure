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
  # WTGC_INFRA_SUT points the suite at another copy (the RED proof runs it against the pre-change file).
  SUT="${WTGC_INFRA_SUT:-$REPO_ROOT/scripts/worktree-gc-infra-run.sh}"

  # A stand-in repo directory — the wrapper only needs it to EXIST (the janitor, which is stubbed,
  # is what would need it to be a git checkout).
  export CC_WTGC_INFRA_REPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$CC_WTGC_INFRA_REPO"

  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  ARGV="$BATS_TEST_TMPDIR/gc.argv"        # janitor invocation record; ABSENT ⇒ never invoked
  ENVFILE="$BATS_TEST_TMPDIR/gc.env"
  GITARGV="$BATS_TEST_TMPDIR/git.argv"

  export CC_WTGC_INFRA_GC="$BIN/gc-stub.sh"
  export CC_WTGC_GIT="$BIN/git"
  export CC_WTGC_INFRA_FETCH_BACKOFF=0    # the retry's sleep, never wall clock in a test
  stub_git 0
  # ⚠️ THIS PAYLOAD IS THE JANITOR'S REAL CONTRACT AND MUST TRACK IT. It used to hold the pre-§9
  # five-number summary (no `landed-dirt`), and because L1 stubs the janitor, that stale fixture is
  # precisely why this suite could not see the wrapper's positional reader go off by one when the
  # real janitor gained a sixth number. A stub frozen at an older format tests the wrapper against
  # a world that no longer exists. Both lines below are copied from scripts/worktree-gc.sh's
  # emitter: the human summary (six numbers now) AND the machine `counts` line the wrapper reads.
  stub_gc 0 'worktree-gc: removed 3 worktree(s) · disposed 0 abandoned · 5 landed-dirt · kept 7 · deleted 41 branch(es) · 2 refusal(s)
worktree-gc: counts removed=3 disposed=0 landed_dirt=5 kept=7 branches_deleted=41 refusals=2 elapsed=12s lock_staleness_window=3600s dry_run=0'

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

# stub_git_fetch <fetch-failures> <fetch-rc> <rev-parse-rc>: the first N `fetch` calls exit
# <fetch-rc>, later ones exit 0; `rev-parse` (is there ANY origin/main?) exits <rev-parse-rc>;
# every other git call exits 0. Counted in a file, because each call is a fresh process.
stub_git_fetch() {
  cat > "$BIN/git" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$GITARGV"
case " \$* " in
  *" fetch "*)
    n=\$(( \$(cat "$BATS_TEST_TMPDIR/fetch.n" 2>/dev/null || echo 0) + 1 ))
    echo "\$n" > "$BATS_TEST_TMPDIR/fetch.n"
    [ "\$n" -le $1 ] && exit $2
    exit 0 ;;
  *" rev-parse "*) exit $3 ;;
esac
exit 0
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
# FLIPPED 2026-09-30 (eed2530a4165): ON by default, after the nightly log printed the class on every
# run for four weeks and it never had a member. The OFF state keeps its own case, because the
# empty-argument hazard above is a property of OFF, whichever state is the default.
@test "landed-dirt disposal is ON by default" {
  run bash "$SUT"
  [ "$status" -eq 0 ]
  grep -q -- '--dispose-landed-dirt' "$ARGV"
  grep -q -- '--prune-branches' "$ARGV"
}

@test "WTGC_DISPOSE_LANDED_DIRT=0 turns it off and passes NO empty argument" {
  export WTGC_DISPOSE_LANDED_DIRT=0
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ -f "$ARGV" ]
  ! grep -q -- '--dispose-landed-dirt' "$ARGV" || false
  # the off state must not smuggle an empty arg in: the recorded argv is exactly the one flag
  [ "$(tr -s ' ' '\n' < "$ARGV" | grep -c .)" -eq 1 ]
}

@test "WTGC_DISPOSE_LANDED_DIRT=1 passes the flag through" {
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

# 2026-09-29 04:31: one fetch timed out at its 300 s bound and the whole night swept nothing
# (pop 282). The fetch is retried, and a fetch that never succeeds sweeps the last-known trunk.
@test "a fetch that fails once and then succeeds is retried — verdict=ok, the attempts recorded" {
  stub_git_fetch 1 124 0
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "ok" ]
  [ "$(field fetch_attempts)" = "2" ]
  [ "$(grep -c ' fetch ' "$GITARGV")" -eq 2 ]
  grep -q -- '--dispose-landed-dirt' "$ARGV"
}

@test "the fetch never tags and never auto-gcs inside its bound" {
  run bash "$SUT"
  grep ' fetch ' "$GITARGV" | grep -q -- '--no-tags'
  grep ' fetch ' "$GITARGV" | grep -q 'gc.auto=0'
}

@test "a fetch that fails every attempt still SWEEPS the stale trunk — nofetch rc 3, dirt disposal OFF" {
  stub_git_fetch 99 124 0
  run bash "$SUT"
  [ "$status" -eq 3 ]
  [ "$(field verdict)" = "nofetch" ]
  [ "$(field trunk)" = "stale" ]
  [ "$(field reason)" = "timeout" ]
  [ "$(field fetch_attempts)" = "3" ]
  [ "$(field removed)" = "3" ]            # the janitor's own numbers ride the row
  [ -f "$ARGV" ]                          # a stale trunk can only turn a delete into a KEEP
  grep -q -- '--prune-branches' "$ARGV"
  # the one class that compares bytes against the tree this run could NOT fetch is held back,
  # even with the switch explicitly on
  ! grep -q -- '--dispose-landed-dirt' "$ARGV" || false
}

@test "no origin/main at all is no oracle — verdict=nofetch and the sweep does NOT run" {
  stub_git_fetch 99 1 1
  run bash "$SUT"
  [ "$status" -eq 3 ]
  [ "$(field verdict)" = "nofetch" ]
  [ "$(field trunk)" = "absent" ]
  [ ! -f "$ARGV" ]
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
# The fleet.manifest row for this label is owned by tests/fleet-manifest-lint.bats ("the REAL repo
# is clean"), which reds on any committed launchd plist without a manifest row.

@test "the plist is valid, calendar-scheduled off reso's slot, and does not run at load" {
  P="$REPO_ROOT/launchd/com.claude.worktree-gc-infra.plist"
  plutil -lint "$P" >/dev/null
  [ "$(plutil -extract StartCalendarInterval.Hour raw -o - "$P")" = "4" ]
  [ "$(plutil -extract StartCalendarInterval.Minute raw -o - "$P")" = "15" ]
  [ "$(plutil -extract RunAtLoad raw -o - "$P")" = "false" ]
  [ "$(plutil -extract Label raw -o - "$P")" = "com.claude.worktree-gc-infra" ]
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

# ── the machine `counts` line, and the off-by-one it retired ────────────────────────────────────
# The wrapper used to reduce the HUMAN summary with `tr -cd '0-9 \n'` and take five fields by
# POSITION. That was correct until §9 inserted `landed-dirt` as the third number, after which
# kept/branches/refusals each shifted one place left and the refusal count fell off the end —
# silently, exit 0, in every nightly row. These pin the named reader that replaced it.

@test "counts line is read BY NAME — every field lands in its own slot" {
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "ok" ]
  [ "$(field removed)" = "3" ]
  [ "$(field disposed)" = "0" ]
  [ "$(field kept)" = "7" ]           # 7, NOT 5 — 5 is landed_dirt, which the old reader logged here
  [ "$(field branches)" = "41" ]      # 41, NOT 7
  [ "$(field refusals)" = "2" ]       # 2, NOT 41 — and it is not dropped
  [ "$(field dirt)" = "5" ]
}

@test "RED PROOF: the exact shift the positional reader produced is now impossible" {
  # Truth: removed=7 disposed=3 dirt=5 kept=11 branches=2 refusals=9.
  # The old reader logged: kept=5 branches=11 refusals=2. Assert we get the TRUTH.
  stub_gc 0 'worktree-gc: removed 7 worktree(s) · disposed 3 abandoned · 5 landed-dirt · kept 11 · deleted 2 branch(es) · 9 refusal(s)
worktree-gc: counts removed=7 disposed=3 landed_dirt=5 kept=11 branches_deleted=2 refusals=9 elapsed=1128s lock_staleness_window=3600s dry_run=0'
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(field kept)" = "11" ]
  [ "$(field branches)" = "2" ]
  [ "$(field refusals)" = "9" ]
  [ "$(field elapsed)" = "1128s" ]
}

@test "a summary WITHOUT the counts line fails CLOSED — never a silent mis-parse" {
  # An old janitor against this wrapper. The known-wrong positional path was deliberately NOT
  # kept as a fallback: a wrong number that looks right is worse than a loud absent one.
  stub_gc 0 'worktree-gc: removed 7 worktree(s) · disposed 3 abandoned · 5 landed-dirt · kept 11 · deleted 2 branch(es) · 9 refusal(s)'
  run bash "$SUT"
  [ "$(field verdict)" = "error" ]
  [ "$(field reason)" = "no-counts-line" ]
}

@test "elapsed is carried into the row, and is n-a (never 0) when the janitor omits it" {
  stub_gc 0 'worktree-gc: removed 0 worktree(s) · disposed 0 abandoned · 0 landed-dirt · kept 0 · deleted 0 branch(es) · 0 refusal(s)
worktree-gc: counts removed=0 disposed=0 landed_dirt=0 kept=0 branches_deleted=0 refusals=0 dry_run=0'
  run bash "$SUT"
  [ "$(field elapsed)" = "n-a" ]      # unknown must not read as instantaneous
}

# ── WP-15: --auto / --wake, event mode, pins, and the foreign backstop (DESIGN §3.4) ─────────────
# The plist runs `--auto` from three triggers (04:15 calendar, WatchPaths on the wake file,
# StartInterval 600), so "is the backstop due?" is decided from the log. Event mode is observe unless
# the operator's activation script wrote `act`; in observe the home janitor's argv must be exactly
# what it was before WP-15. Foreign repos are dry-run until promoted (OP-5), park first, and never
# get --prune-branches, --dispose-landed-dirt or a fetch. Each case below stubs the janitor, the
# wake evaluator and the pin library, and builds throwaway foreign repos under $BATS_TEST_TMPDIR.

wp15_setup() {
  unset WTGC_EVENTS
  CALLS="$BATS_TEST_TMPDIR/gc.calls"
  WAKECALLS="$BATS_TEST_TMPDIR/wake.calls"
  PINCALLS="$BATS_TEST_TMPDIR/pins.calls"
  FLOG="$HOME/.claude/logs/worktree-gc-foreign.log"
  export DEV="$BATS_TEST_TMPDIR/dev"; mkdir -p "$DEV" "$HOME/.claude/autonomy"
  export CC_WTGC_INFRA_DEV_ROOT="$DEV"
  export CC_WTGC_EVENTS_MODE_FILE="$HOME/.claude/autonomy/worktree-gc-events.mode"
  export CC_WTGC_PROMOTED_FILE="$HOME/.claude/autonomy/worktree-gc-repos.promoted"
  export CC_WTGC_ARCHIVE_FLOOR_FILE="$HOME/.claude/autonomy/worktree-gc-archive-floor.gb"
  REAL_GIT="$(PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v git)"

  export CC_WTGC_WAKE_SH="$BIN/wake-stub.sh"
  cat > "$CC_WTGC_WAKE_SH" <<EOF
#!/bin/bash
echo "wake \$*" >> "$WAKECALLS"
exit 0
EOF

  export CC_WTGC_TOMBSTONE_LIB="$BIN/tomb-stub.sh"
  cat > "$CC_WTGC_TOMBSTONE_LIB" <<EOF
wt_pin_lock_sync() {
  printf '%s\n' "\$*" >> "$PINCALLS"
  [ "\${2:-}" = --observe ] && echo "wt-tombstone: would_lock \$1/wt-pinned crash" >&2
  return 0
}
EOF

  # One record per janitor call: repo|trunk|exclude|archive-floor|argv. GC_FAIL_REPO, GC_SLEEP_REPO
  # and GC_DISABLED_REPO make one run fail, hang, or report the janitor's own kill switch.
  cat > "$CC_WTGC_INFRA_GC" <<EOF
#!/bin/bash
printf '%s|%s|%s|%s|%s\n' "\$CC_WTGC_REPO" "\$CC_WTGC_TRUNK" "\$CC_WTGC_EXCLUDE" "\${CC_WTGC_ARCHIVE_FLOOR_GB:-}" "\$*" >> "$CALLS"
printf '%s\n' "\$*" >> "$ARGV"
if [ "\$CC_WTGC_REPO" = "\${GC_FAIL_REPO:-none}" ]; then echo 'boom'; exit 7; fi
if [ "\$CC_WTGC_REPO" = "\${GC_SLEEP_REPO:-none}" ]; then sleep 5; fi
if [ "\$CC_WTGC_REPO" = "\${GC_DISABLED_REPO:-none}" ]; then echo 'worktree-gc: verdict=disabled env=CC_WTGC_DISABLE'; exit 0; fi
echo 'worktree-gc: removed 3 worktree(s) · disposed 0 abandoned · 5 landed-dirt · kept 7 · deleted 41 branch(es) · 2 refusal(s)'
echo 'worktree-gc: counts removed=3 disposed=0 landed_dirt=5 kept=7 branches_deleted=41 refusals=2 elapsed=12s lock_staleness_window=3600s dry_run=0'
case " \$* " in *" --park-first "*)
  echo 'KEEP    /x/wt1 [b1] — dirty and young'
  echo 'would park    /x/wt2 [b2] — arm-i (clean, quiet 2d)'
  echo 'worktree-gc: park-first parked=1 detached=0 archived=0 pop_active=4 pop_parked=1 dry_run=1' ;;
esac
exit 0
EOF
  chmod +x "$CC_WTGC_WAKE_SH" "$CC_WTGC_INFRA_GC"
}

# Real git for the foreign repos (the scope table reads origin/HEAD), every call logged, and every
# fetch a logged no-op success, so "never fetched a foreign repo" is assertable from GITARGV.
stub_git_real() {
  cat > "$BIN/git" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$GITARGV"
case " \$* " in *" fetch "*) exit 0 ;; esac
exec "$REAL_GIT" "\$@"
EOF
  chmod +x "$BIN/git"
}

mk_repo() { # <name> [--no-trunk] — a throwaway main checkout under $DEV, origin/HEAD → origin/main
  local r="$DEV/$1"; mkdir -p "$r"
  "$REAL_GIT" -C "$r" init -q
  "$REAL_GIT" -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  if [ "${2:-}" != --no-trunk ]; then
    "$REAL_GIT" -C "$r" update-ref refs/remotes/origin/main HEAD
    "$REAL_GIT" -C "$r" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
  fi
}

calls_for() { grep "^$1|" "$CALLS" 2>/dev/null; }   # <repo-root> → that repo's janitor records

epoch_at() { date -j -f '%Y-%m-%d %H:%M:%S' "$1" +%s; }   # <local 'Y-m-d H:M:S'> → epoch (BSD date)
backstop_row() { mkdir -p "$(dirname "$LOG")"; printf '%s  verdict=ok observe=0 rc=0\n' "$1" >> "$LOG"; }

@test "--auto before 04:15 runs the wake evaluator and sweeps nothing" {
  wp15_setup
  backstop_row '2026-10-16 04:15:30'
  CC_WTGC_INFRA_NOW="$(epoch_at '2026-10-17 03:00:00')" run bash "$SUT" --auto </dev/null
  [ "$status" -eq 0 ]
  [ "$(grep -c '^wake' "$WAKECALLS")" -eq 1 ]
  [ ! -f "$ARGV" ]
  [ ! -f "$GITARGV" ]          # a tick decides from the log alone: no git, no fetch
}

@test "--auto after 04:15 when today's backstop already ran is a wake tick, not a second sweep" {
  wp15_setup
  backstop_row '2026-10-17 04:15:10'
  CC_WTGC_INFRA_NOW="$(epoch_at '2026-10-17 05:00:00')" run bash "$SUT" --auto </dev/null
  [ "$status" -eq 0 ]
  [ "$(grep -c '^wake' "$WAKECALLS")" -eq 1 ]
  [ ! -f "$ARGV" ]
}

@test "--auto after 04:15 with only yesterday's row runs the backstop (a calendar fire missed in sleep)" {
  wp15_setup
  backstop_row '2026-10-16 04:15:30'
  CC_WTGC_INFRA_NOW="$(epoch_at '2026-10-17 09:40:00')" run bash "$SUT" --auto </dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$WAKECALLS" ]
  [ "$(calls_for "$CC_WTGC_INFRA_REPO" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(field verdict)" = "ok" ]
  [ "$(grep -c '  verdict=' "$LOG")" -eq 2 ]
}

@test "--auto after 04:15 with no backstop row at all runs the backstop" {
  wp15_setup
  CC_WTGC_INFRA_NOW="$(epoch_at '2026-10-17 04:15:00')" run bash "$SUT" --auto </dev/null
  [ "$status" -eq 0 ]
  [ ! -f "$WAKECALLS" ]
  [ -f "$ARGV" ]
}

@test "--wake runs only the wake evaluator, even when a backstop would be due" {
  wp15_setup
  CC_WTGC_INFRA_NOW="$(epoch_at '2026-10-17 05:00:00')" run bash "$SUT" --wake </dev/null
  [ "$status" -eq 0 ]
  [ "$(grep -c '^wake' "$WAKECALLS")" -eq 1 ]
  [ ! -f "$ARGV" ]
  [ ! -f "$LAST" ]
}

@test "event mode observe: the home janitor's argv and env are exactly today's, no --park-first" {
  wp15_setup
  echo 40 > "$CC_WTGC_ARCHIVE_FLOOR_FILE"     # present, but only act may read it
  run bash "$SUT" </dev/null
  [ "$status" -eq 0 ]
  [ "$(calls_for "$CC_WTGC_INFRA_REPO")" = "$CC_WTGC_INFRA_REPO|origin/main|$CC_WTGC_INFRA_REPO:$HOME/.claude/autonomy/postland||--prune-branches --dispose-landed-dirt" ]
}

@test "event mode act (from the operator's mode file): --park-first and the archive floor reach the home janitor" {
  wp15_setup
  echo act > "$CC_WTGC_EVENTS_MODE_FILE"
  echo 40 > "$CC_WTGC_ARCHIVE_FLOOR_FILE"
  run bash "$SUT" </dev/null
  [ "$status" -eq 0 ]
  [ "$(calls_for "$CC_WTGC_INFRA_REPO")" = "$CC_WTGC_INFRA_REPO|origin/main|$CC_WTGC_INFRA_REPO:$HOME/.claude/autonomy/postland|40|--prune-branches --dispose-landed-dirt --park-first" ]
}

@test "event mode act with a malformed floor file parks first but exports no floor" {
  wp15_setup
  export WTGC_EVENTS=act
  echo 'forty GB' > "$CC_WTGC_ARCHIVE_FLOOR_FILE"
  run bash "$SUT" </dev/null
  calls_for "$CC_WTGC_INFRA_REPO" | grep -q -- '--park-first'
  [ "$(calls_for "$CC_WTGC_INFRA_REPO" | cut -d'|' -f4)" = "" ]
}

@test "pins: the home repo is synced --observe in observe mode, for real in act mode" {
  wp15_setup
  run bash "$SUT" </dev/null
  [ "$(cat "$PINCALLS")" = "$CC_WTGC_INFRA_REPO --observe" ]
  grep -q "repo=repo scope=home mode=observe pins would_lock=1 would_unlock=0" "$FLOG"
  grep -q "^    wt-tombstone: would_lock $CC_WTGC_INFRA_REPO/wt-pinned crash" "$FLOG"

  : > "$PINCALLS"
  WTGC_EVENTS=act run bash "$SUT" </dev/null
  [ "$(cat "$PINCALLS")" = "$CC_WTGC_INFRA_REPO" ]
}

@test "foreign repo, observe: --park-first --dry-run only — no --prune-branches, no landed-dirt, no fetch" {
  wp15_setup; stub_git_real
  mk_repo foo
  run bash "$SUT" </dev/null
  [ "$status" -eq 0 ]
  [ "$(calls_for "$DEV/foo")" = "$DEV/foo|origin/main|$DEV/foo||--park-first --dry-run" ]
  ! grep -E -- "-C $DEV/foo .*fetch|fetch.*$DEV/foo" "$GITARGV" || false
  grep -q "$DEV/foo --observe" "$PINCALLS"
  grep -q "repo=foo mode=observe trunk=origin/main rc=0 would_park=1 would_detach=0 would_keep=7 would_lock=1" "$FLOG"
  grep -q '^    KEEP    /x/wt1 \[b1\] — dirty and young' "$FLOG"
  grep -q '^    would park    /x/wt2' "$FLOG"
}

@test "foreign repo, act but NOT promoted: still a dry run" {
  wp15_setup; stub_git_real
  mk_repo foo
  WTGC_EVENTS=act run bash "$SUT" </dev/null
  [ "$(calls_for "$DEV/foo" | cut -d'|' -f5)" = "--park-first --dry-run" ]
  grep -q "$DEV/foo --observe" "$PINCALLS"
}

@test "foreign repo, promoted AND act: parks first for real, pins for real, still no branch prune" {
  wp15_setup; stub_git_real
  mk_repo foo
  echo "$DEV/foo/.git" > "$CC_WTGC_PROMOTED_FILE"
  WTGC_EVENTS=act run bash "$SUT" </dev/null
  [ "$status" -eq 0 ]
  [ "$(calls_for "$DEV/foo" | cut -d'|' -f5)" = "--park-first" ]
  grep -qx "$DEV/foo" "$PINCALLS"
  grep -q "repo=foo mode=act trunk=origin/main rc=0 parked=1 detached=0 kept=7" "$FLOG"
}

@test "reso-management-app is skipped (its own janitor owns it), logged scope=excluded" {
  wp15_setup; stub_git_real
  mk_repo reso-management-app
  run bash "$SUT" </dev/null
  [ -z "$(calls_for "$DEV/reso-management-app")" ]
  ! grep -q "$DEV/reso-management-app" "$PINCALLS" || false
  grep -q 'repo=reso-management-app scope=excluded' "$FLOG"
}

@test "a repo with no origin/HEAD is skipped, logged scope=no-trunk; a worktree's .git FILE is never a repo" {
  wp15_setup; stub_git_real
  mk_repo bar --no-trunk
  mkdir -p "$DEV/linked"; echo "gitdir: $DEV/bar/.git/worktrees/linked" > "$DEV/linked/.git"
  run bash "$SUT" </dev/null
  [ -z "$(calls_for "$DEV/bar")" ]
  [ -z "$(calls_for "$DEV/linked")" ]
  grep -q 'repo=bar scope=no-trunk' "$FLOG"
  ! grep -q 'repo=linked' "$FLOG" || false
}

@test "the home repo is never swept a second time as a foreign one" {
  wp15_setup; stub_git_real
  mk_repo home
  export CC_WTGC_INFRA_REPO="$DEV/home"
  run bash "$SUT" </dev/null
  [ "$(calls_for "$DEV/home" | wc -l | tr -d ' ')" -eq 1 ]
  ! grep -q 'repo=home mode=' "$FLOG" || false
}

@test "a FAILED foreign run leaves the home verdict line and exit code byte-identical" {
  wp15_setup; stub_git_real
  run bash "$SUT" </dev/null
  base_status="$status"; base_line="$(cut -c20- "$LAST")"
  mk_repo foo
  GC_FAIL_REPO="$DEV/foo" run bash "$SUT" </dev/null
  [ "$status" -eq "$base_status" ]
  [ "$(cut -c20- "$LAST")" = "$base_line" ]
  grep -q 'repo=foo mode=observe trunk=origin/main rc=7 would_park=n-a' "$FLOG"
}

@test "a HUNG foreign run is bounded and logged rc=timeout; the home verdict is untouched" {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1 || skip "no timeout(1)"
  wp15_setup; stub_git_real
  mk_repo foo
  CC_WTGC_FOREIGN_BOUND=1 GC_SLEEP_REPO="$DEV/foo" run bash "$SUT" </dev/null
  [ "$status" -eq 0 ]
  [ "$(field verdict)" = "ok" ]
  grep -q 'repo=foo mode=observe trunk=origin/main rc=timeout' "$FLOG"
}

@test "the kill switch and the janitor's own switch both skip the pins and the foreign pass" {
  wp15_setup; stub_git_real
  mk_repo foo
  mkdir -p "$(dirname "$DISABLED")"; : > "$DISABLED"
  run bash "$SUT" </dev/null
  [ "$(field verdict)" = "disabled" ]
  [ ! -f "$CALLS" ]; [ ! -f "$PINCALLS" ]; [ ! -f "$FLOG" ]

  rm -f "$DISABLED"
  GC_DISABLED_REPO="$CC_WTGC_INFRA_REPO" run bash "$SUT" </dev/null
  [ "$(field verdict)" = "disabled" ]
  [ -z "$(calls_for "$DEV/foo")" ]; [ ! -f "$PINCALLS" ]; [ ! -f "$FLOG" ]
}
