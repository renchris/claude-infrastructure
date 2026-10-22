#!/bin/bash
# shasum-lint.sh — refuse a tracked file that runs `shasum`.
#
# /usr/bin/shasum is a `#!` perl script. On macOS 15.8.1 every exec of a `#!` script by path keeps
# ~1.1 KiB of kernel memory (data.kalloc.1024) until reboot, and the zone's ~20 GiB ceiling panics
# the kernel (docs/research/panic-2026-10-18-zone-map-shebang-leak.md). /sbin/sha256sum and
# /sbin/sha1sum are Mach-O and print byte-identical output, so every call site runs those instead
# (hooks/lib/shasum-direct.sh, or the two-line CC_SHA256/CC_SHA1 resolver at the top of a file).
#
# A finding is a NON-COMMENT line naming `shasum` in command position (line start, after a pipe,
# `;`, `&&`, `||`, `$(`, `(`, `{`, a backtick, or after then/do/else/exec/-exec/xargs/env/time/
# timeout/nice), a probe of it (`command -v`, `type`, `which`, `hash`), or the path /usr/bin/shasum
# anywhere. A word inside a list (`… rm shasum md5 …`) is a name, not a call, and reads clean.
# Scope: `git ls-files` minus docs/, *.md and tests/ (fixtures there quote shasum on purpose).
#
# Usage: shasum-lint.sh [--file F]... · --selftest · --print-scope
# Exit: 0 clean · 1 findings · 2 no verdict (not a git checkout, unreadable file)
set -uo pipefail

_p="${BASH_SOURCE[0]}"   # resolve the ~/.claude/scripts symlink first, or `..` is ~/.claude
while [ -L "$_p" ]; do _d="$(cd "$(dirname "$_p")" && pwd)"; _p="$(readlink "$_p")"
  case "$_p" in /*) ;; *) _p="$_d/$_p" ;; esac; done
ROOT="$(cd "$(dirname "$_p")/.." && pwd)"
SELF_REL="scripts/shasum-lint.sh"
PATHSPEC=(. ':!docs' ':!*.md' ':!tests' ":!$SELF_REL")

# Lines that name shasum as DATA, pinned by file AND whole-line content so a real call added to the
# same file still reads RED. Format: <path><TAB><ERE over the whole line>.
EXEMPT="$(printf '%s\t%s\n' \
  'scripts/unattended-path-lint.sh' '^shasum$')"   # its binary-name inventory (one name per line)

# The predicate. Reads `path:line:content` (grep -n -H / git grep -n), prints each finding as
# `path:line: content`. awk ERE, POSIX classes only, so it runs under BSD and GNU awk alike.
_judge() {
  awk -v exempt="$EXEMPT" '
    BEGIN {
      n = split(exempt, rows, "\n")
      for (i = 1; i <= n; i++) { if (split(rows[i], kv, "\t") == 2) { ex_f[i] = kv[1]; ex_re[i] = kv[2] } }
      ne = n
      pre = "(^|[|;&({!`]|\\$\\(|[[:space:]](then|do|else|exec|-exec|xargs|env|time|timeout|nice))"
      call = pre "[[:space:]]*shasum([[:space:]]|$|[;|)&<>`\"(])"
      probe = "(command[[:space:]]+-[vV]|type([[:space:]]+-[a-zA-Z]+)?|which|hash)[[:space:]]+shasum([^a-zA-Z0-9_-]|$)"
    }
    {
      p1 = index($0, ":"); if (!p1) next
      f = substr($0, 1, p1 - 1); rest = substr($0, p1 + 1)
      p2 = index(rest, ":"); if (!p2) next
      ln = substr(rest, 1, p2 - 1); line = substr(rest, p2 + 1)
      if (line ~ /^[[:space:]]*#/) next
      code = line; sub(/[[:space:]]#.*$/, "", code)       # drop a trailing comment
      skip = 0
      for (i = 1; i <= ne; i++) if (f == ex_f[i] && line ~ ex_re[i]) skip = 1
      if (skip) next
      if (code ~ /\/usr\/bin\/shasum/ || code ~ call || code ~ probe) printf "%s:%s: %s\n", f, ln, line
    }'
}

_scan_files() { # files… → findings on stdout; rc 0 clean · 1 findings · 2 unreadable
  local f out rc=0
  for f in "$@"; do [ -r "$f" ] || { echo "shasum-lint: $f is unreadable — no verdict" >&2; return 2; }; done
  out="$(grep -n -H -I -E 'shasum' -- "$@" 2>/dev/null | _judge)"
  [ -n "$out" ] && { printf '%s\n' "$out"; rc=1; }
  return "$rc"
}

_scan_tree() { # → findings over the tracked scope of $ROOT
  local out
  git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || { echo "shasum-lint: $ROOT is not a git checkout — no verdict" >&2; return 2; }
  out="$(git -C "$ROOT" grep -n -I -E 'shasum' -- "${PATHSPEC[@]}" 2>/dev/null | _judge)"
  [ -z "$out" ] && return 0
  printf '%s\n' "$out"
  return 1
}

case "${1:-}" in
  --selftest)
    d="$(mktemp -d "${TMPDIR:-/tmp}/shasum-lint.XXXXXX")" || exit 2
    trap 'rm -f "$d"/call.sh "$d"/comment.sh "$d"/list.sh; rmdir "$d" 2>/dev/null' EXIT
    w=sha; w="${w}sum"   # the fixture's word, spelled so this file's own text stays clean
    # shellcheck disable=SC2016  # the fixture's own $( ), written literally
    printf '#!/bin/bash\nk="$(printf x | %s | cut -c1-16)"\n' "$w" > "$d/call.sh"
    printf '#!/bin/bash\n# was: printf x | %s -a 256\nk=1   # not %s any more\n' "$w" "$w" > "$d/comment.sh"
    printf '#!/bin/bash\nTOOLS=(sort uniq rm %s md5)\n' "$w" > "$d/list.sh"
    _scan_files "$d/call.sh" >/dev/null && { echo "shasum-lint selftest: FAIL — a piped $w call read clean" >&2; exit 1; }
    _scan_files "$d/comment.sh" >/dev/null || { echo "shasum-lint selftest: FAIL — a comment-only fixture read RED" >&2; exit 1; }
    _scan_files "$d/list.sh" >/dev/null || { echo "shasum-lint selftest: FAIL — a name inside a list read RED" >&2; exit 1; }
    for c in "$w -a 256 f" "x=\$($w f)" "a && $w f" "command -v $w" "[ -x /usr/bin/$w ]" "find . -exec $w {} +"; do
      printf '%s\n' "$c" > "$d/call.sh"
      _scan_files "$d/call.sh" >/dev/null && { echo "shasum-lint selftest: FAIL — '$c' read clean" >&2; exit 1; }
    done
    echo "shasum-lint selftest: ok"
    exit 0 ;;
  --print-scope) git -C "$ROOT" ls-files -- "${PATHSPEC[@]}"; exit $? ;;
esac

files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || { echo "shasum-lint: --file needs a path" >&2; exit 2; }; files+=("$2"); shift 2 ;;
    *) echo "shasum-lint: unknown argument $1" >&2; exit 2 ;;
  esac
done

if [ ${#files[@]} -gt 0 ]; then _scan_files "${files[@]}"; else _scan_tree; fi
rc=$?
[ "$rc" -eq 1 ] && echo "shasum-lint: RED — run \"\$CC_SHA256\"/\"\$CC_SHA1\" (/sbin/sha256sum, /sbin/sha1sum), never shasum (a #! perl script)" >&2
exit "$rc"
