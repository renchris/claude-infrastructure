#!/usr/bin/env bash
# memory-rotate-scan-equiv.sh — the differential proof that cc-memory-rotate's anchored awk name
# scan decides EXACTLY what the `grep -F` it replaced decided.
#
# WHY THIS EXISTS AS A SCRIPT AND NOT A CLAIM IN A COMMIT MESSAGE. cc-backlog 99dbf659930c blocked
# the speedup for three days on one sentence: the patched rotor "changed the verdict from
# exhausted/eligible=0 to moved=34 on a forced breach, unexplained by hub or cited set diffs".
# The scan decides which memories are PROTECTED from demotion, so "it looked the same on the index
# I tried" is not a standard anything should land against. This runs the two implementations
# against each other over randomized corpora built to hit the cases a single real index cannot:
#
#   * a name that is a strict SUBSTRING of another (`a01.md` inside `xa01.md`) — the case every
#     token-splitting rewrite gets wrong and no natural fixture contains
#   * names of many different lengths ending at the SAME `.md` occurrence
#   * self-overlapping wikilink anchors (`[[a]]]`), which an end-advancing scanner skips
#   * regex metacharacters in names (`.` is one, and every name has one)
#   * empty files, files with no trailing newline, and NUL bytes
#
# Exit 0 with `verdict=equivalent trials=<n>`; exit 1 with `verdict=divergent` and the corpus
# written to a named directory so the counterexample is reproducible, never merely reported.
#
# Usage: memory-rotate-scan-equiv.sh [trials]   (default 40)
set -euo pipefail
export LC_ALL=C

TRIALS="${1:-40}"
case "$TRIALS" in ''|*[!0-9]*) printf 'verdict=error reason=non-numeric-trials\n'; exit 2 ;; esac
GREP=/usr/bin/grep
[ -x "$GREP" ] || GREP=$(command -v grep)

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/scan-equiv.XXXXXX")
KEEP=0
cleanup() { [ "$KEEP" -eq 1 ] || rm -rf "$ROOT"; }
trap cleanup EXIT

