#!/usr/bin/env bats
# cc-research-built — method v1.2, REPORT.md §11: the code-native instruments of Stage 9
# (`cc-research built finding|mutate|contact|soak`, lib/built.py). A finding is material only with
# a test the tool itself saw fail; sealed mutants are run against the acceptance harness on a COPY
# of the artifact; contact re-runs from an empty HOME with PATH=/usr/bin:/bin under /bin/bash; the
# soak samples the acceptance checks.
#
# The fixture is the known-good program plus a small built artifact (a git repo with out.txt,
# n.txt and extra.txt), two acceptance rows that read it through $ARTIFACT, and four sealed
# mutants: M-1 and M-2 the harness kills, M-3 it misses, M-4 whose text is absent.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$CC_NOW" > "$BATS_FILE_TMPDIR/now"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  mkdir -p "$W"
  "$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$W" > "$BATS_FILE_TMPDIR/records-path"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  A="$W/artifact"
  mkdir -p "$A" "$REC/built" "$CC_RESEARCH_HOME/demo/built" "$W/bin"
  printf 'ok\n' > "$A/out.txt"; printf '3\n' > "$A/n.txt"; printf 'keep\n' > "$A/extra.txt"
  git -C "$A" init -q
  git -C "$A" -c user.name=t -c user.email=t@t add -A
  git -C "$A" -c user.name=t -c user.email=t@t commit -qm built
  /usr/bin/python3 - "$REC" "$A" "$CC_RESEARCH_HOME/demo/built/mutants.json" "$CC_NOW" <<'PY'
import json, subprocess, sys
rec, art, mutants, now = sys.argv[1:5]
fr = json.load(open(f"{rec}/frame.json")); fr["method_version"] = "1.2"
json.dump(fr, open(f"{rec}/frame.json", "w"))
acc = json.load(open(f"{rec}/acceptance.json"))
base = acc["rows"][0]
acc["rows"] = [dict(base, id="AM-1", check_cmd='grep -q ok "$ARTIFACT/out.txt"'),
               dict(base, id="AM-2", check_cmd='test "$(cat "$ARTIFACT/n.txt")" = 3')]
json.dump(acc, open(f"{rec}/acceptance.json", "w"))
sha = subprocess.run(["git", "-C", art, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
json.dump({"snapshot_sha": sha, "artifact_root": art, "frozen_at": now, "research_cert": "CERT-v1",
           "waves_done": []}, open(f"{rec}/built/freeze.json", "w"))
json.dump([{"id": "M-1", "file": "out.txt", "search": "ok", "replace": "bad"},
           {"id": "M-2", "file": "n.txt", "search": "3", "replace": "4"},
           {"id": "M-3", "file": "extra.txt", "search": "keep", "replace": "drop"},
           {"id": "M-4", "file": "out.txt", "search": "absent-text", "replace": "x"}], open(mutants, "w"))
with open(f"{rec}/probes.jsonl", "a") as fh:
    for pid, cmd in (("P-only", ["onlyhere"]),
                     ("P-env", ["/bin/bash", "-c", 'test -z "$(ls -A "$HOME")" && test "$PATH" = /usr/bin:/bin'])):
        fh.write(json.dumps({"id": pid, "kind": "handed-cmd", "cmd": cmd, "exit": 0, "at": now,
                             "negative_control": {"ran": True, "reported_refutation": True}}) + "\n")
PY
  printf '#!/bin/bash\nexit 0\n' > "$W/bin/onlyhere"; chmod +x "$W/bin/onlyhere"
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  R="$REPO/bin/cc-research"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  A="$W/artifact"
}

jedit() {
  /usr/bin/python3 -c "import json; p='$REC/$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"
}
# finding <id> <python expression over f>: a field of the folded finding.
finding() {
  /usr/bin/python3 -c "
import json
f = {}
for line in open('$REC/built/findings.jsonl'):
    r = json.loads(line)
    if r['id'] == '$1': f.update(r)
print(($2))"
}
# mutant <id> <python expression over m>
mutant() {
  /usr/bin/python3 -c "import json; m=[x for x in json.load(open('$REC/built/mutation.json'))['mutants'] if x['id']=='$1'][0]; print(($2))"
}
treehash() { (cd "$A" && find . -type f -not -path './.git/*' -exec shasum {} + | sort | shasum | cut -d' ' -f1); }
last() { /usr/bin/python3 -c "import json; r=[json.loads(l) for l in open('$REC/$1')][-1]; print(($2))"; }

@test "every built verb refuses without a pinned built snapshot" {
  rm "$REC/built/freeze.json"
  run "$R" built show --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"no built snapshot"* ]] || false
  run "$R" built mutate --program demo
  [ "$status" -eq 2 ]
  run "$R" built soak sample --program demo
  [ "$status" -eq 2 ]
}

