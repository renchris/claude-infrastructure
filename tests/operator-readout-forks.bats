#!/usr/bin/env bats
# operator-readout-forks.bats — the process budget of hooks/operator-readout.sh, and proof that
# cutting it changed nothing the hook prints, logs or latches.
#
# The defect this pins (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md, Stop hooks): operator-readout
# was cancelled at its 10 s timeout 13 times in 30 minutes at a load of 520-680. A full render made
# about 500 process starts, measured 10-30 s at that load: 172 of them were one `basename` per
# resume-debt meta file inside `cc-resume-debt list`, and about 30 more were `grep | head | cut`
# once per ledger field.
#
# Parity is against the REAL pre-change hook, rebuilt from git (stop-hook-forks-helpers.bash): the
# two are run over one fixture and their stdout, IDL rows and latch files compared byte for byte.
# Counts come from PATH stubs that log every external command and then exec it.
#
# Assertions are simple commands only (bash exempts `[[ ]]` from errexit in a bats body).

load stop-hook-forks-helpers

setup_file() {
  STUB="$BATS_FILE_TMPDIR/stub"
  shf_build_stubs "$STUB"
  export STUB
}

setup() {
  export CC_BACKLOG_PROJECT_WARN=off CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID CLAUDE_CONFIG_DIR ITERM_SESSION_ID \
        KITTY_WINDOW_ID CC_PANE_ID NO_COLOR
  # Parity with the pre-change hook is a property of the layout that hook drew: collapse. The
  # footer layout (default since lr-wake Wave H, 2026-10-19) changes the render on purpose.
  export CC_OPREADOUT_CLASSBUDGET=collapse
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  NEW="$REPO"
  OLD="$BATS_TEST_TMPDIR/old"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export SHF_OUT_DIR="$BATS_TEST_TMPDIR/out"; mkdir -p "$SHF_OUT_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_ACTIVATION_DIR="$BATS_TEST_TMPDIR/activation"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  export WRAP_LEDGER_BIN="$REPO/scripts/wrap-ledger.sh"
  export WRAP_TRUNK="origin/main"
  export CC_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/no-such-checkout"
  export CC_OPREADOUT_NOW=1000000 CC_OPREADOUT_TTL_S=900
  export CC_DO_BIN=cc-do
  export CC_HANDOFF_ALARM_DIR="$BATS_TEST_TMPDIR/handoff-alarms"
  export CC_ANNOUNCE_ALARM_DIR="$BATS_TEST_TMPDIR/announce-alarms"
  export CC_COMPLETION_RECORDS_DIR="$BATS_TEST_TMPDIR/completion-push"
  export CC_PAGES_DIR="$BATS_TEST_TMPDIR/pages"
  export CC_MAILBOX_DIR="$BATS_TEST_TMPDIR/mailbox"
  export CC_SWEEP_SEEN_DIR="$BATS_TEST_TMPDIR/sweep-seen"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr" LR_RECON_ROOT="$BATS_TEST_TMPDIR/lr/recon"
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/no-research-registry.json"
  export CC_RESUME_DEBT_DIR="$BATS_TEST_TMPDIR/resume-debt"
  # The hook bounds `cc-resume-debt list` at 3 s and prints no stranded line when it overruns, so
  # with the real tool the pre-change arm (one basename per meta file) drops the line on a loaded
  # box and the comparison measures the box. The hook tests therefore read a fixture through a
  # stub, as tests/operator-readout-stranded.bats does; the real tool is compared in the last test.
  export CC_RESUME_DEBT_BIN="$BATS_TEST_TMPDIR/cc-resume-debt-stub"
  printf '#!/bin/bash\n[ "$*" = "list --escalated --json" ] || exit 2\ncat %q\n' \
    "$BATS_TEST_TMPDIR/escalated.json" > "$CC_RESUME_DEBT_BIN"
  chmod +x "$CC_RESUME_DEBT_BIN"
  jq -cn '[{sid:"11111111-aaaa-4000-8000-000000000001", cwd:"/x/reso", account:"next3", state:"escalated", backlog_id:"bl0000000001"},
           {sid:"22222222-bbbb-4000-8000-000000000002", cwd:"/x/infra", account:"next", state:"escalated"}]' \
    > "$BATS_TEST_TMPDIR/escalated.json"
  # A process table with no team assignee in it: the ancestry walk reads this file instead of
  # running `ps` once per hop, so the counts below do not depend on how deep the runner is nested.
  export CC_WF_PSTABLE_FILE="$BATS_TEST_TMPDIR/pstable"
  printf '1 0 /sbin/launchd\n' > "$CC_WF_PSTABLE_FILE"
  mkdir -p "$CC_ACTIVATION_DIR" "$CC_DECISIONS_DIR" "$CC_HANDOFF_ALARM_DIR" \
           "$CC_ANNOUNCE_ALARM_DIR" "$CC_COMPLETION_RECORDS_DIR" "$CC_PAGES_DIR" \
           "$CC_MAILBOX_DIR/dead-letter" "$CC_SWEEP_SEEN_DIR" "$CC_RESUME_DEBT_DIR/meta"
  : > "$CC_BACKLOG_FILE"
}

