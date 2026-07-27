#!/usr/bin/env bats
# WAKE FLOOR (v3 R1) — hooks/session-continue.sh must not let a session reach IDLE with no wake path.
#
# WHY THIS EXISTS: the wake MECHANISM was proven end-to-end on 2026-07-26 (armed cc-await-ping →
# cc-notify write → detected in one poll → exit → harness task-completion notification re-invoked the
# model). Nothing ACTUATED it: every cc-await-ping call site in the repo was a doc telling the model
# to arm, or a lint noting it hadn't. Measured: 0 armed watchers across 74 mailboxes / 1,300 unacked
# lines. This suite pins the actuator that converts "the agent should arm" into "the agent cannot
# reach idle unarmed" — and, just as load-bearing, pins the bounds that stop it becoming a loop.
#
# The floor may BLOCK a stop, so the two override paths are tested as hard as the happy path:
# an operator kill-switch always wins, and an exhausted budget degrades to a human-visible
# systemMessage and ALLOWS the stop.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-continue.sh"
  # Fixture $HOME before anything else: the floor builds its arm command from $HOME and falls back to
  # $HOME/.claude for the lib, so an unfixtured suite reads (and could write under) the operator's
  # live home. Assertions below match the command SHAPE, never an absolute prefix, so they hold here.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox";   mkdir -p "$CC_MAILBOX_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # Pin the pane: $_ouid must be the FIXTURE's, never the pane that happens to run the suite.
  U="AAAAAAAA-1111-2222-3333-444444444444"
  export ITERM_SESSION_ID="w0t0p0:$U"
  export CC_WAKE_FLOOR_TTL_S=0        # the TTL damper has its own test; elsewhere it must not mask a fire
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
}

# Stop actuation. $1=session_id  $2=transcript_path. stderr is human diagnostics only.
actuate() { printf '{"cwd":"%s","session_id":"%s","transcript_path":"%s"}' "$CWD" "${1:-sidA}" "${2:-}" | bash "$HOOK" 2>/dev/null; }
blocked() { printf '%s' "$1" | grep -q '"decision":"block"'; }
# a live watcher: fresh heartbeat naming a pid that is actually alive ($$ = this bats process)
arm_watcher()      { printf 'pid=%s\n' "$$" > "$CC_MAILBOX_DIR/$U.watching"; }
arm_watcher_dead() { printf 'pid=999999\n'  > "$CC_MAILBOX_DIR/$U.watching"; }
mail() { printf '2026-07-26T00:00:0%sZ [peer] page %s\n' "${1:-1}" "${1:-1}" >> "$CC_MAILBOX_DIR/$U.md"; }
# transcript whose LAST user message is $1
tx() {
  local p="$BATS_TEST_TMPDIR/tx-$BATS_TEST_NUMBER.jsonl"
  jq -nc --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}' > "$p"
  printf '%s' "$p"
}

# ── THE FLOOR FIRES ───────────────────────────────────────────────────────────────
@test "unarmed session going idle ⇒ BLOCKS and names the exact arm command" {
  run actuate sidA
  blocked "$output"
  # the model must be able to paste this verbatim — an absolute path, this pane's uuid, background-able
  printf '%s' "$output" | jq -r .reason | grep -q "/cc-await-ping $U --timeout"
  printf '%s' "$output" | jq -r .reason | grep -q 'run_in_background=true'
  # and the human must see that it happened
  printf '%s' "$output" | jq -er .systemMessage >/dev/null
}

@test "pending mail is named in the block reason (count, not just 'you have mail')" {
  mail 1; mail 2
  run actuate sidA
  blocked "$output"
  printf '%s' "$output" | jq -r .reason | grep -q '2 message(s) are pending'
}

@test "a STALE heartbeat is not a wake path ⇒ still blocks" {
  arm_watcher
  touch -t 202001010000 "$CC_MAILBOX_DIR/$U.watching"     # older than CC_WATCH_FRESH_S
  run actuate sidA
  blocked "$output"
}

@test "DISCRIMINATOR: a fresh heartbeat naming a DEAD pid is not a wake path ⇒ still blocks" {
  # SIGKILL skips cc-await-ping's EXIT trap, leaving a marker that stays 'fresh' while nothing runs.
  # Freshness alone cannot falsify the claim — this is the case that made the pid field necessary.
  arm_watcher_dead
  run actuate sidA
  blocked "$output"
}

# ── THE FLOOR STANDS DOWN ─────────────────────────────────────────────────────────
@test "an ARMED session is left alone ⇒ no block" {
  arm_watcher
  run actuate sidA
  [ "$status" -eq 0 ]
  ! blocked "$output"
}

