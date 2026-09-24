# Census: the fleet baseline by billing type (2026-09-09 → 2026-09-23)

**Source:** `data/extract.sqlite` (built 2026-09-23T23:02Z), filtered to `xdup=0`. It covers 162,406 responses, 4,086 contexts and 1,052 session trees.
**Re-derive:** `cd /tmp && nice -n 10 python3 scripts/census.py && nice -n 10 python3 scripts/census_cache.py`. This writes `census.json`, with the supplement merged in under `cache_supplement`, and also `census_cache.json`.
**Dollars are list-price weights.** The fleet is billed by subscription quota, not dollars. Each response is priced at its own model's rates and also re-priced at Opus 5.5 ($4/$20, cache read 0.05x). Cache writes cost 1.25x input at 5m TTL and 2x at 1h.
**Labels:** every number is MEASURED from the extract unless marked otherwise. Output tokens use `output_est`, which is ESTIMATED for the 18,041 responses (11.1%) that have no final usage record, nearly all of them agent responses (EXTRACT.md L2). Its totals are good to about ±3%; its per-response values are not usable.

## Headline

1. **Cache reads are 58% of spend, and they scale with context length.** A main thread re-reads a mean of **331k tokens per turn**; its first request is only 123k. Spend per turn is driven by how long the context is, not by output (main mean 813 output tokens per response).
2. **The setup prefix accounts for about 37% of all spend (ESTIMATED upper bound).** The prefix is everything in a context's first request: system, tools, memory files, skills and the brief. Writing it costs **$2.9k** and re-reading it on every later turn costs **$9.3k**, together **$12.2k of $32.5k**. It is an upper bound because the first request also holds the first prompt or brief. `/context` puts the static part at 64k of the ~123k (52%), and memory files alone at 48k, so the static harness is roughly **$6-9k (19-29%)** (ESTIMATED by ratio).
3. **About half of main-thread 1h cache writes are re-writes after a miss, not new content.** 702 mid-session misses (0.85% of later requests) cost **$2.65k of the $5.13k** main-thread 1h-write spend. 518 of them came after the session had been **idle more than 1h**, each re-writing a mean ~370k-token context ($2.1k).
4. **Spend is concentrated and worker-heavy at the top.** The top 10% of tasks carry 67% of $. Only 106 of 1,052 tasks (10%) use subagents or workflow agents, yet they carry 39% of fleet $. Inside those tasks workers take a median 62%, and 89-96% in the largest trees.
5. **1h TTL on main threads is correct (negative result, ESTIMATED).** Replaying main threads under a 5m TTL, using the measured gaps between turns, gives **+$4.1k (+23% on the input side)**. Only 3.9% of main-thread gaps exceed 5 min, but each one would re-write a ~330k context at 1.25x.

## 1. Fleet totals by billing type

| billing type | tokens | $ at own model | share | $ at Opus 5.5 | share |
|---|---:|---:|---:|---:|---:|
| uncached input | 1.23M | 7 | 0.0% | 5 | 0.0% |
| cache write 5m | 608.5M | 4,064 | 12.5% | 3,042 | 16.6% |
| cache write 1h | 481.4M | 5,131 | 15.8% | 3,851 | 21.0% |
| cache read | 40,952.2M | 19,006 | 58.4% | 8,190 | 44.7% |
| output (est) | 161.5M | 4,309 | 13.3% | 3,230 | 17.6% |
| **total** | | **32,517** | | **18,319** | |

- The recorded final output is 139.7M; imputation adds 21.8M.
- The census of record (`cc-quota-price`) reads output 46% low (EXTRACT.md L1).
- Re-priced at Opus 5.5, the cache-read share falls from 58% to 45% because its cache-read multiplier is 0.05x instead of 0.1x. Cache writes and output gain share.
- **Not included:** side queries such as prompt suggestion, away summaries, titles and classifiers never reach transcripts. That is about $105 of Haiku plus ~11M uncached Opus/Fable input (EXTRACT.md L6).

## 2. Splits

### By context type

| ctx_type | contexts | responses | $ | share | $ at 5.5 | share | cache read | cw 5m | cw 1h | output |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| main | 1,055 | 83,887 | 19,747 | 60.7% | 10,666 | 58.2% | 64.8% | 0.0% | 26.0% | 9.2% |
| workflow_agent | 2,669 | 63,071 | 10,673 | 32.8% | 6,388 | 34.9% | 47.5% | 33.2% | 0 | 19.3% |
| subagent | 362 | 15,448 | 2,098 | 6.5% | 1,264 | 6.9% | 54.5% | 24.9% | 0 | 20.6% |

- Main threads write 1h cache; every agent writes 5m cache.
- Workflow agents spend a third of their $ on 5m cache writes. Each agent writes its own ~127k prefix because the setup sits after the per-agent brief (see `binary-and-cache.md`).

### By model

