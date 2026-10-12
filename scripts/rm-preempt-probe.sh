#!/bin/bash
# rm-preempt-probe.sh — live acceptance probe for hooks/rm-prompt-preempt.sh (the gate on migration 0061).
#
# WHY: the hook answers Claude Code's dangerous-removal dialog (the "will automatically deny this request in
# M:SS" prompt) with an instant deny. Bats proves the classifier and the JSON it prints; only a REAL
# interactive auto-mode session proves Claude Code honours that deny before its 120 s timer
# (docs/research/autodeny-prompts-2026-10-11/verdicts.md, C1 efficacy change 3). Re-run after every
# Claude Code upgrade: the inline-shell scanner and the hook contract both move between releases.
#
# HOW: for each arm (main thread; a workflow-lean subagent) it starts a detached tmux session running
# `claude --permission-mode auto --settings <overlay registering THIS checkout's hook>` with a prompt to run
# one known false positive, `bash -c 'f(){ "$@"; }; f true'`. It then reads that session's transcript and
# measures tool_use -> tool_result. PASS = the result carries the hook's deny text within PASS_S seconds.
# Each session is killed when its arm settles. It spends a few cents of quota; it writes no settings.
#
# Usage: rm-preempt-probe.sh [--arm main|agent|both]      exit 0 PASS (all arms) · 1 FAIL · 3 NO VERDICT
# Env:   CLAUDE_CONFIG_DIR (account; default ~/.claude), CC_PROBE_BIN (claude binary; default `claude` on
#        PATH), CC_PROBE_WAIT_S (per-arm ceiling, default 300), CC_PROBE_PASS_S (default 30).
set -uo pipefail

arm=both
while [ $# -gt 0 ]; do
  case "$1" in
    --arm) arm="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "usage: $0 [--arm main|agent|both]" >&2; exit 2 ;;
  esac
done
case "$arm" in main|agent|both) ;; *) echo "usage: --arm main|agent|both" >&2; exit 2 ;; esac

