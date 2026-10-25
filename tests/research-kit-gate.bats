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
  # the class-C open at row 12 files as a daemon would: from a session cc-decide requires --ceiling
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID
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
  [[ "$output" == *"round 3 owes no settle step"* ]] || false
  [ -z "$(cr_rows)" ]
}

# RED-proof (2026-10-12): cert-activity refused whenever no round was due, so a last round closed at
# the stop with a re-pass still owed could never settle under the research block.
@test "cert-activity: after the stop, a last round that still owes a settle step re-opens the activity settle-only" {
  set_state certifying
  jedit rounds/3/matrix.json "d['kappa']={'materiality':0.1,'n':4,'below':0.7,'repass':False,'unstable':False}"
  run "$G" cert-activity --program demo
  [ "$status" -eq 0 ]
  [ "${lines[${#lines[@]}-1]}" = ACT-demo-1 ]
  [[ "$output" == *"settle-only: round 3 owes rating re-pass (round.sh repass)"* ]] || false
  [ "$(cr_rows)" = "ACT-demo-1:open" ]
  [ "$(/usr/bin/python3 -c "import json; print(json.load(open('$CC_RESEARCH_HOME/activities.json'))['activities'][0]['settle_round'])")" = 3 ]
  jedit rounds/3/matrix.json "d['kappa']['repass']=True"
  run "$G" cert-activity --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"no certification round is due"*"round 3 owes no settle step"* ]] || false
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

# The command bound (gate_rows_a.run_cmd): a timeout is no verdict, never the check's exit.
# RED-proof (2026-10-16): on ecbaf8ba4 run_cmd timed out at a fixed bound and returned 124, so the slow
# method below failed row 2 as "exited 124", the hung one read "exited 124" with no "gave no verdict",
# and a known-bad fixture that hung counted as failing as it should, leaving row 6 PASS.
@test "row 2: a census method slower than the base bound but inside the cap passes on the larger bound" {
  jedit census/callers.json 'd["methods"][1]["cmd"] = "sleep 2; " + d["methods"][1]["cmd"]'
  export CC_RESEARCH_GATE_TIMEOUT=1 CC_RESEARCH_GATE_TIMEOUT_CAP=15
  [ "$(rowstat 2)" = "PASS" ]
}

@test "row 2: a census method that never finishes fails as no verdict, not as an exit" {
  jedit census/callers.json 'd["methods"][1]["cmd"] = "sleep 60; " + d["methods"][1]["cmd"]'
  export CC_RESEARCH_GATE_TIMEOUT=1 CC_RESEARCH_GATE_TIMEOUT_CAP=2
  out="$(rowtext 2)"
  [[ "$out" == *"method y \`sleep 60; printf"*"gave no verdict: timed out after 2 s at load1 "* ]] || false
  [[ "$out" != *"exited"* ]] || false
}

