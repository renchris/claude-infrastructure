#!/usr/bin/env bats
# research-kit-built-gate — the built gate of research method v1.2: `gate.sh built-run`, rows 20-25
# (REPORT.md §11, scripts/research-kit/lib/gate_rows_built.py).
#
# One known-good built program (tests/fixtures/research-kit/build_good.py, then build_built.py)
# passes all six rows. Every other test restores it, plants ONE defect in the Stage 9 records, and
# asserts that the named row turns FAIL for that reason. The rows are read from the JSON that
# built-run prints, never from its exit code: the certificate it writes after an all-pass run is
# another module.

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
  "$BATS_TEST_DIRNAME/fixtures/research-kit/build_built.py" "$W"
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  FX="$BATS_TEST_DIRNAME/fixtures/research-kit/build_built.py"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  ART="$W/artifact"
  OUT="$BATS_TEST_TMPDIR/rows.json"
}

# gate: one built-run, its rows kept in $OUT. The exit code is not the subject (see the header).
gate() { "$G" built-run --program demo --json > "$OUT" 2>/dev/null || true; }
# rowstat <n>: the status of built-gate row n on the last run.
rowstat() {
  /usr/bin/python3 -c "import json,sys; print([r['status'] for r in json.load(open(sys.argv[1])) if r['num'] == $1][0])" "$OUT"
}
# rowtext <n>: the evidence lines of row n on the last run.
rowtext() {
  /usr/bin/python3 -c "import json,sys; print('\n'.join([r for r in json.load(open(sys.argv[1])) if r['num'] == $1][0]['evidence']))" "$OUT"
}
# fails <n> <text>: run the gate; row n is FAIL and its evidence names <text>.
fails() {
  gate
  [[ "$(rowstat "$1")" == FAIL ]] || { rowtext "$1"; return 1; }
  [[ "$(rowtext "$1")" == *"$2"* ]] || { rowtext "$1"; return 1; }
}
# jedit <file under REC> <python statement over d>: edit a JSON record in place.
jedit() {
  /usr/bin/python3 -c "import json; p='$REC/$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"
}
# jledit <file under REC> <python statement over rows>: edit a JSONL record list in place.
jledit() {
  /usr/bin/python3 -c "
import json, time, calendar
p='$REC/$1'
rows=[json.loads(l) for l in open(p) if l.strip()]
now=calendar.timegm(time.strptime('$CC_NOW', '%Y-%m-%dT%H:%M:%SZ'))
iso=lambda t: time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(t))
$2
open(p, 'w').write(''.join(json.dumps(r) + '\n' for r in rows))"
}
# ago <hours>: the ISO instant that many hours before the fixture's now.
ago() { date -u -v-"$1"H -j -f %Y-%m-%dT%H:%M:%SZ "$CC_NOW" +%Y-%m-%dT%H:%M:%SZ; }

# ── known good ──────────────────────────────────────────────────────────────────────────────────

@test "known-good built program: rows 20-25 all PASS and the plan is six rows" {
  gate
  run /usr/bin/python3 -c "import json,sys; print(' '.join(f\"{r['num']}:{r['status']}\" for r in json.load(open(sys.argv[1]))))" "$OUT"
  [[ "$output" == "20:PASS 21:PASS 22:PASS 23:PASS 24:PASS 25:PASS" ]] || false
  [[ "$(rowtext 21)" == *"1 rejected-no-repro"* ]] || false
  [[ "$(rowtext 22)" == *"kill rate 10/10"* ]]
}

@test "built-run writes nothing into the records or the artifact" {
  before="$(cd "$W" && find repo artifact -type f -not -path '*/.git/*' -not -name 'BUILT-CERT-*' -exec shasum {} + | sort)"
  gate
  after="$(cd "$W" && find repo artifact -type f -not -path '*/.git/*' -not -name 'BUILT-CERT-*' -exec shasum {} + | sort)"
  [[ "$(rowstat 20)" == PASS ]] || false
  [[ "$before" == "$after" ]]
}

# ── row 20: built snapshot ──────────────────────────────────────────────────────────────────────

