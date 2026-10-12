#!/usr/bin/env bats
# research-kit-gate — scripts/research-kit/gate.sh, the REPORT.md §3.10 gate (rows 1-15, plus row 16:
# rounds and stage time against their caps, §10 item 17, and row 17: an honest stop), the freeze that
# sets the registry to certifying (§10 item 1), and the render a completeness turn relays.
#
# One known-good program (tests/fixtures/research-kit/build_good.py) passes all 17 rows and
# certifies. Every other test restores it and plants ONE defect, then asserts that the named row
# turns FAIL: "every gate row has a planted-input test that must fail" (REPORT.md §3.10).

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$CC_NOW" > "$BATS_FILE_TMPDIR/now"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  mkdir -p "$W"
  "$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$W" > "$BATS_FILE_TMPDIR/records-path"
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  export CC_RESEARCH_ROUTER="$W/router.sh"
  export CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
}

# rowstat <n>: the status of gate row n on this run.
rowstat() {
  "$G" run --program demo --consent-sealed-read --json 2>/dev/null | /usr/bin/python3 -c "import json,sys; print([r['status'] for r in json.load(sys.stdin) if r['num'] == $1][0])"
}
# rowtext <n>: the evidence lines of row n.
rowtext() {
  "$G" run --program demo --consent-sealed-read --json 2>/dev/null | /usr/bin/python3 -c "import json,sys; print('\n'.join([r for r in json.load(sys.stdin) if r['num'] == $1][0]['evidence']))"
}
# jedit <file under REC> <python statement over d>: edit a JSON record in place.
jedit() {
  /usr/bin/python3 -c "import json; p='$REC/$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"
}
state() { /usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_REGISTRY'))['programs'][0]['state'])"; }

@test "the known-good program passes all 19 rows, certifies, and the registry reads certified" {
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -cE '^ ?[0-9]+\. .* PASS$')" -eq 19 ]
  [ "$(state)" = "certified" ]
  [ -f "$REC/cert/CERT-v1.json" ]
}

@test "render relays the certificate's state lines and writes nothing" {
  "$G" run --program demo --consent-sealed-read
  before="$(find "$W" -type f -newer "$REC/cert/CERT-v1.json" | wc -l)"
  run "$G" --render --program demo
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "Research: demo version 1. CERTIFIED"* ]] || false
  [[ "$output" == *"Signed frame: 100.00% closed."* ]] || false
  [[ "$output" == *"uncalibrated"* ]] || false
  [ "$(find "$W" -type f -newer "$REC/cert/CERT-v1.json" | wc -l)" -eq "$before" ]
}

@test "render reads the records live: a counted escape after the issue moves the After-signoff line" {
  "$G" run --program demo --consent-sealed-read
  run "$G" --render --program demo
  [ "$status" -eq 0 ]
  before="$output"
  [[ "$output" == *"After signoff: 0 material changes"* ]] || false
  ts="$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"id":"CR-80","cause":"operator_new","status":"parked","justification":"idea","ts":"%s"}\n' "$ts" \
    >> "$REC/changes.jsonl"
  run "$G" --render --program demo
  [ "$output" = "$before" ]
  printf '{"id":"CR-90","cause":"escape","challenge":"CH-90","justification":"planted","ts":"%s"}\n' "$ts" \
    >> "$REC/changes.jsonl"
  run "$G" --render --program demo
  [ "$status" -eq 0 ]
  [ "$output" != "$before" ]
  [[ "$output" == *"After signoff: 1 material change (1 escape; forecast about"* ]] || false
  [[ "$output" != *"unchanged since"* ]] || false
}

@test "render never prints a literal take-backs 0" {
  "$G" run --program demo --consent-sealed-read
  run "$G" --render --program demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"take-backs 0"* ]] || false
  [[ "$(cat "$REC/cert/CERT-v1.md")" != *"take-backs 0"* ]] || false
}

@test "render: a residual row renders the Residuals and Scheduled checks lines; none renders neither" {
  "$G" run --program demo --consent-sealed-read
  run "$G" --render --program demo
  [[ "$output" == *"Residuals: 1 declared (elapsed-time 1)"* ]] || false
  [[ "$output" == *"Scheduled checks: 1 production or elapsed-time check with owner and date (next due "* ]] || false
  # the due date is build_good.py's residual row, read back rather than restated here
  due="$(jq -r .due "$REC/residual.jsonl")"
  [[ "$output" == *"(next due $due)"* ]] || false
  : > "$REC/residual.jsonl"
  run "$G" --render --program demo
  [[ "$output" != *"Residuals:"* ]] || false
  [[ "$output" != *"Scheduled checks:"* ]] || false
  printf '{"id":"P-fresh-PR-1","at":"%s","exit":0}\n' "$CC_NOW" >> "$REC/probes.jsonl"
  run "$G" --render --program demo
  [[ "$output" == *"Scheduled checks: last freshness run "*", no verdict changed"* ]] || false
  # a sweep drift flip counts until it is triaged refuted (raised from a crashed re-check, 2026-10-11)
  printf '{"id":"CH-70","raised_by":"sweep","kind":"drift","premise":"PR-1","triage":"pending"}\n' >> "$REC/challenges.jsonl"
  run "$G" --render --program demo
  [[ "$output" == *"last freshness run "*", 1 verdict changed"* ]] || false
  printf '{"id":"CH-70","triage":"refuted"}\n' >> "$REC/challenges.jsonl"
  run "$G" --render --program demo
  [[ "$output" == *"last freshness run "*", no verdict changed"* ]] || false
}

