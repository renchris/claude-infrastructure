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

# census repin (RED-proof: each of the four below FAILS on 0c6956972, the kit before the verb: no
# `repin` subcommand, and row 2 counted and re-ran superseded methods).
cfield() {
  /usr/bin/python3 -c "import json; d=json.load(open('$REC/census/callers.json')); print(json.dumps($1))"
}

@test "census repin: a population that grew after a method was pinned fails row 2 until the stale method is superseded" {
  # x reads the live plan (a, b, c); y is pinned to the old one (a, b). c is extra to the census.
  jedit census/callers.json 'd["methods"][0]["cmd"] = "printf \"a\\nb\\nc\\n\""'
  [ "$(rowstat 2)" = "FAIL" ]
  run "$CR" census repin --program demo --pop callers --method z --supersedes y --count 3 \
    --cmd 'printf "c\nb\na\n"' --why "merge added c"
  [ "$status" -eq 0 ]
  [ "$(rowstat 2)" = "PASS" ]
  [ "$(cfield "[m['id'] for m in d['members']]")" = '["a", "b", "c"]' ]
  [ "$(cfield "[(m['agent'], m.get('superseded_by'), m.get('superseded_why')) for m in d['methods']]")" = \
    '[["x", null, null], ["y", "z", "merge added c"], ["z", null, null]]' ]
}

@test "census repin: a member no active method lists moves to retired_members and row 2 passes" {
  # y reads the live plan, where a ruling removed b; x is pinned to the old one (a, b).
  jedit census/callers.json 'd["methods"][1]["cmd"] = "echo a"'
  [ "$(rowstat 2)" = "FAIL" ]
  run "$CR" census repin --program demo --pop callers --method x2 --supersedes x --count 1 \
    --cmd 'echo a' --why "ruling removed b"
  [ "$status" -eq 0 ]
  [ "$(cfield "[m['id'] for m in d['members']]")" = '["a"]' ]
  [ "$(cfield "[(m['id'], m['why']) for m in d['retired_members']]")" = '[["b", "ruling removed b"]]' ]
  [ "$(rowstat 2)" = "PASS" ]
}

@test "census repin: when every method is stale, one call re-pins them all (one at a time is refused)" {
  # Both x and y are pinned to the old population (a, b); the live one is (a, b, c).
  before="$(shasum "$REC/census/callers.json")"
  run "$CR" census repin --program demo --pop callers --method x2 --supersedes x --count 3 \
    --cmd 'printf "a\nb\nc\n"' --why "c added upstream"
  [ "$status" -eq 2 ]
  [[ "$output" == *"disagree"* ]] || false
  [ "$(shasum "$REC/census/callers.json")" = "$before" ]
  run "$CR" census repin --program demo --pop callers \
    --method x2 --supersedes x --count 3 --cmd 'printf "a\nb\nc\n"' \
    --method y2 --supersedes y --count 3 --cmd 'printf "c\nb\na\n"' --why "c added upstream"
  [ "$status" -eq 0 ]
  [ "$(cfield "[m['id'] for m in d['members']]")" = '["a", "b", "c"]' ]
  [ "$(cfield "[(m['agent'], m.get('superseded_by')) for m in d['methods']]")" = \
    '[["x", "x2"], ["y", "y2"], ["x2", null], ["y2", null]]' ]
  [ "$(rowstat 2)" = "PASS" ]
  # unpaired flags are refused, writing nothing
  before="$(shasum "$REC/census/callers.json")"
  run "$CR" census repin --program demo --pop callers --method x3 --method y3 --supersedes x2 \
    --count 3 --cmd 'printf "a\nb\nc\n"' --why r
  [ "$status" -eq 2 ]
  [[ "$output" == *"pair by position"* ]] || false
  [ "$(shasum "$REC/census/callers.json")" = "$before" ]
}

