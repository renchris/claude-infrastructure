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
  # HERMETIC #2 — THE SUITE MUST NOT BE A FUNCTION OF WHO RUNS IT (found 2026-08-07: 9 of these
  # tests went RED, and ONLY when the suite was run from inside an Agent-Teams assignee session).
  # The attribution guard's `_ca_assignee` reads the RUNNING PROCESS's ancestry, so an assignee
  # executing bats is itself "a confirmed assignee" — and every fixture here is write-free by
  # construction (mkfix records no tool_use), which is exactly the pair the hook exonerates. The
  # fixture transcript is a fixture; the ancestry it should be judged against is the fixture's, not
  # the harness's. So pin the axis OFF via the documented hard override (a missing file ⇒ "no lib"
  # ⇒ not an assignee ⇒ stay strict), which is the disposition every one of these cases was written
  # against. Same class as MEMORY.md guard-refusal-fires-on-its-own-harness.
  # The three `attribution:` tests below are UNAFFECTED — they record real writes, so they take the
  # normal intersection path and never reach this branch.
  export AGENT_IDENTITY_LIB="$BATS_TEST_TMPDIR/no-such-agent-identity.sh"
  # ARM 2 / D1 disk oracle — ALWAYS a stub, never the real bin/cc-backlog: the real one reads the
  # live backlog ledger (and is edited by other sessions), which would make this suite a function
  # of someone else's state. CC_BACKLOG_STUB_JSON / _RC drive it per-test; the default is the
  # affirmative "nothing filed" answer (`[]`, rc 0).
  CCB_STUB="$BATS_TEST_TMPDIR/cc-backlog-stub"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s" "${CC_BACKLOG_STUB_JSON-[]}"' 'exit "${CC_BACKLOG_STUB_RC:-0}"' > "$CCB_STUB"
  chmod +x "$CCB_STUB"
  export CC_BACKLOG_BIN="$CCB_STUB"
  # D6 hermeticity: the origin oracle reads the fired-peer stamp store; without this pin a
  # write-recording ✅ fixture would read the REAL ~/.claude/cc-fired for whatever pane id the
  # harness happens to run in — the suite-is-a-function-of-who-runs-it class again.
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"; mkdir -p "$CC_FIRED_DIR"
  # W2 hermeticity, same class: wrap-ledger's custody counter resolves the repo's bin/cc-custody,
  # whose store defaults under the operator's $HOME. Empty fixture dir = counted zero.
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  # LIVE-PEER-OWNED hermeticity, and the same class a third time: that term reads the cc-registry,
  # so leaving it unfixtured makes every test here a function of which OTHER sessions are running
  # (~50 live rows on this box). Empty fixture dir = no peer = the strict disposition these tests
  # were written against.
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
}

# Reap the fake peers the LIVE-PEER-OWNED tests spawn. Reading the pid list from a FILE, not a
# variable: each @test body is its own subshell, so a variable set there is gone by the time this
# runs.
teardown() {
  [ -f "$BATS_TEST_TMPDIR/pids" ] || return 0
  local p
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    kill "$p" 2>/dev/null || true
    wait "$p" 2>/dev/null || true
  done < "$BATS_TEST_TMPDIR/pids"
}

