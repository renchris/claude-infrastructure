#!/usr/bin/env bats
# What a scripted reboot keeps (2026-10-13): scripts/alarm-reboot-prep.sh records kitty's arrangement
# as a checked restore heartbeat and saves each pane's unsent prompt-box text; scripts/lib/
# reboot-drafts.sh types a saved draft back and never submits it. Every case runs under /bin/bash 3.2
# (launchd runs boot-resume.sh there). HOME is a fixture and kitty is ONE stub that answers `ls` and
# `get-text` from files and records every `send-text`, so nothing here reads or types into a live pane.

bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  S="$REPO/scripts/alarm-reboot-prep.sh"
  LIB="$REPO/scripts/lib/reboot-drafts.sh"
  HBL="$REPO/scripts/lib/restore-heartbeat.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_REBOOT_PREP_CLAUDE_TMP="$D/claude-tmp" CC_REBOOT_PREP_KITTY_SOCK_PREFIX="$D/kitty-" CC_REBOOT_PREP_SOCKS_DIR="$D/socks"
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$D/absent-repo"   # hermeticity: no live converge
  export CC_REBOOT_PREP_DIR="$D/autonomy" CC_REBOOT_PREP_DATE=2020-01-01
  export CC_REBOOT_PREP_PS=/usr/bin/true CC_REBOOT_PREP_ZPRINT=/usr/bin/true
  export CC_REBOOT_PREP_SESSIONS="$D/sessions"
  export CC_BOOTUUID_OVERRIDE=UUID-T CC_HB_PS_BIN="$BATS_TEST_DIRNAME/fixtures/hb-kitty-ps" CC_HB_LSOF_BIN=/usr/bin/true
  export CC_ROLES_DIR="$D/roles" CC_HB_MAILBOX_DIR="$D/mailbox" CC_HB_AGENT_BROWSER_DIR="$D/ab"
  mkdir -p "$CC_ROLES_DIR" "$CC_HB_MAILBOX_DIR" "$CC_HB_AGENT_BROWSER_DIR"
  export CC_CARRY_SETTLE_S=0 CC_TUI_RPC_TIMEOUT=5
  unset CC_TERM_KITTY_TO KITTY_WINDOW_ID KITTY_LISTEN_ON CC_HEARTBEAT_DIR CC_HB_SESSIONS_BIN CC_HB_NOW
  export CC_KITTY_SOCKET_BIN="$D/ksock"
  printf '#!/bin/sh\necho unix:/tmp/kitty-test\n' > "$CC_KITTY_SOCKET_BIN"; chmod +x "$CC_KITTY_SOCKET_BIN"

  # The stub kitty. `ls` prints $0.tree (fails while $0.lsfail exists); `ls --match id:N` says pane N
  # exists; `get-text` renders pane N's box from $0.d/N.box between two borders, or prints N.raw as
  # is; `send-text --from-file` appends to N.box (so a read-back sees it) and to N.typed.
  K="$D/kitty"; mkdir -p "$K.d"
  cat > "$K" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$0.log"
shift 3; cmd="$1"; shift
id=""; file=""
while [ $# -gt 0 ]; do
  case "$1" in --match) id="${2#id:}"; shift 2 ;; --from-file) file="$2"; shift 2 ;; *) shift ;; esac
done
S="$0.d"
case "$cmd" in
  ls) if [ -n "$id" ]; then printf '[{"tabs":[{"windows":[{"id":%s}]}]}]\n' "$id"
      else [ -f "$0.lsfail" ] && exit 1; cat "$0.tree"; fi ;;
  get-text)
    if [ -f "$S/$id.raw" ]; then cat "$S/$id.raw"; exit 0; fi
    [ -f "$S/$id.box" ] || exit 1
    printf ' output above\n────────────────────────────────────────\n❯ %s\n────────────────────────────────────────\n  ? for shortcuts\n' "$(cat "$S/$id.box")" ;;
  send-text) [ -n "$file" ] || exit 0; cat "$file" >> "$S/$id.box"; cat "$file" >> "$S/$id.typed" ;;
