#!/usr/bin/env bash
# banner-video.sh — render one animated banner SVG to a seamlessly-looping MP4.
#
#   scripts/banner-video.sh <asset.svg> --period <seconds> [--fps 24] [--width 960]
#                           [--scale 2] [--out <dir>] [--bg dark|light]
#
# The frames come from `banner-shots.sh`, which freezes the asset deterministically at a given
# timestamp, so the movie is a reproducible sampling of the animation rather than a screen capture.
#
# WHY t = period IS EXCLUDED. The asset's t=0 and t=period frames are identical BY CONSTRUCTION —
# that identity is what `banner-verify.sh`'s SEAM check asserts. A player looping a clip that
# contains both paints that image twice in a row at every wrap, so the loop visibly stutters once
# per cycle. The timestamps are therefore k/fps for k in 0 .. fps*period-1; the last frame is one
# frame BEFORE the seam, and the wrap back to frame 0 lands exactly on it.
#
# WHY banner-shots.sh IS CALLED EXACTLY ONCE. It calibrates the headless-viewport inset once per
# process (its `calibrate_inset`) and launches Chromium per frame. A loop of one-frame invocations
# re-measures the inset for every frame and buys nothing.
#
# THE ORDERING TRAP — the reason this script exists rather than a two-line ffmpeg glob.
# banner-shots.sh names each frame after its timestamp with `.` rewritten to `p`:
#   v6c-dusk-line-dark-t0.png  …-t0p0417.png  …-t0p125.png  …-t1p5.png  …-t10p5.png
# Those names DO NOT sort into time order. `t10p5` sorts before `t2`; `t9` sorts after both. A glob
# (`ffmpeg -pattern_type glob -i '*.png'`) or an `ls`-driven list therefore hands the encoder frames
# out of sequence — and nothing fails: it encodes cleanly, it plays, it is simply not the animation.
# A silently-wrong render is the failure mode this whole banner track keeps paying for.
#
# So the order is NEVER read off the filesystem. It is rebuilt from the same `k` loop that produced
# the timestamps: frame k is symlinked to a zero-padded `f%05d.png` in a staging dir, and ffmpeg
# consumes that sequence. Zero-padding is what makes the encoder's own numeric pattern agree with
# lexical order — the padding is doing real work, not cosmetics.
#
# WHY THE GUARDS ARE THE POINT (same reasoning as banner-verify.sh's header: that script once
# reported PASS by comparing two md5s of two files that did not exist). Every frame is asserted to
# exist and be NON-EMPTY before it is encoded, the frame count is asserted to equal fps*period
# exactly, and the encoded stream's own frame count is read back with ffprobe. A missing frame is a
# hard error that names its timestamp — never a quietly shorter video.
#
# Requires: banner-shots.sh's dependencies (playwright Chromium, magick) plus ffmpeg; ffprobe is
# optional and only the read-back check is skipped without it.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SHOTS="$HERE/banner-shots.sh"

die() { printf 'banner-video: %s\n' "$*" >&2; exit 1; }
usage() {
  printf 'usage: banner-video.sh <asset.svg> --period <seconds> [--fps 24] [--width 960]\n' >&2
  printf '                       [--scale 2] [--out <dir>] [--bg dark|light]\n' >&2
  exit 2
}

# Positive-number / positive-integer predicates. awk BEGIN rather than a bash arithmetic test:
# `(( ))` cannot see a decimal, and an unvalidated value reaching awk later would silently read 0.
is_pos_num() { awk -v v="$1" 'BEGIN{ exit !(v ~ /^[0-9]+(\.[0-9]+)?$/ && v+0 > 0) }'; }
is_pos_int() { awk -v v="$1" 'BEGIN{ exit !(v ~ /^[0-9]+$/ && v+0 > 0) }'; }

ASSET=""; PERIOD=""; FPS=24; WIDTH=960; SCALE=2; OUT="./video"; BG="dark"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --period|--fps|--width|--scale|--out|--bg)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      case "$1" in
        --period) PERIOD="$2" ;;
        --fps)    FPS="$2" ;;
        --width)  WIDTH="$2" ;;
        --scale)  SCALE="$2" ;;
        --out)    OUT="$2" ;;
        --bg)     BG="$2" ;;
      esac
      shift 2 ;;
    -h|--help)  usage ;;
    -*)         die "unknown flag $1" ;;
    *)          ASSET="$1"; shift ;;
  esac
done

[[ -n "$ASSET" ]] || usage
[[ -f "$ASSET" ]] || die "asset not found: $ASSET"
[[ -x "$SHOTS" ]] || die "banner-shots.sh not found next to this script (looked at $SHOTS)"
[[ -n "$PERIOD" ]] || die "--period <seconds> is required — the loop length is not inferable from the asset"
is_pos_num "$PERIOD" || die "--period must be a positive number (got '$PERIOD')"
is_pos_int "$FPS"    || die "--fps must be a positive integer (got '$FPS')"
is_pos_int "$WIDTH"  || die "--width must be a positive integer (got '$WIDTH')"
is_pos_int "$SCALE"  || die "--scale must be a positive integer (got '$SCALE')"
[[ "$BG" = "dark" || "$BG" = "light" ]] || die "--bg must be dark or light (got '$BG')"
command -v ffmpeg >/dev/null 2>&1 || die "ffmpeg is not on PATH — cannot encode"

# fps*period must be a whole number of frames. A fractional count would silently truncate, and a
# truncated clip is a loop whose last frame is not adjacent to its first.
NFRAMES=$(awk -v f="$FPS" -v p="$PERIOD" 'BEGIN{
  n = f * p; r = int(n + 0.5)
  if (r < 1 || n - r > 1e-9 || r - n > 1e-9) exit 1
  printf "%d", r
}') || die "--fps ($FPS) x --period ($PERIOD) is not a whole number of frames"

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"; OUT=$(cd "$OUT" && pwd)
STEM=$(basename "$ASSET"); STEM="${STEM%.*}"

