#!/usr/bin/env bats
# completion-assert.sh — Stop hook: catch the CONFIDENT / TELL-FREE false-done (FM1) that the
# phrasing-only anti-deference matcher misses. Fire predicate = the P11 FM1 signature:
#   (done_assertion ∨ deference_tell) ∧ ledger-contradiction ∧ ¬genuine
# ledger-contradiction (via wrap-ledger.sh) = dirty ∨ unlanded-content ∨ DoD-remainder>0.
# genuine = credential/sudo/destructive-migration/external-info/value-fork ONLY — ship/land of
# clean committed work is NOT genuine (2026-07-17 strengthening), so it does NOT grant abstain.
#
# RED-proof: a19 D-1 + D-5 + all six §KQ1 tell-free closes FIRE over a contradicting ledger; a
# true-complete tree (clean ∧ landed-by-content ∧ no remainder) ABSTAINS; a genuine-credential
# close ABSTAINS; latch blocks re-fire; cap halts; every fail-safe path exits 0 silent.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/completion-assert.sh"
  export COMPLETION_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export COMPLETION_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export COMPLETION_MAX=3
  export WRAP_TRUNK="origin/main"
  # HERMETIC: wrap-ledger resolves the 👤-rung session as --session > $WRAP_SESSION_ID >
  # $CLAUDE_SESSION_ID. An ambient value from the running session would give it a second way to
  # resolve a sid, so the flag under test would no longer be the only path.
  unset CLAUDE_SESSION_ID WRAP_SESSION_ID
  # ARM 2 / D1 disk oracle — ALWAYS a stub, never the real bin/cc-backlog: the real one reads the
  # live backlog ledger (and is edited by other sessions), which would make this suite a function
  # of someone else's state. CC_BACKLOG_STUB_JSON / _RC drive it per-test; the default is the
  # affirmative "nothing filed" answer (`[]`, rc 0).
  CCB_STUB="$BATS_TEST_TMPDIR/cc-backlog-stub"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s" "${CC_BACKLOG_STUB_JSON-[]}"' 'exit "${CC_BACKLOG_STUB_RC:-0}"' > "$CCB_STUB"
  chmod +x "$CCB_STUB"
  export CC_BACKLOG_BIN="$CCB_STUB"
}

