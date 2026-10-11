#!/usr/bin/env bats
# handoff-fire.sh — A SELF-RECYCLE RUN MID-TURN WAITS FOR ITS TURN TO END (2026-10-05, reso pane 254).
#
# WHY THIS SUITE EXISTS. An agent can only run `--recycle` from inside a tool call of its own turn,
# and while that call runs the pane often shows no composer box. Session d425afab was refused twice in
# one day ("composer could not be READ", after the full 180 s), and the retry ticket could not
# converge, because the re-run it asks for is issued from inside a turn as well. The fix forks: the
# foreground returns so the turn can end, and the child waits for the turn to end and then runs the
# unchanged tail of the recycle, composer gate first.
#
# What is driven here is the REAL chain, extracted from the script: recycle_fire_gated →
# recycle_composer_block → hf_recycle_defer → (fork) recycle_turn_wait → recycle_fire_gated again.
# Only the part after the gate (recycle_fire_armed: watcher, last read, /exit) is a stub that leaves a
# marker, because it needs a real tty; reaching that marker is "the recycle went on".
#
# THE CONTROL is the kill switch on the same fixture: CC_RECYCLE_TURN_WAIT=off is the pre-fix
# behaviour, and there the unreadable composer refuses and never reaches the marker.
# THE NEGATIVE CONTROL is a draft: a composer that holds text once the turn has ended still holds the
# recycle, with nothing typed.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/logs"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_FIRE_CAPACITY_GATE=off
  export CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/account-sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/no-such-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_RECYCLE_RETRY_DIR="$BATS_TEST_TMPDIR/retry"
  export CC_NOTIFY_BIN="$BATS_TEST_TMPDIR/no-such-cc-notify"
  export W="$BATS_TEST_TMPDIR"
  export SCREEN_FILE="$W/screen.txt" SENT_LOG="$W/sent.log" EVENTS="$W/events.log"
  export TX="$W/tx.jsonl" SIDFILE="$W/sid" ARMED="$W/armed" READS="$W/reads.log"
  : > "$SENT_LOG"; : > "$EVENTS"; : > "$READS"; printf 'sess-aaaa' > "$SIDFILE"
  UNITS="$W/units.sh"
  {
    sed -n '/^composer_content() {/,/^}/p'           "$HF"
    sed -n '/^recycle_composer_gate() {/,/^}/p'      "$HF"
    sed -n '/^hf_transcript_at_rest() {/,/^}/p'      "$HF"
    sed -n '/^hf_recycle_retry_dir() {/p'            "$HF"
    sed -n '/^hf_recycle_retry_ticket() {/,/^}/p'    "$HF"
    sed -n '/^hf_hold_screen_witness() {/,/^}/p'     "$HF"
    sed -n '/^rcy_composer_unreadable() {/,/^}/p'    "$HF"
    sed -n '/^hf_new_prompt_since() {/,/^}/p'        "$HF"
    sed -n '/^recycle_turn_wait() {/,/^}/p'          "$HF"
    sed -n '/^hf_recycle_defer_eligible() {/,/^}/p'  "$HF"
    sed -n '/^hf_recycle_defer() {/,/^}/p'           "$HF"
    sed -n '/^rcy_composer_unreadable_static() {/,/^}/p' "$HF"
    sed -n '/^composer_scrub_verified() {/,/^}/p'    "$HF"
    sed -n '/^composer_residue_dir() {/,/^}/p'       "$HF"
    sed -n '/^composer_residue_forget() {/,/^}/p'    "$HF"
    sed -n '/^composer_residue_is_ours() {/,/^}/p'   "$HF"
    sed -n '/^recycle_fire_gated() {/,/^}/p'         "$HF"
    sed -n '/^recycle_composer_block() {/,/^}/p'     "$HF"
  } > "$UNITS"
  bash -n "$UNITS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  for f in hf_new_prompt_since recycle_turn_wait hf_recycle_defer recycle_fire_gated recycle_composer_block; do
    grep -q "^$f() {" "$UNITS" || { echo "$f was not extracted from $HF" >&2; return 1; }
  done

  # The driver is the foreground of a self-recycle from the composer gate on, under the script's own
  # shell options. Its name carries `handoff-fire` because the one-waiter check reads the waiter's argv.
  DRIVER="$W/handoff-fire-driver.sh"
  cat > "$DRIVER" <<'DRV'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
