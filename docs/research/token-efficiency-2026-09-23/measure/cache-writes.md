# Cache writes: where the 1.25x / 2x writes come from

Window: 2026-09-09 to 2026-09-23 (14.96 days). Data: `data/extract.sqlite`, `xdup=0`, with the 7
`tokeff` experiment sessions excluded. Every dollar figure is a **list-price weight**. The fleet is
billed by subscription quota, not dollars. `own` = each response priced at its own model. `@5.5` =
the same tokens re-priced at Opus 5.5 ($4/MTok input, write 1.25x at 5m or 2x at 1h, read 0.05x).

Re-derive:

```
cd /tmp && nice -n 10 python3 <dir>/scripts/cache_walk.py
cd /tmp && nice -n 10 python3 <dir>/scripts/cache_writes_report.py
```

`cache_walk.py` writes `data/cache_walk.sqlite`, one classified row per response.
`cache_writes_report.py` writes `measure/cache-writes.json`, which holds every number below.

## Headline

1. **Rewrites are the largest class of write spend.** Out of $9,194 own / $6,892 @5.5 of cache
   writes, rewrites are 36% ($3,316 / $2,404), START 32% and INCREMENTAL 32% (MEASURED).
   - The biggest single cell is **main-thread rewrites after a gap of more than 1h**: 517 requests
     (0.6% of main requests) cost **$2,102 own / $1,528 @5.5**, 23% of all write spend.
   - Each one rewrites a mean **390k-token** prefix at 2x.
   - Writes @5.5 ($6.9k) are the same order as reads @5.5 ($8.2k).
2. **The 1h TTL on main threads is clearly net positive. Keep it.** Priced at uniform 5m (ESTIMATED
   replay), main threads would cost **+$3,547 own (+20%) / +$2,841 @5.5 (+31%)**.
   - The 1h premium ($1,924 / $1,444) buys $5,471 / $4,285 of avoided rewrites across 2,630
     hits that arrived after gaps of more than 5 min.
   - For agents the reverse holds: uniform 1h would add +$1,633 own / +$1,226 @5.5. Their 5m TTL is
     correct.
3. **What wakes a main thread after more than 1h** (@5.5, n=517):
   - operator prompts: $557
   - **self-armed inbox watchers (`cc-await-ping`) that time out with no mail: 116 wakes, $355**
   - slash commands, mostly `/limit-recover`: $201
   - foreground tool calls that return more than 1h later: $162
   - background commands finishing: $99
   - workflow or agent completions: $43

   A watcher wake that times out carries no information and still pays a full 2x rewrite. Setting
   the watcher term to 55 min or less saves about **$261 per 14 days @5.5** (ESTIMATED).
4. **Agent START writes: $1,760 own / $1,362 @5.5 per 14 days** (workflow $1,579 / $1,215; subagent
   $181 / $147).
   - Only 14.6% (workflow) and 7.0% (subagent) of the first-request prefix is served from cache.
   - 92% of a workflow agent's first message is shared setup (memory files, skill listing, deferred
     tools).
   - 2,075 of 2,400 workflow STARTs had a same-session, same-model sibling START in the previous
     5 min, so they could have read that setup from cache (upper-bound saving **$912 per 14 days
     @5.5**, ESTIMATED; see §6).

## 1. Method

Each file is one context. Responses are walked in `seq` order with
`prefix_i = input + cc_total + cache_read`. Zero-prefix responses (`<synthetic>`) are skipped. The
walk runs over xdup rows too, so the sequence stays continuous, but only `xdup=0` is aggregated.

| class | rule |
|---|---|
| START | the first response of the file (`seq=0`), i.e. its whole written prefix |
| START_TRUNC | the first in-window response of a file that straddles the window start; its predecessor is unknown |
| INCREMENTAL | `cache_read_i >= 0.9 x prefix_(i-1)`: the write is only the new content |
| REWRITE | anything else, sub-classed in priority order: `model_switch` (the previous response used another model) · `shrink` (prefix fell below 0.9x: compaction or context edit) · `gap_gt_1h` · `gap_5m_1h` · `gap_lt_5m` |

- **The 0.9 threshold is not a tuning choice.** The ratio `cache_read_i / prefix_(i-1)` is bimodal:
  there are 0 rows in [0.5, 0.9); 98.2% of non-START rows are in [0.99, 1.0] and 1.1% are above
  1.0, against 0.7% below 0.5 (MEASURED, 157,924 rows).
- **The gap** is the difference between the first-record timestamps of the two responses: a
  send-to-send proxy whose time-to-first-block latency roughly cancels.
- **The TTL model is validated empirically** (MEASURED, `hit_rate_by_gap_and_live_ttl`):

