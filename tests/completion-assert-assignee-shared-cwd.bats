#!/usr/bin/env bats
# RC-3 — completion-assert must ABSTAIN for a CONFIRMED assignee whose cwd is SHARED with its lead.
# W1 of docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md. Pinned pre-fix sha d88366d52.
#
# THE MEASURED DEFECT (register § 3 RC-3): a teammate is a full session and runs the fleet's 13 Stop
# hooks. On a SHARED worktree the lead commits by brief, so the member can neither commit nor land —
# and completion-assert convicts it on `dirty` / `unlanded` anyway: 94 blocks across 53 of 334
# teammate sessions since 2026-08-20, each costing a forced turn. Worse, by the vendor rule a BLOCKED
# Stop emits no TeammateIdle and no idle_notification, so the fleet's own closer is silently disarmed
# on exactly those stops. `hooks/session-continue.sh:874-884` / `:1009-1012` already abstain for this
# population — two arms, one population, opposite policies.
#
# THE NARROWING IS THE POINT, AND R3 STILL BINDS. session-continue abstains for ANY confirmed
# assignee; this arm does NOT copy that. An implementation teammate on its OWN worktree must still be
# convicted for uncommitted work (register RC-3 "must NOT wrap"). (b) below is that equivalence
# guard, and `mutant:` proves it is not decorative by building the over-wide version and killing it.
#
# HERMETIC: the identity oracle is the REAL hooks/lib/agent-identity.sh driven through its own
# documented seams (CC_WF_PSTABLE_FILE / CC_WF_START_PID / CC_WF_TEAM_ROOTS) — never a
# re-implementation, which is fixture drift by construction.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/completion-assert.sh"
  D="$BATS_TEST_TMPDIR"
  # HERMETIC #0 — $HOME. agent-identity.sh's team-root fallback globs "$HOME"/.claude*/teams and the
  # hook's own lib chain ends at "$HOME/.claude/hooks/...", so an unfixtured $HOME makes every arm
  # here a function of the operator's live fleet (~10 real team configs on this box). CC_WF_TEAM_ROOTS
  # already pins the root this suite drives, but pinning only the seam leaves the FALLBACKS live —
  # which is the half that bites when a seam is renamed. Same class the sibling suite's HERMETIC #2
  # names, and caught by scripts/test-hermeticity-lint.sh.
  export HOME="$D/home"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  mkdir -p "$CLAUDE_CONFIG_DIR/hooks/lib" "$CLAUDE_CONFIG_DIR/teams"
  export COMPLETION_STATE_DIR="$D/state"
  export COMPLETION_IDL="$D/idl.jsonl"
  export COMPLETION_MAX=3
  export WRAP_TRUNK="origin/main"
  # Same hermeticity pins the sibling suite carries: without them these arms are judged against the
  # real box's live layer, converge record, registry, backlog and custody store.
  export WRAP_LIVE_ROOT="$D/no-live-root"
  export CC_POSTLAND_DIR="$D/postland"
  export CC_FIRED_DIR="$D/fired"; mkdir -p "$CC_FIRED_DIR"
  export CC_CUSTODY_DIR="$D/custody"
  export CC_REGISTRY_DIR="$D/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CONTINUE_IDL="$D/continue-idl.jsonl"
  export CONTINUE_LOG="$D/continue.log"
  export CC_IDL="$D/cc-idl.jsonl"
  unset CLAUDE_SESSION_ID WRAP_SESSION_ID
  CCB_STUB="$D/cc-backlog-stub"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s" "${CC_BACKLOG_STUB_JSON-[]}"' 'exit "${CC_BACKLOG_STUB_RC:-0}"' > "$CCB_STUB"
  chmod +x "$CCB_STUB"; export CC_BACKLOG_BIN="$CCB_STUB"
  # THE AXIS UNDER TEST IS PINNED ON, not off: the sibling suite pins AGENT_IDENTITY_LIB at a missing
  # file precisely so its fixtures are never read as assignees. Here assignee-ness IS the subject, so
  # the real lib is wired up and its seams carry the fixture's ancestry instead of the harness's.
  export AGENT_IDENTITY_LIB="$REPO/hooks/lib/agent-identity.sh"
  export CC_WF_TEAM_ROOTS="$D/teams"
  mkdir -p "$CC_WF_TEAM_ROOTS"
  # Transient identity for every fixture commit below. The persistent `git config user.email` form is
  # banned in this repo: ~100 linked worktrees share ONE .git/config, so a fixture that set it would
  # re-author every session on the machine (2026-08-05, 9 mis-attributed commits here, 214 on reso).
  GITID=(-c user.email=t@e.com -c user.name=t)
}

