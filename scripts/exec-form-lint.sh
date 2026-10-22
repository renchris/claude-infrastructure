#!/bin/bash
# exec-form-lint.sh — rule R2: refuse a NEW place where our shell code runs a tracked #! file by path.
#
# macOS 15.8.1 keeps ~1.1 KiB of kernel memory for every #! file the kernel execs by path, until reboot
# (docs/plans/KALLOC_TRIGGER_ELIMINATION_2026-10-22.md W4; REPORT §3 Phase 4). Running the interpreter
# with the script as its argument runs the same program with no kernel #! exec: `cc_run "$X" …`, or
# `cc_argv "$X"; timeout 5 "${CC_ARGV[@]}" …` (scripts/lib/cc-run.sh), or the script's own shebang
# written out (`/bin/bash "$HOME/.claude/scripts/x.sh"`). The predicate — what counts as a by-path run,
# through which relays — is scripts/exec-form-lint.py's; this file is the ratchet around it.
#
# Hundreds of call sites predate the rule, so it is a RATCHET, not a ban (the shape of W3's
# test-stub-lint.sh): config/exec-form-baseline.tsv holds each file's count, a file may not exceed it
# (absent = 0), and a decrease is locked in with --write-baseline.
#
# Usage: exec-form-lint.sh · --files <path>... · --list [<path>...] · --write-baseline · --selftest
# Exit: 0 clean · 1 a file exceeds its baseline · 2 no verdict (no git repo, baseline or predicate missing)
# Env:  EXEC_FORM_LINT_ROOT (repo root, default this script's git toplevel)
#       EXEC_FORM_LINT_BASELINE (default <root>/config/exec-form-baseline.tsv)
set -uo pipefail

_p="${BASH_SOURCE[0]}"   # resolve the ~/.claude/scripts symlink first, or `..` is ~/.claude
while [ -L "$_p" ]; do _d="$(cd "$(dirname "$_p")" && pwd)"; _p="$(readlink "$_p")"
  case "$_p" in /*) ;; *) _p="$_d/$_p" ;; esac; done
SELF="$(cd "$(dirname "$_p")" && pwd)/$(basename "$_p")"
PRED="${SELF%/*}/exec-form-lint.py"
# shellcheck disable=SC2016  # the fix-it names shell syntax literally
FIX='run it through its interpreter: cc_run "$X" … / cc_argv "$X"; <relay> "${CC_ARGV[@]}" … (scripts/lib/cc-run.sh)'

die2() { echo "exec-form-lint: $* — no verdict" >&2; exit 2; }
[ -f "$PRED" ] || die2 "predicate missing at $PRED"

selftest() {
  local d rc out
  d="$(mktemp -d "${TMPDIR:-/tmp}/exec-form-lint.XXXXXX")" || exit 2
  # shellcheck disable=SC2064  # expand $d now: it is local and gone by the time EXIT fires
  trap "case '$d' in */exec-form-lint.*) rm -rf '$d' ;; esac" EXIT
  mkdir -p "$d/bin" "$d/scripts" "$d/config" && git -C "$d" init -q || exit 2
  printf '#!/bin/bash\necho tool\n' > "$d/bin/tool"; chmod 755 "$d/bin/tool"
  printf '#!/bin/bash\necho helper\n' > "$d/scripts/helper.sh"; chmod 755 "$d/scripts/helper.sh"
  printf 'not a script\n' > "$d/bin/data"; chmod 755 "$d/bin/data"
  # One violation per form: a literal path, a seam variable, resolve_bin under a relay chain, find -exec,
  # a beside-script path. Then the shapes that must stay silent.
  # shellcheck disable=SC2016  # fixture text, written literally
  printf '%s\n' '#!/bin/bash' \
    '"$HOME/.claude/bin/tool" a' \
    'T="${CC_TOOL_BIN:-$HOME/.claude/bin/tool}"' 'x=$("$T" b)' \
    'H="$(resolve_bin "${CC_H_BIN:-}" helper.sh)"' 'exec timeout -k 5 10 nohup "$H"' \
    'find . -name x -exec "$HOME/.claude/scripts/helper.sh" {} +' \
    '"$(dirname "$0")/helper.sh" c' > "$d/scripts/bad.sh"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/bash' \
    '/bin/bash "$HOME/.claude/bin/tool" a' 'cc_run "$HOME/.claude/bin/tool" a' \
    'T="$HOME/.claude/bin/tool"; [ -x "$T" ] && command -v "$T"' 'cc_argv "$T"; timeout 5 "${CC_ARGV[@]}"' \
    'case "$T" in bin/tool) echo ;; esac' 'for f in "$HOME/.claude/bin/tool"; do :; done' \
    '# "$HOME/.claude/bin/tool" in a comment' 'echo "$HOME/.claude/bin/tool"' '"$HOME/.claude/bin/data"' \
    'tool' > "$d/scripts/good.sh"
  printf '# fixture\nscripts/grand.sh\t1\n' > "$d/config/exec-form-baseline.tsv"
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/bash' '"$HOME/.claude/bin/tool"' > "$d/scripts/grand.sh"
  git -C "$d" add -A || exit 2
  out="$(EXEC_FORM_LINT_ROOT="$d" EXEC_FORM_LINT_BASELINE="" /bin/bash "$SELF" 2>&1)"; rc=$?
  if [ "$rc" -ne 1 ]; then echo "exec-form-lint selftest: FAIL — fixture read rc $rc, want 1:" >&2
    echo "$out" >&2; exit 1; fi
  case "$out" in *"scripts/bad.sh: 5 by-path"*) ;; *)
    echo "exec-form-lint selftest: FAIL — bad.sh not convicted 5 times:" >&2; echo "$out" >&2; exit 1 ;; esac
  case "$out" in *good.sh*|*grand.sh*)
    echo "exec-form-lint selftest: FAIL — a clean or grandfathered file was convicted:" >&2
    echo "$out" >&2; exit 1 ;; esac
  # The fix-it: run every site through the runner and the same fixture must come back clean.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/bin/bash' 'cc_run "$HOME/.claude/bin/tool" a' > "$d/scripts/bad.sh"
  out="$(EXEC_FORM_LINT_ROOT="$d" EXEC_FORM_LINT_BASELINE="" /bin/bash "$SELF" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then echo "exec-form-lint selftest: FAIL — fixed fixture read rc $rc:" >&2
    echo "$out" >&2; exit 1; fi
  echo "exec-form-lint selftest: ok"
  exit 0
}

