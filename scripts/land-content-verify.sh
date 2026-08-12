#!/usr/bin/env bash
# land-content-verify.sh — is this ref's CONTENT already on the trunk?
#
#   scripts/land-content-verify.sh <commit-ish> [--trunk <branch>] [--repo <dir>] [--no-fetch]
#
#   exit 0   the ref's content IS on trunk       ⇒ a `re-land …` row about it should RETRACT
#   exit 1   the ref holds content trunk LACKS   ⇒ the row is real; keep it
#   exit 2   CANNOT TELL (no/bad ref, no trunk, fetch failed) — never conflated with 0 or 1
#
# WHY THIS EXISTS. `land_failure_inbox()` (scripts/ship-land.sh) files a `re-land …` backlog row
# every time ship-land exits non-zero past the in-flight claim. That population measures an EXIT
# CODE, and nothing ever re-asks by content — so the rows are PREDICTIONS, and they decay within a
# day as the work lands under a different sha. Censused against trunk 2026-08-12: 24 of the 25
# `re-land …` rows of the master-stranded-work effort were FALSE, and actioning four of them would
# have REVERTED trunk. This script is the falsifier that retracts them (bin/cc-backlog `falsify`).
#
# THREE INSTRUMENTS WERE TRIED FIRST, and each failure is why the rule below is worded as it is:
#   * `git rev-list --count origin/<trunk>..<ref>` — reads 0 after a sibling rebase. This is the
#     instrument that stranded the population (incident 2026-07-11: it read 0 while the files were
#     absent from main).
#   * `git diff origin/<trunk>...<ref>` non-empty ⇒ "unlanded" — OVER-reports: non-empty for 17
#     refs, 13 of which were fully landed. A landed patch still diffs against the old merge-base.
#   * `git cherry` (patch-id) — wrong in BOTH directions: it cleared 3 refs that still held residue,
#     and convicted 0a131da73 whose every path was blob-identical to trunk. Context drift moves a
#     patch-id; it does not move content.
#
# THE RULE. base = origin/<trunk>. For every path P in `git diff --name-only <base>...<ref>`:
#   * P absent on <ref> (the ref DELETES it) ⇒ landed iff P is absent on <base> too. The arm
#     scripts/land-verify.sh already ships: never false-flag a landed delete.
#   * blob(<ref>:P) == blob(<base>:P)        ⇒ landed.
#   * P absent on <base>                     ⇒ NOT landed.
#   * blobs differ                           ⇒ landed iff `diff <ref's P> <trunk's P>` yields ZERO
#     lines present only in the ref's version — i.e. trunk is a SUPERSET. A line the ref holds and
#     trunk does not is unlanded content, wherever else that file has since travelled. Blobs that
#     differ but cannot be line-compared (binary) are NOT landed: differing bytes are content.
# Exit 0 iff every path is landed.
#
# THE PATH SET IS THREE-DOT, and that is load-bearing. Two-dot (`<base> <ref>`) drags in every path
# a SIBLING changed since the ref branched, judges the ref's stale copies of them, and reports "not
# landed" for work already in trunk's history. Measured over the 93 live refs/land/failed/*: the 19
# that are ancestors of trunk have a three-dot set of 0 paths and a two-dot set of 77–412.
#
# AN ANCESTOR OF TRUNK IS LANDED — even where trunk later removed what it introduced. The empty
# three-dot set says so, and the NOTE below makes that visible rather than silent. The discriminator
# is sound rather than merely lenient: a commit that is an ancestor DID land, so any later removal
# is a separate deliberate commit recorded on trunk, whereas a rebase-dropped commit is never left
# as an ancestor. Re-landing one of these is exactly how four of the censused rows would have
# reverted trunk.
#
# NOT scripts/land-verify.sh, which demands EQUALITY (`git diff <local> <trunk> -- P` empty). That
# is the right question immediately after a push and the wrong one a day later — any later edit to
# a landed path would read as stranded. This asks the weaker, durable question: is trunk a superset?
#
# A STALE TRUNK IS THE FAILURE MODE OF EVERY INSTRUMENT ABOVE, so the fetch is not optional: if it
# cannot be refreshed the answer is 2, never an answer computed from a trunk we did not look at.
# `--no-fetch` (or LAND_CONTENT_VERIFY_FETCH=off) is for fixtures and for reading a known-fresh ref.
#
# bash 3.2-safe (BSD userland: no `readlink -f`). NO `set -e`.
set -uo pipefail

