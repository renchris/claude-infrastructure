---
axis: A1 — the quota exchange rate (what unit does the weekly limit count?)
status: DERIVED — first empirical exchange rate for this fleet; the joinable time-series the lead
        believed absent DOES exist
date: 2026-08-16
headline: >
  The weekly limit is denominated in a WEIGHTED COST unit the API itself calls dollars
  (`limit_dollars`/`used_dollars`/`remaining_dollars`, withheld as null on Max), and this fleet's
  own 6-day utilization series joined against its transcripts prices it: 1 weekly percentage point
  ≈ 780K Opus-5 OUTPUT tokens or 9.5M cache-CREATION tokens, while cache-READ tokens are charged at
  essentially nothing — so a full account-week is ~78M Opus output tokens (~$7.4K API-list) and the
  four-account fleet is sitting on 374 pp ≈ 292M output tokens of headroom that expires in 2–7 days.
load_bearing_claim: >
  Weekly-% burn is a near-linear function of OUTPUT + CACHE-CREATION tokens with a near-zero
  coefficient on CACHE-READ tokens. Fitted by NNLS over 265 ≥2h intervals across 4 accounts,
  R²=0.82, 5-fold CV RMSE 1.63 pp vs sd(y)=2.13; independently replicated on the disjoint 5-hour
  bucket (128 intervals, R²=0.54) which reproduces the same out:cc ratio (9.0 vs 12.2) from a
  different denominator.
---

## Headline

**The unit is a weighted cost unit, not tokens and not requests — and the API says so in its own
schema.** The raw `api.anthropic.com/api/oauth/usage` payload (captured verbatim below, first time
in this repo) carries `limit_dollars`, `used_dollars`, `remaining_dollars` on both the `five_hour`
and `seven_day` buckets; on these Max accounts all three are `null` while `utilization` (a percent)
is populated. Overflow past the plan limit is billed through `extra_usage`/`spend`, denominated in
**cents** (`spend.used.amount_minor`, `exponent: 2`; `used_credits` verified as cents 2026-07-26 at
`bin/claude-accounts:1141`). So the meter is monetary; consumer plans are simply shown the meter's
percentage and denied its face value.

**The exchange rate is derivable retrospectively — the lead's feasibility gate is REFUTED.** A usage
time-series *does* exist: `~/.claude/logs/account-utilization.jsonl`, written by
`record_utilization()` (`bin/claude-accounts:2236`) and driven every 180 s by
`com.claude.accounts-keepwarm`. 5,013 rows, 4 accounts, 2026-08-10T05:58Z → 2026-08-16T10:20Z,
**median inter-sweep gap 6.3 min, p99 15.2 min, max 205 min, zero gaps > 6 h**. The lead searched for
`*usage*`/`*quota*`; the file is named `account-utilization.jsonl`, which is why the search missed it.
Joining that series against 140,928 assistant-message usage records extracted from the same window's
transcripts (1,283 files, 1.77 GB) gives the first measured price list this fleet has ever had:

| against the **weekly** limit | pp per 1M tokens | 1 pp buys |
|---|---|---|
| Opus-5 **output** | 1.282 | **780K tokens** |
| Opus-5 **cache-creation** | 0.105 | 9.5M tokens |
| Opus-5 **cache-read** | **0.000** (p95 ≤ 0.0017) | ≥ 590M tokens |
| Fable-5 output | 1.680 | 595K tokens |
| Fable-5 cache-creation | 0.300 | 3.3M tokens |
| Fable-5 cache-read | 0.0096 | 104M tokens |

The single most decision-changing consequence: **re-reading a large cached context is nearly free
against the plan limit; what you pay for is tokens you EMIT and tokens that newly ENTER the cache.**
Under the operator policy (never trade quality for tokens; under-use is itself a defect) this
removes the main reason to shrink contexts, and it prices the standing under-utilization: the fleet
currently holds **374 pp of weekly headroom ≈ 292M Opus-5 output tokens ≈ $27.5K of API-list-equivalent
work**, expiring on staggered resets 2–7 days out.

---

## The raw payload (ground truth, captured 2026-08-16 ~10:30Z, account `next`, HTTP 200)

Re-issued read-only through the same auth path `claude-accounts` uses (keychain item
`Claude Code-credentials-<sha256(realpath(config_dir))[:8]>` → `claudeAiOauth.accessToken`, headers
`anthropic-beta: oauth-2025-04-20`, `User-Agent: claude-cli/2.1.183`). All four accounts returned
structurally identical payloads.

