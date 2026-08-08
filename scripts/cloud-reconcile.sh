#!/usr/bin/env bash
# cloud-reconcile.sh — gate G6: the CLOUD LANDING PATH. Discover the `claude/*` branches a cloud
# Claude Code VM pushed, decide which are eligible, and hand each — serialized, smallest diff first —
# to the sanctioned local lander.
#
#   scripts/cloud-reconcile.sh --list
#   scripts/cloud-reconcile.sh --land <branch> [--dry-run]
#   CONFIRM=1 scripts/cloud-reconcile.sh --all [--dry-run] [--include-undeclared]
#
# WHY THIS EXISTS. A cloud VM can push only its own working branch (named `claude/*`). It has no
# ~/.claude, no `gh`, and cannot run this repo's project-local /ship. Nothing LOCAL ever looks for
# that branch, so every cloud result strands on the remote:
#   * scripts/stranded-sweep.sh:66 iterates `git for-each-ref … refs/heads/` — LOCAL heads only. A
#     remote-only branch is STRUCTURALLY invisible to it, not merely unreported. Same for
#     scripts/branch-reaper.sh and scripts/worktree-gc.sh:374-387.
#   * scripts/ship-land.sh:1987's SHIP_LAND_SESSION_BRANCH_RE defaults to
#     `^(feat|fix|chore|docs|refactor|test|perf|style|build|ci)/.+`, which `claude/*` does not match,
#     so a land attempt refuses before it starts.
# This script is the missing local half. It is DISCOVERY + ELIGIBILITY + SERIALIZATION and nothing
# else: the land itself is scripts/desk-land.sh → scripts/ship-land.sh, which already own the
# landing lock, the shared-checkout refusal, the escalation PARK, the mandatory shellcheck+bats
# gate, the content-verify and the stranded sweep. Re-implementing any of those here would create a
# SECOND, weaker envelope — the exact defect a single sanctioned rail exists to prevent.
#
# THE BRANCH-NAME PROBLEM, AND WHY THE OVERRIDE IS SAFE. ship-land's session-branch regex rejects
# `claude/`. This script does NOT edit that default; it passes SHIP_LAND_SESSION_BRANCH_RE for the
# ONE invocation it makes, widened by EXACTLY the one prefix that is the subject here:
#     ^(claude|feat|fix|chore|docs|refactor|test|perf|style|build|ci)/.+
# A branch NAME is not a safety property — it is a shape check that keeps a land off trunk-as-a-
# branch and off a detached HEAD, and the widened regex still enforces both. The REAL safety
# properties are the shared-checkout refusal, the dirty-tree refusal, the gate and the
# content-verify, and every one of them is untouched and still runs. The override is scoped to the
# invocation (never exported process-wide) so nothing else on this box inherits it.
#
# ELIGIBILITY is cross-referenced against the `bin/cc-cloud` declaration store — flat `key=value`
# files at ~/.claude/autonomy/cloud/<id>.decl, read WITHOUT eval (a declaration is data written by a
# dispatcher; `eval` on it would be an injection seam). A branch with a declaration INHERITS its
# repo / trunk / paths. `<id>.retired` marks terminal. Landedness is decided BY CONTENT — `git
# ls-tree <trunk> -- <path>` per declared path, the rule at bin/cc-cloud:219-234 — because
# `rev-list --count` reads 0 after a sibling rebase and proves nothing (scripts/land-verify.sh:6-11).
#
# DEFAULT-OFF. `--land` and `--all` refuse without CONFIRM=1 (the repo's dominant convention —
# scripts/relogin-desharing-activate.sh:65-68). `--list` is read-only and always allowed: it makes
# no local ref, no worktree and no push.
#
# UNDECLARED BRANCHES are DISCOVERED and FLAGGED, never swept up by `--all`. A `claude/*` branch
# with no declaration is one nothing on this machine vouches for; landing it automatically would be
# this script deciding, unattended, that an unknown remote branch belongs on trunk. `--land <branch>`
# lands it (the operator named it), and `--all --include-undeclared` opts the sweep in explicitly.
#
# "CANNOT LOOK" IS NEVER "NOTHING FOUND". A failed `git ls-remote` exits 69 with zero rows emitted,
# never 0-with-no-candidates. A caller that read a sensor failure as an empty fleet would report the
# cloud landing path healthy at exactly the moment it went blind.
#
# EXITS. 0 ok · 64 usage · 65 refusal (no CONFIRM · branch absent from the remote · retired) ·
#   69 SENSOR FAILED (remote unreachable — never read as absence) · 70 at least one branch failed
#   to land. Per-branch failures are REPORTED and the remaining branches still run: a lander exit is
#   a statement about ONE branch, and aborting the sweep on it would let one bad branch strand every
#   other cloud result behind it. desk-land's own codes are surfaced verbatim per branch
#   (0 landed · 2 dirty/preflight · 3 escalation-PARK · 5 rebase-conflict · 6 gate-red · 7 push
#   non-ff · 8 verify-fail · 9 GATE-KILLED · 75 LOCK-STARVED · 64/65/66 desk-land preflight).
#
# Env seams: CLOUD_RECONCILE_REPO (local repo) · CLOUD_RECONCILE_REMOTE (origin) ·
#   CLOUD_RECONCILE_LAND_BIN (the lander — the test seam) · CLOUD_RECONCILE_GIT_BIN ·
#   CLOUD_RECONCILE_TRUNK (default trunk ref) · CLOUD_RECONCILE_NET_TIMEOUT_S ·
#   CC_CLOUD_STATE (shared with bin/cc-cloud, so the two can never disagree about a declaration).
#
# bash 3.2-safe (no declare -A / mapfile).
set -euo pipefail

