# Probe quota-draw: how many Max plan points Sonnet 5.5 draws per token, relative to Opus 5.5

Written 2026-09-28 by probe "quota-draw". It ran on account next4 (`~/.claude-quaternary`) with CC 2.1.284.

## Answer

**Per output token, Sonnet 5.5 draws about 0.62× what Opus 5.5 draws from the 5h meter. The bound is
[0.49, 0.76].** It does not draw the 0.5× that the list price implies ($10 vs $20 per M output). The
list ratio sits right at the bottom edge of the bound. The two Sonnet phases came out identical, and
the Opus 5.5 rate agrees with the 2026-09-22 sweep, so I hold this at about 80% conviction. The
weekly meter bounds almost nothing: 3 weekly pp for Sonnet against 2 for Opus.

One consequence: per list dollar, Sonnet draws more plan points than Opus. Sonnet gives 0.50 5h-pp
per list-$ and Opus 5.5 gives 0.40 (MEASURED: meter deltas ÷ `total_cost_usd`). Anyone who reads
Sonnet's price list as its plan cost will overstate its saving by about 20%.

## Design (as run)

- **Instrument:** `claude-accounts --fresh --json`, sampled every 120 s by a detached sampler
  (`scripts/lib/detach.sh`). It records the next4 `session_pct` and `weekly_pct` (both integers),
  plus a `ps -E` census of claude main processes on `~/.claude-quaternary`: foreign `-p`, foreign
  interactive, and mine (tagged `S55_QD=1`).
- **Account choice:** next4, not next. Deviation: `claude-accounts` gave next k=0 and next4 k=1, but a
  `ps -E` census at 20:05Z found 6 foreign `-p` processes on next (the sonnet55 synth probe,
  `SYN_CONFIG_DIR=~/.claude-next`). next4 had 1 foreign `-p` (the last cell of the sonnet55 effort
  sweep) plus 1 interactive Opus pane that was idle (no transcript writes in the prior 30 min). The
  driver waited for foreign `-p` = 0 before its baseline hold.
- **Burn calls:** each call was `claude -p --model <id> --effort high --output-format json --tools ""
  --no-session-persistence --strict-mcp-config --setting-sources ""`, with an 18,000-word
  technical-reference prompt whose topic varied per call. 20 calls ran in parallel. Each phase stopped
  launching once completed plus projected in-flight output reached its target. Usage came from each
  call's JSON `usage` field.
- **Phases (run 2):** H0 hold 6 min, then S1 Sonnet burn, H1 6 min, O Opus 5.5 burn, H2 6 min, S2 Sonnet
  burn, H3 8 min. Each phase's window runs from the last sample before its burn_start to the last
  sample before the next burn_start. Every hold ended flat, so each burn's lagging ticks land inside
  its own window.
- **Contamination:** my calls write no transcripts, so every next4 transcript record in a window
  belongs to another consumer. `analyze.py` sums those records, deduped on `message.id`, the same
  method as the opus55 README's `others.py`.

## Results (MEASURED: `python3 /tmp/s55/probe-quota-draw/analyze.py`)

| phase | window (UTC) | calls | output tok | cache_create | 5h [start→end] | weekly | 5h-pp per M out | weekly-pp per M out | foreign -p max | others' tokens |
|---|---|---|---|---|---|---|---|---|---|---|
| H0 baseline | 20:26:30–20:32:26 | 0 | 0 | 0 | 11→11 | 13→13 | — | — | 0 | none |
| S1 Sonnet 5.5 | 20:32:26–20:54:30 | 30 | 1,610,848 | 5,231 | 11→19 (**+8**) | 13→14 (+1) | **4.96** [4.34, 5.59] | 0.62 [0.00, 1.24] | 0 | none |
| O Opus 5.5 | 20:54:30–21:16:30 | 26 | 1,364,284 | 15,113 | 19→30 (**+11**) | 14→16 (+2) | **8.05** [7.32, 8.79] | 1.46 [0.73, 2.20] | 0 | 7 msgs claude-opus-5-5, 3,405 out + 7,898 cc (≈0.03 5h-pp, ignored) |
| S2 Sonnet 5.5 | 21:16:30–21:38:26 | 31 | 1,610,279 | 16,218 | 30→38 (**+8**) | 16→18 (+2) | **4.96** [4.34, 5.58] | 1.24 [0.62, 1.86] | 0 | none |

