#!/usr/bin/env bats
# EMIT-THEN-COMMIT (backlog 6a178497df5f). A hook's stdout is its delivery only if the harness reads
# it, and a hook reaped at its timeout has its stdout discarded. The drain used to advance `.seen`
# BEFORE emitting, so a reap in between left the window in (acked, seen] and the next Stop's
# mailbox_promote_acked (acked=seen) made it CONSUMED — nobody surfaced it again.
#
# WHAT IS PINNED: a drain killed inside the take→emit window, or one whose emit write fails, leaves
# the window PENDING and the next boundary delivers it; a live drain's claim makes a concurrent drain
# deliver nothing; an older lib without the primitives keeps the take path; the session-continue Stop
# fold obeys the same order. Every red-proof runs the SAME scenario against the pinned pre-fix tree.
#
# Harness rules (tests/mailbox-drain.bats): `|| false` on every bare [[ ]] / negated assertion;
# assert the SPECIFIC string.

# PINNED TO A SHA, never a moving ref (tests/mailbox-drain.bats records why): the trunk tip this fix
# was cut from.
CC_ETC_PREFIX_SHA="${CC_ETC_PREFIX_SHA:-12c60021e}"

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DRAIN="$REPO/hooks/mailbox-drain.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"; mkdir -p "$CC_MAILBOX_DIR"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  UUID="AAAAAAAA-1111-2222-3333-444444444444"
  export ITERM_SESSION_ID="w0t0p0:$UUID"
  MBOX="$CC_MAILBOX_DIR/$UUID.md"
  SEEN="$CC_MAILBOX_DIR/$UUID.seen"
}

seed() { printf '%s\n' "$@" > "$MBOX"; }
seen_val() { if [ -s "$SEEN" ]; then tr -dc '0-9' < "$SEEN"; else echo 0; fi; }
ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

