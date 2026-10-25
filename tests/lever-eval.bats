#!/usr/bin/env bats
# lever-eval — the hillclimb eval kernel and the D3 keepalive offline eval (USAGE_LEVERS § W7+ S7a).
#
# Subjects: tools/lever-evals/lib/hc.py (split, seal, decide, approval, leak check, rounds),
# bin/cc-lever-eval (the CLI's exit codes and refusals), tools/lever-evals/d3_keepalive/ (the
# policy replay and its checks).
#
# THE ASSERTION THIS SUITE EXISTS FOR is the D3 reproduction: the replay, run through
# hooks/lib/idle_gap.py outcome(), must land within ±5% of recompute.out's engine check (as coded
# 3.79 / 2.67, R2 busy2 5.07 / 4.23 pp/wk). It runs on the committed reference fixture
# (tests/fixtures/lever-eval-d3-g2.jsonl.gz: the reviewer's G2.json, reduced to the fields the
# replay reads, sid hashed), so it needs neither ~/.claude/hillclimb/_imports nor live transcripts.
# Its negative control drops one account from the fixture and requires the same check to FAIL:
# without it, a check that always printed PASS would satisfy test 6 too.
#
# decide()'s expected verdicts are the plan's truth table (§3 "Hillclimb loop"), written out here,
# never read back from hc.py.
# RED-proof (2026-10-24, scratch copy): k_min() + 1 in policy.py → test 8's oracle check FAILs
# (123 gaps where literal beats perfect foresight); the fixture minus next4 → test 7's repro FAILs.
# HOME is a fixture, so recompute.out reads as absent and the targets
# come from flow.TARGETS; the CLI is run as `python3 <file>` (no #! exec per call).

setup() {
	export HOME="$BATS_TEST_TMPDIR/home"
	mkdir -p "$HOME"
	export CC_HILLCLIMB_DIR="$BATS_TEST_TMPDIR/hc"
	export CC_LEVER_ROUNDS_LOG="$BATS_TEST_TMPDIR/rounds.jsonl"
	REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
	CLI="$REPO/bin/cc-lever-eval"
	FX="$REPO/tests/fixtures/lever-eval-d3-g2.jsonl.gz"
	LIB="$REPO/tools/lever-evals/lib"
}

ev() { python3 "$CLI" "$@"; }

# a 2,500-gap slice of the fixture, so the round tests bootstrap in seconds
small_flow() {
	python3 -c 'import gzip,sys; L=gzip.open(sys.argv[1],"rt").readlines()[:2500]; open(sys.argv[2],"w").writelines(L)' \
		"$FX" "$BATS_TEST_TMPDIR/small.jsonl"
	ev build d3_keepalive --from "$BATS_TEST_TMPDIR/small.jsonl" >/dev/null
	ev split d3_keepalive >/dev/null
}

approve() {
	local sha
	sha="$(ev harness-sha d3_keepalive)"
	ev approve-harness d3_keepalive --confirm "${sha:0:12}" >/dev/null
}

@test "decide(): the plan's full truth table, boundaries included" {
	run python3 - "$LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import hc
# (train, nf_train, test_point, test_lo, nf_test, min_act) -> verdict
T = [
    ((2.0, 1.0, 1.5, 0.1, 1.0, 1.0), "KEEP"),
    ((2.0, 1.0, 1.0, 0.1, 1.0, 1.0), "KEEP"),          # point == MIN_ACT keeps (>=)
    ((1.0, 1.0, 1.5, 0.1, 1.0, 1.0), "NOT-MERGED"),    # train == NF is not "train > NF"
    ((2.0, 1.0, 1.5, 0.0, 1.0, 1.0), "REVERT"),        # CI lower == 0 is not > 0: train up, test flat
    ((2.0, 1.0, 0.9, 0.1, 1.0, 1.0), "REVERT"),        # below MIN_ACT: train up, test flat
    ((2.0, 1.0, 0.0, -0.5, 1.0, 1.0), "REVERT"),       # train up, test flat
    ((-1.1, 1.0, 5.0, 4.0, 1.0, 1.0), "REVERT"),       # train below -NF, however good test is
    ((0.5, 1.0, -1.1, -2.0, 1.0, 1.0), "REVERT"),      # test below -NF
    ((-1.0, 1.0, -1.0, -2.0, 1.0, 1.0), "NOT-MERGED"), # exactly -NF is not below it
    ((0.5, 1.0, 5.0, 4.0, 1.0, 1.0), "NOT-MERGED"),    # test great, train flat: never KEEP
    ((20.0, 1.0, 9.9, 1.0, 1.0, 10.0), "REVERT"),      # points flow: 9.9 < MIN_ACT 10
    ((20.0, 1.0, 10.0, 1.0, 1.0, 10.0), "KEEP"),
]
bad = [(a, want, hc.decide(*a)[0]) for a, want in T if hc.decide(*a)[0] != want]
print("rows=%d bad=%r" % (len(T), bad))
PY
	[ "$status" -eq 0 ]
	[ "$output" = "rows=12 bad=[]" ]
}

