#!/usr/bin/env bats
# bin/cc-lr rotate / recover --limited — a recover the LIVE reconciler takes is counted and named
# (lr-reliability 2026-10-10 REPORT D6 / rank 10, wave A item A4).
#
# The defect, measured on one live `rotate --all`: `0 rotated · 0 not · 7 still in flight` with 3
# QUEUED recovers uncounted, and a queued-only rotate said "nothing was started", rc 1. cmd_recover
# returned before it recorded the row, so rotate never saw what the reconciler had been handed.
#
# HERMETIC: HOME, LR_STATE_DIR, LR_RECON_ROOT in BATS_TEST_TMPDIR; cc-find, lr-fleet, the router,
# the census and launchctl are stubs; the reconciler is "live" by its heartbeat seam. Nothing types.

NOW=1790000500

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LR="$REPO/bin/cc-lr"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export LR_MOVE_ENV_DIR="$BATS_TEST_TMPDIR/penv"; mkdir -p "$LR_MOVE_ENV_DIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/state"; mkdir -p "$LR_STATE_DIR"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"; mkdir -p "$LR_RECON_ROOT/owned"
  export LR_RECON_NOW="$NOW" LR_RECON_WAKETIME=0
  export CC_LR_FIND_BIN="$BATS_TEST_TMPDIR/cc-find"
  export CC_LR_FLEET_BIN="$BATS_TEST_TMPDIR/lr-fleet.sh"
  export CC_LR_HANDOFF_BIN="$BATS_TEST_TMPDIR/lr-handoff.sh"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/claude-accounts"
  export CC_LR_UPGRADE_BIN="$BATS_TEST_TMPDIR/lr-upgrade.sh"
  export CC_LR_POLLER_LABEL="com.reso.lr-reset-poller"
  STUBBIN="$BATS_TEST_TMPDIR/stubbin"; mkdir -p "$STUBBIN"
  PATH="$STUBBIN:$PATH"; export PATH
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/launchctl.argv"\n' "$BATS_TEST_TMPDIR" > "$STUBBIN/launchctl"
  for s in "$CC_LR_FLEET_BIN" "$CC_LR_HANDOFF_BIN" "$CC_LR_UPGRADE_BIN"; do
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/%s.argv"\nexit 0\n' "$BATS_TEST_TMPDIR" "$(basename "$s")" > "$s"
  done
  # next3 has headroom, so rotate --account next3 is its limited session's recover and nothing else.
  cat > "$CC_ACCOUNTS_BIN" <<SH
#!/usr/bin/env bash
case " \$* " in
  *" --json "*) printf '{"rows":[{"acct":"next3","weekly_pct":40,"session_pct":1}]}\n'; exit 0 ;;
  *" --rank "*) printf 'next2 3\n'; exit 0 ;;
esac
exit 97
SH
  cat > "$CC_LR_FIND_BIN" <<SH
#!/usr/bin/env bash
row="dddd0310-0000-4000-8000-000000000310	310	claude-tertiary	$HOME/.claude-tertiary	/y	live	LIMITED"
if [ "\$1" = --limited ]; then printf '%s\n' "\$row"; exit 0; fi
case "\$row" in "\$1"*) printf '%s\n' "\$row"; exit 0 ;; esac
exit 1
SH
  chmod +x "$STUBBIN/launchctl" "$CC_ACCOUNTS_BIN" "$CC_LR_FIND_BIN" "$CC_LR_FLEET_BIN" "$CC_LR_HANDOFF_BIN" "$CC_LR_UPGRADE_BIN"
  unset CLAUDE_CODE_SESSION_ID CC_PANE_ID ITERM_SESSION_ID KITTY_WINDOW_ID
}

recon_live() {
  : > "$LR_STATE_DIR/recon.on"
  printf '{"pid":1,"progress":7,"progress_wall":%s}' "$NOW" > "$LR_RECON_ROOT/heartbeat"
}

@test "rotate whose only recover the reconciler QUEUED counts it, names it, and is rc 0 — never 'nothing was started'" {
  recon_live
  run bash "$LR" rotate --account next3 --no-wait
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" != *"nothing was started"* ]] || { echo "$output"; false; }
  [[ "$output" == *"cc-lr rotate: 0 rotated · 0 not · 0 still in flight"* ]] || { echo "$output"; false; }
  [[ "$output" == *"cc-lr rotate: 1 queued for the reconciler"* ]] || { echo "$output"; false; }
  [[ "$output" == *"    cc-lr status dddd0310"* ]] || { echo "$output"; false; }
  [ -f "$LR_STATE_DIR/requests/dddd0310-0000-4000-8000-000000000310.cc-lr.json" ]
  [ ! -e "$BATS_TEST_TMPDIR/lr-fleet.sh.argv" ] || { echo "a recovery was fired beside the queue"; false; }
}

@test "recover --limited says how many of the fired were only QUEUED for the reconciler" {
  recon_live
  run bash "$LR" recover --limited --account next3
  [ "$status" -eq 0 ] || { echo "rc $status: $output"; false; }
  [[ "$output" == *"1 fired, 0 refused of 1 limited session(s) on next3 (1 of the fired QUEUED for the reconciler"* ]] || { echo "$output"; false; }
}

@test "CONTROL — with the reconciler NOT live the same rotate fires the recover and prints no queued line" {
  run bash "$LR" rotate --account next3 --no-wait
  grep -q dddd0310 "$BATS_TEST_TMPDIR/lr-fleet.sh.argv" || { echo "not fired"; echo "$output"; false; }
  [[ "$output" != *"queued for the reconciler"* ]] || { echo "$output"; false; }
}
