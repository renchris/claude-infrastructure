#!/usr/bin/env bash
# session-kind.sh — which succession rail fits THIS session. Sourced by hooks that prescribe one.
#
# A Claude Code BACKGROUND JOB (`claude --bg`, `/background`, or a recycle's "Move to background and
# exit") has no pane. Before 2026-10-03 every hook told it to "run the /handoff rails", and every rail
# it could reach refused: the /handoff skill fires --split-right (needs a pane), a pane --recycle
# needs $ITERM_SESSION_ID or $KITTY_WINDOW_ID (the daemon strips both). Job 032aa97f was told exactly
# that, ran it, got the refusal, and could only ask the operator to /clear and paste.
#
# The mark is CLAUDE_JOB_DIR with its state.json: measured on 2.1.284, a job's tool and hook env carry
# it, and do NOT carry CLAUDE_CODE_SESSION_KIND (docs/research/bgjob-recycle-2026-10-03/README.md).
# handoff-fire.sh keeps its own copy of the test (hf_bgjob_self), because it runs standalone.

cc_bgjob_short() { # → echoes this session's background-job short id; rc 1 when it is not a background job
  local d="${CLAUDE_JOB_DIR:-}" s
  [ -n "$d" ] && [ -f "$d/state.json" ] || return 1
  d="${d%/}"; s="${d##*/}"
  case "$s" in ''|*[!0-9a-f]*) return 1 ;; esac
  printf '%s' "$s"
}

# The one step that works for a background job, as a sentence a hook can splice in.
cc_bgjob_succession_step() { # $1=short → echoes the step
  printf '%s' "This session is Claude Code background job ${1} — it has no pane, so the /handoff skill's --split-right fire and a pane recycle both refuse here. Write the bridge brief to a file, then run \`~/.claude/scripts/handoff-fire.sh --recycle --prompt-file <brief>\`: for a background job it starts a successor job (same cwd, account, model and effort; your /goal re-armed) and stops this one, keeping its conversation (\`claude attach ${1}\`)."
}
