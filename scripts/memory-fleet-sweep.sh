#!/usr/bin/env bash
# memory-fleet-sweep.sh — measure EVERY project's auto-loaded memory index, fleet-wide, and say
# which ones are silently dropping entries right now.
#
# ── WHY THIS EXISTS ──────────────────────────────────────────────────────────────────────────
# The rotor (bin/cc-memory-rotate) is invoked from hooks/memory-nudge.sh on every prompt, and
# cc-memory-rotate's own header claims "the next prompt ANYWHERE rotates it back under budget".
# That claim is FALSE, and the gap is not small. memory-nudge.sh resolves the index from the
# SESSION'S OWN cwd (its jq .cwd → git-common-dir → slugify chain), so exactly one index — the
# project you happen to have open — is ever considered. A project nobody opens is never measured
# by anything.
#
# Measured 2026-09-03: doc-classifier sat 2,256 units OVER the 25,000-char cap for ELEVEN DAYS,
# its 9 newest memories loading in ZERO sessions, with archive/ and .rotate.log both absent —
# the rotor had never run there once. No scheduled sweep existed either: a scan of
# ~/Library/LaunchAgents found no job invoking cc-memory-rotate (positive control: the same scan
# did find capacity-alarm in com.claude.compressor-sentinel.plist), and `crontab -l` reported no
# crontab. Nothing on this machine was watching.
#
# ── WHAT IT REPORTS, AND THE COLUMN THAT MATTERS ─────────────────────────────────────────────
# DARK is the point of this tool. The loader reads the index up to its cap and SILENTLY DROPS
# THE TAIL — the NEWEST entries — so an over-cap index is not merely untidy, it is actively
# withholding its most recent lessons from every session, with no error and no way for a reader
# to tell. DARK counts exactly those entries. Everything else here is context for that number.
#
# ── SAFETY ───────────────────────────────────────────────────────────────────────────────────
# REPORT-ONLY BY DEFAULT. It writes nothing without --rotate, and even then it only invokes
# bin/cc-memory-rotate, whose moves are verbatim and reversible (restore = paste the line back).
# This deliberately does NOT install a background job: rotating memory files with no session
# watching is a class of automation the operator constrains, and that decision is theirs. Run
# this by hand, or wire it once that call is made.
#
# Usage: memory-fleet-sweep.sh [--rotate] [--quiet]
# Exit:  0 every index under both caps · 1 at least one index over · 2 error
set -euo pipefail

ROTATE=0; QUIET=0
for a in "$@"; do
  case "$a" in
    --rotate) ROTATE=1 ;;
    --quiet)  QUIET=1 ;;
    -h|--help) sed -n '1,40p' "$0"; exit 0 ;;
    *) printf 'memory-fleet-sweep: unknown flag %s\n' "$a" >&2; exit 2 ;;
  esac
done

# Resolve $0 THROUGH symlinks before deriving the repo root. This script is reached through the
# ~/.claude symlink farm, where a bare `dirname "$0"/..` derives ~/.claude as the root and resolves
# the measure lib and the rotor to the wrong tree — the exact scar scripts/self-path-lint.sh
# ratchets against, and it caught this file on its first land attempt. macOS ships BSD userland, so
# there is no `readlink -f`; the manual loop is the portable form (bash 3.2 safe).
_resolve_self() {  # <path> → absolute path, every symlink hop resolved
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
HERE="$(cd "$(dirname "$SELF")/.." && pwd -P)"
MEASURE="$HERE/hooks/lib/memory-index-measure.sh"
ROTOR="$HERE/bin/cc-memory-rotate"
[ -r "$MEASURE" ] || { printf 'memory-fleet-sweep: cannot read %s\n' "$MEASURE" >&2; exit 2; }
# shellcheck source=/dev/null
. "$MEASURE"

LIMIT=$(mim_limit 2>/dev/null || printf 25000)
LINE_LIMIT=$(mim_line_limit 2>/dev/null || printf 200)
case "$LIMIT" in ''|*[!0-9]*) LIMIT=25000 ;; esac
case "$LINE_LIMIT" in ''|*[!0-9]*) LINE_LIMIT=200 ;; esac

