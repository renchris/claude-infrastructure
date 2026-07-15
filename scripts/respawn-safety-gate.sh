#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the `<check> && ok || bad` reporter idiom is intentional —
# ok/bad/todo always return 0 (printf + arithmetic), so SC2015's "C runs when A true but B fails" cannot occur.
#
# respawn-safety-gate — the RED-provable un-hold bar for RESPAWN-AS-PROTOCOL (B1-a, RS-a..RS-f).
# Sibling of wait-safety-gate.sh / reaper-safety-gate.sh / comms-safety-gate.sh / limit-reset-safety-gate.sh,
# same discipline: criteria REGISTERED before the build; turning this green IS "ready".
#
# ── THE EVIDENCE THAT IS THE SPEC (agent-teammate-spawn-2-1-183 §5/§5e, W3+W4+fable4 sessions) ─────────
# On the CC 2.1.183 runtime, NO mid-stream lead→teammate message has ever demonstrably been processed:
# 7/7 teammates stalled post-instruction (W3); two idle panes sat with ZERO activity after a "spawn 2 GO"
# mail; binding conditions sent with sha-ack requests were shipped violated. The proven rule — "spawn-
# boundary GO = RESPAWN, never a message" — lived only as PROSE in a memory file (the §3g PROSE-MISTAKEN-
# FOR-MACHINERY class: a capability that exists only as a prescription in a document read as a report).
# This build makes it machinery: bin/cc-respawn — TaskStop the target → checkpoint-recover its branch/wip
# refs → fresh-spawn a successor with the GO/ruling BAKED INTO the brief. The mailbox is never relied on.
#
# ── HARNESS-TOOL SPLIT (what a shell tool can and cannot do) ───────────────────────────────────────────
# TaskStop and Agent-spawn are HARNESS tools — only the lead session can invoke them. cc-respawn is the
# deterministic, effect-verified protocol AROUND them: prepare (checkpoint + brief-compose, fail-closed)
# → [lead: TaskStop] → verify-stopped (effect-read, never trust the tool result) → [lead: Agent spawn]
# → verify-spawned (effect-read). Every phase writes an outcome record. The two harness steps are the
# lead's; everything checkable is the tool's.
#
# ⚠️ RED TODAY BY DESIGN (bin/cc-respawn unbuilt). Exit: 0 = every criterion met · 1 = not ready.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2
PASS=0; FAIL=0; TODO=0
ok(){   printf '  ✅ %-5s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
bad(){  printf '  ⛔ %-5s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
todo(){ printf '  ⏳ %-5s %s\n' "$1" "$2"; TODO=$((TODO+1)); }

TOOL=bin/cc-respawn

echo "respawn-safety-gate — spawn-boundary-GO-is-a-respawn bar (RS-a..RS-f registered; RED until $TOOL built)"
echo

if [ ! -f "$TOOL" ]; then
  todo "RS-a" "NOT BUILT — GO-IN-BRIEF, FAIL-CLOSED AT THE PRODUCER: prepare REFUSES (exit 2) a respawn with no --go ruling, and the composed successor brief CONTAINS the GO text verbatim. The naive form (GO by mailbox) is UNEXPRESSIBLE: the tool has no send-to-target code path at all — delivery rides the spawn, the only channel W4 evidence says works."
  todo "RS-b" "NOT BUILT — CHECKPOINT-BEFORE-STOP (Invariant 7 / capture-before-notify): prepare captures the target worktree's WIP (tracked+untracked, temp-index plumbing, zero working-tree touch) into refs/respawn/<member>/<ts> + refs/wip/<member>/LAST BEFORE any stop directive is emitted; the ref survives even if the stop never happens. RED-provable: dirty worktree → prepare → ref exists containing the uncommitted blob."
  todo "RS-c" "NOT BUILT — EFFECT-VERIFIED STOP: verify-stopped proves the target DEAD by {pid,start-time} identity (kill -0 + ps lstart), NEVER trusting a claimed TaskStop result. RED-provable: a live pid with matching start → exit 5 LOUD (still alive); a dead pid → 0; a recycled pid (live, different start) → 0 (the original is gone)."
  todo "RS-d" "NOT BUILT — SUCCESSOR CONTINUITY: the composed brief embeds worktree + branch + checkpoint ref + the recovery recipe, so the successor recovers WIP without the dead predecessor's context. RED-provable: prepare with no --worktree → REFUSED; a composed brief greps GREEN for all four continuity fields."
  todo "RS-e" "NOT BUILT — OUTCOME RECORDS (abstention law): every phase writes {prepared|refused|stop-verified|stop-failed|spawn-verified|spawn-missing} to ~/.claude/respawn/ (CC_RESPAWN_RECORDS_DIR) — a silent respawn protocol cannot be audited."
  todo "RS-f" "NOT BUILT — EFFECT-VERIFIED SPAWN: verify-spawned proves a successor process for --member is LIVE (ps command-line carries --agent-name <member> — the memory-verified method), exit 5 LOUD when absent. A respawn is not delivered until the successor is SEEN running."
else
  "$TOOL" selftest >/dev/null 2>&1 && ok "RS" "cc-respawn selftest GREEN — RS-a GO-in-brief fail-closed, RS-b checkpoint-before-stop, RS-c effect-verified stop ({pid,start} identity, live→5/dead→0/recycled→0), RS-d continuity fields, RS-e outcome records on every path, RS-f effect-verified spawn all fire RED-provably" || bad "RS" "cc-respawn selftest not green — an RS-a..f RED-proof does not fire"
  if [ -f tests/cc-respawn.bats ] && command -v bats >/dev/null 2>&1; then
    bats tests/cc-respawn.bats >/dev/null 2>&1 && ok "RS-cli" "tests/cc-respawn.bats GREEN — CLI exit-code contract (0 ok · 2 refuse · 5 verify-fail) regression-pinned" || bad "RS-cli" "tests/cc-respawn.bats RED"
  else
    todo "RS-cli" "NOT BUILT — bats CLI-contract regression (tests/cc-respawn.bats)"
  fi
fi

# RS-blind — DECLARED (composition rule): between verify-stopped and verify-spawned the lead itself could
# die, leaving a stopped teammate and NO successor. That window is covered by the OUTER layers: the
# checkpoint ref persists (this build), the P8 registry + reconciler surface the missing pid, and the
# supervisor pages — the respawn protocol never becomes the only thing holding the wave.
echo
echo "  🕳  RS-blind DECLARED: lead-death between stop and spawn → covered by checkpoint ref (durable),"
echo "      P8/reconciler divergence, and the supervisor page (never-stuck composition)."

echo
printf 'respawn-safety-gate: %d met · %d failed · %d NOT BUILT\n' "$PASS" "$FAIL" "$TODO"
if [ "$FAIL" -gt 0 ] || [ "$TODO" -gt 0 ]; then
  echo "⇒ RESPAWN-AS-PROTOCOL: NOT READY. (Red here is not a bug — it is the bar. Build $TOOL to RS-a..RS-f.)"
  exit 1
fi
echo "⇒ every registered respawn-safety criterion is mechanically satisfied; spawn-boundary GO delivery is machinery, not prose (activation-free: cc-respawn is lead-invoked tooling, no daemon/hook — symlink rides the consolidated bundle)."
