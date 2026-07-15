#!/bin/bash
# boundary-hook-e2e.sh — regression guard for hooks/boundary-handoff.sh (SESSION_AUTONOMY §3.2, B-1..B-3).
#
# Synthetic git repo + telemetry fixtures in a sandbox. Asserts POSITIVE fires AND ANTI-TRIGGER abstains
# (both marquee W0-W3 rescues were OVER-firing — "proves it fires" is never enough, audit §3b/§3c), plus
# the two laws a naive hook violates and a green suite would miss:
#   B-2  the latch RE-ARMS on a used_pct climb (a HEAD-sha-only latch goes silent as an ignored session
#        fills — quiet exactly when it should get louder).
#   B-3  EVERY invocation logs {fired|abstained} to the IDL (else 'didn't fire' == 'never evaluated').
# Run from the repo root. Exit nonzero on any failure (a gate). --selftest is an alias (self-contained).
set -u
cd "$(dirname "$0")/.." || exit 2
HOOK="$PWD/hooks/boundary-handoff.sh"
P=0; F=0
ok(){ P=$((P+1)); echo "  ✓ $1"; }
no(){ F=$((F+1)); echo "  ✗ $1"; }

SBX=$(mktemp -d)
export CC_TELEMETRY_DIR="$SBX/tel";        mkdir -p "$CC_TELEMETRY_DIR"
export CC_IDL="$SBX/idl.jsonl"
export CC_BOUNDARY_LATCH_DIR="$SBX/latch"
export CC_CONTINUE_SENTINEL="$SBX/no-such-sentinel"
export CC_BOUNDARY_T=73
export CC_BOUNDARY_REARM_DELTA=10

REPO="$SBX/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
echo x > "$REPO/f"; git -C "$REPO" add f; git -C "$REPO" commit -qm init
HEAD=$(git -C "$REPO" rev-parse HEAD)
GITDIR=$(git -C "$REPO" rev-parse --git-common-dir); case "$GITDIR" in /*) ;; *) GITDIR="$REPO/$GITDIR";; esac
green_at_head(){ printf '%s' "$HEAD" > "$GITDIR/gate-green"; }

mktel(){ # $1=sid $2=used $3=age_s
  local ts; ts=$(( $(date +%s) - ${3:-0} ))
  jq -nc --arg sid "$1" --arg cwd "$REPO" --argjson up "$2" --argjson ts "$ts" \
    '{ts:$ts,session_id:$sid,cwd:$cwd,config_dir:"/Users/x/.claude-next",used_pct:$up,pid:1}' \
    > "$CC_TELEMETRY_DIR/$1.json"; }
run_hook(){ printf '{"session_id":"%s"}' "$1" | bash "$HOOK" 2>/dev/null; }
fired(){   echo "$1" | jq -e '.decision=="block"' >/dev/null 2>&1; }
idl_last(){ tail -1 "$CC_IDL" 2>/dev/null; }
idl_count(){ [ -f "$CC_IDL" ] && wc -l < "$CC_IDL" | tr -d ' ' || echo 0; }
reset_idl(){ : > "$CC_IDL"; rm -rf "$CC_BOUNDARY_LATCH_DIR"; }

green_at_head

echo "T1 FIRE — fresh ∧ used≥T ∧ clean ∧ green==HEAD ∧ no teammates ⇒ decision:block + IDL fired"
reset_idl; mktel s1 80 0
out=$(run_hook s1)
fired "$out"                          && ok "fires (decision:block)"        || no "did NOT fire on a valid boundary"
idl_last | grep -q '"disposition":"fired"' && ok "IDL records the fire"     || no "fire not logged to IDL"

echo "T2 ANTI-TRIGGER — used < T ⇒ abstain, no injection"
reset_idl; mktel s2 50 0
out=$(run_hook s2)
[ -z "$out" ]                         && ok "no injection below threshold"  || no "fired below threshold"
idl_last | grep -q 'below-threshold'  && ok "abstain logged (below-threshold)" || no "abstain not logged"

echo "T3 ANTI-TRIGGER — stale telemetry (age>180s) ⇒ abstain (an old number is not the current fill)"
reset_idl; mktel s3 90 999
out=$(run_hook s3)
[ -z "$out" ]                         && ok "no injection on stale telemetry" || no "fired on stale telemetry"
idl_last | grep -q 'stale-telemetry'  && ok "abstain logged (stale)"         || no "stale abstain not logged"

echo "T4 ANTI-TRIGGER — dirty tree ⇒ abstain (never advise handoff on an uncommitted tree)"
reset_idl; mktel s4 90 0; echo dirty > "$REPO/uncommitted"
out=$(run_hook s4)
[ -z "$out" ]                         && ok "no injection on dirty tree"     || no "fired on dirty tree"
idl_last | grep -q 'dirty-tree'       && ok "abstain logged (dirty-tree)"    || no "dirty abstain not logged"
rm -f "$REPO/uncommitted"

echo "T5 ANTI-TRIGGER — gate-green marker != HEAD ⇒ abstain (never advise on an UNPROVEN-green tree)"
reset_idl; rm -f "$GITDIR/gate-green"; mktel s5 90 0
out=$(run_hook s5)
[ -z "$out" ]                         && ok "no injection when gate-green absent" || no "fired without a green marker"
idl_last | grep -q 'gate-not-green'   && ok "abstain logged (gate-not-green)" || no "green abstain not logged"
green_at_head

echo "T6 B-2 one-shot — a second invocation at the SAME used is latched (no double-advisory)"
reset_idl; mktel s6 80 0
run_hook s6 >/dev/null                 # fire 1
out=$(run_hook s6)                     # same used → latched
[ -z "$out" ]                         && ok "second invocation latched"      || no "double-fired on one boundary"
idl_last | grep -q 'latched'          && ok "latch abstain logged"           || no "latch not logged"

echo "T7 B-2 LAW — re-arm on used_pct +DELTA (a HEAD-sha-only latch would stay SILENT — the bug)"
mktel s6 90 0                          # +10 climb, same HEAD
out=$(run_hook s6)
fired "$out"                          && ok "re-fires on +10 fill (B-2 re-arm — louder, not quieter)" \
                                      || no "stayed silent as fill climbed (B-2 VIOLATED)"

echo "T8 B-3 LAW — every invocation logs (fired|abstained), never silent"
reset_idl
mktel s7 50 0; run_hook s7 >/dev/null  # abstain (below)
mktel s7 80 0; run_hook s7 >/dev/null  # fire
mktel s7 80 0; run_hook s7 >/dev/null  # latched abstain
[ "$(idl_count)" = 3 ]                && ok "3 invocations → 3 IDL lines (no silent evaluation)" \
                                      || no "IDL lines != 3 (got $(idl_count))"

echo "T9 fail-open — a Stop hook must NEVER cost a session"
printf 'garbage-not-json' | bash "$HOOK" >/dev/null 2>&1; [ $? -eq 0 ] && ok "garbage stdin → exit 0"       || no "garbage stdin nonzero"
printf '{"session_id":"ghost"}' | bash "$HOOK" >/dev/null 2>&1; [ $? -eq 0 ] && ok "missing telemetry → exit 0" || no "missing telemetry nonzero"

rm -rf "$SBX"
echo ""
echo "boundary-hook-e2e: $P passed, $F failed"
[ "$F" -eq 0 ] || exit 1
