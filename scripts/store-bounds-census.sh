#!/bin/bash
# store-bounds-census.sh — every append-only store has a DECLARED cap, and something notices a breach.
#
# WHY (row 13 M9c, MACHINE_CAPACITY_V2.md §11.3). §8.5.5 named eight stores that grow without a bound:
# 36 MB of bash-execution.log, 34 MB of bash-commands.log, 21 MB of idl.jsonl, a 50 MB session-index.db
# beside a 49 MB stale .bak of itself, and so on. Each is individually harmless and collectively a
# monotonic leak that nothing in the repo was watching. Fixing them one at a time leaves the CLASS
# alive — the ninth store ships next week unwatched. So the bound becomes DATA
# (config/store-bounds.manifest) and this walks it.
#
# IT NEVER DELETES, ROTATES, OR TRUNCATES — and that is a hard property, tested, not a convention.
# It measures, compares, and PAGES; the remedy is text for the store's owner to run. Deletion is the
# destination's property, never the census's decision: memory append-only-store-safety-rules records
# an "archive" step whose `mv -f` destroyed 1,461 lines. A tool that both watches and prunes will
# eventually prune on a bad read, and this tool's whole job is to be trusted about numbers.
#
# THE READ IS BOUNDED BY CONSTRUCTION. Each manifest glob is expanded exactly as written, one level,
# never walked recursively. ~/.claude contains the 7,359-file / 4.26 GB transcript corpus under
# projects/; a `find` over it would make this census its own load problem — the exact self-defeat
# pattern this row exists to eliminate. Globs are also rejected if they contain `..`.
#
# Verdicts (three, and the third is why this is trustworthy):
#   OK       every declared store is within its cap.                          exit 0
#   BREACH   at least one store is over its cap.                              exit 1
#   NO-DATA  the root does not exist, or the manifest yielded no usable rows.  exit 3
#
# THERE IS DELIBERATELY NO exit 2. capacity-alarm.sh has WARN/ALARM because memory pressure has two
# genuinely different severities (approaching vs already swapping). A store is over its declared cap or
# it is not; splitting that into two tiers would require a second threshold nobody has calibrated, and
# an uncalibrated number in a verdict is the defect R9 forbids.
#
# NO-DATA IS NOT "no breaches". If $HOME/.claude is missing, every glob matches nothing, every store
# sums to 0, and a naive reading reports a clean OK — a fixtured void reporting success. The root's
# existence is therefore checked as its own precondition (memory
# absence-alarm-needs-existence-evidence: gate on the producer's world existing). A glob that matches
# nothing while the root DOES exist is genuinely OK — an absent store is not a growth problem.
#
# Seams: CC_STORE_BOUNDS=off (kill switch) · CC_SB_ROOT (default $HOME/.claude) ·
#        CC_SB_MANIFEST · CC_SB_LOG · CC_SB_PAGE=off · CC_PAGES_DIR · CC_SB_SELFTEST=1
#
# bash 3.2 safe. Ships to launchd ⇒ tested under /bin/bash.

set -uo pipefail

# Resolve $0 through any symlink chain BEFORE deriving the manifest path. The live layer symlinks
# scripts/ into this checkout per-file, so `dirname $0` there is ~/.claude/scripts — and
# ../config/store-bounds.manifest under it does not exist (top-level config/ never auto-deploys).
# memory shared-lib-source-ladder-collapses-when-deployed: resolve the link, then derive.
SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF" 2>/dev/null)" || break
  [ -n "$_link" ] || break
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
SELF_DIR="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd -P)" || SELF_DIR="."

ROOT="${CC_SB_ROOT:-$HOME/.claude}"
MANIFEST="${CC_SB_MANIFEST:-$SELF_DIR/../config/store-bounds.manifest}"
LOG="${CC_SB_LOG:-$HOME/.claude/logs/store-bounds.jsonl}"
PAGES_DIR="${CC_PAGES_DIR:-$HOME/.claude/autonomy/pages}"
PAGE="$PAGES_DIR/store-bounds.page"
APPEND=1; WANT_JSON=0; QUIET=0

