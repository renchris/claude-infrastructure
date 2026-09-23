#!/usr/bin/env bats
# lr-reset-poller.sh § 0 — THE REQUEST LANE (W5-A, LIMIT_RECOVER_100P, 2026-09-20).
#
# Four defects, all live before this wave, and one new policy gate:
#   (1) the worker ran in the FOREGROUND inside the tick lock. lr-fleet prices `--one` at 115-658 s
#       (lr-fleet.sh:725), so ONE request held LOCKD for minutes and every concurrent tick
#       TICK-SKIPped. `--detach` (lr-fleet.sh:739-768) returns in <= 3 s and mails the verdict.
#   (2) nothing reserved the sid between reading the record and driving it, so two ticks could
#       drive one sid twice. `mkdir` is the atomic reservation that `: >` (claim_sid, :225) is not.
#   (3) the glob is `*.json` and the transplant arm writes `retire-husk-<sid>.json` into the SAME
#       directory, so a husk breadcrumb was executed as a recovery.
#   (4) a drained request was `rm -f`'d, leaving no evidence it had ever reached this daemon.
#   (5) NEW, safety-critical: hooks/stop-failure-marker.sh will write a request on every rate-limit
#       death and ~30 sessions die at once on one cap. Draining that cohort unattended is an OPEN
#       operator decision (85% conviction, shipped default OFF — LIMIT_RECOVER_100P.md:384), so a
#       hook-originated request is drained ONLY when $STATE/autorecover.on exists. FAIL CLOSED.
#
# The suite builds every fixture. The live store is never read (requests/ 0, results/ 22 today —
# a population that is nearly empty is not a control, it is an absence).

setup() {
  # The upgrade auto-trigger (lr-upgrade.sh --auto-enqueue) is its own suite's subject
  # (tests/lr-upgrade.bats); here it would run a live census and could detach a real drainer.
  export LR_UPGRADE_AUTO=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$BATS_TEST_TMPDIR/stubs"
  SID="52e35019-17e8-40f6-a54f-3a04de70d2e6"
  # Seams: no census fork, no registry, no kitty, no GUI. This suite is about § 0 only, which runs
  # immediately after the tick lock and before every other arm.
  export LR_POLLER_NO_CENSUS=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  unset KITTY_WINDOW_ID CC_TERM_KITTY_TO
  printf '#!/bin/bash\nexit 1\n' > "$BATS_TEST_TMPDIR/stubs/osascript"
  cat > "$HOME/bin/claude-accounts" <<'STUB'
#!/bin/bash
echo '{"rows":[{"acct":"next4","session_pct":12,"weekly_pct":40}]}'
STUB
  chmod +x "$BATS_TEST_TMPDIR/stubs/osascript" "$HOME/bin/claude-accounts"
  export PATH="$BATS_TEST_TMPDIR/stubs:$PATH"

  # ── the lr-fleet stub REPRODUCES THE REAL --detach CONTRACT ─────────────────────────────────
  # A stub that ignored --detach would make the timing case below pass for a poller that never
  # passes the flag — the arm would be pinned by nothing. This one behaves as lr-fleet.sh:739-768
  # does: with --detach it returns at once having started a driver; without it, it BLOCKS.
  export LR_FLEET_BIN="$BATS_TEST_TMPDIR/stubs/lr-fleet"
  cat > "$LR_FLEET_BIN" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "${FLEET_LOG:?}"
_d=0; for _a in "$@"; do [ "$_a" = "--detach" ] && _d=1; done
if [ "$_d" = 1 ]; then
  echo "lr-fleet: DETACHED — driver pid 4242 is recovering; the verdict arrives as mail."
  echo "run=/nowhere/run log=/nowhere/run/detached.log"
  exit "${FLEET_DETACH_RC:-0}"
fi
sleep "${FLEET_FG_SLEEP:-0}"
echo "fleet ran in the FOREGROUND"
exit "${FLEET_RC:-0}"
STUB
  chmod +x "$LR_FLEET_BIN"
  export FLEET_LOG="$BATS_TEST_TMPDIR/fleet.log"; : > "$FLEET_LOG"

  # ── the cc-tui.sh seam. SET but pointing nowhere is the shipped state until W5-E converges. ──
  export LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  export TUI_LOG="$BATS_TEST_TMPDIR/tui.log"; : > "$TUI_LOG"
}

