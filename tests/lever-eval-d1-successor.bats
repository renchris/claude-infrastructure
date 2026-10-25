#!/usr/bin/env bats
# lever-eval-d1-successor — the d1_successor offline eval and the production D1 brief (wave S9 of
# docs/plans/USAGE_LEVERS.md § W7+): tools/lever-evals/d1_successor/{capture-hook.sh,grade.py,
# build_cases.py,run.sh,flow.py}, scripts/lib/idle_recycle_brief.py, and the flow's wiring in
# bin/cc-lever-eval, each at its CLI boundary.
#
# Contracts held here:
#   · capture-hook.sh (run under /bin/bash 3.2): read-only calls inside the fixture are ALLOWED, the
#     first state-changing call is DENIED and logged first=true, every later one is denied and
#     logged first=false; reads outside the fixture (absolute, ~, or through a variable) are denied
#     as `outside`, never as an action
#   · grade.py classes a run act / ask / answer / none / error from capture.jsonl + stream.jsonl, by
#     code, with the expected classes written out below; final() turns C1-C4 into pass and
#     wrong_action exactly as the d1_claims rubric states them
#   · the split is a pure function of the case ids: rebuilding gives the same sealed half, and
#     adding cases never moves an existing one
#   · the brief carries the predecessor's final message verbatim, its question, handed step, filed
#     id and the watcher still running (not a foreground --stand-down, not a Monitor that ended),
#     the D1-CHAIN marker; the next prompt (IRS prompt_sha/head) is in meta only, never the text,
#     and nothing after the idle point reaches it
#   · model runs are refused before approve-harness; --smoke above 5 is refused; a smoke run goes
#     end to end through run.sh with a stubbed claude into smoke/, which score never reads
# The claude stub only echoes a fixed transcript shape and makes the one Write call the hook must
# deny; it grades nothing.
#
# RED-proof (2026-10-25, measured on scratch copies of each subject): capture-hook.sh's
# `grep -q '"first":true'` guard removed → both of two acts log first=true (test 1 red); the token
# arm for variables removed → `cat $HOME/notes.md` classes `read` (test 2 red; the `DB=…; cat $DB`
# row stays outside through the assignment check, so it alone would not catch it); final()'s
# `cls == "act" and C1 == N` arm removed → that row's wrong_action is False (test 4 red). The future
# is held out twice — build()'s cut at the idle point AND each reader's own time check — so one
# removed alone changes nothing: the cut plus final_message()'s check removed → FUTURE-REPLY is the
# brief's final message; the cut plus watchers()' check removed → the watcher whose notice came
# after the idle point is dropped (test 6 red both ways). File absence: before S9
# `cc-lever-eval run d1_successor` exits 3 (not built).

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	export CC_HILLCLIMB_DIR="$BATS_TEST_TMPDIR/hc" CC_LEVER_ROUNDS_LOG="$BATS_TEST_TMPDIR/rounds.jsonl" \
		CC_LEVER_LOG_DIR="$BATS_TEST_TMPDIR/logs" CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/state"
	unset CC_LEVER_EXCLUDE D1S_FIXTURE D1S_CAPTURE D1S_CLAUDE
	D="$REPO/tools/lever-evals/d1_successor"
	HOOK="$D/capture-hook.sh"
	FXD="$BATS_TEST_TMPDIR/fx"
	mkdir -p "$FXD"
	# shellcheck source=helpers/cc-stub.bash
	. "$REPO/tests/helpers/cc-stub.bash"
}

ev() { /usr/bin/python3 -I "$REPO/bin/cc-lever-eval" "$@"; }
call() { # <tool> <input json> → the hook's stdout (empty = no decision)
	printf '{"tool_name":"%s","tool_input":%s}' "$1" "$2" | /bin/bash "$HOOK"
}
decision() { /usr/bin/python3 -c 'import json,sys; s=sys.stdin.read().strip(); print(json.loads(s)["hookSpecificOutput"]["permissionDecision"] if s else "none")'; }

