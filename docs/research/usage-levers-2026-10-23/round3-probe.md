# Round 3 — cache-read quota probe on next3 (2026-10-24)

**Verdict: CHARGED.** About 527M cache-read tokens, with nothing else billable in the window, moved
next3's 5h meter by **+20pp** and its weekly meter by **+3 to +4pp**. If reads were free, those same
calls predict **+0.006pp** and **+0.001pp**. **Conviction 98%** that cache reads count against the
Max quota. Per token they cost **more** than round 2 fitted, not less: about 0.038 pp/Mtok on the 5h
meter (round 2: 0.0199) and 0.0057–0.0076 pp/Mtok weekly (round 2: 0.0048 [0.0036, 0.0056]).

This settles decision 1 of `round2/REPORT.md` (90% → 98%), which unblocks W4 and fixes W3's weighting
(see the end of this file).

## Method

- **Account isolation.** The probe ran on next3 (`~/.claude-tertiary`). The driving session ran on
  next (`CLAUDE_CONFIG_DIR=~/.claude-next`). Two other next3 sessions were live and were left alone:
  `wt-b6fb791b88fa` (working) and `personal` (idle). Their transcripts were snapshotted at the window
  start and their in-window usage measured afterwards (below).
- **One call** (`round3/call.sh`) is the 2.1.293 binary (`cc-claude-bin`) under `env -i`, with
  `-p --model claude-opus-5-5 --effort low --tools "" --setting-sources "" --strict-mcp-config
  --disable-slash-commands --no-session-persistence --system-prompt "<one line>" --output-format json`
  and a fixed 1,150,097-byte context on stdin: `docs/research/*.md` at `7ac848e82`, concatenated in
  sorted order up to 1.15 MB, plus a "reply with one character" tail. That is **458,656 tokens**.
  With no tools, the call makes no tool calls and so no server classifier requests. With no setting
  sources, no hooks or CLAUDE.md enter the prompt, so the prefix is identical on every call.
- **Cache.** The binary writes this prefix to the **1-hour** cache tier (`ephemeral_1h`). Two calls
  before the baseline paid the write: one cold call (458,656 written) and one warm call (458,656 read).
  Every call inside the window was a full hit: **0 cache-write tokens in 1,149 calls**.
- **Driver** (`round3/drive.py`): batches of 60 calls, 6 in parallel. After each batch it read
  next3's meters and checked the guards: weekly +4pp, any dollar meter moving more than $20, failed
  calls. It ran for 22 minutes (01:26–01:48 CDT). A five-minute gap (01:33–01:39) was a driver crash
  on a 429 from the usage endpoint, fixed by falling back to the wire reading.
- **Meters** (`round3/meter.py`, next3 only). It imports `bin/claude-accounts` and calls its
  `fetch_usage` (usage endpoint, integer `utilization`) and `fetch_wire_limits`. The second is one
  `max_tokens: 1` call whose `anthropic-ratelimit-unified-*` headers give the 5h and weekly fractions
  to 2 decimals. The before and after `claude-accounts --fresh` tables are `round3/table-*.txt`, run
  with `CC_ACCOUNTS_WIRE=off` so no other account got a wire call. No other account was touched.
- **Read count**: from the probe's own JSON usage records (`round3/calls.csv`, one row per call),
  not from estimates.

## Probe usage (its own records, inside the window)

| | tokens |
|---|---|
| calls | 1,149 (0 failed), all `claude-opus-5-5` |
| cache read | **526,995,744** (458,656 × 1,149) |
| cache write | 0 |
| input (uncached) | 2,298 |
| output | 3,447 |

Predicted meter movement from round 2's weights (`fit4.py`: weekly reads 0.00481, writes 0.245,
output 0.404 pp/Mtok; 5h reads 0.0199):

| hypothesis | 5h | weekly |
|---|---|---|
| reads charged at the round 2 fit | +10.5pp | +2.54pp |
| reads free | +0.006pp | +0.001pp |

## Readings (next3)

`wire` is the header fraction ×100, rounded to the nearest point. `endpoint` is the usage endpoint's
integer, which rounds up; "429" means the endpoint rate-limited that read. Cumulative reads are
inside the window.

| time (CDT) | reading | cum. reads | wire 5h | wire weekly | endpoint 5h | endpoint weekly |
|---|---|---|---|---|---|---|
| 01:23:59 | before cold write | — | 1 | 12 | 1 | 13 |
| 01:26:18 | **baseline** (after cache write) | 0 | **1** | **12** | **2** | **13** |
| 01:28:16 | batch 1 | 31.6M | 3 | 13 | 3 | 13 |
| 01:29:24 | batch 2 | 59.2M | 4 | 13 | 4 | 13 |
| 01:30:21 | batch 3 | 86.7M | 5 | 13 | 5 | 13 |
| 01:31:17 | batch 4 | 114.2M | 6 | 13 | 6 | 14 |
| 01:32:04 | batch 5 | 141.7M | 7 | 13 | 7 | 14 |
| 01:32:52 | batch 6 | 169.2M | 8 | 13 | 8 | 14 |
| 01:33:39 | batch 7 | 196.8M | 9 | 14 | 429 | 429 |
| 01:39:28 | batch 8 (after 5-min gap) | 224.3M | 10 | 14 | 10 | 14 |
| 01:40:24 | batch 9 | 251.8M | 11 | 14 | 429 | 429 |
| 01:41:09 | batch 10 | 279.3M | 12 | 14 | 429 | 429 |
| 01:41:59 | batch 11 | 306.8M | 13 | 14 | 429 | 429 |
| 01:42:57 | batch 12 | 334.4M | 14 | 14 | 14 | 15 |
| 01:43:42 | batch 13 | 361.9M | 15 | 15 | 429 | 429 |
| 01:44:31 | batch 14 | 389.4M | 16 | 15 | 429 | 429 |
| 01:45:25 | batch 15 | 416.9M | 17 | 15 | 17 | 15 |
| 01:46:07 | batch 16 | 444.4M | 18 | 15 | 429 | 429 |
| 01:46:55 | batch 17 | 472.0M | 19 | 15 | 429 | 429 |
| 01:47:45 | batch 18 | 499.5M | 20 | 15 | 429 | 429 |
| 01:48:28 | **after** (batch 19) | **527.0M** | **21** | **16** | **21** | **16** |
| 01:50:12 | settled, 2 min later | 527.0M | 21 | 16 | 429 | 429 |

