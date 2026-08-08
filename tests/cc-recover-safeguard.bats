#!/usr/bin/env bats
# cc-recover-safeguard — RED-proof the recovery of a safeguard-blocked fired peer. The tested contract
# is COMMAND CONSTRUCTION: the re-fire swaps to a DIFFERENT model, the self-close carries a succession
# statement, and the brief is carried VERBATIM. Live orchestration (execute) is exercised with mocked
# handoff-fire + cc-sessions (no real fire, no real pane close). All inputs are env-seamed — nothing
# touches the real registry / transcripts / iTerm2.

setup() {
  # M11 (MACHINE_CAPACITY_V2 §11.3) — a test's environment is PINNED, not ambient. handoff-fire.sh's
  # capacity_gate reads the box's live loadavg AND (M10) its memory headroom, exiting 9 when either is
  # past its bar, so an unpinned suite goes RED purely because the box is busy — the corpus deciding a
  # verdict on machine state instead of on the tree. Both terms are pinned off here (they are the two
  # TERMS of one exit 9, handoff-fire.sh:4487); tests/handoff-fire-capacity-gate.bats is the ONE place
  # the gate runs ON, against synthetic inputs.
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-recover-safeguard"
  D="$BATS_TEST_TMPDIR"; mkdir -p "$D/bin" "$D/reg" "$D/fired" "$D/proj/slug" "$D/bcwd"
  BPANE="2BE82E97-1111-4222-8333-444455556666"
  BCWD="$D/bcwd"; BSID="blockedsid"
  ORIG="0R161N00-1111-4222-8333-444455556666"
  NEWPANE="9EF00000-1111-4222-8333-444455556666"
  # registry row for the blocked pane (cwd / account / session_id)
  jq -nc --arg p "$BPANE" --arg c "$BCWD" --arg s "$BSID" \
     '{paneUUID:$p,cwd:$c,account:"claude-quaternary",session_id:$s}' > "$D/reg/$BPANE.json"
  # persisted fired brief (PRIMARY source) — apostrophe in the body proves verbatim carry
  printf 'ORIGINAL BRIEF line 1\nline 2 apostrophe: can'"'"'t stop me\n' > "$D/fired/$BPANE.prompt"
  # fired marker with the firedBy ORIGINATOR
  jq -nc --arg p "$BPANE" --arg c "$BCWD" --arg by "$ORIG" \
     '{paneUUID:$p,cwd:$c,firedBy:$by,firedAt:"2026-07-25T09:00:00Z",selfRetire:true}' > "$D/fired/$BPANE.json"
  # transcript: a Fable refusal (for the blocked-model parse) + a user brief (the FALLBACK source)
  jq -nc '{type:"user",isMeta:false,timestamp:"2026-07-25T09:00:00Z",message:{role:"user",content:"TRANSCRIPT BRIEF BODY\nsecond line"}}' > "$D/proj/slug/$BSID.jsonl"
  jq -nc '{type:"assistant",isApiErrorMessage:true,timestamp:"2026-07-25T09:00:01Z",message:{role:"assistant",content:[{type:"text",text:"API Error: Fable 5'"'"'s safeguards flagged this message. Claude Code can'"'"'t respond to this request with Fable 5."}]}}' >> "$D/proj/slug/$BSID.jsonl"
  # cc-sessions mock reads a mutable file (the fire "creates" a new session by appending to it)
  printf '[{"paneUUID":"%s","cwd":"%s","account":"claude-quaternary","session_id":"%s"}]\n' "$BPANE" "$BCWD" "$BSID" > "$D/sessions.json"
  printf '#!/bin/bash\n[ "$1" = --json ] && cat "%s"\n' "$D/sessions.json" > "$D/bin/sessions"
  # handoff-fire stub: records argv; a --prompt-file (re-fire) invocation "creates" a new session in BCWD
  cat > "$D/bin/handoff" <<EOF
#!/bin/bash
echo "HANDOFF \$*" >> "$D/handoff-calls"
if printf '%s ' "\$@" | grep -q -- '--prompt-file'; then
  jq '. += [{"paneUUID":"$NEWPANE","cwd":"$BCWD","account":"next","session_id":"newsid"}]' "$D/sessions.json" > "$D/sessions.json.t" && mv "$D/sessions.json.t" "$D/sessions.json"
fi
exit \${HANDOFF_RC:-0}
EOF
  printf '#!/bin/bash\necho "NOTIFY $*" >> "%s"\n' "$D/notify-calls" > "$D/bin/notify"
  chmod +x "$D/bin/sessions" "$D/bin/handoff" "$D/bin/notify"
  export CC_RECOVER_REG_DIR="$D/reg" CC_FIRED_DIR="$D/fired" CC_RECOVER_PROJECT_ROOTS="$D/proj"
  export CC_RECOVER_SESSIONS_BIN="$D/bin/sessions" CC_RECOVER_HANDOFF_BIN="$D/bin/handoff" CC_RECOVER_NOTIFY_BIN="$D/bin/notify"
  export CC_RECOVER_WAIT_TRIES=3 CC_RECOVER_WAIT_S=0
}
# extract the reworded-brief path the dry-run printed
reworded_path() { printf '%s\n' "$1" | sed -n 's/^reworded brief: //p' | head -1; }

