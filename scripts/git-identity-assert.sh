#!/usr/bin/env bash
# git-identity-assert.sh — the SENSOR and REPAIR half of the git-identity guard.
#
# githooks/pre-commit is the brake: it refuses a mis-authored commit at the moment it is made.
# This is the part that answers the question nobody could answer for three days — "is the
# identity wrong RIGHT NOW, anywhere on this machine?" — and repairs it where the repair is
# unambiguous.
#
# THE GAP THIS CLOSES. The 2026-08-05 round shipped two WRITE-side defences (a corpus lint and a
# PreToolUse guard). Both answer "did someone just try to write a bad identity?". Neither answers
# "is a bad identity currently in force?". So when one escaped before those landed, it sat in
# .git/config from 2026-08-05 to 2026-08-08 and produced 710 unattributable commits while every
# sensor on the machine read green. A defence with no state sensor is a defence with a blind spot
# the exact width of its own deployment date.
#
# ONE PREDICATE, NOT TWO. This script never re-implements the "is this identity acceptable" test.
# It shells out to the repo's OWN installed githooks/pre-commit in `--check` mode, so the sweep
# and the gate are the same code. Re-deriving the rule here would let a repo pass the sweep and
# be refused by its gate, or worse the reverse (memory: make-the-actuator-the-arbiter).
# A repo with no hook installed is reported UNPROTECTED — that is a finding, not a pass.
#
# REPAIR IS DELIBERATELY NARROW. It only ever REMOVES a local override that shadows a correct
# global. It never invents an identity and never writes a global, because a repair that guesses
# is worse than the fault it treats (memory: prescribed-remedy-worse-than-the-bug). If the global
# itself is wrong, that is reported with the one command to fix it and left to a human.
#
#   git-identity-assert.sh check    [<repo>]      one repo   · 0 ok/out-of-scope · 1 wrong · 2 usage
#   git-identity-assert.sh repair   [<repo>]      unset a shadowing local override, then re-check
#   git-identity-assert.sh install  [<repo>]      deploy the gate into <repo>'s shared .git/hooks
#   git-identity-assert.sh sweep    [--repair|--install]   every repo under the roots
#   git-identity-assert.sh verify-attribution     re-derive the email→account mapping from GitHub
#   git-identity-assert.sh selftest               RED-on-wrong + GREEN-on-right, throwaway dir
#
# Env seams: CC_GIT_IDENTITY_EMAIL · CC_GIT_IDENTITY_OWNER · CC_GIT_IDENTITY_ROOTS (colon-sep)
#            CC_GIT_IDENTITY_HOOK  (path to the arbiter; default = alongside this script's repo)
#
# Exit: 0 = all clean · 1 = at least one wrong or unprotected · 2 = usage / unusable (LOUD).
# `set -uo pipefail`, not -e: every predicate answers by exit code and errexit would abort on the
# first honest "no" instead of letting the sweep finish and report it.
set -uo pipefail
export LC_ALL=C

# ── The contract, and why the env seams are SEALED in production ───────────────────────────────
# CC_GIT_IDENTITY_EMAIL / _OWNER exist so the /Users/chrisren/.claude/bin/cc-bats suite can pin a contract that does not depend
# on the operator's real address. Left live, they were a ONE-LINE TOTAL BYPASS, and the worse of
# the two is _OWNER: it does not widen the allowlist, it makes the repo out of scope, so the gate
# exits 0 without ever looking at the identity.
#
#     CC_GIT_IDENTITY_OWNER=someone-else git commit -m x      # committed t <t@e.com>, silently
#
# That is reachable, not contrived. hooks/validate-bash.sh blocks `--no-verify` and `commit -n`,
# so the escape an agent reaches for FIRST is refused — and both of these were documented as
# supported overrides in this very file, three lines from the refusal message. An agent told
# "🔧 never yields" was being steered straight at them. handoff-fire.sh's `--env KEY=VAL` is
# inherited by every descendant of a fired pane, so one such var set once poisons a whole session.
#
# They now require CC_GIT_IDENTITY_TEST=1 as well, which the suite sets and nothing in production
# does. An env var that can silently WIDEN a security predicate is not a seam, it is a hole.
if [ "${CC_GIT_IDENTITY_TEST:-}" = 1 ]; then
  WANT_EMAIL="${CC_GIT_IDENTITY_EMAIL:-ren.chris@outlook.com}"
  WANT_OWNER="${CC_GIT_IDENTITY_OWNER:-renchris}"
