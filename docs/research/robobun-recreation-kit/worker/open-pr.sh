#!/usr/bin/env bash
# PR mechanics. The body is prose(model) + evidence(harness) -- never model-written evidence.
set -euo pipefail
git push -u origin "$BRANCH"
BODY=$(mktemp)
{ [ -n "${SOURCE_REF:-}" ] && printf 'Fixes %s\n\n' "$SOURCE_REF"
  cat .gate/prose.md        # model: What / Repro / Cause / Fix / Verification
  cat .gate/evidence.md     # harness: gate block or structured abstention
} > "$BODY"
gh pr create --repo "$REPO" --head "$BRANCH" --base main \
  --title "$TITLE" --body-file "$BODY" --assignee "$HUMAN_REVIEWER"
