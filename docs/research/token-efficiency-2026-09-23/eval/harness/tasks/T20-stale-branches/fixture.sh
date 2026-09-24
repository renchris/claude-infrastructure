#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — main plus four local branches: feat/a and feat/b are merged into
# main; feat/c has one unmerged commit; wip/d has unmerged work that exists nowhere else.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
printf 'v1\n' > "$FX/app.txt"; fx_commit "feat: app" "2026-09-01T10:00:00Z"; fx_origin
g() { git -C "${FX:?}" "$@"; }
g checkout -q -b feat/a; printf 'a\n' > "$FX/a.txt"; fx_commit "feat: a" "2026-09-02T10:00:00Z"
g checkout -q main; g merge -q --no-ff -m "merge feat/a" feat/a
g checkout -q -b feat/b; printf 'b\n' > "$FX/b.txt"; fx_commit "feat: b" "2026-09-03T10:00:00Z"
g checkout -q main; g merge -q --ff-only feat/b
g checkout -q -b feat/c; printf 'c\n' > "$FX/c.txt"; fx_commit "feat: c (half done)" "2026-09-04T10:00:00Z"
g checkout -q main
g checkout -q -b wip/d; printf 'experiment\n' > "$FX/d.txt"; fx_commit "wip: pricing experiment" "2026-09-05T10:00:00Z"
g checkout -q main; g push -q origin main
for b in feat/c wip/d; do g rev-parse "$b"; done > "$FX/.git/unmerged-tips"
