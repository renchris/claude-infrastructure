#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# A session on a SERVER-REJECTED account must not be held for reasons that only protect a healthy
# source, and a move whose exit is cancelled must leave the source usable.
#
# THE INCIDENT: 2026-10-13 ~01:45-03:25Z, rotating next3 (weekly limit rejected on the wire) to next2.
#   1  pane 297 (ab512c88): the harness ended its turn at the Stop-hook block cap and paused its
#      /goal. Idle for 3+ hours, yet `cc-lr plan` and `cc-lr move` said hold:mid-turn.
#   2  pane 297 again, hold:goal-live; pane 113 (14233392), HELD:busy 87 s after a Workflow agent's
#      <task-notification> landed behind its limit error.
#   3  pane 12 (c56c729c): confirm retired the source, /exit raised the background-work dialog, the
#      watcher answered Stay, and `--phase unconfirm` refused stub-present over the /exit's own
#      three local-command records. fold-stub refuses while the source lives: no undo.
#
# EVERY FIXTURE IS THE REAL ARTIFACT, projected to the fields the readers use and with prompt text
# elided (tests/fixtures/lr-dead-source-holds/): the pane-297 transcript tail, the pane-113 records
# from its limit error on, the account fact the reconciler held for next3, and the stub pane 12
# wrote. Timestamps the rules compare against the clock are re-based to the age they had.
#
# Hermetic: the registry, every store and `ps` are fixtures (lr-upgrade's seams), a holder is a real
# `sleep`, and nothing here can reach a live pane.

bats_require_minimum_version 1.5.0

setup() {
  command -v jq >/dev/null || skip "jq required"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FX="$REPO/tests/fixtures/lr-dead-source-holds"
  LRU="$REPO/scripts/limit-recover/lr-upgrade.sh"
  LRT="$REPO/scripts/limit-recover/lr-transplant.sh"
  HF="$REPO/scripts/handoff-fire.sh"
  CCLR="$REPO/bin/cc-lr"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE/recon/facts" "$LRU_STATE/locks"
  export LR_STATE_DIR="$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$HOME"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_COMPOSER=off LRU_SELF_SID=""
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"
  printf '#!/bin/bash\nexit 0\n' > "$LRU_NOTIFY_BIN"; chmod +x "$LRU_NOTIFY_BIN"
  export LRU_SA_PROBE="$STUBS/sa-probe"
  printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"; chmod +x "$LRU_SA_PROBE"
  printf '#!/bin/bash\nexit 0\n' > "$STUBS/launchctl"; chmod +x "$STUBS/launchctl"
  export CC_ACCOUNTS_BIN="$STUBS/claude-accounts"
  printf '#!/bin/bash\nprintf "next2 0.9\\nnext3 0.4\\n"\n' > "$CC_ACCOUNTS_BIN"; chmod +x "$CC_ACCOUNTS_BIN"
  export PATH="$STUBS:$PATH"
  export CC_LR_UPGRADE_BIN="$LRU" CC_PANE_ID=999 CC_LR_MOVE_POLL_S=0
  export CC_ACCOUNT_MAP="$REPO/lib/account-map.generated.sh"
  export CC_GOAL_SCAN_DIR="$BATS_TEST_TMPDIR/goal-scan"
  # Sealed: handoff-fire's absolute /tmp defaults (an absent path fails open in both sensors).
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/handoff-account-sweep.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/claude-accounts-heal-"
  unset CLAUDE_CODE_SESSION_ID ITERM_SESSION_ID KITTY_WINDOW_ID LR_DEAD_SOURCE_RELEASE LR_RECON_ROOT
  BIN="/opt/cc/.claude-293/node_modules/.bin/claude"; LST="Tue Sep 22 06:47:13 2026"
  S297=ab512c88-0000-4000-8000-000000000297
  STORE="$HOME/.claude-tertiary/projects/-x"; mkdir -p "$STORE"
  HOLDER_PIDS=""
}

teardown() {
  local p
  for p in $HOLDER_PIDS; do kill "$p" 2>/dev/null || true; done
}

