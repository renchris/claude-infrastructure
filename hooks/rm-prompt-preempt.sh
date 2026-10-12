#!/bin/bash
# rm-prompt-preempt.sh — PermissionRequest(Bash): answer Claude Code's built-in dangerous-removal
# dialog at once with a DENY that carries the rewrite, instead of letting its 2-minute timer deny it
# with nobody watching ("will automatically deny this request in M:SS, to avoid blocking progress
# on an unattended session").
#
# WHY. Census 2026-10-11 (docs/research/autodeny-prompts-2026-10-11/): 64 such auto-denies in two
# weeks, 51 of them in workflow agents; 40 were a `bash -c` script with no rm that 2.1.293's
# inline-shell scanner cannot read. No allow rule or PreToolUse allow clears this check. A
# PermissionRequest hook decision resolves the dialog before its timer, and a hook resolution does
# not count toward the 3-expired-timers-per-session cap.
#
# SCOPE. Only the measured shapes match (hooks/lib/rm_prompt_shape.py: inline_shell, unguarded_var,
# cd_rel_glob); every other dialog passes through untouched. The hook only ever DENIES, so it never
# widens authority: the same command was going to be denied 120 s later anyway.
#
# MODE GATE. In 2.1.293 the 120 s timer exists only in auto, plan (with auto active) and
# bypassPermissions (wln is gated on LLe(mode) or bypassPermissions). In default and acceptEdits the
# same safety dialog waits for the person, so it must pass through: denying it would take the choice
# away and gain nothing.
#
# KNOWN RESIDUALS (both deny-only, never unsafe; the preempt log shows whether they occur):
#  (a) plan mode is accepted unconditionally, although 2.1.293's LLe() times the dialog out in plan
#      only while auto is active and bypass is unavailable; in other plan sessions the hook denies a
#      dialog a person could have answered.
#  (b) an explicit ask rule (e.g. Bash(git push:*)) or a non-timed fallback prompt on a command that
#      also matches a shape is an UNTIMED prompt, and the hook still denies it.
#
# Kill switch: CC_RM_PREEMPT=off (no-op) · CC_RM_PREEMPT=agents (subagent calls only, i.e. the hook
# input carries an agent_id). Log: ~/.claude/logs/rm-prompt-preempt.jsonl (cmd_head + sha256, never
# the full command). Fail-open: any error exits 0 with no output, which shows the normal dialog.
# bash 3.2-safe (hooks may run under /bin/bash).

sw="${CC_RM_PREEMPT:-on}"
[ "$sw" = off ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

in="$(cat)"
[ -n "$in" ] || exit 0

# One jq call: line 1 = tool_name|permission_mode|agent_id (none of which carries "|" or a newline),
# the rest = the command. Malformed JSON ⇒ empty ⇒ not Bash ⇒ pass through.
out="$(jq -r '([(.tool_name // "" | tostring), (.permission_mode // "" | tostring), (.agent_id // "" | tostring)] | join("|")), (.tool_input.command // "" | tostring)' <<<"$in" 2>/dev/null)" || exit 0
head="${out%%$'\n'*}"
tool="${head%%|*}"
rest="${head#*|}"
mode="${rest%%|*}"
agent="${rest#*|}"
cmd="${out#*$'\n'}"
[ "$out" = "$head" ] && cmd=""

[ "$tool" = Bash ] || exit 0
# MODE GATE (see header): the timer exists only in these modes.
case "$mode" in
  auto|bypassPermissions|plan) ;;
  *) exit 0 ;;
esac
if [ "$sw" = agents ] && [ -z "$agent" ]; then exit 0; fi

# Fork-free prefilter: a -c flag (also -lc, -ec, …) or an rm word must be present. Everything else
# cannot match any shape, so python is never started for it.
pre='-[A-Za-z]*c|rm'
[[ $cmd =~ $pre ]] || exit 0

lib="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/lib/rm_prompt_shape.py"
[ -f "$lib" ] || exit 0
printf '%s' "$in" | python3 -I "$lib" --decide 2>/dev/null
exit 0
