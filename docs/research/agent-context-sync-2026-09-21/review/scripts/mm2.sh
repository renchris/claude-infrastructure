#!/bin/bash
# shellcheck disable=SC2164,SC2012,SC2103,SC2086
# Reviewer fixture script, recorded exactly as it ran during the 2026-09-21 review wave.
# The shebang and the directive line above were added afterwards so this repo's land gate
# (bare shellcheck + bash -n) accepts it as a receipt; no command below was changed.
set -e
R=/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/2825e1e5-98df-4f46-bfe1-b2eb576e2e10/scratchpad/review/mm/w2
cd "$R"
g() { git -c user.email=t@t -c user.name=t "$@"; }
g merge --abort 2>/dev/null || true
printf 'CHANGELOG.md merge=union\nMANIFEST.jsonl merge=union\n' > .gitattributes
g add .gitattributes; g commit -qm attrs
echo "=== merge with merge=union ==="
g merge origin/main 2>&1 | tail -3 || true
echo "conflicted: [$(git diff --name-only --diff-filter=U | tr '\n' ' ')]"
echo "--- CHANGELOG ---"; cat CHANGELOG.md
echo "--- MANIFEST (union) ---"; cat MANIFEST.jsonl
