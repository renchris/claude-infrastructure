#!/usr/bin/env bash
# browse-mirror-sync.sh — hold a human-browsable checkout at its upstream ref, forever.
#
# THE PROBLEM, STATED CORRECTLY. Every session in a high-volume repo runs in a worktree
# (~/.zshrc:_cc_route_check → scripts/new-worktree.sh), so the ORIGINAL checkout is never the
# thing anyone works in. It is still the thing a human opens in Cursor or Finder to read a file.
# Measured 2026-09-19, ~/Development/reso-management-app had been showing files 1,948 commits old.
#
# BUT THE REPOSITORY WAS NEVER STALE — only the CHECKOUT was. refs/remotes lives in the common
# git dir, so every fetch by any of that repo's 35 worktrees updates the root's `origin/main` too;
# root and wt-pool-1 both read 06ce6fee5 at the moment of measurement. The objects and the refs
# were current the whole time. What had never advanced was HEAD, and therefore the FILES.
#
# WHY IT HAD NEVER ADVANCED, AND WHY "just run git pull" is not the fix. Two independent wedges,
# both silent, both permanent once entered:
#
#   1. DIVERGENCE. The root's local `main` was 10 commits AHEAD (7 of them already on trunk under
#      a different sha, rebased by the land flow — `git cherry` prints those as `-`). `git pull
#      --ff-only` refuses a diverged branch, correctly, and says so into a terminal nobody was
#      watching. One accidental commit in the root checkout wedges the folder for good.
#   2. TOOLING DIRT. `next dev` REGENERATES a block in AGENTS.md (see that file's own
#      BEGIN:nextjs-agent-rules marker, written by next/dist/server/lib/generate-agent-files.js).
#      So "keep the browse checkout clean" is not a discipline any human can hold — the build tool
#      re-dirties it, and a dirty tree blocks a merge.
#
# THE SHAPE THAT CANNOT WEDGE. A mirror is held at a DETACHED HEAD, not on a local branch:
#
#   * Detached ⇒ divergence is structurally impossible. There is no local branch to commit onto,
#     so wedge (1) cannot recur. It is also the honest signal to a human who opens the folder:
#     git itself refuses to let you casually commit from a detached HEAD. "We never implement
#     against it" stops being a convention and becomes a property.
#   * Tracked modifications are ARCHIVED to a ref, then discarded. `git stash create` makes a real
#     commit object; we point refs/mirror-rescue/<ts> at it before `reset --hard`. Nothing is ever
#     lost — `git stash apply refs/mirror-rescue/<ts>` brings it back years later. Wedge (2) is
#     absorbed instead of blocking.
#   * UNTRACKED files are never touched and never forced over. We use a plain `git checkout
#     --detach`, never `-f`: if an untracked file sits where the target ref wants to write one,
#     git refuses, and we report `verdict=blocked` loudly rather than clobbering a human's file.
#     That is the one state a person must resolve, and it is the one state that stops the mirror —
#     by design, because the alternative is deleting bytes we did not write.
#
# WHY A LOCAL BRANCH IS STILL FAST-FORWARDED. Detaching leaves `refs/heads/main` behind, and a
# stale local `main` is a trap: `git log main` in the browse folder would answer with 2026-08
# history. So when the target ref is `origin/<X>` and a local `<X>` exists, is checked out in no
# worktree, and is a strict ANCESTOR of the target, we fast-forward it. Never a force: a diverged
# local branch is reported, not rewritten.
#
# FETCH POLICY. The mirror advance itself is free — it reads refs another session already fetched,
# which is why this is cheap enough to run on every ref change. A network fetch is rate-limited to
# CC_BROWSE_MIRROR_FETCH_MIN seconds (default 600). Both halves are needed: without the event-driven
# advance the folder lags by the poll interval, and without the periodic fetch a quiet fleet would
# leave the mirror pinned to a stale `origin/main` while reporting itself current — the exact
# silent-staleness failure this file exists to end.
#
# ADDING A REPO is one line in MIRRORS below: `<checkout path>|<ref>`.
#
# Kill switch (no unload needed):  touch ~/.claude/autonomy/browse-mirror.disabled

set -uo pipefail
PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH
export PATH

# CC_BROWSE_MIRRORS overrides the table. It exists so tests/browse-mirror-sync.bats can drive real
# throwaway repositories instead of stubbing git — the regimes that matter here (an untracked
# collision, a diverged local branch) are git's own refusals, and a stub cannot reproduce a refusal
# it does not implement.
MIRRORS="${CC_BROWSE_MIRRORS:-\
$HOME/Development/reso-management-app|origin/main
$HOME/Development/reso-management-app-release|origin/release}"

