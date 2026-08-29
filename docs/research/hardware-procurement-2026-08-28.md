---
status: measured
date: 2026-08-28
---

# What hardware, if any, addresses the ~15-session ceiling — and the recommendation this wave refuted

**Question (operator):** *"What hardware spec changes would address our bottlenecks? More RAM?
More CPU? None of the above?"* — then, on the used market: *"how about arbitrage finding second
hand?"*

**Verdict in one line: no single spec fixes it, RAM is the only one buying a real physical limit,
and the used-market arbitrage this wave initially recommended DOES NOT EXIST IN SUPPLY** — a
9-metro sweep found zero M1 Ultra 128GB machines and priced the one M1 Ultra on the market
(64GB) at $5,500, roughly double what a search-engine summary had claimed for a *128GB* unit.

⚠️ **Every price here rots.** Apple refreshed both relevant lines on 2026-08-25 and DRAM pricing
is moving. Treat §3–§4 as a dated snapshot, not a standing recommendation. §1–§2 are the durable
part, because they are derived from this repo's own measurements rather than from the market.

---

## 1 · The spec ranking, derived from our measurements

**RAM > CPU cores > storage > GPU**, and the gaps between them are large.

| Spec | What it buys | Evidence |
|---|---|---|
| **RAM** | The **crash** axis, roughly linearly. `vm.compressor_segment_limit` × `vm.compressor_segment_buffer_size` = 1,629,609 × 64 KiB = **99.5 GiB nominal on a 64 GiB box — 1.55× RAM**. Exhaustion arrives at ~28% mean fill, so effective burst headroom is **27.8 GiB = 0.43× RAM**. 128GB roughly doubles it. | Read live 2026-08-27; mechanism in `session-capacity-ceiling-2026-08-09.md` §11 |
| **CPU cores** | The **admission threshold** only — `CC_HW_DEFAULT_MAX_LOAD_PER_CORE × ncpu`. That constant was never derived (see §2), so cores buy permission to open more sessions, not a resource. | `capacity-admit.sh:134`; `gc-cpu-vs-session-ceiling-2026-08-18.md` §3 |
| **Storage** | Capacity headroom only, never throughput. Darwin's load average counts **runnable threads, never disk-wait** (`sched_run_buckets[TH_BUCKET_RUN]`), so disk I/O is structurally invisible to the gating number. A faster SSD fills a full segment table faster. | `session-capacity-ceiling-2026-08-09.md` §2.2 |
| **GPU** | **Nothing, today.** iTerm2 disables Metal at **≥6 panes/tab** (`cmp x8, #0x6`, disassembled), measured **361 legacy CPU-rasterizer frames vs 72 Metal** at ~42 panes. The GPU is already idle; more cores receive no more work. Fixing panes-per-tab is free and strictly dominates buying GPU. | `gpu-vs-cpu-lag-2026-07-29.md` §2 |

**The single-core caveat, because it is the one CPU lever that is real.** Load is
`occupancy = concurrency × duration`, and more cores do not shorten how long a fork holds a
slot — faster cores do. Fork cost is `fork+exec` → dyld → sandbox eval → code-signing, which is
mostly kernel time bound by the **memory subsystem and TLB**, not ALU throughput. So a
generational jump helps, sub-linearly against its headline number, and **core count within a
generation buys none of it**. ⚠️ Darwin schedules background-QoS work on **E-cores**, so before
paying for faster P-cores, check which band the fleet's daemons and hooks actually run in
(`nice` alone does not demote — only `taskpolicy -c background` reaches the background band).

## 2 · Why "buy hardware" is the wrong frame at all

Three facts, each independently sufficient:

1. **What the gate measures is not our fleet.** `claude.exe` is **4.7%** of the load-average
   numerator (1.075 of 22.95 runnable threads), replicated by an independently written parser.
   A fresh sampler run on 2026-08-27 (n=81, 27.6 min) put the Claude-owned share at **15.2%**
   of runnable and measured `corr(load1, census) = 0.181` — the census barely tracks the load
   it apportions. Deleting 100% of Claude's threads removes ~5% of the number that refuses
   sessions.
