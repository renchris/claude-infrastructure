#!/usr/bin/env bats
# The SHARED half of item 270106134cc8: the spell-correction disarm and the verified-typing
# discipline now exist in TWO files, and the whole point of the change is that they cannot drift.
#
#   · scripts/handoff-fire.sh          FIRE_NOCORRECT_LINE + _it2_type_line   (it2 CLI transport)
#   · scripts/lib/cc-type-verified.sh  CC_NOCORRECT_LINE  + _cc_tv_type_line  (osascript transport)
#
# WHY TWO COPIES AND NOT ONE SOURCED CONSTANT. handoff-fire.sh takes no source-dependency on
# anything (verified: it sources no file), and two of the lib's three callers are launchd jobs — one
# at BOOT. Making the most safety-critical script in the repo depend on a lib being deployed first
# trades a rare silent hang for a common hard failure. The repo already has this pattern and states
# it at hooks/lib/osa.sh: lead-crash-watchdog.sh "keeps its own copy on purpose … it must not depend
# on a lib file being deployed before it can spawn a watchdog". The cost of that choice is DRIFT,
# and drift is what this file makes impossible: the duplication is mechanical, so its equality is
# mechanically enforced rather than left to a reader noticing.
#
# The lint (scripts/typed-send-lint.sh) enforces that every raw send is ROUTED through a helper.
# This file enforces that the two helpers still say the SAME THING. Neither implies the other.

setup() {
  # Hermetic: this suite only reads the repo's own source, but a live $HOME is a standing hazard
  # (a suite can encode WHO ran it), so fixture it unconditionally.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # This suite only READS handoff-fire.sh (for FIRE_NOCORRECT_LINE), but naming that file at all
  # puts it in scope for the capacity gate, which refuses above 2.0/core — and this box lives well
  # above that. Pin it off so a red here can only ever mean the subject broke, never that the
  # machine was busy. (tests/test-hermeticity-lint.bats enforces this.)
  export CC_FIRE_CAPACITY_GATE=off
  # Seams whose defaults do NOT resolve under $HOME, so fixturing $HOME alone does not contain them:
  # two absolute /tmp paths and one BARE NAME the subject would execute off the operator's live PATH.
  # Absent paths are the right values here — these sensors fail open on one, and this suite only ever
  # READS source text, so it must never touch the operator's real sweep stamp, heal locks, or
  # accounts binary. (tests/test-hermeticity-lint.bats enforces this; cc-relogin-status.bats counted
  # the operator's live pending approvals for exactly this reason.)
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts-absent"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  LIB="$REPO/scripts/lib/cc-type-verified.sh"
}

@test "both disarm lines exist and are BYTE-IDENTICAL" {
  # Extracted by evaluating each file's own assignment line — the same technique
  # tests/handoff-fire-inject.bats:103 uses — so this reads the shipping value, not a copy of it.
  local fire lib
  eval "$(grep -E "^FIRE_NOCORRECT_LINE=" "$HF")"
  eval "$(grep -E "^CC_NOCORRECT_LINE=" "$LIB")"
  fire="${FIRE_NOCORRECT_LINE:-}"; lib="${CC_NOCORRECT_LINE:-}"
  [ -n "$fire" ] || { echo "handoff-fire.sh has no FIRE_NOCORRECT_LINE"; false; }
  [ -n "$lib" ]  || { echo "cc-type-verified.sh has no CC_NOCORRECT_LINE"; false; }
  [ "$fire" = "$lib" ] || {
    echo "the two disarm lines have DRIFTED:"; echo "  handoff-fire: $fire"; echo "  lib:          $lib"; false; }
}

