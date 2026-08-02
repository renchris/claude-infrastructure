#!/usr/bin/env bash
# cc-resume-shell.sh — the launcher-side half of cross-account `--resume`.
#
# Sourced by ~/.zshrc (and by tests under bash). Defines ONE function, `_cc_resume_pin`, which
# every `claude*` launcher calls before it builds its launch line. It turns the out-of-the-box
# invocation Claude Code itself prints —
#     Resume this session with: claude --resume <id>
# — into something that works from any directory on any of the 4 accounts, by resolving the id
# to the store and cwd that actually hold it (bin/cc-resume-resolve) and reporting back what the
# launcher must change.
#
# CONTRACT
#   _cc_resume_pin <default_config_dir> "$@"
#     always returns 0 (fail-open: an unresolvable id must reach Claude so IT prints the error)
#     sets:
#       CC_RESUME_ARGS   array — argv, with an id PREFIX expanded to the full session id.
#                        Always set, always safe to `set -- "${CC_RESUME_ARGS[@]}"`.
#       CC_RESUME_CFG    config dir the launcher must use, or "" to keep its own.
#       CC_RESUME_CWD    directory the launcher must run in, or "" to stay put.
#
# WHY A FUNCTION AND NOT A WRAPPER SCRIPT: pinning means changing the config dir and the cwd of
# the process that becomes Claude. A child script cannot do that to its parent, and re-exec'ing
# through a wrapper would lose the launchers' worktree gate, effort defaults and close-attrib
# instrumentation. So the resolution is a script (testable, tracked) and the mutation is a
# function (in the launcher's own shell).
#
# Env: CC_RESUME_NO_RESOLVE=1 disables everything (pass argv through untouched) — the escape
#      hatch for deliberately resuming a transplanted transcript on another account.
#      CC_RESUME_MKDIR=0 refuses to recreate a reaped worktree path (default: recreate + warn).
#      CC_RESUME_RESOLVE_BIN overrides the resolver path (tests).

# shellcheck disable=SC2034  # CC_RESUME_CFG/CWD/ARGS are the RETURN VALUES — read by the caller.
_cc_resume_pin() {
  CC_RESUME_ARGS=()
  CC_RESUME_CFG=""
  CC_RESUME_CWD=""

  local _default_cfg="${1:-}"; shift 2>/dev/null || true
  CC_RESUME_ARGS=("$@")
  [ "${CC_RESUME_NO_RESOLVE:-0}" = "1" ] && return 0

  # ── find the --resume VALUE, if there is one ────────────────────────────────────────────
  # A bare `--resume`/`-r` (no value, or followed by another flag) is Claude's interactive
  # picker. That path is cwd-scoped BY DESIGN — the operator is browsing "sessions from here" —
  # so we must not touch it. Only an explicit id is a request to go find that one session.
  # EVERY local is declared here, never inside the loop. In zsh, `local x` on a name that already
  # exists in scope PRINTS `x=<value>` instead of silently re-declaring — so a `local _a` in the
  # loop body leaked one line of argv to stdout per iteration (bash is silent, which is exactly
  # why it survived the bash test run and only showed up under a real zsh).
  local _i=1 _n=$# _val="" _idx=0 _inline=0 _a="" _next="" _j=0
  while [ "$_i" -le "$_n" ]; do
    eval "_a=\${$_i}"
    case "$_a" in
      --resume=*) _val="${_a#--resume=}"; _idx=$_i; _inline=1; break ;;
      --resume|-r)
        if [ "$_i" -lt "$_n" ]; then
          _j=$((_i+1))
          eval "_next=\${$_j}"
          # Belt-and-braces, deliberately NOT load-bearing: cc-resume-resolve rejects any
          # argument starting with `-` on its own (tested), so removing this guard changes no
          # behaviour — it only avoids spawning the resolver to be told no. Recorded as
          # redundant rather than left looking like the thing that makes bare --resume safe.
          case "$_next" in -*) ;; *) _val="$_next"; _idx=$_j ;; esac
        fi
        break ;;
    esac
    _i=$((_i+1))
  done
  [ -n "$_val" ] || return 0

  # ── resolve ─────────────────────────────────────────────────────────────────────────────
  local _bin="${CC_RESUME_RESOLVE_BIN:-$HOME/.claude/bin/cc-resume-resolve}"
  [ -x "$_bin" ] || return 0
  local _out _rc
  _out="$("$_bin" "$_val" 2>/dev/null)"; _rc=$?
  if [ "$_rc" -ne 0 ]; then
    # 4 = ambiguous prefix: the operator must disambiguate, and Claude's own error would say
    # "No conversation found", which is both wrong and undiagnostic. Every other non-zero code
    # (3 not-found, 2 usage, and any code added later) falls through to Claude unchanged —
    # fail-open is the default for an enum we may not have heard of yet.
    if [ "$_rc" -eq 4 ]; then
      "$_bin" "$_val" >/dev/null
    fi
    return 0
  fi

  local _sid="" _account="" _cfg="" _cwd="" _cwd_exists=1 _k _v
  while IFS='=' read -r _k _v; do
    case "$_k" in
      sid)        _sid="$_v" ;;
      account)    _account="$_v" ;;
      config_dir) _cfg="$_v" ;;
      cwd)        _cwd="$_v" ;;
      cwd_exists) _cwd_exists="$_v" ;;
    esac
  done <<EOF
