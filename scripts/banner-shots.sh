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
multi, delayed = [], []
TIME = re.compile(r'(?<![\w.])-?\d*\.?\d+m?s(?![\w.])')
for prop in ('animation', 'animation-name', 'animation-delay', 'animation-duration'):
    for m in re.finditer(rf'(?<![\w-]){prop}\s*:\s*([^;{{}}]+)', svg):
        value = m.group(1)
        line = svg.count('\n', 0, m.start()) + 1
        # a comma inside animation shorthand/longhand means more than one animation on the element
        if ',' in value:
            multi.append(f'  line {line}: {prop}: {value.strip()}')
            continue
        # An AUTHORED delay is clobbered by the freeze, which sets animation-delay on `*` to reach
        # the requested timestamp. The element still animates correctly in a browser, but every
        # frozen frame renders it at the wrong phase — so a staggered population screenshots in
        # lockstep, which is a more convincing lie than an obviously broken render.
        if prop == 'animation-delay':
            if not re.fullmatch(r'0m?s|0', value.strip()):
                delayed.append(f'  line {line}: {prop}: {value.strip()}')
        elif prop == 'animation' and len(TIME.findall(value)) > 1:
            delayed.append(f'  line {line}: {prop}: {value.strip()}   (2nd time value is a delay)')
if multi:
    print('banner-shots --lint: FAIL — element(s) carry more than one animation, so a frozen', file=sys.stderr)
    print('frame cannot represent their real state (see the header comment):', file=sys.stderr)
    print('\n'.join(multi), file=sys.stderr)
if delayed:
    print('banner-shots --lint: FAIL — authored animation-delay. The freeze overrides delay on', file=sys.stderr)
    print('every element to seek the timestamp, so an authored one is silently discarded and the', file=sys.stderr)
    print('render shows the wrong phase:', file=sys.stderr)
    print('\n'.join(delayed), file=sys.stderr)
    print('  Put the phase offset in the KEYFRAME PERCENTAGES instead — a per-element @keyframes', file=sys.stderr)
    print('  with its events shifted inside the same period survives the freeze exactly.', file=sys.stderr)
if multi or delayed:
    sys.exit(1)
print('banner-shots --lint: ok — one animation per element, no authored delay; frozen frames are exact')
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
# Prints two numbers: the CSS height to size the window by, and the exact device height to crop to.
# They differ because the CSS one is rounded while the real image edge lands on a fraction — a
# 1920x780 asset at 900 CSS px is 365.625 tall, so a round-and-multiply crop keeps one row of page
# background. Flooring the device height drops that row and no part of the banner.
img_height() {
  python3 - "$1" "$WIDTH" "$SCALE" <<'PY'
import math, re, subprocess, sys
src, width, scale = sys.argv[1], int(sys.argv[2]), float(sys.argv[3])
if src.lower().endswith('.svg'):
    head = open(src, encoding='utf-8').read(4000)
    m = re.search(r'viewBox\s*=\s*["\']\s*[\d.eE+-]+\s+[\d.eE+-]+\s+([\d.eE+-]+)\s+([\d.eE+-]+)', head)
    w, h = (float(m.group(1)), float(m.group(2))) if m else (16.0, 9.0)
else:
    out = subprocess.run(['magick', 'identify', '-format', '%w %h', src + '[0]'],
                         capture_output=True, text=True).stdout.split()
    w, h = (float(out[0]), float(out[1])) if len(out) == 2 else (16.0, 9.0)
print(max(1, round(width * h / w)), max(1, math.floor(width * h / w * scale)))
PY
}

# A headless window is TALLER than the page viewport it yields, so a window sized to the image
# delivers a viewport shorter than the image and silently crops its bottom to the page background.
# On GitHub dark that padding is the same colour as the plate, so the truncation is invisible: the
# render just looks like a banner with more empty space at the bottom than it has.
#
# Measured 2026-07-29 (Chromium 141, macOS): viewport_h = max(window_h, ~375) - 87. A 1920x780
# asset at --width 900 asks for a 366-tall window, gets a 288-tall viewport, and loses everything
# below y=613 of the viewBox. It reproduced identically under --headless=new and at every device
# scale factor, so it is not a headless-mode flag away from being correct.
#
# The inset is MEASURED rather than assumed — a hard-coded 87 is a constant from one machine, and
# the whole failure mode here is a number that is wrong without looking wrong. Requesting
# vh + inset then guarantees viewport >= vh (the minimum-window clamp only ever helps), and the
# extra padding is cropped back off, so the output is still exactly the banner.
VIEWPORT_INSET=""
calibrate_inset() {
  [[ -n "$VIEWPORT_INSET" ]] && return 0
  local probe="$WORK/inset.html" req=1000 got
  # A large request dodges the minimum-window clamp, so the difference is purely the inset.
  cat > "$probe" <<'HTML'
<!doctype html><meta charset="utf-8"><title>inset</title>
<body><script>addEventListener('load',()=>{document.body.textContent='INNERH='+innerHeight})</script>
HTML
  got=$("$CHROME" --headless --disable-gpu --no-sandbox --window-size=900,"$req" \
        --virtual-time-budget=800 --dump-dom "file://$probe" 2>/dev/null \
        | sed -n 's/.*INNERH=\([0-9][0-9]*\).*/\1/p' | head -1)
  [[ -n "$got" ]] && (( got > 0 && got <= req )) || {
    echo "banner-shots: could not measure the headless viewport inset (got '${got:-}')" >&2
    echo "  without it a tall asset is cropped silently — refusing to emit a render." >&2
    exit 1
  }
  VIEWPORT_INSET=$(( req - got ))
}

shoot() {
  local img="$1" png="$2" extra="${3:-}"
  local html vh win_h cw ch
  html="$WORK/page-$(basename "${png%.png}").html"
  read -r vh ch <<<"$(img_height "$img")"
  calibrate_inset
  win_h=$(( vh + VIEWPORT_INSET ))
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
      --window-size="$WIDTH","$win_h" \
      $extra \
      --screenshot="$png" "file://$html" >/dev/null 2>&1
  [[ -s "$png" ]] || { echo "banner-shots: empty screenshot for $png" >&2; return 1; }

  # Crop the inset padding back off, so the file on disk is the banner and nothing else. The
  # dimensions are asserted rather than trusted: a short capture means the inset moved, and a
  # quietly-padded render is the exact failure this whole path exists to prevent.
  cw=$(awk -v w="$WIDTH" -v s="$SCALE" 'BEGIN{printf "%d", w*s+0.5}')
  local got
  got=$(magick identify -format '%w %h' "$png" 2>/dev/null) || {
    echo "banner-shots: magick is required to crop the headless window inset" >&2; return 1; }
  # shellcheck disable=SC2086
  set -- $got
  (( $1 >= cw && $2 >= ch )) || {
    echo "banner-shots: capture ${1}x${2} is smaller than the banner ${cw}x${ch} — the viewport" >&2
    echo "  inset (${VIEWPORT_INSET}) no longer covers this window. Not emitting a cropped render." >&2
    return 1
  }
  magick "$png" -crop "${cw}x${ch}+0+0" +repage "$png"
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
