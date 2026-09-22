#!/bin/bash
# shellcheck disable=SC2164,SC2012,SC2103,SC2086
# Reviewer fixture script, recorded exactly as it ran during the 2026-09-21 review wave.
# The shebang and the directive line above were added afterwards so this repo's land gate
# (bare shellcheck + bash -n) accepts it as a receipt; no command below was changed.
R=/private/tmp/claude-501/-Users-chrisren-Development-claude-infrastructure/2825e1e5-98df-4f46-bfe1-b2eb576e2e10/scratchpad/review/dep
rm -rf "$R"; mkdir -p "$R/repo/docs/topics/clients/acme" "$R/repo/docs/mirror/sharepoint/acme/finance"
cd "$R/repo"
printf -- '---\nrendered_sha256: 3ab77e11\n---\nbody\n' > docs/mirror/sharepoint/acme/finance/q3.md
printf 'page\tsource\tpinned_sha\trole\n' > docs/DEPENDS.tsv
# column 2 exactly as the doc's frontmatter writes it (page-relative)
printf 'topics/clients/acme/acme-pricing.md\t../../mirror/sharepoint/acme/finance/q3.md\t3ab77e11\tprimary\n' >> docs/DEPENDS.tsv
echo "=== the document's verbatim refresh-queue loop, run from the repo root ==="
awk -F'\t' 'NR>1' docs/DEPENDS.tsv | while IFS= read -r row; do
  p=$(printf '%s' "$row" | awk -F'\t' '{print $1}'); s=$(printf '%s' "$row" | awk -F'\t' '{print $2}')
  sha=$(printf '%s' "$row" | awk -F'\t' '{print $3}')
  cur=$(sed -n 's/^rendered_sha256: //p' "docs/$s" 2>/dev/null | head -1)
  [ -z "$cur" ] && { echo "TOMBSTONE-OR-MISSING	$p	$s"; continue; }
  case "$cur" in "$sha"*) ;; *) echo "STALE	$p	$s" ;; esac
done | sort -u
echo "=== path it actually opened ==="
echo "docs/../../mirror/sharepoint/acme/finance/q3.md -> $(cd /; ls "$R/repo/docs/../../mirror/sharepoint/acme/finance/q3.md" 2>&1 | head -1)"
