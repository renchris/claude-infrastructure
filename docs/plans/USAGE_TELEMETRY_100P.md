---
status: open
created: 2026-08-16
owner: desk
subsystem: Usage telemetry — weekly-limit utilization, token economics, zero-bloat instrumentation
---

# USAGE TELEMETRY 100P — ground-up rebuild

**Scope (frozen):** the 100th-percentile Claude Code usage telemetry for claude-infrastructure,
researched from the ground up and landed:

- **(a) UTILIZATION** — weekly-limit utilization maximized across the 4 Max accounts. Unspent weekly
  quota is *destroyed* at reset; on 2026-08-16 three of four windows sat at 1–3% with 6+ days left
  and every `pace to 100%` line read BEHIND. **Under-use is the primary defect**, not over-use.
- **(b) EFFICIENCY, BOUNDED BY QUALITY** — model/effort/pattern routing that spends tokens well
  *without penny-pinching*. Quality at the 100th percentile is never traded for tokens, at any
  savings ratio. A saving is admissible **only** when output at the ceiling is UNCHANGED.
- **(c) NO INSTRUMENT BLOAT** — the telemetry itself must not be token bloat. Token-charged
  instrumentation is measured and minimized; token-free instrumentation is preferred.

**Deliverables:** research artifacts in `docs/research/usage-telemetry-100p-2026-08-16/`; this plan
carrying the synthesis; and the implementation it supports, landed and live.

---

## §0 The admissibility rule — written BEFORE the evidence, deliberately

Every recommendation this plan accepts must pass this test. It is written now, ahead of any finding,
so that a large measured saving cannot later talk the plan into a quality cut it would have refused
in advance. The operator's words are the binding text:

> *"we do not penny-pinch either — we are for diminishing returns towards achieving the 100th
> percentile optimal output, but if output is the same at 100th percentile and we can improve token
> utilization, that's good. never cut quality even for a disproportionate amount of token savings."*

| | Class | Rule |
|---|---|---|
| **Q1** | **Free win** — output at the ceiling provably unchanged, tokens down | **ACCEPT.** This is the entire admissible efficiency class. Examples in kind: removing a duplicated resident block, avoiding a cache miss, deleting an instrument nothing reads. |
| **Q2** | **Utilization win** — quality unchanged or better, tokens *up*, weekly headroom consumed that would otherwise expire | **ACCEPT, and prefer it.** Spending idle quota is the goal's first half. More agents, deeper verification, more parallel fan-out are *good* here. |
| **Q3** | **Quality cost, any size of saving** | **REJECT.** No exchange rate exists. A 90% token saving for a 1% quality loss is still a reject. Do not model it, do not present it as a trade-off, do not park it as "available if needed". |
| **Q4** | **Unknown quality effect** | **REJECT until measured.** An unproven iso-quality claim is a Q3 wearing Q1's clothes. The burden is on the saving, never on the quality. |

**The asymmetry is deliberate.** Tokens are recoverable — the window resets weekly. A degraded
answer that shipped is not recoverable. So the telemetry's job is to *find Q1 and Q2*, and it must be
structurally incapable of being cited to justify Q3. Any metric that could be read as "quality per
token" is therefore forbidden as a headline number: it invites the trade this rule denies.

**Corollary for the instrument (c).** A hook that prevents a false completion, a verification pass, a
skeptic agent — these cost tokens and are **not** bloat. Bloat is spend that changes no decision.
Rank instruments by *decisions changed*, never by bytes.

---

## Phase 0 — Agent Team Orchestration

| Wave | Locus | Members | Rationale |
|---|---|---|---|
| **W1 — Research** | **S** (dispatched, in-workflow) | 13: 9 census axes + 3 adversarial skeptics + 1 completeness critic | Breadth-first discovery over 9 orthogonal axes; read-only, so no file contention. Run as `Workflow` `wf_e043c4e9-4a9` at effort `high` (not the session's `xhigh`) — census work is evidence-gathering, and inheriting `xhigh` for 13 agents is exactly the haphazard spend this plan exists to find. |
| **W2 — Synthesis** | **L** (lead-inline) | — | The synthesis IS the judgment; it must be held against §0 by one reader with the whole picture. Cannot be delegated without losing the frame. |
| **W3 — Implementation** | **S** (dispatched sessions, one per component) | TBD from W2 | Default locus per CLAUDE.md § Agent Teams. Sized after W2 names the components. |

**Lead context budget:** ≥50% held for deciding. Succession point: after W2 lands, before W3 fires.

### W1 decomposition (fired 2026-08-16)

| Axis | Question | Keystone |
|---|---|---|
| A1 `exchange-rate` | What unit does the weekly limit count? tokens → weekly-% mapping | ✅ + skeptic |
| A2 `utilization` | Why are 3 of 4 windows at 1–3%? What is the binding constraint? | ✅ + skeptic |
| A3 `spend-census` | Where do the tokens actually go? cache-miss tax, per-session distribution | |
| A4 `resident-tax` | What every turn pays before work: CLAUDE.md duplication, MCP rosters, MEMORY.md | |
| A5 `telemetry-own-cost` | Which hooks inject context; the forced-turn cost of Stop hooks | |
| A6 `routing-economics` | Effort/model economics + the Fable 50%-weighting arbitrage + the quality floor | ✅ + skeptic |
| A7 `pattern-waste` | Dead sessions, re-derived work, failed calls; the recycle crossover point | |
| A8 `vendor-ground-truth` | Anthropic docs, native OTel telemetry, ccusage/claude-monitor, cache TTLs | |
| A9 `incumbent-inventory` | Every existing instrument, graded by the reader test and the accuracy test | |
| C1 `critic` | What modality was not run; which cross-axis claim is verified nowhere | |

Adversarial share 3/9 = 33%, above the 15–20% floor in the `research-subagents` skill.

---

## §1 Opening state (measured 2026-08-16, before any change)

Recorded so every later claim has a baseline to move against.

**Quota** (`claude-accounts --readout`, live from `api.anthropic.com/api/oauth/usage`):

| account | live sessions | 5h used | weekly used | Fable used | weekly resets |
|---|---|---|---|---|---|
| next | 2 | 4% | 3% | 3% | in 6d 17h |
| next4 | 7 | 60% | 3% | 4% | in 6d 22h |
| next3 | 6 | 6% | 18% | 5% | in 2d 1h |
| next2 | 0 | 4% | 1% | 0% | in 6d |

All four `pace to 100%` lines read BEHIND. Fable (which draws at ≤50% weight per
`model-config.yaml frontier_access`) is at 0–5% across the entire fleet.

> 🚨 **THE READING ABOVE IS CORRECT AND ITS OBVIOUS INTERPRETATION IS FALSE.** The table is retained
> verbatim as the audit trail. Measured the same day from `~/.claude/logs/account-utilization.jsonl`
> (5,017 samples, 4 accounts, 6 days) — the *previous complete* weekly window for every account
> closed at **next 91% · next2 92% · next3 100% · next4 85%**. The 1–3% readings are three windows
> that had just **reset**. The fleet is **near-saturating** its weekly allowance, not idling.
>
> `next3` reached exactly **100%** — a real exhaustion, and an exhausted account is *down* until
> reset. **That inverts the design target for scope item (a):** the job is not to push utilization
> up, it is to land in the high-90s *without any account hitting 100*, and — because at saturation
> a wasted token displaces real work rather than merely costing money — scope item (b) becomes
> materially more valuable, not less.
>
> **The generalisable defect, and the spec for the rebuild in one sentence:** a point-in-time
> percentage against a *periodically resetting* counter is dominated by where you are in the window,
> not by how you are using it — so a usage instrument must report against the window's **elapsed
> fraction**. The primitive is a **burn ratio** `weekly_pct ÷ elapsed_fraction_of_window` (1.0 = on
> pace to finish at 100%). Every account above reads ~1.0 on that measure; the raw percentage read
> 0.03. The fleet's own headline renderer produced a reading that inverted the truth, and every
> figure in it was accurate. Derivation + method + the two estimator bugs found on the way:
> [`usage-telemetry-100p-2026-08-16/lead-exchange-rate.md`](../research/usage-telemetry-100p-2026-08-16/lead-exchange-rate.md).

**Corpus:** ~7.3 GB of transcripts across four config dirs (`~/.claude` 2.0G, `~/.claude-secondary`
2.0G, `~/.claude-tertiary` 1.9G, `~/.claude-quaternary` 1.4G). `~/.claude-next{,2,3,4}/projects` are
symlinks into these — dedupe by realpath.

**Known absence:** no usage **time-series** store exists on disk (searched `~/.claude` for
`*usage*`/`*quota*`; only unrelated hits). Quota readings are point-in-time only, so the
tokens→weekly-% exchange rate cannot be derived retrospectively. Positive control: the same search
surfaces `~/.claude/archives/cleanup-20260725/usage`, so the scan does find matching names.

---

## §2 Findings

### §2.1 The price list — what a token actually costs against the weekly limit

The keystone result. Derived by A1 (`exchange-rate.md`, NNLS over 265 intervals, R²=0.82), then
**calibrated ×2.99 by the lead** after a hold-out check on whole weekly windows exposed a consistent
3× under-prediction (`lead-exchange-rate.md` § Addendum). Cause: Claude Code writes a streaming
assistant message to the transcript several times, so a census that does not dedupe on `message.id`
over-counts ~2.4× — measured at 58.7% repeat records, 98.5% byte-identical usage, 0 spanning files.

**Three independent derivations of the same bug, then two independent corrections.** A1 published a
price list; the lead's hold-out check and the A1 skeptic *separately* found the same extractor defect
(Claude Code writes one transcript line per content block of a streamed assistant message — same
`message.id`, same `requestId`, identical complete `usage` — so summing lines counts one billing
event 2–3×). A1's own falsifier #6 named this hazard and was not run. Corrected two different ways:

| | lead (calibrate A1 ×2.99 against whole-window burn) | skeptic (dedupe, then re-fit NNLS) |
|---|---|---|
| Opus-5 **output** — tokens per 1 pp | 261,000 | ~360,000 (320–410K) |
| Opus-5 **cache_creation** — tokens per 1 pp | 3.19 M | ~3.4 M |
| Opus-5 **cache_read** | free | free (`op_cr` = 0.0000 at every anchor spacing) |

**Use ~360K as the marginal price and ~261K as the realised average.** They differ by 1.38× for a
reason worth keeping: the skeptic's figure is the clean *local* relationship fitted on transcript-
visible tokens, while the lead's is calibrated against *actual* window burn — so the gap implies
**~28% of weekly consumption leaves no local transcript at all.** Anthropic documents exactly this:
`/usage` attribution is "computed from local session history **on this machine**", so `cc-offload`
cloud sessions and claude.ai usage draw the same plan quota invisibly. A full account-week is
therefore **≈26–36 M Opus-5 output tokens**, and no local instrument can ever see all of it.

A1's published figures (780K per pp, 78M per account-week, 292M of headroom) are **2.1–2.8× too
high** and should not be quoted. The unit itself is monetary: the raw `api/oauth/usage` payload
carries `limit_dollars`/`used_dollars`/`remaining_dollars`, nulled on Max while `utilization`
(a percent) is populated.

### §2.2 The inversion — 96% of the tokens cost 0% of the quota

Applying §2.1 to the deduped 7-day census:

Computed on **deduped** 6-day fleet totals (12.46 B tokens, 4 accounts), under **both** independent
corrections — the shares are reported as the range the two produce, never as a single false-precise
number:

| class | % of tokens moved | **% of quota spent** |
|---|---|---|
| output | **0.31%** | **51–57%** |
| cache_creation | **2.74%** | **42–48%** |
| cache_read | **96.95%** | **≈0%** (bounded small — not proven exactly zero; see below) |
| input | 0.005% | ~0.9% |

**Two levers of roughly equal size, and neither of them is context length.** My first pass reported
61.4 / 37.9 from a non-deduped census; on deduped totals the split is closer to even, and the
difference between the two corrections (51/48 vs 57/42) is larger than any distinction worth drawing
between them. **What is robust across every treatment is the thing that matters: ~97% of the tokens
this fleet moves cost ~0% of its quota.**

Modelled burn is **52–64 pp/account/week** against **85–100 observed** (§2.3) — the residual is the
~28% of consumption that leaves no local transcript.

**This table was adversarially tested by the lead before being accepted, because A6 contradicts it.**
A6 measures the same turns at **API list price** and gets output 13.1% / cache_read 62.7% — the
opposite ranking. Both cannot steer the plan. The denominators differ (dollars vs weekly points), and
since A1 also found the meter is *dollar*-denominated (`limit_dollars` in the raw payload), the
conflict is real rather than definitional. Two tests, on 67 `(account, 6h)` buckets:

1. **Model fit** (each model given one free scale factor, least squares through the origin):

   | model | rel-RMSE | R² |
   |---|---|---|
   | **A1 shape (cache_read free)** | **0.456** | **0.827** |
   | output only | 0.557 | 0.742 |
   | list-price dollars (A6) | 0.583 | 0.717 |
   | raw tokens | 0.763 | 0.516 |

   The cache_read-free shape beats the list-price model decisively. Its fitted scale is **3.26**,
   independently converging on the **2.99** obtained from whole weekly windows — two different
   aggregations agreeing on the same calibration.

2. **A discriminating test that needs no fit:** if cache_read were free, pp-per-output-token would be
   independent of the cache_read:output ratio. Across a 1.9× swing in that ratio, pp-per-output moved
   **1.42×** — less than the ~1.9× a dollar-priced model predicts, but more than the 1.0× "free"
   predicts.

⚠️ **So the honest position, and the one this plan is built on:** the **ranking** is robust —
per token, output ≫ cache_creation ≫ cache_read — and the list-price model is refuted as a
description of *weekly-limit* burn. But `cache_read = exactly 0` is **not** established:
`corr(output, cache_read) = +0.909` makes the coefficient unidentifiable, and NNLS is bounded below
at zero, so A1's exact zero is partly a boundary artifact. The residual sensitivity in test 2 is
confounded and **must not** be converted into a coefficient (doing so yields 330 pp/week for
cache_read, which exceeds the entire fleet budget — a reductio confirming the estimate is
contaminated). **Read the 61.4 / 37.9 / ≈0 split as a well-supported ordering with a small unpriced
residual on cache_read, never as three exact numbers.** Every recommendation below survives that
uncertainty, because each rests on the ordering rather than on the exact shares.

🚨 **This inverts the default intuition and it is the governing fact of this plan.** Quota is spent
on what the model **emits** and on what **newly enters** the cache — never on re-reading context
already there. One output token costs the quota of **12.2** cache-creation tokens and of
**unboundedly many** cache-read tokens.

Three consequences that change standing practice:

1. **Shrinking context to save quota optimizes the free class.** ✅ **Experimentally confirmed** —
   this consequence was suspended by the critic and is now restored: 31.7M cache_read tokens moved
   the weekly meter at most 2 points where list pricing demanded 4.62 (§2.8, `meter-experiment.md`).
   Recycling, `/compact`, and aggressive context trimming remain justified by **rot** and by the
   hard **context ceiling** — both real and untouched by this — but **not** by quota. They should
   never again be argued on cost grounds.
2. **Verbosity is the primary quota lever, worth 61% of the bill.** The existing CLAUDE.md
   § Communication Discipline rule ("Opus 5 runs long by default … it has to be prompted for") is
   therefore not a style preference — it is the single largest cost control this fleet has. And it is
   a **Q1 free win by construction**: removing words that carry no information cannot lower quality.
3. **Cache-creation (38%) is driven by what newly ENTERS context** — large file reads, verbose tool
   output, agent reports delivered into the lead's window. Every one of those has a quality-neutral
   cheaper form (line-ranged reads, file-delivery instead of prose return) already mandated elsewhere
   in this repo's practice.

### §2.3 Utilization — the fleet is near-saturating, not idling

See the correction box in §1. Last complete windows: next 91% · next2 92% · next3 **100%** · next4
85%. Modelled burn from §2.1 is 59 pp/account/week against 85–100 observed — the right band, with the
shortfall consistent with usage no local transcript can see (Anthropic documents `/usage` attribution
as computed from local session history **on this machine**, so cloud `cc-offload` and claude.ai usage
are structurally invisible).

**Therefore scope item (a) is nearly met and its real content changed:** the risk is not waste from
idleness, it is an account hitting 100% and going down for days. `next3` already did.

**A2 dated the windows precisely and found the one genuine stranding case — plus the mechanism
behind it.** Three of the four windows began within the last 24 h (`next` 6.4 h ago, `next4` 1.4 h,
`next2` 23.4 h), so their 1–4% readings measure *hours of elapsed window*, not a week of underuse.
Only **`next3`** is genuinely stranding: 118.4 h into a 168 h window at 18%, i.e. a **burn ratio of
0.26** — exactly the quantity §3.2 makes the headline metric, and exactly the case a raw percentage
cannot distinguish from a healthy window that just reset.

**A mechanical cause exists — but it is NOT the top lever, and the paragraph that said so was
wrong.** The autonomous dispatcher has parked **254 of 261 dispatchable items behind a cloud-only
venue filter since 2026-08-11**, firing ~17 sessions/day while fleet burn fell to **38% then 21%**
of demonstrated daily capacity on 08-14/08-15. This plan originally called that "the single largest
utilization lever … a Q2 win".

> 🚨 **REFUTED BY A2's SKEPTIC, AND THE ERROR WAS THE LEAD'S OWN INCONSISTENCY.** The four most
> recent *complete* weekly windows finished at **91 / 85 / 92 / 100 — 368 of 400 points, i.e. 92%
> of the fleet's entire weekly allowance already consumed** (Anthropic's own meter, 1,257 samples
> per account over six days). `next3` sat at **exactly 100% for 11.2 hours** before its reset.
> **There is no utilization crisis to solve**, and a venue filter cannot be "the binding constraint"
> on a resource the fleet already spends 92% of.
>
> Measured against that headroom, releasing the parked queue wholesale would consume **26–74× the
> entire remaining weekly allowance**, exhausting every window in 1.5–2 days and leaving the fleet
> **walled for 4–5 days a week**. Under §0 that is not a Q2 utilization win — it is **Q3, quality-
> destroying**, and is REJECTED in that form.
>
> **The inconsistency was mine, not A2's alone.** §2.3 established near-saturation and then this
> section endorsed a recommendation premised on abundant headroom, in the same document. Both
> halves cannot be true. Kept visible rather than quietly rewritten, because it is the exact trap
> §3.2 exists to prevent: *a throughput lever priced without its denominator*.

