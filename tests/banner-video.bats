#!/usr/bin/env bats
# banner-video.bats — the frame-ORDER contract, which is the only thing about this script that can
# be wrong without anything failing.
#
# WHY: banner-shots.sh names frames after their timestamp with `.` → `p`, and those names do not
# sort into time order (`t10p5` < `t2` < `t9` lexically). A glob-driven encode therefore produces a
# clean, playable mp4 that is simply not the animation. Test 2 is the regression test for exactly
# that: it drives a case where lexical and numeric order genuinely disagree and asserts the encoder
# saw the NUMERIC one.
#
# HERMETIC: the script under test is copied into a temp `scripts/` dir next to a STUB
# banner-shots.sh, so the script's own `dirname "$BASH_SOURCE"` resolution picks the stub up — no
# bypass env var, and no browser is ever launched. ffmpeg/ffprobe are stubbed on PATH.
#
# BATS ERREXIT: a non-final bare `[[ ]]`/`(( ))` is errexit-EXEMPT and therefore a DEAD assertion —
# every non-final assertion below is `|| false` or a live final `[ ]`.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"

  # the script under test, beside a stub banner-shots.sh
  mkdir -p "$D/scripts" "$D/bin" "$D/asset" "$D/out"
  cp "$REPO/scripts/banner-video.sh" "$D/scripts/banner-video.sh"
  VID="$D/scripts/banner-video.sh"
  ASSET="$D/asset/demo.svg"
  printf '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="4"></svg>\n' > "$ASSET"

  # observation points the stubs write to
  export SHOTS_TIMES="$D/shots-times.txt"   # the raw --times argument, one line per invocation
  export SHOTS_SKIP=""                      # a timestamp the stub refuses to emit
  export SHOTS_EMPTY=""                     # a timestamp the stub emits as a ZERO-BYTE file
  export ENCODE_ORDER="$D/encode-order.txt" # frame basenames in the order ffmpeg consumed them
  export ENCODE_COUNT="$D/encode-count.txt"
  export FFPROBE_FRAMES=""                  # override the frame count ffprobe reports

  cat > "$D/scripts/banner-shots.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
times=""; out="."; bg="dark"; asset=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --times) times="$2"; shift 2 ;;
    --out)   out="$2";   shift 2 ;;
    --bg)    bg="$2";    shift 2 ;;
    --width|--scale|--scheme) shift 2 ;;
    -*)      shift ;;
    *)       asset="$1"; shift ;;
  esac
done
printf '%s\n' "$times" >> "$SHOTS_TIMES"
stem=$(basename "$asset"); stem="${stem%.*}"
mkdir -p "$out"
IFS=',' read -r -a ts <<< "$times"
for t in "${ts[@]}"; do
  tag=$(printf '%s' "$t" | tr '.' 'p')
  f="$out/${stem}-${bg}-t${tag}.png"
  if [[ "$t" = "${SHOTS_SKIP:-}" ]]; then
    continue
  elif [[ "$t" = "${SHOTS_EMPTY:-}" ]]; then
    : > "$f"
  else
    printf 'PNG-%s\n' "$tag" > "$f"
  fi
  printf '%s\n' "$f"
done
SH
  chmod +x "$D/scripts/banner-shots.sh"

  # ffmpeg stub: resolve the staged f%05d.png sequence back to the frames it points at, in the
  # sequence's own order — that resolved list IS what the encoder would have seen.
  cat > "$D/bin/ffmpeg" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
pattern=""; prev=""; outfile=""
for a in "$@"; do
  if [[ "$prev" = "-i" ]]; then pattern="$a"; fi
  prev="$a"; outfile="$a"
done
: > "$ENCODE_ORDER"
n=0
if [[ -n "$pattern" ]]; then
  for f in "$(dirname "$pattern")"/f*.png; do
    [[ -e "$f" ]] || continue
    tgt=$(readlink "$f" 2>/dev/null || printf '%s' "$f")
    printf '%s\n' "$(basename "$tgt")" >> "$ENCODE_ORDER"
    n=$((n + 1))
  done
