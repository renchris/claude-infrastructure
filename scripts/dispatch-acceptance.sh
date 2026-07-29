#!/bin/bash
# dispatch-acceptance.sh — render the AUTONOMY_DISPATCH_V2 §7 acceptance criteria as DISK-TRUTH
# READS. One row per criterion: PASS / FAIL / NOT-RUN, each naming the file it read.
#
# THE POINT: §7 claims are only worth what a disk read proves. This script IS that read — it is the
# instrument the rebuild's DoD is measured with, and it is deliberately fail-closed in the honest
# direction: a criterion whose evidence does not exist yet reports **NOT-RUN**, never PASS. A
# NOT-RUN is not a failure; a NOT-RUN reported as PASS is (memory: gate-never-ran-vs-gate-red,
# named-failure-vs-no-verdict — a non-verdict is a THIRD state, never folded into either).
#
#   dispatch-acceptance.sh              human table
#   dispatch-acceptance.sh --json       one JSON object per criterion
#   dispatch-acceptance.sh selftest     RED-proves the reader against fixtures
#
# Exit: 0 = no FAIL rows (PASS and NOT-RUN are both acceptable) · 1 = at least one FAIL · 3 = the
#       reader itself could not run (jq absent). Never exit 0 on a FAIL.
#
# Env seams (so the selftest is hermetic — it never reads the operator's live state):
#   CC_DISPATCH_IDL        decision/wall journal   (default ~/.claude/autonomy/idl.jsonl)
#   CC_BACKLOG_FILE        the ledger              (default ~/.claude/autonomy/backlog.jsonl)
#   CC_DISPATCH_PAGES_DIR  page channel            (default ~/.claude/autonomy/pages)
#   CC_DISPATCH_CEILING    concurrency ceiling     (default 6)
#   CC_ACCEPT_REPO         repo root for source greps (default: git toplevel of $PWD)
#   CC_ACCEPT_LAUNCHCTL    launchctl bin           (default: launchctl; stubbed in tests)
# shellcheck disable=SC2016  # grep PATTERNS are single-quoted on purpose — they must not expand
set -uo pipefail

IDL="${CC_DISPATCH_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
BACKLOG="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
PAGES_DIR="${CC_DISPATCH_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
CEILING="${CC_DISPATCH_CEILING:-6}"
REPO="${CC_ACCEPT_REPO:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LAUNCHCTL="${CC_ACCEPT_LAUNCHCTL:-launchctl}"
JSON=0; FAILS=0
ROWS=""   # accumulated "id\tverdict\tdetail\tsource" lines

command -v jq >/dev/null 2>&1 || { echo "dispatch-acceptance: jq is required" >&2; exit 3; }

row() { # <id> <verdict PASS|FAIL|NOT-RUN> <detail> <source>
  ROWS="${ROWS}$1	$2	$3	$4
"
  [ "$2" = FAIL ] && FAILS=$((FAILS + 1))
  return 0
}

# newest decision pass id present in the journal, or "" when v2 has never run.
newest_pass() { jq -r 'select(.actor=="cc-dispatch" and .action=="decision") | .pass // empty' "$IDL" 2>/dev/null | tail -1; }
have_v2()     { [ -n "$(newest_pass)" ]; }

# ── A1 — every open item gets a decision each pass ───────────────────────────────────────────────
a1() {
  local pass n_dec n_open
  pass="$(newest_pass)"
  if [ -z "$pass" ]; then
    row A1 NOT-RUN "no v2 decision records in the journal yet" "$IDL"; return
  fi
  n_dec="$(jq -r --arg p "$pass" 'select(.actor=="cc-dispatch" and .action=="decision" and .pass==$p) | .id' "$IDL" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
  # open = folded status "open" (blocked is excluded from the wave by contract, so not decided)
  n_open="$(cc-backlog list --open --json 2>/dev/null | jq '[.[] | select(.status=="open")] | length' 2>/dev/null || echo "")"
  if [ -z "$n_open" ]; then
    row A1 NOT-RUN "cannot fold the ledger (cc-backlog unavailable)" "$BACKLOG"; return
  fi
  if [ "$n_dec" -eq "$n_open" ]; then
    row A1 PASS "$n_dec decisions == $n_open open items (pass $pass)" "$IDL"
  else
    row A1 FAIL "$n_dec decisions != $n_open open items (pass $pass) — the pass did not cover the backlog" "$IDL"
  fi
}

