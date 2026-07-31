#!/usr/bin/env bash
# banner-timeline-anchor.sh — does an SVG-as-image CSS timeline start at LOAD, or at a shared epoch?
#
# This decides whether the opening seconds of the loop are the product. If the timeline anchors at
# load, every reader who scrolls past the README sees t=0 and the first few seconds are what the
# banner IS; a beat placed at t=231s is effectively unseen. If it anchors to some shared clock,
# readers arrive at arbitrary phase and placement within the loop hardly matters.
#
# METHOD — and the first version of this test was WRONG in a way worth recording.
#
#   Naive: render the unfrozen asset twice, GAP seconds apart, and compare. If they differ,
#   conclude "not load-anchored".
#
#   That is not decisive. A load-anchored timeline ALSO produces two different renders, because the
#   screenshot fires at a slightly variable delay after load and this asset has a 0.5s stepped
#   stride — 250 ms of jitter flips the legs. "Differs" cannot separate jitter from drift, so the
#   naive test reports a refutation on evidence that is equally consistent with confirmation.
#
#   Decisive: measure WHICH PHASE each render is at, by matching it against frozen reference frames
#   and taking the best RMSE. Load-anchored means both renders match t≈0 however long you wait.
#   Epoch-anchored means the second matches t≈GAP.
#
# Measured 2026-07-29 (Chromium 141, v6a-long-night, GAP=25s):
#   raw-first  -> best match t=0 (RMSE 0.000%)
#   raw-second -> best match t=0 (RMSE 0.189%), and NOT t=25
#   => anchors at load. Every reader starts at t=0.
#
# The 0.000% on the first render is also an independent validation of the freeze itself: the frozen
# t=0 frame is pixel-exact against a live render of the unmodified file.
#
#   scripts/banner-timeline-anchor.sh assets/banner/v6a-long-night.svg [--gap 25]

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ASSET="${1:-}"; shift || true
GAP=25
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gap) GAP="$2"; shift 2 ;;
    *) echo "banner-timeline-anchor: unknown flag $1" >&2; exit 2 ;;
  esac
done
[[ -n "$ASSET" && -f "$ASSET" ]] || { echo "banner-timeline-anchor: asset not found: ${ASSET:-<none>}" >&2; exit 2; }
ASSET=$(cd "$(dirname "$ASSET")" && pwd)/$(basename "$ASSET")

# Prefers chrome-headless-shell — the full Chromium.app bundle paints a Dock tile on every
# launch (see resolve_headless_chrome in lib/cc-common.sh for the measurements).
_ccl="$(cd "$(dirname "$0")" 2>/dev/null && pwd)/lib/cc-common.sh"
[[ -f "$_ccl" ]] || _ccl="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cc-common.sh"
[[ -f "$_ccl" ]] || _ccl="$HOME/.claude/scripts/lib/cc-common.sh"
# shellcheck source=lib/cc-common.sh
# shellcheck disable=SC1091  # runtime-resolved source; the ship gate runs shellcheck without -x
if ! . "$_ccl" 2>/dev/null; then
  echo "banner-timeline-anchor: FATAL — cannot source $_ccl" >&2
  exit 1
fi
CHROME="$(resolve_headless_chrome "${BANNER_CHROME:-}")"
[[ -x "$CHROME" ]] || { echo "banner-timeline-anchor: no playwright Chromium found" >&2; exit 1; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/p.html" <<HTML
<!doctype html><meta charset="utf-8">
<style>html,body{margin:0;background:#0d1117}img{width:900px;display:block}</style>
<img src="file://$ASSET" width="900">
HTML

shoot() {
  "$CHROME" --headless --disable-gpu --hide-scrollbars --no-sandbox \
    --window-size=900,281 --force-device-scale-factor=1 \
    --blink-settings=preferredColorScheme=0 --screenshot="$1" "file://$WORK/p.html" >/dev/null 2>&1
}

echo "banner-timeline-anchor: $(basename "$ASSET"), gap ${GAP}s"
shoot "$WORK/raw-first.png"
sleep "$GAP"
shoot "$WORK/raw-second.png"

# frozen references bracketing BOTH hypotheses: t≈0 and t≈GAP
TIMES="0,0.5,1,2,3,$(python3 -c "print(max(0,$GAP-1))"),$GAP,$(python3 -c "print($GAP+1)")"
"$HERE/banner-shots.sh" "$ASSET" --times "$TIMES" --bg dark --scheme dark --scale 1 \
  --out "$WORK/ref" >/dev/null 2>&1

python3 - "$WORK" "$GAP" <<'PY'
import glob, os, re, subprocess, sys
work, gap = sys.argv[1], float(sys.argv[2])

def rmse(a, b):
    r = subprocess.run(["magick", "compare", "-metric", "RMSE", a, b, "null:"],
                       capture_output=True, text=True)
    t = (r.stderr or r.stdout).strip()
    try:
        return float(t.split("(")[1].split(")")[0]) * 100
    except Exception:
        return None

refs = []
for f in glob.glob(os.path.join(work, "ref", "*.png")):
    m = re.search(r"-t([\dp.]+)\.png$", f)
    if m:
        refs.append((float(m.group(1).replace("p", ".")), f))
if not refs:
    sys.exit("banner-timeline-anchor: NOT PROVEN — no reference frames rendered")

best = {}
for tag in ("raw-first", "raw-second"):
    p = os.path.join(work, tag + ".png")
    if not (os.path.isfile(p) and os.path.getsize(p)):
        sys.exit(f"banner-timeline-anchor: NOT PROVEN — {tag} render missing or empty")
    scored = sorted(((rmse(p, f), t) for t, f in refs), key=lambda x: (x[0] is None, x[0]))
    best[tag] = scored[0]
    print(f"  {tag:11s} best match t={scored[0][1]:<6g}s (RMSE {scored[0][0]:.3f}%)")

# a control: the two bracketing references must themselves be distinguishable, or nothing is
t0 = min(refs, key=lambda r: r[0])[1]
tg = min(refs, key=lambda r: abs(r[0] - gap))[1]
sep = rmse(t0, tg)
if sep is None or sep < 0.5:
    sys.exit(f"banner-timeline-anchor: CONTROL FAILED — frozen t=0 and t={gap:g} differ by only "
             f"{sep}%, so {gap:g}s of motion is not detectable and the result is meaningless")
print(f"  control: frozen t=0 vs t={gap:g} differ by {sep:.2f}% — {gap:g}s of motion IS detectable")

second_t = best["raw-second"][1]
if second_t <= 3:
    print(f"  RESULT: after {gap:g}s of wall clock the render is STILL at t≈{second_t:g}")
    print("  => the timeline ANCHORS AT LOAD. Every reader starts at t=0, so the opening seconds")
    print("     are the product and a beat late in the loop is effectively unseen.")
elif abs(second_t - gap) <= 3:
    print(f"  RESULT: after {gap:g}s the render is at t≈{second_t:g}")
    print("  => the timeline tracks a SHARED CLOCK. Readers arrive at arbitrary phase.")
else:
    print(f"  RESULT: INCONCLUSIVE — best match t≈{second_t:g} fits neither t≈0 nor t≈{gap:g}")
    sys.exit(1)
PY
