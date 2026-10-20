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
  *) exit 64 ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/launchctl"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

teardown() {
  if [ -f "$FAKE/com.reso.lr-reconciler.pid" ]; then kill "$(cat "$FAKE/com.reso.lr-reconciler.pid")" 2>/dev/null || true; fi
  return 0
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