@test "an ARMED session clears the attempt budget (a later unarmed episode gets a fresh one)" {
  run actuate sidA                                   # attempt 1 — writes the budget
  [ -f "$CC_MAILBOX_DIR/$U.wakefloor" ]
  arm_watcher
  run actuate sidA                                   # armed ⇒ budget cleared
  [ ! -f "$CC_MAILBOX_DIR/$U.wakefloor" ]
  rm -f "$CC_MAILBOX_DIR/$U.watching"                # watcher exits (self-disarming) …
  run actuate sidA
  blocked "$output"                                  # … and the floor fires again, not exhausted
}

@test "OVERRIDE: an operator kill-switch phrase ⇒ never blocks, warns instead" {
  local t; t="$(tx 'looks good, stop here')"
  run actuate sidA "$t"
  [ "$status" -eq 0 ]
  ! blocked "$output"
  printf '%s' "$output" | jq -r .systemMessage | grep -q 'No inbox wake path armed'
}

@test "after ONE declined attempt with no mail waiting, the floor stops nagging" {
  run actuate sidA; blocked "$output"                # first idle of the session: always try
  run actuate sidA                                   # nothing is waiting ⇒ leave the session alone
  ! blocked "$output"
  [ -z "$output" ]                                   # not even a warning: there is nothing to lose yet
}

@test "BOUND: budget exhausted ⇒ allows the stop with a human-visible warning, never a loop" {
  # The cap is only reachable while mail is actually PENDING — that is the only state in which the
  # floor keeps pressing. Without mail it stands down after one attempt (test above).
  mail 1
  run actuate sidA; blocked "$output"                # 1
  run actuate sidA; blocked "$output"                # 2 (CC_WAKE_FLOOR_MAX default 2)
  run actuate sidA                                   # 3 — must give up, loudly
  [ "$status" -eq 0 ]
  ! blocked "$output"
  printf '%s' "$output" | jq -r .systemMessage | grep -q 'cc-await-ping'
  printf '%s' "$output" | jq -r .systemMessage | grep -q 'waiting and NO wake path'
}

@test "BOUND: the TTL damper stops a burst of short turns re-blocking every one" {
  CC_WAKE_FLOOR_TTL_S=600 run actuate sidA
  blocked "$output"
  CC_WAKE_FLOOR_TTL_S=600 run actuate sidA           # immediately again, inside the TTL
  ! blocked "$output"
}

@test "a NEW session in the same pane gets a fresh budget (no inherited exhaustion)" {
  mail 1
  run actuate sidA; run actuate sidA                 # spend sidA's whole budget (mail pending)
  run actuate sidA; ! blocked "$output"              # sidA is now exhausted
  run actuate sidB                                   # a successor in the same pane must not inherit it
  blocked "$output"
}

@test "CC_WAKE_FLOOR=0 disables the floor entirely" {
  CC_WAKE_FLOOR=0 run actuate sidA
  [ "$status" -eq 0 ]
  ! blocked "$output"
}

@test "a pane with no inbox identity is never blocked" {
  ITERM_SESSION_ID="" run actuate sidA
  [ "$status" -eq 0 ]
  ! blocked "$output"
}

@test "the floor never pre-empts an armed continuation sentinel" {
  ( cd "$CWD" && CLAUDE_CODE_SESSION_ID=sidA bash "$HOOK" set "finish the thing" >/dev/null )
  run actuate sidA
  blocked "$output"
  printf '%s' "$output" | jq -r .reason | grep -q 'Loose ends remain'   # the SENTINEL's reason, not the floor's
}

# ── RED-PROOF — the control is the REAL pre-fix artifact, not an approximation ─────
# A suite that cannot fail proves nothing. Replay hooks/ exactly as it stands on origin/main (the
# tree this change is written against) and require the two core assertions to FAIL there.
@test "RED-PROOF: the pre-fix hooks/ from origin/main does NOT block an unarmed idle session" {
  local old="$BATS_TEST_TMPDIR/pre"; mkdir -p "$old"
  git -C "$REPO" archive origin/main hooks | tar -x -C "$old" || skip "origin/main unavailable"
  [ -f "$old/hooks/session-continue.sh" ]
  # sanity: the control must genuinely predate the change
  ! grep -q 'WAKE FLOOR' "$old/hooks/session-continue.sh"
  ! grep -q 'mailbox_wake_armed' "$old/hooks/lib/mailbox-pending.sh"
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' | bash '$old/hooks/session-continue.sh' 2>/dev/null"
  [ "$status" -eq 0 ]
  ! blocked "$output"                                # RED: the defect this change closes
}