2. **The wall is a constant nobody derived.** `CC_HW_DEFAULT_MAX_LOAD_PER_CORE = 2.0` cites a
   section that falsifies itself; the origin commit measured 2.72/core and picked 2.0 with no
   stated rule. It cannot separate the fatal 2026-08-05 reading (**2.53/core**) from 13
   consecutive survived samples at **2.92–5.98/core**. 47% of gated fires already run with the
   gate off. More cores raise `ncpu × 2.0` — i.e. admit more sessions into a box that already
   feels bad.
3. **The progressive degradation is residue, and residue is per-machine.** Measured live
   2026-08-27: **788 of 1,147 processes orphaned to PID 1** with the fleet near-idle and load
   21.82 — already above the load-20 ceiling. Each orphaned `ps` walk slows every other through
   shared kernel **proc-table contention**, and `cc-reaper` — the relief — bound-fires at 90s
   under exactly that load. That compounds, which is why it presents as a slope rather than a
   wall, and **more cores means more contenders on one lock**. A 2× machine reaches the same
   state in 2× the time: the signature of a leak, not a capacity shortage.

**Corollary: the unit to buy is an independent KERNEL, not GB or cores.** Compressor segments,
proc-table contention and orphan accumulation are all per-machine limits.

⚠️ **And the cheapest kernel is off-box, which is already built.** `session-capacity-ceiling-2026-08-09.md`
§5 says "zero off-box sessions have ever executed; `git ls-remote` returns exactly one head" —
**that was 18 days stale**. Measured 2026-08-27: **239 remote heads, 236 of them `claude/fire-*`**.
And `cloud-local-cost-ab-2026-08-11.md` measured cloud at **≈0.81× local** price-weighted, with
zero local CPU, RAM or fork traffic. Saturating that lane dominates every purchase below.

## 3 · THE REFUTED RECOMMENDATION — record it, because the reasoning was sound and the premise was not

**This wave first recommended a used M1 Ultra Mac Studio with 128GB at ~$2,700**, on the argument
that the compressor segment table scales with *physical RAM, not chip generation* — so an old
high-RAM Mac is functionally equivalent on the crash axis at a fraction of the price. **The
argument still holds. The supply does not.**

A 3-agent Craigslist sweep across 9 metros (LA · Orange County · San Diego · SF Bay · Seattle ·
Portland · New York · Austin · Dallas) found:

| Spec | Price | Where |
|---|---|---|
| M3 Ultra 256GB / 1TB | **$7,500** | Oakland |
| M3 Ultra 256GB / 1TB | $8,500–$8,900 | San Jose, Oakland |
| M3 Ultra 256GB / 2TB | $9,500 | San Jose, Pasadena |
| M3 Ultra 512GB | $20,000–$21,999 | SF, Beverly Hills |
| **M1 Ultra 64GB** | **$5,500** | Menlo Park |
| M4 Max 64GB / 1TB | $3,200 | Tustin |
| M2 Max 64GB / 1TB | $2,800 | Brooklyn |

**Zero M1 Ultra 128GB listings in any metro.** The sub-$3,500 used tier tops out at **64GB** —
what an M1 Max desk already has, so it buys a kernel and zero crash headroom. The first genuine
128GB+ machine is $7,500.

**Where the bad number came from, and the lesson.** The $2,623–$2,991 figures were taken from a
**search-engine summary of eBay**, never from reading eBay. They could not have been verified by
content: eBay's **sold** listings now redirect to `signin.ebay.com`, and its **active** listings
serve a `splashui/challenge` bot wall — both measured with `agent-browser` 0.27.1. A summary of a
source is not a reading of the source, and a purchase recommendation was built on one.

## 4 · Marketplace reachability, measured 2026-08-28

| Marketplace | Result | Path |
|---|---|---|
| **Craigslist** | ✅ readable via `WebFetch`; per-metro URLs, trivially parallel | note the 301 `sfbay.craigslist.org/search/sya` → `craigslist.org/search/area/sfbay?cat=sya` |
| **FB Marketplace** | ⚠️ logged-out view returned listings, reliability unknown, **scam-bait prices mixed in** | deep path needs the operator's logged-in browser (CDP) |
| **eBay sold** | ❌ sign-in wall | operator session required |
| **eBay active** | ❌ bot challenge | operator session required |