# pane297 → the registry row, the ps row and the REAL transcript tail of the goal-paused session
pane297() {
  printf '{"paneUUID":"297","pid":50297,"session_id":"%s","account":"claude-tertiary","cwd":"%s","lstart":"%s"}\n' \
    "$S297" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/297.json"
  printf '50297 1 %s %s --model claude-opus-5-5 --effort high\n' "$LST" "$BIN" >> "$LRU_PS_SNAPSHOT"
  cp "$FX/block-cap-tail.2.1.293.jsonl" "$STORE/$S297.jsonl"
}
# rejected <acct> → the REAL next3.7d fact, re-based: observed 10 minutes ago, resets in 10 hours
rejected() {
  jq -c --arg a "$1" --argjson now "$(date +%s)" '.acct = $a | .observed_at = ($now - 600) | .resets_at = ($now + 36000)' \
    "$FX/next3.7d.fact.json" > "$LRU_STATE/recon/facts/$1.7d.json"
}
disp() { printf '%s\n' "$output" | awk -v s="${1:0:8}" '$2 == s { print $3 }'; }
# load <file> <function>… → source those functions out of a script, never the script
load_fns() {
  local src="$1" f out="$BATS_TEST_TMPDIR/fns.$RANDOM.sh"; shift
  for f in "$@"; do
    awk -v f="$f" '$0 ~ "^" f "\\(\\) \\{" { on = 1 } on { print } on && /^}/ { exit }' "$src" >> "$out"
  done
  # shellcheck disable=SC1090
  . "$out"
}

# ── 1. A TURN THE HARNESS ENDED AT ITS BLOCK CAP IS AT REST ────────────────────────────────────────

@test "1a [RED] the pane-297 tail (block-cap override, goal paused) is at rest for both at-rest rules" {
  load_fns "$LRU" lru_at_rest
  load_fns "$HF" hf_transcript_at_rest
  run lru_at_rest "$FX/block-cap-tail.2.1.293.jsonl"
  [ "$status" -eq 0 ] || { echo "lru_at_rest rc=$status (1 = in flight)"; false; }
  run hf_transcript_at_rest "$FX/block-cap-tail.2.1.293.jsonl"
  [ "$status" -eq 0 ] || { echo "hf_transcript_at_rest rc=$status (1 = in flight)"; false; }
}

@test "1b a Stop-hook block with NO override after it is still a turn in flight, and so is a prompt typed after the override" {
  load_fns "$LRU" lru_at_rest
  load_fns "$HF" hf_transcript_at_rest
  # the same tail cut before the harness's override: the hook fed back and the model is working
  jq -c 'select(.type != "system" or .subtype != "informational")' "$FX/block-cap-tail.2.1.293.jsonl" > "$BATS_TEST_TMPDIR/blocked.jsonl"
  run lru_at_rest "$BATS_TEST_TMPDIR/blocked.jsonl"; [ "$status" -eq 1 ]
  run hf_transcript_at_rest "$BATS_TEST_TMPDIR/blocked.jsonl"; [ "$status" -eq 1 ]
  cp "$FX/block-cap-tail.2.1.293.jsonl" "$BATS_TEST_TMPDIR/typed.jsonl"
  printf '%s\n' '{"type":"user","isSidechain":false,"message":{"role":"user","content":"continue"}}' >> "$BATS_TEST_TMPDIR/typed.jsonl"
  run lru_at_rest "$BATS_TEST_TMPDIR/typed.jsonl"; [ "$status" -eq 1 ]
  run hf_transcript_at_rest "$BATS_TEST_TMPDIR/typed.jsonl"; [ "$status" -eq 1 ]
  # a sidechain or an assistant's prose carrying the sentence is not the harness's record
  jq -c 'if .type == "system" and .subtype == "informational" then .isSidechain = true else . end' \
    "$FX/block-cap-tail.2.1.293.jsonl" > "$BATS_TEST_TMPDIR/side.jsonl"
  run lru_at_rest "$BATS_TEST_TMPDIR/side.jsonl"; [ "$status" -eq 1 ]
}

@test "1c [RED] the census no longer calls that session mid-turn: on a healthy source it is held for its live goal" {
  pane297
  run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(disp "$S297")" = hold:goal-live ] || { echo "$output"; false; }
}

# ── 2. HOLDS THAT ONLY PROTECT A HEALTHY SOURCE ────────────────────────────────────────────────────