**The resolution — and it reverses the build order.** The filter is still a real defect, but it is a
**demand** lever pointed at a **nearly-exhausted supply**, so it must never be released
un-governed. **M3 (burn ratio + wall alarm) therefore ships BEFORE M1**, and M1 is re-scoped from
"unblock the queue" to "admit work against measured headroom": the dispatcher fires while the burn
ratio is below pace and throttles as it approaches 1.0, so the queue drains into *whatever headroom
genuinely exists* instead of into a wall. That ordering is now reflected in §4.

### §2.7 The incumbent: the quota half is good, the token half is near-empty

A9's inventory: `account-utilization.jsonl` is real, durable, 5,021 rows, already steering routing —
so on the quota axis **the rebuild's job is to SURFACE an existing series, not to build one.** The
token axis is where the hole is: only **2 of ~90 tools** read the durable per-session token record,
the sole window denominator has **0.4% coverage**, and `cc-value` — the one value-per-quota
instrument — joins on a git trailer **this repo measured as extinct four days ago** and was never
disconnected, so it is silently reporting over an empty join. That last one is the `idl.jsonl` shape
again: an instrument recording its own activity rather than the thing that matters.

### §2.4 The instrument is not the bloat — but one instrument is actively wrong

A5 measured token-charged telemetry at **0.6–1.2% of throughput**. It is not eating the budget, and
cutting it is not a lever worth pulling. Two real defects surfaced instead, both quality failures
found by a cost audit:

- **The frozen-DoD carrier is silently truncated.** The harness replaces any hook `additionalContext`
  over ~10 KB with a 2.3 KB stub containing only the **first** 2 KB. `dod-persist.sh` concatenates a
  live store with a frozen legacy store into ~44 KB, so the stub previews the **oldest, superseded**
  scope and the binding current `Scope (frozen):` line is structurally unreachable — in **51%** of
  the sessions it fires in. It is the only hook in the fleet that overflows the cap. *(This affects
  this very session.)*
- **`hooks/cache-expiry-warning.sh` is premised on a falsified TTL and gives harmful advice.**
  `:10` hardcodes `CACHE_TTL=300` and injects `"prompt cache TTL is 5m … Consider /clear or
  /compact"`. Refuted three ways: Anthropic documents that **on a Claude subscription Claude Code
  requests the one-hour TTL automatically**; A3 measured the breakpoint in this corpus at **65
  minutes** (3600–3900 s band 33.5% miss vs 3900–4200 s 90.8%, while the 300–900 s band it polices
  sits at 7.1% vs a 1.3% baseline); and `credits_on` is false on 5,017/5,017 rows, so the
  credit-drawdown path that would downgrade to 5 min has never fired. It therefore fires ~12× more
  often than warranted, and **under §2.2 its advice is backwards**: `/clear` and `/compact` destroy a
  warm cache, converting free `cache_read` into paid `cache_creation`.

### §2.5 The resident tax — real, free to remove, but smaller in quota than in tokens

`./CLAUDE.md` is **byte-identical** (`md5 10de4a19…`, 63,983 B) to `~/.claude/CLAUDE.md` and to the
per-account copies in all four config dirs — verified independently by the lead across all five
loading paths. Every session in this repo loads the same ~23,700 tokens twice, for zero informational
gain, and this session's own context shows both copies.

**But price it before ranking it.** The duplicate lands in `cache_creation`, not `output`: ~24K
tokens × ~677 sessions/week ÷ 3.19M tokens-per-pp ≈ **5 pp/week fleet-wide**, ~2% of the bill. It is
a genuine **Q1 free win** and should be taken — but it is not the headline, and saying "23,697 tokens
duplicated" without the exchange rate would have mis-ranked it above the output lever, which is 12×
more valuable per token. *This is precisely what the price list is for.*

### §2.6 What Anthropic already ships that we do not use

Claude Code has a complete OpenTelemetry pipeline — 8 metrics, 15 events, `CLAUDE_CODE_ENABLE_TELEMETRY=1`
plus OTLP exporters — that is **out-of-band and therefore token-free by construction**, which is the
exact instrument shape scope item (c) demands. It is enabled in **0 of 5** config dirs (positive
control: the same grep finds 42 `"hooks"` entries in each file). It carries **no quota denominator** —
that lives only behind `api/oauth/usage`, which `account-utilization.jsonl` already samples every
~6 min at 94% wall-clock coverage. So the two halves compose: **OTel for the numerator, the existing
utilization series for the denominator.** `/usage` additionally exposes per-skill, per-subagent,
per-plugin and per-MCP attribution that nothing here reads.

### §2.8 ✅ RESOLVED — the meter WAS identified, by experiment (2026-08-16)

> **The doubt below stood for about two hours and is now settled by measurement, not argument.**
> M0 ran on `next2`: one session, 45 resumed turns, **31,726,824 cache_read tokens against 208
> output** (a 152,533:1 ratio no observational sample of this fleet contains). List-price weighting
> predicted **4.62** weekly points and **11.19** five-hour points; the meters moved **1** and **4**.
> Over-predicted 3–4× on two independent meters.
>
> **Under all four attribution assumptions, list-price weighting for cache_read is REFUTED** (by
> 1.3× to 10.3×), and on the best-supported reading — the 5-hour meter with calibrated coefficients
> — `cache_creation` **alone** explains 4.43 pp of a 3–5 pp move, leaving **nothing** for
> cache_read. Bound: **≤0.018–0.049 pp per million tokens, i.e. at most a quarter of list-price
> weight and plausibly zero.**
>
> ⇒ **§2.2's consequence #1 is restored to its unconditional form**, and the wave's central
> inversion survives its own critic. Cost: 1 weekly point on an account at 2%. Full method, bounds,
> and the two instrument failures found on the way (one of which would have produced a confident
> null from an *empty* arm):
> [`meter-experiment.md`](../research/usage-telemetry-100p-2026-08-16/meter-experiment.md).
>
> *The reasoning that motivated the experiment is retained verbatim below — it is why the experiment
> was run, and the two hypotheses it names are what the arm was designed to separate.*

#### (superseded) The meter is NOT identified — the wave's own critic, and it qualifies §2.2

**Nine axes measured what tokens the fleet moves; none measured what the operator actually spends.**
Every artifact except A1 and A2 prices work in **API list dollars**, while the operator pays in
`weekly_pct` on four Max subscriptions. That bridge is crossed by a "therefore" in A3, A5, A6, A7
and the lead's own A0, and is graded MEASURED in most of them. It is **ASSUMED**.

Two attempts to settle it, both inconclusive:

- A1's NNLS returned a **boundary** solution for cache_read whose unconstrained sign is negative —
  i.e. the fit hit the zero wall, which is not evidence of zero.
- A6's skeptic ran the discriminating regression and found the fleet has **no instrument that can
  separate the candidate meters**: cumulative R² 0.945 (priced dollars) vs 0.953 (output-only), and
  a *properly differenced* form yields only 11 movement windows in 6 days at R² 0.13–0.16 for **all
  four** hypotheses.

**This qualifies the lead's §2.2 model comparison** (R² 0.827 cache_read-free vs 0.717 list-price on
67 buckets). That comparison is real, but it is a *level*-fit over few, highly collinear buckets
(`corr(output, cache_read) = +0.909`), and the properly-differenced form the skeptic ran does not
reproduce its separation. **What survives is the ordering — output is the dearest class per token,
cache_read the cheapest. What does NOT survive is the 51–57 / 42–48 / ≈0 split as a measured
quantity**, and with it the unconditional form of §2.2's consequence #1.

**The hinge, stated plainly:** if cache_read ≈ 0, context re-read is free and recycling is
quota-*negative*; if cache_read carries 0.1× input, context re-read is 58–66% of the bill and
recycling is the largest lever there is. **Two of this wave's biggest recommendations point in
opposite directions on that one undecided coefficient, and neither author noticed** — they ran in
parallel and neither cites the other.

**The settling experiment exists, costs ~3 pp of one account's quota, and nobody ran it.** It is
now the highest-priority open item — **M0, ahead of everything in §4** — because every cost claim
in this plan is conditional on its outcome. Design it to move ONE class at a time against a quiet
account and read the meter: the only reason it was not run here is that the fleet is at 92% weekly
consumption (§2.3), which makes 3 pp a real cost rather than a rounding error. That is a scheduling
constraint, not a reason to skip it — run it in the first hours of a fresh window.

**Also corrected by the critic:** five artifacts price cache-creation at **×1.25** (the 5-minute-TTL
write rate). This fleet is on the **1-hour TTL** (§2.4), whose write multiplier is **×2**. Every
dollar-side figure in A3, A5, A6, A7 and A0 is understated on that term. The correct value was in a
durably recorded field nobody read.

---

## §3 Design

### §3.1 Three layers, and the join is the whole product

The reason no existing instrument answers the operator's question is that the fleet has a good
numerator and a good denominator and **nothing that converts between them**. That converter is
§2.1's price list, and it is the actual deliverable.

| layer | what it answers | what to use | token cost |
|---|---|---|---|
| **L1 numerator** — what we spent | tokens by class, by model, by session/skill/subagent | **Claude Code's native OTel** (`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `claude_code.token.usage` carries a type attribute per class) + the retrospective transcript census as the audit path | **zero** — out-of-band exporter, nothing enters a prompt |
| **L2 denominator** — what we're allowed | weekly / 5h / Fable-scoped percent + reset stamps | **`account-utilization.jsonl`** — already exists, ~6 min cadence, 94% wall-clock coverage, rides a sweep that already happens | **zero** — disk only |
| **L3 the join** — what it *cost us* | tokens → weekly percentage points | **the price list**, re-fitted on a schedule from L1×L2 | zero |

Nothing here needs a new daemon or a new network call. L1 is a config flag Anthropic maintains; L2
exists; L3 is arithmetic. **The no-bloat constraint (scope c) is satisfied by construction, not by
discipline** — the whole instrument lives outside the model's context.

### §3.2 The four numbers that steer, and the ones that are forbidden

A metric earns its place only if a specific action changes when it moves.

| metric | definition | the action it drives |
|---|---|---|
| **burn ratio** | `weekly_pct ÷ elapsed_fraction_of_window` | `>1.15` → route new work off this account · `<0.85` → this account can absorb more · `~1.0` → on pace |
| **projected end-of-window pct** | `weekly_pct ÷ elapsed_fraction` × 100 | alarm before an account reaches 100 and goes down for days — the failure `next3` already hit |
| **quota by class** | output pp vs cache_creation pp | tells you *which* lever to pull; without it, effort goes to the 96% of tokens that cost nothing |
| **output per session, trended** | median output tokens/session | the 61%-of-quota lever; a rise with no rise in delivered work is the one true waste signal |

🚨 **Forbidden by §0:** any metric shaped *quality per token*, *cost per finding*, or *tokens per
commit*. Those invite exactly the Q3 trade the admissibility rule denies, and a number that exists
will eventually be optimized. The instrument must be structurally incapable of arguing for a quality
cut. Cost is reported **per class and per account**, never per unit of output quality.

### §3.3 Design laws carried from the evidence

1. **Report against window phase, never against the window.** A point-in-time percent on a resetting
   counter inverted this investigation's own premise (§1). Every rendered quota figure carries its
   elapsed fraction.
2. **Dedupe on `message.id` or be wrong by 2.4×.** Claude Code writes a streaming assistant message
   to the transcript repeatedly (58.7% repeat records, 98.5% byte-identical, never spanning files).
   Any census that sums records over-counts. *This must be a named, tested invariant* — it silently
   corrupted a keystone number in this very wave.
3. **Prefer the token-free channel.** Disk, statusline, OTel, on-demand renderer. `additionalContext`
   only where it changes the current turn's decision — and never over ~9,200 bytes, because the
   harness silently replaces a larger payload with a head-truncated stub (§2.4).
4. **Abstain, never impute.** Carried from `CONTEXT_ECONOMY_V2`. A missing window, a missing
   denominator, an unfitted coefficient → report null.
5. **One renderer.** `claude-accounts --readout` stays the single surface; the burn ratio is added to
   it rather than growing a second reader that can drift.

### §3.4 The ranked levers, priced

Every item is Q1 (free win) or Q2 (utilization win) under §0. **No Q3 appears anywhere in this plan.**

| # | lever | class | evidence | quality risk |
|---|---|---|---|---|
| 1 | **Output discipline** — enforce the existing CLAUDE.md § Communication Discipline rule; it governs 61.4% of quota and is currently prose-only | Q1 | §2.2 | **NONE** — removing words that carry no information cannot lower quality |
| 2 | **Wall-proximity alarm** on projected end-of-window pct | Q2 | `next3` hit 100% | **NONE** |
| 3 | **Fix `cache-expiry-warning.sh`** — TTL 300→3600 and drop the `/clear`/`/compact` advice | Q1 | **77.3% of its fires are false** (184 of 238 in a 13,622-gap sample); advice inverts §2.2 | **NONE** — it currently *causes* quota spend |
| 4 | **Fix the truncated DoD carrier** — stop concatenating the frozen legacy store; emit newest-first under the cap | Q1 | 51% of injections truncated to the *oldest* scope | **NONE** — this is a quality *restoration* |
| 5 | **De-duplicate `./CLAUDE.md`** — byte-identical to the global copy on all 5 load paths | Q1 | ~5 pp/week fleet (~2%) | **NONE** — zero informational loss, verified by md5 |
| 6 | **Enable OTel** in all 5 config dirs | Q1 | 0 of 5 today; token-free | **NONE** |
| 7 | **Raise `account-utilization.jsonl` retention** past 6 days | Q1 | it is the only durable denominator | **NONE** |
| 8 | **Cache-creation hygiene** — line-ranged reads, agents delivering to files rather than into the lead's window | Q1 | 37.9% of quota | **NONE** — already this repo's practice; make it measurable |

**Explicitly REJECTED levers**, recorded so they are not re-proposed:

- **Shrinking context / recycling to save quota** — optimizes the free class (§2.2). Recycling remains
  right for *rot* and for the hard context ceiling; it is no longer a cost argument.
- **The Fable 50% arbitrage** — refuted by A6: Fable draws weekly quota in proportion to its list
  price and costs ~3.1× an Opus turn realized.
