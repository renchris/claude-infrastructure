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
  # ── 2026-07-24 fired-peer stamp + operator-interaction hold: hermetic marker dir, EMPTY by default
  #    (⇒ operator pane ⇒ finished/finished-teammate can never apply); tests opt in with stamp. Hold
  #    pinned explicitly so env drift can't change the fixtures' meaning. ──
  export CC_FIRED_DIR="$D/fired"
  export CC_CLASSIFY_INTERACTIVE_HOLD_S=21600
  export CC_CLASSIFY_FIRE_PROMPT_SLACK_S=300
}
# fired_peer refuses non-UUID panes as path fragments, so stamped tests need a UUID-shaped pane.
UP="4EC4DA5D-0000-4000-8000-000000000001"
# a second UUID for a firedBy-stamped SUCCESSOR pane (change 4 positive-handoff link).
SUCC="4EC4DA5D-0000-4000-8000-000000000002"

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
# a REAL operator-typed prompt <ago> seconds before NOW (string content, no isMeta); args: sid ago [text]
utx() { local sid="$1" ago="$2" text="${3:-please do the thing}"; local ts
        ts="$(TZ=UTC date -j -f %s "$((NOW-ago))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
        printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"%s"}}\n' "$ts" "$text" >> "$D/proj/slug/$sid.jsonl"; }
# the spawner's fired-peer stamp (handoff-fire mark_fired_peer shape); args: paneUUID [fired-ago-seconds]
# ALSO binds the registered startedAt for this pane to the fire epoch so the stamp is tenancy-VALID by
# default (rule 2: a real fired worker boots ~at the fire) — must be called AFTER reg/add wrote the row.
stamp() { local pane="$1" ago="${2:-50000}"; mkdir -p "$D/fired"; local iso fire_ep=$((NOW-ago))
          iso="$(TZ=UTC date -j -u -f %s "$fire_ep" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
          printf '{"paneUUID":"%s","cwd":"x","firedBy":"t","firedAt":"%s","selfRetire":true}\n' "$pane" "$iso" > "$D/fired/$pane.json"
          [ -f "$D/sessions.json" ] && jq --arg p "$pane" --argjson s "$((fire_ep*1000))" \
            '(.[]|select(.paneUUID==$p)|.startedAt)|=$s' "$D/sessions.json" > "$D/sessions.json.t" 2>/dev/null \
            && mv "$D/sessions.json.t" "$D/sessions.json"; return 0; }
# a fired stamp whose firedBy names the PREDECESSOR sid (change 4 positive-handoff link), sitting on the
# SUCCESSOR pane; binds the successor's startedAt to the fire epoch (tenancy-valid). args: succ-pane pred-sid [ago]
stamp_by() { local pane="$1" by="$2" ago="${3:-200}"; mkdir -p "$D/fired"; local iso fire_ep=$((NOW-ago))
             iso="$(TZ=UTC date -j -u -f %s "$fire_ep" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
             printf '{"paneUUID":"%s","cwd":"x","firedBy":"%s","firedAt":"%s","selfRetire":true}\n' "$pane" "$by" "$iso" > "$D/fired/$pane.json"
             [ -f "$D/sessions.json" ] && jq --arg p "$pane" --argjson s "$((fire_ep*1000))" \
               '(.[]|select(.paneUUID==$p)|.startedAt)|=$s' "$D/sessions.json" > "$D/sessions.json.t" 2>/dev/null \
               && mv "$D/sessions.json.t" "$D/sessions.json"; return 0; }
# a real git repo whose HEAD == origin/main (work LANDED). `dirty` arg (any value) leaves the tree dirty.
# `git -C ""` is a NO-OP, not an error — an empty <dir> would write this identity into the cwd repo.
mkrepo() { local r="${1:?mkrepo: repo path required}" dirty="${2:-}"; mkdir -p "$r"; git -C "$r" init -q
           git -C "$r" config user.email t@t; git -C "$r" config user.name t
           echo a > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm c1
           git -C "$r" update-ref refs/remotes/origin/main HEAD
           [ -n "$dirty" ] && echo change >> "$r/f"; return 0; }
