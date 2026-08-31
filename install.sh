#!/bin/bash
# Install Claude Code infrastructure — symlinks, copies, LaunchAgents
#
# Usage:
#   ./install.sh                                    # Install everything (default config dir)
#   ./install.sh --dry-run                           # Preview without changes
#   ./install.sh --config-dir ~/.claude-secondary    # Install to alternate config dir
#                                                    # (skips global items: bin/, LaunchAgents)
#
# Idempotent: safe to run multiple times.
#
# MUST be run from the PRIMARY checkout: a global install links ~/.claude at this script's own
# directory, so running it from a linked worktree points the live layer at a directory that is
# entitled to be deleted. That case is REFUSED (CC_INSTALL_ALLOW_WORKTREE=1 overrides); see the
# guard below. --config-dir installs are unaffected.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="$HOME/.claude"
DRY_RUN=false
WIRE_HOOKS=false
ORIG_ARGS="$*"          # kept verbatim for the worktree-refusal re-run hint below

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --wire-hooks) WIRE_HOOKS=true; shift ;;   # additively merge the settings.example.json hook/deny/ask roster
    *)            echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Global items (bin/, LaunchAgents, versions) only for default config dir
IS_GLOBAL=false
[[ "$CONFIG_DIR" == "$HOME/.claude" ]] && IS_GLOBAL=true

