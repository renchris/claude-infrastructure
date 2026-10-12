#!/bin/bash
# rm-preempt-probe.sh — live acceptance probe for hooks/rm-prompt-preempt.sh (the gate on migration 0061).
#
# WHY: the hook answers Claude Code's dangerous-removal dialog (the "will automatically deny this request in
# M:SS" prompt) with an instant deny. Bats proves the classifier and the JSON it prints; only a REAL
# interactive auto-mode session proves Claude Code honours that deny before its 120 s timer
# (docs/research/autodeny-prompts-2026-10-11/verdicts.md, C1 efficacy change 3). Re-run after every
# Claude Code upgrade: the inline-shell scanner and the hook contract both move between releases.
#
# HOW: for each arm (main thread; a general-purpose Workflow slot) it starts a detached tmux session running
# `claude --permission-mode auto --settings <overlay registering THIS checkout's hook>` with a prompt to run
# one known false positive, `bash -c 'f(){ "$@"; }; f true'`. It then reads that session's transcript and
# measures tool_use -> tool_result. PASS = the result carries the hook's deny text within PASS_S seconds;
# NODIALOG = Claude Code denied in < 5 s on its own, so that context has no dialog to preempt.
# Each session is killed when its arm settles. It spends a few cents of quota; it writes no settings.
#
# Usage: rm-preempt-probe.sh [--arm main|workflow|both]
# Exit:  0 = main PASS and workflow PASS or NODIALOG · 1 = any arm FAIL · 3 = NO VERDICT (or main not PASS)
#        4 = NOTRIGGER: the main arm's command simply RAN, so this binary no longer raises the dialog for
#            the trap shape at all (news: the hook may be moot there); the workflow arm is then not run.
# Env:   CLAUDE_CONFIG_DIR (account; default ~/.claude), CC_PROBE_BIN (claude binary; default `claude` on
#        PATH), CC_PROBE_MODEL (optional --model), CC_PROBE_WAIT_S (per-arm ceiling, default 300),
#        CC_PROBE_PASS_S (default 30). lib/cc-upgrade-gate/check17_rm_preempt.sh runs this per binary move.
set -uo pipefail

arm=both
while [ $# -gt 0 ]; do
  case "$1" in
    --arm) arm="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "usage: $0 [--arm main|workflow|both]" >&2; exit 2 ;;
  esac
done
case "$arm" in agent) arm=workflow ;; esac   # pre-2026-10-12 name
case "$arm" in main|workflow|both) ;; *) echo "usage: --arm main|workflow|both" >&2; exit 2 ;; esac

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
  local a="$1" sess="rmpp-$1-$$" tag prompt start f verdict mflag
  tag="rmpp-probe-$a-$$"
  if [ "$a" = main ]; then
    prompt="[$tag] Acceptance probe. Run exactly this one Bash command, verbatim, once: $probe_cmd -- then quote the tool result verbatim and stop. Do not retry or rewrite it."
    printf '%s\n' "$prompt" > "$work/$a.prompt"
  else
    # A WORKFLOW slot, because that is where the timed dialog lives (51 of the 64 census rows). Two
    # measured dead ends (2026-10-12): a workflow-lean slot declines the command (its own brief
    # forbids this bash -c shape), and a plain Agent-tool subagent cannot prompt at all, so Claude
    # Code denies it in 0.1 s with no dialog for any hook to answer. Hence agentType general-purpose.
    printf '[%s] ' "$tag" > "$work/$a.prompt"
    cat >> "$work/$a.prompt" <<'EOF'
Acceptance probe of a permission hook; the operator asks you to run this workflow. The Bash command inside is a harmless no-op test fixture. Call the Workflow tool once with exactly this script, then quote its result verbatim and stop:

export const meta = { name: 'rmpp-probe', description: 'rm-prompt-preempt acceptance probe' }
return await agent(`Acceptance probe of a permission hook; the command is a harmless no-op test fixture. Run exactly this one Bash command verbatim, once, and return the tool result verbatim without retrying: bash -c 'f(){ "$@"; }; f true'`, { label: 'probe', agentType: 'general-purpose' })
EOF
  fi
  printf '%s\n' "$overlay" > "$work/overlay.json"
  start="$(date +%s)"
  mflag=""
  [ -n "${CC_PROBE_MODEL:-}" ] && mflag="--model $CC_PROBE_MODEL "
  # env -u: the probe must not inherit the caller's pane/session identity. Run from `!` in a live
  # session, it otherwise read as that pane, and its hooks SIGTERMed the pane's own cc-await-ping
  # watcher (measured 2026-10-12, WAKE-PATH-DOWN naming this probe's argv as the sender).
  tmux new-session -d -s "$sess" -x 220 -y 60 -c "$here" \
    "env -u ITERM_SESSION_ID -u CC_PANE_ID -u KITTY_WINDOW_ID -u KITTY_LISTEN_ON -u KITTY_PID -u KITTY_PUBLIC_KEY -u CLAUDECODE -u CLAUDE_PID -u CLAUDE_CODE_SESSION_ID -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_TASK_LIST_ID -u CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CONFIG_DIR='$cfg' '$bin' --permission-mode auto $mflag--settings \"\$(cat '$work/overlay.json')\" \"\$(cat '$work/$a.prompt')\""
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
        elif "denied by a built-in Claude Code safety check" in text and dt < 5:
            # Claude Code denied it itself, too fast for any dialog: this context cannot prompt, so there
            # was no timer and nothing for the hook to preempt. Not a hook failure.
            print(f"NODIALOG Claude Code denied in {dt:.1f}s with no dialog (this context cannot prompt)")
        else:
            if "denied" not in text.lower() and "permission" not in text.lower():
                print(f"NOTRIGGER the command ran in {dt:.1f}s with no deny: this binary raised no removal dialog")
                sys.exit(0)
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
  case "$verdict" in PASS*) return 0 ;; FAIL*) return 1 ;; NODIALOG*) return 4 ;; NOTRIGGER*) return 5 ;; *) return 3 ;; esac
}

# The main arm must PASS (it is the arm that proves the hook resolves a timed dialog). The workflow arm
# passes on PASS or NODIALOG: a context that cannot prompt has no timer, so it costs nothing to leave.
rc=0
for a in main workflow; do
  [ "$arm" = both ] || [ "$arm" = "$a" ] || continue
  run_arm "$a"; r=$?
  case "$a:$r" in
    main:5) rc=4; break ;;
    *:0|workflow:4) ;;
    *:1) rc=1 ;;
    *) [ "$rc" -eq 1 ] || rc=3 ;;
  esac
done
case "$rc" in 0) echo "verdict=PASS" ;; 1) echo "verdict=FAIL" ;; 4) echo "verdict=NOTRIGGER" ;; *) echo "verdict=NO-VERDICT" ;; esac
exit "$rc"