The brackets are the integer meter's ±1 pp on a difference of two readings. The per-M rates use
output-equivalent tokens: out + cache_create × 360K/3.4M, the Opus-5 marginal list from V-quota.md.
cache_create is below 1.2% of that weighting in every phase. There were 0 errors, every stop_reason
was `end_turn`, and every call's `modelUsage` named only the requested model (no side-model calls).

**Ratio, Sonnet 5.5 : Opus 5.5, 5h meter.** Pooled Sonnet is 16 pp over 3.221M, or 4.97/M, bounded
[14, 18] pp → [4.35, 5.59]. Opus is 8.05/M [7.32, 8.79]. **Point 0.62, bound [0.49, 0.76]**
(worst-case division of the interval ends).

**Weekly.** Sonnet is 3 pp over 3.22M (0.93/M, [0.31, 1.55]) and Opus is 2 pp over 1.36M (1.46/M,
[0.73, 2.20]). The ratio's point is 0.64, but its bound [0.14, 2.1] rules nothing in or out. This
reading is recorded, not used.

**5h-to-weekly exchange** (whole run 2, 20:26→21:40): 5h +27 against weekly +5, which is 5.4× (4.5–7.0
within quantization). The opus55 sweep measured 5.8×, and the draw.py predictor assumes 4.0.

**Cross-check against prior work.** The opus55 README measured Opus 5.5 at 5h obs/pred 0.78 on the
Opus-5 marginal list, which is 0.78 × 4 × 1M/360K ≈ 8.7 5h-pp per M output. This run's 8.05
[7.32, 8.79] contains that value, so the instrument reproduces.

**Per-call profile** (MEASURED from `index2.jsonl`):

| model | calls | mean out/call | thinking share | mean duration | tok/s per stream | list $ |
|---|---|---|---|---|---|---|
| Sonnet 5.5, S1+S2 | 61 | 52.8K | 8.5% | 391 s | 135 | 32.32 |
| Opus 5.5, O | 26 | 52.5K | 12.3% | 493 s | 107 | 27.42 |

On this prompt at effort high, both models wrote about the same number of tokens. So the per-token
ratio of about 0.62 is also the per-task ratio **for this writing task only**. Agentic tasks, where
the two models' token counts differ, were not measured.

## Budget spent (MEASURED, series.jsonl)

On next4, weekly went 11 → 18 (**+7 pp**) and 5h went 0 → 38 over 20:08–21:40Z. That is under the
~15 weekly pp cap. It includes the aborted run 1 below, and the 0→4 5h / 11→12 weekly moves caused by
other probes during run 1's H0.

## Failures and hazards (findings, not passes)

1. **Run 1 was lost to an instrument bug of mine.** The `calls/` directory was never created, because
   the command that should have made it was refused by the auto-mode classifier and I did not check.
   All 20 Sonnet calls of run-1 S1 (20:15–20:24Z) ran and were metered, but each worker thread died
   writing its output, so their usage was never recorded. I killed my own driver (pid 29531) before
   its Opus phase and relaunched it with paths suffixed `2`. Run 1 moved 5h 4→11 (+7) on ~1.06M
   Sonnet output, **ESTIMATED** as 20 calls × 53K mean from run 2. That is about 6.6/M, but other
   probes were active in that window (foreign `-p` 2–4, refusal-exposure and teammate-classifier
   transcripts on next4), so it is contaminated and not used.
2. **Sibling probes were sharing the probe accounts.** In the run-1 baseline, next4's 5h moved 0→3 and
   weekly moved 11→12 with none of my calls live. This was the refusal-exposure probe (7 jobs on next4)
   and others. Run 2 saw foreign `-p` = 0 at every sample and 7 foreign messages in total (above).
3. **Invisible consumers.** Any foreign `-p` run with `--no-session-persistence` writes no transcript.
   The process census is the only guard against these, and it read 0 throughout run 2.
4. The auto-mode classifier also refused one of my read-only `until` polling loops. `python3 -c` sleep
   loops worked.

## Raw data (scratch, not committed)

