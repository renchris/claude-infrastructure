#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `<check> && ok || bad` reporter idiom is intentional —
# ok/bad/todo always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# reaper-safety-gate — the RED-provable un-hold bar for the REAPER-BIRTH-GRACE build (R-a/b/c). Sibling of
# scripts/wait-safety-gate.sh and premortem-gate.sh, same discipline: the desk registers RED-provable
# criteria BEFORE the build, and turning this green IS "ready". Desk GO ruling 2026-07-14.
#
# ── THE INCIDENT THAT IS THE SPEC ──────────────────────────────────────────────────────────────────────
# The TeammateIdle auto-shutdown hook (~/.claude/hooks/teammate-auto-shutdown.sh) prematurely REAPED a
# HEALTHY teammate ~3-4 min after spawn: a clean tree + no `.teammate-busy` marker read as "idle" — but a
# JUST-BORN worker is indistinguishable from a FINISHED one by tree-state alone. Caught by the lead's
# effect-sweep, not any harness signal. Zero loss (workaround held). This is Invariant-7's REAPER family,
# new member — a reaper keyed on IDLENESS-AT-A-GLANCE with NO grace window at birth (the exact hole P8's
# NO-RENDER? grace closed for registration; the same grace discipline as L4-b and wait-safety).
#
# ── BUILD-vs-ACTIVATION SPLIT (C10 — what makes this desk-signable) ────────────────────────────────────
# The fix is a STANDALONE decision module scripts/reap-guard.sh (decide REAP|DEFER + reason + outcome
# record); the live hook CALLS it at ACTIVATION. The agent builds + RED-proves the guard and hands the
# operator an activation script — it NEVER edits the live hook in place. That split keeps the C10 line.
#
# ── COMPOSITION PRE-CLEARANCE (desk record) ───────────────────────────────────────────────────────────
# R-a's birth-grace blindness — a genuinely-hung JUST-BORN teammate WITHIN the grace window — is COVERED by
# the L2 wait-contract DEADLINE (the lead's wait on that teammate carries its own timeout → re-observe) and
# by L1 at exit-instant if it dies. So the grace window cannot hide a real early hang; another layer holds it.
#
# ⚠️ RED TODAY BY DESIGN (scripts/reap-guard.sh unbuilt). Redness IS "not ready"; green IS the definition of
# ready. Exit: 0 = every registered criterion met · 1 = not ready (with reasons).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0; TODO=0
ok(){   printf '  ✅ %-5s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-5s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
todo(){ printf '  ⏳ %-5s %s\n' "$1" "$2"; TODO=$((TODO+1)); }

GUARD=scripts/reap-guard.sh

echo "reaper-safety-gate — never-reap-the-living bar (R-a/b/c registered; RED until scripts/reap-guard.sh built)"
echo

if [ ! -f "$GUARD" ]; then
  todo "R-a" "NOT BUILT — BIRTH GRACE (age-keyed): never reap within N min of spawn (the guard reads the teammate's spawn timestamp). RED-provable: a teammate spawned < N min ago, clean tree, no marker → the guard must DEFER (grace-held); the current bare-idleness heuristic REAPS it. Fixture: spawn-time < N min → assert defer, not reap."
  todo "R-b" "NOT BUILT — EFFECT-READ predicate (not tree-cleanliness alone): the reap predicate reads WORK PRODUCTS since spawn (commits on the teammate branch, checkpoint/wip refs, file mtimes). A clean tree with NO products yet = just-born (DEFER); a clean tree AFTER products = finished (REAP). RED-provable: two clean-tree fixtures — {no products since spawn} → DEFER vs {products then clean} → REAP — a tree-only heuristic cannot tell them apart."
  todo "R-c" "NOT BUILT — REAPER ABSTENTION LAW (no silent reap): the guard emits an outcome record {reaped|deferred|grace-held} per decision. The current hook reaps SILENTLY — and a silent reaper is the D9 shape with a body count (a reaper that cannot be audited). RED-provable: after a reap OR a defer, an outcome record exists on disk; a silent decision produces none."
  todo "R-*" "NOT BUILT — scripts/reap-guard.sh absent (a STANDALONE decide REAP|DEFER module with --selftest). The live hook must never be edited in place — the guard is called at ACTIVATION (C10). Build to this gate, then hand the operator an activation script."
else
  ./scripts/reap-guard.sh --selftest >/dev/null 2>&1 && ok "R" "reap-guard --selftest GREEN — R-a birth-grace (young → defer), R-b effect-read (products-then-clean → reap vs no-products → defer), R-c outcome-record (every reap/defer recorded, no silent reap) all fire RED-provably" || bad "R" "reap-guard --selftest not green — an R-a/b/c RED-proof does not fire"
fi

echo
printf 'reaper-safety-gate: %d met · %d failed · %d NOT BUILT\n' "$PASS" "$FAIL" "$TODO"
if [ "$FAIL" -gt 0 ] || [ "$TODO" -gt 0 ]; then
  echo "⇒ NEVER-REAP-THE-LIVING: NOT READY. (Red here is not a bug — it is the bar. Build scripts/reap-guard.sh to R-a/b/c.)"
  exit 1
fi
echo "⇒ every registered reaper-safety criterion is mechanically satisfied; the birth-grace guard is build-complete (activation C10-queued)."
