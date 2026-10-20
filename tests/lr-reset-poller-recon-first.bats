#!/usr/bin/env bats
# lr-reset-poller.sh — RECONCILER FIRST, POLLER AS A BOUNDED BACKSTOP (A7 Part A, lr-sustained-load
# 2026-10-20; docs/research/lr-sustained-load-2026-10-20/impl/A7-limited-cohort-ruling.md §6, both
# reviews). With hands-off recovery on (autorecover.on AND recon/autorecover.on), a live reconciler in
# act mode, and an OPEN actionable record for the sid, the poller leaves the sid to the reconciler for
# a bounded time (LR_POLLER_RECON_FIRST_S, 600, clamped ≤ 900) at three call sites — the hook request
# loop, reroute_parked and the § 2 nudge — and then acts exactly as before.
#
# RED BEFORE (measured, /tmp/a7/bt2.out): `DISPATCHED: --one 52e35019… lr-recon-fence: verdict=act
# sid=52e35019 reason=not-owned` — the poller raced a live hands-off reconciler holding a 60 s-old
# open record. Case 1 below is that probe, on the hook's real request shape (ts, no `at`; F-A3).
#
# THE CLOCK IS THE POLLER'S (efficacy R1): $STATE/recon-first/<sid> is stamped once at the first
# deferral and <sid>.eta once with the first passed eta; the cases age a window by rewriting a stamp's
# epoch, never by sleeping it out.
#
# Every tick runs `/bin/bash "$POLLER"`, the interpreter launchd gives it (T-A12). HERMETIC: HOME,
# LR_STATE_DIR, LR_RECON_ROOT and TMPDIR live under BATS_TEST_TMPDIR; lr-fleet, osascript, launchctl,
# pgrep, claude-accounts and cc-tui are stubs that record what they were asked.

SID="52e35019-17e8-40f6-a54f-3a04de70d2e6"
S2="00000002-0000-4000-8000-000000000002"
S3="00000003-0000-4000-8000-000000000003"

