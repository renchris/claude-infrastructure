#!/bin/bash
# p8-e2e — regression gate for P8 (the session-registration spine).
#
# P8-GO condition 2: EFFECT-CHECK BEFORE TRUST, BOTH DIRECTIONS.
#   POSITIVE — a session that registers and NEVER renders must show a LOUD row on cc-board.
#              (That row is the whole point: a telemetry-spined board renders such a pane as
#              ABSENCE, and absence is silent. This is the D8-trigger-1 spawn-death detector.)
#   NEGATIVE — the hook, forced to fail in every way we can force it, must STILL exit 0 and never
#              block a session start (P8-GO condition 1: fail-open). A registration spine that can
#              kill startups inverts its own purpose.
#
# Plus the two invariants the join depends on:
#   ADDRESSING — cc-sessions' default view still lists LIVE rows only, so cc-notify can never
#                resolve a friendly name onto a dead pane. (Load-bearing for W4 right now.)
#   RETENTION  — a DEAD row is KEPT (not reaped) inside the investigation window. The old sweep
#                deleted it on deadness, which erased the very evidence P8 exists to surface.
#
# Sandboxed: CC_REGISTRY_DIR + CC_TELEMETRY_DIR overrides. Touches nothing real. CI-safe.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
HOOK=./hooks/session-register.sh; BOARD=./bin/cc-board; SESS=./bin/cc-sessions
SB=$(mktemp -d); REG="$SB/reg"; TEL="$SB/tel"; mkdir -p "$REG" "$TEL"
export CC_REGISTRY_DIR="$REG" CC_TELEMETRY_DIR="$TEL"
trap 'rm -rf "$SB"' EXIT
P=0; F=0
ok(){ P=$((P+1)); echo "  ✓ $1"; }
no(){ F=$((F+1)); echo "  ✗ $1"; }
U1=AAAAAAAA-1111-2222-3333-444444444444
U2=BBBBBBBB-1111-2222-3333-444444444444

run_hook(){ # <paneUUID> <session_id>  -> runs the SessionStart hook with synthetic stdin
  printf '{"session_id":"%s","cwd":"/work","hook_event_name":"SessionStart"}' "$2" \
    | ITERM_SESSION_ID="w0t0p0:$1" bash "$HOOK" >/dev/null 2>&1
  return $?
}

echo "P8 T1 — fail-open (condition 1): the hook exits 0 no matter what"
run_hook "$U1" sid-live; [ $? -eq 0 ] && ok "normal run exits 0" || no "normal run"
printf 'not json at all' | ITERM_SESSION_ID="w0t0p0:$U2" bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] && ok "garbage stdin → exit 0" || no "garbage stdin"
printf '{}' | ITERM_SESSION_ID="" bash "$HOOK" >/dev/null 2>&1
[ $? -eq 0 ] && ok "no pane (ITERM_SESSION_ID unset) → exit 0" || no "no pane"
CC_REGISTRY_DIR=/proc/nonexistent/nope run_hook "$U2" sid-x
[ $? -eq 0 ] && ok "unwritable registry dir → exit 0 (never costs a session)" || no "unwritable dir"
# A REAL jq-less PATH. Two earlier attempts were phantoms: PATH=/nonexistent removed `bash` itself
# (tested my fixture, not the hook), and PATH=/usr/bin:/bin still HAS jq on this machine — the test
# passed while jq was present, asserting nothing. Build a shim dir with everything the hook needs
# EXCEPT jq, and assert jq is genuinely unresolvable before trusting the result.
mkdir -p "$SB/nojq"
for c in bash sh printf ps date mkdir mv rm cat sed basename grep; do
  src=$(command -v "$c" 2>/dev/null) && ln -sf "$src" "$SB/nojq/$c"
done
if PATH="$SB/nojq" command -v jq >/dev/null 2>&1; then
  no "fixture broken: jq still resolvable in the shim PATH (would be a phantom green)"
else
  ( PATH="$SB/nojq" run_hook "$U2" sid-y )
  [ $? -eq 0 ] && ok "jq genuinely missing → exit 0" || no "jq missing"
fi
t0=$(date +%s); P8_REGISTER_TIMEOUT=1 run_hook "$U2" sid-t; t1=$(date +%s)
[ $((t1 - t0)) -le 3 ] && ok "bounded (timeout honoured; no startup hang)" || no "hook took $((t1-t0))s"

