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

# dod_toplevel <cwd> → the worktree identity a capture is STAMPED with. ONE author, deliberately:
# hooks/dod-persist.sh persist_dod stamps `## … · toplevel=<this>` and the lineage filter below
# compares against it BYTE-EQUAL, so a second copy of the formula is not a style problem here — it
# is a silent filter miss (this file's own header names that exact defect for the path formula).
dod_toplevel() {
  local t
  t="$(git -C "${1:-.}" rev-parse --show-toplevel 2>/dev/null)" || t=""
  [ -n "$t" ] || t="${1:-.}"
  printf '%s' "$t"
}

# ── SUCCESSION LINEAGE (row 4de3d0f9c0e1, prerequisite 2) ───────────────────────────────────────
# THE DEFECT the repo key created from the other side. The key is byte-equal across every worktree
# of the repo — which is what makes the succession hop work (dod-path.bats case 1) and is ALSO what
# made two CONCURRENT waves share one scope file: wave B read wave A's frozen scope as binding and
# REMAINDER summed both waves' boxes. 101 worktrees of this repo, 15 distinct frozen scopes in one
# file, measured 2026-08-18.
#
# WHY NO READ-SIDE HEURISTIC COULD FIX IT, stated as the proof rather than the list: cases 1 and 8
# of tests/dod-path.bats have the SAME setup — A freezes a scope, B reads it — and OPPOSITE
# expected answers (case 1: B must inherit; case 8: B must not). No function of that setup can
# satisfy both, so the fix was never a cleverer rule; it was a MISSING INPUT. This is that input:
# the edge predecessor-worktree → successor-worktree, minted at fire time by the one site every
# dir-changing succession passes through (scripts/handoff-fire.sh, where LAUNCH_DIR is resolved).
# `--recycle` included — it is the DEFAULT succession and it writes no fired-peer stamp at all
# (handoff-fire.sh:7358 makes RECYCLE=0 a precondition of that stamp), which is precisely why the
# fired-peer record could not be reused here. See docs/research/dod-crosstalk-2026-08-18.md.
#
# FAIL-OPEN IS THE DESIGN, NOT AN OVERSIGHT. A capture carrying NO `toplevel=` stamp is
# unattributable (every capture written before prerequisite 1 landed) and is ALWAYS inherited. The
# filter can only ever drop a block that positively names a foreign wave, so the failure direction
# is "keeps the crosstalk", never "loses a contract you legitimately own" — the same direction the
# lossless legacy read-fallback above already chose.
_DOD_TAB="$(printf '\tx')"; _DOD_TAB="${_DOD_TAB%x}"   # $( ) strips TRAILING whitespace — the x survives it
_DOD_NL="$(printf '\nx')"; _DOD_NL="${_DOD_NL%x}"

_dod_lineage_file() { printf '%s/lineage.tsv' "$(_dod_dir)"; }

# dod_lineage_record <firing-cwd> <fired-cwd> [label] → append one edge. BEST-EFFORT, ALWAYS 0:
# this runs on the fire path, where a lineage write must never be able to cost a succession.
dod_lineage_record() {
  local f from to lbl
  [ "${CC_DOD_LINEAGE:-1}" != 0 ] || return 0
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 0
  from="$(dod_toplevel "$1")"; to="$(dod_toplevel "$2")"; lbl="${3:-fire}"
  [ -n "$from" ] && [ -n "$to" ] || return 0
  # A same-dir succession (`--recycle` with no --worktree: LAUNCH_DIR IS $PWD, byte-identical)
  # keeps the toplevel identity, so its captures are already "mine" — an edge would be a self-loop
  # that says nothing. Recording only dir-CHANGING successions is what keeps the store meaningful.
  [ "$from" != "$to" ] || return 0
  case "$from$to$lbl" in *"$_DOD_TAB"*) return 0 ;; esac   # a tab would corrupt the row's fields
  case "$from$to$lbl" in *"$_DOD_NL"*) return 0 ;; esac
  f="$(_dod_lineage_file)"
  mkdir -p "$(dirname "$f")" 2>/dev/null || return 0
  printf '%s\t%s\t%s\t%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf '?')" "$from" "$to" "$lbl" \
    >> "$f" 2>/dev/null || true
  return 0
}

