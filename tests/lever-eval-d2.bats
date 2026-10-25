#!/usr/bin/env bats
# lever-eval-d2 — the d2-lean eval (USAGE_LEVERS § W7+ §2 D2 "Offline d2-lean"; wave S10).
#
# Subjects: tools/lever-evals/d2_lean/build_cases.py (the case pool), grade.py (code facts first,
# then the judge), flow.py (the ABBA driver and the gate arithmetic) through bin/cc-lever-eval. No
# model runs: HOME, the transcript roots, the repos dir and the judge binary are fixtures, the judge
# is a python stub that labels every dossier pass, and the driver runs only --dry-run.
#
# The expected numbers are computed by hand in each test's comment, never read back from flow.py.
# RED-proof (2026-10-25, scratch copies run against these exact fixtures, measured):
#   - shadow_calls() storing kind=slots rows as call rows → the continuation's would_deny=false
#     overwrites the call's: p-a1 drops as shadow-not-would-deny, cases [] (test 1 red);
#   - read_slot() taking the first user record → the short relayed operator request becomes the
#     brief: p-a1 drops (as a probe), cases [] (test 1 red);
#   - launches() ignoring resumeFromRunId → cases [p-a1, p-b1], resume 1 (test 1 red);
#   - grade.py sending every scored answer to the judge → the stub sees 4 dossiers, not 1 (test 2);
#   - WRITE_BASH scanning heredoc bodies (the first smoke's false positive) → c1 forbidden
#     ['/agentsync.lock', '/etc/also-prose'] and not passed (test 2);
#   - _boot() resampling slots instead of runs → CI [-50.0, 0.0] (the cluster test red);
#   - the point ratio used as the requests bound → upper 1.25, PASS (the requests test red);
#   - the launch test is a found bug, not a mutant: the first smoke spliced `--effort high` between
#     `--model` and its value, every lead refused ("unrecognized model --effort"), and the run still
#     exited 0. On that code the test reads "--effort" as the model and status 0.

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME/.claude/logs"
	export CC_HILLCLIMB_DIR="$BATS_TEST_TMPDIR/hc"
	export CC_LEVER_ROUNDS_LOG="$BATS_TEST_TMPDIR/rounds.jsonl"
	export CC_LEVER_LOG_DIR="$BATS_TEST_TMPDIR/logs"
	export CC_LEVER_EVAL_ROOTS="next3=$BATS_TEST_TMPDIR/r3/projects"
	export CC_D2_DEV_DIR="$BATS_TEST_TMPDIR/dev"
	export CC_D2_FX_ROOT="$BATS_TEST_TMPDIR/fx"
	export CC_D2_RUN_ROOT="$BATS_TEST_TMPDIR/runs"
	mkdir -p "$CC_LEVER_LOG_DIR" "$CC_D2_DEV_DIR"
	REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	CLI="$REPO/bin/cc-lever-eval"
	D2="$REPO/tools/lever-evals/d2_lean"
	load helpers/cc-stub
}

ev() { python3 "$CLI" "$@"; }

