#!/usr/bin/env bats
# cc-classify — RED-proof each of the 7 causes against fixtures (mock registry + mock transcripts +
# mock ps + temp git). SAFETY properties under test: an active / rate-limited / waiting session is
# NEVER labeled reapable; the two reapable causes require positive evidence.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-classify"
  D="$BATS_TEST_TMPDIR"
  mkdir -p "$D/bin" "$D/proj/slug" "$D/teams"
  NOW=1000000000
  # a guaranteed-dead pid (> kern.maxproc) and a guaranteed-live pid (this shell)
  DEAD=4000000; LIVE=$$
  # mock cc-sessions: prints $D/sessions.json
  cat > "$D/bin/cc-sessions" <<EOF
#!/bin/bash
cat "$D/sessions.json"
EOF
  chmod +x "$D/bin/cc-sessions"
  # default ps mock: NO agent procs (override per-test)
  printf '#!/bin/bash\ntrue\n' > "$D/bin/ps-none"; chmod +x "$D/bin/ps-none"
  printf '#!/bin/bash\necho "12345 claude --agent-name worker-1"\n' > "$D/bin/ps-agent"; chmod +x "$D/bin/ps-agent"
  export CC_CLASSIFY_SESSIONS_BIN="$D/bin/cc-sessions"
  export CC_CLASSIFY_NOW="$NOW"
  export CC_CLASSIFY_IDLE_S=300
  export CC_CLASSIFY_PROJECT_ROOTS="$D/proj"
  export CC_CLASSIFY_TEAMS_GLOB="$D/teams"
  export CC_CLASSIFY_PS_BIN="$D/bin/ps-none"
  # hermetic wait-system inputs: absent by default (per-test opt-in), never the real machine state
  export CC_CLASSIFY_WAIT_CONTRACTS_DIR="$D/wait-contracts"
  export CC_CLASSIFY_DESK_ROLE_FILE="$D/cc-roles-desk"
}

# write a single-session registry; args: paneUUID pid cwd sid [startedAt]
reg() { printf '[{"name":"t","paneUUID":"%s","account":"next","cwd":"%s","pid":%s,"session_id":"%s","startedAt":%s}]\n' \
        "$1" "$3" "$2" "$4" "${5:-0}" > "$D/sessions.json"; }
# append a second session to the registry (the successor); args: paneUUID pid cwd sid startedAt
add() { jq --arg p "$1" --arg pid "$2" --arg cwd "$3" --arg sid "$4" --argjson s "$5" \
        '. += [{"name":"succ","paneUUID":$p,"account":"next","cwd":$cwd,"pid":($pid|tonumber),"session_id":$sid,"startedAt":$s}]' \
        "$D/sessions.json" > "$D/sessions.json.t" && mv "$D/sessions.json.t" "$D/sessions.json"; }
# transcript with a last assistant turn at <epoch-offset-from-NOW seconds ago>; extra jsonl lines appended
tx() { local sid="$1" ago="$2"; local ts; ts="$(TZ=UTC date -j -f %s "$((NOW-ago))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
       printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}\n' "$ts" > "$D/proj/slug/$sid.jsonl"; }
cause() { "$C" "$1" --json 2>/dev/null | jq -r '.cause'; }
# a real git repo whose HEAD == origin/main (work LANDED). `dirty` arg (any value) leaves the tree dirty.
mkrepo() { local r="$1" dirty="${2:-}"; mkdir -p "$r"; git -C "$r" init -q
           git -C "$r" config user.email t@t; git -C "$r" config user.name t
           echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c1
           git -C "$r" update-ref refs/remotes/origin/main HEAD
           [ -n "$dirty" ] && echo change >> "$r/f"; return 0; }
# write an implicit-team config (only the in-process `team-lead` placeholder — CC 2.1.178+ writes one
# for EVERY session, solo ones too). args: sid
solo_team_cfg() { mkdir -p "$D/teams/session-$1"
  printf '{"leadSessionId":"%s","members":[{"name":"team-lead","agentType":"team-lead","backendType":"in-process"}]}\n' "$1" \
    > "$D/teams/session-$1/config.json"; }

@test "active — recent assistant turn (< idle threshold)" {
  reg PANE-A "$LIVE" /repo sidA; tx sidA 30
  [ "$(cause PANE-A)" = active ]
}

