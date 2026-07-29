#!/usr/bin/env bash
# banner-verify.sh — the full acceptance gate for one animated banner asset.
#
# Five checks, each of which can actually FAIL:
#
#   1. LINT      one animation per element, so `banner-shots.sh`'s deterministic freeze is exact.
#   2. SEAM      t=0 and t=P render byte-identically ⇒ the loop has no visible restart.
#   3. ALIVE     N frames sampled across a short window are all DISTINCT ⇒ it is not a still.
#   4. THEMES    dark / light / none(base-stylesheet) all render ⇒ both readers get a real look.
#   5. STILL     prefers-reduced-motion renders ⇒ the frozen fallback exists.
#
# WHY THE GUARDS ARE THE POINT. The obvious spelling of check 2 is
#     [[ "$(md5 -q a.png)" == "$(md5 -q b.png)" ]] && echo PASS
# and when neither file exists that compares "" to "" and prints PASS. That false pass really
# happened on this track. So every hash here is asserted non-empty and every file asserted
# non-empty BEFORE it is compared, and the aliveness check additionally requires the expected
# number of frames — a harness that renders 1 of 12 frames must not report "all distinct".
#
#   scripts/banner-verify.sh assets/banner/v6a-long-night.svg
#   scripts/banner-verify.sh assets/banner/v6a-long-night.svg --period 240 --keep /tmp/out
#   scripts/banner-verify.sh --self-test        # proves the guards fail when they should
#
# Exit 0 = every check passed. Non-zero = at least one failed; the summary names which.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SHOTS="$HERE/banner-shots.sh"

ASSET=""; PERIOD=240; KEEP=""; ALIVE_N=12; ALIVE_SPAN=31
while [[ $# -gt 0 ]]; do
  case "$1" in
    --period)    PERIOD="$2"; shift 2 ;;
    --keep)      KEEP="$2"; shift 2 ;;
    --frames)    ALIVE_N="$2"; shift 2 ;;
    --span)      ALIVE_SPAN="$2"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    -*)          echo "banner-verify: unknown flag $1" >&2; exit 2 ;;
    *)           ASSET="$1"; shift ;;
  esac
done

PASS=0; FAIL=0; RESULTS=()
ok()   { RESULTS+=("  ✓ $1"); PASS=$((PASS+1)); }
bad()  { RESULTS+=("  ✗ $1"); FAIL=$((FAIL+1)); }

# hash_of — stdout is the hash, and it is EMPTY only when the file is unusable. Callers must
# check for emptiness; that is the guard the naive version of this script lacked.
hash_of() {
  local f="$1"
  [[ -f "$f" && -s "$f" ]] || return 1
  md5 -q "$f" 2>/dev/null || md5sum "$f" 2>/dev/null | cut -d' ' -f1
}

# ── self-test: prove the guards are load-bearing ──────────────────────────────────────────────
# A guard that has never been observed to fire is a guess. These four assertions sabotage the
# inputs and require the failure to be detected.
if [[ "${SELF_TEST:-0}" == 1 ]]; then
  echo "banner-verify --self-test: proving the guards fail when they should"
  st_pass=0; st_fail=0
  st() { if [[ "$2" == "$3" ]]; then echo "  ✓ $1"; st_pass=$((st_pass+1));
         else echo "  ✗ $1 (got '$3', want '$2')"; st_fail=$((st_fail+1)); fi; }

  tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT

  # 1. a missing file must NOT yield a hash
  hash_of "$tmp/nope.png" >/dev/null 2>&1 && r=hashed || r=refused
  st "missing file refused by hash_of" refused "$r"

  # 2. an empty file must NOT yield a hash — this is the exact false-PASS shape
  : > "$tmp/empty.png"
  hash_of "$tmp/empty.png" >/dev/null 2>&1 && r=hashed || r=refused
  st "zero-byte file refused by hash_of" refused "$r"

  # 3. two absent files must not compare equal through the real code path
  a=$(hash_of "$tmp/a.png" 2>/dev/null || true); b=$(hash_of "$tmp/b.png" 2>/dev/null || true)
  if [[ -n "$a" && -n "$b" && "$a" == "$b" ]]; then r=equal; else r=not-equal; fi
  st "two absent files do not compare equal" not-equal "$r"

  # 4. and the naive spelling DOES produce the false pass — so the guard is not decoration
  if [[ "$(md5 -q "$tmp/x.png" 2>/dev/null)" == "$(md5 -q "$tmp/y.png" 2>/dev/null)" ]]; then
    r=false-pass; else r=safe; fi
  st "unguarded compare is genuinely unsafe (documents the bug)" false-pass "$r"

  echo "self-test: $st_pass passed, $st_fail failed"
  [[ "$st_fail" -eq 0 ]] || exit 1
  exit 0
fi

[[ -n "$ASSET" && -f "$ASSET" ]] || { echo "banner-verify: asset not found: ${ASSET:-<none>}" >&2; exit 2; }
[[ -x "$SHOTS" ]] || { echo "banner-verify: banner-shots.sh not executable at $SHOTS" >&2; exit 2; }

STEM=$(basename "$ASSET"); STEM="${STEM%.*}"
if [[ -n "$KEEP" ]]; then mkdir -p "$KEEP"; WORK=$(cd "$KEEP" && pwd)
else WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT; fi

echo "banner-verify: $ASSET  (P=${PERIOD}s)"

