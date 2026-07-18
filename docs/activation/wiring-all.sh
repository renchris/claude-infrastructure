#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `cmd && ✓echo || {✗echo; FAILS++}` verify-reporter idiom
# wiring-all.sh v3 — THE consolidated C10 activation bundle. RUN BY THE HUMAN'S HAND, NEVER THE AGENT.
#
# v1 → never-wait L1..L4 · reaper birth-grace · comms F1..F5.
# v2 → Track-B gaps: B1-a cc-respawn · B1-b cc-route · B1-d lr-reset-poller (AUTOFIRE) ·
#      B1-c never-stuck-gate onto the supervisor sweep · cc-teardown permission · D2/P8 effect-checks.
# v3 → the DESK-EXISTENCE program (Program A): P0-14 desk-invariant (the missing organ — an
#      API-budget-independent launchd observer that re-prompts/re-fires a stunned/absent desk) ·
#      P0-18 nightly-regression (standing test signal) · full-hook-roster template + settings-drift
#      assert · activation-watch (absence-is-loud re-page) · boundary-4-dir + CC_PAGE_TO/Pushover ·
#      gate-green producer verify · Kimi key. Templates ⑨–⑭ below; ①–⑧ carry forward unchanged.
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
echo "== wiring-all v3 ==  repo=$REPO  bindir=$BIN  ($(git -C "$REPO" log --oneline -1 2>/dev/null || echo 'git state unreadable'))"
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
echo "== 1/4 verify: desk-existence program (v3 — P0-14/18 + template drift) =="
for pair in "scripts/desk-invariant.sh|P0-14" "scripts/nightly-regression.sh|P0-18" "scripts/settings-drift-assert.sh|drift-assert"; do
  s="${pair%%|*}"; tag="${pair##*|}"
  "$REPO/$s" --selftest >/dev/null 2>&1 && echo "  ✓ ${s##*/} ($tag)" || { echo "  ✗ ${s##*/} ($tag)"; FAILS=$((FAILS+1)); }
done
if command -v bats >/dev/null 2>&1; then
  bats "$REPO/tests/desk-invariant.bats" "$REPO/tests/settings-drift.bats" "$REPO/tests/activation-watch.bats" >/dev/null 2>&1 \
    && echo "  ✓ desk-invariant + settings-drift + activation-watch bats" || { echo "  ✗ desk-existence bats"; FAILS=$((FAILS+1)); }
