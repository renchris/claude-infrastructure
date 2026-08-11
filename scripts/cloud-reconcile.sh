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
# THE IDENTITY WALL, AND WHY THE TRANSLATION LIVES HERE. A cloud VM authors its commits as
# `noreply@anthropic.com`, which resolves to no GitHub account, so githooks/pre-push REFUSES the
# push — on purpose (docs/research/git-identity-leak-2026-08-05.md). That refusal is correct and is
# not the thing to weaken. What was broken is that it arrived UNNAMED: the hook's block prints as
# *guidance* on git's stderr and ship-land then exits 7 (push non-ff), so a permanent policy wall
# read as an ordinary sibling race and invited a retry that could never succeed. It was retried
# twice before the identity line was read (docs/plans/CLOUD_OBSERVABILITY.md §13.4).
# So the translation belongs at the ONE place that knows a range came from a cloud VM — here,
# between the fetch and the land. The transform is the one the gate itself prescribes
# (githooks/pre-push:125, `--reset-author` over the range) and provenance is PRESERVED rather than
# thrown away, in trailers on every rewritten commit:
#     Cloud-session: <declaration id> · Original-commit: <pre-rewrite sha> · Original-branch: <name>
# NOT `Co-authored-by:` — githooks/commit-msg blocks AI-authorship trailers, and a rewrite that
# trips it fails EVERY commit in the range. The composed message is put through the repo's OWN
# commit-msg hook before it is written, so that predicate has one arbiter rather than a copy here.
# The remote's branch and shas are left untouched, so nothing is lost: this re-attributes the
# authorship of the commits that go on OUR trunk, and the VM's originals stay where they were.
#
# EXITS. 0 ok · 64 usage · 65 refusal (no CONFIRM · branch absent from the remote · retired) ·
#   69 SENSOR FAILED (remote unreachable — never read as absence) · 70 at least one branch failed
#   to land — which now includes "the range needed re-authoring and could not be re-authored", a
#   per-branch failure like any other rather than a new exit code its callers would not read.
#   Per-branch failures are REPORTED and the remaining branches still run: a lander exit is
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
#
# …EXCEPT WHEN THE DIVERGENCE IS OUR OWN RESIDUE, which is the case this refusal actually met. A
# failed land leaves a rebased — and now, a re-authored — local head of that name behind, so the
# NEXT run refused with "diverged, or checked out in a worktree" and reported a first-failure cause
# as a second, different one. No amount of retrying cleared it; deleting the ref by hand did.
# A reconciler that cannot self-heal from its own leftovers is not idempotent, and the re-author
# below GUARANTEES the leftovers, so this is not an optional convenience.
#
# The heal is narrow and the two cases are told apart, because merging them into one string is
# exactly what made the diagnosis wrong:
#   * CHECKED OUT somewhere → still refuse. Someone owns that worktree; this is a real conflict.
#   * NOT checked out, and a `claude/*` branch → origin is the authority for a cloud branch (the VM
#     pushed it and nothing local may add to it), so reset the local ref to the remote and say so.
# Deliberately NOT widened past the cloud prefix: for a hand-made `feat/*` branch a diverged local
# head may be the only copy of someone's work, and the refusal there is correct.
worktree_holding() {  # <repo> <branch> → the worktree path with that branch checked out (else empty)
  # Same porcelain read as desk-land.sh:130 — one shape for one question, so the two can never
  # disagree about whether a branch is checked out.
  "$GIT_BIN" -C "$1" worktree list --porcelain 2>/dev/null | awk -v b="refs/heads/$2" '
    /^worktree /{wt=substr($0,10)}
    /^branch /{ if(substr($0,8)==b){print wt; exit} }'
}