| context · live TTL | ≤ 240 s | 240-300 s | 300-360 s | 6-15 min | 15-55 min | 55-60 min | 60-65 min | > 65 min |
|---|---|---|---|---|---|---|---|---|
| main · 1h | 99.9% | 98.6% | 98.8% | 98.8% | 95.0% | 95.7% | **24.1%** | **2.4%** |
| workflow · 5m | 100% | 95.5% | **43.5%** | **5.6%** | 0% | 0% | 0% | 0% |
| subagent · 5m | 100% | 100% | 80% | 0% | 0% | – | – | 0% |

Hit rates fall exactly at the TTL boundaries, so the gap proxy is sound.

## 2. Writes by class × context (MEASURED)

Write $ (own / @5.5). Reads are shown for scale.

| class | main | subagent | workflow_agent | all | share of write $ (own) |
|---|---:|---:|---:|---:|---:|
| START (+TRUNC) | 1,067 / 843 | 193 / 157 | 1,692 / 1,300 | **2,952 / 2,301** | 32.1% |
| INCREMENTAL | 1,468 / 1,105 | 264 / 209 | 1,194 / 873 | **2,926 / 2,186** | 31.8% |
| REWRITE gap > 1h | **2,102 / 1,528** | 13 / 11 | 33 / 25 | **2,149 / 1,564** | 23.4% |
| REWRITE gap 5-60 min | 181 / 138 | 40 / 34 | **495 / 356** | 715 / 527 | 7.8% |
| REWRITE gap < 5 min | 154 / 124 | 6 / 5 | 107 / 51 | 267 / 180 | 2.9% |
| REWRITE model switch | 116 / 86 | 1 / 1 | 18 / 15 | 136 / 102 | 1.5% |
| REWRITE shrink | 44 / 28 | 6 / 3 | – | 49 / 31 | 0.5% |
| **all writes** | **5,132 / 3,852** | **523 / 420** | **3,539 / 2,620** | **9,194 / 6,892** | 100% |
| cache reads (for scale) | 12,793 / 5,444 | 1,143 / 502 | 5,070 / 2,245 | 19,006 / 8,190 | – |

- Write tokens: 608M at 5m and 481M at 1h. Main threads write 1h (only 0.4M of their writes are
  5m); agents write 5m only.
- Control: this total matches the extract headline (1h $5.1k + 5m $4.1k).

**Which class dominates:**

- **In main threads, long-gap rewrites.** They cost more than all main incremental writes put
  together, on 0.6% of the requests.
- **In workflow agents, START.** It is followed by incremental writes and by rewrites after tool
  calls that run 5-60 min.

**By model** (write $ own / @5.5, from `by_model_class`):

| model | writes | START | long-gap rewrites |
|---|---:|---:|---:|
| Opus 5 | $6.9k / $5.5k | $2,356 | $1,623 |
| Fable 5.1 | $1.55k / $0.62k | $305 | $432 |
| Opus 5.5 | $0.67k | $228 | $91 |

- Opus 5 carries 476 of the 552 long-gap rewrites (76% of their write $).
- Model-switch rewrites (45, $136) cluster on Opus 5.5 (17): the 2026-09-22 in-place upgrades.

## 3. Gap histogram per context (non-START responses, MEASURED)

Counts, with the misses and the write $ (own) those misses spent. "miss" includes model switches
and shrinks.

| context | < 5 min | 5-60 min | > 60 min |
|---|---|---|---|
| main | 79,305 (72 miss, $189) | 2,691 (80 miss, $268) | 546 (**527 miss, $2,140**) |
| subagent | 15,022 (8 miss, $10) | 45 (41 miss, $43) | 12 (12 miss, $13) |
| workflow_agent | 59,942 (41 miss, $124) | 338 (**300 miss, $496**) | 23 (23 miss, $33) |

## 4. TTL counterfactual (ESTIMATED)

**Method.** Replay each response's actual tokens under a uniform TTL.

- A real hit whose gap exceeds the new TTL becomes a rewrite of the whole prefix minus uncached
  input minus S. S is the file's first-request cache read (system + tools, shared across the fleet
  and assumed still warm).
- A real miss stays a miss at the new write multiplier.
- Under all-1h, a 5m-TTL `gap_5m_1h` miss becomes a hit.
- Output is unchanged and excluded.

| context | as-is | all-5m | all-1h | verdict |
|---|---|---|---|---|
| main (own) | $17,931 | $21,478 (**+$3,547, +19.8%**) | $17,932 | 1h is right |
| main @5.5 | $9,299 | $12,141 (**+$2,841, +30.6%**) | $9,301 | 1h is right |
| subagent @5.5 | $921 | $924 | $1,121 (+$200) | 5m is right |
| workflow_agent @5.5 | $4,866 | $4,915 | $5,892 (+$1,026) | 5m is right |

