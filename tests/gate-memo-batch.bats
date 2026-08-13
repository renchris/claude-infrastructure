#!/usr/bin/env bats
# gate-memo-batch.bats — the BATCH per-file memo in scripts/lib/gate-memo.sh (backlog c4d65e8933e1).
#
# WHY A BATCH API AT ALL, in one line: the per-file API it sits beside costs 16.8 ms per lookup and
# the checks it was about to be rolled onto cost 18.5-19.5 ms per file, so copying the proven
# pattern onto them would have paid 17 to save 19. Hashing the population in ONE fork takes the
# lookup to 0.33 ms/file. The full measurement is in gate-memo.sh's own header.
#
# WHAT IS PINNED HERE IS THE FAILURE DIRECTION, never the speed. A memo that returns a green it did
# not earn is strictly worse than the 28s it saves (repo memory: gate-default-decides-failure-
# direction), and this API adds exactly one new way to do that: it is INDEX-KEYED, so a batch that
# came back short would slide every later verdict onto the wrong file. That control gets its own
# case AND its own mutant below.
#
# EVERY CONTROL HERE IS MUTATED. A case that passes against the unmutated library proves nothing on
# its own — it has to be shown able to FAIL (repo memory: verification-harness-vacuous-pass-traps,
# per-site-mutation-attributes-coverage). `mutate` asserts its own precondition, because a mutation
# that never applied reads exactly like a blind test.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"          # hermeticity: never the operator's live ~
  mkdir -p "$HOME"

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LIB="$REPO/scripts/lib/gate-memo.sh"

  # A repo of its own: memo_init refuses on a dirty worktree, so a test run against $REPO would go
  # silently memo-OFF for anyone with an edit in flight — passing while asserting nothing.
  FIX="$BATS_TEST_TMPDIR/fix"
  mkdir -p "$FIX"
  cd "$FIX" || exit 1
  git init -q .
  git config user.email tester@example.com
  git config user.name tester
  for i in 1 2 3 4 5; do printf 'content %s\n' "$i" > "f$i.sh"; done
  git add -A
  git -c user.email=tester@example.com -c user.name=tester commit -qm init
}

# mutate <sed-expr-from> <sed-expr-to> — copy the library, apply ONE textual mutation, and REFUSE
# unless it applied exactly once. Prints the mutant's path.
mutate() {
  local from="$1" to="$2" out="$BATS_TEST_TMPDIR/mutant-$RANDOM.sh" n
  n="$(grep -cF -- "$from" "$LIB")"
  [ "$n" -eq 1 ] || { echo "MUTATOR PRECONDITION FAILED: '$from' matched $n times, need exactly 1" >&2; return 1; }
  python3 - "$LIB" "$out" "$from" "$to" <<'PY'
import sys
src, dst, frm, to = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
s = open(src).read()
assert s.count(frm) == 1, f"expected 1 occurrence, found {s.count(frm)}"
open(dst, "w").write(s.replace(frm, to))
PY
  printf '%s\n' "$out"
}

# drive <lib> <script-body> — source a library and run a body against the fixture repo.
drive() {
  local lib="$1" body="$2"
  bash -c '. "$1" || exit 90; shift; eval "$1"' _ "$lib" "$body"
}

@test "arm succeeds on a clean tree and returns one blob per path" {
  run drive "$LIB" '
    memo_init || { echo "INIT-REFUSED"; exit 1; }
    memo_batch_arm ck f1.sh f2.sh f3.sh f4.sh f5.sh || { echo "ARM-REFUSED"; exit 1; }
    echo "OK=$MEMO_B_OK BLOBS=${#MEMO_B_BLOBS[@]}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK=1 BLOBS=5"* ]]
}

@test "a hit is returned only for content already recorded" {
  run drive "$LIB" '
    memo_init && memo_batch_arm ck f1.sh f2.sh f3.sh || exit 1
    memo_batch_hit 0 && { echo "PRE-RECORD-HIT"; exit 1; }   # the control: it must be able to say no
    memo_batch_record 0
    memo_batch_hit 0 || { echo "POST-RECORD-MISS"; exit 1; }
    memo_batch_hit 1 && { echo "UNRECORDED-INDEX-HIT"; exit 1; }
    echo CLEAN'
  [ "$status" -eq 0 ]
  [[ "$output" == *CLEAN* ]]
}

@test "changed content misses — the verdict is keyed on bytes, not on the path" {
  run drive "$LIB" '
    memo_init && memo_batch_arm ck f1.sh f2.sh || exit 1
    memo_batch_record 0
    memo_batch_hit 0 || { echo "SETUP-MISS"; exit 1; }
    printf "mutated\n" > f1.sh
    memo_init && memo_batch_arm ck f1.sh f2.sh || { echo "REARM-REFUSED (dirty tree, expected)"; exit 0; }
    memo_batch_hit 0 && { echo "STALE-GREEN-SERVED"; exit 1; }
    echo CLEAN'
  [ "$status" -eq 0 ]
  [[ "$output" != *STALE-GREEN-SERVED* ]]
}

@test "a different checker-id misses — the read set is part of the key" {
  run drive "$LIB" '
    memo_init && memo_batch_arm ck-A f1.sh f2.sh || exit 1
    memo_batch_record 0
    memo_batch_arm ck-B f1.sh f2.sh || exit 1
    memo_batch_hit 0 && { echo "CROSS-CHECKER-HIT"; exit 1; }
    echo CLEAN'
  [ "$status" -eq 0 ]
  [[ "$output" == *CLEAN* ]]
}

