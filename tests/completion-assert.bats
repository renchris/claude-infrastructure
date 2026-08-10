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
