#!/usr/bin/env bats
# hooks/frontier-spawn-gate.sh — R2 of docs/plans/NONLIMIT_RESUME_LADDER.md § W3 (conviction 93%).
#
# THE DEFECT THIS SUITE PINS. The gate counted AGENT spawns only. Measured 2026-09-09 over 4,117
# transcripts, the frontier tier's dominant carrier is the SESSION path — 52 Fable lead sessions
# against 140 subagent runs — so `max_fable_spawns_per_session` bounded the minority path and
# nothing at all bounded the majority one, while CLAUDE.md called the agent "bounded" on the
# strength of it. Cases 3-8 below all exit 0 WITHOUT COUNTING against the pre-fix gate (it reads
# `.tool_input.model`, empty on a Bash call) — that is the red proof; cases 1-2 and 12-13 are the
# control arm proving the Agent path is unchanged.
#
# The suite also carries the two false-positive controls (a grep that merely NAMES the tier, a
# `--dry-run` probe) because the failure mode of a substring gate is not a missed count, it is an
# exit 2 over an ordinary read — strictly worse than the hole it closes.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/frontier-spawn-gate.sh"
  # HERMETIC. The subject's own SSOT default is "$HOME/.claude/model-config.yaml", so an
  # unfixtured $HOME would make every case read the operator's live config — and cases 14-16
  # would then be asserting against whatever the real frontier window says today. The three
  # seams below do not resolve under $HOME (an absolute /tmp default, and a BARE NAME the fire
  # path would EXECUTE off the operator's PATH), so fixturing $HOME alone does not reach them;
  # an absent path is the right value, since these sensors fail open on one.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  CFG="$BATS_TEST_TMPDIR/model-config.yaml"
  export FRONTIER_GATE_CFG="$CFG"
  write_cfg true 2099-12-31 6
}

# The SSOT shape the gate parses: exactly-2-space children of frontier_access, plus the budget key.
write_cfg() { # <active> <end> <cap> [reserve_dates]
  cat > "$CFG" <<EOF
versions:
  opus_latest: claude-opus-5
frontier_access:
  model: claude-fable-5-1
  active: $1
  end: "$2"
  fallback: claude-opus-5
frontier_discovery_budget:
  max_fable_spawns_per_session: $3
  reserve_dates: "${4:-}"
EOF
}

bash_call() { # <session id> <command>
  printf '{"tool_name":"Bash","session_id":"%s","tool_input":{"command":%s}}' \
    "$1" "$(printf '%s' "$2" | jq -Rs .)"
}
agent_call() { # <session id> <model>
  printf '{"tool_name":"Agent","session_id":"%s","tool_input":{"model":"%s","prompt":"go"}}' "$1" "$2"
}
count_of() { cat "$TMPDIR/frontier-gate-$1.count" 2>/dev/null || echo 0; }

# ── control arm: the AGENT path is untouched ───────────────────────────────────
@test "1 agent spawn on the frontier tier is allowed and counted" {
  run bash -c "$(declare -f agent_call); agent_call A fable | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of A)" = 1 ]
}

@test "2 agent spawn on the default tier is not counted" {
  run bash -c "$(declare -f agent_call); agent_call B claude-opus-5 | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of B)" = 0 ]
}

# ── the red proof: the SESSION path ────────────────────────────────────────────
@test "3 a handoff-fire on the frontier tier is counted (RED pre-fix: the gate never saw it)" {
  run bash -c "$(declare -f bash_call); bash_call C 'scripts/handoff-fire.sh --recycle --model claude-fable-5-1 --effort xhigh' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of C)" = 1 ]
}

@test "4 the --model fable ALIAS is counted — handoff-fire resolves it from the same SSOT key" {
  run bash -c "$(declare -f bash_call); bash_call D '\$HOME/.claude/scripts/handoff-fire.sh --model fable --prompt-file /tmp/x' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of D)" = 1 ]
}

@test "5 the PRIOR frontier id (claude-fable-5) is counted — prefix, not equality" {
  run bash -c "$(declare -f bash_call); bash_call E 'handoff-fire.sh --model claude-fable-5' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of E)" = 1 ]
}

@test "6 --model=X spelling is counted" {
  run bash -c "$(declare -f bash_call); bash_call F 'handoff-fire.sh --model=claude-fable-5-1' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of F)" = 1 ]
}

@test "7 a bare launcher fired on the frontier tier is counted" {
  run bash -c "$(declare -f bash_call); bash_call G 'claude-next2 --model claude-fable-5-1 -p hello' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of G)" = 1 ]
}

@test "8 the two paths share ONE budget — an agent spawn and a fire both advance the same counter" {
  run bash -c "$(declare -f agent_call bash_call); agent_call H fable | bash '$HOOK'; bash_call H 'handoff-fire.sh --model fable' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of H)" = 2 ]
}

# ── false-positive controls: naming the tier is not spending it ────────────────
@test "9 a grep that merely NAMES the frontier model is untouched and uncounted" {
  run bash -c "$(declare -f bash_call); bash_call I 'grep -n claude-fable-5-1 ~/.claude/model-config.yaml' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of I)" = 0 ]
}

@test "9b a backlog row that QUOTES the fire command is not a fire — the entrypoint guard" {
  run bash -c "$(declare -f bash_call); bash_call I2 'cc-backlog add --why-not-now \"needs-human: re-fire with --model claude-fable-5-1\"' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of I2)" = 0 ]
}

@test "10 --dry-run spawns nothing, so it spends nothing" {
  run bash -c "$(declare -f bash_call); bash_call J 'scripts/handoff-fire.sh --dry-run --model fable' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of J)" = 0 ]
}

