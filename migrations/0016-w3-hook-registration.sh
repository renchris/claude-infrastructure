#!/bin/bash
# migration-class: c10
# migration-step: register the three READY W3 hook handlers — StopFailure, PostToolBatch and InstructionsLoaded(session_start) — in every fleet settings.json, so five landed, live-exec handlers stop being unreachable code; it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0016-w3-hook-registration.sh
# migration-subject: ~/.claude/hooks/stop-failure-marker.sh
# migration-verify: jq -e '[.hooks.StopFailure[]?.hooks[]?.command] as $s | [.hooks.PostToolBatch[]?.hooks[]?.command] as $b | [.hooks.InstructionsLoaded[]?.hooks[]?.command] as $i | ($s | any(. == "~/.claude/hooks/stop-failure-marker.sh")) and ($b | any(. == "~/.claude/hooks/post-tool-batch.sh")) and ($i | any(. == "~/.claude/hooks/instructions-loaded.sh"))' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0016 — the registration half of three of W3's five landed handlers (docs/plans/HOOK_SURFACE_100P.md
# § 2 "What W3 should wire", items 1, 4 and 5).
#
# WHAT IT FIXES. All five W3 handlers are on origin/main AND live-exec in ~/.claude/hooks — the
# core.bare repair landed and deploy-live converged on 2026-09-07, so § 2's "on trunk, not live"
# caveat is discharged. What has NOT changed is that NOTHING from W3 is registered anywhere:
# re-measured 2026-09-07, ~/.claude/settings.json carries exactly 90 registrations across 13 event
# keys, and StopFailure, PostToolBatch, InstructionsLoaded, FileChanged and CwdChanged are absent
# from all five config dirs. A built, deployed, executable, never-registered hook is unreachable
# code that reads as shipped — the exact inertness face migrations/README.md exists to close.
#
# WHY THREE AND NOT FIVE, and why this is a SPLIT rather than the single migration § 2 line 75
# anticipated:
#   · SubagentStop is ALREADY covered by 0014, staged and unrun. Re-registering it here would put
#     two migrations on one key, and 0014's own append is idempotent only against ITS command
#     string — a duplicate row would be created, not detected. Out of scope by construction.
#   · FileChanged + CwdChanged are ONE wiring (§ 3e) whose third mandatory part had no working
#     implementation until this wave: hooks/file-changed.sh guarded on `file_path` ABOVE its
#     watchPaths emit, so a CwdChanged payload (which carries no file_path) emitted EMPTY stdout
#     and could not re-arm. Measured both arms 2026-09-07 with CC_FILECHANGED_WATCHLIST set. They
#     therefore wait for 0017, AFTER the handler fix — registering a re-arm hook that cannot re-arm
#     would read GREEN on this migration's own verifier while the watch list still emptied on the
#     first `cd`.
# So the split is not tidiness: it is the difference between a registration that works and one that
# verifies.
#
# THE THREE, AND WHY EACH MATCHER IS WHAT IT IS:
#   · StopFailure → matcher-less. It fires at the instant of death with `error` and
#     `last_assistant_message`; there is no sub-selector to make, and the handler writes a MARKER
#     keyed on the CAUSE (not the session) precisely because ~30 sessions die together on one cap.
#   · PostToolBatch → matcher-less. ⚠️ 220-ONLY and SILENTLY so: the event is absent from 2.1.114's
#     enum, and an unknown hook event name is accepted without error, warning or log line
#     (§ 5). So this row is a silent no-op on 114 rather than a breakage — which is why it can be
#     registered fleet-wide from one file instead of needing a per-binary config split.
#   · InstructionsLoaded → matcher `session_start`, and this one is NOT a tool name. The binary's
#     own metadata gives matcherMetadata:{fieldToMatch:"load_reason", values:[session_start,
#     nested_traversal, path_glob_match, include, compact]} (hooks/instructions-loaded.sh:22-27
#     quotes it). The matcher SELECTS WHICH LOADS ARE OBSERVED, so a wrong value does not fail
#     loudly — it points the log at a different population. `session_start` answers the question
#     the event was adopted for and is BOUNDED at 2-4 rows/session (all 16 measured rows carry it).
#     `path_glob_match` is the one to avoid: it fires per file Claude touches and is unbounded
#     within a session.
#
# WHY THE LITERAL TILDE. The command strings below are stored INTO settings.json as
# `~/.claude/hooks/...`, unexpanded. CC expands them at hook-RUN time to $HOME/.claude/hooks/
# regardless of which config dir the settings.json lives in — so every config dir runs the primary
# copy, and the .claude-next hooks fork (backlog 11da376d60e3) is irrelevant here, exactly as 0014
# established. Expanding here would hard-code this machine's $HOME into a config mirrored five ways.
#
# WHY c10. It edits settings.json. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." Staged, never self-run.
set -uo pipefail

