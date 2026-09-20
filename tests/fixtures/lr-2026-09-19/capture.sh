#!/bin/bash
# capture.sh — freeze the LIVE limit-recover stores into a self-consistent cc-limited fixture.
#
# WHY THIS EXISTS (LIMIT_DETECT_100P § 11 #1, the one FATAL critic gap, 92 %).
# The drill in § 5 asserted registry row `147.json` for sid 07e30aeb. The plan's OWN § 10 receipts
# say, verbatim: "NO row for 147, 09e64dcb, 98f02458, 4bc1159f, 07e30aeb". Both cannot be true, and
# the sibling generator build.sh resolved it by HAND-WRITING the disputed row. Amendment #1's ruling
# is that fixtures are never hand-asserted: they are CAPTURED from the live stores, they ship a
# receipt, and the expected states are RE-DERIVED from the capture rather than quoted from a prior
# moment. This script is that capture.
#
# THE DESIGN POINT, and it is the whole reason this cannot drift: the expected screen is not written
# by a human and not copied from § 5. It is PRODUCED by running the census against the snapshot at
# capture time and saved as a golden. The fixture and its expectation are therefore true of the same
# instant by construction — the failure mode amendment #1 names is unreachable here.
#
# SAFETY. Read-only on every live store. Writes only under <outdir>. Transcripts are TAIL-BOUNDED
# (LR_TAIL_BYTES, default 128 KiB) because the census only ever reads a tail, and a whole transcript
# is both large and full of conversation nobody needs. The default outdir is OUTSIDE the repo for
# that reason — captured transcript tails are operator content; commit a capture only after reading
# what is in it.
#
# Usage:  capture.sh [outdir]        default: /tmp/lr-capture-<UTC>
#         then:  . <outdir>/env.sh && cc-limited
set -uo pipefail

OUT="${1:-/tmp/lr-capture-$(date -u +%Y%m%dT%H%M%SZ)}"
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
CCL="${CC_LIMITED_BIN:-$REPO/bin/cc-limited}"
TAILB="${LR_TAIL_BYTES:-131072}"

SRC_MARKER="${CC_LIMITED_MARKER_DIR:-$HOME/.claude/autonomy/stop-failure}"
SRC_REG="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
SRC_STATE="${LR_STATE_DIR:-$HOME/.reso/limit-recover}"
SRC_ACCT="${CC_LIMITED_ACCOUNTS:-$HOME/.claude/accounts.json}"
SRC_IDL="${CC_LIMITED_IDL:-$HOME/.claude/autonomy/idl.jsonl}"
SRC_BEATS="$HOME/.claude/cc-beats"

[ -x "$CCL" ] || { echo "capture: no cc-limited at $CCL" >&2; exit 1; }
mkdir -p "$OUT"/{home/.claude/autonomy/stop-failure,home/.claude/cc-registry,home/.claude/cc-beats,state,proj} || exit 1
H="$OUT/home"

# ── the pinned instant. Everything downstream is relative to THIS, never to the wall clock. ──────
NOW_EPOCH="$(date -u +%s)"
NOW_ISO="$(date -u -r "$NOW_EPOCH" +%Y-%m-%dT%H:%M:%SZ)"

echo "== capturing at $NOW_ISO -> $OUT"

