#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 14-land-pipeline-v2  —  activate the WHOLE v2 landing net in ONE operator command
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: idempotent, self-verifying. (1) symlink postland-verify.sh + deploy-live.sh into the live
#   ~/.claude/scripts/ layer (per-file topology — both plists exec $HOME/.claude/scripts/<name>).
#   (2) load com.claude.postland-verify (the VERIFIER: every 300s, full corpus in a fresh worktree,
#   background band, stamps GREEN/RED/CUT/HUNG, auto-reverts a bisected red). (3) load
#   com.claude.deploy-live (the DEPLOY lane: every 600s, advance the live layer to the newest
#   GREEN-stamped commit, then run the host-suite partition against it). (4) kick one verifier run
#   and print the deploy lane's dry-run decision, so the operator SEES the net working, not a claim.
# WHY ONE SCRIPT: the two jobs are one mechanism. The verifier is the only party that can make the
#   full-suite claim; the deploy lane is fail-closed ON that claim. Loading either alone is a
#   degraded state that looks activated — verifier-only never deploys, deploy-only never advances.
#   SUPERSEDES 09-postland-verify-activate.sh (that plist is loaded here too — do not run both).
# WHY C10 (agent stages; operator loads): loading a launchd job IS an activation, and agents are
#   classifier-blocked from it. Kill switches after load: POSTLAND_VERIFY=off · POSTLAND_AUTOREVERT=off
#   · SHIP_LAND_LANE=v1 · launchctl bootout of either label. Mark done: touch <this file>.done
# WHAT IT ARMS (absence-is-loud, R9): `cc-blockers` gains VERIFIER-INERT (stamps stale while lands
#   keep arriving) and DEPLOY-LAG (a green cursor >60 min ahead of the deployed HEAD). Until this
#   script runs, VERIFIER-INERT reads "net never activated" and names this file.
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
UID_="$(id -u)"
LOGDIR="$HOME/.claude/autonomy/postland"

echo "== 14-land-pipeline-v2 =="
for pair in "postland-verify.sh:com.claude.postland-verify" "deploy-live.sh:com.claude.deploy-live"; do
  src="$REPO/scripts/${pair%%:*}"
  [ -f "$src" ] || { echo "✗ missing in checkout: $src (is the checkout on a trunk with LAND_PIPELINE_V2?)" >&2; exit 1; }
  [ -f "$REPO/launchd/${pair##*:}.plist" ] || { echo "✗ missing plist: $REPO/launchd/${pair##*:}.plist" >&2; exit 1; }
done

echo "Will do: [0] $REPO/scripts/postland-verify.sh --selftest (proves both verdict paths, side-effect-free)"
echo "         [1] symlink postland-verify.sh + deploy-live.sh → ~/.claude/scripts/"
echo "         [2] load com.claude.postland-verify  (StartInterval 300, RunAtLoad=false)"
echo "         [3] load com.claude.deploy-live      (StartInterval 600, RunAtLoad=true)"
echo "         [4] kick one verifier run + print the deploy lane's dry-run decision"

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/14-land-pipeline-v2-activate.sh"
  exit 0
fi

echo "[0] selftest"
bash "$REPO/scripts/postland-verify.sh" --selftest || { echo "✗ selftest RED — NOT activating" >&2; exit 1; }

echo "[1] live symlinks"
mkdir -p "$HOME/.claude/scripts" "$LOGDIR"    # Standard*Path dirs must exist before launchd starts the job
for s in postland-verify.sh deploy-live.sh; do
  src="$REPO/scripts/$s"; dest="$HOME/.claude/scripts/$s"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then echo "  = $dest (already linked)"
  elif ln -sfn "$src" "$dest"; then echo "  → $dest"
  else echo "  ✗ failed: $dest" >&2; exit 1; fi
done

# A label sitting in launchd's DISABLED database refuses bootstrap with a bare "Bootstrap failed:
# 5: Input/output error" that names neither cause nor cure (legacy `launchctl unload -w` writes that
# bit; `bootout` does not clear it). `enable` clears it and is a no-op when unset. Deliberately NOT
# in the && chain: bootstrap is the verdict, and a benign enable failure must not mask a load that
# would have worked. bootout-if-loaded first makes the whole step idempotent.
load_job() { # <label>
  local label="$1" plist="$REPO/launchd/$1.plist"
  echo "  ── $label"
  launchctl enable "gui/$UID_/$label" || echo "     (enable rc=$? — continuing; the bootstrap below is the verdict)"
  launchctl bootout "gui/$UID_/$label" 2>/dev/null || true
  if cp "$plist" "$HOME/Library/LaunchAgents/$label.plist" \
       && plutil -lint "$HOME/Library/LaunchAgents/$label.plist" >/dev/null \
       && launchctl bootstrap "gui/$UID_" "$HOME/Library/LaunchAgents/$label.plist"; then
    echo "     ✓ loaded"
  else
    echo "     ✗ load failed — inspect above" >&2; return 1
  fi
}
echo "[2] load the verifier"; load_job com.claude.postland-verify || exit 1
echo "[3] load the deploy lane"; load_job com.claude.deploy-live   || exit 1

# `launchctl print gui/$UID/<label>`, NOT `launchctl list | grep`: print resolves the label in THIS
# domain and fails non-zero when it is absent, whereas a grep over list can match a substring of an
# unrelated label and reads a job that exited as present. Verified 2026-07-28: all 13 com.claude.*
# labels sit in the disabled database (`launchctl print-disabled gui/501`), which is why the enable
# above is load-bearing — without it bootstrap fails EIO and this check is the thing that catches it.
echo "== verify (launchctl print — resolves the label in this domain, not a substring match) =="
rc=0
for label in com.claude.postland-verify com.claude.deploy-live; do
  if launchctl print "gui/$UID_/$label" >/dev/null 2>&1; then echo "  ✓ $label loaded"
  else echo "  ✗ $label does NOT resolve in gui/$UID_ — not loaded" >&2; rc=1; fi
done
[ "$rc" -eq 0 ] || { echo "✗ activation INCOMPLETE — the net is degraded, not live" >&2; exit 1; }

echo "[4] kick one verifier run (bounded by its own singleton lock; abstains in ~1s if already stamped)"
"$HOME/.claude/scripts/postland-verify.sh" --run-if-needed 2>&1 | tail -5 \
  || echo "  (verifier rc=$? — see $LOGDIR/runner.log)"

echo "[4b] deploy lane decision (dry-run — mutates nothing)"
"$HOME/.claude/scripts/deploy-live.sh" --dry-run 2>&1 | sed 's/^/  /' \
  || echo "  (refusal above is EXPECTED until the first GREEN stamp exists — that is the gate working)"

echo "== armed =="
echo "  alarms:    cc-blockers        # VERIFIER-INERT + DEPLOY-LAG now read live disk state"
echo "  stamps:    ls -lt $LOGDIR/stamps | head"
echo "  deploy:    tail -20 $LOGDIR/deploy.log"
echo "  status:    $HOME/.claude/scripts/postland-verify.sh status"
echo "  mark done: touch $HOME/.claude/autonomy/pending-activation/14-land-pipeline-v2-activate.sh.done"
echo "ROLLBACK: launchctl bootout gui/$UID_/com.claude.deploy-live ; launchctl bootout gui/$UID_/com.claude.postland-verify ; rm ~/Library/LaunchAgents/com.claude.{deploy-live,postland-verify}.plist"
