#!/usr/bin/env bats
# bin/desk-register — the standalone desk-role registration primitive. handoff-fire writes
# cc-roles/<role> on an `--as-role` fire; this is the same claim for a HAND-started desk
# (`claude-desk`, `/desk`) that handoff-fire never touched.
#
# What these prove: the pane actually written (UUID parsed out of the iTerm2 "wNtNpN:UUID" form),
# idempotency, atomicity (no half-written file, no tmp litter), and — the load-bearing one — that a
# malformed $ITERM_SESSION_ID FAILS LOUD instead of writing a garbage role file. A garbage role file
# silently breaks ping routing, the reaper's page target and cc-classify's desk never-reap, so
# "wrote something" is a WORSE outcome than "refused".

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DR="$REPO/bin/desk-register"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  # A reassignment now also writes the crash-path mailbox `.forward`, so the mailbox dir must be
  # isolated too — otherwise a test would write a pointer into the LIVE ~/.claude/mailbox.
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  PANE="8B90BC66-9853-4F63-9C1C-39B161174221"
  export ITERM_SESSION_ID="w2t0p3:$PANE"
  unset SESSION_ID
  # SEAM 5b: the kitty-ancestry predicate is a BARE NAME the subject EXECUTES, so an unpinned
  # $CC_IN_KITTY_BIN would run the operator's deployed cc-in-kitty and let this suite's verdicts
  # depend on which terminal the box happens to be running. Pinned to an ABSENT path, which is the
  # right default here: derived_is_kitty_window fails closed on a missing predicate, so the
  # non-kitty cases assert the iTerm2 behaviour they mean to. The kitty cases override it per test.
  export CC_IN_KITTY_BIN="$BATS_TEST_TMPDIR/no-such-cc-in-kitty"
}
role_file() { cat "$CC_ROLES_DIR/${1:-desk}" 2>/dev/null; }

@test "fresh: parses the pane UUID out of \$ITERM_SESSION_ID and writes it" {
  run "$DR"
  [ "$status" -eq 0 ]
  [[ "$output" == "registered desk → $PANE" ]] || false
  [ "$(role_file)" = "$PANE" ]
}

@test "idempotent: re-registering the SAME pane is a no-op, not a rewrite" {
  run "$DR"; [ "$status" -eq 0 ]
  before="$(stat -f %m "$CC_ROLES_DIR/desk")"
  run "$DR"
  [ "$status" -eq 0 ]
  [[ "$output" == already\ desk\ →\ * ]] || false
  [ "$(stat -f %m "$CC_ROLES_DIR/desk")" = "$before" ]   # untouched, not rewritten
  [ "$(role_file)" = "$PANE" ]
}

@test "reassign: a DIFFERENT pane takes the role and the move is reported (never silent)" {
  printf 'OLD-PANE-UUID\n' > "$CC_ROLES_DIR/desk" 2>/dev/null || { mkdir -p "$CC_ROLES_DIR"; printf 'OLD-PANE-UUID\n' > "$CC_ROLES_DIR/desk"; }
  run "$DR"
  [ "$status" -eq 0 ]
  [[ "$output" == "reassigned desk: OLD-PANE-UUID → $PANE" ]] || false
  [ "$(role_file)" = "$PANE" ]
}

@test "malformed \$ITERM_SESSION_ID (no colon) → FAILS LOUD, writes NOTHING" {
  export ITERM_SESSION_ID="garbage-no-colon"
  run "$DR"
  [ "$status" -eq 1 ]
  # The refusal wording moved from "a pane UUID" to "a pane id for THIS terminal" when the check
  # learned kitty's id space (9002948eb52c) — one check, two id spaces, so "UUID" stopped being the
  # whole story. The assertion follows the wording rather than pinning a string the subject
  # deliberately changed, and keeps the ECHO of the offending value so it cannot go vacuous.
  [[ "$output" == *"did not yield a pane id"* ]] || false
  [[ "$output" == *"garbage-no-colon"* ]] || false
  [ ! -f "$CC_ROLES_DIR/desk" ]        # the whole point: no garbage role file
}

@test "no \$ITERM_SESSION_ID and no --pane → FAILS LOUD, writes NOTHING" {
  unset ITERM_SESSION_ID
  run "$DR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot tell which pane"* ]] || false
  [ ! -f "$CC_ROLES_DIR/desk" ]
}