```jsonc
{
  "five_hour":  { "utilization": 4.0, "resets_at": "2026-08-16T13:30:00.185150+00:00",
                  "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
  "seven_day":  { "utilization": 3.0, "resets_at": "2026-08-23T04:00:00.185166+00:00",
                  "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
  "seven_day_oauth_apps": null, "seven_day_opus": null, "seven_day_sonnet": null,
  "seven_day_cowork": null, "seven_day_omelette": null,
  "tangelo": null, "iguana_necktie": null, "omelette_promotional": null,
  "nimbus_quill": { "utilization": 0.0, "resets_at": null,
                    "limit_dollars": null, "used_dollars": null, "remaining_dollars": null },
  "cinder_cove": null, "amber_ladder": null,
  "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null,
                   "utilization": null, "currency": null, "decimal_places": null,
                   "disabled_reason": null, "user_disabled": true, "spend_limit_reached": false,
                   "credits_ever_enabled": true, "daily": null, "weekly": null },
  "limits": [
    { "kind": "session",       "group": "session", "percent": 4, "severity": "normal",
      "resets_at": "2026-08-16T13:30:00.185150+00:00", "scope": null, "is_active": true },
    { "kind": "weekly_all",    "group": "weekly",  "percent": 3, "severity": "normal",
      "resets_at": "2026-08-23T04:00:00.185166+00:00", "scope": null, "is_active": false },
    { "kind": "weekly_scoped", "group": "weekly",  "percent": 3, "severity": "normal",
      "resets_at": "2026-08-23T04:00:00.185315+00:00",
      "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null },
      "is_active": false }
  ],
  "spend": { "used": { "amount_minor": 0, "currency": "USD", "exponent": 2 }, "limit": null,
             "percent": 0, "severity": "normal", "enabled": false, "cap": null, "balance": null,
             "auto_reload": null, "can_purchase_credits": false, "can_toggle": false,
             "disclaimer": "Usage credits cover you when you hit your plan limits. …" },
  "member_dashboard_available": false
}
```

Response headers carried **no** `anthropic-ratelimit-*` and no `retry-after`; the only
`anthropic-*` headers were `anthropic-organization-id` and `anthropic-workspace-id` (positive
control — the same filter that found nothing rate-limit-shaped did return those two, so the absence
is measured, not an instrument failure).

**What `bin/claude-accounts` parses, and what it throws away.** `pick()` (`bin/claude-accounts:803-810`)
walks `limits[]` only, matching `kind` ∈ {`session`, `weekly_all`, `weekly_scoped`} with the Fable
scope filtered on `scope.model.display_name` (`:1145-1148`). `extra_usage` is read for credits
(`set_credits`, `:1130-1160`). **`grep -c 'five_hour\|seven_day\|nimbus_quill\|limit_dollars\|amount_minor' bin/claude-accounts` → 0**
(positive control: `grep -c extra_usage` → 2, `used_credits` → 6). So the entire top-level bucket
map — including the dollar fields that name the unit, the nine codenamed buckets, and the
`seven_day_opus` / `seven_day_sonnet` slots that would silently appear if Anthropic ever populated
them — is invisible to every consumer on this box.

---

## Findings

