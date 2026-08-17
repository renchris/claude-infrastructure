#!/usr/bin/env bats
# validate-bash AUDIT LOGGER — the tail of hooks/validate-bash.sh, after every decision is made.
#
# WHY THIS SUITE EXISTS. The fork census of 2026-08-17
# (docs/research/validate-bash-fork-census-2026-08-17.md §6, levers 2-3) measured the last four
# lines of the hook forking `jq` + `mkdir` + `date` on EVERY invocation — 7.2 ms, 10% of the modal
# path's 71.9 ms, to append one audit line. The `mkdir -p` created a directory that already existed
# on every call after the first; the `date` duplicated a stamp the `jq` beside it could emit.
# Collapsing them changes NO danger pattern — this code runs after the gate has already decided —
# but it does change the audit line's PRODUCER, and the audit line is what every fleet rate in
# HOOK_CHAIN_COST.md is derived from. So the contract that must not move is the LINE SHAPE:
#
#     [<ISO-8601 UTC>] [<session-id or ->] <command>
#
# Each assertion below pins one half of that shape, and (5) is the control that can FAIL: an
# anchor-checked mutant that drops `todateiso8601` from the collapsed jq must produce a line whose
# timestamp field is empty, so a green suite credits THIS code and not the fixture
# (MEMORY.md control-must-replay-the-real-artifact, per-site-mutation-attributes-coverage).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  D="$BATS_TEST_TMPDIR"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_SHARED_CHECKOUT="$D/shared"; mkdir -p "$D/shared"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

# emit <command> <session-id-or-empty> [hook-path] — drive the hook, echo the audit line it wrote.
emit() {
  local cmd="$1" sid="$2" hook="${3:-$HOOK}"
  rm -rf "$HOME/.claude/logs"
  if [ -n "$sid" ]; then
    jq -nc --arg c "$cmd" --arg s "$sid" '{tool_name:"Bash",tool_input:{command:$c},session_id:$s}' \
      | bash "$hook" >/dev/null 2>&1 || true
  else
    jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}' \
      | bash "$hook" >/dev/null 2>&1 || true
  fi
  head -1 "$HOME/.claude/logs/bash-commands.log" 2>/dev/null
}

SHAPE='^\[[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\] \[[^]]+\] '

@test "(1) the audit line keeps its shape: [ISO8601Z] [sid] command" {
  line=$(emit "echo r15-shape-probe" "sid-12345")
  [[ "$line" =~ $SHAPE ]]
}

@test "(2) the session id from the payload lands in the line" {
  line=$(emit "echo r15-sid-probe" "sid-12345")
  [[ "$line" == *"[sid-12345]"* ]]
}

@test "(3) a payload with NO session_id still renders the '-' placeholder, not an empty field" {
  line=$(emit "echo r15-nosid-probe" "")
  [[ "$line" =~ $SHAPE ]]
  [[ "$line" == *"[-]"* ]]
}

@test "(4) the command body is carried verbatim" {
  line=$(emit "echo r15-verbatim-probe --flag=x" "sid-9")
  [[ "$line" == *"echo r15-verbatim-probe --flag=x" ]]
}

@test "(5) the timestamp is the CURRENT UTC minute, not a fixed or stale value" {
  now=$(date -u '+%Y-%m-%dT%H:%M')
  line=$(emit "echo r15-clock-probe" "sid-9")
  [[ "$line" == *"$now"* ]]
}

@test "(6) the log directory is created when it does not exist" {
  rm -rf "$HOME/.claude/logs"
  line=$(emit "echo r15-mkdir-probe" "sid-9")
  [ -d "$HOME/.claude/logs" ]
  [[ "$line" =~ $SHAPE ]]
}

@test "(7) CONTROL — a mutant whose stamp is frozen writes a line the real hook would not" {
  # Anchor-checked: if the collapsed jq is ever rewritten, this substitution stops matching and the
  # test fails loudly rather than silently mutating nothing (a mutant that changes no byte is a
  # vacuous control). The mutation is a FROZEN stamp rather than a deleted one, because deleting it
  # is caught by the fallback below — see (8), which is what the first draft of this control
  # accidentally measured.
  MUT="$D/mutant-frozen.sh"
  anchor='(now|todateiso8601)'
  grep -qF -- "$anchor" "$HOOK"
  sed 's/(now|todateiso8601)/("1999-01-01T00:00:00Z")/' "$HOOK" > "$MUT"
  chmod +x "$MUT"
  now=$(date -u '+%Y-%m-%dT%H:%M')
  good=$(emit "echo r15-mutant-probe" "sid-9")
  mline=$(emit "echo r15-mutant-probe" "sid-9" "$MUT")
  [[ "$good" =~ $SHAPE ]]
  [[ "$good" == *"$now"* ]]
  [[ "$mline" == *"1999-01-01T00:00:00Z"* ]]
  # Negations LAST: bats errexit skips a failing negation placed mid-test, which makes it dead code
  # (MEMORY.md bats dead-assertion ratchet). `! cmd` is the form that carries its own exit status;
  # `cmd && false` does NOT — when cmd is false the list short-circuits and yields cmd's own rc 1,
  # so it fails on exactly the runs it is supposed to pass. Measured here, this run.
  ! grep -qF -- "$anchor" "$MUT"
  ! [[ "$mline" == *"$now"* ]]
}

@test "(8) the jq-failure FALLBACK produces the same shape and a live stamp" {
  # Proven by mutating the collapsed jq to emit ONE field, so the tab test fails exactly as it does
  # when jq is absent or the payload is unreadable. This path forks `date` — that is the point: the
  # saving is taken on the modal path and paid back only where the fast path could not answer.
  MUT="$D/mutant-nofield.sh"
  anchor='(now|todateiso8601)'
  grep -qF -- "$anchor" "$HOOK"
  sed 's/(now|todateiso8601)/(empty)/' "$HOOK" > "$MUT"
  chmod +x "$MUT"
  now=$(date -u '+%Y-%m-%dT%H:%M')
  mline=$(emit "echo r15-fallback-probe" "sid-9" "$MUT")
  [[ "$mline" =~ $SHAPE ]]
  [[ "$mline" == *"$now"* ]]
  [[ "$mline" == *"[-]"* ]]
}