# a squash-landed repo: clean tree, HEAD 1 commit AHEAD of origin/main by COUNT, but its content is
# ALREADY on trunk under a DIFFERENT sha (the squash/cherry-pick land). rev-list count says "ahead"
# while the work is durably landed — the L-10 permanent-DEFER trap.
mksquashland() { local r="${1:?mksquashland: repo path required}"; mkdir -p "$r"; git -C "$r" init -q
           git -C "$r" config user.email t@t; git -C "$r" config user.name t
           echo base > "$r/f"; git -C "$r" add f; git -C "$r" commit -qm base
           echo feature >> "$r/f"; git -C "$r" add f; git -C "$r" commit -qm landed-on-trunk
           git -C "$r" update-ref refs/remotes/origin/main HEAD    # trunk = base+feature (commit L)
           git -C "$r" reset -q --hard HEAD~1                      # back to base
           echo feature >> "$r/f"; git -C "$r" add f
           GIT_AUTHOR_DATE="@1000000500" GIT_COMMITTER_DATE="@1000000500" \
             git -C "$r" commit -qm featureX   # identical CONTENT to trunk, different sha (count=1 ahead)
           return 0; }
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

@test "handed-off-lead — idle + fired /handoff + a LIVE firedBy-stamped successor (change 4)" {
  reg PANE-A "$LIVE" /work sidA 500
  printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"~/.claude/scripts/handoff-fire.sh --recycle"}}]}}\n' >> "$D/proj/slug/sidA.jsonl"
  add "$SUCC" "$LIVE" /work sidB 999999900000   # successor: same cwd, alive pid, newer (epoch-ms)
  stamp_by "$SUCC" sidA                          # the spawner stamped the successor pane firedBy=sidA
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

@test "finished-teammate — an idle SPAWNER-STAMPED worktree worker" {
  reg "$UP" "$LIVE" /tmp/wt-feature-x sidA; tx sidA 9000; stamp "$UP"
  [ "$(cause "$UP")" = finished-teammate ]
}

@test "finished-teammate REQUIRES the stamp: an unstamped idle worktree session is NOT a teammate (2026-07-24)" {
  # the Danny-Studio-60 shape minus the conversation: a worktree cwd alone must not brand a session
  # a reapable worker — without the spawner's cc-fired stamp it falls to the never-reap default.
  reg PANE-A "$LIVE" /tmp/wt-feature-x sidU; tx sidU 9000
  c="$(cause PANE-A)"
  [ "$c" != finished-teammate ]
  [ "$c" = owned-wait ]
}

@test "finished — idle STAMPED worker (implicit team only) + work LANDED → reapable" {
  # the done-lifecycle worker: idle, only the phantom team-lead member, tree clean & on trunk, stamped.
  mkrepo "$D/landed"; reg "$UP" "$LIVE" "$D/landed" sidDone; tx sidDone 9000; solo_team_cfg sidDone; stamp "$UP"
  [ "$(cause "$UP")" = finished ]
}