FETCH_DETAIL=""
fetch_branch() {  # <repo> <branch> → 0 ok (FETCH_DETAIL non-empty ⇒ healed) · 1 refused · 2 cannot
  local repo="$1" b="$2" wt
  FETCH_DETAIL=""
  "$GIT_BIN" -C "$repo" fetch -q "$REMOTE" "refs/heads/$b:refs/heads/$b" >/dev/null 2>&1 && return 0

  # A fetch can fail for reasons that have nothing to do with a local head, and healing on those
  # would be acting on an absence. Confirm the stale ref is actually there before touching anything
  # (memory: probe-that-acts-on-absence-must-confirm-presence).
  if ! "$GIT_BIN" -C "$repo" show-ref --verify --quiet "refs/heads/$b"; then
    FETCH_DETAIL="the fetch of '$b' failed and there is NO local branch of that name to blame — the remote refused it, or it vanished from '$REMOTE' between the listing and now."
    return 2
  fi

  wt="$(worktree_holding "$repo" "$b")"
  if [ -n "$wt" ]; then
    FETCH_DETAIL="local '$b' is CHECKED OUT in a worktree ($wt) — a real conflict someone owns. NOT forcing: land it from there, or remove that worktree, then re-run."
    return 1
  fi

  # Scoped by restating the DISCOVERY filter rather than a second literal: $PREFIX is the one place
  # that decides what a cloud branch is, so this can never widen without discovery widening first.
  # Unreachable today by construction (candidates() emits nothing else, and --land refuses a branch
  # that is not among them) — kept because "the remote is the authority" is true only of a branch a
  # VM pushed, and for a hand-made one a diverged local head can be the only copy of that work.
  case "refs/heads/$b" in
    "$PREFIX"*) ;;
    *) FETCH_DETAIL="local '$b' has diverged from '$REMOTE' and is not a cloud branch ($PREFIX*), so the remote is NOT presumed to be its authority. NOT forcing."
       return 1 ;;
  esac

  if "$GIT_BIN" -C "$repo" fetch -q --force "$REMOTE" "refs/heads/$b:refs/heads/$b" >/dev/null 2>&1; then
    FETCH_DETAIL="healed: local '$b' had diverged and is checked out nowhere — residue of an earlier failed attempt — so it was reset to '$REMOTE', which is the authority for a cloud branch."
    return 0
  fi
  FETCH_DETAIL="local '$b' has diverged, is checked out nowhere, and even a forced re-fetch from '$REMOTE' failed. This is not the stale-residue case."
  return 2
}

diff_size() {  # <repo> <trunk-ref> <branch> → changed-file count (large sentinel if undecidable)
  local n
  n="$("$GIT_BIN" -C "$1" diff --name-only "$2...refs/heads/$3" 2>/dev/null | wc -l | tr -d ' ')" || n=""
  case "$n" in ''|*[!0-9]*) printf '999999' ;; *) printf '%s' "$n" ;; esac
}

# ── the identity translation (see "THE IDENTITY WALL" in the header) ─────────────────────────
git_ident_email() {  # <repo> → the author email git ITSELF would use (empty ⇒ none resolvable)
  # `git var GIT_AUTHOR_IDENT`, never `git config user.email`: the same arbiter githooks/pre-commit
  # settled on after measuring that a config read sees two of the five inputs to the effective
  # author. Re-deriving it differently here would be a second predicate that can disagree with the
  # commit it is about to make (memory: make-the-actuator-the-arbiter).
  local id
  id="$("$GIT_BIN" -C "$1" var GIT_AUTHOR_IDENT 2>/dev/null)" || return 1
  case "$id" in *"<"*">"*) ;; *) return 1 ;; esac
  id="${id#*<}"
  printf '%s' "${id%%>*}"
}

