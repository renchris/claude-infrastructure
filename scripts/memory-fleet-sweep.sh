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
# ── --reach: WHAT A SESSION CAN ACTUALLY GET TO, and whether Claude Code's own writers are on ───
# DARK measures loss INSIDE the index. It cannot see a lesson that sits in full view in a rules
# file `claudeMdExcludes` keeps out of every session: in infra, 44 topics were cited ONLY by the
# excluded situational file, and two stores routed into an excluded file that no delivered file
# even names (docs/research/truememory-2026-09-27.md §3.8). --reach adds, report-only:
#   REACH <store>       topics reachable in one hop from the delivered set, and what only the
#                       excluded files hold. `REACH-VERDICT dark_dest=` is the token to alarm on.
#   NATIVE <cache>      the server flags that would turn on Claude Code's OWN memory writers in our
#                       stores (extraction, dream, the index-model switch, the load kill switch).
#                       Every one is off today, so this measures PRESENCE — the only detector for a
#                       server flip. `NATIVE-VERDICT nondefault=` is its token; unreadable is
#                       counted as unknown, never as default.
#   HISTORY <store>     age of the store's last out-of-store snapshot against its newest write.
# It reads every store and every .claude.json; the one thing it writes is its own transcript-scan
# stamp under ~/.claude/state. Without --reach the table and the exit contract are unchanged.
#
# Usage: memory-fleet-sweep.sh [--rotate] [--quiet] [--reach]
# Exit:  0 every index under both caps · 1 at least one index over · 2 error
set -euo pipefail

ROTATE=0; QUIET=0; REACH=0
for a in "$@"; do
  case "$a" in
    --rotate) ROTATE=1 ;;
    --quiet)  QUIET=1 ;;
    --reach)  REACH=1 ;;
    -h|--help) sed -n '/^set -euo/q;p' "$0"; exit 0 ;;
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
if [ "$REACH" -eq 1 ]; then
  # Whether a rules file loads is computed from claudeMdExcludes by ONE helper, never restated
  # here (#1). Missing, the reach numbers would be guesses, so that is an error, not a default.
  RULES_LIB="$HERE/hooks/lib/rules-loaded.sh"
  [ -r "$RULES_LIB" ] || { printf 'memory-fleet-sweep: cannot read %s\n' "$RULES_LIB" >&2; exit 2; }
  # shellcheck source=/dev/null
  . "$RULES_LIB"
fi

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

# ══ --reach ═══════════════════════════════════════════════════════════════════════════════════
# project_dir_for_slug <slug> → the project directory the store belongs to, or nothing. A slug is
# the path with every non-alphanumeric turned into `-`, which is lossy (`a-b` and `a/b` collide),
# so it is decoded by walking the REAL tree and matching each entry's own slug, backtracking on a
# miss — never by splitting on `-`.
project_dir_for_slug() {
  python3 - "$1" <<'PY' 2>/dev/null || true
import os, re, sys
from typing import Optional

def slugify(name: str) -> str:
    return re.sub(r'[^A-Za-z0-9]', '-', name)

def walk(d: str, rest: str) -> Optional[str]:
    if rest == '':
        return d
    try:
        names = os.listdir(d)
    except OSError:
        return None
    for n in sorted(names, key=len, reverse=True):
        s = '-' + slugify(n)
        if (rest == s or rest.startswith(s + '-')) and os.path.isdir(os.path.join(d, n)):
            found = walk(os.path.join(d, n), rest[len(s):])
            if found:
                return found
    return None

found = walk('/', sys.argv[1])
if found:
    print(found)
PY
}

