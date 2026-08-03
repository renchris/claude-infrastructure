#!/usr/bin/env bats
# OPERATOR-SURFACE SCOPE — "no operator entrypoint ⇒ no operator-facing surface" (2026-08-02).
#
# THE DEFECT. A background team assignee is a REAL child session (argv
# `claude.exe --agent-id <n>@session-<t> --agent-name <n> --team-name <t> --parent-session-id <p>`),
# so it runs the whole main-session Stop chain. Observed: a teammate pane rendered
# `OPERATOR ▸ ✅ SAFE TO CLOSE … 12 runnable now, 253 need your call` into its OWN transcript. It has
# no human entrypoint at all — its only channel is two-way with its lead — so that block is
# undeliverable, burns the one resource the brief discipline protects, and invites it to act on
# operator-owned items that are not its work.
#
# WHAT IS ASSERTED, AND WHY IT IS SHAPED THIS WAY. The fix must not decay into "subagent ⇒ hooks
# off" (MEMORY.md subagent-stop-has-two-shapes: agent-ness may VALIDATE evidence, never EXCUSE a
# session). So every suppression test is paired with a LEAD CONTROL over identical state — without
# the control, "suppressed" is indistinguishable from "hook broken":
#   S1  each operator-facing hook goes silent for an assignee
#   S2  … and STILL FIRES for a lead on the same input   ← the control that can fail
#   S3  the contract hooks (completion-assert / session-continue) are NOT suppressed — a teammate is
#       still held to its own work
#   S4  fail-open: no lib / refuted-by-team-config / prose-only argv ⇒ the surface renders as today
#   S5  the shape gate: an argv match that yields a garbage id is prose, not a verdict

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/hooks/lib/agent-identity.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  CCBIN="/x/claude-code/bin/claude.exe"
}

# ── ancestry fixtures ────────────────────────────────────────────────────────────────────────────
# Rows are "pid ppid command…", walked from CC_WF_START_PID. Shapes taken VERBATIM from live argv
# captured 2026-08-02 on CC 2.1.220 (both a subagent_type-bearing spawn and a bare `name:` spawn —
# the runtime assigns `--team-name session-<sid>` for both, and the bare one carries NO --agent-type,
# which is why the Stop PAYLOAD cannot be the discriminator).
pstable() {
  local p="$BATS_TEST_TMPDIR/pstable"; : > "$p"
  local r; for r in "$@"; do printf '%s\n' "$r" >> "$p"; done
  export CC_WF_PSTABLE_FILE="$p" CC_WF_START_PID=1000
}
assignee_ancestry() { pstable \
  "1000 1001 bash /x/hook.sh" \
  "1001 1002 /bin/zsh -c source /snap.zsh" \
  "1002 1003 $CCBIN --agent-id ${1:-tm}@session-${2:-t1} --agent-name ${1:-tm} --team-name session-${2:-t1} --parent-session-id p1 --permission-mode auto" \
  "1003 1 -zsh"; }
lead_ancestry() { pstable \
  "1000 1001 bash /x/hook.sh" \
  "1001 1002 /bin/zsh -c source /snap.zsh" \
  "1002 1003 $CCBIN --permission-mode auto --model claude-opus-5 --effort high" \
  "1003 1 -zsh"; }
# A LEAD whose BRIEF quotes the three flags — the false positive that is concrete in this repo (this
# very investigation's own Bash call carried all three and made a lead read as its own assignee).
prose_lead_ancestry() { pstable \
  "1000 1001 bash /x/hook.sh" \
  "1001 1002 /bin/zsh -c source /snap.zsh" \
  "1002 1003 $CCBIN --model claude-opus-5 Investigate: a teammate argv carries --agent-id x@session-y --agent-name x --team-name y and we must scope it" \
  "1003 1 -zsh"; }
