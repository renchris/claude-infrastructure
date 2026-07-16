#!/bin/bash
# wiring-all.sh v2 — THE consolidated C10 activation bundle. RUN BY THE HUMAN'S HAND, NEVER THE AGENT.
#
# Supersedes v1 (never-wait L1..L4 · reaper birth-grace · comms F1..F5) and ADDS the Track-B gaps:
#   B1-a cc-respawn (spawn-boundary GO as machinery)      B1-b cc-route (live-read model/effort routing)
#   B1-d lr-reset-poller (limit-park re-fire; install + the ruled AUTOFIRE flip)
#   B1-c never-stuck-gate (the systematic invariant — wire it onto the supervisor sweep)
# plus the cc-teardown permission hand-step and D2/P8 effect-checks.
#
# WHAT THIS SCRIPT DOES (idempotent · self-testing · re-runnable):
#   1. VERIFIES every gate + selftest read-only — refuses to proceed on any red (a green gate is the go).
#   2. Creates SYMLINKS (~/.claude/bin tools · the limit-recover mirror → repo) + the cc-roles map.
#   3. EFFECT-CHECKS its own work (every symlink resolves into the repo; launchd/P8 state reported).
#   4. PRINTS every launchd/hook/recipe template for YOU to install.
# WHAT IT NEVER DOES (the C10 line): load launchd · start a daemon · edit a hook/exit-recipe/supervisor
# in place · touch permission settings. Those are your literal hand — the templates below.
#
# Tracked master: docs/activation/wiring-all.sh (this repo). Runbooks: docs/{NEVER-WAIT,REAPER-SAFETY,
# COMMS-SAFETY,D2-RUNTIME}-ACTIVATION.md. Rollback: the final template block.
set -uo pipefail

REPO="${REPO:-$HOME/Development/claude-infrastructure}"
BIN="$HOME/.claude/bin"
DESK_UUID="${DESK_UUID:-1EB2C679-625D-4740-9355-A8DB4D21F2D4}"   # trackb-era desk pane; rebind on a NON-in-place restart
FAILS=0
echo "== wiring-all v2 ==  repo=$REPO  bindir=$BIN  ($(git -C "$REPO" log --oneline -1 2>/dev/null || echo 'git state unreadable'))"
[ -d "$REPO/scripts" ] || { echo "✗ repo not found at $REPO — set REPO=<path> and re-run"; exit 1; }
mkdir -p "$BIN"

# ══ SECTION 1 — VERIFY (read-only; a committed tool is not a live tool; a green gate is the go) ═══════
echo
echo "== 1/4 verify: the systematic invariant (runs all seven sibling gates live) =="
if "$REPO/scripts/never-stuck-gate.sh" >/dev/null 2>&1; then
  echo "  ✓ never-stuck-gate GREEN (wait · reaper · comms · limit-reset · respawn · route · premortem all green)"
else
  echo "  ✗ never-stuck-gate RED — run $REPO/scripts/never-stuck-gate.sh for the failing leg"; FAILS=$((FAILS+1))
fi
echo "== 1/4 verify: tool selftests =="
for pair in "scripts/lead-deathwatch.sh|L1" "scripts/lead-reconciler.sh|L4" "scripts/wait-contract-lint.sh|L2" \
            "scripts/reap-guard.sh|R-a/b/c" "scripts/payload-lint.sh|F3" "scripts/exit-deadline.sh|F4" \
            "scripts/completion-push.sh|F5"; do
  s="${pair%%|*}"; tag="${pair##*|}"
  "$REPO/$s" --selftest >/dev/null 2>&1 && echo "  ✓ ${s##*/} ($tag)" || { echo "  ✗ ${s##*/} ($tag)"; FAILS=$((FAILS+1)); }
done
"$REPO/bin/cc-announce" --selftest >/dev/null 2>&1 && echo "  ✓ cc-announce (F1)" || { echo "  ✗ cc-announce"; FAILS=$((FAILS+1)); }
"$REPO/bin/cc-respawn" selftest    >/dev/null 2>&1 && echo "  ✓ cc-respawn (RS-a..f)" || { echo "  ✗ cc-respawn"; FAILS=$((FAILS+1)); }
"$REPO/bin/cc-route"   selftest    >/dev/null 2>&1 && echo "  ✓ cc-route (RT-a..f)" || { echo "  ✗ cc-route"; FAILS=$((FAILS+1)); }
"$REPO/bin/cc-teardown" --selftest >/dev/null 2>&1 && echo "  ✓ cc-teardown" || { echo "  ✗ cc-teardown"; FAILS=$((FAILS+1)); }
command -v bats >/dev/null 2>&1 && bats "$REPO/tests/lr-reset-poller.bats" >/dev/null 2>&1 && echo "  ✓ lr-reset-poller (LR-a..i)" || { echo "  ✗ lr-reset-poller bats"; FAILS=$((FAILS+1)); }