Main-thread decomposition (`ttl_1h_premium_vs_payoff_main`):

- The 1h premium (0.75x input on 481M 1h-write tokens) costs **$1,924 own / $1,444 @5.5**.
- It pays back **$5,471 / $4,285**.
- The payback comes from 2,630 hits with gaps over 5 min, each of which would otherwise be an 897M-token
  aggregate rewrite. The net return is 2.8-3.0x.
- On agents, 1h would convert only 339 misses into hits, and would put 0.75x on 608M tokens of writes.

## 5. Rewrites after more than 1h: what woke the session (MEASURED)

For each rewrite the classifier inspects the items between the previous response and this one: the
last user prompt or queued command, else the tool result or `continue`. Task-notification
`<summary>` text and `promptSource` are read from the raw record, for about 500 records.

**Main threads, gap > 1h, by wake family** (517 rewrites):

| wake family | n | write $ own | write $ @5.5 |
|---|---:|---:|---:|
| operator prompt (typed; includes keystroke-injected) | 174 | 746 | **557** |
| **self-armed inbox watcher (`cc-await-ping`)** | **116** | 469 | **355** |
| slash command (`/limit-recover` 41, `/are-we-done` 16, `/accounts` 10) | 68 | 341 | 201 |
| foreground tool call that returned after more than 1h | 68 | 215 | 162 |
| background command done (ship-land 13, test/gate 5, other 11, orphan after resume 7) | 36 | 123 | 99 |
| queued prompt | 16 | 55 | 46 |
| workflow or agent done | 17 | 62 | 43 |
| peer or teammate message | 11 | 39 | 28 |
| other task notification | 7 | 38 | 26 |
| none found | 4 | 14 | 12 |

- Of the 116 watcher wakes, **102 are `failed with exit code 2`**, which is `cc-await-ping`'s
  *timeout* exit: nothing arrived, the session woke, paid the rewrite and (typically) re-armed.
- Watcher wakes by gap:

  | gap | wakes | of which misses | write $ @5.5 |
  |---|---:|---:|---:|
  | 50-60 min | 7 | 0 | $0.07 |
  | **60-65 min** | 15 | 12 | $38 |
  | 1-2 h | 19 | 18 | $58 |
  | 2-4 h | 37 | 37 | $117 |
  | over 4 h | 49 | 49 | $142 |

  The 60-65 min cluster is the `--idle-scoped` default `--timeout 3600` (`bin/cc-await-ping:195`),
  which lands just past the 1h TTL. The over-4h cluster matches the `--timeout 14400` that the
  stand-down message recommends (`bin/cc-await-ping:365`).

**Machine sleep is not the cause.** `pmset -g log` (saved as `data/pmset_sleepwake.txt`) covers
2026-09-19 onward. It covers 183 of the long-gap rewrites: none was at least 50% asleep, 41 had some
sleep and 142 were fully awake. Most long gaps are idle panes on an awake machine.

**Ten sampled rewrites** (spread across the ranking, `long_gap_samples`):

| gap | prefix | write @5.5 | what woke it |
|---|---:|---:|---|
| 2.7 h | 961k | $7.48 | background command done (a scratch-dir script) |
| 2.6 h | 619k | $4.85 | typed prompt: "OPUS55-UPGRADE … relaunch THIS session in place" |
| 2.9 h | 511k | $4.08 | **"Arm inbox wake watcher" failed, exit 2** (watcher timeout) |
| 2.8 h | 487k | $3.65 | **"Re-arm the inbox watcher after its term expired with no ping" failed, exit 2** |
| 5.8 h | 386k | $3.09 | after a resume: "No completion record was found for this background shell command" |
| 9.6 h | 346k | $2.77 | operator: "Did you ping the lead agent?" |
| 6.6 h | 334k | $2.41 | workflow done: "Adversarial mutation verify of W2 …" |
| 4.6 h | 296k | $2.10 | operator: "Good to close?" |
| 1.3 h | 252k | $1.79 | background `ship-land.sh` finished |
| 2.1 h | 213k | $1.47 | "(Check for any updates)" |

**Agents, gap 5 min to 1h** (workflow $356 @5.5):

- 248 of 299 workflow rewrites and 27 of 40 subagent rewrites follow a **foreground Bash call that
  ran 5-60 min** (mean 14 min), for example `until [ -f … ]; do sleep …`, scratch-dir probe scripts,
  and gate runs.
- 42 follow a queued command.

**Rewrites after a gap under 5 min** (99, $267 own):

- main: `teammate_message` delivered (27, $50), `thinking_drop` attachment (5, $11), a session
  resumed or transplanted in the gap (4, $17), unexplained (28, $77)
- workflow: unexplained (30, $107)

These are small, and none is a TTL effect.

## 6. START writes (MEASURED; the shared-setup split is ESTIMATED)

