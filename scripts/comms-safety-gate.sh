#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `<check> && ok || bad` reporter idiom is intentional —
# ok/bad/todo always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# comms-safety-gate — the RED-provable un-hold bar for the COMMS build (F1..F5). Sibling of wait-safety-gate
# and reaper-safety-gate, same discipline: RED-provable criteria registered BEFORE the build; turning this
# green IS "ready". Operator-directed (100th-percentile, comms edition), desk-relayed 2026-07-15.
#
# ── THE INCIDENT THAT IS THE SPEC ──────────────────────────────────────────────────────────────────────
# W5 lead #3's TERMINAL announce used `SendMessage` (teammate-scope only — the desk is NOT a teammate, so the
# target was UNRESOLVABLE); it SILENTLY degraded to passive disk-truth, and the desk learned of the ship
# 50 min late FROM THE OPERATOR. The desk's own L2 wait-contract re-observe fired 2 min after — it worked,
# it was just hourly-tuned. Root: the successor-fire payload DROPPED the back-channel block (F3). The lesson
# is delivery≠processing INVERTED: disk-truth is a RELOAD signal, not a WAKE — a TERMINAL event demands an
# ACTIVE, VERIFIED announce. Never wait on the dead → and never let COMPLETION go silent either.
#
# ── BUILD-vs-ACTIVATION SPLIT (C10) ────────────────────────────────────────────────────────────────────
# Build + RED-prove the tools/lints; wire them into the live exit/ship recipes at ACTIVATION (the agent
# hands the operator an activation script; it never edits the live recipe machinery in place).
#
# ⚠️ RED TODAY BY DESIGN (F1..F5 unbuilt). Redness IS "not ready". Exit: 0 = every criterion met · 1 = not ready.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0; TODO=0
ok(){   printf '  ✅ %-5s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-5s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
todo(){ printf '  ⏳ %-5s %s\n' "$1" "$2"; TODO=$((TODO+1)); }

ANNOUNCE=bin/cc-announce
PAYLOAD_LINT=scripts/payload-lint.sh

echo "comms-safety-gate — never-let-completion-go-silent bar (F1..F5 registered; RED until built)"
echo

# ── F1 — cc-announce: a role-resolving, VERIFIED, never-silent announce primitive ─────────────────────
if [ ! -f "$ANNOUNCE" ]; then
  todo "F1" "NOT BUILT — bin/cc-announce: role-token → RESOLVE (registry / self-close chain) → cc-notify VERIFIED submit → retry ONCE → on failure write a LOUD alarm record (NEVER a silent degrade like SendMessage did). RED-provable (--selftest): an UNRESOLVABLE / undeliverable target → an alarm record exists on disk AND a non-zero exit (never silent success); a resolvable target → a VERIFIED delivery. This is the mechanical announce the exit/ship recipes call so an announce is never 'remembered'."
else
  ./bin/cc-announce --selftest >/dev/null 2>&1 && ok "F1" "cc-announce --selftest GREEN — resolve→verified→retry→LOUD-alarm-on-failure (never silent degrade)" || bad "F1" "cc-announce --selftest not green"
fi

# ── F2 — channel-ladder law (E5 addition): met when F1 IMPLEMENTS the ladder (VERIFIED-or-alarm) + F3/a
#         lints a SendMessage terminal-announce RED + §8.5 E5 DOCUMENTS the law. ─────────────────────────
AUDIT=docs/research/W0-W3_INTERVENTION_AUDIT.md
f2_f1=0; [ -f "$ANNOUNCE" ]     && ./bin/cc-announce --selftest    >/dev/null 2>&1 && f2_f1=1
f2_f3=0; [ -f "$PAYLOAD_LINT" ] && ./scripts/payload-lint.sh --selftest >/dev/null 2>&1 && f2_f3=1
f2_e5=0; [ -f "$AUDIT" ] && grep -q '### 8.5' "$AUDIT" && grep -qiE 'channel.?ladder' "$AUDIT" && f2_e5=1
if [ "$f2_f1" = 1 ] && [ "$f2_f3" = 1 ] && [ "$f2_e5" = 1 ]; then
  ok "F2" "channel-ladder law: F1 cc-announce implements the ladder (VERIFIED-or-alarm) · F3/a lints a SendMessage terminal-announce RED · §8.5 E5 documents it (a TERMINAL event REQUIRES a VERIFIED announce; disk-truth is a RELOAD not a WAKE)"
elif [ "$f2_f1" = 0 ] || [ "$f2_f3" = 0 ]; then
  todo "F2" "NOT BUILT — channel-ladder law depends on F1 (ladder impl) + F3/a (SendMessage lint) + §8.5 E5 doc. Now: F1:$f2_f1 F3/a:$f2_f3 E5-doc:$f2_e5. SendMessage = TEAMMATE-scope ONLY; ladder cc-notify(full-uuid) → mailbox-only → alarm; a TERMINAL event REQUIRES an active VERIFIED announce (disk-truth is a RELOAD, not a WAKE)."
else
  bad "F2" "channel-ladder law: F1 + F3/a green but §8.5 E5 not documented in $AUDIT — document the law, then F2 goes green."
fi

# ── F3 — successor-fire payload lint (the ROOT of this incident) ──────────────────────────────────────
if [ ! -f "$PAYLOAD_LINT" ]; then
  todo "F3" "NOT BUILT — scripts/payload-lint.sh: a successor-fire payload (the /tmp/fire-*.txt / handoff prompt) WITHOUT the BACK-CHANNEL BLOCK (a cc-notify line + the desk full-uuid) lints RED — this succession DROPPED it, and that is the incident's ROOT. RED-provable (--selftest): a payload fixture missing the cc-notify+desk-uuid block → RED; one carrying it → GREEN; a missing file → LOUD (exit 2)."
else
  ./scripts/payload-lint.sh --selftest >/dev/null 2>&1 && ok "F3" "payload-lint --selftest GREEN — a back-channel-less successor payload lints RED (the incident root, closed)" || bad "F3" "payload-lint --selftest not green"
fi

# ── F4 — event-adaptive contract deadlines ────────────────────────────────────────────────────────────
todo "F4" "NOT BUILT — EVENT-ADAPTIVE deadlines: the desk's wait-contract / reconciler sweep TIGHTENS to ~900s during EXIT SEQUENCES (the 50-min window was tuning, not architecture). RED-provable: with an exit-sequence flag set, the effective deadline/sweep cadence is ~900s (not the 3600s hourly default); without it, the default. (Extends L2/L4 — the deadline is an INPUT, not a constant.)"

# ── F5 — completion-push ──────────────────────────────────────────────────────────────────────────────
todo "F5" "NOT BUILT — COMPLETION-PUSH: program-terminal detection → an OPERATOR push. The rule existed but was STARVED of input; F1 (cc-announce) feeds it. RED-provable: a program-terminal completion event → a push/announce fires (a record exists), verified via cc-announce; the terminal event is never silent. Wire into the exit recipe at ACTIVATION (C10)."

echo
printf 'comms-safety-gate: %d met · %d failed · %d NOT BUILT\n' "$PASS" "$FAIL" "$TODO"
if [ "$FAIL" -gt 0 ] || [ "$TODO" -gt 0 ]; then
  echo "⇒ NEVER-LET-COMPLETION-GO-SILENT: NOT READY. (Red here is not a bug — it is the bar. Build F1..F5.)"
  exit 1
fi
echo "⇒ every registered comms-safety criterion is mechanically satisfied; completion cannot go silent (activation C10-queued)."
