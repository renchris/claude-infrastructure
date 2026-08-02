#!/usr/bin/env bash
# agent-identity.sh — SSOT: "is THIS session a background Agent-Teams assignee?"
#
# WHY IT IS A LIB (2026-08-02). Two Stop-hook arms need the same fact and it must be ONE oracle:
#   · session-continue's wake floor abstains for an assignee — its lead wakes it over the teammate
#     channel, so the floor's premise ("nothing will wake it") is false for it.
#   · completion-assert uses it to decide whether "this session recorded no writes" is TRUSTWORTHY
#     evidence of innocence, or merely an unread transcript.
# Two copies of a discriminator this load-bearing is the two-oracles-disagreeing trap (MEMORY.md
# uniform-error-ratio-indicts-the-model): the copies rot apart and the disagreement is invisible.
# Extracted VERBATIM from hooks/session-continue.sh, where it was proven; only the names changed.
#
# MEASURED SHAPE (2026-08-02, CC 2.1.220) — a background/named subagent is a REAL child session:
#   claude.exe --agent-id <n>@session-<t> --agent-name <n> --team-name <t> --parent-session-id <p>
# A FOREGROUND in-process subagent has no such process and is not covered here — it fires
# SubagentStop, for which nothing is registered, so it can never be blocked anyway.
#
# Pure function definitions only — no side effects on source (safe under `set -u`).
# Seams (tests): CC_WF_PSTABLE_FILE · CC_WF_START_PID · CC_WF_MAX_HOPS · CC_WF_TEAM_ROOTS.

# (A) Am I an Agent-Teams assignee? Read MY OWN process ancestry — the assignee's CC process is this
# hook's grandparent, and CC gives a teammate three flags it gives nothing else:
#   --agent-id <name>@session-<team>   --agent-name <n>   --team-name <t>
# ANCESTRY, not a machine-wide scan, and a THREE-flag conjunction rather than one, because argv
# carries whole briefs: any single flag also matches every session that merely MENTIONS it (memory
# pgrep-f-matches-agent-briefs — read 50 where the truth was 1; a live scan run while writing this
# very hook returned a bogus `--agent-id processes` row off an awk command line). Requiring all three
# AND requiring the process to be an ANCESTOR of this hook means the only thing that can match is the
# CC process actually running me.
# WHY NOT REUSE handoff-fire.sh's agent_id_on_tty (:942): it is tty-keyed, and a hook HAS NO TTY —
# `ps -o tty= -p $$` reads `??` here (verified). That oracle resolves its tty from the session
# registry, and an assignee pane has no registry row at all (134/134, lead-crash-watchdog.sh:596).
agent_assignee_argv() { # → 0 = this session IS a team assignee; echoes the matched agent-id
  local tbl
  if [ -n "${CC_WF_PSTABLE_FILE:-}" ] && [ -f "${CC_WF_PSTABLE_FILE}" ]; then
    tbl="$(cat "$CC_WF_PSTABLE_FILE" 2>/dev/null)"
  else
    tbl="$(ps -axo pid=,ppid=,command= 2>/dev/null)"
  fi
  [ -n "$tbl" ] || return 1
  # CC_WF_START_PID exists so the suite can pin where the walk begins: a hook's own $$ is a pid the
  # test cannot know in advance, so without it the ancestry could only be tested by stubbing out the
  # walk itself — i.e. not tested at all. $$ (not BASHPID) is right in production: it survives the
  # command substitution this function is called inside, and names the hook process whose ancestry
  # actually contains the CC process.
  printf '%s\n' "$tbl" | awk -v start="${CC_WF_START_PID:-$$}" -v maxhop="${CC_WF_MAX_HOPS:-8}" '
    { p = $1; PP[p] = $2; c = ""; for (i = 3; i <= NF; i++) c = c " " $i; CMD[p] = c " " }
    END {
      cur = start
      for (h = 0; h < maxhop; h++) {
        if (cur == "" || cur == "0" || cur == "1") exit 1
        c = CMD[cur]
        if (c ~ / --agent-id / && c ~ / --agent-name / && c ~ / --team-name /) {
          n = split(c, w, " ")
          for (i = 1; i < n; i++) if (w[i] == "--agent-id") { print w[i + 1]; exit 0 }
        }
        cur = PP[cur]
      }
      exit 1
    }' 2>/dev/null
}

# CROSS-SOURCE CONFIRMATION for (A), and it is not belt-and-braces — it closes a false positive that
# is CONCRETE IN THIS REPO. `ps -o command=` flattens argv into one line, which destroys the
# difference between "separate argv words" and "words inside a single quoted argument" — and a
# session's BRIEF is one such argument. An infra session fired with a brief that quotes assignee argv
# (this very file does) would carry all three flags as apparent words and read as its own assignee.
# handoff-fire.sh hit the identical trap and documents it at :949-957.
# So the argv claim is checked against the harness's OWN record: the team config CC writes at
# $CLAUDE_CONFIG_DIR/teams/<team>/config.json. Roots are scanned the way teammate-auto-shutdown.sh
# does (:70-90) — the *2/*3/*4 launchers each run a DIFFERENT real config dir, so a team led from any
# of them records its members ONLY under that dir.
# TRICHOTOMOUS, because "no config" and "config says no" are different facts:
#   0 = CONFIRMED (a non-lead member of that team bears this agent-name)
#   1 = REFUTED   (that team's config exists and has no such member ⇒ the argv match was prose)
#   2 = UNKNOWN   (no readable config for that team ⇒ the argv evidence stands alone)
agent_team_member_confirms() { # $1="<name>@session-<team>"
  local id="${1:-}" nm team root cfg seen=0
  case "$id" in *@session-*) ;; *) return 2 ;; esac
  nm="${id%%@session-*}"; team="session-${id##*@session-}"
  case "$nm"   in ''|*[!A-Za-z0-9_.-]*) return 2 ;; esac
  case "$team" in ''|*[!A-Za-z0-9_.-]*) return 2 ;; esac
  # Build the root list explicitly rather than word-splitting a defaulted string: the default has to
  # carry BOTH a quoted path and a glob, and a `${VAR:-a b*}` that must split one and expand the other
  # is exactly the kind of seam that reads fine and silently resolves to nothing.
  local roots=()
  if [ -n "${CC_WF_TEAM_ROOTS:-}" ]; then
    # shellcheck disable=SC2206  # deliberate split of a space-separated test seam
    roots=( ${CC_WF_TEAM_ROOTS} )
  else
    [ -n "${CLAUDE_CONFIG_DIR:-}" ] && roots+=( "${CLAUDE_CONFIG_DIR}/teams" )
    for root in "$HOME"/.claude*/teams; do [ -d "$root" ] && roots+=( "$root" ); done
  fi
  for root in "${roots[@]+"${roots[@]}"}"; do
    [ -n "$root" ] || continue
    cfg="$root/$team/config.json"
    [ -f "$cfg" ] || continue
    seen=1
    # A member is an ASSIGNEE when it is not the lead: CC records the lead with tmuxPaneId "leader"
    # and agentType "team-lead" (verified against live configs).
    if jq -e --arg n "$nm" '[.members[]? | select(.name == $n and .tmuxPaneId != "leader" and .agentType != "team-lead")] | length > 0' \
         "$cfg" >/dev/null 2>&1; then
      return 0
    fi
  done
  [ "$seen" = 1 ] && return 1
  return 2
}
