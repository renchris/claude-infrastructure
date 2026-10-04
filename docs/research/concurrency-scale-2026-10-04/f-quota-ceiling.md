# How far $200 Max accounts stretch: concurrent-agent ceiling (2026-10-04)

**Answer.** Quota is already the limit on today's fleet, and it stays the limit at every scale up to 1000 agents.

- **Measured burn.** One agent that generates without pause draws about **1.2 weekly-pp per hour** (range 1.07–1.30). An agent kept at the fleet's real duty cycle draws about **0.17 pp per hour**. The duty cycle is in-flight API time over session wall time, about 14%.
- **What one account sustains.** A $200 Max account holds 100 pp per 168 h, or **0.595 pp/h**. That covers about **3.5 concurrently-open agents at today's duty cycle**, **about 1 continuously-working worker**, or **about 0.5 always-generating streams**.
- **1000 concurrent agents** need between **about 290 accounts ($57K/month)** and **about 2,000 accounts ($400K/month)**. The answer depends on which of those three "agent" definitions the operator means (§4).
- **Today's 4 accounts are saturated.** All 14 weekly windows since 2026-09-12 closed at 100%. Over the last 28 days, next and next2 sat walled 21% and 26% of the time. All this happened at a time-averaged **20 open / 5 busy / 2.6 generating agents** fleet-wide.
- **Throttling is not a factor at our fan-out.** Every rate_limit error in 30 days of transcripts was a quota wall. Retry time was 0.31% of API time.

Labels: **MEASURED** means read from a tool or log this run. **INFERRED** means derived arithmetic or a cross-model scaling. Scratch scripts and data are in `/tmp/concurrency-scale/fq/` (`burn.py`, `cs.py`, `util.py`, `an3.py`, `an4.py`).

---

## 0 · Live readout (MEASURED, `claude-accounts --readout --no-heal --no-agents`, 2026-10-04 ~06:40Z)

| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| next | 1 | 0% | — | 0% | 0% | Sat Oct 10 23:00 (in 6d 21h) | Wed Oct 21 23:12 (in 17d 21h) |
| **next4** ➤ᵍ ← you | 18 | 55% | Sun 04:39 (in 3.0h) | 62% | 6% | Sun 03:59 (in 2.3h) | Thu 05:42 (in 4d 3h) |
| **next3** ➤ | 3 | 2% | Sun 05:09 (in 3.5h) | 39% | 3% | Tue 06:59 (in 2d 5h) | Sat Oct 24 11:38 (in 20d 9h) |
| next2 | 0 | 0% | Sun 03:39 (in 2.0h) | 0% | 0% | Sat Oct 10 05:59 (in 6d 4h) | Sat Oct 31 06:33 (in 27d 4h) |

next and next2 read 0% because their weeks reset on Oct 3 and Oct 4. Both closed the previous window at 100%; see §3.

Read-only status: `--no-heal` skips the token refresh. `cc-quota-price` and `desk-strand-replay.py` only read logs and transcripts.

## 1 · Calibration: weekly-pp to tokens to agent-hours (MEASURED)

Method. The numerator is quota burned: the sum of positive steps of `weekly_pct` per account in `~/.claude/logs/account-utilization.jsonl`, using non-stale rows. The denominator is what the agents did, taken from Claude Code's own per-session `cost-state` records (last record per sessionId, sessions started in the window). Those records carry true output for subagents as well. Transcripts do not: 76.5% of subagent responses on 2.1.284 never write a final record. Over 7 days, transcripts held 54.8M output tokens against 157.3M in `cost-state`, a 2.9× under-read. Cache-creation agrees between the two to within 2% (835M against 854M), which shows the `cost-state` sum is not double-counting.

