#!/usr/bin/env bash
# cloud-retire-terminal.sh — retire the declarations that can never return anything, so they leave
# the return sweep's working set instead of being re-examined forever.
#
# ── WHY (measured 2026-09-04, docs/research/backlog-zero-2026-09-04/cloud-lane.md §2) ────────────
# 547 managed declarations, 543 of them pending, growing +23.5/day against 1.3 returns/day — a
# ~400-day drain horizon. But 33% of that pile (183 rows) has NO BRANCH ON ORIGIN AT ALL, and a
# further ~22% of the branches that do exist are already content-on-trunk. Neither stratum can ever
# produce a return, and both are re-read on every cursor rotation (~1.4 d), so the sweep spends its
# per-tick limit on rows whose answer is already terminal. `cc-cloud gc` cannot reach them: it
# archives declarations that are ALREADY retired and retires none itself. Nothing did.
#
# ── THE TWO TERMINAL VERDICTS, AND WHY EACH IS TERMINAL ─────────────────────────────────────────
#   gone    the declared branch is absent from the remote's head list. A cloud session returns by
#           pushing to that branch; a branch that does not exist is one nothing can push to and
#           nothing can land from. Either it was never created, or it was pruned after landing —
#           and `bin/cc-cloud`'s state function already treats the second case as LANDED (C3
#           precedes C1) from the path set the pruner fills before deleting. Retiring does not
#           change either reading: `id_for_item`/`ids_for_branch` deliberately keep serving retired
#           declarations, so the forensic answer survives (bin/cc-cloud § gc).
#   landed  every commit on the branch is patch-equivalent on the trunk. `git cherry`, never
#           ancestry — ship-land rebases before it pushes, so a branch whose bytes are verbatim on
#           main still reads "not merged" (scripts/branch-prune-landed.sh header, measured 1 of 97
#           by ancestry vs 56 by patch id).
#
# ── WHAT IT REFUSES TO DO ───────────────────────────────────────────────────────────────────────
#   · It NEVER deletes a branch, a declaration or a byte. Its only write is `cc-cloud retire`, which
#     drops one `<id>.retired` marker. `cc-cloud gc` archives those 14 days later; nothing here does.
#   · It refuses to act on a declaration younger than CC_RETIRE_MIN_AGE_H (default 6 h). A session
#     fired four minutes ago has no branch on origin YET, and "not created yet" is the same
#     observation as "never created" — the age is what separates them. Without this the pass would
#     retire every fire the moment it was declared.
#   · AN EMPTY HEAD LIST IS A SENSOR FAILURE, NOT AN EMPTY REMOTE. A remote answering with zero
#     heads while the store holds hundreds of declarations would retire all of them on one bad
#     read. It exits 69 instead — the same "cannot look is not nothing to see" rule
#     `cloud-reconcile.sh` takes at its own `candidates()` (memory: lookup-miss-is-not-absence).
#   · If the fetch fails the patch-equivalence arm is SKIPPED entirely rather than run against stale
#     remote-tracking refs: a ref that has not been updated since the branch advanced would report
#     "already on trunk" about content that is not.
#
# Usage:  cloud-retire-terminal.sh [--dry-run] [--max N] [--trunk <ref>]
# Exits:  0 ok · 2 usage · 3 a required tool is missing · 69 SENSOR FAILED (never read as absence)
#
# Env seams: CC_CLOUD_STATE · CLOUD_RETIRE_REPO · CLOUD_RETIRE_REMOTE · CLOUD_RETIRE_TRUNK ·
#   CLOUD_RETIRE_GIT_BIN · CLOUD_RETIRE_CLOUD_BIN · CC_RETIRE_MIN_AGE_H · CC_RETIRE_MAX
# bash 3.2-safe (no declare -A / mapfile).
set -uo pipefail

DEFAULT_SHARED="$HOME/Development/claude-infrastructure"
REPO="${CLOUD_RETIRE_REPO:-$DEFAULT_SHARED}"
REMOTE="${CLOUD_RETIRE_REMOTE:-origin}"
GIT_BIN="${CLOUD_RETIRE_GIT_BIN:-git}"
TRUNK="${CLOUD_RETIRE_TRUNK:-origin/main}"
STATE="${CC_CLOUD_STATE:-$HOME/.claude/autonomy/cloud}"
MIN_AGE_H="${CC_RETIRE_MIN_AGE_H:-6}"; case "$MIN_AGE_H" in ''|*[!0-9]*) MIN_AGE_H=6 ;; esac
MAX="${CC_RETIRE_MAX:-200}";           case "$MAX"       in ''|*[!0-9]*) MAX=200 ;; esac
DRY=0

# 🚨 RESOLVE $0 THROUGH ITS SYMLINKS BEFORE DERIVING A ROOT FROM IT. ~/.claude/scripts/ is a set of
# per-file symlinks into the checkout, so an unresolved `dirname "$0"/..` is ~/.claude — which has a
# bin/ and would therefore find A cc-cloud, just never this checkout's. The canonical loop is
# `_resolve_self()` in scripts/ship-land.sh; no `readlink -f`, which is GNU-only and this box is BSD.
_resolve_self() {  # <path> → absolute path, every symlink hop resolved (bash 3.2 / POSIX-safe)
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd "$(dirname "$p")" && pwd)"
    p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s/%s\n' "$(cd "$(dirname "$p")" && pwd)" "$(basename "$p")"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]:-$0}")"