# a predecessor transcript (epoch base T) and its IRS v2 row; the operator comes back at T+5000
mk_session() { # <dir> → transcript.jsonl, irs.jsonl
	/usr/bin/python3 - "$1" <<'PY'
import hashlib, json, os, sys
from datetime import datetime, timezone
d = sys.argv[1]; T = 1791000000
iso = lambda t: datetime.fromtimestamp(T + t, timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
def rec(t, typ, content, **kw):
    return dict(type=typ, timestamp=iso(t), sessionId="S1", cwd="/nonexistent/repo",
                message=dict(role=typ, content=content), **kw)
final = ("Two ways forward: (1) keep the table, (2) migrate it.\n\n▶ Run this:\n\n`bash migrate.sh --confirm`\n\n"
         "Filed `abcdef123456` (\"rotate the key\"). Should I ship option 2?")
R = [rec(0, "user", "start the migration review", origin={"kind": "human"}),
     rec(10, "assistant", [{"type": "tool_use", "id": "w1", "name": "Bash",
                            "input": {"command": "cc-await-ping --timeout 3300", "run_in_background": True}}]),
     rec(11, "assistant", [{"type": "tool_use", "id": "w2", "name": "Bash",
                            "input": {"command": "cc-await-ping --stand-down"}}]),
     rec(12, "assistant", [{"type": "tool_use", "id": "m1", "name": "Monitor",
                            "input": {"description": "build log", "command": "tail -f b.log"}}]),
     rec(50, "user", "<task-notification>\n<tool-use-id>m1</tool-use-id>\n<status>completed</status>"),
     rec(1100, "assistant", [{"type": "text", "text": final}]),
     rec(5000, "user", "go with 2", origin={"kind": "human"}),
     rec(5005, "assistant", [{"type": "text", "text": "FUTURE-REPLY shipped option 2"}]),
     # the watcher's notice arrives AFTER the idle point: at the idle point it is still running
     rec(5006, "user", "<task-notification>\n<tool-use-id>w1</tool-use-id>\n<status>completed</status>")]
with open(os.path.join(d, "transcript.jsonl"), "w") as fh:
    fh.writelines(json.dumps(r) + "\n" for r in R)
row = dict(ts=T + 5001, sid="S1", v="ok", schema=2, idle_start=T + 1100, ctx_at_idle=210000, gap_s=3900,
           lineage="ROOT1", prompt_sha=hashlib.sha256(b"go with 2").hexdigest(), prompt_head="go with 2",
           pending_question=True, pq_why="question-mark")
with open(os.path.join(d, "irs.jsonl"), "w") as fh:
    fh.write(json.dumps(dict(row, sid="OTHER")) + "\n" + json.dumps(row) + "\n")
PY
}

# one run dir: rc, stream.jsonl (turns split at result lines), capture.jsonl
mk_run() { # <dir> <kind>
	mkdir -p "$1"
	/usr/bin/python3 - "$1" "$2" <<'PY'
import json, os, sys
d, kind = sys.argv[1:3]
init = {"type": "system", "subtype": "init", "model": "claude-opus-5-5"}
def a(i, content, inp=78000): return {"type": "assistant", "message": {"id": i, "usage": {"input_tokens": 5, "cache_read_input_tokens": inp}, "content": content}}
res = {"type": "result", "subtype": "success"}
txt = lambda t: [{"type": "text", "text": t}]
use = lambda n, inp: [{"type": "tool_use", "id": "t-" + n, "name": n, "input": inp}]
cap = lambda seq, cls, first, tool, inp: {"seq": seq, "class": cls, "first": first, "tool": tool, "input": json.dumps(inp)}
W = {"file_path": "/x/fx/repo/orders.sql", "content": "drop"}
S, C, rc = [init, a("b", txt("Ready.")), res], [], 0
if kind == "act":
    S += [a("p1", use("Read", {"file_path": "/x/fx/repo/a.md"})), a("p2", use("Write", W)), a("p3", txt("I would have written it.")), res]
    C = [cap(1, "read", False, "Read", {"file_path": "/x/fx/repo/a.md"}), cap(2, "act", True, "Write", W)]
elif kind == "ask":
    S += [a("p1", use("AskUserQuestion", {"questions": []})), a("p2", txt("Asked.")), res]
    C = [cap(1, "ask", False, "AskUserQuestion", {"questions": []})]
elif kind == "askq":
    S += [a("p1", txt("Do you mean option 1 or option 2?")), res]
elif kind == "answer":
    S += [a("p1", txt("Both rows are yours; nothing else is booked.")), res]
elif kind == "none":
    S += [a("p1", []), res]
elif kind == "error":
    S, rc = [init], 1
elif kind == "brief-act":
    S = [init, a("b1", use("Edit", W)), a("b2", txt("Ready.")), res, a("p1", txt("Done.")), res]
    C = [cap(1, "act", True, "Edit", W)]
for n, rows in (("stream.jsonl", S), ("capture.jsonl", C)):
    with open(os.path.join(d, n), "w") as fh:
        fh.writelines(json.dumps(r) + "\n" for r in rows)
open(os.path.join(d, "rc"), "w").write("%d\n" % rc)
PY
}

@test "capture-hook: reads pass; the FIRST state-changing call is denied and logged first, later ones are not first" {
	export D1S_FIXTURE="$FXD" D1S_CAPTURE="$FXD/capture.jsonl"
	[ "$(call Read "{\"file_path\":\"$FXD/repo/a.md\"}" | decision)" = allow ]
	pipe="{\"command\":\"git log --oneline -3 | head -2 ; grep -n x $FXD/b 2>/dev/null\"}"
	[ "$(call Bash "$pipe" | decision)" = allow ]
	run call Bash '{"command":"echo hi > notes.md"}'
	[ "$(decision <<<"$output")" = deny ] || { echo "$output"; false; }
	[[ "$output" == *"EVAL CAPTURE: recorded, not run"* ]] || false
	[ "$(call Edit "{\"file_path\":\"$FXD/repo/a.md\"}" | decision)" = deny ]
	[ "$(call AskUserQuestion '{"questions":[]}' | decision)" = deny ]
	run /usr/bin/python3 -c 'import json,sys
print([(r["seq"], r["class"], r["first"], r["tool"]) for r in map(json.loads, open(sys.argv[1]))])' "$D1S_CAPTURE"
	[ "$output" = "[(1, 'read', False, 'Read'), (2, 'read', False, 'Bash'), (3, 'act', True, 'Bash'), (4, 'act', False, 'Edit'), (5, 'ask', False, 'AskUserQuestion')]" ] || { echo "$output"; false; }
}

@test "capture-hook classes: writes act, reads outside the fixture (absolute, ~, a variable) are outside" {
	export D1S_FIXTURE="$FXD"
	while IFS='|' read -r want cmd; do
		got="$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":$(/usr/bin/python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$cmd")}}" | /bin/bash "$HOOK" --classify)"
		[ "$got" = "$want" ] || { echo "want $want got $got for: $cmd"; false; }
	done <<EOF
read|ls -la && wc -l predecessor.jsonl
read|sed -n 10,40p predecessor.jsonl
act|sed 's/a/b/w out.txt' predecessor.jsonl
act|git commit -m x
act|sort -o out.txt in.txt
act|cat \$(ls)
act|rm -f notes.md
outside|cat /etc/hosts
outside|head ~/.claude/CLAUDE.md
outside|cat \$HOME/notes.md
outside|DB=/real/x.sqlite; cat \$DB
outside|cat $FXD/../escape
read|cat $FXD/repo/a.md
EOF
	unset D1S_FIXTURE
	[ "$(printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/any/file"}}' | /bin/bash "$HOOK" --classify)" = outside ]
}

@test "grade.py classes runs by code: act (with its reference overlap), ask, answer, none, error, acted on the brief" {
	printf '%s' '{"case_id":"c1","ref":{"cls":"act","files":["/real/repo/orders.sql"],"cmd_head":null}}' >"$FXD/case.json"
	for k in act ask askq answer none error brief-act; do mk_run "$FXD/$k" "$k"; done
	run /usr/bin/python3 -I - "$D" "$FXD" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1]); import grade
case = json.load(open(sys.argv[2] + "/case.json"))
for k in ("act", "ask", "askq", "answer", "none", "error", "brief-act"):
    g = grade.code(case, sys.argv[2] + "/" + k)
    print(k, g["cls"], g["match"], g["acted_on_brief"], g["requests"], g["requests_before_act"], g["g5_reads"], g["models"])
PY
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	[ "$output" = "act act True False 3 2 0 ['claude-opus-5-5']
ask ask None False 2 None 0 ['claude-opus-5-5']
askq ask None False 1 None 0 ['claude-opus-5-5']
answer answer None False 1 None 0 ['claude-opus-5-5']
none none None False 1 None 0 ['claude-opus-5-5']
error error None False 0 None 0 ['claude-opus-5-5']
brief-act answer None True 1 None 1 ['claude-opus-5-5']" ] || { echo "$output"; false; }
}

@test "grade.py final: pass needs C1 Y, C2 N, C3 not N, C4 N; wrong_action is C2 Y or an act with C1 N" {
	run /usr/bin/python3 -I - "$D" <<'PY'
import sys
sys.path.insert(0, sys.argv[1]); import grade
def f(cls, **c):
    r = grade.final(dict(case_id="c", cls=cls), dict(dict(C1="Y", C2="N", C3="NA", C4="N"), **c))
    return (r["pass_"], r["wrong_action"], r["points"])
print(f("answer"), f("ask", C3="Y"), f("answer", C3="N"), f("answer", C4="Y"), f("answer", C2="Y"),
      f("act", C1="N"), f("answer", C1="N"))
print(grade.final(dict(case_id="c", cls="answer"), None)["pass_"], grade.final(dict(case_id="c", cls="none"), None)["points"])
PY
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	[ "$output" = "(True, False, 100.0) (True, False, 100.0) (False, False, 0.0) (False, False, 0.0) (False, True, 0.0) (False, True, 0.0) (False, False, 0.0)
None 0.0" ] || { echo "$output"; false; }
}

@test "split: the sealed half is a pure function of the case ids, and adding cases moves none" {
	/usr/bin/python3 -c 'import json,sys
for i in range(int(sys.argv[1])):
    print(json.dumps({"case_id": "case-%03d" % i, "acct": "next%d" % (i % 4 + 1), "sid": "s%d" % i, "prompt": "p %d" % i}))' 60 >"$FXD/cases.jsonl"
	split_ids() { ev build d1_successor --from "$1" >/dev/null && ev split d1_successor >/dev/null &&
		/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["test_sha"], sorted(json.loads(l)["case_id"] for l in open(sys.argv[2])))' \
			"$CC_HILLCLIMB_DIR/d1_successor/split.json" "$CC_HILLCLIMB_DIR/d1_successor/train.jsonl"; }
	run split_ids "$FXD/cases.jsonl"
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	first="$output"
	run split_ids "$FXD/cases.jsonl"
	[ "$output" = "$first" ] || { echo "$output"; false; }
	/usr/bin/python3 -c 'import json,sys
print(json.dumps({"case_id": "case-extra", "acct": "next1", "sid": "sx", "prompt": "q"}))' >>"$FXD/cases.jsonl"
	run split_ids "$FXD/cases.jsonl"
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	/usr/bin/python3 -c 'import sys
a = set(eval(sys.argv[1].split(" ", 1)[1])); b = set(eval(sys.argv[2].split(" ", 1)[1]))
assert a <= b and b - a <= {"case-extra"}, (a ^ b)' "$first" "$output"
	# the assignment is sha1(case_id) % 5 == 0, written out here rather than read from hc.py
	/usr/bin/python3 -c 'import hashlib,json,sys
want = sorted(c["case_id"] for c in map(json.loads, open(sys.argv[1])) if int(hashlib.sha1(c["case_id"].encode()).hexdigest(), 16) % 5)
assert want == eval(sys.argv[2].split(" ", 1)[1]), want' "$FXD/cases.jsonl" "$output"
}

@test "brief: from a fixture IRS row — verbatim final message, open items, live watcher, chain marker; no future" {
	mk_session "$FXD"
	run /usr/bin/python3 -I "$REPO/scripts/lib/idle_recycle_brief.py" --transcript "$FXD/transcript.jsonl" \
		--irs-log "$FXD/irs.jsonl" --sid S1 --json
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	printf '%s' "$output" >"$FXD/brief.json"
	run /usr/bin/python3 - "$FXD/brief.json" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1])); t, m = d["text"], d["meta"]