# clean repo, HEAD == origin/main (landed)
mkrepo_landed() {
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w"
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
}
# landed + clean, but the LIVE LAYER is behind PAST its converge budget (⇒ RUNG=🚀).
# The live checkout must share the fixture's `remote.origin.url` byte-for-byte — that is
# wrap-ledger's applicability gate — so it is a CLONE OF THE SAME ORIGIN, not an unrelated repo.
# The caller sets WRAP_LIVE_REPO + WRAP_LIVE_BUDGET_COMMITS: an export in here would die with the
# `$( )` subshell this helper is invoked from.
# The landed work EDITS base.txt rather than adding a file (2026-08-09): an ADD breaches with NO
# budget, so a fixture that added one would satisfy the FIRE case without WRAP_LIVE_BUDGET_COMMITS=0
# ever mattering — the budget lever untested, and the test still green. mkrepo_landed_not_live_adding
# below is the deliberate lever for the other kind.
mkrepo_landed_not_live() { # <tag> → echoes the session repo; live clone at $BATS_TEST_TMPDIR/live-<tag>
  local w; w="$(mkrepo_landed "$1")"
  ( cd "$w" || exit 1; echo y >> base.txt; git add base.txt; git commit -q -m "landed work"; git push -q origin main ) >/dev/null 2>&1
  # CLONE AFTER THE PUSH, then step HEAD back. Order is load-bearing: wrap-ledger deliberately does
  # NOT fetch (its law is pure-read), so it measures lag against the live repo's LAST-FETCHED trunk
  # ref. Cloning first leaves that ref stale, LIVE_LAG reads 0, no breach — the first draft of this
  # fixture did exactly that and the FIRE case failed while the subject was correct.
  git clone -q "$BATS_TEST_TMPDIR/o-$1.git" "$BATS_TEST_TMPDIR/live-$1" >/dev/null 2>&1
  # --detach origin/main~1, NOT `reset --hard HEAD~1`: the bare origin's default branch is master
  # while the fixture pushes main, so the clone lands with an UNBORN HEAD and the reset fails
  # silently under 2>/dev/null — leaving LIVE_LAG=0 and no breach.
  git -C "$BATS_TEST_TMPDIR/live-$1" checkout -q --detach origin/main~1 >/dev/null 2>&1
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
# PIN THE D7 AXIS OFF (2026-08-23). Filing that row is also what makes wrap-ledger compute RUNG=👤
# — CC_BACKLOG_BIN is its env seam too — and this close states no act line, so D7 convicts it. That
# conviction is CORRECT (a 👤 close whose line 1 reads "✅ Complete" and whose act is nowhere is
# exactly D7's target) and must not be weakened to keep this case green. But this case is about
# D1's abstain, and a test that measures two arms at once measures neither: without the pin it
# passed or failed on ORDER, because wrap-ledger's memo could hand it a cached ✅ from an earlier
# test. Same technique the setup() uses for AGENT_IDENTITY_LIB — judge the fixture on its own axis.
# The D7 axis has its own cases at the end of this file, including this shape.
@test "D1 abstains when a blocked backlog item carries this session" {
  local w; w="$(mkrepo_landed a2d1ok)"
  export CC_CLOSE_ACT=0
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

@test "D5 a MULTI-WORD placeholder fires — the value described, not named" {
  # The escape that reached the operator, 2026-08-23. The class held no SPACE, so `<addr>` and
  # `<pw>` convicted while `<your SevenRooms password>` — the form a model writes when it DESCRIBES
  # the value rather than naming it — sailed through, under a `▶ Run this:` marker, the one place
  # the contract promises something literal enough to paste. The rule was already written; it
  # simply did not match.
  local w; w="$(mkrepo_landed a2d5mw)"
  run run_ca "$(mkfix '👤 My side is done & landed — 1 step needs you.

▶ Run this:

`aws secretsmanager create-secret --name sevenrooms/sidecar/login --secret-string {"password":"<your SevenRooms password>"}`')" "$w" "a2-d5-mw"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'placeholder'
}

@test "D5 CONTROL: a heredoc-plus-redirect is NOT a placeholder" {
  # The case that admitting the space would otherwise let in: `<<EOF > out` reads as `<EOF >` once
  # a space is legal inside the brackets. The trailing must-be-alphanumeric anchor is what excludes
  # it, and this test is what makes that anchor load-bearing rather than decorative. A false FIRE
  # here is worse than the escape above — it convicts a correct command, and an arm that cries wolf
  # teaches the operator to paste through the next real one.
  local w; w="$(mkrepo_landed a2d5hd)"
  run run_ca "$(mkfix '👤 My side is done & landed — 1 step needs you.

▶ Run this:

`cat <<EOF > /tmp/report.txt`')" "$w" "a2-d5-hd"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'placeholder' && false || true
}

@test "D5 REGRESSION: the shape carries NO capture group — jq scan would return the group" {
  # Spelling the two-or-more case as `<[A-Za-z](…)?>` is the obvious way to admit spaces, and it is
  # wrong in a way bash cannot see: this regex is consumed by bash `[[ =~ ]]` (POSIX ERE) AND by jq
  # `scan()` (Oniguruma), and `scan` returns the CAPTURES when a group is present. Every rendered
  # token silently became `our-addres` instead of `<your-address>`; 10 operator-readout and cc-do
  # tests caught it. Non-capturing `(?:…)` does not exist in POSIX ERE, so the length cases must
  # stay separate alternatives.
  local repo; repo="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck disable=SC1090,SC1091
  . "$repo/hooks/lib/placeholder.sh"
  printf '%s' "$CC_PLACEHOLDER_RE" | grep -q '(' && false || true

  # …and the property that absence protects: scan returns the WHOLE token.
  run jq -nr --arg s 'subscribe --endpoint <your-address>' --arg ph "$CC_PLACEHOLDER_RE" \
    '[$s | scan($ph)] | join(",")'
  [ "$status" -eq 0 ]
  [ "$output" = "<your-address>" ]
}

@test "D5 SSOT: the shape is the LIB's, and the inline fallback is byte-identical to it" {
  # The shape moved to hooks/lib/placeholder.sh (2026-08-22) so the RENDERERS could refuse to platter
  # a stored command with a hole in it — the only half of this defect that is prevention rather than
  # apology. This arm keeps an inline copy so a missing lib cannot stop it asserting; that copy is a
  # FALLBACK, not a second definition, and two answers to "is this pasteable" would drift silently in
  # the direction that plates the bad command. So: pin them against each other.
  local repo; repo="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  local from_lib from_hook
  from_lib="$(grep -m1 '^CC_PLACEHOLDER_RE=' "$repo/hooks/lib/placeholder.sh" | cut -d= -f2-)"
  from_hook="$(grep -m1 '^CA_PLACEHOLDER=' "$repo/hooks/completion-assert.sh" | cut -d= -f2-)"
  [ -n "$from_lib" ] && [ "$from_lib" = "$from_hook" ]
}

@test "D5 still FIRES with the lib unreachable — the fallback is live, not decorative" {
  local w; w="$(mkrepo_landed a2d5nolib)"
  PLACEHOLDER_LIB="$BATS_TEST_TMPDIR/no-such-lib.sh" \
  CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/nocfg" \
    run run_ca "$(mkfix '✅ Complete & live on trunk.

▶ Run this:

`aws sns subscribe --protocol email --notification-endpoint <your-address>`')" "$w" "a2-d5-nolib"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'placeholder'
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

# ── ATTRIBUTION (2026-08-02): convict only for work THIS SESSION wrote ────────────────
# Reproduces the live false-conviction: the only unlanded commit touched config/kitty.conf,
# a file the session never opened, and the hook demanded "/ship it" — an action the project
# CLAUDE.md forbids from the shared checkout. The controls matter more than the fix here:
# a session that DID write the unlanded file must still be convicted, or this just blinds
# the guard.

_ca_repo() { # $1=tag → echoes a repo with origin/main and one unlanded commit touching $2
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add -A; git commit -q -m base; git push -q -u origin main
    mkdir -p config; echo 'x' > "$2"; git add -A; git commit -q -m "sibling work" ) >/dev/null 2>&1
  printf '%s' "$w"
}
_ca_tr() { # $1=out $2..=paths the session wrote
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys
out, paths = sys.argv[1], sys.argv[2:]
rows = [{"type":"user","message":{"content":"go"}}]
for p in paths:
    rows.append({"type":"assistant","message":{"content":[
        {"type":"tool_use","name":"Edit","input":{"file_path":p}}]}})
rows.append({"type":"assistant","message":{"content":[{"type":"text","text":"✅ Complete — all done."}]}})
open(out,"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
PY
  printf '%s' "$out"
}

@test "attribution: an unlanded commit this session did NOT write must not convict" {
  w="$(_ca_repo att1 config/kitty.conf)"
  tr="$(_ca_tr "$BATS_TEST_TMPDIR/a1.jsonl" "$w/some/other/file.ts")"
  run bash -c "printf '{\"session_id\":\"S1\",\"cwd\":\"$w\",\"transcript_path\":\"$tr\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  # must NOT block; and the IDL must say WHY (exonerated), not merely 'clean'
  ! printf '%s' "$output" | grep -q '"decision":"block"' || false
  grep -q 'exonerated' "$COMPLETION_IDL"
}

@test "attribution CONTROL: an unlanded commit this session DID write still convicts" {
  w="$(_ca_repo att2 config/kitty.conf)"
  tr="$(_ca_tr "$BATS_TEST_TMPDIR/a2.jsonl" "$w/config/kitty.conf")"
  run bash -c "printf '{\"session_id\":\"S2\",\"cwd\":\"$w\",\"transcript_path\":\"$tr\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"decision":"block"'
}

@test "attribution: cannot-tell (no transcript) stays as strict as before — still convicts" {
  w="$(_ca_repo att3 config/kitty.conf)"
  run bash -c "printf '{\"session_id\":\"S3\",\"cwd\":\"$w\",\"transcript_path\":\"/nonexistent.jsonl\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  # no transcript => no close-tell either; the point is it must never EXONERATE on ignorance
  ! grep -q 'exonerated' "$COMPLETION_IDL"
}

# ── LIVE-PEER-OWNED (2026-08-03): the 📦 state the escape hatch could not express ────────────────
# End-to-end over the same conviction the unit suite pins in tests/peer-owned.bats: session
# claude-infrastructure-323 — read-only research turn, clean tree, ZERO files written — blocked 3/3
# for two commits made by claude-infrastructure-234, which was still running. Its only compliant
# answers were to land a live peer's commits from the shared checkout (the dfacccd data-loss
# incident .claude/CLAUDE.md forbids) or to stay blocked forever.
# The CONTROL is the whole point: with the peer DEAD the same close still fires, because that is the
# /handoff + --recycle successor, whose job IS to land what it inherited.

# `>/dev/null 2>&1` on the background job: these run inside `$( )`, and a command substitution
# returns when the captured pipe closes, not when the child exits — an inherited pipe hangs it for
# the full sleep (measured while writing tests/peer-owned.bats).
_ca_live_pid() { sleep 300 >/dev/null 2>&1 & local p=$!
  printf '%s\n' "$p" >> "$BATS_TEST_TMPDIR/pids"; printf '%s' "$p"; }
# REAPED, not merely killed: an unreaped zombie still answers `kill -0` with rc 0, so a "dead" peer
# fixtured without the wait is read as alive (MEMORY.md kill-on-reaped-child-fails-fast-path-hides-it).
_ca_dead_pid() { sleep 300 >/dev/null 2>&1 & local p=$!
  kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; printf '%s' "$p"; }
_ca_reg() { # <paneUUID> <pid> <startedAt_epoch> <cwd> <session_id>
  jq -nc --arg u "$1" --arg n "claude-peer-$1" --arg c "$4" --arg s "$5" \
         --argjson p "$2" --argjson t "$(( $3 * 1000 ))" \
    '{paneUUID:$u,name:$n,cwd:$c,account:"a",pid:$p,startedAt:$t,session_id:$s}' \
    > "$CC_REGISTRY_DIR/$1.json"
}

@test "LIVE-PEER-OWNED: a write-free close over a still-live peer's commits must NOT block" {
  w="$(_ca_repo pown config/kitty.conf)"
  _ca_reg 234 "$(_ca_live_pid)" "$(( $(date +%s) - 3600 ))" "$w" peer-234
  tr="$(_ca_tr "$BATS_TEST_TMPDIR/pown.jsonl")"
  run bash -c "printf '{\"session_id\":\"S9\",\"cwd\":\"$w\",\"transcript_path\":\"$tr\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q '"decision":"block"' || false
  # the IDL must name the STATE, not merely say clean — an exoneration is a decision, not a non-event
  grep -q 'unlanded-live-peer-owned' "$COMPLETION_IDL"
}

@test "LIVE-PEER-OWNED CONTROL: the SAME close with the peer DEAD still convicts (successor lands)" {
  w="$(_ca_repo pdead config/kitty.conf)"
  _ca_reg 234 "$(_ca_dead_pid)" "$(( $(date +%s) - 3600 ))" "$w" peer-234
  tr="$(_ca_tr "$BATS_TEST_TMPDIR/pdead.jsonl")"
  run bash -c "printf '{\"session_id\":\"S10\",\"cwd\":\"$w\",\"transcript_path\":\"$tr\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"decision":"block"'
}

@test "LIVE-PEER-OWNED CONTROL: a live peer does NOT launder a commit this session DID write" {
  w="$(_ca_repo pmine config/kitty.conf)"
  _ca_reg 234 "$(_ca_live_pid)" "$(( $(date +%s) - 3600 ))" "$w" peer-234
  tr="$(_ca_tr "$BATS_TEST_TMPDIR/pmine.jsonl" "$w/config/kitty.conf")"
  run bash -c "printf '{\"session_id\":\"S11\",\"cwd\":\"$w\",\"transcript_path\":\"$tr\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"decision":"block"'
}

# ── LANDED ≠ LIVE: the 🚀 rung the guard was never taught (face 4) ──
@test "🚀: '✅ Complete & live on trunk' while the live layer is PAST its converge budget ⇒ FIRE" {
  local w; w="$(mkrepo_landed_not_live bl1)"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/live-bl1" WRAP_LIVE_BUDGET_COMMITS=0
  run run_ca "$(mkfix "✅ Complete & live on trunk — safe to close, nothing unsaved.")" "$w"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | /usr/bin/grep -q 'LANDED BUT NOT LIVE'
}

@test "🚀 CONTROL: the SAME close, live layer AT the landed sha ⇒ ABSTAIN (not a blanket alarm)" {
  local w; w="$(mkrepo_landed_not_live bl2)"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/live-bl2" WRAP_LIVE_BUDGET_COMMITS=0
  git -C "$WRAP_LIVE_REPO" checkout -q --detach origin/main 2>/dev/null
  run run_ca "$(mkfix "✅ Complete & live on trunk — safe to close, nothing unsaved.")" "$w"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | /usr/bin/grep -q '"decision":"block"'; then return 1; fi
}

# ── the ADDED-FILE cause: the same close, a budget nowhere near tripping, and it must STILL fire ──
# The measured hole (backlog 99b715f31a98): a landing that ADDS a file is not stale on the live
# layer, it is ABSENT — ~/.claude is per-file symlinks, so there is no link and every `command -v` /
# `[ -f ]` consumer guard silently skips. The default budget (25 commits / 60 min) is an EDIT's
# budget and cannot cover it. This guard consumes RUNG=🚀, so the test is that the ledger's added-file
# breach reaches the guard at all — and that the fact it states names the right cause.
@test "🚀 ADDED FILE: a landing that ADDS a file convicts at lag 1, INSIDE the default budget" {
  local w; w="$(mkrepo_landed bl4)"
  ( cd "$w" || exit 1; echo n > newthing.sh; git add newthing.sh; git commit -q -m "adds a file"; git push -q origin main ) >/dev/null 2>&1
  git clone -q "$BATS_TEST_TMPDIR/o-bl4.git" "$BATS_TEST_TMPDIR/live-bl4" >/dev/null 2>&1
  git -C "$BATS_TEST_TMPDIR/live-bl4" checkout -q --detach origin/main~1 >/dev/null 2>&1
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/live-bl4"
  unset WRAP_LIVE_BUDGET_COMMITS          # the DEFAULT 25 — nothing near tripping at a lag of 1
  run run_ca "$(mkfix "✅ Complete & live on trunk — safe to close, nothing unsaved.")" "$w"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | /usr/bin/grep -q 'LANDED BUT NOT LIVE'
  printf '%s' "$output" | /usr/bin/grep -q 'NEW file'
  # the sentence the pre-2026-08-09 code would have said here, and which is FALSE at a lag of 1
  if printf '%s' "$output" | /usr/bin/grep -q 'PAST its converge budget'; then return 1; fi
}

@test "🚀 CONTROL: an unrelated live repo (different origin) must NOT convict — fail-open" {
  local w; w="$(mkrepo_landed_not_live bl3)"
  local other; other="$(mkrepo_landed other3)"
  export WRAP_LIVE_REPO="$other" WRAP_LIVE_BUDGET_COMMITS=0
  run run_ca "$(mkfix "✅ Complete & live on trunk — safe to close, nothing unsaved.")" "$w"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | /usr/bin/grep -q '"decision":"block"'; then return 1; fi
}

# ── ⛔ BLOCKED ON THE OPERATOR: the rung the guard was never taught (2026-08-07) ────────────────
# A close read "✅ SAFE TO CLOSE — nothing of mine is open" — true over every git fact — while a
# blocking operator decision sat in paragraph 4 of its own prose. The term CONSUMES wrap-ledger's
# RUNG verdict (it never re-derives it and never reads the cc-decide store), so the fixture is a
# STUB LEDGER through the hook's WRAP_LEDGER_BIN seam: the ledger's own suite proves it can compute
# ⛔, and what is untested here is whether the hook honours it.
#
# NOTE (contradicts the brief): the pre-existing suite does NOT stub WRAP_LEDGER_BIN — every case
# above drives the REAL scripts/wrap-ledger.sh over a throwaway git fixture. This stub is new, and
# is deliberately confined to the cases below so no existing case changes oracle.
mkledger() { # $1=tag  $2..=KEY=VAL lines → echoes a stub wrap-ledger path (caller EXPORTs it; an
             # export inside the `$( )` this is called from dies with the subshell)
  local p="$BATS_TEST_TMPDIR/wl-$1.sh" f; shift
  { printf '%s\n' '#!/usr/bin/env bash'
    for f in "$@"; do printf 'printf "%%s\\n" %s\n' "'$f'"; done
  } > "$p"
  printf '%s' "$p"
}
CA_BLOCKED_LEDGER=(DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 TRUNK=origin/main BLOCKED=1 RUNG=⛔)

@test "⛔: a confident done-assertion while the ledger says BLOCKED ⇒ FIRE" {
  WRAP_LEDGER_BIN="$(mkledger blk1 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" \
             "$BATS_TEST_TMPDIR" "blk-1"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | /usr/bin/grep -q 'BLOCKED ON YOU'
  printf '%s' "$output" | /usr/bin/grep -q '1 decision(s) filed this session are open'
  printf '%s' "$output" | /usr/bin/grep -q 'cc-decide list --open'
  /usr/bin/grep -q '"arm":"ledger"' "$COMPLETION_IDL"
  /usr/bin/grep -q '"rung":"⛔"' "$COMPLETION_IDL"
}

# The fixture must be able to go BOTH ways, or the positive above is vacuous: the SAME close over a
# ✅ ledger is the legitimate close this guard must never touch.
@test "⛔ CONTROL: the SAME close over a ✅ ledger ⇒ ABSTAIN (ledger-clean)" {
  WRAP_LEDGER_BIN="$(mkledger blk2 DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 \
                              TRUNK=origin/main BLOCKED=0 RUNG=✅)"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" \
             "$BATS_TEST_TMPDIR" "blk-2"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"ledger-clean"' "$COMPLETION_IDL"
}

# The close-tell gate (hooks/completion-assert.sh, the CLOSE / CA_SETTLED test) still governs: a
# ⛔ ledger alone is not a fire — this hook judges a CLOSE, not a session.
@test "⛔: a message that is not a close ⇒ ABSTAIN no-close-tell even over a ⛔ ledger" {
  WRAP_LEDGER_BIN="$(mkledger blk3 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "Investigating the auth flow; the grep returned four call sites.")" \
             "$BATS_TEST_TMPDIR" "blk-3"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"no-close-tell"' "$COMPLETION_IDL"
}

# A ledger that cannot compute its rung abstains BEFORE any term reads it — unchanged by this term.
@test "⛔: an uncomputable rung (RUNG=?) ⇒ ABSTAIN ledger-uncomputable, unchanged" {
  WRAP_LEDGER_BIN="$(mkledger blk4 DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 \
                              TRUNK=origin/main BLOCKED=1 'RUNG=?')"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" \
             "$BATS_TEST_TMPDIR" "blk-4"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"ledger-uncomputable"' "$COMPLETION_IDL"
}

# A non-numeric / absent BLOCKED must not break the term or emit a garbage count — it degrades to
# the `?` sentinel, exactly as LIVE_LAG does in the 🚀 term.
@test "⛔: a BLOCKED field that is absent degrades to '?' and still fires" {
  WRAP_LEDGER_BIN="$(mkledger blk5 DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 \
                              TRUNK=origin/main RUNG=⛔)"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" \
             "$BATS_TEST_TMPDIR" "blk-5"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | /usr/bin/grep -q '? decision(s) filed this session are open'
}

# The one-shot latch bounds the new term exactly as it bounds the others.
@test "⛔ LATCH: the identical close fires once, then silent" {
  WRAP_LEDGER_BIN="$(mkledger blk6 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  local tx; tx="$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")"
  run run_ca "$tx" "$BATS_TEST_TMPDIR" "blk-latch"; [ "$status" -eq 0 ]; fired "$output"
  run run_ca "$tx" "$BATS_TEST_TMPDIR" "blk-latch"; [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"latched-already-fired"' "$COMPLETION_IDL"
}

# …and so does COMPLETION_MAX, on DISTINCT closes (which the latch cannot bound).
@test "⛔ CAP: distinct ⛔ closes fire to COMPLETION_MAX then go silent" {
  export COMPLETION_MAX=1
  WRAP_LEDGER_BIN="$(mkledger blk7 "${CA_BLOCKED_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green, nothing unsaved.")" \
             "$BATS_TEST_TMPDIR" "blk-cap"
  [ "$status" -eq 0 ]; fired "$output"
  run run_ca "$(mkfix "All complete — nothing to do.")" "$BATS_TEST_TMPDIR" "blk-cap"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"capped:1>=1"' "$COMPLETION_IDL"
}

# ── D6 — the ORIGIN Pyramid-close contract (CLOSE_INTEGRITY W1) ─────────────────────────────────
# The one close every other arm waves through: ledger ✅, real written work, a close-shaped
# message — and the operator's two standing questions (Complication/Solution/Outcome + an explicit
# good-to-close verdict) unanswered. D6 owns exactly that gap; everything it abstains on is a
# stated policy, and each abstain direction below is pinned.

_d6_tr() { # $1=out $2=final-text $3..=paths the session wrote
  local out="$1" text="$2"; shift 2
  python3 - "$out" "$text" "$@" <<'PY'
import json, sys
out, text, paths = sys.argv[1], sys.argv[2], sys.argv[3:]
rows = [{"type":"user","message":{"content":"go"}}]
for p in paths:
    rows.append({"type":"assistant","message":{"content":[
        {"type":"tool_use","name":"Edit","input":{"file_path":p}}]}})
rows.append({"type":"assistant","message":{"content":[{"type":"text","text":text}]}})
open(out,"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
PY
  printf '%s' "$out"
}

@test "D6 FIRE: origin + landed ✅ + real writes + close-tell, shape missing ⇒ block names the contract" {
  local w; w="$(mkrepo_landed d6f)"
  tr="$(_d6_tr "$BATS_TEST_TMPDIR/d6f.jsonl" "Everything is done and landed on trunk." "$w/base.txt")"
  run run_ca "$tr" "$w" "d6-sess-1"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'Origin-session close contract'
  printf '%s' "$output" | grep -q 'Complication:'
  grep -q '"arm":"shape"' "$COMPLETION_IDL"
}

@test "D6 CONTROL: the SAME fixture with the full shape present ⇒ ABSTAIN ledger-clean" {
  local w; w="$(mkrepo_landed d6c)"
  tr="$(_d6_tr "$BATS_TEST_TMPDIR/d6c.jsonl" "✅ Complete & live on trunk.
Complication: silent closes passed every rail.
Solution: a D6 arm in completion-assert, landed abc123.
Outcome: origin closes now answer the operator's two questions.
Good to close: yes — complete, durable, deployed live, no loose ends; follow-on: none." "$w/base.txt")"
  run run_ca "$tr" "$w" "d6-sess-2"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -q '"decision":"block"'; then echo "blocked: $output" >&2; false; fi
}

@test "D6 ABSTAIN: a FIRED PEER (valid stamp for this pane+cwd) is exempt — its close is the ping" {
  local w; w="$(mkrepo_landed d6p)"
  export ITERM_SESSION_ID="w0t0p0:42"
  jq -n --arg c "$w" '{paneUUID:"42", cwd:$c, selfRetire:true, closedAt:null}' > "$CC_FIRED_DIR/42.json"
  tr="$(_d6_tr "$BATS_TEST_TMPDIR/d6p.jsonl" "Everything is done and landed on trunk." "$w/base.txt")"
  run run_ca "$tr" "$w" "d6-sess-3"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -q 'Origin-session close contract'; then false; fi
}

@test "D6 ABSTAIN: a WRITE-FREE session is never forced into a work-close shape" {
  local w; w="$(mkrepo_landed d6w)"
  run run_ca "$(mkfix "Everything requested is done — nothing left to do.")" "$w" "d6-sess-4"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -q 'Origin-session close contract'; then false; fi
}

@test "D6 SEAM: CC_CLOSE_SHAPE=0 disables the arm outright" {
  local w; w="$(mkrepo_landed d6k)"
  tr="$(_d6_tr "$BATS_TEST_TMPDIR/d6k.jsonl" "Everything is done and landed on trunk." "$w/base.txt")"
  CC_CLOSE_SHAPE=0 run_ca "$tr" "$w" "d6-sess-5" > "$BATS_TEST_TMPDIR/d6k.out"
  if grep -q '"decision":"block"' "$BATS_TEST_TMPDIR/d6k.out"; then false; fi
}

@test "D6 on 👤: operator-steps rung with shape missing ⇒ the contract still fires" {
  local w; w="$(mkrepo_landed d6y)"
  export CC_BACKLOG_STUB_JSON='[{"session":"d6-sess-6","title":"restart Cursor"}]'
  tr="$(_d6_tr "$BATS_TEST_TMPDIR/d6y.jsonl" "My side is done and landed; one step is filed for you." "$w/base.txt")"
  run run_ca "$tr" "$w" "d6-sess-6"
  unset CC_BACKLOG_STUB_JSON
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'Origin-session close contract'
}

# ── W2 CUSTODY — a done-claim over unreturned dispatched work is the wave-abandonment close ─────
@test "custody: 'done' over 2 unreturned dispatches on a clean landed tree ⇒ FIRE naming them" {
  local w; w="$(mkrepo_landed cust)"
  STUB="$BATS_TEST_TMPDIR/cust-stub"; printf '%s\n' '#!/usr/bin/env bash' 'echo 2' > "$STUB"; chmod +x "$STUB"
  export CC_CUSTODY_BIN="$STUB"
  run run_ca "$(mkfix "Everything requested is done — the wave is running and I'm finished here.")" "$w" "cust-sess-1"
  unset CC_CUSTODY_BIN
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'dispatched session(s) have NOT returned'
}

# ── LAND IN FLIGHT (land-architecture-100p §5 P4, defect 3) ──────────────────────────────────────
# The dual of the LIVE-PEER-OWNED case above, one process closer to home: there the unlanded
# commits are a live PEER's, here they are THIS session's and its own land is already running.
# `trunk..HEAD` is unlanded for a land's whole duration, so this term convicted a session mid-land
# and every compliant answer pushed it toward a SECOND /ship on the same worktree — which can only
# queue behind its own sibling on the machine-wide mutex. The exoneration asserts nothing about the
# land's outcome; the moment the marker stops adjudicating live, the conviction returns unaltered.

@test "LAND-IN-FLIGHT: a close over THIS session's own running land must NOT block" {
  w="$(_ca_repo lif config/kitty.conf)"
  tr="$(_ca_tr "$BATS_TEST_TMPDIR/lif.jsonl" "$w/config/kitty.conf")"   # the commits ARE this session's
  sleep 300 >/dev/null 2>&1 & lander=$!
  printf 'pid=%s\nlstart=%s\nstarted=%s\nbranch=feat/x\n' \
    "$lander" "$(ps -o lstart= -p "$lander")" "$(date +%s)" \
    > "$(git -C "$w" rev-parse --absolute-git-dir)/ship-land-inflight"

  run bash -c "printf '{\"session_id\":\"SL1\",\"cwd\":\"$w\",\"transcript_path\":\"$tr\"}' | bash '$HOOK'"
  kill "$lander" 2>/dev/null || true
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q '"decision":"block"' || false
  # An exoneration is a decision, not a non-event — the IDL must name the STATE.
  grep -q 'unlanded-land-in-flight' "$COMPLETION_IDL"
}

@test "LAND-IN-FLIGHT CONTROL: the SAME close with a STALE marker still convicts" {
  # Without this the test above passes for the wrong reason. `$$` is alive but its start-time
  # cannot match, so the marker is a dead land's residue — and residue must not buy an exoneration
  # that hides genuinely parked work (the FM1 park-and-call-it-done hazard).
  w="$(_ca_repo lifc config/kitty.conf)"
  tr="$(_ca_tr "$BATS_TEST_TMPDIR/lifc.jsonl" "$w/config/kitty.conf")"
  printf 'pid=%s\nlstart=%s\nstarted=%s\nbranch=feat/x\n' \
    "$$" 'Thu Jan  1 00:00:00 2020' "$(date +%s)" \
    > "$(git -C "$w" rev-parse --absolute-git-dir)/ship-land-inflight"

  run bash -c "printf '{\"session_id\":\"SL2\",\"cwd\":\"$w\",\"transcript_path\":\"$tr\"}' | bash '$HOOK'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '"decision":"block"'
}

# ── DIRTY ATTRIBUTION: the sibling's-dirt conviction (2026-08-11) ────────────────────────────────
# MEASURED twice — session 44dc8891 in wt-149789b69fc4 ("dirty tree (4 file(s))", backlog
# ce91e9583df1) and session a1dd4283 in wt-592061637f80 ("dirty tree (8 file(s))" for files staged
# by a PRIOR session, backlog 9be5e66e1c34). Both wrote nothing; both were told to drive a sibling's
# in-flight work to done, which is the G4 violation CLAUDE.md forbids by name. `_ca_mine dirty`
# answers rc 2 for them (a write-free transcript is not innocence), and rc 2 convicts — so the
# ordering term supplies the positive evidence instead. See hooks/lib/peer-owned.sh
# § THE DIRTY TERM'S ORDERING PROOF for why ordering, and why there is no liveness term.

_ca_tr_ts() { # $1=out $2=first-record epoch $3..=paths the session wrote
  local out="$1" ts="$2"; shift 2
  python3 - "$out" "$ts" "$@" <<'PY'
import json, sys, time
out, ts, paths = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
iso = time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(ts)) + ".000Z"
rows = [{"type":"user","timestamp":iso,"message":{"content":"go"}}]
for p in paths:
    rows.append({"type":"assistant","timestamp":iso,"message":{"content":[
        {"type":"tool_use","name":"Edit","input":{"file_path":p}}]}})
rows.append({"type":"assistant","timestamp":iso,"message":{"content":[
    {"type":"text","text":"✅ Complete — all done."}]}})
open(out,"w").write("\n".join(json.dumps(r) for r in rows)+"\n")
PY
  printf '%s' "$out"
}

# clean + landed, then dirtied — so DIRTY is the ONLY ledger contradiction under test.
_ca_dirty_repo() { # <tag> → echoes the worktree, with base.txt modified
  local w; w="$(mkrepo_landed "$1")"
  echo "sibling in-flight edit" >> "$w/base.txt"
  printf '%s' "$w"
}

_ca_touch_at() { # <epoch> <file>
  local s; s="$(date -r "$1" +%Y%m%d%H%M.%S 2>/dev/null || date -d "@$1" +%Y%m%d%H%M.%S 2>/dev/null)"
  touch -t "$s" "$2"
}

@test "dirty attribution: dirt that PREDATES this session ⇒ ABSTAIN (the measured conviction)" {
  local w tr now; w="$(_ca_dirty_repo dpa1)"; now="$(date +%s)"
  _ca_touch_at "$(( now - 7200 ))" "$w/base.txt"
  tr="$(_ca_tr_ts "$BATS_TEST_TMPDIR/dpa1.jsonl" "$(( now - 3600 ))")"
  run run_ca "$tr" "$w"
  [ "$status" -eq 0 ]
  ! fired "$output" || false
  grep -q 'dirty-predates-session' "$COMPLETION_IDL"
}

# THE CONTROL THE FIX LIVES OR DIES BY: dirt made after this session started is the case the guard
# exists for, and it is where a Bash `sed -i` with no tool_use record lands.
@test "dirty attribution CONTROL: dirt made AFTER the session started ⇒ still FIRES" {
  local w tr now; w="$(_ca_dirty_repo dpa2)"; now="$(date +%s)"
  _ca_touch_at "$now" "$w/base.txt"
  tr="$(_ca_tr_ts "$BATS_TEST_TMPDIR/dpa2.jsonl" "$(( now - 3600 ))")"
  run run_ca "$tr" "$w"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'dirty tree'
}

# GATED ON rc 2 ALONE. A session that provably wrote the dirty path is rc 0 — positive self-evidence
# — and the ordering term must never be consulted, let alone override it. Backdating the mtime here
# is deliberate: it makes the ordering term WANT to exonerate, so the gate is the only thing that
# can keep this red-if-broken.
@test "dirty attribution CONTROL: a path this session DID write still convicts, old mtime or not" {
  local w tr now; w="$(_ca_dirty_repo dpa3)"; now="$(date +%s)"
  _ca_touch_at "$(( now - 7200 ))" "$w/base.txt"
  tr="$(_ca_tr_ts "$BATS_TEST_TMPDIR/dpa3.jsonl" "$(( now - 3600 ))" "$w/base.txt")"
  run run_ca "$tr" "$w"
  [ "$status" -eq 0 ]; fired "$output"
}

# THE 9 FIXTURES STAY STRICT. Every pre-existing transcript here is built by mkfix/_ca_tr, which
# record no `.timestamp`, so the session start is unresolvable ⇒ cannot-tell ⇒ convict, exactly as
# before this term existed. That is what keeps the widening from reaching them.
@test "dirty attribution CONTROL: a transcript with NO timestamp stays strict ⇒ FIRES" {
  local w now; w="$(_ca_dirty_repo dpa4)"; now="$(date +%s)"
  _ca_touch_at "$(( now - 7200 ))" "$w/base.txt"
  run run_ca "$(mkfix "Done. Complete — nothing left to do.")" "$w"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── DIRTY ATTRIBUTION, SECOND AXIS: the residue the ordering term names (2026-08-12) ─────────────
# Ordering only ever reaches dirt OLDER than the session, and its own residue note says the rest
# "has to" stay convicted. MEASURED 2026-08-11 that residue is the live case: session
# claude-infrastructure-387 (backlog 76e444a40188), a read-only ORIGIN turn with zero file-edit
# records, blocked 3 of 3 over a sibling's in-flight work made 38 minutes INTO its run — in a
# checkout whose .claude/CLAUDE.md forbids committing, so no close it could write was accepted.
# The exoneration is earned on the SECOND axis instead: the mtime falls in a gap between this
# session's Bash execution windows, so no command of its own could have produced it.
# See hooks/lib/peer-owned.sh § THE SAME QUESTION ON A SECOND AXIS.

# Like _ca_tr_ts, but with a distinct LAST record and explicit Bash execution windows.
#   --win A B  a Bash tool_use at A paired with its tool_result at B   ·  --bg A B  the same,
#   backgrounded. The two timestamps must differ: a transcript whose records all share one stamp
#   brackets nothing, which is exactly why every fixture built by _ca_tr_ts above stays strict.
_ca_tr_exec() { # <out> <first_ts> <last_ts> [--win A B | --bg A B]...
  local out="$1"; shift
  python3 - "$out" "$@" <<'PY'
import json, sys, time
out, first, last, args = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4:]
def iso(t): return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(int(t))) + ".000Z"
rows = [{"type": "user", "timestamp": iso(first), "message": {"content": "go"}}]
for n, i in enumerate(range(0, len(args), 3)):
    tid, inp = "t%d" % n, {"command": "git status"}
    if args[i] == "--bg":
        inp["run_in_background"] = True
    rows.append({"type": "assistant", "timestamp": iso(args[i + 1]), "message": {"content": [
        {"type": "tool_use", "id": tid, "name": "Bash", "input": inp}]}})
    rows.append({"type": "user", "timestamp": iso(args[i + 2]), "message": {"content": [
        {"type": "tool_result", "tool_use_id": tid, "content": "ok"}]}})
rows.append({"type": "assistant", "timestamp": iso(last), "message": {"content": [
    {"type": "text", "text": "✅ Complete — all done."}]}})
open(out, "w").write("\n".join(json.dumps(r) for r in rows) + "\n")
PY
  printf '%s' "$out"
}

@test "dirty attribution: dirt in a GAP between this session's commands ⇒ ABSTAIN (the ORIGIN case)" {
  local w tr now; w="$(_ca_dirty_repo dxa1)"; now="$(date +%s)"
  _ca_touch_at "$(( now - 1800 ))" "$w/base.txt"
  tr="$(_ca_tr_exec "$BATS_TEST_TMPDIR/dxa1.jsonl" "$(( now - 3600 ))" "$(( now - 10 ))" \
        --win "$(( now - 2400 ))" "$(( now - 2395 ))" --win "$(( now - 600 ))" "$(( now - 595 ))")"
  run run_ca "$tr" "$w"
  [ "$status" -eq 0 ]
  ! fired "$output" || false
  grep -q 'dirty-outside-session-exec' "$COMPLETION_IDL"
}

# THE CONTROL THIS AXIS LIVES OR DIES BY, and it is where the Bash blind spot actually lands: a
# `sed -i` leaves no tool_use record of the WRITE, but it cannot run outside its own command's
# window, so the mtime is inside one and the guard must still convict.
@test "dirty attribution CONTROL: dirt stamped INSIDE an execution window ⇒ still FIRES" {
  local w tr now; w="$(_ca_dirty_repo dxa2)"; now="$(date +%s)"
  _ca_touch_at "$(( now - 2398 ))" "$w/base.txt"
  tr="$(_ca_tr_exec "$BATS_TEST_TMPDIR/dxa2.jsonl" "$(( now - 3600 ))" "$(( now - 10 ))" \
        --win "$(( now - 2400 ))" "$(( now - 2395 ))")"
  run run_ca "$tr" "$w"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'dirty tree'
}

# A detached command outlives the window the whole argument rests on, so one such record anywhere
# abstains for the entire session. Same fixture as the ABSTAIN case above but for the flag — so the
# flag is the only thing that can keep this red-if-broken.
@test "dirty attribution CONTROL: a backgrounded Bash call ⇒ still FIRES" {
  local w tr now; w="$(_ca_dirty_repo dxa3)"; now="$(date +%s)"
  _ca_touch_at "$(( now - 1800 ))" "$w/base.txt"
  tr="$(_ca_tr_exec "$BATS_TEST_TMPDIR/dxa3.jsonl" "$(( now - 3600 ))" "$(( now - 10 ))" \
        --bg "$(( now - 2400 ))" "$(( now - 2395 ))")"
  run run_ca "$tr" "$w"
  [ "$status" -eq 0 ]; fired "$output"
}

# ── D6 MENTION vs USE — the template was its own bypass (item 3b464e94b3ff) ─────────────────────
# close_shape_ok matched the four anchors ANYWHERE in the message, and close_shape_template() emits
# lines that contain them. So a close that merely QUOTED the skeleton — echoed /wrap's block, or
# pasted D6's own block-reason back — satisfied the contract without answering one question. The
# defect is false-PASS-ONLY, so the fix is pinned from BOTH sides: the quoting close must fire, and
# the honest close (including one using the template's own <follow-on> notation) must not.

_cs_lib() { bash -c '. "$1/hooks/lib/close-shape.sh"; '"$2" _ "$REPO"; }

@test "close-shape UNIT: quoting the template answers nothing — close_shape_ok must REJECT it" {
  run _cs_lib "$REPO" 'close_shape_ok "$(close_shape_template)"'
  [ "$status" -ne 0 ]
  run _cs_lib "$REPO" 'printf "%s" "$(close_shape_missing "$(close_shape_template)")"'
  [ "$output" = "Complication: Solution: Outcome: good-to-close-verdict" ]
}

@test "close-shape CONTROL (green both sides — the no-false-FAIL half): an honest close PASSES" {
  # Deliberately includes the template's own <angle-bracket> follow-on notation and a label whose
  # value is empty: neither is a quote of the skeleton, and neither may be newly rejected.
  run _cs_lib "$REPO" 'close_shape_ok "✅ Complete & live on trunk.
Complication: the template matched itself.
Solution: the value, not the label, decides — landed abc123.
Outcome:
Good to close: yes — complete, durable, no loose ends; follow-on: <none>"'
  [ "$status" -eq 0 ]
}

@test "D6 MENTION-vs-USE: an origin close that QUOTES the template still FIRES" {
  local w; w="$(mkrepo_landed d6q)"
  tr="$(_d6_tr "$BATS_TEST_TMPDIR/d6q.jsonl" "✅ Complete & live on trunk — everything is done and landed.
The close contract wants this shape:
Complication: <what made this work necessary — one line>
Solution: <what was built/changed, with the landed sha — one line>
Outcome: <what is now true that was not before — one line>
Good to close: <yes — complete, durable, deployed live, no loose ends; follow-on: <filed ids|none> | no — <what remains + who owns it>>" "$w/base.txt")"
  run run_ca "$tr" "$w" "d6-sess-quote"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'Origin-session close contract'
  grep -q '"arm":"shape"' "$COMPLETION_IDL"
}

# ── CAP SPLIT — the terminal close was starved by the mid-wave ones (item 3b464e94b3ff) ─────────
# One counter served every arm. A wave lead's mid-wave done-claims are convicted by the LEDGER arm
# (custody open, unlanded work) and each spends a slot; by the time the wave returns and the
# TERMINAL close arrives — the only close the D6 origin contract exists for — the budget is gone
# and the contract is never asserted against. The order is structural: D6 requires contra=0, so it
# is reachable only AFTER the conviction arms fall silent. Budgets are therefore per CLASS.

@test "CAP SPLIT: mid-wave convictions spend the assert cap; the TERMINAL close still gets its shape demand" {
  export COMPLETION_MAX=3
  local w; w="$(mkrepo_landed capsplit)"
  # MID-WAVE: a clean landed tree with dispatched peers still out ⇒ the ledger arm convicts.
  STUB="$BATS_TEST_TMPDIR/capsplit-stub"; printf '%s\n' '#!/usr/bin/env bash' 'echo 2' > "$STUB"; chmod +x "$STUB"
  export CC_CUSTODY_BIN="$STUB"
  run run_ca "$(mkfix "Everything requested is done — the wave is running.")" "$w" "capsplit-s"; fired "$output"
  run run_ca "$(mkfix "All complete, nothing left to do here.")"             "$w" "capsplit-s"; fired "$output"
  run run_ca "$(mkfix "Finished — that was the main ask.")"                  "$w" "capsplit-s"; fired "$output"
  unset CC_CUSTODY_BIN
  # TERMINAL: the wave has returned (custody 0 ⇒ ✅), real writes, shape missing. The assert budget
  # is spent — the shape demand must NOT be.
  tr="$(_d6_tr "$BATS_TEST_TMPDIR/capsplit.jsonl" "Everything is done and landed on trunk." "$w/base.txt")"
  run run_ca "$tr" "$w" "capsplit-s"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | grep -q 'Origin-session close contract'
  /usr/bin/grep -q '"class":"shape"' "$COMPLETION_IDL"
}

@test "CAP SPLIT: the shape budget is itself a HARD cap (COMPLETION_SHAPE_MAX)" {
  export COMPLETION_SHAPE_MAX=1
  local w; w="$(mkrepo_landed capshape)"
  tr1="$(_d6_tr "$BATS_TEST_TMPDIR/capshape1.jsonl" "Everything is done and landed on trunk." "$w/base.txt")"
  tr2="$(_d6_tr "$BATS_TEST_TMPDIR/capshape2.jsonl" "All complete — landed, nothing left to do." "$w/base.txt")"
  run run_ca "$tr1" "$w" "capshape-s"; [ "$status" -eq 0 ]; fired "$output"
  run run_ca "$tr2" "$w" "capshape-s"; [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"capped:shape:1>=1"' "$COMPLETION_IDL"
}

@test "CAP SPLIT COMPAT (green both sides): a pre-split latch line, bare hash, counts as assert" {
  export COMPLETION_MAX=1
  local w; w="$(mkrepo_unlanded capcompat)"
  run run_ca "$(mkfix "Everything is done.")" "$w" "capcompat-s"; fired "$output"
  # rewrite the latch file into the pre-split format (hash only, no class column)
  local f; f="$(ls "$COMPLETION_STATE_DIR"/*.fired)"
  awk '{print $1}' "$f" > "$f.tmp"; mv "$f.tmp" "$f"
  run run_ca "$(mkfix "All complete, nothing to do.")" "$w" "capcompat-s"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"capped:1>=1"' "$COMPLETION_IDL"
}

# ── D7 — THE ACT LINE (CLOSE_SCANNABILITY W2, measured 2026-08-23) ─────────────────────────────
# The operator: closes "force me to scan really long and hard what the actual decisions are and
# it's not 'scan one line' for an actionable silver-plattered what to do". The founding close had a
# correct rung AND the blocker in its supporting lines and still drew "Whats blocked on me? Be
# explicit" — every arm above passed it, because the act was WELDED INTO a sentence rather than
# being a line. Parameters come from docs/research/close-scannability-2026-08-23.md.
#
# The ledger is a STUB (mkledger, as the ⛔ cases above are) because D7 CONSUMES wrap-ledger's RUNG
# verdict and never re-derives it; what is under test is whether the hook honours a 👤.
# CC_BACKLOG_STUB_JSON carries a row for the session in these cases, which is what a real 👤 means
# (a step IS filed) and which keeps D1 out of the way so each assertion names one arm.
CA_YOURS_LEDGER=(DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 TRUNK=origin/main YOURS=1 RUNG=👤)
ca_filed() { export CC_BACKLOG_STUB_JSON="[{\"id\":\"y1\",\"status\":\"blocked\",\"session\":\"$1\",\"project\":\"p\",\"title\":\"t\",\"needs\":\"finish the login\"}]"; }

# The founding evidence, reduced: three acts welded into line 1, nothing else wrong with the close.
CA_WELDED="👤 My side is done and landed — resend the code, tick Trust this browser, then close that Chrome window.
- Your code expired at 07:51Z; hit Resend and I will pull the fresh one.
- Chrome pid 35559 is still running and must be closed after you verify."

@test "D7 UNIT: an act welded into line 1 is not an act LINE" {
  . "$REPO/hooks/lib/close-shape.sh"
  [ "$(close_act_missing "$CA_WELDED")" = "act-line" ]
}

# The unit must be able to go BOTH ways or the positive above is vacuous.
@test "D7 UNIT CONTROL: the SAME close with the act on its own line PASSES" {
  . "$REPO/hooks/lib/close-shape.sh"
  run close_act_missing "👤 My side is done and landed — one step is yours.
▶ Finish this, then quit the window:
\`open -a 'Google Chrome' https://example.test/verify\`"
  [ -z "$output" ]
}

@test "D7 UNIT: the ACT: label is the second legal shape, and its VALUE is the discriminator" {
  . "$REPO/hooks/lib/close-shape.sh"
  [ -z "$(close_act_missing "👤 done
ACT: finish the login in the open Chrome window, then quit it")" ]
  [ -z "$(close_act_missing "👤 done
**ACT:** quit Chrome")" ]
  # a bare label with the act on the NEXT line is exactly the shape being ruled out
  [ "$(close_act_missing "👤 done
ACT:
finish the login")" = "act-line" ]
  # and a template placeholder answers nothing (same law as close_shape's MENTION-vs-USE)
  [ "$(close_act_missing "👤 done
ACT: <the one act>")" = "act-line" ]
}

# 13 of the 81 ▶ occurrences in the corpus are the ` ▶ cc-do [N runnable]` row INSIDE the rendered
# OPERATOR block's fence. A matcher that counts it passes a close whose real act is at line 11.
@test "D7 UNIT: a ▶ inside a fence is the rendered block, not this close's act ⇒ still missing" {
  . "$REPO/hooks/lib/close-shape.sh"
  [ "$(close_act_missing '```
OPERATOR ▸ 13 runnable now, 205 need your call
 ▶ cc-do   [13 runnable]
```
👤 My side is done and landed.
some supporting prose
more supporting prose
▶ Open this:')" = "act-line" ]
}

# …and the same fence must not COUNT against the window either, or a close that obeys the
# Silver-Platter rule (reproduce the rendered block verbatim) could never comply.
@test "D7 UNIT CONTROL: the fenced block is skipped, not counted — act at line 2 after it PASSES" {
  . "$REPO/hooks/lib/close-shape.sh"
  run close_act_missing '```
OPERATOR ▸ 13 runnable now, 205 need your call
 ▶ cc-do   [13 runnable]
```
👤 My side is done and landed — one step is yours.
▶ Run this:
`cc-do land-the-mcp-wiring`'
  [ -z "$output" ]
}

@test "D7: a 👤 close whose act is welded into prose ⇒ FIRE" {
  WRAP_LEDGER_BIN="$(mkledger act1 "${CA_YOURS_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  ca_filed "act-1"
  run run_ca "$(mkfix "$CA_WELDED")" "$BATS_TEST_TMPDIR" "act-1"
  [ "$status" -eq 0 ]; fired "$output"
  printf '%s' "$output" | /usr/bin/grep -q 'no single line IS that act'
  printf '%s' "$output" | /usr/bin/grep -q 'ACT: <one imperative sentence'
  /usr/bin/grep -q '"arm":"act"' "$COMPLETION_IDL"
  /usr/bin/grep -q '"class":"act"' "$COMPLETION_IDL"
  /usr/bin/grep -q '"rung":"👤"' "$COMPLETION_IDL"
}

# THE NEGATIVE HALF. Same ledger, same session, same substance — the act moved onto its own line.
# An assert that cannot pass a good close is indistinguishable from one that is not wired up.
@test "D7 CONTROL: the SAME close with the act on its own line ⇒ ABSTAIN (ledger-clean)" {
  WRAP_LEDGER_BIN="$(mkledger act2 "${CA_YOURS_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  ca_filed "act-2"
  run run_ca "$(mkfix "👤 My side is done and landed — one step is yours.
▶ Finish this, then quit the window:
\`open -a 'Google Chrome' https://example.test/verify\`
- Your code expired at 07:51Z; hit Resend and I will pull the fresh one.")" "$BATS_TEST_TMPDIR" "act-2"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"ledger-clean"' "$COMPLETION_IDL"
}

# THE WINDOW IS THE LEVER — the measured median act line is 6. The same message must flip on the
# window alone, or the fire above could be explained by anything else in the close.
@test "D7: an act at the measured median line 6 FIRES, and widening the window alone clears it" {
  local msg="👤 My side is done and landed.
supporting line a
supporting line b
supporting line c
supporting line d
▶ Run this:
\`cc-do finish-the-login\`"
  WRAP_LEDGER_BIN="$(mkledger act3 "${CA_YOURS_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  ca_filed "act-3"
  run run_ca "$(mkfix "$msg")" "$BATS_TEST_TMPDIR" "act-3"
  [ "$status" -eq 0 ]; fired "$output"
  CC_ACT_WINDOW=8 run run_ca "$(mkfix "$msg")" "$BATS_TEST_TMPDIR" "act-3b"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "D7 SCOPE: the SAME act-less close over a ✅ ledger ⇒ ABSTAIN (👤 is the only rung)" {
  WRAP_LEDGER_BIN="$(mkledger act4 DIRTY=0 DIRTY_N=0 UNLANDED=0 AHEAD=0 REMAINDER=0 \
                              TRUNK=origin/main YOURS=0 RUNG=✅)"; export WRAP_LEDGER_BIN
  ca_filed "act-4"
  run run_ca "$(mkfix "$CA_WELDED")" "$BATS_TEST_TMPDIR" "act-4"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"ledger-clean"' "$COMPLETION_IDL"
}

@test "D7 KILL SWITCH: CC_CLOSE_ACT=0 silences the arm" {
  WRAP_LEDGER_BIN="$(mkledger act5 "${CA_YOURS_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  ca_filed "act-5"
  CC_CLOSE_ACT=0 run run_ca "$(mkfix "$CA_WELDED")" "$BATS_TEST_TMPDIR" "act-5"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "D7 LATCH + CAP: fires to COMPLETION_ACT_MAX on distinct closes, then silent" {
  WRAP_LEDGER_BIN="$(mkledger act6 "${CA_YOURS_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  ca_filed "act-6"
  export COMPLETION_ACT_MAX=1
  run run_ca "$(mkfix "$CA_WELDED")" "$BATS_TEST_TMPDIR" "act-6"
  [ "$status" -eq 0 ]; fired "$output"
  # identical content ⇒ latched, whatever the cap says
  run run_ca "$(mkfix "$CA_WELDED")" "$BATS_TEST_TMPDIR" "act-6"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"latched-already-fired"' "$COMPLETION_IDL"
  # a DIFFERENT act-less close ⇒ the cap, named by its own class
  run run_ca "$(mkfix "👤 Landed and done — go and finish the login, then quit the window.")" \
             "$BATS_TEST_TMPDIR" "act-6"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"capped:act:1>=1"' "$COMPLETION_IDL"
}

# THE NO-DISTURBANCE PROOF. `act` is claimed ONLY when D7 fired alone; when another arm fires on the
# same message that arm's demand governs and its budget is untouched. Without this, adding D7 would
# silently divert D1's convictions into a different, smaller counter.
@test "D7 CLASS: a message that also fires D1 keeps class=assert, and both sentences are emitted" {
  WRAP_LEDGER_BIN="$(mkledger act7 "${CA_YOURS_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  export CC_BACKLOG_STUB_JSON='[]'      # nothing filed for this session ⇒ D1 convicts
  # the handoff phrase sits on line 2, not line 1 — otherwise D3 co-fires on it (settled verdict +
  # retraction in one line) and the arm string under test would be measuring three arms, not two.
  run run_ca "$(mkfix "👤 Landed and complete.
Two things remain yours, and I have written them up above.")" \
             "$BATS_TEST_TMPDIR" "act-7"
  [ "$status" -eq 0 ]; fired "$output"
  /usr/bin/grep -q '"arm":"handoff+act"' "$COMPLETION_IDL"
  /usr/bin/grep -q '"class":"assert"' "$COMPLETION_IDL"
  printf '%s' "$output" | /usr/bin/grep -q 'cc-backlog needs'
  printf '%s' "$output" | /usr/bin/grep -q 'no single line IS that act'
}

# A stale live lib (no close_act_ok) must be NO DEMAND, never a block — a Stop hook may not block
# the turn on its own misconfiguration.
@test "D7 FAIL-SAFE: an unreachable close-shape lib ⇒ silent abstain, not a block" {
  WRAP_LEDGER_BIN="$(mkledger act8 "${CA_YOURS_LEDGER[@]}")"; export WRAP_LEDGER_BIN
  ca_filed "act-8"
  CLOSE_SHAPE_LIB="$BATS_TEST_TMPDIR/no-such-close-shape.sh" \
    run run_ca "$(mkfix "$CA_WELDED")" "$BATS_TEST_TMPDIR" "act-8"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

# The other side of the pin on the D1-abstain case above: that fixture's shape — a step filed for
# THIS session (so the REAL wrap-ledger computes 👤) and a close with no act line — is exactly what
# D7 exists to catch, and here it is asserted through the real ledger rather than a stub. Without
# this, pinning the axis off up there would have removed coverage instead of separating it.
@test "D7 END-TO-END: a real 👤 ledger (not a stub) + no act line ⇒ FIRE" {
  local w; w="$(mkrepo_landed a2d7e2e)"
  export CC_BACKLOG_STUB_JSON='[{"id":"abc123","status":"blocked","session":"d7-e2e","project":"p","title":"t","needs":"run the mcp add"}]'
  run run_ca "$(mkfix "✅ Complete & live on trunk — landed, all green.

Two things remain yours before this is fully wired up.")" "$w" "d7-e2e"
  [ "$status" -eq 0 ]; fired "$output"
  /usr/bin/grep -q '"rung":"👤"' "$COMPLETION_IDL"
  printf '%s' "$output" | /usr/bin/grep -q 'no single line IS that act'
}

# …and the same real ledger with the act stated as a line ⇒ the arm is silent. The pair is the
# no-false-FAIL half through the REAL wrap-ledger, matching the stubbed pair above.
@test "D7 END-TO-END CONTROL: the same real 👤 ledger WITH an act line ⇒ no act demand" {
  local w; w="$(mkrepo_landed a2d7e2eok)"
  export CC_BACKLOG_STUB_JSON='[{"id":"abc123","status":"blocked","session":"d7-e2e-ok","project":"p","title":"t","needs":"run the mcp add"}]'
  run run_ca "$(mkfix "👤 My side is done & landed — one step is yours.
▶ Run this:
\`cc-do run-the-mcp-add\`")" "$w" "d7-e2e-ok"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  /usr/bin/grep -q '"reason":"ledger-clean"' "$COMPLETION_IDL"
}
