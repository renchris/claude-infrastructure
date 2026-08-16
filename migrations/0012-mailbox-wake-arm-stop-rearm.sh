#!/bin/bash
# migration-class: c10
# migration-step: register hooks/mailbox-wake-arm.sh ALSO on Stop with asyncRewake so an idle session re-arms its inbox watcher at every boundary instead of going deaf when its birth watcher is spent — it edits settings.json, which is C10
# migration-run: bash ~/Development/claude-infrastructure/migrations/0012-mailbox-wake-arm-stop-rearm.sh
# migration-subject: ~/.claude/hooks/mailbox-wake-arm.sh
# migration-verify: jq -e '[.hooks.Stop[].hooks[]? | select(.command == "~/.claude/hooks/mailbox-wake-arm.sh")] | length >= 1 and all(.[]; .asyncRewake == true)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e '[.hooks.Stop[].hooks[]? | select(.command == "~/.claude/hooks/mailbox-wake-arm.sh")] | length >= 1 and any(.[]; .asyncRewake != true)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
#
# 0012 — W2, the safety net under W1. Subject: hooks/mailbox-wake-arm.sh (claim guard) ·
# tests/mailbox-wake-arm.bats (21/21). Design: docs/research/goal-safe-2way-comms-2026-08-13.md §5.
# Probe: docs/research/w2-stop-rewake-proof/ (P-W2a–d, run before this was written).
#
# WHAT IT FIXES. 0007 arms the watcher at SessionStart, and the watcher is ONE-SHOT by design:
# consumed by its first ping, or expired at 3h59m. SessionStart does not recur, and under a live
# `/goal` every model-armed re-arm is (rightly) denied by validate-bash. So a long-lived session is
# DEAF from the moment its birth watcher is spent until a human types — the residual half of the
# pane-248 incident ("8 pings, none entered context") and the terminal state of the 15 measured cap
# force-idles. Stop is the only boundary that recurs at every idle, so re-arming there is what makes
# the wake path a settings fact rather than something a model must remember.
#
# WHY THE PROBE HAD TO COME FIRST, and what it settled. `exit 2` is OVERLOADED on Stop — it is also
# Stop's own "block" code — so nothing about W1's SessionStart proof carried over by citation. Four
# questions, four answers, measured on CC 2.1.233 with a hermetic config holding only the hook:
#   P-W2a  the Stop is neither blocked nor delayed. A 600 s watch was registered; the turn completed
#          in 4 s and the watcher was still alive across the boundary. The dispatch gate reads
#          `(e.async || e.asyncRewake && K) && !forceSyncExecution` and never consults the event.
#   P-W2b  exit 2 while idle SYNTHESIZES A WAKE, not a retroactive Stop block: transcript line 13 is
#          a harness-authored user turn carrying <task-notification> + the hook's STDERR, and the
#          turn's own result record reads origin.kind = "task-notification".
#   P-W2c  the harness dedupes NOTHING — every Stop launched another watcher.
#   P-W2d  a same-Stop `decision:"block"` from an ordinary shell hook and this one coexist: the block
#          forced its extra turn AND the watcher armed and later woke.
#
# WHY THE GUARD IS IN THE SUBJECT AND NOT HERE. P-W2c is the sharp edge: two watchers on one box both
# fired on the SAME mail line and each burned a model turn. Registration cannot fix that — only the
# hook can, so 0012 registers nothing that 0007 does not already register, and lands only alongside
# the claim guard in mailbox-wake-arm.sh (fresh heartbeat AND a live pid, asked over the whole
# keyset). Do not land this file without that one.
#
# WHY c10. It edits settings.json. migrations/README.md: "A migration that touches settings.json, a
# launchd plist, or credentials declares c10 and waits for a human." The §3 rescope of C10 has not
# been ratified, so this STAGES and never self-runs; promotion is the one-word diff.
#
# BLAST RADIUS. Same three bounds as 0007, plus one this event adds:
#   1. It only ADDS a hook entry; no existing entry is modified or removed.
#   2. `asyncRewake` must be present in every installed track or this refuses (precondition below) —
#      registering the command WITHOUT the field would run a 14400 s watch SYNCHRONOUSLY at every
#      STOP, which is worse here than at birth: it would wedge the session at every single turn end.
#   3. CC_WAKE_ARM=0 kills the behaviour without editing settings.json again.
#   4. NEW, and stated because it is the one cost the probe found: `flushPendingAsyncRewakeHooks`
#      makes a HEADLESS run wait for pending rewake hooks at exit, bounded by a 30 s race. A watcher
#      armed at Stop is such a hook, so a streaming-input headless session can pay up to 30 s on
#      teardown. Plain `claude -p` one-shots are unaffected (the subject's headless guard skips them
#      outright), and 0007 already carries the identical exposure from birth — this adds no new
#      class, only another boundary at which the same one watcher exists.
# Every config file is backed up before it is touched, and the edit is verified BY CONTENT before it
# replaces the live file — so "operator can revert" is a property of this script, not a promise.
#
# WHY IT WRITES EVERY CONFIG DIR. ~/.claude, ~/.claude-next, ~/.claude-secondary, ~/.claude-tertiary
# and ~/.claude-quaternary are separate REAL files, not symlinks into the checkout, and live sessions
# run against all of them. Registering in one leaves every session launched against another deaf at
# exactly the boundary this exists to cover.
set -uo pipefail

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Every sibling entry is written the same way.
HOOK_CMD='~/.claude/hooks/mailbox-wake-arm.sh'
HOOK_FILE="${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/mailbox-wake-arm.sh"
# Strictly ABOVE the adapter's own CC_WAKE_ARM_TIMEOUT (14340), as 0007 registers it, so our clean
# silent exit always wins the race against a harness reap.
TIMEOUT=14400
REWAKE_MSG='📬 Peer mail arrived while you were idle — delivered by the inbox watcher, not typed by you:'
REWAKE_SUM='📬 peer mail'
rc=0

