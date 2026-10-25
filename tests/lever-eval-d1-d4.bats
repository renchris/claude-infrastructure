#!/usr/bin/env bats
# lever-eval-d1-d4 — the D1 K/N replay and the D4 poll-loop predicate + population gate
# (USAGE_LEVERS § W7+ S7b). The kernel (split, seal, decide, approval) is lever-eval.bats's.
#
# Subjects: tools/lever-evals/d1_recycle/ (sim.py, the port of w4/sim.py; flow.py's checks),
# tools/lever-evals/d4_pollloop/ (predicate.py running the REAL hooks/subagent-long-bash-shadow.sh
# under /bin/bash with its log redirected; flow.py's population gate), bin/cc-lever-eval's
# `check --population`.
#
# THE TWO REPRODUCTIONS this suite exists for, both on committed fixtures (no _imports, no live
# transcripts: HOME is a fixture, so receipts read as absent and targets come from the flows):
#   D1  the replay lands within ±5% of 16.36 / 15.39 pp/wk gross at 150k / 200k after 15 min
#       (decisions-2026-10-24 REPORT §1; tests/fixtures/lever-eval-d1-sessions.jsonl.gz is W4's
#       14-d rows trimmed to what K>=150k, N>=15 can read — flow.fixture()).
#   D4  replay_pred.py's answer: the 20 hand-read poll loops are all poll-loop would-denies, and
#       their 20 re-issues as told (270 s slices) are not judged again.
# Each has a negative control that must FAIL the same check (a check that always printed PASS would
# satisfy the positive test too). The population gate's thresholds are pinned by planted cases whose
# expected verdict is computed by hand below, never read back from flow.py.
#
# RED-proof (2026-10-24, scratch copies, measured): sim.py WARM_N 55*60 -> 10*60 (most handoffs a
# rewrite) -> the repro FAILs (150k 0.99 vs 16.36, 200k 3.36 vs 15.39); _rx_loop without `until`
# -> 7/20 hand-read originals, FAIL (test 5); GATE_N_WK 20 -> 40 -> test 6's 25/wk case PARKs.
# Test 5 also caught a real flaw on first run: replay(hook=HOOK) bound the default at import, so
# a reassigned HOOK was silently ignored.

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	export CC_HILLCLIMB_DIR="$BATS_TEST_TMPDIR/hc"
	export CC_LEVER_ROUNDS_LOG="$BATS_TEST_TMPDIR/rounds.jsonl"
	REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	CLI="$REPO/bin/cc-lever-eval"
	FX1="$REPO/tests/fixtures/lever-eval-d1-sessions.jsonl.gz"
	FX4="$REPO/tests/fixtures/lever-eval-d4-calls.jsonl.gz"
	D4="$REPO/tools/lever-evals/d4_pollloop"
}

ev() { python3 "$CLI" "$@"; }

@test "D1 reproduction: the K/N replay lands within ±5% of 16.36 / 15.39 pp/wk at 150k / 200k" {
	run ev check d1_recycle repro --ref "$FX1"
	[ "$status" -eq 0 ]
	[[ "$output" == *"PASS repro"* ]] || false
	[[ "$output" == *"150k/15m: replay 16.3"*"vs anchor 16.36"*" ok"* ]] || false
	[[ "$output" == *"200k/15m: replay 15.3"*"vs anchor 15.39"*" ok"* ]] || false
	[[ "$output" == *"absent; targets from flow.TARGETS"* ]] || false
}

@test "D1 reproduction negative control: the same check FAILS on the fixture minus one account" {
	python3 -c 'import gzip,json,sys
L=gzip.open(sys.argv[1],"rt").readlines()
o=gzip.open(sys.argv[2],"wt"); o.write(L[0])
o.writelines(l for l in L[1:] if json.loads(l)["acct"]!="next2")' "$FX1" "$BATS_TEST_TMPDIR/no2.jsonl.gz"
	run ev check d1_recycle repro --ref "$BATS_TEST_TMPDIR/no2.jsonl.gz"
	[ "$status" -eq 1 ]
	[[ "$output" == *"FAIL repro"* ]] || false
	[[ "$output" == *"150k/15m"*"FAIL"* ]] || false
}

