#!/bin/bash
# migration-class: c10
# migration-step: add mcp__ms365__graph-batch to the ms365 PreToolUse matcher in every fleet config dir — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0028-ms365-graph-batch-matcher.sh
# migration-subject: ~/.claude/hooks/enforce-email-formatting.py
# migration-verify: bash ~/Development/claude-infrastructure/migrations/0028-ms365-graph-batch-matcher.sh --verify
# migration-conflict: bash ~/Development/claude-infrastructure/migrations/0028-ms365-graph-batch-matcher.sh --conflict
#
# 0028 — R1 CALLS ITSELF ABSOLUTE, AND ONE UNMATCHED TOOL NAME MADE IT OPTIONAL.
#
# hooks/enforce-email-formatting.py R1 denies the four ms365 tools that compose and transmit in one
# call, in terms that admit no override: a Graph send cannot be recalled. The Softeria
# ms-365-mcp-server (v0.143.0) also exposes `graph-batch` — POST /$batch, up to 20 RAW Graph
# requests forwarded in ONE tool call. A batched {"method":"POST","url":"/me/sendMail"} reaches the
# same irreversible send, and so do /me/messages/{id}/send, createReply and createForward.
#
# Measured 2026-09-14 from a mac-bootstrap session: `grep -c mcp__ms365__graph-batch` was **0** in
# all of ~/.claude, ~/.claude-next, ~/.claude-tertiary and ~/.claude-quaternary. The tool name was
# in no matcher, so the guard was never invoked, so R1 held only against a model that used the
# NAMED tools. The hook-side rule (R1c, tests/ms365-graph-batch-guard.bats) lands in the same diff
# as this file — and a rule the chain never invokes is a rule that does not exist, which is the
# whole reason a registration belongs in migrations/ rather than in a folder someone visits.
#
# THIS IS ADDITIVE AND STRICTLY NARROWING. It appends one alternation branch to an existing
# matcher; it removes nothing, re-points nothing, and touches no other entry. The tool it newly
# routes was previously ungated.
#
# 🚨 WHY c10 AND NOT mechanical. It edits settings.json — the C10 class, staged and never run by the
# converger. Blast radius is small by comparison with 0024 (one MCP tool, on one server, whose only
# new outcome is a refusal of non-GET batches), but the class is decided by the FILE it writes, not
# by how modest the edit is.
#
# WHY THE PRECONDITION RE-DERIVES THE EFFECT INSTEAD OF TESTING FOR A FILE. A matcher pointing at a
# hook that lacks R1c is a registered NO-OP that reads GREEN in every state report
# (MEMORY: registration-precondition-must-assert-version-not-executability). The live layer is a
# per-file symlink farm that routinely runs OLDER bytes than trunk (MEMORY: a landed EDIT rides its
# symlink), so "the file exists and is executable" is exactly the assertion that cannot tell a
# converged hook from a stale one. This refuses to register until the LIVE hook actually denies a
# batched send — the same predicate --verify uses, for the same reason.
set -uo pipefail

command -v jq >/dev/null 2>&1 || { printf '0028: jq required\n' >&2; exit 1; }

# The command string as it appears in settings.json — tilde LITERAL, expanded by CC at hook-run
# time. GUARD_RE matches the entry by its script name rather than by the exact string, so a dir
# spelling the path differently is still found rather than silently given a second entry.
GUARD_RE='enforce-email-formatting\.py'
# The LIVE hook, resolved. Config-dir-INVARIANT on purpose (README "Mind the per-config-dir loop"):
# every dir's entry names ~/.claude/hooks/..., so there is exactly one hook to exercise, and
# re-deriving it per dir would manufacture a permanent `partial`.
LIVE_HOOK="$HOME/.claude/hooks/enforce-email-formatting.py"
TOOL='mcp__ms365__graph-batch'
CONFIG_DIRS=("$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary")

# The bypass itself, as the payload a PreToolUse hook would receive. This exact blob is the oracle
# for the precondition AND for --verify: the effect this migration exists to produce is "that call
# is refused", and nothing about the shape of settings.json can stand in for it.
batch_is_denied() {
  [ -f "$LIVE_HOOK" ] || return 1
  TOOL="$TOOL" HOOK="$LIVE_HOOK" python3 -c '
import json, os, subprocess, sys
pay = json.dumps({"session_id": "mig0028", "hook_event_name": "PreToolUse",
                  "tool_name": os.environ["TOOL"],
                  "tool_input": {"body": {"requests": [
                      {"id": "1", "method": "GET",  "url": "/me"},
                      {"id": "2", "method": "POST", "url": "/me/sendMail",
                       "body": {"message": {"subject": "migration 0028 probe"}}}]}}})
try:
    p = subprocess.run([sys.executable, os.environ["HOOK"]], input=pay,
                       capture_output=True, text=True, timeout=30)
except Exception:
    sys.exit(1)
out = (p.stdout or "").strip()
if not out:
    sys.exit(1)            # empty stdout is an ALLOW; the bypass is open.
try:
    d = json.loads(out)["hookSpecificOutput"]["permissionDecision"]
except Exception:
    sys.exit(1)
sys.exit(0 if d == "deny" else 1)
' 2>/dev/null
}