DEFAULT_SHARED="$HOME/Development/claude-infrastructure"
REPO="${CLOUD_RECONCILE_REPO:-$DEFAULT_SHARED}"
REMOTE="${CLOUD_RECONCILE_REMOTE:-origin}"
GIT_BIN="${CLOUD_RECONCILE_GIT_BIN:-git}"
STATE="${CC_CLOUD_STATE:-$HOME/.claude/autonomy/cloud}"
DEF_TRUNK="${CLOUD_RECONCILE_TRUNK:-origin/main}"
NET_TIMEOUT="${CLOUD_RECONCILE_NET_TIMEOUT_S:-20}"
LAND_BIN="${CLOUD_RECONCILE_LAND_BIN:-$REPO/scripts/desk-land.sh}"

# The scoped widening. See "THE BRANCH-NAME PROBLEM" above: exactly one prefix added to
# ship-land.sh:1987's default, never `.*`, and never exported beyond the land invocation.
LAND_BRANCH_RE='^(claude|feat|fix|chore|docs|refactor|test|perf|style|build|ci)/.+'

PREFIX="refs/heads/claude/"
TAB="$(printf '\t')"

MODE="" TARGET="" DRY_RUN=0 INCLUDE_UNDECLARED=0

# Self path (for the usage banner), symlink-resolved.
SELF="$0"; while [ -L "$SELF" ]; do _t="$(readlink "$SELF")"; case "$_t" in /*) SELF="$_t" ;; *) SELF="$(dirname "$SELF")/$_t" ;; esac; done
usage() { sed -n '2,/^set -euo pipefail/p' "$SELF" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }
die() { echo "!! cloud-reconcile: $2" >&2; exit "$1"; }

# ── args ─────────────────────────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --list)                MODE=list; shift ;;
    --all)                 MODE=all; shift ;;
    --land)                MODE=land; TARGET="${2:?--land needs a branch}"; shift 2 ;;
    --land=*)              MODE=land; TARGET="${1#--land=}"; shift ;;
    --dry-run)             DRY_RUN=1; shift ;;
    --include-undeclared)  INCLUDE_UNDECLARED=1; shift ;;
    -h|--help)             usage 0 ;;
    *)                     die 64 "unknown argument '$1' (see --help)." ;;
  esac
done
[ -n "$MODE" ] || die 64 "no verb — pass --list, --land <branch> or --all. Run with --help."
[ -d "$REPO" ] || die 65 "repo '$REPO' does not exist (set CLOUD_RECONCILE_REPO)."

# ── the declaration reader (bin/cc-cloud:175-186, same contract, no eval) ────────────────────
dfield() {  # <file> <key> → value (empty if absent)
  local f="$1" k="$2" line
  [ -f "$f" ] || return 0
  # `|| [ -n "$line" ]` is load-bearing: a file with no trailing newline makes the final `read`
  # return 1, and under `set -e` a bare `while read` loop would swallow that last line.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$k="*) printf '%s' "${line#*=}"; return 0 ;; esac
  done < "$f"
  return 0
}

decl_for_branch() {  # <branch> → declaration id (empty if none). First match wins, ids sorted.
  local b="$1" f id
  [ -d "$STATE" ] || return 0
  for f in "$STATE"/*.decl; do
    [ -f "$f" ] || continue
    [ "$(dfield "$f" branch)" = "$b" ] || continue
    id="${f##*/}"; id="${id%.decl}"
    printf '%s' "$id"
    return 0
  done
  return 0
}