@test "D1 flow: built from the fixture, the accounting identity, null and no-future-reads checks pass; n_min < 15 refused" {
	# A/A is not asserted here: its band is a property of the full population (0.055 over W4's 1,341
	# train sessions), not of 464 trimmed ones
	ev build d1_recycle --from "$FX1" >/dev/null
	ev split d1_recycle >/dev/null
	for c in oracle null truncation; do
		run ev check d1_recycle "$c"
		[ "$status" -eq 0 ]
		[[ "$output" == "PASS $c"* ]] || false
	done
	[[ "$output" == *"0 of 160 fire differently from the full session ok"* ]] || false
	# the rails hold 15 min after an interactive turn: a candidate that recycles sooner is not a D1 rule
	run ev score d1_recycle --candidate '{"n_min": 10}'
	[ "$status" -eq 2 ]
	[[ "$output" == *"n_min 10 outside [15, 120]"* ]] || false
}

@test "D4 reproduction: the real hook logs all 20 hand-read poll loops as would-deny and none of their re-issues" {
	run ev check d4_pollloop repro --ref "$FX4"
	[ "$status" -eq 0 ]
	[[ "$output" == *"PASS repro"* ]] || false
	[[ "$output" == *"logged as poll-loop would-deny: 20/20 · re-issues judged again: 0/20 ok"* ]] || false
}

@test "D4 negative control: a hook whose loop pattern misses until-loops FAILs the reproduction; a silent hook is no verdict" {
	sed 's/(while|until|for)\[\[:space:\]\]/(while|for)[[:space:]]/' "$REPO/hooks/subagent-long-bash-shadow.sh" >"$BATS_TEST_TMPDIR/narrow.sh"
	if cmp -s "$REPO/hooks/subagent-long-bash-shadow.sh" "$BATS_TEST_TMPDIR/narrow.sh"; then false; fi
	# predicate.py runs a hook as `/bin/bash <file>`, never by path, so the stand-in needs no #! line
	printf 'exit 0\n' >"$BATS_TEST_TMPDIR/silent.sh"
	run python3 - "$D4" "$FX4" "$BATS_TEST_TMPDIR" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import flow, predicate
cases, meta = flow.import_cases(sys.argv[2])
predicate.HOOK = sys.argv[3] + "/narrow.sh"
ok, rows = flow.check_repro(cases, meta)
print("narrow", ok, rows[0])
predicate.HOOK = sys.argv[3] + "/silent.sh"
ok, rows = flow.check_population(cases, meta)
print("silent", ok, rows[0])
PY
	[ "$status" -eq 0 ]
	[[ "$output" == *"narrow False hand-read originals logged as poll-loop would-deny: "*"/20"*"FAIL"* ]] || false
	[[ "$output" == *"silent False PARK population: no verdict — positive control not logged"* ]] || false
}

# Planted 7-day windows. Each call: a 600 s foreground poll loop that held 400 s, next request
# re-wrote 400k of a 400k context. Gross per call at write 0.20 = 400000 x 0.20 / 1e6 = 0.08 pp.
#   25 calls -> 25/wk (>= 20) and 2.0 pp/wk (>= 1.0)        PASS
#   10 calls -> 10/wk (< 20), 0.8 pp/wk                      PARK on both thresholds
#   25 calls wrapped in `timeout 200` -> exempt, 0 would-deny PARK
plant() {
	python3 - "$1" "$2" "$3" <<'PY'
import json, sys
path, n, wrap = sys.argv[1], int(sys.argv[2]), sys.argv[3] == "exempt"
with open(path, "w") as fh:
    for i in range(n):
        cmd = "until test -f /tmp/none-%d; do sleep 10; done" % i
        if wrap:
            cmd = "timeout 200 bash -c '%s'; echo rc=$?" % cmd
        fh.write(json.dumps(dict(case_id="p%03d" % i, tool_use_id="p%03d" % i, agent_id="a%03d" % i,
                                 sid="s%d" % (i % 5), acct=("next", "next2", "next3", "next4")[i % 4],
                                 t=1.0e9 + i, cmd=cmd, timeout_ms=600000, bg=False, rt=400.0, gap=410.0,
                                 ctx=400000, ncw=400000, reb=True, is_wait=True)) + "\n")
with open(path + ".meta", "w") as fh:
    json.dump(dict(schema=2, flow="d4_pollloop", start=1.0e9, end=1.0e9 + 7 * 86400, window_s=7 * 86400), fh)
PY
}

