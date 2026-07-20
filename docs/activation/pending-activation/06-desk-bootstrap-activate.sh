#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 06-desk-bootstrap  —  make `claude-desk` / `/desk` / desk-register live
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: wires the one-command desk bootstrap. Six idempotent steps:
#   1-4  symlink desk-register (bin), desk-brief-inject.sh (hook), desk.md (command), desk.zsh (lib)
#        into the live ~/.claude layer, matching the existing per-file-symlink topology.
#   5    add ONE `source` line to ~/.zshrc so `claude-desk` exists in new shells.
#   6    register hooks/desk-brief-inject.sh in ~/.claude/settings.json SessionStart, so whichever
#        pane holds ~/.claude/cc-roles/desk re-inherits the canonical brief on every start/compact.
#
# WHY C10 (agent staged; operator runs): steps 5-6 activate a hook and mutate the live shell config.
#   The agent never self-activates hooks/daemons/permissions — that ceiling is the whole point of
#   this queue. Steps 1-4 are inert file placements but ride along so activation is ALL-OR-NOTHING;
#   a half-wired state (command present, hook absent) is the confusing one.
#
# SAFETY: every mutation is backed up first (~/.claude/backups/desk-bootstrap-<ts>/) and verified
#   after — ~/.zshrc with `zsh -n`, settings.json with `jq -e`. A failed verify ROLLS BACK that step
#   automatically rather than leaving you with a shell that will not start.
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/06-desk-bootstrap-activate.sh
# Mark done: touch ~/.claude/autonomy/pending-activation/06-desk-bootstrap-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
CFG="$HOME/.claude"
TS="$(date +%Y%m%d-%H%M%S)"
BAK="$CFG/backups/desk-bootstrap-$TS"
# Both literals are written VERBATIM into config files, so they must NOT expand here:
#   SRC_LINE goes into ~/.zshrc, where $HOME must expand at shell-startup time, not now.
#   HOOK_CMD goes into settings.json, whose hook commands all use the `~/…` form (Claude Code
#   expands it) — an absolute path here would be inconsistent with every sibling entry.
# shellcheck disable=SC2016
SRC_LINE='[[ -f "$HOME/.claude/lib/desk.zsh" ]] && source "$HOME/.claude/lib/desk.zsh"'
# shellcheck disable=SC2088
HOOK_CMD='~/.claude/hooks/desk-brief-inject.sh'

echo "== 06-desk-bootstrap =="
echo "repo: $REPO"

# ---- preflight -------------------------------------------------------------------------------
fail=0
for f in bin/desk-register hooks/desk-brief-inject.sh commands/desk.md lib/desk.zsh \
         docs/templates/desk-boot-brief.md; do
  if [ ! -f "$REPO/$f" ]; then echo "✗ missing in checkout: $REPO/$f" >&2; fail=1; fi
done
[ "$fail" = 0 ] || { echo "✗ preflight failed — is the checkout on a trunk that has the desk-bootstrap commit? (git -C $REPO pull --ff-only)" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "✗ jq required for step 6" >&2; exit 1; }

echo
echo "Will do:"
echo "  1-4  symlink bin/desk-register, hooks/desk-brief-inject.sh, commands/desk.md, lib/desk.zsh → $CFG/"
echo "  5    append to ~/.zshrc:  $SRC_LINE"
echo "  6    add $HOOK_CMD to SessionStart in $CFG/settings.json"
echo "  backups → $BAK"
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/06-desk-bootstrap-activate.sh"
  exit 0
fi

mkdir -p "$BAK" || { echo "✗ cannot create backup dir $BAK" >&2; exit 1; }

