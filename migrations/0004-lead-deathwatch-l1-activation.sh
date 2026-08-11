#!/bin/bash
# migration-class: c10
# migration-step: L1 death-watch is built + GREEN but cannot be activated yet — its watch-file has no producer; the launchd persistence below is written and waiting on that one missing piece
# migration-run: bash ~/Development/claude-infrastructure/migrations/0004-lead-deathwatch-l1-activation.sh
# migration-verify: launchctl list 2>/dev/null | grep -qi deathwatch && [ -s "${CC_DEATHWATCH_WATCHFILE:-$HOME/.claude/deathwatch/watch.tsv}" ]
# migration-conflict: launchctl list 2>/dev/null | grep -qi deathwatch && [ ! -s "${CC_DEATHWATCH_WATCHFILE:-$HOME/.claude/deathwatch/watch.tsv}" ]
#
# 0004 — the L1 half of the never-wait-on-the-dead build (docs/NEVER-WAIT-ACTIVATION.md), staged
# against its MEASURED state rather than against its doc row.
#
# WHY THIS IS A MIGRATION AND NOT A pending-activation SCRIPT. The brief that commissioned this asked
# for `~/.claude/autonomy/pending-activation/`, "following the existing numbered examples". That store
# is the one migrations/README.md was written to abolish: an advisory diode where writes always
# succeed and reads are discretionary (38 pending, 11 rotting past 24 h). The queue was still showing
# 6 un-run and 5 rotting >24 h when this landed, which is the same residue one generation on. So this
# lands on the ENFORCING side, where scripts/deploy-migrations.sh files it once, event-keyed, into a
# store hooks/operator-readout.sh already renders.
#
# ── THE STATE ON DISK, MEASURED 2026-08-09 (not read off the doc) ────────────────────────────────
# docs/NEVER-WAIT-ACTIVATION.md's L1 row names TWO activation steps. They are not in the same state,
# and the doc does not distinguish them:
#
#   1. symlink cc-deathwatch-kqueue → ~/.claude/bin       ALREADY DONE since 2026-07-18. The link
#      exists and points into the checkout. Nothing to do; asserted below so this stays idempotent.
#   2. run `lead-deathwatch.sh --watch <watch-file>` under launchd    BLOCKED, and not on launchd.
#
# 🚨 THE BLOCKER IS THAT `<watch-file>` HAS NO PRODUCER. lead-deathwatch.sh:31 specifies its format —
# `pid <TAB> start <TAB> label <TAB> waiter <TAB> worktree` — and the doc says it is "built from the
# P8 registry (spawn-instant rows)". Nothing in scripts/, bin/ or hooks/ writes such a file. The only
# contents of ~/.claude/deathwatch are the death/alarm records the 2026-07-15 `--selftest` left
# behind, i.e. fixtures, not live rows. So a launchd job installed today would arm kqueue on an EMPTY
# watch-list forever and report a perfectly healthy heartbeat while watching nothing — a watcher whose
# own liveness proves nothing about its coverage, which is the exact failure L1-e exists to prevent,
# reintroduced one level up.
#
# This is the reason the migration is staged with a PRECONDITION rather than a plist. Activating L1
# without its producer would satisfy the activation queue and change no behaviour: the whole point of
# scripts/wait-safety-gate.sh being GREEN is that the DETECTOR is complete, and completeness of the
# detector is not the same claim as coverage of the fleet. L1-a already declares this blindness in
# lead-deathwatch.sh:12 ("BLIND to a pid it never registered ... covered by the P8 registry") — the
# composition it names is real, and the registry side of it is what is missing.
#
# ── THE ORACLE (added 2026-08-11): TWO CLAUSES, BECAUSE ONE OF THEM IS THE WHOLE POINT ───────────
# `launchctl list` alone would answer the question the activation queue asks — is the job loaded —
# and that is the question this file spends its length arguing is the WRONG one. A loaded agent over
# an empty watch-list is the failure described above: kqueue armed on nothing, a heartbeat that
# stays healthy, and coverage of zero. So the verifier only says `registered` when the job is loaded
# AND the list it exists to watch has rows, and the missing half gets its own name via the conflict
# arm — `overridden`, "a different value is set at the same key", which is exactly what a watcher
# pointed at an empty file is. Loaded-and-blind is thus reported as a FAILING state rather than
# folded into either "activated" or "still staged"; today, with nothing loaded, both arms return 1
# and the verdict stays `staged-pending`, which is true. All three states were controlled against a
# stubbed `launchctl` before landing (loaded+rows ⇒ registered · loaded+empty ⇒ overridden ·
# not loaded ⇒ neither).
#
# The label is matched on the substring `deathwatch` rather than a full `com.claude.*` string on
# purpose: no plist for this job exists yet in launchd/, so a label pinned here would be one this
# file INVENTED, and the day someone writes the plist under any other spelling the oracle would read
# false forever while looking authoritative (MEMORY.md caller-census-keyed-on-path-misses-the-name).
# The watch-file rides the same `CC_DEATHWATCH_WATCHFILE` seam the body below uses, but the header's
# fallback deliberately drops the body's inner `${CC_CLAUDE_DIR:-…}` hop and names $HOME/.claude
# outright. registration-state.sh re-runs each verifier once per config dir with CC_CLAUDE_DIR
# re-aimed; there is one death-watch, not five, and lead-deathwatch.sh's own records dir is likewise
# $HOME/.claude/deathwatch — so keeping the indirection here would send the oracle hunting four
# watch-files that were never meant to exist and manufacture a permanent `partial`. Both spellings
# resolve to the same path in every context that actually runs this migration.
#
# WHY c10. The remaining step loads a launchd agent. migrations/README.md: "A migration that touches
# settings.json, a launchd plist, or credentials declares c10 and waits for a human." The §3 rescope
# of C10 has not been ratified, so this STAGES and never self-runs. Promotion is the one-word diff.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
LINK="${CC_CLAUDE_DIR:-$HOME/.claude}/bin/cc-deathwatch-kqueue"
WATCH_FILE="${CC_DEATHWATCH_WATCHFILE:-${CC_CLAUDE_DIR:-$HOME/.claude}/deathwatch/watch.tsv}"

