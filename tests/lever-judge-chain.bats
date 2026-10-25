#!/usr/bin/env bats
# lever-judge-chain.bats — wave S8 of docs/plans/USAGE_LEVERS.md § W7+: D1's chain accounting
# (scripts/lib/lever_chain.py, scored by bin/cc-lever-score) and the blind judge (bin/cc-lever-judge
# over config/lever-rubrics.json), each at its CLI boundary.
#
# Contracts held here:
#   · chain arithmetic: one treated recycle on tests/fixtures/lever-judge/mkchain.py, priced BY HAND
#     below, scores 0.02841 pp net (the TTL rule, the first turn, wake, handoff and rework all count)
#   · the D1 model check passes on a fleet whose idle context is true and FAILS (PLUMBING for D1)
#     when ctx_at_idle overstates it 2x; predecessor/successor arms that differ FAIL agreement
#   · the judge refuses a forbidden served model or a missing init line (exit 4) before any row
#   · a batch whose anchors the judge reads inverted is VOID on kappa; a known negative that passes
#     even once voids the batch; each known negative is judged exactly 3 times
#   · at most 40 dossiers a UTC day, counted across runs; the next day is fresh
#   · reask: operator prompts after the would-recycle point (the successor's bridge prompt is not
#     one), pre-filter negatives written beside the judged candidate, T5 leaves "pending", and a
#     second run re-judges nothing
#   · D4 S1 "re-issued as told" comes from kind=d4_follow rows, and 0/6 at S1 REVERTs
# The claude stub (tests/fixtures/lever-judge/claude-stub) answers only from labels the fixture
# planted ([[gold:…]]) or from the rubric's own known-negative texts; it never applies a rubric.
# The kind=offline round row is held in lever-eval.bats (its owner suite, test "round: …").
#
# RED-proof (2026-10-25, measured on a git-archive scratch copy): project() without its TTL arm
# scores -0.01925 pp, not 0.02841 (test 1 red); model_check_tol 0.25 -> 2.0 passes the 2x fleet's
# ratio 1.390 (test 2 red); the kappa_min comparison made False -> the flip batch holds OK (test 5
# red); fails() made False -> a gold batch is VOID on its known negatives (tests 4, 6, 8 red);
# reserve() removed -> the second run is accepted, rc 0 (test 7 red). File absence: before S8
# there is no bin/cc-lever-judge and D1 scored "metric … is built by wave S8".

setup() {
	REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
	FX="$BATS_TEST_TMPDIR/fx"
	T0=1791000000
	mkdir -p "$FX"
	export HOME="$FX/home" CC_LEVER_STATE_DIR="$FX/state" CC_LEVER_LOG_DIR="$FX/logs" \
		CC_LAND_LOG="$FX/land.jsonl" CC_NOW=$((T0 + 86400)) CC_TOKEN_LEDGER_WORKERS=1 \
		CC_HILLCLIMB_DIR="$FX/hc" CC_LEVER_JUDGE_CLAUDE="$REPO/tests/fixtures/lever-judge/claude-stub" \
		STUB_RUBRICS="$REPO/config/lever-rubrics.json" STUB_LOG="$FX/stub.log" CC_LEVER_JUDGE_WORKERS=2
	unset CC_LEVER_ALL CC_LEVER_D1 CC_LEVER_D2 CC_LEVER_D3 CC_LEVER_D4 CC_LEVER_EXCLUDE CC_MODEL_CONFIG \
		STUB_MODE STUB_MODEL
	/usr/bin/python3 -I "$REPO/tests/fixtures/lever-judge/mkchain.py" "$FX" "$T0" >/dev/null
}

score() { /usr/bin/python3 -I "$REPO/bin/cc-lever-score" "$@"; }
judge() { /usr/bin/python3 -I "$REPO/bin/cc-lever-judge" "$@"; }
jf() { /usr/bin/python3 -c 'import json,sys; r=json.loads(sys.stdin.read().splitlines()[-1]); print(eval(sys.argv[1]))' "$1"; }
dossiers() { # <n> <file>: re-ask dossiers, none of them a known negative
	/usr/bin/python3 -c 'import json,sys
for i in range(int(sys.argv[1])):
    print(json.dumps({"id": "d%02d" % i, "sid": "s%d" % i, "sections": {"assistant_before": "done %d" % i, "operator_prompt": "next thing %d" % i}}))' "$1" >"$2"
}