@test "render: Built and Live read unknown, and Calibration counts the calibration rows" {
  "$G" run --program demo --consent-sealed-read
  run "$G" --render --program demo
  [[ "$output" == *"Built – · Live – · Calibration: none measured (uncalibrated)"* ]] || false
  printf '{"plan":"a"}\n{"plan":"b"}\n' > "$CC_RESEARCH_CALIBRATION"
  run "$G" --render --program demo
  [[ "$output" == *"Calibration: 2 plans measured"* ]] || false
  [[ "$output" != *"uncalibrated"* ]] || false
}

@test "an uncertified program renders as not certified" {
  run "$G" render --program demo
  [[ "$output" == "Research: demo — registered; not certified."* ]]
}

@test "§10 item 1: freeze sets the registry to certifying" {
  run "$G" freeze --program demo
  [ "$status" -eq 0 ]
  [ "$(state)" = "certifying" ]
}

# round_due: re-open review in the known-good records (its last round becomes not quiet, so the stop
# rule has not fired and certification round 4 is due), committed as freeze requires.
round_due() {
  jedit rounds/3/matrix.json "d['quiet']=False; d['new_material']=1"
  git -C "$W/repo" commit -qam "round 3 not quiet"
}
cr_rows() { /usr/bin/python3 -c "import json; print(' '.join(a['id'] + ':' + a['state'] for a in json.load(open('$CC_RESEARCH_HOME/activities.json'))['activities'] if a['kind'] == 'certification-round'))" 2>/dev/null; }
set_state() { /usr/bin/python3 -c "import json; p='$CC_RESEARCH_REGISTRY'; d=json.load(open(p)); d['programs'][0]['state']='$1'; json.dump(d, open(p, 'w'))"; }

@test "freeze opens exactly one certification-round activity when a round is due, and a re-freeze reuses it" {
  round_due
  run "$G" freeze --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"certification activity open: ACT-demo-1"* ]] || false
  git -C "$W/repo" add -A; git -C "$W/repo" commit -qm "fix cycle"   # a re-freeze pins a committed snapshot
  run "$G" freeze --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"certification activity open: ACT-demo-1"* ]] || false
  [ "$(cr_rows)" = "ACT-demo-1:open" ]
}

@test "freeze opens no certification-round activity once the stop rule has fired" {
  run "$G" freeze --program demo
  [ "$status" -eq 0 ]
  [[ "$output" != *"certification activity"* ]] || false
  [ -z "$(cr_rows)" ]
}

@test "cert-activity: refused unless certifying, frozen and a round is due; idempotent when it opens" {
  round_due
  run "$G" cert-activity --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"'registered', not certifying"* ]] || false
  set_state certified
  run "$G" cert-activity --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"'certified', not certifying"* ]] || false
  set_state certifying
  mv "$REC/freeze.json" "$REC/freeze.json.off"
  run "$G" cert-activity --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"no freeze.json"* ]] || false
  mv "$REC/freeze.json.off" "$REC/freeze.json"
  [ -z "$(cr_rows)" ]
  run "$G" cert-activity --program demo
  [ "$status" -eq 0 ]
  [ "$output" = ACT-demo-1 ]
  run "$G" cert-activity --program demo
  [ "$status" -eq 0 ]
  [ "$output" = ACT-demo-1 ]
  [ "$(cr_rows)" = "ACT-demo-1:open" ]
}

@test "cert-activity: refused when no certification round is due (the stop rule has fired)" {
  set_state certifying
  run "$G" cert-activity --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"no certification round is due"*"stop rule has fired"* ]] || false
  [ -z "$(cr_rows)" ]
}

# ── the front-end return (REPORT.md §6.1, §6.5): gate.sh return-activity ─────────────────────────
# RED-proof (all four tests): on 931209017 gate.sh has no return-activity verb, so every call exits 2
# on argparse's "invalid choice" and no asserted id or refusal text is printed; activities.py also
# refuses the front-end-return kind there.

# many_holes [n]: round 1 found n material holes, so the estimate sits above 1.5 x the design point.
many_holes() { jedit rounds/1/matrix.json "d['new_material']=${1:-30}"; }
fer_rows() { /usr/bin/python3 -c "import json; print(' '.join(a['id'] + ':' + a.get('area', '-') + ':' + a['state'] for a in json.load(open('$CC_RESEARCH_HOME/activities.json'))['activities'] if a['kind'] == 'front-end-return'))" 2>/dev/null; }
ret() { "$G" return-activity --program demo --area "$1" --because "course c1; areas a1"; }

