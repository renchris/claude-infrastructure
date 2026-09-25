#!/usr/bin/env bats
# A BACKGROUNDED session keeps its pane address (hooks/session-register.sh + hooks/mailbox-drain.sh).
#
# THE INCIDENT (2026-09-25, reso wt-pool-2, third occurrence of "a recovered session has no address").
# Claude Code 2.1.280 can BACKGROUND a running session: the TUI in kitty window 405 (pid 76287, sid
# e44c8e8c) logged "Backgrounding after the current tool finishes…" and a `continued-in` record, and a
# daemon it spawned (`claude daemon run --origin transient --spawned-by {"pid":76287}`) started
#   claude --session-id bb4e00d0 --fork-session --resume …/e44c8e8c.jsonl --reply-on-resume …
# with CLAUDE_CODE_SESSION_KIND=bg and WITHOUT KITTY_WINDOW_ID / ITERM_SESSION_ID (KITTY_PID and
# KITTY_LISTEN_ON survived). Window 405's TUI went on DISPLAYING bb4e00d0, so the pane is bb4e00d0's —
# but session-register had no address, wrote no row, and the row for 405 kept naming the dead-to-work
# sid e44c8e8c. `handoff-fire.sh --recycle` then refused ("needs $ITERM_SESSION_ID, $KITTY_WINDOW_ID
# … or --session-id") and mailbox-drain exited before reading one line, so --notify-back was deaf.
#
# The fixture reproduces the process SHAPE, not the binary: an outer fake `claude` (the pane's client)
# owns the row, and spawns an inner fake `claude` whose argv carries the fork flags exactly as the
# daemon passes them and whose env has no pane variable at all. `ln -s /bin/bash …/claude` makes both
# tiers answer `ps -o comm=` with `claude`, which is what the hook's ancestor walk keys on (see
# tests/session-registry.bats `nested_register` for why the symlink and the trailing `:` matter).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  REG="$REPO/hooks/session-register.sh"
  DRAIN="$REPO/hooks/mailbox-drain.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  # The ratchet below only GREPS lr-fire-resume.sh, but the lint cannot tell a grep from a run.
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export SESSION_REGISTER_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export SESSION_REGISTER_RECLAIM_WAIT=1
  export CC_BACKLOG_BIN=/usr/bin/false
  mkdir -p "$CC_REGISTRY_DIR"
  PANE=405
  PARENT="e44c8e8c-59a9-49eb-9a84-4a781077b6ea"
  CHILD="bb4e00d0-47a8-4f4a-b42d-1aef86ae49e6"
  ENVF="$BATS_TEST_TMPDIR/session-env/sessionstart-hook-0.sh"
  mkdir -p "$(dirname "$ENVF")"
}

# bg_fork <kind> [row-sid] — run the hook as the daemon-hosted fork of the pane's session.
#   kind     the CLAUDE_CODE_SESSION_KIND the inner tier carries ('' = unset)
#   row-sid  the session the pane's row names (default: the fork's parent)
# Leaves the inner (fork) pid in $BATS_TEST_TMPDIR/inner.pid and the outer (client) pid in outer.pid.
bg_fork() {
  local kind="$1" rowsid="${2:-$PARENT}" fake="$BATS_TEST_TMPDIR/fake"
  mkdir -p "$fake"; ln -sf /bin/bash "$fake/claude"
  cat > "$BATS_TEST_TMPDIR/outer.sh" <<'OUT'
echo "$$" > "$BF_DIR/outer.pid"
printf '{"paneUUID":"%s","name":"wt-pool-2-405","cwd":"/tmp","account":"claude-quaternary","pid":%s,"startedAt":1,"session_id":"%s","surface":"pane"}' \
  "$BF_PANE" "$$" "$BF_ROWSID" > "$CC_REGISTRY_DIR/$BF_PANE.json"
env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u CC_PANE_ID -u CLAUDE_CODE_SESSION_KIND \
    ${BF_KIND:+CLAUDE_CODE_SESSION_KIND=$BF_KIND} KITTY_PID=73832 CLAUDE_ENV_FILE="$BF_ENVF" \
  "$BF_FAKE/claude" "$BF_DIR/inner.sh" --session-id "$BF_CHILD" --fork-session \
    --resume "/Users/x/.claude-quaternary/projects/-wt/$BF_PARENT.jsonl" --reply-on-resume
:
OUT
  cat > "$BATS_TEST_TMPDIR/inner.sh" <<'IN'
echo "$$" > "$BF_DIR/inner.pid"
printf '{"cwd":"/tmp/wt-pool-2","session_id":"%s","source":"resume","hook_event_name":"SessionStart"}' "$BF_CHILD" \
  | bash "$BF_HOOK"
:
IN
  BF_DIR="$BATS_TEST_TMPDIR" BF_PANE="$PANE" BF_ROWSID="$rowsid" BF_KIND="$kind" BF_ENVF="$ENVF" \
  BF_FAKE="$fake" BF_CHILD="$CHILD" BF_PARENT="$PARENT" BF_HOOK="$REG" \
    env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u CC_PANE_ID "$fake/claude" "$BATS_TEST_TMPDIR/outer.sh"
}

