#!/usr/bin/env bats
# boundary-handoff-forks.bats — the process budget of hooks/boundary-handoff.sh, and proof that
# cutting it changed nothing the hook prints, logs or latches.
#
# The defect this pins (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md, Stop hooks): boundary-handoff
# was cancelled at its 5 s timeout 3 times in 30 minutes at a load of 520-680. Between 35% and 73%
# fill its free-win arm asks the ledger for one field, RUNG, and that ask ran the ledger's BUSY
# probe as well: a process-table scan plus lsof, bounded at 8 s, for fields this hook never reads.
# It also keyed a different memo entry from session-continue's ask, so the two hooks computed two
# ledgers per Stop where one would do.
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
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/tel"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BOUNDARY_LATCH_DIR="$BATS_TEST_TMPDIR/latch"
  export CC_CONTINUE_SENTINEL="$BATS_TEST_TMPDIR/no-such-sentinel"
  export CC_RECYCLE_RETRY_DIR="$BATS_TEST_TMPDIR/recycle-retry"
  export WRAP_TRUNK="origin/main"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-repo"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/no-programs.json"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mbox"
  # Fixture process tables: the hook's ancestry walk and the ledger's BUSY probe read these files
  # instead of running `ps`, so neither arm depends on the box or on how deep the runner is nested.
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/pstable"
  export CC_PROC_SCOPE_PS="$BATS_TEST_TMPDIR/pstable"
  printf '1 0 /sbin/launchd\n' > "$CC_WF_PSTABLE_FILE"
  : > "$CC_BACKLOG_FILE"
  W="$BATS_TEST_TMPDIR/w"
  TEL_TS="$(date +%s)"
  # conv_age_s is seconds since the transcript's last human turn, read off the wall clock.
  export SHF_IDL_DEL='.ts, .conv_age_s'
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/boundary-handoff.sh scripts/wrap-ledger.sh \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# blank <used_pct|none> — every directory the hook writes, emptied, and the telemetry row rewritten
# with one fixed timestamp: each arm starts from the same state and reads the same row.
blank() {
  local d
  for d in "$HOME" "$CC_TELEMETRY_DIR" "$CC_BOUNDARY_LATCH_DIR" "$CC_RECYCLE_RETRY_DIR" \
           "$CC_DECISIONS_DIR" "$CC_FIRED_DIR" "$CC_CUSTODY_DIR" "$CC_MAILBOX_DIR" "$BATS_TEST_TMPDIR/tmp"; do
    rm -rf "$d"; mkdir -p "$d"
  done
  rm -f "$CC_IDL"
  [ "$1" = none ] && return 0
  jq -nc --arg cwd "$W" --argjson used "$1" --argjson ts "$TEL_TS" \
    '{ts:$ts,session_id:"sidA",cwd:$cwd,config_dir:"/cfg",used_pct:$used,input_tokens:1}' \
    > "$CC_TELEMETRY_DIR/sidA.json"
}

transcript() { # a transcript whose one human turn is an hour old; echoes its path
  local tp="$BATS_TEST_TMPDIR/t.jsonl" past
  past="$(date -u -r $(( TEL_TS - 3600 )) +%Y-%m-%dT%H:%M:%S.000Z)"
  jq -nc --arg ts "$past" \
    '{type:"user",isMeta:null,userType:"external",message:{role:"user",content:"quick question"},timestamp:$ts}' > "$tp"
  printf '%s' "$tp"
}
payload() { jq -cn --arg t "${1:-}" '{session_id:"sidA",transcript_path:$t}'; }

# stop <old|new> <label> — one Stop through that arm's hook; stdin is the payload.
stop() {
  local root="$REPO"
  [ "$1" = old ] && root="$OLD"
  TMPDIR="$BATS_TEST_TMPDIR/tmp" shf_run "$2" "$root/hooks/boundary-handoff.sh" || true
  shf_keep "$2" "$CC_IDL" "$CC_BOUNDARY_LATCH_DIR"
}
reason() { jq -r -s '.[-1].reason // ""' "$SHF_OUT_DIR/$1.idl"; }

