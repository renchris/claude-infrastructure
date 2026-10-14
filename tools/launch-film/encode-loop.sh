#!/usr/bin/env bash
# encode-loop.sh: encode the README hero loop (assets/hero/hero.webp) from the launch film's master.
#
#   bash tools/launch-film/encode-loop.sh MASTER.mp4 OUT.webp [WIDTH] [QUALITY]
#
# Every frame of the master becomes one stored frame: no frame is dropped, merged or re-timed, so the
# loop runs at the master's 60 fps for its whole length. Each frame is stored whole and lossy. Animated
# WebP has no motion compensation, and in this film the camera, the sea or the fur moves on every
# frame, so there is no still rectangle to save; storing whole frames also means no stale patch can
# build up (the drift scripts/hero-film-encode-loop.py documents for changed-rectangle encodes).
#
# WebP frame durations are whole milliseconds, so 60 fps is stored as 17, 17, 16 ms repeating: 50 ms
# for every three frames, exact over the film.
#
# The levers, measured on this film (every 15th frame, scaled to the full 1,755): bytes follow pixel
# count first and quality second. 1676 px wide is 59 MB at q30, 1257 px 42 MB, 1048 px 25 MB at q20,
# 838 px 19 MB at q20. The shipped loop is 1048 px (1.25x the README's 838 CSS px column) at q20.
set -euo pipefail

src="${1:?usage: encode-loop.sh MASTER.mp4 OUT.webp [WIDTH] [QUALITY]}"
out="${2:?usage: encode-loop.sh MASTER.mp4 OUT.webp [WIDTH] [QUALITY]}"
width="${3:-1048}"
quality="${4:-20}"
jobs="${ENCODE_JOBS:-4}"

for tool in ffmpeg ffprobe cwebp webpmux; do
  command -v "$tool" >/dev/null || { echo "encode-loop: $tool not found" >&2; exit 1; }
done

work="$(mktemp -d "${TMPDIR:-/tmp}/launch-film-loop.XXXXXX")"
mkdir -p "$work/png" "$work/webp"

IFS=x read -r src_w src_h < <(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0:s=x "$src")
height=$(( (width * src_h + src_w / 2) / src_w ))
expected="$(ffprobe -v error -select_streams v:0 -count_packets -show_entries stream=nb_read_packets -of csv=p=0 "$src")"

# passthrough: one PNG per decoded frame, never a duplicate or a drop to fit a rate.
ffmpeg -v error -i "$src" -an -fps_mode passthrough "$work/png/f%06d.png"
count="$(find "$work/png" -name 'f*.png' | wc -l | tr -d ' ')"
[ "$count" = "$expected" ] || { echo "encode-loop: extracted $count frames, master has $expected" >&2; exit 1; }

# shellcheck disable=SC2016  # the positional parameters belong to the inner sh, not this shell
find "$work/png" -name 'f*.png' -print0 | xargs -0 -P "$jobs" -I{} sh -c \
  'cwebp -quiet -q "$1" -m 6 -sns 70 -resize "$2" "$3" "$4" -o "$5/$(basename "$4" .png).webp"' \
  _ "$quality" "$width" "$height" {} "$work/webp"

args=()
i=0
while IFS= read -r frame; do
  if [ $(( i % 3 )) -eq 2 ]; then ms=16; else ms=17; fi
  args+=(-frame "$frame" "+${ms}+0+0+0-b")
  i=$(( i + 1 ))
done < <(find "$work/webp" -name 'f*.webp' | sort)
[ "$i" = "$expected" ] || { echo "encode-loop: encoded $i frames, master has $expected" >&2; exit 1; }

webpmux "${args[@]}" -loop 0 -bgcolor 255,255,255,255 -o "$out"
rm -r "$work/png" "$work/webp"
rmdir "$work"

echo "encode-loop: $out ${width}x${height} q${quality} frames=$i bytes=$(wc -c < "$out" | tr -d ' ')"
