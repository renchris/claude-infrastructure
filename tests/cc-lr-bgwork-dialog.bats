#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2016  # each @test is its own subshell; per-test exports are the intent
# The census names the bg-work modal: a HOLD plus one page, never a wait (lr-wake 2026-10-18, Wave G).
#
# Pane 350 (f06b5e9b) sat at Claude Code's exit-time "Background work is running" modal through
# three 3600 s waits and nobody was told: the modal hides the composer, cc_tui_composer fails, and
# bin/cc-lr and lr-upgrade.sh read the row `composer-unknown`, which every caller waits out.
# WHAT IS PINNED:
#   · the screen tests/fixtures/lr-recon/screens/bgwork-dialog-2.1.284.txt plans hold:bg-work-dialog,
#     act hold, even with --until-idle (it never ends by itself);
#   · it pages once per pane and session, however many plans meet it;
#   · an unreadable box with no modal is still composer-unknown (CONTROL);
#   · lr-upgrade's verdict class for a bg-work hold is `hold` (terminal held-bgwork), not `wait`.
# [RED] cases fail on the tree before the fix.
#
# Hermetic: the registry, stores, `ps`, cc-tui and the pager are fixtures; no kitty is reached.

setup() {
  command -v jq >/dev/null || skip "jq required"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_FIRE_CAPACITY_GATE=off CC_ADMIT_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json" CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  CCLR="$REPO/bin/cc-lr"
  SCREEN="$REPO/tests/fixtures/lr-recon/screens/bgwork-dialog-2.1.284.txt"
  # A stub cc-tui: window 401's box is unreadable and its screen is the modal; 402's box is
  # unreadable and its screen is plain output.
  TUI="$BATS_TEST_TMPDIR/tui.sh"
  cat > "$TUI" <<EOF
cc_tui_composer() { return 1; }
cc_tui_screen() { case "\$1" in 401) cat "$SCREEN" ;; *) printf 'some output\n' ;; esac; }
EOF
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
  export LR_PAGE_ONCE_BIN="$STUBS/lr-page"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/pages.log"\necho "lr-page: verdict=posted"\n' "$BATS_TEST_TMPDIR" > "$LR_PAGE_ONCE_BIN"
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
  P_MODAL=aaaa0401; P_UNREAD=aaaa0402
}
pdisp() { printf '%s\n' "$output" | awk -v s="$1" '$2 == s { print $3 }'; }
pages() { [ -f "$BATS_TEST_TMPDIR/pages.log" ] && wc -l < "$BATS_TEST_TMPDIR/pages.log" | tr -d ' ' || echo 0; }

@test "1 [RED] plan: the bgwork-dialog-2.1.284 screen is hold:bg-work-dialog, never a wait" {
  run bash "$CCLR" plan --from next3 --to next2 --until-idle 600
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(pdisp "$P_MODAL")" = hold:bg-work-dialog ] || { echo "$output"; false; }
  run bash "$CCLR" plan --from next3 --to next2 --until-idle 600 --json
  [ "$(printf '%s' "$output" | jq -r --arg s "$P_MODAL" '.rows[] | select(.sid | startswith($s)) | .act')" = hold ] || { echo "$output"; false; }
}

@test "2 [RED] plan: the modal pages once per pane and session, however many plans meet it" {
  run bash "$CCLR" plan --from next3 --to next2 --until-idle 600
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(pages)" = 1 ] || { cat "$BATS_TEST_TMPDIR/pages.log"; false; }
  grep -q "pane 401 ${P_MODAL}" "$BATS_TEST_TMPDIR/pages.log"
  run bash "$CCLR" plan --from next3 --to next2 --until-idle 600
  run bash "$CCLR" plan --from next3 --to next2
  [ "$(pages)" = 1 ] || { cat "$BATS_TEST_TMPDIR/pages.log"; false; }
}

@test "3 CONTROL plan: an unreadable box with no modal on screen is still composer-unknown, waited" {
  run bash "$CCLR" plan --from next3 --to next2 --until-idle 600
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(pdisp "$P_UNREAD")" = wait:composer-unknown ] || { echo "$output"; false; }
}

@test "4 [RED] lr-upgrade: a bg-work hold is the hold class (terminal held-bgwork), not a wait" {
  run bash -c '. "$1"; lru_class_of skipped "relaunch held: (held: bgwork) the modal is up"; lru_class_of skipped bg-work-dialog; lru_class_of skipped "(held: busy) mid-turn"' _ "$REPO/scripts/limit-recover/lr-upgrade.sh"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$(printf 'hold\nhold\nwait')" ] || { echo "$output"; false; }
}

@test "5 [RED] lr-upgrade census: the modal reads bg-work-dialog, which is not waitable" {
  run bash -c '. "$1"; lru_unreadable_disp 401; echo; lru_unreadable_disp 402; echo; lru_switch_waitable bg-work-dialog && echo waitable || echo hold' _ "$REPO/scripts/limit-recover/lr-upgrade.sh"
  [ "$output" = "$(printf 'bg-work-dialog\ncomposer-unknown\nhold')" ] || { echo "$output"; false; }
}
