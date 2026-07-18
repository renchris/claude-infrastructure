#!/usr/bin/env bats
# lr-audit team-awareness + reset-poller teammate-skip — RED-proofed against the
# 2026-07-18 incident shape (team session-44f5331d): "failed" teammates with
# deliverables on disk must classify COMPLETE_UNDELIVERED (zero re-spend), dead
# ones without deliverables must respawn from VERBATIM salvage briefs, and the
# reset poller must never bare-`--resume` an assignee session (lead-owned recovery).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  AUDIT="$REPO/scripts/limit-recover/lr-audit.py"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  LEAD_SID="11111111-2222-3333-4444-555555555555"
  FIX="$BATS_TEST_TMPDIR/fix"
}

build_team_fixture() {
  python3 - "$FIX" "$LEAD_SID" <<'PY'
import json, os, re, sys
from datetime import datetime, timedelta, timezone

fix, lead_sid = sys.argv[1], sys.argv[2]
cfg = os.path.join(fix, "cfg")
cwd = os.path.join(fix, "repo")
out = os.path.join(fix, "out")
for d in (cfg, cwd, out):
    os.makedirs(d, exist_ok=True)
slug = re.sub(r"[^A-Za-z0-9]", "-", cwd)
proj = os.path.join(cfg, "projects", slug)
os.makedirs(proj, exist_ok=True)

now = datetime.now(timezone.utc)
t30 = (now - timedelta(minutes=30)).isoformat().replace("+00:00", "Z")
joined_ms = int((now - timedelta(hours=1)).timestamp() * 1000)

def rec(name, obj):
    obj.setdefault("teamName", "t1")
    obj.setdefault("agentName", name)
    obj.setdefault("timestamp", t30)
    return obj

def brief_rec(name, prompt):
    return rec(name, {"type": "user",
                      "message": {"role": "user", "content": prompt}})

def tool_pair(name, i):
    return [
        rec(name, {"type": "assistant",
                   "message": {"role": "assistant", "model": "claude-opus-4-8",
                               "stop_reason": "tool_use",
                               "content": [{"type": "tool_use", "id": f"tu{i}",
                                            "name": "Bash", "input": {}}]}}),
        rec(name, {"type": "user",
                   "message": {"role": "user",
                               "content": [{"type": "tool_result",
                                            "tool_use_id": f"tu{i}",
                                            "content": "ok"}]}}),
    ]

def api_error(name):
    return rec(name, {"type": "assistant", "isApiErrorMessage": True,
                      "error": "rate_limit", "apiErrorStatus": 429,
                      "message": {"role": "assistant",
                                  "content": [{"type": "text",
                                               "text": "You've hit your monthly spend limit · raise it at claude.ai/settings/usage"}]}})

def end_turn(name, text):
    return rec(name, {"type": "assistant",
                      "message": {"role": "assistant", "model": "claude-opus-4-8",
                                  "stop_reason": "end_turn",
                                  "content": [{"type": "text", "text": text}]}})

def write_tx(sid, records):
    with open(os.path.join(proj, sid + ".jsonl"), "w") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")

members, transcripts = [], {}

def member(name, sid=None, report=False, recs=None):
    prompt = f"Do the work. Write the FULL report to {out}/{name}.md via heredoc."
    members.append({"agentId": f"{name}@t1", "name": name, "agentType": "deep-research",
                    "model": "opus", "cwd": cwd, "tmuxPaneId": "PANE-" + name,
                    "joinedAt": joined_ms, "isActive": True, "subscriptions": [],
                    "prompt": prompt, "backendType": "iterm2"})
    if report:
        with open(os.path.join(out, f"{name}.md"), "w") as f:
            f.write("# report\nfindings\n")
    if sid and recs is not None:
        write_tx(sid, recs)

# dead WITH deliverable -> COMPLETE_UNDELIVERED (the a19 shape)
n = "m-undelivered"
member(n, sid="aaaa0001-0000-0000-0000-000000000001", report=True,
       recs=[brief_rec(n, f"Write the FULL report to {out}/{n}.md")]
            + tool_pair(n, 1) + tool_pair(n, 2) + tool_pair(n, 3)
            + [api_error(n), rec(n, {"type": "system", "subtype": "turn_duration"})])

# dead WITHOUT deliverable -> PARTIAL (respawn from salvage)
n = "m-partial"
member(n, sid="aaaa0002-0000-0000-0000-000000000002", report=False,
       recs=[brief_rec(n, f"Write the FULL report to {out}/{n}.md")]
            + sum((tool_pair(n, i) for i in range(1, 6)), [])
            + [api_error(n), rec(n, {"type": "system", "subtype": "turn_duration"})])

# clean finisher -> COMPLETE
n = "m-clean"
member(n, sid="aaaa0003-0000-0000-0000-000000000003", report=True,
       recs=[brief_rec(n, f"Write the FULL report to {out}/{n}.md")]
            + sum((tool_pair(n, i) for i in range(1, 4)), [])
            + [end_turn(n, "DONE — report written.")])

# killed at spawn -> NULL
n = "m-null"
member(n, sid="aaaa0004-0000-0000-0000-000000000004", report=False,
       recs=[brief_rec(n, f"Write the FULL report to {out}/{n}.md"), api_error(n)])

# registered, no transcript -> UNVERIFIABLE
member("m-missing")

team_dir = os.path.join(cfg, "teams", "t1")
os.makedirs(team_dir, exist_ok=True)
config = {"name": "t1", "createdAt": joined_ms, "leadAgentId": "team-lead@t1",
          "leadSessionId": lead_sid,
          "members": [{"agentId": "team-lead@t1", "name": "team-lead",
                       "agentType": "team-lead", "joinedAt": joined_ms,
                       "tmuxPaneId": "leader", "cwd": cwd, "subscriptions": [],
                       "backendType": "in-process"}] + members}
with open(os.path.join(team_dir, "config.json"), "w") as f:
    json.dump(config, f)

# minimal lead transcript (no agentName anywhere near the head)
with open(os.path.join(proj, lead_sid + ".jsonl"), "w") as f:
    f.write(json.dumps({"type": "user", "cwd": cwd, "timestamp": t30,
                        "message": {"role": "user", "content": "lead work"}}) + "\n")
    f.write(json.dumps({"type": "assistant", "timestamp": t30,
                        "message": {"role": "assistant", "model": "claude-opus-4-8",
                                    "stop_reason": "end_turn",
                                    "content": [{"type": "text", "text": "ok"}]}}) + "\n")
PY
}

