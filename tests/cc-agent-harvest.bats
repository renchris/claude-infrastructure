#!/usr/bin/env bats
# cc-agent-harvest — recovering a team member's deliverable from its OWN transcript.
#
# WHAT THIS EXISTS TO PIN. Passing `name:` to the Agent tool registers a TEAM MEMBER, not a
# fire-and-forget subagent: the member's deliverable channel is SendMessage, and there is NO
# Agent-tool return value for that spawn shape. Measured 2026-08-09 — three Fable 5 derivation
# panelists completed three full reports, signalled idle, and handed the lead nothing. The work
# survived only because someone read their transcripts by hand.
#
# THE PROPERTY THAT IS NOT "does it work" — and is the reason this suite exists at all:
#
#   ATTRIBUTION. The join key from member -> transcript is the member's brief. The first
#   implementation keyed on the brief's first 300 chars, and that shipped a FALSE JOIN on its
#   first live run: sibling briefs from one panel share a boilerplate head, and two of the three
#   were byte-identical until char 320. Newest-first scan order handed one member the OTHER
#   member's transcript, and the tool reported HARVESTED with exit 0.
#
#   A harvester that mis-attributes is WORSE than one that harvests nothing: it manufactures a
#   confident wrong provenance in a workflow whose whole premise is that nobody is checking.
#   So the fixture below is deliberately the shape that broke it — two members whose briefs are
#   identical for far longer than any prefix key would sample, diverging only at the end. Test 1
#   is RED against the pre-fix prefix key and GREEN against the full-prompt key; it is a
#   regression pin, not a smoke test.
#
# Hermetic: a scratch CLAUDE_CONFIG_DIR with a hand-built team config and hand-built transcripts.
# Nothing reads the live fleet, so the suite cannot pass by accidentally finding real sessions.

