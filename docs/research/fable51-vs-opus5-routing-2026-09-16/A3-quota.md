# A3 — The quota axis: does Fable 5.1 buy the fleet more work per week than Opus 5?

**Verdict: No, and it is not close. On this fleet the binding resource is a shared weekly bucket, Fable
is a SUB-CAP of that same bucket (not a separate one), and a percentage point spent on Fable buys
2.5–2.8× less work than a point spent on Opus 5. There is also a hard structural ceiling: Fable can
never consume more than 50 of an account's 100 weekly points, so it cannot be the fleet default
regardless of its quality.**

Written 2026-09-16 by a read-only subagent. Every claim below is tagged MEASURED (by us, this session)
/ QUOTED (vendor) / ASSUMED. Scratch data beside this file: `next2-minute-tokens.json`,
`next3-minute-tokens.json`, `next{2,3}-onlysegs.json`, `scan*.py`, `integrate*.py`.

---

## 1. The rendered readout, verbatim

`./bin/claude-accounts` (cached ≤90 s, 2026-09-16 22:26 local):

```
  Claude Max accounts                                           cached · Wed 22:26

  account    live  5h session ┆85%   ↻5h  weekly all       weekly Fable      ↻week
  next     ●    0  ········┆·   0%    ↻?  █████████▍  94%  ▋·········   7%      3d
  next4 ←➤ ●    5  ▏·······┆·   2% ↻3.6h  ███▉······  39%  █▎········  13%   3d 5h
  next3    ●    2  ▏·······┆·   2% ↻2.6h  ▌·········   6%  ··········   0%   5d 8h
  next2    ●    1  ██████▌·┆·  65% ↻2.2h  ██████████ 100%  ███████▌··  76%   2d 7h

  ◉ Fable permanent — standard Max/Team-Premium inclusion at ≤50% of weekly limits
  ➤ desk    → next4  weekly ↻ 3d 5h · 5h 2% · safe set · sticky  · 1 excluded
  ➤ general → next3  5h 2% · weekly 6% ↻ 5d 8h  · 2 excluded
  ➤ fable   → next3  Fable 0% ↻ 5d 8h · weekly 6%  · 2 excluded
  weekly drain — pp that DIE at reset (K=0.202 live · nowcast at the last 48h of pace):
    next3 strand ~55pp of 94 · p76 of its own 24h burns · start by T−29h (100h slack) · 5d left
    next no strand — on pace to fill the window · 3d left
    next4 no strand — on pace to fill the window · 3d left
    next2 no strand — on pace to fill the window · 2d left
  cache ≤90s old · --fresh for a live sweep
```

`./bin/claude-accounts --rank general` and `--rank fable`, verbatim:

```
### --rank general
claude-accounts: general excluded — next2=weekly-exhausted
route-meta: acct=next4 cliff_band=none cliff_h=511.2 cliff_at=2026-10-08T10:42:31.113000+00:00 quota_as_of=- quota_age_s=78 cached=1 yielded=0 k_src=panes k_cap=40 k_work=- k=5 k_stale_s=- k_eff=8 kwork_to=0 repick_ratio=4
next4 0.000081
next3 0.000052
next 0.000011
### --rank fable
claude-accounts: fable excluded — next2=fable-exhausted
route-meta: acct=next4 cliff_band=none cliff_h=511.2 cliff_at=2026-10-08T10:42:31.113000+00:00 quota_as_of=- quota_age_s=79 cached=1 yielded=0 k_src=panes k_cap=40 k_work=- k=5 k_stale_s=- k_eff=8 kwork_to=0 repick_ratio=4
next4 0.000059
next3 0.000027
next 0.000011
```

**Buckets the tool tracks (MEASURED — read from `bin/claude-accounts:1444-1458`, which parses
`claude.ai/api/oauth/usage`):** exactly three per account —
`session` (the 5-hour window), `weekly_all`, and `weekly_scoped` with display name `Fable`.
There is **no scoped 5-hour bucket** — the 5h window is model-agnostic.

Note the tell in the `--rank fable` line: next2 is reported `fable-exhausted` while its Fable bar reads
**76%**, not 100%. That is the coupling doing its work, and §2 explains it.

---

## 2. Fable is a SUB-CAP of the weekly bucket, not a separate bucket — and this is measured, not assumed

### QUOTED (vendor, authoritative)

