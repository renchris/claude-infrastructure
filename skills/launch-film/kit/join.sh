#!/bin/bash
# join.sh <N>: out/frames.mkv = frames 0..N-1 of out/frames-a.mkv + all of out/frames-b.mkv (rendered with --from N/30).
# Needed once: the first full render lost its Chrome renderer after frame 498 and hung. FFV1 is all-intra (-g 1), so the
# cut and the join are stream copies: no frame is re-encoded. Checks the seam (A's frame N vs B's frame 0 must match, since
# every frame is a pure function of t) and the total count (675).
set -euo pipefail
cd "$(dirname "$0")/out"
N=${1:?first frame of part B}
ffmpeg -hide_banner -loglevel error -y -i frames-a.mkv -map 0:v -frames:v "$N" -c copy a-cut.mkv
ffmpeg -hide_banner -loglevel error -y -i frames-a.mkv -vf "select=eq(n\,$N)" -frames:v 1 seam-a.png
ffmpeg -hide_banner -loglevel error -y -i frames-b.mkv -frames:v 1 seam-b.png
echo "seam: A frame $N vs B frame 0: PSNR $(ffmpeg -hide_banner -i seam-a.png -i seam-b.png -lavfi psnr -f null - 2>&1 | grep -o 'average:[^ ]*')"
printf "file 'a-cut.mkv'\nfile 'frames-b.mkv'\n" > join.txt
ffmpeg -hide_banner -loglevel error -y -f concat -safe 0 -i join.txt -c copy frames.mkv
ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames,r_frame_rate,width,height -of compact frames.mkv
rm -f a-cut.mkv join.txt