@test "the disarm disarms BOTH correction options, and is a silent no-op under bash" {
  # Three properties the line cannot lose without reopening the hang:
  #   · `correct` AND `correct_all` — CORRECT_ALL extends correction to ARGUMENTS, so disarming only
  #     `correct` would leave an argument-triggered prompt live for any shell that sets it.
  #   · stderr suppressed + `|| true` — under bash `unsetopt` is not a builtin, so without both the
  #     line would print an error and return non-zero into a caller that may be running `set -e`.
  local lib
  eval "$(grep -E "^CC_NOCORRECT_LINE=" "$LIB")"; lib="${CC_NOCORRECT_LINE:-}"
  [[ "$lib" == *"unsetopt"* ]]      || { echo "not an unsetopt line: $lib"; false; }
  [[ "$lib" == *"correct"* ]]       || { echo "does not disarm correct: $lib"; false; }
  [[ "$lib" == *"correct_all"* ]]   || { echo "does not disarm correct_all: $lib"; false; }
  [[ "$lib" == *"2>/dev/null"* ]]   || { echo "would print an error under bash: $lib"; false; }
  [[ "$lib" == *"|| true"* ]]       || { echo "would return non-zero under bash: $lib"; false; }
  # Prove the bash claim by RUNNING it rather than asserting it: this is the shell two of the three
  # callers' panes could plausibly be, and a line that fails there would break the spawn it protects.
  run bash -c "$lib"
  [ "$status" -eq 0 ] || { echo "the disarm line is not a no-op under bash: status=$status"; false; }
}

@test "RED-PROOF: a drifted pair is actually caught" {
  # Proves the equality test above discriminates rather than passing vacuously — the same predicate,
  # applied to a deliberately drifted pair, must fail.
  local a='unsetopt correct correct_all 2>/dev/null || true'
  local b='unsetopt correct 2>/dev/null || true'
  [ "$a" != "$b" ] || false
}

@test "every rewired site routes its typed command through osa_type_verified" {
  # The three sites the item names. Asserted per-file so a regression names the file it broke.
  local f
  for f in scripts/boot-resume-launch.sh \
           scripts/limit-recover/lr-handoff.sh \
           scripts/limit-recover/lr-reset-poller.sh; do
    grep -q 'osa_type_verified' "$REPO/$f" || { echo "$f does not route through osa_type_verified"; false; }
  done
}

@test "every rewired site SOURCES the helper, and none blind-sends a command any more" {
  # Routing is not enough: a site that calls the helper without sourcing it would fail at runtime in
  # exactly the unattended context nobody watches. And a surviving `write text` of a COMMAND (as
  # opposed to a mention in prose) would mean the old path is still reachable.
  local f
  for f in scripts/boot-resume-launch.sh \
           scripts/limit-recover/lr-handoff.sh \
           scripts/limit-recover/lr-reset-poller.sh; do
    grep -q 'cc-type-verified.sh' "$REPO/$f" || { echo "$f never sources the helper"; false; }
    # Strip full-line comments, then look for a live `write text` still carrying a command.
    if sed 's/^[[:space:]]*#.*$//' "$REPO/$f" | grep -q 'write text .*exec '; then
      echo "$f still blind-sends a command with write text"; false
    fi
  done
}

@test "the helper refuses to submit when the pane cannot be read back" {
  # The load-bearing guarantee: Enter is gated on PROOF. With an osascript stub that records the
  # calls but never echoes the typed line back, the verify can never be satisfied, so the helper
  # must FAIL (rc 1) rather than hopefully sending a CR — and must send no submit at all.
  local stub="$BATS_TEST_TMPDIR/osascript" log="$BATS_TEST_TMPDIR/osa.log"
  cat > "$stub" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${OSA_LOG:?}"
exit 0
STUB
  chmod +x "$stub"
  : > "$log"
  # shellcheck disable=SC1090
  . "$LIB"
  OSA_LOG="$log" CC_OSASCRIPT_BIN="$stub" CC_TYPE_ATTEMPTS=2 CC_TYPE_SETTLE=0 CC_TYPE_PRESETTLE=0 \
    run osa_type_verified "PANE-1" "exec /bin/bash /tmp/launcher"
  [ "$status" -eq 1 ] || { echo "expected fail-loud on an unverifiable pane, got $status"; false; }
  # `write text "" newline yes` is the submit. It must NEVER appear: nothing was ever proven.
  ! grep -q 'newline yes' "$log" || { echo "the helper SUBMITTED an unverified line"; cat "$log"; false; }
}

@test "the helper DOES submit once the pane echoes the line back (positive control)" {
  # The mirror of the test above: without this, an always-refusing helper would pass that one and
  # the mechanism could be entirely broken while looking maximally safe.
  local stub="$BATS_TEST_TMPDIR/osascript2" log="$BATS_TEST_TMPDIR/osa2.log"
  cat > "$stub" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${OSA_LOG:?}"
case "$*" in
  *"contents of s"*) for a in "$@"; do case "$a" in ": cctv-"*) printf '%s\n' "$a" ;; esac; done ;;
