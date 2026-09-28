#!/bin/bash
# Does Claude Code deliver a hook's additionalContext to the model? Four arms:
# UserPromptSubmit top-level / nested, SessionStart top-level / nested.
# Usage: bash run.sh [claude-binary]   (default: claude on PATH). Uses Haiku to keep it cheap.
# Result 2026-09-27 on 2.1.114 and 2.1.280: top-level -> NONE, nested -> the token.
set -u
BIN=${1:-claude}
D=$(mktemp -d)
here=$(cd "$(dirname "$0")" && pwd)
for s in top hso sstop ssnest; do cp "$here/$s.sh" "$D/$s.sh"; chmod +x "$D/$s.sh"; done
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"%s/top.sh"}]}]}}' "$D" > "$D/s-top.json"
printf '{"hooks":{"UserPromptSubmit":[{"hooks":[{"type":"command","command":"%s/hso.sh"}]}]}}' "$D" > "$D/s-hso.json"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"%s/sstop.sh"}]}]}}' "$D" > "$D/s-sstop.json"
printf '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"%s/ssnest.sh"}]}]}}' "$D" > "$D/s-ssnest.json"
cd "$D" && git init -q
"$BIN" --version
for v in top hso sstop ssnest; do
  printf '%-7s ' "$v"
  "$BIN" -p --settings "$D/s-$v.json" --model claude-haiku-4-5-20251001 \
    'If any token starting with PROBE- appears anywhere in your context, reply with exactly that token. Otherwise reply NONE.' </dev/null 2>/dev/null | tail -1
done
