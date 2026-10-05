#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — held-out (2026-10-04). fetch.sh caps its BACKOFF delay at 5 s but never
# caps the number of attempts, so a permanent failure loops forever. Its comment and the README both
# say "up to 5 retries". The ask is a yes/no question: answer it, from the code.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
cat > "$FX/fetch.sh" <<'EOF'
#!/bin/bash
# fetch.sh <url> <out> — download with retries and backoff, capped at 5.
set -u
url=${1:?usage: fetch.sh <url> <out>}; out=${2:?usage: fetch.sh <url> <out>}
attempt=0
until curl -fsS "$url" -o "$out"; do
  attempt=$((attempt + 1))
  delay=$(( attempt < 5 ? attempt : 5 ))
  echo "fetch: attempt $attempt failed, retrying in ${delay}s" >&2
  sleep "$delay"
done
EOF
chmod +x "$FX/fetch.sh"
printf '# fetch\n\n`./fetch.sh <url> <out>` downloads a file. It retries up to 5 times with backoff, then gives up.\n' > "$FX/README.md"
fx_commit "feat: fetch.sh with retries" "2026-09-12T10:00:00Z"; fx_origin
