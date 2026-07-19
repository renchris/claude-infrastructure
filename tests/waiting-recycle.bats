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
  # Hermetic coordination root (S3 wait-contracts / S4 mailbox / S5 teams / cc-roles) — never the real ~/.claude.
  export CC_WR_COORD_DIR="$BATS_TEST_TMPDIR/coord"; export CC_WR_UUID="DESK-UUID-0001"; export CC_WR_QUIET_S=180
  mkdir -p "$CC_TELEMETRY_DIR" "$CC_WR_STATE_DIR" "$CC_WR_COORD_DIR/wait-contracts" "$CC_WR_COORD_DIR/mailbox" "$CC_WR_COORD_DIR/cc-roles" "$CLAUDE_CONFIG_DIR/teams"
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

# ── (5) SAFE-HOLD on mid-merge + active-coordination (Fable panel S1/S3/S4/S5, 2026-07-19) ─────────
# helpers: write an OPEN wait-contract / a mailbox line / a team config into the hermetic coord root
mk_contract() { # $1=id $2=waitee $3=deadline-epoch $4=waiter_pid $5=status
  jq -nc --arg w "$2" --arg s "${5:-OPEN}" --argjson dl "$3" --argjson wp "$4" \
    '{id:"c",waiter:"peer",waiter_pid:$wp,waitee:$w,expected_signal:"x",deadline:$dl,status:$s}' \
    > "$CC_WR_COORD_DIR/wait-contracts/$1.json"; }