@test "team audit: incident-shape verdicts + exit code (deliverable-on-disk outranks lead-side 'failed')" {
  build_team_fixture
  run python3 "$AUDIT" --config-dir "$FIX/cfg" --session "$LEAD_SID" --cwd "$FIX/repo" \
    --json "$BATS_TEST_TMPDIR/audit.json" --salvage-dir "$BATS_TEST_TMPDIR/salvage" --quiet
  [ "$status" -eq 1 ]   # hard gaps: PARTIAL + NULL + UNVERIFIABLE
  python3 - "$BATS_TEST_TMPDIR/audit.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
led = d["teams"]["led"]
assert len(led) == 1 and led[0]["name"] == "t1", led
v = {m["name"]: m["verdict"] for m in led[0]["members"]}
assert v == {"m-undelivered": "COMPLETE_UNDELIVERED", "m-partial": "PARTIAL",
             "m-clean": "COMPLETE", "m-null": "NULL",
             "m-missing": "UNVERIFIABLE"}, v
mu = next(m for m in led[0]["members"] if m["name"] == "m-undelivered")
assert mu["limit_events"] and mu["limit_events"][-1]["kind"] == "monthly_spend", mu["limit_events"]
assert mu["limit_events"][-1]["resets_at_utc"] is None  # spend cap: NO reset
assert sum(1 for x in mu["deliverables"] if x["written_during_tenure"]) == 1
units = {g["unit"]: g for g in d["gap_units"]}
assert "READ deliverable" in units["team t1/m-undelivered"]["action"]
assert "VERBATIM" in units["team t1/m-partial"]["action"]
# full briefs must NOT leak into the audit json (salvage-only)
assert "_prompt_full" not in json.dumps(d)
PY
}

@test "team salvage: respawn_call carries the VERBATIM brief + exact Agent() args" {
  build_team_fixture
  run python3 "$AUDIT" --config-dir "$FIX/cfg" --session "$LEAD_SID" --cwd "$FIX/repo" \
    --json "$BATS_TEST_TMPDIR/audit.json" --salvage-dir "$BATS_TEST_TMPDIR/salvage" --quiet
  [ "$status" -eq 1 ]
  python3 - "$BATS_TEST_TMPDIR/salvage/teams/t1/m-partial.json" "$FIX/out" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
rc = s["respawn_call"]
assert rc["name"] == "m-partial" and rc["subagent_type"] == "deep-research"
assert rc["model"] == "opus"
assert rc["prompt"] == f"Do the work. Write the FULL report to {sys.argv[2]}/m-partial.md via heredoc."
assert s["partial_output_seeds"] == []  # nothing written -> no false seeds
PY
}

@test "reset poller: teammate session SKIPped (lead-owned), lead session PARKED" {
  H="$BATS_TEST_TMPDIR/home"
  CWD="$H/repo"; PROJ="$H/.claude-next/projects/p"
  mkdir -p "$CWD" "$PROJ"
  TSID="bbbb0001-0000-0000-0000-000000000001"
  LSID="bbbb0002-0000-0000-0000-000000000002"
  LIMIT_TXT="You've hit your session limit · resets Dec 31 at 11pm (America/Vancouver)"
  TS="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  # teammate: agentName in the head + genuine session-limit tail
  printf '{"type":"user","teamName":"tX","agentName":"tm-1","cwd":"%s","timestamp":"%s","message":{"role":"user","content":"brief"}}\n' "$CWD" "$TS" > "$PROJ/$TSID.jsonl"
  printf '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$TS" "$LIMIT_TXT" >> "$PROJ/$TSID.jsonl"
  # lead: same limit, NO agentName
  printf '{"type":"user","cwd":"%s","timestamp":"%s","message":{"role":"user","content":"lead work"}}\n' "$CWD" "$TS" > "$PROJ/$LSID.jsonl"
  printf '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","timestamp":"%s","message":{"role":"assistant","content":[{"type":"text","text":"%s"}]}}\n' "$TS" "$LIMIT_TXT" >> "$PROJ/$LSID.jsonl"
  HOME="$H" LR_POLLER_AUTOFIRE=0 run "$POLLER" --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$H/.reso/limit-recover/parked/$TSID.json" ]
  [ -f "$H/.reso/limit-recover/teammate-skip/$TSID" ]
  [ -f "$H/.reso/limit-recover/parked/$LSID.json" ]
  grep -q "SKIP  $TSID" "$H/.reso/limit-recover/poller.log"
  [ "$(jq -r .kind "$H/.reso/limit-recover/parked/$LSID.json")" = "session" ]
}
