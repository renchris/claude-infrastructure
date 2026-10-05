#!/usr/bin/env bats
# Forward chains + succession migration (v3 D1) — hooks/lib/mailbox-pending.sh.
#
# What these pin: a pane-UUID-keyed mailbox strands its contents when the pane recycles (live forensics
# 2026-07-20: 631/206/155 unread lines in former-desk boxes). A `.forward` pointer makes a dead box a
# POINTER — followed at SEND time, and drained ONCE by the successor at adoption time.
#
# Harness rules (v1 suite, learned from real escapes):
#   1. `|| false` on EVERY bare [[ ]] — bats does not trap a bare [[ ]] failure mid-body.
#   2. Assert the SPECIFIC value, never a loose glob a degraded result also matches.
# Isolation: CC_MAILBOX_DIR only — never the live ~/.claude/mailbox.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  mkdir -p "$CC_MAILBOX_DIR"
  # shellcheck source=../hooks/lib/mailbox-pending.sh
  . "$REPO/hooks/lib/mailbox-pending.sh"
  A="AAAAAAAA-1111-2222-3333-444444444444"
  B="BBBBBBBB-1111-2222-3333-444444444444"
  C="CCCCCCCC-1111-2222-3333-444444444444"
}

# ── mailbox_forward_of ────────────────────────────────────────────────────────────────────────────

@test "no forward → the head IS the input uuid (callers can pipe unconditionally)" {
  [ "$(mailbox_forward_of "$A")" = "$A" ]
}

@test "a chain resolves to its terminal head (A→B→C ⇒ C)" {
  mailbox_write_forward "$A" "$B"
  mailbox_write_forward "$B" "$C"
  [ "$(mailbox_forward_of "$A")" = "$C" ]
}

@test "a CYCLE terminates at the last good hop instead of spinning (a hook must never hang)" {
  mailbox_write_forward "$A" "$B"
  mailbox_write_forward "$B" "$C"
  mailbox_write_forward "$C" "$A"        # close the loop
  run timeout 10 bash -c ". '$REPO/hooks/lib/mailbox-pending.sh'; mailbox_forward_of '$A'"
  [ "$status" -eq 0 ]                    # 124 would mean the timeout killed a spin
  # The VALUE, not merely non-emptiness. mailbox-pending.sh:398 breaks on the visited set BEFORE
  # advancing, so the last good hop is exactly C — and `[ -n "$output" ]` passes just as happily on
  # A, the fully-degraded result where the chain was not followed at all. The sibling bounded-hops
  # test below pins its value, so the loose one was the outlier against this file's own header.
  [ "$output" = "$C" ]
}

@test "chain depth is BOUNDED — a longer-than-max chain stops early, never walks forever" {
  local prev="$A" nxt
  for i in 1 2 3 4 5 6; do
    nxt="$(printf '%08d-1111-2222-3333-444444444444' "$i")"
    mailbox_write_forward "$prev" "$nxt"; prev="$nxt"
  done
  CC_MBX_FORWARD_MAX_HOPS=2 run bash -c ". '$REPO/hooks/lib/mailbox-pending.sh'; CC_MBX_FORWARD_MAX_HOPS=2 mailbox_forward_of '$A'"
  [ "$status" -eq 0 ]
  [ "$output" = "00000002-1111-2222-3333-444444444444" ]   # exactly 2 hops, not the true head
}

@test "a JUNK forward pointer stops at the last good hop (never delivers to garbage)" {
  printf 'not-a-uuid!!\n' > "$CC_MAILBOX_DIR/$A.forward"
  [ "$(mailbox_forward_of "$A")" = "$A" ]
}

@test "a SELF-forward is refused (it would hide a real succession bug behind a no-op pointer)" {
  run mailbox_write_forward "$A" "$A"
  [ "$status" -eq 1 ]
  [ ! -f "$CC_MAILBOX_DIR/$A.forward" ]
}

# ── mailbox_migrate ───────────────────────────────────────────────────────────────────────────────

@test "migrate moves exactly the UNCONSUMED (acked, EOF] window, with provenance" {
  printf 'l1\nl2\nl3\n' > "$CC_MAILBOX_DIR/$A.md"
  printf '2\n' > "$CC_MAILBOX_DIR/$A.acked"      # l1,l2 provably consumed; only l3 is owed
  printf '2\n' > "$CC_MAILBOX_DIR/$A.seen"
  run mailbox_migrate "$A" "$B"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$B.md")" -eq 1 ]
  grep -q '\[forwarded:AAAAAAAA\] l3' "$CC_MAILBOX_DIR/$B.md"
  # COUNT, not `grep -qv`. `grep -qv PAT` exits 0 whenever ANY line fails to match, so over the
  # exact regression fixture (migrate re-delivering from line 0, i.e. $B.md carrying all three
  # forwarded lines) it exits 0 and the assertion passes — the same verdict as over the correct
  # single-line output. Zero discriminating power: the only input that reds it is one where EVERY
  # line matches, which this fixture cannot produce. A bare `! grep -q` would work here today only
  # because this is the terminal statement of the body — an `!`-inverted status is errexit-exempt,
  # so that form dies silently the moment anyone appends an assertion below it.
  [ "$(grep -c 'l1' "$CC_MAILBOX_DIR/$B.md" || true)" -eq 0 ]   # consumed lines are NOT re-delivered
}

@test "migrate is IDEMPOTENT — a second call moves nothing (safe on every SessionStart)" {
  printf 'x1\nx2\n' > "$CC_MAILBOX_DIR/$A.md"
  run mailbox_migrate "$A" "$B"; [ "$output" = "2" ]
  run mailbox_migrate "$A" "$B"
  [ "$status" -eq 1 ]
  [ "$output" = "0" ]
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$B.md")" -eq 2 ]   # NOT 4 — no duplication
}

