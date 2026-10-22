#!/bin/bash
# hook-shebang-lint.sh — refuse a hook command or statusLine that executes a `#!` script by bare path.
#
# On macOS 15.7.9 each execve() of a `#!` script retains one 1 KiB data.kalloc.1024 element; the zone
# hit its ~20 GiB ceiling and panicked the kernel on 2026-10-18 with ~100 hook commands running as
# bare `#!` paths (docs/research/panic-2026-10-18-zone-map-shebang-leak.md). The template is what
# install.sh seeds and what every settings migration is written against, so a bare entry here becomes
# a leaking entry in every config dir. Judged hermetically against THIS checkout (--root .), never the
# live layer, so the verdict is the tree's own. The predicate is scripts/hook-interp.py's; this file
# only names the population and runs the selftest.
#
# The launchd jobs are the same leak on a timer (docs/research/kalloc-longterm-2026-10-21/REPORT.md
# §3 Phase 1): launchd/*.plist and launchd/staged/*.plist are in the default scope, and a --file
# ending .plist is judged by `hook-interp.py lint-plist` — a ProgramArguments[0], or a shell `-c`
# command word, that is a `#!` script in this checkout must carry its interpreter in front.
#
# Usage: hook-shebang-lint.sh [--file F]... · --selftest · --print-scope
# Exit: 0 clean · 1 findings · 2 no verdict (unreadable file, missing predicate)
set -uo pipefail

_p="${BASH_SOURCE[0]}"   # resolve the ~/.claude/scripts symlink first, or `..` is ~/.claude
while [ -L "$_p" ]; do _d="$(cd "$(dirname "$_p")" && pwd)"; _p="$(readlink "$_p")"
  case "$_p" in /*) ;; *) _p="$_d/$_p" ;; esac; done
ROOT="$(cd "$(dirname "$_p")/.." && pwd)"
PRED="${HOOK_SHEBANG_LINT_PRED:-$ROOT/scripts/hook-interp.py}"
DEFAULT_FILES=("settings-templates/settings.example.json" "settings-templates/kimi-settings.example.json")
# The launchd jobs, relative to ROOT. A glob, not a list: a new job is in scope the moment it exists.
default_plists() {
  local f
  for f in "$ROOT"/launchd/*.plist "$ROOT"/launchd/staged/*.plist; do
    [ -f "$f" ] && printf '%s\n' "${f#"$ROOT"/}"
  done
}

[ -f "$PRED" ] || { echo "hook-shebang-lint: predicate missing at $PRED — no verdict" >&2; exit 2; }

case "${1:-}" in
  --selftest)
    /usr/bin/env python3 "$PRED" --selftest || exit 1
    # The wrapper's own discrimination: a bare fixture must go RED and its rewrite must come back clean.
    d="$(mktemp -d "${TMPDIR:-/tmp}/hook-shebang-lint.XXXXXX")" || exit 2
    trap 'rm -f "$d"/hooks/x.sh "$d"/s.json "$d"/s2.json "$d"/bare.plist "$d"/arg0.plist "$d"/fixed.plist
          rmdir "$d"/hooks "$d" 2>/dev/null' EXIT
    mkdir -p "$d/hooks" && printf '#!/bin/bash\n' > "$d/hooks/x.sh"
    printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/.claude/hooks/x.sh"}]}]}}\n' > "$d/s.json"
    if /usr/bin/env python3 "$PRED" lint "$d/s.json" --root "$d" --hermetic >/dev/null; then
      echo "hook-shebang-lint selftest: FAIL — a bare #! fixture read clean" >&2; exit 1
    fi
    /usr/bin/env python3 "$PRED" rewrite "$d/s.json" --root "$d" --hermetic > "$d/s2.json" 2>/dev/null || exit 1
    /usr/bin/env python3 "$PRED" lint "$d/s2.json" --root "$d" --hermetic >/dev/null || {
      echo "hook-shebang-lint selftest: FAIL — the rewritten fixture still reads RED" >&2; exit 1; }
    # The plist arm: a `-c` exec and a ProgramArguments[0] by path go RED; the interpreter-led form,
    # XML-escaped exactly as a real job is, comes back clean.
    pl() { printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>Label</key><string>t</string><key>ProgramArguments</key><array>%s</array></dict></plist>\n' "$1"; }
    # shellcheck disable=SC2016  # $HOME is the plist's own text; launchd's shell expands it, not this one
    pl '<string>/bin/bash</string><string>-c</string><string>exec "$HOME/.claude/hooks/x.sh" 2&gt;&amp;1</string>' > "$d/bare.plist"
    pl '<string>/Users/u/.claude/hooks/x.sh</string><string>--run</string>' > "$d/arg0.plist"
    # shellcheck disable=SC2016
    pl '<string>/bin/bash</string><string>-c</string><string>exec /bin/bash "$HOME/.claude/hooks/x.sh" 2&gt;&amp;1</string>' > "$d/fixed.plist"
    for f in bare arg0; do
      if /usr/bin/env python3 "$PRED" lint-plist "$d/$f.plist" --root "$d" >/dev/null; then
        echo "hook-shebang-lint selftest: FAIL — the by-path $f.plist fixture read clean" >&2; exit 1
      fi
    done
    /usr/bin/env python3 "$PRED" lint-plist "$d/fixed.plist" --root "$d" >/dev/null || {
      echo "hook-shebang-lint selftest: FAIL — the interpreter-led plist fixture reads RED" >&2; exit 1; }
    echo "hook-shebang-lint selftest: ok"
    exit 0 ;;
  --print-scope) printf '%s\n' "${DEFAULT_FILES[@]}"; default_plists; exit 0 ;;
esac

files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || { echo "hook-shebang-lint: --file needs a path" >&2; exit 2; }; files+=("$2"); shift 2 ;;
    *) echo "hook-shebang-lint: unknown argument $1" >&2; exit 2 ;;
  esac
done
if [ ${#files[@]} -eq 0 ]; then
  for f in "${DEFAULT_FILES[@]}"; do files+=("$ROOT/$f"); done
  while IFS= read -r f; do files+=("$ROOT/$f"); done < <(default_plists)
fi

rc=0
plists=()
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "hook-shebang-lint: $f is absent — no verdict" >&2; rc=2; continue; }
  case "$f" in *.plist) plists+=("$f"); continue ;; esac
  /usr/bin/env python3 "$PRED" lint "$f" --root "$ROOT" --hermetic
  r=$?
  if [ "$r" -eq 2 ]; then rc=2; elif [ "$r" -ne 0 ] && [ "$rc" -eq 0 ]; then rc=1; fi
done
if [ ${#plists[@]} -gt 0 ]; then
  /usr/bin/env python3 "$PRED" lint-plist "${plists[@]}" --root "$ROOT"
  r=$?
  if [ "$r" -eq 2 ]; then rc=2; elif [ "$r" -ne 0 ] && [ "$rc" -eq 0 ]; then rc=1; fi
fi
exit "$rc"