@test "a corrupted entry misses — the body must match the key exactly" {
  run drive "$LIB" '
    memo_init && memo_batch_arm ck f1.sh f2.sh || exit 1
    memo_batch_record 0
    b="${MEMO_B_BLOBS[0]}"
    printf "gate-memo v1 green WRONG %s" "$b" > "$MEMO_B_DIR/$b"
    memo_batch_hit 0 && { echo "CORRUPT-ENTRY-HIT"; exit 1; }
    printf "" > "$MEMO_B_DIR/$b"
    memo_batch_hit 0 && { echo "EMPTY-ENTRY-HIT"; exit 1; }
    echo CLEAN'
  [ "$status" -eq 0 ]
  [[ "$output" == *CLEAN* ]]
}

@test "🚨 a SHORT batch disarms — the index-alignment control" {
  # A directory in the population makes `git hash-object` abort at that argument, so it emits only
  # the hashes BEFORE it. Without the count assertion, index 2 would carry index 3's verdict.
  run drive "$LIB" '
    mkdir -p adir
    memo_init || exit 1
    memo_batch_arm ck f1.sh f2.sh adir f4.sh f5.sh && { echo "ARMED-ON-SHORT-BATCH"; exit 1; }
    echo "OK=$MEMO_B_OK BLOBS=${#MEMO_B_BLOBS[@]}"
    memo_batch_hit 0 && { echo "HIT-WHILE-DISARMED"; exit 1; }
    echo CLEAN'
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK=0 BLOBS=0"* ]]
  [[ "$output" == *CLEAN* ]]
}

@test "MUTANT: deleting the alignment control arms on a short batch" {
  m="$(mutate 'if [ "${#MEMO_B_BLOBS[@]}" -ne "$n" ]; then MEMO_B_BLOBS=(); MEMO_B_DIR=""; return 1; fi' ':')"
  run drive "$m" '
    mkdir -p adir
    memo_init || exit 1
    memo_batch_arm ck f1.sh f2.sh adir f4.sh f5.sh && { echo "ARMED-ON-SHORT-BATCH"; exit 1; }
    echo NOT-CAUGHT'
  # The mutant MUST arm on a short batch. If this reads CLEAN/NOT-CAUGHT the case above is blind.
  [[ "$output" == *ARMED-ON-SHORT-BATCH* ]]
}

@test "MUTANT: a body check that only tests non-emptiness accepts a corrupted entry" {
  m="$(mutate '[ "$body" = "gate-memo v1 green $MEMO_B_CK $b" ]' '[ -n "$body" ]')"
  run drive "$m" '
    memo_init && memo_batch_arm ck f1.sh f2.sh || exit 1
    memo_batch_record 0
    b="${MEMO_B_BLOBS[0]}"
    printf "gate-memo v1 green WRONG %s" "$b" > "$MEMO_B_DIR/$b"
    memo_batch_hit 0 && { echo "CORRUPT-ENTRY-HIT"; exit 1; }
    echo NOT-CAUGHT'
  [[ "$output" == *CORRUPT-ENTRY-HIT* ]]
}

@test "an empty population refuses to arm — never a vacuous green" {
  run drive "$LIB" '
    memo_init || exit 1
    memo_batch_arm ck && { echo "ARMED-ON-NOTHING"; exit 1; }
    echo "OK=$MEMO_B_OK"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK=0"* ]]
}

@test "MUTANT: dropping the empty-population guard arms on nothing" {
  m="$(mutate '[ "$#" -gt 0 ] || return 1                     # nothing to arm on ⇒ OFF, not a vacuous green' ':')"
  run drive "$m" '
    memo_init || exit 1
    memo_batch_arm ck && { echo "ARMED-ON-NOTHING"; exit 1; }
    echo NOT-CAUGHT'
  [[ "$output" == *ARMED-ON-NOTHING* ]]
}

@test "a memo that is OFF refuses to arm — MEMO_OK gates the batch" {
  run drive "$LIB" '
    MEMO_OK=0
    memo_batch_arm ck f1.sh f2.sh && { echo "ARMED-WHILE-OFF"; exit 1; }
    echo "OK=$MEMO_B_OK"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK=0"* ]]
}

@test "a dirty tree keeps the batch OFF — memo_init is the gate, unchanged" {
  run drive "$LIB" '
    printf "dirty\n" >> f1.sh
    memo_init && { echo "INIT-ARMED-ON-DIRTY"; exit 1; }
    memo_batch_arm ck f1.sh f2.sh && { echo "ARMED-ON-DIRTY"; exit 1; }
    echo CLEAN'
  [ "$status" -eq 0 ]
  [[ "$output" == *CLEAN* ]]
}

@test "the batch and per-file APIs agree on what is green" {
  # Same content, same salt: whatever one calls green the other must too. The two key layouts are
  # different (flat digest filename vs per-checker dir + blob), so this pins that the MOVE of the
  # checker digest changed only the arithmetic.
  run drive "$LIB" '
    memo_init && memo_batch_arm ck f1.sh f2.sh f3.sh || exit 1
    memo_batch_record 1
    memo_file_record ck f3.sh
    memo_batch_hit 1 || { echo "BATCH-LOST-ITS-OWN"; exit 1; }
    memo_file_hit ck f3.sh || { echo "FILE-LOST-ITS-OWN"; exit 1; }
    memo_batch_hit 0 && { echo "BATCH-INVENTED-A-GREEN"; exit 1; }
    memo_file_hit ck f1.sh && { echo "FILE-INVENTED-A-GREEN"; exit 1; }
    echo CLEAN'
  [ "$status" -eq 0 ]
  [[ "$output" == *CLEAN* ]]
}
