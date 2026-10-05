#!/usr/bin/env bats
# Tests define stubs for helpers the EXTRACTED functions call; shellcheck cannot see those calls.
# shellcheck disable=SC2329
# handoff-fire.sh self-close over a terminal that is NOT ANSWERING (husk panes 2026-09-30,
# docs/research/husk-panes-2026-09-30.md root cause 5, fix F-b).
#
# THE DEFECT. kitty's remote control stops accepting connections for 10-60 s at a time. Every
# `it2 session list` in such an episode dies on its 10 s bound (rc 124) with nothing enumerated, and
# pane_proof read that as "pane UNREACHABLE" — a terminal verdict. Between 01:40 and 02:36Z ten
# `self-close --terminal` runs aborted on it before /exit, nothing retried, nothing durable recorded
# it, and five sessions still held the panes they meant to close.
#
# WHAT IS PINNED HERE:
#   · a FAILED listing is its own verdict (pane-NO-ANSWER, rc 2), never pane-UNREACHABLE;
#   · await_pane_proof hands that up as rc 3, distinct from "answered: not there" (1);
#   · the self-close helpers wait for the terminal to answer before re-arming, record the wait in
#     the durable pane-close queue, and give up loudly with an alarm record;
#   · the __selfclose watcher treats a pane that already closed ITSELF (cc-pane-runner, fix F-a) as
#     closed, instead of failing four close attempts over it and paging close-failed-unknown.
# Nothing here touches a live terminal: it2 is a recording stub under a hermetic $HOME.

setup() {
  unset KITTY_WINDOW_ID CC_TERM CC_PANE_CMD_INTERACTIVE
  export IT2_WRAPPER_NO_KITTY=1
  # One export per line: the pin-guard (handoff-fire-capacity-gate.bats case 25) reads them that way.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/no-such-sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/no-such-heal-lock-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms"
  export IT2_CALLS="$BATS_TEST_TMPDIR/it2-calls"; : > "$IT2_CALLS"
  export LIST_MODE_FILE="$BATS_TEST_TMPDIR/list-mode"; printf 'fail\n' > "$LIST_MODE_FILE"
  export LIST_N="$BATS_TEST_TMPDIR/list-n"; printf '0\n' > "$LIST_N"
  # The it2 stub's `session list` behaviour is driven by $LIST_MODE_FILE:
  #   fail      → exit 124, nothing printed (the bound firing on a deaf kitty socket)
  #   present   → JSON naming panes 218 and 219
  #   vanish    → first call names 218 and 219, every later call names only 219
  # `session close` exits 1 with kitty's not-found text, so a close of a gone pane FAILS.
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$IT2_CALLS"
if [ "${1:-}" = session ] && [ "${2:-}" = list ]; then
  n="$(cat "$LIST_N")"; n=$((n + 1)); printf '%s\n' "$n" > "$LIST_N"
  case "$(cat "$LIST_MODE_FILE")" in
    fail) exit 124 ;;
    present) printf '[{"id": "218"}, {"id": "219"}]\n'; exit 0 ;;
    vanish) if [ "$n" -le 1 ]; then printf '[{"id": "218"}, {"id": "219"}]\n'; else printf '[{"id": "219"}]\n'; fi; exit 0 ;;
  esac
fi
if [ "${1:-}" = session ] && [ "${2:-}" = close ]; then echo "No matching windows" >&2; exit 1; fi
exit 0
SH
  chmod +x "$HOME/.claude/bin/it2"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$HOME/.claude/bin/osascript"; chmod +x "$HOME/.claude/bin/osascript"
  export PATH="$HOME/.claude/bin:$PATH"
}

xf() { local pat; pat='/^'"$1"'() {/,/^}/p'; eval "$(sed -n "$pat" "$HF")"; }

@test "pane_proof: a FAILED listing (rc 124, nothing enumerated) is NO-ANSWER rc 2, never UNREACHABLE" {
  hf_bounded() { "$@"; }
  kitty_identity() { return 1; }
  xf pane_proof
  run pane_proof "$HOME/.claude/bin/it2" 218 __selfclose
  [ "$status" -eq 2 ]
  [[ "$output" == *"!! pane-NO-ANSWER:"* ]] || false
  [[ "$output" != *"pane-UNREACHABLE"* ]] || false
  [[ "$output" == *"NOT evidence the pane is gone"* ]] || false
}