@test "2a [RED] the goal hold is released when the fact ledger says the source account is rejected" {
  pane297; rejected next3
  run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(disp "$S297")" = move ] || { echo "$output"; false; }
}

@test "2b the goal hold stands for a healthy source: no fact, a fact for another account, a contradicted or expired fact, or the kill switch" {
  pane297
  rejected next2
  run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S297")" = hold:goal-live ] || { echo "another account's fact released it: $output"; false; }
  rm -f "$LRU_STATE/recon/facts/next2.7d.json"
  rejected next3
  jq -c '.contradicted = true' "$LRU_STATE/recon/facts/next3.7d.json" > "$BATS_TEST_TMPDIR/f.json"
  cp "$BATS_TEST_TMPDIR/f.json" "$LRU_STATE/recon/facts/next3.7d.json"
  run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S297")" = hold:goal-live ] || { echo "a contradicted fact released it: $output"; false; }
  # the fact exactly as the ledger held it, un-rebased once its reset has passed
  jq -c --argjson now "$(date +%s)" '.resets_at = ($now - 120)' "$FX/next3.7d.fact.json" > "$LRU_STATE/recon/facts/next3.7d.json"
  run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S297")" = hold:goal-live ] || { echo "an expired fact released it: $output"; false; }
  rejected next3
  LR_DEAD_SOURCE_RELEASE=off run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S297")" = hold:goal-live ] || { echo "the kill switch did not hold: $output"; false; }
}

# ── 2b1-3. THE GOAL HOLD KEYS ON GOAL ACTIVITY, NOT ON A GOAL BEING ARMED (operator, 2026-10-18) ─────
# An actively looping goal reads at rest for ~3 s between turns (raw/E-holds.md §2.5), so activity is
# a goal record or a transcript write inside the window. The hold cases pin a 600 s window so a
# loaded box (load 100-600) cannot age a 10 s record past it before the census reads it.
# goalage <secs> → re-base pane 297's goal_status records to <secs> old; txage <secs> → its last write
goalage() {
  jq -c --argjson t "$(( $(date +%s) - $1 ))" \
    'if .type == "attachment" and .attachment.type == "goal_status" then .timestamp = ($t | todate) else . end' \
    "$FX/block-cap-tail.2.1.293.jsonl" > "$BATS_TEST_TMPDIR/g.jsonl"
  cp "$BATS_TEST_TMPDIR/g.jsonl" "$STORE/$S297.jsonl"
}
txage() { perl -e 'utime $ARGV[0], $ARGV[0], $ARGV[1] or die' "$(( $(date +%s) - $1 ))" "$STORE/$S297.jsonl"; }

@test "2b1 [RED] an armed goal at rest (last evaluation and last turn 30 min old) does not hold an idle session; always restores the old rule" {
  pane297; goalage 1800; txage 1800
  run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(disp "$S297")" = move ] || { echo "an at-rest goal held it: $output"; false; }
  CC_LR_MOVE_GOAL_HOLD=always run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S297")" = hold:goal-live ] || { echo "always did not hold an armed goal: $output"; false; }
}

@test "2b2 a goal evaluated 10 s ago holds even when the transcript's last write is 30 min old, and so does a turn inside the window" {
  pane297; goalage 10; txage 1800
  LR_MOVE_GOAL_ACTIVE_S=600 run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S297")" = hold:goal-live ] || { echo "a just-evaluated goal did not hold: $output"; false; }
  goalage 1800; txage 30
  LR_MOVE_GOAL_ACTIVE_S=600 run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S297")" = hold:goal-live ] || { echo "a turn 30 s ago did not hold: $output"; false; }
  LR_MOVE_GOAL_ACTIVE_S=1 run bash "$CCLR" plan --from next3 --to next2
  [ "$(disp "$S297")" = move ] || { echo "the window knob was not read: $output"; false; }
}

@test "2b3 CC_LR_MOVE_GOAL_HOLD=off never holds, even for an active goal" {
  pane297; goalage 10
  CC_LR_MOVE_GOAL_HOLD=off run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(disp "$S297")" = move ] || { echo "off still held it: $output"; false; }
}

