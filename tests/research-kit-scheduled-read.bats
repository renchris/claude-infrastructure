#!/usr/bin/env bats
# research-kit-scheduled-read — gate row 15 as a scheduled read (method v1.3, "exhaust, then
# proceed"; docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md §13.1).
#
# When a stratum of the router's instrument awaits a fresh set, the read is not in grasp. A filed
# scheduled read lets row 15 print FILED (nothing decrypted, no read logged) and the certificate
# issue; `gate.sh read` spends the read later under every guard the gate run had; `gate.sh requires`
# holds only the filing's waves until a PASS. Each case starts from the known-good program
# (tests/fixtures/research-kit/build_good.py) with regex-missed and pushback planted as awaiting.
#
# RED-proof (2026-10-16): on the kit before v1.3 `cc-research read` and `gate.sh read` are invalid
# choices (exit 2), and row 15 fails "awaits a fresh set" with or without a filing, so no
# certificate can issue while a set accrues.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "$CC_NOW" > "$BATS_FILE_TMPDIR/now"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  export CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  mkdir -p "$W"
  "$BATS_TEST_DIRNAME/fixtures/research-kit/build_good.py" "$W" > "$BATS_FILE_TMPDIR/records-path"
  cp -Rp "$W" "$BATS_FILE_TMPDIR/golden"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"
  mkdir -p "$HOME"
  unset CC_BATS_ACTIVE CC_RESEARCH_RECORDS CC_RESEARCH_ACTIVITY
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  G="$REPO/scripts/research-kit/gate.sh"
  CR="$REPO/bin/cc-research"
  export W="$BATS_FILE_TMPDIR/w"
  export CC_RESEARCH_HOME="$W/home" CC_RESEARCH_REGISTRY="$W/home/programs.json"
  CC_NOW="$(cat "$BATS_FILE_TMPDIR/now")"
  export CC_NOW CC_RESEARCH_VAULT_KEY="test-key"
  export CC_DECISIONS_DIR="$W/decisions" CC_IDL="$W/idl.jsonl"
  export CC_RESEARCH_ROUTER="$W/router.sh"
  export CC_RESEARCH_CALIBRATION="$W/calibration.jsonl"
  rsync -a --delete "$BATS_FILE_TMPDIR/golden/" "$W/"
  REC="$(cat "$BATS_FILE_TMPDIR/records-path")"
  INST="$CC_RESEARCH_HOME/router-heldout/instrument.json"
}

reads() { cat "$CC_RESEARCH_HOME/router-heldout/reads.jsonl" 2>/dev/null | wc -l | tr -d ' '; }
# pin <regex-missed set|null> <pushback set|null>: the instrument, other strata from v1.
pin() {
  printf '{"strata": {"regex-matched": "v1", "regex-missed": %s, "pushback": %s, "other": "v1"}}\n' "$1" "$2" > "$INST"
}
rowjson() { "$G" run --program demo --json ${2:+"$2"} 2>/dev/null | /usr/bin/python3 -c "import json,sys; r=[r for r in json.load(sys.stdin) if r['num'] == $1][0]; print(r['status']); print('\n'.join(r['evidence']))"; }
# sfile <args>: the filing verb with every required flag.
sfile() {
  "$CR" read file --program demo --row 15 --awaits "v5: 40 labeled subtle re-asks" --owner lead \
    --due "cert+30d" --falsifier "test -s $REC/scheduled-reads.jsonl" --blocks-wave B2 \
    --why "v5 accrues from Nov 4 (ruling 915d7fb98b7f)" "$@"
}

@test "without a filing, a stratum awaiting a fresh set fails row 15 and reads nothing (the base rule stands)" {
  pin null null
  out="$(rowjson 15 --consent-sealed-read)"
  [ "$(printf '%s\n' "$out" | head -1)" = FAIL ]
  [[ "$out" == *"awaits a fresh set"* ]] || { echo "$out"; false; }
  [ "$(reads)" = 0 ]
  [ ! -f "$REC/cert/CERT-v1.json" ]
}

