#!/usr/bin/env bats
# model/effort auto-routing — cc-route: the tool's selftest RED-proves RT-a..RT-f with a stubbed
# accounts bin + temp SSOT; these bats add CLI-level regression on the exit-code contract
# (0 plan · 2 usage · 3 fire-blind refusal · 4 quota cliff) and plan-shape pins.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  T="$REPO/bin/cc-route"
  export CC_ROUTE_RECORDS_DIR="$BATS_TEST_TMPDIR/records"
  export CC_MODEL_CONFIG="$BATS_TEST_TMPDIR/model-config.yaml"
  cat > "$CC_MODEL_CONFIG" <<'YAML'
frontier_access:
  model: claude-fable-5
  active: true
roles:
  lead_default: claude-opus-4-8
YAML
  cat > "$BATS_TEST_TMPDIR/accounts-stub" <<'STUB'
#!/bin/bash
if [ "${1:-}" = "--route" ]; then
  case "$2" in
    fable)   rc="${STUB_FABLE_RC:-0}";   name="next4" ;;
    general) rc="${STUB_GENERAL_RC:-0}"; name="next3" ;;
  esac
  if [ "$rc" = 0 ]; then echo "$name"; exit 0; fi
  echo "stub says none" >&2; exit "$rc"
fi
exit 2
STUB
  chmod +x "$BATS_TEST_TMPDIR/accounts-stub"
  export CC_ROUTE_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/accounts-stub"
}

@test "selftest passes and runs all 15 checks (a zero-check suite must not 'pass')" {
  run "$T" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 15 ]
}

@test "lead → one-line JSON plan {slot,model,account,lead_effort,reason} on stdout" {
  run bash -c "'$T' lead 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'select(.slot=="lead" and .model=="claude-opus-4-8" and .account=="next3" and .lead_effort=="max" and (.reason|length)>0)'
  [ "$(echo "$output" | wc -l)" -eq 1 ]
}

@test "judgment-dense with window open → fable plan; with fable-route none → reason-carrying fallback" {
  run bash -c "'$T' judgment-dense 2>/dev/null | jq -r .model"
  [ "$output" = "claude-fable-5" ]
  run bash -c "STUB_FABLE_RC=2 '$T' judgment-dense 2>/dev/null | jq -r '.model + \" \" + .reason'"
  [[ "$output" == "claude-opus-4-8 "*fallback* ]]
}

@test "quota cliff → exit 4 and stdout is EMPTY (no plan a caller could mistakenly consume)" {
  run bash -c "STUB_GENERAL_RC=2 '$T' lead 2>/dev/null"
  [ "$status" -eq 4 ]
  [ -z "$output" ]
}

@test "data-unavailable → exit 3 and stdout is EMPTY (never fire blind)" {
  run bash -c "STUB_GENERAL_RC=3 '$T' lead 2>/dev/null"
  [ "$status" -eq 3 ]
  [ -z "$output" ]
}

@test "unknown slot → exit 2 (fail-closed parser)" {
  run "$T" omniscient-oracle
  [ "$status" -eq 2 ]
}

@test "structural: no hardcoded window date anywhere in the tool's CODE (SSOT discipline)" {
  # The two real incidents were COPIES of the window (JUL7 constant; comment-matching grep). The tool
  # must carry no date literal that could shadow the SSOT — in CODE; comments are stripped first
  # (the reaper-horizon comment-as-code lesson, applied in reverse).
  ! sed 's/[[:space:]]*#.*$//' "$T" | grep -nE '2026-[0-9]{2}-[0-9]{2}|JUL[0-9]'
}