msg_hook_refuses() {  # <repo> <msg-file> → 0 the repo's OWN commit-msg hook refuses this message
  # The trailer names are chosen to clear githooks/commit-msg, and that constraint is invisible in
  # the strings themselves — so it is CHECKED by the hook rather than restated as a regex here. One
  # predicate, one arbiter: if someone later reaches for `Co-authored-by:`, this refuses before a
  # single commit object is written, instead of the whole range failing later somewhere else.
  local repo="$1" f="$2" hook
  hook="$("$GIT_BIN" -C "$repo" rev-parse --git-path hooks/commit-msg 2>/dev/null)" || return 1
  case "$hook" in /*) ;; *) hook="$repo/$hook" ;; esac
  [ -x "$hook" ] || return 1                       # no hook installed ⇒ nothing refuses
  ( cd "$repo" && "$hook" "$f" ) >/dev/null 2>&1 && return 1
  return 0
}

REAUTH_DETAIL=""
reauthor_branch() {  # <repo> <trunk-ref> <branch> <decl-id> → 0 ok (rewritten OR not needed) · 1 no
  local repo="$1" trunk="$2" b="$3" id="$4"
  local want base sha ae ce tree new f n=0 total=0 date
  local -a ta=()
  REAUTH_DETAIL=""

  want="$(git_ident_email "$repo")" || want=""
  if [ -z "$want" ]; then
    REAUTH_DETAIL="'$repo' has no effective git identity (\`git var GIT_AUTHOR_IDENT\`), so there is nothing to re-author TO."
    return 1
  fi
  base="$("$GIT_BIN" -C "$repo" merge-base "$trunk" "refs/heads/$b" 2>/dev/null)" || base=""
  if [ -z "$base" ]; then
    REAUTH_DETAIL="no merge-base between '$trunk' and '$b' — the range to re-author cannot be bounded, and rewriting an unbounded history is never the right move."
    return 1
  fi

  # NOT NEEDED is the common case for a branch a person pushed, and it must stay a strict no-op: a
  # gratuitous rewrite would change the shas of work that was already attributable, for nothing.
  # BOTH fields, because a rebase rewrites the committer and keeps the author (githooks/pre-push:26).
  while IFS='|' read -r sha ae ce; do
    [ -n "$sha" ] || continue
    [ "$ae" = "$want" ] && [ "$ce" = "$want" ] && continue
    n=$((n + 1))
  done <<EOF
$("$GIT_BIN" -C "$repo" log --reverse --format='%H|%ae|%ce' "$base..refs/heads/$b" 2>/dev/null)
EOF
  [ "$n" -gt 0 ] || return 0

  if [ -n "$("$GIT_BIN" -C "$repo" rev-list --merges "$base..refs/heads/$b" 2>/dev/null)" ]; then
    REAUTH_DETAIL="the range $base..$b contains a MERGE commit and this replay is linear-only, so it would flatten one side. A cloud VM pushes a linear branch; this one did not, which is itself the finding. Re-author it by hand and re-run."
    return 1
  fi

  # The replay is `git commit-tree`, not a rebase: it needs no checkout, no index and no working
  # tree, so it cannot touch the shared checkout's HEAD, and it carries each ORIGINAL TREE across
  # byte-exact — a cherry-pick replay can conflict and would leave a half-finished rebase behind in
  # a repo other sessions are using. The identity comes from the same resolution `--reset-author`
  # uses (config → GIT_AUTHOR_*), and the ORIGINAL AUTHOR DATE is carried over, which
  # `--reset-author` would have discarded: when the VM did the work is provenance too.
  f="$(mktemp "${TMPDIR:-/tmp}/cloud-reauthor.XXXXXX")" || {
    REAUTH_DETAIL="could not create a temporary file to compose the rewritten messages."
    return 1
  }
  new="$base"
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    tree="$("$GIT_BIN" -C "$repo" rev-parse --verify --quiet "$sha^{tree}" 2>/dev/null)" || tree=""
    if [ -z "$tree" ]; then
      REAUTH_DETAIL="could not read the tree of $sha."
      rm -f "$f"; return 1
    fi
    if ! "$GIT_BIN" -C "$repo" log -1 --format=%B "$sha" > "$f" 2>/dev/null; then
      REAUTH_DETAIL="could not read the commit message of $sha."
      rm -f "$f"; return 1
    fi
    ta=(--trailer "Original-commit: $sha" --trailer "Original-branch: $b")
    [ -n "$id" ] && ta=(--trailer "Cloud-session: $id" "${ta[@]}")
    if ! "$GIT_BIN" -C "$repo" interpret-trailers --in-place "${ta[@]}" "$f" 2>/dev/null; then
      REAUTH_DETAIL="could not append the provenance trailers to the message of $sha."
      rm -f "$f"; return 1
    fi
    if msg_hook_refuses "$repo" "$f"; then
      REAUTH_DETAIL="this repo's OWN commit-msg hook REFUSES the message this rewrite composed for $sha — the trailers carry something it blocks (an AI-authorship trailer such as \`Co-authored-by: Claude\` is the case it exists for). NOTHING was written; fix the trailers, not the hook."
      rm -f "$f"; return 1
    fi
    date="$("$GIT_BIN" -C "$repo" log -1 --format=%aI "$sha" 2>/dev/null)" || date=""
    new="$(GIT_AUTHOR_DATE="$date" "$GIT_BIN" -C "$repo" commit-tree "$tree" -p "$new" -F "$f" 2>/dev/null)" || new=""
    if [ -z "$new" ]; then
      REAUTH_DETAIL="git commit-tree failed while replaying $sha."
      rm -f "$f"; return 1
    fi
    total=$((total + 1))
  done <<EOF
$("$GIT_BIN" -C "$repo" rev-list --reverse "$base..refs/heads/$b" 2>/dev/null)
EOF
  rm -f "$f"

  if [ "$total" -eq 0 ]; then
    REAUTH_DETAIL="the range read as $n mis-authored commit(s) and then replayed none — the two reads disagree, so nothing was written."
    return 1
  fi
  if ! "$GIT_BIN" -C "$repo" update-ref -m "cloud-reconcile: re-authored $b for the git-identity gate" "refs/heads/$b" "$new" 2>/dev/null; then
    REAUTH_DETAIL="replayed $total commit(s) but could not move refs/heads/$b onto them."
    return 1
  fi
  REAUTH_DETAIL="re-authored $total commit(s) as <$want> ($n of them were unattributable); provenance in Cloud-session / Original-commit / Original-branch trailers, and '$REMOTE' still holds the originals."
  return 0
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
  rc=0; fetch_branch "$C_REPO" "$TARGET" || rc=$?
  [ "$rc" -eq 0 ] || die 65 "could not bring '$TARGET' into $C_REPO as a local head — $FETCH_DETAIL"
  [ -n "$FETCH_DETAIL" ] && echo "→ $TARGET — $FETCH_DETAIL"
  rc=0; reauthor_branch "$C_REPO" "$C_TRUNK" "$TARGET" "$C_ID" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "✗ $TARGET — NOT landed. This range is authored by someone GitHub cannot attribute, so githooks/pre-push would refuse the push (and ship-land would report that refusal as exit 7, an ordinary push race, which is why it is caught HERE). It could not be re-authored: $REAUTH_DETAIL" >&2
    exit 70
  fi
  [ -n "$REAUTH_DETAIL" ] && echo "→ $TARGET — $REAUTH_DETAIL"
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
  rc=0; fetch_branch "$C_REPO" "$b" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "✗ $b — could not bring it into $C_REPO as a local head: $FETCH_DETAIL" >&2
    FAILED=$((FAILED + 1))
    continue
  fi
  [ -n "$FETCH_DETAIL" ] && echo "→ $b — $FETCH_DETAIL"
  rc=0; reauthor_branch "$C_REPO" "$C_TRUNK" "$b" "$C_ID" || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "✗ $b — NOT landed. Its commits are authored by someone GitHub cannot attribute, so githooks/pre-push would refuse the push (reported by ship-land as exit 7, an ordinary push race — which is why it is caught HERE). It could not be re-authored: $REAUTH_DETAIL" >&2
    FAILED=$((FAILED + 1))
    continue
  fi
  [ -n "$REAUTH_DETAIL" ] && echo "→ $b — $REAUTH_DETAIL"
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