# One fixture session with three Workflow runs, written by python so every record is real JSON.
mk_transcripts() {
	python3 - "$BATS_TEST_TMPDIR" <<'PY'
import json, os, sys
T = sys.argv[1]
P = os.path.join(T, "r3/projects/-tmp-d2-fixture")
S = "11111111-2222-3333-4444-555555555555"
cwd = "/tmp/d2-fixture-work"  # no repo: briefs below name no paths
def w(path, rows):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
def tu(i, inp): return {"type": "assistant", "message": {"content": [{"type": "tool_use", "id": i, "name": "Workflow", "input": inp}]}}
def tr(i, run): return {"type": "user", "message": {"content": [{"type": "tool_result", "tool_use_id": i,
                        "content": "Workflow launched. Transcript dir: /x/subagents/workflows/%s" % run}]}}
w(os.path.join(P, S + ".jsonl"), [
    tu("tu1", {"script": "agent('a')"}), tr("tu1", "wf_aaaaaaaa-111"),
    tu("tu2", {"scriptPath": "/x.js", "resumeFromRunId": "wf_aaaaaaaa-111"}), tr("tu2", "wf_bbbbbbbb-222"),
    tu("tu3", {"script": "agent('c')"}), tr("tu3", "wf_cccccccc-333"),
])
REQ = "[Workflow harness — user request] The harness relays the user request:\n  please commit everything when done"
PAD = " Keep each bullet under twenty words, cite the section it comes from, and say plainly when the plan is silent on a point instead of guessing what it means. Return the bullets as plain text with no preamble, no closing summary and no headings."
def task(t): return "[Workflow harness — computed task] frame text. The computed task text follows:\n  \n  " + t
def slot(run, aid, agent_type, brief, relay=True):
    d = os.path.join(P, S, "subagents/workflows", run)
    recs = ([{"type": "user", "cwd": cwd, "timestamp": "2026-10-20T00:00:00Z", "message": {"content": REQ}}] if relay else [])
    recs.append({"type": "user", "cwd": cwd, "timestamp": "2026-10-20T00:00:01Z", "message": {"content": task(brief)}})
    recs.append({"type": "assistant", "message": {"model": "claude-opus-5-5", "content": [{"type": "text", "text": "ok"}]}})
    w(os.path.join(d, "agent-%s.jsonl" % aid), recs)
    with open(os.path.join(d, "agent-%s.meta.json" % aid), "w") as fh:
        json.dump({"agentType": agent_type}, fh)
for run, slots in (("wf_aaaaaaaa-111", [("a1", "workflow-subagent", "Summarize the plan in three bullets." + PAD),
                                         ("a2", "workflow-lean", "Summarize the notes in three bullets." + PAD),
                                         ("a3", "workflow-subagent", "Make the edit, then commit it." + PAD),
                                         ("a4", "workflow-subagent", "Reply with exactly the string WF_OK and nothing else.")]),
                   ("wf_bbbbbbbb-222", [("b1", "workflow-subagent", "List the open questions." + PAD)]),
                   ("wf_cccccccc-333", [("c1", "workflow-subagent", "Name the riskiest step." + PAD)])):
    for aid, at, b in slots:
        slot(run, aid, at, b)
    w(os.path.join(P, S, "subagents/workflows", run, "journal.jsonl"),
      [{"type": "launched"}] + [{"type": "started", "key": "v2:" + aid, "agentId": aid, "label": "x:" + aid} for aid, _, _ in slots]
      + [{"type": "result", "agentId": aid} for aid, _, _ in slots])
    w(os.path.join(P, S, "workflows", run + ".json"), [{"runId": run, "script": "agent('x')"}])
# shadow: the call row for tu1 says would_deny; a kind=slots continuation for the same call carries
# would_deny=false (a reader that takes it as a call row drops p-a1); tu3's row is a resume
w(os.path.join(T, "home/.claude/logs/workflow-lean-shadow.jsonl"), [
    {"tool_use_id": "tu1", "session_id": S, "would_deny": True, "resume_from_run_id": None},
    {"kind": "slots", "tool_use_id": "tu1", "would_deny": False, "part": 0, "slots": []},
    {"tool_use_id": "tu3", "session_id": S, "would_deny": True, "resume_from_run_id": "wf_zzzzzzzz-999"},
])
PY
}

@test "case builder: one would-deny slot survives; resumes, typed slots, keep-default, probes and kind=slots rows are filtered" {
	mk_transcripts
	run python3 "$D2/build_cases.py" --out "$BATS_TEST_TMPDIR/cases.jsonl" --all --start 0 --end 9999999999
	[ "$status" -eq 0 ]
	# a1 is the case: its brief is the computed task, not the relayed request that says "commit"
	run python3 -c 'import json,sys
c=[json.loads(l) for l in open(sys.argv[1])]
print(json.dumps(sorted(x["case_id"] for x in c if x["src"]=="prod")), sum(1 for x in c if x["src"]=="f2"),
      [x["brief"] for x in c if x["case_id"]=="p-a1"][0][:36], [x["shadow"] for x in c if x["case_id"]=="p-a1"][0]["would_deny"])' "$BATS_TEST_TMPDIR/cases.jsonl"
	[ "$status" -eq 0 ]
	[ "$output" = '["p-a1"] 10 Summarize the plan in three bullets. True' ]
	# b1 (launched with resumeFromRunId) and c1 (its shadow row names a resume) are the 2 resumes
	run python3 -c 'import json,sys; m=json.loads(open(sys.argv[1]).read().splitlines()[-1]); d=m["drops"]
print(d.get("resume"), d.get("has-agent-type"), d.get("keep-default"), d.get("probe"), d.get("shadow-kind:slots"), d.get("shadow-not-would-deny"))' <(python3 "$D2/build_cases.py" --out /dev/null --all --start 0 --end 9999999999)
	[ "$status" -eq 0 ]
	[ "$output" = "2 1 1 1 1 None" ]
}

