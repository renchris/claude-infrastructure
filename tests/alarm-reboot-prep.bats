#!/usr/bin/env bats
# alarm-reboot-prep.sh — the agent half of the safe reboot order (host-memory.2). Every external
# reader is stubbed (ps, cc-sessions, zprint), so the verdicts are about the script, not this box.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/absent-repo"   # hermeticity: no live converge
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/land-lock"                           # hermeticity: never the live land lock
  mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  S="$REPO/scripts/alarm-reboot-prep.sh"
  D="$BATS_TEST_TMPDIR"
  export CC_REBOOT_PREP_DIR="$D/autonomy" CC_REBOOT_PREP_DATE=2020-01-01
  printf '#!/bin/sh\ncat "%s/ps.out"\n' "$D" > "$D/ps"
  printf '#!/bin/sh\necho "[{\\"paneUUID\\": \\"1\\"}, {\\"paneUUID\\": \\"2\\"}]"\n' > "$D/sessions"
  printf '#!/bin/sh\necho "data.kalloc.1024 1024 0K 0K 0 0 6291456 0K 0"\n' > "$D/zprint"
  chmod +x "$D/ps" "$D/sessions" "$D/zprint"
  export CC_REBOOT_PREP_PS="$D/ps" CC_REBOOT_PREP_SESSIONS="$D/sessions" CC_REBOOT_PREP_ZPRINT="$D/zprint"
  : > "$D/ps.out"
  # Every machine-touching seam is fixtured: the land's cwd (lsof), the prune targets, the defaults
  # writer, the kitten and the kitty sockets. Unset, the script refuses to touch the real ones under
  # bats, but a test must not depend on that guard to be hermetic.
  printf '#!/bin/sh\ncat "%s/lsof.out" 2>/dev/null\n' "$D" > "$D/lsof"
  printf '#!/bin/sh\necho "$*" >> "%s/defaults.log"\ncase "$1" in read) echo 1 ;; esac\nexit 0\n' "$D" > "$D/defaults"
  chmod +x "$D/lsof" "$D/defaults"
  mkdir -p "$D/socks" "$D/ctmp" "$D/cchome"
  export CC_REBOOT_PREP_LSOF="$D/lsof" CC_REBOOT_PREP_DEFAULTS="$D/defaults" \
         CC_REBOOT_PREP_SOCKS_DIR="$D/socks" CC_REBOOT_PREP_CLAUDE_TMP="$D/ctmp" \
         CC_REBOOT_PREP_CC_HOMES="$D/cchome" CC_REBOOT_PREP_KITTEN="$D/no-kitten" \
         CC_REBOOT_PREP_KITTY_SOCK_PREFIX="$D/no-kitty-"
  unset CLAUDE_CODE_SESSION_ID
}

# land_repo <pid> <phase> — a git repo whose in-flight marker names <pid> at <phase>, and an lsof stub
# answering that it is <pid>'s cwd (ship-land.sh writes the marker; this is its shape).
land_repo() {
  local r="$D/landrepo"
  mkdir -p "$r"; git -C "$r" init -q 2>/dev/null
  printf 'pid=%s\nlstart=x\nstarted=1\nbranch=feat/x\nhead=abc\nsid=s\nphase=%s\n' "$1" "$2" \
    > "$(git -C "$r" rev-parse --absolute-git-dir)/ship-land-inflight"
  printf 'p%s\nfcwd\nn%s\n' "$1" "$r" > "$D/lsof.out"
}

@test "READY with no land in flight: records the start epoch, the roster and the kalloc reading" {
  printf '  101 1 /bin/zsh -l\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=READY"* ]] || false
  [ -s "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" ] || false
  grep -q 'kalloc1024_gb=6.00' "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.kalloc" || false
  # .start is ONE line, ONE field: the epoch boot-resume.sh compares against the boot.
  [ "$(wc -l < "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" | tr -d ' ')" -eq 1 ] || false
  grep -qx '[0-9][0-9]*' "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" || false
  [ "$(grep -c paneUUID "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.roster.json")" -ge 1 ] || false
  [[ "$output" == *"live sessions      2 "* ]] || false
}

@test "NOT-READY (exit 3) when a ship-land.sh PROCESS outlives the wait deadline — and the records are still written" {
  export CC_REBOOT_PREP_LAND_WAIT_S=0
  printf '  201 1 bash /Users/x/.claude/scripts/ship-land.sh --land\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"waiting for them to finish, deadline "* ]] || false
  [[ "$output" == *"pids 201 still running at the deadline"* ]] || false
  [[ "$output" == *"verdict=NOT-READY reason=land-in-flight"* ]] || false
  [ -s "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" ] || false   # a reboot taken anyway still restores
  # R13: the operator steps print on the NOT-READY path too (they used to be skipped by the exit 3)
  [[ "$output" == *"Operator steps, in order:"* ]] || false
  printf '  202 1 /Users/x/.claude/scripts/ship-land.sh\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 3 ] || false
}