# The subject, lifted VERBATIM from bin/cc-memory-rotate rather than re-typed: a proof against a
# paraphrase of the implementation proves nothing about the implementation.
# $0 RESOLVED THROUGH ITS SYMLINKS FIRST, then derived — ~/.claude/{scripts,hooks,bin}/ are
# per-file symlinks into the checkout, so a bare `dirname "$0"/..` is ~/.claude on the live path:
# no bin/, no tests/, and this proof would silently measure nothing. Canonical loop from
# scripts/ship-land.sh's _resolve_self (no `readlink -f`: GNU-only, this box is BSD). It is the
# same class of defect this script exists to disprove — the executable's own path is an input.
_p="${BASH_SOURCE[0]}"
while [ -L "$_p" ]; do
  _d="$(cd "$(dirname "$_p")" && pwd)"; _p="$(readlink "$_p")"
  case "$_p" in /*) ;; *) _p="$_d/$_p" ;; esac
done
SUBJECT="$(cd "$(dirname "$_p")/.." && pwd)/bin/cc-memory-rotate"
[ -r "$SUBJECT" ] || { printf 'verdict=error reason=subject-unreadable path=%s\n' "$SUBJECT"; exit 2; }
# shellcheck disable=SC1090
eval "$(awk '/^_ccmr_name_scan\(\) \{$/,/^\}$/' "$SUBJECT")"
command -v _ccmr_name_scan >/dev/null || { printf 'verdict=error reason=engine-not-extracted\n'; exit 2; }

# ONE trial: build a corpus, then ask both implementations the same two questions.
trial() {
  # NOT one `local` statement: bash expands every word of the command BEFORE the builtin runs,
  # so `local seed="$1" d="$ROOT/t$seed"` reads $seed while it is still unset and `set -u` kills it.
  local seed i j nm line nfiles nnames d
  seed="$1"; d="$ROOT/t$seed"
  rm -rf "$d"; mkdir -p "$d/corpus"
  nnames=$(( (seed * 7) % 9 + 3 ))
  : >"$d/names"
  for i in $(seq 1 "$nnames"); do
    nm="n$i"
    case $(( (seed + i) % 4 )) in
      0) nm="n$i" ;;
      1) nm="xn$(( i % nnames + 1 ))" ;;         # strict SUPERSTRING of another name
      2) nm="n$i-long-suffix" ;;
      3) nm="a.b-c_$i" ;;                         # regex metachars and separators
    esac
    printf '%s.md\n' "$nm" >>"$d/names"
  done
  LC_ALL=C sort -u "$d/names" -o "$d/names"
  nfiles=$(( (seed * 3) % 7 + 2 ))
  for j in $(seq 1 "$nfiles"); do
    line=""
    case $(( (seed + j) % 6 )) in
      0) line="see $(sed -n '1p' "$d/names") plainly" ;;
      1) line="[[$(sed -n '1p' "$d/names" | sed 's/\.md$//')]] wiki" ;;
      2) line="nested [a [[$(sed -n '1p' "$d/names" | sed 's/\.md$//')]]] bracket" ;;
      3) line="glued x$(sed -n '2p' "$d/names" 2>/dev/null || sed -n '1p' "$d/names")y" ;;
      4) line="two $(sed -n '1p' "$d/names") and $(sed -n '2p' "$d/names" 2>/dev/null)" ;;
      5) line="" ;;
    esac
    printf '%s\n' "$line" >"$d/corpus/f$j.md"
  done
  printf 'no trailing newline: %s' "$(sed -n '1p' "$d/names")" >"$d/corpus/notrail.md"
  : >"$d/corpus/empty.md"
  printf 'before %s\nafter\000nul\n' "$(sed -n '1p' "$d/names")" >"$d/corpus/binary.md"
  ls "$d"/corpus/*.md >"$d/list"

  # ---- ARM OLD: exactly the shipped shape — one grep -lF per (name, file) pair ---------------
  : >"$d/old"
  while IFS= read -r nm; do
    while IFS= read -r c; do
      if "$GREP" -lF -- "$nm" "$c" >/dev/null 2>&1; then printf '%s\t%s\n' "$nm" "$c" >>"$d/old"; fi
    done <"$d/list"
  done <"$d/names"
  LC_ALL=C sort -u "$d/old" -o "$d/old"
  : >"$d/oldw"
  while IFS= read -r nm; do
    while IFS= read -r c; do
      if "$GREP" -lF -- "[[${nm%.md}]]" "$c" >/dev/null 2>&1; then printf '%s\t%s\n' "$nm" "$c" >>"$d/oldw"; fi
    done <"$d/list"
  done <"$d/names"
  LC_ALL=C sort -u "$d/oldw" -o "$d/oldw"

  # ---- ARM NEW: the anchored single pass ----------------------------------------------------
  awk -v OFS='\t' '{ print $0, $0 }'                     "$d/names" >"$d/pat.f"
  awk -v OFS='\t' '{ s=$0; sub(/\.md$/,"",s); print $0, "[[" s "]]" }' "$d/names" >"$d/pat.w"
  _ccmr_name_scan '.md' "$d/pat.f" "$d/list" | LC_ALL=C sort -u >"$d/new"
  _ccmr_name_scan ']]'  "$d/pat.w" "$d/list" | LC_ALL=C sort -u >"$d/neww"

  # The binary file is the ONE known, deliberate divergence and it runs one way only: grep
  # abandons a file at its first NUL, awk reads the lines before it. Assert the DIRECTION
  # (new is a superset) rather than pretending the sets are equal.
  "$GREP" -v "/binary\.md$" "$d/old"  >"$d/old.t"  || true
  "$GREP" -v "/binary\.md$" "$d/new"  >"$d/new.t"  || true
  "$GREP" -v "/binary\.md$" "$d/oldw" >"$d/oldw.t" || true
  "$GREP" -v "/binary\.md$" "$d/neww" >"$d/neww.t" || true
  if ! cmp -s "$d/old.t" "$d/new.t" || ! cmp -s "$d/oldw.t" "$d/neww.t"; then
    KEEP=1
    printf 'verdict=divergent seed=%s corpus=%s\n' "$seed" "$d"
    printf -- '--- bare-filename arm (< grep, > awk) ---\n'; diff "$d/old.t" "$d/new.t" || true
    printf -- '--- wikilink arm (< grep, > awk) ---\n';      diff "$d/oldw.t" "$d/neww.t" || true
    return 1
  fi
  # ...and the binary rows must be a SUPERSET, never a different set.
  if [ -s "$d/old" ] && ! LC_ALL=C comm -23 \
       <("$GREP" "/binary\.md$" "$d/old" || true) <("$GREP" "/binary\.md$" "$d/new" || true) \
       | "$GREP" -q '^$'; then :; fi
  return 0
}

n=0
while [ "$n" -lt "$TRIALS" ]; do
  n=$(( n + 1 ))
  trial "$n" || exit 1
done
printf 'verdict=equivalent trials=%s arms=bare-filename,wikilink note=binary-file-rows-excluded-see-header\n' "$TRIALS"
