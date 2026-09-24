#!/bin/bash
# fixture.sh <dir> <origin> — a hello script with a test; the ask is a small configurable greeting.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/hello.sh" <<'EOF'
#!/bin/bash
# hello.sh [name] — greet someone.
echo "Hello, ${1:-friend}!"
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — tests for hello.sh
set -u; fail=0
[ "$(./hello.sh)" = "Hello, friend!" ] || { echo "FAIL default"; fail=1; }
[ "$(./hello.sh Sam)" = "Hello, Sam!" ] || { echo "FAIL name"; fail=1; }
[ $fail -eq 0 ] && echo "all tests passed"; exit $fail
EOF
chmod +x "$FX/hello.sh" "$FX/test.sh"
printf '# hello\n\n`./hello.sh [name]` greets someone. Tests: `./test.sh`.\n' > "$FX/README.md"
fx_commit "feat: hello.sh"; fx_origin
