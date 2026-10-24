---
status: in-progress
---

# Usage levers — getting more work from the same 4 Max 20x accounts

Scope (frozen): act on the verified usage-efficiency levers surfaced by `claude -p /usage`
(research: `docs/research/usage-levers-2026-10-23/REPORT.md`, round 2 in `round2/REPORT.md`),
implementing what clears 90% conviction and running the one cheap test each remaining lever needs,
each wave landed via `/ship` and converged live.

## Phase 0 — Agent Team Orchestration

**Execution locus per wave**

| Wave | Locus | Why (T/L only) |
|---|---|---|
| W0 research + this plan | L | docs only, already in the lead's hands; no code |
| W1 binary pin + "reads are free" doc reword + log-only Workflow shadow hook | S | — |
| W2 cache-read quota probe | S | — |
| W3 idle-cache redesign (shadow mode) | S | — |
| W4 context-recycle thresholds | S | — (gated) |

**Task size per unit:** 40–150K output tokens (≈30–75 min, 3–6 files). W1 is three small tasks in
one unit because each alone is under 20K; W2 and W3 are one task each.

**Team / roles:** each S session leads its own team only if it ends up touching 2+ independent
files sets; W1's three tasks are disjoint files (bin/cc-notify; docs + two script headers; one new
hook + its bats) so it may run them as three teammates.

**Dependency graph**
- W1, W2: no blockers — fire in parallel.
- W3: blockedBy W2 (decides which weighting the break-even uses); its Phase-0 counts may run now.
  W2 DONE 2026-10-24: meter weights apply.
- W4: blockedBy W2 (only worth doing if cache reads are charged — round 2 says 90%, one short).
  W2 DONE 2026-10-24: charged (98%), W4 unblocked.
- Deny-mode Workflow hook: blockedBy W1 shadow data (3 days, ≈2026-10-27).

**Worktrees:** one per S session, branch `usage-levers-w<N>`, created by `handoff-fire.sh --worktree`.

**Spawn order:** W1 ∥ W2 now → W3 after W2 reports → W4 after W2 reports, if charged.

**Lead context budget + succession point:** the lead holds ≥50% of its window for deciding; it
recycles (`handoff-fire.sh --recycle`) once W1 and W2 have reported and their results are folded
into this plan, or at 35% fill while idle, whichever comes first.

## W0 — research + plan — DONE (`5b52c6fab`, 2026-10-24)
- `/usage` is free and diagnostic, not a saving; it double-counts subagent transcripts copied
  between accounts (next4 7-day requests ~46% high).
- Ranked levers and the binary hazard: `docs/research/usage-levers-2026-10-23/REPORT.md`.
- Round 2 convictions: cache reads charged 90% (weekly ≈0.0048 pp/Mtok on Opus 5.5, 28–35% of the
  meter); lean enforcement 65% (saving ≈3–4%/week, not 5.2%); idle-cache fixes 60% (both fixes as
  first written are wrong). Dropped: skill-listing trim, watcher timeout wakes, peer-message
  batching (each <1%).

## W1 — binary pin, doc reword, Workflow shadow hook (S, unblocked)
1. **Binary pin.** `bin/cc-notify:682` takes `command -v claude` first, which resolves to
   `~/Library/pnpm/claude` 2.0.5 in scripts; `cc-claude-bin` (→ `~/.claude-293/.../claude`) is only
   the fallback. Swap the order (keep the `CC_CLAUDE_BIN` seam). Audit the other bare callers the
   round-1 scan named: `scripts/research-kit/router.py:546`, `scripts/rm-preempt-probe.sh:47`.
   Pin with a bats case that puts a fake old `claude` first on PATH.
2. **Doc reword (95%).** "Cache reads are free/≈0" → "discounted, ≈0.005 pp/Mtok weekly on Opus
   5.5". Sites: `docs/plans/USAGE_TELEMETRY_100P.md:152,179`,
   `docs/research/token-efficiency-2026-09-23/REPORT.md:20,318`, the `bin/cc-quota-price`
   docstring, the `hooks/cache-expiry-warning.sh` header. Keep the 0.049 constant (it is an upper
   bound, which still holds).
3. **Shadow hook (log-only).** PreToolUse on `Workflow` that parses `tool_input.script` for
   `agent(` calls without `agentType`, and logs per call: would-deny verdict, what a rewrite would
   add, whether the slot's brief names commit/ship/Skill/MCP, and hook latency (a Workflow hook that
   times out at 5 s lets the call through — measured round 2). Never denies. Registration may need
   a settings.json change, which is the operator's (migration class c10): if so, write the
   migration and file it with `cc-backlog needs … --class needs-human`.
- Goal: the bats file for each task passes and `/ship` prints LANDED, content-verified.

## W2 — cache-read quota probe — DONE (2026-10-24): reads are CHARGED, 98%
- Ran on next3 from a next session: 1,149 tool-free `-p` calls re-reading one 458,656-token cached
  context (1h tier, 0 writes in the window) = **527.0M cache reads**. Meters, baseline → after:
  5h **1 → 21** (wire), weekly **12 → 16** wire / **13 → 16** endpoint, so +3 to +4pp. "Free" predicted
  +0.006 / +0.001pp. The only other live next3 session added ≤0.07pp 5h in the window.
- Weights at large context: 5h ≈0.038 pp/Mtok (≈1.9× round 2), weekly 0.0057–0.0076 pp/Mtok
  (≈1.2–1.6× fit4's 0.0048). Open confound: the context was above 200k, so the excess may be a
  long-context premium. A same-size probe below 200k would split it (≈0.7pp weekly, not run: cap reached).
- Spent ≈3–4pp of next3's week (stopped by the 4pp guard on the final batch). Decision 1: 90% → 98%.
- **Unblocks:** W4 (its gate was "reads charged"); W3 uses round 2's meter-weight branch, with reads
  ≈1/32–1/43 of a cache write, not 0.
- Report, readings table, scripts and data: `docs/research/usage-levers-2026-10-23/round3-probe.md`,
  `round3/`.

## W3 — idle-cache redesign, shadow mode (S, unblocked by W2: use the meter-weight branch)
- Cause (reproduced): the mailbox watcher (`--timeout 14340`) exits silently on timeout, and the
  3300 s wake floor stands down while that hook is registered (`hooks/session-continue.sh:688`);
  a keepalive added beside it does nothing because `mailbox-wake-arm.sh:203` exits when a watcher
  is armed. Prototype: an idle-scoped keepalive timed from the gap start, waking about once per gap.
- Subagent rule: a blanket deny on Bash `timeout > 270 s` would hit 5,941 harmless calls to save 250
  rebuilds; narrow it, run it as count-only for a week, accept only if wrongly denied calls cost
  <0.2% of weekly usage.

## W4 — context-recycle thresholds (S, unblocked: W2 found reads charged)
- Only if W2 confirms reads are charged. Main sessions run a 1M window at median 231k / p90 459k;
  the recycle rails act at 250k–750k. Do not force busy sessions to drain; the candidate is an
  earlier idle recycle. Estimated 3–8.5% of weekly usage.