@test "a land in flight is WAITED for, deadline printed, then READY — the refusal that stranded the 10-12 reboot" {
  # ps reports the land for its first two calls, then it is gone.
  printf '#!/bin/sh\nn=$(cat "%s/ps.n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "%s/ps.n"\n[ "$n" -le 2 ] && echo "  201 1 bash /x/scripts/ship-land.sh --land"\nexit 0\n' "$D" "$D" > "$D/ps"
  run env CC_REBOOT_PREP_LAND_WAIT_S=60 CC_REBOOT_PREP_LAND_POLL_S=1 bash "$S"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [[ "$output" == *"pids 201 — waiting for them to finish, deadline "*" (60s)"* ]] || false
  [[ "$output" == *"lands in flight    finished or past their push after "* ]] || false
  [[ "$output" == *"verdict=READY"* ]]
}

@test "the HEAD prints the zone level, its share of the ceiling and the ETA, from the alarm's zone state" {
  mkdir -p "$CC_REBOOT_PREP_DIR"
  printf 'ceiling_gib=19.98\nslope_gib_day=2.00\nslope_src=trailing 3.0 d\n' > "$CC_REBOOT_PREP_DIR/kalloc-zone.state"
  printf '#!/bin/sh\necho "data.kalloc.1024 1024 0K 0K 0 0 15728640 0K 0"\n' > "$D/zprint"   # 15.00 GiB
  run bash "$S"
  [ "$status" -eq 0 ] || false
  # Line 2, before the roster, the arrangement and the steps: 4.98 GiB of room at 2 GiB/day.
  [ "$(printf '%s\n' "$output" | sed -n 2p)" = "  data.kalloc.1024   15.00 GiB = 75% of the ~19.98 GiB panic ceiling · +2.00 GiB/day (trailing 3.0 d) · ceiling in ~2.5 d ($(date -r $(( $(date +%s) + 216000 )) +%Y-%m-%d))" ] \
    || { printf '%s\n' "$output" | sed -n 1,3p; false; }
  grep -q 'kalloc1024_gb=15.00' "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.kalloc" || false
  rm -f "$CC_REBOOT_PREP_DIR/kalloc-zone.state"            # no alarm state: the level alone, said so
  run bash "$S"
  [[ "$(printf '%s\n' "$output" | sed -n 2p)" == *"15.00 GiB · ceiling and ETA unknown (no capacity-alarm zone state"* ]]
}

@test "a session whose brief merely MENTIONS ship-land.sh is not a land (the pgrep -f false positive)" {
  printf '  301 1 /Users/x/.claude-284/node_modules/.bin/claude --append-system-prompt run ship-land.sh later\n  302 1 bash /Users/x/.claude/bin/cc-close-attrib claude ship-land.sh\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"verdict=READY"* ]] || false
}

@test "a staged root capture is printed as the step BEFORE the reboot; absent, it is not" {
  run bash "$S"
  [[ "$output" != *"root zone capture is STAGED"* ]] || false
  mkdir -p "$CC_REBOOT_PREP_DIR"
  echo 'echo capture' > "$CC_REBOOT_PREP_DIR/kalloc-root-capture.cmd"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"root zone capture is STAGED"* ]] || false
  [[ "$output" == *"bash $CC_REBOOT_PREP_DIR/kalloc-root-capture.cmd"* ]] || false
}

@test "a failed roster read is said, never rendered as zero sessions" {
  printf '#!/bin/sh\nexit 1\n' > "$D/sessions"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"unknown (cc-sessions failed"* ]] || false
  [ ! -e "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.roster.json" ] || false
}

@test "a pending kitty restart rides this reboot and is named; absent, nothing is said" {
  run bash "$S"
  [[ "$output" != *"ALSO the kitty restart"* ]] || false
  mkdir -p "$CC_REBOOT_PREP_DIR"
  echo "kitty 0.48.3 patched build from ~/kitty-dev" > "$CC_REBOOT_PREP_DIR/kitty-restart-pending"
  run bash "$S"
  [[ "$output" == *"ALSO the kitty restart: kitty 0.48.3 patched build from ~/kitty-dev"* ]] || false
}

