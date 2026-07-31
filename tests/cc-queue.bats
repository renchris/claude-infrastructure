#!/usr/bin/env bats
# cc-queue — the operator's exception queue (TERMINAL_AGNOSTIC_L3_L4.md P4/T4).
#
# RED-PROOF suite written against the FROZEN CONTRACT, never against the script: every expected value
# below is derived from a contract clause quoted beside the assertion. Reproduce the proof that these
# assertions can FAIL with:  tests/cc-queue-redproof.py
#
# CONTRACT (the clause each test binds to):
#   C1  verbs     (none)=table · --json · --check · --attach ROW|SID · --state S · --group-by K
#                 --account PAT · --cwd PAT · --limit N · --watch [S] · --selftest · --no-color
#   C2  sources   beacon    $CC_PERMPEND_DIR/<sid>.json   {ts,tool_name,tool_input,cwd}   [spine]
#                 telemetry $CC_TELEMETRY_DIR/<sid>.json  {session_id,cwd,config_dir,model,pid,used_pct}
#                 registry  $CC_REGISTRY_DIR/<pane>.json  {session_id,paneUUID,account}
#                 activity  <config_dir>/projects/<cwd with [/.]→->/<sid>.jsonl  (mtime)
#   C3  3-state   dir ABSENT **or** .beacon-alive ABSENT ⇒ INERT, rendered LOUDLY, --check refuses.
#                 dir+heartbeat, no <sid>.json ⇒ the all-clear that CAN be trusted.
#                 <sid>.json present ⇒ a blocked row.
#   C4  fail-safe a beacon whose sid has NO telemetry row STILL renders (marked enrich:none)
#   C5  states    blocked (beacon) | done (pid not a live owner) | working (activity ≤ WORKING_S) | idle
#   C6  activity  TRANSCRIPT mtime, NEVER telemetry ts; unresolvable ⇒ COLD (never "recently active")
#   C7  liveness  pid alive AND its command matches CC_QUEUE_OWNER_PAT (bare kill -0 reads a RECYCLED pid)
#   C8  order     blocked first; within blocked, longest wait first
#   C9  caps      --limit caps NON-blocked states and ANNOUNCES the withheld count; 0 ⇒ no cap;
#                 blocked rows are NEVER capped
#   C10 fleet     one list across ALL config dirs; account label normalised to a bare account name
#   C11 check     exit 0 iff beacon live AND nothing blocked; 2 if INERT; 1 if blocked
#   C12 readonly  never creates/removes/modifies anything under any source dir
#
# Seams used for hermeticity: CC_PERMPEND_DIR CC_TELEMETRY_DIR CC_REGISTRY_DIR CC_QUEUE_NOW
#                             CC_QUEUE_PS CC_QUEUE_WORKING_S CC_QUEUE_OWNER_PAT

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  Q="$REPO/bin/cc-queue"
  TD="$BATS_TEST_TMPDIR"
  export CC_PERMPEND_DIR="$TD/pend" CC_TELEMETRY_DIR="$TD/tel" CC_REGISTRY_DIR="$TD/reg"
  export CC_QUEUE_NOW=1000000 CC_QUEUE_WORKING_S=300
  export CC_QUEUE_PS="echo 4242 claude-session"        # C7: pid 4242 is the only live owner
  mkdir -p "$CC_PERMPEND_DIR" "$CC_TELEMETRY_DIR" "$CC_REGISTRY_DIR" "$TD/cfg/projects/-x-proj"
  : > "$CC_PERMPEND_DIR/.beacon-alive"                 # C3: hook has run
}