# --- REFUSE a global install from a linked worktree -------------------------------------------
# link_file points every ~/.claude/** entry at $REPO_DIR, and $REPO_DIR is just $0's directory
# (line 14) — it has never been git-aware. Run from a linked worktree, the entire live layer
# therefore targets a directory that `git worktree remove` and scripts/worktree-gc.sh are both
# entitled to delete, at which point every hook, command, skill and cc-* tool becomes a dangling
# symlink simultaneously. The deploy lane cannot repair that: deploy-live.sh only reaches its
# install.sh call (line 283-284) after advancing to a green-stamped tree, and the hooks that
# produce a green stamp are the same links that just died. That is the dead deploy lane.
#
# Scoped to the GLOBAL install ($CONFIG_DIR == $HOME/.claude) DELIBERATELY — a blanket refusal
# would be self-defeating. Every automated caller passes --config-dir into a throwaway dir
# (tests/install-wire-hooks.bats x4, docs/activation/wiring-all.sh), and BOTH postland-verify.sh
# (which mints wt-run-$$ per run) and the /ship gate (ship-land.sh refuses to land from the
# shared checkout) execute that suite FROM A LINKED WORKTREE BY CONSTRUCTION. Refusing them
# would turn every postland run red ⇒ no tree ever earns a green stamp ⇒ deploy-live.sh stops
# advancing: the exact failure this guard exists to prevent. deploy-live.sh, its launchd job and
# wiring-all.sh all resolve to the fixed primary checkout and are unaffected.
#
# --dry-run is NOT exempt: a preview that prints "would link ~/.claude/hooks/x → <worktree>/..."
# is previewing the catastrophe, so the honest answer to "what would happen?" is the refusal.
# No automated caller uses --dry-run (only README.md's quickstart).
#
# Detection FAILS OPEN. A tarball checkout, a fresh machine, or a git that cannot answer must
# still install normally; the dangerous state is specifically "this IS a linked worktree", which
# --absolute-git-dir names unambiguously (<main>/.git/worktrees/<name>, vs <repo>/.git in the
# primary checkout). `git -C "$REPO_DIR"` and not a bare `git`: the CWD is unrelated to $0.
IS_LINKED_WORKTREE=false
case "$(git -C "$REPO_DIR" rev-parse --absolute-git-dir 2>/dev/null || true)" in
  */.git/worktrees/*) IS_LINKED_WORKTREE=true ;;
esac

if $IS_LINKED_WORKTREE; then
  # Resolve the canonical checkout so the message can hand over an exact re-run command.
  # --git-common-dir is ".git" (relative) in the primary and absolute in a linked worktree.
  _common="$(git -C "$REPO_DIR" rev-parse --git-common-dir 2>/dev/null || true)"
  case "$_common" in
    "") PRIMARY_DIR="" ;;
    /*) PRIMARY_DIR="$(cd "$_common/.." 2>/dev/null && pwd || true)" ;;
    *)  PRIMARY_DIR="$(cd "$REPO_DIR/$_common/.." 2>/dev/null && pwd || true)" ;;
  esac

  if $IS_GLOBAL && [[ "${CC_INSTALL_ALLOW_WORKTREE:-}" != "1" ]]; then
    {
      echo "✗ install.sh: REFUSING a global install from a linked worktree."
      echo "    worktree   : $REPO_DIR"
      [[ -n "$PRIMARY_DIR" ]] && echo "    primary    : $PRIMARY_DIR"
      echo "    config dir : $CONFIG_DIR"
      echo ""
      echo "  Every $CONFIG_DIR symlink would point into this worktree and would dangle the"
      echo "  moment it is removed (git worktree remove / scripts/worktree-gc.sh), taking the"
      echo "  live layer and the autonomous deploy lane with it."
      echo ""
      if [[ -n "$PRIMARY_DIR" ]]; then
        echo "  Re-run from the primary checkout:"
        echo "      $PRIMARY_DIR/install.sh${ORIG_ARGS:+ $ORIG_ARGS}"
      else
        echo "  Re-run from the primary checkout (the symlink source for $CONFIG_DIR)."
      fi
      echo ""
      echo "  --config-dir <dir> installs are unaffected; CC_INSTALL_ALLOW_WORKTREE=1 overrides."
    } >&2
    exit 1
  fi

  # Non-global from a worktree is NOT refused (it is the automated callers' path), but it is not
  # silent either: an alt config dir that outlives this worktree — ~/.claude-secondary and the
  # other real per-account dirs, as opposed to a test tmpdir — inherits exactly the same dangling
  # links. One line, to stderr, so it cannot corrupt a --dry-run diff or a caller parsing stdout.
  echo "  ⚠ installing from a linked worktree ($REPO_DIR) — links into $CONFIG_DIR will dangle if it is removed" >&2
fi

# --- REFUSE a global install from a STALE checkout ---------------------------------------------
#
# THE DEFECT (observed 2026-08-01, and it reported SUCCESS while doing it): a sibling session left
# a local commit on main in the shared checkout. `git merge-base --is-ancestor origin/main HEAD`
# was therefore false — trunk held a commit this tree did not. install.sh has never been trunk-
# aware, so it happily deployed that tree: it printed "✓ CLAUDE.md (554 lines)" and exit 0 while
# copying a version WITHOUT the change that had just landed, and every hooks/ symlink kept
# resolving to the stale content. The land was verified, the deploy was verified, and the live
# layer was still wrong — the failure is invisible precisely because both halves report green.
#
# THE PREDICATE is containment, not equality: `origin/main` must be an ANCESTOR of HEAD. Being
# AHEAD of trunk is normal and allowed (that is every pre-land state); being BEHIND is what
# silently deploys yesterday's tree. A detached HEAD or a feature branch missing trunk content
# fails the same test, correctly — deploying either drops landed fixes out of the live layer.
#
# FRESHNESS OF THE REF ITSELF: `origin/main` is a local ref, so an unfetched repo can pass this
# check vacuously. We attempt one BOUNDED fetch first and say plainly which answer we have — a
# guard that cannot distinguish "verified current" from "could not check" is the same class of
# lie it exists to catch. No network ⇒ we still compare, and we SAY the comparison may be stale.
#
# SCOPE: a global install (the live ~/.claude layer) is REFUSED. A --config-dir install WARNS
# loudly instead — same reasoning as the worktree guard directly above: automated callers use that
# path, and bricking them costs more than the staleness does. CC_INSTALL_ALLOW_STALE=1 overrides
# both. --dry-run is NOT exempt: previewing a stale tree previews the wrong tree.
if git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1; then
  STALE_NOTE=""
  if git -C "$REPO_DIR" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    if command -v timeout >/dev/null 2>&1; then
      timeout 15 git -C "$REPO_DIR" fetch --quiet origin main >/dev/null 2>&1 \
        && STALE_NOTE="origin/main re-fetched just now" \
        || STALE_NOTE="could NOT reach origin — compared against the last-known origin/main, which may itself be behind"
    else
      STALE_NOTE="no timeout(1) — did not fetch; compared against the last-known origin/main, which may itself be behind"
    fi

    if ! git -C "$REPO_DIR" merge-base --is-ancestor origin/main HEAD >/dev/null 2>&1; then
      BEHIND_N="$(git -C "$REPO_DIR" rev-list --count HEAD..origin/main 2>/dev/null || echo '?')"
      if [[ "${CC_INSTALL_ALLOW_STALE:-}" == "1" ]]; then
        echo "  ⚠ STALE checkout ($BEHIND_N commit(s) on origin/main are absent here) — proceeding: CC_INSTALL_ALLOW_STALE=1" >&2
      elif $IS_GLOBAL; then
        {
          echo "✗ install.sh: REFUSING a global install from a STALE checkout."
          echo "    checkout   : $REPO_DIR"
          echo "    behind     : $BEHIND_N commit(s) on origin/main are NOT in this tree"
          echo "    ref state  : $STALE_NOTE"
          echo "    config dir : $CONFIG_DIR"
          echo ""
          echo "  Deploying now would copy pre-trunk content into $CONFIG_DIR and leave every"
          echo "  hooks/ bin/ scripts/ symlink resolving to it — while printing success. That is"
          echo "  the 2026-08-01 failure this guard exists to make impossible."
          echo ""
          echo "  Reconcile first, then re-run:"
          echo "      git -C $REPO_DIR pull --rebase origin main"
          echo "      $REPO_DIR/install.sh${ORIG_ARGS:+ $ORIG_ARGS}"
          echo ""
          echo "  (A local commit of your own is fine — rebase preserves it. CC_INSTALL_ALLOW_STALE=1"
          echo "   overrides this refusal; --config-dir installs warn instead of refusing.)"
        } >&2
        exit 1
      else
        echo "  ⚠ STALE checkout — $BEHIND_N commit(s) on origin/main are absent here; $CONFIG_DIR gets pre-trunk content ($STALE_NOTE)" >&2
      fi
    fi
  else
    # No origin/main to compare against (fresh clone, no remote, a fork). CANNOT TELL is reported,
    # never silently treated as current — an absent oracle is a third state, not a pass.
    echo "  ⚠ no origin/main ref — cannot verify this checkout is current; deploying unchecked" >&2
  fi
fi

installed=0
skipped=0
# Hoisted from the settings-hooks section (was initialised just above it) so the LaunchAgents block
# further down can COUNT a refused activation instead of swallowing it. Nothing between here and
# there read it before.
warnings=0

run() {
  if $DRY_RUN; then
    echo "  [dry-run] $*"
  else
    "$@"
  fi
}

link_file() {
  local src="$1" dest="$2"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    skipped=$((skipped + 1))
    return
  fi
  # A REAL file at $dest whose content DIFFERS from $src is unversioned work: `ln -sf` below
  # replaces it and it is gone with no git path back. Back it up first — the same one-time
  # migration guard DEPLOY-NOW.sh hand-rolls below, hoisted to the chokepoint because the skills
  # loop now recurses (see "--- Skills ---") and so reaches nested REAL files that predate the
  # per-file symlink model. Inert wherever the invariant already holds: identical content, an
  # existing symlink, and a fresh path all skip it, so no established path changes behaviour.
  if [[ -f "$dest" && ! -L "$dest" ]] && ! diff -q "$src" "$dest" >/dev/null 2>&1; then
    run cp -a "$dest" "$dest.pre-link.bak"
    echo "  ⚠ $dest was an unversioned real file that differs from $src — saved to $dest.pre-link.bak"
  fi
  run ln -sf "$src" "$dest"
  echo "  ✓ $dest → $src"
  installed=$((installed + 1))
}

copy_file() {
  local src="$1" dest="$2"
  if [[ -L "$dest" ]]; then
    # Replace symlink with real copy (breaks dependency on primary)
    run rm "$dest"
  elif [[ -f "$dest" ]] && diff -q "$src" "$dest" >/dev/null 2>&1; then
    skipped=$((skipped + 1))
    return
  fi
  run cp "$src" "$dest"
  run chmod +x "$dest" 2>/dev/null || true
  echo "  ✓ $dest"
  installed=$((installed + 1))
}

ensure_real_dir() {
  local dir="$1"
  if [[ -L "$dir" ]]; then
    echo "  ⚠ $dir is a directory symlink — replacing with real directory"
    run rm "$dir"
  fi
  run mkdir -p "$dir"
}

echo "Claude Code Infrastructure Installer"
echo "====================================="
echo "Config dir: $CONFIG_DIR"
$DRY_RUN && echo "(dry-run mode — no changes will be made)"
$IS_GLOBAL || echo "(non-default config — skipping global items)"
echo ""

# --- Accounts SSOT bootstrap + account-map codegen ---
# A first-time install has no accounts.json (it's gitignored — real emails live there): seed it
# from the generic template so the rest of this script, and every account-aware tool it deploys,
# has something to read. One account is enough to start; accounts.json's own comments explain
# how to add more.
if [[ ! -f "$REPO_DIR/accounts.json" ]]; then
  if [[ -f "$REPO_DIR/accounts.json.example" ]]; then
    echo "No accounts.json — seeding one from accounts.json.example (edit it: your email, account count)"
    run cp "$REPO_DIR/accounts.json.example" "$REPO_DIR/accounts.json"
  else
    echo "  ⚠ no accounts.json and no accounts.json.example — account-aware tools (cc-board, handoff-fire, …) will be unavailable" >&2
    warnings=$((warnings + 1))
  fi
fi
# Regenerate lib/account-map.generated.sh from accounts.json so it never drifts, for both a
# fresh install and every subsequent re-run after accounts.json changes.
if [[ -f "$REPO_DIR/accounts.json" ]]; then
  if $DRY_RUN; then
    echo "  [dry-run] scripts/gen-account-map.sh"
  else
    "$REPO_DIR/scripts/gen-account-map.sh" || { echo "  ⚠ gen-account-map.sh failed — account-name/config-dir lookups may be stale" >&2; warnings=$((warnings + 1)); }
  fi
fi

# --- Hooks ---
echo "Hooks → $CONFIG_DIR/hooks/"
ensure_real_dir "$CONFIG_DIR/hooks"
ensure_real_dir "$CONFIG_DIR/hooks/lib"
for hook in "$REPO_DIR"/hooks/*.sh; do
  [[ -f "$hook" ]] || continue
  link_file "$hook" "$CONFIG_DIR/hooks/$(basename "$hook")"
done
# *.py hooks too: settings.json wires curl-gate.py and enforce-email-formatting.py by path, but
# this loop globbed *.sh only, so a python hook could never be deployed FROM the repo — which is
# why both lived live-only and unversioned until 2026-07-25. Same failure shape as the missing
# agents/ leg: a brand-new tracked file is not linked at all, however current the checkout.
for hook in "$REPO_DIR"/hooks/*.py; do
  [[ -f "$hook" ]] || continue
  link_file "$hook" "$CONFIG_DIR/hooks/$(basename "$hook")"
done
for lib in "$REPO_DIR"/hooks/lib/*.sh; do
  [[ -f "$lib" ]] || continue
  link_file "$lib" "$CONFIG_DIR/hooks/lib/$(basename "$lib")"
done

# --- Git hooks (githooks/) ---
# GIT hooks, not Claude hooks: git runs these itself out of .git/hooks, so they never passed
# through any loop above and were, until 2026-08-08, outside the deploy lane entirely.
# `commit-msg` existed as two byte-identical HAND-PLACED copies (this repo's .git/hooks and
# ~/.git-template/hooks) that no install path owned, no test covered, and nothing would have
# noticed the loss of. That is the same class this file already documents twice above — a guard
# that is real on exactly one machine — which is why githooks/ is now tracked.
#
# 🚨 COPIES EVERYWHERE, NEVER SYMLINKS — this shipped as a symlink for six hours and that was a
# critical bug. A link into the WORKING TREE points at a file that exists only on branches
# containing it. githooks/ landed 2026-08-08, so 384 of 400 local branches lack it, and a single
# `git checkout <older-branch>` or `git bisect` in the shared checkout dangles the link. Git fails
# OPEN on a dangling hook — no warning, no exit code — so one checkout in one directory silently
# ungated all 207 worktrees at once, and this repo's own CLAUDE.md notes the shared checkout
# "frequently sits on another session's feature branch". The same argument applies to the template,
# where a link would additionally point outside any checkout at all.
#
# The cost of a copy is drift, and drift is the lesser failure: it is visible on inspection, this
# loop re-asserts it on every deploy, and scripts/git-identity-assert.sh sweep reports it. The
# dangling link was silent and permanent.
#
# pre-merge-commit is pre-commit's implementation under git's OTHER name for the merge path —
# without it a `git merge`/`git pull` commit is ungated by hook name alone.
echo ""
echo "Git hooks → repo .git/hooks/ + $HOME/.git-template/hooks/ (copies, never symlinks)"
_gh_install() {   # <destdir>
  local _d="$1" gh base dest
  ensure_real_dir "$_d"
  for gh in "$REPO_DIR"/githooks/*; do
    [[ -f "$gh" ]] || continue
    base="$(basename "$gh")"
    dest="$_d/$base"
    # Never clobber a FOREIGN hook — recognised by our content marker, so our own older copy is
    # upgraded rather than skipped.
    if [[ -e "$dest" || -L "$dest" ]] && ! grep -q 'cc-git-identity-gate\|commit-msg — reject' "$dest" 2>/dev/null; then
      echo "  ⚠ $dest is a foreign hook — left alone; chain it by hand" >&2
      warnings=$((warnings + 1)); continue
    fi
    copy_file "$gh" "$dest"
  done
  # pre-merge-commit shares pre-commit's body; git runs it under a different name for merges.
  if [[ -f "$REPO_DIR/githooks/pre-commit" ]]; then
    if [[ -e "$_d/pre-merge-commit" || -L "$_d/pre-merge-commit" ]] \
       && ! grep -q 'cc-git-identity-gate' "$_d/pre-merge-commit" 2>/dev/null; then
      echo "  ⚠ $_d/pre-merge-commit is a foreign hook — left alone" >&2
      warnings=$((warnings + 1))
    else
      copy_file "$REPO_DIR/githooks/pre-commit" "$_d/pre-merge-commit"
    fi
  fi
}
_gh_common="$(git -C "$REPO_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
if [[ -n "$_gh_common" ]]; then
  _gh_install "$_gh_common/hooks"
else
  echo "  ⚠ cannot resolve git-common-dir — repo git hooks NOT installed" >&2
  warnings=$((warnings + 1))
fi
_gh_install "$HOME/.git-template/hooks"

# --- init.templateDir: set it, but NEVER from an ephemeral HOME --------------------------------
#
# init.templateDir is what makes the template reach a new repo at all. Unset, every clone lands
# unguarded and the copies above are inert decoration. So the setting itself is load-bearing and
# this guard must not suppress it on a real machine.
#
# THE DEFECT (measured 2026-08-11): the VALUE is $HOME-derived and the WRITE is `--global`, and
# those two are not bound to the same HOME. Run under an isolated gate HOME, $HOME is a temp dir,
# so the value becomes e.g. /var/folders/.../T/gate-home.qhMxtm/.git-template — while the write
# destination can still be the operator's REAL global config, because git resolves `--global`
# through GIT_CONFIG_GLOBAL / XDG_CONFIG_HOME before it ever looks at $HOME/.gitconfig, and a gate
# that overrides HOME does not necessarily override those. The temp dir is then deleted, every
# later `git init` on the box warns "templates not found" and creates NO hooks/ directory, and the
# symptom surfaces three tests away from the cause (tests/ship-land.bats 14/15/33 write
# $ORIGIN/hooks/update into a bare repo that no longer has one) where it reads as a test bug.
#
# THE DISCRIMINATOR is the passwd database, not a path denylist — scripts/lib/real-home.sh owns it
# and carries the full rationale, the resolution ladder (bash `~<user>` first, dscl/getent as the
# cross-check), and why the username comes from `id -un` rather than $USER.
#
# FAIL DIRECTION HERE: a HOME that is provably NOT the passwd home ⇒ SKIP the write, one line to
# stderr, install continues. The exit status is unchanged and `warnings` is deliberately NOT
# incremented — an isolated HOME is the *correct* state for every gate/bats caller (they all pass
# --config-dir into a throwaway dir), so counting it would make the common case report a defect.
# An unresolvable passwd home fails OPEN inside the lib, so a fresh machine still gets the setting.
#
# A MISSING LIB SKIPS THE WRITE. The lib lives in this same checkout, so its absence means a
# broken/partial tree; between "silently skip a load-bearing setting" and "write a path we cannot
# vouch for into the operator's global git config", only the first is recoverable and loud.
if [[ -r "$REPO_DIR/scripts/lib/real-home.sh" ]]; then
  # shellcheck source=scripts/lib/real-home.sh
  # The `source=` hint above resolves the path but does NOT make shellcheck follow it without -x,
  # and ship-land's statics gate runs a BARE `shellcheck` (scripts/ship-land.sh:2326) while
  # .shellcheckrc sets only disable=SC2001,SC2015. So this line has reddened that gate for every
  # land that TOUCHES install.sh since the lib was introduced — pre-existing, and invisible until a
  # diff invalidates the file's blob-sha memo and forces a re-scan.
  # shellcheck disable=SC1091
  . "$REPO_DIR/scripts/lib/real-home.sh"
else
  cc_home_is_passwd_home() { CC_HOME_NOT_OURS_WHY="scripts/lib/real-home.sh is missing from $REPO_DIR"; return 1; }
fi

if ! cc_home_is_passwd_home; then
  echo "  ⚠ init.templateDir NOT set — $CC_HOME_NOT_OURS_WHY; refusing to write a path derived from an ephemeral HOME into the global git config" >&2
elif [[ "$(git config --global --get init.templateDir || true)" != "$HOME/.git-template" ]]; then
  run git config --global init.templateDir "$HOME/.git-template"
  echo "  ✓ git config --global init.templateDir → $HOME/.git-template"
fi

# --- Shared shell libs (lib/) ---
# config-mirror.zsh in particular: it decides which state each account config dir SHARES vs
# isolates, and it lived for months as an unversioned real file at ~/.claude/lib/ — a config with
# real blast radius, no history, no review, and no way to tell drift from intent. Linking it from
# the repo puts the isolate-set under the same review as everything else. desk.zsh was already
# linked here by hand; this generalises that.
echo ""
echo "Shell libs → $CONFIG_DIR/lib/"
ensure_real_dir "$CONFIG_DIR/lib"
# Both extensions: .zsh for zsh-only libs (config-mirror, desk), .sh for the ones written
# bash/zsh-portable so a bats suite can source them under bash (cc-resume-shell.sh). Globbing
# only *.zsh silently skipped every .sh lib — a lib the launcher sources but install never
# deploys is dead on any machine but the one it was written on.
for zlib in "$REPO_DIR"/lib/*.zsh "$REPO_DIR"/lib/*.sh; do
  [[ -f "$zlib" ]] || continue
  link_file "$zlib" "$CONFIG_DIR/lib/$(basename "$zlib")"
done
# account-map.generated.sh (regenerated above from accounts.json) — the account-name/config-dir
# lookup every cc-*/lr-*/handoff-fire.sh tool sources. .sh, not .zsh, so it needs its own line.
[[ -f "$REPO_DIR/lib/account-map.generated.sh" ]] && link_file "$REPO_DIR/lib/account-map.generated.sh" "$CONFIG_DIR/lib/account-map.generated.sh"

