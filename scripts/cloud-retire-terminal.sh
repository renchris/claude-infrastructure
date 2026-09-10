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
# ── TWO MORE, ADDED 2026-09-05 — the strata that made the pile a fiction ────────────────────────
# Measured that day: 332 pending declarations resolved to 49 backlog items. 27 of those items were
# already `done` and held 137 declarations between them; of the 180 branches belonging to OPEN items,
# 128 could not rebase onto trunk (`git merge-tree`) and 52 could. The lane's "pile" was therefore
# ~19 pieces of collectable work wearing 332 rows, and the dispatcher's pile cap (50) read the 332,
# so it closed the lane to new fires while the return sweep spent its rotation re-examining rows
# whose answer was already terminal. Neither verdict deletes anything: a branch stays on origin for
# forensics, `cc-cloud gc` archives the declaration after 14 days, and the ROW is left exactly as the
# backlog has it — closed if it was closed, open (and re-dispatchable) if it was open.
#   superseded  the declaration's `item=` folds to `done` in the backlog. The row was closed by a
#               sibling branch or a local session; this branch is a second implementation of work
#               that is already on trunk, and landing it would be the loudest possible duplicate.
#               One `cc-backlog list --all --json` per pass answers it for every row (fail-OPEN: an
#               unreadable store yields no `superseded` at all).
#   conflict    the branch carries commits not on trunk AND `git merge-tree --write-tree <trunk>
#               <branch>` reports a conflict. The lander's rc 5 is the same fact reached after
#               minutes; it caches on the branch head, and a retired VM never pushes again, so the
#               row was held hostage forever (the dispatcher's already-declared gate refuses to
#               re-fire an item with a pending declaration). Retiring frees the row for a fresh
#               dispatch against the trunk that exists now, which is the only path that ever lands
#               such work. Age-gated like everything here; a young conflict is a VM still working.
#
# CUSTODY IS SETTLED WITH THE DECLARATION. Every dispatcher fire opens a custody debt keyed on the
# session id (467 open cloud debts measured 2026-09-05, all against cwd "/"), and nothing retired it.
# `landed` RETURNS it (the content reached trunk); `gone` / `superseded` / `conflict` ABANDON it with
# the verdict as the reason — nothing from that session reached trunk, so "returned" would be a lie
# the close certificate could read. Best-effort, never fatal to the retire itself.
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
#   CLOUD_RETIRE_GIT_BIN · CLOUD_RETIRE_CLOUD_BIN · CLOUD_RETIRE_BACKLOG_BIN · CLOUD_RETIRE_CUSTODY_BIN ·
#   CC_RETIRE_MIN_AGE_H · CC_RETIRE_MAX
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
BACKLOG_BIN="$(resolve "${CLOUD_RETIRE_BACKLOG_BIN:-}" cc-backlog "$ROOT/bin/cc-backlog" "$HOME/.claude/bin/cc-backlog")"
CUSTODY_BIN="$(resolve "${CLOUD_RETIRE_CUSTODY_BIN:-}" cc-custody "$ROOT/bin/cc-custody" "$HOME/.claude/bin/cc-custody")"

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

# ── THE BACKLOG STATUS MAP — one read per pass, fail-OPEN ───────────────────────────────────────
# `superseded` needs to know whether an item is done. One `list --all --json` (21.6 s measured on the
# live store under load) beats one `show` per row, and an unreadable store must produce NO verdict:
# an empty map means every `item_done` answers no and the pass behaves exactly as it did before this
# arm existed. Reading the store is the peer tool's job; this only consumes its fold.
STATUS_F="$(mktemp -t cloud-retire-status.XXXXXX 2>/dev/null || printf '/tmp/cloud-retire-status.%s' "$$")"
: >"$STATUS_F"
trap 'rm -f "$STATUS_F" 2>/dev/null' EXIT
if [ -n "$BACKLOG_BIN" ] && command -v jq >/dev/null 2>&1; then
  "$BACKLOG_BIN" list --all --json 2>/dev/null \
    | jq -r '.[]? | select((.id // "") != "") | [.id, (.status // "")] | @tsv' >"$STATUS_F" 2>/dev/null \
    || : >"$STATUS_F"
