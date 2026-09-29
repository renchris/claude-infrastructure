#!/usr/bin/env bats
# RECYCLE CUSTODY (W2b, lr-reconciler) — the probe half, cases 1-4; the recycle half appends 5-13.
#
#   1  --voluntary --account-evidence F is the ONLY way a healthy pane passes the limit gate, and a
#      caller passing neither flag sees today's refusal byte-for-byte.
#   1b the probe's teammate test is lr-predicate's parsed is-teammate-head, not a substring grep.
#   2  a background job the session still runs HOLDs the probe (hf_bg_work_gate / hf_bg_work_kind),
#      and the idle inbox watcher does not.
#   3  live_subagents_of counts a Workflow's in-flight agents (subagents/workflows/<run>/…).
#   4  emit_recycle_event rows carry the attempt + watcher nonce.
#
# WHY CASE 2 IS DRIVEN THROUGH THE EXTRACTED FUNCTIONS, NOT THE PROBE VERB: the bg-work gate sits
# after `pane_state: cc`, which needs a real tty holding a real claude process — nothing a hermetic
# fixture can supply. The gate is one call in the probe; its whole decision lives in the function.
#
# Every case is RED on its feature's revert (one mutant per case, run by hand before landing):
#   1 drop the `--voluntary` bypass branch · 1b drop the parsed true/false arms (substring fallback) ·
#   2 make hf_bg_work_kind print `none` ·
#   3 drop the workflows glob · 4 drop the three nonce keys from the jq object.
# Run a mutant from scripts/ (the script resolves its libraries beside itself):
#   HF_OVERRIDE="$PWD/scripts/.hf-mutant.sh" bats tests/handoff-fire-recycle-custody.bats

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="${HF_OVERRIDE:-$REPO/scripts/handoff-fire.sh}"

  HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  HOME="$(cd "$HOME" && pwd -P)"; export HOME
  mkdir -p "$HOME/.claude/logs"
  # HERMETICITY (land ratchet): no live machine load, and the seams that do NOT resolve under $HOME
  # point at absent paths inside the test dir.
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  # Nothing here lands, but the converge kick must never inherit the operator's checkout.
  export SHIP_LAND_CONVERGE=off
  export DEPLOY_REPO="$BATS_TEST_TMPDIR/deploy-repo"
  # NO LIVE TERMINAL: an explicit CC_TERM stops the remote-pane resolver probing kitty sockets, and
  # the tty-query countdown fails every pane→tty read, so the probe ends at REFUSED:pane:unknown
  # without ever asking the operator's terminal anything.
  export CC_TERM=iterm2
  echo 99 > "$BATS_TEST_TMPDIR/tty-fail"
  export HANDOFF_TTY_FAIL_FILE="$BATS_TEST_TMPDIR/tty-fail"
  export HANDOFF_TTY_RETRIES=1 HANDOFF_TTY_RETRY_SLEEP_S=0
  unset WATCHER_PID HF_RECYCLE_ATTEMPT HF_WATCHER_IS_JOB HF_PS_SNAPSHOT 2>/dev/null || true

  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  SID="a1b2c3d4-0000-4000-8000-000000000002"
  PANE=901
  printf '{"session_id":"%s","pane":"%s","account":"acctA"}\n' "$SID" "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"
  export CC_PROJECTS_DIRS="$BATS_TEST_TMPDIR/cfg/projects"
  mkdir -p "$CC_PROJECTS_DIRS/-some-repo"
  TX="$CC_PROJECTS_DIRS/-some-repo/$SID.jsonl"
  EV="$BATS_TEST_TMPDIR/evidence"; mkdir -p "$EV"
}

# A HEALTHY transcript: the last assistant record is an ordinary end_turn, not an API error.
seed_healthy_transcript() {
  printf '%s\n' \
    '{"type":"user","timestamp":"2026-09-20T00:00:00.000Z","message":{"role":"user","content":"go"}}' \
    '{"type":"assistant","timestamp":"2026-09-20T00:00:01.000Z","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"done"}]}}' \
    > "$TX"
}