The batch labels restart at 1 in `round3/meters.jsonl` after the crash. This table
numbers them straight through.

**Deltas, baseline → after:** 5h **+20pp** on the wire, +19 on the endpoint. Weekly **+4** on the
wire, **+3** on the endpoint. Given each source's rounding, the weekly delta lies in **[3.0, 4.0]pp**
(wire nearest-rounding allows 3–5, endpoint round-up allows 2–4). The 5h meter climbed 1pp for every
27.5M-read batch, at every reading (batch 1 held 69 calls and rose 2pp). That includes the 5-minute
gap with no calls (01:33 → 01:39), where it still rose exactly 1pp for the one batch in between. The
charge comes from the calls, not from wall time.

**Other next3 sessions** (`round3/others_ts.py` → `others_ts.json`): 13 assistant requests inside the
window, all from `wt-b6fb791b88fa`. They total 2.40M cache read, 16,648 cache write and 4,101 output.
That is at most **0.07pp of 5h and 0.02pp weekly** even with reads charged, so subtracting it changes
nothing. More records were appended to the transcripts during the window but carry pre-window
timestamps (history re-serialized, 00:07–01:22 and Oct 21–23). Those records are not new requests and
are excluded.

## Verdict

| | value |
|---|---|
| verdict | **charged** |
| conviction | **98%** that cache reads consume Max quota on both meters |
| 5h weight | 20pp / 527.0M = **0.038 pp/Mtok** (19–21pp → 0.036–0.040) |
| weekly weight | 3.0–4.0pp / 527.0M = **0.0057–0.0076 pp/Mtok** |
| vs round 2 | 5h ≈1.9× the fit (0.0199); weekly ≈1.2–1.6× fit4 (0.0048), at or above the Opus 5.5-only fit (0.00568 [0.00472, 0.00642]) |
| spent | ≈3–4pp of next3's week, ≈20pp of one 5h window; stopped by the 4pp weekly guard on the run's final batch |

**Why 98% and not higher.** "Free" predicts essentially zero, and the meters moved by about 3,400×
that on the 5h meter. The response is linear across 19 batches. The things round 2 could not
exclude are excluded here: no tool calls, so no classifier requests; no cache writes; and output plus
uncached input that predict <0.01pp under any weight. The remaining 2% covers an unseen charge that
scales with prompt size but is not the read itself. An example is a long-context surcharge on an
otherwise free read. No public pricing has that shape, but this probe cannot rule it out.

**The confound that remains: context size.** Each call carried 458,656 tokens, above the 200k line
where API pricing has historically changed. The excess over round 2 (≈1.9× on 5h, ≈1.2–1.6× weekly)
is what a long-context premium would look like. The other explanation is that round 2's
whole-history fit underweights reads, for example because the 5h meter was rescaled. This probe
**cannot tell** these apart. It was one context size, and the 4pp cap was reached. For decisions
about big contexts (W4's recycle thresholds, at 231k median and 459k p90), the measured rate is the
right number either way, since it was measured at a big context. For short-context reads, round 2's
fit stays the best estimate until a same-size probe below 200k is run (≈100M reads at about 190k
tokens, about 0.6–0.8pp weekly).

**What the 5h/weekly ratio says.** The probe gives 20 / 3.0–4.0 = **5–6.7**, against round 2's 4.14.
The 5h meter is relatively tighter than it was over September–October, or tighter at this hour. It
does not change the verdict.

## What this unblocks (plan `docs/plans/USAGE_LEVERS.md`)

- **W4 (context-recycle thresholds): unblocked.** Its gate was "only if W2 confirms reads are
  charged". At the measured weekly rate, a session idling at 459k context costs about 0.003pp of the
  week per turn just to re-read its own history, and about 0.017pp of the 5h window.
- **W3 (idle-cache redesign): use the meter branch.** Round 2's break-even for (b) has two branches:
  net +1.19% to +2.24% of weekly usage at meter weights, −0.97% to +0.57% at API weights. The probe
  makes the meter branch the relevant one. Reads cost about 1/32–1/43 of a weekly cache-write token
  (0.0057–0.0076 against 0.245), not zero, and not 1/10 as list price would have it.
- **W1's doc reword** ("discounted, ≈0.005 pp/Mtok weekly") stays correct as a lower figure. Where
  it quotes a single number, 0.005–0.008 pp/Mtok is the measured range at large context.

Files: `round3/` holds the scripts (`call.sh`, `drive.py`, `meter.py`, `others_ts.py`,
`analyze.py`), the data (`calls.csv`, `meters.jsonl`, `others_ts.json`) and the
before/after `claude-accounts` tables.