# ── 1. markers ───────────────────────────────────────────────────────────────────────────────────
n_marker=0
if [ -d "$SRC_MARKER" ]; then
  for f in "$SRC_MARKER"/*.jsonl; do
    [ -f "$f" ] || continue
    cp -p "$f" "$H/.claude/autonomy/stop-failure/" 2>/dev/null && n_marker=$((n_marker+1))
  done
fi

# ── 2. registry ──────────────────────────────────────────────────────────────────────────────────
n_reg=0
if [ -d "$SRC_REG" ]; then
  for f in "$SRC_REG"/*.json; do
    [ -f "$f" ] || continue
    cp -p "$f" "$H/.claude/cc-registry/" 2>/dev/null && n_reg=$((n_reg+1))
  done
fi

# ── 3. beats — the SECOND liveness source (amendment #2); a registry-only capture reproduces the
#      completeness bug P5 refuted, so a capture that omits beats is not a capture. ──────────────
n_beat=0
if [ -d "$SRC_BEATS" ]; then
  for f in "$SRC_BEATS"/*.json; do
    [ -f "$f" ] || continue
    cp -p "$f" "$H/.claude/cc-beats/" 2>/dev/null && n_beat=$((n_beat+1))
  done
fi

# ── 4. the limit-recover state dir: locks / parked / results / requests / faults ──────────────────
for sub in locks parked results requests faults fleet; do
  [ -d "$SRC_STATE/$sub" ] || continue
  mkdir -p "$OUT/state/$sub"
  cp -Rp "$SRC_STATE/$sub/." "$OUT/state/$sub/" 2>/dev/null
done

# ── 5. accounts + an IDL TAIL (the full file is ~20k rows and the census only reads a window) ────
[ -f "$SRC_ACCT" ] && cp -p "$SRC_ACCT" "$H/.claude/accounts.json" 2>/dev/null
mkdir -p "$H/.claude/autonomy"
[ -f "$SRC_IDL" ] && tail -c "$TAILB" "$SRC_IDL" > "$H/.claude/autonomy/idl.jsonl" 2>/dev/null

# ── 6. the ps table, pinned. (pid,lstart) is the reaper's own identity pin; TZ/LC are pinned too
#      because an unpinned lstart convicts every row on a DST flip. ──────────────────────────────
TZ=UTC LC_ALL=C ps -eo pid=,lstart= > "$OUT/ps.txt" 2>/dev/null

# ── 7. transcript TAILS for every sid the markers name ───────────────────────────────────────────
sids="$(cat "$H"/.claude/autonomy/stop-failure/*.jsonl 2>/dev/null \
        | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([0-9a-f-]\{8,\}\)".*/\1/p' | sort -u)"
n_tx=0
for sid in $sids; do
  for f in "$HOME"/.claude*/projects/*/"$sid"*.jsonl; do
    [ -f "$f" ] || continue
    root="$(printf '%s' "$f" | sed -n 's#.*/\(\.claude[^/]*\)/projects/\([^/]*\)/.*#\1__\2#p')"
    mkdir -p "$OUT/proj/$root"
    tail -c "$TAILB" "$f" > "$OUT/proj/$root/$(basename "$f")" 2>/dev/null && n_tx=$((n_tx+1))
  done
done

# ── 8. env.sh — the seams, so the capture is replayable with one `source` ────────────────────────
cat > "$OUT/env.sh" <<ENV
# generated by capture.sh at $NOW_ISO — source this, then run cc-limited
export CC_LIMITED_MARKER_DIR="$H/.claude/autonomy/stop-failure"
export CC_REGISTRY_DIR="$H/.claude/cc-registry"
export LR_STATE_DIR="$OUT/state"
export CC_LIMITED_ACCOUNTS="$H/.claude/accounts.json"
export CC_LIMITED_IDL="$H/.claude/autonomy/idl.jsonl"
export CC_LIMITED_PS="$OUT/ps.txt"
export CC_LIMITED_ROOTS="$OUT/proj"
export LR_NOW="$NOW_ISO"
export CC_LIMITED_CLAIM_GRACE_S="\${CC_LIMITED_CLAIM_GRACE_S:-120}"
ENV

