#!/usr/bin/env bats
# wrap-ledger.sh § RESIDENT MEMBERS — RC-2 of docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md.
#
# THE FACT UNDER TEST: at a close, does the ledger tell the lead that members of ITS OWN team are
# still running? Measured cause (docs/research/SUBAGENT_LIFECYCLE_ROOT_CAUSE_2026-09-19.md §3
# RC-2): the vendor ends a member only when its lead says so, 58% of leads send nothing (42/72),
# and 105 of the fleet closer's 124 reaps in 30 d fired behind a LIVE lead. Nothing told the lead.
#
# IT IS A CHECK. Nothing in this file — and nothing in the arm it tests — kills, stops, sends a
# shutdown_request, starts a timer or counts an idle. Every process in every fixture here is a
# LINE IN A TEXT FILE (CC_WF_PSTABLE_FILE); no live session is read, signalled or closed.
#
# THE CONTROL THAT MATTERS MOST is the anti-false-positive one: this arm runs at EVERY close on
# this box, so a matcher that fired on a session merely MENTIONING a member's name would
# manufacture a permanent 🔧 fleet-wide (MEMORY.md pgrep-f-matches-agent-briefs). Three one-line
# mutants of the real predicate are built and each is shown to die on that fixture — without them
# the control would be an equivalence guard (green before and after), not a red-proof.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # Seam so the RED can be recorded against the PINNED PRE-FIX sha without touching the tree:
  #   git show <sha>:scripts/wrap-ledger.sh > /tmp/prefix.sh
  #   WRAP_LEDGER_UNDER_TEST=/tmp/prefix.sh bats tests/wrap-ledger-resident.bats
  LEDGER="${WRAP_LEDGER_UNDER_TEST:-$REPO/scripts/wrap-ledger.sh}"
  # $HOME FIRST, before anything reads it. The ledger resolves several fallbacks under ~ (the
  # backlog/custody binaries, the live-layer root, session-writes' lib path) and THIS arm globs
  # $HOME/.claude*/teams when CC_WF_TEAM_ROOTS is unset — 419 real team dirs on this box. Pinning
  # each store individually still leaves the suite a function of whoever runs it; pinning HOME is
  # what the land gate's test-hermeticity ratchet requires, and what tests/wrap-ledger-memo.bats
  # already does against this same subject.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || return 1
  git checkout -q -b main
  echo base > base.txt; git add base.txt
  # TRANSIENT identity only (-c, never `config`): this fixture runs inside a checkout whose ~100
  # linked worktrees share ONE .git/config, and a persisted identity there re-authors the fleet.
  git -c user.email=tester@example.com -c user.name=tester commit -q -m base
  git push -q -u origin main
  export WRAP_TRUNK="origin/main"
  # Hermeticity, the same discipline tests/wrap-ledger.bats states five times over: every store
  # this ladder reads is pointed at an empty fixture dir, so no arm here is a function of the
  # operator's live box. Without these the ✅-eligible path reads their real custody/backlog/live.
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/absent-cc-backlog"
  export CC_DECIDE_BIN="$BATS_TEST_TMPDIR/absent-cc-decide"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-layer"
  export WRAP_LIVE_ROOT="$BATS_TEST_TMPDIR/no-live-root"
  export CC_MIGRATIONS_STATE="$BATS_TEST_TMPDIR/migrations"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export WRAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/projects"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID
  # …and the seams this arm adds. An EMPTY team-roots dir is the "no team config" world that every
  # session which never spawned a member lives in — i.e. most sessions on this box.
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teams"
  mkdir -p "$CC_WF_TEAM_ROOTS"
  export CC_SESSIONS_BIN="$BATS_TEST_TMPDIR/absent-cc-sessions"
  SID="sess-99999999-8888-7777-6666-555555555555"
  TEAM="session-${SID}"
}

