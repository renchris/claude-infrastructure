#!/bin/bash
# Runs both P1 runs back to back, each blocking in run-p1.sh's own preflight.
#
# The bars here are the FALLBACK bars declared in P-probes.md BEFORE any run, not a quiet
# loosening: `cc_sp_active <= 4` and CPU idle >= 25%. They are legitimate because the
# addendum's rule is asymmetric and applies at INTERPRETATION time — a survivors==0 result
# stands at any load (and stands more strongly the busier the box was), while survivors>0
# below the 40% bar licenses nothing and is re-run on a quiet box with both readings printed
# side by side. Every run records uptime + CPU idle before and after regardless.
#
# It never overrides the fleet's admission gate. Waiting IS the gate's own prescribed remedy
# ("let the running turns finish… shed first, then spawn").
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROBE_PREFLIGHT_WAIT_S="${PROBE_PREFLIGHT_WAIT_S:-5400}"
export PROBE_MAX_ACTIVE="${PROBE_MAX_ACTIVE:-4}"
export PROBE_MIN_IDLE_PCT="${PROBE_MIN_IDLE_PCT:-25}"
for r in "${@:-run1 run2}"; do :; done
for r in ${*:-run1 run2}; do
  echo "=== $(date -u +%Y-%m-%dT%H:%M:%SZ) starting $r ==="
  "$HERE/run-p1.sh" "$r"; echo "=== $r exited $? ==="
done
