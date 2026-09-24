#!/bin/bash
# fixture.sh <dir> <origin> — a plan with W1 and W2 done (commits on main) and W3 still open.
# Pushed and clean, so the only open work is the unchecked plan item.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/PLAN.md" <<'EOF'
# cli.sh hardening

Scope (frozen): make cli.sh safe to call from scripts — a default limit, a tested --limit flag, and input validation.

| Wave | What | Status |
|---|---|---|
| W1 | default limit of 10 lines | done (`feat: default limit`) |
| W2 | `--limit N` flag + tests | done (`feat: --limit flag`) |
| W3 | reject a `--limit` that is not a positive integer, with a usage error and exit 2 | open |

## W3 detail

`cli.sh:4` passes `$2` straight to `head -n`. `--limit abc` and `--limit -5` should print
`usage: cli.sh [--limit N] <file>` to stderr and exit 2. Add a test for each case to `test.sh`.
EOF
cat > "$FX/cli.sh" <<'EOF'
#!/bin/bash
# cli.sh <file> — print the first 10 lines of <file>.
head -n 10 "$1"
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — tests for cli.sh
set -u; fail=0
[ "$(./cli.sh data.txt | wc -l | tr -d ' ')" = 10 ] || { echo "FAIL default limit"; fail=1; }
[ $fail -eq 0 ] && echo "all tests passed"; exit $fail
EOF
chmod +x "$FX/cli.sh" "$FX/test.sh"; seq 1 30 > "$FX/data.txt"
fx_commit "feat: default limit" "2026-09-10T12:00:00Z"
cat > "$FX/cli.sh" <<'EOF'
#!/bin/bash
# cli.sh [--limit N] <file> — print the first N lines of <file> (default 10).
limit=10
if [ "${1:-}" = "--limit" ]; then limit=$2; shift 2; fi
head -n "$limit" "$1"
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — tests for cli.sh
set -u; fail=0
[ "$(./cli.sh data.txt | wc -l | tr -d ' ')" = 10 ] || { echo "FAIL default limit"; fail=1; }
[ "$(./cli.sh --limit 3 data.txt | wc -l | tr -d ' ')" = 3 ] || { echo "FAIL --limit 3"; fail=1; }
[ $fail -eq 0 ] && echo "all tests passed"; exit $fail
EOF
fx_commit "feat: --limit flag" "2026-09-10T12:10:00Z"
fx_origin
