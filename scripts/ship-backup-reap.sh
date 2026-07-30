#!/usr/bin/env bash
# ship-backup-reap.sh — the ship flow's own GC for its rollback refs.
#
#   scripts/ship-backup-reap.sh reap <backup-ref> <landed-head>
#
# ship-land.sh writes `ship/backup-<sha>` before every land as the rollback point, and NOTHING
# ever deleted it. So each *successful* land manufactured a permanent branch pinning the
# PRE-rebase commits: a rebase reflows context and a landing frequently also revises the commit,
# so those commits' patch-ids differ from what landed. `git cherry` scores them `+` and patch-id
# dedupe cannot collapse them onto their landed twins — every land therefore added fresh
# permanent "stranded" rows, and any patch-id-based exposure metric overcounted MONOTONICALLY
# with landing volume. 70 of 81 orphan-carrying branches were these refs
# (STRANDED_EXPOSURE_2026-07-26 §8.2); the live count when this landed was 739.
#
# THE PREDICATE IS CONTENT — never patch-id, never reachability. For every path the backup ref's
# own commits touched, that path's content on the ref must equal its content on the head that was
# just content-verified onto the trunk. All equal ⇒ the ref holds nothing the trunk lacks ⇒
# delete. Any difference ⇒ KEEP, naming the path. That is *precisely* land-verify.sh's per-path
# algorithm, so this script CALLS it rather than restating it: one algorithm, already the gate for
# every land, so the reap can never drift from the check that authorises it.
#
# WHY IT COMPARES AGAINST <landed-head> AND NOT origin/<trunk>. land-verify has, by the time this
# runs, already proven every path in LAND_BASE..LANDED_HEAD is present and identical on
# origin/<trunk>; proving ref ≡ LANDED_HEAD on the ref's own paths therefore proves the ref's
# content is on the trunk, transitively. Re-reading origin/<trunk> instead would re-introduce a
# race the transitive form does not have: a sibling can advance the trunk between our push and
# this reap (this repo lands ~105 commits/3h; the exposure scan watched trunk move twice inside
# one measurement), and a sibling touching one of OUR paths would then make the diff non-empty and
# leak the ref forever, for a reason having nothing to do with our content. Measured over the 739
# live refs, the same predicate against a drifted origin/main classifies 437 as "content differs" —
# i.e. against a moving trunk the predicate decays from exact to unusable. That is the whole reason
# the reap is hooked at LAND TIME, where the head we compare against is the one we just pushed,
# and the reason this script has no retrospective sweep mode at all (see the note below `cmd_reap`).
#
# FAIL-CLOSED, AND IT NEVER FAILS A LAND. Every uncertainty — unresolvable ref, missing
# land-verify, a git error, a branch checked out elsewhere — KEEPS the ref. A leaked ref costs one
# row in a metric; a wrongly-deleted one can be the sole holder of real work (45 of the 739 hold at
# least one path absent from trunk). The caller invokes this with `|| true`: a land that has
# already content-verified must never be turned red by its own cleanup.
#
# bash 3.2-safe. `pipefail` load-bearing; NO `set -e`.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAND_VERIFY="${SHIP_BACKUP_REAP_LAND_VERIFY:-${SCRIPT_DIR}/land-verify.sh}"

# The one ref namespace this tool may ever delete. A guard, not a convention: it is the only thing
# standing between a bad argument and a session branch holding unlanded work. It doubles as
# option-injection protection — a name that must start with `ship/backup-` cannot start with `-`.
REAP_NS_PREFIX='ship/backup-'

die() { printf '✗ ship-backup-reap: %s\n' "$1" >&2; exit "${2:-3}"; }

is_reapable_name() { # <ref> — refuse anything outside the backup namespace
  case "$1" in
    "${REAP_NS_PREFIX}"?*)
      case "$1" in
        *..*|*' '*|*'~'*|*'^'*|*':'*) return 1 ;;   # no revision syntax in a branch name we delete
        *) return 0 ;;
      esac
      ;;
  esac
  return 1
}

