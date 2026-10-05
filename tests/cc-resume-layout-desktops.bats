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
    [ -f "$KLOG.hang" ] && { sleep 30 & echo $! > "$KLOG.sleeppid"; wait; echo 999; exit 0; }
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

# BOUNDED k() (2026-10-02, W3 P2): a wedged `kitty @` used to hang the launchd restore for good.
# The stub's launch sleeps 30 s in a grandchild, which would also hold `$(k …)`'s pipe open, so the
# bound must kill the whole process group. Pinned on both paths: timeout(1) and the perl fallback.
hung_launch() { # <timeout-bin override, or "default">
  row repo-a 1; touch "$KLOG.hang"
  export CC_RESUME_K_TIMEOUT=1
  [ "$1" = default ] || export CC_RESUME_K_TIMEOUT_BIN="$1"
  local t0=$SECONDS
  run --separate-stderr bash "$LAYOUT" --desktops --to unix:/tmp/fake --file "$ROWS"
  [ $((SECONDS - t0)) -lt 10 ]
  [ "$status" -eq 4 ]
  [ "$(kv failed)" = 1 ]; [ "$(kv launched)" = 0 ]; [ "$(kv verdict)" = failed ]
  ! kill -0 "$(cat "$KLOG.sleeppid")" 2>/dev/null || false
}

@test "a hung kitty launch is bounded by CC_RESUME_K_TIMEOUT and counted failed (timeout(1) path)" {
  hung_launch default
}

@test "a hung kitty launch is bounded by CC_RESUME_K_TIMEOUT and counted failed (perl fallback path)" {
  hung_launch ""
}

# The bound itself (W3 amendment §C 3): 120 s on today's default path, where a loaded kitty can take
# tens of seconds to answer; 15 s only under --restore. A recording timeout(1) stub logs the bound
# it was handed, then runs the call.
bound_for() { # <extra layout args…> → the distinct bounds k() handed timeout(1)
  row repo-a 1
  local tb="$BATS_TEST_TMPDIR/rec-timeout"
  printf '#!/bin/bash\necho "$1" >> "$0.log"; shift; exec "$@"\n' > "$tb"; chmod +x "$tb"
  unset CC_RESUME_K_TIMEOUT; export CC_RESUME_K_TIMEOUT_BIN="$tb"
  run --separate-stderr bash "$LAYOUT" --desktops --to unix:/tmp/fake --file "$ROWS" "$@"
  [ "$status" -eq 0 ]
  sort -u "$tb.log" | tr '\n' ' '
}

@test "k() is bounded at 120 s on the default path and 15 s under --restore" {
  [ "$(bound_for)" = "120 " ]
  rm -f "$BATS_TEST_TMPDIR/rec-timeout.log" "$KLOG"*; : > "$ROWS"
  [ "$(bound_for --restore)" = "15 " ]
}

