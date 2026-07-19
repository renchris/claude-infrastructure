#!/usr/bin/env bats
# waiting-recycle.sh — PostToolUse:Bash hook that advises a purely-WAITING monitoring desk to
# self-recycle (/handoff → handoff-fire.sh --recycle) at a MODERATE context threshold OR on a
# behavioral state-rot tell, firing on the desk's monitoring cadence (not only on Stop).
#
# Coverage: the 4 brief-required cases — (1) threshold fire, (2) behavioral-signal fire,
# (3) safe-hold on open work (dirty tree / open decision), (4) kill-switch (opt-out-by-default +
# global kill) — plus the cross-session cooldown loop-breaker, per-session cap, recycle-machinery
# guard, telemetry freshness, non-repo cwd, the ROT regex corpus (no false-positive on healthy
# monitoring, no ReDoS), every fail-safe path exits 0 silent, the IDL {fired|abstained} record,
# the model-facing additionalContext payload, and the arm/clear/status/kill/unkill CLI.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/waiting-recycle.sh"
  export CC_WR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export CC_WR_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CC_WR_T=55 CC_WR_MAX=3 CC_WR_COOLDOWN_S=600 CC_WR_AGE_MAX=180
  mkdir -p "$CC_TELEMETRY_DIR" "$CC_WR_STATE_DIR"
  # A CLEAN git repo standing in for the desk's monitoring cwd.
  DESK="$BATS_TEST_TMPDIR/desk"; mkdir -p "$DESK"
  git -C "$DESK" init -q
  git -C "$DESK" config user.email t@t; git -C "$DESK" config user.name t
  echo seed > "$DESK/f.txt"; git -C "$DESK" add -A; git -C "$DESK" commit -qm init
  ( cd "$DESK" && bash "$HOOK" arm >/dev/null )    # opt this desk IN (default is off)
}