. "$W/units.sh"
hf_bounded() { # <bin> session <read|send> -s <sid> ... — anything else (cc-notify) is unreachable
  if [ "${2:-}" = session ] && [ "${3:-}" = read ]; then echo r >> "$READS"; cat "$SCREEN_FILE" 2>/dev/null; return 0; fi
  if [ "${2:-}" = session ] && [ "${3:-}" = send ]; then printf '%s\n' "SEND:${6:-}" >> "$SENT_LOG"; return 0; fi
  # The screen witness runs the REAL snapshot store; its kitty transport is the LCS_CC_TUI stub.
  case "${2:-}" in */lr-composer-snapshot.sh) "$@"; return $? ;; esac
  return 1
}
in_kitty() { [ "${STUB_IN_KITTY:-0}" = 1 ]; }
emit_recycle_event() { printf '%s\t%s\n' "$1" "${4:-}" >> "$EVENTS"; }
cc-notify() { printf '%s\n' "NOTIFY:$*" >> "$EVENTS"; }
hf_invoking_call_pid() { [ -n "${CALLER_PID:-}" ] || return 1; printf '%s' "$CALLER_PID"; }
cc_sid_for_pane() { cat "$SIDFILE" 2>/dev/null || true; }
transcript_for_sid() { printf '%s' "$TX"; }
fire_cleanup() { :; }
hf_inflight_release() { :; }
recycle_fire_armed() { echo reached > "$ARMED"; }
SID=77; tty=/dev/ttys999; CMD="claude 'brief'"; RCY_REMOTE="${RCY_REMOTE:-0}"; RESUME_LAUNCHER="${RESUME_LAUNCHER:-}"
PROMPT_FILE="$W/brief.txt"; REAL_IT2=it2
recycle_fire_gated
DRV
  chmod +x "$DRIVER"

  B="$(printf '─%.0s' $(seq 1 100))"
  # Fast clocks: no first look, a 2 s draft wait, a 1 s settle.
  export CC_RECYCLE_TURN_WAIT_PROBE_S=0 CC_RECYCLE_DRAFT_WAIT=2 CC_RECYCLE_DRAFT_IVL=1
  export CC_RECYCLE_TURN_WAIT_S=20 CC_RECYCLE_TURN_WAIT_IVL_S=1 CC_RECYCLE_TURN_SETTLE_S=1
  # A caller that has already returned: a pid that is certainly dead.
  true & DEAD_PID=$!; wait "$DEAD_PID" 2>/dev/null || true
  LIVE_PID=""
}

teardown() {
  [ -z "${LIVE_PID:-}" ] || kill "$LIVE_PID" 2>/dev/null || true
  local p
  for p in "$CC_RECYCLE_RETRY_DIR"/.turn-wait-*.pid; do
    [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null || true
  done
}

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────
screen_boxless() { { echo "⏺ Bash(handoff-fire.sh --recycle)"; echo "  ⎿  Running…"; echo "✻ Working… (12s)"; } > "$SCREEN_FILE"; }
screen_box() { { echo "⏺ some reply"; echo "$B"; echo "❯ ${1:-}"; echo "$B"; echo "  (4) repo · statusline"; } > "$SCREEN_FILE"; }
iso() { date -u -v+"${1:-0}"S +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d "+${1:-0} seconds" +%Y-%m-%dT%H:%M:%S.000Z; }
tx_tool_use()  { printf '{"type":"assistant","timestamp":"%s","message":{"stop_reason":"tool_use","content":[{"type":"tool_use"}]}}\n' "$(iso 0)" >> "$TX"; }
tx_tool_result() { printf '{"type":"user","timestamp":"%s","message":{"content":[{"type":"tool_result","content":"deferred"}]}}\n' "$(iso "${1:-60}")" >> "$TX"; }
tx_end_turn()  { printf '{"type":"assistant","timestamp":"%s","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"Recycling."}]}}\n' "$(iso "${1:-61}")" >> "$TX"; }
tx_hook_feedback() { printf '{"type":"user","isMeta":true,"timestamp":"%s","message":{"content":"Stop hook feedback: keep going"}}\n' "$(iso "${1:-62}")" >> "$TX"; }
tx_prompt()    { printf '{"type":"user","timestamp":"%s","message":{"content":"%s"}}\n' "$(iso "${2:-63}")" "$1" >> "$TX"; }
wait_for() { # $1=seconds $2...=condition → 0 once it holds
  local n=0 max=$(( $1 * 5 )); shift
  while [ "$n" -lt "$max" ]; do "$@" && return 0; sleep 0.2; n=$((n + 1)); done
  return 1
}
event() { grep -q "^$1$(printf '\t')" "$EVENTS"; }
not() { if "$@"; then return 1; fi; }
armed() { [ -f "$ARMED" ]; }
units() { # shellcheck disable=SC1090
  . "$UNITS"; }

# ── 1. the fork: the foreground returns, the recycle goes on once the turn has ended ─────────

@test "[RED] unreadable composer mid-turn: the call returns DEFERRED, and the recycle goes on after the turn ends" {
  screen_boxless; tx_tool_use
  CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"recycle DEFERRED to the end of this turn"* ]] || false
  [[ "$output" != *"could not be READ"* ]] || false
  event recycle-deferred-turn
  # The turn is still running: nothing goes on, and nothing was typed.
  sleep 2
  not armed; not event recycle-turn-ended; [ ! -s "$SENT_LOG" ]
  # The turn ends and the composer is back, empty.
  tx_tool_result; tx_end_turn; screen_box ""
  wait_for 15 armed
  event recycle-turn-ended
  [ ! -s "$SENT_LOG" ]                                   # the gate itself types nothing
  [ ! -f "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json" ]        # a recycle that went on leaves no ticket
}