- **Effort downgrades** — effort moves output tokens within a turn whose cost is dominated by
  conversation cache, so a downgrade buys little and risks quality: a Q3, rejected outright. *(A6's
  supporting numbers were corrected by its skeptic — output is 10.8% not 13.1% of an Opus-5@high
  message, rising to ~19–32% once you account for a persisted output token being re-read as cache on
  every later turn. The conclusion is unchanged; the margin is narrower than A6 claimed.)*
- **Effort UPGRADES — A6's own recommendation R3 (raise the floor to `xhigh`) is also REJECTED.**
  Its evidence was the "5.6× thinking-token ladder", which **does not reproduce**: it was an artifact
  of counting one API response as up to 8 turns *and* excluding 51% of the corpus. Deduped over the
  full corpus the ladder is **non-monotone** — `xhigh` yields *fewer* output tokens than `high`.
  So this data justifies neither raising nor lowering the effort floor, and the honest position is
  that **the effort question is open**, not settled in either direction. Filed as such rather than
  answered. *(Noted with some irony: this session itself runs at `xhigh`.)*
- **The Fable 50% arbitrage** — refuted twice, and harder on the second pass: the skeptic's
  independent estimator puts Fable's quota draw per list-dollar at **1.79× Opus** (90% CI
  [1.67, 1.90], P(ratio < 0.75) = 0.000). There is no discounted lane to exploit.
- **Cutting telemetry to save tokens** — it is 0.6–1.2% of throughput, and the two defects found are
  quality failures, not cost ones.

## §4 Implementation

**Execution locus: S (dispatched session) for every wave below except M5**, per Phase 0 and the
global default. Each fires with `--goal` naming a measurable end state and the command that proves
it, because the goal evaluator is tool-less and can only judge what the session *prints*.

🚨 **ORDER REVISED after A2's skeptic (see §2.3).** M1 was originally first. It is a **demand**
lever aimed at a supply the fleet already consumes 92% of, so released un-governed it would wall
every account in 1.5–2 days. **M3 now ships first and M1 depends on it.** M2 is independent of both
and can fire in parallel with M3.

| id | wave | locus | end state (the `--goal` condition) | why it ranks here |
|---|---|---|---|---|
| ~~**M0**~~ | ✅ **DONE 2026-08-16 — Identify the meter** (§2.8). Ran on `next2`: 31.7M cache_read vs 208 output; list pricing predicted 4.62 weekly pp, meter moved 1. **cache_read weight ≤0.018–0.049 pp/Mtok — at most a quarter of list price, plausibly zero.** | L (ran inline) | met — `meter-experiment.md` carries the arm, both meters, the bound under 4 attribution assumptions, and the 2 instrument failures caught en route | Cost **1 weekly pp**, 43 min — under the 3 pp estimate because the meter moved, making the staged positive control unnecessary |
| **M1** | ⏭ **NEXT (unblocked by M3)** — **Govern the dispatcher** — 254 of 261 items are parked behind a cloud-only venue filter since 2026-08-11; admit them **against measured headroom**, never wholesale | S — ~~blockedBy M3~~ **ready** | the dispatcher fires while its account's burn ratio is below pace and throttles as it approaches 1.0; over one full weekly window no account exceeds 100% and the parked count falls; do not release the queue un-governed, and do not disable any safety gate to do it | Re-scoped from "unblock" to "admit against headroom". **Un-governed it is Q3** — 26–74× the remaining allowance, 4–5 walled days/week |
| **M2** | **Fix the DoD truncation** — `dod-persist.sh` concatenates a frozen legacy store, overflows the ~9,200 B cap, and delivers the *oldest* scope | S | a session in this repo shows the NEWEST `Scope (frozen):` line inline in `hook_additional_context`, with no `<persisted-output>` stub, on 3 consecutive starts | **Quality restoration.** 51% of injections currently carry a superseded contract — the frozen-DoD mechanism is silently not working |
| ~~**M3**~~ | ✅ **DONE 2026-08-16 `47ddbf47c` — the burn-ratio instrument.** `wall_projection()` in `bin/claude-accounts`: `burn_ratio` = (weekly_pct/100) ÷ elapsed_fraction, `proj_end_pct`, `wall_risk`, all exported per row; the footer is re-captioned from `pace to 100%` (which named the failure mode as the goal) to *weekly burn (1.00× = lands exactly at the 100% wall)* and flags `⚠ WALL`. **Abstains below 5% elapsed** — the load-bearing guard: at 1 h in, a 1% reading projects to 168% and would page on every fresh window. | **L** *(deviation from the S default: the metric's whole content is the correction this session measured; a dispatched brief would have had to re-derive it, and the change is one function + one footer)* | met — live on 4 accounts at 0.46/0.51/0.54/0.73×, all projecting 46–73% by reset, no wall risk | Closed the error class that inverted this plan's own premise (§1), in the renderer that produced it. 8 bats, RED-proved 8/8; the floor additionally mutant-proved (0.05→0.0 reds case 1 alone) because an absence-red is weak |
| **M4** | **The price list as code** — `cc-quota-price`: re-fit tokens→pp on a schedule from `account-utilization.jsonl` × deduped transcripts, with the **`message.id` dedup as a tested invariant** | S | `cc-quota-price --selftest` passes, including a RED-proof case that a non-deduping extractor inflates output tokens ≥2× | Without it, every later cost claim is unpriced — and the dedup bug silently corrupted a keystone number in this very wave |
| **M5** | **De-duplicate `./CLAUDE.md`** — byte-identical to the global copy on all 5 load paths; move the versioned source to a path Claude Code does not auto-load | **S** *(reclassified — see below)* | a session in this repo loads the global CLAUDE.md exactly once; the deploy gate still asserts repo↔live parity from the new path; `install.sh` still reports the line count | Q1 free win, ~5 pp/week fleet, zero informational loss |
| **M6** | **Enable OTel** in all 5 config dirs + a local collector | S | `claude_code.token.usage` rows land in the collector for a live session, and `grep ENABLE_TELEMETRY` finds it in 5/5 settings.json | The token-free numerator; scope (c) satisfied by construction |
| **M7** | **Disconnect or repair `cc-value`'s extinct join** — it joins on a git trailer this repo measured extinct 4 days ago | S | `cc-value` either reports ABSTAIN with a named reason, or joins on a key with >0 coverage proven in its output | An instrument silently reporting over an empty join is worse than no instrument |

**M5's blast radius, recorded because it caught the lead out.** M5 was first written as `L` — "one
file move, briefing a session costs more than doing it". A reference sweep before touching anything
showed that is false: `./CLAUDE.md` is not merely a duplicate, it is the **deployed source** of the
global instructions. `install.sh:660-676` copies it to `~/.claude/CLAUDE.md` and prints its line
count; `deploy-parity-assert.sh:733-752` runs a whole gate class (`CLAUDE.md (copy)`) asserting
repo↔live parity and reports `NOVERDICT` if the diff cannot run; `deploy-link-parity.sh:21` and
`scripts/gate-select.sh:192` name it too. Moving it is a ≥4-file change **that modifies a deploy
gate**, which is exactly the shape the default locus exists for. *Generalisable: "it's one file" is
a claim about the edit, not about the blast radius — sweep the references before choosing the
locus.*

**Not scheduled, deliberately.** Cache-scope consolidation (Anthropic scopes the prompt cache
per-directory, worktrees included; 381 project dirs, 80 touched in 7 days) is a real
cache_creation lever but it collides head-on with the worktree-per-writer isolation rule, which
exists to prevent index corruption and lost commits. **That trade is a genuine fork and it is the
operator's, not mine** — quota savings vs. concurrency safety, where the safety side has a measured
incident history. Filed rather than decided.

### §4.1 Landed this session

| commit | what |
|---|---|
| `7c9f36316` | `fix(cache-expiry-warning)` — TTL 300s→3600s (77.3% of its fires were false) and the `/clear`//`/compact` advice removed, because against the weekly limit it converted a free `cache_read` into a paid `cache_creation`. Verified with a positive control. |

## §5 The weekly-drain planner — implementation spec

> **INTEGRATION NOTE — this is a NEW section to be APPENDED after §4.1 of
> `docs/plans/USAGE_TELEMETRY_100P.md`.** That file is 552 lines and INTEGRATE-never-overwrite
> binds: do **not** rewrite it, do **not** touch §0–§4.1, and do **not** re-number the existing
> sections. Append this whole block as `## §5` and leave everything above it byte-identical.
> §3.3's design laws (L1–L4) and §3.2's forbidden metric shapes bind everything below and are not
> restated except where a decision turns on one.

**Verdict first.** The synthesis shipped five metrics on the claim that a **strand forecast with
~20 h of lead time** is the product. Adversarial verification refuted that claim on four
independent grounds, and refuted the 5h sub-cap's dismissal as well. What survives is smaller,
sound, and still worth building: **the fleet strands 43 pp per 8 completed account-weeks, and
nothing today names which account is losing it.** The planner ships as a **nowcast + a start-time
constraint + a burst-feasibility read**, with the forecast's lead-time claim withdrawn and replaced
by a falsifiable scoring harness that must run before any alarm is trusted.

Every number in this section was re-measured for this spec by scripts in
`scratchpad/SPEC_{roll,core,win2,live,burst,next3}.py` against
`~/.claude/logs/account-utilization.jsonl` — **12,581 records, 0 parse failures**, 4 accounts,
`2026-08-10T05:58Z → 2026-08-25T09:47Z` (15.16 d). Where a figure is carried from the synthesis or
from a verifier rather than re-measured here, it is marked *(carried)*.

---

### §5.1 Amended design — what changed against the synthesis, and why

| # | Synthesis claim | Verdict | What ships instead |
|---|---|---|---|
| LB-1 | `K = 0.192` weekly-pp per session-pp, band [0.185, 0.198], is a **plan constant** | **SURVIVES** the value; the *justification* is struck | `K` ships, **re-fit on read** with a band guard (§5.2 S1c). The words "plan constant" are deleted. |
| LB-2 | The strand forecast called 4/4 strands with **median ~20 h lead**, 0/4 false positives | **REFUTED — fatally** | The forecast becomes a **nowcast** (M3a). The lead-time claim is withdrawn entirely. A causal, **≤12 h-capped** rescue alarm (M3b) ships only after the scoring harness (M3c) clears it. |
| LB-3 | The 5h sub-cap **cannot bind**; M4 ships as a **veto** | **REFUTED for the planner's span** | M4 as specified is **deleted**. Replaced by M4′ `burst_start_by_h`, a **trigger** and a **start-time constraint**, sized on the burst denominator. |
| LB-4 | Replacing `burn_5h_ph` changes the **router's exclusions** | **REFUTED — structurally impossible** | M1 ships as a **correctness + availability** fix with the exclusion claim deleted and its regime blind spot named. Ranked last, not first. |

#### LB-1 — K survives; two amendments ride with it

I re-derived K independently rather than accept it: **adjacent non-rolling pairs, dt ≤ 0.5 h,
minute-ROUNDED roll keys on both meters → K = 0.1925** (n = 11,026 pairs, Σ Δsession = 4,047 pp,
Σ Δweekly = 779 pp). That is the third independent reproduction (synthesis 0.1927, verifier 0.1923
telescoping / 0.1924 pairs) and it lands inside the shipped band.

**Amendment 1 — strike the justification, keep the number.** The verifier showed the pooled
ratio-of-sums structurally averages mix away: jittering per-window K by ±30% leaves the pooled
estimate at 0.1922 and in-band on 85% of trials. So the pooled fit carries almost no information
about workload-invariance, and only the stratified tests can see it — at a minimum detectable mix
shift of ~4–5% (Fable-gained, `s1 ≥ 90`) to ~11% (`w0 ≥ 80`). **The defensible statement is:**

> *No workload effect larger than roughly 5–11% exists in the mix dimensions this log records.
> A shift common to every recorded dimension is untestable here.*

**Amendment 2 (NEW — measured for this spec) — the band is already breached by the trailing
window, so K may not be a frozen literal.** Re-fitting on trailing slices:

| trailing from | Σ Δsession pp | K |
|---|---|---|
| 2026-08-19 | 1,771 | 0.1982 |
| 2026-08-20 | 1,510 | 0.1987 |
| 2026-08-21 | 1,350 | **0.2000** |
| 2026-08-22 | 1,019 | **0.2012** |

The last two sit **above** the shipped band's ceiling of 0.198. The verifier saw the same drift
(Aug 22–25 window-level 0.2000 [0.1947, 0.2060]; permutation test on late-vs-early diff +0.0065,
**p = 0.0948**, not significant at 0.05). It is not proven to be a real change — but a frozen
literal has no path to learn that it became one. This is MEMORY.md
`resident-policy-must-not-restate-perishable-facts` and `published-figure-decays-with-its-source`
applied to a coefficient: **ship K as a live fit with a fallback and an abstain**, per §5.2 S1c.

**Amendment 3 — record the trap, so no future session re-reports it as a finding.** Binning K by
burn intensity produces a spectacular apparent workload dependence (observed by Δsession bin:
0.1245 / 0.1774 / 0.1824 / 0.1926). It is entirely an instrument artifact — burn intensity is
Δsession/Δt, so binning on it is **binning on K's own denominator**. A simulation with K set to
*exactly* 0.192 reproduces the same monotone pattern (0.1463 / 0.1751 / 0.1866 / 0.1916).
*(carried, verifier)*. This is `positive-control-the-denominator.md` and
`proxy-must-be-independent-of-what-it-supplements.md`. **Anyone re-testing K will hit this. It is
not a finding.**

#### LB-2 — the forecast is dead as a forecast; it survives as a nowcast

The synthesis's headline — *"this lead time IS the product"* — is withdrawn. Four independent
kills *(carried, verifier; I did not re-run the 504-config sweep)*:

1. **The score was a tautology.** The fire rule ("projected strand holds ≥ 4 pp and never retracts
   thereafter") is non-empty only at the window's **last** sample, where `reset_h → 0` (median
   0.03 h) and the projection therefore converges to `100 − weekly_pct` — **the true strand**. The
   rule fires iff the true strand ≥ 4 pp; verified to agree with the identity function on 8/8
   windows. Recall 4/4 and FP 0/4 are guaranteed for *any* estimator of this form. A control that
   cannot fail is not a control (`gate-must-not-key-on-its-own-signal.md`).
2. **Scoring it causally destroys the FP record.** Per-instant, the three windows that closed at
   98 / 99 / 100% fire on 28.8% / 66.6% / 91.7% of their evaluable instants. next2's 08-22 window
   closed at **exactly 100%** — the operator's stated goal — and was forecast to strand up to
   100.0 pp for two-thirds of its life.
3. **The temporal split fails.** Parameters fixed, week-1 resets score 3/3 recall + 0/1 FP;
   held-out week-2 resets fire on **4 of 4** windows, FP 3/3.
4. **No long-horizon causal rule exists.** Across 504 causal configurations (floor 2–30 pp × dwell
   0–24 h × horizon cap 6–168 h), exactly 18 achieve 4/4 + 0 FP, and **every one caps the horizon
   at ≤ 12 h**. Maximum lead achievable by any clean causal rule: **11.96 h**.

**The operator's "planned hours/days ahead" requirement is therefore NOT met by this data, and the
spec says so plainly rather than shipping a number that cannot support it.** What ships:

- **M3a — the nowcast.** Same arithmetic, honest framing: *"at the pace of the last 48 h, this
  window lands at X% and Y pp die at reset."* No lead-time claim, no alarm semantics.
- **M3c — the scoring harness** (`--strand-score`). Horizon-stratified signed error per
  (window, horizon bucket ∈ {96, 48, 24, 12, 6} h). ~45 scored cells today against 8 binary
  outcomes. **This instrument can fail.** It is a prerequisite, not a nicety.
- **M3b — the ≤12 h rescue alarm**, on probation, gated behind M3c showing it survives a temporal
  split. In-sample it is 4/4 + 0 FP across 18 settings (floor 2–5 pp, dwell 1–8 h), which largely
  dissolves the in-sample-floor objection at short horizon — but it is still a 3-parameter fit on
  n = 8 and **the temporal split was never run on it**.

**One correction to the refutation, measured for this spec.** The verifier's *"BONUS METHOD
DEFECT"* — that the spec's minute-rounded roll key flips on ~42% of adjacent pairs and collapses
recall to 0/4 — is **itself an implementation error**, and it matters because it would have sent an
implementer chasing a non-existent defect. My measurement over 9,777 adjacent pairs (dt ≤ 1 h):

| roll-key spelling | key changes | rate | agrees with ground truth (reset shift > 1 h)? |
|---|---|---|---|
| string prefix `s[:16]` (**truncation**) | 4,498 | **46.0%** | no — 4,399 spurious |
| **`round(epoch/60)`** | **99** | **1.0%** | **yes — 99 of 99, exact** |
| ground truth: reset stamp moved > 1 h | 99 | 1.0% | — |
| cross-check: `session_pct` decreased | 98 | 1.0% | — |

Weekly stamp, same test: truncation 5,136 of 11,310 (45.4%); **rounding 3, ground truth 3.** The
stamp's second-of-minute distribution is `00: 1,880 · 59: 1,427 · 01: 13 · 17: 1` — it straddles
the boundary, which is exactly why truncation fails and rounding does not. **Rounding is correct
and the verifier's kills 1–4 stand without it.** *(This also retires the verifier's inference that
M1's MAE win "must have been measured with a roll rule other than the one documented" — it was not;
the second verifier independently reproduced the win using rounding.)*