@test "migrate advances BOTH of the predecessor's cursors to EOF (the guard stops alarming)" {
  printf 'y1\ny2\ny3\n' > "$CC_MAILBOX_DIR/$A.md"
  mailbox_migrate "$A" "$B" >/dev/null
  [ "$(mailbox_seen "$A")"  -eq 3 ]
  [ "$(mailbox_acked "$A")" -eq 3 ]
  [ "$(mailbox_unacked_count "$A")" -eq 0 ]
}

@test "migrate preserves the 1-message-1-line cursor contract" {
  printf 'a\nb\nc\nd\n' > "$CC_MAILBOX_DIR/$A.md"
  mailbox_migrate "$A" "$B" >/dev/null
  [ "$(mailbox_lines "$B")" -eq 4 ]
}

@test "migrate onto a NON-EMPTY successor box APPENDS (never clobbers the successor's own mail)" {
  printf 'own-mail\n' > "$CC_MAILBOX_DIR/$B.md"
  printf 'inherited\n' > "$CC_MAILBOX_DIR/$A.md"
  mailbox_migrate "$A" "$B" >/dev/null
  [ "$(grep -c '' "$CC_MAILBOX_DIR/$B.md")" -eq 2 ]
  grep -q '^own-mail$' "$CC_MAILBOX_DIR/$B.md"
}

@test "migrate refuses a self-migration and a missing source box (no cursor damage)" {
  printf 'z\n' > "$CC_MAILBOX_DIR/$A.md"
  run mailbox_migrate "$A" "$A";  [ "$status" -eq 1 ]; [ "$output" = "0" ]
  run mailbox_migrate "$C" "$B";  [ "$status" -eq 1 ]; [ "$output" = "0" ]   # C has no box
  [ "$(mailbox_acked "$A")" -eq 0 ]                                          # untouched
}

@test "nothing unconsumed → migrate is a no-op (fully-drained predecessor)" {
  printf 'done1\ndone2\n' > "$CC_MAILBOX_DIR/$A.md"
  printf '2\n' > "$CC_MAILBOX_DIR/$A.seen"; printf '2\n' > "$CC_MAILBOX_DIR/$A.acked"
  run mailbox_migrate "$A" "$B"
  [ "$status" -eq 1 ]
  [ "$output" = "0" ]
  [ ! -f "$CC_MAILBOX_DIR/$B.md" ]
}

# ── forward expiry on a reusable (kitty window id) key — W3 P5 ─────────────────────────────────────
# kitty hands a window id out again, so a pointer on one must die when the pane gets a new occupant.

@test "a kitty window id is accepted as the OLD key, and the pointer records the pane's occupant" {
  mailbox_alias_write 249 "$A"
  run mailbox_write_forward 249 "$A"
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$CC_MAILBOX_DIR/249.forward")" = "$A" ]
  [ "$(sed -n 2p "$CC_MAILBOX_DIR/249.forward")" = "occupant=$A" ]
  [ "$(mailbox_forward_of 249)" = "$A" ]
}

@test "a uuid old key still writes the one-line pointer (an iTerm2 pane id is never reused)" {
  mailbox_write_forward "$A" "$B"
  [ "$(cat "$CC_MAILBOX_DIR/$A.forward")" = "$B" ]
}

@test "HIJACK: once another session registers in the reused window, the pointer is not followed" {
  mailbox_alias_write 249 "$A"
  mailbox_write_forward 249 "$A"
  [ "$(mailbox_forward_of 249)" = "$A" ]
  mailbox_alias_write 249 "$C"                    # kitty reused window 249 for an unrelated session
  [ "$(mailbox_forward_of 249)" = "249" ]         # mail for pane 249 stays with pane 249
  CC_MBX_FORWARD_EXPIRY=0 run mailbox_forward_of 249
  [ "$output" = "$A" ]                            # the control: without the expiry it is hijacked
}

@test "a self-close pointer (old occupant → successor) is honoured until the window is reused" {
  mailbox_alias_write 12 "$A"
  mailbox_alias_write 13 "$B"
  run mailbox_write_forward 12 13                 # handoff-fire passes two kitty pane keys
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$CC_MAILBOX_DIR/12.forward")" = "$B" ]   # stored as the successor's SESSION
  [ "$(mailbox_forward_of 12)" = "$B" ]
  mailbox_alias_write 12 "$C"
  [ "$(mailbox_forward_of 12)" = "12" ]
}

@test "a kitty window id as the NEW key with no known session is refused (never a reusable target)" {
  run mailbox_write_forward "$A" 77
  [ "$status" -eq 1 ]
  [ ! -f "$CC_MAILBOX_DIR/$A.forward" ]
}

@test "mailbox_forward_expire removes a pointer that does not serve the pane's new session, and keeps one that does" {
  mailbox_alias_write 249 "$A"; mailbox_write_forward 249 "$A"
  [ "$(mailbox_forward_expire 249 "$A")" = 0 ]
  [ -f "$CC_MAILBOX_DIR/249.forward" ]
  [ "$(mailbox_forward_expire 249 "$C")" = 1 ]
  [ ! -f "$CC_MAILBOX_DIR/249.forward" ]
  grep -qF "was → $A" "$CC_MAILBOX_DIR/249.forward.expired"
  printf '%s\n' "$B" > "$CC_MAILBOX_DIR/$A.forward"
  [ "$(mailbox_forward_expire "$A" "$C")" = 0 ]   # a uuid key is never expired
  [ -f "$CC_MAILBOX_DIR/$A.forward" ]
}