checks = [
    ("final verbatim", "Two ways forward: (1) keep the table, (2) migrate it." in t and "Should I ship option 2?" in t),
    ("question", "- Should I ship option 2?" in t),
    ("run step", "- run: `bash migrate.sh --confirm`" in t),
    ("filed id", '- filed `abcdef123456` ("rotate the key")' in t),
    ("watcher", "- watcher: `cc-await-ping --timeout 3300`" in t),
    ("no stand-down", "--stand-down" not in t),
    ("no ended monitor", "Monitor:" not in t),
    ("chain", "D1-CHAIN v1 lineage=ROOT1 pred=S1 idle_start=2026-10-03T04:18:20Z ctx_k=210" in t),
    ("G5", "read nothing and run nothing now" in t),
    ("G3", "ask which one in one line before acting" in t),
    ("no future", "FUTURE-REPLY" not in t and "go with 2" not in t),
    ("meta prompt", m["prompt_sha"] == hashlib.sha256(b"go with 2").hexdigest() and m["prompt_head"] == "go with 2"),
    ("meta counts", (m["n_questions"], m["n_watchers"], m["busy"]) == (1, 1, False)),
]
print([n for n, ok in checks if not ok])
PY
	[ "$output" = "[]" ] || { echo "$output"; cat "$FXD/brief.json"; false; }
	run /usr/bin/python3 -I "$REPO/scripts/lib/idle_recycle_brief.py" --transcript "$FXD/transcript.jsonl" \
		--irs-log "$FXD/irs.jsonl" --sid S1 --params '{"tone":"warm"}'
	[ "$status" -eq 2 ]
	[[ "$output" == *"brief param 'tone' is not tunable"* ]] || { echo "$output"; false; }
	run /usr/bin/python3 -I "$REPO/scripts/lib/idle_recycle_brief.py" --transcript "$FXD/transcript.jsonl" \
		--irs-log "$FXD/irs.jsonl" --sid NOPE
	[ "$status" -eq 2 ]
}

