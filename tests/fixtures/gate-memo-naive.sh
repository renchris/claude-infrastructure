#!/bin/bash
# gate-memo-naive.sh — THE CONTROL for tests/land-gate-memo.bats. Not shipped, not sourced by any
# real code path: this is the naive memo the real one had to avoid being.
#
# It keys on the file PATH alone — no blob sha, no checker-version salt — and treats the mere
# EXISTENCE of an entry as green, with no body match. That is the shape a memo takes when it is
# written for speed and not for failure direction, and it is wrong in exactly the three ways the
# suite pins:
#   * an edited file keeps its old verdict          (no blob sha in the key)
#   * a checker upgrade keeps every old verdict     (no version salt)
#   * a corrupt or truncated entry still reads green (existence, not an exact body match)
#
# Running the suite with CC_MEMO_LIB=tests/fixtures/gate-memo-naive.sh must therefore FAIL the
# invalidation and corruption tests and PASS the rest. A control that fails everything (or nothing)
# attributes no test to any mechanism — the asymmetry is the evidence.

MEMO_OK=0
MEMO_DIR=""
MEMO_HITS=0
MEMO_RUNS=0
# NOTE: there is deliberately no MEMO_SALT here. Its ABSENCE is the mutation — the naive memo has
# no checker identity in its key, which is what makes test 3 (version invalidation) fail against it.

memo_init() {
  MEMO_OK=0
  [[ "${SHIP_LAND_MEMO:-on}" = "off" ]] && return 1
  local gd; gd="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1
  MEMO_DIR="$gd/ship-land-memo"
  mkdir -p "$MEMO_DIR" 2>/dev/null || return 1
  MEMO_OK=1
  return 0
}

_naive_path() {
  [[ "$MEMO_OK" = "1" ]] || return 1
  printf '%s/%s\n' "$MEMO_DIR" "$(printf '%s' "$1:$2" | tr -c 'A-Za-z0-9._-' '_')"
}

memo_file_hit() {
  local f; f="$(_naive_path "$1" "$2")" || return 1
  [[ -e "$f" ]]                      # EXISTENCE only — no body, no key restatement
}

memo_file_record() {
  local f; f="$(_naive_path "$1" "$2")" || return 0
  printf 'ok' > "$f" 2>/dev/null
  return 0
}

memo_partition() {
  local checker="$1" p; shift
  for p in "$@"; do memo_file_hit "$checker" "$p" || printf '%s\n' "$p"; done
}

memo_count() { MEMO_HITS=$(( MEMO_HITS + $1 )); MEMO_RUNS=$(( MEMO_RUNS + $2 )); }
memo_summary() { echo "→ gate: NAIVE CONTROL memo — ${MEMO_HITS} carried, ${MEMO_RUNS} run." >&2; }