field() { printf '%s' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

# A team config in the shape CC actually writes (verified against a live config 2026-09-19:
# tmuxPaneId "leader" + agentType "team-lead" marks the lead; members[].sessionId is null).
mk_team() { # mk_team <teamname> [<member>…]
  local team="$1"; shift
  local dir="$CC_WF_TEAM_ROOTS/$team" m mem=""
  mkdir -p "$dir"
  for m in "$@"; do
    mem="${mem:+$mem,}$(printf '{"agentId":"%s@%s","name":"%s","agentType":"Explore","joinedAt":1,"tmuxPaneId":"PANE-%s","cwd":"%s","backendType":"iterm2","sessionId":null}' "$m" "$team" "$m" "$m" "$WORK")"
  done
  printf '{"name":"%s","leadAgentId":"team-lead@%s","leadSessionId":"%s","members":[{"agentId":"team-lead@%s","name":"team-lead","agentType":"team-lead","tmuxPaneId":"leader","cwd":"%s","backendType":"in-process"}%s]}\n' \
    "$team" "$team" "$SID" "$team" "$WORK" "${mem:+,$mem}" > "$dir/config.json"
}

# A `ps -axo pid=,ppid=,command=` row. A LIVE member is exactly what CC spawns
# (hooks/lib/agent-identity.sh:13-14): the three flags, mutually consistent.
ps_live_member() { printf '%s 1 /Applications/claude.exe --agent-id %s@%s --agent-name %s --team-name %s --parent-session-id %s\n' "$1" "$2" "$3" "$2" "$3" "$SID"; }

# Every hostile row NAMES the member `alpha` and is not `alpha`. Each kills one weakening.
mk_hostile_ps() {
  {
    # (a) a plain mention in a brief — kills a name-substring (`pgrep -f alpha`) matcher
    printf '3001 1 /Applications/claude.exe --model opus -p brief: tell alpha to stand down and report\n'
    # (b) ONE flag quoted inside a brief. `ps -o command=` flattens argv, so prose reads as argv —
    #     the measured trap of hooks/lib/agent-identity.sh:24-29. Kills a single-flag test.
    printf '3002 1 /Applications/claude.exe --model opus -p the member runs --agent-id %s@%s so watch it\n' alpha "$TEAM"
    # (c) all three flags present but NOT agreeing — kills a co-presence test that never checks
    #     that the id is <name>@<team>.
    printf '3003 1 /Applications/claude.exe --agent-id beta@session-somewhere-else --agent-name alpha --team-name %s\n' "$TEAM"
  } > "$BATS_TEST_TMPDIR/ps-hostile"
}

# Build a mutant by replacing the ONE marked predicate line in a COPY of the real script.
mutate() { # mutate <awk-return-expression> → path to the mutant script
  local expr="$1" out="$BATS_TEST_TMPDIR/mutant.sh"
  awk -v e="      return $expr" '
    /^ *return index\(c, " --agent-id " nm "@" tm " "\)/ { print e; next } { print }
  ' "$LEDGER" > "$out"
  grep -qF "return $expr" "$out" || return 1      # the mutation must actually have applied
  printf '%s' "$out"
}

# ── (1) THE RED: a live member ⇒ not ✅, and it is NAMED ────────────────────────────────────────
@test "RESIDENT: one live member ⇒ NOT ✅, and the READOUT NAMES it" {
  mk_team "$TEAM" alpha
  ps_live_member 4242 alpha "$TEAM" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "1" ]
  [ "$(field "$output" RESIDENT_MINE_NAMES)" = "alpha" ]
  [ "$(field "$output" RESIDENT_SRC)" = "ok" ]
  [ "$(field "$output" RUNG)" = "🔧" ]
  # NAMED, never counted (§ the close message S6): a shutdown_request is addressed to a name, so
  # a readout carrying only "1 member" would not be actionable.
  printf '%s' "$output" | grep -E '^READOUT=' | grep -q alpha
}

# ── (2) THE ARM THAT STOPS IT BECOMING PERMANENT ────────────────────────────────────────────────
@test "RESIDENT: the same fixture with the process GONE ⇒ ✅ is reachable again" {
  mk_team "$TEAM" alpha
  : > "$BATS_TEST_TMPDIR/ps"           # the member exited; its row is gone
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "0" ]
  # An alarm that always fires carries no information (MEMORY.md alarm-polarity-and-attention-budget).
  [ "$(field "$output" RUNG)" = "✅" ]
}

# ── (3) THE ANTI-FALSE-POSITIVE CONTROL, and the three mutants that prove it is not vacuous ─────
@test "RESIDENT: argv that only MENTIONS a member is not a member ⇒ RESIDENT_MINE=0" {
  mk_team "$TEAM" alpha
  mk_hostile_ps
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps-hostile"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "0" ]
  [ "$(field "$output" RESIDENT_MINE_NAMES)" = "" ]
  [ "$(field "$output" RESIDENT_SRC)" = "ok" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "RESIDENT: the pgrep-f mutant DIES on the anti-false-positive fixture" {
  mk_team "$TEAM" alpha
  mk_hostile_ps
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps-hostile"
  local m; m="$(mutate 'index(c, nm)')"
  run env WRAP_SESSION_ID="$SID" bash "$m" --machine
  [ "$status" -eq 0 ]
  # The naive matcher the memory warns about reports a resident that does not exist — so the
  # control above is a RED-PROOF, not an equivalence guard.
  [ "$(field "$output" RESIDENT_MINE)" = "1" ]
  [ "$(field "$output" RUNG)" = "🔧" ]
}

@test "RESIDENT: the single-flag mutant DIES on the same fixture" {
  mk_team "$TEAM" alpha
  mk_hostile_ps
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps-hostile"
  local m; m="$(mutate 'index(c, " --agent-id " nm "@" tm " ")')"
  run env WRAP_SESSION_ID="$SID" bash "$m" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "1" ]     # matched row (b): a flag quoted inside a brief
}

@test "RESIDENT: the co-presence mutant (no cross-field check) DIES on the same fixture" {
  mk_team "$TEAM" alpha
  mk_hostile_ps
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps-hostile"
  local m; m="$(mutate 'index(c, " --agent-id ") && index(c, " --agent-name " nm " ") && index(c, " --team-name " tm " ")')"
  run env WRAP_SESSION_ID="$SID" bash "$m" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "1" ]     # matched row (c): three flags, disagreeing
}

