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
  echo "lr-fleet: DETACHED — driver pid ${FLEET_DRIVER_PID:-4242} is recovering; the verdict arrives as mail."
  echo "run=/nowhere/run log=/nowhere/run/detached.log"
  exit "${FLEET_DETACH_RC:-0}"
fi
sleep "${FLEET_FG_SLEEP:-0}"
echo "fleet ran in the FOREGROUND"
exit "${FLEET_RC:-0}"
STUB
  chmod +x "$LR_FLEET_BIN"
  export FLEET_LOG="$BATS_TEST_TMPDIR/fleet.log"; : > "$FLEET_LOG"
  # The "driver" the stub names must be ALIVE for as long as the case runs: the poller re-stamps the
  # claim with it (D2), and a dead one is stolen at once. The bats process outlives every tick.
  export FLEET_DRIVER_PID="$$"

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
# A hook request is re-checked against its transcript at drain time (D3), so a hook-origin fixture
# needs a session that is really LIMITED on disk. Prints the transcript path.
lim_tx() { # $1=sid
  local d="$HOME/.claude-tertiary/projects/-Users-x-proj"; mkdir -p "$d"
  printf '{"type":"assistant","timestamp":"2026-09-28T03:00:00Z","isApiErrorMessage":true,"error":"rate_limit","message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit · resets Oct 1"}]}}\n' > "$d/$1.jsonl"
  printf '%s' "$d/$1.jsonl"
}
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

@test "claim CONTROL: a holder-less claim with no live driver is retaken — a dead driver must not wedge the sid" {
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
  grep -q "RUN-CLAIM-ORPHAN $SID" "$STATE/poller.log" || { plog; false; }
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; false; }
}

@test "claim CONTROL: a FRESH holder-less claim inside the stamp window is honoured, not retaken" {
  mkdir -p "$STATE/runs/by-sid/$SID.active"
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  grep -q "SUPERSEDED-BY-LIVE-RUN $SID" "$STATE/poller.log" || { plog; false; }
}

# THE 2026-09-26 WEDGE (pane 780, ac0f0123). cc-lr re-stamps the claim's holder with the detached
# driver's pid, and nothing releases it when that driver exits. The poller read only the claim's AGE,
# so for 30 minutes after the driver died every repair request was dropped as SUPERSEDED-BY-LIVE-RUN
# (21:02:51Z and 21:05:29Z) while the holder named pid 85261, already dead. cc-lr and lr-fleet both
# steal a dead holder at once; the poller must read the same fact.
@test "[RED] claim: a FRESH claim whose holder pid is DEAD is retaken, not honoured" {
  mkdir -p "$STATE/runs/by-sid/$SID.active"
  sleep 0 & dead=$!; wait "$dead" || true
  printf '{"sid":"%s","pane":"780","pid":%d,"ts":"2026-09-26T21:01:19Z","by":"lr-fleet --one --detach"}\n' \
    "$SID" "$dead" > "$STATE/runs/by-sid/$SID.active/holder"
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG" 2>/dev/null; plog; false; }
  ! grep -q "SUPERSEDED-BY-LIVE-RUN $SID" "$STATE/poller.log" || { plog; false; }
  grep -q "RUN-CLAIM-DEAD-HOLDER $SID" "$STATE/poller.log" || { plog; false; }
}

@test "claim CONTROL: a FRESH claim whose holder pid is ALIVE is honoured" {
  mkdir -p "$STATE/runs/by-sid/$SID.active"
  printf '{"sid":"%s","pane":"780","pid":%d,"by":"lr-fleet --one --detach"}\n' "$SID" "$$" \
    > "$STATE/runs/by-sid/$SID.active/holder"
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
{"sid":"$SID","requested_by":"stop-failure-marker","transcript_path":"$(lim_tx "$SID")"}
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
{"sid":"$SID","requested_by":"stop-failure-marker","transcript_path":"$(lim_tx "$SID")"}
EOF
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
  # D3: a hook request stays queued, attempt recorded, until the session is seen recovered
  [ "$(jq -r .attempts "$STATE/requests/$SID.json")" = 1 ] || { plog; false; }
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
{"sid":"$SID","requested_by":"stop-failure-marker","transcript_path":"$(lim_tx "$SID")"}
EOF
  tick
  [ ! -e "$STATE/autorecover.on" ] || { echo "the daemon granted itself the permission"; false; }
}