- Meter series: `/tmp/s55/probe-quota-draw/series.jsonl` (47 samples, 20:08–21:40Z; run 2 starts at 20:26)
- Per-call usage: `/tmp/s55/probe-quota-draw/index2.jsonl`; raw call JSON in `/tmp/s55/probe-quota-draw/calls/`
- Phase marks: `/tmp/s55/probe-quota-draw/phases2.jsonl` (run 1: `phases.jsonl`)
- Scripts: `sampler.py`, `driver.py`, `analyze.py` in the same directory

Compact series (HH:MM 5h weekly foreign_p foreign_interactive mine):
`20:08 0 11 1 1 0;20:10 0 11 0 1 0;20:12 3 12 4 1 0;20:14 4 12 3 2 0;20:16 5 12 2 1 20;20:18 6 12 2 1 20;20:20 6 12 2 1 19;20:22 9 13 0 1 6;20:24 11 13 0 1 0;20:26 11 13 0 1 0;20:28 11 13 0 1 0;20:30 11 13 0 1 0;20:32 11 13 0 1 0;20:34 12 13 0 1 20;20:36 12 13 0 1 20;20:38 12 13 0 1 20;20:40 14 14 0 1 19;20:42 17 14 0 1 10;20:44 17 14 0 1 9;20:46 18 14 0 1 3;20:48 19 14 0 1 1;20:50 19 14 0 1 0;20:52 19 14 0 1 0;20:54 19 14 0 1 0;20:56 19 14 0 1 20;20:58 20 14 0 1 20;21:00 20 14 0 1 20;21:02 20 15 0 1 20;21:04 24 15 0 1 13;21:06 27 16 0 1 6;21:08 28 16 0 1 5;21:10 28 16 0 1 2;21:12 30 16 0 1 0;21:14 30 16 0 1 0;21:16 30 16 0 1 0;21:18 30 16 0 1 20;21:20 30 16 0 1 20;21:22 30 16 0 1 20;21:24 32 17 0 1 20;21:26 35 17 0 1 11;21:28 36 17 0 1 10;21:30 37 17 0 1 2;21:32 38 18 0 1 0;21:34 38 18 0 1 0;21:36 38 18 0 1 0;21:38 38 18 0 1 0;21:40 38 18 0 1 0`

## Skeptic

Written 2026-09-28 by the quota-draw skeptic. I spent no quota: every check below re-reads existing
artifacts or local logs. No cheap live check would settle anything. The wire headers resolve only 0.01
(MEASURED: `grep -o '"wire_5h_util":…' ~/.claude/logs/account-utilization.jsonl`, 671 non-null rows,
all with two decimals). That is the same 1 pp as the endpoint, so tightening 0.62 vs 0.5 needs another
full ABA burn of about 27 5h-pp. Scratch: `/tmp/s55/probe-skeptic-quota-draw/mc.py`.

### What I checked

- **Reproduction.** `python3 /tmp/s55/probe-quota-draw/analyze.py` reproduces every Results row
  exactly (MEASURED).
- **Build and model.** `/Users/chrisren/.claude-284/node_modules/.bin/claude --version` prints
  `2.1.284 (Claude Code)`. Its `claude.exe` mtime is 18:48Z, before the run (MEASURED: `ls -la`). All
  87 call JSONs show 1 turn, `fast_mode_state: off`, `provider: firstParty`, `costBasis: list`, and a
  single `modelUsage` key equal to the requested model (MEASURED: a python pass over `calls/*.json`).
  Run 2 had no path through a wrong build or wrong model.
- **Account identity.** The sha256 prefixes of `oauthAccount.accountUuid` and `organizationUuid` in
  `~/.claude-quaternary/.claude.json` match no other config dir. `~/.claude` shares next's account,
  not next4's (MEASURED). So no process on this machine can draw on next4's credential from another
  config dir without the census seeing it. Use of the account from claude.ai or another device is
  invisible to every instrument here.
- **Census blind spots.** I ran a live `ps -Eww` census today and tallied only the shapes, printing
  no env values. All 86 `CLAUDE_CONFIG_DIR=` entries are followed by a space, none has a trailing
  slash, and all 13 claude main processes match the sampler's `\S*claude(\.exe)?\s` regex (MEASURED).
  Run 1's foreign_p reached 1–4, so the census does detect sibling `-p` probes.
- **Own transcripts.** `~/.claude-quaternary/projects/-private-tmp-s55-probe-quota-draw/` holds only
  a `memory` symlink, so "my calls write no transcripts" holds.

