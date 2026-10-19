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
# Usage: hook-shebang-lint.sh [--file F]... · --selftest · --print-scope
# Exit: 0 clean · 1 findings · 2 no verdict (unreadable file, missing predicate)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRED="${HOOK_SHEBANG_LINT_PRED:-$ROOT/scripts/hook-interp.py}"
DEFAULT_FILES=("settings-templates/settings.example.json" "settings-templates/kimi-settings.example.json")

[ -f "$PRED" ] || { echo "hook-shebang-lint: predicate missing at $PRED — no verdict" >&2; exit 2; }

case "${1:-}" in
  --selftest)
    /usr/bin/env python3 "$PRED" --selftest || exit 1
    # The wrapper's own discrimination: a bare fixture must go RED and its rewrite must come back clean.
    d="$(mktemp -d "${TMPDIR:-/tmp}/hook-shebang-lint.XXXXXX")" || exit 2
    trap 'rm -f "$d"/hooks/x.sh "$d"/s.json "$d"/s2.json; rmdir "$d"/hooks "$d" 2>/dev/null' EXIT
    mkdir -p "$d/hooks" && printf '#!/bin/bash\n' > "$d/hooks/x.sh"
    printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"~/.claude/hooks/x.sh"}]}]}}\n' > "$d/s.json"
    if /usr/bin/env python3 "$PRED" lint "$d/s.json" --root "$d" --hermetic >/dev/null; then
      echo "hook-shebang-lint selftest: FAIL — a bare #! fixture read clean" >&2; exit 1
    fi
    /usr/bin/env python3 "$PRED" rewrite "$d/s.json" --root "$d" --hermetic > "$d/s2.json" 2>/dev/null || exit 1
    /usr/bin/env python3 "$PRED" lint "$d/s2.json" --root "$d" --hermetic >/dev/null || {
      echo "hook-shebang-lint selftest: FAIL — the rewritten fixture still reads RED" >&2; exit 1; }
    echo "hook-shebang-lint selftest: ok"
    exit 0 ;;
  --print-scope) printf '%s\n' "${DEFAULT_FILES[@]}"; exit 0 ;;
esac

files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --file) [ $# -ge 2 ] || { echo "hook-shebang-lint: --file needs a path" >&2; exit 2; }; files+=("$2"); shift 2 ;;
    *) echo "hook-shebang-lint: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ ${#files[@]} -gt 0 ] || { for f in "${DEFAULT_FILES[@]}"; do files+=("$ROOT/$f"); done; }

rc=0
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "hook-shebang-lint: $f is absent — no verdict" >&2; rc=2; continue; }
  /usr/bin/env python3 "$PRED" lint "$f" --root "$ROOT" --hermetic
  r=$?
  if [ "$r" -eq 2 ]; then rc=2; elif [ "$r" -ne 0 ] && [ "$rc" -eq 0 ]; then rc=1; fi
done
exit "$rc"