@test "pane_proof: an ANSWERED listing that lacks the pane is still UNREACHABLE rc 1 (fail-closed intact)" {
  hf_bounded() { "$@"; }
  kitty_identity() { return 1; }
  xf pane_proof
  printf 'present\n' > "$LIST_MODE_FILE"
  run pane_proof "$HOME/.claude/bin/it2" 300 __selfclose
  [ "$status" -eq 1 ]
  [[ "$output" == *"!! pane-UNREACHABLE:"* ]] || false
}

@test "await_pane_proof: a NO-ANSWER verdict is rc 3, distinct from refused (1) and silence (2)" {
  xf await_pane_proof
  local log="$BATS_TEST_TMPDIR/w.log"
  printf '→ armed: x\n!! pane-NO-ANSWER: __selfclose — failed\n' > "$log"
  run await_pane_proof "$log"
  [ "$status" -eq 3 ]
}

@test "sc_noanswer_wait: re-arms as soon as the terminal answers a probe again" {
  hf_bounded() { "$@"; }
  xf sc_noanswer_wait
  printf 'present\n' > "$LIST_MODE_FILE"
  CC_SELFCLOSE_NOANSWER_WAIT_S=3 CC_SELFCLOSE_NOANSWER_POLL_S=1 run sc_noanswer_wait 1
  [ "$status" -eq 0 ]
}

@test "sc_noanswer_wait: gives up inside its bound while the terminal stays deaf, and after the pass cap" {
  hf_bounded() { "$@"; }
  xf sc_noanswer_wait
  CC_SELFCLOSE_NOANSWER_WAIT_S=2 CC_SELFCLOSE_NOANSWER_POLL_S=1 run sc_noanswer_wait 1
  [ "$status" -eq 1 ]
  printf 'present\n' > "$LIST_MODE_FILE"
  CC_SELFCLOSE_NOANSWER_ARMS=3 CC_SELFCLOSE_NOANSWER_WAIT_S=2 CC_SELFCLOSE_NOANSWER_POLL_S=1 run sc_noanswer_wait 3
  [ "$status" -eq 1 ]
}

@test "sc_noanswer_record: the wait is written to the durable pane-close queue with its retrier" {
  local rec="$BATS_TEST_TMPDIR/pcq-args"
  export CC_PCQ_LIB="$BATS_TEST_TMPDIR/pcq.sh"
  cat > "$CC_PCQ_LIB" <<SH
pcq_add() { printf '%s\n' "\$@" > "$rec"; return 0; }
pcq_list() { printf '%s\n' "$BATS_TEST_TMPDIR/q/self-close-218.json"; }
pcq_remove() { return 0; }
SH
  cc_sid_for_pane() { printf 'sid-218'; }
  _hf_lstart() { printf 'Wed Oct  1 01:00:00 2026'; }
  xf sc_pcq_load; xf sc_noanswer_record
  SC_TERMINAL=1 run sc_noanswer_record 218 /dev/ttys999 3 /tmp/x.log
  [ "$status" -eq 0 ]
  [[ "$output" == *"self-close-218.json"* ]] || false
  run cat "$rec"
  [[ "$output" == *"self-close"* ]] || false
  [[ "$output" == *"sid=sid-218"* ]] || false
  [[ "$output" == *"retrier_pid="* ]] || false
  [[ "$output" == *"argv=--terminal"* ]] || false
}

@test "sc_noanswer_giveup: a deaf terminal is reported as such, with a durable alarm record" {
  cc_sid_for_pane() { printf 'sid-218'; }
  hf_alarm() { printf '%s\n' "$*" >> "$BATS_TEST_TMPDIR/alarms"; }
  xf sc_noanswer_giveup
  run sc_noanswer_giveup 218 3 /tmp/x.log "$BATS_TEST_TMPDIR/q/self-close-218.json"
  [[ "$output" == *"a deaf terminal, NOT a missing pane"* ]] || false
  run cat "$BATS_TEST_TMPDIR/alarms"
  [[ "$output" == *"selfclose-no-answer 218"* ]] || false
  [[ "$output" == *"HANDOFF-SELFCLOSE-NO-ANSWER"* ]] || false
}

@test "__selfclose watcher: a pane that already closed ITSELF counts as closed — no failed closes, no alarm" {
  printf 'vanish\n' > "$LIST_MODE_FILE"
  run env HOME="$HOME" timeout 30 bash "$HF" __selfclose 218 "$BATS_TEST_TMPDIR/no-such-tty"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already gone (closed from inside"* ]] || false
  run grep -c 'session close' "$IT2_CALLS"
  [ "$output" = 0 ]
  [ ! -d "$CC_HANDOFF_ALARM_DIR" ] || [ -z "$(ls -A "$CC_HANDOFF_ALARM_DIR")" ]
}