### Findings the note lacks

1. **The instrument silently served cached values.** `~/.claude/logs/claude-accounts.log` logs nine
   next4 `429 poll-throttled … lastgood=served` events during run 2: 20:48:32, 20:50:31, 20:54:36,
   20:56:31, 21:00:35, 21:06:43, 21:24:33, 21:26:42 and 21:34:31 (MEASURED:
   `grep "probe next4" ~/.claude/logs/claude-accounts.log`). The matching `account-utilization.jsonl`
   rows at 20:50:33 and 20:56:33 carry `stale: true`. So about 9 of the 47 series samples are
   last-good values. The sampler tried to record `stale`, but the `--json` row does not carry that
   key, so the field reads `None` in every row and the run could not see the cached reads.
   - **Impact on boundaries.** Four of the five window-boundary readings were fresh. The fifth is
     20:54:30, the S1/O boundary. Its `session_reset_at` stamp (…59.887618) first appears there, so
     it is either fresh or a last-good read taken after the fresh 20:52:29 sample. Either way it
     falls inside H1 with no burn live, so the value 19 stands.
   - **Verdict.** The conclusions do not change, but "sampled every 120 s" overstates how fresh the
     samples were.
2. **Late ticks are ruled out.** The keepwarm ledger reads next4 at 38/18 at 21:44:01 and again at
   21:50:07, both `stale: false` (MEASURED: next4 rows of `account-utilization.jsonl`). The meter
   stayed flat for about 18 min after S2's last tick, so none of S2's charge landed outside its
   window.
3. **Two +1 ticks came before any completion.**
   - **S1.** The 5h meter moved 11→12 by 20:34:27, 66 s after launch. The first S1 completion was at
     20:39:10.
   - **O.** It moved 19→20 by 20:58:28. The first O completion was at 21:01:43.
   - **Conditions.** Both reads were fresh (no 429), foreign_p was 0, and no foreign transcript
     records fall in those minutes. S2 had no such tick. Streaming per-token metering would have
     shown ~0.8 pp/min, and the meter instead stayed flat at 12 through 20:38:27 (MEASURED:
     `series.jsonl`, `index2.jsonl`, the claude-accounts log).
   - **Cause.** Either a small per-request charge at start or an unseen consumer. The note explains
     neither.
   - **Effect.** If it was a consumer, removing it lowers S1 and O by up to 1 each. That raises the
     ratio to at most 0.635 (ESTIMATED: recomputed with those deltas), so it does not threaten the
     "not 0.5" direction.
4. **The foreign messages' cost leaves out their cache reads.** The 7 O-window messages came from
   the interactive `hero-film-regrade` pane during the H2 hold (21:11:31–21:15:35). They also read
   2,017,892 cache tokens (MEASURED: transcript rescan deduped on message.id). `analyze.py` drops
   cache_read, per V-quota's "cache reads free".
   - **Size.** Priced at 0.1× the input list price (assumed $4–5/M for Opus 5.5 input), they come to
     about 0.3–0.4 5h-pp, not 0.03 (ESTIMATED: `mc.py`).
   - **Effect.** Subtracting them moves the ratio to about 0.64, away from 0.5.

### Verdict per claim

