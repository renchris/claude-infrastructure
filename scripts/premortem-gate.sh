#!/bin/bash
# premortem-gate — the mechanical bar for the RUNTIME-PHASE UN-HOLD.
#
# The desk registered B-1..B-3 and S-1..S-4 as binding review criteria, and then sharpened them:
#
#     "each must arrive as a RED-provable test, not prose — a pre-mortem nobody can watch fire is
#      itself a check that cannot observe what it guards."
#
# Correct, and it is this project's own law turned back on its authors (audit §3i). So the pre-mortems
# live here as ASSERTIONS, not paragraphs.
#
# ⚠️ THIS GATE IS RED TODAY, BY DESIGN. The boundary hook and the supervisor do not exist; the criteria
# they must satisfy therefore cannot pass. That redness IS the statement "the runtime phase is not ready",
# and turning it green IS the definition of ready. It is deliberately NOT wired into pre-commit: a gate
# that is red on every commit teaches people to ignore it (the cry-wolf failure — the same reason cc-board
# has a grace window). Run it when someone proposes to un-hold.
#
# Exit: 0 = every criterion met (⇒ un-hold is defensible) · 1 = not ready (with the reasons)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0; TODO=0
ok(){   printf '  ✅ %-5s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-5s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
todo(){ printf '  ⏳ %-5s %s\n' "$1" "$2"; TODO=$((TODO+1)); }

HOOK=hooks/boundary-handoff.sh
SUP=scripts/lead-supervisor.sh

echo "premortem-gate — the runtime-phase un-hold bar (blueprint §3.2/§3.3)"
echo

echo "BOUNDARY HOOK (h)"
if [ ! -f "$HOOK" ]; then
  todo "B-1" "NOT BUILT — $HOOK absent. Criterion: the hook fires on STOP, so a session HUNG MID-TURN never runs it. It is blind to exactly the sessions most likely to be past their boundary (the trigger and the failure are the same event). ⇒ the SUPERVISOR must independently cover 'past-threshold ∧ not-Stopping'; the hook may never be the sole boundary mechanism."
  todo "B-2" "NOT BUILT — Criterion: the one-shot latch must NOT be keyed on HEAD-sha alone. A session that ignores the advisory and keeps working WITHOUT committing leaves HEAD unchanged ⇒ the latch holds ⇒ the hook never re-advises: it goes quiet exactly when it should get louder. This is INVARIANT-7-shaped (the latch's one-shot HYGIENE goal destroys the advisory's EVIDENCE role — the desk's read, and it is right). Needs a second re-arm dimension: a used_pct delta (~+10) or a time-based re-arm."
  todo "B-3" "NOT BUILT — Criterion: the hook MUST log ABSTENTIONS, not only fires. Abstain paths (stale telemetry, dirty tree, live teammates) must emit {fired|abstained:<reason>} to the IDL, else 'it didn't fire' is indistinguishable from 'it never evaluated' — the D9 shape, in the primitive whose whole job is to fire."
else
  grep -qE 'used_pct|USED_PCT|delta|re-?arm' "$HOOK" \
    && ok  "B-2" "latch carries a second re-arm dimension (not HEAD-sha alone)" \
    || bad "B-2" "latch appears keyed on HEAD-sha alone — it will go quiet exactly when it should get louder"
  grep -qE 'abstain' "$HOOK" \
    && ok  "B-3" "abstentions are logged" \
    || bad "B-3" "no abstain logging — 'didn't fire' and 'never evaluated' are the same observation (D9)"
  grep -qE 'past-threshold|not-stopping|stale' "${SUP:-/dev/null}" 2>/dev/null \
    && ok  "B-1" "supervisor independently covers past-threshold ∧ not-Stopping" \
    || bad "B-1" "nothing covers a session HUNG past its boundary — the hook cannot see it (it fires on Stop)"
fi

echo
echo "SUPERVISOR (b)"
# S-1 is the ONE criterion that does not need the supervisor to exist — it constrains the reapers the
# supervisor will read. Encoded today (the desk's suggestion), so the constraint is safe BY CONSTRUCTION
# rather than by luck, and a future "tidy /tmp" change fails a gate NOW instead of blinding a supervisor
# that does not exist yet.
if ./scripts/reaper-horizon-lint.sh >/dev/null 2>&1; then
  ok  "S-1" "every evidence horizon outlives the supervisor's slowest sweep (×10) — enforced by scripts/reaper-horizon-lint.sh"
else
  bad "S-1" "a reaper's horizon is shorter than the sweep interval ×10 — its evidence would be INVISIBLE to the supervisor (run scripts/reaper-horizon-lint.sh)"
fi

# S-2 is a PRECONDITION and it is checkable today: the supervisor reads telemetry + the registry, both of
# whose reapers were found erasing evidence. A supervisor on a spine that deletes its own evidence reports
# "all clear" into a fire. So: the evidence-separation suites must be green BEFORE b is built.
if bash scripts/telemetry-e2e.sh >/dev/null 2>&1 && ./scripts/p8-e2e.sh >/dev/null 2>&1; then
  ok  "S-2" "evidence separation proven upstream (telemetry-e2e + p8-e2e green) — the spine no longer deletes its own evidence"
else
  bad "S-2" "evidence-separation suites are NOT green — do not build the supervisor on a spine that erases what it must detect"
fi

if [ ! -f "$SUP" ]; then
  todo "S-3" "NOT BUILT — Criterion: the supervisor cannot see in-session state AT ALL (bash, out-of-session): modals, composer, mid-turn reasoning. This is STRUCTURAL blindness, not a policy choice — a structural blindness cannot be fixed by a better rule. It must PAGE (ruling #2), and must declare the blindness rather than paper over it."
  todo "S-3b" "NOT BUILT — Criterion (desk-registered 2026-07-14 after the FIRST live stall-page cycle, audit §3h): the supervisor's page path MUST encode deadline→RE-OBSERVATION — the disposition branch reachable ONLY through a fresh effects-dark re-read, NEVER from deadline-silence alone (reply-compliance is not a liveness signal; a busy lead ignores pages). RED-provable NOW: scripts/s3b-lint.sh reds a silence-reaps straw-supervisor (./scripts/s3b-lint.sh --selftest ⇒ 3/3)."
  todo "S-4" "NOT BUILT — Criterion: the supervisor MUST log every sweep (a heartbeat outcome record). A silently-crashed daemon is otherwise indistinguishable from a quiet system. This answers 'who watches the watcher' mechanically: THE WATCHER'S HEARTBEAT IS AN OUTCOME RECORD, AND ITS ABSENCE IS THE ALARM."
else
  grep -qE 'MODAL|modal' "$SUP" && ok "S-3" "in-session blindness declared; modal ⇒ PAGE" || bad "S-3" "structural in-session blindness not declared"
  ./scripts/s3b-lint.sh "$SUP" >/dev/null 2>&1 && ok "S-3b" "page-deadline gates on a re-observe re-read, not silence (scripts/s3b-lint.sh)" || bad "S-3b" "disposition reachable from deadline-silence alone — it would reap a healthy long turn (scripts/s3b-lint.sh)"
  grep -qE 'heartbeat|sweep_log|IDL|idl' "$SUP" && ok "S-4" "sweeps emit a heartbeat/outcome record" || bad "S-4" "no sweep heartbeat — a crashed daemon looks like a quiet system"
fi

echo
echo "SHIP-GATE REQUIREMENT (desk-adopted, applies to EVERY check, not just these two)"
echo "  every check ships emitting {fired|passed|abstained|failed}; ALARM: abstained==100% over N≥10"
echo "  real invocations ⇒ inert BY CONSTRUCTION. Without it, 'correctly quiet' and 'structurally"
echo "  blind' are the same observation. (This alone would have caught cc-notify in hours, not a day.)"
echo
printf 'premortem-gate: %d met · %d failed · %d NOT BUILT\n' "$PASS" "$FAIL" "$TODO"
if [ "$FAIL" -gt 0 ] || [ "$TODO" -gt 0 ]; then
  echo "⇒ RUNTIME PHASE: NOT READY TO UN-HOLD. (Red here is not a bug — it is the bar.)"
  exit 1
fi
echo "⇒ every registered pre-mortem is mechanically satisfied; un-hold is defensible."
