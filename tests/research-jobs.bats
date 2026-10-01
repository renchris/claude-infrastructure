#!/usr/bin/env bats
# research-jobs — `cc-research job …`, the launchd runner, the five staged plists and migration 0051
# (REPORT.md §5.5, §8 item 12, §10 item 4). Every runner and the migration run under /bin/bash 3.2,
# the interpreter launchd uses. Real bin/cc-decide in a scratch decisions dir; triage is a fake
# cc-research (CC_RESEARCH_BIN), because that verb belongs to another module.

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
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CC_RESEARCH_BIN CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CLI="$REPO/bin/cc-research"
  G="$REPO/scripts/research-kit/gate.sh"
  D="$REPO/bin/cc-decide"
  RUNNER="$REPO/scripts/research-kit/jobs/research-job.sh"
  MIG="$REPO/migrations/0051-research-jobs.sh"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  reg demo certifying
}

reg() { # <slug> <state>: registry entry (roots under the fixture repo)
  /usr/bin/python3 -c "import sys; sys.path.insert(0, '$REPO/scripts/research-kit/lib'); import kit
kit.registry_set('$1', '$2', cwd_roots=['$W/repo'])"
}
job() { /usr/bin/python3 "$CLI" job "$@"; }
later() { /usr/bin/python3 -c "import time,calendar; t=calendar.timegm(time.strptime('$CC_NOW','%Y-%m-%dT%H:%M:%SZ'))+$1*86400; print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(t)))"; }
count() { # <file> <python predicate over r>
  /usr/bin/python3 -c "
import json, os
n = 0
if os.path.exists('$1'):
    for l in open('$1'):
        r = json.loads(l)
        n += bool($2)
print(n)"
}
premise() { # <id> <recheck_cmd> <verdict> [ttl_h]
  printf '{"id":"%s","truth_lives_in":"code","verdict":"%s","recheck_cmd":"%s","validated_at":{"ts":"2026-09-01T00:00:00Z"},"ttl_h":%s}\n' \
    "$1" "$3" "$2" "${4:-1}" >> "$REC/premises.jsonl"
}

@test "/bin/bash is 3.2, the interpreter launchd uses" {
  run /bin/bash --version
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"version 3.2"* ]]
}

@test "freshness: an expired premise is re-checked as a probe; a flipped verdict files a drift challenge" {
  premise PR-9 false holds
  premise PR-8 true holds
  run job freshness --program demo
  [ "$status" -eq 0 ]
  [ "$(count "$REC/probes.jsonl" "'PR-9' in r.get('closes', []) and r['exit'] != 0")" -eq 1 ]
  [ "$(count "$REC/probes.jsonl" "'PR-8' in r.get('closes', []) and r['exit'] == 0")" -eq 1 ]
  [ "$(count "$REC/challenges.jsonl" "r['raised_by'] == 'sweep' and r['kind'] == 'drift' and r['premise'] == 'PR-9' and r['triage'] == 'pending'")" -eq 1 ]
  [ "$(count "$REC/challenges.jsonl" "r.get('premise') == 'PR-8'")" -eq 0 ]
  [ "$(count "$REC/premises.jsonl" "r['id'] in ('PR-8', 'PR-9') and r.get('carried') is True")" -eq 2 ]
}

@test "freshness: a premise is re-validated once per program, never again" {
  premise PR-9 false holds
  run job freshness --program demo
  [ "$status" -eq 0 ]
  CC_NOW="$(later 3)" run job freshness --program demo
  [ "$status" -eq 0 ]
  [ "$(count "$REC/probes.jsonl" "'PR-9' in r.get('closes', [])")" -eq 1 ]
  [ "$(count "$REC/challenges.jsonl" "r.get('premise') == 'PR-9'")" -eq 1 ]
}

@test "drift: the first run records a baseline and files nothing; a rule edit naming a row files reality_moved" {
  R="$BATS_TEST_TMPDIR/rules"
  mkdir -p "$R/.claude/rules" "$R/docs/lessons"
  echo "# global" > "$R/CLAUDE.global.md"
  echo "rule one" > "$R/.claude/rules/a.md"
  echo "lesson" > "$R/docs/lessons/x.md"
  /usr/bin/python3 -c "import json; p='$REC/acceptance.json'; d=json.load(open(p))
d['rows'].append(dict(d['rows'][0], id='AM-2', rule_refs=['docs/lessons/x.md'])); json.dump(d, open(p, 'w'))"
  export CC_RESEARCH_RULES_ROOT="$R"
  run job drift --program demo
  [ "$status" -eq 0 ]
  [ -f "$CC_RESEARCH_HOME/demo/drift-state.json" ]
  [ "$(count "$REC/changes.jsonl" "r.get('source') == 'rule-drift'")" -eq 0 ]
  echo "AM-1 no longer holds" >> "$R/.claude/rules/a.md"
  run job drift --program demo
  [ "$status" -eq 0 ]
  [ "$(count "$REC/changes.jsonl" "r['source'] == 'rule-drift' and r['cause'] == 'reality_moved' and r['affected_rows'] == ['AM-1'] and r['id'].startswith('CR-')")" -eq 1 ]
  echo "lesson edited" >> "$R/docs/lessons/x.md"
  run job drift --program demo
  [ "$status" -eq 0 ]
  [ "$(count "$REC/changes.jsonl" "r['source'] == 'rule-drift' and r['affected_rows'] == ['AM-2']")" -eq 1 ]
  run job drift --program demo
  [ "$(count "$REC/changes.jsonl" "r.get('source') == 'rule-drift'")" -eq 2 ]
}

