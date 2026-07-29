#!/usr/bin/env bash
# banner-shots.sh — screenshot a banner asset the way GitHub actually renders it.
#
# Renders the asset INSIDE <img src="…">, which is SVG-as-image mode: no scripts, no external
# resources, stricter than opening the SVG as a document. That is the mode GitHub uses, so it is
# the only mode worth verifying in.
#
# Animated frames are frozen DETERMINISTICALLY by injecting
#   animation-delay: -Ts; animation-play-state: paused
# rather than by racing a wall clock, so the same timestamp screenshots identically every run.
#
# That freeze is only EXACT while every element carries at most ONE animation. An element with a
# comma-list of animations has per-animation delays, and a blanket -Ts override collapses them —
# a second, delayed animation starts immediately and paints its value into frames it should not
# appear in. `--lint` fails on exactly that, because a silently-wrong reference render is worse
# than no render. (Measured 2026-07-29: a two-animation #haloR painted its idle-breath opacity
# into every narrative frame; a control render is what caught it.)
#
# Chromium's --virtual-time-budget was tried as a cross-check against the unmodified file and is
# INERT here: it does not drive the animation clock of an SVG loaded as an image, so every
# timestamp rendered identically. It is deliberately not offered — a verification mode that
# cannot fail is worse than none.
#
#   scripts/banner-shots.sh <asset> --times 0,1.5,3,7 --bg dark --out /tmp/shots
#   scripts/banner-shots.sh <asset> --reduced-motion --out /tmp/shots
#   scripts/banner-shots.sh <asset> --lint
#
# Requires the playwright Chromium already on this machine; no network, no npm install.

set -euo pipefail

# glob rather than `ls`: highest-numbered install wins, and no parsing of filenames
CHROME=""
for _c in "$HOME"/Library/Caches/ms-playwright/chromium-*/chrome-mac/Chromium.app/Contents/MacOS/Chromium; do
  [[ -x "$_c" ]] && CHROME="$_c"
done
[[ -x "$CHROME" ]] || { echo "banner-shots: no playwright Chromium found" >&2; exit 1; }

ASSET=""; TIMES="0"; BG="dark"; OUT="./shots"; WIDTH=900; SCALE=2; REDUCED=0; LINT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --times)          TIMES="$2"; shift 2 ;;
    --bg)             BG="$2"; shift 2 ;;
    --out)            OUT="$2"; shift 2 ;;
    --width)          WIDTH="$2"; shift 2 ;;
    --scale)          SCALE="$2"; shift 2 ;;
    --reduced-motion) REDUCED=1; shift ;;
    --lint)           LINT=1; shift ;;
    -*)               echo "banner-shots: unknown flag $1" >&2; exit 2 ;;
    *)                ASSET="$1"; shift ;;
  esac
done
[[ -n "$ASSET" && -f "$ASSET" ]] || { echo "banner-shots: asset not found: ${ASSET:-<none>}" >&2; exit 2; }

ASSET=$(cd "$(dirname "$ASSET")" && pwd)/$(basename "$ASSET")
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
STEM=$(basename "$ASSET"); STEM="${STEM%.*}"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# The freeze is exact only while no element carries a comma-list of animations. Fail loudly
# rather than emit a reference render that is quietly wrong.
if [[ "$LINT" -eq 1 ]]; then
  python3 - "$ASSET" <<'PY'
import re, sys, pathlib
svg = pathlib.Path(sys.argv[1]).read_text()
bad = []
for prop in ('animation', 'animation-name', 'animation-delay', 'animation-duration'):
    for m in re.finditer(rf'(?<![\w-]){prop}\s*:\s*([^;{{}}]+)', svg):
        value = m.group(1)
        # a comma inside animation shorthand/longhand means more than one animation on the element
        if ',' in value:
            line = svg.count('\n', 0, m.start()) + 1
            bad.append(f'  line {line}: {prop}: {value.strip()}')
if bad:
    print('banner-shots --lint: FAIL — element(s) carry more than one animation, so a frozen', file=sys.stderr)
    print('frame cannot represent their real state (see the header comment):', file=sys.stderr)
    print('\n'.join(bad), file=sys.stderr)
    sys.exit(1)
