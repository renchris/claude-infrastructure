#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 05-ship-rail-push-allow  —  narrow the git push:* ask so autonomous ship stops stranding (T-P15-4)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT IT FIXES: `defaultMode:auto` still HALTS on the `ask` array, and `Bash(git push:*)` sits there —
#   so a MODEL-issued land push (`git push origin HEAD:<trunk>`, commands/ship.md:43) strands with no
#   human to approve. (ship-land.sh's own push escapes this — it runs as a SUBPROCESS, a non-Bash-tool
#   path; that resolved audit uncertainty U2.) `hooks/ship-rail-push-allow.sh` is a PreToolUse(Bash)
#   hook that auto-allows EXACTLY the non-force land shape `git push origin HEAD:<branch>` and defers
#   everything else (force / other-remote / bare push / compound → the git push:* ask + force deny
#   stay in force). Built + tested (8/8 bats, full suite 733/733, shellcheck clean), landed 9d2bf16.
#
# C10: this stages the wiring; YOU (operator) run it — it registers the hook in the 5 settings.json
#   files that govern the agent's own permissions, so an agent must never apply it. This is also
#   Operator decision point #4 in ORCHESTRATOR_DESK_24X7_PLAN.md ("sanction the ship-rail-only push
#   allow"). Running the activation IS the sanction.
#
#   The activation is a landed, IDEMPOTENT, dry-run-first, jq-structural script (backs up every
#   settings.json, validates JSON before writing). Authoritative runbook + safety model:
#     docs/SHIP-RAIL-PUSH-ALLOW-ACTIVATION.md
#
# Convention: after you complete activation, mark done:
#     touch ~/.claude/autonomy/pending-activation/05-ship-rail-push-allow-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
ACT="$REPO/docs/activation/ship-rail-push-activate.sh"
RUNBOOK="$REPO/docs/SHIP-RAIL-PUSH-ALLOW-ACTIVATION.md"

echo "== 05-ship-rail-push-allow =="
echo "Pre: ensure the shared checkout has the landed commit (9d2bf16):"
echo "    git -C $REPO pull --ff-only"
echo "Step 1 (DRY-RUN — writes nothing; validates the jq transform vs all 5 live settings.json):"
echo "    $ACT"
echo "Step 2 (APPLY — backs up each settings.json *.bak-<ts>, transforms, validates, mv; idempotent):"
echo "    $ACT --apply"
echo "Verify:"
echo "    printf '{\"tool_input\":{\"command\":\"git push origin HEAD:main\"}}' | ~/.claude/hooks/ship-rail-push-allow.sh   # → permissionDecision:allow"
echo "    printf '{\"tool_input\":{\"command\":\"git push --force origin HEAD:main\"}}' | ~/.claude/hooks/ship-rail-push-allow.sh   # → (no output = deferred to deny/ask)"
echo "Rollback: the --apply run prints exact mv commands to restore each *.bak-<ts>; or set"
echo "    SHIP_RAIL_PUSH_ALLOW_DISABLED=1 in the environment to disable the hook without unwiring."
echo "Runbook (authoritative): $RUNBOOK"
echo
