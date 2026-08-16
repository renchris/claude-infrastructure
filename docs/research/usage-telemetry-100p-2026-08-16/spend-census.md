---
axis: A3 — Spend census (where the tokens actually go)
status: complete
date: 2026-08-16
headline: "96.7% of fleet tokens and 62% of list-equivalent cost is cache_read — the fleet's dominant expense is re-reading its own history, and the cache-expiry hook that was supposed to police this is premised on a 5-minute TTL that the corpus falsifies (the measured breakpoint is 65 minutes, i.e. the 1-hour TTL is already live and already saving ~$97K/yr-equivalent)."
load_bearing_claim: "The prompt-cache TTL in force on this fleet is ~1 hour, not 5 minutes — measured as a sharp discontinuity in cache-miss fraction between the 3600–3900s gap band (33.5% miss, n=35) and the 3900–4200s band (90.8% miss, n=41), with the 300–900s band that hooks/cache-expiry-warning.sh polices sitting at 7.1% miss (n=2603), statistically indistinguishable from the 0–120s baseline of 1.3%."
---

# A3 — Spend census

## Headline

**The fleet spent 62.175B tokens across 283,816 API calls in the 36 days the transcript corpus retains (2026-07-11 → 2026-08-16), and 96.71% of those tokens — 60.127B — were `cache_read`: the model re-reading context it had already processed.** By API list price that inverts only partially: cache_read is still the largest line at 61.6% of a $51,114 list-equivalent bill, with cache_write 22.5% and output — the only tokens that are actual *work product* — at 15.8% of cost and **0.50% of token count**. The input-side to output-side ratio is **232 : 1** fleet-wide and **332 : 1** in the long sessions (peak ≥400K, ≥60 requests) that hold most of the spend. That ratio, not any hook, is the spend census: an agentic session is a machine for re-reading its own transcript, and it re-reads it ~21 times per user prompt because 92% of API calls (261,395 / 283,816) end in `tool_use`, not `end_turn`.

**The one actionable defect this census found is an instrument, not a spend line.** `hooks/cache-expiry-warning.sh` fires on >300s idle and tells the model *"Full context will be reprocessed at uncached rate. Consider /clear or /compact."* Both halves are wrong. The premise is falsified — the cache-miss breakpoint is at **~3900s (65 min)**, so between 5 and 65 minutes the cache is still ~93% hitting, and the hook's firing population is **~85% false positive**. And the advice is quality-negative under the operator policy: it instructs the model to destroy context to save tokens, which the standing policy explicitly rejects. It is also keyed on `$CLAUDE_CONFIG_DIR/.last-interaction`, **one file per account config dir shared by every concurrent session on that account**, so any sibling's Stop clobbers the timestamp — it is wrong in both directions simultaneously. The residual real tax (gaps ≥65 min) is 845 events, 0.238B re-written tokens, **$1,497 list-equivalent over 36 days (2.93% of spend, $15.2K/yr-equivalent)** — real, but an order of magnitude below the ~$97.5K/yr-equivalent the 1-hour TTL is *already* saving with no configuration on this box.

---

## Findings

### §1 The four-way split

Denominator: **283,816 deduped API requests / 62.175B tokens / 3,352 sessions / 6,980 unique transcript files. Coverage: 100% of the deduped corpus** (not a sample — the full pass took 25s). Cost column uses `model-config.yaml:149 pricing_per_mtok` with standard Anthropic cache multipliers (write ×1.25, read ×0.10) — those multipliers are **ASSUMED**, they are not in the repo SSOT.

| Cut | requests | tokens | input | output | cache_write | cache_read |
|---|---|---|---|---|---|---|
| **FLEET (36d)** | 283,816 | 62.175B | 0.01% | 0.50% | 2.79% | **96.71%** |
| — same cut, by **cost** ($51,114) | | | 0.07% | 15.80% | 22.52% | **61.61%** |
| `.claude` (next) | 71,099 | 16.074B | 0.01% | 0.48% | 2.83% | 96.68% |
| `.claude-secondary` | 71,505 | 15.319B | 0.01% | 0.54% | 3.14% | 96.31% |
| `.claude-tertiary` | 74,832 | 15.666B | 0.01% | 0.50% | 2.55% | 96.93% |
| `.claude-quaternary` | 66,380 | 15.115B | 0.01% | 0.46% | 2.62% | 96.91% |
| last 7d | 61,702 | 14.902B | 0.01% | 0.38% | 2.67% | 96.94% |
| last 30d | 278,871 | 61.326B | 0.01% | 0.49% | 2.73% | 96.77% |
| **sidechain (subagent)** | 68,902 | 8.170B | 0.05% | 0.93% | **5.14%** | 93.88% |
| **main chain (lead)** | 214,914 | 54.005B | 0.01% | 0.43% | 2.43% | 97.13% |

