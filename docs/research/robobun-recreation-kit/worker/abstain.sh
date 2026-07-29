#!/usr/bin/env bash
# Structured abstention -- a FIRST-CLASS outcome, publicly declared. 88/200 of robobun's
# sampled PRs take this path. REASON must come from gate/abstention-reasons.txt.
set -euo pipefail
: "${REASON:?}"; MARK=${MARK:-acme}; ITER=$(cat .gate/iteration)
grep -qF "${REASON%%:*}" gate/abstention-reasons.txt || { echo "error: reason not in closed vocabulary"; exit 1; }
{ echo "<!-- ${MARK}:evidence:begin -->"; echo; echo '---'; echo
  echo "**no test proof** · iteration ${ITER} · ${REASON}"; echo
  echo "<!-- ${MARK}:evidence:end -->"; } > .gate/evidence.md
