#!/usr/bin/env bats
# cc-wake-headless — THE WAKE PATH FOR A PANE-LESS SESSION (backlog 8ad4b02602dc; gap 2 of
# docs/research/scaling-bottlenecks-2026-08-09/03-headless-substrate.md §2.4 B).
#
# THE CLAIM UNDER TEST, and why it needs an end-to-end case rather than a unit one. Until
# 2026-08-13 `cc-pane-headless` spawned every agent `</dev/null` — stdin closed at birth — so a
# resident `claude -p --input-format stream-json` session had no wake path at all. The fleet's
# existing primitive `cc-await-ping` wakes by EXITING, and the harness's task-completion
# notification is what synthesises the turn; in stream-json NOTHING CONSUMES THAT EXIT, so an armed
# watcher fires perfectly and changes nothing. The wake must therefore terminate in a WRITE THAT
# THE AGENT PROCESS ACTUALLY READS — which is why W1 asserts on the agent's own output, not on the
# waker's exit code. A tool that returns 0 having written into a pipe nobody reads is precisely the
# failure this replaces.
#
# Every assertion is `[ ]` / `|| false` — `[[ ]]` and `(( ))` are errexit-EXEMPT in bats and would
# be silently DEAD anywhere but a body's last line.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DRV="$REPO/bin/cc-pane-headless"
  WAKE="$REPO/bin/cc-wake-headless"
  export CC_PANE_HOME="$BATS_TEST_TMPDIR/panes"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"; mkdir -p "$CC_MAILBOX_DIR"
  export CC_PANE_KILL_WAIT_S=3
  export CC_PANE_HOLD_POLL_S=1
  # Poison every terminal entrypoint: a pane-less driver that reaches for one is a design
  # violation, and a loud attributable failure beats a silent one.
  local pz="$BATS_TEST_TMPDIR/poison"; mkdir -p "$pz"
  local t
  for t in it2 osascript tmux; do
    printf '#!/bin/bash\necho "HEADLESS TOUCHED A TERMINAL: %s $*" >&2\nexit 66\n' "$t" > "$pz/$t"
    chmod +x "$pz/$t"
  done
  export PATH="$pz:$PATH"
}

teardown() {
  local d p h
  for d in "$CC_PANE_HOME"/hdl-* "$CC_PANE_HOME"/dead-*; do
    [ -d "$d" ] || continue
    p="$(sed -n 's/^pid=//p'    "$d/meta" 2>/dev/null | head -1)"
    h="$(sed -n 's/^holder=//p' "$d/meta" 2>/dev/null | head -1)"
    [ -n "$p" ] && kill -9 "$p" 2>/dev/null
    [ -n "$h" ] && kill -9 "$h" 2>/dev/null
  done
  return 0
}

# An agent that ECHOES every stdin line it receives into its own out.log. This is the oracle for
# "the write was READ", which is the only thing a wake means.
_spawn_reader() {
  "$DRV" spawn --cwd "$BATS_TEST_TMPDIR" "$@" -- \
    /bin/bash -c 'while IFS= read -r l; do printf "GOT %s\n" "$l"; done; printf "EOF\n"'
}

_meta() { sed -n "s/^$2=//p" "$CC_PANE_HOME/$1/meta" 2>/dev/null | head -1; }

# A LIVE agent that has NO stdin endpoint. It must not READ stdin: with `--stdin null` a reader
# hits EOF instantly and the driver correctly refuses the spawn, which is a different case (W8's
# control) from "live, but unwakeable".
_spawn_deaf() { "$DRV" spawn --cwd "$BATS_TEST_TMPDIR" --stdin null -- /bin/sleep 30; }

# Poll rather than sleep a fixed amount: the read is a scheduling event, not a wall-clock one.
_await_log() { # $1=id $2=pattern $3=max-tenths
  local i=0
  while [ "$i" -lt "${3:-40}" ]; do
    grep -q "$2" "$CC_PANE_HOME/$1/out.log" 2>/dev/null && return 0
    sleep 0.1; i=$(( i + 1 ))
  done
  return 1
}

# ── W1: the whole point — a wake reaches the RUNNING PROCESS ────────────────────────────────────

@test "W1: a wake is READ by the live agent — the stream-json line lands in its own output" {
  local id; id="$(_spawn_reader)"
  [ -n "$id" ]
  run "$WAKE" "$id"
  [ "$status" -eq 0 ]
  run _await_log "$id" '^GOT {'
  [ "$status" -eq 0 ]
  # …and it is the WAKE's line, not an artefact: the payload names the agent's own mailbox path.
  run grep -q "$CC_MAILBOX_DIR/$id.md" "$CC_PANE_HOME/$id/out.log"
  [ "$status" -eq 0 ]
  "$DRV" close "$id"
}

