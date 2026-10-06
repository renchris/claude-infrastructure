# E1h slot: stronger-model trial, LIVE, on tuning set v1 only (2026-10-06)

Question: would a stronger classifier model with thinking off (claude-sonnet-5-5), or haiku with a
precision-tightened brief, cut over-flagging (relay labels on ordinary prompts) while keeping relay recall
and fitting the 9 s limit?

**Read this first: tuning v1 overstates `other`, and it cannot show the v3 failure at all.** The live fast
call (haiku, thinking off, E1b brief) gave relay labels to 26 of v3's 148 agreed `other` prompts. On tuning v1's
21 agreed `other`-stratum rows with non-relay gold, every thinking-off arm, including that same fast call,
relays **0 of 21** (E1c reps 1 and 2 and this run). The `other` measure here has no power on the failure mode. The
only over-flagging signal v1 carries is on its *hard negatives*: the 56 rows (all strata) where **neither**
rater gave a relay label. Most of them sit in the regex-matched and regex-missed strata, so they are prompts
that look like re-asks. The over-flagging findings below rest on those 56 rows. That transfer to v3's `other`
stratum is an assumption, not a measurement.

## What was run

- Harness: `/tmp/e1h-research/stronger-model-live.py`, scorer `/tmp/e1h-research/stronger-model-score.py`,
  union replay `/tmp/e1h-research/stronger-model-union-replay.py`. Per-call data, keyed by tuning row index
  with no prompt text: `/tmp/e1h-research/stronger-model-live-calls.json`. Scorer output:
  `stronger-model-live-score.txt`. Replay output: `stronger-model-union-replay.txt`.
- The command line is built from the live `router.py` `classifier_flags("fast")`: `claude -p --model <m>
  --setting-sources local --tools '' --strict-mcp-config --no-session-persistence --disable-slash-commands
  --system-prompt <E1b system> --settings '{"alwaysThinkingEnabled":false}'`. Only `--model` is swapped. The
  prompt goes in on stdin, the call runs from an empty temp dir with `CC_RESEARCH_ROUTER_INNER=1`, and each call
  gets 30 s. The brief is the live `FAST_BRIEF`, asserted byte-equal to E1b's patch composition. Label and wall
  time are recorded apart, as `e1c-tune.py` does.
- Arms, 96 tuning rows x 1 rep each, **strictly sequential**: one call at a time, with the four arms run back
  to back for each row so they see the same load window:
  1. `sonnet-off-e1b`: claude-sonnet-5-5, thinking off, E1b brief (the brief's main arm)
  2. `haiku-off-tight`: claude-haiku-4-5, thinking off, E1b brief plus precision notes. I wrote the notes
     before seeing any result, from ROUTE_DEFINITIONS, not fitted to tuning rows. They are in the JSON's
     `meta.tight_notes`.
  3. `haiku-off-e1b`: the live fast call, run as a same-moment control
  4. `sonnet-off-tight`: sonnet with the tightened brief
- When: 2026-10-06 01:07:29 to 01:22:51 CDT (925 s, 384 calls). The 1-min load ran from 19.2 to 160.2 (it
  spiked to about 130-160 mid-run and was 19-25 at the start). Measured by `os.getloadavg()` before each call.
- Scoring uses `e1c-choose.py`'s definitions (agreed = both raters equal; recall on agreed relay rows outside
  stratum `other`; `other` = exact label on agreed `other`-stratum rows; borderline = the 13 split rows where
  one rater said completeness or pushback; fallback = label not in ROUTES, or a timeout, or wall > 9.0 s).
  One rep means 26 recall calls, 22 `other` calls and 13 borderline calls. E1c's arms are shown per rep (rep 1)
  and over 2 reps.

## Results (measured: stronger-model-score.py on stronger-model-live-calls.json and E1c tune-2reps.json)