@test "autorecover: a whole cohort is held and reported as ONE line, not one line per request" {
  local i s
  for i in 1 2 3; do
    s="0000000$i-0000-4000-8000-00000000000$i"
    rq "$s" <<EOF
{"sid":"$s","requested_by":"stop-failure-marker","transcript_path":"$(lim_tx "$s")"}
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

# ── D2 (2026-09-28): one claim format, and it names a pid that lives as long as the work ────────
# THE INCIDENT: REROUTE retook 415a3aac in the poller's old shape (a directory, NO holder), its
# detached driver died at once, and cc-lr's retry was refused "names no pid; 421s old" until a
# 30-minute TTL. The operator ran the rmdir. These cases pin the shape that makes that impossible.
age_claim() { # $1=seconds old
  python3 - "$STATE/runs/by-sid/$SID.active" "$1" <<'PY2'
import os,sys,time
t = time.time() - int(sys.argv[2]); os.utime(sys.argv[1], (t, t))
PY2
}

@test "[RED] D2: a holder-less claim 421 s old with no live driver is retaken at once, not after 30 min" {
  mkdir -p "$STATE/runs/by-sid/$SID.active"; age_claim 421
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
  grep -q "RUN-CLAIM-ORPHAN $SID" "$STATE/poller.log" || { plog; false; }
}

@test "D2 CONTROL: a holder-less claim is honoured while a live recovery driver names the sid" {
  mkdir -p "$STATE/runs/by-sid/$SID.active"; age_claim 421
  mkdir -p "$BATS_TEST_TMPDIR/fake/limit-recover"
  printf '#!/bin/bash\nsleep 30\n' > "$BATS_TEST_TMPDIR/fake/limit-recover/lr-fleet.sh"
  bash "$BATS_TEST_TMPDIR/fake/limit-recover/lr-fleet.sh" --one "$SID" & drv=$!
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  kill "$drv" 2>/dev/null || true
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  grep -q "SUPERSEDED-BY-LIVE-RUN $SID" "$STATE/poller.log" || { plog; false; }
}

@test "[RED] D2: after a dispatch the claim's holder names the DETACHED driver's pid" {
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  grep -q "\"pid\":$FLEET_DRIVER_PID," "$STATE/runs/by-sid/$SID.active/holder" \
    || { cat "$STATE/runs/by-sid/$SID.active/holder" 2>&1; plog; false; }
}

@test "D2: a dispatch that names no driver pid releases the claim — nothing is left to wedge the sid" {
  cat > "$LR_FLEET_BIN" <<'STUB'
printf '%s\n' "$*" >> "${FLEET_LOG:?}"
echo "lr-fleet: something printed, but no driver line"
exit 0
STUB
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  [ ! -e "$STATE/runs/by-sid/$SID.active" ] || { ls -la "$STATE/runs/by-sid/$SID.active"; plog; false; }
  grep -q "RUN-CLAIM-RELEASED $SID" "$STATE/poller.log" || { plog; false; }
}

@test "D2: a failed dispatch releases the claim" {
  export FLEET_DETACH_RC=2
  rq "$SID" <<EOF
{"sid":"$SID","requested_by":"driver-abc"}
EOF
  tick
  [ ! -e "$STATE/runs/by-sid/$SID.active" ] || { plog; false; }
}

# ══ W6b (LIMIT_RECOVER_FLEET_V2): STAY NEAR THE RESET (D1.4) AND PACE THE COHORT (D1.6) ═════════
hook_rq() { # $1=sid $2=account $3=reset epoch (optional)
  # The optional key is built OUTSIDE the heredoc: `${3:+…"…"}` inside one loses its inner quotes.
  local extra=""; [ -n "${3:-}" ] && extra=",\"reset_at_epoch\":\"$3\""
  rq "$1" <<JSON
{"sid":"$1","requested_by":"stop-failure-marker","account":"$2","transcript_path":"$(lim_tx "$1")"$extra}
JSON
}
cohort_sid() { printf '0000000%s-0000-4000-8000-0000000000%02d' "$(( $1 % 10 ))" "$1"; }

@test "[D1.4] a hook request whose account resets inside 15 min STAYS queued — no dispatch, no attempt spent" {
  : > "$STATE/autorecover.on"
  hook_rq "$SID" next3 "$(( $(date +%s) + 300 ))"
  tick
  [ ! -s "$FLEET_LOG" ] || { echo "moved minutes before its reset: $(cat "$FLEET_LOG")"; false; }
  [ "$(jq -r '.attempts // "none"' "$STATE/requests/$SID.json")" = none ] || { cat "$STATE/requests/$SID.json"; false; }
  grep -q "REQUEST-STAY $SID (next3) — its account resets in" "$STATE/poller.log" || { plog; false; }
}

@test "D1.4 CONTROL: a reset further than 15 min away, or already past, is dispatched as before" {
  : > "$STATE/autorecover.on"
  local s2; s2="$(cohort_sid 2)"
  hook_rq "$SID" next3 "$(( $(date +%s) + 1200 ))"
  hook_rq "$s2" next3 "$(( $(date +%s) - 60 ))"
  tick
  grep -q -- "--one $SID" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
  grep -q -- "--one $s2" "$FLEET_LOG" || { cat "$FLEET_LOG"; plog; false; }
  ! grep -q 'REQUEST-STAY' "$STATE/poller.log"
}

@test "[D1.6] a 6-death cohort on ONE account dispatches 4 this tick; 2 stay queued, unspent, with depth and ETA" {
  : > "$STATE/autorecover.on"
  local i
  for i in 1 2 3 4 5 6; do hook_rq "$(cohort_sid "$i")" next3; done
  tick
  [ "$(grep -c -- '--one ' "$FLEET_LOG")" = 4 ] || { cat "$FLEET_LOG"; plog; false; }
  local unspent=0 f
  for f in "$STATE/requests"/*.json; do [ "$(jq -r '.attempts // 0' "$f")" = 0 ] && unspent=$(( unspent + 1 )); done
  [ "$unspent" = 2 ] || { echo "unspent=$unspent"; false; }
  grep -q "REQUEST-QUEUED 2 request(s) over the 4/account/tick cap left queued (by account: next3=2); queue depth 2, ETA ~15 min" "$STATE/poller.log" || { plog; false; }
}

@test "D1.6: the cap is PER ACCOUNT — 4 on next3 and 2 on next4 all go in one tick" {
  : > "$STATE/autorecover.on"
  local i
  for i in 1 2 3 4; do hook_rq "$(cohort_sid "$i")" next3; done
  for i in 5 6; do hook_rq "$(cohort_sid "$i")" next4; done
  tick
  [ "$(grep -c -- '--one ' "$FLEET_LOG")" = 6 ] || { cat "$FLEET_LOG"; plog; false; }
  ! grep -q 'REQUEST-QUEUED' "$STATE/poller.log" || false
}

@test "D1.6: LR_REQUEST_MAX_PER_TICK is honoured" {
  : > "$STATE/autorecover.on"
  local i
  for i in 1 2 3; do hook_rq "$(cohort_sid "$i")" next3; done
  LR_REQUEST_MAX_PER_TICK=1 LR_POLLER_AUTOFIRE=1 run bash "$POLLER" --once
  [ "$(grep -c -- '--one ' "$FLEET_LOG")" = 1 ] || { cat "$FLEET_LOG"; false; }
  grep -q 'queue depth 2, ETA ~30 min' "$STATE/poller.log" || { plog; false; }
}

# ══ W6b: PAST THE RESET THE REQUEST LANE WAKES IN PLACE (D1.4, resolution 2); A HELD LEAD IS RETIRED (D4.8)
wake_rq() { # $1=sid $2=pane — a hook request whose account reset 10 min ago, its pane live
  local tp; tp="$(lim_tx "$1")"
  rq "$1" <<JSON
{"sid":"$1","requested_by":"stop-failure-marker","account":"next3","source_pane":"$2","transcript_path":"$tp","reset_at_epoch":"$(( $(date +%s) - 600 ))"}
JSON
  printf '{"paneUUID":"%s","session_id":"%s","pid":%d,"account":"claude-tertiary","cwd":"/tmp"}\n' "$2" "$1" "$$" > "$CC_REGISTRY_DIR/$2.json"
}

@test "[D1.4] past its reset, a still-limited hook request with a live pane gets a continue typed IN PLACE — never a move" {
  : > "$STATE/autorecover.on"; mk_tui
  wake_rq "$SID" 616
  tick
  [ ! -s "$FLEET_LOG" ] || { echo "moved after its own account reset: $(cat "$FLEET_LOG")"; false; }
  grep -q '^pane=616$' "$TUI_LOG" || { cat "$TUI_LOG"; plog; false; }
  grep -q '^prompt=\[limit-recover\] The usage limit has reset on claude-tertiary. Continue the work' "$TUI_LOG" || { cat "$TUI_LOG"; false; }
  ! grep -q '/limit-recover' "$TUI_LOG" || { cat "$TUI_LOG"; false; }
  [ "$(jq -r .last_verdict "$STATE/requests/$SID.json")" = woken-in-place ] || { cat "$STATE/requests/$SID.json"; false; }
  grep -q "REQUEST-WAKE $SID (next3)" "$STATE/poller.log" || { plog; false; }
}

@test "[D1.4] the in-place wake is paced: at most 3 per account per tick" {
  : > "$STATE/autorecover.on"; mk_tui
  local i
  for i in 1 2 3 4; do wake_rq "$(cohort_sid "$i")" "70$i"; done
  tick
  [ "$(grep -c '^pane=' "$TUI_LOG")" = 3 ] || { cat "$TUI_LOG"; plog; false; }
  grep -q 'REQUEST-QUEUED 1 request(s)' "$STATE/poller.log" || { plog; false; }
}

@test "D1.4 CONTROL: with no live pane the request keeps the relaunch path" {
  : > "$STATE/autorecover.on"; mk_tui
  wake_rq "$SID" 616; rm -f "$CC_REGISTRY_DIR/616.json"
  tick
  [ ! -s "$TUI_LOG" ]
  grep -q -- "--one $SID" "$FLEET_LOG" || { plog; false; }
}

@test "[D4.8] a hook request for a lead with LIVE members is retired as held:team — never dispatched" {
  : > "$STATE/autorecover.on"
  export LR_TEAM_PS_SNAPSHOT="$BATS_TEST_TMPDIR/ps.snapshot"
  printf '4242 S /opt/cc/bin/claude --agent-id w@session-t --parent-session-id %s\n' "$SID" > "$LR_TEAM_PS_SNAPSHOT"
  hook_rq "$SID" next3
  tick
  [ ! -s "$FLEET_LOG" ] || { cat "$FLEET_LOG"; false; }
  grep -q "REQUEST-RETIRED $SID — held:team, resumes in place at reset" "$STATE/poller.log" || { plog; false; }
  [ -e "$STATE/results/$SID.retired.json" ]
}

@test "[D6.6] REQUEST-EXHAUSTED pages ONCE, naming the pane and the likely unsent draft" {
  : > "$STATE/autorecover.on"
  export LR_PAGE_OS_CHANNEL=on LR_PAGE_OSASCRIPT_BIN="$BATS_TEST_TMPDIR/stubs/page-osa" LR_PAGE_LOG="$BATS_TEST_TMPDIR/pages.log"
  export PAGE_ARGV="$BATS_TEST_TMPDIR/page.argv"; : > "$PAGE_ARGV"
  printf '#!/bin/bash\ncat >/dev/null; printf "%%s\\n" "$*" >> "$PAGE_ARGV"\n' > "$LR_PAGE_OSASCRIPT_BIN"; chmod +x "$LR_PAGE_OSASCRIPT_BIN"
  local tp; tp="$(lim_tx "$SID")"
  rq "$SID" <<JSON
{"sid":"$SID","requested_by":"stop-failure-marker","account":"next3","source_pane":"616","transcript_path":"$tp","attempts":3,"last_attempt_epoch":1}
JSON
  tick
  grep -q "REQUEST-EXHAUSTED $SID" "$STATE/poller.log" || { plog; false; }
  grep -q 'pane 616' "$PAGE_ARGV" || { cat "$PAGE_ARGV"; false; }
  grep -q 'unsent draft' "$PAGE_ARGV" || { cat "$PAGE_ARGV"; false; }
  tick
  [ "$(grep -c 'unsent draft' "$PAGE_ARGV")" = 1 ] || { cat "$PAGE_ARGV"; false; }
}

# ── A PARK IS NOT AN ATTEMPT (2026-10-01) ────────────────────────────────────────────────────────
# Three next4 sessions spent all three dispatches on "no routable target" parks and paged the
# operator while their own account had its headroom back. A dispatch whose run PARKED is refunded.
parked_run() { # $1=sid $2=verdict line → the results log names a run whose verdict.txt says $2
  local run="$BATS_TEST_TMPDIR/fleet-run-$1"; mkdir -p "$run" "$STATE/results"
  printf '%s\n' "$2" > "$run/verdict.txt"
  printf 'lr-fleet: DETACHED — driver pid 1 is recovering %s\nrun=%s log=%s/detached.log\n' "${1:0:8}" "$run" "$run" > "$STATE/results/$1.log"
}
@test "a request whose last dispatch PARKED is refunded, re-dispatched, and never exhausted or paged" {
  : > "$STATE/autorecover.on"
  local tp; tp="$(lim_tx "$SID")"
  rq "$SID" <<JSON
{"sid":"$SID","requested_by":"stop-failure-marker","account":"next3","source_pane":"616","transcript_path":"$tp","attempts":3,"last_attempt_epoch":1}
JSON
  parked_run "$SID" "lr-fleet --one ${SID:0:8}: verdict=PARKED rc=1 pane=616 acct=next3 mech=parked — no routable target"
  tick
  grep -q "REQUEST-REFUND $SID" "$STATE/poller.log" || { plog; false; }
  ! grep -q "REQUEST-EXHAUSTED $SID" "$STATE/poller.log" || { plog; false; }
  grep -q -- "--one $SID" "$FLEET_LOG" || { plog; false; }
}
@test "CONTROL: a request whose last dispatch FAILED (not parked) still exhausts at its budget" {
  : > "$STATE/autorecover.on"
  local tp; tp="$(lim_tx "$SID")"
  rq "$SID" <<JSON
{"sid":"$SID","requested_by":"stop-failure-marker","account":"next3","source_pane":"616","transcript_path":"$tp","attempts":3,"last_attempt_epoch":1}
JSON
  parked_run "$SID" "lr-fleet --one ${SID:0:8}: verdict=FAILED rc=4 pane=616 acct=next3 mech=recycle-in-place/FAILED"
  tick
  grep -q "REQUEST-EXHAUSTED $SID" "$STATE/poller.log" || { plog; false; }
  ! grep -q "REQUEST-REFUND $SID" "$STATE/poller.log" || { plog; false; }
}

@test "[R4] the queue is PAGED with its depth and ETA — once per depth, not once per tick" {
  : > "$STATE/autorecover.on"
  export LR_PAGE_OS_CHANNEL=on LR_PAGE_OSASCRIPT_BIN="$BATS_TEST_TMPDIR/stubs/page-osa" LR_PAGE_LOG="$BATS_TEST_TMPDIR/pages.log"
  export PAGE_ARGV="$BATS_TEST_TMPDIR/page.argv"; : > "$PAGE_ARGV"
  printf '#!/bin/bash\ncat >/dev/null; printf "%%s\\n" "$*" >> "$PAGE_ARGV"\n' > "$LR_PAGE_OSASCRIPT_BIN"; chmod +x "$LR_PAGE_OSASCRIPT_BIN"
  local i
  for i in 1 2 3 4 5 6; do hook_rq "$(cohort_sid "$i")" next3; done
  tick
  grep -q '2 limited session(s) are queued for recovery (by account: next3=2).*about 15 min' "$PAGE_ARGV" || { cat "$PAGE_ARGV"; plog; false; }
}