@test "return-activity: opens an area's return between rounds, closing the round's tag; names it again; blocks the next round; freeze closes it; the area never reopens" {
  round_due
  many_holes
  git -C "$W/repo" commit -qam "round 1 found many"
  "$G" freeze --program demo
  [ "$(cr_rows)" = "ACT-demo-1:open" ]
  run ret A1
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = "ACT-demo-2" ]
  [[ "$output" == *"certification activity closed for the return: ACT-demo-1"* ]] || false
  [ "$(cr_rows)" = "ACT-demo-1:closed" ]
  [ "$(fer_rows)" = "ACT-demo-2:A1:open" ]
  [ "$(/usr/bin/python3 -c "import json; a=json.load(open('$CC_RESEARCH_HOME/activities.json'))['activities'][-1]; print(a['because'], a['n_hat'] > 15, a['design_holes'], a['after_round'])")" = "course c1; areas a1 True 10 3" ]
  run ret A1
  [ "$status" -eq 0 ]
  [ "$output" = "ACT-demo-2" ]
  [ "$(fer_rows)" = "ACT-demo-2:A1:open" ]
  # no certification round, and so no round tag, while the return is open
  run "$G" cert-activity --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"a front-end return is open (ACT-demo-2)"* ]] || false
  [ "$(cr_rows)" = "ACT-demo-1:closed" ]
  git -C "$W/repo" add -A; git -C "$W/repo" commit -qm "the return's edits"   # a re-freeze pins a committed snapshot
  run "$G" freeze --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"front-end return closed by the re-freeze: ACT-demo-2"* ]] || false
  [[ "$output" == *"certification activity open: ACT-demo-3"* ]] || false
  [ "$(fer_rows)" = "ACT-demo-2:A1:closed" ]
  run ret A1
  [ "$status" -eq 2 ]
  [[ "$output" == *"'A1' already had its front-end return (ACT-demo-2)"* ]] || false
  [ "$(fer_rows)" = "ACT-demo-2:A1:closed" ]
}

@test "return-activity: refused when not certifying, outside the window between rounds, on a low estimate, and for a bad area or an empty reason" {
  run ret A1
  [ "$status" -eq 2 ]
  [[ "$output" == *"'registered', not certifying"* ]] || false
  set_state certifying
  run ret A1
  [ "$status" -eq 2 ]
  [[ "$output" == *"n_hat 1 is not above 1.5 x the lite design point 10"* ]] || false
  many_holes
  mkdir "$REC/rounds/4"   # round 4 has started
  run ret A1
  [ "$status" -eq 2 ]
  [[ "$output" == *"before the next one runs"* ]] || false
  rmdir "$REC/rounds/4"
  jedit rounds/3/matrix.json "d['closed']=False"   # round 3 is still running
  run ret A1
  [ "$status" -eq 2 ]
  [[ "$output" == *"before the next one runs"* ]] || false
  jedit rounds/3/matrix.json "d['closed']=True"
  run ret "a b"
  [ "$status" -eq 2 ]
  [[ "$output" == *"bad area name 'a b'"* ]] || false
  run "$G" return-activity --program demo --area A1 --because " "
  [ "$status" -eq 2 ]
  [[ "$output" == *"--because names the recorded course and areas decisions"* ]] || false
  [ -z "$(fer_rows)" ]
  # the control: with every refusal's cause removed, the same call opens
  run ret A1
  [ "$status" -eq 0 ]
  [ "$(fer_rows)" = "ACT-demo-1:A1:open" ]
}

@test "return-activity: the area cap is the profile's, 1 on lite and 3 on standard" {
  set_state certifying
  many_holes 40
  ret A1
  run ret A2
  [ "$status" -eq 2 ]
  [[ "$output" == *"used its 1 front-end return area(s) (A1)"* ]] || false
  jedit frame.json "d['profile']='standard'"
  ret A2
  ret A3
  run ret A4
  [ "$status" -eq 2 ]
  [[ "$output" == *"used its 3 front-end return area(s) (A1, A2, A3)"* ]] || false
  [ "$(fer_rows)" = "ACT-demo-1:A1:open ACT-demo-2:A2:open ACT-demo-3:A3:open" ]
}

# ── the signed profile switch of a running program (cc-signoff research:<slug>/profile/<name>) ────
# RED-proof: on 931209017 `profile` is not a signing action, so the fixture signer exits 2 and the
# round cap, the planned reviewers and the certificate stay on the frame's standard profile. The
# ceiling and budget lines hold on that commit too (nothing switched); their red is the mutant that
# reads kit.round_profile in cli_core.cmd_ceiling and budget_report (28 -> 12 days, 11.5 -> 4.25).
# The "unsigned" test also holds on that commit; its red is the mutant where kit.profile_switch takes
# the newest record whatever its verdict (the round cap reads 6 off the agent-written record).
# All three reds measured 2026-10-12.