@test "CONTROL (the pre-fix behaviour, CC_RECYCLE_TURN_WAIT=off): the same fixture REFUSES and leaves a ticket" {
  screen_boxless; tx_tool_use
  CC_RECYCLE_TURN_WAIT=off CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 1 ]
  [[ "$output" == *"composer could not be READ"* ]] || false
  not event recycle-deferred-turn
  tx_tool_result; tx_end_turn; screen_box ""
  sleep 2
  not armed
  [ -f "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json" ]
}

@test "NEGATIVE CONTROL: a composer holding a DRAFT once the turn has ended still HOLDS — nothing typed" {
  screen_boxless; tx_tool_use
  CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 0 ]
  tx_tool_result; tx_end_turn; screen_box "fix the margin"
  wait_for 15 event recycle-held-draft
  grep -q 'fixthemargin' "$EVENTS"
  not armed
  [ ! -s "$SENT_LOG" ]
}

@test "the turn never ends inside the bound ⇒ HELD, nothing typed, and the retry ticket is the fallback" {
  screen_boxless; tx_tool_use
  CC_RECYCLE_TURN_WAIT_S=2 CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 0 ]
  wait_for 15 event recycle-held-busy
  not armed; [ ! -s "$SENT_LOG" ]
  [ "$(jq -r .why "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json")" = "the turn that ran the recycle did not end in time" ]
}

@test "the tool call that ran the recycle has NOT returned ⇒ an at-rest transcript is not believed" {
  screen_box ""; tx_tool_use; tx_tool_result; tx_end_turn
  screen_boxless
  sleep 60 3>&- & LIVE_PID=$!
  CC_RECYCLE_TURN_WAIT_S=2 CALLER_PID="$LIVE_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 0 ]
  wait_for 15 event recycle-held-busy
  grep -q 'has not returned' "$EVENTS"
  not armed
}

@test "a NEW PROMPT after the deferral ⇒ HELD with a ticket: the session is on other work now" {
  screen_boxless; tx_tool_use
  CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 0 ]
  tx_tool_result; tx_end_turn; tx_prompt "actually, look at the margin first"; screen_box ""
  wait_for 15 event recycle-held-new-prompt
  not armed; [ ! -s "$SENT_LOG" ]
  [ -f "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json" ]
}

@test "the pane now holds ANOTHER session ⇒ dropped, nothing typed, no ticket for a session that is gone" {
  screen_boxless; tx_tool_use
  CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 0 ]
  printf 'sess-bbbb' > "$SIDFILE"; tx_tool_result; tx_end_turn; screen_box ""
  wait_for 15 event recycle-held-subject-gone
  not armed; [ ! -s "$SENT_LOG" ]
  [ ! -f "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json" ]
}