| arm | recall, agreed relay | `other`, agreed | relays on agreed-`other` non-relay rows | **relays on the 56 neither-relay rows** | borderline relays | fallback at 9 s | wall median / p90 / max (cold) |
|---|---|---|---|---|---|---|---|
| **sonnet-off-e1b** (this run) | 25/26 = 0.96 | 22/22 | 0/21 | **1/56** (row 10 only) | 7/13 | 1/96 (20.4 s) | 2.77 / 4.71 / 20.38 s |
| sonnet-off-tight (this run) | 25/26 = 0.96 | 21/22 (1 INVALID, rc 1) | 0/21 | **1/56** | 5/13 | 1/96 (INVALID) | 2.92 / 4.37 / 6.29 s |
| haiku-off-tight (this run) | 25/26 = 0.96 | 21/22 | 0/21 | 5/56 | 5/13 | 0/96 | 1.71 / 2.49 / 3.36 s |
| haiku-off-e1b = live fast call (this run, control) | 26/26 | 22/22 | 0/21 | **8/56** | 5/13 | 0/96 | 1.50 / 2.40 / 3.08 s |
| E1c off-e1b, rep 1 (2026-10-04) | 26/26 | 22/22 | 0/21 | 9/56 | 6/13 | 1/96 | 1.60 / 2.11 / 10.1 s |
| E1c off-e1b, rep 2 | (2 reps: 51/52) | (2 reps: 44/44) | 0/21 | 6/56 | (2 reps: 10/26) | (2 reps: 1/192) | (2 reps: 1.70 / 2.32 s) |
| E1c on-pre (thinking on, as-built careful), rep 1 | 26/26 | 20/22 | 1/21 | 10/56 | 10/13 | 16/96 | 5.47 / 10.19 / 18.43 s |
| E1c on-pre, rep 2 | (2 reps: 51/52) | (2 reps: 40/44) | (2 reps: 2/42) | 7/56 | (2 reps: 21/26) | (2 reps: 33/192) | (2 reps: 5.66 / 10.86 s) |

All three columns of over-flag counts are relay labels given to rows whose agreed or both-rater label is not a
relay. Agreed-relay "relays on all agreed non-relay rows" (42 rows) read 1/42 for all four arms in this run.
That one row is row 10, gold `new-idea`, which every arm and every rep labels completeness.

### Over-flagging: sonnet cuts it sharply on the only rows that show it

- **Measured.** On the 56 rows neither rater calls a relay, the haiku fast call relays 8, 9 and 6 of them in
  three separate runs (this run's control, E1c rep 1 and rep 2). The same rows recur every time (35, 37, 49, 51,
  56, 57, mostly regex-missed), so this is systematic, not noise. Sonnet thinking off relays **1/56** with either
  brief, and that one is row 10, which every arm relays. Paired on the same rows in the same window: 7 rows are
  relayed by haiku and not by sonnet, and 0 the other way round. **Estimated:** exact sign-test p ≈ 0.016 (2 x
  0.5^7).
- **Measured.** Haiku with the tightened brief cuts this only to 5/56 and costs one recall call (row 46). It also
  costs one exact `other` (row 90, research-order to other). Wording again does much less than the model change.

### Recall and sensitivity

- **Measured.** Sonnet misses one agreed relay row (row 29, regex-missed, gold completeness; sonnet says
  `other`). On n = 26, 25/26 = 0.96 is exactly at the 0.95 bar, so one more miss on a bigger set fails. Haiku-off
  also gets row 29 "wrong" in substance (pushback / research-order), but pushback happens to count as a relay.
- **Measured.** Borderline relays: sonnet-off-e1b 7/13, against haiku-off 5-6/13 and thinking-on on-pre 10/13.
  Sonnet is no worse than haiku thinking off on the subtle completeness and pushback prompts, but it does not
  reach thinking-on. E1g's bar was 17/26, which is 8.5 of 13 per rep.
- Single rep, so per-row noise is visible. E1c measured 10-25 of 96 rows flipping label between reps.

### Latency (fits 9 s cold, with a tail)

- **Measured, cold, sequential.** Sonnet-off median 2.77 s, p90 4.71 s. 6 of 96 took over 5 s (at loads
  51-132). One call took 20.38 s at load 23.1, an API tail, not load: it is the 1/96 fallback. Sonnet-tight
  had one INVALID (rc 1 after 1.84 s, an error exit, also a fallback). Haiku-off in the same window: median
  1.50 s, p90 2.40 s, max 3.08 s, none over 5 s.
- **Measured, paired per row.** Sonnet minus haiku (same row, same minute): median +1.20 s, p90 +2.62 s.
- **Warm estimate, the brief's method** (cold wall minus 2-4 s cold start): sonnet median 0-0.8 s, p90
  0.7-2.7 s. **Caveat:** this run's haiku cold calls finished in 1.11-3.08 s *in total*, so the cold-start
  overhead today is at most about 1.1-1.5 s, and subtracting 2-4 s understates warm latency.
