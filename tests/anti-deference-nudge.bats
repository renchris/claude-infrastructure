#!/usr/bin/env bats
# anti-deference-nudge.sh — Stop hook that blocks the deference reflex (presenting drivable,
# pre-authorized work as a question/hold) and corrects it toward DRIVING.
#
# RED-proof coverage: fires on every listed tell; SILENT on clean answers, on genuine-STOP-ASK
# (the legitimate three + escalation surfaces), and on substring traps; the latch blocks a
# re-fire on identical content; the hard cap halts after N; every fail-safe path exits 0 silent;
# one IDL {fired|abstained} line per invocation; the block reason carries the corrective.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/anti-deference-nudge.sh"
  export ANTIDEF_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export ANTIDEF_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export ANTIDEF_MAX=3
}

# Build a transcript whose LAST assistant message carries $1 as text; echo its path.
mkfix() {
  local text="$1" path="${2:-$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}-$RANDOM.jsonl}"
  jq -nc --arg t "$text" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$path"
  printf '%s' "$path"
}

# Drive the hook with a transcript + session id (distinct sid ⇒ isolated latch/cap).
runhook() {
  local tx="$1" sid="${2:-sid-$RANDOM}"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"/tmp/adf"}' "$sid" "$tx" | bash "$HOOK"
}

fired()  { echo "$1" | grep -q '"decision":"block"'; }   # hook stdout ⇒ did it block?

# ── Fires on EVERY listed deference tell (each in its own session so cap/latch don't interfere) ──
@test "fires on every listed deference tell" {
  local msgs=(
    "The migration is ready. Say the word and I'll apply it."                 # say the word
    "I've drafted everything — on your word I'll land it."                     # on your word
    "I've finished the refactor. Want me to run the tests next?"              # want me to
    "Shall I proceed with wiring the remaining hooks?"                        # shall I
    "Should I proceed with the cleanup?"                                     # should I proceed
    "Should I go ahead and commit the changes?"                              # should I go
    "Should I do the same for the other four files?"                         # should I do
    "Let me know if you want the coverage expanded."                         # let me know if you
    "Holding for your review before I continue."                             # holding for your
    "Everything's staged. Otherwise I'll hold until you confirm."            # otherwise I'll hold
    "I'll wait on your steer for the final wording."                         # your steer
    "Do you want me to also update the docs?"                                # do you want me to
    "Awaiting your confirmation to continue with the tests."                 # awaiting your
    "I can land it now — otherwise I'll wait for your nod."                  # I can X it — otherwise I
  )
  for m in "${msgs[@]}"; do
    local tx; tx="$(mkfix "$m")"
    run runhook "$tx"
    [ "$status" -eq 0 ]
    if ! fired "$output"; then echo "DID NOT FIRE (should have): $m" >&2; false; fi
  done
}

# ── SILENT on clean answers / completions (no tell) ──
@test "silent on a clean completion" {
  run runhook "$(mkfix "Done. All 12 tests pass, shellcheck clean, wired into all 5 config dirs. Landed at abc1234.")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "silent on a plain informational answer" {
  run runhook "$(mkfix "The hook fires on the Stop event and reads the transcript path from stdin.")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── SILENT on a genuine STOP-ASK even though a tell is present (the three-genuine carve-out) ──
@test "silent: external-info blocker (need your secret) + tell" {
  run runhook "$(mkfix "I can wire OAuth, but I need your Google client secret first — do you want me to scaffold the rest?")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "silent: which-account external-info + tell" {
  run runhook "$(mkfix "Which account should I use for this? Want me to default to next2?")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "silent: value-fork (which do you prefer) + tell" {
  run runhook "$(mkfix "Session cookies vs JWT — which do you prefer? Want me to sketch both?")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "silent: C10 permission (push is your call) + tell" {
  run runhook "$(mkfix "Committed on the branch. Pushing to main is your call — do you want me to open a PR?")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "silent: escalation surface (destructive migration) + tell" {
  run runhook "$(mkfix "This requires a destructive migration (DROP TABLE users_old). Should I proceed?")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "silent: sudo / interactive login (run it yourself) + tell" {
  run runhook "$(mkfix "You'll need to run gcloud auth login yourself — should I proceed with the rest?")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── SILENT on substring / boundary traps (must not match the tells) ──
@test "silent: 'should i download' does not match 'should i do'" {
  run runhook "$(mkfix "Should I download the larger dataset for this analysis?")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "silent: 'want to' does not match 'want me to'" {
  run runhook "$(mkfix "You might want to review the diff before we land.")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "silent: 'otherwise the code' does not match the otherwise-hold tell" {
  run runhook "$(mkfix "I can explain it — otherwise the code is fairly self-documenting.")"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── LATCH: identical content never re-fires (kills the block→identical-reply→block loop) ──
@test "latch: fires once, then silent on identical content" {
  local tx; tx="$(mkfix "Want me to run the full suite now?")"
  run runhook "$tx" "latch-sess"
  [ "$status" -eq 0 ]; fired "$output"
  run runhook "$tx" "latch-sess"          # same session, same message hash
  [ "$status" -eq 0 ]; [ -z "$output" ]   # latched → silent
}

# ── CAP: halts after ANTIDEF_MAX distinct defers (paraphrase-loop backstop; never wedge) ──
@test "cap: distinct defers fire up to the cap then go silent" {
  export ANTIDEF_MAX=2
  run runhook "$(mkfix "Want me to run the tests?")"      "cap-sess"; fired "$output"
  run runhook "$(mkfix "Shall I proceed with the wire?")" "cap-sess"; fired "$output"
  run runhook "$(mkfix "Should I go ahead and commit?")"  "cap-sess"
  [ "$status" -eq 0 ]; [ -z "$output" ]   # 3rd distinct defer → capped → silent
}

# ── FAIL-SAFE: every degenerate input exits 0 silent (a block must never come from an error) ──
@test "fail-safe: missing transcript_path → silent exit 0" {
  run bash -c 'printf "{\"session_id\":\"x\",\"cwd\":\"/tmp\"}" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "fail-safe: nonexistent transcript → silent exit 0" {
  run bash -c 'printf "{\"transcript_path\":\"/no/such/file.jsonl\"}" | bash "$1"' _ "$HOOK"
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
@test "fail-safe: last assistant turn has no text (tool_use only) → silent" {
  local tx="$BATS_TEST_TMPDIR/toolonly.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{}}]}}' > "$tx"
  run runhook "$tx"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── IDL: exactly one {fired|abstained} record per invocation (B-3: didn't-fire ≠ never-evaluated) ──
@test "IDL: fire writes a fired record with the tell" {
  run runhook "$(mkfix "Want me to run the tests next?")"
  grep -q '"disposition":"fired"' "$ANTIDEF_IDL"
  grep -q '"hook":"anti-deference-nudge"' "$ANTIDEF_IDL"
}
@test "IDL: a clean answer writes an abstained record" {
  run runhook "$(mkfix "Done — landed at abc1234, all green.")"
  grep -q '"disposition":"abstained"' "$ANTIDEF_IDL"
  grep -q '"reason":"no-tell"' "$ANTIDEF_IDL"
}

# ── The block reason carries the corrective + the matched tell ──
@test "reason: names the defect, the DRIVE directive, and the matched tell" {
  run runhook "$(mkfix "Want me to wire it into settings next?")"
  echo "$output" | grep -q "Anti-deference"
  echo "$output" | grep -q "DRIVE it now"
  echo "$output" | grep -qi "want me to"
}
