#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 12-mailbox-posttool  —  wire the v3 D5 MID-TURN mail drain into the LIVE per-account settings.json
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: adds, to EVERY config dir that has a settings.json:
#
#     PostToolUse (matcher "", i.e. every tool)  += ~/.claude/hooks/mailbox-drain.sh post-tool  (timeout 5)
#
#   This is the third delivery boundary. 07-comms-drain wired the two RELIABLE ones (SessionStart +
#   UserPromptSubmit); both are session- or human-gated, so a session inside an hours-long autonomous
#   turn passes NEITHER — that is failure R-2 in docs/research/cross-session-mail-2026-07-20.md, and it
#   is what let the live desk sit on 57 unacked pages for 2 h WHILE WORKING. PostToolUse fires on every
#   tool call, which is the only boundary such a turn actually has.
#
#   The entry is COPIED VERBATIM out of settings-templates/settings.example.json at run time (never
#   hand-retyped), so the live wiring can not drift from the template. It is appended as its own
#   {"matcher":"","hooks":[…]} group — a hook list is a list of groups, so appending never disturbs a
#   sibling (notably the teammate-checkpoint group that shares the empty matcher).
#
# WHY THIS IS SAFE TO RUN ON EVERY TOOL CALL — the hook is damped three ways and every path exits 0:
#     • only-when-pending: no mail ⇒ a couple of stats and an exit, no lock, no take
#     • at most one drain per CC_POSTTOOL_DRAIN_MIN_S (default 20 s)
#     • at most CC_POSTTOOL_DRAIN_MAX_LINES (default 20) lines per drain, cursor-exact (nothing dropped)
#
# WHY C10 (agent staged; operator runs): this mutates the live harness config of every account. The
#   agent never self-activates hooks — a bad write here breaks every session that starts afterwards.
#
# SAFETY: per-dir backup to <dir>/settings.json.pre-posttool-drain.bak BEFORE any write · jq only, never
#   sed · post-write validation (parses AND the command is present) · a failed validation RESTORES that
#   dir's backup and ABORTS LOUD · already-wired dirs are SKIPPED (idempotent, no double-add).
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/12-mailbox-posttool-activate.sh
# Rollback: bash ~/.claude/autonomy/pending-activation/12-mailbox-posttool-activate.sh --rollback
# Mark done: touch ~/.claude/autonomy/pending-activation/12-mailbox-posttool-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
TEMPLATE="$REPO/settings-templates/settings.example.json"
LIVE="${CC_LIVE_DIR:-$HOME/.claude}"
BAK_SUFFIX=".pre-posttool-drain.bak"

DEFAULT_DIRS="$HOME/.claude $HOME/.claude-next $HOME/.claude-secondary $HOME/.claude-tertiary $HOME/.claude-quaternary"
CANDIDATE_DIRS="${CC_CONFIG_DIRS:-$DEFAULT_DIRS}"

PT_MATCH='mailbox-drain.sh post-tool'

echo "== 12-mailbox-posttool =="
echo "repo: $REPO"

command -v jq >/dev/null 2>&1 || { echo "✗ jq required" >&2; exit 1; }

# ---- --rollback -----------------------------------------------------------------------------------
if [ "${1:-}" = "--rollback" ]; then
  echo "[rollback] restoring every $BAK_SUFFIX"
  n=0
  for d in $CANDIDATE_DIRS; do
    b="$d/settings.json$BAK_SUFFIX"
    [ -f "$b" ] || continue
    if jq -e . "$b" >/dev/null 2>&1; then
      cp -a "$b" "$d/settings.json" && rm -f "$b" && { echo "  ← $d/settings.json restored"; n=$((n+1)); }
    else
      echo "  ✗ $b does not parse — REFUSING to restore it. Fix by hand." >&2
    fi
  done
  [ "$n" -gt 0 ] && echo "✓ rolled back $n dir(s)." || echo "· nothing to roll back."
  exit 0
fi

# ---- preflight ------------------------------------------------------------------------------------
[ -f "$TEMPLATE" ] || { echo "✗ template not found: $TEMPLATE" >&2; exit 1; }