@test "NOT a self-recycle inside a tool call ⇒ unchanged: refused, no fork" {
  screen_boxless; tx_tool_use
  run "$DRIVER" 3>&-
  [ "$status" -eq 1 ]
  [[ "$output" == *"composer could not be READ"* ]] || false
  not event recycle-deferred-turn
}

@test "a REMOTE recycle is never deferred, even with a caller pid in hand" {
  screen_boxless; tx_tool_use
  RCY_REMOTE=1 CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 1 ]
  not event recycle-deferred-turn
  [ ! -f "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json" ]
}

@test "ONE waiter per pane: a second recycle while one waits forks nothing and says so" {
  screen_boxless; tx_tool_use
  CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 0 ]
  CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 0 ]
  [[ "$output" == *"already DEFERRED"* ]] || false
  [ "$(grep -c '^recycle-deferred-turn' "$EVENTS")" -eq 1 ]
}

@test "a READABLE empty composer mid-turn is not deferred at all — the recycle goes straight on" {
  screen_box ""; tx_tool_use
  CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 0 ]
  armed
  not event recycle-deferred-turn
}

# ── 1b. a STATIC unreadable screen is held at once (docs/research/recycle-failures-kitty-2026-10-10/
# REPORT.md F3, fixes 3 and 5). Pane 134: our own /exit stayed in the box under the slash menu, the
# self-recycle took the UNKNOWN for a running turn, deferred, and the child then spent the full gate
# on an idle pane. The real 2.1.291 capture with HF_COMPOSER_SLASH_MENU=off is that field shape (a ❯
# menu row above the box). The gate sleeps with /bin/sleep, so the cost is counted in screen reads.
screen_slash_menu() { cp "$REPO/tests/fixtures/recycle-exit-residue/slash-menu-exit-2.1.291.txt" "$SCREEN_FILE"; }
reads() { wc -l < "$READS" | tr -d ' '; }

@test "[RED] F3: a STATIC unreadable screen at rest is HELD at once as recycle-held-unreadable-static — no deferral, no full gate, nothing typed" {
  screen_slash_menu; tx_tool_use; tx_tool_result 0; tx_end_turn 1
  HF_COMPOSER_SLASH_MENU=off CC_RECYCLE_TURN_WAIT_PROBE_S=2 CC_RECYCLE_DRAFT_WAIT=10 CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 1 ]
  event recycle-held-unreadable-static
  grep -q 'dialog-above' "$EVENTS"
  not event recycle-deferred-turn
  [ "$(reads)" -le 3 ] || { echo "reads=$(reads)"; false; }
  not armed; [ ! -s "$SENT_LOG" ]
  # No receipt for our own /exit: the hold does not claim the box holds it.
  not grep -q 'our own /exit' "$EVENTS"
  jq -e '.why | test("static screen")' "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json" >/dev/null
}

@test "F3: with a fresh receipt for our own /exit, the static hold says the box most likely holds it and it is safe to clear by hand" {
  screen_slash_menu; tx_tool_use; tx_tool_result 0; tx_end_turn 1
  mkdir -p "$CC_COMPOSER_RESIDUE_DIR"; printf '2026-10-10T01:21:00Z\t/exit\n' > "$CC_COMPOSER_RESIDUE_DIR/77"
  HF_COMPOSER_SLASH_MENU=off CC_RECYCLE_TURN_WAIT_PROBE_S=2 CC_RECYCLE_DRAFT_WAIT=10 CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 1 ]
  event recycle-held-unreadable-static
  grep -q 'our own /exit.*safe to clear that /exit by hand' "$EVENTS"
  [[ "$output" == *"safe to clear that /exit by hand"* ]] || false
  jq -e '.why | test("our own /exit")' "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json" >/dev/null
  [ ! -s "$SENT_LOG" ]
}

# ── 2. the decision, as units ────────────────────────────────────────────────────────────────

