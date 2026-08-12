#!/bin/bash
# smart-bash-allowlist.sh — PreToolUse hook that conditionally auto-allows
# common safe commands, reducing permission prompt fatigue.
#
# Safety invariant: re-runs the DANGER_PATTERNS from validate-bash.sh and
# refuses to emit "allow" if any match. Kill switch: SMART_ALLOWLIST_DISABLED=1.
#
# Runs BEFORE validate-bash.sh in the hooks array. If this hook emits "allow",
# validate-bash.sh still runs (hooks chain independently in Claude Code's
# model — first non-empty decision wins; but deny always overrides).
#
# Auto-allows:
#   1. git commit        — unless --no-verify/--amend-published
#   3. sed -i <file>     — target under CWD, not in DENY_DIR/DENY_SENSITIVE
#   5. chmod <safe-mode> — 644/755/600/700/750/640/+x/u+x only, under CWD
#   6. sed -n <script>   — read-only paging (positive whitelist; see rule 6)
#
# RULE NUMBERS 2 AND 4 ARE RETIRED, NOT RENUMBERED — the gap is deliberate, so that a reader
# comparing this file against the decision packet or the tests can see that two rules were
# REMOVED rather than that the list was always this short.
#
# WHY THEY WERE REMOVED (2026-08-12). Both auto-approved a command the operator had independently
# placed behind an `ask` rule in ~/.claude/settings.json (`Bash(git push:*)`, and deletion via the
# global rm guard). A PreToolUse hook emitting "allow" BYPASSES the permission system, so wiring
# this hook would have silently revoked those gates as a side effect of a prompt-reduction change
# — the operator would keep the rule and lose the guard, with nothing in either file recording it.
#
# Rule 4 was also DEAD, and mis-specified underneath the deadness — measured, not read:
#   • Its extraction regex `[[:alnum:]_.\-/]+` is an INVALID CHARACTER RANGE. /usr/bin/grep exits 2
#     with "invalid character range", so GIT_PUSH_MATCH was always empty and rule 4 never allowed
#     any push at all, on any branch, for its whole life.
#   • Underneath that, its reject list was `^(develop|production|prod|release.*)$` — `main` and
#     `master` ABSENT. So repairing the bracket expression, which any reader would call a typo fix,
#     would have SILENTLY ARMED `git push origin main` against a standing never-push-to-main rule.
# A latent defect sitting behind a broken matcher is the worst arrangement of the two: there is no
# symptom to motivate the repair, and the repair is what makes it dangerous.
#
# (Recorded because the first pass of this analysis got it wrong in the operator-facing direction:
# it reported that `git push origin main` WOULD be auto-allowed. The missing main|master was real;
# the consequence attached to it was not, because the rule could not fire. The control in
# tests/smart-bash-allowlist-narrow.bats is what caught it — a true fact next to a wrong
# consequence reads exactly like a diagnosis.)
#
# Neither rule carried the prompt volume that justified them: the measured blockers in the beacon
# archive (1,124 prompts, 2026-07-31 →) are compound commands, and rules 1/3/5/6 cover those.

# Kill switch
[[ "${SMART_ALLOWLIST_DISABLED:-0}" == "1" ]] && exit 0

set -uo pipefail

INPUT=$(cat)

