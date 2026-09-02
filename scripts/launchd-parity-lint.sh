#!/bin/bash
# launchd-parity-lint — every live LaunchAgent in scope must have a findable, matching repo SSOT.
#
# WHY THIS EXISTS (2026-07-25 launchd audit, §7 action 16): on 2026-07-25 a `plutil -extract` loop
# without `-o` REWROTE 5 live plists in place. The restore reconstructed 3 of them from
# `launchctl print` output — while a *git-tracked SSOT already existed* for 2, in a sibling repo.
# Nobody found them, because discoverability was by FILENAME and the filenames did not match the
# Labels. The same audit found three more silent drifts, each of which would have CHANGED LIVE
# BEHAVIOUR on the next reinstall:
#
#   com.chrisren.cc-reaper           SSOT misfiled as docs/activation/autonomous-reaper.plist
#   com.chrisren.verify-2114-archive repo RunAtLoad=1 vs live 0  (would fire at every login)
#   com.chrisren.restic-claude-archive  repo missing LowPriorityIO/ProcessType
#   com.reso.lr-reset-poller         repo had LR_POLLER_AUTOFIRE commented out
#                                    (would silently kill unattended limit auto-resume)
#
# Every one of those is caught by the three assertions below. More copies were never the missing
# piece — discoverability BY LABEL plus a standing drift check were.
#
# THE THREE ASSERTIONS, per in-scope live plist:
#   (a) `plutil -lint` passes                        — it parses at all
#   (b) a repo SSOT exists, KEYED BY LABEL           — findable without knowing the filename
#   (c) `plutil -p` live == `plutil -p` SSOT         — normalized content matches (comments and
#                                                      key order are allowed to differ; semantics
#                                                      are not)
#
# SCOPE — deliberately NOT every live plist:
#   com.chrisren.*.plist · com.claude.*.plist · com.reso.lr-reset-poller.plist
# The other 6 com.reso.*/gl.reso.* jobs are reso-owned, have no repo anywhere, and 2 of them do not
# even pass `plutil -lint` (raw unescaped `&&`; launchd's parser is more lenient than plutil's).
# Including them would make this check RED on every single run from day one — and a detector that
# cries wolf is a detector that gets ignored. They are the reso repo's to adopt (audit §7 item 8);
# when they are, add them here in the same commit.
#
# `.plist.disabled` files are NOT scoped on the live side (launchd does not load them) but ARE
# indexed on the repo side, so an archived-disabled SSOT still satisfies (b) if the job is ever
# re-enabled under its real name.
#
# READ-ONLY BY CONSTRUCTION: only `plutil -lint` and `plutil -p` (both pure readers, output to
# stdout) ever touch a live file. `plutil -extract` is never used here — without `-o` it rewrites
# its input in place, which is the exact incident this lint exists to make impossible to repeat.
# Nothing is loaded, unloaded, installed, or booted out; that is C10 (operator-only).
#
# No self-test flag on purpose: nightly-regression.sh runs bare `scripts/*lint*.sh`, and a bare run
# against the live fleet IS the check. A fixture-only pass would observe a description of the fleet
# instead of the fleet.
#
# Exit: 0 = every in-scope live plist parses, is findable by label, and matches its SSOT
#       1 = at least one lint failure / missing SSOT / content drift
#       2 = usage error
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LA_DIR="${LAUNCHD_LINT_LA_DIR:-$HOME/Library/LaunchAgents}"
# Colon-separated search path. The archive repo is a SIBLING git repo that legitimately owns two
# com.chrisren.* labels; a label is "findable" if it is tracked in ANY of these, not just this repo.
#
# launchd/staged/ is in this path, and that is NOT a declaration that its plists should be installed.
# This path is a RECOVERY INDEX and nothing else: the only loop that consumes it walks $LA_DIR (the
# LIVE files) and asks "if I lost this file, could I get it back?". It never enumerates the index to
# decide what ought to be running, so adding a directory here cannot invent a row — it can only turn
# a false "unrecoverable" into a true "recoverable", plus enable the (c) content-parity compare that
# a missing SSOT skips entirely. Contrast bin/cc-blockers' REPO-side glob, which DOES enumerate the
# repo to emit REPO-ONLY and therefore must stay non-recursive (tests/cc-blockers-fleet.bats).
#
# Concretely: com.claude.relogin is live, and its SSOT is committed at launchd/staged/ ON PURPOSE —
# install.sh:452 globs launchd/*.plist and bootstraps each one, so promoting that plist would let a
# routine install auto-activate credentials automation (8a1e49ab: "structure, not a conditional").
# Before this entry the lint called a committed, recoverable plist unrecoverable, and the only fixes
# its own message suggested were to copy it into the very directory that guard exists to keep it out
# of. A staged SSOT is a real SSOT; only its INSTALLATION is deliberately withheld.
LAUNCHD_LINT_REPO_DIR_DEFAULT="$REPO_ROOT/launchd:$REPO_ROOT/launchd/staged:$REPO_ROOT/scripts/limit-recover:$HOME/Development/claude-code-archive/launchd"
REPO_DIRS="${LAUNCHD_LINT_REPO_DIR:-$LAUNCHD_LINT_REPO_DIR_DEFAULT}"