$_out
EOF
  [ -n "$_sid" ] || return 0

  # ── argv: expand a prefix to the full id ────────────────────────────────────────────────
  # Rebuilt by APPEND, never by indexed assignment: bash arrays are 0-indexed and zsh's are
  # 1-indexed, so any `arr[$i]=` here would be correct in one shell and off by one — silently
  # corrupting argv — in the other. `+=` means the same thing in both.
  if [ "$_val" != "$_sid" ] && [ "$_idx" -gt 0 ]; then
    local _j2=1 _a2
    CC_RESUME_ARGS=()
    while [ "$_j2" -le "$_n" ]; do
      eval "_a2=\${$_j2}"
      if [ "$_j2" -eq "$_idx" ]; then
        if [ "$_inline" = 1 ]; then CC_RESUME_ARGS+=("--resume=$_sid"); else CC_RESUME_ARGS+=("$_sid"); fi
      else
        CC_RESUME_ARGS+=("$_a2")
      fi
      _j2=$((_j2+1))
    done
  fi

  # ── config dir: pin only when the default genuinely cannot reach the transcript ─────────
  # ~/.claude-next/projects is a SYMLINK to ~/.claude/projects (account 1, two names), so a
  # session "in ~/.claude" is already reachable from ~/.claude-next. Comparing resolved
  # projects/ trees, not dir names, is what keeps this from announcing a pointless switch.
  local _def_real="" _got_real=""
  [ -n "$_default_cfg" ] && _def_real="$(cd "$_default_cfg/projects" 2>/dev/null && pwd -P)"
  _got_real="$(cd "$_cfg/projects" 2>/dev/null && pwd -P)"
  if [ -n "$_got_real" ] && [ "$_def_real" != "$_got_real" ]; then
    CC_RESUME_CFG="$_cfg"
    [ -t 2 ] && printf '↩︎ session %s lives on account %s (%s) — resuming there.\n' \
      "${_sid%%-*}" "${_account}" "${_cfg##*/}" >&2
  fi

  # ── cwd: Claude keys the project dir off cwd, so we must stand where the session stood ──
  [ -n "$_cwd" ] || return 0
  local _here; _here="$(pwd -P 2>/dev/null)"
  local _there; _there="$(cd "$_cwd" 2>/dev/null && pwd -P)"
  [ -n "$_there" ] && [ "$_there" = "$_here" ] && return 0

  if [ "$_cwd_exists" != "1" ]; then
    # The worktree was reaped. The transcript is intact and is the whole value, but Claude can
    # only find it from a cwd that hashes to its project dir — so the path has to exist. An
    # empty directory is enough to resume the CONVERSATION; it is not a restored working tree.
    if [ "${CC_RESUME_MKDIR:-1}" = "0" ]; then
      [ -t 2 ] && printf '⚠️  %s no longer exists — cannot resume %s from here (CC_RESUME_MKDIR=0).\n' \
        "$_cwd" "${_sid%%-*}" >&2
      return 0
    fi
    case "$_cwd" in
      /*) ;;
      *) return 0 ;;
    esac
    mkdir -p "$_cwd" 2>/dev/null || { [ -t 2 ] && printf '⚠️  could not recreate %s\n' "$_cwd" >&2; return 0; }
    [ -t 2 ] && printf '⚠️  worktree %s was reaped — recreated it EMPTY so the transcript can load.\n   The conversation resumes; the working tree does not. For a real restore use limit-recover.\n' \
      "$_cwd" >&2
  fi

  CC_RESUME_CWD="$_cwd"
  [ -t 2 ] && [ "$_cwd_exists" = "1" ] && printf '↩︎ session %s was born in %s — resuming there.\n' \
    "${_sid%%-*}" "$_cwd" >&2
  return 0
}
