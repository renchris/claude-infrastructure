#!/usr/bin/env bats
# RECYCLE CUSTODY (W2b, lr-reconciler) — the probe half, cases 1-4; the recycle half appends 5-13.
#
#   1  --voluntary --account-evidence F is the ONLY way a healthy pane passes the limit gate, and a
#      caller passing neither flag sees today's refusal byte-for-byte.
#   1b the probe's teammate test is lr-predicate's parsed is-teammate-head, not a substring grep.
#   2  a background job the session still runs HOLDs the probe (hf_bg_work_gate / hf_bg_work_kind),
#      and the idle inbox watcher does not.
#   3  live_subagents_of counts a Workflow's in-flight agents (subagents/workflows/<run>/…).
#   3b …and a Workflow agent with a `result`/`failed` row in its run's journal.jsonl is settled.
#   4  emit_recycle_event rows carry the attempt + watcher nonce.
#
# WHY CASE 2 IS DRIVEN THROUGH THE EXTRACTED FUNCTIONS, NOT THE PROBE VERB: the bg-work gate sits
# after `pane_state: cc`, which needs a real tty holding a real claude process — nothing a hermetic
# fixture can supply. The gate is one call in the probe; its whole decision lives in the function.
#
# Every case is RED on its feature's revert (one mutant per case, run by hand before landing):
#   1 drop the `--voluntary` bypass branch · 1b drop the parsed true/false arms (substring fallback) ·
#   2 make hf_bg_work_kind print `none` ·
#   3 drop the workflows glob · 3b drop the journal-settle `case` arm ·
#   4 drop the three nonce keys from the jq object.
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
  # The row names the CONFIG DIR (what session-register writes); facts name the ACCOUNT. A stub
  # account map ties the two, the way lib/account-map.generated.sh does on the box.
  printf '{"session_id":"%s","pane":"%s","account":"claude-secondary"}\n' "$SID" "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"
  export CC_ACCOUNT_MAP="$BATS_TEST_TMPDIR/account-map.sh"
  cat > "$CC_ACCOUNT_MAP" <<'MAP'
