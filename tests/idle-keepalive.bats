#!/usr/bin/env bats
# shellcheck disable=SC2016  # the bash -c bodies read $1/$2 as positional args, on purpose
# idle-keepalive — the log-only main-session cache keepalive (docs/plans/USAGE_LEVERS.md § W3).
#
# Owns two contracts:
#   the GAP LEDGER  hooks/cache-expiry-tracker.sh (registered on Stop) → hooks/lib/idle_gap.py stop:
#                   each Stop closes the session's previous idle gap (duration, what the first
#                   request after it paid, the priced outcome) and opens the next with its context
#                   size; stdout stays empty and the hook cannot fail.
#   the TIMER       hooks/idle-keepalive.sh (registered by migration 0077): timed from the gap start,
#                   one would-wake row per idle gap while a watcher is armed, nothing once the gap
#                   ends, nothing in a non-interactive session, and exit 0 on every path (asyncRewake
#                   wakes only on exit 2, so rc 0 is what makes it log-only).
# RED-proof: new behaviour. Mutants checked by hand on scratch copies: dropping the tracker's
# idle_gap call fails (1); dropping the timer's transcript-size check fails (5); dropping the
# headless guard fails (6).
#
# Hermetic: $HOME, the ledger, the state dir and the mailbox dir are fixtures; the timer's harness
# argv and fd 1 come through the same seams mailbox-wake-arm.sh uses.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$HOME/.claude-tertiary"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_IDLE_KEEPALIVE_LOG="$BATS_TEST_TMPDIR/ledger.jsonl"
  export CC_IDLE_KEEPALIVE_STATE="$BATS_TEST_TMPDIR/state"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"; mkdir -p "$CC_MAILBOX_DIR"
  unset CC_IDLE_KEEPALIVE CLAUDE_CODE_ENTRYPOINT CC_PANE_ID ITERM_SESSION_ID CC_KEEPALIVE_WAKE_S CC_KEEPALIVE_MAX_WAKES
  TX="$BATS_TEST_TMPDIR/sess.jsonl"; : > "$TX"
  SID="0b5e1d2c-aaaa-bbbb-cccc-000000000001"
  PAYLOAD="$(jq -nc --arg s "$SID" --arg t "$TX" '{session_id:$s,transcript_path:$t,hook_event_name:"Stop"}')"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

