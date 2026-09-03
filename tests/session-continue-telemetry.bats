#!/usr/bin/env bats
# session-continue-telemetry — the auto-continue actuator must leave a trail (audit 09 D-11).
#
# `session-continue.sh` can emit {decision:"block"} up to CLAUDE_CONTINUE_MAX (8) times — it is
# the cross-turn auto-continue actuator — and it wrote NO IDL record and NO log, while all three
# of its Stop siblings (completion-assert, boundary-handoff, anti-deference-nudge) do. A runaway
# continuation or a wrongly-SUPPRESSED one was forensically invisible.
#
# Contract pinned here: every STATE CHANGE is recorded (armed · cleared{cli,kill-switch,
# sid-mismatch,cap} · fired) and the disarmed steady state is deliberately NOT — it fires on
# every Stop of every session and the sentinel's absence is itself the record.
#
# Harness laws: L1 records come from the REAL hook via its real CLI + real Stop payload; L2
# assertions key on the failure-distinct disposition/reason strings; L3 `[ ]` / `grep -q` only;
# L4 both a must-log and a must-NOT-log fixture, so an always-log bug goes RED too.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/session-continue.sh"
  # HERMETICITY — added on the 2026-07-30 graveyard take (row 8 / CONTEXT_ECONOMY_V2 §6). This suite
  # was authored BEFORE the repo's test-hermeticity ratchet existed, so it fixtured CLAUDE_CONFIG_DIR
  # and the two telemetry seams but left $HOME pointing at the operator's live ~/ — every seam the
  # hook defaults to $HOME (the wake floor's mailbox, the IDL fallback) therefore read and wrote real
  # state, and the gate correctly refused the land. Fixture $HOME FIRST: the ratchet is not
  # satisfiable by an allowlist entry and should not be.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/autonomy" "$HOME/.claude/mailbox"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox";   mkdir -p "$CC_MAILBOX_DIR"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CONTINUE_LOG="$BATS_TEST_TMPDIR/session-continue.log"
  # PIN THE PANE (the same discipline tests/session-continue.bats:41-44 already applies). Without it
  # `_ouid` is whatever pane RAN the suite, so the two floors take different exits depending on the
  # runner: under a stripped environment they return at the `_ouid` guard, and under a real pane they
  # run to completion. A verdict that flips by runner is not a control.
  PANE="CCCCCCCC-1111-2222-3333-444444444444"
  export ITERM_SESSION_ID="w0t0p0:$PANE"
  CWD="$BATS_TEST_TMPDIR/wt"; mkdir -p "$CWD"
}

arm()  { ( cd "$CWD" && CLAUDE_CODE_SESSION_ID="${2:-sidA}" bash "$HOOK" set "${1:-do the thing}" >/dev/null ); }
sc()   { ( cd "$CWD" && CLAUDE_CODE_SESSION_ID="${2:-sidA}" bash "$HOOK" "$1" >/dev/null ); }
actuate() { printf '{"cwd":"%s","session_id":"%s","transcript_path":"%s"}' "$CWD" "${1:-sidA}" "${2:-}" | bash "$HOOK" >/dev/null 2>&1; }

# last IDL record's <field>
idl_last() { jq -r "$1" "$CONTINUE_IDL" | tail -1; }
idl_count() { grep -c . "$CONTINUE_IDL" 2>/dev/null || printf '0'; }

mkuser_tx() { # transcript whose LAST user message is $1
  local path="$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}.jsonl"
  jq -nc --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}' > "$path"
  printf '%s' "$path"
}

@test "CLI set writes an 'armed' IDL record + a log line" {
  arm "finish the gate"
  [ -f "$CONTINUE_IDL" ]
  [ "$(idl_last '.disposition')" = "armed" ]
  [ "$(idl_last '.reason')" = "cli-set" ]
  [ "$(idl_last '.hook')" = "session-continue" ]
  [ "$(idl_last '.sid')" = "sidA" ]
  [ "$(idl_last '.step')" = "finish the gate" ]
  grep -q 'armed' "$CONTINUE_LOG"
}

@test "CLI clear writes a 'cleared/cli-clear' record" {
  arm "x"; sc clear
  [ "$(idl_last '.disposition')" = "cleared" ]
  [ "$(idl_last '.reason')" = "cli-clear" ]
}

@test "a block writes a 'fired/continue' record carrying the counter" {
  arm "keep going"
  actuate sidA
  [ "$(idl_last '.disposition')" = "fired" ]
  [ "$(idl_last '.reason')" = "continue" ]
  [ "$(idl_last '.count')" = "1" ]
  [ "$(idl_last '.step')" = "keep going" ]
}