else
  WANT_EMAIL="ren.chris@outlook.com"
  WANT_OWNER="renchris"
fi

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${CC_GIT_IDENTITY_HOOK:-$SELF_DIR/../githooks/pre-commit}"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 2; }
die2()  { echo "git-identity-assert: ⛔ $*" >&2; exit 2; }

[ -x "$HOOK" ] || die2 "arbiter hook not executable: $HOOK (set CC_GIT_IDENTITY_HOOK)"

# ── check ─────────────────────────────────────────────────────────────────────────────────────
# Delegates entirely to the arbiter. Prints its verdict line verbatim.
do_check() {
  local repo="${1:-$PWD}"
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die2 "not a git repo: $repo"
  "$HOOK" --check "$repo"
}

# ── repair ────────────────────────────────────────────────────────────────────────────────────
do_repair() {
  local repo="${1:-$PWD}" out rc
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die2 "not a git repo: $repo"

  out="$("$HOOK" --check "$repo")"; rc=$?
  if [ "$rc" -eq 0 ]; then echo "$out"; return 0; fi

  # The ONLY unambiguous repair: a local override differs from the sanctioned address while the
  # global already holds it. Removing the override restores the SSOT rather than adding a second
  # copy of it — one address, in one place, so a future correction to the global propagates.
  local loc glob
  loc="$(git -C "${repo:?repo path required}" config --local --get user.email 2>/dev/null)"
  glob="$(git -C "${repo:?repo path required}" config --global --get user.email 2>/dev/null)"

  if [ -n "$loc" ] && [ "$loc" != "$WANT_EMAIL" ] && [ "$glob" = "$WANT_EMAIL" ]; then
    git -C "$repo" config --local --remove-section user 2>/dev/null
    out="$("$HOOK" --check "$repo")"; rc=$?
    [ "$rc" -eq 0 ] && { echo "repaired  $repo  (dropped local override '$loc')"; echo "          $out"; return 0; }
    echo "REPAIR-INCOMPLETE  $repo"; echo "  $out"; return 1
  fi

  # Anything else needs a human: a wrong GLOBAL is machine-wide state, and an identity coming
  # from the environment belongs to whoever exported it. Report the cure the arbiter chose.
  echo "NEEDS-HUMAN  $repo"; echo "  $out"; return 1
}

