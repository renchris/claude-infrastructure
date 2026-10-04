# Hostile review — "100 → 1000 concurrent agents on $200 Max accounts + local hardware"

**Verdict: infeasible as stated. Hardware is the fourth constraint, not the first.** Three
non-hardware walls each cap the plan below 1000 on their own: the trunk (hard), the quota
arithmetic (hard at 10–40 accounts), and the vendor's "ordinary, individual usage" contract
(terminal risk, not a cost). Oversight is already broken at 100.

## Ranked

### 1. One trunk + CAS landing caps the fleet at ~250 lands/day — HARD BLOCKER
- `scripts/ship-land.sh:41-66`: the gate runs **outside** the lock on the rebased tree; a sibling land
  during the gate ⇒ exit 42, re-rebase, up to 4 rounds, then a **statics-only** in-lock fallback
  (no tests). Measured `~/.claude/land.log` 2026-09-27→10-04 (n=675 attempts): **gate_s p50 338 s**,
  p90 2,039 s; **169 of 675 (25%) stale-gate rounds**; 314 landed; lock wait p50 0 s, hold p50 3 s.
- Poisson check: at the observed ~3 lands/h and T=338 s, P(stale)=1−e^(−0.28)=24% — matches 25%.
  At 10× demand (30/h) P(stale)=94% per round, P(land in 4 rounds)≈22%; the survivors land
  through the untested statics-only lane. **Max sustainable ≈ 1/T_gate ≈ 10/h ≈ 255/day for any N.**
- Demand: 70 lands/day today from ~5.8 working units ≈ 12/unit/day
  (`docs/research/breaking-the-ceiling-2026-08-19.md:20`). 1000 agents at measured duty 0.357 = 357
  working units ⇒ ~4,300 lands/day, **17× the ceiling**. Already 25 `revert` commits on `origin/main`
  in 30 days and 12 `postland-*` incident docs in `docs/research/` — quality falls before throughput.
- The lock is not the bottleneck (hold 3 s); **the gate duration is**. Only shorter gates or more
  trunks move this.

### 2. Quota: 10–40 accounts buys 22–88 working units, not 1000 — HARD at the stated budget
- Measured: one working unit burns **6.45%/day of one account's weekly meter**; one Max account
  sustains **2.21 continuously-working units** (`breaking-the-ceiling-2026-08-19.md:101,113,276`).
  1000 working units ⇒ **~450 accounts, ~$90K/mo**; 1000 resident agents at 0.357 duty ⇒ ~160
  accounts, ~$32K/mo. 10–40 accounts is 4–45× short.
- Subagents make it worse, not better: workflow/unnamed agents are **2.43–3.53× worse per quota
  point** than a pane (`:115,188`). "1000 cheap subagents" is the capped, expensive path.
- No escape hatch: overage is `org_level_disabled`, `can_purchase_credits=false` on all 4 (`:277`).
  Burn is unstable: GitHub #22435 reports 5.6–59.9%/h on one Max 20x plan.

### 3. Terms: Max is sold for "ordinary, individual usage"; enforcement is unilateral — TERMINAL RISK
- https://code.claude.com/docs/en/legal-and-compliance: *"Advertised usage limits for Pro and Max
  plans assume ordinary, individual usage"*; OAuth is *"designed to support ordinary use"*;
  *"Anthropic reserves the right to take measures to enforce these restrictions and may do so
  without prior notice."*
- https://www.anthropic.com/legal/consumer-terms (eff. 2025-10-08) §12: suspend/terminate *"at any
  time without notice"*, **no refund**. §2: no sharing/making the Account available to others.
  https://www.anthropic.com/legal/aup (eff. 2025-09-15): *"throttle, suspend, or terminate"*.
- Multiple accounts per person are **not** prohibited (no clause; Claude Code team's Thariq
  Shihipar, Feb 2026: *"It's not against terms of service to have multiple MAX accounts"* — via
  https://metricnexus.ai/blog/anthropic-banning-multiple-claude-accounts, secondary). But weekly limits
  were introduced explicitly against *"continuously in the background, 24/7"* use and sharing/reselling
  (https://techcrunch.com/2025/07/28/anthropic-unveils-new-rate-limits-to-curb-claude-code-power-users/),
  and Anthropic actioned **1.45M accounts** Jul–Dec 2025, 1,700 of 52K appeals overturned
  (https://www.anthropic.com/transparency/platform-security). A 40-account fleet on one IP/device is
  exactly the resale fingerprint; cross-account device coupling is already reported
  (https://github.com/anthropics/claude-code/issues/12786). Loss mode: all accounts at once, no refund.
- Friction: **3 accounts per phone number max**
  (https://support.claude.com/en/articles/8287232-verifying-your-phone-number) ⇒ 40 accounts need 14
  numbers — itself an abuse signal.

### 4. Oversight does not exist at 100, let alone 1000 — HARD on the operator's own rule
- Operator's real reach: **4–5 sessions at a 4-h tolerance** (`oversight-at-scale-2026-08-19.md`
  N9); 310 workflow agents fleet-wide started and never returned (N7); 1,172/1,172 escalations
  unread (N15). Memory `feedback-oversight-outranks-throughput.md`: capacity bought by removing the
  thing watched is rejected by this operator.
- Scaling the measured rates: 0.428 permission blocks/session-hour ⇒ **428/h at 1000**; paging only
  on >1 h stuck still yields **~33 pages/h** (vs 1.0/h at 30). The doc's best design (T3, §6) is
  rated "50+", not 1000, and its true stop is unbuilt.

### 5. Per-account concurrency caps — COST, unverified
- No official per-account session cap found; the "Max = 10 concurrent sessions" figure circulates
  only in unsourced third-party guides (e.g. https://mintlify.wiki/stoneforge-ai/stoneforge/guides/scaling).
  529 `overloaded` is capacity-side, retryable, uncorrelated with account
  (https://hn.svelte.dev/item/48624168). OAuth refresh herd: a fleet concentrated on few accounts
  fails as a **discontinuous account-wide logout** (`breaking-the-ceiling:276,383`).

## Ruled out
- "Scripted use violates Consumer Terms §3": Claude Code is the explicitly permitted surface; the
  live prohibition is non-Claude-Code harnesses (Jan 2026 OAuth lock-down).
- Hardware lag at 15 sessions: real, but more Macs fix only this one of five.

## What would change the verdict
Many trunks (or batched landing) + a per-wave quota budget + exception-oversight at T3 + an
Anthropic-sanctioned seat model (Team/Enterprise) instead of personal Max accounts. Without the
first and last, 1000 is a number, not a plan.
