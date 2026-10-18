#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# The move lane carries a draft instead of holding it (operator request 2026-10-18).
#
# Until then `cc-lr move` planned every composer-occupied session hold:draft ("drafts are not
# carried") and lr-handoff's precheck refused a held composer (rc 6), while `cc-lr switch` and the
# transplanted recycle already carried drafts. WHAT IS PINNED:
#   · the plan gives such a row disposition `draft`, act move; LR_MOVE_CARRY_DRAFT=off restores hold:draft;
#   · the worker hands a stale real draft to the recycle's carry (LRH_CARRY_DRAFT=1, CC_RECYCLE_DRAFT_WAIT=0,
#     HF_RCY_CARRY_STALE=1), and lr-handoff's precheck lets HELD:draft through only with that opt-in;
#   · a [Pasted text #N] block (content only in the session's memory) keeps HELD:draft, untouched.
# [RED] cases fail on the tree before the carry.
#
# Hermetic: the registry, stores, `ps`, cc-tui and lr-handoff are fixtures; no kitty is reached.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  # Seams $HOME does not redirect (an absolute /tmp default, a bare name off PATH): absent paths, so
  # the sensors fail open on the fixture instead of reading the operator's live state.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json" CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  # A stub cc-tui: the box of window N is the file composer-N, read space-stripped as the real one is.
  TUI="$BATS_TEST_TMPDIR/tui.sh"
  cat > "$TUI" <<EOF
cc_tui_composer() { [ -f "$BATS_TEST_TMPDIR/composer-\$1" ] || return 1; tr -d '[:space:]' < "$BATS_TEST_TMPDIR/composer-\$1"; }
cc_tui_composer_text() { cat "$BATS_TEST_TMPDIR/composer-\$1" 2>/dev/null; }
cc_tui_clear() { echo "\$1" >> "$BATS_TEST_TMPDIR/cleared.log"; : > "$BATS_TEST_TMPDIR/composer-\$1"; }
EOF
}
teardown() { [ -z "${MVF_PIDS:-}" ] || mvf_teardown; }

# ── the plan (bin/cc-lr cl_move_rows) ─────────────────────────────────────────────────────────
plan_world() {
  CCLR="$REPO/bin/cc-lr"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"
  export LRU_STATE="$HOME/.reso/limit-recover"; mkdir -p "$LRU_STATE"
  export LR_STATE_DIR="$LRU_STATE"
  export LRU_REG_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$LRU_REG_DIR"
  export LRU_CFG_ROOT="$HOME"
  export LRU_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.txt"; : > "$LRU_PS_SNAPSHOT"
  export LRU_COMPOSER=on LRU_TUI_LIB="$TUI" LRU_SELF_SID=""
  export LRU_LR_LIB="$BATS_TEST_TMPDIR/absent-lr-lib.sh"
  STUBS="$BATS_TEST_TMPDIR/stubs"; mkdir -p "$STUBS"
  export LRU_NOTIFY_BIN="$STUBS/cc-notify"; printf '#!/bin/bash\nexit 0\n' > "$LRU_NOTIFY_BIN"
  export LRU_SA_PROBE="$STUBS/sa-probe"; printf '#!/bin/bash\necho "live_subagents: 0"\n' > "$LRU_SA_PROBE"
  printf '#!/bin/bash\nexit 0\n' > "$STUBS/launchctl"
  export CC_ACCOUNTS_BIN="$STUBS/claude-accounts"; printf '#!/bin/bash\nprintf "next2 0.9\\nnext3 0.4\\n"\n' > "$CC_ACCOUNTS_BIN"
  chmod +x "$STUBS/"*
  export PATH="$STUBS:$PATH" CC_LR_UPGRADE_BIN="$REPO/scripts/limit-recover/lr-upgrade.sh" CC_PANE_ID=999 CC_LR_MOVE_POLL_S=0
  unset CLAUDE_CODE_SESSION_ID ITERM_SESSION_ID KITTY_WINDOW_ID
  local bin="/opt/cc/.claude-280/node_modules/.bin/claude" lst="Tue Sep 22 06:47:13 2026" pane sid pid=50001 tx
  for pane in 401 402; do
    sid="aaaa0${pane}-0000-4000-8000-000000000001"; pid=$((pid + 1))
    printf '{"paneUUID":"%s","pid":%d,"session_id":"%s","account":"claude-tertiary","cwd":"%s","lstart":"%s"}\n' \
      "$pane" "$pid" "$sid" "$BATS_TEST_TMPDIR" "$lst" > "$LRU_REG_DIR/$pane.json"
    printf '%d 1 %s %s --model claude-opus-5-5\n' "$pid" "$lst" "$bin" >> "$LRU_PS_SNAPSHOT"
    tx="$HOME/.claude-tertiary/projects/-x/$sid.jsonl"; mkdir -p "$(dirname "$tx")"
    printf '%s\n' '{"type":"assistant","message":{"stop_reason":"end_turn","content":[{"type":"text","text":"idle"}]}}' > "$tx"
  done
  P_DRAFT=aaaa0401; P_EMPTY=aaaa0402
  printf 'please also check the reaper\n' > "$BATS_TEST_TMPDIR/composer-401"
  : > "$BATS_TEST_TMPDIR/composer-402"
}
pdisp() { printf '%s\n' "$output" | awk -v s="$1" '$2 == s { print $3 }'; }

