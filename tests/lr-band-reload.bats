#!/usr/bin/env bats
# lr-band-reload.bats — the operator step for lever A1 (docs/research/lr-sustained-load-2026-10-20):
# reload the reconciler and the reset poller from the live layer, then read their band back.
#
# Hermetic: launchctl is a fake on PATH that keeps its loaded set and each job's spawn type in files,
# and records every call; the live dir, agents dir and state live under $BATS_TEST_TMPDIR. plutil is
# the real one. The fake bootstrap of the reconciler starts a real `sleep` as its "pid" and writes
# the band.log line the new daemon would, which is the read-back the script verifies against.

SUT="$BATS_TEST_DIRNAME/../scripts/limit-recover/lr-band-reload.sh"
SRC="$BATS_TEST_DIRNAME/../scripts/limit-recover"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"
  export LR_LAUNCHD_AGENTS_DIR="$BATS_TEST_TMPDIR/agents"
  export LR_BAND_LIVE_DIR="$BATS_TEST_TMPDIR/live"
  export LR_BAND_WAIT_S=5 LR_BAND_QUIET_MAX_S=5
  export FAKE="$BATS_TEST_TMPDIR/fake" FAKE_LOG="$BATS_TEST_TMPDIR/launchctl.log"
  export FAKE_BAND="${FAKE_BAND:-31}"
  mkdir -p "$HOME" "$BATS_TEST_TMPDIR/bin" "$FAKE" "$LR_BAND_LIVE_DIR/lr_recon" "$LR_STATE_DIR/recon"
  cp "$SRC/com.reso.lr-reconciler.plist" "$SRC/com.reso.lr-reset-poller.plist" "$LR_BAND_LIVE_DIR/"
  : > "$LR_BAND_LIVE_DIR/lr_recon/band.py"
  # both jobs loaded today, in launchd's default band
  for l in com.reso.lr-reconciler com.reso.lr-reset-poller; do echo "daemon (3)" > "$FAKE/$l"; done
  # the dispatcher target (wave 5): loaded today at Background; the repo plist and a live
  # cc-dispatch that carries the band self-check are fixtured beside the live dir
  echo "background (5)" > "$FAKE/com.claude.dispatcher"
  export LR_BAND_DISPATCHER_PLIST="$BATS_TEST_TMPDIR/com.claude.dispatcher.plist"
  export LR_BAND_DISPATCHER_BIN="$BATS_TEST_TMPDIR/cc-dispatch"
  export LR_BAND_DISPATCHER_LOG="$BATS_TEST_TMPDIR/dispatch-band.log"
  cp "$BATS_TEST_DIRNAME/../launchd/com.claude.dispatcher.plist" "$LR_BAND_DISPATCHER_PLIST"
  cp "$BATS_TEST_DIRNAME/../bin/cc-dispatch" "$LR_BAND_DISPATCHER_BIN"
  cat > "$BATS_TEST_TMPDIR/bin/launchctl" <<'SH'
#!/bin/bash
echo "$*" >> "$FAKE_LOG"
case "$1" in
  print)
    l="${2##*/}"; [ -f "$FAKE/$l" ] || exit 113
    printf '%s = {\n\tspawn type = %s\n' "$2" "$(cat "$FAKE/$l")"
    [ -f "$FAKE/$l.pid" ] && printf '\tpid = %s\n' "$(cat "$FAKE/$l.pid")"
    echo "}" ;;
  bootstrap)
    l="$(basename "$3" .plist)"
    if /usr/bin/plutil -p "$3" | grep -q '"ProcessType" => "Interactive"'; then st="interactive (4)"; else st="daemon (3)"; fi
    echo "$st" > "$FAKE/$l"
    if [ "$l" = com.reso.lr-reconciler ]; then
      sleep 30 & p=$!; echo "$p" > "$FAKE/$l.pid"
      echo "1000 pid=$p pri=$FAKE_BAND floor=31 $([ "$FAKE_BAND" -ge 31 ] && echo ok || echo low)" >> "$LR_STATE_DIR/recon/band.log"
    fi
    exit 0 ;;
  bootout) l="${2##*/}"; [ -f "$FAKE/$l.pid" ] && kill "$(cat "$FAKE/$l.pid")" 2>/dev/null; rm -f "$FAKE/$l" "$FAKE/$l.pid" ;;
  enable) exit 0 ;;
  kickstart)
    l="${2##*/}"; [ -f "$FAKE/$l" ] || exit 113
    sleep 30 & p=$!; echo "$p" > "$FAKE/$l.pid"
    echo "$(date +%s) pid=$p pri=$FAKE_BAND floor=31 $([ "$FAKE_BAND" -ge 31 ] && echo ok || echo low)" >> "$LR_BAND_DISPATCHER_LOG"
    exit 0 ;;
  *) exit 64 ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