team_cfg() { # $1=team-suffix  $2=member name (omit ⇒ team exists but REFUTES)
  local d="$BATS_TEST_TMPDIR/teamroot/session-${1}"; mkdir -p "$d"
  if [ -n "${2:-}" ]; then
    jq -n --arg n "$2" '{name:"t",members:[
      {name:"team-lead",agentType:"team-lead",tmuxPaneId:"leader"},
      {name:$n,agentType:"general-purpose",tmuxPaneId:"268"}]}' > "$d/config.json"
  else
    jq -n '{name:"t",members:[{name:"team-lead",agentType:"team-lead",tmuxPaneId:"leader"}]}' > "$d/config.json"
  fi
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teamroot"
}

# ── the lib's own verdict ────────────────────────────────────────────────────────────────────────
@test "lib: a confirmed assignee has NO operator entrypoint" {
  assignee_ancestry tm t1; team_cfg t1 tm
  run bash -c '. "$0"; agent_is_assignee' "$LIB"
  [ "$status" -eq 0 ]; [ "$output" = "tm@session-t1" ]
  run bash -c '. "$0"; agent_has_operator_entrypoint' "$LIB"
  [ "$status" -eq 1 ]
}

@test "lib CONTROL: a lead HAS an operator entrypoint" {
  lead_ancestry; team_cfg t1 tm
  run bash -c '. "$0"; agent_is_assignee' "$LIB"
  [ "$status" -eq 1 ]
  run bash -c '. "$0"; agent_has_operator_entrypoint' "$LIB"
  [ "$status" -eq 0 ]
}

@test "S5 a lead whose BRIEF quotes the three flags is prose, not an assignee" {
  # The three flags CO-OCCUR here (ps -o command= flattens argv, so the brief's words look like
  # flags) — this is the false positive measured live on 2026-08-02. What refutes it is the
  # harness's internal consistency: the brief says --team-name y while its --agent-id claims team
  # session-y, and CC never emits a record that disagrees with itself.
  prose_lead_ancestry
  run bash -c '. "$0"; agent_assignee_argv' "$LIB"
  [ "$status" -ne 0 ]
  run bash -c '. "$0"; agent_has_operator_entrypoint' "$LIB"
  [ "$status" -eq 0 ]
}

@test "S5 the consistency check is not vacuous: a SELF-CONSISTENT record still identifies" {
  # Positive control for the test above — without this, S5 would also pass if the conjunction were
  # simply broken. Same fixture shape, but the fields agree the way the real harness emits them.
  pstable \
    "1000 1001 bash /x/hook.sh" \
    "1002 1003 $CCBIN --agent-id x@session-y --agent-name x --team-name session-y" \
    "1001 1002 /bin/zsh -c source /snap.zsh" \
    "1003 1 -zsh"
  run bash -c '. "$0"; agent_assignee_argv' "$LIB"
  [ "$status" -eq 0 ]; [ "$output" = "x@session-y" ]
}

@test "S4 fail-open: the team config REFUTES the argv ⇒ operator entrypoint stands" {
  assignee_ancestry ghost t1; team_cfg t1        # team exists, has no such member
  run bash -c '. "$0"; agent_has_operator_entrypoint' "$LIB"
  [ "$status" -eq 0 ]
}

@test "S4 fail-open: no readable team config ⇒ argv evidence alone still suppresses" {
  assignee_ancestry tm t9; export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/nowhere"
  run bash -c '. "$0"; agent_has_operator_entrypoint' "$LIB"
  [ "$status" -eq 1 ]
}

@test "S4 fail-open: no ancestry at all ⇒ operator entrypoint stands" {
  pstable "1000 1 bash /x/hook.sh"
  run bash -c '. "$0"; agent_has_operator_entrypoint' "$LIB"
  [ "$status" -eq 0 ]
}

