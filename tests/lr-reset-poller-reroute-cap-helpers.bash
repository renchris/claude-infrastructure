# Shared fixture for tests/lr-reset-poller-reroute-cap*.bats (decision 1dc45a0d583c, the reroute cap).
#
# ONE TICK PER FILE (setup_file), one sid per case with its cap state SEEDED as earlier ticks would
# have left it: the off-box bound is 300 s per suite and the parked loop costs 20-40 s PER RECORD at
# load 600 (measured 2026-10-12: 8 records took 247 s), so each file keeps to 3-4 parked records —
# the 2026-10-11 lesson of tests/lr-reset-poller-parked-gates.bats. The tick runs under /bin/bash,
# launchd's 3.2 interpreter. lr-page runs for real with its osascript seam stubbed.

cap_env() { # → the hermetic store, stubs and the verdict strings; call first in setup_file
  export LR_UPGRADE_AUTO=off LR_POLLER_NO_CENSUS=1
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_FILE_TMPDIR/home"
  export STATE="$HOME/.reso/limit-recover"
  local stubs="$BATS_FILE_TMPDIR/stubs"
  mkdir -p "$HOME/bin" "$HOME/.claude" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$STATE/reroute" \
           "$STATE/results" "$STATE/requests" "$STATE/recon/sessions" "$stubs"
  export CC_REGISTRY_DIR="$BATS_FILE_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_FILE_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_FILE_TMPDIR/no-kitty-socket"
  export LR_CC_TUI_LIB="$BATS_FILE_TMPDIR/absent-cc-tui.sh"
  unset KITTY_WINDOW_ID CC_TERM_KITTY_TO CC_ACCOUNTS_BIN LR_POLLER_REROUTE LR_REROUTE_EVERY_MIN LR_REROUTE_MAX_SAME LR_REROUTE_CAP
  unset PUSHOVER_TOKEN PUSHOVER_USER
  printf '#!/bin/bash\nexit 1\n' > "$stubs/osascript"; chmod +x "$stubs/osascript"
  export PATH="$stubs:$PATH"
  printf '#!/bin/bash\ncase " $* " in *" --rank "*) echo "next2 0.8"; exit 0 ;; esac\necho "{\\"rows\\":[]}"\n' > "$HOME/bin/claude-accounts"
  chmod +x "$HOME/bin/claude-accounts"
  # Run dirs under a SHORT path: a real evidence path (~/.reso/limit-recover/fleet/one-<ts>-<sid8>)
  # is ~75 chars, and the off-box TMPDIR alone is ~130, which would push it past lr-page's 200-char cut.
  RUNS="$(mktemp -d /tmp/lrc.XXXXXX)"; export RUNS
  export FLEET_LOG="$BATS_FILE_TMPDIR/fleet.log"; : > "$FLEET_LOG"
  export LR_FLEET_BIN="$stubs/lr-fleet"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\necho "lr-fleet: DETACHED — driver pid 99999 is recovering; the verdict arrives as mail."\n' "$FLEET_LOG" > "$LR_FLEET_BIN"
  chmod +x "$LR_FLEET_BIN"
  # lr-page for real; its Notification Center leg records argv and FAILS for sid prefix 1dc45a07 only.
  export LR_PAGE_OS_CHANNEL=on LR_PAGE_OSASCRIPT_BIN="$stubs/page-osa" LR_PAGE_LOG="$BATS_FILE_TMPDIR/pages.log"
  export LR_PAGE_PUSH_BIN="$stubs/no-push" PAGE_ARGV="$BATS_FILE_TMPDIR/page.argv"; : > "$PAGE_ARGV"
  printf '#!/bin/bash\ncat >/dev/null; printf "%%s\\n" "$*" >> "%s"\ncase "$*" in *1dc45a07*) exit 1 ;; esac\nexit 0\n' "$PAGE_ARGV" > "$LR_PAGE_OSASCRIPT_BIN"
  chmod +x "$LR_PAGE_OSASCRIPT_BIN"
  : > "$STATE/autorecover.on"
  export R_FAIL="FAILED recycle-in-place/FAILED lr-handoff rc=2"
  export V_FAIL="verdict=FAILED rc=6 pane=- acct=next4 mech=recycle-in-place/FAILED — lr-handoff rc=2;"
  export V_PARK="verdict=PARKED rc=1 pane=- acct=next4 mech=parked — no routable target: router timed out;"
  export V_OK="verdict=RECOVERED rc=0 pane=36 acct=next2 mech=nudge-in-place/RECOVERED — -;"
}
run_tick() { # one tick under launchd's interpreter; rc and output kept for the first case
  LR_POLLER_AUTOFIRE=1 /bin/bash "$POLLER" --once > "$BATS_FILE_TMPDIR/tick.out" 2>&1
  echo "$?" > "$BATS_FILE_TMPDIR/tick.rc"
}
cap_teardown() { [ -n "${RUNS:-}" ] && [[ "$RUNS" == /tmp/lrc.* ]] && rm -rf "$RUNS"; return 0; }

park_rec() { # <sid> — the § 1 record shape, reset far in the future so § 2a is the arm that sees it
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"weekly","reset_at_utc":"2099-01-01T00:00:00Z","parked_at":"2026-10-04T07:00:00Z"}\n' \
    "$1" "$HOME/.claude" "$BATS_FILE_TMPDIR" > "$STATE/parked/$1.json"
}
seed() { printf '%s\t%s\t%s\n' "$2" "$RUNS/prev-$1" "$3" > "$STATE/reroute/$1.tries"; } # <sid> <n> <reason>
last_run() { # <sid> <verdict tail> — the sid's last dispatch names a run whose verdict.txt says it
  local d="$RUNS/$1"; mkdir -p "$d"
  printf 'lr-fleet --one %s: %s evidence: %s\n' "${1:0:8}" "$2" "$d" > "$d/verdict.txt"
  printf 'lr-fleet: DETACHED — driver pid 99999\nrun=%s log=%s/detached.log\n' "$d" "$d" > "$STATE/results/$1.log"
}
plog() { cat "$STATE/poller.log" >&2 2>/dev/null || true; }
dispatched() { grep -c -- "--one $1" "$FLEET_LOG"; }
pages_for() { grep -c "^- reroute stopped Session ${1:0:8} " "$PAGE_ARGV"; }
