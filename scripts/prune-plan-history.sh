#!/bin/bash
# prune-plan-history.sh — keep-policy for the two-layer plan version store.
# Called daily from hooks/session-start.sh (background, non-blocking), beside prune-backups.sh.
#
# WHAT THIS SURFACE ACTUALLY IS. Audit 03 §1c lists `plan-history/plans` as "996 files / 524
# dirs, zero rm sites, accelerating" and prescribes keep-N-per-plan mirroring prune-backups.
# Measured on disk, that model does not fit: `~/.claude/plan-history` is a **git repo**
# (hooks/plan-version-commit.sh "Layer 2"), and `plans/` is its WORKING TREE — exactly one
# current file per plan basename (523 files / 13 MB), not N snapshots per plan. The audit's
# file/dir counts were `.git` internals. Deleting working-tree files there would destroy the
# browsable current snapshot and reclaim nothing, because every byte also lives in .git.
#
# So the keep-policy lands where it is meaningful:
#
#   Layer 1  ~/.claude/plan-versions/MANIFEST.jsonl — append-only, one line per plan version,
#            3,310 lines / 992 KB, no reader-side bound. THIS is the keep-N surface:
#            keep the newest KEEP_PER_PLAN entries per plan `.name`, plus drop anything past
#            MAX_AGE_DAYS. Both bounds apply; an entry survives only if it passes both.
#
#   Layer 2  ~/.claude/plan-history/.git — 3,305 commits, 12,710 packed + 492 LOOSE objects
#            (6.13 MiB of the 15 MB). `git gc` repacks the loose objects and prunes
#            unreachable ones past the same horizon. Reachable history is never touched:
#            history is the product here, and truncating it would be deleting the artifact
#            to save its index.
#
#   NOT pruned: `plans/` itself. Declared UNBOUNDED-BY-DESIGN in the growth-coverage SSOT with
#   that reason, rather than silently left uncovered.
#
# Env (tests): CC_PLAN_MANIFEST · CC_PLAN_HISTORY_REPO · CC_PLAN_KEEP_PER_PLAN
#   · CC_PLAN_MAX_AGE_DAYS · CC_PLAN_PRUNE_LOG.  bash-3.2 safe, no eval, never `set -e`.
set -uo pipefail

MANIFEST="${CC_PLAN_MANIFEST:-$HOME/.claude/plan-versions/MANIFEST.jsonl}"
REPO="${CC_PLAN_HISTORY_REPO:-$HOME/.claude/plan-history}"
KEEP="${CC_PLAN_KEEP_PER_PLAN:-10}"
MAX_AGE_DAYS="${CC_PLAN_MAX_AGE_DAYS:-90}"
LOG="${CC_PLAN_PRUNE_LOG:-$HOME/.claude/logs/plan-history-prune.log}"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; }
case "${1:-}" in -h|--help) usage; exit 0 ;; esac

command -v jq >/dev/null 2>&1 || { echo "prune-plan-history: jq required" >&2; exit 0; }
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
say() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG" 2>/dev/null || true; }

# ── concurrency guard (the proven prune-backups.sh shape) ─────────────────────────────────────
LOCK_DIR="${TMPDIR:-/tmp}/.plan-history-prune.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  if [ -d "$LOCK_DIR" ] && [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +30 2>/dev/null)" ]; then
    rm -rf "$LOCK_DIR" 2>/dev/null; mkdir "$LOCK_DIR" 2>/dev/null || exit 0
  else
    exit 0
  fi
fi
trap 'rm -rf "$LOCK_DIR"' EXIT

# ── Layer 1: MANIFEST.jsonl — keep newest N per plan, and nothing past the age cap ────────────
manifest_before=0; manifest_after=0
if [ -f "$MANIFEST" ]; then
  manifest_before=$(wc -l < "$MANIFEST" | tr -d ' ')
  # Line count is captured BEFORE the filter so any record the hook appends mid-run can be
  # re-attached afterwards. This file is append-only and live; a tmp+mv that ignored the tail
  # would silently drop whatever was written during the rewrite.
  cutoff=$(date -u -v-"${MAX_AGE_DAYS}"d +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
        || date -u -d "-${MAX_AGE_DAYS} days" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)
  tmp="$(dirname "$MANIFEST")/.MANIFEST.$$.tmp"
  # One jq pass for the whole policy: group by plan `.name`, keep the newest KEEP by ts, then
  # drop what is past the cutoff, then restore the original file order (`__i`).
  #
  # ...with a FLOOR: the newest entry of every plan is always retained, even past the cutoff.
  # Without it the age cap alone erased 163 of 523 plans outright (measured), because their
  # last edit was in March — the index would stop knowing those plans ever existed while
  # `plans/<name>.md` and the full git history still hold them. A retention policy should
  # bound how much it keeps per subject, not silently forget the subject.
  #
  # `-R` + try/catch means one corrupt line cannot abort the pass and take the file with it.
  if jq -R -s -c --argjson keep "$KEEP" --arg cutoff "$cutoff" '
        [ splits("\n") | select(length > 0) | (try fromjson catch empty) ]
        | to_entries
        | map(.value.__i = .key | .value)
        | group_by(.name // "__unnamed")
        | map( sort_by(.ts // "") | reverse | .[0:$keep]
               | to_entries | map(.value + {__newest: (.key == 0)}) )
        | flatten
        | map(select(.__newest or ((.ts // "9999") >= $cutoff)))
        | sort_by(.__i)
        | map(del(.__i, .__newest))
        | .[]
      ' "$MANIFEST" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    # Re-attach anything appended while we were filtering.
    now_lines=$(wc -l < "$MANIFEST" | tr -d ' ')
    if [ "$now_lines" -gt "$manifest_before" ]; then
      tail -n "$((now_lines - manifest_before))" "$MANIFEST" >> "$tmp" 2>/dev/null || true
    fi
    mv -f "$tmp" "$MANIFEST" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    manifest_after=$(wc -l < "$MANIFEST" | tr -d ' ')
  else
    # Empty or unparseable output means "I could not compute the policy", never "keep nothing".
    rm -f "$tmp" 2>/dev/null
    manifest_after="$manifest_before"
    say "MANIFEST prune SKIPPED — filter produced no output (left $manifest_before lines intact)"
  fi
fi

# ── Layer 2: compact the plan-history git repo (loose objects + unreachable past the cap) ─────
gc_before=""; gc_after=""
if [ -d "$REPO/.git" ] && command -v git >/dev/null 2>&1; then
  gc_before=$(du -sk "$REPO/.git" 2>/dev/null | cut -f1)
  git -C "$REPO" gc --quiet --prune="${MAX_AGE_DAYS}.days.ago" >/dev/null 2>&1 || true
  gc_after=$(du -sk "$REPO/.git" 2>/dev/null | cut -f1)
fi

say "manifest ${manifest_before}->${manifest_after} lines (keep=$KEEP/plan, ${MAX_AGE_DAYS}d); .git ${gc_before:-n/a}K->${gc_after:-n/a}K"
echo "prune-plan-history: manifest ${manifest_before}->${manifest_after} lines; .git ${gc_before:-n/a}K->${gc_after:-n/a}K"
exit 0
