#!/bin/bash
# migration-class: c10
# migration-step: register the 11 hooks that are wired in some fleet config dirs and missing in others — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0021-fleet-hook-parity.sh
# migration-subject: ~/.claude/settings.json
# migration-verify: bash ~/Development/claude-infrastructure/migrations/0021-fleet-hook-parity.sh --verify
#
# 0021 — WHAT A SESSION MAY DO DEPENDED ON WHICH ACCOUNT FIRED IT.
#
# The fleet picks a config dir by account at fire time (~/.claude · .claude-next · .claude-secondary
# · .claude-tertiary · .claude-quaternary). Eleven hooks were wired in some of those and not others,
# so the same prompt ran a different guard set depending on which account happened to be routed to.
# Measured 2026-09-08 by `scripts/settings-drift-assert.sh --assert`, which exited 1 with:
#
#   DRIFT [hooks] "PostToolUseFailure|cc-permission-beacon.sh clear" — missing in: next secondary tertiary quaternary
#   DRIFT [hooks] "PostToolUseFailure|log-bash.sh"                   — missing in: next secondary tertiary quaternary
#   DRIFT [hooks] "PostToolUseFailure|mailbox-drain.sh post-tool"    — missing in: next secondary tertiary quaternary
#   DRIFT [hooks] "PreToolUse|cc-unattended-ask-guard.sh"            — missing in: next
#   DRIFT [hooks] "PreToolUse|coldcompile-admit.sh"                  — missing in: next
#   DRIFT [hooks] "PreToolUse|pr-gate.sh"                            — missing in: next secondary tertiary quaternary
#   DRIFT [hooks] "PreToolUse|web-entrypoint-ladder.sh"              — missing in: next secondary quaternary
#   DRIFT [hooks] "SessionEnd|session-deregister.sh"                 — missing in: next
#   DRIFT [hooks] "SessionStart|desk-brief-inject.sh"                — missing in: next
#   DRIFT [hooks] "SessionStart|escalation-watch.sh"                 — missing in: next secondary tertiary quaternary
#   DRIFT [hooks] "UserPromptSubmit|handed-off-session-guard.sh"     — missing in: next
#
# THE SSOT IS ~/.claude, AND THAT IS A CHOICE, NOT A DEFAULT. Every one of the eleven is present in
# ~/.claude and absent somewhere else — the divergence is one-directional, so the primary config is
# the only reading under which no dir loses a hook. Each entry below carries the event, matcher and
# timeout COPIED from that file (read 2026-09-08), not re-derived: three of them deliberately carry
# no timeout because the primary carries none, and inventing one here would make this migration a
# second source of truth that cannot learn the primary changed.
#
# WHY c10. It edits settings.json — staged, never self-run (migrations/README.md). Running it is the
# operator's paste; backlog 02e67ee88123 is blocked on exactly that command.
#
# THE DETECTOR IS THE CLOSE CONDITION. `scripts/settings-drift-assert.sh --assert` exits 0 when the
# dirs agree, so this migration's effect is falsifiable by a command that existed before it.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '0021: jq required\n' >&2; exit 1; }

# event · matcher ('' = matcher-less) · command (tilde DELIBERATELY literal — CC expands it at
# hook-run time; expanding here would hard-code this machine's $HOME into five mirrored configs)
# · timeout ('' = omit the key, mirroring the primary) · the hook file this row needs on disk
# shellcheck disable=SC2088
declare -a ROWS=(
  'PostToolUseFailure|||~/.claude/hooks/cc-permission-beacon.sh clear||cc-permission-beacon.sh'
  'PostToolUseFailure|Bash||~/.claude/hooks/log-bash.sh|5|log-bash.sh'
  'PostToolUseFailure|||~/.claude/hooks/mailbox-drain.sh post-tool||mailbox-drain.sh'
  'PreToolUse|AskUserQuestion||~/.claude/hooks/cc-unattended-ask-guard.sh|5|cc-unattended-ask-guard.sh'
  'PreToolUse|Bash||~/.claude/hooks/coldcompile-admit.sh|10|coldcompile-admit.sh'
  'PreToolUse|Bash||~/.claude/hooks/pr-gate.sh||pr-gate.sh'
  'PreToolUse|WebFetch|WebSearch|~/.claude/hooks/web-entrypoint-ladder.sh||web-entrypoint-ladder.sh'
  'SessionEnd|||~/.claude/hooks/session-deregister.sh|5|session-deregister.sh'
  'SessionStart|||~/.claude/hooks/desk-brief-inject.sh|5|desk-brief-inject.sh'
  'SessionStart|||~/.claude/hooks/escalation-watch.sh|10|escalation-watch.sh'
  'UserPromptSubmit|||~/.claude/hooks/handed-off-session-guard.sh||handed-off-session-guard.sh'
)
# FIELD 2 AND 3 ARE ONE MATCHER, SPLIT ON PURPOSE. `WebFetch|WebSearch` is a single CC matcher that
# CONTAINS the delimiter, so it is stored as two fields and rejoined with '|' below. Storing it as
# one field would have silently truncated it to `WebFetch` — a narrower guard that still reads as
# registered.
_row() { # <row> → sets EV MT CMD TMO FILE
  local IFS='|'; read -r EV M1 M2 CMD TMO FILE <<<"$1"
  if [ -n "$M2" ]; then MT="$M1|$M2"; else MT="$M1"; fi
}

