#!/usr/bin/env bats
# research-program-intake — wave B2 of docs/plans/RESEARCH_PROGRAM_BUILD.md (REPORT.md §8 item 8):
# scripts/research-kit/intake.py, stage 1 of a program. Each case plants one bad input and asserts the
# refusal, so a green run is evidence the guard can fail:
#   - registration goes through gate.sh (the registry's only writer) and A1's resolver reads it;
#   - a numberless superlative never reaches the frame (§3.2 step 3);
#   - the contract page refuses before both §3.1 rulings, before a finite escape cost (question 10),
#     before a STRICTLY earlier vendor preflight (gate row 13), and on a dead lane (§3.8);
#   - a declined ruling leaves gate row 1 failing and the program closed (§3.1);
#   - a frame the intake fills and maps fails gate row 1 on the signature alone.

setup() {
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/h"; mkdir -p "$HOME"   # hermetic: never the operator's live ~/
  I="$REPO/scripts/research-kit/intake.py"
  G="$REPO/scripts/research-kit/gate.sh"
  RP="$REPO/scripts/lib/research-program.sh"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/home" CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/home/programs.json"
  export CC_NOW="2026-10-01T12:00:00Z" CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  ROOT="$BATS_TEST_TMPDIR/repo"; mkdir -p "$ROOT"
  REC="$ROOT/docs/research/demo"
}

init_ok() {
  "$I" init --program demo --root "$ROOT" --profile lite \
    --deliverable "a daemon that loses 0 writes in 1000 trials" --intent "make it solid" --alias "the demo"
}

rulings_ok() {
  "$I" ruling --program demo --which definition-of-complete --adopt --quote "adopt it"
  "$I" ruling --program demo --which exemption --adopt --quote "adopt it too"
}

# preflight.json as courier.sh preflight writes it; $1 = its timestamp, $2 = google ok (True|False)
preflight() {
  mkdir -p "$CC_RESEARCH_HOME/demo"
  python3 - "$CC_RESEARCH_HOME/demo/preflight.json" "$1" "${2:-True}" <<'PY'
import json, sys
path, at, g = sys.argv[1], sys.argv[2], sys.argv[3] == "True"
json.dump({v: {"ok": (g if v == "google" else True), "model_id": v + "-model", "at": at,
               "error": None if (g or v != "google") else "login needs consent"}
           for v in ("anthropic", "frontier", "openai", "google")}, open(path, "w"))
PY
}

frame_field() {
  python3 -c "import json,sys; print(json.dumps(json.load(open('$REC/frame.json')).get(sys.argv[1])))" "$1"
}

row1_evidence() {
  "$G" run --program demo --json 2>/dev/null | python3 -c "
import json, sys
print('\n'.join(next(r for r in json.load(sys.stdin) if r['num'] == 1)['evidence']))"
}

@test "init registers through gate.sh, and wave A1's resolver reads the program from its root" {
  run init_ok
  [ "$status" -eq 0 ]
  [ "$(/bin/bash -c ". '$RP'; rp_resolve_cwd '$ROOT'")" = "demo registered" ]
  [ "$(frame_field profile)" = '"lite"' ]
  [ -f "$REC/budget.json" ]
}

@test "the frame skeleton carries every checklist row gate row 1 requires, all unmapped" {
  init_ok
  python3 - "$REC/frame.json" "$REPO" <<'PY'
import json, sys
sys.path[:0] = [sys.argv[2] + "/scripts/research-kit/lib", sys.argv[2] + "/scripts/lib"]
import gate_rows_a
fr = json.load(open(sys.argv[1]))
assert [m["fac"] for m in fr["fac_map"]] == gate_rows_a.FAC_IDS, fr["fac_map"]
assert all(m["row"] is None and m["na_reason"] is None for m in fr["fac_map"])
assert {m["frame"] for m in fr["reask_map"]} == {"deployed and live", "nothing can beat it", "no loose ends"}
PY
}

@test "a numberless superlative in the deliverable is refused and nothing is registered" {
  run "$I" init --program demo --root "$ROOT" --profile lite --deliverable "the best sync daemon" --intent x
  [ "$status" -eq 2 ]
  [[ "$output" == *"numberless superlative"* ]] || false
  [ ! -e "$CC_RESEARCH_REGISTRY" ]
  [ ! -e "$REC/frame.json" ]
}

@test "intake runs once: a second init over an existing frame is refused" {
  init_ok
  run init_ok
  [ "$status" -eq 2 ]
  [[ "$output" == *"runs once"* || "$output" == *"already registered"* ]]
}