iso() { date -u -r "$1" +%FT%TZ; }
user_at() { printf '{"type":"user","timestamp":"%s","message":{"content":"go"}}\n' "$(iso "$1")" >> "$TX"; }
asst_at() { # <epoch> <cache_write> <cache_read>
  printf '{"type":"assistant","timestamp":"%s","message":{"model":"claude-opus-5-5","usage":{"input_tokens":2,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s,"output_tokens":98}}}\n' \
    "$(iso "$1")" "$2" "$3" >> "$TX"
}
tracker() { run bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$PAYLOAD" "$REPO/hooks/cache-expiry-tracker.sh"; }
backdate() { # <seconds> — move the open gap's start into the past
  jq --argjson d "$1" '.start -= $d' "$CC_IDLE_KEEPALIVE_STATE/$SID.json" > "$BATS_TEST_TMPDIR/s" \
    && mv "$BATS_TEST_TMPDIR/s" "$CC_IDLE_KEEPALIVE_STATE/$SID.json"
}
timer() { # runs the timer as an interactive session would, with a 1 s wake
  run env CC_IDLE_KEEPALIVE_HARNESS_ARGV="${ARGV:-claude --model x}" CC_IDLE_KEEPALIVE_HARNESS_FD1=/dev/ttys009 \
    CC_KEEPALIVE_WAKE_S=1 CC_IDLE_KEEPALIVE_SETTLE_S=0 CC_IDLE_KEEPALIVE_POLL_S=1 \
    bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$PAYLOAD" "$REPO/hooks/idle-keepalive.sh"
}

@test "(1) a Stop opens a gap and the next Stop closes it: duration, observed rebuild, priced outcome" {
  now=$(date +%s)
  user_at $((now - 4100)); asst_at $((now - 4095)) 1000 199000   # before the back-dated gap start
  tracker
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(jq -r .ctx "$CC_IDLE_KEEPALIVE_STATE/$SID.json")" = 200100 ]
  [ -f "$CLAUDE_CONFIG_DIR/.last-interaction" ]
  [ ! -s "$CC_IDLE_KEEPALIVE_LOG" ]                         # nothing to close on the first Stop
  backdate 4000                                              # the gap started 4000 s ago
  start=$(jq -r '.start|floor' "$CC_IDLE_KEEPALIVE_STATE/$SID.json")
  user_at $((start + 3900)); asst_at $((start + 3905)) 200300 0   # 65 min later: a full re-write
  tracker
  [ "$status" -eq 0 ]; [ -z "$output" ]
  row="$(tail -1 "$CC_IDLE_KEEPALIVE_LOG")"
  [ "$(jq -r '[.kind,.acct,(.dur|floor),.end_src,.ctx,.wakes,.outcome,.obs_cw] | join(" ")' <<<"$row")" \
    = "gap .claude-tertiary 3900 record 200100 1 wake_saves 200300" ]
  jq -e '.net_pp[0] > 0 and .net_pp[0] <= .net_pp[1]
         and .breakeven_p[0] > 0 and .breakeven_p[1] < 0.1' <<<"$row" >/dev/null
  # and the next gap is open, at the context the last request left
  [ "$(jq -r .ctx "$CC_IDLE_KEEPALIVE_STATE/$SID.json")" = 200400 ]
}

@test "(2) outcome classes: no wake / unneeded / saves / insufficient, and a second wake extends cover" {
  run /usr/bin/env python3 -I - "$REPO/hooks/lib/idle_gap.py" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("g", sys.argv[1]); g = importlib.util.module_from_spec(spec); spec.loader.exec_module(g)
for d in (3000, 3500, 3600, 6899, 6900):
    c = g.gap_costs(200000, d, wake_s=3300, ttl_s=3600, max_wakes=1)
    print(d, c["outcome"], c["wakes"], "+" if c["net_pp"][0] > 0 else ("0" if c["net_pp"] == [0, 0] else "-"))
print(9000, g.outcome(9000, wake_s=3300, ttl_s=3600, max_wakes=2)[3])
PY
  [ "$status" -eq 0 ]
  [ "$output" = "3000 no_wake 0 0
3500 wake_unneeded 1 -
3600 wake_saves 1 +
6899 wake_saves 1 +
6900 wake_insufficient 1 -
9000 wake_saves" ]
}

@test "(3) a non-interactive session's Stop opens no gap; CC_IDLE_KEEPALIVE=off leaves only the timestamp" {
  asst_at "$(date +%s)" 10 10
  CLAUDE_CODE_ENTRYPOINT=sdk-cli tracker
  [ "$status" -eq 0 ]
  [ ! -e "$CC_IDLE_KEEPALIVE_STATE/$SID.json" ]
  CC_IDLE_KEEPALIVE=off tracker
  [ "$status" -eq 0 ]
  [ ! -e "$CC_IDLE_KEEPALIVE_STATE/$SID.json" ]
  [ -f "$CLAUDE_CONFIG_DIR/.last-interaction" ]
}

@test "(4) an unwritable ledger costs the row, never the hook: rc 0, empty stdout" {
  asst_at "$(date +%s)" 10 10
  CC_IDLE_KEEPALIVE_STATE=/dev/null/nope CC_IDLE_KEEPALIVE_LOG=/dev/null/nope tracker
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ -f "$CLAUDE_CONFIG_DIR/.last-interaction" ]
}

@test "(5) timer: one would-wake row per idle gap, alongside an ARMED watcher; none once the gap ends" {
  asst_at "$(date +%s)" 500 150000
  tracker                                                     # the ledger opens the gap (ctx)
  printf 'pid=%s\n' "$$" > "$CC_MAILBOX_DIR/$SID.watching"   # a live watcher covers this inbox
  timer
  [ "$status" -eq 0 ]; [ -z "$output" ]
  [ "$(grep -c '"kind":"wake"' "$CC_IDLE_KEEPALIVE_LOG")" -eq 1 ]
  [ "$(jq -r 'select(.kind=="wake") | [.n,.ctx,.watcher_armed,.mode] | join(" ")' "$CC_IDLE_KEEPALIVE_LOG")" \
    = "1 150600 true shadow" ]
  # the gap ends mid-wait (a new turn writes the transcript): no row
  ( sleep 0.5; printf '{"type":"user"}\n' >> "$TX" ) &
  timer
  wait
  [ "$status" -eq 0 ]
  [ "$(grep -c '"kind":"wake"' "$CC_IDLE_KEEPALIVE_LOG")" -eq 1 ]
}

@test "(6) timer: a non-interactive harness (-p, or stdout not a tty) returns at once and logs nothing" {
  ARGV="claude -p hello" timer
  [ "$status" -eq 0 ]
  run env CC_IDLE_KEEPALIVE_HARNESS_ARGV="claude" CC_IDLE_KEEPALIVE_HARNESS_FD1="pipe:[123]" CC_KEEPALIVE_WAKE_S=1 \
    CC_IDLE_KEEPALIVE_SETTLE_S=0 bash -c 'printf "%s" "$1" | /bin/bash "$2"' _ "$PAYLOAD" "$REPO/hooks/idle-keepalive.sh"
  [ "$status" -eq 0 ]
  [ ! -s "$CC_IDLE_KEEPALIVE_LOG" ]
}

@test "(7) timer exits 0 on a malformed payload and when switched off" {
  run bash -c 'printf "not json" | CC_IDLE_KEEPALIVE_HARNESS_ARGV=claude CC_IDLE_KEEPALIVE_HARNESS_FD1=/dev/ttys1 /bin/bash "$1"' _ "$REPO/hooks/idle-keepalive.sh"
  [ "$status" -eq 0 ]
  CC_IDLE_KEEPALIVE=off timer
  [ "$status" -eq 0 ]
  [ ! -s "$CC_IDLE_KEEPALIVE_LOG" ]
}