command -v jq >/dev/null 2>&1 || { printf '0012: jq required\n' >&2; exit 1; }

# ── precondition 1: the subject must be on the live layer ────────────────────────────────────────
# Re-derived at CONSUMPTION, not trusted from the header: a migration's premise can rot between
# staging and the converge that reads it. Registering a path that does not execute is a registered
# no-op, and a registered no-op READS GREEN.
if [ ! -x "$HOOK_FILE" ]; then
  printf '0012: NOT registered — %s is missing or not executable.\n' "$HOOK_FILE" >&2
  printf '      hooks/ is symlinked into the live layer by install.sh; run it first.\n' >&2
  exit 1
fi

# ── precondition 2: the subject must carry the CLAIM GUARD ───────────────────────────────────────
# Unique to 0012, and the reason it exists: without the guard this registration is a turn-burner.
# Every Stop would start another watcher on the same box (P-W2c), and they would all wake on the same
# line. Assert the guard is present in the file we are about to point Stop at, rather than assuming
# the two halves of this change landed together — the live layer is a symlink farm and a partial
# converge is exactly how "landed" and "live" come apart here.
if ! grep -q '_armed_already' "$HOOK_FILE"; then
  printf '0012: NOT registered — %s carries no claim guard (_armed_already).\n' "$HOOK_FILE" >&2
  printf '      Registering on Stop without it starts one watcher per idle boundary, each of which\n' >&2
  printf '      wakes the model on the same mail. Land the subject first, then converge.\n' >&2
  exit 1
fi

