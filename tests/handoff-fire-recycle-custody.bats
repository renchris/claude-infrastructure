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
