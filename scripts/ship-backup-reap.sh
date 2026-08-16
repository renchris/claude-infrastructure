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
# ── THE SECOND MODE: `sweep` — the accumulated population (backlog d88c1640550f) ───────────────
#
#   scripts/ship-backup-reap.sh sweep [--apply]
#
# `reap` stops the population GROWING. It never addressed the pile already on the disk (~248 refs
# at the time of the ruling), because every ref that survives today is one whose land did NOT
# succeed — i.e. a STUCK FIRE TIP, whose branch is still parked at the very commit the backup ref
# names. THE RULING (2026-08-16): those may be GC'd, restricted to the subset where a live carrier
# ref CONTAINS them, proof-gated per ref, with a disposal record. See §THE PREDICATE below.
#
# WHY THIS PREDICATE SURVIVES THE WALK WHERE `reap`'s DOES NOT — the objection this mode had to
# answer, since the block at the foot of this file used to refuse a sweep outright. `reap`'s
# content-vs-trunk predicate decays retrospectively: against a drifted trunk 437 of 739 refs
# classify as "content differs", and from there a dropped hunk and a trunk that merely moved on are
# THE SAME OBSERVATION. `sweep` never asks that question. It uses only `reap`'s FIRST and strongest
# branch — `git merge-base --is-ancestor` — against a carrier chosen at sweep time. Ancestry is
# exact, trunk-independent, and strictly stronger than content identity: if the backup ref is an
# ancestor of the carrier, every OBJECT it holds is reachable from the carrier, so the deletion
# frees nothing. There is no drift for it to decay under, which is precisely why it is decidable
# retrospectively and the content one is not. A ref with no carrier is the sole-holder class — it
# is KEPT and NAMED, never guessed at.
#
# WHY DELETING A STUCK FIRE'S ROLLBACK POINT DOES NOT COST THE REDUNDANCY — the item's own worry,
# and the reason the answer is yes. Three independent mechanisms, each verified in a landed file:
#   1. IT IS REGENERATED, IDENTICALLY, BEFORE IT IS NEXT NEEDED. `ship-land.sh:3708` computes
#      `ship/backup-$(git rev-parse --short HEAD)` and writes it with `git branch -f` in the land
#      preflight. A fire branch still parked at that sha therefore re-creates THE SAME REF NAME AT
#      THE SAME COMMIT at the start of its next land attempt, before anything mutates the tree.
#      The rollback point is not being destroyed; it is being deferred to the moment it has a job.
#   2. NO OBJECT IS FREED. Ancestor-containment means the carrier already pins every object in the
#      backup's history, so `git gc` has nothing new to prune. (Deleting the ref is also reflog-
#      recoverable in its own right — that is a second line of defence, not the argument.)
#   3. THE CARRIER CANNOT BE SWEPT OUT FROM UNDER IT. `worktree-gc.sh` prunes a branch only when
#      `landed()` holds — patch-id containment on the trunk (`worktree-gc.sh:433`) — and a stuck
#      fire's pre-rebase commits score `+` under `git cherry`, which is the whole reason this
#      population exists. Its worktree-DISPOSE path independently refuses without a durable-ref
#      proof and records `preserved_at: refs/heads/<branch>`. The asymmetry runs the OTHER way from
#      the item's premise: `ship/backup-*` is on `protected_branch()`'s never-delete list
#      (`worktree-gc.sh:787-792`) and the fire branch is not — so this mode is deleting the member
#      that no other sweeper would have touched, which is exactly why it must carry its own proof.
#
# DRY-RUN BY DEFAULT, unlike `reap`. `reap` acts on one ref it was just handed by the land that
# created it; `sweep` walks a population it did not create, so the default is a report and deletion
# needs `--apply`. Every disposal writes a record (`master-fleet-footprint` P1: *record the
# decision, never guess*) naming the carrier that authorised it, so "why did this ref go" is
# answerable months later — the question `worktree-gc --dispose-landed-dirt` could not answer for
# the 32 directories it removed on 2026-08-11.
#
# bash 3.2-safe. `pipefail` load-bearing; NO `set -e`.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAND_VERIFY="${SHIP_BACKUP_REAP_LAND_VERIFY:-${SCRIPT_DIR}/land-verify.sh}"

# The trunk a sweep offers as a carrier. A REMOTE-tracking ref deliberately: it is the one carrier
# whose durability does not depend on this disk at all.
SWEEP_TRUNK="${CC_SHIP_BACKUP_TRUNK:-origin/main}"
# Same directory and the same JSONL shape as worktree-gc.sh's disposal log, so the two reapers'
# records read as one story rather than two formats.
DISPOSAL_LOG="${CC_SHIP_BACKUP_DISPOSAL_LOG:-$HOME/.claude/autonomy/ship-backup-disposals.jsonl}"

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

