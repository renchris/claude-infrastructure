#!/usr/bin/env bats
# lr-predicate-cwd — scripts/limit-recover/lr-predicate.sh must not import from its caller's cwd
# (LR sustained-load W0b, the second site of G2 review C1).
#
# `python3 -c` puts the cwd at sys.path[0], ahead of the stdlib, and the predicate's first line is
# `import json`. hooks/stop-failure-marker.sh calls it (is-teammate-head) with the capped session's
# cwd, so a json.py sitting there ran inside the predicate. The cure is `/usr/bin/python3 -I`.
#
# WHAT THIS PINS:
#   · NO HIJACK. A planted json.py in the cwd that writes a marker: the marker exists before the
#     fix and is absent after.
#   · THE VERDICT STILL COMES BACK. The same run prints {"teammate":false}, so the cure cannot pass
#     by breaking the predicate (a predicate that never runs also never imports the planted file).
#   · THE PLANT IS LIVE. A control imports json from that cwd and sees the marker, so the first
#     test cannot pass on an inert plant.
#
# Hermetic: HOME, TMPDIR and the limit-recover state dirs live in BATS_TEST_TMPDIR.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LRP="$REPO/scripts/limit-recover/lr-predicate.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"; mkdir -p "$TMPDIR"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lrstate" LR_RECON_ROOT="$BATS_TEST_TMPDIR/lrstate/recon"
  unset PYTHONPATH LR_PREDICATE_PY
  CWD="$BATS_TEST_TMPDIR/session-cwd"; mkdir -p "$CWD"
  HIJACK="$BATS_TEST_TMPDIR/hijacked"
  printf 'open(%s, "w").write("hijacked\\n")\n' "'$HIJACK'" > "$CWD/json.py"
  TX="$BATS_TEST_TMPDIR/tx/a.jsonl"; mkdir -p "$(dirname "$TX")"
  printf '%s\n' '{"type":"user","message":{"role":"user","content":"hi"}}' > "$TX"
}

@test "a json.py planted in the caller's cwd is not imported by the predicate, and the verdict still comes back" {
  cd "$CWD"
  run /bin/bash "$LRP" is-teammate-head "$TX"
  # RED before the fix: the planted module ran, and the predicate it hijacked failed.
  [ ! -e "$HIJACK" ]
  [ "$status" -eq 0 ]
  [ "$output" = '{"teammate":false}' ]
}

@test "control: the planted module is live — imported from that cwd, it does write the marker" {
  cd "$CWD"
  run /usr/bin/python3 -c 'import json'
  [ -e "$HIJACK" ]
}