The four accounts are **indistinguishable** — spread across the four is 2.55–3.14% cache_write and 96.3–96.9% cache_read. There is no per-account efficiency story to tell; whatever drives the split is a property of the workload, not of an account's routing.

**Recency is flat.** 7d vs 30d vs all-time differ by <0.15pp on every line. The shape is stable, which means it is structural, not a phase.

**Only the sidechain cut moves.** Subagents pay **2.1× the cache_write share** of the lead (5.14% vs 2.43%) because each one starts on a cold prefix. That makes subagents **17.0% of list-equivalent cost ($8,698) on 13.1% of tokens** — a 30% cost premium per token. Stated as a marginal, not an aggregate: a subagent token costs $1.065/Mtok against the lead's $0.785/Mtok.

| claim | evidence | grade | coverage |
|---|---|---|---|
| cache_read is 96.71% of tokens, 61.61% of cost | full pass, 283,816 deduped requests / 62.175B tok / $51,114 | MEASURED | 100% of deduped corpus |
| output is 0.50% of tokens, 15.80% of cost | same; 0.308B output | MEASURED | 100% |
| accounts are indistinguishable on the split | 4 rows above, 66K–75K requests each | MEASURED | 100% |
| subagents cost 30% more per token than the lead | $8,698/8.170B vs $42,417/54.005B | MEASURED | 100% |
| cache multipliers ×1.25 / ×0.10 | not in `model-config.yaml`; Anthropic published cache pricing | **ASSUMED** | — |
| Max subscription price $200/mo/account | not on disk anywhere in this repo | **ASSUMED** | — |

**The dedupe trap that would have inflated everything 2.38×.** The raw scan found 676,575 records carrying a `usage` object, but only **283,816 distinct `requestId`s**. A single API call is written to the transcript as one jsonl line *per content block*, each carrying a snapshot of the same usage object (verified: 160,345 of 209,759 duplicate groups have byte-identical usage tuples; the 49,414 that differ are the streaming progression — `output_tokens` grows 1 → 358 while `cache_creation` stays pinned at 18,717). Summing records instead of requests reports **141.6B tokens instead of 62.2B**. Every figure in this document dedupes by `requestId`, keeping the record with maximal `output_tokens`. A separate 1,397 requestIds appear in **two different account directories** (session transplant / resume copies) — global requestId dedupe absorbs those, at the cost of making per-account attribution ambiguous for 0.5% of requests.

*(Positive control that the dedupe is not over-eager: 262 records, 0.04%, carry no requestId at all and are passed through un-deduped; `requestId` is absent, not empty-string-collapsed.)*

---

### §2 The cache-miss tax — the hook's premise is falsified

`hooks/cache-expiry-tracker.sh` (7 lines, Stop hook) writes `date +%s` to `$CLAUDE_CONFIG_DIR/.last-interaction`. `hooks/cache-expiry-warning.sh` (33 lines, UserPromptSubmit) reads it, and if `>300s` emits `additionalContext` reading *"CACHE EXPIRED: Nm idle — prompt cache TTL is 5m. Full context will be reprocessed at uncached rate. Consider /clear (fresh session) or /compact (compress history) to reduce token cost."* Both are wired live at `~/.claude/settings.json:793` and `:858`. **Nothing else in the repo reads either one** — no counter, no ledger, no actuator. The only consumer is the model's own attention.

**Measurement.** For all 211,562 consecutive main-chain request pairs inside a session, I binned the inter-request gap and computed the miss fraction `cc / (cc + cr)` per bin:

| gap band (s) | n | miss fraction | cache_write/req | cache_read/req |
|---|---|---|---|---|
| 0–120 | 198,827 | **1.30%** | 3.3K | 247.4K |
| 120–240 | 5,966 | 4.20% | 11.3K | 257.0K |
| 240–300 | 945 | 6.82% | 20.0K | 272.9K |
| **300–360** ← hook starts firing | 671 | **7.15%** | 22.1K | 287.3K |
| 360–480 | 783 | 7.40% | 22.5K | 282.3K |
| 480–600 | 1,099 | 5.30% | 16.9K | 301.9K |
| 600–900 | 1,149 | 7.08% | 21.0K | 276.0K |
| 900–1200 | 333 | 16.49% | 48.6K | 246.2K |
| 1200–1800 | 376 | 16.65% | 54.1K | 271.1K |
| 1800–3000 | 416 | ~15.2% | ~51.7K | ~288K |
| 3000–3600 | 117 | 18.6% | 73.3K | 306K |
| 3600–3900 | 35 | **33.45%** | 114.9K | 228.7K |
| **3900–4200** ← the real cliff | 41 | **90.76%** | 307.0K | 31.2K |
| 4200–4800 | 59 | 91.89% | 247.7K | 21.8K |
| 4800–7200 | 193 | ~93.3% | ~280K | ~20K |
| 7200–14400 | 232 | ~94.3% | ~289K | ~17K |
| >14400 | 320 | 94.93% | 280.2K | 15.0K |

**The breakpoint is at ~3900s — 65 minutes.** The 1-hour cache TTL is in force on this fleet. No env var sets it (`~/.claude/settings.json` `env` block holds 8 keys, none containing `CACHE` or `TTL`), so it is the harness default. There is nothing to turn on.

*This is the positive control for the absence claim.* "There is no 5-minute cliff" is only credible because **the same instrument, unchanged, finds a cliff** — a 2.7× jump in miss fraction across one 300-second bin boundary at 3900s. An instrument that could not resolve a TTL boundary would have shown no cliff anywhere.

**The obvious confound was tested and does not survive.** The cliff could be measuring *human behaviour* — long absences ending in a `/compact` or a resume, which resets the prefix independently of any cache. I re-scanned the raw jsonl of every affected session for a compaction/summary record falling **inside** the gap window, for both bands:

| band | events | events with a compact/summary inside the gap | **miss fraction of the compaction-free events** |
|---|---|---|---|
| 300–3900s | 4,979 (1,312 sessions) | **0** | **9.37%** (cc 0.146B / cr 1.410B) |
| ≥3900s | 845 (497 sessions) | **0** | **93.96%** (cc 0.238B / cr 0.015B) |