@test "crashed — owning pid is dead" {
  reg PANE-A "$DEAD" /repo sidA; tx sidA 30
  [ "$(cause PANE-A)" = crashed ]
}

@test "rate-limited — structured usage-cap api error in the transcript tail" {
  reg PANE-A "$LIVE" /repo sidA; tx sidA 9000
  printf '{"type":"assistant","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'\''ve hit your session limit · resets 6pm"}]}}\n' >> "$D/proj/slug/sidA.jsonl"
  [ "$(cause PANE-A)" = rate-limited ]
}

@test "handed-off-lead — idle + fired /handoff + a LIVE successor in the same cwd" {
  reg PANE-A "$LIVE" /work sidA 500
  printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"~/.claude/scripts/handoff-fire.sh --recycle"}}]}}\n' >> "$D/proj/slug/sidA.jsonl"
  add PANE-B "$LIVE" /work sidB 999999900000   # successor: same cwd, alive pid, newer (epoch-ms)
  [ "$(cause PANE-A)" = handed-off-lead ]
}

@test "handed-off-lead REFUSED when the successor is DEAD (no live successor → never this cause)" {
  reg PANE-A "$LIVE" /work sidA 500
  printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"handoff-fire.sh --recycle"}}]}}\n' >> "$D/proj/slug/sidA.jsonl"
  add PANE-B "$DEAD" /work sidB 999999900000   # a DEAD 'successor' is no successor (epoch-ms, passes time-gate)
  [ "$(cause PANE-A)" != handed-off-lead ]
}

@test "handoff is NOT inferred from CC-native bridge-session records (false-positive guard)" {
  reg PANE-A "$LIVE" /work sidA 500; tx sidA 9000
  printf '{"type":"bridge-session","sessionId":"sidA","bridgeSessionId":"cse_01"}\n' >> "$D/proj/slug/sidA.jsonl"
  add PANE-B "$LIVE" /work sidB 999999900
  [ "$(cause PANE-A)" != handed-off-lead ]
}

@test "finished-teammate — an idle worktree session" {
  reg PANE-A "$LIVE" /tmp/wt-feature-x sidA; tx sidA 9000
  [ "$(cause PANE-A)" = finished-teammate ]
}

@test "finished — idle solo session (implicit team only) + work LANDED → reapable" {
  # the done-lifecycle session: idle, only the phantom team-lead member, tree clean & on trunk.
  mkrepo "$D/landed"; reg PANE-A "$LIVE" "$D/landed" sidDone; tx sidDone 9000; solo_team_cfg sidDone
  [ "$(cause PANE-A)" = finished ]
}

@test "finished REQUIRES landed — idle solo session on a DIRTY tree stays owned-wait (never-reap)" {
  # same session but with uncommitted work: must NOT be reapable, and must NOT be coordination-hang.
  mkrepo "$D/wip" dirty; reg PANE-A "$LIVE" "$D/wip" sidWip; tx sidWip 9000; solo_team_cfg sidWip
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
  [ "$c" != coordination-hang ]
}

@test "implicit solo team is NOT coordination-hang — regression for the uniform-coordination-hang bug" {
  # the exact production shape: every session has a teams/session-<sid>/config.json with only team-lead.
  # Ahead-of-trunk (not landed) so 'finished' can't apply — isolates the team-branch decision alone.
  mkrepo "$D/ahead"; echo b > "$D/ahead/g"; git -C "$D/ahead" add g; git -C "$D/ahead" commit -qm c2
  reg PANE-A "$LIVE" "$D/ahead" sidAhead; tx sidAhead 9000; solo_team_cfg sidAhead
  c="$(cause PANE-A)"
  [ "$c" != coordination-hang ]
  [ "$c" = owned-wait ]
}

@test "owned-wait — idle lead of a team with a LIVE member" {
  export CC_CLASSIFY_PS_BIN="$D/bin/ps-agent"
  reg PANE-A "$LIVE" /repo sidLead; tx sidLead 9000
  printf '{"leadSessionId":"sidLead","members":[{"name":"worker-1"}]}\n' > "$D/teams/teamX/config.json" || mkdir -p "$D/teams/teamX" && printf '{"leadSessionId":"sidLead","members":[{"name":"worker-1"}]}\n' > "$D/teams/teamX/config.json"
  [ "$(cause PANE-A)" = owned-wait ]
}