| model | responses | $ | share | $ at 5.5 | dominant class |
|---|---:|---:|---:|---:|---|
| claude-opus-5 | 139,532 | 28,007 | 86.1% | 15,249 | cache read 64% |
| claude-fable-5-1 | 5,080 | 2,642 | 8.1% | 1,200 | cw 1h 31%, cw 5m 28%, output 28% |
| claude-opus-5-5 | 16,098 | 1,711 | 5.3% | 1,711 | cache read 42% |
| claude-opus-4-8 / 4-7 (4-7 ASSUMED at 4-8 prices) | 209 | 111 | 0.3% | 83 | |
| claude-sonnet-5 | 738 | 45 | 0.1% | 69 | |
| claude-haiku-4-5 | 44 | 2 | 0.0% | 7 | |
| `<synthetic>` | 705 | 0 | | | |

- Opus 5.5 became the default on 2026-09-22 and carries only 5% of this window.
- Per-model, per-context rows are in `census.json` (`by_ctx_type_model`).

### Main threads by entrypoint

| entrypoint | main contexts | responses | $ | hit rate | tasks | median $/task | worker share |
|---|---:|---:|---:|---:|---:|---:|---:|
| `cli` (TUI) | 815 | 83,186 | 19,594 | 98.3% | 812 | 10.84 | 39.4% |
| `sdk-cli` (headless `-p` / SDK) | 237 | 697 | 150 | 75.3% | 236 | 0.63 | 4.0% |

- `cli` includes the dispatched `handoff-fire` sessions, which run in the TUI, so "interactive" does not mean human-attended.
- Headless runs are 22% of tasks but 0.5% of $. 83% of their $ is 1h cache writes on one-shot runs.

## 3. Per task (task = one session tree: a main thread plus every subagent and workflow agent under its session id)

| per task | mean | median | p75 | p90 | p99 | max |
|---|---:|---:|---:|---:|---:|---:|
| $ (own model) | 30.91 | 7.33 | 21.72 | 70.39 | 385.49 | 1,079.90 |
| $ at Opus 5.5 | 17.41 | 4.38 | 12.04 | 39.34 | 217.75 | 606.73 |
| responses | 154 | 42 | 112 | 303 | 1,772 | 8,206 |
| contexts | 3.88 | 1 | 1 | 2 | 58 | 444 |
| human prompts (main thread) | 2.61 | 1 | 2 | 7 | 25 | 40 |
| all main-thread prompts | 4.99 | 1 | 4 | 14 | 39 | 406 |
| $ per human prompt (858 tasks with ≥1) | 12.65 | 4.02 | 11.82 | 26.14 | 166.43 | 355.71 |

- **Human prompts** are main-thread `user_prompt` items of subkind plain, command, pasted and bash_mode. Machine-authored fire briefs arrive as `plain` and count here too. Task notifications, teammate and peer messages, interrupts and agent briefs are excluded.
- 194 trees have no human prompt in the window: they started before the window or were driven only by notifications.
- **$ per human prompt, fleet: $11.8** ($32,517 / 2,750).
- **Worker share** is the $ spent in subagents and workflow agents: 39.3% fleet-wide.
  - Only 106 tasks (10.1%) have any worker. Across all tasks the median share is 0%.
  - Among the tasks with workers: mean 57%, median 62%, p90 91%.
- **Concentration:**

  | slice | share of $ |
  |---|---:|
  | top 1 tree | 3.3% |
  | top 15 trees | 23.4% |
  | top 50 trees | 49.1% |
  | top 100 trees | 66.3% |
  | top 10% of trees | 67.4% |

## 4. Cache hit rate and prefix size

**Cache hit rate** = cache_read / (cache_read + cache_creation + uncached input).

| ctx_type | hit rate | 1st request | later requests | mean prefix per response | median | p90 | p99 | 1st-request prefix (mean / median) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| main | 98.3% | 17.1% | 98.6% | 331.5k | 297.1k | 559.1k | 748.3k | 123.4k / 128.8k |
| workflow_agent | 95.5% | 14.6% | 97.7% | 187.4k | 171.6k | 275.0k | 412.2k | 126.8k / 120.7k |
| subagent | 96.8% | 7.0% | 97.9% | 167.9k | 161.7k | 242.7k | 353.7k | 93.7k / 102.5k |
| fleet | 97.4% | | | 258.9k | | | | |

- The hit rate is high. The cost lever is the size of what is read, not the rate.
- A first request reads only the ~16k shared system+tools block and writes everything else.

**Setup-prefix attribution** (`census_cache.py` §A; F = first-request prefix; ESTIMATED upper bound on static setup):

| ctx_type | contexts | mean F | setup write $ | setup re-read $ | re-read share of that ctx's cache-read $ |
|---|---:|---:|---:|---:|---:|
| main | 985 | 123k | 1,011 | 5,379 | 42% |
| workflow_agent | 2,401 | 127k | 1,691 | 3,285 | 65% |
| subagent | 361 | 94k | 193 | 630 | 55% |
| **total** | | | **2,895** | **9,294** | = **$12.2k, 37.5% of fleet $** |

**Mid-session cache misses** (§B, MEASURED): a later request re-writes at least 50% of a prefix of 20k tokens or more.

| ctx_type | misses | re-write $ |
|---|---:|---:|
| main | 702 | 2,655 |
| workflow_agent | 366 | 656 |
| subagent | 61 | 66 |