# grade.py over one position: c1 right, c2 wrong number, c3 right but writes /etc/x, c4 failed in the
# journal, c5 served by another model. The judge stub labels every dossier it receives pass.
mk_graded_run() {
	python3 - "$BATS_TEST_TMPDIR" <<'PY'
import json, os, sys
T = sys.argv[1]
W, R, FX = os.path.join(T, "wf"), os.path.join(T, "run"), os.path.join(T, "fxroot")
for d in (W, R, FX): os.makedirs(d, exist_ok=True)
open(os.path.join(FX, "data.txt"), "w").write("a\nb\nc\n")
def w(path, rows):
    with open(path, "w") as fh:
        for r in rows: fh.write(json.dumps(r) + "\n")
def asst(text, model="claude-opus-5-5", rid="r1", usage=None, tools=()):
    c = [{"type": "tool_use", "id": "t%d" % i, "name": n, "input": inp} for i, (n, inp) in enumerate(tools)]
    c.append({"type": "text", "text": text})
    return {"type": "assistant", "requestId": rid, "message": {"model": model, "content": c, "usage": usage or {"input_tokens": 1}}}
# c1: two records of ONE request (streamed): usage per field is the max → output 200, not 250
w(os.path.join(W, "agent-x1.jsonl"), [
    asst("", usage={"input_tokens": 10, "cache_creation_input_tokens": 1000, "cache_read_input_tokens": 100000, "output_tokens": 50}),
    asst("There are 3 lines, per workflow-lean.", usage={"input_tokens": 10, "cache_creation_input_tokens": 1000, "cache_read_input_tokens": 100000, "output_tokens": 200},
         tools=[("Bash", {"command": "mkdir -p %s/out/c1 && cat > %s/out/c1/answer.md <<'EOF'\nThe lock lives at -> /agentsync.lock\necho x > /etc/also-prose\nEOF" % (T, T)})])])
w(os.path.join(W, "agent-x2.jsonl"), [asst("There are 4 lines.")])
w(os.path.join(W, "agent-x3.jsonl"), [asst("There are 3 lines.", tools=[("Write", {"file_path": "/etc/x"})])])
w(os.path.join(W, "agent-x5.jsonl"), [asst("There are 3 lines.", model="claude-sonnet-5-5")])
w(os.path.join(W, "journal.jsonl"), [{"type": "started", "agentId": a, "label": "d2:default:%s:r1" % c}
   for a, c in (("x1", "c1"), ("x2", "c2"), ("x3", "c3"), ("x4", "c4"), ("x5", "c5"))] + [{"type": "failed", "agentId": "x4"}])
cases = [dict(case_id=c, acct="next3", out=os.path.join(T, "out", c), clone=None, fixture_root=FX, allowed_rel=[])
         for c in ("c1", "c2", "c3", "c4", "c5")]
w(os.path.join(R, "positions.jsonl"), [dict(block="b0", pos=0, variant="default", rep=1, sid="s", wf_dir=W, workdir=T, cases=cases)])
key = {c: dict(asks=["Count the lines in data.txt."], facts=[dict(claim="lines", check_cmd="wc -l < data.txt", match="number")])
       for c in ("c1", "c2", "c3", "c4", "c5")}
json.dump(key, open(os.path.join(T, "key.json"), "w"))
# the judge stub: records what it was sent, labels each dossier pass in lever-judge.jsonl
open(os.path.join(T, "judge.py"), "w").write('''import json, os, sys
a = sys.argv; d = [json.loads(l) for l in open(a[a.index("--dossiers") + 1])]
open(os.environ["STUB_SEEN"], "w").write(json.dumps(d))
with open(os.path.join(os.environ["CC_LEVER_LOG_DIR"], "lever-judge.jsonl"), "a") as fh:
    for x in d: fh.write(json.dumps({"kind": "judged", "rubric": "d2_quality", "id": x["id"], "pass": True}) + "\\n")
''')
PY
}

