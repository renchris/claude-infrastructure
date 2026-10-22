#!/bin/bash
# migration-class: c10
# migration-step: migration 0012 — register hooks/mailbox-wake-arm.sh ALSO on Stop with asyncRewake in ~/.claude/settings.json, which every account links to, so an idle session re-arms its inbox watcher at every turn end instead of going deaf once its birth watcher is spent (re-probed on 2.1.293: it does not pause /goal checks). It writes settings.json, which is C10.
# migration-run: bash ~/Development/claude-infrastructure/migrations/0012-mailbox-wake-arm-stop-rearm.sh --confirm settings.json
# migration-subject: ~/.claude/hooks/mailbox-wake-arm.sh
# migration-verify: jq -e 'def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); [.hooks.Stop[].hooks[]? | select(((.command // "") | cmd_bare) == "~/.claude/hooks/mailbox-wake-arm.sh")] | length >= 1 and all(.[]; .asyncRewake == true)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# migration-conflict: jq -e 'def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); [.hooks.Stop[].hooks[]? | select(((.command // "") | cmd_bare) == "~/.claude/hooks/mailbox-wake-arm.sh")] | length >= 1 and any(.[]; .asyncRewake != true)' "${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json" >/dev/null
# cmd_bare: a hook command may carry its interpreter (/bin/bash ~/.claude/hooks/x.sh) since 0070.
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
# WHY IT WRITES EVERY CONFIG DIR (original, 2026-08-16). ~/.claude, ~/.claude-next, ~/.claude-secondary,
# ~/.claude-tertiary and ~/.claude-quaternary are separate REAL files, not symlinks into the checkout,
# and live sessions run against all of them. Registering in one leaves every session launched against
# another deaf at exactly the boundary this exists to cover.
# CORRECTED (2026-10-19): since 0037 the four account files are SYMLINKS to the one real
# ~/.claude/settings.json, so the per-dir loop was replaced by the 0068 contract: resolve the one real
# file, refuse a forked fleet (cc-settings-parity), write it once, verify by content. Measured in a
# scratch HOME (docs/research/startup-hooks-2026-10-18/probes/probeB-RESULT.md): the old loop wrote the
# shared file once when everything worked, but when its first write failed it registered through each
# symlink with `mv`, which replaced every link with a real file and forked all four accounts. It also
# registered a bare `#!` command, which 0070 exists to remove (kernel-memory leak per exec).
# Re-probed on 2.1.293 (same doc): the goal-deferral predicate reads only the task registry, and an
# asyncRewake hook never enters it, so this registration does not pause /goal evaluation.
#
# Usage: bash migrations/0012-mailbox-wake-arm-stop-rearm.sh --dry-run | --check | --verify
#        bash migrations/0012-mailbox-wake-arm-stop-rearm.sh --confirm settings.json
# Exit: 0 applied / already applied / skipped / preflight ok · 1 failure, nothing written · 2 usage ·
#       3 REFUSED, an account settings.json is still forked (run 0037 first)
set -uo pipefail

mode=""
case "${1:-}" in
  --dry-run) mode=dry ;;
  --check) mode=check ;;
  --verify) mode=verify ;;
  --confirm) [ "${2:-}" = "settings.json" ] || { printf '0012: --confirm must name its target: --confirm settings.json\n' >&2; exit 2; }; mode=apply ;;
  '') [ -n "${CC_MIGRATION_STATE:-}" ] && mode=apply ;;
  *) printf '0012: unknown argument %s (use --dry-run, --check, --verify or --confirm settings.json)\n' "$1" >&2; exit 2 ;;
esac
[ -n "$mode" ] || { printf '0012: pass --dry-run, --check, --verify or --confirm settings.json\n' >&2; exit 2; }

# shellcheck disable=SC2088  # the tilde is DELIBERATELY literal: this string is stored INTO
# settings.json, where CC expands it at hook-run time. Every sibling entry is written the same way.
HOOK_CMD='~/.claude/hooks/mailbox-wake-arm.sh'
HOOK_FILE="${CC_CLAUDE_DIR:-$HOME/.claude}/hooks/mailbox-wake-arm.sh"
# Strictly ABOVE the adapter's own CC_WAKE_ARM_TIMEOUT (14340), as 0007 registers it, so our clean
# silent exit always wins the race against a harness reap.
TIMEOUT=14400
REWAKE_MSG='📬 Peer mail arrived while you were idle — delivered by the inbox watcher, not typed by you:'
REWAKE_SUM='📬 peer mail'