**Three sweep caveats that generalise beyond this task.** (a) Austin returned page chrome with no
result rows — an **unreliable null**, not a confirmed zero; a blind instrument's null is not
absence. (b) The query was `cat=sya` + "mac studio", so a **Mac Pro** listing omitting that phrase
could never appear — the zero Mac Pro count is a property of the query, not the market. (c) Specs
were read from titles only, and titles are adversarial: one listing read "M4 Max 512GB/36Gb",
where 512GB is the SSD and 36GB the RAM, which scans as a 64GB+ hit.

## 5 · What this leaves

- **Buy nothing to fix concurrency.** Saturate the off-box lane first — it costs the box zero and
  measured cheaper than local.
- **If a box is bought anyway, buy kernels, not GB.** Two Mac mini M6 (12-core, 32GB, $899 each =
  **$1,798**) beat one 18-core M5 Pro/64GB (**$1,899**) on the axis that binds, *provided nothing
  on them runs a cold compile* — measured storms hit **38.9 GB and 44.7 GB**, straight through 32GB.
  A single box that must do everything wants the 64GB ceiling, i.e. M5 Pro.
- **A MacBook Pro is a desk replacement, not capacity.** M5 Max is the only chip reaching 128GB
  (M5 Pro caps at 64GB — a lateral move from an M1 Max). Never buy one as a *worker*: it always
  drives a display, and it thermally throttles under exactly the sustained load a fleet generates.
- **NOT open — `CC_HW_DEFAULT_MAX_LOAD_PER_CORE` is underivable on this axis, and that is settled on
  trunk.** This bullet used to read *"still wants deriving (backlog `e981656df348`, held by a live
  off-box worker)"*. That prescription is disproved, not merely unfinished: load-per-core cannot
  separate fatal from survived — fatal 2026-08-05 at **2.53/core** against **13 consecutive survived
  samples spanning 2.92–5.98/core** (`scripts/capacity-alarm.sh` rung-7 header, *executable*: 5.98 is
  pinned in its selftest as a known false ALARM) — so there is no measured failure point to set a
  ceiling from. Independently, `fix(fire-gate): load1 does not move with the spawn it was gating`
  established that an additional **resident** session moves the 1-min runnable count by ~0: the INPUT
  is wrong, not the value, so no setting of the literal can make the term correct. The load term
  therefore `DEFAULT`s **off** in `capacity_gate()` and the literal stays at 2.0 deliberately (C18 — a
  fix moves a term switch, never a ceiling; raising it is the design
  `docs/plans/LOAD_INSENSITIVE_VERIFY_V2.md:156` exists to reject). Both cures are on trunk: the
  falsified `§9.5` citation in `scripts/lib/capacity-admit.sh` (landed in `b5553505`) and the
  disproved §3 prescription itself (`951d4e82`). Full account, and the standing rule it leaves —
  *strike a remedy in the same edit as the evidence that kills it* —
  `docs/research/gc-cpu-vs-session-ceiling-2026-08-18.md` §3.
  ⚠️ **The stated blocker was a misattribution.** This item was never gated on the marginal-load
  measurement: that coefficient (backlog `193ae8ddce72`) denominates `CC_ADMIT_ACTIVE_CEILING`, a
  per-**active-session** population, not this per-**core** literal — and its own §6a records that even
  the active ceiling is *"not blocked on §6"*. Running it would not have discharged this row.
- **Still genuinely open (a different constant):** `scripts/capacity-marginal.sh` returned
  **NO-ATTRIBUTION** on a 27.6-minute quiet-box window — C1 LEVEL and C2 DYNAMICS both failed, and it
  correctly withheld the 0.846 fit that would otherwise have become a fifth value in the 30×-span
  family. That is the `CC_ADMIT_ACTIVE_CEILING` axis (`193ae8ddce72`), and it is unaffected by the
  paragraph above.