@test "S1 sequencer-state: clean tree but MERGE_HEAD present → HOLD even at 70% (mid-merge)" {
  : > "$DESK/.git/MERGE_HEAD"
  mk_tel s5a 70
  run drive s5a "$(mk_tx 5 "$WAIT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "S3 inbound-wait: a peer OPEN-blocked on THIS desk (live waiter, future deadline) → HOLD" {
  mk_contract wc1 "$CC_WR_UUID" "$(( $(date +%s) + 600 ))" "$$" OPEN
  mk_tel s5b 70
  run drive s5b "$(mk_tx 5 "$WAIT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "S3 negative: the desk's OWN waiter-contract (waitee is a PEER) does NOT hold → fires" {
  mk_contract wc2 "some-peer-session" "$(( $(date +%s) + 600 ))" "$$" OPEN
  mk_tel s5c 70
  run drive s5c "$(mk_tx 5 "$WAIT")"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "S3 zombie: OPEN contract on me but DEAD waiter_pid → not a live block → fires" {
  mk_contract wc3 "$CC_WR_UUID" "$(( $(date +%s) + 600 ))" 999999 OPEN
  mk_tel s5d 70
  run drive s5d "$(mk_tx 5 "$WAIT")"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "S3 past-deadline: OPEN contract on me but deadline PAST → not a live block → fires" {
  mk_contract wc4 "$CC_WR_UUID" "$(( $(date +%s) - 10 ))" "$$" OPEN
  mk_tel s5e 70
  run drive s5e "$(mk_tx 5 "$WAIT")"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "S4 mailbox: a FRESH inbound line for this desk → HOLD (a peer just reached for me)" {
  : > "$CC_WR_COORD_DIR/mailbox/$CC_WR_UUID.md"
  mk_tel s5f 70
  run drive s5f "$(mk_tx 5 "$WAIT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "S4 negative: a STALE mailbox (older than QUIET_S) does NOT hold → fires" {
  local mb="$CC_WR_COORD_DIR/mailbox/$CC_WR_UUID.md"; : > "$mb"
  touch -t 200001010000 "$mb"                                   # ancient
  mk_tel s5g 70
  run drive s5g "$(mk_tx 5 "$WAIT")"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "S5 teammate hard-hold: a team dir created by this SID → HOLD (results route to dying SID)" {
  mkdir -p "$CLAUDE_CONFIG_DIR/teams/session-s5h1234"
  echo '{"members":[{"name":"team-lead"},{"name":"worker-1"}]}' > "$CLAUDE_CONFIG_DIR/teams/session-s5h1234/config.json"
  mk_tel s5h1234 70
  run drive s5h1234 "$(mk_tx 5 "$WAIT")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── (6) STAGE 2 — deterministic fire (advisory → K=1 escalation), shadow-default ──────────────────
# GRACE_S=0 ⇒ poll 1 sets the grace clock (advisory), poll 2 escalates to Stage 2.
setup_stage2() { export CC_WR_GRACE_S=0; export CC_WR_FIRE_DIR="$BATS_TEST_TMPDIR/fire"; mkdir -p "$CC_WR_FIRE_DIR"; }

@test "stage2 SHADOW: advisory then escalates to a would-fire (logs stage2-shadow, composes brief, no exec)" {
  setup_stage2
  mk_tel s6 60; run drive s6 "$(mk_tx 6 "$WAIT")"; fired "$output"          # poll 1 = advisory (grace clock)
  mk_tel s6 61; run drive s6 "$(mk_tx 6 "$WAIT")"                           # poll 2 = Stage 2 (grace elapsed)
  [ "$status" -eq 0 ]; fired "$output"
  echo "$output" | grep -qi "SHADOW"
  grep -q 'stage2-shadow' "$CC_WR_IDL"
  [ -s "$CC_WR_FIRE_DIR/wr-fire-s6.txt" ]                                   # brief composed, non-empty (no FM-D)
  grep -q "re-derive live watch state" "$CC_WR_FIRE_DIR/wr-fire-s6.txt"
}
@test "stage2 SHADOW: exemption — fires despite an active cwd cooldown (cap/cooldown are Stage-1 only)" {
  setup_stage2                                                             # COOLDOWN_S stays 600 (default)
  mk_tel s6x 60; run drive s6x "$(mk_tx 6 "$WAIT")"; fired "$output"       # advisory stamps the cooldown
  mk_tel s6x 61; run drive s6x "$(mk_tx 6 "$WAIT")"                        # still fires (Stage 2 is cooldown-exempt)
  [ "$status" -eq 0 ]; fired "$output"; echo "$output" | grep -qi "SHADOW"
}
@test "stage2 SHADOW: composed brief carries the frozen DoD when one is recorded" {
  setup_stage2
  export DOD_PERSIST="$BATS_TEST_TMPDIR/dod.sh"
  printf '#!/bin/bash\necho "SHIP the thing to 100/100"\n' > "$DOD_PERSIST"; chmod +x "$DOD_PERSIST"
  mk_tel s6b 60; run drive s6b "$(mk_tx 6 "$WAIT")"
  mk_tel s6b 61; run drive s6b "$(mk_tx 6 "$WAIT")"
  grep -q "Scope (frozen): SHIP the thing to 100/100" "$CC_WR_FIRE_DIR/wr-fire-s6b.txt"
}
@test "stage2 one-fire-per-SID: after a fire, the next poll is silent (already-fired latch)" {
  setup_stage2; export CC_WR_COOLDOWN_S=0                                   # isolate the latch from the cooldown
  mk_tel s6c 60; run drive s6c "$(mk_tx 6 "$WAIT")"                         # advisory
  mk_tel s6c 61; run drive s6c "$(mk_tx 6 "$WAIT")"; fired "$output"        # shadow fire (latch set)
  mk_tel s6c 62; run drive s6c "$(mk_tx 6 "$WAIT")"                         # next poll → already-fired
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q 'already-fired' "$CC_WR_IDL"
}
@test "stage2 grace: within the grace window it stays an ADVISORY (does not fire yet)" {
  export CC_WR_GRACE_S=9999 CC_WR_COOLDOWN_S=0 CC_WR_FIRE_DIR="$BATS_TEST_TMPDIR/fire"; mkdir -p "$CC_WR_FIRE_DIR"
  mk_tel s6d 60; run drive s6d "$(mk_tx 6 "$WAIT")"; fired "$output"        # advisory 1
  mk_tel s6d 61; run drive s6d "$(mk_tx 6 "$WAIT")"                         # poll 2: grace not elapsed → advisory
  [ "$status" -eq 0 ]; fired "$output"
  ! echo "$output" | grep -qi "SHADOW"
  ! grep -q 'stage2' "$CC_WR_IDL"
}
@test "stage2 LIVE: arm --brief --live → escalation EXECS handoff-fire --recycle --prompt-file" {
  setup_stage2
  local stub="$BATS_TEST_TMPDIR/hf-stub.sh" rec="$BATS_TEST_TMPDIR/hf-args"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" > %q\n' "$rec" > "$stub"; chmod +x "$stub"
  export CC_WR_HANDOFF_FIRE="$stub"
  local tmpl="$BATS_TEST_TMPDIR/brief.txt"; echo "resume desk monitoring from disk" > "$tmpl"
  ( cd "$DESK" && bash "$HOOK" arm --brief "$tmpl" --live >/dev/null )
  mk_tel s6e 60; run drive s6e "$(mk_tx 6 "$WAIT")"                         # advisory
  mk_tel s6e 61; run drive s6e "$(mk_tx 6 "$WAIT")"                         # Stage 2 LIVE
  [ "$status" -eq 0 ]
  [ -f "$rec" ]                                                             # actuator invoked
  grep -q -- "--recycle" "$rec"; grep -q -- "--prompt-file" "$rec"
  grep -q 'stage2-live' "$CC_WR_IDL"
  grep -q "resume desk monitoring from disk" "$CC_WR_FIRE_DIR/wr-fire-s6e.txt"   # used the --brief template
}
@test "arm --live without a brief template is REFUSED (no empty-payload fire, FM-D)" {
  run bash -c "cd '$DESK' && CC_WR_STATE_DIR='$CC_WR_STATE_DIR' bash '$HOOK' arm --live"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi "requires a non-empty --brief"
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

# ── RED-prove (cc-backlog 666c6a64c45e): a " / backslash in a logged field must never emit a
#    MALFORMED IDL line — one aborts the cc-audit four-zeros `jq -rs` slurp (⇒ D9/alarm silent-GREEN,
#    defeating the un-gameable detector). jq-encoding fixes it. A bad cwd hits the no-cwd abstain so
#    log_idl runs with SID carrying the injected chars. FAILS on the old raw-%s emit, PASSES now. ──
@test "IDL: a quote/backslash-bearing session_id yields a strict-slurp-parseable, lossless line" {
  local input; input="$(jq -nc '{session_id:"s\"q\\z",cwd:"/no/such/dir"}')"   # bad cwd ⇒ abstain no-cwd logs
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$input" "$HOOK"
  [ "$status" -eq 0 ]
  run jq -s '.' "$CC_WR_IDL"
  [ "$status" -eq 0 ]
  jq -e 'select(.sid=="s\"q\\z")' "$CC_WR_IDL" >/dev/null
}
