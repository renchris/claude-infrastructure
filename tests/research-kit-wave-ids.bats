#!/usr/bin/env bats
# research-kit-wave-ids — the build-wave gate resolves a wave id against ONE canonical set per program
# (`gate.sh requires`, `handoff-fire.sh --requires-gate`), refuses an id outside it naming the
# near-miss, refuses either spelling while the records spell one wave two ways, and `gate.sh
# rekey-wave` re-spells a known row's or decision's waves by an appended event (RECORDS.md "Wave ids").
#
# RED-proof (2026-10-16, measured by the lead on b2ed965e3): `requires --wave D0` listed the open
# frame-omission rows KR-06 and KR-07 while `--wave Day0`, the id the fire recipe passes, listed only
# the certificate reasons, so a certified Day 0 wave would have fired past two open rows. On that kit
# every case below that expects a refusal reads CLEAR (rc 0), and `rekey-wave` and `waves` are unknown
# verbs (rc 2 from argparse with no record written).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CC_RESEARCH_OWNER
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
  # handoff-fire seams, as tests/research-kit-requires.bats pins them (test-hermeticity-lint).
  # One export per line: the pin-guard (handoff-fire-capacity-gate.bats case 25) reads them that way.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
}

# certify: CERT-v1 with every row PASS, the registry certified, the certificate operator-signed.
certify() {
  /usr/bin/env python3 - "$REC" "$CC_RESEARCH_REGISTRY" <<'PY'
import json, sys, os
rec, reg = sys.argv[1], sys.argv[2]
os.makedirs(os.path.join(rec, "cert"), exist_ok=True)
json.dump({"cert": "CERT-v1", "program": "demo", "version": 1,
           "rows": {str(n): "PASS" for n in range(1, 18)}},
          open(os.path.join(rec, "cert", "CERT-v1.json"), "w"))
d = json.load(open(reg))
for p in d["programs"]:
    if p["slug"] == "demo":
        p["state"] = "certified"
json.dump(d, open(reg, "w"))
PY
  "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/cert --evidence fixture > /dev/null
}
dec() { printf '%s\n' "$1" >> "$REC/decisions.jsonl"; }
kr()  { printf '%s\n' "$1" >> "$REC/known_rows.jsonl"; }
# folded <store> <id> <field>: the field of the folded record, as JSON
folded() {
  /usr/bin/python3 -c "
import json; s = {}
for l in open('$REC/$1'):
    if l.strip(): r = json.loads(l); s.setdefault(r['id'], {}).update(r)
print(json.dumps(s['$2'].get('$3')))"
}

# The live truememory-2-0 shape: two open rows keyed D0 and one keyed release, while the decisions and
# the fire recipe spell the same waves Day0 and rel.
plant_measured_shape() {
  kr '{"id":"KR-06","kind":"frame-omission","status":"open","names_rows":["AM-9"],"blocks_waves":["D0","W1"],"resign_due":"2099-01-01T00:00:00Z","default":"class-b","ts":"2026-10-12T08:38:14Z"}'
  kr '{"id":"KR-13","kind":"frame-omission","status":"open","names_rows":["AM-9"],"blocks_waves":["release"],"resign_due":"2099-01-01T00:00:00Z","default":"class-b","ts":"2026-10-12T08:38:14Z"}'
  dec '{"id":"DR-09","status":"ruled","ruled_by":"operator","blocks_waves":["W0","Day0"],"ts":"2026-10-01T00:00:00Z"}'
  dec '{"id":"DR-07","status":"ruled","ruled_by":"operator","blocks_waves":["rel"],"ts":"2026-10-01T00:00:00Z"}'
}

# ── resolving a wave id ──────────────────────────────────────────────────────────────────────────

@test "CONTROL: a wave the frame's build_waves or a record names resolves, and a clear one is CLEAR" {
  certify
  run "$G" requires --program demo --wave B1 # the fixture frame's build_waves
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  dec '{"id":"DR-3","status":"ruled","ruled_by":"operator","blocks_waves":["tail"],"ts":"2026-10-01T00:00:00Z"}'
  run "$G" requires --program demo --wave tail # named only by a ruled decision
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "CLEAR demo wave tail"* ]] || { echo "$output"; false; }
}