else echo "  · bats not installed — skipped the desk-existence bats"; fi
"$REPO/hooks/activation-watch.sh" --selftest >/dev/null 2>&1 && echo "  ✓ activation-watch (D-v)" || { echo "  ✗ activation-watch"; FAILS=$((FAILS+1)); }
command -v plutil >/dev/null 2>&1 && plutil -lint "$REPO"/launchd/*.plist >/dev/null 2>&1 \
  && echo "  ✓ launchd/*.plist all parse (plutil -lint)" || echo "  · plutil skipped/failed — run plutil -lint $REPO/launchd/*.plist"

if [ "$FAILS" -gt 0 ]; then
  echo
  echo "⛔ $FAILS verification(s) RED — DO NOT ACTIVATE. Fix to green first (the gate IS the go-signal)."
  exit 1
fi

# ══ SECTION 2 — SYMLINKS (idempotent) + ROLE MAP + POLLER MIRROR ══════════════════════════════════════
echo
echo "== 2/4 symlinks + role map =="
for t in cc-wait cc-deathwatch-kqueue cc-run cc-announce cc-respawn cc-route cc-teardown cc-teardown-safety-gate.sh \
         cc-bind cc-board cc-context cc-sessions cc-notify cc-await-ping \
         desk-assert cc-backlog cc-decide cc-digest; do
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
# v3 desk-existence program: the launchd/SessionStart-run scripts its plists reference must resolve
# into the repo (install.sh symlinks all scripts/*.sh + hooks/*.sh; wiring-all guarantees these ones).
mkdir -p "$HOME/.claude/scripts" "$HOME/.claude/hooks"
for s in desk-invariant.sh nightly-regression.sh settings-drift-assert.sh; do
  ln -sf "$REPO/scripts/$s" "$HOME/.claude/scripts/$s" && echo "  linked scripts/$s"
done
ln -sf "$REPO/hooks/activation-watch.sh" "$HOME/.claude/hooks/activation-watch.sh" && echo "  linked hooks/activation-watch.sh"

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
for s in desk-invariant.sh nightly-regression.sh settings-drift-assert.sh; do
  if [ -x "$HOME/.claude/scripts/$s" ] && readlink "$HOME/.claude/scripts/$s" | grep -q "$REPO"; then echo "  ✓ scripts/$s live → repo"
  else echo "  ✗ scripts/$s symlink broken/foreign"; FAILS=$((FAILS+1)); fi
done
launchctl list 2>/dev/null | grep -q com.claude.desk-invariant \
  && echo "  ✓ desk-invariant launchd ACTIVE (P0-14)" || echo "  · desk-invariant NOT loaded — install per template ⑨ below"
launchctl list 2>/dev/null | grep -q com.claude.nightly-regression \
  && echo "  ✓ nightly-regression launchd ACTIVE (P0-18)" || echo "  · nightly-regression NOT loaded — install per template ⑩ below"
# desk-existence liveness snapshot (read-only; the invariant itself will page/re-fire when loaded)
if [ -f "$HOME/.claude/cc-roles/desk" ]; then
  echo "  · desk role → $(cat "$HOME/.claude/cc-roles/desk" 2>/dev/null) (desk-invariant asserts engagement once loaded)"
else echo "  · cc-roles/desk absent — desk-invariant will fire a replacement from the canned brief (budgeted)"; fi
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

════ ⑨ DESK-EXISTENCE INVARIANT (P0-14 — the missing organ) ════════════════════════════════════════════
# The API-budget-independent launchd observer: asserts a registered desk exists AND took a turn <=45m
# (or holds a fresh owned wait-contract); else OS-pages + re-prompts a stunned desk / fires a BUDGETED
# replacement (<=2/6h). It NEVER kills or edits a session. Load it (300s sweep, RunAtLoad):
cp "$REPO/launchd/com.claude.desk-invariant.plist" ~/Library/LaunchAgents/
launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.claude.desk-invariant.plist
# Prereqs it reads: ~/.claude/cc-roles/desk (a live desk pane UUID — set in §2) + the P8 cc-registry.
# Tunables (plist env): DESK_INVARIANT_STALE_MIN=45 · RESPAWN_MAX=2 · RESPAWN_WINDOW_S=21600 · DEDUP_WINDOW_S=3600.
# NOTE: the replacement-fire uses handoff-fire --as-role (fm2-stack P0-15). Until that lands, confirm the
# fire argv or override DESK_INVARIANT_FIRE_BIN. Dry-check: "$REPO/scripts/desk-invariant.sh" --selftest
# kill-switch: launchctl bootout gui/\$(id -u)/com.claude.desk-invariant

════ ⑩ NIGHTLY REGRESSION SIGNAL (P0-18) ═══════════════════════════════════════════════════════════════
# Runs bats + gate/lint selftests + plutil -lint nightly (04:00); PAGES on red (autonomy/pages/ + osascript);
# always logs one line to ~/.claude/autonomy/regression.log. p12: nothing runs the tests between lands.
cp "$REPO/launchd/com.claude.nightly-regression.plist" ~/Library/LaunchAgents/
launchctl bootstrap gui/\$(id -u) ~/Library/LaunchAgents/com.claude.nightly-regression.plist
# eyeball one run now:  "$REPO/scripts/nightly-regression.sh" --run ; tail -3 ~/.claude/autonomy/regression.log
# kill-switch: launchctl bootout gui/\$(id -u)/com.claude.nightly-regression

════ ⑪ HOOK ROSTER: template merge + boundary-4-dir + activation-watch (G-P6-7 / G-P6-5b / D-v) ═════════
# settings-templates/settings.example.json carries the FULL portable hook roster. Wire it per config dir
# (ADDITIVE event merge + deny/ask union; each writes a .pre-wire.bak; a read-only assert reports gaps):
for d in ~/.claude ~/.claude-next ~/.claude-secondary ~/.claude-tertiary ~/.claude-quaternary; do
  "$REPO/install.sh" --config-dir "\$d" --wire-hooks
done
# boundary-handoff is ORDER-sensitive in the Stop chain — the merge won't reorder a populated Stop. If the
# assert still flags it, add per dir by hand (obj-2):
#   settings.json .hooks.Stop += [ { "hooks":[ {"type":"command","command":"~/.claude/hooks/boundary-handoff.sh"} ] } ]
# activation-watch is wired by --wire-hooks (SessionStart). completion-assert + DoD re-inject (dod-persist)
# are fm1-stack P0-3/T-P6-7 — add hooks/completion-assert.sh into Stop obj-1 (before anti-deference) once it lands.

════ ⑫ SETTINGS-DRIFT ASSERT on SessionStart (T-P10-4) ═════════════════════════════════════════════════
# Surface a deny/ask/hook rule that silently dropped out of one of the 5 config dirs (memory: next4 drifted).
# Add to EACH dir's SessionStart (advisory — the assert exits 1 on drift; SessionStart hooks don't block):
#   .hooks.SessionStart += [ { "hooks":[ {"type":"command","command":"~/.claude/scripts/settings-drift-assert.sh","timeout":8} ] } ]
# check anytime:  "$REPO/scripts/settings-drift-assert.sh"     (exit 1 + named lines on any drift)

════ ⑬ PAGE DELIVERY: CC_PAGE_TO + Pushover (P0-7 / G-P10-6 — the page channel is DISCONNECTED today) ═══
# lead-supervisor sets CC_PAGE_TO="" → every page is a dead-letter; push-critical is INERT (no token). Arm
# BOTH so desk-invariant / nightly / supervisor pages actually reach you:
#   1. /usr/libexec/PlistBuddy -c 'Set :EnvironmentVariables:CC_PAGE_TO desk' \\
#        ~/Library/LaunchAgents/com.claude.lead-supervisor.plist   (role-indirected via cc-roles/desk)
#      then: launchctl kickstart -k gui/\$(id -u)/com.claude.lead-supervisor
#   2. ~/.zshenv:  export PUSHOVER_TOKEN=... ; export PUSHOVER_USER=...
# verify once:  printf '{"message":"wiring-all test"}' | ~/.claude/hooks/push-critical.sh   (expect a phone buzz)

════ ⑭ GATE-GREEN PRODUCER (verify) + KIMI HEDGE KEY ═══════════════════════════════════════════════════
# boundary-handoff fires only when .git/gate-green==HEAD. landing's ship-land.sh is the PRODUCER — verify a
# green /ship writes it:  git rev-parse HEAD ; cat "\$(git rev-parse --git-common-dir)/gate-green"  (must match)
# Kimi metered hedge (cliff-fallback for a capped account):
#   ~/.zshenv:  export MOONSHOT_API_KEY=...   (endpoint api.moonshot.ai/anthropic — metered, NOT the /coding flat plan)

════ ⑧ ROLLBACK (mirror of every step above) ═══════════════════════════════════════════════════════════
# launchctl unload ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist && rm <plist>
# remove the never-stuck line from lead-supervisor.sh sweep() + kickstart
# /permissions → remove Bash(cc-teardown:*) etc.
# rm ~/.claude/bin/{cc-respawn,cc-route} (+ any of the others); restore ~/.claude/scripts/limit-recover
#   from the repo by plain copy if symlinks are unwanted; remove the reap-guard/F3/F4/F5 insertions.
# v3 (⑨–⑭):
#   launchctl bootout gui/\$(id -u)/com.claude.desk-invariant     && rm ~/Library/LaunchAgents/com.claude.desk-invariant.plist
#   launchctl bootout gui/\$(id -u)/com.claude.nightly-regression && rm ~/Library/LaunchAgents/com.claude.nightly-regression.plist
#   restore each settings.json from its .pre-wire.bak; remove the settings-drift SessionStart line;
#     unset CC_PAGE_TO / PUSHOVER_* / MOONSHOT_API_KEY; rm the ~/.claude/scripts/{desk-invariant,
#     nightly-regression,settings-drift-assert}.sh + ~/.claude/hooks/activation-watch.sh symlinks.
TEMPLATES

echo "== done: VERIFIED green + symlinks/role-map applied + effect-checked; every template printed above =="
echo "   NOTHING was loaded, started, or edited in place by this script — that half is your hand (C10)."
