#!/usr/bin/env bats
# lr-handoff.sh — TERMINAL STATES AND THE MOVE-LANE ABORT (lr-reliability-telemetry-speed 2026-10-10,
# wave C: report D4 and D5, ranked rows 4 and 3).
#
# D4: the in-place stand-down aborts its own admit through `$( )`, where lr-transplant's holder
#     default `$PPID` names the substitution subshell, not lr-handoff — so every abort carrying a
#     record id (every move-lane and reconciler row) was refused as "a live actuator" (4 of 4).
# D5: every way out of a run leaves a terminal line in the bundle's events.jsonl, the log
#     `cc-lr status` reads: the verdict writes it, and a non-zero exit with no verdict writes
#     `exited`. Before this, 151 of 224 bundles ended non-terminal and a FAILED run read `admitted`.
#
# Harness: copied from tests/lr-handoff-flags.bats — the REAL script, stubbed only at its edges,
# under a fixture $HOME.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  HANDOFF="$REPO/scripts/limit-recover/lr-handoff.sh"

  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export CC_FIRE_CAPACITY_GATE=off CC_FIRE_HEADROOM_GATE=off CC_ADMIT_GATE=off
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit" CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export IT2_BIN="$BATS_TEST_TMPDIR/absent-it2"
  export LRH_LIVE_PARSER_CHECK=off
  export LRH_PRECHECK=off
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  unset LR_PLACED_BY LR_ASSIGN_ID LR_ADMIT_TOKEN_PATH LR_PRESEED_DONE LR_WAKE_GUARD_S LR_INPLACE_AWAIT
  unset HF_RECYCLE_ATTEMPT HF_WATCHER_RECORD CC_RECYCLE_BGWORK_ANSWER KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export HF_LOG="$BATS_TEST_TMPDIR/hf.log"; : > "$HF_LOG"
  export TX_LOG="$BATS_TEST_TMPDIR/tx.log"; : > "$TX_LOG"
  export PRESEED_LOG="$BATS_TEST_TMPDIR/preseed.log"; : > "$PRESEED_LOG"
  export VERIFY_LOG="$BATS_TEST_TMPDIR/verify.log"; : > "$VERIFY_LOG"
  export ACCT_LOG="$BATS_TEST_TMPDIR/accounts.log"; : > "$ACCT_LOG"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  LRD="$HOME/.claude/scripts/limit-recover"
  mkdir -p "$LRD" "$HOME/.claude/projects" "$HOME/.claude-next/projects/-x-y" \
           "$HOME/.claude-secondary/projects" "$BATS_TEST_TMPDIR/plain" "$BATS_TEST_TMPDIR/ev"

  # handoff-fire: answers the probe and records every call (it does NOT parse --record-id or
  # --account-evidence, which is the live state this wave lands against).
  cat > "$STUB/handoff-fire.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${HF_LOG:?}"
printf 'BGWORK=%s ATTEMPT=%s\n' "${CC_RECYCLE_BGWORK_ANSWER:-}" "${HF_RECYCLE_ATTEMPT:-}" >> "${HF_LOG:?}"
case " $* " in
  *" --probe-recycle-preconditions "*) printf 'live_subagents: 0\n%s' "${PROBE_EXTRA:-}"; printf 'verdict: OK\n'; exit 0 ;;
esac
[ -n "${TOMB_CHECK:-}" ] && [ -e "$TOMB_CHECK" ] && echo "tombstone-present-at-fire" >> "${HF_LOG:?}"
if [ -n "${HF_HELD_CLASS:-}" ]; then
  mkdir -p "$HOME/.claude/logs"
  printf '{"ts":"%s","class":"%s","target_pane":"31"}\n' "$(date -u +%FT%TZ)" "$HF_HELD_CLASS" >> "$HOME/.claude/logs/handoffs.jsonl"
fi
[ -n "${HF_ERR:-}" ] && printf '%s\n' "$HF_ERR" >&2
exit "${HF_RC:-0}"
STUB
  printf '#!/bin/bash\nexit 0\n' > "$STUB/cc-notify"
  # --print-only hands the launcher to `cursor`; unshimmed it would open the real editor
  printf '#!/bin/bash\nexit 0\n' > "$STUB/cursor"
  # claude-accounts: ranks only next3, so the router REFUSES next2 whenever it is consulted.
  cat > "$STUB/claude-accounts" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${ACCT_LOG:?}"
printf 'next3 90\n'
STUB
  chmod +x "$STUB/"*
  export CC_HANDOFF_FIRE_BIN="$STUB/handoff-fire.sh" CC_NOTIFY_BIN="$STUB/cc-notify"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"

  cat > "$LRD/lr-audit.py" <<'PY'
import sys, json, os
a = sys.argv
out = a[a.index('--json') + 1]
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump({"session_dir": "/nonexistent", "transcript_sha256": "deadbeef",
           "counts": {"gaps": 3, "waiting": 2}}, open(out, "w"))
