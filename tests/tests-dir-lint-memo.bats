#!/usr/bin/env bats
# tests-dir-lint-memo.bats — the per-file memo in the land-gate ratchet lints that judge tests/*.bats one
# suite at a time (follow-on 3 of the cloud-lane redesign: memoize the arms, highest runtime first).
# moving-ref-control-lint is the first; the siblings of the same shape append their cases below.
#
# SAME CONTRACT AS gitid-file-memo.bats and pipefail-file-memo.bats: --selftest owns the DETECTOR (and
# runs memo-OFF, so it always exercises it); this suite owns the MEMO — it carries, a carried run says
# exactly what an unmemoized run says, and every component of its key INVALIDATES when it moves. A memo
# keyed on the wrong thing is strictly worse than no memo: it hands out a green nobody earned.
#
# THE CORPUS IS FULLY OURS, so every count is exact: three clean suites and one that is a finding for the
# lint under test. A warm run therefore carries 3 and re-proves 1 — the finding, which is never cached.
#
# 🚨 Each lint's POSITIVE CONTROL comes first: the memo refuses on a dirty worktree, so a suite that
# silently ran memo-OFF would pass every other case while asserting nothing.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"          # hermeticity: never the operator's live ~
  mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CORPUS="$BATS_TEST_TMPDIR/corpus"
}

# mkcorpus <lint basename> <env prefix> <a line that makes a suite a FINDING for that lint>
mkcorpus() {
  LINT_BASE="$1"; P="$2"
  mkdir -p "$CORPUS/scripts/lib" "$CORPUS/tests"
  # The library travels with the lint: it is sourced from the lint's own ROOT, so a copy without it is
  # a lint whose memo is fail-closed OFF — correct, and silent. The positive control catches that.
  cp "$REPO/scripts/$1" "$CORPUS/scripts/"
  cp "$REPO/scripts/lib/gate-memo.sh" "$CORPUS/scripts/lib/"
  for n in 1 2 3; do printf '@test "clean %s" {\n  true\n}\n' "$n" > "$CORPUS/tests/clean$n.bats"; done
  printf '@test "finding" {\n  %s\n}\n' "$3" > "$CORPUS/tests/zz-hit.bats"
  ( cd "$CORPUS" && git init -q . && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm init )
}
commit() { ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm "$1" ); }

# The invocation ship-land's own_run makes: the own-set EXPORTED (here to a name nothing matches, so the
# finding is advisory and the rc is not the subject), the suites dir given relative to the repo root.
run_lint() {  # [extra VAR=value …] → combined output
  ( cd "$CORPUS" && env "CC_${P}_OWN=x" "$@" bash "scripts/$LINT_BASE" tests 2>&1 ) || true
}

# An ABSENT attestation answers -1, never the empty string: `[ "" -eq 1 ]` aborts the test with a usage
# error, which reads as a red for the wrong reason and hides which assertion failed.
carried() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*per-file memo — \([0-9]*\) verdict(s) carried.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}
proven() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*carried, \([0-9]*\) proven fresh.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}
store_entries() { find "$CORPUS/.git/ship-land-memo" -type f 2>/dev/null | grep -c . || true; }

# A PATH shim whose bytes are FIXED for the life of a test (so it keys exactly one checker, where it is in
# the key at all); whether it fails is decided by a flag FILE, which is outside every key by construction.
shim() {  # $1=tool · $2=case pattern over "$*" that makes it fail while the flag exists · $3=exit code
  SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"
  export MEMO_SHIM_FLAG="$BATS_TEST_TMPDIR/fail.flag"
  # shellcheck disable=SC2016  # the shim's own "$MEMO_SHIM_FLAG" / "$*" / "$@" must reach it LITERALLY
  { printf '#!/bin/bash\n'
    printf 'if [ -e "$MEMO_SHIM_FLAG" ]; then case "$*" in %s) exit %s ;; esac; fi\n' "$2" "$3"
    printf 'exec /usr/bin/%s "$@"\n' "$1"
  } > "$SHIM/$1"
  chmod +x "$SHIM/$1"
}

# ── moving-ref-control-lint ──────────────────────────────────────────────────────────────────────────
# Its finding: a pre-fix control replayed from a ref that ADVANCES. Carried here inside single quotes,
# which the detector strips, so this suite is not itself a finding.
# shellcheck disable=SC2016  # the fixture LINE is data written into a corpus suite, never expanded here
mr() { mkcorpus moving-ref-control-lint.sh MOVINGREF 'run git -C "$REPO" show main:scripts/x.sh'; }