command -v jq >/dev/null 2>&1 || { printf '0012: jq required\n' >&2; exit 1; }
f="${CC_CLAUDE_DIR:-$HOME/.claude}/settings.json"
parity="${CC_SETTINGS_PARITY_BIN:-$HOME/.claude/bin/cc-settings-parity}"
# Through its interpreter, never by path: a #! exec keeps ~1.1 KiB of kernel memory on macOS 15.8.1
# (docs/research/kalloc-longterm-2026-10-21/REPORT.md). Read from its own #! line, so a stub still runs.
_pl=""; IFS= read -r _pl < "$parity" 2>/dev/null || true
case "$_pl" in *python3*) parity_cmd=(/usr/bin/env python3 "$parity") ;; *) parity_cmd=("$parity") ;; esac
# shellcheck disable=SC2016  # jq programs, not shell
DEFS='def cmd_bare: sub("^(/bin/(ba|z)?sh|/usr/bin/env +(ba|z)?sh|/usr/bin/env +python3?) +(?=[~$/])"; ""); def mine: ((.command // "") | cmd_bare) == $c;'
if [ "$mode" = verify ]; then
  jq -e --arg c "$HOOK_CMD" "$DEFS"' [.hooks.Stop[]?.hooks[]? | select(mine)] | length >= 1 and all(.[]; .asyncRewake == true)' "$f" >/dev/null 2>&1
  exit $?
fi

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

# ── the one shared file (0037): resolve it, refuse a forked fleet, write it once ────────────────────
[ -f "$f" ] || { printf '0012: %s not found — nothing written\n' "$f" >&2; exit 1; }
real="$f"
if [ -L "$f" ]; then t="$(readlink "$f")"; case "$t" in /*) real="$t" ;; *) real="$(dirname "$f")/$t" ;; esac; fi
jq -e . "$real" >/dev/null 2>&1 || { printf '0012: %s is not valid JSON — nothing written\n' "$real" >&2; exit 1; }

# Only touch a config that already runs Stop hooks. A settings.json with no Stop array is not a
# fleet config, and inventing one here would be a scope this migration never claimed.
if ! jq -e '.hooks.Stop | type == "array" and length > 0' "$real" >/dev/null 2>&1; then
  printf '0012: %s — no Stop array; skipped (not a fleet config)\n' "$real"
  exit 0
fi
if jq -e --arg c "$HOOK_CMD" "$DEFS"' [.hooks.Stop[].hooks[]? | select(mine)] | length > 0' "$real" >/dev/null 2>&1; then
  printf '0012: %s — already registered\n' "$real"
  exit 0
fi
"${parity_cmd[@]}" check >/dev/null 2>&1 || {
  printf '0012: REFUSED — accounts do not all share %s (%s check failed). Converge with 0037 first.\n' "$f" "$parity" >&2
  exit 3
}
printf '0012: will register %s on Stop (asyncRewake) in %s\n' "$HOOK_CMD" "$real"
case "$mode" in
  dry) printf '0012: DRY RUN — nothing written\n'; exit 0 ;;
  check) printf '0012: CHECK ok — preflight passes, nothing written\n'; exit 0 ;;
esac

bdir="$HOME/.claude/backups/mailbox-wake-arm-stop-0012-$(date +%Y%m%d%H%M%S)"
mkdir -p "$bdir" && cp -p "$real" "$bdir/settings.json" || { printf '0012: backup FAILED — nothing written\n' >&2; exit 1; }
tmp="$(dirname "$real")/.settings.json.tmp-0012-$$"
# Append to the FIRST Stop group. Ordering is irrelevant to correctness: the harness BACKGROUNDS
# this hook the moment it is dispatched (P-W2a), so it can neither delay a sibling Stop hook nor be
# delayed by one — including a sibling that returns decision:"block" (P-W2d). The command names its
# interpreter (0070): a bare `#!` exec leaks kernel memory on macOS 15.7.9, at every turn end here.
if ! jq --arg c "/bin/bash $HOOK_CMD" --argjson t "$TIMEOUT" --arg m "$REWAKE_MSG" --arg s "$REWAKE_SUM" \
     '.hooks.Stop[0].hooks += [{"type":"command","command":$c,"timeout":$t,
       "asyncRewake":true,"rewakeMessage":$m,"rewakeSummary":$s}]' "$real" > "$tmp" 2>/dev/null \
   || ! jq -e . "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp"; printf '0012: jq edit FAILED — nothing written\n' >&2; exit 1
fi
# BY CONTENT: exactly one entry, and asynchronous (the command alone would register a turn-BLOCKING
# hook); with that entry removed, the documents are identical.
norm() { jq -S --arg c "$HOOK_CMD" "$DEFS"' .hooks.Stop |= map(.hooks |= map(select(mine | not)))' "$1"; }
if ! jq -e --arg c "$HOOK_CMD" "$DEFS"' [.hooks.Stop[].hooks[]? | select(mine)] | length == 1 and .[0].asyncRewake == true' "$tmp" >/dev/null 2>&1 \
   || [ "$(norm "$real")" != "$(norm "$tmp")" ]; then
  rm -f "$tmp"; printf '0012: edit did not verify by content — nothing written\n' >&2; exit 1
fi
mv "$tmp" "$real" || { rm -f "$tmp"; printf '0012: write FAILED — nothing written\n' >&2; exit 1; }
printf '0012: registered asyncRewake on Stop for every account. Backup: %s/settings.json. Takes effect in NEW sessions.\n' "$bdir"
"${parity_cmd[@]}" check >/dev/null 2>&1 || printf '0012: WARNING — cc-settings-parity check now fails; restore with: cp -p %s/settings.json %s\n' "$bdir" "$real" >&2
exit 0
