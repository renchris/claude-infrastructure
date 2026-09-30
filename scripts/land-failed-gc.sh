#!/usr/bin/env bash
# land-failed-gc.sh — bound the refs/land/failed/* pin population by pruning only what is PROVEN landed.
#
#   scripts/land-failed-gc.sh [--dry-run] [--max N] [--min-age-days D] [--repo DIR] [--journal PATH]
#
#   exit 0  the pass ran (whatever it pruned) · 2 cannot look (no repo, trunk fetch failed, backlog
#           unreadable) — nothing is deleted on a 2 · 64 usage
#
# WHY (2026-09-30, BACKLOG_MASTER land-truth.5). ship-land pins the head of every land that fails
# past its claim as `refs/land/failed/<utcstamp>-<sid>-<branch>`, and nothing ever removes one:
# 789 pins on 2026-08-17, 2,112 on 2026-09-30. The pins are evidence — the only durable copy of a
# failed land's head (scripts/ship-land.sh:819, scripts/stranded-sweep.sh:79) — so the bound must
# never cost one that still holds unlanded work.
#
# THE RULE. A pin is pruned iff ALL of:
#   * its name stamp is older than --min-age-days (14) — a young pin may still be re-landed;
#   * scripts/land-content-verify.sh answers 0 for it (every path landed by content, or trunk
#     DECLARES it superseded) — 1 (unlanded content) and 2 (cannot tell) both KEEP it;
#   * no OPEN backlog row names it — a row whose falsifier reads a pin would otherwise lose its
#     subject and answer 2 forever instead of retracting.
# A name with no parsable stamp is kept. The deletion is a compare-and-swap on the sha that was
# verified, so a pin re-written meanwhile survives.
#
# JOURNALED FIRST. Each deletion appends {ts, ref, sha, verdict} to the journal BEFORE the ref is
# removed; a journal that cannot be written deletes nothing. Restore any pin with
# `git update-ref <ref> <sha>` from its line (until `git gc` prunes the unreachable object, 2 weeks
# by default).
#
# --max bounds the verifies per pass (oldest first); the population drains over successive passes.
#
# Env seams: CC_LAND_GC_JOURNAL · CC_LAND_GC_BACKLOG_BIN (cc-backlog) · LAND_GC_LCV_BIN ·
#   LAND_GC_NOW (epoch, tests) · LAND_GC_FETCH=off (fixtures)
# bash 3.2-safe. NO `set -e`.
set -uo pipefail

_resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
SDIR="$(dirname "$SELF")"

DRY=0 MAX=300 MIN_AGE_D=14 REPO="" CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
JOURNAL="${CC_LAND_GC_JOURNAL:-${CFG%/}/autonomy/land-failed-gc.jsonl}"
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --max) MAX="${2:-}"; shift 2 ;;
    --min-age-days) MIN_AGE_D="${2:-}"; shift 2 ;;
    --repo) REPO="${2:-}"; shift 2 ;;
    --journal) JOURNAL="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,8p' "$SELF" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "land-failed-gc: unknown argument $1" >&2; exit 64 ;;
  esac
done
case "$MAX" in ''|*[!0-9]*) echo "land-failed-gc: --max needs a number" >&2; exit 64 ;; esac
case "$MIN_AGE_D" in ''|*[!0-9]*) echo "land-failed-gc: --min-age-days needs a number" >&2; exit 64 ;; esac

[ -n "$REPO" ] || REPO="$(git -C "$SDIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO" ] || ! git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  echo "land-failed-gc: no git repo resolved — cannot look; nothing deleted." >&2; exit 2
fi
LCV="${LAND_GC_LCV_BIN:-$SDIR/land-content-verify.sh}"
[ -f "$LCV" ] || { echo "land-failed-gc: $LCV missing — cannot verify; nothing deleted." >&2; exit 2; }
BL="${CC_LAND_GC_BACKLOG_BIN:-$(command -v cc-backlog 2>/dev/null || true)}"

TRUNK="$(git -C "$REPO" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')"
[ -n "$TRUNK" ] || TRUNK=main
if [ "${LAND_GC_FETCH:-on}" != off ]; then
  TO="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
  if [ -n "$TO" ]; then "$TO" 30 git -C "$REPO" fetch --quiet origin "$TRUNK" >/dev/null 2>&1
  else git -C "$REPO" fetch --quiet origin "$TRUNK" >/dev/null 2>&1; fi \
    || { echo "land-failed-gc: could not fetch origin/$TRUNK — a verdict off a stale trunk is no verdict; nothing deleted." >&2; exit 2; }
fi

# SINGLE-FLIGHT: a pass costs seconds per pin under load, so a second spawn while one runs would
# only double the verifies. A lock whose pid is dead is reclaimed.
LOCK="${CC_LAND_GC_LOCK:-${CFG%/}/autonomy/.land-failed-gc.lock}"
mkdir -p "$(dirname "$LOCK")" 2>/dev/null || true
if ! mkdir "$LOCK" 2>/dev/null; then
  _lp="$(head -1 "$LOCK/pid" 2>/dev/null)"
  if [ -n "$_lp" ] && kill -0 "$_lp" 2>/dev/null; then
    echo "land-failed-gc: another pass (pid $_lp) holds $LOCK — exiting."; exit 0
  fi
  rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null
  mkdir "$LOCK" 2>/dev/null || { echo "land-failed-gc: cannot take $LOCK — nothing deleted." >&2; exit 2; }