@test "coordination-hang — idle lead of a team with NO live member" {
  export CC_CLASSIFY_PS_BIN="$D/bin/ps-none"
  mkdir -p "$D/teams/teamY"
  reg PANE-A "$LIVE" /repo sidLead2; tx sidLead2 9000
  printf '{"leadSessionId":"sidLead2","members":[{"name":"worker-9"}]}\n' > "$D/teams/teamY/config.json"
  [ "$(cause PANE-A)" = coordination-hang ]
}

@test "owned-wait — idle plain session, no team (never-reap default, not reapable)" {
  reg PANE-A "$LIVE" /repo sidA; tx sidA 9000
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
}

@test "no readable transcript → active (fail-safe: cannot prove idle)" {
  reg PANE-A "$LIVE" /repo sidNoTx    # no tx file written
  [ "$(cause PANE-A)" = active ]
}

# ── Gap A (2026-07-17): dead-partner coordination-hang past the horizon + a live co-cwd owner ──────
@test "coordination-abandoned — dead partner, idle past horizon, LIVE co-cwd owner → reapable (Gap A)" {
  export CC_CLASSIFY_PS_BIN="$D/bin/ps-none"          # partner (worker-dead) NOT alive
  export CC_CLASSIFY_COORD_HANG_DEAD_REAP_S=7200
  mkdir -p "$D/teams/teamZ"
  reg PANE-A "$LIVE" /shared sidZombie; tx sidZombie 50000   # idle 50000s >> 7200 horizon
  printf '{"leadSessionId":"sidZombie","members":[{"name":"worker-dead"}]}\n' > "$D/teams/teamZ/config.json"
  add PANE-LIVE "$LIVE" /shared sidOwner 999999900   # a LIVE distinct session owns the shared cwd
  [ "$(cause PANE-A)" = coordination-abandoned ]
}

@test "coordination-hang STAYS never-reap under the horizon even with a live co-cwd owner (Gap A safety)" {
  export CC_CLASSIFY_PS_BIN="$D/bin/ps-none"
  export CC_CLASSIFY_COORD_HANG_DEAD_REAP_S=7200
  mkdir -p "$D/teams/teamH"
  reg PANE-A "$LIVE" /shared sidRecent; tx sidRecent 1000    # idle 1000s < 7200 horizon
  printf '{"leadSessionId":"sidRecent","members":[{"name":"worker-x"}]}\n' > "$D/teams/teamH/config.json"
  add PANE-LIVE "$LIVE" /shared sidOwner 999999900
  [ "$(cause PANE-A)" = coordination-hang ]
}

# ── Gap B (2026-07-17): done solo session, dirty shared cwd owned by a live sibling → surface only ─
@test "finished-shared-review — landed solo, dirty shared cwd owned by a live sibling → surfaced NOT reaped (Gap B)" {
  mkrepo "$D/shared2" dirty; reg PANE-A "$LIVE" "$D/shared2" sidDone2; tx sidDone2 9000; solo_team_cfg sidDone2
  add PANE-LIVE "$LIVE" "$D/shared2" sidSibling 999999900000   # live sibling owns the unrelated dirt (epoch-ms)
  [ "$(cause PANE-A)" = finished-shared-review ]
}

# ── P0-13 task 1: ms/s unit fix + self-scoped handoff tell (a18 L-3) ────────────────────────────
# lat for these fixtures = epoch of 2001-09-08T00:00:00Z = 999907200s. Registry startedAt is epoch-MS
# (session-register.sh:69 `date +%s * 1000`), so a REAL successor started after lat carries ~1e12; the
# time gate must compare startedAt/1000 >= lat, never the vacuous ms>=s that always held.
@test "successor time-gate (ms/s fix): a co-cwd sibling started BEFORE the last turn is NOT a successor (a18 L-3)" {
  reg PANE-A "$LIVE" /work sidA 500
  printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"~/.claude/scripts/handoff-fire.sh --recycle"}}]}}\n' >> "$D/proj/slug/sidA.jsonl"
  add PANE-B "$LIVE" /work sidB 999000000000   # epoch-ms: 999000000s < lat 999907200s → started BEFORE the last turn
  [ "$(cause PANE-A)" != handed-off-lead ]
}

