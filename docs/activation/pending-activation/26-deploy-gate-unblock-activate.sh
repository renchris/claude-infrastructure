#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 26-deploy-gate-unblock  —  break the deploy-gate BOOTSTRAP CIRCLE by deploying the verifier fix
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: surgically update ONE file in the shared checkout's working tree —
#   scripts/postland-verify.sh — to the version on origin/main. HEAD is NOT moved, nothing is
#   committed, nothing is stashed, no plist is touched.
#
# WHY THIS IS NEEDED AT ALL (the circle, measured 2026-07-31 — docs/plans/DEPLOY_GATE_CONVERGENCE.md §7):
#   ~/.claude/scripts/postland-verify.sh is a SYMLINK into the shared checkout's WORKING TREE:
#       ~/.claude/scripts/postland-verify.sh -> ~/Development/claude-infrastructure/scripts/postland-verify.sh
#   So "the live verifier" is whatever that working tree holds — and it is 122 commits behind trunk.
#   The fix that makes the retry ladder able to render a verdict (RETRY_QOS: run the re-run in the
#   UTILITY band instead of the corpus's PRI-4 background clamp) is therefore NOT live merely by
#   being landed. And it cannot become live by the normal path, because:
#       live layer advances  ⇐ deploy-live fast-forwards  ⇐ a GREEN stamp exists
#       a GREEN stamp exists ⇐ the ladder can render a verdict ⇐ THE FIX IS LIVE
#   That is a closed loop. It must be broken from the DEPLOY side, exactly once, by hand.
#   (Repo precedent: the same one-file mechanism is documented in §4 of that plan and was used
#   2026-07-31 to land a desktop-leak fix while the checkout was 119 behind with 4 live writers.)
#
# WHY THE FILE IS LEFT STAGED, deliberately. `git checkout <ref> -- <path>` updates BOTH the index
#   and the working tree. Do NOT "clean up" by unstaging it: an unstaged-but-modified file is a LOCAL
#   MODIFICATION, and `git merge --ff-only` REFUSES to advance over one — which would block the very
#   fast-forward this script exists to enable. Staged (index == worktree == trunk content) is the
#   state that SELF-RESOLVES: when deploy-live later fast-forwards, git sees the file already matches
#   its target and the merge succeeds, leaving nothing behind.
#
# WHY C10 (agent stages; operator runs). The shared checkout has 4+ live sessions writing in it and
#   they share ONE git index, so a sibling's bare `git commit` can sweep a file this script stages.
#   The agent cannot pick a safe moment; you can. Run it when you are not mid-commit elsewhere.
#   It is idempotent and re-runnable.
#
# ORDER: run this AFTER the fix has LANDED on origin/main. The script REFUSES otherwise (step 0) —
#   it will not stage a file that does not yet carry the fix.
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
REL="scripts/postland-verify.sh"
MARKER="RETRY_QOS"                        # the fix's own identifier — content, never a commit count
LIVE="$HOME/.claude/scripts/postland-verify.sh"

echo "== 26-deploy-gate-unblock =="
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "✗ not a git checkout: $REPO" >&2; exit 1; }

echo "[0] preflight"
git -C "$REPO" fetch origin main >/dev/null 2>&1 \
  || { echo "✗ git fetch origin main FAILED (network? remote?)" >&2; exit 1; }

# (a) the fix must EXIST on trunk. Verified by CONTENT in the trunk blob, never by a commit count —
#     a count answers "how far behind", which is a different question from "is the fix there".
if ! git -C "$REPO" show "origin/main:$REL" 2>/dev/null | grep -q "$MARKER"; then
  echo "✗ origin/main:$REL does not contain $MARKER — the fix has NOT landed yet." >&2
  echo "  Land it first (project-local /ship), then re-run this script." >&2
  exit 1
fi

