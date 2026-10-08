#!/usr/bin/env bash
# run-ours.sh — one run of OUR loop on the fixed form task: headless Claude Code driving the
# agent-browser CLI through its Bash tool, reading the cards from screenshots with its Read tool.
#
# This is the free arm of backlog 9e97305d19d0 (SDK browser toolset loop vs our agent-browser
# loop). It spends plan quota only; no API key is read or needed. The SDK arm reuses the same
# fixture/, expected.json, PROMPT text and score.py, so the two arms differ only in the loop.
#
# Usage: run-ours.sh <label> [model]        model defaults to claude-haiku-5-5 (the video's model)
# Env:   CLAUDE_BIN   binary to run (default: the 2.1.293 install, whose upgrade gate read GREEN
#                     with claude-haiku-5-5; the run is labelled by the init line, never by this)
#        RUN_BOUND_S  watchdog for the claude process (default 900)
# Out:   one JSON line appended to results.jsonl beside this script; the raw stream, saved leads
#        and screenshots stay in the printed work dir (they carry base64 images, so not committed).
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
LABEL=${1:?usage: run-ours.sh <label> [model]}
MODEL=${2:-claude-haiku-5-5}
CLAUDE_BIN=${CLAUDE_BIN:-$HOME/.claude-293/node_modules/.bin/claude}
BOUND=${RUN_BOUND_S:-900}
SKILL=$HOME/.claude/skills/agent-browser/SKILL.md
SESSION="blp-$LABEL-$$"

[ -x "$CLAUDE_BIN" ] || { echo "run-ours: no executable claude at $CLAUDE_BIN" >&2; exit 2; }
[ -r "$SKILL" ] || { echo "run-ours: agent-browser skill not readable at $SKILL" >&2; exit 2; }
command -v agent-browser >/dev/null || { echo "run-ours: agent-browser not on PATH" >&2; exit 2; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/blp-$LABEL.XXXXXX")
PORT=$(python3 -I -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')
URL="http://127.0.0.1:$PORT/crm.html"

SRV="" WD="" CP=""
cleanup() {
  [ -n "$WD" ] && kill "$WD" 2>/dev/null
  [ -n "$SRV" ] && kill "$SRV" 2>/dev/null
  agent-browser --session "$SESSION" close >/dev/null 2>&1
  return 0
}
trap cleanup EXIT INT TERM

python3 -I "$HERE/server.py" "$PORT" "$WORK/saved.jsonl" &
SRV=$!
i=0
until curl -fsS -o /dev/null "$URL"; do
  i=$((i + 1))
  [ "$i" -ge 50 ] && { echo "run-ours: fixture server never answered on $PORT" >&2; exit 2; }
  sleep 0.1
done

# The prompt names an ABSOLUTE screenshot path: agent-browser resolves a relative one against its
# daemon's cwd, not the caller's, and in the pilot run that cost the model 3 calls hunting the file.
# The page is open before the clock starts, as in the video (FIG 3 begins on a loaded CRM page).
agent-browser --session "$SESSION" set viewport 1280 800 >/dev/null 2>&1
agent-browser --session "$SESSION" open "$URL" >/dev/null || { echo "run-ours: agent-browser could not open $URL" >&2; exit 2; }

PROMPT="A CRM page is already open in a browser at $URL. It shows three scanned, handwritten booth lead cards, one at a time ('Next card' moves between them; the zoom buttons enlarge a card that is too small to read). Enter each card as a new lead in the form exactly as written on the card, and click 'Save lead' once per card. Drive the browser with the agent-browser CLI and pass --session $SESSION on every call. To read a card, save a screenshot with agent-browser to an absolute path under $WORK/ and view that file with the Read tool. Do not close the browser. Stop when all three leads are saved."

T0=$(python3 -I -c 'import time; print(time.time())')
(
  cd "$WORK" || exit 2
  exec "$CLAUDE_BIN" -p "$PROMPT" \
    --model "$MODEL" \
    --setting-sources project \
    --strict-mcp-config \
    --disable-slash-commands \
    --no-session-persistence \
    --append-system-prompt-file "$SKILL" \
    --tools Bash,Read \
    --allowedTools "Bash(agent-browser:*)" Read \
    --permission-mode dontAsk \
    --output-format stream-json --verbose \
    > "$WORK/stream.jsonl" 2> "$WORK/stream.err"
) &
CP=$!
# The watchdog's sleep must not inherit our stdout and must die with the watchdog: killing only the
# subshell orphaned the sleep, which held a caller's pipe (`run-ours.sh … | tail`) open for the
# full bound after every run and stalled the next run by up to 15 minutes.
(
  exec >/dev/null 2>&1
  sleep "$BOUND" &
  SL=$!
  trap 'kill "$SL"; exit 0' TERM
  wait "$SL" && kill "$CP"
) &
WD=$!
wait "$CP"
RC=$?
T1=$(python3 -I -c 'import time; print(time.time())')
WALL=$(python3 -I -c "print($T1 - $T0)")

LINE=$(python3 -I "$HERE/score.py" "$WORK/saved.jsonl" "$WORK/stream.jsonl" "$WALL") || { echo "run-ours: scoring failed; raw data in $WORK" >&2; exit 1; }
LINE=$(printf '%s' "$LINE" | python3 -I -c 'import json,sys; d=json.load(sys.stdin); d.update(label=sys.argv[1], rc=int(sys.argv[2]), bound_s=int(sys.argv[3])); print(json.dumps(d))' "$LABEL" "$RC" "$BOUND")
printf '%s\n' "$LINE" >> "$HERE/results.jsonl"
printf '%s\n' "$LINE"
echo "run-ours: raw data in $WORK" >&2
