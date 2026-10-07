#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# 50-haiku55-cc293-activate — repoint the everyday launcher's binary 2.1.284 → 2.1.293
# ═══════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: ONE edit to ~/.zshrc inside claude(), idempotent, reversible with --undo, one timestamped
#   backup taken before the write:
#     _bin pin   ~/.claude-284 → ~/.claude-293     (2.1.293 installed with npm --prefix)
#   The launcher's --model default (claude-opus-5-5) and --effort default (high) are UNCHANGED:
#   this is a binary advance, not a lead-model change.
#
# WHY THE BINARY: claude-haiku-5-5 needs CC 2.1.293. Measured 2026-10-07 with cc-model-registered
#   (byte scan beside the claude-opus-5 positive control): 2.1.284 holds the id 0 times, 2.1.291 0,
#   2.1.292 0, 2.1.293 21. The fifth model release in a row that is also a binary event.
#
# THIS MOVE ALSO MOVES A MODEL, WITH NO CONFIG EDIT: on 2.1.293 the alias `haiku` and the small/fast
#   helper model resolve to claude-haiku-5-5 on first party (2.1.284: claude-haiku-4-5). So from the
#   first new shell, every `model: "haiku"` spawn (the retrieval role) and every helper call (titles,
#   summaries, WebFetch page summaries) runs Haiku 5.5. Measured live on 2.1.293: an Opus 5.5 lead at
#   --effort high spawning Explore with model "haiku" was served claude-haiku-5-5 at effort high (the
#   subagent inherits the lead's rung; Haiku 4.5 took no effort at all). To hold retrieval on Haiku
#   4.5 instead, export ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5 in the launcher.
#
# WHY NOW, against the ">=7 d since publish" churn bar that 2.1.293 fails (published
#   2026-10-07T17:18Z): the bar is a proxy for field evidence, and the gate IS the evidence. Operator
#   mandate: "we ALWAYS upgrade immediately to a new model IF all our ways of working continue to
#   work". holds.md also retired every target below 2.1.291 (2.1.288-2.1.290 could lose a session's
#   last messages on quit), and 2.1.293 is the last fix in the band's background-job cluster.
#
#     scripts/cc-upgrade-gate.sh ~/.claude-293/node_modules/.bin/claude claude-haiku-5-5 next next2 next4
#       → 14 pass · 0 fail · 1 skip — VERDICT: GREEN
#     scripts/cc-upgrade-gate.sh ~/.claude-293/node_modules/.bin/claude claude-opus-5-5  next next2 next4
#       → 14 pass · 0 fail · 1 skip — VERDICT: GREEN
#
#   THREE accounts, not four: next3 was logged out at gate time (the 4-account runs read RED 13/1/1
#   on #02 only, identically under Opus 5.5, which next3 is entitled to). next3's Haiku 5.5
#   entitlement is UNPROVEN until it is logged in and re-gated. The one skip is #14 authstore.
#   Beyond the gate, probed live on 2.1.293: --resume through the symlinked ~/.claude-next/projects
#   (upstream #98899) recalls the session; Write under auto in -p works and backup-before-write fires.
#   Evidence, the 2.1.285-2.1.293 CHANGELOG audit and its referee: docs/research/haiku55-upgrade-2026-10-07/.
#
# KNOWN CHANGES YOU TAKE WITH THIS BINARY (audit, none a blocker):
#   · Headless sessions (-p, SDK) now kill a backgrounded Bash command after 10 min (one-shot -p) or
#     30 min (streaming) unless the call passes its own timeout. Interactive panes are exempt.
#   · Haiku 5.5 is NOT covered by the binary's native read-before-write guard (Haiku 4.5 was). Our
#     backup-before-write hook and read-before-write shim are the only guard for a Haiku writer.
#   · A per-agent token budget exists behind a server flag (off on all four accounts today, advisory
#     only). CLAUDE_CODE_RIPPLING_TULIP=0 in settings env switches it off for good; that edit is a
#     settings migration and is the operator's.
#   · The revoked-login error text changed in 2.1.287; hooks/stop-failure-marker.sh is updated in the
#     same branch as this script.
#
# THE #68619 CONTAINMENT LEVER SURVIVES. Nothing in 2.1.285-2.1.293 restores a spawn cap; the depth
#   check is still inclusive (gate #15 PASS). `export CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` stays
#   load-bearing; this script asserts it is intact.
#
# WHAT THIS SCRIPT DELIBERATELY DOES NOT DO: the SSOT flip in model-config.yaml (haiku_latest, the
#   retrieval role, effort keys). claude-haiku-5-5 is parked in versions.haiku_staged until this
#   script has run. ORDER: binary first, SSOT second.
#
# A ZSHRC EDIT IS NOT A SHELL FLIP: running shells keep the old launcher body and stay on 2.1.284
#   until they are recycled. On that split fleet `haiku` means 4.5 in old panes and 5.5 in new ones.
#
# ROLLBACK: `bash 50-haiku55-cc293-activate.sh --undo`. ~/.claude-284 stays installed as the floor.
#
# RUN:  bash ~/.claude/autonomy/pending-activation/50-haiku55-cc293-activate.sh --confirm 2.1.293
#       (a bare run is a dry run: preflight only, nothing written)
# ═══════════════════════════════════════════════════════════════════════════════════════════════
set -uo pipefail

ZSHRC="$HOME/.zshrc"
OLD_DIR=".claude-284"; NEW_DIR=".claude-293"; NEW_VER="2.1.293"
NEW_BIN="$HOME/$NEW_DIR/node_modules/.bin/claude"
SMOKE_MODELS="claude-haiku-5-5 claude-opus-5-5"
BAK="$HOME/.claude/autonomy/backups/haiku55-cc293-$(date -u +%Y%m%dT%H%M%SZ)"

CONFIRM_TARGET=""
if [ "${1:-}" = "--confirm" ]; then CONFIRM_TARGET="${2:-}"; fi

# ---------- --undo -----------------------------------------------------------------------------
if [ "${1:-}" = "--undo" ]; then
  # shellcheck disable=SC2012  # backup dirs are timestamps this script names; ls -1d sorts them
  last="$(ls -1d "$HOME"/.claude/autonomy/backups/haiku55-cc293-* 2>/dev/null | tail -1)"
  [ -n "$last" ] && [ -f "$last/zshrc" ] || { echo "✗ no backup to undo from" >&2; exit 1; }
  cp -a "$last/zshrc" "$ZSHRC" || exit 1
  echo "✓ restored ~/.zshrc from $last"
  echo "  open a NEW shell (or: source ~/.zshrc) — running shells keep the old body either way."
  exit 0
fi

fail=0
echo "== 50-haiku55-cc293-activate =="

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
if [ "$CONFIRM_TARGET" != "$NEW_VER" ]; then
  echo; echo "DRY RUN. Re-run with --confirm $NEW_VER to write."; exit 0
fi

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
print("  → _bin ~/.claude-284 → ~/.claude-293")
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