# gate <account dir basename> → run the recover lane's bg-work gate over the REAL pane-113 records,
# the Workflow agent's notification re-based to the 87 s it was old when the recovery was held
gate() {
  local tx="$HOME/.$1/projects/-x/14233392-0000-4000-8000-000000000113.jsonl"
  mkdir -p "$(dirname "$tx")"
  jq -c --arg ts "$(date -u -v-87S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '87 seconds ago' +%Y-%m-%dT%H:%M:%SZ)" \
    'if .type == "user" and ((.message.content | type) == "string") and (.message.content | startswith("<task-notification>")) then .timestamp = $ts else . end' \
    "$FX/limit-then-notification.2.1.293.jsonl" > "$tx"
  load_fns "$HF" hf_transcript_at_rest hf_bg_work_kind hf_lr_script
  # hf_bg_work_gate names its helpers only when they exist: on the pre-fix tree there are none
  load_fns "$HF" hf_tx_account hf_dead_source_notification hf_bg_work_gate
  export HF_DIR="$REPO/scripts" HF_PS_SNAPSHOT="$LRU_PS_SNAPSHOT"
  GTX="$tx"
  HF_BG_HOLD=""; GRC=0
  hf_bg_work_gate "" 1 "$tx" "$tx" > "$BATS_TEST_TMPDIR/gate.out" || GRC=$?
}

@test "2c [RED] a harness notification behind the limit error does not hold a session whose account is rejected" {
  rejected next3
  gate claude-tertiary
  [ "$GRC" -eq 0 ] || { echo "rc=$GRC hold=$HF_BG_HOLD"; cat "$BATS_TEST_TMPDIR/gate.out"; false; }
  [ -z "$HF_BG_HOLD" ]
  grep -q 'limited on a rejected account (next3.7d ' "$BATS_TEST_TMPDIR/gate.out" || { cat "$BATS_TEST_TMPDIR/gate.out"; false; }
}

@test "2d the same notification still holds when the account is not rejected, and a typed prompt holds on a rejected one" {
  gate claude-tertiary
  [ "$GRC/$HF_BG_HOLD" = "3/HELD:busy" ] || { echo "no fact: rc=$GRC hold=$HF_BG_HOLD"; false; }
  rejected next2
  gate claude-tertiary
  [ "$GRC/$HF_BG_HOLD" = "3/HELD:busy" ] || { echo "another account's fact: rc=$GRC hold=$HF_BG_HOLD"; false; }
  rejected next3
  gate claude-tertiary
  [ "$GRC" -eq 0 ] || { echo "control: the rejected account did not release (rc=$GRC)"; false; }
  # the operator's own prompt after the limit — the fixture's record 6, 8 s after the first error
  jq -c 'select(.timestamp <= "2026-10-13T01:45:49.999Z")' "$FX/limit-then-notification.2.1.293.jsonl" > "$GTX"
  HF_BG_HOLD=""; GRC=0
  hf_bg_work_gate "" 1 "$GTX" "$GTX" > "$BATS_TEST_TMPDIR/gate.out" || GRC=$?
  [ "$GRC/$HF_BG_HOLD" = "3/HELD:busy" ] || { echo "a typed prompt was released: rc=$GRC hold=$HF_BG_HOLD"; false; }
}

# ── 3. A CANCELLED EXIT LEAVES THE SOURCE USABLE ───────────────────────────────────────────────────

