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
# $6 = optional pid (P9). Fixtures must carry the fields production actually emits (harness law L1).
mk(){ jq -nc --arg ts "$1" --arg sid "$2" --arg cwd "$3" --arg cfg "$4" --argjson up "$5" --arg pid "${6:-}" \
  '{ts:($ts|tonumber),session_id:$sid,cwd:$cwd,config_dir:$cfg,model:"claude-opus-4-8",effort:"max",window:1000000,used_pct:$up,remaining_pct:(100-$up),input_tokens:($up*10000),
    pid:(if $pid=="" then null else ($pid|tonumber) end)}' > "$SB/$2.json"; }
mk "$now" self "$PWD" "/Users/chrisren/.claude-secondary" 52
mk "$now" other /tmp/o "/weird/path" 9
mk 1      stale /tmp/s "/Users/chrisren/.claude-next" 40

echo "T4 cc-context --me: self-resolve (P4)"
CLAUDE_CODE_SESSION_ID=self bash "$CC" --me 2>/dev/null | jq -e '.session_id=="self" and has("age_s")' >/dev/null && ok "--me resolves self" || no "--me"
( unset CLAUDE_CODE_SESSION_ID; bash "$CC" --me 2>/dev/null | jq -e '.session_id=="self"' >/dev/null ) && ok "--me PWD fallback" || no "--me fallback"

echo "T5 cc-context --quota: fusion + graceful degrade (P6)"
CLAUDE_CODE_SESSION_ID=self bash "$CC" --me --quota 2>/dev/null | jq -e '(.quota.acct=="next2") or (.quota=="n/a")' >/dev/null && ok "quota fused or n/a" || no "quota"
CLAUDE_CODE_SESSION_ID=other bash "$CC" other --quota 2>/dev/null | jq -e '.quota=="n/a"' >/dev/null && ok "unmappable → n/a (anti-trigger)" || no "degrade"

echo "T6 cc-context sweep: reaps only the PROVABLY DEAD; never hides a stall (P3/P9)"
# The sweep used to delete on AGE alone, justified by "a live long-turn re-renders within seconds".
# FALSIFIED 2026-07-14: a session in one long operation — or hung — renders ZERO times and goes
# arbitrarily stale WHILE ALIVE (a respawn sat RUNNING 1h25m at 78m stale). Deleting that row made
# the stall VANISH from cc-board, and ABSENCE IS SILENT where STALE is LOUD. New rule: never delete
# what we cannot PROVE is dead. The live-but-stale case below is the ANTI-TRIGGER that would have
# caught the old policy — a suite that only proved "stale gets swept" passed the fail-silent hole.
sleep 300 & LIVEPID=$!
mk 1 stalledlive /tmp/sl "/Users/chrisren/.claude-next" 16 "$LIVEPID"   # ALIVE, ancient telemetry
mk 1 deadpane    /tmp/dp "/Users/chrisren/.claude-next" 16 "999999"     # pid gone
H7="$(date -v-7H +%Y%m%d%H%M 2>/dev/null || date -d '7 hours ago' +%Y%m%d%H%M)"
touch -t "$H7" "$SB/stale.json" "$SB/self.json" "$SB/stalledlive.json" "$SB/deadpane.json"
CLAUDE_CODE_SESSION_ID=self bash "$CC" >/dev/null 2>&1
[ -f "$SB/stalledlive.json" ] && ok "live-but-stale PRESERVED (the stall stays visible — ANTI-TRIGGER)" || no "sweep hid a live stall"
[ ! -f "$SB/deadpane.json" ]  && ok "provably-dead pid reaped after 6h"                                 || no "dead not reaped"
[ -f "$SB/self.json" ]        && ok "own row protected"                                                 || no "own row swept"
[ -f "$SB/stale.json" ]       && ok "pid-unknown row kept (7d hygiene only — never silently dropped)"   || no "legacy row silently dropped"
kill $LIVEPID 2>/dev/null

echo "T7 cc-board: states + rank footer (P7)"
# HERMETIC quota stub — cc-board's OK↔LIMIT state is a join over the account's LIVE 5h/weekly/Fable
# quota (`claude-accounts --json`). A test that reaches the real feed is NON-DETERMINISTIC: it RED on
# next2@93% weekly (2026-07-14) while cc-board was correct (weekly≥90% ⇒ LIMIT, per the header rule).
# Stub low quota so each row's state is a function of the FIXTURE (ctx + pid), not the operator's usage.
# (Same testability principle as cc-sessions' IT2_BIN; cc-board resolves claude-accounts via PATH.)
QSTUB=$(mktemp -d)
cat > "$QSTUB/claude-accounts" <<'SH'
#!/bin/bash
case "$*" in
  *--rank*) printf 'next\nnext3\nnext4\nnext2\n' ;;
  *)        printf '%s\n' '{"rows":[{"acct":"next","session_pct":5,"weekly_pct":10,"fable_pct":10},{"acct":"next2","session_pct":5,"weekly_pct":10,"fable_pct":10},{"acct":"next3","session_pct":5,"weekly_pct":10,"fable_pct":10},{"acct":"next4","session_pct":5,"weekly_pct":10,"fable_pct":10}]}' ;;
esac
SH
chmod +x "$QSTUB/claude-accounts"
board(){ PATH="$QSTUB:$PATH" bash "$BOARD" 2>/dev/null; }
mk "$now" duerow /w2 "/Users/chrisren/.claude-next" 80   # DUE (ctx≥73)
b=$(board)
echo "$b" | grep -q 'duerow.*DUE'      && ok "DUE state"      || no "DUE"
# liveness states (P9) — DEAD is effect-verified (kill -0), STALL? is a CANDIDATE, never an action.
# STALL? and DEAD must be DISTINCT: age alone conflates a hung session with a healthy long turn
# (both render zero times), so a board that calls them the same thing cannot be paged off safely.
sleep 300 & BLIVE=$!
mk 1 bdead /w3 "/Users/chrisren/.claude-next" 10 "999999"
mk 1 bhang /w4 "/Users/chrisren/.claude-next" 10 "$BLIVE"
b2=$(board)
echo "$b2" | grep -q 'bdead.*DEAD'   && ok "DEAD (pid gone — effect-verified)"        || no "DEAD"
echo "$b2" | grep -q 'bhang.*STALL?' && ok "STALL? (pid ALIVE + stale = candidate)"   || no "STALL?"
kill $BLIVE 2>/dev/null
echo "$b" | grep -q 'self.*next2.*OK'  && ok "OK state + join" || no "OK"
echo "$b" | grep -q 'place next →'     && ok "rank footer"    || no "footer"
rm -rf "$QSTUB"

rm -rf "$SB"
echo ""
echo "telemetry-e2e: $P passed, $F failed"
[ "$F" -eq 0 ] || exit 1
