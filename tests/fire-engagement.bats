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
  eval "$(sed -n '/^assistant_turn_in() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^engagement_seen() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^check_slash_head() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^ensure_registration() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^mark_fired_peer() {/,/^}/p' "$HF")"

  HOMEDIR="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOMEDIR/.claude/projects" "$HOMEDIR/.claude/cc-registry"
  PROJ="$HOMEDIR/.claude/projects"
  REG="$HOMEDIR/.claude/cc-registry"
  PANE="FAKEPANE-0000-0000-0000-000000000001"

  PF="$BATS_TEST_TMPDIR/brief.md"
  printf 'BRIEF BODY line one\nline two\n' > "$PF"

  # it2 stub: `session split` echoes a fake pane; `session send`/`run` record the payload and
  # `session read` echoes it back (terminal-echo sim) so it2_type_verified's echo-verify passes;
  # focus + everything else are silent successes.
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/it2" <<STUB
#!/bin/bash
LAST="$BATS_TEST_TMPDIR/it2-last-send"
case "\$1 \$2" in
  "session send"|"session run") printf '%s' "\${!#}" > "\$LAST" ;;
esac
case "\$*" in
  *"session split"*) echo "Created new pane: $PANE" ;;
  *"session read"*)  cat "\$LAST" 2>/dev/null ;;
  *) : ;;
esac
STUB
  chmod +x "$BIN/it2"
  # IT2_SHIM ($HOME/.claude/bin/it2) must EXIST or the script's `sed | head` REAL_IT2 probe aborts
  # under pipefail (in prod the shim is always present; IT2_BIN then overrides it to our stub).
  mkdir -p "$HOMEDIR/.claude/bin"; cp "$BIN/it2" "$HOMEDIR/.claude/bin/it2"
}

# ---- P0-11 unit: engagement_seen (the pure detector) ----------------------------------------

@test "engagement_seen: marker in a transcript WITH an assistant turn -> engaged (0)" {
  mkdir -p "$PROJ/proj"
  { printf '{"type":"user","message":{"role":"user","content":"hi MARKER-XYZ ok"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"on it"}]}}\n'
  } > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 0 ]
}

# THE ff2d6609a33e RED: transcript BIRTH is not engagement. This is the exact live shape — the fired
# brief landed in the transcript (attachment/system rows + the harness's own /goal rejection line),
# the marker is present, and the model NEVER took a turn. The old birth-check called this engaged.
@test "engagement_seen: marker present but ONLY attachment/system rows (rejected /goal) -> NOT engaged (1)" {
  mkdir -p "$PROJ/proj"
  { printf '{"type":"attachment","content":"the brief MARKER-XYZ ok"}\n'
    printf '{"type":"system","content":"Goal condition is limited to 4000 characters"}\n'
  } > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "engagement_seen: an assistant row with EMPTY content is not a turn -> not engaged (1)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"assistant","message":{"role":"assistant","content":""},"x":"MARKER-XYZ"}\n' > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "engagement_seen: marker absent + no registry row -> not engaged (1)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"user","message":{"role":"user","content":"unrelated"}}\n' > "$PROJ/proj/s.jsonl"
  run engagement_seen "$PROJ" "MARKER-XYZ" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "engagement_seen: registry session_id whose transcript HAS an assistant turn -> engaged (0)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi"}]}}\n' \
    > "$PROJ/proj/sid-123.jsonl"
  printf '{"paneUUID":"%s","session_id":"sid-123"}\n' "$PANE" > "$REG/$PANE.json"
  run engagement_seen "$PROJ" "MARKER-ABSENT" "$REG" "$PANE"
  [ "$status" -eq 0 ]
}