row9_evidence() {
  "$G" run --program demo --json 2>/dev/null | python3 -c "
import json, sys
print('\n'.join(next(r for r in json.load(sys.stdin) if r['num'] == 9)['evidence']))"
}

@test "init's frame skeleton carries plan and topic_owner as null, the keys gate rows 8 and 9 read" {
  init_ok
  [ "$(frame_field plan)" = "null" ]
  [ "$(frame_field topic_owner)" = "null" ]
  python3 -c "import json,sys; fr=json.load(open(sys.argv[1])); assert 'plan' in fr and 'topic_owner' in fr" "$REC/frame.json"
}

@test "set --plan and --topic-owner alone write both keys, and gate row 9's lint finds the plan" {
  init_ok
  CC_RESEARCH_RECORDS="$REC" row9_evidence | grep -q "plan file None (frame.json \`plan\`) missing"
  mkdir -p "$REC/plan"; printf '# Plan\n\nship 0 regressions in 100 runs\n' > "$REC/plan/PLAN.md"
  run "$I" set --program demo --plan plan/PLAN.md --topic-owner "the operator, Chris"
  [ "$status" -eq 0 ]
  [ "$(frame_field plan)" = '"plan/PLAN.md"' ]
  [ "$(frame_field topic_owner)" = '"the operator, Chris"' ]
  ev="$(CC_RESEARCH_RECORDS="$REC" row9_evidence)"
  [[ "$ev" == *"not frozen"* ]] || false   # row 9 ran and reached past its lint
  [[ "$ev" != *"(frame.json \`plan\`) missing"* ]] || false
}

@test "set refuses a --plan that does not resolve, an empty or superlative --topic-owner, frame untouched" {
  init_ok
  before="$(shasum "$REC/frame.json")"
  run "$I" set --program demo --plan nope.md
  [ "$status" -eq 2 ]
  [[ "$output" == *"$REC/nope.md"* ]] || false
  run "$I" set --program demo --topic-owner "   "
  [ "$status" -eq 2 ]
  [[ "$output" == *"--topic-owner may not be empty"* ]] || false
  run "$I" set --program demo --topic-owner "the best owner"
  [ "$status" -eq 2 ]
  [[ "$output" == *"numberless superlative"* ]] || false
  # a valid flag beside a refused one writes nothing either
  run "$I" set --program demo --escape-cost-days 3 --plan nope.md
  [ "$status" -eq 2 ]
  [ "$(shasum "$REC/frame.json")" = "$before" ]
}

@test "the contract page refuses before both §3.1 rulings are recorded" {
  init_ok
  "$I" ruling --program demo --which exemption --adopt --quote "yes"
  "$I" set --program demo --escape-cost-days 3
  preflight "2026-10-01T11:00:00Z"
  run "$I" contract-page --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"definition_of_complete"* ]] || false
  [ "$(frame_field contract_page_at)" = "null" ]
}

@test "question 10: an infinite or non-numeric escape cost is refused, and the page waits for a number" {
  init_ok; rulings_ok
  run "$I" set --program demo --escape-cost-days inf
  [ "$status" -eq 2 ]
  run "$I" set --program demo --escape-cost-days never
  [ "$status" -eq 2 ]
  preflight "2026-10-01T11:00:00Z"
  run "$I" contract-page --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"escape cost"* ]]
}

@test "gate row 13: the contract page refuses with no preflight, and with one not strictly earlier" {
  init_ok; rulings_ok
  "$I" set --program demo --escape-cost-days 3
  run "$I" contract-page --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"preflight has not run"* ]] || false
  preflight "$CC_NOW"
  run "$I" contract-page --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"strictly before"* ]] || false
  [ ! -e "$REC/CONTRACT.md" ]
}

@test "§3.8: a dead vendor lane at the preflight pauses the contract page with exit 3" {
  init_ok; rulings_ok
  "$I" set --program demo --escape-cost-days 3
  preflight "2026-10-01T11:00:00Z" False
  run "$I" contract-page --program demo
  [ "$status" -eq 3 ]
  [[ "$output" == *"DEAD LANE google"* ]] || false
  [ ! -e "$REC/CONTRACT.md" ]
}

