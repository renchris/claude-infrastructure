#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# 45-opus55-cc280-activate — repoint the everyday launcher onto 2.1.280 + Claude Opus 5.5
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: three edits to ~/.zshrc inside claude(), all idempotent, all reversible with --undo,
#   one timestamped backup taken before any write.
#     (1) _bin pin           ~/.claude-260 → ~/.claude-280     (2.1.280 already installed)
#     (2)+(3) the two --model default sites: claude-opus-5 → claude-opus-5-5
#
# WHY THE BINARY: claude-opus-5-5 requires CC >= 2.1.280. Measured on 2.1.260, the API refuses it
#   BY NAME — 400 [claude-code:unrecognized_model] "Claude Code 2.1.260 does not support this
#   model; version 2.1.280 or newer is required". So this is a binary gate, not entitlement:
#   all four accounts are entitled (gate check #2).
#
# WHY NOW, against this repo's own ">=7 d age since publish" churn bar, which 2.1.280 FAILS
#   (published 2026-09-22 15:44Z; hours old at activation): the bar is a PROXY for field evidence,
#   and cc-upgrade-gate is the evidence itself. Operator mandate, cc-upgrade-gate skill: "we ALWAYS
#   upgrade immediately to a new model IF all our ways of working continue to work." Run 2026-09-22:
#
#     scripts/cc-upgrade-gate.sh ~/.claude-280/node_modules/.bin/claude claude-opus-5-5 \
#                                next next2 next3 next4
#       → 14 pass · 0 fail · 1 skip — VERDICT: GREEN
#
#   covering: binary registers 5-5 without demotion · entitlement on ALL FOUR accounts · auto-mode
#   drives a real tool turn · effort ladder high/xhigh/max · launcher effect-read · SPAWN_DEPTH
#   containment (BOTH surfaces) · teammate spawn · Dynamic Workflow · subagent · lifecycle hooks ·
#   permission non-block · resume routing · 8 MCP servers connected · depth-effect FLAT topology.
#   The one skip is #14 authstore-writeloss: unchanged from the 2.1.220 baseline, known-open
#   upstream, and explicitly not an upgrade blocker (an alarm that fires on every candidate
#   forever carries no information).
#
# THE #68619 CONTAINMENT LEVER SURVIVES — and this is the load-bearing check, not a formality.
#   2.1.224 removed the 200-subagent-per-session cap, so CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH is
#   the ONLY runaway bound left on a box that fans out N=10 and has four memory-storm kernel panics
#   on record. Nothing in the 261-280 band restores a ceiling and 2.1.269 moves the other way
#   (CLAUDE_CODE_MAX_CONCURRENT_AGENTS, 1-256). Gate #6 proves the export still REACHES the 280
#   binary via both surfaces; gate #15 proves the binary still REFUSES at depth >= max. The
#   `export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` at ~/.zshrc:484 therefore stays load-bearing
#   and this script does not touch it.
#
# WHAT THIS SCRIPT DELIBERATELY DOES NOT DO: the SSOT flip in model-config.yaml
#   (opus_latest/opus_prior/opus_staged + the role keys). ~/.claude/model-config.yaml is a SYMLINK
#   into the shared claude-infrastructure checkout, so editing it here would dirty a tree several
#   sessions share and bypass the land gate. That half goes through a worktree + the project-local
#   /ship + deploy-live, and the symlink picks it up on the fast-forward.
#
# ORDER MATTERS, and it is binary-first by construction: this script moves the launcher to a binary
#   that runs BOTH claude-opus-5 and claude-opus-5-5, so there is never a window where a config
#   names 5.5 while the binary cannot dispatch it. The SSOT flip lands after.
#
# EFFORT — the one behavioural trap, already closed. Opus 5.5 defaults to effort `medium` where
#   every prior Opus defaulted to `high`, and 2.1.280 separately stops a saved /effort from
#   applying to newly released models. Both of our paths pass effort EXPLICITLY —
#   ~/.zshrc `_eff="${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}}"` and the SSOT's
#   `effort_defaults.default: high` — so no session silently drops a rung. Verified, not assumed.
#
# A ZSHRC EDIT IS NOT A SHELL FLIP: already-running shells keep the old launcher body. This goes
#   live for shells started AFTER it runs. Existing panes stay on 2.1.260 until they are recycled,
#   which is the desired gradual rollout, not a bug.
#
# ROLLBACK: `bash 45-opus55-cc280-activate.sh --undo` (or repoint the three lines by hand).
#   ~/.claude-260 is left fully installed and untouched as the rollback floor.
#
# RUN:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/45-opus55-cc280-activate.sh
# ═══════════════════════════════════════════════════════════════════════════════════════════════
set -uo pipefail

