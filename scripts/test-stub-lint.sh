#!/bin/bash
# test-stub-lint.sh — rule R4: refuse a NEW inline `#!` stub write in tests/.
#
# On macOS 15.8.1 each execve() of a `#!` script by path retains ~1.1 KiB of kernel memory until reboot
# (docs/research/panic-2026-10-18-zone-map-shebang-leak.md). Test harnesses write inline `#!` stubs and
# exec them by name thousands of times a run, so the suite itself is a leak. cc_stub DIR NAME BODY
# (tests/helpers/cc-stub.bash) links the stub to a compiled trampoline instead. Hundreds of files predate
# it, so this is a RATCHET, not a ban: config/test-stub-baseline.tsv holds each file's count, a file may
# not exceed it (absent = 0), and a decrease is locked in by --write-baseline.
#
# A stub write is one line, never line 1 (a file's own shebang), that either
#   (a) writes a #! via printf/echo — `(printf|echo) ['"]#!`, shim.md §4.4 R4; or
#   (b) is a `#!` line directly under a heredoc opener (`<<EOF`, `<<-'EOF'`, `<< "SH"`; not `<<<`).
#
# Usage: test-stub-lint.sh · --files <path>... · --write-baseline · --selftest
# Exit: 0 clean · 1 a file exceeds its baseline · 2 no verdict (not a git repo, baseline unreadable)
# Env:  TEST_STUB_LINT_ROOT (repo root, default this script's git toplevel)
#       TEST_STUB_LINT_BASELINE (default <root>/config/test-stub-baseline.tsv)
set -uo pipefail

_p="${BASH_SOURCE[0]}"   # resolve the ~/.claude/scripts symlink first, or `..` is ~/.claude
while [ -L "$_p" ]; do _d="$(cd "$(dirname "$_p")" && pwd)"; _p="$(readlink "$_p")"
  case "$_p" in /*) ;; *) _p="$_d/$_p" ;; esac; done
SELF="$(cd "$(dirname "$_p")" && pwd)/$(basename "$_p")"
EXEMPT="tests/helpers/cc-stub.bash"   # the helper's own trampoline plumbing is the cure, not a stub
FIX="use cc_stub DIR NAME BODY (tests/helpers/cc-stub.bash)"

die2() { echo "test-stub-lint: $* — no verdict" >&2; exit 2; }

selftest() {
  local d rc
  d="$(mktemp -d "${TMPDIR:-/tmp}/test-stub-lint.XXXXXX")" || exit 2
  # shellcheck disable=SC2064  # expand $d now: it is local and gone by the time EXIT fires
  trap "case '$d' in */test-stub-lint.*) rm -rf '$d' ;; esac" EXIT
  mkdir -p "$d/tests/helpers" "$d/config" && git -C "$d" init -q || exit 2
  # One violation per detection form, a grandfathered file AT its ceiling, a decreased file, the exempt
  # helper, and the two shapes that must stay silent (line-1 shebang, heredoc not followed by #!).
  printf '#!/usr/bin/env bats\nprintf %s > x\n' "'#!/bin/sh\\nexit 0\\n'" > "$d/tests/a.bats"
  printf '#!/usr/bin/env bats\necho "#!/bin/sh" > x\n' > "$d/tests/b.bats"
  printf '#!/usr/bin/env bats\ncat > x <<'"'EOF'"'\n#!/bin/sh\nEOF\n' > "$d/tests/c.bats"
  printf '#!/usr/bin/env bats\necho "#!/bin/a" > x\necho "#!/bin/b" > y\n' > "$d/tests/g.bats"
  printf '#!/usr/bin/env bats\necho "#!/bin/a" > x\ncat > y <<EOF\nplain\nEOF\n' > "$d/tests/dec.bats"
  printf '#!/bin/bash\nprintf "#!/bin/sh\\n" > out\n' > "$d/$EXEMPT"
  # Bodies handed to cc_stub stay silent in all three spellings.
  # shellcheck disable=SC2016  # the fixture's own $(printf …), written literally
  printf '#!/usr/bin/env bats\ncc_stub d x - <<'"'EOF'"'\n#!/bin/sh\nEOF\ncc_stub d y "$(printf %s)"\ncc_stub d z \\\n  "$(printf %s)"\n' \
    "'#!/bin/sh\\n'" "'#!/bin/sh\\n'" > "$d/tests/cc.bats"
  printf '# fixture baseline\ntests/dec.bats\t3\ntests/g.bats\t2\n' > "$d/config/test-stub-baseline.tsv"
  git -C "$d" add -A || exit 2
  local out
  out="$(TEST_STUB_LINT_ROOT="$d" TEST_STUB_LINT_BASELINE="" /bin/bash "$SELF" 2>&1)"; rc=$?
  if [ "$rc" -ne 1 ]; then echo "test-stub-lint selftest: FAIL — fixture read rc $rc, want 1:" >&2
    echo "$out" >&2; exit 1; fi
  local f
  for f in a b c; do
    case "$out" in *"tests/$f.bats: 1 inline"*) ;; *)
      echo "test-stub-lint selftest: FAIL — tests/$f.bats not named:" >&2; echo "$out" >&2; exit 1 ;; esac
  done
  case "$out" in *g.bats:*|*dec.bats:*|*cc-stub.bash:*|*cc.bats:*)
    echo "test-stub-lint selftest: FAIL — a grandfathered, decreased or exempt file was convicted:" >&2
    echo "$out" >&2; exit 1 ;; esac
  # The fix-it: convert the three offenders and the same fixture must come back clean.
  for f in a b c; do printf '#!/usr/bin/env bats\ncc_stub bin x "exit 0"\n' > "$d/tests/$f.bats"; done
  out="$(TEST_STUB_LINT_ROOT="$d" TEST_STUB_LINT_BASELINE="" /bin/bash "$SELF" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then echo "test-stub-lint selftest: FAIL — fixed fixture read rc $rc:" >&2
    echo "$out" >&2; exit 1; fi
  echo "test-stub-lint selftest: ok"
  exit 0
}