| window | weekly pp burned (4 accts) | 5h pp burned | 5h:weekly | output (cost-state) | cache_creation | API in-flight hours | session wall-hours | **pp per API-hour** | **pp per wall-hour** | output-equiv tokens per weekly pp ¹ |
|---|---|---|---|---|---|---|---|---|---|---|
| 7d | 534 | 2,073 | 3.88 | 157.3M | 854M | 500 | 3,420 | **1.07** | **0.156** | 464K |
| 14d | 934 | 3,806 | 4.07 | 225.1M | 1,410M | 716 | 5,146 | **1.30** | **0.181** | 401K |
| 28d ² | 1,741 | 7,619 | 4.38 | 347.0M | 2,184M | 1,125 | 8,401 | 1.55 | 0.207 | 332K |

¹ Output-equivalent = output + cache_creation × 360/3400. That weighting comes from the repo's price list (`docs/plans/USAGE_TELEMETRY_100P.md:149-152`). Cache reads cost about 0 (§2.8 there).

² The 28-day row mixes in Opus 5 (35% of output) and Fable 5.1, which draws 3.2–3.7× per token. It is not used for the Opus 5.5 rate.

- Model mix, 7 days, from `cost-state` (MEASURED): Opus 5.5 is 97% of output. By effort, from transcripts: high 63%, xhigh 26%, medium 7% of output-equivalent tokens. **So the calibration is effectively an Opus 5.5 calibration.**
- Per API-hour, `cost-state` gives **315K output + 1.7M cache_creation** tokens. That matches the main-session output rate measured in transcripts, 87–94 tok/s during generation (`an4.py`), and the 107 tok/s measured for Opus 5.5 in `docs/research/sonnet55-utilization-2026-09-28/notes/probe-quota-draw.md`.
- Cross-check against the shipped tool. `cc-quota-price --since 14d` returned R² 0.870 and **481,928 output / 1 pp, 3,394,189 cache_creation / 1 pp**, with an 80% Opus 5.5 mix (MEASURED). Its output coefficient reads transcript output, so it inherits the subagent under-read. That makes it an upper bound on tokens per pp. The direction is consistent with the table.
- Census (MEASURED, `cc-quota-price --census --since 7d`): 175,609 billed responses; 54.6M output; 833M cache_creation; 30.6B cache_read; 58.3% repeat records deduped.
- **One account-week ≈ 29M output + 160M cache_creation tokens** at the 7-day mix. That agrees with the plan's "≈26–36M Opus-5 output tokens per account-week" (`USAGE_TELEMETRY_100P.md:156`).

## 2 · Burn table (answers question a)

The meter cannot isolate effort or model in the fleet data, so the effort and model rows scale the measured Opus 5.5 rate by measured relative factors. Rows marked INFERRED are derived that way.

| model · effort | weekly pp per **generating** hour | weekly pp per **open-agent** hour at fleet duty (×0.14) | % of one account's week per generating hour | per-task output (review class, median) | basis |
|---|---|---|---|---|---|
| **Opus 5.5 · fleet mix (63% high)** | **1.2** (1.07–1.30) | **0.17** (0.156–0.181) | **1.2%** | — | **MEASURED** (§1) |
| Opus 5.5 · medium | ~1.35 | ~0.19 | 1.35% | 6.3K tok (0.44× high) | INFERRED: main-session tokens per generating hour, medium 627K : high 554K = 1.13× (`an4.py`). Per-task figure from the effort sweep |
| Opus 5.5 · high | ~1.2 | ~0.17 | 1.2% | 14.5K | MEASURED (dominant class) |
| Opus 5.5 · xhigh | ~1.0 | ~0.14 | 1.0% | 36.5K (2.5×) | INFERRED: 468K/554K = 0.84× per hour; ~2.5× per task |
| Opus 5.5 · max | ~1.0 | ~0.14 | 1.0% | 106K (7.3×); 2/9 cells hit the 128K cap | INFERRED, as above |
| Sonnet 5.5 · high | ~0.95 | ~0.13 | 0.95% | 15.1K | INFERRED: 0.62× Opus 5.5 per output token on the 5h meter, bound [0.49, 0.76] (MEASURED in the probe note), × 135/107 tok/s throughput |
| Haiku 4.5 | ~0.3–0.6 | ~0.05–0.08 | 0.3–0.6% | — | INFERRED, low conviction: list ratio 0.25× Opus 5.5, and Sonnet's measured skew is 1.24× its list. No Haiku draw or throughput measurement exists in the repo |
| Fable 5.1 · high | ~4.2 | ~0.6 | 4.2%, **capped at 50 pp/acct/week** | — | INFERRED: 3.2–3.7× Opus 5 per token (`fable51-vs-opus5-routing-2026-09-16/V-quota.md` §What survives). Opus 5.5 ≈ Opus 5 within [0.78, 1.72] |

