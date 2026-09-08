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
  export WRAP_TRUNK="origin/main"
  # T-P15-5: sandbox the decision-packet side effect so the genuine-3 → packet exit writes to a
  # per-test dir (never the real ~/.claude/autonomy/decisions or the 165MB live IDL).
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_IDL="$BATS_TEST_TMPDIR/cc-idl.jsonl"
}

# ── git fixtures for the P0-4 (b)/(c) ledger-aware paths (bare origin + working clone) ──
mkrepo_landed() {   # clean, HEAD == origin/main (nothing to drive)
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w"
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
}
mkrepo_unlanded() { # clean tree, one commit ahead of origin/main ⇒ push/land is DRIVABLE
  local w; w="$(mkrepo_landed "$1")"
  ( cd "$w"; echo x > x.txt; git add x.txt; git commit -q -m "unlanded verified work" ) >/dev/null 2>&1
  printf '%s' "$w"
}
mkrepo_dirty() {    # uncommitted changes ⇒ NOT drivable (carve-out preserved)
  local w; w="$(mkrepo_landed "$1")"
  ( cd "$w"; echo dirt >> base.txt ) >/dev/null 2>&1
  printf '%s' "$w"
}
# transcript with the real deference text buried under a tool_use-only turn, a sidechain turn,
# and a metadata tail (the G-P11-1 343c6e77 shape) — extractor must WALK BACK to the main text.
mkfix_tail() {
  local text="$1" path="$BATS_TEST_TMPDIR/txt-${BATS_TEST_NUMBER}-$RANDOM.jsonl"
  {
    jq -nc --arg t "$text" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'
    jq -nc '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{}}]}}'
    jq -nc '{type:"assistant",isSidechain:true,message:{content:[{type:"text",text:"subagent chatter"}]}}'
    jq -nc '{type:"system",subtype:"mode",mode:"acceptEdits"}'
  } > "$path"
  printf '%s' "$path"
}
runhook_at() { # $1=transcript $2=cwd $3=sid  — drive the hook with a real git cwd
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "${3:-sid-$RANDOM}" "$1" "$2" | bash "$HOOK"
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

# Same drive, but with EVERY locale variable stripped — the shape launchd hands an unattended job
# (its plists set no LANG), and therefore the shape postland-verify runs the corpus under. Kept as
# a separate helper rather than a flag on runhook: the ambient locale is what made the C-locale
# defect invisible to every other assertion in this file, so the pinned cases must say so by name.
runhook_nolocale() {
  local tx="$1" sid="${2:-sid-$RANDOM}"
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"/tmp/adf"}' "$sid" "$tx" \
    | env -u LANG -u LC_ALL -u LC_CTYPE bash "$HOOK"
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

# ══ P0-4 (a): main-agent-scoped extraction — walk back past tool_use/sidechain/metadata tail ══
@test "P0-4a: fires on a deference tell buried under a tool_use/sidechain/metadata tail" {
  # current tail-1 extraction grabs the metadata/sidechain tail → abstains no-assistant-text (RED)
  run runhook_at "$(mkfix_tail "The rest is drafted. Want me to wire it in?")" "/tmp/adf"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "P0-4a: a sidechain-only final text does not mask the main agent's deference" {
  local tx="$BATS_TEST_TMPDIR/side.jsonl"
  jq -nc '{type:"assistant",message:{content:[{type:"text",text:"Shall I proceed with the wiring?"}]}}'  > "$tx"
  jq -nc '{type:"assistant",isSidechain:true,message:{content:[{type:"text",text:"(subagent) inspecting files"}]}}' >> "$tx"
  run runhook_at "$tx" "/tmp/adf"
  [ "$status" -eq 0 ]; fired "$output"
}

# ══ P0-4 (b): ship/land carve-out is CONDITIONAL — drivable (clean ∧ own commits) ⇒ FIRE ══
@test "P0-4b: 'Pushing to main is your call' FIRES over clean+own-commits (ship not genuine)" {
  local w; w="$(mkrepo_unlanded pb)"
  # current blanket carve-out abstains genuine-blocker (RED); narrowed version fires
  run runhook_at "$(mkfix "Committed on the branch. Pushing to main is your call — say the word to land.")" "$w" "pb-s"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "P0-4b: verbatim 'say the word (/ship or push)' FIRES over clean+own-commits" {
  local w; w="$(mkrepo_unlanded pbv)"
  run runhook_at "$(mkfix "📦 Done, but only on a branch. Say the word (/ship or push) to land it.")" "$w" "pbv-s"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "P0-4b: carve-out PRESERVED when NOT drivable (dirty tree) — 'pushing is your call' abstains" {
  local w; w="$(mkrepo_dirty pbd)"
  run runhook_at "$(mkfix "Pushing to main is your call — do you want me to open a PR?")" "$w" "pbd-s"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "P0-4b: a true value-fork 'your call' with NO ship verb stays genuine (abstains)" {
  local w; w="$(mkrepo_unlanded pbf)"
  run runhook_at "$(mkfix "Session cookies vs JWT for the token store — your call. Want me to sketch both?")" "$w" "pbf-s"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ══ P0-4 (c): confident false-DONE assertions fire ONLY when the live ledger contradicts ══
@test "P0-4c: 'Complete — nothing to do' FIRES over committed-but-unlanded work" {
  local w; w="$(mkrepo_unlanded pc)"
  # current TELLS has no done-assertion → abstains no-tell (RED); (c) fires on ledger contradiction
  run runhook_at "$(mkfix "Complete — nothing to do.")" "$w" "pc-s"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "P0-4c: 'Everything requested is done' FIRES over a frozen-DoD remainder" {
  local w; w="$(mkrepo_landed pcr)"
  local dod="$BATS_TEST_TMPDIR/dod-pcr.md"; printf -- '- [x] a\n- [ ] b\n' > "$dod"
  export WRAP_DOD_FILE="$dod"
  run runhook_at "$(mkfix "Everything requested is done.")" "$w" "pcr-s"
  [ "$status" -eq 0 ]; fired "$output"
}
@test "P0-4c: an HONEST 'Complete — nothing to do' over a clean+landed tree stays SILENT" {
  local w; w="$(mkrepo_landed pcc)"
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/none.md"
  run runhook_at "$(mkfix "Complete — nothing to do.")" "$w" "pcc-s"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ══ T-P15-5: genuine-3 → durable class-B decision packet (never a bare idle) ══════════════════
@test "T-P15-5: a genuine fork/external-info stop opens a durable class-B packet (still abstains)" {
  run runhook "$(mkfix "Which account should I use for this run — default to next2? Want me to proceed?")" "pkt-sess"
  [ "$status" -eq 0 ]; [ -z "$output" ]                       # the hook still ABSTAINS (never blocks a genuine ask)
  run bash -c "ls '$CC_DECISIONS_DIR'/*.json 2>/dev/null | head -1"
  [ -n "$output" ]                                             # a durable packet was written
  f="$output"
  [ "$(jq -r '.class'  "$f")" = B ]
  [ "$(jq -r '.status' "$f")" = open ]
  [ -n "$(jq -r '.default_if_no_veto' "$f")" ]                 # class-B carries a default …
  [ -n "$(jq -r '.veto_deadline' "$f")" ]                      # … and a veto deadline
  [ "$(jq -r '.conviction' "$f")" = 0 ]                        # no number stated in the close ⇒ filed UNCONVICTED (0), not refused
  [[ "$(jq -r '.receipt' "$f")" == "session pkt-sess close => "* ]] || false
  grep -q '"packet":' "$ANTIDEF_IDL"                           # the IDL records the opened packet
}

@test "T-P15-5: a stated conviction in the close is READ into the class-B packet (the gate's number)" {
  run runhook "$(mkfix "Which account should I use — default to next2, conviction 60%. Want me to proceed?")" "pkt-conv"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "ls '$CC_DECISIONS_DIR'/*.json 2>/dev/null | head -1"
  [ -n "$output" ]
  [ "$(jq -r '.conviction' "$output")" = 60 ]
}

@test "T-P15-5: degrade-silent — cc-decide absent ⇒ hook exits 0 silent, no packet, no crash" {
  export ANTIDEF_DECIDE_BIN="$BATS_TEST_TMPDIR/no-such-cc-decide"
  run runhook "$(mkfix "which do you prefer — approach one or two? Want me to sketch both?")" "deg-sess"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "ls '$CC_DECISIONS_DIR'/*.json 2>/dev/null"
  [ -z "$output" ]                                             # nothing written when cc-decide is unresolvable
  grep -q '"disposition":"abstained"' "$ANTIDEF_IDL"           # still the abstain path
}

@test "T-P15-5: a class-C credential blocker does NOT open a packet (C needs a staged artifact)" {
  run runhook "$(mkfix "I need your Google client secret first — want me to scaffold the rest?")" "cred-sess"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  run bash -c "ls '$CC_DECISIONS_DIR'/*.json 2>/dev/null"
  [ -z "$output" ]                                             # credential ⇒ class C ⇒ hook opens no packet
}

# ── RED-prove (cc-backlog 666c6a64c45e): a " / backslash in a logged field must never emit a
#    MALFORMED IDL line — one aborts the cc-audit four-zeros `jq -rs` slurp (⇒ D9/alarm silent-GREEN).
#    The `tell` here is a substring of the MODEL's own prose (it can carry quotes), so this hook was
#    the sharpest real vector. jq-encoding fixes it. FAILS on the old raw-%s emit, PASSES now. ──
@test "IDL: a quote/backslash-bearing session_id yields a strict-slurp-parseable, lossless line" {
  local input; input="$(jq -nc '{session_id:"s\"q\\z",cwd:"/tmp"}')"   # no transcript_path ⇒ abstain logs
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$input" "$HOOK"
  [ "$status" -eq 0 ]
  run jq -s '.' "$ANTIDEF_IDL"
  [ "$status" -eq 0 ]
  jq -e 'select(.sid=="s\"q\\z")' "$ANTIDEF_IDL" >/dev/null
}

# ── (2026-08-02) CATEGORY-NOT-IDEA: handing work over by COUNT instead of by CONTENT.
#    Provenance: the model shipped BOTH offending lines below in two CONSECUTIVE real closes while
#    knowing the content (it wrote four paragraphs of it the moment the operator asked "what is
#    it?"). CLAUDE.md § Session Close already bans this in prose (Minto Ch 7 p. 94); prose did not
#    bind. RED-proof: these FAIL on the pre-2026-08-02 hook (no CATEGORY_TELLS ⇒ abstain no-tell).
@test "category-not-idea: fires on a count-only handover" {
  local msgs=(
    "Everything of mine is done and landed. One item is yours."
    "Repo is clean, three commits landed. One item still needs your call."
    "My side is complete — 2 things need your attention."
    "All green. A few items are yours."
    "Wrapped up; some decisions need your decision."
    "Done. Three steps are for you."
  )
  for m in "${msgs[@]}"; do
    local tx; tx="$(mkfix "$m")"
    run runhook "$tx"
    [ "$status" -eq 0 ]
    if ! fired "$output"; then echo "DID NOT FIRE (should have): $m" >&2; false; fi
  done
}

# The whole point of the bar: NAME the thing and the hook goes away. A ':' or a dash before the
# sentence end means the idea is present.
@test "category-not-idea: SILENT once the item is actually named" {
  local msgs=(
    "Everything landed. One item is yours: the Fly deploy trigger still points at main, so every /ship deploys."
    "Done. One item still needs your call — repointing server.ts:284 to refs/heads/release."
    "Clean. Two things are yours: the Amplify branch binding, and the release-ref seed."
  )
  for m in "${msgs[@]}"; do
    local tx; tx="$(mkfix "$m")"
    run runhook "$tx"
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then echo "FIRED (should have been silent): $m" >&2; false; fi
  done
}

# Ordinary prose that merely CONTAINS a count-noun must stay silent — the tell requires the
# count-noun to be joined to a handover phrase.
@test "category-not-idea: SILENT on ordinary prose containing a count-noun" {
  local msgs=(
    "I fixed one thing in the reconcile path and re-ran the suite."
    "There are three tests covering the fast-path predicate."
    "Two items were already on the backlog, so I deduped them."
    "12 runnable now, 195 need your call."
  )
  for m in "${msgs[@]}"; do
    local tx; tx="$(mkfix "$m")"
    run runhook "$tx"
    [ "$status" -eq 0 ]
    if [ -n "$output" ]; then echo "FIRED (should have been silent): $m" >&2; false; fi
  done
}

@test "category-not-idea: the block reason carries the Minto corrective, not the deference one" {
  run runhook "$(mkfix "All landed. One item is yours.")"
  [ "$status" -eq 0 ]
  fired "$output"
  printf '%s' "$output" | grep -q 'Category-not-idea'
  printf '%s' "$output" | grep -q 'tells the kind, not the idea'
  if printf '%s' "$output" | grep -q 'Anti-deference:'; then
    echo "wrong corrective — got the deference message" >&2; false
  fi
}

@test "category-not-idea: logs its own FIRE_KIND to the IDL" {
  run runhook "$(mkfix "Complete. One item is yours.")" "sid-catkind"
  [ "$status" -eq 0 ]
  jq -e 'select(.reason=="category-not-idea")' "$ANTIDEF_IDL" >/dev/null
}

@test "opaque-identifier: fires on two or more unexpanded 12-hex ids" {
  local msgs=(
    "Nothing is open on my side. Your queue is 0aa3febf3143 and b1614375d051."
    "Waiting on you: answer 0aa3febf3143, then b1614375d051, then deploy."
    "Blocked on 408427e74888 plus 02ba4e52389a."
  )
  for m in "${msgs[@]}"; do
    local tx; tx="$(mkfix "$m")"
    run runhook "$tx"
    [ "$status" -eq 0 ]
    if ! fired "$output"; then echo "DID NOT FIRE (should have): $m" >&2; false; fi
  done
}

@test "opaque-identifier: SILENT once ONE id is glossed, in either order" {
  # (b) is the shape this hook's own nudge text recommends — firing on compliance would be a defect.
  local msgs=(
    "Your queue is 0aa3febf3143 (the store-version timing) and b1614375d051."
    "May the sync endpoint read permissions inside the transaction it guards? (b1614375d051) And the store version (0aa3febf3143)?"
    "Two calls: 0aa3febf3143 — when to ship the store version; and b1614375d051."
  )
  for m in "${msgs[@]}"; do
    local tx; tx="$(mkfix "$m")"
    run runhook "$tx"
    [ "$status" -eq 0 ]
    if fired "$output"; then echo "FIRED (should be silent): $m" >&2; false; fi
  done
}

@test "opaque-identifier: the gloss is still a gloss with NO locale set (launchd/postland shape)" {
  # Post-land RED d6a4896406aa. The gloss regex spelled its dash alternatives as a bracket
  # expression, which is a set of CHARACTERS only under a UTF-8 locale; with no LANG it is a set
  # of BYTES, the em dash matched only its \xE2 lead byte, and the hook FIRED on the exact
  # id-then-em-dash-then-explanation shape its own corrective recommends. Every other assertion
  # here inherits the operator's en_CA.UTF-8 and so was structurally blind to it, which is why
  # this case pins the environment instead of trusting the one it happens to run in.
  local msgs=(
    "Your queue is 0aa3febf3143 (the store-version timing) and b1614375d051."
    "May the sync endpoint read permissions inside the transaction it guards? (b1614375d051) And the store version (0aa3febf3143)?"
    "Two calls: 0aa3febf3143 — when to ship the store version; and b1614375d051."
    "Two calls: 0aa3febf3143 – when to ship the store version; and b1614375d051."
    "Two calls: 0aa3febf3143: when to ship the store version; and b1614375d051."
  )
  for m in "${msgs[@]}"; do
    local tx; tx="$(mkfix "$m")"
    run runhook_nolocale "$tx"
    [ "$status" -eq 0 ]
    if fired "$output"; then echo "FIRED with no locale (should be silent): $m" >&2; false; fi
  done
}

@test "opaque-identifier: still FIRES on two bare ids with NO locale set" {
  # The other half of the pinned pair: the C-locale fix must not have bought silence by making the
  # gloss match everything. A control that only asserted silence would pass on a dead detector.
  local tx; tx="$(mkfix "Nothing is open on my side. Your queue is 0aa3febf3143 and b1614375d051.")"
  run runhook_nolocale "$tx"
  [ "$status" -eq 0 ]
  fired "$output"
}

@test "opaque-identifier: SILENT on commit shas and on a single id" {
  # Naming a sha is what the EVIDENCE slot asks for; it must never be punished.
  local msgs=(
    "Landed 90e1c70c2 through c34475d1, all ancestors of origin/main; 828264453 verified."
    "Filed as 2130e8a40cc2 so it survives the pane."
  )
  for m in "${msgs[@]}"; do
    local tx; tx="$(mkfix "$m")"
    run runhook "$tx"
    [ "$status" -eq 0 ]
    if fired "$output"; then echo "FIRED (should be silent): $m" >&2; false; fi
  done
}

@test "opaque-identifier: the block reason carries the expansion corrective, not the Minto one" {
  local tx; tx="$(mkfix "Nothing is open on my side. Your queue is 0aa3febf3143 and b1614375d051.")"
  run runhook "$tx"
  [ "$status" -eq 0 ]
  fired "$output"
  echo "$output" | grep -q "Opaque-identifier"
  echo "$output" | grep -q "expanded at first use"
  ! echo "$output" | grep -q "tells the kind, not the idea"
}