SIGNER() { "$REPO/tests/fixtures/research-kit/fixture_signer.py" "$@"; }
standard_running() { # the known-good program, signed on standard, certifying, round 4 due
  jedit frame.json "d['profile']='standard'"
  jedit rounds/3/matrix.json "d['quiet']=False; d['new_material']=1"
  set_state certifying
}
rmax() { /usr/bin/python3 "$REPO/scripts/research-kit/estimate.py" forecast --program demo | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin)['r_max'])"; }
next_round() { /usr/bin/python3 -c "import sys; sys.path.insert(0, '$REPO/scripts/research-kit/lib'); import round as r
try:
    rid, slots, vonly, cap = r.plan_slots('demo', 'certification', 4, None); print(rid, len(slots), cap)
except r.kit.KitError as e:
    print('refused:', e)"; }
ceiling() { "$REPO/bin/cc-research" ceiling --program demo --json | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d['profile'], d['ceiling_days'])"; }

@test "profile switch: unsigned, the program stays on its frame's profile; an agent-written record is void and switches nothing" {
  standard_running
  [ "$(rmax)" = 8 ]   # min(round-1 p90 4 + 4, standard's hard cap 10)
  [ "$(next_round)" = "4 16 8" ]
  printf '{"action":"profile","target":"lite","from":"standard","after_round":3,"at":9e9,"pins":{},"provenance":{"claude_ancestor":false,"chain":["zsh","claude"]}}\n' \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  [ "$(rmax)" = 8 ]
  [ "$(next_round)" = "4 16 8" ]
  printf '{"action":"profile","target":"lite","from":"standard","after_round":3,"at":9e9,"pins":{}}\n' \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  [ "$(rmax)" = 8 ]
}

@test "profile switch: signed after round 3, rounds 4 on run on lite under R_max min(6, 3 + lite's cap), and the ceiling and stage budgets stay the frame's" {
  standard_running
  before="$(ceiling)"
  [ "$before" = "standard 28.0" ]
  budget_before="$("$REPO/bin/cc-research" budget --program demo --json | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d['profile'], sum(s['budget_days'] for s in d['stages'].values()))")"
  [ "$budget_before" = "standard 11.5" ]
  frame_before="$(shasum "$REC/frame.json")"
  run SIGNER research:demo/profile/lite --because "course c1: return then certify on lite"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SIGNED research:demo/profile/lite"* ]] || false
  [ "$(/usr/bin/python3 -c "import json; r=json.loads(open('$CC_RESEARCH_HOME/demo/signoff.jsonl').read().splitlines()[-1]); print(r['from'], r['after_round'], r['target'])")" = "standard 3 lite" ]
  [ "$(rmax)" = 6 ]
  [ "$(next_round)" = "4 8 6" ]
  [ "$(ceiling)" = "$before" ]
  [ "$("$REPO/bin/cc-research" budget --program demo --json | /usr/bin/python3 -c "import json,sys; d=json.load(sys.stdin); print(d['profile'], sum(s['budget_days'] for s in d['stages'].values()))")" = "$budget_before" ]
  [ "$(shasum "$REC/frame.json")" = "$frame_before" ]
  # one switch per program
  run SIGNER research:demo/profile/lite --because "again"
  [ "$status" -eq 2 ]
  [[ "$output" == *"the one profile switch per program is already signed"* ]] || false
}

@test "profile switch: the signature is refused without a reason, outside certifying, mid-round, to a wider profile, and past the new cap" {
  standard_running
  run SIGNER research:demo/profile/lite
  [ "$status" -eq 2 ]
  [[ "$output" == *"profile needs --because"* ]] || false
  run SIGNER research:demo/profile/full --because x
  [ "$status" -eq 2 ]
  [[ "$output" == *"full is not narrower than standard"* ]] || false
  run SIGNER research:demo/profile/tiny --because x
  [ "$status" -eq 2 ]
  [[ "$output" == *"'tiny' is not a profile"* ]] || false
  mkdir "$REC/rounds/4"
  run SIGNER research:demo/profile/lite --because x
  [ "$status" -eq 2 ]
  [[ "$output" == *"round 4 has already started on standard"* ]] || false
  rmdir "$REC/rounds/4"
  jedit rounds/3/matrix.json "d['closed']=False"
  run SIGNER research:demo/profile/lite --because x
  [ "$status" -eq 2 ]
  [[ "$output" == *"signed between rounds"* ]] || false
  jedit rounds/3/matrix.json "d['closed']=True"
  for n in 4 5 6; do   # six counted rounds: lite's hard cap leaves none to run
    mkdir "$REC/rounds/$n"
    /usr/bin/python3 -c "import json; m=json.load(open('$REC/rounds/3/matrix.json')); m['round']='$n'; m['seq']=$n; json.dump(m, open('$REC/rounds/$n/matrix.json', 'w'))"
  done
  run SIGNER research:demo/profile/lite --because x
  [ "$status" -eq 2 ]
  [[ "$output" == *"6 counted round(s) so far against lite's hard cap of 6"* ]] || false
  rm "$REC"/rounds/[456]/matrix.json; rmdir "$REC"/rounds/[456]
  set_state certified
  run SIGNER research:demo/profile/lite --because x
  [ "$status" -eq 2 ]
  [[ "$output" == *"demo is certified, not certifying"* ]] || false
  run grep -c '"action": "profile"' "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  [ "$output" = 0 ]
  # the control: back in the window, the same call signs
  set_state certifying
  run SIGNER research:demo/profile/lite --because x
  [ "$status" -eq 0 ]
}

