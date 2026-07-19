#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `<check> && ok || bad` reporter idiom is intentional —
# ok/bad/todo always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# limit-reset-safety-gate — the RED-provable un-hold bar for the LIMIT-RESET AUTO-RESUME POLLER (B1-d,
# LR-a..LR-h). Sibling of wait-safety-gate.sh / reaper-safety-gate.sh / comms-safety-gate.sh, same
# discipline: criteria REGISTERED before the proof exists; turning this green IS "ready".
#
# ── THE GAP THAT IS THE SPEC (docs/plans/LIMIT_RESET_AUTO_RESUME_POLLER.md) ────────────────────────────
# A session killed by a 5-hour/weekly usage limit stays IDLE FOREVER: the keepalive only nudges RUNNING
# panes; lr-audit parses resets_at_utc but schedules nothing; no launchd job is limit-aware. This is the
# largest hole in the never-stuck-idle invariant (B1-c states: a limit-parked session is neither
# progressing, nor at an owned wait, nor at a designed gate, nor terminated — it is SILENTLY idle with
# work remaining, for hours, exactly when nobody is watching).
#
# ── RECONCILED STATE (2026-07-15) ──────────────────────────────────────────────────────────────────────
# scripts/limit-recover/lr-reset-poller.sh EXISTS (built 2026-07-11/12) and ran a LIVE notify-only cycle
# 2026-07-12 (PARKED 6802c9b8 → READY notified — poller.log). What was MISSING: any RED-provable proof
# (zero tests, no gate row), and the activation is C10-queued (plist NOT in ~/Library/LaunchAgents).
# This gate registers the proof obligations; tests/lr-reset-poller.bats discharges them.
#
# ── BUILD-vs-ACTIVATION SPLIT (C10) ────────────────────────────────────────────────────────────────────
# The agent builds + proves the poller; the OPERATOR installs the launchd plist and (after eyeballing a
# live cycle — already satisfied by the 2026-07-12 log) sets LR_POLLER_AUTOFIRE=1. Both hand-steps ride
# the consolidated /tmp/wiring-all.sh bundle. The agent NEVER loads launchd or flips autofire itself.
#
# Exit: 0 = every registered criterion met · 1 = not ready (with reasons).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0; TODO=0
ok(){   printf '  ✅ %-7s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-7s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
todo(){ printf '  ⏳ %-7s %s\n' "$1" "$2"; TODO=$((TODO+1)); }

SUITE=tests/lr-reset-poller.bats
POLLER=scripts/limit-recover/lr-reset-poller.sh

echo "limit-reset-safety-gate — never-park-forever bar (LR-a..LR-n registered; RED until $SUITE proves them)"
echo

if [ ! -f "$POLLER" ]; then
  bad "LR-*" "$POLLER ABSENT — the poller itself is gone; the limit-park hole is fully open"
elif [ ! -f "$SUITE" ]; then
  todo "LR-a" "NOT PROVEN — DETECT+LEDGER: a transcript whose tail is a genuine limit isApiErrorMessage (error=rate_limit, reset-bearing) → a PARKED ledger row carrying {kind, reset_at_utc}. RED-provable: fixture transcript → row exists with the parsed reset."
  todo "LR-b" "NOT PROVEN — NO-FIRE-BEFORE-RESET: a parked row whose reset_at_utc is in the FUTURE → no resume, no launcher, no notification (the poller waits)."
  todo "LR-c" "NOT PROVEN — HEADROOM GUARD: reset passed but the account still capped (session_pct/weekly_pct ≥ 100) → WAIT logged, ZERO fire — never resume into a still-capped account (the quota-cliff law: stop, never fire blind)."
  todo "LR-d" "NOT PROVEN — NOTIFY-ONLY DEFAULT + NOTIFY-ONCE: LR_POLLER_AUTOFIRE unset → no session is ever spawned; exactly ONE notification per parked session across N ticks (no per-tick spam)."
  todo "LR-e" "NOT PROVEN — AUTOFIRE + IDEMPOTENT LEDGER: LR_POLLER_AUTOFIRE=1 → launcher written + window-open attempted + the row moves parked/→resumed/ so a second tick NEVER double-fires."
  todo "LR-f" "NOT PROVEN — RUNAWAY CAP: more ready rows than MAX_PER_RUN → only MAX_PER_RUN fire this tick, CAP logged, the rest deferred to the next tick (a detector false-positive cannot spawn unbounded sessions)."
  todo "LR-g" "NOT PROVEN — KILL-SWITCH: LR_POLLER_DISABLED=1 → exit 0 immediately, zero ledger writes, zero fires."
  todo "LR-h" "NOT PROVEN — OUTCOME RECORDS (abstention law): every decision path logs {PARKED|READY|WAIT|RESUMED|CAP} to poller.log — a silent decision is a reaper-shaped detector that cannot be audited."
  todo "LR-i" "NOT PROVEN — RECURRENCE: the resumed/ marker is EVENT-keyed, never sid-keyed-forever. A session resumed once MUST re-park on its NEXT limit event (newer reset ⇒ REPARK); the same event never double-fires. The naive sid-keyed skip is fatal for multi-day runs (a 5h limit recurs every window)."
  todo "LR-j" "NOT PROVEN — HEADLESS SPAWN (P0-8): LR_POLLER_SPAWN=tmux → a parked, reset-passed session resumes via a DETACHED tmux session running the launcher (no Aqua/iTerm2 window) → the ledger moves parked/→resumed/ and the mechanism is recorded. The GUI-only resume is blind in a LaunchDaemon/SSH/pre-login context (P0-10)."
  todo "LR-k" "NOT PROVEN — MONTHLY-SPEND PACKET (P0-8 / I-LIVE-1): a billing-plane kill (\"You've hit your monthly spend limit\", NO reset) → a class-B decision packet via cc-decide (cross-account-continuation default, operator decision #3), and the session is NEVER parked (nothing to wait for) and NEVER silently dropped (the pre-2026-07-19 poller's session|weekly pre-filter dropped it entirely)."
  todo "LR-l" "NOT PROVEN — SPEND IDEMPOTENCY: the class-B spend packet is opened EXACTLY ONCE across N ticks (marker-keyed under spend-packet/) — no per-tick cc-decide spam."
  todo "LR-m" "NOT PROVEN — AUTO FALLBACK: LR_POLLER_SPAWN=auto with the GUI unavailable (osascript window-open fails) → the resume FALLS BACK to tmux rather than logging ERROR and stranding the session — a resume is never silently failed when a headless path exists."
  todo "LR-n" "NOT PROVEN — SPEND TEAMMATE-SKIP: a teammate (agentName) monthly-spend session opens NO packet (recovery is lead-owned; the lead's own spend kill carries the packet) — teammate-skip logged."
else
  if command -v bats >/dev/null 2>&1; then
    if bats "$SUITE" >/dev/null 2>&1; then
      ok "LR-a..n" "$SUITE GREEN — detect+ledger, no-fire-before-reset, headroom guard, notify-only default + notify-once, autofire idempotency, runaway cap, kill-switch, outcome records, event-keyed recurrence, headless tmux spawn (LR-j) + auto→tmux fallback (LR-m), monthly-spend class-B packet (LR-k) + idempotency (LR-l) + teammate-skip (LR-n) all proven (fixtures = real transcript bytes; stubs for claude-accounts/osascript/tmux/cc-decide; suite RED-proven against the as-shipped poller: LR-c blind headroom + LR-i forever-skip fired, and LR-j/k RED against the GUI-only + session|weekly-only poller)"
    else
      bad "LR-a..n" "$SUITE RED — a registered limit-reset criterion fails (run: bats $SUITE)"
    fi
  else
    bad "LR-*" "bats unavailable — the proof cannot run (install bats-core)"
  fi
fi

# LR-blind — DECLARED, not closed (composition rule: every blindness names its cover):
#   The FABLE-scoped limit message's verbatim shape has never been captured (no real fixture exists).
#   lr-audit classifies by prefix ("You've hit your session|weekly limit…"); IF the Fable message carries
#   the weekly prefix it parks as kind=weekly (covered). IF it has a novel shape it classifies
#   other_api_error → NEVER PARKED → this poller is blind to it. COVER: the session renders STALL?/idle on
#   cc-board and the page-only supervisor pages it (the never-stuck composition holds through a different
#   layer, at page latency instead of reset latency). OBLIGATION: the first real Fable-limit capture must
#   be fixture-ized into $SUITE (turning this declared blindness into a proven row).
echo
echo "  🕳  LR-blind DECLARED: fable-scoped message shape unverified — covered by the weekly prefix if it matches,"
echo "      else by the supervisor stall page (never-stuck composition). Fixture-ize on first real capture."

echo
printf 'limit-reset-safety-gate: %d met · %d failed · %d NOT PROVEN\n' "$PASS" "$FAIL" "$TODO"
if [ "$FAIL" -gt 0 ] || [ "$TODO" -gt 0 ]; then
  echo "⇒ LIMIT-RESET AUTO-RESUME: NOT READY. (Red here is not a bug — it is the bar. Prove LR-a..LR-h in $SUITE.)"
  exit 1
fi
echo "⇒ every registered limit-reset criterion is mechanically proven; the poller is build-complete (activation C10-queued: plist install + LR_POLLER_AUTOFIRE=1 are operator hand-steps in wiring-all.sh)."