fi
[ -s "$STATUS_F" ] || printf 'cloud-retire-terminal: backlog status unreadable (no cc-backlog/jq, or an empty fold) — the superseded arm is SKIPPED this pass; nothing is retired on a guess.\n' >&2
item_done() { # <item> → 0 iff a 12-hex backlog id that folds to `done`
  case "$1" in
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) ;;
    *) return 1 ;;
  esac
  [ -s "$STATUS_F" ] || return 1
  [ "$(awk -F'\t' -v i="$1" '$1 == i { print $2; exit }' "$STATUS_F" 2>/dev/null)" = "done" ]
}

# `git merge-tree --write-tree` (≥ 2.38) answers "would this rebase conflict?" without a worktree.
# Probed once against the trunk itself: rc 0 means the verb exists; anything else disables the
# `conflict` arm for this pass rather than letting a usage error read as a verdict.
MT_OK=0
if [ "$FETCHED" = 1 ] && "$GIT_BIN" -C "$REPO" rev-parse --verify --quiet "$TRUNK" >/dev/null 2>&1 \
   && "$GIT_BIN" -C "$REPO" merge-tree --write-tree "$TRUNK" "$TRUNK" >/dev/null 2>&1; then MT_OK=1; fi

# THE REASON MUST CARRY THE BRANCH MEASUREMENT, NOT JUST THE VERDICT NAME (2026-09-09, adjudicating
# cc-backlog 95cbba839b44 — docs/research/custody-landing-backlog-2026-09-09.md). A custody discharge
# is written ONCE and can never be amended: cc-custody refuses a second discharge on a marker that is
# no longer open. So whatever this line says is the store's final word on that row, forever.
#
# `superseded` is the one verdict above that is NOT a measurement of the branch. `gone` reads the
# remote, `landed` reads `git cherry`, `conflict` reads `merge-tree`; `superseded` reads the BACKLOG
# ITEM's status and infers the branch's disposition from it. That inference — "the row was closed by
# a sibling, so this branch is a second implementation of work already on trunk" — is right most of
# the time and wrong exactly when a sibling landed PART of a commit, which is the case that costs
# something, because the part left behind is the part nobody wrote down. Measured over the 153 rows
# retired this way: 2 of the 3 genuine recoveries found in that adjudication came out of this class,
# and both were live defects in the landing and dispatch machinery (770569a15, f9c98cd1a).
#
# The arm is NOT disarmed and its verdict is NOT changed — it retires rows that would otherwise be
# re-examined on every cursor rotation, which is the cost its own header measures. What changes is
# that the reason now names the count of commits the branch carries that are NOT patch-equivalent on
# trunk, from the `git cherry` this pass has ALREADY run one screen above. Zero extra work, and it
# makes the two populations separately addressable in the store instead of indistinguishable:
#   "…retired: superseded (branch patch-equivalent)"        — nothing was left behind
#   "…retired: superseded (item closed; branch holds N unlanded commit(s))"  — N is the question
_settle_detail=""   # set beside the verdict; consumed and cleared by settle_custody
settle_custody() { # <decl-file> <verdict> — best-effort; the retire is the act, this is bookkeeping
  local marker why; marker="$(field "$1" custody)"
  why="cloud declaration retired: $2${_settle_detail:+ $_settle_detail}"
  _settle_detail=""
  [ -n "$marker" ] && [ -n "$CUSTODY_BIN" ] || return 0
  case "$2" in
    landed) "$CUSTODY_BIN" return  "$marker" >/dev/null 2>&1 || true ;;
    *)      "$CUSTODY_BIN" abandon "$marker" --why "$why" >/dev/null 2>&1 || true ;;
  esac
  return 0
}

