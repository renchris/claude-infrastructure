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

@test "sweep, no --program, under the launchd runner: a registered program with an open packet is swept" {
  reg demo registered
  reg x-reg registered
  printf '{"id":"DR-1","status":"carried","blocks_waves":["B1"]}\n' >> "$REC/decisions.jsonl"
  past="$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ)"
  "$G" file-packet --program demo --decision DR-1 --class B --what "retry policy" --option "retry::writes retried" \
    --option "do-nothing::no change" --default retry --deadline "$past" --conviction 80 --receipt "$REC/frame.json" >/dev/null
  /bin/bash "$D" expire-sweep >/dev/null
  CC_RESEARCH_BIN="$CLI" run /bin/bash "$RUNNER" sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"job sweep demo: ok"* ]] || false
  [[ "$output" != *"x-reg"* ]] || false
  [ "$(count "$REC/decisions.jsonl" "r['id'] == 'DR-1' and r.get('ruled_by') == 'packet-default' and r.get('chosen') == 'retry'")" -eq 1 ]
  reg demo closed
  CC_RESEARCH_BIN="$CLI" run /bin/bash "$RUNNER" sweep
  [ "$status" -eq 0 ]
  [[ "$output" == *"no program in certifying|certified, nor registered with an open packet"* ]]
}

@test "no --program iterates only certifying|certified programs, and one failure does not stop the rest" {
  reg x-reg registered
  reg x-cert certified
  reg x-closed closed
  FAKE="$BATS_TEST_TMPDIR/fake-cc-research"
  # shellcheck disable=SC2016  # the fake's $* and $3 expand when it runs, not here
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
    [[ "$(/usr/bin/plutil -extract ProgramArguments.1 raw "$P")" == */.claude/scripts/research-kit/jobs/research-job.sh ]] || false
    [ "$(/usr/bin/plutil -extract ProgramArguments.2 raw "$P")" = "$j" ]
    [ "$(/usr/bin/plutil -extract Label raw "$P")" = "com.claude.research-$j" ]
    [ "$(/usr/bin/plutil -extract "StartCalendarInterval.$key" raw "$P")" = "$want" ]
    [[ "$(/usr/bin/plutil -extract StandardOutPath raw "$P")" == */.claude/logs/research-$j.out.log ]] || false
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
    [[ "$output" == *"com.claude.research-$j"* ]] || false
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

@test "every staged plist's runner is a file install.sh links and deploy-parity-assert declares" {
  # The plists name the runner by its LIVE path; ~/.claude/scripts/ is a per-file symlink farm built
  # by install.sh's research-kit loop, so a subdirectory that loop skips is a job that runs nothing.
  for j in sweep freshness triage drift market; do
    P="$REPO/launchd/staged/com.claude.research-$j.plist"
    rel="$(/usr/bin/plutil -extract ProgramArguments.1 raw "$P")"
    rel="${rel#*/.claude/}"
    [ -f "$REPO/$rel" ]
    sub="$(dirname "${rel#scripts/research-kit}")"
    grep -Eq "for sub in .*\"$sub\"" "$REPO/install.sh"
    grep -Fq "cls='$(dirname "$rel")/*'" "$REPO/scripts/deploy-parity-assert.sh"
  done
}

# ── wave E3c: the Stage 9 soak scheduler (REPORT.md §11 instrument 4, row 24) ─────────────────────

SOAK_MIG() { echo "$REPO/migrations/0058-research-soak-job.sh"; }

stage9() { # turn the fixture's demo into a Stage 9 program: a 1.2 frame, a built artifact, a freeze
  local A="$W/artifact"
  mkdir -p "$A" "$REC/built"
  printf 'ok\n' > "$A/out.txt"
  git -C "$A" init -q
  git -C "$A" -c user.name=t -c user.email=t@t add -A
  git -C "$A" -c user.name=t -c user.email=t@t commit -qm built
  /usr/bin/python3 - "$REC" "$A" "$CC_NOW" <<'PY'
import json, subprocess, sys
rec, art, now = sys.argv[1:4]
fr = json.load(open(f"{rec}/frame.json")); fr["method_version"] = "1.2"
json.dump(fr, open(f"{rec}/frame.json", "w"))
acc = json.load(open(f"{rec}/acceptance.json"))
base = acc["rows"][0]
acc["rows"] = [dict(base, id="AM-1", check_cmd='grep -q ok "$ARTIFACT/out.txt"'),
               dict(base, id="AM-2", check_cmd='test -z "$(ls -A "$HOME")"')]
json.dump(acc, open(f"{rec}/acceptance.json", "w"))
sha = subprocess.run(["git", "-C", art, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
json.dump({"snapshot_sha": sha, "artifact_root": art, "frozen_at": now, "research_cert": "CERT-v1",
           "waves_done": []}, open(f"{rec}/built/freeze.json", "w"))
PY
  reg demo build-certifying
}

@test "soak: no --program samples every acceptance check of a build-certifying program, the as-built way" {
  stage9
  reg x-cert certified
  run job soak
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"job soak demo: ok — 2 sample(s), all pass"* ]] || false
  [[ "$output" != *"x-cert"* ]] || false
  # AM-2 passes only under the empty HOME the as-built run gives it
  [ "$(count "$REC/built/soak.jsonl" "r['exit'] == 0 and r['check'] in ('AM-1', 'AM-2')")" -eq 2 ]
  [ -f "$REC/built/soak.json" ]
}

@test "soak: a failing sample fails the pass and names the check, so the log is never quiet about it" {
  stage9
  printf 'bad\n' > "$W/artifact/out.txt"
  run job soak --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"job soak demo: FAILED — 2 sample(s), failing: AM-1"*"built finding add --source soak"* ]] || false
  [ "$(count "$REC/built/soak.jsonl" "r['check'] == 'AM-1' and r['exit'] != 0")" -eq 1 ]
}