usage() {
  sed -n '2,10p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'
}

# The live layer reaches scripts/ by PER-FILE symlink, so a bare `dirname "$0"/..` resolves to
# ~/.claude — which is no git repo — and this would answer 2 forever (scripts/self-path-lint.sh is
# the ratchet for that class; this is its canonical fix).
_resolve_self() { # <path> → absolute path, every symlink hop resolved
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}

REF="" TRUNK="" REPO_ARG="" FETCH="${LAND_CONTENT_VERIFY_FETCH:-on}"
while [ $# -gt 0 ]; do
  case "$1" in
    --trunk) shift; TRUNK="${1:-}"; [ $# -gt 0 ] && shift ;;
    --repo)  shift; REPO_ARG="${1:-}"; [ $# -gt 0 ] && shift ;;
    --no-fetch) FETCH=off; shift ;;
    -h|--help) usage; exit 64 ;;
    -*) printf '✗ land-content-verify: unknown option %s\n' "$1" >&2; usage >&2; exit 2 ;;
    *)
      if [ -z "$REF" ]; then REF="$1"; else
        printf '✗ land-content-verify: one <commit-ish> at a time (got %s and %s)\n' "$REF" "$1" >&2
        exit 2
      fi
      shift ;;
  esac
done

if [ -z "$REF" ]; then
  printf '✗ land-content-verify: no <commit-ish> given — cannot tell.\n' >&2
  usage >&2
  exit 2
fi

if [ -n "$REPO_ARG" ]; then
  REPO="$REPO_ARG"
else
  SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
  REPO="$(git -C "$(dirname "$SELF")" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$REPO" ] || REPO="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
if [ -z "$REPO" ] || ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  printf '✗ land-content-verify: no git repo resolved (tried --repo, this script'"'"'s own location, cwd) — cannot tell.\n' >&2
  exit 2
fi

if [ -z "$TRUNK" ]; then
  TRUNK="$(git -C "$REPO" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
  [ -n "$TRUNK" ] || TRUNK="main"
fi
BASE="origin/${TRUNK}"

if [ "$FETCH" != "off" ]; then
  # Bounded the way bin/cc-backlog bounds a falsifier and for the same reason — a probe must never
  # hold its caller open. No timeout binary ⇒ fetch unbounded rather than skip: an unfetched trunk
  # is the one thing this script must not answer from.
  TO=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    if [ -n "$_c" ] && [ -x "$_c" ]; then TO="$_c"; break; fi
  done
  if [ -n "$TO" ]; then
    "$TO" "${LAND_CONTENT_VERIFY_FETCH_TIMEOUT:-20}" git -C "$REPO" fetch --quiet origin "$TRUNK" >/dev/null 2>&1
    FRC=$?
  else
    git -C "$REPO" fetch --quiet origin "$TRUNK" >/dev/null 2>&1
    FRC=$?
  fi
  if [ "$FRC" -ne 0 ]; then
    printf '✗ land-content-verify: could not fetch origin/%s (rc %s) — CANNOT TELL. A verdict off a stale trunk is the failure mode this script exists to end.\n' \
      "$TRUNK" "$FRC" >&2
    exit 2
  fi
fi

if ! git -C "$REPO" rev-parse -q --verify "${REF}^{commit}" >/dev/null 2>&1; then
  printf '✗ land-content-verify: %s does not resolve to a commit in %s — cannot tell.\n' "$REF" "$REPO" >&2
  exit 2
fi
if ! git -C "$REPO" rev-parse -q --verify "${BASE}^{commit}" >/dev/null 2>&1; then
  printf '✗ land-content-verify: %s does not resolve — no trunk to compare against; cannot tell.\n' "$BASE" >&2
  exit 2
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/land-content-verify.XXXXXX" 2>/dev/null || true)"
if [ -z "$TMP" ] || [ ! -d "$TMP" ]; then
  printf '✗ land-content-verify: no scratch dir — cannot tell.\n' >&2
  exit 2