@test "the contract page, once its inputs exist, pins the responding models and is hashed into the frame" {
  init_ok; rulings_ok
  "$I" set --program demo --escape-cost-days 3 --release-gap-days 15
  preflight "2026-10-01T11:00:00Z"
  run "$I" contract-page --program demo
  [ "$status" -eq 0 ]
  [ "$(frame_field contract_page_at)" = "\"$CC_NOW\"" ]
  python3 - "$REC" <<'PY'
import hashlib, json, sys
rec = sys.argv[1]
fr = json.load(open(rec + "/frame.json"))
page = open(rec + "/CONTRACT.md", "rb").read()
assert fr["contract_page_sha256"] == hashlib.sha256(page).hexdigest()
assert fr["reviewer_pins"] == {v: v + "-model" for v in ("anthropic", "frontier", "openai", "google")}
assert fr["reviewer_effort"] == {"anthropic": "xhigh", "frontier": "high", "openai": "xhigh"}, fr.get("reviewer_effort")
text = page.decode()
for s in ("Definition of complete", "fixing a counted escape", "3 research days", "hard cap 6",
          "ceiling (every loop at its cap) about 12 days", "upstream release",
          "anthropic xhigh, frontier high, openai xhigh"):
    assert s in text, s
PY
}

@test "§6.3: a typical total over 3x the measured research time puts the override on the page" {
  init_ok; rulings_ok
  "$I" set --program demo --escape-cost-days 3 --reference-days 1
  preflight "2026-10-01T11:00:00Z"
  "$I" contract-page --program demo
  grep -q "Override required" "$REC/CONTRACT.md"
  [ "$(frame_field reference_override)" = "true" ]
}

@test "§3.1: a declined ruling closes the program and gate row 1 still fails on it" {
  init_ok
  "$I" ruling --program demo --which exemption --adopt --quote "yes"
  run "$I" ruling --program demo --which definition-of-complete --decline --quote "no, keep 100.00 literal"
  [ "$status" -eq 0 ]
  run /bin/bash -c ". '$RP'; rp_is_active '$ROOT'"
  [ "$status" -eq 1 ]
  run "$I" ruling --program demo --which definition-of-complete --adopt --quote "ok fine"
  [ "$status" -eq 2 ]
  CC_RESEARCH_RECORDS="$REC" row1_evidence | grep -q "ruling not recorded: definition_of_complete"
}

@test "a ruling with no operator words is refused" {
  init_ok
  run "$I" ruling --program demo --which exemption --adopt --quote "  "
  [ "$status" -eq 2 ]
  [ "$(frame_field rulings)" = "{}" ]
}

@test "map refuses an unknown checklist row and an ambiguous mapping" {
  init_ok
  run "$I" map --program demo --fac FAC-99 --row K-1
  [ "$status" -eq 2 ]
  run "$I" map --program demo --fac FAC-01 --row K-1 --na "both"
  [ "$status" -eq 2 ]
  run "$I" map --program demo --frame "no loose ends"
  [ "$status" -eq 2 ]
}

@test "lint is gate row 1 without the signature: unmapped rows fail, a fully mapped frame fails only unsigned" {
  init_ok; rulings_ok
  run "$I" lint --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"checklist rows unmapped: FAC-01"* ]] || false
  for n in $(seq -w 1 33); do "$I" map --program demo --fac "FAC-$n" --na "fixture" > /dev/null; done
  "$I" map --program demo --frame "deployed and live" --axis V7
  "$I" map --program demo --frame "nothing can beat it" --excluded "not this one"
  "$I" map --program demo --frame "no loose ends" --excluded "covered by the gate"
  run "$I" lint --program demo
  [ "$status" -eq 0 ]
  ev="$(CC_RESEARCH_RECORDS="$REC" row1_evidence)"
  [ "$ev" = "the frame has never been signed (cc-signoff research:<slug>/frame, operator only)" ]
}

@test "status lists every stage-1 step and exits 1 until all are done" {
  init_ok
  run "$I" status --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"done  registered"* ]] || false
  [[ "$output" == *"TODO  contract page"* ]] || false
  [[ "$output" == *"TODO  topic owner confirmed"*"TODO  plan named"*"cc-signoff research:demo/frame"* ]] || false
}

# ── method v1.2 (ruling 1bf69e5c1775) ──────────────────────────────────────────────────────────

init_wide() { # <profile>: init with a wider profile; stdout and stderr both captured by `run`
  "$I" init --program demo --root "$ROOT" --profile "$1" \
    --deliverable "a daemon that loses 0 writes in 1000 trials" --intent "make it solid"
}