# ── A2 — decision within 5 min of add ────────────────────────────────────────────────────────────
# Joins each item's `add` ts in the ledger to its FIRST decision record. Reports max; the bound is
# 300s. Items added before v2 existed are excluded (they cannot testify about v2's latency).
a2() {
  local first_pass_ts joined max p50 n
  have_v2 || { row A2 NOT-RUN "no v2 decision records yet" "$IDL"; return; }
  first_pass_ts="$(jq -r 'select(.actor=="cc-dispatch" and .action=="decision") | .ts' "$IDL" 2>/dev/null | sort | head -1)"
  joined="$(
    jq -r --arg since "$first_pass_ts" '
      select(.event=="add" and .ts >= $since) | [.id, .ts] | @tsv' "$BACKLOG" 2>/dev/null \
    | sort -u | while IFS=$'\t' read -r id ts; do
        [ -n "$id" ] || continue
        d="$(jq -r --arg i "$id" 'select(.actor=="cc-dispatch" and .action=="decision" and .id==$i) | .ts' "$IDL" 2>/dev/null | sort | head -1)"
        [ -n "$d" ] || continue
        a="$(iso_epoch "$ts")"; b="$(iso_epoch "$d")"
        [ -n "$a" ] && [ -n "$b" ] && echo $(( b - a ))
      done | sort -n
  )"
  n="$(printf '%s\n' "$joined" | grep -c '^[0-9-]' || true)"
  if [ "${n:-0}" -eq 0 ]; then
    row A2 NOT-RUN "no item was added AND decided inside the v2 window yet" "$BACKLOG + $IDL"; return
  fi
  max="$(printf '%s\n' "$joined" | tail -1)"
  p50="$(printf '%s\n' "$joined" | awk '{a[NR]=$1} END{print a[int((NR+1)/2)]}')"
  if [ "$max" -lt 300 ]; then
    row A2 PASS "max ${max}s p50 ${p50}s over n=$n adds (bound 300s)" "$BACKLOG + $IDL"
  else
    row A2 FAIL "max ${max}s exceeds the 300s bound (p50 ${p50}s, n=$n)" "$BACKLOG + $IDL"
  fi
}

iso_epoch() { # <iso8601> → epoch seconds (BSD + GNU)
  local s="${1:0:19}"
  date -u -j -f "%Y-%m-%dT%H:%M:%S" "$s" +%s 2>/dev/null || date -u -d "$s" +%s 2>/dev/null
}

# ── A3 — surplus defers, never abstains ──────────────────────────────────────────────────────────
a3() {
  local defers abst
  have_v2 || { row A3 NOT-RUN "no v2 decision records yet" "$IDL"; return; }
  defers="$(jq -r 'select(.actor=="cc-dispatch" and .action=="decision" and .verdict=="defer") | .id' "$IDL" 2>/dev/null | wc -l | tr -d ' ')"
  # abstentions SINCE v2 began — the legacy population is history, not a v2 defect.
  local since; since="$(jq -r 'select(.actor=="cc-dispatch" and .action=="decision") | .ts' "$IDL" 2>/dev/null | sort | head -1)"
  abst="$(jq -r --arg s "$since" 'select(.actor=="cc-dispatch" and .action=="abstained" and .ts >= $s) | .ts' "$IDL" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$abst" -eq 0 ]; then
    row A3 PASS "$defers deferral(s), 0 abstentions since v2 began" "$IDL"
  else
    row A3 FAIL "$abst abstention(s) since v2 began — surplus must defer, not abstain" "$IDL"
  fi
}

