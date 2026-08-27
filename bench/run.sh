#!/usr/bin/env bash
# Run the whole design-review perception pipeline over the ground-truth corpus.
#
# Exit code is the false-positive gate's, not a summary of the run: 0 means zero
# findings on the clean control and zero unbudgeted collateral, which is the
# precondition for any other number here meaning anything.
#
#   bash bench/run.sh                     # rebuild, capture, detect, route, gate
#   BENCH_CHROMIUM=/path/to/chrome ...    # use a pre-provisioned browser
#   PROFILE=reso-landing-app ...          # route under a different app's weightings
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
OUT=corpus/out
PROFILE=${PROFILE:-corpus}
DPR=${DPR:-1,1.5}

step() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

step "corpus"
python3 corpus/build_corpus.py "$OUT" | tail -2
# NB: no `| head -N` anywhere below. head closes the pipe on its Nth line, the
# producer dies of SIGPIPE mid-report, and under `set -o pipefail` the run aborts
# with a traceback that looks like a detector crash. Measured here on stage 3.

step "capture (dpr $DPR)"
python3 capture.py "$OUT" --dpr "$DPR"

step "deterministic rules"
python3 detect_dom.py "$OUT"

step "cross-check (DOM vs pixels)"
python3 detect_xcheck.py "$OUT"

step "abstention router (profile: $PROFILE)"
python3 route_abstain.py "$OUT" --profile "$PROFILE" --crops

# The gate runs LAST and its status is the script's. Anything above it can print a
# pleasing summary while a rule is firing on the control; only this decides.
step "false-positive budget"
python3 fp_budget.py "$OUT"