@test "the disarmed steady state writes NOTHING (no per-Stop IDL spam)" {
  # RE-SCOPED 2026-09-03 (backlog 61a3b40d8695). This assertion was authored for the SENTINEL
  # actuator — "no sentinel ⇒ nothing to record" — but the two FLOORS were added to the same hook
  # later and run on exactly this fixture, so with a pane identity present the payload below did not
  # exercise a steady state at all: it made the WAKE FLOOR emit {decision:"block"}, and the hook
  # recorded nothing, so the assertion passed while measuring the precise ambiguity the IDL exists to
  # remove. Worse, its verdict was pane-dependent — under a stripped environment the floor returned
  # early at the `_ouid` guard and the same green came from a completely different path.
  # The floors are now disabled here so this owns the sentinel contract it was written for, and the
  # floors' own dispositions are pinned by the three tests below.
  CC_WAKE_FLOOR=0 CC_SHIP_FLOOR=0 actuate sidA
  [ "$(idl_count)" -eq 0 ]
  [ ! -s "$CONTINUE_LOG" ]
}

# ── THE FLOORS' DISPOSITIONS (B-3: a fire must never be byte-identical to never having run) ───────
# Measured over 978,400 IDL records / 17 files before this landed: 323 session-continue records and
# NOT ONE carrying a wake-floor reason of any kind, while the ship floor logged 1 of its 17 exits.
@test "a wake-floor BLOCK is recorded — the loudest disposition was the silent one" {
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' \
                 | ITERM_SESSION_ID='w0t0p0:$PANE' bash '$HOOK' 2>/dev/null"
  printf '%s' "$output" | grep -q '"decision":"block"'   # it really did block…
  [ "$(idl_last '.disposition')" = "fired" ]             # …and said so
  [ "$(idl_last '.reason')" = "wake-floor" ]
  [ "$(idl_last '.count')" = "1" ]
}

@test "a wake floor standing down on the operator kill-switch records WHY" {
  local tx; tx="$(mkuser_tx 'just do the one typo and stop')"
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"%s\"}' '$CWD' '$tx' \
                 | ITERM_SESSION_ID='w0t0p0:$PANE' bash '$HOOK' 2>/dev/null"
  printf '%s' "$output" | grep -qv '"decision":"block"' || false   # allowed the stop
  [ "$(idl_last '.disposition')" = "abstained" ]
  [ "$(idl_last '.reason')" = "wake-floor-kill-switch" ]
}

@test "MUST-NOT-LOG control: the floor's ordinary no-trigger decline stays silent" {
  # L4 — an always-log bug must go red here. Once the floor has fired, a later idle with no mail and
  # no custody is the genuine common case: it is not a judgment, and logging it would put a row on
  # most Stops of most sessions, which is the cost the narrowing exists to avoid.
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' \
                 | ITERM_SESSION_ID='w0t0p0:$PANE' bash '$HOOK' 2>/dev/null"
  [ "$(idl_count)" -eq 1 ]                                # the fire above
  run bash -c "printf '{\"cwd\":\"%s\",\"session_id\":\"sidA\",\"transcript_path\":\"\"}' '$CWD' \
                 | ITERM_SESSION_ID='w0t0p0:$PANE' bash '$HOOK' 2>/dev/null"
  [ -z "$output" ]                                        # declined
  [ "$(idl_count)" -eq 1 ]                                # …and added no row
}

@test "the kill switch records why the sentinel was cleared" {
  arm "keep going"
  tx="$(mkuser_tx 'do the thing and stop')"
  actuate sidA "$tx"
  [ "$(idl_last '.disposition')" = "cleared" ]
  [ "$(idl_last '.reason')" = "kill-switch" ]
}

@test "a cross-succession sentinel records the sid mismatch" {
  arm "keep going" sidA
  actuate sidB
  [ "$(idl_last '.disposition')" = "cleared" ]
  [ "$(idl_last '.reason')" = "sid-mismatch" ]
  [ "$(idl_last '.stored_sid')" = "sidA" ]
  [ "$(idl_last '.session_sid')" = "sidB" ]
}

@test "hitting the cap records 'cap-reached' with the counter" {
  arm "grind"
  CLAUDE_CONTINUE_MAX=2 actuate sidA
  CLAUDE_CONTINUE_MAX=2 actuate sidA
  CLAUDE_CONTINUE_MAX=2 actuate sidA
  [ "$(idl_last '.disposition')" = "cleared" ]
  [ "$(idl_last '.reason')" = "cap-reached" ]
  [ "$(idl_last '.max')" = "2" ]
}

@test "every emitted IDL line is valid JSON even when the step carries quotes and newlines" {
  arm 'fix the "broken" gate
then land it'
  actuate sidA
  run jq -e . "$CONTINUE_IDL"
  [ "$status" -eq 0 ]
  [ "$(idl_count)" -eq 2 ]
}

@test "telemetry never changes the stop decision (block still emitted on stdout)" {
  arm "keep going"
  run bash -c "printf '{\"cwd\":\"$CWD\",\"session_id\":\"sidA\"}' | bash '$HOOK' 2>/dev/null"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"decision":"block"'
}
