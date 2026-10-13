#!/usr/bin/env bats
# completion-assert-forks.bats — the process budget of hooks/completion-assert.sh, and proof that
# cutting it changed nothing the hook prints, logs or latches.
#
# The defect this pins (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md, Stop hooks): completion-assert
# was cancelled at its 5 s timeout 3 times in 30 minutes at a load of 520-680. Every Stop that had
# assistant text started python3 for the research relay check, even for a session with no route
# record, where that check is a no-op. A Stop that reached the ledger then waited on the ledger's
# BUSY probe (a process-table scan plus lsof, bounded at 8 s) for fields it never reads, walked its
# own ancestry twice, and started `grep | head -1 | cut` for each of eighteen ledger fields.
#
# Parity is against the REAL pre-change hook and ledger, rebuilt from git
# (stop-hook-forks-helpers.bash). The two arms run one after the other over the SAME paths, from the
# same blank state. Counts come from PATH stubs that log every external command and then exec it.
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

load stop-hook-forks-helpers

setup_file() {
  STUB="$BATS_FILE_TMPDIR/stub"
  shf_build_stubs "$STUB"
  export STUB
}

setup() {
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID WRAP_SESSION_ID ITERM_SESSION_ID \
        KITTY_WINDOW_ID CC_PANE_ID WRAP_LEDGER_BIN CLAUDE_CONFIG_DIR AGENT_IDENTITY_LIB
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  OLD="$BATS_TEST_TMPDIR/old"
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  export COMPLETION_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export COMPLETION_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_IDL="$BATS_TEST_TMPDIR/cc-idl.jsonl"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/continue-idl.jsonl"
  export CONTINUE_LOG="$BATS_TEST_TMPDIR/continue.log"
  export WRAP_TRUNK="origin/main"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-repo"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"
  export PEER_OWNED_HOMES="$BATS_TEST_TMPDIR/acct-none"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/no-programs.json"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  # Fixture process tables: the hook's ancestry walk and the ledger's BUSY probe read these files
  # instead of running `ps`, so neither arm depends on the box or on how deep the runner is nested.
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/pstable"
  export CC_PROC_SCOPE_PS="$BATS_TEST_TMPDIR/pstable"
  printf '1 0 /sbin/launchd\n' > "$CC_WF_PSTABLE_FILE"
  : > "$CC_BACKLOG_FILE"
  W="$BATS_TEST_TMPDIR/w"
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/completion-assert.sh scripts/wrap-ledger.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# blank — every directory the hook writes, emptied: each arm starts from the same state.
blank() {
  local d
  for d in "$HOME" "$COMPLETION_STATE_DIR" "$CC_POSTLAND_DIR" "$CC_DECISIONS_DIR" "$CC_FIRED_DIR" \
           "$CC_CUSTODY_DIR" "$CC_REGISTRY_DIR" "$CC_MAILBOX_DIR" "$BATS_TEST_TMPDIR/tmp"; do
    rm -rf "$d"; mkdir -p "$d"
  done
  rm -f "$COMPLETION_IDL" "$CC_IDL" "$CONTINUE_IDL" "$CONTINUE_LOG"
}

transcript() { # <assistant close text> [<edited path>] → a transcript; echoes its path
  local tp="$BATS_TEST_TMPDIR/t.jsonl"
  jq -cn '{type:"user",message:{role:"user",content:"make the change"}}' > "$tp"
  if [ -n "${2:-}" ]; then
    jq -cn --arg p "$2" '{type:"assistant",message:{content:[{type:"tool_use",name:"Edit",input:{file_path:$p}}]}}' >> "$tp"
  fi
  jq -cn --arg t "$1" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' >> "$tp"
  printf '%s' "$tp"
}
payload() { jq -cn --arg c "$W" --arg t "${1:-}" --arg s "${2:-sidA}" '{session_id:$s,cwd:$c,transcript_path:$t}'; }

# stop <old|new> <label> — one Stop through that arm's hook; stdin is the payload.
stop() {
  local root="$REPO"
  [ "$1" = old ] && root="$OLD"
  TMPDIR="$BATS_TEST_TMPDIR/tmp" shf_run "$2" "$root/hooks/completion-assert.sh" || true
  shf_keep "$2" "$COMPLETION_IDL" "$COMPLETION_STATE_DIR"
}

@test "a Stop with no close tell: same abstain as before, and python3 is never started" {
  have_old; shf_mkrepo "$W"
  local tp
  tp="$(transcript 'Still reading the parser; two call sites to go.')"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  jq -e -s 'any(.[]; .reason == "no-close-tell")' "$SHF_OUT_DIR/o.idl" >/dev/null || { echo "fixture did not reach no-close-tell"; cat "$SHF_OUT_DIR/o.idl"; false; }
  shf_same o n
  echo "# no close tell: $(shf_total o) external calls before, $(shf_total n) after: $(shf_census n)" >&3
  [ "$(shf_calls o python3)" -eq 1 ]
  [ "$(shf_calls n python3)" -eq 0 ] || { echo "python3 ran: $(shf_census n)"; false; }
  [ "$(shf_calls n dirname)" -eq 0 ] || { echo "dirname ran: $(shf_census n)"; false; }
  [ "$(shf_total n)" -le 16 ] || { echo "too many: $(shf_total n): $(shf_census n)"; false; }
}

@test "a session WITH a route record still goes to the router, exactly as before" {
  have_old; shf_mkrepo "$W"
  local tp
  tp="$(transcript 'Still reading the parser; two call sites to go.')"
  mkdir -p "$CC_RESEARCH_HOME/route-state"
  printf '{"label":"other","program":"none"}\n' > "$CC_RESEARCH_HOME/route-state/sidA.json"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  shf_same o n
  [ "$(shf_calls n python3)" -eq 1 ] || { echo "python3 ran $(shf_calls n python3)x"; false; }
  # A sid the router's sanitizer would rewrite is never decided in the shell.
  blank; payload "$tp" 'sid with spaces' | stop old so
  blank; payload "$tp" 'sid with spaces' | stop new sn
  shf_same so sn
  [ "$(shf_calls sn python3)" -eq 1 ] || { echo "python3 ran $(shf_calls sn python3)x for an unsafe sid"; false; }
}

@test "a done claim over this session's own uncommitted write blocks with the same reason" {
  have_old; shf_mkrepo "$W"
  local tp
  echo dirt > "$W/mine.txt"; git -C "$W" add mine.txt
  tp="$(transcript 'All done — everything is complete and landed.' "$W/mine.txt")"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  grep -q '"decision":"block"' "$SHF_OUT_DIR/o.out" || { echo "the control did not block"; cat "$SHF_OUT_DIR/o.out" "$SHF_OUT_DIR/o.idl"; false; }
  shf_same o n
}

@test "a done claim on a clean landed repo, and one over an unlanded commit: same as before" {
  have_old; shf_mkrepo "$W"
  local tp
  tp="$(transcript '✅ Good to close: yes — nothing of mine is open; follow-on: none')"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  shf_same o n
  echo x > "$W/x.txt"; git -C "$W" add x.txt; git -C "$W" -c user.email=t@e.com -c user.name=t commit -qm "my change"
  tp="$(transcript 'Done. All landed and complete.' "$W/x.txt")"
  blank; payload "$tp" | stop old uo
  blank; payload "$tp" | stop new un
  shf_same uo un
}

@test "a team assignee's done claim gets the same answer as before (the ancestry memo carries the id)" {
  have_old; shf_mkrepo "$W"
  local tp
  export CC_WF_START_PID=4242 CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teams"
  printf '4242 1 claude --agent-id w@session-t --agent-name w --team-name session-t\n1 0 /sbin/launchd\n' > "$CC_WF_PSTABLE_FILE"
  echo dirt > "$W/mine.txt"; git -C "$W" add mine.txt
  tp="$(transcript 'All done — everything is complete and landed.' "$W/mine.txt")"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  shf_same o n
}

@test "odd Stop payloads are parsed exactly as before (the one-jq fast path declines them)" {
  have_old; shf_mkrepo "$W"
  local i=0 p tp
  tp="$(transcript 'All done.')"
  for p in '[]' 'not json' '{}' '{"session_id":7,"cwd":"/nonexistent"}' '{"session_id":false}' \
           '{"session_id":"a"}{"session_id":"b"}' '{"session_id":"s","cwd":{"x":1}}' \
           "$(jq -cn --arg c "$W" --arg t "$tp" '{session_id:"nl", cwd:($c + "\n"), transcript_path:$t}')" \
           "$(jq -cn --arg c "$W" --arg t "$tp" '{session_id:"", cwd:$c, transcript_path:$t}')"; do
    i=$((i + 1))
    blank; printf '%s' "$p" | stop old "po$i"
    blank; printf '%s' "$p" | stop new "pn$i"
    shf_same "po$i" "pn$i" || { echo "payload $i differs: $p"; false; }
  done
}

@test "a done claim that reaches the ledger starts at least 40 fewer processes than before" {
  have_old; shf_mkrepo "$W"
  local tp old new
  echo dirt > "$W/mine.txt"; git -C "$W" add mine.txt
  tp="$(transcript 'All done — everything is complete and landed.' "$W/mine.txt")"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  old="$(shf_total o)"; new="$(shf_total n)"
  echo "# done claim, ledger computed: $old external calls before, $new after" >&3
  echo "# after: $(shf_census n)" >&3
  [ "$(shf_calls n python3)" -eq 0 ] || { echo "python3 ran: $(shf_census n)"; false; }
  # The BUSY probe is its own `bash -c` child of the ledger (fed the fixture process table here,
  # so no ps or lsof shows either way): one bash fewer is the probe not being started.
  [ "$(shf_calls n bash)" -le $(( $(shf_calls o bash) - 1 )) ] || { echo "the BUSY probe still ran: bash $(shf_calls o bash) -> $(shf_calls n bash)"; false; }
  [ "$(shf_calls n head)" -le $(( $(shf_calls o head) - 8 )) ] || { echo "head: $(shf_calls o head) -> $(shf_calls n head)"; false; }
  [ "$new" -le $((old - 40)) ] || { echo "only $((old - new)) fewer ($old -> $new): $(shf_census n)"; false; }
}

@test "a landed close that misses the close contract: same block, and the ancestry is read once, not per guard" {
  have_old; shf_mkrepo "$W"
  local tp
  tp="$(transcript 'All done — everything is complete and landed.' "$W/f.txt")"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  shf_same o n
  # The ancestry walk reads the fixture table with `cat`, so one walk fewer is one cat fewer (the
  # other cats, stdin and the ledger's cache reads, are the same in both arms).
  echo "# cat calls (one per ancestry walk, plus fixed others): $(shf_calls o cat) before, $(shf_calls n cat) after" >&3
  [ "$(shf_calls n cat)" -le $(( $(shf_calls o cat) - 1 )) ] || { echo "the second guard walked again: cat $(shf_calls o cat) -> $(shf_calls n cat)"; false; }
}