if [ "$FAILS" -gt 0 ]; then
  echo
  echo "⛔ $FAILS verification(s) RED — DO NOT ACTIVATE. Fix to green first (the gate IS the go-signal)."
  exit 1
fi

# ══ SECTION 2 — SYMLINKS (idempotent) + ROLE MAP + POLLER MIRROR ══════════════════════════════════════
echo
echo "== 2/4 symlinks + role map =="
for t in cc-wait cc-deathwatch-kqueue cc-run cc-announce cc-respawn cc-route cc-teardown cc-teardown-safety-gate.sh \
         cc-bind cc-board cc-context cc-sessions cc-notify cc-await-ping; do
  ln -sf "$REPO/bin/$t" "$BIN/$t" && echo "  linked $t"
done
mkdir -p "$HOME/.claude/cc-roles"
printf '%s\n' "$DESK_UUID" > "$HOME/.claude/cc-roles/desk"
printf '%s\n' "$DESK_UUID" > "$HOME/.claude/cc-roles/orchestrator"
printf '%s\n' "$DESK_UUID" > "$HOME/.claude/cc-roles/operator"   # <-- EDIT to your own push target if different
echo "  ✓ cc-roles/{desk,orchestrator,operator} → $DESK_UUID (rebind on a non-in-place pane restart)"
# The ~/.claude/scripts/limit-recover MIRROR becomes symlinks → repo (kills the statusline-class
# live-vs-repo drift for the poller: the launchd plist runs the mirror path).
mkdir -p "$HOME/.claude/scripts/limit-recover"
for f in "$REPO"/scripts/limit-recover/*; do
  ln -sf "$f" "$HOME/.claude/scripts/limit-recover/$(basename "$f")"
done
echo "  ✓ limit-recover mirror → repo symlinks (plist path resolves to the PROVEN poller)"

# ══ SECTION 3 — EFFECT-CHECK OUR OWN WORK (Deploy DoD: every deploy ends with 'it resolves + runs') ═══
echo
echo "== 3/4 effect-check =="
for t in cc-wait cc-respawn cc-route cc-teardown cc-announce; do
  if [ -x "$BIN/$t" ] && readlink "$BIN/$t" | grep -q "$REPO"; then echo "  ✓ $t live → repo"
  else echo "  ✗ $t symlink broken/foreign"; FAILS=$((FAILS+1)); fi
done
readlink "$HOME/.claude/scripts/limit-recover/lr-reset-poller.sh" | grep -q "$REPO" \
  && echo "  ✓ poller mirror → repo" || { echo "  ✗ poller mirror not a repo symlink"; FAILS=$((FAILS+1)); }
launchctl list 2>/dev/null | grep -q com.claude.lead-supervisor \
  && echo "  ✓ lead-supervisor launchd ACTIVE (D2)" || echo "  · lead-supervisor NOT loaded — see D2 template below"
launchctl list 2>/dev/null | grep -q com.reso.lr-reset-poller \
  && echo "  ✓ lr-reset-poller launchd ACTIVE" || echo "  · lr-reset-poller NOT loaded — install per template ① below"
"$BIN/cc-sessions" --names >/dev/null 2>&1 \
  && echo "  ✓ P8 session registry answers" || echo "  · P8 registry quiet — see /tmp/p8-activate.sh for a fresh machine"
[ "$FAILS" -gt 0 ] && { echo "⛔ effect-check failed — fix before installing the templates"; exit 1; }

# ══ SECTION 4 — TEMPLATES (adapt + install YOURSELF; NOTHING below is auto-applied) ═══════════════════
cat <<TEMPLATES

== 4/4 templates — your hand from here ==

════ ① LIMIT-RESET POLLER (B1-d) — install + the ruled AUTOFIRE flip ═══════════════════════════════════
# The notify-only precondition cycle RAN live 2026-07-12 (poller.log) and LR-a..i are proven, so the
# design's "notify-first for one cycle, then flip" is satisfied: install WITH autofire.
cp "$REPO/scripts/limit-recover/com.reso.lr-reset-poller.plist" ~/Library/LaunchAgents/
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' -c 'Add :EnvironmentVariables:LR_POLLER_AUTOFIRE string 1' \\
  ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist
launchctl load -w ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist
tail -5 ~/.reso/limit-recover/poller.log        # eyeball the first tick
# kill-switch: launchctl unload …  (or LR_POLLER_DISABLED=1 in the plist env)

════ ② NEVER-STUCK META-GATE onto the supervisor sweep (B1-c) ══════════════════════════════════════════
# In $REPO/scripts/lead-supervisor.sh, inside sweep() (YOU edit it — the agent never edits the live
# daemon), add an hourly composition check (cheap relative to the 3600s sweep):
#   "$REPO/scripts/never-stuck-gate.sh" >/dev/null 2>&1 || idl alarm '"never-stuck":"composition RED"'
# Then: launchctl kickstart -k gui/\$(id -u)/com.claude.lead-supervisor   # restart to pick it up

════ ③ PERMISSION HAND-STEP (harness-enforced C10 — must be YOUR hand, in-session /permissions) ════════
#   Bash(cc-teardown:*)      REQUIRED for delegated live-session teardown (the 3-denial proof stands)
#   Bash(cc-respawn:*)       optional — lets leads run the respawn protocol without prompts
#   Bash(cc-route:*)         optional — same for routing reads

════ ④ NEVER-WAIT RUNTIME LOOPS (L1..L4 — unchanged from v1) ═══════════════════════════════════════════
# L1  launchd death-watcher: com.chrisren.lead-deathwatch.plist → scripts/lead-deathwatch.sh --watch
#     ~/.claude/deathwatch/watch-list (rows pid\\tstart\\tlabel\\twaiter\\tworktree from the P8 registry).
# L2  supervisor sweep: scripts/wait-contract-lint.sh --sweep ~/.claude/wait-contracts
# L4  supervisor sweep: CC_RECON_ROSTER_TASKS='<harness task-table reader>' scripts/lead-reconciler.sh --once
# L3  beat-freshness: watch ~/.claude/cc-run/*.beat mtimes vs expected cadence → re-observe (S-3b), never reap.

════ ⑤ REAPER BIRTH-GRACE hook snippet (unchanged from v1) ═════════════════════════════════════════════
# In ~/.claude/hooks/teammate-auto-shutdown.sh immediately BEFORE its reap action:
#   if ! "$REPO/scripts/reap-guard.sh" decide --worktree "\$WT" --spawn-time "\$SPAWN_EPOCH" --member "\$MEMBER"; then
#     exit 0   # DEFER (birth grace / no products / dirty / busy) — additive: only ever turns reap → defer
#   fi

════ ⑥ COMMS RECIPE WIRING (F3/F4/F5 — unchanged from v1; full detail docs/COMMS-SAFETY-ACTIVATION.md) ═
# F5 in scripts/handoff-fire.sh self-close --terminal path, BEFORE the close:
#   "$REPO/scripts/completion-push.sh" fire --event "program-terminal: <what>" --detail "<state>"
# F4 exit-sequence flag: ': > ~/.claude/exit-sequence.flag' at exit-start · rm at exit-end; deadlines read
#   "$REPO/scripts/exit-deadline.sh" resolve   (900 in-exit, 3600 otherwise)
# F3 in the fire-payload generator: "$REPO/scripts/payload-lint.sh" "\$PAYLOAD_FILE" || exit 1

════ ⑦ FRESH-MACHINE ONLY — D2 + P8 (already ACTIVE here per the effect-check above) ══════════════════
# D2 supervisor + boundary-hook: docs/D2-RUNTIME-ACTIVATION.md (/tmp/d2-activate.sh pattern)
# P8 session-register SessionStart hook: /tmp/p8-activate.sh pattern (4 config dirs)

════ ⑧ ROLLBACK (mirror of every step above) ═══════════════════════════════════════════════════════════
# launchctl unload ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist && rm <plist>
# remove the never-stuck line from lead-supervisor.sh sweep() + kickstart
# /permissions → remove Bash(cc-teardown:*) etc.
# rm ~/.claude/bin/{cc-respawn,cc-route} (+ any of the others); restore ~/.claude/scripts/limit-recover
#   from the repo by plain copy if symlinks are unwanted; remove the reap-guard/F3/F4/F5 insertions.
TEMPLATES

echo "== done: VERIFIED green + symlinks/role-map applied + effect-checked; every template printed above =="
echo "   NOTHING was loaded, started, or edited in place by this script — that half is your hand (C10)."