@test "D4 population gate: >= 20 would-deny/wk pricing >= 1.0 pp/wk PASSes; fewer, or exempt, PARKs (exit 1)" {
	plant "$BATS_TEST_TMPDIR/pass.jsonl" 25 plain
	ev build d4_pollloop --from "$BATS_TEST_TMPDIR/pass.jsonl" >/dev/null
	run ev check d4_pollloop --population
	[ "$status" -eq 0 ]
	[[ "${lines[0]}" == "PASS population: 25.0 non-exempt would-deny calls/wk (need >= 20), pricing 2.000 pp/wk gross at write 0.20 (need >= 1.0), over the last 7.0 d" ]] || false

	plant "$BATS_TEST_TMPDIR/few.jsonl" 10 plain
	ev build d4_pollloop --from "$BATS_TEST_TMPDIR/few.jsonl" >/dev/null
	run ev check d4_pollloop --population
	[ "$status" -eq 1 ]
	[[ "${lines[0]}" == "PARK population: 10.0 non-exempt would-deny calls/wk (need >= 20), pricing 0.800 pp/wk"* ]] || false
	[[ "$output" == *"approved, no target population"* ]] || false

	plant "$BATS_TEST_TMPDIR/ex.jsonl" 25 exempt
	ev build d4_pollloop --from "$BATS_TEST_TMPDIR/ex.jsonl" >/dev/null
	run ev check d4_pollloop --population
	[ "$status" -eq 1 ]
	[[ "${lines[0]}" == "PARK population: 0.0 non-exempt would-deny calls/wk"* ]] || false
	[[ "$output" == *"25 exempt by inner timeout · 0 would-deny"* ]] || false
}

@test "D4 population gate fails closed: no build, or an empty one, is PARK with exit 1, never PASS" {
	run ev check d4_pollloop --population
	[ "$status" -eq 1 ]
	[[ "$output" == "PARK population: no data"* ]] || false
	: >"$BATS_TEST_TMPDIR/empty.jsonl"
	printf '{"window_s": 604800}' >"$BATS_TEST_TMPDIR/empty.jsonl.meta"
	ev build d4_pollloop --from "$BATS_TEST_TMPDIR/empty.jsonl" >/dev/null
	run ev check d4_pollloop --population
	[ "$status" -eq 1 ]
	[[ "$output" == "PARK population: no data — the build holds 0 cases"* ]] || false
	[[ "$output" != *PASS* ]] || false
}

@test "D4 flow: on the fixture, perfect foresight bounds the hook call by call, never-deny = 0, the hook sees no outcome" {
	ev build d4_pollloop --from "$FX4" >/dev/null
	ev split d4_pollloop >/dev/null
	run ev check d4_pollloop oracle
	[ "$status" -eq 0 ]
	[[ "$output" == *"calls where the hook beats PF: 0 ok"* ]] || false
	run ev check d4_pollloop null
	[ "$status" -eq 0 ]
	run ev check d4_pollloop truncation
	[ "$status" -eq 0 ]
	[[ "$output" == *"0 cases leak · verdicts changed by scrambling outcomes: 0 of "* ]] || false
}
