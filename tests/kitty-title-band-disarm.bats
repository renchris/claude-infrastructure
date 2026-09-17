#!/usr/bin/env bats
# kitty-title-band-disarm — THE INTERLOCK THAT KEEPS THE CRASHING CHORD DOWN.
#
# WHY THIS SUITE EXISTS. On 2026-09-16 at 20:13:49 the ⌘⇧B title-band chord SIGSEGV'd kitty
# (pid 597): EXC_BAD_ACCESS KERN_INVALID_ADDRESS at 0x20 in kitty.fast_data_types.so+840952,
# reached glfw-cocoa -> Python key dispatch -> cfunction_call. It took every pane in the only OS
# window with it and lr-select found 55 resumable sessions across 16 worktrees. Report:
# ~/Library/Logs/DiagnosticReports/kitty-2026-09-16-201349.ips · cc-backlog bf6af099a712.
#
# THE RE-ARM VECTOR IS NOT THE CHORD, IT IS THIS SCRIPT. Commenting the two `map` lines out of
# config/kitty.conf disarms the keyboard. It does NOT disarm scripts/kitty-title-band-deploy.sh,
# whose `install` path rewrites ~/.config/kitty/drag-arm.d/drag.conf with both map lines AND a
# `watcher` line — and that watcher makes every kitty started afterwards inject the shim into
# ITSELF. That is measured, not feared: kitty died at 20:13:49, its successor started at
# 20:13:53 while the drop-in was still armed, and /tmp/kitty-title-band-watcher.log's last
# record for the live process reads `installed pid=73832`.
#
# SAFETY OF THIS SUITE ITSELF. The script's socket loop globs /tmp/kitty-* and WOULD find the
# operator's live kitty. Every arm below therefore points SCRIPTS at an empty directory, so the
# run dies on the missing watcher file long before any socket is touched, and DROPIN at a temp
# path so no live config is written. No arm here executes --revert or install for real.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # FIXTURE $HOME BEFORE ANYTHING ELSE. The subject defaults both of the paths it can WRITE from
  # $HOME — KCONF=$HOME/.config/kitty/kitty.conf and DROPIN=$HOME/.config/kitty/drag-arm.d/
  # drag.conf — and the second of those is the operator's LIVE kitty config. Every arm below
  # overrides both, but a suite whose safety rests on remembering to override is one edit away
  # from writing to the live config, and the whole point of this file is that the drop-in is the
  # re-arm vector. An unfixtured $HOME here is not a style nit.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.config/kitty/drag-arm.d"
  SCRIPT="$REPO/scripts/kitty-title-band-deploy.sh"
  CONF="$REPO/config/kitty.conf"
  [ -f "$SCRIPT" ] || skip "deploy script missing"
  # The subject reads KITTY_TITLE_BAND_LOG, whose default is an absolute /tmp path that a
  # fixtured $HOME does not redirect — so pin it here or these cases touch the operator's live
  # shim log. Absent is correct: the status line these cases do not assert on degrades to unknown.
  export KITTY_TITLE_BAND_LOG="$BATS_TEST_TMPDIR/seam-absent.log"
  EMPTY="$BATS_TEST_TMPDIR/empty-scripts"; mkdir -p "$EMPTY"
  DROPIN_T="$BATS_TEST_TMPDIR/drag.conf"
  DISARMED_CONF="$BATS_TEST_TMPDIR/disarmed.conf"
  ARMED_CONF="$BATS_TEST_TMPDIR/armed.conf"
  printf '%s\n' '# DISARMED-map cmd+shift+b combine : launch --type=background x' > "$DISARMED_CONF"
  printf '%s\n' 'map cmd+shift+b combine : launch --type=background x' > "$ARMED_CONF"
}

run_install() {  # $1 = KCONF to present
  KCONF="$1" SCRIPTS="$EMPTY" DROPIN="$DROPIN_T" run bash "$SCRIPT"
}

@test "install REFUSES while the band is disarmed, and writes nothing" {
  run_install "$DISARMED_CONF"
  [ "$status" -eq 3 ] || { echo "expected exit 3 (disarm refusal), got $status"; echo "$output"; false; }
  echo "$output" | grep -q 'REFUSING TO INSTALL' || { echo "$output"; false; }
  echo "$output" | grep -q 'bf6af099a712' || { echo "the refusal does not name the open row"; echo "$output"; false; }
  [ ! -s "$DROPIN_T" ] || { echo "the drop-in was written despite the refusal:"; cat "$DROPIN_T"; false; }
}