@test "settle: a Stop hook that blocks seconds after end_turn is a turn still running" {
  units
  # shellcheck disable=SC2329  # called by composer_content, which units() sourced
  hf_bounded() { cat "$SCREEN_FILE" 2>/dev/null; }
  screen_box ""; tx_tool_use; tx_end_turn 1
  step=0
  fake_sleep() { step=$((step + 1)); [ "$step" = 1 ] && tx_hook_feedback 2; return 0; }
  # shellcheck disable=SC2034  # read by recycle_turn_wait
  HF_SLEEP=fake_sleep
  rc=0; recycle_turn_wait it2 77 "$DEAD_PID" "$TX" "$(date +%s)" 4 1 3 || rc=$?
  [ "$rc" -eq 2 ]
  [ "$RCY_TW_WHY" = "the turn is still running" ]
  # Without the hook's record the same clock reaches the settle window.
  : > "$TX"; tx_tool_use; tx_end_turn 1; step=5
  rc=0; recycle_turn_wait it2 77 "$DEAD_PID" "$TX" "$(date +%s)" 4 1 3 || rc=$?
  [ "$rc" -eq 0 ]
}

@test "no transcript to read ⇒ the composer box is the witness: boxless waits, a box is ready" {
  units
  # shellcheck disable=SC2329  # called by composer_content, which units() sourced
  hf_bounded() { cat "$SCREEN_FILE" 2>/dev/null; }
  # shellcheck disable=SC2034  # read by recycle_turn_wait
  HF_SLEEP=true
  screen_boxless
  rc=0; recycle_turn_wait it2 77 "$DEAD_PID" "$W/absent.jsonl" "$(date +%s)" 2 1 0 || rc=$?
  [ "$rc" -eq 2 ]
  screen_box "a draft is still a box"
  rc=0; recycle_turn_wait it2 77 "$DEAD_PID" "$W/absent.jsonl" "$(date +%s)" 2 1 0 || rc=$?
  [ "$rc" -eq 0 ]
}

@test "[RED] the UNKNOWN's shape travels as the exit code: turn-shaped rc 1 waits out the gate, static rc 3 stops at the second read" {
  units
  # shellcheck disable=SC2329  # called by composer_content, which units() sourced
  hf_bounded() { echo r >> "$READS"; cat "$SCREEN_FILE" 2>/dev/null; }
  # Turn shape: no box. composer_content says 1, and the gate waits out its whole bound (rc 2).
  screen_boxless
  rc=0; composer_content it2 77 >/dev/null || rc=$?
  [ "$rc" -eq 1 ]
  : > "$READS"; rc=0; recycle_composer_gate it2 77 2 1 >/dev/null || rc=$?
  [ "$rc" -eq 2 ]; [ "$(reads)" -eq 3 ]
  # Static shapes: a menu row above the box, and an option row under the last border.
  screen_slash_menu
  rc=0; out="$(HF_COMPOSER_SLASH_MENU=off composer_content it2 77)" || rc=$?
  [ "$rc" -eq 3 ]; [ -z "$out" ]                         # nothing new on stdout
  : > "$READS"; rc=0; out="$(HF_COMPOSER_SLASH_MENU=off recycle_composer_gate it2 77 30 1)" || rc=$?
  [ "$rc" -eq 3 ]; [ "$out" = dialog-above ]; [ "$(reads)" -eq 2 ]
  { echo "$B"; echo "❯ "; echo "$B"; echo "  ❯ 1. Yes"; } > "$SCREEN_FILE"
  rc=0; out="$(recycle_composer_gate it2 77 30 1)" || rc=$?
  [ "$rc" -eq 3 ]; [ "$out" = glyph-below ]
  # A one-read gate (the freshness re-read, the focus gate) never says 3: one read confirms nothing.
  screen_slash_menu
  rc=0; HF_COMPOSER_SLASH_MENU=off recycle_composer_gate it2 77 0 1 >/dev/null || rc=$?
  [ "$rc" -eq 2 ]
  # A static SHAPE on a screen that changes between reads (a spinner's timer) is not a static screen:
  # the gate waits out its bound as before.
  # shellcheck disable=SC2329  # called by composer_content
  hf_bounded() { echo r >> "$READS"; sed "1s/.*/✻ Working… ($(reads)s)/" "$SCREEN_FILE"; }
  : > "$READS"; rc=0; HF_COMPOSER_SLASH_MENU=off recycle_composer_gate it2 77 2 1 >/dev/null || rc=$?
  [ "$rc" -eq 2 ]; [ "$(reads)" -eq 3 ]
}

