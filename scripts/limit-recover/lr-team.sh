#!/bin/bash
# lr-team.sh — the ONE live-member test for a team lead (FLEET_V2 W6, D4.1). The census, the probe
# and the last read before a move all ask "does this lead still have a live teammate?", and before
# this file each asked it differently: census.py matched the substring '@session-<sid8>' against
# every process, which twice matched quoted prose (a brief that merely mentioned a teammate).
#
# The rule: a live, non-zombie process whose argv[0] basename is `claude` or `claude.exe` and whose
# argv carries the two adjacent tokens `--parent-session-id <full lead sid>`. Keyed only on live
# processes (D4.2), never on a team config file, which outlives its members. The same rule catches
# named teams (`--agent-id w@session-<team name>`), which the '@session-<sid8>' form missed.
# lr_recon/census.py `is_member_argv` is the Python copy; tests/lr-team.bats pins the two equal.
#
#   source lr-team.sh; lr_has_live_teammate <lead sid> [snapshot]   rc 0 = a member is live
#   source lr-team.sh; lr_team_members <lead sid> [snapshot]        prints the live member count
#   lr-team.sh has|count <lead sid>                                 the same, as a command
#
# Snapshot: "<pid> <stat> <args…>" per line, from ONE ps taken before any filtering, so the filter
# is never in the population it filters (a `ps | grep -- "--parent-session-id S"` lists the grep).
# The pattern reaches awk through the environment, never argv. LR_TEAM_PS_SNAPSHOT (a file) is the
# test seam. bash 3.2-safe.

lr_team_snapshot() {
  if [ -n "${LR_TEAM_PS_SNAPSHOT:-}" ]; then
    cat "$LR_TEAM_PS_SNAPSHOT" 2>/dev/null
    return 0
  fi
  LC_ALL=C ps -axww -o pid=,stat=,args= 2>/dev/null
}

# A process line, not the continuation of an argv that contained a raw newline: a pid, then a
# ps stat code. Exits with the member count so both entry points share one program.
# shellcheck disable=SC2016  # an awk program, deliberately unexpanded by the shell
_LR_TEAM_AWK='
$1 ~ /^[0-9]+$/ && $2 ~ /^[DIRSTUZ][A-Za-z<>+]*$/ && $2 !~ /^Z/ {
  a0 = $3; sub(/^.*\//, "", a0)
  if (a0 != "claude" && a0 != "claude.exe") next
  for (i = 4; i < NF; i++) if ($i == "--parent-session-id" && $(i + 1) == ENVIRON["LR_TEAM_SID"]) { n++; next }
}
END { print n + 0 }'

lr_team_members() { # $1=lead sid [$2=snapshot] → prints the count of live members
  local sid="${1:-}" snap
  [ -n "$sid" ] || {
    echo 0
    return 0
  }
  if [ $# -ge 2 ]; then snap="$2"; else snap="$(lr_team_snapshot)"; fi
  printf '%s\n' "$snap" | LR_TEAM_SID="$sid" awk "$_LR_TEAM_AWK"
}

lr_has_live_teammate() { # $1=lead sid [$2=snapshot] → rc 0 when a member process is live
  local n
  n="$(lr_team_members "$@")"
  [ "${n:-0}" -gt 0 ]
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    has)
      lr_has_live_teammate "${2:-}"
      exit $?
      ;;
    count) lr_team_members "${2:-}" ;;
    *)
      echo "usage: lr-team.sh has|count <lead sid>" >&2
      exit 2
      ;;
  esac
fi
