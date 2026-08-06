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
  # THE DRAIN IS CONDITIONAL — drain ONLY a script-on-stdin invocation (`osascript - …`, which is the
  # shape _as_tty_query uses at handoff-fire.sh:785, where the heredoc guarantees the EOF that ends
  # it). An UNCONDITIONAL `cat` also reads stdin on the `osascript -e …` shape, where the real binary
  # never would — and there stdin is whatever the RUNNER inherited, so on a launchd / nightly /
  # background runner (stdin = a pipe nobody closes) the suite hangs forever. That is not theoretical:
  # it cost tests/handoff-fire-kitty.bats a 12h+ landing gate that never returned a verdict. This
  # suite reaches only the `-` shape today, so the guard is LATENT here — kept in lockstep so the
  # first `-e` assertion added to it does not silently re-arm the trap. Full rationale:
  # tests/handoff-fire-kitty.bats, the osascript stub in setup().
  cat > "$STUB/osascript" <<'FAKE'
#!/bin/bash
printf 'osascript %s\n' "$*" >> "$OLOG"
for a in "$@"; do
  if [ "$a" = "-" ]; then cat >/dev/null 2>&1 || true; break; fi
done
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

# THE WINDOW OPENS AT MODE ENTRY, NOT AT THE SC_SID LINE — and the widening is a STRENGTHENING.
# It used to open at `SC_SID="${SC_SID:-…}"`, the identity default. 255b3f66 then hoisted the pin ONE
# LINE ABOVE that ("a kitty peer could not name itself"): self_pane_id CONSUMES the ancestry verdict,
# so an unpinned peer on a kitty box exited 1 having done nothing, could never obey its own
# self-retire instruction, and leaked its pane and worktree until an operator reaped them. The
# property this test asserts became MORE true — the pin moved EARLIER relative to every as_tty — and
# the test went red anyway, because its window now opened one line BELOW the pin it was looking for.
# A position-keyed control that convicts its subject for improving is decayed, not vigilant.
#
# So the identity default stops being the window boundary and becomes an ASSERTED CONSUMER instead:
# the pin must precede BOTH self_pane_id (255b3f66 / item 4e074b938da7) and the first as_tty (item
# 12f2524f8b83). That is strictly more than the old window could see — re-anchoring alone would have
# licensed a pin sitting between SC_SID and the as_tty, i.e. the exact arrangement 255b3f66 fixed.
# The red-proof below mutates the REAL script into each of those three arrangements and requires a
# distinct conviction for each.
#
# ANCHORED TO COLUMN 0-PLUS-INDENT, never a bare substring: this file DOCUMENTS its own call sites
# in prose, and `SUC_TTY="$(as_tty …)"` appears inside a comment ~2100 lines above the code it
# describes. An unanchored `head -1` picked that comment and compared the wrong pair of numbers —
# the first draft of this very test failed that way, which is the whole argument for `^ *`. The new
# start anchor is safe on the same axis: the span it ADDS (mode entry → the pin) contains one prose
# mention of as_tty and no `as_tty "`, so the tty offset is unchanged by the widening.
#
# The verdict is computed over an ARBITRARY copy of the script so the IDENTICAL judge can be pointed
# at a mutant. Exit codes are distinct on purpose: a red-proof that goes red because an ANCHOR rotted
# rather than because the ordering broke is a vacuous control, and 10-14 say so out loud.
#   1  no pin in the window          2  pin below the first as_tty     3  pin below self_pane_id
#   10-14  an anchor failed to resolve — the subject drifted out from under this file
pin_order_verdict() {   # $1 = a handoff-fire.sh (real or mutant); prints the three in-window offsets
  local f="$1" start end win pin_at use_at tty_at
  start="$(grep -n '^if \[ "\${1:-}" = "self-close" \]' "$f" | head -1 | cut -d: -f1)"
  end="$(grep -n '^ *SUC_TTY="\$(as_tty' "$f" | head -1 | cut -d: -f1)"
  [ -n "$start" ] || return 10
  [ -n "$end" ]   || return 11
  [ "$start" -lt "$end" ] || return 12
  win="$(sed -n "${start},${end}p" "$f")"
  pin_at="$(printf '%s\n' "$win" | grep -n '^ *pin_term_verdict_for_watcher *$'  | head -1 | cut -d: -f1)"
  use_at="$(printf '%s\n' "$win" | grep -n '^ *SC_SID="\${SC_SID:-'              | head -1 | cut -d: -f1)"
  tty_at="$(printf '%s\n' "$win" | grep -n 'as_tty "'                            | head -1 | cut -d: -f1)"
  [ -n "$use_at" ] || return 13
  [ -n "$tty_at" ] || return 14
  printf 'window=%s..%s pin=%s use=%s tty=%s\n' "$start" "$end" "${pin_at:-NONE}" "$use_at" "$tty_at"
  [ -n "$pin_at" ] || return 1
  [ "$pin_at" -lt "$tty_at" ] || return 2
  [ "$pin_at" -lt "$use_at" ] || return 3
}

# Relocate the pin to sit immediately AFTER a named line of the REAL script, on stdout. It MOVES
# rather than rewrites — the mutant differs from the subject in position only, and inherits the
# destination's indentation — because a hand-authored approximation can pass for reasons the real
# artifact never had. The caller asserts the transform changed the file and preserved the pin count.
move_pin() {   # $1 = the pin's current line  $2 = the line to move it after  $3 = source file
  awk -v pin="$1" -v dest="$2" '
    NR == pin  { next }
    { print }
    NR == dest { match($0, /^[[:space:]]*/); print substr($0, 1, RLENGTH) "pin_term_verdict_for_watcher" }
  ' "$3"
}

@test "self-close pins the terminal verdict BEFORE its first as_tty, not after" {
  run pin_order_verdict "$HF"
  echo "verdict rc=$status :: $output" >&2      # bats surfaces this only when the assertion below fails
  [ "$status" -eq 0 ]
}

@test "RED-PROOF — the same judge convicts a pin moved below EITHER consumer, or deleted" {
  local entry pin_line sc_line tty_line pins m
  entry="$(grep -n '^if \[ "\${1:-}" = "self-close" \]' "$HF" | head -1 | cut -d: -f1)"; [ -n "$entry" ]
  pin_line="$(awk -v s="$entry" 'NR>=s && /^[[:space:]]*pin_term_verdict_for_watcher[[:space:]]*$/ {print NR; exit}' "$HF")"
  sc_line="$(grep -n '^ *SC_SID="\${SC_SID:-' "$HF" | head -1 | cut -d: -f1)"
  tty_line="$(awk -v s="$entry" 'NR>=s && /as_tty "/ {print NR; exit}' "$HF")"
  [ -n "$pin_line" ]; [ -n "$sc_line" ]; [ -n "$tty_line" ]
  echo "entry=$entry pin=$pin_line sc=$sc_line tty=$tty_line" >&2
  pins="$(grep -c '^ *pin_term_verdict_for_watcher *$' "$HF")"

  # MUTANT 1 — the pin back where 255b3f66 hoisted it FROM: below the identity default, still above
  # every as_tty. This is the arrangement a window that OPENED at SC_SID was structurally unable to
  # convict, so this case is the proof that re-anchoring strengthened the test instead of widening it.
  m="$BATS_TEST_TMPDIR/pin-below-sid.sh"
  move_pin "$pin_line" "$sc_line" "$HF" > "$m"
  run cmp -s "$HF" "$m"; [ "$status" -ne 0 ]                                     # the transform DID something
  [ "$(grep -c '^ *pin_term_verdict_for_watcher *$' "$m")" = "$pins" ]           # moved, never dropped
  run pin_order_verdict "$m"
  echo "mutant-1 rc=$status :: $output" >&2
  [ "$status" -eq 3 ]

  # MUTANT 2 — the pin below the FIRST as_tty (SC_SC_TTY's), the regression this file was written for.
  m="$BATS_TEST_TMPDIR/pin-below-astty.sh"
  move_pin "$pin_line" "$tty_line" "$HF" > "$m"
  [ "$(grep -c '^ *pin_term_verdict_for_watcher *$' "$m")" = "$pins" ]
  run pin_order_verdict "$m"
  echo "mutant-2 rc=$status :: $output" >&2
  [ "$status" -eq 2 ]

  # MUTANT 3 — no pin at all in the window: the shape a rotted anchor also produces, which is why the
  # code for it is distinct from both orderings above.
  m="$BATS_TEST_TMPDIR/pin-deleted.sh"
  awk -v pin="$pin_line" 'NR != pin' "$HF" > "$m"
  [ "$(grep -c '^ *pin_term_verdict_for_watcher *$' "$m")" -eq $((pins - 1)) ]
  run pin_order_verdict "$m"
  echo "mutant-3 rc=$status :: $output" >&2
  [ "$status" -eq 1 ]
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