cc_acct_name_for_dir_basename() {
  case "$1" in
    .claude-secondary|claude-secondary) echo next2 ;;
    .claude-next|claude-next) echo next ;;
    *) return 1 ;;
  esac
}
MAP
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

  fact next2.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$later}"
  probe --voluntary --account-evidence "$EV/next2.5h.json"
  [[ "$output" == *"limit: bypassed — account evidence next2.5h resets_at=$later (voluntary)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"teammate: no"* ]] || { echo "the probe stopped at the limit gate: $output"; false; }

  # An ISO-8601 reset time is read too, and the scope may come from the file name alone.
  fact next2.7d.json "{\"status\":\"rejected\",\"resets_at\":\"$(date -u -r "$later" +%Y-%m-%dT%H:%M:%SZ)\"}"
  probe --voluntary --account-evidence "$EV/next2.7d.json"
  [[ "$output" == *"limit: bypassed — account evidence next2.7d "* ]] || { echo "$output"; false; }

  probe --voluntary
  [ "$status" -eq 5 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict: REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"evidence: missing"* ]] || { echo "$output"; false; }

  fact next2.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$soon}"
  probe --voluntary --account-evidence "$EV/next2.5h.json"
  [[ "$output" == *"verdict: REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"evidence: expiring"* ]] || { echo "$output"; false; }

  fact next2.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$later,\"contradicted\":true}"
  probe --voluntary --account-evidence "$EV/next2.5h.json"
  [[ "$output" == *"verdict: REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"evidence: contradicted"* ]] || { echo "$output"; false; }

  # The fact must be about the account this pane is on.
  fact next.5h.json "{\"status\":\"rejected\",\"scope\":\"5h\",\"resets_at\":$later}"
  probe --voluntary --account-evidence "$EV/next.5h.json"
  [[ "$output" == *"evidence: account-mismatch"* ]] || { echo "$output"; false; }

  # A row whose config dir the account map does not know admits nothing.
  printf '{"session_id":"%s","pane":"%s","account":"claude-nowhere"}\n' "$SID" "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"
  probe --voluntary --account-evidence "$EV/next2.5h.json"
  [[ "$output" == *"verdict: REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"evidence: account-unmapped (claude-nowhere)"* ]] || { echo "$output"; false; }
  printf '{"session_id":"%s","pane":"%s","account":"claude-secondary"}\n' "$SID" "$PANE" > "$CC_REGISTRY_DIR/$PANE.json"

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
  probe --account-evidence "$EV/next2.5h.json"
  [ "$status" -eq 2 ] || { echo "status=$status $output"; false; }
}

@test "1a an auth fact admits the TARGET-AUTH hop with --voluntary; expired, foreign or flagless refuses" {
  seed_healthy_transcript
  local past=$(( $(date +%s) - 120 )) later=$(( $(date +%s) + 600 ))

  # Live: no resets_at (expires by deletion in lr_recon.facts) — admitted.
  fact next2.auth.json '{"status":"rejected","scope":"auth","resets_at":null}'
  probe --voluntary --account-evidence "$EV/next2.auth.json"
  [[ "$output" == *"limit: bypassed — account evidence next2.auth resets_at=- (voluntary)"* ]] || { echo "$output"; false; }
  [[ "$output" != *"REFUSED:not-limited"* ]] || { echo "$output"; false; }

  # A resets_at 10 min out is live for auth (the 30-min rule is a 5h/7d rule).
  fact next2.auth.json "{\"status\":\"rejected\",\"scope\":\"auth\",\"resets_at\":$later}"
  probe --voluntary --account-evidence "$EV/next2.auth.json"
  [[ "$output" == *"limit: bypassed — account evidence next2.auth "* ]] || { echo "$output"; false; }

  # Expired on the facts rule (resets_at + 60 < now).
  fact next2.auth.json "{\"status\":\"rejected\",\"scope\":\"auth\",\"resets_at\":$past}"
  probe --voluntary --account-evidence "$EV/next2.auth.json"
  [[ "$output" == *"verdict: REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [[ "$output" == *"evidence: expired"* ]] || { echo "$output"; false; }

  # Contradicted and foreign auth facts refuse.
  fact next2.auth.json '{"status":"rejected","scope":"auth","contradicted":true}'
  probe --voluntary --account-evidence "$EV/next2.auth.json"
  [[ "$output" == *"evidence: contradicted"* ]] || { echo "$output"; false; }
  fact next.auth.json '{"status":"rejected","scope":"auth"}'
  probe --voluntary --account-evidence "$EV/next.auth.json"
  [[ "$output" == *"evidence: account-mismatch"* ]] || { echo "$output"; false; }

  # Without --voluntary it is still a usage error.
  fact next2.auth.json '{"status":"rejected","scope":"auth"}'
  probe --account-evidence "$EV/next2.auth.json"
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
# ltx <file> [prompt] — a LIMITED transcript: a turn, then the API's limit record; with a second
# argument, a user prompt typed AFTER the limit and not yet answered (D1.2: a turn in flight).
LIMIT_REC='{"type":"assistant","timestamp":"2026-09-29T06:30:57.000Z","isApiErrorMessage":true,"message":{"role":"assistant","stop_reason":"stop_sequence","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 7:50am"}]}}'
ltx() {
  printf '%s\n' '{"type":"user","timestamp":"2026-09-29T06:30:50.000Z","message":{"role":"user","content":"go"}}' "$LIMIT_REC" > "$1"
  if [ -n "${2:-}" ]; then
    printf '{"type":"user","timestamp":"2026-09-29T06:31:00.603Z","message":{"role":"user","content":"%s"}}\n' "$2" >> "$1"
  fi
}

@test "2 a ship-land under a Bash-tool job HOLDS; the idle inbox watcher does not" {
  load_bg_funcs
  local S="$BATS_TEST_TMPDIR/ps.txt" rc
  snap "$S" \
    "5000 4000 $L claude --resume x" \
    "5100 5000 $L /bin/zsh -c source \$HOME/.claude/shell-snapshots/snapshot-zsh-x.sh && eval '/ship now'" \
    "5101 5100 $L bash scripts/ship-wrapper" \
    "5102 5101 $L bash scripts/ship-land.sh --lock"
  export HF_PS_SNAPSHOT="$S"
  local LT="$BATS_TEST_TMPDIR/limited.jsonl"; ltx "$LT"
  run hf_bg_work_kind 5000
  [ "$output" = "work shipland=yes pids=5100" ] || { echo "$output"; false; }
  rc=0; hf_bg_work_gate 5000 1 "$LT" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
  [ "$rc" = 3 ] || { cat "$BATS_TEST_TMPDIR/gate.out"; echo "rc=$rc hold=$HF_BG_HOLD"; false; }
  [ "$HF_BG_HOLD" = "HELD:bg-work:ship-land" ] || { cat "$BATS_TEST_TMPDIR/gate.out"; echo "rc=$rc hold=$HF_BG_HOLD"; false; }
  grep -qx 'bg_work: work shipland=yes pids=5100' "$BATS_TEST_TMPDIR/gate.out"

  snap "$S" \
    "5000 4000 $L claude --resume x" \
    "5200 5000 $L /bin/zsh -c source \$HOME/.claude/shell-snapshots/snapshot-zsh-x.sh && eval '\$HOME/.claude/bin/cc-await-ping --timeout 3300'" \
    "5201 5200 $L /bin/bash \$HOME/.claude/bin/cc-await-ping --timeout 3300" \
    "5202 5200 $L tail -n 5"
  rc=0; hf_bg_work_gate 5000 1 "$LT" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
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
  rc=0; hf_bg_work_gate "" 1 "$LT" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
  [ "$rc" = 0 ] || { cat "$BATS_TEST_TMPDIR/gate.out"; false; }
  grep -qx 'bg_work: unknown (no registry pid)' "$BATS_TEST_TMPDIR/gate.out"
}

# D1.2 (FLEET_V2 W6, lead resolution 10). Mutant: restore the old `limited ⇒ at rest by
# construction` (drop the limited block) — both halves go green-to-red.
@test "2b a LIMITED pane with a prompt typed after the limit is HELD:busy, pid or no pid; a bare limit is at rest" {
  load_bg_funcs
  local LT="$BATS_TEST_TMPDIR/limited.jsonl" rc p
  export HF_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"
  snap "$HF_PS_SNAPSHOT" "5000 4000 $L claude --resume x"
  ltx "$LT" "are you there?"
  for p in 5000 ""; do
    rc=0; hf_bg_work_gate "$p" 1 "$LT" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
    [ "$rc" = 3 ] || { echo "pid=[$p] rc=$rc"; cat "$BATS_TEST_TMPDIR/gate.out"; false; }
    [ "$HF_BG_HOLD" = HELD:busy ] || { echo "pid=[$p] hold=$HF_BG_HOLD"; false; }
    grep -q 'limited, but a turn is in flight after the limit' "$BATS_TEST_TMPDIR/gate.out"
  done
  # An unreadable transcript cannot show at rest either.
  rc=0; hf_bg_work_gate 5000 1 "$BATS_TEST_TMPDIR/absent.jsonl" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
  [ "$rc" = 3 ] || { cat "$BATS_TEST_TMPDIR/gate.out"; false; }
  [ "$HF_BG_HOLD" = HELD:busy ] || { echo "hold=$HF_BG_HOLD"; false; }
  # The limit record alone is where the turn ended: at rest, and the census runs.
  ltx "$LT"
  rc=0; hf_bg_work_gate 5000 1 "$LT" > "$BATS_TEST_TMPDIR/gate.out" || rc=$?
  [ "$rc" = 0 ] || { cat "$BATS_TEST_TMPDIR/gate.out"; false; }
  grep -qx 'bg_work: none shipland=no pids=-' "$BATS_TEST_TMPDIR/gate.out"
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

# The REAL finished shape (wf_99ea9654-29f, 2026-09-29): every agent's last stop_reason is `tool_use`
# (its structured-output call) and the parent transcript holds no task-notification for it; only the
# run's journal.jsonl says it ended. `result` and `failed` both settle; `started` alone does not.
@test "3b a Workflow agent settled in its run's journal is not counted" {
  wfagent wf_y b1 live; wfagent wf_y b2 live; wfagent wf_y b3 live
  printf '%s\n' '{"type":"launched"}' \
    '{"type":"started","key":"v2:k1","agentId":"b1","label":"x","phase":"Map"}' \
    '{"type":"started","key":"v2:k2","agentId":"b2","label":"y","phase":"Map"}' \
    '{"type":"started","key":"v2:k3","agentId":"b3","label":"z","phase":"Map"}' \
    '{"type":"result","key":"v2:k1","agentId":"b1","result":"{\"agentId\":\"b3\"}"}' \
    '{"type":"failed","key":"v2:k2","agentId":"b2"}' \
    > "$CC_PROJECTS_DIRS/-some-repo/$SID/subagents/workflows/wf_y/journal.jsonl"
  run bash "$HF" --probe-live-subagents --source-session "$SID"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # b3 is still in flight — and b1's payload naming it (escaped) must not settle it.
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
             hf_recycle_lock_acquire hf_recycle_disarm hf_wake_guard hf_pane_focused hf_lr_lib_load _hf_focus_composer hf_focus_gate \
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
  # The focus gate sources lr-lib.sh on first use, which would redefine the lr_last_api_error stub
  # below with the real reader. Load it FIRST, so the stubs are the last definitions standing.
  HF_DIR="$REPO/scripts" hf_lr_lib_load || { echo "lr-lib.sh did not load" >&2; return 1; }
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
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  SID="$PANE" CMD="relaunch-cmd" RCY_IT2="$STUB/it2" RCY_REMOTE=1 RCY_SAME_ACCOUNT=0
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  RCY_TRANSPLANTED_SOURCE=1 RCY_TRANSPLANT_CAUSE=limit ALLOW_LIVE_SA=1
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  SESS="$SID_UUID" RCY_TS_SID="$SID_UUID" RCY_SOURCE_SESSION="$SID_UUID"
  HF_TS_CFG="$BATS_TEST_TMPDIR/from" HF_TS_TO="$BATS_TEST_TMPDIR/to"
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  RCY_SRC_TX="$TX" HF_TS_TOMBSTONE="" HF_REMOTE_ROW_PID="" RESUME_LAUNCHER="" RESUME_CFG=""
  seed_healthy_transcript
  # A case that builds a second world must not inherit the first one's watcher: its live holder
  # would (correctly) refuse the new acquire. Retire it and its lock, as a finished recycle would.
  local _p
  for _p in "$BATS_TEST_TMPDIR"/watcher.*.pid; do
    if [ -f "$_p" ]; then kill "$(cat "$_p")" 2>/dev/null || true; rm -f "$_p"; fi
  done
  rm -rf "$LR_LOCKS_DIR"
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
    [ -f "$p" ] && { kill "$(cat "$p")" 2>/dev/null || true; }
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
  [ "$(calls_n "transplant --phase confirm --sid $SESS --from $HF_TS_CFG --to $HF_TS_TO --record-id rec-1")" = 1 ] || { cat "$CALLS"; false; }
  ! grep -q '^send' "$CALLS" || { echo "a keystroke was sent:"; cat "$CALLS"; false; }
  rows_of recycle-held-draft | grep -q 'operatordraft; unconfirm rc 0' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ ! -d "$HF_RECYCLE_LOCK" ] || { echo "lock not released: $HF_RECYCLE_LOCK"; false; }
  ! kill -0 "$WATCHER_PID" 2>/dev/null || { echo "watcher still alive"; false; }
  # No confirm ran ⇒ nothing to unconfirm.
  tail_world
  printf '%s\n' "operator draft" > "$READS"
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  RCY_TRANSPLANTED_SOURCE=0
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  ! grep -q '^transplant' "$CALLS" || { cat "$CALLS"; false; }
  rows_of recycle-held-draft | grep -q 'unconfirm rc n/a' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

# ── 7 · /exit READ-BACK MISMATCH ───────────────────────────────────────────────────────────────

# D7.3 (FLEET_V2 W6): the five DELs erase from the END, so they are ours only when our `/exit` IS the
# end. `ab/exit` (the operator typed first) gets them; `/exitab` (typed after) and a torn `/exi` are
# held with nothing typed. Mutant: send the DELs on every mismatch again — `/exitab` goes red.
@test "7 an /exit that reads back as anything else holds with an unconfirm and no CR; DELs only over a trailing /exit" {
  local rb dels
  for rb in "/exi" "x/exit" "ab/exit" "/exitab"; do
    case "$rb" in */exit) dels=1 ;; *) dels=0 ;; esac
    tail_world
    printf '%s\n' "" "$rb" > "$READS"
    run recycle_fire_commit "$SESS"
    [ "$status" -eq 1 ] || { echo "[$rb] status=$status $output"; cat "$CALLS"; false; }
    [ "$(calls_n "send /exit")" = 1 ] || { cat "$CALLS"; false; }
    [ "$(calls_n "send \$'\\177\\177\\177\\177\\177'")" = "$dels" ] || { echo "[$rb] want $dels DEL send(s)"; cat "$CALLS"; false; }
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
  export PRP_IT2="$RCY_IT2" LR_HID_IDLE_S=2044
  PRP_PANE=901 run bash -c ". '$FUNCS'; . '$frag'"
  [ "$status" -eq 3 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"focused: yes"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict: HELD:focused"* ]] || { echo "$output"; false; }
  PRP_PANE=902 run bash -c ". '$FUNCS'; . '$frag'"
  [[ "$output" == *"past the focus gate"* ]] || { echo "$output"; false; }
  [[ "$output" == *"hid_idle_s: 2044"* ]] || { echo "$output"; false; }
  printf '%s\n' "" "" > "$READS"
  PRP_PANE=901 LR_MOVE_FOCUSED=on run bash -c ". '$FUNCS'; . '$frag'"
  [[ "$output" == *"past the focus gate"* ]] || { echo "$output"; false; }
  [ "$(calls_n read)" = 2 ] || { cat "$CALLS"; false; }
  # D7.2(c): under on, a composer that is not empty on the second read HOLDS in the probe, before
  # any caller's admit, as a draft.
  printf '%s\n' "" "typing" > "$READS"
  PRP_PANE=901 LR_MOVE_FOCUSED=on run bash -c ". '$FUNCS'; . '$frag'"
  [ "$status" -eq 3 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"verdict: HELD:draft"* ]] || { echo "$output"; false; }
  printf '%s\n' "" > "$READS"

  # The recycle: a pane that became focused by the last read is held, and nothing is sent.
  printf '%s\n' "" "/exit" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  ! grep -q '^send' "$CALLS" || { cat "$CALLS"; false; }
  rows_of recycle-held-focused | grep -q 'unconfirm rc 0' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

# ── D7.4 · THE ON-PATH (FLEET_V2 W6): the pre-flip coverage of LR_MOVE_FOCUSED=on ────────────────
# Mutants: F3 make hf_focus_gate return 0 at its top (a focused draft passes) · F4 turn the suffix
# test in _it2_type_line into the substring one (a CR over operator text) · F5 drop the focused-stray
# exclusion in the probe (a first keystroke is receipted for scrubbing) · F6 skip the gate in
# hf_recycle_last_read (a draft typed after the first read gets /exit merged into it).

@test "F3 hf_focus_gate: off holds a focused pane unread; on passes two empty reads a gap apart and holds a draft; no lr-lib holds" {
  tail_world
  kitty_stub
  local rc
  rc=0; hf_focus_gate "$RCY_IT2" 901 || rc=$?
  [ "$rc" = 3 ] || { echo "rc=$rc"; false; }
  [ "$HF_FOCUS_HOLD" = HELD:focused ] || { echo "hold=$HF_FOCUS_HOLD"; false; }
  [ "$(calls_n read)" = 0 ] || { cat "$CALLS"; false; }
  rc=0; hf_focus_gate "$RCY_IT2" 902 || rc=$?
  [ "$rc" = 0 ] || { echo "rc=$rc"; false; }
  [ "$HF_FOCUS_STATE" = no ] || { echo "state=$HF_FOCUS_STATE"; false; }
  export LR_MOVE_FOCUSED=on HF_FOCUS_READ_GAP_S=10
  printf '%s\n' "" "" > "$READS"
  rc=0; hf_focus_gate "$RCY_IT2" 901 || rc=$?
  [ "$rc" = 0 ] || { echo "rc=$rc"; cat "$CALLS"; false; }
  [ "$(grep -E '^(read|sleep)' "$CALLS" | tr '\n' ,)" = "read,sleep 10,read," ] || { cat "$CALLS"; false; }
  : > "$CALLS"; printf '%s\n' "" "half a thought" > "$READS"
  rc=0; hf_focus_gate "$RCY_IT2" 901 || rc=$?
  [ "$rc" = 3 ] || { echo "rc=$rc"; false; }
  [ "$HF_FOCUS_HOLD" = HELD:draft ] || { echo "hold=$HF_FOCUS_HOLD"; false; }
  [ "$HF_FOCUS_READ" = halfathought ] || { echo "read=$HF_FOCUS_READ"; false; }
  # The rule unreachable: a focused pane is HELD, never waved through.
  unset -f lr_focus_gate; unset LR_LIB_LOADED
  HF_DIR="$BATS_TEST_TMPDIR/nowhere" CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/nowhere" hf_focus_gate "$RCY_IT2" 901 || rc=$?
  [ "$HF_FOCUS_HOLD" = HELD:focused ] || { echo "hold=$HF_FOCUS_HOLD"; false; }
}

@test "F4 _it2_type_line on a FOCUSED pane under on withholds the CR when operator text trails the command" {
  tail_world
  kitty_stub
  local T="$BATS_TEST_TMPDIR/tl.sh"
  { grep '^BP_START=' "$HF"; grep '^BP_END=' "$HF"; sed -n '/^_it2_type_line() {/,/^}/p' "$HF"; } > "$T"
  # shellcheck disable=SC1090
  . "$T"
  # it2 stub: `send` remembers the last non-control text; `read` shows it with TRAIL typed after it.
  cat > "$STUB/it2e" <<'SH'
#!/usr/bin/env bash
case "$1 $2" in
  "session send")
    t="${!#}"; printf 'send %q\n' "$t" >> "$CALLS"
    case "$t" in $'\x15'|$'\r') ;; *) t="${t#$'\e[200~'}"; printf '%s' "${t%$'\e[201~'}" > "$CALLS.last" ;; esac ;;
  "session read") printf '$ %s%s\n' "$(cat "$CALLS.last" 2>/dev/null)" "${TRAIL:-}" ;;
esac
exit 0
SH
  chmod +x "$STUB/it2e"
  export LR_MOVE_FOCUSED=on FIRE_TYPE_ATTEMPTS=2 FIRE_TYPE_SETTLE=0 FIRE_TYPE_PRESETTLE=0
  TRAIL="ab" run _it2_type_line "$STUB/it2e" 901 "claude --resume x"
  [ "$status" -eq 1 ] || { echo "status=$status"; cat "$CALLS"; false; }
  [ "$(calls_n "send \$'\\r'")" = 0 ] || { echo "a CR was sent over operator text"; cat "$CALLS"; false; }
  : > "$CALLS"
  TRAIL="" run _it2_type_line "$STUB/it2e" 901 "claude --resume x"
  [ "$status" -eq 0 ] || { echo "status=$status"; cat "$CALLS"; false; }
  [ "$(calls_n "send \$'\\r'")" = 1 ] || { cat "$CALLS"; false; }
  # An unfocused pane keeps the substring match: trailing text is not the operator's there.
  : > "$CALLS"
  TRAIL="ab" run _it2_type_line "$STUB/it2e" 902 "claude --resume x"
  [ "$status" -eq 0 ] || { echo "status=$status"; cat "$CALLS"; false; }
}

@test "F5 the probe reads a FOCUSED pane's two-character composer as a draft, never as a stray to scrub" {
  tail_world
  kitty_stub
  local frag="$BATS_TEST_TMPDIR/probe-composer.sh" F2="$BATS_TEST_TMPDIR/f5-funcs.sh" f
  { for f in composer_residue_dir composer_residue_record hf_composer_intent_load hf_composer_unintended; do
      sed -n "/^$f() {/,/^}/p" "$HF"; done; } > "$F2"
  {
    echo 'prp_verdict() { echo "verdict: $1"; exit "$2"; }'
    sed -n '/4d\. FOCUS (W2b/,/^  prp_verdict OK 0$/p' "$HF"
  } > "$frag"
  export PRP_IT2="$RCY_IT2" LR_HID_IDLE_S=0 LR_MOVE_FOCUSED=on CC_COMPOSER_RESIDUE_DIR="$BATS_TEST_TMPDIR/residue"
  printf '%s\n' "" "" "ab" > "$READS"
  PRP_PANE=901 run bash -c ". '$FUNCS'; . '$F2'; . '$frag'"
  [ "$status" -eq 3 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"verdict: HELD:draft"* ]] || { echo "$output"; false; }
  [ ! -e "$BATS_TEST_TMPDIR/residue" ] || { echo "a receipt was filed:"; ls -R "$BATS_TEST_TMPDIR/residue"; false; }
  # The same two characters in an UNFOCUSED pane are a stray keystroke: receipted, not held.
  printf '%s\n' "ab" > "$READS"
  PRP_PANE=902 run bash -c ". '$FUNCS'; . '$F2'; . '$frag'"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"composer: unintended:stray"* ]] || { echo "$output"; false; }
}

@test "F6 hf_recycle_last_read under on: a focused pane moves past two empty reads, and a draft between them holds" {
  tail_world
  kitty_stub
  export LR_MOVE_FOCUSED=on HF_FOCUS_READ_GAP_S=10
  printf '%s\n' "" "" "" "/exit" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  [ "$(calls_n "send \$'\\r'")" = 1 ] || { cat "$CALLS"; false; }
  grep -qx 'sleep 10' "$CALLS" || { cat "$CALLS"; false; }
  tail_world
  kitty_stub
  export LR_MOVE_FOCUSED=on   # tail_world unsets it
  printf '%s\n' "" "draft" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  ! grep -q '^send' "$CALLS" || { cat "$CALLS"; false; }
  rows_of recycle-held-draft | grep -q 'unconfirm rc 0' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

# D7.2(b): a focused remote transplant's operator can submit straight past the composer reads (the
# guard admits prompts while the admit is unconfirmed), so the last-moment at-rest read covers it.
# Driven as the recycle's own lines. Mutant: restrict the read to same-account again — case 1 passes.
@test "F7 a FOCUSED remote transplant whose operator submitted a prompt is held busy at the last moment; unfocused is not read" {
  tail_world
  local frag="$BATS_TEST_TMPDIR/rest-frag.sh"
  {
    sed -n '/A FOCUSED REMOTE TRANSPLANT GETS THE SAME READ/,/^  if \[ "\$RCY_SAME_ACCOUNT" = 1 \]; then$/p' "$HF"
    echo '  :; fi'
    echo 'echo "past the at-rest read"'
  } > "$frag"
  grep -q 'hf_transcript_at_rest "\$rcy_rest_tx"' "$frag" || { cat "$frag"; false; }
  ltx "$TX" "wait, one more thing"
  RCY_REMOTE=1 RCY_SAME_ACCOUNT=0 RCY_FOCUSED=yes RCY_SRC_TX="$TX" run bash -c ". '$FUNCS'; hf_recycle_disarm() { :; }; . '$frag'"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"recycle ABORTED at the last read"* ]] || { echo "$output"; false; }
  rows_of recycle-held-busy | grep -q 'focused-remote: transcript not at rest' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  # Unfocused: not read at all (the pre-confirm limit read and the post-confirm last read own it).
  RCY_REMOTE=1 RCY_SAME_ACCOUNT=0 RCY_FOCUSED=no RCY_SRC_TX="$TX" run bash -c ". '$FUNCS'; hf_recycle_disarm() { :; }; . '$frag'"
  [[ "$output" == *"past the at-rest read"* ]] || { echo "$output"; false; }
  # Focused, and the limit is where the turn ended: at rest, and the move goes on.
  ltx "$TX"
  RCY_REMOTE=1 RCY_SAME_ACCOUNT=0 RCY_FOCUSED=yes RCY_SRC_TX="$TX" run bash -c ". '$FUNCS'; hf_recycle_disarm() { :; }; . '$frag'"
  [[ "$output" == *"past the at-rest read"* ]] || { echo "$output"; false; }
}