setup() {
  export LR_UPGRADE_AUTO=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  POLLER="$REPO/scripts/limit-recover/lr-reset-poller.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  STATE="$HOME/.reso/limit-recover"
  export LR_STATE_DIR="$STATE" LR_RECON_ROOT="$STATE/recon" TMPDIR="$BATS_TEST_TMPDIR/tmp"
  S="$BATS_TEST_TMPDIR/stubs"; CWD="$BATS_TEST_TMPDIR/cwd"
  mkdir -p "$HOME/bin" "$STATE/parked" "$STATE/resumed" "$STATE/locks" "$STATE/recon/sessions" "$STATE/recon/owned" \
           "$S" "$CWD" "$TMPDIR"
  unset LR_RECORD_ID LR_LAUNCH_LOCK LR_RECON_FENCE_FRESH_S KITTY_WINDOW_ID CC_TERM_KITTY_TO CC_ACCOUNTS_BIN
  unset LR_POLLER_REROUTE LR_REROUTE_EVERY_MIN LR_POLLER_RECON_FIRST_S LR_POLLER_RECON_INGEST_S
  # The suite pins the behaviour that ships at the flip; T-A18 unsets it to read the shipped shadow.
  export LR_POLLER_RECON_FIRST=on
  NOW="$(date +%s)"; export LR_RECON_NOW="$NOW" LR_RECON_WAKETIME=0
  export LR_POLLER_NO_CENSUS=1 IT2_WRAPPER_NO_KITTY=1
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export LR_POLLER_LAUNCH_DIR="$BATS_TEST_TMPDIR/launchers"; mkdir -p "$LR_POLLER_LAUNCH_DIR"
  export CC_KITTY_SOCKET_BIN="$BATS_TEST_TMPDIR/no-kitty-socket"
  export LR_CC_TUI_LIB="$BATS_TEST_TMPDIR/absent-cc-tui.sh"
  export LR_NUDGE_ENGAGE_S=4 LR_NUDGE_IVL=1
  export LR_POLLER_CAPACITY_LIB="$REPO/tests/fixtures/lr-poller-capacity-stub.sh"
  export ACT_LOG="$BATS_TEST_TMPDIR/act.log"; : > "$ACT_LOG"
  cat > "$S/record-act" <<'STUB'
#!/bin/bash
who="$1"; shift
printf '%s\targv=%s\n' "$who" "$*" >> "${ACT_LOG:?}"
STUB
  export LR_FLEET_BIN="$S/lr-fleet"
  cat > "$LR_FLEET_BIN" <<STUB
#!/bin/bash
"$S/record-act" fleet "\$@"
echo "lr-fleet: DETACHED — driver pid \$PPID is recovering; the verdict arrives as mail."
exit 0
STUB
  # § 2's wake and the request lane's post-reset wake type through cc-tui.sh's cc_tui_submit; the stub
  # records it as `tui` and plays the fresh assistant turn the engagement wait looks for.
  cat > "$S/cc-tui-stub.sh" <<STUB
cc_tui_submit() {
  "$S/record-act" tui "\$@"
  [ -z "\${IT2_TX:-}" ] || printf '{"type":"assistant","timestamp":"%s","message":{"role":"assistant","model":"claude-opus-5","content":[{"type":"text","text":"resumed"}]}}\n' \
    "\$(date -u -v+5S +%FT%T.000Z 2>/dev/null || date -u +%FT%T.000Z)" >> "\$IT2_TX"
  return 0
}
STUB
  printf '#!/bin/bash\nexit 1\n' > "$S/osascript"
  printf '#!/bin/bash\nexit 1\n' > "$S/pgrep"
  printf '#!/bin/bash\nexit 0\n' > "$S/launchctl"
  export LR_LAUNCHCTL_BIN="$S/launchctl" LR_SELECT_PGREP_BIN="$S/pgrep"
  cat > "$HOME/bin/claude-accounts" <<'STUB'
#!/bin/bash
case " $* " in *" --rank "*) printf '%b\n' "${RANK_OUT:-none}"; exit 0 ;; esac
echo '{"rows":[{"acct":"next4","session_pct":12,"weekly_pct":40},{"acct":"next2","session_pct":5,"weekly_pct":7},{"acct":"next3","session_pct":5,"weekly_pct":7}]}'
STUB
  chmod +x "$S"/* "$HOME/bin/claude-accounts"
  export PATH="$S:$PATH"
}

tick() { LR_POLLER_AUTOFIRE=1 run /bin/bash "$POLLER" --once; }
plog() { cat "$STATE/poller.log" >&2; cat "$ACT_LOG" >&2; printf '%s\n' "$output" >&2; }
acted() { grep -c "^$1	" "$ACT_LOG" || true; }
dispatched() { grep -q "^fleet	argv=--one ${1:-$SID} " "$ACT_LOG"; }
clean() { : > "$ACT_LOG"; rm -f "$STATE/poller.log"; }

# ── fixtures ─────────────────────────────────────────────────────────────────────────────────────
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
age_file() { touch -t "$(date -r "$2" +%Y%m%d%H%M.%S)" "$1"; }   # $1=file $2=epoch → its mtime
lim_tx() { # $1=sid → a transcript whose last record is a usage-limit error (the drain-time revalidation)
  local d="$HOME/.claude-tertiary/projects/-Users-x-proj"; mkdir -p "$d"
  printf '{"type":"assistant","timestamp":"2026-09-28T03:00:00Z","isApiErrorMessage":true,"error":"rate_limit","message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your weekly limit · resets Oct 1"}]}}\n' > "$d/$1.jsonl"
  printf '%s' "$d/$1.jsonl"
}
# THE HOOK'S OWN SHAPE (hooks/stop-failure-marker.sh: sid … ts … death_uuid; no `at`), its file aged to
# the same instant with touch -t, so the predicate reads what production gives it (F-A3).
hook_rq() { # $1=sid $2=age s (default 60) $3=death_uuid (default u-<sid8>) $4=reset epoch (default none) $5=by $6=ts
  local sid="$1" at=$(( NOW - ${2:-60} )) f
  mkdir -p "$STATE/requests"; f="$STATE/requests/$sid.json"
  jq -nc --arg sid "$sid" --arg ts "${6:-$(iso "$at")}" --arg tp "$(lim_tx "$sid")" --arg du "${3:-u-${sid:0:8}}" \
         --arg reset "${4:-}" --arg by "${5:-stop-failure-marker}" \
    '{sid:$sid, target:"auto", source_pane:"20", requested_by:$by, ts:$ts, account:"next3", cwd:"/tmp", tier:"",
      transcript_path:$tp, error:"rate_limit", reset_at_epoch:$reset, rate_limit_type:"seven_day",
      death_uuid:$du, origin_class:"unknown"}' > "$f"
  age_file "$f" "$at"
}
handsoff_live() { # [no-recon-marker] — both zero-human markers, recon.on, mode act, a fresh heartbeat
  : > "$STATE/autorecover.on"; : > "$STATE/recon.on"; echo act > "$STATE/recon/mode"
  [ "${1:-}" = no-recon-marker ] || : > "$STATE/recon/autorecover.on"
  printf '{"pid":1,"progress":7,"progress_wall":%s}' "$((NOW - 10))" > "$STATE/recon/heartbeat"
}
record() { # $1=sid $2=jq object merged over an open, actionable, hook-origin limited record
  local o="${2:-}"; [ -n "$o" ] || o='{}'
  jq -nc --arg sid "$1" --argjson det "$((NOW - 60))" --argjson o "$o" \
    '{sid:$sid, record_id:("recon:next3-7d-1:" + $sid[0:8] + ":1"), kind:"limited", origin:"hook",
      plan_only:false, escalated:false, pane:[1,20], phase:"PRE-MOVE", substate:"DETECTED",
      timeline:{detected:$det}, wait:null, close:{death:("u-" + $sid[0:8] + "@2026-10-20T17:00:00Z")},
      terminal:null} * $o' > "$STATE/recon/sessions/$1.json"
}
stamp() { mkdir -p "$STATE/recon-first"; printf '%s\n' "$2" > "$STATE/recon-first/$1"; }   # $1=name $2=epoch
park_future() { # a parked record not yet reset; § 2a asks the router and reroutes
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"weekly","reset_at_utc":"2099-01-01T00:00:00Z","parked_at":"2026-09-26T20:55:27Z"}\n' \
    "$1" "$HOME/.claude-quaternary" "$CWD" > "$STATE/parked/$1.json"
}
park_ready() { # a parked record whose reset passed 10 min ago, with the transcript § 2 and lr-select read
  local proj ts
  proj="$HOME/.claude-quaternary/projects/$(printf '%s' "$CWD" | tr '/' '-')"; mkdir -p "$proj"
  ts="$(date -u -v-3H +%FT%T.000Z)"
  {
    printf '{"type":"user","cwd":"%s","gitBranch":"main","timestamp":"%s"}\n' "$CWD" "$ts"
    printf '{"type":"assistant","timestamp":"%s"}\n' "$ts"
    printf '{"type":"assistant","timestamp":"%s","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"limit"}]}}\n' "$ts"
  } > "$proj/$SID.jsonl"
  export IT2_TX="$proj/$SID.jsonl"
  printf '{"sid":"%s","acct":"next4","cfg":"%s","cwd":"%s","kind":"session","reset_at_utc":"%s","parked_at":"2026-01-01T00:00:00Z"}\n' \
    "$SID" "$HOME/.claude-quaternary" "$CWD" "$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ)" > "$STATE/parked/$SID.json"
}
live_row() { # $1=pane $2=sid $3=account dir name — the original pane is alive (pid = this bats process)
  printf '{"paneUUID":"%s","session_id":"%s","pid":%d,"account":"%s","cwd":"%s"}\n' "$1" "$2" "$$" "$3" "$CWD" > "$CC_REGISTRY_DIR/$1.json"
  export LR_CC_TUI_LIB="$S/cc-tui-stub.sh"
}
no_shell_noise() {
  ! printf '%s\n' "$output" | grep -Ei 'unbound variable|syntax error|command not found|No such file|Not a directory' || { plog; false; }
}

# ══ THE REQUEST LANE (call site 1) ══════════════════════════════════════════════════════════════
@test "T-A1 [RED before] hands-off on, live reconciler, open record 60 s old: the request is left, unspent, one RECON-FIRST 1 line" {
  handsoff_live; record "$SID"; hook_rq "$SID"
  tick
  [ "$status" -eq 0 ] || { plog; false; }
  [ "$(acted fleet)" -eq 0 ] || { echo "DISPATCHED: $(cat "$ACT_LOG")"; plog; false; }
  [ -f "$STATE/requests/$SID.json" ]
  [ "$(jq -r '.attempts // "none"' "$STATE/requests/$SID.json")" = none ] || { cat "$STATE/requests/$SID.json"; false; }
  [ "$(grep -c 'RECON-FIRST ' "$STATE/poller.log")" -eq 1 ] || { plog; false; }
  grep -q "RECON-FIRST 1 limited session(s) left to the live hands-off reconciler, up to 600s each (sids: ${SID:0:8})" "$STATE/poller.log" || { plog; false; }
  # the poller's own clock started now, written once
  [ "$(cat "$STATE/recon-first/$SID")" -ge "$NOW" ] || { ls -la "$STATE/recon-first"; false; }
  no_shell_noise
}

@test "T-A2 CONTROL: recon/autorecover.on absent (a hook-origin record): dispatched as before" {
  handsoff_live no-recon-marker; record "$SID"; hook_rq "$SID"
  tick
  dispatched || { plog; false; }
  ! grep -q 'RECON-FIRST' "$STATE/poller.log" || { plog; false; }
}

@test "T-A3 backstop: once the poller's own stamp is past g, the request is dispatched" {
  handsoff_live; record "$SID"; hook_rq "$SID" 30
  tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  stamp "$SID" "$(( NOW - 601 ))"; clean
  tick
  dispatched || { plog; false; }
}

@test "T-A3b F-A2: a request older than g is dispatched at once, however fresh the record (t0 = min(stamp, request ts))" {
  handsoff_live; record "$SID" '{"timeline":{"detected":'"$NOW"'}}'; hook_rq "$SID" 700
  tick
  dispatched || { plog; false; }
}

@test "T-A4 a heartbeat 3600 s old (reconciler not live): dispatched" {
  handsoff_live; record "$SID"; hook_rq "$SID"
  printf '{"pid":1,"progress":7,"progress_wall":%s}' "$((NOW - 3600))" > "$STATE/recon/heartbeat"
  tick
  dispatched || { plog; false; }
}

@test "T-A5 a record the reconciler will not drive, or a mode that is not act: dispatched (5 sub-cases)" {
  local c
  for c in terminal plan_only escalated pane mode; do
    # the last sub-case's dispatch leaves a run claim whose holder (the tick) is dead: stolen, as in production
    rm -f "$STATE/recon-first/$SID" "$STATE/recon-first/$SID.eta" "$STATE/requests/$SID.json"
    handsoff_live; clean
    case "$c" in
      terminal)  record "$SID" '{"terminal":{"outcome":"ENGAGED","at":'"$NOW"'}}' ;;   # closed AFTER the request, same death
      plan_only) record "$SID" '{"plan_only":true}' ;;
      escalated) record "$SID" '{"escalated":true}' ;;
      pane)      record "$SID" '{"pane":null}' ;;
      mode)      record "$SID"; echo observe > "$STATE/recon/mode" ;;
    esac
    hook_rq "$SID"
    tick
    dispatched || { echo "sub-case $c was not dispatched"; plog; false; }
  done
}

@test "T-A6 no record yet (not ingested): a 30 s-old request is deferred, a 400 s-old one dispatched" {
  handsoff_live; hook_rq "$SID" 30
  tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  grep -q "RECON-FIRST 1 " "$STATE/poller.log" || { plog; false; }
  clean; hook_rq "$SID" 400
  tick
  dispatched || { plog; false; }
}

@test "T-A6m an unreadable ts falls back to the file's mtime (30 s: deferred; 400 s: dispatched)" {
  handsoff_live; hook_rq "$SID" 30 "" "" "" "?"
  tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  clean; hook_rq "$SID" 400 "" "" "" "?"
  tick
  dispatched || { plog; false; }
}

@test "T-A6b F-A1: an EARLIER death's terminal record on file and a fresh request: deferred as not ingested" {
  handsoff_live
  record "$SID" '{"terminal":{"outcome":"ENGAGED","at":'"$(( NOW - 86400 ))"'},"close":{"death":"u-olddeath@2026-10-17T03:00:00Z"}}'
  hook_rq "$SID" 30
  tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  grep -q "RECON-FIRST 1 " "$STATE/poller.log" || { plog; false; }
}

@test "T-A6c F-A1: a terminal record closed after the request for ANOTHER death (death_uuid differs) is still not-ingested" {
  handsoff_live
  record "$SID" '{"terminal":{"outcome":"ENGAGED","at":'"$NOW"'},"close":{"death":"u-olddeath@2026-10-17T03:00:00Z"}}'
  hook_rq "$SID" 30 u-newdeath
  tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
}

@test "T-A7 the post-reset wake with an open WAIT_RESET record: eta 120 s past ⇒ nothing typed; 900 s past ⇒ typed" {
  handsoff_live; live_row 616 "$SID" claude-tertiary
  record "$SID" '{"substate":"WAIT_RESET","wait":{"reason":"WAIT_RESET","eta":'"$(( NOW - 120 ))"'}}'
  hook_rq "$SID" 3000 "" "$(( NOW - 1000 ))"
  tick
  [ "$(acted tui)" -eq 0 ] || { plog; false; }
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  [ "$(cat "$STATE/recon-first/$SID.eta")" = "$(( NOW - 120 ))" ] || { ls -la "$STATE/recon-first"; false; }
  rm -f "$STATE/recon-first/$SID" "$STATE/recon-first/$SID.eta"; clean
  record "$SID" '{"substate":"WAIT_RESET","wait":{"reason":"WAIT_RESET","eta":'"$(( NOW - 900 ))"'}}'
  tick
  [ "$(acted tui)" -eq 1 ] || { plog; false; }
}

@test "T-A13 a stay re-offer loop: the eta window is stamped once, so a re-placed eta never re-arms it (total ≤ 2·g)" {
  handsoff_live
  record "$SID" '{"substate":"WAIT_RESET","wait":{"reason":"WAIT_RESET","eta":'"$(( NOW + 300 ))"'}}'
  hook_rq "$SID" 30
  tick                                                    # window 1: the first deferral
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  stamp "$SID" "$(( NOW - 601 ))"; clean
  record "$SID" '{"substate":"WAIT_RESET","wait":{"reason":"WAIT_RESET","eta":'"$(( NOW - 5 ))"'}}'
  tick                                                    # window 2: the eta has passed
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  [ "$(cat "$STATE/recon-first/$SID.eta")" = "$(( NOW - 5 ))" ]
  stamp "$SID.eta" "$(( NOW - 601 ))"; clean
  record "$SID" '{"substate":"WAIT_RESET","wait":{"reason":"WAIT_RESET","eta":'"$(( NOW - 1 ))"'}}'   # plan re-offered the stay
  tick                                                    # both windows spent: the backstop acts
  dispatched || { plog; false; }
}

@test "T-A14 a record whose wake failed (close.wake_failed): dispatched" {
  handsoff_live
  record "$SID" '{"substate":"WAIT_RESET","wait":{"reason":"WAIT_RESET","eta":'"$(( NOW - 60 ))"'},"close":{"wake_failed":"the composer could not be read (rc 2)"}}'
  hook_rq "$SID"
  tick
  dispatched || { plog; false; }
}

@test "T-A15 a PARKED-REBOOT record: dispatched" {
  handsoff_live; record "$SID" '{"substate":"PARKED-REBOOT"}'; hook_rq "$SID"
  tick
  dispatched || { plog; false; }
}

@test "T-A15k a record of another kind (idle): dispatched" {
  handsoff_live; record "$SID" '{"kind":"idle"}'; hook_rq "$SID"
  tick
  dispatched || { plog; false; }
}

@test "T-A16 LR_POLLER_RECON_FIRST_S=5000 is clamped to 900: a stamp 1000 s old acts, one 800 s old still defers" {
  export LR_POLLER_RECON_FIRST_S=5000
  handsoff_live; record "$SID"; hook_rq "$SID" 30
  stamp "$SID" "$(( NOW - 800 ))"
  # the request's own ts (30 s) is newer than the stamp, so the stamp is the window
  tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  grep -q "up to 900s each" "$STATE/poller.log" || { plog; false; }
  stamp "$SID" "$(( NOW - 1000 ))"; clean
  tick
  dispatched || { plog; false; }
}

@test "T-A10 kill switches: LR_POLLER_RECON_FIRST=off, and separately \$STATE/recon-first.off: dispatched" {
  handsoff_live; record "$SID"; hook_rq "$SID"
  LR_POLLER_RECON_FIRST=off tick
  dispatched || { plog; false; }
  clean; hook_rq "$SID"   # a fresh request: the first one now carries an attempt and its retry pacing
  : > "$STATE/recon-first.off"
  tick
  dispatched || { plog; false; }
  [ ! -e "$STATE/recon-first/$SID" ] || { echo "stamped while off"; false; }
}

@test "T-A11 three deferred sids, one also parked: exactly one RECON-FIRST 3 line (deduped by sid)" {
  handsoff_live
  local s
  for s in "$SID" "$S2" "$S3"; do record "$s"; hook_rq "$s"; done
  park_future "$SID"
  RANK_OUT="next2 0.8" tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  [ "$(grep -c 'RECON-FIRST ' "$STATE/poller.log")" -eq 1 ] || { plog; false; }
  grep -q 'RECON-FIRST 3 limited session(s)' "$STATE/poller.log" || { plog; false; }
}

@test "T-A11x F-A6: the request lane's count is logged even when the tick ends early (lr-select missing)" {
  handsoff_live; record "$SID"; hook_rq "$SID"
  LR_SELECT_BIN="$BATS_TEST_TMPDIR/no-lr-select" tick
  grep -q 'ERROR lr-select missing' "$STATE/poller.log" || { plog; false; }
  grep -q 'RECON-FIRST 1 ' "$STATE/poller.log" || { plog; false; }
}

@test "T-A19 F-A5: a stranded-husk request is never deferred (the reconciler opens no record for it)" {
  handsoff_live; hook_rq "$SID" 30 "" "" stranded-husk
  tick
  dispatched || { plog; false; }
  ! grep -q 'RECON-FIRST' "$STATE/poller.log" || { plog; false; }
}

@test "T-A20 a cc-lr-origin record is the reconciler's even with recon/autorecover.on absent" {
  handsoff_live no-recon-marker; record "$SID" '{"origin":"cc-lr"}'; hook_rq "$SID"
  tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
}

@test "T-A21 F-A4: a missing recon/mode prints nothing to stderr, and the poller acts as before" {
  handsoff_live; record "$SID"; hook_rq "$SID"; rm -f "$STATE/recon/mode"
  tick
  dispatched || { plog; false; }
  no_shell_noise
}

@test "T-A22 the stamps leave with the request: a session seen recovered retires the request and its stamps" {
  handsoff_live; record "$SID"; hook_rq "$SID"
  tick
  [ -e "$STATE/recon-first/$SID" ] || { plog; false; }
  printf '{"type":"assistant","timestamp":"2026-10-20T18:00:00Z","message":{"role":"assistant","content":[{"type":"text","text":"done"}]}}\n' \
    >> "$(jq -r .transcript_path "$STATE/requests/$SID.json")"
  clean; tick
  grep -q "REQUEST-RETIRED $SID" "$STATE/poller.log" || { plog; false; }
  [ ! -e "$STATE/recon-first/$SID" ] || { ls -la "$STATE/recon-first"; false; }
}

# ══ reroute_parked (call site 2) and the § 2 nudge (call site 3) ═════════════════════════════════
@test "T-A8 reroute_parked with an open record: no reroute dispatch; CONTROL recon-first off: rerouted" {
  handsoff_live; record "$SID"; park_future "$SID"
  RANK_OUT="next2 0.8" tick
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  [ -f "$STATE/parked/$SID.json" ]
  grep -q 'RECON-FIRST 1 ' "$STATE/poller.log" || { plog; false; }
  clean
  RANK_OUT="next2 0.8" LR_POLLER_RECON_FIRST=off tick
  dispatched || { plog; false; }
}

@test "T-A17 a promoted record (detected 5000 s ago, acting now) gets one fresh window, then the backstop" {
  handsoff_live; park_future "$SID"
  record "$SID" '{"timeline":{"detected":'"$(( NOW - 5000 ))"'}}'
  RANK_OUT="next2 0.8" tick
  # RED under a record-keyed clock (t0 = detected): rerouted at once
  [ "$(acted fleet)" -eq 0 ] || { plog; false; }
  stamp "$SID" "$(( NOW - 601 ))"; clean
  RANK_OUT="next2 0.8" tick
  dispatched || { plog; false; }
}

@test "T-A9 § 2 nudge with an open WAIT_RESET record whose eta passed 60 s ago: nothing typed; CONTROL off: typed" {
  handsoff_live; park_ready; live_row 616 "$SID" claude-quaternary
  record "$SID" '{"substate":"WAIT_RESET","wait":{"reason":"WAIT_RESET","eta":'"$(( NOW - 60 ))"'}}'
  tick
  [ "$(acted tui)" -eq 0 ] || { plog; false; }
  grep -q 'RECON-FIRST 1 ' "$STATE/poller.log" || { plog; false; }
  clean
  LR_POLLER_RECON_FIRST=off tick
  [ "$(acted tui)" -eq 1 ] || { plog; false; }
}

@test "T-A9h a HELD:team record takes the eta window too (60 s past: nothing typed)" {
  handsoff_live; park_ready; live_row 616 "$SID" claude-quaternary
  record "$SID" '{"substate":"HELD:team","wait":{"reason":"HELD:team","eta":'"$(( NOW - 60 ))"'}}'
  stamp "$SID" "$(( NOW - 700 ))"   # the first window is spent; only the eta window can hold it
  tick
  [ "$(acted tui)" -eq 0 ] || { plog; false; }
}

# ══ SHADOW, THE SHIPPED DEFAULT (packet 4ffc4e1e5f1c open) ═══════════════════════════════════════
@test "T-A18 shadow (the code default): the would-defer line is logged and the request is dispatched as today" {
  unset LR_POLLER_RECON_FIRST
  handsoff_live; record "$SID"; hook_rq "$SID"
  tick
  dispatched || { plog; false; }
  grep -q "RECON-FIRST would-defer $SID — open DETECTED record" "$STATE/poller.log" || { plog; false; }
  [ "$(grep -c "RECON-FIRST would-defer $SID" "$STATE/poller.log")" -eq 1 ] || { plog; false; }
  ! grep -q 'RECON-FIRST [0-9]' "$STATE/poller.log" || { plog; false; }
  no_shell_noise
}