Both populations are 100% compaction-free, so the **10.0× difference in miss fraction between them is attributable to gap duration alone.** (The zero counts are themselves consistent with `CONTEXT_ECONOMY_V2`'s finding that compaction is vanishingly rare fleet-wide — 39/39 manual, 0 auto.) The load-bearing claim is confirmed, not merely asserted.

**Three consequences, in severity order:**

1. **The hook is ~85% false-positive.** Its firing population is gaps >300s. Of the 5,824 main-chain gaps >300s, **4,944 (84.9%) fall in the 300–3600s window where the cache is still 85–93% hitting.** Only 880 (15.1%) sit past the real cliff.
2. **Its advice is quality-negative.** It tells the model to run `/clear` or `/compact` *to reduce token cost*. The standing operator policy is *"NEVER cut quality for token savings, even a large saving"* and *"under-utilizing the weekly allowance is itself a defect."* This hook is a resident instruction to do the forbidden trade, on a false premise, at every idle >5 min.
3. **Its state is per-account, not per-session.** `$CLAUDE_CONFIG_DIR/.last-interaction` is ONE file (verified: exactly four exist, one per config dir, 11 bytes each). Any of N concurrent sessions on that account resets it on every Stop. So a session that genuinely idled 3 hours reads 40 seconds if a sibling was busy → **silent under-fire**; and a session on a quiet account reads the fleet's last activity, not its own. This is `alarm-polarity-and-attention-budget` and `argv-is-sampling-cwd-is-durable` in one hook.

**The residual real tax** (gaps ≥3900s, the only ones that are true expiries):

| quantity | value |
|---|---|
| expiry events | 845 (0.40% of 211,562 inter-request gaps) |
| tokens re-written | 0.238B (**0.38% of fleet tokens**) |
| paid as cache_write @1.25× | $1,627 |
| would have been read @0.10× | $130 |
| **excess** | **$1,497 over 36 days = 2.93% of list-equivalent spend** |
| annualized | **$15,173/yr-equivalent** |

**The counterfactual is the bigger number and it is already banked.** Had the TTL been the 5 minutes the hook believes, the 300–3900s band (4,944 requests, mean prefix ~300K) would have re-written instead of read: **+$9,620 over 36 days = $97,533/yr-equivalent.** The 1-hour TTL is delivering ~6.4× the value that closing the entire remaining gap could.

| claim | evidence | grade | coverage |
|---|---|---|---|
| TTL breakpoint is ~3900s, not 300s | miss-fraction table, 211,562 gaps; 33.5%→90.8% across the 3900s boundary | MEASURED | 100% of main-chain gaps |
| the cliff is not a compaction/resume artifact | 0/845 and 0/4,979 events have a compact-summary inside the gap; compaction-free miss 93.96% vs 9.37% | MEASURED (controlled) | 100% of both bands |
| hook fires ~85% false-positive | 4,944 of 5,824 gaps >300s sit below the cliff | MEASURED | 100% |
| nothing consumes either hook's output | `grep -rn cache-expiry` → only settings.json:793/:858 + settings.example.json | MEASURED | repo + live settings |
| `.last-interaction` is per-config-dir, not per-session | `ls` finds exactly 4 files, one per account root; script reads `${CLAUDE_CONFIG_DIR}/.last-interaction` with no session key | MEASURED | 4/4 config dirs |
| real expiry tax = $15.2K/yr-equivalent | 845 events × mean 282K tok × (1.25−0.10) × $5/Mtok, ×365/36 | MEASURED (tokens) / INFERRED (annualization from a 36d window) | 100% |
| 1h TTL already saves $97.5K/yr-equivalent | counterfactual on the 4,944-request 300–3900s band | INFERRED (counterfactual, not observed) | 100% of the band |
| the 1h TTL is not operator-configured | `settings.json` env block has no CACHE/TTL key; cli.js not locatable on disk for a static confirm | MEASURED (settings) / could not verify in binary | — |

---

### §3 Per-session distribution

Denominator: **3,352 sessions**, 62.175B tokens.

| statistic | value |
|---|---|
| median tokens/session | **5.22M** |
| p75 | 17.56M |
| p90 | 49.92M |
| p95 | **87.09M** |
| p99 | 180.97M |
| max | **914.65M** (one session) |
| mean | 18.55M (3.6× the median — heavy right tail) |
| requests/session | p50 37 · p90 187 · p99 705 · max 8,192 |
| **top 10% of sessions hold** | **59.0% of fleet tokens** |
| top 5% hold | 41.1% |
| top 1% (33 sessions) hold | 15.3% |

Peak in-context occupancy per request (`input + cache_write + cache_read`): **p50 193K · p90 422K · p95 539K · max 977K**. This independently reproduces the 13-agent audit's *"median peak 190K, p95 558K"* (`context-economy-100p-2026-08-11`) from a differently-constructed instrument — a real cross-instrument positive control, and it means neither reading is an artifact of its own pipeline.

**Are top-decile sessions producing proportionate value? Partially — and the marginal says no.** `bin/cc-value` cannot answer this: it attributes commits to sessions only through a `Session-Id:`/`Land-Session:` trailer, and **114 of 2,851 commits on `origin/main` in this window carry one — 4.0%.** The remaining 96% are counted fleet-level and left deliberately unattributed (cc-value's own truth discipline, `bin/cc-value:14-18`). I therefore **abstain on the cc-value join** and substitute the one per-session value proxy that is fully recorded: file-mutating tool calls (`Edit` + `Write` + `NotebookEdit`), counted from the transcripts themselves.

| session decile by tokens | n | tokens | mutations | tool calls | **Mtok / mutation** |
|---|---|---|---|---|---|
| top 10% | 335 | 36.706B (59.0%) | 15,616 (43.9%) | 177,083 | **2.35** |
| deciles 2–5 | 1,341 | 22.721B (36.5%) | 18,567 (52.2%) | 142,162 | **1.22** |
| bottom half | 1,676 | 2.748B (4.4%) | 1,390 (3.9%) | 33,150 | 1.98 |
| all | 3,352 | 62.175B | 35,573 | 352,395 | 1.75 |

**The top decile is 1.9× less token-efficient per mutation than the middle band.** That is a genuine marginal (per-decile, not an aggregate ÷ N), and its direction is exactly what §5's re-read math predicts: cost per unit of work grows with context occupancy. **It is not causal evidence.** Hard problems are plausibly both long *and* low-mutation, and a mutation is a crude value unit (a one-line fix and a 400-line rewrite both count 1). Graded INFERRED.

| claim | evidence | grade | coverage |
|---|---|---|---|
| median 5.22M, p95 87.09M, max 914.65M tokens/session | 3,352 sessions, full corpus | MEASURED | 100% |
| top decile holds 59.0% of tokens | 335 sessions / 36.706B | MEASURED | 100% |
| peak occupancy p50 193K / p95 539K | 3,074 sessions with ≥2 main requests | MEASURED | 91.7% of sessions |
| cc-value cannot attribute per-session | 114/2,851 commits carry a session trailer (4.0%) | MEASURED | claude-infrastructure origin/main, 36d |
| top decile 1.9× less efficient per mutation | 2.35 vs 1.22 Mtok/mutation | MEASURED (ratio) / **INFERRED** (that it means inefficiency) | 100% |

---

### §4 Subagent / teammate overhead

| quantity | value |
|---|---|
| sidechain share of fleet tokens | **13.14%** (8.170B / 62.175B) |
| sidechain share of list-equivalent cost | **17.02%** ($8,698 / $51,114) |
| sessions using any sidechain | 323 / 3,352 = **9.6%** |
| within those 323, sidechain fraction of their own spend | **41.5%** (p50 25.0%, p90 76.7%, max 98.2%) |
| `Agent`/`Task` tool_use invocations, fleet | 2,495 |
| **mean tokens per subagent invocation** | **3.27M** |
| sidechain requests per session-with | mean 213 · p50 56 · p90 538 · max 6,545 |

**Is the fan-out paying for itself? Not answerable from token data, and I will not pretend otherwise.** A subagent's product is a file and a synthesis; neither is joinable to a token count. What the data *does* say, sharply:

- **A subagent costs 3.27M tokens — 63% of a whole median session (5.22M).** A 12-agent research wave is therefore ~39M tokens: **7.5 median sessions, or p90 of the entire session distribution, spent in one Agent block.** That is the number the `research-subagents` default of N=10–13 should be sized against, and it does not currently appear anywhere in that skill.
- **Fan-out is rare and concentrated.** Only 9.6% of sessions ever spawn one, but when they do it becomes 41.5% of their spend. So the "is fan-out worth it" question is a decision made ~323 times in 36 days, each worth ~10.5M tokens.
- **The premium is real but small.** 30% more per token than the lead, from the cold-prefix cache write. Against the operator policy — where under-utilizing quota is itself a defect — a 30% premium on the *only* spend class that buys parallel wall-clock is not an argument against fan-out. It is an argument that fan-out is the correct place to spend the headroom.

| claim | evidence | grade | coverage |
|---|---|---|---|
| sidechain = 13.14% tokens / 17.02% cost | 68,902 sidechain requests | MEASURED | 100% |
| mean 3.27M tokens per subagent | 8.170B / 2,495 Agent tool_use blocks | MEASURED | 100% |
| only 9.6% of sessions fan out | 323 / 3,352 | MEASURED | 100% |
| whether fan-out pays for itself | no instrument joins subagent output to value | **ABSTAIN** | — |

---

### §5 The turn shape — the mathematical case for recycling

**A "turn" is not the unit of spend. The tool-loop iteration is.** Of 283,816 deduped requests, **261,395 (92.1%) end in `stop_reason: tool_use`** and only 12,816 in `end_turn`. Two independent counts agree on the user-prompt population: 12,816 `end_turn` records vs **12,952 real main-chain user messages** (non-`tool_result`, non-meta, counted by a separate scan of the raw jsonl) — a 1.1% discrepancy, which is the positive control that both counts are measuring the same thing.

| turn-shape quantity | value | denominator |
|---|---|---|
| mean tokens per **API request** | 219K | 62.175B / 283,816 |
| mean tokens per **user prompt** | **4.80M** | 62.175B / 12,952 |
| mean API requests per user prompt | **21.9** | 283,816 / 12,952 |
| mean user prompts per session | 3.8 | 12,952 / 3,372 |
| **fleet input-side : output ratio** | **232 : 1** | 53.758B : 0.232B (main chain) |

**Context grows monotonically and the growth is the spend.** Across 2,205 sessions with ≥20 main-chain requests, binned into deciles of session progress:

| decile of session | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|---|
| median context (K) | 113 | 158 | 187 | 212 | 233 | 250 | 270 | 290 | 307 | **335** |
| mean context (K) | 118 | 166 | 199 | 225 | 251 | 274 | 298 | 323 | 344 | **374** |

Median context **triples** from first decile to last. Every request in decile 9 pays 335K to produce ~1.1K of output.

**The worked example, measured on real sessions rather than modelled.** The brief asked for "a session reaching 500K over 100 turns". The corpus contains **341 sessions with ≥60 main-chain requests and peak ≥400K** — mean peak **552K**, mean **242 requests**:

| | tokens | share of input-side |
|---|---|---|
| input-side total | 29.482B | 100% |
| — of which `cache_read` (= literal re-read of already-processed history) | **28.853B** | **97.87%** |
| — of which `cache_write` (new content entering the prefix) | 0.629B | 2.13% |
| output | 0.0888B | 0.30% of *all* tokens |
| **per session** | 86.5M input-side, 260K output | **332 : 1** |

**Stated in tokens, as asked: a 552K-peak / 242-request session spends 86.5M tokens, of which 28.85B/29.48B = 97.9% is re-reading its own history, and 0.30% is output.** Recycling that session at the fleet median peak (193K) instead of riding to 552K would have cut the per-request re-read by ~2.9×. The same relationship read across the occupancy bands:

| peak-context band | sessions | requests | input-side | cache_read % | in : out |
|---|---|---|---|---|---|
| 0–50K | 169 | 275 | 0.008B | 67.5% | 230 : 1 |
| 50–150K | 1,031 | 11,944 | 1.168B | 91.1% | 84 : 1 |
| 150–300K | 1,517 | 82,564 | 13.949B | 97.1% | 155 : 1 |
| 300–500K | 439 | 66,021 | 17.472B | 98.3% | 259 : 1 |
| **500K+** | 196 | 54,110 | 21.175B | **97.7%** | **351 : 1** |

**196 sessions — 5.8% of the fleet — consume 21.175B tokens, 34% of everything, at 351 tokens of input per token of output.** That is the recycling argument in its strongest form, and it is a token statement, not a vibe.

⚠️ **The honest caveat that keeps this from being a savings argument.** Re-read is *what the model is for* — it is how the context stays coherent. A session that recycles at 193K does not do the same work more cheaply; it does **different, more bounded work** and pays a fresh cold-prefix write (~200–300K at ×1.25) to start. The 97.9% is not waste, it is the price of continuity. What the table licenses is the narrower claim: **at the top of the distribution the marginal token buys less** (§3's 2.35 vs 1.22 Mtok/mutation is the same fact from the value side), so the recycle decision should be made on *judgment density*, exactly as `CONTEXT_ECONOMY_V2` concluded — not on the token count.

| claim | evidence | grade | coverage |
|---|---|---|---|
| 92.1% of requests end in tool_use | 261,395 / 283,816 | MEASURED | 100% |
| 21.9 API requests per user prompt | 283,816 / 12,952 (two independent counts agree to 1.1%) | MEASURED | 100% |
| 4.80M tokens per user prompt | 62.175B / 12,952 | MEASURED | 100% |
| median context triples across a session | decile table, 2,205 sessions ≥20 requests | MEASURED | 65.8% of sessions (those ≥20 req) |
| 97.87% of a big session's input-side is cache_read | 341 sessions, 29.482B input-side | MEASURED | 10.2% of sessions, 47% of fleet tokens |
| 5.8% of sessions hold 34% of tokens at 351:1 | 196 sessions / 21.175B | MEASURED | 100% |
| that the re-read is *waste* | — | **REJECTED** — re-read is the mechanism, not an inefficiency | — |

---

## Method

**Corpus construction.** Four account roots (`~/.claude`, `-secondary`, `-tertiary`, `-quaternary`) globbed for `projects/**/*.jsonl` and deduped by `os.path.realpath`. Raw glob returns 6,991 paths; `~/.claude-next/projects` resolves to `~/.claude/projects` (the recorded double-count trap — confirmed live, it would have added 1,827 phantom files) and `~/.claude-next{2,3,4}` do not exist on this box. **6,980 unique files.**

**Extraction.** One streaming pass (`scratchpad/extract.py`), substring-prefiltered on `"usage"` then `json.loads`: **1,636,037 lines read, 676,575 usage records emitted, 0 JSON errors, 25.3s wall.** Fields kept: account root, file, sessionId, isSidechain, timestamp, model, requestId, the four usage counters, stop_reason, type.

**Deduplication.** Grouped by `requestId`, kept the record with maximal `output_tokens`. 676,575 → **283,816**. 262 records (0.04%) have no requestId and pass through. Justification and the verification that within-group usage tuples are otherwise identical is in §1.

**Pricing.** `model-config.yaml:149`. Requests on a model absent from that table (`<synthetic>`, `claude-opus-4-7`) default to Opus pricing (5/25); they are 0.2% of requests. Cache multipliers ×1.25 write / ×0.10 read are ASSUMED.

**Falsification test (§2).** A second full raw-jsonl pass over the 1,809 sessions containing a >300s gap, looking for `isCompactSummary` / `type:"summary"` / `subtype` containing "compact" records whose timestamp falls between the two requests bracketing the gap. Result: 0 hits in both the 300–3900s band (4,979 events) and the ≥3900s band (845 events).

**No sampling was necessary.** Every figure here is a population statistic over the deduped corpus. The one place a sample appears is the decile-growth table (restricted to the 2,205 sessions with ≥20 main-chain requests, 65.8% of sessions) and the worked example (341 sessions, 10.2% of sessions but 47% of tokens) — both restrictions are stated inline.

**What I could not measure, and why:**

| unmeasurable | why | what I did instead |
|---|---|---|
| Actual dollars spent | Max subscriptions meter quota, not cash. `bin/cc-value:30-33` records that even `credits_used==0` is not proof (a Max account carried $176.91 of extra-usage on 2026-07-26). | Report list-price *equivalents*, always labelled. |
| Anything before 2026-07-11 | The corpus retains 36 days. Daily totals show a genuine ramp (0.067B → 5.558B peak), so this is retention + growth confounded. | Every "annualized" figure is `×365/36` on a 36-day window and is graded INFERRED. |
| Per-session value (commits/tasks) | 114/2,851 commits (4.0%) carry a joinable session trailer. `bin/cc-value` deliberately refuses to guess the other 96%. | Substituted a fully-recorded proxy (Edit+Write+NotebookEdit per session), stated as a proxy. |
| Whether the 1h TTL is settable | Could not locate `cli.js` on disk (`find / -name cli.js -path '*claude-code*'` → 0 hits; `claude` resolves to a pnpm shim). No CACHE/TTL key in the settings `env` block. | Answered behaviourally instead — the 65-min breakpoint proves the TTL in force regardless of how it is set, which is the stronger evidence. |
| Teammate vs research-subagent split | `isSidechain` is one bit; it does not distinguish an `Agent({name})` teammate from a fire-and-forget research subagent. | Reported the union as "sidechain" throughout and said so. |
| Which model a *session* ran on | Model is per-request; sessions mix (Opus 5 = 489,485 raw records, Opus 4.8 = 150,014, Fable 5 = 28,811). | Priced per request, never per session. |

**Commands.** All scripts are in the session scratchpad (`.../9f151488-…/scratchpad/{extract.py,dedupe.py,usage.tsv.gz,req.tsv.gz}`), outside the repo. No repo file was modified; this document is the only file written.

---

## Recommendations

| # | action | expected effect (quantified) | quality risk | effort |
|---|---|---|---|---|
| **R1** | **Delete `hooks/cache-expiry-warning.sh` and its Stop-side tracker, or gut the message.** Its premise is falsified (cliff at 65 min, not 5) and its advice — *"Consider /clear or /compact to reduce token cost"* — instructs the model to make the exact quality-for-tokens trade the operator policy forbids. | Removes ~4,944 false-positive advisories per 36 days (84.9% of its firings) and 2 forks per turn from the hook chain (`HOOK_CHAIN_COST` prices these). Token effect ≈ 0; **the win is that a false instruction stops reaching the model.** | **NONE** — it is currently a *negative*-quality instrument. | 15 min (one settings.json edit + `git rm`) |
| **R2** | If the alarm is kept rather than deleted: **re-key it to 3900s and to a per-session file** (`.last-interaction-$CLAUDE_SESSION_ID`), and change the copy from "consider /clear" to a neutral statement of fact. | Firing population drops 5,824 → 845 (−85%); the per-session key removes the sibling-clobber that currently makes it under-fire on busy accounts. | NONE | 30 min |
| **R3** | **Publish "3.27M tokens per subagent" into the `research-subagents` skill's sizing section.** A default of N=10–13 is currently chosen with no cost anchor; it is a ~39M-token decision, i.e. 7.5 median sessions. | Makes the fan-out decision priced instead of habitual. Under the operator policy this should *increase* fan-out (13% of tokens is under-use of the only lever that buys wall-clock), not decrease it. | **NONE** (a number, not a cap) | 20 min |
| **R4** | **Re-express the recycle rule in the measured marginal, not the fill %.** The binding fact is 2.35 vs 1.22 Mtok/mutation between the top decile and deciles 2–5, and 351:1 vs 155:1 input:output between the 500K+ and 150–300K occupancy bands. `CONTEXT_ECONOMY_V2` already reached the right conclusion; this supplies its missing numerator. | The 196 sessions in the 500K+ band hold 34% of fleet tokens. Halving their mean peak would not "save" tokens (the work moves) but would move ~2× more mutations per Mtok, by the measured band ratio. | **MEDIUM** — the ratio is correlational; hard problems are plausibly both long and low-mutation. Do **not** turn this into a hard recycle threshold. | 1h (edit to CONTEXT_ECONOMY_V2 + the global rule's cite) |
| **R5** | **Do not build a cache-optimisation program.** The residual expiry tax is 0.38% of tokens / 2.93% of list-equivalent cost, and the lever that mattered (1h TTL) is already on by default with no configuration. | Avoids spending a wave on a $15K/yr-equivalent line while the 232:1 re-read ratio — 60.1B tokens — sits unaddressed and, per §5, is mostly *not* addressable. | NONE | 0 (a decision not to act) |
| **R6** | **Record the requestId-dedupe rule wherever this corpus gets read again.** Summing usage records instead of unique requests inflates every figure **2.38×** (141.6B vs 62.2B). | Prevents the next audit publishing a 2.38× overstatement. | NONE | 10 min (a line in the telemetry doc) |
| **R7** | **Spend the headroom.** Fleet ran 1.727B tok/day over 36 days; every account's weekly pace reads BEHIND (next 3%, next2 1%, next3 18%, next4 3% at the 2026-08-16 reading). At list-equivalent $518K/yr against an assumed ~$9.6K/yr of subscription, the plans return ~54×. | Under-use is the defect the operator named. The measured place with headroom *and* a quality upside is R3's fan-out, not longer sessions (R4 says the marginal decays there). | **LOW** | ongoing |

---

## What would falsify my headline

1. ~~**The 65-minute cliff is an artifact of *when people return*, not of the TTL.**~~ **TESTED AND SURVIVED** (§2). Partitioning both bands on whether a compaction/summary record falls inside the gap: **0 of 845** long-gap events and **0 of 4,979** mid-band events have one, and the compaction-free miss fractions are **93.96% vs 9.37%** — a 10.0× separation attributable to duration alone. This was the weakest joint; it is now the strongest. *A residual: a `--resume` that reuses the same sessionId with a fresh process would not emit a summary record and is not excluded by this test.*
2. **The cache multipliers are wrong.** Every cost column assumes ×1.25 write / ×0.10 read. Those are Anthropic's published 5-minute-cache multipliers; the **1-hour** cache writes at ×2.0. If the fleet is on 1h caching — which §2 argues it is — then cache_write should be priced at ×2.0, raising it from 22.5% to ~32% of cost and lowering cache_read's share to ~55%. **This does not change the headline's direction but it does change its numbers**, and it makes R1/R2 slightly *more* valuable and R5 slightly less safe. This is the honest weak point in §1's cost column and I flag it rather than silently pick the favourable multiplier.
3. **`isSidechain` does not mean what I assumed.** If it is set on things other than Agent/Task children (e.g. certain hook-injected turns), the 13.14% is not "subagent overhead". **Test:** join sidechain request bursts to the parent's `Agent` tool_use timestamps and confirm 1:1.
4. **The 2.38× dedupe is over-correction.** If some requestId collisions are genuinely distinct billed calls (e.g. a server-side retry reusing an id), I am under-counting. **Control:** 160,345 of 209,759 duplicate groups have byte-identical usage; a retry would differ. But the 49,414 differing groups are assumed streaming progressions on the strength of one inspected example.
5. **The 36-day window is not representative.** Daily totals ramp 0.067B → 5.558B. If that ramp is the fleet growing rather than retention truncating, every `×365/36` annualization overstates history and understates the forward rate.