ZSHRC="$HOME/.zshrc"
BIN280="$HOME/.claude-280/node_modules/.bin/claude"
OLD_DIR=".claude-260"; NEW_DIR=".claude-280"
OLD_MODEL="claude-opus-5"; NEW_MODEL="claude-opus-5-5"
BAK="$HOME/.claude/autonomy/backups/opus55-cc280-$(date -u +%Y%m%dT%H%M%SZ)"

# ---------- --undo -----------------------------------------------------------------------------
if [ "${1:-}" = "--undo" ]; then
  # shellcheck disable=SC2012  # backup dirs are timestamps this script names; ls -1d sorts them
  last="$(ls -1d "$HOME"/.claude/autonomy/backups/opus55-cc280-* 2>/dev/null | tail -1)"
  [ -n "$last" ] && [ -f "$last/zshrc" ] || { echo "✗ no backup to undo from" >&2; exit 1; }
  cp -a "$last/zshrc" "$ZSHRC" || exit 1
  echo "✓ restored ~/.zshrc from $last"
  echo "  open a NEW shell (or: source ~/.zshrc) — running shells keep the old body either way."
  exit 0
fi

fail=0
echo "== 45-opus55-cc280-activate =="

# ---------- preflight (fail-closed) ------------------------------------------------------------
v280="$(node -e "console.log(require('$HOME/$NEW_DIR/node_modules/@anthropic-ai/claude-code/package.json').version)" 2>/dev/null)"
if [ "$v280" = "2.1.280" ]; then
  echo "  ✓ $NEW_DIR present and is 2.1.280"
else
  echo "  ✗ $NEW_DIR is '${v280:-missing}' (need exactly 2.1.280)" >&2
  echo "    npm install --prefix ~/$NEW_DIR @anthropic-ai/claude-code@2.1.280" >&2
  fail=1
fi
[ -x "$BIN280" ] || { echo "  ✗ not executable: $BIN280" >&2; fail=1; }

# the rollback floor must still exist BEFORE we move off it
[ -x "$HOME/$OLD_DIR/node_modules/.bin/claude" ] \
  || { echo "  ✗ rollback floor missing: ~/$OLD_DIR — refusing to advance with no way back" >&2; fail=1; }

# the binary must actually dispatch the model (modelUsage proof, not a version string)
if [ "$fail" -eq 0 ]; then
  echo "  … smoke: $NEW_MODEL on 2.1.280"
  smoke="$("$BIN280" --model "$NEW_MODEL" --print --output-format json "Reply with exactly: ok" 2>/dev/null)"
  if printf '%s' "$smoke" | M="$NEW_MODEL" python3 -c 'import sys,json,os;o=json.load(sys.stdin);sys.exit(0 if os.environ["M"] in (o.get("modelUsage") or {}) and not o.get("is_error") else 1)' 2>/dev/null; then
    echo "  ✓ reachable + entitled (modelUsage carries $NEW_MODEL)"
  else
    echo "  ✗ $NEW_MODEL did not return a verified completion on 2.1.280" >&2; fail=1
  fi
fi

# anchors must be exactly where we think they are
n_bin=$(grep -c "local _bin=\"\$HOME/$OLD_DIR/node_modules/.bin/claude\"" "$ZSHRC" 2>/dev/null || true)
n_mod=$(grep -c -- "--model \"\${CLAUDE_NEXT_MODEL:-$OLD_MODEL}\"" "$ZSHRC" 2>/dev/null || true)
already_bin=$(grep -c "local _bin=\"\$HOME/$NEW_DIR/node_modules/.bin/claude\"" "$ZSHRC" 2>/dev/null || true)
already_mod=$(grep -c -- "--model \"\${CLAUDE_NEXT_MODEL:-$NEW_MODEL}\"" "$ZSHRC" 2>/dev/null || true)

