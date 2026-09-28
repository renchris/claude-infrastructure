#!/usr/bin/env bash
# memory-store-snapshot.sh — local, never-pushed git history for ONE memory store, kept OUTSIDE it.
#
# Idea: arXiv 2605.04897 / TrueMemory; independent implementation, no TrueMemory code.
# Design: docs/research/truememory-2026-09-27.md § 3.11 (local-store-history).
#
# ── WHY ──────────────────────────────────────────────────────────────────────────────────────
# None of the ~39 physical memory stores had any undo. restic covers only archives/claude-code,
# the Time Machine destination does not mount, and backup-before-write sees only Write overwrites
# (0 memory backups on disk when measured). Meanwhile three actors mutate stores: the rotor
# (bin/cc-memory-rotate), /compact-memory, and Claude Code's own background passes, which can Edit,
# Write and `rm -f` any `.md` in a store with no settings opt-out. This takes a pre-image before
# the first two act, and at every SessionStart for the third, so every mutation has a restore point
# at most one session old.
#
# ── THE GITDIR LIVES OUTSIDE THE STORE ───────────────────────────────────────────────────────
#   ${CC_MEMORY_HISTORY_ROOT:-$HOME/.local/state/cc-memory-history}/<physical-slug>.git
# A `.git` inside the store would ride the config-mirror rsync and contend on `index.lock` with
# every other writer; outside it, the store stays byte-identical. The slug is the store's PHYSICAL
# path (`pwd -P`, every `/` → `-`, dots kept), so a store reached through a worktree or
# account-root symlink maps to the one gitdir. Each gitdir records the path it was keyed on in `cc-store-path`, which is
# how a store that config-mirror later MOVED (old path now a symlink to the new one) keeps its one
# history: on first sight of a new physical path we adopt the gitdir whose recorded path resolves to
# it. Contract for readers (memory-fleet-sweep's history-age column): `refs/heads/main` in that
# gitdir, one commit per snapshot, committer date = snapshot time, `cc-store-path` = the store.
#
# ── LOCK-FREE, AND THE STORE IS NEVER WRITTEN ─────────────────────────────────────────────────
# A temp GIT_INDEX_FILE (outside the store) → `add -A` → `write-tree`; an unchanged tree is a no-op.
# Otherwise `commit-tree` + `update-ref <new> <old>`, a compare-and-swap: two concurrent snapshots
# cannot lose each other's commit, and the loser re-reads and retries once. There is no shared index
# to leave a stale `index.lock` in. The caller runs this INSIDE its own mutation lock, so the tree
# captured is the pre-image of that caller's write.
#
# ── ALWAYS EXIT 0, ONE LINE ──────────────────────────────────────────────────────────────────
# Callers are actuators that must not change their verdict because history failed. So every path
# prints exactly one `verdict=<snapshotted|unchanged|contended|refused|error> store=… sha=… reason=…`
# line and exits 0. `reason=` is the caller's reason, except on refused/error, where it is the cause.
# It never pushes, and refuses outright (verdict=refused reason=has-remote) if the gitdir has a remote.
#
# Usage:
#   memory-store-snapshot.sh <store-dir> <reason>
#   memory-store-snapshot.sh --list <store-dir>       history, newest first (restore aid)
#   memory-store-snapshot.sh --session-start          the SessionStart trigger (payload in $CC_MSS_PAYLOAD)
# Restore one file:  git --git-dir=<gitdir> show <sha>:<file>   (the --list header names the gitdir)

set -u

HIST_ROOT="${CC_MEMORY_HISTORY_ROOT:-$HOME/.local/state/cc-memory-history}"
ZERO_OID=0000000000000000000000000000000000000000

# Scratch the rotor and index writers leave in the store for seconds at a time. Snapshotting them
# would record a lock dir or a half-written temp as memory content.
EXCLUDES=(':(exclude,glob).rotate.lock.d/**' ':(exclude,glob)**/.rotate.cited.*'
          ':(exclude,glob)**/*.tmp' ':(exclude,glob)**/.MEMORY.md.*')

# History key: the PHYSICAL path with every `/` → `-` (dots kept), so
# /Users/x/.claude/projects/foo/memory → -Users-x-.claude-projects-foo-memory. memory-fleet-sweep
# derives the same name to read history age, so this rule is a contract, not a detail.
hist_slug() { printf "%s" "$1" | tr "/" "-"; }
# Claude Code's own project slug (`/` and `.` → `-`), used only to FIND a session's store.
project_slug() { printf "%s" "$1" | tr "/." "--"; }

# git with nothing from the operator's global config that could write, sign, or spawn: no
# fsmonitor daemon, no gpg prompt, no global excludes silently dropping a memory file.
g() {
  git -c core.fsmonitor=false -c commit.gpgSign=false -c core.excludesFile=/dev/null \
      -c core.autocrlf=false -c gc.auto=0 --git-dir="$GD" "$@"
}

