#!/usr/bin/env bats
# research-kit-sweep — `gate.sh sweep` and `gate.sh file-packet` (REPORT.md §3.5, §5.4, §5.6; §10 items 4
# and 9). Fired class-B defaults reach the decision records; only an operator-SIGNED veto stops one;
# a class-C row past its due date converts to class B on its reversible option and descopes its waves;
# a frame-omission known row past its re-sign date closes by its default. Real bin/cc-decide, in a
# scratch decisions dir.

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
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  D="$REPO/bin/cc-decide"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions" CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  printf '{"id":"DR-1","status":"carried","blocks_waves":["B1"]}\n' >> "$REC/decisions.jsonl"
}

pkt() { /usr/bin/python3 -c "import json; print(json.load(open('$CC_DECISIONS_DIR/$1.json'))$2)"; }
dec() { /usr/bin/python3 -c "
import json; d={}
for l in open('$REC/decisions.jsonl'):
    r=json.loads(l)
    if r['id']=='DR-1': d.update(r)
print($1)"; }
file_b() {
  "$G" file-packet --program demo --decision DR-1 --class B --what "retry policy" --option "retry::writes retried" \
    --option "do-nothing::no change" --default retry --deadline "${1:-2026-10-01T00:00:00Z}" --conviction 80 --receipt "$REC/frame.json" \
    | awk '{print $2}'
}
file_c() {
  "$G" file-packet --program demo --decision DR-1 --class C --what "storage backend" --option "a::x" --option "b::y" \
    --conviction 70 --receipt "$REC/frame.json" --due "${1:-2026-09-30T00:00:00Z}" | awk '{print $2}'
}
sig() { # <action> <target|null>
  mkdir -p "$CC_RESEARCH_HOME/demo"
  printf '{"action":"%s","target":%s,"at":9e9,"at_iso":"2099-01-01T00:00:00Z","pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["zsh","kitty"]}}\n' \
    "$1" "$2" >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
}

@test "file-packet files class B with the program's --project and --default-effect no-change" {
  id="$(file_b)"
  [ "$(pkt "$id" '["subject_project"]')" = "$W/repo" ] || [ "$(pkt "$id" '["subject_project"]')" = "$(cd "$W/repo" && pwd -P)" ]
  [ "$(pkt "$id" '["default_effect"]')" = "no-change" ]
  [ "$(dec 'd["packet"]["id"]')" = "$id" ]
}

@test "file-packet refuses a class-C packet with no due date" {
  run "$G" file-packet --program demo --decision DR-1 --class C --what x --option "a::x" --option "b::y" --conviction 70 --receipt "$REC/frame.json"
  [ "$status" -eq 2 ]
  [[ "$output" == *"--due"* ]]
}

@test "an expired class-B default is applied to the decision record" {
  id="$(file_b)"
  /bin/bash "$D" expire-sweep >/dev/null
  [ "$(pkt "$id" '["status"]')" = "expired-actioned" ]
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  [ "$(dec 'd["status"], d["ruled_by"], d["chosen"], d["decided_by_default_at"]')" = "ruled packet-default retry 90" ]
}

@test "a class-B default not yet expired is left alone" {
  file_b "$(date -u -v+96H +%Y-%m-%dT%H:%M:%SZ)" >/dev/null
  /bin/bash "$D" expire-sweep >/dev/null
  "$G" sweep --program demo
  [ "$(dec 'd["status"]')" = "carried" ]
}

@test "an operator-signed veto stops the default" {
  file_b >/dev/null
  /bin/bash "$D" expire-sweep >/dev/null
  sig veto '"DR-1"'
  run "$G" sweep --program demo
  [[ "$output" == *"vetoed-by-operator DR-1"* ]] || false
  [ "$(dec 'd["status"]')" = "carried" ]
}

@test "an agent-written veto signature does not stop the default" {
  file_b >/dev/null
  /bin/bash "$D" expire-sweep >/dev/null
  printf '{"action":"veto","target":"DR-1","at":9e9,"pins":{},"because":"x","provenance":{"claude_ancestor":false,"chain":["zsh","claude"]}}\n' \
    >> "$CC_RESEARCH_HOME/demo/signoff.jsonl"
  "$G" sweep --program demo
  [ "$(dec 'd["ruled_by"]')" = "packet-default" ]
}

@test "a cc-decide veto with no operator signature fails the sweep as UNSIGNED" {
  id="$(file_b "$(date -u -v+96H +%Y-%m-%dT%H:%M:%SZ)")"
  /bin/bash "$D" veto "$id" >/dev/null
  run "$G" sweep --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNSIGNED VETO"* ]]
}

@test "a class-C row past its due date converts to class B on its reversible option and descopes its waves" {
  old="$(file_c)"
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  new="$(dec 'd["packet"]["id"]')"
  [ "$new" != "$old" ]
  [ "$(pkt "$old" '["status"]')" = "actioned" ]
  [ "$(pkt "$new" '["class"]')" = "B" ]
  [ "$(pkt "$new" '["default_if_no_veto"]')" = "do-nothing" ]
  [ "$(pkt "$new" '["default_effect"]')" = "no-change" ]
  [ "$(dec 'd["descoped_waves"]')" = "['B1']" ]
}

@test "a class-C row not yet due is left waiting" {
  old="$(file_c "$(date -u -v+1500H +%Y-%m-%dT%H:%M:%SZ)")"
  "$G" sweep --program demo
  [ "$(dec 'd["packet"]["id"]')" = "$old" ]
  [ "$(pkt "$old" '["status"]')" = "open" ]
}

@test "a class-C row past due with no reversible option cannot convert and fails the sweep" {
  printf '{"id":"DR-1","options":[{"label":"a"},{"label":"b"}]}\n' >> "$REC/decisions.jsonl"
  file_c >/dev/null
  run "$G" sweep --program demo
  [ "$status" -eq 1 ]
  [[ "$output" == *"CANNOT CONVERT DR-1"* ]]
}

@test "§10 item 9: a frame-omission known row past its re-sign date closes by descoping its waves" {
  printf '{"id":"KR-1","kind":"frame-omission","status":"open","resign_due":"2026-09-30T06:00:00Z","default":"descope","blocks_waves":["B2"]}\n' \
    >> "$REC/known_rows.jsonl"
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  tail -n 1 "$REC/known_rows.jsonl" | grep -q '"status": "closed"'
  tail -n 1 "$REC/known_rows.jsonl" | grep -q '"B2"'
}

@test "§10 item 9: a known row whose frame was re-signed after its due date stays open" {
  printf '{"id":"KR-1","kind":"frame-omission","status":"open","resign_due":"2026-09-29T00:00:00Z","default":"descope","blocks_waves":["B2"]}\n' \
    >> "$REC/known_rows.jsonl"
  "$G" sweep --program demo
  [ "$(grep -c '"closed"' "$REC/known_rows.jsonl")" -eq 0 ]
}

@test "§10 item 9: a class-b known-row default files a no-change class-B packet and closes the row" {
  printf '{"id":"KR-2","kind":"frame-omission","status":"open","resign_due":"2026-09-30T06:00:00Z","default":"class-b","names_rows":["AM-9"]}\n' \
    >> "$REC/known_rows.jsonl"
  run "$G" sweep --program demo
  [ "$status" -eq 0 ]
  id="$(tail -n 1 "$REC/known_rows.jsonl" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["packets"][0])')"
  [ "$(pkt "$id" '["default_effect"]')" = "no-change" ]
}