@test "census repin refuses an unknown or superseded OLD, a NEW that is already a method, an empty --why and disagreeing active methods, writing nothing" {
  run "$CR" census repin --program demo --pop callers --method z --supersedes y --count 2 \
    --cmd 'printf "a\nb\n"' --why "re-pinned"
  [ "$status" -eq 0 ]
  before="$(shasum "$REC/census/callers.json")"
  refused() {
    run "$CR" census repin --program demo --pop callers "$@"
    [ "$status" -eq 2 ]
    [ "$(shasum "$REC/census/callers.json")" = "$before" ]
  }
  refused --method w --supersedes nope --count 2 --cmd 'printf "a\nb\n"' --why r
  [[ "$output" == *"no method 'nope'"* ]] || false
  refused --method w --supersedes y --count 2 --cmd 'printf "a\nb\n"' --why r
  [[ "$output" == *"already superseded by 'z'"* ]] || false
  refused --method x --supersedes z --count 2 --cmd 'printf "a\nb\n"' --why r
  [[ "$output" == *"'x' already recorded"* ]] || false
  refused --method w --supersedes z --count 2 --cmd 'printf "a\nb\n"' --why " "
  [[ "$output" == *"--why is empty"* ]] || false
  refused --method w --supersedes z --count 1 --cmd 'echo a' --why r
  [[ "$output" == *"disagree"*"w lacks ['b']"* ]] || false
}