fi
trap 'rm -rf "$TMP"' EXIT

# -z (NUL-delimited) because a path with a space or a quote is otherwise RE-QUOTED by git and would
# be looked up under a name that does not exist. Written to a file, never a variable: bash discards
# NUL bytes in a command substitution, which would silently concatenate the whole path set into one.
if ! git -C "$REPO" diff --name-only -z "${BASE}...${REF}" > "$TMP/paths" 2>/dev/null; then
  printf '✗ land-content-verify: git diff --name-only %s...%s failed — cannot tell.\n' "$BASE" "$REF" >&2
  exit 2
fi

N=0 BAD=0 SUP=0
: > "$TMP/report"; : > "$TMP/superseded"

# ── SUPERSESSION: value that reached trunk AND WAS THEN IMPROVED ─────────────────────────────────
# Without this arm the script convicts our own later fixes. Measured 2026-08-12 against the census
# that motivated this file: it called 3 of 5 already-landed refs NOT-landed, and for 0a131da73 the
# single "line present only in the ref" was the exact line trunk replaced in 12343c527 — the bug
# that fix removed. Reported back as "content trunk lacks".
#
# That is not a cosmetic wrong verdict. The failure inbox wires this as a FALSIFIER and a falsifier
# retracts on exit 0, so a ref whose region trunk later rewrote can never reach exit 0 again: the
# rows this exists to close would stay open forever while the mechanism reads as installed. Landed,
# wired, inert.
#
# 🚨 THE DISCRIMINATOR IS NARROW ON PURPOSE, and the obvious one is WRONG. "Did trunk touch this
# path after the ref's commit?" (`rev-list --count REF..BASE -- PATH`) over-forgives: trunk editing
# a file for an unrelated reason would retract a row whose work really was lost. For a falsifier
# that RETRACTS, over-forgiving risks losing work while under-forgiving only makes noise, so the
# error must be taken in the safe direction.
#
# What is asked instead is exact and has no judgment in it: DID TRUNK EVER CARRY THIS EXACT BLOB
# FOR THIS PATH? If it did, the ref's version reached trunk and a later trunk commit changed it —
# supersession. If it never did, the ref's bytes are genuinely absent — a real strand. Measured:
#     0a131da73 : scripts/handoff-fire.sh     → MATCH at depth 2      ⇒ superseded
#     fefa49b05 : tests/cc-backlog-venue.bats → NO MATCH in 7 revs    ⇒ genuinely held content
# The second is the control that keeps the arm from forgiving everything.
#
# Bounded: the walk stops at LCV_HISTORY_MAX revisions of that ONE path (not of the repo), so cost
# is a few rev-parses per differing path. Exhausting the bound WITHOUT a match does not forgive —
# it falls through to the strand verdict, which is the safe direction.
trunk_ever_carried() {   # $1=path $2=ref-blob → 0 trunk carried this blob once / 1 it never did
  local p="$1" want="$2" c b n=0 max="${LCV_HISTORY_MAX:-200}"
  while IFS= read -r c; do
    n=$((n + 1)); [ "$n" -gt "$max" ] && return 1
    b="$(git -C "$REPO" rev-parse -q --verify "${c}:${p}" 2>/dev/null || true)"
    [ "$b" = "$want" ] && return 0
  done < <(git -C "$REPO" log --format=%H "$BASE" -- "$p" 2>/dev/null)
  return 1
}
while IFS= read -r -d '' P; do
  N=$((N + 1))
  RB="$(git -C "$REPO" rev-parse -q --verify "${REF}:${P}" 2>/dev/null || true)"
  TB="$(git -C "$REPO" rev-parse -q --verify "${BASE}:${P}" 2>/dev/null || true)"
  if [ -z "$RB" ]; then
    # The ref DELETES this path. Trunk lacking it too is positive proof the deletion landed.
    if [ -n "$TB" ]; then
      BAD=$((BAD + 1)); printf '  %s — the ref deletes it; trunk still carries it\n' "$P" >> "$TMP/report"
    fi
    continue
  fi
  if [ -z "$TB" ]; then
    BAD=$((BAD + 1)); printf '  %s — ABSENT from %s\n' "$P" "$BASE" >> "$TMP/report"
    continue
  fi
  [ "$RB" = "$TB" ] && continue          # blob-identical: landed, whatever the sha of the commit
  git -C "$REPO" show "$RB" > "$TMP/a" 2>/dev/null
  RCA=$?
  git -C "$REPO" show "$TB" > "$TMP/b" 2>/dev/null
  RCB=$?
  if [ "$RCA" -ne 0 ] || [ "$RCB" -ne 0 ]; then
    BAD=$((BAD + 1)); printf '  %s — blobs differ and one could not be read\n' "$P" >> "$TMP/report"
    continue
  fi
  diff "$TMP/a" "$TMP/b" > "$TMP/d" 2>/dev/null
  ONLY_REF="$(grep -c '^<' "$TMP/d" 2>/dev/null || true)"
  ONLY_TRUNK="$(grep -c '^>' "$TMP/d" 2>/dev/null || true)"
  ONLY_REF="${ONLY_REF//[[:space:]]/}"; ONLY_TRUNK="${ONLY_TRUNK//[[:space:]]/}"
  if [ "${ONLY_REF:-0}" -gt 0 ]; then
    if trunk_ever_carried "$P" "$RB"; then
      SUP=$((SUP + 1))
      printf '  %s — %s ref-only line(s), but %s carried this exact blob before: SUPERSEDED, not lost\n' \
        "$P" "$ONLY_REF" "$BASE" >> "$TMP/superseded"
    else
      BAD=$((BAD + 1))
      printf '  %s — %s line(s) present only in the ref\n' "$P" "$ONLY_REF" >> "$TMP/report"
    fi
  elif [ "${ONLY_TRUNK:-0}" -eq 0 ]; then
    # Blobs differ, yet neither side shows a line: binary, or diff could not compare them. Differing
    # bytes ARE content trunk lacks — this is a 1, not a 2.
    BAD=$((BAD + 1))
    printf '  %s — blobs differ but cannot be line-compared (binary?)\n' "$P" >> "$TMP/report"
  fi
