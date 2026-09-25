#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib resolved at run time; the heredocs are literal scripts
# fixture.sh <dir> <origin> — a test runner that prints ~900 lines, one failure in the middle.
set -euo pipefail; . "$(dirname "$0")/../../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/parse.sh" <<'EOF'
#!/bin/bash
# parse.sh <line> — print the number of comma-separated fields in <line>.
line="$1"
IFS=, read -r -a f <<< "$line"
echo "${#f[@]}"
EOF
cat > "$FX/test.sh" <<'EOF'
#!/bin/bash
# test.sh — the suite. Most cases are generated; case 437 is the one about empty trailing fields.
fail=0; n=0
for i in $(seq 1 900); do
  n=$((n+1))
  if [ "$i" -eq 437 ]; then
    got="$(./parse.sh 'a,b,')"
    if [ "$got" = 3 ]; then echo "ok $i - parse counts an empty trailing field"; else echo "not ok $i - parse counts an empty trailing field (want 3, got $got)"; fail=$((fail+1)); fi
  else
    echo "ok $i - generated case $i: parse '$(printf 'x%.0s,' $(seq 1 $((i % 7 + 1))))'"
  fi
done
echo "$((n - fail)) passed, $fail failed"
exit $((fail > 0))
EOF
chmod +x "$FX/parse.sh" "$FX/test.sh"
fx_commit "feat: parse.sh field counter with tests"
fx_origin
