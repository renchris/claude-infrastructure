#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `cond && okp || badp` reporter idiom (okp/badp always return 0)
# idl-abstain-alarm.sh — T-P6-4 / "abstain-alarm D9": the IDL abstention monitor.
#
# WHY (blind-check law §3i, boundary-handoff:17-19): a check whose whole job is to FIRE
# but which ABSTAINS 100% of the time is indistinguishable from a DEAD check — "didn't
# fire" and "never evaluated" are the same observation. The canonical incident (P0-1):
# the gate-green producer was never wired, so boundary-handoff abstained 100% in prod
# ("gate-not-green-at-head" / "no-telemetry") — FM1(b) silently inert behind a green
# selftest. This monitor sweeps the IDL and PAGES (via the nightly-regression host) when
# a check is PROVABLY inert.
#
# THE FALSE-POSITIVE TRAP (boundary-handoff:41-49, re-observed 2026-07-19): the naive
# rule "abstained==100% over N>=10 REGARDLESS of reason" is a STRUCTURAL false positive.
# Every live hook is at 100% abstained today — waiting-recycle (not-armed),
# boundary-handoff (below-threshold), completion-assert (ledger-clean/no-close-tell),
# anti-deference-nudge (no-tell) — all HEALTHY-DORMANT (the guard WAS evaluated and the
# fire condition was legitimately false). A regardless-of-reason alarm would page on all
# four every night. So this monitor DISCRIMINATES the abstention REASON:
#   BLIND    — the check could not OBSERVE its guard at all (missing input / telemetry /
#              transcript / repo). 100%-blind over N>=10 == "no check" == INERT == PAGE.
#   DORMANT  — the guard WAS reached; the fire condition was legitimately not met.
#              100%-dormant is a healthy quiet advisory — NEVER a page.
# A single DORMANT abstention proves the check CAN reach its guard, so a hook is inert
# only when EVERY in-window abstention is blind (blind_share >= CC_ABSTAIN_BLIND_PCT,
# default 100). New/unclassified reasons default to DORMANT (fail toward NOT paging) and
# are surfaced in the DORMANT-100 report line for human review — no silent 3am false page.
#
# VERDICT per hook, over the lookback window (schema = objects with BOTH .hook + .disposition):
#   INERT (RED, exit!=0)   total>=N_MIN AND abstained==total AND blind_share>=BLIND_PCT
#   DORMANT-100 (green)    total>=N_MIN AND abstained==total AND blind_share< BLIND_PCT   (reported, not paged)
#   HEALTHY (green)        has fired/passed, OR total<N_MIN
#
# Read-only. Appends one summary line to CC_ABSTAIN_LOG. On >=1 INERT hook it prints the
# inert hook(s) and exits non-zero, so the nightly-regression host writes ONE page to
# autonomy/pages/ (drainable by the P0-15 desk consumer). C10: no live edits — the
# already-loaded nightly-regression plist runs THIS repo script (no re-install needed).
#
# Modes: --run (default; live sweep, exit reflects inert) · --report (table, ALWAYS exit 0) ·
#        --selftest (RED-provable, side-effect-free).
# Env seams (tests + tuning): CC_IDL · CC_ABSTAIN_LOG · CC_ABSTAIN_NMIN (10) ·
#        CC_ABSTAIN_LOOKBACK_DAYS (14) · CC_ABSTAIN_BLIND_PCT (100) ·
#        CC_ABSTAIN_BLIND_REASONS (space/newline list — REPLACES the default blind set) ·
#        CC_ABSTAIN_NOW (epoch — deterministic "now" for tests).
set -uo pipefail

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
IDL="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
LOG="${CC_ABSTAIN_LOG:-$HOME/.claude/autonomy/abstain-alarm.log}"
NMIN="${CC_ABSTAIN_NMIN:-10}"
LOOKBACK_DAYS="${CC_ABSTAIN_LOOKBACK_DAYS:-14}"
BLIND_PCT="${CC_ABSTAIN_BLIND_PCT:-100}"

# BLIND reason-tokens (matched against the reason substring BEFORE the first ':'). These are
# the unambiguous "could not observe my guard" reasons drawn from the live hook vocabulary
# (boundary-handoff / anti-deference-nudge / completion-assert / waiting-recycle). Everything
# NOT listed is treated as DORMANT (condition-not-met) — conservative against false pages.
_default_blind=(no-jq no-session-id no-stdin no-telemetry stale-telemetry \
                no-transcript-path transcript-missing not-a-repo no-cwd no-assistant-text)
if [ -n "${CC_ABSTAIN_BLIND_REASONS:-}" ]; then
  # shellcheck disable=SC2206  # intentional word-split of the override list
  BLIND=($CC_ABSTAIN_BLIND_REASONS)