# reach_row <slug> <store> <effective-index> <delivered-list> <excluded-list> <unknown> <resolved>
# → one REACH line. The lists are computed in bash first, through rules_file_loads, so the load
# decision is the helper's and this only does the set arithmetic.
reach_row() {
  python3 - "$@" <<'PY'
import os, re, sys
from typing import List, Set

slug, store, eff, deliv_list, excl_list, unknown, resolved = sys.argv[1:8]

def read(p: str) -> str:
    try:
        with open(p, encoding='utf-8', errors='replace') as fh:
            return fh.read()
    except OSError:
        return ''

def lines_of(p: str) -> List[str]:
    return [x for x in read(p).split('\n') if x]

topics: Set[str] = {n for n in os.listdir(store)
                    if n.endswith('.md') and n != 'MEMORY.md' and os.path.isfile(os.path.join(store, n))}

LINK = re.compile(r'\]\(<?([^)\s>]+)>?\)')
WIKI = re.compile(r'\[\[([^\]|#]+)')
PATH = re.compile(r'(?<![A-Za-z0-9_.-])memory/([A-Za-z0-9_.-]+\.md)')

def cited(text: str) -> Set[str]:
    # A topic is cited by a bare relative link (how the index and a routed line name it), by a
    # link or a path through a memory/ directory, or by a [[wikilink]]. A `../../docs/lessons/x.md`
    # link is a DIFFERENT file that may share a basename, so a slashed link must pass memory/
    # (`memory/x.md` relative, as some indexes write it, or an absolute path through it).
    out: Set[str] = set()
    for t in LINK.findall(text):
        t = t.split('#', 1)[0]
        base = t.rsplit('/', 1)[-1]
        if base in topics and ('/' not in t or re.search(r'(^|/)memory/', t)):
            out.add(base)
    out |= {m + '.md' for m in WIKI.findall(text) if m + '.md' in topics}
    out |= {m for m in PATH.findall(text) if m in topics}
    return out

delivered = [eff] + lines_of(deliv_list)
excluded = lines_of(excl_list)
dtext = '\n'.join(read(p) for p in delivered)
hop1 = cited(dtext)
ecited: Set[str] = set()
for p in excluded:
    ecited |= cited(read(p))
dlines = {x.strip() for x in dtext.split('\n')}
excl_bullets = sum(1 for p in excluded for x in read(p).split('\n')
                   if re.match(r'\s*- ', x) and x.strip() not in dlines)
# DARK DESTINATION: an excluded file no delivered file even NAMES. Its lessons are not merely one
# hop further away — no session has any pointer to them at all.
dark = 0
for p in excluded:
    base = os.path.basename(p)
    if base not in dtext and base[:-3] not in dtext:
        dark = 1
row = 'REACH store=%s topics=%d hop1=%d excl_bullets=%d excl_only_topics=%d dark_dest=%s' % (
    slug, len(topics), len(hop1), excl_bullets, len(ecited - hop1), '?' if unknown == '1' else dark)
if resolved != '1':
    row += ' project=unresolved'
print(row)
PY
}

