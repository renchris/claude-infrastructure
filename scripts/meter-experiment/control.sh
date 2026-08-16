#!/usr/bin/env bash
# POSITIVE CONTROL for the meter experiment — run ONLY if the cache_read arm moved the meter 0 pp.
#
# WHY IT EXISTS. A null reading from a blind instrument is not absence. If the cache_read arm
# shows no movement, there are two explanations and they are opposite in consequence:
#   (a) cache_read genuinely carries no weekly-limit weight   <- the finding
#   (b) the meter did not update at all during the run        <- an instrument failure
# This arm distinguishes them by driving the ONE class both hypotheses agree is charged —
# OUTPUT — and requiring the meter to move. If it moves here and not there, (a) holds.
#
# Both hypotheses are normalised to the same output weight (3.83 pp/Mtok), so this arm is
# deliberately NOT a test between them. It tests the instrument.
#
# Mechanically long generations, not prose: "write an essay" yields a few thousand tokens and
# is refusal-prone at length; enumerating is reliable and reaches the per-response output cap.
set -uo pipefail
export PATH="$HOME/.claude/bin:$PATH"
BIN="$(cc-claude-bin | head -1)"
CFG="$HOME/.claude-secondary"
D=/tmp/meter-exp
LOG="$D/control-log.tsv"
N="${N:-8}"

meter() {
  python3 - <<'PY'
import json,subprocess,datetime
try:
    out=subprocess.run(["claude-accounts","--json","--fresh"],capture_output=True,text=True,timeout=180).stdout
    d=json.loads(out)
    for r in (d.get("rows") or []):
        if r.get("acct")=="next2":
            print(f"{datetime.datetime.now(datetime.timezone.utc).isoformat()}\t{r.get('weekly_pct')}\t{r.get('session_pct')}")
            break
except Exception as e:
    print(f"ERR\t{e}\tNA")
PY
}

echo "=== CONTROL baseline ===" | tee -a "$LOG"
meter | tee -a "$LOG"
: > "$D/control-sids.txt"   # start the per-call session-id list empty

t0=$(date +%s)
for i in $(seq 1 "$N"); do
  S=$(uuidgen); echo "$S" >> "$D/control-sids.txt"
  CLAUDE_CONFIG_DIR="$CFG" timeout 900 "$BIN" -p --session-id "$S" --model claude-opus-5 \
    "Output the integers from 1 to 12000, one per line, with no other text at all." \
    >/dev/null 2>&1
  printf 'control call %d/%d rc=%d elapsed=%ds\n' "$i" "$N" "$?" "$(( $(date +%s) - t0 ))" | tee -a "$LOG"
done

echo "=== CONTROL final ===" | tee -a "$LOG"
meter | tee -a "$LOG"
