#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `cmd && okp || badp` reporter idiom
# power-policy-verify.sh — T-P16-3: verify the machine-awake power policy + PAGE on drift.
#
# Two reads, one page channel:
#   (A) the AC (`-c`/charger) pmset policy matches intent — the load-bearing 24/7 keys (p16 G-P16-3):
#         sleep=0  displaysleep=0  disablesleep=0    (a key absent from the AC block ⇒ macOS default 0)
#       The one-time `sudo pmset -c ...` apply is the OPERATOR's (C10): a user LaunchAgent has no root,
#       so this job cannot re-apply — it VERIFIES and PAGES with the exact remediation command. Why a
#       laptop drifts: an OS update / SMC-NVRAM reset / a new machine silently reverts pmset to the
#       default idle-sleep profile, and the AC `sleep 0` is otherwise an out-of-band manual setting.
#   (B) the caffeinate idle-sleep FLOOR (T-P16-4) — reported INFORMATIONALLY (delegates to
#       caffeinate-floor.sh --verify). The floor's own liveness guarantee is its plist KeepAlive; a
#       floor-absent line is logged/printed but does NOT page (avoids an activation-ordering false page
#       before the floor plist is loaded). pmset drift is the sole paging condition.
#
# ON DRIFT (A): write an epoch-headed page to autonomy/pages/ (drained by the P0-15 desk-role consumer
#   / autonomy-sweep) + an osascript OS-level notification; exit 1. GREEN clears a prior standing page.
# ABSTAIN (exit 3): pmset produced no "AC Power:" block — the check cannot observe what it guards, so
#   it fails LOUD rather than false-green (blind-check law §3i). Never pages a drift it could not read.
# C10: OPERATOR loads the plist (RunAtLoad + hourly re-check). Selftest: `--selftest` (fixture-driven).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# intended AC policy — the load-bearing keys, "key=value …"; override via env for tests.
INTENDED_AC="${CC_PMSET_INTENDED_AC:-sleep=0 displaysleep=0 disablesleep=0}"
REMEDIATE="${CC_PMSET_REMEDIATE:-sudo pmset -c sleep 0 displaysleep 0 disablesleep 0}"
PAGEDIR="${CC_PPV_PAGEDIR:-$HOME/.claude/autonomy/pages}"
LOG="${CC_PPV_LOG:-$HOME/.claude/autonomy/power-policy.log}"
NOTIFY_CMD="${CC_PPV_NOTIFY:-}"                       # empty → builtin osascript
PAGE_KEY="${CC_PPV_PAGE_KEY:-power-policy}"
# stubbable commands (arrays so word-splitting is shellcheck-clean):
read -r -a PMSET_CMD    <<< "${CC_PMSET_CMD:-pmset -g custom}"
read -r -a FLOOR_VERIFY <<< "${CC_FLOOR_VERIFY_CMD:-$REPO/scripts/caffeinate-floor.sh --verify}"

now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
now_epoch() { date +%s; }

notify() { # <title> <msg> — OS-level, API-independent
  local title="$1" msg="$2"
  if [ -n "$NOTIFY_CMD" ]; then "$NOTIFY_CMD" "$title" "$msg" >/dev/null 2>&1 || true; return 0; fi
  command -v osascript >/dev/null 2>&1 && \
    osascript -e "display notification \"${msg//\"/}\" with title \"${title//\"/}\"" >/dev/null 2>&1 || true
}

# ac_block — print the body lines of the "AC Power:" section of a pmset -g custom capture (<file>).
ac_block() { awk '/^AC Power:/{inac=1;next} /^[A-Za-z].*Power:[[:space:]]*$/{inac=0} inac' "$1"; }

# ac_value — value of a single-token key in the AC block; absent ⇒ "0" (the macOS default-off state).
ac_value() { # <key> <file>
  ac_block "$2" | awk -v k="$1" '$1==k{print $NF; f=1; exit} END{if(!f) print "0"}'
}

verify() {
  mkdir -p "$PAGEDIR" "$(dirname "$LOG")" 2>/dev/null || true
  local f; f="$(mktemp "${TMPDIR:-/tmp}/power-policy.XXXXXX")" || { echo "mktemp failed" >&2; exit 3; }
  # shellcheck disable=SC2064
  trap "rm -f '$f'" RETURN
  "${PMSET_CMD[@]}" > "$f" 2>/dev/null || true

  # ABSTAIN if we cannot even see the AC block — a check that cannot observe what it guards is no check.
  if [ -z "$(ac_block "$f")" ]; then
    printf 'power-policy: ABSTAIN — no "AC Power:" block from [%s] (cannot verify; NOT paging)\n' "${PMSET_CMD[*]}"
    printf '%s power-policy: ABSTAIN (no AC block)\n' "$(now_iso)" >> "$LOG"
    return 3
  fi

  # (A) pmset AC drift
  local drift="" pair key want got
  for pair in $INTENDED_AC; do
    key="${pair%%=*}"; want="${pair#*=}"
    got="$(ac_value "$key" "$f")"
    if [ "$got" != "$want" ]; then
      drift="$drift AC:$key=$got(want=$want)"
      printf '  DRIFT AC %s = %s (want %s)\n' "$key" "$got" "$want"
    else
      printf '  ok    AC %s = %s\n' "$key" "$got"
    fi
  done

  # (B) caffeinate floor — INFORMATIONAL only (never pages; KeepAlive is its liveness guarantee)
  if "${FLOOR_VERIFY[@]}" >/dev/null 2>&1; then
    printf '  ok    caffeinate floor PRESENT\n'
  else
    printf '  note  caffeinate floor ABSENT (KeepAlive should relaunch it; load com.claude.caffeinate-floor if not)\n'
  fi

  local pf="$PAGEDIR/$PAGE_KEY.page"
  if [ -n "$drift" ]; then
    { now_epoch
      printf 'power-policy DRIFT @ %s:%s\n' "$(now_iso)" "$drift"
      printf 'remediate (operator, one-time root): %s\n' "$REMEDIATE"
      printf 're-verify: %s --verify\n' "$SELF"
    } > "$pf"
    notify "Claude power-policy DRIFT" "AC pmset reverted:$drift — run: $REMEDIATE"
    printf '%s power-policy: DRIFT —%s\n' "$(now_iso)" "$drift" >> "$LOG"
    printf 'power-policy: DRIFT —%s — remediate: %s\n' "$drift" "$REMEDIATE"
    return 1
  fi
  rm -f "$pf" 2>/dev/null || true                    # green run clears a prior standing page
  printf '%s power-policy: GREEN (AC policy matches intent)\n' "$(now_iso)" >> "$LOG"
  printf 'power-policy: GREEN — AC policy matches intent (%s)\n' "$INTENDED_AC"
  return 0
}