# ── install ───────────────────────────────────────────────────────────────────────────────────
# Installs pre-commit AND pre-push AND pre-merge-commit as REAL COPIES into the repo's shared
# hooks dir. A linked worktree resolves .git/hooks through the common dir, so one install protects
# every worktree of the repo (measured).
#
# 🚨 COPIES, NOT SYMLINKS — this was a symlink for six hours and that was a critical bug. A link
# into the WORKING TREE points at a file that only exists on branches containing it. githooks/
# landed 2026-08-08, so 384 of 400 local branches lack it; a single `git checkout <older-branch>`
# or `git bisect` in the shared checkout makes the link dangle, and git fails OPEN on a dangling
# hook — no warning, no exit code, nothing. One checkout in one directory silently ungated all 207
# worktrees at once, and CLAUDE.md itself notes the shared checkout "frequently sits on another
# session's feature branch". A copy is immune to what the tree is currently checked out to.
#
# The cost of a copy is drift, and drift is the lesser failure: it is loud on inspection and
# `install` re-asserts on every deploy, whereas the dangling link was silent and permanent. install
# rewrites a copy whose content differs, so a repo edit propagates on the next deploy.
#
# NEVER CLOBBERS A FOREIGN HOOK. Overwriting one to install a guard would trade an identity bug for
# whatever that hook was preventing — an unprotected repo you know about beats a broken one you do
# not. Recognition is by content marker, so our own older copy is upgraded rather than skipped.
CC_HOOK_MARKER='cc-git-identity-gate'
do_install() {
  local repo="${1:-$PWD}" cdir hookdir wrote=0 kept=0 skipped=0
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || die2 "not a git repo: $repo"
  cdir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
    || die2 "cannot resolve git-common-dir for $repo"
  hookdir="$cdir/hooks"; mkdir -p "$hookdir"

  local srcdir; srcdir="$(cd "$(dirname "$HOOK")" && pwd)"
  local h src dest
  # pre-merge-commit shares pre-commit's implementation: a merge commit is a commit, and git runs
  # a DIFFERENT hook name for it, so without this the merge path is ungated by name alone.
  for h in pre-commit pre-push pre-merge-commit; do
    case "$h" in pre-merge-commit) src="$srcdir/pre-commit" ;; *) src="$srcdir/$h" ;; esac
    [ -f "$src" ] || continue
    dest="$hookdir/$h"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      if ! grep -q "$CC_HOOK_MARKER" "$dest" 2>/dev/null; then
        echo "SKIP-FOREIGN  $repo/$h  (not ours; chain it by hand)"; skipped=$((skipped+1)); continue
      fi
      if cmp -s "$src" "$dest"; then kept=$((kept+1)); continue; fi
    fi
    cp "$src" "$dest" && chmod +x "$dest" && wrote=$((wrote+1))
  done

  [ "$skipped" -gt 0 ] && { echo "partial   $repo  (wrote $wrote, current $kept, foreign $skipped)"; return 1; }
  [ "$wrote" -eq 0 ] && { echo "already   $repo  ($kept hook(s) current)"; return 0; }
  echo "installed $repo  ($wrote hook(s) written, $kept current)"
}

# ── sweep ─────────────────────────────────────────────────────────────────────────────────────
# Enumerates real repos, not worktrees: linked worktrees share one .git/config and one .git/hooks,
# so reporting each of ~200 separately would say the same thing 200 times and bury the one repo
# that differs. Dedupe is by git-common-dir, which is the file the fault actually lives in.
do_sweep() {
  local repair=0 install=0
  [ "${1:-}" = "--repair" ]  && repair=1
  [ "${1:-}" = "--install" ] && install=1
  local roots="${CC_GIT_IDENTITY_ROOTS:-$HOME/Development}"
  local seen="" bad=0 unprot=0 ok=0 skipped=0 exempted=0

  local IFS=:
  # shellcheck disable=SC2086
  set -- $roots
  unset IFS

  local found; found="$(
    for root in "$@"; do
      [ -d "$root" ] || continue
      find "$root" -maxdepth 3 -name .git -print 2>/dev/null
    done
  )"

  while IFS= read -r g; do
    [ -n "$g" ] || continue
    local repo cdir
    repo="${g%/.git}"
    cdir="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || continue
    case ":$seen:" in *":$cdir:"*) continue ;; esac
    seen="$seen:$cdir"

    local out rc
    if [ "$repair" -eq 1 ]; then out="$(do_repair "$repo")"; rc=$?
    else out="$("$HOOK" --check "$repo")"; rc=$?; fi

    case "$out" in
      n/a*) skipped=$((skipped+1)); continue ;;   # out of scope: not the owner's GitHub repo
    esac

    # In scope from here on. Install BEFORE reporting protection, so --install's table is the
    # post-state and not a stale read of what it just changed.
    [ "$install" -eq 1 ] && do_install "$repo" | sed 's/^/  /'

    # Is it actually protected, or merely correct by luck today? "ok + unprotected" is the state
    # the whole 3-day leak lived in — a correct identity with nothing holding it there.
    #
    # pre-PUSH is the one that decides the verdict. pre-commit is early warning; only pre-push sees
    # what reaches GitHub, because rebase/cherry-pick/merge/am replay commits without ever running
    # pre-commit and `ship-land.sh` rebases before every push. A repo with pre-commit but no
    # pre-push reads `partial`, not `guarded` — it is exactly the state that let ~66 mis-authored
    # commits sit staged behind a gate that could not see them.
    local prot="unprotected"
    if [ -e "$cdir/hooks/pre-push" ]; then
      prot="guarded"; [ -e "$cdir/hooks/pre-commit" ] || prot="push-only"
    elif [ -e "$cdir/hooks/pre-commit" ]; then
      prot="partial"                              # commit-time only — replays walk around it
    fi
    [ "$prot" = guarded ] || unprot=$((unprot+1))

    case "$out" in
      exempt*) exempted=$((exempted+1)); printf '  %-9s %-11s %s\n' "exempt" "$prot" "$repo"
               printf '%s\n' "$out" | sed 's/^/            /'; continue ;;
    esac

    if [ "$rc" -eq 0 ]; then ok=$((ok+1)); printf '  %-9s %-11s %s\n' "ok" "$prot" "$repo"
    else bad=$((bad+1)); printf '  %-9s %-11s %s\n' "WRONG" "$prot" "$repo"
         printf '%s\n' "$out" | sed 's/^/            /'
    fi
  done <<EOF
