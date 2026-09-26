#!/usr/bin/env bash
# hero-film-render.sh: render the README hero launch film (tools/hero-film/) into its deliverables.
#
#   bash scripts/hero-film-render.sh pacing   # the pacing gate: camera speed and reading time, per frame
#   bash scripts/hero-film-render.sh review   # 2 fps stills of both cuts and grades -> contact sheets
#   bash scripts/hero-film-render.sh loop     # assets/hero/hero-{dark,light}.webp + poster-{dark,light}.png
#   bash scripts/hero-film-render.sh film     # assets/hero/launch-film.mp4 (dark, 3840x2160, 60 fps)
#   bash scripts/hero-film-render.sh seam     # loop seam: frame 0 against the last frame, both grades
#   bash scripts/hero-film-render.sh verify   # decode the shipped WebPs and check them (hero-film-verify.py)
#
# Adapted from agent-context-sync scripts/film-render.sh (round 3, approved 2026-09-24). Frames go to
# $OUT (default /tmp/cih-film); only the deliverables are written into the repo.
set -euo pipefail
# Resolve $0 through its symlinks before deriving the repo root: through the ~/.claude layer,
# scripts/ is a farm of per-file symlinks, and `dirname "$0"/..` would be ~/.claude, not the repo
# (the land gate's self-path ratchet; the loop is _resolve_self() in scripts/ship-land.sh).
_resolve_self() {
  local p="$1" d
  while [[ -L "$p" ]]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
cd "$(dirname "$SELF")/.."

OUT=${OUT:-/tmp/cih-film}
LOOP_W=${LOOP_W:-1676} # 2x the 838 CSS px README column
LOOP_H=${LOOP_H:-943}
FONT=${FONT:-/System/Library/Fonts/Menlo.ttc}
LOOP_FPS=${LOOP_FPS:-60}
FILM_FPS=${FILM_FPS:-60}
# Round 3: the page is photographed at 2x (3840 x 2160). That is the FILM's size, and the loop's
# supersampled source: 2.3 source pixels per output pixel across, so edges and pane text resolve
# instead of stair-stepping. The loop stays 1676 px wide: that is 2x the README's 838 CSS px column,
# and 3x would push a 60 fps flight frame's decode past its 16.7 ms (measured: p90 6.8 ms at 1676).
LOOP_SCALE=${LOOP_SCALE:-2}
FILM_SCALE=${FILM_SCALE:-2}
WORKERS=${WORKERS:-3}
CAP="node scripts/hero-film-capture.mjs"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing dependency: $1" >&2; exit 1; }; }
need node; need ffmpeg; need magick; need img2webp; need webpinfo; need python3

# three.js and the Geist fonts are render-time dependencies only: install them without touching
# package.json or the lockfile (the repo's own dependencies are for other tools).
if [ ! -f node_modules/three/build/three.module.js ] || [ ! -d node_modules/@fontsource/geist-sans ] || [ ! -d node_modules/@fontsource/geist-mono ]; then
  npm install --no-save --no-audit --no-fund three@0.186.1 @fontsource/geist-sans@5.3.0 @fontsource/geist-mono@5.3.0 >/dev/null
fi

sheet() { # $1 = frame dir, $2 = output png, $3 = columns
  local dir=$1 out=$2 cols=${3:-4} labelled="$1/labelled"
  mkdir -p "$labelled"
  rm -f "$labelled"/*.png
  # Each frame is labelled with its time from meta.json. Python drives magick directly, so no
  # tab-separated rows cross a shell read (the land gate's tsv-pad ratchet).
  python3 - "$dir" "$labelled" "$FONT" <<'PY'
import json, subprocess, sys, pathlib
d, labelled, font = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]), sys.argv[3]
times = json.loads((d / 'meta.json').read_text())['times']
for f, t in zip(sorted(d.glob('f*.png')), times):
    subprocess.run(['magick', str(f), '-resize', '800x', '-font', font, '-gravity', 'NorthWest', '-fill', '#ff00ff',
                    '-undercolor', '#000000c0', '-pointsize', '26', '-annotate', '+10+8', f'{t:.2f} s', str(labelled / f.name)], check=True)
PY
  magick montage "$labelled"/f*.png -font "$FONT" -tile "${cols}x" -geometry +6+6 -background '#888888' "$out"
}

review() {
  for cut in loop film; do
    for theme in dark light; do
      [ "$cut" = film ] && [ "$theme" = light ] && continue # the film ships in one grade
      local dir="$OUT/review-$cut-$theme"
      $CAP --cut "$cut" --theme "$theme" --fps "${REVIEW_FPS:-2}" --width 1920 --height 1080 --workers "$WORKERS" --out "$dir"
      sheet "$dir" "$OUT/sheet-$cut-$theme.png" 5
      echo "  $OUT/sheet-$cut-$theme.png"
    done
  done
}

# The pacing gate (scripts/hero-film-pacing.py): the page reports every frame's camera flow, story
# clock and type state without rendering, and the checker fails on any frame over a speed bound or any
# line held for less than its reading time. loop and film run it first, so no render starts on a cut
# that would fail it.
pacing() {
  mkdir -p "$OUT"
  for cut in loop film; do
    $CAP --cut "$cut" --probe "$OUT/pacing-$cut.json"
  done
  python3 scripts/hero-film-pacing.py "$OUT/pacing-loop.json" "$OUT/pacing-film.json"
}

loop() {
  pacing
  mkdir -p assets/hero
  for theme in dark light; do
    local dir="$OUT/loop-$theme"
    # Every frame at 60 fps, flights included (operator, round two: 20 fps flights read as judder).
    $CAP --cut loop --theme "$theme" --fps "$LOOP_FPS" --width 1920 --height 1080 --scale "$LOOP_SCALE" --workers "$WORKERS" --out "$dir"
    mkdir -p "$dir/small"
    rm -f "$dir/small"/*.png
    cp "$dir/meta.json" "$dir/small/"
    # Downscale, and soften each frame in proportion to how fast the picture moves in it (the pacing
    # report's image flow, frame for frame): sigma = SOFT_MAX px at the gate's speed bound, nothing at
    # rest. Motion hides it and a flight lands into focus without a pop. Measured round two on the
    # homeward flight (324 frames, lossy q30): 4.23 MB at SOFT_MAX 1.5, 4.03 at 2.0, 3.88 at 2.5.
    # Round 3 (the operator asked for higher resolution): SOFT_MAX 1.0 against the new 2,000 px/s bound,
    # so a flight softens a little at its peak and nowhere else.
    python3 - "$dir" "$OUT/pacing-loop.json" "${LOOP_W}x${LOOP_H}!" "${SOFT_MAX:-1.0}" "${JOBS:-8}" <<'PY'
import json, pathlib, subprocess, sys
from concurrent.futures import ThreadPoolExecutor
d, pacing, size, soft, jobs = pathlib.Path(sys.argv[1]), json.loads(pathlib.Path(sys.argv[2]).read_text()), sys.argv[3], float(sys.argv[4]), int(sys.argv[5])
flow = [max(f["flow"]) * pacing["fps"] for f in pacing["frames"]]
frames = sorted(d.glob("f*.png"))
if len(frames) != len(flow):
    sys.exit(f"{len(frames)} frames but the pacing report has {len(flow)}: re-run the capture and the gate together")
def one(k):
    sigma = round(soft * min(1.0, flow[k] / 2000.0), 2)
    args = ["magick", str(frames[k]), "-filter", "Lanczos", "-resize", size]
    if sigma >= 0.05:
        args += ["-blur", f"0x{sigma}"]
    subprocess.run([*args, str(d / "small" / frames[k].name)], check=True)
with ThreadPoolExecutor(jobs) as ex:
    list(ex.map(one, range(len(frames))))
PY
  done
  # The two grades encode in parallel: the encoder is single-threaded and is most of the time.
  local pids=() theme
  for theme in dark light; do
    python3 scripts/hero-film-encode-loop.py "$OUT/loop-$theme/small" "assets/hero/hero-$theme.webp" --hold "${LOOP_HOLD:-q90}" --move "${LOOP_MOVE:-q75}" --flight "${LOOP_FLIGHT:-q45}" &
    pids+=("$!")
  done
  local pid
  for pid in "${pids[@]}"; do wait "$pid"; done
  for theme in dark light; do
    # Frame 0 as a still, at the loop's size, for the <picture> fallback and for reduced motion.
    magick "$OUT/loop-$theme/small/f000000.png" -strip "assets/hero/poster-$theme.png"
  done
}

film() {
  pacing
  mkdir -p assets/hero
  local dir="$OUT/film-dark"
  $CAP --cut film --theme dark --fps "$FILM_FPS" --width 1920 --height 1080 --scale "$FILM_SCALE" --workers "$WORKERS" --out "$dir"
  # H.264 High at 4K60 (level 5.2) plays everywhere a browser does; -tune film keeps the grain.
  # Measured round 3 at CRF 20: a flight ~2.2 MB/s, a hold 0.6-0.85 MB/s.
  ffmpeg -y -hide_banner -loglevel error -framerate "$FILM_FPS" -i "$dir/f%06d.png" \
    -vf "format=yuv420p" -c:v libx264 -preset slow -crf "${FILM_CRF:-22}" -tune film \
    -x264-params "keyint=$((FILM_FPS * 2)):bframes=4:ref=5:aq-mode=3" \
    -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
    -movflags +faststart assets/hero/launch-film.mp4
  ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate,nb_frames -show_entries format=duration,size -of default=nw=1 assets/hero/launch-film.mp4
}

seam() {
  for theme in dark light; do
    local frames=("$OUT/loop-$theme"/f*.png)
    local last=${frames[${#frames[@]} - 1]}
    printf '  seam %s: ' "$theme"
    magick compare -metric AE -fuzz 15% "$OUT/loop-$theme/f000000.png" "$last" null: 2>&1 || true
    echo " px differ (frame 0 vs $(basename "$last"))"
  done
}

verify() {
  for theme in dark light; do
    python3 scripts/hero-film-verify.py "assets/hero/hero-$theme.webp" "$OUT/verify-$theme" 0.5 "$OUT/loop-$theme/small"
  done
}

case "${1:-review}" in
  pacing) pacing ;;
  review) review ;;
  loop) loop ;;
  film) film ;;
  seam) seam ;;
  verify) verify ;;
  *) echo "usage: $0 pacing|review|loop|film|seam|verify" >&2; exit 2 ;;
esac
