#!/bin/bash
# kalloc-slo.sh — the loop that keeps the #! kernel-leak cut from eroding (REPORT §3 Phase 5,
# docs/research/kalloc-longterm-2026-10-21/REPORT.md; plan docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md W5).
#
# macOS 15.8.1 keeps ~1.1 KiB of data.kalloc.1024 for every #! script the kernel execs by path, until
# reboot, and ~20 GiB panics the Mac. Waves W1-W4 cut the sources; the workload's mix moved 3-8x
# between 10-minute windows and no lint sees every new source, so this checks the OUTCOME instead:
#   · TARGET  the 7-day median rate per boot-day stays <= 0.30 GiB/day. Each of the last 7 days is
#             fitted on its own boot's rows only (a reboot drops the zone, and a fit across it is
#             garbage) and counts when the fit spans >= 12 h; the median needs >= 4 such days.
#             Reported, never filed: it lags, the two legs below lead.
#   · BREACH  the trailing-24-h slope of THIS boot > 0.45 GiB/day, or growth per Bash call over that
#             span > 1.5x the previous boot's last 24 h. The per-call leg is what separates a new
#             leaking source from a busier fleet; it is kalloc-leak-rate.sh --span on both sides, so
#             one instrument measures both.
#   · ABSTAIN when the boot is under ~22 h old (the 24-h fit must span 90% of a day), the series is
#             unreadable, or the boot epoch is unknown. Abstain is its own verdict, printed and stored
#             with its reason, never rendered as OK and never filed as a breach. A per-call leg that
#             cannot be computed (no previous boot in the series, no Bash log) is named in the line;
#             the slope leg alone then decides OK.
# Inputs need no root: the zone series capacity-alarm.sh writes (~900 s, measured reads only) and
# bash-commands.log. On a breach it files ONE operator row carrying the census command, deduped:
# while the row it filed is still live, and for REFILE_S after it closes, nothing new is filed. It
# never runs the census (that needs sudo and the operator's window).
#
# Usage: kalloc-slo.sh [--force] [--no-file] [--now EPOCH] [--boot EPOCH] [--series TSV]
#                      [--bash-log LOG] [--state FILE]
#   --force    evaluate even inside the damping interval (default: once per CC_KALLOC_SLO_MIN_S=3600)
#   --no-file  compute and print, write the state, file nothing
# Prints `kalloc-slo: verdict=<ok|breach|abstain> …` (or `damped verdict=<last>` inside the interval).
# Exit: 0 ok or damped · 1 breach · 3 abstain · 2 usage
# Seams: CC_KALLOC_SLO_TARGET_GIB (0.30) · CC_KALLOC_SLO_BREACH_GIB (0.45) · CC_KALLOC_SLO_CALL_RATIO (1.5)
#        CC_KALLOC_SLO_MIN_S (3600) · CC_KALLOC_SLO_REFILE_S (604800) · CC_KALLOC_SLO_BACKLOG (cc-backlog)
#        CC_KALLOC_SLO_LOG (one line per evaluation; default ~/.claude/logs/kalloc-slo.log)
# Runs under /bin/bash 3.2 (capacity-alarm's launchd tick): no arrays, no bash-4 syntax.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERIES="$HOME/.claude/logs/kalloc-zone-series.tsv"
BLOG="$HOME/.claude/logs/bash-commands.log"
STATE="$(dirname "${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}")/kalloc-slo.state"
NOW="" BOOT="" FORCE=0 FILE=1
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --no-file) FILE=0; shift ;;
    --now) NOW="${2:-}"; shift 2 ;;
    --boot) BOOT="${2:-}"; shift 2 ;;
    --series) SERIES="${2:-}"; shift 2 ;;
    --bash-log) BLOG="${2:-}"; shift 2 ;;
    --state) STATE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    *) echo "kalloc-slo: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -n "$NOW" ] || NOW="$(date +%s)"
case "$NOW" in *[!0-9]*) echo "kalloc-slo: --now must be an epoch" >&2; exit 2 ;; esac
if [ -z "$BOOT" ]; then
  BOOT="$(/usr/sbin/sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \([0-9][0-9]*\),.*/\1/p' | head -1)"
fi
case "$BOOT" in *[!0-9]*) BOOT="" ;; esac