@test "RESIDENT: all three mutants still read 1 on a REAL member — they are weakenings, not breakages" {
  mk_team "$TEAM" alpha
  ps_live_member 4242 alpha "$TEAM" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  local e m
  for e in 'index(c, nm)' \
           'index(c, " --agent-id " nm "@" tm " ")' \
           'index(c, " --agent-id ") && index(c, " --agent-name " nm " ") && index(c, " --team-name " tm " ")'; do
    m="$(mutate "$e")"
    run env WRAP_SESSION_ID="$SID" bash "$m" --machine
    [ "$status" -eq 0 ]
    [ "$(field "$output" RESIDENT_MINE)" = "1" ]
  done
}

# ── (4) THE FLEET-WIDE REGRESSION GUARD ─────────────────────────────────────────────────────────
@test "RESIDENT: a session with NO team config at all ⇒ 0, src none, nothing about its close changes" {
  # No mk_team. Most sessions on this box are not leads; an arm that fired here would fire at
  # every close fleet-wide forever.
  ps_live_member 4242 alpha "$TEAM" > "$BATS_TEST_TMPDIR/ps"   # a LIVE member of somebody else's team
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "0" ]
  [ "$(field "$output" RESIDENT_SRC)" = "none" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "RESIDENT: a config holding ONLY the lead ⇒ 0 (the lead is not its own resident)" {
  mk_team "$TEAM"                       # lead only — what CC writes for a session that spawned none
  printf '4242 1 /Applications/claude.exe --agent-id team-lead@%s --agent-name team-lead --team-name %s\n' "$TEAM" "$TEAM" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "RESIDENT: no session id ⇒ src none (an unresolvable session never manufactures a rung)" {
  mk_team "$TEAM" alpha
  ps_live_member 4242 alpha "$TEAM" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run bash "$LEDGER" --machine          # no WRAP_SESSION_ID
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_SRC)" = "none" ]
  [ "$(field "$output" RESIDENT_MINE)" = "0" ]
}

@test "RESIDENT: the team is found under the SHORT spelling CC actually writes" {
  # Measured on a live config 2026-09-19: the harness names the team session-eb77ca3e for session
  # eb77ca3e-c23c-4f1d-858f-4b116cd759d3. A resolver trying only the full id would read `none` for
  # every real lead on this box — the arm would be inert and nothing would report it.
  local short="session-${SID%%-*}"
  mk_team "$short" alpha
  ps_live_member 4242 alpha "$short" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "1" ]
  [ "$(field "$output" RESIDENT_MINE_NAMES)" = "alpha" ]
}

@test "RESIDENT: two live members are BOTH named" {
  mk_team "$TEAM" alpha beta
  { ps_live_member 4242 alpha "$TEAM"; ps_live_member 4243 beta "$TEAM"; } > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "2" ]
  printf '%s' "$output" | grep -E '^RESIDENT_MINE_NAMES=' | grep -q alpha
  printf '%s' "$output" | grep -E '^RESIDENT_MINE_NAMES=' | grep -q beta
  printf '%s' "$output" | grep -E '^READOUT=' | grep -q alpha
  printf '%s' "$output" | grep -E '^READOUT=' | grep -q beta
}

@test "RESIDENT: one member live, one gone ⇒ only the live one is named" {
  mk_team "$TEAM" alpha beta
  ps_live_member 4242 alpha "$TEAM" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "1" ]
  [ "$(field "$output" RESIDENT_MINE_NAMES)" = "alpha" ]
}

@test "RESIDENT: a member of ANOTHER team bearing the same name is not mine" {
  mk_team "$TEAM" alpha
  ps_live_member 4242 alpha "session-someone-else" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "0" ]
}

