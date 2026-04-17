#!/bin/bash
# PreToolUse hook for Bash command validation
# Complements settings.json deny/ask permissions with pattern-matching
# that permission prefixes can't catch (DDL inside commands, etc.)
# Exit 0 with JSON to stdout for decisions, exit 2 for blocking errors

INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

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

# ── Hard deny: catastrophic or rule-violating patterns ────────────────

# Original blocks (system damage)
if echo "$CMD" | grep -qE '(rm -rf /[^a-zA-Z]|sudo rm|:(){ :|:& };:)'; then
  deny "Dangerous command pattern blocked: potential system damage"
fi

# DDL via any mechanism (turso shell, sqlite3, echo|pipe, etc.)
# Case-insensitive. turso db shell is in the allow list but DDL within it must be blocked.
if echo "$CMD" | grep -qiE '\b(DROP\s+TABLE|DROP\s+DATABASE|DROP\s+INDEX|ALTER\s+TABLE|CREATE\s+TABLE|TRUNCATE)\b'; then
  deny "DDL blocked — all schema changes must go through Drizzle migrations (pnpm generate). See CLAUDE.md critical rule #1."
fi

# drizzle-kit push bypasses migration history
if echo "$CMD" | grep -qE 'drizzle-kit\s+push'; then
  deny "drizzle-kit push bypasses migration history and causes schema drift. Use pnpm generate instead."
fi

# git add -f on directories (force-adds gitignored content, bloats history)
if echo "$CMD" | grep -qE 'git\s+add\s+(-f|--force)\b'; then
  deny "git add --force blocked — gitignored files are intentionally excluded. Force-adding bypasses .gitignore protection."
fi

# --no-verify bypasses pre-commit hooks (CLAUDE.md critical rule)
# Matches --no-verify as a standalone argument (not substring like --no-verify-ssl).
if echo "$CMD" | grep -qE '(^|[[:space:]])--no-verify([[:space:]]|$)'; then
  deny "--no-verify blocked — bypasses pre-commit hooks. Fix the underlying hook failure instead. See CLAUDE.md critical rule #2."
fi

# ── Warn (ask): destructive but sometimes intentional ────────────────

# rm -rf on non-safe targets. Per-clause extraction avoids the compound-command
# escape hatch (e.g., `rm -rf src && rm -rf node_modules` used to silently pass
# because one clause matched a safe target).
SAFE_RM_TARGETS='(node_modules|\.next|dist|__pycache__|\.cache|build|\.turbo|coverage|test-results|out|\.vercel)'
RM_OCCURRENCES=$(echo "$CMD" | grep -oE 'rm[[:space:]]+-(r|rf|fr)[[:space:]]+[^[:space:];&|]+' || true)
if [[ -n "$RM_OCCURRENCES" ]]; then
  while IFS= read -r occurrence; do
    target=$(echo "$occurrence" | sed -E 's/^rm[[:space:]]+-(r|rf|fr)[[:space:]]+//')
    target_stripped=$(echo "$target" | sed -E 's|^\.?/?||')
    if ! echo "$target_stripped" | grep -qE "^${SAFE_RM_TARGETS}(/|$)"; then
      warn "rm -rf on non-build-artifact target: '$target'. Verify intentional."
      break
    fi
  done <<<"$RM_OCCURRENCES"
fi

# Log command for audit
mkdir -p ~/.claude/logs
echo "$CMD" >> ~/.claude/logs/bash-commands.log
exit 0