# clean repo, HEAD == origin/main (landed)
mkrepo_landed() {
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w"
  ( cd "$w"; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
}
# clean tree, one commit ahead of origin/main (committed-but-unlanded ⇒ ledger contradiction)
mkrepo_unlanded() {
  local w; w="$(mkrepo_landed "$1")"
  ( cd "$w"; echo x > x.txt; git add x.txt; git commit -q -m "unlanded work" ) >/dev/null 2>&1
  printf '%s' "$w"
}

# transcript whose LAST main-agent text = $1
mkfix() {
  local text="$1" path="${2:-$BATS_TEST_TMPDIR/tx-${BATS_TEST_NUMBER}-$RANDOM.jsonl}"
  jq -nc --arg t "$text" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$path"
  printf '%s' "$path"
}
# transcript where the real text is followed by a tool_use-only turn, a sidechain turn, and a
# metadata tail — the extractor must WALK BACK to the main text (G-P11-1 shape).
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

run_ca() { # $1=transcript $2=cwd $3=sid
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"}' "${3:-sid-$RANDOM}" "$1" "$2" | bash "$HOOK"
}
fired() { printf '%s' "$1" | grep -q '"decision":"block"'; }

# ── a19 D-1: confident false-done over remaining scope ⇒ FIRE ──
@test "D-1 'Done. All 12 tests pass… Landed' over unlanded work ⇒ FIRE" {
  local w; w="$(mkrepo_unlanded d1)"
  run run_ca "$(mkfix "Done. All 12 tests pass, shellcheck clean, wired into all 5 config dirs. Landed at abc1234.")" "$w"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── a19 D-5: tell-free milestone-stop burying the remainder in a codename ⇒ FIRE ──
@test "D-5 'Phase 3 landed. Program 2 remains.' over remainder ⇒ FIRE" {
  local w; w="$(mkrepo_landed d5)"
  local dod="$BATS_TEST_TMPDIR/dod-d5.md"; printf -- '- [x] phase 3\n- [ ] program 2\n' > "$dod"
  export WRAP_DOD_FILE="$dod"
  run run_ca "$(mkfix "Phase 3 landed at def5678. Program 2 remains.")" "$w"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── a19 §KQ1: all SIX tell-free deference-equivalent closes FIRE over a contradicting ledger ──
@test "all six §KQ1 tell-free closes FIRE" {
  local closes=(
    "The remaining three items are ready to implement whenever you'd like to prioritize them."
    "I've completed the core; the edge cases are a natural follow-up."
    "That covers Phase 2. Phase 3 is a larger effort — flagging it for planning."
    "Two approaches exist here (A and B); happy to go either direction."
    "Everything requested is done. Let me know if anything else comes up."
    "Shipped the authentication flow — that was the main ask."
  )
  local i=0
  for c in "${closes[@]}"; do
    i=$((i+1))
    local w; w="$(mkrepo_unlanded "kq$i")"
    run run_ca "$(mkfix "$c")" "$w" "kq-sess-$i"
    [ "$status" -eq 0 ]
    if ! fired "$output"; then echo "KQ1 #$i DID NOT FIRE: $c" >&2; false; fi
  done
}

# ── true-complete (clean ∧ landed-by-content ∧ no remainder) ⇒ ABSTAIN even with 'Done' phrasing ──
@test "true-complete tree ⇒ ABSTAIN (ledger clean)" {
  local w; w="$(mkrepo_landed done)"
  run run_ca "$(mkfix "Everything requested is done. Landed on trunk, all green — nothing to do.")" "$w"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── genuine-three (external-info credential) ⇒ ABSTAIN even over a contradicting ledger ──
@test "genuine credential blocker ⇒ ABSTAIN" {
  local w; w="$(mkrepo_unlanded cred)"
  run run_ca "$(mkfix "Committed everything. I need your Azure client secret to finish — otherwise it's all done.")" "$w"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "genuine destructive-migration ⇒ ABSTAIN" {
  local w; w="$(mkrepo_unlanded destr)"
  run run_ca "$(mkfix "Core is done. The last step is a destructive migration (DROP TABLE users_old) — need your go.")" "$w"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── ship/land is NOT genuine: park-and-call-done over unlanded verified work ⇒ FIRE (G-P11-2) ──
@test "'📦 Done, only on a branch — /ship to land' over unlanded ⇒ FIRE (ship not genuine)" {
  local w; w="$(mkrepo_unlanded park)"
  run run_ca "$(mkfix "📦 Done, but only on a branch — /ship to land it whenever.")" "$w"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── extraction walks back past tool_use / sidechain / metadata tail (G-P11-1) ──
@test "walks back past tool_use/sidechain/metadata tail to the main done-assertion ⇒ FIRE" {
  local w; w="$(mkrepo_unlanded tail)"
  run run_ca "$(mkfix_tail "Everything requested is done — nothing left to do.")" "$w"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── block reason names the contradiction FACT ──
@test "block reason names the ledger contradiction" {
  local w; w="$(mkrepo_unlanded reason)"
  run run_ca "$(mkfix "Everything is done, all green.")" "$w"
  printf '%s' "$output" | grep -qi "unlanded"
  printf '%s' "$output" | grep -qi "completion-assert"
}

# ── LATCH: identical content fires once, then silent ──
@test "latch: fires once then silent on identical content" {
  local w; w="$(mkrepo_unlanded latch)"
  local tx; tx="$(mkfix "Everything requested is done.")"
  run run_ca "$tx" "$w" "latch-s"; [ "$status" -eq 0 ]; fired "$output"
  run run_ca "$tx" "$w" "latch-s"; [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── CAP: halts after COMPLETION_MAX distinct fires ──
@test "cap: distinct false-dones fire to the cap then go silent" {
  export COMPLETION_MAX=2
  local w; w="$(mkrepo_unlanded cap)"
  run run_ca "$(mkfix "Everything is done.")"        "$w" "cap-s"; fired "$output"
  run run_ca "$(mkfix "All complete, nothing to do.")" "$w" "cap-s"; fired "$output"
  run run_ca "$(mkfix "Finished — that was the main ask.")" "$w" "cap-s"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── FAIL-SAFE: every degenerate input exits 0 silent (a block must never come from an error) ──
@test "fail-safe: missing transcript_path ⇒ silent exit 0" {
  run bash -c 'printf "{\"session_id\":\"x\",\"cwd\":\"/tmp\"}" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "fail-safe: nonexistent transcript ⇒ silent exit 0" {
  run bash -c 'printf "{\"transcript_path\":\"/no/such/file.jsonl\",\"cwd\":\"/tmp\"}" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "fail-safe: garbage stdin ⇒ silent exit 0" {
  run bash -c 'printf "not json" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "fail-safe: cwd not a git repo ⇒ silent exit 0 (cannot compute ledger)" {
  mkdir -p "$BATS_TEST_TMPDIR/nogit"
  run run_ca "$(mkfix "Everything is done.")" "$BATS_TEST_TMPDIR/nogit"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── IDL: one record per invocation (fired + abstained both logged) ──
@test "IDL: fire writes a fired record; clean writes an abstained record" {
  local w1; w1="$(mkrepo_unlanded idl1)"
  run run_ca "$(mkfix "Everything is done, all green.")" "$w1"
  grep -q '"disposition":"fired"' "$COMPLETION_IDL"
  grep -q '"hook":"completion-assert"' "$COMPLETION_IDL"
  local w2; w2="$(mkrepo_landed idl2)"
  run run_ca "$(mkfix "Everything is done, all green.")" "$w2"
  grep -q '"disposition":"abstained"' "$COMPLETION_IDL"
}

# ── RED-prove (cc-backlog 666c6a64c45e): a " / backslash in a logged field must never emit a
#    MALFORMED IDL line. Raw %s did — `{…,"sid":"s"q",…}` — which aborts the cc-audit four-zeros
#    `jq -rs` slurp (⇒ "no records" ⇒ D9/alarm silently GREEN, defeating the un-gameable detector).
#    jq-encoding every field fixes it. Drive an early abstain so log_idl runs with SID carrying the
#    injected chars. This test FAILS on the old raw-printf emit (jq -s aborts) and PASSES now. ──
@test "IDL: a quote/backslash-bearing session_id yields a strict-slurp-parseable, lossless line" {
  local input; input="$(jq -nc '{session_id:"s\"q\\z",cwd:"/tmp"}')"   # no transcript_path ⇒ abstain logs
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$input" "$HOOK"
  [ "$status" -eq 0 ]
  run jq -s '.' "$COMPLETION_IDL"                                # STRICT slurp = what the four-zeros consumer does
  [ "$status" -eq 0 ]                                            # one malformed line would abort this
  jq -e 'select(.sid=="s\"q\\z")' "$COMPLETION_IDL" >/dev/null   # lossless: jq-escaped, NOT quote-stripped
}

# ══════════════════════════════════════════════════════════════════════════════════════════════
# ARM 2 — OPERATOR SURFACE (2026-08-01). The ledger arm is blind to the close that is ledger-CLEAN
# (git says ✅, and it IS) yet still unactionable: it hands the operator work in a PARAGRAPH (D1,
# so operator-readout.sh cannot render it), or shows the one command to paste OUTSIDE a
# ```bash-tagged fence (D2, so the TUI cannot highlight it out of the prose). Every case below
# therefore runs over mkrepo_landed — a contradicting ledger would prove nothing about this arm.
#
# NEGATIVE CONTROL (run 2026-08-01): ALL SEVEN fire-cases — D1, D2-unfenced, D2-ENV=VAL,
# D2-bare-fence, D1+D2, D3 and D4 — were re-run against the PRE-ARM hook (this file's edit reverted
# by content copy from HEAD, NOT `git stash`, which is repo-global across worktrees) and all seven
# went RED there (abstain, empty output). They fail without the arm and pass with it.
# The wiring case below was controlled SEPARATELY and more tightly: with the arms fully intact and
# ONLY the one-line `--session "$SID"` feed reverted, it fails at the `rung` assertion — so it is
# pinning the feed, not the arm.
# ══════════════════════════════════════════════════════════════════════════════════════════════

# ── D1: work handed over in prose, with NOTHING filed on disk ⇒ FIRE ──
@test "D1 ledger-clean close that says 'two things remain yours' with no filed step ⇒ FIRE" {
  local w; w="$(mkrepo_landed a2d1)"
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green.

Two things remain yours before this is fully wired up.")" "$w" "a2-d1"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'cc-backlog needs'
  printf '%s' "$output" | grep -qi 'operator-readout'
  grep -q '"arm":"handoff"' "$COMPLETION_IDL"
}

# ── D1 abstain: the SAME close, but the step IS filed for THIS session ⇒ nothing to nag about ──
@test "D1 abstains when a blocked backlog item carries this session" {
  local w; w="$(mkrepo_landed a2d1ok)"
  export CC_BACKLOG_STUB_JSON='[{"id":"abc123","status":"blocked","session":"a2-d1-filed","project":"p","title":"t","needs":"run the mcp add"}]'
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green.

Two things remain yours before this is fully wired up.")" "$w" "a2-d1-filed"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── D1 fail-open: the oracle cannot answer (rc 1) ⇒ "cannot tell" ⇒ DO NOT FIRE ──
@test "D1 fails OPEN when the cc-backlog oracle exits non-zero" {
  local w; w="$(mkrepo_landed a2d1fail)"
  export CC_BACKLOG_STUB_JSON=''
  export CC_BACKLOG_STUB_RC=1
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green.

Two things remain yours before this is fully wired up.")" "$w" "a2-d1-failopen"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── D2: the paste-line sits bare in the body (the real 2026-08-01 close) ⇒ FIRE ──
@test "D2 bare unfenced command line ⇒ FIRE" {
  local w; w="$(mkrepo_landed a2d2)"
  run run_ca "$(mkfix "✅ Complete & live on trunk.

cc-do land-the-mcp-wiring

Then everything is in place.")" "$w" "a2-d2"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'inline-code span'
  grep -q '"arm":"fence"' "$COMPLETION_IDL"
}

# ── D2: an ENV=VAL-prefixed command, unfenced, mid-paragraph (the mcp-add close) ⇒ FIRE ──
@test "D2 unfenced ENV=VAL-prefixed command ⇒ FIRE" {
  local w; w="$(mkrepo_landed a2d2env)"
  run run_ca "$(mkfix "✅ Complete & live on trunk, which is the main reason I'd leave it:

CLAUDE_CONFIG_DIR=~/.claude-next claude-latest mcp add browsermcp

and that finishes the wiring")" "$w" "a2-d2-env"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── D2 abstain: a ```bash fence is DELIMITED and copy-clean, so it is not the defect D2 hunts —
#    though it is no longer the PREFERRED form (screenshot-measured 2026-08-01: a fence renders
#    plain WHITE, because syntax highlighting colours syntax and a bare command has none, while
#    inline code is blue unconditionally). D2 hunts a command with NO code styling at all, bare in
#    a paragraph. Firing on a fence would be over-enforcement — it would convict every legitimate
#    fenced example in a doc or a review. The preferred form is pinned two tests below. ──
@test "D2 abstains when the command is in a bash-tagged fence" {
  local w; w="$(mkrepo_landed a2d2ok)"
  run run_ca "$(mkfix "✅ Complete & live on trunk.

\`\`\`bash
cc-do land-the-mcp-wiring
\`\`\`")" "$w" "a2-d2-ok"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── D2: a BARE ``` fence still cannot be highlighted ⇒ FIRE ──
@test "D2 bare fence with no language tag ⇒ FIRE" {
  local w; w="$(mkrepo_landed a2d2bare)"
  run run_ca "$(mkfix "✅ Complete & live on trunk.

\`\`\`
cc-do land-the-mcp-wiring
\`\`\`")" "$w" "a2-d2-bare"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'inline-code span'
}

# ── FALSE-POSITIVE GUARD: naming a command in inline backticks is legitimate prose ⇒ ABSTAIN.
#    An advisory that cries wolf stops being read (MEMORY.md alarm-polarity-and-attention-budget). ──
@test "D2 abstains on an inline-backtick mention of a command mid-sentence" {
  local w; w="$(mkrepo_landed a2fp)"
  run run_ca "$(mkfix "✅ Complete & live on trunk.

\`cc-do land-the-mcp-wiring\` is the driver that would have landed it — reference only")" "$w" "a2-fp"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── FALSE-POSITIVE GUARD: ordinary prose that happens to open at column 0 with a verb ⇒ ABSTAIN ──
@test "D2 abstains on column-0 prose whose first word is a command verb" {
  local w; w="$(mkrepo_landed a2fp2)"
  run run_ca "$(mkfix "✅ Complete & live on trunk.

git history shows the same fix landed twice, so nothing more is needed here.")" "$w" "a2-fp2"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── The GENUINE abstain (line 87-88) precedes BOTH arms: a close carrying D1 phrasing AND a bare
#    command AND an irreducible operator-only blocker must still go silent. ──
@test "genuine blocker ⇒ ABSTAIN over BOTH arm-2 defects" {
  local w; w="$(mkrepo_landed a2gen)"
  run run_ca "$(mkfix "✅ Complete & live on trunk. Two things remain yours.

cc-do land-the-mcp-wiring

I need your API key to finish the last step.")" "$w" "a2-genuine"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"genuine-blocker"' "$COMPLETION_IDL"
}

# ── BOTH arm-2 defects in one close ⇒ ONE fire naming BOTH remedies, arm = handoff+fence ──
@test "D1+D2 together ⇒ one fire carrying both sentences" {
  local w; w="$(mkrepo_landed a2both)"
  run run_ca "$(mkfix "✅ Complete & live on trunk.

Two things remain yours before this is fully wired up.

cc-do land-the-mcp-wiring")" "$w" "a2-both"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'cc-backlog needs'
  printf '%s' "$output" | grep -q 'inline-code span'
  grep -q '"arm":"handoff+fence"' "$COMPLETION_IDL"
  [ "$(grep -c . "$COMPLETION_IDL")" -eq 1 ]   # one IDL line per invocation
}

# ── The LEDGER arm's own record still carries arm="ledger" and its reason is unchanged ──
@test "ledger-only fire records arm=ledger with the unchanged reason" {
  local w; w="$(mkrepo_unlanded a2led)"
  run run_ca "$(mkfix "Everything is done, all green.")" "$w" "a2-ledger"
  [ "$status" -eq 0 ]; fired "$output"
  grep -q '"arm":"ledger"' "$COMPLETION_IDL"
  printf '%s' "$output" | grep -qi 'the LIVE ledger contradicts it'
  ! printf '%s' "$output" | grep -q 'inline-code span'
}

# ── D3 — HEDGED GOVERNING LINE (addendum 1). Line 1 must be ONE unhedged rung. "Yes — with one
#    thing still parked" answers and then withdraws the answer, and the operator has to spend a
#    round-trip asking which it was ("so you want me to run the command or want me to close?").
#    Scoped to the FIRST non-empty line: a settled line 1 with the detail below it is the WANTED
#    shape, so whole-message matching would fire on nearly every legitimate close. ──
@test "D3 line 1 that asserts and withdraws a verdict ⇒ FIRE" {
  local w; w="$(mkrepo_landed a2d3)"
  run run_ca "$(mkfix "Yes — with one thing still parked.

The parked thing is the mcp wiring in the other worktree.")" "$w" "a2-d3"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'ONE rung that actually governs'
  grep -q '"arm":"hedge"' "$COMPLETION_IDL"
}

@test "D3 abstains on an unhedged settled line 1" {
  local w; w="$(mkrepo_landed a2d3ok)"
  run run_ca "$(mkfix "✅ Safe to close.

Everything landed, both trees clean.")" "$w" "a2-d3-ok"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── The key D3 false-positive guard: a rung-CONSISTENT line 1 where the remainder IS the rung.
#    "📦 Done, on a branch only — /ship to land it" states one rung and does not withdraw it —
#    which is why the settled-verdict set deliberately excludes a bare rung glyph. ──
@test "D3 abstains on a rung-consistent remainder line (📦 …/ship to land it)" {
  local w; w="$(mkrepo_landed a2d3rung)"
  run run_ca "$(mkfix "📦 Done, on a branch only — /ship to land it (else lost).")" "$w" "a2-d3-rung"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── D3 is FIRST-LINE-scoped: a settled line 1 with the handoff further down fires D1 only ──
@test "D3 does not fire when the remainder sits below line 1 (D1 only)" {
  local w; w="$(mkrepo_landed a2d3scope)"
  run run_ca "$(mkfix "✅ Complete & live on trunk.

Landed at abc1234, gates green, tree clean.

Detail on the wiring is in the commit body.

Two things remain yours before this is fully wired up.")" "$w" "a2-d3-scope"
  [ "$status" -eq 0 ]; fired "$output"
  grep -q '"arm":"handoff"' "$COMPLETION_IDL"
  ! grep -q 'hedge' "$COMPLETION_IDL"
}

# ── D4 — OFFER INSTEAD OF DRIVE (addendum 2). The close names remaining work it has already
#    researched, then asks permission to continue. The operator's ruling: "the answer will always
#    be yes — the job is not done until the job is done." The ledger arm is structurally blind to
#    it (this tree was clean and landed; the work lived in another worktree and an older DoD). ──
@test "D4 named remaining work + 'say the word' ⇒ FIRE" {
  local w; w="$(mkrepo_landed a2d4)"
  run run_ca "$(mkfix "✅ Done — closeable. verify.sh prints Complete, everything landed, both trees clean.

Two things are in this worktree but were never part of this session's scope, if you want a next thread:
- cc-010333-23674 — 38 commits ahead of origin/main, still stranded.
- DESIGN_GATE_V2 sequence — the worktree's older frozen DoD.

Say the word and I'll pick up either; otherwise this is a clean stopping point.")" "$w" "a2-d4"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'three dispositions'
  printf '%s' "$output" | grep -q 'DRIVEN'
  printf '%s' "$output" | grep -q 'FILED'
  grep -q '"arm":"offer"' "$COMPLETION_IDL"
}

# ── The guard that keeps D4 from punishing CORRECT behaviour: the same remaining work, stated as
#    filed and counted, with the offer sentence gone ⇒ ABSTAIN. Only the QUESTION is the defect. ──
@test "D4 abstains when the same work is stated as filed instead of offered" {
  local w; w="$(mkrepo_landed a2d4ok)"
  run run_ca "$(mkfix "✅ Done — closeable. verify.sh prints Complete, everything landed, both trees clean.

Two out-of-scope items found in this worktree are now filed as backlog rows (2 counted): cc-010333-23674 and the DESIGN_GATE_V2 sequence.")" "$w" "a2-d4-ok"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── Predicate (b) is what stops D4 firing on ordinary sign-off politeness: an offer phrase with
#    NO named remaining work ⇒ ABSTAIN. ──
@test "D4 abstains on an offer phrase with no named remaining work" {
  local w; w="$(mkrepo_landed a2d4pol)"
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green.

Let me know if you'd like a walkthrough of the diff.")" "$w" "a2-d4-pol"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── PRECEDENCE: a genuine value fork still abstains at hooks/completion-assert.sh:87-88, ahead of
#    every arm-2 defect — an offer of a real CHOICE is not deference-fishing. ──
# ── WIRING: the session id must actually REACH wrap-ledger. This asserts the FEED, not the
#    computation — wrap-ledger's own suite proves it can compute 👤, and did so while the hook
#    passed it no --session at all, so the rung it produced for every real close was ✅ and the
#    feature was inert. Only an end-to-end read through the hook can see that.
#    The observable is the IDL `rung` on a fire: a clean+landed tree is ✅-eligible on the git
#    facts, so 👤 can ONLY appear if the sid reached wrap-ledger and matched a filed blocked row.
#    Fires via D2 (arm=fence) because a 👤 ledger is not a `contra` — the ledger arm cannot reach
#    this state at all, which is the other half of why this went unseen. ──
@test "wiring: the stdin session_id reaches wrap-ledger (rung 👤, not ✅)" {
  local w; w="$(mkrepo_landed a2sid)"
  unset CLAUDE_SESSION_ID WRAP_SESSION_ID   # --session is the ONLY path to a resolved sid here
  export CC_BACKLOG_STUB_JSON='[{"id":"zz9","status":"blocked","session":"a2-sid-feed","project":"p","title":"t","needs":"run the mcp add"}]'
  run run_ca "$(mkfix "✅ Complete & live on trunk.

cc-do land-the-mcp-wiring")" "$w" "a2-sid-feed"
  [ "$status" -eq 0 ]; fired "$output"
  grep -q '"rung":"👤"' "$COMPLETION_IDL"
  ! grep -q '"rung":"✅"' "$COMPLETION_IDL"
}

@test "genuine value fork ⇒ ABSTAIN ahead of D4" {
  local w; w="$(mkrepo_landed a2d4fork)"
  run run_ca "$(mkfix "✅ Done — closeable, with one remaining decision.

Say the word and I'll take it on: which of these two approaches do you want, the shim or the fork?")" "$w" "a2-d4-fork"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  grep -q '"reason":"genuine-blocker"' "$COMPLETION_IDL"
}

# ── QUOTED SPANS ARE MENTION, NOT USE ─────────────────────────────────────────────────────────
# Found by this hook firing on the very close that shipped it: a table citing the operator's own
# examples matched D1 and D4, so the guard convicted the change that fixes the thing it names.
# The pair below is the discriminator — same phrases, quoted vs bare — so a future strip that is
# too greedy (kills the real fire) or too timid (keeps the FP) fails exactly one of them.
@test "D1/D4 abstain when the close QUOTES the defect instead of committing it" {
  local w; w="$(mkrepo_landed a2quote)"
  run run_ca "$(mkfix '✅ Complete & live on trunk — landed, all green.

| Your example | Now |
|---|---|
| ✅ then "two things remain yours" in ¶4 | filed via `cc-backlog needs`, renders in the block |
| "Say the word and I'"'"'ll pick up either" | three dispositions, never a fourth |

Curly variant, same rule: “two things remain yours” is a citation too.')" "$w" "a2-quote"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "CONTROL: the same phrases UNQUOTED still fire — the strip did not defang the arm" {
  local w; w="$(mkrepo_landed a2quotectl)"
  run run_ca "$(mkfix '✅ Complete & live on trunk — landed, all green.

Two things remain yours: authenticate motion-plus, and restart Cursor.

Say the word and I will pick up either of the remaining items.')" "$w" "a2-quote-ctl"
  [ "$status" -ne 0 ] || [ -n "$output" ]
  printf '%s' "$output" | grep -q 'cc-backlog needs'
}

# ── THE PREFERRED FORM (CLAUDE.md § ONE command, screenshot-measured 2026-08-01): a marker line of
#    its own, then the command as an inline-code span alone on the next line. Blue on every wrapped
#    row, marker breaks left-align scanning, and no row starts with chrome so a drag-copy is exact.
#    This MUST abstain, or the rule the docs mandate would be blocked by the hook that enforces it —
#    the same self-contradiction the quoted-span FP already cost us once. ──
@test "D2 abstains on the PREFERRED marker-line + inline-span form" {
  local w; w="$(mkrepo_landed a2d2pref)"
  run run_ca "$(mkfix '✅ Complete & live on trunk — landed, all green.

▶ Run this:

`cc-do`')" "$w" "a2-d2-pref"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "D2 abstains on the preferred form with a LONG wrapping command" {
  local w; w="$(mkrepo_landed a2d2preflong)"
  run run_ca "$(mkfix '✅ Complete & live on trunk — landed, all green.

▶ Run this:

`CLAUDE_CONFIG_DIR=~/.claude-next claude-latest mcp add -e TOKEN=X --scope user motion-local -- node ~/Development/motion-plus/ai-kit/mcp/dist/es/index.mjs`')" "$w" "a2-d2-preflong"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── CONTROL: strip the styling and the SAME command bare in a paragraph still FIRES, so the two
#    abstains above are the form being recognised, not D2 having gone quiet. ──
@test "CONTROL: the same command BARE in a paragraph still fires D2" {
  local w; w="$(mkrepo_landed a2d2barectl)"
  run run_ca "$(mkfix '✅ Complete & live on trunk — landed, all green.

Run this:

cc-do')" "$w" "a2-d2-barectl"
  [ "$status" -ne 0 ] || [ -n "$output" ]
}

# ── D5: a command handed over for copy-paste that still contains a PLACEHOLDER ─────────────────
# Found the only way it gets found: the operator pasted one and their shell said
# `(eval):1: no such file or directory: checkout`. Every other arm passed it — D2 sees code
# styling and abstains, and nothing else looks INSIDE the command. "One thing to select and
# paste" is the contract; a template is homework.
@test "D5 a run-marked command containing <placeholder> ⇒ FIRE" {
  local w; w="$(mkrepo_landed a2d5)"
  run run_ca "$(mkfix '✅ Complete & live on trunk.

▶ Reconcile and retry:

`git -C <checkout> pull --rebase origin main && <checkout>/install.sh`')" "$w" "a2-d5"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'placeholder'
}

@test "D5 fires on the PASTE_ / YOUR_ literals too" {
  local w; w="$(mkrepo_landed a2d5lit)"
  run run_ca "$(mkfix '✅ Complete & live on trunk.

▶ Run this:

`claude-latest mcp add -e TOKEN=PASTE_TOKEN_HERE --scope user motion-local`')" "$w" "a2-d5-lit"
  [ "$status" -eq 0 ]; fired "$output"
}

# ---- false-positive guards: each pins a lane a blanket placeholder-hunt would have broken -----

@test "FP GUARD: a placeholder in a MID-SENTENCE mention is documentation, not a handover" {
  local w; w="$(mkrepo_landed a2d5doc)"
  run run_ca "$(mkfix '✅ Complete & live on trunk. The refusal prints `git -C <path> pull --rebase origin main` with the real path substituted when it fires, so nothing needs filling in.')" "$w" "a2-d5-doc"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "FP GUARD: \$VAR / ~ / \$(cmd) are RESOLVED by the shell — not placeholders" {
  local w; w="$(mkrepo_landed a2d5var)"
  run run_ca "$(mkfix '✅ Complete & live on trunk.

▶ Run this:

`cd "$HOME/Development/claude-infrastructure" && bash install.sh`')" "$w" "a2-d5-var"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "FP GUARD: a shell redirect and a heredoc are not angle-bracket placeholders" {
  local w; w="$(mkrepo_landed a2d5redir)"
  run run_ca "$(mkfix '✅ Complete & live on trunk.

▶ Run this:

`sort < input.txt > output.txt`')" "$w" "a2-d5-redir"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "CONTROL: the SAME command fully substituted abstains — D5 reads the value, not the shape" {
  local w; w="$(mkrepo_landed a2d5ok)"
  run run_ca "$(mkfix '✅ Complete & live on trunk.

▶ Reconcile and retry:

`git -C /Users/chrisren/Development/claude-infrastructure pull --rebase origin main`')" "$w" "a2-d5-ok"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# ── NEGATED HANDOFFS: "nothing for you to run" is the OPPOSITE of a handoff ────────────────────
# FP #3 of this family, found by the hook blocking a correct close. `for you to run` matched and
# the matcher could not see the `nothing` two words left of it. Paired with a bare control so a
# strip that is too greedy (kills the real fire) or too timid (keeps the FP) fails exactly one.
@test "D1 abstains on a NEGATED handoff (nothing for you to run)" {
  local w; w="$(mkrepo_landed a2neg)"
  run run_ca "$(mkfix '✅ Complete & live on trunk — 11 commits landed and deployed; nothing for you to run.

The checkout is 0 ahead, 0 behind, clean.')" "$w" "a2-neg"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "D1 abstains on other negated forms (no manual step / never left to you)" {
  local w; w="$(mkrepo_landed a2neg2)"
  run run_ca "$(mkfix '✅ Complete & live on trunk. There is no manual step here, and nothing is left for you to do.')" "$w" "a2-neg2"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "CONTROL: the SAME phrase UNNEGATED still fires D1 — the strip did not defang the arm" {
  local w; w="$(mkrepo_landed a2negctl)"
  run run_ca "$(mkfix '✅ Complete & live on trunk — landed and deployed.

There is one manual step for you to run: re-authenticate the MCP server.')" "$w" "a2-neg-ctl"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'cc-backlog needs'
}
