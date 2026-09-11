#!/usr/bin/env bats
# pipefail-file-memo.bats — the per-file memo inside pipefail-sigpipe-lint (follow-on 3 of the
# cloud-lane redesign: memoize the land gate's ratchet lints, highest measured runtime first).
#
# THE SPLIT WITH --selftest, as in gitid-file-memo.bats: --selftest owns the DETECTOR, on synthetic
# fixtures in a non-git tmpdir where the memo can never arm. This suite owns the MEMO — that it
# carries, that a carried run says exactly what an unmemoized run says, and that every component of
# its key INVALIDATES when it moves. A memo keyed on the wrong thing is strictly worse than no memo:
# it hands out a green nobody earned (repo memory: gate-default-decides-failure-direction).
#
# THE POPULATION IS FULLY OURS, so every count below is exact rather than "> 0". Seven files are in
# the lint's scan set: the five fixtures, the copied memo library, and the allowlist (scripts/* is a
# scan shape). Exactly one of them — hit.sh — carries a finding, so a warm run carries 6 and re-proves
# 1, and a finding re-proven on every run is the memo's first invariant made visible.
#
# 🚨 CASE 1 IS A POSITIVE CONTROL AND COMES FIRST. The memo refuses on a dirty worktree, so a suite
# that silently ran memo-OFF would pass every case below while asserting nothing.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"          # hermeticity: never the operator's live ~
  mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CORPUS="$BATS_TEST_TMPDIR/corpus"
  mkdir -p "$CORPUS/scripts/lib"
  # THE LIBRARY MUST TRAVEL WITH THE LINT: it is sourced from beside the lint, never from ROOT, so a
  # copy without it is a lint whose memo is fail-closed OFF — correct, and silent. Case 1 catches it.
  cp "$REPO/scripts/pipefail-sigpipe-lint.sh" "$CORPUS/scripts/"
  cp "$REPO/scripts/lib/gate-memo.sh" "$CORPUS/scripts/lib/"
  printf '# empty allowlist — every finding here is a live one\n' > "$CORPUS/scripts/pipefail-sigpipe-allow.txt"
  mk clean1 'echo one'
  mk clean2 'echo two'
  mk clean3 'echo three'
  mk hit 'if git status --porcelain 2>/dev/null | grep -q .; then :; fi'
  mk nopf 'echo this file never enables pipefail' 'set -e'
  ( cd "$CORPUS" && git init -q . )
  commit init
}

mk() {  # $1=name $2=body [$3=set line]
  { echo '#!/bin/bash'; echo "${3:-set -euo pipefail}"; printf '%s\n' "$2"; } > "$CORPUS/scripts/$1.sh"
}
commit() { ( cd "$CORPUS" && git add -A && git -c user.email=t@e.x -c user.name=t commit -qm "$1" ); }

# The default --scan mode, which is the invocation ship-land's own_run makes. Combined output; the
# rc is not the subject here (hit.sh is outside the own-set, so it is advisory either way).
run_lint() {
  ( cd "$CORPUS" || exit 2
    CC_PIPEFAIL_OWN=x bash "$CORPUS/scripts/pipefail-sigpipe-lint.sh" 2>&1 ) || true
}
census() {
  ( cd "$CORPUS" || exit 2
    bash "$CORPUS/scripts/pipefail-sigpipe-lint.sh" --census 2>&1 ) || true
}

# An ABSENT attestation answers -1, never the empty string: `[ "" -eq 1 ]` aborts the test with a
# usage error, which reads as a red for the wrong reason and hides which assertion failed.
carried() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*per-file memo — \([0-9]*\) verdict(s) carried.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}
proven() {
  local v; v="$(printf '%s\n' "$1" | sed -n 's/.*carried, \([0-9]*\) proven fresh.*/\1/p' | tail -1)"
  printf '%s' "${v:--1}"
}

