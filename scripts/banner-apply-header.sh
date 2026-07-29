#!/usr/bin/env bash
# banner-apply-header.sh — put the chosen hero banner at the top of the README.
#
# Staged, not applied: the landing gate for this track is the operator seeing the comparison
# first (docs/plans/README_HERO_BANNER.md § Landing gate). Run this once that has happened.
#
#   scripts/banner-apply-header.sh          # prototype A, the recommended vector banner
#   scripts/banner-apply-header.sh b        # the fine-grid ASCII banner
#   scripts/banner-apply-header.sh b2       # the coarse-grid ASCII banner
#   scripts/banner-apply-header.sh a --dry-run
#
# `d6845630` deleted 426 lines of this README because an open-ended regex bounded a replacement
# and matched to the last `</sub>` in the file. So: anchor on exact strings, and assert the SHAPE
# of the result — line count, heading count — not merely that the addition is present.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

CHOICE="${1:-a}"; DRY=0
[[ "${2:-}" == "--dry-run" || "${1:-}" == "--dry-run" ]] && DRY=1
[[ "${1:-}" == "--dry-run" ]] && CHOICE="a"

case "$CHOICE" in
  a)  SRC="assets/banner/proto-a-vector.svg" ;;
  b)  SRC="assets/banner/proto-b-ascii.svg" ;;
  b2) SRC="assets/banner/proto-b2-ascii-coarse.svg" ;;
  *)  echo "banner-apply-header: choice must be a, b or b2 (got '$CHOICE')" >&2; exit 2 ;;
esac
DST="assets/banner/hero.svg"

[[ -f "$SRC" ]] || { echo "banner-apply-header: missing $SRC" >&2; exit 1; }
[[ -f README.md ]] || { echo "banner-apply-header: no README.md here" >&2; exit 1; }

ALT="The claude-infrastructure mark: a single Claude starburst on a hairline rail divides into two, \
the pair exchange one message each way along the rail, and the originator retires — leaving one \
mark at rest above the words claude-infrastructure and sessions run each other."

BLOCK="<img src=\"$DST\" width=\"900\" alt=\"$ALT\">"

# The anchor is the first three lines of the file, matched exactly and required to be unique.
ANCHOR=$'<div align="center">\n\n# Claude Code Infrastructure'

python3 - "$BLOCK" "$ANCHOR" "$DRY" <<'PY'
import pathlib, sys

block, anchor, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
p = pathlib.Path("README.md")
before = p.read_text()

if block.split('alt=')[0] in before:
    sys.exit("banner-apply-header: a hero banner is already in the README — nothing to do")

n = before.count(anchor)
if n != 1:
    sys.exit(f"banner-apply-header: anchor found {n} times, expected exactly 1 — refusing to edit")
if not before.startswith(anchor):
    sys.exit("banner-apply-header: anchor is not at the top of the file — refusing to edit")

lines_before = before.count("\n")
heads_before = sum(1 for l in before.splitlines() if l.startswith("#"))

after = before.replace(anchor, f'<div align="center">\n\n{block}\n\n# Claude Code Infrastructure', 1)

# assert the SHAPE, not just that the addition is present
lines_after = after.count("\n")
heads_after = sum(1 for l in after.splitlines() if l.startswith("#"))
problems = []
if lines_after != lines_before + 2:
    problems.append(f"line count {lines_before} -> {lines_after}, expected +2")
if heads_after != heads_before:
    problems.append(f"heading count {heads_before} -> {heads_after}, expected unchanged")
if len(after) != len(before) + len(block) + 2:
    problems.append("byte delta is not exactly the inserted block")
if problems:
    sys.exit("banner-apply-header: REFUSED — " + "; ".join(problems))

print(f"  README.md  {lines_before} -> {lines_after} lines, {heads_after} headings (unchanged)")
if dry:
    print("  --dry-run: not written")
else:
    p.write_text(after)
    print("  README.md written")
PY

if [[ "$DRY" -eq 1 ]]; then
  echo "  --dry-run: $SRC would become $DST"
  exit 0
fi

git mv "$SRC" "$DST"
echo "  $SRC -> $DST"
echo
echo "Review it, then commit:"
echo "  git add README.md $DST && git commit -m 'feat(readme): animated Claude-mascot hero banner'"