@test "row 2: one active method plus one superseded fails the two-method rule" {
  jedit census/callers.json 'd["methods"][1]["superseded_by"] = "z"'
  [ "$(rowstat 2)" = "FAIL" ]
  rowtext 2 | grep -q "1 method(s) active (1 superseded)"
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

# refused <premise revise args>: the call exits 2 (a refusal), naming the args when it does not.
refused() {
  local rc=0
  "$CR" premise revise --program demo "$@" > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || { echo "accepted (exit $rc): $*"; false; }
}

# RED-proof (K5, 2026-10-11): before `premise revise` existed the first call exits 2 (no such verb).
@test "premise revise appends one reasoned event per call; refusals write nothing; row 4 reads a refutation" {
  first="$(head -1 "$REC/premises.jsonl")"
  n="$(wc -l < "$REC/premises.jsonl")"
  run "$CR" premise revise --program demo --id PR-1 --recheck-cmd "test -s x" --repointed-from P-1 --why "the old command could not fail"
  [ "$status" -eq 0 ]
  [ "$(fold premises.jsonl PR-1 recheck_cmd)" = '"test -s x"' ]
  [ "$(fold premises.jsonl PR-1 recheck_repointed_from)" = '"P-1"' ]
  [ "$(fold premises.jsonl PR-1 why)" = '"the old command could not fail"' ]
  [ "$(fold premises.jsonl PR-1 verdict)" = '"holds"' ]
  [ "$(head -1 "$REC/premises.jsonl")" = "$first" ]
  [ "$(wc -l < "$REC/premises.jsonl")" -eq $((n + 1)) ]
  n=$((n + 1))
  refused --id PR-1 --verdict refuted --why w                   # refuted names no refuter
  refused --id PR-1 --verdict holds --refuted-by P-1 --why w    # a refuter without refuted
  refused --id PR-1 --verdict refuted --refuted-by P-404 --why w
  refused --id PR-1 --recheck-cmd x --retire-recheck --why w
  refused --id PR-1 --why w                                     # nothing to revise
  refused --id PR-404 --verdict holds --why w
  refused --id PR-1 --verdict holds                             # no --why
  refused --id PR-1 --verdict holds --why ""
  refused --id PR-1 --recheck-cmd "unmeasured: later, n>=5" --why w
  [ "$(wc -l < "$REC/premises.jsonl")" -eq "$n" ]
  run "$CR" premise revise --program demo --id PR-1 --load-bearing-for DR-1 --load-bearing-for DR-9 --why "DR-9 reads it too"
  [ "$status" -eq 0 ]
  [ "$(fold premises.jsonl PR-1 load_bearing_for)" = '["DR-1", "DR-9"]' ]
  run "$CR" premise revise --program demo --id PR-1 --load-bearing-for DR-1 --retire-recheck --why "decomposed"
  [ "$status" -eq 0 ]
  [ "$(fold premises.jsonl PR-1 recheck_cmd)" = 'null' ]
  [ "$(rowstat 4)" = "PASS" ]
  run "$CR" premise revise --program demo --id PR-1 --verdict refuted --refuted-by P-1 --why "P-1 reads the opposite"
  [ "$status" -eq 0 ]
  [ "$(fold premises.jsonl PR-1 refuted_by)" = '"P-1"' ]
  rowtext 4 | grep -q "PR-1 refuted but dependent DR-1 was never revised"
}

# RED-proof (2026-10-12): before `--probe` existed every call below exits 2 (unrecognized argument),
# so the join is refused and row 4 stays FAIL.
@test "premise revise --probe joins a recorded probe that closes the premise, raising the level row 4 reads; unknown or non-closing probes are refused" {
  printf '%s\n' '{"id": "PR-1", "truth_lives_in": "live-state"}' >> "$REC/premises.jsonl"
  printf '{"id": "P-5", "kind": "live-read", "env": {"id": "agent-shell"}, "closes": ["PR-1"], "exit": 0, "n": 1, "stdin": "/dev/null", "negative_control": {"ran": true, "reported_refutation": true}, "raw": "evidence/P-5/", "at": "%s"}\n' "$CC_NOW" >> "$REC/probes.jsonl"
  mkdir -p "$REC/evidence/P-5" && echo ok > "$REC/evidence/P-5/stdout"
  rowtext 4 | grep -q "PR-1: at E2, needs E3"
  n="$(wc -l < "$REC/premises.jsonl")"
  refused --id PR-1 --probe P-404 --why w                       # no such probe
  refused --id PR-1 --probe P-2 --why w                         # P-2 closes nothing
  refused --id PR-404 --probe P-5 --why w                       # no such premise
  refused --id PR-1 --probe P-1 --why w                         # already joined: nothing to revise
  refused --id PR-1 --probe P-5                                 # no --why
  [ "$(wc -l < "$REC/premises.jsonl")" -eq "$n" ]
  run "$CR" premise revise --program demo --id PR-1 --probe P-5 --probe P-1 --probe P-5 --why "P-5 read the live state"
  [ "$status" -eq 0 ]
  [ "$(fold premises.jsonl PR-1 probes)" = '["P-1", "P-5"]' ]
  [ "$(fold premises.jsonl PR-1 verdict)" = '"holds"' ]
  [ "$(fold premises.jsonl PR-1 why)" = '"P-5 read the live state"' ]
  [ "$(wc -l < "$REC/premises.jsonl")" -eq $((n + 1)) ]
  [ "$(rowstat 4)" = "PASS" ]
}

# pfile <premise file args>: the verb with the program and every required flag but --id (args after
# these override nothing; argparse takes the last of a repeated single flag).
pfile() {
  "$CR" premise file --program demo --awaits build --owner-wave B3 --owner lead \
    --due 2099-01-01T00:00:00Z --closing-probe P-9 --why "K2c is built in B3" "$@"
}
# pfile_refused <reason> <args>: refused with exit 2 and the reason on stderr.
pfile_refused() {
  local want="$1"; shift
  run pfile "$@"
  [ "$status" -eq 2 ] || { echo "accepted (exit $status): $*"; return 1; }
  [[ "$output" == *"$want"* ]] || { echo "[$want] $output"; return 1; }
}

# RED-proof (decision 55e7da1e7311, 2026-10-16): before `premise file` existed the first call exits 2
# (invalid choice 'file'), nothing is written, and row 4 stays FAIL.
@test "premise file: writes the not-yet-true row and its reconcile line, and row 4 files the premise; refusals write nothing" {
  printf '%s\n' '{"id":"PR-2","truth_lives_in":"target-env","verdict":"partial","probes":[],"load_bearing_for":["DR-2"],"recheck_cmd":"true"}' >> "$REC/premises.jsonl"
  printf '%s\n' '{"id":"DR-2","status":"carried","ruled_by":"operator","options":[{"label":"do-nothing"},{"label":"use-what-exists"}],"set":{"members":[{"id":"a","feasibility_probe":"P-1"},{"id":"b","feasibility_probe":"P-2"}],"narrowing_probe":{"wave":"B3","owner":"lead","due":"2099-01-01"},"revision_budget_h":4},"blocks_waves":["B4"]}' >> "$REC/decisions.jsonl"
  rowtext 4 | grep -q "PR-2: at E0, needs E5"
  run pfile --id PR-2 --blocks-wave B5
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "R-NYT-PR-2: filed PR-2 not-yet-true until B3 (build), due 2099-01-01T00:00:00Z; waves B4, B5 wait for P-9 to join it" ]] || { echo "$output"; false; }
  [ "$(fold residual.jsonl R-NYT-PR-2 why_unreachable)" = '"not-yet-true"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2 premise)" = '"PR-2"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2 owner)" = '"lead"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2 closing_probe)" = '"P-9"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2 blocks_waves)" = '["B5"]' ]
  [ "$(fold reconcile.jsonl residual:R-NYT-PR-2 disposition)" = '"filed"' ]
  [ "$(fold reconcile.jsonl residual:R-NYT-PR-2 ref)" = '"R-NYT-PR-2"' ]
  out="$(rowtext 4)"
  [[ "$out" == *"FILED PR-2: at E0, needs E5; not yet true until B3 (build), owner lead"* ]] || { echo "$out"; false; }
  [[ "$out" != *"PR-2: at E0, needs E5 ("* ]] || { echo "$out"; false; }
  # refusals: each writes nothing to either store
  printf '%s\n' \
    '{"id":"PR-3","truth_lives_in":"target-env","verdict":"refuted","refuted_by":"P-1","load_bearing_for":["DR-2"],"recheck_cmd":"true"}' \
    '{"id":"PR-4","truth_lives_in":"code","verdict":"partial","probes":[],"load_bearing_for":["DR-2"],"recheck_cmd":"true"}' \
    '{"id":"PR-5","truth_lives_in":"target-env","verdict":"partial","probes":[],"load_bearing_for":["DR-1"],"recheck_cmd":"true"}' \
    >> "$REC/premises.jsonl"
  before="$(cat "$REC/residual.jsonl" "$REC/reconcile.jsonl" | cksum)"
  pfile_refused "PR-404 is not in premises.jsonl" --id PR-404
  pfile_refused "a refuted premise is never filed" --id PR-3
  pfile_refused "PR-1 is already at its required level" --id PR-1
  pfile_refused "a code premise is not raised by build" --id PR-4
  pfile_refused "a code premise is not raised by upstream-merge" --id PR-4 --awaits upstream-merge
  pfile_refused "dependent DR-1 is ruled by agent" --id PR-5
  pfile_refused "is unparseable or already past" --id PR-5 --due 2020-01-01T00:00:00Z
  pfile_refused "is not ISO-8601 UTC or YYYY-MM-DD" --id PR-5 --due "next week"
  pfile_refused "not a probe id" --id PR-5 --closing-probe "after the build"
  pfile_refused "--why is required" --id PR-5 --why " "
  pfile_refused "argument --owner: expected one argument" --id PR-5 --owner
  pfile_refused "invalid choice" --id PR-5 --awaits someday
  pfile_refused "PR-2 is already filed not-yet-true" --id PR-2
  [ "$(cat "$REC/residual.jsonl" "$REC/reconcile.jsonl" | cksum)" = "$before" ]
}