# fact <name> <json> — one account fact file in the evidence dir.
fact() { printf '%s\n' "$2" > "$EV/$1"; }

probe() { run bash "$HF" --probe-recycle-preconditions --source-pane "$PANE" --source-session "$SID" "$@"; }

# ── 1 · THE EVIDENCE BYPASS ────────────────────────────────────────────────────────────────────

@test "1 --voluntary + a valid account fact passes a HEALTHY pane; weak or absent evidence still refuses" {
  seed_healthy_transcript
  local later=$(( $(date +%s) + 7200 )) soon=$(( $(date +%s) + 600 ))

  fact acctA.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$later}"
  probe --voluntary --account-evidence "$EV/acctA.5h.json"
  [[ "$output" == *"limit: bypassed — account evidence acctA.5h resets_at=$later (voluntary)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"teammate: no"* ]] || { echo "the probe stopped at the limit gate: $output"; false; }

  # An ISO-8601 reset time is read too, and the scope may come from the file name alone.
  fact acctA.7d.json "{\"status\":\"rejected\",\"resets_at\":\"$(date -u -r "$later" +%Y-%m-%dT%H:%M:%SZ)\"}"
  probe --voluntary --account-evidence "$EV/acctA.7d.json"
  [[ "$output" == *"limit: bypassed — account evidence acctA.7d "* ]] || { echo "$output"; false; }

  probe --voluntary
  [ "$status" -eq 5 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict: REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"evidence: missing"* ]] || { echo "$output"; false; }

  fact acctA.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$soon}"
  probe --voluntary --account-evidence "$EV/acctA.5h.json"
  [[ "$output" == *"verdict: REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"evidence: expiring"* ]] || { echo "$output"; false; }

  fact acctA.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$later,\"contradicted\":true}"
  probe --voluntary --account-evidence "$EV/acctA.5h.json"
  [[ "$output" == *"verdict: REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"evidence: contradicted"* ]] || { echo "$output"; false; }

  # The fact must be about the account this pane is on.
  fact acctB.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$later}"
  probe --voluntary --account-evidence "$EV/acctB.5h.json"
  [[ "$output" == *"evidence: account-mismatch"* ]] || { echo "$output"; false; }

  # No new flags: today's refusal, byte-for-byte, and no evidence line.
  probe
  [ "$status" -eq 5 ] || { echo "$output"; false; }
  local want got
  want="limit: NO — the last assistant record is not an api error ($TX)
limit: a healthy pane is moved by asking it to move itself — cc-lr switch --pane $PANE --target <acct>"
  got="$(printf '%s\n' "$output" | grep '^limit:')"
  [ "$got" = "$want" ] || { echo "want:"; echo "$want"; echo "got:"; echo "$got"; false; }
  [[ "$output" != *"evidence:"* ]] || { echo "$output"; false; }

  # Evidence without --voluntary is a usage error, not a silently ignored flag.
  probe --account-evidence "$EV/acctA.5h.json"
  [ "$status" -eq 2 ] || { echo "status=$status $output"; false; }
}

@test "1b the teammate test is PARSED: a real agentName refuses, a null one does not" {
  local lim='{"type":"assistant","timestamp":"2026-09-20T00:00:01.000Z","isApiErrorMessage":true,"message":{"role":"assistant","model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit · resets 4am (America/Chicago)"}]}}'
  printf '%s\n' '{"type":"summary"}' '{"type":"user","agentName":"mate-1","message":{"role":"user","content":"hi"}}' "$lim" > "$TX"
  probe
  [[ "$output" == *"verdict: REFUSED:teammate"* ]] || { echo "$output"; false; }
  # The substring grep this replaced answered YES here; presence of the key is not a name.
  printf '%s\n' '{"type":"summary"}' '{"type":"user","agentName":null,"message":{"role":"user","content":"hi"}}' "$lim" > "$TX"
  probe
  [[ "$output" == *"teammate: no"* ]] || { echo "$output"; false; }
}

# ── 2 · BACKGROUND WORK ────────────────────────────────────────────────────────────────────────

load_bg_funcs() {
  FUNCS="$BATS_TEST_TMPDIR/bg-funcs.sh"
  {
    sed -n '/^hf_transcript_at_rest() {/,/^}/p' "$HF"
    sed -n '/^hf_bg_work_kind() {/,/^}/p'       "$HF"
    sed -n '/^hf_bg_work_gate() {/,/^}/p'       "$HF"
  } > "$FUNCS"
  bash -n "$FUNCS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$FUNCS"
}

# snap <file> <line>… — a ps snapshot in the probe's own `pid ppid lstart(5) args` shape.
snap() { local f="$1"; shift; printf '%s\n' "$@" > "$f"; }
L="Tue Sep 29 10:00:00 2026"

@test "2 a ship-land under a Bash-tool job HOLDS; the idle inbox watcher does not" {
  load_bg_funcs
  local S="$BATS_TEST_TMPDIR/ps.txt" rc
  snap "$S" \
    "5000 4000 $L claude --resume x" \
    "5100 5000 $L /bin/zsh -c source \$HOME/.claude/shell-snapshots/snapshot-zsh-x.sh && eval '/ship now'" \
    "5101 5100 $L bash scripts/ship-wrapper" \
    "5102 5101 $L bash scripts/ship-land.sh --lock"
  export HF_PS_SNAPSHOT="$S"
  run hf_bg_work_kind 5000
  [ "$output" = "work shipland=yes pids=5100" ] || { echo "$output"; false; }
  rc=0; hf_bg_work_gate 5000 1 "" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
  [ "$rc" = 3 ] || { cat "$BATS_TEST_TMPDIR/gate.out"; echo "rc=$rc hold=$HF_BG_HOLD"; false; }
  [ "$HF_BG_HOLD" = "HELD:bg-work:ship-land" ] || { cat "$BATS_TEST_TMPDIR/gate.out"; echo "rc=$rc hold=$HF_BG_HOLD"; false; }
  grep -qx 'bg_work: work shipland=yes pids=5100' "$BATS_TEST_TMPDIR/gate.out"

  snap "$S" \
    "5000 4000 $L claude --resume x" \
    "5200 5000 $L /bin/zsh -c source \$HOME/.claude/shell-snapshots/snapshot-zsh-x.sh && eval '\$HOME/.claude/bin/cc-await-ping --timeout 3300'" \
    "5201 5200 $L /bin/bash \$HOME/.claude/bin/cc-await-ping --timeout 3300" \
    "5202 5200 $L tail -n 5"
  rc=0; hf_bg_work_gate 5000 1 "" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
  [ "$rc" = 0 ] || { cat "$BATS_TEST_TMPDIR/gate.out"; echo "rc=$rc"; false; }
  [ -z "$HF_BG_HOLD" ] || { cat "$BATS_TEST_TMPDIR/gate.out"; echo "rc=$rc"; false; }
  grep -qx 'bg_work: watcher shipland=no pids=5200' "$BATS_TEST_TMPDIR/gate.out"
  # …unless the kill switch counts watchers as work.
  HF_WATCHER_IS_JOB=1 run hf_bg_work_kind 5000
  [ "$output" = "work shipland=no pids=5200" ] || { echo "$output"; false; }

  # A voluntary (non-limited) pane mid-turn is HELD before any census: its own Bash call is a job.
  printf '%s\n' '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"}}' > "$BATS_TEST_TMPDIR/tx.jsonl"
  rc=0; hf_bg_work_gate 5000 0 "$BATS_TEST_TMPDIR/tx.jsonl" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
  [ "$rc" = 3 ] || { cat "$BATS_TEST_TMPDIR/gate.out"; false; }
  [ "$HF_BG_HOLD" = "HELD:mid-turn" ] || { cat "$BATS_TEST_TMPDIR/gate.out"; false; }
  grep -qx 'bg_work: unknown (turn in flight)' "$BATS_TEST_TMPDIR/gate.out"

  # No registry pid: unknown, and the probe proceeds.
  rc=0; hf_bg_work_gate "" 1 "" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
  [ "$rc" = 0 ] && grep -qx 'bg_work: unknown (no registry pid)' "$BATS_TEST_TMPDIR/gate.out"
}

# ── 3 · WORKFLOW AGENTS ────────────────────────────────────────────────────────────────────────

# wfagent <run> <id> <live|done> — one Workflow agent, in the same on-disk shape as an Agent-tool one.
wfagent() {
  local d="$CC_PROJECTS_DIRS/-some-repo/$SID/subagents/workflows/$1"
  mkdir -p "$d"
  printf '{"agentType":"workflow-lean","description":"slot %s","toolUseId":"toolu_%s"}\n' "$2" "$2" > "$d/agent-$2.meta.json"
  {
    printf '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"}}\n'
    if [ "$3" = "done" ]; then printf '{"type":"assistant","message":{"role":"assistant","stop_reason":"end_turn"}}\n'
    else printf '{"type":"assistant","message":{"role":"assistant","stop_reason":"tool_use"}}\n'; fi
  } > "$d/agent-$2.jsonl"
}

@test "3 a Workflow's in-flight agent is counted; a finished one is not" {
  wfagent wf_x a1 live
  wfagent wf_x a2 "done"
  run bash "$HF" --probe-live-subagents --source-session "$SID"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "live_subagents: 1" ] || { echo "$output"; false; }
}

# ── 4 · THE ROW NONCE ──────────────────────────────────────────────────────────────────────────

@test "4 emit_recycle_event rows carry attempt, watcher_pid and watcher_lstart" {
  command -v jq >/dev/null 2>&1 || skip "row shape needs jq"
  FUNCS="$BATS_TEST_TMPDIR/ev-funcs.sh"
  {
    grep '^_iso_now() {' "$HF" || true
    sed -n '/^_under_test() {/,/^}/p'        "$HF"
    sed -n '/^emit_recycle_event() {/,/^}/p' "$HF"
  } > "$FUNCS"
  bash -n "$FUNCS"
  # shellcheck disable=SC1090
  . "$FUNCS"
  local log="$HOME/.claude/logs/handoffs.jsonl"
  # A live pid (this shell) so the lstart read has something to find.
  HF_RECYCLE_ATTEMPT=2 WATCHER_PID=$$ emit_recycle_event recycle-engaged 1 "pane-R" "recycled"
  emit_recycle_event recycle-dead 0 "pane-R" "no watcher named"
  run jq -c '[.attempt, .watcher_pid, (.watcher_lstart != null)]' "$log"
  [ "${lines[0]}" = "[2,$$,true]" ] || { echo "$output"; false; }
  [ "${lines[1]}" = "[null,null,false]" ] || { echo "$output"; false; }
}

# ══ THE RECYCLE HALF (W2b T-recycle-a): cases 5-8, 13 and the focus case ══════════════════════════
# Driven through recycle_fire_commit and the helpers it calls, extracted from the subject: a full
# recycle_fire needs a real tty holding a real claude (see case 2's note). Every stub appends to ONE
# call log, so ORDER is assertable: the it2 stub (`send <%q text>` / `read`), HF_SLEEP (`sleep <s>`),
# the lr-transplant stub (`transplant <argv>`) and the resume-debt stub (`debt <argv>`).
# Mutants (one per case): 5 make _hf_lock_holder_alive always false · 6 make hf_recycle_last_read
# return 0 · 7 make hf_exit_readback return 0 without the DEL send · 8 restore the blind
# `as_write "$SID" ""` · 13 make hf_wake_guard return 0 · F make hf_pane_focused print `no`.

load_tail_funcs() {
  FUNCS="$BATS_TEST_TMPDIR/tail-funcs.sh"
  local f
  {
    grep '^_iso_now() {' "$HF"
    grep '^kt() {' "$HF"
    for f in _under_test emit_recycle_event hf_bounded hf_bounded_s kt_window_field composer_content \
             recycle_composer_gate hf_transcript_at_rest hf_bg_work_kind hf_bg_work_gate hf_lr_script \
             hf_recycle_fenced hf_recycle_lock_dir _hf_lstart _hf_lock_raw _hf_lock_field \
             _hf_lock_holder_alive hf_recycle_lock_write hf_recycle_lock_take hf_recycle_lock_release \
             hf_recycle_lock_acquire hf_recycle_disarm hf_wake_guard hf_pane_focused hf_focus_double_read \
             hf_recycle_unconfirm hf_recycle_hold hf_recycle_last_read hf_exit_readback recycle_fire_commit; do
      sed -n "/^$f() {/,/^}/p" "$HF"
    done
  } > "$FUNCS"
  bash -n "$FUNCS" || { echo "extraction from $HF is not valid bash" >&2; return 1; }
  # shellcheck disable=SC1090
  . "$FUNCS"
  grep -q '^recycle_fire_commit() {' "$FUNCS" || { echo "recycle_fire_commit not extracted" >&2; return 1; }
}

# The stubbed world recycle_fire_commit runs in: a transplanted, LIMITED remote source whose every
# last-read fact is clean unless a case changes one.
tail_world() {
  load_tail_funcs
  STUB="$BATS_TEST_TMPDIR/stub"; mkdir -p "$STUB"
  CALLS="$BATS_TEST_TMPDIR/calls.log"; : > "$CALLS"
  READS="$STUB/reads"; : > "$READS"
  export CALLS READS
  # it2: `session read` serves the NEXT queued composer content (the last one repeats) inside a box.
  cat > "$STUB/it2" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "session send") printf 'send %q\n' "${!#}" >> "$CALLS" ;;
  "session read")
    printf 'read\n' >> "$CALLS"
    c="$(head -n 1 "$READS")"
    [ "$(wc -l < "$READS" | tr -d ' ')" -gt 1 ] && { tail -n +2 "$READS" > "$READS.t"; mv "$READS.t" "$READS"; }
    printf 'history\n────────────────────\n❯ %s\n────────────────────\n' "$c" ;;
