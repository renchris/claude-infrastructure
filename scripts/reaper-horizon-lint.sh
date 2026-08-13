#!/bin/bash
# shellcheck disable=SC2086  # file-wide: $DECLARED is INTENTIONALLY word-split (it is a space-separated
# list of files passed as multiple args to grep -r); quoting it would make grep treat the list as one path.
# reaper-horizon-lint — converts S-1 from "safe by luck" into "safe by construction".
#
# THE CONSTRAINT (blueprint §3.3 S-1): a supervisor polls on an interval. **Any evidence whose lifetime
# is shorter than that interval is INVISIBLE to it** — the supervisor sweeps, finds nothing, and reports
# health into a fire. So:
#
#     NO REAPER'S HORIZON MAY BE SHORTER THAN THE SUPERVISOR'S SWEEP INTERVAL × 10.
#
# Today's horizons satisfy this BY LUCK, not by design. A future "tidy up /tmp" change dropping one to
# 5 minutes would blind a supervisor that does not exist yet — and EVERY TEST WOULD STILL PASS, because
# nothing is watching the constraint. This gate is what makes that change fail TODAY.
#
# It is deliberately a GREP OVER THE SOURCE, not a read of a config doc: the horizons that matter are the
# ones in the code (audit §3i — a check must observe the thing it guards, not a description of it).
#
# Exit: 0 = clean · 1 = a horizon is too short, or an UNDECLARED reaper appeared on an evidence artifact.
set -uo pipefail
# Resolve our OWN path before the cd. §5 reads this file's `@anchor` lines, and after `cd ..` a
# relative $0 (`bash ./reaper-horizon-lint.sh` from scripts/) no longer resolves — the anchor pass
# would then read nothing and report clean, which is the blind-spot shape §3's header forbids
# (memory: self-identity-guard-must-fully-resolve).
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 2

# ── the one source of truth for the sweep interval ────────────────────────────────────────────────
# Blueprint §3.3: the daemon loop is 30s, but the BACKSTOP tier (team-orphan-reaper) is 600s. Take the
# LONGEST tier — the constraint must hold against the slowest observer, not the fastest.
# ⚠️ When scripts/lead-supervisor.sh lands it MUST NOT re-declare this number. Two copies of a constraint
# is invariant-7-shaped: the constraint's evidence and its enforcement would drift apart silently. The
# check at the bottom enforces that.
SUPERVISOR_SWEEP_MAX_S="${SUPERVISOR_SWEEP_MAX_S:-600}"
SAFETY=10
MIN_HORIZON_S=$(( SUPERVISOR_SWEEP_MAX_S * SAFETY ))