# Fail-open on malformed input (let validate-bash.sh handle it)
if ! CMD=$(echo "$INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null); then
  exit 0
fi

[[ -z "$CMD" ]] && exit 0

# ═══ Safety invariant: re-run DANGER_PATTERNS ═══════════════════════════
# If ANY danger pattern matches, exit 0 without deciding (defer to validate-bash.sh)

# rm -rf / (system damage), sudo rm, fork bomb
if echo "$CMD" | grep -qE '(rm -rf /[^a-zA-Z]|sudo rm|:(){ :|:& };:)'; then exit 0; fi

# DDL
if echo "$CMD" | grep -qiE '\b(DROP\s+TABLE|DROP\s+DATABASE|DROP\s+INDEX|ALTER\s+TABLE|CREATE\s+TABLE|TRUNCATE)\b'; then exit 0; fi

# drizzle-kit push
if echo "$CMD" | grep -qE 'drizzle-kit\s+push'; then exit 0; fi

# git add -f (force-adds gitignored)
if echo "$CMD" | grep -qE 'git\s+add\s+(-f|--force)\b'; then exit 0; fi

# --no-verify
if echo "$CMD" | grep -qE '(^|[[:space:]])--no-verify([[:space:]]|$)'; then exit 0; fi

# turso db shell / destroy
if echo "$CMD" | grep -qE 'turso\s+db\s+(shell|destroy)\b'; then exit 0; fi

# chmod 777
if echo "$CMD" | grep -qE 'chmod\s+(-R\s+)?777\b'; then exit 0; fi

# git clean -x / -X (deletes gitignored paid assets per CLAUDE.md)
if echo "$CMD" | grep -qE 'git\s+clean\s+[^|;]*-[xX]\b'; then exit 0; fi

allow() {
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "$1"
  }
}
EOF
  exit 0
}

# ═══ Auto-allow conditions ══════════════════════════════════════════════

# 1. git commit (no --no-verify already filtered above; no --amend on published)
#    Matches: git commit, git commit -m "...", git commit -am "...", git commit $(...)
if echo "$CMD" | grep -qE '^[[:space:]]*git\s+commit(\s|$)'; then
  # --amend is allowed (local commit rewrite); guard against amending pushed commits is out-of-scope for a hook
  allow "git commit: safe (no --no-verify, local operation)"
fi

# 2. RETIRED — see the header. Deletion stays behind the operator's own gate.

