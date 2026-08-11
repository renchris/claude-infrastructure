#!/bin/bash
# migration-class: c10
# migration-step: the SessionStart accounts board is landed but reaches no session — settings.json is FIVE separate real files and the mirror refuses to touch a forked one, so each config dir needs its own hook-roster merge (and .claude-next, the DEFAULT account, is the divergent one)
# migration-run: CONFIRM=1 bash ~/Development/claude-infrastructure/docs/activation/pending-activation/38-accounts-board-activate.sh
# migration-subject: ~/.claude/settings.json + the four sibling config dirs
# migration-verify: for d in "$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do grep -q 'accounts-board.sh' "$d/settings.json" || exit 1; done; [ -e "$HOME/.claude/hooks/accounts-board.sh" ]
#
# WHAT LANDED IN THIS DIFF (DESK_ROUTER_AND_STARTUP_V1 §3 W3 items 6-7)
# ─────────────────────────────────────────────────────────────────────────────────────────────
# hooks/accounts-board.sh — a SessionStart hook printing the /accounts board through the ONE
# channel that reaches the operator's terminal without entering model context: a TOP-LEVEL
# `systemMessage`. (The nested `hookSpecificOutput.systemMessage` is silently ignored;
# `additionalContext` is billed as input tokens. Measured under a real pty, transcript-inspected:
# docs/research/R5b-sessionstart-render-probe.py.)
#
# bin/claude-accounts gained `--readout --narrow` — the same renderer at <=76 cols — and
# `--keepwarm` now writes that rendering to disk. The hook is a file read (~65ms). It may not
# call claude-accounts: `--readout` measured 5.33s against a 5s hook timeout and was killed in
# the probe, which is precisely the class of defect W0 had just finished removing.
#
# WHY C10, AND NOT MECHANICAL
# ─────────────────────────────────────────────────────────────────────────────────────────────
# The hook FILE converges by itself — it is a new file in hooks/, so deploy-live.sh links it like
# any other. The WIRING does not, and cannot:
#
#   settings.json is not one file with four symlinks. It is FIVE SEPARATE REAL FILES — five
#   distinct inodes, measured 2026-08-11: 452849547 (.claude), 452849554 (.claude-next),
#   464207462 (.claude-secondary), 452849551 (.claude-tertiary), 453104257 (.claude-quaternary).
#   The knowledge-layer mirror's safe mode REFUSES to write a forked real file, which is the
#   correct behaviour and is also exactly why a hook added to the repo template propagates to
#   nothing. Each dir needs its own `install.sh --config-dir <dir> --wire-hooks` merge.
#
# Merging a hook roster into five live operator configs is a write into the operator's own
# environment, five times, each with a backup — migrations/README.md puts that on the human side,
# and an unattended 600s converger doing it is how five configs get a half-applied roster.
#
# .claude-next IS THE ONE THAT MATTERS, AND THE ONE THAT WILL BE MISSED
# ─────────────────────────────────────────────────────────────────────────────────────────────
# It is ACCOUNT 1 — where a bare `claude` lands — and it is already the divergent config: 74 hook
# commands against 79 in the other four (the five divergences migration 0009-claude-next-guardrail-
# parity records, still staged), plus a FORKED REAL hooks/ dir (53 files vs 75) where the other
# three carry a symlink to ~/.claude/hooks.
#
# ⚠️ THE FORKED hooks/ DIR IS A RED HERRING FOR *THIS* HOOK, and saying so is the point — the
# plan's W3.7 warns the hook file "will not appear there via the mirror … needs its own link
# pass". Re-measured at implementation: all 79 hook commands across all five settings.json files
# invoke the LITERAL path `~/.claude/hooks/<name>`; ZERO reference a per-account hooks dir. So the
# file has to exist at ~/.claude/hooks/accounts-board.sh and nowhere else, and a .claude-next
# session runs that same file. What .claude-next genuinely needs its own pass for is its
# settings.json — which this migration is about. Verified, not assumed, because the difference
# decides whether "wired" means one link or two.
#
# THE EXPECTED STATE BETWEEN LANDING AND THE STEP, so it is not read as a defect: the hook exists
# and is inert. No session prints a board, nothing errors, and no gate goes red — an unwired hook
# is invisible by construction, which is the whole reason this migration exists to name it.
set -uo pipefail

REPO="${CC_MIGRATION_REPO:-$HOME/Development/claude-infrastructure}"
ROOT="${CC_MIGRATION_CONFIG_ROOT:-$HOME}"
HOOK_SRC="$REPO/hooks/accounts-board.sh"
ACTIVATE="$REPO/docs/activation/pending-activation/38-accounts-board-activate.sh"
DIRS=("$ROOT/.claude" "$ROOT/.claude-next" "$ROOT/.claude-secondary" \
      "$ROOT/.claude-tertiary" "$ROOT/.claude-quaternary")

# ---- step 1: the artifacts this migration presupposes must actually exist ------------------------
for f in "$HOOK_SRC" "$ACTIVATE"; do
  if [ ! -f "$f" ]; then
    echo "0011: MISSING $f — the wiring commit did not land intact; refusing to file a step for it" >&2
    exit 1
  fi
done

# The step is only worth filing if the repo template actually carries the hook. If somebody
# reverted the settings template, filing "go merge the template into five configs" would send the
# operator to merge a roster that does not contain this hook — a no-op they would record as done.
if ! grep -q 'accounts-board.sh' "$REPO/settings-templates/settings.example.json" 2>/dev/null; then
  echo "0011: settings-templates/settings.example.json does not carry accounts-board.sh — the" >&2
  echo "      roster this step merges FROM lacks the hook. Refusing to file a step that would" >&2
  echo "      wire nothing and read as applied." >&2
  exit 1
fi

# ---- step 2: is it already wired everywhere? then this migration is a no-op -----------------------
# PREMISE RE-DERIVED AT CONSUMPTION, not at authoring (memory discovery-critic-premise-goes-stale):
# a sibling may have run the activation since this was written, and a migration that re-files an
# already-done step trains the operator to ignore the queue.
missing=""
for d in "${DIRS[@]}"; do
  [ -d "$d" ] || continue
  grep -q 'accounts-board.sh' "$d/settings.json" 2>/dev/null || missing="$missing $(basename "$d")"
done
if [ -z "$missing" ] && [ -e "$ROOT/.claude/hooks/accounts-board.sh" ]; then
  echo "0011: accounts-board.sh already wired in every config dir and live at ~/.claude/hooks — recording as applied"
  exit 0
fi

# ---- step 3: hand it to the operator --------------------------------------------------------------
# A c10 body is never executed by deploy-migrations.sh (it reads the header and files the backlog
# item itself), so reaching here means somebody ran this file by hand. Say what to run.
echo
echo "0011: the SessionStart accounts board is landed but reaches no session."
echo "      Unwired config dir(s):${missing:- none} "
if [ ! -e "$ROOT/.claude/hooks/accounts-board.sh" ]; then
  echo "      ⚠ ~/.claude/hooks/accounts-board.sh is ABSENT — it is a NEW file, so the trunk"
  echo "        fast-forward does not create its symlink. Run scripts/deploy-live.sh first."
fi
echo "      settings.json is five separate real files; the mirror will not propagate this."
echo "      Run:  CONFIRM=1 bash $ACTIVATE"
echo "      It merges the template hook roster into each dir (union, backed up), then asserts"
echo "      settings drift. Idempotent — an already-wired dir is left unchanged."
exit 0
