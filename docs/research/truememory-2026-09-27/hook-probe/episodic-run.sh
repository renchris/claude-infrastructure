#!/bin/bash
# X6 live delivery probe for #18: does the model actually receive the episodic cue that
# hooks/memory-nudge.sh merges into its JSON? Modeled line-for-line on nudge-supersession-run.sh.
# The cue is RENDERED hermetically by the repo's own hooks/memory-nudge.sh (fixture HOME, state,
# config and index) from a cue-firing prompt on a NON-due count (MEMORY_NUDGE_INTERVAL=1000), so the
# JSON carries the cue alone; then a UserPromptSubmit hook replays that exact JSON into `claude -p`.
# Two arms, so the instrument can say no: `cue` carries the hook, `control` carries none.
# The question never contains the answer: the rendered prompt names an invented topic
# ("zebra-lantern migration") the model must read back from between the cue's single quotes.
# Pass = cue answers "zebra-lantern migration" AND control NONE.
# Usage: bash episodic-run.sh [claude-binary]   (default: claude on PATH; needs >= 2.1.280). Haiku, cheap.
set -u
BIN=${1:-claude}
here=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$here/../../../.." && pwd)
D=$(mktemp -d)
mkdir -p "$D/home" "$D/cfg" "$D/state" "$D/mem"
printf -- '- [A](a.md) — one\n' > "$D/mem/MEMORY.md"
printf '{"session_id":"probe-18","cwd":"/nonexistent-cwd-xyz","prompt":"like we did before with the zebra-lantern migration"}' \
  | HOME="$D/home" CLAUDE_CONFIG_DIR="$D/cfg" MEMORY_NUDGE_STATE_DIR="$D/state" \
    CC_IDL="$D/idl.jsonl" MEMORY_NUDGE_INTERVAL=1000 MEMORY_INDEX_PATH="$D/mem/MEMORY.md" \
    bash "$REPO/hooks/memory-nudge.sh" > "$D/cue.json"
jq -e '.hookSpecificOutput.additionalContext | startswith("EPISODIC CUE:") and contains("zebra-lantern migration")' \
  "$D/cue.json" >/dev/null || { echo "RENDER-FAIL: the rendered nudge lacks the cue"; exit 2; }
printf '#!/bin/bash\ncat %q\n' "$D/cue.json" > "$D/replay.sh"; chmod +x "$D/replay.sh"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"%s/replay.sh"}]}]}}' "$D" > "$D/s-cue.json"
printf '{}' > "$D/s-control.json"
cd "$D" && git init -q
"$BIN" --version
Q='If your context contains a line that begins "EPISODIC CUE", reply with exactly the text that appears between the single quotes in that line, and nothing else. Otherwise reply NONE.'
for v in cue control; do
  printf '%-8s ' "$v"
  "$BIN" -p --settings "$D/s-$v.json" --model claude-haiku-4-5-20251001 "$Q" </dev/null 2>/dev/null | tail -1
done