# ── --restore (W3 P3b, 2026-10-04) ─────────────────────────────────────────────────────────────────
# The unattended restore path: one row of panes per window (head + vsplits, then goto-layout
# horizontal and the reset_window_sizes kitten, never `layout_action equalize`), wait-and-re-ask on
# the non-charging capacity probe, idle rows before prompt rows, the kitty fd guard, map lines,
# maybe rows judged by holder + SessionStart:resume, and fullscreen by kitty's own action by id.
# Extra stubs: the probe (refuses the first $PROBE_REFUSE asks and logs the R it saw), lr-lib's
# lr_holder_count (reads $BATS_TEST_TMPDIR/holders.<sid>), lsof, and a kitty that can time out
# (rc 124), refuse a toggle, or write the session's resume record on a launch it reports as failed.
restore_setup() {
  cat >> "$FIX/scripts/lib/capacity-admit.sh" <<'SH'
cc_capacity_probe() {
  local n; n=$(cat "$BATS_TEST_TMPDIR/probes" 2>/dev/null || echo 0); echo $((n + 1)) > "$BATS_TEST_TMPDIR/probes"
  printf 'R=%s %s\n' "${CC_ADMIT_RESTORE_R:-}" "$2" >> "$BATS_TEST_TMPDIR/probe.log"
  [ "$n" -ge "${PROBE_REFUSE:-0}" ] || return 9
}
SH
  mkdir -p "$FIX/scripts/limit-recover"
  printf 'lr_holder_count() { cat "$BATS_TEST_TMPDIR/holders.$1" 2>/dev/null || echo 0; }\n' > "$FIX/scripts/limit-recover/lr-lib.sh"
  : > "$FIX/scripts/kitty-equalize.py"
  export CC_LSOF_BIN="$BATS_TEST_TMPDIR/lsof"
  cat > "$CC_LSOF_BIN" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$0.log"
printf 'p1\nfcwd\nftxt\n'; i=0; while [ "$i" -lt "$(cat "$0.n" 2>/dev/null || echo 40)" ]; do echo "f$i"; i=$((i + 1)); done
SH
  chmod +x "$CC_LSOF_BIN"
  cat > "$CC_TERM_KITTY" <<'SH'
#!/bin/bash
printf 'KW=%s %s\n' "${KITTY_WINDOW_ID:-}" "$*" >> "$KLOG"
case " $* " in
  *" launch "*)
    if [ -f "$KLOG.mark" ]; then
      s="$(printf '%s' "$*" | grep -o 'sid-[a-z0-9-]*' | head -1)"
      mkdir -p "$HOME/.claude/projects/p"; echo '{"attachment":{"hookName":"SessionStart:resume"}}' >> "$HOME/.claude/projects/p/$s.jsonl"
    fi
    [ -f "$KLOG.rc124" ] && exit 124
    [ -f "$KLOG.fail" ] && { echo "Error: no such window"; exit 1; }
    n=$(cat "$KLOG.n" 2>/dev/null || echo 100); n=$((n + 1)); echo "$n" > "$KLOG.n"; echo "$n" ;;
  *" toggle_fullscreen "*) [ -f "$KLOG.fsfail" ] && exit 1 ;;
esac
exit 0
SH
  export CC_RESTORE_WAIT=0 CC_RESTORE_K_BACKOFF=0 CC_RESTORE_FS_GAP=0 CC_RESTORE_MAYBE_S=0 CC_RESTORE_MAYBE_POLL=0
  unset CC_ADMIT_RESTORE_R CC_ADMIT_ACTIVE_CEILING CC_RESTORE_DEADLINE CC_RESTORE_KITTY_PID KITTY_PID
}
restore() { run --separate-stderr bash "$LAYOUT" --desktops --restore --to unix:/tmp/kitty-4242 --file "$ROWS"; }
xrow() { # <repo> <n> <model> <effort> <group> <slot> <prompt> — an 11-column contract row, \037 = empty
  local wt="$BATS_TEST_TMPDIR/$1/w$2"; mkdir -p "$wt"
  printf 'next\tsid-%s-%s\t%s\tbr\tlabel\t%s\t%s\t%s\t%s\t%s\t\037\n' "$1" "$2" "$wt" "$3" "$4" "$5" "$6" "$7" >> "$ROWS"
}
launched_sids() { grep ' launch ' "$KLOG" | grep -o "'sid-[a-z0-9-]*'" | tr -d "'" | tr '\n' ' '; }

@test "restore: 5 rows → one window, a head plus 4 vsplits each beside the previous, one goto-layout, the kitten, no rotate or equalize" {
  restore_setup
  for i in 1 2 3 4 5; do row repo-a "$i"; done
  restore
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '--type=os-window' "$KLOG")" -eq 1 ]
  [ "$(grep -c -- '--location=vsplit' "$KLOG")" -eq 4 ]
  for p in 101 102 103 104; do grep -q -- "--match window_id:$p --next-to id:$p .*sid-repo-a-$((p - 99))'" "$KLOG"; done
  [ "$(grep -c 'goto-layout' "$KLOG")" -eq 1 ]
  grep -q -- 'goto-layout --match window_id:101 horizontal' "$KLOG"
  grep -q "^KW=101 .*action --self kitten /.*/tree/scripts/kitty-equalize.py$" "$KLOG"
  ! grep -q 'rotate\|layout_action' "$KLOG" || false
  [ "$(grep ' launch ' "$KLOG" | grep -vc -- '--keep-focus')" -eq 0 ]
  [ "$(grep -vc -- '--to unix:/tmp/kitty-4242' "$KLOG")" -eq 0 ]
  [ "$(kv windows)" = 1 ]; [ "$(kv launched)" = 5 ]; [ "$(kv verdict)" = ok ]; [ "$(kv maybe)" = 0 ]
}

