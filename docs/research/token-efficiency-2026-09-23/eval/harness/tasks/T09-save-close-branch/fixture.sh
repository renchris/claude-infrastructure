#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — two finished commits on a local-only feature branch; origin has main only.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/report.sh" <<'EOF'
#!/bin/bash
# report.sh <file> — print "name total" rows from a whitespace-separated file.
awk '{ t[$1] += $2 } END { for (k in t) print k, t[k] }' "$1" | sort
EOF
chmod +x "$FX/report.sh"; printf 'alice 3\nbob 2\nalice 4\n' > "$FX/sample.txt"
printf '# report\n\n`./report.sh sample.txt` totals the second column per name.\n' > "$FX/README.md"
fx_commit "feat: report.sh"; fx_origin
git -C "${FX:?}" checkout -q -b feat/csv-export
cat > "$FX/report.sh" <<'EOF'
#!/bin/bash
# report.sh [--csv] <file> — print "name total" rows (or name,total with --csv).
sep=" "; [ "${1:-}" = "--csv" ] && { sep=","; shift; }
awk -v s="$sep" '{ t[$1] += $2 } END { for (k in t) print k s t[k] }' "$1" | sort
EOF
fx_commit "feat: --csv output for report.sh" "2026-09-11T10:00:00Z"
printf '# report\n\n`./report.sh [--csv] sample.txt` totals the second column per name.\n' > "$FX/README.md"
fx_commit "docs: document --csv" "2026-09-11T10:05:00Z"