@test "1a [RED] plan: an idle session with a draft is a move with disposition draft, never hold:draft" {
  plan_world
  run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(pdisp "$P_DRAFT")" = draft ] || { echo "$output"; false; }
  [ "$(pdisp "$P_EMPTY")" = move ] || { echo "$output"; false; }
  [[ "$output" == *"2 to move · 0 waiting · 0 held"* ]] || { echo "$output"; false; }
  run bash "$CCLR" plan --from next3 --to next2 --json
  [ "$(printf '%s' "$output" | jq -r '.rows[] | select(.disposition == "draft") | .act')" = move ] || { echo "$output"; false; }
}

@test "5a CONTROL plan: LR_MOVE_CARRY_DRAFT=off: the draft row is hold:draft, exactly as before" {
  plan_world
  LR_MOVE_CARRY_DRAFT=off run bash "$CCLR" plan --from next3 --to next2
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(pdisp "$P_DRAFT")" = hold:draft ] || { echo "$output"; false; }
  [[ "$output" == *"1 to move · 0 waiting · 1 held"* ]] || { echo "$output"; false; }
}

# ── the worker (scripts/limit-recover/lr-move-worker.sh) ──────────────────────────────────────
worker_world() {
  # shellcheck source=/dev/null
  . "$REPO/tests/helpers/lr-move-fixture.sh"
  mvf_setup
  mvf_handoff_stub
  # The fixture's lr-handoff stand-in, behind a recorder of the three carry variables.
  mv "$LR_MOVE_HANDOFF_BIN" "$STUBS/lr-handoff.real"
  cat > "$LR_MOVE_HANDOFF_BIN" <<EOF
#!/bin/bash
printf 'carry=%s wait=%s stale=%s\n' "\${LRH_CARRY_DRAFT:-}" "\${CC_RECYCLE_DRAFT_WAIT:-}" "\${HF_RCY_CARRY_STALE:-}" >> "\$STUB_LOG/carry.log"
exec "$STUBS/lr-handoff.real" "\$@"
EOF
  chmod +x "$LR_MOVE_HANDOFF_BIN"
  export LR_MOVE_TUI_LIB="$TUI" LR_HID_IDLE_S=999
  SID="cccc3333-0000-4000-8000-000000000001"; PANE=51
  mvf_session "$PANE" "$SID"
  mvf_plan w1 move "$PANE:$SID"
  jq -c '.rows[0].disposition = "draft"' "$BDIR/plan.json" > "$BDIR/plan.t" && mv "$BDIR/plan.t" "$BDIR/plan.json"
  printf '{"admitted":true,"target":"next3","target_auth":"ok"}\n' > "$BDIR/admit.json"
  CLAIMS="$LR_STATE_DIR/runs/by-sid"
}
worker() {
  bash "$LRD/lr-move-worker.sh" w1 "$SID" > "$BATS_TEST_TMPDIR/worker.out" 2>&1 3>&- &
  WPID=$!
  mkdir -p "$CLAIMS/$SID.active"
  bash -c '. "$1/lr-lib.sh"; lr_claim_stamp "$2" "$3" "$4" lr-move-worker "$5"' _ "$LRD" "$CLAIMS/$SID.active" "$SID" "$WPID" "$PANE"
  WRC=0; wait "$WPID" || WRC=$?
}
res() { jq -r ".$1" "$BDIR/$SID.json"; }

