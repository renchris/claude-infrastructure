#!/bin/bash
# migration-class: c10
# migration-step: register hooks/mailbox-wake-arm.sh as an asyncRewake SessionStart hook so every session is inbox-armed at birth with no model action — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0007-mailbox-wake-arm-registration.sh
# migration-subject: ~/.claude/hooks/mailbox-wake-arm.sh
# migration-verify: jq -e '[.hooks.SessionStart[].hooks[]? | select(.command == "~/.claude/hooks/mailbox-wake-arm.sh")] | length >= 1 and all(.[]; .asyncRewake == true)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e '[.hooks.SessionStart[].hooks[]? | select(.command == "~/.claude/hooks/mailbox-wake-arm.sh")] | length >= 1 and any(.[]; .asyncRewake != true)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# The verifier asserts the COMMAND *and* `asyncRewake`, and the conflict oracle is what separates the
# two ways this can be absent. Registering the command WITHOUT the field does not merely fail to arm:
# the harness would run this hook SYNCHRONOUSLY at every session birth and block it for the full
# 14400s timeout — strictly worse than never registering. That is `overridden`, not `not-delivered`,
# and it needs the opposite fix (repair the entry, not add one).
#
# 0007 — the registration half of arming-by-construction.
# Subject: hooks/mailbox-wake-arm.sh · tests/mailbox-wake-arm.bats (12/12, 2 mutants killed)
# Finding: docs/plans/CROSS_SESSION_COMMS_V2.md §10 (findings 1, 2 and 4)
#
# WHAT IT FIXES. Arming the inbox watcher is currently something a MODEL must remember to do: a Stop
# hook nags "you are about to go idle with NO wake path armed", the model runs cc-await-ping, the
# watcher exits on the first ping, and the model must remember again. Measured in one firing session:
# re-armed by hand FIVE times. Anything a model must remember is not solved — it is brittle exactly
# the way the operator reported ("brittle between armed and unarmed state").
#
# CC 2.1.219 exposed `asyncRewake` as a generic per-hook field, and it is still live on 2.1.220 — the
# binary all 14 live sessions actually run (re-verified 2026-08-09 by reading the binary: the field is
# consumed at the hook-dispatch call site, not merely present as a string). A SessionStart hook
# declared `asyncRewake: true` is launched by the HARNESS in the background, outlives the birth turn,
# and wakes the model when it exits 2. Arming stops being a thing to remember and becomes a
# declarative line of settings JSON. Proven live 2026-07-29; never wired anywhere until this diff.
#
# A/B'd live 2026-08-13 (docs/research/goal-asyncrewake-ab-2026-08-13/, backlog d9d0012229b7): the
# claim that this registration wakes an idle session WITHOUT deferring an armed /goal was, until
# then, a binary read. Three hermetic arms varying only HOW the same watcher is registered — 30
# Stops, CC's own background_tasks recorded at each — split perfectly: 24 registry-empty Stops → 24
# goal evaluations, 6 holding a parked shell → 0. The asyncRewake watcher was alive across 5 of the
# empty-registry Stops and fired its wake in the same session, so both halves hold together.
#
# WHY A WRAPPER AND NOT `cc-await-ping` DIRECTLY. The two contracts are INVERTED — asyncRewake wakes
# on exit 2, cc-await-ping exits 0 on mail-arrived and 2 on timeout. Registered as the 2026-07-29
# remainder specifies, the hook would be silent on every delivered message and fire a spurious wake on
# every idle timeout. cc-await-ping's rc 2 cannot be re-mapped at the source (cc-wait:138 branches on
# it), so the translation lives in the adapter this registers.
#
# WHY c10. It edits settings.json. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." The §3 rescope of C10 has not
# been ratified, so this STAGES and never self-runs; promotion is the one-word diff.
#
# BLAST RADIUS, stated plainly because this touches the FLEET WAKE PATH. A wake-path change that
# lands wrong makes every running session deaf. Three independent bounds:
#   1. It only ADDS a hook entry; no existing entry is modified or removed.
#   2. `asyncRewake` is carried by BOTH installed tracks (2.1.219 and 2.1.220 — occurrence counts
#      7/5/4/13 identical in each), so no live session reads a field its binary does not know.
#   3. The subject itself honours CC_WAKE_ARM=0 as a total no-op, so the behaviour can be killed
#      without editing settings.json again.
# Every config file is backed up before it is touched, and the edit is verified BY CONTENT before it
# replaces the live file — so "operator can revert" is a property of this script, not a promise.
#
# WHY IT WRITES EVERY CONFIG DIR. ~/.claude, ~/.claude-next, ~/.claude-tertiary and
# ~/.claude-quaternary are separate REAL files, not symlinks into the checkout (measured 2026-08-09:
# 35 940 / 35 270 / 35 929 / 35 947 B — already divergent), and live sessions run against all of them.
# Registering in one leaves every session launched against another unarmed, which is the same silent
# half-coverage this hook exists to abolish.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Every sibling entry is written the same way.
HOOK_CMD='~/.claude/hooks/mailbox-wake-arm.sh'
HOOK_FILE="${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/mailbox-wake-arm.sh"
# Strictly ABOVE the adapter's own CC_WAKE_ARM_TIMEOUT (14340) so our clean silent exit always wins
# the race against a harness reap whose behaviour toward a backgrounded hook is NOT established.
TIMEOUT=14400
REWAKE_MSG='📬 Peer mail arrived while you were idle — delivered by the inbox watcher, not typed by you:'
REWAKE_SUM='📬 peer mail'
rc=0

