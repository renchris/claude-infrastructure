#!/usr/bin/env bash
# THE GATE -- the load-bearing mechanism. Emits the evidence block or a structured abstention.
# Terminal states: PROVED | ABSTAINED(<reason>) | REJECTED(-> iterate, max 8)
# RECONSTRUCTED from robobun's published output shape (187/200 sampled PRs carry the block).
set -euo pipefail
BASE=$(cat .gate/base-sha)
TESTS=("$@")                       # test files the agent claims prove the fix
OUT=.gate/evidence.md
MARK=${MARK:-acme}
FENCE='```'                        # kept in a var: a literal fence inside a single-quoted
                                   # printf format reads as command substitution to shellcheck

# 1. FAILS ON MAIN. Replay the PRISTINE pre-fix tree from git -- never a hand-edited
#    approximation, or the RED-proof passes vacuously and proves nothing.
rm -rf /tmp/prefix && mkdir -p /tmp/prefix
git archive "$BASE" | tar -x -C /tmp/prefix
for t in "${TESTS[@]}"; do mkdir -p "/tmp/prefix/$(dirname "$t")"; cp "$t" "/tmp/prefix/$t"; done
FAIL_OUT=$( cd /tmp/prefix && build --profile=debug --asan && run-tests "${TESTS[@]}" 2>&1; echo "rc=$?" )

# 2. PASSES ON PR
PASS_OUT=$( build --profile=debug --asan && run-tests "${TESTS[@]}" 2>&1; echo "rc=$?" )

# 3. Verdict. A gate that could not RUN is a THIRD state, never a pass.
if   ! grep -q 'rc=' <<<"$FAIL_OUT$PASS_OUT"; then verdict=COULD_NOT_RUN
elif grep -q 'rc=0' <<<"$FAIL_OUT"; then verdict=REJECTED   # test passes WITHOUT the fix => invalid test
elif grep -q 'rc=0' <<<"$PASS_OUT"; then verdict=PROVED
else verdict=REJECTED; fi
[ "$verdict" = PROVED ] || { echo "$verdict"; exit 1; }

ITER=$(cat .gate/iteration); PASSED=$(cat .gate/passed); REJ=$(cat .gate/rejected)
NFILES=$(git diff --name-only "$BASE" | wc -l | tr -d ' ')

# 4. Emit in robobun's exact published shape.
{
  echo "<!-- ${MARK}:evidence:begin -->"; echo; echo '---'; echo
  echo "**[${GATE_NAME:-review}]** gate passed · iteration ${ITER} · ${NFILES} files touched"; echo
  printf '<details><summary>fails on main (without fix)</summary>\n\n%sconsole\n%s\n%s\n\n</details>\n\n' "$FENCE" "$FAIL_OUT" "$FENCE"
  printf '<details><summary>passes on PR (with fix)</summary>\n\n%sconsole\n%s\n%s\n\n</details>\n\n' "$FENCE" "$PASS_OUT" "$FENCE"
  printf '<details><summary>diff hotspot</summary>\n\n%s\n%s\n%s\n\n</details>\n\n' "$FENCE" "$(git diff --stat "$BASE")" "$FENCE"
  echo "**gate history** · ${PASSED} passed · ${REJ} rejected · iteration ${ITER}"; echo
  printf '<details><summary>evidence per changed file</summary>\n\n%s\n%s\n%s\n\n</details>\n\n' "$FENCE" "$(./worker/telemetry.sh)" "$FENCE"
  echo "<!-- ${MARK}:evidence:end -->"
} > "$OUT"
echo PROVED
