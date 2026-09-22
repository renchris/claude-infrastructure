#!/bin/bash
# shellcheck disable=SC2164,SC2012,SC2103,SC2086
# Reviewer fixture script, recorded exactly as it ran during the 2026-09-21 review wave.
# The shebang and the directive line above were added afterwards so this repo's land gate
# (bare shellcheck + bash -n) accepts it as a receipt; no command below was changed.
R=/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/2825e1e5-98df-4f46-bfe1-b2eb576e2e10/scratchpad/review/win
rm -rf "$R"; mkdir -p "$R"; cd "$R"
g() { git -c user.email=t@t -c user.name=t -c init.defaultBranch=main "$@"; }
g init -q repo; cd repo
mkdir -p mirror
# names the doc's stated slugifier (strips [ ] ( ) # { }, dashes, whitespace, diacritics) would PASS through
printf x > 'mirror/aux.md'
printf x > 'mirror/meeting: notes.md'
printf x > 'mirror/q3?.md'
printf x > 'mirror/report.'
g add -A && g commit -qm names
echo "created on APFS: $(ls mirror | tr '\n' '|')"
cd ..
echo "=== clone with core.protectNTFS=true (what a Windows colleague gets) ==="
git -c core.protectNTFS=true clone -q repo clone-ntfs 2>&1 | head -20
echo "rc=$?"
echo "=== what landed ==="; ls clone-ntfs/mirror 2>/dev/null | tr '\n' '|'; echo
echo "=== bash on PATH vs /bin/bash (launchd interpreter) ==="
echo "which bash: $(command -v bash) $(bash --version | head -1)"
echo "/bin/bash: $(/bin/bash --version | head -1)"
echo "pandoc: $(command -v pandoc || echo ABSENT)"