@test "grade.py: code facts first, forbidden writes (never a heredoc's prose) and plumbing statuses, the judge sees only code-passing answers, redacted" {
	mk_graded_run
	export CC_LEVER_JUDGE_BIN="$BATS_TEST_TMPDIR/judge.py" STUB_SEEN="$BATS_TEST_TMPDIR/seen.json"
	run python3 "$D2/grade.py" "$BATS_TEST_TMPDIR/run" --key "$BATS_TEST_TMPDIR/key.json"
	[ "$status" -eq 0 ]
	[[ "$output" == *'"passed": 1'*'"pending": 0'* ]] || false
	run python3 -c 'import json,sys
g={r["case_id"]:r for r in map(json.loads, open(sys.argv[1]))}
s=json.load(open(sys.argv[2]))
print(g["c1"]["passed"], g["c1"]["requests"], g["c1"]["pp"], g["c2"]["passed"], g["c2"]["facts_ok"],
      g["c3"]["passed"], g["c3"]["forbidden"], g["c4"]["status"], g["c5"]["status"], g["c5"]["passed"],
      len(s), s[0]["sections"]["answer"].count("<agent>"), "workflow-lean" in s[0]["sections"]["answer"])' \
		"$BATS_TEST_TMPDIR/run/graded.jsonl" "$BATS_TEST_TMPDIR/seen.json"
	[ "$status" -eq 0 ]
	# c1 pp (mid) = (0.245*(1000+10) + 0.0067*100000 + 0.404*200) / 1e6 = 0.00099825 → 0.000998
	[ "$output" = "True 1 0.000998 False 0 False ['/etc/x'] error served-model None 1 1 False" ]
}

# Gate rows: one per (case, variant), rep 1. accounts: c1 c2 next, c3 c4 next2.
mk_rows() { # $1 = c4's lean pass (true|false), $2 = c1's lean requests
	python3 - "$BATS_TEST_TMPDIR/graded.jsonl" "$1" "$2" <<'PY'
import json, sys
out, c4lean, c1req = sys.argv[1], sys.argv[2] == "true", float(sys.argv[3])
rows = []
for c, acct in (("c1", "next"), ("c2", "next"), ("c3", "next2"), ("c4", "next2")):
    rows.append(dict(case_id=c, acct=acct, variant="default", rep=1, status="ok", passed=True, requests=10, pp_lo=0.01, pp=0.01, pp_hi=0.01))
    lp = c4lean if c == "c4" else True
    rows.append(dict(case_id=c, acct=acct, variant="lean", rep=1, status="ok", passed=lp, requests=c1req if c == "c1" else 10,
                     pp_lo=0.004, pp=0.004, pp_hi=0.004))
with open(out, "w") as fh:
    for r in rows: fh.write(json.dumps(r) + "\n")
PY
}

@test "gate: pass-rate CI lower bound from the stratified case bootstrap (hand-computed −50) fails the −10 floor" {
	# lean fails c4 only: diff = (0+0+0−100)/4 = −25. next2 resamples (c3,c3) / (c3,c4)×2 / (c4,c4) give
	# means 0 / −25 / −50 with p ¼ ½ ¼, so the 2.5th percentile is −50 and the 97.5th is 0.
	mk_rows false 10
	run ev gate d2_lean --graded "$BATS_TEST_TMPDIR/graded.jsonl"
	[ "$status" -eq 0 ]
	[[ "$output" == *"FAIL pass rate: lean 75.0 vs default 100.0, diff -25.00 pts, CI95 [-50.00, +0.00]"* ]] || false
	[[ "$output" == *"PASS requests: lean/default 1.0, one-sided 95% upper 1.0"* ]] || false
	[[ "$output" == *"PASS pp: lean/default 0.4 / 0.4 / 0.4"* ]] || false
	[[ "$output" == *"gate: FAIL — reported, not decided"* ]] || false
	mk_rows true 10
	run ev gate d2_lean --graded "$BATS_TEST_TMPDIR/graded.jsonl"
	[ "$status" -eq 0 ]
	[[ "$output" == *"PASS pass rate: lean 100.0 vs default 100.0, diff +0.00 pts, CI95 [+0.00, +0.00]"* ]] || false
	[[ "$output" == *"gate: PASS — reported, not decided"* ]] || false
}

