#!/usr/bin/env bats
# cc-resume-layout.sh --desktops — the operator's resume layout (ruling 2026-09-30, after the 15:24
# reboot recovery): ONE native-fullscreen kitty OS window per macOS Desktop, at most 4 panes each as
# a 2x2, grouped by project. The per-monitor mode put 5 panes side by side, 37 columns each, which
# wraps Claude Code's footer.
#
# Contract under test: the kitty argv the mode emits (os-window head, vsplits, `layout_action
# rotate` on the 3rd and 4th pane, equalize, every call aimed at the given socket), the packing of
# projects into windows, the fullscreen verdict taken ONLY from the AXFullScreen read-back, the
# temporary title marker, per-pane capacity shedding, the one stdout summary line boot-resume.sh
# parses, and the exit codes. RED-proof: every case fails against the pre-change script, which
# rejects `--desktops` as an unknown argument (exit 2).
#
# Hermetic: the script is COPIED into a fixture tree whose scripts/lib holds stub capacity-admit and
# pane-spawn-log libraries (the script resolves both beside itself first), so no case measures the
# real box or writes the live spawn log; kitty and osascript are stubs; no case touches a real kitty.

bats_require_minimum_version 1.5.0

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # The fixture tree below already stubs the capacity library; this closes the real gate too, in
  # case a resolution ever falls through to it.
  export CC_ADMIT_GATE=off
  FIX="$BATS_TEST_TMPDIR/tree"
  mkdir -p "$FIX/bin" "$FIX/scripts/lib"
  cp "$REPO/bin/cc-resume-layout.sh" "$FIX/bin/"
  LAYOUT="$FIX/bin/cc-resume-layout.sh"
  # capacity stub: admits the first $ADMIT_ALLOW calls (default: all), refuses after.
  cat > "$FIX/scripts/lib/capacity-admit.sh" <<'SH'
cc_capacity_admit() {
  local n; n=$(cat "$BATS_TEST_TMPDIR/admits" 2>/dev/null || echo 0); echo $((n + 1)) > "$BATS_TEST_TMPDIR/admits"
  [ "$n" -lt "${ADMIT_ALLOW:-999}" ]
}
cc_capacity_admit_reason() { printf 'stub: box full'; }
SH
  printf 'cc_log_pane_spawn() { :; }\n' > "$FIX/scripts/lib/pane-spawn-log.sh"

  export KLOG="$BATS_TEST_TMPDIR/kitty.log"
  export CC_TERM_KITTY="$BATS_TEST_TMPDIR/kitty"
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf 'KW=%s %s\n' "${KITTY_WINDOW_ID:-}" "$*" >> "$KLOG"
case " $* " in
  *" launch "*)
    [ -f "$KLOG.fail" ] && { echo "Error: no such window"; exit 1; }
    n=$(cat "$KLOG.n" 2>/dev/null || echo 100); n=$((n + 1)); echo "$n" > "$KLOG.n"; echo "$n" ;;
esac
SH
  chmod +x "$CC_TERM_KITTY"
  export CC_OSASCRIPT_BIN="$BATS_TEST_TMPDIR/osascript"
  cat > "$CC_OSASCRIPT_BIN" <<'SH'
#!/bin/bash
m="$(grep -o 'contains "[^"]*"' | head -1)"
printf '%s\n' "$m" >> "$0.log"
cat "$0.reply" 2>/dev/null || echo true
SH
  chmod +x "$CC_OSASCRIPT_BIN"
  export CC_RESUME_ONE_BIN="$BATS_TEST_TMPDIR/resume-one"
  printf '#!/bin/bash\nexit 0\n' > "$CC_RESUME_ONE_BIN"; chmod +x "$CC_RESUME_ONE_BIN"
  export CC_RESUME_STAGGER=0 CC_DESKTOP_SETTLE=0 CC_DESKTOP_FS_DELAY=0
  export CC_SWIFT_BIN="$BATS_TEST_TMPDIR/no-swift"
  unset KITTY_WINDOW_ID CC_TERM_KITTY_TO

  # Two projects: repo-a and repo-b, each worktree a subdirectory (the group key is the repo).
  for r in repo-a repo-b; do git init -q "$BATS_TEST_TMPDIR/$r"; done
  ROWS="$BATS_TEST_TMPDIR/rows.tsv"; : > "$ROWS"
}