# ── A4 — zero false cliffs (every `capped` verdict carries falsifying evidence) ──────────────────
a4() {
  local walls bad_noev bad_healthy bad_rc
  walls="$(jq -r 'select(.actor=="cc-wave-plan" and .action=="wall") | .verdict' "$IDL" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$walls" -eq 0 ]; then
    row A4 NOT-RUN "no wall verdicts recorded (no cliff has been reached under v2)" "$IDL"; return
  fi
  bad_noev="$(jq -r 'select(.actor=="cc-wave-plan" and .action=="wall" and .verdict=="capped" and (.evidence|not)) | .ts' "$IDL" 2>/dev/null | wc -l | tr -d ' ')"
  bad_healthy="$(jq -r 'select(.actor=="cc-wave-plan" and .action=="wall" and .verdict=="capped")
                        | select([.evidence.accounts[]? | select(.state=="healthy")] | length > 0) | .ts' "$IDL" 2>/dev/null | wc -l | tr -d ' ')"
  bad_rc="$(jq -r 'select(.actor=="cc-wave-plan" and .action=="wall" and .verdict=="capped" and (.evidence.oracle_rc // 0) != 0) | .ts' "$IDL" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$bad_noev" -eq 0 ] && [ "$bad_healthy" -eq 0 ] && [ "$bad_rc" -eq 0 ]; then
    row A4 PASS "$walls wall verdict(s), 0 un-evidenced / 0 with a healthy account / 0 on a failed oracle" "$IDL"
  else
    row A4 FAIL "FALSE CLIFFS: no-evidence=$bad_noev healthy-account=$bad_healthy failed-oracle=$bad_rc" "$IDL"
  fi
}

# ── A5 — unknown is not a cliff (no page written for an `unknown` verdict) ───────────────────────
a5() {
  local unk
  unk="$(jq -r 'select(.actor=="cc-wave-plan" and .action=="wall" and .verdict=="unknown") | .ts' "$IDL" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$unk" -eq 0 ]; then
    row A5 NOT-RUN "no unknown-verdict recorded yet (oracle has not failed under v2)" "$IDL"; return
  fi
  if [ -f "$PAGES_DIR/cc-dispatch-quota-cliff.page" ]; then
    row A5 FAIL "$unk unknown verdict(s) but a quota-cliff page is standing — an unknown must never page" "$PAGES_DIR"
  else
    row A5 PASS "$unk unknown verdict(s), no quota-cliff page written" "$PAGES_DIR"
  fi
}

