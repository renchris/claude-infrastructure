#!/bin/bash
# loaded-untracked-lint — the RATCHET that stops a file the HARNESS AUTO-LOADS from living outside git.
#
# THE RULE: every file under a directory Claude Code auto-loads as project context must be either
# TRACKED or IGNORED. Untracked-and-ignored is fine and deliberate (settings.local.json, tmp/, logs/,
# worktrees/ — the repo's .gitignore already carves those out). Untracked-and-NOT-ignored is the
# defect: the harness reads it into every session, so it is load-bearing policy, and git protects
# none of it. One `git clean -f -d` deletes it with no trace and no diff.
#
# THE INCIDENT (backlog b7e127506fda, measured 2026-09-08). `.claude/rules/agent-operating-lessons.md`
# — 8,165 bytes, 5 active rules and 19 demoted pointers, maintained as recently as 2026-09-06 — was
# injected into EVERY interactive session in this repo under the harness's own label "project
# instructions, checked into the codebase". It was checked into nothing:
#     git ls-tree -r origin/main --name-only -- .claude/rules   ->  0 files
#     git check-ignore -v .claude/rules/agent-operating-lessons.md  ->  rc 1 (NOT ignored, just untracked)
# Its only copies were that one working-tree file and auto-`checkpoint:` commits on non-trunk refs.
# Meanwhile origin/main DID track .claude/CLAUDE.md, .claude/settings.json and .claude/commands/ship.md
# — so .claude/ was a tracked directory with exactly one unprotected child, which is the shape that
# makes this invisible: the directory looks cared for.
#
# WHY THE SCOPE IS "LOADED", NOT "UNTRACKED". A guard on every untracked file in the repo would fire
# on scratch, settings backups and half-finished work, and would be turned off within a week. The
# discriminator is whether the HARNESS reads the path, and git already owns the second half of the
# predicate: `--exclude-standard` means a path the repo deliberately ignores can never be a finding.
# So the rule is exactly "loaded AND not ignored AND not tracked", and each of the three clauses is
# doing work.
#
# WHY IT IS NOT SCOPED TO THE LANDING DIFF. A file that was never `git add`ed appears in NO diff, so
# every own-scope set the gate builds is structurally blind to it — the same blindness measured in
# memory gate-scope-from-git-diff-is-blind-to-untracked. This arm is therefore a WHOLE-TREE
# predicate, and it is cheap enough to be one: a single `git ls-files` per scope, no file reads.
#
# THE ATTRIBUTION CAVEAT, stated rather than hidden (memory: gate-attributes-by-reachability-not-
# causation). This can refuse a land over a loaded file the lander did not create. Two things make
# that acceptable here and not merely tolerable: `git ls-files --others` is PER-WORKTREE, so a
# sibling session's untracked file in the shared checkout cannot reach an isolated lander; and the
# cure is one `git add` of a file that is, by construction, policy every session in the repo is
# already obeying.
#
# Usage:  loaded-untracked-lint.sh [<repo-root>]        (default: the git toplevel of $PWD)
#         loaded-untracked-lint.sh --selftest
# Env:    CC_LOADED_SCOPES  space-separated pathspecs to judge
#                           (default: ".claude CLAUDE.md CLAUDE.global.md")
#
# Exit: 0 = clean — every loaded path is tracked or deliberately ignored
#       1 = RED   — a loaded path is untracked and not ignored
#       2 = CANNOT DETERMINE (no git, not a repo, unreadable root) — LOUD, never a silent 0, because
#           an indeterminate check that passes is indistinguishable from a working one.
set -uo pipefail

# CLAUDE.global.md is the global-instructions SSOT install.sh copies to ~/.claude/CLAUDE.md, so an
# untracked one reaches every session while being in no revision. Bare "CLAUDE.md" is RETAINED
# deliberately: this repo has no root one any more (backlog c3647a090021), so the pathspec matches
# nothing and costs nothing — but it goes red the moment someone re-adds an untracked root copy.
DEFAULT_SCOPES=".claude CLAUDE.md CLAUDE.global.md"