@test "v1.2: a non-lite profile is warned about at init with the measured reason; lite is not" {
  run init_wide standard
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING profile standard"*"against lite's"*"false material calls"* ]] || false
  # the warning is advice, not a refusal: the frame exists with the profile that was asked for
  [ "$(frame_field profile)" = '"standard"' ]
}

@test "v1.2: lite draws no profile warning" {
  run init_ok
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING profile"* ]]
}

@test "v1.2: the warning follows the measured file, so it stops when wider review starts to pay" {
  # planted inputs with no false calls, no downgrades and no fix-born holes: more reviewers only help
  printf '{"u_plan_mean":0.0,"fpp":0.0,"q":0.0,"omit_plan_mean":0.9,"fixborn_plan_median":0.0,"u_hi":0.2}\n' \
    > "$BATS_TEST_TMPDIR/params.json"
  CC_RESEARCH_PARAMS="$BATS_TEST_TMPDIR/params.json" run init_wide standard
  [ "$status" -eq 0 ]
  [[ "$output" != *"WARNING profile"* ]]
}

@test "v1.2: the frame is stamped method_version 1.2, which the v1.2 gate rows key on" {
  init_ok
  [ "$(frame_field method_version)" = '"1.2"' ]
}

@test "v1.2: the contract page prints the measured forecast and labels the assumed one a contrast" {
  init_ok; rulings_ok
  "$I" set --program demo --escape-cost-days 3
  preflight "2026-10-01T11:00:00Z"
  "$I" contract-page --program demo
  grep -q "at the measured inputs (method v1.2" "$REC/CONTRACT.md"
  grep -q "Contrast, the pre-calibration assumed inputs" "$REC/CONTRACT.md"
  ! grep -q "uncalibrated until the calibration run" "$REC/CONTRACT.md"
}

@test "v1.2: status counts a program in the build-certification states as registered" {
  init_ok
  python3 - "$CC_RESEARCH_REGISTRY" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for p in d["programs"]:
    p["state"] = "build-certifying"
json.dump(d, open(sys.argv[1], "w"))
PY
  run "$I" status --program demo
  [[ "$output" == *"done  registered"* ]] || false
}

# ── wave E3c: the contract page's ceiling carries the v1.2 additions (REPORT.md §11, §12) ─────────

contract_v12() { # <profile>: a contract page for a fresh program on that profile
  init_wide "$1" 2>/dev/null; rulings_ok
  "$I" set --program demo --escape-cost-days 3
  preflight "2026-10-01T11:00:00Z"
  "$I" contract-page --program demo
}

@test "E3c: a v1.2 lite page adds the §12 yield ceiling (5.25 d) and the §11 Stage 9 budget to the ceiling" {
  contract_v12 lite
  grep -q "yield ceiling: up to 3 extra stage budgets on each of stages 3 and 5, 5.25 agent-days (§12)" "$REC/CONTRACT.md"
  grep -q "Stage 9 (built-artifact certification): 1 agent-day budget, 1.5 at the §6.5 overrun line (§11)" "$REC/CONTRACT.md"
  grep -q "ceiling with the v1.2 additions about 18.75 days (12 + 5.25 + 1.5)" "$REC/CONTRACT.md"
  grep -q "at least 24 hours of soak, elapsed time outside this ceiling" "$REC/CONTRACT.md"
}

@test "E3c: standard prices 12 days of yield ceiling and a 2-day Stage 9, as §12 and §11 print them" {
  contract_v12 standard
  grep -q "stages 3 and 5, 12 agent-days (§12)" "$REC/CONTRACT.md"
  grep -q "Stage 9 (built-artifact certification): 2 agent-day budget, 3 at the §6.5 overrun line (§11)" "$REC/CONTRACT.md"
  grep -q "ceiling with the v1.2 additions about 43 days (28 + 12 + 3)" "$REC/CONTRACT.md"
}

@test "E3c: a frame signed under 1.1 keeps the §6.1 ceiling alone" {
  init_ok; rulings_ok
  "$I" set --program demo --escape-cost-days 3
  python3 - "$REC/frame.json" <<'PY'
import json, sys
fr = json.load(open(sys.argv[1])); fr.pop("method_version", None); json.dump(fr, open(sys.argv[1], "w"))
PY
  preflight "2026-10-01T11:00:00Z"
  "$I" contract-page --program demo
  grep -q "ceiling (every loop at its cap) about 12 days" "$REC/CONTRACT.md"
  ! grep -q "v1.2 additions" "$REC/CONTRACT.md"
}
