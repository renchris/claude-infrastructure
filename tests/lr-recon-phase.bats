#!/usr/bin/env bats
# lr_recon.phase over the W0 derive_phase fixtures (§4.2 of LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md).

setup() {
  cd "$BATS_TEST_DIRNAME/../scripts/limit-recover" || return 1
  FIX="$BATS_TEST_DIRNAME/fixtures/lr-recon"
}

@test "phase CLI: every fixture row derives its expected phase" {
  run python3 -m lr_recon.phase --fixtures "$FIX"
  [ "$status" -eq 0 ]
  [[ "$output" =~ phase\ fixtures:\ ([0-9]+)\ rows,\ ([0-9]+)\ pass,\ 0\ fail ]]
  [ "${BASH_REMATCH[1]}" -eq "${BASH_REMATCH[2]}" ]
  [ "${BASH_REMATCH[1]}" -gt 0 ]
  [ "$(grep -c '^FAIL ' <<<"$output")" -eq 0 ]
}

@test "phase CLI: every required row class is present and passing" {
  run python3 -m lr_recon.phase --fixtures "$FIX"
  [ "$status" -eq 0 ]
  local cls
  for cls in SPLIT-BRAIN EXITING HUSK-RETIRED/stub HUSK-RETIRED/no-stub EXITED PANE-GONE/R \
      PANE-GONE/NOT_NEEDED TARGET-LIMITED TARGET-AUTH TARGET-TRANSIENT ENGAGED MOVED \
      PRE-MOVE/HOLD-MENU RELAUNCHED/UNPROMPTED; do
    grep -Eq "^ok   [^ ]+ ${cls}( |\$)" <<<"$output" || { echo "missing class: $cls"; return 1; }
  done
}

@test "phase CLI: the 751 and 815 false-RECOVERED rows pass and are never ENGAGED" {
  run python3 -m lr_recon.phase --fixtures "$FIX"
  local rows
  rows="$(grep -E '^[a-zA-Z]+ +0927-(751|815)-' <<<"$output")"
  [ "$(wc -l <<<"$rows")" -ge 4 ]
  [ "$(grep -cv '^ok   ' <<<"$rows")" -eq 0 ]
  [ "$(grep -c 'ENGAGED' <<<"$rows")" -eq 0 ]
}

@test "phase CLI: a flipped expected_phase is caught (negative control)" {
  python3 - "$FIX/phase-20260929-cohort-0417.json" "$BATS_TEST_TMPDIR/phase-flipped.json" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
for r in d["rows"]:
    if r["id"] == "849-b":
        r["expected_phase"] = "RELAUNCHED"
json.dump(d, open(sys.argv[2], "w"))
EOF
  run python3 -m lr_recon.phase --fixtures "$BATS_TEST_TMPDIR"
  [ "$status" -eq 1 ]
  grep -q '^FAIL 849-b expected=RELAUNCHED got=ENGAGED' <<<"$output"
}

@test "phase CLI: an empty fixture dir exits 2" {
  mkdir -p "$BATS_TEST_TMPDIR/empty"
  run python3 -m lr_recon.phase --fixtures "$BATS_TEST_TMPDIR/empty"
  [ "$status" -eq 2 ]
}