esac
SH
  chmod +x "$K"
  export CC_HB_KITTEN_BIN="$K" CC_TERM_KITTY="$K"

  KP=$$                                   # a LIVE kitty pid: this test's own process
  HBD="$CC_REBOOT_PREP_DIR/heartbeat/UUID-T/$KP"
  printf '#!/bin/sh\ncat "%s/sessions.json"\n' "$D" > "$D/sessions"; chmod +x "$D/sessions"
  echo "[$(sess s-a 11),$(sess s-b 12),$(sess s-c 13)]" > "$D/sessions.json"
  # One OS window, one tab: three session panes and a plain shell.
  printf '[{"id":6,"platform_window_id":700,"tabs":[{"layout":"splits","windows":[%s,%s,%s,%s]}]}]\n' \
    "$(kwin 11)" "$(kwin 12)" "$(kwin 13)" "$(kwin 14)" > "$K.tree"
  printf '%s' 'fix the login bug' > "$K.d/11.box"          # an unsent draft
  : > "$K.d/12.box"                                        # an empty box
  printf ' Do you want to proceed?\n ❯ 1. Yes\n   2. No\n' > "$K.d/13.raw"   # a dialog: UNKNOWN
}

sess() { # <sid> <pane>
  printf '{"session_id":"%s","kitty_pid":%s,"pid":1,"cwd":"/nonexistent/%s","account":"claude-next","paneUUID":"%s","name":"N-%s","kitty_listen_on":"unix:/tmp/kitty-test"}' \
    "$1" "$KP" "$1" "$2" "$1"
}
kwin() { printf '{"id":%s,"cwd":"/tmp/scratch-%s","cmdline":["/bin/zsh","-l"]}' "$1" "$1"; }
prep() { run /bin/bash "$S" "$@"; }
rd() { run /bin/bash -c '. "$1"; shift; "$@"' _ "$LIB" "$@"; }
sent() { grep -c ' send-text ' "$K.log" 2>/dev/null || true; }
mode() { /usr/bin/stat -f %Lp "$1"; }
draft() { # <drafts-dir> <sid> <text> — a draft as cc_carry_save writes it
  mkdir -p "$1/$2"; printf '%s' "$3" > "$1/$2/draft.txt"; : > "$1/$2/images.txt"; : > "$1/$2/unsaved.txt"
}

@test "prep records the arrangement as a heartbeat stamped with its own start epoch, tree read and checked" {
  prep
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=READY"* ]] || false
  [[ "$output" == *"1 OS window(s), 1 tab(s), 4 pane(s): 3 session(s), 1 other"* ]] || false
  printf '%s\n' "$output" | grep -q '^capture layout=ok kitty=1 degraded=0 ' || false
  # boot-resume takes the heartbeat over the alarm roster when its start is not older: they are equal.
  [ "$(cat "$HBD/hb.start")" = "$(cat "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start")" ] || false
  [ "$(jq '.[0].tabs[0].windows | length' "$HBD/hb.kitty-ls.json")" -eq 4 ] || false
  [ "$(jq length "$HBD/hb.roster.json")" -eq 3 ] || false
  [ ! -e "$HBD/hb.layout-degraded" ] || false
  [ "$(grep -c ' ls$' "$K.log")" -eq 1 ] || false            # a good tree is not asked for twice
}

@test "prep: a kitty that never answers the tree read is DEGRADED after 3 tries, marked, and still READY" {
  : > "$K.lsfail"
  prep
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"DEGRADED after 3 tries"* ]] || false
  [[ "$output" == *"plain"*"row layout"* ]] || false
  printf '%s\n' "$output" | grep -q '^capture layout=degraded kitty=1 degraded=1 ' || false
  [ "$(grep -c ' ls$' "$K.log")" -eq 3 ] || false
  grep -q 'did not answer' "$HBD/hb.layout-degraded" || false
  [[ "$output" == *"verdict=READY"* ]] || false
}

@test "prep: an older tree left on disk is not passed off as this moment's arrangement" {
  mkdir -p "$HBD"; cp "$K.tree" "$HBD/hb.kitty-ls.json"; touch -t 202001010000 "$HBD/hb.kitty-ls.json"
  : > "$K.lsfail"
  prep
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"the tree on disk is from"* ]] || false
  [ -s "$HBD/hb.layout-degraded" ] || false
}

@test "prep: a tree missing a session's pane is DEGRADED, never recorded as a partial arrangement" {
  printf '[{"id":6,"tabs":[{"layout":"splits","windows":[%s,%s]}]}]\n' "$(kwin 11)" "$(kwin 12)" > "$K.tree"
  prep
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"1 session pane(s) are not in the tree"* ]] || false
  grep -q '1 session pane' "$HBD/hb.layout-degraded" || false
}

