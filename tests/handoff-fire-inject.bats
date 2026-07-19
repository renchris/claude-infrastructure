#!/usr/bin/env bats
# Regression guard for handoff-fire.sh RELIABLE LAUNCH-COMMAND INJECTION (INC ttys018, 2026-07-19).
#
# The incident: a fire's launch command `cd <cwd> && <launcher> … "$(cat <prompt-file>)"` was typed
# into a fresh split pane as a raw async_send_text char-stream, which raced the target zsh's ZLE
# (zsh-autosuggestions + zsh-syntax-highlighting per-keystroke widgets + `setopt CORRECT`). Characters
# transposed (`cd` → `ould ocd`), CORRECT held the mangled word at a [nyae] prompt, and the tail of
# the line — including the `"$(cat …)"` — spilled out of its quotes so the brief flooded the shell as
# raw commands. The launcher never started; the worker was left task-less.
#
# The durable invariants this file locks down (the 2 composed defenses in it2_type_verified):
#   1. BRACKETED PASTE — the command is sent wrapped in ESC[200~ … ESC[201~ (atomic literal insert,
#      no per-keystroke ZLE widget can corrupt it), never as a bare char-stream;
#   2. ECHO-VERIFY before submit — the pane is read back and the intact command confirmed on the input
#      line BEFORE any CR. The load-bearing safety property: a line that does NOT verify is NEVER
#      submitted (no Enter), so a mangled command can never execute.
# Plus: graceful degradation (final attempt falls back to a plain send, still echo-gated) and the
# multi-line RESEND helper (it2_paste_submit) pastes-then-submits atomically (no line-by-line flood).
#
# Functions are extracted from the real script (same technique as handoff-splitright.bats). REAL_IT2
# is stubbed with a fake it2 that RECORDS every `session send` as an event (CTRLU / CR / PASTE / PLAIN)
# and serves a configurable `session read` echo — "perfect" (echoes what was pasted), "garbage" (never
# matches → corruption), "corrupt-once" (garbage first read then good) and "only-plain" (matches only a
# plain send → drives the fallback). The mode is switched per-test via a file the mock reads.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"

  EVENTS="$BATS_TEST_TMPDIR/events"; : > "$EVENTS"
  SCREEN="$BATS_TEST_TMPDIR/screen"; : > "$SCREEN"
  MODE_FILE="$BATS_TEST_TMPDIR/mode"; printf 'perfect' > "$MODE_FILE"
  FIRSTPASTE="$BATS_TEST_TMPDIR/firstpaste"; rm -f "$FIRSTPASTE"
  LASTTYPE="$BATS_TEST_TMPDIR/lasttype"; : > "$LASTTYPE"
  SEEN="$BATS_TEST_TMPDIR/seen"; rm -f "$SEEN"

  FAKE_IT2="$BATS_TEST_TMPDIR/it2"
  # Expanding heredoc — bake the record paths in; the mock stays mode-driven via $MODE_FILE.
  cat > "$FAKE_IT2" <<SH
#!/usr/bin/env bash
EVENTS='$EVENTS'; SCREEN='$SCREEN'; MODE_FILE='$MODE_FILE'
FIRSTPASTE='$FIRSTPASTE'; LASTTYPE='$LASTTYPE'; SEEN='$SEEN'
SH
  cat >> "$FAKE_IT2" <<'SH'
ESC=$'\x1b'; BPS="${ESC}[200~"; BPE="${ESC}[201~"; CU=$'\x15'; CR=$'\r'
mode="perfect"; [ -f "$MODE_FILE" ] && mode="$(cat "$MODE_FILE")"
sub="${1:-}"; verb="${2:-}"
if [ "$sub" = session ] && [ "$verb" = send ]; then
  shift 2; text=""
  while [ $# -gt 0 ]; do case "$1" in -s) shift 2 ;; *) text="$1"; shift ;; esac; done
  if [ "$text" = "$CU" ]; then
    printf 'CTRLU\n' >> "$EVENTS"; : > "$SCREEN"; printf 'CTRLU' > "$LASTTYPE"
  elif [ "$text" = "$CR" ]; then
    printf 'CR\n' >> "$EVENTS"; printf 'CR' > "$LASTTYPE"
  else
    case "$text" in
      "${BPS}"*"${BPE}")
        [ -f "$FIRSTPASTE" ] || printf '%s' "$text" > "$FIRSTPASTE"
        inner="${text#"$BPS"}"; inner="${inner%"$BPE"}"
        printf 'PASTE\n' >> "$EVENTS"; printf '%s' "$inner" > "$SCREEN"; printf 'PASTE' > "$LASTTYPE" ;;
      *)
        printf 'PLAIN\n' >> "$EVENTS"; printf '%s' "$text" > "$SCREEN"; printf 'PLAIN' > "$LASTTYPE" ;;
    esac
  fi
  exit 0