esac
exit 0
STUB
  chmod +x "$stub"
  : > "$log"
  # shellcheck disable=SC1090
  . "$LIB"
  OSA_LOG="$log" CC_OSASCRIPT_BIN="$stub" CC_TYPE_ATTEMPTS=2 CC_TYPE_SETTLE=0 CC_TYPE_PRESETTLE=0 \
    run osa_type_verified "PANE-1" "exec /bin/bash /tmp/launcher"
  [ "$status" -eq 0 ] || { echo "expected success when the pane echoes back, got $status"; cat "$log"; false; }
  grep -q 'newline yes' "$log" || { echo "verified the line but never submitted it"; cat "$log"; false; }
}

@test "the disarm is typed as its OWN accepted line, BEFORE the command" {
  # Order is the entire mechanism: zsh CORRECT fires as a line is READ, so a disarm sharing the
  # command's buffer has not run when the command word is resolved. Both lines must be submitted,
  # and the disarm's submit must come first.
  local stub="$BATS_TEST_TMPDIR/osascript3" log="$BATS_TEST_TMPDIR/osa3.log"
  cat > "$stub" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${OSA_LOG:?}"
case "$*" in
  *"contents of s"*) for a in "$@"; do case "$a" in ": cctv-"*) printf '%s\n' "$a" ;; esac; done ;;
esac
exit 0
STUB
  chmod +x "$stub"
  : > "$log"
  # shellcheck disable=SC1090
  . "$LIB"
  OSA_LOG="$log" CC_OSASCRIPT_BIN="$stub" CC_TYPE_ATTEMPTS=2 CC_TYPE_SETTLE=0 CC_TYPE_PRESETTLE=0 \
    osa_type_verified "PANE-1" "exec /bin/bash /tmp/launcher" || true
  local dis cmd
  dis="$(grep -n 'unsetopt correct correct_all' "$log" | head -1 | cut -d: -f1)"
  cmd="$(grep -n 'exec /bin/bash /tmp/launcher' "$log" | head -1 | cut -d: -f1)"
  [ -n "$dis" ] || { echo "the disarm line was never typed"; cat "$log"; false; }
  [ -n "$cmd" ] || { echo "the command was never typed"; cat "$log"; false; }
  [ "$dis" -lt "$cmd" ] || { echo "disarm ($dis) did not precede the command ($cmd)"; cat "$log"; false; }
  # Two submits: one per accepted line. One would mean they shared a buffer.
  [ "$(grep -c 'newline yes' "$log")" -eq 2 ] \
    || { echo "expected 2 submits (disarm + command), got $(grep -c 'newline yes' "$log")"; cat "$log"; false; }
}

@test "CC_NOCORRECT=0 skips the disarm but still verifies the command" {
  # The seam must turn OFF the thing it names and NOTHING ELSE — a kill switch that also disabled
  # the echo-verify would silently reinstate the blind send it was added to remove.
  local stub="$BATS_TEST_TMPDIR/osascript4" log="$BATS_TEST_TMPDIR/osa4.log"
  cat > "$stub" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${OSA_LOG:?}"
case "$*" in
  *"contents of s"*) for a in "$@"; do case "$a" in ": cctv-"*) printf '%s\n' "$a" ;; esac; done ;;
esac
exit 0
STUB
  chmod +x "$stub"
  : > "$log"
  # shellcheck disable=SC1090
  . "$LIB"
  OSA_LOG="$log" CC_OSASCRIPT_BIN="$stub" CC_NOCORRECT=0 CC_TYPE_ATTEMPTS=2 CC_TYPE_SETTLE=0 \
    CC_TYPE_PRESETTLE=0 run osa_type_verified "PANE-1" "exec /bin/bash /tmp/launcher"
  [ "$status" -eq 0 ]
  ! grep -q 'unsetopt correct' "$log" || { echo "CC_NOCORRECT=0 still typed the disarm"; false; }
  grep -q 'exec /bin/bash /tmp/launcher' "$log" || { echo "the command was not typed"; false; }
  [ "$(grep -c 'newline yes' "$log")" -eq 1 ] || { echo "expected exactly 1 submit"; cat "$log"; false; }
}
