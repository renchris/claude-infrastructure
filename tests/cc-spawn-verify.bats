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
  # No kitty ⇒ both pane oracles fail OPEN ⇒ absence reports ABSENT(1) never PARKED(2), and presence
  # reports RUNNING(0) never WEDGED(4).
  #
  # ⚠ CC_KITTY_BIN, not PATH. This line used to be `CC_TERM_KITTY_TO=""` alone, with a comment
  # claiming "no kitty on PATH" — but PREPENDING $D to PATH does not REMOVE the operator's real
  # /opt/homebrew/bin/kitten further down it, and CC_TERM_KITTY_TO="" falls through `:-` to an
  # inherited KITTY_LISTEN_ON. This suite was therefore querying the operator's live 20-pane fleet
  # and passing by luck (no live pane happened to quote `--agent-name worker`). The subject's
  # `+set` seam is honored set-to-EMPTY, so this genuinely turns the lookup off (memory:
  # unfixtured-sensor-executes-the-deployed-subject).
  export CC_KITTY_BIN=""
  export CC_TERM_KITTY_TO=""
  unset KITTY_LISTEN_ON
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

# ================================================================================================
# 4 WEDGED — the process EXISTS and is inert on a modal (plan §9.5, backlog 75c2e3e2bde7)
#
# THE STATE THIS SUITE COULD NOT PREVIOUSLY EXPRESS. Every test above models an agent that is NOT
# in the process table. §9.2's failure is the inverse: `claude.exe` is running, `ps` is healthy,
# `agent_pid` finds it — and the session is stopped on a startup dialog doing no work. This file
# reported that as `✓ RUNNING`, which is the one verdict that costs an agent rather than a glance.
# ================================================================================================

# A kitty that answers exactly two RPCs from files, and logs what it was asked, so a test can assert
# WHICH pane was read rather than only what came back.
#   $1 = file holding the `@ ls` JSON      $2 = file holding the `get-text` screen
fake_kitty() {
  KLOG="$BATS_TEST_TMPDIR/kitty.log"; : > "$KLOG"
  cat > "$D/kitten" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$KLOG"
for a in "\$@"; do
  case "\$a" in
    ls)       cat "$1"; exit 0 ;;
    get-text) cat "$2"; exit 0 ;;
  esac
done
exit 0
SH
  chmod +x "$D/kitten"
  export CC_KITTY_BIN="$D/kitten"
}

# One window hosting a genuine agent process for $1, as `kitty @ ls` renders it.
agent_window_json() { # $1=agent-name $2=window-id
  cat > "$BATS_TEST_TMPDIR/ls.json" <<JSON
[{"tabs":[{"windows":[{"id":$2,"in_alternate_screen":true,"at_prompt":false,
  "foreground_processes":[{"cmdline":["/Users/x/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe","--agent-id","w@s","--agent-name","$1"]}]}]}]}]
JSON
  printf '%s' "$BATS_TEST_TMPDIR/ls.json"
}

mcp_modal_screen() {
  cat > "$BATS_TEST_TMPDIR/screen" <<'EOF'
│ New MCP server found in this project: ms365                  │
│ 1. Use this MCP server                                       │
│ 3. Continue without using this MCP server                    │
EOF
  printf '%s' "$BATS_TEST_TMPDIR/screen"
}

working_screen() {
  cat > "$BATS_TEST_TMPDIR/screen" <<'EOF'
⏺ Clauding… (2m 11s · 18.4k tokens)
  ? for shortcuts
EOF
  printf '%s' "$BATS_TEST_TMPDIR/screen"
}

live_agent_ps() { fake_ps "  501 /Users/x/.claude-220/node_modules/@anthropic-ai/claude-code/bin/claude.exe --agent-id w@s --agent-name worker --model claude-opus-5"; }

@test "WEDGED (4) — a live agent parked on the MCP-approval dialog is NOT reported RUNNING" {
  live_agent_ps
  fake_kitty "$(agent_window_json worker 312)" "$(mcp_modal_screen)"
  run "$V" worker --timeout 0
  [ "$status" -eq 4 ] || false
  echo "$output" | grep -q 'WEDGED' || false
  echo "$output" | grep -q 'mcp-trust-modal' || false
  echo "$output" | grep -q 'pane id=312' || false
  # The remedy is part of the verdict — a diagnosis with no next action is a report nobody can act on.
  echo "$output" | grep -q 'enabledMcpjsonServers' || false
  # `! A || false`, never `A && false` — the latter is and-absorbed under errexit, so it asserts
  # nothing (scripts/bats-assert-liveness-fix.py names the class and rewrites it).
  ! echo "$output" | grep -q 'RUNNING' || false
}

