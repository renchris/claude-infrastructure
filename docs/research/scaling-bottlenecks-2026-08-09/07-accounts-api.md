# 07 · Account / API capacity at 150 resident, ~10 active

**Verdict.** Account capacity does **not** bind the 150-**RESIDENT** half of the design point — a
resident session blocked on the API draws ~zero quota, exactly as §S6.2 assumes. It binds hard on
the **~10-ACTIVE** half: four Max accounts sustain **~4 concurrent active sessions 24/7**, not 10.
Ten active is a *burst* the fleet can afford ~**65 h/week** (39% of wall-clock). And before either
of those, a **local router constant refuses the 33rd session**: `router.KMAX = 8` × 4 accounts = 32
resident, proven end-to-end below. Fix KMAX first; then re-size "~10 active" to a duty cycle.

Measured on this box, 2026-08-09/10. Every number is either a live tool read, a transcript
measurement, or an executed predicate. Inferred claims are labelled INFERRED.

---

## 1 · Live per-account state — `claude-accounts --readout` (verbatim)

Run read-only with `--no-heal` (the default path calls `claude auth login` to refresh a stale
token — an account mutation, out of scope; `bin/claude-accounts:382-420`). Rendering is unaffected.

| account | live | 5h used | 5h resets | weekly used | Fable used | weekly resets | login expires |
|---|---|---|---|---|---|---|---|
| next | 1 | 4% | Mon 02:20 (in 3.1h) | 11% | 0% | Sat 21:00 (in 5d 21h) | Sun Aug 30 08:03 (in 20d 8h) |
| **next4** ➤ | 1 | 10% | Mon 02:19 (in 3.1h) | 5% | 0% | Sun Aug 16 01:59 (in 6d 2h) | Sun Aug 30 08:36 (in 20d 9h) |
| **next3** ➤ᶠ ← you | 5 | 22% | Mon 00:19 (in 1.1h) | 60% | 14% | Tue 04:59 (in 1d 5h) | Thu Sep 03 10:27 (in 24d 11h) |
| next2 | 2 | 6% | Mon 03:00 (in 3.7h) | 10% | 0% | Sat 04:00 (in 5d 4h) | Mon Sep 07 04:28 (in 28d 5h) |

➤ general → **next4** · ➤ fable → **next3**
Fable window: **permanent** (no expiry).

9 live sessions, all four `auth: ok`, all four `cliff_band: none`, `credits_on: false` everywhere
(`--json --no-heal`). **Weekly resets are already well staggered** — Sat / Sun / Tue / Sat — which
is a capacity asset (§6.6); nothing should align them.

### How the tool derives "remaining"

- Percentages are **not locally computed**. `fetch_usage()` GETs
  `https://api.anthropic.com/api/oauth/usage` with the OAuth bearer + `anthropic-beta:
  oauth-2025-04-20` (`bin/claude-accounts:349-357`; endpoint from `~/.claude/accounts.json`), and
  `pick(u,"session"|"weekly_all"|"weekly_scoped")` reads the vendor's own `limits[].utilization`
  and `resets_at` (`:846-853`). **The vendor tells us the percentage; we never see the cap.** That
  is why §2 has to calibrate.
- A `429` from that endpoint is classified as a **poll throttle, never a cap** — "a real
  weekly/5h/Fable cap returns HTTP 200 with percent≈100" (`:828-836`).
- Cache: 90 s TTL, single-flight, `/tmp/claude-accounts-cache.json`; 600 s grace on lock-degrade.

---

## 2 · Quota arithmetic — calibrating tokens against the vendor's own %

The caps are unpublished, so the only honest route is to measure **our** token stream inside each
account's current window and divide by the utilization the vendor reports for that same window.
Two independent methods; they agree.

🚨 **A measurement defect found and fixed mid-analysis.** Claude Code writes **one JSONL line per
content block** of an assistant message, each carrying the **same** `message.usage`. Summing
per-line double-counts by ~2.1× (measured: 508 usage records → 237 unique `message.id`, all dupes
byte-identical). Everything below is **deduped on `message.id`**. The first pass, un-deduped, put
the weekly cap at $9.3K/week — 2.3× too high.

### 2a · Cost-equivalent method

API-equivalent $ at list price (Opus 5 $5/$25, Fable 5 $10/$50, Sonnet 5 $3/$15, Haiku $1/$5;
cache-write 1.25×, cache-read 0.10×), summed over each account's **current** weekly and 5h window.

