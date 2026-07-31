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

# Prefers chrome-headless-shell over the full Chromium.app bundle: the bundle registers with
# LaunchServices on EVERY launch, so this script's per-shot loop flashed a Dock tile every 1-2s
# for the whole run. Render-identical on SVG art and ~5x faster — measurements and the rejected
# --headless=new alternative are recorded on resolve_headless_chrome in lib/cc-common.sh.
_ccl="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/cc-common.sh"
[[ -f "$_ccl" ]] || _ccl="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-common.sh"
[[ -f "$_ccl" ]] || _ccl="$HOME/.claude/scripts/lib/cc-common.sh"
# shellcheck source=lib/cc-common.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if ! . "$_ccl" 2>/dev/null; then
  echo "banner-shots: FATAL — cannot source $_ccl (resolve_headless_chrome unavailable)" >&2
  exit 1
fi
CHROME="$(resolve_headless_chrome "${BANNER_CHROME:-}")"
[[ -x "$CHROME" ]] || { echo "banner-shots: no playwright Chromium found" >&2; exit 1; }

ASSET=""; TIMES="0"; BG="dark"; OUT="./shots"; WIDTH=900; SCALE=2; REDUCED=0; LINT=0; SCHEME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --times)          TIMES="$2"; shift 2 ;;
    --bg)             BG="$2"; shift 2 ;;
    --scheme)         SCHEME="$2"; shift 2 ;;
    --out)            OUT="$2"; shift 2 ;;
    --width)          WIDTH="$2"; shift 2 ;;
    --scale)          SCALE="$2"; shift 2 ;;
    --reduced-motion) REDUCED=1; shift ;;
    --lint)           LINT=1; shift ;;
    -*)               echo "banner-shots: unknown flag $1" >&2; exit 2 ;;
    *)                ASSET="$1"; shift ;;
  esac
done

# --scheme drives `prefers-color-scheme` INSIDE the SVG. Distinct from --bg, which only paints the
# page behind the image: an asset with a full-bleed background plate hides the page entirely, so
# --bg light on such an asset renders byte-identically to --bg dark and silently reports nothing.
# That is exactly what happened to v5a, whose light theme was never actually rendered.
# Values measured against this Chromium (141.0.7390.37), which defaults to DARK when unset:
#   0 -> dark matches   1 -> light matches   2 -> NEITHER matches (base stylesheet only)
# `none` is the useful third state: what a renderer without color-scheme support shows.
SCHEME_FLAG=""
case "$SCHEME" in
  "")          ;;
  dark)        SCHEME_FLAG="--blink-settings=preferredColorScheme=0" ;;
  light)       SCHEME_FLAG="--blink-settings=preferredColorScheme=1" ;;
  none)        SCHEME_FLAG="--blink-settings=preferredColorScheme=2" ;;
  *)           echo "banner-shots: --scheme must be dark|light|none (got '$SCHEME')" >&2; exit 2 ;;
esac
[[ -n "$ASSET" && -f "$ASSET" ]] || { echo "banner-shots: asset not found: ${ASSET:-<none>}" >&2; exit 2; }

ASSET=$(cd "$(dirname "$ASSET")" && pwd)/$(basename "$ASSET")
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
STEM=$(basename "$ASSET"); STEM="${STEM%.*}"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT

# The freeze is exact only while no element carries a comma-list of animations. Fail loudly
# rather than emit a reference render that is quietly wrong.
#
# Commas at the TOP LEVEL of the value separate animations. Commas nested inside a function do not:
# `steps(1,end)` and `cubic-bezier(.2,.7,0,1)` are single animations with a comma in their timing
# function. Testing the raw value for `,` therefore FALSE-FAILS every stepped or eased animation —
# which is most of them, since steps() is what keeps pixel art from interpolating into mush.
# (Measured 2026-07-29: v5a-long-walk.svg failed this lint on `animation: wA .5s steps(1,end)
# infinite`, a perfectly legal single animation. The lint was wrong, not the asset.)
if [[ "$LINT" -eq 1 ]]; then
  python3 - "$ASSET" <<'PY'
import re, sys, pathlib

def top_level_commas(value: str) -> int:
    """Commas at nesting depth 0 — the only ones that separate animations."""
    depth = n = 0
    for ch in value:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth = max(0, depth - 1)
        elif ch == ',' and depth == 0:
            n += 1
    return n

