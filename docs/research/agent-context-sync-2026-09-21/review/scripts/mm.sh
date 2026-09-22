#!/bin/bash
# shellcheck disable=SC2164,SC2012,SC2103,SC2086
# Reviewer fixture script, recorded exactly as it ran during the 2026-09-21 review wave.
# The shebang and the directive line above were added afterwards so this repo's land gate
# (bare shellcheck + bash -n) accepts it as a receipt; no command below was changed.
set -e
R=/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/2825e1e5-98df-4f46-bfe1-b2eb576e2e10/scratchpad/review/mm
rm -rf "$R"; mkdir -p "$R"; cd "$R"
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }
g init -q --bare origin.git; g init -q base
cd base
printf '# CHANGELOG\n' > CHANGELOG.md
printf '{"id":"A","h":"1"}\n{"id":"B","h":"1"}\n' > MANIFEST.jsonl
g add -A; g commit -qm init; git remote add origin ../origin.git; git push -q origin main
cd ..; git clone -q origin.git w1; git clone -q origin.git w2
cd w1; printf '\n## sync 10:00Z mac-1\nM mirror/a.md\n' >> CHANGELOG.md
printf '{"id":"A","h":"2"}\n{"id":"B","h":"1"}\n' > MANIFEST.jsonl
g commit -qam s1; git push -q origin main
cd ../w2; printf '\n## sync 10:01Z mac-2\nM mirror/b.md\n' >> CHANGELOG.md
printf '{"id":"A","h":"1"}\n{"id":"B","h":"2"}\n' > MANIFEST.jsonl
g commit -qam s2
git fetch -q origin
echo "=== plain merge ==="
g merge origin/main 2>&1 | tail -3 || true
echo "conflicted: [$(git diff --name-only --diff-filter=U | tr '\n' ' ')]"
g merge --abort 2>/dev/null || true
echo "=== with merge=union on both ==="
printf 'CHANGELOG.md merge=union\nMANIFEST.jsonl merge=union\n' > .gitattributes
g commit -qam attrs
g merge origin/main 2>&1 | tail -2 || true
echo "conflicted: [$(git diff --name-only --diff-filter=U | tr '\n' ' ')]"
echo "--- MANIFEST after union merge ---"; cat MANIFEST.jsonl