@test "row 6: a known-bad fixture that times out is no verdict, not a correct failure" {
  jedit acceptance.json 'd["rows"][0]["check_cmd"] = "grep -q ok \"$FIXTURE\" || sleep 60"'
  export CC_RESEARCH_GATE_TIMEOUT=1 CC_RESEARCH_GATE_TIMEOUT_CAP=2
  [ "$(rowstat 6)" = "FAIL" ]
  [[ "$(rowtext 6)" == *"on its known-bad fixture, \`grep -q ok"*"gave no verdict"* ]] || false
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

# ── decision 55e7da1e7311 (2026-10-16): a premise only the build or a third party can raise ─────────
# nyt_premise [verdict] [truth] [DR-2 blocks_waves json]: PR-2, load-bearing for DR-2 and below its
# level (E0), with DR-2 a well-formed operator-carried set narrowing in B3, and a fresh re-check
# probe P-5 that closes PR-2 but is not joined (row 10 reads it; row 4's level does not).
nyt_premise() {
  printf '{"id":"PR-2","truth_lives_in":"%s","verdict":"%s","probes":[],"load_bearing_for":["DR-2"],"recheck_cmd":"true","origin":{"tier":"E0"}}\n' \
    "${2:-target-env}" "${1:-partial}" >> "$REC/premises.jsonl"
  printf '{"id":"DR-2","question":"store","status":"carried","ruled_by":"operator","options":[{"label":"do-nothing"},{"label":"use-what-exists"},{"label":"k2c"}],"set":{"members":[{"id":"a","feasibility_probe":"P-1"},{"id":"b","feasibility_probe":"P-2"}],"narrowing_probe":{"wave":"B3","owner":"lead","due":"2099-01-01"},"revision_budget_h":4},"blocks_waves":%s}\n' \
    "${3:-[\"B4\"]}" >> "$REC/decisions.jsonl"
  printf '{"id":"P-5","kind":"read","env":{"id":"agent-shell"},"closes":["PR-2"],"exit":0,"n":1,"stdin":"/dev/null","negative_control":{"ran":true,"reported_refutation":true},"raw":"evidence/P-5/","at":"%s"}\n' \
    "$CC_NOW" >> "$REC/probes.jsonl"
  mkdir -p "$REC/evidence/P-5" && echo ok > "$REC/evidence/P-5/stdout"
}
# nyt_file [python statements over r]: the residual and reconcile rows `cc-research premise file`
# writes for PR-2 (owner wave B3, awaits build), edited by $1 before they are written.
nyt_file() {
  /usr/bin/python3 -c "
import json
r = {'id': 'R-NYT-PR-2', 'why_unreachable': 'not-yet-true', 'premise': 'PR-2', 'awaits': 'build',
     'owner_wave': 'B3', 'owner': 'lead', 'due': '2099-01-01T00:00:00Z', 'closing_probe': 'P-9',
     'blocks_waves': [], 'why': 'K2c is built in B3', 'ts': '$CC_NOW'}
${1:-pass}
open('$REC/residual.jsonl', 'a').write(json.dumps(r) + '\n')
open('$REC/reconcile.jsonl', 'a').write(json.dumps({'id': 'residual:' + r['id'], 'disposition': 'filed', 'ref': r['id']}) + '\n')"
}
# row_now <n>: row n's status then its evidence, by calling the row itself (no whole gate run).
row_now() {
  /usr/bin/python3 -c "
import sys
sys.path[:0] = ['$REPO/scripts/research-kit/lib', '$REPO/scripts/lib', '$REPO/scripts/research-kit']
import gate, gate_rows_a, gate_rows_b
fn = getattr(gate_rows_a, 'row$1', None) or getattr(gate_rows_b, 'row$1')
r = fn(gate.make_ctx('demo'))
print(r.status); print('\n'.join(r.evidence))"
}

# RED-proof (2026-10-16): on the base kit row 4 has no FILED path and row 11 refuses 'not-yet-true'
# as a reason, so the filed premise below still FAILs both rows and the gate cannot certify.
@test "row 4 / decision 55e7da1e7311: a below-level premise fails until filed not-yet-true, then renders FILED; the gate certifies and schedules it" {
  nyt_premise
  [ "$(rowstat 4)" = "FAIL" ]
  nyt_file
  out="$(row_now 4)"
  [ "$(head -1 <<<"$out")" = "FILED" ] || { echo "$out"; false; }
  [[ "$out" == *"FILED PR-2: at E0, needs E5; not yet true until B3 (build), owner lead, due 2099-01-01T00:00:00Z, closing probe P-9"* ]] || false
  [[ "$out" == *"1 premise(s) filed not-yet-true"* ]] || false
  out="$(row_now 11)"
  [ "$(head -1 <<<"$out")" = "FILED" ] || { echo "$out"; false; }
  [[ "$out" == *"R-NYT-PR-2: not-yet-true, premise PR-2 awaits build, owner B3"* ]] || false
  git -C "$W/repo" add -A
  git -C "$W/repo" commit -qm "filed premise"
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(state)" = "certified" ]
  run "$G" --render --program demo
  [[ "$output" == *"Scheduled checks: 1 production or elapsed-time check and 1 filed not-yet-true premise check with owners and dates"* ]] || { echo "$output"; false; }
}

# RED-proof (2026-10-16): the base kit reads the superseded filing too, so row 4 fails its past due,
# row 11 fails nothing but lists it as live, and the certificate counts 2 not-yet checks.
@test "a refiled premise (premise file --refile): rows 4 and 11 read the newest filing, the superseded one is history, and the certificate schedules one check; a broken chain fails row 11" {
  nyt_premise
  nyt_file "r['due'] = '2020-01-01'"
  nyt_file "r.update(id='R-NYT-PR-2-r2', supersedes='R-NYT-PR-2', due='2099-06-01')"
  printf '%s\n' '{"id":"R-NYT-PR-2","superseded_by":"R-NYT-PR-2-r2"}' >> "$REC/residual.jsonl"
  out="$(row_now 4)"
  [ "$(head -1 <<<"$out")" = "FILED" ] || { echo "$out"; false; }
  [[ "$out" == *"due 2099-06-01, closing probe P-9"* ]] || { echo "$out"; false; }
  out="$(row_now 11)"
  [ "$(head -1 <<<"$out")" = "FILED" ] || { echo "$out"; false; }
  [[ "$out" == *"R-NYT-PR-2: superseded by R-NYT-PR-2-r2 (history)"* ]] || { echo "$out"; false; }
  git -C "$W/repo" add -A
  git -C "$W/repo" commit -qm "refiled premise"
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$G" --render --program demo
  [[ "$output" == *"1 production or elapsed-time check and 1 filed not-yet-true premise check"* ]] || { echo "$output"; false; }
  [[ "$output" != *"2020-01-01"* ]] || { echo "$output"; false; }
  # a marker naming a row that does not refile it is a broken chain
  printf '%s\n' '{"id":"R-NYT-PR-2-r2","superseded_by":"R-NYT-PR-404"}' >> "$REC/residual.jsonl"
  out="$(row_now 11)"
  [[ "$out" == *"R-NYT-PR-2-r2: superseded, but R-NYT-PR-404 is not a refile of it for premise PR-2"* ]] || { echo "$out"; false; }
}

# RED-proof: the base kit prints none of these reasons (it fails every case as plain "below level").
@test "row 4: a filing that cannot carry its premise fails, naming why (each guard of decision 55e7da1e7311)" {
  check() { # check <reason> <setup...>: restore, plant, expect row 4 FAIL naming <reason>
    local want="$1"; shift
    rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
    "$@"
    out="$(row_now 4)"
    [ "$(head -1 <<<"$out")" = "FAIL" ] || { echo "[$want] $out"; return 1; }
    [[ "$out" == *"PR-2: filed not-yet-true, but "*"$want"* ]] || { echo "[$want] $out"; return 1; }
  }
  base() { nyt_premise "$@"; nyt_file; }
  check "the filing is missing owner" eval 'nyt_premise; nyt_file "r.pop(\"owner\")"'
  check "the filing is missing closing_probe" eval 'nyt_premise; nyt_file "r.pop(\"closing_probe\")"'
  check "is unparseable or already past" eval 'nyt_premise; nyt_file "r[\"due\"] = \"2020-01-01T00:00:00Z\""'
  check "a live-state premise is not raised by build" base partial live-state
  check "a code premise is not raised by build" base partial code
  check "verdict 'unknown'" base unknown
  check "dependent DR-2 is ruled by agent" eval 'base; printf "%s\n" "{\"id\":\"DR-2\",\"status\":\"ruled\",\"ruled_by\":\"agent\"}" >> "$REC/decisions.jsonl"'
  check "dependent DR-2 is open" eval 'base; printf "%s\n" "{\"id\":\"DR-2\",\"status\":\"open\"}" >> "$REC/decisions.jsonl"'
  check "dependent AM-1 is not a recorded decision" eval 'base; printf "%s\n" "{\"id\":\"PR-2\",\"load_bearing_for\":[\"DR-2\",\"AM-1\"]}" >> "$REC/premises.jsonl"'
  check "its recheck_cmd is missing or a prose note" eval 'base; printf "%s\n" "{\"id\":\"PR-2\",\"recheck_cmd\":\"Note: run it in B3\"}" >> "$REC/premises.jsonl"'
  check "owner wave B3 is descoped" eval 'base; printf "%s\n" "{\"id\":\"DR-9\",\"status\":\"descoped\",\"descoped_waves\":[\"B3\"]}" >> "$REC/decisions.jsonl"'
  # the skeptic's correction: a live owner wave is not enough when the dependent's waves are gone
  check "DR-2 narrowing wave B3 is descoped" eval 'nyt_premise; nyt_file "r[\"owner_wave\"] = \"B6\""; printf "%s\n" "{\"id\":\"KR-9\",\"status\":\"closed\",\"descoped_waves\":[\"B3\"]}" >> "$REC/known_rows.jsonl"'
  check "DR-2 blocks_waves B4 is descoped" eval 'base; printf "%s\n" "{\"id\":\"DR-9\",\"status\":\"descoped\",\"descoped_waves\":[\"B4\"]}" >> "$REC/decisions.jsonl"'
  check "no wave depends on it" base partial target-env '[]'
}

# RED-proof: the base kit's row 11 refuses 'not-yet-true' as a reason, so neither message appears.
@test "row 11: a not-yet-true row needs premise, owner and awaits; a premise refuted when filed is never fileable; a holding premise below level is" {
  nyt_premise
  nyt_file "r.pop('premise'); r.pop('owner'); r.pop('awaits')"
  out="$(row_now 11)"
  [ "$(head -1 <<<"$out")" = "FAIL" ]
  [[ "$out" == *"R-NYT-PR-2: not-yet-true residual missing premise, owner, awaits"* ]] || { echo "$out"; false; }
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  nyt_premise
  printf '{"id":"PR-2","verdict":"refuted","refuted_by":"P-5","ts":"2026-01-01T00:00:00Z"}\n' >> "$REC/premises.jsonl"
  nyt_file
  out="$(row_now 11)"
  [ "$(head -1 <<<"$out")" = "FAIL" ]
  [[ "$out" == *"R-NYT-PR-2: premise PR-2 was refuted when filed"* ]] || { echo "$out"; false; }
  # a premise that holds but below its level is the same bet as a partial one, and is filed
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  nyt_premise holds
  nyt_file
  [ "$(row_now 4 | head -1)" = "FILED" ]
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

# holes.jsonl is append-only and records vendor text verbatim (truememory-2-0 H-3-008, 2026-10-13: a blind
# verifier's suggested probe ran on a scratch copy under /tmp). Only the fields the lead writes are scanned.
@test "row 8: /tmp inside a verifier's probe, a rater's note or a blind reviewer's claim in holes.jsonl passes" {
  [ "$(rowstat 8)" = "PASS" ]
  printf '%s\n' \
    '{"id":"H-1","event":"verify","round":1,"verification":{"status":"CONFIRMED","probe":"cp -R a /tmp/f1probe/c1","consequence":"ran under /tmp/x/","read":{"path":"PLAN.md","quote":"see /tmp/y/"},"by":"courier verifier"}}' \
    '{"id":"H-1","event":"rate","round":1,"materiality":{"level":"MATERIAL","note":"repro in /tmp/z/"}}' \
    '{"id":"H-1","event":"raise","round":1,"claim":"writes to /tmp/q/","title":"/tmp/t/","locus":{"path":"PLAN.md","quote":"/tmp/l/"},"raised_by":{"blind":true,"panel":"r1p1"}}' \
    >> "$REC/holes.jsonl"
  [ "$(rowstat 8)" = "PASS" ]
}

@test "row 8: /tmp in a lead-written holes.jsonl field (evidence, a split-off claim) still fails" {
  printf '%s\n' '{"id":"H-1","event":"verify","verification":{"status":"CONFIRMED","against":"real","by":"lead","evidence":["/tmp/proof.txt"]}}' >> "$REC/holes.jsonl"
  [[ "$(rowtext 8)" == *"holes.jsonl: cites a path under /tmp"* ]] || false
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  printf '%s\n' '{"id":"H-1","event":"raise","round":1,"claim":"writes to /tmp/q/","split_from":"H-0"}' >> "$REC/holes.jsonl"
  [[ "$(rowtext 8)" == *"holes.jsonl: cites a path under /tmp"* ]]
}

# A relay trial records what the observed session said and ran, and `rehearse record` quotes it in its
# fails (truememory-2-0 trial 20, 2026-10-16: the session ran `ls -t /tmp/*handoff*` on its own). That
# text is behavior under test, not a path the program cites; every other field is still scanned.
@test "row 8: /tmp in a relay trial's reply or tools, or a fails line quoting them, passes" {
  [ "$(rowstat 8)" = "PASS" ]
  mkdir -p "$REC/evidence/rehearsal"
  for f in trials-1.jsonl practice.jsonl; do
    printf '%s\n' '{"prompt":"which decisions moved?","reply":"merged in /tmp/dr13-merge.X7Mj","replies":["see /tmp/a/"],"tools":["ls -t /tmp/*handoff*","Read"],"trial":1}' \
      >> "$REC/evidence/rehearsal/$f"
  done
  printf '%s\n' '{"event":"record","trials":3,"passed":false,"fails":["trial 1: it called ls -t /tmp/*handoff*, which reads no certificate"],"frames_typed":true}' \
    >> "$REC/rehearsal.jsonl"
  [ "$(rowstat 8)" = "PASS" ]
}

@test "row 8: /tmp in a relay trial's lead-written field, or a fails line that is not a trial's, still fails" {
  mkdir -p "$REC/evidence/rehearsal"
  printf '%s\n' '{"prompt":"read /tmp/brief.md","reply":"ok","tools":[],"trial":1}' >> "$REC/evidence/rehearsal/trials-1.jsonl"
  [[ "$(rowtext 8)" == *"trials-1.jsonl: cites a path under /tmp"* ]] || false
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  mkdir -p "$REC/evidence/rehearsal"
  printf '%s\n' '{"prompt":"p","reply":"ok","transcript":"/tmp/t.jsonl","practice":true}' >> "$REC/evidence/rehearsal/practice.jsonl"
  [[ "$(rowtext 8)" == *"practice.jsonl: cites a path under /tmp"* ]] || false
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  printf '%s\n' '{"event":"record","trials":3,"passed":false,"fails":["see /tmp/why.txt"],"frames_typed":true}' >> "$REC/rehearsal.jsonl"
  [[ "$(rowtext 8)" == *"rehearsal.jsonl: cites a path under /tmp"* ]] || false
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  mkdir -p "$REC/evidence/rehearsal"
  printf '%s\n' '{"prompt":"p","reply":"/tmp/x/","tools":[]}' >> "$REC/evidence/rehearsal/findings-1.jsonl"
  [[ "$(rowtext 8)" == *"findings-1.jsonl: cites a path under /tmp"* ]]
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

@test "row 9: a fix cycle before the verification-only cap round certifies the snapshot the cap round examined" {
  # REPORT.md §3.8: the cap round reviews at full width and never edits, so the snapshot it examined is
  # the last one examined. Rounds 1-2 saw the pre-fix snapshot; the cap round saw the frozen one.
  jedit rounds/1/matrix.json "d['snapshot_sha']='0'*40"
  jedit rounds/2/matrix.json "d['snapshot_sha']='0'*40"
  jedit rounds/3/matrix.json "d['verification_only']=True"
  [[ "$(rowtext 9)" != *"is not the one the last"* ]] || false
}

@test "row 9: a cap round that examined a snapshot older than the freeze still fails" {
  jedit rounds/3/matrix.json "d['verification_only']=True; d['snapshot_sha']='0'*40"
  [[ "$(rowtext 9)" == *"is not the one the last counted round examined"* ]] || false
}

# RED-proof (2026-10-12): row 9 failed every MATERIAL cap-round hole with no known row, so the re-find,
# the artifact and the seed catch below each failed it although round close counts none of them.
@test "row 9: a cap-round re-find of a held hole, an artifact and a seed catch need no known row; an unnamed real find still fails" {
  jedit rounds/3/matrix.json "d['verification_only']=True"
  echo '{"id":"KR-1","kind":"frame-omission","hole":"H-1","status":"open"}' > "$REC/known_rows.jsonl"
  hc() { printf '{"id":"%s","round":3,"verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"}%s}\n' "$1" "${2:-}" >> "$REC/holes.jsonl"; }
  hc H-3-001 ',"artifact":{"reason":"copy damage"}'
  hc H-3-002 ',"seed_match":"S-1"'
  hc H-3-003 ',"refind_of":"H-1"'
  hc H-3-004
  t="$(rowtext 9)"
  [[ "$t" == *"H-3-004: a cap-round or rehearsal find that is not a named known row"* ]] || false
  [[ "$t" != *"H-3-001"* && "$t" != *"H-3-002"* && "$t" != *"H-3-003"* ]] || false
}

# RED-proof (2026-10-18): kit.held_frame_omissions holds only OPEN rows, so once gate.sh run's
# close_delta_rows closed truememory-2-0's KR-06..21 under CERT-v2, row 9 failed eight round-6 re-finds
# of their holes (H-6-013 and seven more) and could never pass again; H-3-005 below failed the same way.
@test "row 9: a cap-round re-find of a hole whose row a frame-delta closed needs no known row; one of a row closed any other way still fails" {
  jedit rounds/3/matrix.json "d['verification_only']=True"
  jedit frame.json "d['known_rows_applied']=['KR-5','KR-6','KR-8']"
  mkdir -p "$REC/cert" && echo '{"cert":"CERT-v1"}' > "$REC/cert/CERT-v1.json"
  kr() { printf '{"id":"%s","kind":"frame-omission","hole":"%s","status":"closed","closed_by":"%s"}\n' "$1" "$2" "$3" >> "$REC/known_rows.jsonl"; }
  kr KR-5 H-5 CERT-v1   # the delta cycle closed it: its frame carries KR-5, CERT-v1 was issued
  kr KR-6 H-6 default   # the sweep closed it by its default, though the frame lists it
  kr KR-7 H-7 CERT-v1   # a certificate is named, but the frame never carried KR-7
  kr KR-8 H-8 CERT-v9   # the frame carries KR-8, but no CERT-v9 was issued
  hc() { printf '{"id":"%s","round":3,"verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL"},"refind_of":"%s"}\n' "$1" "$2" >> "$REC/holes.jsonl"; }
  hc H-3-005 H-5
  hc H-3-006 H-6
  hc H-3-007 H-7
  hc H-3-008 H-8
  t="$(rowtext 9)"
  [[ "$t" != *"H-3-005"* ]] || { echo "$t"; false; }
  for h in H-3-006 H-3-007 H-3-008; do
    [[ "$t" == *"$h: a cap-round or rehearsal find that is not a named known row"* ]] || { echo "$t"; false; }
  done
}

# Rehearsal finds (round.sh rehearsal-*, lib/rehearsal.py). RED-proof: before it, row 9 read only a
# rehearsal hole's level, so a find raised and never verified, or verified CONFIRMED and never rated,
# passed the gate unadjudicated (H-RH-3 and H-RH-4 below).
@test "row 9: a named rehearsal find passes; an unnamed MATERIAL one, and one never verified or never rated, fail" {
  hr() { printf '{"id":"%s","event":"raise","round":"rehearsal","source":"rehearsal"%s}\n' "$1" "${2:-}" >> "$REC/holes.jsonl"; }
  hr H-RH-1 ',"verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL","clause":"b"}'
  hr H-RH-2 ',"verification":{"status":"CONFIRMED"},"materiality":{"level":"MATERIAL","clause":"b"}'
  hr H-RH-3
  hr H-RH-4 ',"verification":{"status":"CONFIRMED"}'
  hr H-RH-5 ',"verification":{"status":"REFUTED"}'
  hr H-RH-6 ',"verification":{"status":"CONFIRMED"},"materiality":{"level":"REFINEMENT"}'
  echo '{"id":"KR-90","kind":"rehearsal","hole":"H-RH-1","applied_in_wave":"W1","blocks_waves":[],"status":"open"}' >> "$REC/known_rows.jsonl"
  t="$(rowtext 9)"
  [[ "$t" == *"H-RH-2: a cap-round or rehearsal find that is not a named known row"* ]] || false
  [[ "$t" == *"H-RH-3: a rehearsal find not yet verified (round.sh rehearsal-verify)"* ]] || false
  [[ "$t" == *"H-RH-4: a rehearsal find verified CONFIRMED but not rated (round.sh rehearsal-rate)"* ]] || false
  [[ "$t" != *"H-RH-1"* && "$t" != *"H-RH-5"* && "$t" != *"H-RH-6"* ]] || false
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

# A program session carries a session id, and cc-decide refuses a session's class-C open with no
# operator-only ceiling (ruling d610f8473106): gate_sweep's file-packet must pass --ceiling program.
@test "program packets: file-packet --class C from a session carries --ceiling program and succeeds" {
  printf '{"id":"DR-1","status":"carried","blocks_waves":["B1"]}\n' >> "$REC/decisions.jsonl"
  export CLAUDE_CODE_SESSION_ID="sess-program-1"
  run "$G" file-packet --program demo --decision DR-1 --class C --what "storage backend" --option "a::x" --option "b::y" \
    --conviction 70 --receipt "$REC/frame.json" --due "2099-01-01T00:00:00Z"
  [ "$status" -eq 0 ]
  id="$(printf '%s\n' "$output" | awk '{print $2}' | tail -n 1)"
  [ "$(jq -r '.ceiling' "$CC_DECISIONS_DIR/$id.json")" = "program" ]
  [ "$(jq -r '.session_sid' "$CC_DECISIONS_DIR/$id.json")" = "sess-program-1" ]
}

@test "row 13: a vendor preflight run after the contract page fails" {
  jedit frame.json 'd["contract_page_at"] = "2026-09-29T00:00:00Z"'
  [ "$(rowstat 13)" = "FAIL" ]
}

# Row 13 and the re-run preflight (2026-10-13, program truememory-2-0): every certification round
# needs a fresh preflight, and courier.sh preflight rewrites preflight.json whole, so the snapshot
# always post-dates the contract page. The evidence is the append-only history and the page itself.
# pfrun <at> [google ok]: one courier.sh preflight run, as preflight.json and a history line.
pfrun() {
  /usr/bin/python3 - "$CC_RESEARCH_HOME/demo" "$1" "${2:-True}" <<'PY'
import json, sys
d, at, g = sys.argv[1], sys.argv[2], sys.argv[3] == "True"
pins = {"anthropic": "claude-opus-5-5", "frontier": "claude-fable-5-1", "openai": "gpt-x", "google": "gemini-x"}
run = {v: {"ok": g or v != "google", "model_id": m, "at": at} for v, m in pins.items()}
json.dump(run, open(d + "/preflight.json", "w"))
open(d + "/preflights.jsonl", "a").write(json.dumps({"ts": at, "lanes": run}) + "\n")
PY
}
# page <at> [tamper]: CONTRACT.md with its vendor preflight lines dated <at>, its hash pinned in the frame.
page() {
  /usr/bin/python3 - "$REC" "$1" "${2:-}" <<'PY'
import hashlib, json, sys
rec, at, tamper = sys.argv[1], sys.argv[2], sys.argv[3]
pins = {"anthropic": "claude-opus-5-5", "frontier": "claude-fable-5-1", "google": "gemini-x", "openai": "gpt-x"}
page = "# Contract page — demo\n\n## Vendor preflight (responding model ids, pinned for the program)\n\n" + "".join(
    f"- {v}: live {m} at {at}\n" for v, m in pins.items()) + "\nReviewer effort: none pinned\n"
fr = json.load(open(rec + "/frame.json"))
fr["contract_page_sha256"] = hashlib.sha256(page.encode()).hexdigest()
json.dump(fr, open(rec + "/frame.json", "w"))
open(rec + "/CONTRACT.md", "w").write(page.replace("2026", "2025") if tamper else page)
PY
}

@test "row 13: an all-live preflight in the history before the contract page passes after later re-runs" {
  jedit frame.json 'd["contract_page_at"] = "2026-10-05T00:00:00Z"'
  pfrun "2026-10-04T00:00:00Z"
  pfrun "2026-10-06T00:00:00Z"
  [ "$(rowstat 13)" = "PASS" ]
}

@test "row 13: a history run before the contract page with a dead lane is no evidence" {
  jedit frame.json 'd["contract_page_at"] = "2026-10-05T00:00:00Z"'
  pfrun "2026-10-04T00:00:00Z" False
  pfrun "2026-10-06T00:00:00Z"
  [[ "$(rowtext 13)" == *"did not run before the contract page"* ]]
}

@test "row 13: a contract page that preceded every recorded preflight still fails" {
  jedit frame.json 'd["contract_page_at"] = "2026-10-05T00:00:00Z"'
  pfrun "2026-10-06T00:00:00Z"
  pfrun "2026-10-07T00:00:00Z"
  [[ "$(rowtext 13)" == *"did not run before the contract page"* ]]
}

@test "row 13: with no history, the hash-pinned contract page's own all-live preflight lines are the evidence" {
  jedit frame.json 'd["contract_page_at"] = "2026-10-05T00:00:00Z"'
  pfrun "2026-10-06T00:00:00Z"
  rm "$CC_RESEARCH_HOME/demo/preflights.jsonl"
  page "2026-10-04T00:00:00Z"
  [ "$(rowstat 13)" = "PASS" ]
}

@test "row 13: a contract page whose hash does not match the frame is no evidence and fails" {
  jedit frame.json 'd["contract_page_at"] = "2026-10-05T00:00:00Z"'
  pfrun "2026-10-06T00:00:00Z"
  rm "$CC_RESEARCH_HOME/demo/preflights.jsonl"
  page "2026-10-04T00:00:00Z" tamper
  run rowtext 13
  [[ "$output" == *"did not run before the contract page"* ]] || false
  [[ "$output" == *"CONTRACT.md does not match"* ]]
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

# RED-proof (method v1.3, 2026-10-16): before close_delta_rows nothing closed a frame-omission known
# row when the frame-delta cycle re-issued the certificate (§5.4 step 4), so `requires` held its waves.
# RED-proof (pane 194 / the lead, 2026-10-16): the closing rule read "any valid frame signature newer
# than the hold", so a re-sign that carried none of a row's delta (truememory-2-0's 2026-10-12 one over
# KR-06..09) closed it on the next passing run. On that kit the first run below closes KR-3 and KR-4.
@test "v1.3: a passing gate run closes an open frame-omission row only when a frame re-signed after its hold carries its delta" {
  # the fixture's frame is signed 2026-09-30T00:00:00Z; both rows are held after it
  printf '%s\n' \
    '{"id":"KR-3","kind":"frame-omission","status":"open","resign_due":"2099-01-01T00:00:00Z","default":"descope","blocks_waves":["B2"],"ts":"2026-09-30T01:00:00Z"}' \
    '{"id":"KR-4","kind":"frame-omission","status":"open","resign_due":"2099-01-01T00:00:00Z","default":"descope","blocks_waves":["B3"],"ts":"2026-09-30T01:00:00Z"}' \
    >> "$REC/known_rows.jsonl"
  # the KR-06 shape: re-signed after the hold, frame unchanged, so no delta reached it
  "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/frame --evidence "re-read, nothing added" > /dev/null
  git -C "$REC" add -A && git -C "$REC" commit -qm "plant known rows"
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" != *"closed known row"* ]] || { echo "$output"; false; }
  # the delta lists KR-3, and the operator re-signs that frame
  /usr/bin/env python3 "$REPO/scripts/research-kit/intake.py" set --program demo --applies-known-row KR-3 > /dev/null
  "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/frame --evidence "FRAME v2 carries KR-3" > /dev/null
  git -C "$REC" add -A && git -C "$REC" commit -qm "frame delta for KR-3"
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"closed known row KR-3 (frame-delta cycle: frame re-signed "*" carries KR-3, certificate re-issued as CERT-v2)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"closed known row KR-4"* ]] || { echo "$output"; false; }
  [ "$(grep -c '"closed_by": "CERT-v2"' "$REC/known_rows.jsonl")" -eq 1 ]
}

# ── gate.sh delta-activity (REPORT.md §5.4: the post-certificate frame-delta cycle) ───────────────
# fd_rows: the program's frame-delta activity rows, one `id state known_rows` line each.
fd_rows() {
  /usr/bin/python3 -c "
import json, os
p = os.path.join('$CC_RESEARCH_HOME', 'activities.json')
for a in (json.load(open(p))['activities'] if os.path.exists(p) else []):
    if a.get('kind') == 'frame-delta': print(a['id'], a['state'], ','.join(a.get('known_rows') or []))"
}
set_state() {
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_REGISTRY'; d=json.load(open(p)); d['programs'][0]['state']='$1'; json.dump(d, open(p, 'w'))"
}
# held_and_certified: KR-3 and KR-4 held after the fixture's frame signature, then CERT-v1 issued.
held_and_certified() {
  printf '%s\n' \
    '{"id":"KR-3","kind":"frame-omission","status":"open","resign_due":"2099-01-01T00:00:00Z","default":"descope","blocks_waves":["B2"],"ts":"2026-09-30T01:00:00Z"}' \
    '{"id":"KR-4","kind":"frame-omission","status":"open","resign_due":"2099-01-01T00:00:00Z","default":"descope","blocks_waves":["B3"],"ts":"2026-09-30T01:00:00Z"}' \
    >> "$REC/known_rows.jsonl"
  git -C "$REC" add -A && git -C "$REC" commit -qm "plant known rows"
  "$G" run --program demo --consent-sealed-read > /dev/null
  [ "$(state)" = certified ]
}
carry_kr3() {
  /usr/bin/env python3 "$REPO/scripts/research-kit/intake.py" set --program demo --applies-known-row KR-3 > /dev/null
  "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/frame --evidence "FRAME v2 carries KR-3" > /dev/null
  git -C "$REC" add -A && git -C "$REC" commit -qm "frame delta for KR-3"
}

# RED-proof (2026-10-17): before gate_delta.py the verb did not exist (argparse exit 2, "invalid
# choice"), and the only path to a frame-delta activity was triage's blind rater, so truememory-2-0's
# census critic was refused by the research block after the operator re-signed frame v4.
@test "delta-activity: refused with no pending cycle, opens once a re-signed frame carries a held row, prints the same id again, and the re-issued certificate closes it" {
  run "$G" delta-activity --program demo
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"is 'registered'"* ]] || { echo "$output"; false; }
  held_and_certified
  # certified, but no frame re-signed with a delta: no cycle is pending
  run "$G" delta-activity --program demo
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"no frame-delta cycle is pending"*"KR-3, KR-4"* ]] || { echo "$output"; false; }
  # the KR-06 shape: re-signed after the hold, frame unchanged, so no delta reached either row
  "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/frame --evidence "re-read, nothing added" > /dev/null
  run "$G" delta-activity --program demo
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [ -z "$(fd_rows)" ]
  carry_kr3
  run "$G" delta-activity --program demo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  aid="${lines[${#lines[@]}-1]}"
  [[ "$aid" == ACT-demo-* ]] || { echo "$output"; false; }
  [ "$(fd_rows)" = "$aid open KR-3" ]
  run "$G" delta-activity --program demo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "${lines[${#lines[@]}-1]}" = "$aid" ] || { echo "$output"; false; }
  [ "$(fd_rows)" = "$aid open KR-3" ]
  run "$G" run --program demo --consent-sealed-read
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"closed frame-delta activity $aid (CERT-v2 closed KR-3)"* ]] || { echo "$output"; false; }
  [ "$(fd_rows)" = "$aid closed KR-3" ]
  # KR-3 closed and KR-4 carried by no re-sign: nothing is pending, and nothing re-opens
  run "$G" delta-activity --program demo
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"open frame-omission rows: KR-4)"* ]] || { echo "$output"; false; }
  [ "$(fd_rows)" = "$aid closed KR-3" ]
}