@test "finished-operator — landed idle solo WITHOUT the stamp → surfaced for confirm-close, never reapable (2026-07-24 Opus-5 shape)" {
  # the Opus-5-upgrade session's steady state: operator-launched, Q&A finished hours ago, clean &
  # 0 ahead (it never wrote anything). "Done"-looking, but the pane is the operator's to close.
  mkrepo "$D/opq"; reg PANE-A "$LIVE" "$D/opq" sidOp; tx sidOp 9000; solo_team_cfg sidOp
  [ "$(cause PANE-A)" = finished-operator ]
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

@test "branch-order guard: §4.7 operator hold PRECEDES the coordination-abandoned branch (recent operator prompt wins → owned-wait)" {
  # LOAD-BEARING ORDERING (2026-07-25 Gap 2): a session that is BOTH a coordination-abandoned candidate
  # (dead partner + idle past horizon + live co-cwd owner) AND carries a RECENT operator prompt MUST read
  # owned-wait — because cc-classify evaluates the §4.7 interactive hold (returns ~:404) BEFORE the
  # coordination-abandoned branch (~:440). That ordering was undefended: if the branches are ever
  # reordered (or §4.7's early-return removed), a live operator conversation reads coordination-abandoned
  # (REAPABLE) and this test flips to that value and FAILS. It is the classifier-side twin of cc-reaper's
  # independent second leg for the same cause.
  export CC_CLASSIFY_PS_BIN="$D/bin/ps-none"          # partner dead
  export CC_CLASSIFY_COORD_HANG_DEAD_REAP_S=7200
  mkdir -p "$D/teams/teamO"
  reg PANE-A "$LIVE" /shared sidBoth; tx sidBoth 50000   # last assistant turn 50000s ago → idle past horizon
  utx sidBoth 600                                         # BUT the operator typed 600s ago (< 6h hold)
  printf '{"leadSessionId":"sidBoth","members":[{"name":"worker-dead"}]}\n' > "$D/teams/teamO/config.json"
  add PANE-LIVE "$LIVE" /shared sidOwner 999999900       # live co-cwd owner (coordination-abandoned needs it)
  [ "$(cause PANE-A)" = owned-wait ]
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
  # not in-flight → the normal finished path applies (clean+landed stamped worker).
  mkrepo "$D/done"; reg "$UP" "$LIVE" "$D/done" sidDone3; solo_team_cfg sidDone3; stamp "$UP"
  ts="$(TZ=UTC date -j -f %s "$((NOW-9000))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  {
    printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_x","name":"Bash","input":{"command":"pnpm -s test"}}]}}\n' "$ts"
    printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_x","content":"ok"}]}}\n'
    printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}\n' "$ts"
  } > "$D/proj/slug/sidDone3.jsonl"
  [ "$(cause "$UP")" = finished ]
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

@test "wait-contract: a CLOSED contract confers no protection (landed stamped worker still finished — never weakens)" {
  mkrepo "$D/desk2"; reg "$UP" "$LIVE" "$D/desk2" sidDesk2; tx sidDesk2 9000; solo_team_cfg sidDesk2; stamp "$UP"
  mkdir -p "$D/wait-contracts"
  printf '{"id":"c2","waiter":"sidDesk2","waitee":"peer","status":"SATISFIED"}\n' > "$D/wait-contracts/c2.json"
  [ "$(cause "$UP")" = finished ]
}

@test "desk-role never-reap: the desk-role file resolving to this pane → owned-wait, not finished (a17 S-3)" {
  mkrepo "$D/desk3"; reg PANE-A "$LIVE" "$D/desk3" sidDesk3; tx sidDesk3 9000; solo_team_cfg sidDesk3
  printf 'PANE-A\n' > "$D/cc-roles-desk"
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
  [ "$c" != finished ]
}

# ── P0-17: landed-by-content + monthly-spend cap-grep (a18 L-10 / L-14) ──────────────────────────
@test "landed-by-content: a squash-landed repo (content on trunk, count>0) → finished, not owned-wait (a18 L-10)" {
  # rev-list count says 1 ahead, but the branch content is durably on trunk (squash-land). Count-based
  # work_landed reads not-landed → owned-wait forever; content-based reads landed → finished (reapable).
  mksquashland "$D/squash"; reg "$UP" "$LIVE" "$D/squash" sidSq; tx sidSq 9000; solo_team_cfg sidSq; stamp "$UP"
  [ "$(cause "$UP")" = finished ]
}

@test "landed-by-content does NOT mislabel a genuinely-ahead branch (real WIP stays owned-wait)" {
  # a real commit NOT on trunk (different content) → cherry shows '+' + tree-diff non-empty → not landed.
  mkrepo "$D/ahead2"; echo genuinely-new > "$D/ahead2/newfile"; git -C "$D/ahead2" add newfile
  git -C "$D/ahead2" commit -qm real-wip
  reg PANE-A "$LIVE" "$D/ahead2" sidAhead2; tx sidAhead2 9000; solo_team_cfg sidAhead2
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
  [ "$c" != finished ]
}

@test "rate-limited: a monthly-spend-cap API error classifies rate-limited, not finished (a18 L-14)" {
  # the real I-LIVE-1 error text — a BILLING-plane cap the old cap-grep missed entirely, so a
  # spend-capped clean+landed session read `finished` (reapable). Must be rate-limited (never-reap).
  mkrepo "$D/capped"; reg PANE-A "$LIVE" "$D/capped" sidCap; tx sidCap 9000; solo_team_cfg sidCap
  printf '{"type":"assistant","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'\''ve hit your monthly spend limit"}]}}\n' >> "$D/proj/slug/sidCap.jsonl"
  [ "$(cause PANE-A)" = rate-limited ]
}

# ── 2026-07-24: operator-interaction hold + fired-peer stamp gating (Danny-Studio-60 / Opus-5) ────
# The incident: two sessions the operator had typed into 12-14 min earlier were reaped as
# finished-teammate / finished — "idle + clean + landed" is every interactive conversation's steady
# state between prompts, so the classifier must read WHO drove the last turn, not only WHEN.
@test "operator hold: a recent REAL prompt holds even a STAMPED landed worker → owned-wait (adoption)" {
  # the Danny-Studio-60 shape: a desk-fired pool worker the operator started conversing with. Fired
  # long ago (stamp 50000s old), landed, idle past threshold — but the operator typed 950s ago.
  mkrepo "$D/adopt"; reg "$UP" "$LIVE" "$D/adopt" sidAd; tx sidAd 900; utx sidAd 950; stamp "$UP" 50000
  c="$(cause "$UP")"
  [ "$c" = owned-wait ]
  [ "$c" != finished ]
}

@test "operator hold expires: a prompt OLDER than the hold no longer holds (stamped worker GC resumes)" {
  mkrepo "$D/old"; reg "$UP" "$LIVE" "$D/old" sidOld; tx sidOld 9000; utx sidOld 30000; solo_team_cfg sidOld; stamp "$UP" 50000
  [ "$(cause "$UP")" = finished ]
}

@test "the fire-time brief is NOT adoption: a prompt within slack of firedAt leaves the worker reapable" {
  # a fired worker's brief arrives as a REAL user prompt at fire time (it2 keystroke injection).
  # firedAt 1000s ago, brief 950s ago (inside the 300s slack) → spawn traffic, not operator adoption.
  mkrepo "$D/brief"; reg "$UP" "$LIVE" "$D/brief" sidBr; tx sidBr 900; utx sidBr 950; solo_team_cfg sidBr; stamp "$UP" 1000
  [ "$(cause "$UP")" = finished ]
}

@test "operator hold protects the UNSTAMPED interactive session (the Opus-5 mid-conversation shape)" {
  # operator-launched (no stamp), landed, idle 675s — the operator asked a question 720s ago. Must be
  # owned-wait via the hold (and could never be `finished` anyway — unstamped ⇒ finished-operator).
  mkrepo "$D/conv"; reg PANE-A "$LIVE" "$D/conv" sidConv; tx sidConv 675; utx sidConv 720; solo_team_cfg sidConv
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
  [ "$c" != finished ]
  [ "$c" != finished-teammate ]
}

@test "meta/auto traffic is NOT adoption: isMeta + Stop-hook feedback do not hold a stamped worker" {
  # auto-drive re-prompts arrive isMeta:true and/or "Stop hook feedback:"-prefixed — both excluded,
  # so a self-driving worker still reads finished (the conversation-hold deadlock guard).
  mkrepo "$D/auto"; reg "$UP" "$LIVE" "$D/auto" sidAuto; tx sidAuto 9000; solo_team_cfg sidAuto; stamp "$UP" 50000
  ts="$(TZ=UTC date -j -f %s "$((NOW-100))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  printf '{"type":"user","isMeta":true,"timestamp":"%s","message":{"role":"user","content":"auto-driven continuation"}}\n' "$ts" >> "$D/proj/slug/sidAuto.jsonl"
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":"Stop hook feedback: continue the loop"}}\n' "$ts" >> "$D/proj/slug/sidAuto.jsonl"
  [ "$(cause "$UP")" = finished ]
}

@test "a tool_result user record is NOT adoption (tool traffic never reads as an operator prompt)" {
  mkrepo "$D/toolt"; reg "$UP" "$LIVE" "$D/toolt" sidTool; tx sidTool 9000; solo_team_cfg sidTool; stamp "$UP" 50000
  ts="$(TZ=UTC date -j -f %s "$((NOW-100))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_z","content":"ok"}]}}\n' "$ts" >> "$D/proj/slug/sidTool.jsonl"
  [ "$(cause "$UP")" = finished ]
}

# ── 2026-07-24 residual fixes (adversarial audit of c063ca0): tenancy binding · tail fallback ·
#    image paste · hold-before-handoff · positive successor link · hold floor ──────────────────────

@test "stale-tenancy stamp: an operator session reusing a previously-fired pane is NOT reapable (rule 2)" {
  # a pane was fired as a worker long ago (firedAt = NOW-50000). That worker closed; the OPERATOR later
  # opened a fresh session in the SAME pane (startedAt = NOW-40000, well past firedAt+BOOT_MAX=+1800).
  # The pane-keyed stamp must NOT brand the current tenant a reapable worker. Pre-fix: file-exists ⇒
  # finished (reapable). Post-fix: tenancy-stale stamp rejected ⇒ finished-operator (surface).
  mkrepo "$D/tenancy"; reg "$UP" "$LIVE" "$D/tenancy" sidT; tx sidT 9000; solo_team_cfg sidT
  local fiso; fiso="$(TZ=UTC date -j -u -f %s "$((NOW-50000))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
  mkdir -p "$D/fired"; printf '{"paneUUID":"%s","cwd":"x","firedBy":"t","firedAt":"%s","selfRetire":true}\n' "$UP" "$fiso" > "$D/fired/$UP.json"
  # current tenant booted 40000s ago — 8200s AFTER firedAt+1800 → tenancy STALE (do NOT auto-patch)
  jq --arg p "$UP" --argjson s "$(( (NOW-40000)*1000 ))" '(.[]|select(.paneUUID==$p)|.startedAt)|=$s' "$D/sessions.json" > "$D/sessions.json.t" && mv "$D/sessions.json.t" "$D/sessions.json"
  c="$(cause "$UP")"
  [ "$c" = finished-operator ]
  [ "$c" != finished ]
}

@test "tail-window fallback: an interactive turn buried BEYOND the tail window still holds (whole-file scan)" {
  # a long transcript: the operator prompt is early, then filler pushes it past a small tail window. The
  # tail scan misses it; the file exceeds the window ⇒ the whole-file fallback finds it → still holds.
  export CC_CLASSIFY_INTERACTIVE_TAIL_BYTES=4096
  mkrepo "$D/bury"; reg PANE-A "$LIVE" "$D/bury" sidBury; solo_team_cfg sidBury
  utx sidBury 950                                    # operator prompt FIRST (recent), then filler
  local pad; pad="$(printf 'x%.0s' $(seq 1 200))"
  local i; for i in $(seq 1 40); do
    printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$pad" >> "$D/proj/slug/sidBury.jsonl"
  done
  [ "$(wc -c < "$D/proj/slug/sidBury.jsonl")" -gt 4096 ]   # guard: the fixture really exceeds the window
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
  [ "$c" != finished-operator ]
}

@test "image-only operator paste holds (interactive with no text) → owned-wait" {
  # an operator pastes ONLY a screenshot (⌘V): content is an array with an image block, no text. Still
  # operator presence → the hold reads it interactive → owned-wait. Pre-fix (text-only): finished-operator.
  mkrepo "$D/img"; reg PANE-A "$LIVE" "$D/img" sidImg; tx sidImg 900; solo_team_cfg sidImg
  local ts; ts="$(TZ=UTC date -j -f %s "$((NOW-950))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  printf '{"type":"user","timestamp":"%s","message":{"role":"user","content":[{"type":"image","source":{"type":"base64","media_type":"image/png","data":"iVBOR"}}]}}\n' "$ts" >> "$D/proj/slug/sidImg.jsonl"
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
  [ "$c" != finished-operator ]
}

@test "hold beats handed-off-lead: a recent operator prompt holds even with a live successor → owned-wait (change 3)" {
  # a lead that fired a /handoff AND has a live successor, but the operator just typed into it → adopted,
  # not spent. Pre-fix (hold after handed-off-lead): handed-off-lead (reapable). Post-fix: owned-wait.
  reg PANE-A "$LIVE" /work sidA 500
  printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"handoff-fire.sh --recycle"}}]}}\n' >> "$D/proj/slug/sidA.jsonl"
  utx sidA 200                                        # operator typed 200s ago (well within hold)
  add "$SUCC" "$LIVE" /work sidB 999999900000         # live successor
  stamp_by "$SUCC" sidA                               # even firedBy-stamped, the hold still wins
  c="$(cause PANE-A)"
  [ "$c" = owned-wait ]
  [ "$c" != handed-off-lead ]
}