# path_escapes_project <path> — rc 0 when the path must NOT be auto-allowed.
# Replaces an ERE negative lookahead `^/(?!Users/chrisren/Development…)`, which POSIX ERE does not
# support: /usr/bin/grep exits 2 with "repetition-operator operand invalid" on it, and because the
# call site was `if grep -qE …; then exit 0; fi`, rc 2 is not 0, so the branch never fired. The
# guard was therefore INERT and fail-OPEN — every absolute path passed it — while also printing a
# grep error to stderr on each invocation. Verified 2026-08-12 under bash + /usr/bin/grep; note it
# behaves differently again under ugrep, so re-measure with the interpreter the hook actually runs.
path_escapes_project() {
  local p="$1"
  case "$p" in
    *..*|*'*'*|*'?'*) return 0 ;;          # traversal or glob — never auto-allow
    /*) [ "${p#"$PWD"/}" = "$p" ] && return 0 || return 1 ;;   # absolute: must be under $PWD
    *)  return 1 ;;                         # relative — already CWD-anchored
  esac
}

# 3. sed -i targeting files under CWD, not in DENY_DIR/DENY_SENSITIVE
# DENY regexes lifted from uidotsh-allowlist.sh
DENY_DIR='(^|/)lib/error-logger|(^|/)lib/rate-limit|(^|/)src/app/actions|(^|/)src/app/api|(^|/)middleware\.|(^|/)next\.config|(^|/)drizzle/|(^|/)\.env($|\.)|(^|/)package\.json$|(^|/)pnpm-lock|(^|/)tsconfig\.json$|(^|/)\.npmrc$|(^|/)\.nvmrc$|(^|/)\.mcp\.json$|(^|/)infrastructure/|(^|/)\.github/workflows/|(^|/)pre-build/|(^|/)\.claude/(hooks/|agents/|settings\.json$|settings\.local\.json$)'
DENY_SENSITIVE='(^|/)(auth|session|cookie|token|secret)(\.config)?\.(ts|tsx|js|jsx|json)$|(^|/)(auth|session|cookie|token|secret)-(handler|helpers?|service|utils?|middleware|manager|provider|guard)\.(ts|tsx|js|jsx)$|(^|/)(auth|session|cookies?|tokens?|secrets?)/'

SED_MATCH=$(echo "$CMD" | grep -oE "^[[:space:]]*sed[[:space:]]+-i[[:space:]]*'?'?[[:space:]]+['\"]?[^'\"]+['\"]?[[:space:]]+[^[:space:]]+" || true)
if [[ -n "$SED_MATCH" ]]; then
  # Extract the file target (last non-whitespace token)
  SED_TARGET=$(echo "$CMD" | grep -oE '[^[:space:]]+$' | head -1)
  if [[ -n "$SED_TARGET" ]]; then
    # Reject absolute paths outside project, .. traversal, glob
    if path_escapes_project "$SED_TARGET"; then exit 0; fi
    # Reject DENY_DIR / DENY_SENSITIVE
    if echo "$SED_TARGET" | grep -qE "$DENY_DIR" || echo "$SED_TARGET" | grep -qE "$DENY_SENSITIVE"; then exit 0; fi
    allow "sed -i: target under CWD, not in protected paths"
  fi
fi

# 4. RETIRED — see the header. `Bash(git push:*)` is an operator `ask` rule; this hook must not
#    silently cancel it, and its protected-branch regex omitted main/master anyway.

# 5. chmod with safe modes, target under CWD
CHMOD_MATCH=$(echo "$CMD" | grep -oE '^[[:space:]]*chmod[[:space:]]+(644|755|600|700|750|640|\+x|u\+x)[[:space:]]+[^;&|]+$' || true)
if [[ -n "$CHMOD_MATCH" ]]; then
  CHMOD_TARGET=$(echo "$CHMOD_MATCH" | awk '{print $NF}')
  # Reject absolute paths outside project, .. traversal, glob
  if path_escapes_project "$CHMOD_TARGET"; then exit 0; fi
  allow "chmod: safe mode, target under CWD"
fi

# 6. sed -n — READ-ONLY paging. Measured 2026-07-31 (bin/cc-permission-audit) as the single
#    largest allow-listable slice: 730 of the 1,014 simple-verb unmatched invocations (72%), out
#    of 41,829 Bash calls in the transcript corpus.
#    `-n` suppresses auto-print, so sed emits only what an explicit p/=/l prints — it cannot
#    write. The dangerous sibling is `-i` (in-place), which rule 3 handles with its own
#    DENY_DIR/DENY_SENSITIVE gauntlet; the anchored pattern here cannot match it, and the explicit
#    guard below refuses it belt-and-braces.
#    Same conservatism as every rule above: whole-command anchor plus [^;&|], so a compound like
#    `sed -n 1p f; rm -rf /` never reaches this branch — it falls through to the normal gate.
#    w/W (write-to-file) and e (execute) are sed COMMANDS that still have effects under -n, so any
#    script containing one is refused.
#    The script is validated by POSITIVE WHITELIST, not by blacklisting effectful commands. A
#    blacklist here enumerates spellings rather than the class — the first draft listed w/W/e and
#    still let `sed -n 'w /tmp/out' f` through, because the guard assumed a character preceded the
#    command letter. Only the address+print forms actually observed in the corpus are admitted;
#    everything else falls through to the normal permission gate.
SED_N_MATCH=$(echo "$CMD" | grep -oE "^[[:space:]]*sed[[:space:]]+-n[[:space:]]+[^;&|]+$" || true)
if [[ -n "$SED_N_MATCH" ]]; then
  # the script is the first argument after -n; strip one layer of surrounding quotes
  SED_SCRIPT=$(echo "$SED_N_MATCH" | awk '{print $3}' | sed -e "s/^'//" -e "s/'$//" -e 's/^"//' -e 's/"$//')
  # WHITELIST: numeric line/range print, or /regex/ (range) print. p/=/l only; no other command.
  if echo "$SED_SCRIPT" | grep -qE '^[0-9]+(,[0-9]+|,\$)?[p=l]$'                 \
  || echo "$SED_SCRIPT" | grep -qE '^\$[p=l]$'                                    \
  || echo "$SED_SCRIPT" | grep -qE '^/[^/]*/(,/[^/]*/)?[p=l]$'                    \
  || echo "$SED_SCRIPT" | grep -qE '^[0-9]+,/[^/]*/[p=l]$'; then
    allow "sed -n: read-only paging (whitelisted address+print script, single command)"
  fi
fi

# No match — defer to downstream hooks
exit 0