json_esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# The disposal record. Written at the ONE deletion site, so it cannot be forgotten by a future
# caller: a reaper whose record is a separate call is a reaper that eventually deletes without one.
# Best-effort by design — an unwritable log must never fail a land (see FAIL-CLOSED above), but the
# deletion it would have recorded has already been authorised by a proof either way.
disposal_record() { # <ref> <sha> <mode> <authority> <why>
  local dir; dir="$(dirname "$DISPOSAL_LOG")"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '{"ts":"%s","event":"ship-backup-disposed","ref":"%s","sha":"%s","mode":"%s","authority":"%s","why":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(json_esc "$1")" "$2" "$(json_esc "$3")" \
    "$(json_esc "$4")" "$(json_esc "$5")" \
    >> "$DISPOSAL_LOG" 2>/dev/null || true
}

reap_delete() { # <ref> <why> [mode] [authority] — the only deletion site in this file
  local ref="$1" why="$2" mode="${3:-reap}" authority="${4:-land-verify}"
  is_reapable_name "$ref" || die "internal: reap_delete called with '$ref'" 3
  # Read the sha BEFORE the delete — afterwards the ref is gone and the record could only name it
  # as a string, which is exactly the unrecoverable-blast-radius defect this log exists to close.
  local sha; sha="$(git rev-parse --verify --quiet "refs/heads/$ref" 2>/dev/null)"

  # git as a SECOND gate wherever it can apply: `-d` refuses a branch not merged into HEAD or its
  # upstream, so it independently re-confirms the safe case (201 of the 739 live refs are plain
  # ancestors of the trunk — a fast-forward land). It CANNOT pass for a rebased land, because the
  # pre-rebase commits are ancestors of nothing — which is exactly the case the content proof above
  # exists to decide, so a `-d` refusal falls through rather than aborting.
  if git branch -d "$ref" >/dev/null 2>&1; then
    disposal_record "$ref" "$sha" "$mode" "$authority" "merged; $why"
    echo "✓ ship-backup-reap: reaped $ref (merged; $why)."
    return 0
  fi
  if git branch -D "$ref" >/dev/null 2>&1; then
    disposal_record "$ref" "$sha" "$mode" "$authority" "$why"
    echo "✓ ship-backup-reap: reaped $ref ($why)."
    return 0
  fi
  # Checked out in a worktree, a locked ref, a read-only repo — all KEEP.
  echo "⚠ ship-backup-reap: $ref is content-verified but git refused to delete it (checked out in a worktree?) — kept." >&2
  return 1
}

# ---- sweep: the accumulated population --------------------------------------------------------
#
# SUPERSEDES the block that used to stand here refusing a retrospective sweep outright. That
# refusal gave two reasons, and the ruling of 2026-08-16 (backlog d88c1640550f) addressed them
# rather than overruling them — both are preserved here because the shape of the answer is what
# keeps this mode inside its lane:
#
#   1. "The predicate does not survive the walk." STILL TRUE, and STILL BINDING — of the CONTENT
#      predicate, which is why `sweep` does not use it. Against a drifted trunk 437 of 739 refs
#      classify as "content differs", and retrospectively a dropped hunk and a trunk that merely
#      moved on are the same observation. `sweep` asks only the ancestry question, which has no
#      drift term at all (see §WHY THIS PREDICATE SURVIVES THE WALK in the header). The three
#      sole-holder re-land candidates INFRA_PERFECTION_2026-07-25 named — the calibration that
#      killed the original idea — are precisely the refs ancestry REFUSES to carry, so they are
#      KEPT and named. That is the check that this mode does not smuggle the old predicate back in.
#   2. "Bulk disposal is not this tool's call — it is an open OPERATOR ruling with its own backlog
#      item." That item is d88c1640550f and this IS its ruling, so reason 2 is discharged rather
#      than ignored. The ruling is narrower than the "rolling window (>14d AND P1-landed)" that
#      INFRA_PERFECTION put on the platter, and deliberately so: age is not evidence about content,
#      and `landed` there meant patch-id, the one reading that provably does not hold for this
#      population. A proof per ref beats a window over the population.
#
# The 45-of-739 refs that hold a path absent from the trunk are not a counterexample to this mode —
# they are its KEEP set, and a sweep that reports them by name is how they finally get looked at.