# RED-proof (2026-10-16): before `--refile` existed every call with it exits 2 (unrecognized
# argument), so the past-due filing below can never be re-dated and row 4 stays FAIL.
@test "premise file --refile: supersedes the live filing under every first-filing guard; row 4 and row 11 read the newest; without --refile a second filing is still refused" {
  printf '%s\n' '{"id":"PR-2","truth_lives_in":"target-env","verdict":"partial","probes":[],"load_bearing_for":["DR-2"],"recheck_cmd":"true"}' >> "$REC/premises.jsonl"
  printf '%s\n' '{"id":"DR-2","status":"carried","ruled_by":"operator","options":[{"label":"do-nothing"},{"label":"use-what-exists"}],"set":{"members":[{"id":"a","feasibility_probe":"P-1"},{"id":"b","feasibility_probe":"P-2"}],"narrowing_probe":{"wave":"B3","owner":"lead","due":"2099-01-01"},"revision_budget_h":4},"blocks_waves":["B4"]}' >> "$REC/decisions.jsonl"
  before="$(cat "$REC/residual.jsonl" "$REC/reconcile.jsonl" | cksum)"
  pfile_refused "PR-2 has no not-yet-true filing to refile" --id PR-2 --refile   # (a) nothing filed yet
  [ "$(cat "$REC/residual.jsonl" "$REC/reconcile.jsonl" | cksum)" = "$before" ]
  run pfile --id PR-2 --blocks-wave B5
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # the due date passes: row 4 now fails the filing, as it will on 2026-11-01
  printf '%s\n' '{"id":"R-NYT-PR-2","due":"2020-01-01"}' >> "$REC/residual.jsonl"
  rowtext 4 | grep -q "PR-2: filed not-yet-true, but due '2020-01-01' is unparseable or already past"
  before="$(cat "$REC/residual.jsonl" "$REC/reconcile.jsonl" | cksum)"
  pfile_refused "PR-2 is already filed not-yet-true" --id PR-2 --due 2099-06-01   # (e) no --refile
  pfile_refused "is unparseable or already past" --id PR-2 --refile --due 2020-02-01T00:00:00Z   # (b)
  [ "$(cat "$REC/residual.jsonl" "$REC/reconcile.jsonl" | cksum)" = "$before" ]
  # the first-filing guards bind the refile: a now-agent-ruled dependent refuses it
  printf '%s\n' '{"id":"DR-2","status":"ruled","ruled_by":"agent"}' >> "$REC/decisions.jsonl"
  pfile_refused "dependent DR-2 is ruled by agent" --id PR-2 --refile --due 2099-06-01
  printf '%s\n' '{"id":"DR-2","status":"carried","ruled_by":"operator"}' >> "$REC/decisions.jsonl"
  [ "$(cat "$REC/residual.jsonl" "$REC/reconcile.jsonl" | cksum)" = "$before" ]
  pfile_refused "--why is required" --id PR-2 --refile --due 2099-06-01 --why " "
  # (c) the refile: a new row superseding the old, which stays as history
  run pfile --id PR-2 --refile --due 2099-06-01 --closing-probe P-10 --blocks-wave B5 --why "W1 waits for the v5 held-out set"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "R-NYT-PR-2-r2: refiled PR-2 not-yet-true until B3 (build), due 2099-06-01, superseding R-NYT-PR-2; waves B4, B5 wait for P-10 to join it" ]] || { echo "$output"; false; }
  [ "$(fold residual.jsonl R-NYT-PR-2-r2 supersedes)" = '"R-NYT-PR-2"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2-r2 due)" = '"2099-06-01"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2-r2 closing_probe)" = '"P-10"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2-r2 why)" = '"W1 waits for the v5 held-out set"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2 superseded_by)" = '"R-NYT-PR-2-r2"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2 closing_probe)" = '"P-9"' ]   # history is kept
  [ "$(fold reconcile.jsonl residual:R-NYT-PR-2-r2 disposition)" = '"filed"' ]
  out="$(rowtext 4)"
  [[ "$out" == *"FILED PR-2: at E0, needs E5; not yet true until B3 (build), owner lead, due 2099-06-01, closing probe P-10"* ]] || { echo "$out"; false; }
  [[ "$out" != *"already past"* ]] || { echo "$out"; false; }
  [ "$(rowstat 4)" != "FAIL" ]
  out="$(rowtext 11)"
  [[ "$out" == *"R-NYT-PR-2-r2: not-yet-true, premise PR-2 awaits build, owner B3, due 2099-06-01"* ]] || { echo "$out"; false; }
  [[ "$out" == *"R-NYT-PR-2: superseded by R-NYT-PR-2-r2"* ]] || { echo "$out"; false; }
  [ "$(rowstat 11)" != "FAIL" ]
  # a third filing supersedes the second, still never without --refile
  pfile_refused "PR-2 is already filed not-yet-true" --id PR-2
  run pfile --id PR-2 --refile --due 2099-07-01 --closing-probe P-10 --why "again"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(fold residual.jsonl R-NYT-PR-2-r3 supersedes)" = '"R-NYT-PR-2-r2"' ]
  [ "$(fold residual.jsonl R-NYT-PR-2-r2 superseded_by)" = '"R-NYT-PR-2-r3"' ]
  rowtext 4 | grep -q "due 2099-07-01, closing probe P-10"
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

