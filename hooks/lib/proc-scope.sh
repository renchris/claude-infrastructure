#!/usr/bin/env bash
# hooks/lib/proc-scope.sh — ONE reader for "which processes belong to THIS worktree".
#
# EXTRACTED, NOT COPIED (backlog a3eaa0dc1be2, D8 build order step 1). These helpers were born in
# scripts/gate-cleanup.sh:69-92, where they scope a SIGKILL. A second consumer now needs the same
# scoping to answer "is a job of mine executing?" (hooks/lib/session-busy.sh), and a second COPY of
# a kill-selector's scoping rules is the failure this repo has already paid for once: the rules
# below encode two properties that a re-derivation loses silently, and the first draft of
# gate-cleanup selected a LIVE PEER's `claude` process for SIGKILL when it lost the second one.
#
#   (1) PHYSICAL PATHS. Containment is a string prefix, so a symlinked or /private-prefixed
#       spelling of the same directory matches NOTHING (macOS /tmp → /private/tmp). `pwd -P` on
#       the root is what makes the scope real rather than textual.
#   (2) ARGV-POSITION MATCHING, never a substring scan. A Claude session's argv embeds its entire
#       task prompt, so a peer whose brief merely NAMES `ship-land.sh` or `bats` matches a naive
#       `case "$rest" in *ship-land.sh*)`. Only the first two argv tokens are inspected, and only
#       their BASENAME. Text is not evidence of execution.
#
# CONTRACT: pure function definitions, no side effects on source, bash 3.2, POSIX tools only. Every
# reader degrades to empty rather than dying, so a hook sourcing this under `set -u` reads
# "unknown" instead of aborting. Sourced, never executed.
#
# Env seams (tests): CC_PROC_SCOPE_PS / CC_PROC_SCOPE_CWD — a `ps -eo pid=,ppid=,command=`
# substitute and a `<pid>` → cwd resolver. The LEGACY gate-cleanup names are honoured as a
# fallback so tests/pkill-scope.bats (36 cases over a SIGKILL selector) keeps driving the real
# code path through the seams it already uses; a rename there would have been a silent
# re-scoping of the one script that must never be re-scoped by accident.

ps_scope_all() {  # → "<pid> <ppid> <command…>" per line
  if   [ -n "${CC_PROC_SCOPE_PS:-}" ];   then "$CC_PROC_SCOPE_PS"
  elif [ -n "${CC_GATE_CLEANUP_PS:-}" ]; then "$CC_GATE_CLEANUP_PS"
  else ps -eo pid=,ppid=,command=
  fi
}

ps_scope_cwd_of() {  # <pid> → its cwd, or empty when unknowable (a process we may not inspect)
  if   [ -n "${CC_PROC_SCOPE_CWD:-}" ];   then "$CC_PROC_SCOPE_CWD" "$1"; return 0
  elif [ -n "${CC_GATE_CLEANUP_CWD:-}" ]; then "$CC_GATE_CLEANUP_CWD" "$1"; return 0
  fi
  lsof -a -d cwd -p "$1" -Fn 2>/dev/null | sed -n 's/^n//p' | head -1
}

ps_scope_physical() {  # <dir> → its PHYSICAL path (empty when the dir does not exist)
  [ -d "${1:-}" ] || return 1
  ( cd "$1" 2>/dev/null && pwd -P ) || return 1
}

