#!/usr/bin/env bats
# cc-research-records — the record verbs of bin/cc-research (REPORT.md §8 item 9; RECORDS.md) and
# concern triage, the writer of $CC_RESEARCH_HOME/activities.json (§5.1, §5.2, §10 item 8).
#
# Each test starts from the known-good program (tests/fixtures/research-kit/build_good.py), drives
# a verb, and reads the result back through the reader that consumes it: gate row 2 for censuses,
# the certificate summary for parked ideas, router.open_activities for activities.

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
  unset CC_BATS_ACTIVE CC_RESEARCH_TRIAGE_RATER CC_RESEARCH_ACTIVITY
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  CR="$REPO/bin/cc-research"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  export CC_RESEARCH_ROUTER="$W/router.sh"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  export CC_RESEARCH_RECORDS="$REC"
}

rowstat() {
  "$G" run --program demo --json 2>/dev/null | /usr/bin/python3 -c "import json,sys; print([r['status'] for r in json.load(sys.stdin) if r['num'] == $1][0])"
}
rowtext() {
  "$G" run --program demo --json 2>/dev/null | /usr/bin/python3 -c "import json,sys; print('\n'.join([r for r in json.load(sys.stdin) if r['num'] == $1][0]['evidence']))"
}
jedit() {
  /usr/bin/python3 -c "import json; p='$REC/$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"
}
# fold <file> <id> <field>: the field of one record after the last-writer-wins fold.
fold() {
  /usr/bin/python3 -c "
import json
s = {}
for l in open('$REC/$1'):
    if l.strip():
        r = json.loads(l); s.setdefault(r.get('id'), {}).update(r)
print(json.dumps(s.get('$2', {}).get('$3')))"
}
open_acts() {
  /usr/bin/python3 -c "import sys; sys.path.insert(0, '$REPO/scripts/research-kit'); import router; print(' '.join(router.open_activities('demo')))"
}
# A stub rater: records its prompt and its activity tag, answers by a planted token.
stub_rater() {
  cat > "$W/rater.sh" <<'EOF'
#!/bin/bash
p="$(cat)"
printf '%s\n' "$p" >> "$W/prompts.txt"
printf '%s\n' "$CC_RESEARCH_ACTIVITY" >> "$W/acts.txt"
case "$p" in
  *ZZESC*) echo escape ;;
  *ZZFD*) echo frame-defect ;;
  *ZZNR*) echo new-requirement ;;
  *ZZINA*) echo intent-never-asked ;;
  *ZZDR*) echo drift ;;
  *ZZGEN*) echo generic ;;
  *ZZERR*) exit 7 ;;
  *) echo banana ;;
esac
EOF
  chmod +x "$W/rater.sh"
  export CC_RESEARCH_TRIAGE_RATER="$W/rater.sh"
}

@test "census add: two methods written by the verb make row 2 pass where the census was missing; one alone keeps it failing" {
  rm "$REC/census/callers.json"
  [ "$(rowstat 2)" = "FAIL" ]
  run "$CR" census add --program demo --pop callers --method x --count 2 --cmd 'printf "a\nb\n"'
  [ "$status" -eq 0 ]
  run "$CR" census critic --program demo --pop callers --family openai --unlisted-verified 0
  [ "$status" -eq 0 ]
  [ "$(rowstat 2)" = "FAIL" ]
  rowtext 2 | grep -q "1 method(s)"
  run "$CR" census add --program demo --pop callers --method y --count 2 --cmd 'printf "b\na\n"'
  [ "$status" -eq 0 ]
  [ "$(rowstat 2)" = "PASS" ]
}

@test "census add refuses overwriting a method, a population not in the frame, and a count that does not match" {
  jedit frame.json "d['populations'].append('hooks')"
  run "$CR" census add --program demo --pop hooks --method x --count 1 --cmd 'echo h1'
  [ "$status" -eq 0 ]
  before="$(shasum "$REC/census/hooks.json")"
  run "$CR" census add --program demo --pop hooks --method x --count 1 --cmd 'echo h1'
  [ "$status" -eq 2 ]
  [[ "$output" == *"already"* ]] || false
  [ "$(shasum "$REC/census/hooks.json")" = "$before" ]
  run "$CR" census add --program demo --pop nope --method x --count 1 --cmd 'echo h1'
  [ "$status" -eq 2 ]
  [[ "$output" == *"not in frame"* ]] || false
  [ ! -e "$REC/census/nope.json" ]
  run "$CR" census add --program demo --pop hooks --method y --count 5 --cmd 'echo h1'
  [ "$status" -eq 2 ]
}

