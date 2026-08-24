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
| ~~**M2**~~ | ✅ **DONE 2026-08-24 `45158b0f`** — **the DoD carrier stays under the cap.** Two halves: the *newest-wins reframe* (landed earlier) already moved the binding scope to the TOP, so a stub previewed the right contract rather than the oldest superseded one; this closes the other half by keeping the payload **under** `CC_DOD_CTX_MAX` (default 9200) so **no stub is produced at all**. History is elided **oldest-first**, one `## ` block at a time; `$_lead` is never droppable; the elision is **named with its count** and the store files named beside it. | **L** | met — measured end to end: a **45,021-byte** store emits **9,112 bytes** with the current contract on line 3. 7 bats cases, RED-proved 3/3, plus an anti-vacuity control (case 32) proving the same store is over-cap without the fix | **Quality restoration.** 51% of injections carried a truncated contract — the frozen-DoD mechanism was silently not working |
| ~~**M3**~~ | ✅ **DONE 2026-08-16 `47ddbf47c` — the burn-ratio instrument.** `wall_projection()` in `bin/claude-accounts`: `burn_ratio` = (weekly_pct/100) ÷ elapsed_fraction, `proj_end_pct`, `wall_risk`, all exported per row; the footer is re-captioned from `pace to 100%` (which named the failure mode as the goal) to *weekly burn (1.00× = lands exactly at the 100% wall)* and flags `⚠ WALL`. **Abstains below 5% elapsed** — the load-bearing guard: at 1 h in, a 1% reading projects to 168% and would page on every fresh window. | **L** *(deviation from the S default: the metric's whole content is the correction this session measured; a dispatched brief would have had to re-derive it, and the change is one function + one footer)* | met — live on 4 accounts at 0.46/0.51/0.54/0.73×, all projecting 46–73% by reset, no wall risk | Closed the error class that inverted this plan's own premise (§1), in the renderer that produced it. 8 bats, RED-proved 8/8; the floor additionally mutant-proved (0.05→0.0 reds case 1 alone) because an absence-red is weak |
| ~~**M4**~~ | ✅ **DONE 2026-08-24 `5727aeab`** — **the price list as code.** `bin/cc-quota-price` + `tests/cc-quota-price.bats`: L1 deduped transcript census × L2 `account-utilization.jsonl` → L3 NNLS fit on the same (account, 6h) grid §2.2 used. The `message.id` dedup is a **tested invariant with a live seam** (`CC_QP_DEDUP=0`), not a comment. **cache_read is refused as a fitted coefficient** — §2.8's experimental bound is reported instead, because `corr(output, cache_read)=+0.909` plus NNLS's zero floor makes a fitted 0.0000 a boundary artifact, which is exactly what A1's exact zero was. | **L** *(deviation from the S default: the whole content of the tool is §2.1/§2.8's corrections, which a dispatched brief would have had to re-derive from this plan before it could write a line)* | met — `--selftest` 13/13 (incl. the ≥2× RED-proof) · bats 14/14 · fit recovers a KNOWN price vector within 5% | Every later cost claim was unpriced without it. The dedup bug silently corrupted a keystone number in this very wave |
| **M5** | **De-duplicate `./CLAUDE.md`** — byte-identical to the global copy on all 5 load paths; move the versioned source to a path Claude Code does not auto-load | **S** *(reclassified — see below)* | a session in this repo loads the global CLAUDE.md exactly once; the deploy gate still asserts repo↔live parity from the new path; `install.sh` still reports the line count | Q1 free win, ~5 pp/week fleet, zero informational loss |
| **M6** | **Enable OTel** in all 5 config dirs + a local collector | S | `claude_code.token.usage` rows land in the collector for a live session, and `grep ENABLE_TELEMETRY` finds it in 5/5 settings.json | The token-free numerator; scope (c) satisfied by construction |
| ~~**M7**~~ | ✅ **DONE 2026-08-24 `09c3c4c5`** — **`cc-value`'s extinct join now reports its own coverage.** Re-measured on trunk: **0 of the last 500 commits** carry `Session-Id:` or `Land-Session:`. `.attribution` carries {verdict, reason, key, commits, attributed, **trailerless**, **unjoined**, coverage_pct}; on ABSTAIN the per-account and per-session commit columns are **NULL, not 0**, and `cc-board`'s footer renders `?c`. | **L** | met — ABSTAIN names the extinct key; the joined world still reports 1/2 = 50% coverage, so the verdict is DERIVED, not hardcoded | An instrument silently reporting over an empty join is worse than no instrument |

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