@test "the measured fail-open: Day0 and D0 are refused while KR-06 keys D0 and a decision keys Day0" {
  certify; plant_measured_shape
  for w in Day0 D0; do
    run "$G" requires --program demo --wave "$w"
    [ "$status" -eq 1 ] || { echo "$w: $output"; false; }
    [[ "$output" == *"wave ids D0 and Day0 spell one wave two ways (D0: KR-06; Day0: DR-09)"* ]] || { echo "$output"; false; }
    [[ "$output" == *"gate.sh rekey-wave --program demo --row KR-06 --from D0 --to Day0"* ]] || { echo "$output"; false; }
  done
  run "$G" requires --program demo --wave rel
  [ "$status" -eq 1 ]
  [[ "$output" == *"wave ids rel and release spell one wave two ways (rel: DR-07; release: KR-13)"* ]] || { echo "$output"; false; }
  # a wave with no twin is unaffected by another wave's twin
  run "$G" requires --program demo --wave W0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "an id outside the program's set is refused before any side effect (rc 2), naming the near-miss" {
  certify
  dec '{"id":"DR-09","status":"ruled","ruled_by":"operator","blocks_waves":["Day0"],"ts":"2026-10-01T00:00:00Z"}'
  dec '{"id":"DR-07","status":"ruled","ruled_by":"operator","blocks_waves":["rel"],"ts":"2026-10-01T00:00:00Z"}'
  run "$G" requires --program demo --wave D0 --start
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown wave id 'D0' for demo; near-miss: Day0"* ]] || { echo "$output"; false; }
  [ ! -e "$REC/waves.jsonl" ] # --start recorded nothing
  run "$G" requires --program demo --wave release
  [ "$status" -eq 2 ]
  [[ "$output" == *"near-miss: rel"* ]] || { echo "$output"; false; }
  run "$G" requires --program demo --wave day0 # case is a spelling too
  [ "$status" -eq 2 ]
  [[ "$output" == *"near-miss: Day0"* ]] || { echo "$output"; false; }
  # a typo with no near-miss still refuses, and lists the set to choose from
  run "$G" requires --program demo --wave W11
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown wave id 'W11' for demo"*"its wave ids: "*"Day0"*"rel"* ]] || { echo "$output"; false; }
  run "$G" requires --program demo --wave D0 --json
  [ "$status" -eq 2 ]
}

@test "a blocking row that names an ill-formed wave id refuses every wave: it may block any of them" {
  certify
  dec '{"id":"DR-5","status":"open","blocks_waves":["W0 (gates 4, 5, 6, 8)"]}'
  run "$G" requires --program demo --wave W1
  [ "$status" -eq 1 ]
  [[ "$output" == *"DR-5 blocks_waves names 'W0 (gates 4, 5, 6, 8)', which is not a wave id"* ]] || { echo "$output"; false; }
  # once the row no longer blocks, its stray text blocks nothing
  dec '{"id":"DR-5","status":"ruled","ruled_by":"operator"}'
  run "$G" requires --program demo --wave W1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "handoff-fire --requires-gate refuses a twin-spelled wave and an unknown one before any side effect" {
  PAYLOAD="$BATS_TEST_TMPDIR/p.txt"
  echo "TASK — research build wave fixture payload." > "$PAYLOAD"
  certify; plant_measured_shape
  run bash "$HF" --prompt-file "$PAYLOAD" --dry-run --requires-gate demo --gate-wave Day0
  [ "$status" -eq 2 ]
  [[ "$output" == *"research gate REFUSES this build wave"* ]] || { echo "$output"; false; }
  [[ "$output" == *"spell one wave two ways"* ]] || { echo "$output"; false; }
  run bash "$HF" --prompt-file "$PAYLOAD" --dry-run --requires-gate demo --gate-wave Day1
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown wave id 'Day1' for demo"* ]] || { echo "$output"; false; }
}

# ── gate.sh waves (read) ─────────────────────────────────────────────────────────────────────────

@test "gate.sh waves lists the canonical set with where each id is named, and the twins" {
  plant_measured_shape
  run "$G" waves --program demo
  [ "$status" -eq 1 ] # twins: the set is not canonical yet
  [[ "$output" == *"D0: KR-06 blocks_waves"* ]] || { echo "$output"; false; }
  [[ "$output" == *"B1: frame.json build_waves"* ]] || { echo "$output"; false; }
  [[ "$output" == *"TWINS D0 / Day0"* ]] || { echo "$output"; false; }
  run "$G" waves --program demo --json
  printf '%s' "$output" | /usr/bin/python3 -c "
import json, sys; d = json.load(sys.stdin)
assert 'Day0' in d['ids'] and 'D0' in d['ids'], d
assert ['D0', 'Day0'] in d['twins'] and ['rel', 'release'] in d['twins'], d['twins']"
}

# ── gate.sh rekey-wave ───────────────────────────────────────────────────────────────────────────

@test "rekey-wave re-spells a known row by an appended event, the old row kept; the row then blocks the canonical wave" {
  certify; plant_measured_shape
  before="$(head -n 1 "$REC/known_rows.jsonl")"
  n="$(wc -l < "$REC/known_rows.jsonl")"
  run "$G" rekey-wave --program demo --row KR-06 --from D0 --to Day0 --reason "the fire recipe spells it Day0"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"REKEYED KR-06: D0 -> Day0 in blocks_waves"* ]] || { echo "$output"; false; }
  [ "$(wc -l < "$REC/known_rows.jsonl")" -eq $((n + 1)) ]
  [ "$(head -n 1 "$REC/known_rows.jsonl")" = "$before" ]
  [ "$(folded known_rows.jsonl KR-06 blocks_waves)" = '["Day0", "W1"]' ]
  [ "$(folded known_rows.jsonl KR-06 status)" = '"open"' ]
  tail -n 1 "$REC/known_rows.jsonl" | /usr/bin/python3 -c "
import json, sys; e = json.load(sys.stdin)
r = e['rekeyed']; assert (r['from'], r['to'], r['fields']) == ('D0', 'Day0', ['blocks_waves']), r
assert r['reason'] == 'the fire recipe spells it Day0' and r['by'] and r['at'], r
assert 'status' not in e, e"
  # the real block now lands on the canonical id, and the old spelling is gone from the set
  run "$G" requires --program demo --wave Day0
  [ "$status" -eq 1 ]
  [[ "$output" == *"KR-06: open frame-omission row"* ]] || { echo "$output"; false; }
  [[ "$output" != *"two ways (D0"* ]] || { echo "$output"; false; }
  run "$G" requires --program demo --wave D0
  [ "$status" -eq 2 ]
  [[ "$output" == *"near-miss: Day0"* ]] || { echo "$output"; false; }
  # the row's held time is its first event's, not the re-key's
  /usr/bin/python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/research-kit/lib'); import gate, gate_rows_a
ctx = gate.make_ctx('demo'); h = gate_rows_a.held_at(ctx)
assert h['KR-06'] == '2026-10-12T08:38:14Z', h"
}

