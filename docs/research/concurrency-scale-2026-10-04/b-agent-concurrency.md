# B: How many agents ran at once, and does machine load follow the count? (2026-09-20 to 2026-10-04 06:50Z)

## Answer first

- **The most agents ever observed running at once was 70** (MEASURED, 2026-09-28 20:11Z: 23 top-level, 14 subagents, 33 workflow agents). The loosest count, which treats a transcript as running from its first record to its last, peaks at **79**. Agent concurrency never reached 100 in the 14 days.
- **p95 is 19 agents actively running at once (p99 31, p50 2)** (MEASURED). The loose count gives p95 43 and p50 16.
- **The lag point is far below 100 agents.** Load per core crosses the 2.5 alarm line at a median of **5 actively working agents**. At load per core of 10 or more, the median is **9 active agents** (about 4 interactive sessions and 3 children), with 25 transcripts open and 18 claude processes (MEASURED). The operator's figure of "15 sessions × 10-20 subagents ≈ 100" describes the *open* sessions correctly (process count p50 14, p95 30, max 41). It overstates the *working* agents and the children per session by about 10×.
- **Load follows actively working interactive sessions best, not total agents and not open sessions.** Variance explained, hourly:

  | Measure | Spearman ρ² | Pearson R² |
  |---|---|---|
  | Active interactive sessions | 0.67 | 0.35 |
  | All active agents | 0.62 | 0.26 |
  | Active subagents and workflow agents | 0.49 | 0.13 |
  | Open sessions (spans) | 0.18 | 0.06 |
  | Process count | ≈0.09 | 0.03 (minute level) |

  Fitted marginal cost (MEASURED fit, weak at R² 0.20):
  - one active interactive session: **+1.2 load per core**
  - one in-process teammate: **+1.0**
  - one headless `claude -p`: **+0.6**
  - one direct subagent: **+0.4**
  - one workflow agent: **+0.22**
- **Children per session.** 86% of active-session-minutes have 0 children, p95 is 4 and the maximum is 37. Even at the 60 peak minutes the median session has 0 children (p75 1, p95 12). Only 58 of 448 session-minutes (13%) carried 10 or more. The pattern of 10-20 children per session is real, but only a minority of sessions run waves.
- **Memory is not what binds at today's scale.** The CPU run queue is. Headroom p50 drifts only from 28 GB (0 active) to about 21 GB (30-50 active). The p5 stays at 10-14 GB in every bucket (MEASURED).

## Method

**Sources (all read-only):**
- Transcripts from four project roots:
  - `~/.claude/projects` (next; `~/.claude-next/projects` resolves to it, so it is not counted twice)
  - `~/.claude-secondary/projects` (next2)
  - `~/.claude-tertiary/projects` (next3)
  - `~/.claude-quaternary/projects` (next4)

  `~/.claude-next4/projects` holds only 2 files in the window and is excluded. No other `~/.claude-*` or `/tmp` config dir holds transcripts from the window.
- Load:
  - `~/.reso/load.jsonl*`: `loadavg[0]` and `runnable`, sampled about every 10 s, giving 22,513 minutes.
  - `~/.claude/logs/capacity-alarm.jsonl`: `sessions` (the claude process count), `headroom_gb`, `load_per_core`. It samples every 72 s at p50, so values are carried forward up to 3 minutes. Of 19,981 load minutes, 17,451 have a value.

**Steps:**
1. **`b_scan.py`** walked the roots with `os.scandir`. It kept files with mtime after 2026-09-19 and read only the first 16 KB (growing if needed) and the last 32 KB of each, regex `"timestamp":"…Z"`. Result: 12,077 files in 13 s.
   - Kinds: `main` is `<slug>/<sid>.jsonl`. `sub` is `<sid>/subagents/agent-*.jsonl`. `wf` is `<sid>/subagents/workflows/wf_*/agent-*.jsonl`.
   - It also read `.meta.json` (agentType, spawnDepth, requestShape).
2. **Dedup.** 1,810 subagent transcripts and 12 main transcripts exist as identical copies in two accounts, left by session moves between accounts. The check found all 1,810 had the same sid, rel, first and last timestamps, and size. Keying on (kind, sid, aid) leaves **10,175 unique transcripts.**
3. **Classification.** Team configs (`~/.claude*/teams/*/config.json`, 46 in the window) list only the lead (`backendType: in-process`), so teammates cannot be found from configs. Instead, a main transcript counts as a **teammate** when its records carry `"teamName"`.
   - Top-level transcripts split by `"entrypoint"` into **interactive** (`cli`, 763 transcripts, median 39 active minutes) and **headless** (`sdk-cli`, 2,924 transcripts, median 2 minutes). Headless runs are mostly hook, classifier and probe calls.
   - Final counts: **ia 763 · hl 2,956 · teammate 206 · direct subagent 881 · workflow agent 5,369.**