@test "restore: a map line per launch, on stdout ahead of the verdict line" {
  restore_setup
  row repo-a 1; row repo-a 2
  restore
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | sed -n 1p)" = "cc-resume-layout: map sid=sid-repo-a-1 wid=101 oswin=1" ]
  [ "$(printf '%s\n' "$output" | sed -n 2p)" = "cc-resume-layout: map sid=sid-repo-a-2 wid=102 oswin=1" ]
  printf '%s\n' "$output" | sed -n 3p | grep -q '^cc-resume-layout: verdict=ok '
}

@test "restore: 7 rows of one project → 6 + 1, the cap is 6" {
  restore_setup
  for i in 1 2 3 4 5 6 7; do row repo-a "$i"; done
  restore
  [ "$(grep -c -- '--type=os-window' "$KLOG")" -eq 2 ]
  [ "$(grep -c 'goto-layout' "$KLOG")" -eq 2 ]
  [ "$(kv windows)" = 2 ]; [ "$(kv launched)" = 7 ]
}

@test "restore: a refused probe waits and re-asks the SAME row, never spends the budget, and passes R" {
  restore_setup
  row repo-a 1; row repo-a 2
  run --separate-stderr env PROBE_REFUSE=2 CC_ADMIT_RESTORE_R=5 bash "$LAYOUT" --desktops --restore --to unix:/tmp/kitty-4242 --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'restore sid-repo-a-1 on next' "$BATS_TEST_TMPDIR/probe.log")" -eq 3 ]
  [ "$(cut -d' ' -f1 "$BATS_TEST_TMPDIR/probe.log" | sort -u)" = "R=5" ]
  [ ! -f "$BATS_TEST_TMPDIR/admits" ]
  [ "$(printf '%s\n' "$stderr" | grep -c 'WAIT 0s, then re-ask for sid-repo-a-1')" -eq 2 ]
  [ "$(kv launched)" = 2 ]; [ "$(kv shed)" = 0 ]; [ "$(kv verdict)" = ok ]
}

@test "restore: a library without cc_capacity_probe falls back to the admit, loudly, and never waits" {
  row repo-a 1
  export CC_RESTORE_FS_GAP=0 CC_RESTORE_WAIT=30
  local t0=$SECONDS
  run --separate-stderr bash "$LAYOUT" --desktops --restore --to unix:/tmp/fake --file "$ROWS"
  [ $((SECONDS - t0)) -lt 20 ]
  [ "$status" -eq 0 ]
  printf '%s\n' "$stderr" | grep -q 'has no cc_capacity_probe'
  [ "$(cat "$BATS_TEST_TMPDIR/admits")" = 1 ]
  [ "$(kv launched)" = 1 ]
}

@test "restore: a probe that errors (rc not 9) launches the row ungated instead of waiting" {
  restore_setup
  row repo-a 1
  printf 'cc_capacity_probe() { return 1; }\n' >> "$FIX/scripts/lib/capacity-admit.sh"
  export CC_RESTORE_WAIT=30
  local t0=$SECONDS
  restore
  [ $((SECONDS - t0)) -lt 20 ]
  printf '%s\n' "$stderr" | grep -q 'capacity probe failed (rc 1) for sid-repo-a-1 — launching it UNGATED'
  [ "$(kv launched)" = 1 ]
}

@test "restore: R defaults to the active ceiling (8) when the caller sets none" {
  restore_setup
  row repo-a 1
  restore
  [ "$(cut -d' ' -f1 "$BATS_TEST_TMPDIR/probe.log")" = "R=8" ]
}

