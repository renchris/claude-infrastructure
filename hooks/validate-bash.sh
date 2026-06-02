#!/bin/bash
# PreToolUse hook for Bash command validation
#
# Complements settings.json deny/ask permissions with pattern-matching that
# permission prefixes can't catch (DDL inside commands, compound command
# escape hatches, bypass-flag detection aware of quoted message bodies).
#
# Exit 0 with JSON to stdout for decisions. Exit 2 for blocking errors.
#
# Rollback knobs (env):
#   VALIDATE_BASH_LEGACY=1       Use regex-only flag detection (skips shlex).
#   VALIDATE_BASH_DISABLED=1     No-op the hook entirely (emergency only).

# Kill switch
if [[ "${VALIDATE_BASH_DISABLED:-0}" == "1" ]]; then
  exit 0
fi

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Source the argv-aware flag detector. If unavailable, caller can force
# legacy mode; otherwise fall back silently on a per-call basis below.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
if [[ -f "$LIB_DIR/is-true-flag.sh" && "${VALIDATE_BASH_LEGACY:-0}" != "1" ]]; then
  # shellcheck source=lib/is-true-flag.sh
  source "$LIB_DIR/is-true-flag.sh"
  HAVE_IS_TRUE_FLAG=1
else
  HAVE_IS_TRUE_FLAG=0
fi

deny() {
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$1"
  }
}
EOF
  exit 0
}

warn() {
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "ask",
    "permissionDecisionReason": "$1"
  }
}
EOF
  exit 0
}

# check_real_flag <flag> — returns 0 if CMD contains <flag> as a real argv
# token (in a non-inert head, outside message bodies). Returns 1 otherwise.
# Falls back to word-boundary regex when the shlex helper is unavailable.
check_real_flag() {
  local flag="$1"
  if [[ "$HAVE_IS_TRUE_FLAG" == "1" ]]; then
    is_true_flag "$flag" "$CMD"
    local rc=$?
    # rc=0 → real flag; rc=1 → substring only; rc=2 → unclear (fail safe = block)
    [[ "$rc" == "0" || "$rc" == "2" ]] && return 0
    return 1
  else
    # Legacy fallback: word-boundary regex (still false-positives on message
    # bodies that contain the literal bracketed by spaces).
    local pattern="(^|[[:space:]])${flag//./\\.}([[:space:]]|\$)"
    echo "$CMD" | grep -qE "$pattern"
  fi
}

# ── Hard deny: catastrophic or rule-violating patterns ────────────────

# System damage
if echo "$CMD" | grep -qE '(rm[[:space:]]+-rf[[:space:]]+/[^a-zA-Z]|rm[[:space:]]+-rf[[:space:]]+\$HOME|rm[[:space:]]+-rf[[:space:]]+~(/|$|[[:space:]])|sudo[[:space:]]+rm|:\(\)\{[[:space:]]*:\|:&[[:space:]]*\};:)'; then
  deny "Dangerous command pattern blocked: potential system damage (rm -rf /, rm -rf ~, sudo rm, or fork bomb)."
fi

# DDL via any mechanism (turso shell, sqlite3, echo|pipe, etc.) — only
# blocked when in DATABASE-COMMAND context. This avoids false positives on
# commit messages that discuss DDL ("fix: block DROP TABLE in migration").
# A command like `echo "DROP TABLE x" | turso db shell` still matches because
# BOTH conditions are true.
if echo "$CMD" | grep -qiE '\b(turso|sqlite3?|psql|mysql|mariadb|libsql|drizzle-kit[[:space:]]+(push|drop|migrate))\b' \
   && echo "$CMD" | grep -qiE '\b(DROP[[:space:]]+TABLE|DROP[[:space:]]+DATABASE|DROP[[:space:]]+INDEX|ALTER[[:space:]]+TABLE|CREATE[[:space:]]+TABLE|TRUNCATE[[:space:]]+TABLE)\b'; then
  deny "DDL blocked — all schema changes must go through Drizzle migrations (pnpm generate). See CLAUDE.md critical rule #1."
fi

# drizzle-kit push bypasses migration history
if echo "$CMD" | grep -qE 'drizzle-kit[[:space:]]+push'; then
  deny "drizzle-kit push bypasses migration history and causes schema drift. Use pnpm generate instead."
fi

# git add -f / --force (argv-aware)
if check_real_flag "--force" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
  deny "git add --force blocked — gitignored files are intentionally excluded. Force-adding bypasses .gitignore protection."
fi
if check_real_flag "-f" && echo "$CMD" | grep -qE 'git[[:space:]]+add\b'; then
  deny "git add -f blocked — gitignored files are intentionally excluded. Force-adding bypasses .gitignore protection."
fi