# --- Commands ---
echo ""
echo "Commands → $CONFIG_DIR/commands/"
ensure_real_dir "$CONFIG_DIR/commands"
for cmd in "$REPO_DIR"/commands/*.md; do
  [[ -f "$cmd" ]] || continue
  link_file "$cmd" "$CONFIG_DIR/commands/$(basename "$cmd")"
done

# --- Agents (custom subagent types) ---
# Same per-file symlink model as commands above: agents are NAME-invoked model surfaces
# (`subagent_type: "deep-research"`), so they have zero grep-able callers and drift silently.
# Until 2026-07-25 install.sh had NO agents leg at all — every $REPO_DIR/<dir> it touched was
# hooks/commands/skills/bin/launchd/statusline, never agents — so the repo's four agent files
# were spawnable NOWHERE while all five config dirs carried a DIFFERENT, unversioned set. That
# is not deploy-lag (there was no leg to lag); it was an inverse orphan in both directions.
# Only touches agent NAMES present in the repo — other live agents are left untouched.
if [[ -d "$REPO_DIR/agents" ]]; then
  echo ""
  echo "Agents → $CONFIG_DIR/agents/"
  ensure_real_dir "$CONFIG_DIR/agents"
  for agent in "$REPO_DIR"/agents/*.md; do
    [[ -f "$agent" ]] || continue
    link_file "$agent" "$CONFIG_DIR/agents/$(basename "$agent")"
  done
fi

# --- Bin tools (global only) ---
if $IS_GLOBAL; then
  echo ""
  echo "Bin tools → ~/bin/"
  mkdir -p "$HOME/bin"
  # claude-bump-models + screenshot-to-clipboard.sh were in NEITHER this list nor sync.sh's, so
  # nothing reconciled them in either direction — ~/bin/claude-bump-models silently gained the
  # frontier family while the repo copy could not bump that tier at all (audit 02, 2026-07-25).
  # browsermcp-wrapper.sh dropped 2026-08-11 with the server it wrapped (0 invocations / 3,504
  # transcripts / 30 d; upstream frozen 2025-04-11). Browser work goes through agent-browser.
  for tool in claude-latest claude-update claude-versions claude-kimi \
              claude-bump-models screenshot-to-clipboard.sh; do
    [[ -f "$REPO_DIR/bin/$tool" ]] || continue
    copy_file "$REPO_DIR/bin/$tool" "$HOME/bin/$tool"
  done

  # claude-accounts is SYMLINKED, unlike its copied neighbours above. Those are
  # self-updating launchers that may legitimately diverge from the checkout; this
  # is a read-only SSOT probe whose consumers (cc-board, cc-context --quota,
  # cc-route, handoff-fire, lr-*) must all see the SAME code. As a copy it silently
  # drifted for 2 days (repo gained the last-good quota ledger 2026-07-19; ~/bin
  # stayed on 2026-07-17), so handoff-fire read a stale_quota field the deployed
  # binary never emitted, and sync.sh — which copies ~/bin BACK into the repo with
  # no direction guard — would have clobbered the newer repo version with the stale
  # copy. Symlinking makes drift structurally impossible and turns that sync.sh leg
  # into a no-op (sync_file resolves the link, then short-circuits on identical).
  # Stays at ~/bin (NOT moved to ~/.claude/bin): two hardcoded consumers reference
  # $HOME/bin/claude-accounts by absolute path, and two binaries sharing one
  # /tmp cache would be split-brain. Verified by scripts/deploy-parity-assert.sh.
  link_file "$REPO_DIR/bin/claude-accounts" "$HOME/bin/claude-accounts"

  # dia-cdp-launch.sh — SYMLINKED, and it is the FIFTH instance of the defect this block already
  # records four times: a tool that IS live at ~/bin, IS tracked, and appears in NEITHER the copy
  # list above nor any link site, so nothing reconciles it in either direction and it drifts
  # silently. The four already named here are claude-bump-models and screenshot-to-clipboard.sh
  # (audit 02, 2026-07-25), reso-resume-one, and reso-keepalive (2026-08-12, backlog 8550b6129d9c)
  # — each found by hand, each fixed one at a time, and nothing ever generalised the check. It is
  # generalised now: tests/deploy-parity.bats derives this list from these very loops and requires
  # every ~/bin tool an executable surface names to be claimed here.
  #
  # MEASURED 2026-08-31: ~/bin/dia-cdp-launch.sh was a REAL FILE holding revision c8149d3c1
  # (2026-07-30) while the checkout carried 3dcac1f32 — "an early-exit pipe consumer reads FALSE on
  # a match, and 22 sites were doing it". So the deployed copy still ran the drained construct at
  # its line 123, under its own `set -euo pipefail` at :37: on a MATCH the early-exiting consumer
  # takes SIGPIPE, pipefail promotes it, and the `if` reads FALSE — the health check reports the
  # LaunchAgent NOT loaded precisely when it IS. reso-keepalive's note above describes the same
  # shape in the same words: the landed fix unreachable, the buggy original what actually ran.
  #
  # LINK, not copy, and the file itself asks for it: bin/dia-cdp-launch.sh:46 says "Sourced through
  # $0's PHYSICAL location: ~/bin holds per-file SYMLINKS into the checkout" and carries a readlink
  # preamble to resolve itself. It was written expecting this deploy shape and was not getting it.
  # Its consumers reference the ~/bin path absolutely (launchd/com.chrisren.dia-cdp.plist.disabled
  # and skills/dia-agent/SKILL.md), so ~/bin stays the destination.
  link_file "$REPO_DIR/bin/dia-cdp-launch.sh" "$HOME/bin/dia-cdp-launch.sh"

  # reso-resume-one — SYMLINKED for the same reason, arrived at the hard way. It lived as an
  # UNTRACKED file at ~/.reso/bin/ while boot-resume-launch.sh:89, boot-resume.sh, lr-fire-resume.sh
  # and the resume-sessions runbook all called it, so it sat outside the ship gate, outside the
  # linters and outside every reader that could see it rot — and it rotted for weeks, in the
  # directions that are silent (a pinned binary path, a pinned model generation, a pinned effort).
  # (That wording is deliberate: a comment whose first word after `#` is the linter's own name is
  # parsed as a DIRECTIVE and aborts the file, so this very block once made install.sh unreadable
  # to the gate it is explaining.)
  # A copy here would restore exactly that: the deployed path is what boot-resume execs, so a copy
  # that fell behind would resume the fleet on stale code and say nothing. ~/.reso/bin stays the
  # deployed location because those four callers reference it by absolute path.
  # reso-keepalive joins it, and the gap it closes was SILENT for the same reason the paragraph
  # above describes — measured 2026-08-12 (backlog 8550b6129d9c). bin/reso-keepalive is tracked,
  # lint-covered and carries a 7-case suite, but NOTHING linked it anywhere: ~/.reso/bin/
  # (that wording dodges the same trap the block above names — a comment whose first word after
  # `#` is the linter's own name parses as a DIRECTIVE and aborts the file. It caught this edit.)
  # reso-keepalive was a real file dated 2026-07-04, `#!/bin/zsh`, with ZERO hits for
  # CC_KEEPALIVE_MARKERS — i.e. the pre-410f920c version, carrying the frozen 12-worktree list and
  # WITHOUT the `${VAR:-} swallows an explicit empty` guard fix landed the same day.
  # That made the landed fix unreachable and the buggy original what actually ran on every boot,
  # because scripts/boot-resume.sh falls back to this exact path when resolve_bin comes up empty
  # — and resolve_bin's ladder (beside-script, ../bin, ~/.claude/bin) never reaches ~/.reso/bin.
  # A tracked file that no installer deploys is not "landed", it is a second copy of the truth with
  # the live one winning. Same remedy, same reason: SYMLINK, never copy.
  for _reso_tool in reso-resume-one reso-keepalive; do
    [[ -f "$REPO_DIR/bin/$_reso_tool" ]] || continue
    mkdir -p "$HOME/.reso/bin"
    link_file "$REPO_DIR/bin/$_reso_tool" "$HOME/.reso/bin/$_reso_tool"
  done

  # Accounts SSOT — symlink (repo = source of truth; the knowledge-layer mirror
  # shares ~/.claude/accounts.json into every alt config dir automatically).
  echo ""
  echo "Accounts SSOT → $CONFIG_DIR/accounts.json"
  link_file "$REPO_DIR/accounts.json" "$CONFIG_DIR/accounts.json"

  # Model-config SSOT — same symlink pattern, for the same reason (consolidation audit 02).
  # This was a REAL unversioned file at ~/.claude/model-config.yaml while templates/model-config.yaml
  # separately claimed SSOT in its header: the two drifted in BOTH directions, and the live Opus 5
  # activation existed in no committed file at all. One versioned file + a symlink makes that
  # divergence structurally impossible.
  echo "Model-config SSOT → $CONFIG_DIR/model-config.yaml"
  link_file "$REPO_DIR/model-config.yaml" "$CONFIG_DIR/model-config.yaml"

  # Provider registry — the NON-Claude agent backends behind `claude-accounts --agents`.
  # Symlinked for the same reason as the two above, and TRACKED in git (unlike accounts.json,
  # which is gitignored because it holds real email addresses): this file holds no secrets, only
  # verified facts about what each backend rides and what it bills. Those facts are exactly what
  # must survive in history — a cost verdict that lives only on one machine gets re-litigated,
  # and the whole point of the registry is that a SKIP stays skipped for a recorded reason.
  echo "Provider registry → $CONFIG_DIR/providers.json"
  link_file "$REPO_DIR/providers.json" "$CONFIG_DIR/providers.json"

  # MS365 / Microsoft Graph MCP server → every account's user-scope config.
  # NOT a symlink like the three above, and NOT the knowledge-layer mirror: `mcpServers` lives in
  # `.claude.json`, which is in the isolate-set of all four account dirs (lib/config-mirror.zsh)
  # because it races between concurrent Claude Code processes. So it can only be an idempotent
  # per-dir MERGE — and that merge has to re-run on every install, because a hand-copy is exactly
  # how ms365 came to exist in 1 account dir of 4. Diagnosis: docs/plans/MS365_MCP_ALL_ACCOUNTS.md.
  echo ""
  echo "MS365 MCP server → all account config dirs"
  if [[ ! -x "$REPO_DIR/scripts/ms365-mcp-wire.sh" ]]; then
    echo "  ⚠ scripts/ms365-mcp-wire.sh missing or not executable"
    warnings=$((warnings + 1))
  elif $DRY_RUN; then
    # Read-only preview: --check reports per-dir state and wires nothing. (`run` is not usable —
    # it would echo the command but execute nothing, losing the preview's actual value, which is
    # reporting what is currently unwired. Same reasoning as the kitty step below.)
    echo "  [dry-run] would run scripts/ms365-mcp-wire.sh — current state:"
    "$REPO_DIR/scripts/ms365-mcp-wire.sh" --check 2>&1 | sed 's/^/  /' || true
  elif ! "$REPO_DIR/scripts/ms365-mcp-wire.sh"; then
    echo "  ⚠ ms365 not fully wired — re-run: scripts/ms365-mcp-wire.sh --check"
    warnings=$((warnings + 1))
  fi
fi

# --- Scripts ---
# Primary ~/.claude → SYMLINK (same as hooks/commands above) so edits to the live
# scripts land in the repo directly and can't silently drift out of version control —
# the failure mode observed 2026-07-03, when handoff-fire.sh drifted +198 lines in the
# deployment and was one `install.sh` (copy_file clobber) away from being lost.
# Alt config dirs → COPY, to stay independent of the primary (copy_file's rationale).
echo ""
echo "Scripts → $CONFIG_DIR/scripts/"
ensure_real_dir "$CONFIG_DIR/scripts"
for script in "$REPO_DIR"/scripts/*.sh; do
  [[ -f "$script" ]] || continue
  if $IS_GLOBAL; then
    link_file "$script" "$CONFIG_DIR/scripts/$(basename "$script")"
  else
    copy_file "$script" "$CONFIG_DIR/scripts/$(basename "$script")"
  fi
done

# scripts/lib/ — same reason as limit-recover below: the loop above globs scripts/*.sh top-level
# only, so a subdirectory needs its own explicit pass. cc-common.sh holds resolve_bin, sourced by
# the boot-resume and autonomy-sweep launchd jobs (consolidation audit 02); if it is not deployed,
# both fail LOUD at startup rather than degrading silently — so this loop is load-bearing, not
# cosmetic.
#
# 🚨 *.py AS WELL AS *.sh, AND THE .py LEG IS WHY THIS COMMENT GREW. A deploy glob keyed on an
# EXTENSION goes stale the moment a later commit puts a different extension in the same directory,
# and NOTHING re-examines the glob — not even the auditor, because deploy-parity-assert.sh mirrors
# this file 1:1 BY DESIGN and therefore scored the newcomer want=0 via its scripts/*/* catch-all.
# Two sibling checks, one blind spot, because they share the extension: an auditor built to mirror
# the deployer can catch the deployer's DRIFT but never its OMISSION.
#
# MEASURED 2026-08-24 (backlog 70cc9f44040f's generalisation clause, made concrete). scripts/lib/
# gained pty-run.py on 2026-08-08 (769ea1fca82f, on trunk). This loop globbed *.sh, so it was never
# linked — 11 of 12 files in the directory live, that one absent for 16 days. Its consumer resolves
# it relative to its OWN source dir, so the LIVE copy of scripts/lib/cloud-create.sh computes
# $HOME/.claude/scripts/lib/pty-run.py and finds nothing:
#
#   $ . ~/.claude/scripts/lib/cloud-create.sh; echo "$CC_CLOUD_PTY_RUN"
#   /Users/chrisren/.claude/scripts/lib/pty-run.py        # absent
#
# cloud-create.sh:190 is fail-CLOSED, so every scheduled cloud create on this box returns
# "refused-harness  no pty allocator at …" and never reaches the binary — and both cloud lanes are
# scheduled (com.chrisren.autonomy-sweep.plist and com.claude.dispatcher.plist each export
# CC_FIRE_CLOUD=on). Fail-closed is the RIGHT polarity and it is still invisible: the refusal is a
# classification a scheduled caller consumes, not a page anyone reads. This is the ADD class from
# CLAUDE.md — an added file is not stale, it is ABSENT — and want=0 disabled the one repair path
# that could have healed it without an advance (link_refresh() repairs exactly the assert's own
# MISSING lines; see deploy-parity-assert.sh's note on the backlog-consolidation instance, which is
# this same defect caught one directory earlier).
if [[ -d "$REPO_DIR/scripts/lib" ]]; then
  echo ""
  echo "Script libs → $CONFIG_DIR/scripts/lib/"
  ensure_real_dir "$CONFIG_DIR/scripts/lib"
  for f in "$REPO_DIR"/scripts/lib/*.sh "$REPO_DIR"/scripts/lib/*.py; do
    [[ -f "$f" ]] || continue
    if $IS_GLOBAL; then
      link_file "$f" "$CONFIG_DIR/scripts/lib/$(basename "$f")"
    else
      copy_file "$f" "$CONFIG_DIR/scripts/lib/$(basename "$f")"
    fi
  done
fi

# scripts/backlog-consolidation/ — the SAME subdirectory gap as scripts/lib above and
# scripts/limit-recover below, hit a third time, and this instance is the one that proves the
# pattern is a defect rather than a quirk: the classes here are ENUMERATED BY HAND, so a wave that
# adds a new directory of executables ships a live NO-OP and nothing says so.
#
# MEASURED 2026-08-12, by executing the deployed artifact rather than trusting the deploy. W2 landed
# scripts/backlog-consolidation/{group,link,prune,citegraph,verify}.py plus its caller
# scripts/backlog-grouping-sweep.sh. The CALLER is top-level `scripts/*.sh`, so it deployed and is
# live. Its engine is in a subdirectory no glob covers, so it did not. Running the live copy:
#
#   $ bash ~/.claude/scripts/backlog-grouping-sweep.sh
#   no grouper at /Users/chrisren/.claude/scripts/backlog-consolidation/group.py (fail-open)
#   rc=0
#
# rc 0. The sweep is wired into autonomy-sweep, runs on schedule, reports success, and folds nothing
# — the whole consolidation mechanism inert behind a green exit code. That is the ADD class stated
# in CLAUDE.md ("a file the landed diff ADDS is not stale, it is ABSENT, and every consumer guard on
# it is a SILENT skip"), and the fail-open is what makes it invisible: a fail-CLOSED engine check
# would have paged on the first tick.
#
# .py, not .sh, deliberately — this directory's executables are Python and the *.sh globs above
# would have skipped them even if the directory had been enumerated.
if [[ -d "$REPO_DIR/scripts/backlog-consolidation" ]]; then
  echo ""
  echo "Backlog consolidation → $CONFIG_DIR/scripts/backlog-consolidation/"
  ensure_real_dir "$CONFIG_DIR/scripts/backlog-consolidation"
  for f in "$REPO_DIR"/scripts/backlog-consolidation/*.py; do
    [[ -f "$f" ]] || continue
    if $IS_GLOBAL; then
      link_file "$f" "$CONFIG_DIR/scripts/backlog-consolidation/$(basename "$f")"
    else
      copy_file "$f" "$CONFIG_DIR/scripts/backlog-consolidation/$(basename "$f")"
    fi
  done
fi

# scripts/limit-recover/ — the loop above globs scripts/*.sh (top level only), so this
# subdirectory was never deployed by the installer. It was reachable ONLY via
# docs/activation/wiring-all.sh, which is explicitly marked run-by-hand — yet
# com.reso.lr-reset-poller.plist is a LOADED launchd job that executes
# ~/.claude/scripts/limit-recover/lr-reset-poller.sh by absolute path. On a fresh machine
# ./install.sh therefore produced a loaded job pointing at a missing script. Deploying the
# files here does NOT touch launchd (nothing is loaded, unloaded or rewritten) — it only
# makes what the job already references reproducible. Every file, not just *.sh: the job
# also reads lr-audit.py and the plist itself.
if [[ -d "$REPO_DIR/scripts/limit-recover" ]]; then
  echo ""
  echo "limit-recover scripts → $CONFIG_DIR/scripts/limit-recover/"
  ensure_real_dir "$CONFIG_DIR/scripts/limit-recover"
  for f in "$REPO_DIR"/scripts/limit-recover/*; do
    [[ -f "$f" ]] || continue
    if $IS_GLOBAL; then
      link_file "$f" "$CONFIG_DIR/scripts/limit-recover/$(basename "$f")"
    else
      copy_file "$f" "$CONFIG_DIR/scripts/limit-recover/$(basename "$f")"
    fi
  done
fi

# Convenience symlink (global only)
if $IS_GLOBAL && [[ ! -L "$HOME/bin/restore-file" ]]; then
  run ln -sf "$HOME/.claude/scripts/restore-file.sh" "$HOME/bin/restore-file"
  echo "  ✓ ~/bin/restore-file → ~/.claude/scripts/restore-file.sh"
  installed=$((installed + 1))
fi

# DEPLOY-NOW compat symlink (global only) — the operator entrypoint is `bash ~/.claude/DEPLOY-NOW.sh`
# and must keep working. It existed for months as an UNVERSIONED real file at that path (no repo
# copy, unrecoverable if lost); scripts/deploy-now.sh is now its SSOT. A pre-existing real file is
# backed up before being replaced, so the one-time migration can never drop unreviewed content.
if $IS_GLOBAL; then
  deploy_now_link="$CONFIG_DIR/DEPLOY-NOW.sh"
  if [[ -f "$deploy_now_link" && ! -L "$deploy_now_link" ]]; then
    run cp -a "$deploy_now_link" "$deploy_now_link.pre-ssot.bak"
    echo "  ✓ backed up the unversioned $deploy_now_link → .pre-ssot.bak"
  fi
  link_file "$CONFIG_DIR/scripts/deploy-now.sh" "$deploy_now_link"
fi

# --- Skills ---
# Same symlink model as hooks/commands: version each repo skill dir and deploy it live.
# Only touches skill NAMES present in the repo — other ~/.claude/skills are left untouched.
#
# RECURSIVE since 2026-08-16 (backlog 3e2358f03e23). This loop was `for f in "$skilldir"*` with a
# `-f` test: TOP LEVEL ONLY, and a nested file was not skipped loudly, it was invisible. The victim
# was already on trunk — all 23 tracked skills/kpmg-deck/{assets,examples,references,scripts}/*
# files existed live as REAL FILES rather than symlinks, so every one of them was outside the
# converger: `deploy-live.sh` merges and re-runs this installer, and this installer never named
# them. They happened to match origin/main the day this was measured, which is exactly why it was
# silent — nothing kept them that way and the next repo-side edit would simply not have shipped.
# It also blocked TRACKING any nested skill at all: converting one would have produced a
# half-linked skill (top level symlinked, nested files still unversioned reals), which is a worse
# state than leaving it untracked.
#
# `find -type f` (not a glob) is the fix, and the mkdir must precede each link because a nested
# path's parent may not exist live yet. Note this is still the PER-FILE model, not the dir-symlink
# one used for vendor/ below: skill dirs legitimately accumulate live-only siblings (.git,
# .ruff_cache, generated output) that a dir symlink would obliterate. The brand-new-file hazard
# vendor/'s comment describes is answered instead by re-globbing on EVERY run — a file added to the
# repo is linked by the next install.sh, which deploy-live.sh always runs.
if [[ -d "$REPO_DIR/skills" ]]; then
  echo ""
  echo "Skills → $CONFIG_DIR/skills/"
  for skilldir in "$REPO_DIR"/skills/*/; do
    [[ -d "$skilldir" ]] || continue
    name="$(basename "$skilldir")"
    ensure_real_dir "$CONFIG_DIR/skills/$name"
    while IFS= read -r f; do
      rel="${f#"$skilldir"}"
      [[ "$rel" == */* ]] && ensure_real_dir "$CONFIG_DIR/skills/$name/${rel%/*}"
      link_file "$f" "$CONFIG_DIR/skills/$name/$rel"
    done < <(find "$skilldir" -type f | sort)
  done
fi

# --- Vendored third-party plugin content ---
# ONE directory symlink per vendored plugin, deliberately NOT the per-file model used
# above. vendor/ is upstream content we never edit and replace wholesale, so a per-file
# loop would silently fail to link every BRAND-NEW file on the next re-vendor — the same
# deploy-lag trap that left hooks/lib/cc-interactive.sh and skills/video-understanding
# live-missing. A dir symlink cannot drift from its source.
# `ln -sfn` (not -sf) is load-bearing: without -n, a re-run whose target CHANGED would
# create the new link INSIDE the existing dir symlink instead of replacing it.
if [[ -d "$REPO_DIR/vendor" ]]; then
  echo ""
  echo "Vendored plugins → $CONFIG_DIR/vendor/"
  ensure_real_dir "$CONFIG_DIR/vendor"
  for vdir in "$REPO_DIR"/vendor/*/; do
    [[ -d "$vdir" ]] || continue
    vsrc="${vdir%/}"; vdest="$CONFIG_DIR/vendor/$(basename "$vsrc")"
    if [[ -L "$vdest" && "$(readlink "$vdest")" == "$vsrc" ]]; then
      skipped=$((skipped + 1))
      continue
    fi
    run ln -sfn "$vsrc" "$vdest"
    echo "  ✓ $vdest → $vsrc"
    installed=$((installed + 1))
  done
fi

# --- Global instructions (CLAUDE.md) — repo is the source of truth ---
# The lean resident knowledge layer. CLAUDE.md is COPIED as a real file (CC reads ~/.claude/CLAUDE.md
# as user memory; a symlink into the repo would break across branch switches). PROJECT-only memory
# stays in the repo at .claude/CLAUDE.md and is NEVER deployed globally — ~/.claude/CLAUDE.md remains
# the pure global core.
#
# The rules/ leg was REMOVED 2026-07-25. rules/ itself was deleted from the repo in 270baf8 (its two
# files were relocated into skills/), so the one-shot stale-rule sweep had nothing left to sweep in
# any of the 5 config dirs and the deploy loop nothing to deploy — all the leg still did was
# ensure_real_dir an empty ~/.claude/rules on every run, recreating the very directory the migration
# had emptied. The migration is complete; the live empty dirs were removed with this commit.
echo ""
echo "Global instructions → $CONFIG_DIR/CLAUDE.md"
if ! diff -q "$REPO_DIR/CLAUDE.md" "$CONFIG_DIR/CLAUDE.md" >/dev/null 2>&1; then
  [[ -L "$CONFIG_DIR/CLAUDE.md" ]] && run rm "$CONFIG_DIR/CLAUDE.md"
  run cp "$REPO_DIR/CLAUDE.md" "$CONFIG_DIR/CLAUDE.md"
  echo "  ✓ CLAUDE.md ($(wc -l < "$REPO_DIR/CLAUDE.md" | tr -d ' ') lines)"
  installed=$((installed + 1))
else
  skipped=$((skipped + 1))
fi

# --- Status line ---
echo ""
echo "Status line → $CONFIG_DIR/"
copy_file "$REPO_DIR/statusline.sh" "$CONFIG_DIR/statusline.sh"

# --- it2 wrapper ---
if [[ -f "$REPO_DIR/bin/it2-wrapper" ]]; then
  echo ""
  echo "iTerm2 wrapper → $CONFIG_DIR/bin/"
  mkdir -p "$CONFIG_DIR/bin"
  copy_file "$REPO_DIR/bin/it2-wrapper" "$CONFIG_DIR/bin/it2"
fi

# --- PATH tools (global only) → ~/.claude/bin/ ---
# cc-* (the two-way session-comms + orchestration CLIs) and desk-* (the desk role tools).
# SYMLINKED (like scripts/) so live edits land in the repo and can't drift out of
# version control. ~/.claude/bin is on PATH and holds it2, beside which these sit —
# the /handoff --notify-back back-channel trailer references $HOME/.claude/bin/cc-notify
# by absolute path, so this location is load-bearing.
#
# desk-* is NOT covered by the cc-* glob, and nothing else linked it: ~/.claude/bin/desk-register
# did not exist on this machine at all, so the live /desk command — whose whole first step is
# `desk-register` (commands/desk.md:25,37) — invoked a nonexistent binary (audit 02 BROKEN-DEPLOY).
# desk-assert was live only because someone linked it BY HAND on 2026-07-18. Glob both families
# rather than naming files, so a new desk-* tool deploys without another install.sh edit.
#
# ms365-* joined them on 2026-08-31 for the SAME defect, one family later. bin/ms365-reply-splice.py
# landed 2026-08-25 (fea855e1f) and was named ZERO times across install.sh, deploy-live.sh and
# deploy-link-parity.sh, so it existed on trunk and in no live location at all — and no advance of
# the live layer could ever place it, because the converger materialises what this pass selects and
# this pass never selected it. Meanwhile the LIVE enforce-email-formatting.py hook tells the model
# to RUN it, at RECIPE step 3c and inside the rule-6 denial, exactly as commands/desk.md told it to
# run desk-register. Globbed, not named, per the paragraph above: a second ms365-* tool deploys
# without another edit here.
if $IS_GLOBAL; then
  echo ""
  echo "PATH tools → $CONFIG_DIR/bin/"
  mkdir -p "$CONFIG_DIR/bin"
  for tool in "$REPO_DIR"/bin/cc-* "$REPO_DIR"/bin/desk-* "$REPO_DIR"/bin/ms365-*; do
    [[ -f "$tool" ]] || continue
    link_file "$tool" "$CONFIG_DIR/bin/$(basename "$tool")"
  done
fi

# --- LaunchAgents (global only) ---
#
# ACTIVATION IS MANIFEST-GATED (DAEMON_FLEET_V2 §4.1, remainder R-1). Until 2026-07-31 this loop ran
# `launchctl bootout` + `launchctl bootstrap` over EVERY launchd/*.plist unconditionally and
# swallowed every error (`2>/dev/null || true`). Three measured defects:
#
#  (a) IT COULD AUTO-ACTIVATE A STAGED JOB. 7 of the 8 labels the manifest declares `staged` sit in
#      this very glob — including com.claude.desk-invariant and com.claude.boot-resume, the two
#      timer-driven session GENERATORS whose runaway spawning forced the operator's fleet shutdown
#      of 2026-07-26 (31 live processes, load 17). The ONLY thing holding them off was the disabled
#      bit in the root-owned /var/db/com.apple.xpc.launchd/disabled.501.plist — outside the repo,
#      outside every repo check, and clearable by anything holding `launchctl enable`. The staging
#      DECISION lived nowhere this installer could see, so it could not honour it.
#  (b) A DISABLED `run` JOB COULD NEVER BE RECOVERED HERE. `bootstrap` on a label disabled in that
#      override db returns EIO, and the `2>/dev/null || true` ate the verdict — R-1's symptom.
#  (c) A LOADED JOB WAS BOUNCED MID-WORK on every routine install, and deploy-live.sh runs this
#      script on every 600s autonomous advance while postland-verify's measured runs are
#      3399-10112s. It could never finish. (Its run-lock was held while this fix was written.)
#
# THE TRAP IN THE OBVIOUS FIX, recorded because the prescribed remedy was the dangerous one: R-1's
# own prescription for (b) — "add `launchctl enable` before bootstrap" — applied to this glob would
# have enabled all 7 staged labels including BOTH generators, i.e. re-created the 2026-07-26
# incident. `enable` is right only for a label the manifest declares `expect = run`. The manifest is
# what makes that difference expressible, so activation now reads it and fails CLOSED without it.
#
# Seam: CC_INSTALL_LAUNCHCTL_BIN — tests stub it, so no suite ever touches real launchd.
FLEET_MANIFEST="${CC_FLEET_MANIFEST:-$REPO_DIR/launchd/fleet.manifest}"
LAUNCHCTL_BIN="${CC_INSTALL_LAUNCHCTL_BIN:-launchctl}"

# The `expect` field for a label. Prints run|staged|retired, or NOTHING when the label is undeclared
# or the manifest is absent — and the caller treats "nothing" as "never activate", so a missing or
# unreadable manifest fails CLOSED rather than back to the old blanket bootstrap.
fleet_expect() {
  local want="$1" mlabel mexpect
  if [[ ! -f "$FLEET_MANIFEST" ]]; then return 0; fi
  while IFS='|' read -r mlabel mexpect _ || [[ -n "$mlabel" ]]; do
    mlabel="$(printf '%s' "$mlabel" | tr -d '[:space:]')"
    if [[ -z "$mlabel" || "$mlabel" == \#* ]]; then continue; fi
    if [[ "$mlabel" != "$want" ]]; then continue; fi
    printf '%s' "$mexpect" | tr -d '[:space:]'
    return 0
  done < "$FLEET_MANIFEST"
}

# ── RESIDENT DAEMONS: the reload a per-file symlink converger can never perform ───────────────────
# master ce775801633b. The `$loaded && ! $plist_changed` skip below is right for a PERIODIC job — it
# re-execs its program at its next scheduled load. It is permanently wrong for a KeepAlive daemon,
# which never exits, so its next natural load never arrives; and because its plist names a SCRIPT
# PATH, the plist never changes when the script does. The skip therefore fires on EVERY install and
# the daemon is never reloaded at all.
#
# THE ROW NAMED THE WRONG STATEMENT. It cites the PID skip ("executing right now, not reloaded").
# That branch is UNREACHABLE for an unchanged plist: this skip returns first, and copy_file only
# increments `installed` when the bytes actually differ.
#
# THE PROBES THEMSELVES LIVE IN scripts/lib/cc-common.sh, not here, because a SECOND consumer must
# agree with this one about the same population: scripts/deploy-live.sh reports whether the live
# layer actually reached the running processes (master 475222a572de half 1). Two copies of a probe
# that must agree is precisely the drift cc-common.sh was created to end.
#
# FAIL-CLOSED WHEN THE LIB IS ABSENT, the same way the real-home lib is handled above: a missing lib
# means a broken or partial tree, and the safe reading of "I cannot tell whether this daemon is
# stale" is "do not touch it".
# shellcheck source=scripts/lib/cc-common.sh
# The `source=` hint resolves the path but does not make shellcheck FOLLOW it without -x, and the
# statics gate runs a bare `shellcheck` (scripts/ship-land.sh:2326).
# shellcheck disable=SC1091
if [[ -r "$REPO_DIR/scripts/lib/cc-common.sh" ]]; then
  . "$REPO_DIR/scripts/lib/cc-common.sh"
else
  plist_is_resident() { return 1; }
fi

# The one bounce that can LOSE something. Prints the reason and returns 0 when a reload must NOT
# happen. The compressor sentinel SIGSTOPs burst processes and owes every one of them a SIGCONT;
# that debt lives ONLY in its frozen ledger (5305ee34c). Bouncing it while the ledger is non-empty
# strands those processes stopped forever — the remedy strictly worse than the stale image it cures.
resident_bounce_vetoed() {
  local label="$1" db n
  case "$label" in
    com.claude.compressor-sentinel)
      db="${CC_SENTINEL_FROZEN_DB:-$HOME/.claude/logs/compressor-sentinel-frozen.tsv}"
      if [[ -s "$db" ]]; then
        n="$(wc -l < "$db" 2>/dev/null | tr -d ' ' || true)"
        printf 'it owes SIGCONT to %s frozen pid(s)' "${n:-?}"
        return 0
      fi
      ;;
  esac
  return 1
}

if $IS_GLOBAL; then
  echo ""
  echo "LaunchAgents → ~/Library/LaunchAgents/"
  mkdir -p "$HOME/Library/LaunchAgents"
  uid="$(id -u)"
  # Read the override db ONCE. Absence of a label means ENABLED — it records overrides, not
  # memberships (the rule bin/cc-fleet and cc-blockers already state; reused, not re-derived).
  DISABLED_DB="$("$LAUNCHCTL_BIN" print-disabled "gui/$uid" 2>/dev/null || true)"
  for plist in "$REPO_DIR"/launchd/*.plist; do
    [[ -f "$plist" ]] || continue
    name=$(basename "$plist")
    label="${name%.plist}"
    installed_before=$installed
    copy_file "$plist" "$HOME/Library/LaunchAgents/$name"
    if $DRY_RUN; then continue; fi

    expect="$(fleet_expect "$label")"
    if [[ "$expect" != run ]]; then
      if [[ "$expect" == staged || "$expect" == retired ]]; then
        echo "  · $label — declared '$expect': SSOT deployed, NOT activated (the operator's C10 call)"
      else
        echo "  ⚠ $label — UNDECLARED in launchd/fleet.manifest: NOT activated (declare it first)"
        warnings=$((warnings + 1))
      fi
      continue
    fi

    # expect = run. Touch launchd ONLY when there is something to do — a changed plist, or a job
    # that is not loaded. An unchanged, already-loaded job is left strictly alone; that is what
    # makes this safe to call on every 600s deploy advance.
    plist_changed=false
    if [[ $installed -ne $installed_before ]]; then plist_changed=true; fi
    loaded=false
    if "$LAUNCHCTL_BIN" list "$label" >/dev/null 2>&1; then loaded=true; fi
    if $loaded && ! $plist_changed; then
      # Correct for a periodic job. For a KeepAlive daemon this is the statement that strands it
      # forever — see the resident-daemon block above. Detection is unconditional so the staleness
      # becomes a counted EVENT rather than a standing state nobody is told about; the launchd
      # MUTATION stays behind CC_INSTALL_RESIDENT_RELOAD because this runs on an autonomous path.
      if plist_is_resident "$plist"; then
        rpid="$(resident_pid "$label" "$LAUNCHCTL_BIN")"
        rprog=""
        [[ -n "$rpid" ]] && rprog="$(resident_program "$rpid")"
        if [[ -n "$rprog" ]] && resident_image_stale "$rpid" "$rprog"; then
          if veto="$(resident_bounce_vetoed "$label")"; then
            echo "  · $label — RESIDENT, running a stale image, NOT reloaded: $veto"
          elif [[ "${CC_INSTALL_RESIDENT_RELOAD:-0}" != 1 ]]; then
            echo "  ⚠ $label — RESIDENT daemon is running a STALE image ($rprog changed after it started); CC_INSTALL_RESIDENT_RELOAD=1 reloads it"
            warnings=$((warnings + 1))
          else
            echo "  → $label — RESIDENT daemon running a stale image: reloading"
            "$LAUNCHCTL_BIN" bootout "gui/$uid/$label" 2>/dev/null || true
            if ! "$LAUNCHCTL_BIN" bootstrap "gui/$uid" "$HOME/Library/LaunchAgents/$name" 2>/dev/null; then
              echo "  ⚠ $label — resident reload FAILED; the daemon is NOT running"
              warnings=$((warnings + 1))
            fi
          fi
        fi
      fi
      continue
    fi

    # Never bounce a job that is EXECUTING RIGHT NOW (defect (c)). Its new plist applies at the
    # next natural load; a reload here would restart a run that is already hours deep.
    if $loaded && "$LAUNCHCTL_BIN" list "$label" 2>/dev/null | grep -q '"PID"'; then
      echo "  · $label — executing right now, not reloaded (new plist applies at its next load)"
      continue
    fi

    # `enable` FIRST, and ONLY when the override db actually carries a disabled bit for this label.
    # Bootstrap alone returns EIO on a disabled label — precisely how a declared-`run` job stayed
    # dark and unrecoverable from here (R-1's symptom).
    #
    # CONDITIONAL, not unconditional, because this puts a launchd MUTATION verb on an autonomous
    # path: deploy-live.sh runs this script after every advance. No bit to clear ⇒ no verb issued at
    # all; a clear that does happen prints a line, so an unattended activation can never be silent.
    # It converges only to what the LANDED manifest already declares `run` — the reviewed intent —
    # and the C10 platter remains the operator's route for everything else. Measured 2026-07-31:
    # the run-declared ∩ currently-disabled set is EMPTY, so this is a no-op on today's box.
    #
    # Matched WHOLE and QUOTED with grep -F: `com.claude.dispatcher-foo` would otherwise satisfy
    # `com.claude.dispatcher`, and an unanchored `.` in a label is a wildcard.
    if printf '%s\n' "$DISABLED_DB" | grep -qF "\"$label\" => disabled"; then
      echo "  → $label — declared 'run' but DISABLED at the domain level: clearing the bit"
      if ! "$LAUNCHCTL_BIN" enable "gui/$uid/$label" 2>/dev/null; then
        echo "  ⚠ $label — launchctl enable failed"
        warnings=$((warnings + 1))
      fi
    fi
    if $loaded; then
      "$LAUNCHCTL_BIN" bootout "gui/$uid/$label" 2>/dev/null || true
    fi
    if ! "$LAUNCHCTL_BIN" bootstrap "gui/$uid" "$HOME/Library/LaunchAgents/$name" 2>/dev/null; then
      if ! "$LAUNCHCTL_BIN" load "$HOME/Library/LaunchAgents/$name" 2>/dev/null; then
        echo "  ⚠ $label — launchctl bootstrap FAILED; the job is NOT running"
        warnings=$((warnings + 1))
      fi
    fi
  done

  # --- Version directory ---
  echo ""
  echo "Version management → ~/.claude-versions/"
  mkdir -p "$HOME/.claude-versions"
fi

# --- Settings hooks (merge-wire + post-install assert) ---
# The FULL live hook roster lives in settings-templates/settings.example.json (G-P6-7): the
# anti-premature-done Stop hooks (session-continue, anti-deference, teammate-checkpoint, boundary-handoff)
# MUST survive a settings reset. This ADDITIVELY merges the template's .hooks (adds missing EVENTS only —
# never clobbers a populated event) + unions .permissions.deny/.ask into $CONFIG_DIR/settings.json.
# .permissions.allow is EXCLUDED FROM THE UNION BY DESIGN, and this asymmetry is the whole point:
# deny/ask are RESTRICTIVE, so unioning them is monotonically fail-CLOSED and safe to do behind the
# operator's back; allow is PERMISSIVE, so unioning it would silently WIDEN every config dir's
# auto-allow surface on each install — the exact fail-open move the operator's own ask/deny gates
# exist to prevent. The template's allow IS still seeded wholesale into a dir that has no
# settings.json yet (base = clean template, below), so a fresh dir starts complete; thereafter allow
# is that dir's own to grow. Measured 2026-08-22 (backlog 204e0d795e98, closed on this evidence):
# across the five live config dirs the allow arrays hold 338-339 of a 339-entry union — all 17
# template entries present in all five (missing=0, positive-controlled) and the entire divergence is
# ONE locally-accreted entry, Bash(kitten @ send-text:*), which is not in the template. So unioning
# allow here would be a provable NO-OP on that divergence while widening permissions fleet-wide.
# --wire-hooks opts in; a config with NO .hooks is auto-wired (fresh install). A read-only ASSERT always
# reports template hooks not present in the target. (Merging settings.json is the OPERATOR's hand via
# this installer — never an agent Write; the C10 ceiling holds.)
echo ""
echo "Settings hooks → $CONFIG_DIR/settings.json"
TEMPLATE="$REPO_DIR/settings-templates/settings.example.json"
target_settings="$CONFIG_DIR/settings.json"
if ! command -v jq >/dev/null 2>&1; then
  echo "  ⚠ jq not found — skipping settings merge/assert"
  warnings=$((warnings + 1))
elif [[ ! -f "$TEMPLATE" ]]; then
  echo "  ⚠ template missing: $TEMPLATE"
  warnings=$((warnings + 1))
else
  # clean template = strip every _-prefixed annotation key (recursively) so no _comment/_stagedHooks leak in
  clean_tmpl="$(jq 'walk(if type=="object" then with_entries(select(.key|startswith("_")|not)) else . end)' "$TEMPLATE")"
  do_merge=false
  if [[ ! -f "$target_settings" ]]; then do_merge=true
  elif $WIRE_HOOKS; then do_merge=true
  elif ! jq -e '.hooks' "$target_settings" >/dev/null 2>&1; then do_merge=true   # fresh/reset config → auto-wire
  fi

  if $do_merge; then
    if $DRY_RUN; then
      echo "  [dry-run] would merge-wire hooks + deny/ask union into $target_settings"
    else
      base="$clean_tmpl"; [[ -f "$target_settings" ]] && base="$(cat "$target_settings")"
      [[ -f "$target_settings" ]] && cp "$target_settings" "$target_settings.pre-wire.bak"
      if printf '%s' "$base" | jq --argjson t "$clean_tmpl" '
            .hooks = ($t.hooks + (.hooks // {}))                                    # add missing events; keep present
            | .permissions = (.permissions // {})
            | .permissions.deny = (((.permissions.deny // []) + ($t.permissions.deny // [])) | unique)
            | .permissions.ask  = (((.permissions.ask  // []) + ($t.permissions.ask  // [])) | unique)
            # .permissions.allow is DELIBERATELY NOT unioned — see the header note above. Do not "fix".
          ' > "$target_settings.tmp" && mv "$target_settings.tmp" "$target_settings"; then
        # Merge is ADDITIVE + order-preserving: it wires missing EVENTS in full and unions deny/ask,
        # but never reorders a populated event (the Stop FM1 chain order is load-bearing).
        echo "  ✓ merged: missing hook events + deny/ask union (backup .pre-wire.bak)"
        # WITHIN-EVENT UNION (append-only, never reorders): for every template (event, matcher, command)
        # missing from the target event, append the hook to the FIRST object with the SAME matcher
        # (matcher-null → first matcher-less object, i.e. the obj-1 chain tail); no matching object →
        # append the template's object shape. This is the mechanical form of the activation snippets'
        # per-dir jq — placement semantics per fm1b-activate-snippet §3-5.
        if printf '%s' "$(cat "$target_settings")" | jq --argjson t "$clean_tmpl" '
              def add1($m; $h):
                (map((.matcher // null) == $m) | index(true)) as $i
                | if $i == null
                  then . + [ (if $m == null then {hooks:[$h]} else {matcher:$m, hooks:[$h]} end) ]
                  else .[$i].hooks += [$h] end;
              .hooks |= (reduce ($t.hooks | to_entries[]) as $ev (. // {};
                .[$ev.key] = ((.[$ev.key] // []) as $cur
                  | reduce [ $ev.value[]? as $o | ($o.hooks[]?) as $h
                             | {m: ($o.matcher // null), h: $h} ][] as $x ($cur;
                      if any(.[]?; (.hooks // []) | any(.command == $x.h.command)) then .
                      else add1($x.m; $x.h) end))))
            ' > "$target_settings.tmp2" && jq -e '.hooks' "$target_settings.tmp2" >/dev/null 2>&1; then
          mv "$target_settings.tmp2" "$target_settings"
          echo "  ✓ within-event union: every template hook command present in its event (append-at-tail)"
        else
          rm -f "$target_settings.tmp2"
          echo "  ⚠ within-event union failed — event-level merge kept; gaps listed by the assert below"
          warnings=$((warnings + 1))
        fi
        installed=$((installed + 1))
      else
        rm -f "$target_settings.tmp"
        echo "  ⚠ jq merge failed — settings.json left unchanged"
        warnings=$((warnings + 1))
      fi
    fi
  else
    echo "  · assert-only ($(basename "$target_settings") already has hooks; pass --wire-hooks to merge)"
  fi

  # post-install ASSERT (read-only): which template hooks are NOT wired in the target (by basename+args)
  if [[ -f "$target_settings" ]]; then
    norm='s#\|[^ ]*/#|#'
    tmpl_h="$(printf '%s' "$clean_tmpl" | jq -r '.hooks|to_entries[]|.key as $e|(.value//[])[]?|(.hooks//[])[]?|"\($e)|\(.command)"' 2>/dev/null | sed -E "$norm" | sort -u)"
    live_h="$(jq -r '.hooks|to_entries[]|.key as $e|(.value//[])[]?|(.hooks//[])[]?|"\($e)|\(.command)"' "$target_settings" 2>/dev/null | sed -E "$norm" | sort -u)"
    missing_h="$(comm -23 <(printf '%s\n' "$tmpl_h") <(printf '%s\n' "$live_h"))"
    if [[ -n "$missing_h" ]]; then
      echo "  ⚠ template hooks NOT wired in $(basename "$target_settings") (run with --wire-hooks to add):"
      printf '%s\n' "$missing_h" | sed 's/^/      /'
      warnings=$((warnings + 1))
    else
      echo "  ✓ all template hooks present in $(basename "$target_settings")"
    fi
  fi
fi

# --- Python deps (global only: they back bin/, which --config-dir does not deploy) ---
# Delegated to scripts/python-deps.sh so the step is testable without a global install
# (see the header there). Read the VERDICT TOKEN, not the exit code — "already fine" and
# "installed it just now" are different facts and the summary should not conflate them.
# A dep failure WARNS and never aborts: a missing optional module must not cost the
# operator their hooks and launchers. `|| true` guards the installer's own set -e.
if $IS_GLOBAL && [[ -x "$REPO_DIR/scripts/python-deps.sh" ]]; then
  dep_args=(); $DRY_RUN && dep_args=(--dry-run)
  dep_out="$("$REPO_DIR/scripts/python-deps.sh" "${dep_args[@]+"${dep_args[@]}"}" 2>&1)" || true
  dep_verdict="$(printf '%s\n' "$dep_out" | sed -n 's/.*verdict=\([a-z-]*\).*/\1/p' | head -1)"
  case "$dep_verdict" in
    satisfied) : ;;                                  # silent: nothing changed, nothing to report
    installed)
      echo ""; echo "Python deps → $REPO_DIR/requirements.txt"
      echo "  ✓ $(printf '%s\n' "$dep_out" | sed -n 's/.*modules=//p' | head -1)"
      installed=$((installed + 1)) ;;
    dry-run)
      echo ""; echo "Python deps → $REPO_DIR/requirements.txt"
      echo "  [dry-run] would install: $(printf '%s\n' "$dep_out" | sed -n 's/.*modules=//p' | head -1)" ;;
    *)
      echo ""; echo "Python deps → $REPO_DIR/requirements.txt"
      echo "  ⚠ ${dep_out//$'\n'/$'\n'  }"
      echo "    cc-relogin will report BROWSER-FAILED(4) where the true verdict is CONSENT-GATE(7)."
      warnings=$((warnings + 1)) ;;
  esac