@test "no telemetry, and a fill below the free-win floor: same abstains as before" {
  have_old; shf_mkrepo "$W"
  local tp
  tp="$(transcript)"
  blank none; payload "$tp" | stop old o
  blank none; payload "$tp" | stop new n
  [ "$(reason o)" = no-telemetry ]
  shf_same o n
  echo "# no telemetry: $(shf_total o) external calls before, $(shf_total n) after: $(shf_census n)" >&3
  [ "$(shf_calls n dirname)" -eq 0 ] || { echo "dirname ran: $(shf_census n)"; false; }
  [ "$(shf_calls n jq)" -le 2 ] || { echo "jq ran $(shf_calls n jq)x: $(shf_census n)"; false; }
  [ "$(shf_total n)" -le 8 ] || { echo "too many: $(shf_total n): $(shf_census n)"; false; }
  blank 20; payload "$tp" | stop old lo
  blank 20; payload "$tp" | stop new ln
  [ "$(reason lo)" = 'below-threshold:20<73;freewin=below-floor' ] || { reason lo; false; }
  shf_same lo ln
}

@test "the free-win arm on a clean landed repo fires the same advisory, without the BUSY probe" {
  have_old; shf_mkrepo "$W"
  local tp old new
  tp="$(transcript)"
  blank 50; payload "$tp" | stop old o
  blank 50; payload "$tp" | stop new n
  grep -q '"decision":"block"' "$SHF_OUT_DIR/o.out" || { echo "the control did not fire"; cat "$SHF_OUT_DIR/o.out" "$SHF_OUT_DIR/o.idl"; false; }
  shf_same o n
  old="$(shf_total o)"; new="$(shf_total n)"
  echo "# free-win Stop, ledger computed: $old external calls before, $new after" >&3
  echo "# after: $(shf_census n)" >&3
  # The probe is its own `bash -c` child of the ledger (fed the fixture process table here, so no
  # ps or lsof shows either way): one bash fewer is the probe not being started.
  [ "$(shf_calls n bash)" -le $(( $(shf_calls o bash) - 1 )) ] || { echo "the BUSY probe still ran: bash $(shf_calls o bash) -> $(shf_calls n bash)"; false; }
  [ "$new" -le $((old - 25)) ] || { echo "only $((old - new)) fewer ($old -> $new): $(shf_census n)"; false; }
}

@test "the free-win arm over an unlanded commit declines with the same rung on the record" {
  have_old; shf_mkrepo "$W" unlanded
  local tp
  tp="$(transcript)"
  blank 50; payload "$tp" | stop old o
  blank 50; payload "$tp" | stop new n
  [ "$(reason o)" = 'below-threshold:50<73;freewin=📦' ] || { reason o; false; }
  shf_same o n
}

@test "a fill past the static threshold fires the same block as before" {
  have_old; shf_mkrepo "$W"
  local tp
  tp="$(transcript)"
  blank 80; payload "$tp" | stop old o
  blank 80; payload "$tp" | stop new n
  grep -q '"decision":"block"' "$SHF_OUT_DIR/o.out" || { echo "the control did not fire"; cat "$SHF_OUT_DIR/o.out" "$SHF_OUT_DIR/o.idl"; false; }
  shf_same o n
}

@test "odd Stop payloads are parsed exactly as before (the one-jq fast path declines them)" {
  have_old; shf_mkrepo "$W"
  local i=0 p
  for p in '[]' 'not json' '{}' '{"session_id":7}' '{"session_id":false}' \
           '{"session_id":"sidA"}{"session_id":"b"}' '{"session_id":"sidA","transcript_path":{"x":1}}' \
           '{"session_id":"sidA\n"}' '{"session_id":"sidA","transcript_path":null}'; do
    i=$((i + 1))
    blank 20; printf '%s' "$p" | stop old "po$i"
    blank 20; printf '%s' "$p" | stop new "pn$i"
    shf_same "po$i" "pn$i" || { echo "payload $i differs: $p"; false; }
  done
}

@test "session-continue's ledger ask and the free-win ask are one memo entry: the second is a hit" {
  shf_mkrepo "$W"
  local tp
  tp="$(transcript)"
  blank 50
  # session-continue's ask, verbatim: WRAP_BUSY=off, the transcript as the event key, from the cwd.
  ( cd "$W" && TMPDIR="$BATS_TEST_TMPDIR/tmp" WRAP_TRANSCRIPT="$tp" WRAP_BUSY=off \
      /bin/bash "$REPO/scripts/wrap-ledger.sh" --machine >/dev/null )
  payload "$tp" | stop new n
  echo "# free-win Stop after session-continue's ledger: $(shf_total n) external calls: $(shf_census n)" >&3
  grep -q '"decision":"block"' "$SHF_OUT_DIR/n.out"
  [ "$(shf_calls n git)" -le 4 ] || { echo "the ledger was recomputed: git ran $(shf_calls n git)x: $(shf_census n)"; false; }
}