@test "delta-activity: refused beside triage's open frame-delta row, and while certifying unless the re-sign is newer than the newest certificate" {
  held_and_certified
  carry_kr3
  printf '{"activities":[{"program":"demo","id":"tri-1","kind":"frame-delta","state":"open"}]}\n' > "$CC_RESEARCH_HOME/activities.json"
  run "$G" delta-activity --program demo
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"tri-1 is already open"* ]] || { echo "$output"; false; }
  [ "$(fd_rows)" = "tri-1 open " ]
  rm "$CC_RESEARCH_HOME/activities.json"
  set_state certifying
  jedit cert/CERT-v1.json "d['issued']='2099-01-01T00:00:00Z'"
  run "$G" delta-activity --program demo
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"is certifying and the newest re-sign"*"not newer than CERT-v1"* ]] || { echo "$output"; false; }
  [ -z "$(fd_rows)" ]
  jedit cert/CERT-v1.json "d['issued']='2000-01-01T00:00:00Z'"
  run "$G" delta-activity --program demo
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$(fd_rows)" == "ACT-demo-"*" open KR-3" ]] || { fd_rows; false; }
}

@test "delta-activity --help names the verb's preconditions and its tag" {
  run "$G" delta-activity --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"known_rows_applied"*"CC_RESEARCH_ACTIVITY=<id>"* ]] || { echo "$output"; false; }
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
