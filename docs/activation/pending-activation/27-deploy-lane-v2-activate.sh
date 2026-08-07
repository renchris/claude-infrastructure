#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 27-deploy-lane-v2  —  break the deploy lane's OWN bootstrap circle by deploying the fixed advancer
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: surgically update TWO files in the shared checkout's working tree to the version on
#   origin/main — scripts/deploy-live.sh and bin/cc-blockers. HEAD is NOT moved, nothing is committed,
#   nothing is stashed, no plist is touched, and no OTHER path is read or written.
#
# WHY THIS IS NEEDED AT ALL — the rebuild has the circle it fixes (DEPLOY_LANE_GROUND_UP.md §2.6c):
#   ~/.claude/scripts/deploy-live.sh is a SYMLINK into the shared checkout's WORKING TREE, so "the
#   live advancer" is whatever that tree holds. The v2 advancer (two-tier target: verified by default,
#   degrading to not-red past a staleness budget) is therefore NOT live merely by being landed. And it
#   cannot become live by the normal path, because:
#       live layer advances  <= deploy-live fast-forwards <= a target ABOVE live HEAD exists
#       a target above live HEAD exists                   <= THE V2 SELECTOR IS LIVE
#   That is a closed loop, and it is the same shape as 26-deploy-gate-unblock's. It must be broken
#   from the DEPLOY side, exactly once, by hand.
#
# WHY BOTH FILES. deploy-live.sh is the actuator; bin/cc-blockers is the alarm that reports the lane's
#   state. They are deployed together deliberately: if the advance is still blocked (see BLOCKER B
#   below), the alarm is the only thing that will TELL you so. Observability must not be gated on the
#   actuation it observes — that coupling is what produced 534 silent refusals over 33 hours.
#
# WHY THE FILES ARE LEFT STAGED, deliberately. `git checkout <ref> -- <path>` updates BOTH the index
#   and the working tree. Do NOT "clean up" by unstaging: an unstaged-but-modified file is a LOCAL
#   MODIFICATION, and `git merge --ff-only` REFUSES to advance over one — which would block the very
#   fast-forward this script exists to enable. Staged (index == worktree == trunk content) is the
#   state that SELF-RESOLVES: when the lane later fast-forwards, git sees the file already matches its
#   target and the merge succeeds, leaving nothing behind. (Mechanism proven 2026-07-31 by
#   26-deploy-gate-unblock, used while the checkout was 119 behind with 4 live writers.)
#
# ⚠️ BLOCKER B IS SEPARATE AND IS NOT FIXED BY THIS SCRIPT. hooks/backup-before-write.sh is modified
#   in the shared checkout AND changed on trunk (16dfe3b5), so `git merge --ff-only` refuses for EVERY
#   writer, gated or not — that, not the stamp gate, is why the layer has had zero HEAD moves since
#   2026-08-05 15:40. This script is path-scoped and does not touch it. After running this, the v2
#   lane will name that file in a dedicated refusal instead of dying on "(dirty tree? diverged?)".
#   Parking it is filed separately as backlog 8fdefffaabf7 — it is a peer session's live WIP.
#
# WHY C10 (agent stages; operator runs). The shared checkout has 4+ live sessions sharing ONE git
#   index, so a sibling's bare `git commit` can sweep a file this script stages. The agent cannot pick
#   a safe moment; you can. Run it when you are not mid-commit elsewhere. Idempotent and re-runnable.
#
# ORDER: run this AFTER the v2 lane has LANDED on origin/main. The script REFUSES otherwise (step 0)
#   — it will not stage a file that does not yet carry the change.
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"

# path:marker pairs. The MARKER is the change's own identifier — content, never a commit count. A
# count answers "how far behind", which is a different question from "is the change there".
PAIRS="scripts/deploy-live.sh:CC_DEPLOY_DEGRADE bin/cc-blockers:deploy-stale"

echo "== 27-deploy-lane-v2 =="
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 \
  || { echo "✗ not a git checkout: $REPO" >&2; exit 1; }

echo "[0] preflight"
git -C "$REPO" fetch origin main >/dev/null 2>&1 \
  || { echo "✗ git fetch origin main FAILED (network? remote?)" >&2; exit 1; }