TARGET="${CC_KALLOC_SLO_TARGET_GIB:-0.30}"
BREACH="${CC_KALLOC_SLO_BREACH_GIB:-0.45}"
RATIO_MAX="${CC_KALLOC_SLO_CALL_RATIO:-1.5}"
MIN_S="${CC_KALLOC_SLO_MIN_S:-3600}"
REFILE_S="${CC_KALLOC_SLO_REFILE_S:-604800}"
case "$MIN_S" in ''|*[!0-9]*) MIN_S=3600 ;; esac
case "$REFILE_S" in ''|*[!0-9]*) REFILE_S=604800 ;; esac
RATE="$HERE/kalloc-leak-rate.sh"
BLG="${CC_KALLOC_SLO_BACKLOG:-$HERE/../bin/cc-backlog}"
SLOG="${CC_KALLOC_SLO_LOG:-$HOME/.claude/logs/kalloc-slo.log}"
# Absolute: cc-do runs a row's command with `bash -c` in whatever directory the operator is in.
RUN="bash $HERE/kalloc-exec-census.sh 600"
TITLE="kalloc #! leak SLO breached: run the 10-minute exec census (sudo, read-only) so the new top sources can be cut — numbers in ~/.claude/autonomy/kalloc-slo.state"

st() { # <key> → the value from the state file, or nothing
  [ -r "$STATE" ] || return 0
  awk -F= -v k="$1" '$1 == k { sub(/^[^=]*=/, ""); v = $0 } END { if (v != "") print v }' "$STATE"
}
S_AT="$(st at)"; S_BOOT="$(st boot)"; S_VERDICT="$(st verdict)"
S_FILED_ID="$(st filed_id)"; S_FILED_AT="$(st filed_at)"; S_PREV_KEY="$(st prev_key)"; S_PREV_PC="$(st prev_per_call)"
case "$S_AT" in ''|*[!0-9]*) S_AT=0 ;; esac
case "$S_FILED_AT" in ''|*[!0-9]*) S_FILED_AT=0 ;; esac

if [ "$FORCE" = 0 ] && [ -n "$S_VERDICT" ] && [ "$S_BOOT" = "$BOOT" ] && [ $((NOW - S_AT)) -lt "$MIN_S" ]; then
  echo "kalloc-slo: damped verdict=$S_VERDICT age=$((NOW - S_AT))s"
  exit 0
fi

VERDICT="" REASON="" SLOPE="-" SPAN_H="-" MED="-" MED_DAYS=0 TGT="unknown"
PC="-" PREV_PC="-" RATIO="-" PC_NOTE="" PREV_KEY="" FILED="" FILED_ID="$S_FILED_ID" FILED_AT="$S_FILED_AT"

if [ -z "$BOOT" ]; then
  VERDICT=abstain; REASON="boot epoch unknown"
elif ! [ -r "$SERIES" ]; then
  VERDICT=abstain; REASON="zone series unreadable: $SERIES"