# ~/.claude/scripts/ is a per-file symlink farm: resolve this file to the checkout before deriving
# the repo root, or the probe would register ~/.claude's hook and read ~/.claude's transcript slug.
p="${BASH_SOURCE[0]}"
while [ -L "$p" ]; do
  d="$(cd "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
  case "$p" in /*) ;; *) p="$d/$p" ;; esac
done
here="$(cd "$(dirname "$p")/.." && pwd)"
hook="$here/hooks/rm-prompt-preempt.sh"
cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
bin="${CC_PROBE_BIN:-$(command -v claude)}"
wait_s="${CC_PROBE_WAIT_S:-300}"
pass_s="${CC_PROBE_PASS_S:-30}"
MARK='Denied at once by the rm-prompt-preempt hook'

for need in tmux jq python3; do
  command -v "$need" >/dev/null 2>&1 || { echo "verdict=NO-VERDICT missing $need" >&2; exit 3; }
done
[ -x "$hook" ] || { echo "verdict=NO-VERDICT hook not executable: $hook" >&2; exit 3; }
[ -n "$bin" ] && [ -x "$bin" ] || { echo "verdict=NO-VERDICT no claude binary (set CC_PROBE_BIN)" >&2; exit 3; }

overlay="$(jq -nc --arg h "$hook" \
  '{hooks:{PermissionRequest:[{matcher:"Bash",hooks:[{type:"command",command:$h,timeout:10}]}]}}')"
probe_cmd="bash -c 'f(){ \"\$@\"; }; f true'"
slug="$(printf '%s' "$here" | sed 's/[^A-Za-z0-9]/-/g')"
tdir="$cfg/projects/$slug"
work="$(mktemp -d "${TMPDIR:-/tmp}/rm-preempt-probe.XXXXXX")"

run_arm() {
  local a="$1" sess="rmpp-$1-$$" tag prompt start f verdict
  tag="rmpp-probe-$a-$$"
  if [ "$a" = main ]; then
    prompt="[$tag] Acceptance probe. Run exactly this one Bash command, verbatim, once: $probe_cmd -- then quote the tool result verbatim and stop. Do not retry or rewrite it."
  else
    prompt="[$tag] Acceptance probe. Spawn one Agent with subagent_type workflow-lean whose only task is to run exactly this one Bash command verbatim, once: $probe_cmd -- and return the tool result verbatim without retrying. Quote its return and stop."
  fi
  printf '%s\n' "$prompt" > "$work/$a.prompt"
  printf '%s\n' "$overlay" > "$work/overlay.json"
  start="$(date +%s)"
  tmux new-session -d -s "$sess" -x 220 -y 60 -c "$here" \
    "CLAUDE_CONFIG_DIR='$cfg' '$bin' --permission-mode auto --settings \"\$(cat '$work/overlay.json')\" \"\$(cat '$work/$a.prompt')\""
  verdict="NO-VERDICT timed out after ${wait_s}s"
  while [ $(( $(date +%s) - start )) -lt "$wait_s" ]; do
    sleep 5
    # The probe's own transcript is the top-level jsonl written since the arm started that names the tag
    # (only files newer than the prompt file are read; the project dir holds GBs). Its subagents write
    # <sid>/subagents/*.jsonl, which do not carry the tag, so they are added by session id.
    main_f="$(find "$tdir" -maxdepth 1 -name '*.jsonl' -newer "$work/$a.prompt" -print0 2>/dev/null \
      | xargs -0 grep -lF "$tag" 2>/dev/null | head -1)"
    [ -n "$main_f" ] || continue
    f="$main_f $(find "${main_f%.jsonl}/subagents" -name '*.jsonl' 2>/dev/null | tr '\n' ' ')"
    # shellcheck disable=SC2086  # $f is a space-separated file list on purpose
    verdict="$(python3 -I - "$MARK" "$pass_s" $f <<'PY'
import json, sys
from datetime import datetime
mark, pass_s, files = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
def ts(r):
    return datetime.fromisoformat(r["timestamp"].replace("Z", "+00:00")).timestamp()
uses, res = {}, {}
for p in files:
    for line in open(p, errors="ignore"):
        try:
            r = json.loads(line)
        except ValueError:
            continue
        c = (r.get("message") or {}).get("content")
        if not isinstance(c, list) or "timestamp" not in r:
            continue
        for b in c:
            if b.get("type") == "tool_use" and b.get("name") == "Bash" and "f true" in json.dumps(b.get("input")):
                uses[b["id"]] = ts(r)
            elif b.get("type") == "tool_result":
                t = b.get("content")
                res[b.get("tool_use_id")] = (ts(r), json.dumps(t) if not isinstance(t, str) else t)
for u, t0 in uses.items():
    if u in res:
        t1, text = res[u]
        dt = t1 - t0
        if mark in text:
            print(("PASS" if dt <= pass_s else "FAIL") + f" hook deny after {dt:.1f}s")
        else:
            print(f"FAIL no hook deny; result after {dt:.1f}s: {text[:160]!r}")
        sys.exit(0)
print("PENDING")
PY
)"
    [ "$verdict" = PENDING ] && { verdict="NO-VERDICT timed out after ${wait_s}s"; continue; }
    break
  done
  tmux kill-session -t "$sess" 2>/dev/null
  echo "arm=$a verdict=$verdict"
  case "$verdict" in PASS*) return 0 ;; FAIL*) return 1 ;; *) return 3 ;; esac
}

rc=0
for a in main agent; do
  [ "$arm" = both ] || [ "$arm" = "$a" ] || continue
  run_arm "$a"; r=$?
  [ "$r" -gt "$rc" ] && rc=$r
done
case "$rc" in 0) echo "verdict=PASS" ;; 1) echo "verdict=FAIL" ;; *) echo "verdict=NO-VERDICT" ;; esac
exit "$rc"
