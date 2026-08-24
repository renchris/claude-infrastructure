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

# ── THE POPULATION, NAMED ONCE ───────────────────────────────────────────────────────────────────
# The source dirs a screenshot path could live in. scan_tree reads it, and so does --print-scope, so
# a caller that ASKS (scripts/ship-land.sh via lint_own_scope) learns a widening for free.
EMBEDDED_DIRS="scripts hooks bin tools"

usage() { echo "usage: $(basename "$0") [--root DIR] [--print-scope] [--selftest]" >&2; exit 2; }

# scan_tree <root> — prints "path:line:text" for every offending line. Returns 0 clean, 1 findings,
# 2 unrunnable. Scans the source dirs a screenshot path could live in.
scan_tree() {
  local root="$1" out rc
  [ -d "$root" ] || { echo "chromium-bundle-lint: scan root does not exist: $root" >&2; return 2; }

  local dirs=() d
  # shellcheck disable=SC2086  # deliberate word-split of the dir list — see EMBEDDED_DIRS
  for d in $EMBEDDED_DIRS; do [ -d "$root/$d" ] && dirs+=("$d"); done
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
  #
  # THREE STATES, and `${VAR:-}` could only ever express two (land-architecture-100p §5 P2).
  # UNSET means no caller asked for scoping ⇒ strict, everything blocks. SET-BUT-EMPTY means a
  # caller DID scope and this land touches none of bin/ hooks/ scripts/ tools/ — a docs-only land,
  # a launchd-only land — so NOTHING of theirs is here and nothing may block. `${CC_CHROMIUM_OWN:-}`
  # collapsed those two into "strict", which is the exact taxing leak this arm's own-scope exists
  # to prevent: measured on a fixture, a land with an empty own-set was refused over a SIBLING's
  # offending file, in the direction where the author has nothing to fix. ship-land ALWAYS exports
  # the variable, so set-but-empty is the common case, not a corner. Every sibling lint that got
  # this right (self-path, pane-spawn, permission-gate, tsv-pad, unattended-path) uses `+set`;
  # this was the one that did not. tests/gate-ownscope-leak.bats pins all three states.
  local own="" own_scoped=0 blocking=0
  if [ -n "${CC_CHROMIUM_OWN+set}" ]; then own_scoped=1; own="$CC_CHROMIUM_OWN"; fi
  echo "✗ CHROMIUM-BUNDLE: a screenshot path launches the full Chromium.app bundle." >&2
  printf '%s\n' "$rows" | while IFS= read -r r; do echo "    $r" >&2; done
  echo "  Fix: source scripts/lib/cc-common.sh and use" >&2
  echo "       CHROME=\"\$(resolve_headless_chrome \"\${BANNER_CHROME:-}\")\"" >&2
  echo "  The bundle registers with LaunchServices on every launch and strobes the operator's Dock." >&2

  if [ "$own_scoped" = "1" ]; then
    # The FILE field of every row, once, so the membership test below is a fixed-string equality
    # rather than a regex built from a path (a path carrying a regex metacharacter matched the
    # wrong rows, or none, in the previous form).
    local row_files
    row_files="$(printf '%s\n' "$rows" | sed 's/:.*//')"
    # An EMPTY own-set falls straight through this loop with blocking=0 — which is the point: the
    # caller scoped, and nothing of theirs is here. The loop is skipped rather than special-cased
    # so there is exactly one place that decides, and the empty case cannot drift away from it.
    while IFS= read -r o; do
      [ -z "$o" ] && continue
      # -F -x on the FILE field, not a regex on the row: the own-entry used to be interpolated
      # into `grep -q "^$o:"`, so a path containing a regex metacharacter matched the wrong rows
      # (or none). Fixed-string equality is what the sibling lints already use.
      # DRAINED (`grep … >/dev/null`, never `grep -q`): under the `set -o pipefail` at the top of
      # this file an early-exiting consumer takes SIGPIPE on the producer's next write and pipefail
      # promotes 141 over grep's 0 — the condition then reads FALSE on a MATCH, which here would
      # silently restore the very leak this block was rewritten to close.
      printf '%s\n' "$row_files" | grep -Fx -- "$o" >/dev/null 2>&1 && blocking=1
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
  #
  # THE FOURTH ARGUMENT IS A THREE-STATE, and it used to be two. It defaulted to `""` and set
  # CC_CHROMIUM_OWN unconditionally, so every "strict" case in this selftest was actually running
  # the SET-BUT-EMPTY state — and passed only because the lint conflated the two the same way.
  # A control that encodes the defect cannot catch it: this harness asserted "unscoped ⇒ blocks"
  # while never once running unscoped. Absent 4th arg now means genuinely UNSET.
  #   (omitted) → UNSET: nobody scoped ⇒ strict, everything may block
  #   ""        → SET-BUT-EMPTY: a caller scoped and owns nothing here ⇒ nothing may block
  #   "a/b.sh"  → SET: only that file may block
  expect_rc() {
    local want="$1" label="$2" root="$3" got=0
    if [ "$#" -ge 4 ]; then
      ( CC_CHROMIUM_OWN="$4" lint "$root" >/dev/null 2>&1 ) || got=$?
    else
      ( unset CC_CHROMIUM_OWN; lint "$root" >/dev/null 2>&1 ) || got=$?
    fi
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

  # Own-scope, all three states — the middle one is the leak this arm shipped with
  # (land-architecture-100p §5 P2) and the reason the harness above had to grow a third state.
  expect_rc 0 "an out-of-scope finding blocked" "$d/red" "scripts/other.sh"
  expect_rc 1 "an in-scope finding did not block" "$d/red" "scripts/probe.sh"
  expect_rc 0 "a SET-BUT-EMPTY own-set blocked — a docs-only land refused over a sibling's file" "$d/red" ""

  echo "chromium-bundle-lint --selftest: OK"
  exit 0
fi

# ── --print-scope: the population this lint JUDGES, as git pathspecs, one per line ────────────────
# WHY IT EXISTS (backlog 5fc8ff411a7c, the sibling of 0be0bd2c0b65 that closed the first two arms).
# scripts/ship-land.sh built this lint's own-scope set — the files allowed to BLOCK a land — from a
# pathspec RESTATED there as `-- 'bin/*' 'hooks/*' 'scripts/*' 'tools/*'`. That is EMBEDDED_DIRS
# written down a second time, in another file, and the drift is SILENT in the dangerous direction:
# add a fifth source dir here and a land introducing a bundle-launching screenshot path under it
# builds an own-set WITHOUT that file, so the finding drops to advisory and lands (memory:
# resident-policy-must-not-restate-perishable-facts).
#
# NO ENV SEAM on the dir list, deliberately — and that is why the restatement looked safe and was
# still worth closing: a CODE edit to EMBEDDED_DIRS parts the two copies just as silently as a
# runtime one would, and nothing was watching for it.
#
# BEFORE the --root loop below, because --print-scope answers about the lint's SHAPE, not about a
# tree: it must not require a readable root and must not be mistaken for one.
# An UNRUNNABLE lint (missing, or an older copy whose `*) usage` arm exits 2 with nothing on stdout)
# is the consumer's NON-VERDICT — never an empty scope from here.
if [ "${1:-}" = "--print-scope" ]; then
  # shellcheck disable=SC2086  # deliberate word-split of the dir list; each dir becomes one pathspec
  for _ps_d in $EMBEDDED_DIRS; do printf '%s/*\n' "$_ps_d"; done
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
