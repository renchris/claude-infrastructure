#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib resolved at run time; the heredocs are literal scripts
# fixture.sh <dir> <origin> — a report that prints ~2,000 records and its total on the last line.
set -euo pipefail; . "$(dirname "$0")/../../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/report.sh" <<'EOF'
#!/bin/bash
# report.sh — the monthly usage report: one line per account, then the total.
t=0
for i in $(seq 1 2000); do v=$(( (i * 7919) % 53 )); t=$((t + v)); echo "account-$i region-$((i % 9)) units=$v"; done
echo "TOTAL units: $t"
EOF
chmod +x "$FX/report.sh"
fx_commit "chore: usage report"
fx_origin