@test "a live agent that is WORKING stays RUNNING (0) — the oracle is not 'a TUI is up'" {
  live_agent_ps
  fake_kitty "$(agent_window_json worker 312)" "$(working_screen)"
  run "$V" worker --timeout 0
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'RUNNING' || false
}

@test "REGRESSION: the pane join is by ARGV POSITION — a window merely QUOTING the flags is not it" {
  # The same defect the process oracle above already paid for, arriving through the pane door: a
  # shell whose command line carries the launch text is not the agent. If this join were a substring
  # test, that window's screen would be read and any modal-shaped text on it would convict the agent.
  live_agent_ps
  cat > "$BATS_TEST_TMPDIR/ls.json" <<'JSON'
[{"tabs":[{"windows":[{"id":999,"in_alternate_screen":false,"at_prompt":true,
  "foreground_processes":[{"cmdline":["/bin/zsh","-lc","claude --agent-id w@s --agent-name worker"]}]}]}]}]
JSON
  fake_kitty "$BATS_TEST_TMPDIR/ls.json" "$(mcp_modal_screen)"
  run "$V" worker --timeout 0
  [ "$status" -eq 0 ] || false
  # …and it never even read that pane. Absence of the read is the strong form of the assertion.
  ! grep -q 'get-text' "$KLOG" || false
}

@test "a DIFFERENT agent's wedged pane does not convict the one we asked about" {
  live_agent_ps
  fake_kitty "$(agent_window_json somebody-else 312)" "$(mcp_modal_screen)"
  run "$V" worker --timeout 0
  [ "$status" -eq 0 ] || false
}

@test "FAIL-OPEN: no kitty ⇒ RUNNING, never WEDGED (a blind oracle cannot convict)" {
  live_agent_ps
  export CC_KITTY_BIN=""
  run "$V" worker --timeout 0
  [ "$status" -eq 0 ] || false
}

@test "FAIL-OPEN: the modal lib is ABSENT ⇒ RUNNING, exactly the pre-4 behaviour" {
  # The deploy-lag branch: bin/ is a per-file symlink into the checkout, so this file can be live
  # before install.sh next re-globs hooks/lib into ~/.claude. A missing side-car must degrade, and
  # must not abort the script under `set -e`.
  live_agent_ps
  fake_kitty "$(agent_window_json worker 312)" "$(mcp_modal_screen)"
  export CC_PANE_MODAL_LIB=""
  run "$V" worker --timeout 0
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'RUNNING' || false
}

@test "FAIL-OPEN: an unreadable pane screen ⇒ RUNNING" {
  live_agent_ps
  : > "$BATS_TEST_TMPDIR/screen"
  fake_kitty "$(agent_window_json worker 312)" "$BATS_TEST_TMPDIR/screen"
  run "$V" worker --timeout 0
  [ "$status" -eq 0 ] || false
}

@test "the fold RANK, not max(rc): OFFBOX still outranks WEDGED" {
  # The property the old `max(rc)` fold got right only by arithmetic luck, and which 4 breaks:
  # WEDGED is a verdict, OFFBOX is a NON-VERDICT, and a wave carrying a question this box could not
  # ask must not report as one whose members were all answered.
  use_cc_cloud
  declare_cloud session_01CLOUD
  live_agent_ps
  fake_kitty "$(agent_window_json worker 312)" "$(mcp_modal_screen)"
  run "$V" --all worker session_01CLOUD --timeout 0
  [ "$status" -eq 3 ] || false
  echo "$output" | grep -q 'WEDGED' || false
  echo "$output" | grep -q 'OFFBOX' || false
}

@test "the fold RANK: WEDGED outranks PARKED and ABSENT in a mixed wave" {
  live_agent_ps
  fake_kitty "$(agent_window_json worker 312)" "$(mcp_modal_screen)"
  run "$V" --all ghost worker --timeout 0
  [ "$status" -eq 4 ] || false
  echo "$output" | grep -q 'ABSENT   ghost' || false
}
