#!/bin/bash
# renderer-grid.sh — composite the per-terminal films into ONE animated 2x2 for the README.
#
# WHY AN ANIMATED IMAGE AND NOT THE MP4s. GitHub's markdown sanitizer strips <video> outright, so the
# only thing that can MOVE inline is an image. The 1080p60 masters stay as links beside it; without
# this file the README shows a still and the recordings are one click away, which is not "in the
# README" (operator, 2026-08-01: "I only see screenshots and not 1080p 60fps videos").
#
# WHY WebP AT near_lossless, AND WHY IT IS SO EXPENSIVE. 18 panes of shifting 24-bit colour is close
# to per-pixel noise: WebP animation has no motion compensation, so nearly every pixel is new every
# frame. Measured on one terminal, 3 s:
#     900px 10fps  3.34 MB   ·   760px 10fps  2.31 MB   ·   700px 8fps  1.62 MB   ·   620px 8fps  1.27 MB
# and LOSSY is both worse-looking AND BIGGER on this content (q72 = 8.3 MB against near_lossless
# 40 = 4.2 MB at 760px/12fps/5s), because lossy WebP seams every flat region and the black
# background is one enormous flat region. GIF measured 17.5 MB for 8 s at 1200px. So the levers are
# duration, rate and size — not the codec — and the tile geometry below is chosen against those
# measurements rather than by eye.
#
# USAGE
#   assets/demo/renderer-grid.sh                       # all films found, 2x2, README defaults
#   assets/demo/renderer-grid.sh --tile 460 --fps 8 --seconds 3
# VERDICT: verdict=OK | verdict=NO-FILMS
set -uo pipefail

TILE_W=620; FPS=8; SECS=3; START=6; OUTNAME="renderer-grid.webp"
while [ $# -gt 0 ]; do
  case "$1" in
    --tile)    TILE_W="${2:-620}"; shift 2 ;;
    --fps)     FPS="${2:-8}"; shift 2 ;;
    --seconds) SECS="${2:-3}"; shift 2 ;;
    --start)   START="${2:-6}"; shift 2 ;;
    --out)     OUTNAME="${2:-renderer-grid.webp}"; shift 2 ;;
    -h|--help) sed -n '1,22p' "$0"; exit 0 ;;
    *) echo "renderer-grid: unknown arg: $1" >&2; exit 2 ;;
  esac
done

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  _l="$(readlink "$SELF")"; case "$_l" in /*) SELF="$_l" ;; *) SELF="$(cd "$(dirname "$SELF")" && pwd -P)/$_l" ;; esac
done
REPO="${CC_REPO:-$(cd "$(dirname "$SELF")/../.." && pwd -P)}"
cd "$REPO" || { echo "renderer-grid: cannot cd to $REPO" >&2; exit 1; }
DEMO="$REPO/assets/demo"

# Order is fixed and meaningful: the challenger first, the incumbent last, so the 2x2 reads the way
# the section argues. A film that is absent is SKIPPED with a named line rather than silently
# dropped — a 2x2 quietly rendered as a 1x3 would misrepresent what was tested.
LABELS=("kitty — 18 panes, one window" "WezTerm — 18 panes, one window"
        "Ghostty — 18 panes, one window" "iTerm2 (isolated clone) — 18 panes, one window")
APPS=(kitty wezterm ghostty itermbench)

FOUND=(); FOUND_LABELS=()
for i in "${!APPS[@]}"; do
  f="$DEMO/renderer-${APPS[$i]}.mp4"
  if [ -f "$f" ]; then FOUND+=("$f"); FOUND_LABELS+=("${LABELS[$i]}")
  else echo "  ⚠ no film for ${APPS[$i]} — tile omitted"; fi
done
[ "${#FOUND[@]}" -gt 0 ] || { echo "renderer-grid: no films found in $DEMO" >&2; echo "verdict=NO-FILMS"; exit 3; }
echo "== renderer-grid  tiles=${#FOUND[@]} tile_w=$TILE_W fps=$FPS ${SECS}s =="

WORK="${TMPDIR:-/tmp}/renderer-grid.$$"
rm -rf "$WORK"; mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

for i in "${!FOUND[@]}"; do
  mkdir -p "$WORK/t$i"
  ffmpeg -v error -y -ss "$START" -t "$SECS" -i "${FOUND[$i]}" \
    -vf "fps=${FPS},scale=${TILE_W}:-2:flags=lanczos" "$WORK/t$i/%04d.png" || {
    echo "renderer-grid: frame extraction failed for ${FOUND[$i]}" >&2; exit 1; }
done

# Composite with PIL: this ffmpeg has no drawtext (built without libfreetype), so labels must be
# RENDERED, not drawn by a filter.
LABELS_JOINED="$(printf '%s\n' "${FOUND_LABELS[@]}")"
WORK="$WORK" TILE_W="$TILE_W" LABELS_JOINED="$LABELS_JOINED" python3 - <<'PY'
import os, glob
from PIL import Image, ImageDraw, ImageFont

work = os.environ["WORK"]
labels = os.environ["LABELS_JOINED"].split("\n")
tiles = sorted(d for d in glob.glob(os.path.join(work, "t*")) if os.path.isdir(d))
seqs = [sorted(glob.glob(os.path.join(t, "*.png"))) for t in tiles]
# Every tile must contribute the same number of frames or the grid desynchronises; the shortest wins.
n = min(len(s) for s in seqs)
w, h = Image.open(seqs[0][0]).size
LAB = 22
# 2x2 only when there are FOUR films. With three, a 2-column grid renders one black quadrant, which
# reads as a broken image rather than as three terminals — so an incomplete set stacks instead.
cols = 2 if len(tiles) == 4 else 1
rows = (len(tiles) + cols - 1) // cols
try:
    font = ImageFont.truetype("/System/Library/Fonts/SFNSMono.ttf", 13)
except Exception:
    font = ImageFont.load_default()

out = os.path.join(work, "grid")
os.makedirs(out, exist_ok=True)
for k in range(n):
    sheet = Image.new("RGB", (cols * w, rows * (h + LAB)), "black")
    d = ImageDraw.Draw(sheet)
    for i, seq in enumerate(seqs):
        cx, cy = (i % cols) * w, (i // cols) * (h + LAB)
        d.text((8, cy + 4), labels[i], font=font, fill=(185, 185, 185))
        sheet.paste(Image.open(seq[k]).convert("RGB"), (cx, cy + LAB))
    sheet.save(os.path.join(out, "%04d.png" % k))
print("composited %d frames at %dx%d" % (n, cols * w, rows * (h + LAB)))
PY

DELAY="$(awk -v f="$FPS" 'BEGIN{printf "%d", 1000/f}')"
img2webp -loop 0 -d "$DELAY" -near_lossless 40 "$WORK"/grid/*.png -o "$DEMO/$OUTNAME" >/dev/null 2>&1 || {
  echo "renderer-grid: img2webp failed" >&2; exit 1; }

# Verify it ANIMATES rather than trusting the encoder: a single-frame WebP is a still wearing an
# animation's filename, which is exactly the failure this file exists to correct.
FRAMES="$(webpinfo "$DEMO/$OUTNAME" 2>/dev/null | grep -c '^Chunk ANMF')"
[ "${FRAMES:-0}" -gt 1 ] || { echo "renderer-grid: output has ${FRAMES:-0} animation frame(s)" >&2; exit 1; }
echo "  $DEMO/$OUTNAME — $FRAMES frames, $(wc -c < "$DEMO/$OUTNAME" | tr -d ' ') bytes"
echo "verdict=OK tiles=${#FOUND[@]} frames=$FRAMES"