fi
printf '%s' "$n" > "$ENCODE_COUNT"
printf 'fake-mp4-bytes\n' > "$outfile"
SH
  chmod +x "$D/bin/ffmpeg"

  cat > "$D/bin/ffprobe" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${FFPROBE_FRAMES:-}" ]]; then printf '%s\n' "$FFPROBE_FRAMES"; exit 0; fi
cat "$ENCODE_COUNT" 2>/dev/null || printf '0'
printf '\n'
SH
  chmod +x "$D/bin/ffprobe"

  export PATH="$D/bin:$PATH"
}

@test "frame list excludes t=period and holds exactly fps*period entries" {
  run /bin/bash "$VID" "$ASSET" --period 2 --fps 8 --out "$D/out"
  [ "$status" -eq 0 ]
  # ONE invocation of banner-shots.sh — it calibrates the viewport inset once per process.
  [ "$(wc -l < "$SHOTS_TIMES" | tr -d ' ')" = "1" ]
  times=$(cat "$SHOTS_TIMES")
  # printf '%s\n', not '%s': `wc -l` counts NEWLINES, so a newline-less stream reports one short
  # and the count assertion would be off by exactly the last frame — the one that matters here.
  [ "$(printf '%s\n' "$times" | tr ',' '\n' | wc -l | tr -d ' ')" = "16" ]
  [ "$(printf '%s' "$times" | cut -d, -f1)" = "0" ]
  [ "$(printf '%s\n' "$times" | tr ',' '\n' | tail -1)" = "1.875" ]
  # t=period must NOT appear — it is byte-identical to t=0 and would stutter the loop.
  [ "$(printf '%s\n' "$times" | tr ',' '\n' | grep -c '^2$' || true)" = "0" ]
}

@test "frames reach the encoder in NUMERIC time order, not lexical (the ordering trap)" {
  # fps 1 / period 12 makes the two orders genuinely disagree: lexically t10 < t2 < t9.
  run /bin/bash "$VID" "$ASSET" --period 12 --fps 1 --out "$D/out"
  [ "$status" -eq 0 ]
  numeric=""
  for k in 0 1 2 3 4 5 6 7 8 9 10 11; do numeric="${numeric}demo-dark-t${k}.png"$'\n'; done
  [ "$(cat "$ENCODE_ORDER")" = "$(printf '%s' "$numeric")" ]
  # and prove the assertion above is not vacuous: lexical order really is different here.
  lexical=$(printf '%s' "$numeric" | sort)
  [ "$(cat "$ENCODE_ORDER")" != "$lexical" ]
  # the third frame is t2, which lexical order would have made t10
  [ "$(sed -n '3p' "$ENCODE_ORDER")" = "demo-dark-t2.png" ]
}

@test "a missing frame is a hard error naming its timestamp" {
  export SHOTS_SKIP="0.5"
  run /bin/bash "$VID" "$ASSET" --period 2 --fps 8 --out "$D/out"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 't=0.5s' || false
  # never a silently shorter video
  [ ! -e "$D/out/demo.mp4" ]
}

@test "a zero-byte frame is a hard error naming its timestamp" {
  # A present-but-empty PNG is the harder case: `-e` passes and only `-s` catches it. Encoding it
  # would either abort deep inside ffmpeg or drop a frame silently.
  export SHOTS_EMPTY="0.25"
  run /bin/bash "$VID" "$ASSET" --period 1 --fps 4 --out "$D/out"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 't=0.25s' || false
  printf '%s' "$output" | grep -q 'zero bytes' || false
  [ ! -e "$D/out/demo.mp4" ]
}

@test "an encoded frame-count mismatch is a hard error" {
  export FFPROBE_FRAMES="15"
  run /bin/bash "$VID" "$ASSET" --period 2 --fps 8 --out "$D/out"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'encoded 15 frames but expected 16' || false
}

@test "refuses a missing asset, a missing/non-positive --period, and a fractional frame count" {
  run /bin/bash "$VID" "$D/asset/nope.svg" --period 2 --out "$D/out"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'asset not found' || false

  run /bin/bash "$VID" "$ASSET" --out "$D/out"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q -- '--period' || false

  run /bin/bash "$VID" "$ASSET" --period 0 --out "$D/out"
  [ "$status" -ne 0 ]

  run /bin/bash "$VID" "$ASSET" --period 0.7 --fps 3 --out "$D/out"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'whole number of frames' || false
}