case "${1:-}" in
  '') ;;
  -h|--help)
    printf 'usage: %s\n' "$(basename "$0")"
    printf '  env: LAUNCHD_LINT_LA_DIR    live LaunchAgents dir (default ~/Library/LaunchAgents)\n'
    printf '       LAUNCHD_LINT_REPO_DIR  colon-separated repo SSOT search path\n'
    exit 0 ;;
  *) printf 'launchd-parity-lint: unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

command -v plutil >/dev/null 2>&1 || { echo "launchd-parity-lint: plutil not found (macOS only)" >&2; exit 2; }

viol=0
checked=0
say() { printf '  ok   %s\n' "$1"; }
bad() { printf '  RED  %s\n' "$1"; viol=$((viol+1)); }

# Read a plist's Label without ever writing to it. `plutil -p` is a pure reader; `plutil -extract`
# is NOT (no -o ⇒ in-place rewrite) and must never appear in this file.
plist_label() {
  plutil -p "$1" 2>/dev/null \
    | sed -n 's/^[[:space:]]*"Label"[[:space:]]*=>[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
    | sed -n '1p'
}

IDX="$(mktemp "${TMPDIR:-/tmp}/launchd-parity-idx.XXXXXX")" || exit 2
trap 'rm -f "$IDX"' EXIT

# ── build the label→path index over every repo SSOT dir ───────────────────────────────────────────
IFS=':' read -r -a _repo_dirs <<< "$REPO_DIRS"
idx_dirs=0
for d in "${_repo_dirs[@]}"; do
  [ -n "$d" ] || continue
  [ -d "$d" ] || continue
  idx_dirs=$((idx_dirs+1))
  for f in "$d"/*.plist "$d"/*.plist.disabled; do
    [ -f "$f" ] || continue
    lbl="$(plist_label "$f")"
    if [ -z "$lbl" ]; then
      # An unparseable or Label-less repo file is itself a defect: it can never satisfy (b) for
      # anything, and it will be silently skipped by a filename-based search too.
      bad "$f  repo SSOT does not parse or has no Label key — it can never be found by label"
      continue
    fi
    printf '%s\t%s\n' "$lbl" "$f" >> "$IDX"
  done
done
[ "$idx_dirs" -gt 0 ] || bad "no repo SSOT dir exists in search path: $REPO_DIRS"

# ── check every in-scope live plist ───────────────────────────────────────────────────────────────
for live in "$LA_DIR"/com.chrisren.*.plist "$LA_DIR"/com.claude.*.plist "$LA_DIR"/com.reso.lr-reset-poller.plist; do
  [ -f "$live" ] || continue
  checked=$((checked+1))
  base="$(basename "$live")"

  # (a) it parses
  if ! plutil -lint "$live" >/dev/null 2>&1; then
    bad "$base  plutil -lint FAILED — live file does not parse (launchd's loader is more lenient than plutil; this survives today by parser luck)"
    continue
  fi

  lbl="$(plist_label "$live")"
  if [ -z "$lbl" ]; then
    bad "$base  live plist has no Label key"
    continue
  fi

  # (b) findable by label, filename-independent
  ssots="$(awk -F'\t' -v l="$lbl" '$1==l{print $2}' "$IDX")"
  if [ -z "$ssots" ]; then
    bad "$lbl  NO repo SSOT for this Label (searched $REPO_DIRS) — if this file is lost it is unrecoverable; capture it, do not rely on launchctl print"
    continue
  fi

  # (c) normalized content parity. Multiple SSOTs may claim a label; green if ANY matches exactly,
  # otherwise report the drift against the first (deterministically ordered by the index build).
  match=""
  while IFS= read -r cand; do
    [ -n "$cand" ] || continue
    if diff -q <(plutil -p "$live" 2>/dev/null) <(plutil -p "$cand" 2>/dev/null) >/dev/null 2>&1; then
      match="$cand"; break
    fi
  done <<< "$ssots"

  if [ -n "$match" ]; then
    say "$lbl  ← ${match#"$REPO_ROOT"/}"
  else
    first="$(printf '%s\n' "$ssots" | head -1)"
    bad "$lbl  CONTENT DRIFT vs ${first#"$REPO_ROOT"/} — reinstalling from the repo would CHANGE live behaviour"
    printf '       --- live: %s\n       +++ repo: %s\n' "$live" "$first"
    diff <(plutil -p "$live" 2>/dev/null) <(plutil -p "$first" 2>/dev/null) 2>/dev/null | sed 's/^/       /'
  fi
done

# A check that silently examined nothing is a blind check, not a green one — say so out loud.
if [ "$checked" -eq 0 ]; then
  echo "launchd-parity-lint: no in-scope plists found in $LA_DIR — VACUOUS (nothing was verified)"
  [ "$viol" -eq 0 ] && exit 0 || exit 1
fi

if [ "$viol" -gt 0 ]; then
  echo "launchd-parity-lint: ⛔ $viol problem(s) across $checked in-scope live plist(s)."
  echo "  A live job whose SSOT is missing dies with its file; one whose SSOT has DRIFTED comes back"
  echo "  WRONG — silently, on the next reinstall. Refresh the repo copy FROM live (live is"
  echo "  authoritative for a running job); never reinstall from a repo copy you have not diffed."
  exit 1
fi
echo "launchd-parity-lint: clean — $checked live plist(s), each findable by Label and matching its SSOT"