command -v jq >/dev/null 2>&1 || { printf '0007: jq required\n' >&2; exit 1; }

# ── precondition, re-derived at CONSUMPTION rather than trusted from the header ──────────────────
# A migration's premise can rot between staging and the converge that reads it
# (MEMORY.md discovery-critic-premise-goes-stale). If the adapter is not on the live layer yet, the
# registration would name a path that does not execute — a registered no-op, which reads GREEN.
if [ ! -x "$HOOK_FILE" ]; then
  printf '0007: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it first.\n' >&2
  exit 1
fi

# ── second precondition: the RUNNING binary must carry the field ─────────────────────────────────
# `asyncRewake` is what makes this entry more than an ignored key. If a future track drops it, the
# hook would be launched SYNCHRONOUSLY at every session birth and block it for the full timeout —
# a far worse failure than not arming. Refuse rather than risk it. Read from the binary the harness
# is actually running, never from a launcher's --version
# (MEMORY.md version-identity-is-the-running-process-not-the-launcher).
# Keyed on the INSTALLED TRACKS, not on $PPID: this normally runs from the converger or an operator
# shell, whose parent is not a claude process at all, so a PPID-keyed check would land on its
# "cannot prove" branch essentially always — a precondition that never binds is not a precondition
# (MEMORY.md sensor-default-off-makes-blindness-the-shipping-path). Every track that can launch a
# session is checked, and a SINGLE track missing the field is enough to refuse: sessions are launched
# against all of them.
_checked=0 _bad=""
for _t in "$HOME"/.claude-2*/node_modules/@anthropic-ai/claude-code/bin/claude.exe; do
  [ -r "$_t" ] || continue
  # A stub is not a track. The global-npm "2.1.224" on this box is a 500-byte error script, and
  # grepping it returns a FALSE ZERO that would refuse a perfectly good registration
  # (MEMORY.md lookup-miss-is-not-absence). Size is the cheap discriminator.
  _sz="$(wc -c <"$_t" 2>/dev/null | tr -d ' ')"; case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
  [ "$_sz" -lt 1000000 ] && continue
  _checked=$(( _checked + 1 ))
  # grep -aq DIRECTLY on the binary — never `strings | grep -q`. Measured 2026-08-10: under this
  # file's `set -o pipefail`, grep -q exits at the first match, strings dies of SIGPIPE (141), and
  # pipefail converts the SUCCESSFUL match into a refusal — this precondition refused BOTH healthy
  # tracks on its first live run (the field provably present: grep -ac = 5). A -q reader early-exits
  # by design, so it must own the read, not sit behind a pipe (kin of MEMORY.md
  # verification-harness-vacuous-pass-traps: `bats|tail` = the PIPE's rc).
  LC_ALL=C grep -aq 'asyncRewake' "$_t" 2>/dev/null || _bad="${_bad}${_t} "
done
if [ -n "$_bad" ]; then
  printf '0007: NOT registered — these installed tracks do NOT carry asyncRewake: %s\n' "$_bad" >&2
  printf '      Registering would make this hook BLOCK every session birth on them for %ss.\n' "$TIMEOUT" >&2
  exit 1
fi
if [ "$_checked" -gt 0 ]; then
  printf '0007: precondition OK — asyncRewake present in all %s installed track(s)\n' "$_checked"
else
  # No readable track (a fresh box, or an install layout this loop does not know). Do not guess:
  # the field is inert-but-harmless on a binary that ignores an unknown key, and the blocking risk
  # requires it to have been REMOVED after being present, which no track on this box exhibits.
  printf '0007: NOTE — no readable installed track to re-confirm asyncRewake; proceeding.\n' >&2
fi

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Only touch a config that already runs the sibling SessionStart hooks. A settings.json with no
  # SessionStart array is not a fleet config, and inventing one here would be a scope this migration
  # never claimed.
  if ! jq -e '.hooks.SessionStart | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0007: %s — no SessionStart array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg c "$HOOK_CMD" \
       '[.hooks.SessionStart[].hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0007: %s — already registered\n' "$f"
    continue
  fi

  bak="$f.bak-0007-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0007: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0007-$$"
  # Append to the FIRST SessionStart group. Ordering is irrelevant to correctness: this hook is
  # BACKGROUNDED by the harness the moment it is dispatched, so it can neither delay nor be delayed
  # by a sibling — which is the entire property that makes arming-at-birth free.
  if jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" --arg m "$REWAKE_MSG" --arg s "$REWAKE_SUM" \
       '.hooks.SessionStart[0].hooks += [{"type":"command","command":$c,"timeout":$t,
         "asyncRewake":true,"rewakeMessage":$m,"rewakeSummary":$s}]' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify the edit BY CONTENT before it replaces the live file — both the command AND the field
    # that makes it asynchronous, because the command alone would register a session-BLOCKING hook.
    if jq -e --arg c "$HOOK_CMD" \
         '[.hooks.SessionStart[].hooks[]? | select(.command == $c)]
          | length == 1 and .[0].asyncRewake == true' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0007: %s — registered asyncRewake (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0007: %s — edit did not verify; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0007: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