@test "W2: the delivered line is VALID stream-json with type=user — not merely non-empty text" {
  # A wake the harness cannot parse is a wake that does not happen. Parsed with a real JSON reader,
  # never a grep for a brace.
  local id; id="$(_spawn_reader)"
  run "$WAKE" --text 'probe-payload-W2' "$id"
  [ "$status" -eq 0 ]
  run _await_log "$id" '^GOT {'
  [ "$status" -eq 0 ]
  run python3 -c '
import json,sys
line=[l[4:] for l in open(sys.argv[1]) if l.startswith("GOT ")][0]
d=json.loads(line)
assert d["type"]=="user", d
assert d["message"]["role"]=="user", d
assert d["message"]["content"][0]["text"]=="probe-payload-W2", d
print("PARSED")
' "$CC_PANE_HOME/$id/out.log"
  [ "$status" -eq 0 ]
  [ "$output" = "PARSED" ]
  "$DRV" close "$id"
}

@test "W2b: the jq-absent degrade emits the SAME parseable line — the escape path is not a lie" {
  # The fallback hand-rolls JSON escaping; it is exercised only when jq is missing, i.e. never on
  # this box, which is exactly how it would rot. Text chosen to hit both escapes it performs.
  local id; id="$(_spawn_reader)"
  local pz="$BATS_TEST_TMPDIR/nojq"; mkdir -p "$pz"
  printf '#!/bin/bash\nexit 127\n' > "$pz/jq"; chmod -x "$pz/jq"   # present but NOT executable ⇒ command -v fails
  run env PATH="$pz:$PATH" "$WAKE" --text 'quote " and backslash \ here' "$id"
  [ "$status" -eq 0 ]
  run _await_log "$id" '^GOT {'
  [ "$status" -eq 0 ]
  run python3 -c '
import json,sys
line=[l[4:] for l in open(sys.argv[1]) if l.startswith("GOT ")][0]
d=json.loads(line)
assert d["message"]["content"][0]["text"] == "quote \" and backslash \\ here", d
print("PARSED")
' "$CC_PANE_HOME/$id/out.log"
  [ "$status" -eq 0 ]
  [ "$output" = "PARSED" ]
  "$DRV" close "$id"
}

# ── W3: damping — 150 agents make a broadcast an inference-budget event ─────────────────────────

@test "W3: a second wake inside the damp window is rc 2 and delivers NOTHING; --force overrides" {
  local id; id="$(_spawn_reader)"
  run "$WAKE" "$id"
  [ "$status" -eq 0 ]
  run _await_log "$id" '^GOT {'
  [ "$status" -eq 0 ]
  local before; before="$(grep -c '^GOT ' "$CC_PANE_HOME/$id/out.log")"
  run "$WAKE" "$id"
  [ "$status" -eq 2 ]
  sleep 0.3
  [ "$(grep -c '^GOT ' "$CC_PANE_HOME/$id/out.log")" -eq "$before" ]
  # POSITIVE CONTROL in the same test: the damper is suppressing a wake that WOULD have landed.
  run "$WAKE" --force "$id"
  [ "$status" -eq 0 ]
  local i=0
  while [ "$i" -lt 40 ]; do
    [ "$(grep -c '^GOT ' "$CC_PANE_HOME/$id/out.log")" -gt "$before" ] && break
    sleep 0.1; i=$(( i + 1 ))
  done
  [ "$(grep -c '^GOT ' "$CC_PANE_HOME/$id/out.log")" -gt "$before" ]
  "$DRV" close "$id"
}

@test "W3b: the damp stamp is written only by a wake that HAPPENED" {
  # A stamp written before the write would let a refused attempt damp the retry that could have
  # worked — a damper suppressing on the strength of an event that never occurred.
  local id; id="$(_spawn_deaf)"
  [ ! -f "$CC_PANE_HOME/$id/.wake" ]
  run "$WAKE" "$id"
  [ "$status" -eq 4 ]
  [ ! -f "$CC_PANE_HOME/$id/.wake" ]
  "$DRV" close "$id" || true
}

# ── W4/W5: every refusal names a DIFFERENT thing that was checked ───────────────────────────────

@test "W4: a DEAD agent is rc 1 and nothing is written — a corpse is never reported woken" {
  local id; id="$(_spawn_reader)"
  local pid; pid="$(_meta "$id" pid)"
  kill -9 "$pid" 2>/dev/null
  sleep 0.3
  run "$WAKE" "$id"
  [ "$status" -eq 1 ]
  run grep -q "NOT live" <<< "$output"
  [ "$status" -eq 0 ]
}

@test "W5: an agent with NO stdin endpoint is rc 4 — distinct from dead, and it says which" {
  # This is the laundering case: an agent spawned before the FIFO existed (or whose mkfifo failed)
  # cannot be woken AT ALL, and reporting that as a generic failure leaves the caller unable to act.
  local id; id="$(_spawn_deaf)"
  [ -n "$id" ]
  [ -z "$(_meta "$id" fifo)" ]
  run "$WAKE" "$id"
  [ "$status" -eq 4 ]
  run grep -q "NO stdin endpoint" <<< "$output"
  [ "$status" -eq 0 ]
  # CONTROL: the same spawn WITH a fifo is wakeable, so rc 4 is about the endpoint and not the fixture.
  local id2; id2="$(_spawn_reader)"
  run "$WAKE" "$id2"
  [ "$status" -eq 0 ]
  "$DRV" close "$id" || true
  "$DRV" close "$id2"
}