ps_scope_under() {  # <root> <path> → 0 when <path> is at or under <root>
  case "${2:-}" in "${1:-}") return 0 ;; "${1:-}"/*) return 0 ;; *) return 1 ;; esac
}

ps_scope_ppid_of() {  # <pid> <snapshot> → that pid's ppid, or empty
  printf '%s\n' "${2:-}" | awk -v p="${1:-}" '$1==p {print $2; exit}' || true
}

ps_scope_ancestors() {  # <pid> <snapshot> → " <pid> <parent> <grandparent> … " (space-delimited set)
                        # Self + every ancestor: never signal, and never COUNT, the hand holding the
                        # knife. The cycle guard is load-bearing — a malformed table must not spin.
  local _p="${1:-}" _snap="${2:-}" _set _a
  _set=" ${_p} "
  _a="$(ps_scope_ppid_of "${_p}" "${_snap}")"
  while [ -n "$_a" ] && [ "$_a" != "0" ] && [ "$_a" != "1" ]; do
    case "$_set" in *" $_a "*) break ;; esac
    _set="$_set$_a "
    _a="$(ps_scope_ppid_of "$_a" "${_snap}")"
  done
  printf '%s' "$_set"
}

ps_scope_in_set() {  # <pid> <set> → 0 when present
  case "${2:-}" in *" ${1:-} "*) return 0 ;; *) return 1 ;; esac
}

ps_scope_argv_bases() {  # <command line> → BASENAME of argv[0] and argv[1], one per line.
                         # THE ARGV-POSITION RULE, in one place. Callers `case` over these two and
                         # nothing else; a caller that greps the whole line has left the contract.
  local _t0 _t1
  _t0="${1%% *}"; _t1="${1#* }"; _t1="${_t1%% *}"
  printf '%s\n%s\n' "${_t0##*/}" "${_t1##*/}"
}

ps_scope_is_session() {  # <command line> → 0 when this is an interactive Claude session, never a job.
                         # Belt-and-suspenders shared by both consumers: gate-cleanup must never
                         # SIGNAL one, session-busy must never COUNT one as work (a session is not
                         # a job — counting it makes every session eternally "busy with itself").
  local _t0="${1%% *}"
  case "${_t0##*/}" in claude|claude-*|node) return 0 ;; esac
  case "${1:-}" in *"/node_modules/.bin/claude"*) return 0 ;; esac
  return 1
}

ps_scope_descendants() {  # <roots> <snapshot> <exclude-set> → roots + every descendant, space-delimited
                          # Fixed-point iteration rather than recursion: bash 3.2, no arrays, and a
                          # process table that changes under us can only ever add children we pick
                          # up on the next pass. A descendant cannot escape the scope because every
                          # root came from a containment test.
  local _sel="${1:-}" _snap="${2:-}" _ex="${3:-}" _pass=0 _added pid ppid rest
  while [ "$_pass" -lt 12 ]; do
    _pass=$(( _pass + 1 )); _added=0
    while read -r pid ppid rest; do
      [ -n "${pid:-}" ] || continue
      case "$pid" in ''|*[!0-9]*) continue ;; esac
      ps_scope_in_set "$pid" "$_ex" && continue
      ps_scope_is_session "$rest" && continue
      case " $_sel " in *" $pid "*) continue ;; esac
      case " $_sel " in *" $ppid "*) _sel="$_sel$pid "; _added=1 ;; esac
    done <<EOF
$_snap
EOF
    [ "$_added" = "0" ] && break
  done
  printf '%s' "$_sel"
}

ps_scope_cwd_map() {  # <space-separated pids> → "<pid><TAB><cwd>" per line, in ONE lsof call.
                      # WHY THIS EXISTS: gate-cleanup resolves cwd only for the handful of pids that
                      # already passed an argv-position name test, so per-pid `lsof` is free there.
                      # session-busy's classifier is the INVERSE — everything that is not
                      # infrastructure is work — so its candidate set is the whole process table,
                      # and per-pid lsof turned a 0.6 s ledger read into minutes. Same two facts,
                      # same seams; only the number of forks changes.
                      # The per-pid SEAM still wins when set, so a fixture that stubs cwd resolution
                      # keeps driving the same code path it always did.
  local pids="${1:-}" p csv=""
  [ -n "$pids" ] || return 1
  if [ -n "${CC_PROC_SCOPE_CWD:-}" ] || [ -n "${CC_GATE_CLEANUP_CWD:-}" ]; then
    for p in $pids; do printf '%s\t%s\n' "$p" "$(ps_scope_cwd_of "$p")"; done
    return 0
  fi
  for p in $pids; do csv="$csv,$p"; done
  lsof -a -d cwd -p "${csv#,}" -Fpn 2>/dev/null | awk '
    /^p/ { pid = substr($0,2); next }
    /^n/ { if (pid != "" && !seen[pid]++) printf "%s\t%s\n", pid, substr($0,2) }'
}