while [ $# -gt 0 ]; do
  if   [ "$1" = "--json" ];      then WANT_JSON=1
  elif [ "$1" = "--quiet" ];     then QUIET=1
  elif [ "$1" = "--no-append" ]; then APPEND=0
  elif [ "$1" = "--selftest" ];  then CC_SB_SELFTEST=1
  elif [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0
  else echo "store-bounds-census.sh: unknown arg '$1'" >&2; exit 64
  fi
  shift
done

if [ "${CC_STORE_BOUNDS:-on}" = "off" ]; then
  [ "$QUIET" = 1 ] || echo "store-bounds: disabled (CC_STORE_BOUNDS=off)"
  exit 0
fi

# ── manifest parsing ──────────────────────────────────────────────────────────────────────────────
# Emits one tab-separated record per line: `OK<TAB>glob<TAB>cap<TAB>owner<TAB>remedy` or `BAD<TAB>line`.
# A malformed row is IGNORED AND COUNTED, never fatal and never silently dropped: a manifest that
# fails to parse must not narrow the corpus while still reporting a clean verdict. The remedy field
# absorbs the remainder of the line, so a remedy may itself contain `|`.
parse_manifest() { # <file>
  [ -f "$1" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    # strip a trailing CR (a manifest edited on another platform must not fail on invisible bytes)
    line="${line%$'\r'}"
    # trim leading blanks fork-free, so an INDENTED comment is still a comment
    while :; do
      case "$line" in
        ' '*)   line="${line# }" ;;
        $'\t'*) line="${line#$'\t'}" ;;
        *)      break ;;
      esac
    done
    case "$line" in ''|'#'*) continue ;; esac

    IFS='|' read -r g cap owner remedy <<EOF
