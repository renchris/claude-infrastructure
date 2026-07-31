#!/bin/bash
# chromium-bundle-lint — the RATCHET that stops a screenshot path from launching the FULL
# Chromium.app bundle instead of chrome-headless-shell.
#
# THE SCAR (2026-07-30, operator-reported): "the macOS Dock keeps moving as if it was trying to open
# a new app for ~0.1s then close, every 1-2 seconds." Root cause: scripts/banner-shots.sh took every
# screenshot by exec'ing the playwright FULL bundle. That bundle checks in with LaunchServices on
# EVERY launch even under --headless — `launchservicesd … CHECKIN … org.chromium.Chromium` — so the
# Dock paints a launching-app tile for the ~1.3s each process lives. A per-shot loop therefore
# strobes the operator's Dock for the entire run. Measured against a 0-launch idle baseline of 0:
#     full Chromium.app     x20 -> 22 app CHECKINs, 24s
#     chrome-headless-shell x20 ->  0 app CHECKINs,  5s
# --headless=new is NOT an escape: on the same bundle it registered MORE (37 per 15 launches), ran
# 3.5x slower, and one launch hung until killed. The only fix is the other BINARY.
#
# The swap is free: 0 differing pixels (ImageMagick AE) at 1800x2400 across three real banner
# assets, and banner-verify.sh compares a DECODED RGBA digest rather than file bytes, so its gates
# see nothing change. It is also ~5x faster.
#
# WHY THIS IS A GATE AND NOT JUST A SUITE: enforcement by its own suite alone is post-hoc detection
# — gate-select will not pick this suite up when the edited file is a PRODUCER (a new screenshot
# script) rather than the lint itself (memory: enforcement-must-live-at-the-chokepoint). The symptom
# is invisible to every automated check that exists: nothing is slow, nothing is red, no test fails.
# It shows up only as an annoyance on the operator's own screen, which is exactly the class of bug
# that survives for months.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unusable scan tree / unrunnable check (LOUD,
# never a clean verdict — a detector that could not run has nothing to say about the tree).

set -uo pipefail

SELF="$0"
[ -L "$SELF" ] && SELF="$(readlink "$SELF")"
ROOT_DEFAULT="$(cd "$(dirname "$SELF")/.." 2>/dev/null && pwd)"

# The literal that means "the app bundle", as opposed to the headless shell binary. Kept as one
# fragment so a path split across a variable still reads as the bundle when it is joined.
BUNDLE_RE='chrome-mac/Chromium\.app/Contents/MacOS/Chromium'

# ALLOWED: the one sanctioned mention. resolve_headless_chrome falls back to the bundle when no
# headless shell is installed, so a machine with only the browser build keeps working.
ALLOW='scripts/lib/cc-common.sh'

# GRANDFATHERED BY PATH, all latent — the rule binds on new code, exactly as self-path-lint's 26
# inherited files do. tools/motion-film/capture.mjs opens ONE long-lived CDP browser per run rather
# than a per-shot loop, so it costs a single Dock tile, not a strobe; its headless-shell candidate
# paths are also already wrong for the current playwright layout. Left unchanged deliberately:
# it was never measured, and an unverified fix to a working capture tool is a worse trade than a
# named latent finding.
GRANDFATHERED='tools/motion-film/capture.mjs'

usage() { echo "usage: $(basename "$0") [--root DIR] [--selftest]" >&2; exit 2; }

# scan_tree <root> — prints "path:line:text" for every offending line. Returns 0 clean, 1 findings,
# 2 unrunnable. Scans the source dirs a screenshot path could live in.
scan_tree() {
  local root="$1" out rc
  [ -d "$root" ] || { echo "chromium-bundle-lint: scan root does not exist: $root" >&2; return 2; }

  local dirs=() d
  for d in scripts hooks bin tools; do [ -d "$root/$d" ] && dirs+=("$d"); done
  [ "${#dirs[@]}" -gt 0 ] || { echo "chromium-bundle-lint: no source dirs under $root" >&2; return 2; }

  # grep exit 0=match 1=no-match; anything else is a broken detector and must be LOUD.
  out="$(cd "$root" && grep -rn -- "$BUNDLE_RE" "${dirs[@]}" 2>/dev/null)"; rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "chromium-bundle-lint: grep failed (rc=$rc) — detector unrunnable" >&2; return 2
  fi

  printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | while IFS= read -r line; do
    f="${line%%:*}"
    [ "$f" = "$ALLOW" ] && continue
    [ "$f" = "$GRANDFATHERED" ] && continue
    # This file necessarily contains the pattern — in the detector, in the fix guidance, and in
    # every --selftest fixture. Excluded by basename exactly as self-path-lint.sh excludes itself;
    # what validates THIS file is --selftest, which the gate runs alongside the scan.
    case "${f##*/}" in chromium-bundle-lint.sh) continue ;; esac
    printf '%s\n' "$line"
  done
  return 0
}

