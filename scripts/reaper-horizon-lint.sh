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
DECLARED='bin/cc-context bin/cc-board bin/cc-sessions bin/cc-notify bin/cc-reaper bin/cc-value bin/cc-reconcile hooks/session-register.sh hooks/session-deregister.sh statusline.sh scripts/lead-supervisor.sh scripts/lead-reconciler.sh hooks/waiting-recycle.sh scripts/handoff-fire.sh'

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
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case " $DECLARED " in *" $f "*) continue ;; esac
  grep -qE -- '-delete|rm -f' "$f" 2>/dev/null || continue
  bad "$f  UNDECLARED reaper on an evidence artifact — declare it in \$DECLARED and justify its horizon"
done < <(grep -rlE "$EVIDENCE_GREP" bin hooks scripts statusline.sh 2>/dev/null | grep -vE 'e2e|lint')

# ── 4. the supervisor, once it exists, must not re-declare the sweep interval ─────────────────────
if [ -f scripts/lead-supervisor.sh ]; then
  if grep -qE 'SUPERVISOR_SWEEP_MAX_S' scripts/lead-supervisor.sh 2>/dev/null; then
    say "ok  lead-supervisor.sh sources the shared sweep constant"
  else
    bad "scripts/lead-supervisor.sh exists but does NOT source SUPERVISOR_SWEEP_MAX_S — two copies of the constraint WILL drift (invariant 7)"
  fi
fi

if [ "$viol" -gt 0 ]; then
  echo "reaper-horizon-lint: ⛔ $viol violation(s). A reaper shorter than the sweep interval makes its"
  echo "  evidence invisible to the supervisor — which then reports health into a fire."
  exit 1
fi
echo "reaper-horizon-lint: clean — every evidence horizon outlives the supervisor's slowest sweep"