@test "W6: a write that would BLOCK is bounded and reported rc 5, never left hanging" {
  # An agent that has stopped draining its stdin. One small line fits the pipe buffer and would
  # succeed, so the payload is sized past it — this asserts the BOUND, which at 150 sessions is what
  # stops one wedged agent hanging its notifier.
  local id
  id="$("$DRV" spawn --cwd "$BATS_TEST_TMPDIR" -- /bin/sleep 30)"   # holds the fifo open, reads nothing
  [ -n "$id" ]
  local big; big="$(python3 -c 'print("x"*300000)')"
  run env CC_WAKE_WRITE_TIMEOUT_S=2 "$WAKE" --text "$big" "$id"
  [ "$status" -eq 5 ]
  run grep -q "BLOCKED" <<< "$output"
  [ "$status" -eq 0 ]
  [ ! -f "$CC_PANE_HOME/$id/.wake" ]      # a blocked write must not damp the retry
  "$DRV" close "$id"
}

# ── W7: addressing — the sid a caller DECLARED is a second address ──────────────────────────────

@test "W7: --resolve answers by hdl-id and by the DECLARED session id, and refuses an unknown one" {
  local sid="deadbeef-0000-1111-2222-333344445555"
  # `bash -c` keeps the process alive AND puts the flag in argv where the spawner scans it;
  # `sleep 30 --session-id X` would just exit with a usage error.
  local id; id="$("$DRV" spawn --cwd "$BATS_TEST_TMPDIR" -- /bin/bash -c 'sleep 30' bash --session-id "$sid")"
  [ "$(_meta "$id" sid)" = "$sid" ]
  run "$WAKE" --resolve "$id"
  [ "$status" -eq 0 ]
  [ "$output" = "$id" ]
  run "$WAKE" --resolve "$sid"
  [ "$status" -eq 0 ]
  [ "$output" = "$id" ]
  run "$WAKE" --resolve "hdl-00000000000000ff"
  [ "$status" -eq 1 ]
  # A traversal-shaped address resolves to nothing rather than to a directory outside the registry.
  run "$WAKE" --resolve "../../etc"
  [ "$status" -eq 1 ]
  "$DRV" close "$id"
}

# ── W8/W9: the HOLDER — the thing that makes stdin a channel instead of an EOF ──────────────────

@test "W8: the holder keeps the agent alive on an idle fifo — with no fifo the same agent sees EOF" {
  # The whole design rests on this: the instant the last writer closes, the agent reads EOF and the
  # session ENDS. The reader below exits on EOF, so its survival IS the holder's proof.
  local id; id="$(_spawn_reader)"
  [ -n "$(_meta "$id" holder)" ]
  sleep 1.5
  run "$DRV" address "$id"
  [ "$status" -eq 0 ]
  run grep -q '^EOF$' "$CC_PANE_HOME/$id/out.log"
  [ "$status" -ne 0 ]
  # THE LOAD-BEARING HALF: the agent must survive the WAKER closing its end. Without a holder the
  # waker is the only writer, so its close is EOF and the session dies on the first wake it
  # receives — a wake that kills what it woke.
  run "$WAKE" "$id"
  [ "$status" -eq 0 ]
  run _await_log "$id" '^GOT {'
  [ "$status" -eq 0 ]
  sleep 0.5
  run "$DRV" address "$id"
  [ "$status" -eq 0 ]
  run grep -q '^EOF$' "$CC_PANE_HOME/$id/out.log"
  [ "$status" -ne 0 ]
  # CONTROL: the identical agent with stdin at /dev/null reaches EOF at once and exits — so the
  # driver refuses the spawn outright, and the proof is the preserved log in the dead- row.
  run _spawn_reader --stdin null
  [ "$status" -ne 0 ]
  run grep -rl '^EOF$' "$CC_PANE_HOME"/dead-*/out.log
  [ "$status" -eq 0 ]
  "$DRV" close "$id"
}

@test "W9: close reaps the HOLDER NOW — not eventually, on its own poll" {
  # THE POLL INTERVAL IS THE INSTRUMENT. The holder exits by itself once the agent dies, so at the
  # suite's default 1s poll this case passes whether `close` reaps it or not — it was measured
  # doing exactly that, and the mutant that deletes the reap survived. Pinned at 30s, only an
  # explicit kill can end the holder inside the window below, so the assertion has one cause.
  local id; id="$(CC_PANE_HOLD_POLL_S=30 _spawn_reader)"
  local holder; holder="$(_meta "$id" holder)"
  [ -n "$holder" ]
  run kill -0 "$holder"
  [ "$status" -eq 0 ]
  "$DRV" close "$id"
  local i=0
  while [ "$i" -lt 30 ]; do
    kill -0 "$holder" 2>/dev/null || break
    sleep 0.1; i=$(( i + 1 ))
  done
  run kill -0 "$holder"
  [ "$status" -ne 0 ]
}