have_old() {
  shf_old_tree "$OLD" "$REPO" hooks/operator-readout.sh bin/cc-resume-debt \
    || skip "the pre-change commit $SHF_BASE is not in this clone"
}

# A committed-but-unlanded repo: the 📦 rung, so the block renders its governing line.
mkrepo_unlanded() {
  local o="$BATS_TEST_TMPDIR/o.git"
  W="$BATS_TEST_TMPDIR/w"
  git init -q --bare "$o"; git clone -q "$o" "$W" 2>/dev/null
  ( cd "$W" || exit 1; git config user.email t@e.com; git config user.name t; git checkout -q -b main
    echo base > base.txt; git add base.txt; git commit -q -m base; git push -q -u origin main
    echo x > x.txt; git add x.txt; git commit -q -m "unlanded work" ) >/dev/null 2>&1
}

# A populated store: three activation scripts (one CONFIRM-gated, one settled), two blocked backlog
# rows, one open class-C decision, and <n> resume debts of which two are escalated.
populate() {
  local n="${1:-40}" i id st
  printf '#!/bin/bash\necho hi\n' > "$CC_ACTIVATION_DIR/10-plain-activate.sh"
  printf '#!/bin/bash\n[ "$CONFIRM" = 1 ] || exit 2\n' > "$CC_ACTIVATION_DIR/20-gated-activate.sh"
  printf '#!/bin/bash\necho done\n' > "$CC_ACTIVATION_DIR/30-settled-activate.sh"
  : > "$CC_ACTIVATION_DIR/30-settled-activate.sh.done"
  for i in 1 2; do
    id="$("$REPO/bin/cc-backlog" add --title "Blocked item $i" --project infra 2>/dev/null)"
    "$REPO/bin/cc-backlog" block "$id" --needs "operator step $i" >/dev/null
  done
  "$REPO/bin/cc-decide" open --class C --conviction 40 --receipt "probe => result" \
    --option "a::outcome a" --option "b::outcome b" --what "Choose the reboot posture." >/dev/null
  for i in $(seq 1 "$n"); do
    st=proven; [ "$i" -le 2 ] && st=escalated
    jq -cn --arg s "$(printf '%08d-aaaa-4000-8000-000000000000' "$i")" --arg st "$st" \
      '{sid:$s, state:$st, attempts:1, backlog_id:"", marker:("resume:" + $s), cwd:"/x/reso", account:"next"}' \
      > "$CC_RESUME_DEBT_DIR/meta/$(printf '%08d-aaaa-4000-8000-000000000000' "$i").json"
  done
}

transcript() { # a two-record interactive transcript; echoes its path
  local tp="$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s\n' \
    '{"type":"user","entrypoint":"cli","message":{"content":"fix it"},"timestamp":"2026-10-12T00:00:00.000Z"}' \
    '{"type":"assistant","entrypoint":"cli","message":{"content":[{"type":"text","text":"Done."}]}}' > "$tp"
  printf '%s' "$tp"
}