@test "RESIDENT: the team-blind mutant DIES on another team's member of the same name" {
  # Gives the case above its power: without this the "another team" assertion is only pinned by
  # the field being absent pre-fix, i.e. an equivalence guard for the rung.
  mk_team "$TEAM" alpha
  ps_live_member 4242 alpha "session-someone-else" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  local m; m="$(mutate 'index(c, " --agent-id ") && index(c, " --agent-name " nm " ")')"
  run env WRAP_SESSION_ID="$SID" bash "$m" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "1" ]     # a stranger's member counted as mine
}

@test "RESIDENT: a worse rung already governing ⇒ src skip (never computed, never a second cost)" {
  mk_team "$TEAM" alpha
  ps_live_member 4242 alpha "$TEAM" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  echo dirt > dirt.txt                                  # DIRTY outranks every ✅-eligible arm
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" RESIDENT_SRC)" = "skip" ]
  [ "$(field "$output" RESIDENT_MINE)" = "0" ]
}

@test "RESIDENT: WRAP_RESIDENT=off is a kill switch restoring the previous behaviour exactly" {
  mk_team "$TEAM" alpha
  ps_live_member 4242 alpha "$TEAM" > "$BATS_TEST_TMPDIR/ps"
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps"
  run env WRAP_SESSION_ID="$SID" WRAP_RESIDENT=off bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "RESIDENT: an empty ps table fails OPEN (0, rung unchanged)" {
  mk_team "$TEAM" alpha
  : > "$BATS_TEST_TMPDIR/ps-empty"
  # An EMPTY table and a dead `ps` are indistinguishable here and demand opposite readings
  # (docs/lessons/empty-vs-no-surface.md) — but only one direction is safe on an arm that runs at
  # every close, so both read 0. This case pins the DIRECTION, which is the property that matters.
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/ps-empty"
  run env WRAP_SESSION_ID="$SID" bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESIDENT_MINE)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

# ── (5) THE OPERATOR CONSTRAINT, ASSERTED MECHANICALLY ──────────────────────────────────────────
@test "RESIDENT: this wave adds NO ACTUATOR — the arm's source calls nothing that acts" {
  # "only solve if and when we have explicit issues identified to explicitly solve, never wrap
  # unknown unknowns with general catches and patches" — pinned here rather than promised in a
  # commit message. The arm may NAME shutdown_request and TaskStop in the sentence it renders to
  # the lead; it may not CALL anything. Scope: the § RESIDENT MEMBERS block only.
  local blk="$BATS_TEST_TMPDIR/arm.sh"
  awk '/^# ── RESIDENT MEMBERS/,/^# ── LIVE LAYER/' "$LEDGER" > "$blk"
  [ -s "$blk" ]
  # Whole-line comments out (the arm DISCUSSES TaskStop and shutdown_request, by design — that is
  # what it tells the lead to do), leaving only code.
  local code="$BATS_TEST_TMPDIR/arm.code.sh"
  grep -v '^[[:space:]]*#' "$blk" > "$code"
  [ -s "$code" ]
  # An actuator is a token in COMMAND POSITION — start of a command, or after ; & | ( or &&/||.
  # The same tokens inside the rendered sentence ("escalate to TaskStop after ~60s") are prose and
  # are what the check is FOR, so position is the discriminator, not presence.
  ! grep -qE '(^|[;&|(]|&&|\|\|)[[:space:]]*(kill|pkill|killall|osascript|it2|tmux|cc-notify|cc-teardown|crontab|at|sleep|rm|mv|launchctl)([[:space:]]|$)' "$code" || false
  # No timer, no idle count, no mode switch, no auto-approve — the four shapes the brief forbids
  # by name, none of which has any legitimate spelling in a read-only arm.
  ! grep -qE '(teammateMode|shutdown_approved|auto_approve|autoApprove|idle_count|TeammateIdle)' "$code" || false
  # And it writes nothing: no redirection to a real path, no tee. `>/dev/null` and friends are
  # READ-ONLY idioms (`command -v jq >/dev/null`) and are stripped before the test — the first
  # form of this line matched them, and only the dead-assertion ratchet revealed it, because a
  # mid-test `! cmd` under errexit always passes (MEMORY.md negated-assertion-dead-unless-final).
  local nodev="$BATS_TEST_TMPDIR/arm.nodev.sh"
  sed 's#>[[:space:]]*/dev/[a-z]*##g' "$code" > "$nodev"
  ! grep -qE '(^|[^0-9<>&])>[[:space:]]*[^&|)]*/' "$nodev" || false
  ! grep -qE '(^|[;&|(])[[:space:]]*tee([[:space:]]|$)' "$code"
}
