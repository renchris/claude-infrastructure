#!/bin/bash
# run.sh — one d1_successor run: one case, one brief variant, one rep, in a FRESH `claude -p`
# process (docs/plans/USAGE_LEVERS.md § W7+ §2 D1 "Offline d1-successor"; §3 "Evals").
#
#   run.sh <case.json> <out_dir> [<brief params JSON>]
#
# out_dir must sit under /tmp/lev-eval (the eval cwd root). It gets:
#   fx/            the fixture and the run's cwd (build_cases.py fixture): predecessor.jsonl cut at the
#                  idle point, brief.txt, messages.jsonl, CLAUDE.md (the global instructions and the
#                  session repo's project memory: what production loads at start), repo/ (git archive
#                  at the idle time; removed after the run, it is only the successor's working tree)
#   fx/.claude/settings.json  the ONLY settings the run loads: capture-hook.sh on every tool.
#                  --setting-sources project reads the fixture root alone, so no user setting and no
#                  production hook runs inside an eval, and the fixture's CLAUDE.md loads as memory
#   case.json · stream.jsonl (the run's stream-json output) · capture.jsonl (the hook's log) ·
#   stderr · rc · grade.json
# Env: CC_LEVER_EXCLUDE=1 (never scored as a production arm); the operator stores (backlog,
# decisions, mailbox) point into out_dir/stores, and the run refuses to start if any resolves inside
# the real ~/.claude/autonomy or mailbox. No MCP servers. D1S_MODEL (claude-opus-5-5), D1S_EFFORT
# (high), D1S_TIMEOUT_S (900), D1S_CLAUDE (default: bin/cc-claude-bin, the launcher's pinned binary).
# Exit: the run's rc (124 on the timeout); 2 usage or refused; 3 fixture failed.
set -u
[ $# -ge 2 ] || { echo "usage: run.sh <case.json> <out_dir> [<params JSON>]" >&2; exit 2; }
CASE="$1"; OUT="$2"; PARAMS="${3:-}"
H="$(cd "$(dirname "$0")" && pwd -P)"
REPO="$(cd "$H/../../.." && pwd -P)"
mkdir -p /tmp/lev-eval
ROOT="$(cd /tmp/lev-eval && pwd -P)"
mkdir -p "$OUT" || exit 2
OUT="$(cd "$OUT" && pwd -P)"
case "$OUT" in "$ROOT"/*) ;; *) echo "run.sh: out_dir $OUT is not under $ROOT" >&2; exit 2 ;; esac
[ -f "$CASE" ] || { echo "run.sh: no case file $CASE" >&2; exit 2; }

export CC_LEVER_EXCLUDE=1
S="$OUT/stores"
export CC_BACKLOG_FILE="$S/backlog.jsonl" CC_BACKLOG_IDL="$S/idl.jsonl" \
       CC_BACKLOG_VALIDATED="$S/backlog-validated.json" CC_BACKLOG_GATE_LOG="$S/backlog-gate.jsonl" \
       CC_DECISIONS_DIR="$S/decisions" CC_IDL="$S/decide-idl.jsonl" \
       CC_MAILBOX_DIR="$S/mailbox" CC_COMMS_ALARM_DIR="$S/comms-alarm"
for real in "$HOME/.claude/autonomy" "$HOME/.claude/mailbox"; do
  [ -d "$real" ] || continue
  rr="$(cd "$real" && pwd -P)"
  case "$S" in "$rr"|"$rr"/*) echo "run.sh: refusing: stores dir $S is inside $rr" >&2; exit 2 ;; esac
done
mkdir -p "$S/decisions" "$S/mailbox" "$OUT/tmp"
: >"$OUT/capture.jsonl"
[ "$CASE" -ef "$OUT/case.json" ] || cp "$CASE" "$OUT/case.json" || exit 2

PY=/usr/bin/python3
[ -x "$PY" ] || PY=python3
if [ -n "$PARAMS" ]; then
  "$PY" -I "$H/build_cases.py" fixture "$CASE" "$OUT/fx" --params "$PARAMS" >"$OUT/fixture.out" 2>"$OUT/fixture.err" || exit 3
else
  "$PY" -I "$H/build_cases.py" fixture "$CASE" "$OUT/fx" >"$OUT/fixture.out" 2>"$OUT/fixture.err" || exit 3
fi
FX="$OUT/fx"

mkdir -p "$FX/.claude" || exit 3
jq -cn --arg hook "/bin/bash $H/capture-hook.sh" \
  '{hooks:{PreToolUse:[{matcher:"*", hooks:[{type:"command", command:$hook, timeout:20}]}]}}' >"$FX/.claude/settings.json"

# shellcheck disable=SC1091  # #! helpers run via their interpreter, not by path (kalloc leak; plan KALLOC_TRIGGER_ELIMINATION W4)
. "$REPO/scripts/lib/cc-run.sh"
CLAUDE="${D1S_CLAUDE:-$(cc_run "$REPO/bin/cc-claude-bin" 2>/dev/null)}"
[ -n "$CLAUDE" ] && [ -x "$CLAUDE" ] || { echo "run.sh: no claude binary (D1S_CLAUDE or bin/cc-claude-bin)" >&2; exit 2; }
printf '%s\n' "$CLAUDE" >"$OUT/claude-bin"

cd "$FX" || exit 3
D1S_FIXTURE="$FX" D1S_CAPTURE="$OUT/capture.jsonl" TMPDIR="$OUT/tmp" \
  perl -e 'alarm shift @ARGV; exec @ARGV or exit 127' "${D1S_TIMEOUT_S:-900}" \
  "$CLAUDE" -p --input-format stream-json --output-format stream-json --verbose \
    --model "${D1S_MODEL:-claude-opus-5-5}" --effort "${D1S_EFFORT:-high}" \
    --strict-mcp-config --mcp-config '{"mcpServers":{}}' \
    --setting-sources project \
    <"$FX/messages.jsonl" >"$OUT/stream.jsonl" 2>"$OUT/stderr"
rc=$?
[ "$rc" -eq 142 ] && rc=124   # SIGALRM
printf '%s\n' "$rc" >"$OUT/rc"
cd "$ROOT" || exit 3

"$PY" -I "$H/grade.py" code "$CASE" "$OUT" >"$OUT/grade.json" 2>"$OUT/grade.err"
"$PY" -I "$H/build_cases.py" clean "$OUT/fx" 2>>"$OUT/grade.err"
exit "$rc"