_lstart() { TZ=UTC LC_ALL=C ps -o lstart= -p "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
# half_moved → admit + confirm by the REAL writer, a live holder on the source, then the REAL stub
half_moved() {
  T="$BATS_TEST_TMPDIR"
  SID=c56c729c-0000-4000-8000-000000000012
  mkdir -p "$T/from/projects/slug" "$T/to/projects/slug" "$T/from/sessions"
  SRC="$T/from/projects/slug/$SID.jsonl"; RET="$SRC.handed-off"; DST="$T/to/projects/slug/$SID.jsonl"
  printf '{"type":"user","uuid":"a1"}\n{"type":"assistant","uuid":"a2","message":{"stop_reason":"end_turn"}}\n' > "$SRC"
  cp "$SRC" "$T/pre.jsonl"
  bash "$LRT" --phase admit --sid "$SID" --from "$T/from" --to "$T/to" --cause voluntary >/dev/null
  bash "$LRT" --phase confirm --sid "$SID" --from "$T/from" --to "$T/to" --cause voluntary >/dev/null
  [ -f "$RET" ] && [ ! -e "$SRC" ]
  sleep 300 >/dev/null 2>&1 3>&- &
  HOLDER_PIDS="$HOLDER_PIDS $!"
  printf '{"pid":%s,"sessionId":"%s","procStart":"%s","cwd":"/tmp"}\n' "$!" "$SID" "$(_lstart "$!")" > "$T/from/sessions/s1.json"
  # what the live source wrote when /exit was typed, before the dialog the watcher answered Stay to
  cp "$FX/exit-stub.2.1.293.jsonl" "$SRC"
}

@test "3a [RED] unconfirm hands a half-moved LIVE source back: the retired transcript and the /exit stub, in order, at the live path" {
  half_moved
  run --separate-stderr bash "$LRT" --phase unconfirm --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 0 ] || { echo "rc=$status $output $stderr"; false; }
  [ ! -e "$RET" ] || { echo "the retired copy is still beside the source"; false; }
  cat "$T/pre.jsonl" "$FX/exit-stub.2.1.293.jsonl" | cmp -s - "$SRC" || { echo "the restored source is not retired ∥ stub"; false; }
  [ ! -e "$DST" ] || { echo "the target copy is still resumable"; false; }
  [ ! -e "$LR_STATE_DIR/locks/$SID.lock" ] || { echo "the lock survived"; false; }
  [ "$(printf '%s' "$output" | jq -r .folded_stub_bytes)" = "$(wc -c < "$FX/exit-stub.2.1.293.jsonl" | tr -d ' ')" ] || { echo "$output"; false; }
  local left; left="$(find "$T/from/projects/slug" -name '*unconfirm-stub*' | grep -c . || true)"
  [ "$left" -eq 0 ] || { echo "a set-aside stub was left behind"; false; }
  # the restored source is a plain live session again: the at-rest rule reads it, /exit triple skipped
  load_fns "$LRU" lru_at_rest
  run lru_at_rest "$SRC"; [ "$status" -eq 0 ]
}

@test "3b with no live source the stub still refuses stub-present and every file is byte-identical" {
  half_moved
  local p; for p in $HOLDER_PIDS; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
  local before; before="$(shasum -a 256 "$RET" "$SRC" "$DST" | cut -d' ' -f1 | tr '\n' ' ')"
  run --separate-stderr bash "$LRT" --phase unconfirm --sid "$SID" --from "$T/from" --to "$T/to"
  [ "$status" -eq 2 ] || { echo "rc=$status $output $stderr"; false; }
  [ "$(printf '%s' "$output" | jq -r .reason)" = stub-present ] || { echo "$output"; false; }
  [ "$(shasum -a 256 "$RET" "$SRC" "$DST" | cut -d' ' -f1 | tr '\n' ' ')" = "$before" ] || { echo "a refusal changed a file"; false; }
}

@test "3c [RED] the plan names the undo for a half-moved live session, never the repair-markers loop" {
  half_moved
  # the same state in a store the census reads: pane 12 on next3, its tombstone naming next2
  local st="$HOME/.claude-tertiary/projects/-x"
  cp "$SRC" "$st/$SID.jsonl"; cp "$RET" "$st/$SID.jsonl.handed-off"
  printf '{"handed_off_to":"%s","target_transcript":"x","ts":"2026-10-13T01:55:57Z","cause":"voluntary","confirm_len":1}\n' \
    "$HOME/.claude-secondary" > "$st/$SID.HANDOFF.json"
  mkdir -p "$HOME/.claude-secondary/projects"
  printf '{"paneUUID":"12","pid":50012,"session_id":"%s","account":"claude-tertiary","cwd":"%s","lstart":"%s"}\n' \
    "$SID" "$BATS_TEST_TMPDIR" "$LST" > "$LRU_REG_DIR/12.json"
  printf '50012 1 %s %s --model claude-opus-5-5 --effort high\n' "$LST" "$BIN" >> "$LRU_PS_SNAPSHOT"
  run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(disp "$SID")" = hold:half-moved ] || { echo "$output"; false; }
  [[ "$output" == *"--phase unconfirm --sid $SID --from $HOME/.claude-tertiary --to $HOME/.claude-secondary"* ]] || { echo "$output"; false; }
  [[ "$output" != *"repair-markers --sid $SID"* ]] || { echo "$output"; false; }
}