# ── operator-readout: the hook that was observed leaking ─────────────────────────────────────────
readout_env() {
  export CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state-$BATS_TEST_NUMBER"
  export CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/act"; mkdir -p "$CC_ACTIVATION_DIR"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/dec"; mkdir -p "$CC_DECISIONS_DIR"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"; : > "$CC_BACKLOG_FILE"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh" WRAP_TRUNK="origin/main"
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such"
  export CC_OPREADOUT_NOW=1000000 CC_OPREADOUT_TTL_S=900
  # A 📦 tree (committed, unlanded) — the state that ALWAYS renders, so a silent result can only be
  # the guard and never an empty-block coincidence.
  local o="$BATS_TEST_TMPDIR/o-$BATS_TEST_NUMBER.git" w="$BATS_TEST_TMPDIR/w-$BATS_TEST_NUMBER"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w"; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main
    echo x > x.txt; git add x.txt; git commit -q -m "unlanded" ) >/dev/null 2>&1
  RWD="$w"
}
readout_run() { printf '{"session_id":"s1","cwd":"%s"}' "$RWD" | "$REPO/hooks/operator-readout.sh"; }

@test "S2 CONTROL: operator-readout RENDERS the block for a lead on a parked tree" {
  readout_env; lead_ancestry; team_cfg t1 tm
  run readout_run
  [ "$status" -eq 0 ]
  [[ "$output" == *"systemMessage"* ]]
  [[ "$output" == *"OPERATOR"* ]]
}

@test "S1 operator-readout is SILENT for an assignee on the same parked tree" {
  readout_env; assignee_ancestry tm t1; team_cfg t1 tm
  run readout_run
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q '"reason":"team-assignee:tm@session-t1"' "$CC_IDL"
}

@test "S1 operator-readout: the --render PULL surface is NOT guarded (the operator invoked it)" {
  readout_env; assignee_ancestry tm t1; team_cfg t1 tm
  run "$REPO/hooks/operator-readout.sh" --render --cwd "$RWD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPERATOR"* ]]
}

# ── the remaining operator-facing hooks: each silent for an assignee, each firing for a lead ─────
@test "S1/S2 boundary-handoff: silent for an assignee, abstain recorded" {
  export CC_BOUNDARY_IDL="$CC_IDL"
  assignee_ancestry tm t1; team_cfg t1 tm
  run bash -c 'printf "{\"session_id\":\"s1\",\"cwd\":\"/tmp\"}" | "$0"' "$REPO/hooks/boundary-handoff.sh"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q 'team-assignee' "$CC_IDL"
}

@test "S1 anti-deference-nudge: does NOT block a teammate for the protocol it is REQUIRED to follow" {
  export ANTIDEF_STATE_DIR="$BATS_TEST_TMPDIR/ad" ANTIDEF_IDL="$CC_IDL"
  local tp="$BATS_TEST_TMPDIR/t.jsonl"
  # "awaiting your go-ahead" is a TELLS match verbatim AND is what skills/agent-teams mandates.
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Phase A landed — awaiting your go-ahead."}]}}' > "$tp"
  assignee_ancestry tm t1; team_cfg t1 tm
  run bash -c 'printf "{\"session_id\":\"s1\",\"transcript_path\":\"%s\",\"cwd\":\"/tmp\"}" "$1" | "$0"' \
    "$REPO/hooks/anti-deference-nudge.sh" "$tp"
  [ "$status" -eq 0 ]
  [[ "$output" != *'"decision":"block"'* ]]
}

@test "S2 CONTROL: anti-deference-nudge STILL blocks a LEAD on the identical message" {
  export ANTIDEF_STATE_DIR="$BATS_TEST_TMPDIR/ad2" ANTIDEF_IDL="$CC_IDL"
  local tp="$BATS_TEST_TMPDIR/t2.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Phase A landed — awaiting your go-ahead."}]}}' > "$tp"
  lead_ancestry; team_cfg t1 tm
  run bash -c 'printf "{\"session_id\":\"s2\",\"transcript_path\":\"%s\",\"cwd\":\"/tmp\"}" "$1" | "$0"' \
    "$REPO/hooks/anti-deference-nudge.sh" "$tp"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
}

