#!/usr/bin/env bats
# kitty-title-band-evidence — THE LOG IS THE ONLY EVIDENCE THE LIVE KITTY IS SHIMMED.
#
# /tmp/kitty-title-band-watcher.log is how anyone answers "is the operator's kitty still
# patched?". `shim_state()` reads it per-pid, and its own comment states the contract: "the LAST
# line naming this pid wins, because install and uninstall both append" — an APPEND-ONLY store.
#
# Two things erased it anyway, and the reader failed toward the reassuring answer:
#   1. deploy.sh truncated it (`: > "$LOG"`) at the top of every install, discarding the records
#      of every OTHER live kitty — exactly the per-instance verdict the function exists to give.
#   2. shim-verify.sh `rm -f`'d it during sandbox cleanup, so running the TEST destroyed the
#      production evidence.
#   3. shim_state() then read an absent log as `not installed` — indistinguishable from a clean
#      machine, returned over a process that is STILL PATCHED. A false all-clear on a live crash
#      hazard, and in the direction nobody re-checks. (fail-safe-default-mimics-the-healthy-state)
#
# The verdict now has THREE states. Absence and silence are UNKNOWN; only an explicit
# `uninstalled` record means not installed. These cases pin all three, because a fix that merely
# renamed the default would satisfy any one of them alone.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPT="$REPO/scripts/kitty-title-band-deploy.sh"
  [ -f "$SCRIPT" ] || skip "deploy script missing"
  # PIN THE SEAM IN setup(), not only in the helper. KITTY_TITLE_BAND_LOG defaults to an
  # ABSOLUTE /tmp path that fixturing $HOME cannot redirect, so a case added later that forgot
  # to set it would read and write the OPERATOR's live shim log — the very store this suite
  # exists to protect. An absent path is the right default: shim_state fails to "unknown" on one.
  export KITTY_TITLE_BAND_LOG="$BATS_TEST_TMPDIR/seam-absent.log"
  LOGF="$BATS_TEST_TMPDIR/watcher.log"
  SOCK="/tmp/kitty-4242"          # a NAME, never created: shim_state parses the pid out of it
}
state() { KITTY_TITLE_BAND_LOG="$LOGF" run bash "$SCRIPT" --shim-state "$SOCK"; }

@test "RED-PROOF: an ABSENT log is unknown, never 'not installed'" {
  rm -f "$LOGF"
  state
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  echo "$output" | grep -qi 'unknown' || {
    echo "an absent log reported '$output' — a false all-clear over a possibly-shimmed process"
    false; }
  ! echo "$output" | grep -q 'not installed' || { echo "still claims not-installed: $output"; false; }
}

@test "RED-PROOF: a log with NO record for this pid is unknown" {
  printf 'installed pid=9999\n' > "$LOGF"      # some OTHER instance
  state
  echo "$output" | grep -qi 'unknown' || { echo "got '$output', expected unknown"; false; }
}

# CONTROLS. Without these, "report unknown" could be satisfied by a function that says unknown
# unconditionally — which would destroy the real verdict instead of sharpening it.
@test "CONTROL: an explicit installed record still reads INSTALLED" {
  printf 'installed pid=4242\n' > "$LOGF"
  state
  echo "$output" | grep -q 'INSTALLED' || { echo "got '$output'"; false; }
}

@test "CONTROL: an explicit uninstalled record still reads not installed" {
  printf 'installed pid=4242\nuninstalled pid=4242\n' > "$LOGF"
  state
  echo "$output" | grep -q 'not installed' || { echo "got '$output'"; false; }
  ! echo "$output" | grep -q 'INSTALLED' || { echo "last record must win: $output"; false; }
}

@test "CONTROL: the LAST record naming the pid wins, in both directions" {
  printf 'uninstalled pid=4242\ninstalled pid=4242\n' > "$LOGF"
  state
  echo "$output" | grep -q 'INSTALLED' || { echo "got '$output'"; false; }
}

# RATCHETS on the two erasers. These are the defect, not a style point: each one silently
# converted a known state into the reassuring one.
@test "no script truncates or deletes the SHARED watcher log" {
  # COMMENTS ARE STRIPPED BEFORE THE VERDICT. The fix itself adds lines reading
  # "NEVER rm the shared /tmp/kitty-title-band-watcher.log", and a ratchet that fires on the
  # prose explaining it would be unsatisfiable by any correct tree. `#` is only treated as a
  # comment at line start or after whitespace, so ${var#prefix} survives the strip.
  hits="$BATS_TEST_TMPDIR/hits"; : > "$hits"
  while IFS= read -r f; do
    sed 's/^[[:space:]]*#.*//; s/[[:space:]]#.*//' "$f" \
      | grep -nE '(^|[;&|[:space:]])(rm([[:space:]]+-[a-zA-Z]+)*|:[[:space:]]*>)[[:space:]][^|;&]*/tmp/kitty-title-band-watcher\.log' \
      | sed "s|^|${f#"$REPO/"}:|" >> "$hits" || true
  done < <(find "$REPO/scripts" -type f \( -name '*.sh' -o -name '*.py' \) 2>/dev/null)
  if [ -s "$hits" ]; then
    echo "a script erases the shared evidence log — the only record of whether the operator's"
    echo "kitty is still shimmed. Give the sandbox its own log instead:"
    cat "$hits"
    false
  fi
}

# The ratchet above must be able to FIRE, or its green says nothing.
@test "MUTANT CONTROL: the eraser ratchet sees a reintroduced rm" {
  mkdir -p "$BATS_TEST_TMPDIR/scripts"
  printf '#!/bin/sh\nrm -f /tmp/kitty-title-band-watcher.log\n' > "$BATS_TEST_TMPDIR/scripts/evil.sh"
  run bash -c '
    sed "s/^[[:space:]]*#.*//; s/[[:space:]]#.*//" "$1" \
      | grep -cE "(^|[;&|[:space:]])(rm([[:space:]]+-[a-zA-Z]+)*|:[[:space:]]*>)[[:space:]][^|;&]*/tmp/kitty-title-band-watcher\.log"
  ' _ "$BATS_TEST_TMPDIR/scripts/evil.sh"
  [ "$output" = "1" ] || { echo "CONTROL VACUOUS — the pattern did not match a plain rm: got '$output'"; false; }
  # and it must NOT match the prose the fix adds
  printf '%s\n' '# NEVER rm the shared /tmp/kitty-title-band-watcher.log: it is the evidence.' \
    > "$BATS_TEST_TMPDIR/scripts/comment.sh"
  run bash -c '
    sed "s/^[[:space:]]*#.*//; s/[[:space:]]#.*//" "$1" \
      | grep -cE "(^|[;&|[:space:]])(rm([[:space:]]+-[a-zA-Z]+)*|:[[:space:]]*>)[[:space:]][^|;&]*/tmp/kitty-title-band-watcher\.log"
  ' _ "$BATS_TEST_TMPDIR/scripts/comment.sh"
  [ "$output" = "0" ] || { echo "CONTROL FAILED — the ratchet fires on a COMMENT: got '$output'"; false; }
}

@test "deploy.sh appends to its log, never truncates it" {
  ! grep -qE '^\s*: > "\$LOG"' "$SCRIPT" || {
    echo "deploy.sh truncates \$LOG — that discards every OTHER live kitty's record,"
    echo "which is the per-instance verdict shim_state() exists to give."
    false; }
}
