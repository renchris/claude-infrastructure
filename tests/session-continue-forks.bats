#!/usr/bin/env bats
# session-continue-forks.bats — the process budget of hooks/session-continue.sh at Stop, and proof
# that cutting it changed nothing the hook prints, logs or leaves in its state directory.
#
# The defect this pins (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md, Stop hooks): session-continue
# was cancelled at its 5 s timeout 9 times in 30 minutes at a load of 520-680. An idle Stop started
# jq four to six times to read three stdin fields, `grep | head -1 | cut` once per ledger field, and
# under it the ledger started dirname eleven times.
#
# Parity is against the REAL pre-change hook and ledger, rebuilt from git
# (stop-hook-forks-helpers.bash). The two arms run one after the other over the SAME paths, from the
# same blank state, so any path the hook prints is identical in both. Counts come from PATH stubs
# that log every external command and then exec it.
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
        KITTY_WINDOW_ID WRAP_LEDGER_BIN
  export CC_PANE_ID=shf-pane          # a pane id, so the mailbox ack and the wake floor both run
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  OLD="$BATS_TEST_TMPDIR/old"
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  export CC_TEARDOWN_DIR="$BATS_TEST_TMPDIR/teardown"
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CONTINUE_IDL="$BATS_TEST_TMPDIR/continue-idl.jsonl"
  export CONTINUE_LOG="$BATS_TEST_TMPDIR/continue.log"
  export WRAP_TRUNK="origin/main"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/no-programs.json"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-repo"
  # A process table with no team assignee in it: the ancestry walk reads this file instead of
  # running `ps` once per hop, so the counts do not depend on how deep the runner is nested.
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/pstable"
  printf '1 0 /sbin/launchd\n' > "$CC_WF_PSTABLE_FILE"
  : > "$CC_BACKLOG_FILE"
  W="$BATS_TEST_TMPDIR/w"
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/session-continue.sh scripts/wrap-ledger.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# blank — every directory the hook writes, emptied: each arm starts from the same state.
blank() {
  local d
  for d in "$HOME" "$CLAUDE_CONFIG_DIR" "$CC_MAILBOX_DIR" "$CC_TEARDOWN_DIR" "$CC_TELEMETRY_DIR" \
           "$CC_DECISIONS_DIR" "$CC_CUSTODY_DIR" "$CC_FIRED_DIR" "$BATS_TEST_TMPDIR/tmp"; do
    rm -rf "$d"; mkdir -p "$d"
  done
  rm -f "$CONTINUE_IDL" "$CONTINUE_LOG" "$CC_IDL"
}

transcript() { # <last user text> [<edited path>] → a transcript; echoes its path
  local tp="$BATS_TEST_TMPDIR/t.jsonl"
  jq -cn --arg t "$1" '{type:"user",message:{role:"user",content:$t}}' > "$tp"
  if [ -n "${2:-}" ]; then
    jq -cn --arg p "$2" '{type:"assistant",message:{content:[{type:"tool_use",name:"Edit",input:{file_path:$p}}]}}' >> "$tp"
  fi
  jq -cn '{type:"assistant",message:{content:[{type:"text",text:"Working on it."}]}}' >> "$tp"
  printf '%s' "$tp"
}
payload() { jq -cn --arg c "$W" --arg t "${1:-}" '{session_id:"sidA",cwd:$c,transcript_path:$t}'; }

# stop <old|new> <label> — one Stop through that arm's hook; stdin is the payload.
stop() {
  local root="$REPO"
  [ "$1" = old ] && root="$OLD"
  TMPDIR="$BATS_TEST_TMPDIR/tmp" shf_run "$2" "$root/hooks/session-continue.sh" || true
  # ONE deliberate text change since SHF_BASE (lead-keeps-working, design §3.4 (iii), ruling
  # d610f8473106): continue_reason's disarm list says "held on the user for everything that remains
  # (a held ⛔)" where it said "blocked on the user (⛔)". Rewrite exactly that clause in the OLD arm's
  # output so every other byte is still compared; any other drift stays red.
  if [ "$1" = old ]; then
    sed 's/blocked on the user (⛔)/held on the user for everything that remains (a held ⛔)/' \
      "$SHF_OUT_DIR/$2.out" > "$SHF_OUT_DIR/$2.out.n" && mv "$SHF_OUT_DIR/$2.out.n" "$SHF_OUT_DIR/$2.out"
  fi
  shf_keep "$2" "$CONTINUE_IDL" "$CLAUDE_CONFIG_DIR/state"
}
# armed <old|new> — arm the 🔧 loop for $W through that arm's own `set`.
armed() {
  local root="$REPO"
  [ "$1" = old ] && root="$OLD"
  ( cd "$W" && CLAUDE_CODE_SESSION_ID=sidA /bin/bash "$root/hooks/session-continue.sh" set "finish the wave" >/dev/null )
}