mode="check"
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --selftest) selftest ;;
    --write-baseline) mode="write"; shift ;;
    --list) mode="list"; shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do files+=("$1"); shift; done ;;
    --files) mode="files"; shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do files+=("$1"); shift; done ;;
    *) die2 "unknown argument $1" ;;
  esac
done

ROOT="${EXEC_FORM_LINT_ROOT:-}"
[ -n "$ROOT" ] || ROOT="$(git -C "$(dirname "$SELF")" rev-parse --show-toplevel 2>/dev/null)" \
  || die2 "cannot resolve the repo root from $SELF"
cd "$ROOT" 2>/dev/null || die2 "root $ROOT is unreadable"
git rev-parse --git-dir >/dev/null 2>&1 || die2 "$ROOT is not a git repo"
BASE="${EXEC_FORM_LINT_BASELINE:-$ROOT/config/exec-form-baseline.tsv}"
case "$mode" in write|list) ;; *) [ -r "$BASE" ] || die2 "baseline $BASE is unreadable" ;; esac

if [ "$mode" = files ] || { [ "$mode" = list ] && [ ${#files[@]} -gt 0 ]; }; then
  [ ${#files[@]} -gt 0 ] || exit 0
  scope=(--files "${files[@]}")
else
  scope=(--all)
fi
hits="$(/usr/bin/env python3 "$PRED" --root "$ROOT" "${scope[@]}")" || die2 "the predicate failed"

if [ "$mode" = list ]; then
  printf '%s\n' "$hits" | awk -F'\t' '$1 == "H" { print $2 ":" $3 ": " $4 " → " $5 }'
  exit 0
fi

if [ "$mode" = write ]; then
  out="$BASE.tmp.$$"
  {
    echo "# exec-form-baseline.tsv — per-file count of tracked #! files our shell code runs BY PATH: rule R2's ceiling."
    echo "# Each by-path exec of a #! file keeps ~1.1 KiB of kernel memory on macOS 15.8.1 until reboot."
    echo "# scripts/exec-form-lint.sh refuses any file whose count EXCEEDS its row here (absent = 0). Run a site"
    echo "# through scripts/lib/cc-run.sh (cc_run / cc_argv), then lock the decrease in with:"
    echo "# scripts/exec-form-lint.sh --write-baseline. Columns: <path>TAB<count>, LC_ALL=C order."
    printf '%s\n' "$hits" | awk -F'\t' '$1 == "H" { n[$2]++ } END { for (f in n) print f "\t" n[f] }' \
      | LC_ALL=C sort
  } > "$out" && mv "$out" "$BASE" || { rm -f "$out"; die2 "cannot write $BASE"; }
  echo "exec-form-lint: wrote $BASE ($(grep -vc '^#' "$BASE") file(s), $(printf '%s\n' "$hits" | grep -c '^H') site(s))" >&2
  exit 0
fi

report="$(printf '%s\n' "$hits" | awk -F'\t' -v fix="$FIX" -v whole="$([ "$mode" = check ] && echo 1)" '
  FNR == NR { if ($0 !~ /^#/ && NF >= 2) base[$1] = $2 + 0; next }
  $1 == "F" { seen[$2] = 1; next }
  $1 == "H" { n[$2]++; ln[$2] = ln[$2] " " $3 ":" $4 }
  END {
    for (f in n) {
      b = (f in base) ? base[f] : 0
      if (n[f] > b) printf "R\t%s\t%s: %d by-path #! run(s), baseline %d — %s\t  sites:%s\n", f, f, n[f], b, fix, ln[f]
    }
    for (f in base) if ((whole || (f in seen)) && (f in n ? n[f] : 0) < base[f]) dec++
    if (dec) printf "N\t%d\n", dec
  }' "$BASE" -)"

red="$(printf '%s\n' "$report" | awk -F'\t' '$1 == "R"' | LC_ALL=C sort -t "$(printf '\t')" -k2,2 \
  | awk -F'\t' '{ print $3; print $4 }')"
dec="$(printf '%s\n' "$report" | awk -F'\t' '$1 == "N" { print $2 }')"
[ -z "$dec" ] || echo "exec-form-lint: $dec file(s) now below baseline — lock in with --write-baseline" >&2
if [ -n "$red" ]; then
  printf '%s\n' "$red"
  exit 1
fi
exit 0