PT_ENTRY="$(jq -c --arg m "$PT_MATCH" 'first(.hooks.PostToolUse[]?.hooks[]? | select(.command? // "" | contains($m)))' "$TEMPLATE" 2>/dev/null)"
if [ -z "$PT_ENTRY" ] || [ "$PT_ENTRY" = "null" ]; then
  # ── WHY THIS BRANCH ASKS A SECOND QUESTION ────────────────────────────────────────────────────
  # It used to report ONE cause — "the checkout predates the v3-D5 commit" — and prescribe an
  # ff-merge. That is right for a LAGGING checkout and useless for an UNLANDED feature, and on
  # 2026-07-29 it was the second: D5 sat on three ship/backup refs and a worktree branch, an
  # ancestor of none of them origin/main. The prescription then cannot terminate — the operator
  # ff-merges a checkout that is already current, sees no change, and runs it again. A wrong cause
  # is worse than no cause precisely because it is actionable. So: ask trunk, and never name a
  # cause the answer does not support.
  #
  # NO PIPE INTO grep -q HERE. This script runs under `set -o pipefail` (:36), and `producer |
  # grep -q PAT` inverts under it: grep exits at the first match, the producer takes SIGPIPE, and
  # the pipeline reports 141 — a MATCH reads as NO MATCH. A shell case-glob asks the same question
  # with no pipeline at all.
  _trunk_tmpl="$(git -C "$REPO" show "origin/main:settings-templates/settings.example.json" 2>/dev/null || true)"
  _behind="$(git -C "$REPO" rev-list --count HEAD..origin/main 2>/dev/null || echo '?')"
  if [ -z "$_trunk_tmpl" ]; then _trunk=unknown
  else case "$_trunk_tmpl" in *"$PT_MATCH"*) _trunk=has ;; *) _trunk=lacks ;; esac
  fi

  echo "✗ no '$PT_MATCH' entry under .hooks.PostToolUse in $TEMPLATE — nothing to copy. STOP." >&2
  echo >&2
  case "$_trunk" in
    has)
      # Trunk has it, we do not — but "behind" and "diverged locally" are different causes with
      # different fixes, and ff-merge only answers the first. A checkout that is level with trunk
      # and STILL lacks the entry has a modified/stale working file; merging it is a no-op, which
      # is the same dead end in a different costume.
      if [ "$_behind" != '?' ] && [ "$_behind" -gt 0 ] 2>/dev/null; then
        echo "  CAUSE: deploy lag. origin/main HAS the entry; this checkout is behind by ${_behind}." >&2
        # THE SANCTIONED ADVANCE, never a raw ff (hooks/activation-watch.sh:294, commands/ship.md).
        # This line used to hand over `git -C $REPO merge --ff-only origin/main`, the one command the
        # deploy doctrine forbids: a bare ff advances the FILES but creates no symlinks, so a newly
        # landed file goes live unlinked and silently inert, and it skips the green-stamp gate. Here
        # it was worse than advice — a raw ff carries live HEAD ABOVE every green stamp, which is
        # exactly what wedges scripts/deploy-live.sh into refusing every tick (cc-blockers
        # `deploy-wedged`; measured on the live host 2026-08-08, 27 raw ffs in one reflog window).
        echo "  FIX — advance the checkout, then re-run this script:" >&2
        echo "      bash $REPO/scripts/deploy-live.sh   # the ONLY sanctioned advance (green-gated + runs install.sh, which creates the symlinks a bare ff never makes)" >&2
      else
        echo "  CAUSE: local divergence, NOT deploy lag. origin/main HAS the entry and this checkout" >&2
        echo "  is level with it (behind by ${_behind}) — so the working copy of the template has been" >&2
        echo "  modified or is stale. Merging would change nothing." >&2
        echo "  FIX — see what diverged, then restore that one file:" >&2
        echo "      git -C $REPO diff origin/main -- settings-templates/settings.example.json" >&2
        echo "      git -C $REPO checkout origin/main -- settings-templates/settings.example.json" >&2
      fi ;;
    lacks)
      echo "  CAUSE: the FEATURE IS NOT LANDED. origin/main's template does not carry the entry" >&2
      echo "  either, so this is not deploy lag and NO amount of merging will produce it." >&2
      echo "  (This checkout is behind origin/main by ${_behind} commit(s) — irrelevant here.)" >&2
      echo >&2
      echo "  Do NOT re-run this script until the mail-v3 D5 commit is an ancestor of origin/main." >&2
      echo "  Wiring alone would no-op regardless: hooks/mailbox-drain.sh only accepts" >&2
      echo "  session-start|prompt until D5 lands, so a 'post-tool' argument exits 0 silently." >&2
      echo "  Confirm with:" >&2
      echo "      git -C $REPO log --all --oneline -S 'post-tool' -- hooks/mailbox-drain.sh" >&2 ;;
    *)
      echo "  CAUSE: UNDETERMINED — could not read origin/main's template, so this is not known to" >&2
      echo "  be deploy lag and is not known to be an unlanded feature. Do not guess between them." >&2
      echo "  Establish which, then act:" >&2
      echo "      git -C $REPO fetch origin && git -C $REPO show origin/main:settings-templates/settings.example.json | grep -c '$PT_MATCH'" >&2 ;;
  esac
  exit 1
fi

