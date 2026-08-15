#!/usr/bin/env bats
# waiting-recycle.sh — THE STAGE-2 FIRE IS OUTCOME-BOUND, NOT ANNOUNCEMENT-BOUND.
#
# THE DEFECT THIS PINS (MASTER_SESSION_LIFECYCLE.md L1/L4 — the plan's own filed-not-done follow-on).
# The Stage-2 live exec shipped as:
#
#     "$HANDOFF_FIRE" --recycle --prompt-file "$pf" … >/dev/null 2>&1 || true
#     fmsg="⟳ DETERMINISTIC RECYCLE FIRED … Do NOT run handoff-fire yourself."
#
# handoff-fire's recycle pre-pass REFUSES on at least four inputs — exit 4 (L1-b: in-flight Agent-tool
# subagents), exit 2 (verify_self_pane disproved this pane's identity), exit 1 (dirty tree /
# unresolvable pane / underivable account) — and every one of them was swallowed by that `|| true`.
# The poll then produced three falsehoods at once: the actuation ledger banked an `executed` verdict
# for a context that was never replaced (the declaration-over-event defect L4 exists to kill), the
# desk kept riding at high fill behind a one-fire-per-SID latch, and the model was told NOT to run the
# one command that would have saved it. Nothing observed the absence — this condition's whole class,
# reached through the very mechanism built to cure it.
#
# WHY A SEPARATE FILE rather than more cases in waiting-recycle.bats: every stub there exits 0, so the
# entire refusal axis is unrepresented. Keeping it separate makes the axis greppable and keeps the
# 100+-case parent suite's setup untouched.
#
# RED-PROOF DISCIPLINE. Run against pristine trunk (`git stash` / a pinned worktree of the parent
# commit), cases 1-7 go RED. Case 8 is the POSITIVE CONTROL: it asserts the rc-0 path still behaves
# exactly as it always did, so it passes on BOTH trees — nobody may later read its green as evidence
# the guard exists. Case 9 asserts an ABSENCE on the success path and therefore passes VACUOUSLY on
# pristine (pristine writes no refusal records at all); it is named here so its green is never
# mistaken for coverage either.
#
# HERMETICITY: fixture $HOME, fixture state/telemetry/config dirs, a stubbed actuator
# (CC_WR_HANDOFF_FIRE) and a stubbed notifier (CC_WR_NOTIFY) — nothing here touches the real box, and
# no case can pop an OS notification or fire a real recycle.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/waiting-recycle.sh"
  export CC_WR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_WR_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CC_RECYCLE_EVENTS="$BATS_TEST_TMPDIR/recycle-events.jsonl"   # the actuation ledger under test
  export CC_WR_T_IDLE=55 CC_WR_T_BUSY=75 CC_WR_MAX=3 CC_WR_COOLDOWN_S=600 CC_WR_AGE_MAX=180
  export CC_WR_T_NUDGE=101
  export CC_WR_COORD_DIR="$BATS_TEST_TMPDIR/coord"; export CC_WR_UUID="DESK-UUID-RC01"; export CC_WR_QUIET_S=180
  export CC_WR_GRACE_S=0
  export CC_WR_FIRE_DIR="$BATS_TEST_TMPDIR/fire"
  mkdir -p "$CC_TELEMETRY_DIR" "$CC_WR_STATE_DIR" "$CC_WR_FIRE_DIR" \
           "$CC_WR_COORD_DIR/wait-contracts" "$CC_WR_COORD_DIR/mailbox" "$CC_WR_COORD_DIR/cc-roles" \
           "$CLAUDE_CONFIG_DIR/teams"
  NOTIFY_LOG="$BATS_TEST_TMPDIR/notify.log"
  export CC_WR_NOTIFY="$BATS_TEST_TMPDIR/notify-stub.sh"
  printf '#!/bin/bash\nprintf "%%s | %%s\\n" "$1" "$2" >> %q\n' "$NOTIFY_LOG" > "$CC_WR_NOTIFY"
  chmod +x "$CC_WR_NOTIFY"

  DESK="$BATS_TEST_TMPDIR/desk"; mkdir -p "$DESK"
  git -C "$DESK" init -q
  git -C "$DESK" config user.email t@t; git -C "$DESK" config user.name t
  echo seed > "$DESK/f.txt"; git -C "$DESK" add -A; git -C "$DESK" commit -qm init
  ( cd "$DESK" && bash "$HOOK" arm >/dev/null )
}

# An actuator stub that RECORDS its argv and then exits $1 with $2 on stderr — i.e. a REFUSAL that
# looks exactly like handoff-fire's (which prints `!! …` and exits non-zero before any side effect).
mk_actuator() { # $1=exit-code $2=stderr-line
  local stub="$BATS_TEST_TMPDIR/hf-stub-$1.sh"
  ARGREC="$BATS_TEST_TMPDIR/hf-args-$1"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" > %q\nprintf "%%s\\n" %q >&2\nexit %s\n' \
    "$ARGREC" "$2" "$1" > "$stub"
  chmod +x "$stub"; export CC_WR_HANDOFF_FIRE="$stub"
}