Anthropic support, *"Claude Fable models on your plan"*
(https://support.claude.com/en/articles/15424964-claude-fable-models-on-your-plan), fetched today:

> "You can use up to 50% of your weekly usage limits on Fable models at no extra cost."
> "Fable models count toward your plan's usage limits … your use of other models draws from the same
> usage limits and you can never use more than your weekly limit."
> **"They draw from your plan's regular weekly usage limits and use them faster than other Claude models."**
> "When you reach your Fable limit, you can keep using Fable models with usage credits, or switch to
> another model to stay within your plan's usage limits."

The 2026-07-17 announcement (@claudeai): *"Beginning July 20, Claude Fable 5 will be included in all Max
and Team Premium plans, at 50% of limits."*

So the operational meaning of `frontier_access.source: plan-usage` / `"≤50% of limits"` is: **one weekly
bucket, of which at most half may be spent on Fable.** There is no second allowance.

### MEASURED (us, this session)

`~/.claude/logs/account-utilization.jsonl` — 28,572 samples carrying both `weekly_pct` and `fable_pct`,
4 accounts, 2026-08-10 → 2026-09-17.

1. **Invariant holds in 28,572 / 28,572 rows.** Rows where `fable_pct > 2×weekly_pct + 2` (which would
   refute the sub-cap): **0**. Rows where `weekly_pct < 0.5×fable_pct`: **2**, both `w=0 f=1`, i.e.
   integer rounding of a 1-point reading.

2. **The exchange rate is exactly 0.5 weekly-pp per Fable-pp**, read off a pure-Fable burn.
   next3, 2026-09-05, k=1, no other model in the window:

   ```
   03:45 w=0 f=1      05:30 w=2 f=4      06:44 w=3 f=5
   03:52 w=1 f=2      05:36 w=2 f=4      07:04 w=3 f=6
   04:27 w=2 f=3      06:38 w=2 f=4      07:17 w=3 f=6
   ```
   Ratio w/f oscillates 0.50–0.67 — which is what 0.5 looks like through integer rounding of two
   small counters.

3. **Confirmed at scale on a second account.** next2, 24 disjoint intervals (2.9 h) in which the only
   model with any tokens was `claude-fable-5-1`: **Δfable = 31 pp, Δweekly = 17 pp**. Predicted
   31 × 0.5 = 15.5 pp. Observed 17 pp.

4. **The ceiling is real and has been hit.** Highest `fable_pct` ever observed per account:
   `next 100% (weekly 95%)`, `next4 100% (weekly 89%)`, `next3 78% (weekly 91%)`, `next2 76% (weekly 99%)`.
   Two accounts have exhausted the Fable half outright.

5. **The router already encodes it** (`bin/claude-accounts:3481`):
   `f_eff = min(F["coupling"] * (1 - fable_pct/100), w_rem)` with
   `accounts.json frontier.coupling = 0.5` and the field's own comment:
   *"coupling = fable_cap/weekly_cap per SSOT '<=50% of weekly usage limits'"*.
   The `min(…, w_rem)` is why next2 reads `fable-exhausted` at 76% Fable — its weekly hit 100 first.

**Consequence — the structural ceiling.** A week spent entirely on Fable ends with `fable_pct = 100`
and `weekly_pct = 50`. Fable then locks out and the remaining 50 weekly points can only be spent on a
non-Fable model. **Fable cannot be the fleet's default model. It is arithmetically incapable of
carrying more than half a week's quota, so a "Fable-first" default is a plan that stops working on
Thursday and falls back to Opus anyway.**

---

## 3. Does a Fable token draw MORE weekly quota than an Opus token? MEASURED: yes, ~2.5–2.8×

This is the number the decision turns on, and it is the one nobody on this fleet had measured.

**Instrument.** For accounts next2 (`~/.claude-secondary`) and next3 (`~/.claude-tertiary`) I scanned
every transcript touched since 2026-09-01 (997 and 1,517 files), summed `message.usage` by model at
minute resolution, then integrated those tokens between consecutive `account-utilization.jsonl` samples
(gap ≤ 1 h, same weekly window, monotone counters). I then kept only **single-model intervals** — every
interval in which exactly one model produced any tokens.

**next2 — the clean arm** (its Opus-only set moved `fable_pct` by just 1 pp, so it is near-uncontaminated):

| | intervals | Δweekly | out-tok / 1pp weekly | fresh-in (in+cache-create) / 1pp | cache-read / 1pp | list-$ / 1pp |
|---|---|---|---|---|---|---|
| **Fable 5.1 only** | 24 (2.9 h) | 17 pp | **105,602** | 2,177,514 | 17,518,188 | **$36.87** |
| **Opus 5 only** | 635 (77.5 h) | 110 pp | **342,768** | 4,048,248 | 115,203,413 | **$91.47** |
| ratio (Opus buys more per pp) | | | **3.25×** | 1.86× | 6.58× | **2.48×** |

**next3 — the noisy second arm** (Fable set is only 2 pp of weekly; its Opus-only set moved `fable_pct`
by 17 pp, i.e. the transcript scan missed some Fable there, so read it as corroboration of DIRECTION
only):

| | intervals | Δweekly | out-tok / 1pp | fresh-in / 1pp | cache-read / 1pp | list-$ / 1pp |
|---|---|---|---|---|---|---|
| Fable 5.1 only | 16 (1.8 h) | 2 pp | 198,156 | 1,528,342 | 42,726,276 | $39.68 |
| Opus 5 only | 631 (76.3 h) | 82 pp | 398,821 | 4,061,699 | 150,507,554 | $110.61 |
| ratio | | | 2.01× | 2.66× | 3.52× | **2.79×** |

`list-$` uses the SSOT prices — Opus 5 `[5 / 25]`, Fable 5.1 `[10 / 50]`, cache-read Opus `$0.50`,
Fable `$0.25`, cache-create ASSUMED at 1.25× base input for both.

### The finding that kills the operator's premise

The premise under the question is *"Fable 5.1's cache reads are half the price of Opus 5's, so on
cache-read-dominated agentic sessions Fable's dominant input line is cheaper in absolute dollars."*
**That is true about dollars and false about quota, and on this fleet only quota is spent.**

If weekly quota were consumed in proportion to list dollars, the `list-$ / 1pp` column would be
**equal** for both models. It is not: **$36.87 vs $91.47** on next2 and **$39.68 vs $110.61** on next3.
Two independent accounts, same direction, same magnitude. A weekly point spent on Fable redeems for
roughly **40% (1/2.5)** of the list-price work that a point spent on Opus redeems for. The cheap
cache-read line does not come back as quota — the cache-read column is where Fable does *worst*
(6.58× and 3.52× fewer cache-read tokens per point).

### Corroboration from two independent sources

- **QUOTED, vendor:** *"they … use them faster than other Claude models."* Anthropic says the direction
  outright; our contribution is the size.
- **The operator's own launcher already believes it** — `~/.zshrc:489-491`, fired on any `claude`
  invocation selecting a `claude-fable-5*` model on a TTY:
  ```
  ⚠️  Fable 5 session — ~2× Opus burn/token against the plan window. Only with measured headroom
  (SSOT: ~/.claude/model-config.yaml frontier_access).
  ```
  That `~2×` was ASSUMED (it is the list output-price ratio, inherited from the retired `claude-fable`
  launcher on 2026-08-01). Our measurement says the true figure is **2.5–2.8× on a dollar basis and
  ~3× per output token** — i.e. the standing warning is right in direction and, if anything,
  understates it.

### What I could NOT determine, and why

- **The accounting rule itself is unpublished.** I inferred a per-token weight from an aggregate; I
  cannot see Anthropic's actual formula (normalised tokens? a model multiplier? a cost proxy?). The
  ratio is robust across two accounts and three normalisations, but it is an inference, not a spec.
- **Sample asymmetry.** 2.9 h / 17 pp of Fable against 77.5 h / 110 pp of Opus on the good arm.
  Integer-pp quantisation puts roughly ±6% on the Fable figure at 17 pp, more at next3's 2 pp.
- **Transcript coverage is not proof of total account draw.** Headless `-p` runs, Dynamic Workflow
  slots and anything that writes outside `<config_dir>/projects` are invisible to the scan.
  next3's Opus-only set is demonstrably contaminated this way (Δfable = 17 pp with 0 Fable tokens
  observed); next2's is not (Δfable = 1 pp), which is why next2 is the arm I would quote.
