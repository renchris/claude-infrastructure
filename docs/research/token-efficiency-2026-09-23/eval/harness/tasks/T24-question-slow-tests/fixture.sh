#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — held-out (2026-10-04). ./test.sh takes ~9 s because every test calls
# start_server in tests/helpers.sh, which sleeps a fixed 3 s "waiting for the server" (two tests, three start_server calls, x 3 s).
# A large unused fixture file is a decoy. The ask is a why-question: answer it.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
mkdir -p "$FX/tests/data"
cat > "$FX/server.sh" <<'EOF'
#!/bin/bash
# server.sh <port-file> — a stand-in server: writes "ready" to <port-file> at once.
echo ready > "$1"
EOF
cat > "$FX/tests/helpers.sh" <<'EOF'
# helpers.sh — sourced by test.sh.
start_server() {
  ./server.sh "$TMP/ready"
  # wait for the server to come up (TODO: poll $TMP/ready instead of a fixed wait)
  sleep 3
}
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — run the tests; exits non-zero on the first failure.
set -u; fail=0
TMP=$(mktemp -d); export TMP
. tests/helpers.sh
t_ready()   { start_server; grep -q ready "$TMP/ready"; }
t_restart() { start_server; start_server; [ -f "$TMP/ready" ]; }
for t in t_ready t_restart; do "$t" && echo "ok $t" || { echo "FAIL $t"; fail=1; }; done
rm -f "$TMP/ready"; rmdir "$TMP"
[ $fail -eq 0 ] && echo "all tests passed"; exit $fail
EOF
chmod +x "$FX/server.sh" "$FX/test.sh"
awk 'BEGIN { for (i = 0; i < 20000; i++) printf "row %d,%d,%d\n", i, i * 7, i % 13 }' > "$FX/tests/data/legacy-dump.csv"
printf '# srv\n\nRun `./test.sh` for the tests.\n' > "$FX/README.md"
fx_commit "test: server tests" "2026-09-14T10:00:00Z"; fx_origin