teardown() {
  local l w
  for l in com.reso.lr-reconciler com.claude.dispatcher com.claude.accounts-keepwarm com.claude.accounts-local; do
    if [ -f "$FAKE/$l.pid" ]; then kill "$(cat "$FAKE/$l.pid")" 2>/dev/null || true; fi
  done
  if [ -f "$BATS_TEST_TMPDIR/wrapper.pid" ]; then
    w="$(cat "$BATS_TEST_TMPDIR/wrapper.pid")"
    pkill -P "$w" 2>/dev/null || true
    kill "$w" 2>/dev/null || true
  fi
  return 0
}

# An actuator wrapper in act.WRAPPER's argv shape (`/bin/bash -c <script> lr-recon-act --record-id
# <rid> --intent <nonce> …`), started by this test, so its ppid is not the reconciler's: the shape of
# an actuator inherited across an earlier restart, which launchd (ppid 1) holds (A6 F-J).
fake_wrapper() { # $1=record id
  /bin/bash -c 'sleep 30; :' lr-recon-act --record-id "$1" --intent 0123456789ab >/dev/null 2>&1 3>&- &
  echo $! > "$BATS_TEST_TMPDIR/wrapper.pid"
}
record() { # $1=record id $2=terminal JSON (null = open)
  mkdir -p "$LR_STATE_DIR/recon/sessions"
  printf '{"sid":"abcdef01","record_id":"%s","terminal":%s}\n' "$1" "$2" > "$LR_STATE_DIR/recon/sessions/abcdef01.json"
}

@test "dry run: preflight passes on the repo plists, nothing is booted out, exit 0" {
  run bash "$SUT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"declare ProcessType Interactive"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "consent must name the target" {
  run bash "$SUT" --confirm yes
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  ! grep -q 'bootout' "$FAKE_LOG" 2>/dev/null
}

