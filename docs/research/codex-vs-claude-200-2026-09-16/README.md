# Which $200/mo plan gets more usage: OpenAI Pro 20x (GPT-6 Astra) or Claude Max 20x (Fable 5.1)?

**Date:** 2026-09-16 · **Question (operator):** *"Investigate if $200 Codex plan for Astra or
$200 Claude plan for Fable 5.1 gets more usage/value."*
**Method:** 5 parallel web-research arms (A–E, verbatim below) + 6 live local measurements on
this box. Every number carries the instrument that produced it.

---

## VERDICT

**The volume question is a near-tie and it is not what decides this. Two facts decide it.**

1. **The OpenAI $200 tier is not purchasable.** OpenAI paused new sign-ups *and upgrades* to
   ChatGPT Pro $200 (Pro 20x) on **2026-09-10**, citing GPT-6 Astra demand — including upgrades
   from Plus and from Pro $100. Existing seats keep working; no reopen date published. This box
   holds **Plus**, not Pro (`~/.codex/auth.json` → `chatgpt_plan_type: "plus"`), so for this
   operator the Codex $200 plan is **not a live option today**. (Arm A fact #3, arm E §0.)
2. **On raw metered volume the two plans land within ~30% of each other**, both dominated by
   cached input, so no volume argument is strong enough to overturn (1):

   | | measured weekly consumption at a full window | instrument |
   |---|---|---|
   | **Claude Max 20x** (1 seat) | **~4.6B tokens** · **107 agent-hours** · 7.4–10.0M output tok | this box, 3,044 transcripts, deduped on `message.id` |
   | **OpenAI Pro 20x** (1 seat) | **~3.9B tokens** (1.212B in one day = 31pp of the weekly meter) | `codex#43222`, rollout JSONL, `plan_type: "pro"` |

**So: keep the Claude seats. The marginal $200 cannot buy a Codex Pro seat, and if it could, it
would buy roughly the same volume with worse cache economics for this specific workload.**

---

## The six local measurements

| # | Finding | Value | Instrument |
|---|---|---|---|
| 1 | API-equivalent value extracted per Claude seat | **$3,849/wk** vs $46.15/wk price = **83×**; conservative floor excluding cache-reads **33×** | `measure-weekly-value.py`, official price cards |
| 2 | Composition of that value | cache-read **60%** · cache-write 34% · output **6%** | same |
| 3 | Agent-hours delivered per Claude seat | **107 h/wk** (fleet 428 h/wk across 4 seats) | per-session active-minute union over 7d |
| 4 | Astra **is** entitled on ChatGPT **Plus** today | probe returned 150/150 words, 15,454 in (12,160 cached) / 1,079 out (893 reasoning) | `codex exec --model gpt-6-astra` on the 0.154 binary |
| 5 | Both frontier models were blocked locally by **stale CLIs, not entitlement** | Astra needs codex **≥0.153** (installed 0.147 → server 400 "requires a newer version"); Fable 5.1 needs CC **≥2.1.255** (bare `claude` is 2.0.5 → 400 `claude_code_version_too_old`) | both 400s captured |
| 6 | The Fable sub-meter is **partially decoupled** from the general weekly meter | 1pp of Fable costs **≤0.59pp** of weekly; **35%** of intervals where Fable rose showed *zero* weekly movement (n=438) | `~/.claude/logs/account-utilization.jsonl`, 28,444 rows |

⚠️ #6 is an **upper bound**: `d(weekly)` includes concurrent non-Fable work, so true coupling is
≤0.59. It does **not** contradict Anthropic's documented "50% of your weekly limit … drawn from
the same pool" (arm B fact 2.4) — a scoped ceiling inside one pool is exactly what a sub-1.0
coupling looks like when the meters are priced differently per model.

🚨 **One local measurement CONFLICTS with a vendor doc and the conflict is unresolved.**
`docs/research/orchestration-units-2026-08-19/A6-quota-economics.md` fits the 5-hour meter at
R²=0.974 with a **zero** coefficient on cache-read across a 0→735M-token span. Anthropic's
`code.claude.com/docs/en/costs` says cache reads **do** draw on subscription limits. Both may be
true (free on the *5-hour* meter, charged on the *weekly* one) — **nobody has fitted the weekly
meter.** That is the single highest-value open measurement here, because cache-read is 60% of
the value in #2. Do not quote either side as settled.

---

## What actually separates them (from the arms)

- **Overage is API-priced on BOTH.** Anthropic usage credits bill "at standard API rates"; OpenAI
  credits derive to **exactly $0.04** on 10/10 rate-card rows. Neither subscription makes the
  marginal token cheaper than the API — the $200 buys an included block and nothing else. (E §2.)
- **Gating asymmetry, temporary and in OpenAI's favour.** Codex lead Tibo Sottiaux, 2026-08-25,
  verbatim: *"in Codex they apply specifically to weekly usage limits. And we also don't have 5h
  limits for both Pro plans. The Pro 20X is quite precisely 20X the usage of the Plus
  subscription."* So Pro gates **once** (weekly) where Anthropic gates **three ways** (5h ×
  weekly × Fable-50%). For bursty parallel fan-out that is the largest structural advantage
  either side holds — and it is explicitly "for the upcoming months". (E §4.)