# Every knowledge-layer mirror reproduces projects/<slug>/memory/, and several of them RESOLVE TO
# THE SAME TREE (measured: .claude and .claude-quaternary are one tree for doc-classifier). Collect
# by realpath and dedupe, or the same index is reported — and rotated — more than once.
SEEN=""
INDEXES=""
for cfg in "$HOME"/.claude "$HOME"/.claude-secondary "$HOME"/.claude-tertiary "$HOME"/.claude-quaternary; do
  [ -d "$cfg/projects" ] || continue
  for idx in "$cfg"/projects/*/memory/MEMORY.md; do
    [ -f "$idx" ] || continue
    rp=$(cd "$(dirname "$idx")" && pwd -P)/MEMORY.md
    case "$SEEN" in *"|$rp|"*) continue ;; esac
    SEEN="$SEEN|$rp|"
    # A slug decoding to /private/tmp or /tmp is a PROBE FIXTURE, not a project — this repo's own
    # suites mint them (memprobe-*), they are wiped on reboot, and one of them is a deliberate
    # 800,016-char monster. Counting them as fleet breaches would make the OVER count permanently
    # non-zero and train the reader to ignore it. Skipped, but COUNTED and reported, never silent.
    sl=$(basename "$(dirname "$(dirname "$rp")")")
    case "$sl" in -private-tmp-*|-tmp-*) SKIPPED_TMP=$(( ${SKIPPED_TMP:-0} + 1 )); continue ;; esac
    INDEXES="$INDEXES$rp
"
  done
done

# DARK: entries whose line STARTS past the loader's cut. Counted the way the loader counts —
# UTF-16 units of the stripped, trimmed index — not bytes, and not by eyeballing the tail.
dark_count() {
  LC_ALL=en_US.UTF-8 python3 - "$1" "$LIMIT" <<'PY' 2>/dev/null || printf '?'
import re,sys
p,limit=sys.argv[1],int(sys.argv[2])
s=open(p,encoding='utf-8',errors='replace').read()
s=re.sub(r'^---\s*\n([\s\S]*?)---\s*\n?','',s)
s=re.sub(r'<!--[\s\S]*?-->','',s)
s=s.strip()
u16=lambda t: sum(2 if ord(c)>0xFFFF else 1 for c in t)
run=0; dark=0
for line in s.split('\n'):
    if run>limit and re.match(r'^- \*{0,2}\[', line): dark+=1
    run+=u16(line)+1
print(dark)
PY
}

OVER=0; N=0
[ "$QUIET" -eq 1 ] || printf '%-46s %8s %6s %6s %5s  %s\n' PROJECT CHARS LINES ENTRIES DARK STATUS
while IFS= read -r idx; do
  [ -n "$idx" ] || continue
  N=$(( N + 1 ))
  read -r c l <<EOF
$(mim_measure_file "$idx")
EOF
  case "$c" in ''|*[!0-9]*) c=0 ;; esac
  case "$l" in ''|*[!0-9]*) l=0 ;; esac
  # `grep -c` PRINTS 0 and EXITS 1 on no-match, so `|| printf 0` emits a SECOND zero and the
  # column renders as two lines. Swallow the status, then sanitize.
  e=$(grep -cE '^- \*{0,2}\[' "$idx" 2>/dev/null || true)
  case "$e" in ''|*[!0-9]*) e=0 ;; esac
  d=$(dark_count "$idx")
  slug=$(basename "$(dirname "$(dirname "$idx")")"); slug=${slug#-Users-chrisren-}
  st=ok
  if [ "$c" -gt "$LIMIT" ] || [ "$l" -gt "$LINE_LIMIT" ]; then st=OVER; OVER=$(( OVER + 1 ))
  elif [ "$c" -gt $(( LIMIT - 2000 )) ] || [ "$l" -gt $(( LINE_LIMIT - 16 )) ]; then st=tight
  fi
  [ "$QUIET" -eq 1 ] || printf '%-46s %8s %6s %6s %5s  %s\n' "$(printf '%.46s' "$slug")" "$c" "$l" "$e" "$d" "$st"
  if [ "$st" = OVER ] && [ "$ROTATE" -eq 1 ] && [ -x "$ROTOR" ]; then
    printf '    → rotating: '; "$ROTOR" "$idx" 2>&1 | tail -1
  fi
done <<EOF
$INDEXES
EOF

[ "$QUIET" -eq 1 ] || printf '\n%s index(es) swept · %s over cap · %s tmp fixture(s) skipped · caps: %s chars / %s lines\n' \
  "$N" "$OVER" "${SKIPPED_TMP:-0}" "$LIMIT" "$LINE_LIMIT"
[ "$OVER" -eq 0 ] || exit 1
exit 0