@test "hf_new_prompt_since: tool results, hook feedback, subagent traffic and older prompts are not new prompts" {
  units
  since="$(date +%s)"
  tx_prompt "the prompt that started the turn" -30; tx_tool_use; tx_tool_result; tx_hook_feedback
  printf '{"type":"user","isSidechain":true,"timestamp":"%s","message":{"content":"subagent brief"}}\n' "$(iso 64)" >> "$TX"
  rc=0; hf_new_prompt_since "$TX" "$since" || rc=$?
  [ "$rc" -eq 1 ]
  tx_prompt "<task-notification>\\n<task-id>b1</task-id>" 65
  rc=0; hf_new_prompt_since "$TX" "$since" || rc=$?
  [ "$rc" -eq 0 ]
  rc=0; hf_new_prompt_since "$W/absent.jsonl" "$since" || rc=$?
  [ "$rc" -eq 2 ]
}

# ── fix 4: a DEFERRED self-recycle re-reads the session at the last moment before /exit ───────────
# docs/research/recycle-failures-kitty-2026-10-10/REPORT.md fix 4. Once the deferred turn has ended,
# the composer gate can hold for up to CC_RECYCLE_DRAFT_WAIT, and before this fix the self lane had no
# at-rest or new-prompt read after it: rcy_rest_tx was set only for same-account and focused-remote.
# A prompt the operator submitted inside that window was a turn the /exit would kill. The REAL
# recycle_fire_armed is driven over stubs to its commit; reaching the recycle_fire_commit stub is "the
# /exit would have been typed", so the held cases assert that marker is ABSENT (a "no SEND:/exit"
# assertion passes before the fix, because the commit is stubbed).
armed_driver() {
  export HF DEAD_PID COMMITTED="$W/committed" T0
  cat > "$W/armed-driver.sh" <<'DRV'
#!/usr/bin/env bash
set -euo pipefail
# shellcheck disable=SC1090
. "$W/units.sh"
eval "$(sed -n '/^recycle_fire_armed() {/,/^}/p' "$HF")"
hf_bounded() {
  if [ "${2:-}" = session ] && [ "${3:-}" = read ]; then cat "$SCREEN_FILE" 2>/dev/null; return 0; fi
  if [ "${2:-}" = session ] && [ "${3:-}" = send ]; then printf '%s\n' "SEND:${6:-}" >> "$SENT_LOG"; return 0; fi
  return 1
}
emit_recycle_event() { printf '%s\t%s\n' "$1" "${4:-}" >> "$EVENTS"; }
cc_sid_for_pane() { cat "$SIDFILE" 2>/dev/null || true; }
inherit_recycle_goal() { :; }; pin_term_verdict_for_watcher() { :; }; hf_lr_lib_load() { return 1; }
hf_recycle_lock_acquire() { :; }; hf_phase() { :; }; detach() { printf '4242'; }
await_armed() { return 0; }; await_pane_proof() { return 0; }; hf_recycle_owed_clear() { :; }
write_teardown_marker() { :; }; hf_recycle_disarm() { :; }; hf_succ_stage() { :; }
recycle_fire_commit() { echo reached > "$COMMITTED"; }
SID=77; tty=/dev/ttys999; CMD="claude 'brief'"; LAUNCHER=claude; RCY_IT2=it2; RCY_REMOTE=0; RCY_SAME_ACCOUNT=0
RESUME_LAUNCHER=""; RESUME_CFG=""; HF_TS_TOMBSTONE=""; RECYCLE_MARKER=MK; FIRE_GOAL=""; RCY_TRANSPLANT_CAUSE=""
PROMPT_FILE="$W/brief.txt"; log="$W/watcher.log"; cmdfile="$W/cmd"; LAUNCH_DIR="$W"; RECYCLE_AWAIT=0
HF_ORIG_ARGV=(); HF_ORIG_SELF=""; HF_ORIG_PWD=""; HF_T0_EPOCH=0; HF_RCY_PHASES=""; HF_RCY_CARRY_DIR=""; HF_RCY_CARRY_STATE=""
RCY_DEFERRED=1; RCY_DEFER_CALLER_PID="$DEAD_PID"
# hf_recycle_defer's locals, which the fork this tail runs in inherits: the transcript recycle_turn_wait
# judged and the deferral epoch.
dtx="$TX"; t0="$T0"
recycle_fire_armed
DRV
  chmod +x "$W/armed-driver.sh"
}
deferred_turn_ended() { T0="$(date +%s)"; screen_box ""; tx_tool_use; tx_tool_result; tx_end_turn; }

