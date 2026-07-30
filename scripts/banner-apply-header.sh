#!/usr/bin/env bash
# banner-apply-header.sh — put the chosen hero banner at the top of the README.
#
#   scripts/banner-apply-header.sh                    # the operator's pick
#   scripts/banner-apply-header.sh --dry-run
#   scripts/banner-apply-header.sh v6a-long-night     # any other built variant
#
# WHAT THIS USED TO OFFER, AND WHY THAT WAS A TRAP. Its three choices were `a`, `b` and `b2` —
# proto-a-vector.svg, proto-b-ascii.svg, proto-b2-ascii-coarse.svg — and the operator REJECTED all
# three on 2026-07-29, on four grounds recorded in docs/plans/README_HERO_BANNER.md § Landing gate.
# Its hard-coded ALT text still described that dead concept ("a single Claude starburst … divides
# into two"), so the one command this track pointed at for landing could only have landed the thing
# the track exists to have replaced, and would have described it wrongly on the way. A remedy rots
# independently of the symptom it was written for.
#
# `d6845630` deleted 426 lines of this README because an open-ended regex bounded a replacement and
# matched to the last `</sub>` in the file. So: anchor on exact strings, and assert the SHAPE of the
# result — line count, heading count, byte delta — not merely that the addition is present. That part
# was always right and is kept verbatim.
#
# NO `git mv` TO A PRETTIER NAME. The old version renamed the chosen prototype to `assets/banner/
# hero.svg`, which was safe for a hand-authored file and is not safe for this one: every v6 asset is
# EMITTED by tools/banner/gen.py, so a rename means the next `gen.py --out assets/banner` recreates
# the original name and quietly stops maintaining the file the README points at. The README names the
# generator's own output path, and this script refuses to land an asset that a fresh generator run
# does not reproduce byte-for-byte.

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

PICK="v6c-dusk-line"  # THE PICK, docs/plans/BANNER_NARRATIVE_SPEC.md § THE PICK (operator, 2026-07-29)
CHOICE="$PICK"; DRY=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    -*)        echo "banner-apply-header: unknown flag $a" >&2; exit 2 ;;
    *)         CHOICE="$a" ;;
  esac
done

SRC="assets/banner/${CHOICE}.svg"
[[ -f "$SRC" ]] || { echo "banner-apply-header: missing $SRC" >&2; exit 1; }
[[ -f README.md ]] || { echo "banner-apply-header: no README.md here" >&2; exit 1; }

# The asset must be the generator's own current output. A README pointing at a hand-edited SVG is a
# file with no generator, which is the one thing this whole track refuses to ship.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
python3 tools/banner/gen.py --out "$TMP" >/dev/null
if ! cmp -s "$SRC" "$TMP/${CHOICE}.svg"; then
  echo "banner-apply-header: $SRC is NOT what gen.py currently emits — regenerate before landing" >&2
  exit 1
fi
echo "  $SRC reproduces byte-identically from tools/banner/gen.py"

# Alt text describes what the file ACTUALLY does, beat by beat. It is long because the subject is a
# four-minute animation with three narrative events, and a reader on a screen reader gets this or
# nothing. Every claim in it is a thing the generator emits.
ALT="An animated banner that loops seamlessly every four minutes. The words claude-infrastructure \
stand in a dusk sky above the words sessions run each other, legible at every moment of it; a \
crescent moon and three tiers of stars sit to the left, and banded clouds drift behind. Below, the \
Claude Code creature — an orange pixel-art figure with two square eyes and four legs — \
walks a dark ground that scrolls beneath it, leaving one continuous line of footprints. Three things \
happen. At four seconds it puts on a hat and a second, smaller creature arrives in a burst of light; \
the walker turns its eyes to watch, hands it a pale letter, and the letter comes back with a green \
face — the finished work — before the smaller creature leaves in a second burst. At \
seventeen seconds a gate arm drops across the path ahead; the walker settles, the ground pulls \
backward by exactly one footprint, the walker re-walks the step it was sent back over, and the \
ground then runs at double speed to make the distance up. At twenty-six seconds the walker looks up \
out of the frame at you, and half a second later the whole world stops — six seconds in which \
nothing moves but three blinks — after which the ground runs at treble speed to clear the time \
it spent waiting."

CAP="<sub><b>One four-minute loop — the title never leaves, and three things happen around \
it.</b> A session <b>summons</b> a subagent, which hands work back and removes itself; a hook \
<b>refuses</b> a turn that tried to end early, and the world is pulled back one footprint and has to \
re-walk it; and a decision with no default <b>stops everything</b> until a human answers. Nothing \
here is decoration: the ground's scroll rate is the only gauge the piece owns, so every beat is \
spoken in it, and a stop or a rewind must be repaid inside the loop at a whole-number rate or the \
footprints stop landing in their own prints. Generated by <a href=\"tools/banner/gen.py\"><code>\
tools/banner/gen.py</code></a>, which refuses to emit rather than ship a subtly wrong asset, and \
gated by <a href=\"scripts/banner-verify.sh\"><code>banner-verify.sh</code></a> — where \
<code>t=0</code> and <code>t=240</code> must render <b>pixel-identical</b>, so the loop cannot have a \
visible restart. <code>prefers-reduced-motion</code> gets a frame the animation genuinely passes \
through.</sub>"

BLOCK="<img src=\"$SRC\" width=\"900\" alt=\"$ALT\">"

# The anchor is the first three lines of the file, matched exactly and required to be unique.
ANCHOR=$'<div align="center">\n\n# Claude Code Infrastructure'

python3 - "$BLOCK" "$CAP" "$ANCHOR" "$DRY" <<'PY'
import pathlib, sys

# No unicode_escape round-trip on these. The first version ran one "to handle escapes" and there are
# none to handle — argv arrives already decoded — so all it did was reinterpret UTF-8 bytes as
# latin-1 and write "loop â the title" into the README where an em-dash belonged.
block, cap, anchor, dry = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4] == "1"
p = pathlib.Path("README.md")
before = p.read_text()

if block.split("alt=")[0] in before:
    sys.exit("banner-apply-header: a hero banner is already in the README — nothing to do")

n = before.count(anchor)
if n != 1:
    sys.exit(f"banner-apply-header: anchor found {n} times, expected exactly 1 — refusing to edit")
if not before.startswith(anchor):
    sys.exit("banner-apply-header: anchor is not at the top of the file — refusing to edit")

lines_before = before.count("\n")
heads_before = sum(1 for l in before.splitlines() if l.startswith("#"))

add = f"{block}\n\n{cap}"
after = before.replace(anchor, f'<div align="center">\n\n{add}\n\n# Claude Code Infrastructure', 1)

# assert the SHAPE, not just that the addition is present
lines_after = after.count("\n")
heads_after = sum(1 for l in after.splitlines() if l.startswith("#"))
problems = []
if lines_after != lines_before + 4:
    problems.append(f"line count {lines_before} -> {lines_after}, expected +4")
if heads_after != heads_before:
    problems.append(f"heading count {heads_before} -> {heads_after}, expected unchanged")
if len(after) != len(before) + len(add) + 2:
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

[[ "$DRY" -eq 1 ]] && exit 0

echo
echo "Review it, then commit:"
echo "  git add README.md && git commit -m 'feat(readme): the animated hero banner'"