| context | STARTs | mean first prefix | mean cache read | read share | 0-read share | START write $ per 14 d (own / @5.5) |
|---|---:|---:|---:|---:|---:|---|
| main | 978 | 123.9k | 21.1k | 17.0% | 12.0% | 944 / 746 |
| subagent | 359 | 94.1k | 6.6k | 7.0% | 27.0% | 181 / 147 |
| workflow_agent | 2,400 | 126.7k | 18.5k | 14.6% | 15.1% | 1,579 / 1,215 |

- An agent's cache read is only system + tools (about 18.5k). This is consistent with
  `measure/binary-and-cache.md`, which found a single message breakpoint on the last message and
  setup attachments ahead of the brief with no breakpoint after them.
- **Shared-setup estimate** (`start_shared_setup_agents`): in a workflow agent's first message,
  memory files + skill listing + deferred tools are **92.2%** of the visible characters (96.2% for
  subagents).
- 2,075 of 2,400 workflow STARTs (263 of 359 subagent STARTs) had a same-session, same-model sibling
  START in the previous 5 min.
- If that setup were cache-read (a breakpoint after the setup, with the setup ahead of the brief),
  the saving is **$974 per window, $912 per 14 days @5.5** for workflow agents and $99 per 14 days
  for subagents.
- This is an upper bound: the split is a character share applied to measured tokens, and it assumes
  byte-identical setup across siblings, which holds when they share a cwd.
- It **overlaps** with `omitClaudeMd` (`binary-and-cache.md`), which removes most of the same
  tokens. Do not add the two savings together.

## 7. Levers, ranked (ESTIMATED savings at Opus 5.5, per 14 days)

| # | lever | layer | saving | risk | category |
|---|---|---|---|---|---|
| 1 | Cache the shared agent setup across siblings: a breakpoint after the setup attachments, with the setup ahead of the brief | CC binary (request assembly) | ≤ $1,011 (workflow $912 + subagent $99); overlaps with omitClaudeMd | low | propose (upstream; not configurable here) |
| 2 | Idle keepalive for main threads: re-touch the cache every 55 min while idle, capped at H = 4 h | harness / binary | net ≥ $575 at one read per ping (saves $877, pings cost ≤ $263 per window; the idle-tail cost is an upper bound). At two reads per wake-turn (user-space, via a watcher) the net is ≥ $328 | low | propose |
| 3 | `cc-await-ping` term ≤ 3300 s: change the `--idle-scoped` default from 3600 to 3300 (already env-overridable via `CC_AWAIT_IDLE_TIMEOUT_S`) and the stand-down hint from `--timeout 14400` to a 55-min re-arm | harness script (`bin/cc-await-ping:195,365`) | **$261** (116 watcher misses become 474 hit-wakes at two reads each; conservative) | low: more re-look wakes, each a cheap hit | flag (env var exists), or direct for the constant |
| 4 | Agents do not block a foreground call longer than about 4.5 min: background it and poll in slices of 270 s or less (brief / workflow-authoring guidance) | subagent prompting | $214 (312 rewrites become 2,520 cheap polls) | low-medium: extra poll turns | flag |
| 5 | Keep 1h on main and 5m on agents; never force `ENABLE_PROMPT_CACHING_1H` onto agents | config | avoids +$1,226 (agents at 1h) and +$2,841 (main at 5m) | – | no change (verified) |
| 6 | Recycle before a long idle at high fill, so the wake rewrite is a fresh 124k START rather than 390k | behaviour | up to about $1.1k per window, but loses the context | high | propose; not recommended without a quality study |

Levers 2 and 3 overlap: the watcher term is the user-space subset of a keepalive.

## Gaps

- **Gap proxy:** it uses first-record timestamps and cannot see side requests that refresh the TTL
  (prompt suggestion, away summary; they are not in transcripts). 19 main hits after more than 1h
  are probably these.
- **Typed prompts:** keystroke-injected prompts (it2 send-text, handoff briefs) carry
  `promptSource=typed` like human input, so the "operator prompt" family is an upper bound on human
  returns.
- **Sleep coverage:** `pmset` history covers 2026-09-19 onward only (183 of 517 long-gap rewrites).
- **All-5m assumption:** the counterfactual assumes the shared system + tools block (S, about 16-21k)
  stays warm. Rewriting S as well would add about $265 @5.5 to the all-5m cost, which only
  strengthens the verdict.
- **Keepalive ping cost:** the ping cost for sessions that never wake is priced over the idle tail up
  to the data end, capped at H. Real sessions often close sooner, so that cost is an upper bound.
- **Output:** excluded from every counterfactual (it is unchanged). The walk does not model
  `context_management` edits except through `shrink`.
- **Unexplained short-gap rewrites:** 63 of 99 have no visible cause in the items.
