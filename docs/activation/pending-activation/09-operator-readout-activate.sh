#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 09-operator-readout  —  silver-platter close block at every Stop (operator crux 2026-07-20)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: two idempotent steps.
#   1  symlink hooks/operator-readout.sh into the live ~/.claude/hooks/ layer (per-file topology).
#   2  register it LAST in the Stop obj-0 chain of EVERY config dir's settings.json
#      (~/.claude, -secondary, -tertiary, -quaternary — the G-P6-5b lesson: a hook wired on one
#      dir via an abs path never evaluates for the desk accounts), portable `~/.claude/…` path.
#
# WHY: manual operator steps (pending activations · open class-C decisions · blocked backlog ·
#   deploy-lag) were surfaced only as model PROSE at turn close — a discipline, not a construction;
#   the exact runnable command could be buried under paragraphs or omitted. operator-readout.sh
#   renders the close block BY CONSTRUCTION from disk truth: one state line (wrap-ledger rung),
#   then numbered `▶ <exact command>` lines, damped (change → render now; unchanged → re-assert
#   after 15 min). Pure-advisory {systemMessage} — it NEVER blocks the model (zero loop risk).
#   Proven: tests/operator-readout.bats (18 green) + live render of the real 29-step board.
#
# WHY C10 (agent stages; operator runs): step 2 mutates live settings.json and activates a hook.
#   The agent never self-activates hooks — that ceiling is the whole point of this queue.
#
# SAFETY: every settings.json is backed up first (~/.claude/backups/operator-readout-<ts>/) and
#   verified with `jq -e` after; a failed verify ROLLS BACK that dir automatically. Step 1 is an
#   inert file placement. Re-running is a no-op (idempotent).
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/09-operator-readout-activate.sh
# Mark done: touch ~/.claude/autonomy/pending-activation/09-operator-readout-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
CFG="$HOME/.claude"
TS="$(date +%Y%m%d-%H%M%S)"
BAK="$CFG/backups/operator-readout-$TS"
# Written VERBATIM into settings.json, whose hook commands all use the `~/…` form (Claude Code
# expands it) — an absolute path here would be inconsistent with every sibling entry.
# shellcheck disable=SC2088
HOOK_CMD='~/.claude/hooks/operator-readout.sh'

echo "== 09-operator-readout =="
echo "repo: $REPO"

# ---- preflight -------------------------------------------------------------------------------
if [ ! -f "$REPO/hooks/operator-readout.sh" ]; then
  echo "✗ missing in checkout: $REPO/hooks/operator-readout.sh" >&2
  echo "  is the checkout on a trunk that has this commit? (git -C $REPO pull --ff-only)" >&2
  exit 1
fi
command -v jq >/dev/null 2>&1 || { echo "✗ jq required for step 2" >&2; exit 1; }

echo
echo "Will do:"
echo "  1  symlink hooks/operator-readout.sh → $CFG/hooks/"
echo "  2  append $HOOK_CMD to Stop obj-0 (timeout 10) in settings.json of:"
for d in "$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
  [ -f "$d/settings.json" ] && echo "       $d"
done
echo "  backups → $BAK"
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/09-operator-readout-activate.sh"
  exit 0
fi

mkdir -p "$BAK" || { echo "✗ cannot create backup dir $BAK" >&2; exit 1; }

# ---- 1: live symlink ---------------------------------------------------------------------------
echo "[1] live symlink"
SRC="$REPO/hooks/operator-readout.sh"
DEST="$CFG/hooks/operator-readout.sh"
mkdir -p "$(dirname "$DEST")"
if [ -L "$DEST" ] && [ "$(readlink "$DEST")" = "$SRC" ]; then
  echo "  = $DEST (already linked)"
else
  [ -e "$DEST" ] && cp -a "$DEST" "$BAK/operator-readout.sh" 2>/dev/null
  if ln -sfn "$SRC" "$DEST"; then echo "  → $DEST"; else echo "  ✗ failed: $DEST" >&2; exit 1; fi
fi

# ---- 2: Stop wiring on EVERY config dir --------------------------------------------------------
echo "[2] settings.json Stop wiring (all config dirs)"
fail=0
for d in "$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
  S="$d/settings.json"
  [ -f "$S" ] || { echo "  - $d: no settings.json (skip)"; continue; }
  if jq -e --arg c "$HOOK_CMD" '.hooks.Stop[]?.hooks[]?|select(.command==$c)' "$S" >/dev/null 2>&1; then
    echo "  = $d: already wired"; continue
  fi
  bdir="$BAK/$(basename "$d")"; mkdir -p "$bdir"
  cp -a "$S" "$bdir/settings.json" || { echo "  ✗ $d: backup failed — dir UNTOUCHED" >&2; fail=1; continue; }
  tmp="$S.opreadout-tmp.$$"
  if jq --arg c "$HOOK_CMD" \
       '(.hooks.Stop[0].hooks) |= ((. // []) + [{type:"command",command:$c,timeout:10}])' \
       "$S" > "$tmp" 2>/dev/null && jq -e . "$tmp" >/dev/null 2>&1; then
    mv -f "$tmp" "$S" && echo "  → $d: wired (Stop obj-0, timeout 10)"
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
for d in "$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"; do
  S="$d/settings.json"; [ -f "$S" ] || continue
  if jq -e --arg c "$HOOK_CMD" '[.hooks.Stop[]?.hooks[]?.command]|any(.==$c)' "$S" >/dev/null 2>&1; then
    echo "  ✓ $d carries $HOOK_CMD"
  else
    echo "  ✗ $d NOT wired after edit — restore: cp -a $BAK/$(basename "$d")/settings.json $S" >&2; exit 1
  fi
done
echo "  smoke: $("$CFG/hooks/operator-readout.sh" --render 2>&1 | head -1)"
echo
echo "✓ silver-platter close block ACTIVE for every session started from now on."
echo "  (Sessions already running picked their hook set at start — it applies from their next launch.)"
echo
echo "  Mark this activation done:"
echo "      touch $HOME/.claude/autonomy/pending-activation/09-operator-readout-activate.sh.done"
echo
echo "ROLLBACK: rm $DEST ; for d in ~/.claude ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do [ -f $BAK/\$(basename \$d)/settings.json ] && cp -a $BAK/\$(basename \$d)/settings.json \$d/settings.json; done"
