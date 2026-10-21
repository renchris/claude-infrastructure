#!/usr/bin/env bats
# alarm-reboot-prep.sh — the agent half of the safe reboot order (host-memory.2). Every external
# reader is stubbed (ps, cc-sessions, zprint), so the verdicts are about the script, not this box.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export SHIP_LAND_CONVERGE=off DEPLOY_REPO="$BATS_TEST_TMPDIR/absent-repo"   # hermeticity: no live converge
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
}

@test "READY with no land in flight: records the start epoch, the roster and the kalloc reading" {
  printf '  101 /bin/zsh -l\n' > "$D/ps.out"
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
  printf '  201 bash /Users/x/.claude/scripts/ship-land.sh --land\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"waiting for them to finish, deadline "* ]] || false
  [[ "$output" == *"pids 201 still running at the deadline"* ]] || false
  [[ "$output" == *"verdict=NOT-READY reason=land-in-flight"* ]] || false
  [ -s "$CC_REBOOT_PREP_DIR/reboot-2020-01-01.start" ] || false   # a reboot taken anyway still restores
  printf '  202 /Users/x/.claude/scripts/ship-land.sh\n' > "$D/ps.out"
  run bash "$S"
  [ "$status" -eq 3 ] || false
}

@test "a land in flight is WAITED for, deadline printed, then READY — the refusal that stranded the 10-12 reboot" {
  # ps reports the land for its first two calls, then it is gone.
  printf '#!/bin/sh\nn=$(cat "%s/ps.n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "%s/ps.n"\n[ "$n" -le 2 ] && echo "  201 bash /x/scripts/ship-land.sh --land"\nexit 0\n' "$D" "$D" > "$D/ps"
  run env CC_REBOOT_PREP_LAND_WAIT_S=60 CC_REBOOT_PREP_LAND_POLL_S=1 bash "$S"
  [ "$status" -eq 0 ] || { printf '%s\n' "$output"; false; }
  [[ "$output" == *"pids 201 — waiting for them to finish, deadline "*" (60s)"* ]] || false
  [[ "$output" == *"lands in flight    finished after "* ]] || false
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
  printf '  301 /Users/x/.claude-284/node_modules/.bin/claude --append-system-prompt run ship-land.sh later\n  302 bash /Users/x/.claude/bin/cc-close-attrib claude ship-land.sh\n' > "$D/ps.out"
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

# ── B8 (K3): the reboot is also a kitty start. The stub EXITS 1 with key=absent, as the real
#    `status` does on a WARN: under pipefail the old `status | grep -q` read that exit and never
#    printed the hint (RED on the design's sketch; measured HINT-NOT-PRINTED, review S4). ──
hyg_stub() { # $1=key state $2=exit code [$3=sleep]
  printf '#!/bin/bash\necho "$*" >> "$0.log"\n%sprintf "key=%s\\nmain_kitties=1\\nverdict=WARN(key)\\n"\nexit %s\n' \
    "${3:+sleep $3; }" "$1" "$2" > "$D/hyg"
  chmod +x "$D/hyg"; export CC_REBOOT_PREP_HYGIENE_BIN="$D/hyg"
}

@test "T12 key=absent with a WARN exit prints the defaults write hint; the verdict stays READY" {
  hyg_stub absent 1
  run bash "$S"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Before rebooting (it is also a kitty start): defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=READY"* ]] || false
  # the cheap verb, never the full status
  [ "$(cat "$D/hyg.log")" = "status --only key,main,probe" ]
}

@test "T12b key=on says nothing; CC_KITTY_HYGIENE=off never calls the tool" {
  hyg_stub on 0
  run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" != *"Before rebooting (it is also a kitty start)"* ]] || false
  rm -f "$D/hyg.log"; hyg_stub absent 1
  CC_KITTY_HYGIENE=off run bash "$S"
  [ "$status" -eq 0 ] || false
  [[ "$output" != *"Before rebooting (it is also a kitty start)"* ]] || false
  [ ! -e "$D/hyg.log" ]
}

@test "T12c a stalled hygiene read is bounded as a whole: no hint, verdict READY, within the bound" {
  hyg_stub absent 1 30
  export CC_REBOOT_PREP_HYGIENE_S=1
  s=$SECONDS; run bash "$S"; el=$(( SECONDS - s ))
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=READY"* ]] || false
  [[ "$output" != *"Before rebooting (it is also a kitty start)"* ]] || false
  [ "$el" -lt 20 ] || { echo "took ${el}s — the bound did not fire"; false; }
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