@test "read file: refused while every stratum is pinned (the read is in grasp), on prose or past dues, and twice without --refile; writes nothing when refused" {
  run sfile
  [ "$status" -eq 2 ]
  [[ "$output" == *"the read is in grasp"* ]] || { echo "$output"; false; }
  [ ! -e "$REC/scheduled-reads.jsonl" ]
  pin null null
  run sfile --falsifier "check: when v5 is sealed"
  [ "$status" -eq 2 ]
  [[ "$output" == *"not prose"* ]] || { echo "$output"; false; }
  run sfile --due 2020-01-01
  [ "$status" -eq 2 ]
  [[ "$output" == *"already past"* ]] || { echo "$output"; false; }
  run sfile --due "B9+5d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"a wave this filing does not block"* ]] || { echo "$output"; false; }
  [ ! -e "$REC/scheduled-reads.jsonl" ]
  run sfile
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "SR-15-1: filed row 15 as a scheduled read; scheduled read SR-15-1: awaits v5: 40 labeled subtle re-asks (strata regex-missed, pushback), owner lead, due cert+30d (pending: no certificate issued)"* ]] || { echo "$output"; false; }
  run sfile
  [ "$status" -eq 2 ]
  [[ "$output" == *"SR-15-1 is already filed and unread; --refile supersedes it"* ]] || { echo "$output"; false; }
  run sfile --refile --due "cert+40d"
  [ "$status" -eq 0 ]
  [ "$(grep -c '"supersedes": "SR-15-1"' "$REC/scheduled-reads.jsonl")" -eq 1 ]
}

@test "with a filing, row 15 is FILED and decrypts nothing; the gate certifies with row 15 carried" {
  pin null null
  # filed an hour after the fixture's freeze, so the certificate counts it as a late wait
  CC_NOW="$(/usr/bin/python3 -c "import calendar, time; t = calendar.timegm(time.strptime('$CC_NOW', '%Y-%m-%dT%H:%M:%SZ')); print(time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(t + 3600)))")" sfile > /dev/null
  git -C "$REC" add -A && git -C "$REC" commit -qm "file the scheduled read"
  run "$G" run --program demo # no read consent: none is needed, nothing is read
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"15. Router                   FILED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"FILED scheduled read SR-15-1: awaits v5"* ]] || { echo "$output"; false; }
  [[ "$output" == *"nothing decrypted, no read logged"* ]] || { echo "$output"; false; }
  [[ "$output" == *"CERTIFIED demo"* ]] || { echo "$output"; false; }
  [ "$(jq -r '.rows["15"]' "$REC/cert/CERT-v1.json")" = FILED ]
  [ "$(reads)" = 0 ]
  run "$G" --render --program demo
  [[ "$output" == *"Router read SR-15-1: scheduled, awaits v5: 40 labeled subtle re-asks; due cert+30d (cert issued "* ]] || { echo "$output"; false; }
  # filed after the freeze: a wait the intake did not front-load, counted on the certificate (§13.6)
  [[ "$output" == *"1 filed after the freeze (a wait the intake did not front-load, §13.6)"* ]] || { echo "$output"; false; }
  # the operator signs the certificate that carries row 15 FILED; then the filing's wave waits for
  # the read, and a wave that does not rest on the router fires
  "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/cert --evidence fixture > /dev/null
  run "$G" requires --program demo --wave B2
  [ "$status" -eq 1 ]
  [[ "$output" == *"row 15: scheduled read SR-15-1 has not run"* ]] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "a filing that does not cover every awaiting stratum, or is past due, fails row 15" {
  pin null '"v1"'
  sfile > /dev/null
  pin null null
  out="$(rowjson 15)"
  [ "$(printf '%s\n' "$out" | head -1)" = FAIL ]
  [[ "$out" == *"SR-15-1 does not cover stratum pushback"* ]] || { echo "$out"; false; }
  /usr/bin/python3 -c "
import json; p='$REC/scheduled-reads.jsonl'
rows=[json.loads(l) for l in open(p)]; rows[0]['strata']=['regex-missed','pushback']; rows[0]['due']='2020-01-01'
open(p,'w').write(''.join(json.dumps(r)+'\n' for r in rows))"
  out="$(rowjson 15)"
  [[ "$out" == *"SR-15-1: its due 2020-01-01 has passed with no read recorded"* ]] || { echo "$out"; false; }
}