done < "$TMP/paths"

if [ "$N" -eq 0 ]; then
  if git -C "$REPO" merge-base --is-ancestor "$REF" "$BASE" 2>/dev/null; then
    printf 'NOTE: %s is an ANCESTOR of %s — its commits are in trunk history. If trunk has since removed what it introduced, that removal is trunk'"'"'s own later commit; re-landing this would revert it.\n' \
      "$REF" "$BASE"
  fi
  printf '✓ land-content-verify: %s introduces nothing %s lacks (0 paths) — LANDED.\n' "$REF" "$BASE"
  exit 0
fi

if [ "$BAD" -eq 0 ]; then
  if [ "$SUP" -gt 0 ]; then
    # SAY WHY, always. A bare ✓ over a superseded path is the same silent verdict this file exists
    # to end — the reader has to be able to tell "trunk is a superset" from "trunk carried this and
    # then improved it", because only the second one means re-landing would REVERT something.
    printf '✓ land-content-verify: all %s path(s) of %s are on %s — LANDED (%s superseded since):\n' \
      "$N" "$REF" "$BASE" "$SUP"
    head -40 "$TMP/superseded"
    [ "$SUP" -gt 40 ] && printf '  … and %s more\n' "$((SUP - 40))"
    printf '  ⚠ re-landing this ref would REVERT the later work on the path(s) above.\n'
  else
    printf '✓ land-content-verify: all %s path(s) of %s are on %s — LANDED (trunk is a superset).\n' \
      "$N" "$REF" "$BASE"
  fi
  exit 0
fi

printf '✗ land-content-verify: %s of %s path(s) hold content %s LACKS — NOT landed:\n' "$BAD" "$N" "$BASE"
head -40 "$TMP/report"
[ "$BAD" -gt 40 ] && printf '  … and %s more\n' "$((BAD - 40))"
[ "$SUP" -gt 0 ] && printf '  (%s further path(s) differ but are SUPERSEDED, not lost — not counted against the verdict)\n' "$SUP"
exit 1