# --no-verify bypasses pre-commit hooks (CLAUDE.md critical rule)
# argv-aware: recognises that `--no-verify` inside a quoted -m / -F message
# body is not a real flag to git.
if check_real_flag "--no-verify"; then
  deny "--no-verify blocked — bypasses pre-commit hooks. Fix the underlying hook failure instead. See CLAUDE.md critical rule #2."
fi

# --no-gpg-sign also bypasses signing policy
if check_real_flag "--no-gpg-sign"; then
  deny "--no-gpg-sign blocked — bypasses commit signing policy. See CLAUDE.md git-safety rules."
fi

# git commit -n short form of --no-verify (head-aware regex). `-n` is meaningful
# only when preceded by `git commit` (or git commit --amend, etc.). Cannot use
# is_true_flag since `-n` is common on many tools (cat -n, sed -n, head -n).
if echo "$CMD" | grep -qE 'git([[:space:]]+-[a-zA-Z]+[[:space:]]+[^[:space:]]+)*[[:space:]]+commit\b[^|&;]*[[:space:]]-n\b'; then
  deny "git commit -n blocked — short form of --no-verify, bypasses pre-commit hooks. See CLAUDE.md critical rule #2."
fi

# ── Warn (ask): destructive but sometimes intentional ────────────────

# git reset --hard — can destroy uncommitted work
if echo "$CMD" | grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'; then
  warn "git reset --hard can destroy uncommitted work. Verify intentional."
fi

# git clean -x / -X removes gitignored files (may include paid assets).
# Match any flag bundle containing x or X after `git clean -`.
if echo "$CMD" | grep -qE 'git[[:space:]]+clean[[:space:]]+-[a-zA-Z]*[xX]'; then
  warn "git clean -x/-X removes gitignored files which may include paid assets (AI-generated images, API outputs). Confirm intentional — safer alternative is git clean -fd (no -x)."
fi

# rm -rf on non-safe targets. Per-clause extraction avoids the compound-command
# escape hatch (e.g., `rm -rf src && rm -rf node_modules` used to silently pass
# because one clause matched a safe target).
SAFE_RM_TARGETS='(node_modules|\.next|dist|__pycache__|\.cache|build|\.turbo|coverage|test-results|out|\.vercel)'
RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
if [[ -n "$RM_OCCURRENCES" ]]; then
  while IFS= read -r occurrence; do
    target=$(echo "$occurrence" | sed -E 's/^rm[[:space:]]+-(r|rf|fr)[[:space:]]+//')
    # Strip leading `./` or `/` (but NOT a leading `.` — `.next` must match `\.next`)
    # Two separate subs to avoid `|` collision with sed's delimiter.
    target_stripped=$(echo "$target" | sed -E 's|^\./||; s|^/||')
    if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
      warn "rm -rf on non-build-artifact target: '$target'. Verify intentional."
      break
    fi
  done <<<"$RM_OCCURRENCES"
fi

# ── Layer-3 concurrency guard for irreversible git ops (#9) ──────────
# Deny git push|commit|merge|rebase from the reso PRIMARY worktree when another
# LIVE writer holds the repo writer-lock — defense-in-depth with
# concurrent-writer-guard.sh (#3); a push here is a production deploy. No-op in
# a linked worktree or outside the reso primary. Honors CLAUDE_ISOLATION_SKIP=1.
if [[ "${CLAUDE_ISOLATION_SKIP:-0}" != "1" ]] \
   && echo "$CMD" | grep -qE 'git([[:space:]]+-[^[:space:]]+)*[[:space:]]+(push|merge|rebase|commit)\b'; then
  _vb_top=$(git rev-parse --show-toplevel 2>/dev/null || echo '')
  if [[ "$(basename "${_vb_top:-/}")" == "${RESO_GUARD_REPO_NAME:-reso-management-app}" && -d "${_vb_top}/.git" ]]; then
    _vb_lock="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/reso-writer.lock"
    _vb_sid=$(echo "$INPUT" | jq -r '.session_id // "unknown"' 2>/dev/null || echo unknown)
    if command -v python3 >/dev/null 2>&1 && [[ -f "$_vb_lock" ]]; then
      case "$(python3 "$HOME/.claude/hooks/reso-writer-lock.py" check "$_vb_lock" "$_vb_sid" 2>/dev/null || echo error)" in
        other*) deny "git push/commit/merge/rebase blocked — another live writer holds this repo's writer-lock and this is the primary worktree (push = production deploy). Isolate via scripts/new-worktree.sh, or wait for the other session. Override: CLAUDE_ISOLATION_SKIP=1." ;;
      esac
    fi
  fi
fi

# Log command for audit
mkdir -p ~/.claude/logs
echo "$CMD" >> ~/.claude/logs/bash-commands.log
exit 0