@test "soak: only build-certifying is sampled; a certified program draws a refusal, not a sample" {
  run job soak
  [ "$status" -eq 0 ]
  [[ "$output" == *"job soak: no program in build-certifying"* ]] || false
  run job soak --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in build-certifying"* ]] || false
  [ ! -e "$REC/built/soak.jsonl" ]
}

@test "soak runner: /bin/bash 3.2 accepts soak and execs cc-research job soak" {
  FAKE="$BATS_TEST_TMPDIR/fake-cc-research"
  printf '#!/bin/bash\necho "$*" > "%s"\n' "$BATS_TEST_TMPDIR/args" > "$FAKE"
  chmod +x "$FAKE"
  CC_RESEARCH_BIN="$FAKE" run /bin/bash "$RUNNER" soak
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/args")" = "job soak" ]
}

@test "soak plist: staged, lints, runs /bin/bash on the shared runner hourly at :17, declared in the fleet manifest" {
  P="$REPO/launchd/staged/com.claude.research-soak.plist"
  /usr/bin/plutil -lint "$P" >/dev/null
  grep -q 'STAGED, NOT LOADED' "$P"
  [ "$(/usr/bin/plutil -extract Label raw "$P")" = com.claude.research-soak ]
  [ "$(/usr/bin/plutil -extract ProgramArguments.0 raw "$P")" = /bin/bash ]
  [[ "$(/usr/bin/plutil -extract ProgramArguments.1 raw "$P")" == */.claude/scripts/research-kit/jobs/research-job.sh ]] || false
  [ "$(/usr/bin/plutil -extract ProgramArguments.2 raw "$P")" = soak ]
  [ "$(/usr/bin/plutil -extract StartCalendarInterval.Minute raw "$P")" = 17 ]
  [[ "$(/usr/bin/plutil -extract StandardOutPath raw "$P")" == */.claude/logs/research-soak.out.log ]] || false
  grep -Eq '^com\.claude\.research-soak +\| staged \| 3600 +\| auto \| - \| 0058-research-soak-job\.sh$' "$REPO/launchd/fleet.manifest"
}

@test "soak migration: c10, --dry-run under /bin/bash names the label and writes nothing; bad args exit 2" {
  M="$(SOAK_MIG)"
  grep -q '^# migration-class: c10$' "$M"
  grep -q '^# migration-verify: launchctl print gui/$(id -u)/com.claude.research-soak' "$M"
  grep -q '^# migration-run: bash ~/Development/claude-infrastructure/migrations/0058-research-soak-job.sh$' "$M"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\necho called >> "%s"\n' "$BATS_TEST_TMPDIR/launchctl-calls" > "$BATS_TEST_TMPDIR/bin/launchctl"
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
  export HOME="$BATS_TEST_TMPDIR/mhome"
  mkdir -p "$HOME"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" run /bin/bash "$M" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would install $REPO/launchd/staged/com.claude.research-soak.plist"* ]] || false
  [ -z "$(find "$HOME" -mindepth 1)" ]
  [ ! -e "$BATS_TEST_TMPDIR/launchctl-calls" ]
  run /bin/bash "$M" --bogus
  [ "$status" -eq 2 ]
}

@test "soak migration: a real run refuses until the live layer has the runner, and loads nothing" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\necho "$*" >> "%s"\nexit 1\n' "$BATS_TEST_TMPDIR/launchctl-calls" > "$BATS_TEST_TMPDIR/bin/launchctl"
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
  export HOME="$BATS_TEST_TMPDIR/mhome"
  mkdir -p "$HOME"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" CC_MIGRATION_LA_DIR="$HOME/LA" run /bin/bash "$(SOAK_MIG)"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not in the live layer yet"* ]] || false
  [ ! -e "$HOME/LA/com.claude.research-soak.plist" ]
}

@test "soak migration: with the live layer present it installs the plist and reads the load back" {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # a launchctl that 'loads' on bootstrap and answers print only after it
  cat > "$BATS_TEST_TMPDIR/bin/launchctl" <<SH
#!/bin/bash
case "\$1" in
  bootstrap) touch "$BATS_TEST_TMPDIR/loaded"; exit 0 ;;
  bootout) exit 0 ;;
  print) [ -e "$BATS_TEST_TMPDIR/loaded" ] ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
  export HOME="$BATS_TEST_TMPDIR/mhome"
  mkdir -p "$HOME/.claude/scripts/research-kit/jobs" "$HOME/.claude/bin"
  : > "$HOME/.claude/scripts/research-kit/jobs/research-job.sh"; : > "$HOME/.claude/bin/cc-research"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" CC_MIGRATION_LA_DIR="$HOME/LA" run /bin/bash "$(SOAK_MIG)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"com.claude.research-soak loaded"* ]] || false
  cmp -s "$REPO/launchd/staged/com.claude.research-soak.plist" "$HOME/LA/com.claude.research-soak.plist"
  # a re-run over identical bytes is a no-op
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" CC_MIGRATION_REPO="$REPO" CC_MIGRATION_LA_DIR="$HOME/LA" run /bin/bash "$(SOAK_MIG)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already loaded from the repo plist"* ]] || false
}

@test "soak: shellcheck, bare, is clean on the runner and the soak migration" {
  run shellcheck "$RUNNER" "$(SOAK_MIG)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}