@test "moving-ref POSITIVE CONTROL: the memo arms, and carries every clean suite" {
  mr
  first="$(run_lint)"
  [[ "$first" == *"per-file memo"* ]] || { echo "MEMO NEVER ARMED — every moving-ref case is vacuous"; echo "$first"; false; }
  [ "$(carried "$first")" -eq 0 ]
  [ "$(proven "$first")" -eq 4 ]
  second="$(run_lint)"
  [ "$(carried "$second")" -eq 3 ]
  [ "$(proven "$second")" -eq 1 ]
}

@test "moving-ref: a carried run says exactly what an unmemoized run says, and re-reports the finding" {
  mr
  run_lint >/dev/null
  warm="$(run_lint)"
  [ "$(carried "$warm")" -eq 3 ]
  cold="$(run_lint CC_MOVINGREF_MEMO=off)"
  [ "$(printf '%s\n' "$warm" | grep -v 'per-file memo')" = "$(printf '%s\n' "$cold" | grep -v 'per-file memo')" ]
  [[ "$warm" == *"zz-hit.bats"* ]]
}

@test "moving-ref: editing one suite re-proves THAT suite and no other" {
  mr
  run_lint >/dev/null
  printf '# bytes that change no verdict\n' >> "$CORPUS/tests/clean2.bats"
  commit edit
  after="$(run_lint)"
  [ "$(proven "$after")" -eq 2 ]
  [ "$(carried "$after")" -eq 2 ]
}

@test "moving-ref KEY: the lint's own blob invalidates every carried verdict" {
  mr
  run_lint >/dev/null
  printf '\n# read-set change\n' >> "$CORPUS/scripts/moving-ref-control-lint.sh"
  commit lint-edit
  [ "$(carried "$(run_lint)")" -eq 0 ]
}

@test "moving-ref KEY: the allowlist is in the key BY VALUE — no byte of any file moves" {
  mr
  run_lint >/dev/null
  [ "$(carried "$(run_lint CC_MOVINGREF_ALLOWLIST=unrelated.bats)")" -eq 0 ]
}

@test "moving-ref KEY: a different AWK binary invalidates — and then re-earns" {
  mr
  run_lint >/dev/null
  shim awk 'NEVER-MATCHES' 3
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 0 ]
  [ "$(carried "$(run_lint PATH="$SHIM:$PATH")")" -eq 3 ]
}

@test "moving-ref: an AWK that could not run for a clean suite is never banked" {
  mr
  shim awk '*tests/clean1.bats*' 3
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  b="$(run_lint PATH="$SHIM:$PATH")"
  [ "$(proven "$b")" -eq 2 ]                   # clean1 + the finding
  [ "$(carried "$b")" -eq 2 ]
}

@test "moving-ref: an allowlisted CLEAN suite is never banked, even when the allowlist probe cannot run" {
  # The RATCHET line ("fixed but still grandfathered") is how the list shrinks, and it must print on every
  # run. in_allowlist is a forked grep; if it fails, the suite falls through to the clean branch — and
  # without the builtin guard at the record site that fall-through would be BANKED, silencing the line
  # for as long as the key holds. grep is not in this lint's key, so the shim cannot hide the bug.
  mr
  shim grep '*-xF*' 2
  : > "$MEMO_SHIM_FLAG"
  run_lint PATH="$SHIM:$PATH" CC_MOVINGREF_ALLOWLIST=clean1.bats >/dev/null
  rm -f "$MEMO_SHIM_FLAG"
  out="$(run_lint PATH="$SHIM:$PATH" CC_MOVINGREF_ALLOWLIST=clean1.bats)"
  [[ "$out" == *"clean1.bats"* ]]
}

@test "moving-ref: --selftest runs memo-OFF and writes nothing to the store" {
  mr
  run_lint >/dev/null
  before="$(store_entries)"
  ( cd "$CORPUS" && bash scripts/moving-ref-control-lint.sh --selftest >/dev/null 2>&1 ) || true
  [ "$(store_entries)" -eq "$before" ]
}

@test "moving-ref: a dirty worktree, and CC_MOVINGREF_MEMO=off, each disarm the memo" {
  mr
  [[ "$(run_lint CC_MOVINGREF_MEMO=off)" != *"per-file memo"* ]] || false
  printf '# uncommitted\n' >> "$CORPUS/tests/clean1.bats"
  [[ "$(run_lint)" != *"per-file memo"* ]]
}
