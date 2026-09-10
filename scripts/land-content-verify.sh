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
#     Two arms rescue a path that shows ref-only lines but lost nothing, and each is exact:
#       SUPERSEDED — trunk once carried the ref's whole-file BLOB and later changed it.
#       RELOCATED  — trunk's version is a MULTISET SUPERSET of the ref's lines, so every line is
#                    present and only its OFFSET moved. `diff` is positional and cannot see this;
#                    it is the systematic false strand for INTEGRATE-only, newest-first log files.
#       AMENDED    — the ref's OWN commit is on trunk under another sha (byte-identical author date
#                    AND subject) and touches this path: the ref holds the PRE-AMENDMENT form of a
#                    commit that landed. Censused 2026-09-10 over the 21 live `re-land …` rows: 11
#                    are fully twinned this way and no other arm can retract them.
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

N=0 BAD=0 SUP=0 REL=0 AMD=0
AMENDED_TWIN=""
: > "$TMP/report"; : > "$TMP/superseded"; : > "$TMP/relocated"; : > "$TMP/amended"

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

# ── RELOCATION: value that reached trunk AT ANOTHER POSITION IN THE SAME FILE ────────────────────
# `diff` is POSITIONAL, so a line trunk carries at a different offset is counted as ref-only and the
# path is convicted. `trunk_ever_carried` cannot rescue it: it asks for the ref's whole-file BLOB,
# and trunk here carries the ref's LINES without ever having carried its blob.
#
# The miss is SYSTEMATIC for the file class this repo mandates everywhere — INTEGRATE-only,
# newest-first logs. Landing an entry at the top while the ref appended it at the bottom
# re-positions every line, so the ref reads as holding content that is demonstrably present.
# Measured on refs/land/failed/20260817T072101Z-…-reland-drain-chain: its
# docs/plans/BACKLOG_DRAIN_24_7.md was reported as "19 line(s) present only in the ref" while all 18
# non-blank ref-only lines were on trunk VERBATIM. Two `re-land …` rows sat open on that for a day,
# and the row's own remedy would have re-applied a superseded regression to scripts/autonomy-sweep.sh.
#
# 🚨 THE TEST IS A MULTISET SUPERSET, NOT A SET ONE, and that is the whole safety of the arm. A set
# test forgives a LOST DUPLICATE — a hunk deleted from a file whose other copy survives elsewhere —
# which is precisely a real strand. Asking "does trunk hold this line AT LEAST AS MANY TIMES" cannot.
#
# WHAT IT STILL CANNOT SEE, stated honestly: ORDER. A file whose every line survives but whose
# sequence was scrambled is called landed here. That is the intended reading — this oracle's question
# is "was CONTENT lost", and the arm forgives only movement, never absence. Structure-sensitive
# checks belong to the gate that compiles or runs the file, not to a landedness oracle.
#
# LC_ALL=C on both sides: the comparison must be byte-wise and the two sorts must share one collating
# order, or `comm` silently mis-pairs (memory: c-locale-turns-character-ops-into-byte-ops).
# Cost is two sorts of ONE file per differing path — cheaper than the history walk above.
trunk_covers_every_line() {   # $1=ref's blob file $2=trunk's blob file → 0 iff trunk is a multiset superset
  local lost
  lost="$(LC_ALL=C comm -23 <(LC_ALL=C sort "$1") <(LC_ALL=C sort "$2") 2>/dev/null | wc -l)"
  lost="${lost//[[:space:]]/}"
  [ "${lost:-1}" = "0" ]
}