@test "S1 handoff-intent-nudge: no pane-succession spec for an assignee" {
  assignee_ancestry tm t1; team_cfg t1 tm
  run bash -c 'printf "{\"prompt\":\"please hand off when done\"}" | "$0"' "$REPO/hooks/handoff-intent-nudge.sh"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "S2 CONTROL: handoff-intent-nudge still injects the spec for a lead" {
  lead_ancestry; team_cfg t1 tm
  run bash -c 'printf "{\"prompt\":\"please hand off when done\"}" | "$0"' "$REPO/hooks/handoff-intent-nudge.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"HANDOFF-INTENT PARITY"* ]]
}

@test "S1 notify: no chime for an assignee's turn-complete" {
  assignee_ancestry tm t1; team_cfg t1 tm
  export CC_NOTIFY_SILENT=1
  run bash -c '"$0" complete </dev/null' "$REPO/hooks/notify.sh"
  [ "$status" -eq 0 ]
}

@test "S1 notify: a PERMISSION page is NOT suppressed — the operator must still answer it" {
  assignee_ancestry tm t1; team_cfg t1 tm
  # Scope check only: `complete` takes the guarded branch, `permission` must not even consult it.
  run grep -c 'EVENT_TYPE" = "complete"' "$REPO/hooks/notify.sh"
  [ "$output" = "1" ]
}

# ── S3: the CONTRACT hooks stay armed — a teammate is still held to its own work ─────────────────
@test "S3 completion-assert is NOT suppressed: an assignee that DID write is still convicted" {
  # Delegating _ca_assignee to the lib must not turn it into an exemption. The R3 arm of
  # tests/subagent-stop-r1.bats owns the full proof; this asserts the wiring did not silently
  # convert a transcript-validator into a session-excuser.
  run bash -c 'grep -c "agent_is_assignee" "$0"' "$REPO/hooks/completion-assert.sh"
  [ "$status" -eq 0 ]; [ "$output" -ge 1 ]
  # It must ask "is this session's write-free-ness trustworthy?", NEVER "does it have an operator?"
  # — the latter would make agent-ness an excuse instead of a transcript validator.
  run bash -c 'grep -c "agent_has_operator_entrypoint" "$0" || true' "$REPO/hooks/completion-assert.sh"
  [ "$output" = "0" ]
}

@test "S3 session-continue keeps its mechanical 🔧 arm for assignees" {
  run bash -c 'grep -c "agent_has_operator_entrypoint" "$0" || true' "$REPO/hooks/session-continue.sh"
  [ "$output" = "0" ]
}

# ── chokepoint lint: a NEW operator-facing hook cannot silently skip the guard ────────────────────
# MEMORY.md enforcement-must-live-at-the-chokepoint: a rule that lives only in a review comment is
# detection, not a gate. Every hook that renders an operator-addressed surface must consult the ONE
# oracle; this fails the moment one is added or a guard is deleted.
@test "LINT: every operator-facing hook consults the agent-identity oracle" {
  local h missing=""
  for h in operator-readout boundary-handoff anti-deference-nudge dispatch-assert \
           waiting-recycle notify handoff-intent-nudge; do
    grep -q 'agent_is_assignee' "$REPO/hooks/$h.sh" || missing="$missing $h"
  done
  [ -z "$missing" ] || { echo "unguarded operator-facing hooks:$missing"; false; }
}

@test "LINT: the discriminator exists in exactly ONE place" {
  # The three-flag argv conjunction must not be re-implemented in any hook (the six-copies-of-a-
  # regex failure the fix exists to avoid).
  # Match the awk CONJUNCTION itself, not the mere string "--agent-name": hooks legitimately name
  # the flags in explanatory comments, and a lint that convicted a comment would be pressure to
  # delete the explanation rather than the duplication.
  local hits
  hits="$(grep -rlE '~ /[[:space:]]*--agent-name[[:space:]]*/' "$REPO/hooks" 2>/dev/null \
          | grep -v '/lib/agent-identity\.sh$' || true)"
  [ -z "$hits" ] || { echo "discriminator re-implemented in: $hits"; false; }
}