print('banner-shots --lint: ok — one animation per element, frozen frames are exact')
PY
  exit $?
fi

# Page background matches the real GitHub canvas so contrast is judged, not guessed.
case "$BG" in
  dark)  PAGE="#0d1117" ;;   # github dark default
  light) PAGE="#ffffff" ;;   # github light default
  *)     PAGE="$BG" ;;
esac

# Freeze an animated SVG at time T by appending an override <style> (last rule wins, plus
# !important). Geometry is untouched — only the animation clock moves.
freeze() {
  local src="$1" t="$2" dst="$3"
  python3 - "$src" "$t" "$dst" <<'PY'
import sys, pathlib
src, t, dst = sys.argv[1], sys.argv[2], sys.argv[3]
svg = pathlib.Path(src).read_text()
override = (
    f'<style id="__freeze">*{{'
    f'animation-delay:-{t}s !important;'
    f'animation-play-state:paused !important;'
    f'}}</style>'
)
i = svg.rfind('</svg>')
if i == -1:
    sys.exit('banner-shots: no closing </svg>')
pathlib.Path(dst).write_text(svg[:i] + override + svg[i:])
PY
}

# Display height at $WIDTH, so the screenshot is the banner and not a page with a banner on it.
img_height() {
  python3 - "$1" "$WIDTH" <<'PY'
import re, subprocess, sys
src, width = sys.argv[1], int(sys.argv[2])
if src.lower().endswith('.svg'):
    head = open(src, encoding='utf-8').read(4000)
    m = re.search(r'viewBox\s*=\s*["\']\s*[\d.eE+-]+\s+[\d.eE+-]+\s+([\d.eE+-]+)\s+([\d.eE+-]+)', head)
    w, h = (float(m.group(1)), float(m.group(2))) if m else (16.0, 9.0)
else:
    out = subprocess.run(['magick', 'identify', '-format', '%w %h', src + '[0]'],
                         capture_output=True, text=True).stdout.split()
    w, h = (float(out[0]), float(out[1])) if len(out) == 2 else (16.0, 9.0)
print(max(1, round(width * h / w)))
PY
}

shoot() {
  local img="$1" png="$2" extra="${3:-}"
  local html vh
  html="$WORK/page-$(basename "${png%.png}").html"
  vh=$(img_height "$img")
  # Sized to the image so the screenshot is the banner, not a page with a banner on it.
  cat > "$html" <<HTML
<!doctype html><meta charset="utf-8">
<style>
  html,body{margin:0;padding:0;background:$PAGE}
  body{display:flex;align-items:flex-start;justify-content:center}
  img{width:${WIDTH}px;height:auto;display:block}
</style>
<img src="file://$img" width="$WIDTH">
HTML
  # shellcheck disable=SC2086
  "$CHROME" --headless --disable-gpu --hide-scrollbars --no-sandbox \
      --force-device-scale-factor="$SCALE" \
      --window-size="$WIDTH","$vh" \
      $extra \
      --screenshot="$png" "file://$html" >/dev/null 2>&1
  [[ -s "$png" ]] || { echo "banner-shots: empty screenshot for $png" >&2; return 1; }
}

FLAGS=""
[[ "$REDUCED" -eq 1 ]] && FLAGS="--force-prefers-reduced-motion"

if [[ "$REDUCED" -eq 1 ]]; then
  png="$OUT/${STEM}-${BG}-reduced.png"
  shoot "$ASSET" "$png" "$FLAGS"
  echo "$png"
  exit 0
fi

IFS=',' read -r -a TS <<< "$TIMES"
for t in "${TS[@]}"; do
  tag=$(printf '%s' "$t" | tr '.' 'p')
  png="$OUT/${STEM}-${BG}-t${tag}.png"
  frozen="$WORK/frozen-$tag.svg"
  if [[ "$ASSET" == *.svg ]]; then freeze "$ASSET" "$t" "$frozen"; else frozen="$ASSET"; fi
  shoot "$frozen" "$png" "$FLAGS"
  echo "$png"
done