# Fresh telemetry for a session at $2% fill.
mk_tel() { printf '{"session_id":"%s","ts":%s,"used_pct":%s,"cwd":"%s"}' "$1" "$(date +%s)" "$2" "$DESK" > "$CC_TELEMETRY_DIR/$1.json"; }
# Stale telemetry (age far beyond AGE_MAX).
mk_tel_stale() { printf '{"session_id":"%s","ts":%s,"used_pct":%s,"cwd":"%s"}' "$1" "$(( $(date +%s) - 100000 ))" "$2" "$DESK" > "$CC_TELEMETRY_DIR/$1.json"; }
# Transcript whose LAST assistant message carries $1 as text; echo its path.
mk_tx() { local p="$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}-$1.jsonl"; jq -nc --arg t "$2" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$p"; printf '%s' "$p"; }
# Drive the PostToolUse actuator: $1=sid $2=transcript-path $3=command(optional) $4=cwd(optional).
drive() { printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","tool_input":{"command":"%s"}}' "$1" "$2" "${4:-$DESK}" "${3:-echo poll}" | bash "$HOOK"; }
fired() { echo "$1" | grep -q '"decision":"block"'; }

WAIT="next3 is still running; next4 pinged done. Waiting on the rest."   # benign monitoring narration
ROT="Wait, which sessions did I fire again? Let me reconstruct the state."  # state-rot tell

# ── (1) THRESHOLD FIRE ────────────────────────────────────────────────────────────────────────
@test "threshold: armed + used>=55 + clean + benign msg → fires with a recycle advisory" {
  mk_tel s1 60
  run drive s1 "$(mk_tx 1 "$WAIT")"
  [ "$status" -eq 0 ]; fired "$output"
  echo "$output" | grep -q '"additionalContext"'
  echo "$output" | grep -qi "recycle"
  echo "$output" | grep -q "/handoff"
}
@test "threshold: just below (54 < 55) with no tell → silent" {
  mk_tel s1 54
  run drive s1 "$(mk_tx 1 "$WAIT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── (2) BEHAVIORAL-SIGNAL FIRE (below threshold) ────────────────────────────────────────────────
@test "behavioral: state-rot tell fires even at 40% (below threshold)" {
  mk_tel s2 40
  run drive s2 "$(mk_tx 2 "$ROT")"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "behavioral: normal monitoring narration at 40% → silent (no tell, below threshold)" {
  mk_tel s2 40
  run drive s2 "$(mk_tx 2 "$WAIT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── (3) SAFE-HOLD on genuine in-scope work / open decision ──────────────────────────────────────
@test "safe-hold: dirty tree (uncommitted in-scope work) → silent even at 70%" {
  echo change >> "$DESK/f.txt"                       # uncommitted work in hand
  mk_tel s3 70
  run drive s3 "$(mk_tx 3 "$WAIT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "safe-hold: open decision (your call) in last msg → silent even at 70%" {
  mk_tel s3 70
  run drive s3 "$(mk_tx 3 "Which account should I use for the next fire? Your call.")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "safe-hold: external-info blocker (need your secret) → silent even at 70%" {
  mk_tel s3 70
  run drive s3 "$(mk_tx 3 "I can wire the next fire but I need your API key first.")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── (4) KILL-SWITCH — opt-out-by-default (not armed) + global kill ───────────────────────────────
@test "kill-switch: an UN-armed desk is never recycled (opt-out default)" {
  ( cd "$DESK" && bash "$HOOK" clear >/dev/null )    # opt this desk OUT
  mk_tel s4 88
  run drive s4 "$(mk_tx 4 "$ROT")"                   # even 88% + a rot tell
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "kill-switch: global kill silences every session" {
  bash "$HOOK" kill >/dev/null
  mk_tel s4 88
  run drive s4 "$(mk_tx 4 "$ROT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  bash "$HOOK" unkill >/dev/null                     # and unkill restores firing
  mk_tel s4b 60
  run drive s4b "$(mk_tx 4 "$WAIT")"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── COOLDOWN — cross-session loop-breaker (a fresh recycled desk can't immediately re-recycle) ──
@test "cooldown: after one advisory, a DIFFERENT session in the same cwd is silenced" {
  mk_tel a1 60
  run drive a1 "$(mk_tx 5 "$WAIT")"; fired "$output"       # first advisory stamps the cwd cooldown
  mk_tel a2 92                                              # fresh successor, even higher fill
  run drive a2 "$(mk_tx 5 "$ROT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]                    # within cooldown → held (no recycle→recycle spin)
}

# ── CAP — a wedged single session is never nagged past MAX ──────────────────────────────────────
@test "cap: same session fires up to MAX, then goes silent" {
  export CC_WR_COOLDOWN_S=0                                # isolate the cap from the cooldown gate
  mk_tel c1 60; run drive c1 "$(mk_tx 6 "$WAIT")"; fired "$output"     # 1
  mk_tel c1 61; run drive c1 "$(mk_tx 6 "$WAIT")"; fired "$output"     # 2
  mk_tel c1 62; run drive c1 "$(mk_tx 6 "$WAIT")"; fired "$output"     # 3
  mk_tel c1 63; run drive c1 "$(mk_tx 6 "$WAIT")"                      # 4 → capped
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── RECYCLE-MACHINERY GUARD — never advise-recycle off the recycle path's own Bash calls ─────────
@test "guard: a handoff-fire --recycle command does not trigger a fresh advisory" {
  mk_tel g1 80
  run drive g1 "$(mk_tx 7 "recycling now")" "handoff-fire.sh --recycle"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── TELEMETRY freshness + non-repo cwd ──────────────────────────────────────────────────────────
@test "stale telemetry + no tell → silent (an old % is not evidence of current fill)" {
  mk_tel_stale s8 95
  run drive s8 "$(mk_tx 8 "$WAIT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
# ROT-FLOOR (2026-07-19 Fable panel, probe P1): a rot-tell needs FRESH telemetry AND used_pct ≥
# ROT_FLOOR to count — an un-floored tell false-positives on healthy watch narration, and with the
# deterministic-fire path that becomes a WRONG recycle. This REVERSES the old "rot fires independent
# of telemetry" contract (which was safe only while the hook was advisory-only).
@test "stale telemetry + rot tell → SILENT (rot now requires FRESH telemetry, not a lagging tell)" {
  mk_tel_stale s8 90
  run drive s8 "$(mk_tx 8 "$ROT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "rot-floor: fresh telemetry + rot tell + used BELOW floor (15 < 25) → SILENT (floored out)" {
  mk_tel s8 15
  run drive s8 "$(mk_tx 8 "$ROT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "rot-floor: fresh telemetry + rot tell + used AT floor (25) → fires" {
  mk_tel s8 25
  run drive s8 "$(mk_tx 8 "$ROT")"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "non-repo cwd: armed + over threshold → fires (clean-tree gate is skipped, not failed)" {
  local ND="$BATS_TEST_TMPDIR/notrepo"; mkdir -p "$ND"
  ( cd "$ND" && bash "$HOOK" arm >/dev/null )
  mk_tel s9 70
  # telemetry cwd + JSON cwd both = the non-repo dir
  printf '{"session_id":"s9","ts":%s,"used_pct":70,"cwd":"%s"}' "$(date +%s)" "$ND" > "$CC_TELEMETRY_DIR/s9.json"
  run drive s9 "$(mk_tx 9 "$WAIT")" "echo poll" "$ND"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── ROT REGEX CORPUS — fires on state-rot tells, SILENT on healthy monitoring (false-positive is
#    the dangerous failure: it recycles a healthy desk). Each in its own session; cooldown off. ──
@test "rot corpus: fires on state-rot / memory-loss tells" {
  export CC_WR_COOLDOWN_S=0
  local i=0 msgs=(
    "I've lost track of which sessions are still running."
    "Remind myself what I was monitoring here."
    "What was I waiting on again?"
    "Hmm, I don't recall which teammate owns the money track."
    "Let me re-check which sessions are still outstanding."
    "I'm no longer sure which sessions have pinged back."
    "Let me re-establish the current state of the wave."
    "How many sessions did I launch so far, again?"
    "Not certain what's still running at this point."
  )
  for m in "${msgs[@]}"; do
    i=$((i+1)); mk_tel "rp$i" 30                     # 30% → below threshold, so ONLY the tell can fire
    run drive "rp$i" "$(mk_tx "10p$i" "$m")"
    [ "$status" -eq 0 ]
    if ! fired "$output"; then echo "DID NOT FIRE (rot): $m" >&2; false; fi
  done
}
@test "rot corpus: SILENT on healthy monitoring narration (no false recycle)" {
  export CC_WR_COOLDOWN_S=0
  local i=0 msgs=(
    "next3 is still running; next4 pinged done. Continuing to watch."
    "Let me check the fired sessions for new pings."
    "Polling the mailbox for back-channel pings."
    "The money track committed at abc1234; waiting on the rest."
    "I'll wait for the next ping and re-poll in a bit."
    "Re-running the status check to get fresh data."
    "Let me review the diff before landing."
    "Let me re-run the build now that the fix landed."
    "Session next2 is working; I'll keep monitoring."
    "Checking each session's transcript for the latest state."
  )
  for m in "${msgs[@]}"; do
    i=$((i+1)); mk_tel "rn$i" 30
    run drive "rn$i" "$(mk_tx "10n$i" "$m")"
    [ "$status" -eq 0 ]
    if fired "$output"; then echo "FALSE FIRE (healthy monitoring): $m" >&2; false; fi
  done
}

# ── FAIL-SAFE — every degenerate input exits 0 silent (an advisory must never come from an error) ──
@test "fail-safe: not armed for cwd → silent exit 0" {
  ( cd "$DESK" && bash "$HOOK" clear >/dev/null )
  mk_tel s60 70
  run drive s60 "$(mk_tx 60 "$WAIT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "fail-safe: no session_id → silent exit 0" {
  run bash -c 'printf "{\"cwd\":\"/tmp\"}" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "fail-safe: no/absent cwd → silent exit 0" {
  run bash -c 'printf "{\"session_id\":\"x\",\"cwd\":\"/no/such/dir\"}" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "fail-safe: garbage stdin → silent exit 0" {
  run bash -c 'printf "not json at all" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "fail-safe: empty stdin → silent exit 0" {
  run bash -c 'printf "" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "fail-safe: no telemetry + no tell → silent (nothing to trigger on)" {
  run drive nosuch "$(mk_tx 61 "$WAIT")"             # no tel/nosuch.json written
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── IDL — one {fired|abstained} record per invocation (didn't-fire ≠ never-evaluated) ────────────
@test "IDL: a fire writes a fired record with the trigger" {
  mk_tel s70 60
  run drive s70 "$(mk_tx 70 "$WAIT")"
  grep -q '"disposition":"fired"' "$CC_WR_IDL"
  grep -q '"hook":"waiting-recycle"' "$CC_WR_IDL"
}
@test "IDL: a below-threshold poll writes an abstained record" {
  mk_tel s71 40
  run drive s71 "$(mk_tx 71 "$WAIT")"
  grep -q '"disposition":"abstained"' "$CC_WR_IDL"
  grep -q '"reason":"below-threshold-no-tell' "$CC_WR_IDL"
}

# ── model-facing advisory: additionalContext points at the reuse path, reason is user-facing ─────
@test "advisory: additionalContext names /handoff, handoff-fire --recycle, and the kill-switch" {
  mk_tel s80 66
  run drive s80 "$(mk_tx 80 "$WAIT")"
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  echo "$ctx" | grep -q "/handoff"
  echo "$ctx" | grep -q "handoff-fire.sh --recycle"
  echo "$ctx" | grep -qi "waiting-recycle.sh clear"
  echo "$output" | jq -e '.decision=="block"' >/dev/null
}

# ── DoD carry (T-P4-4): the advisory carries the frozen mission line for the successor ───────────
@test "dod-carry: advisory carries the frozen DoD line when one is recorded" {
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/dod.md"
  printf 'Scope (frozen): drive PLAN.md — carry me across the recycle\n' > "$WRAP_DOD_FILE"
  mk_tel sd 60
  run drive sd "$(mk_tx 90 "$WAIT")"
  [ "$status" -eq 0 ]; fired "$output"
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  echo "$ctx" | grep -q "MISSION TO CARRY"
  echo "$ctx" | grep -q "carry me across the recycle"
}
@test "dod-carry: no DoD recorded → advisory still fires, no MISSION line (graceful degrade)" {
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/empty-dod.md"; : > "$WRAP_DOD_FILE"
  mk_tel se 60
  run drive se "$(mk_tx 91 "$WAIT")"
  [ "$status" -eq 0 ]; fired "$output"
  ctx="$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [ -z "$(printf '%s' "$ctx" | grep 'MISSION TO CARRY' || true)" ]
}

# ── CLI — arm / clear / status / kill / unkill ──────────────────────────────────────────────────
@test "cli: arm then status reports ARMED; clear then status reports not armed" {
  ( cd "$DESK" && run bash "$HOOK" status ) # armed in setup
  ( cd "$DESK" && bash "$HOOK" status ) | grep -q "ARMED"
  ( cd "$DESK" && bash "$HOOK" clear >/dev/null )
  ( cd "$DESK" && bash "$HOOK" status ) | grep -q "not armed"
}
@test "cli: kill then status reports GLOBAL KILL; unkill clears it" {
  bash "$HOOK" kill >/dev/null
  ( cd "$DESK" && bash "$HOOK" status ) | grep -q "GLOBAL KILL"
  bash "$HOOK" unkill >/dev/null
  run bash -c '( cd "$1" && bash "$2" status ) | grep -c "GLOBAL KILL"' _ "$DESK" "$HOOK"
  [ "$output" -eq 0 ]
}
