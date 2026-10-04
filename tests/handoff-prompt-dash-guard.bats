#!/usr/bin/env bats
# Regression guard for a brief that opens with `-` — handoff-fire.sh hf_prompt_dash_guard and
# rcy_stderr_cause.
#
# THE DEFECT (2026-10-03, pane 168). Every launch line passes the brief as `launcher "$(cat F)"`.
# The recycle bridge opened with YAML frontmatter (`---\nstatus: open\n---`), claude's option parser
# read the positional as a flag, and the relaunch died in under a second with
# `error: unknown option '---…'`. The watcher waited 181 s and reported "cause UNKNOWN, read the
# launcher log" while that exact line sat in ~/.claude/logs/stderr/<ts>-<pid>.log.

setup() {
  # Pinned for the hermeticity ratchet. This suite only extracts two functions, but it names
  # handoff-fire.sh, so the seams that script reads are fixtured all the same.
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts-absent"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  REPO_SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO_SRC/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  eval "$(sed -n '/^hf_prompt_dash_guard() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^rcy_stderr_cause() {/,/^}/p' "$HF")"
  command -v hf_prompt_dash_guard >/dev/null && command -v rcy_stderr_cause >/dev/null
}

@test "a brief opening with YAML frontmatter gains ONE leading newline and is otherwise byte-identical" {
  F="$BATS_TEST_TMPDIR/copy.md"
  printf -- '---\nstatus: open\n---\n\n# Bridge\nbody\n' > "$F"
  cp "$F" "$BATS_TEST_TMPDIR/orig.md"
  run hf_prompt_dash_guard "$F"
  [ "$status" -eq 0 ]
  [ "$(head -c 1 "$F" | od -An -c | tr -d ' ')" = '\n' ]
  cmp <(tail -c +2 "$F") "$BATS_TEST_TMPDIR/orig.md"
}

@test "CONTROL: a brief that does not open with '-' is left byte-identical" {
  F="$BATS_TEST_TMPDIR/copy.md"
  printf '# Bridge\n---\nbody\n' > "$F"
  cp "$F" "$BATS_TEST_TMPDIR/orig.md"
  run hf_prompt_dash_guard "$F"
  [ "$status" -eq 0 ]
  cmp "$F" "$BATS_TEST_TMPDIR/orig.md"
}

@test "a single-dash opener (e.g. '- item') is guarded too" {
  F="$BATS_TEST_TMPDIR/copy.md"; printf -- '- first item\n' > "$F"
  hf_prompt_dash_guard "$F"
  [ "$(sed -n 2p "$F")" = "- first item" ]
}

@test "stalled boot: the launcher's own error is found by the recycle marker" {
  D="$BATS_TEST_TMPDIR/stderr"; mkdir -p "$D"
  M="HANDOFF-RECYCLE-1-2-3"
  printf "Error: unknown option '---\nstatus: open\n---\n<!-- marker: %s -->'\n" "$M" > "$D/20261003T213045-493.log"
  printf 'unrelated launch noise\n' > "$D/20261003T213050-3669.log"
  run rcy_stderr_cause "$M" "$D"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown option"* ]] || false
  [[ "$output" == *"20261003T213045-493.log"* ]] || false
}

@test "CONTROL: no log carries the marker → no cause (the verdict keeps saying UNKNOWN)" {
  D="$BATS_TEST_TMPDIR/stderr"; mkdir -p "$D"
  printf "Error: unknown option '---'\n" > "$D/a.log"
  run rcy_stderr_cause "HANDOFF-RECYCLE-other" "$D"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "CONTROL: an empty marker never matches every log" {
  D="$BATS_TEST_TMPDIR/stderr"; mkdir -p "$D"
  printf "Error: anything\n" > "$D/a.log"
  run rcy_stderr_cause "" "$D"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