@test "CONTROL fix 4: a deferred self-recycle whose session is still at rest reaches the /exit commit" {
  deferred_turn_ended; armed_driver
  run "$W/armed-driver.sh" 3>&-
  [ "$status" -eq 0 ] || { echo "$output"; cat "$EVENTS"; false; }
  [ -f "$COMMITTED" ] || { echo "$output"; cat "$EVENTS"; false; }
  not event recycle-held-new-prompt; not event recycle-held-busy
}

@test "[RED] fix 4: a prompt submitted after the deferred turn ended HOLDS at the last read — the /exit commit is never reached" {
  deferred_turn_ended; armed_driver
  tx_prompt "wait, one more thing first"
  run "$W/armed-driver.sh" 3>&-
  [ "$status" -eq 1 ] || { echo "status=$status $output"; cat "$EVENTS"; false; }
  [ ! -f "$COMMITTED" ] || { echo "the /exit commit was reached over a new prompt"; echo "$output"; false; }
  event recycle-held-new-prompt || { cat "$EVENTS"; false; }
  [ ! -s "$SENT_LOG" ]
  [ "$(jq -r .why "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json")" = "a new prompt arrived after the recycling turn had ended" ]
}

@test "[RED] fix 4: a turn running again after the deferred turn ended (blocking Stop hook) HOLDS busy — no commit" {
  deferred_turn_ended; armed_driver
  tx_hook_feedback
  run "$W/armed-driver.sh" 3>&-
  [ "$status" -eq 1 ] || { echo "status=$status $output"; cat "$EVENTS"; false; }
  [ ! -f "$COMMITTED" ] || { echo "the /exit commit was reached mid-turn"; echo "$output"; false; }
  grep -q "^recycle-held-busy$(printf '\t')deferred-self: transcript not at rest" "$EVENTS" || { cat "$EVENTS"; false; }
  [ -f "$CC_RECYCLE_RETRY_DIR/sess-aaaa.json" ]
}

# ── fix 6: a held-unreachable keeps the screen it could not read ─────────────────────────────────
# docs/research/recycle-failures-kitty-2026-10-10/REPORT.md fix 6: F2 and F3 had no screen witness.
# The REAL lr-composer-snapshot.sh store runs; only its kitty transport (cc_tui_rpc) is a stub serving
# the fixture screen, so nothing reaches a terminal.
@test "[RED] fix 6: a held-unreachable composer writes a 0600 screen snapshot carrying the fixture's rows, named in the row" {
  screen_boxless; tx_tool_use
  export HF_DIR="$REPO/scripts" LR_COMPOSER_SNAP_DIR="$W/snaps" LCS_CC_TUI="$W/cc-tui-stub.sh" STUB_IN_KITTY=1
  # shellcheck disable=SC2016  # expanded by the stub library, not here
  printf 'cc_tui_rpc() { cat "$SCREEN_FILE"; }\n' > "$LCS_CC_TUI"
  CC_RECYCLE_TURN_WAIT=off CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  event recycle-held-unreachable || { cat "$EVENTS"; false; }
  local snap
  snap="$(find "$LR_COMPOSER_SNAP_DIR" -name '*.ansi' 2>/dev/null | head -n 1)"
  [ -n "$snap" ] || { echo "no snapshot written"; cat "$EVENTS"; false; }
  grep -qF 'Bash(handoff-fire.sh --recycle)' "$snap" || { cat "$snap"; false; }
  grep -qF 'Working… (12s)' "$snap" || { cat "$snap"; false; }
  [ "$(stat -f %Lp "$snap" 2>/dev/null || stat -c %a "$snap")" = 600 ]
  grep -qF "screen $snap" "$EVENTS" || { cat "$EVENTS"; false; }
}

@test "fix 6: outside kitty the hold names no screen and still holds — the witness never costs the refusal" {
  screen_boxless; tx_tool_use
  export HF_DIR="$REPO/scripts" LR_COMPOSER_SNAP_DIR="$W/snaps"
  CC_RECYCLE_TURN_WAIT=off CALLER_PID="$DEAD_PID" run "$DRIVER" 3>&-
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  grep -qF 'screen none (not a kitty pane)' "$EVENTS" || { cat "$EVENTS"; false; }
  [ ! -d "$LR_COMPOSER_SNAP_DIR" ]
}