# ── assertion helpers ────────────────────────────────────────────────────────────────────────────
# NOT `[[ ... ]]`. MEASURED on bats 1.13.0 with this bash: a NON-FINAL failing `[[ ]]` does NOT fail
# the test (a non-final `[ ]` does). Every multi-assertion test written with `[[ ]]` was therefore
# checking only its LAST line — a silent vacuous pass, and this repo's recorded failure mode. Found
# by tests/cc-queue-redproof.py: a mutation deleting the cap notice left the suite fully green.
# A helper FUNCTION is a simple command, so errexit fails the test at the failing line.
has()   { case "$2" in *"$1"*) return 0 ;; *) printf 'expected to find: %s\n' "$1" >&2; return 1 ;; esac; }
hasnt() { case "$2" in *"$1"*) printf 'expected NOT to find: %s\n' "$1" >&2; return 1 ;; *) return 0 ;; esac; }

# helpers — build the exact on-disk shapes C2 freezes
beacon() { # $1=sid $2=since $3=tool $4=json tool_input
  printf '{"ts":%s,"tool_name":"%s","tool_input":%s,"cwd":"/x/proj"}' "$2" "$3" "$4" > "$CC_PERMPEND_DIR/$1.json"
}
telem() { # $1=sid $2=pid [$3=model]
  printf '{"ts":999000,"session_id":"%s","cwd":"/x/proj","config_dir":"%s/cfg","model":"%s","pid":%s,"used_pct":11}' \
    "$1" "$TD" "${3:-claude-opus-5}" "$2" > "$CC_TELEMETRY_DIR/$1.json"
}
touch_transcript() { # $1=sid $2=epoch mtime
  local f="$TD/cfg/projects/-x-proj/$1.jsonl"; : > "$f"
  touch -t "$(date -r "$2" +%Y%m%d%H%M.%S)" "$f"
}

# ── C3 — the three-state world (the load-bearing property) ───────────────────────────────────────

@test "C3: an ABSENT beacon dir renders INERT, never a false all-clear" {
  rm -rf "$CC_PERMPEND_DIR"
  run "$Q" --no-color
  has "BEACON INERT" "$output"
  hasnt "nothing blocked" "$output"
}

@test "C3: dir present but heartbeat MISSING is still INERT" {
  # Any actor can mkdir a path; only the heartbeat proves the HOOK ran. Without this clause the
  # existence evidence degrades to "does a directory exist", which an accident satisfies.
  rm -f "$CC_PERMPEND_DIR/.beacon-alive"
  run "$Q" --no-color
  has "BEACON INERT" "$output"
}

@test "C3: heartbeat present + no beacons ⇒ the all-clear that CAN be trusted" {
  run "$Q" --no-color
  has "nothing blocked" "$output"
  hasnt "BEACON INERT" "$output"
}

# ── C2/C4 — the blocked row is the product ───────────────────────────────────────────────────────

@test "C2: a blocked row shows the EXACT blocked command, not a paraphrase" {
  beacon sid-b 999700 Bash '{"command":"git push --force origin main"}'
  run "$Q" --no-color
  has "git push --force origin main" "$output"
}

@test "C2: wait duration is rendered from the beacon ts against the frozen clock" {
  beacon sid-b 999700 Bash '{"command":"rm -rf /x"}'   # 1000000-999700 = 300s ⇒ 5m00s
  run "$Q" --no-color
  has "5m00s" "$output"
}

@test "C2: a Write beacon renders its file_path (per-tool detail, not a blob)" {
  beacon sid-w 999900 Write '{"file_path":"/etc/hosts","content":"x"}'
  run "$Q" --no-color
  has "/etc/hosts" "$output"
}

@test "C4: a beacon with NO telemetry row still renders, marked enrich:none" {
  beacon sid-orphan 999900 Bash '{"command":"whoami"}'
  run "$Q" --no-color
  has "whoami" "$output"
  has "enrich:none" "$output"
}

# ── C5/C6/C7 — classification ────────────────────────────────────────────────────────────────────

@test "C5+C6: alive pid + WARM transcript ⇒ working" {
  telem sid-w 4242; touch_transcript sid-w 999950     # 50s old ≤ 300
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[]|select(.sid=="sid-w").state')" = working ]
}