# ── precondition 3: the RUNNING binary must carry the field ──────────────────────────────────────
# Identical in shape and rationale to 0007's, including the two traps it paid for: a stub binary is
# not a track (size discriminates), and `grep -aq` must own the read rather than sit behind a
# `strings |` pipe, where its early exit SIGPIPEs the producer and pipefail converts a successful
# match into a refusal.
_checked=0 _bad=""
for _t in "$HOME"/.claude-2*/node_modules/@anthropic-ai/claude-code/bin/claude.exe; do
  [ -r "$_t" ] || continue
  _sz="$(wc -c <"$_t" 2>/dev/null | tr -d ' ')"; case "$_sz" in ''|*[!0-9]*) _sz=0 ;; esac
  [ "$_sz" -lt 1000000 ] && continue
  _checked=$(( _checked + 1 ))
  LC_ALL=C grep -aq 'asyncRewake' "$_t" 2>/dev/null || _bad="${_bad}${_t} "
done
if [ -n "$_bad" ]; then
  printf '0012: NOT registered — these installed tracks do NOT carry asyncRewake: %s\n' "$_bad" >&2
  printf '      Registering would make this hook BLOCK every turn end on them for %ss.\n' "$TIMEOUT" >&2
  exit 1
fi
if [ "$_checked" -gt 0 ]; then
  printf '0012: precondition OK — asyncRewake present in all %s installed track(s)\n' "$_checked"
else
  printf '0012: NOTE — no readable installed track to re-confirm asyncRewake; proceeding.\n' >&2
fi

for dir in "$HOME"/.claude "$HOME"/.claude-next "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  f="$dir/settings.json"
  [ -f "$f" ] || continue

  # Only touch a config that already runs Stop hooks. A settings.json with no Stop array is not a
  # fleet config, and inventing one here would be a scope this migration never claimed.
  if ! jq -e '.hooks.Stop | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
    printf '0012: %s — no Stop array; skipped (not a fleet config)\n' "$f"
    continue
  fi

  if jq -e --arg c "$HOOK_CMD" \
       '[.hooks.Stop[].hooks[]?.command] | any(. == $c)' "$f" >/dev/null 2>&1; then
    printf '0012: %s — already registered\n' "$f"
    continue
  fi

  bak="$f.bak-0012-$(date +%Y%m%d%H%M%S)"
  cp -p "$f" "$bak" || { printf '0012: %s — backup FAILED, not touching it\n' "$f" >&2; rc=1; continue; }

  tmp="$f.tmp-0012-$$"
  # Append to the FIRST Stop group. Ordering is irrelevant to correctness: the harness BACKGROUNDS
  # this hook the moment it is dispatched (P-W2a), so it can neither delay a sibling Stop hook nor be
  # delayed by one — including a sibling that returns decision:"block" (P-W2d).
  if jq --arg c "$HOOK_CMD" --argjson t "$TIMEOUT" --arg m "$REWAKE_MSG" --arg s "$REWAKE_SUM" \
       '.hooks.Stop[0].hooks += [{"type":"command","command":$c,"timeout":$t,
         "asyncRewake":true,"rewakeMessage":$m,"rewakeSummary":$s}]' \
       "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ] && jq -e . "$tmp" >/dev/null 2>&1; then
    # verify the edit BY CONTENT before it replaces the live file — both the command AND the field
    # that makes it asynchronous, because the command alone would register a turn-BLOCKING hook.
    if jq -e --arg c "$HOOK_CMD" \
         '[.hooks.Stop[].hooks[]? | select(.command == $c)]
          | length == 1 and .[0].asyncRewake == true' "$tmp" >/dev/null 2>&1; then
      mv "$tmp" "$f" && printf '0012: %s — registered asyncRewake on Stop (backup: %s)\n' "$f" "$bak"
    else
      rm -f "$tmp"; printf '0012: %s — edit did not verify; left unchanged\n' "$f" >&2; rc=1
    fi
  else
    rm -f "$tmp"; printf '0012: %s — jq edit FAILED; left unchanged\n' "$f" >&2; rc=1
  fi
done

exit "$rc"