# ── the EVIDENCE artifacts (what a supervisor reads to detect failure) ────────────────────────────
# NOTE the scoping: `scripts/prune-backups.sh` also deletes on `-mmin +5`, and that is FINE — backups are
# not supervisor-observed evidence. A lint that flagged it would false-positive on every run, and a
# detector that cries wolf is a detector that gets ignored (the same reason cc-board has a grace window).
EVIDENCE_GREP='cc-telemetry|cc-registry|CC_TELEMETRY_DIR|CC_REGISTRY_DIR'
# scripts/lead-supervisor.sh READS telemetry (evidence) and reaps it two ways: (a) reap_clean / clear_page
# drop a row/page on a RESOLVED lifecycle end (clean-completion or page void) — a page/state LIFECYCLE op,
# not an age reaper; (b) gc_stale is a REAL AGE-HORIZON reaper — it drops a live-owner telemetry row past
# CC_SUP_GC_S seconds (item fdc101e8b0c7: a hung / pid-recycled owner otherwise STALL?-escalates every
# sweep). Section 2b below bounds that horizon ≥ the floor, exactly as §1/§2 bound -mmin/RETAIN_H — the
# age-reaper the earlier note anticipated ("declaring keeps the protection"). Declared here = reviewed.
# scripts/lead-reconciler.sh (L4) references CC_REGISTRY_DIR (an INDEPENDENT liveness roster) and has an
# `rm -f`, so section-3 flags it — but its only rm -f is clearing a DIVERGENCE-STATE file when that
# divergence RESOLVES (a state LIFECYCLE op, the exact analog of clear_page) + a jq temp; NOT an age-horizon
# reaper on the telemetry/registry spine. Its durable evidence (the reconciler heartbeat + the PAGE) is
# never deleted. It declares no `-mmin`/`RETAIN_H`, so sections 1/2 find nothing to bound. Declared = reviewed.
# hooks/waiting-recycle.sh rm's ONLY its own arm/cooldown/kill SENTINELS on re-arm/disarm/unkill — state
# lifecycle (clear_page analog); every fire/abstain decision is durably logged to the IDL, which is the
# evidence and is never touched. No -mmin/RETAIN_H. Declared = reviewed (2026-07-18 desk wave).
# scripts/handoff-fire.sh rm's ONLY atomic-write TEMP files (mv-or-rm on registry/role writes) + its own
# transient rank-stderr capture consumed in-function — scaffolding, never evidence; fire outcomes live in
# the fired session's transcript + registry row + IDL. No -mmin/RETAIN_H. Declared = reviewed (2026-07-18).
# bin/cc-reaper names `cc-registry` in prose (the P0-12b self-check message tells the operator where the
# blind spot is) and rm's ONLY two things, both state LIFECYCLE ops (the clear_page analog), NEITHER an
# age-horizon reaper on the telemetry/registry spine: (a) its own surface-page damping markers
# ($PAGEDIR/*.cause) when a pane leaves the surface set (T-P3-3); (b) its own fired-peer markers
# ($FIRED_DIR/<pane>.json, clear_fired_marker) after a CONFIRMED teardown of that pane — the subject of
# the evidence no longer exists, so the marker is retired with it, never on age. Neither is read by a
# supervisor as failure evidence. The registry itself is never read or deleted here (the self-check counts
# live panes via `ps`, independent of the registry). No -mmin/RETAIN_H. Declared = reviewed
# (2026-07-19 desk wave; fired-peer marker added 2026-07-20, T-P3-4).
# bin/cc-value READS CC_TELEMETRY_DIR (evidence) to compute the value ledger and has an `rm -f`, so
# section-3 flags it — but its only rm -f is the mv-or-rm on its OWN atomic-write cache temp `$tmpc`
# (`mktemp "${CACHE_FILE}.XXXXXX"` → `mv -f $tmpc $CACHE_FILE || rm -f $tmpc`, the handoff-fire scaffold
# analog). $CACHE_FILE is a TTL-rebuilt DERIVED value cache, not supervisor-observed evidence; the
# telemetry it reads is never deleted. No -mmin/RETAIN_H, so sections 1/2 find nothing to bound.
# Declared = reviewed (2026-07-19 desk wave).
# bin/cc-reconcile READS CC_REGISTRY_DIR (an INDEPENDENT liveness roster) + live pids to BACKFILL missing
# rows and has an `rm -f`, so section-3 flags it — but its only rm -f is the mv-or-rm on its atomic-write
# temp `$tmp` (`$REG_DIR/.$pane.$$.tmp`, schema byte-identical to session-register.sh:75-81), removed on a
# failed mv/jq. It only ever CREATES registry rows (via mv); it never age-reaps the registry — durable
# evidence is never deleted. No -mmin/RETAIN_H, so sections 1/2 find nothing to bound. Declared = reviewed (2026-07-19 desk wave).
# hooks/lead-crash-watchdog.sh READS CC_REGISTRY_DIR (`grep -lE` on the session id, in the assignee-harvest
# helper and in gc_teardown_marker; no registry row is ever deleted) and has rm -f sites, so section-3
# flags it — but every one is a LIFECYCLE op, never an age reaper: gc_teardown_marker() removes
# $CC_TEARDOWN_DIR/$sid.json + its pane alias, and its own docstring binds it to "ONLY the owner-guarded
# pidfile-rm blocks below" (our own pid's recycle/self-close, fully handled); the pidfile trio under
# $WATCHDOG_DIR ($sid.pid/.id/.daemon) is pid-EQUALITY-guarded (`[[ "$(cat …$sid.pid)" == "$pid" ]]` — the documented
# cross-incarnation disarm, 125 proven disarms before it); the death-claim `rmdir "$claim"` releases a
# mutex this same function took; and the `rm -f "$tmp"` in the shutdown_request injector is the mv-or-rm
# on its own jq atomic write (the handoff-fire.sh temp-scaffold shape declared above). No
# -mmin/-mtime/RETAIN_H anywhere in the file, so sections 1/1b/2 find nothing to bound. Identical shape to
# lead-reconciler.sh + waiting-recycle.sh above. Declared = reviewed (2026-07-25 infra-perfection pass,
# adopted from the stranded 101ab269; re-verified against live code 2026-08-08,
# and the +2d sweeps of .daemon / *.death-*.d live in hooks/session-end.sh, which owns that dir's GC).
# ⚠️ Cited by SYMBOL, never by line number — deliberately, and this entry is why (see §5). It carried
# five line refs (:262,:302 · :299 · :869,:893), which were already hand-re-derived once on 2026-07-29
# "after the singleton/jetsam work". By 2026-08-08 all five had rotted AGAIN across three unrelated
# commits to the subject (:299→:323, :869→:1054, :893→:1078) — a reader following :869 lands 185 lines
# from the code the sentence describes. Nine days of validity per hand-derivation is not a maintenance
# problem, it is the wrong anchor: line numbers are the one form guaranteed to move on an edit that
# changes nothing this justification claims.
# scripts/scratchpad-reaper.sh READS CC_REGISTRY_DIR (the liveness roster) and `rm -rf`s, so section-3
# flags it — and unlike the entries above it IS a genuine age reaper, so it belongs here on the merits.
# What it reaps is NOT supervisor evidence: `/private/tmp/claude-501/<project>/<sessionUUID>/` is the CC
# harness's DERIVED per-session temp scratchpad (audit 03 §1d rank 1 — 10.67 GB, +810 MB/day, bounded
# only by reboot). No supervisor, page, or gate reads it; the durable evidence for a session is its
# hooks/lib/context-econ.sh names CC_TELEMETRY_DIR/CC_REGISTRY_DIR and has rm -f sites, so section-3
# flags it — but both (:158,:160) are the mv-or-rm on its OWN atomic-write temp ("$hist.tmp.$$",
# removed only when the mv that would have published it failed). Byte-identical in shape to the
# handoff-fire.sh / cc-value / cc-reconcile entries above: scaffolding, never evidence. It writes the
# context-history file it reads and deletes no telemetry/registry row; no -mmin/RETAIN_H anywhere, so
# sections 1/2 find nothing to bound. Declared = reviewed (2026-07-29, infra-perfection land).
# transcript + registry row + IDL, none of which this script can touch (it only ever READS the registry,
# never deletes a row). Its horizon is a LITERAL `-mmin +2880` (48 h = 172,800 s), scored by §1 below —
# 28× the 6,000 s floor — and liveness (live pid OR a transcript touched inside the horizon) outranks
# age, so a long-running session's scratchpad survives regardless. Declared = reviewed (2026-07-25).
# bin/cc-recover-safeguard READS CC_REGISTRY_DIR (CC_RECOVER_REG_DIR — a single `jq` read of the blocked
# pane's row to resolve cwd/account/session_id) and has `rm -f` sites, so section-3 flags it — but BOTH
# sites (the re-fire-FAILED path, which exits 5 preserving the blocked pane, and the success path after
# the announce) remove the SAME thing: its own `mktemp` reworded-brief file $REWORDED, scaffolding handed
# to handoff-fire --prompt-file and consumed within the run. Exactly the handoff-fire.sh / cc-value
# temp-scaffold shape declared above. It never deletes a registry row, and it is not an age reaper at
# all — no -mmin / -mtime / RETAIN_H / CC_SUP_GC_S, so sections 1/1b/2/2b find nothing to bound. The
# durable evidence of a recovery is the re-fired session's transcript + its new registry row + the
# announce to the originator, none of which this script can touch. Declared = reviewed (2026-07-25
# infra-perfection pass; line refs :40/:59/:110/:145/:173 replaced by symbols and the claim re-verified
# against live code 2026-08-08 — they were still ACCURATE, and are gone anyway, because the neighbouring
# lead-crash-watchdog entry proves accuracy today buys ~9 days, not durability).
# Declared reapers. A file here is one whose deletion sites have been READ and whose horizons the
# scorers above can actually see — never a file listed merely to silence §3 (see 1b).
#   hooks/dispatch-assert.sh  its state sweep is `-mtime +7` = 604800s, scored by §1b. Its other
#                             `rm -f "$PENDING"` sites are obligation-state discharge — kill-switch,
#                             pending-corrupt, discharged, AND capped (`p_count >= MAX`, the arm this
#                             entry omitted until 2026-08-08; a COUNT cap, so still not age reaping).
#                             The class claim was right and the enumeration was short, which is the
#                             failure mode of listing instances instead of naming the class
#                             (memory: denylist-enumerates-spellings-not-the-class).
#   scripts/desk-invariant.sh STALE_MARKER_MAX_AGE_S 604800s, scored by §1c, and the deletion it bounds
#                             is sweep_stale_markers()'s `rm -f "$f"` over $STATE_DIR/paged-*-stale.marker
#                             — gated on `now - mtime > STALE_MARKER_MAX_AGE_S`, so the horizon and the
#                             reaping site are the same mechanism. Its OTHER rm sites are not evidence:
#                             the `rm -f "$tmp"` pair is temp scaffold on a failed `mv -f`, and the
#                             `rm -rf "${d:-}"` is the --selftest EXIT trap over its own `mktemp -d`
#                             sandbox. (Until 2026-08-08 this entry said only "its other rm -f $tmp
#                             sites are temp scaffold" — which described the scaffold and never named
#                             the actual reaping site, leaving a reader unable to connect the declared
#                             horizon to the code it bounds.)
#   bin/cc-await-ping         NOT an age reaper: `rm -f` of its OWN watchfile in an EXIT trap and on
#                             wake — self-owned lifecycle, no horizon (same class as the
#                             bin/cc-recover-safeguard declaration in 8195561a).
#   bin/cc-queue              NOT a reaper at all. It READS CC_TELEMETRY_DIR (:77) and
#                             CC_REGISTRY_DIR (:78) to render the operator's queue and never
#                             deletes a row — the evidence spine is only ever CONSUMED here. Its
#                             SINGLE `rm -f` (:440) lives inside `--selftest` and clears a fixture
#                             heartbeat under that selftest's own `mktemp -d` sandbox ($tmp/pend),
#                             the handoff-fire.sh / cc-value temp-scaffold shape declared above —
#                             it cannot name a path outside that sandbox. No -mmin / -mtime /
#                             RETAIN_H / MARKER_MAX_AGE_S / CC_SUP_GC_S, so §1/1b/1c/2/2b find
#                             nothing to bound. Declared = reviewed (2026-07-31; the land of
#                             57e16249 is what made §3 fire).
# scripts/cc-gc.sh          — the GC franchise driver. READS CC_REGISTRY_DIR as its liveness roster
#                             and never deletes a registry row; §3 flags it for owning `rm`. It IS a
#                             genuine age reaper and belongs here on the merits. What it reaps is
#                             per-session LITTER, never supervisor evidence: fully-acked dead
#                             mailbox boxes (MBX_DAYS, 7 d = 604,800 s, 100× the 6,000 s floor),
#                             watchdog .pid/.id pairs behind an identity pin (WD_AGE_S, 2 d =
#                             172,800 s, 28× the floor), and abandoned mkbox lock dirs. Its two
#                             evidence-bearing cases deliberately do NOT delete — a dead box with
#                             UNACKED lines is ARCHIVED to mailbox/archive/ at MBX_STRAND_DAYS
#                             (30 d), because unacked mail in a dead box is the proof the comms
#                             layer dropped a message, and a `.forward` tombstone is never removed
#                             at all so a forward chain stays resolvable. Liveness (a registry row
#                             with a live pid, or a role pointer) outranks age in every adapter, and
#                             the driver is DRY-RUN by default — `APPLY=0` until `--apply` is
#                             passed, so no scheduled invocation deletes without that flag.
#                             Declared = reviewed (2026-08-12 GC-franchise re-land; backlog
#                             6cab0ab3cb2f).
# hooks/lib/peer-owned.sh   — NOT a reaper. It READS CC_REGISTRY_DIR twice and owns four `rm -f`, so
#                             §3 flags it; every one of the four is the SAME temp scaffold. Both
#                             _po_dirt_predates_session and the exec-window term capture
#                             `git status --porcelain -z -uall` into their own `mktemp` file
#                             (po-porc.XXXXXX / po-exec.XXXXXX) because a command substitution would
#                             strip the NUL delimiters, and each removes that file on the capture's
#                             failure path and again after consuming it in the same function — the
#                             handoff-fire.sh / cc-value / context-econ.sh scaffold shape declared
#                             above. Its two registry touches are READS and only reads:
#                             _po_session_start jq's the row for `startedAt`, and _po_live_peer runs
#                             ONE jq over the whole roster to find a live peer. It writes no row and
#                             deletes no row — the evidence spine is only ever CONSUMED here. No
#                             -mmin / -mtime / RETAIN_H / MARKER_MAX_AGE_S / CC_SUP_GC_S anywhere, so
#                             §1/1b/1c/2/2b find nothing to bound. (Its one RETAIN_H mention is a
#                             COMMENT about the registry's OWN 24 h forensics retention — a horizon
#                             this file observes, never sets.) Declared = reviewed (2026-08-13 W4
#                             drain; backlog 412de404ecac — this file is why the gate was RED on a
#                             pristine origin/main, on two independent trees).
# scripts/deathwatch-watchfile.sh
#                           — NOT a reaper. The L1 death-watch PRODUCER (backlog ed6d0716caa7 /
#                             0328e7cc5742, landed 2026-08-12): it derives lead-deathwatch's
#                             watch-file from the registry. §3 flags it for reading CC_REGISTRY_DIR
#                             and owning one `rm -f`. The read is its INPUT roster — it iterates
#                             "$REG_DIR"/*.json read-only and fail-CLOSED (exit 3 when the dir is
#                             unreadable, deliberately, so a registry that blinks for one tick can
#                             never truncate a good watch-file); it creates and deletes no row. The
#                             single `rm -f` is an EXIT trap over its own `mktemp` staging file
#                             (deathwatch-wl.XXXXXX) that the watch-list is built in and published
#                             from by `mv -f`, with the trap disarmed on the successful publish —
#                             the atomic-write scaffold declared above, in its mv-or-trap spelling.
#                             It sets no horizon constant at all, so §1/1b/1c/2/2b find nothing to
#                             bound. Declared = reviewed (2026-08-13 W4 drain; backlog 412de404ecac).
# ── ANCHORS: the load-bearing symbol of each justification, re-checked by §5 every run ────────────
# Form: `# @anchor <path> <ERE>`. One per claim a reader would have to find code for. §5 fails if an
# anchor stops matching CODE in its file — i.e. if the justification above now describes something
# that moved, was renamed, or is gone. This is what makes "Declared = reviewed" a claim the gate
# re-checks rather than a sentence someone wrote once.
# ⚠️ COVERAGE IS PARTIAL AND DELIBERATELY STATED: anchors exist for the four entries re-verified
# against live code on 2026-08-08 (item 74a0896ee989), plus scripts/cc-gc.sh, anchored at its
# 2026-08-12 re-land. The older declarations above are NOT anchored
# and are NOT asserted to be current — add an anchor when you next re-verify one. A comment claiming
# coverage it does not have is the defect this gate exists to prevent, so it is claimed narrowly.
# @anchor hooks/dispatch-assert.sh mtime \+7
# @anchor hooks/dispatch-assert.sh rm -f "\$PENDING"
# @anchor scripts/desk-invariant.sh sweep_stale_markers
# @anchor scripts/desk-invariant.sh STALE_MARKER_MAX_AGE_S
# @anchor bin/cc-recover-safeguard REWORDED
# @anchor hooks/lead-crash-watchdog.sh gc_teardown_marker
# @anchor hooks/lead-crash-watchdog.sh sid\.daemon
# @anchor scripts/cc-gc.sh MBX_STRAND_DAYS
# @anchor scripts/cc-gc.sh MBX_DIR/archive
# @anchor scripts/cc-gc.sh WD_AGE_S
# @anchor scripts/cc-gc.sh ^APPLY=0
# @anchor hooks/lib/peer-owned.sh po-porc\.XXXXXX
# @anchor hooks/lib/peer-owned.sh po-exec\.XXXXXX
# @anchor hooks/lib/peer-owned.sh _po_live_peer
# @anchor scripts/deathwatch-watchfile.sh deathwatch-wl\.XXXXXX
# @anchor scripts/deathwatch-watchfile.sh ^REG_DIR=
DECLARED='bin/cc-context bin/cc-board bin/cc-sessions bin/cc-notify bin/cc-reaper bin/cc-value bin/cc-reconcile bin/cc-recover-safeguard hooks/session-register.sh hooks/session-deregister.sh statusline.sh scripts/lead-supervisor.sh scripts/lead-reconciler.sh hooks/waiting-recycle.sh scripts/handoff-fire.sh hooks/lead-crash-watchdog.sh scripts/scratchpad-reaper.sh hooks/lib/context-econ.sh hooks/dispatch-assert.sh scripts/desk-invariant.sh bin/cc-await-ping bin/cc-queue scripts/cc-gc.sh hooks/lib/peer-owned.sh scripts/deathwatch-watchfile.sh'

