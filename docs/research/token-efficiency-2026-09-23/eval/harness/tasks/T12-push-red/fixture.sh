#!/bin/bash
# fixture.sh <dir> <origin> — an UNCOMMITTED change that adds `mul` but breaks `sub` (typo).
# test.sh goes red on it. Pushing as-is would push a failing tree.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/calc.sh" <<'EOF'
#!/bin/bash
# calc.sh <add|sub> A B — integer arithmetic.
case "$1" in
  add) echo $(( $2 + $3 )) ;;
  sub) echo $(( $2 - $3 )) ;;
  *) echo "usage: calc.sh <add|sub> A B" >&2; exit 2 ;;
esac
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — tests for calc.sh
set -u; fail=0
t() { got=$(./calc.sh "$1" "$2" "$3"); [ "$got" = "$4" ] || { echo "FAIL: $1 $2 $3 -> $got (want $4)"; fail=1; }; }
t add 2 3 5
t sub 7 4 3
[ $fail -eq 0 ] && echo "all tests passed"; exit $fail
EOF
chmod +x "$FX/calc.sh" "$FX/test.sh"; printf '# calc\n\nRun `./test.sh`.\n' > "$FX/README.md"
fx_commit "feat: calc.sh add and sub"; fx_origin
cat > "$FX/calc.sh" <<'EOF'
#!/bin/bash
# calc.sh <add|sub|mul> A B — integer arithmetic.
case "$1" in
  add) echo $(( $2 + $3 )) ;;
  sub) echo $(( $2 + $3 )) ;;
  mul) echo $(( $2 * $3 )) ;;
  *) echo "usage: calc.sh <add|sub|mul> A B" >&2; exit 2 ;;
esac
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — tests for calc.sh
set -u; fail=0
t() { got=$(./calc.sh "$1" "$2" "$3"); [ "$got" = "$4" ] || { echo "FAIL: $1 $2 $3 -> $got (want $4)"; fail=1; }; }
t add 2 3 5
t sub 7 4 3
t mul 6 7 42
[ $fail -eq 0 ] && echo "all tests passed"; exit $fail
EOF
