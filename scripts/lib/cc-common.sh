#!/usr/bin/env bash
# cc-common.sh — shared helpers for the launchd-loaded scripts/ tools.
#
# WHY (consolidation audit 02, backlog b13787e71c9f): `resolve_bin` existed twice —
# scripts/boot-resume.sh and scripts/autonomy-sweep.sh — and the two copies had ALREADY DRIFTED:
# boot-resume's took a third `beside` argument and searched a beside-script tier first; autonomy-
# sweep's did not. Both are launchd jobs whose failures are silent, so a fix applied to one copy
# would have gone unnoticed in the other.
#
# The canonical form here is boot-resume's SUPERSET (`beside` defaults to the basename). Adopting it
# in autonomy-sweep is behaviour-preserving: its three helpers are cc-notify / cc-decide /
# cc-backlog, and no `scripts/cc-notify`-style sibling exists in either the repo or the live layer,
# so the added tier resolves nothing there. Verified on disk before the change, not assumed.
#
# NOTE on the audit's other two `cc-common.sh` candidates — both REJECTED, with reasons recorded in
# docs/plans/CONSOLIDATION_AUDIT02.md:
#   • the jq guard (29 top-level sites): not duplication but a shared convention with four distinct
#     semantics, and you cannot `source` a lib to discover whether `jq` exists — that trades a
#     zero-dependency one-liner for a heavier dependency than the one being guarded.
#   • the selftest scaffold (16 files): hashing their okp()/badp() definitions yields SEVEN distinct
#     variants, each pinned by its own bats assertions. Not lockstep; unifying them would rewrite
#     selftest output in 16 independently-deployed scripts for no operational gain.
#
# Pure function definitions only — no side effects on source (safe under `set -u`).
#
# Deployed by install.sh (which globs scripts/*.sh top-level only, so scripts/lib/ gets its own
# explicit loop — same treatment as scripts/limit-recover/).

# Resolve a helper binary: env override → beside-script → repo/CFG bin → ~/.claude/bin → PATH.
# Echoes the resolved path, or "" when nothing is found (callers guard on empty — a missing helper
# degrades the job, it does not crash it). Always returns 0.
#
# $0 is deliberately used rather than BASH_SOURCE: this is sourced, so $0 stays the CALLING script
# and the beside-script/../bin tiers keep resolving relative to it exactly as the inline copies did.
resolve_bin() { # <env-value> <basename> [<beside-name>]
  local override="$1" name="$2" beside="${3:-$2}" cand
  if [ -n "$override" ]; then [ -x "$override" ] && printf '%s' "$override"; return 0; fi
  for cand in "$(dirname "$0")/$beside" "$(dirname "$0")/../bin/$name" \
              "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/$name" "$HOME/.claude/bin/$name"; do
    [ -x "$cand" ] && { printf '%s' "$cand"; return 0; }
  done
  command -v "$name" >/dev/null 2>&1 && printf '%s' "$(command -v "$name")"
  return 0
}

# Resolve a Chromium for headless screenshotting, PREFERRING chrome-headless-shell.
# Echoes the resolved path, or "" when nothing is found (callers guard on empty).
#
# WHY the preference is load-bearing, not cosmetic: the full Chromium.app bundle checks in with
# LaunchServices on EVERY launch even under --headless, so the Dock paints a launching-app tile for
# the ~1.3s each process lives. A screenshot LOOP therefore makes the operator's Dock flash an
# app icon every 1-2s for the entire run — the reported symptom this helper exists to kill.
# Measured 2026-07-30 (Chromium 141.0.7390.37, macOS 24.6), counting `launchservicesd ... CHECKIN
# ... org.chromium.Chromium` from `log stream`, against a 0-launch idle baseline that read 0:
#     full Chromium.app      x20 -> 22 app CHECKINs, 24s
#     chrome-headless-shell  x20 ->  0 app CHECKINs,  5s
# --headless=new is NOT the fix: on the same bundle it registered MORE (37 per 15 launches) and ran
# 3.5x slower, with one launch hanging until killed.
#
# The swap is render-identical, so this is a pure win rather than a quality trade: 0 differing
# pixels (ImageMagick AE) at 1800x2400 on assets/banner/clawd-reference.svg, motion-kit.svg and
# proto-a-vector.svg. (A toy page of system-font TEXT did drift 281px/1.44M — antialiasing of
# fonts, not of SVG art — so re-measure before reusing this for text-heavy captures.)
#
# Falls back to the full bundle when no headless shell is installed: a machine with only the
# browser build keeps working, it just flashes the Dock as it did before.
resolve_headless_chrome() { # [<env-override>]
  local override="${1:-}" cand best=""
  if [ -n "$override" ]; then [ -x "$override" ] && printf '%s' "$override"; return 0; fi
  # glob rather than `ls`: highest-numbered install wins, and no filename is ever parsed.
  for cand in "$HOME"/Library/Caches/ms-playwright/chromium_headless_shell-*/chrome-headless-shell-mac-*/chrome-headless-shell; do
    [ -x "$cand" ] && best="$cand"
  done
  if [ -z "$best" ]; then
    for cand in "$HOME"/Library/Caches/ms-playwright/chromium-*/chrome-mac/Chromium.app/Contents/MacOS/Chromium; do
      [ -x "$cand" ] && best="$cand"
    done
  fi
  [ -n "$best" ] && printf '%s' "$best"
  return 0
}