@test "unstamped successor ⇒ NO handed-off-lead (operator-driven /handoff surfaces, never auto-reaps) (change 4)" {
  # fired a /handoff with a LIVE successor in the same cwd, but NO cc-fired stamp names sidA as firedBy →
  # the handoff was operator-driven. Must NOT be handed-off-lead; falls through to finished-operator.
  mkrepo "$D/uns"; reg PANE-A "$LIVE" "$D/uns" sidA 500
  {
    printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_ho","name":"Bash","input":{"command":"handoff-fire.sh --recycle"}}]}}\n'
    printf '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_ho","content":"fired"}]}}\n'
  } >> "$D/proj/slug/sidA.jsonl"
  add "$SUCC" "$LIVE" "$D/uns" sidB 999999900000     # live successor, but no firedBy stamp
  c="$(cause PANE-A)"
  [ "$c" != handed-off-lead ]
  [ "$c" = finished-operator ]
}

@test "hold floor: HOLD_S=0 falls back to the 21600 default (+ warns), still holds a recent prompt (rule 5)" {
  export CC_CLASSIFY_INTERACTIVE_HOLD_S=0
  mkrepo "$D/floor"; reg PANE-A "$LIVE" "$D/floor" sidF; tx sidF 900; utx sidF 950; solo_team_cfg sidF
  run bash -c "'$C' PANE-A --json 2>&1 >/dev/null"   # capture stderr only
  echo "$output" | grep -qi 'flooring to 21600'
  [ "$(cause PANE-A)" = owned-wait ]                  # floored hold (21600) holds the 950s prompt
}

