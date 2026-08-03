#!/usr/bin/env bats
# cc-spawn-verify — "did the session I just spawned actually START?"
#
# THE DEFECT THIS SUITE EXISTS FOR (2026-08-03). A spawn is fire-and-forget: the Agent tool returns
# "Spawned successfully" when the pane is REQUESTED, not when the agent is running. Two of four
# subagents in one wave died at the shell — one on `zsh: command not found: acd`, one wedged on the
# interactive `correct 'acd' to 'cd' [nyae]?` prompt — and both panes stayed ALIVE and idle, so
# nothing reported anything and the lead waited indefinitely.
#
# THE REGRESSION TEST THAT MATTERS IS `--agent-name is not enough`. The first implementation matched
# the argv PAIR `--agent-name <n>`, reasoning that it was safe where a bare `pgrep -f <n>` is not.
# It was not safe: that pair appears verbatim in every command line that merely QUOTES the launch —
# the spawning shell, a `send-text` carrying the launch text, a grep. Measured: a pane visibly hung
# on `[nyae]` with no agent running reported `RUNNING (pid 54740)`, pid 54740 being the harness that
# quoted the flags. A verifier satisfiable by the SENTENCE DESCRIBING the spawn returns green in
# exactly the case it exists to catch, so this is pinned in BOTH directions.
#
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  V="$REPO/bin/cc-spawn-verify"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Everything below runs against a FAKE ps and NO kitty, so the suite can never read the
  # operator's live fleet — a sibling suite learned that the hard way.
  D="$BATS_TEST_TMPDIR/bin"; mkdir -p "$D"
  export PATH="$D:$PATH"
  # No kitty on PATH ⇒ parked_evidence fails OPEN ⇒ absence reports ABSENT(1), never PARKED(2).
  export CC_TERM_KITTY_TO=""
}

# $1 = the full `ps -Ao pid=,command=` body this test wants the subject to see.
fake_ps() {
  printf '#!/bin/bash\ncat <<'"'"'PSEOF'"'"'\n%s\nPSEOF\n' "$1" > "$D/ps"
  chmod +x "$D/ps"
}

@test "RUNNING (0) when a real claude process carries --agent-name" {
  fake_ps "  501 /Users/x/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id w@s --agent-name worker --model claude-opus-5"
  run "$V" worker --timeout 0
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'RUNNING' || false
  echo "$output" | grep -q '501' || false
}

@test "ABSENT (1) when nothing matches and no pane oracle can explain it" {
  fake_ps "  501 /bin/zsh"
  run "$V" worker --timeout 0
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'ABSENT' || false
}

@test "REGRESSION: --agent-name in argv is NOT enough — argv[0] must BE claude" {
  # The exact false-RUNNING that shipped in the first draft: a harness whose own command line
  # quotes the launch. `kitten`, a shell, a grep — none of these are the agent, and every one of
  # them contains the pair. If this test goes green-by-matching, the verifier is worthless.
  fake_ps "54740 /opt/homebrew/bin/kitten @ send-text --match id:345 -- acd /tmp && claude.exe --agent-id p@x --agent-name worker
54741 /bin/zsh -c cc-spawn-verify --agent-name worker
54742 grep --agent-name worker"
  run "$V" worker --timeout 0
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'ABSENT' || false
  echo "$output" | grep -qv 'RUNNING' || false
}

@test "a DIFFERENT agent's live process does not satisfy the one we asked about" {
  fake_ps "  501 /Users/x/claude.exe --agent-id other@s --agent-name someone-else --model claude-opus-5"
  run "$V" worker --timeout 0
  [ "$status" -eq 1 ] || false
}

@test "--all reports the WORST verdict across a wave, not the last" {
  fake_ps "  501 /Users/x/claude.exe --agent-id a@s --agent-name alpha --model m"
  # alpha RUNNING(0), beta ABSENT(1) ⇒ the wave is not green. A wave is only green when every
  # member started; taking the last verdict would call this 0 whenever the healthy one sorts last.
  run "$V" --all beta alpha --timeout 0
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'RUNNING  alpha' || false
  echo "$output" | grep -q 'ABSENT   beta' || false
}

@test "no agent name is a usage error, not a silent success" {
  run "$V"
  [ "$status" -eq 64 ] || false
}
