PASS — conviction 70%. On the central estimate every leg passes, with and without 0039. Only the no-baseline worst case fails the 50% rate leg; see Verdict.

# Rank 16: `bashOutputMaxChars: 16000`, measured by replaying real transcripts

Scope: the window is 2026-09-09T00:00Z to 2026-09-23T23:02Z (14.96 days). It covers every main, subagent and workflow-agent transcript under `~/.claude*/projects`: 6,914 files, 161,701 responses and 1,012 tasks (session trees). Prices are Opus 5.5 list prices as the brief gave them: $5/MTok input, 5m write 1.25x, 1h write 2x, cache read 0.1x, $25/MTok output, 2.5 chars per token. Script: `r16-scan.py` (numbers `r16-scan.json`; the 2 MB raw dump `r16-scan.raw.json` is written by the script and not committed).

## 1. How often the model re-reads output that was persisted today (>30k chars)

| | n | saved file re-read ≤3 turns | ≤10 / ever | chars re-read (mean, when re-read) | any recovery ≤3 turns | inline 16-30k baseline | excess over baseline |
|---|---:|---:|---:|---:|---:|---:|---:|
| all persisted Bash results | 1,094 | **21.9%** | 22.0% / 22.1% | 26,191 (file mean 121k) | 60.7% | 36.2% | **24.5%** |
| deliberate reads (cat/sed/head/tail/grep/rg, git show/diff/log) | 460 | 28.7% | 28.7% / 28.9% | 33,448 | 70.2% | 36.5% | 33.7% |
| everything else | 634 | 17.0% | 17.2% / 17.2% | 17,321 | 53.8% | 35.7% | 18.1% |
| results ≤60k only (the stratum closest to the band) | 648 | 28.9% | | | 69.4% | 36.2% | 33.2% |

- **"Saved file re-read"** is the brief's definition. A later Read, Grep or Glob on the saved path, or a Bash command naming it, counts.
- **"Any recovery"** also counts two other things. One is a later read-type call naming a file or URL that the original command named, i.e. re-reading the source rather than the saved copy. Sampling showed this is the model's main recovery path. For example, a persisted `sed -n '81,260p' X.md` was followed by three `awk 'NR>=…' X.md` calls. The other is a re-run of the same command with a filter appended; the strict prefix test found 0 of these.
- **The baseline** is the same "any recovery" test applied to the 1,944 inline 16-30k results, which were never persisted. 36% of them get their source re-touched within 3 turns anyway, so that share is not caused by persistence.
- **"Excess"** is any recovery minus that baseline. It is the causal estimate.
- The preview the model sees measured 2,167 chars on average, including the wrapper and path.

## 2. The 16,000-30,000 band (inline today)

| kind (leading program) | n | chars | later requests (mean) | of which cache reads | mean weight (input-price units) | exempt from 0039 |
|---|---:|---:|---:|---:|---:|---:|
| file_read (cat/sed/head/tail/grep/rg/awk…) | 1,189 | 24.94M | 42.5 | 40.0 | 7.49 | 1,189 |
| git_read (show/diff/log/blame) | 49 | 0.97M | 50.6 | 48.3 | 8.11 | 49 |
| build_test | 22 | 0.45M | 83.3 | 80.2 | 13.45 | 19 |
| other (scripts, curl, python, ps…) | 684 | 14.37M | 42.6 | 40.3 | 7.54 | 439 |
| **all** | **1,944** | **40.73M** | **43.2** | **40.8** | **7.59** | **1,696 (87%)** |

- By context: main 403, subagent 259, workflow agents 1,282.
- **Weight** is the first write (1.25x or 2x) plus 0.1x for each later cache read, plus a rewrite multiplier for each later request whose `cache_read` fell below the prompt size at which the result first appeared.
- **What 0039 does to the band.** 1,696 results are exempt because the hook's read regex matches anywhere in the command, including `| grep` and `| tail`. It offloads 153 below 16k. It offloads 4 whose preview is still over 16k. It leaves 91 alone because they are 110 lines or fewer.

## 3 and 4. Net effect per 14.96 days, without and with 0039

The model:

- **Saving** = (chars − 2,167) / 2.5 × weight × $5/MTok.
- **Cost** = rate × [re-read tokens × the same weight + one extra turn at a full-context cache read (the context size when the result first appears, 179k tokens on average) + 150 output tokens].
- **Re-read tokens** are either the empirical fraction of the file that was re-read ("frac") or the whole result ("full").
- **The rate** is stratified into deliberate reads and the rest.