rq() { # $1=basename (without .json) ; stdin = the record
  mkdir -p "$STATE/requests"
  cat > "$STATE/requests/$1.json"
}
tick() { LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once; }
plog() { cat "$STATE/poller.log" >&2; }
mk_tui() { # a cc-tui.sh that records its two arguments and returns ${TUI_RC:-0}
  export LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/cc-tui.sh"
  cat > "$LR_CC_TUI_LIB" <<'STUB'
cc_tui_submit() {
  printf 'pane=%s\n' "$1" >> "${TUI_LOG:?}"
  printf 'prompt=%s\n' "$(cat "$2")" >> "$TUI_LOG"
  return "${TUI_RC:-0}"
}
STUB
}

# ══ 1. THE WORKER RUNS OFF THE LOCK ════════════════════════════════════════════════════════════

@test "detach: the dispatched argv carries --detach beside every flag it already carried" {
  rq "$SID" <<EOF
{"sid":"$SID","target":"next3","source_pane":"616","requested_by":"driver-abc"}
EOF
  tick
  [ "$status" -eq 0 ]
  grep -q -- "--one $SID --target next3 --source-pane 616 --from-daemon --detach" "$FLEET_LOG" \
    || { cat "$FLEET_LOG"; false; }
}

@test "detach RED-PROOF: a worker that blocks for 20 s does not hold the tick" {
  # THE MEASUREMENT THAT MATTERS. Remove `--detach` from the poller's argv and this stub blocks for
  # 20 s inside LOCKD — which is the pre-wave behaviour, scaled down from lr-fleet's real 115-658 s.
  export FLEET_FG_SLEEP=20
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  local t0 t1
  t0=$(date +%s); tick; t1=$(date +%s)
  [ "$status" -eq 0 ]
  [ $(( t1 - t0 )) -le 8 ] || { echo "tick took $(( t1 - t0 ))s — the worker is still on the lock"; false; }
}

@test "detach: a dispatch that FAILS releases the claim, because nothing is in flight to guard" {
  export FLEET_DETACH_RC=2
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  [ ! -d "$STATE/runs/by-sid/$SID.active" ] || { ls -la "$STATE/runs/by-sid"; false; }
  grep -q "REQUEST $SID — dispatch-failed rc=2" "$STATE/poller.log" || { plog; false; }
}

# ══ 2. A REAL PER-SID CLAIM ════════════════════════════════════════════════════════════════════

@test "claim: a drained request leaves an .active claim and lands in claimed/, never deleted" {
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  [ "$status" -eq 0 ]
  [ -d "$STATE/runs/by-sid/$SID.active" ]
  [ -f "$STATE/claimed/$SID.json" ] || { ls -la "$STATE/claimed" 2>&1; false; }
  [ ! -e "$STATE/requests/$SID.json" ]
}

@test "claim: two ticks over one request — exactly one claims, the other is SUPERSEDED-BY-LIVE-RUN" {
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick; [ "$status" -eq 0 ]
  [ "$(grep -c . "$FLEET_LOG")" = 1 ] || { cat "$FLEET_LOG"; false; }
  # the same sid asked for again while the first run is still in flight
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick; [ "$status" -eq 0 ]
  grep -q "SUPERSEDED-BY-LIVE-RUN $SID" "$STATE/poller.log" || { plog; false; }
  [ "$(grep -c . "$FLEET_LOG")" = 1 ] || { echo "the second tick drove the sid a second time"; cat "$FLEET_LOG"; false; }
}

@test "claim CONTROL: a claim older than the TTL is retaken — a dead driver must not wedge the sid" {
  mkdir -p "$STATE/runs/by-sid/$SID.active"
  python3 - "$STATE/runs/by-sid/$SID.active" <<'PY'
import os,sys,time
old = time.time() - 3*3600
os.utime(sys.argv[1], (old, old))
PY
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  grep -q "RUN-CLAIM-STALE $SID" "$STATE/poller.log" || { plog; false; }
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; false; }
}

