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

1. **Shrinking context to save quota optimizes the free class.** Recycling, `/compact`, and
   aggressive context trimming are justified by *rot* and by the hard context ceiling — both real —
   but **not** by quota. They should never again be argued on cost grounds.
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

🚨 **And the cause is mechanical, not a shortage of work.** The autonomous dispatcher has parked
**254 of 261 dispatchable items behind a cloud-only venue filter since 2026-08-11** and fires only
~17 sessions/day; fleet burn fell to **38% then 21%** of its own demonstrated daily capacity on
08-14 and 08-15. So the answer to scope item (a) is not "find more work" and not "route better" —
**it is a stuck filter holding 97% of the queue**, which the burn-ratio metric would have surfaced
within a day of it engaging. Fixing that is the single largest utilization lever, and it is a
**Q2 win** (more quality work into quota that would otherwise expire), not a Q1 saving.

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
- **Effort downgrades** — A6: effort moves only output tokens within a turn whose cost is dominated by
  conversation cache; the ladder spans 5.6× in thinking for a 14-point cost band. A downgrade buys
  little and risks quality — a Q3, therefore rejected outright.
- **Cutting telemetry to save tokens** — it is 0.6–1.2% of throughput, and the two defects found are
  quality failures, not cost ones.

## §4 Implementation

**Execution locus: S (dispatched session) for every wave below except M5**, per Phase 0 and the
global default. Each fires with `--goal` naming a measurable end state and the command that proves
it, because the goal evaluator is tool-less and can only judge what the session *prints*.

W3.1 and W3.4 are independent of everything else and are the two highest-value items; fire them
first and in parallel.

| id | wave | locus | end state (the `--goal` condition) | why it ranks here |
|---|---|---|---|---|
| **M1** | **Unblock the dispatcher** — 254 of 261 dispatchable items parked behind a cloud-only venue filter since 2026-08-11 | S | `cc-backlog`/dispatcher prints a dispatchable count where local-venue items are ≥90% of the eligible set, and daily fire count returns to the demonstrated ~40+/day capacity; do not widen quota exposure by disabling any safety gate | **The largest lever in the plan and the real answer to scope (a).** Q2: converts quota that expires into delivered work |
| **M2** | **Fix the DoD truncation** — `dod-persist.sh` concatenates a frozen legacy store, overflows the ~9,200 B cap, and delivers the *oldest* scope | S | a session in this repo shows the NEWEST `Scope (frozen):` line inline in `hook_additional_context`, with no `<persisted-output>` stub, on 3 consecutive starts | **Quality restoration.** 51% of injections currently carry a superseded contract — the frozen-DoD mechanism is silently not working |
| **M3** | **The burn-ratio instrument** — add `burn_ratio` and `projected_end_pct` to `claude-accounts --readout`; wall-proximity alarm; raise `account-utilization.jsonl` retention past 6 days | S | `claude-accounts --readout` prints a burn ratio per account and flags any account whose projected end-of-window pct ≥100; `next3` renders 0.26 today | Closes the error class that inverted this plan's own premise (§1) |
| **M4** | **The price list as code** — `cc-quota-price`: re-fit tokens→pp on a schedule from `account-utilization.jsonl` × deduped transcripts, with the **`message.id` dedup as a tested invariant** | S | `cc-quota-price --selftest` passes, including a RED-proof case that a non-deduping extractor inflates output tokens ≥2× | Without it, every later cost claim is unpriced — and the dedup bug silently corrupted a keystone number in this very wave |
| **M5** | **De-duplicate `./CLAUDE.md`** — byte-identical to the global copy on all 5 load paths; move the versioned source to a path Claude Code does not auto-load | **L** *(one file move + a pointer; briefing a session costs more than doing it)* | a session in this repo loads the global CLAUDE.md exactly once; `md5` of the versioned source still matches `~/.claude/CLAUDE.md` | Q1 free win, ~5 pp/week fleet, zero informational loss |
| **M6** | **Enable OTel** in all 5 config dirs + a local collector | S | `claude_code.token.usage` rows land in the collector for a live session, and `grep ENABLE_TELEMETRY` finds it in 5/5 settings.json | The token-free numerator; scope (c) satisfied by construction |
| **M7** | **Disconnect or repair `cc-value`'s extinct join** — it joins on a git trailer this repo measured extinct 4 days ago | S | `cc-value` either reports ABSTAIN with a named reason, or joins on a key with >0 coverage proven in its output | An instrument silently reporting over an empty join is worse than no instrument |

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