# ── A7 — the concurrency ceiling is enforced ─────────────────────────────────────────────────────
a7() {
  local over
  have_v2 || { row A7 NOT-RUN "no v2 decision records yet" "$IDL"; return; }
  over="$(jq -r --argjson c "$CEILING" 'select(.actor=="cc-dispatch" and .action=="decision" and .verdict=="admit")
          | select((.live_workers // 0) >= $c) | .ts' "$IDL" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$over" -eq 0 ]; then
    row A7 PASS "no admit recorded at or above ceiling $CEILING" "$IDL"
  else
    row A7 FAIL "$over admit(s) recorded while live_workers >= ceiling $CEILING" "$IDL"
  fi
}

# ── A8 — every oracle call site is bounded (a SOURCE read, provable before activation) ───────────
# Counts call sites of the account/route oracles that are NOT preceded by a timeout on the line.
a8() {
  local d="$REPO/bin/cc-dispatch" w="$REPO/bin/cc-wave-plan" unwrapped=0 f
  for f in "$d" "$w"; do
    [ -r "$f" ] || { row A8 NOT-RUN "source not readable: $f" "$f"; return; }
  done
  unwrapped="$(grep -hnE '(claude-accounts|\$\(accounts_bin\)|\$\(route_bin\)|"\$bin" --(rank|json))' "$d" "$w" 2>/dev/null \
    | grep -vE '^\s*#' | grep -vE 'timeout' | grep -cE '\$\(|"\$bin"' || true)"
  if [ "${unwrapped:-0}" -eq 0 ]; then
    row A8 PASS "0 unwrapped oracle call sites" "bin/cc-dispatch + bin/cc-wave-plan"
  else
    row A8 FAIL "$unwrapped oracle call site(s) not wrapped in timeout(1)" "bin/cc-dispatch + bin/cc-wave-plan"
  fi
}

# ── A11 — activation is real (loaded, not disabled, log non-empty) ──────────────────────────────
a11() {
  local lbl="com.claude.dispatcher" listed disabled log="/tmp/claude-dispatcher.stdout.log"
  listed="$("$LAUNCHCTL" list 2>/dev/null | grep -c "$lbl" || true)"
  disabled="$("$LAUNCHCTL" print-disabled "gui/$(id -u)" 2>/dev/null | grep "$lbl" | grep -c 'disabled' || true)"
  if [ "${listed:-0}" -eq 0 ] || [ "${disabled:-0}" -gt 0 ]; then
    row A11 NOT-RUN "dispatcher NOT activated (listed=$listed disabled=$disabled) — operator C10 step pending" "launchctl"
    return
  fi
  if [ -s "$log" ]; then
    row A11 PASS "label loaded + enabled; $log non-empty" "launchctl + $log"
  else
    row A11 FAIL "label loaded but $log is absent/empty — the job is not actually running" "$log"
  fi
}

render() {
  if [ "$JSON" -eq 1 ]; then
    printf '%s' "$ROWS" | while IFS=$'\t' read -r id v d s; do
      [ -n "$id" ] || continue
      jq -cn --arg id "$id" --arg v "$v" --arg d "$d" --arg s "$s" \
        '{criterion:$id, verdict:$v, detail:$d, source:$s}'
    done
    return
  fi
  echo "AUTONOMY_DISPATCH_V2 §7 — disk-truth acceptance reads"
  echo "  journal: $IDL"
  echo "  ledger : $BACKLOG"
  echo
  printf '%s' "$ROWS" | while IFS=$'\t' read -r id v d s; do
    [ -n "$id" ] || continue
    case "$v" in
      PASS)    printf '  \033[32m✓ %-4s PASS\033[0m    %s\n         └─ %s\n' "$id" "$d" "$s" ;;
      FAIL)    printf '  \033[31m✗ %-4s FAIL\033[0m    %s\n         └─ %s\n' "$id" "$d" "$s" ;;
      *)       printf '  \033[33m· %-4s NOT-RUN\033[0m %s\n         └─ %s\n' "$id" "$d" "$s" ;;
    esac
  done
  echo
  if [ "$FAILS" -eq 0 ]; then echo "  verdict=clean fails=0  (NOT-RUN rows are pending evidence, not failures)"
  else echo "  verdict=red fails=$FAILS"; fi
}

case "${1:-}" in
  --json) JSON=1 ;;
  -h|--help) sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  selftest) : ;;   # handled below
  '') : ;;
  *) echo "dispatch-acceptance: unknown arg $1" >&2; exit 2 ;;
esac

