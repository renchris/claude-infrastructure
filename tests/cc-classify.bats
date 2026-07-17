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
  add PANE-B "$LIVE" /work sidB 999999900   # successor: same cwd, alive pid, newer
  [ "$(cause PANE-A)" = handed-off-lead ]
}

@test "handed-off-lead REFUSED when the successor is DEAD (no live successor → never this cause)" {
  reg PANE-A "$LIVE" /work sidA 500
  printf '{"type":"assistant","isSidechain":false,"timestamp":"2001-09-08T00:00:00.000Z","message":{"role":"assistant","content":[{"type":"tool_use","name":"Bash","input":{"command":"handoff-fire.sh --recycle"}}]}}\n' >> "$D/proj/slug/sidA.jsonl"
  add PANE-B "$DEAD" /work sidB 999999900   # a DEAD 'successor' is no successor
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