# A hook tree the test controls: the drain + its lib, and a bin/ the drain resolves cc-custody from
# ("$_scd/../bin/cc-custody" is its FIRST candidate).
tree_now() { # $1 = root
  mkdir -p "$1/hooks/lib" "$1/bin"
  cp "$REPO/hooks/mailbox-drain.sh" "$REPO/hooks/session-continue.sh" "$1/hooks/"
  cp "$REPO"/hooks/lib/*.sh "$1/hooks/lib/"
}
tree_prefix() { # $1 = root — the pinned pre-fix tree, or skip
  mkdir -p "$1"
  git -C "$REPO" archive "$CC_ETC_PREFIX_SHA" hooks | tar -x -C "$1" \
    || skip "pre-fix tree $CC_ETC_PREFIX_SHA unavailable"
  mkdir -p "$1/bin"
  [ -f "$1/hooks/mailbox-drain.sh" ] || false
  ! grep -q 'mailbox_commit_seen' "$1/hooks/lib/mailbox-pending.sh" || false   # truly pre-fix
}

# Run a prompt drain from <root> and SIGKILL it while it sits INSIDE the take→emit window: the stub
# cc-custody (reached only on a HANDOFF-PING body, after the take and before the emit) records that it
# was reached, then blocks — standing in for any slow step the harness's 5 s timeout lands on.
kill_mid_drain() { # $1 = root
  local root="$1" mk="$BATS_TEST_TMPDIR/stub.reached" hp sp i
  rm -f "$mk"
  cat > "$root/bin/cc-custody" <<STUB
#!/bin/bash
echo \$\$ > "$mk.tmp" && mv "$mk.tmp" "$mk"
sleep 30
STUB
  chmod +x "$root/bin/cc-custody"
  printf '{"cwd":"%s"}' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/stdin.json"
  bash "$root/hooks/mailbox-drain.sh" prompt < "$BATS_TEST_TMPDIR/stdin.json" \
    > "$BATS_TEST_TMPDIR/killed.out" 2>/dev/null &
  hp=$!
  for i in $(seq 1 200); do [ -f "$mk" ] && break; sleep 0.05; done
  if [ ! -f "$mk" ]; then kill -KILL "$hp" 2>/dev/null || true; return 1; fi
  kill -KILL "$hp" 2>/dev/null || true          # the harness reaping the hook at its timeout
  wait "$hp" 2>/dev/null || true
  sp="$(cat "$mk")"; kill -KILL "$sp" 2>/dev/null || true
}

PING="2026-09-10T10:00:00+0000 [peer] HANDOFF-PING wave42: landed abc123, self-closing"

@test "reaped inside take→emit: the window stays PENDING and the next boundary delivers it" {
  local root="$BATS_TEST_TMPDIR/now"; tree_now "$root"
  seed "$PING"
  kill_mid_drain "$root"
  [ ! -s "$BATS_TEST_TMPDIR/killed.out" ]         # the reaped drain emitted nothing
  [ "$(seen_val)" -eq 0 ]                          # …and so it committed nothing
  # the dead drain's claim is reclaimed at once (its pid is gone), and the mail arrives
  CC_DRAIN_CUSTODY_RETURN=0 run bash -c 'echo "{}" | "$0" prompt' "$root/hooks/mailbox-drain.sh"
  [ "$status" -eq 0 ]
  ctx_of "$output" | grep -qF 'HANDOFF-PING wave42' || false
  [ "$(seen_val)" -eq 1 ]
}

@test "RED-PROOF: the pre-fix drain, reaped in the same window, loses the ping for good" {
  local root="$BATS_TEST_TMPDIR/pre"; tree_prefix "$root"
  seed "$PING"
  kill_mid_drain "$root"
  [ ! -s "$BATS_TEST_TMPDIR/killed.out" ]
  [ "$(seen_val)" -eq 1 ]                          # RED: cursor advanced over a body nobody got
  CC_DRAIN_CUSTODY_RETURN=0 run bash -c 'echo "{}" | "$0" prompt' "$root/hooks/mailbox-drain.sh"
  ! ctx_of "$output" | grep -qF 'HANDOFF-PING wave42' || false   # the next boundary shows nothing
  # and the next Stop fold makes it CONSUMED — no reader will surface it again
  ( . "$root/hooks/lib/mailbox-pending.sh"; mailbox_promote_acked "$UUID"
    [ "$(mailbox_unacked_count "$UUID")" -eq 0 ] ) || false
}

@test "a failed emit write commits nothing (stdout closed ⇒ the window stays pending)" {
  seed "2026-09-10T10:00:00+0000 [peer] please look at X"
  run bash -c 'echo "{}" | "$0" prompt >&-' "$DRAIN"
  [ "$status" -eq 0 ]
  [ "$(seen_val)" -eq 0 ]
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  ctx_of "$output" | grep -qF 'please look at X' || false
  [ "$(seen_val)" -eq 1 ]
}

@test "RED-PROOF: the pre-fix drain advances the cursor even when its emit write fails" {
  local root="$BATS_TEST_TMPDIR/pre"; tree_prefix "$root"
  seed "2026-09-10T10:00:00+0000 [peer] please look at X"
  run bash -c 'echo "{}" | "$0" prompt >&-' "$root/hooks/mailbox-drain.sh"
  [ "$(seen_val)" -eq 1 ]                          # RED: marked delivered, delivered to nobody
}

@test "a LIVE drain's claim makes a concurrent drain deliver nothing and move no cursor" {
  seed "2026-09-10T10:00:00+0000 [peer] one window, one delivery"
  mkdir "$CC_MAILBOX_DIR/.$UUID.drain.lock"
  echo "$$" > "$CC_MAILBOX_DIR/.$UUID.drain.lock/owner"      # the bats process: alive
  run bash -c 'echo "{}" | "$0" post-tool' "$DRAIN"
  [ "$status" -eq 0 ]
  ! ctx_of "$output" | grep -qF 'one window, one delivery' || false
  [ "$(seen_val)" -eq 0 ]
  [ -d "$CC_MAILBOX_DIR/.$UUID.drain.lock" ]                  # a live holder's claim is never stolen
}

@test "CONTROL: the same claim held by a DEAD pid is reclaimed and the window delivered" {
  seed "2026-09-10T10:00:00+0000 [peer] one window, one delivery"
  local dead; bash -c 'exit 0' & dead=$!; wait "$dead" || true
  mkdir "$CC_MAILBOX_DIR/.$UUID.drain.lock"
  echo "$dead" > "$CC_MAILBOX_DIR/.$UUID.drain.lock/owner"
  run bash -c 'echo "{}" | "$0" prompt' "$DRAIN"
  ctx_of "$output" | grep -qF 'one window, one delivery' || false
  [ "$(seen_val)" -eq 1 ]
  [ ! -d "$CC_MAILBOX_DIR/.$UUID.drain.lock" ]                # released on exit
}

@test "capped post-tool drain: the remainder note counts past OUR window, not the uncommitted cursor" {
  local i; : > "$MBOX"
  for i in 1 2 3 4 5; do printf '2026-09-10T10:00:0%s+0000 [peer] m%s\n' "$i" "$i" >> "$MBOX"; done
  CC_POSTTOOL_DRAIN_MAX_LINES=2 CC_POSTTOOL_DRAIN_MIN_S=0 run bash -c 'echo "{}" | "$0" post-tool' "$DRAIN"
  ctx_of "$output" | grep -qF '(+3 more pending' || false
  [ "$(seen_val)" -eq 2 ]
}

@test "LIB SKEW: an older lib without the primitives keeps the take path (delivers + advances)" {
  local root="$BATS_TEST_TMPDIR/skew"; tree_now "$root"
  printf '\nunset -f mailbox_commit_seen\n' >> "$root/hooks/lib/mailbox-pending.sh"
  seed "2026-09-10T10:00:00+0000 [peer] old lib, same delivery"
  run bash -c 'echo "{}" | "$0" prompt' "$root/hooks/mailbox-drain.sh"
  ctx_of "$output" | grep -qF 'old lib, same delivery' || false
  [ "$(seen_val)" -eq 1 ]
  [ ! -d "$CC_MAILBOX_DIR/.$UUID.drain.lock" ]                # the take path never claims
}

# ── the session-continue Stop fold ────────────────────────────────────────────────────────────────
# Env mirrors tests/session-continue.bats (its setup records why each seam is pinned).
sc_env() {
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/continue-idl.jsonl"
  export CONTINUE_LOG="$BATS_TEST_TMPDIR/continue.log"
  export CC_WAKE_FLOOR=0
  SCWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$SCWD"
  TX="$BATS_TEST_TMPDIR/tx.jsonl"
  jq -nc '{type:"user",message:{content:[{type:"text",text:"please keep going"}]}}' > "$TX"
}
sc_arm() { ( cd "$SCWD" && CLAUDE_CODE_SESSION_ID=sidA bash "$1" set "finish the thing" >/dev/null ); }
sc_stop() { # $1 = hook, $2 = extra redirection ("closed" ⇒ stdout closed)
  local j; j="$(printf '{"cwd":"%s","session_id":"sidA","transcript_path":"%s"}' "$SCWD" "$TX")"
  if [ "${2:-}" = closed ]; then printf '%s' "$j" | bash "$1" 2>/dev/null >&-
  else printf '%s' "$j" | bash "$1" 2>/dev/null; fi
}

@test "Stop fold: a failed block write commits nothing; the next Stop delivers the mail" {
  sc_env
  seed "2026-09-10T10:00:00+0000 [peer] stop-fold mail"
  sc_arm "$REPO/hooks/session-continue.sh"
  run sc_stop "$REPO/hooks/session-continue.sh" closed
  [ "$(seen_val)" -eq 0 ]
  run sc_stop "$REPO/hooks/session-continue.sh"
  printf '%s' "$output" | grep -q '"decision":"block"' || false
  printf '%s' "$output" | jq -r '.reason' | grep -qF 'stop-fold mail' || false
  [ "$(seen_val)" -eq 1 ]
  [ ! -d "$CC_MAILBOX_DIR/.$UUID.drain.lock" ]
}

@test "RED-PROOF: the pre-fix Stop fold advances the cursor even when its block write fails" {
  sc_env
  local root="$BATS_TEST_TMPDIR/pre"; tree_prefix "$root"
  seed "2026-09-10T10:00:00+0000 [peer] stop-fold mail"
  sc_arm "$root/hooks/session-continue.sh"
  run sc_stop "$root/hooks/session-continue.sh" closed
  [ "$(seen_val)" -eq 1 ]                          # RED: taken, never shown
}