@test "claim CONTROL: a FRESH claim inside the TTL is honoured, not retaken" {
  mkdir -p "$STATE/runs/by-sid/$SID.active"
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  grep -q "SUPERSEDED-BY-LIVE-RUN $SID" "$STATE/poller.log" || { plog; false; }
}

# ══ 3. THE HOOK-ORIGIN POLICY GATE — the red proof ═════════════════════════════════════════════

@test "autorecover: a stop-failure-marker request is NOT drained without the flag, and is LEFT in place" {
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"stop-failure-marker"}
EOF
  tick
  [ "$status" -eq 0 ]
  [ ! -s "$FLEET_LOG" ] || { echo "a hook-originated request was auto-transplanted"; cat "$FLEET_LOG"; false; }
  [ -f "$STATE/requests/$SID.json" ] || { echo "the breadcrumb cc-find --limited reads was consumed"; false; }
  [ ! -d "$STATE/runs/by-sid/$SID.active" ]
  [ ! -e "$STATE/claimed/$SID.json" ]
  grep -q "HOOK-HELD 1 hook-originated request(s) NOT drained" "$STATE/poller.log" || { plog; false; }
}

@test "autorecover: WITH the flag the same request drains" {
  : > "$STATE/autorecover.on"
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"stop-failure-marker"}
EOF
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
  [ -f "$STATE/claimed/$SID.json" ]
}

@test "autorecover CONTROL: any other requester is unaffected by the gate" {
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"stop-failure-marker-lookalike"}
EOF
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
  ! grep -q "HOOK-HELD" "$STATE/poller.log"
}

@test "autorecover: the poller NEVER creates the flag file — its absence is the shipped default" {
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"stop-failure-marker"}
EOF
  tick
  [ ! -e "$STATE/autorecover.on" ] || { echo "the daemon granted itself the permission"; false; }
}

