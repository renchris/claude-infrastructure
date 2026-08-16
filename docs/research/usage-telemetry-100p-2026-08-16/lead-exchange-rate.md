---
axis: A0 (lead) — the quota exchange rate, derived
status: measured
date: 2026-08-16
headline: The fleet is not under-utilizing its weekly limits — it is near-saturating them (4 of 5 complete windows ended at 85–100%, one at exactly 100%), so the goal's real target is not "spend more" but "never let an account hit the wall, and stop wasting the ~$3,000/week of inference each window is worth".
load_bearing_claim: account-utilization.jsonl's weekly_pct series, joined to transcript token totals over whole windows, shows every account reaching 85–100% weekly before reset — which falsifies the point-in-time readout's apparent 1–3% idleness.
---

## Headline

The premise this investigation opened on was **wrong, and wrong in the direction that matters**. A
live `claude-accounts --readout` showed three of four accounts at 1–3% weekly with 6+ days left and
every `pace to 100%` line reading BEHIND, which reads as gross under-utilization. It is not. Those
readings are **three weekly windows that had just reset**. Reconstructed from the
`account-utilization.jsonl` time series, the *previous complete* window for every account ended at:

| account | window closed | weekly_pct reached |
|---|---|---|
| next | 2026-08-16T04:00Z | **91%** |
| next2 | 2026-08-15T11:00Z | **92%** |
| next3 | 2026-08-11T12:00Z | **100%** ← exhausted |
| next4 | 2026-08-16T09:00Z | **85%** |

So the fleet already runs its weekly allowance at 85–100%. **Under-use is not the defect; hitting
the wall is.** `next3` reached exactly 100% and an account at 100% is *down* until its reset —
which for a weekly window can be days. That inverts the design target: the telemetry's first job is
not to push utilization up, it is to (1) land the fleet in the high-90s *without* any single account
hitting 100, and (2) make sure the tokens spent inside that near-full window are not waste, because
at saturation every wasted token **displaces real work** rather than merely costing money.

## The correction, and why the instrument caused it

This matters beyond the number. A point-in-time percentage against a *periodically resetting*
counter carries almost no information on its own — its value is dominated by *where you are in the
window*, not by how you are using it. `claude-accounts --readout` renders exactly that number, and
its `pace to 100%` line compounds the error by extrapolating from a window that has barely started.
The fleet's own headline instrument therefore produced a reading that inverted the truth, and it did
so *truthfully* — every figure in it was correct.

**This is the specification for the rebuild in one sentence: a usage instrument must report against
the window's elapsed fraction, not against the window.** The right primitive is
`weekly_pct / elapsed_fraction_of_window` — a **burn ratio** where 1.0 means "exactly on pace to
finish at 100%", <1.0 means headroom is being left on the table, and >1.0 means this account will
hit the wall early. Every account above reads ~1.0 on that measure and would have all week; the
raw percentage read 0.03.

## Findings

| claim | evidence | status | coverage |
|---|---|---|---|
| A usage time-series **does** exist — `~/.claude/logs/account-utilization.jsonl`, 5,017 samples, 4 accounts, 2026-08-10 → 08-16, carrying `weekly_pct`/`session_pct`/`fable_pct` + reset stamps | direct read; schema keys enumerated | MEASURED | 6 days; sampled ~every 6 min |
| The lead's initial "no usage store exists" claim was **false** — a filename search for `*usage*`/`*quota*` missed a file named `*utilization*` | `find ~/.claude -iname '*usage*' -o -iname '*quota*'` returned only unrelated hits; positive control: the same search *does* surface `~/.claude/archives/cleanup-20260725/usage` | MEASURED | — |
| Every account reached 85–100% weekly in its last complete window | window reconstruction above, 5 windows | MEASURED | 5 windows / 4 accounts |
| `next3` reached **100%** — a real exhaustion event, not a near-miss | window 2026-08-11T12:00Z, pct 58→100 over 30h | MEASURED | 1 event |
| **95.3% of all tokens billed are `cache_read`**; output is 0.4%; raw input is ~0.0% | fleet totals over matched intervals, 12.3M raw tok per 1% split by class | MEASURED | 291 pct-points |
| A full weekly window is worth **~$1,900–$3,800 of API list-price inference** per account (mean ≈ $2,960); ≈ **$11,800/week ≈ $614K/yr** across four accounts | 5 windows, list prices per `PRICE` table (prices ASSUMED pending A8) | MEASURED (given assumed prices) | 5 windows |
| **Output tokens are the tightest correlate** of weekly consumption (spread 1.39× across accounts) vs raw tokens 1.92×, list cost 1.74×, non-cached 2.05× | window-integrated hypothesis test, `unit_test3.py` | MEASURED | 5 windows |
| …but the unit is **NOT identified**, because the estimator's own noise floor exceeds the discrimination needed | `next3`'s two windows differ 18.99M vs 32.57M raw tok/1% — a **1.72× within-account** spread, i.e. as large as the 1.39–1.92× between-account spread being used to discriminate | MEASURED | 2 windows, 1 account |
| Model mix inside measured windows is 81–98% Opus 5, 2–19% Fable 5, ~1% Sonnet/Haiku | per-window mix table | MEASURED | 5 windows |
| Systematic under-count, uncorrected: **cloud sessions (`cc-offload`) draw plan quota but write no local transcript** | design of `bin/cc-offload`; not quantified here | INFERRED | — |