@test "an idle Stop on a clean landed repo: same output, IDL rows and state as before" {
  have_old; shf_mkrepo "$W"
  local tp
  tp="$(transcript 'fix the failing test')"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  [ -s "$SHF_OUT_DIR/o.idl" ] || { echo "the control logged nothing"; cat "$SHF_OUT_DIR/o.err"; false; }
  shf_same o n
}

@test "an armed Stop blocks with the same JSON, and a kill-switch turn clears it the same way" {
  have_old; shf_mkrepo "$W"
  local tp
  tp="$(transcript 'keep going')"
  blank; armed old; payload "$tp" | stop old o
  blank; armed new; payload "$tp" | stop new n
  grep -q '"decision":"block"' "$SHF_OUT_DIR/o.out" || { echo "the control did not block"; cat "$SHF_OUT_DIR/o.out" "$SHF_OUT_DIR/o.err"; false; }
  shf_same o n
  tp="$(transcript 'good, stop here')"
  blank; armed old; payload "$tp" | stop old ko
  blank; armed new; payload "$tp" | stop new kn
  jq -e -s 'any(.[]; .reason == "kill-switch")' "$SHF_OUT_DIR/ko.idl" >/dev/null || { echo "the control did not clear"; cat "$SHF_OUT_DIR/ko.idl"; false; }
  shf_same ko kn
}

@test "a Stop over this session's own uncommitted write, and one over an unlanded commit: same as before" {
  have_old; shf_mkrepo "$W"
  local tp
  echo dirt > "$W/mine.txt"; git -C "$W" add mine.txt
  tp="$(transcript 'make the change' "$W/mine.txt")"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  shf_same o n
  git -C "$W" -c user.email=t@e.com -c user.name=t commit -qm "my change"
  blank; payload "$tp" | stop old uo
  blank; payload "$tp" | stop new un
  shf_same uo un
}

@test "odd Stop payloads are parsed exactly as before (the one-jq fast path declines them)" {
  have_old; shf_mkrepo "$W"
  local i=0 p
  for p in '[]' 'not json' '{}' '{"session_id":7,"cwd":"/nonexistent"}' '{"cwd":false}' \
           '{"session_id":"a"}{"session_id":"b"}' '{"session_id":"s","cwd":{"x":1}}' \
           "$(jq -cn --arg c "$W" '{session_id:"nl", cwd:($c + "\n")}')" \
           "$(jq -cn --arg c "$W" '{session_id:"", cwd:$c, transcript_path:null}')"; do
    i=$((i + 1))
    blank; printf '%s' "$p" | ( cd "$W" && stop old "po$i" )
    blank; printf '%s' "$p" | ( cd "$W" && stop new "pn$i" )
    shf_same "po$i" "pn$i" || { echo "payload $i differs: $p"; false; }
  done
}

@test "an idle Stop starts jq once for stdin, no grep|head|cut per field, and fewer processes than before" {
  have_old; shf_mkrepo "$W"
  local tp old new
  tp="$(transcript 'fix the failing test')"
  blank; payload "$tp" | stop old o
  blank; payload "$tp" | stop new n
  old="$(shf_total o)"; new="$(shf_total n)"
  echo "# idle Stop, ledger computed: $old external calls before, $new after" >&3
  echo "# after: $(shf_census n)" >&3
  [ "$(shf_calls n head)" -le $(( $(shf_calls o head) - 2 )) ] || { echo "head: $(shf_calls o head) -> $(shf_calls n head)"; false; }
  [ "$(shf_calls n dirname)" -le $(( $(shf_calls o dirname) - 7 )) ] || { echo "dirname: $(shf_calls o dirname) -> $(shf_calls n dirname)"; false; }
  [ "$(shf_calls n jq)" -le $(( $(shf_calls o jq) - 3 )) ] || { echo "jq: $(shf_calls o jq) -> $(shf_calls n jq)"; false; }
  [ "$new" -le $((old - 12)) ] || { echo "only $((old - new)) fewer ($old -> $new): $(shf_census n)"; false; }
  # The same Stop again: the ledger is served from its memo, and the hook's own starts are all that is left.
  payload "$tp" | stop new n2
  echo "# idle Stop, ledger memo hit: $(shf_total n2) external calls: $(shf_census n2)" >&3
  [ "$(shf_total n2)" -le 35 ] || { echo "too many: $(shf_total n2): $(shf_census n2)"; false; }
}