@test "R the MAIN parser takes --record-id: lr-handoff passes it to --recycle whenever the case exists (W5 rig)" {
  run bash "$HF" --record-id recon:x:1 --help
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
  [[ "$output" != *"unknown arg"* ]] || { echo "$output"; false; }
  # the detection lr-handoff runs is satisfied by the main parser, not only by --relaunch-at-shell's
  [ "$(grep -c -- '--record-id)' "$HF")" -ge 2 ]
}

@test "F2 a background TAB's window is not focused, though kitty flags its window is_focused (W5 rig)" {
  tail_world
  # The shape kitty emits (measured in the W5 rig): the active window of EVERY tab of the focused OS
  # window carries is_focused:true; only the tab and OS-window flags say which one the operator sees.
  cat > "$STUB/kitty" <<'SH'
#!/usr/bin/env bash
printf '[{"is_focused":true,"tabs":[{"is_focused":true,"windows":[{"id":901,"is_focused":true,"pid":1}]},{"is_focused":false,"windows":[{"id":903,"is_focused":true,"pid":3}]}]},{"is_focused":false,"tabs":[{"is_focused":true,"windows":[{"id":904,"is_focused":true,"pid":4}]}]}]\n'
SH
  chmod +x "$STUB/kitty"
  export CC_TERM=kitty CC_KITTY_BIN="$STUB/kitty"
  [ "$(hf_pane_focused 901)" = yes ]
  [ "$(hf_pane_focused 903)" = no ]   # background tab of the focused OS window
  [ "$(hf_pane_focused 904)" = no ]   # active tab of an unfocused OS window
  [ "$(kt_window_field "" id)" = 901 ]
}