- **Per-TASK, not per-token.** Everything above is per token. A model that finishes a task in fewer
  tokens can be quota-cheaper at a worse per-token rate. §4 is where that is settled.

---

## 4. The arithmetic that decides it

Let **r** = weekly-quota drawn per token by Fable 5.1 ÷ the same for Opus 5. **MEASURED r ≈ 2.5 (range
2.0–3.3 depending on which token type you normalise on; 2.48 and 2.79 on the dollar basis).**

Let **t** = tokens Fable 5.1 @medium needs per task ÷ tokens Opus 5 @high needs per the same task.

> **Break-even: Fable is quota-neutral as a default only if t ≤ 1/r, i.e. Fable @medium must finish a
> task in ≈ 2.5× FEWER tokens than Opus 5 @high, at equal or better quality.**

What is known about **t**:

- **MEASURED (ours, `docs/research/fable51-effort-sweep-2026-09-10/README.md`, 45 cells, 2026-09-10):**
  Fable 5.1 median output tokens per cell — low 6,449 · medium 18,077 · high 24,252 · xhigh 62,062 ·
  max 118,365. Dropping Fable from high to medium saves **1.34×**, not 2.5×.
- **THE HOLE — there is no matched Opus 5 @high cell anywhere in this fleet's corpus.** The sweep's
  Opus reference is `claude-opus-5 @max` from the frozen codex-probe corpus and it carries no token
  count. So **t is UNMEASURED.** For the break-even to clear, Opus 5 @high would have to spend
  ≈ 45,000 output tokens on a cell Fable @medium does in 18,077 — i.e. Opus @high would have to be
  *more* verbose than Fable @xhigh. Nothing in the sweep suggests that, but nothing in it refutes it
  either.

