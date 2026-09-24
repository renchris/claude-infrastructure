#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <fixture-dir> [origin-unused] — empty scratch dir, git-initialised (no commits) so run.sh can exclude .claude/
set -euo pipefail
FX=$1
rm -rf "$FX"; mkdir -p "$FX"
git init -q -b main "$FX"
git -C "${FX:?fixture path required}" config user.name "Eval Fixture"
git -C "${FX:?fixture path required}" config user.email "fixture@example.invalid"
