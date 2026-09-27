#!/bin/bash
# finish.sh <poster-seconds>: poster + final encode.
#   out/frames.mkv (lossless RGB) + out/mix.wav -> ../brag.mp4, with the poster frame baked in as frame 0
#   (replaced, not added: the frame count and the audio sync are unchanged), and ../brag.jpg.
set -euo pipefail
cd "$(dirname "$0")"
T=${1:?poster time in seconds}
FPS=30
N=$(python3 -c "print(round($T*$FPS))")

# the poster: exactly frame N of the lossless render
ffmpeg -hide_banner -loglevel error -y -i out/frames.mkv -vf "select=eq(n\,$N)" -frames:v 1 out/poster.png
ffmpeg -hide_banner -loglevel error -y -i out/poster.png -q:v 2 ../brag.jpg

# the video: RGB -> BT.709 limited-range 4:2:0 once, frame 0 replaced by the poster
# v2: CRF 22 + tune grain. v2's film grain made CRF 14 cost 74 MB (v1: 10 MB); measured 21/8/4 MB at CRF 20/23/26 with SSIM
# flat at 0.977, and CRF 23 against the lossless render showed crisp type and no banding in the darkest gradient.
ffmpeg -hide_banner -loglevel error -y \
  -i out/frames.mkv -loop 1 -framerate $FPS -i out/poster.png -i out/mix.wav \
  -filter_complex "[0:v][1:v]overlay=shortest=1:enable='eq(n\,0)',scale=out_color_matrix=bt709:out_range=tv:flags=lanczos+accurate_rnd+full_chroma_int,format=yuv420p[v]" \
  -map "[v]" -map 2:a \
  -c:v libx264 -preset slow -crf 22 -tune grain -profile:v high -level 4.2 -g 60 -keyint_min 30 -bf 2 \
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv \
  -c:a aac -b:a 256k -ar 48000 -ac 2 \
  -movflags +faststart -shortest ../brag.mp4

ffprobe -v error -show_entries format=duration,size:stream=codec_name,width,height,r_frame_rate,nb_frames,pix_fmt,color_space,sample_rate,channels -of compact ../brag.mp4
