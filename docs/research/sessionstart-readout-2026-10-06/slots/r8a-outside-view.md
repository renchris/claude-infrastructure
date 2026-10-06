# R8a — outside view: how other meters word a coarse reading near a cap

Slot: web research (read-only). Written 2026-10-06. Every row cites a URL; local figures name the command.

## 0. What our own source does and does not promise (question d)

- **Anthropic does not publish the `anthropic-ratelimit-unified-*` headers.** The official rate-limit page lists only `retry-after`, `anthropic-ratelimit-{requests,tokens,input-tokens,output-tokens}-{limit,remaining,reset}` and the priority-tier set; no `unified`, `utilization`, `allowed_warning` or `surpassed-threshold` appears (https://platform.claude.com/docs/en/api/rate-limits, fetched 2026-10-06). The same page says the documented limits "represent maximum allowed usage, not guaranteed minimums" and that token `remaining` is "rounded to the nearest thousand". So Anthropic's own documented convention is coarse remaining plus no guarantee.
- **What is known about the unified headers comes from public bug reports, not from docs:**
  - Names and an example in Claude Code issue #12829: `-status`, `-5h-status`, `-5h-reset` (epoch), `-5h-utilization`, `-7d-*`, `-representative-claim`, `-fallback-percentage`, `-reset`, `-overage-disabled-reason`. Utilization there was a full float, `0.7370692663445869` (https://github.com/anthropics/claude-code/issues/12829, reset epoch 1764554400 = 2025-12-01).
  - Claude Code issue mirrors say `allowed_warning` has two sources. The **server** sends it when it also sends `anthropic-ratelimit-unified-<claim>-surpassed-threshold`. The **client** derives it from a pace table, `utilization >= X && elapsedPct <= T` (7d: 0.75/0.60, 0.50/0.35, 0.25/0.15; 5h: 0.90/0.72) (https://claudeissues.com/issue/72495-bug-prompt-suggestions-silently-suppressed-whenever-the-client-derived-rate-limi). The weekly banner reads "You've used NN% of your weekly limit - resets in Xd" and fires at the 75% surpassed-threshold (https://claudeissues.com/issue/72994-feature-configurable-threshold-or-opt-out-for-the-recurring-weekly-limit-usage-w).
  - These are third-party mirrors of Claude Code issues, so treat them as reverse-engineered evidence, not a spec.
  - **Implication (reasoned):** `allowed_warning` means "past a warning threshold (≈75%), not refused at this response". It carries no nearness-to-100 information beyond the utilization figure. Reading it as "still accepts work" overstates it.
- **Measured, the server now quantizes:**
  - Every logged `wire_7d_util` has at most two decimals: 2068 values, 174 with two decimals and 1894 with one (python scan of `~/.claude/logs/account-utilization.jsonl`).
  - `_wire_float` stores `float(h[name])` without rounding (`bin/claude-accounts`, `def _wire_float`). The quantization is therefore server-side and new since the Dec-2025 full-float example. Whether it rounds or truncates is R2's question.
- **Measured: time in the top band on next3** (same log; first-seen per value):
  - `0.98` was first seen at 01:56:31Z (k=15).
  - `0.99` was first seen at 03:08:26Z (k=15).
  - The first `1.0 rejected` row was at 06:08:11Z (k=9). The user-visible refusal came at 06:03:04Z.
  - **The account sat at `0.99 allowed_warning` for about 2 h 54 min** (03:08:26 to 06:03:04), across 12 consecutive identical reads. The 5h meter moved 2 to 7 over the same span.
  - So a two-decimal "0.99" says nothing about whether the account is at minute 1 or minute 170 of the last point. The time since entering the band is the only fresh-looking field that carries that information.

## 1. Survey table (questions a, b)

| Product / system | What it shows near the cap | Precision | How it shows age / freshness | Projects time-to-limit? | URL |
|---|---|---|---|---|---|
| Anthropic API (documented headers) | `*-remaining` count, `*-reset` time, `retry-after` on 429 | Tokens "rounded to the nearest thousand"; limits are "not guaranteed minimums" | None; each value is as of that response | No; reset time only | https://platform.claude.com/docs/en/api/rate-limits |
| Anthropic unified headers (undocumented) | `*-utilization` float, `*-status` allowed / allowed_warning / rejected, surpassed-threshold | Full float in Dec 2025; ≤2 decimals now (measured, §0) | None; as of that response | No; `*-reset` epoch only | https://github.com/anthropics/claude-code/issues/12829 |
| Claude Code client banner | "You've used NN% of your weekly limit - resets in Xd"; pace-table warning | Integer % | None | No; reset countdown only | https://claudeissues.com/issue/72994-feature-configurable-threshold-or-opt-out-for-the-recurring-weekly-limit-usage-w |
| GitHub REST API | `x-ratelimit-remaining` reaches `0`, then "do not retry until `x-ratelimit-reset`" | Integer requests | Per-response headers are "authoritative" over `GET /rate_limit` when the two disagree; secondary limits: "There is not a way to check the status" | No; reset epoch | https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api , https://docs.github.com/en/rest/rate-limit/rate-limit |
| OpenAI API | `x-ratelimit-remaining-*`, `x-ratelimit-reset-*` as a duration (`6m0s`), `Retry-After` | Integer | Per response; Retry-After is "the minimum ... treat this value as a minimum" | Only "resets in" duration | https://developers.openai.com/api/docs/guides/rate-limits |
| IETF RateLimit fields (draft-11, 2026-05-23) | `RateLimit: "default";r=50;t=30` | Server-chosen; "MAY be approximated" | Values are "the server's view at response time" | `t` = window remaining, not exhaustion | https://datatracker.ietf.org/doc/draft-ietf-httpapi-ratelimit-headers/ |
| IETF draft, client duty | "Clients MUST NOT assume that a positive available quota is a guarantee that further requests will be served"; with shared quotas, clients "should not assume quota will be available" | n/a | n/a | n/a | same |
| Cloudflare API | IETF `Ratelimit`/`Ratelimit-Policy`; `retry-after` "rounded up" | Integer, rounded toward caution | Per response | No | https://developers.cloudflare.com/changelog/2025-09-03-rate-limiting-improvement |
| Stripe | No remaining headers at all; only a 429 with `Stripe-Rate-Limited-Reason`; advises a client-side token bucket | None shown before the wall | n/a | No | https://docs.stripe.com/rate-limits |
| GCP Quotas console | "Current usage percentage"; per-minute quotas show "the average per minute usage in the past 10 minutes" | % column | Window definition stated; no data-age stamp | No | https://docs.cloud.google.com/docs/quota/view-manage |
| AWS Service Quotas + CloudWatch | Utilization `m1/SERVICE_QUOTA(m1)*100`; threshold alarms | % | Metric period (CloudWatch) | No | https://docs.aws.amazon.com/servicequotas/latest/userguide/configure-cloudwatch.html , https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-Service-Quota-Integration.html |
| AWS Budgets | Actual vs **forecasted** alerts (for example at 80%) | Currency | "updated up to three times a day ... 8–12 hours after the previous update"; "You might incur additional costs or usage that exceed your budget notification threshold before AWS Budgets can notify you" | Yes: a separate "forecasted" alert, labelled as forecast | https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-managing-costs.html |
| AT&T usage (phone data) | Usage vs allowance | GB | "It can take two to five days for data use to post ... amounts shown online may not reflect all usage" | No | https://www.att.com/support/article/wireless/KM1009269 |
| GM distance-to-empty | Shows **"LOW"** instead of miles below about 35 mi | Number withdrawn near empty | n/a | Withdrawn near empty | https://gmauthority.com/blog/2025/06/poll-should-gm-redesign-its-distance-to-empty-gauge/ |
| Tesla range | Shows 0 mi with an undisclosed buffer; Tesla: "the buffer cannot be defined exactly to a number every time"; Edmunds drove 11 / 17.5 mi past zero | Miles, biased low | n/a | Range itself is the projection, biased conservative | https://www.news4jax.com/business/2021/03/31/edmunds-puts-teslas-range-to-the-test/ |
| Aircraft fuel gauge (legacy 14 CFR 23.1337(b)(1)) | Must read **zero** in level flight when only *unusable* fuel remains | Calibrated to the usable boundary | n/a | No | https://americanflyers.com/?p=9719 |
| macOS 10.12.2 battery | **Removed** "time remaining"; Apple: "the percentage is accurate, but ... the time remaining indicator couldn't accurately keep up" | % kept, ETA dropped | n/a | Removed because it was unreliable | https://techcrunch.com/2016/12/13/macos-sierra-update-fixes-macbook-pros-graphics-issues-removes-time-remaining-estimate-following-battery-life-complaints |
| iPhone battery | % shown, yet "more likely to experience unexpected shutdowns when your battery has a low state of charge" | Integer % | n/a | No | https://support.apple.com/en-us/101575 |
| Dexcom G7 CGM | Shows **LOW** below 40 and **HIGH** above 400 mg/dL instead of a number; "If you don't have a number, or you don't have an arrow, use your BG meter to treat" | Number withdrawn outside the trusted range | 5-min cadence; Signal Loss alert when readings stop | Trend arrow = rate, not ETA | Dexcom G7 User Guide (third-party host), pdftotext lines 1410-1430, 6248-6251: https://medicalserviceco.com/uploads/userfiles/files/documents/G7%20user%20guide.pdf |
| Nightscout (CGM follower) | Value plus "N min ago"; stale **warn at 15 min**, **urgent at 30 min** without a reading | mg/dL | Age is first-class and alarms escalate with it | No | https://nightscout.readthedocs.io/en/latest/nightscout/setup_variables.html |

### Cross-cutting findings
- **No surveyed cloud quota UI promises headroom.**
  - Each states the value as of a response (GitHub, OpenAI, IETF, Cloudflare) or with an explicit lag (AWS Budgets, AT&T).
  - Two say outright that a positive remaining is not a promise: the IETF draft's "MUST NOT assume" and Anthropic's own "not guaranteed minimums".
  - Stripe shows nothing before the wall at all.
- **Physical gauges near empty withdraw the number or bias it toward caution:**
  - GM shows "LOW".
  - Tesla's 0 hides a buffer.
  - The FAA zero sits at the usable boundary.
  - Dexcom shows LOW/HIGH.
  - Apple dropped the ETA.
  - None of them reports a precise last 1%.
- **Age is printed where data is pulled or lags (Nightscout, AWS Budgets, carriers) and omitted where every response carries fresh headers (GitHub, OpenAI).** Our board is the first kind: a snapshot read every ~6 min, shared by 11 to 15 sessions. So the outside view says to print the age.
- **Downgrading by age:** only Nightscout escalates on age (15 min warn, 30 min urgent). No surveyed product keeps a present-tense claim ("accepts work") on stale data. Carriers and AWS Budgets attach a standing disclaimer instead.
- **Projection:**
  - The products that project (AWS Budgets forecast, car range) label it as a forecast or bias it low.
  - Apple removed its projection when it could not keep up.
  - No surveyed product projects time-to-exhaustion as a point estimate near the cap.

## 2. HCI / dashboard guidance (question c)
- **Spurious precision.** Values with uncertainty should not carry "too many significant digits"; spurious digits are "meaningless digits" (https://data.europa.eu/apps/data-visualisation-guide/number-rounding). A two-decimal source (0.99) supports at most "99%"; "99.0%" adds a digit the source never sent.
- **Visibility of system status:** "keep users informed about what is going on, through appropriate feedback within reasonable time". When state changes through time passing, explain it "in brief but understandable terms" (https://www.nngroup.com/articles/visibility-system-status/). This supports carrying the read's age in the same line as the claim.
- **Uncertainty for everyday decisions.** Kay, Kola, Hullman, Munson (CHI 2016): users "may not grasp that such predictions are subject to uncertainty". Discrete outcome displays (quantile dotplots) improved estimates, and in the 2018 follow-up, decisions (https://idl.uw.edu/papers/when-ish-is-my-bus). For a one-line terminal, the transferable part is to state a bound or band rather than a point.
- **Bound notation is established practice:**
  - Dexcom LOW/HIGH (out of measurable range).
  - Cloudflare's "rounded up" retry-after (rounding toward caution).
  - Anthropic's "rounded to the nearest thousand" remaining.
  - Our own board already prints "≥99%" for the unconfirmed state (`bin/claude-accounts`, comment above `NEAR_WALL_RGB`).

## 3. Wording patterns for a one-line terminal board (ranked)

Constraints carried in: the three wall states stay inline in the percent column and bar; only a server-confirmed refusal prints "100%"; the hook stays a file read.

1. **Lower bound in the percent column, no decimal from a two-decimal source.** Print `≥99%` (or `99%+`), never `99.0%`/`99.6%`. Precedents: Dexcom LOW/HIGH, data.europa.eu on spurious digits, Anthropic "rounded to nearest thousand".
   - Our states need distinct text without colour. Proposed: nearly-out = `≥99%` with the orange sliver bar; unconfirmed (endpoint integer only) = `≥99%?` or `~100%` gray.
   - That frees `≥99%` from today's "not confirmed" meaning; the other option is to keep `≥99%` for unconfirmed and use `99%+` for nearly-out.
   - Conviction 85% on "no tenths"; 55% on which glyph pair.
2. **Replace present tense with "as of" plus age plus load in the same line.** Example: `next3 ≥99%  not refused at 06:01 (1m ago) · 11 sessions on it`. Precedents: the IETF "server's view at response time", GitHub per-response authority, Nightscout "N min ago", NN/g. Never "still accepts work". Conviction 85%.
3. **Withdraw the headroom number at the wall, as GM's "LOW" and Apple's dropped ETA do.** Drop "about 1% of the week left, roughly 5% of one 5-hour window". Print `last <1% (amount unknown)` or nothing.
   - Measured: next3 sat at 0.99 for about 2 h 54 min, so the true headroom at any 0.99 read is anywhere in [0, 1pp).
   - Printing the upper end as "about 1%" is what over-promised.
   - Conviction 80%.
4. **Time in band instead of headroom: `≥99% since 03:08 (2h53m)`.** A long dwell at the last point is the honest hint that the account is near the end. Precedent: Nightscout makes age first-class.
   - It needs the producer to keep a first-seen timestamp per wire value. That is producer-side and zero-token, and the hook still only reads a file.
   - Conviction 55%. One account-incident (next3 2026-10-06) is the whole evidence; R3 should check the dwell spread.
5. **Downgrade by age (Nightscout's 15 / 30 min ladder).**
   - When the wire read is older than about one sweep plus margin (for example > 10 min), drop "not refused at HH:MM" and render the unconfirmed state.
   - When k is large, shorten the threshold.
   - Conviction 60%; the thresholds are unmeasured (R3/R4).
6. **Projection only as a labelled trend, never a point ETA.** Keep "⚠ WALL trajectory" or "1.04× burn" as the rate cue (Dexcom arrow, AWS "forecasted"). Do not print "~N min left" from a two-decimal source (Apple removed exactly that). Conviction 70%.

Worked one-liner combining 1+2+3 (estimated width ~70 cols):
`next3  ≥99%  ▮▮▮▮▮▮▮▮▮▯  not refused at 06:01 (1m ago), 11 sessions — route new work elsewhere`

## 4. Alternatives considered and rejected
- **`99.0%` / `99.6%` (current).** Rejected: it adds a digit the server never sent (§0 measured ≤2 decimals) and contradicts every surveyed near-empty gauge.
- **`<1% left` as the main text.** Rejected as the column text: the column is "used %" and the 2026-10-03 ruling puts the state there. Acceptable in the note.
- **A point ETA ("~3 min left") from burn rate.** Rejected per Apple 10.12.2 and the 2h54m dwell (rate × coarse level gives a meaningless ETA).
- **Showing nothing until 429, as Stripe does.** Rejected: it loses the 1pp the 2026-10-01 ruling values (~5% of a 5h window per the `K_FROZEN` comment in `bin/claude-accounts`).

## 5. Blockers / caveats
- `allowed_warning` semantics are reverse-engineered from issue mirrors (claudeissues.com), not documented by Anthropic.
- The GM 35-mi figure is from trade press, and the Tesla buffer quote is from syndicated AP/Edmunds coverage.
- The Dexcom guide text is from a third-party PDF host.
- The FAA cite is the legacy (pre-2017 rewrite) Part 23 text, via a flight-school article.
- The zero-cost rejection signal on disk (second half of plan row R8) is outside this slot and was not researched here.