@test "hold DISABLE=1 turns the hold OFF (a recent prompt no longer holds a stamped landed worker) (rule 5)" {
  export CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1
  mkrepo "$D/dis"; reg "$UP" "$LIVE" "$D/dis" sidD; tx sidD 900; utx sidD 950; solo_team_cfg sidD; stamp "$UP" 50000
  [ "$(cause "$UP")" = finished ]                     # hold disabled ⇒ the recent prompt does not hold
}

# ── safeguard-blocked (2026-07-25) — the model-content-refusal DOA fixtures. Built with jq (not printf)
#    so the LITERAL refusal text — apostrophes ("can't"), quotes, URLs — round-trips without escaping hell.
#    sgtx mirrors the REAL transcript shape: empty-thinking assistant → system(model_refusal_no_fallback)
#    → isApiErrorMessage assistant carrying the refusal text (the shape captured from pane 725A269A). ──
sgtx() { local sid="$1" ago="$2" model="${3:-Fable 5}"; local ts txt jf="$D/proj/slug/$sid.jsonl"
  ts="$(TZ=UTC date -j -f %s "$((NOW-ago))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).948Z"
  txt="API Error: ${model}'s safeguards flagged this message (https://www.anthropic.com/legal/aup). They may flag safe, normal content as well. Claude Code can't respond to this request with ${model}."
  jq -nc --arg ts "$ts" '{type:"assistant",isSidechain:false,timestamp:$ts,message:{role:"assistant",content:[{type:"thinking",thinking:""}]}}' > "$jf"
  jq -nc '{type:"system",subtype:"model_refusal_no_fallback",content:""}' >> "$jf"
  jq -nc --arg ts "$ts" --arg t "$txt" '{type:"assistant",isApiErrorMessage:true,isSidechain:false,timestamp:$ts,message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$jf"
  jq -nc '{type:"system",subtype:"turn_duration",content:"null"}' >> "$jf"
}
# a refusal that was then RECOVERED: a real user re-prompt + a real assistant answer AFTER the refusal.
sgtx_recovered() { sgtx "$1" "$2" "${3:-Fable 5}"; local ts jf="$D/proj/slug/$1.jsonl"
  ts="$(TZ=UTC date -j -f %s "$((NOW-$2+10))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  jq -nc --arg ts "$ts" '{type:"user",isMeta:false,timestamp:$ts,message:{role:"user",content:"try again please"}}' >> "$jf"
  jq -nc --arg ts "$ts" '{type:"assistant",isSidechain:false,timestamp:$ts,message:{role:"assistant",content:[{type:"text",text:"sure — here is the answer"}]}}' >> "$jf"
}
# a text-only refusal (NO system subtype marker) — proves the CONFIGURABLE text signature alone triggers.
sgtx_textonly() { local sid="$1" ago="$2" txt="$3"; local ts jf="$D/proj/slug/$sid.jsonl"
  ts="$(TZ=UTC date -j -f %s "$((NOW-ago))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  jq -nc --arg ts "$ts" '{type:"user",isMeta:false,timestamp:$ts,message:{role:"user",content:"do the thing"}}' > "$jf"
  jq -nc --arg ts "$ts" --arg t "$txt" '{type:"assistant",isApiErrorMessage:true,isSidechain:false,timestamp:$ts,message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$jf"
}
# a subtype-only refusal (NO matching text) — proves the STRUCTURAL model_refusal_no_fallback signal alone triggers.
sgtx_subtypeonly() { local sid="$1" ago="$2"; local ts jf="$D/proj/slug/$sid.jsonl"
  ts="$(TZ=UTC date -j -f %s "$((NOW-ago))" +%Y-%m-%dT%H:%M:%S 2>/dev/null).000Z"
  jq -nc --arg ts "$ts" '{type:"assistant",isSidechain:false,timestamp:$ts,message:{role:"assistant",content:[{type:"thinking",thinking:""}]}}' > "$jf"
  jq -nc '{type:"system",subtype:"model_refusal_no_fallback",content:""}' >> "$jf"
}