@test "rekey-wave re-spells a decision, and an ill-formed id to the wave its text opens with" {
  certify
  dec '{"id":"DR-09","status":"carried","blocks_waves":["Day 0 (p1 filing)"],"set":{"members":[],"narrowing_probe":{"wave":"Day 0 (p1 filing)"}},"descoped_waves":[]}'
  dec '{"id":"DR-1","status":"ruled","ruled_by":"operator","blocks_waves":["Day0"]}'
  run "$G" rekey-wave --program demo --row DR-09 --from "Day 0 (p1 filing)" --to Day0 --reason "free text from intake"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(folded decisions.jsonl DR-09 blocks_waves)" = '["Day0"]' ]
  [ "$(folded decisions.jsonl DR-09 set)" = '{"members": [], "narrowing_probe": {"wave": "Day0"}}' ]
  [ "$(folded decisions.jsonl DR-09 status)" = '"carried"' ]
  # the carried set now exempts the wave owning its narrowing probe, as it was meant to
  run "$G" requires --program demo --wave Day0
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "rekey-wave refuses, appending nothing: another wave, an id not on the row, an unknown row, a bad id, a started wave, a fresh lease" {
  certify; plant_measured_shape
  n="$(wc -l < "$REC/known_rows.jsonl")"
  run "$G" rekey-wave --program demo --row KR-06 --from W1 --to W2 --reason x
  [ "$status" -eq 2 ]
  [[ "$output" == *"W2 is not a spelling of W1"* ]] || { echo "$output"; false; }
  run "$G" rekey-wave --program demo --row KR-06 --from W7 --to W7a --reason x
  [ "$status" -eq 2 ]
  [[ "$output" == *"KR-06 names no wave W7"* ]] || { echo "$output"; false; }
  run "$G" rekey-wave --program demo --row KR-99 --from D0 --to Day0 --reason x
  [ "$status" -eq 2 ]
  [[ "$output" == *"no known row or decision KR-99"* ]] || { echo "$output"; false; }
  run "$G" rekey-wave --program demo --row KR-06 --from D0 --to "Day 0" --reason x
  [ "$status" -eq 2 ]
  [[ "$output" == *"bad wave id"* ]] || { echo "$output"; false; }
  printf '%s\n' '{"wave":"D0","event":"started","at":"2026-10-14T00:00:00Z","cert":"CERT-v1"}' >> "$REC/waves.jsonl"
  run "$G" rekey-wave --program demo --row KR-06 --from D0 --to Day0 --reason x
  [ "$status" -eq 2 ]
  [[ "$output" == *"wave D0 started at 2026-10-14T00:00:00Z"* ]] || { echo "$output"; false; }
  : > "$REC/waves.jsonl"
  CC_RESEARCH_OWNER=other-lead "$REPO/bin/cc-research" lease acquire --program demo > /dev/null
  run env CC_RESEARCH_OWNER=me "$G" rekey-wave --program demo --row KR-06 --from D0 --to Day0 --reason x
  [ "$status" -eq 2 ]
  [[ "$output" == *"other-lead"* ]] || { echo "$output"; false; }
  [ "$(wc -l < "$REC/known_rows.jsonl")" -eq "$n" ]
}