# The tilde is DELIBERATELY literal — see the header. It is data written into a config file, not a
# path this script ever opens. A `disable` binds to the NEXT construct only (memory
# lint-directive-binds-to-the-next-construct), so each assignment carries its own; one directive
# above the block silently covered STOPFAIL_CMD alone and the gate went red on the other two.
# shellcheck disable=SC2088
STOPFAIL_CMD='~/.claude/hooks/stop-failure-marker.sh'
# shellcheck disable=SC2088
BATCH_CMD='~/.claude/hooks/post-tool-batch.sh'
# shellcheck disable=SC2088
INSTR_CMD='~/.claude/hooks/instructions-loaded.sh'

CLAUDE_HOOKS="$HOME/.claude/hooks"

command -v jq >/dev/null 2>&1 || { printf '0016: jq required\n' >&2; exit 1; }

rc=0

# ── preconditions, re-derived at CONSUMPTION rather than trusted from this header ────────────────
# A migration's premise can rot between staging and the converge that reads it (MEMORY.md
# discovery-critic-premise-goes-stale). If a handler is not executable on the LIVE layer, the
# registration names a path that does not run — a registered no-op, and a registered no-op reads
# GREEN on every verifier that only asks whether the string is present.
for h in stop-failure-marker.sh post-tool-batch.sh instructions-loaded.sh; do
  if [ ! -x "$CLAUDE_HOOKS/$h" ]; then
    printf '0016: NOT registered — %s/%s is missing or not executable.\n' "$CLAUDE_HOOKS" "$h" >&2
    printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
    exit 1
  fi
done

# ── register one command into one event key of one settings file ────────────────────────────────
# `//= []` then append, so a sibling registration written by a later migration or by hand is never
# clobbered. MATCHER is the empty string for a matcher-less group; a non-empty value is written as
# a real `matcher` field, which is how InstructionsLoaded selects its load_reason.
register() { # <settings-file> <event> <command> <timeout> <matcher-or-empty>
  local f="$1" ev="$2" cmd="$3" to="$4" matcher="$5"

  if jq -e --arg c "$cmd" --arg e "$ev" \
       '[.hooks[$e][]?.hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0016: %s [%s] — already registered\n' "$f" "$ev"
    return 0
  fi

  local bak tmp
  bak="$f.bak-0016-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0016: %s — backup FAILED, not touching it\n' "$f" >&2; return 1; }

  tmp="$f.tmp-0016-$$"
  # The group is built once and appended whole; when a group already exists for this event the
  # command joins the FIRST group's hooks array. Two shapes, one for each matcher case, because a
  # matcher-less group must not carry an empty `matcher` key the dispatcher would test against.
  if jq --arg c "$cmd" --arg e "$ev" --arg m "$matcher" --argjson t "$to" \
       '($m | length > 0) as $has |
        (if $has then {"matcher":$m,"hooks":[{"type":"command","command":$c,"timeout":$t}]}
                 else {"hooks":[{"type":"command","command":$c,"timeout":$t}]} end) as $grp |
        .hooks //= {} |
        .hooks[$e] //= [] |
        if (.hooks[$e] | length) == 0
        then .hooks[$e] = [$grp]
        else .hooks[$e] += [$grp]
        end' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify the edit BY CONTENT before it replaces the live file — a malformed or subtly-wrong
    # settings.json silently kills every one of the 90 registrations already in it.
    if jq -e --arg c "$cmd" --arg e "$ev" \
         '[.hooks[$e][]?.hooks[]?.command] | any(. == $c)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0016: %s [%s] — registered (backup: %s)\n' "$f" "$ev" "$bak"
    else
      rm -f "$tmp"; printf '0016: %s [%s] — edit did not contain the hook; left unchanged\n' "$f" "$ev" >&2; return 1
    fi
  else
    rm -f "$tmp"; printf '0016: %s [%s] — jq edit FAILED; left unchanged\n' "$f" "$ev" >&2; return 1
  fi
  return 0
}

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # The fleet-config discriminator is the Stop array, borrowed from a DIFFERENT event for the
  # reason 0014 records: none of the three events below exists in ANY config yet, so testing for
  # one of them would skip all five dirs and still exit 0 — a migration that always succeeds by
  # doing nothing.
  if ! jq -e '.hooks.Stop | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0016: %s — no Stop array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  # 10s: it runs on the DEATH path and resolves the account through the accounts SSOT, so it does
  # real work under the one condition where the host is already failing.
  register "$f" StopFailure        "$STOPFAIL_CMD" 10 ""             || rc=1
  # 5s: one invocation per BATCH, but still a hot path — two forks in the steady state.
  register "$f" PostToolBatch      "$BATCH_CMD"     5 ""             || rc=1
  # 5s: bounded at 2-4 rows/session. `session_start` — the load_reason, not a tool name.
  register "$f" InstructionsLoaded "$INSTR_CMD"     5 "session_start" || rc=1
done

exit "$rc"