@test "11 a fire on the DEFAULT tier is uncounted" {
  run bash -c "$(declare -f bash_call); bash_call K 'handoff-fire.sh --model claude-opus-5 --effort high' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  [ "$(count_of K)" = 0 ]
}

# ── the cap, on both paths ─────────────────────────────────────────────────────
@test "12 at cap the AGENT path refuses with the park instruction" {
  printf '6' > "$TMPDIR/frontier-gate-L.count"
  run bash -c "$(declare -f agent_call); agent_call L fable | bash '$HOOK' 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cap reached (6/6"* ]]
  [[ "$output" == *"FRONTIER_HOLES.md"* ]]
}

@test "13 at cap the SESSION path refuses, and names re-firing on the default tier" {
  printf '6' > "$TMPDIR/frontier-gate-M.count"
  run bash -c "$(declare -f bash_call); bash_call M 'handoff-fire.sh --model fable' | bash '$HOOK' 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cap reached (6/6"* ]]
  [[ "$output" == *"--model claude-opus-5"* ]]
  # It must NOT tell a SESSION fire to "re-spawn this agent" — that names a tool the caller
  # did not use, and the agent then looks for a defect in the wrong place.
  [[ "$output" != *"Re-spawn this agent"* ]]
}

@test "14 a reserve date HALVES the cap on the session path too" {
  write_cfg true 2099-12-31 6 "$(date +%F)"
  printf '3' > "$TMPDIR/frontier-gate-N.count"
  run bash -c "$(declare -f bash_call); bash_call N 'handoff-fire.sh --model fable' | bash '$HOOK' 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"(3/3"* ]]
}

# ── the window ─────────────────────────────────────────────────────────────────
@test "15 a CLOSED window refuses a session fire and names the fallback" {
  write_cfg false 2099-12-31 6
  run bash -c "$(declare -f bash_call); bash_call O 'handoff-fire.sh --model fable' | bash '$HOOK' 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"window is CLOSED"* ]]
  [[ "$output" == *"--model claude-opus-5"* ]]
}

@test "16 an EXPIRED window refuses a session fire" {
  write_cfg true 2020-01-01 6
  run bash -c "$(declare -f bash_call); bash_call P 'handoff-fire.sh --model fable' | bash '$HOOK' 2>&1"
  [ "$status" -eq 2 ]
  [[ "$output" == *"window is CLOSED"* ]]
}

# ── fail-open: the gate must never cost an ordinary tool call ──────────────────
@test "17 a missing SSOT is a silent allow, on both paths" {
  export FRONTIER_GATE_CFG="$BATS_TEST_TMPDIR/absent.yaml"
  run bash -c "$(declare -f bash_call); bash_call Q 'handoff-fire.sh --model fable' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "$(declare -f agent_call); agent_call Q fable | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "18 garbage stdin and an empty Bash command are silent allows" {
  run bash -c "printf 'not json at all' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  run bash -c "printf '{\"tool_name\":\"Bash\",\"session_id\":\"R\",\"tool_input\":{\"command\":\"\"}}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

@test "19 a Bash call with no tool_input at all is a silent allow" {
  run bash -c "printf '{\"tool_name\":\"Bash\",\"session_id\":\"S\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
}

# ── mutants: each kills one load-bearing predicate ─────────────────────────────
# A green suite over an unmutated subject credits no site (memory: per-site-mutation-attributes-
# coverage). One mutant per predicate the session arm rests on.
mutate() { # <sed expr> → path to a mutated copy of the hook
  local m="$BATS_TEST_TMPDIR/mutant.sh"
  sed "$1" "$HOOK" > "$m"; printf '%s' "$m"
}

@test "20 MUTANT — dropping the entrypoint requirement makes a QUOTED command spend a slot" {
  M="$(mutate '/grep -qE/s/|| return 1/|| :/')"
  # the mutant is built by neutering the entry-point guard: assert it CHANGED the file,
  # or the mutant is vacuous and proves nothing.
  ! cmp -s "$M" "$HOOK"
  run bash -c "$(declare -f bash_call); bash_call T 'cc-backlog add --why-not-now \"needs-human: re-fire with --model claude-fable-5-1\"' | bash '$M'"
  [ "$(count_of T)" = 1 ]   # the mutant MIScounts — case 9b is what kills it
}

@test "21 MUTANT — equality instead of prefix stops counting the PRIOR frontier id" {
  M="$(mutate 's|    fable\|claude-fable-5\*) return 0 ;;|    fable) return 0 ;;|')"
  ! cmp -s "$M" "$HOOK"
  run bash -c "$(declare -f bash_call); bash_call U 'handoff-fire.sh --model claude-fable-5' | bash '$M'"
  [ "$(count_of U)" = 0 ]   # silently unbounded — case 5 is what kills it
}

@test "22 MUTANT — treating --dry-run as a real fire spends a slot on a probe" {
  M="$(mutate 's|  case "\$c" in \*--dry-run\*) return 1 ;; esac|  :|')"
  ! cmp -s "$M" "$HOOK"
  run bash -c "$(declare -f bash_call); bash_call V 'handoff-fire.sh --dry-run --model fable' | bash '$M'"
  [ "$(count_of V)" = 1 ]   # case 10 is what kills it
}

@test "23 MUTANT — reading tool_input.model on a Bash call restores the original hole" {
  M="$(mutate 's|^  path=session$|  path=session; exit 0|')"
  ! cmp -s "$M" "$HOOK"
  run bash -c "$(declare -f bash_call); bash_call W 'handoff-fire.sh --model fable' | bash '$M'"
  [ "$status" -eq 0 ]
  [ "$(count_of W)" = 0 ]   # this IS the pre-fix behaviour; cases 3-8 are what kill it
}