### §4.1 Landed 2026-08-16 (the research wave)

| commit | what |
|---|---|
| `7c9f36316` | `fix(cache-expiry-warning)` — TTL 300s→3600s (77.3% of its fires were false) and the `/clear`//`/compact` advice removed, because against the weekly limit it converted a free `cache_read` into a paid `cache_creation`. Verified with a positive control. |
| `47ddbf47c` | `feat(claude-accounts)` — M3, the burn-ratio instrument. See the M3 row above. |

### §4.2 Landed 2026-08-24 (M4 + M7)

| commit | what |
|---|---|
| `5727aeab` | **M4 — `bin/cc-quota-price` + `tests/cc-quota-price.bats`.** The converter §3.1 calls the actual deliverable, made re-runnable. 13 selftest cases + 14 bats cases; **RED-proved by mutation 6/6** (dedup removed → case 1 · reset guard → 7 · stale filter → 8 · absent-store abstain → 3 · cache_read promoted to fitted → 6 · bucket floor → 9). Two assertions were WEAKENED-PROOF at first pass and were tightened until their mutants went red — see the learning below. |
| `09c3c4c5` | **M7 — `cc-value` + `cc-board`.** The attribution join reports its own coverage and abstains when it has none. RED-proved by mutation 5/5. |
| `45158b0f` | **M2 — `hooks/dod-persist.sh` + its suite.** The SessionStart payload is kept under the harness's silent-truncation cap; 37/37 bats, RED-proved 3/3. |

**Remaining after this wave: M1, M5, M6 — and all three are blocked on the LIVE BOX, not on
judgment.** M2/M4/M7 were tractable here because each is repo code with a hermetic test. The other
three are not, and it is worth saying why so the next session does not re-discover it: **M1** needs
`account-utilization.jsonl` and the live dispatcher queue to govern anything; **M5** modifies a
deploy gate (`install.sh`, `deploy-parity-assert.sh`) whose assertion is repo↔live parity, which
cannot be verified anywhere but the box; **M6** writes `CLAUDE_CODE_ENABLE_TELEMETRY` into five
`settings.json` files, which C10 forbids editing in place. Each wants a session **on the desk**.

**Learnings from this wave, recorded because both generalise past this plan.**

1. 🚨 **A mutation that survives is a WEAKENED assertion, and the survivor looked like the strongest
   case in the file.** M4's abstain case asserted the reason names the store's *path*. Deleting the
   entire absent-store guard did **not** turn it red: control fell through to the *next* abstain rung
   ("0 usable samples"), whose reason also names the path. The case was checking the noun both rungs
   share instead of the verb that distinguishes them. Same shape on the cache_read case — it asserted
   the *label* `bounded` while a mutant that promoted cache_read to a regressor still produced that
   label, because the bounded block overwrote the fitted one downstream. **The fix in both was to
   assert against the thing only the correct code path can produce**: the rung's own words
   (`"does not exist"`), and the absence of `cache_read` from `fit.coef_pp_per_token` — i.e. that the
   column never entered the design matrix, not that its output was relabelled afterwards. *Generalisable
   rule: assert on the discriminator between the branches, never on what they have in common — and
   run the mutant, because reading the assertion will not tell you which one you wrote.*
2. **An empty join does not merely under-report — it makes a detector FIRE.** M7 was filed as "an
   instrument silently reporting over an empty join", i.e. a reporting defect. It was worse than
   that: `cc-value`'s per-session churn predicate is `bysid[sid] == 0`, and an empty join satisfies
   it for *every* session, so every active session over 40% fill was being convicted of churning on
   evidence that was structurally absent rather than negative. *Generalisable: when a join dies, audit
   every predicate that reads `count == 0` off it — absence and zero are the same value and opposite
   facts.*