# ── step 1: the symlink (idempotent; already satisfied on this box since 2026-07-18) ─────────────
if [ -e "$LINK" ] || [ -L "$LINK" ]; then
  printf '0004: symlink already present: %s\n' "$LINK"
else
  printf '0004: symlink MISSING (%s) — install.sh normally owns this link class; re-run install.sh\n' "$LINK" >&2
  exit 1
fi

# ── step 2: the PRECONDITION that is actually blocking, checked at CONSUMPTION ───────────────────
# Deliberately re-derived here rather than trusted from the header above. A migration's premise can
# rot between staging and the converge that reads it (MEMORY.md discovery-critic-premise-goes-stale):
# the day something starts producing a watch-file, this check passes on its own and the operator step
# below becomes runnable without anyone editing this file.
if [ ! -s "$WATCH_FILE" ]; then
  cat >&2 <<MSG
0004: L1 death-watch NOT activated — and the missing piece is not the launchd job.

  built + GREEN : bin/cc-deathwatch-kqueue, scripts/lead-deathwatch.sh
                  (scripts/wait-safety-gate.sh: 13 met, 0 failed, 0 NOT BUILT)
  linked        : $LINK
  BLOCKED ON    : nothing produces the watch-file $WATCH_FILE
                  format (lead-deathwatch.sh:31): pid <TAB> start <TAB> label <TAB> waiter <TAB> worktree

Installing a launchd watcher now would arm kqueue on an EMPTY list and heartbeat healthily while
watching nothing. The remaining work is a PRODUCER that writes a row at spawn-instant for each
process a lead may wait on; L1 then activates in one step and this migration passes on its own.
MSG
  exit 1
fi

# ── step 3: reached only once a producer exists — the persistence itself ─────────────────────────
# Written now, so the day the producer lands this is already idempotent and already reviewed.
printf '0004: watch-file present (%s) — install the launchd agent from %s/launchd and load it\n' \
  "$WATCH_FILE" "$REPO"
exit 0