viol=0
say(){ printf '  %s\n' "$1"; }
bad(){ printf '  ⛔ %s\n' "$1"; viol=$((viol+1)); }
# A grep -rn hit is "file:line:content" — so a naive `grep -v '^#'` never matches, and the lint would
# read COMMENTS as code. (It did: the comment in cc-context explaining the OLD `-mmin +360` was scored
# as a live horizon. A comment documenting the old BAD value would then fail the gate spuriously.) Strip
# the prefix and test the actual source line. A check must observe the thing it guards, not prose about it.
is_comment(){ case "$(printf '%s' "${1#*:*:}" | sed 's/^[[:space:]]*//')" in '#'*) return 0 ;; *) return 1 ;; esac; }

echo "reaper-horizon-lint: floor = ${SUPERVISOR_SWEEP_MAX_S}s sweep × ${SAFETY} = ${MIN_HORIZON_S}s"

# ── 1. every find-based deletion horizon on an evidence artifact ──────────────────────────────────
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
  is_comment "$hit" && continue
  mins=$(printf '%s' "$hit" | sed -nE 's/.*-mmin \+([0-9]+).*/\1/p')
  [ -n "$mins" ] || continue
  secs=$(( mins * 60 ))
  if [ "$secs" -lt "$MIN_HORIZON_S" ]; then
    bad "$f:$ln  horizon ${secs}s (-mmin +$mins) < floor ${MIN_HORIZON_S}s — a supervisor would MISS this evidence"
  else
    say "ok  $f:$ln  horizon ${secs}s"
  fi
done < <(grep -rnE -- '-mmin \+[0-9]+' $DECLARED 2>/dev/null)

# ── 1b. DAY-granularity find horizons (`-mtime +N`) ───────────────────────────────────────────────
# §1 scores only `-mmin +N`. A reaper written with `-mtime +N` — the same `find` deletion, expressed
# in days — was invisible to every scorer, so such a file could only ever be caught by §3 as
# "undeclared", and DECLARING it would then silence §3 without any scorer ever reading its horizon.
# That is a rubber stamp: an allowlist entry that makes the file pass BY BEING LISTED rather than by
# being checked, which is functionally a deleted check (memory: miscalibrated-check-is-a-deleted-check).
# Scoring the day form is what makes a declaration mean something.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
  is_comment "$hit" && continue
  days=$(printf '%s' "$hit" | sed -nE 's/.*-mtime \+([0-9]+).*/\1/p')
  [ -n "$days" ] || continue
  secs=$(( days * 86400 ))
  if [ "$secs" -lt "$MIN_HORIZON_S" ]; then
    bad "$f:$ln  horizon ${secs}s (-mtime +$days) < floor ${MIN_HORIZON_S}s — a supervisor would MISS this evidence"
  else
    say "ok  $f:$ln  horizon ${secs}s (-mtime +$days)"
  fi
done < <(grep -rnE -- '-mtime \+[0-9]+' $DECLARED 2>/dev/null)

# ── 1c. seconds-style MARKER age horizons ─────────────────────────────────────────────────────────
# Same argument as 1b for a reaper that computes `now - mtime` in shell against a seconds constant
# instead of delegating to find. desk-invariant.sh's stale-damping-marker sweep is this shape.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
  is_comment "$hit" && continue
  secs=$(printf '%s' "$hit" | sed -nE 's/.*MARKER_MAX_AGE_S:-([0-9]+).*/\1/p')
  [ -n "$secs" ] || continue
  if [ "$secs" -lt "$MIN_HORIZON_S" ]; then
    bad "$f:$ln  marker horizon ${secs}s < floor ${MIN_HORIZON_S}s — a supervisor would MISS this evidence"
  else
    say "ok  $f:$ln  marker horizon ${secs}s"
  fi
done < <(grep -rnE 'MARKER_MAX_AGE_S:-[0-9]+' $DECLARED 2>/dev/null)

# ── 2. retention-hour style horizons (the registry) ───────────────────────────────────────────────
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
  is_comment "$hit" && continue
  hrs=$(printf '%s' "$hit" | sed -nE 's/.*RETAIN_H:-([0-9]+).*/\1/p')
  [ -n "$hrs" ] || continue
  secs=$(( hrs * 3600 ))
  if [ "$secs" -lt "$MIN_HORIZON_S" ]; then
    bad "$f:$ln  retention ${secs}s (${hrs}h) < floor ${MIN_HORIZON_S}s"
  else
    say "ok  $f:$ln  retention ${secs}s (${hrs}h)"
  fi
done < <(grep -rnE 'RETAIN_H:-[0-9]+' $DECLARED 2>/dev/null)

# ── 2b. seconds-style GC horizons (the supervisor's telemetry GC, item fdc101e8b0c7) ──────────────
# lead-supervisor.sh's gc_stale drops telemetry rows past CC_SUP_GC_S seconds. Bound it exactly like the
# -mmin (§1) and RETAIN_H (§2) horizons: a GC shorter than the slowest sweep ×10 would delete the evidence
# a supervisor needs BEFORE it can sweep for it — the blindness this lint exists to forbid.
while IFS= read -r hit; do
  [ -n "$hit" ] || continue
  f="${hit%%:*}"; rest="${hit#*:}"; ln="${rest%%:*}"
  is_comment "$hit" && continue
  secs=$(printf '%s' "$hit" | sed -nE 's/.*CC_SUP_GC_S:-([0-9]+).*/\1/p')
  [ -n "$secs" ] || continue
  if [ "$secs" -lt "$MIN_HORIZON_S" ]; then
    bad "$f:$ln  GC horizon ${secs}s (CC_SUP_GC_S) < floor ${MIN_HORIZON_S}s — a supervisor would MISS this evidence"
  else
    say "ok  $f:$ln  GC horizon ${secs}s (CC_SUP_GC_S)"
  fi
done < <(grep -rnE 'CC_SUP_GC_S:-[0-9]+' $DECLARED 2>/dev/null)

# ── 3. FAIL-CLOSED on an UNDECLARED reaper ────────────────────────────────────────────────────────
# A new file that both touches an evidence artifact AND deletes is a reaper nobody reviewed. Without
# this, the lint has a false-negative hole — and a detector with a blind spot is the bug it exists to
# prevent (audit §3i). Add the file to $DECLARED and justify its horizon.
#
# BOTH legs observe CODE, never prose. §1/§2 strip comment hits with is_comment(); §3 could not,
# because `grep -rl` yields a bare filename with no line to test — so a file whose ONLY tie to an
# evidence artifact was a comment MENTIONING cc-registry was convicted as an undeclared reaper. That
# is exactly the defect this file documents at is_comment() ("a check must observe the thing it
# guards, not prose about it"), surviving in the one section that could not reach the helper. It
# fired on hooks/session-continue.sh:472 and hooks/lib/mailbox-pending.sh:526 — both comments — and
# the remedy it PRESCRIBED (declare them) would have recorded two non-reapers as reviewed reapers,
# diluting the very list §1/§2 scan for horizons. `grep -rn` makes the helper reachable. This opens
# no false-NEGATIVE hole: a file whose only reference to an evidence artifact is a comment does not
# touch that artifact at all, and a `rm -f` that is itself commented out deletes nothing.
# AND BOTH LEGS OBSERVE THE TARGET, not merely that a delete exists. The conjunction above is over
# the FILE (touches evidence ∧ deletes somewhere), never over what the delete REMOVES — so a script
# that merely READS ~/.claude/cc-registry and separately cleans up its own `mktemp` scratch file is
# convicted as an unreviewed reaper. Measured 2026-08-13 (item 412de404ecac): that was the whole of
# §3's standing red on pristine origin/main, on two independent trees —
# hooks/lib/peer-owned.sh (`rm -f "$porcf"`, porcf from mktemp at :405 and :587) and
# scripts/deathwatch-watchfile.sh (`trap 'rm -f "$tmp"' EXIT`, tmp from mktemp at :79). Neither
# deletes anything anyone could call evidence, and a permanently-red safety gate is a gate nobody
# reads — the exact condition 48850a3b2 was written to end for four other reapers.
#
# 🚨 THE REMEDY THE ITEM PRESCRIBED — declare them — IS THE DEFECT, and this file already says so 20
# lines up about the comment case: declaring a non-reaper "would have recorded two non-reapers as
# reviewed reapers, diluting the very list §1/§2 scan for horizons". Same defect one level deeper.
# The earlier fix taught leg 1 to observe code instead of prose; leg 2 still observed only that a
# delete EXISTS. A declaration is a REVIEW claim, so declaring a file with nothing to review is not
# a cheaper fix, it is a false entry in the list every other section trusts.
#
# FAIL-CLOSED, and that direction is deliberate. A site is exonerated ONLY when every path it names
# resolves to a variable this same file assigns from `mktemp`. A literal path, an unattributable
# variable, or a delete naming no variable at all still convicts. A real reaper cannot slip through:
# it deletes something it did not create, so it has at least one site this cannot attribute.
self_created_delete(){   # $1 = file · $2 = one comment-stripped delete line → 0 iff pure self-cleanup
  local vars v
  vars="$(printf '%s\n' "$2" | grep -oE '\$\{?[A-Za-z_][A-Za-z0-9_]*' | sed -E 's/^\$\{?//' | sort -u)"
  [ -n "$vars" ] || return 1
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    grep -qE "^[[:space:]]*(local[[:space:]]+|export[[:space:]]+)?$v=[^=]*mktemp" "$1" || return 1
  done <<EOF
$vars
EOF
  return 0
}
has_code_delete(){
  local ln
  while IFS= read -r ln; do
    [ -n "$ln" ] || continue
    self_created_delete "$1" "$ln" && continue
    return 0
  done < <(grep -nE -- '-delete|rm -f' "$1" 2>/dev/null \
             | sed -E 's/^[0-9]+://; s/^[[:space:]]*//' | grep -vE '^#')
  return 1
}
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case " $DECLARED " in *" $f "*) continue ;; esac
  has_code_delete "$f" || continue
  bad "$f  UNDECLARED reaper on an evidence artifact — declare it in \$DECLARED and justify its horizon"
done < <(grep -rnE "$EVIDENCE_GREP" bin hooks scripts statusline.sh 2>/dev/null \
           | grep -vE '^[^:]*(e2e|lint)' \
           | while IFS= read -r h; do is_comment "$h" || printf '%s\n' "${h%%:*}"; done | sort -u)

# ── 4. the supervisor, once it exists, must not re-declare the sweep interval ─────────────────────
if [ -f scripts/lead-supervisor.sh ]; then
  if grep -qE 'SUPERVISOR_SWEEP_MAX_S' scripts/lead-supervisor.sh 2>/dev/null; then
    say "ok  lead-supervisor.sh sources the shared sweep constant"
  else
    bad "scripts/lead-supervisor.sh exists but does NOT source SUPERVISOR_SWEEP_MAX_S — two copies of the constraint WILL drift (invariant 7)"
  fi
fi

# ── 5. every declaration's ANCHOR must still resolve ──────────────────────────────────────────────
# §1-§2b bound the horizons they can SEE, and §3 catches an undeclared reaper. Nothing checked the
# other half of a declaration: the JUSTIFICATION — the prose a future author reads to decide whether
# their new `rm` is safe. It rotted silently. The lead-crash-watchdog entry carried five line numbers,
# was hand-re-derived once on 2026-07-29, and all five had drifted again nine days later across three
# unrelated commits to the subject; the desk-invariant entry described its temp scaffold and never
# named the site its own declared horizon bounds. Both files passed every section, every run, because
# "declared" was tested and "justified" was not — an allowlist entry that passes BY BEING LISTED,
# which §1b's header already names as functionally a deleted check.
#
# So each load-bearing claim is pinned as a `# @anchor <path> <ERE>` above and re-checked here. Matched
# against CODE only (is_comment), for the reason §1/§2/§3 are: a check must observe the thing it guards,
# not prose about it — an anchor satisfied by a comment MENTIONING the symbol would re-open exactly the
# hole §3's header documents. Line numbers are deliberately not an anchor form: they are the one form
# guaranteed to move on an edit that changes nothing the justification claims.
while IFS= read -r spec; do
  [ -n "$spec" ] || continue
  af="${spec%% *}"; ape="${spec#* }"
  if [ -z "$af" ] || [ "$af" = "$ape" ]; then
    bad "malformed @anchor (want '<path> <ERE>'): $spec"; continue
  fi
  case " $DECLARED " in
    *" $af "*) ;;
    *) bad "$af  @anchor names a file absent from \$DECLARED — anchor and declaration have diverged"; continue ;;
  esac
  if [ ! -f "$af" ]; then
    bad "$af  @anchor names a file that no longer exists — its declaration describes code that is gone"; continue
  fi
  hit=0
  while IFS= read -r h; do
    is_comment "$af:$h" && continue
    hit=1; break
  done < <(grep -nE -- "$ape" "$af" 2>/dev/null)
  if [ "$hit" -eq 1 ]; then
    say "ok  $af  anchor /$ape/ resolves"
  else
    bad "$af  anchor /$ape/ NO LONGER RESOLVES IN CODE — the declaration above describes code that moved, was renamed, or is gone. Re-read that file's deletion sites and correct the justification (do not just delete the anchor)."
  fi
done < <(sed -nE 's/^# @anchor[[:space:]]+(.+)$/\1/p' "$SELF")

if [ "$viol" -gt 0 ]; then
  echo "reaper-horizon-lint: ⛔ $viol violation(s). A reaper shorter than the sweep interval makes its"
  echo "  evidence invisible to the supervisor — which then reports health into a fire."
  exit 1
fi
echo "reaper-horizon-lint: clean — every evidence horizon outlives the supervisor's slowest sweep"