now_s="$(date +%s)"
min_age_s=$(( MIN_AGE_H * 3600 ))
examined=0; gone=0; landed=0; superseded=0; conflict=0; kept=0; young=0; retired=0; failed=0

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
  item="$(field "$f" item)"
  if ! on_remote "$br"; then
    verdict=gone
  else
    if [ "$FETCHED" = 1 ] \
       && "$GIT_BIN" -C "$REPO" rev-parse --verify --quiet "refs/remotes/$REMOTE/$br" >/dev/null 2>&1 \
       && "$GIT_BIN" -C "$REPO" rev-parse --verify --quiet "$TRUNK" >/dev/null 2>&1; then
      # `git cherry <upstream> <head>` prints one line per commit: `+` = NOT on upstream by patch
      # id, `-` = equivalent. Zero `+` lines is the terminal verdict; a cherry that FAILS is not one
      # (rc non-zero leaves the count empty), so it falls through.
      ch="$("$GIT_BIN" -C "$REPO" cherry "$TRUNK" "refs/remotes/$REMOTE/$br" 2>/dev/null)" && {
        if [ -z "$(printf '%s\n' "$ch" | grep '^+' || true)" ]; then verdict=landed; fi
      }
    fi
    # `landed` outranks `superseded`: both are terminal, but only the first RETURNS custody.
    if [ -z "$verdict" ] && item_done "$item"; then
      verdict=superseded
      # `ch` is this branch's `git cherry` output, already computed above. An unreadable cherry
      # leaves it EMPTY, which is not the same fact as "zero unlanded commits" — so an unmeasured
      # branch says so rather than borrowing the healthy reading (lookup-miss-is-not-absence).
      if [ -n "${ch:-}" ]; then
        _n_unlanded="$(printf '%s\n' "$ch" | grep -c '^+' || true)"
        if [ "${_n_unlanded:-0}" -gt 0 ]; then
          _settle_detail="(item closed; branch holds $_n_unlanded unlanded commit(s) — NOT measured as landed)"
        else
          _settle_detail="(branch patch-equivalent on trunk)"
        fi
      else
        _settle_detail="(branch NOT measured — cherry unreadable this pass)"
      fi
    fi
    # `conflict` is asked last and only of a branch that carries real unlanded commits: rc 1 is a
    # conflict, rc 0 is clean (KEPT — that is the collectable work), anything else is not a verdict.
    if [ -z "$verdict" ] && [ "$MT_OK" = 1 ] && [ -n "${ch:-}" ]; then
      "$GIT_BIN" -C "$REPO" merge-tree --write-tree "$TRUNK" "refs/remotes/$REMOTE/$br" >/dev/null 2>&1; mt_rc=$?
      [ "$mt_rc" -eq 1 ] && verdict=conflict
    fi
    ch=""
  fi

  case "$verdict" in
    gone)       gone=$((gone + 1)) ;;
    landed)     landed=$((landed + 1)) ;;
    superseded) superseded=$((superseded + 1)) ;;
    conflict)   conflict=$((conflict + 1)) ;;
    *)          kept=$((kept + 1)); continue ;;
  esac

  if [ "$retired" -ge "$MAX" ]; then continue; fi
  if [ "$DRY" = 1 ]; then
    printf '  would retire %s (%s) — branch %s\n' "$id" "$verdict" "$br"
    retired=$((retired + 1))
    continue
  fi
  if "$CLOUD_BIN" retire --id "$id" --verdict "$verdict" >/dev/null 2>&1; then
    printf '  retired %s (%s) — branch %s\n' "$id" "$verdict" "$br"
    retired=$((retired + 1))
    settle_custody "$f" "$verdict"
  else
    printf '  RETIRE FAILED %s (%s)\n' "$id" "$verdict" >&2
    failed=$((failed + 1))
  fi
done

printf 'cloud-retire-terminal: examined=%d gone=%d landed=%d superseded=%d conflict=%d young-held=%d kept=%d retired=%d failed=%d dry_run=%d\n' \
  "$examined" "$gone" "$landed" "$superseded" "$conflict" "$young" "$kept" "$retired" "$failed" "$DRY"
exit 0