# ── AMENDMENT: the ref's OWN commit landed, and landed AMENDED ───────────────────────────────────
# The third reading of "a line present only in the ref", and the one the two arms above cannot
# reach: the ref is the PRE-FIX form of a commit that DID land, because the author amended it on
# the way in. `trunk_ever_carried` asks for the ref's whole-file BLOB and trunk never carried it;
# `trunk_covers_every_line` asks whether trunk holds the ref's LINES and it does not — the whole
# point is that trunk deliberately holds a DIFFERENT line there.
#
# LIVE INSTANCE (why this arm exists): refs/land/failed/20260910T064729Z-…-wt-3dd6dcf66e37, commit
# 9dde21d2c "fix(classify): a ⛔ RECYCLE REFUSED body read as an operator turn …". Its
# tests/interactive-parity.bats put the literal `handoff-fire.sh --recycle` inside a fixture STRING,
# which test-hermeticity-lint rule 2 greps for against the suite's CODE — so that literal reds the
# land. The author's retry landed the same commit as 957d01564 with the literal replaced by "the
# recycler" plus a NOTE saying not to restore it. One line, present only in the ref, and it is the
# exact line the land was blocked on. Re-landing it re-introduces the regression and re-reds trunk.
# Censused over the 21 live `re-land …` rows: 11 are fully twinned this way and cannot self-retract.
#
# 🚨 THE DISCRIMINATOR IS AN IDENTITY, NOT A JUDGMENT — the same bar the supersession arm sets.
# "Did trunk change this path around when the ref's commit was written?" would over-forgive exactly
# as "did trunk touch this path after the ref's commit?" does. What is asked instead is whether the
# ref's OWN COMMIT IS ITSELF ON TRUNK under another sha: a commit with a BYTE-IDENTICAL author date
# AND a byte-identical subject. Both survive a rebase and a `--amend` unchanged, and neither is a
# similarity score — two commits agreeing on an ISO-8601 instant and a full subject line are the
# same logical commit re-landed, not two commits that resemble each other.
#
# The twin must ALSO touch this path, which is why the search is the path's own trunk log rather
# than the repository's. A twin that landed while leaving P alone says nothing about P.
#
# WHAT IT FORGIVES, STATED HONESTLY: an author who re-landed their own commit having deliberately
# dropped a hunk. That is the same trade the ANCESTOR note at the foot of this file already takes,
# and takes for a weaker reason — there the removal is a SEPARATE later commit by possibly someone
# else, while here it is the author's own final form of the very commit, decided at land time. It is
# reported as its own class with its own ⚠ for that reason: forgiven, never silent.
#
# Bounded by LCV_HISTORY_MAX revisions of that ONE path, like the supersession walk. Exhausting the
# bound without a match does NOT forgive — it falls through to the strand verdict, the safe direction.
trunk_landed_this_commit_amended() {   # $1=path → 0 iff a ref commit touching $1 has an (author-date,subject) twin on trunk that also touches $1
  local p="$1" key n=0 max="${LCV_HISTORY_MAX:-200}"
  git -C "$REPO" log --format='%aI%x09%s' "${BASE}..${REF}" -- "$p" > "$TMP/refkeys" 2>/dev/null
  [ -s "$TMP/refkeys" ] || return 1
  while IFS= read -r key; do
    n=$((n + 1)); [ "$n" -gt "$max" ] && return 1
    [ -n "$key" ] || continue
    if LC_ALL=C grep -Fxq -- "$key" "$TMP/refkeys" 2>/dev/null; then
      AMENDED_TWIN="$(git -C "$REPO" log --format='%aI%x09%s%x09%H' "$BASE" -- "$p" 2>/dev/null \
        | LC_ALL=C awk -F'\t' -v k="$key" '($1 "\t" $2)==k {print $3; exit}')"
      return 0
    fi
  done < <(git -C "$REPO" log --format='%aI%x09%s' "$BASE" -- "$p" 2>/dev/null)
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
    elif trunk_covers_every_line "$TMP/a" "$TMP/b"; then
      REL=$((REL + 1))
      printf '  %s — %s line(s) read as ref-only by positional diff, but %s holds every one of them (multiset superset): RELOCATED, not lost\n' \
        "$P" "$ONLY_REF" "$BASE" >> "$TMP/relocated"
    elif trunk_landed_this_commit_amended "$P"; then
      AMD=$((AMD + 1))
      printf '  %s — %s ref-only line(s), but the ref commit that wrote them is itself on %s as %s (same author date + subject) and touches this path: AMENDED at land time, not lost\n' \
        "$P" "$ONLY_REF" "$BASE" "${AMENDED_TWIN:-?}" >> "$TMP/amended"
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
  if [ "$SUP" -gt 0 ] || [ "$REL" -gt 0 ] || [ "$AMD" -gt 0 ]; then
    # SAY WHY, always, and say WHICH — the three ways a path can be landed are not interchangeable
    # to the reader. A bare ✓ is the silent verdict this file exists to end: only SUPERSEDED means
    # re-landing would REVERT something, while RELOCATED means the bytes are all there and the ref
    # is simply describing them at another offset.
    printf '✓ land-content-verify: all %s path(s) of %s are on %s — LANDED (%s superseded, %s relocated, %s amended):\n' \
      "$N" "$REF" "$BASE" "$SUP" "$REL" "$AMD"
    [ "$SUP" -gt 0 ] && head -40 "$TMP/superseded"
    [ "$SUP" -gt 40 ] && printf '  … and %s more superseded\n' "$((SUP - 40))"
    [ "$REL" -gt 0 ] && head -40 "$TMP/relocated"
    [ "$REL" -gt 40 ] && printf '  … and %s more relocated\n' "$((REL - 40))"
    [ "$AMD" -gt 0 ] && head -40 "$TMP/amended"
    [ "$AMD" -gt 40 ] && printf '  … and %s more amended\n' "$((AMD - 40))"
    [ "$SUP" -gt 0 ] && printf '  ⚠ re-landing this ref would REVERT the later work on the superseded path(s) above.\n'
    [ "$AMD" -gt 0 ] && printf '  ⚠ re-landing this ref would RESTORE the pre-amendment form on the amended path(s) above — the form the author changed to get the land through.\n'
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
[ "$REL" -gt 0 ] && printf '  (%s further path(s) differ but are RELOCATED — every line is on %s at another offset — not counted against the verdict)\n' "$REL" "$BASE"
[ "$AMD" -gt 0 ] && printf '  (%s further path(s) differ but are AMENDED — the ref commit that wrote them is on %s under another sha — not counted against the verdict)\n' "$AMD" "$BASE"
exit 1