lint_repo() {
  local root="$1"
  [ -n "$root" ] && [ -d "$root" ] || { echo "loaded-untracked-lint: CANNOT DETERMINE — no readable repo root '$root'"; return 2; }
  command -v git >/dev/null 2>&1 || { echo "loaded-untracked-lint: CANNOT DETERMINE — git(1) is not on PATH"; return 2; }
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "loaded-untracked-lint: CANNOT DETERMINE — '$root' is not inside a git work tree"; return 2; }

  local findings n
  # POSITIONAL PARAMS, not an array: /bin/bash on macOS is 3.2, where "${arr[@]}" of an EMPTY array
  # is an unbound-variable error under set -u — the lint would die instead of reaching its own LOUD
  # arm. And `${CC_LOADED_SCOPES-...}`, never `:-`: `:-` collapses SET-BUT-EMPTY into the default, so
  # an operator who blanked the scope set would get a full-strength run and never learn the variable
  # was ignored (memory: harness-default-collapses-the-states-under-test).
  # shellcheck disable=SC2086  # word splitting is the contract: the scope set is a space-separated list
  set -- ${CC_LOADED_SCOPES-$DEFAULT_SCOPES}
  [ "$#" -gt 0 ] || { echo "loaded-untracked-lint: CANNOT DETERMINE — the loaded-scope set is empty, so this lint judges nothing"; return 2; }

  # DRAINED into a variable, never piped into `grep -q`: under pipefail a `producer | grep -q` fails
  # on the very input it matched (memory: grep-q-under-pipefail-inverts-the-verdict).
  findings="$(git -C "$root" ls-files --others --exclude-standard -- "$@" 2>/dev/null)"
  n="$(printf '%s' "$findings" | grep -c . || true)"

  if [ "$n" -eq 0 ]; then
    echo "  OK   loaded-untracked  every path under [$*] is tracked or deliberately ignored"
    return 0
  fi
  echo "  RED  loaded-untracked  $n file(s) the harness AUTO-LOADS are untracked and NOT gitignored:"
  printf '%s\n' "$findings" | sed 's/^/         /'
  echo "         These are read into every session in this repo and git protects none of them —"
  echo "         one 'git clean -f -d' deletes them with no diff and no trace."
  echo "         Cure, in this same commit:  git add $(printf '%s' "$findings" | tr '\n' ' ')"
  echo "         If a path is genuinely scratch, ignore it explicitly in .gitignore instead."
  return 1
}