@test "bg fork: the backgrounded session re-registers the pane under its NEW sid and pid" {
  bg_fork bg
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$PANE.json"
  [ "$output" = "$CHILD" ] || { echo "row still names [$output] — the fork never registered"; false; }
  run jq -r '.pid' "$CC_REGISTRY_DIR/$PANE.json"
  [ "$output" = "$(cat "$BATS_TEST_TMPDIR/inner.pid")" ] || { echo "row pid [$output] is not the fork's"; false; }
  run jq -r '.paneUUID' "$CC_REGISTRY_DIR/$PANE.json"
  [ "$output" = "$PANE" ]
}

@test "bg fork: the pane address is exported through CLAUDE_ENV_FILE for every later Bash call" {
  bg_fork bg
  [ -s "$ENVF" ] || { echo "no env file written"; false; }
  run env -i /bin/bash -c ". '$ENVF'; printf '%s|%s' \"\${ITERM_SESSION_ID:-}\" \"\${KITTY_WINDOW_ID:-}\""
  [ "$status" -eq 0 ]
  [ "$output" = "w0t0p0:$PANE|$PANE" ] || { echo "exported [$output]"; false; }
}

@test "bg fork: the adoption is journalled (a silent re-key reads as an inert mechanism)" {
  bg_fork bg
  run grep -F '"disposition":"adopted"' "$SESSION_REGISTER_IDL"
  [ "$status" -eq 0 ]
  run grep -F "$PARENT" "$SESSION_REGISTER_IDL"
  [ "$status" -eq 0 ]
}

# ── WHAT IT STILL REFUSES. A widening with only now-passes tests cannot show its bound. ─────────────

@test "control: a fork WITHOUT CLAUDE_CODE_SESSION_KIND=bg does not take the pane (a headless probe is not a continuation)" {
  bg_fork ""
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$PANE.json"
  [ "$output" = "$PARENT" ]
  [ ! -s "$ENVF" ]
}

@test "control: a bg fork whose parent no row names registers nothing and exports nothing" {
  bg_fork bg "11111111-2222-3333-4444-555555555555"
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$PANE.json"
  [ "$output" = "11111111-2222-3333-4444-555555555555" ]
  run bash -c "ls '$CC_REGISTRY_DIR' | wc -l | tr -d ' '"
  [ "$output" = "1" ]
  [ ! -s "$ENVF" ]
}

@test "control: an ambiguous parent (two rows name it) is refused, never guessed" {
  printf '{"paneUUID":"406","name":"dup","cwd":"/tmp","account":"x","pid":1,"startedAt":1,"session_id":"%s"}' \
    "$PARENT" > "$CC_REGISTRY_DIR/406.json"
  bg_fork bg
  run jq -r '.session_id' "$CC_REGISTRY_DIR/$PANE.json"
  [ "$output" = "$PARENT" ]
  run jq -r '.session_id' "$CC_REGISTRY_DIR/406.json"
  [ "$output" = "$PARENT" ]
}