fi

# --- Validation ---
echo ""
echo "Validating..."

if ! grep -q "statusline" "$CONFIG_DIR/settings.json" 2>/dev/null; then
  echo "  ⚠ settings.json missing statusLine config"
  warnings=$((warnings + 1))
fi

if ! grep -q "hooks" "$CONFIG_DIR/settings.json" 2>/dev/null; then
  echo "  ⚠ settings.json missing hooks config — hooks won't fire without registration"
  warnings=$((warnings + 1))
fi

if $IS_GLOBAL; then
  if ! command -v claude-latest &>/dev/null; then
    echo "  ⚠ ~/bin not in PATH — add 'export PATH=\"\$HOME/bin:\$PATH\"' to ~/.zshrc"
    warnings=$((warnings + 1))
  fi
fi

if [[ $warnings -eq 0 ]]; then
  echo "  ✓ All checks passed"
fi

# --- macOS: pre-establish the iTerm2 clear-scrollback pref -------------------
# So an autonomous /limit-recover resume never blocks on the "control sequence attempted
# to clear scrollback history" GUI modal (a sheet above the PTY that expect cannot answer).
# Setting it at SETUP (not just per-resume) closes the cold-machine first-resume race where
# iTerm2, launched before the pref was ever written, hasn't yet processed the change.
# See scripts/limit-recover/lr-preseed-env.sh.
if [[ "$(uname)" == "Darwin" ]] && command -v defaults >/dev/null 2>&1; then
  if [[ "$(defaults read com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory 2>/dev/null)" != "1" ]]; then
    defaults write com.googlecode.iterm2 PreventEscapeSequenceFromClearingHistory -bool true 2>/dev/null \
      && echo "  ✓ iTerm2 clear-scrollback modal suppressed (autonomous-resume prereq)"
  fi
