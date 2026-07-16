#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `<check> && ok || bad` reporter idiom is intentional —
# ok/bad/todo always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# route-safety-gate — the RED-provable un-hold bar for MODEL/EFFORT AUTO-ROUTING (B1-b, RT-a..RT-f).
# Sibling of wait/reaper/comms/limit-reset/respawn-safety gates, same discipline: criteria REGISTERED
# before the build; turning this green IS "ready".
#
# ── THE GAP THAT IS THE SPEC (roadmap B1-b) ────────────────────────────────────────────────────────────
# Model routing lives as a MANUAL table (BUILD_LOG § Model routing) + the model-config.yaml SSOT + the
# operator's head. Two silent-failure incidents (frontier-window-ssot-discipline memory) came from COPIES
# of that state: a hardcoded JUL7 window and a comment-matching awk. bin/cc-route makes the routing a
# live-read primitive: slot descriptor → {model, account, LEAD effort} — with the window/quota reads
# DELEGATED to the reference implementations (claude-accounts frontier_window() + --route contract),
# never re-derived, never hardcoded.
#
# ── THE TWO EDGES THAT MUST BE RED-PROVEN (roadmap-named) ──────────────────────────────────────────────
# 1. FRONTIER-WINDOW EDGE (Fable-close mid-wave): a fable slot when the window shuts → an EXPLICIT,
#    reason-carrying Opus fallback — the SSOT-designed degrade ("post-window degrades to fallback, say
#    so in reports"), never a silent model swap. Each invocation is a fresh live read, so mid-wave close
#    = the next call already routes the fallback.
# 2. QUOTA CLIFF: the general route returning policy-none (every account capped) is NOT a routing input —
#    it is a STOP: exit 4, no plan, "run /limit-recover". Never silent down-tier, never fire blind.
#
# ⚠️ RED TODAY BY DESIGN (bin/cc-route unbuilt). Exit: 0 = every criterion met · 1 = not ready.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0; TODO=0
ok(){   printf '  ✅ %-6s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-6s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
todo(){ printf '  ⏳ %-6s %s\n' "$1" "$2"; TODO=$((TODO+1)); }

TOOL=bin/cc-route

echo "route-safety-gate — never-misroute bar (RT-a..RT-f registered; RED until $TOOL built)"
echo

if [ ! -f "$TOOL" ]; then
  todo "RT-a" "NOT BUILT — SLOT → COMPLETE PLAN: each slot {lead|judgment-dense|transcription|adversarial} yields {model, account, lead_effort, reason}. The emitted effort is the LEAD's (teammate effort inherits the lead on 2.1.183 — there is no per-member surface; agent-teammate-spawn-2-1-183 §2)."
  todo "RT-b" "NOT BUILT — FRONTIER-WINDOW EDGE: a fable slot when --route fable returns none (window closed / no entitlement / fable-exhausted) → an EXPLICIT Opus-fallback plan CARRYING the reason; the fable model id never appears in a fallback plan. Mid-wave close is covered by construction: every call is a fresh live read."
  todo "RT-c" "NOT BUILT — QUOTA CLIFF: --route general policy-none (exit 2: every account capped) → cc-route exits 4 with a /limit-recover directive and NO plan on stdout. A cliff is a STOP, never a silent down-tier, never a blind fire."
  todo "RT-d" "NOT BUILT — DATA-UNAVAILABLE: quota unreadable (--route exit 3) → cc-route exits 3, NO plan. Routing on unknown quota is firing blind."
  todo "RT-e" "NOT BUILT — SSOT DISCIPLINE: model ids parsed LIVE from model-config.yaml with key-anchored, value-bounded parses (frontier_access.model, roles.lead_default); window state DELEGATED to claude-accounts (the reference frontier_window()). Parse failure → exit 3 LOUD — never default open OR closed, never hardcode (two real incidents: frontier-window-ssot-discipline)."
  todo "RT-f" "NOT BUILT — OUTCOME RECORDS (abstention law): every plan, fallback, cliff-stop, and refusal appends a record to ~/.claude/route/ (CC_ROUTE_RECORDS_DIR) — routing that cannot be audited cannot be trusted."
else
  "$TOOL" selftest >/dev/null 2>&1 && ok "RT" "cc-route selftest GREEN — slot plans, frontier-edge fallback (reason-carrying, fable-id-free), quota-cliff stop (exit 4 + limit-recover, no plan), data-unavailable stop, SSOT parse fail-loud, outcome records all fire RED-provably" || bad "RT" "cc-route selftest not green — an RT-a..f RED-proof does not fire"
  if [ -f tests/cc-route.bats ] && command -v bats >/dev/null 2>&1; then
    bats tests/cc-route.bats >/dev/null 2>&1 && ok "RT-cli" "tests/cc-route.bats GREEN — CLI exit-code contract (0 plan · 2 usage · 3 blind/no-data · 4 cliff) regression-pinned" || bad "RT-cli" "tests/cc-route.bats RED"
  else
    todo "RT-cli" "NOT BUILT — bats CLI-contract regression (tests/cc-route.bats)"
  fi
fi

# RT-blind — DECLARED (composition rule): cc-route plans a SPAWN; it cannot see mid-TURN quota burn
# (a wave that exhausts Fable between spawns). COVER: claude-accounts' 90s cache TTL keeps every next
# call near-live; the E4 numeric-succession law (Fable ≥96% → re-route) is the lead's standing rule;
# and the cliff protocol stops the wave at the hard edge.
echo
echo "  🕳  RT-blind DECLARED: mid-turn quota burn between spawns → covered by the 90s-fresh live read on"
echo "      every call, the E4 numeric-succession law, and the quota-cliff stop."

echo
printf 'route-safety-gate: %d met · %d failed · %d NOT BUILT\n' "$PASS" "$FAIL" "$TODO"
if [ "$FAIL" -gt 0 ] || [ "$TODO" -gt 0 ]; then
  echo "⇒ MODEL/EFFORT AUTO-ROUTING: NOT READY. (Red here is not a bug — it is the bar. Build $TOOL to RT-a..RT-f.)"
  exit 1
fi
echo "⇒ every registered route-safety criterion is mechanically satisfied; routing is a live-read primitive, not a manual table (activation-free: lead-invoked tooling — symlink rides the consolidated bundle)."
