#!/bin/bash
# telemetry-e2e.sh — regression guard for telemetry-v2 (SESSION_AUTONOMY §3.1 + axis i).
#
# Codifies the verified behaviors of the atomic statusline export + cc-context (--me,
# --quota, sweep) + cc-board, in a CC_TELEMETRY_DIR sandbox (P2/P3 patterns). Every
# primitive is checked with a POSITIVE and (where it matters) an ANTI-TRIGGER fixture —
# both marquee W0-W3 rescues were OVER-firing, so "proves it fires" is not enough
# (audit §3b/§3c). Run from the repo root. Exits nonzero on any failure (a gate).
set -u
cd "$(dirname "$0")/.." || exit 2
SL=./statusline.sh CC=./bin/cc-context BOARD=./bin/cc-board
SB=$(mktemp -d); export CC_TELEMETRY_DIR="$SB"
now=$(date +%s); P=0; F=0
ok(){ P=$((P+1)); echo "  ✓ $1"; }
no(){ F=$((F+1)); echo "  ✗ $1"; }

echo "T1 statusline: atomic export + config_dir join-key (P1/P5)"
PAY='{"session_id":"s1","cwd":"/w","transcript_path":"/Users/chrisren/.claude-secondary/projects/-x/T.jsonl","model":{"id":"claude-opus-4-8"},"effort":{"level":"max"},"context_window":{"context_window_size":1000000,"used_percentage":42,"remaining_percentage":58,"total_input_tokens":420000},"exceeds_200k_tokens":true}'
# statusline hardcodes /tmp/cc-telemetry (no CC_TELEMETRY_DIR seam yet) — test with a
# throwaway sid in the real dir + clean up; $SB isolates cc-context/cc-board only.
echo "$PAY" | bash "$SL" >/dev/null 2>&1
jq -e '.config_dir=="/Users/chrisren/.claude-secondary" and .used_pct==42' /tmp/cc-telemetry/s1.json >/dev/null 2>&1 && ok "config_dir + fields" || no "config_dir/fields"

echo "T2 statusline: sid-once guard — no unknown.json (P2)"
rm -f /tmp/cc-telemetry/unknown.json
echo "$PAY" | jq 'del(.session_id)' | bash "$SL" >/dev/null 2>&1
[ ! -f /tmp/cc-telemetry/unknown.json ] && ok "no unknown.json on empty sid" || no "unknown.json created"

echo "T3 statusline: atomic under concurrency — 0 torn reads (P1)"
e=0; ( for i in $(seq 20); do echo "$PAY" | bash "$SL" >/dev/null 2>&1; done ) & \
     ( for i in $(seq 20); do echo "$PAY" | jq '.context_window.used_percentage=9' | bash "$SL" >/dev/null 2>&1; done ) &
for i in $(seq 150); do jq . /tmp/cc-telemetry/s1.json >/dev/null 2>&1 || e=$((e+1)); done; wait
[ "$e" -eq 0 ] && ok "0 torn reads" || no "$e torn reads"
rm -f /tmp/cc-telemetry/s1.json

# --- cc-context / cc-board in the isolated sandbox ---
mk(){ jq -nc --arg ts "$1" --arg sid "$2" --arg cwd "$3" --arg cfg "$4" --argjson up "$5" \
  '{ts:($ts|tonumber),session_id:$sid,cwd:$cwd,config_dir:$cfg,model:"claude-opus-4-8",effort:"max",window:1000000,used_pct:$up,remaining_pct:(100-$up),input_tokens:($up*10000)}' > "$SB/$2.json"; }
mk "$now" self "$PWD" "/Users/chrisren/.claude-secondary" 52
mk "$now" other /tmp/o "/weird/path" 9
mk 1      stale /tmp/s "/Users/chrisren/.claude-next" 40

echo "T4 cc-context --me: self-resolve (P4)"
CLAUDE_CODE_SESSION_ID=self bash "$CC" --me 2>/dev/null | jq -e '.session_id=="self" and has("age_s")' >/dev/null && ok "--me resolves self" || no "--me"
( unset CLAUDE_CODE_SESSION_ID; bash "$CC" --me 2>/dev/null | jq -e '.session_id=="self"' >/dev/null ) && ok "--me PWD fallback" || no "--me fallback"

echo "T5 cc-context --quota: fusion + graceful degrade (P6)"
CLAUDE_CODE_SESSION_ID=self bash "$CC" --me --quota 2>/dev/null | jq -e '(.quota.acct=="next2") or (.quota=="n/a")' >/dev/null && ok "quota fused or n/a" || no "quota"
CLAUDE_CODE_SESSION_ID=other bash "$CC" other --quota 2>/dev/null | jq -e '.quota=="n/a"' >/dev/null && ok "unmappable → n/a (anti-trigger)" || no "degrade"

echo "T6 cc-context sweep: bounds growth, protects own (P3)"
touch -t "$(date -v-7H +%Y%m%d%H%M 2>/dev/null || date -d '7 hours ago' +%Y%m%d%H%M)" "$SB/stale.json"
touch -t "$(date -v-7H +%Y%m%d%H%M 2>/dev/null || date -d '7 hours ago' +%Y%m%d%H%M)" "$SB/self.json"
CLAUDE_CODE_SESSION_ID=self bash "$CC" >/dev/null 2>&1
{ [ ! -f "$SB/stale.json" ] && [ -f "$SB/self.json" ]; } && ok "stale swept, own protected (anti-trigger)" || no "sweep"

echo "T7 cc-board: states + rank footer (P7)"
mk "$now" duerow /w2 "/Users/chrisren/.claude-next" 80   # DUE (ctx≥73)
b=$(bash "$BOARD" 2>/dev/null)
echo "$b" | grep -q 'duerow.*DUE'      && ok "DUE state"      || no "DUE"
echo "$b" | grep -q 'self.*next2.*OK'  && ok "OK state + join" || no "OK"
echo "$b" | grep -q 'place next →'     && ok "rank footer"    || no "footer"

rm -rf "$SB"
echo ""
echo "telemetry-e2e: $P passed, $F failed"
[ "$F" -eq 0 ] || exit 1