@test "dry-run: re-fire swaps to a DIFFERENT model (Fable blocked → opus) with --prompt-file/--cwd/--no-self-retire" {
  run "$C" "$BPANE" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^target model:   opus'
  echo "$output" | grep -qE -- '--prompt-file .+ --model opus --cwd .+ --no-self-retire'
}

@test "dry-run: self-close carries the pane + a succession statement (--terminal)" {
  run "$C" "$BPANE" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE "self-close --session-id $BPANE --terminal"
}

@test "dry-run: the brief is carried VERBATIM (re-route note prepended to the original)" {
  run "$C" "$BPANE" --dry-run
  [ "$status" -eq 0 ]
  RW="$(reworded_path "$output")"; [ -f "$RW" ]
  head -1 "$RW" | grep -q 'RE-ROUTED'                                  # note prepended
  grep -qF "line 2 apostrophe: can't stop me" "$RW"                    # original brief carried verbatim (apostrophe intact)
  grep -qF 'ORIGINAL BRIEF line 1' "$RW"
}

@test "dry-run: touches nothing (handoff-fire never invoked)" {
  run "$C" "$BPANE" --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$D/handoff-calls" ]                                          # no fire, no close
  [ ! -f "$D/notify-calls" ]
}

@test "dry-run: explicit --model overrides the default target" {
  run "$C" "$BPANE" --model haiku --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^target model:   haiku'
  echo "$output" | grep -qE ' --model haiku '
}

@test "dry-run: an OPUS-blocked session swaps to sonnet (never re-fires the blocked model)" {
  # rewrite the transcript refusal to an Opus block
  jq -nc '{type:"assistant",isApiErrorMessage:true,timestamp:"2026-07-25T09:00:01Z",message:{role:"assistant",content:[{type:"text",text:"API Error: Opus 4.8'"'"'s safeguards flagged this message. Claude Code can'"'"'t respond to this request with Opus 4.8."}]}}' > "$D/proj/slug/$BSID.jsonl"
  run "$C" "$BPANE" --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '^blocked model:  Opus 4.8'
  echo "$output" | grep -qE '^target model:   sonnet'
}

@test "brief source: the persisted .prompt is preferred; falls back to the transcript when absent" {
  run "$C" "$BPANE" --dry-run                                          # .prompt present
  echo "$output" | grep -qE '^brief source:   .*/fired/'
  RW="$(reworded_path "$output")"; grep -qF 'ORIGINAL BRIEF line 1' "$RW"
  rm -f "$D/fired/$BPANE.prompt"                                       # remove persisted brief
  run "$C" "$BPANE" --dry-run
  echo "$output" | grep -qE '^brief source:   transcript:'
  RW="$(reworded_path "$output")"; grep -qF 'TRANSCRIPT BRIEF BODY' "$RW"
}

@test "no brief anywhere → loud refuse (exit 4), nothing fired" {
  rm -f "$D/fired/$BPANE.prompt" "$D/proj/slug/$BSID.jsonl"
  run "$C" "$BPANE" --execute
  [ "$status" -eq 4 ]
  [ ! -f "$D/handoff-calls" ]
}

@test "unresolvable pane (no registry / not a live session) → exit 3" {
  rm -f "$D/reg/$BPANE.json"; printf '[]\n' > "$D/sessions.json"
  run "$C" "$BPANE" --execute
  [ "$status" -eq 3 ]
  [ ! -f "$D/handoff-calls" ]
}

@test "a non-UUID pane arg is refused (exit 2)" {
  run "$C" "../../etc/pwned" --dry-run
  [ "$status" -eq 2 ]
}

@test "execute: re-fires FIRST then self-closes with --successor (safe order, sanctioned close)" {
  run "$C" "$BPANE" --execute
  [ "$status" -eq 0 ]
  [ -f "$D/handoff-calls" ]
  # the re-fire line comes before the self-close line (re-fire first = never destroy before the replacement launches)
  grep -n 'HANDOFF' "$D/handoff-calls" | head -1 | grep -q -- '--prompt-file'
  grep -q -- "self-close --session-id $BPANE --successor $NEWPANE --dirty-owner successor" "$D/handoff-calls"
  grep -q "NOTIFY $ORIG" "$D/notify-calls"                            # originator told recovery happened
}

@test "execute: a FAILED re-fire preserves the blocked pane (never self-closed)" {
  export HANDOFF_RC=7                                                  # the re-fire fails
  run "$C" "$BPANE" --execute
  [ "$status" -eq 5 ]
  grep -q -- '--prompt-file' "$D/handoff-calls"                       # re-fire was attempted
  ! grep -q 'self-close' "$D/handoff-calls"                           # blocked pane NOT closed
}
