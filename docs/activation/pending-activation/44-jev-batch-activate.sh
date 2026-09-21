#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 44-jev-batch  —  load com.claude.jev-batch, then (separately) authorise one window of Jev calls
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: (1) install launchd/com.claude.jev-batch.plist into ~/Library/LaunchAgents and bootstrap it.
#   (2) OPTIONALLY, behind a typed `yes`, arm one bounded window so the job actually calls Jev.
#   The two are deliberately separate acts and step 2 is the only one that sends anything.
#
# WHY THE SPLIT. Loading the job schedules NOTHING that leaves the machine: unarmed, `cc-jev batch`
#   writes one line to its log and exits 0. Arming is the consent, and it is per-window — the batch
#   consumes the token BEFORE its first call, the token expires on a clock, and it carries the
#   corpus, the per-file byte cap and the call ceiling that the batch then honours by construction.
#   A launchd job is not bound by the session permission classifier, so without that split a single
#   bootstrap would silently become standing unattended egress of our engineering lessons under
#   standard retention. Nobody decided that; it is filed as a decision packet.
#
# WHAT IT SENDS, if you arm it: the frontmatter `description:` plus the first 1200 bytes of the body
#   of memory topic files that are reachable from NEITHER MEMORY.md NOR the always-loaded project
#   rules file — 278 of them. Our own engineering lessons. NEVER a transcript, never the mailbox,
#   never the 213,995-message msg corpus, never customer data. Retention is STANDARD: ZDR is
#   Pro/Enterprise-only and returns 403 on this plan.
#
# WHAT IT PRODUCES: ~/.claude/autonomy/jev-promote-<stamp>.jsonl and a SWAP LIST — pairs of
#   (promote this orphan, demote that weak incumbent), one index slot each. It edits nothing.
#
# UNDO: `launchctl bootout gui/$UID/com.claude.jev-batch` and `cc-jev arm --revoke`.
set -uo pipefail
LABEL=com.claude.jev-batch
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
SRC="$REPO/launchd/$LABEL.plist"
DST="$HOME/Library/LaunchAgents/$LABEL.plist"
CCJEV="$HOME/.claude/bin/cc-jev"; [ -x "$CCJEV" ] || CCJEV="$REPO/bin/cc-jev"

[ -f "$SRC" ] || { printf '✗ missing %s — land the plist first.\n' "$SRC" >&2; exit 1; }

if [ "${1:-}" = "--undo" ]; then
  launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
  rm -f "$DST"
  "$CCJEV" arm --revoke >/dev/null 2>&1 || true
  printf '✓ unloaded, plist removed, any armed window revoked.\n'
  exit 0
fi

# ── STEP 1: schedule it. Reversible, sends nothing, so it is driven without asking. ────────────
mkdir -p "$HOME/Library/LaunchAgents"
cp "$SRC" "$DST"
launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true      # idempotent re-bootstrap
if ! launchctl bootstrap "gui/$UID" "$DST" 2>&1; then
  printf '✗ bootstrap failed. Nothing is scheduled and nothing was sent.\n' >&2; exit 1
fi
# VERIFY BY READING BACK THROUGH A DIFFERENT CALL than the one that made the change.
if ! launchctl print "gui/$UID/$LABEL" >/dev/null 2>&1; then
  printf '✗ bootstrap reported success but the job is not present. Not proceeding.\n' >&2; exit 1
fi
printf '✓ %s is loaded (every 1800s).\n' "$LABEL"
printf '  It is INERT: with no armed window it writes one log line per tick and sends nothing.\n\n'

# ── STEP 2: the consent. GATED — this is the step that spends and that transmits. ─────────────
cat <<EOF
Arming authorises ONE bounded window of Jev calls:

  corpus     the 278 memory topic files reachable from neither the index nor the rules file
  sends      the frontmatter description + first 1200 B of body, per file
  ceiling    sized from the live corpus for ONE COMPLETE pass (133 calls today, ~9-27 min),
             expiring in 180 minutes, consumed before the first call
  retention  STANDARD — the vendor keeps what is sent; ZDR is not available on this plan
  reverses   cc-jev arm --revoke  (before the job next ticks)

It cannot be undone once the calls are made.
EOF
printf '\nArm one window now? [yes/N] '
read -r ans
if [ "$ans" != "yes" ]; then
  printf '\nNot armed. The job stays loaded and inert. Arm later with:  cc-jev arm\n'
  exit 0
fi
"$CCJEV" arm || exit 1

# ── STEP 3: RUN IT NOW, rather than leaving you to wait for a tick ────────────────────────────
# No second gate: the arming you just typed IS the authorisation, and this consumes that exact
# window — the same one the timer would have consumed, just sooner. Waiting up to 1800s to find
# out whether the route even answers is the kind of delay that turns a working feature into one
# nobody is sure about, and the preflight inside the batch fails in ~2s if the route is dead.
printf '\nRunning the pass now (the timer would otherwise pick this up within 30 min)...\n\n'
"$CCJEV" batch
printf '\n'
"$CCJEV" status 2>/dev/null | grep -E '^(promotion|armed)' || true

# Name the artifact explicitly. The batch logs the path, but a run that ends by printing WHERE
# the verdicts are is the difference between a feature and a thing you have to go looking for.
_rows="$(find -H "$HOME/.claude/autonomy" -maxdepth 1 -name 'jev-promote-*.jsonl' -size +0c \
         2>/dev/null | sort -r | head -1)"
if [ -n "$_rows" ]; then
  printf '\nVerdicts: %s (%s row(s))\n' "$_rows" "$(wc -l < "$_rows" | tr -d ' ')"
  printf 'Read the swap list again, free, any time:\n    cc-jev promote --report %s\n' "$_rows"
else
  printf '\nNo verdict rows were written. The batch log says why:\n    tail ~/.claude/autonomy/jev-batch.log\n'
fi