# The timestamps, in k order, one per line. %.4f then trailing-zero strip reproduces the shape
# banner-shots.sh tags with (0, 0.0417, 0.125, 1.5) — the filename must be PREDICTABLE, because
# predicting it is what lets the ordering come from k instead of from a glob.
awk -v f="$FPS" -v n="$NFRAMES" 'BEGIN{
  for (k = 0; k < n; k++) {
    s = sprintf("%.4f", k / f)
    sub(/0+$/, "", s); sub(/\.$/, "", s)
    print s
  }
}' > "$WORK/times.txt"

# Two timestamps that round to the same 4-decimal string would collide onto ONE filename: the video
# would be short by a frame and a different frame would appear twice. Assert distinctness.
UNIQ=$(sort -u "$WORK/times.txt" | wc -l | tr -d ' ')
[[ "$UNIQ" -eq "$NFRAMES" ]] || \
  die "timestamps collide at 4-decimal precision ($UNIQ distinct of $NFRAMES) — lower --fps"

TIMES=()
while IFS= read -r _t; do TIMES[${#TIMES[@]}]="$_t"; done < "$WORK/times.txt"
[[ "${#TIMES[@]}" -eq "$NFRAMES" ]] || die "built ${#TIMES[@]} timestamps, expected $NFRAMES"

# ONE invocation, all timestamps (see the header).
#
# The frames land in the WORK dir, not in --out. --out is an asset directory: the first run of this
# script against a 7 s loop at 24 fps left 168 intermediate PNGs sitting in assets/demo/ next to the
# committed media, where the next `git add` sweeps them into the repo. The frames are scaffolding for
# one command; only the mp4 is a deliverable. WORK is a mktemp with a cleanup trap, so they go away
# on their own — including when this script dies partway through.
FRAMES="$WORK/frames"; mkdir -p "$FRAMES"
TIMES_ARG=$(tr '\n' ',' < "$WORK/times.txt" | sed 's/,$//')
printf 'banner-video: rendering %s frames of %s (%ss loop @ %s fps)…\n' \
  "$NFRAMES" "$STEM" "$PERIOD" "$FPS" >&2
if ! "$SHOTS" "$ASSET" --times "$TIMES_ARG" --bg "$BG" --out "$FRAMES" \
       --width "$WIDTH" --scale "$SCALE" > "$WORK/shots.log" 2>&1; then
  cat "$WORK/shots.log" >&2
  die "banner-shots.sh failed — no frames to encode"
fi

# Stage the frames in k order. The symlink name carries the order; the filesystem never decides it.
STAGE="$WORK/seq"; mkdir -p "$STAGE"
K=0
for _t in "${TIMES[@]}"; do
  TAG=$(printf '%s' "$_t" | tr '.' 'p')
  PNG="$FRAMES/${STEM}-${BG}-t${TAG}.png"
  [[ -e "$PNG" ]] || die "missing frame for t=${_t}s — expected $PNG (frame $K of $NFRAMES)"
  [[ -s "$PNG" ]] || die "empty frame for t=${_t}s — $PNG is zero bytes (frame $K of $NFRAMES)"
  ln -s "$PNG" "$(printf '%s/f%05d.png' "$STAGE" "$K")"
  K=$((K + 1))
done

STAGED=$(find "$STAGE" -name 'f*.png' | wc -l | tr -d ' ')
[[ "$STAGED" -eq "$NFRAMES" ]] || die "staged $STAGED frames but expected $NFRAMES — refusing to encode"

MP4="$OUT/${STEM}.mp4"
# yuv420p needs even dimensions and the banner's height is derived from its aspect ratio, so an odd
# height is reachable; the scale filter rounds it down rather than letting libx264 refuse.
ffmpeg -y -loglevel error -framerate "$FPS" -start_number 0 -i "$STAGE/f%05d.png" \
  -vf 'scale=trunc(iw/2)*2:trunc(ih/2)*2' \
  -c:v libx264 -pix_fmt yuv420p -crf 20 -movflags +faststart -an "$MP4"

[[ -e "$MP4" ]] || die "ffmpeg exited 0 but produced no file at $MP4"
[[ -s "$MP4" ]] || die "ffmpeg produced a zero-byte file at $MP4"

if command -v ffprobe >/dev/null 2>&1; then
  GOT=$(ffprobe -v error -count_frames -select_streams v:0 \
        -show_entries stream=nb_read_frames -of csv=p=0 "$MP4" 2>/dev/null | tr -d '\r, ' | head -1)
  # An unreadable count is a NON-VERDICT, not a pass — the whole point of the check is that a short
  # video is indistinguishable from a correct one by eye.
  [[ -n "$GOT" ]] || die "ffprobe could not read a frame count from $MP4"
  case "$GOT" in
    ''|*[!0-9]*) die "ffprobe returned a non-numeric frame count ('$GOT') for $MP4" ;;
  esac
  [[ "$GOT" -eq "$NFRAMES" ]] || die "encoded $GOT frames but expected $NFRAMES — the clip is wrong"
else
  printf 'banner-video: ffprobe not on PATH — SKIPPING the encoded-frame-count check\n' >&2
fi

BYTES=$(wc -c < "$MP4" | tr -d ' ')
printf '%s\n' "$MP4"
printf 'banner-video: %s frames @ %s fps · %ss loop · %s bytes\n' "$NFRAMES" "$FPS" "$PERIOD" "$BYTES"