# RED-proof: on 931209017 `decision reopen` and `decision rule --by` do not exist (argparse exits 2
# on "invalid choice" / "unrecognized arguments"), so no asserted text prints and DR-2 never leaves
# its agent ruling.
@test "decision reopen: the operator's reopen of a ruled decision fails row 5 until his re-ruling, which needs his words and a revisit trigger and no 90; a third reopen is refused" {
  "$CR" decision add --program demo --id DR-2 --question "q" --option do-nothing --option use-what-exists --option x
  "$CR" premise add --program demo --id PR-2 --claim "c" --truth-lives-in code --load-bearing-for DR-2
  "$CR" decision tally --program demo --id DR-2 --premise PR-2 --flip-probe P-2 --flip-result negative
  # an open decision is not the operator's to rule through this verb: it goes to him as a packet
  run "$CR" decision rule --program demo --id DR-2 --chosen x --by operator --receipt "he said x" --revisit-trigger t
  [ "$status" -eq 2 ]
  [[ "$output" == *"re-rules a decision the operator reopened"*"cc-research gate file-packet"* ]] || false
  run "$CR" decision reopen --program demo --id DR-2 --because "P7 moved" --receipt "re-plan it"
  [ "$status" -eq 2 ]
  [[ "$output" == *"status 'open'; only a ruled or carried decision is reopened"* ]] || false
  # DR-2 as a ruled decision whose derived conviction has since fallen to 0
  printf '{"id":"DR-2","status":"ruled","ruled_by":"agent","chosen":"x","receipt":"old","revisit_trigger":"old"}\n' >> "$REC/decisions.jsonl"
  run "$CR" decision reopen --program demo --id DR-2 --because "census P7 moved" --receipt "operator 2026-10-12: re-plan DR-2"
  [ "$status" -eq 0 ]
  [ "$output" = "DR-2: reopened by operator (1 of 2)" ]
  [ "$(fold decisions.jsonl DR-2 status)" = '"reopened"' ]
  [ "$(fold decisions.jsonl DR-2 reopen_receipt)" = '"operator 2026-10-12: re-plan DR-2"' ]
  rowtext 5 | grep -q "DR-2: status 'reopened'"
  run "$CR" decision rule --program demo --id DR-2 --chosen x --by operator --receipt "keep x"
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs --receipt (his words) and --revisit-trigger"* ]] || false
  run "$CR" decision rule --program demo --id DR-2 --chosen x --by operator --revisit-trigger "P7 moves again"
  [ "$status" -eq 2 ]
  [[ "$output" == *"needs --receipt (his words) and --revisit-trigger"* ]] || false
  run "$CR" decision rule --program demo --id DR-2 --chosen x --revisit-trigger "P7 moves again"
  [ "$status" -eq 2 ]
  [[ "$output" == *"derived conviction 0%; an agent rules only at 90"* ]] || false
  run "$CR" decision rule --program demo --id DR-2 --chosen x --by operator --receipt "operator 2026-10-12: keep x" --revisit-trigger "P7 moves again"
  [ "$status" -eq 0 ]
  [ "$output" = "DR-2: ruled x by operator (derived 0%)" ]
  [ "$(fold decisions.jsonl DR-2 ruled_by)" = '"operator"' ]
  [ "$(fold decisions.jsonl DR-2 receipt)" = '"operator 2026-10-12: keep x"' ]
  run rowtext 5
  [[ "$output" != *"DR-2"* ]] || false
  "$CR" decision reopen --program demo --id DR-2 --because "again" --receipt "re-plan again"
  "$CR" decision rule --program demo --id DR-2 --chosen x --by operator --receipt "keep x" --revisit-trigger t
  run "$CR" decision reopen --program demo --id DR-2 --because "a third time" --receipt "once more"
  [ "$status" -eq 2 ]
  [[ "$output" == *"already reopened 2 times; the cap is 2 per decision"* ]] || false
  [ "$(fold decisions.jsonl DR-2 status)" = '"ruled"' ]
}