$line
EOF
    # every field must be present and the cap must be a positive integer
    if [ -z "${g:-}" ] || [ -z "${cap:-}" ] || [ -z "${owner:-}" ] || [ -z "${remedy:-}" ]; then
      printf 'BAD\t%s\n' "$line"; continue
    fi
    case "$cap" in ''|*[!0-9]*) printf 'BAD\t%s\n' "$line"; continue ;; esac
    [ "$cap" -gt 0 ] || { printf 'BAD\t%s\n' "$line"; continue; }
    # a glob must stay inside the root: relative, and no `..` escape
    case "$g" in /*|*..*) printf 'BAD\t%s\n' "$line"; continue ;; esac
    printf 'OK\t%s\t%s\t%s\t%s\n' "$g" "$cap" "$owner" "$remedy"
  done < "$1"
  return 0
}

# ── sizing ────────────────────────────────────────────────────────────────────────────────────────
# Sums BYTES via stat, not `du -m`: du reports allocated blocks rounded per file, so a glob matching
# three files can read several MB over the bytes actually stored — a ratchet must not page on
# filesystem rounding. Comparison happens in bytes; MB is only ever a presentation.
sum_bytes() { # <glob-relative-to-root> → "<bytes> <files>"
  local pat="$ROOT/$1" total=0 n=0 f sz
  # IFS pinned to newline so a path containing a SPACE is not word-split. Pathname expansion happens
  # after word splitting and its results are already separate words, so globbing still works.
  local IFS=$'\n'
  # shellcheck disable=SC2086  # unquoted ON PURPOSE — this is the pathname expansion, the whole point
  for f in $pat; do
    [ -f "$f" ] || continue          # -f, not -e: a directory is not a store
    sz="$(stat -f %z "$f" 2>/dev/null)"
    case "${sz:-}" in ''|*[!0-9]*) continue ;; esac
    total=$((total + sz)); n=$((n + 1))
  done
  printf '%s %s\n' "$total" "$n"
}

mb() { awk -v b="$1" 'BEGIN{printf "%.1f", b/1048576}'; }

# Strip the two characters that could break the JSON this emits. The strings come from a repo-owned
# manifest, but "reviewed input" is not a parser — one stray quote would emit a row no consumer can
# read, and a log nobody can parse is a log nobody keeps. Done with parameter expansion (fork-free,
# and it sidesteps the backslash-adjacent-to-quote form that reads as an escaped quote); the result
# lands in JSAN rather than on stdout so the hot loop stays free of subshells.
JSAN=''
jsan() { JSAN="${1//\\/}"; JSAN="${JSAN//\"/}"; }

# ── verdict ───────────────────────────────────────────────────────────────────────────────────────
classify() { # <root_exists 0|1> <valid_rows> <breaches> → prints verdict
  if [ "$1" != "1" ]; then printf 'NO-DATA'; return 0; fi
  if [ "${2:-0}" -eq 0 ]; then printf 'NO-DATA'; return 0; fi
  if [ "${3:-0}" -gt 0 ]; then printf 'BREACH'; return 0; fi
  printf 'OK'
}

# ── positive control (R6) — prove every rung is reachable, and prove the PARSER too ───────────────
# Without this, "OK" is indistinguishable from "the comparison never fires". The classifier probes are
# arithmetic; the parser probe matters more, because the failure that would actually hurt is a parser
# that silently drops rows and then reports a clean verdict over an empty corpus.
if [ "${CC_SB_SELFTEST:-0}" = "1" ]; then
  fails=0
  for probe in "1:8:0:OK" "1:8:1:BREACH" "1:8:9:BREACH" "0:8:0:NO-DATA" "1:0:0:NO-DATA" "0:0:1:NO-DATA"; do
    r="${probe%%:*}";  rest="${probe#*:}"
    rows="${rest%%:*}"; rest="${rest#*:}"
    br="${rest%%:*}";   want="${rest#*:}"
    got="$(classify "$r" "$rows" "$br")"
    if [ "$got" = "$want" ]; then
      echo "  control OK   root='$r' rows='$rows' breaches='$br' → $got"
    else
      echo "  control FAIL root='$r' rows='$rows' breaches='$br' → $got (want $want)"; fails=$((fails+1))
    fi
  done

  # parser control: a synthetic manifest with one comment, one blank, one indented comment, three
  # malformed rows (short / non-numeric cap / `..` escape) and two good rows ⇒ exactly 2 OK, 3 BAD.
  st="${TMPDIR:-/tmp}/store-bounds-selftest.$$"
  {
    echo '# a comment'
    echo ''
    echo '   # an indented comment'
    echo 'logs/a.log|10|6|rotate'
    echo 'logs/short.log|10'
    echo 'logs/b.log|notanumber|6|rotate'
    echo '../escape.log|10|6|rotate'
    echo 'logs/c.log|20|-|rotate: keeps | a pipe'
  } > "$st"
  pok="$(parse_manifest "$st" | grep -c '^OK' || true)"
  pbad="$(parse_manifest "$st" | grep -c '^BAD' || true)"
  rm -f "$st"
  if [ "$pok" = "2" ] && [ "$pbad" = "3" ]; then
    echo "  control OK   parser valid=$pok malformed=$pbad (comments/blanks ignored, dotdot rejected)"
  else
    echo "  control FAIL parser valid=$pok malformed=$pbad (want 2 / 3)"; fails=$((fails+1))
  fi

  # NEVER-DESTRUCTIVE control: assert the property by reading this file's own EXECUTABLE lines.
  # Comments are stripped first — the header discusses deletion at length, and a guard that convicted
  # its own documentation would be the defect in memory detector-matching-its-own-skill-description.
  #
  # THE GUARD IS SCOPED TO STORE PATHS, not to the word `rm`. The first draft forbade `rm -f` outright
  # and immediately convicted this file's own page retraction (`rm -f "$PAGE"`) — which is correct
  # behaviour, not a violation: self-clearing a page it wrote is nothing like touching a store. So the
  # pattern requires a destructive verb (or a redirection) aimed at a path derived from the ROOT or
  # from the glob expansion — the only paths that are somebody's data.
  # `[$]` rather than `\$` for the literal dollar: it keeps the two characters `$(` out of the pattern
  # entirely, so the regex cannot be misread (by ShellCheck or by a human) as a command substitution.
  if sed 's/#.*//' "$SELF" \
     | grep -qE '(\brm\b|\bmv\b|\btruncate\b|\bgzip\b|\bshred\b|\bsed[[:space:]]+-i\b)[^;&|]*[$](ROOT|f|pat|glob)\b|>[[:space:]]*"?[$](ROOT|f|pat|glob)\b'; then
    echo "  control FAIL a destructive verb targets a store path on an executable line"; fails=$((fails+1))
  else
    echo "  control OK   no destructive verb targets any store path (measure-only)"
  fi

  [ "$fails" -eq 0 ] && { echo "store-bounds: selftest GREEN (3 rungs + parser + measure-only)"; exit 0; }
  echo "store-bounds: selftest RED ($fails)" >&2; exit 70
fi

# ── the census ────────────────────────────────────────────────────────────────────────────────────
ROOT_OK=0; [ -d "$ROOT" ] && ROOT_OK=1

ROWS=0; MALFORMED=0; BREACHES=0; TOTAL_BYTES=0
STORES_JSON=''; BREACH_LINES=''

