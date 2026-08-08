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
  # No cc-cloud by default: the off-box abstain seam is OFF for every pre-existing test, so the
  # local verdicts below are measured against the same subject they always were. Set-to-EMPTY is
  # honored verbatim by the subject; the off-box tests re-enable it explicitly.
  export CC_CLOUD_BIN=""
}

# Turn the off-box abstain seam ON, pointed at this repo's real cc-cloud over a tmpdir state root.
# The real binary, not a stub — the join key between these two tools is the whole subject of the
# CLOUD_OBSERVABILITY.md §5.2 wiring, and a stub would let a mismatch pass vacuously.
use_cc_cloud() {
  export CC_CLOUD_BIN="$REPO/bin/cc-cloud"
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/cloud"
  mkdir -p "$CC_CLOUD_STATE"
}
declare_cloud() { printf 'id=%s\nbranch=b\n' "$1" > "$CC_CLOUD_STATE/$1.decl"; }

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

# ── CLOUD_OBSERVABILITY.md §5.2, liar #1 — the local process table must ABSTAIN off-box ──────────
# The defect: a cloud session shares no process table with this box, so `agent_pid` returns empty
# BY CONSTRUCTION and this file printed "✗ ABSENT … Died, or never launched." for a healthy
# session. Each test below is RED against the pre-wiring subject.

@test "OFFBOX (3) — a DECLARED cloud id abstains instead of convicting" {
  use_cc_cloud
  declare_cloud session_01LIVE
  fake_ps "  501 /bin/zsh -l"                     # nothing local, exactly as it will always be
  run "$V" session_01LIVE --timeout 0
  [ "$status" -eq 3 ] || false
  echo "$output" | grep -q 'OFFBOX' || false
  # The load-bearing half: it must not utter the death verdict at all.
  ! echo "$output" | grep -q 'ABSENT' || false
  ! echo "$output" | grep -q 'Died, or never launched' || false
  true
}

@test "--cloud <id> binds a LOCAL name to a cloud id" {
  use_cc_cloud
  declare_cloud session_01BOUND
  fake_ps "  501 /bin/zsh -l"
  run "$V" worker --cloud session_01BOUND --timeout 0
  [ "$status" -eq 3 ] || false
  echo "$output" | grep -q 'session_01BOUND' || false
}

# THE CONTROL. Without it the test above would pass for an implementation that abstains on
# EVERYTHING — an abstain that cannot convict is as useless as a verdict that cannot abstain.
@test "an UNDECLARED id still gets the ordinary local verdict (the abstain is not blanket)" {
  use_cc_cloud
  fake_ps "  501 /bin/zsh -l"
  run "$V" session_01NEVERDECLARED --timeout 0
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'ABSENT' || false
}

@test "a RETIRED cloud id stops abstaining — retire is terminal" {
  use_cc_cloud
  declare_cloud session_01GONE
  printf 'retired_at=1\n' > "$CC_CLOUD_STATE/session_01GONE.retired"
  fake_ps "  501 /bin/zsh -l"
  run "$V" session_01GONE --timeout 0
  [ "$status" -eq 1 ] || false
}

@test "OFFBOX outranks every local verdict in the --all fold (a wave with one is NOT green)" {
  use_cc_cloud
  declare_cloud session_01CLOUD
  fake_ps "  501 /Users/x/claude.exe --agent-id a@s --agent-name alpha --model m"
  run "$V" --all alpha session_01CLOUD --timeout 0
  [ "$status" -eq 3 ] || false
  echo "$output" | grep -q 'RUNNING  alpha' || false
}

@test "the abstain costs no wall clock — it is checked BEFORE the wait loop" {
  use_cc_cloud
  declare_cloud session_01FAST
  fake_ps "  501 /bin/zsh -l"
  start=$(date +%s)
  run "$V" session_01FAST --timeout 6 --quiet
  elapsed=$(( $(date +%s) - start ))
  [ "$status" -eq 3 ] || false
  # Waiting the full timeout for a process that can NEVER appear is spending the clock to reach a
  # wrong answer. 3s is a generous ceiling on "did not wait 6".
  [ "$elapsed" -le 3 ] || false
}
