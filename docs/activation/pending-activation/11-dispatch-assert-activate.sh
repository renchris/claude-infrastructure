#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 11-dispatch-assert  —  narrated-not-dispatched follow-on work must become a durable record
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: two idempotent steps (the 09-operator-readout shape).
#   1  symlink hooks/dispatch-assert.sh into the live ~/.claude/hooks/ layer (per-file topology —
#      settings-hooks-lint's DEAD class: a new tracked hook is otherwise simply never linked).
#   2  register it in the Stop obj-0 chain of EVERY config dir's settings.json, AFTER
#      completion-assert (portable `~/.claude/…` path, matching every sibling entry).
#
# WHY: completion-assert catches a false "done" because git writes its facts unavoidably. Named
#   follow-on work has NO such fact — it lives only in prose, governed only by the self-applied
#   Follow-On Gate, and self-application demonstrably fails (2026-07-25: "cc-inbox-guard deserves
#   its own scoped pass" — written, F1-F4 satisfied, never fired until the operator re-asked).
#   dispatch-assert.sh is the mechanical enqueue-edge: naming-tell ∧ no-queue-write-since-turn-start
#   → block ONCE with the exact commands (cc-backlog add / fire / block --needs / cc-decide). The
#   only discharge is an actual durable record — gaming the hook IS compliance. Obligation state
#   survives the block's own window reset; caps at DISPATCH_ASSERT_MAX (2) + session total (6);
#   operator kill-phrases and DISPATCH_ASSERT_DISABLE=1 abstain. tests/dispatch-assert.bats (19).
#
# WHY C10 (agent stages; operator runs): step 2 mutates live settings.json and activates a
#   BLOCKING Stop hook. The agent never self-activates hooks.
#
# SAFETY: every settings.json is backed up first and verified with `jq -e` after; a failed edit
#   leaves the file untouched. Step 1 is an inert file placement. Re-running is a no-op.
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/11-dispatch-assert-activate.sh
# Mark done: touch ~/.claude/autonomy/pending-activation/11-dispatch-assert-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
CFG="$HOME/.claude"
TS="$(date +%Y%m%d-%H%M%S)"
BAK="$CFG/backups/dispatch-assert-$TS"
CFG_DIRS=("$HOME/.claude" "$HOME/.claude-next" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary")
# Written VERBATIM into settings.json, whose hook commands all use the `~/…` form (Claude Code
# expands it) — an absolute path here would be inconsistent with every sibling entry.
# shellcheck disable=SC2088
HOOK_CMD='~/.claude/hooks/dispatch-assert.sh'

echo "== 11-dispatch-assert =="
echo "repo: $REPO"

# ---- preflight -------------------------------------------------------------------------------
if [ ! -f "$REPO/hooks/dispatch-assert.sh" ]; then
  echo "✗ missing in checkout: $REPO/hooks/dispatch-assert.sh" >&2
  echo "  is the checkout on a trunk that has this commit? (git -C $REPO pull --ff-only)" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "✗ jq required for step 2" >&2; exit 1; }

echo
echo "Will do:"
echo "  1  symlink hooks/dispatch-assert.sh → $CFG/hooks/"
echo "  2  append $HOOK_CMD to Stop obj-0 (timeout 10, after completion-assert) in settings.json of:"
for d in "${CFG_DIRS[@]}"; do
  [ -f "$d/settings.json" ] && echo "       $d"
done
echo "  backups → $BAK"
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/11-dispatch-assert-activate.sh"
  exit 0
fi

mkdir -p "$BAK" || { echo "✗ cannot create backup dir $BAK" >&2; exit 1; }

# ---- 1: live symlink ---------------------------------------------------------------------------
echo "[1] live symlink"
SRC="$REPO/hooks/dispatch-assert.sh"
DEST="$CFG/hooks/dispatch-assert.sh"
mkdir -p "$(dirname "$DEST")"
if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then
  echo "  = $DEST (already linked)"