And the quality side of "equal or better quality" points the wrong way for Fable:

- **MEASURED (ours, same sweep, 36 anchored defects, strict-majority recall):** Fable 5.1 low 6 ·
  medium 10 · high 10 · xhigh 9 · max 9/25 · Fable 5 @xhigh 9 · **Opus 5 @max 12**. Opus beat every
  Fable 5.1 effort. (Scope limit the lead already named: one task class, one sample per cell, recall
  only, and the Opus arm ran @max rather than our actual default @high.)

So the two multiplicands compose against Fable: **a ~2.5× worse quota rate × a token saving of at most
1.34× × a recall deficit.** Even under the most charitable assumption available — that Fable @medium
matches Opus @high on both quality and tokens per task — the fleet does **2.5× less work per week**.

**And then the ceiling in §2 applies on top:** even at break-even the arithmetic would only license
Fable for at most half of each account's weekly points before `fable-exhausted` forces the fallback.

---

## 5. Where this leaves the SSOT

**MEASURED, on the quota axis alone, nothing here supports moving the default off `claude-opus-5 @ high`.**
The case for Fable-as-default rests on a dollar comparison, and this fleet does not spend dollars —
`accounts.json spend.usage_credits_authorized = false`, four Max subscriptions, and the only scarce
thing is 400 weekly points a week. On that currency Fable is the expensive model, not the cheap one.

What the measurement *does* support, and is a genuine finding rather than a restatement:

1. **`~/.zshrc:490`'s `~2× Opus burn/token` is now MEASURED rather than assumed, and the honest number
   is 2.5–2.8×.** Worth correcting in place.
2. **The "Fable cache reads are cheaper" fact is true and irrelevant here.** It should be recorded as
   refuted *on the quota axis* wherever it gets written down, or the next session re-derives the same
   wrong conclusion from the same true premise.
3. **`frontier_access` staying opt-in, agent-escalated and spawn-capped is the correct shape** — it is
   what keeps Fable inside the half-bucket it can actually occupy.

**Not a recommendation this axis can make:** whether Opus 5's *effort* should move (high ↔ max ↔
medium). That is a pure quality/token question within one model at one quota rate, and the decisive
missing datum is the same one: no Opus 5 @high cell on the anchored corpus.

---

## 6. Open unknowns, stated so the next session does not re-derive them

1. **`t` — tokens per task for Opus 5 @high on the anchored corpus — is UNMEASURED.** Determined by:
   9 more cells, `claude -p --output-format json --model claude-opus-5 --effort high` over
   `docs/research/fable51-effort-sweep-2026-09-10/` (`run-arms.sh` already does this; the Opus arm is
   the one cell block it never ran). ~$20 and one evening. This closes both the break-even above AND
   the lead's own "our actual default was never in the grid" gap with one run.
2. **The quota accounting rule is unpublished.** Our r is inferred from aggregates. Determined by:
   a controlled A/B — one account, one idle window, a fixed synthetic prompt run N times on each model
   with the 90 s utilisation cache forced fresh. Feasible; costs real quota; nobody has done it.
3. **Whether the 5-hour bucket weights models too.** The API exposes no scoped 5h limit
   (`bin/claude-accounts:1444-1446` picks `session` unscoped), so Fable's 5h draw is unobservable
   through this instrument. Determined by: the same controlled A/B, reading `session_pct`.
4. **Whether Fable 5.1's cheaper cache-read price is reflected in quota at all.** Our cache-read column
   says it is not (Fable does *worst* there), but that column is also where the Fable sample is
   thinnest. Determined by: (2).