# (b) the file must be CLEAN in the shared checkout. A dirty one is a peer session's live WIP and
#     overwriting it would destroy work this script has no way to attribute or recover.
DIRTY="$(git -C "$REPO" status --porcelain -- "$REL" 2>/dev/null)"
if [ -n "$DIRTY" ]; then
  echo "✗ $REL is NOT clean in $REPO:" >&2
  printf '    %s\n' "$DIRTY" >&2
  echo "  That is very likely a peer session's uncommitted work. REFUSING to overwrite it." >&2
  echo "  Resolve that file's state with its owner first; this script never discards local work." >&2
  exit 1
fi

# (c) idempotence: already deployed ⇒ nothing to do. Checked on the LIVE path (through the symlink),
#     because that is what launchd actually executes — the question is never "is the repo right".
if [ -r "$LIVE" ] && grep -q "$MARKER" "$LIVE" 2>/dev/null; then
  echo "  = the live verifier already carries $MARKER — nothing to do."
  echo "    (mark done: touch $HOME/.claude/autonomy/pending-activation/26-deploy-gate-unblock-activate.sh.done)"
  exit 0
fi

BEHIND="$(git -C "$REPO" rev-list --count HEAD..origin/main 2>/dev/null || echo '?')"
echo "  checkout HEAD is $BEHIND commit(s) behind origin/main (context only — not the gate)"
echo "Will do: [1] git -C $REPO checkout origin/main -- $REL   (HEAD unmoved; leaves it STAGED, by design)"
echo "         [2] verify the LIVE symlink now resolves to a file containing $MARKER"
echo "         [3] print what happens next, and how to confirm it happened"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/26-deploy-gate-unblock-activate.sh"
  exit 0
fi

echo "[1] surgical checkout of $REL"
git -C "$REPO" checkout origin/main -- "$REL" \
  || { echo "✗ checkout FAILED — nothing changed" >&2; exit 1; }

echo "[2] verify by CONTENT, through the live path"
[ -r "$LIVE" ] || { echo "✗ $LIVE is not readable — is the per-file symlink present?" >&2; exit 1; }
grep -q "$MARKER" "$LIVE" \
  || { echo "✗ $LIVE still lacks $MARKER — the symlink may point elsewhere:" >&2
       ls -l "$LIVE" >&2; exit 1; }
echo "  ✓ live verifier now carries $MARKER"

# Cheap proof the deployed file is not merely present but RUNNABLE. A syntax error here would take
# the verifier out entirely, and a dead verifier reads to its consumers as "net not adopted ⇒ trust".
if /bin/bash -n "$LIVE" 2>/dev/null; then echo "  ✓ bash -n clean"
else echo "  ✗ bash -n FAILED on the deployed file — investigate before the next tick" >&2; exit 1; fi

echo "== what happens next =="
echo "  • com.claude.postland-verify ticks every 300s. Its NEXT run uses the fixed ladder, so a"
echo "    machine-pressure kill no longer convicts a suite it cannot fairly judge."
echo "  • When a tree verifies GREEN, com.claude.deploy-live (600s tick) fast-forwards the live"
echo "    layer to it, and THAT fast-forward silently absorbs the file this script staged."
echo "  • Neither job was modified. No plist was touched (C10 intact)."
echo "== confirm it worked (not before ~10 min) =="
echo "  $LIVE status                     # last-green now renders its tree-keyed stamp + verdict"
echo "  tail -5 ~/.claude/autonomy/postland/runner.log"
echo "  ls -t ~/.claude/autonomy/postland/stamps/*.json | head -1 | xargs cat   # look for suites + verdict"
echo "  git -C $REPO rev-list --count HEAD..origin/main   # should start falling once a green lands"
echo "  mark done: touch $HOME/.claude/autonomy/pending-activation/26-deploy-gate-unblock-activate.sh.done"
echo "ROLLBACK: git -C $REPO checkout HEAD -- $REL   # restores the checkout's own version, unstages"