# ══ THE WATCHER HALF (W2b T-recycle-b): cases 9-12, the 1 s poll and the launch-lock prefix ═══════
# Mutants (one per case, run by hand before landing): 9 make the husk branch `if false` (confirm
# runs) · 10 make hf_launch_lock_take return 0 at its top · 11 make HF_FOLD_STUB default `off` ·
# 12 drop `; unconfirm=needed` from the bgwork row · P default HF_RECYCLE_SHELL_POLL_S to 3 ·
# X make hf_resume_cmd_set always take the legacy branch.
#
# The __recycle watcher is driven directly, as tests/handoff-recycle-custody.bats does: `ps` is a
# shim that reads a claude on the pane until $HOME/shell-at (an epoch) has passed, then a bare zsh;
# it answers `-o lstart=` with one fixed time so lock holders can be stamped. The it2 stub logs every
# call and renders $SCREEN for `session read` when one is set.
watcher_world() {
  W="$BATS_TEST_TMPDIR/w"; mkdir -p "$W/shim"
  export HOME="$BATS_TEST_TMPDIR/whome"; mkdir -p "$HOME/.claude/bin" "$HOME/.claude/logs" "$HOME/.claude/autonomy"
  export CC_HANDOFF_ALARM_DIR="$HOME/.claude/handoff-alarms"
  export CC_ADMIT_IDL="$HOME/.claude/autonomy/idl.jsonl"; : > "$CC_ADMIT_IDL"
  export CC_NOTIFY_BIN="$HOME/.claude/bin/cc-notify"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$CC_NOTIFY_BIN"
  export DEBT_LOG="$W/debt.log" CC_RESUME_DEBT_BIN="$W/cc-resume-debt"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$DEBT_LOG" > "$CC_RESUME_DEBT_BIN"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$W/shim/osascript"
  cat > "$W/shim/ps" <<'SH'
#!/usr/bin/env bash
args="$*"
cc=0; [ "$(date +%s)" -lt "$(cat "$HOME/shell-at" 2>/dev/null || echo 0)" ] && cc=1
case "$args" in *pgid=*) printf '4242\n'; exit 0 ;; esac
# RELATIVE CLOCK: with $HOME/shell-after-first holding N, claude stays up for N s counted from the
# watcher's FIRST pane read, not from the test's start — a loaded box can spend longer than N s
# just starting the watcher, which would put the shell there before the first look.
if [ -f "$HOME/shell-after-first" ]; then
  case "$args" in *"-o comm= -t"*|*"-axww -o args="*|*"-p 100"*)
    [ -f "$HOME/first-read" ] || date +%s > "$HOME/first-read" ;;
  esac
  cc=0
  if [ -f "$HOME/first-read" ] \
     && [ "$(date +%s)" -lt $(( $(cat "$HOME/first-read") + $(cat "$HOME/shell-after-first") )) ]; then cc=1; fi
  [ -f "$HOME/first-read" ] || cc=1