# has_guard_entry <settings.json> -> rc 0 iff this dir registers the email guard at all.
# Separate from matcher_has_tool so a red can say WHICH of the two states it is: "the guard is not
# registered here" is a defect this migration cannot cure (it appends to an entry, it does not
# invent one), while "registered but the matcher lacks the tool" is exactly what apply fixes. One
# opaque red covering both would send the operator to the wrong remedy.
has_guard_entry() {
  jq -e --arg re "$GUARD_RE" \
    '[(.hooks.PreToolUse // [])[] | select([.hooks[]?.command] | any(test($re)))] | length > 0' \
    "$1" >/dev/null 2>&1
}

# matcher_has_tool <settings.json> -> rc 0 iff the email-guard entry's matcher carries the tool.
matcher_has_tool() {
  jq -e --arg re "$GUARD_RE" --arg t "$TOOL" '
    [(.hooks.PreToolUse // [])[] | select([.hooks[]?.command] | any(test($re)))] as $e
    | ($e | length > 0)
      and ($e | all((.matcher // "") | split("|") | any(. == $t)))' "$1" >/dev/null 2>&1
}

# ── verify ──────────────────────────────────────────────────────────────────────────────────────
# TWO arms, and the second is the one that matters. The matcher arm is PAPERWORK — it proves a
# string reached a file. The effect arm runs the live hook against the real bypass payload and
# requires a deny, so a matcher registered over a hook that never converged reports NOT live
# instead of green (README: "Verify the EFFECT, not the paperwork").
#
# Scope of the matcher arm follows CC_CLAUDE_DIR, which is how registration-state.sh re-runs this
# once per config dir; run by hand with it unset, it checks ALL of them, so the operator's own
# `--verify` answers the fleet-wide question the step is written in terms of.
verify() {
  local ok=0 f
  if [ -n "${CC_CLAUDE_DIR:-}" ]; then
    f="$CC_CLAUDE_DIR/settings.json"
    if [ ! -f "$f" ]; then printf '0028 --verify: %s absent\n' "$f" >&2; return 1; fi
    if ! has_guard_entry "$f"; then
      printf '0028 --verify: %s — NO ms365 email-guard entry at all; %s cannot be routed here.\n' "$f" "$TOOL" >&2
      printf '      This migration appends to an existing entry and will not invent one — the\n' >&2
      printf '      missing registration is the defect to fix, and it is not 0028 that fixes it.\n' >&2
      ok=1
    elif ! matcher_has_tool "$f"; then
      printf '0028 --verify: %s — the ms365 guard matcher does not carry %s\n' "$f" "$TOOL" >&2
      ok=1
    fi
  else
    local seen=0
    for dir in "${CONFIG_DIRS[@]}"; do
      f="$dir/settings.json"
      [ -f "$f" ] || continue
      jq -e '.hooks.PreToolUse | type == "array" and length > 0' "$f" >/dev/null 2>&1 || continue
      if ! has_guard_entry "$f"; then
        printf '0028 --verify: %s — NO ms365 email-guard entry at all; %s cannot be routed here.\n' "$f" "$TOOL" >&2
        printf '      0028 appends to an existing entry and will not invent one.\n' >&2
        ok=1
        continue
      fi
      seen=$((seen + 1))
      if ! matcher_has_tool "$f"; then
        printf '0028 --verify: %s — the ms365 guard matcher does not carry %s\n' "$f" "$TOOL" >&2
        ok=1
      fi
    done
    # Zero dirs carrying the guard is NOT a pass. A verifier whose population can silently empty
    # reports success over nothing at all (MEMORY: aggregate-control-cannot-see-a-per-member-zero),
    # and "the email guard is registered nowhere" is the loudest possible version of not-live.
    if [ "$seen" -eq 0 ]; then
      printf '0028 --verify: no fleet settings.json registers the ms365 email guard — nothing was checked\n' >&2
      ok=1
    fi
  fi
  if ! batch_is_denied; then
    printf '0028 --verify: the LIVE hook %s does NOT deny a batched POST /me/sendMail — the\n' "$LIVE_HOOK" >&2
    printf '      matcher would route graph-batch to a guard that has no rule for it. Converge the\n' >&2
    printf '      live layer (bash ~/Development/claude-infrastructure/scripts/deploy-live.sh).\n' >&2
    ok=1
  fi
  return "$ok"
}

# ── conflict ────────────────────────────────────────────────────────────────────────────────────
# `overridden` = a DIFFERENT value at the same key. Declared because it is genuinely possible and
# would be invisible otherwise: another hook registering an entry that matches graph-batch means
# some other command now claims this tool, and whichever ordering CC applies, the operator's model
# of "the email guard owns ms365 writes" is no longer true.
conflict() {
  local f="${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json"
  [ -f "$f" ] || return 1
  jq -e --arg re "$GUARD_RE" --arg t "$TOOL" '
    [(.hooks.PreToolUse // [])[]
     | select((.matcher // "") | split("|") | any(. == $t))
     | select([.hooks[]?.command] | any(test($re)) | not)] | length > 0' "$f" >/dev/null 2>&1
}

case "${1:-}" in
  --verify)   verify;   exit $? ;;
  --conflict) conflict; exit $? ;;
esac

# ── precondition: the hook must already REFUSE the bypass, or this registers a no-op ─────────────
if [ ! -x "$LIVE_HOOK" ]; then
  printf '0028: NOT registered — %s is missing or not executable.\n' "$LIVE_HOOK" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it (or deploy-live) first.\n' >&2
  exit 1
fi
if ! batch_is_denied; then
  printf '0028: NOT registered — the live hook does not yet deny a batched POST /me/sendMail.\n' >&2
  printf '      Registering the matcher now would route graph-batch to a guard with no rule for it,\n' >&2
  printf '      which reads GREEN in every state report while the bypass stays open. Converge first:\n' >&2
  printf '      bash ~/Development/claude-infrastructure/scripts/deploy-live.sh\n' >&2
  exit 1
fi

rc=0
for dir in "${CONFIG_DIRS[@]}"; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Fleet discriminator borrowed from an array every fleet config already has (as 0024 does) —
  # testing for OUR entry would be false in exactly the dirs that need the edit.
  if ! jq -e '.hooks.PreToolUse | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0028: %s — no PreToolUse array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if ! jq -e --arg re "$GUARD_RE" \
       '[(.hooks.PreToolUse // [])[] | select([.hooks[]?.command] | any(test($re)))] | length > 0' \
       "$f" >/dev/null 2>&1; then
    printf '0028: %s — no ms365 email-guard entry; skipped (nothing to extend)\n' "$f"
    continue
  fi

  if matcher_has_tool "$f"; then
    printf '0028: %s — already carries %s\n' "$f" "$TOOL"
    continue
  fi

  bak="$f.bak-0028-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0028: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0028-$$"
  # APPEND one alternation branch, to the guard entry only, and only when absent. Splitting on "|"
  # and re-joining is what makes a second run a no-op by CONSTRUCTION rather than by the ledger
  # (README rule 1) — a plain string concatenation would grow the matcher on every run.
  # shellcheck disable=SC2016  # $re/$t are jq variables bound by --arg.
  jq --arg re "$GUARD_RE" --arg t "$TOOL" '
      .hooks.PreToolUse = [
        (.hooks.PreToolUse // [])[]
        | if ([.hooks[]?.command] | any(test($re)))
          then .matcher = (((.matcher // "") | split("|")) as $p
                           | (if ($p | any(. == $t)) then $p else $p + [$t] end)
                           | join("|"))
          else . end ]' "$f" > "$tmp" 2>/dev/null \
    || { rm -f "$tmp"; printf '0028: %s — jq FAILED\n' "$f" >&2; rc=1; continue; }

  # Content check BEFORE the swap. Beyond "our branch arrived", it re-asserts the file's other
  # arrays survived and that the entry count is unchanged: a settings edit that lands valid JSON
  # having dropped .hooks.Stop, or having duplicated the guard row, is the worst outcome here.
  before_pre="$(jq '(.hooks.PreToolUse // []) | length' "$f" 2>/dev/null)"
  after_pre="$(jq '(.hooks.PreToolUse // []) | length' "$tmp" 2>/dev/null)"
  if [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1 \
     && matcher_has_tool "$tmp" \
     && [ "$before_pre" = "$after_pre" ] \
     && jq -e --arg re "$GUARD_RE" --arg t "$TOOL" \
          '([(.hooks.PreToolUse // [])[] | select([.hooks[]?.command] | any(test($re)))] | length == 1)
             and ([(.hooks.PreToolUse // [])[]
                   | select([.hooks[]?.command] | any(test($re)))
                   | (.matcher // "") | split("|") | map(select(. == $t)) | length] | all(. == 1))' \
          "$tmp" >/dev/null 2>&1 \
     && jq -e '(.hooks.Stop | type == "array" and length > 0)' "$tmp" >/dev/null 2>&1; then
    mv "$tmp" "$f"
    printf '0028: %s — ms365 guard matcher now carries %s (backup: %s)\n' "$f" "$TOOL" "$bak"
  else
    rm -f "$tmp"
    printf '0028: %s — edit FAILED its content check; left unchanged (backup: %s)\n' "$f" "$bak" >&2
    rc=1
  fi
done

exit "$rc"