# A PATH shim for one interpreter. Its bytes are FIXED for the life of a test, so it keys exactly
# one checker; whether it fails is decided by a flag FILE, which is outside the key by construction.
# That is what lets a case break one probe on run 1 and heal it on run 2 UNDER THE SAME KEY.
shim_dir() { SHIM="$BATS_TEST_TMPDIR/shim"; mkdir -p "$SHIM"; export PF_SHIM_FLAG="$BATS_TEST_TMPDIR/fail.flag"; }

@test "POSITIVE CONTROL: the memo arms, and carries every clean file on an unchanged corpus" {
  first="$(run_lint)"
  [[ "$first" == *"per-file memo"* ]] || { echo "MEMO NEVER ARMED — every case below is vacuous"; echo "$first"; return 1; }
  [ "$(carried "$first")" -eq 0 ]
  [ "$(proven "$first")" -eq 7 ]
  second="$(run_lint)"
  [ "$(carried "$second")" -eq 6 ]             # THE ASSERTION: it actually carried
  [ "$(proven "$second")" -eq 1 ]              # and the one finding was re-proven, not replayed
}

@test "a carried run reports the SAME verdict and the SAME census as an unmemoized one" {
  run_lint >/dev/null
  warm="$(run_lint)"
  cold="$( cd "$CORPUS" && CC_PIPEFAIL_MEMO=off CC_PIPEFAIL_OWN=x bash "$CORPUS/scripts/pipefail-sigpipe-lint.sh" 2>&1 || true )"
  [ "$(carried "$warm")" -eq 6 ]               # the warm side really was carried
  w="$(printf '%s\n' "$warm" | grep -v 'per-file memo' || true)"
  c="$(printf '%s\n' "$cold" | grep -v 'per-file memo' || true)"
  [ "$w" = "$c" ]
  wc_="$(census)"
  cc_="$( cd "$CORPUS" && CC_PIPEFAIL_MEMO=off bash "$CORPUS/scripts/pipefail-sigpipe-lint.sh" --census 2>&1 || true )"
  [ "$wc_" = "$cc_" ]
}

@test "a live finding is RE-REPORTED on every run, never replayed from the cache" {
  run_lint >/dev/null
  one="$(census)"; two="$(census)"
  [[ "$one" == *"scripts/hit.sh:"* ]] || false
  [[ "$two" == *"scripts/hit.sh:"* ]]
}

@test "editing one file re-proves THAT file and no other" {
  run_lint >/dev/null
  printf '# a comment that changes bytes and no verdict\n' >> "$CORPUS/scripts/clean3.sh"
  commit edit
  after="$(run_lint)"
  [ "$(proven "$after")" -eq 2 ]               # clean3 + the finding
  [ "$(carried "$after")" -eq 5 ]
}

@test "KEY: a change to the LINT ITSELF invalidates every carried verdict" {
  run_lint >/dev/null
  printf '\n# read-set change: the lint blob is part of the key\n' >> "$CORPUS/scripts/pipefail-sigpipe-lint.sh"
  commit lint-edit
  after="$(run_lint)"
  [ "$(carried "$after")" -eq 0 ]
  [ "$(proven "$after")" -eq 7 ]
}

@test "KEY: a different AWK binary invalidates every carried verdict — and then re-earns them" {
  run_lint >/dev/null
  shim_dir
  cat > "$SHIM/awk" <<'SH'
#!/bin/bash
exec /usr/bin/awk "$@"
SH
  chmod +x "$SHIM/awk"
  a="$( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh 2>&1 || true )"
  [ "$(carried "$a")" -eq 0 ]                  # a verdict earned under /usr/bin/awk is not honoured
  b="$( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh 2>&1 || true )"
  [ "$(carried "$b")" -eq 6 ]                  # the shim is a working awk: the miss was the KEY
}

