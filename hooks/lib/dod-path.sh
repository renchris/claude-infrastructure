#!/usr/bin/env bash
# hooks/lib/dod-path.sh — ONE resolution for the durable-DoD store (CLOSE_INTEGRITY W3; generator G2).
#
# THE DEFECT (recon report-adversarial G2, confirmed at wrap-ledger.sh:213-218 = dod-persist.sh
# dod_file_for — two copies of one formula, guarded only by a MUST-match comment): the DoD was
# keyed on sha(toplevel PATH), so the RECOMMENDED long-horizon pattern — wave N+1 on a fresh
# worktree off origin/main — landed every successor on a BLANK scope contract, absent-DoD read as
# ✅-with-caveat, and the close certificate could render SAFE TO CLOSE over a structurally
# unverifiable scope. 64 unaggregated per-path files existed at measurement.
#
# THE FIX: new captures are keyed on REPO IDENTITY — sha(remote.origin.url), byte-equal, the same
# identity wrap-ledger's live-layer gate already trusts, and the same move bin/cc-tlid made for the
# task board ("one board per repo — repo identity, not repo+branch"). A worktree hop keeps the
# origin, so the scope follows the WORK.
#
# MIGRATION IS TWO READ SOURCES, ZERO REWRITES — deliberately not a seed/absorb scheme: a
# first-writer-seeds design would let an ephemeral worktree's tiny legacy file shadow the main
# checkout's standing DoD history until someone happened to write there (a regression window with
# no bound). Instead:
#   · WRITE  → always the repo-key file (`repo-<sha16>.md`; local-only repos with no origin keep
#              the legacy scheme outright — nothing to key on).
#   · READ   → BOTH stores, repo-key first, then THIS toplevel's legacy path-hash file. Consumers
#              sum/concat across them, so per-toplevel history keeps working exactly where it
#              always did (its own toplevel) while every worktree of the repo shares the new store.
#              Legacy files age out as their worktrees die; nothing is ever migrated or deleted.
# `repo-` prefixes the filename so the two schemes cannot collide (legacy names are bare hex).
#
# CONSUMERS: hooks/dod-persist.sh (producer + injector) · scripts/wrap-ledger.sh (REMAINDER/DOD) —
# both source THIS file; the PATH CONTRACT comment pair they used to carry is retired by
# construction. Env seams (shared): WRAP_DOD_FILE (hard override — one file, both modes) ·
# WRAP_DOD_DIR.
# shellcheck shell=bash

_dod_dir() { printf '%s' "${WRAP_DOD_DIR:-$HOME/.claude/autonomy/dod}"; }

_dod_repo_key() { # $1=cwd → sha16 of remote.origin.url, or nothing (local-only repo)
  local u
  u="$(git -C "${1:-.}" config --get remote.origin.url 2>/dev/null || true)"
  [ -n "$u" ] || return 0
  printf '%s' "$u" | shasum 2>/dev/null | cut -c1-16 | tr -d '[:space:]'
}

_dod_legacy_file() { # $1=cwd → the pre-W3 path-hash file (the formula both copies carried)
  local top hash
  top="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${1:-.}")"
  hash="$(printf '%s' "$top" | shasum 2>/dev/null | cut -c1-16)"
  printf '%s/%s.md' "$(_dod_dir)" "${hash:-unknown}"
}

# dod_path_for <cwd> [write] → prints THE path new captures go to (also the "expected" path an
# absent-DoD message should name). The mode arg is accepted for call-site legibility; write is
# the only single-path question left — reads go through dod_read_files.
dod_path_for() {
  local cwd="${1:-.}" rk
  if [ -n "${WRAP_DOD_FILE:-}" ]; then printf '%s' "$WRAP_DOD_FILE"; return 0; fi
  rk="$(_dod_repo_key "$cwd")"
  if [ -n "$rk" ]; then printf '%s/repo-%s.md' "$(_dod_dir)" "$rk"
  else _dod_legacy_file "$cwd"; fi
  return 0
}

# dod_read_files <cwd> → prints the EXISTING read sources, one per line, repo-key first then this
# toplevel's legacy. Empty output = no durable DoD anywhere. Under WRAP_DOD_FILE prints that file
# iff it exists (the test seam stays one-file, both modes).
dod_read_files() {
  local cwd="${1:-.}" rf lf
  if [ -n "${WRAP_DOD_FILE:-}" ]; then [ -f "$WRAP_DOD_FILE" ] && printf '%s\n' "$WRAP_DOD_FILE"; return 0; fi
  rf="$(dod_path_for "$cwd" write)"
  lf="$(_dod_legacy_file "$cwd")"
  [ -f "$rf" ] && printf '%s\n' "$rf"
  [ "$lf" != "$rf" ] && [ -f "$lf" ] && printf '%s\n' "$lf"
  return 0
}