if [ "${1:-}" = selftest ]; then
  # Hermetic: every read is pointed at a fixture. Proves the reader DISCRIMINATES — a reader that
  # cannot fail is not evidence (memory: control-must-replay-the-real-artifact).
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-accept.XXXXXX")" || exit 3
  trap 'rm -rf "${tmp:-}"' EXIT
  pass=0; fail=0
  t() { if [ "$2" = "$3" ]; then printf '  ok   %s\n' "$1"; pass=$((pass+1)); else printf '  FAIL %s (want %s got %s)\n' "$1" "$3" "$2"; fail=$((fail+1)); fi; }

  # A4 negative: a `capped` verdict whose own evidence shows a healthy account IS a false cliff.
  printf '%s\n' '{"actor":"cc-wave-plan","action":"wall","verdict":"capped","ts":"2026-07-29T00:00:00Z","evidence":{"oracle_rc":0,"accounts":[{"acct":"next","state":"healthy","k":0}]}}' > "$tmp/idl-false.jsonl"
  got="$(CC_DISPATCH_IDL="$tmp/idl-false.jsonl" CC_BACKLOG_FILE="$tmp/none.jsonl" "$0" --json 2>/dev/null | jq -r 'select(.criterion=="A4")|.verdict')"
  t "A4 flags a capped verdict with a healthy account as FAIL" "$got" "FAIL"

  # A4 positive control: the SAME reader passes a properly-evidenced capped verdict.
  printf '%s\n' '{"actor":"cc-wave-plan","action":"wall","verdict":"capped","ts":"2026-07-29T00:00:00Z","evidence":{"oracle_rc":0,"accounts":[{"acct":"next","state":"capped","k":2}]}}' > "$tmp/idl-true.jsonl"
  got="$(CC_DISPATCH_IDL="$tmp/idl-true.jsonl" CC_BACKLOG_FILE="$tmp/none.jsonl" "$0" --json 2>/dev/null | jq -r 'select(.criterion=="A4")|.verdict')"
  t "A4 passes a genuinely-evidenced capped verdict" "$got" "PASS"

  # A4 non-verdict: no wall records at all is NOT-RUN — never PASS (the honest-direction rule).
  : > "$tmp/idl-empty.jsonl"
  got="$(CC_DISPATCH_IDL="$tmp/idl-empty.jsonl" CC_BACKLOG_FILE="$tmp/none.jsonl" "$0" --json 2>/dev/null | jq -r 'select(.criterion=="A4")|.verdict')"
  t "A4 with no evidence is NOT-RUN, never PASS" "$got" "NOT-RUN"

  # A4 un-evidenced capped (the incumbent's exact record shape) must FAIL.
  printf '%s\n' '{"actor":"cc-wave-plan","action":"wall","verdict":"capped","ts":"2026-07-29T00:00:00Z"}' > "$tmp/idl-noev.jsonl"
  got="$(CC_DISPATCH_IDL="$tmp/idl-noev.jsonl" CC_BACKLOG_FILE="$tmp/none.jsonl" "$0" --json 2>/dev/null | jq -r 'select(.criterion=="A4")|.verdict')"
  t "A4 flags an un-evidenced capped verdict as FAIL" "$got" "FAIL"

  # A11 discriminates not-activated from running, via a stubbed launchctl (never the real one).
  printf '#!/bin/bash\nexit 0\n' > "$tmp/lc-absent"; chmod +x "$tmp/lc-absent"
  got="$(CC_ACCEPT_LAUNCHCTL="$tmp/lc-absent" CC_DISPATCH_IDL="$tmp/idl-empty.jsonl" CC_BACKLOG_FILE="$tmp/none.jsonl" "$0" --json 2>/dev/null | jq -r 'select(.criterion=="A11")|.verdict')"
  t "A11 reports NOT-RUN when the label is absent" "$got" "NOT-RUN"

  # exit code: a FAIL row must make the reader exit non-zero (it gates, it does not merely print).
  CC_DISPATCH_IDL="$tmp/idl-false.jsonl" CC_BACKLOG_FILE="$tmp/none.jsonl" "$0" >/dev/null 2>&1
  t "a FAIL row exits non-zero" "$?" "1"

  echo "dispatch-acceptance selftest: $pass passed, $fail failed"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
fi

a1; a2; a3; a4; a5; a7; a8; a11
render
[ "$FAILS" -eq 0 ] || exit 1
exit 0
