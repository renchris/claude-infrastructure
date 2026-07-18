#!/usr/bin/env bats
# P0-11 engagement verification + P0-12 registration guarantee for handoff-fire.sh (FM2 / INC-4).
#
# FM2 / INC-4 (memory cold-worktree-fire-autosubmit-race, 2026-07-17): a cold --worktree fire can
# race CC boot so the auto-submit keystroke is lost and the pane sits at an empty composer — 0
# commits, no ping — yet the fire printed "→ fired" exit 0. These tests prove the fix: a
# never-engaged fire now FAILS LOUD, and an engaged fire whose registry row never lands gets a
# provisional row.
#
# Isolation (fire-autonomy.bats pattern): HOME → a temp dir (config/projects/registry all under it;
# pre_trust no-ops with no .claude.json), IT2_BIN stubs the it2 transport, and the engagement /
# registration windows shrink to seconds via env. The pure detectors are extracted + sourced.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  eval "$(sed -n '/^engagement_seen() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^ensure_registration() {/,/^}/p' "$HF")"

  HOMEDIR="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOMEDIR/.claude/projects" "$HOMEDIR/.claude/cc-registry"
  PROJ="$HOMEDIR/.claude/projects"
  REG="$HOMEDIR/.claude/cc-registry"
  PANE="FAKEPANE-0000-0000-0000-000000000001"

  PF="$BATS_TEST_TMPDIR/brief.md"
  printf 'BRIEF BODY line one\nline two\n' > "$PF"

  # it2 stub: `session split` echoes a fake pane; run/focus/send are silent successes.
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/it2" <<STUB
#!/bin/bash
case "\$*" in
  *"session split"*) echo "Created new pane: $PANE" ;;
  *) : ;;
esac
STUB
  chmod +x "$BIN/it2"
  # IT2_SHIM ($HOME/.claude/bin/it2) must EXIST or the script's `sed | head` REAL_IT2 probe aborts
  # under pipefail (in prod the shim is always present; IT2_BIN then overrides it to our stub).
  mkdir -p "$HOMEDIR/.claude/bin"; cp "$BIN/it2" "$HOMEDIR/.claude/bin/it2"
}

# ---- P0-11 unit: engagement_seen (the pure detector) ----------------------------------------

@test "engagement_seen: marker in a transcript JSONL -> engaged (0)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"user","message":{"role":"user","content":"hi MARKER-XYZ ok"}}\n' > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 0 ]
}

@test "engagement_seen: marker absent + no registry row -> not engaged (1)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"user","message":{"role":"user","content":"unrelated"}}\n' > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "engagement_seen: cc-registry row bearing a session_id -> engaged (0), marker not needed" {
  printf '{"paneUUID":"%s","session_id":"sid-123"}\n' "$PANE" > "$REG/$PANE.json"
  run engagement_seen "$PROJ" "MARKER-ABSENT" "$REG" "$PANE"
  [ "$status" -eq 0 ]
}

@test "engagement_seen: registry row with NULL session_id -> not engaged (1)" {
  printf '{"paneUUID":"%s","session_id":null}\n' "$PANE" > "$REG/$PANE.json"
  run engagement_seen "$PROJ" "MARKER-ABSENT" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

# ---- P0-11 E2E: never-engaged FAILS LOUD (the RED->GREEN), engaged still succeeds ------------

@test "E2E: a never-engaged fire prints FIRE FAILED and exits non-zero (no false '→ fired')" {
  run env HOME="$HOMEDIR" IT2_BIN="$BIN/it2" TMPDIR="$BATS_TEST_TMPDIR" \
    FIRE_ENGAGE_TIMEOUT=1 FIRE_ENGAGE_RETRY=1 FIRE_ENGAGE_INTERVAL=1 FIRE_REG_TIMEOUT=0 \
    FIRE_ENGAGE_MARKER=NEVER-SEEN-MARKER \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --split-right \
      --session-id FIRING-0000 --cwd "$BATS_TEST_TMPDIR" --no-self-retire
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'FIRE FAILED — never engaged'
  ! printf '%s\n' "$output" | grep -q '→ fired'
}

@test "E2E: an engaged fire (marker in a transcript) prints '→ fired' exit 0" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"user","message":{"role":"user","content":"the brief SEEN-MARKER ok"}}\n' > "$PROJ/proj/s.jsonl"
  run env HOME="$HOMEDIR" IT2_BIN="$BIN/it2" TMPDIR="$BATS_TEST_TMPDIR" \
    FIRE_ENGAGE_TIMEOUT=5 FIRE_ENGAGE_RETRY=1 FIRE_ENGAGE_INTERVAL=1 FIRE_REG_TIMEOUT=0 \
    FIRE_ENGAGE_MARKER=SEEN-MARKER \
    bash "$HF" --prompt-file "$PF" --launcher claude-test --split-right \
      --session-id FIRING-0000 --cwd "$BATS_TEST_TMPDIR" --no-self-retire
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '→ fired'
}

# ---- P0-12 unit: ensure_registration --------------------------------------------------------

@test "ensure_registration: an existing P8 row is NOT clobbered" {
  printf '{"paneUUID":"%s","session_id":"real-sid","pid":4242}\n' "$PANE" > "$REG/$PANE.json"
  before="$(cat "$REG/$PANE.json")"
  export FIRE_REG_TIMEOUT=0
  run ensure_registration "$REG" "$PANE" "nm" "/cwd" "cmd"
  [ "$status" -eq 0 ]
  [ "$(cat "$REG/$PANE.json")" = "$before" ]
}

@test "ensure_registration: no row -> writes a PROVISIONAL row (provisional:true, no pid)" {
  export FIRE_REG_TIMEOUT=0
  run ensure_registration "$REG" "$PANE" "desk-fire" "/some/cwd" "launcher xyz"
  [ "$status" -eq 0 ]
  [ -f "$REG/$PANE.json" ]
  run jq -e '.provisional == true and .paneUUID=="'"$PANE"'" and .name=="desk-fire" and (has("pid")|not)' "$REG/$PANE.json"
  [ "$status" -eq 0 ]
}

@test "ensure_registration: empty pane arg is a clean no-op" {
  export FIRE_REG_TIMEOUT=0
  run ensure_registration "$REG" "" "nm" "/cwd" "cmd"
  [ "$status" -eq 0 ]
}