setup() {
  REPO="${BATS_TEST_DIRNAME}/.."
  HARVEST="${REPO}/bin/cc-agent-harvest"
  # $HOME must be fixtured, not just CLAUDE_CONFIG_DIR: the subject's config_dirs() deliberately
  # scans EVERY ~/.claude* store, because a member can live in a different account's store than
  # its lead. That breadth is correct in production and fatal in a test — unfixtured, the suite
  # scans the operator's live fleet, so a green run would be partly a statement about whichever
  # teams happen to exist on the box today. Caught by the land gate's hermeticity ratchet.
  export HOME="${BATS_TEST_TMPDIR}/home"; mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="${BATS_TEST_TMPDIR}/cfg"
  PROJ="${CLAUDE_CONFIG_DIR}/projects/-scratch"
  TEAM="${CLAUDE_CONFIG_DIR}/teams/session-deadbeef"
  mkdir -p "$PROJ" "$TEAM"

  # The shared head is long on purpose: any prefix-based key samples only this region.
  HEAD="READ-ONLY. Do not write, edit, or create any file. Do not commit. Your deliverable is your final text. THE BOX: a fixed 10-core, 64 GB machine running a large autonomous fleet of terminal agent sessions plus everything those sessions spawn. THE TARGET: scale the fleet by an order of magnitude on the same hardware without new hardware."
  P_ALPHA="${HEAD} YOUR AXIS: kernel-managed finite tables."
  P_BETA="${HEAD} YOUR AXIS: userspace and IPC saturation."

  cat > "${TEAM}/config.json" <<EOF
{"name":"session-deadbeef","leadAgentId":"team-lead@session-deadbeef",
 "leadSessionId":"deadbeef-0000-0000-0000-000000000000",
 "members":[
  {"agentId":"team-lead@session-deadbeef","name":"team-lead","agentType":"team-lead"},
  {"agentId":"alpha@session-deadbeef","name":"alpha","agentType":"frontier-derivation",
   "model":"fable","backendType":"iterm2","prompt":$(printf '%s' "$P_ALPHA" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')},
  {"agentId":"beta@session-deadbeef","name":"beta","agentType":"frontier-derivation",
   "model":"fable","backendType":"iterm2","prompt":$(printf '%s' "$P_BETA" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')}
 ]}
EOF

  # Distinctive, unmistakable payloads, each >= the 200-char substantive floor.
  ALPHA_OUT="ALPHA-PAYLOAD-KERNEL $(printf 'k%.0s' $(seq 1 300))"
  BETA_OUT="BETA-PAYLOAD-USERSPACE $(printf 'u%.0s' $(seq 1 300))"

  _mk_transcript() {  # <file> <prompt> <final-output>
    python3 - "$1" "$2" "$3" <<'PY'
import json,sys
path,prompt,out=sys.argv[1],sys.argv[2],sys.argv[3]
rows=[
 {"type":"user","timestamp":"2026-08-09T21:00:00.000Z",
  "message":{"role":"user","content":f'<teammate-message teammate_id="team-lead">\n{prompt}\n</teammate-message>'}},
 {"type":"assistant","timestamp":"2026-08-09T21:01:00.000Z",
  "message":{"role":"assistant","model":"claude-fable-5",
             "content":[{"type":"text","text":"I'll start by building the model."}]}},
 {"type":"assistant","timestamp":"2026-08-09T21:05:00.000Z",
  "message":{"role":"assistant","model":"claude-fable-5",
             "content":[{"type":"text","text":out}]}},
]
with open(path,"w") as fh:
    for r in rows: fh.write(json.dumps(r)+"\n")
PY
  }

  # beta's transcript is written SECOND so it is the newer file — the pre-fix code scanned
  # newest-first, which is exactly how alpha ended up claiming beta's transcript.
  _mk_transcript "${PROJ}/aaaa1111-0000-0000-0000-000000000001.jsonl" "$P_ALPHA" "$ALPHA_OUT"
  sleep 1
  _mk_transcript "${PROJ}/bbbb2222-0000-0000-0000-000000000002.jsonl" "$P_BETA" "$BETA_OUT"

  OUT="${BATS_TEST_TMPDIR}/out"
}

@test "attribution: each member harvests its OWN transcript despite a long shared brief prefix" {
  run "$HARVEST" --team session-deadbeef --out "$OUT"
  [ "$status" -eq 0 ]

  # The regression pin. Under the pre-fix 300-char prefix key both members matched beta's
  # (newer) transcript, so alpha.md carried BETA-PAYLOAD and this assertion failed.
  grep -q 'ALPHA-PAYLOAD-KERNEL'    "${OUT}/alpha.md"
  grep -q 'BETA-PAYLOAD-USERSPACE'  "${OUT}/beta.md"

  # And the converse, which is the half that actually catches a swap: neither file may carry
  # the other's payload. Asserting only "mine is present" passes vacuously if both are.
  ! grep -q 'BETA-PAYLOAD'  "${OUT}/alpha.md" || false
  ! grep -q 'ALPHA-PAYLOAD' "${OUT}/beta.md"
}

@test "provenance: the harvest names the transcript it came from" {
  run "$HARVEST" --team session-deadbeef --out "$OUT"
  [ "$status" -eq 0 ]
  grep -q 'aaaa1111-0000-0000-0000-000000000001' "${OUT}/alpha.md"
  grep -q 'bbbb2222-0000-0000-0000-000000000002' "${OUT}/beta.md"
}

@test "the lead is never harvested as a member" {
  run "$HARVEST" --team session-deadbeef --out "$OUT"
  [ "$status" -eq 0 ]
  [ ! -f "${OUT}/team-lead.md" ]
  ! echo "$output" | grep -q 'team-lead'
}

@test "loss verdict: a member with no locatable transcript exits 3, not 0" {
  # Delete alpha's transcript: its work is now unrecoverable, which must be LOUD.
  rm -f "${PROJ}/aaaa1111-0000-0000-0000-000000000001.jsonl"
  run "$HARVEST" --team session-deadbeef --out "$OUT"
  [ "$status" -eq 3 ]
  echo "$output" | grep -q 'NO-TRANSCRIPT'
  # beta is unaffected — one member's loss must not suppress another's recovery.
  grep -q 'BETA-PAYLOAD-USERSPACE' "${OUT}/beta.md"
}

@test "a member that produced only narration reports NO-OUTPUT and does not inflate the loss verdict" {
  python3 - "${PROJ}/aaaa1111-0000-0000-0000-000000000001.jsonl" "$P_ALPHA" <<'PY'
import json,sys
path,prompt=sys.argv[1],sys.argv[2]
rows=[
 {"type":"user","timestamp":"2026-08-09T21:00:00.000Z",
  "message":{"role":"user","content":f'<teammate-message teammate_id="team-lead">\n{prompt}\n</teammate-message>'}},
 {"type":"assistant","timestamp":"2026-08-09T21:01:00.000Z",
  "message":{"role":"assistant","content":[{"type":"text","text":"Working on it."}]}},
]
with open(path,"w") as fh:
    for r in rows: fh.write(json.dumps(r)+"\n")
PY
  run "$HARVEST" --team session-deadbeef --out "$OUT"
  # NO-OUTPUT is a real answer ("it never got going"), not a harvest failure. Conflating the two
  # would make the loss verdict fire on every panel that had one slow member, and an alarm that
  # always fires carries no bits (memory: alarm-polarity-and-attention-budget).
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'NO-OUTPUT'
}

@test "--dry-run reports without writing" {
  run "$HARVEST" --team session-deadbeef --out "$OUT" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'HARVESTED'
  [ ! -d "$OUT" ]
}

@test "--json emits the verdict and every member row" {
  run "$HARVEST" --team session-deadbeef --out "$OUT" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d=json.load(sys.stdin)
assert d["verdict"]==0, d["verdict"]
names={m["name"] for m in d["members"]}
assert names=={"alpha","beta"}, names
assert all(m["status"]=="HARVESTED" for m in d["members"]), d["members"]
assert all(m["session"] for m in d["members"]), "session id must be recorded per member"
'
}

@test "no team found exits 2, and does not fall back to some other team" {
  export CLAUDE_CONFIG_DIR="${BATS_TEST_TMPDIR}/empty"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  run "$HARVEST" --team session-nosuchteam --out "$OUT"
  [ "$status" -eq 2 ]
}