$found
EOF

  echo
  echo "  in scope: $((ok+bad+exempted))   ok: $ok   wrong: $bad   exempt: $exempted   unprotected: $unprot   out-of-scope skipped: $skipped"
  # An exemption is a recorded decision, so it does not fail the sweep; a WRONG or an UNPROTECTED
  # in-scope repo does. Unprotected counts because "correct right now" is exactly what read green
  # for three days while 710 commits went out unattributable.
  [ "$bad" -eq 0 ] && [ "$unprot" -eq 0 ]
}

# ── verify-attribution ────────────────────────────────────────────────────────────────────────
# The email→account mapping is a fact about a live GitHub account, not a constant. A rule that
# merely ASSERTS it cannot learn that it changed (memory: resident-policy-must-not-restate-
# perishable-facts), so this re-derives it on demand from the API and says plainly when it cannot.
do_verify_attribution() {
  command -v gh >/dev/null 2>&1 || die2 "gh CLI required for verify-attribution"
  local repo="${1:-$PWD}" slug
  slug="$(git -C "$repo" remote get-url origin 2>/dev/null \
        | sed -E 's#^.*github\.com[:/]##; s#\.git$##')"
  [ -n "$slug" ] || die2 "no github origin on $repo"

  # SAMPLE ONLY FROM THE REMOTE-REACHABLE HISTORY. The first version searched `--all` and picked
  # whatever commit carried the address first — routinely a local-only checkpoint ref, for which
  # the API answers 422 "No commit found for SHA". With stderr swallowed that read as
  # UNATTRIBUTED, so the verifier declared the SANCTIONED address broken and told the operator not
  # to trust its own allowlist. A null from an instrument that cannot see the subject is not
  # absence (memory: lookup-miss-is-not-absence) — and a false alarm here is worse than no check,
  # because the printed advice is "do not edit the constant", i.e. distrust a correct config.
  local base; base="$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"
  base="${base#refs/remotes/}"; [ -n "$base" ] || base="origin/main"
  git -C "$repo" rev-parse --verify --quiet "$base" >/dev/null \
    || die2 "no remote-tracking $base to sample — fetch first; refusing to test against local-only shas"

  echo "Re-deriving email → account from the GitHub API (repo $slug, sampling $base):"
  local any=1 untestable=0
  while IFS= read -r em; do
    [ -n "$em" ] || continue
    local sha login
    sha="$(git -C "$repo" log "$base" --format='%H %ae' | awk -v e="$em" '$2==e{print $1; exit}')"
    if [ -z "$sha" ]; then
      # Present in local history but on no pushed commit: GitHub has never seen it, so the
      # question is unanswerable rather than answered "no". Named, not silently skipped.
      printf '  %-34s %-9s -> (no pushed commit — untestable)\n' "$em" "—"
      [ "$em" = "$WANT_EMAIL" ] && untestable=1
      continue
    fi
    login="$(gh api "repos/$slug/commits/$sha" --jq '.author.login // "UNATTRIBUTED"' 2>/dev/null)"
    [ -n "$login" ] || login="API-ERROR"
    printf '  %-34s %s -> %s\n' "$em" "${sha:0:9}" "$login"
    [ "$em" = "$WANT_EMAIL" ] && [ "$login" = "$WANT_OWNER" ] && any=0
  done <<EOF
$(git -C "$repo" log "$base" --format='%ae' | sort -u)
EOF

  echo
  if [ "$any" -eq 0 ]; then
    echo "  ✓ sanctioned address $WANT_EMAIL still resolves to @$WANT_OWNER"
  elif [ "$untestable" -eq 1 ]; then
    echo "  ? sanctioned address $WANT_EMAIL has no pushed commit here — UNTESTABLE, not refuted."
    echo "     Land one commit under it and re-run. Do not treat this as a failure."
  else
    echo "  ⛔ sanctioned address $WANT_EMAIL did NOT resolve to @$WANT_OWNER."
    echo "     Either the address changed on the account, or the API could not be reached."
    echo "     Do not edit the constant until you know which — a wrong allowlist blocks every commit."
  fi
  return "$any"
}