@test "chain: one treated recycle nets 0.02841 pp, priced by hand from the fixture's tokens" {
	# pp per Mtok: write 0.245, read 0.0067 (mid), output 0.404. Idle point t=1000 (ctx 200000).
	# successor first turn [2000, 2030] (gap 3000 s ends it): 15104 + 1950.2 = 17054.2
	# rest, shifted by off = 200000 - 65000 = 135000 and priced from the predecessor's last request:
	#   5030 (4030 s after t=1000 > TTL: rewrite 201000)  CF 49406.6  actual  842.1
	#   5060 (warm, write 2000, read 201000)              CF  2079.1  actual 1174.6
	# wake 1445.3 · handoff 2314.17 · rework: /x/a.py re-read, 4000 chars = 1000 tokens x 0.245 = 245
	# net = 51485.7 - 2016.7 - 17054.2 - 1445.3 - 2314.17 - 245 = 28410.33 (x 1e-6 pp)
	run score score --lever D1 --since 7d --json
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	[ "$(jf 'r["estimate"]["net_per_recycle"]' <<<"$output")" = "0.02841" ]
	[ "$(jf '(r["chain"]["scored"], r["chain"]["rework_tok_median"], r["chain"]["first_reqs_median"])' <<<"$output")" = "(1, 1000, 2)" ]
	# a live D1 with a priced recycle still holds its verdict for the plumbing it lacks
	[ "$(jf 'r["verdict"]' <<<"$output")" = "PLUMBING" ]
}

