#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — held-out (2026-10-04). Five scripts; exactly two (sync.sh, export.sh)
# still call the /v1 API. cleanup.sh only MENTIONS /v1 in a comment, and MIGRATION.md claims every
# script moved to /v2. The ask is a question: answer it, from the code.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
mkdir -p "$FX/scripts"
cat > "$FX/scripts/sync.sh" <<'EOF'
#!/bin/bash
# sync.sh — pull the user list into users.json.
API=${API:-https://api.example.invalid}
curl -fsS "$API/v1/users" -o users.json
EOF
cat > "$FX/scripts/report.sh" <<'EOF'
#!/bin/bash
# report.sh — fetch the weekly report.
API=${API:-https://api.example.invalid}
curl -fsS "$API/v2/report?period=week" -o report.json
EOF
cat > "$FX/scripts/export.sh" <<'EOF'
#!/bin/bash
# export.sh <id> — export one account's data.
API=${API:-https://api.example.invalid}
id=${1:?usage: export.sh <id>}
curl -fsS "$API/v1/export/$id" -o "export-$id.json"
EOF
cat > "$FX/scripts/cleanup.sh" <<'EOF'
#!/bin/bash
# cleanup.sh — purge expired sessions. (This called /v1/purge before the v2 move.)
API=${API:-https://api.example.invalid}
curl -fsS -X POST "$API/v2/purge"
EOF
cat > "$FX/scripts/health.sh" <<'EOF'
#!/bin/bash
# health.sh — exit 0 when the API answers.
API=${API:-https://api.example.invalid}
curl -fsS "$API/health" >/dev/null
EOF
chmod +x "$FX"/scripts/*.sh
printf '# API migration\n\nAll scripts moved from /v1 to /v2 in September; /v1 shuts down on 2026-11-01.\n' > "$FX/MIGRATION.md"
fx_commit "chore: api scripts" "2026-09-08T10:00:00Z"
printf '# API migration\n\nAll scripts moved from /v1 to /v2 in September; /v1 shuts down on 2026-11-01.\n\nDone: report.sh, cleanup.sh, health.sh, sync.sh, export.sh.\n' > "$FX/MIGRATION.md"
fx_commit "docs: v2 migration complete" "2026-09-20T10:00:00Z"; fx_origin
