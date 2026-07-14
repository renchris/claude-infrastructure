#!/bin/bash
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
DECLARED='bin/cc-context bin/cc-board bin/cc-sessions bin/cc-notify hooks/session-register.sh hooks/session-deregister.sh statusline.sh'

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
