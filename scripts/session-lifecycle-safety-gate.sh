#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `<check> && ok || bad` reporter idiom is intentional —
# ok/bad/todo always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# session-lifecycle-safety-gate — the un-hold bar for AUTONOMOUS SESSION REAPING (CL-a..c classifier,
# RP-a..f reaper). Sibling of route/wait/reaper/comms/limit-reset/respawn-safety gates, same discipline:
# criteria are the safety contract; turning this green IS "ready to reap unattended".
#
# ── THE GAP THAT IS THE SPEC (roadmap §1.2 + /tmp/autonomous-session-lifecycle-brief.md) ────────────────
# Teammates auto-reap (TeammateIdle); LEADS do not. A handed-off lead whose --recycle pane-exit fails
# lingers idle holding a pane until a human notices (incident 2026-07-17: session 9e5c5f1f, idle 2.6h).
# The fix is a classifier (cc-classify) that decides WHY a session is idle + a reaper (cc-reaper) that
# closes ONLY the provably-terminal, work-safe causes through the effect-verified cc-teardown actuator.
#
# ── THE EDGES THAT MUST BE RED-PROVEN ──────────────────────────────────────────────────────────────────
# CL: an active / rate-limited / waiting session is NEVER labeled reapable; handed-off-lead requires a
#     LIVE successor (a dead one is refused); handoff is not inferred from CC-native bridge-session records.
# RP: a reap requires cause∈{handed-off-lead,finished-teammate} AND work-landed AND idle≥settle AND --reap;
#     checkpoint runs BEFORE any close; a post-classify dirty tree ABORTS (WIP checkpointed); cc-teardown's
#     own gate is re-run (double-gate); every never-reap cause is left untouched.
# TD: the actuator effect-verifies (re-observed) and a blind 0-list enumerator → INDETERMINATE, never a
#     false "pane gone" (the it2-ls-0 incident).
#
# ── BUILD-vs-ACTIVATION SPLIT (C10) ─────────────────────────────────────────────────────────────────────
# This gate proves the machinery. The STANDING-LOOP deployment (launchd running `cc-reaper sweep --reap`)
# is C10 (human-only) — docs/AUTONOMOUS-REAPER-ACTIVATION.md + docs/activation/autonomous-reaper.plist.
#
# Exit: 0 = every criterion met (ready) · 1 = not ready (any FAIL/TODO) · 2 = internal error.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0; TODO=0
ok(){   printf '  ✅ %-6s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-6s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
todo(){ printf '  ⏳ %-6s %s\n' "$1" "$2"; TODO=$((TODO+1)); }

echo "session-lifecycle-safety-gate — autonomous reap un-hold bar (CL classifier · RP reaper · TD actuator):"

CLASSIFY=bin/cc-classify
REAPER=bin/cc-reaper
TEARDOWN=bin/cc-teardown
bats_green(){ command -v bats >/dev/null 2>&1 && bats "$1" >/dev/null 2>&1; }

# ── CL — the classifier ─────────────────────────────────────────────────────────────────────────────────
if [ ! -x "$CLASSIFY" ]; then
  todo "CL-a" "NOT BUILT — bin/cc-classify: classify_session→{active,rate-limited,owned-wait,coordination-hang,handed-off-lead,finished-teammate,crashed} from durable signals (last-assistant-ts, pid, isApiErrorMessage, git, team attribution), NEVER mtime."
  todo "CL-b" "NOT BUILT — the two REAPABLE causes need POSITIVE evidence: handed-off-lead ⇒ real /handoff + LIVE successor; a dead successor is refused."
  todo "CL-c" "NOT BUILT — handoff is NOT inferred from CC-native bridge-session records; an unreadable timestamp fails safe to active."
else
  bats_green tests/cc-classify.bats \
    && ok "CL" "cc-classify built · tests/cc-classify.bats green (7 causes + dead-successor + bridge-false-positive RED-proofs)" \
    || bad "CL" "cc-classify present but tests/cc-classify.bats is RED"
fi

# ── RP — the reaper ─────────────────────────────────────────────────────────────────────────────────────
if [ ! -x "$REAPER" ]; then
  todo "RP-a" "NOT BUILT — bin/cc-reaper sweep: reap ONLY cause∈{handed-off-lead,finished-teammate} AND work-landed AND idle≥settle."
  todo "RP-b" "NOT BUILT — DRY-RUN default; --reap to act; checkpoint-first (WIP→refs/wip) BEFORE any close."
  todo "RP-c" "NOT BUILT — post-classify dirty tree ABORTS the reap (WIP checkpointed); cc-teardown's gate re-run (double-gate)."
  todo "RP-d" "NOT BUILT — active/owned-wait/coordination-hang/rate-limited/crashed NEVER reaped."
else
  bats_green tests/cc-reaper.bats \
    && ok "RP" "cc-reaper built · tests/cc-reaper.bats green (reap-path + checkpoint-first + race-abort + all 5 never-reap guarantees)" \
    || bad "RP" "cc-reaper present but tests/cc-reaper.bats is RED"
fi

# ── TD — the actuator (reused; must stay green under the blind-enumerator fix) ───────────────────────────
if [ ! -x "$TEARDOWN" ]; then
  bad "TD" "bin/cc-teardown missing — the reaper has no effect-verified actuator"
else
  "$TEARDOWN" --selftest >/dev/null 2>&1 \
    && ok "TD" "cc-teardown --selftest green (effect-verified close · blind 0-list → INDETERMINATE, never false 'gone')" \
    || bad "TD" "cc-teardown --selftest RED"
fi

# ── declared residual blindness (named, with its covering layer) ────────────────────────────────────────
echo "  🕳  CL-blind DECLARED: owned-wait vs coordination-hang uses best-effort per-lead team attribution"
echo "      (ps --agent-name + team config.json); imprecision cannot cause a wrongful reap — both are"
echo "      NEVER-reap, so the split only steers SURFACING. Successor detection is cwd-heuristic; the reaper's"
echo "      work-landed re-check + cc-teardown's independent gate are the covering layers."

printf 'session-lifecycle-safety-gate: %d met · %d failed · %d NOT BUILT\n' "$PASS" "$FAIL" "$TODO"
if [ "$FAIL" -gt 0 ] || [ "$TODO" -gt 0 ]; then
  echo "⇒ AUTONOMOUS SESSION REAPING: NOT READY. (Red here is not a bug — it is the bar. Build to green, never lower the bar.)"
  exit 1
fi
echo "⇒ every registered session-lifecycle criterion is mechanically satisfied; autonomous reaping is safe to activate (deployment = C10, see docs/AUTONOMOUS-REAPER-ACTIVATION.md)."
