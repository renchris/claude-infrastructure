#!/usr/bin/env bash
# worktree-gc.sh — the sanctioned worktree janitor for claude-infrastructure.
#
# WHY THIS FILE EXISTS: `hooks/git-worktree-guard.sh` (:6, :40, :57) tells the operator three
# times to reap with `bash scripts/worktree-gc.sh --prune` ("gates on live-claude-cwd / lsof /
# idle>30m / .teammate-busy and KEEPS the branch"), and `hooks/live-session-registry.sh:2`
# calls itself "durable per-worktree liveness registry for worktree-gc". Both promises pointed
# at a file that was absent from the checkout, from origin/main and from all of history — so
# every blocked operator fell back to raw `git worktree remove` / `git branch -D`, which
# bypasses every gate the guard exists to enforce (worktree audit 2026-07-25, §8-E).
#
# SAFETY MODEL — a worktree is removed ONLY when ALL of these hold; any miss ⇒ KEEP + reason:
#   1. it is a linked worktree of THIS repo, read from `git worktree list --porcelain`
#      (NEVER a directory glob: ~/Development/.worktrees is SHARED ACROSS 5 REPOS and hosts
#      other repos' live sessions — audit §6, the highest-severity finding),
#   2. the directory exists and is not excluded (CC_WTGC_EXCLUDE) / locked / .teammate-busy,
#   3. `git status --porcelain` is empty (dirty ⇒ removal would need --force ⇒ data loss),
#   4. no live session: union of `cc-notify --list --json` cwds, live `claude` proc cwds
#      (lsof -d cwd), any process holding files open under it, and the live-session registry
#      PID — over-matching is SAFE here, it can only ever cause a KEEP,
#   5. idle > 30 min measured by the BRANCH TIP COMMITTER DATE, never directory mtime (a
#      `git status` sweep rewrites .git/worktrees/<n>/index, so admin-dir mtime is not a
#      freshness signal — audit §8-B),
#   6. the branch is LANDED by patch-equivalence: `git cherry <trunk> <branch>` has zero `+`
#      (catches the rebase/cherry-pick landing that plain ancestry misses).
# Removal is always `git worktree remove` — NEVER --force. Branch deletion is always
# `git branch -d` — NEVER -D. Those two refusals are git's own second gate on our evidence;
# a refusal is a KEEP, never something to force through (audit §8-H).
#
# Branches are KEPT by default (a vanished worktree must stay recoverable via its branch).
# --prune-branches deletes only landed, worktree-less, unprotected branches.
#
#   worktree-gc.sh                      # remove reapable worktrees, keep every branch
#   worktree-gc.sh --prune              # identical (the invocation git-worktree-guard.sh prints)
#   worktree-gc.sh --dry-run            # print the plan, mutate nothing
#   worktree-gc.sh --prune-branches     # also delete landed worktree-less branches (-d only)
#
# Env seams (all optional; the CC_WTGC_* bins exist so bats can fixture the oracles):
#   CC_WTGC_EXCLUDE       colon-separated paths never touched (also covers nested worktrees)
#   CC_WTGC_REPO          repo to sweep (default: the repo containing $PWD)
#   CC_WTGC_TRUNK         landedness base (default: origin/main)
#   CC_WTGC_IDLE_MIN      idle floor in minutes (default: 30)
#   CC_WTGC_CC_NOTIFY / CC_WTGC_LSOF / CC_WTGC_PGREP / CC_WTGC_JQ    oracle binaries
#   CC_WTGC_REGISTRY_DIR  live-session registry (default: ~/.reso/live-sessions)
#   CC_WTGC_LOCK          mutex dir (default: ~/.claude/state/worktree-gc.lock)
#
# bash 3.2-safe (macOS default): no associative arrays, no mapfile, no [[ -v ]].
set -uo pipefail

DRY_RUN=0
PRUNE_BRANCHES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n)      DRY_RUN=1 ;;
    --prune-branches)  PRUNE_BRANCHES=1 ;;
    --prune)           : ;;   # compat alias: the guard hook's advertised invocation == default
    -h|--help)
      sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "worktree-gc: unknown flag '$arg'" >&2
       echo "usage: worktree-gc.sh [--prune-branches] [--dry-run]" >&2
       exit 2 ;;
  esac
done

GIT_BIN="${CC_WTGC_GIT:-git}"
JQ_BIN="${CC_WTGC_JQ:-jq}"
LSOF_BIN="${CC_WTGC_LSOF:-lsof}"
PGREP_BIN="${CC_WTGC_PGREP:-pgrep}"
CC_NOTIFY_BIN="${CC_WTGC_CC_NOTIFY:-$HOME/.claude/bin/cc-notify}"
REGISTRY_DIR="${CC_WTGC_REGISTRY_DIR:-$HOME/.reso/live-sessions}"
TRUNK="${CC_WTGC_TRUNK:-origin/main}"
IDLE_MIN="${CC_WTGC_IDLE_MIN:-30}"
LOCK_DIR="${CC_WTGC_LOCK:-$HOME/.claude/state/worktree-gc.lock}"

