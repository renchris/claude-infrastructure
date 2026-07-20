# desk.zsh — `claude-desk`: one command to START the machine-wide orchestrator desk.
#
# Source from ~/.zshrc (after the claude-next block, which this composes):
#     [[ -f "$HOME/.claude/lib/desk.zsh" ]] && source "$HOME/.claude/lib/desk.zsh"
#
# THE PROBLEM THIS SOLVES: a hand-started Claude session cannot presume the desk role, because the
# identity lived in two places neither of which a fresh session has — an ad-hoc brief pasted into a
# handoff-fire recycle prompt (re-authored into /tmp every time, evaporating on recycle) and a
# hand-written ~/.claude/cc-roles/desk. `claude-desk` does both, mechanically, in the right order.
#
# Composition mirrors claude-fable(): a THIN wrapper that sets up state and delegates to
# claude-next() for binary/config/model/effort/isolation. Account variants follow the house pattern
# (claude-desk2/3/4 = CLAUDE_CONFIG_DIR prefix), exactly like claude-next2 / claude-fable2.

CLAUDE_DESK_HOME="${CLAUDE_DESK_HOME:-$HOME/Development/claude-infrastructure}"
CLAUDE_DESK_BRIEF="${CLAUDE_DESK_BRIEF:-$CLAUDE_DESK_HOME/docs/templates/desk-boot-brief.md}"

claude-desk() {
  local reg="$HOME/.claude/bin/desk-register" roles="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"

  # --- preflight: refuse to start a desk that cannot know what a desk IS ---
  if [[ ! -f "$CLAUDE_DESK_BRIEF" ]]; then
    echo "✗ claude-desk: canonical brief missing — $CLAUDE_DESK_BRIEF" >&2
    echo "  The brief is the desk's role SSOT; starting without it yields a session that does not" >&2
    echo "  know it is the desk. Check out claude-infrastructure or set \$CLAUDE_DESK_BRIEF." >&2
    return 1
  fi
  if [[ ! -x "$reg" ]]; then
    echo "✗ claude-desk: desk-register missing or not executable — $reg" >&2
    echo "  Without it the pane never claims ~/.claude/cc-roles/desk: no pages, no worker" >&2
    echo "  back-channel pings, no cc-classify never-reap, and invisible to the desk invariant." >&2
    return 1
  fi

  # --- warn LOUDLY before stealing the role from a desk that is still alive ---
  # Two live desks is a genuine failure (pages and worker pings follow the role file, so the older
  # desk silently goes deaf). desk-register prints "reassigned …" either way; this adds liveness.
  local prev; prev="$(head -n1 "$roles/desk" 2>/dev/null | tr -d '[:space:]')"
  local here="${ITERM_SESSION_ID##*:}"
  if [[ -n "$prev" && "$prev" != "$here" ]]; then
    if command -v cc-sessions >/dev/null 2>&1 && cc-sessions --json 2>/dev/null | grep -q "$prev"; then
      echo "⚠️  claude-desk: pane $prev currently holds the desk role and still looks ALIVE." >&2
      echo "   Taking the chair here makes THAT desk deaf (pages + worker pings follow the role" >&2
      echo "   file). Retire it first — handoff-fire.sh self-close --terminal in that pane — or" >&2
      echo "   continue if it is a leftover. Proceeding in 5s; ^C to abort." >&2
      sleep 5
    fi
  fi

  # --- claim the role BEFORE launch ---
  # Ordering is load-bearing: claude-next execs in THIS pane, so the role file must already name
  # this pane when the new session's SessionStart hooks run — that is what lets
  # hooks/desk-brief-inject.sh recognise the desk and inject the brief.
  "$reg" || return 1

  # --- launch ---
  # POINTER kickoff, not the brief body: when desk-brief-inject.sh is wired the body is already in
  # context (injected at SessionStart) and pasting it again would just duplicate ~8KB; when it is
  # NOT wired, this pointer makes the session read the SSOT itself. Correct in both worlds, and it
  # matches the repo's established /goal pointer form.
  local kickoff="You are the machine-wide orchestrator DESK for this machine (this pane now holds ~/.claude/cc-roles/desk).

Read ${CLAUDE_DESK_BRIEF} in full and assume that role NOW — it is your standing brief and it is binding. If it already appears above (injected at SessionStart because you hold the role), do not re-read it.

Then do exactly what its 'First three actions' say: orient (cc-blockers, cc-board + cc-backlog, cc-notify --list, /wrap), confirm you hold the role, and DRIVE every non-blocked track. Do not re-introduce yourself and do not ask what to do."

  ( cd "$CLAUDE_DESK_HOME" && claude-next "$kickoff" "$@" )
}

# Account variants — same shape as claude-next2/3/4 and claude-fable2.
alias claude-desk2='CLAUDE_CONFIG_DIR=$HOME/.claude-secondary claude-desk'
alias claude-desk3='CLAUDE_CONFIG_DIR=$HOME/.claude-tertiary claude-desk'
alias claude-desk4='CLAUDE_CONFIG_DIR=$HOME/.claude-quaternary claude-desk'