# THE CONTROL. A guard that refuses unconditionally passes the test above for the wrong reason
# and would also block the fix forever. With an ARMED config the interlock must NOT fire: the
# run gets past it and dies on the missing watcher instead (exit 1), never reaching a socket.
@test "CONTROL: with an armed config the interlock does not fire" {
  run_install "$ARMED_CONF"
  [ "$status" -ne 3 ] || { echo "the interlock fired on an ARMED config — it is unconditional"; echo "$output"; false; }
  ! echo "$output" | grep -q 'REFUSING TO INSTALL' || { echo "refusal text on an armed config"; echo "$output"; false; }
  echo "$output" | grep -qi 'missing' || { echo "expected the missing-watcher die, got:"; echo "$output"; false; }
}

# MUTANT CONTROL: the refusal must come FROM the interlock. Strip the block and the disarmed
# arm must stop refusing — otherwise the test above is passing on something else entirely.
@test "MUTANT CONTROL: removing the interlock removes the refusal" {
  MUT="$BATS_TEST_TMPDIR/mutant-deploy.sh"
  awk '/^# ── THE DISARM INTERLOCK/{skip=1} /^\[ -f "\$WATCHER" \]/{skip=0} !skip' "$SCRIPT" > "$MUT"
  before="$(grep -c 'REFUSING TO INSTALL' "$SCRIPT")" || true
  after="$(grep -c 'REFUSING TO INSTALL' "$MUT")" || true
  [ "${before:-0}" -ge 1 ] || { echo "CONTROL VACUOUS — the unmutated script has no refusal to remove"; false; }
  [ "${after:-0}" -eq 0 ] || { echo "CONTROL FAILED — the mutation did not remove the interlock"; false; }
  KCONF="$DISARMED_CONF" SCRIPTS="$EMPTY" DROPIN="$DROPIN_T" run bash "$MUT"
  [ "$status" -ne 3 ] || { echo "CONTROL FAILED — still refusing with the interlock deleted"; echo "$output"; false; }
}

# A guard that denies its own cure is the failure this repo has met before. --revert is the ONE
# command that clears the live shim, so the disarm must never block it. Asserted STRUCTURALLY
# rather than by execution: running --revert for real would inject into the operator's live
# kitty. The property is reachability — the case arm that handles it must come FIRST — and both
# line numbers are re-derived here rather than pinned, so this cannot rot into a stale pointer.
@test "the disarm cannot block --revert or --status" {
  case_ln="$(grep -n '^case "\$MODE" in' "$SCRIPT" | head -1 | cut -d: -f1)"
  revert_ln="$(grep -n '^  --revert|revert)' "$SCRIPT" | head -1 | cut -d: -f1)"
  status_ln="$(grep -n '^  --status|status)' "$SCRIPT" | head -1 | cut -d: -f1)"
  lock_ln="$(grep -n 'REFUSING TO INSTALL' "$SCRIPT" | head -1 | cut -d: -f1)"
  for v in case_ln revert_ln status_ln lock_ln; do
    eval "x=\$$v"; [ -n "$x" ] || { echo "could not locate $v — the script's shape changed"; false; }
  done
  [ "$revert_ln" -lt "$lock_ln" ] || { echo "--revert ($revert_ln) is now BELOW the interlock ($lock_ln): the cure is blocked"; false; }
  [ "$status_ln" -lt "$lock_ln" ] || { echo "--status ($status_ln) is now BELOW the interlock ($lock_ln)"; false; }
  # and both arms exit inside the case block, so control never falls through to the interlock
  sed -n "${case_ln},${lock_ln}p" "$SCRIPT" | grep -q 'exit 0' || {
    echo "the --status/--revert arms no longer exit before the interlock"; false; }
}

# The `# DISARMED-` prefix is load-bearing for three consumers (this interlock, the polarity gate
# in kitty-conf-bindings.bats, and any human reading the config). A future session must not be
# able to keep the prefix while deleting the reason for it — that is how a disarm decays into an
# unexplained oddity somebody "cleans up".
@test "the disarm in config/kitty.conf carries its receipt" {
  grep -q '^# DISARMED-map cmd+' "$CONF" || skip "band is armed — nothing to check"
  grep -q 'kitty-2026-09-16-201349.ips' "$CONF" || { echo "the disarm does not name the crash report"; false; }
  grep -qE 'EXC_BAD_ACCESS|SIGSEGV' "$CONF" || { echo "the disarm does not name the fault"; false; }
  # NOT a count of 2. The disarm is per-chord and a PARTIAL state is legitimate: 5252bd28b
  # re-armed ⌘⇧B, which only turns real bars OFF and toggles the overlay, while deliberately
  # leaving ⌘⌥B down because it is the chord that sets window_title_bar_min_windows 1 — the only
  # state in which the shim's faulting branch runs. What must hold is that whatever IS disarmed
  # carries its reason; which chords those are is a live judgment recorded in the config itself,
  # not something this suite should freeze.
  n="$(grep -c '^# DISARMED-map cmd+' "$CONF")" || true
  [ "${n:-0}" -ge 1 ] || { echo "no chord is disarmed, but the receipt block is present"; false; }
}