else
  # One pass over the series. A boot segment starts where the zone falls below half its last value
  # (only a reboot shrinks it) or where the rows cross this boot's epoch.
  AN="$(awk -v boot="$BOOT" -v now="$NOW" '
    $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $1 <= now + 5 {
      t = $1; y = $2 / 1073741824
      if (n == 0 || y < py / 2 || (pt < boot - 5 && t >= boot - 5)) seg++
      n++; T[n] = t; Y[n] = y; S[n] = seg
      if (!(seg in first)) first[seg] = t
      last[seg] = t; pt = t; py = y }
    function fit(lo, hi, sg,   i, k, sx, sy, sxx, sxy, x, t0, t1, d) {
      k = 0; sx = sy = sxx = sxy = 0; t0 = ""; t1 = 0
      for (i = 1; i <= n; i++) if (S[i] == sg && T[i] >= lo && T[i] < hi) {
        x = (T[i] - now) / 86400; k++; sx += x; sy += Y[i]; sxx += x * x; sxy += x * Y[i]
        if (t0 == "") t0 = T[i]; t1 = T[i] }
      FK = k; FSPAN = (k > 0) ? t1 - t0 : 0; FB = ""
      d = k * sxx - sx * sx
      if (k >= 3 && d > 0) FB = (k * sxy - sx * sy) / d }
    END {
      cur = (n > 0 && T[n] >= boot - 5) ? S[n] : -1
      lo = now - 86400; if (boot + 0 > lo) lo = boot + 0
      if (cur > 0) fit(lo, now + 6, cur); else { FK = 0; FSPAN = 0; FB = "" }
      printf "slope %d %d %s\n", FK, FSPAN, (FB == "" ? "-" : sprintf("%.3f", FB))
      prev = (cur > 0) ? cur - 1 : (n > 0 ? S[n] : 0)
      if (prev > 0) printf "prev %d %d\n", first[prev], last[prev]; else print "prev - -"
      m = 0
      for (dd = 0; dd < 7; dd++) {
        blo = now - (dd + 1) * 86400; bhi = now - dd * 86400; best = 0; bk = 0
        for (i = 1; i <= n; i++) if (T[i] >= blo && T[i] < bhi) { c[dd, S[i]]++; if (c[dd, S[i]] > bk) { bk = c[dd, S[i]]; best = S[i] } }
        if (best == 0) continue
        fit(blo, bhi, best)
        if (FB != "" && FSPAN >= 43200) { m++; R[m] = FB }
      }
      for (i = 2; i <= m; i++) { v = R[i]; for (j = i - 1; j >= 1 && R[j] > v; j--) R[j + 1] = R[j]; R[j + 1] = v }
      med = (m == 0) ? "-" : sprintf("%.3f", (m % 2) ? R[(m + 1) / 2] : (R[m / 2] + R[m / 2 + 1]) / 2)
      printf "median %d %s\n", m, med }' "$SERIES" 2>/dev/null)"
  SL_K="$(printf '%s\n' "$AN" | awk '$1 == "slope" { print $2 }')"
  SL_SPAN="$(printf '%s\n' "$AN" | awk '$1 == "slope" { print $3 }')"
  SLOPE="$(printf '%s\n' "$AN" | awk '$1 == "slope" { print $4 }')"
  P_LO="$(printf '%s\n' "$AN" | awk '$1 == "prev" { print $2 }')"
  P_HI="$(printf '%s\n' "$AN" | awk '$1 == "prev" { print $3 }')"
  MED_DAYS="$(printf '%s\n' "$AN" | awk '$1 == "median" { print $2 }')"
  MED="$(printf '%s\n' "$AN" | awk '$1 == "median" { print $3 }')"
  case "$SL_K" in ''|*[!0-9]*) SL_K=0 ;; esac
  case "$SL_SPAN" in ''|*[!0-9]*) SL_SPAN=0 ;; esac
  case "$MED_DAYS" in ''|*[!0-9]*) MED_DAYS=0 ;; esac
  [ -n "$SLOPE" ] || SLOPE="-"; [ -n "$MED" ] || MED="-"
  SPAN_H="$(awk -v s="$SL_SPAN" 'BEGIN { printf "%.1f", s / 3600 }')"

  if [ "$MED_DAYS" -ge 4 ] && [ "$MED" != "-" ]; then
    if awk -v m="$MED" -v t="$TARGET" 'BEGIN { exit !(m + 0 <= t + 0) }'; then TGT=met; else TGT=missed; fi
  fi

  # The per-call leg: this boot's trailing 24 h against the previous boot's last 24 h.
  LO=$((NOW - 86400)); [ "$BOOT" -gt "$LO" ] && LO="$BOOT"
  PC="$(/bin/bash "$RATE" --span "$LO" $((NOW + 6)) --series "$SERIES" --bash-log "$BLOG" 2>/dev/null \
        | sed -n 's/^per_call=//p')"
  [ -n "$PC" ] || { PC="-"; PC_NOTE="this boot's 24 h per-call fit insufficient"; }
  case "$P_LO:$P_HI" in
    *[!0-9:]*|:*|*:) PREV_PC="-"; PC_NOTE="${PC_NOTE:+$PC_NOTE; }no previous boot in the series" ;;
    *)
      PREV_KEY="$P_HI"
      if [ "$S_PREV_KEY" = "$PREV_KEY" ] && [ -n "$S_PREV_PC" ]; then
        PREV_PC="$S_PREV_PC"        # a finished boot's figure never changes; computed once per boot
      else
        PLO=$((P_HI - 86400)); [ "$P_LO" -gt "$PLO" ] && PLO="$P_LO"
        PREV_PC="$(/bin/bash "$RATE" --span "$PLO" $((P_HI + 1)) --series "$SERIES" --bash-log "$BLOG" 2>/dev/null \
                   | sed -n 's/^per_call=//p')"
        [ -n "$PREV_PC" ] || PREV_PC="-"
      fi
      [ "$PREV_PC" = "-" ] && PC_NOTE="${PC_NOTE:+$PC_NOTE; }previous boot's last-24 h per-call fit insufficient" ;;
  esac
  if [ "$PC" != "-" ] && [ "$PREV_PC" != "-" ]; then
    RATIO="$(awk -v a="$PC" -v b="$PREV_PC" 'BEGIN { if (b + 0 > 0) printf "%.2f", a / b }')"
    [ -n "$RATIO" ] || { RATIO="-"; PC_NOTE="previous boot's per-call growth is not positive"; }
  fi

  slope_known=0; [ "$SL_K" -ge 3 ] && [ "$SL_SPAN" -ge 77760 ] && [ "$SLOPE" != "-" ] && slope_known=1
  b_slope=0; b_ratio=0
  [ "$slope_known" = 1 ] && awk -v s="$SLOPE" -v b="$BREACH" 'BEGIN { exit !(s + 0 > b + 0) }' && b_slope=1
  [ "$RATIO" != "-" ] && awk -v r="$RATIO" -v m="$RATIO_MAX" 'BEGIN { exit !(r + 0 > m + 0) }' && b_ratio=1
  if [ "$b_slope" = 1 ] || [ "$b_ratio" = 1 ]; then
    VERDICT=breach
    [ "$b_slope" = 1 ] && REASON="24 h slope ${SLOPE} GiB/day > ${BREACH}"
    [ "$b_ratio" = 1 ] && REASON="${REASON:+$REASON; }growth per Bash call ${RATIO}x the previous boot's > ${RATIO_MAX}x"
  elif [ "$slope_known" = 1 ]; then
    VERDICT=ok
  else
    VERDICT=abstain
    REASON="series too short: this boot's 24 h fit has ${SL_K} rows over ${SPAN_H} h, needs >= 3 over 21.6 h"
  fi