@test "row 20: no built/freeze.json fails" {
  rm "$REC/built/freeze.json"
  fails 20 "built/freeze.json is missing"
}

@test "row 20: a research certificate with no valid operator signature fails" {
  jedit cert/CERT-v1.json "d['note'] = 'edited after the signature'"
  fails 20 "no valid operator signature"
}

@test "row 20: a signed research certificate holding a FAIL row fails" {
  jedit cert/CERT-v1.json "d['rows']['7'] = 'FAIL'"
  "$FX" "$W" resign
  fails 20 "row(s) not passed: 7"
  [[ "$(rowtext 20)" != *"no valid operator signature"* ]]
}

@test "row 20: a reopen signed after the research certificate fails" {
  "$FX" "$W" reopen
  fails 20 "reopen is signed after"
}

@test "row 20: a build wave the frame names and the freeze did not record fails" {
  jedit built/freeze.json "d['waves_done'] = ['B1']"
  fails 20 "not recorded done: B2"
}

@test "row 20: an artifact HEAD that moved past the snapshot fails" {
  echo more >> "$ART/daemon.sh"
  git -C "$ART" commit -q -am "after the freeze"
  fails 20 "is not the built snapshot"
}

@test "row 20: a dirty artifact tree fails" {
  echo more >> "$ART/daemon.sh"
  fails 20 "artifact tree is dirty"
}

@test "row 20: a last counted built round on another snapshot fails" {
  jedit rounds/b2/matrix.json "d['snapshot_sha'] = 'f' * 40"
  fails 20 "last counted built round b2 examined"
}

# ── row 21: repro ───────────────────────────────────────────────────────────────────────────────

@test "row 21: an open material finding fails" {
  jledit built/findings.jsonl "rows.append(dict(rows[0], id='BF-9', status='open'))"
  fails 21 "BF-9: material finding is open"
}

@test "row 21: a fixed material finding with no recorded failing run fails" {
  jledit built/findings.jsonl "rows[0]['repro']['red'] = None"
  fails 21 "BF-1: no tool-recorded failing run"
}

@test "row 21: a recorded 'failing' run that exited 0 is not a failing run" {
  jledit built/findings.jsonl "rows[0]['repro']['red']['exit'] = 0"
  fails 21 "BF-1: no tool-recorded failing run"
}

@test "row 21: a test command that fails when re-run now on the snapshot fails" {
  jledit built/findings.jsonl "rows[0]['repro']['test_cmd'] = 'test -f absent.sh'"
  fails 21 "BF-1: test command exits 1 now"
}

@test "row 21: the test command is re-run in the artifact, not trusted from its green record" {
  git -C "$ART" rm -q daemon.sh
  git -C "$ART" commit -q -m "regress"
  fails 21 "BF-1: test command exits 1 now"
}

@test "row 21: a rejected-no-repro finding never fails the row, and is counted" {
  jledit built/findings.jsonl "rows.append(dict(rows[1], id='BF-8'))"
  gate
  [[ "$(rowstat 21)" == PASS ]] || false
  [[ "$(rowtext 21)" == *"2 rejected-no-repro"* ]]
}

# ── row 22: harness mutation ────────────────────────────────────────────────────────────────────

@test "row 22: no built/mutation.json fails" {
  rm "$REC/built/mutation.json"
  fails 22 "built/mutation.json is missing"
}

@test "row 22: a mutation run on another snapshot fails" {
  jedit built/mutation.json "d['snapshot_sha'] = 'f' * 40"
  fails 22 "not the built snapshot"
}

@test "row 22: an unmutated baseline that did not pass fails" {
  jedit built/mutation.json "d['baseline_exit'] = 1"
  fails 22 "unmutated baseline exited 1"
}

@test "row 22: fewer mutants than the floor fails, and an invalid mutant does not count" {
  jedit built/mutation.json "[m.update(status='invalid') for m in d['mutants'][:2]]"
  fails 22 "9 mutant(s), fewer than"
}

@test "row 22: an acceptance row no mutant was killed by fails" {
  jedit acceptance.json "d['rows'].append(dict(d['rows'][0], id='AM-2'))"
  fails 22 "acceptance row AM-2"
}