@test "restore: shed happens only at the deadline, and then for every remaining row" {
  restore_setup
  for i in 1 2 3; do row repo-a "$i"; done
  run --separate-stderr env PROBE_REFUSE=999 CC_RESTORE_DEADLINE=0 bash "$LAYOUT" --desktops --restore --to unix:/tmp/kitty-4242 --file "$ROWS"
  [ ! -f "$KLOG" ] || [ "$(launches)" -eq 0 ]
  [ "$(kv shed)" = 3 ]; [ "$(kv launched)" = 0 ]; [ "$(kv stopped)" = deadline ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/probe.log")" -eq 1 ]
}

@test "restore: a timed-out launch is a maybe, not failed; holder + a new resume record make it restored" {
  restore_setup
  row repo-a 1
  touch "$KLOG.rc124" "$KLOG.mark"; echo 1 > "$BATS_TEST_TMPDIR/holders.sid-repo-a-1"
  restore
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q '^cc-resume-layout: maybe sid=sid-repo-a-1 rc=124$'
  printf '%s\n' "$output" | grep -q '^cc-resume-layout: maybe-resolved sid=sid-repo-a-1 state=restored holders=1$'
  printf '%s\n' "$stderr" | grep -q 'backing off'
  [ "$(kv failed)" = 0 ]; [ "$(kv launched)" = 1 ]; [ "$(kv maybe)" = 0 ]; [ "$(kv verdict)" = ok ]
}

@test "restore: a live holder WITHOUT a new resume record stays maybe (degraded); no holder at all is failed" {
  restore_setup
  row repo-a 1; row repo-a 2
  touch "$KLOG.fail"; echo 1 > "$BATS_TEST_TMPDIR/holders.sid-repo-a-1"
  restore
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -q 'maybe-resolved sid=sid-repo-a-1 state=unconfirmed holders=1'
  printf '%s\n' "$output" | grep -q 'maybe-resolved sid=sid-repo-a-2 state=failed holders=0'
  [ "$(kv maybe)" = 1 ]; [ "$(kv failed)" = 1 ]; [ "$(kv launched)" = 0 ]; [ "$(kv verdict)" = degraded ]
}

@test "restore: groups from columns 8-9 keep their own windows, in slot order" {
  restore_setup
  xrow repo-a 1 $'\037' $'\037' g1 2 $'\037'
  xrow repo-a 2 $'\037' $'\037' g2 1 $'\037'
  xrow repo-a 3 $'\037' $'\037' g1 1 $'\037'
  restore
  [ "$status" -eq 0 ]
  [ "$(kv windows)" = 2 ]
  [ "$(launched_sids)" = "sid-repo-a-3 sid-repo-a-1 sid-repo-a-2 " ]
  printf '%s\n' "$output" | grep -q 'map sid=sid-repo-a-1 wid=102 oswin=1'
  printf '%s\n' "$output" | grep -q 'map sid=sid-repo-a-2 wid=103 oswin=2'
}

@test "restore: rows with a prompt (column 10) launch after the idle rows" {
  restore_setup
  xrow repo-a 1 $'\037' $'\037' $'\037' $'\037' /tmp/prompt-1
  xrow repo-a 2 $'\037' $'\037' $'\037' $'\037' $'\037'
  xrow repo-b 1 $'\037' $'\037' $'\037' $'\037' $'\037'
  restore
  [ "$status" -eq 0 ]
  [ "$(launched_sids)" = "sid-repo-a-2 sid-repo-b-1 sid-repo-a-1 " ]
}

@test "restore: model and effort ride through; columns 10-11 do not; a bad effort is dropped; \\037 is empty" {
  restore_setup
  xrow repo-a 1 claude-opus-5-5 xhigh $'\037' $'\037' /tmp/prompt-1
  xrow repo-a 2 $'\037' turbo $'\037' $'\037' $'\037'
  restore
  [ "$status" -eq 0 ]
  grep -q "'CC_RESUME_MODEL=claude-opus-5-5' '$CC_RESUME_ONE_BIN' 'next' '.*/repo-a/w1' 'sid-repo-a-1' 'br' '--effort' 'xhigh' || exec zsh -i" "$KLOG"
  ! grep -q 'prompt-1\|--prompt-file\|--permission-mode' "$KLOG" || false
  grep -q "'sid-repo-a-2' 'br' || exec zsh -i" "$KLOG"
  ! grep 'sid-repo-a-2' "$KLOG" | grep -q 'CC_RESUME_MODEL\|--effort' || false
  printf '%s\n' "$stderr" | grep -q "effort 'turbo' for sid-repo-a-2 .* dropped"
}