| claim | verdict |
|---|---|
| Sonnet 5.5 : Opus 5.5 per output token ≈ 0.62, worst-case bound [0.49, 0.76] | **Upheld.** The arithmetic reproduces: 0.616, [0.494, 0.763]. The windows share their edges, so both corners of the bound can actually occur together, and the stated bound is honest. |
| "It does not draw the 0.5× that the list price implies" | **Upheld, with a correction.** As written it overreaches, because the note's own worst-case bound contains 0.5 (0.494). A quantization Monte Carlo puts P(ratio ≤ 0.50) at about 1e-5 and the 95% interval at [0.54, 0.70] (ESTIMATED: `python3 /tmp/s55/probe-skeptic-quota-draw/mc.py`, 400k draws; uniform fraction inside each rounded-up reading, shared edges). A steady invisible background of b pp per 22-min window would pull the ratio down (b=1 gives 0.593). The flat holds and the 18-min flat tail make b=1 unlikely, P≈0.09 (ESTIMATED: product of no-tick probabilities over the four flat segments, `mc.py`). Say "0.5 is at the extreme corner", not "excluded". |
| The two Sonnet phases came out identical | **Upheld.** Each moved +8, on 1.611M and 1.610M output tokens. They agree as integers, each ±1. |
| The Opus rate agrees with the 2026-09-22 sweep, so "the instrument reproduces" | **Upheld as a consistency check, not as a positive control.** The sweep's figure is 0.78 × 4 × 1M/360K = 8.67, bracket [8.22, 9.0], which overlaps 8.05 [7.32, 8.79]. Both runs used the same instrument, the same account and the same cache-reads-free predictor, so the comparison cannot catch a bias they share. Sanity inside this run comes from the ABA replicate and from flat holds against moving burns. |
| Weekly bounds almost nothing: 3 vs 2 pp, ratio 0.64, [0.14, 2.1] | **Upheld.** |
| 0.50 vs 0.40 5h-pp per list-$ | **Upheld as numbers:** 0.495 [0.433, 0.557] vs 0.401 [0.365, 0.438]. "Sonnet draws more per list-$" has the bound [0.99, 1.53], so it carries the same edge caveat as the headline. |
| "…will overstate its saving by about 20%" | **Refuted as worded.** The list price implies a 50% saving, and the measurement gives 38% [24%, 51%]. That overstates the saving by ~12 points, about 1.3× relative. The ~20–23% figure is how far the list *understates Sonnet's relative plan cost* (0.62/0.50). |
| 5h-to-weekly exchange 5.4× (4.5–7.0) | **Refuted, minor arithmetic.** With +27±1 and +5±1 the bound is [26/6, 28/4] = **[4.33, 7.0]**. The point value is right. |
| Design: "an 18,000-word technical-reference prompt" | **Refuted as worded.** The prompt is about 70 words and *asks for* about 18,000 words. Input per call was ~2 uncached tokens plus ~2.5K cache-read tokens (MEASURED: `index2.jsonl`). The result is unaffected, but the wording misleads anyone modelling input cost. |
| Per-call profile: 52.8K/52.5K out, 8.5%/12.3% thinking, 391/493 s, 135/107 tok/s, $32.32/$27.42 | **Upheld.** Recomputed from `index2.jsonl` (MEASURED); the Sonnet dollars sum to 32.33. Each non-thinking token carries about 2.55 characters for Sonnet and 2.51 for Opus. The two tokenizers are comparable, so the per-token basis is fair. |
| 0 errors, all end_turn, only the requested model in modelUsage | **Upheld.** |
| Every hold ended flat, so lagging ticks land in their own window | **Upheld,** with finding 1's caveat (some of the flat samples were cached) and finding 2's confirmation. |
| Foreign -p = 0 throughout run 2 | **Upheld for CLI consumers on this machine,** per the census-shape and credential checks. Use of the account from other devices is not covered. |
| Others' tokens "≈0.03 5h-pp, ignored" | **Unsupported as a measurement.** It is an estimate that leaves out 2.02M cache-read tokens (finding 4). Ignoring them still errs in the safe direction for the headline. |
| Budget: weekly 11→18, 5h 0→38 | **Upheld.** Taken from `series.jsonl`; the post-run ledger still reads 38/18. |
| Run 1 was lost to a missing `calls/` dir | **Upheld:** `driver.log` has 20 `FileNotFoundError` tracebacks. The artifacts cannot confirm that a classifier refusal caused the missing dir. |
| Run-1 baseline "5h moved 0→3" | **Minor inconsistency.** The series shows 0→3 by 20:12 and 0→4 by 20:14, and the Budget section says 0→4. Which figure you get depends on the sample chosen. |
| Account choice: "next k=0" at 20:05Z | **Unsupported.** No artifact covers 20:05Z, and the first sample (20:08:25) reads next_k = 1, next_k_work = 26. It does not bear on the result. |

**Bottom line.** The headline survives: per output token on the 5h meter, Sonnet 5.5 draws about 0.6×
what Opus 5.5 draws. List 0.5× is unlikely but not excluded by the note's own bound. Three wordings
need fixing: the 0.5 exclusion, "overstate saving by 20%", and the lower bound of the exchange rate.
The instrument has a silent-cache mode the note did not report. I checked it, and it did not affect
the window boundaries.