# Identity via env, so no user.name/email config is needed on a fresh machine or temp HOME.
export GIT_AUTHOR_NAME=cc-memory-snapshot GIT_AUTHOR_EMAIL=cc-memory-snapshot@localhost
export GIT_COMMITTER_NAME=cc-memory-snapshot GIT_COMMITTER_EMAIL=cc-memory-snapshot@localhost

STORE="-" REASON="-" GD=""
out() { # verdict sha [reason-override]
  printf 'verdict=%s store=%s sha=%s reason=%s gitdir=%s\n' "$1" "$STORE" "${2:--}" \
    "${3:-$REASON}" "${GD:--}"
}

# rename(2) refuses a non-empty target, which makes it the atomic "create or lose the race"
# primitive that `mv` is not (macOS mv would move the source INSIDE an existing directory).
atomic_rename() { /usr/bin/perl -e 'rename($ARGV[0], $ARGV[1]) or exit 1' "$1" "$2" 2>/dev/null; }

# Resolve (and on first use create or adopt) the gitdir for physical store path $1 into GD.
resolve_gitdir() {
  local phys="$1" cand rec rphys tmp
  GD="$HIST_ROOT/$(hist_slug "$phys").git"
  [ -d "$GD" ] && return 0
  mkdir -p "$HIST_ROOT" 2>/dev/null || return 1
  # Adopt: a gitdir keyed on an older path of THIS store (config-mirror moved the directory and
  # left a symlink behind) is the same history, so it is renamed to the new key, not duplicated.
  for cand in "$HIST_ROOT"/*.git; do
    [ -f "$cand/cc-store-path" ] || continue
    rec="$(head -n1 "$cand/cc-store-path" 2>/dev/null)"
    [ -n "$rec" ] && [ "$rec" != "$phys" ] || continue
    rphys="$(cd "$rec" 2>/dev/null && pwd -P)" || continue
    if [ "$rphys" = "$phys" ]; then
      atomic_rename "$cand" "$GD" || [ -d "$GD" ] || continue
      printf '%s\n' "$phys" >"$GD/cc-store-path" 2>/dev/null
      return 0
    fi
  done
  tmp="$(mktemp -d "$HIST_ROOT/.init.XXXXXX")" || return 1
  if ! git init -q --bare --template= "$tmp" >/dev/null 2>&1; then rm -rf "$tmp"; return 1; fi
  git --git-dir="$tmp" symbolic-ref HEAD refs/heads/main 2>/dev/null
  printf '%s\n' "$phys" >"$tmp/cc-store-path"
  # Losing the creation race is fine: the winner's gitdir is the same history-to-be.
  atomic_rename "$tmp" "$GD" || rm -rf "$tmp"
  [ -d "$GD" ]
}

snapshot() { # $1=store $2=reason → prints the one verdict line
  local in="$1" phys idx tree parent ptree new attempt
  REASON="$(printf '%s' "${2:-unspecified}" | tr -c '[:alnum:]_.:-' '_' | cut -c1-64)"
  if [ -z "$in" ] || [ ! -d "$in" ]; then STORE="${in:--}"; out error - no-store; return 0; fi
  phys="$(cd "$in" 2>/dev/null && pwd -P)" || { STORE="$in"; out error - unresolvable; return 0; }
  STORE="$phys"
  local hphys; hphys="$(mkdir -p "$HIST_ROOT" 2>/dev/null && cd "$HIST_ROOT" && pwd -P)" || hphys=""
  case "$hphys/" in "$phys"/*) out error - history-inside-store; return 0 ;; esac
  command -v git >/dev/null 2>&1 || { out error - no-git; return 0; }
  resolve_gitdir "$phys" || { out error - gitdir-create-failed; return 0; }
  if [ -n "$(g remote 2>/dev/null)" ]; then out refused - has-remote; return 0; fi

  idx="$(mktemp "${TMPDIR:-/tmp}/cc-mss-index.XXXXXX")" || { out error - no-temp-index; return 0; }
  rm -f "$idx"   # git wants to create the index itself; mktemp only reserved a unique name
  # shellcheck disable=SC2064  # expand $idx now: the path is fixed for this run
  trap "rm -f '$idx' '$idx.lock'" EXIT
  if ! (cd "$phys" && GIT_INDEX_FILE="$idx" g --work-tree="$phys" add -A -- . "${EXCLUDES[@]}") >/dev/null 2>&1; then
    out error - add-failed; return 0
  fi
  tree="$(GIT_INDEX_FILE="$idx" g write-tree 2>/dev/null)" || { out error - write-tree-failed; return 0; }

  attempt=0
  while [ "$attempt" -lt 2 ]; do
    attempt=$(( attempt + 1 ))
    parent="$(g rev-parse -q --verify refs/heads/main 2>/dev/null)" || parent=""
    if [ -n "$parent" ]; then
      ptree="$(g rev-parse "$parent^{tree}" 2>/dev/null)" || ptree=""
      if [ "$ptree" = "$tree" ]; then out unchanged "$parent"; return 0; fi
      new="$(printf '%s %s\n' "$REASON" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | g commit-tree "$tree" -p "$parent" 2>/dev/null)"
    else
      new="$(printf '%s %s\n' "$REASON" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" | g commit-tree "$tree" 2>/dev/null)"
    fi
    [ -n "$new" ] || { out error - commit-tree-failed; return 0; }
    if g update-ref -m "$REASON" refs/heads/main "$new" "${parent:-$ZERO_OID}" 2>/dev/null; then
      out snapshotted "$new"; return 0
    fi
  done
  out contended "${parent:--}"
  return 0
}

list_history() {
  local phys
  phys="$(cd "${1:-}" 2>/dev/null && pwd -P)" || { printf 'no store at %s\n' "${1:-<none>}"; return 0; }
  GD="$HIST_ROOT/$(hist_slug "$phys").git"
  [ -d "$GD" ] || { printf 'no history for %s (expected %s)\n' "$phys" "$GD"; return 0; }
  printf '# gitdir=%s — restore a file: git --git-dir=%s show <sha>:<file>\n' "$GD" "$GD"
  g log --format='%h %cI %s' refs/heads/main 2>/dev/null || true
}

# The SessionStart trigger. The hook detaches this so a session start pays no git cost; the store
# is resolved from the payload's cwd the same way hooks/memory-nudge.sh resolves the index, and the
# verdict is written (by the detach log) under its own IDL name so a dead branch cannot hide behind
# session-start.sh's other duties. Reasons it could not look at all are distinct tokens (no-cwd,
# snapshot error causes) from the healthy quiet ones (no-store: this project has no memory yet).
TAG="session-start:memory-snapshot"
session_start() {
  local payload="${CC_MSS_PAYLOAD:-}" cwd="" sid="" cfg root gcd cand phys base store="" line v r
  if [ -n "$payload" ] && command -v jq >/dev/null 2>&1; then
    cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)" || cwd=""
    sid="$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)" || sid=""
  fi
  [ -n "$cwd" ] && [ -d "$cwd" ] || cwd="${CC_MSS_CWD:-}"
  if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    line="verdict=error store=- sha=- reason=no-cwd gitdir=-"
  else
    cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"; root=""
    if gcd="$(cd "$cwd" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
       && [ -n "$gcd" ]; then root="$(dirname "$gcd")"; fi
    # Logical AND physical spelling of each base: the harness keys on the cwd it was handed, git
    # reports a resolved path, and /var vs /private/var share no prefix.
    for cand in "$root" "$cwd"; do
      [ -n "$cand" ] || continue
      phys="$(cd "$cand" 2>/dev/null && pwd -P)" || phys=""
      for base in "$cand" "$phys"; do
        [ -n "$base" ] || continue
        [ -d "$cfg/projects/$(project_slug "$base")/memory" ] && { store="$cfg/projects/$(project_slug "$base")/memory"; break 2; }
      done
    done
    if [ -z "$store" ]; then line="verdict=unchanged store=- sha=- reason=no-store gitdir=-"
    else line="$(snapshot "$store" session-start)"; fi
  fi
  printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$TAG" "$line"
  # IDL row under the branch's own name. fired = a pre-image was written; everything else is an
  # abstention whose reason says whether the guard was reached (unchanged / no-store / contended)
  # or never observed (no-cwd and the error causes).
  command -v jq >/dev/null 2>&1 || return 0
  v="${line#verdict=}"; v="${v%% *}"; r="${line##*reason=}"; r="${r%% *}"
  case "$v" in
    snapshotted) set -- fired snapshotted ;;
    unchanged)   set -- abstained "$r" ;;
    contended)   set -- abstained contended ;;
    *)           set -- abstained "$r" ;;
  esac
  local idl="${CC_IDL:-$HOME/.claude/autonomy/idl.jsonl}" rec
  mkdir -p "$(dirname "$idl")" 2>/dev/null || return 0
  rec="$(jq -cn --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg hook "$TAG" --arg sid "${sid:-?}" \
           --arg d "$1" --arg r "$2" '{ts:$ts,hook:$hook,sid:$sid,disposition:$d,reason:$r}' 2>/dev/null)" || return 0
  [ -n "$rec" ] && printf '%s\n' "$rec" >>"$idl" 2>/dev/null
  return 0
}

case "${1:-}" in
  --list)          list_history "${2:-}" ;;
  --session-start) session_start ;;
  -*)              out error - "unknown-flag" ;;
  *)               snapshot "${1:-}" "${2:-}" ;;
esac
exit 0
