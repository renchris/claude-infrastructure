#!/usr/bin/env bats
# T-P2-5 — handoff-fire.sh wires F3 payload-lint PRE-FIRE (the W5 root, live-unfixed until this caller:
# payload-lint.sh was DEAD in the loop, p02 G-P2-5). A fire whose MATERIALIZED payload INTENDS a
# back-channel (references cc-notify) but botches the block — or prescribes a SendMessage terminal-
# announce (F3/a) — is ABORTED LOUD (exit 4) BEFORE any spawn. A pure one-way fire (no cc-notify) is
# NOT gated (fire-and-forget is the documented default). Role-indirection (/goal fires) passes.
#
# Enforce is exercised on the REAL fire path with an explicit --launcher (bypasses account/probe) +
# explicit --cwd/--session-id; the abort happens before pre_trust/spawn, so no iTerm2/config side
# effects. GREEN/one-way decision logic is asserted via --dry-run (side-effect-free; the dry preview
# lints the pre-trailer payload).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  WT="$BATS_TEST_TMPDIR/wt"; mkdir -p "$WT"
  P="$BATS_TEST_TMPDIR/fire.txt"
  SID="fake:DEADBEEF-0000-0000-0000-000000000000"
}

# ---- enforce (real fire path; aborts before any side effect) ---------------------------------

@test "RED-with-intent (cc-notify, no uuid/role) → real fire ABORTS exit 4 before spawn" {
  printf 'Continue the build.\nOn completion, cc-notify the desk when finished.\n' > "$P"
  run timeout 25 bash "$HF" --prompt-file "$P" --cwd "$WT" --launcher claude-next --session-id "$SID"
  [ "$status" -eq 4 ]
  [[ "$output" == *"ABORTED (F3 / T-P2-5)"* ]]
  [[ "$output" == *"BACK-CHANNEL BLOCK missing"* ]]
  # aborted BEFORE the spawn — no "→ fired" success line
  [[ "$output" != *"→ fired"* ]]
}

@test "SendMessage terminal-announce (F3/a) → real fire ABORTS exit 4 even WITH a valid block" {
  { printf 'Continue. cc-notify D5D419C8-8B79-4C05-A38C-DF0A85A1AAE2 is the desk.\n'
    printf 'On ship, announce the ship-witness to the desk via SendMessage.\n'; } > "$P"
  run timeout 25 bash "$HF" --prompt-file "$P" --cwd "$WT" --launcher claude-next --session-id "$SID"
  [ "$status" -eq 4 ]
  [[ "$output" == *"F3/a"* ]]
}

@test "role-indirection (cc-notify + cc-roles/<role>, no uuid) → NOT blocked (dry reaches full output)" {
  printf 'Continue.\nOn completion cc-notify "$(cat ~/.claude/cc-roles/desk)".\n' > "$P"
  run timeout 25 bash "$HF" --prompt-file "$P" --cwd "$WT" --launcher claude-next --session-id "$SID" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"WOULD BLOCK"* ]]
  [[ "$output" == *"command:"* ]]     # reached the end of the dry readout — the gate let it through
}

# ---- one-way fires are NOT gated (fire-and-forget default) ------------------------------------

@test "one-way fire (no cc-notify) → advisory note, NOT blocked, dry exit 0" {
  printf 'Go build feature X. Fire and forget.\n' > "$P"
  run timeout 25 bash "$HF" --prompt-file "$P" --cwd "$WT" --launcher claude-next --session-id "$SID" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"payload-lint (advisory): one-way fire"* ]]
  [[ "$output" != *"WOULD BLOCK"* ]]
}

# ---- dry preview reports the block without failing (dry never fires) --------------------------

@test "dry-run preview REPORTS a would-be block (RED-with-intent) but exits 0 (nothing fires)" {
  printf 'Continue.\nOn completion, cc-notify the desk when finished.\n' > "$P"
  run timeout 25 bash "$HF" --prompt-file "$P" --cwd "$WT" --launcher claude-next --session-id "$SID" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD BLOCK"* ]]
}

# ---- the gate is best-effort when the lint tool is missing (never a hard-fail of the fire) ----

@test "missing payload-lint tool → fire is NOT gated (best-effort), no abort" {
  printf 'Continue.\nOn completion, cc-notify the desk when finished.\n' > "$P"
  run timeout 25 env CC_PAYLOAD_LINT_BIN="$BATS_TEST_TMPDIR/nonexistent-lint.sh" \
    bash "$HF" --prompt-file "$P" --cwd "$WT" --launcher claude-next --session-id "$SID" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"ABORTED (F3 / T-P2-5)"* ]]
}