mk_tel() { printf '{"session_id":"%s","ts":%s,"used_pct":%s,"cwd":"%s"}' "$1" "$(date +%s)" "$2" "$DESK" > "$CC_TELEMETRY_DIR/$1.json"; }
mk_tx()  { local p="$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}-$1.jsonl"; jq -nc --arg t "$2" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$p"; printf '%s' "$p"; }
drive()  { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2" "${4:-$DESK}" "${3:-echo poll}" | bash "$HOOK"; }
fired()  { echo "$1" | grep -q '"decision":"block"'; }

WAIT="next3 is still running; next4 pinged done. Waiting on the rest."

# Arm the desk LIVE (Stage-2 exec enabled) with a standing brief, then advance to Stage 2.
arm_live() {
  local tmpl="$BATS_TEST_TMPDIR/brief.txt"; echo "resume desk monitoring from disk" > "$tmpl"
  ( cd "$DESK" && bash "$HOOK" arm --brief "$tmpl" --live >/dev/null )
}
# Drive to the Stage-2 fire for sid $1: poll 1 sets the grace clock, poll 2 fires (GRACE_S=0).
to_stage2() { # $1=sid
  mk_tel "$1" 60; drive "$1" "$(mk_tx "$1" "$WAIT")" >/dev/null 2>&1 || true
  mk_tel "$1" 61; drive "$1" "$(mk_tx "$1" "$WAIT")"
}

# ── (1) THE CORE LIE — a refused actuator must not be reported as a fired recycle ────────────────
@test "refusal: rc 4 (in-flight subagents) does NOT report 'RECYCLE FIRED' to the model" {
  arm_live; mk_actuator 4 '!! recycle REFUSED: 2 in-flight subagent(s) of a1b2c3d4 would be killed'
  run to_stage2 r1
  [ "$status" -eq 0 ]; fired "$output"
  [ -f "$ARGREC" ]                                                    # the actuator really was invoked
  echo "$output" | grep -q "REFUSED"
  ! echo "$output" | grep -q "RECYCLE FIRED" || false                 # the defect: the old text shipped verbatim
  ! echo "$output" | grep -q "Do NOT run handoff-fire yourself" || false   # …and told the model to stand down
}

@test "refusal: the model is told to run /handoff ITSELF (the actuator will not retry this SID)" {
  arm_live; mk_actuator 4 '!! recycle REFUSED: in-flight subagent(s)'
  run to_stage2 r2
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "/handoff"
  echo "$output" | grep -qi "was NOT replaced"
  echo "$output" | grep -q '"additionalContext"'                      # reaches the MODEL, not just the operator
}

# ── (2) THE LEDGER — L4's actuation proof must not bank a refusal as an execution ────────────────
@test "refusal: the recycle-events ledger records 'refused', retracting the pre-call 'executed'" {
  arm_live; mk_actuator 1 '!! --recycle: refusing on a DIRTY git tree'
  run to_stage2 r3
  [ "$status" -eq 0 ]
  [ -s "$CC_RECYCLE_EVENTS" ]
  grep -q '"verdict":"refused"' "$CC_RECYCLE_EVENTS"
  # the pairing invariant: exactly one `executed` claim, retracted by exactly one `refused`
  [ "$(grep -c '"verdict":"executed"' "$CC_RECYCLE_EVENTS")" -eq 1 ]
  [ "$(grep -c '"verdict":"refused"'  "$CC_RECYCLE_EVENTS")" -eq 1 ]
}

@test "refusal: the IDL records stage2-refused with the rc and the actuator's own reason line" {
  arm_live; mk_actuator 2 '!! --recycle: pane identity could not be verified (stale id)'
  run to_stage2 r4
  [ "$status" -eq 0 ]
  grep -q '"reason":"stage2-refused"' "$CC_WR_IDL"
  grep -q '"fire_rc":2' "$CC_WR_IDL"
  grep -q 'pane identity could not be verified' "$CC_WR_IDL"
  grep -q '"executed":false' "$CC_WR_IDL"
}

# ── (3) OUT-OF-BAND — a refused recycle at high fill is a wedge; the operator must hear it ───────
@test "refusal: pages the operator out-of-band (a silent refusal is the failure class itself)" {
  arm_live; mk_actuator 4 '!! recycle REFUSED: in-flight subagent(s)'
  run to_stage2 r5
  [ "$status" -eq 0 ]
  [ -f "$NOTIFY_LOG" ]
  grep -qi "REFUSED" "$NOTIFY_LOG"
}

# ── (4) STATE — the fire's cooldown anchor is a claim about a recycle that never happened ────────
@test "refusal: the fire's cooldown anchor is RESTORED, so the desk is not silenced for a non-event" {
  arm_live; mk_actuator 1 '!! --recycle: refusing on a DIRTY git tree'
  # poll 1 = Stage-1 advisory (stamps the cooldown); poll 2 = Stage-2 fire, which re-stamps it "on the FIRE"
  mk_tel r6 60; drive r6 "$(mk_tx r6 "$WAIT")" >/dev/null 2>&1 || true
  local cdf="" pre f
  for f in "$CC_WR_STATE_DIR"/cooldown-*; do [ -f "$f" ] && { cdf="$f"; break; }; done
  [ -n "$cdf" ]; pre="$(cat "$cdf")"
  sleep 1
  mk_tel r6 61; run drive r6 "$(mk_tx r6 "$WAIT")"
  [ "$status" -eq 0 ]
  [ "$(cat "$cdf")" = "$pre" ]                                        # NOT advanced by a fire that never fired
}

# ── (5) THE FOLLOW-ON PAGE — a wedge after a refusal must name the refusal, not a wrong cause ────
@test "refusal: the next wedge page names the REFUSAL, not 'the exec is not armed'" {
  arm_live; mk_actuator 4 '!! recycle REFUSED: in-flight subagent(s) of deadbeef'
  to_stage2 r7 >/dev/null 2>&1 || true
  export CC_WR_COOLDOWN_S=0                                           # clear the pacer so the wedge branch is reachable
  mk_tel r7 62; run drive r7 "$(mk_tx r7 "$WAIT")"                    # next poll: firedf latched, not cooled ⇒ WEDGED
  [ "$status" -eq 0 ]; fired "$output"
  echo "$output" | grep -qi "WEDGED"
  echo "$output" | grep -qi "REFUSED"
  ! echo "$output" | grep -q "the exec is not armed" || false         # the diagnosis that is definitely wrong here
  grep -q '"refused_fire":true' "$CC_WR_IDL"
}

# ── (6) POSITIVE CONTROL — passes on BOTH trees; its green is NOT evidence of the guard ──────────
@test "POSITIVE CONTROL (green on pristine too): rc 0 still reports RECYCLE FIRED, unchanged" {
  arm_live
  local stub="$BATS_TEST_TMPDIR/hf-ok.sh"; ARGREC="$BATS_TEST_TMPDIR/hf-args-ok"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" > %q\nexit 0\n' "$ARGREC" > "$stub"; chmod +x "$stub"
  export CC_WR_HANDOFF_FIRE="$stub"
  run to_stage2 r8
  [ "$status" -eq 0 ]; fired "$output"
  [ -f "$ARGREC" ]; grep -q -- "--recycle" "$ARGREC"; grep -q -- "--prompt-file" "$ARGREC"
  echo "$output" | grep -q "RECYCLE FIRED"
  grep -q '"reason":"stage2-live"' "$CC_WR_IDL"
  grep -q '"verdict":"executed"' "$CC_RECYCLE_EVENTS"
}

# ── (7) VACUOUS ON PRISTINE — asserts an ABSENCE, so pristine passes it for the wrong reason ─────
@test "VACUOUS ON PRISTINE (asserts an absence): rc 0 writes no refusal record and no refused sentinel" {
  arm_live
  local stub="$BATS_TEST_TMPDIR/hf-ok2.sh"
  printf '#!/bin/bash\nexit 0\n' > "$stub"; chmod +x "$stub"
  export CC_WR_HANDOFF_FIRE="$stub"
  run to_stage2 r9
  [ "$status" -eq 0 ]
  [ -z "$(grep '"verdict":"refused"' "$CC_RECYCLE_EVENTS" 2>/dev/null || true)" ]
  [ -z "$(grep 'stage2-refused' "$CC_WR_IDL" 2>/dev/null || true)" ]
  local f sentinel=0
  for f in "$CC_WR_STATE_DIR"/refused-*; do [ -f "$f" ] && sentinel=1; done
  [ "$sentinel" -eq 0 ]
}

# ── (8) HYGIENE — the captured output is bounded and JSON-safe before it reaches the model ───────
@test "refusal: a hostile/huge actuator output cannot break the JSON or leak unbounded into the message" {
  arm_live
  local stub="$BATS_TEST_TMPDIR/hf-hostile.sh"
  # a quote-laden, backtick-laden, 4000-char refusal — the shape that would corrupt an unescaped jq --arg
  printf '#!/bin/bash\nprintf "!! refused: \\"quoted\\" `backtick` $(subst) %%s\\n" "$(head -c 4000 < /dev/zero | tr "\\0" x)" >&2\nexit 4\n' > "$stub"
  chmod +x "$stub"; export CC_WR_HANDOFF_FIRE="$stub"
  run to_stage2 r10
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.decision == "block"' >/dev/null            # still well-formed JSON
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("REFUSED")' >/dev/null
  tail -n1 "$CC_WR_IDL" | jq -e '.refusal | length <= 200' >/dev/null # bounded, not an unbounded stderr tail
}