@test "freeze is refused while lint shows an error, and the registry stays registered" {
  echo "This is the best design." >> "$REC/PLAN.md"
  git -C "$W/repo" commit -qam "plan"
  run "$G" freeze --program demo
  [ "$status" -eq 2 ]
  [ "$(state)" = "registered" ]
}

@test "a failing row blocks the certificate and the registry stays registered" {
  printf '{"id":"DR-1","status":"open"}\n' >> "$REC/decisions.jsonl"
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 1 ]
  [ "$(state)" = "registered" ]
  [ ! -e "$REC/cert/CERT-v1.json" ]
}

@test "row 1: a frame changed after it was signed fails as stale" {
  jedit frame.json 'd["version"] = 2'
  [ "$(rowstat 1)" = "FAIL" ]
  [[ "$(rowtext 1)" == *"STALE"* ]]
}

@test "row 1: a newer agent-written frame signature fails as void" {
  pin="$(/usr/bin/python3 -c "import json; print(json.loads(open('$CC_RESEARCH_HOME/demo/signoff.jsonl').readline())['pins']['frame.json'])")"
  printf '{"action":"frame","target":null,"at":9e9,"pins":{"frame.json":"%s"},"provenance":{"claude_ancestor":false,"chain":["zsh","claude"]}}\n' "$pin" \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  [[ "$(rowtext 1)" == *"VOID"* ]]
}

@test "row 1: a numberless superlative in an acceptance predicate fails" {
  jedit acceptance.json 'd["rows"][0]["predicate"] = "the best retry policy"'
  [ "$(rowstat 1)" = "FAIL" ]
}

@test "row 1: an unmapped checklist row fails" {
  jedit frame.json 'd["fac_map"] = [m for m in d["fac_map"] if m["fac"] != "FAC-17"]'
  [[ "$(rowtext 1)" == *"FAC-17"* ]]
}

@test "row 2: a census method whose re-run drops a member fails" {
  jedit census/callers.json 'd["methods"][1]["cmd"] = "echo a"'
  [ "$(rowstat 2)" = "FAIL" ]
}

@test "row 2: an empty grid cell fails" {
  jedit census/callers.json 'd["grid"] = {"cells": [{"row": "write", "col": "wrong-duration"}]}'
  [ "$(rowstat 2)" = "FAIL" ]
}

@test "row 3: a consulted source whose evidence is missing fails" {
  printf '{"id":"E-1","status":"consulted","evidence":["evidence/P-404"]}\n' > "$REC/sources.jsonl"
  [ "$(rowstat 3)" = "FAIL" ]
}

@test "row 4: a code premise held only by recall fails (E0, needs E2)" {
  printf '{"id":"PR-1","truth_lives_in":"code","verdict":"holds","probes":[],"load_bearing_for":["DR-1"],"origin":{"tier":"E1"}}\n' \
    > "$REC/premises.jsonl"
  [ "$(rowstat 4)" = "FAIL" ]
}

# RED-proof (K4, 2026-10-11): the pre-K4 row 4 compared DR-1's ruling with the premise's FOLDED ts,
# which the 10-04 re-check event moved past it, so it failed "PR-1 refuted but dependent DR-1 was
# never revised" although DR-1 was ruled after the refutation.
@test "row 4: a refuted premise's dependent is revised against the event that refuted it, not a later re-check" {
  printf '{"id":"PR-1","verdict":"refuted","refuted_by":"P-1","ts":"2026-10-02T00:00:00Z"}\n' >> "$REC/premises.jsonl"
  printf '{"id":"DR-1","status":"ruled","ts":"2026-10-03T00:00:00Z"}\n' >> "$REC/decisions.jsonl"
  printf '{"id":"PR-1","probes":["P-1","P-2"],"rechecked_by":"P-2","recheck_verdict":"refuted","ts":"2026-10-04T00:00:00Z"}\n' >> "$REC/premises.jsonl"
  printf '{"id":"PR-1","verdict":"refuted","why":"re-asserted","ts":"2026-10-05T00:00:00Z"}\n' >> "$REC/premises.jsonl"
  [ "$(rowstat 4)" = "PASS" ]
  # a NEW refutation (holds, then refuted again) after the ruling does ask for a fresh revision
  printf '{"id":"PR-1","verdict":"holds","ts":"2026-10-06T00:00:00Z"}\n{"id":"PR-1","verdict":"refuted","ts":"2026-10-07T00:00:00Z"}\n' >> "$REC/premises.jsonl"
  [[ "$(rowtext 4)" == *"PR-1 refuted but dependent DR-1 was never revised"* ]]
}