@test "next_action(): STALL after 3 non-KEEP edit rounds, streak reset by KEEP or STALL, CONFIRM at 6" {
	run python3 - "$LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import hc
V = lambda *vs: [dict(verdict=v) for v in vs]
T = [
    (V(), "EDIT"),
    (V("NOT-MERGED", "REVERT"), "EDIT"),
    (V("NOT-MERGED", "REVERT", "NOT-MERGED"), "STALL"),
    (V("KEEP", "REVERT", "REVERT", "NOT-MERGED"), "STALL"),
    (V("REVERT", "REVERT", "KEEP", "REVERT", "REVERT"), "EDIT"),
    (V("REVERT", "REVERT", "REVERT", "STALL"), "EDIT"),
    (V("REVERT", "REVERT", "REVERT", "STALL", "REVERT", "KEEP"), "CONFIRM"),
]
bad = [(r, w, hc.next_action(r)) for r, w in T if hc.next_action(r) != w]
print("rows=%d bad=%r" % (len(T), bad))
PY
	[ "$status" -eq 0 ]
	[ "$output" = "rows=7 bad=[]" ]
}

@test "split: test iff sha1(case_id) % 5 == 0, identical across rebuilds, test half sealed 0400" {
	ev build d3_keepalive --from "$FX" >/dev/null
	run ev split d3_keepalive
	[ "$status" -eq 0 ]
	sha1="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["test_sha"])' "$output")"
	d="$CC_HILLCLIMB_DIR/d3_keepalive"
	[ "$(stat -f '%Lp' "$d/test.sealed.jsonl")" = "400" ]
	run python3 - "$d" <<'PY'
import hashlib, json, sys
d = sys.argv[1]
ids = lambda f: [json.loads(l)["case_id"] for l in open(d + "/" + f)]
tr, te = ids("train.jsonl"), ids("test.sealed.jsonl")
rule = lambda c: int(hashlib.sha1(c.encode()).hexdigest(), 16) % 5 == 0
print(len(tr), len(te), sum(map(rule, tr)), sum(not rule(c) for c in te))
PY
	[ "$status" -eq 0 ]
	[ "$output" = "9371 2323 0 0" ]
	CC_HILLCLIMB_DIR="$BATS_TEST_TMPDIR/hc2" ev build d3_keepalive --from "$FX" >/dev/null
	CC_HILLCLIMB_DIR="$BATS_TEST_TMPDIR/hc2" run ev split d3_keepalive
	[ "$status" -eq 0 ]
	[ "$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["test_sha"])' "$output")" = "$sha1" ]
}

@test "seal: test rows refused without --unseal, to the analyzer, and once tampered" {
	small_flow
	run ev score d3_keepalive --candidate '{"min_ctx_k": 50}' --split test
	[ "$status" -eq 4 ]
	[[ "$output" == *"sealed"* ]] || false
	run ev failures d3_keepalive --split test
	[ "$status" -eq 4 ]
	run ev score d3_keepalive --candidate '{"min_ctx_k": 50}' --split test --unseal
	[ "$status" -eq 0 ]
	f="$CC_HILLCLIMB_DIR/d3_keepalive/test.sealed.jsonl"
	chmod 600 "$f"
	sed -i '' '$d' "$f"
	run ev score d3_keepalive --candidate '{"min_ctx_k": 50}' --split test --unseal
	[ "$status" -eq 4 ]
	[[ "$output" == *"does not match split.json"* ]]
}