fi

# ── the operator row: one, deduped across runs ──
if [ "$VERDICT" = breach ] && [ "$FILE" = 1 ]; then
  live=""
  if [ -n "$FILED_ID" ]; then
    if command -v jq >/dev/null 2>&1 && [ -x "$BLG" ]; then
      if _js="$("$BLG" list --all --json 2>/dev/null)"; then
        _sts="$(printf '%s' "$_js" | jq -r --arg id "$FILED_ID" '.[]? | select(.id == $id) | .status' 2>/dev/null | tail -1)"
        case "$_sts" in ''|done) live=no ;; *) live=yes ;; esac
      else live=unknown
      fi
    else live=unknown
    fi
  fi
  if [ "$live" = yes ]; then FILED="dup (row $FILED_ID still open)"
  elif [ "$live" = unknown ]; then FILED="not filed (row $FILED_ID filed before; ledger unreadable, so no second row)"
  elif [ "$FILED_AT" -gt 0 ] && [ $((NOW - FILED_AT)) -lt "$REFILE_S" ]; then
    FILED="not filed (row ${FILED_ID:-?} is closed, filed $(( (NOW - FILED_AT) / 3600 )) h ago; re-file after $((REFILE_S / 86400)) d)"
  elif ! [ -x "$BLG" ]; then FILED="FAILED: cc-backlog not executable at $BLG"
  else
    _out="$("$BLG" needs "$TITLE" --class needs-human --run "$RUN" --project claude-infrastructure 2>/dev/null)"; _rc=$?
    _id="$(printf '%s\n' "$_out" | grep -Eo '^[0-9a-f]{12}$' | tail -1)"
    if [ "$_rc" -eq 0 ] && [ -n "$_id" ]; then FILED="new row $_id"; FILED_ID="$_id"; FILED_AT="$NOW"
    else FILED="FAILED: cc-backlog needs rc=$_rc (retried next evaluation)"
    fi
  fi
fi

LINE="verdict=${VERDICT}${REASON:+ ($REASON)} · 24 h slope ${SLOPE} GiB/day over ${SPAN_H} h (breach > ${BREACH})"
r1() { case "$1" in -) printf -- - ;; *) awk -v v="$1" 'BEGIN { printf "%.1f", v }' ;; esac; }
LINE="${LINE} · growth per Bash call $(r1 "$PC") vs previous boot $(r1 "$PREV_PC") elements, ratio ${RATIO} (breach > ${RATIO_MAX}x)${PC_NOTE:+ [$PC_NOTE]}"
LINE="${LINE} · target 7-day median ${MED} GiB/day over ${MED_DAYS} day(s): ${TGT} (<= ${TARGET})${FILED:+ · operator row: $FILED}"
echo "kalloc-slo: $LINE"

mkdir -p "$(dirname "$STATE")" 2>/dev/null
{
  printf 'boot=%s\nat=%s\nverdict=%s\nreason=%s\n' "$BOOT" "$NOW" "$VERDICT" "$REASON"
  printf 'slope_24h=%s\nslope_span_h=%s\nper_call=%s\nprev_per_call=%s\nprev_key=%s\nratio=%s\n' \
    "$SLOPE" "$SPAN_H" "$PC" "$PREV_PC" "$PREV_KEY" "$RATIO"
  printf 'median_7d=%s\nmedian_days=%s\ntarget=%s\nfiled_id=%s\nfiled_at=%s\nline=%s\n' \
    "$MED" "$MED_DAYS" "$TGT" "$FILED_ID" "$FILED_AT" "$LINE"
} > "$STATE.tmp" 2>/dev/null && mv -f "$STATE.tmp" "$STATE"
mkdir -p "$(dirname "$SLOG")" 2>/dev/null
printf '%s %s\n' "$(date -u -r "$NOW" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$LINE" >> "$SLOG" 2>/dev/null
if [ "$(wc -l < "$SLOG" 2>/dev/null | tr -d ' ')" -gt 4000 ] 2>/dev/null; then
  tail -n 2000 "$SLOG" > "$SLOG.tmp" 2>/dev/null && mv -f "$SLOG.tmp" "$SLOG"
fi

case "$VERDICT" in ok) exit 0 ;; breach) exit 1 ;; *) exit 3 ;; esac
