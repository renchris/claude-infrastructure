#!/bin/bash
# kalloc-leak-rate.sh — data.kalloc.1024 growth before vs after a cutover, raw and per Bash tool call.
#
# Built to judge migration 0070 (hook commands run as `/bin/bash <script>` instead of a bare `#!`
# path) at fleet scale: the same window length either side of the cutover, from the zone series
# capacity-alarm.sh already writes every ~900 s, so both sides come from one instrument. The raw rate
# moves with how busy the fleet is, so the comparison that decides is growth per Bash tool call
# (~20 hooks fire per call), counted from bash-commands.log and its rotated .gz siblings over the same
# span the zone fit covers. Method and history: docs/research/panic-2026-10-18-zone-map-shebang-leak.md.
#
# Usage: kalloc-leak-rate.sh --cutover EPOCH [--window SECS] [--series TSV] [--bash-log LOG]
#        kalloc-leak-rate.sh --span LO HI [--window SECS] [--series TSV] [--bash-log LOG]
#   --window   seconds each side of the cutover (default 86400)
#   --span     one side only, rows in [LO, HI): prints its line, then `per_call=<elements per Bash
#              call>`, exit 0; or `verdict=insufficient`, exit 1. --window is then the span the fit
#              must cover 90% of. kalloc-slo.sh uses it to compare one boot against the last.
#   --series   "<epoch> <bytes>" rows (default ~/.claude/logs/kalloc-zone-series.tsv)
#   --bash-log current Bash-call log; LOG.<stamp>.gz siblings are read too
#              (default ~/.claude/logs/bash-commands.log)
# Prints one line per side, then `verdict=<v> ratio=<after/before per Bash call>`:
#   reduced (ratio <= 0.5) · partial (0.5-0.8) · unchanged (>= 0.8) · insufficient (a side's zone fit
#   spans < 90% of the window, has < 3 rows, or saw no Bash calls)
# Exit: 0 a verdict was computed (any of the first three) · 1 insufficient · 2 usage or unreadable input
set -uo pipefail

CUT="" WIN=86400 SPAN_LO="" SPAN_HI=""
SERIES="$HOME/.claude/logs/kalloc-zone-series.tsv"
BLOG="$HOME/.claude/logs/bash-commands.log"
while [ $# -gt 0 ]; do
  case "$1" in
    --cutover) CUT="${2:-}"; shift 2 ;;
    --window) WIN="${2:-}"; shift 2 ;;
    --span) [ $# -ge 3 ] || { echo "kalloc-leak-rate: --span needs LO HI" >&2; exit 2; }
            SPAN_LO="$2"; SPAN_HI="$3"; shift 3 ;;
    --series) SERIES="${2:-}"; shift 2 ;;
    --bash-log) BLOG="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "kalloc-leak-rate: unknown argument $1" >&2; exit 2 ;;
  esac
done
if [ -n "$SPAN_LO$SPAN_HI" ]; then
  case "$SPAN_LO:$SPAN_HI" in :*|*:|*[!0-9:]*) echo "kalloc-leak-rate: --span LO HI must be epochs" >&2; exit 2 ;; esac
else
  case "$CUT" in ''|*[!0-9]*) echo "kalloc-leak-rate: --cutover EPOCH is required" >&2; exit 2 ;; esac
fi
case "$WIN" in ''|*[!0-9]*|0) echo "kalloc-leak-rate: --window must be a positive integer" >&2; exit 2 ;; esac
[ -r "$SERIES" ] || { echo "kalloc-leak-rate: series unreadable: $SERIES" >&2; exit 2; }