@test "every built verb refuses a frame signed under method 1.1" {
  jedit frame.json "d.pop('method_version')"
  run "$R" built finding add --program demo --source round --claim c --severity material --test-cmd false
  [ "$status" -eq 2 ]
  [[ "$output" == *"method 1.2"* ]] || false
  [ ! -e "$REC/built/findings.jsonl" ]
}

@test "a material finding whose test fails on the snapshot is open, with the failing run recorded by the tool" {
  run "$R" built finding add --program demo --source round --claim "no report file" --severity material --test-cmd 'test -f report.txt'
  [ "$status" -eq 0 ]
  sha="$(git -C "$A" rev-parse HEAD)"
  [ "$(finding BF-1 "f['status'], f['repro']['red']['exit'], f['repro']['red']['sha'] == '$sha'")" = "('open', 1, True)" ]
}

@test "a material finding whose test passes is not admitted: rejected-no-repro, no red run" {
  run "$R" built finding add --program demo --source round --claim "looks wrong" --severity material --test-cmd 'true'
  [ "$status" -eq 0 ]
  [[ "$output" == *"not material"* ]] || false
  [ "$(finding BF-1 "f['status'], f['repro']['red']")" = "('rejected-no-repro', None)" ]
}

@test "a material finding with no test command is rejected-no-repro" {
  run "$R" built finding add --program demo --source round --claim "just a feeling" --severity material
  [ "$status" -eq 0 ]
  [ "$(finding BF-1 "f['status'], f['repro']")" = "('rejected-no-repro', None)" ]
}

@test "finding fix refuses while the repro still fails, and accepts it once it passes" {
  "$R" built finding add --program demo --source round --claim "no report file" --severity material --test-cmd 'test -f report.txt'
  run "$R" built finding fix --program demo --id BF-1
  [ "$status" -eq 1 ]
  [ "$(finding BF-1 "f['status']")" = "open" ]
  touch "$A/report.txt"
  run "$R" built finding fix --program demo --id BF-1
  [ "$status" -eq 0 ]
  [ "$(finding BF-1 "f['status'], f['repro']['green']['exit'], f['repro']['red']['exit']")" = "('fixed', 0, 1)" ]
}

@test "mutate refuses when the harness fails on the unmutated artifact" {
  printf 'bad\n' > "$A/out.txt"
  run "$R" built mutate --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"passing baseline"* ]] || false
  [ ! -e "$REC/built/mutation.json" ]
}

@test "mutate classifies killed, survived and invalid mutants, and names the rows that killed" {
  run "$R" built mutate --program demo
  [ "$status" -eq 1 ]
  [ "$(mutant M-1 "m['status'], m['killed_by']")" = "('killed', ['AM-1'])" ]
  [ "$(mutant M-2 "m['status'], m['killed_by']")" = "('killed', ['AM-2'])" ]
  [ "$(mutant M-3 "m['status']")" = "survived" ]
  [ "$(mutant M-4 "m['status']")" = "invalid" ]
  [ "$(/usr/bin/python3 -c "import json; d=json.load(open('$REC/built/mutation.json')); print(d['killed'], d['survived'], d['kill_rate'], d['baseline_exit'])")" = "2 1 0.6667 0" ]
}

@test "mutate never changes the artifact: every mutant runs on a copy" {
  before="$(treehash)"
  run "$R" built mutate --program demo
  [ "$(mutant M-1 "m['status']")" = "killed" ]
  [ "$(treehash)" = "$before" ]
  [ -z "$(git -C "$A" status --porcelain)" ]
}

@test "a surviving mutant becomes one open material finding, once" {
  run "$R" built mutate --program demo
  run "$R" built mutate --program demo
  [ "$(grep -c '"mutant": "M-3"' "$REC/built/findings.jsonl")" -eq 1 ]
  [ "$(finding BF-1 "f['source'], f['severity'], f['status'], f['mutant']")" = "('mutation', 'material', 'open', 'M-3')" ]
}

@test "a survivor's finding is fixed by a harness row that kills it, and the re-run is recorded" {
  run "$R" built mutate --program demo
  jedit acceptance.json "d['rows'].append(dict(d['rows'][0], id='AM-3', check_cmd='grep -q keep \"\$ARTIFACT/extra.txt\"'))"
  run "$R" built finding fix --program demo --id BF-1
  [ "$status" -eq 0 ]
  [ "$(finding BF-1 "f['status']")" = "fixed" ]
  [ "$(mutant M-3 "m['status'], m['killed_by'], m['rerun']")" = "('killed', ['AM-3'], 1)" ]
}

