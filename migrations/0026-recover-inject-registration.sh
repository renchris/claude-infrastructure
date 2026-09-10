#!/bin/bash
# migration-class: c10
# migration-step: register hooks/recover-inject.sh as a UserPromptSubmit hook so a session that comes back from a NON-quota interruption (network drop, crash, stall, a failed background task) is told to audit disk before it reconciles from context — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0026-recover-inject-registration.sh
# migration-subject: ~/.claude/hooks/recover-inject.sh
# migration-verify: jq -e '[.hooks.UserPromptSubmit[].hooks[]? | select(.command == "~/.claude/hooks/recover-inject.sh")] | length >= 1 and all(.[]; (.asyncRewake // false) == false)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e '[.hooks.UserPromptSubmit[].hooks[]? | select(.command == "~/.claude/hooks/recover-inject.sh")] | length >= 1 and any(.[]; (.asyncRewake // false) != false)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0026 — D3 of docs/plans/NONLIMIT_RESUME_LADDER.md (T6/W2-B).
# Subject: hooks/recover-inject.sh · tests/recover-inject.bats (18/18, 5 mutants killed)
# Engine:  scripts/limit-recover/lr-audit.py --ledger-only · lr-lib.sh lr_last_api_error /
#          lr_tail_nonsuccess_notification · tests/lr-audit-nonlimit.bats (29/29)
#
# WHAT IT FIXES. `/limit-recover`'s description named only quota and auth-cliff triggers, so
# "(Reconnected to internet, continue)" loaded none of the recovery machinery — and the model then
# reconciled from CONTEXT, which still holds the pre-kill narrative, reads plausible, satisfices on
# the units it remembers, and smooths the gaps into the conclusion. The engine was never
# limit-specific (lr-audit's verdict never consults the REASON for a death); only the trigger was.
# On 2026-09-09 the operator typed the correcting paragraph BY HAND seven times in 93 seconds, once
# per blocked pane. That is a hand-off that makes the human the runtime, and this registration is
# what removes it: the notice arrives on the prompt they were going to type anyway, and on the
# harness's own `<task-notification>` wake, which is the majority wake in this fleet.
#
# WHY THE VERIFIER ASSERTS `asyncRewake` IS ABSENT, and why that is the conflict arm. This is the
# INVERSE of 0007's oracle, deliberately. 0007 registers a SessionStart watcher that MUST be
# backgrounded, so its absence-of-field case is the catastrophe. Here the hook is a synchronous
# UserPromptSubmit hook whose entire output contract is `additionalContext` on stdout — a field the
# harness reads only from a synchronous hook. Registered `asyncRewake: true` it would be backgrounded,
# its stdout would reach nobody, and it would report GREEN while injecting nothing on every prompt
# for the life of the fleet: a registered no-op, which is the one failure this whole plan is about
# (a fail-safe default that mimics the healthy state is unfalsifiable). So a wrong value here is
# genuinely possible and genuinely silent, which is exactly when README says to declare a conflict
# oracle. `overridden` needs the opposite fix from `not-delivered`: repair the entry, not add one.
#
# WHY c10. It edits settings.json. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." So this STAGES and never
# self-runs.
#
# BLAST RADIUS. This hook runs on EVERY prompt in every session, so a bad landing is felt everywhere.
# Four independent bounds, three of them properties of the subject rather than promises:
#   1. It only ADDS an entry; no existing entry is modified or removed.
#   2. The subject can never cost a prompt: it is not `set -e`, every path exits 0, and it emits only
#      `additionalContext`. It has no `decision`, no `block`, and writes nothing outside its own
#      latch dir and log. tests/recover-inject.bats pins exit 0 on a missing transcript, on garbage
#      stdin and on empty stdin.
#   3. Cost is bounded to a fixed 128 KB TAIL read on the common path — the full one-pass ledger is
#      paid only when a death record is actually present, and then only ONCE per death record
#      (the latch is `mkdir`, an atomic test-and-set, taken before the work).
#   4. `CC_RECOVER_INJECT=off` is a total no-op, so the behaviour can be killed without editing
#      settings.json again.
# Every config file is backed up before it is touched and the edit is verified BY CONTENT before it
# replaces the live file, so "the operator can revert" is a property of this script.
#
# WHY IT WRITES EVERY CONFIG DIR. ~/.claude and its siblings are separate REAL files, not symlinks
# into the checkout, and live sessions run against all of them. Registering in one leaves every
# session launched against another uncorrected — the same silent half-coverage the hook exists to
# abolish, and what `registration-state.sh` would report as a permanent `partial`.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Every sibling entry is written the same way.
HOOK_CMD='~/.claude/hooks/recover-inject.sh'
HOOK_FILE="${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/recover-inject.sh"
# Generous but finite. The common path is a 128 KB tail read; the expensive path is one sequential
# pass over one transcript, paid once per death record. A UserPromptSubmit hook that hangs delays the
# operator's own prompt, so this must be small enough that a pathological read cannot feel like a
# wedge, and large enough that a genuinely large transcript still completes.
TIMEOUT=25
rc=0