@test "gate.sh read: practice writes nothing; the read refuses before the certificate, spends once after it, and clears the waves on PASS" {
  pin null null
  sfile > /dev/null
  run "$G" read --program demo --row 15 --practice
  [ "$status" -eq 1 ]
  [[ "$output" == *"NOT  stratum regex-missed, pushback awaits a fresh set"* ]] || { echo "$output"; false; }
  [[ "$output" == *"PRACTICE NOT READY"* ]] || { echo "$output"; false; }
  run "$G" read --program demo --row 15 --consent-sealed-read
  [ "$status" -eq 2 ]
  [[ "$output" == *"a scheduled read runs after the certificate issues"* ]] || { echo "$output"; false; }
  git -C "$REC" add -A && git -C "$REC" commit -qm "file the scheduled read"
  "$G" run --program demo > /dev/null
  "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/cert --evidence fixture > /dev/null
  run "$G" read --program demo --row 15
  [ "$status" -eq 2 ]
  [[ "$output" == *"no read consent"* ]] || { echo "$output"; false; }
  [ "$(reads)" = 0 ]
  # the set accrued and is pinned: the practice run is ready and still reads nothing
  pin '"v1"' '"v1"'
  run "$G" read --program demo --row 15 --practice
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PRACTICE READY: demo row 15; nothing decrypted, no read logged, nothing written"* ]] || { echo "$output"; false; }
  [ "$(reads)" = 0 ]
  run "$G" read --program demo --row 15 --consent-sealed-read
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "SR-15-1: row 15 scheduled read PASS"* ]] || { echo "$output"; false; }
  [ "$(reads)" = 4 ]
  run "$G" requires --program demo --wave B2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  run "$G" read --program demo --row 15 --consent-sealed-read
  [ "$status" -eq 2 ]
  [[ "$output" == *"SR-15-1 was already read (PASS"* ]] || { echo "$output"; false; }
  [ "$(reads)" = 4 ]
}

@test "gate.sh read: a FAIL is recorded, final, keeps the waves refused, and fails row 15 on a later run" {
  pin null null
  sfile > /dev/null
  git -C "$REC" add -A && git -C "$REC" commit -qm "file the scheduled read"
  "$G" run --program demo > /dev/null
  "$REPO/tests/fixtures/research-kit/fixture_signer.py" research:demo/cert --evidence fixture > /dev/null
  pin '"v1"' '"v1"'
  printf '#!/bin/bash\ncat >/dev/null\necho work-order\n' > "$W/router.sh"
  run "$G" read --program demo --row 15 --consent-sealed-read
  [ "$status" -eq 1 ]
  [[ "$output" == "SR-15-1: row 15 scheduled read FAIL"* ]] || { echo "$output"; false; }
  run "$G" requires --program demo --wave B2
  [ "$status" -eq 1 ]
  [[ "$output" == *"row 15: scheduled read SR-15-1 FAILED at"* ]] || { echo "$output"; false; }
  out="$(rowjson 15)"
  [ "$(printf '%s\n' "$out" | head -1)" = FAIL ]
  [[ "$out" == *"the scheduled read FAILED at"* ]] || { echo "$out"; false; }
  # The two views agree (REPORT.md §13.1): the ISSUED certificate keeps row 15 FILED and a FAIL holds
  # only the filing's waves (above), while a RE-ISSUE may not carry a pending read that already
  # failed, so it prints FAIL until the strata await a fresh set and a new read is filed.
  run "$G" requires --program demo --wave B1
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  pin null null
  run sfile
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "SR-15-2: filed row 15 as a scheduled read"* ]] || { echo "$output"; false; }
  out="$(rowjson 15)"
  [ "$(printf '%s\n' "$out" | head -1)" = FILED ] || { echo "$out"; false; }
  [[ "$out" == *"FILED scheduled read SR-15-2"* ]] || { echo "$out"; false; }
}