PY
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "${PRESEED_LOG:?}"\n' > "$LRD/lr-preseed-env.sh"
  cat > "$LRD/lr-transplant.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${TX_LOG:?}"
printf '{"ok":true,"target_transcript":"/dev/null"}\n'
STUB
  # argv printer with unambiguous boundaries
  cat > "$LRD/lr-fire-resume.sh" <<'STUB'
#!/bin/bash
echo "argc=$#"
echo "pair=<${LR_RECORD_ID:-}|${LR_ATTEMPT:-}>"
i=0; for a in "$@"; do i=$((i+1)); printf 'argv[%d]=<%s>\n' "$i" "$a"; done
STUB
  # lr-ingest-verify: VERIFY_MODE picks the receipt (rc0 | A1 | A2 | C3)
  cat > "$LRD/lr-ingest-verify.sh" <<'STUB'
#!/bin/bash
echo ran >> "${VERIFY_LOG:?}"
case "${VERIFY_MODE:-rc0}" in
  rc0) echo "PASS A1 — gaps_at_handoff=0"; echo "FAST-PATH PROMPT — $LR_SUBMIT_TOKEN"; exit 0 ;;
  A1)  echo "FAIL A1 — gaps_at_handoff=3"; echo "verdict: rc 1 (first failure: A1)"; exit 1 ;;
  A2)  echo "PASS A1 — gaps_at_handoff=0"; echo "FAIL A2 — counts.gaps=1 counts.waiting=1"; echo "verdict: rc 1 (first failure: A2)"; exit 1 ;;
  C3)  echo "PASS A1 — gaps_at_handoff=0"; echo "FAIL C3 — target transcript sha mismatch"; echo "verdict: rc 1 (first failure: C3)"; exit 1 ;;
esac
STUB
  chmod +x "$LRD/"*.sh

  export PATH="$STUB:$PATH"
  SID="0000bbbb-0000-4000-8000-00000000beef"
  printf '{"session_id":"%s"}\n' "$SID" > "$CC_REGISTRY_DIR/31.json"
  # a HEALTHY transcript on the source account: the pane is not limit-blocked
  printf '{"type":"assistant","timestamp":"2026-09-29T10:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n' \
    > "$HOME/.claude-next/projects/-x-y/$SID.jsonl"
}

# in-place driver form on the source account `next` (config dir .claude-next) → target next2
fire() {
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$SID" --target next2 --config-dir "$HOME/.claude-next" \
      --cwd "$BATS_TEST_TMPDIR/plain" --launch --in-place --source-pane 31 "$@"
}
# the bundle's state log, and its last recorded state
events() { local f last=""; for f in "$HOME/.reso/limit-recover/$SID"/bundle-*/events.jsonl; do [ -e "$f" ] && last="$f"; done; printf '%s' "$last"; }
last_state() { local ev; ev="$(events)"; [ -n "$ev" ] || return 1; tail -1 "$ev" | jq -r .state; }

# ── D4: the move lane's stand-down can abort its own admit ─────────────────────────────────────
# The REAL lr-transplant runs, and --record-id makes it write a holder into the lock (lrt_holder_json
# returns early without one, which is why the record-less D7.1 rows in lr-handoff-flags.bats pass).
# On trunk the abort runs inside `$( )`, its $PPID is the subshell, and it refuses its own caller:
# FAILED rc 4, tombstone and lock left behind. Mutant: drop `LR_HOLDER_PID=…` from the abort call.
@test "D4 an in-place stand-down WITH a record id aborts its own admit: NOTMOVED rc 6, tombstone and lock gone" {
  cp "$REPO/scripts/limit-recover/lr-transplant.sh" "$LRD/lr-transplant.sh"; chmod +x "$LRD/lr-transplant.sh"
  local tomb="$HOME/.claude-next/projects/-x-y/$SID.HANDOFF.json" lock="$LR_STATE_DIR/locks/$SID.lock"
  TOMB_CHECK="$tomb" HF_HELD_CLASS=recycle-held-focused HF_RC=1 \
    HF_ERR="!! recycle DEFERRED: pane 31 is FOCUSED — the operator may be typing into it. Nothing typed, no watcher armed, the session stays alive." \
    fire --record-id R1
  grep -q '^tombstone-present-at-fire$' "$HF_LOG" || { echo "the admit never tombstoned"; cat "$HF_LOG"; false; }
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  [[ "$output" != *"live-actuator"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=NOTMOVED"* ]] || { echo "$output"; false; }
  [ ! -e "$tomb" ] || { echo "tombstone still there"; false; }
  [ ! -e "$lock" ] || { echo "lock still there"; false; }
  [ -f "$HOME/.claude-next/projects/-x-y/$SID.jsonl" ] || { echo "the source transcript is gone"; false; }
}