@test "model check: true idle context passes, a 2x ctx_at_idle FAILS and holds D1 at PLUMBING" {
	K="$BATS_TEST_TMPDIR/st"
	run /usr/bin/python3 -I "$REPO/bin/cc-lever-score" selftest --keep "$K"
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	export HOME="$K/home" CC_LEVER_STATE_DIR="$K/state" CC_LEVER_LOG_DIR="$K/logs" CC_LAND_LOG="$K/land.log" \
		CC_NOW=1791072000
	mc() { score plumbing --since 7d --json | /usr/bin/python3 -c 'import json,sys
for k in json.load(sys.stdin)["checks"]:
    if k["check"].startswith("D1 model check"): print(k["status"], k["detail"])'; }
	run mc
	[[ "$output" == "pass "*"= 1.000 over "* ]] || { echo "$output"; false; }
	irs="$K/logs/idle-recycle-shadow.jsonl"
	/usr/bin/python3 -c 'import json,sys
rs=[json.loads(l) for l in open(sys.argv[1])]
open(sys.argv[1],"w").writelines(json.dumps(dict(r, ctx_at_idle=2*r["ctx_at_idle"]))+"\n" for r in rs)' "$irs"
	run mc
	[[ "$output" == "fail "* ]] || { echo "$output"; false; }
	run score score --lever D1 --since 7d --json
	[[ "$(jf 'r["verdict"], [p for p in r["plumbing"] if "model check" in p]' <<<"$output")" == "('PLUMBING', ['fail:D1 model check"* ]] || { echo "$output"; false; }
}

@test "arm agreement: a successor whose D1 arm differs from its predecessor's FAILS (as built: 1/1 agree)" {
	ag() { score plumbing --since 7d --json | /usr/bin/python3 -c 'import json,sys
for k in json.load(sys.stdin)["checks"]:
    if k["check"].startswith("successor/predecessor"): print(k["status"], k["detail"])'; }
	run ag
	[[ "$output" == "pass 1/1 edge(s) agree"* ]] || { echo "$output"; false; }
	/usr/bin/python3 -c 'import json,sys
rs=[json.loads(l) for l in open(sys.argv[1])]
rs[1]["arms"]["D1"]["arm"]="ctrl"
open(sys.argv[1],"w").writelines(json.dumps(r)+"\n" for r in rs)' "$FX/logs/lever-arms.jsonl"
	run ag
	[[ "$output" == "fail 0/1 edge(s) agree"* ]] || { echo "$output"; false; }
}

@test "judge: a forbidden served model or no init line stops the batch (exit 4), sonnet runs" {
	dossiers 3 "$FX/d.jsonl"
	STUB_MODEL=claude-opus-5-5 run judge run reask --dossiers "$FX/d.jsonl" --write
	[ "$status" -eq 4 ] || { echo "$output"; false; }
	[[ "$output" == *"forbidden model"* ]] || false
	STUB_MODE=noinit run judge run reask --dossiers "$FX/d.jsonl" --write
	[ "$status" -eq 4 ] || { echo "$output"; false; }
	[[ "$output" == *"no init line"* ]] || false
	[ ! -e "$FX/logs/lever-judge.jsonl" ]
	run judge run reask --dossiers "$FX/d.jsonl" --write
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	[ "$(jf 'r["verdict"], r["models"]' <<<"$output")" = "('OK', {'claude-sonnet-5-5': 30})" ]
}

@test "kappa: anchors judged inverted VOID the batch; nothing but the batch row is written" {
	dossiers 3 "$FX/d.jsonl"
	STUB_MODE=flip run judge run d1_return --dossiers "$FX/d.jsonl" --write
	[ "$status" -eq 1 ] || { echo "$output"; false; }
	[[ "$(jf 'r["verdict"], r["why"]' <<<"$output")" == "('VOID', 'kappa "* ]] || { echo "$output"; false; }
	[ "$(/usr/bin/python3 -c 'import json,sys; print(sorted({json.loads(l)["kind"] for l in open(sys.argv[1])}))' "$FX/logs/lever-judge.jsonl")" = "['batch']" ]
}

@test "known negatives: each judged 3 times; one that passes voids the batch" {
	dossiers 10 "$FX/d.jsonl"
	run judge run reask --dossiers "$FX/d.jsonl" --seed 7
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	[ "$(jf 'r["known_negatives"]' <<<"$output")" = "{'kn-reask-file': [3, 3], 'kn-reask-staging': [3, 3]}" ]
	# 10 dossiers + 1 re-judged swapped + 20 anchors + 2 known negatives x 3
	[ "$(wc -l <"$STUB_LOG")" -eq 37 ]
	STUB_MODE=kn-pass run judge run reask --dossiers "$FX/d.jsonl" --seed 7
	[ "$status" -eq 1 ] || { echo "$output"; false; }
	[[ "$(jf 'r["why"]' <<<"$output")" == "known negative(s) not failed 3/3: kn-reask-file 0, kn-reask-staging 0" ]] || { echo "$output"; false; }
}

@test "daily cap: 40 dossiers per UTC day across runs; refused runs call nothing; the next day is fresh" {
	dossiers 30 "$FX/a.jsonl"
	dossiers 15 "$FX/b.jsonl"
	run judge run reask --dossiers "$FX/a.jsonl"
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	n="$(wc -l <"$STUB_LOG")"
	run judge run reask --dossiers "$FX/b.jsonl"
	[ "$status" -eq 3 ] || { echo "$output"; false; }
	[[ "$output" == *"daily cap: 30 of 40 dossiers used today"* ]] || false
	[ "$(wc -l <"$STUB_LOG")" -eq "$n" ]
	CC_NOW=$((T0 + 2 * 86400)) run judge run reask --dossiers "$FX/b.jsonl"
	[ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "reask: prompts after the recycle point, bridge excluded; T5 leaves pending; a re-run judges nothing new" {
	t5() { score guards --json | /usr/bin/python3 -c 'import json,sys; print(json.loads(sys.stdin.readline())["guards"]["T5"]["status"])'; }
	run t5
	[ "$output" = "pending" ]
	run judge reask --since 7d --write
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	[[ "$output" == *"2 prompt(s) in 1 session(s), 1 candidate(s)"* ]] || { echo "$output"; false; }
	[ "$(/usr/bin/python3 -c 'import json,sys
print(sorted((r["src"], r["reask"]) for r in map(json.loads, open(sys.argv[1])) if r["kind"] == "reask"))' "$FX/logs/lever-judge.jsonl")" = "[('judge', True), ('prefilter', False)]" ]
	run t5
	[ "$output" = "ok" ]
	run judge reask --since 7d --write
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	[[ "$output" == *"0 prompt(s) in 0 session(s)"* ]] || { echo "$output"; false; }
}

@test "D4 compliance: re-issued as told is read from d4_follow rows, and 0/6 at S1 REVERTs" {
	/usr/bin/python3 -c 'import json,sys,time
ts=lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
t0=int(sys.argv[2])
rows=[{"kind":"d4_follow","ts":ts(t0+100+i),"sid":"s","agent_id":"a%d"%i,"follows_verdict":"deny","echo_rc":i<4,"run_in_background":i==3} for i in range(6)]
rows.append({"kind":"d4_follow","ts":ts(t0+200),"sid":"s","agent_id":"z","follows_verdict":"would_deny","echo_rc":True})
rows.append({"kind":"subagent_bash","ts":ts(t0+300),"sid":"s","agent_id":"y","would_deny_class":"poll-loop","exempt":None})
open(sys.argv[1],"a").writelines(json.dumps(r)+"\n" for r in rows)' "$FX/logs/subagent-long-bash.jsonl" "$T0"
	run score score --lever D4 --since 7d --json
	[ "$status" -eq 0 ] || { echo "$output"; false; }
	[ "$(jf '(r["compliance"]["complied"], r["compliance"]["denies"])' <<<"$output")" = "(3, 6)" ]
	/usr/bin/python3 -c 'import json,sys
d=json.load(open(sys.argv[1])); d["levers"]["D4"].update(stage="S1", pct=50, mode="live")
open(sys.argv[1],"w").write(json.dumps(d))' "$FX/state/flags.json"
	/usr/bin/python3 -c 'import json,sys
rs=[json.loads(l) for l in open(sys.argv[1])]
open(sys.argv[1],"w").writelines(json.dumps(dict(r, echo_rc=False) if r["kind"]=="d4_follow" else r)+"\n" for r in rs)' "$FX/logs/subagent-long-bash.jsonl"
	run score score --lever D4 --since 7d --json
	[[ "$(jf 'r["stat_verdict"], r["reasons"][0]' <<<"$output")" == "('REVERT', 're-issued as told: Wilson upper "* ]] || { echo "$output"; false; }
}