| rate used | 0039 | n | saving $ | cost $ | **net $** | extra turns | % of all turns | mean % per task | projected band rate |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| saved-file (brief), frac | off | 1,944 | 554 | 130 | **+424** | 476 | 0.29% | 0.17% | 24.5% |
| saved-file (brief), full | off | 1,944 | 554 | 195 | **+359** | 476 | 0.29% | 0.17% | 24.5% |
| excess, full (central) | off | 1,944 | 554 | 223 | **+331** | 545 | 0.34% | 0.19% | 28.0% |
| excess, full, ≤60k stratum | off | 1,944 | 554 | 276 | **+277** | 675 | 0.42% | 0.24% | 34.7% |
| saved-file (brief), full | on | 1,791 | 523 | 187 | **+337** | 449 | 0.28% | 0.16% | 25.1% |
| excess, full (central) | on | 1,791 | 523 | 215 | **+309** | 517 | 0.32% | 0.18% | 28.9% |
| excess, full, ≤60k stratum | on | 1,791 | 523 | 265 | **+259** | 636 | 0.39% | 0.23% | 35.5% |
| worst: any recovery, full, no baseline | off | 1,944 | 554 | 512 | +42 | 1,249 | 0.77% | 0.45% | **64.2%** |
| worst, ≤60k stratum | on | 1,791 | 523 | 537 | **−14** | 1,286 | 0.80% | 0.48% | **71.8%** |

- **0039 barely overlaps rank 16.** Its read regex exempts 87% of the band, so rank 16 keeps about 94% of its saving when 0039 is on.
- **The per-task tail.** Under the central case, 52 of 1,012 tasks gain more than 1% extra turns. The worst of them gains 12.7%; these are short main sessions (4-67 turns) that hold several band-sized reads.
- Every row is in `r16-scan.json` under `leg3`. The file also has the "frac" variants and the ≤60k ("near") variants.

## Verdict under the rule

1. **Net saving with and without 0039: passes** in every baseline-corrected and brief-definition row, from +$259 to +$424. It fails only in the ≤60k worst case (−$14).
2. **Extra turns per task under 1%: passes** in every row. The largest aggregate is 0.80% of turns, and the largest per-task mean is 0.48%.
3. **Band re-read rate at most 50%: passes** in every baseline-corrected and brief-definition row (24.5% to 35.5%). It **fails** in the worst case (64-72%). That case counts every source re-touch as caused by persistence, although 36% of inline results get the same re-touch anyway.

**Why the conviction is 70% and not higher:** the band's re-read rate is transferred from results over 30k chars. Band results are smaller, so the preview shows 7-13% of them, against 4% at the median result over 30k (51k chars). The ≤60k stratum shows the rate rising, not falling, as results get smaller (28.9% against 21.9%). If the true band rate sits near the no-baseline figure, legs 1 and 3 fail. Per the TEST_PLAN, an A/B over a few accounts that watches `persisted` follow-ups within 3 turns would settle it.

## Limits

- **Pricing.** The brief's Opus 5.5 prices ($5/MTok, cache read 0.1x) differ from the extract's `price` table ($4/MTok, 0.05x). Saving and cost are both dominated by cache reads, so the other price set scales both roughly 0.4-0.5x and leaves their sign alone.
- **Version mix.** 92% of the persisted population ran on 2.1.260 (1,009 of 1,094). The mechanism is assumed to behave the same on 2.1.280, which has 85 persisted results. 7 results over 30k were not persisted; they are all 2.1.260 heredoc-writing commands (`cat > file`, `mkdir -p … &&`).
- **Recovery detection is lexical.** It matches file and URL tokens and the saved basename. A recovery made by a different route is missed, for example a re-run with changed arguments, or asking a subagent. A source re-touch that has nothing to do with the output is counted, and the baseline is what corrects for that. Parallel tool calls are charged a full extra turn each, which is conservative.
- **Dedupe.** Responses are deduped by `message.id` and results by `tool_use_id`, with the first file in mtime order winning. That gives 161,701 responses, 0.4% below the extract's 162,406. A result copied into a resumed file still accrues that file's new requests. A `compact_boundary` ends a result's life. Context-management clearing inside a segment is not modelled, so the saving is an upper bound.
- **What the replay cannot see.** It does not observe answer quality directly; extra turns are the only quality proxy measured. The 150 output tokens per extra turn is assumed.
