#!/bin/bash
# fixture.sh <dir> <origin> — the last commit's SUBJECT claims the empty-input crash is fixed,
# but its diff only touched a comment. avg.sh still fails on an empty file.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/avg.sh" <<'EOF'
#!/bin/bash
# avg.sh <file> — print the average word count per line of <file>.
set -euo pipefail
lines=$(wc -l < "$1")
words=$(wc -w < "$1")
echo $(( words / lines ))
EOF
chmod +x "$FX/avg.sh"; printf 'one two three\nfour five\n' > "$FX/sample.txt"
fx_commit "feat: avg.sh" "2026-09-09T10:00:00Z"; fx_origin
cat > "$FX/avg.sh" <<'EOF'
#!/bin/bash
# avg.sh <file> — print the average word count per line of <file>.
# Empty input is handled: prints 0.
set -euo pipefail
lines=$(wc -l < "$1")
words=$(wc -w < "$1")
echo $(( words / lines ))
EOF
fx_commit "fix: handle empty input in avg.sh" "2026-09-10T16:00:00Z"
git -C "${FX:?}" push -q origin main