sweep_carrier_for() { # <backup-ref> → prints the first ref that CONTAINS it; rc 1 if none
  local ref="$1" c
  # Trunk first — a pushed remote-tracking ref is the most durable carrier available, and the
  # honest reason string ("landed") when it applies. Tried before local branches so a landed ref is
  # never attributed to some session branch that merely happens to also contain it.
  if git rev-parse --verify --quiet "${SWEEP_TRUNK}^{commit}" >/dev/null 2>&1 \
     && git merge-base --is-ancestor "$ref" "$SWEEP_TRUNK" 2>/dev/null; then
    printf '%s' "$SWEEP_TRUNK"; return 0
  fi
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    [ "$c" = "$ref" ] && continue
    # 🚨 A BACKUP REF MAY NEVER VOUCH FOR ANOTHER BACKUP REF. Two refs in this namespace can stand
    # in an ancestor relation, and letting one carry the other would let a single sweep delete BOTH
    # — the carrier last, by which point its own authority has already been destroyed. Excluding
    # the namespace from the carrier set is what makes every survivor's proof independent of every
    # deletion this run performs.
    is_reapable_name "$c" && continue
    if git merge-base --is-ancestor "$ref" "$c" 2>/dev/null; then
      printf '%s' "$c"; return 0
    fi
  done < <(git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
  return 1
}

cmd_sweep() {
  local apply=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --apply)   apply=1 ;;
      --dry-run) apply=0 ;;
      -h|--help) echo "usage: ship-backup-reap.sh sweep [--apply]"; return 0 ;;
      *) die "sweep: unknown option '$1' (expected --apply or --dry-run)" 3 ;;
    esac
    shift
  done

  # The kill switch covers BOTH modes. One that silenced only the land hook would leave the far
  # more destructive walk running under an operator who believed they had turned the reaper off.
  if [ "${SHIP_BACKUP_REAP:-on}" = "off" ]; then
    echo "⏭ ship-backup-reap: sweep SKIPPED (SHIP_BACKUP_REAP=off) — nothing examined." >&2
    return 0
  fi

  local n_total=0 n_carried=0 n_sole=0 n_deleted=0 n_refused=0
  local ref carrier prefix=""
  [ "$apply" = "1" ] || prefix="would "

  while IFS= read -r ref; do
    [ -n "$ref" ] || continue
    is_reapable_name "$ref" || continue
    n_total=$((n_total + 1))
    if ! carrier="$(sweep_carrier_for "$ref")"; then
      n_sole=$((n_sole + 1))
      echo "KEEP    $ref — NO carrier ref contains it: on this disk it is the SOLE holder of its commits."
      continue
    fi
    n_carried=$((n_carried + 1))
    if [ "$apply" != "1" ]; then
      echo "${prefix}reap  $ref — contained in $carrier"
      continue
    fi
    # RE-PROVE immediately before deleting. The classification above and this line are separated by
    # every ref processed in between, and a concurrent worktree-gc / cc-reaper can retire a carrier
    # inside that window — the same "inventory moved mid-audit" discipline INFRA_PERFECTION_2026-07-25
    # applied to worktree removals. Cheap; the alternative is a proof that was true a minute ago.
    if ! git merge-base --is-ancestor "$ref" "$carrier" 2>/dev/null; then
      n_refused=$((n_refused + 1)); n_carried=$((n_carried - 1)); n_sole=$((n_sole + 1))
      echo "KEEP    $ref — carrier $carrier no longer contains it (it moved mid-sweep); re-run to re-classify."
      continue
    fi
    if reap_delete "$ref" "contained in $carrier" sweep "$carrier"; then
      n_deleted=$((n_deleted + 1))
    else
      n_refused=$((n_refused + 1))
    fi
  done < <(git for-each-ref --format='%(refname:short)' "refs/heads/${REAP_NS_PREFIX}*" 2>/dev/null)

  local suffix=""
  [ "$apply" = "1" ] || suffix="   [DRY-RUN — nothing was deleted; pass --apply]"
  echo "ship-backup-reap sweep: $n_total ref(s) · $n_carried carried · $n_sole sole-holder (KEPT) · $n_deleted deleted · $n_refused refused$suffix"
  # Exit 0 even with KEEPs and refusals: both are NORMAL outcomes of this walk, and a bulk tool that
  # went red on its own correct conservatism could never be run unattended.
  return 0
}

case "${1:-}" in
  reap)   shift; cmd_reap "$@" ;;
  sweep)  shift; cmd_sweep "$@" ;;
  ''|-h|--help)
    echo "usage: ship-backup-reap.sh reap <backup-ref> <landed-head>"
    echo "       ship-backup-reap.sh sweep [--apply]"
    exit 0 ;;
  *) die "unknown mode '$1' — expected 'reap' or 'sweep'" 3 ;;
esac