reach_report() {
  local tmp idx store slug pd f u row dd resolved dsum=0 unk=0 unres=0
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/mfs-reach.XXXXXX")
  while IFS= read -r idx; do
    [ -n "$idx" ] || continue
    store=$(dirname "$idx"); slug=$(basename "$(dirname "$store")")
    : >"$tmp/deliv"; : >"$tmp/excl"; u=0
    mim_effective_file "$idx" >"$tmp/eff" 2>/dev/null || cp "$idx" "$tmp/eff"
    pd=$(project_dir_for_slug "$slug")
    if [ -n "$pd" ]; then
      for f in "$pd/CLAUDE.md" "$pd/.claude/CLAUDE.md" "$pd/CLAUDE.local.md" "$pd"/.claude/rules/*.md; do
        [ -f "$f" ] || continue
        case "$(rules_file_loads "$f")" in
          excluded) printf '%s\n' "$f" >>"$tmp/excl" ;;
          loads)    printf '%s\n' "$f" >>"$tmp/deliv" ;;
          # Unknown is kept in the delivered set for the counts, but it poisons dark_dest: a
          # settings file we could not read must never be reported as "nothing is dark".
          *)        printf '%s\n' "$f" >>"$tmp/deliv"; u=1 ;;
        esac
      done
      resolved=1
    else
      resolved=0; unres=$(( unres + 1 ))
    fi
    row=$(reach_row "$slug" "$store" "$tmp/eff" "$tmp/deliv" "$tmp/excl" "$u" "$resolved") \
      || row="REACH store=$slug status=error dark_dest=?"
    printf '%s\n' "$row"
    dd=${row##*dark_dest=}; dd=${dd%% *}
    case "$dd" in 1) dsum=$(( dsum + 1 )) ;; 0) ;; *) unk=$(( unk + 1 )) ;; esac
  done <<EOF
$INDEXES
EOF
  rm -rf "$tmp"
  printf 'REACH-VERDICT dark_dest=%s unknown=%s unresolved=%s\n' "$dsum" "$unk" "$unres"
}

# Portable mtime (BSD stat on macOS, GNU elsewhere) — epoch seconds for each argument.
if stat --version >/dev/null 2>&1; then STAT_OPT=-c; STAT_FMT=%Y; else STAT_OPT=-f; STAT_FMT=%m; fi
_mtimes() { stat "$STAT_OPT" "$STAT_FMT" "$@"; }
_iso() {  # <epoch> → UTC ISO-8601
  date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
}

native_report() {
  local settings model c out w k v nondef=0 unk=0 idx store stamp newstamp since roots root rp list n cap trunc=0 hits
  # The kill switch matches the MAIN-LOOP model id, so it is read from the same settings file the
  # rules helper reads. Read-only: jq never writes.
  settings="${RULES_LOADED_SETTINGS:-$HOME/.claude/settings.json}"
  model=$(jq -r '.model // empty' "$settings" 2>/dev/null || true)
  for c in "$HOME/.claude.json" "$HOME/.claude/.claude.json" "$HOME/.claude-next/.claude.json" \
           "$HOME/.claude-secondary/.claude.json" "$HOME/.claude-tertiary/.claude.json" "$HOME/.claude-quaternary/.claude.json"; do
    [ -e "$c" ] || continue
    # ONE jq per cache. An absent flag is false, which is its shipped default; a cache that is
    # missing or not an object is UNREADABLE — it says nothing, so it may not read as all-off.
    out=$(jq -r --arg m "$model" '
        .cachedGrowthBookFeatures as $f
        | if ($f | type) != "object" then "UNREADABLE" else
          (($f.tengu_onyx_plover // {}) | if type == "object" then . else {} end) as $o
          | "quail=\(($f.tengu_passport_quail // false) | tostring)"
          + " slate=\(($f.tengu_slate_thimble // false) | tostring)"
          + " onyx_enabled=\(($o.enabled // false) | tostring)"
          + " onyx_available=\(($o.available // false) | tostring)"
          + " moth=\(($f.tengu_moth_copse // false) | tostring)"
          + " stone=\(($f.tengu_stone_shell // false) | tostring)"
          + " linen=\(($f.tengu_linen_orbit // false) | tostring)"
          + " haze=\(($f.tengu_haze_glass // false) | tostring)"
          + " killswitch=" + (if ($f.tengu_umber_petrel // false) != true then "0"
              elif $m == "" then "?"
              elif ([($f.tengu_sepia_cormorant // []) | if type == "array" then .[] else empty end
                     | strings | select(. as $s | $m | contains($s))] | length) > 0 then "1"
              else "0" end)
          end' "$c" 2>/dev/null) || out=UNREADABLE
    [ -n "$out" ] || out=UNREADABLE
    if [ "$out" = UNREADABLE ]; then
      printf 'NATIVE root=%s status=unreadable\n' "$c"; unk=$(( unk + 1 )); continue
    fi
    printf 'NATIVE root=%s %s\n' "$c" "$out"
    for w in $out; do
      k=${w%%=*}; v=${w#*=}
      case "$k" in
        killswitch) case "$v" in 0) ;; 1) nondef=$(( nondef + 1 )) ;; *) unk=$(( unk + 1 )) ;; esac ;;
        # Anything but `false` counts: a flag that grew a non-boolean value is news, not default.
        *) [ "$v" = false ] || nondef=$(( nondef + 1 )) ;;
      esac
    done
  done

  # A first dream leaves .consolidate-lock behind for good; team/ and logs/ are the native
  # writers' other footprints. All 37 stores read 0 on 2026-09-27.
  while IFS= read -r idx; do
    [ -n "$idx" ] || continue
    store=$(dirname "$idx")
    set -- 0 0 0
    [ -e "$store/.consolidate-lock" ] && set -- 1 "$2" "$3"
    [ -d "$store/team" ] && set -- "$1" 1 "$3"
    [ -d "$store/logs" ] && set -- "$1" "$2" 1
    printf 'NATIVE-STORE store=%s consolidate_lock=%s team_dir=%s logs_dir=%s\n' \
      "$(basename "$(dirname "$store")")" "$1" "$2" "$3"
    nondef=$(( nondef + $1 + $2 + $3 ))
  done <<EOF
$INDEXES
EOF

  # memory_saved records: incremental, keyed on a stamp so each run counts only what is new. The
  # new stamp is taken BEFORE the scan, so a transcript written mid-scan is seen next run, not lost.
  stamp="$HOME/.claude/state/memory-fleet-sweep.native-stamp"
  mkdir -p "$(dirname "$stamp")"
  newstamp="$stamp.new.$$"; : >"$newstamp"
  cap="${MFS_NATIVE_SCAN_MAX:-20000}"
  list=$(mktemp "${TMPDIR:-/tmp}/mfs-native.XXXXXX")
  roots=""
  for root in "$HOME/.claude/projects" "$HOME/.claude-secondary/projects" "$HOME/.claude-tertiary/projects" "$HOME/.claude-quaternary/projects"; do
    [ -d "$root" ] || continue
    rp=$(cd "$root" && pwd -P)
    case "$roots" in *"|$rp|"*) continue ;; esac
    roots="$roots|$rp|"
    if [ -f "$stamp" ]; then find "$rp" -type f -name '*.jsonl' -newer "$stamp" 2>/dev/null >>"$list" || true
    else find "$rp" -type f -name '*.jsonl' -mmin -1440 2>/dev/null >>"$list" || true
    fi
  done
  if [ -f "$stamp" ]; then since=$(_iso "$(_mtimes "$stamp")"); else since=$(_iso $(( $(date +%s) - 86400 ))); fi
  n=$(wc -l <"$list" | tr -d ' ')
  if [ "$n" -gt "$cap" ]; then
    trunc=1; head -n "$cap" "$list" >"$list.cap"; mv "$list.cap" "$list"; n=$cap
  fi
  hits=0
  if [ "$n" -gt 0 ]; then
    # grep exits 1 on no match and xargs reports that as 123 — neither is an error here.
    hits=$(tr '\n' '\0' <"$list" | xargs -0 grep -l -F '"subtype":"memory_saved"' 2>/dev/null | wc -l | tr -d ' ') || true
  fi
  case "$hits" in ''|*[!0-9]*) hits=0 ;; esac
  rm -f "$list"; mv "$newstamp" "$stamp"
  printf 'NATIVE-TRANSCRIPTS memory_saved_records=%s scanned=%s since=%s truncated=%s\n' "$hits" "$n" "$since" "$trunc"
  nondef=$(( nondef + hits ))
  printf 'NATIVE-VERDICT nondefault=%s unknown=%s\n' "$nondef" "$unk"
}

# HISTORY (#11's read side). The snapshot gitdir lives OUTSIDE the store, keyed on its physical
# path, so symlinked worktree stores share one history. Read with plain `git log`; no lock taken.
history_report() {
  local idx store phys gd ct newest now behind
  now=$(date +%s)
  while IFS= read -r idx; do
    [ -n "$idx" ] || continue
    store=$(dirname "$idx"); phys=$(cd "$store" && pwd -P)
    gd="${CC_MEMORY_HISTORY_ROOT:-$HOME/.local/state/cc-memory-history}/$(printf '%s' "$phys" | tr '/' '-').git"
    set -- "$(basename "$(dirname "$store")")"
    if [ ! -d "$gd" ]; then printf 'HISTORY store=%s status=none\n' "$1"; continue; fi
    ct=$(GIT_OPTIONAL_LOCKS=0 git --git-dir="$gd" log -1 --format=%ct refs/heads/main 2>/dev/null || true)
    case "$ct" in ''|*[!0-9]*) printf 'HISTORY store=%s status=unreadable\n' "$1"; continue ;; esac
    newest=$(find "$store" -type f -name '*.md' -print0 2>/dev/null | xargs -0 stat "$STAT_OPT" "$STAT_FMT" 2>/dev/null | sort -n | tail -1 || true)
    case "$newest" in ''|*[!0-9]*) newest=$ct ;; esac
    behind=0; [ "$newest" -le "$ct" ] || behind=1
    printf 'HISTORY store=%s age_s=%s newest_mtime_age_s=%s behind=%s\n' \
      "$1" "$(( now - ct ))" "$(( now - newest ))" "$behind"
  done <<EOF
$INDEXES
EOF
}

if [ "$REACH" -eq 1 ]; then
  reach_report
  native_report
  history_report
fi

[ "$OVER" -eq 0 ] || exit 1
exit 0