row() { # <repo> <n> — one lr-select-shaped row: acct sid worktree branch label
  local wt="$BATS_TEST_TMPDIR/$1/w$2"; mkdir -p "$wt"
  printf 'next\tsid-%s-%s\t%s\tbr\tlabel-%s\n' "$1" "$2" "$wt" "$2" >> "$ROWS"
}
summary() { printf '%s\n' "$output" | grep '^cc-resume-layout: verdict=' ; }
kv() { summary | tr ' ' '\n' | sed -n "s/^$1=//p"; }
launches() { grep -c ' launch ' "$KLOG"; }

@test "4 rows, one project → one 2x2: head, vsplits, rotate on panes 3 and 4, equalize, all via --to" {
  for i in 1 2 3 4; do row repo-a "$i"; done
  run --separate-stderr bash "$LAYOUT" --desktops --to unix:/tmp/fake --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--type=os-window' "$KLOG")" -eq 1 ]
  [ "$(grep -c -- '--location=vsplit' "$KLOG")" -eq 3 ]
  # C (id 103) goes under A (101); D (104) is launched beside B (102) and goes under it.
  grep -q -- '--next-to id:101 .*sid-repo-a-3' "$KLOG"
  grep -q -- '--next-to id:102 .*sid-repo-a-4' "$KLOG"
  [ "$(grep 'layout_action rotate' "$KLOG" | cut -d' ' -f1 | tr '\n' ' ')" = "KW=103 KW=104 " ]
  grep -q '^KW=101 .*layout_action equalize' "$KLOG"
  ! grep -q 'goto-layout' "$KLOG" || false
  [ "$(grep -vc -- '--to unix:/tmp/fake' "$KLOG")" -eq 0 ]
  [ "$(kv windows)" = 1 ]; [ "$(kv launched)" = 4 ]; [ "$(kv fullscreen_ok)" = 1 ]; [ "$(kv verdict)" = ok ]
}

@test "the pane command is a shell root: the resume runs under zsh, then an interactive zsh remains" {
  row repo-a 1
  run --separate-stderr bash "$LAYOUT" --desktops --to unix:/tmp/fake --file "$ROWS"
  [ "$status" -eq 0 ]
  grep -q -- "-- zsh -ic 'env' 'CC_ADMIT_DONE=1' '$CC_RESUME_ONE_BIN' 'next' '.*/repo-a/w1' 'sid-repo-a-1' 'br' || exec zsh -i" "$KLOG"
}

@test "6 rows over two projects (4+2) → two windows, and no window mixes the projects" {
  for i in 1 2 3 4; do row repo-a "$i"; done
  for i in 1 2; do row repo-b "$i"; done
  run --separate-stderr bash "$LAYOUT" --desktops --dry-run --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(kv windows)" = 2 ]
  [ "$(printf '%s\n' "$stderr" | grep -c 'DRY \[CC-DESK-1 repo-a\]')" -eq 4 ]
  [ "$(printf '%s\n' "$stderr" | grep -c 'DRY \[CC-DESK-2 repo-b\]')" -eq 2 ]
}

@test "5 rows of one project → 4 + 1, never a fifth pane in one window" {
  for i in 1 2 3 4 5; do row repo-a "$i"; done
  run --separate-stderr bash "$LAYOUT" --desktops --to unix:/tmp/fake --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--type=os-window' "$KLOG")" -eq 2 ]
  [ "$(kv windows)" = 2 ]; [ "$(kv launched)" = 5 ]; [ "$(kv fullscreen_ok)" = 2 ]
}