# ── selftest ──────────────────────────────────────────────────────────────────────────────────
# A control that can FAIL: the out-of-scope case must PASS and the in-scope-wrong case must FAIL.
# If both passed, the hook would be inert and every sweep above would be vacuously green.
do_selftest() {
  local P R rc fails=0
  P="$(mktemp -d)"; R="$P/repo"; mkdir -p "$R"
  trap 'rm -rf "$P"' RETURN
  git -C "$R" init -q .
  git -C "$R" config user.email wrong@nowhere.test
  git -C "$R" config user.name wrong

  "$HOOK" --check "$R" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then echo "  ✓ out-of-scope repo (no owner remote) is not gated"
  else echo "  ✗ out-of-scope repo was gated — the hook would red the bats corpus"; fails=$((fails+1)); fi

  git -C "$R" remote add origin "https://github.com/$WANT_OWNER/probe.git"
  "$HOOK" --check "$R" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 1 ]; then echo "  ✓ in-scope repo with a wrong identity is REFUSED"
  else echo "  ✗ in-scope repo with a wrong identity PASSED — the gate is inert"; fails=$((fails+1)); fi

  git -C "$R" config user.email "$WANT_EMAIL"
  "$HOOK" --check "$R" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq 0 ]; then echo "  ✓ in-scope repo with the sanctioned identity is allowed"
  else echo "  ✗ sanctioned identity was refused — the gate blocks correct work"; fails=$((fails+1)); fi

  echo; [ "$fails" -eq 0 ] && { echo "  selftest: PASS"; return 0; }
  echo "  selftest: FAIL ($fails)"; return 1
}

case "${1:-}" in
  check)              shift; do_check "${1:-}" ;;
  repair)             shift; do_repair "${1:-}" ;;
  install)            shift; do_install "${1:-}" ;;
  sweep)              shift; do_sweep "${1:-}" ;;
  verify-attribution) shift; do_verify_attribution "${1:-}" ;;
  selftest)           do_selftest ;;
  ''|-h|--help)       usage ;;
  *)                  die2 "unknown mode: $1" ;;
esac
