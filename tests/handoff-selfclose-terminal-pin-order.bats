#!/usr/bin/env bats
# THE TERMINAL VERDICT MUST BE PINNED BEFORE THE FIRST PANE→TTY QUERY, NOT MERELY BEFORE THE DETACH.
# (item 12f2524f8b83 — the residual half of the fired-peer self-close leak)
#
# KITTY_* are ordinary exported env vars: an iTerm2.app launched from a kitty pane inherits them and
# hands them to every pane under it forever. _as_tty_query therefore branches on kitty_identity(),
# which honours the CC_TERM pin and otherwise falls back to that inherited env var — so an UNPINNED
# query on a polluted box asks kitty's numeric id space for an iTerm2 UUID, gets no match, and
# returns the "pane absent" answer for a pane that is alive and enumerable.
#
# Item 191d1fc4143c stage 1 hoisted pin_term_verdict_for_watcher above SC_TTY. Two as_tty calls run
# ~160 lines EARLIER and were left unpinned, and neither degrades quietly — both are HARD ABORTS on
# a false negative:
#   SUC_TTY    → "successor pane <uuid> not found in iTerm2", exit 3, for a live successor.
#                `self-close --successor` is a primary close form.
#   SC_SC_TTY  → agent_id_on_tty(none) ⇒ "pane is NOT an Agent-Team assignee", exit 2, for one that is.
#
# THE DEFECT IS POSITIONAL, so the mechanism test alone cannot catch a regression of it — a future
# edit that moves the pin back below the gates would leave every behavioural assertion below green.
# Hence the ordering pin, which is the assertion that actually binds.
#
# Every assertion is `[ ]` or `run`+status. `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and are
# silently DEAD anywhere but a body's last line.

setup() {
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"   # hermeticity: never live ~/

  PANE="C0FA8974-3A79-47A2-BC66-F1D8C894710F"                          # UUID-shaped: never a kitty id
  TTY_ANSWER="/dev/ttys015"
  export PANE TTY_ANSWER

  hf_bounded() { "$@"; }
  kt_window_field() { printf ''; return 0; }   # kitty's honest answer for a UUID: no such window

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  OLOG="$BATS_TEST_TMPDIR/osascript.log"; : > "$OLOG"; export OLOG
  cat > "$STUB/osascript" <<'FAKE'
#!/bin/bash
printf 'osascript %s\n' "$*" >> "$OLOG"
cat >/dev/null 2>&1 || true
printf '%s\n' "$TTY_ANSWER"
FAKE
  chmod +x "$STUB/osascript"
  PATH="$STUB:$PATH"

  # in_kitty / kitty_identity are ONE-LINERS with no `^}` of their own — extract by their single
  # line, and GUARD every extraction: an empty eval is a vacuous pass.
  x_kitty="$(sed -n '/^in_kitty() {/p' "$HF")";                  [ -n "$x_kitty" ]
  x_kid="$(sed -n '/^kitty_identity() {/p' "$HF")";              [ -n "$x_kid" ]
  x_ttyq="$(sed -n '/^_as_tty_query() {/,/^}/p' "$HF")";         [ -n "$x_ttyq" ]
  x_tty="$(sed -n '/^as_tty() {/,/^}/p' "$HF")";                 [ -n "$x_tty" ]
  x_pin="$(sed -n '/^pin_term_verdict_for_watcher() {/,/^}/p' "$HF")"; [ -n "$x_pin" ]
  eval "$x_kitty"; eval "$x_kid"; eval "$x_ttyq"; eval "$x_tty"; eval "$x_pin"

  unset CC_TERM IT2_WRAPPER_NO_KITTY
  export KITTY_WINDOW_ID=2          # the pollution: inherited into a genuinely-iTerm2 pane
  printf '#!/bin/sh\nexit 1\n' > "$HOME/.claude/bin/cc-in-kitty"   # ancestry: this is iTerm2
  chmod +x "$HOME/.claude/bin/cc-in-kitty"
}

# ── the ordering pin — the assertion that actually binds ─────────────────────────────────────────

@test "self-close pins the terminal verdict BEFORE its first as_tty, not after" {
  # Window: self-close mode entry (SC_SID finalised) → the successor gate's as_tty. Both anchors are
  # load-bearing lines, so a rename breaks this loudly rather than silently widening the window.
  #
  # ANCHORED TO COLUMN 0-PLUS-INDENT, never a bare substring: this file DOCUMENTS its own call sites
  # in prose, and `SUC_TTY="$(as_tty …)"` appears inside a comment ~2100 lines above the code it
  # describes. An unanchored `head -1` picked that comment and compared the wrong pair of numbers —
  # the first draft of this very test failed that way, which is the whole argument for `^ *`.
  local start end win
  start="$(grep -n '^ *SC_SID="${SC_SID:-' "$HF" | head -1 | cut -d: -f1)";  [ -n "$start" ]
  end="$(grep -n '^ *SUC_TTY="\$(as_tty' "$HF" | head -1 | cut -d: -f1)";    [ -n "$end" ]
  [ "$start" -lt "$end" ]
  win="$(sed -n "${start},${end}p" "$HF")"

  # the pin must appear, and must appear BEFORE the first as_tty in that window
  local pin_at tty_at
  pin_at="$(printf '%s\n' "$win" | grep -n '^ *pin_term_verdict_for_watcher *$' | head -1 | cut -d: -f1)"
  tty_at="$(printf '%s\n' "$win" | grep -n 'as_tty "' | head -1 | cut -d: -f1)"
  [ -n "$pin_at" ]
  [ -n "$tty_at" ]
  [ "$pin_at" -lt "$tty_at" ]
}

# ── the mechanism the ordering protects ──────────────────────────────────────────────────────────

@test "CONTROL — unpinned, a live pane resolves to EMPTY (what the two gates saw)" {
  [ -z "${CC_TERM:-}" ]
  run kitty_identity; [ "$status" -eq 0 ]        # ← the wrong id space
  run as_tty "$PANE"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                               # ← SUC_TTY="" ⇒ exit 3 on a LIVE successor
  [ ! -s "$OLOG" ]                               # iTerm2 was never asked
}

@test "once pinned, the same pane resolves — the false abort cannot fire" {
  pin_term_verdict_for_watcher
  [ "${CC_TERM:-}" = "iterm2" ]
  run kitty_identity; [ "$status" -ne 0 ]
  run as_tty "$PANE"
  [ "$status" -eq 0 ]
  [ "$output" = "$TTY_ANSWER" ]
  [ -s "$OLOG" ]
}

@test "a genuine kitty box is unaffected — the pin confirms kitty and the id space stays kitty's" {
  printf '#!/bin/sh\nexit 0\n' > "$HOME/.claude/bin/cc-in-kitty"
  pin_term_verdict_for_watcher
  [ "${CC_TERM:-}" = "kitty" ]
  run kitty_identity; [ "$status" -eq 0 ]
  [ ! -s "$OLOG" ]
}

@test "UNVERIFIABLE ancestry pins nothing — today's env-var verdict stands, never a guess" {
  printf '#!/bin/sh\nexit 2\n' > "$HOME/.claude/bin/cc-in-kitty"
  pin_term_verdict_for_watcher
  [ -z "${CC_TERM:-}" ]
  run kitty_identity; [ "$status" -eq 0 ]
}