@test "1b [RED] worker: a stale real draft is moved, and the actuator gets the carry opt-in" {
  worker_world
  printf 'please also check the reaper\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  worker
  [ "$(res verdict)" = MOVED ] || { cat "$BDIR/$SID.json" "$BATS_TEST_TMPDIR/worker.out"; false; }
  [ "$(cat "$STUB_LOG/carry.log")" = "carry=1 wait=0 stale=1" ] || { cat "$STUB_LOG/carry.log"; false; }
  grep -q '"stage":"draft-carry"' "$BDIR/$SID.events.jsonl"
  # the worker itself never clears a real draft: the recycle's carry saves it first
  [ ! -e "$BATS_TEST_TMPDIR/cleared.log" ]
}

@test "1c CONTROL worker: a plain move row carries no opt-in" {
  worker_world
  jq -c '.rows[0].disposition = "move"' "$BDIR/plan.json" > "$BDIR/plan.t" && mv "$BDIR/plan.t" "$BDIR/plan.json"
  printf 'please also check the reaper\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  worker
  [ "$(cat "$STUB_LOG/carry.log")" = "carry= wait= stale=" ] || { cat "$STUB_LOG/carry.log"; false; }
}

@test "4 [RED] worker: a [Pasted text #N] block is HELD:draft with the pasted-block reason, nothing touched" {
  worker_world
  printf '[Pasted text #1 +20 lines] fix this\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  worker
  [ "$WRC" -eq 3 ]
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == "HELD:draft — its box holds a pasted block"* ]] || { res reason; false; }
  [ ! -s "$STUB_LOG/typers.log" ]
  [ ! -e "$BATS_TEST_TMPDIR/cleared.log" ]
  [ -f "$SRC/projects/-x/$SID.jsonl" ]
}

@test "2 [RED] worker: stale junk (a leaked terminal reply) is cleared and the row moves with no carry" {
  worker_world
  printf '_Ga=d,d=I,i=7110,q=225h\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  worker
  [ "$(res verdict)" = MOVED ] || { cat "$BDIR/$SID.json" "$BATS_TEST_TMPDIR/worker.out"; false; }
  [ "$(cat "$BATS_TEST_TMPDIR/cleared.log")" = "$PANE" ]
  [ "$(cat "$STUB_LOG/carry.log")" = "carry= wait= stale=" ] || { cat "$STUB_LOG/carry.log"; false; }
  grep -q '"stage":"draft-discarded"' "$BDIR/$SID.events.jsonl"
  grep -q 'class=terminal-reply' "$HOME/.claude/logs/composer-discarded.log"
}

# A box somebody is typing into: rewritten every 0.3 s, by rename so no read sees it empty.
typing() {
  ( i=0; f="$BATS_TEST_TMPDIR/composer-$PANE"
    while :; do i=$((i + 1)); printf 'still typing %s\n' "$i" > "$f.t"; mv -f "$f.t" "$f"; sleep 0.3; done ) 3>&- &
  MVF_PIDS="$MVF_PIDS $!"
}
wstart() {
  bash "$LRD/lr-move-worker.sh" w1 "$SID" > "$BATS_TEST_TMPDIR/worker.out" 2>&1 3>&- &
  WPID=$!
  mkdir -p "$CLAIMS/$SID.active"
  bash -c '. "$1/lr-lib.sh"; lr_claim_stamp "$2" "$3" "$4" lr-move-worker "$5"' _ "$LRD" "$CLAIMS/$SID.active" "$SID" "$WPID" "$PANE"
}
await_stage() { # <stage> → 0 once the worker logged it (bounded poll, load-tolerant)
  local i=0
  until grep -q "\"stage\":\"$1\"" "$BDIR/$SID.events.jsonl" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 600 ] || { cat "$BDIR/$SID.events.jsonl" 2>/dev/null; return 1; }
    sleep 0.2
  done
}

@test "3 [RED] worker: a box that changed seconds ago waits, never moved and never HELD while it is still changing" {
  worker_world
  export LR_HID_IDLE_S=10 LR_MOVE_DRAFT_POLL_S=0.2
  typing
  wstart
  await_stage draft-wait
  [ ! -e "$BDIR/$SID.json" ] || { cat "$BDIR/$SID.json"; false; }
  [ ! -s "$STUB_LOG/typers.log" ]
  : > "$BDIR/abort"
  WRC=0; wait "$WPID" || WRC=$?
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == "aborted while its draft was still changing"* ]] || { res reason; false; }
  [ ! -s "$STUB_LOG/typers.log" ]
  [ ! -e "$BATS_TEST_TMPDIR/cleared.log" ]
}

