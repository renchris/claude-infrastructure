#!/usr/bin/env bash
#
# render.sh — the whole pipeline, in the order you should actually run it.
#
#   ./render.sh review              1fps pass -> contact sheets. Look at these FIRST.
#   ./render.sh film                60fps 1080p master
#   FPS=120 ./render.sh film        120fps master
#   RES=4k  ./render.sh film        3840x2160
#   RES=4k FPS=120 ./render.sh film
#
# Reviewing at 1fps costs ~35 frames and a few seconds. Reviewing at 60fps costs
# thousands and several minutes. The defects that matter (blank frames at cuts,
# content clipped by the frame edge, a colour fighting a filter) are all visible
# in a still, so there is no reason to pay the full price to find them. Motion
# hides problems; grids of stills expose them.
#
# Frames are captured LOSSLESS (png). Flat vector content shows JPEG ringing
# around type and banding in the blurs, and h264 then spends bitrate encoding
# those artefacts as if they were signal. One lossy step, at the end, only.

set -euo pipefail
cd "$(dirname "${0}")"

FPS="${FPS:-60}"
RES="${RES:-1080p}"
CRF="${CRF:-16}"

case "${RES}" in
  720p) W=1280; H=720 ;;
  1080p) W=1920; H=1080 ;;
  1440p) W=2560; H=1440 ;;
  4k | 2160p) W=3840; H=2160 ;;
  *)
    echo "RES must be one of: 720p 1080p 1440p 4k" >&2
    exit 2
    ;;
esac

OUT="reso-film-${RES}-${FPS}fps.mp4"

need() {
  command -v "${1}" >/dev/null 2>&1 || {
    echo "missing dependency: ${1}" >&2
    exit 1
  }
}
need node
need ffmpeg

review() {
  echo "==> review pass (1fps)"
  node capture.mjs --review --width "${W}" --height "${H}"
  node contact-sheet.mjs
  echo
  echo "    look at every tile in review/ before paying for the full render."
}

film() {
  echo "==> film pass (${W}x${H} · ${FPS}fps · lossless png)"
  node capture.mjs --fps "${FPS}" --width "${W}" --height "${H}" --format png
  echo "==> encoding"
  # JPEG input would decode as FULL range and silently override -pix_fmt to the
  # deprecated yuvj420p; png is already full-range RGB, so the range conversion
  # is made explicit either way and bt709 is tagged so players agree on levels.
  #
  # yuv444p at CRF<=16 would be better still for flat type, but 420 keeps it
  # universally playable. Raise CRF=12 for an archival master.
  ffmpeg -y -hide_banner -loglevel error \
    -framerate "${FPS}" -i frames/f%06d.png \
    -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2:in_range=full:out_range=tv,format=yuv420p" \
    -c:v libx264 -preset veryslow -crf "${CRF}" -tune animation \
    -x264-params "keyint=${FPS}:min-keyint=${FPS}:bframes=4:ref=5:aq-mode=3" \
    -color_range tv -colorspace bt709 -color_primaries bt709 -color_trc bt709 \
    -movflags +faststart \
    "${OUT}"
  printf '    %s  %s\n' "${OUT}" "$(du -h "${OUT}" | cut -f1)"
}

case "${1:-all}" in
  review) review ;;
  film) film ;;
  all)
    review
    film
    ;;
  *)
    echo "usage: [RES=1080p|4k] [FPS=60|120] ${0} [review|film]" >&2
    exit 2
    ;;
esac