@test "row 22: a surviving mutant fails" {
  jedit built/mutation.json "d['mutants'].append({'id': 'M-99', 'status': 'survived', 'killed_by': []})"
  fails 22 "surviving mutant(s): M-99"
  [[ "$(rowtext 22)" == *"kill rate 10/11"* ]]
}

@test "row 22: an equivalent mutant without a rater fails" {
  jedit built/mutation.json "[m['equivalent'].pop('rater') for m in d['mutants'] if m['status'] == 'equivalent']"
  fails 22 "lacks a reason or a rater"
}

@test "row 22: an equivalent mutant without a reason fails" {
  jedit built/mutation.json "[m['equivalent'].pop('reason') for m in d['mutants'] if m['status'] == 'equivalent']"
  fails 22 "lacks a reason or a rater"
}

# ── row 23: as-built contact ────────────────────────────────────────────────────────────────────

@test "row 23: an as-built probe with no run on this snapshot fails" {
  jledit built/contact.jsonl "rows[0]['snapshot_sha'] = 'f' * 40"
  fails 23 "P-3: no as-built run on this snapshot"
}

@test "row 23: an acceptance row with no run fails" {
  jledit built/contact.jsonl "rows.pop(1)"
  fails 23 "AM-1: no as-built run on this snapshot"
}

@test "row 23: the newest run of a target exiting nonzero fails" {
  jledit built/contact.jsonl "rows.append(dict(rows[0], id='BC-9', exit=1))"
  fails 23 "P-3: as-built run exits 1"
}

@test "row 23: a HOME that was not clean fails" {
  jledit built/contact.jsonl "rows[0]['env']['home_clean'] = False"
  fails 23 "P-3: environment is not as-built (home_clean)"
}

@test "row 23: a PATH wider than the as-built one fails" {
  jledit built/contact.jsonl "rows[0]['env']['path'] = '/opt/homebrew/bin:/usr/bin:/bin'"
  fails 23 "P-3: environment is not as-built (path)"
}

@test "row 23: an interpreter other than /bin/bash fails" {
  jledit built/contact.jsonl "rows[0]['env']['interpreter'] = '/opt/homebrew/bin/bash'"
  fails 23 "P-3: environment is not as-built (interpreter)"
}

@test "row 23: a bash that is not 3.2 fails" {
  jledit built/contact.jsonl "rows[0]['env']['interpreter_version'] = '5.2.37(1)-release'"
  fails 23 "P-3: environment is not as-built (interpreter_version)"
}

@test "row 23: a negative control that did not run and gives no reason fails" {
  jledit built/contact.jsonl "rows[0]['negative_control'] = {'ran': False}"
  fails 23 "P-3: no negative control and no reason"
}

@test "row 23: a negative control that ran and refuted nothing fails" {
  jledit built/contact.jsonl "rows[0]['negative_control']['reported_refutation'] = False"
  fails 23 "P-3: no negative control and no reason"
}

@test "row 23: a negative control not run for a stated reason passes" {
  jledit built/contact.jsonl "rows[0]['negative_control'] = {'ran': False, 'reason_if_not_run': 'no known-bad input exists'}"
  gate
  [[ "$(rowstat 23)" == PASS ]]
}

# ── row 24: soak ────────────────────────────────────────────────────────────────────────────────

@test "row 24: samples spanning less than the minimum hours fail" {
  jledit built/soak.jsonl "[r.update(at=iso(now - i * 600)) for i, r in enumerate(reversed(rows))]"
  fails 24 "h, under the"
}

@test "row 24: fewer samples than the minimum fail" {
  jledit built/soak.jsonl "rows[:] = rows[::2]"
  fails 24 "16 sample(s), fewer than"
}

@test "row 24: one failing sample fails" {
  jledit built/soak.jsonl "rows[5]['exit'] = 1"
  fails 24 "1 failing sample(s)"
}

@test "row 24: samples before the last restart do not count" {
  jedit built/soak.json "d['restarts'] = [{'at': '$(ago 10)', 'finding': 'BF-1'}]"
  fails 24 "h, under the"
  [[ "$(rowtext 24)" == *"sample(s), fewer than"* ]]
}