svg = pathlib.Path(sys.argv[1]).read_text()
multi, delayed = [], []
TIME = re.compile(r'(?<![\w.])-?\d*\.?\d+m?s(?![\w.])')
for prop in ('animation', 'animation-name', 'animation-delay', 'animation-duration'):
    # The value ends at `;`, at a rule brace — or at a QUOTE. Animation properties are routinely
    # set through an inline style="animation-delay:-3s", and a value class that does not stop at
    # the closing quote runs on through the rest of the element, picking up unrelated attributes:
    # font-family="ui-monospace,Menlo,monospace" then supplies a top-level comma and the element
    # is reported as carrying two animations. A CSS value cannot contain a bare quote here.
    for m in re.finditer(rf'(?<![\w-]){prop}\s*:\s*([^;{{}}"\']+)', svg):
        value = m.group(1)
        line = svg.count('\n', 0, m.start()) + 1
        # Commas at the TOP LEVEL of the value separate animations. Commas nested inside a function
        # do not: `steps(1,end)` and `cubic-bezier(.2,.7,0,1)` are single animations with a comma in
        # their timing function. Testing the raw value for `,` false-fails every stepped or eased
        # animation — which is most of them, since steps() is what keeps pixel art from interpolating
        # into mush. (Measured 2026-07-29: v5a-long-walk.svg failed on `animation: wA .5s
        # steps(1,end) infinite`, a perfectly legal single animation. The lint was wrong, not it.)
        if top_level_commas(value):
            multi.append(f'  line {line}: {prop}: {value.strip()}')
            continue
        # A LITERAL authored delay is clobbered by the freeze's seek, so the element still animates
        # correctly in a browser but every frozen frame renders it at the wrong phase — a staggered
        # population screenshots in lockstep, a more convincing lie than an obviously broken render.
        #
        # Phase itself is legitimate and necessary (many elements, one shared master period), so what
        # is rejected is the CLOBBERED spelling, not phase. The additive channel
        # `animation-delay: calc(var(--d,0s) + var(--fz,0s))` with per-element `--d` survives the
        # seek — see freeze() — so a value that routes through it passes.
        if prop == 'animation-delay':
            v = value.strip()
            additive = 'var(--d' in v and 'var(--fz' in v
            if not additive and not re.fullmatch(r'0m?s|0', v):
                delayed.append(f'  line {line}: {prop}: {v}'
                               f'   (use --d + the calc form so the freeze can seek it)')
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
#
# The seek is ADDITIVE rather than absolute. A flat `animation-delay:-Ts !important` reaches the
# timestamp but destroys every authored phase, so a deliberately staggered population — a star field
# twinkling out of step, two legs half a stride apart — screenshots in LOCKSTEP. That is a more
# convincing lie than an obviously broken render, which is why `--lint` rejects an authored delay.
#
# But phase-by-negative-delay is the sanctioned way to run many elements off one shared master period
# (README_HERO_BANNER § S2), so the harness has to be able to seek it rather than forbid it. The fix
# is a two-part custom property: the ASSET carries its per-element phase in `--d`, the FREEZE supplies
# the global seek in `--fz`, and the delay is their sum. Custom properties inherit into SVG children,
# so one rule on the root reaches everything.
#
# Measured in this exact mode (SVG-as-image, Chromium 141) with three rects at --d 0/-1/-2s on a 4s
# steps(4) colour cycle: with --fz the three stay one step apart and rotate together as --fz changes;
# with the old blanket override all three render the SAME colour. An asset that does not use `--d`
# is unaffected — var(--d,0s) falls back to 0s and it seeks exactly as before.
freeze() {
  local src="$1" t="$2" dst="$3"
  python3 - "$src" "$t" "$dst" <<'PY'
import sys, pathlib
src, t, dst = sys.argv[1], sys.argv[2], sys.argv[3]
svg = pathlib.Path(src).read_text()
override = (
    f'<style id="__freeze">'
    f'svg{{--fz:-{t}s}}'
    f'*{{'
    f'animation-delay:calc(var(--d,0s) + var(--fz,0s)) !important;'
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
  # Spelled as an explicit if: `A && B || C` reads as if-then-else and is not one — C also runs
  # when A succeeds and B fails, which here is right by luck rather than by construction.
  if [[ -z "$got" ]] || (( got <= 0 )) || (( got > req )); then
    echo "banner-shots: could not measure the headless viewport inset (got '${got:-}')" >&2
    echo "  without it a tall asset is cropped silently — refusing to emit a render." >&2
    exit 1
  fi
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

FLAGS="$SCHEME_FLAG"
[[ "$REDUCED" -eq 1 ]] && FLAGS="$FLAGS --force-prefers-reduced-motion"

# The scheme is part of the render's identity, so it is part of the filename — otherwise a light
# render silently overwrites the dark one at the same timestamp and the difference is invisible.
SUFFIX="$BG"
[[ -n "$SCHEME" ]] && SUFFIX="$BG-$SCHEME"

if [[ "$REDUCED" -eq 1 ]]; then
  png="$OUT/${STEM}-${SUFFIX}-reduced.png"
  shoot "$ASSET" "$png" "$FLAGS"
  echo "$png"
  exit 0
fi

IFS=',' read -r -a TS <<< "$TIMES"
for t in "${TS[@]}"; do
  tag=$(printf '%s' "$t" | tr '.' 'p')
  png="$OUT/${STEM}-${SUFFIX}-t${tag}.png"
  frozen="$WORK/frozen-$tag.svg"
  if [[ "$ASSET" == *.svg ]]; then freeze "$ASSET" "$t" "$frozen"; else frozen="$ASSET"; fi
  shoot "$frozen" "$png" "$FLAGS"
  echo "$png"
done