# ── B8 → R13 (2026-10-21): the reboot is also a kitty start, and kitty reads NSAppSleepDisabled at
#    start. The script used to print a `defaults write` hint nobody ran; it now writes the key itself
#    and reads it back with a SECOND call (a write's own exit is not the verdict). ──
@test "T12 the sleep key is written and read back; the verdict stays READY" {
  run bash "$S"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx 'write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES' "$D/defaults.log" || { cat "$D/defaults.log"; false; }
  grep -qx 'read net.kovidgoyal.kitty NSAppSleepDisabled' "$D/defaults.log" || false
  [[ "$output" == *"kitty sleep key    NSAppSleepDisabled = YES (set and read back"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=READY"* ]] || false
}

@test "T12b a write that does not read back says NOT SET with the command; CC_KITTY_HYGIENE=off touches nothing" {
  printf '#!/bin/sh\necho "$*" >> "%s/defaults.log"\ncase "$1" in read) echo 0 ;; esac\nexit 0\n' "$D" > "$D/defaults"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" == *"kitty sleep key    NOT SET"*"defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES"* ]] || { echo "$output"; false; }
  rm -f "$D/defaults.log"
  CC_KITTY_HYGIENE=off run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" != *"kitty sleep key"* ]] || false
  [ ! -e "$D/defaults.log" ]
}

@test "T12c a stalled defaults call is bounded: verdict READY, within the bound" {
  # Two stalled calls of 300 s each; bounded at 1 s, the whole run (slow under load) stays far below 600.
  printf '#!/bin/sh\nsleep 300\n' > "$D/defaults"
  export CC_REBOOT_PREP_DEFAULTS_S=1
  s=$SECONDS; run bash "$S"; el=$(( SECONDS - s ))
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=READY"* ]] || false
  [[ "$output" == *"kitty sleep key    NOT SET"* ]] || false
  [ "$el" -lt 150 ] || { echo "took ${el}s — the bound did not fire"; false; }
}

# ── R2 (2026-10-21): the owner session, in its own file (never in .start) ──
@test "R2 the owner file holds CLAUDE_CODE_SESSION_ID, one line; .start stays one epoch" {
  CLAUDE_CODE_SESSION_ID=551eb39b-28fe-4d85-8c97-a3d02448ab77 run bash "$S"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  o="$CC_REBOOT_PREP_DIR/reboot-2020-01-01.owner"
  [ "$(cat "$o")" = "551eb39b-28fe-4d85-8c97-a3d02448ab77" ] || { cat "$o"; false; }
  [ "$(wc -l < "$o" | tr -d ' ')" -eq 1 ] || false
  grep -qx '[0-9][0-9]*' "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" || false
  [[ "$output" == *"owner session      551eb39b-28fe-4d85-8c97-a3d02448ab77  → "* ]] || false
  # a later run from outside any session keeps today's owner rather than erasing it
  run bash "$S"
  [ "$(cat "$o")" = "551eb39b-28fe-4d85-8c97-a3d02448ab77" ] || false
  [[ "$output" == *"kept from an earlier run today"* ]] || false
}

# ── R13 (2026-10-21): phase-aware lands, one pid per land, one run at a time ──
@test "R13 a land in its post-release phase is SAFE: READY with no wait, named as past its push" {
  export CC_REBOOT_PREP_LAND_WAIT_S=60
  land_repo 401 post-release
  printf '  401 1 bash /x/scripts/ship-land.sh --land\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"lands past push    pids 401 (post-release)"*"safe to reboot"* ]] || { echo "$output"; false; }
  # no wait: the wait loop always announces itself (wall-clock is no witness at 15-40 load per core)
  [[ "$output" != *"waiting for them to finish"* ]] || false
  [[ "$output" == *"verdict=READY"* ]] || false
  land_repo 401 pushed; run bash "$S"
  [ "$status" -eq 0 ] || false
}

@test "R13 the same land BEFORE its push is still waited for (NOT-READY at the deadline)" {
  export CC_REBOOT_PREP_LAND_WAIT_S=0
  land_repo 402 pre-push
  printf '  402 1 bash /x/scripts/ship-land.sh --land\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  # a marker naming ANOTHER pid is somebody else's land: unknown phase, waited for
  land_repo 999 post-release
  printf '  402 1 bash /x/scripts/ship-land.sh --land\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 3 ] || { echo "$output"; false; }
}

@test "R13 a land's own subshell and locked child are ONE land, not three" {
  export CC_REBOOT_PREP_LAND_WAIT_S=0
  printf '  501 1 bash /x/scripts/ship-land.sh --land\n  502 501 bash /x/scripts/ship-land.sh --land\n  503 502 /bin/bash /x/scripts/land-lock.sh -- /x/scripts/ship-land.sh __locked\n  504 503 bash /x/scripts/ship-land.sh __locked main 0\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"pids 501 still running at the deadline"* ]] || { echo "$output"; false; }
}

@test "R13 a second concurrent prep run exits 2 naming the first; a stale lock is taken over" {
  mkdir -p "$CC_REBOOT_PREP_DIR/.reboot-prep.lock.d"
  sleep 30 & holder=$!
  echo "$holder" > "$CC_REBOOT_PREP_DIR/.reboot-prep.lock.d/pid"
  run bash "$S"
  kill "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"another run is in flight (pid $holder"* ]] || false
  [ ! -e "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" ] || false    # wrote nothing
  # the holder is gone now: its lock is stale, and the next run proceeds and releases it
  run bash "$S"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$CC_REBOOT_PREP_DIR/.reboot-prep.lock.d" ] || false
}

# ── R22 (2026-10-21): prune what Template Migration crawls ──
@test "R22 dead-pid sockets and idle tmp trees of sessions not in the roster are pruned; live ones stay" {
  touch "$D/socks/999999.sock" "$D/socks/$$.sock"
  dead=dddddddd-0000-0000-0000-000000000001; live=aaaaaaaa-0000-0000-0000-000000000002
  pidf=cccccccc-0000-0000-0000-000000000003; fresh=eeeeeeee-0000-0000-0000-000000000004
  for s in $dead $live $pidf $fresh; do mkdir -p "$D/ctmp/-x-cwd/$s/tasks"; echo o > "$D/ctmp/-x-cwd/$s/tasks/t.output"; done
  touch -t 202001010000 "$D/ctmp/-x-cwd/$dead/tasks/t.output" "$D/ctmp/-x-cwd/$live/tasks/t.output" "$D/ctmp/-x-cwd/$pidf/tasks/t.output"
  mkdir -p "$D/cchome/sessions"; printf '{"sessionId":"%s"}\n' "$pidf" > "$D/cchome/sessions/$$.json"
  printf '#!/bin/sh\necho "[{\\"paneUUID\\": \\"1\\", \\"session_id\\": \\"%s\\"}]"\n' "$live" > "$D/sessions"
  run bash "$S"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ ! -e "$D/socks/999999.sock" ] || false
  [ -e "$D/socks/$$.sock" ] || false
  [ ! -e "$D/ctmp/-x-cwd/$dead" ] || false                 # not in the roster, idle 6 h+
  [ -d "$D/ctmp/-x-cwd/$live" ] || false                   # in the roster
  [ -d "$D/ctmp/-x-cwd/$pidf" ] || false                   # a live Claude Code pid file names it
  [ -d "$D/ctmp/-x-cwd/$fresh" ] || false                  # wrote within 6 h
  [[ "$output" == *"pruned             1 dead-pid socket(s)"*"1 tmp tree(s)"* ]] || { echo "$output"; false; }
}

@test "R22 a failed roster read prunes nothing" {
  printf '#!/bin/sh\nexit 1\n' > "$D/sessions"
  touch "$D/socks/999999.sock"
  run bash "$S"
  [ -e "$D/socks/999999.sock" ] || false
  [[ "$output" != *"pruned "* ]] || false
}

# ── R14 (2026-10-21): --arm-restart, so the restart needs no click ──
# A unix socket bound by BASENAME after a chdir: an absolute path past 104 bytes fails to bind, and
# postland's tmp paths are longer than an interactive run's (the AF_UNIX gate in ship-land.sh).
mksock() { /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$1"; }
@test "R14 --arm-restart turns off every live kitty's quit dialog, lists vetoing apps, writes no reboot record" {
  sd="$D/ks"; mkdir -p "$sd"
  mksock "$sd/kitty-$$"
  mksock "$sd/kitty-999999"   # a dead kitty
  printf '#!/bin/sh\necho "$*" >> "%s/kitten.log"\nexit 0\n' "$D" > "$D/kitten"; chmod +x "$D/kitten"
  printf '  601 1 /Applications/Dia.app/Contents/MacOS/Dia\n  602 1 /Applications/kitty.app/Contents/MacOS/kitty\n  603 1 /Applications/Google Chrome.app/Contents/Frameworks/x/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper --type=gpu\n' > "$D/ps.out"
  CC_REBOOT_PREP_KITTEN="$D/kitten" CC_REBOOT_PREP_KITTY_SOCK_PREFIX="$sd/kitty-" run bash "$S" --arm-restart
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(cat "$D/kitten.log")" = "@ --to unix:$sd/kitty-$$ load-config -o confirm_os_window_close=0" ] || { cat "$D/kitten.log"; false; }
  [[ "$output" == *"kitty quit dialog  off for 1 kitty(s): $$:off"* ]] || { echo "$output"; false; }
  [[ "$output" == *"can veto restart   Dia — quit them first"* ]] || { echo "$output"; false; }
  [[ "$output" == *"final heartbeat    "* ]] || false
  [[ "$output" == *"verdict=ARMED"* ]] || false
  [ ! -e "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" ] || false
}

@test "R14 a kitty that refuses the override is NOT-ARMED (exit 3), naming it" {
  sd="$D/ks"; mkdir -p "$sd"
  mksock "$sd/kitty-$$"
  printf '#!/bin/sh\nexit 1\n' > "$D/kitten"; chmod +x "$D/kitten"
  CC_REBOOT_PREP_KITTEN="$D/kitten" CC_REBOOT_PREP_KITTY_SOCK_PREFIX="$sd/kitty-" run bash "$S" --arm-restart
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"1 of 1 kitty(s) did NOT take the override: $$:FAILED"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=NOT-ARMED reason=kitty-override"* ]] || false
}

@test "--dry-run reports the owner it would write and a post-push land as safe, and writes neither" {
  land_repo 701 post-release
  printf '  701 1 bash /x/scripts/ship-land.sh --land\n' > "$D/ps.out"
  CLAUDE_CODE_SESSION_ID=551eb39b-28fe-4d85-8c97-a3d02448ab77 run bash "$S" --dry-run
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"owner session      551eb39b-28fe-4d85-8c97-a3d02448ab77  (a real run writes it"* ]] || { echo "$output"; false; }
  [[ "$output" == *"lands past push    pids 701 (post-release) — safe to reboot"* ]] || false
  [[ "$output" == *"verdict=DRY-RUN"* ]] || false
  [ ! -e "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.owner" ] || false
}

# ── The .start pair (W3 P3a-i): the two scripts run together. Until 2026-10-04 this script appended
#    its kalloc reading to .start as a second line, and boot-resume.sh read the whole file as the
#    epoch, so every roster this script wrote was skipped at the reboot it was written for. ──
@test "paired: the roster this script writes is the one boot-resume.sh restores after the reboot" {
  B="$D/br"; mkdir -p "$B/registry" "$B/roles" "$B/tombs" "$HOME"
  echo desk-pane > "$B/roles/desk"
  printf '#!/bin/sh\necho "[{\\"session_id\\": \\"s-pair\\", \\"paneUUID\\": \\"1\\", \\"account\\": \\"claude-next\\", \\"cwd\\": \\"/x/pair\\", \\"name\\": \\"PAIRED-ONE\\"}]"\n' > "$D/sessions"
  run bash "$S"
  [ "$status" -eq 0 ] || false
  start="$(cat "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start")"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "$0.log"\n' > "$B/notify"; chmod +x "$B/notify"
  printf '#!/bin/bash\necho "[]"\n' > "$B/hbsess"; chmod +x "$B/hbsess"
  run env CC_BOOTTIME_OVERRIDE=$((start + 60)) CC_BOOT_RESUME_MODE=page \
      CC_BOOT_RESUME_ROSTER_DIR="$CC_REBOOT_PREP_DIR" CC_BOOT_RESUME_STATE_DIR="$B/state" \
      CC_REGISTRY_DIR="$B/registry" CC_ROLES_DIR="$B/roles" CC_SHUTDOWN_TOMB_DIR="$B/tombs" \
      CC_IDL="$B/idl.jsonl" CC_NOTIFY_BIN="$B/notify" CC_BACKLOG_BIN=/usr/bin/false \
      CC_RESUME_LAUNCH_BIN=/usr/bin/false CC_RESUME_LAYOUT_BIN="$B/none" CC_LAUNCHCTL_BIN=/usr/bin/true \
      CC_HEARTBEAT_DIR="$B/hb" CC_HB_SESSIONS_BIN="$B/hbsess" CC_HB_KITTEN_BIN=/usr/bin/false \
      CC_HB_PS_BIN="$BATS_TEST_DIRNAME/fixtures/hb-kitty-ps" CC_HB_LSOF_BIN=/usr/bin/true \
      /bin/bash "$REPO/scripts/boot-resume.sh"
  [ "$status" -eq 0 ] || false
  grep -q 'PAIRED-ONE' "$B/notify.log" || false
  grep -q 'source: roster reboot-2020-01-01' "$B/notify.log" || false
  grep -q '"source":"roster"' "$B/idl.jsonl" || false
}