# LANDED BY CONTENT (bin/cc-cloud:219-234). 0 landed · 1 not · 2 cannot tell.
landed() {  # <repo> <trunk-ref> <comma-separated-paths>
  local repo="$1" trunk="$2" paths="$3" p rest out
  [ -n "$paths" ] || return 1                       # nothing declared ⇒ landing is not assertable
  [ -d "$repo" ] || return 2
  "$GIT_BIN" -C "$repo" rev-parse --verify --quiet "$trunk" >/dev/null 2>&1 || return 2
  rest="$paths"
  while [ -n "$rest" ]; do
    case "$rest" in *,*) p="${rest%%,*}"; rest="${rest#*,}" ;; *) p="$rest"; rest="" ;; esac
    [ -n "$p" ] || continue
    out="$("$GIT_BIN" -C "$repo" ls-tree "$trunk" -- "$p" 2>/dev/null)" || return 2
    [ -n "$out" ] || return 1
  done
  return 0
}

# ── the network sensor ───────────────────────────────────────────────────────────────────────
# rc 0 → candidate branch names on stdout (possibly none, meaning the remote HAS none).
# rc 2 → SENSOR FAILED. Never conflated: the caller turns this into exit 69, not an empty list.
NET_BOUND=""
if command -v timeout >/dev/null 2>&1; then NET_BOUND="timeout"
elif command -v gtimeout >/dev/null 2>&1; then NET_BOUND="gtimeout"; fi

candidates() {
  local out rc line ref
  local -a cmd=()
  [ -n "$NET_BOUND" ] && cmd=("$NET_BOUND" "$NET_TIMEOUT")
  cmd+=("$GIT_BIN" -C "$REPO" ls-remote --heads "$REMOTE" 'claude/*')
  # GIT_TERMINAL_PROMPT=0 is the difference between a bounded failure and an indefinite hang on a
  # credential prompt, which no timeout on a parent can help with once git owns the tty.
  rc=0
  out="$(GIT_TERMINAL_PROMPT=0 GIT_ASKPASS=/usr/bin/true "${cmd[@]}" 2>/dev/null)" || rc=$?
  [ "$rc" -eq 0 ] || return 2
  # Filter LOCALLY as well as in the pattern. ls-remote's pattern matching is a tail match at a
  # slash boundary; this `case` is the authority on what counts as a cloud branch, so the contract
  # does not depend on that subtlety being read correctly.
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    # `<sha>\t<ref>` — a ref name can contain no whitespace, so the greedy strip is exact.
    ref="${line##*[[:space:]]}"
    case "$ref" in "$PREFIX"*) printf '%s\n' "${ref#refs/heads/}" ;; esac
  done <<EOF
$out
EOF
  return 0
}