@test "KEY: a different GREP binary invalidates every carried verdict — and then re-earns them" {
  run_lint >/dev/null
  shim_dir
  cat > "$SHIM/grep" <<'SH'
#!/bin/bash
exec /usr/bin/grep "$@"
SH
  chmod +x "$SHIM/grep"
  a="$( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh 2>&1 || true )"
  [ "$(carried "$a")" -eq 0 ]
  b="$( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh 2>&1 || true )"
  [ "$(carried "$b")" -eq 6 ]
}

# ── the three could-not-answer states: each is skipped exactly as before, and NONE is banked ────────
# Each case breaks ONE probe for ONE clean file on a cold run, heals it, and runs again under the SAME
# key. A banked non-answer shows up as that file being carried (proven 1) instead of re-proven (2).

@test "an AWK that could not run for a clean file is never banked" {
  shim_dir
  cat > "$SHIM/awk" <<'SH'
#!/bin/bash
if [ -e "$PF_SHIM_FLAG" ]; then for a in "$@"; do [ "$a" = scripts/clean1.sh ] && exit 3; done; fi
exec /usr/bin/awk "$@"
SH
  chmod +x "$SHIM/awk"
  : > "$PF_SHIM_FLAG"
  ( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh >/dev/null 2>&1 || true )
  rm -f "$PF_SHIM_FLAG"
  b="$( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh 2>&1 || true )"
  [ "$(proven "$b")" -eq 2 ]                   # clean1 + the finding
  [ "$(carried "$b")" -eq 5 ]
}

@test "a clause-1 GREP that could not run is never banked as 'does not enable pipefail'" {
  shim_dir
  cat > "$SHIM/grep" <<'SH'
#!/bin/bash
if [ -e "$PF_SHIM_FLAG" ]; then
  case "$*" in *pipefail*scripts/nopf.sh*) exit 2 ;; esac
fi
exec /usr/bin/grep "$@"
SH
  chmod +x "$SHIM/grep"
  : > "$PF_SHIM_FLAG"
  ( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh >/dev/null 2>&1 || true )
  rm -f "$PF_SHIM_FLAG"
  b="$( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh 2>&1 || true )"
  [ "$(proven "$b")" -eq 2 ]                   # nopf + the finding
  [ "$(carried "$b")" -eq 5 ]
}

@test "an errexit (HASE) GREP that could not run is never banked" {
  shim_dir
  cat > "$SHIM/grep" <<'SH'
#!/bin/bash
if [ -e "$PF_SHIM_FLAG" ]; then
  case "$*" in *errexit*scripts/clean1.sh*) exit 2 ;; esac
fi
exec /usr/bin/grep "$@"
SH
  chmod +x "$SHIM/grep"
  : > "$PF_SHIM_FLAG"
  ( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh >/dev/null 2>&1 || true )
  rm -f "$PF_SHIM_FLAG"
  b="$( cd "$CORPUS" && PATH="$SHIM:$PATH" CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh 2>&1 || true )"
  [ "$(proven "$b")" -eq 2 ]                   # clean1 + the finding
  [ "$(carried "$b")" -eq 5 ]
}

@test "a dirty worktree disarms the memo entirely" {
  run_lint >/dev/null
  printf '# uncommitted\n' >> "$CORPUS/scripts/clean1.sh"
  out="$(run_lint)"
  [[ "$out" != *"per-file memo"* ]]
}

@test "CC_PIPEFAIL_MEMO=off disarms it" {
  out="$( cd "$CORPUS" && CC_PIPEFAIL_MEMO=off CC_PIPEFAIL_OWN=x bash scripts/pipefail-sigpipe-lint.sh 2>&1 || true )"
  [[ "$out" != *"per-file memo"* ]]
}

@test "--census and --regen stay free of the attestation: their output is consumed as data" {
  run_lint >/dev/null
  c="$(census)"
  r="$( cd "$CORPUS" && bash scripts/pipefail-sigpipe-lint.sh --regen 2>&1 || true )"
  [[ "$c" != *"per-file memo"* ]] || false
  [[ "$r" != *"per-file memo"* ]]
}