@test "row 5: an agent-ruled decision whose flip probe never ran computes 89 and fails" {
  printf '{"id":"DR-1","tally":{"premises":["PR-1"]}}\n' >> "$REC/decisions.jsonl"
  [[ "$(rowtext 5)" == *"agent-ruled at 89%"* ]]
}

@test "row 5: a typed conviction that the rule does not compute fails" {
  printf '{"id":"DR-1","conviction":95}\n' >> "$REC/decisions.jsonl"
  [[ "$(rowtext 5)" == *"typed, not computed"* ]]
}

@test "row 5: a reversible decision researched 3 times fails" {
  printf '{"id":"DR-1","runs_used":3}\n' >> "$REC/decisions.jsonl"
  [ "$(rowstat 5)" = "FAIL" ]
}

@test "row 6: an acceptance check that passes its known-bad fixture fails" {
  jedit acceptance.json 'd["rows"][0]["check_cmd"] = "true"'
  [[ "$(rowtext 6)" == *"cannot fail"* ]]
}

@test "row 7: an environment the doctor found but no probe crossed fails" {
  grep -v '"P-4"' "$REC/probes.jsonl" > "$REC/p.tmp"; mv "$REC/p.tmp" "$REC/probes.jsonl"
  [[ "$(rowtext 7)" == *"interactive-zsh never crossed"* ]]
}

@test "row 8: a record citing a /tmp path fails" {
  echo "see /tmp/notes.txt" >> "$REC/research.md"
  [ "$(rowstat 8)" = "FAIL" ]
}

@test "row 8: a research heading with no trace fails" {
  printf '\n## Untraced claim\n' >> "$REC/research.md"
  [[ "$(rowtext 8)" == *"untraced-claim"* ]]
}

@test "row 8: a private receipt whose cited span changed fails" {
  printf 'one\ntwo\n' > "$W/mem.md"
  h="$(printf 'one\ntwo' | shasum -a 256 | awk '{print $1}')"
  jedit frame.json "d['private_receipts'] = [{'path': '$W/mem.md', 'span': '1-2', 'sha256': '$h'}]"
  "$G" run --program demo --consent-sealed-read --json >/dev/null 2>&1 || true
  printf 'one\nTWO\n' > "$W/mem.md"
  [[ "$(rowtext 8)" == *"the cited span changed"* ]]
}

@test "row 9: a plan edited after the freeze fails" {
  echo "A late edit of 2 lines." >> "$REC/PLAN.md"
  [[ "$(rowtext 9)" == *"changed after the freeze"* ]]
}

@test "row 9: a plan citing a probe that never ran fails lint" {
  echo "Measured by P-77." >> "$REC/PLAN.md"
  [[ "$(rowtext 9)" == *"P-77"* ]]
}

@test "row 10: a premise re-check older than 24 hours fails" {
  CC_NOW="$(date -u -v+48H +%Y-%m-%dT%H:%M:%SZ)" run rowstat 10
  [ "$output" = "FAIL" ]
}

# RED-proof (2026-10-11): before kit.recheck_verdict, row 10 counted the crashed re-check as fresh
# and the first assertion read PASS.
@test "row 10: a re-check that crashed (exit 127, a traceback under exit 1) is not a re-check; a clean one is" {
  later="$(date -u -v+48H +%Y-%m-%dT%H:%M:%SZ)" at="$(date -u -v+47H +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"id":"P-9","kind":"live-read","closes":["PR-1"],"exit":127,"at":"%s"}\n' "$at" >> "$REC/probes.jsonl"
  printf '{"id":"P-10","kind":"live-read","closes":["PR-1"],"exit":1,"at":"%s"}\n' "$at" >> "$REC/probes.jsonl"
  mkdir -p "$REC/evidence/P-10"
  printf 'Traceback (most recent call last):\nModuleNotFoundError: No module named x\n' > "$REC/evidence/P-10/stderr"
  CC_NOW="$later" run rowstat 10
  [ "$output" = "FAIL" ]
  printf '{"id":"P-11","kind":"live-read","closes":["PR-1"],"exit":1,"at":"%s"}\n' "$at" >> "$REC/probes.jsonl"
  CC_NOW="$later" run rowstat 10
  [ "$output" = "PASS" ]
}

@test "row 11: a residual with a reason outside the allowed list fails" {
  printf '{"id":"RS-2","why_unreachable":"too-hard"}\n' >> "$REC/residual.jsonl"
  printf '{"id":"residual:RS-2","disposition":"done"}\n' >> "$REC/reconcile.jsonl"
  [ "$(rowstat 11)" = "FAIL" ]
}