Main-thread misses by cause (§D), from the gap since the previous response:

| cause | misses | $ |
|---|---:|---:|
| idle > 1h | 518 | 2,106 |
| 5m-1h (prefix mutation, TTL still live) | 63 | 208 |
| ≤ 5m | 65 | 158 |
| model switch | 32 | 116 |

24 misses could not be classified because a timestamp was missing.

**TTL replay, main threads** (§C, ESTIMATED): a 5m TTL would force 3,105 extra misses and cost $22.0k against the actual $17.9k on the input side, **+$4.1k**.

| gap between main-thread responses | value |
|---|---:|
| p50 | 8.5 s |
| p90 | 64 s |
| p95 | 170 s |
| p99 | 1,726 s |
| share > 5 min | 3.9% |
| share > 1 h | 0.66% |

## 5. Top 15 session trees by $

| # | project | session | $ | $ at 5.5 | fleet share | responses | contexts | human prompts | worker share | dominant billing type |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | `-worktrees-wt-pool-7` | `eab98191` | 1,080 | 607 | 3.3% | 8,206 | 444 | 30 | 89% | cache_read (60%) |
| 2 | `claude-infrastructure` | `309ec82a` | 964 | 538 | 3.0% | 4,504 | 99 | 19 | 91% | cache_read (61%) |
| 3 | `claude-infrastructure` | `a4241557` | 589 | 326 | 1.8% | 2,523 | 23 | 7 | 70% | cache_read (62%) |
| 4 | `claude-infrastructure` | `e27fe852` | 550 | 306 | 1.7% | 2,715 | 44 | 9 | 92% | cache_read (61%) |
| 5 | `claude-infrastructure` | `04235d35` | 452 | 311 | 1.4% | 1,642 | 255 | 14 | 95% | cache_write_5m (54%) |
| 6 | `personal` | `22100d17` | 431 | 244 | 1.3% | 2,510 | 100 | 13 | 79% | cache_read (58%) |
| 7 | `claude-infrastructure` | `d90959db` | 431 | 240 | 1.3% | 2,042 | 28 | 19 | 75% | cache_read (61%) |
| 8 | `claude-infrastructure` | `11569d45` | 417 | 203 | 1.3% | 1,413 | 34 | 10 | 84% | cache_read (38%) |
| 9 | `claude-infrastructure` | `52e35019` | 415 | 219 | 1.3% | 1,262 | 18 | 5 | 81% | cache_read (40%) |
| 10 | `claude-infrastructure` | `cc1f8d0a` | 414 | 195 | 1.3% | 854 | 40 | 7 | 92% | cache_write_5m (45%) |
| 11 | `-worktrees-reland-rowkey` | `fd1ab61c` | 397 | 168 | 1.2% | 1,664 | 1 | 2 | 0% | cache_read (94%) |
| 12 | `mac-bootstrap` | `57859803` | 374 | 216 | 1.2% | 2,139 | 44 | 5 | 92% | cache_read (56%) |
| 13 | `-worktrees-wt-cc-140654-64740` | `52b82738` | 368 | 235 | 1.1% | 1,799 | 167 | 7 | 96% | cache_write_5m (45%) |
| 14 | `-worktrees-wt-pool-3` | `7193ec2b` | 357 | 180 | 1.1% | 1,718 | 153 | 11 | 88% | cache_write_5m (33%) |
| 15 | `-worktrees-wt-f5c3cfb86e2e` | `65e22fd1` | 356 | 151 | 1.1% | 1,165 | 1 | 1 | 0% | cache_read (94%) |

- Two shapes dominate:
  - **Workflow fan-outs**: many contexts and 80-96% worker share. Where a wave runs dozens to hundreds of agents, the dominant class becomes 5m cache writes (#5, #10, #13, #14).
  - **Long single-thread autonomous runs**: one context, 1-2 prompts, 94% cache read (#11, #15). Each turn re-reads a very long context: about $0.24 per response, or roughly 450k tokens at Opus 5 cache-read price (ESTIMATED).
- The top 15 carry $7.6k (23.4%). The full JSON rows include $ by billing class.

**By project (top 5 of 10):**

| project | tasks | $ | share |
|---|---:|---:|---:|
| claude-infrastructure | 187 | 10,175 | 31.3% |
| personal | 42 | 2,744 | 8.4% |
| wt-pool-7 | 28 | 2,153 | 6.6% |
| mac-bootstrap | 31 | 1,286 | 4.0% |
| wt-pool-2 | 17 | 794 | 2.4% |

## Gaps

- Output for 11.1% of responses is imputed. Per-task $ for agent-heavy trees carries that error; the error on totals is about 3%.
- There is no tokenizer. The static-vs-brief split of F uses `/context` ratios (ESTIMATED).
- Side-query spend (L6) is not in any per-task figure.
- Miss causes are classified from response timestamps. The "5m-1h" and "≤5m" buckets (128 misses, $366) are prefix mutations whose trigger (compaction, attachment churn, effort switch) was not identified.
- `entrypoint` cannot separate human-attended TUI sessions from fired autonomous ones. Both are `cli`.
- The Opus 4.7 price is ASSUMED equal to Opus 4.8.