fi
# With $HOME/cc-after-type the pane is a shell until the launcher line is typed, and a claude after.
if [ -f "$HOME/cc-after-type" ]; then
  cc=0; grep -q lr-launch-w.sh "$HOME/it2-calls.log" 2>/dev/null && cc=1
fi
case "$args" in *lstart=*) printf 'Tue Sep 29 10:00:00 2026\n'; exit 0 ;; esac
case "$args" in
  *"-axww -o args="*) [ "$cc" = 1 ] && printf 'claude --resume x\n'; exit 0 ;;
  *"-o pid= -t"*)     printf '100\n' ;;
  *"-o tpgid= -t"*)   printf '100\n' ;;
  *"-o comm= -t"*)    if [ "$cc" = 1 ]; then printf 'claude\n'; else printf -- '-zsh\n'; fi ;;
  *pid=,ppid=*)       printf '100 1\n' ;;
  *"pid=,comm= -g"*)  printf '100 /bin/zsh\n' ;;
  *"-p 100"*)         if [ "$cc" = 1 ]; then printf 'claude\n'; else printf '/bin/zsh\n'; fi ;;
esac
exit 0
SH
  export WPANE="W-PANE"
  cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    [ "${3:-}" = --json ] && printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "$WPANE" || printf '%s\n' "$WPANE"
    exit 0 ;;
  "session read") if [ -n "${SCREEN:-}" ]; then cat "$SCREEN"; else cat "$HOME/it2-screen" 2>/dev/null; fi ;;
  "session send") txt="${!#}"; [ "${#txt}" -gt 3 ] && printf '%s' "$txt" > "$HOME/it2-screen" ;;
esac
exit 0
SH
  printf '#!/usr/bin/env bash\nprintf "transplant %%s\\n" "$*" >> "%s"\n[ -n "${FOLD_OUT:-}" ] && printf "%%s\\n" "$FOLD_OUT"\nexit "${FOLD_RC:-0}"\n' "$W/calls.log" > "$W/lr-transplant.sh"
  chmod +x "$W/shim/ps" "$W/shim/osascript" "$HOME/.claude/bin/it2" "$CC_NOTIFY_BIN" "$CC_RESUME_DEBT_BIN" "$W/lr-transplant.sh"
  export PATH="$W/shim:$PATH" HF_LR_TRANSPLANT="$W/lr-transplant.sh" LR_LOCKS_DIR="$W/locks"
  export CC_REGISTRY_DIR="$W/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export HF_RECYCLE_SHELL_WAIT_S=6 FIRE_TYPE_ATTEMPTS=1 FIRE_TYPE_SETTLE=0 FIRE_TYPE_PRESETTLE=0
  export RCY_BOOT_WAIT_S=1 RCY_BOOT_STALE_S=2 RCY_BOOT_IVL_S=0.2 RCY_BOOT_SLOW_IVL_S=1 RCY_BOOT_PANE_EVERY=2
  export LR_RECORD_ID="rec-9"
  unset CC_TERM HANDOFF_TTY_FAIL_FILE SCREEN HF_LAUNCH_REC HF_LAUNCH_ATT HF_RECYCLE_LOCK
  WCMD="$W/relaunch.cmd"; printf 'cd /tmp && nocorrect bash /tmp/lr-launch-w.sh\n' > "$WCMD"
  WTTY="$W/ttys999"; : > "$WTTY"
  WCFG="$W/to"; mkdir -p "$WCFG"
  WSRC="$W/from/projects/-r/$SID_UUID.jsonl"; mkdir -p "$(dirname "$WSRC")"
}
# The resume-mode watcher: $10 cfg, $11 the resumed sid, $12 T0, $13 the source transcript.
drive_watcher() {
  run bash "$HF" __recycle "$WPANE" "${1:-$WTTY}" "$WCMD" /tmp "$SID_UUID" "" "" "" \
    "$WCFG" "$SID_UUID" "2026-09-29T00:00:00" "$WSRC"
}
typed_relaunch() { grep -c 'lr-launch-w.sh' "$HOME/it2-calls.log" 2>/dev/null || true; }
wrows() { grep "\"class\":\"$1\"" "$HOME/.claude/logs/handoffs.jsonl" 2>/dev/null; }

# ── 9 · --husk ─────────────────────────────────────────────────────────────────────────────────