@test "C5+C6: alive pid + COLD transcript ⇒ idle" {
  telem sid-i 4242; touch_transcript sid-i 900000     # 100000s old > 300
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[]|select(.sid=="sid-i").state')" = idle ]
}

@test "C6: an UNRESOLVABLE transcript is COLD, never counted as recent activity" {
  telem sid-nt 4242                                    # no transcript file at all
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[]|select(.sid=="sid-nt").state')" = idle ]
}

@test "C6: a FRESH telemetry ts does NOT make a cold session look working" {
  # The telemetry writer is the statusline; it goes stale on healthy sessions and fresh on ones doing
  # nothing. Binding activity to it was measured wrong (3.5-day-stale telemetry, 5-min-warm transcript).
  telem sid-fresh 4242                                 # tel ts=999000 (1000s old), no transcript
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[]|select(.sid=="sid-fresh").state')" = idle ]
}

@test "C7: a pid that is NOT a live claude owner ⇒ done" {
  telem sid-d 999999; touch_transcript sid-d 999990    # transcript warm, but pid is not an owner
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[]|select(.sid=="sid-d").state')" = done ]
}

@test "C7: liveness requires the COMMAND to match, not merely a live pid" {
  export CC_QUEUE_PS="echo 4242 some-unrelated-process"   # pid alive, but not a claude session
  telem sid-r 4242; touch_transcript sid-r 999990
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[]|select(.sid=="sid-r").state')" = done ]
}

# ── C8 — ordering: the exception queue is what the operator sees first ───────────────────────────

@test "C8: blocked sorts first even when working rows exist" {
  telem sid-w 4242; touch_transcript sid-w 999990
  beacon sid-b 999700 Bash '{"command":"sudo rm"}'
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[0].state')" = blocked ]
}

@test "C8: within blocked, the LONGEST wait is first (the 6.6-minute case surfaces above a fresh one)" {
  beacon sid-new 999980 Bash '{"command":"fresh"}'     # 20s
  beacon sid-old 999600 Bash '{"command":"stale"}'     # 400s
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[0].sid')" = sid-old ]
}

# ── C9 — no silent caps ──────────────────────────────────────────────────────────────────────────

@test "C9: --limit caps non-blocked rows and ANNOUNCES the withheld count" {
  for i in 1 2 3; do telem "sid-i$i" 4242; done        # 3 idle
  run "$Q" --no-color --state idle --limit 1
  has "more not shown" "$output"
  [ "$(echo "$output" | grep -c '^  *[0-9]')" -eq 1 ]
}

@test "C9: --limit 0 renders every row" {
  for i in 1 2 3; do telem "sid-i$i" 4242; done
  run "$Q" --no-color --state idle --limit 0
  [ "$(echo "$output" | grep -c '^  *[0-9]')" -eq 3 ]
}

@test "C9: blocked rows are NEVER capped, even at --limit 1" {
  beacon sid-b1 999900 Bash '{"command":"one"}'
  beacon sid-b2 999800 Bash '{"command":"two"}'
  beacon sid-b3 999700 Bash '{"command":"three"}'
  run "$Q" --no-color --limit 1
  has "one" "$output" && has "two" "$output" && has "three" "$output"
}

# ── C10 — cross-account: the coverage gap this tool exists to close ──────────────────────────────

@test "C10: sessions from DIFFERENT config dirs appear in ONE list" {
  # `claude agents --json` is scoped to one CLAUDE_CONFIG_DIR and saw 3 of 25. The spine is /tmp, and
  # the telemetry row carries config_dir, so a 4-account fleet is one census by construction.
  mkdir -p "$TD/cfgA/projects/-x-proj" "$TD/cfgB/projects/-x-proj"
  printf '{"session_id":"sid-A","cwd":"/x/proj","config_dir":"%s/cfgA","pid":4242,"ts":1}' "$TD" > "$CC_TELEMETRY_DIR/sid-A.json"
  printf '{"session_id":"sid-B","cwd":"/x/proj","config_dir":"%s/cfgB","pid":4242,"ts":1}' "$TD" > "$CC_TELEMETRY_DIR/sid-B.json"
  run "$Q" --json
  [ "$(echo "$output" | jq '[.[]|select(.sid=="sid-A" or .sid=="sid-B")]|length')" -eq 2 ]
}