**Effort barely moves the hourly burn.** A generating stream is limited by output throughput (about 90 tok/s), so the burn per generating hour is almost flat across effort. Effort changes how many generating hours a task takes, which is 0.44× to 7.3× the tokens per task. For a concurrency budget, the variable that matters is duty cycle, not effort. Effort shows up as throughput (tasks per pp), not as capacity (agents per account).

**The Fable sub-cap** allows at most 50 pp per account per week, which is about 12 Fable generating-hours per account-week. Fable cannot be the bulk tier at any scale.

## 3 · Duty cycle (answers question b; MEASURED)

| population | n | in-flight / wall | busy / wall (gap <5 min) | source |
|---|---|---|---|---|
| main sessions, pooled over wall-hours | 1,261 | **0.13–0.15** (API-h / session wall-h, 7–28d) | — | `cost-state` totalAPIDuration / totalDuration |
| main sessions, per-session distribution | 1,261 | p25 0.13 · **p50 0.41** · p75 0.67 · p90 0.85 | — | same (API time includes the session's parallel subagents) |
| main sessions, transcript (own turns only) | 447 Opus-high | pooled 0.03–0.04 · median 0.13 | pooled 0.10–0.12 · median 0.39 | `an1.py` |
| subagents | 5,946 files | **pooled 0.38–0.59 · median 0.67–0.77** | pooled 0.70–0.80 · median 1.00 | `an1.py`; median subagent life is 6–7 min |
| **fleet time-average, 7d (4 accts)** | — | **2.6 generating** | **5.0 busy** | **20.1 open** (16.3 main + 3.8 sub) |
| fleet peaks, 7d | — | generating per 1-min bin: p90 9.3 · p99 16 · max ~150 (single minute) | — | open per 10-min bin: p50 20 · p90 47 · p99 106 · max 213 |

The fleet runs at about 14% duty because most open panes are idle leads waiting on a human or on subagents. Subagents run at 50–75% duty. Whether the answer is "~290 accounts" or "~1,000 accounts" depends on that difference.

**Saturation at today's scale** (MEASURED, `scripts/desk-strand-replay.py` and `util.py 28`):

- 14 of 14 weekly windows from 2026-09-12 to 2026-10-04 reset at 100% used, with 0 pp stranded.
- Share of 28-day samples at weekly 100%: next 21%, next2 26%, next3 7%, next4 6%.
- So demand at roughly 20 open agents already exceeds 4 accounts. That makes the per-agent rates above **supply-rationed**. Unconstrained demand per agent can only be higher.

## 4 · Ceilings and accounts needed (answers question c)

**Ceilings per account (MEASURED):**

- **Weekly:** 100 pp per 168 h, which sustains **0.595 pp/h**.
- **5-hour window:** 100 5h-pp. The fleet exchange rate is 3.9–4.4 five-hour pp per weekly pp, so one full 5h window costs **about 23–25 weekly pp**. That allows a burst rate of about 4.6–4.9 weekly pp/h, **about 7.7× the sustainable weekly rate**. Pure `-p` output burns measured 5.4–5.8× (probe note; opus55 sweep), so the 5h window is tighter for output-heavy work.
- The week holds only about 4 full 5h windows' worth of burn. **The 5h limit binds bursts; the weekly limit binds anything that runs longer than about 20 hours of full burn per account per week.**

| per account | sustained (weekly-bound, 24/7) | burst (5h-bound, ≤5 h, then walled) |
|---|---|---|
| open agents at fleet duty (0.17 pp/h) | **~3.5** (3.3–3.8) | ~27–29 |
| busy workers, subagent-like (~0.6 pp/h) | **~1.0** | ~8 |
| always-generating streams (1.2 pp/h) | **~0.5** (0.46–0.56) | ~3.8–4.1 |

**Accounts and monthly cost for N concurrent agents, sustained 24/7** (INFERRED arithmetic on the MEASURED rates; $200 per account-month):

| N concurrent | **open agents at fleet duty (~14%)** | **busy workers (~50% duty)** | **always generating (100%)** | binding constraint |
|---|---|---|---|---|
| today (20 open avg) | 4 accts are over-subscribed: walled 6–26% of the time | — | — | **quota** (hardware gate ~12–15 local sessions also near) |
| **100** | **29 accts · $5.8K/mo** (26–30) | 101 · $20K | 202 · $40K (180–218) | **quota**. Hardware also needs off-box or multiple boxes: one local box caps at ~25–40 even after fork/headless levers ³ |
| **250** | **71 · $14K** (66–76) | 252 · $50K | 504 · $101K (450–546) | **quota** first; hardware second (≥7–10 boxes or off-box) ³ |
| **500** | **143 · $29K** (131–152) | 504 · $101K | 1,008 · $202K (899–1,092) | **quota** (dollars and account administration); hardware is a solvable scaling step |
| **1000** | **286 · $57K/mo** (262–304) | 1,008 · $202K | 2,017 · $403K (1,798–2,185) | **quota**, by 1–2 orders of magnitude in operational terms. Hundreds of logins, each with a ~monthly re-login cliff and a 5h/weekly window to route |

³ Hardware figures come from `docs/research/session-capacity-ceiling-2026-08-09.md:229-249`, cited rather than re-measured: local ceiling ~12–15 today and ~25–40 after fork-reduction and headless levers, with "150+ requires off-box". **Quota and hardware are both necessary.** Hardware costs a step per box. Quota costs a linear $200 per 3.5 open agents (or per 1 busy worker), and that recurring line dominates. At current duty, quota would stop binding before hardware only if per-agent burn fell about 10× (for example, Haiku-class bulk work) or if duty fell further.

**Two routes that change the numbers without breaking the no-API constraint.** INFERRED from §2: these are the only levers that move "accounts per agent", since effort mostly does not.

1. **Lower duty per open agent.** Idle panes cost almost nothing. Quota is driven by generating-hours, not by open sessions, so "1000 open agents" is far cheaper than "1000 working agents".
2. **A cheaper model tier for bulk slots.** Sonnet 5.5 is about 0.8× Opus 5.5 per hour, not 0.5×. Haiku is about 0.3–0.5× per hour, unmeasured.

## 5 · Concurrency throttling, 429s, overloaded (answers question d; MEASURED)

- **Transcripts, last 30 days** (13,550 files, `grep isApiErrorMessage`): 36× "You've hit your session limit" and 11× "You've hit your weekly limit". These are quota walls, not concurrency throttles. Also present: 1× **529 Overloaded** (2026-09-22T00:56Z), 1× 500, 7× DNS/connect errors, 3× Fable safeguard refusals, 6× version-gate 400s and 1× login expired. **No concurrency-type 429 was written.**
- **Silent retries** (`cost-state`, 7 days): totalAPIDuration 499.7 h against 498.1 h without retries, so **0.31% of API time was spent retrying**. The worst session spent 488 s retrying out of 31,120 s of API time.
- **Per-account parallelism observed without throttling.** Generating streams per minute per account: p99 10–13, max 17–20 (next2, next3, next4). The Sonnet quota probe ran 20 parallel streams on next4 with 0 errors. The opus55 sweep had 0× 429 on next4.
- **High fan-out hits the 5h wall, not a rate limiter.** A 92-slot Fable workflow on `next` consumed the whole 5h window in about 30 min, and 74 slots died on the limit (`docs/research/limit-cascade-2026-09-10.md:3-8,25-29`). The Fable sweep's 17 HTTP 429s were "5-hour limit mid-generation" (`fable51-effort-sweep-2026-09-10/README.md:57-60`). next3 once moved +41 5h-pp in 5 minutes.
- **The monitoring endpoint is a separate throttle.** `/api/oauth/usage` returned 1,764 `429 poll-throttled` lines (`~/.claude/logs/claude-accounts.log`). That endpoint is usage polling, not inference (`quota-429-drift-2026-09-30/README.md:5-7`). At hundreds of accounts it becomes a monitoring design problem.
- **Unmeasured:** behaviour above about 20 parallel streams on one account. Nothing in the repo tests 50–150 concurrent streams per account for a server-side concurrency cap. Under sustained-quota math one account cannot feed more than about 4 generating streams for 5 hours anyway, so a concurrency cap would only bind in sub-hour bursts.

## 6 · Vendor-published limits (WebSearch/WebFetch)

- The Max plan article ([support.claude.com/…/11049741-what-is-the-max-plan](https://support.claude.com/en/articles/11049741-what-is-the-max-plan), "updated over a week ago") says: *"Max 20x includes 20 times the Pro plan's per-session usage allowance."* It also says *"Your session-based usage limit will reset every five hours."*, *"Max plans also have a weekly usage limit that applies across all models. The weekly limit resets at a fixed time each week that is assigned to your account."*, and *"we may limit your usage in other ways, such as weekly and monthly caps or model and feature usage, at our discretion."* **The article publishes no token or hour numbers and does not address concurrency or multiple accounts.**
- [Use Claude Code with your Pro or Max plan](https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan) (updated 2026-08-19) says only that limits are "shared across Claude and Claude Code". It gives no numbers.
- Third-party, unverified: a May 6, 2026 doubling of 5h limits and a +50% weekly increase scheduled to expire July 13, 2026 "unless extended" ([verdent.ai](https://www.verdent.ai/guides/claude-code-limits-doubled-may-2026), [morphllm.com](https://www.morphllm.com/comparisons/claude-code-vs-codex)); a "~300 h weekly Opus 4.7" estimate ([superblocks](https://www.superblocks.com/blog/claude-code-pricing)). **These are not used.** The only trustworthy denominator is this fleet's own meter, and the vendor reserves the right to move it.

## 7 · Adversarial pass: gaps found and how each was closed

1. **The "/accounts understates spend" note.** I did not use point-in-time percentages. Burn is the sum of meter steps over whole windows, and every recent window closed at 100%, which bounds the total exactly. Being supply-rationed is the remaining bias, and it makes the per-agent rates lower bounds.
2. **Transcript output under-read (2.9×).** Found and closed by switching the denominator to `cost-state`, whose cache_creation agrees with transcripts to within 2%.
3. **Invisible consumption.** Cloud and claude.ai usage carries no local record (~28% historically, `USAGE_TELEMETRY_100P.md:154-156`). It inflates pp per local agent-hour, so the account counts here are conservative, possibly by up to ~1.4×. **Not separable** with local data.
4. **The 7d and 14d windows disagree** (1.07 against 1.30 pp/API-h). Reported as a range. 28 days was excluded because of the Opus 5 and Fable mix.
5. **Effort attribution.** Only main-session transcripts carry trustworthy output plus effort. Effort rows are relative factors (INFERRED), not metered.
6. **Haiku has no measurement.** Marked low conviction.
7. **5h exchange rate.** The fleet measures 3.9–4.4. Output-only probes measure 5.4–5.8. Burst ceilings for output-heavy work are about 25% lower than in the table.
8. **Not investigated:** whether the vendor permits or detects operating hundreds of Max accounts as one fleet. It is a policy question outside this brief, but it is the obvious non-quota blocker past roughly 10 accounts. The vendor's "at our discretion" clause applies.