@test "--force accepts a non-UUID pane (documented escape hatch)" {
  export ITERM_SESSION_ID="w0t0p0:some-pane-name"
  run "$DR" --force
  [ "$status" -eq 0 ]
  [ "$(role_file)" = "some-pane-name" ]
}

@test "--pane is taken VERBATIM (role files legitimately hold a uuid, sid or name)" {
  run "$DR" --pane "rSID"
  [ "$status" -eq 0 ]
  [ "$(role_file)" = "rSID" ]
}

@test "--role targets a non-desk role without disturbing desk" {
  run "$DR"; [ "$status" -eq 0 ]
  run "$DR" --role operator --pane "OP-1"
  [ "$status" -eq 0 ]
  [ "$(role_file operator)" = "OP-1" ]
  [ "$(role_file desk)" = "$PANE" ]     # untouched
}

@test "--print reads the holder without writing; exit 1 when unregistered" {
  run "$DR" --print
  [ "$status" -eq 1 ]
  [ ! -f "$CC_ROLES_DIR/desk" ]         # a read must never create the file
  run "$DR"; [ "$status" -eq 0 ]
  run "$DR" --print
  [ "$status" -eq 0 ]
  [ "$output" = "$PANE" ]
}

@test "--quiet is silent on success but still writes" {
  run "$DR" --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(role_file)" = "$PANE" ]
}

@test "unknown argument → exit 2 (fail-loud, never a silent no-op)" {
  run "$DR" --nope
  [ "$status" -eq 2 ]
  [ ! -f "$CC_ROLES_DIR/desk" ]
}

@test "atomic: no tmp litter left in the roles dir" {
  run "$DR"; [ "$status" -eq 0 ]
  run "$DR" --pane "SECOND"; [ "$status" -eq 0 ]
  # only the role file itself — a reader must never see (or trip over) a partial .desk.$$ file
  [ "$(find "$CC_ROLES_DIR" -name '.*' -type f | wc -l | tr -d ' ')" = "0" ]
}

@test "\$SESSION_ID outranks \$ITERM_SESSION_ID (explicit beats derived)" {
  export SESSION_ID="EXPLICIT-SID"
  run "$DR"
  [ "$status" -eq 0 ]
  [ "$(role_file)" = "EXPLICIT-SID" ]
}

# ── CRASH-PATH SUCCESSION: only handoff-fire's graceful self-close used to write a `.forward` ──────
@test "reassign writes the mailbox .forward — a crashed holder's box becomes a POINTER, not a strand" {
  OLD="AAAAAAAA-1111-2222-3333-444444444444"
  mkdir -p "$CC_ROLES_DIR"; printf '%s\n' "$OLD" > "$CC_ROLES_DIR/desk"
  run "$DR"
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_MAILBOX_DIR/$OLD.forward")" = "$PANE" ]
  [[ "$output" == *"mail forwarded: $OLD → $PANE"* ]] || false
}

@test "the forward makes raw-uuid mail follow the succession (the 631-line stranding class)" {
  OLD="AAAAAAAA-1111-2222-3333-444444444444"
  mkdir -p "$CC_ROLES_DIR"; printf '%s\n' "$OLD" > "$CC_ROLES_DIR/desk"
  run "$DR"; [ "$status" -eq 0 ]
  # a peer still holding the dead pane's RAW uuid now resolves to the successor
  . "$REPO/hooks/lib/mailbox-pending.sh"
  [ "$(mailbox_forward_of "$OLD")" = "$PANE" ]
}

