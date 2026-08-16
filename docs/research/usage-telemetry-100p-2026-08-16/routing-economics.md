---
axis: "A6 — Model and effort routing economics, and the quality floor that forbids penny-pinching"
status: complete
date: 2026-08-16
headline: "Effort is a 5.6x lever on reasoning depth and a 14-point lever on cost — because 87% of a turn's marginal cost is conversation cache, not output — so every effort-downgrade is the worst trade on the board; and the Fable 50% arbitrage is refuted (Fable draws weekly quota in proportion to its list price and costs 3.1x an Opus turn realized), while the premise that the Fable lane sits idle is a post-reset snapshot artifact: the four accounts peaked at 91/92/100/85% weekly and 60/39/64/33% of the Fable sub-cap in the cycle that ended this week."
load_bearing_claim: "Output tokens are 13.1% of the marginal cost of an Opus-5 turn (cache read 62.7%, cache creation 24.1%; n=65,904 turns) — therefore effort, which moves ONLY output tokens, cannot be a material cost lever, and the entire low/medium/high/xhigh ladder spans a 14-point cost band at fixed context while spanning 5.6x in thinking tokens."
---

# A6 — Routing economics and the quality floor

## Headline

**Stop treating effort as a cost knob: it is not one.** Measured over 157,038 assistant turns
carrying a durable `effort` field, an Opus-5 turn's marginal cost is **13.1% output tokens, 62.7%
cache read, 24.1% cache creation** — and effort moves only the output component. Holding
conversation context fixed, sliding the entire ladder `low → xhigh` moves marginal cost by
**−9.6% to +4.4%** (a 14-point band) while moving thinking tokens **5.6×** (210 → 1,173 per turn).
So the cheapest configuration that is iso-quality at the 100th percentile is, for every reasoning
class, **the highest effort you can express**: `xhigh` costs +4.4% over `high` at fixed context and
buys +33% thinking. The 2026-08-01 `max → high` flip was **asserted, not measured** — the SSOT says
so in its own comment ("the guide's STARTING POINT, not a measured optimum") — and it did land
(max's share of Opus-5 turns fell 78.1% → 9.1%) with a realized −15.3% output/turn and **flat
visible output** (146 → 143 tokens/turn), which is evidence of iso-*length*, not iso-*quality*; no
quality panel was ever run on Opus 5. Separately, the **Fable 50% arbitrage is refuted**: an
independent regression of the weekly bucket against transcript token cost puts Fable's weekly draw
per list-dollar at **1.27× Opus (90% CI 0.79–1.88)** — consistent with dollar-parity metering,
with only 4% bootstrap mass below the 0.75 needed for any discount at all — and a *realized* Fable
turn costs **$0.6145 vs $0.1970** for Opus-5@high, i.e. **3.1×**, not 2×. Fable's "50% of limits"
is a **sub-cap, not a discount**, and every Fable dollar charges **both** buckets (confirmed: β
estimated from the weekly bucket, 0.0186, matches β implied by the Fable bucket's own slope ÷ 2,
0.0190 — 2% apart). Finally, the axis premise that "an entire discounted lane sits idle" is a
**post-reset snapshot artifact**: over the 5,013-record utilization time series the four accounts
peaked at **91 / 92 / 100 / 85%** weekly and **60 / 39 / 64 / 33%** of the Fable sub-cap in the
cycle that ended on 15–16 August. Quota is scarce here, not abundant — but it is being spent on
**context**, which is where the only real economy lives.

---

## Findings

| # | Claim | Evidence (command / file:line / number + denominator) | Status | Coverage |
|---|---|---|---|---|
| **F1** | Output tokens are **13.1%** of an Opus-5@high turn's marginal cost; cache read is **62.7%**, cache creation **24.1%**, fresh input **0.05%**. | `/tmp/eff_*.json` roll-up: `$in 0.0001 · $cc 0.0475 · $cr 0.1236 · $out 0.0259 = $0.1970/turn`, n=**65,904** turns. Priced at `model-config.yaml:pricing_per_mtok` `claude-opus-5:[5,25]`, cache-write ×1.25, cache-read ×0.1. | **MEASURED** | 35% file sample of 4 config dirs (1,190 of ~3,404 jsonl); 157,038 assistant turns |
| **F2** | The effort ladder is a **5.6× lever on thinking tokens** and a **14-point lever on cost**. Opus-5 thinking tokens/turn: low 210 · medium 636 · **high 884** · **max 1,058 (×1.20)** · **xhigh 1,173 (×1.33)**. At fixed context the same ladder spans **−9.6% (low) to +4.4% (xhigh)** of marginal $/turn. | Thinking tokens derived as `output_tokens − (text_chars + tool_use_json_chars)/3.6`; insensitive to the divisor — the max/high ratio is 1.19–1.21 and xhigh/high 1.32–1.33 across cpt ∈ {3.0,3.3,3.6,4.0,4.4}. Cell n: high 65,904 · max 61,368 · xhigh 8,374 · medium 896 · low 154. | **MEASURED** (ratio), **INFERRED** (absolute token split — chars→tokens conversion) | same sample |
| **F3** | **`xhigh` costs MORE thinking than `max` on Opus 5** (1,173 vs 1,058 tok/turn, ×1.33 vs ×1.20). The enum's nominal ceiling is not the observed ceiling. | Same table. Both cells are large (8,374 / 61,368). ⚠️ **Confounded**: efforts were not randomly assigned — `xhigh` is opt-in via `claude-x` for work judged harder, and `max` was the *default* pre-2026-08-01, so `max`'s cell is a whole-fleet task mix. The confound pushes xhigh's number **up**, so ×1.33 is an upper bound and the true xhigh/max ordering is not established. | **INFERRED** | same sample |
| **F4** | The `max → high` flip was **ASSERTED, not measured** — and the SSOT says so itself. | `model-config.yaml` `effort_defaults.default`: *"This is the guide's STARTING POINT, not a measured optimum — a real per-class sweep is still owed (docs/research/opus5-adaptation-2026-08-01.md §D3)"*. `opus5-adaptation-2026-08-01.md:102` heads §D3 "**PARTLY DONE**". The only measured effort certification in the repo (`~/.claude/model-routing-freewin-probe.md` T1, probe `wf_771c1e9f-644`) is explicitly **model-scoped to Opus 4.8** and found xhigh *regressing* vs max on synthesis and mechanical-search. | **MEASURED** (documentary) | n/a — direct quote |
| **F5** | The flip **took**, and its realized effect was −15.3% output/turn with **flat visible output**. Opus-5 turns: Jul 21–31 `max`=78.1%, out/turn **1,207**, visible 146 → Aug 11–20 `high`=85.8%, out/turn **1,022**, visible **143**. Thinking/turn 1,061 → 879 (−17.2%). | `/tmp/eff3_*.json` date×effort×model roll-up; n = 44,654 / 65,259 / 26,794 Opus-5 turns per band. | **MEASURED** | same sample |
| **F6** | Flat visible output across the flip is evidence of **iso-length, not iso-quality**. No Opus-5 quality panel has ever been run at any effort. | `~/.claude/model-routing-freewin-probe.md` — every certified panel (T1, T2, T2-re-probe, effort grid, T4) ran on Opus **4.8** or scored Opus-5 only as a **cost anchor** in a Fable comparison. Positive control: the file *does* record a completed Opus-5 arm (T4, 2026-08-11), so the absence is of an Opus-5 *effort* panel specifically, not of Opus-5 evidence generally. | **MEASURED** (documentary) | n/a |
| **F7** | **Fable's "50% of limits" is a SUB-CAP, not a discount.** Per list-price dollar, Fable draws weekly quota at **1.27× Opus** (bootstrap median; 90% CI **[0.79, 1.88]**, n=564 hourly observations, 2,000 resamples). `P(ratio<0.75)=0.040` — the 0.5 discount hypothesis is outside the interval. | Pooled 2-hour-window least squares `ΔW_pp = α·Opus$ + β·Fable$` over `~/.claude/logs/account-utilization.jsonl` × transcript token cost, 4 accounts × 6 days. α=0.00711, β=0.00905 pp/list-$. | **MEASURED** | 100% of the 6-day utilization log (5,013 records); 100% of transcripts with mtime ≥ Aug 9 |
| **F8** | Every Fable dollar charges **both** buckets, and the fable-scoped bucket is exactly **half** the weekly bucket — the `coupling: 0.5` model in `accounts.json` is measurement-consistent. | Two independent estimates of β agree to 2%: from the **weekly** bucket regression β=0.01859; from the **Fable** bucket's own slope ÷ 2, β=0.01897 (lag-0 fit). `accounts.json:frontier.coupling = 0.5`; `bin/claude-accounts:2096` `f_eff = min(F["coupling"]*(1−fable_pct/100), w_rem)`. | **MEASURED** | as F7 |
| **F9** | A **realized** Fable turn costs **3.1×** an Opus-5@high turn ($0.6145 vs $0.1970), not 2×: it carries 1.37× the cache read (337K vs 247K tok/turn) and 2.1× the output (2,182 vs 1,036). | `/tmp/eff_*.json`, n=7,199 Fable@max turns vs 65,904 Opus-5@high turns. | **MEASURED** | same sample |
| **F10** | The "idle Fable lane / under-utilized weekly windows" premise is a **post-reset snapshot artifact**. Peak weekly utilization in the last complete cycle: `next` **91%** · `next2` **92%** · `next3` **100%** (hit the wall 2026-08-11) · `next4` **85%**. Peak Fable sub-cap: **60 / 39 / 64 / 33%**. | `~/.claude/logs/account-utilization.jsonl`, segmented by `weekly_reset_at`; 5,013 records, 2026-08-10T05:58 → 2026-08-16T10:33 UTC. The 1–4% readings quoted in the brief are all from segments that began after resets on Aug 15–16. | **MEASURED** | 100% of the log's window (6 days, 4 accounts) |
| **F11** | **A usage TIME-SERIES store DOES exist**, contradicting the brief's "none found". `~/.claude/logs/account-utilization.jsonl`, 1.37 MB, 5,013 records, one row per account per sweep with `session_pct`/`weekly_pct`/`fable_pct` + absolute reset stamps. | `bin/claude-accounts:2231` `UTIL_PATH = $CC_UTIL_LOG or ~/.claude/logs/account-utilization.jsonl`; written on the fresh-sweep path, rate-limited to one batch per `min_interval_s`. Positive control for the negative search: the brief's grep for `*usage*`/`*quota*` cannot match a file named `account-utilization.jsonl`. | **MEASURED** | n/a |
| **F12** | Fable is at **14.97%** of fleet output tokens (Aug 10–16) — the second-largest lane, not a dormant one. Opus 84.95%, **Haiku 0.06%**, **Sonnet 0.01%**. | All usage rows in files with mtime ≥ Aug 9 across all 4 config dirs: opus 88.98M out / fable 15.69M / haiku 0.06M / sonnet 0.01M. | **MEASURED** | 100% of recently-touched files; 92,930 usage rows |
| **F13** | The **certified Sonnet-5 free win has never been realized at scale**. `roles.workflow_synthesis_worker: claude-sonnet-5` (certified 2026-07-01, ties Opus-4.8@max on hard synthesis briefs) accounts for **537 of 157,038** assistant turns (0.34%) and **0.01%** of output tokens — because it is realizable only inside Dynamic Workflows, which the fleet barely runs. | `model-config.yaml:roles.workflow_synthesis_worker` + the model-share census. | **MEASURED** | same sample |
| **F14** | The Sonnet-5-vs-Opus finding the brief cites (**"≤ Opus 4.8 quality AND ~15% pricier at inherited-max effort"**) is a **2026-06-30 Artificial-Analysis figure, superseded in this repo's own file the next day**, and has **never** been re-run against Opus 5. | `~/.claude/commands/research.md:87` carries the 15% claim. `~/.claude/model-routing-freewin-probe.md` "CRITICAL CORRECTION (effort grid, 2026-07-01)": at equal `max` effort Sonnet-5 **ties** Opus-4.8 (0 reliable Opus wins; 3/3 hard-brief ties, both 12/12 excellent) at ~2–3× lighter quota. Realized marginal cost here: Sonnet-5@high **$0.1028/turn** vs Opus-5@high **$0.1970** (n=444 vs 65,904). | **MEASURED** (documentary + cost); the Opus-**5** comparison is **unmeasured** | n/a |
| **F15** | The freewin probe **was run**, repeatedly, and is at `~/.claude/model-routing-freewin-probe.md` (34,285 B, mtime 2026-08-11). Certified: T1 (`verify_judge: xhigh` free win, Opus 4.8) · T2 + effort grid (Sonnet-5@max adopted for the Workflow synthesis slot) · T3 (applied) · T4 (`gpt-5.6-sol` **rejected** for `research_adversarial`). **T5 is OPEN and is the highest-value open routing question in the file**: Opus-5 vs Fable-5 at *matched* effort. | The file's own status block and § "Target T5". T4 found Opus-5 beating Fable-5 on recall 13 v 9 of 36, non-overlap 5 v 1, unique hits 2 v 0, at half the list price — **but not at equal effort** (Fable @xhigh, Opus @max), so it cannot separate "Opus 5 > Fable 5" from "max > xhigh". | **MEASURED** (documentary) | n/a |
| **F16** | **Thinking text is not recoverable from transcripts** — it is stripped to `""`, leaving only the encrypted `signature`. Any per-effort thinking figure must be derived from `output_tokens`, never read. | Every `{"type":"thinking"}` block inspected has `thinking` of `len=0` and a `signature` of 680–9,344 chars. Positive control: `output_tokens`, `effort` (top-level, per assistant record), and `message.model` **are** durably present on 157,038 of 157,038 sampled turns. | **MEASURED** | same sample |
| **F17** | A weekly window is worth roughly **$8.4K–$14K of Opus-5 list-price-equivalent per account** (≈$34K–$56K/week fleet-wide). | `100/α`: α = 0.0119 pp/$ from the 6 per-reset segment fits (→ $8,400), α = 0.00711 from the pooled hourly 2-h-window fit (→ $14,060). Reported as a range because the two estimators disagree by 1.7×. | **INFERRED** | as F7 |
| **F18** | **Haiku has never been probed in this fleet.** No Haiku arm exists in any certified probe, and its routed slot (`roles.research_retrieval: claude-haiku-4-5`, "Explore tier, 25% slot") produced 0.06% of output tokens. Positive control: `~/.claude/agents/` contains four model-pinned agent definitions (`deep-research: opus`, `deep-research-sonnet: sonnet`, `research-decomposition-critic: sonnet`, `frontier-derivation: opus`) — **none pins Haiku**. | `model-config.yaml:roles.research_retrieval`; `grep -m1 '^model:' ~/.claude/agents/*.md`. | **MEASURED** | n/a |

---

## Method

**Corpus and sampling.** Four real config dirs — `~/.claude` (account `next`; `~/.claude-next` is a
symlink whose `projects/` points here, verified with `readlink`), `~/.claude-secondary` (`next2`),
`~/.claude-tertiary` (`next3`), `~/.claude-quaternary` (`next4`) — mapped from
`accounts.json:accounts[].config_dir`. De-duplication is structural, not heuristic: the four dirs
scanned are the four `realpath` targets, and the `~/.claude-next*` aliases were resolved before
scanning.

Two scans:

1. **Effort/model census** (F1–F6, F9, F12–F14, F16, F18). A fixed-seed 35% file sample per dir
   (`random.seed(11)`), **1,190 of ~3,404** `.jsonl` files, yielding **157,038** assistant turns
   carrying a top-level `effort` field. Per turn I recorded `usage.{input,output,cache_creation,
   cache_read}_tokens`, `message.model`, `effort`, and the character lengths of `text` blocks,
   `tool_use.input` JSON, and `thinking.signature`. Line-level prefilter on the literal `"effort"`
   before `json.loads` — this is what made a 7.3 GB corpus tractable.
2. **Quota-draw regression** (F7, F8, F10, F17). 100% of `.jsonl` files with mtime ≥ 2026-08-09
   across all four dirs (**92,930** usage rows, Aug 10–16), hour-bucketed by model family and
   priced from `model-config.yaml:pricing_per_mtok` with cache-write ×1.25 and cache-read ×0.1;
   joined to 100% of `~/.claude/logs/account-utilization.jsonl` (**5,013** records).

**Thinking-token derivation.** `thinking` text is empty in transcripts (F16), so thinking tokens are
`output_tokens − (text_chars + tool_use_json_chars)/3.6`. The ratios reported are stable across
divisors 3.0–4.4 (max/high 1.19–1.21; xhigh/high 1.32–1.33) because visible output is only 10–15%
of `output_tokens`; the **absolute** per-rung figures inherit the divisor's error and are labelled
INFERRED.

**Fable metering.** Model: `ΔF_pp = 2β·Fable$` (the scoped bucket is half the weekly bucket per
`accounts.json:frontier.coupling = 0.5`) and `ΔW_pp = α·Opus$ + β·Fable$`. Fitted three ways
(lag-0, lag-1, and a 2-hour window robust to sweep lag) plus a 2,000-resample bootstrap. The
2-hour-window fit is reported because it is the only one that does not assume the utilization sweep
and the transcript timestamp fall in the same hour.

**Not measured, and why.**

- **Quality at any effort on Opus 5.** No panel exists (F6). The 5.6× thinking ratio is a *cost*
  measurement and says nothing about output quality; asserting either direction would be exactly the
  Q4 error §0 of `USAGE_TELEMETRY_100P.md` forbids.
- **Whether `xhigh > max` is real or selection.** Efforts were operator/launcher-assigned by task
  difficulty; no randomization exists in the corpus. Reported as an upper bound (F3).
- **The exact Fable/Opus weekly-meter ratio.** Integer-percent quantization on `weekly_pct` plus a
  ≤1-sweep lag give a 90% CI spanning 0.79–1.88. That interval **excludes** a 0.5 discount but does
  **not** distinguish dollar-parity (1.0) from a 1.5× penalty. The measurement that would settle it
  is stated below.
- **Haiku quality on any fleet task class.** Zero probe arms, 0.06% realized share (F18). Every
  Haiku recommendation below is therefore gated on a probe, not asserted.
- **Per-subagent attribution.** `isSidechain` was absent on 157,058 of 157,058 assistant records in
  this sample, so I could not split lead vs subagent spend. Reported as null rather than imputed.

---

## Recommendations

| # | Action | Expected effect (quantified) | Quality risk | Effort |
|---|---|---|---|---|
| **R1** | **Delete effort from the cost conversation, in writing.** Record in `model-config.yaml:effort_defaults` that the ladder spans 14 points of marginal cost (−9.6% low → +4.4% xhigh at fixed context, F2) against 5.6× of thinking, and that **no effort downgrade may ever be justified on cost grounds**. | Removes the single most likely future quality cut: a −17% "saving" (F5) that is really ≤4% of marginal spend. | **NONE** (it forbids a cut) | 30 min — one comment block |
| **R2** | **Run the owed Opus-5 effort panel (D3's remainder) before touching `default` again.** Reuse the existing harness: the frozen 9-brief corpus and blind 4-judge pipeline from T4 already exist. Arms: Opus-5 @ {high, xhigh, max} on the four T1 task classes. | Converts `default: high` from ASSERTED (F4) to certified, or reverses it. Cost of the panel ≈ 27 worker runs ≈ 0.5–1 weekly pp on one account (from F17's ~$100/pp). | **NONE** (it *measures* the floor) | 1 dispatched session; harness exists |
| **R3** | **Until R2 lands, raise the reasoning-slot floor to `xhigh`, not lower it.** At fixed context xhigh costs **+4.4%** marginal over high and buys **+33%** thinking (F2). Given the operator's Q2 rule (spend idle quota) and F10's 85–100% peaks, this is the correct direction of travel; scope it to reasoning/synthesis slots, leaving `settings_floor` alone until R2. | +4.4% marginal $/turn on affected slots; +33% thinking tokens. On the measured fleet burn that is ≈ +0.5 weekly pp/account/week. | **NONE** (more reasoning, not less) | 1 h — `effort_defaults` + `cc-route` `ssot_effort()` |
| **R4** | **Close T5 — Opus-5 vs Fable-5 at matched effort — and reseat `research_adversarial`/`workflow_judge`/`eval_judge` on Opus-5 if Fable trails.** T4 already has Opus-5 ahead on recall (13 v 9 of 36), non-overlap (5 v 1) and unique hits (2 v 0) at half list price, but at unequal effort (F15). | If Fable trails at matched effort: Fable's realized 3.1× per-turn premium (F9) leaves those slots at **~68% lower marginal cost, quality equal-or-better**, and the slots stop behaving differently in-window vs window-shut. If Fable wins, the premium is finally *earned* and stays. | **NONE** either way — the probe's decision rule rejects any config that loses by even ~1% | 1 dispatched session; corpus + judges already built |
| **R5** | **Correct the "idle Fable lane / under-utilized weekly" premise wherever it is written**, including `USAGE_TELEMETRY_100P.md:12-15`. It is a post-reset snapshot (F10); the last complete cycle peaked 91/92/100/85% weekly with one account hitting the wall. Point every such statement at `account-utilization.jsonl` (F11) instead of a point-in-time `--readout`. | Prevents the whole telemetry programme optimizing for the opposite of the real constraint. `next3` **exhausted** its weekly window on 2026-08-11 — the failure mode is a wall, not waste. | **NONE** | 1 h |
| **R6** | **Move the economy to where the money is: context.** 86.8% of an Opus turn's marginal cost is cache read + cache creation (F1). Any iso-quality reduction in resident prompt weight or cache-miss rate is worth ~6× the entire effort ladder. `opus5-adaptation-2026-08-01.md §D7` already measures one such item: **94% of the global CLAUDE.md (356 of 377 lines) is duplicated verbatim in the project CLAUDE.md — ~25.8 KB re-sent in every session in this repo.** | De-duplicating that one block removes ~25.8 KB (~6.5K tokens) from every cached prefix in this repo. On the measured 247K cache-read tokens/turn that is a ~2.6% cut to the dominant cost component — larger than the entire effort ladder's realizable saving, with **zero** reasoning impact. | **LOW** — must verify by content that no rule is lost; INTEGRATE-never-overwrite applies | 2–3 h + a diff review |
| **R7** | **Probe Haiku-4.5 for exactly one slot: `research_retrieval` (file:line lookup), gated on a deterministic post-check.** Adopt ONLY if a `grep -n`/`sed -n` re-verification of every quoted line passes at the rate the Claude arms already hit in T4 (**93–96% exact**), and route it so a failed check re-runs on Opus rather than surfacing. Do **not** extend to log greps, censuses or format conversions until each has its own check and its own arm. | Haiku's base is $1/$5 vs Opus $5/$25 — and because cost is cache-dominated, the win lands on cache read (−80%): a long-context retrieval turn falls from ~$0.197 to ~$0.04, ≈**5×**. Upside is capped by volume: the slot is currently **0.06%** of output tokens (F12), so this is a *capability to route into*, not a saving to book. | **LOW** *only* under the deterministic gate; **HIGH** without it — T4 measured a model quoting lines >3 lines off 33–40% of the time, undetectable without the check | 1 dispatched session |
| **R8** | **Do not act on the "Sonnet 5 is ~15% pricier" line** (`~/.claude/commands/research.md:87`) — it is a 2026-06-30 vendor figure this repo's own probe superseded on 2026-07-01 (F14), and it has never been re-run against Opus 5. Either re-probe Sonnet-5@max vs Opus-5@{high,max}, or mark the line as historical. | Realized here, Sonnet-5@high is **$0.1028/turn vs $0.1970** — the opposite sign to the doc's claim. The certified Sonnet win is also stranded: 0.34% of turns (F13), because it is Workflow-only. | **NONE** (correcting a stale doc); adopting Sonnet anywhere else is **HIGH** until re-probed | 30 min to annotate; 1 session to re-probe |

### The quality floor — NEVER rules

These are written as prohibitions so that this artifact's own numbers cannot be cited to justify a
cut. The binding text is the operator's:

> *"we do not penny-pinch either — we are for diminishing returns towards achieving the 100th
> percentile optimal output, but if output is the same at 100th percentile and we can improve token
> utilization, that's good. **never cut quality even for a disproportionate amount of token
> savings.**"* — `docs/plans/USAGE_TELEMETRY_100P.md:33-35`

| | NEVER | Why, with the number from this axis |
|---|---|---|
| **N1** | **Never lower effort to save quota.** Not on the lead, not on a teammate, not on a subagent, not "just for this wave". | The whole ladder is a 14-point cost band (F2). You would be trading the model's entire reasoning budget for ≤4% of marginal spend. This is the archetypal Q3. |
| **N2** | **Never reduce research fan-out N to save tokens.** N is set by decomposition — by how many orthogonal axes the question has — and by nothing else. | `~/.claude/model-routing-freewin-probe.md` § Quota-Aware Wave Sizing already rules that under a quota "N is a cost knob, not a target to fill" — but the admissible move is **OASIS-stopping a redundant tail**, i.e. removing axes that are *not orthogonal*, never shrinking a live axis. Dropping a real axis is a silent recall loss with no detector. |
| **N3** | **Never trade a verification pass, a judge, a skeptic agent, or a gate for tokens.** | `USAGE_TELEMETRY_100P.md:52` — "a hook that prevents a false completion, a verification pass, a skeptic agent — these cost tokens and are **not** bloat. Bloat is spend that changes no decision." T4's measured value came *entirely* from the union across arms; a dropped arm is a dropped finding. |
| **N4** | **Never downgrade the LEAD.** Model and effort are launch-time identity for a session; the lead holds the frame no successor can re-derive from disk. | `model-config.yaml:roles.lead_default: claude-opus-5`, and the frontier policy already forbids the *inverse* (the lead never runs on Fable) for cost reasons. The cost asymmetry runs the other way too: a lead turn is one turn among ~157K. |
| **N5** | **Never adopt a cheaper model or effort on an *unproven* iso-quality claim.** An unproven iso-quality claim is Q3 wearing Q1's clothes. | The one certification in this repo that *looked* safe — "Sonnet loses at low/med" — was overturned the next day by a wider grid (F14). And the current `default: high` is itself uncertified on Opus 5 (F4). Burden of proof sits on the saving, always. |
| **N6** | **Never cite a "quality per token" ratio as a headline.** | `USAGE_TELEMETRY_100P.md:47` forbids it by name: any such metric "invites the trade this rule denies". Nothing in this artifact may be reduced to one. |
| **N7** | **Never read a point-in-time `--readout` as a utilization verdict** — in either direction. | F10: the same fleet reads 1–4% and 85–100% depending on which side of a reset you sample. A quota claim without a time series is not a measurement. |
| **N8** | **Never route Haiku (or any cheap tier) to a task whose wrong answer is not caught by a deterministic check that runs every time.** | T4 measured 33–40% of one model's quoted lines sitting >3 lines from the number cited — invisible to a reader, trivial for `grep -n`. Absent the check, the cheap tier's errors are *silent*, which is the one failure mode no amount of saving offsets. |

---

## What would falsify my headline

1. **F1's cost decomposition is the load-bearing claim.** If cache-read pricing is not 0.1× base
   input on these Max-plan requests — or if plan quota is metered on something other than
   dollar-equivalent list price, e.g. on output tokens alone — then output is not 13.1% of marginal
   cost, effort *is* a material cost lever, and R1/R3 invert. **Test:** run a controlled pair of
   identical-prompt sessions differing only in effort, on an otherwise idle account, and read the
   `weekly_pct` delta from `account-utilization.jsonl`. If ΔW scales with output tokens rather than
   with total priced cost, I am wrong.
2. **The Fable refutation (F7) rests on a 90% CI of [0.79, 1.88].** A single account-week of
   deliberately Fable-only load would collapse that interval. **Test:** for one 5-hour window, drive
   one idle account with Fable-only traffic and one with Opus-only traffic at matched token volume,
   and compare ΔW per priced dollar. A measured ratio ≤0.75 would resurrect the arbitrage and make
   Fable the correct default for judgment-dense slots.
3. **F3's `xhigh > max` is confounded by task selection.** If R2's randomized panel finds `max`
   producing more thinking than `xhigh` on matched briefs, the ladder's top is where the enum says
   it is and R3 should name `max`, not `xhigh`.
4. **F5's flat visible output could mask a quality loss.** If R2's judge panel finds Opus-5@high
   losing to Opus-5@max on any task class by any margin, `default: high` is a Q3 that has been live
   since 2026-08-01 and must be reverted immediately — the flat-length evidence would then be
   exactly the "iso-length mistaken for iso-quality" trap.
5. **F10's utilization peaks could be one anomalous week.** The log covers 6 days and 1–2 weekly
   cycles per account. If the next three cycles peak below 40%, the scarcity framing is wrong and
   the Q2 "spend the idle quota" pressure dominates — which would strengthen R3 and R4 and weaken
   R6's urgency, though it would not license any N-rule violation.
