#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# 47-sonnet55-cc284-activate — repoint the everyday launcher's binary 2.1.280 → 2.1.284
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: ONE edit to ~/.zshrc inside claude(), idempotent, reversible with --undo, one timestamped
#   backup taken before the write:
#     _bin pin   ~/.claude-280 → ~/.claude-284     (2.1.284 installed with npm --prefix)
#   The launcher's --model default (claude-opus-5-5) and --effort default (high) are UNCHANGED:
#   this is a binary advance, not a lead-model change.
#
# WHY THE BINARY: claude-sonnet-5-5 needs CC 2.1.284. Measured 2026-09-28 with a byte scan of each
#   claude.exe, beside the claude-opus-5 positive control: 2.1.280 holds the id 0 times, 2.1.284 holds
#   it. That makes this the fourth model release in a row that is also a binary event (Opus 5 → 2.1.219,
#   Fable 5.1 → 2.1.253, Opus 5.5 → 2.1.280).
#
# WHY NOW, against the ">=7 d since publish" churn bar that 2.1.284 fails (published
#   2026-09-28T17:11Z): the bar is a proxy for field evidence, and the gate IS the evidence. Operator
#   mandate (cc-upgrade-gate): "we ALWAYS upgrade immediately to a new model IF all our ways of working
#   continue to work". The gate ran once per model the fleet will run on the new binary: the lead model
#   as well as the new one, because the lead moves to 2.1.284 too.
#
#     scripts/cc-upgrade-gate.sh ~/.claude-284/node_modules/.bin/claude claude-sonnet-5-5 next next2 next3 next4
#       → 14 pass · 0 fail · 1 skip — VERDICT: GREEN
#     scripts/cc-upgrade-gate.sh ~/.claude-284/node_modules/.bin/claude claude-opus-5-5   next next2 next3 next4
#       → 14 pass · 0 fail · 1 skip — VERDICT: GREEN
#
#   Both runs covered registration without demotion, entitlement on all four accounts, auto mode driving
#   a real tool turn, the effort ladder, the launcher effect-read, SPAWN_DEPTH containment on both
#   surfaces (#6) plus a flat topology (#15), a teammate spawn, a Dynamic Workflow, a subagent,
#   lifecycle hooks, permission non-block, resume routing and MCP. The one skip is #14 authstore
#   (unchanged since 2.1.220, known-open upstream, not an upgrade blocker).
#   Evidence and the 2.1.281-2.1.284 CHANGELOG audit: docs/research/sonnet55-utilization-2026-09-28/.
#
# THE #68619 CONTAINMENT LEVER SURVIVES. Nothing in 2.1.281-2.1.284 restores a spawn cap, and every
#   held-open issue from the 2.1.280 audit is still open or was closed as stale, not fixed. So
#   `export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` stays load-bearing; this script asserts it is intact.
#
# WHAT THIS SCRIPT DELIBERATELY DOES NOT DO: the SSOT flip in model-config.yaml (sonnet_latest and the
#   role/effort keys). ~/.claude/model-config.yaml is a symlink into the shared checkout, so that half
#   lands through a worktree + /ship + deploy-live. ORDER: binary first, SSOT second, so no config
#   ever names claude-sonnet-5-5 while the launcher's binary cannot dispatch it.
#
# EFFORT — measured, not assumed. The 2.1.284 model catalog gives BOTH claude-sonnet-5-5 and
#   claude-opus-5-5 default_effort "medium". The launcher passes --effort high explicitly
#   (`_eff="${CLAUDE_EFFORT:-${CLAUDE_OPUS5_EFFORT:-high}}"`), so a lead does not drop a rung.
#
# A ZSHRC EDIT IS NOT A SHELL FLIP: running shells keep the old launcher body and stay on 2.1.280
#   until they are recycled. The SSOT routes a --recycle by the family ALIAS (`opus`), which both
#   builds resolve, so the split fleet is safe (model-upgrade § Case A step 0b).
#
# ROLLBACK: `bash 47-sonnet55-cc284-activate.sh --undo`. ~/.claude-280 stays installed as the floor.
#
# RUN:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/47-sonnet55-cc284-activate.sh
# ═══════════════════════════════════════════════════════════════════════════════════════════════
set -uo pipefail

ZSHRC="$HOME/.zshrc"
OLD_DIR=".claude-280"; NEW_DIR=".claude-284"; NEW_VER="2.1.284"
NEW_BIN="$HOME/$NEW_DIR/node_modules/.bin/claude"
SMOKE_MODELS="claude-sonnet-5-5 claude-opus-5-5"
BAK="$HOME/.claude/autonomy/backups/sonnet55-cc284-$(date -u +%Y%m%dT%H%M%SZ)"

# ---------- --undo -----------------------------------------------------------------------------
if [ "${1:-}" = "--undo" ]; then
  # shellcheck disable=SC2012  # backup dirs are timestamps this script names; ls -1d sorts them
  last="$(ls -1d "$HOME"/.claude/autonomy/backups/sonnet55-cc284-* 2>/dev/null | tail -1)"
  [ -n "$last" ] && [ -f "$last/zshrc" ] || { echo "✗ no backup to undo from" >&2; exit 1; }
  cp -a "$last/zshrc" "$ZSHRC" || exit 1
  echo "✓ restored ~/.zshrc from $last"
  echo "  open a NEW shell (or: source ~/.zshrc) — running shells keep the old body either way."
  exit 0