@test "9 --husk never runs confirm (extracted recycle_fire_commit); a husk whose source has no .handed-off is held" {
  tail_world
  local tomb="$BATS_TEST_TMPDIR/from/projects/-r/$SID_UUID.HANDOFF.json"
  mkdir -p "$(dirname "$tomb")"; : > "${tomb%.HANDOFF.json}.jsonl.handed-off"
  RCY_HUSK=1 HF_TS_TOMBSTONE="$tomb" RESUME_CFG="$HF_TS_TO"
  printf '%s\n' "" "/exit" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  ! grep -q -- '--phase confirm' "$CALLS" || { echo "a husk ran confirm:"; cat "$CALLS"; false; }
  ! grep -q '^transplant' "$CALLS" || { cat "$CALLS"; false; }
  [[ "$output" == *"→ husk: session ${SESS:0:8} is already retired"* ]] || { echo "$output"; false; }
  [ "$(calls_n "send /exit")" = 1 ] || { cat "$CALLS"; false; }

  # Not retired: held, nothing sent, the watcher killed and the pane lock released.
  tail_world
  RCY_HUSK=1 HF_TS_TOMBSTONE="$BATS_TEST_TMPDIR/from/projects/-r/none.HANDOFF.json" RESUME_CFG="$HF_TS_TO"
  printf '%s\n' "" "/exit" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  ! grep -q '^send' "$CALLS" || { cat "$CALLS"; false; }
  ! grep -q '^transplant' "$CALLS" || { cat "$CALLS"; false; }
  rows_of recycle-held-husk | grep -q 'handed-off absent; unconfirm rc n/a' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ ! -d "$HF_RECYCLE_LOCK" ] || { echo "lock not released: $HF_RECYCLE_LOCK"; false; }
  ! kill -0 "$WATCHER_PID" 2>/dev/null || { echo "watcher still alive"; false; }

  # Retired, but handed to a config dir other than --resume-cfg: held too.
  tail_world
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  RCY_HUSK=1 HF_TS_TOMBSTONE="$tomb" RESUME_CFG="$BATS_TEST_TMPDIR/elsewhere"
  printf '%s\n' "" "/exit" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  rows_of recycle-held-husk | grep -q "not --resume-cfg" || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }

  # --husk outside --recycle --transplanted-source is a usage error, before anything else.
  run bash "$HF" --husk --prompt-file /dev/null
  [ "$status" -eq 2 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"--husk is only valid with --recycle --transplanted-source"* ]] || { echo "$output"; false; }
  run bash "$HF" --recycle --husk --prompt-file /dev/null
  [ "$status" -eq 2 ] || { echo "status=$status $output"; false; }
}

# ── 10 · --relaunch-at-shell REFUSES BEFORE ANY KEYSTROKE ──────────────────────────────────────