@test "safeguard-blocked — refusal is the terminal event, idle past threshold" {
  reg "$UP" "$LIVE" /repo sidSG; sgtx sidSG 200
  [ "$(cause "$UP")" = safeguard-blocked ]
}

@test "safeguard-blocked — blocked_model + refusal text emitted in JSON" {
  reg "$UP" "$LIVE" /repo sidSG; sgtx sidSG 200 "Fable 5"
  run "$C" "$UP" --json
  [ "$(printf '%s' "$output" | jq -r '.blocked_model')" = "Fable 5" ]
  printf '%s' "$output" | jq -e '.refusal | test("safeguards flagged this message")' >/dev/null
}

@test "safeguard-blocked — idle below threshold stays active (transient churn tolerance)" {
  reg "$UP" "$LIVE" /repo sidSG; sgtx sidSG 30            # < 120s default
  [ "$(cause "$UP")" = active ]
  run "$C" "$UP" --json                                   # and does NOT leak the refusal field
  [ "$(printf '%s' "$output" | jq -r '.refusal')" = null ]
}

@test "no safeguard-blocked — a normal completed turn (no refusal)" {
  mkrepo "$D/n"; reg "$UP" "$LIVE" "$D/n" sidN; tx sidN 500
  [ "$(cause "$UP")" != safeguard-blocked ]
}