#### LB-3 — the sub-cap is a planning constraint after all; M4 is deleted

The synthesis's M4 is **unshippable on its own evidence** and is removed rather than weakened:

- Recomputed over the whole series it reads `REACHABLE` on **10,556 of 10,623** evaluable samples
  = **99.37%**, so `P(4/4 REACHABLE | null instrument) = 0.9937⁴ = 97.5%` — the "4/4 historical
  strands" evidence carries ~0.04 bits. *(carried, verifier)*
- During the **five wall episodes it exists to detect** — the exact event — it reads `REACHABLE` on
  **100% of 74 samples** and never once flips. `reach_pp` and `need` are both monotone in
  `(weekly_pct, hours-remaining)`, so the comparison is near-algebraically fixed. The synthesis's
  own §1.4 wrote *"a capability metric can never be the alarm"* and then cited the same 4/4 as
  evidence **for** M4. One observation, used in both directions.

**The stratification that kills the dismissal, reproduced exactly by me:**

| 5h segments by peak `session_pct` | n | walled | rate |
|---|---|---|---|
| idle < 10 | 130 | 0 | 0.0% |
| light 10–30 | 76 | 0 | 0.0% |
| moderate 30–50 | 27 | 0 | 0.0% |
| heavy 50–80 | 11 | 0 | 0.0% |
| **BURST ≥ 80** | **8** | **5** | **62.5%** |
| total | 252 | 5 | 1.98% |

Fisher exact two-sided **p = 6.9e-09** *(carried)*. The 1.98% headline averages over a population
that is overwhelmingly idle — 130 of 252 segments never passed 10%. **The operator's entire goal is
to convert idle windows into burst windows**, and in the regime the planner *creates*, the cap
binds 5 times in 8. `count-the-population-the-remedy-acts-on.md`,
`control-fixture-must-reach-the-bugs-regime.md`.

**The 6.5× headroom is a 168-hour average and decays with the horizon** — 1.00× at 5 h remaining,
0.60× at 3 h. Empirically the BINDS verdict fires on 0.0% of samples beyond 12 h remaining and on
14.0–16.7% inside the final 6 h *(carried)*.

**And the loss is not inside the window — it is the frozen tail.** All 8 burst windows delivered
13–20 weekly pp regardless of walling. The damage is the freeze that follows. Measured, the 8 burst
windows:

| acct | window start | peak 5h% | weekly gain | fill h | session-pp/h | wall | wall h |
|---|---|---|---|---|---|---|---|
| next3 | 08-10 07:20Z | 100 | 20 | 1.40 | 71.66 | **WALL** | 3.53 |
| next4 | 08-11 08:03Z | 85 | 13 | 4.87 | 17.46 | — | — |
| next3 | 08-16 20:06Z | 100 | 20 | 3.45 | 28.40 | **WALL** | 1.42 |
| next | 08-17 19:55Z | 100 | 19 | 4.42 | 22.64 | **WALL** | 0.31 |
| next3 | 08-18 00:33Z | 100 | 19 | 4.33 | 23.09 | **WALL** | 0.55 |
| next3 | 08-18 05:38Z | 100 | 19 | 2.37 | 41.39 | **WALL** | 2.45 |
| next4 | 08-22 20:34Z | 99 | 19 | 4.83 | 20.50 | — | — |
| next3 | 08-23 21:16Z | 86 | 17 | 4.85 | 17.12 | — | — |

**Shipped burst constants** (all from this table): `P_WALL = 5/8 = 0.625` ·
`BURST_SPPH` (median sustained fill) = **22.87 session-pp/h** = 4.39 weekly pp/h at K = 0.192 ·
`MEAN_WALL_H = 1.653` (median 1.425) · **expected freeze per burst window = 1.033 h**.

⚠️ **`P_WALL` is a LOWER bound.** Inter-sample gaps are p50 6.4 min / p90 7.8 / p99 12.4, and a
≥2-sample wall detector cannot see a freeze shorter than ~13 min *(carried)*.

**The forward arithmetic the design must absorb:** closing the measured 19.9 pp/week fleet strand
needs **1.04 extra full 5h windows/week**. At the burst wall rate that moves fleet walls
2.31 → 2.96/week, i.e. **1.72% → 2.20% of all 5h windows — past the 2% inversion trigger the
original claim named, before the planner is even built** *(carried)*.

#### LB-4 — M1 keeps its accuracy, loses its story, and drops to last

- **The exclusion claim is CODE-FALSE and must be deleted from the spec.** `_excluded()` computes
  `su = r["session_pct"] / 100.0` at `bin/claude-accounts:2045` — the **raw** meter. `_su_projected`
  is read only at `:1372` (inside `_soft`) and `:2197` (inside `desk_keys`). `_soft` returns
  `SF*KF*CF` with `SF ≥ SF_FLOOR = 0.05`, so it is floored at 0.0025 > 0 and can never trip
  `_rank_pass`'s `s > 0` gate. **No value of `burn_5h_ph` can ever change an exclusion.** Proven
  with a positive control rather than asserted: feeding an absurd `burn_5h_ph = 5.0` across 11,530
  rows changed **score values on 10,489 rows and desk tiers on 11,200 — and exclusions on 0**.
  *(carried, verifier)*
- **Its measured effect is small and absent where the goal lives.** rank[0] flips: 46/3,011 (1.5%)
  general, 64/3,011 (2.1%) desk, 139/11,479 (1.2%) desk-tier — but **0 of 64 general flips** in the
  `weekly_reset ≤ 6 h AND session_pct ≥ 50` stratum, which is precisely the end-of-window regime
  the operator's goal names. *(carried)*
- **It inverts in the burst regime.** Scored against realised `session_pct` 1 h later (n = 4,017),
  EWMA wins overall (MAE 0.0282 vs 0.0388, **−27.3%**, paired t = 11.6) but **loses at
  `session_pct ≥ 40`** (n = 133): incumbent 0.0617, EWMA 0.0797, EWMA over-projecting by +0.0355.
  *(carried)*. Direction note: `_su_projected` is soften-only, so over-projection at high load is
  **fail-safe for routing** — it makes a loaded account less attractive. It is still wrong as a
  measurement and M1's abstain rule must not pretend otherwise.

