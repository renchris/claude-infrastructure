#!/bin/bash
# X6 live delivery probe for #12: does the model actually receive the memory nudge's supersession
# clause? The nudge is RENDERED hermetically by the repo's own hooks/memory-nudge.sh (fixture HOME,
# state, config and index; MEMORY_NUDGE_INTERVAL=1 forces a fire, as tests/memory-nudge-budget.bats
# does), then a UserPromptSubmit hook replays that exact JSON into a `claude -p` run.
# Two arms, so the instrument can say no: `nudge` carries the hook, `control` carries none.
# The question never contains the answer: the model must read the two words after
# "Replaces: <practice> —" out of its context. Pass = nudge answers "ruling pending" AND control NONE.
# Usage: bash nudge-supersession-run.sh [claude-binary]   (default: claude on PATH). Haiku, cheap.
set -u
BIN=${1:-claude}
here=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$here/../../../.." && pwd)
D=$(mktemp -d)
mkdir -p "$D/home" "$D/cfg" "$D/state" "$D/mem"
printf -- '- [A](a.md) — one\n' > "$D/mem/MEMORY.md"
printf '{"session_id":"probe-12","cwd":"/nonexistent-cwd-xyz","prompt":"x"}' \
  | HOME="$D/home" CLAUDE_CONFIG_DIR="$D/cfg" MEMORY_NUDGE_STATE_DIR="$D/state" \
    CC_IDL="$D/idl.jsonl" MEMORY_NUDGE_INTERVAL=1 MEMORY_INDEX_PATH="$D/mem/MEMORY.md" \
    bash "$REPO/hooks/memory-nudge.sh" > "$D/nudge.json"
jq -e '.hookSpecificOutput.additionalContext | contains("ruling pending")' "$D/nudge.json" >/dev/null \
  || { echo "RENDER-FAIL: the rendered nudge lacks the clause"; exit 2; }
printf '#!/bin/bash\ncat %q\n' "$D/nudge.json" > "$D/replay.sh"; chmod +x "$D/replay.sh"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"%s/replay.sh"}]}]}}' "$D" > "$D/s-nudge.json"
printf '{}' > "$D/s-control.json"
cd "$D" && git init -q
"$BIN" --version
Q='If your context contains a sentence that begins "A CORRECTION edits the file it corrects", reply with exactly the two words that immediately follow "Replaces: <practice> —" in that sentence, and nothing else. Otherwise reply NONE.'
for v in nudge control; do
  printf '%-8s ' "$v"
  "$BIN" -p --settings "$D/s-$v.json" --model claude-haiku-4-5-20251001 "$Q" </dev/null 2>/dev/null | tail -1
done