fi

# --- kitty: split panes + native Agent Teams panes ---
# Zero-click by default: if kitty is installed, wire it. The whole point is that a new user never has
# to discover that cmd+D is dead, that the pane backend needs an env var, or that teammateMode
# decides whether assignee sessions are visible at all — every one of which is a silent failure.
#
# Runs only when kitty is present (never installs a terminal for you), is idempotent, and CANNOT
# leave the tree in a half-state: kitty-setup.sh exits non-zero purely to report "restart kitty",
# which is not an install failure, so its status is reported and deliberately not propagated.
if command -v kitty >/dev/null 2>&1 || [[ -x /Applications/kitty.app/Contents/MacOS/kitty ]]; then
  echo ""
  echo "kitty → split panes + native Agent Teams panes"
  if ! [[ -x "$REPO_DIR/scripts/kitty-setup.sh" ]]; then
    echo "  ⚠ scripts/kitty-setup.sh missing or not executable"
    warnings=$((warnings + 1))
  elif $DRY_RUN; then
    # A preview MUST NOT wire anything. kitty-setup.sh writes symlinks, appends a dotfile block and
    # rewrites teammateMode — all real side effects — so --dry-run runs its READ-ONLY --check
    # instead. (`run` is not usable here: it echoes the command but would still execute nothing,
    # losing the preview's actual value, which is reporting what is currently unwired.)
    echo "  [dry-run] would run scripts/kitty-setup.sh — current state:"
    "$REPO_DIR/scripts/kitty-setup.sh" --check 2>&1 | sed 's/^/    /' || true
  else
    if "$REPO_DIR/scripts/kitty-setup.sh" >/dev/null 2>&1; then
      echo "  ✓ kitty wired and live (cmd+D splits right, cmd+shift+D splits down)"
    else
      # The overwhelmingly common cause is the one nothing can automate away.
      echo "  ⚠ kitty wired, but NOT yet live — quit kitty (Cmd+Q) and reopen it."
      echo "    allow_remote_control/listen_on are the only options kitty cannot reload."
      echo "    Verify with: scripts/kitty-setup.sh --check"
    fi
  fi
fi

# --- Summary ---
echo ""
echo "Done: $installed installed, $skipped already up-to-date"
if [[ $warnings -gt 0 ]]; then
  echo "     $warnings warning(s)"
fi
