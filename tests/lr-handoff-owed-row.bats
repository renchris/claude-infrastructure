#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2034,SC2119,SC2120  # single-quoted text is literal on purpose; globals feed the sourced lr-handoff; fire() takes optional args
# lr-handoff.sh — THE MOVE LANE SPENDS THE OWED RECYCLE ROW IT SETTLED ITSELF (R2,
# docs/plans/LIMIT_RECOVER_SELF_INPLACE.md, incident 2026-10-18).
#
# A remote-form recycle (--source-pane P --source-session S) that handoff-fire HELD files a
# pane-close-queue `recycle` row keyed on P holding the worker's argv. Once lr-handoff has settled the
# hold itself (abort rc 0 before the confirm, or unconfirm rc 0 after it) that argv is dead; a
# surviving row was mailed to the SUBJECT as "re-run it". Mutant: drop the two lrh_owed_recycle_spend
# calls — the RED rows below keep their row.
#
# Harness: copied from tests/lr-handoff-terminal-state.bats — the REAL script, stubbed only at its
# edges, under a fixture $HOME and a fixture queue dir.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  HANDOFF="$REPO/scripts/limit-recover/lr-handoff.sh"
  LIB="$REPO/scripts/lib/pane-close-queue.sh"

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
  export CC_PANE_CLOSE_QUEUE_DIR="$BATS_TEST_TMPDIR/q"
  unset LR_PLACED_BY LR_ASSIGN_ID LR_ADMIT_TOKEN_PATH LR_PRESEED_DONE LR_WAKE_GUARD_S LR_INPLACE_AWAIT
  unset HF_RECYCLE_ATTEMPT HF_WATCHER_RECORD CC_RECYCLE_BGWORK_ANSWER KITTY_WINDOW_ID CC_LRH_OWED_ROW_SPEND
  export IT2_WRAPPER_NO_KITTY=1

  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export HF_LOG="$BATS_TEST_TMPDIR/hf.log"; : > "$HF_LOG"
  export TX_LOG="$BATS_TEST_TMPDIR/tx.log"; : > "$TX_LOG"
  export PRESEED_LOG="$BATS_TEST_TMPDIR/preseed.log"; : > "$PRESEED_LOG"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  LRD="$HOME/.claude/scripts/limit-recover"
  mkdir -p "$LRD" "$HOME/.claude/projects" "$HOME/.claude-next/projects/-x-y" \
           "$HOME/.claude-secondary/projects" "$BATS_TEST_TMPDIR/plain"

  # handoff-fire: answers the probe, then exits HF_RC with HF_ERR on stderr (the hold under test).
  cat > "$STUB/handoff-fire.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${HF_LOG:?}"
case " $* " in
  *" --probe-recycle-preconditions "*) printf 'live_subagents: 0\nverdict: OK\n'; exit 0 ;;
esac
[ -n "${HF_ERR:-}" ] && printf '%s\n' "$HF_ERR" >&2
exit "${HF_RC:-0}"
STUB
  printf '#!/bin/bash\nexit 0\n' > "$STUB/cc-notify"
  printf '#!/bin/bash\nexit 0\n' > "$STUB/cursor"
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
  # every phase (admit, abort) succeeds and nothing is retired, so a hold lands in the abort branch
  cat > "$LRD/lr-transplant.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${TX_LOG:?}"
printf '{"ok":true,"target_transcript":"/dev/null"}\n'
STUB
  chmod +x "$LRD/"*.sh

  export PATH="$STUB:$PATH"
  SID="0000bbbb-0000-4000-8000-00000000beef"
  printf '{"session_id":"%s"}\n' "$SID" > "$CC_REGISTRY_DIR/31.json"
  printf '{"type":"assistant","timestamp":"2026-09-29T10:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n' \
    > "$HOME/.claude-next/projects/-x-y/$SID.jsonl"
}

# in-place driver form on the source account `next` → target next2, source pane 31
fire() {
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$SID" --target next2 --config-dir "$HOME/.claude-next" \
      --cwd "$BATS_TEST_TMPDIR/plain" --launch --in-place --source-pane 31 "$@"
}
# the owed row handoff-fire's hf_recycle_owed_record would have filed for pane <p>
owe() { bash -c '. "$0"; pcq_add "$@"' "$LIB" recycle "$1" sid="$SID" reason=unreachable form=remote \
          argv="--recycle --source-pane $1 --source-session $SID"; }

HOLD_BEFORE="!! recycle ABORTED: watcher heartbeat never appeared (log) — /exit NOT typed, session stays alive."
HOLD_AFTER="!! recycle ABORTED before /exit (held: draft) — lr-transplant --phase unconfirm rc 0. Nothing typed."

@test "abort rc 0 before the confirm spends the source pane's owed recycle row" {
  owe 31
  [ -f "$CC_PANE_CLOSE_QUEUE_DIR/recycle-31.json" ]
  HF_RC=1 HF_ERR="$HOLD_BEFORE" fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  grep -q -- '--phase abort' "$TX_LOG" || { cat "$TX_LOG"; false; }
  [ ! -e "$CC_PANE_CLOSE_QUEUE_DIR/recycle-31.json" ] || { echo "owed row survived"; echo "$output"; false; }
  [[ "$output" == *"lr-handoff: owed recycle row for pane 31 spent (the move lane settled this hold itself)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"lr-handoff: verdict: HELD:"* ]] || { echo "$output"; false; }
}

@test "HELD after the confirm with unconfirm rc 0 spends the source pane's owed recycle row" {
  owe 31
  HF_RC=1 HF_ERR="$HOLD_AFTER" fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"lr-handoff: verdict: HELD:draft — held after the confirm"* ]] || { echo "$output"; false; }
  [ ! -e "$CC_PANE_CLOSE_QUEUE_DIR/recycle-31.json" ] || { echo "owed row survived"; echo "$output"; false; }
}

@test "CONTROL: only the source pane's row is spent — another pane's row (310) stays" {
  owe 310
  HF_RC=1 HF_ERR="$HOLD_BEFORE" fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  [ -f "$CC_PANE_CLOSE_QUEUE_DIR/recycle-310.json" ]
  [[ "$output" != *"owed recycle row"* ]] || { echo "$output"; false; }
}

@test "CONTROL: CC_LRH_OWED_ROW_SPEND=off leaves the owed row for the drainer" {
  owe 31
  CC_LRH_OWED_ROW_SPEND=off HF_RC=1 HF_ERR="$HOLD_BEFORE" fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  [ -f "$CC_PANE_CLOSE_QUEUE_DIR/recycle-31.json" ]
}