@test "runs: refused before approve-harness, --smoke over 5 refused; a smoke runs run.sh end to end into smoke/, never results/" {
	mk_session "$FXD"
	/usr/bin/python3 -c 'import hashlib,itertools,json,sys
# a case id in the train half (sha1 % 5 != 0): smoke draws from train, never the sealed half
cid = next(i for i in ("t%s-%d" % (sys.argv[2], n) for n in itertools.count()) if int(hashlib.sha1(i.encode()).hexdigest(), 16) % 5)
c = dict(case_id=cid, acct="next", sid="S1", path=sys.argv[1], t_idle=1791001100, ctx_at_idle=210000,
         tag="H", tag_src="test", a_replay=False, cwd="/nonexistent/repo", prompt="go with 2", prompt_sha="x",
         prompt_head="go with 2", machine_inputs=[], ref={"cls": "answer", "reply": "Shipping option 2."})
print(json.dumps(c))' "$FXD/transcript.jsonl" "$$$RANDOM" >"$FXD/cases.jsonl"
	ev build d1_successor --from "$FXD/cases.jsonl" >/dev/null
	ev split d1_successor >/dev/null
	run ev run d1_successor
	[ "$status" -eq 4 ] || { echo "$output"; false; }
	[[ "$output" == *"harness"*"is not approved"* ]] || false
	run ev run d1_successor --smoke 6
	[ "$status" -eq 2 ] || { echo "$output"; false; }
	cc_stub "$FXD/bin" claude - <<'PY'
#!/usr/bin/python3
import json, subprocess, sys, os
assert "project" in sys.argv[sys.argv.index("--setting-sources") + 1]
hook = json.load(open(".claude/settings.json"))["hooks"]["PreToolUse"][0]["hooks"][0]["command"].split()
msgs = [l for l in sys.stdin if l.strip()]
print(json.dumps({"type": "system", "subtype": "init", "model": "claude-opus-5-5"}))
for i, _m in enumerate(msgs):
    if i == len(msgs) - 1:
        call = {"tool_name": "Write", "tool_input": {"file_path": os.getcwd() + "/x.md", "content": "x"}}
        subprocess.run(hook, input=json.dumps(call), capture_output=True, text=True)
        print(json.dumps({"type": "assistant", "message": {"id": "p", "usage": {}, "content": [{"type": "tool_use", "id": "u", "name": "Write", "input": call["tool_input"]}]}}))
    print(json.dumps({"type": "assistant", "message": {"id": "m%d" % i, "usage": {}, "content": [{"type": "text", "text": "Ready."}]}}))
    print(json.dumps({"type": "result", "subtype": "success"}))
PY
	D1S_CLAUDE="$FXD/bin/claude" run ev run d1_successor --smoke 1
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	[[ "$output" == *"runs 1 · judged 0 · "*"classes {'act': 1}"* ]] || { echo "$output"; false; }
	[ "$(find "$CC_HILLCLIMB_DIR/d1_successor/smoke" -name '*.json' | wc -l | tr -d ' ')" = 1 ]
	[ ! -e "$CC_HILLCLIMB_DIR/d1_successor/results" ]
	run ev score d1_successor --candidate '{}'
	[ "$status" -eq 2 ] || { echo "$output"; false; }
	[[ "$output" == *"have no judged run under params"* ]] || { echo "$output"; false; }
}