# ── THE DRAIN: an addressed session must also be able to READ what it is sent ─────────────────────
# $HOME is already fixtured in setup(); three of the drain's seams default under it.
drain_home() {
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbx"
  mkdir -p "$CC_MAILBOX_DIR"
}

@test "drain fixture: WITH a pane env the same box is read (proves the fixture can say yes)" {
  drain_home
  printf '2026-09-25T10:00:00+0000 [peer] DONE — wave landed at abc1234\n' > "$CC_MAILBOX_DIR/$PANE.md"
  run bash -c "printf '{\"session_id\":\"$CHILD\",\"hook_event_name\":\"UserPromptSubmit\"}' \
    | env -u KITTY_WINDOW_ID -u CC_PANE_ID ITERM_SESSION_ID=w0t0p0:$PANE bash '$DRAIN' prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wave landed at abc1234"* ]] || { echo "drain output: [$output]"; false; }
}

@test "drain: a session with no pane env reads its pane's inbox via its own registry row" {
  drain_home
  printf '{"paneUUID":"%s","name":"n","cwd":"/tmp","account":"x","pid":%s,"startedAt":1,"session_id":"%s"}' \
    "$PANE" "$$" "$CHILD" > "$CC_REGISTRY_DIR/$PANE.json"
  printf '2026-09-25T10:00:00+0000 [peer] DONE — wave landed at abc1234\n' > "$CC_MAILBOX_DIR/$PANE.md"
  run bash -c "printf '{\"session_id\":\"$CHILD\",\"hook_event_name\":\"UserPromptSubmit\"}' \
    | env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u CC_PANE_ID CLAUDE_CODE_SESSION_KIND=bg bash '$DRAIN' prompt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"wave landed at abc1234"* ]] || { echo "drain output: [$output]"; false; }
}

@test "drain control: with no pane env and NO row naming this session, the drain stays silent" {
  drain_home
  printf '2026-09-25T10:00:00+0000 [peer] not yours\n' > "$CC_MAILBOX_DIR/$PANE.md"
  run bash -c "printf '{\"session_id\":\"$CHILD\",\"hook_event_name\":\"UserPromptSubmit\"}' \
    | env -u ITERM_SESSION_ID -u KITTY_WINDOW_ID -u CC_PANE_ID CLAUDE_CODE_SESSION_KIND=bg bash '$DRAIN' prompt"
  [ "$status" -eq 0 ]
  [[ "$output" != *"not yours"* ]] || { echo "drained a stranger's box: [$output]"; false; }
}

# ── THE LIMIT-RECOVER RELAUNCH IS NOT THIS DEFECT — and must never become it ──────────────────────
# The report named lr-fire-resume. Measured on the incident box, its relaunch (pid 76287) carried
# KITTY_WINDOW_ID=405 and ITERM_SESSION_ID=w0t0p0:405 and held a correct row; the address was lost one
# hop later, in the daemon's fork. The relaunch keeps the pane address only because its expect spawn
# line strips a fixed `env -u` list that does not name any address variable. This pins that: a future
# addition of one of them to the list would recreate the bg defect on every recovered session.
@test "ratchet: lr-fire-resume's expect spawn never strips a pane-address variable" {
  local f="$REPO/scripts/limit-recover/lr-fire-resume.sh"
  run grep -c 'spawn -noecho env ' "$f"
  [ "$status" -eq 0 ]
  [ "$output" -ge 2 ] || { echo "spawn lines not found (count [$output]) — the ratchet lost its subject"; false; }
  run grep -E 'spawn -noecho env .*-u (KITTY_WINDOW_ID|ITERM_SESSION_ID|CC_PANE_ID|KITTY_PID|KITTY_LISTEN_ON)( |$)' "$f"
  [ "$status" -eq 1 ] || { echo "a spawn line strips an address: $output"; false; }
}