command -v jq >/dev/null 2>&1 || { printf '0026: jq required\n' >&2; exit 1; }

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# A migration's premise can rot between staging and the converge that reads it. If the hook is not on
# the live layer yet, this registration would name a path that does not execute — and a registered
# no-op READS GREEN, which is the failure mode this file's own subject exists to remove.
if [ ! -x "$HOOK_FILE" ]; then
  printf '0026: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it first.\n' >&2
  exit 1
fi

# ── second precondition: THE ENGINE THE HOOK CALLS MUST BE LIVE, NOT MERELY LANDED ──────────────
# The hook degrades safely when the ledger is absent (it says UNREAD rather than "nothing was
# delegated", and tests/recover-inject.bats pins that wording) — but registering it against a live
# layer whose lr-lib.sh predates `lr_last_api_error` buys a hook that logs
# "refused: lr-lib too old" on every prompt and injects nothing, forever, silently. Landed is not
# live: the live layer is a per-file symlink farm and an ADD is absent until the converger runs.
# Verify BY CONTENT (grep the function), never by a lag counter.
_LR_LIVE="${CC_CLAUDE_DIR:-$HOME/.claude}/scripts/limit-recover/lr-lib.sh"
if [ ! -r "$_LR_LIVE" ]; then
  printf '0026: NOT registered — %s is not readable; the hook would refuse on every prompt.\n' "$_LR_LIVE" >&2
  exit 1
fi
if ! grep -q 'lr_last_api_error' "$_LR_LIVE" 2>/dev/null; then
  printf '0026: NOT registered — the LIVE %s does not carry lr_last_api_error.\n' "$_LR_LIVE" >&2
  printf '      The hook would log "refused: lr-lib too old" on every prompt and inject nothing.\n' >&2
  printf '      Converge the live layer first (install.sh / deploy-live), then re-run this.\n' >&2
  exit 1
fi
_LA_LIVE="${CC_CLAUDE_DIR:-$HOME/.claude}/scripts/limit-recover/lr-audit.py"
if [ -r "$_LA_LIVE" ] && ! grep -q 'ledger-only' "$_LA_LIVE" 2>/dev/null; then
  # NOT fatal: the hook still emits the death record and the audit instruction, and says UNREAD for
  # the population rather than claiming a zero. Said out loud so the degradation is a known state
  # rather than a discovery.
  printf '0026: NOTE — the live lr-audit.py has no --ledger-only; the notice will fire and report\n' >&2
  printf '      the delegation population as UNREAD until the live layer converges.\n' >&2
fi
printf '0026: preconditions OK — subject executable, live lr-lib carries the predicate\n'

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Only touch a config that already runs sibling UserPromptSubmit hooks. A settings.json with no
  # UserPromptSubmit array is not a fleet config, and inventing one here would be a scope this
  # migration never claimed.
  if ! jq -e '.hooks.UserPromptSubmit | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0026: %s — no UserPromptSubmit array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg c "$HOOK_CMD" \
       '[.hooks.UserPromptSubmit[].hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0026: %s — already registered\n' "$f"
    continue
  fi

  bak="$f.bak-0026-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0026: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0026-$$"
  # Appended to the FIRST UserPromptSubmit group. Ordering does not affect correctness: the harness
  # concatenates the additionalContext of every hook in the chain, and this notice does not depend on
  # (or interfere with) any sibling's output.
  if jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" \
       '.hooks.UserPromptSubmit[0].hooks += [{"type":"command","command":$c,"timeout":$t}]' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # Verify the edit BY CONTENT before it replaces the live file: the command must be there EXACTLY
    # once, and it must NOT carry asyncRewake — a backgrounded entry's stdout reaches nobody, so it
    # would inject nothing while reading registered.
    if jq -e --arg c "$HOOK_CMD" \
         '[.hooks.UserPromptSubmit[].hooks[]? | select(.command == $c)]
          | length == 1 and ((.[0].asyncRewake // false) == false)' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0026: %s — registered UserPromptSubmit (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0026: %s — edit did not verify; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0026: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
