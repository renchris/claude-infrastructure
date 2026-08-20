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

# ── RESIDENT-DAEMON IMAGE PROBES (master ce775801633b · 475222a572de half 1) ──────────────────────
# Why these live HERE rather than in their first caller: two consumers must agree about the same
# population, and this file exists because two copies of resolve_bin had already drifted. The
# actuator (install.sh, which decides whether to RELOAD a daemon) and the reporter
# (scripts/deploy-live.sh, which PROVES whether the live layer actually reached the running
# processes) have to answer "is this daemon running stale bytes" identically, or the converger
# reports converged while the installer would still reload — the sibling-auditor failure mode.
#
# THE DEFECT THEY EXIST FOR. install.sh skips any loaded job whose plist did not change. That is
# right for a PERIODIC job — it re-execs its program at its next scheduled load. It is permanently
# wrong for a KeepAlive daemon, which never exits, so its next natural load never arrives; and
# because its plist names a SCRIPT PATH, the plist never changes when the script does. Measured on
# the live box 2026-08-19: com.claude.compressor-sentinel running an image 23.3 h older than the
# file, com.claude.lead-supervisor 18.8 h older.

# Resident = the plist's OWN top-level KeepAlive key is true. rc 0 iff resident.
#
# NOT `grep -l KeepAlive`. Measured 2026-08-19: that matches 6 of 22 plists, but 3 of those say the
# word only in a COMMENT and two of those comments say the job is deliberately NOT KeepAlive. The
# true population is 3 of 22. A grep that matches prose answers a different question, and here it
# doubled the blast radius of the remedy.
#
# Strictly true/1: a KeepAlive DICT is a CONDITIONAL restart, i.e. the job does exit, so it is not
# in the class these probes exist for. The failure direction is deliberate — a dict-KeepAlive job is
# reported fresh (today's behaviour) rather than earning an unwanted bounce.
#
# PlistBuddy is invoked by absolute path and so cannot be PATH-shadowed. That is intentional and
# stays hermetic: it only ever READS the plist it is handed, which under test is a fixture file.
plist_is_resident() { # <plist-path>
  local ka
  ka="$(/usr/libexec/PlistBuddy -c 'Print :KeepAlive' "$1" 2>/dev/null | tr -d '[:space:]' || true)"
  case "$ka" in true|1) return 0 ;; *) return 1 ;; esac
}

# The program a running process is ACTUALLY executing, read out of its own argv. Echoes the path, or
# "" when argv names no existing file (callers guard on empty). Always returns 0.
#
# NEVER out of the plist, and that is not a preference: 4 of this fleet's ProgramArguments are
# `/bin/bash -c '<inline script>'` with $HOME unexpanded, and com.claude.caffeinate-floor exec's
# into /usr/bin/caffeinate, so its running image is not a repo file at all — correctly exempt by
# construction, not a gap in the probe. argv is already resolved and already exec'd.
resident_program() { # <pid>
  local pid="$1" tok prog="" line
  line="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  local -a argv=()
  read -ra argv <<<"$line"
  # ${argv[@]+…}: bash 3.2 treats an empty array as UNBOUND under `set -u`.
  for tok in ${argv[@]+"${argv[@]}"}; do
    [ -f "$tok" ] && prog="$tok"
  done
  printf '%s' "$prog"
}

# rc 0 iff the program file on disk is NEWER than the moment the process started — i.e. the running
# image is not the image on disk. This is the "read the RUNNING image, not the symlink" primitive.
#
# TZ=UTC *and* LC_ALL=C, on BOTH sides. TZ alone is NOT enough, which is why the pin is asserted by
# a test rather than left to this comment: unpinned, this box renders lstart as
# `Tue 18 Aug 11:36:03 2026`, which the US-order format cannot parse at all — yielding an EMPTY
# start that then silently compares as "fresh". LC_ALL=C normalises it to `Tue Aug 18 11:36:03 2026`.
#
# `stat -L` FOLLOWS the live-layer symlink to the checkout. Without -L it reads the SYMLINK's own
# mtime, which for com.claude.compressor-sentinel is 13 days OLDER than the daemon's own start while
# its target is 23 h NEWER — so a -L-less probe reports a 23-hour-stale daemon as fresh. That is
# master 475222a572de half 1's defect exactly, and it is one character wide.
#
# Fail-closed: any operand it cannot resolve ⇒ rc 1, NOT stale. Each operand is validated
# SEPARATELY — concatenating them to test both at once lets an empty one hide behind a valid one,
# which is how the first draft of this reported a 23-hour-stale daemon as fresh.
resident_image_stale() { # <pid> <program-path>
  local pid="$1" prog="$2" lstart start_s file_s
  lstart="$(TZ=UTC LC_ALL=C ps -p "$pid" -o lstart= 2>/dev/null || true)"
  start_s="$(TZ=UTC LC_ALL=C date -j -f '%a %b %e %T %Y' "$lstart" +%s 2>/dev/null || true)"
  file_s="$(stat -L -f %m "$prog" 2>/dev/null || stat -L -c %Y "$prog" 2>/dev/null || true)"
  case "${start_s:-x}" in *[!0-9]*) return 1 ;; esac
  case "${file_s:-x}"  in *[!0-9]*) return 1 ;; esac
  [ "$file_s" -gt "$start_s" ]
}

# The PID launchd reports for a label, or "" when the job is unloaded or not executing.
#
# The output is captured WHOLE and then parsed. `launchctl list … | sed …q` or `| head -1` would
# exit early and SIGPIPE the producer, and under `pipefail` that rc propagates — in an assignment
# under `set -e` it aborts the CALLER, which for install.sh means a failed install.
resident_pid() { # <label> [<launchctl-bin>]
  local label="$1" bin="${2:-launchctl}" out pid
  out="$("$bin" list "$label" 2>/dev/null || true)"
  pid="$(printf '%s\n' "$out" | sed -n 's/.*"PID" = \([0-9][0-9]*\).*/\1/p' || true)"
  printf '%s' "${pid%%$'\n'*}"
}