# A process table in which THIS test's ancestry is a real teammate's claude.exe: the three flags,
# cross-field consistent, as CC emits them. CC_WF_START_PID pins where the ancestry walk begins.
pstable() { # <member> <team-slug>
  printf '%s\n' \
    "  9001  9002 /bin/bash /tmp/hook.sh" \
    "  9002     1 /usr/local/bin/claude.exe --agent-id $1@session-$2 --agent-name $1 --team-name session-$2" \
    > "$D/pstable.txt"
  export CC_WF_PSTABLE_FILE="$D/pstable.txt"
  export CC_WF_START_PID=9001
}

# team config.json. With <lead-cwd> == <member-cwd> the tree is SHARED (the :784 occupancy oracle
# counts 2); with them different the member is the sole occupant and OWNS its tree.
teamcfg() { # <team-slug> <member> <member-cwd> <lead-cwd>
  mkdir -p "$CC_WF_TEAM_ROOTS/session-$1"
  jq -nc --arg m "$2" --arg mc "$3" --arg lc "$4" \
    '{members:[{name:"team-lead",tmuxPaneId:"leader",agentType:"team-lead",cwd:$lc},
               {name:$m,tmuxPaneId:"%9",cwd:$mc}]}' \
    > "$CC_WF_TEAM_ROOTS/session-$1/config.json"
}

# a repo on origin/main with one UNCOMMITTED edit to <path> ⇒ DIRTY=1
mkrepo_dirty() { # <tag> <path>
  local o="$D/o-$1.git" w="$D/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  git -C "$w" checkout -q -b main
  mkdir -p "$w/$(dirname "$2")"; echo base > "$w/$2"
  git -C "$w" add -A; git -C "$w" "${GITID[@]}" commit -q -m base
  git -C "$w" push -q -u origin main >/dev/null 2>&1
  echo 'work in progress' >> "$w/$2"
  printf '%s' "$w"
}

# a repo on origin/main with one COMMITTED-BUT-UNLANDED commit touching <path> ⇒ UNLANDED=1
mkrepo_unlanded() { # <tag> <path>
  local o="$D/o-$1.git" w="$D/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  git -C "$w" checkout -q -b main
  echo base > "$w/base.txt"
  git -C "$w" add -A; git -C "$w" "${GITID[@]}" commit -q -m base
  git -C "$w" push -q -u origin main >/dev/null 2>&1
  mkdir -p "$w/$(dirname "$2")"; echo 'member work' > "$w/$2"
  git -C "$w" add -A; git -C "$w" "${GITID[@]}" commit -q -m "member work"
  printf '%s' "$w"
}