MAIN="$("$GIT_BIN" -C "${CC_WTGC_REPO:-$PWD}" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$MAIN" ]; then
  echo "worktree-gc: not inside a git repository (set CC_WTGC_REPO)" >&2
  exit 2
fi
# Always drive off the MAIN checkout, even when invoked from a linked worktree.
MAIN="$("$GIT_BIN" -C "$MAIN" rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's#/\.git$##')"
[ -d "$MAIN" ] || MAIN="$("$GIT_BIN" -C "${CC_WTGC_REPO:-$PWD}" rev-parse --show-toplevel)"

# canon <path> — resolve symlinks and fold /private/tmp → /tmp so cc-notify cwds, lsof output
# and the worktree registry compare on one canonical form (macOS /tmp is a symlink).
canon() {
  local p="${1:-}" r
  [ -n "$p" ] || return 0
  r="$(cd "$p" 2>/dev/null && pwd -P)" || r=""
  [ -n "$r" ] && p="$r"
  case "$p" in /private/tmp/*) p="/tmp/${p#/private/tmp/}" ;; esac
  printf '%s' "$p"
}

# ── Mutex: serialize every MUTATING pass (audit §8-D — cc-reaper:267, desk-land.sh,
#    lr-fire-resume.sh, teammate-auto-shutdown.sh and the guard hook all remove/prune too;
#    concurrent worktree mutation is the GH #34645/#48927 data-loss class). ────────────
LOCK_HELD=0
# shellcheck disable=SC2329  # invoked indirectly via `trap cleanup EXIT` (shellcheck can't see traps)
cleanup() { [ "$LOCK_HELD" = "1" ] && rmdir "$LOCK_DIR" 2>/dev/null; rm -f "$REMOVED_BR" 2>/dev/null; }
REMOVED_BR="${TMPDIR:-/tmp}/worktree-gc.removed.$$"
trap cleanup EXIT
if [ "$DRY_RUN" = "0" ]; then
  mkdir -p "$(dirname "$LOCK_DIR")" 2>/dev/null
  if mkdir "$LOCK_DIR" 2>/dev/null; then
    LOCK_HELD=1
  else
    # Break a lock left behind by a crashed pass (>60 min), never a live one.
    if [ -d "$LOCK_DIR" ] && [ -n "$(find "$LOCK_DIR" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
      rmdir "$LOCK_DIR" 2>/dev/null
      mkdir "$LOCK_DIR" 2>/dev/null && LOCK_HELD=1
    fi
    if [ "$LOCK_HELD" = "0" ]; then
      echo "worktree-gc: another pass holds $LOCK_DIR — skipping (no concurrent worktree mutation)."
      exit 0
    fi
  fi
fi
: > "$REMOVED_BR"

# ── Liveness oracles, computed once. ─────────────────────────────────────────────────
# (a) registered sessions — cc-notify --list --json emits LIVE rows only (pid alive + pane present)
NOTIFY_CWDS=""
ORACLES=0
if [ -x "$CC_NOTIFY_BIN" ] && command -v "$JQ_BIN" >/dev/null 2>&1; then
  if NOTIFY_RAW="$("$CC_NOTIFY_BIN" --list --json 2>/dev/null)"; then
    NOTIFY_CWDS="$(printf '%s' "$NOTIFY_RAW" | "$JQ_BIN" -r '.[]?.cwd // empty' 2>/dev/null)"
    ORACLES=$((ORACLES + 1))
  fi
fi
# (b) process-level cwd sweep — catches panes that never registered (session-register.sh was
#     only wired ~2026-07-18 and SessionStart is write-once: memory reaper-blindness-...).
CLAUDE_CWDS=""
if command -v "$PGREP_BIN" >/dev/null 2>&1 && command -v "$LSOF_BIN" >/dev/null 2>&1; then
  ORACLES=$((ORACLES + 1))
  for cpid in $("$PGREP_BIN" -f claude 2>/dev/null | sort -u); do
    CLAUDE_CWDS="$CLAUDE_CWDS
$("$LSOF_BIN" -a -p "$cpid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
  done
fi
LIVE_CWDS="$(printf '%s\n%s\n' "$NOTIFY_CWDS" "$CLAUDE_CWDS" | while IFS= read -r c; do
  [ -n "$c" ] || continue
  printf '%s\n' "$(canon "$c")"
done | sort -u)"
if [ "$ORACLES" = "0" ] && [ "$DRY_RUN" = "0" ]; then
  echo "worktree-gc: no liveness oracle available (cc-notify + jq absent AND pgrep/lsof absent)."
  echo "worktree-gc: cannot prove a worktree is idle ⇒ refusing to remove anything. Re-run with --dry-run to inspect."
  exit 3
fi

is_live_cwd() { printf '%s\n' "$LIVE_CWDS" | grep -qxF "$1"; }

registry_live() { # <basename> <canon-path> → 0 iff a registered session PID is still alive here
  local base="$1" path="$2" row pid rcwd
  [ -f "$REGISTRY_DIR/$base" ] || return 1
  row="$(cat "$REGISTRY_DIR/$base" 2>/dev/null)"
  pid="$(printf '%s' "$row" | cut -f1)"
  rcwd="$(printf '%s' "$row" | cut -f3)"
  case "${pid:-}" in ''|*[!0-9]*) return 1 ;; esac
  kill -0 "$pid" 2>/dev/null || return 1
  # A bare basename can collide across the 5 repos sharing ~/Development/.worktrees (audit §6):
  # only honour the row when its recorded cwd is this worktree (or was never recorded).
  [ -z "$rcwd" ] && return 0
  [ "$(canon "$rcwd")" = "$path" ]
}

landed() { # <branch> → 0 iff every commit since the merge-base is on the trunk by patch-id
  local br="$1" out
  "$GIT_BIN" -C "$MAIN" rev-parse --verify --quiet "$TRUNK" >/dev/null 2>&1 || return 1
  out="$("$GIT_BIN" -C "$MAIN" cherry "$TRUNK" "$br" 2>/dev/null)" || return 1
  ! printf '%s\n' "$out" | grep -q '^+'
}

excluded() { # <canon-path> → 0 iff hard-excluded by CC_WTGC_EXCLUDE (exact or ancestor)
  local p="$1" e rest="${CC_WTGC_EXCLUDE:-}"
  [ -n "$rest" ] || return 1
  while [ -n "$rest" ]; do
    e="${rest%%:*}"
    if [ "$rest" = "$e" ]; then rest=""; else rest="${rest#*:}"; fi
    [ -n "$e" ] || continue
    e="$(canon "$e")"
    [ "$p" = "$e" ] && return 0
    case "$p" in "$e"/*) return 0 ;; esac
  done
  return 1
}

protected_branch() { # never deleted, whatever the evidence says
  case "$1" in
    main|master)                            return 0 ;;
    ship/backup-*|backup/*|*-prerebase-backup) return 0 ;;
  esac
  return 1
}

N_REMOVED=0; N_KEPT=0; N_BR_DELETED=0; N_REFUSED=0
PREFIX=""; [ "$DRY_RUN" = "1" ] && PREFIX="would "

# ── 1. Broken admin records (dir gone, .git link gone) — pure bookkeeping, zero content. ──
if [ "$DRY_RUN" = "1" ]; then
  PRUNABLE="$("$GIT_BIN" -C "$MAIN" worktree prune --dry-run -v 2>/dev/null)"
  [ -n "$PRUNABLE" ] && printf '%s\n' "$PRUNABLE" | sed 's/^/would prune  /'
else
  "$GIT_BIN" -C "$MAIN" worktree prune -v 2>/dev/null | sed 's/^/prune  /'
fi

# ── 2. Per-worktree gates. Records come ONLY from git — never a directory listing. ───────
wt=""; br=""; detached=0; locked=0
process_record() {
  local path="$wt" branch="$br" base reason=""
  [ -n "$path" ] || return 0
  [ "$path" = "$MAIN" ] && return 0                       # never the primary checkout
  local cpath; cpath="$(canon "$path")"
  base="$(basename "$path")"

  if   excluded "$cpath";                                    then reason="hard-excluded (CC_WTGC_EXCLUDE)"
  elif [ ! -d "$path" ];                                     then reason="directory is gone (admin record only — 'git worktree prune' handles it)"
  elif [ "$locked" = "1" ];                                  then reason="locked worktree"
  elif [ -f "$path/.teammate-busy" ];                        then reason=".teammate-busy marker present"
  elif [ -n "$("$GIT_BIN" -C "$path" status --porcelain 2>/dev/null)" ]; then reason="dirty tree (removal would need --force ⇒ data loss)"
  elif is_live_cwd "$cpath";                                 then reason="LIVE — a registered session / running claude is cwd'd here"
  elif registry_live "$base" "$cpath";                       then reason="LIVE — live-session-registry PID still alive"
  elif command -v "$LSOF_BIN" >/dev/null 2>&1 && "$LSOF_BIN" -- "$path" 2>/dev/null | grep -q .; then
                                                                  reason="open by a live process"
  elif [ "$detached" = "1" ] || [ -z "$branch" ];            then reason="detached HEAD (manual review — no branch records where the work went)"
  else
    local tip now age
    tip="$("$GIT_BIN" -C "$MAIN" log -1 --format=%ct "$branch" 2>/dev/null)"
    now="$(date +%s)"
    case "${tip:-}" in ''|*[!0-9]*) tip="" ;; esac
    if [ -z "$tip" ]; then
      reason="branch tip date unreadable"
    else
      age=$(( (now - tip) / 60 ))
      if [ "$age" -lt "$IDLE_MIN" ]; then
        reason="branch tip is ${age}m old (< ${IDLE_MIN}m idle floor)"
      elif ! landed "$branch"; then
        local n; n="$("$GIT_BIN" -C "$MAIN" rev-list --count "$TRUNK..$branch" 2>/dev/null || echo '?')"
        reason="$n commit(s) not on $TRUNK by patch-id (unlanded — ship first)"
      fi
    fi
  fi

  if [ -n "$reason" ]; then
    echo "KEEP    $path [${branch:-detached}] — $reason"
    N_KEPT=$((N_KEPT + 1))
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    echo "${PREFIX}remove  $path [$branch] — clean · idle · landed on $TRUNK"
    N_REMOVED=$((N_REMOVED + 1))
    printf '%s\n' "$branch" >> "$REMOVED_BR"
    return 0
  fi
  # NEVER --force: git's refusal is the second gate on our evidence.
  if "$GIT_BIN" -C "$MAIN" worktree remove "$path" 2>/dev/null; then
    echo "remove  $path [$branch] — clean · idle · landed on $TRUNK"
    N_REMOVED=$((N_REMOVED + 1))
    printf '%s\n' "$branch" >> "$REMOVED_BR"
  else
    echo "KEEP    $path [$branch] — git REFUSED 'worktree remove' (it changed since the gates ran)"
    N_KEPT=$((N_KEPT + 1)); N_REFUSED=$((N_REFUSED + 1))
  fi
}

while IFS= read -r line; do
  case "$line" in
    "worktree "*) wt="${line#worktree }"; br=""; detached=0; locked=0 ;;
    "branch refs/heads/"*) br="${line#branch refs/heads/}" ;;
    "detached") detached=1 ;;
    "locked"|"locked "*) locked=1 ;;
    "") process_record; wt=""; br=""; detached=0; locked=0 ;;
  esac
done < <({ "$GIT_BIN" -C "$MAIN" worktree list --porcelain 2>/dev/null; echo; })

# ── 3. Branches. KEPT by default; --prune-branches deletes only the provably redundant. ──
if [ "$PRUNE_BRANCHES" = "1" ]; then
  WT_BRANCHES="$("$GIT_BIN" -C "$MAIN" worktree list --porcelain 2>/dev/null | sed -n 's#^branch refs/heads/##p')"
  while IFS= read -r branch; do
    [ -n "$branch" ] || continue
    protected_branch "$branch" && continue
    # Still holding a worktree ⇒ never delete (git-worktree-guard.sh:35-44 blocks it too:
    # a vanished worktree must stay recoverable via its branch).
    if printf '%s\n' "$WT_BRANCHES" | grep -qxF "$branch"; then
      if grep -qxF "$branch" "$REMOVED_BR" 2>/dev/null; then
        echo "KEEP-BR $branch — worktree record still present"
      fi
      continue
    fi
    landed "$branch" || continue
    if [ "$DRY_RUN" = "1" ]; then
      echo "${PREFIX}delete  branch $branch — landed on $TRUNK, no worktree"
      N_BR_DELETED=$((N_BR_DELETED + 1))
      continue
    fi
    # NEVER -D: git's merged-check is the second gate; a refusal is a KEEP.
    if "$GIT_BIN" -C "$MAIN" branch -d "$branch" >/dev/null 2>&1; then
      echo "delete  branch $branch — landed on $TRUNK, no worktree"
      N_BR_DELETED=$((N_BR_DELETED + 1))
    else
      echo "KEEP-BR $branch — git REFUSED 'branch -d' (not merged into HEAD/upstream)"
      N_REFUSED=$((N_REFUSED + 1))
    fi
  done < <("$GIT_BIN" -C "$MAIN" for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)
fi

SUFFIX=""; [ "$DRY_RUN" = "1" ] && SUFFIX="   [DRY-RUN — nothing was mutated]"
echo "worktree-gc: removed $N_REMOVED worktree(s) · kept $N_KEPT · deleted $N_BR_DELETED branch(es) · $N_REFUSED refusal(s)$SUFFIX"
[ "$PRUNE_BRANCHES" = "0" ] && echo "worktree-gc: branches preserved (pass --prune-branches to delete landed, worktree-less ones)"
exit 0
