#!/usr/bin/env bats
# agent-teams-enforce.sh — RC-1 spawn advisory: `name:` on a RESEARCH subagent_type.
#
# WHAT IS UNDER TEST. On this runtime `name:` is the lifecycle switch: a named Agent call becomes a
# real child CLI session in a pane that never exits on its own (no idle timeout exists anywhere in
# the binary; only a structured `shutdown_response` terminates it), while an unnamed one runs
# in-process, returns through a task notification and reaps itself. Measured over 30 d: 904 Agent
# spawns, 419 named, 71% of named briefs research/read-only, and 0 of 338 named members ever
# received a non-shutdown message — the persistence naming buys was used zero times.
#
# WHAT IS DELIBERATELY NOT UNDER TEST. This is an ADVISORY and must never become a deny/ask on any
# path: the legitimate named case is a member the lead will message or re-task, and an advisory
# cannot wrap it where a deny would. Case (d) pins exactly that.
#
# A PreToolUse hook signals its decision in JSON, never in $status — every path exits 0, so every
# assertion below reads the emitted JSON.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/agent-teams-enforce.sh"

  # HERMETICITY (scripts/test-hermeticity-lint.sh RULE 1) — this hook appends to the operator's
  # live decision ledger and charges a per-session spawn budget under $HOME. Fixture both.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/autonomy"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_WCLAIM_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_SPAWN_STATE_DIR="$BATS_TEST_TMPDIR/spawn-budget"

  # DETERMINISM. Four admission terms above the policy under test read the REAL box (free memory,
  # loadavg, a live backlog lease, a pane-lineage env stamp). Left on, any of them could deny and
  # the case would pass or fail for a reason that has nothing to do with the advisory. Each has its
  # own suite; this one pins the POLICY.
  export CC_ADMIT_GATE=off
  export CC_WCLAIM_GATE=off
  export CC_SPAWN_GATE=off
  export CC_LINEAGE_GATE=off

  MARKER='NAMED RESEARCH AGENT'
}

# $1=subagent_type  $2=name (empty for an unnamed spawn)  [$3=hook path]
spawn() {
  jq -n --arg t "$1" --arg n "$2" \
     '{tool_input:({subagent_type:$t,prompt:"Read the three files and report what you find."}
                   + (if $n == "" then {} else {name:$n} end))}' \
    | bash "${3:-$HOOK}"
}

# ── (a) RED-PROOF ────────────────────────────────────────────────────────────────────────────
# The only case that fails at the pinned pre-fix sha. Everything else in this file is an
# equivalence guard whose power is proven by a named mutant below.

@test "(a) RED-PROOF: deep-research WITH name emits the lifecycle advisory" {
  run spawn deep-research researcher-1
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF "$MARKER"
}

@test "(a) the other three research types WITH name emit it too" {
  for t in deep-research-sonnet Explore frontier-derivation; do
    run spawn "$t" "worker-$t"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qF "$MARKER"
  done
}

@test "(a) the advisory names the unnamed alternative, not just the hazard" {
  run spawn deep-research researcher-1
  echo "$output" | grep -qF 'UNNAMED'
  echo "$output" | grep -qF 'shutdown_request'
}

# ── (b) EQUIVALENCE GUARD — passes on BOTH arms ──────────────────────────────────────────────
# Its power is proven by mutant M-b (advisory keyed on subagent_type alone, ignoring `name:`),
# which it kills in the test below.

@test "(b) EQUIVALENCE GUARD: deep-research WITHOUT name is silent" {
  run spawn deep-research ""
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF "$MARKER"
}

@test "(b) mutant M-b (keyed on type, ignoring name) is killed by that guard" {
  m="$BATS_TEST_TMPDIR/mutant-b.sh"
  # M-b: emit the advisory for any research type, whether or not `name:` is set — the plausible
  # mis-implementation that reads the rule as being about research agents rather than about naming.
  awk '1; /^SUBAGENT_TYPE=/ {
        print "case \"$SUBAGENT_TYPE\" in deep-research|deep-research-sonnet|Explore|frontier-derivation)";
        print "  printf %s \"{\\\"hookSpecificOutput\\\":{\\\"hookEventName\\\":\\\"PreToolUse\\\",\\\"permissionDecision\\\":\\\"allow\\\",\\\"additionalContext\\\":\\\"NAMED RESEARCH AGENT\\\"}}\"; exit 0 ;;";
        print "esac" }' "$HOOK" > "$m"
  run spawn deep-research "" "$m"
  echo "$output" | grep -qF "$MARKER"   # the mutant DOES emit ⇒ guard (b) would fail ⇒ it has power
}

# ── (c) EQUIVALENCE GUARD — passes on BOTH arms ──────────────────────────────────────────────
# Power proven by mutant M-c (research type set widened to general-purpose).

@test "(c) EQUIVALENCE GUARD: general-purpose WITH name is silent (no advisory)" {
  run spawn general-purpose builder-1
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF "$MARKER"
}

@test "(c) mutant M-c (type set widened to general-purpose) is killed by that guard" {
  m="$BATS_TEST_TMPDIR/mutant-c.sh"
  sed 's/deep-research|deep-research-sonnet|Explore|frontier-derivation/deep-research|deep-research-sonnet|Explore|frontier-derivation|general-purpose/' "$HOOK" > "$m"
  run spawn general-purpose builder-1 "$m"
  echo "$output" | grep -qF "$MARKER"
}

# ── (d) EQUIVALENCE GUARD — passes on BOTH arms; THE SCOPE CONSTRAINT ────────────────────────
# Power proven by mutant M-d (the advisory's own emission turned into a deny).

@test "(d) EQUIVALENCE GUARD: a named research spawn is never denied or asked" {
  run spawn deep-research researcher-1
  [ "$status" -eq 0 ]
  d=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  [ "$d" != "deny" ]
  [ "$d" != "ask" ]
}

@test "(d) mutant M-d (advisory emitted as a deny) is killed by that guard" {
  m="$BATS_TEST_TMPDIR/mutant-d.sh"
  sed 's/"permissionDecision":"allow"/"permissionDecision":"deny"/' "$HOOK" > "$m"
  run spawn deep-research researcher-1 "$m"
  d=$(echo "$output" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  [ "$d" = "deny" ]
}

# ── NON-REGRESSION of the block this rides in ────────────────────────────────────────────────

@test "the 250-line brief hard cap still denies, advisory or not" {
  big=$(yes "brief content line" | head -n 260)
  run bash -c 'jq -n --arg p "$1" "{tool_input:{name:\"researcher-1\",subagent_type:\"deep-research\",prompt:\$p}}" | bash "$2"' _ "$big" "$HOOK"
  echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}