@test "no safeguard-blocked — transient churn then RECOVERED (a real turn after the refusal)" {
  reg "$UP" "$LIVE" /repo sidR; sgtx_recovered sidR 500
  [ "$(cause "$UP")" != safeguard-blocked ]
}

@test "safeguard-blocked BEATS finished-teammate — a stamped fired peer in a worktree, blocked on turn 1" {
  # WITHOUT the 2.5 check this reads finished-teammate → the reaper auto-reaps it as if the work was done.
  mkrepo "$D/.worktrees/wt"; reg "$UP" "$LIVE" "$D/.worktrees/wt" sidSG; sgtx sidSG 200; stamp "$UP" 50000
  [ "$(cause "$UP")" = safeguard-blocked ]
}

@test "safeguard-blocked — CONFIGURABLE signature: a custom marker triggers; defaults do NOT match it" {
  reg "$UP" "$LIVE" /repo sidC; sgtx_textonly sidC 200 "A novel refusal WOMBAT no default matches"
  [ "$(cause "$UP")" != safeguard-blocked ]                       # default signatures miss it
  run env CC_CLASSIFY_SAFEGUARD_SIGNATURES="wombat" "$C" "$UP" --json
  [ "$(printf '%s' "$output" | jq -r '.cause')" = safeguard-blocked ]   # case-insensitive custom match
}

@test "safeguard-blocked — STRUCTURAL subtype alone (model_refusal_no_fallback) triggers" {
  reg "$UP" "$LIVE" /repo sidS; sgtx_subtypeonly sidS 200
  [ "$(cause "$UP")" = safeguard-blocked ]
}

# ── G1 (2026-07-25) — the interactive lib must FAIL CLOSED when it cannot be resolved ────────────
# Live, cc-classify runs as ~/.claude/bin/cc-classify (a per-file symlink dir), so $0's dirname IS
# $CLAUDE_CONFIG_DIR/bin and ALL THREE resolve candidates collapse onto ~/.claude/hooks/lib/. A newly
# landed hooks/lib/cc-interactive.sh that the ff-sync never linked therefore misses every candidate at
# once. `nolib_bin` reproduces that EXACTLY (relocated script + bare config dir, no hooks/lib anywhere)
# — the repo layout every other test in this file runs under can never exercise it.
nolib_bin() {                      # → path of a cc-classify with NO resolvable cc-interactive.sh
  mkdir -p "$D/live/.claude/bin"   # bare config dir: no hooks/, no hooks/lib/
  cp "$C" "$D/live/.claude/bin/cc-classify"; chmod +x "$D/live/.claude/bin/cc-classify"
  printf '%s' "$D/live/.claude/bin/cc-classify"
}
nolib_run() { HOME="$D/live" CLAUDE_CONFIG_DIR="$D/live/.claude" "$(nolib_bin)" "$@"; }

@test "G1 lib UNRESOLVABLE ⇒ adoption-unknown ⇒ owned-wait (fail-closed; pre-fix read 'finished')" {
  # the incident fixture verbatim (test 32's shape): stamped 50000s ago, landed, idle 900s, a REAL
  # operator prompt 950s ago. With the lib it is owned-wait. Without it, pre-fix, §4.7 silently never
  # ran and this read `finished` = REAPABLE — a live operator conversation killed by a deploy step.
  mkrepo "$D/nolib"; reg "$UP" "$LIVE" "$D/nolib" sidNL; tx sidNL 900; utx sidNL 950; stamp "$UP" 50000
  c="$(nolib_run "$UP" --json 2>/dev/null | jq -r '.cause')"
  [ "$c" = owned-wait ]
  [ "$c" != finished ]
  nolib_run "$UP" --json 2>/dev/null | jq -e '.detail | test("adoption-unknown, fail-closed")' >/dev/null
}