# dod_lineage_ancestors <cwd> → my toplevel, then every transitive PREDECESSOR, one per line.
# Cycle-safe (a `seen` set, so an A→B→A pair terminates) and depth-bounded.
dod_lineage_ancestors() {
  local me f line rest from to seen frontier next guard=0
  me="$(dod_toplevel "${1:-.}")"
  [ -n "$me" ] || return 0
  printf '%s\n' "$me"
  f="$(_dod_lineage_file)"
  [ -f "$f" ] || return 0
  seen="${_DOD_NL}${me}${_DOD_NL}"
  frontier="${_DOD_NL}${me}${_DOD_NL}"
  while [ "$guard" -lt 64 ]; do
    guard=$((guard + 1))
    next=""
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      case "$line" in '#'*) continue ;; esac
      rest="${line#*"$_DOD_TAB"}"            # from <tab> to <tab> label
      from="${rest%%"$_DOD_TAB"*}"
      rest="${rest#*"$_DOD_TAB"}"            # to <tab> label
      to="${rest%%"$_DOD_TAB"*}"
      [ -n "$from" ] && [ -n "$to" ] || continue
      case "$frontier" in *"${_DOD_NL}${to}${_DOD_NL}"*) ;; *) continue ;; esac
      case "$seen" in *"${_DOD_NL}${from}${_DOD_NL}"*) continue ;; esac
      seen="${seen}${from}${_DOD_NL}"
      next="${next}${from}${_DOD_NL}"
      printf '%s\n' "$from"
    done < "$f"
    [ -n "$next" ] || break
    frontier="${_DOD_NL}${next}"
  done
  return 0
}

# _dod_filter_file <file> <ancestor-set> → the file's content with FOREIGN waves' blocks removed.
# A block runs from a `## ` line to the next one; everything before the first `## ` (the file
# header, and a bare legacy file that is nothing but `- [ ]` boxes) is always kept.
_dod_filter_file() {
  local keep=1 line rest top
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '## '*)
        case "$line" in
          *' · toplevel='*)
            rest="${line#*' · toplevel='}"
            top="${rest%%' · '*}"
            case "$2" in *"${_DOD_NL}${top}${_DOD_NL}"*) keep=1 ;; *) keep=0 ;; esac ;;
          *) keep=1 ;;   # unattributable (pre-provenance) — inherited, never dropped
        esac ;;
    esac
    if [ "$keep" = 1 ]; then printf '%s\n' "$line"; fi
  done < "$1"
  return 0
}

# dod_filter_for <cwd> <file> → ONE source's content, lineage-filtered. `get` needs this rather
# than the concatenation below because its precedence is PER SOURCE (a repo-key scope wins over a
# legacy one); reading the concatenated stream would silently invert that to last-file-wins.
dod_filter_for() {
  local anc
  [ -f "${2:-}" ] || return 0
  anc="${_DOD_NL}$(dod_lineage_ancestors "${1:-.}")${_DOD_NL}"
  _dod_filter_file "$2" "$anc"
  return 0
}

# dod_read_content <cwd> → the concatenated content of every read source, LINEAGE-FILTERED.
# The read-side SSOT: `get`, the SessionStart injection and wrap-ledger's REMAINDER all go through
# this file's filter, so the three cannot disagree about which captures are this wave's.
dod_read_content() {
  local cwd="${1:-.}" anc f
  anc="${_DOD_NL}$(dod_lineage_ancestors "$cwd")${_DOD_NL}"
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] || continue
    _dod_filter_file "$f" "$anc"
    printf '\n'
  done <<DODRC
$(dod_read_files "$cwd")
DODRC
  return 0
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