@test "row 24: samples on another snapshot do not count" {
  jledit built/soak.jsonl "[r.update(snapshot_sha='f' * 40) for r in rows[:20]]"
  fails 24 "11 sample(s), fewer than"
}

@test "row 24: more restarts than the cap fail" {
  jedit built/soak.json "d['restarts'] = [{'at': '$(ago 40)', 'finding': 'BF-1'}] * 3"
  fails 24 "3 restart(s), more than"
}

@test "row 24: a computable boundary that no passing sample crossed fails" {
  jledit built/soak.jsonl "[r.update(at=iso(now)) for r in rows]"
  fails 24 "boundary hour: not crossed"
}

@test "row 24: a boundary the gate cannot compute, with no residual, fails" {
  jedit frame.json "d['soak_boundaries'] = ['hour', 'month-end']"
  fails 24 "boundary month-end: not crossed"
}

@test "row 24: an uncrossed boundary declared as an elapsed-time residual is FILED" {
  jedit frame.json "d['soak_boundaries'] = ['hour', 'month-end']"
  jledit residual.jsonl "rows.append({'id': 'RS-9', 'why_unreachable': 'elapsed-time', 'boundary': 'month-end', 'owner': 'operator', 'due': iso(now + 30 * 86400)[:10]})"
  gate
  [[ "$(rowstat 24)" == FILED ]] || false
  [[ "$(rowtext 24)" == *"FILED boundary month-end"* ]]
}

@test "row 24: a boundary residual with no owner does not file the boundary" {
  jedit frame.json "d['soak_boundaries'] = ['hour', 'month-end']"
  jledit residual.jsonl "rows.append({'id': 'RS-9', 'why_unreachable': 'elapsed-time', 'boundary': 'month-end', 'due': iso(now + 30 * 86400)[:10]})"
  fails 24 "boundary month-end: not crossed"
}

# ── row 25: built rounds ────────────────────────────────────────────────────────────────────────

@test "row 25: no counted built round on this snapshot fails" {
  jedit rounds/b1/matrix.json "d['snapshot_sha'] = 'f' * 40"
  jedit rounds/b2/matrix.json "d['snapshot_sha'] = 'f' * 40"
  fails 25 "no counted built round on this snapshot"
}

@test "row 25: a counted round with an incomplete slot fails" {
  jedit rounds/b2/matrix.json "d['slots'][0]['status'] = 'dead'"
  fails 25 "round b2: slot b2p1 is dead"
}

@test "row 25: a counted round with one vendor family fails" {
  jedit rounds/b2/matrix.json "d['slots'] = [s for s in d['slots'] if s['vendor'] in ('anthropic', 'frontier')]"
  fails 25 "round b2: 1 vendor family"
}

@test "row 25: more built rounds than the profile's cap fails" {
  for n in 3 4; do
    mkdir "$REC/rounds/b$n"
    cp "$REC/rounds/b2/matrix.json" "$REC/rounds/b$n/matrix.json"
    jedit "rounds/b$n/matrix.json" "d.update(round='b$n', seq=$n)"
  done
  fails 25 "4 counted built round(s), past the cap"
}

@test "row 25: rounds that neither ended quiet nor reached the cap fail" {
  jedit rounds/b2/matrix.json "d.update(quiet=False, new_material=1)"
  fails 25 "have not stopped"
}

@test "row 25: rounds that reached the cap without a quiet finish pass" {
  mkdir "$REC/rounds/b3"
  cp "$REC/rounds/b2/matrix.json" "$REC/rounds/b3/matrix.json"
  jedit rounds/b3/matrix.json "d.update(round='b3', seq=3, quiet=False, new_material=1)"
  gate
  [[ "$(rowstat 25)" == PASS ]] || false
  [[ "$(rowtext 25)" == *"stop cap"* ]]
}

@test "row 25: a round that did not count neither stops the rounds nor fills the cap" {
  jedit rounds/b2/matrix.json "d['counted'] = False"
  fails 25 "have not stopped"
}