@test "prep saves an unsent draft mode 600, counts the empty and the unreadable box, and sends no key" {
  prep
  [ "$status" -eq 0 ] || false
  DR="$CC_REBOOT_PREP_DIR/reboot-2020-01-01.drafts"
  printf '%s\n' "$output" | grep -q 'saved=1 partial=0 empty=1 unreadable=1 unread=0$' || false
  [ "$(cat "$DR/s-a/draft.txt")" = 'fix the login bug' ] || false
  [ "$(mode "$DR")" = 700 ] || false
  [ "$(mode "$DR/s-a")" = 700 ] || false
  [ "$(mode "$DR/s-a/draft.txt")" = 600 ] || false
  [ ! -e "$DR/s-b" ] && [ ! -e "$DR/s-c" ] || false
  [[ "$output" != *"fix the login bug"* ]] || false          # the text is never printed
  # READ-ONLY: every call was ls or get-text. Nothing typed, nothing cleared, nothing submitted.
  [ "$(sent)" -eq 0 ] || false
  [ "$(grep -vc -e ' ls' -e ' get-text ' "$K.log")" -eq 0 ] || false
  [ "$(cat "$K.d/11.box")" = 'fix the login bug' ] || false
}

@test "prep: a second run the same day replaces the drafts; a drafts directory over 7 days old is removed" {
  prep
  DR="$CC_REBOOT_PREP_DIR/reboot-2020-01-01.drafts"
  [ -f "$DR/s-a/draft.txt" ] || false
  OLD="$CC_REBOOT_PREP_DIR/reboot-2019-12-01"
  draft "$OLD.drafts" s-old 'an old secret'; echo 1000 > "$OLD.start"
  : > "$K.d/11.box"                                          # the operator sent it since
  prep
  [ "$status" -eq 0 ] || false
  [ ! -e "$DR" ] || false
  [ ! -e "$OLD.drafts" ] || false
}

@test "prep --dry-run writes no reboot record, prints the tree pane by pane and the draft count, stores no draft" {
  prep --dry-run
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=DRY-RUN"* ]] || false
  for f in start roster.json kalloc drafts; do [ ! -e "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.$f" ] || false; done
  [ ! -e "$CC_REBOOT_PREP_DIR/heartbeat" ] || false
  [[ "$output" == *"OS window 6: 1 tab(s)"* ]] || false
  [[ "$output" == *"pane 11  session s-a"* ]] || false
  [[ "$output" == *"pane 14  shell in /tmp/scratch-14"* ]] || false
  [[ "$output" == *"1 non-empty (counted, not stored: dry run); 1 empty; 1 unreadable"* ]] || false
  [[ "$output" != *"fix the login bug"* ]] || false
  [ "$(sent)" -eq 0 ] || false
  [ -z "$(find "$CC_REBOOT_PREP_DIR" -name draft.txt)" ] || false
  # The restore plan for that capture is the arrangement it printed: one window, 3 sessions, 1 shell.
  T="$CC_REBOOT_PREP_DIR/reboot-prep-dryrun/heartbeat/UUID-T/$KP/hb.kitty-ls.json"
  [[ "$output" == *"--desktops --restore --dry-run --tree $T"* ]] || false
  run --separate-stderr env -u CC_TERM_KITTY PATH=/usr/bin:/bin:/opt/homebrew/bin /bin/bash "$REPO/bin/cc-resume-layout.sh" \
    --desktops --restore --dry-run --tree "$T" </dev/null
  [ "$status" -eq 0 ] || false
  printf '%s\n' "$output" | grep -q '^cc-resume-layout: tree oswin=1 .* tabs=1 panes=4 claude=3 shells=1 ' || false
}

@test "heartbeat: a tick that reads a tree removes the degraded mark; one that cannot leaves it" {
  export CC_HEARTBEAT_DIR="$D/hb" CC_HB_SESSIONS_BIN="$D/sessions" CC_HB_NOW=1784800000
  H="$D/hb/UUID-T/$KP"; mkdir -p "$H"; echo why > "$H/hb.layout-degraded"
  : > "$K.lsfail"
  run /bin/bash -c '. "$1"; hb_tick' _ "$HBL"
  [ "$status" -eq 0 ] || false
  [ -f "$H/hb.layout-degraded" ] || false
  rm -f "$K.lsfail"
  run /bin/bash -c '. "$1"; hb_tick' _ "$HBL"
  [ "$status" -eq 0 ] || false
  [ ! -e "$H/hb.layout-degraded" ] || false
}