# ── classification ───────────────────────────────────────────────────────────────────────────
# Sets C_STATE C_ID C_REPO C_TRUNK C_PATHS C_DETAIL. bash 3.2 has no associative arrays and this
# stays a single-writer, single-reader pair, so globals beat encoding six fields into one string.
C_STATE="" C_ID="" C_REPO="" C_TRUNK="" C_PATHS="" C_DETAIL=""
classify() {  # <branch>
  local b="$1" id r
  C_STATE="" C_ID="" C_REPO="$REPO" C_TRUNK="$DEF_TRUNK" C_PATHS="" C_DETAIL=""
  id="$(decl_for_branch "$b")"
  if [ -z "$id" ]; then
    C_STATE="NO-DECL"
    C_DETAIL="no cc-cloud declaration — discovered, not vouched for"
    return 0
  fi
  C_ID="$id"
  if [ -f "$STATE/$id.retired" ]; then
    C_STATE="RETIRED"
    C_DETAIL="declaration $id is retired (terminal)"
    return 0
  fi
  r="$(dfield "$STATE/$id.decl" repo)";  [ -n "$r" ] && [ -d "$r" ] && C_REPO="$r"
  r="$(dfield "$STATE/$id.decl" trunk)"; [ -n "$r" ] && C_TRUNK="$r"
  C_PATHS="$(dfield "$STATE/$id.decl" paths)"
  r=0; landed "$C_REPO" "$C_TRUNK" "$C_PATHS" || r=$?
  if [ "$r" -eq 0 ]; then
    C_STATE="LANDED"
    C_DETAIL="declared paths already on $C_TRUNK"
  else
    C_STATE="ELIGIBLE"
    C_DETAIL="declared by $id"
  fi
  return 0
}

trunk_arg() {  # <trunk-ref> → the bare branch name ship-land's --trunk wants (origin/main → main)
  printf '%s' "${1#origin/}"
}

# ── the land path ────────────────────────────────────────────────────────────────────────────
# Bring the remote-only branch down to a LOCAL head, because desk-land.sh:150 resolves the target
# with `git show-ref --verify refs/heads/<branch>` and a remote-only branch fails that. The fetch is
# deliberately NOT forced: a `+` refspec would silently overwrite a local branch of the same name,
# and a divergence there is a finding to surface, not a conflict to resolve unattended.
fetch_branch() {  # <repo> <branch> → 0 ok, 1 could not
  "$GIT_BIN" -C "$1" fetch -q "$REMOTE" "refs/heads/$2:refs/heads/$2" >/dev/null 2>&1
}

diff_size() {  # <repo> <trunk-ref> <branch> → changed-file count (large sentinel if undecidable)
  local n
  n="$("$GIT_BIN" -C "$1" diff --name-only "$2...refs/heads/$3" 2>/dev/null | wc -l | tr -d ' ')" || n=""
  case "$n" in ''|*[!0-9]*) printf '999999' ;; *) printf '%s' "$n" ;; esac
}

land_one() {  # <branch> — classify() must have run for it. → 0 landed, else the lander's code
  local b="$1" rc=0
  local -a a=(--branch "$b" --repo "$C_REPO")
  [ -n "$C_TRUNK" ] && a+=(--trunk "$(trunk_arg "$C_TRUNK")")
  [ "$DRY_RUN" = 1 ] && a+=(--dry-run)
  # The override is scoped to THIS command, never exported: nothing else inherits a widened
  # session-branch regex.
  SHIP_LAND_SESSION_BRANCH_RE="$LAND_BRANCH_RE" "$LAND_BIN" "${a[@]}" || rc=$?
  return "$rc"
}

# ── verbs ────────────────────────────────────────────────────────────────────────────────────
CANDS="$(candidates)" || die 69 "SENSOR FAILED — could not read '$REMOTE' (git ls-remote). This is 'cannot look', NOT 'nothing to land': zero rows emitted deliberately. Re-run when the remote is reachable."