# ── 1. LINT ───────────────────────────────────────────────────────────────────────────────────
if lint_out=$("$SHOTS" "$ASSET" --lint 2>&1); then
  ok "LINT   one animation per element"
else
  bad "LINT   $(printf '%s' "$lint_out" | head -3 | tr '\n' ' ')"
fi

# ── 2. SEAM ───────────────────────────────────────────────────────────────────────────────────
# The whole claim of a seamless loop reduces to this one identity, so it gets the strictest guard.
seam_dir="$WORK/seam"
"$SHOTS" "$ASSET" --times "0,$PERIOD" --bg dark --scheme dark --out "$seam_dir" >/dev/null 2>&1
p0="$seam_dir/${STEM}-dark-dark-t0.png"
pP="$seam_dir/${STEM}-dark-dark-t${PERIOD}.png"
h0=$(hash_of "$p0" 2>/dev/null || true)
hP=$(hash_of "$pP" 2>/dev/null || true)
if [[ -z "$h0" || -z "$hP" ]]; then
  bad "SEAM   NOT PROVEN — a render is missing or empty (t=0:'${h0:-MISSING}' t=$PERIOD:'${hP:-MISSING}')"
elif [[ "$h0" == "$hP" ]]; then
  ok "SEAM   t=0 == t=$PERIOD  ($h0)"
else
  bad "SEAM   t=0 != t=$PERIOD  ($h0 vs $hP) — some sub-period does not divide $PERIOD"
fi

# ── 3. ALIVE ──────────────────────────────────────────────────────────────────────────────────
# Distinctness alone is not enough: if the renderer produced 1 file, 1 unique hash would trivially
# be "all distinct". So the frame COUNT is asserted too.
alive_dir="$WORK/alive"
times=$(python3 -c "
n=$ALIVE_N; span=$ALIVE_SPAN
print(','.join(f'{i*span/(n-1):.2f}' for i in range(n)))")
"$SHOTS" "$ASSET" --times "$times" --bg dark --scheme dark --out "$alive_dir" >/dev/null 2>&1
hashes=(); missing=0
while IFS= read -r f; do
  h=$(hash_of "$f" 2>/dev/null || true)
  if [[ -z "$h" ]]; then missing=$((missing+1)); else hashes+=("$h"); fi
done < <(find "$alive_dir" -name '*.png' 2>/dev/null | sort)
n_got=${#hashes[@]}
n_uniq=$(printf '%s\n' "${hashes[@]:-}" | sort -u | grep -c . || true)
if [[ "$n_got" -ne "$ALIVE_N" ]]; then
  bad "ALIVE  NOT PROVEN — rendered $n_got/$ALIVE_N frames ($missing unusable)"
elif [[ "$n_uniq" -eq "$ALIVE_N" ]]; then
  ok "ALIVE  $n_uniq/$ALIVE_N distinct frames across 0..${ALIVE_SPAN}s"
else
  bad "ALIVE  only $n_uniq/$ALIVE_N frames distinct across 0..${ALIVE_SPAN}s — motion is too sparse"
fi

# ── 4. THEMES ─────────────────────────────────────────────────────────────────────────────────
# dark and light must both render AND must differ — identical output means the media query never
# applied and one of the two audiences is seeing a look nobody ever looked at.
theme_dir="$WORK/themes"
# Plain variables, not an associative array: macOS ships bash 3.2, where `declare -A` is a syntax
# error. A `set -u` script that reaches it dies mid-run rather than reporting a failed check.
th_dark=""; th_light=""; th_none=""
for s in dark light none; do
  page=light; [[ "$s" == dark ]] && page=dark
  "$SHOTS" "$ASSET" --times 0 --bg "$page" --scheme "$s" --out "$theme_dir" >/dev/null 2>&1
  h=$(hash_of "$theme_dir/${STEM}-${page}-${s}-t0.png" 2>/dev/null || true)
  case "$s" in dark) th_dark="$h" ;; light) th_light="$h" ;; none) th_none="$h" ;; esac
done
if [[ -z "$th_dark" || -z "$th_light" || -z "$th_none" ]]; then
  bad "THEMES NOT PROVEN — dark:'${th_dark:-MISSING}' light:'${th_light:-MISSING}' none:'${th_none:-MISSING}'"
elif [[ "$th_dark" == "$th_light" ]]; then
  bad "THEMES dark and light are IDENTICAL — prefers-color-scheme never applied"
else
  ok "THEMES dark / light / none all render, dark != light"
fi

# ── 5. STILL ──────────────────────────────────────────────────────────────────────────────────
still_dir="$WORK/still"
"$SHOTS" "$ASSET" --reduced-motion --bg dark --scheme dark --out "$still_dir" >/dev/null 2>&1
hs=$(hash_of "$still_dir/${STEM}-dark-dark-reduced.png" 2>/dev/null || true)
if [[ -n "$hs" ]]; then ok "STILL  prefers-reduced-motion renders a frozen frame"
else bad "STILL  NOT PROVEN — reduced-motion render missing or empty"; fi

# ── summary ───────────────────────────────────────────────────────────────────────────────────
printf '%s\n' "${RESULTS[@]}"
[[ -n "$KEEP" ]] && echo "  renders kept in $WORK"
if [[ "$FAIL" -eq 0 ]]; then
  echo "banner-verify: PASS ($PASS/$((PASS+FAIL)))"; exit 0
else
  echo "banner-verify: FAIL — $FAIL of $((PASS+FAIL)) checks failed"; exit 1
fi