# ── --selftest: prove BOTH directions fire. A test that can only pass proves nothing. ──────────────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)" || { echo "loaded-untracked-lint --selftest: CANNOT RUN — mktemp failed"; exit 2; }
  trap 'rm -rf "$d"' EXIT
  fails=0

  # THE FIXTURES REPLICATE THE SUBJECT'S WHOLE IGNORE STACK, and are pinned so the operator's own
  # git config cannot decide the verdict (memory: probe-subprocess-inherits-the-callers-environment).
  # This is not decoration: ~/.gitignore_global on this machine contains `.claude/`, and the repo's
  # own .gitignore re-admits it with `!.claude/`. A fixture built without BOTH halves goes green for
  # the wrong reason on this box and red for the wrong reason on a hermetic off-box runner.
  printf '%s\n' '.claude/' > "$d/global-ignore"
  printf '[core]\n\texcludesFile = %s\n' "$d/global-ignore" > "$d/gitconfig"
  : > "$d/gitconfig-system"
  export GIT_CONFIG_GLOBAL="$d/gitconfig" GIT_CONFIG_SYSTEM="$d/gitconfig-system"

  mkrepo() {  # $1 = name -> echoes the repo path; hermetic: no remote, so the identity pre-commit
              # hook is inert here by its own documented scope, and nothing is ever committed anyway.
    local r="$d/$1"
    mkdir -p "$r" || return 1
    git -C "$r" init -q 2>/dev/null || return 1
    printf '%s\n' '!.claude/' '.claude/settings.local.json' > "$r/.gitignore"
    git -C "$r" add .gitignore 2>/dev/null || return 1
    printf '%s' "$r"
  }

  # (i) NEGATIVE FIXTURE — a loaded-but-untracked rules file. Must go RED.
  ri="$(mkrepo untracked_rules)" || { echo "SELFTEST FAIL: could not build fixture (i)"; fails=1; ri=""; }
  if [ -n "$ri" ]; then
    mkdir -p "$ri/.claude/rules"
    printf 'a loaded rule\n' > "$ri/.claude/rules/lesson.md"
    lint_repo "$ri" >/dev/null 2>&1; [ "$?" -eq 1 ] \
      || { echo "SELFTEST FAIL: a loaded-but-untracked .claude/rules file did not go RED"; fails=1; }
  fi

  # (ii) POSITIVE FIXTURE — the same rules file TRACKED, beside an untracked file that IS ignored.
  #      Must go GREEN. This is the arm that proves the guard is not simply "any untracked file".
  rii="$(mkrepo tracked_rules)" || { echo "SELFTEST FAIL: could not build fixture (ii)"; fails=1; rii=""; }
  if [ -n "$rii" ]; then
    mkdir -p "$rii/.claude/rules"
    printf 'a loaded rule\n' > "$rii/.claude/rules/lesson.md"
    git -C "$rii" add .claude/rules/lesson.md 2>/dev/null
    printf '{}\n' > "$rii/.claude/settings.local.json"   # untracked AND gitignored — legal, not a finding
    lint_repo "$rii" >/dev/null 2>&1 \
      || { echo "SELFTEST FAIL: a TRACKED rules file beside an IGNORED untracked file did not go GREEN"; fails=1; }
  fi

  # (iii) the ignored-only control, isolated: with NO rules file at all, an untracked ignored file
  #       alone must stay GREEN. Separates clause 2 from clause 3 of the predicate.
  riii="$(mkrepo ignored_only)" || { echo "SELFTEST FAIL: could not build fixture (iii)"; fails=1; riii=""; }
  if [ -n "$riii" ]; then
    mkdir -p "$riii/.claude"
    printf '{}\n' > "$riii/.claude/settings.local.json"
    lint_repo "$riii" >/dev/null 2>&1 \
      || { echo "SELFTEST FAIL: an untracked-but-IGNORED file alone did not go GREEN"; fails=1; }
  fi

  # (iv) SCOPE control — the same untracked file OUTSIDE the loaded set must NOT be a finding.
  #      Without this, the lint could be a whole-repo untracked check wearing a scope's clothes.
  riv="$(mkrepo outside_scope)" || { echo "SELFTEST FAIL: could not build fixture (iv)"; fails=1; riv=""; }
  if [ -n "$riv" ]; then
    mkdir -p "$riv/notes"
    printf 'scratch\n' > "$riv/notes/scratch.md"
    lint_repo "$riv" >/dev/null 2>&1 \
      || { echo "SELFTEST FAIL: an untracked file OUTSIDE the loaded scope was treated as a finding"; fails=1; }
  fi

  # (v) LOUD arms — an indeterminate run must exit 2, never 0.
  lint_repo "$d/does-not-exist" >/dev/null 2>&1; [ "$?" -eq 2 ] \
    || { echo "SELFTEST FAIL: a missing repo root did not exit 2 (LOUD)"; fails=1; }
  if [ -n "$ri" ]; then
    ( CC_LOADED_SCOPES="" lint_repo "$ri" ) >/dev/null 2>&1; [ "$?" -eq 2 ] \
      || { echo "SELFTEST FAIL: an EMPTY loaded-scope set did not exit 2 (a scope-less lint judges nothing)"; fails=1; }
  fi
  mkdir -p "$d/plain"
  lint_repo "$d/plain" >/dev/null 2>&1; [ "$?" -eq 2 ] \
    || { echo "SELFTEST FAIL: a non-repo directory did not exit 2 (LOUD)"; fails=1; }

  if [ "$fails" -eq 0 ]; then
    echo "loaded-untracked-lint --selftest: 7/7 — RED on a loaded-but-untracked .claude/rules file; GREEN on that file TRACKED beside an untracked-but-IGNORED one, on an ignored file alone, and on an untracked file OUTSIDE the loaded scope; LOUD (exit 2) on a missing root, an empty scope set, and a non-repo directory."
    exit 0
  fi
  echo "loaded-untracked-lint --selftest: FAILED — the lint does not discriminate."
  exit 1
fi

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
fi
lint_repo "$ROOT"
exit $?