# ════ selftest — RED-prove: match→GREEN(no page); reverted key→DRIFT(page,epoch-headed); no AC→ABSTAIN
PASS=0; FAIL=0
# shellcheck disable=SC2317
okp()  { printf '  ok   %-56s\n' "$1"; PASS=$((PASS+1)); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-56s\n' "$1"; FAIL=$((FAIL+1)); }
# shellcheck disable=SC2317
selftest() {
  local d rc out pf; d="$(mktemp -d "${TMPDIR:-/tmp}/power-policy-selftest.XXXXXX")" || { echo mktemp; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  pf="$d/pages/$PAGE_KEY.page"
  echo "power-policy-verify --selftest:"

  # fixtures in pmset -g custom format
  printf 'Battery Power:\n sleep                1\n displaysleep         0\nAC Power:\n sleep                0\n displaysleep         0\n' > "$d/good.txt"
  printf 'Battery Power:\n sleep                1\nAC Power:\n sleep                10\n displaysleep         0\n' > "$d/reverted.txt"
  printf 'Battery Power:\n sleep                1\n displaysleep         0\n' > "$d/noac.txt"

  run_v() { # <pmset-fixture> <floor-verdict-bin> → runs verify with everything stubbed
    env CC_PMSET_CMD="cat $1" CC_FLOOR_VERIFY_CMD="$2" CC_PPV_NOTIFY=/usr/bin/true \
        CC_PPV_PAGEDIR="$d/pages" CC_PPV_LOG="$d/pp.log" "$SELF" --verify 2>&1
  }

  # GREEN: intent matches (disablesleep absent → 0), floor present → exit 0, NO page
  out="$(run_v "$d/good.txt" /usr/bin/true)"; rc=$?
  [ "$rc" -eq 0 ] && okp "match + floor present → exit 0 (GREEN)" || badp "GREEN path exit $rc (want 0)"
  [ ! -f "$pf" ] && okp "GREEN writes NO page" || badp "GREEN wrongly wrote a page"
  printf '%s' "$out" | grep -q 'GREEN' && okp "GREEN report line present" || badp "no GREEN line"

  # floor-absent must NOT flip the verdict (informational only) — still GREEN, still no page
  out="$(run_v "$d/good.txt" /usr/bin/false)"; rc=$?
  [ "$rc" -eq 0 ] && okp "floor ABSENT does NOT page (informational) → exit 0" || badp "floor-absent wrongly paged (exit $rc)"
  printf '%s' "$out" | grep -q 'floor ABSENT' && okp "floor-absent reported as a note" || badp "floor-absent note missing"

  # DRIFT: AC sleep=10 → exit 1, page written, epoch-headed, remediation named, dir named
  out="$(run_v "$d/reverted.txt" /usr/bin/true)"; rc=$?
  [ "$rc" -eq 1 ] && okp "reverted AC sleep → exit 1 (DRIFT)" || badp "DRIFT not caught (exit $rc)"
  [ -f "$pf" ] && okp "DRIFT writes a page to pages/" || badp "DRIFT wrote no page"
  head -1 "$pf" 2>/dev/null | grep -qE '^[0-9]+$' && okp "page first line is an epoch (consumer convention)" || badp "page not epoch-headed"
  grep -q 'sudo pmset -c' "$pf" 2>/dev/null && okp "page names the sudo remediation" || badp "page missing remediation"
  printf '%s' "$out" | grep -qE 'DRIFT AC sleep = 10' && okp "report names the drifted key+value" || badp "report missing key detail"

  # GREEN after a DRIFT clears the standing page
  run_v "$d/good.txt" /usr/bin/true >/dev/null 2>&1
  [ ! -f "$pf" ] && okp "a subsequent GREEN clears the standing page" || badp "stale page survived a GREEN run"

  # ABSTAIN: no AC block → exit 3, no page, no false-green
  out="$(run_v "$d/noac.txt" /usr/bin/true)"; rc=$?
  [ "$rc" -eq 3 ] && okp "no AC block → exit 3 (ABSTAIN)" || badp "no-AC not abstained (exit $rc)"
  [ ! -f "$pf" ] && okp "ABSTAIN writes no page" || badp "ABSTAIN wrote a page"
  printf '%s' "$out" | grep -q 'ABSTAIN' && okp "ABSTAIN report line present" || badp "no ABSTAIN line"

  echo "power-policy-verify --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "power-policy-verify --selftest: GREEN — match passes; reverted key pages (epoch-headed, remediation named); floor-absent is informational; no-AC abstains."
}

case "${1:-}" in
  --selftest) selftest ;;
  ""|--verify) verify ;;
  *) printf 'power-policy-verify: unknown arg %s (use --verify | --selftest)\n' "$1" >&2; exit 2 ;;
esac