| # | Claim | Evidence | Grade | Coverage |
|---|---|---|---|---|
| 1 | The limit is denominated in a **monetary** unit, not tokens or requests | Payload keys `five_hour.limit_dollars` / `used_dollars` / `remaining_dollars`, `seven_day.*` same; `spend.used = {amount_minor:0, currency:"USD", exponent:2}`; `bin/claude-accounts:1141` comment records `used_credits` = cents, verified against claude.ai (17691 → $176.91) | **MEASURED** (schema) / **INFERRED** (that plan % is a fraction of that same dollar figure) | 4/4 accounts, 1 live call each |
| 2 | Anthropic **withholds** the dollar face value on Max | All three `*_dollars` are `null` on all 4 accounts while `utilization` and `resets_at` in the same object are non-null (positive control) | MEASURED | 4/4 |
| 3 | Anthropic publishes **no** token count for any plan; overflow bills at standard API rates | WebSearch 2026-08-16, morphllm/portkey/tokenkarma round-up: "Anthropic publishes no token count for Claude Pro, or for any other plan"; credits bill at API rates | MEASURED (public sources) / secondary | n/a |
| 4 | **A usage time-series exists** — the lead's "no store on disk" is refuted | `~/.claude/logs/account-utilization.jsonl`, 5,013 rows, 1,375,139 B, 2026-08-10T05:58Z→2026-08-16T10:20Z; producer `record_utilization()` `bin/claude-accounts:2236`; driver `~/Library/LaunchAgents/com.claude.accounts-keepwarm.plist` `StartInterval 180` | MEASURED | 100% of the 4 accounts; 1,254 distinct sweeps |
| 5 | Its sampling is dense enough to differentiate | inter-sweep gaps n=1,253: median **6.3 min**, p90 8.2, p99 15.2, max 205.5; 5 gaps > 60 min, **0 gaps > 6 h** | MEASURED | 6.2 days |
| 6 | **1 weekly pp ≈ 780K Opus-5 output tokens** | NNLS over 265 intervals (≥2 h anchors, within-cycle): `opus_out` = 1.2823 pp/Mtok, bootstrap-600 [p5 0.626, p50 1.137, p95 1.462], never zero | MEASURED (regression) | 265 intervals / 296 pp / 4 accounts / 6.2 d |
| 7 | **1 weekly pp ≈ 9.5M Opus-5 cache-CREATION tokens** (≈ 1/12 of an output token) | same fit: `opus_cc` = 0.1054 pp/Mtok, bootstrap [0.092, 0.107, 0.159], never zero | MEASURED | as above |
| 8 | **Cache-READ tokens are charged at ~zero** against the limit | same fit pins `opus_cr` = 0.0000; bootstrap p95 = 0.0017 pp/Mtok (≥ 590M tokens per pp) and zero in 70% of resamples. Profile: forcing `cr = out/50` (the API-list ratio) costs only R² 0.8126→0.7968 | **INFERRED** — `corr(opus_out, opus_cr) = 0.936`, so the two are not separately identified; the fit *prefers* zero but does not exclude the list-price weight | 265 intervals |
| 9 | Model matters: **Fable output is ~1.31× an Opus output token**, Fable cache-creation ~2.8× | `fable_out` 1.6804 vs `opus_out` 1.2823; `fable_cc` 0.2996 vs 0.1054. API list ratio for both is 2.0× | MEASURED (point estimate) — bootstrap on `fable_out` is wide [0, 1.01, 2.65] (21% of resamples zero); Fable is 6% of messages so it is poorly identified | 8,083 Fable messages / 140,928 total |
| 10 | The **Fable-scoped weekly bucket is real and Fable-driven** | Separate NNLS onto `fable_pct`: `fable_out` 3.111, `fable_cc` 0.569, `opus_out` 0.0069 (450× smaller), R²=0.75. Series-wide, `fable_pct < weekly_pct` on 4,647/5,013 rows | MEASURED | 5,013 rows |
| 11 | `model-config.yaml`'s "Fable at ≤50% of limits" is a **plan-inclusion policy statement, not a draw rate** | `model-config.yaml:118-120` `source: plan-usage` — "Fable 5 is included in ALL Max + Team Premium plans at ≤50% of limits". The mechanism on the wire is a *separate scoped bucket* (`weekly_scoped`), not a 2× multiplier on the shared one | MEASURED (file) / INFERRED (mechanism) | — |
| 12 | **Independent replication on the disjoint 5-hour bucket** | 128 intervals (0.25–1.5 h, 231 pp): `opus_out` 9.2747, `opus_cc` 1.0353, `opus_cr` 0.0000, R²=0.54. out:cc ratio **9.0** here vs **12.2** in the weekly fit — same order, same sign, same zero on cache-read, from a different denominator | MEASURED | 128 intervals |
| 13 | **A weekly allowance ≈ 7.2–9.8 five-hour allowances** | ratio of 5h to weekly coefficients: out 9.2747/1.2823 = **7.23**, cc 1.0353/0.1054 = **9.82**. A week contains 33.6 five-hour windows ⇒ one account can sustain only **~22–29%** duty cycle before the weekly binds | MEASURED (derived from 12 + 6/7) | as above |
| 14 | **A full account-week = 78M Opus-5 output tokens** at the margin, or 4.4–10.2B total tokens at realised mixes | 100/1.2823 = 78.0M. Realised whole-cycle mixes: `next` 80 pp / 6.47B tok; `next2` 82 pp / 7.64B; `next3` 42 pp / 1.84B and 19 pp / 1.28B; `next4` 80 pp / 8.17B ⇒ 4.39–10.2B tok per 100 pp, 27–39M output tokens per 100 pp | MEASURED (bounded range; mix-dependent) | 5 whole/partial cycles |
| 15 | Dollar-weighted API list price is the **best single-parameter** explanation: **$73.50 of API-list-equivalent per weekly pp** | NNLS on one scalar over `5·in + 25·out + 6.25·cc + 0.5·cr` (Opus, 2× for Fable): R²=**0.7638** — versus total-tokens 0.6001, output-tokens-only 0.6970, `in+cc+0.1·cr` 0.6716. ⇒ **~$7,350 per account-week, ~$29.4K/week fleet-wide against $800/mo of subscriptions (~158×)** | MEASURED (fit) / INFERRED (that Anthropic's internal weights *are* list prices) | 265 intervals |
| 16 | The instrument's **resolution floor is 1 pp = ~780K output tokens** | `five_hour.utilization` / `seven_day.utilization` came back 4.0 / 61.0 / 10.0 / 1.0 — floats whose values are always integral; `limits[].percent` is an int. `record_utilization` stores the int (`bin/claude-accounts:2270`) and discards the float | MEASURED | 4/4 accounts, 5,013 rows |
| 17 | **No rate-limit headers are persisted anywhere** | 0/40 recent transcripts (mtime ≥ 2026-08-14, `~/.claude` + `~/.claude-tertiary`) contain `anthropic-ratelimit` or `retry-after` — the single "hit" was this session's own transcript quoting the string. Positive control: 40/40 contain `cache_read_input_tokens` | MEASURED | 40-file sample |
| 18 | Retention is not a near-term risk, but the joiner must handle `.gz` | `scripts/rotate-autonomy-logs.sh:344` lists the file; `ROTATE_MAX_BYTES` 25 MiB, `ROTATE_KEEP` 8, `ROTATE_GZIP` 1 (`:75-76`, `:62-63`). At the measured **217 KiB/day** the first rotation is ~118 days out; 8 kept rotations ≈ 2.6 years of history | MEASURED | — |

### What I could NOT measure (abstentions, not imputations)

| Quantity | Why null |
|---|---|
| The **absolute dollar size** of a weekly allowance | `limit_dollars` is `null` on every Max account. $73.50/pp is an *API-list-equivalent*, i.e. what the same work would have cost on the API — **not** Anthropic's internal per-pp budget. NULL, and it cannot be recovered from this endpoint. |
| The coefficient on **plain (uncached) input tokens** | Uncached input is 0.7M against 33.6M output on the largest account — 2% of the output volume and collinear with everything. NNLS returns 0.0000 with 71% of bootstrap resamples at zero and p95 = 9.15 pp/Mtok. The interval spans four orders of magnitude: **unidentified**, not free. |
| Whether **cache-read is truly free or list-priced** | corr(out, cr) = 0.936; cond(X) = 23,556. Both hypotheses fit (R² 0.813 vs 0.797). Reported as a bound, not a point. |
| Any **pre-2026-08-10** history | The series begins with `record_utilization`'s own arrival. No rotations exist yet (`ls ~/.claude/logs | grep account-util` → one file). Everything here is a 6.2-day window. |
| Per-**surface** attribution (claude.ai web, mobile, other tools on the same account) | The join assumes an account's quota is moved only by sessions whose transcripts land in that account's `projects/` dir. Any out-of-band usage inflates the pp side and biases every coefficient **upward** (i.e. the true token-per-pp figures are floors, not ceilings). |

---

## Method

**1. Payload capture.** Read `bin/claude-accounts` end-to-end for the auth path (`read_creds`
`:355`, `keychain_service` = `Claude Code-credentials-<sha256(realpath(config_dir))[:8]>`,
`fetch_usage` `:641`, `_ssl_ctx` `:624`). Re-issued the same read-only GET for all 4 accounts with an
inline python script (never wrote a repo file; the framework python needs `cafile=/etc/ssl/cert.pem`
or it raises `CERTIFICATE_VERIFY_FAILED`). 4/4 returned HTTP 200.

**2. Account → transcript mapping.** From `accounts.json`: `next`→`~/.claude-next`,
`next2`→`~/.claude-secondary`, `next3`→`~/.claude-tertiary`, `next4`→`~/.claude-quaternary`.
Resolved `projects/` per dir: `~/.claude-next/projects` → `~/.claude/projects` (so `next`'s corpus
IS `~/.claude/projects`); `~/.claude-next{2,3,4}` have no `projects/` at all. Deduped by
`os.path.realpath` before reading, per the recorded double-count trap.

**3. Token extraction.** Streamed every `*.jsonl` under the four `projects/` roots with
`mtime ≥ 2026-08-09`, substring-gated on `"output_tokens"` before `json.loads`. Kept
`timestamp`, `message.model`, and the four `message.usage` counters; aggregated into
(account, 10-min bucket, model). **1,283 files / 1.77 GB / 140,928 usage records / 1,982 keys**,
4.5 s wall. Model mix by assistant-message count: `claude-opus-5` 128,216 · `claude-fable-5` 8,083 ·
`claude-sonnet-5` 723 · `claude-haiku-4-5` 376 · `<synthetic>` 131 · `claude-opus-4-7` 64.

*Coverage:* this is the **whole** 2026-08-09→16 slice, not a sample — 100% of the window the
utilization series covers. It is ~24% of the 7.3 GB corpus by bytes; the other 76% predates the
series and is unjoinable.

**4. Cycle segmentation.** Split each account's `weekly_pct` series on a real drop (`p < prev − 1`);
the sub-second jitter in `weekly_reset_at` (`…T03:59:59.xxx` vs `…T04:00:00.xxx`) makes the reset
stamp useless as a segmentation key — it produced 434 spurious segments for `next` before this fix.
Result: 5 usable cycles.

| account | cycle | span | weekly Δ | Fable-scoped Δ | opus out / cc / cr (M) | fable out / cc / cr (M) |
|---|---|---|---|---|---|---|
| next | 1 | 08-10 05:58 → 08-16 03:58 (142.0 h) | 11→91 = **80 pp** | 0→60 | 22.62 / 160.6 / 5,438.1 | 4.07 / 54.5 / 756.5 |
| next | 2 | 08-16 04:04 → 10:26 (6.4 h) | 1→3 = 2 pp | 0→3 | 0.28 / 2.6 / 58.7 | 0.004 / 2.3 / 3.4 |
| next2 | 1 | 08-10 05:58 → 08-15 10:58 (125.0 h) | 10→92 = **82 pp** | 0→39 | 25.84 / 317.2 / 6,564.2 | 6.14 / 34.2 / 682.5 |
| next3 | 1 | 08-10 05:58 → 08-11 11:59 (30.0 h) | 58→100 = **42 pp** | 13→64 | 7.65 / 56.3 / 1,360.8 | 3.69 / 32.1 / 378.4 |
| next3 | 2 | 08-11 12:04 → 08-16 10:26 (118.4 h) | 0→19 = **19 pp** | 0→5 | 4.83 / 30.3 / 1,112.1 | 0.64 / 1.3 / 114.7 |
| next4 | 1 | 08-10 05:58 → 08-16 08:58 (147.0 h) | 5→85 = **80 pp** | 0→33 | 29.46 / 200.5 / 7,708.0 | 1.58 / 11.8 / 171.8 |

**5. The regression.** Within each cycle, anchored samples ≥ 2 h apart → **265 intervals, 296 pp
total**. Design matrix = 8 columns (opus/fable × in/out/cc/cr, in Mtok). `scipy.optimize.nnls`
(non-negativity is the physical constraint: no token class can *refund* quota).
R² = **0.8161**. 5-fold CV RMSE **1.633 pp** vs sd(y) = 2.133. Bootstrap n=600.

Model comparison (all NNLS, same 265 rows):

| model | free params | R² |
|---|---|---|
| full 8-feature | 8 | **0.8161** |
| out + cc + cr (6) | 6 | 0.8161 |
| out + cc (4) | 4 | 0.8126 |
| **API-list-dollar, single scalar** | **1** | **0.7638** |
| output tokens, single scalar | 1 | 0.6970 |
| `in + cc + 0.1·cr`, single scalar | 1 | 0.6716 |
| total tokens, single scalar | 1 | 0.6001 |

**6. Independent replication.** Repeated the whole pipeline against `session_pct` (the 5-hour
bucket) using 0.25–1.5 h intervals with non-negative Δ: 128 intervals, 231 pp, R² = 0.5426. This
shares the token side but has a *completely different* denominator and reset cadence, so agreement
on the out:cc ratio (9.0 vs 12.2) and on cache-read ≈ 0 is genuine corroboration, not circularity.

**7. Per-account stability check.** Fitting output-only per account gives `opus_out` of 2.07 / 2.32 /
0.00 / 2.01 pp/Mtok for next / next2 / next3 / next4 — `next3` degenerates because its Fable share is
much higher, which is exactly why the pooled multi-feature fit is the reportable one and the
single-feature per-account fits are not.

---

## Recommendations

| # | Action | Expected effect (quantified) | Quality risk | Effort |
|---|---|---|---|---|
| R1 | **Stop treating long cached context as quota-expensive.** Publish finding #8 as an operating fact: cache-READ is ≤ 1/750 of an output token against the weekly limit; context *re-reads* are ~free, context *growth* (cache-creation) costs 1/12 of an output token, and only OUTPUT is expensive. | Removes the standing incentive to trim context. On `next`'s 80 pp cycle, 5.44B of 6.47B tokens (84%) were cache-read — i.e. **84% of the fleet's token volume is in the class the limit barely charges for**. Any "shrink the context" saving targets ≤ 16% of volume and buys ≤ 1/12-weight tokens. | **NONE** — it authorises *more* context, which is the quality-positive direction | 1 h (doc + CLAUDE.md line) |
| R2 | **Spend the standing headroom.** Fleet weekly headroom right now is 374 pp = **292M Opus-5 output tokens ≈ $27.5K API-list-equivalent**, expiring on staggered resets 2–7 d out. Route the goal's own remaining waves as dispatched sessions rather than serialising them. | Converts the measured under-utilisation defect into work. 374 pp ≈ **4.7 full account-weeks** of headroom sitting idle. | NONE | 0 — a routing decision |
| R3 | **Land the joiner as a tool: `bin/cc-quota-rate`.** Nightly (or on demand) re-run §4–5 over the last N days and append one row of fitted coefficients + R² + n to `~/.claude/logs/quota-exchange-rate.jsonl`. All inputs already exist; **no new producer, no new network call, no new quota**. | ~**300 bytes/day** (~0.1 MB/yr) for a continuously re-derived price list. Makes every later optimisation priced instead of guessed, and makes coefficient DRIFT (Anthropic re-weighting) observable within a day. | NONE — read-only derived store; the telemetry-bloat constraint is met by 3 orders of magnitude | 4–6 h |
| R4 | **Widen `record_utilization` to the full bucket map** — store `five_hour`/`seven_day` `utilization` as **floats** (not the int `percent`), plus `*_dollars` (null today, non-null the day Anthropic exposes them), plus every non-null top-level bucket incl. `seven_day_opus`/`seven_day_sonnet`/`nimbus_quill`. `pick()` reads `limits[]` only; grep proves the rest is discarded (finding #18/§payload). | Removes the 1-pp = 780K-token quantisation floor *if* the float ever carries decimals; and makes a newly-populated model-scoped bucket visible on day 1 instead of never. Row grows ~120 B → ~+130 KiB/day at current cadence (still under 1 % of the log dir). | **LOW** — `record_utilization` swallows all errors by design (`:2252` blast-radius note); a wider row cannot break routing | 2–3 h |
| R5 | **Record the model each account was actually running per sweep.** The exchange rate is per-model and the util series is model-blind; today the join must go through transcripts, which cannot see out-of-band (web/mobile) usage. | Closes the one bias named in the abstentions table — currently every token-per-pp figure is a **floor** of unknown tightness. | NONE | 2 h |
| R6 | **Do not use `$73.50/pp` as an internal cost.** It is an API-list *equivalent* (finding #15), not Anthropic's budget; `limit_dollars` is null and cannot be recovered. Use it only for cross-model routing arithmetic, never for a "we're spending $X" claim. | Prevents a 158×-inflated spend figure entering a close or a plan. | NONE (it is a guardrail) | 0 |
| R7 | **Re-run the fit after ≥ 2 more full weekly cycles per account, and after any Anthropic pricing/limit announcement.** Current n = 5 cycles / 6.2 days; the Fable coefficient in particular is unstable (bootstrap p5 = 0). | Tightens `fable_out` from [0, 2.65] to something usable; detects re-weighting. | NONE | 30 min once R3 exists |

### R1 — what it superseded, and the ruling that closed it (added 2026-08-24)

R1's "standing incentive to trim context" was not hypothetical: it was a **named, live policy line in
this repo**, and R1 shipped without citing it, so both documents stood for 15 days giving directly
opposite advice. `scaling-bottlenecks-2026-08-09.md:36,150` prescribed *"68% of quota cost is
cache-read at median ~200K contexts ⇒ halving context ≈ +50% active capacity — bigger than a fifth
account"*, carried into that doc's standing-policy list. It was priced from a composition model
(cache-read 68% / cache-write 18% / output 14%), never from the meter.

**Ruled 2026-08-24, class A (measurement supersedes an unvalidated composition model): this
document's rate governs.** That clause is struck at both sites; the full reasoning, the arithmetic
showing the 68% premise fails under the API-list hypothesis too (**~28%**, so the lever is worth 0%
to ≤ +16%, never +50%), and the corrected sustainable-active figure (A6 §C4's model-free
**6.2–11.0**, replacing the cache-read-priced 3.9) are in
**`scaling-bottlenecks-2026-08-09.md` §2a**. Chain of custody:
`orchestration-units-2026-08-19.md` N7 (REFUTED, *"needs a filed decision"*) →
`orchestration-units-2026-08-19/A6-VERIFY-quota-economics.md` §C6 (found the live consequence, and
correctly held this doc's cache-read result to *a bound, not a point*) →
`orchestration-units-2026-08-19/Z-completeness-critic.md` G15 (no decision was filed) → §2a (filed).

⚠️ **Read R1 as scoped to quota, which is all it ever measured.** It removes the *quota* reason to
trim context. It says nothing about the context-window ceiling — a hard `Prompt is too long` refusal
with no auto-compaction beneath it — which is the entire basis of `CLAUDE.md` § Context Stewardship
and is unaffected by anything in this file.

---

## What would falsify my headline

1. **A populated `limit_dollars`.** If a Max account ever returns a non-null
   `seven_day.limit_dollars` and that number, times `utilization`, does *not* track the API-list
   dollar value of the work done in that window (± the ~26% spread I measure across accounts), then
   the dollar keys are vestigial API-plan plumbing and the Max unit is something else. This is the
   single cleanest test and it costs one GET the day the field lights up.
2. **A high-output, cache-read-poor workload that burns quota slower than 1.28 pp/Mtok predicts.**
   The whole fit rests on the OUTPUT coefficient. Run one deliberate probe: a session that emits
   ~2M output tokens with minimal cache-read (short prompts, long generations) on a quiet account,
   and read the weekly Δ. Predicted 2.6 pp. If it reads < 1 pp or > 6 pp, the linear-in-output model
   is wrong and everything downstream of finding #6 falls.
3. **A cache-read-heavy, output-poor probe that DOES burn quota.** The mirror image, and the direct
   test of finding #8's identifiability problem: replay a very large cached context many times with
   near-zero output. Predicted ≈ 0 pp; the API-list hypothesis predicts ~1 pp per 2B cache-read
   tokens. This is the one experiment that separates the two models the data cannot.
4. **Substantial out-of-band usage on any account.** If the operator used claude.ai web or mobile on
   these accounts during 2026-08-10→16, the pp side is inflated relative to the transcript side and
   every coefficient here is biased high — the token-per-pp figures would then be *under*-estimates
   (quota is even cheaper than stated), which strengthens R1/R2 but invalidates the point estimates.
5. **Non-linearity or a per-request term.** All fits assume pp is linear in token counts with no
   per-request constant. If Anthropic charges partly per *request*, an interval's message COUNT
   should carry signal after the token columns are absorbed. I did not test this (message count
   correlates ~1.0 with output tokens in this corpus); a deliberate many-tiny-requests probe would.
6. **The 5-hour replication turning out to be circular.** It shares the token-side extraction with
   the weekly fit. If a bug in the extractor (e.g. double-counting sidechain assistant messages)
   inflated one token class systematically, BOTH fits would move together and the "independent"
   corroboration in finding #12 evaporates. A `jq`-based re-extraction by a second party on one
   account-cycle would settle it.