# ---- reap: the ship-flow hook ----------------------------------------------------------------
cmd_reap() {
  local ref="${1:-}" landed="${2:-}"
  [[ -n "$ref" && -n "$landed" ]] || die "usage: ship-backup-reap.sh reap <backup-ref> <landed-head>" 3

  if [[ "${SHIP_BACKUP_REAP:-on}" = "off" ]]; then
    echo "⏭ ship-backup-reap: SKIPPED (SHIP_BACKUP_REAP=off) — $ref kept." >&2
    return 0
  fi

  is_reapable_name "$ref" \
    || die "refusing to touch '$ref' — this tool only ever deletes ${REAP_NS_PREFIX}* refs" 3

  # Absent ⇒ nothing to do. Not an error: a land can legitimately reach here with no backup ref
  # (the preflight write is best-effort `|| true`), and a re-run must be idempotent.
  if ! git show-ref --verify --quiet "refs/heads/$ref"; then
    return 0
  fi

  local landed_sha
  landed_sha="$(git rev-parse --verify --quiet "${landed}^{commit}" 2>/dev/null)"
  [[ -n "$landed_sha" ]] || {
    echo "⚠ ship-backup-reap: cannot resolve landed head '$landed' — keeping $ref (fail-closed)." >&2
    return 1
  }

  [[ -x "$LAND_VERIFY" ]] || {
    echo "⚠ ship-backup-reap: land-verify.sh missing/not executable — keeping $ref (fail-closed; the reap is only ever authorised by a content proof)." >&2
    return 1
  }

  # The ref's OWN range. merge-base against the landed head, not origin/<trunk>: it is the last
  # commit the two share, i.e. the trunk point this branch was cut from, and it is computable from
  # the two refs alone — so the range cannot be widened by anything a sibling does to the trunk.
  local base
  base="$(git merge-base "$ref" "$landed_sha" 2>/dev/null)"
  [[ -n "$base" ]] || {
    echo "⚠ ship-backup-reap: no merge-base between $ref and $(git rev-parse --short "$landed_sha") — keeping $ref (fail-closed)." >&2
    return 1
  }

  # The land needed no replay (nothing landed under us), so the ref's commits are literally IN the
  # head we pushed — the strongest form of "carried", and the case `git branch -d` can re-confirm on
  # its own. 201 of the 739 live refs are this. Decided first because it is both cheaper and a more
  # honest reason string than the path-by-path result below.
  if git merge-base --is-ancestor "$ref" "$landed_sha" 2>/dev/null; then
    reap_delete "$ref" "its commits are contained in the landed head"
    return $?
  fi

  # A ref whose tree matches its base introduced nothing; land-verify would check 0 paths and pass
  # vacuously, so decide it here instead of accepting a green over an empty path set.
  if git diff --quiet "$base" "$ref" 2>/dev/null; then
    reap_delete "$ref" "introduced no change over its own base"
    return $?
  fi

  if "$LAND_VERIFY" "${base}..${ref}" "$landed_sha" "$ref" >/dev/null 2>&1; then
    reap_delete "$ref" "every path it touches is content-identical to the landed head"
    return $?
  fi

  # KEPT — and say exactly which path, because this is the branch that holds real work. The detail
  # is land-verify's own stderr verdict, quoted rather than paraphrased, so the reason a ref
  # survived is always in the verifier's words.
  local detail
  detail="$("$LAND_VERIFY" "${base}..${ref}" "$landed_sha" "$ref" 2>&1 >/dev/null)"
  echo "⚠ ship-backup-reap: KEEPING $ref — its content is NOT fully carried by the landed head $(git rev-parse --short "$landed_sha"):" >&2
  printf '%s\n' "$detail" | sed 's/^/  /' >&2
  echo "  This ref is the rollback point AND, on these paths, the only copy — recover from it before deleting it by hand." >&2
  return 1
}

reap_delete() { # <ref> <why> — the only deletion site in this file
  local ref="$1" why="$2"
  is_reapable_name "$ref" || die "internal: reap_delete called with '$ref'" 3

  # git as a SECOND gate wherever it can apply: `-d` refuses a branch not merged into HEAD or its
  # upstream, so it independently re-confirms the safe case (201 of the 739 live refs are plain
  # ancestors of the trunk — a fast-forward land). It CANNOT pass for a rebased land, because the
  # pre-rebase commits are ancestors of nothing — which is exactly the case the content proof above
  # exists to decide, so a `-d` refusal falls through rather than aborting.
  if git branch -d "$ref" >/dev/null 2>&1; then
    echo "✓ ship-backup-reap: reaped $ref (merged; $why)."
    return 0
  fi
  if git branch -D "$ref" >/dev/null 2>&1; then
    echo "✓ ship-backup-reap: reaped $ref ($why)."
    return 0
  fi
  # Checked out in a worktree, a locked ref, a read-only repo — all KEEP.
  echo "⚠ ship-backup-reap: $ref is content-verified but git refused to delete it (checked out in a worktree?) — kept." >&2
  return 1
}

# ---- NO retrospective sweep mode, deliberately -----------------------------------------------
# This tool reaps ONE ref, at land time, and has no mode that walks the accumulated population.
# Two independent reasons, both measured rather than assumed:
#   1. The predicate does not survive the walk. Against a drifted trunk, 437 of the 739 live refs
#      classify as "content differs" — and retrospectively that reading is UNDECIDABLE, because a
#      dropped hunk and a trunk that simply moved on are the same observation from there. The three
#      refs INFRA_PERFECTION_2026-07-25 named as sole-holder re-land candidates land in exactly
#      that class, which is the calibration that killed the idea: a sweep would have to either
#      refuse them (reaping nothing interesting) or guess (the one thing this must never do).
#   2. Bulk disposal is not this tool's call. It is an open OPERATOR ruling with its own backlog
#      item ("ship/backup-*: retention window, never bulk-delete"), and 45 of the 739 hold at least
#      one path absent from the trunk.
# The land-time hook is what makes the population stop growing, which is the whole finding of
# STRANDED_EXPOSURE §8.2 — the accumulated backlog is a separate, human-gated question.

case "${1:-}" in
  reap)   shift; cmd_reap "$@" ;;
  ''|-h|--help)
    echo "usage: ship-backup-reap.sh reap <backup-ref> <landed-head>"
    exit 0 ;;
  *) die "unknown mode '$1' — expected 'reap'" 3 ;;
esac