| account | wk % used | wk $eq | **$eq per 1% wk** | 5h % | 5h $eq | **$eq per 1% 5h** |
|---|---|---|---|---|---|---|
| next  | 11 | 427.43 | 38.86 | 4  | 32.64  | 8.16 |
| next4 | 5  | 226.96 | 45.39 | 10 | 61.47  | 6.15 |
| next3 | 60 | 2184.71 | 36.41 | 22 | 139.53 | 6.34 |
| next2 | 10 | 407.44 | 40.74 | 6  | 36.94  | 6.16 |

**Weekly: mean 40.4 $eq per 1%, spread [36.4, 45.4] — ±11% across four independent accounts.**
⇒ one account's weekly cap ≈ **$4,035 API-equivalent/week**; 5h cap ≈ **$670** (`next`'s 8.16 is
the 4%-denominator outlier — quantisation; the other three sit in [6.15, 6.34]).

Raw-token weighting fits *worse* (Mtok per 1% weekly: 53.7 / 67.7 / 49.1 / 57.1, ±16%), so
cost-weighting is the better model — but only weakly discriminated, because 86% of the corpus is
Opus cache-read. **INFERRED**, and §2b is built to not depend on it.

### 2b · Pricing-free method (the invariant)

The dollar unit cancels: any weighting linear in the same token counts gives the same
*hours-per-percent*. So measure **ACTIVE session-hours** directly — active time = sum of
inter-turn gaps ≤ 300 s, deduped, inside each account's live weekly window.

| account | wk % used | active hours burnt | **active-h per 1%** | ⇒ 100% | sessions | window elapsed |
|---|---|---|---|---|---|---|
| next  | 11 | 15.2 | 1.38 | 138 h | 31  | 26.4 h |
| next4 | 5  | 8.5  | 1.69 | 169 h | 17  | 21.4 h |
| next3 | 60 | 83.0 | 1.38 | 138 h | 195 | 138.4 h |
| next2 | 10 | 20.8 | 2.08 | 208 h | 37  | 43.4 h |

**Mean 1.64 active-h per 1% ⇒ ~164 ACTIVE session-hours per account per week.**

### 2c · The structural fact: weekly ≈ 6 five-hour caps

$4,035 / $670 = **6.0 five-hour caps per week**, against **33.6** five-hour blocks in a week.
**The weekly cap permits an 18% full-rate duty cycle.** The 5h cap is a burst governor; the weekly
cap is the budget. Any policy that optimises the 5h number is optimising the wrong one.

---

## 3 · Demand model — what one ACTIVE session costs

114 sessions sampled (deduped, ≥0.15 active-h, gap ≤300 s), newest 150 transcript files:

| metric | median | p75 | p90 | max |
|---|---|---|---|---|
| **$eq per ACTIVE hour** | **22.7** | 28.5 | 34.5 | 47.9 |
| turns per active hour | 151 | — | — | — |
| duty cycle (active / wall-span) | 0.83 | — | — | — |
| per-turn context (in+cw+cr) | 199,628 tok | — | — | — |

**Cost composition: cache-read 68.0% · cache-write 18.0% · output 14.0% · fresh input 0.0%.**
~~This is the single most actionable number in the file — see §6.4.~~