lint() {
  local root="$1" rows
  rows="$(scan_tree "$root")" || return 2
  [ -z "$rows" ] && return 0

  # Own-scope: block only on files THIS land changes; the rest stay advisory, so one author's
  # omission never becomes every author's hard stop.
  local own="${CC_CHROMIUM_OWN:-}" blocking=0
  echo "✗ CHROMIUM-BUNDLE: a screenshot path launches the full Chromium.app bundle." >&2
  printf '%s\n' "$rows" | while IFS= read -r r; do echo "    $r" >&2; done
  echo "  Fix: source scripts/lib/cc-common.sh and use" >&2
  echo "       CHROME=\"\$(resolve_headless_chrome \"\${BANNER_CHROME:-}\")\"" >&2
  echo "  The bundle registers with LaunchServices on every launch and strobes the operator's Dock." >&2

  if [ -n "$own" ]; then
    while IFS= read -r o; do
      [ -z "$o" ] && continue
      printf '%s\n' "$rows" | grep -q "^$o:" && blocking=1
    done <<< "$own"
    [ "$blocking" -eq 1 ] || { echo "  (advisory only — none of these files are in this land's diff)" >&2; return 0; }
  fi
  return 1
}

# ── --selftest: each case proves a RED path FIRES or a GREEN path does NOT — both directions ──────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  fail() { echo "SELFTEST FAIL: $1"; exit 1; }
  mk() { mkdir -p "$d/$1/scripts"; printf '%s\n' "$2" > "$d/$1/scripts/probe.sh"; }
  # rc <expected> <label> -- runs `lint` in a subshell and compares its EXIT CODE. Written as an
  # explicit `|| rc=$?` capture rather than `[ $? -eq N ]`, so the assertion cannot be silently
  # reading the exit status of some intervening command.
  expect_rc() {
    local want="$1" label="$2" root="$3" own="${4:-}" got=0
    ( CC_CHROMIUM_OWN="$own" lint "$root" >/dev/null 2>&1 ) || got=$?
    [ "$got" -eq "$want" ] || fail "$label (wanted rc=$want, got rc=$got)"
  }

  # RED: the real scar shape, byte-for-byte as banner-shots.sh carried it.
  # shellcheck disable=SC2016  # a fixture of literal source text; expansion here would defeat it
  mk red 'for _c in "$HOME"/Library/Caches/ms-playwright/chromium-*/chrome-mac/Chromium.app/Contents/MacOS/Chromium; do
  [[ -x "$_c" ]] && CHROME="$_c"
done'
  expect_rc 1 "the real scar shape did not fire" "$d/red"

  # GREEN: the fixed shape must NOT fire — otherwise the lint red-lines its own remedy.
  # shellcheck disable=SC2016  # fixture text, not an expression to expand
  mk green 'CHROME="$(resolve_headless_chrome "${BANNER_CHROME:-}")"'
  expect_rc 0 "the fixed shape fired (the lint rejects its own remedy)" "$d/green"

  # GREEN: the headless shell binary itself must not fire.
  # shellcheck disable=SC2016  # fixture text, not an expression to expand
  mk shell 'CHROME="$HOME/Library/Caches/ms-playwright/chromium_headless_shell-1228/chrome-headless-shell-mac-arm64/chrome-headless-shell"'
  expect_rc 0 "chrome-headless-shell fired" "$d/shell"

  # LOUD: a missing scan root is exit 2, never a clean 0 — a non-verdict must not read as a pass.
  expect_rc 2 "a missing scan root did not exit 2" "$d/nope"
  mkdir -p "$d/empty"
  expect_rc 2 "a root with no source dirs did not exit 2" "$d/empty"

  # Own-scope: a finding OUTSIDE the own-set is advisory (0); INSIDE it blocks (1).
  expect_rc 0 "an out-of-scope finding blocked" "$d/red" "scripts/other.sh"
  expect_rc 1 "an in-scope finding did not block" "$d/red" "scripts/probe.sh"

  echo "chromium-bundle-lint --selftest: OK"
  exit 0
fi

ROOT="$ROOT_DEFAULT"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT="${2:-}"; [ -n "$ROOT" ] || usage; shift 2 ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

lint "$ROOT"
exit $?