@test "10 --relaunch-at-shell is HELD:launch-lock under a live foreign holder and HELD:holder while S is held" {
  load_tail_funcs
  export LR_LOCKS_DIR="$BATS_TEST_TMPDIR/locks"
  local launcher="$BATS_TEST_TMPDIR/lr-launch.sh" cfg="$BATS_TEST_TMPDIR/to" idf="$BATS_TEST_TMPDIR/id.json" dir holder
  printf 'exec true\n' > "$launcher"; mkdir -p "$cfg"
  printf '{"tty":"/dev/ttys999","window_id":"%s"}\n' "$PANE" > "$idf"
  ras() { run bash "$HF" --relaunch-at-shell --source-pane "$PANE" --source-session "$SID_UUID" \
            --resume-launcher "$launcher" --resume-cfg "$cfg" --expect-identity "$idf" --record-id rec-10; }

  dir="$LR_LOCKS_DIR/$SID_UUID.launch"; mkdir -p "$dir"
  sleep 300 >/dev/null 2>&1 3>&- & holder=$!
  echo "$holder" > "$BATS_TEST_TMPDIR/holder.pid"
  hf_recycle_lock_write "$dir" relaunch "$holder" rec-other 1
  ras
  [ "$status" -eq 3 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"verdict: HELD:launch-lock"* ]] || { echo "$output"; false; }
  [ "$(_hf_lock_field "$(_hf_lock_raw "$dir")" pid)" = "$holder" ] || { echo "the foreign lock was taken"; cat "$dir/holder"; false; }
  [ ! -e "$HOME/.claude/bin/it2" ] || { echo "an it2 exists in the hermetic HOME"; false; }

  # A dead holder is stolen; then a LIVE registry row for S holds the session — and the lock is given back.
  kill "$holder"; wait "$holder" 2>/dev/null || true
  sleep 300 >/dev/null 2>&1 3>&- & holder=$!
  echo "$holder" > "$BATS_TEST_TMPDIR/holder2.pid"
  printf '{"session_id":"%s","pane":"%s","pid":%s}\n' "$SID_UUID" "$PANE" "$holder" > "$CC_REGISTRY_DIR/$PANE.json"
  ras
  [ "$status" -eq 3 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"launch_lock: ours"* ]] || { echo "$output"; false; }
  [[ "$output" == *"holders: 1"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict: HELD:holder"* ]] || { echo "$output"; false; }
  [ ! -d "$dir" ] || { echo "the launch lock was not released on HELD:holder"; cat "$dir/holder"; false; }

  # An identity file that names none of the four fields is refused before the lock is touched.
  printf '{"other":1}\n' > "$idf"
  ras
  [ "$status" -eq 2 ] || { echo "status=$status $output"; false; }
}

# ── 11 · THE FOLD IS lr-transplant's ───────────────────────────────────────────────────────────

@test "11 a re-created stub is folded by --phase fold-stub (not appended by the watcher); a refusal types nothing" {
  watcher_world
  printf 'retired\n' > "$WSRC.handed-off"; printf 'stub\n' > "$WSRC"
  drive_watcher
  grep -qxF "transplant --phase fold-stub --sid $SID_UUID --from $W/from --to $WCFG --record-id rec-9" "$W/calls.log" \
    || { cat "$W/calls.log"; echo "$output"; false; }
  [ "$(cat "$WSRC.handed-off")" = retired ] || { echo "the watcher appended to .handed-off itself"; cat "$WSRC.handed-off"; false; }
  [[ "$output" == *"via lr-transplant --phase fold-stub"* ]] || { echo "$output"; false; }
  [ "$(typed_relaunch)" -ge 1 ] || { echo "rc 0 must go on to type"; cat "$HOME/it2-calls.log"; false; }

  # rc 2: held — no relaunch typed, nothing settled, an alarm and a recycle-held-fold row naming why.
  watcher_world; rm -f "$HOME/it2-calls.log" "$DEBT_LOG" "$HOME/.claude/logs/handoffs.jsonl"
  printf 'retired\n' > "$WSRC.handed-off"; printf 'stub\n' > "$WSRC"
  FOLD_RC=2 FOLD_OUT='{"ok":false,"reason":"target-held","detail":"target-advanced","sid":"x"}' drive_watcher
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(typed_relaunch)" = 0 ] || { cat "$HOME/it2-calls.log"; false; }
  wrows recycle-held-fold | grep -q 'target-held (target-advanced)' || { cat "$HOME/.claude/logs/handoffs.jsonl"; echo "$output"; false; }
  [ ! -s "$DEBT_LOG" ] || { echo "a refused fold settled the session:"; cat "$DEBT_LOG"; false; }
  grep -lq recycle-held-fold "$CC_HANDOFF_ALARM_DIR"/* || { echo "no alarm"; false; }

  # rc 3 (an lr-transplant without the phase): the legacy append, loudly.
  watcher_world
  printf 'retired\n' > "$WSRC.handed-off"; printf 'stub\n' > "$WSRC"
  FOLD_RC=3 drive_watcher
  [[ "$output" == *"⚠ legacy fold"* ]] || { echo "$output"; false; }
  [ "$(cat "$WSRC.handed-off")" = "$(printf 'retired\nstub')" ] || { cat "$WSRC.handed-off"; false; }
  [ ! -e "$WSRC" ] || { echo "the stub was left"; false; }

  # The launch lock in the watcher: a live foreign holder of the session's lock types nothing.
  watcher_world; rm -f "$HOME/it2-calls.log"
  load_tail_funcs
  local dir="$LR_LOCKS_DIR/$SID_UUID.launch" holder
  mkdir -p "$dir"
  sleep 300 >/dev/null 2>&1 3>&- & holder=$!
  echo "$holder" > "$BATS_TEST_TMPDIR/wholder.pid"
  hf_recycle_lock_write "$dir" relaunch "$holder" rec-other 1
  drive_watcher
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(typed_relaunch)" = 0 ] || { cat "$HOME/it2-calls.log"; false; }
  wrows recycle-held-launch-lock | grep -q 'rec-other' || { cat "$HOME/.claude/logs/handoffs.jsonl"; echo "$output"; false; }
}

@test "14 a stub re-created after confirm is read JOINED with .handed-off: the limit still stands (W5 rig)" {
  tail_world
  local fix="$REPO/tests/fixtures/lr-recon/jsonl"
  unset -f lr_last_api_error; unset LR_LIB_LOADED   # tail_world preloaded lr-lib; load it again
  # shellcheck disable=SC1091  # the REAL reader, not tail_world's stub
  . "$REPO/scripts/limit-recover/lr-lib.sh"
  cp "$fix/death-quota-limits.jsonl" "$TX.handed-off"
  cp "$fix/system-informational-retired-source.jsonl" "$TX"   # the re-created stub: no assistant record
  printf '%s\n' "" > "$READS"
  hf_recycle_last_read || { echo "refused: $HF_LR_REASON $HF_LR_WHAT"; false; }
  # Control: a stub carrying a SUCCESSFUL assistant turn really did lift the limit.
  cat "$fix/assistant-turn.jsonl" >> "$TX"
  ! hf_recycle_last_read || { echo "a lifted limit read as standing"; false; }
  [ "$HF_LR_REASON" = limit-cleared ] || { echo "$HF_LR_REASON $HF_LR_WHAT"; false; }
}

@test "14b a VOLUNTARY move's background-work gate reads the same JOINED transcript as its at-rest proof (W5b canary 3)" {
  tail_world
  local fix="$REPO/tests/fixtures/lr-recon/jsonl"
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  RCY_TRANSPLANT_CAUSE=voluntary HF_REMOTE_ROW_PID="$$"
  cp "$fix/assistant-turn.jsonl" "$TX.handed-off"                   # retired: at rest
  cp "$fix/system-informational-retired-source.jsonl" "$TX"   # the re-created stub: no turn at all
  printf '%s\n' "" > "$READS"
  # the at-rest proof read retired + stub and passed; the gate was handed the stub ALONE, could not
  # prove at-rest from it, and held HELD:mid-turn a session that was at rest — 181 husk spawns
  hf_recycle_last_read || { echo "refused: $HF_LR_REASON $HF_LR_WHAT"; false; }
  # Control: a stub whose tail is a user turn in flight really is mid-turn, and still holds.
  cat "$fix/user-prompt.jsonl" >> "$TX"
  ! hf_recycle_last_read || { echo "a turn in flight read as at rest"; false; }
}

# ── 15 · THE TARGET ANSWERED WITH A LIMIT: A VERDICT, NOT A WAIT ───────────────────────────────

# The watcher in the background holding a real pane lock, as recycle_fire hands it one; $1 = extra env.
drive_watcher_locked() {
  load_tail_funcs
  rm -f "$HOME/it2-calls.log" "$HOME/.claude/logs/handoffs.jsonl"; touch "$HOME/cc-after-type"
  mkdir -p "$(dirname "$WCFG/projects/-r/x")"
  cp "$REPO/tests/fixtures/lr-recon/jsonl/death-quota-limits.jsonl" "$WCFG/projects/-r/$SID_UUID.jsonl"
  export HF_RECYCLE_LOCK="$LR_LOCKS_DIR/pane-t.recycle"; mkdir -p "$HF_RECYCLE_LOCK"
  local t0=$SECONDS wp
  env "$@" bash "$HF" __recycle "$WPANE" "$WTTY" "$WCMD" /tmp "$SID_UUID" "" "" "" \
    "$WCFG" "$SID_UUID" "2026-09-29T00:00:00" "$WSRC" > "$W/watcher.out" 2>&1 & wp=$!
  echo "$wp" > "$BATS_TEST_TMPDIR/wl.pid"
  hf_recycle_lock_write "$HF_RECYCLE_LOCK" watcher "$wp"
  status=0; wait "$wp" || status=$?
  output="$(cat "$W/watcher.out")"; elapsed=$((SECONDS - t0))
}

# D1.2(b). Mutant: drop the at-rest read in hf_recycle_last_read's limited branch — the /exit goes in
# over the operator's in-flight prompt.
@test "14c a LIMITED source whose operator typed after the limit is held busy at the last read: unconfirm, no /exit" {
  tail_world
  ltx "$TX" "are you there?"
  printf '%s\n' "" "/exit" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 1 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
  ! grep -q '^send' "$CALLS" || { cat "$CALLS"; false; }
  grep -q '^transplant --phase unconfirm ' "$CALLS" || { cat "$CALLS"; false; }
  rows_of recycle-held-busy | grep -q 'unconfirm rc 0' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [[ "$output" == *"held: busy"* ]] || { echo "$output"; false; }
  # The limit alone, with no prompt after it, still moves.
  tail_world
  ltx "$TX"
  printf '%s\n' "" "/exit" > "$READS"
  run recycle_fire_commit "$SESS"
  [ "$status" -eq 0 ] || { echo "status=$status $output"; cat "$CALLS"; false; }
}

@test "15 a target that answers with a limit ends the watcher at once: target-limited row, lock released, no dead page" {
  watcher_world
  drive_watcher_locked RCY_ENGAGE_TIMEOUT=60 RCY_ENGAGE_INTERVAL=1 LR_RECORD_ID=recon:x:1
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"RECYCLE FAILED — target-limited"* ]] || { echo "$output"; false; }
  [ "$elapsed" -lt 20 ] || { echo "waited ${elapsed}s: $output"; false; }
  wrows recycle-target-limited | grep -q 'the target answered limit' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ -z "$(wrows recycle-dead)" ] || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  [ ! -d "$HF_RECYCLE_LOCK" ] || { echo "the pane lock was not released"; cat "$HF_RECYCLE_LOCK/holder"; false; }
  ! grep -rqsE 'HANDOFF-RECYCLE-(DEAD|TARGET)' "$CC_HANDOFF_ALARM_DIR" \
    || { echo "a reconciler-owned move paged:"; grep -rhsE 'HANDOFF-RECYCLE' "$CC_HANDOFF_ALARM_DIR"; false; }

  # RED control, today's behaviour: with the arm off the same world waits out the window as "never engaged".
  watcher_world
  drive_watcher_locked RCY_ENGAGE_TIMEOUT=3 RCY_ENGAGE_INTERVAL=1 LR_RECORD_ID=recon:x:1 HF_RECYCLE_TARGET_ERROR_EXIT=off
  [[ "$output" == *"never engaged"* ]] || { echo "$output"; false; }
  wrows recycle-dead | grep -q . || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

# ── 12 · CANCELLING THE BACKGROUND-WORK DIALOG OWES AN UNCONFIRM ───────────────────────────────

@test "12 the bgwork dialog under CC_RECYCLE_BGWORK_ANSWER=cancel: one Esc, no relaunch, unconfirm=needed" {
  watcher_world
  export SCREEN="$REPO/tests/fixtures/lr-recon/screens/bgwork-dialog-2.1.284.txt"
  export CC_PANE_MODAL_LIB="$REPO/hooks/lib/pane-modal.sh" CC_RECYCLE_BGWORK_EVERY_S=3
  # The /exit did not land: claude is still on the pane, sitting at the dialog.
  echo $(( $(date +%s) + 600 )) > "$HOME/shell-at"
  CC_RECYCLE_BGWORK_ANSWER=cancel drive_watcher
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [ "$(grep -c $'session send .*\e' "$HOME/it2-calls.log")" = 1 ] || { cat -v "$HOME/it2-calls.log"; false; }
  [ "$(typed_relaunch)" = 0 ] || { cat "$HOME/it2-calls.log"; false; }
  wrows recycle-held-bgwork | grep -q 'nothing typed; unconfirm=needed' || { cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
}

@test "12b the 2-option dialog (agent view off) gets one Esc and never a digit — under cancel AND by default" {
  local mode
  for mode in cancel on; do
    watcher_world
    rm -f "$HOME/it2-calls.log" "$HOME/.claude/logs/handoffs.jsonl"
    export SCREEN="$REPO/tests/fixtures/lr-recon/screens/bgwork-dialog-2.1.284-agent-view-off.txt"
    export CC_PANE_MODAL_LIB="$REPO/hooks/lib/pane-modal.sh" CC_RECYCLE_BGWORK_EVERY_S=3
    echo $(( $(date +%s) + 600 )) > "$HOME/shell-at"
    CC_RECYCLE_BGWORK_ANSWER="$mode" drive_watcher
    [ "$status" -eq 1 ] || { echo "mode=$mode $output"; false; }
    [ "$(grep -c $'session send .*\e' "$HOME/it2-calls.log")" = 1 ] || { echo "mode=$mode"; cat -v "$HOME/it2-calls.log"; false; }
    ! grep -qE 'session send (-s [^ ]+ )?[0-9]$' "$HOME/it2-calls.log" || { echo "mode=$mode typed a digit"; cat -v "$HOME/it2-calls.log"; false; }
    [ "$(typed_relaunch)" = 0 ] || { echo "mode=$mode"; cat "$HOME/it2-calls.log"; false; }
    wrows recycle-held-bgwork | grep -q 'unconfirm=needed' || { echo "mode=$mode"; cat "$HOME/.claude/logs/handoffs.jsonl"; false; }
  done
  # The 3-option shape in default mode still answers its READ keep-work index, with no Esc.
  watcher_world
  rm -f "$HOME/it2-calls.log"
  export SCREEN="$REPO/tests/fixtures/lr-recon/screens/bgwork-dialog-2.1.284.txt"
  echo $(( $(date +%s) + 8 )) > "$HOME/shell-at"
  CC_RECYCLE_BGWORK_ANSWER=on drive_watcher
  grep -qE 'session send (-s [^ ]+ )?2$' "$HOME/it2-calls.log" || { cat -v "$HOME/it2-calls.log"; echo "$output"; false; }
  ! grep -q $'session send .*\e' "$HOME/it2-calls.log" || { cat -v "$HOME/it2-calls.log"; false; }
}

@test "12c after the Esc, our own /exit left in the composer is scrubbed; an operator's text is not" {
  local mode fx="$REPO/tests/fixtures/lr-recon/screens"
  for mode in ours theirs; do
    watcher_world
    rm -f "$HOME/it2-calls.log"
    # composer screens: the empty fixture with its prompt line replaced
    sed 's/^❯.*/❯ \/exit/' "$fx/composer-empty-2.1.284.txt" > "$HOME/scr-exit"
    sed 's/^❯.*/❯ half a thought the operator typed/' "$fx/composer-empty-2.1.284.txt" > "$HOME/scr-draft"
    cp "$fx/composer-empty-2.1.284.txt" "$HOME/scr-empty"
    cp "$fx/bgwork-dialog-2.1.284-agent-view-off.txt" "$HOME/scr"
    export SCREEN="$HOME/scr" AFTER_ESC="$HOME/scr-exit"
    [ "$mode" = theirs ] && AFTER_ESC="$HOME/scr-draft"
    # the pane: Esc closes the dialog onto AFTER_ESC; Ctrl-U empties the composer
    cat > "$HOME/.claude/bin/it2" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/it2-calls.log"
case "$1 $2" in
  "session list")
    [ "${3:-}" = --json ] && printf '[{"id": "%s", "tty": "/dev/ttys999"}]\n' "$WPANE" || printf '%s\n' "$WPANE"
    exit 0 ;;
  "session read") cat "$SCREEN" ;;
  "session send") txt="${!#}"
    [ "$txt" = $'\e' ] && cp "$AFTER_ESC" "$SCREEN"
    [ "$txt" = $'\x15' ] && cp "$HOME/scr-empty" "$SCREEN" ;;