@test "§10 item 7: a method-created residual renders FILED, not FAIL, and the gate still certifies" {
  printf '{"id":"RS-2","why_unreachable":"depth-cap","owner_wave":"B1","due":"%s","closing_probe":"P-9"}\n' "$(date -u -v+720H +%Y-%m-%d)" >> "$REC/residual.jsonl"
  printf '{"id":"residual:RS-2","disposition":"filed","ref":"RS-2"}\n' >> "$REC/reconcile.jsonl"
  [ "$(rowstat 11)" = "FILED" ]
  git -C "$W/repo" add -A
  git -C "$W/repo" commit -qm "residual"
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ]
}

@test "§10 item 7: a method-created residual with no closing probe fails" {
  printf '{"id":"RS-2","why_unreachable":"stub-validated","owner_wave":"B1","due":"%s"}\n' "$(date -u -v+720H +%Y-%m-%d)" >> "$REC/residual.jsonl"
  printf '{"id":"residual:RS-2","disposition":"filed","ref":"RS-2"}\n' >> "$REC/reconcile.jsonl"
  [ "$(rowstat 11)" = "FAIL" ]
}

@test "row 12: a dirty file in the deliverable repo that nothing reconciles fails" {
  echo x > "$W/repo/stray.txt"
  [[ "$(rowtext 12)" == *"unmapped: dirty:stray.txt"* ]]
}

@test "row 12 / §10 item 4: a program packet filed without --project fails" {
  id="$(/bin/bash "$REPO/bin/cc-decide" open --class C --what "pick a store" --option "a::x" --option "b::y" --conviction 70 --receipt "$REC/frame.json")"
  printf '{"id":"DR-1","packet":{"id":"%s","class":"C","due":"%s"}}\n' "$id" "$(date -u -v+1500H +%Y-%m-%dT%H:%M:%SZ)" >> "$REC/decisions.jsonl"
  [[ "$(rowtext 12)" == *"MALFORMED PACKET"* ]]
}

@test "row 13: a vendor preflight run after the contract page fails" {
  jedit frame.json 'd["contract_page_at"] = "2026-09-29T00:00:00Z"'
  [ "$(rowstat 13)" = "FAIL" ]
}

@test "row 13: a counted round whose reviewer answered as an unpinned model fails" {
  /usr/bin/python3 -c "import json; p='$REC/rounds/2/panels/r2p5.json'; d=json.load(open(p)); d['responding_model']='gpt-old'; json.dump(d, open(p,'w'))"
  [[ "$(rowtext 13)" == *"gpt-old"* ]]
}

@test "row 13: a counted round whose reviewer ran at an effort other than the frame's pin fails" {
  [ "$(rowstat 13)" = "PASS" ]
  jedit frame.json 'd["reviewer_effort"] = {"openai": "xhigh"}'
  [[ "$(rowtext 13)" == *"r2p5 ran at effort CLI default, pinned xhigh"* ]]
}

@test "row 13: a counted round with a dead vendor lane fails" {
  jedit rounds/3/matrix.json 'd["lanes"]["google"] = "dead"'
  [[ "$(rowtext 13)" == *"dead vendor lane"* ]]
}

@test "row 14: a relay test that failed without 'relay unstable' fails" {
  jedit rehearsal.json 'd["relay"]["passed"] = False'
  [ "$(rowstat 14)" = "FAIL" ]
}

@test "row 15: no router built fails" {
  CC_RESEARCH_ROUTER="" run rowtext 15
  [[ "$output" == *"router not built"* ]]
}

@test "row 15: a router that labels everything a work order fails on recall" {
  printf '#!/bin/bash\ncat >/dev/null\necho work-order\n' > "$W/router.sh"
  [[ "$(rowtext 15)" == *"recall 0/12"* ]]
}

@test "row 15: a router that errors on every prompt fails on the fallback rate" {
  printf '#!/bin/bash\nexit 1\n' > "$W/router.sh"
  [[ "$(rowtext 15)" == *"fallback rate 1.00"* ]]
}

@test "row 15: a router that answers two labels at once is a fallback" {
  printf '#!/bin/bash\ncat >/dev/null\necho completeness work-order\n' > "$W/router.sh"
  [ "$(rowstat 15)" = "FAIL" ]
}

# ── row 15, wave E1l (ruling a7fd5e2ee7c8 guard 1, 17aff7158fa6) ──────────────────────────────────
reads() { cat "$CC_RESEARCH_HOME/router-heldout/reads.jsonl" 2>/dev/null | wc -l | tr -d ' '; }

@test "row 15 (E1l): a gate run without --consent-sealed-read fails row 15, issues no certificate, and logs no read" {
  run "$G" run --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"15. Router"*"FAIL"* ]] || false
  [[ "$output" == *"no read consent"* ]] || false
  [ "$(reads)" = 0 ]
  [ ! -f "$REC/cert/CERT-v1.json" ]
}

@test "row 15 (E1l): when another row fails in the same run, row 15 runs last and reads nothing" {
  jedit rehearsal.json 'd["relay"]["passed"] = False'
  git -C "$REC" commit -qam "plant: relay failed"  # row 12 would otherwise see the plant as dirty
  run "$G" run --program demo --consent-sealed-read --json
  [ "$(printf '%s' "$output" | /usr/bin/python3 -c "import json,sys; print([r['status'] for r in json.load(sys.stdin) if r['num'] == 15][0])")" = FAIL ]
  [[ "$output" == *"row(s) 14 did not pass in this gate run"* ]] || false
  [ "$(reads)" = 0 ]
}

