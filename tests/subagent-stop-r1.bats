#!/usr/bin/env bats
# SUBAGENT STOP LOOP (docs/plans/SUBAGENT_STOP_HOOK_LOOP.md) — R1 end-to-end, with its controls.
#
# THE DEFECT. Three read-only research subagents ran to idle and delivered NOTHING (2026-08-02,
# reso `/ground-up` Phase 1); all three had to be killed with TaskStop. Measured cause: a
# background/named subagent is a REAL child session — argv
# `claude.exe --agent-id <n>@session-<t> --agent-name <n> --team-name <t> --parent-session-id <p>` —
# so it runs the whole main-session Stop chain, in the LEAD's worktree, and completion-assert
# convicts it of the LEAD's dirty + unlanded ledger. Read-only brief ⇒ it cannot commit, must not
# land, and can never satisfy the assert; every stop is blocked and it re-enters.
# (A FOREGROUND in-process subagent is NOT affected: the harness fires SubagentStop for it and zero
# SubagentStop hooks are registered. The two shapes have opposite exposure — that measurement is
# what ruled out "detect a subagent and no-op", which would have suppressed the guard on the shape
# that CAN leave real work behind.)
#
# WHAT IS ACTUALLY ASSERTED HERE. The fix is not an exemption, so this suite is written to fail if
# it ever becomes one. Agent-ness only VALIDATES THE TRANSCRIPT — it says "this session's
# write-free-ness is trustworthy", never "this session is excused":
#   R1  a write-free assignee stops and delivers.
#   R3  an assignee that DID write is STILL blocked — three ways (dirty file, new-directory file,
#       its own unlanded commit). Without these, "fixed" is indistinguishable from "hook disabled".
#   R2  a MAIN session is never an assignee, so its protection is bit-for-bit unchanged.
#   fail-safe  every way of NOT resolving assignee-ness (refuted by team config, no lib, no
#       ancestry) leaves the hook exactly as strict as before. Ignorance never exonerates.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/completion-assert.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export COMPLETION_STATE_DIR="$BATS_TEST_TMPDIR/st"
  export COMPLETION_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  CCBIN="/x/claude-code/bin/claude.exe"
}

# ── ancestry fixture — rows are "pid ppid command…", walked from CC_WF_START_PID. A hook's own $$
# is unknowable in advance, which is exactly why hooks/lib/agent-identity.sh exposes both seams.
pstable() {
  local p="$BATS_TEST_TMPDIR/pstable"; : > "$p"
  local r; for r in "$@"; do printf '%s\n' "$r" >> "$p"; done
  export CC_WF_PSTABLE_FILE="$p" CC_WF_START_PID=1000
}
# The THREE flags CC gives a teammate and nothing else. Requiring all three, on an ANCESTOR, is what
# stops a session whose BRIEF merely quotes them from reading as its own assignee.
assignee_ancestry() { pstable \
  "1000 1001 bash $HOOK" \
  "1001 1002 /bin/zsh -c source /snap.zsh" \
  "1002 1003 $CCBIN --agent-id ${1:-gu-arch}@session-${2:-t1} --agent-name ${1:-gu-arch} --team-name session-${2:-t1} --parent-session-id p1" \
  "1003 1 -zsh"; }
lead_ancestry() { pstable \
  "1000 1001 bash $HOOK" \
  "1001 1002 /bin/zsh -c source /snap.zsh" \
  "1002 1003 $CCBIN --permission-mode auto --model claude-opus-5 --effort high" \
  "1003 1 -zsh"; }
team_cfg() { # $1=team-suffix  $2=assignee member name
  local d="$BATS_TEST_TMPDIR/teamroot/session-${1}"; mkdir -p "$d"
  jq -n --arg n "$2" '{name:"t",members:[
      {agentId:"team-lead@t",name:"team-lead",agentType:"team-lead",tmuxPaneId:"leader"},
      {agentId:($n+"@t"),name:$n,agentType:"general-purpose",tmuxPaneId:"7D0DE6BE-0000-0000-0000-000000000000"}]}' \
    > "$d/config.json"
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teamroot"
}

# A worktree carrying the LEAD's dirty + unlanded state — none of it the subagent's.
lead_repo() {
  W="$BATS_TEST_TMPDIR/w"
  git init -q --bare "$W.git"; git clone -q "$W.git" "$W" 2>/dev/null
  ( cd "$W" || exit 1
    git config user.email t@e.com; git config user.name t; git checkout -q -b main
    mkdir -p config src
    echo base > base.txt; git add -A; git commit -q -m base; git push -q -u origin main
    echo lead > config/kitty.conf; git add -A; git commit -q -m "lead's unlanded work"
    echo leaddirt > lead-dirty.txt ) >/dev/null 2>&1
}
# Transcript: the file-edit tool_uses in $@ (none ⇒ a genuinely read-only session), closing "done".
tx() {
  TX="$BATS_TEST_TMPDIR/tx.jsonl"
  python3 - "$TX" "$@" <<'PY'
import json, sys
out, paths = sys.argv[1], sys.argv[2:]
rows = [{"type": "user", "message": {"content": "research the deploy wiring"}}]
for p in paths:
    rows.append({"type": "assistant", "message": {"content": [
        {"type": "tool_use", "name": "Edit", "input": {"file_path": p}}]}})
rows.append({"type": "assistant", "message": {"content": [{"type": "text", "text":
    "✅ Research complete — findings delivered. Nothing further to investigate."}]}})
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
}
fire() { printf '{"session_id":"S","transcript_path":"%s","cwd":"%s"}' "$TX" "$W" | bash "$HOOK" 2>/dev/null; }
blocked() { printf '%s' "$1" | grep -q '"decision":"block"'; }

