#!/bin/bash
# deploy-now.sh — the operator's `bash ~/.claude/DEPLOY-NOW.sh` entrypoint. A THIN FRONT-END onto
# scripts/deploy-live.sh, which is the only sanctioned advance of the live layer.
#
#   Run:  bash ~/.claude/DEPLOY-NOW.sh              (the operator entrypoint — a symlink to this file)
#   Hammer: bash ~/.claude/DEPLOY-NOW.sh --force    (every flag is passed straight through)
#
# This script used to advance the shared checkout ITSELF, with `git merge --ff-only origin/main`.
# That is the exact operation `.claude/commands/ship.md:112` forbids by name — "Never raw-ff the
# shared checkout" — and it made this file the one TRACKED, DOCUMENTED, operator-blessed spelling
# of the forbidden path. Three properties of that body are why it is gone rather than patched:
#
#   1. IT COULD NOT DEPLOY. ~/.claude/{hooks,commands,scripts,bin,skills} are real directories of
#      PER-FILE symlinks, so a ff updates every already-linked file and deploys NOTHING for a file
#      the checkout gained. Its step 5 REPORTED those files and deliberately never linked them, so
#      a "successful" deploy-now reliably ended with brand-new landed code inert on disk.
#   2. IT SKIPPED THE GREEN GATE. No stamp check, no target selection — it ff'd to whatever tip
#      origin/main happened to carry, verified or not. That is the named incident deploy-live.sh
#      exists to answer (see its header: "the old nag emitted a raw `git pull --ff-only`").
#   3. IT SCORED ITSELF UNGATED. `merge --ff-only origin/main` reflogs the REF, and
#      scripts/deploy-parity-assert.sh's provenance leg discriminates precisely on ref-vs-SHA — so
#      every run left a permanent UNGATED finding against the live layer it had just advanced.
#
# WHY DELEGATION COSTS THE OPERATOR NOTHING. The historical objection was that routing this into
# deploy-live.sh removes the un-gated hammer for the case where the gate is stuck. That was true of
# the SINGLE-TIER deploy-live (measured 2026-08-07: 534 identical refusals, 276 launchd runs, every
# one exit 1) and is not true of the current one. `deploy-live.sh --force` is a strict SUPERSET of
# everything the old body did — the same fast-forward, plus link_refresh + install.sh (which is what
# actually creates the links), migrations, post-deploy host checks, a page on refusal, and a GATED
# provenance verdict — and T1H/T2 give the gate a degradation path, so `--force` is rarely the
# reach. Nothing the operator could do before is unreachable now; only the spelling moved.
#
# THERE IS NO RAW-FF FALLBACK, deliberately. If deploy-live.sh is missing this script fails loud.
# Falling back to a bare ff would re-create the exact hole at the exact moment nobody is watching,
# and a fallback is indistinguishable from the sanctioned path in every after-the-fact audit.
#
# SSOT NOTE: this lived ONLY as a real file at ~/.claude/DEPLOY-NOW.sh, unversioned and
# unrecoverable. It is now a tracked script deployed like every other (install.sh symlinks
# scripts/*.sh into ~/.claude/scripts/, plus a ~/.claude/DEPLOY-NOW.sh compat link so the
# operator's existing command is unchanged).
#
# HISTORICAL RECORD — what the deleted body's step 5 replaced, kept because neither script was ever
# tracked in git and this comment is the only surviving record of either. The pre-SSOT script's
# verify leg was `grep -c 'REOPEN GUARDS' ~/.claude/bin/cc-backlog` — a hardcoded content probe for
# one file from one 2026-07-20 deploy, already stale for every deploy after it. Its intent ("did the
# live layer actually pick this up?") is subsumed and generalised, now by deploy-live.sh's own
# link_refresh, which consumes scripts/deploy-parity-assert.sh's MISSING verdict over all ~212
# deployed files and — unlike step 5 — REPAIRS it. The by-design-PENDING signal step 5 protected
# survives intact: deploy-parity-assert `continue`s those files before emitting MISSING, so
# link_refresh cannot touch a hook deliberately left unlinked until its staged activation runs.
set -uo pipefail

REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"
# Same seam shape as deploy-live.sh's own CC_DEPLOY_PARITY_ASSERT: `-` not `:-`, so SET-EMPTY is
# honored verbatim and the default cannot race back in behind a caller that deliberately blanked it.
DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"

# deploy-live.sh reads DEPLOY_REPO; this entrypoint has always read CC_DEPLOY_REPO. Bridge them so
# a caller that set either one gets the checkout it actually asked for.
export DEPLOY_REPO="$REPO"

[ -d "$REPO" ] || { echo "✗ repo not found: $REPO" >&2; exit 1; }

# gate_bounded: MISSING-BINARY, delivered to the human who typed the command — the refusal IS the
# event and nothing queues behind it. This is the case permission-gate-lint scopes out by doctrine
# ("an operator typo and a missing binary are EVENTS by construction, not standing states"); its
# scoped_out() spells that as `command -v`, and this is the same class reached through `[ ! -x ]`
# because the target is a path, not a PATH lookup. The bound is checkable, not asserted: this file
# has NO unattended caller — launchd/com.claude.deploy-live.plist execs scripts/deploy-live.sh
# --auto directly, and install.sh's only use of deploy-now.sh is to create the operator's compat
# symlink. Add an unattended caller and this declaration stops being true; re-derive it then.
if [ ! -x "$DEPLOY_LIVE" ]; then
  echo "✗ ABORT — deploy-live.sh missing or not executable: $DEPLOY_LIVE" >&2
  echo "  This entrypoint delegates to it and will NOT fall back to a raw fast-forward:" >&2
  echo "  a bare ff creates no symlinks, so it deploys nothing for any newly landed file." >&2
  echo "  Restore the checkout, then re-run." >&2
  exit 1
fi

# --auto's contract is silence in the steady state (144 ticks/day) and --offline is parsed by the
# operator platter, so neither may be given a banner. Everything else gets one line, on stderr, so
# it can never contaminate a caller reading stdout.
quiet=0
for a in "$@"; do
  case "$a" in --auto|--offline) quiet=1 ;; esac
done
[ "$quiet" -eq 1 ] || printf '→ deploy-now delegates to the sanctioned advance: %s %s\n' "$DEPLOY_LIVE" "$*" >&2

exec "$DEPLOY_LIVE" "$@"