# set_json <members> [key to drop]: a carried set in the shape gate row 5 reads.
set_json() {
  /usr/bin/python3 -c "
import json, time
due = time.strftime('%Y-%m-%dT00:00:00Z', time.gmtime(time.time() + 30 * 86400))
s = {'members': [{'label': 'm%d' % i, 'feasibility_probe': 'P-%d' % i} for i in range(1, $1 + 1)],
     'narrowing_probe': {'wave': 'W1', 'owner': 'lead', 'due': due},
     'revision_budget_h': 4}
drop = '${2:-}'
if drop == 'feasibility_probe':
    del s['members'][0][drop]
elif drop == 'due':
    del s['narrowing_probe'][drop]
elif drop:
    del s[drop]
print(json.dumps(s, sort_keys=True))"
}
# seed_carried <members>: DR-1 as a carried set, dated before any refutation a test writes.
seed_carried() {
  printf '{"id": "DR-1", "status": "carried", "ts": "2020-01-01T00:00:00Z", "set": %s}\n' "$(set_json "$1")" >> "$REC/decisions.jsonl"
}
no_carry() {
  local rc=0
  "$CR" decision carry --program demo "$@" > /dev/null 2>&1 || rc=$?
  [ "$rc" -eq 2 ] || { echo "accepted (exit $rc): $*"; false; }
}