@test "restore: a 5-column row launches as today — no model, no effort, cert store set, shell root kept" {
  restore_setup
  row repo-a 1
  restore
  [ "$status" -eq 0 ]
  grep -q -- "-- zsh -ic 'env' 'CC_ADMIT_DONE=1' 'CLAUDE_CODE_CERT_STORE=bundled' '$CC_RESUME_ONE_BIN' 'next' '.*/repo-a/w1' 'sid-repo-a-1' 'br' || exec zsh -i" "$KLOG"
  grep -q -- '--env CLAUDE_CODE_CERT_STORE=bundled' "$KLOG"
}

@test "restore: toggle_fullscreen by id once per window, never re-toggled on refusal, and no AX call" {
  restore_setup
  for i in 1 2 3 4 5 6 7; do row repo-a "$i"; done
  touch "$KLOG.fsfail"
  restore
  [ "$status" -eq 0 ]
  [ "$(grep -c 'toggle_fullscreen' "$KLOG")" -eq 2 ]
  grep -q 'action --match id:101 toggle_fullscreen' "$KLOG"
  grep -q 'action --match id:107 toggle_fullscreen' "$KLOG"
  [ ! -f "$CC_OSASCRIPT_BIN.log" ]
  ! grep -q 'set-window-title' "$KLOG" || false
  [ "$(kv fullscreen_failed)" = 2 ]; [ "$(kv fullscreen_ok)" = 0 ]; [ "$(kv verdict)" = degraded ]
}

@test "restore: kitty past 180 fds (pid from the socket name) stops the restore before the next launch" {
  restore_setup
  row repo-a 1; row repo-a 2
  echo 181 > "$CC_LSOF_BIN.n"
  restore
  grep -q -- '-p 4242' "$CC_LSOF_BIN.log"
  [ ! -f "$KLOG" ] || [ "$(launches)" -eq 0 ]
  [ "$(kv stopped)" = fd ]; [ "$(kv shed)" = 2 ]
}

@test "restore: a failing lsof is a BLIND fd guard (said once), never a reading of 0" {
  restore_setup
  row repo-a 1; row repo-a 2
  printf '#!/bin/bash\nexit 1\n' > "$CC_LSOF_BIN"
  restore
  [ "$(printf '%s\n' "$stderr" | grep -c 'fd guard is blind')" -eq 1 ]
  [ "$(kv launched)" = 2 ]; [ "$(kv stopped)" = none ]
}

@test "restore: at 180 fds the restore proceeds" {
  restore_setup
  row repo-a 1
  echo 180 > "$CC_LSOF_BIN.n"
  restore
  [ "$(kv launched)" = 1 ]; [ "$(kv stopped)" = none ]
}

@test "restore --dry-run: one window, a head plus 4 vsplits, one goto-layout, no rotate, no equalize, no kitty" {
  restore_setup
  for i in 1 2 3 4 5; do row repo-a "$i"; done
  run --separate-stderr bash "$LAYOUT" --desktops --restore --dry-run --file "$ROWS"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$stderr" | grep -c '^DRY \[CC-DESK-1 repo-a\] head ')" -eq 1 ]
  [ "$(printf '%s\n' "$stderr" | grep -c '^DRY \[CC-DESK-1 repo-a\] vsplit ')" -eq 4 ]
  [ "$(printf '%s\n' "$stderr" | grep -c 'goto-layout .* horizontal')" -eq 1 ]
  ! printf '%s\n' "$stderr" | grep -q 'rotate\|layout_action' || false
  [ ! -f "$KLOG" ]
  [ "$(kv windows)" = 1 ]; [ "$(kv verdict)" = ok ]
}