## Method

1. `account-utilization.jsonl` → per-account `(ts, weekly_pct, weekly_reset_at)`.
2. Window identity = **reset stamp rounded to the hour**. *This was the first bug:* the raw stamp
   carries sub-second drift (1137 of 1191 consecutive `next3` pairs differ on microseconds alone),
   so comparing it as a string discarded every interval and produced a vacuous `ABSTAIN` across all
   four accounts. A guard that convicts its entire population is indistinguishable from an absence.
3. Outlier screen: a window must hold ≥20 samples. The raw series contains reads such as `next3`
   58 → 18 → 65 inside 40 minutes carrying an 8-hour reset stamp — a different limit family leaking
   into the weekly field. Unscreened, these manufacture enormous fake deltas.
4. Transcript harvest per account config dir (`next`→`~/.claude`, `next2`→`~/.claude-secondary`,
   `next3`→`~/.claude-tertiary`, `next4`→`~/.claude-quaternary`), deduped on `message.id`,
   `"usage"` substring pre-filter before JSON parse. 50,326 assistant turns, 12.46 B raw tokens.
5. **Estimator v2 (rejected):** per-rising-interval. `weekly_pct` is an **integer**, so a rising
   interval is just the ~6-minute sample gap in which the counter ticked; it attributes a whole 1%
   to whatever landed in those 6 minutes. Quantization error 1 part in 1. No hypothesis separated
   (best 1.62×) because the estimator was noise.
6. **Estimator v3 (used):** window-integrated — all tokens between a trusted window's first and last
   sample, divided by the pct consumed over that same span. Quantization error 1 part in ~80.

**What I could not measure.** The raw OAuth `usage` API payload (left to A1). Whether cloud sessions
account against the same weekly counter. Whether Fable's documented ≤50% weighting is applied to the
weekly counter at all — H3 (list cost with Fable at half) was *worse* than H2, which is weak evidence
against a simple 50% weighting, but it is inside the noise floor and must not be reported as a result.

## Recommendations

| action | expected effect | quality risk | effort |
|---|---|---|---|
| Replace the headline utilization metric with a **burn ratio** `weekly_pct ÷ elapsed_fraction_of_window`, and render *that* in `claude-accounts --readout` beside the raw pct | Removes the class of error that inverted this investigation's premise. ~1.0 = on pace; the current renderer cannot express this at all | **NONE** — adds a field, removes nothing | small |
| Add a **wall-proximity alarm** keyed on projected end-of-window pct, not current pct. `next3` hit 100% and nothing flagged it in advance | Prevents the one failure that actually costs work: an account down for days mid-wave | **NONE** | small |
| Keep `account-utilization.jsonl` and **raise its retention** — it is the only durable record that made this correction possible, and it currently holds 6 days | Makes exchange-rate and burn analysis reproducible over a month rather than a week | **NONE** | trivial |
| Record the **API's raw counters** if the payload exposes any (A1 to confirm) — an integer percentage is quantized 1-in-100 and is why the unit could not be identified | Would settle the exchange rate outright, and price every other decision in this plan | **NONE** | small, pending A1 |
| Do **not** act on "we are under-utilizing" | The premise is false; acting on it would push a near-saturated fleet into the wall | — | — |

---

## ADDENDUM — validating A1, and a 3× calibration error found in its keystone number

A1 (`exchange-rate.md`) did the derivation properly and got the **shape** right where my aggregate
estimator could not: it fitted per-class coefficients by NNLS rather than testing whole-unit
hypotheses, which is why it could separate `cache_read ≈ 0` from the rest. Its shape is corroborated.
Its **level is wrong by ~3×**, and the cause is a transcript artifact both of us had to handle.

### The hold-out check

I applied A1's coefficients to a *different aggregation* it was not fitted on — whole weekly windows
— and compared predicted against the pp the API actually reported:

| account | window | actual Δpp | predicted (A1 coef) | ratio |
|---|---|---|---|---|
| next | 2026-08-16 | 80 | 27.6 | 0.35 |
| next2 | 2026-08-15 | 82 | 33.1 | 0.40 |
| next3 | 2026-08-11 | 42 | 11.5 | 0.27 |
| next3 | 2026-08-18 | 20 | 4.9 | 0.25 |
| next4 | 2026-08-16 | 80 | 24.6 | 0.31 |
| **total** | | **304** | **101.8** | **0.33** |

Under-prediction is **consistent** (spread 1.64×, all five in 0.25–0.40), which indicts a systematic
scale factor rather than noise.

### The cause: streamed assistant messages are written to the transcript repeatedly

Claude Code writes the *same* assistant message to the `.jsonl` multiple times as it streams. Measured
on 120 files / 11,040 usage-bearing records in `~/.claude-tertiary`:

- 3,632 of 4,566 distinct `message.id`s appear more than once (58.7% of records are repeats).
- **98.5% of duplicate groups carry byte-identical usage**; **0 groups span more than one file**.
- Example `msg_011CduY5eWpuF5nGuNT22QBH` — three records at `18:25:03.343Z`, `18:25:05.476Z`,
  `18:25:06.498Z`, all `output=402, cache_read=21673, cache_creation=111411`.

So one `message.id` is **one billed API response**, and deduping on it is correct. A census that sums
every record over-counts by ~2.4×. That is the bulk of the 3.0× gap; the residual is consistent with
usage this instrument structurally cannot see — Anthropic's own docs say `/usage` attribution is
"computed from local session history **on this machine**", so cloud (`cc-offload`) and claude.ai usage
draw the same plan quota and appear in no local transcript.

### The calibrated exchange rate (use these, not A1's raw coefficients)

Calibration factor = 304 actual pp ÷ 101.8 predicted pp = **2.99**.

| class | A1 pp/M | **calibrated pp/M** | **tokens per 1 pp** |
|---|---|---|---|
| Opus-5 output | 1.282 | **3.83** | **261,208** |
| Opus-5 cache_creation | 0.105 | **0.314** | 3,189,223 |
| Opus-5 cache_read | 0.000 | **0.000** | free |
| Fable-5 output | 1.680 | **5.02** | 199,326 |
| Fable-5 cache_creation | 0.300 | **0.896** | 1,116,228 |

**Consequences for A1's headline, which should be read with these numbers substituted:**

| A1 stated | corrected |
|---|---|
| 1 pp ≈ 780K Opus output tokens | **≈ 261K** |
| full account-week ≈ 78M output tokens | **≈ 26M** |
| fleet headroom 374 pp ≈ 292M output tokens | **≈ 98M** |

The *relative* prices — and therefore every routing conclusion drawn from them — are **unchanged**,
because a uniform scale factor cancels in the shares. What changes is capacity planning: the fleet
has one third of the headroom A1 credits it with, which strengthens rather than weakens the
near-saturation reading above.

### Quota shares (calibration-independent)

Applying the shape to the deduped 7-day census:

| class | % of tokens | **% of quota** |
|---|---|---|
| output | 0.44% | **61.4%** |
| cache_creation | 3.32% | **37.9%** |
| cache_read | **96.24%** | **0.0%** |
| input | 0.01% | 0.7% |

**96% of the tokens this fleet moves cost 0% of its quota.** Quota is spent on what the model
**emits** and on what **newly enters** the cache — never on re-reading context that is already there.
One output token costs the same quota as **12.2** cache-creation tokens and as **infinitely many**
cache-read tokens.

⚠️ **This is the single most decision-changing result in the wave, and it inverts the default
intuition.** Shrinking a context to save quota optimizes the *free* class. It also means the
operator's existing Communication-Discipline rule (Opus 5 runs long; brevity must be prompted for)
is not a style preference — it is the **primary quota lever**, worth 61% of the bill.

---

## What would falsify my headline

- If `weekly_pct` in this series is not the *plan's* weekly limit but some other counter (e.g. a
  per-model sub-limit), the 85–100% readings mean something else. A1's read of the raw API payload
  settles this.
- If the 4 accounts' windows observed here were unusually busy, 85–100% is not the steady state. Six
  days is one window per account; retention beyond 6 days would test it.
- If a large share of quota is consumed by cloud sessions invisible to local transcripts, the
  tokens-per-1% figures are inflated by an unknown factor — though this does **not** touch the
  headline, which rests on `weekly_pct` alone.