else
  BLIND=("${_default_blind[@]}")
fi
BLIND_JSON="$(printf '%s\n' "${BLIND[@]}" | jq -Rsc 'split("\n")|map(select(length>0))')"

now_epoch() { echo "${CC_ABSTAIN_NOW:-$(date +%s)}"; }
now_iso()   { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ── the sweep: aggregate the IDL per hook, classify, report, and set the exit code ──
# $1 = mode: "run" (exit reflects inert) | "report" (always 0)
sweep() {
  local mode="${1:-run}"
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

  command -v jq >/dev/null 2>&1 || {
    # No jq: this monitor cannot observe ITS OWN guard — fail loud, not silent-green.
    printf 'idl-abstain-alarm: RED — jq unavailable, cannot sweep the IDL (self-blind)\n'
    printf '%s idl-abstain-alarm: RED self-blind (no-jq)\n' "$(now_iso)" >> "$LOG" 2>/dev/null || true
    [ "$mode" = report ] && return 0 || return 1
  }

  if [ ! -f "$IDL" ] || [ ! -s "$IDL" ]; then
    printf 'idl-abstain-alarm: GREEN — no IDL at %s (nothing to sweep)\n' "$IDL"
    printf '%s idl-abstain-alarm: GREEN no-idl\n' "$(now_iso)" >> "$LOG" 2>/dev/null || true
    return 0
  fi

  local now cutoff
  now="$(now_epoch)"
  cutoff="$(( now - LOOKBACK_DAYS * 86400 ))"

  # malformed-line accounting (plan ethos: report, never silently drop)
  local raw parsed malformed
  raw="$(grep -cve '^[[:space:]]*$' "$IDL" 2>/dev/null || echo 0)"
  parsed="$(jq -R 'fromjson? // empty' "$IDL" 2>/dev/null | grep -c . || echo 0)"
  malformed="$(( raw - parsed ))"; [ "$malformed" -lt 0 ] && malformed=0

  # one jq pass → one TSV row per hook: hook total abstained productive failed blind
  local agg
  agg="$(jq -Rrn --argjson cutoff "$cutoff" --argjson blind "$BLIND_JSON" '
    [ inputs
      | (fromjson? // null) | select(. != null)
      | select((.hook? != null) and (.disposition? != null))
      | select(((.ts // "") | fromdateiso8601? // 0) >= $cutoff)
      | { hook: .hook, disp: .disposition, rt: ((.reason // "") | split(":")[0]) } ]
    | group_by(.hook)
    | map(. as $g | {
        hook:       $g[0].hook,
        total:      ($g | length),
        abstained:  ([ $g[] | select(.disp=="abstained") ] | length),
        productive: ([ $g[] | select(.disp=="fired" or .disp=="passed") ] | length),
        failed:     ([ $g[] | select(.disp=="failed") ] | length),
        blind:      ([ $g[] | select(.disp=="abstained")
                            | select(.rt as $x | ($blind | index($x)) != null) ] | length) })
    | .[]
    | [ .hook, .total, .abstained, .productive, .failed, .blind ] | @tsv
  ' "$IDL" 2>/dev/null || true)"

  local -a inert=() dormant100=()
  local nhooks=0 healthy=0
  local hook total abst prod failed blind pct verdict
  while IFS=$'\t' read -r hook total abst prod failed blind; do
    [ -n "$hook" ] || continue
    nhooks=$(( nhooks + 1 ))
    pct=0; [ "$abst" -gt 0 ] && pct=$(( blind * 100 / abst ))
    if   [ "$total" -ge "$NMIN" ] && [ "$abst" -eq "$total" ] && [ "$pct" -ge "$BLIND_PCT" ]; then
      verdict=INERT;       inert+=("$hook")
    elif [ "$total" -ge "$NMIN" ] && [ "$abst" -eq "$total" ]; then
      verdict=DORMANT-100; dormant100+=("$hook")
    else
      verdict=HEALTHY;     healthy=$(( healthy + 1 ))
    fi
    printf '  %-11s %-22s total=%-4s abst=%-4s fired/passed=%-3s failed=%-3s blind=%-3s (%d%%)\n' \
      "$verdict" "$hook" "$total" "$abst" "$prod" "$failed" "$blind" "$pct"
  done <<< "$agg"

  local n_inert="${#inert[@]}" summary
  summary="hooks=$nhooks inert=$n_inert dormant100=${#dormant100[@]} healthy=$healthy window=${LOOKBACK_DAYS}d nmin=$NMIN blind_pct=$BLIND_PCT"
  [ "$malformed" -gt 0 ]      && summary="$summary malformed=$malformed"
  [ "$n_inert" -gt 0 ]        && summary="$summary INERT:[${inert[*]}]"
  [ "${#dormant100[@]}" -gt 0 ] && summary="$summary DORMANT-100:[${dormant100[*]}]"
  printf '%s idl-abstain-alarm: %s\n' "$(now_iso)" "$summary" >> "$LOG" 2>/dev/null || true

  if [ "$n_inert" -gt 0 ]; then
    printf 'idl-abstain-alarm: RED — %d inert check(s): %s\n' "$n_inert" "${inert[*]}"
    printf '  each abstained 100%% over >=%d evals with ONLY blind (cannot-observe) reasons — a check\n' "$NMIN"
    printf '  that cannot see its guard is no check (blind-check law §3i). detail: %s\n' "$LOG"
    [ "$mode" = report ] && return 0 || return 1
  fi
  printf 'idl-abstain-alarm: GREEN — %s\n' "$summary"
  return 0
}

# ════════════════ selftest — RED-prove the discriminator (deterministic, side-effect-free) ═════════
PASS=0; FAIL=0
# shellcheck disable=SC2317  # reached only in --selftest
okp()  { printf '  ok   %-58s\n' "$1"; PASS=$(( PASS + 1 )); }
# shellcheck disable=SC2317
badp() { printf '  FAIL %-58s\n' "$1"; FAIL=$(( FAIL + 1 )); }
# shellcheck disable=SC2317
selftest() {
  local d; d="$(mktemp -d "${TMPDIR:-/tmp}/abstain-alarm-selftest.XXXXXX")" || { echo mktemp failed; exit 1; }
  # shellcheck disable=SC2064
  trap "rm -rf '$d'" EXIT
  local NOW=1752900000 FIXTS OLDTS
  FIXTS="$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 2026-07-19T04:00:00Z)"
  OLDTS="$(date -u -r "$(( NOW - 30 * 86400 ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo 2026-06-19T04:00:00Z)"

  emit() { # <file> <n> <hook> <disp> <reason> [ts]
    local i ts="${6:-$FIXTS}"
    for ((i = 0; i < $2; i++)); do
      printf '{"ts":"%s","hook":"%s","sid":"s%d","disposition":"%s","reason":"%s"}\n' \
        "$ts" "$3" "$i" "$4" "$5" >> "$1"
    done
  }
  run_alarm() { # <idl> [mode-arg] → runs the real script with a fixed clock
    env CC_IDL="$1" CC_ABSTAIN_NOW="$NOW" CC_ABSTAIN_LOG="$d/log" CC_ABSTAIN_NMIN=10 \
        CC_ABSTAIN_LOOKBACK_DAYS=14 CC_ABSTAIN_BLIND_PCT=100 "$SELF" "${2:---run}"
  }

  echo "idl-abstain-alarm --selftest:"

  # A. 100%-blind over N>=10 → INERT (RED, names the hook)
  local A="$d/a.jsonl"; emit "$A" 12 inert-hook abstained no-telemetry
  local out rc
  out="$(run_alarm "$A")"; rc=$?
  [ "$rc" -ne 0 ]                              && okp "A blind-100 → nonzero exit" || badp "A blind-100 exited 0"
  printf '%s' "$out" | grep -q 'inert-hook'    && okp "A blind-100 → names the inert hook" || badp "A did not name inert-hook"
  printf '%s' "$out" | grep -q 'INERT'         && okp "A blind-100 → INERT verdict printed" || badp "A no INERT verdict"

  # B. 100%-dormant over N>=10 → GREEN, NOT flagged (the boundary-handoff false-positive guard)
  local B="$d/b.jsonl"; emit "$B" 12 dormant-hook abstained below-threshold
  out="$(run_alarm "$B")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "B dormant-100 → exit 0" || badp "B dormant-100 nonzero exit"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "B dormant-100 → no INERT flag" || badp "B falsely flagged dormant as INERT"
  printf '%s' "$out" | grep -q 'DORMANT-100'   && okp "B dormant-100 → reported DORMANT-100" || badp "B not reported DORMANT-100"

  # C. mixed: 11 dormant + 1 blind (blind_share ~8% < 100) → GREEN (one dormant proves it can observe)
  local C="$d/c.jsonl"; emit "$C" 11 mixed-hook abstained below-threshold; emit "$C" 1 mixed-hook abstained no-telemetry
  out="$(run_alarm "$C")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "C mixed(1 blind) → exit 0" || badp "C mixed exited nonzero"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "C mixed → not INERT" || badp "C mixed wrongly INERT"

  # D. sub-threshold: 5 blind (< NMIN=10) → GREEN (insufficient evidence)
  local D="$d/d.jsonl"; emit "$D" 5 rare-hook abstained no-telemetry
  out="$(run_alarm "$D")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "D sub-threshold blind → exit 0" || badp "D sub-threshold nonzero"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "D sub-threshold → not INERT" || badp "D sub-threshold wrongly INERT"

  # E. has a fire: 5 fired + 7 blind-abstained (abst!=total) → HEALTHY
  local E="$d/e.jsonl"; emit "$E" 5 firing-hook fired ok; emit "$E" 7 firing-hook abstained no-telemetry
  out="$(run_alarm "$E")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "E has-fired → exit 0" || badp "E has-fired nonzero"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "E has-fired → not INERT" || badp "E has-fired wrongly INERT"

  # F. outside the window: 12 blind but OLD ts → excluded → GREEN
  local F="$d/f.jsonl"; emit "$F" 12 stale-hook abstained no-telemetry "$OLDTS"
  out="$(run_alarm "$F")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "F outside-window → exit 0" || badp "F outside-window nonzero"
  ! printf '%s' "$out" | grep -q 'INERT'       && okp "F outside-window → excluded" || badp "F outside-window not excluded"

  # G. non-hook schema (supervisor/checkpoint lines) → ignored → GREEN
  local G="$d/g.jsonl"; local i
  for ((i = 0; i < 12; i++)); do
    printf '{"ts":"%s","actor":"lead-supervisor","kind":"checkpoint","sid":"s%d"}\n' "$FIXTS" "$i" >> "$G"
  done
  out="$(run_alarm "$G")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "G non-hook lines → exit 0" || badp "G non-hook nonzero"
  printf '%s' "$out" | grep -q 'hooks=0'       && okp "G non-hook lines → hooks=0 (ignored)" || badp "G non-hook lines counted"

  # H. a malformed line does not crash the sweep; valid inert hook still detected
  local H="$d/h.jsonl"; emit "$H" 12 inert2 abstained no-transcript-path; printf '{bad json not closed\n' >> "$H"
  out="$(run_alarm "$H")"; rc=$?
  [ "$rc" -ne 0 ]                              && okp "H malformed+inert → still RED (no crash)" || badp "H malformed swallowed the inert signal"
  printf '%s' "$out" | grep -q 'inert2'        && okp "H malformed → valid line still swept" || badp "H malformed dropped valid line"

  # I. missing IDL → GREEN
  out="$(run_alarm "$d/does-not-exist.jsonl")"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "I missing IDL → exit 0" || badp "I missing IDL nonzero"
  printf '%s' "$out" | grep -q 'no IDL'        && okp "I missing IDL → green no-idl message" || badp "I missing IDL wrong message"

  # J. --report NEVER fails, even with an inert hook present
  out="$(run_alarm "$A" --report)"; rc=$?
  [ "$rc" -eq 0 ]                              && okp "J --report over inert → exit 0 (never pages)" || badp "J --report exited nonzero"
  printf '%s' "$out" | grep -q 'INERT'         && okp "J --report still SHOWS the inert hook" || badp "J --report hid the inert hook"

  # K. combined INERT + DORMANT in one file → RED, names ONLY the inert
  local K="$d/k.jsonl"; emit "$K" 12 real-inert abstained no-cwd; emit "$K" 12 fine-dormant abstained not-armed
  out="$(run_alarm "$K")"; rc=$?
  [ "$rc" -ne 0 ]                              && okp "K combined → RED" || badp "K combined not RED"
  printf '%s' "$out" | grep -qE '1 inert check\(s\): .*real-inert' && okp "K combined → names ONLY real-inert (1 inert)" || badp "K combined did not name exactly real-inert"

  # L. custom blind override: a normally-DORMANT reason becomes blind via env → INERT
  local L="$d/l.jsonl"; emit "$L" 12 custom-hook abstained widget-missing
  out="$(env CC_IDL="$L" CC_ABSTAIN_NOW="$NOW" CC_ABSTAIN_LOG="$d/log" CC_ABSTAIN_NMIN=10 \
            CC_ABSTAIN_BLIND_REASONS="widget-missing" "$SELF" --run)"; rc=$?
  [ "$rc" -ne 0 ]                              && okp "L blind-override → INERT on custom reason" || badp "L blind-override did not fire"

  echo "idl-abstain-alarm --selftest: $PASS passed, $FAIL failed"
  [ "$FAIL" -eq 0 ] || exit 1
  echo "idl-abstain-alarm --selftest: GREEN — blind-100 pages, dormant-100 suppressed, mixed/sub-threshold/window/non-hook/malformed/override all correct."
}

case "${1:-}" in
  --selftest) selftest ;;
  --report)   sweep report ;;
  ""|--run)   sweep run ;;
  *) printf 'idl-abstain-alarm: unknown arg %s (use --run | --report | --selftest)\n' "$1" >&2; exit 2 ;;
esac