STATE_DIR="${CC_BROWSE_MIRROR_STATE:-$HOME/.claude/autonomy/browse-mirror}"
FETCH_MIN="${CC_BROWSE_MIRROR_FETCH_MIN:-600}"
DISABLED="${CC_BROWSE_MIRROR_DISABLED:-$HOME/.claude/autonomy/browse-mirror.disabled}"

DRY=0
case "${1:-}" in
  --dry-run) DRY=1 ;;
  --status)
    if [ -r "$STATE_DIR/status" ]; then cat "$STATE_DIR/status"; else echo "no run recorded"; fi
    exit 0 ;;
  --help|-h)
    sed -n '2,12p' "$0"; exit 0 ;;
  "") ;;
  *) echo "browse-mirror-sync: unknown argument: $1" >&2; exit 2 ;;
esac

if [ -e "$DISABLED" ]; then
  echo "verdict=disabled reason=$DISABLED"
  exit 0
fi

mkdir -p "$STATE_DIR" || exit 1

now()   { date +%s; }
ts()    { date -u +%Y%m%dT%H%M%SZ; }
short() { printf '%.9s' "$1"; }

# `timeout` is NOT a macOS binary — it arrives with Homebrew coreutils, so on a launchd job's own
# minimal PATH a bare `timeout` is simply not found. The original code wrote `timeout 180 git fetch
# … >/dev/null 2>&1`, which means the fetch would never have run AT ALL under launchd, silently, and
# the mirror would have been limited to whatever refs other sessions happened to fetch. Caught by
# scripts/unattended-path-lint.sh, which is exactly the class of defect it exists for.
# Same shape as scripts/deploy-live.sh: resolve absolutely, and degrade to unbounded rather than
# refusing to run.
_resolve_bin() { # <name…> → first executable absolute path
  local c n
  for n in "$@"; do
    c="$(command -v "$n" 2>/dev/null || true)"
    if [ -n "$c" ] && [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
    for c in "/opt/homebrew/bin/$n" "/usr/local/bin/$n"; do
      if [ -x "$c" ]; then printf '%s' "$c"; return 0; fi
    done
  done
  return 1
}
if [ -n "${CC_BROWSE_MIRROR_TIMEOUT_BIN+set}" ]; then TIMEOUT_BIN="$CC_BROWSE_MIRROR_TIMEOUT_BIN"
else TIMEOUT_BIN="$(_resolve_bin timeout gtimeout || true)"; fi

bounded() { # <secs> <cmd…> — rc 124 = OUR bound fired. Unbounded when there is no timeout(1).
  local secs="$1"; shift
  if [ -z "$TIMEOUT_BIN" ] || [ ! -x "$TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$TIMEOUT_BIN" -k 10 "$secs" "$@"
}

# The second bound, and it is not redundant: `bounded` degrades to UNBOUNDED with no timeout(1), and
# an unbounded fetch that hangs wedges this job permanently — launchd will not start a second
# instance while one runs, so the mirror would stop advancing and say nothing. reso's origin is SSH,
# so ConnectTimeout is what actually bounds the common hang, and it needs no external binary.
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o ConnectTimeout=20 -o BatchMode=yes}"

FETCH_STATE=cached

# Rate-limited network fetch, once per distinct repository (mirrors of one repo share a common dir).
fetch_if_stale() {
  local repo="$1" common key stamp age
  common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  key=$(printf '%s' "$common" | tr -c 'A-Za-z0-9' '-')
  stamp="$STATE_DIR/fetch.$key"
  if [ -r "$stamp" ]; then
    age=$(( $(now) - $(cat "$stamp" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$FETCH_MIN" ] && return 0
  fi
  # A dry run DOES fetch. The fetch touches only remote-tracking refs, never the working tree, and
  # it is how a dry run learns what WOULD happen — skipping it made `--dry-run` answer `current`
  # against a ref it had not refreshed, which is the one answer a dry run must never give wrongly.
  # It does not write the stamp, so a dry run can never starve the next real run of its fetch.
  if bounded 180 git -C "$repo" fetch --quiet --prune origin >/dev/null 2>&1; then
    FETCH_STATE=ok
  else
    # A failed fetch is NOT fatal — the mirror still advances to whatever refs are already local,
    # which is usually current because sibling worktrees fetch constantly. But it must be VISIBLE:
    # a mirror that has silently lost the network would otherwise keep reporting `current` forever,
    # which is the failure this whole script exists to end, re-entering through the back door.
    FETCH_STATE=failed
  fi
  [ "$DRY" = 1 ] && return 0
  now > "$stamp"
}

# Fast-forward the local branch matching an origin/<X> target, when that is provably safe.
ff_local_branch() {
  local repo="$1" ref="$2" target="$3" br
  case "$ref" in origin/*) br="${ref#origin/}" ;; *) return 0 ;; esac
  git -C "$repo" show-ref --verify --quiet "refs/heads/$br" || return 0
  # Checked out in any worktree ⇒ not ours to move.
  #
  # NOT `grep -qx`. Under `set -o pipefail`, -q exits the instant it matches, the producer takes
  # SIGPIPE, and the PIPELINE's status is that failure — so the condition reads FALSE on a MATCH
  # and we would fast-forward a branch someone has checked out. That is the one write in this
  # script that could disturb another worktree, and the reso repo has 36 of them, so the producer
  # is long and `main` sorts near the top: the match is exactly the case that races. Dropping -q
  # makes grep drain its input, which is cheap here and removes the race entirely.
  if git -C "$repo" worktree list --porcelain 2>/dev/null | grep -x "branch refs/heads/$br" >/dev/null; then
    return 0
  fi
  # Only ever a fast-forward. A diverged local branch is reported, never rewritten.
  if ! git -C "$repo" merge-base --is-ancestor "refs/heads/$br" "$target" 2>/dev/null; then
    echo "  note: local branch '$br' has diverged from $ref — left untouched"
    return 0
  fi
  [ "$DRY" = 1 ] && return 0
  git -C "$repo" update-ref "refs/heads/$br" "$target" \
    -m "browse-mirror: fast-forward to $ref"
}

sync_one() {
  local path="$1" ref="$2" head target rescue="-" stash
  if [ ! -e "$path/.git" ]; then
    echo "mirror=$path verdict=missing ref=$ref"
    return 1
  fi
  fetch_if_stale "$path"
  target=$(git -C "$path" rev-parse --verify --quiet "${ref}^{commit}") || {
    echo "mirror=$path verdict=no-such-ref ref=$ref"
    return 1
  }
  head=$(git -C "$path" rev-parse --verify HEAD 2>/dev/null || echo none)

  if [ "$head" = "$target" ]; then
    ff_local_branch "$path" "$ref" "$target"
    echo "mirror=$path verdict=current ref=$ref at=$(short "$target") fetch=$FETCH_STATE"
    return 0
  fi

  if [ "$DRY" = 1 ]; then
    echo "mirror=$path verdict=would-advance ref=$ref from=$(short "$head") to=$(short "$target") fetch=$FETCH_STATE"
    return 0
  fi

  # Archive tracked modifications (staged or not) to a permanent ref, then clear them.
  if [ -n "$(git -C "$path" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    stash=$(git -C "$path" stash create "browse-mirror rescue before advancing to $ref" 2>/dev/null)
    if [ -n "$stash" ]; then
      rescue="refs/mirror-rescue/$(ts)"
      git -C "$path" update-ref "$rescue" "$stash" \
        -m "browse-mirror: local modifications archived before advancing to $ref"
    fi
    if ! git -C "$path" reset --hard --quiet HEAD; then
      echo "mirror=$path verdict=blocked reason=reset-failed rescued=$rescue fetch=$FETCH_STATE"
      return 1
    fi
  fi

  # No -f: an untracked file in the way is a human's file, and stopping is the correct answer.
  if ! git -C "$path" checkout --detach --quiet "$target" 2>"$STATE_DIR/last-error"; then
    echo "mirror=$path verdict=blocked ref=$ref from=$(short "$head") to=$(short "$target") rescued=$rescue fetch=$FETCH_STATE"
    sed 's/^/  git: /' "$STATE_DIR/last-error" >&2
    return 1
  fi

  ff_local_branch "$path" "$ref" "$target"
  echo "mirror=$path verdict=advanced ref=$ref from=$(short "$head") to=$(short "$target") rescued=$rescue fetch=$FETCH_STATE"
  return 0
}

rc=0
out=$(
  while IFS='|' read -r path ref; do
    [ -z "${path:-}" ] && continue
    case "$path" in \#*) continue ;; esac
    sync_one "$path" "$ref" || echo "__FAIL__"
  done <<< "$MIRRORS"
)
printf '%s\n' "$out" | grep -v '^__FAIL__$'
# A shell pattern match, not a pipe. `printf | grep -q` is the same pipefail/SIGPIPE trap as above
# and it fails in the worse direction: a FAILING mirror would read as success, which is precisely
# the silently-stale outcome this whole script exists to prevent. $out is already in memory, so
# there is nothing to stream.
case $'\n'"$out"$'\n' in
  *$'\n'__FAIL__$'\n'*) rc=1 ;;
esac

{
  echo "# browse-mirror-sync $(date -u +%Y-%m-%dT%H:%M:%SZ) rc=$rc"
  printf '%s\n' "$out" | grep -v '^__FAIL__$'
} > "$STATE_DIR/status"

exit "$rc"
