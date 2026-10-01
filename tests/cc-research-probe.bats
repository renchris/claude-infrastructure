#!/usr/bin/env bats
# cc-research-probe — bin/cc-research probe | doctor | self-test (REPORT.md §8 item 10, §3.4, §3.6).
# `probe` and `doctor` absorb scripts/research-kit/probe-run.sh, which is now a shim over them; the
# self-test runs every acceptance row over its known-bad and known-good fixtures and must refuse a
# row that cannot fail, one that fails on good input, and one with no fixtures at all.

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
  CR="$REPO/bin/cc-research"
  PR="$REPO/scripts/research-kit/probe-run.sh"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
}

# jedit <file under REC> <python statement over d>: edit a JSON record in place.
jedit() {
  /usr/bin/python3 -c "import json; p='$REC/$1'; d=json.load(open(p)); $2; json.dump(d, open(p, 'w'))"
}
# lastrec <records dir> <python expr over r, the last probe record>
lastrec() {
  /usr/bin/python3 -c "import json; r=[json.loads(l) for l in open('$1/probes.jsonl')][-1]; print($2)"
}

# A fake interactive zsh (the same shape tests/research-kit-probe.bats uses): a PATH holding a tool
# the agent's PATH does not, `print`/`whence` shims, and terminal escape noise on the answer line.
fake_zsh() {
  mkdir -p "$BATS_TEST_TMPDIR/ipath"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/ipath/codex"
  chmod +x "$BATS_TEST_TMPDIR/ipath/codex"
  cat > "$BATS_TEST_TMPDIR/fake-zsh" <<EOF
#!/bin/bash
shift
export PATH="$BATS_TEST_TMPDIR/ipath:/usr/bin:/bin"
print() { shift; shift; printf '\033]1337;CurrentDir=/x\007%s\n' "\$*"; }
whence() { command -v "\$2"; }
echo "banner from an rc file"
eval "\$1"
EOF
  chmod +x "$BATS_TEST_TMPDIR/fake-zsh"
  export CC_RESEARCH_ZSH="$BATS_TEST_TMPDIR/fake-zsh"
}

@test "probe writes the same probes.jsonl record the kit's probe runner wrote" {
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/old"
  /usr/bin/env python3 "$REPO/scripts/research-kit/lib/probe_run.py" run --program demo --id P-1 \
    --kind read --closes PR-1 --negative-control false -- printf 'a b\n'
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/new"
  run "$CR" probe --program demo --id P-1 --kind read --closes PR-1 --negative-control false -- printf 'a b\n'
  [ "$status" -eq 0 ]
  [[ "$output" == *"P-1 kind=read exit=0 n=1 level=E2"* ]] || false
  /usr/bin/python3 -c "
import json
o = json.loads(open('$BATS_TEST_TMPDIR/old/probes.jsonl').read())
n = json.loads(open('$BATS_TEST_TMPDIR/new/probes.jsonl').read())
for r in (o, n):
    r['env']['descriptor'].pop('interpreter')
assert o == n, (o, n)"
  [ "$(cat "$BATS_TEST_TMPDIR/new/evidence/P-1/stdout")" = "a b" ]
}

@test "probe keeps the runner's refusals: --mutates-live exits 2 and writes nothing" {
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/r"
  run "$CR" probe --program demo --id P-2 --kind spike --mutates-live --negative-control false -- true
  [ "$status" -eq 2 ]
  [[ "$output" == *"probes never change the live subject"* ]] || false
  [ ! -e "$CC_RESEARCH_RECORDS/probes.jsonl" ]
}

@test "self-test passes the known-good program and records the row as one probe through the runner" {
  run "$CR" self-test --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS AM-1 bad=1 good=0"* ]] || false
  [ "$(lastrec "$REC" 'r["id"], r["exit"], r["negative_control"]["exit"], r["negative_control"]["reported_refutation"]')" = "P-selftest-AM-1-1 0 1 True" ]
  run "$CR" self-test --program demo
  [ "$(lastrec "$REC" 'r["id"]')" = "P-selftest-AM-1-2" ]
}

@test "self-test fails a row whose check passes on its known-bad fixture" {
  jedit acceptance.json "d['rows'][0]['check_cmd'] = 'true'"
  run "$CR" self-test --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL AM-1 bad=0 good=0"* ]]
}