@test "3b worker: a box still changing at LR_MOVE_DRAFT_WAIT_S is HELD:draft, nothing touched" {
  worker_world
  export LR_HID_IDLE_S=10 LR_MOVE_DRAFT_POLL_S=0.2 LR_MOVE_DRAFT_WAIT_S=2
  typing
  wstart
  WRC=0; wait "$WPID" || WRC=$?
  [ "$(res verdict)" = NOTMOVED ]
  [[ "$(res reason)" == "HELD:draft — its box was still changing after 2s"* ]] || { res reason; false; }
  [ ! -s "$STUB_LOG/typers.log" ]
}

@test "3c [RED] worker: input not idle, but the box sits unchanged LR_MOVE_DRAFT_STALE_S, so it moves with the carry" {
  worker_world
  export LR_HID_IDLE_S=0 LR_MOVE_DRAFT_POLL_S=0.2 LR_MOVE_DRAFT_STALE_S=1
  printf 'please also check the reaper\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  worker
  [ "$(res verdict)" = MOVED ] || { cat "$BDIR/$SID.json" "$BATS_TEST_TMPDIR/worker.out"; false; }
  grep -q '"stage":"draft-wait"' "$BDIR/$SID.events.jsonl"
  [ "$(cat "$STUB_LOG/carry.log")" = "carry=1 wait=0 stale=1" ] || { cat "$STUB_LOG/carry.log"; false; }
}

@test "5b worker: LR_MOVE_CARRY_DRAFT=off passes no opt-in, so the precheck holds the draft as before" {
  worker_world
  printf 'please also check the reaper\n' > "$BATS_TEST_TMPDIR/composer-$PANE"
  LR_MOVE_CARRY_DRAFT=off worker
  [ "$(cat "$STUB_LOG/carry.log")" = "carry= wait= stale=" ] || { cat "$STUB_LOG/carry.log"; false; }
}

# ── lr-handoff's precheck ─────────────────────────────────────────────────────────────────────
lrh_world() {
  HANDOFF="$REPO/scripts/limit-recover/lr-handoff.sh"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export CC_FIRE_HEADROOM_GATE=off CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit" CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json" CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  export IT2_BIN="$BATS_TEST_TMPDIR/absent-it2" IT2_WRAPPER_NO_KITTY=1 LRH_LIVE_PARSER_CHECK=off LRH_PRECHECK=on
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  unset LR_PLACED_BY LR_ASSIGN_ID LR_ADMIT_TOKEN_PATH LR_PRESEED_DONE KITTY_WINDOW_ID LRH_CARRY_DRAFT
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export TX_LOG="$BATS_TEST_TMPDIR/tx.log"; : > "$TX_LOG"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  local lrd="$HOME/.claude/scripts/limit-recover"
  mkdir -p "$lrd" "$HOME/.claude/projects" "$HOME/.claude-next/projects/-x-y" "$HOME/.claude-secondary/projects" "$BATS_TEST_TMPDIR/plain"
  # The probe holds HELD:draft (its last read, rc 3), after its subagent and shell-root lines.
  cat > "$STUB/handoff-fire.sh" <<'STUB'
#!/bin/bash
case " $* " in
  *" --probe-recycle-preconditions "*)
    printf 'live_subagents: 0\nshell_root: yes\nfocused: no\ncomposer: held:pleasealsocheck\nverdict: HELD:draft\n'; exit 3 ;;
esac
exit 0
STUB
  printf '#!/bin/bash\nexit 0\n' > "$STUB/cc-notify"
  printf '#!/bin/bash\nexit 0\n' > "$STUB/cursor"
  chmod +x "$STUB/"*
  export CC_HANDOFF_FIRE_BIN="$STUB/handoff-fire.sh" CC_NOTIFY_BIN="$STUB/cc-notify" CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  cat > "$lrd/lr-audit.py" <<'PY'