@test "an unknown flag is refused before anything is reloaded" {
  run bash "$SUT" --confirm lr-band --nwo
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  [[ "$output" == *"unknown argument '--nwo'"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "--now dry run: preflight passes and it says the quiet wait is skipped; nothing reloaded" {
  run bash "$SUT" --now
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"would: skip the quiet wait (--now"* ]] || { echo "$output"; false; }
  [[ "$output" == *"--confirm lr-band --now)"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "--now is refused for the dispatcher target, which keeps its own quiet point" {
  run bash "$SUT" --confirm dispatcher-band --now
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "[RED] an inherited lr-recon-act naming an open record holds the reload (any ppid)" {
  # pre-A6 the predicate was `pgrep -P <reconciler>` only, and this wrapper is no child of it
  record "recon:bats-open:1" null
  fake_wrapper "recon:bats-open:1"
  run bash "$SUT" --confirm lr-band
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"mid-act for 5s"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "CONTROL: the same wrapper on a TERMINAL record does not hold the reload" {
  record "recon:bats-done:1" '{"outcome":"MOVED","proof":"x","at":1.0}'
  fake_wrapper "recon:bats-done:1"
  run bash "$SUT" --confirm lr-band
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ok"* ]] || { echo "$output"; false; }
}

@test "--now: an in-flight inherited actuator does not hold the reload, and is named" {
  record "recon:bats-open:1" null
  fake_wrapper "recon:bats-open:1"
  run bash "$SUT" --confirm lr-band --now
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"--now: not waiting for a quiet boundary (an actuator is in flight"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ok"* ]] || { echo "$output"; false; }
}

@test "[RED] a live plist without ProcessType Interactive is refused before anything is reloaded" {
  # the pre-A1 plist: the live layer was not converged, so a reload would bootstrap PRI 20 again
  /usr/bin/sed -i '' '/<key>ProcessType<\/key>/d' "$LR_BAND_LIVE_DIR/com.reso.lr-reset-poller.plist"
  run bash "$SUT" --confirm lr-band
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"not converged"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "apply: both jobs bootstrapped from the live layer, spawn type and band read back, verdict ok" {
  run bash "$SUT" --confirm lr-band
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  for l in com.reso.lr-reconciler com.reso.lr-reset-poller; do
    cmp -s "$LR_BAND_LIVE_DIR/$l.plist" "$LR_LAUNCHD_AGENTS_DIR/$l.plist" || { echo "$l not installed"; false; }
    grep -q "^bootout gui/[0-9]*/$l\$" "$FAKE_LOG" || { cat "$FAKE_LOG"; false; }
    grep -q "^bootstrap gui/[0-9]* $LR_LAUNCHD_AGENTS_DIR/$l.plist\$" "$FAKE_LOG" || { cat "$FAKE_LOG"; false; }
    [[ "$output" == *"$l spawn type = interactive (4)"* ]] || { echo "$output"; false; }
  done
  [[ "$output" == *"── ps -M com.reso.lr-reconciler (pid "* ]] || { echo "$output"; false; }
  [[ "$output" == *"✓ band.log: 1000 pid="*" pri=31 floor=31 ok"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ok"* ]] || { echo "$output"; false; }
}

@test "apply: a reconciler that reports a band below 31 fails the verdict" {
  export FAKE_BAND=20
  run bash "$SUT" --confirm lr-band
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"verdict=FAILED"* ]] || { echo "$output"; false; }
}

# ── the dispatcher target (lr-sustained-load wave 5) ──────────────────────────────────────────────
# RED on the pre-change script: `--dispatcher` and `--confirm dispatcher-band` were unknown
# arguments (exit 2), so there was no step that reloads the dispatcher and reads its band back.

@test "dispatcher dry run: preflight passes on the repo plist and the live cc-dispatch, nothing reloaded" {
  run bash "$SUT" --dispatcher
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"declares ProcessType Interactive; the live cc-dispatch logs its band"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "[RED] dispatcher: a plist still at Background is refused before anything is reloaded" {
  /usr/bin/sed -i '' 's#<string>Interactive</string>#<string>Background</string>#' "$LR_BAND_DISPATCHER_PLIST"
  run bash "$SUT" --confirm dispatcher-band
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"not converged"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "[RED] dispatcher: a live cc-dispatch without the band self-check is refused" {
  printf '#!/bin/bash\nexit 0\n' > "$LR_BAND_DISPATCHER_BIN"
  run bash "$SUT" --confirm dispatcher-band
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"no band self-check"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "dispatcher apply: bootout, enable, bootstrap, kickstart; spawn type and band read back; rail untouched" {
  run bash "$SUT" --confirm dispatcher-band
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  l=com.claude.dispatcher
  cmp -s "$LR_BAND_DISPATCHER_PLIST" "$LR_LAUNCHD_AGENTS_DIR/$l.plist" || { echo "$l not installed"; false; }
  for verb in bootout enable kickstart; do
    grep -q "^$verb gui/[0-9]*/$l\$" "$FAKE_LOG" || { cat "$FAKE_LOG"; false; }
  done
  grep -q "^bootstrap gui/[0-9]* $LR_LAUNCHD_AGENTS_DIR/$l.plist\$" "$FAKE_LOG" || { cat "$FAKE_LOG"; false; }
  # enable precedes bootstrap (a disabled label refuses bootstrap with a bare EIO)
  [ "$(grep -n "^enable " "$FAKE_LOG" | cut -d: -f1)" -lt "$(grep -n "^bootstrap " "$FAKE_LOG" | cut -d: -f1)" ]
  [[ "$output" == *"$l spawn type = interactive (4)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"✓ dispatch-band.log: "*" pri=31 floor=31 ok"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=ok"* ]] || { echo "$output"; false; }
  ! grep -q 'com.reso.lr-' "$FAKE_LOG" || false
}

@test "dispatcher apply: a pass that logs a band below 31 fails the verdict" {
  export FAKE_BAND=4
  run bash "$SUT" --confirm dispatcher-band
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"pri=4 floor=31 low (want floor=31 ok)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=FAILED"* ]] || { echo "$output"; false; }
}

# ── the router-cache producers (LR_SUSTAINED_LOAD W7, batch RK) ───────────────────────────────────
# RED on the pre-change tree: `--keepwarm` / `--confirm keepwarm-band` were unknown arguments
# (exit 2), and the staged plists said ProcessType Standard (read 20T live).
KW="com.claude.accounts-keepwarm com.claude.accounts-local"
kw_setup() { # installed copies at the old Standard band, both loaded; the staged dir is the repo's
  export LR_BAND_KEEPWARM_DIR="$BATS_TEST_DIRNAME/../launchd/staged"
  export LR_BAND_PY="$BATS_TEST_TMPDIR/band.py"
  printf 'import os\nprint(os.environ.get("FAKE_BAND", "31"))\n' > "$LR_BAND_PY"
  mkdir -p "$LR_LAUNCHD_AGENTS_DIR"
  local l
  for l in $KW; do
    /usr/bin/sed 's#<string>Interactive</string>#<string>Standard</string>#' "$LR_BAND_KEEPWARM_DIR/$l.plist" > "$LR_LAUNCHD_AGENTS_DIR/$l.plist"
    echo "standard (2)" > "$FAKE/$l"
  done
}

@test "keepwarm dry run: preflight passes on the staged repo plists, names the installed band, nothing reloaded" {
  kw_setup
  run bash "$SUT" --keepwarm
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"both staged plists lint and declare ProcessType Interactive"* ]] || { echo "$output"; false; }
  for l in $KW; do
    [[ "$output" == *"would: bootout + bootstrap + kickstart $l (installed ProcessType Standard; now: spawn type standard (2))"* ]] || { echo "$output"; false; }
  done
  [[ "$output" == *"--confirm keepwarm-band)"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap\|kickstart' "$FAKE_LOG" 2>/dev/null
}

@test "[RED] keepwarm: a staged plist still at Standard is refused before anything is reloaded" {
  kw_setup
  mkdir -p "$BATS_TEST_TMPDIR/staged"
  cp "$LR_BAND_KEEPWARM_DIR"/com.claude.accounts-*.plist "$BATS_TEST_TMPDIR/staged/"
  /usr/bin/sed -i '' 's#<string>Interactive</string>#<string>Standard</string>#' "$BATS_TEST_TMPDIR/staged/com.claude.accounts-local.plist"
  export LR_BAND_KEEPWARM_DIR="$BATS_TEST_TMPDIR/staged"
  run bash "$SUT" --confirm keepwarm-band
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"not converged"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "keepwarm apply: both installed from launchd/staged, bootout/bootstrap/kickstart, spawn type and band read back; rail untouched" {
  kw_setup
  run bash "$SUT" --confirm keepwarm-band
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  for l in $KW; do
    cmp -s "$LR_BAND_KEEPWARM_DIR/$l.plist" "$LR_LAUNCHD_AGENTS_DIR/$l.plist" || { echo "$l not installed"; false; }
    grep -q "^bootout gui/[0-9]*/$l\$" "$FAKE_LOG" || { cat "$FAKE_LOG"; false; }
    grep -q "^bootstrap gui/[0-9]* $LR_LAUNCHD_AGENTS_DIR/$l.plist\$" "$FAKE_LOG" || { cat "$FAKE_LOG"; false; }
    grep -q "^kickstart gui/[0-9]*/$l\$" "$FAKE_LOG" || { cat "$FAKE_LOG"; false; }
    [[ "$output" == *"$l spawn type = interactive (4)"* ]] || { echo "$output"; false; }
    [[ "$output" == *"✓ $l band=31 (pid "* ]] || { echo "$output"; false; }
    [[ "$output" == *"── ps -M $l (pid "* ]] || { echo "$output"; false; }
  done
  [[ "$output" == *"verdict=ok"* ]] || { echo "$output"; false; }
  ! grep -q 'com.reso.lr-\|com.claude.dispatcher' "$FAKE_LOG" || false
}

@test "keepwarm apply: a caught tick below 31 fails the verdict" {
  kw_setup
  export FAKE_BAND=20
  run bash "$SUT" --confirm keepwarm-band
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"com.claude.accounts-keepwarm band=20 (pid"*"want >= 31)"* ]] || { echo "$output"; false; }
  [[ "$output" == *"verdict=FAILED"* ]] || { echo "$output"; false; }
}

@test "keepwarm: a producer that is not installed is skipped, never armed; the other is reloaded" {
  kw_setup
  rm -f "$LR_LAUNCHD_AGENTS_DIR/com.claude.accounts-local.plist" "$FAKE/com.claude.accounts-local"
  run bash "$SUT" --confirm keepwarm-band
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"com.claude.accounts-local: not installed"*"skipped"* ]] || { echo "$output"; false; }
  ! grep -E -q '^(bootout|bootstrap|kickstart|enable) .*accounts-local' "$FAKE_LOG" || { cat "$FAKE_LOG"; false; }
  [ ! -e "$LR_LAUNCHD_AGENTS_DIR/com.claude.accounts-local.plist" ]
  grep -q "^bootstrap gui/[0-9]* $LR_LAUNCHD_AGENTS_DIR/com.claude.accounts-keepwarm.plist\$" "$FAKE_LOG"
}

@test "keepwarm: a tick in flight holds the reload (bounded), and nothing is reloaded" {
  kw_setup
  sleep 30 & echo $! > "$FAKE/com.claude.accounts-keepwarm.pid"
  run bash "$SUT" --confirm keepwarm-band
  [ "$status" -eq 1 ] || { echo "$output"; false; }
  [[ "$output" == *"tick ran for 5s; nothing reloaded"* ]] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}

@test "--now is refused for the keepwarm target" {
  kw_setup
  run bash "$SUT" --confirm keepwarm-band --now
  [ "$status" -eq 2 ] || { echo "$output"; false; }
  ! grep -q 'bootout\|bootstrap' "$FAKE_LOG" 2>/dev/null
}
