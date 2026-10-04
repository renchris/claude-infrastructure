#!/usr/bin/env bats
# research-kit-lease — the program lease (audit 2026-10-04, continuity lens item 6): one owner at a time
# writes a program's records. A fresh lease held by another owner makes every writing verb of
# cc-research, gate.sh, round.sh and seed.py refuse (exit 2, naming the holder); read verbs never
# check; a stale heartbeat or no lease file lets anyone write.

setup() {
  unset CC_BATS_ACTIVE CC_RESEARCH_OWNER CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CR="$REPO/bin/cc-research"
  G="$REPO/scripts/research-kit/gate.sh"
  R="$REPO/scripts/research-kit/round.sh"
  SEED="$REPO/scripts/research-kit/seed.py"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  export CC_RESEARCH_VAULT_KEY="test-key"
  mkdir -p "$CC_RESEARCH_RECORDS"
  LEASE="$CC_RESEARCH_HOME/demo/lease.json"
}

as() { # <owner> <cmd...>: run one command as that lease owner
  local o="$1"
  shift
  CC_RESEARCH_OWNER="$o" "$@"
}
stale_lease() { # <owner>: a lease whose heartbeat is two hours old
  local old
  old="$(date -u -v-2H +%Y-%m-%dT%H:%M:%SZ)"
  mkdir -p "$CC_RESEARCH_HOME/demo"
  printf '{"owner":"%s","pid":1,"host":"h","acquired":"%s","heartbeat":"%s"}\n' "$1" "$old" "$old" > "$LEASE"
}

@test "owner A acquires; B's writing verbs refuse naming A; B's read verbs run" {
  run as A "$CR" lease acquire --program demo
  [ "$status" -eq 0 ]
  [ -f "$LEASE" ]
  run as B "$CR" concern add --program demo --text "worry"
  [ "$status" -eq 2 ]
  [[ "$output" == *"leased to A"* ]] || false
  run as B "$G" close --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"leased to A"* ]] || false
  run as B "$R" close --program demo --round 1
  [ "$status" -eq 2 ]
  [[ "$output" == *"leased to A"* ]] || false
  run as B "$SEED" prescreen --program demo --caught S-1
  [ "$status" -eq 2 ]
  [[ "$output" == *"leased to A"* ]] || false
  run as B "$CR" concern list --program demo
  [ "$status" -eq 0 ]
  run as B "$SEED" status --program demo
  [ "$status" -eq 0 ]
  run as B "$CR" lease show --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *'"owner": "A"'* ]] || false
  [ ! -e "$CC_RESEARCH_RECORDS/challenges.jsonl" ]
}

@test "the holder writes, and its check refreshes the heartbeat" {
  stale_lease A
  before="$(/usr/bin/python3 -c "import json; print(json.load(open('$LEASE'))['heartbeat'])")"
  run as A "$CR" concern add --program demo --text "mine"
  [ "$status" -eq 0 ]
  after="$(/usr/bin/python3 -c "import json; print(json.load(open('$LEASE'))['heartbeat'])")"
  [ "$after" != "$before" ]
  run as B "$CR" concern add --program demo --text "theirs"
  [ "$status" -eq 2 ]
}

@test "a stale heartbeat lets B write and take the lease" {
  stale_lease A
  run as B "$CR" concern add --program demo --text "worry"
  [ "$status" -eq 0 ]
  run as B "$CR" lease acquire --program demo
  [ "$status" -eq 0 ]
  run /usr/bin/python3 -c "import json; print(json.load(open('$LEASE'))['owner'])"
  [ "$output" = B ]
}

@test "no lease file: anyone writes" {
  run as A "$CR" concern add --program demo --text "one"
  [ "$status" -eq 0 ]
  run as B "$CR" concern add --program demo --text "two"
  [ "$status" -eq 0 ]
  [ ! -e "$LEASE" ]
}

@test "acquire and release by another owner refuse while the lease is fresh; the holder releases" {
  run as A "$CR" lease acquire --program demo
  [ "$status" -eq 0 ]
  run as B "$CR" lease acquire --program demo
  [ "$status" -eq 2 ]
  [[ "$output" == *"leased to A"* ]] || false
  run as B "$CR" lease release --program demo
  [ "$status" -eq 2 ]
  run as A "$CR" lease release --program demo
  [ "$status" -eq 0 ]
  [ ! -e "$LEASE" ]
  run "$CR" lease show --program demo
  [ "$status" -eq 0 ]
  [[ "$output" == *"no lease"* ]]
}

@test "owner identity: CC_RESEARCH_OWNER, else the Claude session id, else pid:<ppid>" {
  CLAUDE_CODE_SESSION_ID=sess-1 run "$CR" lease acquire --program demo
  [ "$status" -eq 0 ]
  run /usr/bin/python3 -c "import json; print(json.load(open('$LEASE'))['owner'])"
  [ "$output" = sess-1 ]
  CLAUDE_CODE_SESSION_ID=sess-1 run "$CR" concern add --program demo --text "mine"
  [ "$status" -eq 0 ]
  run "$CR" concern add --program demo --text "theirs"
  [ "$status" -eq 2 ]
  [[ "$output" == *"leased to sess-1"* ]] || false
  [[ "$output" == *"you are pid:"* ]]
}