@test "premise and source add append once; a duplicate id is refused and nothing is written" {
  local exp
  exp="$(date -u -v+1440H +%Y-%m-%dT%H:%M:%SZ)"
  run "$CR" premise add --program demo --id PR-2 --claim "the daemon is launchd-run" \
    --truth-lives-in live-state --load-bearing-for DR-2 --recheck-cmd "true" --expires "$exp"
  [ "$status" -eq 0 ]
  [ "$(fold premises.jsonl PR-2 verdict)" = '"unknown"' ]
  [ "$(fold premises.jsonl PR-2 recheck_cmd)" = '"true"' ]
  n="$(wc -l < "$REC/premises.jsonl")"
  run "$CR" premise add --program demo --id PR-2 --claim "again" --truth-lives-in code
  [ "$status" -eq 2 ]
  [ "$(wc -l < "$REC/premises.jsonl")" -eq "$n" ]
  run "$CR" source add --program demo --id E-2 --source "issue tracker" --kind external \
    --status excluded --exclusion-quote "not this one"
  [ "$status" -eq 0 ]
  run "$CR" source add --program demo --id E-2 --source "again" --kind external \
    --status excluded --exclusion-quote "x"
  [ "$status" -eq 2 ]
}

@test "decision: no --conviction flag exists; rule is refused below 90 naming the packet route, accepted at 90; show prints the derived value" {
  run "$CR" decision add --program demo --id DR-2 --question "q" --option do-nothing --option use-what-exists --option x
  [ "$status" -eq 0 ]
  run "$CR" premise add --program demo --id PR-2 --claim "c" --truth-lives-in code --load-bearing-for DR-2
  [ "$status" -eq 0 ]
  run "$CR" decision tally --program demo --id DR-2 --premise PR-2 --flip-probe P-2 --flip-result negative
  [ "$status" -eq 0 ]
  run "$CR" decision rule --program demo --id DR-2 --chosen x --conviction 95
  [ "$status" -eq 2 ]
  [[ "$output" == *"unrecognized"* ]] || false
  run "$CR" decision rule --program demo --id DR-2 --chosen x
  [ "$status" -eq 2 ]
  [[ "$output" == *"cc-research gate file-packet"* ]] || false
  [ "$(fold decisions.jsonl DR-2 status)" = '"open"' ]
  run "$CR" decision show --program demo --id DR-2 --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["conviction"])')" = "0" ]
  run "$CR" decision add --program demo --id DR-3 --question "q" --option do-nothing --option use-what-exists --option y \
    --reversibility costly
  [ "$status" -eq 0 ]
  run "$CR" decision tally --program demo --id DR-3 --premise PR-1 --flip-probe P-2 --flip-result negative
  [ "$status" -eq 0 ]
  run "$CR" decision rule --program demo --id DR-3 --chosen y
  [ "$status" -eq 0 ]
  [ "$(fold decisions.jsonl DR-3 ruled_by)" = '"agent"' ]
  [ "$(fold decisions.jsonl DR-3 conviction)" = "null" ]
  run "$CR" decision add --program demo --id DR-4 --question "q" --option x
  [ "$status" -eq 2 ]
  [[ "$output" == *"do-nothing"* ]]
}

@test "concern add appends a pending challenge; concern list --pending shows it" {
  run "$CR" concern add --program demo --text "first worry"
  [ "$status" -eq 0 ]
  run "$CR" concern add --program demo --text "second worry" --raised-by sweep
  [ "$status" -eq 0 ]
  [ "$(fold challenges.jsonl CH-2 raised_by)" = '"sweep"' ]
  [ "$(fold challenges.jsonl CH-1 triage)" = '"pending"' ]
  run "$CR" concern list --program demo --pending --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | /usr/bin/python3 -c 'import json,sys; print(",".join(c["id"] for c in json.load(sys.stdin)))')" = "CH-1,CH-2" ]
  run "$CR" concern list --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"second worry"* ]]
}

@test "park writes a parked operator_new change and the certificate's parked count goes up" {
  run "$CR" park --program demo --idea "a dashboard"
  [ "$status" -eq 0 ]
  [ "$(fold changes.jsonl CR-1 cause)" = '"operator_new"' ]
  git -C "$REC" add -A && git -C "$REC" commit -qm park  # row 12 refuses uncommitted records
  run "$G" run --program demo
  [ "$status" -eq 0 ]
  [ "$(/usr/bin/python3 -c "import json; print(json.load(open('$REC/cert/CERT-v1.json'))['state']['parked'])")" = "1" ]
}

