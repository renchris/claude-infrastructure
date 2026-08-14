#!/usr/bin/env bats
# gitid-file-memo.bats — the per-file memo inside git-identity-lint (backlog c4d65e8933e1).
#
# THE SPLIT WITH --selftest IS THE REPO'S STANDING RULE: `--selftest` owns the MECHANISM on synthetic
# fixtures with no history, and this suite owns COVERAGE AGAINST THE REAL CORPUS. Asking either to do
# the other's job yields a vacuous pass.
#
# WHY THIS MEMO EXISTS. The arm costs 18.5 ms/file over 727 files — 13.4s, measured through
# ship-land's own_run — and essentially all of it is one `awk` fork per file. Every optimistic round
# a sibling invalidates (exit 42) re-pays it over a tree identical except for the sibling's delta.
#
# WHAT IS PINNED IS THE MEMO AGREEING WITH AN UNMEMOIZED RUN, never that it is fast. A memo that
# returns a green it did not earn is strictly worse than the 13s it saves (repo memory:
# gate-default-decides-failure-direction).
#
# 🚨 CASE 1 IS A POSITIVE CONTROL AND IT COMES FIRST BY CONSTRUCTION. The memo refuses on a dirty
# worktree, so a suite that ran against the live checkout would go silently memo-OFF for anyone with
# an edit in flight — and every case below would then pass while asserting nothing. Case 1 proves
# the memo is ARMED before anything else claims it behaves.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"          # hermeticity: never the operator's live ~
  mkdir -p "$HOME"

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/git-identity-lint.sh"

  # A REAL slice of the corpus in a repo of its own, so the memo's clean-tree precondition is ours
  # to control rather than the operator's.
  CORPUS="$BATS_TEST_TMPDIR/corpus"
  mkdir -p "$CORPUS/scripts/lib" "$CORPUS/tests" "$CORPUS/bin"
  # THE MEMO LIBRARY MUST TRAVEL WITH THE LINT. The lint sources "$ROOT/scripts/lib/gate-memo.sh",
  # and ROOT is derived from the lint's own resolved path — so a fixture that copies the lint but
  # not the lib gets a lint whose memo is fail-closed OFF. That is correct behaviour and a silent
  # one: case 1 below is the only reason this suite is not still asserting nothing.
  cp "$REPO/scripts/lib/gate-memo.sh" "$CORPUS/scripts/lib/"
  # Glob into an array and slice, never `ls | head`: the gate's own .bats shellcheck ratchet blocks
  # on SC2012, one findings-bearing line per use.
  ALL=( "$REPO"/scripts/*.sh )
  for f in "${ALL[@]:0:35}"; do cp "$f" "$CORPUS/scripts/"; done
  cp "$LINT" "$CORPUS/scripts/"                 # the lint must be able to find itself under ROOT
  cd "$CORPUS" || exit 1
  git init -q .
  git add -A
  git -c user.email=tester@example.com -c user.name=tester commit -qm init
}

# run_lint — the lint against the fixture corpus, combined output. CC_GITID_OWN is exported the way
# ship-land's own_run does, so what is measured is the invocation the gate actually makes.
run_lint() {
  ( cd "$CORPUS" || exit 2
    CC_GITID_OWN="${1-x}" bash "$CORPUS/scripts/git-identity-lint.sh" "$CORPUS" 2>&1 )
}

# An ABSENT attestation answers -1, never the empty string: `[ "" -gt 1 ]` aborts the test with a
# usage error, which reads as a red for the wrong reason and hides which assertion actually failed.
carried() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*per-file memo — \([0-9]*\) verdict(s) carried.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}
proven() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*carried, \([0-9]*\) proven fresh.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}

@test "POSITIVE CONTROL: the memo arms and carries on an unchanged committed corpus" {
  first="$(run_lint)"
  [[ "$first" == *"per-file memo"* ]] || { echo "MEMO NEVER ARMED — every case below is vacuous"; echo "$first"; return 1; }
  [ "$(carried "$first")" -eq 0 ]              # nothing earned yet
  [ "$(proven "$first")" -gt 0 ]
  second="$(run_lint)"
  [ "$(carried "$second")" -gt 0 ]             # THE ASSERTION: it actually carried
  [ "$(proven "$second")" -eq 0 ]
}

@test "a carried run reports the SAME verdicts as an unmemoized one" {
  run_lint >/dev/null                                    # warm
  warm="$(run_lint)"
  cold="$( cd "$CORPUS" && CC_GITID_MEMO=off CC_GITID_OWN=x bash "$CORPUS/scripts/git-identity-lint.sh" "$CORPUS" 2>&1 )"
  # Compare the VERDICT lines, not the attestation (which differs by construction).
  w="$(printf '%s\n' "$warm" | grep -v 'per-file memo' || true)"
  c="$(printf '%s\n' "$cold" | grep -v 'per-file memo' || true)"
  [ "$w" = "$c" ]
}

@test "editing one file re-proves THAT file and no other" {
  run_lint >/dev/null
  before="$(run_lint)"
  n="$(carried "$before")"
  [ "$n" -gt 1 ]
  target="$(printf '%s\n' "$CORPUS"/scripts/*.sh | grep -v git-identity-lint | tail -1)"
  printf '\n# a comment that changes bytes and no verdict\n' >> "$target"
  ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm edit )
  after="$(run_lint)"
  [ "$(proven "$after")" -eq 1 ]               # exactly the edited file
  [ "$(carried "$after")" -eq $((n - 1)) ]
}

@test "a change to the LINT ITSELF invalidates every carried verdict" {
  run_lint >/dev/null
  before="$(run_lint)"
  [ "$(carried "$before")" -gt 1 ]
  printf '\n# read-set change: the lint blob is part of the key\n' >> "$CORPUS/scripts/git-identity-lint.sh"
  ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm lint-edit )
  after="$(run_lint)"
  [ "$(carried "$after")" -eq 0 ]
  [ "$(proven "$after")" -gt 0 ]
}

@test "the ALLOWLIST is in the read set — changing it invalidates, with no byte of any file moving" {
  run_lint >/dev/null
  before="$(run_lint)"
  [ "$(carried "$before")" -gt 1 ]
  after="$( cd "$CORPUS" || exit 2
            CC_GITID_ALLOWLIST="some-file.sh" CC_GITID_OWN=x \
            bash "$CORPUS/scripts/git-identity-lint.sh" "$CORPUS" 2>&1 )"
  [ "$(carried "$after")" -eq 0 ]
}

@test "a live finding is RE-REPORTED, never replayed from the cache" {
  printf 'git -C "$d" config user.email a@b\n' > "$CORPUS/scripts/zz-leaky.sh"
  ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm leak )
  first="$( cd "$CORPUS" && CC_GITID_ALLOWLIST="" CC_GITID_OWN="zz-leaky.sh" bash "$CORPUS/scripts/git-identity-lint.sh" "$CORPUS" 2>&1 || true )"
  [[ "$first" == *"zz-leaky.sh"* ]] || false
  second="$( cd "$CORPUS" && CC_GITID_ALLOWLIST="" CC_GITID_OWN="zz-leaky.sh" bash "$CORPUS/scripts/git-identity-lint.sh" "$CORPUS" 2>&1 || true )"
  # The finding must appear BOTH times — a cached red would print it once and go quiet.
  [[ "$second" == *"zz-leaky.sh"* ]]
}

@test "🚨 a run whose scan could not RUN records NOTHING — the veto is ABSOLUTE, not a delta" {
  # THIS IS THE ONE DEFECT THE SIBLING LINT SHIPPED (test-hermeticity, one iteration, caught only by
  # its own selftest). A veto written as a per-file DELTA vetoes only the FIRST file whose predicate
  # dies: every file after it compares equal to its own baseline, comes out unchanged, and is
  # RECORDED — out of a run that exits 2 and whose whole point is that it produced no verdict.
  # scan_file is fail-SAFE (a sentinel, never a fabricated violation), so a non-verdict looks
  # exactly like a clean file at the record site and nothing else could catch this.
  #
  # THE DISCRIMINATOR: break the scan for exactly ONE file. Absolute veto ⇒ the next run carries 0.
  # Delta veto ⇒ the next run carries every OTHER file. One file rather than all of them because
  # scan_file retries 3x at 1s intervals, and 35 files x 3s would put this suite past the gate's
  # 120s smoke budget and turn a real assertion into a recurring exit-124 non-verdict
  # (repo memory: bound-must-fit-the-band-not-the-bench).
  run_lint >/dev/null                                   # warm: everything earned
  before="$(run_lint)"
  n="$(carried "$before")"
  [ "$n" -gt 1 ]

  # THE VICTIM IS THE FIRST FILE IN THE POPULATION, and that choice is what makes this case
  # discriminate. CHECK_FAILED vetoes from the failure ONWARD — files scanned before it had working
  # predicates and genuinely emitted nothing, so their verdicts are real and are correctly banked.
  # Break the LAST file and both the absolute and the delta veto leave N-1 files recorded, and the
  # case says nothing. Break the FIRST and the two answers separate completely: absolute ⇒ 0
  # carried, delta ⇒ every other file carried.
  VICTIMS=( "$CORPUS"/scripts/*.sh )
  for v in "${VICTIMS[@]}"; do
    case "$v" in *git-identity-lint.sh) continue ;; esac
    victim="$v"; break
  done
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  { echo '#!/bin/bash'
    printf 'for a in "$@"; do [ "$a" = "%s" ] && exit 3; done\n' "$victim"
    echo 'exec /usr/bin/awk "$@"'
  } > "$SHIM/awk"
  chmod +x "$SHIM/awk"

  out="$( cd "$CORPUS" || exit 2
          rm -rf "$(git rev-parse --git-common-dir)/ship-land-memo"
          PATH="$SHIM:$PATH" CC_GITID_OWN=x bash "$CORPUS/scripts/git-identity-lint.sh" "$CORPUS" 2>&1 || true )"
  [[ "$out" == *"UNUSABLE"* ]] || false                 # the run really did produce no verdict

  # THE ASSERTION: with the scan restored, EVERY file must be proven fresh again. A single carried
  # verdict here means the unusable run banked one, which is the delta bug.
  after="$(run_lint)"
  [ "$(carried "$after")" -eq 0 ]
  [ "$(proven "$after")" -gt 1 ]
}

@test "a dirty worktree disarms the memo entirely" {
  run_lint >/dev/null
  printf '\n# uncommitted\n' >> "$CORPUS/scripts/git-identity-lint.sh"
  out="$(run_lint)"
  [[ "$out" != *"per-file memo"* ]]
}

@test "CC_GITID_MEMO=off disarms it" {
  out="$( cd "$CORPUS" || exit 2
          CC_GITID_MEMO=off CC_GITID_OWN=x bash "$CORPUS/scripts/git-identity-lint.sh" "$CORPUS" 2>&1 )"
  [[ "$out" != *"per-file memo"* ]]
}