# arm <old|new> <label> — one Stop through that arm's hook, each arm with its own state, cache and
# TMPDIR, so neither can be served the other's memo. Stdin is the Stop payload.
arm() {
  local which="$1" label="$2" root="$NEW"
  [ "$which" = old ] && root="$OLD"
  mkdir -p "$BATS_TEST_TMPDIR/tmp-$which"
  CC_OPREADOUT_STATE_DIR="$BATS_TEST_TMPDIR/state-$which" \
  CC_ORB_BLG_CACHE_DIR="$BATS_TEST_TMPDIR/blg-$which" \
  CC_IDL="$BATS_TEST_TMPDIR/idl-$which.jsonl" \
  TMPDIR="$BATS_TEST_TMPDIR/tmp-$which" \
    shf_run "$label" "$root/hooks/operator-readout.sh"
}
payload() { jq -cn --arg c "$1" --arg t "${2:-}" '{session_id:"S-forks",cwd:$c,transcript_path:$t}'; }

@test "a full render is byte-identical to the pre-change hook: stdout, IDL row and latch" {
  have_old; mkrepo_unlanded; populate 3
  local tp
  tp="$(transcript)"
  payload "$W" "$tp" | arm old o1
  payload "$W" "$tp" | arm new n1
  [ -s "$SHF_OUT_DIR/o1.out" ] || { echo "the control rendered nothing"; cat "$SHF_OUT_DIR/o1.err"; false; }
  grep -q 'stranded session' "$SHF_OUT_DIR/o1.out" || { echo "fixture did not reach the stranded line"; false; }
  cmp "$SHF_OUT_DIR/o1.out" "$SHF_OUT_DIR/n1.out"
  [ "$(shf_idl "$BATS_TEST_TMPDIR/idl-old.jsonl")" = "$(shf_idl "$BATS_TEST_TMPDIR/idl-new.jsonl")" ]
  cmp "$BATS_TEST_TMPDIR"/state-old/*.last "$BATS_TEST_TMPDIR"/state-new/*.last
  # The second Stop inside the TTL takes the cheap stamp gate in both, and says the same.
  payload "$W" "$tp" | arm old o2
  payload "$W" "$tp" | arm new n2
  cmp "$SHF_OUT_DIR/o2.out" "$SHF_OUT_DIR/n2.out"
  [ "$(shf_idl "$BATS_TEST_TMPDIR/idl-old.jsonl")" = "$(shf_idl "$BATS_TEST_TMPDIR/idl-new.jsonl")" ]
  jq -e -s '.[-1].reason | startswith("stamp-unchanged-ttl")' "$BATS_TEST_TMPDIR/idl-new.jsonl" >/dev/null
}

@test "the --render pull surface is byte-identical to the pre-change hook" {
  have_old; mkrepo_unlanded; populate 3
  shf_run ro "$OLD/hooks/operator-readout.sh" --render --cwd "$W" --sid S-forks < /dev/null
  shf_run rn "$NEW/hooks/operator-readout.sh" --render --cwd "$W" --sid S-forks < /dev/null
  [ -s "$SHF_OUT_DIR/ro.out" ]
  cmp "$SHF_OUT_DIR/ro.out" "$SHF_OUT_DIR/rn.out"
}

@test "odd Stop payloads are parsed exactly as before (the one-jq fast path declines them)" {
  have_old; mkrepo_unlanded; populate 3
  local i=0 p
  for p in '[]' 'not json' '{}' '{"session_id":7,"cwd":"/nonexistent"}' '{"session_id":false}' \
           '{"session_id":"a"}{"session_id":"b"}' '{"session_id":"s","cwd":{"x":1}}' \
           "$(jq -cn --arg c "$W" '{session_id:"nl", cwd:($c + "\n")}')" \
           "$(jq -cn --arg c "$W" '{session_id:"", cwd:$c, transcript_path:null}')"; do
    i=$((i + 1))
    printf '%s' "$p" | arm old "po$i"
    printf '%s' "$p" | arm new "pn$i"
    cmp "$SHF_OUT_DIR/po$i.out" "$SHF_OUT_DIR/pn$i.out" || { echo "payload $i differs: $p"; false; }
  done
  [ "$(shf_idl "$BATS_TEST_TMPDIR/idl-old.jsonl")" = "$(shf_idl "$BATS_TEST_TMPDIR/idl-new.jsonl")" ] \
    || { diff <(shf_idl "$BATS_TEST_TMPDIR/idl-old.jsonl") <(shf_idl "$BATS_TEST_TMPDIR/idl-new.jsonl"); false; }
  [ "$(shf_idl "$BATS_TEST_TMPDIR/idl-new.jsonl" | grep -c .)" -eq "$i" ]
}

@test "a full render starts no basename, and at least 35 fewer processes than before" {
  have_old; mkrepo_unlanded; populate 3
  local tp old new
  tp="$(transcript)"
  payload "$W" "$tp" | arm old o
  payload "$W" "$tp" | arm new n
  old="$(shf_total o)"; new="$(shf_total n)"
  echo "# full render: $old external calls before, $new after" >&3
  echo "# after: $(shf_census n)" >&3
  [ "$(shf_calls n basename)" -eq 0 ] || { echo "basename ran: $(shf_census n)"; false; }
  # Three starts per ledger field (`grep | head -1 | cut`) across ~12 fields, the basenames, the
  # second dirname, two of three stdin parses and the `cut` after each digest are gone.
  [ "$new" -le $((old - 35)) ] || { echo "only $((old - new)) fewer ($old -> $new): $(shf_census n)"; false; }
  [ "$new" -le 215 ] || { echo "too many: $new: $(shf_census n)"; false; }
}

@test "a Stop inside the TTL (stamp unchanged) stays within 30 external calls" {
  mkrepo_unlanded; populate 3
  local tp
  tp="$(transcript)"
  payload "$W" "$tp" | arm new warm1
  payload "$W" "$tp" | arm new warm2
  echo "# stamp-unchanged Stop: $(shf_total warm2) external calls: $(shf_census warm2)" >&3
  [ ! -s "$SHF_OUT_DIR/warm2.out" ]
  # jq: the one stdin parse, the verdict read and the IDL row. cut: the continue-sentinel lib's one.
  [ "$(shf_calls warm2 jq)" -le 3 ] || { echo "jq ran $(shf_calls warm2 jq)x: $(shf_census warm2)"; false; }
  [ "$(shf_calls warm2 dirname)" -eq 0 ] || { echo "dirname ran: $(shf_census warm2)"; false; }
  [ "$(shf_calls warm2 cut)" -le 1 ] || { echo "cut ran $(shf_calls warm2 cut)x: $(shf_census warm2)"; false; }
  [ "$(shf_calls warm2 wc)" -le 1 ] || { echo "wc ran $(shf_calls warm2 wc)x: $(shf_census warm2)"; false; }
  [ "$(shf_total warm2)" -le 30 ] || { echo "too many: $(shf_total warm2): $(shf_census warm2)"; false; }
}

@test "cc-resume-debt list: same bytes as before, and no process per meta file" {
  have_old; populate 40
  shf_run lo "$OLD/bin/cc-resume-debt" list --json < /dev/null
  shf_run ln "$NEW/bin/cc-resume-debt" list --json < /dev/null
  [ "$(jq length "$SHF_OUT_DIR/ln.out")" -eq 40 ]
  cmp "$SHF_OUT_DIR/lo.out" "$SHF_OUT_DIR/ln.out"
  shf_run eo "$OLD/bin/cc-resume-debt" list --escalated < /dev/null
  shf_run en "$NEW/bin/cc-resume-debt" list --escalated < /dev/null
  [ "$(grep -c . "$SHF_OUT_DIR/en.out")" -eq 2 ]
  cmp "$SHF_OUT_DIR/eo.out" "$SHF_OUT_DIR/en.out"
  echo "# cc-resume-debt list, 40 metas: $(shf_total lo) external calls before, $(shf_total ln) after" >&3
  [ "$(shf_calls lo basename)" -eq 40 ]
  [ "$(shf_calls ln basename)" -eq 0 ]
  [ "$(shf_total ln)" -le 8 ] || { echo "too many: $(shf_census ln)"; false; }
}