# RED-proof (2026-10-13): before `decision carry` existed the first call exits 2 (argparse "invalid
# choice"), nothing is appended, and row 4 keeps "PR-1 refuted but dependent DR-1 was never revised".
@test "decision carry: the operator's re-affirmation of a carried set after its premise is refuted lets row 4 pass the dependent; it copies the set and writes no conviction" {
  seed_carried 2
  "$CR" premise revise --program demo --id PR-1 --verdict refuted --refuted-by P-1 --why "P-1 reads the opposite"
  rowtext 4 | grep -q "PR-1 refuted but dependent DR-1 was never revised"
  before="$(fold decisions.jsonl DR-1 set)"
  n="$(wc -l < "$REC/decisions.jsonl")"
  no_carry --id DR-1 --because "PR-1 refuted"                            # no --receipt
  no_carry --id DR-1 --receipt "keep the set"                            # no --because
  no_carry --id DR-1 --because " " --receipt "keep the set"
  no_carry --id DR-1 --because "PR-1 refuted" --receipt ""
  no_carry --id DR-1 --because b --receipt r --conviction 95             # no such flag
  [ "$(wc -l < "$REC/decisions.jsonl")" -eq "$n" ]
  run "$CR" decision carry --program demo --id DR-1 --because "PR-1 refuted by P-1" --receipt "operator 2026-10-13: the set stands"
  [ "$status" -eq 0 ]
  [ "$output" = "DR-1: carried by operator (set of 2 re-affirmed)" ]
  [ "$(wc -l < "$REC/decisions.jsonl")" -eq $((n + 1)) ]
  [ "$(fold decisions.jsonl DR-1 status)" = '"carried"' ]
  [ "$(fold decisions.jsonl DR-1 set)" = "$before" ]
  [ "$(fold decisions.jsonl DR-1 carried_by)" = '"operator"' ]
  [ "$(fold decisions.jsonl DR-1 carried_because)" = '"PR-1 refuted by P-1"' ]
  [ "$(fold decisions.jsonl DR-1 carry_receipt)" = '"operator 2026-10-13: the set stands"' ]
  [ "$(fold decisions.jsonl DR-1 carried_at)" = "\"$CC_NOW\"" ]
  [ "$(fold decisions.jsonl DR-1 conviction)" = "null" ]
  tail -1 "$REC/decisions.jsonl" | grep -q '"set": {'
  run rowtext 4
  [[ "$output" != *"DR-1"* ]] || false
  [ "$(rowstat 4)" = "PASS" ]
  rowtext 5 | grep -q "DR-1: carried set of 2, narrows in W1"
}

# RED-proof (2026-10-13): `decision carry` does not exist before this change, so every call exits 2
# and the accepted ones below never write.
@test "decision carry --set replaces the set in the shape row 5 checks; a malformed set and an open, descoped or unknown decision are refused, writing nothing" {
  seed_carried 2
  n="$(wc -l < "$REC/decisions.jsonl")"
  set_json 1 > "$W/one.json"
  set_json 5 > "$W/five.json"
  set_json 3 feasibility_probe > "$W/noprobe.json"
  set_json 3 due > "$W/nodue.json"
  set_json 3 revision_budget_h > "$W/nobudget.json"
  set_json 3 narrowing_probe > "$W/nonarrow.json"
  echo "not json" > "$W/bad.json"
  echo '[1, 2]' > "$W/list.json"
  for f in one five noprobe nodue nobudget nonarrow bad list absent; do
    no_carry --id DR-1 --because b --receipt r --set "$W/$f.json"
  done
  no_carry --id DR-404 --because b --receipt r
  "$CR" decision add --program demo --id DR-2 --question "q" --option do-nothing --option use-what-exists --option x
  set_json 3 > "$W/three.json"
  n=$((n + 1))
  no_carry --id DR-2 --because b --receipt r --set "$W/three.json"       # open: goes to him as a packet
  printf '{"id": "DR-2", "status": "descoped", "descoped_waves": ["W2"]}\n' >> "$REC/decisions.jsonl"
  n=$((n + 1))
  no_carry --id DR-2 --because b --receipt r --set "$W/three.json"
  [ "$(wc -l < "$REC/decisions.jsonl")" -eq "$n" ]
  run "$CR" decision carry --program demo --id DR-2 --because b --receipt r --set "$W/three.json"
  [[ "$output" == *"status 'descoped'; only a carried, ruled or reopened decision is carried"* ]] || false
  run "$CR" decision carry --program demo --id DR-1 --because "W1 narrowed it" --receipt "operator: carry these three" --set "$W/three.json"
  [ "$status" -eq 0 ]
  [ "$output" = "DR-1: carried by operator (set of 3 replaced)" ]
  [ "$(fold decisions.jsonl DR-1 set)" = "$(cat "$W/three.json")" ]
  rowtext 5 | grep -q "DR-1: carried set of 3, narrows in W1"
  # a carried decision whose folded set is not well-formed is not re-affirmed without --set
  printf '{"id": "DR-1", "set": %s}\n' "$(cat "$W/one.json")" >> "$REC/decisions.jsonl"
  run "$CR" decision carry --program demo --id DR-1 --because b --receipt r
  [ "$status" -eq 2 ]
  [[ "$output" == *"no well-formed set to re-affirm"*"--set"* ]] || false
  # one carried on a dated class-C packet has no set to copy: it is re-affirmed without one
  due="$(date -u -v+30d +%Y-%m-%dT00:00:00Z)"
  printf '{"id": "DR-5", "status": "carried", "packet": {"id": "p", "class": "C", "due": "%s"}}\n' "$due" >> "$REC/decisions.jsonl"
  run "$CR" decision carry --program demo --id DR-5 --because b --receipt r
  [ "$status" -eq 0 ]
  [ "$output" = "DR-5: carried by operator (on its class-C packet)" ]
  [ "$(fold decisions.jsonl DR-5 set)" = "null" ]
  rowtext 5 | grep -q "DR-5: class C, due $due"
}