@test "C10: the account label is normalised across its two spellings" {
  # registry says "claude-tertiary"; a config_dir basename says ".claude-tertiary". One account must
  # not render as two.
  printf '{"session_id":"sid-reg","paneUUID":"P-1","account":"claude-tertiary"}' > "$CC_REGISTRY_DIR/P-1.json"
  printf '{"session_id":"sid-reg","cwd":"/x/proj","config_dir":"/h/.claude-tertiary","pid":4242,"ts":1}' > "$CC_TELEMETRY_DIR/sid-reg.json"
  printf '{"session_id":"sid-cfg","cwd":"/x/proj","config_dir":"/h/.claude-tertiary","pid":4242,"ts":1}' > "$CC_TELEMETRY_DIR/sid-cfg.json"
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[]|select(.sid=="sid-reg").account')" = tertiary ]
  [ "$(echo "$output" | jq -r '.[]|select(.sid=="sid-cfg").account')" = tertiary ]
}

@test "C10: --account filters the fleet down to one shard" {
  printf '{"session_id":"sid-t","cwd":"/x/proj","config_dir":"/h/.claude-tertiary","pid":4242,"ts":1}' > "$CC_TELEMETRY_DIR/sid-t.json"
  printf '{"session_id":"sid-q","cwd":"/x/proj","config_dir":"/h/.claude-quaternary","pid":4242,"ts":1}' > "$CC_TELEMETRY_DIR/sid-q.json"
  run "$Q" --json --account tertiary
  [ "$(echo "$output" | jq 'length')" -eq 1 ]
  [ "$(echo "$output" | jq -r '.[0].sid')" = sid-t ]
}

# ── C11 — --check is a gate, and must never pass vacuously ───────────────────────────────────────

@test "C11: --check exits 0 when the beacon is live and nothing is blocked" {
  run "$Q" --check
  [ "$status" -eq 0 ]
}

@test "C11: --check exits 1 when something is blocked" {
  beacon sid-b 999700 Bash '{"command":"x"}'
  run "$Q" --check
  [ "$status" -eq 1 ]
}

@test "C11: --check exits 2 (never 0) when the beacon is INERT" {
  rm -rf "$CC_PERMPEND_DIR"
  run "$Q" --check
  [ "$status" -eq 2 ]
}

# ── C12 — read-only ──────────────────────────────────────────────────────────────────────────────

@test "C12: a full render mutates NOTHING under any source dir" {
  beacon sid-b 999700 Bash '{"command":"x"}'; telem sid-w 4242; touch_transcript sid-w 999990
  before="$(find "$CC_PERMPEND_DIR" "$CC_TELEMETRY_DIR" "$CC_REGISTRY_DIR" | sort | md5)"
  run "$Q" --no-color
  after="$(find "$CC_PERMPEND_DIR" "$CC_TELEMETRY_DIR" "$CC_REGISTRY_DIR" | sort | md5)"
  [ "$before" = "$after" ]
}

# ── C1 — surface: grouping is how 1000 rows stays readable ───────────────────────────────────────

@test "C1: --group-by collapses the fleet to one line per group with a blocked count" {
  telem sid-1 4242; telem sid-2 4242
  beacon sid-1 999700 Bash '{"command":"x"}'
  run "$Q" --no-color --group-by account
  has "GROUPED BY account" "$output"
}

@test "C1: an unknown option fails loudly rather than rendering a partial list" {
  run "$Q" --bogus
  [ "$status" -eq 2 ]
}

@test "C1: --selftest is self-contained and green" {
  run "$Q" --selftest
  [ "$status" -eq 0 ]
  has "# all" "$output"
}