@test "split refuses an account whose test share is out of band (stratification is checked)" {
	run python3 - "$LIB" "$BATS_TEST_TMPDIR/skew.jsonl" <<'PY'
import hashlib, json, sys
sys.path.insert(0, sys.argv[1])
import hc
# 40 cases of one account that all hash to train: a 0% test share
ids, i = [], 0
while len(ids) < 40:
    c = "s:%d" % i
    if int(hashlib.sha1(c.encode()).hexdigest(), 16) % 5:
        ids.append(c)
    i += 1
with open(sys.argv[2], "w") as fh:
    for c in ids:
        fh.write(json.dumps(dict(case_id=c, acct="next", sid=c)) + "\n")
PY
	[ "$status" -eq 0 ]
	mkdir -p "$CC_HILLCLIMB_DIR/d3_keepalive"
	cp "$BATS_TEST_TMPDIR/skew.jsonl" "$CC_HILLCLIMB_DIR/d3_keepalive/cases.jsonl"
	run ev split d3_keepalive
	[ "$status" -eq 2 ]
	[[ "$output" == *"not stratified by account: next test share 0.000 of 40"* ]] || false
	[ ! -e "$CC_HILLCLIMB_DIR/d3_keepalive/test.sealed.jsonl" ]
}

@test "D3 reproduction: replay through idle_gap.outcome() lands within ±5% of recompute.out" {
	run ev check d3_keepalive repro --ref "$FX"
	[ "$status" -eq 0 ]
	[[ "$output" == "PASS repro"* ]] || false
	for want in "literal low: replay 3.7862" "literal high: replay 2.6654" \
		"r2_busy low: replay 5.0724" "r2_busy high: replay 4.2330"; do
		[[ "$output" == *"$want"* ]] || false
	done
	[[ "$output" == *"receipt absent; targets from flow.TARGETS"* ]]
}

@test "D3 reproduction negative control: the same check FAILS on a fixture missing one account" {
	python3 -c 'import gzip,sys; open(sys.argv[2],"w").writelines(l for l in gzip.open(sys.argv[1],"rt") if "\"next4\"" not in l)' \
		"$FX" "$BATS_TEST_TMPDIR/no4.jsonl"
	run ev check d3_keepalive repro --ref "$BATS_TEST_TMPDIR/no4.jsonl"
	[ "$status" -eq 1 ]
	[[ "$output" == "FAIL repro"* ]]
}

@test "checks: perfect foresight >= every policy gap by gap, never-wake = 0, A/A in band, no future reads" {
	ev build d3_keepalive --from "$FX" >/dev/null
	ev split d3_keepalive >/dev/null
	run ev check d3_keepalive all --ref "$FX"
	[ "$status" -eq 0 ]
	for c in repro oracle null aa served-model truncation; do
		[[ "$output" == *"PASS $c"* ]] || false
	done
	[[ "$output" != *FAIL* ]] || false
	[ "$(grep -c 'gaps where policy beats PF: 0 ok' <<<"$output")" -eq 12 ]
}

@test "truncation: busy/watch are read from job intervals AT the wake time a candidate tries" {
	run python3 - "$REPO/tools/lever-evals/d3_keepalive" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import policy
g = dict(acct="next", sid="s", stop=1000.0, ctx=300000, prev="prompt",
         jobs=[[3000.0, None, "bash"], [500.0, 2500.0, "watch"]])
early, late = policy.DecisionView(g, 2000.0), policy.DecisionView(g, 4300.0)
print(early["busy2"], early["watch2"], late["busy2"], late["watch2"])
ref = dict(g, busy2=True, watch2=False)
del ref["jobs"]
try:
    policy.DecisionView(ref, 1000.0 + 1800)["busy2"]
    print("readable")
except policy.TruncationError:
    print("refused")
PY
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "False True True False" ]
	[ "${lines[1]}" = "refused" ]
}

@test "leak check: a shared 8-gram is caught, a 7-gram overlap is not" {
	run python3 - "$LIB" <<'PY'
import sys
sys.path.insert(0, sys.argv[1])
import hc
case = "please wake the session only when its own background job is still running now"
print(hc.leak_check("x the session only when its own background job is y", [case]))
print(hc.leak_check("the session only when its own background zzz", [case]))
PY
	[ "$status" -eq 0 ]
	[ "${lines[0]}" = "['session only when its own background job is', 'the session only when its own background job']" ]
	[ "${lines[1]}" = "[]" ]
}

