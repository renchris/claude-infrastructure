#!/usr/bin/env bats
# Regression guard: the opt-in --tab / --window launch surfaces MUST create-then-verified-type,
# NEVER osascript `write text` (item 0b878805bc27, 2026-07-19).
#
# Same ttys018 ZLE-race root cause as the split / bg-tab surfaces (item e4c7e7fb41bd): a raw
# char-stream into a fresh zsh transposes characters (`cd` → `ould ocd`) and floods the shell with
# the tail of the brief. as_tab (--follow --tab) and spawn_frontmost (--window) typed via osascript
# `write text` — a DIFFERENT transport, IDENTICAL corruption. This file locks the fix: those two
# functions now CREATE the surface + return the new session id, and the dispatcher lands the command
# through it2_land → it2_type_verified (bracketed-paste + echo-verify), the ZLE-race-safe path the
# split / bg-tab surfaces already use.
#
# These are SOURCE-level invariants: the real as_tab / spawn_frontmost osascript needs a live iTerm2
# to run (it creates a real tab/window), so the create step cannot execute in CI. The durable,
# checkable guarantees are (a) neither function ever types (no `write text` in its body), (b) each
# creates a surface and returns its id, (c) the $ESC AppleScript-string escaping that ONLY the
# write-text path needed is gone, and (d) the dispatcher routes both surfaces through it2_land. The
# it2_type_verified transport itself is unit-tested in handoff-fire-inject.bats; the dispatcher
# wiring (id → it2_land, fail-loud) is exercised with stubs in handoff-splitright.bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  AS_TAB="$(sed -n '/^as_tab() {/,/^}/p' "$HF")"
  SPAWN_FM="$(sed -n '/^spawn_frontmost() {/,/^}/p' "$HF")"
  SPAWN_FN="$(sed -n '/^spawn() {/,/^}/p' "$HF")"
}

@test "as_tab NEVER types — no osascript 'write text' in its body" {
  [ -n "$AS_TAB" ]
  ! grep -q 'write text' <<<"$AS_TAB"
}

@test "as_tab CREATES a background tab and echoes the new session id (OK <id> | NOTFOUND)" {
  grep -q 'create tab' <<<"$AS_TAB"
  grep -qF '"OK " & (id of newSess)' <<<"$AS_TAB"
  grep -q 'NOTFOUND' <<<"$AS_TAB"
}

@test "spawn_frontmost NEVER types — no osascript 'write text' in its body" {
  [ -n "$SPAWN_FM" ]
  ! grep -q 'write text' <<<"$SPAWN_FM"
}

@test "spawn_frontmost CREATES a fresh window and returns the new session id" {
  grep -q 'create window' <<<"$SPAWN_FM"
  grep -qF 'return id of current session of newWin' <<<"$SPAWN_FM"
}

@test "the \$ESC AppleScript-string escaping is fully removed (no write-text path survives)" {
  # The whole file: no ESC= definition and no "$ESC" interpolation into an osascript string literal.
  ! grep -qE '^ESC=' "$HF"
  ! grep -qF '"$ESC"' "$HF"
}

@test "the dispatcher lands BOTH --tab and --window through it2_land (the verified transport)" {
  # --window: capture spawn_frontmost's id, then it2_land it.
  grep -qF 'winid="$(spawn_frontmost' <<<"$SPAWN_FN"
  grep -qF 'it2_land "$winid"' <<<"$SPAWN_FN"
  # --tab: capture as_tab's id, then it2_land it.
  grep -qF 'as_tab "$FIRING_SID"' <<<"$SPAWN_FN"
  grep -qF 'it2_land "$newid"' <<<"$SPAWN_FN"
}

@test "as_tab is invoked create-only — no launch command (\$CMD) passed to it" {
  # The old signature was as_tab <sid> <command>; the command arg is gone (it2_land types $CMD now).
  ! grep -qF 'as_tab "$FIRING_SID" "$CMD"' <<<"$SPAWN_FN"
}
