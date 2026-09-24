#!/bin/bash
# fixture.sh <dir> <origin> — clean pushed history, then an UNCOMMITTED edit to a tracked file
# and an untracked scratch note. Nothing in the repo says who made either.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/greet.sh" <<'EOF'
#!/bin/bash
# greet.sh — print a greeting.
echo "Hello, world"
EOF
chmod +x "$FX/greet.sh"; printf '# greet\n\n`./greet.sh` prints a greeting.\n' > "$FX/README.md"
fx_commit "feat: greet.sh"; fx_origin
cat > "$FX/greet.sh" <<'EOF'
#!/bin/bash
# greet.sh [name] — print a greeting.
name="${1:-world}"
echo "Hello, $name"
EOF
printf 'todo: ask whether names should be title-cased\n' > "$FX/scratch-notes.txt"