@test "G1 lib unresolvable warns ONCE on stderr (damped per invocation), stdout JSON stays clean" {
  mkrepo "$D/nolibw"; reg "$UP" "$LIVE" "$D/nolibw" sidW1; tx sidW1 900; utx sidW1 950; stamp "$UP" 50000
  add "$SUCC" "$LIVE" "$D/nolibw" sidW2 0; tx sidW2 900                 # a 2nd idle session in --all
  b="$(nolib_bin)"
  run bash -c "HOME='$D/live' CLAUDE_CONFIG_DIR='$D/live/.claude' '$b' --all --json 2>&1 >/dev/null"
  [ "$(printf '%s\n' "$output" | grep -c 'cc-interactive.sh unresolvable')" -eq 1 ]   # damped: 1, not 2
  [[ "$output" == *"fail-closed"* ]] || false
  [[ "$output" == *"./install.sh"* ]] || false                           # the remediation is handed over
  # stdout alone is still parseable JSON, and BOTH panes fell closed to owned-wait
  run bash -c "HOME='$D/live' CLAUDE_CONFIG_DIR='$D/live/.claude' '$b' --all --json 2>/dev/null"
  [ "$(printf '%s' "$output" | jq -r '[.[].cause] | unique | join(",")')" = owned-wait ]
}

@test "G1 lib PRESENT ⇒ behavior unchanged (both directions pinned: repo layout still classifies finished)" {
  # the same fixture WITHOUT the operator prompt: with the lib resolvable the hold correctly does NOT
  # engage, so a stamped+landed+idle worker is still `finished`. This is the guard that the fail-closed
  # leg above narrows ONLY the unresolvable case and never widens/blocks normal GC.
  mkrepo "$D/withlib"; reg "$UP" "$LIVE" "$D/withlib" sidWL; tx sidWL 900; solo_team_cfg sidWL; stamp "$UP" 50000
  [ "$(cause "$UP")" = finished ]
  run bash -c "'$C' '$UP' --json 2>&1 >/dev/null"
  [[ "$output" != *"unresolvable"* ]]                                    # and no warning is emitted
}

# ── G9 (2026-07-25) — a LIVE hold-disable is loud + leaves an IDL record ─────────────────────────
# CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1 removes the §4.7 operator-adoption hold entirely (the hold
# FLOOR deliberately exempts it), so set outside tests it reproduces the pre-2026-07-24 reaper with no
# trace anywhere. It stays honored — but it can no longer be silent.

@test "G9 hold DISABLE=1 outside bats ⇒ loud stderr + exactly one IDL record (behavior unchanged)" {
  mkrepo "$D/g9"; reg "$UP" "$LIVE" "$D/g9" sidG9; tx sidG9 900; utx sidG9 950; solo_team_cfg sidG9; stamp "$UP" 50000
  export CC_IDL="$D/idl.jsonl"
  # BATS_TEST_FILENAME emptied = "not running under bats" as the script sees it
  run bash -c "BATS_TEST_FILENAME= CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1 CC_IDL='$D/idl.jsonl' '$C' '$UP' --json 2>&1 >/dev/null"
  [[ "$output" == *"INTERACTIVE_HOLD_DISABLE=1 outside tests"* ]] || false
  [[ "$output" == *"REAPABLE"* ]] || false
  [ "$(grep -c . "$D/idl.jsonl")" -eq 1 ]                       # exactly ONE record per invocation
  run jq -e '.hook=="cc-classify" and .disposition=="warned" and .reason=="interactive-hold-disabled" and .target==$t' --arg t "$UP" "$D/idl.jsonl"
  [ "$status" -eq 0 ]
  # BEHAVIOR UNCHANGED: the disable still disables — this fixture is still classified finished.
  c="$(BATS_TEST_FILENAME= CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1 CC_IDL="$D/idl.jsonl" "$C" "$UP" --json 2>/dev/null | jq -r '.cause')"
  [ "$c" = finished ]
}

@test "G9 hold DISABLE=1 UNDER bats ⇒ silent, no IDL record (the suite is not self-alarming)" {
  mkrepo "$D/g9b"; reg "$UP" "$LIVE" "$D/g9b" sidG9b; tx sidG9b 900; utx sidG9b 950; solo_team_cfg sidG9b; stamp "$UP" 50000
  export CC_IDL="$D/idlb.jsonl" CC_CLASSIFY_INTERACTIVE_HOLD_DISABLE=1
  run bash -c "'$C' '$UP' --json 2>&1 >/dev/null"               # BATS_TEST_FILENAME is set + inherited
  [ -z "$output" ]
  [ ! -e "$D/idlb.jsonl" ]
  [ "$(cause "$UP")" = finished ]
}

@test "G9 hold ENABLED (the normal case) ⇒ no warning, no IDL record at all" {
  mkrepo "$D/g9c"; reg "$UP" "$LIVE" "$D/g9c" sidG9c; tx sidG9c 900; solo_team_cfg sidG9c; stamp "$UP" 50000
  export CC_IDL="$D/idlc.jsonl"
  run bash -c "BATS_TEST_FILENAME= CC_IDL='$D/idlc.jsonl' '$C' '$UP' --json 2>&1 >/dev/null"
  [ -z "$output" ]
  [ ! -e "$D/idlc.jsonl" ]
}