mode="check"
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) selftest ;;
    --write-baseline) mode="write"; shift ;;
    --files) mode="files"; shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do files+=("$1"); shift; done ;;
    *) die2 "unknown argument $1" ;;
  esac
done

ROOT="${TEST_STUB_LINT_ROOT:-}"
[ -n "$ROOT" ] || ROOT="$(git -C "$(dirname "$SELF")" rev-parse --show-toplevel 2>/dev/null)" \
  || die2 "cannot resolve the repo root from $SELF"
cd "$ROOT" 2>/dev/null || die2 "root $ROOT is unreadable"
git rev-parse --git-dir >/dev/null 2>&1 || die2 "$ROOT is not a git repo"
BASE="${TEST_STUB_LINT_BASELINE:-$ROOT/config/test-stub-baseline.tsv}"
if [ "$mode" != write ]; then [ -r "$BASE" ] || die2 "baseline $BASE is unreadable"; fi

# Population: text files only (-I), via one git grep; --files also admits not-yet-added paths.
specs=()
if [ "$mode" = files ]; then
  for f in ${files[@]+"${files[@]}"}; do
    f="${f#./}"
    case "$f" in "$EXEMPT") continue ;; tests/*) [ -f "$f" ] && specs+=("$f") ;; esac
  done
  [ ${#specs[@]} -gt 0 ] || exit 0   # nothing of tests/ in scope (a deletion, or no tests/ files)
  untracked=(--untracked)
else
  specs=(tests ":(exclude)$EXEMPT")
  untracked=()
fi
tmp="$(mktemp "${TMPDIR:-/tmp}/test-stub-lint.pop.XXXXXX")" || exit 2
trap 'rm -f "$tmp"' EXIT
git -c color.grep=never grep ${untracked[@]+"${untracked[@]}"} -I -l -z -e '' -- "${specs[@]}" > "$tmp"
grc=$?
[ "$grc" -le 1 ] || die2 "git grep failed (rc $grc)"
pop=()
while IFS= read -r -d '' f; do pop+=("$f"); done < "$tmp"

# One awk pass over the whole population: F rows name every file scanned, H rows every stub write.
hits=""
if [ ${#pop[@]} -gt 0 ]; then
  hits="$(awk -v q="'" '
    BEGIN { a = "(printf|echo)[ \t]+[" q "\"]#!"; h = "<<-?[ \t]*\\\\?[" q "\"]?[A-Za-z_]" }
    FNR == 1 { print "F\t" FILENAME; prev = $0; next }
    {
      # A body handed to cc_stub is the cure, not a stub write: on the cc_stub line itself, on the
      # continuation line after it, or under its heredoc.
      viacc = ($0 ~ /cc_stub/ || (prev ~ /cc_stub/ && prev ~ /\\[ \t]*$/))
      hit = ($0 ~ a) && !viacc
      if (!hit && $0 ~ /^[ \t]*#!/ && prev !~ /cc_stub/) { p = prev; gsub(/<<</, "", p); hit = (p ~ h) }
      if (hit) print "H\t" FILENAME "\t" FNR
      prev = $0
    }' "${pop[@]}")" || die2 "awk failed over the population"
fi

if [ "$mode" = write ]; then
  out="$BASE.tmp.$$"
  {
    echo "# test-stub-baseline.tsv — per-file count of inline #! stub writes under tests/: rule R4's ceiling."
    echo "# Each exec of a #! stub by path leaks ~1.1 KiB of kernel memory on macOS 15.8.1 until reboot."
    echo "# scripts/test-stub-lint.sh refuses any file whose count EXCEEDS its row here (absent = 0)."
    echo "# Convert a stub with cc_stub DIR NAME BODY (tests/helpers/cc-stub.bash), then lock the decrease"
    echo "# in with: scripts/test-stub-lint.sh --write-baseline. Columns: <path>TAB<count>, LC_ALL=C order."
    printf '%s\n' "$hits" | awk -F'\t' '$1 == "H" { n[$2]++ } END { for (f in n) print f "\t" n[f] }' \
      | LC_ALL=C sort
  } > "$out" && mv "$out" "$BASE" || { rm -f "$out"; die2 "cannot write $BASE"; }
  echo "test-stub-lint: wrote $BASE ($(grep -vc '^#' "$BASE") file(s))" >&2
  exit 0
fi

report="$(printf '%s\n' "$hits" | awk -F'\t' -v fix="$FIX" -v whole="$([ "$mode" = check ] && echo 1)" '
  FNR == NR { if ($0 !~ /^#/ && NF >= 2) base[$1] = $2 + 0; next }
  $1 == "F" { seen[$2] = 1; next }
  $1 == "H" { n[$2]++; ln[$2] = ln[$2] " " $3 }
  END {
    for (f in n) {
      b = (f in base) ? base[f] : 0
      if (n[f] > b) printf "R\t%s\t%s: %d inline #! stub write(s), baseline %d — %s\t  lines:%s\n", f, f, n[f], b, fix, ln[f]
    }
    for (f in base) if ((whole || (f in seen)) && (f in n ? n[f] : 0) < base[f]) dec++
    if (dec) printf "N\t%d\n", dec
  }' "$BASE" -)"

red="$(printf '%s\n' "$report" | awk -F'\t' '$1 == "R"' | LC_ALL=C sort -t "$(printf '\t')" -k2,2 \
  | awk -F'\t' '{ print $3; print $4 }')"
dec="$(printf '%s\n' "$report" | awk -F'\t' '$1 == "N" { print $2 }')"
[ -z "$dec" ] || echo "test-stub-lint: $dec file(s) now below baseline — lock in with --write-baseline" >&2
if [ -n "$red" ]; then
  printf '%s\n' "$red"
  exit 1
fi
exit 0