verify_one() { # → 0 iff every row is registered in this config dir
  local f="${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" row miss=0
  [ -f "$f" ] || { printf '0021 --verify: %s absent\n' "$f" >&2; return 1; }
  local have
  have="$(jq -r '.hooks // {} | to_entries[] | .key as $e | (.value // [])[]? | (.hooks // [])[]? | "\($e)|\(.command)"' "$f" 2>/dev/null)" || return 1
  for row in "${ROWS[@]}"; do
    _row "$row"
    if ! grep -qxF -- "$EV|$CMD" <<<"$have"; then
      printf '0021 --verify: %s — NOT registered: %s|%s\n' "$f" "$EV" "$CMD" >&2; miss=1
    fi
  done
  [ "$miss" -eq 0 ]
}

if [ "${1:-}" = "--verify" ]; then verify_one; exit $?; fi

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# A registration naming a path that does not run is a registered no-op, and it reads GREEN
# (MEMORY.md registration-precondition-must-assert-version-not-executability).
for row in "${ROWS[@]}"; do
  _row "$row"
  if [ ! -x "$HOME/.claude/hooks/$FILE" ]; then
    printf '0021: NOT registered — %s/.claude/hooks/%s is missing or not executable.\n' "$HOME" "$FILE" >&2
    printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
    exit 1
  fi
done

rc=0
for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Fleet discriminator borrowed from an event every fleet config already runs — testing for one of
  # OUR eleven would be false in the lagging dirs, which are exactly the ones that need the edit.
  if ! jq -e '.hooks.Stop | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0021: %s — no Stop array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  bak=""
  for row in "${ROWS[@]}"; do
    _row "$row"

    if jq -e --arg e "$EV" --arg c "$CMD" \
         '[.hooks[$e][]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
      printf '0021: %s — %s|%s already registered\n' "$f" "$EV" "$CMD"
      continue
    fi

    # ONE backup per file, taken before this file's first real edit.
    if [ -z "$bak" ]; then
      bak="$f.bak-0021-$(date +%Y%m%d%H%M%S)"
      cp -p "$f" "$bak" || { printf '0021: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; break; }
    fi

    tmp="$f.tmp-0021-$$"
    # `.hooks[$e] //= []` then APPEND: creates the array when absent and appends when a sibling is
    # already there, so this can never clobber a consumer it did not write.
    # shellcheck disable=SC2016  # $e/$c/$m/$t are JQ variables bound by --arg/--argjson below.
    if [ -n "$MT" ] && [ -n "$TMO" ]; then
      jq_expr='.hooks[$e] //= [] | .hooks[$e] += [{"matcher":$m,"hooks":[{"type":"command","command":$c,"timeout":$t}]}]'
    elif [ -n "$MT" ]; then
      jq_expr='.hooks[$e] //= [] | .hooks[$e] += [{"matcher":$m,"hooks":[{"type":"command","command":$c}]}]'
    elif [ -n "$TMO" ]; then
      jq_expr='.hooks[$e] //= [] | .hooks[$e] += [{"hooks":[{"type":"command","command":$c,"timeout":$t}]}]'
    else
      jq_expr='.hooks[$e] //= [] | .hooks[$e] += [{"hooks":[{"type":"command","command":$c}]}]'
    fi

    if jq --arg e "$EV" --arg c "$CMD" --arg m "$MT" --argjson t "${TMO:-0}" "$jq_expr" \
         "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
      # Verify BY CONTENT before it replaces the live file, and re-assert that the OTHER hook arrays
      # survived — the failure this whole plan is about is a settings file that silently stops
      # running everything it holds.
      if jq -e --arg e "$EV" --arg c "$CMD" \
           '([.hooks[$e][]?.hooks[]?.command] | any(. == $c))
            and (.hooks.Stop | type == "array" and length > 0)
            and (.hooks.PreToolUse | type == "array" and length > 0)' "$tmp" >/dev/null 2>&1; then
        mv "$tmp" "$f" && printf '0021: %s — %s registered%s\n' "$f" "$EV" \
          "$( [ -n "$MT" ] && printf ' (matcher %s)' "$MT" )"
      else
        rm -f "$tmp"; printf '0021: %s — %s edit failed its content check; left unchanged\n' "$f" "$EV" >&2; rc=1
      fi
    else
      rm -f "$tmp"; printf '0021: %s — %s jq edit FAILED; left unchanged\n' "$f" "$EV" >&2; rc=1
    fi
  done
  [ -n "$bak" ] && printf '0021: %s — backup: %s\n' "$f" "$bak"
done

exit "$rc"