> 🚨 **STRUCK (ruled 2026-08-24, swept here 2026-08-28) — this composition is the refuted premise,
> and it is not a quota measurement.** It is an **API-list-price weighting of our own token counts**
> (§2a's rates, cache-read at the 0.10× multiplier), i.e. what the stream *would* cost at list — not
> what it draws against the Max weekly limit, which is the quantity §6.4 spent it on. The 2026-08-16
> meter experiment measured that draw directly: Opus-5 **cache-read = 0.000 pp/Mtok**, output 1.282,
> cache-creation 0.105. Against the meter the composition inverts — **output is what costs** — and
> the "halving context" lever built on this line is dead (§6.4; ruling at
> `../scaling-bottlenecks-2026-08-09.md` **§2a**). Even taking the API-list hypothesis at face value,
> the realised cycle puts cache-read at **~28%** of dollar cost, not 68%. The **usable** residue of
> this line is its last term: *fresh input 0.0%* — the fleet re-reads rather than re-sends, which is
> the fact that makes long contexts cheap, and it was read here as if it made them expensive.

Model mix by $eq this weekly window: `next` opus 426 / sonnet 1.5 · `next4` opus 227 · `next3`
opus 2104 / **fable 80.5** / haiku 0.0 · `next2` opus 406 / fable 1.0 / haiku 0.3. Effectively an
all-Opus fleet.

---

## 4 · Duty-cycle model — how many ACTIVE sessions 4 accounts sustain

4 × 164 = **654 active session-hours/week** (cross-check via §2a: 4 × $4,035 / $22.7 = **711 h**;
the two routes agree within 9%).

| operating window | sustained concurrent **ACTIVE** |
|---|---|
| 24/7 (168 h/wk) | **3.9** |
| 12 h/day (84 h/wk) | 7.8 |
| 40 h/wk | 16.4 |
| **hours/week the fleet can hold 10 active** | **65 h — 39% of the week** |

At p90 demand ($34.5/active-h) the 24/7 figure falls to **2.8**.

**Resident sessions are free, and that is measured, not assumed.** next3 burnt 83 active-hours over
a 138 h window while carrying 5 resident sessions ⇒ **~12% active duty per resident session**.
Project that: 150 resident at 12% duty = 18 active = 4.6× the sustainable rate. Holding the design
point's ~10 active 24/7 needs **2.4× more weekly quota than four Max accounts carry**.

**⇒ The "~10 ACTIVE" half of §S6.2 does not survive as a steady state.** It survives as a burst
with a duty cycle attached. Restate the design point as *150 resident · ≤10 active · ≤65 active-hours
per week fleet-wide*, or add accounts (§6.2).

---

## 5 · Server-side caps

### 5a · What the vendor documents

- **Nothing numeric for subscription plans.** `support.claude.com/en/articles/11145838` says only
  that "Pro and Max plans offer usage limits that are shared across Claude and Claude Code" and
  points at `/status`. **No 5h number, no weekly number, no concurrent-session cap.**
  (fetched 2026-08-09)
- **No documented per-account concurrent-session or concurrent-request cap anywhere.** The API
  rate-limit page (`platform.claude.com/docs/en/api/rate-limits`, fetched 2026-08-09) has RPM /
  ITPM / OTPM and a Batches queue depth — **no concurrency limiter of any kind**. This confirms
  §S6's "docs state no numeric per-account concurrent cloud-session cap" and upgrades it from
  UNVERIFIED to *verified-absent-from-docs* (absence of a documented cap ≠ absence of a cap —
  see 5c).
- **Cache reads are exempt from ITPM.** "For most Claude models, only uncached input tokens count
  toward your ITPM rate limits… `cache_read_input_tokens` ✗ **Do NOT count**." Same page. This is
  why Claude Code sessions are rate-limit-cheap and quota-expensive: the 5h/weekly quota **does**
  bill cache reads (at 0.1×, and they are 68% of our cost), while the per-minute limiter ignores
  them entirely.
- Start-tier Opus 5 reference limits: **1,000 RPM / 2,000,000 ITPM / 400,000 OTPM**. Opus 5 has its
  own bucket, separate from Opus 4.x. Fable 5 is much tighter (500K ITPM / 100K OTPM at Start).
- Third-party figures ("Max 20x = 24-40 Opus hours/week") are **not comparable** to §2b's 164 h and
  should not be used to contradict it: they are cache-cold single-session estimates, pre-date the
  2026-05-06 5h doubling, and are not calibrated to these accounts. §2b is calibrated against these
  four accounts' own live utilization readings.

### 5b · Measured per-minute headroom (110 active sessions sampled)

| per active session | median | p90 | max |
|---|---|---|---|
| requests/min | 3 | 3 | 5 |
| **uncached input tok/min** (what ITPM counts) | 9,889 | 19,441 | 40,382 |
| output tok/min | 2,357 | 3,398 | 4,031 |
| cache-read tok/min (ITPM-exempt) | 483,813 | 788,627 | 1,239,798 |

Against Start-tier Opus 5 caps:

| concurrent ACTIVE | RPM | ITPM | OTPM |
|---|---|---|---|
| 4 | 1.0% | 2.0% | 2.4% |
| **10 (design point)** | **2.5%** | **4.9%** | **5.9%** |
| 32 | 8.0% | 15.8% | 18.9% |
| 150 | 37.7% | 74.2% | **88.4% (p90: 127%)** |

**Per-minute rate limits do not bind at the design point.** OTPM is the first to go and only at
~150 *simultaneously active* sessions — a state this design explicitly never enters.

### 5c · What the fleet has ACTUALLY hit (`isApiErrorMessage:true`, all 4 accounts, full history)

| error | events | distinct days |
|---|---|---|
| **529 Overloaded** | **114** | 6 |
| 500 Internal server error | 38 | 2 |
| 401 OAuth access token has expired | 35 | 2 |
| Fable 5 safety-flag refusals | 30 | 7+ |
| Response stalled mid-stream | 14 | 5 |
| ECONNRESET / ENOTFOUND | 19 | 7 |
| **"Server is temporarily limiting requests (not your usage limit)"** | **10** | **1** |
| "Claude usage limit reached" (a real quota cap) | **0** | — |

Two findings:

1. **The fleet has never once hit a subscription quota cap.** Zero `Claude usage limit reached` in
   the entire local corpus. Quota has been abundant *at the concurrency the fleet has actually run*
   (9-14 sessions), which is exactly what §4 predicts — ~12% duty on ~10 residents is ~1.2 active.
2. **The infrastructure limiter is real but rare and non-chronic**: 10 events, 2 sessions, one
   47-minute burst on next3 on 2026-07-21, and nothing since. Same string that
   `anthropics/claude-code#62426` (opened 2026-05-26, closed, no staff reply) reports at **5-6
   concurrent Claude Code instances on the highest paid tier** — the same band as this fleet's own
   "5-6 per account is deliberate operator practice" (`accounts.json:router._`).
   **529 Overloaded is 11× more common and is the capacity signal that actually shapes the fleet.**
   Neither is quota; both are retryable; neither is a documented cap.

---

## 6 · The wall that actually binds first — and the routing policy

### 6.1 · 🚨 `KMAX = 8` refuses the 33rd session. This is the binding constraint, and it is ours.

`~/.claude/accounts.json` → `router.KMAX: 8`. `_excluded()` returns `kmax-concurrency` the moment
an account's live session count `k >= KMAX` (`bin/claude-accounts:1036-1037`), which zeroes
`score_general` **and** `score_fable`. Executing the real predicate against a live row:

```
k=  0 -> 0.006335   k=  7 -> 0.000792
k=  4 -> 0.003167   k=  8 -> None  reason=kmax-concurrency   (and 9, 20, 38)
```

End-to-end, executing the shipped binary (control = real config; probe = KMAX lowered to 1 so the
live k of 1/1/5/2 puts every account at its cap; isolated cache, no mutation):

```
CONTROL  --route general → next4                                                  rc=0
PROBE    --route general → "no routable account for general:
           next=kmax-concurrency; next4=kmax-concurrency;
           next3=kmax-concurrency; next2=kmax-concurrency"   → none               rc=2
```

`kmax-concurrency` classifies as **policy**, not data (`DATA_UNAVAILABLE` excludes it), so it exits
**2**, and `scripts/handoff-fire.sh:5266-5269` turns rc 2 into `return 1` — *"the caller HALTS
rather than firing blind."* The cliff-yield in `ranked()` does **not** rescue this: it re-ranks only
when `CLIFF_DRAIN_REASON` emptied the set.

**⇒ 4 accounts × KMAX 8 = 32 resident sessions, fleet-wide, then dispatch stops.** The 150-resident
design point breaks at **32 — 4.7× early**, on one integer in one JSON file, on the path CLAUDE.md
makes the *default* execution locus (dispatched handoff sessions). Consumers of the router:
`scripts/handoff-fire.sh`, `scripts/route-safety-gate.sh`, `bin/cc-offload`.

`k` counts **resident** sessions (`concurrency()`, `ps -wwEo command=` keyed on
`CLAUDE_CONFIG_DIR`, `:281-326`) — not active ones. So KMAX is currently a resident cap wearing an
active-cap's name.

### 6.2 · Policy — the two caps must be split

KMAX conflates two different scarcities and can serve neither. Split them:

| gate | governs | value now | value for 150-resident | why |
|---|---|---|---|---|
| **`KMAX`** (resident) | how many sessions may *exist* per account | 8 | **≥ 40** (`ceil(150/4)` + headroom) | residency costs ~0 quota (§4); the only real resident costs are local (render/pty/RAM), owned by §S6.7 |
| **NEW: active-concurrency gate** | how many sessions may be *mid-turn* per account | — | **5** | the measured infra-limiter band (§5c) and GH#62426's 5-6 |
| **NEW: weekly-hours budget** | active-hours/week fleet-wide | — | **≤ 654 h** (≈ 65 h at 10 active) | §4; this is the actual scarce resource |

Sizing the fleet from the target instead: sustaining **10 active 24/7** needs 1,680 active-h/week ÷
164 = **≈ 10 Max accounts**, not 4. Four accounts sustain 4.

### 6.3 · Sessions-per-account split

Even after raising KMAX, **do not split 150 evenly.** `score_general` already ranks on
`w_rem / horizon × SF × KF × cliff` and spreads by `KF = clamp(1 - k/KMAX, 0.1, 1)` — a soft
gradient that keeps working at any KMAX. Keep it and let it place sessions. Two operator-level
constraints on top:

- **Fable stays pinned to ONE account** (next3 today). `frontier.coupling = 0.5` — the Fable
  sub-cap is 50% of that account's *weekly* cap — and Fable bills 2×, so a Fable active-hour costs
  ~2 general active-hours of weekly budget. Spreading Fable across four accounts strands general
  capacity on all four instead of one. next3 is already the Fable route and already carries the
  weekly draw (60%); that concentration is correct, not a problem.
- **Never realign the weekly resets.** Sat / Sun / Tue / Sat means at most one account is deep in
  its window at a time, which is what lets `score_general`'s `w_rem / horizon` term shift load. A
  relogin or account rebuild that clusters the resets would convert four independent budgets into
  one synchronized one.

### 6.4 · ~~The largest quota lever is context, not accounts~~ 🚨 REFUTED — this section is the ORIGIN of the struck lever

> 🚨 **STRUCK (ruled 2026-08-24, swept here 2026-08-28). This section is where "halving context ≈ +50% active capacity" was
> generated**, and it propagated from here into `scaling-bottlenecks-2026-08-09.md:36` (rank 4) and
> its standing-policy list, into `jcode-due-diligence-2026-08-11.md` and that wave's
> `bottleneck-audit.md` / `ranked-levers.md`, and into
> `memory-econ-rearchitecture-2026-08-10/prior-art.md` row 55. **Every one of those is now struck.**
> The premise below was a **composition model over token counts**, never a meter reading. The
> 2026-08-16 direct experiment measured the exchange rate instead: Opus-5 **cache-read = 0.000
> pp/Mtok** (p95 ≤ 0.0017 over ≥590M tokens; NNLS over 265 ≥2h intervals / 4 accounts, R²=0.82,
> replicated on the disjoint 5-hour bucket). Quota is spent by what a session **emits** — output
> 1.282 pp/Mtok, cache-creation 0.105 — **not** by what it re-reads. The halving lever is worth
> **0%** under the measured fit and **≤+16%** under the API-list alternative (which puts cache-read
> at ~28% of dollar cost, not 68%), and even that is an upper bound because halving the window does
> not halve cache-creation. **Never +50%.** Ruling: `../scaling-bottlenecks-2026-08-09.md` **§2a**;
> measurement: `../usage-telemetry-100p-2026-08-16/exchange-rate.md` finding 8 / R1.
>
> **What this does NOT touch.** (a) `CLAUDE.md` § Context Stewardship is argued from the hard
> `Prompt is too long` ceiling and decision rot, never from quota — grep confirms the 68% figure
> never reached it — so recycle discipline stands, on its own grounds. (b) The **model down-tier**
> lever below is priced per *output* token, which is the class the meter says actually costs, so it
> survives this correction intact and is now the largest unspent quota lever in this section.

~~**68% of every quota dollar is cache-read**, and cache-read scales linearly with per-turn context
(median **199,628 tokens**). Halving working context ≈ **−34% quota draw ≈ +50% sustainable active
sessions** — a bigger multiplier than a fifth account (+25%). CLAUDE.md § Context Stewardship's
recycle thresholds are therefore a **capacity policy**, not only a quality policy, and `/handoff`
at 35% idle fill is worth real active-hours.~~ Second lever, **unaffected and now the leading one**:
**model down-tier**. Sonnet 5 is 0.6× Opus
per token (1.67× the active-hours); Haiku 4.5 is 0.2× (5×). The fleet is ~99% Opus by $eq today,
so this lever is entirely unspent.

### 6.5 · Fail-open directions to watch (both currently safe)

- `concurrency()` returns **all-zero counts** on `ps` timeout (`:294-295`). That fails **open** in
  two directions at once: KMAX stops binding, *and* `heal()`'s rotation-safety gate (`k_live > 0`)
  reads 0 and may redeem a refresh token underneath live sessions → logout. **Not currently at
  risk**: measured 118,665 B / 72 lines / **67-95 ms** at 10 sessions, ~5.3 KB argv+env per session,
  Python parse 0.5 ms ⇒ ~865 KB and well under 1 s at 150, against a 10 s timeout. ~10× headroom,
  but it is the one place where scaling the fleet silently disarms an auth safety gate. Worth a
  cheap assertion, not a redesign.
- The 90 s single-flight cache is what keeps 150 sessions from stampeding
  `/api/oauth/usage`. **`~/.claude/statusline.sh` does not call `claude-accounts`** (mentions are
  comments only) — checked, because a statusline caller would multiply by 150 × render rate.

---

## 7 · Adversarial pass — what I got wrong or nearly missed

1. **My own arithmetic was 2.1× too high** until I found the per-content-block duplicate
   `message.usage` records. Caught by auditing one file for duplicate `message.id`. Every figure
   above is post-fix. *(This is the finding most likely to recur in any other transcript analysis
   in this series.)*
2. **"Published Max limits contradict you."** They appear to (24-40 Opus h/wk vs my 164). Named
   rather than buried: the published figures are uncalibrated third-party estimates for cache-cold
   single-session use and predate the 2026-05-06 doubling; §2b is calibrated against these exact
   accounts' live utilization by two independent methods that agree within 9%. If the vendor's
   accounting is *not* linear in these token counts, §2b's hours figure moves — that is the one
   assumption that would change the verdict.
3. **Under-count risk, direction named.** Transcripts capture local sessions only. If cloud
   sessions (`bin/cc-cloud`) draw the same account quota without writing a local transcript, active-h
   per 1% is biased **low** ⇒ true capacity is **higher** than §4 states, never lower. Checked for a
   separate cloud transcript store and found none; `.claude-next/projects` is a **symlink** to
   `.claude/projects` and was deduped (an un-deduped glob double-counts account `next`).
4. **Hypothesis refuted, worth recording:** I expected `ps -wwEo` in `concurrency()` to blow its
   10 s timeout at 150 sessions. Measured — it does not (§6.5). The scaling risk there is the
   fail-open *direction*, not the budget.
5. **Axis I nearly assumed irrelevant:** per-minute rate limits. They are irrelevant *at the design
   point* (§5b) — but only because cache reads are ITPM-exempt while ~~being 68% of quota cost~~
   **carrying essentially the whole context volume** *(corrected 2026-08-24 — §6.4; cache-read is
   0.000 pp/Mtok on the weekly limit, not 68% of it)*. That
   asymmetry is the reason quota and rate-limits give opposite answers, and it is the single fact
   that makes 150 resident affordable at all — **and the correction strengthens this item rather
   than weakening it**: cache reads turn out to be exempt from the per-minute limit *and* ~free on
   the weekly one, so residency is cheaper than this section assumed, not dearer.

---

## 8 · Wall ordering (this file's terms, against §S6.1's)

| # | wall | binds at | axis | owner |
|---|---|---|---|---|
| 1 | **`router.KMAX = 8`** | **32 resident** | resident | **this file — one integer, local** |
| 2 | weekly quota, 24/7 | **~4 active sustained** | active | this file |
| 3 | render | ~140 panes | resident | §S6.7 |
| 4 | 5h quota (burst) | ~24 active for one 5h block | active | this file |
| 5 | ptys | ~509 | resident | §S6.7 (corrected census) |
| 6 | OTPM | ~150 active | active | vendor |

Quota never appears before position 2, and never on the resident axis at all.

---

### Provenance
`claude-accounts --readout --no-heal` · `--json --no-heal` · `--route general` (control + KMAX=1
probe, isolated cache) · `~/.claude/accounts.json` · `bin/claude-accounts:281-326, 349-357,
382-420, 828-853, 1030-1090, 1123-1139, 2186-2400` · `scripts/handoff-fire.sh:5244-5269` ·
4,079 local transcripts across `~/.claude{,-secondary,-tertiary,-quaternary}/projects`,
deduped on `message.id` · `platform.claude.com/docs/en/api/rate-limits` ·
`support.claude.com/en/articles/11145838` · `github.com/anthropics/claude-code/issues/62426`.
All web sources fetched 2026-08-09.