fi
printf '%s\n' "$$" > "$LOCK/pid" 2>/dev/null || true

TMP="$(mktemp -d "${TMPDIR:-/tmp}/land-failed-gc.XXXXXX" 2>/dev/null)" || { rm -f "$LOCK/pid"; rmdir "$LOCK"; echo "land-failed-gc: no scratch dir" >&2; exit 2; }
trap 'rm -rf "$TMP"; rm -f "$LOCK/pid" 2>/dev/null; rmdir "$LOCK" 2>/dev/null' EXIT

# Every string an OPEN row carries, one per line. Unreadable ⇒ the guard cannot run ⇒ delete nothing.
if [ -z "$BL" ] || ! "$BL" list --json 2>/dev/null \
     | jq -r '.[] | [.title, .falsifier, .run, .needs, .source, .dod_ref] | map(select(. != null)) | .[]' \
       > "$TMP/open" 2>/dev/null; then
  echo "land-failed-gc: open backlog rows unreadable — the row guard cannot run; nothing deleted." >&2; exit 2
fi

NOW="${LAND_GC_NOW:-$(date +%s)}"
CUT=$(( NOW - MIN_AGE_D * 86400 ))
stamp_epoch() {   # YYYYMMDDTHHMMSSZ → epoch on BSD and GNU date; empty if unparsable
  date -j -u -f '%Y%m%dT%H%M%SZ' "$1" +%s 2>/dev/null \
    || date -u -d "$(printf '%s' "$1" | sed -E 's/^(....)(..)(..)T(..)(..)(..)Z$/\1-\2-\3 \4:\5:\6/')" +%s 2>/dev/null
}

git -C "$REPO" for-each-ref --sort=refname --format='%(refname) %(objectname)' 'refs/land/failed/' > "$TMP/pins"
total="$(grep -c . "$TMP/pins" 2>/dev/null)" || total=0
[ "$DRY" = 1 ] || mkdir -p "$(dirname "$JOURNAL")" 2>/dev/null || true

ex=0 pruned=0 unl=0 cant=0 young=0 row=0 nostamp=0 jfail=0 deferred=0
while read -r ref sha; do
  [ -n "$ref" ] || continue
  name="${ref#refs/land/failed/}"; st="${name%%-*}"
  ep=""; case "$st" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]T[0-9][0-9][0-9][0-9][0-9][0-9]Z) ep="$(stamp_epoch "$st")" ;; esac
  if [ -z "$ep" ]; then nostamp=$((nostamp + 1)); continue; fi
  if [ "$ep" -gt "$CUT" ]; then young=$((young + 1)); continue; fi
  if grep -qF -- "$name" "$TMP/open" 2>/dev/null; then row=$((row + 1)); continue; fi
  # Sorted by name = by stamp, oldest first, so a bounded pass always works the oldest end.
  if [ "$ex" -ge "$MAX" ]; then deferred=$((deferred + 1)); continue; fi
  ex=$((ex + 1))
  out="$(bash "$LCV" "$ref" --repo "$REPO" --trunk "$TRUNK" --no-fetch 2>&1)"; rc=$?
  case "$rc" in
    0) ;;
    1) unl=$((unl + 1)); continue ;;
    *) cant=$((cant + 1)); continue ;;
  esac
  if [ "$DRY" = 1 ]; then pruned=$((pruned + 1)); continue; fi
  line="$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg r "$ref" --arg s "$sha" \
            --arg v "$(printf '%s\n' "$out" | head -1 | cut -c1-300)" \
            '{ts:$ts, event:"pruned", ref:$r, sha:$s, verdict:$v}')" || line=""
  if [ -z "$line" ] || ! printf '%s\n' "$line" >> "$JOURNAL" 2>/dev/null; then
    jfail=$((jfail + 1)); echo "land-failed-gc: journal $JOURNAL not writable — $ref KEPT" >&2; continue
  fi
  if git -C "$REPO" update-ref -d "$ref" "$sha" 2>/dev/null; then
    pruned=$((pruned + 1))
  else
    jq -cn --arg r "$ref" --arg s "$sha" '{event:"delete-failed", ref:$r, sha:$s}' >> "$JOURNAL" 2>/dev/null || true
  fi
done < "$TMP/pins"

left="$(git -C "$REPO" for-each-ref 'refs/land/failed/' | grep -c .)" || left=0
printf 'land-failed-gc: pins=%s examined=%s pruned-landed=%s kept-unlanded=%s kept-cannot-tell=%s kept-open-row=%s kept-young=%s kept-no-stamp=%s deferred=%s journal-fail=%s remaining=%s dry_run=%s\n' \
  "$total" "$ex" "$pruned" "$unl" "$cant" "$row" "$young" "$nostamp" "$deferred" "$jfail" "$left" "$DRY"
exit 0