4. **Two concurrency definitions per minute (UTC):**
   - **Span** (the brief's definition): a transcript counts in every minute between its first and last record. This is an upper bound, because idle open sessions count as running.
   - **Active** (`b_active.py` reads every line): timestamps are merged into intervals wherever consecutive records are at most 300 s apart, and a minute counts if it overlaps an interval. This is a lower bound, because a single Bash call or model turn longer than 5 minutes shows as a gap. True working concurrency lies between the two.
5. **`b_rate.py`** produced per-minute record and `tool_use` counts by category. **`b_analyze.py` and `b_analyze2.py`** joined these to load, ran the bucket, percentile, Pearson, Spearman and OLS analyses, and mapped children to parents:
   - subagents and workflow agents map to the parent `sid`
   - teammates map to the lead through `teamName = session-<lead sid prefix>`
6. **Validation.** The span count of interactive sessions agrees with the capacity-alarm process count: R² 0.71 and median difference 0. Transcript coverage of top-level sessions is therefore close to complete.

**Deviation from the brief:** `taskpolicy -c background` starved the scanner completely. It got 0.04 s of CPU in 150 s while system load was 168. All passes therefore ran at `nice -n 10` at default QoS. The total cost was about 2.5 minutes of single-core CPU and about 14 GB of sequential reads.

## Concurrency distribution (MEASURED, 19,981 minutes with load data)

| Category | Active p50 | p90 | p95 | p99 | max | Span p95 | Span max |
|---|---|---|---|---|---|---|---|
| Interactive top-level | 1 | 5 | 7 | 10 | 28 | 39 | 48 |
| Headless `claude -p` | 0 | 0 | 0 | 10 | 31 | 0 | 31 |
| Teammates (in-process) | 0 | 0 | 1 | 4 | 10 | 4 | 13 |
| Direct subagents | 0 | 1 | 2 | 10 | 25 | 3 | 25 |
| Workflow agents | 0 | 7 | 11 | 24 | 45 | 12 | 45 |
| **Children (teammates + subagents + workflow)** | 0 | 9 | 13 | 26 | 47 | 14 | 47 |
| **All agents** | **2** | 14 | **19** | 31 | **70** | **43** | **79** |
| capacity-alarm `sessions` (processes) | 14 | n/a | 30 | n/a | 41 | n/a | n/a |

## Load per core and memory by concurrency bucket (MEASURED)

`lpc` is `loadavg_1m / 10` from reso, with a 10-core host (8P+2E) and 64 GB of RAM (`sysctl hw.memsize`). Headroom is `capacity-alarm.headroom_gb`.

**Bucketed on actively working agents:**

| Active agents | Minutes | lpc p50 | lpc p95 | Share of minutes with lpc ≥ 2.5 | Headroom p50 (GB) | Headroom p5 (GB) |
|---|---|---|---|---|---|---|
| 0 | 6,147 | 1.12 | 2.59 | 5% | 28.2 | 21.4 |
| 1–4 | 6,712 | 1.97 | 18.2 | 39% | 26.7 | 11.7 |
| 5–9 | 3,369 | 4.28 | 25.6 | 72% | 24.8 | 11.3 |
| 10–19 | 2,892 | 6.18 | 30.5 | 84% | 24.2 | 12.3 |
| 20–29 | 608 | 9.96 | 34.9 | 96% | 22.2 | 10.7 |
| 30–39 | 213 | 15.0 | 34.8 | 98% | 20.9 | 13.6 |
| 40–49 | 36 | 18.4 | 38.1 | 97% | 21.9 | 14.7 |
| 50–79 | 4 | 9.3 | 22.9 | 100% | 13.6 | 10.7 |

**Bucketed on span agents (open transcripts):**

| Span agents | Minutes | lpc p50 | lpc p95 | Headroom p50 (GB) | Headroom p5 (GB) | Process count p50 |
|---|---|---|---|---|---|---|
| 0–9 | 3,384 | 1.19 | 3.66 | 29.0 | 21.6 | 7 |
| 10–19 | 8,945 | 1.66 | 19.2 | 25.2 | 19.6 | 14 |
| 20–29 | 4,369 | 3.49 | 25.3 | 25.6 | 10.3 | 19 |
| 30–39 | 1,702 | 5.80 | 29.1 | 24.5 | 10.8 | 22 |
| 40–49 | 1,197 | 8.82 | 30.3 | 30.5 | 12.6 | 30 |
| 50–59 | 303 | 9.05 | 33.9 | 29.5 | 16.0 | 32 |
| 60–79 | 81 | 10.2 | 34.6 | 27.8 | 9.7 | 32 |

**Inverse view: what concurrency sat under each load band.** This is what "the lag point" actually looks like.

| lpc band | Minutes | Active all p50 / p95 | Active interactive p50 | Active children p50 | Span all p50 | Process count p50 | Tool calls per minute p50 |
|---|---|---|---|---|---|---|---|
| <1 | 3,347 | 0 / 3 | 0 | 0 | 11 | 11 | 0 |
| 1–2.5 | 8,028 | 1 / 10 | 1 | 0 | 13 | 14 | 0 |
| 2.5–5 | 3,379 | 5 / 18 | 3 | 1 | 20 | 16 | 11 |
| 5–10 | 2,315 | 8 / 24 | 4 | 3 | 25 | 18 | 20 |
| 10–20 | 1,698 | 9 / 29 | 4 | 3 | 27 | 18 | 22 |
| ≥20 | 1,214 | 9 / 32 | 4 | 2 | 25 | 16 | 22 |

The agent count saturates at about 9 active while load keeps climbing. Above lpc 10 the extra load does not come from more agents.
- 506 of 2,912 minutes with lpc ≥ 10 (17%) had 3 or fewer active agents (MEASURED).
- The two worst hours, 2026-09-26 03:00-04:00Z, had lpc mean 58 and `loadavg` max **1,010** with only about 8 active agents.
- On 2026-10-04 at 01:00Z, lpc mean was 36 with 1.9 active agents. The reso `top3` there is dominated by **ffmpeg** and next-server. INFERRED: a video render plus a dev server, not agents. Attributing the non-agent load is outside this brief.

## Does load follow total agents or top-level sessions?

All figures below are MEASURED from `b_analyze2.out`.

| Predictor | Minute R² | Minute ρ² | Hourly R² | Hourly ρ² |
|---|---|---|---|---|
| Active interactive sessions | 0.169 | 0.438 | **0.347** | **0.667** |
| Active all agents | 0.160 | **0.496** | 0.260 | 0.621 |
| Active children | 0.079 | 0.320 | 0.128 | 0.486 |
| Transcript record rate | 0.102 | 0.438 | 0.211 | 0.591 |
| `tool_use` rate | 0.095 | 0.428 | 0.198 | 0.576 |
| Span all (open transcripts) | 0.108 | 0.302 | 0.139 | 0.381 |
| Span interactive (open sessions) | 0.048 | 0.149 | 0.064 | 0.177 |
| capacity-alarm `sessions` | 0.030 | 0.093 | n/a | n/a |
| Active headless | 0.027 | 0.040 | 0.054 | 0.123 |

- **Working beats open.** Every *active* measure beats its *span* counterpart by 2-5×. The process count (open sessions) explains about 3% of load variance. Idle open sessions cost CPU close to nothing.
- **Interactive sessions carry the most load per unit.** At hourly grain, active interactive sessions explain the most variance. In the joint fit `lpc ~ ia + hl + wf + sub + mate` (R² 0.207), the coefficients per active unit are:
  - interactive 1.20
  - teammate 1.05
  - headless 0.63
  - direct subagent 0.43
  - workflow agent 0.22
  - intercept 1.87

  Interactive sessions and teammates run builds, tests and hooks. Workflow and research agents are mostly reads and model waits (INFERRED from their agentTypes: `workflow-subagent` 4,221, `workflow-lean` 3,089, `deep-research` 336).
- **Neither count is a good model on its own: Pearson R² stays ≤ 0.35.** Load is heavy-tailed and partly driven by non-agent processes (see above). Active interactive sessions and active children are nearly independent of each other (R² 0.095), so both terms belong in a capacity model.

## Peak periods (MEASURED, UTC)

**Peak minutes by active agents** (lpc is load per core; open sessions is the capacity-alarm process count, with n/a where it has no sample):

| Minute | Active (span) | Interactive + headless / sub / wf / teammate | lpc | Headroom (GB) | Open sessions |
|---|---|---|---|---|---|
| 09-28 20:11 | **70 (79)** | 23 / 14 / 33 / 0 | 9.1 | 20.2 | 19 |
| 09-24 18:43 | 53 (64) | 13 / 0 / 40 / 0 | 3.4 | 13.6 | 16 |
| 09-29 17:49 | 52 (65) | 28 / 22 / 2 / 0 | 9.3 | 10.7 | 13 |
| 09-30 18:57 | 50 (71) | 13 / 0 / 34 / 3 | 22.9 | n/a | n/a |
| 09-30 01:09 | 49 (63) | 4 / 0 / 45 / 0 | 10.9 | 23.4 | 14 |
| 10-01 08:22 | 37 (**76**) | span: 39 top-level / 37 wf | 13.0 | 31.8 | 32 |

**Sustained hours by mean active agents** (lpc mean, with max in brackets):

| Hour | Mean (max) agents | Mean interactive | Mean children | lpc mean (max) | Minimum headroom (GB) |
|---|---|---|---|---|---|
| 10-04 06Z (this wave) | 35.4 (42) | 4.0 | 31.4 | 16.9 (25.7) | 21.9 |
| 10-04 05Z | 26.2 (42) | 4.1 | 22.2 | 26.1 (42.3) | 20.7 |
| 09-30 01Z | 23.6 (49) | 3.6 | 20.0 | 8.8 (13.9) | 21.4 |
| 09-30 19Z | 23.3 (44) | 6.8 | 16.5 | 26.5 (38.4) | **9.2** |
| 10-02 01Z | 20.9 (38) | 6.7 | 14.1 | 20.1 (39.9) | 25.4 |

**Busiest days by agent-minutes:**

| Day | Agent-minutes | lpc p50 | lpc p95 |
|---|---|---|---|
| 09-30 | 15,631 | 3.9 | 20.1 |
| 09-29 | 12,448 | 5.8 | 25.7 |
| 10-01 | 9,881 | 5.8 | 28.6 |

The quietest days were 09-27 (2,470 agent-minutes) and 10-03 (2,453).

## Children per session (MEASURED; parent = sid, teammates mapped to the lead through teamName)

- **Per minute,** children ÷ active top-level sessions: p50 0.33, p75 1.5, p95 6, p99 12, max 33.
- **Per session-minute** (48,202 in total): 86% have 0 children, p90 1, p95 4, p99 11, max 37.

  | Children | 0 | 1–4 | 5–9 | 10–14 | 15–19 | 20–24 | 25+ |
  |---|---|---|---|---|---|---|---|
  | Session-minutes | 41,520 | 4,518 | 1,470 | 607 | 69 | 11 | 7 |

- **At the 60 peak minutes,** per active session: p50 0, p75 1, p95 12, max 37. 58 of 448 (13%) had 10 or more children.

## What this implies for reaching 1,000 agents (INFERRED, low confidence: linear extrapolation of a fit with R² 0.2)

- Measured scale is a working peak of 70 agents and a p95 of 19. **1,000 is 14× the peak and 50× the p95.**
- The fit costs a mixed 1,000 (50 interactive plus 950 children at about 0.25 each) at roughly 1.9 + 60 + 240 ≈ **300 load per core**, against a 1.5 warning line. Even if the true per-child cost were 10× lower, a 10-core host cannot do this.
- Memory: `headroom ~ capS + ia + kids` gives −0.51 GB per active interactive session and −0.32 GB per active child (R² 0.10). 950 children × 0.32 ≈ 300 GB, against 64 GB. This is weak evidence. In-process subagents share the parent node process, so the true marginal is probably lower.
- The lever is *active* concurrency and *per-agent CPU*, chiefly in interactive sessions and teammates. Hooks and test or build runs are suspects (INFERRED), not the number of open sessions.

## Adversarial pass (gaps checked)

1. **Missed config dirs?** Checked `~/.claude-next4` (2 files), `~/.claude-{scratch,plans,tasks,NNN}` (no projects dir with transcripts), and `/tmp` and `/private/var/folders` config dirs (none). The interactive span count against the process count gives R² 0.71 with median difference 0, so coverage is adequate.
2. **Double-counting from cross-account copies?** Found 1,810 duplicates and removed them by dedup key.
3. **Teammates invisible in team configs?** Confirmed: configs keep only the lead. Teammates were found through `teamName` in the transcripts instead.
4. **Active definition too strict?** Reported span as the upper bound throughout. Conclusions hold on both: the span max of 79 is still below 100, and span predicts load worse.
5. **Non-agent load contaminates the correlation?** Yes, confirmed: ffmpeg, next-server, and a 1,010 loadavg spike on 09-26. This caps the R² and is flagged rather than modelled.

**Not done:** per-process CPU attribution (agents versus hooks versus builds). The reso `top3` field is ranked by RSS, not CPU, so it cannot answer that question.

## Artifacts (all in /tmp/concurrency-scale/)

- Scripts: `b_scan.py`, `b_active.py`, `b_rate.py`, `b_load.py`, `b_analyze.py`, `b_analyze2.py`
- Data:
  - `b_spans.jsonl`: per-file first and last timestamps plus meta
  - `b_active.jsonl`: active intervals plus teamName
  - `b_entry.json`: the sid-to-entrypoint map
  - `b_rate.json`
  - `b_load_min.json`
  - `b_minutes.json`: the joined per-minute table
- Raw outputs: `b_analyze.out`, `b_analyze2.out`