DIRS=""
for d in $CANDIDATE_DIRS; do [ -f "$d/settings.json" ] && DIRS="$DIRS $d"; done
[ -n "$DIRS" ] || { echo "✗ no config dir with a settings.json found in: $CANDIDATE_DIRS" >&2; exit 1; }

echo
echo "Will do:"
echo "  0  ensure live symlinks: hooks/mailbox-drain.sh · hooks/lib/mailbox-pending.sh"
for d in $DIRS; do
  if jq -e --arg m "$PT_MATCH" '[.hooks.PostToolUse[]?.hooks[]?.command? // empty] | any(contains($m))' "$d/settings.json" >/dev/null 2>&1; then
    echo "  ·  $d/settings.json — already wired, WILL SKIP"
  else
    echo "  +  $d/settings.json — add PostToolUse (all tools) drain entry (backup → settings.json$BAK_SUFFIX)"
  fi
done
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/12-mailbox-posttool-activate.sh"
  exit 0
fi

# ---- 0: live symlinks -----------------------------------------------------------------------------
# ~/.claude/hooks is a PER-FILE symlink dir, so a wired hook whose target was never linked errors on
# every tool call. 07-comms-drain already linked both of these; this is the idempotent re-assert.
echo "[0] live symlinks under $LIVE"
if [ -L "$LIVE/hooks" ]; then
  echo "  = $LIVE/hooks is a dir-symlink ($(readlink "$LIVE/hooks")) — per-file links not applicable"
else
  for rel in hooks/mailbox-drain.sh hooks/lib/mailbox-pending.sh; do
    src="$REPO/$rel" dest="$LIVE/$rel"
    [ -e "$src" ] || { echo "  ✗ missing in checkout: $src" >&2; exit 1; }
    if [ -e "$dest" ]; then echo "  = $dest"; continue; fi
    mkdir -p "$(dirname "$dest")"
    if ln -sfn "$src" "$dest"; then echo "  → $dest (linked)"; else echo "  ✗ failed to link $dest" >&2; exit 1; fi
  done
fi

# ---- 1: wire each settings.json -------------------------------------------------------------------
echo "[1] settings.json"
wired=0; skipped=0
for d in $DIRS; do
  S="$d/settings.json"
  if jq -e --arg m "$PT_MATCH" '[.hooks.PostToolUse[]?.hooks[]?.command? // empty] | any(contains($m))' "$S" >/dev/null 2>&1; then
    echo "  = $S (already wired)"; skipped=$((skipped+1)); continue
  fi
  B="$S$BAK_SUFFIX"
  cp -a "$S" "$B" || { echo "  ✗ backup failed — refusing to touch $S" >&2; exit 1; }

  tmp="$S.posttool-drain-tmp.$$"
  if ! jq --argjson pt "$PT_ENTRY" \
        '.hooks //= {}
         | .hooks.PostToolUse = ((.hooks.PostToolUse // []) + [{"matcher":"", "hooks":[$pt]}])' \
        "$S" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    cp -a "$B" "$S"
    echo "  ✗ jq edit FAILED on $S (malformed JSON?) — RESTORED from $B, file UNCHANGED. ABORTING." >&2
    exit 1
  fi

  if jq empty "$tmp" >/dev/null 2>&1 \
     && jq -e --arg m "$PT_MATCH" '[.hooks.PostToolUse[]?.hooks[]?.command? // empty] | any(contains($m))' "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$S" || { rm -f "$tmp"; echo "  ✗ could not replace $S — UNCHANGED (backup at $B)" >&2; exit 1; }
    echo "  → $S (wired: PostToolUse mid-turn drain)"; wired=$((wired+1))
  else
    rm -f "$tmp"
    cp -a "$B" "$S"
    echo "  ✗ VALIDATION FAILED for $S — RESTORED from $B. Nothing wired in this dir. ABORTING." >&2
    echo "    (rollback the dirs already done:  bash $0 --rollback)" >&2
    exit 1
  fi
done

echo
echo "== summary =="
echo "  wired:   $wired"
echo "  skipped: $skipped (already wired)"
echo
echo "✓ mid-turn drain ACTIVE for NEWLY started sessions. Already-running panes keep their old wiring."
echo
echo "  Smoke it: start a new session, set it working, then from another pane:"
echo "      cc-notify <that pane uuid> \"mid-turn probe\""
echo "  Within ~20 s (one tool boundary) the target should surface a 📬 INBOX block WITHOUT you typing,"
echo "  and you should see the '📬 1 message from …' notice in its TUI (that notice is D11)."
echo
echo "  Mark this activation done:"
echo "      touch $HOME/.claude/autonomy/pending-activation/12-mailbox-posttool-activate.sh.done"
echo
echo "ROLLBACK: bash $HOME/.claude/autonomy/pending-activation/12-mailbox-posttool-activate.sh --rollback"