@test "self-scope: a bare Read of a *-resume.md payload does NOT mark handed-off-lead (a18 L-3)" {
  reg PANE-A "$LIVE" /work sidA 500
  printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Read","input":{"file_path":"/tmp/other-slug-resume.md"}}]}}\n' >> "$D/proj/slug/sidA.jsonl"
  add PANE-B "$LIVE" /work sidB 999999900000   # a live co-cwd sibling
  [ "$(cause PANE-A)" != handed-off-lead ]
}

@test "self-scope: a third-party fire (--worktree elsewhere) does NOT mark handed-off-lead (a18 L-3)" {
  reg PANE-A "$LIVE" /work sidA 500
  printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"~/.claude/scripts/handoff-fire.sh --worktree feat/other-thing --account next2"}}]}}\n' >> "$D/proj/slug/sidA.jsonl"
  add PANE-B "$LIVE" /work sidB 999999900000
  [ "$(cause PANE-A)" != handed-off-lead ]
}

# ── P0-13 task 2: in-flight tool guard (a18 L-13) ───────────────────────────────────────────────
@test "in-flight tool guard: a trailing unmatched tool_use (long tool call) → active, not finished (a18 L-13)" {
  # a solo session mid-way through ONE long Bash call (12-min build/test): the transcript's LAST record
  # is the assistant tool_use, timestamped at call START (20 min ago), no tool_result yet. Clean+landed.
  # IDLE crosses 300s mid-call ⇒ old code reads `finished`; a running tool means NOT idle ⇒ active.
  mkrepo "$D/build"; reg PANE-A "$LIVE" "$D/build" sidBuild
  ts="$(TZ=UTC date -j -f %s "$((NOW-1200))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_build","name":"Bash","input":{"command":"pnpm -s test"}}]}}\n' "$ts" > "$D/proj/slug/sidBuild.jsonl"
  [ "$(cause PANE-A)" = active ]
}

@test "in-flight guard does NOT fire once the tool_result has landed (matched tool_use → finished)" {
  # same tool call but its tool_result HAS landed (user record) and a final text turn closed the turn →
  # not in-flight → the normal finished path applies (clean+landed solo).
  mkrepo "$D/done"; reg PANE-A "$LIVE" "$D/done" sidDone3; solo_team_cfg sidDone3
  ts="$(TZ=UTC date -j -f %s "$((NOW-9000))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  {
    printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_x","name":"Bash","input":{"command":"pnpm -s test"}}]}}\n' "$ts"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_x","content":"ok"}]}}\n'
    printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}\n' "$ts"
  } > "$D/proj/slug/sidDone3.jsonl"
  [ "$(cause PANE-A)" = finished ]
}

# ── P0-13 task 3: wait-contract + desk-role never-reap (a17 S-3) ─────────────────────────────────
@test "wait-contract never-reap: an OPEN wait-contract naming this session → owned-wait, not finished (a17 S-3)" {
  # the S-3 desk: clean+landed solo, idle >10min, waiting on fired peers — but an OPEN wait-contract
  # names it as waiter. The classifier must READ the L2 wait system: positive wait evidence → never-reap.
  mkrepo "$D/desk"; reg PANE-A "$LIVE" "$D/desk" sidDesk; tx sidDesk 9000; solo_team_cfg sidDesk
  mkdir -p "$D/wait-contracts"
  printf '{"id":"c1","waiter":"sidDesk","waitee":"peer","status":"OPEN"}\n' > "$D/wait-contracts/c1.json"
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
  [ "$c" != finished ]
}

@test "wait-contract: a CLOSED contract confers no protection (landed solo still finished — never weakens)" {
  mkrepo "$D/desk2"; reg PANE-A "$LIVE" "$D/desk2" sidDesk2; tx sidDesk2 9000; solo_team_cfg sidDesk2
  mkdir -p "$D/wait-contracts"
  printf '{"id":"c2","waiter":"sidDesk2","waitee":"peer","status":"SATISFIED"}\n' > "$D/wait-contracts/c2.json"
  [ "$(cause PANE-A)" = finished ]
}

@test "desk-role never-reap: the desk-role file resolving to this pane → owned-wait, not finished (a17 S-3)" {
  mkrepo "$D/desk3"; reg PANE-A "$LIVE" "$D/desk3" sidDesk3; tx sidDesk3 9000; solo_team_cfg sidDesk3
  printf 'PANE-A\n' > "$D/cc-roles-desk"
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
  [ "$c" != finished ]
}