@test "fullscreen verdict is the READ-BACK: 'false' twice → one retry, fullscreen_failed=1, degraded" {
  row repo-a 1; row repo-a 2
  echo false > "$CC_OSASCRIPT_BIN.reply"
  run --separate-stderr bash "$LAYOUT" --desktops --to unix:/tmp/fake --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CC_OSASCRIPT_BIN.log" | tr -d ' ')" -eq 2 ]
  [ "$(kv fullscreen_failed)" = 1 ]; [ "$(kv fullscreen_ok)" = 0 ]; [ "$(kv verdict)" = degraded ]
}

@test "the window is found by a marker set on EVERY pane before the AX call, and handed back after" {
  row repo-a 1; row repo-a 2
  run --separate-stderr bash "$LAYOUT" --desktops --to unix:/tmp/fake --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(cat "$CC_OSASCRIPT_BIN.log")" = 'contains "CC-DESK-1"' ]
  grep -q 'set-window-title --match id:101 CC-DESK-1' "$KLOG"
  grep -q 'set-window-title --match id:102 CC-DESK-1' "$KLOG"
  # marker first, reset last: the reset lines are the final two kitty calls for this window
  [ "$(grep 'set-window-title' "$KLOG" | tail -2 | grep -c 'CC-DESK')" -eq 0 ]
  [ "$(grep -c 'set-window-title' "$KLOG")" -eq 4 ]
}

@test "a capacity refusal on pane 3 sheds the rest: launched=2 shed=2, verdict=shed" {
  for i in 1 2 3 4; do row repo-a "$i"; done
  run --separate-stderr env ADMIT_ALLOW=2 bash "$LAYOUT" --desktops --to unix:/tmp/fake --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 2 ]
  [ "$(kv launched)" = 2 ]; [ "$(kv shed)" = 2 ]; [ "$(kv verdict)" = shed ]
}

@test "every launch failing → verdict=failed, exit 4" {
  row repo-a 1; row repo-a 2
  touch "$KLOG.fail"
  run --separate-stderr bash "$LAYOUT" --desktops --to unix:/tmp/fake --file "$ROWS"
  [ "$status" -eq 4 ]
  [ "$(kv failed)" = 2 ]; [ "$(kv verdict)" = failed ]
}

@test "--dry-run makes no kitty and no osascript call" {
  row repo-a 1; row repo-a 2
  run --separate-stderr bash "$LAYOUT" --desktops --dry-run --file "$ROWS"
  [ "$status" -eq 0 ]
  [ ! -f "$KLOG" ]
  [ ! -f "$CC_OSASCRIPT_BIN.log" ]
  [ "$(kv verdict)" = ok ]
}

@test "no --to, no KITTY_WINDOW_ID and no live socket → exit 3 (boot-resume's cue to start kitty)" {
  row repo-a 1
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/ksock"
  printf '#!/bin/bash\nexit 4\n' > "$CC_KITTY_SOCKET_BIN"; chmod +x "$CC_KITTY_SOCKET_BIN"
  run --separate-stderr bash "$LAYOUT" --desktops --file "$ROWS"
  [ "$status" -eq 3 ]
  [ ! -f "$KLOG" ]
}

@test "no --to: the live socket from cc-kitty-socket is used" {
  row repo-a 1
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/ksock"
  printf '#!/bin/bash\necho unix:/tmp/kitty-live\n' > "$CC_KITTY_SOCKET_BIN"; chmod +x "$CC_KITTY_SOCKET_BIN"
  run --separate-stderr bash "$LAYOUT" --desktops --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(grep -vc -- '--to unix:/tmp/kitty-live' "$KLOG")" -eq 0 ]
}

@test "without --desktops the per-monitor mode is unchanged: no rotate, no summary line" {
  row repo-a 1; row repo-a 2
  run --separate-stderr bash "$LAYOUT" --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(launches)" -eq 2 ]
  ! grep -q 'rotate' "$KLOG" || false
  [ -z "$output" ]
}