- **Claude Code weekly limits shrank ~17% on 2026-09-14** (the +50% promo ended; a permanent +25%
  replaced it). Two days before this research. Explains the fleet sitting at 84–94%. (C finding 2.)
- **Headless `claude -p` is inside the flat $200 — a reversal, therefore perishable.** Anthropic
  announced a separate metered credit for Agent SDK / `claude -p` / Actions on 2026-05-14 for a
  2026-06-15 start, then **cancelled it on the day it was due**, confirming those surfaces "continue
  drawing from your Pro, Max, Team, and Enterprise subscription limits exactly as before" with
  "advance notice before any future change". This is the **single largest value term** on the
  Anthropic side for this fleet's dispatch architecture. Re-check before relying on it. (E §0.)
- **Capability is a statistical tie; token efficiency is not.** Neutral instruments cannot
  separate Astra and Fable 5.1 on coding/agentic quality, but Astra completes comparable coding-agent
  tasks in **~58%** of Fable 5.1's tokens. That is an API-economics fact that does **not** transfer
  cleanly to a subscription meter. (D headline.)
- **Cache-read price, the dominant term here:** Fable 5.1 **$0.25/Mtok** vs Astra **$1.00/Mtok**
  (and $2.00 above 272K input). 4× in Anthropic's favour on 60% of the spend. (B 3.2, A #16–17.)

## What is NOT settled

- The weekly-meter cache-read coefficient (above). Highest-value open measurement.
- Whether the 2026-08-11 REJECT of Codex for `roles.research_adversarial`
  (`docs/research/codex-probe-w3-verdict-2026-08-11.md`) still holds. That probe judged
  **gpt-5.6-sol**; **Astra did not exist** (released 2026-09-03). The rejection does not cover it,
  and nothing has re-run it.
- OpenAI publishes **no** conversion from $200 to tokens: message-count bands per 5h (as ranges),
  a credit rate card, and a purchased-credit price — but never how many credits a plan *includes*,
  nor the weekly cap. Anyone quoting "the $200 plan = N tokens" is inferring. (A §4.)
- ⚠️ Anthropic Consumer ToS §3 (eff. 2025-10-08) prohibits accessing the Services "through
  automated or non-human means … except when you are accessing our Services via an Anthropic API
  Key". Recorded as a fact of the terms, against which the 2026-06-15 clarification above sits.
  Not legal advice; flagged because this fleet is automated.

## Reproducing

```bash
python3 docs/research/codex-vs-claude-200-2026-09-16/measure-weekly-value.py   # per-seat $/wk
/Users/chrisren/.claude/bin/claude-accounts --readout                          # live meters
```

Arms A–E are the verbatim research deliverables, each with its own sourcing table and its own
"unknowns / not published" section. Read A §3 (the credit→dollar derivation) and E §4 (the
gating asymmetry) first — they carry the two facts most likely to change a decision.