echo "P8 T2 — the JOIN KEY is written (registry ↔ telemetry)"
jq -e '.session_id=="sid-live"' "$REG/$U1.json" >/dev/null 2>&1 && ok "session_id recorded" || no "session_id missing"
jq -e '.pid|numbers'            "$REG/$U1.json" >/dev/null 2>&1 && ok "pid recorded (liveness)" || no "pid missing"

echo "P8 T3 — POSITIVE: registered + NEVER rendered ⇒ a LOUD row (the spawn-death detector)"
# no telemetry file for sid-live; age it past the grace window so it is not "still starting up"
old=$(( ($(date +%s) - 600) * 1000 ))
jq --argjson s "$old" '.startedAt=$s | .pid=999999' "$REG/$U1.json" > "$REG/$U1.tmp" && mv "$REG/$U1.tmp" "$REG/$U1.json"
b=$(bash "$BOARD" 2>/dev/null)
echo "$b" | grep -q 'DIED-UNRENDERED' && ok "dead pid + never rendered → DIED-UNRENDERED (was: ABSENT, silent)" || no "DIED-UNRENDERED"
sleep 300 & LP=$!
jq --argjson s "$old" --argjson p "$LP" '.startedAt=$s | .pid=$p' "$REG/$U1.json" > "$REG/$U1.tmp" && mv "$REG/$U1.tmp" "$REG/$U1.json"
b=$(bash "$BOARD" 2>/dev/null)
echo "$b" | grep -q 'NO-RENDER?' && ok "live pid + never rendered → NO-RENDER? (hung at startup)" || no "NO-RENDER?"
{ kill $LP; wait $LP; } >/dev/null 2>&1

echo "P8 T4 — ANTI-TRIGGER: a session that HAS rendered must NOT be flagged"
printf '{"ts":%s,"session_id":"sid-live","cwd":"/work","config_dir":"","model":"m","effort":"max","pid":1,"window":1000000,"used_pct":5,"remaining_pct":95,"input_tokens":1,"exceeds_200k":false}\n' "$(date +%s)" > "$TEL/sid-live.json"
b=$(bash "$BOARD" 2>/dev/null)
echo "$b" | grep -qE 'NO-RENDER|DIED-UNRENDERED' && no "flagged a session that HAS telemetry (false positive)" || ok "rendered session not flagged"
rm -f "$TEL/sid-live.json"

echo "P8 T5 — ANTI-TRIGGER: a JUST-STARTED session is not slandered before its first render"
jq --argjson s "$(( $(date +%s) * 1000 ))" '.startedAt=$s | .pid=1' "$REG/$U1.json" > "$REG/$U1.tmp" && mv "$REG/$U1.tmp" "$REG/$U1.json"
b=$(bash "$BOARD" 2>/dev/null)
echo "$b" | grep -qE 'NO-RENDER|DIED-UNRENDERED' && no "flagged inside the grace window (would fire on EVERY startup)" || ok "grace window respected"

echo "P8 T6 — RETENTION ≠ LIVENESS: a dead row is KEPT as evidence, and addressing still filters it"
jq '.pid=999999' "$REG/$U1.json" > "$REG/$U1.tmp" && mv "$REG/$U1.tmp" "$REG/$U1.json"
bash "$SESS" --json >/dev/null 2>&1                      # the old code DELETED the row right here
[ -f "$REG/$U1.json" ] && ok "dead row PRESERVED (the spawn-death evidence survives the reaper)" \
                       || no "dead row deleted — the reaper erased the evidence"
bash "$SESS" --json 2>/dev/null | jq -e 'map(select(.paneUUID=="'"$U1"'"))|length==0' >/dev/null 2>&1 \
  && ok "addressing view still LIVE-only (cc-notify cannot resolve a dead pane)" || no "dead pane leaked into addressing"
bash "$SESS" --json --all 2>/dev/null | jq -e 'map(select(.paneUUID=="'"$U1"'"))|length==1' >/dev/null 2>&1 \
  && ok "--all exposes it for forensics" || no "--all did not expose the dead row"
CC_REG_RETAIN_H=0 bash "$SESS" --json >/dev/null 2>&1    # retention window closed → hygiene reap
[ -f "$REG/$U1.json" ] && no "row outlived its retention window" || ok "reaped past retention (AGE, not deadness)"

echo "p8-e2e: $P passed, $F failed"
[ "$F" -eq 0 ] || exit 1
