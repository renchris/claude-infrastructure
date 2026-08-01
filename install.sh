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

# --- Shared shell libs (lib/) ---
# config-mirror.zsh in particular: it decides which state each account config dir SHARES vs
# isolates, and it lived for months as an unversioned real file at ~/.claude/lib/ — a config with
# real blast radius, no history, no review, and no way to tell drift from intent. Linking it from
# the repo puts the isolate-set under the same review as everything else. desk.zsh was already
# linked here by hand; this generalises that.
echo ""
echo "Shell libs → $CONFIG_DIR/lib/"
ensure_real_dir "$CONFIG_DIR/lib"
for zlib in "$REPO_DIR"/lib/*.zsh; do
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
  for tool in claude-latest claude-update claude-versions browsermcp-wrapper.sh claude-kimi \
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
if [[ -d "$REPO_DIR/scripts/lib" ]]; then
  echo ""
  echo "Script libs → $CONFIG_DIR/scripts/lib/"
  ensure_real_dir "$CONFIG_DIR/scripts/lib"
  for f in "$REPO_DIR"/scripts/lib/*.sh; do
    [[ -f "$f" ]] || continue
    if $IS_GLOBAL; then
      link_file "$f" "$CONFIG_DIR/scripts/lib/$(basename "$f")"
    else
      copy_file "$f" "$CONFIG_DIR/scripts/lib/$(basename "$f")"
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
if [[ -d "$REPO_DIR/skills" ]]; then
  echo ""
  echo "Skills → $CONFIG_DIR/skills/"
  for skilldir in "$REPO_DIR"/skills/*/; do
    [[ -d "$skilldir" ]] || continue
    name="$(basename "$skilldir")"
    ensure_real_dir "$CONFIG_DIR/skills/$name"
    for f in "$skilldir"*; do
      [[ -f "$f" ]] || continue
      link_file "$f" "$CONFIG_DIR/skills/$name/$(basename "$f")"
    done
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
if $IS_GLOBAL; then
  echo ""
  echo "PATH tools → $CONFIG_DIR/bin/"
  mkdir -p "$CONFIG_DIR/bin"
  for tool in "$REPO_DIR"/bin/cc-* "$REPO_DIR"/bin/desk-*; do
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
    if $loaded && ! $plist_changed; then continue; fi

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
