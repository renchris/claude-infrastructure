#!/usr/bin/env bats
# P0-14 desk-invariant — the desk-existence + engagement invariant. The tool's --selftest RED-proves
# every branch against stubbed dirs; these bats add (a) the selftest exit-code + check-count contract
# and (b) independent CLI-level end-to-end runs of `--once` through the real override surface (proving
# evaluate() works outside the in-script selftest, not just the selftest helper).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DI="$REPO/scripts/desk-invariant.sh"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/roles" "$C/registry" "$C/projects/p" "$C/wait" "$C/state" "$C/stubs"
  for s in it2 notify push fire; do
    { printf '#!/bin/bash\n'; printf 'printf "%%s\\n" "$*" >> "%s/stubs/%s.log"\nexit 0\n' "$C" "$s"; } > "$C/stubs/$s"
    chmod +x "$C/stubs/$s"
  done
  export DESK_INVARIANT_ROLE=desk DESK_INVARIANT_ROLES_DIR="$C/roles" \
    DESK_INVARIANT_REGISTRY_DIR="$C/registry" DESK_INVARIANT_PROJECT_ROOTS="$C/projects" \
    DESK_INVARIANT_WAIT_DIR="$C/wait" DESK_INVARIANT_STATE_DIR="$C/state" DESK_INVARIANT_IDL="$C/idl.jsonl" \
    DESK_INVARIANT_IT2="$C/stubs/it2" DESK_INVARIANT_NOTIFY="$C/stubs/notify" DESK_INVARIANT_PUSH="$C/stubs/push" \
    DESK_INVARIANT_FIRE_BIN="$C/stubs/fire" DESK_INVARIANT_CANNED_CWD="$C" DESK_INVARIANT_BRIEF="$C/brief.md" \
    DESK_INVARIANT_STALE_MIN=45
  : > "$C/brief.md"
}
row() { # <uuid> <sid> <pid> — write a registry row
  jq -cn --arg u "$1" --arg s "$2" --argjson p "$3" --arg c "$C" \
    '{paneUUID:$u,cwd:$c,pid:$p,startedAt:0,session_id:$s}' > "$C/registry/$1.json"
}
transcript() { # <sid> <iso-ts> [cap-text]
  printf '{"type":"assistant","isSidechain":false,"timestamp":"%s","message":{"content":[{"type":"text","text":"ok"}]}}\n' "$2" > "$C/projects/p/$1.jsonl"
  [ -n "${3:-}" ] && printf '{"type":"user","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$3" >> "$C/projects/p/$1.jsonl"
  return 0
}
disp() { tail -1 "$C/idl.jsonl" | jq -r '.disposition'; }

@test "selftest passes and runs all 18 checks (a zero-check suite must not 'pass')" {
  run "$DI" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 18 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "unknown arg → exit 2 (fail-loud, no silent no-op)" {
  run "$DI" --bogus
  [ "$status" -eq 2 ]
}

@test "healthy: alive pid + fresh assistant turn → exit 0, disposition=healthy, no re-prompt/fire" {
  printf 'U1\n' > "$C/roles/desk"
  sleep 60 & local sp=$!
  row U1 S1 "$sp"
  transcript S1 "$(date -u -v-1M +%Y-%m-%dT%H:%M:%SZ)"
  run "$DI" --once
  kill "$sp" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(disp)" = healthy ]
  [ ! -f "$C/stubs/it2.log" ]
  [ ! -f "$C/stubs/fire.log" ]
}

@test "stunned: alive pid + stale turn + 'monthly spend limit' text → page + re-prompt" {
  printf 'U2\n' > "$C/roles/desk"
  sleep 60 & local sp=$!
  row U2 S2 "$sp"
  transcript S2 "$(date -u -v-90M +%Y-%m-%dT%H:%M:%SZ)" "you have reached the monthly spend limit"
  run "$DI" --once
  kill "$sp" 2>/dev/null || true
  [ "$(disp)" = stunned ]
  [ -f "$C/stubs/it2.log" ]
  [ -f "$C/stubs/push.log" ]
}

@test "no-desk: role points at a UUID with no registry row → budgeted replacement fire + marker" {
  printf 'UGONE\n' > "$C/roles/desk"
  run "$DI" --once
  [ "$(disp)" = no-desk ]
  [ -f "$C/stubs/fire.log" ]
  ls "$C/state"/respawn-*.marker >/dev/null 2>&1
}

@test "budget-exhausted: no-desk + 2 fresh respawn markers → page only, NO fire (loop refused)" {
  printf 'UGONE2\n' > "$C/roles/desk"
  : > "$C/state/respawn-$(date +%s).marker"
  : > "$C/state/respawn-$(( $(date +%s) - 3 )).marker"
  run "$DI" --once
  [ "$(disp)" = budget-exhausted ]
  [ ! -f "$C/stubs/fire.log" ]
}