# ── R1 — the reported defect ─────────────────────────────────────────────────────────────────────

@test "R1: a write-free assignee STOPS and delivers, despite the lead's dirty+unlanded tree" {
  lead_repo; tx; assignee_ancestry gu-arch t1; team_cfg t1 gu-arch
  run fire
  [ "$status" -eq 0 ]
  ! blocked "$output" || false
  grep -q 'exonerated' "$COMPLETION_IDL" || false
}

@test "R1: argv-only evidence (no readable team config) still exonerates a write-free assignee" {
  # UNKNOWN-config is read as an abstain here exactly as session-continue's wake floor reads it.
  # One discriminator with two policies is the same defect as two discriminators.
  lead_repo; tx; assignee_ancestry gu-arch t1
  run fire
  [ "$status" -eq 0 ]
  ! blocked "$output" || false
}

# ── R3 — the positive controls. These are the whole proof that R1 is a fix, not an off-switch ────

@test "R3 CONTROL: an assignee that left its OWN dirty file is STILL blocked" {
  lead_repo; echo mine > "$W/src/report.md"; tx "$W/src/report.md"
  assignee_ancestry gu-arch t1; team_cfg t1 gu-arch
  run fire
  [ "$status" -eq 0 ]
  blocked "$output" || false
}

@test "R3 CONTROL: an assignee's own write in a NEW DIRECTORY is STILL blocked" {
  # git status collapses a wholly untracked dir to one record (`?? docs/`), so before the -uall fix
  # in hooks/lib/session-writes.sh this exonerated — a false-GREEN that would have made R1 look
  # correct while quietly disabling the control beside it.
  lead_repo; mkdir -p "$W/docs/newdir"; echo mine > "$W/docs/newdir/report.md"
  tx "$W/docs/newdir/report.md"
  assignee_ancestry gu-arch t1; team_cfg t1 gu-arch
  run fire
  [ "$status" -eq 0 ]
  blocked "$output" || false
}

@test "R3 CONTROL: an assignee whose OWN commit is unlanded is STILL blocked" {
  lead_repo
  echo mine > "$W/src/report.md"
  ( cd "$W" && git add -A && git commit -q -m "subagent's own work" ) >/dev/null 2>&1
  tx "$W/src/report.md"
  assignee_ancestry gu-arch t1; team_cfg t1 gu-arch
  run fire
  [ "$status" -eq 0 ]
  blocked "$output" || false
}

# ── R2 + fail-safes — every way of NOT knowing must stay strict ───────────────────────────────────

@test "R2: a MAIN session with no recorded writes is blocked exactly as before" {
  lead_repo; tx; lead_ancestry
  run fire
  [ "$status" -eq 0 ]
  blocked "$output" || false
}

@test "fail-safe: an argv match REFUTED by the team's own config does not exonerate" {
  # The false positive this closes is concrete: `ps -o command=` flattens argv, so a session whose
  # BRIEF quotes assignee flags carries all three as apparent words. The harness's own team config
  # is the cross-source that refutes it.
  lead_repo; tx; assignee_ancestry not-a-member t1; team_cfg t1 someone-else
  run fire
  [ "$status" -eq 0 ]
  blocked "$output" || false
}

@test "fail-safe: no ancestry evidence at all does not exonerate" {
  lead_repo; tx; pstable "1000 1 bash $HOOK"
  run fire
  [ "$status" -eq 0 ]
  blocked "$output" || false
}

@test "fail-safe: an unresolvable agent-identity lib does not exonerate" {
  # A missing lib must degrade to the pre-fix behaviour, never to a blanket exemption.
  lead_repo; tx; assignee_ancestry gu-arch t1; team_cfg t1 gu-arch
  export AGENT_IDENTITY_LIB="$BATS_TEST_TMPDIR/nonexistent-lib.sh"
  run fire
  [ "$status" -eq 0 ]
  blocked "$output" || false
}

@test "fail-safe: an unreadable transcript is cannot-tell, not innocence — even for an assignee" {
  lead_repo; TX="$BATS_TEST_TMPDIR/nope.jsonl"
  assignee_ancestry gu-arch t1; team_cfg t1 gu-arch
  run fire
  [ "$status" -eq 0 ]
  ! grep -q 'exonerated' "$COMPLETION_IDL" 2>/dev/null || false
}