if [ "$MODE" = list ]; then
  printf 'BRANCH\tSTATE\tDECL\tDETAIL\n'
  while IFS= read -r b || [ -n "$b" ]; do
    [ -n "$b" ] || continue
    classify "$b"
    printf '%s\t%s\t%s\t%s\n' "$b" "$C_STATE" "${C_ID:--}" "$C_DETAIL"
  done <<EOF
$CANDS
EOF
  exit 0
fi

# Acting verbs are DEFAULT-OFF.
[ "${CONFIRM:-0}" = "1" ] || die 65 "refusing to act without CONFIRM=1 — re-run as: CONFIRM=1 $0 $MODE. (--list needs no confirmation and is always read-only.)"

FAILED=0

if [ "$MODE" = land ]; then
  found=0
  while IFS= read -r b || [ -n "$b" ]; do
    [ "$b" = "$TARGET" ] && found=1
  done <<EOF
$CANDS
EOF
  [ "$found" = 1 ] || die 65 "branch '$TARGET' is not on '$REMOTE' (looked for $PREFIX*). Nothing landed."
  classify "$TARGET"
  case "$C_STATE" in
    RETIRED) die 65 "'$TARGET' — $C_DETAIL. A retired declaration is terminal; not landing it." ;;
    LANDED)  echo "· $TARGET — $C_DETAIL; nothing to land."; exit 0 ;;
  esac
  fetch_branch "$C_REPO" "$TARGET" \
    || die 65 "could not fetch '$TARGET' into $C_REPO as a local head (diverged local branch of the same name, or it is checked out in a worktree). NOT forcing — resolve it and re-run."
  rc=0; land_one "$TARGET" || rc=$?
  if [ "$rc" -eq 0 ]; then echo "✓ $TARGET — landed via $LAND_BIN."; exit 0; fi
  echo "✗ $TARGET — lander exited $rc." >&2
  exit 70
fi

# ── --all ────────────────────────────────────────────────────────────────────────────────────
SIZED=""
while IFS= read -r b || [ -n "$b" ]; do
  [ -n "$b" ] || continue
  classify "$b"
  case "$C_STATE" in
    RETIRED|LANDED) echo "· $b — skipped: $C_DETAIL"; continue ;;
    NO-DECL)
      if [ "$INCLUDE_UNDECLARED" != 1 ]; then
        echo "· $b — skipped: $C_DETAIL (pass --include-undeclared, or name it with --land)"
        continue
      fi
      ;;
  esac
  if ! fetch_branch "$C_REPO" "$b"; then
    echo "✗ $b — could not fetch into $C_REPO as a local head (diverged, or checked out in a worktree). NOT forcing." >&2
    FAILED=$((FAILED + 1))
    continue
  fi
  SIZED="$SIZED$(diff_size "$C_REPO" "$C_TRUNK" "$b")$TAB$b
"
done <<EOF
$CANDS
EOF

# Smallest diff first — the repo's merge-back ordering rule (CLAUDE.md § Concurrent Sessions):
# the cheapest land goes first so a big, conflict-prone one cannot hold the queue.
ORDER="$(printf '%s' "$SIZED" | sed '/^$/d' | sort -n -k1,1)"

LANDED_N=0
while IFS= read -r row || [ -n "$row" ]; do
  [ -n "$row" ] || continue
  b="${row#*"$TAB"}"
  classify "$b"
  rc=0; land_one "$b" || rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "✓ $b — $([ "$DRY_RUN" = 1 ] && echo 'passed dry-run (NOT pushed)' || echo 'landed')."
    LANDED_N=$((LANDED_N + 1))
  else
    # A lander exit is a statement about ONE branch. Report it and keep going — aborting here would
    # strand every remaining cloud result behind the first bad branch.
    echo "✗ $b — lander exited $rc; continuing with the remaining branches." >&2
    FAILED=$((FAILED + 1))
  fi
done <<EOF
$ORDER
EOF

echo "cloud-reconcile: $LANDED_N ok, $FAILED failed."
[ "$FAILED" -eq 0 ] || exit 70
exit 0