# ── 9. DERIVE the expectation. Not quoted from § 5, not written by hand: produced by the subject
#      against this snapshot, at this instant. This is what amendment #1 actually asks for. ──────
# env.sh is GENERATED above, so there is nothing to follow. The ship gate runs the linter WITHOUT
# -x (plan § 4), under which a bare `.` of a non-constant path raises SC1091 and reddens the land;
# source=/dev/null is the directive meaning "intentionally unfollowable".
# NOTE: no prose line here may begin with the linter's own name — any such comment is parsed as a
# DIRECTIVE, and a malformed one is SC1073/SC1072, i.e. an ERROR where the original was an info.
# shellcheck source=/dev/null
( . "$OUT/env.sh"; "$CCL" )        > "$OUT/EXPECTED.screen" 2>"$OUT/EXPECTED.screen.err"; scr_rc=$?
# shellcheck source=/dev/null
( . "$OUT/env.sh"; "$CCL" --tsv )  > "$OUT/EXPECTED.tsv"    2>/dev/null; tsv_rc=$?

# ── 10. the receipt ──────────────────────────────────────────────────────────────────────────────
{
  echo "# CAPTURE-RECEIPT — cc-limited fixture"
  echo
  echo "Captured **$NOW_ISO** (epoch $NOW_EPOCH) by \`tests/fixtures/lr-2026-09-19/capture.sh\`."
  echo "Pinned instant \`LR_NOW=$NOW_ISO\`; every age, reset countdown and claim age below is"
  echo "relative to it, never to a wall clock."
  echo
  echo "## What was copied, and from where"
  echo
  echo '| store | source | items |'
  echo '|---|---|---|'
  echo "| markers | \`$SRC_MARKER\` | $n_marker file(s) |"
  echo "| registry | \`$SRC_REG\` | $n_reg row(s) |"
  echo "| beats | \`$SRC_BEATS\` | $n_beat file(s) |"
  echo "| state (locks/parked/results/requests/faults/fleet) | \`$SRC_STATE\` | see listing |"
  echo "| accounts | \`$SRC_ACCT\` | $( [ -f "$H/.claude/accounts.json" ] && echo present || echo ABSENT ) |"
  echo "| idl (tail ${TAILB}B) | \`$SRC_IDL\` | $( [ -s "$H/.claude/autonomy/idl.jsonl" ] && echo present || echo ABSENT ) |"
  echo "| transcript tails (${TAILB}B each) | \`\$HOME/.claude*/projects\` | $n_tx copy/copies |"
  echo "| ps table | \`TZ=UTC LC_ALL=C ps -eo pid=,lstart=\` | $(wc -l < "$OUT/ps.txt" | tr -d ' ') row(s) |"
  echo
  echo "## Registry rows actually present AT CAPTURE"
  echo
  echo 'This is the list amendment #1 exists to make checkable. Any drill row asserting a registry'
  echo 'pane NOT in this list is hand-asserted and must be re-derived.'
  echo
  echo '```'
  find "$H/.claude/cc-registry" -maxdepth 1 -name '*.json' -exec basename {} .json \; 2>/dev/null \
    | sort | tr '\n' ' ' | fold -w 100
  echo
  echo '```'
  echo
  echo "## Sids the markers name"
  echo
  echo '```'
  printf '%s\n' "$sids" | head -40    # already newline-separated by sort -u; quoting is the correct form
  echo '```'
  echo
  echo "## The DERIVED expectation"
  echo
  echo "\`EXPECTED.screen\` (exit $scr_rc) and \`EXPECTED.tsv\` (exit $tsv_rc) were produced by running"
  echo "the census against THIS snapshot at THIS instant. They are goldens, not assertions: a drill"
  echo "re-runs the census over the same capture and diffs. Nothing here is quoted from § 5."
  echo
  echo '```'
  head -40 "$OUT/EXPECTED.screen" 2>/dev/null
  echo '```'
} > "$OUT/CAPTURE-RECEIPT.md"

echo "== captured: markers=$n_marker registry=$n_reg beats=$n_beat transcripts=$n_tx"
echo "== expectation derived: EXPECTED.screen (exit $scr_rc), EXPECTED.tsv (exit $tsv_rc)"
echo "== receipt: $OUT/CAPTURE-RECEIPT.md"
echo "== replay:  . $OUT/env.sh && $CCL"
