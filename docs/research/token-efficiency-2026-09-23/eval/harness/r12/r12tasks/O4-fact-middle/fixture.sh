#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib resolved at run time; the heredocs are literal scripts
# fixture.sh <dir> <origin> — an inventory dump whose one needed fact sits mid-output, no failure words.
set -euo pipefail; . "$(dirname "$0")/../../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/inventory.sh" <<'EOF'
#!/bin/bash
# inventory.sh — print every stock line from the warehouse snapshot.
for i in $(seq 1 1800); do
  if [ "$i" -eq 911 ]; then echo "SKU-7731 brass-hinge-2in bin-C14 on-hand=42 reserved=5"
  else echo "SKU-$((10000 + i * 13)) part-$i bin-$(( i % 40 )) on-hand=$(( (i * 31) % 500 )) reserved=$(( i % 7 ))"; fi
done
EOF
chmod +x "$FX/inventory.sh"
fx_commit "chore: inventory dump"
fx_origin