esac
exit 0
SH
  printf '#!/usr/bin/env bash\nprintf "sleep %%s\\n" "$1" >> "$CALLS"\n' > "$STUB/sleep"
  printf '#!/usr/bin/env bash\nprintf "transplant %%s\\n" "$*" >> "$CALLS"\nexit "${TRANSPLANT_RC:-0}"\n' > "$STUB/lr-transplant.sh"
  chmod +x "$STUB/it2" "$STUB/sleep" "$STUB/lr-transplant.sh"
  _hf_resume_debt() { printf 'debt %s\n' "$*" >> "$CALLS"; }
  as_write() { printf 'as_write %q\n' "$2" >> "$CALLS"; }
  as_write_transports() { echo stub; }
  subagent_dir_for_sid() { :; }
  live_subagents_of() { :; }
  lr_last_api_error() { printf 'u1\terr\t%s\tts\n' "${LR_KIND:-limit}"; }
  export HF_SLEEP="$STUB/sleep" HF_LR_TRANSPLANT="$STUB/lr-transplant.sh" HF_DIR="$REPO/scripts"
  export HF_TIMEOUT_S="" HF_TIMEOUT_BIN=""
  export HF_KERN_WAKETIME=1 LR_RECORD_ID="rec-1" HF_RECYCLE_LOCK_GATE=on
  export LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks"
  export HF_WATCHER_RECORD="$BATS_TEST_TMPDIR/watcher.json"
  unset CC_TERM CC_TERM_KITTY_TO LR_MOVE_FOCUSED HF_EXIT_READBACK
  SID="$PANE" CMD="relaunch-cmd" RCY_IT2="$STUB/it2" RCY_REMOTE=1 RCY_SAME_ACCOUNT=0
  RCY_TRANSPLANTED_SOURCE=1 RCY_TRANSPLANT_CAUSE=limit ALLOW_LIVE_SA=1
  SESS="$SID_UUID" RCY_TS_SID="$SID_UUID" RCY_SOURCE_SESSION="$SID_UUID"
  HF_TS_CFG="$BATS_TEST_TMPDIR/from" HF_TS_TO="$BATS_TEST_TMPDIR/to"
  RCY_SRC_TX="$TX" HF_TS_TOMBSTONE="" HF_REMOTE_ROW_PID="" RESUME_LAUNCHER="" RESUME_CFG=""
  seed_healthy_transcript
  # The watcher: a real process, so the kill and the lock's (pid, lstart) identity are real too.
  sleep 300 >/dev/null 2>&1 3>&- & WATCHER_PID=$!
  echo "$WATCHER_PID" > "$BATS_TEST_TMPDIR/watcher.$WATCHER_PID.pid"
  export WATCHER_PID
  hf_recycle_lock_acquire "$SID"
  hf_recycle_lock_write "$HF_RECYCLE_LOCK" watcher "$WATCHER_PID"
}
# Every numbered pid this file started, killed however the case ended.
teardown() {
  local p
  for p in "$BATS_TEST_TMPDIR"/*.pid; do
    [ -f "$p" ] && kill "$(cat "$p")" 2>/dev/null
  done
  return 0
}
rows_of() { grep "\"class\":\"$1\"" "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }
calls_n() { grep -cxF -- "$1" "$CALLS" || true; }
SID_UUID="a1b2c3d4-0000-4000-8000-000000000002"

# ── 5 · THE PER-PANE LOCK ──────────────────────────────────────────────────────────────────────

@test "5 a second recycle of a pane whose lock a LIVE holder has is refused; a dead holder is stolen" {
  load_tail_funcs
  export LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks" HF_RECYCLE_LOCK_GATE=on
  local dir holder
  dir="$(hf_recycle_lock_dir 901)"
  mkdir -p "$dir"
  sleep 300 >/dev/null 2>&1 3>&- & holder=$!
  echo "$holder" > "$BATS_TEST_TMPDIR/holder.pid"
  hf_recycle_lock_write "$dir" watcher "$holder"

  run hf_recycle_lock_acquire 901
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"recycle DEFERRED: another recycle of pane 901 is in flight"* ]] || { echo "$output"; false; }
  rows_of recycle-held-locked | grep -q "$holder" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ "$(_hf_lock_field "$(_hf_lock_raw "$dir")" pid)" = "$holder" ] || { cat "$dir/holder"; false; }

  kill "$holder"; wait "$holder" 2>/dev/null || true
  hf_recycle_lock_acquire 901
  [ "$HF_RECYCLE_LOCK" = "$dir" ] || { echo "lock=$HF_RECYCLE_LOCK"; false; }
  [ "$(_hf_lock_field "$(_hf_lock_raw "$dir")" pid)" = "$$" ] || { cat "$dir/holder"; false; }
  grep -q '"role":"recycle"' "$dir/holder"
  grep -q '"record_id":"' "$dir/holder"
  # Only a pid the holder names may release it.
  run hf_recycle_lock_release "$dir" 1
  [ -d "$dir" ] || { echo "a stranger released the lock"; false; }
  hf_recycle_lock_release "$dir" "$$"
  [ ! -d "$dir" ]
}

# ── 6 · THE LAST READ AFTER CONFIRM ────────────────────────────────────────────────────────────

@test "6 a draft that appears after the gate is caught by the post-confirm read: unconfirm, no /exit, held-draft" {
  tail_world
  printf '%s\n' "" "operator draft" > "$READS"
  # The gate the foreground ran before arming saw an empty composer…
  run recycle_composer_gate "$RCY_IT2" "$SID" 0 1
  [ "$status" -eq 0 ] || { echo "the gate did not read empty: $output"; false; }
  # …and the last read, after the confirm, sees the draft.
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  local want="transplant --phase unconfirm --sid $SESS --from $HF_TS_CFG --to $HF_TS_TO --record-id rec-1 --watcher-record $HF_WATCHER_RECORD"
  [ "$(calls_n "$want")" = 1 ] || { cat "$CALLS"; false; }
  [ "$(calls_n "transplant --phase confirm --sid $SESS --from $HF_TS_CFG --to $HF_TS_TO")" = 1 ] || { cat "$CALLS"; false; }
  ! grep -q '^send' "$CALLS" || { echo "a keystroke was sent:"; cat "$CALLS"; false; }
  rows_of recycle-held-draft | grep -q 'operatordraft; unconfirm rc 0' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ ! -d "$HF_RECYCLE_LOCK" ] || { echo "lock not released: $HF_RECYCLE_LOCK"; false; }
  ! kill -0 "$WATCHER_PID" 2>/dev/null || { echo "watcher still alive"; false; }
  # No confirm ran ⇒ nothing to unconfirm.
  tail_world
  printf '%s\n' "operator draft" > "$READS"
  RCY_TRANSPLANTED_SOURCE=0
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  ! grep -q '^transplant' "$CALLS" || { cat "$CALLS"; false; }
  rows_of recycle-held-draft | grep -q 'unconfirm rc n/a' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

# ── 7 · /exit READ-BACK MISMATCH ───────────────────────────────────────────────────────────────

@test "7 an /exit that reads back as anything else gets five DELs, an unconfirm and no CR" {
  local rb
  for rb in "/exi" "x/exit"; do
    tail_world
    printf '%s\n' "" "$rb" > "$READS"
    run recycle_fire_commit "$SESS"
    [ "$status" -eq 1 ] || { echo "[$rb] status=$status $output"; cat "$CALLS"; false; }
    [ "$(calls_n "send /exit")" = 1 ] || { cat "$CALLS"; false; }
    [ "$(calls_n "send \$'\\177\\177\\177\\177\\177'")" = 1 ] || { echo "[$rb]"; cat "$CALLS"; false; }
    [ "$(calls_n "send \$'\\r'")" = 0 ] || { echo "[$rb] a CR was sent"; cat "$CALLS"; false; }
    grep -q '^transplant --phase unconfirm ' "$CALLS" || { cat "$CALLS"; false; }
    grep -q "^debt abandon --sid $SESS " "$CALLS" || { cat "$CALLS"; false; }
    rows_of recycle-held-exit-readback | grep -qF "read back as '$rb'" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
    rm -f "$HOME/.claude/logs/handoffs.jsonl"
    kill "$WATCHER_PID" 2>/dev/null || true
  done
}

# ── 8 · NO BLIND SECOND ENTER ──────────────────────────────────────────────────────────────────

@test "8 the blind anti-strand Enter is gone, and a matching read-back sends exactly one CR" {
  local body
  body="$(sed -n '/^recycle_fire_commit() {/,/^}/p; /^recycle_fire() {/,/^}/p' "$HF")"
  [ -n "$body" ]
  [[ "$body" != *'as_write "$SID" ""'* ]] || { echo "the blind Enter is back"; false; }
  tail_world
  printf '%s\n' "" "/exit" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  [ "$(calls_n "send \$'\\r'")" = 1 ] || { cat "$CALLS"; false; }
  [ "$(calls_n "send /exit")" = 1 ] || { cat "$CALLS"; false; }
  ! grep -q '177' "$CALLS" || { cat "$CALLS"; false; }
  ! grep -q '^as_write' "$CALLS" || { cat "$CALLS"; false; }
  ! grep -q 'unconfirm' "$CALLS" || { cat "$CALLS"; false; }
  # The debt opens before the keystroke, never after it.
  local d s
  d="$(grep -n '^debt open ' "$CALLS" | cut -d: -f1)"; s="$(grep -n '^send /exit$' "$CALLS" | cut -d: -f1)"
  [ -n "$d" ] || { cat "$CALLS"; false; }
  [ "$d" -lt "$s" ] || { cat "$CALLS"; false; }
  # Kill switch: the as_write loop, still with no second Enter.
  tail_world
  printf '%s\n' "" > "$READS"
  HF_EXIT_READBACK=off run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(calls_n "as_write /exit")" = 1 ] || { cat "$CALLS"; false; }
  [ "$(grep -c '^as_write' "$CALLS")" = 1 ] || { cat "$CALLS"; false; }
}

# ── 13 · THE WAKE GUARD ────────────────────────────────────────────────────────────────────────

@test "13 a machine that woke 10s ago defers the confirm until the 30s guard has passed" {
  tail_world
  printf '%s\n' "" "/exit" > "$READS"
  export HF_KERN_WAKETIME=$(( $(date +%s) - 10 )) LR_WAKE_GUARD_S=30
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  [[ "$output" == *"→ wake guard: the machine woke "*"s ago — deferring the transplant confirm "* ]] || { echo "$output"; false; }
  local sl cf
  sl="$(grep -nE '^sleep (19|20|21)$' "$CALLS" | head -n 1 | cut -d: -f1)"
  cf="$(grep -n '^transplant --phase confirm ' "$CALLS" | cut -d: -f1)"
  [ -n "$sl" ] || { echo "no guard sleep recorded"; cat "$CALLS"; false; }
  [ -n "$cf" ] || { cat "$CALLS"; false; }
  [ "$sl" -lt "$cf" ] || { cat "$CALLS"; false; }
  # An unreadable waketime proceeds without a deferral.
  tail_world
  printf '%s\n' "" "/exit" > "$READS"
  export HF_KERN_WAKETIME=garbage
  run hf_wake_guard "x"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -z "$output" ] || { echo "$output"; false; }
}

# ── F · THE FOCUS GATE ─────────────────────────────────────────────────────────────────────────

# kitty stub: `@ ls` lists window 901 focused and 902 not.
kitty_stub() {
  cat > "$STUB/kitty" <<'SH'
#!/usr/bin/env bash
printf '[{"tabs":[{"windows":[{"id":901,"is_focused":true,"pid":1},{"id":902,"is_focused":false,"pid":2}]}]}]\n'
SH
  chmod +x "$STUB/kitty"
  export CC_TERM=kitty CC_KITTY_BIN="$STUB/kitty"
}

@test "F a FOCUSED pane is HELD — by the probe, and at the last read before /exit" {
  tail_world
  kitty_stub
  [ "$(hf_pane_focused 901)" = yes ]
  [ "$(hf_pane_focused 902)" = no ]
  [ "$(CC_TERM=iterm2 hf_pane_focused 901)" = unknown ]

  # The probe's own lines, executed: `focused:` prints and a focused pane is HELD:focused (exit 3).
  local frag="$BATS_TEST_TMPDIR/probe-focus.sh"
  {
    echo 'prp_verdict() { echo "verdict: $1"; exit "$2"; }'
    sed -n '/4d\. FOCUS (W2b/,/UNLESS IT IS NOT A DRAFT/p' "$HF"
    echo 'echo "past the focus gate"'
  } > "$frag"
  PRP_PANE=901 run bash -c ". '$FUNCS'; . '$frag'"
  [ "$status" -eq 3 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"focused: yes"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict: HELD:focused"* ]] || { echo "$output"; false; }
  PRP_PANE=902 run bash -c ". '$FUNCS'; . '$frag'"
  [[ "$output" == *"past the focus gate"* ]] || { echo "$output"; false; }
  PRP_PANE=901 LR_MOVE_FOCUSED=on run bash -c ". '$FUNCS'; . '$frag'"
  [[ "$output" == *"past the focus gate"* ]] || { echo "$output"; false; }

  # The recycle: a pane that became focused by the last read is held, and nothing is sent.
  printf '%s\n' "" "/exit" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  ! grep -q '^send' "$CALLS" || { cat "$CALLS"; false; }
  rows_of recycle-held-focused | grep -q 'unconfirm rc 0' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}
