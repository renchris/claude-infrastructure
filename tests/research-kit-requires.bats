#!/usr/bin/env bats
# research-kit-requires — `gate.sh requires` and `handoff-fire.sh --requires-gate <program>`
# (REPORT.md §3.10 "Carried rows at build time", §5.4, §8 item 13). A certified program's build wave
# fires only when nothing in its dependency closure is open or carried-unresolved: a FAIL row, an
# unresolved class-C row, a carried set (exempt for the wave that owns its narrowing probe), an open
# frame-omission known row, or a wave the sweep descoped.
#
# The known-good program (tests/fixtures/research-kit/build_good.py) is certified here by writing its
# certificate and registry state directly, so this suite tests the reader's contract and not the
# sixteen gate rows (tests/research-kit-gate.bats owns those). Each case plants ONE input and asserts
# the verdict it must produce; the CLEAR case is the control every REFUSED case is measured against.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  export W="$BATS_TEST_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  mkdir -p "$W"
  REC="$("$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$W")"
  # handoff-fire seams (test-hermeticity-lint rules 2 and 5): the box capacity gate off, and every
  # non-$HOME default pinned to an ABSENT per-test path, so no case reads live load, the operator's
  # /tmp state, or a claude-accounts off their PATH.
  export CC_FIRE_CAPACITY_GATE=off HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
}

# certify [row-status-override-json]: write CERT-v1 with all 16 rows PASS (merged with the override)
# and set the registry to certified, as a passing `gate.sh run` leaves them.
certify() {
  /usr/bin/env python3 - "$REC" "$CC_RESEARCH_REGISTRY" "${1:-{\}}" <<'PY'
import json, sys, os
rec, reg, over = sys.argv[1], sys.argv[2], json.loads(sys.argv[3])
rows = {str(n): "PASS" for n in range(1, 17)}
rows.update(over)
os.makedirs(os.path.join(rec, "cert"), exist_ok=True)
json.dump({"cert": "CERT-v1", "program": "demo", "version": 1, "rows": rows},
          open(os.path.join(rec, "cert", "CERT-v1.json"), "w"))
d = json.load(open(reg))
for p in d["programs"]:
    if p["slug"] == "demo":
        p["state"] = "certified"
json.dump(d, open(reg, "w"))
PY
}
dec() { printf '%s\n' "$1" >> "$REC/decisions.jsonl"; }
kr()  { printf '%s\n' "$1" >> "$REC/known_rows.jsonl"; }

# ── the verb ─────────────────────────────────────────────────────────────────────────────────────

@test "CONTROL: a certified program with nothing carried is CLEAR for a named wave and for every wave" {
  certify
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ]
  [[ "$output" == "CLEAR demo wave B1: CERT-v1"* ]]
  run "$G" requires --program demo
  [ "$status" -eq 0 ]
}

@test "a registered, never-certified program refuses: no build wave fires before the gate passes" {
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 1 ]
  [[ "$output" == *"'registered', not 'certified'"* ]] || false
  [[ "$output" == *"no certificate"* ]]
}

@test "certifying (frozen, gate not yet passed) refuses" {
  certify
  /usr/bin/env python3 -c "import json; p='$CC_RESEARCH_REGISTRY'; d=json.load(open(p)); d['programs'][0]['state']='certifying'; json.dump(d, open(p,'w'))"
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 1 ]
  [[ "$output" == *"'certifying'"* ]]
}

@test "a FAIL row on the newest certificate refuses, naming the row" {
  certify '{"11": "FAIL"}'
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL row(s) 11"* ]]
}

@test "an unresolved class-C row refuses exactly the waves it blocks" {
  certify
  dec '{"id":"DR-9","status":"carried","packet":{"id":"p","class":"C","due":"2099-01-01T00:00:00Z"},"blocks_waves":["B2"]}'
  run "$G" requires --program demo --wave B2
  [ "$status" -eq 1 ]
  [[ "$output" == *"DR-9: unresolved class-C row"* ]] || false
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ]
}

@test "a carried set blocks its dependent waves but is exempt for the wave owning its narrowing probe" {
  certify
  dec '{"id":"DR-8","status":"carried","set":{"members":[],"narrowing_probe":{"wave":"B3"}},"blocks_waves":["B3","B4"]}'
  run "$G" requires --program demo --wave B3
  [ "$status" -eq 0 ]
  run "$G" requires --program demo --wave B4
  [ "$status" -eq 1 ]
  [[ "$output" == *"DR-8: carried set (narrows in B3)"* ]]
}

@test "an open frame-omission known row refuses its waves until it closes (§5.4)" {
  certify
  kr '{"id":"KR-1","kind":"frame-omission","status":"open","names_rows":["A-3"],"blocks_waves":["B5"]}'
  run "$G" requires --program demo --wave B5
  [ "$status" -eq 1 ]
  [[ "$output" == *"KR-1: open frame-omission row"* ]] || false
  # the frame-delta cycle closes it: the LIVE records are read, so the wave clears without a reopen
  kr '{"id":"KR-1","status":"closed"}'
  run "$G" requires --program demo --wave B5
  [ "$status" -eq 0 ]
}