@test "put-back types the draft into an EMPTY box, never sends a CR, and deletes the draft" {
  DR="$D/reboot-x.drafts"; draft "$DR" s-a 'fix the login bug'
  : > "$K.d/51.box"
  echo 'cc-resume-layout: map sid=s-a wid=51 oswin=1' > "$D/map"
  export CC_TERM_KITTY_TO=unix:/tmp/kitty-test
  rd rd_putback "$DR" "$D/map" "$D/drafts.log" 5 0
  [ "$status" -eq 0 ] || false
  [ "$output" = 'typed=1 partial=0 kept=0 left=0' ] || false
  [ "$(cat "$K.d/51.typed")" = 'fix the login bug' ] || false
  [ "$(sent)" -eq 1 ] || false
  ! grep ' send-text ' "$K.log" | grep -qv -- '--from-file' || false   # a CR is sent without --from-file
  [ ! -e "$DR" ] || false                                    # a draft may hold a secret: gone once typed
  grep -q 'sid=s-a wid=51 rc=0 typed' "$D/drafts.log" || false
  ! grep -q 'login bug' "$D/drafts.log" || false             # the log never holds the text
}

@test "put-back skips a box that is not empty and one that reads UNKNOWN: nothing typed, the draft kept" {
  DR="$D/reboot-x.drafts"; draft "$DR" s-a 'draft one'; draft "$DR" s-c 'draft two'; draft "$DR" s-z 'never opened'
  printf '%s' 'the operator is typing' > "$K.d/51.box"
  cp "$K.d/13.raw" "$K.d/53.raw"
  printf 'cc-resume-layout: map sid=s-a wid=51 oswin=1\ncc-resume-layout: map sid=s-c wid=53 oswin=1\n' > "$D/map"
  export CC_TERM_KITTY_TO=unix:/tmp/kitty-test
  rd rd_putback "$DR" "$D/map" "$D/drafts.log" 1 0
  [ "$status" -eq 0 ] || false
  [ "$output" = 'typed=0 partial=0 kept=2 left=1' ] || false
  [ "$(sent)" -eq 0 ] || false
  [ "$(cat "$K.d/51.box")" = 'the operator is typing' ] || false
  [ "$(cat "$DR/s-a/draft.txt")" = 'draft one' ] && [ "$(cat "$DR/s-c/draft.txt")" = 'draft two' ] || false
  [ "$(grep -c 'rc=1 kept' "$D/drafts.log")" -eq 2 ] || false
}

@test "put-back refuses a saved draft holding a control byte before any call to kitty" {
  DR="$D/reboot-x.drafts"; draft "$DR" s-a 'placeholder'
  printf 'rm -rf x\rnow' > "$DR/s-a/draft.txt"
  : > "$K.d/51.box"
  echo 'cc-resume-layout: map sid=s-a wid=51 oswin=1' > "$D/map"
  export CC_TERM_KITTY_TO=unix:/tmp/kitty-test
  rd rd_putback "$DR" "$D/map" "$D/drafts.log" 5 0
  [ "$output" = 'typed=0 partial=0 kept=1 left=0' ] || false
  [ ! -e "$K.log" ] || false
  grep -q 'rc=9 kept' "$D/drafts.log" || false
}

@test "rd_pick takes the newest drafts directory whose start is inside the boot window, else none" {
  A="$D/autonomy"; mkdir -p "$A/reboot-d1.drafts" "$A/reboot-d2.drafts" "$A/reboot-d3.drafts"
  echo 100 > "$A/reboot-d1.start"; echo 200 > "$A/reboot-d2.start"; echo 900 > "$A/reboot-d3.start"
  rd rd_pick "$A" 50 500
  [ "$status" -eq 0 ] || false
  [ "$output" = "$A/reboot-d2.drafts" ] || false
  rd rd_pick "$A" 200 500                                     # the lower bound is exclusive
  [ "$status" -eq 1 ] || false
  [ -z "$output" ] || false
}
