#!/usr/bin/env bash
# Meter identification experiment — does the Max weekly limit charge cache_read tokens?
#
# THE QUESTION. Normal agent work moves output, cache_creation and cache_read together
# (corr(output,cache_read)=+0.909 measured), so no regression over observational data can
# separate their weights — A1's NNLS pinned cache_read to the zero BOUNDARY, which is not
# evidence of zero. This forces the decorrelation instead.
#
# THE ARM. One session loads a large context, then N resumed turns each re-read that whole
# context and emit ~4 tokens. Measured shape of a resumed turn: cr=111,920 cc=85 out=4,
# i.e. a ~28,000:1 cache-read-to-output ratio. Under the two live hypotheses:
#   cache_read FREE            -> the meter barely moves, whatever N is
#   cache_read at list weight  -> ~15M cr per weekly point, so ~30M cr shows ~2 pp
# Those predictions differ by orders of magnitude, so a coarse integer meter can still decide.
#
# CONTROLS. (1) A null read before the arm, to show the meter is not drifting on its own.
# (2) An output-only arm AFTER, run only if the cache_read arm shows no movement — because a
# null from a blind instrument is not absence. Movement in the arm is self-evidencing and makes
# the control unnecessary.
#
# SUBJECT. next2 (~/.claude-secondary): 0 live sessions, 0% of its 5h window, 2% weekly,
# 5d14h to reset. Quiet, so no sibling's tokens contaminate the reading.
set -uo pipefail
export PATH="$HOME/.claude/bin:$PATH"
BIN="$(cc-claude-bin | head -1)"
CFG="$HOME/.claude-secondary"
D=/tmp/meter-exp
LOG="$D/log.tsv"
N="${N:-45}"

meter() {  # emit: ts weekly_pct session_pct  (live sweep, next2 only)
  python3 - <<'PY'
import json,subprocess,os,datetime
try:
    out=subprocess.run(["claude-accounts","--json","--fresh"],capture_output=True,text=True,timeout=180).stdout
    d=json.loads(out)
    rows = d if isinstance(d,list) else d.get("accounts",d.get("rows",[]))
    for r in rows:
        if r.get("name")=="next2" or r.get("acct")=="next2":
            print(f"{datetime.datetime.now(datetime.timezone.utc).isoformat()}\t{r.get('weekly_pct')}\t{r.get('session_pct')}")
            break
    else:
        print(f"{datetime.datetime.now(datetime.timezone.utc).isoformat()}\tNA\tNA")
except Exception as e:
    print(f"ERR\t{e}\tNA")
PY
}

echo "=== PHASE 0: baseline (null control) ===" | tee -a "$LOG"
meter | tee -a "$LOG"

echo "=== PHASE 1: build the large context ===" | tee -a "$LOG"
# real repo prose, not gibberish — the model must accept it as ordinary reference material
find /Users/chrisren/Development/claude-infrastructure/docs -name '*.md' -size +8k 2>/dev/null \
  | head -60 | xargs cat 2>/dev/null | head -c 1700000 > "$D/ctx.txt"
echo "context bytes: $(wc -c < "$D/ctx.txt")" | tee -a "$LOG"

SID=$(uuidgen); echo "$SID" > "$D/arm-sid.txt"
echo "arm session: $SID" | tee -a "$LOG"
# The prompt goes in on STDIN, not as an argv word: 1.4 MB as a command argument blew
# ARG_MAX ("Argument list too long", rc 126) and the loop then resumed a session that had
# never loaded. Claude Code's -p reads the prompt from stdin when no positional prompt is given.
{ printf 'Reference material follows. Do not summarise it. Reply with exactly: LOADED\n\n'
  cat "$D/ctx.txt"; } > "$D/prompt.txt"
CLAUDE_CONFIG_DIR="$CFG" timeout 1200 "$BIN" -p --session-id "$SID" --model claude-opus-5 \
  < "$D/prompt.txt" >"$D/load.out" 2>&1
echo "load rc=$? out=$(tail -c 80 "$D/load.out" | tr -d '\n')" | tee -a "$LOG"

echo "=== PHASE 2: $N resumed turns (the cache_read arm) ===" | tee -a "$LOG"
t0=$(date +%s)
for i in $(seq 1 "$N"); do
  CLAUDE_CONFIG_DIR="$CFG" timeout 300 "$BIN" -p --resume "$SID" --model claude-opus-5 \
    "Reply with exactly: OK" >/dev/null 2>&1
  rc=$?
  if [ $((i % 10)) -eq 0 ] || [ "$i" -eq 1 ]; then
    printf 'turn %d/%d rc=%d elapsed=%ds\n' "$i" "$N" "$rc" "$(( $(date +%s) - t0 ))" | tee -a "$LOG"
    meter | tee -a "$LOG"
  fi
  [ $rc -ne 0 ] && echo "  turn $i FAILED rc=$rc" | tee -a "$LOG"
done

echo "=== PHASE 3: final read ===" | tee -a "$LOG"
meter | tee -a "$LOG"
echo "=== DONE in $(( $(date +%s) - t0 ))s ===" | tee -a "$LOG"