# fit LO HI → "n first last slope_bytes_per_s" (OLS over rows in [LO, HI)); n<3 prints "n 0 0 0"
fit() {
  awk -v lo="$1" -v hi="$2" '$1>=lo && $1<hi && $2 ~ /^[0-9]+$/ {
      n++; sx+=$1; sy+=$2; sxx+=$1*$1; sxy+=$1*$2; if (n==1) f=$1; l=$1 }
    END { if (n<3) { print n, 0, 0, 0; exit }
          xm=sx/n; d=sxx-n*xm*xm; b=(d>0) ? (sxy-n*xm*(sy/n))/d : 0
          printf "%d %d %d %.6f\n", n, f, l, b }' "$SERIES"
}

# calls LO HI → Bash tool calls whose "[YYYY-MM-DDTHH:MM:SSZ]" stamp is in [LO, HI]. A rotated
# sibling's name stamps its rotation time, the newest row it can hold, so older ones are skipped.
calls() {
  local lo="$1" hi="$2" g stamp
  {
    for g in "$BLOG".*.gz; do
      [ -r "$g" ] || continue
      stamp="${g##*.log.}"; stamp="${stamp%.gz}"
      stamp="$(/usr/bin/perl -MTime::Local -e '$ARGV[0]=~/^(\d{4})(\d\d)(\d\d)T(\d\d)(\d\d)(\d\d)Z$/ or exit;
        print timegm($6,$5,$4,$3,$2-1,$1)' "$stamp")"
      case "$stamp" in ''|*[!0-9]*) ;; *) [ "$stamp" -lt "$lo" ] && continue ;; esac
      /usr/bin/gzip -dc "$g" 2>/dev/null
    done
    [ -r "$BLOG" ] && cat "$BLOG"
  } | /usr/bin/perl -MTime::Local -ne '
      next unless /^\[(\d{4})-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)Z\]/;
      $e = timegm($6,$5,$4,$3,$2-1,$1); $n++ if $e >= '"$lo"' && $e <= '"$hi"';
      END { print $n+0, "\n" }'
}

ok=1
side() { # LABEL LO HI → prints the side's line; sets PER_CALL
  local label="$1" lo="$2" hi="$3" n f l b span c
  read -r n f l b <<< "$(fit "$lo" "$hi")"
  span=$(( l - f ))
  if [ "$n" -lt 3 ]; then
    printf '%-6s rows=%d — too few zone samples\n' "$label" "$n"; ok=0; PER_CALL=0; return
  fi
  c="$(calls "$f" "$l")"
  awk -v L="$label" -v n="$n" -v span="$span" -v win="$WIN" -v b="$b" -v c="$c" -v f="$f" -v l="$l" 'BEGIN {
    pc = (c > 0) ? b * span / 1024 / c : 0
    printf "%-6s rows=%d span=%.1fh (%.0f%% of window) %.3f GiB/day %.2f elem/s · bash_calls=%d %.2f elem/call\n",
      L, n, span/3600, 100*span/win, b*86400/1073741824, b/1024, c, pc }'
  PER_CALL="$(awk -v b="$b" -v span="$span" -v c="$c" 'BEGIN { printf "%.6f", (c > 0) ? b*span/1024/c : 0 }')"
  if [ "$span" -lt $(( WIN * 9 / 10 )) ] || [ "$c" -eq 0 ]; then ok=0; fi
}

if [ -n "$SPAN_LO" ]; then
  side span "$SPAN_LO" "$SPAN_HI"
  [ "$ok" -eq 1 ] || { echo "verdict=insufficient"; exit 1; }
  echo "per_call=$PER_CALL"; exit 0
fi

side before $(( CUT - WIN )) "$CUT"; PB="$PER_CALL"
side after "$CUT" $(( CUT + WIN )); PA="$PER_CALL"

if [ "$ok" -ne 1 ] || awk -v p="$PB" 'BEGIN { exit !(p <= 0) }'; then
  echo "verdict=insufficient"; exit 1
fi
awk -v a="$PA" -v b="$PB" 'BEGIN { r = a / b
  v = (r <= 0.5) ? "reduced" : (r < 0.8) ? "partial" : "unchanged"
  printf "verdict=%s ratio=%.2f\n", v, r }'