# a transcript in which the session WROTE <paths> and then declared done
tr_wrote() { # <out> <paths…>
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
out, paths = sys.argv[1], sys.argv[2:]
rows = [{"type":"user","message":{"content":"go"}}]
for p in paths:
    rows.append({"type":"assistant","message":{"content":[
        {"type":"tool_use","name":"Edit","input":{"file_path":p}}]}})
rows.append({"type":"assistant","message":{"content":[{"type":"text","text":"✅ Complete — all done."}]}})
open(out,"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
PY
  printf '%s' "$out"
}

run_ca() { # <transcript> <cwd> <sid> [hook]
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "${3:-sid-1}" "$1" "$2" | bash "${4:-$HOOK}"
}
blocked() { printf '%s' "$1" | grep -q '"decision":"block"'; }

# ── (a) RED PROOF ────────────────────────────────────────────────────────────────────────────────
@test "RC-3 (a): a confirmed assignee on a SHARED cwd that wrote and reports done ⇒ NOT blocked" {
  local w; w="$(mkrepo_dirty sh1 src/a.ts)"
  pstable wkrShared t1
  teamcfg t1 wkrShared "$w" "$w"          # lead and member record the SAME cwd ⇒ shared
  local tr; tr="$(tr_wrote "$D/tr-a.jsonl" "$w/src/a.ts")"
  run run_ca "$tr" "$w" S-a
  [ "$status" -eq 0 ]
  ! blocked "$output" || false
}

# ── (b) EQUIVALENCE GUARD — green BOTH before and after the fix. R3 binds. ───────────────────────
@test "RC-3 (b) equivalence guard: an assignee on its OWN worktree that wrote and did not commit ⇒ STILL blocked" {
  local w; w="$(mkrepo_dirty own1 src/b.ts)"
  pstable wkrOwn t2
  teamcfg t2 wkrOwn "$w" "$D/lead-elsewhere"   # sole occupant of its own tree ⇒ OWNED
  local tr; tr="$(tr_wrote "$D/tr-b.jsonl" "$w/src/b.ts")"
  run run_ca "$tr" "$w" S-b
  [ "$status" -eq 0 ]
  blocked "$output"
}

# ── THE MUTANT THAT GIVES (b) POWER ──────────────────────────────────────────────────────────────
# (b) passes before AND after, so on its own it proves nothing. The over-wide fix — abstain for ANY
# confirmed assignee, which is exactly session-continue's blanket policy — passes (a) and every other
# arm here. Only (b) kills it. Built and EXECUTED, not asserted.
@test "RC-3 mutant: the over-wide 'abstain for any assignee' fix is KILLED by (b)" {
  local mut="$D/mutant-ca.sh"
  # force the shared-cwd oracle to answer YES unconditionally ⇒ the narrowing is gone
  sed -e 's|^_ca_assignee_shared_cwd() {|_ca_assignee_shared_cwd() { printf "mutant"; return 0;|' \
      "$HOOK" > "$mut"
  grep -q '_ca_assignee_shared_cwd() { printf "mutant"' "$mut" \
    || skip "pre-fix tree: the shared-cwd oracle does not exist yet, so there is nothing to mutate"
  local w; w="$(mkrepo_dirty mut1 src/c.ts)"
  pstable wkrMut t3
  teamcfg t3 wkrMut "$w" "$D/lead-elsewhere"   # OWNED — (b)'s shape
  local tr; tr="$(tr_wrote "$D/tr-m.jsonl" "$w/src/c.ts")"
  run run_ca "$tr" "$w" S-m "$mut"
  [ "$status" -eq 0 ]
  # the mutant does NOT block where the real hook must ⇒ (b) goes RED against it ⇒ (b) has power
  ! blocked "$output" || false
}

# ── THE IDENTITY GUARD, in both directions ───────────────────────────────────────────────────────
# Without this, (a) would also pass against "abstain whenever the cwd is shared", which would gut the
# guard for every ORIGIN session in the shared checkout — the population peer-owned.sh already
# answers separately and must keep answering.
@test "RC-3 control: a NON-assignee on a shared-looking cwd is unaffected — still blocked" {
  local w; w="$(mkrepo_dirty non1 src/d.ts)"
  # no teammate ancestry at all: the argv oracle finds nothing ⇒ not an assignee
  printf '%s\n' "  9001  9002 /bin/bash /tmp/hook.sh" "  9002     1 /bin/zsh -l" > "$D/pstable.txt"
  export CC_WF_PSTABLE_FILE="$D/pstable.txt"; export CC_WF_START_PID=9001
  teamcfg t4 someoneElse "$w" "$w"
  local tr; tr="$(tr_wrote "$D/tr-n.jsonl" "$w/src/d.ts")"
  run run_ca "$tr" "$w" S-n
  [ "$status" -eq 0 ]
  blocked "$output"
}

# A config that positively REFUTES the argv match (the member is the LEAD) must not buy the abstain:
# agent_is_assignee returns 1 there, and the shared-cwd question is never reached.
@test "RC-3 control: a LEAD whose argv looks teammate-shaped is refuted by the config ⇒ still blocked" {
  local w; w="$(mkrepo_dirty lead1 src/e.ts)"
  pstable teamLead t5
  mkdir -p "$CC_WF_TEAM_ROOTS/session-t5"
  jq -nc --arg c "$w" '{members:[{name:"teamLead",tmuxPaneId:"leader",agentType:"team-lead",cwd:$c}]}' \
    > "$CC_WF_TEAM_ROOTS/session-t5/config.json"
  local tr; tr="$(tr_wrote "$D/tr-l.jsonl" "$w/src/e.ts")"
  run run_ca "$tr" "$w" S-l
  [ "$status" -eq 0 ]
  blocked "$output"
}

# ── THE UNLANDED TERM — the same narrowing, the same two directions ──────────────────────────────
# The fix touches BOTH convictions, so both get a control. On a shared worktree the member must not
# land either: the shared-checkout land is the one .claude/CLAUDE.md forbids by name (incident
# 2026-07-11, dfacccd — five files rebase-dropped by a concurrent land).
@test "RC-3 (a-unlanded): a confirmed assignee on a SHARED cwd with an unlanded commit it wrote ⇒ NOT blocked" {
  local w; w="$(mkrepo_unlanded ush1 src/f.ts)"
  pstable wkrShareU t6
  teamcfg t6 wkrShareU "$w" "$w"
  local tr; tr="$(tr_wrote "$D/tr-ua.jsonl" "$w/src/f.ts")"
  run run_ca "$tr" "$w" S-ua
  [ "$status" -eq 0 ]
  ! blocked "$output" || false
}

@test "RC-3 (b-unlanded) equivalence guard: an assignee on its OWN worktree with an unlanded commit ⇒ STILL blocked" {
  local w; w="$(mkrepo_unlanded uown1 src/g.ts)"
  pstable wkrOwnU t7
  teamcfg t7 wkrOwnU "$w" "$D/lead-elsewhere"
  local tr; tr="$(tr_wrote "$D/tr-ub.jsonl" "$w/src/g.ts")"
  run run_ca "$tr" "$w" S-ub
  [ "$status" -eq 0 ]
  blocked "$output"
}