fi

fail=0
echo "== 47-sonnet55-cc284-activate =="

# ---------- preflight (fail-closed) ------------------------------------------------------------
vnew="$(node -e "console.log(require('$HOME/$NEW_DIR/node_modules/@anthropic-ai/claude-code/package.json').version)" 2>/dev/null)"
if [ "$vnew" = "$NEW_VER" ]; then
  echo "  ✓ $NEW_DIR present and is $NEW_VER"
else
  echo "  ✗ $NEW_DIR is '${vnew:-missing}' (need exactly $NEW_VER)" >&2
  echo "    npm install --prefix ~/$NEW_DIR @anthropic-ai/claude-code@$NEW_VER" >&2
  fail=1
fi
[ -x "$NEW_BIN" ] || { echo "  ✗ not executable: $NEW_BIN" >&2; fail=1; }
[ -x "$HOME/$OLD_DIR/node_modules/.bin/claude" ] \
  || { echo "  ✗ rollback floor missing: ~/$OLD_DIR — refusing to advance with no way back" >&2; fail=1; }

# each model the fleet will run on the new binary must return a verified completion (modelUsage proof)
if [ "$fail" -eq 0 ]; then
  for m in $SMOKE_MODELS; do
    smoke="$("$NEW_BIN" --model "$m" --print --output-format json "Reply with exactly: ok" 2>/dev/null)"
    if printf '%s' "$smoke" | M="$m" python3 -c 'import sys,json,os;o=json.load(sys.stdin);sys.exit(0 if os.environ["M"] in (o.get("modelUsage") or {}) and not o.get("is_error") else 1)' 2>/dev/null; then
      echo "  ✓ $m reachable + entitled on $NEW_VER (modelUsage carries it)"
    else
      echo "  ✗ $m did not return a verified completion on $NEW_VER" >&2; fail=1
    fi
  done
fi

a_old="local _bin=\"\$HOME/$OLD_DIR/node_modules/.bin/claude\""
a_new="local _bin=\"\$HOME/$NEW_DIR/node_modules/.bin/claude\""
n_old=$(grep -cF -- "$a_old" "$ZSHRC" 2>/dev/null || true)
n_new=$(grep -cF -- "$a_new" "$ZSHRC" 2>/dev/null || true)
if [ "$n_new" -ge 1 ] && [ "$n_old" -eq 0 ]; then
  echo "  = already activated (binary $NEW_DIR) — nothing to do"; exit 0
fi
[ "$n_old" -eq 1 ] || { echo "  ✗ expected exactly 1 _bin anchor for $OLD_DIR, found $n_old" >&2; fail=1; }

[ "$fail" -eq 0 ] || { echo "✗ preflight failed — nothing written." >&2; exit 1; }
[ "${CONFIRM:-0}" = "1" ] || { echo; echo "DRY RUN. Re-run with CONFIRM=1 to write."; exit 0; }

# ---------- backup, then edit ------------------------------------------------------------------
mkdir -p "$BAK" && cp -a "$ZSHRC" "$BAK/zshrc" || { echo "✗ backup failed — aborting." >&2; exit 1; }
echo "  ✓ backup: $BAK/zshrc"

ZSHRC="$ZSHRC" AO="$a_old" AN="$a_new" python3 <<'PY'
import os, sys
p, ao, an = os.environ["ZSHRC"], os.environ["AO"], os.environ["AN"]
src = open(p).read()
if src.count(ao) != 1: print(f"  ✗ _bin anchor count {src.count(ao)}"); sys.exit(1)
open(p, "w").write(src.replace(ao, an, 1))
chk = open(p).read()
if not (chk.count(an) == 1 and chk.count(ao) == 0): print("  ✗ post-write assertion FAILED"); sys.exit(1)
print("  → _bin ~/.claude-280 → ~/.claude-284")
if "export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1" not in chk:
    print("  ✗ SPAWN_DEPTH containment export missing after write"); sys.exit(1)
print("  ✓ SPAWN_DEPTH=1 containment export intact")
PY
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "✗ edit failed — restoring backup." >&2; cp -a "$BAK/zshrc" "$ZSHRC"; exit 1
fi

if zsh -n "$ZSHRC" 2>/dev/null; then
  echo "  ✓ zsh -n clean"
else
  echo "  ✗ zsh -n FAILED on the edited rc — restoring backup." >&2
  cp -a "$BAK/zshrc" "$ZSHRC"; exit 1
fi

# the resolver every other launch path reads must now agree with the launcher
if resolved="$("$HOME/.claude/bin/cc-claude-bin" 2>/dev/null)"; then
  case "$resolved" in
    *"/$NEW_DIR/"*) echo "  ✓ bin/cc-claude-bin resolves $resolved" ;;
    *) echo "  ⚠ bin/cc-claude-bin resolves $resolved, not $NEW_DIR — check its source of truth" >&2 ;;
  esac
fi

echo
echo "✓ ACTIVATED — new shells launch $NEW_VER + claude-opus-5-5 @ effort high, auto mode, depth 1."
echo "  running shells keep the old body (a zshrc edit is not a shell flip)"
echo "  rollback:  bash ${BASH_SOURCE[0]} --undo      (~/$OLD_DIR left installed)"