@test "market: parks only unseen items, and only once its cadence has passed" {
  F="$BATS_TEST_TMPDIR/releases.txt"
  printf 'v1\nv2\n' > "$F"
  /usr/bin/python3 -c "import json; p='$REC/frame.json'; d=json.load(open(p))
d['populations_outside']=[{'name':'releases','refresh_cmd':'cat $F','owner':'lead','cadence_days':7}]; json.dump(d, open(p, 'w'))"
  printf '{"population":"releases","members":[{"id":"v1"}]}\n' > "$REC/census/releases.json"
  run job market --program demo
  [ "$status" -eq 0 ]
  parked="r.get('source') == 'market' and r['status'] == 'parked' and r['cause'] == 'reality_moved'"
  [ "$(count "$REC/changes.jsonl" "$parked")" -eq 1 ]
  [ "$(count "$REC/changes.jsonl" "$parked and r['justification'] == 'v2'")" -eq 1 ]
  echo v3 >> "$F"
  run job market --program demo
  [ "$(count "$REC/changes.jsonl" "$parked")" -eq 1 ]
  CC_NOW="$(later 8)" run job market --program demo
  [ "$status" -eq 0 ]
  [ "$(count "$REC/changes.jsonl" "$parked")" -eq 2 ]
  [ "$(count "$REC/changes.jsonl" "$parked and r['justification'] == 'v3'")" -eq 1 ]
}

@test "sweep: an expired class-B packet's default is applied to the decision record" {
  printf '{"id":"DR-1","status":"carried","blocks_waves":["B1"]}\n' >> "$REC/decisions.jsonl"
  id="$("$G" file-packet --program demo --decision DR-1 --class B --what "retry policy" --option "retry::writes retried" \
    --option "do-nothing::no change" --default retry --deadline 2026-10-01T00:00:00Z --conviction 80 --receipt "$REC/frame.json" | awk '{print $2}')"
  /bin/bash "$D" expire-sweep >/dev/null
  run job sweep --program demo
  [ "$status" -eq 0 ]
  [ "$(count "$REC/decisions.jsonl" "r['id'] == 'DR-1' and r.get('ruled_by') == 'packet-default' and r.get('chosen') == 'retry'")" -eq 1 ]
  [ -n "$id" ]
}

@test "no --program iterates only certifying|certified programs, and one failure does not stop the rest" {
  reg x-reg registered
  reg x-cert certified
  reg x-closed closed
  FAKE="$BATS_TEST_TMPDIR/fake-cc-research"
  printf '#!/bin/bash\necho "$*" >> "%s"\n[ "$3" = demo ] && exit 1\nexit 0\n' "$BATS_TEST_TMPDIR/calls" > "$FAKE"
  chmod +x "$FAKE"
  CC_RESEARCH_BIN="$FAKE" run job triage
  [ "$status" -eq 1 ]
  run cat "$BATS_TEST_TMPDIR/calls"
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "triage --program demo" ]
  [ "${lines[1]}" = "triage --program x-cert" ]
}

@test "runner: refuses an unknown job (exit 2) and execs cc-research job <name>" {
  run /bin/bash "$RUNNER" bogus
  [ "$status" -eq 2 ]
  FAKE="$BATS_TEST_TMPDIR/fake-cc-research"
  printf '#!/bin/bash\necho "$*" > "%s"\n' "$BATS_TEST_TMPDIR/args" > "$FAKE"
  chmod +x "$FAKE"
  CC_RESEARCH_BIN="$FAKE" run /bin/bash "$RUNNER" drift
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/args")" = "job drift" ]
}

@test "plists: plutil -lint passes, each runs /bin/bash on the runner, on its calendar" {
  for spec in sweep:Minute:7 freshness:Hour:6 triage:Hour:7 drift:Hour:5 drift:Minute:30 market:Weekday:1 market:Hour:8; do
    j="${spec%%:*}"; rest="${spec#*:}"; key="${rest%%:*}"; want="${rest#*:}"
    P="$REPO/launchd/staged/com.claude.research-$j.plist"
    /usr/bin/plutil -lint "$P" >/dev/null
    [ "$(/usr/bin/plutil -extract ProgramArguments.0 raw "$P")" = /bin/bash ]
    [[ "$(/usr/bin/plutil -extract ProgramArguments.1 raw "$P")" == */.claude/scripts/research-kit/jobs/research-job.sh ]]
    [ "$(/usr/bin/plutil -extract ProgramArguments.2 raw "$P")" = "$j" ]
    [ "$(/usr/bin/plutil -extract Label raw "$P")" = "com.claude.research-$j" ]
    [ "$(/usr/bin/plutil -extract "StartCalendarInterval.$key" raw "$P")" = "$want" ]
    [[ "$(/usr/bin/plutil -extract StandardOutPath raw "$P")" == */.claude/logs/research-$j.out.log ]]
  done
}

@test "migration --dry-run under /bin/bash lists five labels and writes nothing" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\necho called >> "%s"\n' "$BATS_TEST_TMPDIR/launchctl-calls" > "$BATS_TEST_TMPDIR/bin/launchctl"
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
  export HOME="$BATS_TEST_TMPDIR/mhome"   # empty, so "writes nothing" is checkable
  mkdir -p "$HOME"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$MIG" --dry-run
  [ "$status" -eq 0 ]
  for j in sweep freshness triage drift market; do
    [[ "$output" == *"com.claude.research-$j"* ]]
  done
  [ -z "$(find "$HOME" -mindepth 1)" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl-calls" ]
  grep -q '^# migration-class: c10$' "$MIG"
  grep -q '^# migration-verify: ' "$MIG"
  grep -q '^# migration-run: ' "$MIG"
}

@test "shellcheck, bare, is clean on the runner and the migration" {
  run shellcheck "$RUNNER" "$MIG"
  [ "$status" -eq 0 ]
}