@test "row 15 (E1l): the router's kill switch fails row 15 without a read" {
  CC_RESEARCH_ROUTER=off run rowtext 15
  [[ "$output" == *"the router's kill switch"* ]] || false
  [ "$(reads)" = 0 ]
}

@test "row 15 (E1l): the certificate states the load bound beside RULE E1k's real-load figures" {
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ]
  [ "$(reads)" = 4 ]
  c="$(jq -r '.conditions["15"]' "$REC/cert/CERT-v1.json")"
  [[ "$c" == "load bound (ruling 17aff7158fa6), a stated condition of row 15: every routed item started at 1-min load <= 40 (highest 5.0); real-load companion, RULE E1k run 2 above load 150: hedge-on fallback 1/120, rows held with one call silent 0 "* ]] || false
  grep -qF "Row 15, stated condition: load bound (ruling 17aff7158fa6)" "$REC/cert/CERT-v1.md"
}

@test "row 16: more rounds than R_max fails" {
  jedit rounds/1/matrix.json 'd["forecast"]["p90"] = -2'
  [[ "$(rowtext 16)" == *"R_max is 2"* ]]
}

@test "row 16: a second valid extra round set fails" {
  for i in 1 2; do
    printf '{"action":"extra-round","target":null,"at":%s,"pins":{},"provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}\n' "$i" \
      >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  done
  [[ "$(rowtext 16)" == *"2 extra round sets"* ]]
}

@test "row 16: a stage past 1.5x its budget with no overrun packet fails; with one it is FILED" {
  jedit budget.json 'd["stages"]["4"] = {"started": "2026-09-29T00:00:00Z", "ended": "2026-09-30T14:00:00Z"}'
  [ "$(rowstat 16)" = "FAIL" ]
  jedit budget.json 'd["overrun_packets"] = {"4": "abc123"}'
  [ "$(rowstat 16)" = "FILED" ]
}

@test "row 16: a missing row is FAIL, never a silent pass" {
  run /usr/bin/python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/research-kit/lib'); sys.path.insert(0, '$REPO/scripts/lib')
import gate, gate_rows_b
gate_rows_b.ROWS = [f for f in gate_rows_b.ROWS if f.row[0] != 16]
print([r.status for r in gate.run_rows(gate.make_ctx('demo')) if r.num == 16][0])"
  [ "$output" = "FAIL" ]
}

@test "row 17: the round cap reached with one uncounted round fails, and no certificate is issued" {
  jedit rounds/1/matrix.json 'd["forecast"]["p90"] = -1'
  jedit rounds/2/matrix.json 'd["counted"] = False; d["quiet"] = False; d["lanes"]["google"] = "dead"'
  git -C "$REC" commit -qam "plant: round 2 lost"  # row 12 would otherwise see the plant as dirty
  [[ "$(rowtext 17)" == *"1 lost round(s) (2)"* ]] || false
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -ne 0 ]
  # row 17 and row 15, which reads nothing once another row failed (wave E1l)
  [ "$(printf '%s\n' "$output" | grep -cE ' FAIL$')" -eq 2 ]
  [[ "$output" == *"17. "*" FAIL"* ]] || false
  [[ "$output" == *"row(s) 17 did not pass in this gate run"* ]] || false
  [ ! -f "$REC/cert/CERT-v1.json" ]
  [ "$(state)" != "certified" ]
}

@test "row 17: rounds that ended dry pass despite a lost round, and the certificate states it separately" {
  cp -Rp "$REC/rounds/3" "$REC/rounds/4"
  jedit rounds/4/matrix.json 'd["round"] = "4"; d["seq"] = 4'
  jedit rounds/2/matrix.json 'd["counted"] = False; d["quiet"] = False; d["lanes"]["google"] = "dead"'
  git -C "$REC" add rounds
  git -C "$REC" commit -qm "plant: round 2 lost, round 4 quiet"
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ]
  run "$G" --render --program demo
  [[ "${lines[0]}" == *"stopped after 2 quiet rounds; 1 round lost to a dead lane and not counted (round 2)"* ]] || false
}

@test "a valid operator reopen after the certificate sets the registry back to registered" {
  "$G" run --program demo --consent-sealed-read
  [ "$(state)" = "certified" ]
  printf '{"action":"reopen","target":null,"at":9e9,"pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}\n' \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  run "$G" run --program demo --consent-sealed-read
  [[ "$output" == *"REOPENED"* ]]
}

@test "an agent-written reopen does nothing" {
  "$G" run --program demo --consent-sealed-read
  printf '{"action":"reopen","target":null,"at":9e9,"pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["claude"]}}\n' \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  run "$G" run --program demo --consent-sealed-read
  [[ "$output" != *"REOPENED"* ]]
}