# The registry row is written by the SessionStart hook — pure birth. On its own it must not engage.
@test "engagement_seen: registry session_id with NO assistant turn in its transcript -> not engaged (1)" {
  mkdir -p "$PROJ/proj"
  printf '{"type":"system","content":"boot"}\n' > "$PROJ/proj/sid-123.jsonl"
  printf '{"paneUUID":"%s","session_id":"sid-123"}\n' "$PANE" > "$REG/$PANE.json"
  run engagement_seen "$PROJ" "MARKER-ABSENT" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

@test "engagement_seen: registry row with NULL session_id -> not engaged (1)" {
  printf '{"paneUUID":"%s","session_id":null}\n' "$PANE" > "$REG/$PANE.json"
  run engagement_seen "$PROJ" "MARKER-ABSENT" "$REG" "$PANE"
  [ "$status" -eq 1 ]
}

# ---- ff2d6609a33e: the slash-command HEAD guard ----------------------------------------------

@test "check_slash_head: a plain-text first line passes silently" {
  printf 'TASK — do the thing.\nmore body\n' > "$BATS_TEST_TMPDIR/p1.txt"
  run check_slash_head "$BATS_TEST_TMPDIR/p1.txt"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check_slash_head: a /goal head over the cap is REFUSED (the silent-dead-fire shape)" {
  { printf '/goal do the thing.\n'; head -c 5000 /dev/zero | tr '\0' 'x'; printf '\n'; } \
    > "$BATS_TEST_TMPDIR/p2.txt"
  run check_slash_head "$BATS_TEST_TMPDIR/p2.txt"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -q 'parses the ENTIRE submission'
}

@test "check_slash_head: a SHORT /goal head only warns (exit 0) — leading blank lines ignored" {
  printf '\n\n/goal read the plan and satisfy the DoD\n' > "$BATS_TEST_TMPDIR/p3.txt"
  run check_slash_head "$BATS_TEST_TMPDIR/p3.txt"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q "starts with the slash command '/goal'"
}

@test "check_slash_head: FIRE_ALLOW_SLASH_HEAD=1 bypasses the refusal" {
  { printf '/goal do the thing.\n'; head -c 5000 /dev/zero | tr '\0' 'x'; printf '\n'; } \
    > "$BATS_TEST_TMPDIR/p4.txt"
  run env FIRE_ALLOW_SLASH_HEAD=1 bash -c \
    "$(declare -f check_slash_head); check_slash_head '$BATS_TEST_TMPDIR/p4.txt'"
  [ "$status" -eq 0 ]
}

@test "cc-dispatch's composed brief does NOT start with a slash command (would be parsed as one)" {
  run grep -n 'cc-backlog item \$id (project \$PROJECT)' "$REPO/bin/cc-dispatch"
  [ "$status" -eq 0 ]
  ! printf '%s\n' "$output" | grep -q '"/'
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
  { printf '{"type":"user","message":{"role":"user","content":"the brief SEEN-MARKER ok"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n'
  } > "$PROJ/proj/s.jsonl"
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

# ---- T-P3-4 unit: mark_fired_peer (the cc-reaper auto-reap key) -------------------------------
# The marker is the ONLY thing that distinguishes a fired peer worker from an operator's own
# session, and cc-reaper will CLOSE a marked pane without asking. So the invariant that matters is
# not "it writes a file" — it is that nothing else can ever produce one.

@test "mark_fired_peer: writes a marker keyed by the fired pane UUID" {
  FPANE="2BE82E97-1111-4222-8333-444455556666"
  FDIR="$BATS_TEST_TMPDIR/fired"
  run mark_fired_peer "$FDIR" "$FPANE" "/work/cwd" "FIRING-0000-0000-0000-000000000002"
  [ "$status" -eq 0 ]
  [ -f "$FDIR/$FPANE.json" ]
  run jq -e '.selfRetire == true and .paneUUID=="'"$FPANE"'" and .cwd=="/work/cwd"' "$FDIR/$FPANE.json"
  [ "$status" -eq 0 ]
}

@test "mark_fired_peer: a non-UUID pane is refused (no marker, no path escape)" {
  # A pane value is never trusted as a path component — '../' must not reach the filesystem.
  FDIR="$BATS_TEST_TMPDIR/fired2"
  run mark_fired_peer "$FDIR" "../../etc/pwned" "/cwd" "by"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/etc/pwned.json" ]
  [ ! -d "$FDIR" ]
}

@test "mark_fired_peer: empty pane / empty dir are clean no-ops (fail-safe, never fatal)" {
  run mark_fired_peer "$BATS_TEST_TMPDIR/fired3" "" "/cwd" "by"
  [ "$status" -eq 0 ]
  [ ! -d "$BATS_TEST_TMPDIR/fired3" ]
  run mark_fired_peer "" "2BE82E97-1111-4222-8333-444455556666" "/cwd" "by"
  [ "$status" -eq 0 ]
}

@test "the fire path stamps the marker ONLY for a self-retiring peer fire" {
  # Guards the call-site condition, not just the function: a --no-self-retire or --recycle fire
  # must leave NO marker (⇒ cc-reaper treats it as an operator session ⇒ never auto-reaped).
  run grep -B4 'mark_fired_peer "$FIRED_DIR"' "$HF"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'if \[ "$WANT_SELF_RETIRE" = 1 \]; then'
}