else
  [ -e "$DEST" ] && cp -a "$DEST" "$BAK/dispatch-assert.sh" 2>/dev/null
  if ln -sfn "$SRC" "$DEST"; then echo "  → $DEST"; else echo "  ✗ failed: $DEST" >&2; exit 1; fi
fi

# ---- 2: Stop wiring on EVERY config dir --------------------------------------------------------
echo "[2] settings.json Stop wiring (all config dirs)"
fail=0
for d in "${CFG_DIRS[@]}"; do
  S="$d/settings.json"
  [ -f "$S" ] || { echo "  - $d: no settings.json (skip)"; continue; }
  if jq -e --arg c "$HOOK_CMD" '.hooks.Stop[]?.hooks[]?|select(.command==$c)' "$S" >/dev/null 2>&1; then
    echo "  = $d: already wired"; continue
  fi
  bdir="$BAK/$(basename "$d")"; mkdir -p "$bdir"
  cp -a "$S" "$bdir/settings.json" || { echo "  ✗ $d: backup failed — dir UNTOUCHED" >&2; fail=1; continue; }
  tmp="$S.dispassert-tmp.$$"
  # Insert directly AFTER completion-assert when present (the two are one doctrine: false-done,
  # then narrated-not-dispatched); plain append otherwise.
  if jq --arg c "$HOOK_CMD" '
       (.hooks.Stop[0].hooks) |= (
         (. // []) as $h
         | ([ $h[] | .command // "" | test("completion-assert") ] | index(true)) as $i
         | if $i == null then $h + [{type:"command",command:$c,timeout:10}]
           else $h[0:$i+1] + [{type:"command",command:$c,timeout:10}] + $h[$i+1:] end)' \
       "$S" > "$tmp" 2>/dev/null && jq -e . "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$S" && echo "  → $d: wired (Stop obj-0, after completion-assert, timeout 10)"
  else
    rm -f "$tmp"
    echo "  ✗ $d: jq edit failed — settings.json UNCHANGED (backup at $bdir/settings.json)" >&2
    fail=1
  fi
done
[ "$fail" -eq 0 ] || { echo "✗ one or more dirs failed — see above; nothing partially-written." >&2; exit 1; }

# ---- verify -------------------------------------------------------------------------------------
echo
echo "== verify =="
for d in "${CFG_DIRS[@]}"; do
  S="$d/settings.json"; [ -f "$S" ] || continue
  if jq -e --arg c "$HOOK_CMD" '[.hooks.Stop[]?.hooks[]?.command]|any(.==$c)' "$S" >/dev/null 2>&1; then
    echo "  ✓ $d carries $HOOK_CMD"
  else
    echo "  ✗ $d NOT wired after edit — restore: cp -a $BAK/$(basename "$d")/settings.json $S" >&2; exit 1
  fi
done
if [ -x "$REPO/scripts/settings-hooks-lint.sh" ]; then
  if "$REPO/scripts/settings-hooks-lint.sh" >/dev/null 2>&1; then
    echo "  ✓ settings-hooks-lint clean (no DUPLICATE / DEAD / DANGLING)"
  else
    echo "  ⚠ settings-hooks-lint reports findings — run: $REPO/scripts/settings-hooks-lint.sh" >&2
  fi
fi
echo "  smoke (fail-open on empty stdin): $(printf '' | "$CFG/hooks/dispatch-assert.sh" && echo 'exit 0 ✓')"
echo
echo "✓ dispatch-assert ACTIVE for every session started from now on."
echo "  (Sessions already running picked their hook set at start — it applies from their next launch.)"
echo
echo "  Mark this activation done:"
echo "      touch $HOME/.claude/autonomy/pending-activation/11-dispatch-assert-activate.sh.done"
echo
echo "ROLLBACK: rm $DEST ; for d in ${CFG_DIRS[*]}; do [ -f $BAK/\$(basename \$d)/settings.json ] && cp -a $BAK/\$(basename \$d)/settings.json \$d/settings.json; done"