fi
if [ "$sub" = session ] && [ "$verb" = read ]; then
  case "$mode" in
    garbage)      printf 'zsh: correct ould ocd? [nyae]\n' ;;
    corrupt-once) if [ -f "$SEEN" ]; then cat "$SCREEN" 2>/dev/null; else : > "$SEEN"; printf 'ould ocd garbage\n'; fi ;;
    only-plain)   if [ "$(cat "$LASTTYPE" 2>/dev/null)" = PLAIN ]; then cat "$SCREEN" 2>/dev/null; else printf 'not-a-match\n'; fi ;;
    *)            cat "$SCREEN" 2>/dev/null ;;
  esac
  exit 0
fi
exit 0
SH
  chmod +x "$FAKE_IT2"

  # Fast timings for tests.
  export FIRE_TYPE_SETTLE=0.01 FIRE_TYPE_PRESETTLE=0.001 FIRE_TYPE_ATTEMPTS=4 FIRE_TYPE_READLINES=20

  # Extract the bracketed-paste markers + the two helpers under test from the real script.
  eval "$(grep -E '^BP_(START|END)=' "$HF")"
  eval "$(sed -n '/^it2_type_verified() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^it2_paste_submit() {/,/^}/p' "$HF")"

  CMD='cd /private/tmp/wt-x && claude-next3 --effort max "$(cat /tmp/fire-abc.txt)"'
}

set_mode() { printf '%s' "$1" > "$MODE_FILE"; }

@test "it2_type_verified: happy path — bracketed-pastes, verifies the echo, THEN submits" {
  set_mode perfect
  run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  grep -q '^PASTE$' "$EVENTS"
  grep -q '^CR$' "$EVENTS"
  # PASTE must precede CR (never submit before the command is on the line).
  [ "$(grep -nE '^(PASTE|CR)$' "$EVENTS" | head -1)" = "$(grep -n '^PASTE$' "$EVENTS" | head -1)" ]
}

@test "it2_type_verified: the command is wrapped in bracketed-paste markers, inner intact" {
  set_mode perfect
  run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  # The exact bytes of the first paste == ESC[200~ + CMD + ESC[201~ (no corruption, both markers).
  [ -f "$FIRSTPASTE" ]
  [ "$(cat "$FIRSTPASTE")" = "${BP_START}${CMD}${BP_END}" ]
  # And what the terminal "echoed" (mock SCREEN) is exactly the command — the launcher gets it intact.
  [ "$(cat "$SCREEN")" = "$CMD" ]
}

@test "it2_type_verified: SAFETY — a non-verifying echo is NEVER submitted (no CR), fails loud" {
  set_mode garbage
  run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -ne 0 ]                      # fail-loud
  ! grep -q '^CR$' "$EVENTS"               # the load-bearing invariant: no Enter on an unverified line
  grep -q '^PASTE$' "$EVENTS"              # it DID try (bracketed paste)
  grep -q '^CTRLU$' "$EVENTS"              # and scrubbed the mangled line
}

@test "it2_type_verified: recovers on retry when the first echo is corrupt" {
  set_mode corrupt-once
  run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  grep -q '^CR$' "$EVENTS"                 # eventually submits after a clean re-verify
  [ "$(grep -c '^PASTE$' "$EVENTS")" -ge 2 ]   # took at least two paste attempts
}

@test "it2_type_verified: final attempt falls back to a plain send, still echo-gated" {
  set_mode only-plain
  run it2_type_verified "$FAKE_IT2" SID "$CMD"
  [ "$status" -eq 0 ]
  grep -q '^PLAIN$' "$EVENTS"              # degraded to an un-bracketed send on the last attempt
  grep -q '^CR$' "$EVENTS"                 # still only after echo-verify passed
  [ "$(grep -c '^PASTE$' "$EVENTS")" -ge 3 ]   # tried bracketed paste first (attempts 1..N-1)
}

@test "it2_type_verified: an empty command is refused (never blindly submits)" {
  run it2_type_verified "$FAKE_IT2" SID ""
  [ "$status" -ne 0 ]
  ! grep -q '^CR$' "$EVENTS"
}

@test "it2_paste_submit: pastes the multi-line brief atomically then submits (no flood)" {
  local brief=$'first line of brief\nsecond line: run the gate\n<!-- marker HANDOFF-ENGAGE-x -->'
  run it2_paste_submit "$FAKE_IT2" SID "$brief"
  [ "$status" -eq 0 ]
  # Exactly one PASTE then one CR — the brief never goes out as line-by-line commands.
  [ "$(grep -cE '^(PASTE|PLAIN)$' "$EVENTS")" -eq 1 ]
  grep -q '^PASTE$' "$EVENTS"
  grep -q '^CR$' "$EVENTS"
  [ "$(cat "$FIRSTPASTE")" = "${BP_START}${brief}${BP_END}" ]
}