@test "autorecover: a whole cohort is held and reported as ONE line, not one line per request" {
  local i s
  for i in 1 2 3; do
    s="0000000$i-0000-4000-8000-00000000000$i"
    rq "$s" <<EOF
{"sid":"$s","requested_by":"stop-failure-marker"}
EOF
  done
  tick
  [ "$(grep -c 'HOOK-HELD' "$STATE/poller.log")" = 1 ] || { plog; false; }
  grep -q "HOOK-HELD 3 hook-originated request(s)" "$STATE/poller.log" || { plog; false; }
  local kept=0 f
  for f in "$STATE/requests"/*.json; do [ -e "$f" ] && kept=$(( kept + 1 )); done
  [ "$kept" = 3 ] || { echo "requests/ holds $kept, not 3"; false; }
}

# ══ 4. DISPATCH ON SHAPE, NEVER ON THE GLOB ════════════════════════════════════════════════════

@test "kind: a retire-husk breadcrumb is FILED, never executed as a recovery" {
  # The live defect: § 2's transplant arm writes this into $REQUESTS and the glob drove it through
  # `lr-fleet --one` — a request to CLOSE a pane, executed as a request to RECOVER a session.
  rq "retire-husk-$SID" <<EOF
{"kind":"retire-husk","sid":"$SID","pane":"616","cfg":"$HOME/.claude-quaternary","to":"$HOME/.claude-tertiary","ts":"x"}
EOF
  tick
  [ ! -s "$FLEET_LOG" ] || { echo "a husk breadcrumb was executed as a recovery"; cat "$FLEET_LOG"; false; }
  [ -f "$STATE/husk-requests/retire-husk-$SID.json" ]
  [ ! -e "$STATE/requests/retire-husk-$SID.json" ]
  grep -q "HUSK-REQUEST $SID — filed" "$STATE/poller.log" || { plog; false; }
}

@test "kind CONTROL: an explicit kind:recovery still takes the relaunch path" {
  rq "$SID" <<EOF
{"kind":"recovery","sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; false; }
}

@test "kind: an unknown kind is PARKED, not driven" {
  rq "$SID" <<EOF
{"kind":"teleport","sid":"$SID"}
EOF
  tick
  [ ! -s "$FLEET_LOG" ]
  [ -f "$STATE/results/$SID.unknown-kind.json" ]
}

@test "mode: an unknown mode is PARKED, not driven" {
  rq "$SID" <<EOF
{"sid":"$SID","mode":"interpretive-dance"}
EOF
  tick
  [ ! -s "$FLEET_LOG" ]
  [ -f "$STATE/results/$SID.unknown-mode.json" ]
}

@test "mode: absent .mode defaults to the recovery path" {
  rq "$SID" <<EOF
{"sid":"$SID"}
EOF
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; false; }
}

@test "mode:prompt with no cc-tui.sh on this layer SKIPS LOUDLY and leaves the request for the next tick" {
  # An ADD is inert until a converge runs install.sh; a `[ -f x ] && . x` guard over an absent file
  # is a silent skip, and silence here would look like a recovery that happened.
  rq "$SID" <<EOF
{"sid":"$SID","mode":"prompt","source_pane":"616","requested_by":"driver-abc"}
EOF
  tick
  [ ! -s "$FLEET_LOG" ] || { echo "mode:prompt fell through to a relaunch"; cat "$FLEET_LOG"; false; }
  [ -f "$STATE/requests/$SID.json" ]
  grep -q "REQUEST-SKIP $SID — mode:prompt needs scripts/lib/cc-tui.sh" "$STATE/poller.log" || { plog; false; }
}

@test "mode:prompt types the prompt into the named pane and records the verdict" {
  mk_tui
  rq "$SID" <<EOF
{"sid":"$SID","mode":"prompt","source_pane":"616","prompt":"/limit-recover","requested_by":"driver-abc"}
EOF
  tick
  [ "$status" -eq 0 ]
  grep -q '^pane=616$' "$TUI_LOG" || { cat "$TUI_LOG"; plog; false; }
  grep -q '^prompt=/limit-recover$' "$TUI_LOG" || { cat "$TUI_LOG"; false; }
  [ ! -s "$FLEET_LOG" ]
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["mode"]=="prompt" and d["verdict"]=="submitted", d' \
    "$STATE/results/$SID.json"
}

@test "mode:prompt maps cc_tui_submit's rc onto a NAMED verdict, and frees the sid" {
  mk_tui; export TUI_RC=3
  rq "$SID" <<EOF
{"sid":"$SID","mode":"prompt","source_pane":"616","requested_by":"driver-abc"}
EOF
  tick
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["verdict"]=="composer-occupied" and d["rc"]==3, d' \
    "$STATE/results/$SID.json"
  # synchronous: nothing is in flight afterwards, whatever the verdict
  [ ! -d "$STATE/runs/by-sid/$SID.active" ]
}

@test "mode:prompt without .source_pane is malformed, not a guess" {
  mk_tui
  rq "$SID" <<EOF
{"sid":"$SID","mode":"prompt"}
EOF
  tick
  [ ! -s "$TUI_LOG" ] || { cat "$TUI_LOG"; false; }
  [ -f "$STATE/results/$SID.malformed.json" ]
}

# ══ the reader itself ══════════════════════════════════════════════════════════════════════════

@test "reader: a record with no .sid is parked as malformed and never retried" {
  rq "nosid" <<'EOF'
{"target":"next3"}
EOF
  tick
  [ -f "$STATE/results/nosid.malformed.json" ]
  [ ! -e "$STATE/requests/nosid.json" ]
}

@test "reader FAIL-CLOSED: an unparseable record is malformed, not a record of all-defaults" {
  # The four `jq -r … // default` forks this replaced turned a corrupt file into a request with
  # target=auto and requested_by=?, i.e. a real recovery driven off bytes nobody could read.
  rq "corrupt" <<'EOF'
{"sid": "abc", not json at all
EOF
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  [ -f "$STATE/results/corrupt.malformed.json" ]
}

@test "reader: --dry-run still reports and executes nothing (the pre-wave contract, unchanged)" {
  rq "$SID" <<EOF
{"sid":"$SID","target":"next3"}
EOF
  LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once --dry-run
  [ -f "$STATE/requests/$SID.json" ]
  [ ! -s "$FLEET_LOG" ]
  grep -qE "DRY +request $SID.json would be executed" "$STATE/poller.log" || { plog; false; }
}