@test "gate: the requests bound is the one-sided 95th percentile (1.5), so a 1.25 point ratio still fails 1.3" {
	# c1 lean 20 vs 10, others 10/10: point 50/40 = 1.25. next resamples (c1,c1) p¼ → 60/40 = 1.5,
	# (c1,c2) p½ → 1.25, (c2,c2) p¼ → 1.0; the 95th percentile lands on 1.5.
	mk_rows true 20
	run ev gate d2_lean --graded "$BATS_TEST_TMPDIR/graded.jsonl"
	[ "$status" -eq 0 ]
	[[ "$output" == *"FAIL requests: lean/default 1.25, one-sided 95% upper 1.5 (must be <= 1.3)"* ]] || false
	[[ "$output" == *"gate: FAIL"* ]] || false
}

@test "gate: slots of one Workflow run resample together, so a split run gives CI [-25, -25] where slots would give [-50, 0]" {
	# c1 (lean fails) and c2 (lean passes) share run R in account next; c3 c4 (next2) both pass.
	# Resampling the run keeps (c1, c2) together: every draw is (−100 + 0 + 0 + 0)/4 = −25. Resampling
	# slots would draw (c1, c1) a quarter of the time (−50) and (c2, c2) a quarter (0).
	python3 - "$BATS_TEST_TMPDIR/graded.jsonl" <<'PY2'
import json, sys
rows = []
for c, acct, cl, lean in (("c1", "next", "R", False), ("c2", "next", "R", True), ("c3", "next2", None, True), ("c4", "next2", None, True)):
    for v, ok in (("default", True), ("lean", lean)):
        rows.append(dict(case_id=c, acct=acct, cluster=cl, variant=v, rep=1, status="ok", passed=ok, requests=10, pp_lo=0.01, pp=0.01, pp_hi=0.01))
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY2
	run ev gate d2_lean --graded "$BATS_TEST_TMPDIR/graded.jsonl"
	[ "$status" -eq 0 ]
	[[ "$output" == *"diff -25.00 pts, CI95 [-25.00, -25.00]"* ]] || false
}

@test "gate: VOID above 10% plumbing errors, INCOMPLETE while asks wait on the judge" {
	mk_rows true 10
	printf '%s\n' '{"case_id":"c5","acct":"next","variant":"lean","rep":1,"status":"error","passed":null}' >>"$BATS_TEST_TMPDIR/graded.jsonl"
	run ev gate d2_lean --graded "$BATS_TEST_TMPDIR/graded.jsonl"
	# 1 error in 9 rows = 11.1% > 10%
	[ "$status" -eq 1 ]
	[[ "$output" == *"gate: VOID (PLUMBING: 1 of 9 answers errored (> 10%))"* ]] || false
	mk_rows true 10
	printf '%s\n' '{"case_id":"c1","acct":"next","variant":"lean","rep":2,"status":"ok","passed":null}' >>"$BATS_TEST_TMPDIR/graded.jsonl"
	run ev gate d2_lean --graded "$BATS_TEST_TMPDIR/graded.jsonl"
	[ "$status" -eq 0 ]
	[[ "$output" == *"gate: INCOMPLETE (1 answer(s) still wait on the judge)"* ]] || false
}