if [ "$ROOT_OK" = 1 ]; then
  while IFS=$'\t' read -r kind a b c d; do
    if [ "$kind" = "BAD" ]; then MALFORMED=$((MALFORMED + 1)); continue; fi
    [ "$kind" = "OK" ] || continue
    glob="$a"; cap="$b"; owner="$c"; remedy="$d"
    ROWS=$((ROWS + 1))

    sb="$(sum_bytes "$glob")"
    bytes="${sb%% *}"; files="${sb##* }"
    case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
    case "$files" in ''|*[!0-9]*) files=0 ;; esac
    TOTAL_BYTES=$((TOTAL_BYTES + bytes))

    size_mb="$(mb "$bytes")"
    cap_bytes=$((cap * 1048576))
    is_breach=false
    if [ "$bytes" -gt "$cap_bytes" ]; then
      is_breach=true
      BREACHES=$((BREACHES + 1))
      BREACH_LINES="${BREACH_LINES}  ${glob} ${size_mb}/${cap}MB owner=${owner} remedy=${remedy}
"
    fi

    jsan "$glob";   j_glob="$JSAN"
    jsan "$owner";  j_own="$JSAN"
    jsan "$remedy"; j_rem="$JSAN"
    [ -z "$STORES_JSON" ] || STORES_JSON="${STORES_JSON},"
    STORES_JSON="${STORES_JSON}$(printf '{"store":"%s","mb":%s,"cap_mb":%s,"files":%s,"owner":"%s","breach":%s,"remedy":"%s"}' \
      "$j_glob" "$size_mb" "$cap" "$files" "$j_own" "$is_breach" "$j_rem")"
  done <<EOF
$(parse_manifest "$MANIFEST" || true)
EOF
fi

VERDICT="$(classify "$ROOT_OK" "$ROWS" "$BREACHES")"
case "$VERDICT" in
  OK)     RC=0 ;;
  BREACH) RC=1 ;;
  *)      RC=3 ;;
esac

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TOTAL_MB="$(mb "$TOTAL_BYTES")"
jsan "$ROOT"; J_ROOT="$JSAN"
JSON="$(printf '{"ts":"%s","verdict":"%s","rows":%s,"malformed":%s,"breaches":%s,"total_mb":%s,"root":"%s","stores":[%s]}' \
  "$TS" "$VERDICT" "$ROWS" "$MALFORMED" "$BREACHES" "$TOTAL_MB" "$J_ROOT" "$STORES_JSON")"

if [ "$APPEND" = 1 ]; then
  mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
  printf '%s\n' "$JSON" >> "$LOG" 2>/dev/null || true
fi

# ── page the operator on BREACH, and SELF-CLEAR otherwise ─────────────────────────────────────────
# ONE FIXED SLUG, mirroring capacity-alarm.sh: every write overwrites the same file, so a job on an
# interval cannot accumulate pages the way the unslugged channel has (490 files on disk). Damping by
# construction rather than by a separate damper.
#
# AND IT SELF-CLEARS. A page whose condition has passed is misinformation, not history — the durable
# record is the append-only jsonl. NO-DATA clears too: leaving a stale BREACH up while blind would be
# asserting a condition we can no longer see.
if [ "${CC_SB_PAGE:-on}" != "off" ] && [ "$APPEND" = 1 ]; then
  if [ "$VERDICT" = "BREACH" ]; then
    mkdir -p "$PAGES_DIR" 2>/dev/null || true
    {
      date +%s 2>/dev/null || echo 0
      printf 'store-bounds BREACH — %s of %s declared stores over cap (%s MB total under %s)\n' \
        "$BREACHES" "$ROWS" "$TOTAL_MB" "$ROOT"
      printf '%s' "$BREACH_LINES"
      printf 'This census NEVER deletes, rotates, or truncates — the remedy above is yours to run.\n'
      printf 'Caps live in config/store-bounds.manifest; raising one is a decision with a reason.\n'
      printf 're-run:  %s\n' "$0"
    } > "$PAGE" 2>/dev/null || true
  else
    rm -f "$PAGE" "$PAGE.notified" 2>/dev/null || true
  fi
fi

if [ "$QUIET" != 1 ] && [ "$WANT_JSON" != 1 ]; then
  echo "store-bounds — $TS"
  echo "  root:                   $ROOT"
  echo "  manifest:               $MANIFEST"
  echo "  declared stores:        $ROWS   (malformed rows ignored: $MALFORMED)"
  echo "  total measured:         $TOTAL_MB MB"
  echo "  breaches:               $BREACHES"
  if [ -n "$BREACH_LINES" ]; then printf '%s' "$BREACH_LINES"; fi
  echo "  VERDICT:                $VERDICT"
  if [ "$VERDICT" = "BREACH" ]; then
    echo "  This census never deletes, rotates, or truncates. Run the named remedy, or change the cap"
    echo "  in config/store-bounds.manifest with a reason."
  fi
fi
[ "$WANT_JSON" = 1 ] && printf '%s\n' "$JSON"
exit "$RC"