@test "a FRESH registration writes no forward (there is no predecessor to point away from)" {
  run "$DR"
  [ "$status" -eq 0 ]
  [ "$(find "$CC_MAILBOX_DIR" -name '*.forward' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
}

@test "an idempotent re-register writes no forward (a self-forward would hide a real bug)" {
  mkdir -p "$CC_ROLES_DIR"; printf '%s\n' "$PANE" > "$CC_ROLES_DIR/desk"
  run "$DR"
  [ "$status" -eq 0 ]
  [ "$(find "$CC_MAILBOX_DIR" -name '*.forward' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
}

@test "a NON-canonical previous holder gets no pointer, and the registration still succeeds" {
  mkdir -p "$CC_ROLES_DIR"; printf 'OLD-PANE-UUID\n' > "$CC_ROLES_DIR/desk"
  run "$DR"
  [ "$status" -eq 0 ]
  [ "$(role_file)" = "$PANE" ]
  [ "$(find "$CC_MAILBOX_DIR" -name '*.forward' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]
}

# ── THE KITTY ID SPACE (backlog 9002948eb52c, 2026-09-08) ────────────────────────────────────────
# The shape check knew only iTerm2's id space, so on the terminal this fleet actually runs it
# refused EVERY hand-started desk: scripts/kitty-setup.sh:290 exports a synthetic
# ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID", `${itsid##*:}` yields a bare integer, and the UUID case
# never matched. Reproduced pre-fix: `ITERM_SESSION_ID=w0t0p0:618 desk-register` → exit 1, "did not
# yield a pane UUID (got '618')", nothing written — while the live cc-roles/ files written by
# handoff-fire's write_role held exactly that form (desk=330, docs-lead=450, drain-lead=7).
#
# The accept is NOT "digits are fine". A bare integer here has three possible origins and only one is
# us, so both terms must hold: cc-in-kitty (ancestry, fail-closed) AND pair agreement with
# $KITTY_WINDOW_ID. The last two cases pin each term by making the OTHER one pass — a case that let
# both fail together would go green on a fix that implemented neither.
#
# cc-in-kitty is stubbed through $CC_IN_KITTY_BIN rather than $PATH: the suite runs inside a real
# kitty window, so an unstubbed predicate would answer from the MACHINE and the refusal cases could
# not be expressed at all.
kitty_stub() { # <exit-code> → path to a cc-in-kitty stub that always answers <exit-code>
  local rc="$1"
  local p="$BATS_TEST_TMPDIR/cc-in-kitty-$rc"   # own `local`: $rc is not in scope inside the one above
  printf '#!/bin/sh\nexit %s\n' "$rc" > "$p"; chmod +x "$p"; printf '%s' "$p"
}

@test "kitty: \$ITERM_SESSION_ID='w0t0p0:<KITTY_WINDOW_ID>' registers the integer window id" {
  export ITERM_SESSION_ID="w0t0p0:618"
  export KITTY_WINDOW_ID=618
  CC_IN_KITTY_BIN="$(kitty_stub 0)"
  export CC_IN_KITTY_BIN
  run "$DR"
  [ "$status" -eq 0 ]
  [[ "$output" == "registered desk → 618" ]] || false
  [ "$(role_file)" = "618" ]
}

@test "kitty: the integer is REFUSED when ancestry says we are not in kitty (polluted iTerm2 env)" {
  export ITERM_SESSION_ID="w0t0p0:618"
  export KITTY_WINDOW_ID=618          # pair agreement HOLDS — only the ancestry term refuses
  CC_IN_KITTY_BIN="$(kitty_stub 1)"
  export CC_IN_KITTY_BIN
  run "$DR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not yield a pane id for THIS terminal"* ]] || false
  [ ! -f "$CC_ROLES_DIR/desk" ]
}

@test "kitty: the integer is REFUSED when it disagrees with \$KITTY_WINDOW_ID (stale inherited id)" {
  export ITERM_SESSION_ID="w0t0p0:330"
  export KITTY_WINDOW_ID=618          # ancestry HOLDS — only the pair-agreement term refuses
  CC_IN_KITTY_BIN="$(kitty_stub 0)"
  export CC_IN_KITTY_BIN
  run "$DR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not yield a pane id for THIS terminal"* ]] || false
  [ ! -f "$CC_ROLES_DIR/desk" ]
}

@test "kitty: an integer with NO \$KITTY_WINDOW_ID at all is still refused (iTerm2 unaffected)" {
  export ITERM_SESSION_ID="w0t0p0:618"
  unset KITTY_WINDOW_ID
  CC_IN_KITTY_BIN="$(kitty_stub 0)"
  export CC_IN_KITTY_BIN
  run "$DR"
  [ "$status" -eq 1 ]
  [ ! -f "$CC_ROLES_DIR/desk" ]
}
