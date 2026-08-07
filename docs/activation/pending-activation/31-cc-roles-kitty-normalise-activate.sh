#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 31-cc-roles-kitty-normalise  —  retire the iTerm2 UUIDs sitting in ~/.claude/cc-roles/ on a kitty box
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: back up ~/.claude/cc-roles/{desk,operator,orchestrator}, then remove (or re-point) each one
#   whose contents cannot be a window id in the terminal that is actually running.
#
# WHY: measured 2026-08-07, all three files hold iTerm2 session UUIDs —
#     desk         D40A5752-F313-4F2C-B5BF-2FADE3BADB2C
#     operator     D5D419C8-8B79-4C05-A38C-DF0A85A1AAE2
#     orchestrator D5D419C8-8B79-4C05-A38C-DF0A85A1AAE2
#   — while this box runs kitty, whose window ids are small integers. handoff-fire's kitty anchor
#   picker keys its lookup table by integer id, so `by_id.get(desk)` was unconditionally None: the
#   desk preference has been dead code since the fleet moved off iTerm2, and every headless fire
#   silently fell past it onto an operator-owned pane. On 2026-08-07 that took a pane the operator
#   was composing into, and the unsent message was unrecoverable.
#
# WHY THIS IS NOW URGENT RATHER THAN COSMETIC — READ THIS BEFORE DECIDING:
#   The fix landed with it: a role hint that cannot exist in the live terminal's id space is treated
#   as a BROKEN INVARIANT, not a miss, and `it2py anchor` REFUSES (rc 3) instead of guessing. That is
#   deliberate — the silent fallthrough is exactly what turned a stale file into "target the
#   operator" — but it means that while these files hold UUIDs, EVERY HEADLESS FIRE IS HELD.
#   Autonomous dispatch is fail-closed until this script runs. Nothing is lost while it is held
#   (cc-dispatch reopens the claim), but nothing is dispatched either.
#
# WHY REMOVE RATHER THAN REPOINT (the default): an ABSENT desk role is a MISS, and a miss is safe —
#   the picker falls through to a provably agent-owned pane (a live ~/.claude/cc-fired/<id>.json with
#   a live registry pid) and refuses if there is none. A WRONG desk role is not safe, which is the
#   whole lesson here. So unless a desk session is genuinely running in a kitty window you can name,
#   removal is the correct end state and fires resume immediately.
#
# WHY C10 (agent stages; operator runs): ~/.claude/cc-roles/* is LIVE operator state read by a
#   running fleet. An agent rewriting it underneath concurrent sessions is the class of edit this
#   repo forbids outright.
#
# REPOINT INSTEAD: CC_ROLES_DESK=<kitty window id> ./31-cc-roles-kitty-normalise-activate.sh
#   (verified live before it is written; a non-existent id is refused).
# DRY RUN:  CC_ROLES_DRY=1 ./31-cc-roles-kitty-normalise-activate.sh
# UNDO:     cp ~/.claude/cc-roles.bak-<stamp>/* ~/.claude/cc-roles/
# Mark done: touch <this file>.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

ROLES="$HOME/.claude/cc-roles"
DRY="${CC_ROLES_DRY:-0}"
WANT_DESK="${CC_ROLES_DESK:-}"
KITTY_BIN="${CC_TERM_KITTY:-$(command -v kitty 2>/dev/null || true)}"

say() { printf '%s\n' "$*"; }
run() { if [ "$DRY" = 1 ]; then say "  DRY: $*"; else "$@"; fi; }

[ -d "$ROLES" ] || { say "✓ $ROLES does not exist — nothing to normalise."; exit 0; }

# ── 1. which terminal is actually running, and what shape are its ids? ──────────────────────────────
TERM_KIND=iterm2
if [ -n "$KITTY_BIN" ] && "$KITTY_BIN" @ ls >/dev/null 2>&1; then
  TERM_KIND=kitty
fi
say "Live terminal: $TERM_KIND"
if [ "$TERM_KIND" != kitty ]; then
  say "!! kitty's control socket did not answer, so the live id space cannot be established."
  say "   Refusing to rewrite role files on a guess — that is the defect this script exists to undo."
  say "   Run this from a kitty box (or set CC_TERM_KITTY) and try again."
  exit 3
fi

LIVE_IDS="$("$KITTY_BIN" @ ls 2>/dev/null | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
print(" ".join(str(w.get("id")) for ow in d for t in ow.get("tabs", []) for w in t.get("windows", [])))
')" || { say "!! could not enumerate kitty windows — aborting rather than guessing."; exit 3; }
say "Live kitty window ids: ${LIVE_IDS:-<none>}"

# ── 2. back up before touching anything ────────────────────────────────────────────────────────────
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BAK="$HOME/.claude/cc-roles.bak-$STAMP"
say
say "Backing up to $BAK"
run mkdir -p "$BAK"
for f in "$ROLES"/*; do
  [ -f "$f" ] || continue
  run cp -p "$f" "$BAK/"
done

# ── 3. per-role verdict ────────────────────────────────────────────────────────────────────────────
say
CHANGED=0
for role in desk operator orchestrator; do
  f="$ROLES/$role"
  [ -f "$f" ] || { say "· $role — absent (safe: an absent hint is a miss, and a miss falls through)"; continue; }
  cur="$(tr -d '[:space:]' < "$f" 2>/dev/null || true)"
  if [ -z "$cur" ]; then
    say "· $role — empty (safe)"
    continue
  fi
  case "$cur" in
    *[!0-9]*)
      say "· $role — '$cur' is NOT a kitty window id (wrong terminal's id space) ⇒ REMOVING"
      run rm -f "$f"
      CHANGED=1
      ;;
    *)
      # Digits — right SHAPE, but a kitty window id is a per-process counter that restarts at 1, so
      # shape is not existence. Verify against the live enumeration before blessing it.
      if printf '%s\n' $LIVE_IDS | grep -qx "$cur"; then
        say "· $role — '$cur' is a LIVE kitty window ⇒ keeping"
      else
        say "· $role — '$cur' is kitty-shaped but names no live window (stale) ⇒ REMOVING"
        run rm -f "$f"
        CHANGED=1
      fi
      ;;
  esac
done

# ── 4. optional repoint ────────────────────────────────────────────────────────────────────────────
if [ -n "$WANT_DESK" ]; then
  say
  if printf '%s\n' $LIVE_IDS | grep -qx "$WANT_DESK"; then
    say "Re-pointing desk → kitty window $WANT_DESK"
    run bash -c "printf '%s' '$WANT_DESK' > '$ROLES/desk'"
    CHANGED=1
  else
    say "!! CC_ROLES_DESK=$WANT_DESK is not a live kitty window — REFUSED."
    say "   Live ids: ${LIVE_IDS:-<none>}. Writing an id that does not exist re-creates the bug."
    exit 3
  fi
fi

# ── 5. verdict ─────────────────────────────────────────────────────────────────────────────────────
say
if [ "$DRY" = 1 ]; then
  say "DRY RUN — nothing was written. Re-run without CC_ROLES_DRY=1 to apply."
  exit 0
fi
if [ "$CHANGED" = 1 ]; then
  say "✓ cc-roles normalised. Headless fires resume on the next dispatcher cadence:"
  say "  an absent desk hint falls through to a provably agent-owned pane, and refuses if none exists."
else
  say "✓ nothing needed changing — every role file already names a live kitty window."
fi
say "  Backup: $BAK    Undo: cp $BAK/* $ROLES/"
say "  Verify: ~/.claude/scripts/handoff-fire.sh --dry-run   (its anchor: line states the decision)"