@test "self-test fails a row whose check fails on its known-good fixture" {
  jedit acceptance.json "d['rows'][0]['check_cmd'] = 'grep -q nope \"\$FIXTURE\"'"
  run "$CR" self-test --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL AM-1 bad=1 good=1"* ]]
}

@test "self-test fails a row with no controls, and runs nothing for it" {
  jedit acceptance.json "d['rows'][0].pop('control')"
  before="$(wc -l < "$REC/probes.jsonl")"
  run "$CR" self-test --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL AM-1 bad=- good=-"* ]] || false
  [ "$(wc -l < "$REC/probes.jsonl")" -eq "$before" ]
}

@test "self-test --row selects one row, --json reports it, and an unknown row is refused" {
  jedit acceptance.json "d['rows'].append(dict(d['rows'][0], id='AM-2', check_cmd='true'))"
  run "$CR" self-test --program demo --row AM-1 --json
  [ "$status" -eq 0 ]
  /usr/bin/python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert [r['row'] for r in d['rows']] == ['AM-1'], d
assert d['rows'][0]['verdict'] == 'PASS' and d['passed'] is True, d" "$output"
  run "$CR" self-test --program demo --row AM-9
  [ "$status" -eq 2 ]
}

@test "doctor reports a tool on the interactive PATH only as hidden, and one on the agent PATH only as present" {
  fake_zsh
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/r"
  mkdir -p "$BATS_TEST_TMPDIR/agentonly"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/agentonly/shellcheck"
  chmod +x "$BATS_TEST_TMPDIR/agentonly/shellcheck"
  PATH="$BATS_TEST_TMPDIR/agentonly:/usr/bin:/bin" run "$CR" doctor --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"codex"*"$BATS_TEST_TMPDIR/ipath/codex"*"hidden from the agent PATH"* ]] || false
  [[ "$output" == *"shellcheck"*"$BATS_TEST_TMPDIR/agentonly/shellcheck"* ]] || false
  /usr/bin/python3 -c "
import json; d = json.load(open('$CC_RESEARCH_RECORDS/evidence/doctor/env.json'))
assert d['tools']['codex']['state'] == 'hidden', d['tools']['codex']
assert d['tools']['shellcheck']['state'] == 'agent-only', d['tools']['shellcheck']
assert d['tools']['bats']['state'] == 'absent', d['tools']['bats']"
}

@test "doctor reads credential expiry from frame.json credentials" {
  fake_zsh
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/r"
  mkdir -p "$CC_RESEARCH_RECORDS"
  local good
  good="$(date -u -v+8760H +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"credentials":[{"name":"old-token","expires":"2020-01-01T00:00:00Z"},{"name":"good-token","expires":"%s"},{"name":"no-date"}]}\n' "$good" \
    > "$CC_RESEARCH_RECORDS/frame.json"
  run "$CR" doctor --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"old-token"*"expired"* ]] || false
  /usr/bin/python3 -c "
import json; d = json.load(open('$CC_RESEARCH_RECORDS/evidence/doctor/env.json'))
c = {x['name']: x['state'] for x in d['credential_expiry']}
assert c == {'old-token': 'expired', 'good-token': 'ok', 'no-date': 'unknown'}, c"
}

@test "doctor without a frame says the credential expiry is unknown, never fine" {
  fake_zsh
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/r"
  run "$CR" doctor --program demo
  [ "$status" -eq 0 ]
  grep -q '"credential_expiry": "unknown: no frame.json' "$CC_RESEARCH_RECORDS/evidence/doctor/env.json"
}

@test "probe-run.sh is a shim: its doctor is cc-research's, credential expiry included" {
  fake_zsh
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/r"
  mkdir -p "$CC_RESEARCH_RECORDS"
  printf '%s\n' '{"credentials":[{"name":"old-token","expires":"2020-01-01T00:00:00Z"}]}' > "$CC_RESEARCH_RECORDS/frame.json"
  run "$PR" doctor --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"old-token"*"expired"* ]] || false
  run "$PR" bogus
  [ "$status" -eq 2 ]
  if command -v shellcheck >/dev/null; then
    run shellcheck "$PR" # run bare, as the land gate does
    [ "$status" -eq 0 ]
  fi
}