So M1 ships as a **correctness + availability fix** (non-inert on 93.5% of rows against the
incumbent's 20.7%), ranked **last**, with the honest action line: *"feeds the SF multiplier in
`_soft` (score-ranking only, floored so it can never exclude) and the desk lane's
`DESK_5H_FLOOR` tier key in `desk_keys`."*

#### What is now the product

> **Name the account that is about to lose quota, say how much, say whether it can still be spent,
> and say by when the spending must start.** Four facts, none of which any surface renders today.
> The synthesis promised a fifth — *how early you could have known* — and the data does not carry
> it beyond ~12 h.

---

### §5.2 The shippable change list, ranked by value / effort

Ranking is against **the operator's goal**, not against instrument quality. M1 is the best-measured
change in the list and ranks last because it provably does not move the goal.

| rank | id | what | blocks / blocked by | effort |
|---|---|---|---|---|
| **S1** | data fixes | roll-key rounding · `_util_tail` by time · live-window exclusion · live-K fit | **blocks everything below** | S |
| **S2** | M5 | `burst_percentile` — is the demand physically routine or a p95 stunt? | S1 | S |
| **S3** | M3a + M2 | `wk_strand_pp` nowcast on a roll-aware weekly EWMA | S1 | M |
| **S4** | M4′ | `burst_start_by_h` — the start-time constraint | S1, S2 | M |
| **S5** | M3c | `--strand-score` — the falsifiable scoring harness | S3 | M |
| **S6** | M3b | `wk_strand_alarm` ≤12 h, latching, causal | **S5 must clear it first** | S |
| **S7** | M1 | `burn_5h_ewma_ph` — correctness/availability only | S1 | S |

**L3 (one renderer) is held.** Every live metric renders through `readout_lines`
(`bin/claude-accounts:3141`) via `pace_line` (`:2006`, called at `:3375` and `:3696`). No new live
surface. The one new flag, `--strand-score` (S5), is argued as an exception in its own entry.

---

#### S1 · Data fixes — these land FIRST, in one commit, and nothing below is trustworthy until they do

##### S1a — the roll key must ROUND, never truncate

**Change.** Add a module-level helper beside `_util_tail` (`bin/claude-accounts:1877`):

```python
def _reset_key(stamp):
    """Minute-ROUNDED reset-stamp key. The stamp jitters sub-second and STRADDLES the minute
    boundary (measured second-of-minute over 4,000 records: 00:1880 · 59:1427 · 01:13 · 17:1),
    so a string prefix or a truncation splits one window into two on 46.0% of adjacent pairs and
    the roll branch then injects an ABSOLUTE level as a delta. Rounding flips on 1.0% and agrees
    with ground truth (reset shift > 1 h) on 99 of 99. None means NO WINDOW OPEN — a distinct
    state, not missing data."""
    if not stamp:
        return None
    try:
        t = datetime.fromisoformat(str(stamp).replace("Z", "+00:00")).timestamp()
    except (ValueError, TypeError):
        return None
    return round(t / 60.0)


def _rolled(a, b, stamp_field, pct_field):
    """True when the window between two samples RESET. Two independent witnesses, OR'd: the
    rounded key changed, or the meter went backwards. Neither alone is sufficient — a key
    comparison is blind to a same-key reset, and a pct decrease is blind to a reset that
    lands on the same value."""
    ka, kb = _reset_key(a.get(stamp_field)), _reset_key(b.get(stamp_field))
    if ka is not None and kb is not None and ka != kb:
        return True
    pa, pb = a.get(pct_field), b.get(pct_field)
    return pa is not None and pb is not None and pb < pa
```

**Arithmetic.** `key = round(epoch_seconds / 60)`. A roll is `key_a != key_b` **OR**
`pct_b < pct_a`.

**Abstain.** `_reset_key(None) → None`, and a `None` key **never** counts as a roll — it means no
window is open (15.0% of rows; 1,789 of 1,790 have `session_pct == 0`).

**Replaces.** Nothing today — `apply_burn` currently infers a roll only from `d < 0`
(`:1930`, `:1943`), which is blind to a same-value reset and is why `burn_wk_ppd` discards every
window that crosses a reset.

##### S1b — `_util_tail` must select by TIME, not by bytes

**Change.** `_util_tail` at `bin/claude-accounts:1877`, signature
`_util_tail(path=None, max_bytes=131072)`, called with **no argument** by `apply_burn` at `:1918`.

**The defect, re-verified against the live file:** 3,675,531 B, mean record 292.4 B → the 128 KiB
tail parses **407 rows spanning 12.16 h** against a docstring claiming 48 h *(carried; the byte
figures are the synthesis's, the coupling is structural)*. **M2's 48 h lookback is unreachable
today.** Worse, the coupling is undocumented and inverted: adding any field to the record (e.g.
`k_agents`, task #171) silently *shortens* the window.

**Arithmetic.** Keep the byte seek as a cheap pre-filter but size it from the requirement:
`max_bytes = max(131072, int(hours * 3600 / median_interval_s * mean_record_b * 1.5))`, then
**filter the parsed rows by `now - _t <= hours*3600`** and, critically, **assert the achieved
span**. New signature: `_util_tail(path=None, hours=48.0, max_bytes=None)`.

**Abstain.** Return the rows **and** the achieved span; every consumer's abstain rule is written
against the achieved span, never the requested one. A consumer asking for 48 h and receiving 12 h
must see 12 h and abstain on its own rule — it must not be told it got 48.

**Also fix (same commit, cheap):** the rotation cliff. `config/store-bounds.manifest:47` rotates
this file at 25 MiB; at 237 KiB/day that lands ~2026-12-11, and **all readers open only the live
path**, so at rotation every burn estimate silently drops to a series of length ~0. Glob the `.gz`
siblings newest-first until the requested span is covered.

##### S1c — K is fitted live, with a fallback and an abstain

**Change.** New module-level function beside `apply_burn`:

```python
K_FROZEN   = 0.192      # pooled, 2026-08-10..25, n=11,026 pairs (Sds=4047, Sdw=779) -> 0.1925
K_MIN_SDS  = 300.0      # session pp of movement below which the trailing fit is too thin to use
K_SANE     = (0.175, 0.210)   # outside this the PLAN changed (or the meter did) -> abstain

def exchange_rate(samples, hours=168.0):
    """weekly pp per session pp, fitted on the trailing window. Ratio-of-sums over adjacent
    non-rolling pairs (dt <= 0.5 h) -- NEVER a mean-of-ratios (quantization biases that upward at
    small windows: 0.158 below 5 session pp vs 0.192 above 30) and NEVER binned by burn intensity
    (that is K's own denominator; a simulation with K exactly 0.192 reproduces the whole apparent
    trend). Returns (K, sum_ds, 'live'|'frozen'|None)."""
```

**Arithmetic.** `K = Σ Δweekly / Σ Δsession` over adjacent pairs where **neither** meter rolled
(`_rolled` on both), `0 < dt ≤ 0.5 h`, both deltas ≥ 0.

**Abstain (L2), three-way:**

| condition | result |
|---|---|
| `Σ Δsession < K_MIN_SDS` | fall back to `K_FROZEN`, source `"frozen"` |
| fit outside `K_SANE` = [0.175, 0.210] | **return `None`** — every K-consuming metric abstains |
| otherwise | the live fit, source `"live"` |

**Why the guard and not a wider band.** Trailing-from 08-21 already reads 0.2000 and 08-22 reads
0.2012, above the shipped ceiling of 0.198, on Σ Δsession of 1,350 and 1,019 respectively. That is
either drift or noise (permutation p = 0.0948) — but a *frozen* literal cannot tell the difference
and a *silently widened* band launders a plan change into a number. Abstaining is the only reading
that stays honest under both hypotheses.

##### S1d — a completed weekly window requires its reset to be in the PAST

**This one I hit myself while writing this spec, and it would have corrupted the acceptance test.**
The synthesis's completed-window rule is *"reset observed with the last sample ≤ 3 h before it."*
That rule **admits the currently-live window**, because a live window's newest sample is always
some hours before its own reset. Measured, at `NOW = 2026-08-25T09:47:41Z`:

| detector | result |
|---|---|
| naive (`0 ≤ gap ≤ 3 h` only) | **51 pp over 9 account-weeks** — admits next3's live 08-25 window at 92% |
| **fixed (`reset < now` AND `0 ≤ gap ≤ 3 h`)** | **43 pp over 8 account-weeks** ✅ matches the synthesis exactly |

The baseline is therefore confirmed at **43 pp / 8 completed account-weeks = 5.4 pp per
account-week = 19.9 pp/week fleet-wide**, median 8 pp among the 4 that stranded ≥ 4 pp:

```
next3  reset 08-11 12:00Z  final=100%  strand= 0pp
next2  reset 08-15 11:00Z  final= 92%  strand= 8pp
next   reset 08-16 04:00Z  final= 91%  strand= 9pp
next4  reset 08-16 09:00Z  final= 85%  strand=15pp
next3  reset 08-18 12:00Z  final= 98%  strand= 2pp
next2  reset 08-22 11:00Z  final=100%  strand= 0pp
next   reset 08-23 04:00Z  final= 99%  strand= 1pp
next4  reset 08-23 09:00Z  final= 92%  strand= 8pp
```

**n = 8 is the binding limit on every weekly-side figure in this spec.** It grows by ~3.7 completed
account-weeks per week. The class is `gap-IS-the-mechanism` — a detector for "the window ended"
that fires during the window.

---

#### S2 · M5 · `burst_percentile` — replaces the *rendering* of `weekly_need_pct_per_day`

**Ranked first among metrics because it is the only one no refutation touched, and it answers
failure mode (3) directly.**

**Function.** New `burst_percentile(r, samples)` beside `pace_need_ppd`
(`bin/claude-accounts:1962`). Consumed by `pace_line` (`:2006`).

**Arithmetic.** Required rate `need_pph = (100 − weekly_pct) / weekly_reset_h`, in weekly pp/h.
Express it as its percentile within **this account's own** distribution of realised H-hour weekly
burn rates, where `H` = the nearest of `{1, 3, 6, 12, 24}` h to `weekly_reset_h` **on a log scale**.
The distribution is every rolling H-hour window inside one weekly window with span coverage
0.9–1.15 × H.

**Abstain (L2).** Null when fewer than **200** qualifying windows exist for that account; null when
`weekly_reset_h < 0.5 h`. When `need_pph` exceeds every observed window, render
**"never once achieved"** — never extrapolate a p100.

**Replaces.** Not the field — `weekly_need_pct_per_day` (`pace_need_ppd`, `:1962`) stays, because
it still answers *"how hard would I have to push."* M5 replaces its **rendering as a bare rate**.
The defect it cures: `needs 88%/d over 2.2h` quotes a rate in a unit **11× longer than the window
it must happen in**, which is uninterpretable.

**Live confirmation, and it is out-of-sample.** At 09:27Z the synthesis measured next3 at
**p95.5** (H = 3 h, n = 2,618) to close 8 pp. next3 did **not** perform the p95 burst — it went
92% → 92% over the following 2.2 h and its window closed short. **M5 said "this is a p95 stunt"
and the stunt did not happen.** That is one live case, not a validation, but it is the right
polarity and it is the first out-of-sample datum this design has.

---

#### S3 · M3a + M2 · `wk_strand_pp` on `burn_wk_ewma_ph` — the nowcast

**Functions.** `burn_wk_ewma_ph(samples_for_acct, now, weekly_reset_h)` and `wk_strand_pp(r)`, both
beside `wall_projection` (`bin/claude-accounts:1977`); attached to rows in `apply_burn` (`:1909`)
alongside the existing `burn_ratio` / `proj_end_pct` block at `:1950-1960`.

**M2 arithmetic.** Roll-aware EWMA over `weekly_pct`, in **%/h**. Over adjacent pairs `(a,b)` in
the trailing 48 h with `weekly_pct` present on both and `0 < dt ≤ 1 h`:

```
rolled = _rolled(a, b, "weekly_reset_at", "weekly_pct")        # S1a
d      = b.weekly_pct  if rolled  else  max(0, b.weekly_pct - a.weekly_pct)
w      = 2 ** ( -((now - b._t)/3600) / hl )
value  = Σ(w·d) / Σ(w·dt_h)
hl     = 4.0  if weekly_reset_h <= 6  else  8.0
```

**M2 abstain (L2).** Null when the **raw measured span** (Σ dt over usable pairs — *not* the
weighted span, and *not* the requested lookback) is < **6.8 h**, the span below which ±1 pp
quantization exceeds 25% of the weekly meter's realised mean of 0.592 %/h. Null when fewer than
2 usable pairs exist. **Never** abstain on a roll — reconstruct post-roll accrual as a lower bound.
**Refuse the horizon licence:** any consumer with a horizon > 12 h must use the `hl = 8` form; the
`hl = 4` form may never be extrapolated past 12 h.

**M2 replaces `burn_wk_ppd`** (`apply_burn:1940-1949`) — the widest-pair-inside-48 h estimator.
**It ships on availability and roll-awareness, not on accuracy** (live: incumbent 43.79 / 7.96 /
29.85 / 3.98 %/day vs EWMA×24 = 38.0 / 6.9 / 29.3 / 4.6 — close). Its win is that the incumbent
discards **every** window reset and is therefore blind for the first 12 h of every weekly window —
exactly when the week's plan is set. That reasoning is independent of LB-2 and the verifier
affirmed it survives.

**M3a arithmetic.** `wk_strand_pp = max(0, 100 − (weekly_pct + burn_wk_ewma_ph × weekly_reset_h))`.

The clamp is load-bearing, not cosmetic. It discards the **overshoot** regime where every projector
measured here is badly wrong (on `next` at phase 0.32 the incumbent renders 154.6% and the EWMA
renders **231.4%** against a truth near 100% — the "better" estimator is *worse* on that figure)
and keeps the **shortfall** regime, where the arithmetic is a nowcast of a quantity that actually
converges.

**M3a abstain (L2).** Null whenever M2 abstains. Null when `weekly_reset_h ∉ (0, 168]`. Never
clamp a negative strand into a positive one. **Never render a weekly `proj_end_pct` above 100 as a
number** — report the strand, and separately that the account is on a wall trajectory.

**M3a replaces the weekly half of `proj_end_pct` / `wall_risk`** (`wall_projection`, `:1977`).
`wall_projection` itself **stays** — the 5h `burn_ratio` render is the one raw-percentage figure
§3.3 L1 permits, and `tests/claude-accounts-burn-ratio.bats` continues to pin it unchanged.

🚨 **Framing constraint, and it is the whole amendment.** M3a is rendered as a **nowcast**:
*"at the pace of the last 48 h."* It carries **no lead-time claim** and **no alarm semantics**. The
synthesis's `4/4 recall / 0 FP / median ~20 h lead` line is withdrawn and must not appear in the
plan doc, the docstring, the footer, or a commit message. Rationale: the estimator converges to
truth as the horizon closes, which makes it a **good nowcaster and a bad forecaster** — and the
synthesis published the nowcast accuracy as if it were forecast accuracy.

**What the nowcast is worth today** (my measurement, `NOW = 09:47:41Z`):

| acct | weekly% | reset h | `burn_wk_ewma_ph` | `wk_strand_pp` |
|---|---|---|---|---|
| next | 52 | 114.21 | 1.725 (hl 8) | **0.0** — wall trajectory |
| next2 | 17 | 97.20 | 0.281 (hl 8) | **55.7** |
| next3 | 92 | 2.21 | 1.140 (hl 4) | **5.5** |
| next4 | 14 | 119.20 | 0.186 (hl 8) | **63.8** |

**119.5 pp sits on next2 and next4 with four days of runway, against 5.5 pp on the account the
router is alarmed about.** That inversion is the gain, and it does not depend on any lead-time
claim.

---

#### S4 · M4′ · `burst_start_by_h` — the start-time constraint (replaces the deleted M4)

**Function.** New `burst_start_by(r, K)` beside `pace_need_ppd` (`:1962`), consumed by `pace_line`
(`:2006`). **M4 `wk_reach_pp` as specified in the synthesis is not implemented.**

**The primitive is a START TIME, not a capacity verdict.** All 8 burst windows delivered 13–20
weekly pp whether or not they walled, so the wall is not loss *within* the window — the loss is the
frozen tail. The shippable constraint is: *begin the endgame burst early enough that the burn plus
the expected freeze plus the 5h grid still fit inside the weekly window.*

**Arithmetic.** Constants from the burst table in §5.1: `BURST_SPPH = 22.87`, `P_WALL = 0.625`,
`MEAN_WALL_H = 1.653`.

```
deficit_wk = max(0, 100 - weekly_pct)
need_spp   = deficit_wk / K                       # session pp to buy it   (K from S1c)

# walk the 5h grid: you cannot open window N+1 before window N resets.
t = 0.0 ; rem = need_spp ; windows = 0
avail = 100 - session_pct                          # the OPEN window's remainder
if avail > 0:
    burn_h = min(avail, rem) / BURST_SPPH
    burn_h = min(burn_h, session_reset_h)          # the window may die first
    took   = burn_h * BURST_SPPH
    rem   -= took ; t += burn_h ; windows += 1 if took > 0 else 0
    if rem > 0:
        t = session_reset_h                        # wait out the roll
while rem > 0:
    take = min(100.0, rem)
    t   += take / BURST_SPPH
    rem -= take ; windows += 1
    if rem > 0:
        t += 5.0 - (100.0 / BURST_SPPH)            # wait for the next roll

freeze        = windows * P_WALL * MEAN_WALL_H
t_needed      = t + freeze
burst_start_by_h = weekly_reset_h - t_needed       # <= 0  =>  ALREADY LATE
```

**Verdicts.** `burst_start_by_h > 12` → `SLACK` · `0 < burst_start_by_h ≤ 12` → `START SOON` ·
`≤ 0` → `LATE`, and report the floor: `unrecoverable_pp = deficit_wk − K × BURST_SPPH ×
max(0, weekly_reset_h − freeze)`.

**Abstain (L2).** Null when `K` is None (S1c abstained). Null when `session_pct` or
`session_reset_at` is null — a null stamp means **no window is open**, a distinct state that must
not collapse to zero. Null when `deficit_wk ≤ 0`. Null when `weekly_reset_h ∉ (0, 168]`.

🚨 **Its threshold is sized on the BURST denominator (5/8), never the all-windows one (5/252)**,
and `P_WALL` is a **lower bound** (walls under ~13 min are invisible to the detector). Ships **on
probation**: n = 8 burst windows is the entire evidence base, and the monitoring plan (§5.5) re-runs
the burst-stratified wall rate on every completed weekly window rather than waiting for the
planner.

**Live** (`NOW = 09:47:41Z`, K = 0.192):

| acct | deficit | need session-pp | windows | burn h | freeze h | t_needed | reset h | `burst_start_by_h` | verdict |
|---|---|---|---|---|---|---|---|---|---|
| next3 | 8 | 41.7 | 1 | 1.82 | 1.03 | **2.86** | 2.21 | **−0.65** | **LATE** — floor **2.83 pp** unrecoverable |
| next2 | 83 | 432.3 | 6 | 21.41 | 6.20 | 27.61 | 97.20 | +69.59 | SLACK |
| next4 | 86 | 447.9 | 6 | 22.10 | 6.20 | 28.29 | 119.20 | +90.91 | SLACK |
| next | 48 | 250.0 | 3 | 11.69 | 3.10 | 14.79 | 114.21 | +99.42 | SLACK (no strand — wall trajectory) |

The unrecoverable floor for next3 is computed as stated: freeze 1.03 h of the 2.21 h remaining
leaves 1.18 h of usable burn = `K × BURST_SPPH × 1.18` = **5.17 weekly pp** of the 8 needed, so
**2.83 pp cannot be saved even by a perfect burst starting this instant.**

**This is the metric doing the job the deleted M4 could not.** The synthesis's M4 read next3
`16.9 pp reach vs 8 needed — REACHABLE, 2.1× margin`. M4′ reads **LATE by 0.65 h with a 2.83 pp
floor** — and next3 in fact stranded. The difference is that M4 asked a *capacity* question, which
is nearly algebraically fixed, and M4′ asks a *rate-and-freeze-against-the-clock* question, which
can come out either way.

---

#### S5 · M3c · `--strand-score` — the instrument that CAN fail

**Function.** New `strand_score(samples, buckets=(96,48,24,12,6))` beside `_util_tail`, plus a
branch in `main()` (`bin/claude-accounts:4166`) placed **before** `load_cfg()`, exactly like the
`--agents` branch at `:4178` — it must answer without a sweep, without the keychain, and without a
config.

**L3 exception, argued.** L3 governs the *live state* surface: there is one renderer of "what are
the accounts doing now," and `--strand-score` does not touch it. It renders **history** — scored
past windows — reads only the series, and **nothing routes on it**. It is the mutation-test of the
planner, not a second opinion about the fleet. Shipping it as a flag on the same binary (not a new
`scripts/*.sh`) also rides the existing `~/.claude/bin/claude-accounts` symlink, so it converges on
the trunk fast-forward instead of landing as an ADD the live layer cannot reach (the `LIVE_ADDS`
trap).

**Arithmetic.** For each completed weekly window (S1d rule) and each horizon bucket `H`, take the
last evaluable sample with `weekly_reset_h ≥ H`, compute `projected_strand` from M3a at that
instant, and score **`signed_error = projected_strand − realised_strand`**. Report per bucket:
n, mean signed error (bias), MAE, and the sign-agreement rate.

**Why this replaces the refuted score.** The old rule produced **8 binary cells** evaluated at the
horizon's close, where the projection has already converged to truth — a tautology. This produces
**~45 (window, horizon) cells** at fixed distances from the reset, where it can be, and will be,
wrong. `control-must-replay-the-real-artifact.md` and `verification-harness-vacuous-pass-traps.md`.

**Abstain.** A (window, bucket) cell with no evaluable sample at `weekly_reset_h ≥ H` reports
`n=0` and is **excluded from the aggregate** — never imputed, never counted as a hit.

---

#### S6 · M3b · `wk_strand_alarm` — the ≤12 h rescue alarm, gated behind S5

**Do not build this until S5 has run and been read.** If the horizon-stratified bias at the 12 h
bucket is not near zero, this alarm is not shippable at any parameter setting.

**Function.** `wk_strand_alarm(r, state)` beside `wk_strand_pp`; latched per (account, weekly
window key) in the existing route-records store, not in memory.

**Arithmetic.** Causal, latching: fire when `wk_strand_pp ≥ FLOOR` has held continuously for
`DWELL` **and** `weekly_reset_h ≤ HORIZON_CAP`. Once fired it stays fired for that window.
Shipped defaults: `FLOOR = 4 pp`, `DWELL = 2 h`, `HORIZON_CAP = 12 h`.

**Why exactly these.** The 504-config causal sweep found 18 clean settings (4/4 recall, 0 FP) and
**every one caps the horizon at ≤ 12 h**; the clean region spans `FLOOR ∈ [2, 5] pp` and
`DWELL ∈ [1, 8] h`, so the choice is robust and the in-sample-floor objection largely dissolves at
short horizon. Maximum lead any clean causal rule achieves is **11.96 h** *(carried)*.

**Abstain.** Null whenever M3a abstains. **Never fire beyond `HORIZON_CAP`** — an uncapped version
of this exact rule fires on 3 of the 4 windows that closed at 98–100%, including the one that
closed at exactly 100%.

**What it must be sold as, in the docstring and the footer alike:** *a late-window rescue alarm,
not a weekly planner.* It buys ≤ 12 h, not the ~20 h median / 93 h maximum the synthesis claimed.

---

#### S7 · M1 · `burn_5h_ewma_ph` — correctness and availability only

**Functions.** Producer: new branch in `apply_burn` (`bin/claude-accounts:1909`, replacing the
`burn_5h_ph` block at `:1925-1939`). Consumer: `_su_projected` (`:1860`), which reads
`r.get("burn_5h_ph")` at `:1866`.

**Arithmetic.** Roll-aware EWMA over `session_pct`, trailing 6 h, `hl = 1.0 h`, `0 < dt ≤ 1 h`:

```
rolled = _rolled(a, b, "session_reset_at", "session_pct")      # S1a
d      = b.session_pct if rolled else max(0, b.session_pct - a.session_pct)
w      = 2 ** ( -((now - b._t)/3600) / 1.0 )
value  = Σ(w·d) / Σ(w·dt_h)          #  %/h
```

**Abstain (L2).** Null when the **raw measured span** inside the 6 h lookback is < **1.3 h** — the
span below which ±1 pp quantization exceeds 25% of the 5h meter's realised mean — or when fewer
than 2 usable pairs exist. **Never** null on a roll.

🚨 **Two implementation hazards, both of which silently produce a plausible wrong number:**

1. **UNIT.** The formula emits **%/h**; `burn_5h_ph` is consumed by `_su_projected` as
   **fraction/h** (`:1874`, `su + b * ahead` where `su ∈ [0,1]`). Ship under the **new key**
   `burn_5h_ewma_ph` in %/h and divide by 100 at the consumer, **or** `_su_projected` saturates to
   1.0 on every row — a 100× error that looks like "every account is under 5h pressure."
2. **ROLL SPELLING.** Must be `_reset_key` (rounding, S1a). Under truncation the roll branch fires
   on 46.0% of pairs and injects an absolute level as a delta: MAE degrades 0.0282 → **0.2110**,
   i.e. **5.4× worse than the incumbent it replaces** *(carried)*.

**Replaces `burn_5h_ph`** (`apply_burn:1930-1939`). Keep the old key populated for one release so
nothing that reads it breaks silently.

**The honest action line — this replaces the synthesis's, which was code-false:**

> *Feeds the `SF` multiplier in `_soft` (`:1372-1380`) — score-ranking only, floored at
> `SF_FLOOR = 0.05` so it can never exclude — and the desk lane's `DESK_5H_FLOOR` tier key in
> `desk_keys` (`:2197`). It does **not** reach `_excluded`, which reads the raw meter at `:2045`.*

**Named blind spot, which must ship in the docstring:** at `session_pct ≥ 40` the **incumbent is
more accurate** (MAE 0.0617 vs 0.0797; the EWMA over-projects by +3.6 pp). That is the burst
regime — the one the planner creates. The over-projection direction is soften-only and therefore
fail-safe for routing, but the metric is wrong there and must not be quoted as accurate. §5.6 Q3
names the measurement that would fix it.

---

#### The renderer — literal before / after

**L3: one renderer.** All of the above lands in `pace_line` (`bin/claude-accounts:2006`), rendered
by `readout_lines` at `:3375` (chat) and `:3696` (board). No second surface.

**BEFORE** — the live footer, reproduced verbatim from `claude-accounts --readout` at 09:47Z:

```
weekly burn (1.00× = lands exactly at the 100% wall): next3 burn 0.93× → ~93% by reset, needs 88%/d over 2.2h (recent 28%/d) · next2 burn 0.40× → ~40% by reset, needs 20%/d over 4d (recent 8%/d) · next burn 1.62× → ~162% by reset ⚠ WALL, needs 10%/d over 4d (recent 48%/d) · next4 burn 0.48× → ~48% by reset, needs 17%/d over 4d (recent 4%/d)
```

Three defects, each measured above: it is **sorted by soonest reset**, so the 5.5 pp account leads
and the 119.5 pp pair trails; `needs 88%/d over 2.2h` quotes a rate in a unit 11× longer than its
own window; and nothing on the line says whether the demand is **physically reachable**.

**AFTER** — sorted by pp at risk, descending. One row per account, four facts each:

```
weekly drain — pp that DIE at reset (K=0.192 live · nowcast at the last 48h of pace):
  next4   strand ~64pp of 86 · p87 of its own 24h burns · start by T−28h (91h slack)
  next2   strand ~56pp of 83 · p65 of its own 24h burns · start by T−28h (70h slack)
  next3   strand ~5pp of 8   · p96 of its own 3h bursts · ⚠ LATE by 0.7h — 2.8pp already unrecoverable
  next    no strand — 1.62× burn, wall trajectory · 114h left
```

Each row answers, left to right: **how much dies** (M3a) · **is the demand routine or a stunt**
(M5) · **by when must it start** (M4′). Abstentions render as the word, never as a zero — a null
M2 prints `strand unknown (span 4.1h < 6.8h)`, a null K prints
`K unfitted (trailing 0.201 outside [0.175,0.210]) — no strand figures this sweep`.

The `⚠ WALL` flag and the `burn N.NN×` ratio survive **unchanged** for accounts with no strand —
that is `wall_projection`'s existing render, it is pinned by
`tests/claude-accounts-burn-ratio.bats`, and nothing here touches it.

**When S6 ships,** a fired alarm prepends one line above the block:

```
⚠ next3 — 5pp will die in 2.2h and the burst window to save it closed 0.6h ago.
```

---

### §5.3 RED-proof cases

**House rules, from the repo's recorded traps — every case below obeys all four.**

1. **A negated assertion under `errexit` is dead unless final.** No case uses a mid-test
   `! cmd`. Every case asserts on an explicit captured `status` / `output`.
2. **A fixture that references a symbol the fix ADDS will SKIP pre-fix, and bats renders a skip as
   `ok`.** In these Python-module cases, calling `ca.new_function(...)` pre-fix raises
   `AttributeError`, the interpreter exits non-zero, and `[ "$status" -eq 0 ]` fails — a genuine
   RED. **Never guard with `hasattr`**, and never `skip` on a missing symbol; that is precisely how
   a vacuous green is minted.
3. **Every red-proof is paired with a CONTROL that pins the opposite branch**, so an
   always-failing subject cannot be mistaken for a passing test.
4. **Fixtures are hermetic**: `HOME` and `CLAUDE_CONFIG_DIR` into `BATS_TEST_TMPDIR`, series passed
   explicitly via `path=` / `samples=`, following `tests/claude-accounts-core.bats:34-45`.

The module-load preamble is the existing one (`tests/claude-accounts-core.bats:70-74`); the
env-in-not-argv pattern is `tests/claude-accounts-burn-ratio.bats:26-38` (the subject parses
`sys.argv` at import, so any argv we pass is read by IT).

---

#### File: `tests/claude-accounts-roll-key.bats` — NEW (S1a)

**RP-1 · a sub-second stamp jitter across a minute boundary is NOT a roll**

*Fixture* — two samples 6 min apart, `session_pct` 40 → 44, reset stamps straddling the boundary
exactly as the live series does:

```
a: ts=T-6m  session_pct=40  session_reset_at=2026-08-25T11:59:59.900Z
b: ts=T     session_pct=44  session_reset_at=2026-08-25T12:00:00.100Z
```

*Assert* `ca._rolled(a, b, "session_reset_at", "session_pct") is False`.

*Fails before:* `_rolled` does not exist → `AttributeError` → status 1. With the truncation
spelling in place it returns `True`. Either way RED.
*Passes after:* rounding maps both stamps to the same minute key and `44 > 40`, so no roll.

**RP-2 · CONTROL: a real roll IS detected** — same pair, but `b.session_reset_at` = `T+5h` and
`b.session_pct = 3`. Assert `is True`. *This is the case that can fail if someone "fixes" RP-1 by
stubbing `_rolled` to always return `False`.*

**RP-3 · CONTROL: a same-key reset is caught by the second witness** — `b.session_reset_at`
identical to `a`'s, `session_pct` 40 → 3. Assert `is True`. Pins that the `OR` has two live arms;
a key-only implementation passes RP-1 and RP-2 and fails this.

**RP-4 · a null stamp is NOT a roll** — `b.session_reset_at = None`, `session_pct` 40 → 44.
Assert `is False` **and** `ca._reset_key(None) is None`. Pins S1a's "no window open ≠ missing data."

**RP-5 · corpus-level: the rounded key agrees with ground truth** — 200 synthetic pairs, 4 of them
real rolls (reset moves > 1 h), the other 196 jittering ±0.4 s across a minute boundary. Assert
exactly **4** rolls detected. *Pre-fix (truncation) this detects ~100 and the test is RED by a
factor of 25.* This is the case that would have caught the live defect.

---

#### File: `tests/claude-accounts-util-tail.bats` — NEW (S1b)

**RP-6 · `_util_tail` honours a TIME span, not a byte cap**

*Fixture* — a series of 4,000 records for one account, one every 6 min (spanning 400 h), each
padded with a filler field to ~292 B so the file exceeds 128 KiB by ~9×.

*Assert* `rows, span = ca._util_tail(path=p, hours=48.0)` yields `span >= 47.0` and
`min(r["_t"]) <= now - 47*3600`.

*Fails before:* the current signature has no `hours` parameter → `TypeError` → status 1. Called
with the current default the tail parses ~450 rows ≈ 45 h **only because this fixture's record is
small**; the case therefore also asserts the returned `span`, which today's function does not
return at all.
*Passes after:* time-filtered, span asserted.

**RP-7 · CONTROL: a genuinely short series reports its SHORT span and does not lie**
— 20 records spanning 2 h. Assert `span < 3.0` **and** `len(rows) == 20`. Pins that S1b returns the
*achieved* span, which is what every abstain rule downstream is written against. A implementation
that returns the *requested* 48.0 passes RP-6 and fails this.

**RP-8 · CONTROL: rotation — a `.gz` sibling is read when the live file is short**
— live file holds 3 h; `util.jsonl.1.gz` holds the prior 60 h. Assert `span >= 47.0`.
*Fails before:* readers open only the live path, so span ≈ 3 h.

---

#### File: `tests/claude-accounts-strand.bats` — NEW (S1c, S1d, S3)

**RP-9 · a completed weekly window requires its reset to be in the PAST**

*Fixture* — two windows for one account: (i) reset 24 h ago, last sample 0.1 h before it,
`weekly_pct = 90`; (ii) reset **2 h in the future**, last sample now, `weekly_pct = 92`.

*Assert* the completed-window helper returns **exactly one** window, with `strand == 10`.

*Fails before:* the naive `0 ≤ gap ≤ 3 h` rule returns **two** windows and a total strand of 18.
*Passes after:* `reset < now` excludes the live window.
**This is the exact defect I hit while writing this spec** (naive: 51 pp / 9 windows; correct:
43 pp / 8). It is not hypothetical.

**RP-10 · `exchange_rate` abstains when the trailing fit leaves the sane band**

*Fixture* — 400 adjacent pairs with Δsession summing to 2,000 pp and Δweekly to 460 pp
(K = 0.230, outside `K_SANE`'s ceiling of 0.210).

*Assert* `ca.exchange_rate(samples)` returns `(None, ..., None)`.
*Fails before:* `exchange_rate` does not exist → status 1.
*Passes after:* the sanity guard fires.

**RP-11 · CONTROL: a healthy fit is USED, not abstained** — same shape, Δweekly = 385 pp
(K = 0.1925). Assert `abs(K - 0.1925) < 0.002` and source `== "live"`. *An implementation that
abstains unconditionally passes RP-10 and fails this — this is the arm that makes RP-10 a control
rather than a stub.*

**RP-12 · CONTROL: a thin fit FALLS BACK to the frozen constant** — Δsession = 100 pp, below
`K_MIN_SDS = 300`. Assert `K == 0.192` and source `== "frozen"`. Pins that the three-way abstain
has three live arms, not two.

**RP-13 · `burn_wk_ewma_ph` crosses a weekly roll instead of discarding it**

*Fixture* — 20 samples over 10 h at 6-min spacing; the weekly window rolls at the midpoint
(`weekly_pct` 96 → 2, `weekly_reset_at` +168 h). Post-roll accrual is 2 → 8 pp over 5 h.

*Assert* the EWMA is non-null and `> 0.8 %/h`.
*Fails before:* the incumbent `burn_wk_ppd` computes `d = b - a < 0` and leaves the field **absent**
— assert `"burn_wk_ppd" not in row` pre-fix, which is the same blindness stated positively.
*Passes after:* the roll branch substitutes the post-roll level as the increment.

**RP-14 · CONTROL: M3a abstains below the 6.8 h measured-span floor** — 6 samples spanning 0.6 h.
Assert `wk_strand_pp(row) is None`. Paired with **RP-15 · CONTROL: it projects above the floor** —
90 samples spanning 9 h. Assert not None. *Without RP-15, RP-14 is satisfied by a function that
returns `None` always.*

**RP-16 · M3a never renders an overshoot as a number** — `weekly_pct = 52`, `reset_h = 114`,
EWMA = 1.725 %/h → raw projection 248.7%. Assert `wk_strand_pp == 0.0` **and** that the rendered
`pace_line` output contains `"wall trajectory"` and does **not** contain `"248"` or `"%"` adjacent
to a 3-digit projection. Pins the clamp as behaviour, not as a comment.

---

#### File: `tests/claude-accounts-burst.bats` — NEW (S2, S4)

**RP-17 · `burst_percentile` reports a p95 demand as a p95, not as a rate**

*Fixture* — one account, 2,600 rolling 3 h windows synthesised so that a demand of 3.14 weekly pp/h
sits at the 95th percentile of its own history; `weekly_pct = 92`, `weekly_reset_h = 2.55`.

*Assert* `94 <= burst_percentile(row, samples) <= 97` and `H == 3`.
*Fails before:* the function does not exist → status 1.

**RP-18 · CONTROL: a routine demand reports low** — `weekly_pct = 17`, `reset_h = 97` (demand
0.854 pp/h) against the same account's 24 h distribution. Assert the percentile is `< 75` and
`H == 24`. *Pins that the metric discriminates; a constant-p95 stub passes RP-17 and fails here.*

**RP-19 · CONTROL: "never once achieved" rather than an extrapolated p100** — demand set to 3× the
account's observed maximum. Assert the returned marker is the sentinel, not `100.0`.

**RP-20 · CONTROL: abstains below 200 qualifying windows** — 150 windows. Assert `None`.

**RP-21 · `burst_start_by` returns LATE for next3's live shape**

*Fixture* — the measured live row: `weekly_pct=92, weekly_reset_h=2.21, session_pct=13,
session_reset_h=3.37`, `K=0.192`.

*Assert* `-1.0 < burst_start_by(row, K) < 0.0` (measured **−0.65**) and the verdict string is
`"LATE"`.

*Fails before:* the function does not exist → status 1. **And this is the case that separates M4′
from the deleted M4:** a same-shaped assertion against the synthesis's `wk_reach_pp` formula yields
`16.9 pp vs 8 needed → REACHABLE`, i.e. the opposite verdict, on the account that in fact stranded.
Add that as an explicit comment in the test so the deletion is recorded where an implementer reads
it.

**RP-22 · CONTROL: an account with days of runway returns SLACK** — next2's live shape
(`weekly_pct=17, weekly_reset_h=97.2, session_pct=8, session_reset_h=0.54`). Assert
`burst_start_by > 60.0` and verdict `"SLACK"` (measured **+69.59**). *Without this, RP-21 is satisfied
by a function that returns LATE always — which is exactly the degeneracy that killed M4.*

**RP-23 · CONTROL: the freeze term is LIVE, not decorative** — run RP-21's fixture twice, once with
`P_WALL = 0.625` and once with `P_WALL = 0.0` (injected via the module constant). Assert the two
`burst_start_by` values differ by **1.033 h** (± 0.01) — the executed value, not a guess. *Pins that the wall-freeze term actually
participates. This is the mutant that a purely arithmetic implementation would survive.*

**RP-24 · CONTROL: no window open ⇒ abstain, not zero** — `session_reset_at = None`,
`session_pct = None`. Assert `burst_start_by(...) is None`.

---

#### File: `tests/claude-accounts-core.bats` — EXTEND (do not rewrite)

Two existing cases change and must be updated **in place** with the reason recorded beside them,
per the file's own convention at `:1783-1797`:

**RP-25 · the footer sorts by pp at risk, not by soonest reset** — extend
`"router M7: pace line — …"` (`tests/claude-accounts-core.bats:1780`). Fixture: `next3`
(strand 5, reset 2.2 h) and `next4` (strand 64, reset 119 h). Assert the rendered line names
`next4` **before** `next3`.
*Fails before:* `pace_line` sorts on `weekly_reset_h` at `:2015`, so `next3` leads.
*Passes after:* sorted by `wk_strand_pp` descending.

**RP-26 · CONTROL: an account with no strand still renders, and renders LAST** — add `next`
(wall trajectory, strand 0) to RP-25's fixture. Assert it appears, and appears last. *Pins that the
re-sort does not silently drop the zero-strand rows — a `sorted(..., key=strand)` over a list
filtered on `strand > 0` passes RP-25 and fails this.*

**RP-27 · `apply_burn` attaches the new keys under their own names** — extend
`"router M7: apply_burn derives rates …"` (`:1749`). Assert `burn_5h_ewma_ph` and
`burn_wk_ewma_ph` are present **and in %/h** (`burn_5h_ewma_ph ≈ 60.0` for a 10→40 move over
30 min, **not** 0.6). *Fails before:* keys absent. **This is the unit hazard as a test** — an
implementation that reuses the `burn_5h_ph` key in fraction/h passes every other case in this
suite and fails here.

**RP-28 · CONTROL: `_su_projected` consumes the new key at the right SCALE** — row with
`burn_5h_ewma_ph = 60.0` (%/h), `session_pct = 20`, `session_reset_h = 2.0`,
`PROJ_LOOKAHEAD_H = 1.0`. Assert `_su_projected(row, R) ≈ 0.80`, **not** `1.0`. *A missing ÷100
saturates to 1.0 and is caught only here.*

**Unchanged, deliberately:** `tests/claude-accounts-burn-ratio.bats` (all 8 cases). `wall_projection`
and its 5% abstain floor are untouched by this spec; the 5h `burn_ratio` render survives as the one
raw-percentage figure L1 permits.

---

### §5.4 Acceptance

**The operator's ONE command:**

```
▶ Run this:

`claude-accounts --readout`
```

**What proves it works — the footer answers, for every account, all three questions the goal
names.** Expected shape (values are the live measurement at `2026-08-25T09:47:41Z`; a later run
will differ in numbers, not in structure):

```
weekly drain — pp that DIE at reset (K=0.192 live · nowcast at the last 48h of pace):
  next4   strand ~64pp of 86 · p87 of its own 24h burns · start by T−28h (91h slack)
  next2   strand ~56pp of 83 · p65 of its own 24h burns · start by T−28h (70h slack)
  next3   strand ~5pp of 8   · p96 of its own 3h bursts · ⚠ LATE by 0.7h — 2.8pp already unrecoverable
  next    no strand — 1.62× burn, wall trajectory · 114h left
```

| the goal's question | where it is answered | for next3, live |
|---|---|---|
| **how much will strand?** | M3a `strand ~Npp of M` | ~5 pp of the 8 remaining |
| **does the 5h cap bind?** | M4′ `start by T−Nh` / `LATE` | **yes** — LATE by 0.65 h, 2.83 pp unrecoverable |
| **what single action changes it?** | M5 percentile + M4′ verdict | nothing on next3; **route the work to next4** (64 pp, 92 h slack, p87 = routine) |

**The implementer's acceptance, three commands, all of which must be green before the land:**

1. `bash tests/run.sh claude-accounts-roll-key claude-accounts-util-tail claude-accounts-strand claude-accounts-burst claude-accounts-core`
   → every RP case above passes, **and each was demonstrated RED at the commit before its fix.**
   A case that was never seen red does not count as coverage.
2. `claude-accounts --strand-score` → prints the horizon-stratified table (S5). **Acceptance is not
   "it is accurate" — it is that the table has non-zero `n` in at least the 24 h, 12 h and 6 h
   buckets and reports a bias that could have been non-zero.** A harness whose every cell reads 0.0
   is the tautology all over again.
3. `claude-accounts --readout | grep -c 'strand'` → 3 or 4, i.e. the footer renders per account and
   did not silently abstain fleet-wide.

**The falsification the operator can run at the next weekly reset**, and it is the real acceptance:
after next2's or next4's window closes, `claude-accounts --strand-score` must show the realised
strand for that window inside the error band the 24 h bucket published **before** it closed. If it
does not, S6 does not ship and §5.6 Q1 becomes the priority.

---

### §5.5 What is NOT built, and why — carried forward so no future session re-proposes it

#### Killed by this spec's verification

| proposal | status | why it must not come back |
|---|---|---|
| **M4 `wk_reach_pp` as a veto** | **DELETED** | Reads `REACHABLE` on 99.37% of the series and on **100% of the 74 samples inside the 5 wall episodes it was written to catch**. `reach_pp` and `need` are both monotone in `(weekly_pct, hours-remaining)` — an algebraic restatement of what it supplements. Replaced by M4′, which is a trigger keyed on rate-and-freeze. |
| **"~20 h median lead, 4.5–93 h range"** | **WITHDRAWN** | The score was the identity function on true strand (8/8 agreement). Causally scored, the same rule fires on 3 of 4 windows closing at 98–100%. No causal configuration of any parameter setting exceeds **11.96 h** of lead. |
| **"the 5h sub-cap is a same-day guard, not a planning constraint"** | **WITHDRAWN** | True of the 168 h span it was computed on, false of the span the planner acts on. Conditional on a window being driven hard it walls **5 in 8 (62.5%)** against **0 of 244** elsewhere. |
| **"M1 changes the router's exclusions"** | **DELETED from the spec** | `_excluded` reads the raw meter at `:2045`; `_soft` is floored at 0.0025 > 0. Proven by positive control: `burn_5h_ph = 5.0` changed 10,489 scores and 11,200 desk tiers and **0** exclusions. |
| **K as a frozen "plan constant"** | **WEAKENED** | The pooled ratio-of-sums averages mix away (±30% per-window jitter moves the pooled mean by 0.0003). Only the stratified tests can see workload dependence, at 4–11% minimum detectable shift. And the trailing fit already reads 0.2012, above the shipped band. |
| **Binning K by burn intensity** | **BANNED — it is an instrument artifact** | Burn intensity is K's own denominator. A simulation with K exactly 0.192 reproduces the entire apparent trend. Anyone re-testing K will rediscover this; it is not a finding. |
| **"the spec's minute-rounded roll key is broken"** | **REFUTED (by me, this spec)** | Rounding flips 1.0% of pairs and agrees with ground truth 99/99; the 46% figure is the **truncation** spelling. Do not "fix" a working roll key. |

#### Rejected by the synthesis, still rejected

| proposal | why not |
|---|---|
| `k_required` / "fire k ≥ 15 on next3" | Pane units, not session units. The `k` 11.5–19.5 band rests on **14.4 h** of observation and the band above it is **slower** (0.782 vs 3.397 wk-pp/h). |
| `burn_pp_per_session_hour`, `sessions_needed`, `k_intensity_ratio` | Requiring `k_src == "work"` across a 3 h block leaves **9 blocks / 25 h / 1 weekly pp** in the entire series. Revisit after task #171. |
| Per-account or per-regime K | Pooled K beat the per-account model out of sample (MAE 0.435 vs 0.480 pp). |
| Shape-corrected weekly projector `weekly_pct / S(phase)` | Self-refuted by its own author: leave-one-out MAE 54.1 vs 39.5 pp for plain linear. |
| Theil-Sen slope estimators | Lose at every horizon on both meters — median-of-slopes suppresses the burst, and the burst is the signal. |
| `instrument_confidence` three-state label | Redundant once every metric carries its own abstain rule; a parallel label invites reading a number *and* a caveat, which is how the caveat gets dropped. |
| `pace_target_5h_pct` (the "pace car") | Genuinely good render, but it is M3a ÷ windows-remaining and changes no routing decision. Recommend only as an alternative *rendering* of M3a if "56 pp" proves less actionable than "fill each window to 21%". |
| Widening `burn_5h_ph`'s pair to ≥ 1 h | Cures quantization by reintroducing staleness. |
| "Restore the 48 h tail" alone | Correct to fix the byte cap, but the estimator must become roll-aware in the same change or it gets worse: at a true 48 h span the widest-pair form abstains 100% of the first 36 h of every weekly window. |
| Any absolute-token calibration as a prerequisite | Not needed. K makes the two meters commensurable in percentage space, which is all the planner uses. |

#### Previously refuted in this plan doc — do not re-propose (§2.8, §3.4)

- **The Fable 50% arbitrage.** Refuted twice; Fable draws **1.79× Opus per list dollar**
  (90% CI [1.67, 1.90], P(ratio < 0.75) = 0.000). There is no discounted lane.
- **Effort downgrades as a cost lever.** Open, not settled — and not a lever until it is.
- **Recycling / context-shrinking as a cost lever.** `cache_read` weighs ≤ 0.018–0.049 weekly-pp
  per Mtok; shrinking context converts a free `cache_read` into a paid `cache_creation`.
- **Cutting telemetry to save tokens.** It is 0.6–1.2% of throughput.
- **Any Q3 metric shape** — quality-per-token, cost-per-finding, tokens-per-commit. Every metric
  in §5.2 is structurally incapable of expressing one: there is no token, dollar, or output
  denominator anywhere in the series, so each can only ever argue for spending **more** quota (Q2)
  or spending it on a **different account** (Q1). Noted, per §3.3, that this is forced rather than
  virtuous.

---

### §5.6 Open questions the data genuinely cannot answer

**Q1 — Does the strand nowcast have any real skill at 24–96 h, or only at the horizon's close?**
Unknown. Every published accuracy figure was scored where the projection has already converged to
truth. **Measurement that answers it:** S5's `--strand-score`, read at the 96 / 48 / 24 h buckets
across ≥ 20 completed account-weeks (~5 more weeks of data). Until it reads non-degenerate at 24 h,
M3a is a nowcast and S6 does not ship.

**Q2 — Is K drifting, or is 0.2012 noise?** The permutation test gives p = 0.0948 — suggestive,
not significant. **Measurement:** re-run `exchange_rate` weekly and keep a dated series of the
trailing-7d fit. Three consecutive weekly fits above 0.198 is a drift; a single one is not. S1c's
abstain guard makes the wrong answer safe in the meantime.

**Q3 — Why does the 5h EWMA invert above `session_pct` 40, and can a single estimator serve both
regimes?** n = 133 in the high stratum, which is too thin to fit a switch without over-fitting.
**Measurement:** score both estimators against realised next-hour burn on ≥ 500 samples at
`session_pct ≥ 40`. That stratum grows only when the fleet bursts — so it is a by-product of the
planner working, and cannot be forced. Do **not** ship a fitted regime switch on n = 133.

**Q4 — What actually dispatches the work?** Structurally unanswerable from this series. `k` explains
**52%** of 24 h burn variance and the other 48% is per-session intensity, which the log cannot see
(`next` ran 1.35 weekly pp per pane-hour while next3 ran 0.256 at 2.8× the panes). **The planner
names the account and the deficit and cannot promise that dispatching N sessions closes it.**
**Measurement:** task #171 (`k_agents` — `k_work` is non-null on 70.1% of fielded rows and misses
46.7% of live writers where present, anti-correlated with load), then OTel per-session token
counters (§4 M6). Both are prerequisites, neither is on this critical path.

**Q5 — Is `P_WALL = 0.625` the real burst wall rate?** n = 8, and it is a **lower** bound (walls
under ~13 min are invisible at the 6.4 min median sampling cadence). **Measurement:** raise the
sweep cadence inside a driven window, or instrument the wall directly from the API's own 429/limit
response rather than inferring it from `session_pct == 100`. Until then M4′'s freeze term is the
weakest number in the spec, and RP-23 exists so that at least its *participation* is pinned.

**Q6 — Does the planner's own success invert its assumptions?** The end-of-window acceleration
(2.3× in the last 30% of the window) is a record of the behaviour this planner exists to
**replace**. If it works, the shape flattens and any estimator fitted to it drifts toward
complacency. M1–M5 are deliberately fitted to **rates**, never to window shape, for this reason —
but the acceptance test must be **re-run after several weekly windows**, not assumed. The forward
arithmetic already predicts one inversion: closing the 19.9 pp/week strand needs 1.04 extra full 5h
windows/week, carrying the fleet wall rate 1.72% → 2.20%.

---

### §5.7 Implementation record — what actually landed, and where it deviated from the spec

Wave 1 = **S1 + S2 + S3 only**. Wave 2 = **S4 + S5**. S6 and S7 are unbuilt. S5 is now BUILT but
not yet READ against the live series, and S6's gate is the reading, not the build — see below.

#### S1 · data fixes — LANDED

`bin/claude-accounts`: `_reset_key` / `_rolled` (:1877), `_util_tail(path, hours=48.0,
max_bytes=None) → (rows, achieved_span_h)`, `exchange_rate` + `K_FROZEN` / `K_MIN_SDS` /
`K_SANE`, `completed_weekly_windows` + `WEEKLY_TAIL_GAP_H`.
Suites: `tests/claude-accounts-roll-key.bats` (RP-1..RP-5),
`tests/claude-accounts-util-tail.bats` (RP-6..RP-8 + RP-8b/RP-8c),
`tests/claude-accounts-strand.bats` (RP-9..RP-12 + RP-9b/RP-12b). **16/16 proven RED against the
pre-change binary** (`git stash push -- bin/claude-accounts`, run, pop), 16/16 green after.

**Live confirmation, out of the spec's own numbers.** `_util_tail()` now returns span **47.86 h**
against the byte cap's 12.16 h (1,613 rows, 65 ms). `completed_weekly_windows` over a 400 h tail
reproduces §5.1 S1d **exactly** — 8 windows, 43 pp, and the same eight per-account rows. Live
`exchange_rate` reads **K = 0.1969, source `live`, Σ Δsession = 1,889** — in band, and above the
0.192 literal, which is the drift Amendment 2 predicted and the reason K is fitted rather than
frozen.

**Deviation 1 — how the S1b trap was discharged, and it is not what §5.2 S1b implies.** S1b's
sizing formula (`max_bytes` derived from a median interval and a mean record size) was **not
implemented**: it re-creates the exact coupling it cures, because both constants drift with the
record. Shipped instead: the byte seek **doubles** (`UTIL_TAIL_SEED_B` 128 KiB →
`UTIL_TAIL_MAX_B` 32 MiB) until the requested span is actually reached or the file is exhausted,
then the parsed rows are time-filtered and the **achieved** span returned. A record that gains a
field now costs one extra read, not a silently shorter window.

**Deviation 2 — the roll-aware estimator that rides in the SAME commit is the INCUMBENT's, not
M2's.** §5.5 is literal that restoring the span alone is a regression: at a true 48 h span the
widest-pair `burn_wk_ppd` anchors on a pre-reset sample, reads `d < 0`, and abstains for the
whole first stretch of every weekly window. Merging S3 into S1 to satisfy that would have
short-circuited the ranking. Shipped instead: `apply_burn`'s weekly anchor **walks forward to the
newest roll** (`_rolled`, S1a) so the same estimator measures the post-roll segment. It abstains
below its own pre-existing 6 h floor and nowhere else. `tests/claude-accounts-util-tail.bats`
**RP-8b** is that proof — 48 h of samples with a weekly roll 30 h back, `burn_wk_ppd` absent
pre-change and 14.4 %/d after — and **RP-8c** is its control, pinning that with no roll in the
span the anchor still reaches the oldest sample. Without that pair the suite would have been
green and vacuous, which is the failure §5.5 names.

**Deviation 3 — `tests/claude-accounts-core.bats:1768` updated in place**, not rewritten:
`_util_tail` is now a 2-tuple, and the case additionally asserts the achieved span, because that
span is what every abstain rule below it is written against.

#### S2 · M5 `burst_percentile` — LANDED

`bin/claude-accounts`: `burst_percentile(r, samples)` + `fmt_burst(bp)` beside `pace_need_ppd`,
constants `BURST_LOOKBACK_H` / `BURST_H_GRID` / `BURST_MIN_WINDOWS` / `BURST_MIN_RESET_H` /
`BURST_SPAN_LO,HI`. Suite `tests/claude-accounts-burst.bats` (RP-17..RP-20 + RP-20b), **5/5 RED**
pre-change; the render case inside core's `pace line` test is a sixth RED.

**Live, all four accounts, none abstained:**

```
next3 burn 0.94× → ~94% by reset, p97 of its own 1h burns to close 7pp in 1.4h (recent 31%/d) ·
next2 burn 0.40× → ~40% by reset, p71 of its own 24h burns to close 83pp in 4d (recent 6%/d) ·
next  burn 1.63× → ~163% by reset ⚠ WALL, p37 of its own 24h burns to close 47pp in 4d (recent 24%/d) ·
next4 burn 0.47× → ~47% by reset, p94 of its own 24h burns to close 86pp in 4d (recent 6%/d)
```

**Return shape** is a dict — `{"pct": float|None, "h", "n", "need_pph", "never"}` — not the bare
float §5.3 RP-17 sketches, because `never` and `pct` are different states and a float cannot
carry both. `pct is None with never True` is the sentinel; there is no p100.

**Deviation — `apply_burn` now reads `BURST_LOOKBACK_H = 336 h`, not 48.** The ranking needs
`BURST_MIN_WINDOWS = 200` windows of the account's own history, which 48 h cannot supply at any
grid point above 6 h. Every consumer still filters to its own span, so no rate changed, and the
read is nearly free: measured on the live 3.6 MB series, 48 h parses in 66 ms and 336 h in 73 ms
(the doubling seek amortises; the parse dominates). Attach point is `apply_burn`, not `pace_line`
— it is the one place holding both the rows and the series — so `pace_line` still renders what is
stamped and L3's single renderer is intact.

**The abstain that carries the most weight is RP-19**, and it is why the return is not a float:
above the account's observed maximum there is no evidence at all, and a rendered `p100` reads as
a rate that HAS been achieved.

**…and it shipped half-done, caught on the live surface, not by a test.** The refusal held at the
NUMBER and leaked at the STRING. A demand sitting exactly AT the observed maximum is not `never`
— it scores 99.96 — and `:.0f` rounds that to the literal `p100`. On 2026-08-25 next3 rendered
`p100 of its own 1h burns`, which a reader cannot distinguish from the extrapolation the abstain
exists to prevent. `fmt_burst` now caps the rendered percentile at 99, with a case pinning both
arms (99.96 → `p99`; 95.6 → `p96`, so the cap is not a blanket). **Class:** an abstain rule is
only as strong as its rendering — checking the guard in the producer and the format string in the
renderer are two different checks, and RP-19 was only ever the first.

#### S3 · M2 + M3a — the nowcast — LANDED

`bin/claude-accounts`: `burn_wk_ewma_ph(samples_for_acct, now, weekly_reset_h) → (value|None,
measured_span_h)` and `wk_strand_pp(r)` beside `wall_projection`; both attached in `apply_burn`;
`pace_line` restructured into the `PACE_HEAD` block, **sorted by pp at risk, descending**.
Cases RP-13..RP-16 + RP-16b in `tests/claude-accounts-strand.bats` and RP-25..RP-27 in
`tests/claude-accounts-core.bats` — **7/7 RED** against the S2 binary, 111/111 green after.

**Live, and the inversion is the whole gain:**

```
weekly drain — pp that DIE at reset (nowcast at the last 48h of pace):
  next4 strand ~66pp of 86 · p94 of its own 24h burns · 4d left
  next2 strand ~58pp of 83 · p71 of its own 24h burns · 4d left
  next3 strand ~6pp of 7 · p98 of its own 1h burns · 1.3h left
  next no strand — 1.63× burn, wall trajectory · 4d left
```

124 pp sits on next4 and next2 with four days of runway, against 6 pp on the account the router
is alarmed about. The old line sorted by soonest reset and led with the 6 pp.

**Deviation 1 — the header carries NO `K=… live` clause, and the strand does NOT gate on K.**
§5.4's mock header reads `(K=0.192 live · nowcast …)` and its abstain text says a null K prints
`no strand figures this sweep`. But M3a is pure weekly-space arithmetic and consumes no K at
all; the first K consumer is **S4** `burst_start_by`. Gating the strand on a coefficient it does
not use would be a fabricated dependency, and rendering a number nothing consumes is the metric
shape §3.2 forbids. `exchange_rate` is built, tested and live (K = 0.1969, source `live`); the
header clause enters with S4.

**Deviation 2 — `burst_start_by` / the `start by T−Nh` clause is absent**, by scope. S4 is a
later wave. Every row therefore answers two of the goal's three questions — how much dies, and
whether the demand is routine — and not the third.

**Deviation 3 — `pace_line` COMPUTES the strand rather than reading its own stamp**, exactly as
it already calls `wall_projection` instead of reading `burn_ratio`. A renderer that reads a
stamp renders nothing at all when `apply_burn` has not run, which is a silent failure. The
`wk_strand_pp` / `burn_wk_ewma_ph` / `burn_wk_span_h` stamps exist for other consumers.

**Deviation 4 — `(recent N%/d)` is no longer rendered**; `burn_wk_ppd` stays populated (and
keeps S1's roll-aware anchor) so nothing reading it breaks. The EWMA supersedes it on the
surface: the two agree closely and the EWMA is the one that survives a reset.

**Deviation 5 — RP-27 is its own case**, not an extension of `router M7: apply_burn derives
rates`. That fixture holds three samples for next3, which cannot clear either the 2-pair or the
6.8 h measured-span floor, so extending it in place would have meant loosening the floor to make
a test pass. New fixture instead: 24 h at 6 min spacing.

**Deviation 6 — a SPEC CONFLICT, resolved, and it was found by a red rather than by reading.**
§5.3 declares `tests/claude-accounts-burn-ratio.bats` *"Unchanged, deliberately: all 8 cases"*,
and §5.2 says the `⚠ WALL` flag *"survives unchanged"*. But that suite's case *"the footer no
longer frames 100% as the target"* greps the source for the literal caption `lands exactly at the
100% wall` — the very caption §5.2's own AFTER block replaces — and §5.4's mock row reads
`wall trajectory` with no glyph. The two instructions cannot both be obeyed literally.

Resolved without weakening either: the glyph is **restored** (`⚠ WALL trajectory` — dropping a
warning glyph off a warning is a strict loss, and §5.2 is explicit that the flag survives), and
the burn-ratio case is **updated in place with its invariant intact and strengthened**. It now
pins what the case is FOR rather than one spelling of it: the header must name the loss
(`pp that DIE at reset`), the wall flag must be present, and BOTH the old target-framing and the
old caption must be absent. Greping a spelling rather than the invariant is how a live assertion
becomes a tripwire on its own subject's next fix — the caption changed, the defect did not come
back, and only the string moved. §5.4's mock differs by one glyph, which is not structure.

⚠️ **How it was found matters more than the fix.** `scripts/ship-land.sh` exhausted its 120 s
smoke budget after 7 suites and attested `smoke:"partial"`, so this red did not block the land;
it surfaced on a full local re-run afterwards. `burn_wk_ppd` was audited the same way and is
**fine** — `bin/cc-wave-plan:492-505` consumes it and S1/S3 deliberately keep it populated
(`tests/cc-wave-plan.bats` 21/21). The lesson is that a footer string is a consumed surface:
grep the whole tree for every literal a render change deletes, not only the suite you are editing.

**What is NOT claimed.** No lead time, anywhere — not in the caption, the docstrings, or the
commit messages. §5.1 LB-2's four kills stand and the estimator is sold as what it is: a good
nowcaster precisely because it converges as the horizon closes, which is what makes it a bad
forecaster. **S5 (`--strand-score`) is still the prerequisite for S6**, and nothing here
shortens that.

#### S4 · M4′ `burst_start_by` — LANDED

`bin/claude-accounts`: `burst_start_by(r, k)` + `fmt_start_by(sb)` beside `wall_projection`,
constants `BURST_SPPH` / `P_WALL` / `MEAN_WALL_H` / `BURST_WINDOW_H` / `BURST_SOON_H` /
`BURST_MAX_WINDOWS` / `BURST_REM_EPS`; `pace_head(k, k_src)` split out of the `PACE_HEAD`
constant; `apply_burn` stamps `k_exch` / `k_exch_src`; `pace_line(rows, k=None, k_src=None)`
renders both. Suite `tests/claude-accounts-burst.bats` extended with RP-21..RP-24 + RP-24b —
**5/5 proven RED** against the S3 binary, 10/10 green after.

**The arithmetic reproduces §5.2's live table exactly** on the two rows that carry a full fixture:
next3 `−0.645 h` LATE with a `2.83 pp` unrecoverable floor (spec: −0.65 / 2.83), next2 `+69.589 h`
SLACK over 6 windows and `6.199 h` of freeze (spec: +69.59 / 6 / 6.20).

**Deviation 1 — the return is a dict, not the bare float §5.3 RP-21 sketches**, for S2's reason
restated: the hours of slack, the verdict, and the unrecoverable floor are three different facts
and a float carries one. RP-21 asserts on `sb["h"]` and `sb["verdict"]`; the inequality it
specifies is pinned unchanged.

**Deviation 2 — K reaches the renderer as a ROW STAMP, which is the OPPOSITE of S3's Deviation 3,
and the difference is real rather than a lapse.** S3 argued `pace_line` must COMPUTE the strand
instead of reading `wk_strand_pp`, because a renderer that reads a stamp renders nothing when
`apply_burn` has not run — a silent failure. That argument turns on the renderer *being able* to
redo the derivation from the row it already holds. K is not that kind of quantity: it is a fleet
fit over the utilization series, which `pace_line` does not hold and cannot re-derive. So
`apply_burn` stamps it (the one place holding both the rows and the series, exactly as for M5's
`burst`) and `pace_line` reads it, with an explicit `k=` parameter for any caller that has its
own. The failure mode S3 named is still real here and is answered by the abstain instead: with no
K the header keeps its S3 spelling and every start-time clause is absent — which is the same
thing the reader sees when `exchange_rate` itself abstains, and is therefore not a second story.

**Deviation 3 — the start-time clause renders on STRANDING rows only** (`wk_strand_pp ≥ 0.5`, the
same gate M5's percentile already rides). §5.4's own mock does this without saying so: `next`
carries a 48 pp deficit and would score `SLACK` with 99 h of slack, and the mock row shows no
start-by clause on it. An account with no strand is on pace to fill its window or through it;
there is no endgame burst to schedule, and a start time for a plan nobody is making is the metric
shape §3.2 forbids.

**Deviation 4 — `BURST_REM_EPS`, a residue guard the spec's pseudocode does not have, and it is
worth 1.03 h on this plan's own keystone row.** `while rem > 0` over floats: in the exact-fit case
— which is RP-21, next3, the row the whole metric was written for — `burn_h` is computed as
`rem / BURST_SPPH` and `rem -= burn_h * BURST_SPPH` lands on a residue near 1e-14 rather than on
zero. That opens a second window, charges a second `P_WALL × MEAN_WALL_H`, and moves the answer
from −0.645 h to −1.68 h. The verdict survives; the number the operator is asked to act on does
not. **Class:** a spec written in exact arithmetic has to be read twice when it ships in floats,
and the place it bites is the boundary case the spec chose as its example.

**Deviation 5 — a null K does NOT print `no strand figures this sweep`** (§5.4's abstain text).
That line was written when the strand was believed to consume K; S3 Deviation 1 established it
does not. The strand renders exactly as it did in S3, and only the K clause and the start-time
clauses go silent — RP-24b's control arm pins both halves, including that no fallback to
`K_FROZEN` happens at the renderer. Substituting the frozen literal for a fit that abstained is
how a refusal becomes a rendered number.

**What is NOT claimed.** M4′ ships **on probation**, as §5.2 requires: `BURST_SPPH = 22.87`,
`P_WALL = 0.625` and `MEAN_WALL_H = 1.653` all rest on n = 8 burst windows, `P_WALL` is a lower
bound (a wall under ~13 min is invisible to the detector), and it is sized on the burst
denominator (5/8) and must never be quoted against the all-windows one (5/252). The docstring
carries all three. **S5 (`--strand-score`) is still the prerequisite for S6**, and nothing here
shortens that either.

#### S5 · M3c `--strand-score` — BUILT, and NOT YET READ

`bin/claude-accounts`: `strand_score(samples, buckets=STRAND_SCORE_BUCKETS, now=None)` +
`render_strand_score(sc)` beside `apply_burn`, constants `STRAND_SCORE_BUCKETS` /
`STRAND_SCORE_FLOOR` / `STRAND_SCORE_SPAN_H`, and a `--strand-score [--hours N]` branch in
`main()` placed **before `load_cfg()`**, beside `--agents`, so it answers with no config, no
keychain and no sweep. Suite `tests/claude-accounts-strand-score.bats` (RP-29..RP-33) — **5/5
proven RED** against the S4 binary, 5/5 green after; 159/164 across every `claude-accounts*`
suite, the 5 reds being the container's, unchanged (below).

🚨 **BUILDING THIS IS NOT THE GATE ON S6. READING IT IS, and the reading needs the desk's
series.** §5.2 S6 is literal: *"Do not build this until S5 has run and been read. If the
horizon-stratified bias at the 12 h bucket is not near zero, this alarm is not shippable at any
parameter setting."* What is now true is that the instrument exists and has been shown capable of
producing a non-zero answer. What is still unknown is what it says about the **real** 8+ closed
account-weeks, because this wave ran in a container with no utilization series at all. That is one
command on the desk, and it is the whole of S6's precondition:

```
claude-accounts --strand-score
```

**The anti-tautology property is the deliverable, and it is pinned by RP-30/RP-31 as a PAIR.**
The refuted score was the identity function on true strand; a replacement that reports a large
error unconditionally would be exactly as uninformative in the other direction. So RP-30 drives a
window that burns steadily and then STOPS and requires the far buckets to miss by >10 pp while the
6 h bucket converges inside 3 pp *and* MAE to fall monotonically toward the reset; RP-31 drives a
window that holds its pace and requires every bucket inside 2 pp. Neither case passes an
instrument that has only one thing to say. On a 3-window fixture the rendered table reads
`96h −14.23 · 48h −14.22 · 24h −6.22 · 12h −0.41 · 6h −0.15`, which is the estimator's own claim —
a good nowcaster precisely because it is a bad forecaster — measured rather than asserted.

**Deviation 1 — CAUSALITY IS ENFORCED IN THE HARNESS, NOT IN THE ESTIMATOR, and this is the trap
the whole case exists to catch.** `burn_wk_ewma_ph` filters its own 48 h lookback but has never
dropped samples *after* `now`, because every prior caller passes wall-clock time, for which that
set is empty. Replaying history is the first caller for which it is not. Handing it the full
series lets the 24 h cell see the flat tail it is supposed to be predicting: on RP-30's fixture
the leak moves that cell from 28.0 pp to ~41.5 pp — **which reads as a GOOD forecast**, i.e. the
failure is silent and flatters the thing under test. `strand_score` slices `[x for x in ss if
x["_t"] <= e["_t"]]` at every cell, and RP-30 asserts the un-leaked value directly.

**Deviation 2 — a cell may walk BACK from its horizon to find an evaluable sample, and that is
sound rather than a loosened rule.** §5.2 says "the last evaluable sample with `weekly_reset_h ≥
H`". The two words carry different rules and both are kept: the search starts at the horizon and
walks backwards, so every scored cell is *at least* H hours from the reset — never nearer, which
is the direction that would flatter the score. `at_reset_h` is stamped on the cell so the distance
actually used is auditable, and RP-29 pins it into `[H, H+0.3)`.

**Deviation 3 — an unevaluable bucket renders `—`, and `bias`/`mae`/`agree_rate` are None, not
0.0.** RP-32 pins it. A zero is a value and reads as a measurement; a table of zeros over cells
that measured nothing is precisely the shape the refuted score produced, and it must not be
reachable by a second route. The same rule kills the whole table: with no closed window the
command says so in words and prints no columns at all.

**Deviation 4 — `sign-agree` is defined against `STRAND_SCORE_FLOOR = 0.5 pp`, reusing
`pace_line`'s own render gate** rather than testing `> 0`. "Has a strand" then means the same
thing in the score as it does on the surface the score is judging; a second threshold would make
the harness able to disagree with the renderer about what it was measuring.

**Not claimed.** No accuracy verdict, in either direction — the fixtures demonstrate the
instrument's *range*, not the estimator's quality, and the plan's §5.4 falsification (does the
24 h bucket's published band contain the realised strand of the next window to close?) is a
forward test that cannot be run retroactively. S6 stays unbuilt.

#### Acceptance status against §5.4

| command | status |
|---|---|
| the bats suites (roll-key · util-tail · strand · burst · core) | **111/111 green** after wave 1; **159/164 across all `claude-accounts*` suites** after wave 2 (S4 + S5), every new case shown RED at the commit before its fix |
| `claude-accounts --readout` renders the drain block for all four accounts | **yes** — see above (wave 1's live capture) |
| `claude-accounts --readout \| grep -c 'strand'` → 3 or 4 | **4** |
| `claude-accounts --strand-score` prints the horizon table with non-zero `n` at 24/12/6 h | **built, RUN ONLY ON FIXTURES** — 3-window fixture gives n=3 at every bucket and a bias spread of −14.23 → −0.15. The acceptance as §5.4 words it is about the LIVE series and needs one desk run |

⚠️ `bash tests/run.sh …`, named in §5.4, **does not exist in this repo**. The suites are run with
`bats tests/<name>.bats`; `scripts/ship-land.sh` selects and runs them at the land.

⚠️ **Wave 2's 5 reds are the ENVIRONMENT, not the diff, and the distinction was established by
measurement rather than by reading.** S4 was built in a remote container with no keychain, no
route to `api.anthropic.com`, and a smaller `ARG_MAX` than the desk. Five cases in
`claude-accounts-core.bats` / `claude-accounts.bats` fail there — `--relogin-info`, three
`--login-status` cases (one dying on `OSError: [Errno 7] Argument list too long`), and the
`--json` logged-out e2e (`probe-error`). All five were re-run with the diff **stashed** and failed
identically, so they attribute to the box. The live `--readout` acceptance above is
correspondingly **unrunnable there** and is not re-asserted for wave 2; it needs one run on a
machine with the accounts. RP-24b covers the render path that acceptance would exercise, over
fixtures rather than the live fleet.