todo=""
for pair in $PAIRS; do
  rel="${pair%%:*}"; marker="${pair##*:}"
  live="$HOME/.claude/${rel}"

  # (a) the change must EXIST on trunk, verified by CONTENT in the trunk blob.
  #
  #     CAPTURED, NOT PIPED — and that is not style. `git show … | grep -q "$marker"` under the
  #     `set -o pipefail` above reads FALSE **on a match**: grep -q exits at the first hit, git show is
  #     still writing the remaining lines, takes SIGPIPE, exits 141, and pipefail promotes that 141 to
  #     the pipeline's status. Measured on this host while writing 26-deploy-gate-unblock (its lines
  #     54-60) — rc=141 with pipefail, rc=0 without, same command — so the guard refused to deploy a
  #     fix that WAS on trunk. A probe whose verdict inverts on success is worse than no probe.
  blob="$(git -C "$REPO" show "origin/main:$rel" 2>/dev/null || true)"
  case "$blob" in
    *"$marker"*) ;;
    *) echo "✗ origin/main:$rel does not contain $marker — the v2 lane has NOT landed yet." >&2
       echo "  Land it first (project-local /ship), then re-run this script." >&2
       exit 1 ;;
  esac

  # (b) the file must be CLEAN in the shared checkout. A dirty one is a peer session's live WIP and
  #     overwriting it would destroy work this script has no way to attribute or recover.
  dirty="$(git -C "$REPO" status --porcelain -- "$rel" 2>/dev/null)"
  if [ -n "$dirty" ]; then
    echo "✗ $rel is NOT clean in $REPO:" >&2
    printf '    %s\n' "$dirty" >&2
    echo "  That is very likely a peer session's uncommitted work. REFUSING to overwrite it." >&2
    echo "  Resolve that file's state with its owner first; this script never discards local work." >&2
    exit 1
  fi

  # (c) idempotence, checked on the LIVE path (through the symlink) because that is what launchd
  #     actually executes — the question is never "is the repo right".
  if [ -r "$live" ] && grep -q "$marker" "$live" 2>/dev/null; then
    echo "  = $rel already carries $marker live — nothing to do."
  else
    todo="$todo $rel"
  fi
done

if [ -z "${todo# }" ]; then
  echo "  = both files already live. Nothing to do."
  echo "    (mark done: touch $HOME/.claude/autonomy/pending-activation/27-deploy-lane-v2-activate.sh.done)"
  exit 0
fi

BEHIND="$(git -C "$REPO" rev-list --count HEAD..origin/main 2>/dev/null || echo '?')"
echo "  checkout HEAD is $BEHIND commit(s) behind origin/main (context only — not the gate)"
echo "Will do: [1] git -C $REPO checkout origin/main --$todo   (HEAD unmoved; leaves them STAGED, by design)"
echo "         [2] verify each LIVE symlink now resolves to a file carrying its marker"
echo "         [3] bash -n each deployed file, then print what happens next"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/27-deploy-lane-v2-activate.sh"
  exit 0
fi

echo "[1] surgical checkout"
# shellcheck disable=SC2086  # $todo is a space-separated path list we built ourselves
git -C "$REPO" checkout origin/main -- $todo \
  || { echo "✗ checkout FAILED — nothing changed" >&2; exit 1; }

echo "[2] verify by CONTENT, through the live path"
for pair in $PAIRS; do
  rel="${pair%%:*}"; marker="${pair##*:}"; live="$HOME/.claude/${rel}"
  [ -r "$live" ] || { echo "✗ $live is not readable — is the per-file symlink present?" >&2; exit 1; }
  grep -q "$marker" "$live" \
    || { echo "✗ $live still lacks $marker — the symlink may point elsewhere:" >&2
         ls -l "$live" >&2; exit 1; }
  # Cheap proof the deployed file is not merely present but RUNNABLE. A syntax error here would take
  # the advancer or the board out entirely, and a dead sensor reads to its consumers as "all clear".
  /bin/bash -n "$live" 2>/dev/null \
    || { echo "✗ bash -n FAILED on $live — investigate before the next tick" >&2; exit 1; }
  echo "  ✓ $rel live and bash -n clean"
done

echo "== what happens next =="
echo "  • com.claude.deploy-live ticks every 600s. Its NEXT run uses the two-tier selector: it will"
echo "    look for a GREEN descendant of live HEAD first, and past the staleness budget"
echo "    (CC_DEPLOY_MAX_LAG_COMMITS=25 / CC_DEPLOY_MAX_LAG_HOURS=6) fall back to the newest"
echo "    not-RED commit above live HEAD, under a loud banner and a page."
echo "  • It will then meet BLOCKER B — the dirty hooks/backup-before-write.sh — and refuse with that"
echo "    file NAMED, rather than dying on a guess. Park that file (backlog 8fdefffaabf7) to finish."
echo "  • cc-blockers now renders a deploy-stale / NOT-ADVANCING row, so the lane's state is on the"
echo "    board whether or not the advance succeeds."
echo "  • Neither launchd job was modified. No plist was touched (C10 intact)."
echo "== confirm it worked (not before ~10 min) =="
echo "  cc-blockers                                        # expect a deploy-stale NOT-ADVANCING row"
echo "  tail -20 $HOME/.claude/autonomy/postland/deploy.log  # expect a NEW refusal shape, not 'ROLL BACK'"
echo "  git -C $REPO rev-list --count HEAD..origin/main     # should fall once blocker B is parked"
echo "  mark done: touch $HOME/.claude/autonomy/pending-activation/27-deploy-lane-v2-activate.sh.done"
echo "ROLLBACK: git -C $REPO checkout HEAD --$todo   # restores the checkout's own versions, unstages"