if [ "$already_bin" -ge 1 ] && [ "$already_mod" -ge 2 ]; then
  echo "  = already activated (binary $NEW_DIR, model $NEW_MODEL) — nothing to do"; exit 0
fi
[ "$n_bin" -eq 1 ] || { echo "  ✗ expected exactly 1 _bin anchor for $OLD_DIR, found $n_bin" >&2; fail=1; }
[ "$n_mod" -eq 2 ] || { echo "  ✗ expected exactly 2 --model anchors for $OLD_MODEL, found $n_mod" >&2; fail=1; }

[ "$fail" -eq 0 ] || { echo "✗ preflight failed — nothing written." >&2; exit 1; }
[ "${CONFIRM:-0}" = "1" ] || { echo; echo "DRY RUN. Re-run with CONFIRM=1 to write."; exit 0; }

# ---------- backup, then edit ------------------------------------------------------------------
mkdir -p "$BAK" && cp -a "$ZSHRC" "$BAK/zshrc" || { echo "✗ backup failed — aborting." >&2; exit 1; }
echo "  ✓ backup: $BAK/zshrc"

ZSHRC="$ZSHRC" OD="$OLD_DIR" ND="$NEW_DIR" OM="$OLD_MODEL" NM="$NEW_MODEL" python3 <<'PY'
import os, sys
p = os.environ["ZSHRC"]; od, nd = os.environ["OD"], os.environ["ND"]
om, nm = os.environ["OM"], os.environ["NM"]
src = open(p).read()
a_bin_old = f'local _bin="$HOME/{od}/node_modules/.bin/claude"'
a_bin_new = f'local _bin="$HOME/{nd}/node_modules/.bin/claude"'
a_mod_old = f'--model "${{CLAUDE_NEXT_MODEL:-{om}}}"'
a_mod_new = f'--model "${{CLAUDE_NEXT_MODEL:-{nm}}}"'
if src.count(a_bin_old) != 1: print(f"  ✗ _bin anchor count {src.count(a_bin_old)}"); sys.exit(1)
if src.count(a_mod_old) != 2: print(f"  ✗ --model anchor count {src.count(a_mod_old)}"); sys.exit(1)
out = src.replace(a_bin_old, a_bin_new, 1).replace(a_mod_old, a_mod_new, 2)
open(p, "w").write(out)
# self-assert the ARTIFACT, not the intent
chk = open(p).read()
ok = chk.count(a_bin_new) == 1 and chk.count(a_mod_new) == 2 \
     and chk.count(a_bin_old) == 0 and chk.count(a_mod_old) == 0
print(f"  → _bin    ~/{od} → ~/{nd}")
print(f"  → --model {om} → {nm}  (2 sites)")
if not ok: print("  ✗ post-write assertion FAILED"); sys.exit(1)
# the containment export must still be present and untouched
if "export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1" not in chk:
    print("  ✗ SPAWN_DEPTH containment export missing after write"); sys.exit(1)
print("  ✓ SPAWN_DEPTH=1 containment export intact")
sys.exit(0)
PY
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "✗ edit failed — restoring backup." >&2; cp -a "$BAK/zshrc" "$ZSHRC"; exit 1
fi

# ---------- syntax-check the edited rc before anyone sources it --------------------------------
if zsh -n "$ZSHRC" 2>/dev/null; then
  echo "  ✓ zsh -n clean"
else
  echo "  ✗ zsh -n FAILED on the edited rc — restoring backup." >&2
  cp -a "$BAK/zshrc" "$ZSHRC"; exit 1
fi

echo
echo "✓ ACTIVATED — new shells launch 2.1.280 + $NEW_MODEL @ effort high, auto mode, depth 1."
echo "  running shells keep the old body (a zshrc edit is not a shell flip)"
echo "  rollback:  bash ${BASH_SOURCE[0]} --undo      (~/$OLD_DIR left installed)"
