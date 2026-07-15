#!/bin/bash
# wait-safety-gate — the RUNTIME un-hold bar for the NEVER-WAIT-ON-THE-DEAD build (operator-directed
# 2026-07-14; five layers L0..L4). Sibling of premortem-gate.sh, same discipline: the desk registers
# B/S-style criteria as RED-PROVABLE assertions BEFORE the build, and turning this green IS "ready".
#
# ── THE INCIDENT THAT IS THE SPEC (L0 case study) ──────────────────────────────────────────────────
# A W5 corpus teammate died out-of-band and went UNDETECTED for 77 minutes. Three compounding failures,
# each of which one layer below closes:
#   (1) the wave-lead's event-driven wait was UNOWNED — it existed only in the lead's context, so when
#       that context was gone the wait was orphaned and nobody was waiting            → L2 (wait contracts)
#   (2) the harness fired nothing — task notifications cover CLEAN COMPLETION, not pane DEATH           → L1
#   (3) the harness task table still LISTED the dead teammate — a three-way divergence (tasks say alive,
#       registry/disk say dead) that the two-roster/divergence prediction called      → L4 (reconciler)
#   D10's long-op-vs-hang identity is the reason age alone could not have caught it either              → L3
# L0 = the ALREADY-BUILT p8 (spawn-death row: DIED-UNRENDERED) + d2 (boundary hook + PAGE-only supervisor
# DEAD detection). This incident is L0's live case study — it is exactly the DIED-UNRENDERED / unowned-
# boundary shape those cover — but L0 alone leaves the WAIT unowned and the death-event latency = one
# supervisor sweep (≤30s at best, a poll). L1..L4 make it event-instant and structural.
#
# ── THE PRE-MORTEM QUESTION, asked of EVERY layer (verbatim, operator-registered) ──────────────────
#   "What is this check structurally unable to see, and who would end up checking it by hand?"
# Each criterion below is RED-provable: a test that fails against the naive/absent form. C10 activation
# (kqueue daemon, launchd, settings) is human-only — the agent builds + tests + hands an activation script.
#
# ── THE COMPOSITION RULE (desk-elevated 2026-07-14; the coherence principle of the whole build) ────
# Every layer DECLARES its structural blindness AND names the layer that covers it. That composition is
# what turns five PARTIAL detectors into one COMPLETE one — no layer is complete alone, and the design
# is only sound if every declared blind spot is another layer's covered case: L3 silent-op → L1 pid;
# L1 unregistered-pid → P8 registry + L2 RED; L2 dead-waiter → L4 divergence; L4 coherent-wrong → three
# INDEPENDENT sources. A blindness declared WITHOUT a covering route is an open hole, not a closed one.
#
# ── DESK REGISTRATION (2026-07-14): all 14 criteria REGISTERED, NO VETO. Criteria change ONLY by desk
# ruling. Three endorsed as load-bearing: L2-c (watchdog enforces INDEPENDENT of waiter liveness — the
# dead-waiter-with-open-contract case nobody designs for; tonight's incident inverted) · L1-c ({pid,
# start-time} guard — bare-pid identity is a classic false-liveness hole) · the composition rule above.
#
# ⚠️ RED TODAY BY DESIGN (L1..L4 unbuilt). Redness IS "not ready"; green IS the definition of ready.
# Exit: 0 = every registered criterion met · 1 = not ready (with reasons).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0; TODO=0
ok(){   printf '  ✅ %-6s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-6s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
todo(){ printf '  ⏳ %-6s %s\n' "$1" "$2"; TODO=$((TODO+1)); }

DEATHWATCH=scripts/lead-deathwatch.sh          # L1
WCLINT=scripts/wait-contract-lint.sh           # L2 (the keeper)
HEARTBEAT=bin/cc-run                           # L3 (effect-heartbeat command wrapper)
RECONCILER=scripts/lead-reconciler.sh          # L4

echo "wait-safety-gate — never-wait-on-the-dead un-hold bar (L0 done · L1–L4 registered)"
echo

echo "L0 — spawn-death + DEAD detection (p8 + d2; DONE — this incident is its case study)"
if [ -f hooks/boundary-handoff.sh ] && [ -f scripts/lead-supervisor.sh ] && ./scripts/premortem-gate.sh >/dev/null 2>&1; then
  ok "L0" "p8/d2 built + premortem-gate green; DEAD is detected — but at POLL latency (≤1 sweep), and the WAIT it was blocking on is still unowned (⇒ L1 event-instant, L2 owns the wait)"
else
  bad "L0" "p8/d2 not green — build the runtime primitives first (premortem-gate.sh)"
fi

echo
echo "L1 — kqueue EVFILT_PROC death-watcher (event-INSTANT death → waiter's mailbox + auto forensics)"
if [ ! -f "$DEATHWATCH" ]; then
  todo "L1-a" "NOT BUILT — $DEATHWATCH absent. BLIND TO: a pid it never REGISTERED — an unwatched pid's death fires nothing (the p8 'never-rendered ⇒ no row' shape). ⇒ registration at spawn-instant (P8 registry) is a hard dependency, and an event-driven wait on an UNREGISTERED waitee must lint RED (L2 tie). Who checks by hand? the waiter, eventually — i.e. the 77-minute gap."
  todo "L1-b" "NOT BUILT — CAPTURE-BEFORE-NOTIFY (Invariant 7): the forensics checkpoint of orphaned WIP must be written BEFORE the death-event mailbox notify, so the evidence survives even if the notify path fails. RED-provable: kill the notify, the checkpoint still exists."
  todo "L1-c" "NOT BUILT — PID-RECYCLING guard: watch {pid, start-time}, not pid alone — the OS reuses pids, and a stale registration on a recycled pid would fire a FALSE death-event. RED-provable vs a start-time-mismatch fixture."
  todo "L1-d" "NOT BUILT — death ⇒ checkpoint (MECHANICAL) + PAGE (never auto-respawn) — capture is automatic, recovery is paged (ruling #1 + Invariant 7)."
else
  grep -qiE 'checkpoint.*(before|prior).*notif|capture.?before.?notif' "$DEATHWATCH" && ok "L1-b" "capture-before-notify present" || bad "L1-b" "notify may precede the checkpoint — evidence can be lost on a failed capture (Invariant 7)"
  grep -qiE 'start.?time|starttime|lstart|etimes' "$DEATHWATCH" && ok "L1-c" "pid+start-time recycling guard present" || bad "L1-c" "keys on pid alone — a recycled pid fires a false death"
  grep -qiE 'page|paged' "$DEATHWATCH" && grep -qvE 'respawn|auto.?recover' "$DEATHWATCH" && ok "L1-d" "death → checkpoint + PAGE (no auto-respawn)" || bad "L1-d" "auto-recovery present or paging absent — recovery must be paged"
  [ -f "$WCLINT" ] && ok "L1-a" "wait-contract lint present to RED an unregistered waitee (L2)" || bad "L1-a" "no L2 lint — an unregistered waited-on pid is invisible to the watcher"
fi

echo
echo "L2 — WAIT CONTRACTS (the structural core / keeper): no unowned waits BY CONSTRUCTION"
if [ ! -f "$WCLINT" ]; then
  todo "L2-a" "NOT BUILT — $WCLINT absent. THE CORE: every event-driven hold writes a DISK contract {waiter, waitee, expected-signal, heartbeat-expectation, deadline, on-timeout-action}; an UNCONTRACTED wait (an in-context / ad-hoc cc-await-ping) lints RED. This is BIND's move applied to waiting — the 77-min gap was an unowned wait living only in a context. BLIND TO: a wait that bypasses the contract API entirely; who checks? nobody — which is the incident. Mitigation: the lint greps the wait PRIMITIVES for a contract write."
  todo "L2-b" "NOT BUILT — a contract with NO deadline or NO on-timeout-action lints RED — an infinite wait is an orphan-in-waiting."
  todo "L2-c" "NOT BUILT — the watchdog enforces contracts INDEPENDENT of the waiter's liveness: a contract whose WAITER is dead is itself a divergence (contract outlives its author on disk) → detected + PAGED. BLIND TO: nothing the reconciler (L4) doesn't also cover — this is where L2 and L4 meet."
  todo "L2-d" "NOT BUILT — on-timeout for a LIVE-but-stalled waitee gates on the effect re-read (S-3b), NEVER on silence — a page deadline triggers RE-OBSERVATION, never a reap (the §3h near-miss law, inherited)."
else
  ./scripts/wait-contract-lint.sh --selftest >/dev/null 2>&1 && ok "L2" "wait-contract-lint selftest green (uncontracted-wait RED, deadline/on-timeout required, dead-waiter divergence, S-3b timeout)" || bad "L2" "wait-contract-lint selftest not green"
fi

echo
echo "L3 — effect-bound progress heartbeats (closes D10 long-op-vs-hang AT THE SOURCE)"
if [ ! -f "$HEARTBEAT" ]; then
  todo "L3-a" "NOT BUILT — $HEARTBEAT absent. A long-command wrapper touches a heartbeat per unit of REAL OUTPUT (not wall-clock) → a producing op stays fresh, a hung op goes stale: the D10 identity (both render zero over a window) is broken at the source, killing BOTH false-page and silent-stall classes."
  todo "L3-blind" "NOT BUILT — DECLARE THE BLINDNESS: a SILENT-but-alive op (pure compute, no I/O) is NOT distinguishable from a hang by output alone; and a LOOPING-output op fires heartbeats without real progress. So output-heartbeats close the silent-HANG class, NOT the silent-compute or livelock classes. Liveness for a silent op falls back to L1 (pid); its L2 contract sets heartbeat-expectation=none so it does not false-page. Who checks the livelock by hand? still the deadline — named, not hidden."
else
  grep -qiE 'per.?(unit|line|byte).*output|output.*heartbeat|read.*&&.*touch' "$HEARTBEAT" && ok "L3-a" "heartbeat keyed on real output, not wall-clock" || bad "L3-a" "heartbeat appears time-based — it cannot discriminate a long op from a hang (D10)"
  grep -qiE 'no.?output|silent|heartbeat.?expectation|compute' "$HEARTBEAT" && ok "L3-blind" "silent-op / livelock blindness declared + routed to L1/L2" || bad "L3-blind" "the no-output blind spot is undeclared — a silent op will false-page or a hang will hide"
fi

echo
echo "L4 — three-way anti-entropy reconciler (harness tasks × registry × disk; divergence IS the alarm)"
if [ ! -f "$RECONCILER" ]; then
  todo "L4-a" "NOT BUILT — $RECONCILER absent. Reconciles the THREE rosters (harness task table × cc-registry × disk telemetry); any PERSISTENT pairwise divergence alarms and NAMES the diverged pair (the incident: tasks listed a registry-dead pid). Two-roster law: separately-maintained rosters that should agree WILL drift; the drift is the signal."
  todo "L4-b" "NOT BUILT — anti-cry-wolf: a TRANSIENT transition (spawned-not-yet-registered, dying-not-yet-swept) within a grace window must NOT alarm (cc-board's grace-window discipline)."
  todo "L4-c" "NOT BUILT — the reconciler emits its OWN heartbeat (S-4 shape); its ABSENCE is the alarm — who watches the watcher, answered mechanically."
  todo "L4-blind" "NOT BUILT — DECLARE THE BLINDNESS: three-way AGREEMENT on a WRONG state is invisible (the reconciler catches DRIFT, not coherent-wrong). Mitigated by three INDEPENDENT sources (harness API / pid kill-0 / disk mtime) — coherent-wrong across independent sources is unlikely, not impossible. Who checks? nobody — the named residual."
else
  grep -qiE 'grace|transient' "$RECONCILER" && ok "L4-b" "grace window (anti-cry-wolf)" || bad "L4-b" "no grace window — every spawn/teardown transition would false-alarm"
  grep -qiE 'heartbeat|sweep_log|idl' "$RECONCILER" && ok "L4-c" "reconciler heartbeat (who-watches-the-watcher)" || bad "L4-c" "no reconciler heartbeat — a crashed reconciler looks like a quiet system"
  grep -qiE 'diverg|mismatch|pair' "$RECONCILER" && ok "L4-a" "pairwise divergence alarm, pair named" || bad "L4-a" "no divergence detection"
  grep -qiE 'agree.*wrong|coherent|independent.?source|blind' "$RECONCILER" && ok "L4-blind" "coherent-wrong blindness declared" || bad "L4-blind" "the all-three-agree-wrong blind spot is undeclared"
fi

echo
printf 'wait-safety-gate: %d met · %d failed · %d NOT BUILT\n' "$PASS" "$FAIL" "$TODO"
if [ "$FAIL" -gt 0 ] || [ "$TODO" -gt 0 ]; then
  echo "⇒ NEVER-WAIT-ON-THE-DEAD: NOT READY TO UN-HOLD. (Red here is not a bug — it is the bar. L2 is the keeper of the set.)"
  exit 1
fi
echo "⇒ every registered wait-safety criterion is mechanically satisfied; un-hold is defensible."