@test "triage: each counted bucket writes its change cause, the rater is blind and tagged, activities open and the batch closes" {
  stub_rater
  for t in ZZESC ZZFD ZZNR ZZINA ZZDR ZZGEN; do
    run "$CR" concern add --program demo --text "concern $t"
    [ "$status" -eq 0 ]
  done
  run "$CR" triage --program demo
  [ "$status" -eq 0 ]
  [ "$(fold challenges.jsonl CH-1 triage)" = '"escape"' ]
  [ "$(fold challenges.jsonl CH-6 triage)" = '"generic"' ]
  [ "$(fold challenges.jsonl CH-1 rater)" != "null" ]
  causes="$(/usr/bin/python3 -c "
import json
rows = [json.loads(l) for l in open('$REC/changes.jsonl') if l.strip()]
print(' '.join(r['cause'] + ('/' + r['status'] if r.get('status') else '') for r in rows))")"
  [ "$causes" = "escape frame_defect operator_new/parked operator_unelicited reality_moved" ]
  grep -q "escape" "$W/prompts.txt"
  grep -q "drift" "$W/prompts.txt"
  [ "$(grep -ciE 'counted|forecast' "$W/prompts.txt")" -eq 0 ]
  [ "$(sort -u "$W/acts.txt")" = "ACT-demo-1" ]
  acts="$(open_acts)"
  [[ " $acts " != *" ACT-demo-1 "* ]] || false
  kinds="$(/usr/bin/python3 -c "
import json
d = json.load(open('$CC_RESEARCH_HOME/activities.json'))
print(' '.join(sorted(a['kind'] for a in d['activities'] if a['id'] in '$acts'.split())))")"
  [ "$kinds" = "escape frame-delta frame-delta" ]
  run "$CR" concern list --program demo --pending --json
  [ "$output" = "[]" ]
}

@test "triage: a garbage answer or a failing rater leaves the challenge pending and exits 3" {
  stub_rater
  run "$CR" concern add --program demo --text "concern ZZBAD"
  run "$CR" concern add --program demo --text "concern ZZERR"
  run "$CR" concern add --program demo --text "concern ZZDR"
  run "$CR" triage --program demo
  [ "$status" -eq 3 ]
  [ "$(fold challenges.jsonl CH-1 triage)" = '"pending"' ]
  [ "$(fold challenges.jsonl CH-2 triage)" = '"pending"' ]
  [ "$(fold challenges.jsonl CH-3 triage)" = '"drift"' ]
  [ "$(wc -l < "$REC/changes.jsonl")" -eq 1 ]
  [ -z "$(open_acts)" ]
}

@test "records stay append-only: every verb only grows its file and keeps the old bytes as a prefix" {
  stub_rater
  run "$CR" concern add --program demo --text "concern ZZFD"
  run "$CR" park --program demo --idea "later"
  cp "$REC/challenges.jsonl" "$W/ch.before"
  cp "$REC/changes.jsonl" "$W/cr.before"
  cp "$REC/decisions.jsonl" "$W/dr.before"
  run "$CR" triage --program demo
  [ "$status" -eq 0 ]
  run "$CR" decision tally --program demo --id DR-1 --premise PR-1 --flip-probe P-2 --flip-result negative
  [ "$status" -eq 0 ]
  for f in ch:challenges cr:changes dr:decisions; do
    old="$W/${f%%:*}.before"; new="$REC/${f##*:}.jsonl"
    [ "$(wc -l < "$new")" -gt "$(wc -l < "$old")" ]
    head -c "$(wc -c < "$old" | tr -d ' ')" "$new" | cmp -s - "$old"
  done
}

@test "activities: an unknown kind is refused; close keeps the row and only flips its state" {
  run /usr/bin/python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/research-kit/lib')
import activities, kit
a = activities.open_activity('demo', 'escape')
b = activities.open_activity('demo', 'triage-batch')
activities.close_activity(a)
try:
    activities.open_activity('demo', 'reopen')
except kit.KitError:
    print('refused')
d = activities.load()
print(a, b, ' '.join(x['state'] for x in d['activities']))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "refused" ]
  [ "${lines[1]}" = "ACT-demo-1 ACT-demo-2 closed open" ]
  [ "$(open_acts)" = "ACT-demo-2" ]
}