@test "driver: refuses an unapproved model run; approved, --dry-run lays out ABBA per block with the lean definition injected" {
	python3 - "$BATS_TEST_TMPDIR/cases.jsonl" "$CC_HILLCLIMB_DIR/d2_lean/key.json" <<'PY'
import json, os, sys
cs = [dict(case_id=i, src="prod", acct=a, repo=None, commit=None, brief="Say hi to %s." % i, outputs=[], schema=False)
      for i, a in (("p-1", "next"), ("p-2", "next"), ("p-3", "next2"))]
open(sys.argv[1], "w").write("".join(json.dumps(c) + "\n" for c in cs))
os.makedirs(os.path.dirname(sys.argv[2]), exist_ok=True)
json.dump({c["case_id"]: dict(asks=["say hi"], facts=[]) for c in cs}, open(sys.argv[2], "w"))
PY
	run ev run d2_lean --cases "$BATS_TEST_TMPDIR/cases.jsonl" --tag t1 --dry-run
	[ "$status" -eq 4 ]
	[[ "$output" == *"is not approved"* ]] || false
	sha="$(ev harness-sha d2_lean)"
	run ev approve-harness d2_lean --confirm "${sha:0:12}"
	[ "$status" -eq 0 ]
	run ev run d2_lean --cases "$BATS_TEST_TMPDIR/cases.jsonl" --tag t1 --dry-run
	[ "$status" -eq 0 ]
	run python3 -c 'import json,sys
P=[json.loads(l) for l in open(sys.argv[1])]
print(" ".join("%s:%s%d@%s/%d" % (p["block"], p["variant"][0], p["rep"], p["acct"], len(p["cases"])) for p in P))
a=json.load(open(sys.argv[2]))["workflow-lean"]
print(a.get("omitClaudeMd"), "Read" in a["tools"], "Agent" in a["tools"], a["prompt"].startswith("You are a worker agent."))
s=open(P[1]["script"]).read()
print("@@INPUT" in s, "\"variant\": \"lean\"" in s, "Say hi to p-1." in s, "Harness rules" in s)' \
		"$CC_HILLCLIMB_DIR/d2_lean/runs/t1/positions.jsonl" "$CC_HILLCLIMB_DIR/d2_lean/runs/t1/agents.json"
	[ "$status" -eq 0 ]
	# block 0 (next, 2 cases) runs A=default: d1 l1 l2 d2; block 1 (next2) runs A=lean: l1 d1 d2 l2
	[ "${lines[0]}" = "b0:d1@next/2 b0:l1@next/2 b0:l2@next/2 b0:d2@next/2 b1:l1@next2/1 b1:d1@next2/1 b1:d2@next2/1 b1:l2@next2/1" ]
	[ "${lines[1]}" = "True True False True" ]
	[ "${lines[2]}" = "False True True True" ]
}

# A stub `claude` records its argv (one per line), cwd and the two env vars the eval relies on, and
# exits 0 without running a workflow — so the run must report the position incomplete (exit 1).
@test "driver: each position launches a fresh lead with the model, effort, injected agents and session id it records" {
	python3 - "$BATS_TEST_TMPDIR/cases.jsonl" "$CC_HILLCLIMB_DIR/d2_lean/key.json" <<'PY'
import json, os, sys
c = dict(case_id="p-1", src="prod", acct="next", repo=None, commit=None, brief="Say hi.", outputs=[], schema=False)
open(sys.argv[1], "w").write(json.dumps(c) + "\n")
os.makedirs(os.path.dirname(sys.argv[2]), exist_ok=True)
json.dump({"p-1": dict(asks=["say hi"], facts=[])}, open(sys.argv[2], "w"))
PY
	cc_stub "$BATS_TEST_TMPDIR/bin" claude - <<STUB
#!/bin/sh
for a in "\$@"; do printf '%s\n' "\$a"; done > "$BATS_TEST_TMPDIR/argv"
printf '%s\n' "\$(pwd -P)" "\$CLAUDE_CONFIG_DIR" "\$CC_LEVER_EXCLUDE" > "$BATS_TEST_TMPDIR/ctx"
STUB
	export CC_D2_CLAUDE="$BATS_TEST_TMPDIR/bin/claude"
	sha="$(ev harness-sha d2_lean)"
	run ev approve-harness d2_lean --confirm "${sha:0:12}"
	[ "$status" -eq 0 ]
	run ev run d2_lean --cases "$BATS_TEST_TMPDIR/cases.jsonl" --tag t2 --reps 1
	[ "$status" -eq 1 ]
	[[ "$output" == *"2 position(s) ended without a completed workflow"* ]] || false
	run python3 -c 'import json,os,sys
a=open(sys.argv[1]).read().splitlines(); P=[json.loads(l) for l in open(sys.argv[2])]
nxt=lambda f: a[a.index(f)+1]
print(nxt("--model"), nxt("--effort"), nxt("--permission-mode"), nxt("--allowedTools"), os.path.basename(nxt("--agents")),
      nxt("--session-id")==P[-1]["sid"], a[a.index("-p")+1].startswith("Run the workflow script at "+P[-1]["script"]))
c=open(sys.argv[3]).read().splitlines()
print(c[0]==os.path.realpath(P[-1]["workdir"]+"/_lead"), c[1]==os.environ["HOME"]+"/.claude-next", c[2], P[-1]["rc"], P[-1]["wf_status"])' \
		"$BATS_TEST_TMPDIR/argv" "$CC_HILLCLIMB_DIR/d2_lean/runs/t2/positions.jsonl" "$BATS_TEST_TMPDIR/ctx"
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "claude-opus-5-5 high auto Workflow agents.json True True" ]
	[ "${lines[1]}" = "True True 1 0 None" ]
}