ROOT="$(cd "$(dirname "$SELF")/.." 2>/dev/null && pwd)" || ROOT=""
resolve() { # <override> <name> <fallback-path…>
  local ov="$1" name="$2"; shift 2
  [ -n "$ov" ] && { printf '%s' "$ov"; return 0; }
  local c
  for c in "$@" "$(command -v "$name" 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 0
}
CLOUD_BIN="$(resolve "${CLOUD_RETIRE_CLOUD_BIN:-}" cc-cloud "$ROOT/bin/cc-cloud" "$HOME/.claude/bin/cc-cloud")"

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --max)     MAX="${2:?--max needs a count}"; shift 2 ;;
    --trunk)   TRUNK="${2:?--trunk needs a ref}"; shift 2 ;;
    -h|--help) sed -n '2,48p' "$0"; exit 0 ;;
    *) printf 'cloud-retire-terminal: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done
case "$MAX" in ''|*[!0-9]*) printf 'cloud-retire-terminal: --max must be a non-negative integer\n' >&2; exit 2 ;; esac

[ -n "$CLOUD_BIN" ] || { printf 'cloud-retire-terminal: cc-cloud not found — the declaration store has no verbs\n' >&2; exit 3; }
[ -d "$STATE" ]     || { printf 'cloud-retire-terminal: no declaration store at %s — nothing to do.\n' "$STATE"; exit 0; }
"$GIT_BIN" -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || {
  printf 'cloud-retire-terminal: %s is not a git repo — cannot ask about branches.\n' "$REPO" >&2; exit 3; }

field() { sed -n "s/^$2=//p" "$1" 2>/dev/null | head -1; }

# ── THE SENSOR, AND ITS FAIL-CLOSED ARM ─────────────────────────────────────────────────────────
HEADS="$("$GIT_BIN" -C "$REPO" ls-remote --heads "$REMOTE" 2>/dev/null)" || {
  printf 'cloud-retire-terminal: SENSOR FAILED — could not read %s (ls-remote). This is "cannot look", NOT "no branches": nothing retired.\n' "$REMOTE" >&2
  exit 69; }
HEADS="$(printf '%s\n' "$HEADS" | sed -n 's#^[0-9a-f]*[[:space:]]*refs/heads/##p')"
if [ -z "$HEADS" ]; then
  printf 'cloud-retire-terminal: SENSOR FAILED — %s reported ZERO heads. A remote with no branches at all is a read we will not act on: retiring on it would retire the whole store.\n' "$REMOTE" >&2
  exit 69
fi

FETCHED=1
"$GIT_BIN" -C "$REPO" fetch "$REMOTE" --prune --quiet >/dev/null 2>&1 || FETCHED=0
[ "$FETCHED" = 1 ] || printf 'cloud-retire-terminal: fetch failed — the patch-equivalence arm is SKIPPED (stale tracking refs cannot answer it); the branch-absence arm still runs off the live ls-remote.\n' >&2

now_s="$(date +%s)"
min_age_s=$(( MIN_AGE_H * 3600 ))
examined=0; gone=0; landed=0; kept=0; young=0; retired=0; failed=0

on_remote() { # <branch> → 0 present
  printf '%s\n' "$HEADS" | grep -qxF "$1"
}

for f in "$STATE"/*.decl; do
  [ -f "$f" ] || continue
  b="${f##*/}"; id="${b%.decl}"
  # TERMINAL ALREADY — the two markers the store uses for "this session is answered".
  [ -f "$STATE/$id.returned" ] && continue
  [ -f "$STATE/$id.retired" ]  && continue
  examined=$((examined + 1))

  br="$(field "$f" branch)"
  [ -n "$br" ] || { kept=$((kept + 1)); continue; }

  dat="$(field "$f" declared_at)"; case "$dat" in ''|*[!0-9]*) dat=0 ;; esac
  if [ "$dat" -gt 0 ] && [ $(( now_s - dat )) -lt "$min_age_s" ]; then
    young=$((young + 1)); continue
  fi

  verdict=""
  if ! on_remote "$br"; then
    verdict=gone
  elif [ "$FETCHED" = 1 ]; then
    if "$GIT_BIN" -C "$REPO" rev-parse --verify --quiet "refs/remotes/$REMOTE/$br" >/dev/null 2>&1 \
       && "$GIT_BIN" -C "$REPO" rev-parse --verify --quiet "$TRUNK" >/dev/null 2>&1; then
      # `git cherry <upstream> <head>` prints one line per commit: `+` = NOT on upstream by patch
      # id, `-` = equivalent. Zero `+` lines is the terminal verdict; a cherry that FAILS is not one
      # (rc non-zero leaves the count empty), so it falls through to `kept`.
      ch="$("$GIT_BIN" -C "$REPO" cherry "$TRUNK" "refs/remotes/$REMOTE/$br" 2>/dev/null)" && {
        if [ -z "$(printf '%s\n' "$ch" | grep '^+' || true)" ]; then verdict=landed; fi
      }
    fi
  fi

  case "$verdict" in
    gone)   gone=$((gone + 1)) ;;
    landed) landed=$((landed + 1)) ;;
    *)      kept=$((kept + 1)); continue ;;
  esac

  if [ "$retired" -ge "$MAX" ]; then continue; fi
  if [ "$DRY" = 1 ]; then
    printf '  would retire %s (%s) — branch %s\n' "$id" "$verdict" "$br"
    retired=$((retired + 1))
    continue
  fi
  if "$CLOUD_BIN" retire --id "$id" >/dev/null 2>&1; then
    printf '  retired %s (%s) — branch %s\n' "$id" "$verdict" "$br"
    retired=$((retired + 1))
  else
    printf '  RETIRE FAILED %s (%s)\n' "$id" "$verdict" >&2
    failed=$((failed + 1))
  fi
done

printf 'cloud-retire-terminal: examined=%d gone=%d landed=%d young-held=%d kept=%d retired=%d failed=%d dry_run=%d\n' \
  "$examined" "$gone" "$landed" "$young" "$kept" "$retired" "$failed" "$DRY"
exit 0
