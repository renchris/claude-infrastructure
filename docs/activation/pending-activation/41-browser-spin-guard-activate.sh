#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 41-browser-spin-guard  —  activate the CPU-spin guard for automation browsers
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT LANDED (438883e365ec): scripts/browser-spin-guard.sh + launchd/com.claude.browser-spin-guard.plist
#   + tests/browser-spin-guard.bats (13 tests).
#
# WHY: on 2026-08-17 an `agent-browser`-owned headless Chrome wedged with EVERY service process
#   spinning at once — GPU, NetworkService, StorageService, AudioService, VideoCaptureService and
#   three renderers, 86-103% CPU each. That is 761% of this box's 1000%, sustained for 1d15h, with
#   load average 244, 85.9% sys and 0.0% idle. Killing the tree returned the box to 309% total CPU
#   and load 56 within one minute. Nothing on the machine ever reported it.
#
#   Two guards could plausibly have owned the class and neither does. `cc-reaper garbage` snapshots
#   `pid=,ppid=,etime=,ucomm=` — no CPU field at all — so a process that is ALIVE and burning a core
#   is invisible to it by construction; it collects the residue of DEAD sessions. `compressor-sentinel`
#   samples pcpu but adjudicates MEMORY, and was correct to stay quiet: segment utilisation was 12.8%
#   of limit. The box was not dying of memory. No rung watched CPU.
#
# WHY THIS SCRIPT EXISTS AT ALL: ~/.claude/scripts/ is a directory of PER-FILE symlinks, so a
#   brand-new tracked file is never linked no matter how current the checkout. Landed ≠ live. Without
#   Step 1 the script sits in the repo, inert. (deploy-live.sh does this too, but only for STAMPED
#   commits — at the time of writing this commit sat behind 11 un-stamped ones, which is exactly the
#   gap this file covers.)
#
# C10: this STAGES the wiring; YOU (operator) run it. Step 3 loads a launchd job.
#
# Convention: after you complete the steps, mark done:
#     touch ~/.claude/autonomy/pending-activation/41-browser-spin-guard-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
PLIST="com.claude.browser-spin-guard.plist"

echo "== 41-browser-spin-guard =="
echo
echo "Step 1 (mechanical, safe — the per-file symlink; nothing runs without it):"
echo "    ln -sfn $REPO/scripts/browser-spin-guard.sh ~/.claude/scripts/browser-spin-guard.sh"
echo
echo "Step 2 (rehearse — READ-ONLY, this arm never kills anything):"
echo "    ~/.claude/scripts/browser-spin-guard.sh"
echo "    Expect 'verdict=clean' on a healthy box. If it prints 'verdict=spin' it will name the"
echo "    pegged pids, their roles (gpu / renderer / NetworkService / ...) and the aggregate CPU,"
echo "    and the remedy is one command: agent-browser close --all"
echo
echo "Step 3 (load the job — detection only; it does NOT kill):"
echo "    ln -sfn $REPO/launchd/$PLIST ~/Library/LaunchAgents/$PLIST"
echo "    launchctl bootstrap gui/\$UID ~/Library/LaunchAgents/$PLIST"
echo "    launchctl list com.claude.browser-spin-guard    # expect LastExitStatus 0 — and NO PID line"
echo "    A PID line is the WRONG expectation here and its absence is not a failed load: this is a"
echo "    StartInterval job, not KeepAlive, so it is not resident. It holds a pid only for the"
echo "    fraction of a second it runs every 300s; between fires launchd reports 'state = not"
echo "    running', which is the healthy steady state. For the real signal use:"
echo "        launchctl print gui/\$UID/com.claude.browser-spin-guard | grep -E 'runs|last exit'"
echo "    'runs = 1, last exit code = 0' right after Step 3 is RunAtLoad having fired correctly."
echo
echo "Step 4 (verify it is actually ticking — evidence, not assumption):"
echo "    sleep 310; tail -3 ~/.claude/logs/browser-spin-guard.log"
echo "    One line per 300s run, clean or spin. That log IS the manifest's evidence path, so an"
echo "    empty file here means capacity-alarm will (correctly) call the job stalled."
echo
echo "OPTIONAL — arming the reaper. NOT part of activation, and deliberately a separate decision."
echo "  The job runs detection-only: it reports and notifies, it never kills. To let it tear the"
echo "  wedged tree down itself, add --reap to ProgramArguments in the plist and re-run Step 3."
echo "  The asymmetry vs the compressor sentinel (which IS armed) is the warning window: a"
echo "  compressor panic gives ~7.6 seconds, so only an armed actuator can act inside it. This wedge"
echo "  ran for a day and a half — a surfaced alarm has abundant time, and the downside of"
echo "  auto-killing (a browser torn out mid-automation) is real. Your call, not the default."
echo
echo "KILL SWITCHES (after loading):"
echo "    CC_SPIN_GUARD=0 in the plist wrapper     # arm goes inert, still reports verdict=clean"
echo "    launchctl bootout gui/\$UID/com.claude.browser-spin-guard"