import sys, json, os
a = sys.argv
out = a[a.index('--json') + 1]
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump({"session_dir": "/nonexistent", "transcript_sha256": "deadbeef", "counts": {"gaps": 0, "waiting": 0}}, open(out, "w"))
PY
  printf '#!/bin/bash\nexit 0\n' > "$lrd/lr-preseed-env.sh"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "${TX_LOG:?}"\nprintf "{\\"ok\\":true,\\"target_transcript\\":\\"/dev/null\\"}\\n"\n' > "$lrd/lr-transplant.sh"
  printf '#!/bin/bash\nexit 0\n' > "$lrd/lr-fire-resume.sh"
  printf '#!/bin/bash\necho "PASS A1"; echo "FAST-PATH PROMPT — x"; exit 0\n' > "$lrd/lr-ingest-verify.sh"
  chmod +x "$lrd/"*.sh
  LSID="0000cccc-0000-4000-8000-00000000beef"
  printf '{"session_id":"%s"}\n' "$LSID" > "$CC_REGISTRY_DIR/31.json"
  printf '{"type":"assistant","timestamp":"2026-09-29T10:00:00.000Z","message":{"role":"assistant","content":[{"type":"text","text":"working"}]}}\n' \
    > "$HOME/.claude-next/projects/-x-y/$LSID.jsonl"
}
lrh_fire() { # the voluntary move of a healthy pane, on account evidence (lr-handoff-flags' path)
  local f="$BATS_TEST_TMPDIR/next.5h.json"
  printf '{"status":"rejected","scope":"5h","resets_at":%s}\n' "$(( $(date +%s) + 7200 ))" > "$f"
  run env PATH="$STUB:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" "$@" \
      "$HANDOFF" --sid "$LSID" --target next2 --config-dir "$HOME/.claude-next" \
      --cwd "$BATS_TEST_TMPDIR/plain" --launch --in-place --source-pane 31 --voluntary --account-evidence "$f"
}

@test "1d [RED] lr-handoff: a held draft with LRH_CARRY_DRAFT=1 passes the precheck and reaches the transplant" {
  lrh_world
  lrh_fire LRH_CARRY_DRAFT=1
  [[ "$output" == *"HELD:draft, and the caller vouches the box is stale (LRH_CARRY_DRAFT=1)"* ]] || { echo "status=$status $output"; false; }
  [[ "$output" != *"PRECHECK HELD:draft"* ]] || { echo "$output"; false; }
  [ -s "$TX_LOG" ] || { echo "status=$status $output"; false; }
}

@test "1e CONTROL lr-handoff: the same held draft without the opt-in refuses rc 6, nothing transplanted" {
  lrh_world
  lrh_fire
  [ "$status" -eq 6 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"PRECHECK HELD:draft"* ]] || { echo "$output"; false; }
  [ ! -s "$TX_LOG" ]
}

# ── handoff-fire's carry eligibility (hf_rcy_carry_eligible, extracted) ───────────────────────
# A focused live source is refused as mid-typing unless the move worker vouches the box is stale.
carry_eligible() { # [env…] → rc of hf_rcy_carry_eligible for a focused, live, transplanted remote source
  local units="$BATS_TEST_TMPDIR/carry-units.sh" f
  for f in hf_rcy_carry_libs hf_rcy_carry_retired hf_rcy_carry_eligible; do
    sed -n "/^$f() {/,/^}/p" "$REPO/scripts/handoff-fire.sh"
  done > "$units"
  grep -q '^hf_rcy_carry_eligible() {' "$units"
  run env "$@" HF_TUI_LIB="$TUI" HF_CARRY_LIB="$REPO/scripts/lib/composer-carry.sh" bash -c '
    . "$1"; hf_pane_focused() { echo yes; }
    SID=77 RCY_REMOTE=1 RCY_TRANSPLANTED_SOURCE=1 RESUME_LAUNCHER=/x/launcher.sh RCY_HUSK=0 HF_TS_TOMBSTONE=""
    hf_rcy_carry_eligible; rc=$?; echo "why=$HF_RCY_CARRY_WHY"; exit "$rc"' _ "$units"
}

@test "6 [RED] handoff-fire: HF_RCY_CARRY_STALE=1 lifts the focus refusal for a stale box" {
  carry_eligible HF_RCY_CARRY_STALE=1
  [ "$status" -eq 0 ] || { echo "status=$status $output"; false; }
}

@test "6b CONTROL handoff-fire: without the vouch a focused live source is still refused as mid-typing" {
  carry_eligible
  [ "$status" -eq 1 ] || { echo "status=$status $output"; false; }
  [[ "$output" == *"why=the source is live and focused"* ]] || { echo "$output"; false; }
}