@test "a wave the sweep descoped refuses, for a decision and for a known row" {
  certify
  dec '{"id":"DR-7","status":"carried","packet":{"id":"q","class":"B","due":"2099-01-01T00:00:00Z"},"descoped_waves":["B6"]}'
  kr '{"id":"KR-2","kind":"frame-omission","status":"closed","descoped_waves":["B7"]}'
  run "$G" requires --program demo --wave B6
  [ "$status" -eq 1 ]
  [[ "$output" == *"DR-7: descoped wave B6"* ]] || false
  run "$G" requires --program demo --wave B7
  [ "$status" -eq 1 ]
  [[ "$output" == *"KR-2: descoped wave B7"* ]]
}

@test "without --wave there is no closure to scope to, so a block on ANY wave refuses (fail closed)" {
  certify
  dec '{"id":"DR-9","status":"carried","packet":{"id":"p","class":"C","due":"2099-01-01T00:00:00Z"},"blocks_waves":["B2"]}'
  run "$G" requires --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"pass the wave id"* ]]
}

@test "an unregistered program is rc 2 (cannot read), distinct from rc 1 (refused)" {
  run "$G" requires --program nope --wave B1
  [ "$status" -eq 2 ]
  [[ "$output" == *"not registered"* ]]
}

@test "--json carries the verdict and every reason" {
  certify '{"3": "FAIL"}'
  run "$G" requires --program demo --wave B1 --json
  [ "$status" -eq 1 ]
  printf '%s' "$output" | /usr/bin/env python3 -c "import json,sys; d=json.load(sys.stdin); assert d['verdict']=='refused' and d['wave']=='B1' and any('FAIL row(s) 3' in r for r in d['reasons'])"
}

# ── handoff-fire.sh --requires-gate ──────────────────────────────────────────────────────────────

hf_env() {
  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — research build wave fixture payload." > "$PAYLOAD"
}

@test "handoff-fire --requires-gate REFUSES a blocked wave before any side effect (exit 2, research-gate)" {
  hf_env; certify
  dec '{"id":"DR-9","status":"carried","packet":{"id":"p","class":"C","due":"2099-01-01T00:00:00Z"},"blocks_waves":["B2"]}'
  run bash "$HF" --prompt-file "$PAYLOAD" --dry-run --requires-gate demo --gate-wave B2
  [ "$status" -eq 2 ]
  [[ "$output" == *"research gate REFUSES this build wave"* ]] || false
  [[ "$output" == *"DR-9: unresolved class-C row"* ]]
}

@test "handoff-fire --requires-gate ADMITS a clear wave and proceeds past the gate" {
  hf_env; certify
  run bash "$HF" --prompt-file "$PAYLOAD" --dry-run --requires-gate demo --gate-wave B1
  # A dry run that clears the gate proceeds into the rest of the script, which has its own exit paths
  # under a fixtured $HOME; the gate's verdict is what is under test, so: not the gate's refusal, and
  # its CLEAR line printed.
  [[ "$output" == *"CLEAR demo wave B1"* ]] || false
  [[ "$output" != *"research gate REFUSES"* ]]
}

@test "handoff-fire --requires-gate on an unreadable program refuses and says it could not read it" {
  hf_env
  run bash "$HF" --prompt-file "$PAYLOAD" --dry-run --requires-gate nope --gate-wave B1
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not be read (rc 2)"* ]]
}

@test "handoff-fire refuses when the kit is absent: an unreadable gate is not a passed one" {
  hf_env; certify
  CC_RESEARCH_GATE="$BATS_TEST_TMPDIR/absent/gate.sh" run bash "$HF" --prompt-file "$PAYLOAD" --dry-run --requires-gate demo --gate-wave B1
  [ "$status" -eq 2 ]
  [[ "$output" == *"research kit is not installed"* ]]
}

@test "handoff-fire --gate-wave without --requires-gate is a usage refusal" {
  hf_env
  run bash "$HF" --prompt-file "$PAYLOAD" --dry-run --gate-wave B1
  [ "$status" -eq 2 ]
  [[ "$output" == *"--gate-wave scopes --requires-gate"* ]]
}

@test "the payload marker handoff-fire appends is one the re-ask router labels work-order without a classifier" {
  # The literal line handoff-fire.sh writes into the fired session's brief, extracted from the script
  # so a reworded marker that the router no longer matches turns this case red.
  fmt="$(grep -o "research work order: --requires-gate %s wave %s (handoff-fire)" "$HF")"
  [ -n "$fmt" ]
  # shellcheck disable=SC2059  # the format string IS the subject: it is the script's own printf format
  line="$(printf "$fmt" demo B1)"
  run bash -c "printf 'build wave B1 brief\n<!-- %s -->\n' '$line' | CC_RESEARCH_CLASSIFIER=false python3 '$REPO/scripts/research-kit/router.py' classify"
  [ "$status" -eq 0 ]
  [ "$output" = "work-order" ]
}
