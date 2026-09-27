#!/bin/bash
# sheet.sh <out.png> t1 t2 ... : render stills and tile them 3 across at 640x360 with time labels
out=$1; shift
node "$(dirname "$0")/render.mjs" stills "$@" >/dev/null 2>/tmp/brag-sheet.err || { cat /tmp/brag-sheet.err; exit 1; }
files=(); for t in "$@"; do files+=("$(dirname "$0")/stills/t-$(printf '%.2f' "$t").png"); done
magick montage "${files[@]}" -tile 3x -geometry 640x360+6+6 -background '#222' -fill white -pointsize 18 -label '%t' "$out" 2>/dev/null || magick montage "${files[@]}" -tile 3x -geometry 640x360+6+6 -background '#222' "$out"
echo "$out"