@test "a survivor is re-run once: a second re-run without a kill is refused at the cap" {
  run "$R" built mutate --program demo
  run "$R" built finding fix --program demo --id BF-1
  [ "$status" -eq 1 ]
  run "$R" built finding fix --program demo --id BF-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"the cap is 1 per survivor"* ]] || false
  [ "$(mutant M-3 "m['status'], m['rerun']")" = "('survived', 1)" ]
}

@test "an equivalent mutant needs a reason and a rater, and must be a survivor" {
  run "$R" built mutate --program demo
  run "$R" built mutate --program demo --equivalent M-3 --reason "same output"
  [ "$status" -eq 2 ]
  [[ "$output" == *"both --reason and --rater"* ]] || false
  run "$R" built mutate --program demo --equivalent M-1 --reason r --rater openai
  [ "$status" -eq 2 ]
  [[ "$output" == *"only a survivor"* ]] || false
  run "$R" built mutate --program demo --equivalent M-3 --reason "extra.txt is never read" --rater openai
  [ "$status" -eq 0 ]
  [ "$(mutant M-3 "m['status'], m['equivalent']['rater']")" = "('equivalent', 'openai')" ]
  [ "$(finding BF-1 "f['status']")" = "rejected-no-repro" ]
}

@test "contact runs from an empty environment: a tool only on the caller's PATH is not found" {
  export PATH="$W/bin:$PATH"
  onlyhere
  run "$R" built contact --program demo --target P-only --no-negative-control "an inventory read"
  [ "$status" -eq 1 ]
  [ "$(last built/contact.jsonl "r['target'], r['exit']")" = "('P-only', 127)" ]
}

@test "contact records the environment it set: empty HOME, PATH=/usr/bin:/bin, /bin/bash 3.2" {
  run "$R" built contact --program demo --target P-env --no-negative-control "an inventory read"
  [ "$status" -eq 0 ]
  [ "$(last built/contact.jsonl "r['exit'], r['env']['home_clean'], r['env']['path'], r['env']['interpreter'], r['env']['interpreter_version'][:3]")" = "(0, True, '/usr/bin:/bin', '/bin/bash', '3.2')" ]
  sha="$(git -C "$A" rev-parse HEAD)"
  [ "$(last built/contact.jsonl "r['snapshot_sha'] == '$sha'")" = "True" ]
}

@test "contact re-runs an acceptance row by id, and refuses an unknown target" {
  run "$R" built contact --program demo --target AM-1 --no-negative-control "read-only"
  [ "$status" -eq 0 ]
  [ "$(last built/contact.jsonl "r['target'], r['exit']")" = "('AM-1', 0)" ]
  run "$R" built contact --program demo --target NOPE --no-negative-control x
  [ "$status" -eq 2 ]
}

@test "contact refuses without a negative control or a reason, and records one that ran" {
  run "$R" built contact --program demo --target AM-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"shown able to fail"* ]] || false
  [ ! -e "$REC/built/contact.jsonl" ]
  run "$R" built contact --program demo --target AM-1 --negative-control 'grep -q ok "$ARTIFACT/n.txt"'
  [ "$status" -eq 0 ]
  [ "$(last built/contact.jsonl "r['negative_control']['ran'], r['negative_control']['exit'], r['negative_control']['reported_refutation']")" = "(True, 1, True)" ]
}

@test "soak sample appends one sample per acceptance row and reports a failing check" {
  run "$R" built soak sample --program demo
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$REC/built/soak.jsonl" | tr -d ' ')" = "2" ]
  [ "$(last built/soak.jsonl "r['check'], r['exit'], r['at'] == '$CC_NOW'")" = "('AM-2', 0, True)" ]
  printf '4\n' > "$A/n.txt"
  run "$R" built soak sample --program demo
  [ "$status" -eq 1 ]
  [ "$(last built/soak.jsonl "r['check'], r['exit']")" = "('AM-2', 1)" ]
}

@test "a soak restart names a finding on record and is refused past the cap" {
  run "$R" built soak restart --program demo --finding BF-1
  [ "$status" -eq 2 ]
  "$R" built finding add --program demo --source soak --claim "flaky at midnight" --severity material --test-cmd false
  "$R" built soak restart --program demo --finding BF-1
  "$R" built soak restart --program demo --finding BF-1
  run "$R" built soak restart --program demo --finding BF-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"the cap is 2"* ]] || false
  [ "$(/usr/bin/python3 -c "import json; print(len(json.load(open('$REC/built/soak.json'))['restarts']))")" = "2" ]
}

@test "built show counts findings, mutants, contact runs and soak samples" {
  "$R" built finding add --program demo --source round --claim c --severity material --test-cmd false
  run "$R" built mutate --program demo
  run "$R" built show --program demo --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | /usr/bin/python3 -c "import json,sys; s=json.load(sys.stdin); print(s['findings']['open'], s['mutants']['killed'], s['mutants']['survived'])")" = "2 2 1" ]
}
