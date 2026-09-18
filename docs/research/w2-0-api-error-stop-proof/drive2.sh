#!/bin/bash
# T9 arm F/G driver — the watcher is armed at SESSIONSTART, i.e. BEFORE the turn that dies.
# That is D4's actual design (plan line 451: "it must already exist when the death happens"),
# and it is the arm W2-0 names: does the armed watcher's exit 2 synthesize a turn after an
# api-error turn end? Mail is fed by an external shell while the session sits idle.
P="$(cd "$(dirname "$0")" && pwd)"
arm="$1"; hold="${2:-120}"
# NOTE: this took a third arg, the seconds to wait before feeding its own mailbox. It is GONE, and
# its absence is the record: that in-script feeder raced this script's own `: > mail.txt`, so every
# run ended with an empty mailbox — a state in which the watcher could not fire. Mail is fed from an
# unrelated shell now. See ./README.md § The arm-1 rig.
# mail.txt is NOT truncated here and NOT fed here. The original in-script feeder raced its own
# truncate: every run ended with an empty mailbox, so the watcher could never have fired, and that
# null would have read as "the harness refused to wake" — a verdict about my driver wearing the
# evidence's clothes. The mail is now fed by an UNRELATED shell while the session is idle, which is
# how ../w2-stop-rewake-proof/ did it ("a single echo >> mail.txt from an unrelated shell").
{
  printf '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Say exactly: OK"}]}}\n'
  sleep "$hold"
} | T9_ARM="$arm" CLAUDE_CONFIG_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude-tertiary}" \
    timeout $((hold + 60)) "$HOME/.claude/bin/claude-latest" \
      -p --input-format stream-json --output-format stream-json --verbose \
      --model claude-haiku-4-5-20251001 --strict-mcp-config --max-turns 4 \
      --settings "$P/cfg2/settings.json" > "$P/stream.$arm.jsonl" 2> "$P/stderr.$arm.txt"
echo "arm $arm exited rc=$?"