esac
exit 0
SH
    chmod +x "$HOME/.claude/bin/it2"
    export CC_PANE_MODAL_LIB="$REPO/hooks/lib/pane-modal.sh" CC_RECYCLE_BGWORK_EVERY_S=3 FIRE_TYPE_SETTLE=0
    echo $(( $(date +%s) + 600 )) > "$HOME/shell-at"
    CC_RECYCLE_BGWORK_ANSWER=cancel drive_watcher
    [ "$status" -eq 1 ] || { echo "mode=$mode $output"; false; }
    if [ "$mode" = ours ]; then
      grep -q $'session send .*\x15' "$HOME/it2-calls.log" || { echo "mode=$mode"; cat -v "$HOME/it2-calls.log"; false; }
    else
      ! grep -q $'session send .*\x15' "$HOME/it2-calls.log" || { echo "mode=$mode scrubbed a draft"; cat -v "$HOME/it2-calls.log"; false; }
    fi
    [ "$(typed_relaunch)" = 0 ] || { echo "mode=$mode"; cat "$HOME/it2-calls.log"; false; }
  done
}

# ── P · THE 1 s SHELL POLL ─────────────────────────────────────────────────────────────────────

@test "P a shell that appears ~1 s after the /exit is confirmed with waited < 3" {
  watcher_world
  echo 1 > "$HOME/shell-after-first"
  drive_watcher
  [[ "$output" =~ CONFIRMED\ at\ a\ shell\ prompt\ after\ ([0-9]+)s ]] || { echo "$output"; false; }
  [ "${BASH_REMATCH[1]}" -ge 1 ] || { echo "the shell was never claude first: $output"; false; }
  [ "${BASH_REMATCH[1]}" -lt 3 ] || { echo "waited ${BASH_REMATCH[1]}s: $output"; false; }
}

# ── X · THE LAUNCH-LOCK PREFIX IN THE RESUME-MODE COMMAND ──────────────────────────────────────

@test "X the resume-mode command carries LR_LAUNCH_LOCK/LR_RECORD_ID/LR_ATTEMPT; HF_LAUNCH_LOCK=off is today's" {
  load_tail_funcs
  local f
  for f in hf_launch_identity hf_launch_lock_dir hf_resume_cmd_set; do
    eval "$(sed -n "/^$f() {/,/^}/p" "$HF")"
  done
  export LR_LOCKS_DIR="$BATS_TEST_TMPDIR/lk" LR_RECORD_ID=rec-x LR_ATTEMPT=2
  unset HF_LAUNCH_REC HF_LAUNCH_ATT NC
  # shellcheck disable=SC2034  # globals read by the handoff-fire functions under test
  RCY_CWD="/w d" RESUME_LAUNCHER="/l/lr-launch.sh"
  hf_resume_cmd_set "$SID_UUID"
  [ "$CMD" = "cd /w\\ d && nocorrect env LR_LAUNCH_LOCK=$BATS_TEST_TMPDIR/lk/$SID_UUID.launch LR_RECORD_ID=rec-x LR_ATTEMPT=2 bash /l/lr-launch.sh" ] || { echo "$CMD"; false; }
  HF_LAUNCH_LOCK=off hf_resume_cmd_set "$SID_UUID"
  [ "$CMD" = "cd /w\\ d && nocorrect bash /l/lr-launch.sh" ] || { echo "$CMD"; false; }
  # No record in the environment: one hf-<pid>-<epoch> pair, computed once and reused.
  unset LR_RECORD_ID HF_LAUNCH_REC HF_LAUNCH_ATT
  hf_resume_cmd_set "$SID_UUID"
  [[ "$CMD" == *" LR_RECORD_ID=hf-$$-"*" LR_ATTEMPT=1 bash "* ]] || { echo "$CMD"; false; }
  local first="$HF_LAUNCH_REC"
  hf_resume_cmd_set "$SID_UUID"
  [ "$HF_LAUNCH_REC" = "$first" ] || { echo "$first → $HF_LAUNCH_REC"; false; }
}