- **Warm estimate, a second method** (warm haiku fast relay latency plus the paired sonnet-haiku gap): the v3
  read's trace (`reading-v3-2026-10-05.paths.jsonl`, labels only) shows the resident fast call's relay answers
  at median 0.54 s and p90 0.83 s (n = 126). Adding the paired gap gives warm sonnet ≈ 1.7 s median and ≈ 3.5 s p90.
  This assumes the gap is additive. Either way it fits well inside 9 s, and inside 8.5 s.

### Union replay (estimate: offline, E1g's join rule, fast = this run's arm, careful = E1c's on-pre calls from 2026-10-04)

| fast arm + on-pre careful | recall | `other` | borderline | relays on 56 neither-relay rows (by fast / by careful) |
|---|---|---|---|---|
| haiku-off-e1b (= E1g as built) | 26/26 | 21-22/22 | 9-10/13 | 10/56 (8 / 2) |
| haiku-off-tight | 26/26 | 20-21/22 | 9-10/13 | 8/56 (5 / 3) |
| sonnet-off-e1b | 26/26 | 21-22/22 | 10-11/13 | **6/56 (1 / 5)** |
| sonnet-off-tight | 26/26 | 21-22/22 | 9-10/13 | 6/56 (1 / 5) |

(The ranges cover the two on-pre reps.) **Estimated.** With sonnet as the fast call, the union keeps recall at
26/26 (the careful call catches row 29) and gains borderline. But the careful call (thinking-on haiku) then
over-flags the rows the fast call no longer relays: from 2 to 5 of 56. Thinking-on on-pre over-flags 10/56 and
7/56 on its own, as much as haiku-off does. On v3 that is the 10 careful relays seen, plus whatever the haiku
fast call's 26 relays were masking. **A sonnet fast call cuts the union's over-flagging by about 40% on v1's hard
negatives (10 to 6 of 56), not by 85%.** The careful arm becomes the main leak.

## Answer to the slot's question

- **Yes for the model itself.** On v1, Sonnet 5.5 with thinking off is the only configuration tried here that
  nearly stops over-flagging re-ask-looking prompts: 1/56, against 8/56 for the live haiku fast call in the same
  window. It holds `other` (22/22), keeps borderline sensitivity at or above haiku-off (7/13), and fits 9 s with
  a wide margin (cold median 2.8 s, warm about 1.7 s estimated).
- **Cost:** recall 25/26, exactly at the bar on a small n. A cold-path tail of 1 in 96 over 9 s (20.4 s), plus
  1 error exit in the sister arm.
- **The precision-tightened haiku brief does little** (8 to 5 of 56) and costs one recall call and one `other`
  call.
- **In the E1g union, swapping only the fast call is not enough** (estimated 10 to 6 of 56), because the
  thinking-on careful call over-flags on its own.

## Caveats (stated plainly)

1. **Tuning v1 overstates `other`.** Every thinking-off arm is 0/21 there, while the live fast call relayed
   26/148 on v3. v1's `other` rows cannot detect the failure. The 56 neither-relay rows are mostly
   regex-stratum prompts, and whether sonnet's precision on them transfers to v3's `other` stratum is unmeasured.
2. One rep, n = 26 recall, 22 `other` and 13 borderline calls. Recall 25/26 versus 26/26 is one row.
3. Load ran from 19 to 160 during the run. Arms were interleaved per row, so the comparisons are same-window,
   but absolute walls at load 130-160 are slower than a quiet machine.
4. The union replay mixes this run's fast calls with E1c's 2-day-old cold careful calls (load 28-46). It is an
   estimate, not a live measurement.
5. claude-sonnet-5-5 printed an "unrecognized model / catalog" warning on stderr from this CLI version. stdout
   carried the label, so it did not affect the parse, but the warm daemon should be checked for the same.
6. Sonnet's per-call cost and rate limits are higher than haiku's. Not measured here.
7. Deviations: I did not run `git pull`. `git fetch` showed HEAD already equal to `origin/main` (ff3e87fb7),
   so the pull would have been a no-op, and pulling is a git mutation my worker rules forbid. I added two arms
   beyond the brief (the same-moment haiku control and sonnet-tight) so the comparison shares one load window.
   No tracked file was edited, nothing was committed, and no sealed set, key, `tuning-v2.jsonl` or miner
   output was read. `/tmp/e1h-research/cands.jsonl`, another worker's file, was not opened.