# ---- 1-4: live symlinks ------------------------------------------------------------------------
link() { # $1=repo-relative src  $2=absolute dest
  local src="$REPO/$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then echo "  = $dest (already linked)"; return 0; fi
  [ -e "$dest" ] && cp -a "$dest" "$BAK/$(basename "$dest")" 2>/dev/null
  if ln -sfn "$src" "$dest"; then echo "  → $dest"; else echo "  ✗ failed: $dest" >&2; return 1; fi
}
echo "[1-4] live symlinks"
link bin/desk-register            "$CFG/bin/desk-register"            || exit 1
link hooks/desk-brief-inject.sh   "$CFG/hooks/desk-brief-inject.sh"   || exit 1
link commands/desk.md             "$CFG/commands/desk.md"             || exit 1
link lib/desk.zsh                 "$CFG/lib/desk.zsh"                 || exit 1

# ---- 5: ~/.zshrc source line -------------------------------------------------------------------
echo "[5] ~/.zshrc"
if grep -qF 'lib/desk.zsh' "$HOME/.zshrc" 2>/dev/null; then
  echo "  = already sourced"
else
  cp -a "$HOME/.zshrc" "$BAK/zshrc" || { echo "  ✗ backup failed — refusing to touch ~/.zshrc" >&2; exit 1; }
  {
    printf '\n# claude-desk — one command to start the machine-wide orchestrator desk.\n'
    printf '# Defines claude-desk (+ claude-desk2/3/4); composes claude-next above.\n'
    printf '%s\n' "$SRC_LINE"
  } >> "$HOME/.zshrc"
  if zsh -n "$HOME/.zshrc" 2>/dev/null; then
    echo "  → appended (zsh -n clean)"
  else
    cp -a "$BAK/zshrc" "$HOME/.zshrc"
    echo "  ✗ zsh -n FAILED after append — ROLLED BACK from $BAK/zshrc. Nothing changed." >&2
    exit 1
  fi
fi

# ---- 6: SessionStart hook -----------------------------------------------------------------------
echo "[6] settings.json SessionStart"
S="$CFG/settings.json"
if [ ! -f "$S" ]; then
  echo "  ✗ $S not found — wire $HOOK_CMD into SessionStart by hand." >&2; exit 1
fi
if jq -e --arg c "$HOOK_CMD" '.hooks.SessionStart[]?.hooks[]?|select(.command==$c)' "$S" >/dev/null 2>&1; then
  echo "  = already wired"
else
  cp -a "$S" "$BAK/settings.json" || { echo "  ✗ backup failed — refusing to touch settings.json" >&2; exit 1; }
  tmp="$S.desk-tmp.$$"
  if jq --arg c "$HOOK_CMD" \
       '.hooks.SessionStart += [{"hooks":[{"type":"command","command":$c,"timeout":5}]}]' \
       "$S" > "$tmp" 2>/dev/null && jq -e . "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$S" && echo "  → wired (timeout 5s)"
  else
    rm -f "$tmp"
    echo "  ✗ jq edit failed — settings.json UNCHANGED (backup at $BAK/settings.json)" >&2
    exit 1
  fi
fi

# ---- verify -------------------------------------------------------------------------------------
echo
echo "== verify =="
"$CFG/bin/desk-register" --print >/dev/null 2>&1 \
  && echo "  desk role currently held by: $("$CFG/bin/desk-register" --print)" \
  || echo "  desk role: unregistered (expected until you run claude-desk or /desk)"
echo "  brief: $REPO/docs/templates/desk-boot-brief.md ($(wc -l < "$REPO/docs/templates/desk-boot-brief.md" | tr -d ' ') lines)"
echo
echo "✓ desk bootstrap ACTIVE. Open a NEW terminal tab (or: source ~/.zshrc), then run:"
echo
echo "      claude-desk"
echo
echo "  In an already-open session instead:  /desk"
echo "  Mark this activation done:"
echo "      touch $HOME/.claude/autonomy/pending-activation/06-desk-bootstrap-activate.sh.done"
echo
echo "ROLLBACK: rm $CFG/bin/desk-register $CFG/hooks/desk-brief-inject.sh $CFG/commands/desk.md $CFG/lib/desk.zsh"
echo "          cp -a $BAK/zshrc ~/.zshrc ; cp -a $BAK/settings.json $CFG/settings.json"