# ── C1 — --attach: the ONE action, keyed to the row number the operator actually reads ───────────
# A stub `it2` on PATH records what it was asked to focus, so the jump is provable without moving the
# operator's real focus mid-session.
stub_it2() {
  mkdir -p "$TD/binstub"
  printf '#!/bin/sh\nprintf "%%s\\n" "$*" > "%s/it2.args"\n' "$TD" > "$TD/binstub/it2"
  chmod +x "$TD/binstub/it2"
  PATH="$TD/binstub:$PATH"
}

@test "C1: --attach <row> focuses the pane registered for THAT row" {
  # MUST have >1 row, and the target must NOT be the last one — with a single-row fixture "row 1" and
  # "whatever row happens to be last" are indistinguishable, so the row number is not actually being
  # tested. (Found by redproof: a mutation replacing .[$n-1] with .[-1] survived the one-row version.)
  stub_it2
  printf '{"session_id":"sid-b","paneUUID":"PANE-BLOCKED","account":"claude-next"}' > "$CC_REGISTRY_DIR/p1.json"
  printf '{"session_id":"sid-z","paneUUID":"PANE-OTHER","account":"claude-next"}'   > "$CC_REGISTRY_DIR/p3.json"
  beacon sid-b 999700 Bash '{"command":"x"}'
  telem sid-b 4242
  telem sid-z 4242                                  # a second, NON-blocked row sorts after the blocked one
  run "$Q" --attach 1
  [ "$status" -eq 0 ]
  has "session focus PANE-BLOCKED" "$(cat "$TD/it2.args")"
  hasnt "PANE-OTHER" "$(cat "$TD/it2.args")"
}

@test "C1: --attach <sid> resolves by session id, not only by row number" {
  stub_it2
  printf '{"session_id":"sid-x","paneUUID":"PANE-X","account":"claude-next"}' > "$CC_REGISTRY_DIR/p2.json"
  telem sid-x 4242
  run "$Q" --attach sid-x
  [ "$status" -eq 0 ]
  has "session focus PANE-X" "$(cat "$TD/it2.args")"
}

@test "C1: a row with NO registered pane fails loudly and still names the sid" {
  # A headless agent (T2's driver) has no pane BY DESIGN. Attach must say so and hand back the sid —
  # never silently focus some OTHER row's pane.
  stub_it2
  telem sid-headless 4242
  run "$Q" --attach sid-headless
  [ "$status" -eq 1 ]
  has "sid-headless" "$output"
  [ ! -e "$TD/it2.args" ]
}

# ── malformed input must degrade, never blind the surface ────────────────────────────────────────

@test "a malformed telemetry file does not hide the other rows" {
  telem sid-good 4242; touch_transcript sid-good 999990
  printf 'NOT JSON{{{' > "$CC_TELEMETRY_DIR/broken.json"
  run "$Q" --json
  [ "$(echo "$output" | jq -r '.[]|select(.sid=="sid-good").state')" = working ]
}

@test "a malformed BEACON file does not hide a sibling blocked row" {
  beacon sid-ok 999700 Bash '{"command":"visible"}'
  printf '{{{garbage' > "$CC_PERMPEND_DIR/sid-bad.json"
  run "$Q" --no-color
  has "visible" "$output"
}

@test "C2: a TRUNCATED blocked command is marked as truncated" {
  # An operator deciding whether to approve must never see a silently-cut prefix that reads like the
  # whole command. (Live 2026-07-31: a real blocked heredoc cut mid-string with no indication.)
  long=$(printf 'x%.0s' $(seq 1 200))
  beacon sid-long 999900 Bash "{\"command\":\"$long\"}"
  run "$Q" --no-color
  has "…" "$output"
}

@test "C2: a SHORT blocked command is NOT marked truncated" {
  beacon sid-short 999900 Bash '{"command":"ls"}'
  run "$Q" --no-color --state blocked
  hasnt "…" "$output"
}