@test "approval: no round before approve-harness; --confirm must name the current sha" {
	small_flow
	run ev round d3_keepalive --candidate '{"min_ctx_k": 50}'
	[ "$status" -eq 4 ]
	[[ "$output" == *"not approved"*"approve-harness d3_keepalive --confirm"* ]] || false
	run ev approve-harness d3_keepalive --confirm 000000000000
	[ "$status" -eq 4 ]
	[ ! -e "$CC_HILLCLIMB_DIR/d3_keepalive/state.json" ]
	approve
	run ev round d3_keepalive --candidate '{"min_ctx_k": 50}'
	[ "$status" -eq 0 ]
}

@test "approval is void once a harness file changes" {
	t="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$t/bin" "$t/hooks/lib" "$t/tools"
	cp "$CLI" "$t/bin/"
	cp "$REPO/hooks/lib/idle_gap.py" "$t/hooks/lib/"
	cp -R "$REPO/tools/lever-evals" "$t/tools/"
	CLI="$t/bin/cc-lever-eval"
	small_flow
	approve
	printf '# edited\n' >>"$t/tools/lever-evals/d3_keepalive/policy.py"
	run ev round d3_keepalive --candidate '{"min_ctx_k": 50}'
	[ "$status" -eq 4 ]
	[[ "$output" == *"not approved"* ]]
}

@test "round: one change per round, a row in state and lever-rounds.jsonl, STALL scores nothing" {
	small_flow
	approve
	run ev round d3_keepalive --candidate '{"min_ctx_k": 50, "skip_watcher": false}'
	[ "$status" -eq 4 ]
	[[ "$output" == *"one change per round"* ]] || false
	run ev round d3_keepalive --candidate '{}'
	[ "$status" -eq 4 ]
	run ev round d3_keepalive --candidate '{"min_ctx_k": 50}'
	[ "$status" -eq 0 ]
	v="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["verdict"])' "$output")"
	[[ " KEEP REVERT NOT-MERGED " == *" $v "* ]] || false
	# one kind=round row and one kind=offline row (the incumbent's test-half pp/wk, ADVANCE's offline sign)
	[ "$(wc -l <"$CC_LEVER_ROUNDS_LOG")" -eq 2 ]
	[ "$(python3 -c 'import json,sys; print(" ".join(sorted(json.loads(l)["kind"] for l in open(sys.argv[1]))))' "$CC_LEVER_ROUNDS_LOG")" = "offline round" ]
	[ "$(awk '{ print length($0) }' "$CC_LEVER_ROUNDS_LOG" | sort -n | tail -1)" -le 2048 ]
	# seed two more non-KEEP rounds: the next round must be a STALL that scores no candidate
	python3 - "$CC_HILLCLIMB_DIR/d3_keepalive/state.json" <<'PY'
import json, sys
p = sys.argv[1]
st = json.load(open(p))
st["rounds"] = [dict(n=i + 1, verdict="REVERT") for i in range(3)]
json.dump(st, open(p, "w"))
PY
	run ev round d3_keepalive --candidate '{"min_ctx_k": 80}'
	[ "$status" -eq 0 ]
	[ "$(python3 -c 'import json,sys; r=json.loads(sys.argv[1]); print(r["verdict"], r["candidate"], "test" in r)' "$output")" = "STALL None False" ]
}

@test "eval context: CC_LEVER_EXCLUDE=1 and the /tmp/lev-eval cwd, inherited by children" {
	run python3 - "$LIB" <<'PY'
import os, subprocess, sys
sys.path.insert(0, sys.argv[1])
import hc
os.environ.pop("CC_LEVER_EXCLUDE", None)
hc.enter_eval_context()
out = subprocess.run(["/bin/sh", "-c", 'echo "$CC_LEVER_EXCLUDE $(pwd -P)"'], capture_output=True, text=True).stdout.strip()
print(out)
PY
	[ "$status" -eq 0 ]
	[ "$output" = "1 $(cd /tmp/lev-eval && pwd -P)" ]
}

# S10 built d2_lean, so the refusal is pinned on d1_successor (wave S9); when S9 lands it flips the
# last unbuilt flow and this test goes with it
@test "a flow whose wave has not landed is refused with exit 3, never stubbed" {
	run ev check d1_successor
	[ "$status" -eq 3 ]
	[[ "$output" == *"not built yet (wave S9)"* ]]
}