# RED-proof (2026-10-13): before this change `decision carry` does not exist and `decision reopen`
# refuses DR-1 once it is carried ("only a ruled decision is reopened"), both exit 2.
@test "decision carry takes a ruled decision into a set only with --set and withdraws its ruling; decision reopen accepts a carried decision under the same 2-reopen cap" {
  set_json 2 > "$W/two.json"
  no_carry --id DR-1 --because b --receipt r                             # ruled: it has no set
  run "$CR" decision reopen --program demo --id DR-1 --because "PR-1 moved" --receipt "re-plan it"
  [ "$status" -eq 0 ]
  [ "$output" = "DR-1: reopened by operator (1 of 2)" ]
  "$CR" decision rule --program demo --id DR-1 --chosen retry --by operator --receipt "keep retry" --revisit-trigger t
  run "$CR" decision carry --program demo --id DR-1 --because "two options survive" --receipt "operator: carry both" --set "$W/two.json"
  [ "$status" -eq 0 ]
  [ "$(fold decisions.jsonl DR-1 status)" = '"carried"' ]
  [ "$(fold decisions.jsonl DR-1 chosen)" = "null" ]
  [ "$(fold decisions.jsonl DR-1 ruled_by)" = "null" ]
  run "$CR" decision reopen --program demo --id DR-1 --because "the set's premise fell" --receipt "operator: re-plan the set"
  [ "$status" -eq 0 ]
  [ "$output" = "DR-1: reopened by operator (2 of 2)" ]
  [ "$(fold decisions.jsonl DR-1 status)" = '"reopened"' ]
  rowtext 5 | grep -q "DR-1: status 'reopened'"
  # a reopened set is carried again on his words, its folded set unchanged
  run "$CR" decision carry --program demo --id DR-1 --because "re-planned" --receipt "operator: the two stand"
  [ "$status" -eq 0 ]
  [ "$(fold decisions.jsonl DR-1 status)" = '"carried"' ]
  [ "$(fold decisions.jsonl DR-1 set)" = "$(cat "$W/two.json")" ]
  run "$CR" decision reopen --program demo --id DR-1 --because "a third time" --receipt "once more"
  [ "$status" -eq 2 ]
  [[ "$output" == *"already reopened 2 times; the cap is 2 per decision"* ]] || false
  [ "$(fold decisions.jsonl DR-1 status)" = '"carried"' ]
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

@test "concurrent concern adds mint distinct ids (the mint is locked)" {
  # CC_RESEARCH_TEST_MINT_DELAY (test-only) holds each writer between reading the max and reserving.
  for i in 1 2 3 4; do
    CC_RESEARCH_TEST_MINT_DELAY=0.3 "$CR" concern add --program demo --text "race $i" > "$BATS_TEST_TMPDIR/add.$i" 2>&1 &
  done
  wait
  run /usr/bin/python3 -c "import json; ids=[json.loads(l)['id'] for l in open('$REC/challenges.jsonl') if 'race ' in l]; print(len(ids), len(set(ids)))"
  [ "$status" -eq 0 ]
  [ "$output" = "4 4" ]
}

@test "park writes a parked operator_new change and the certificate's parked count goes up" {
  run "$CR" park --program demo --idea "a dashboard"
  [ "$status" -eq 0 ]
  [ "$(fold changes.jsonl CR-1 cause)" = '"operator_new"' ]
  git -C "$REC" add -A && git -C "$REC" commit -qm park  # row 12 refuses uncommitted records
  run "$G" run --program demo --consent-sealed-read
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
