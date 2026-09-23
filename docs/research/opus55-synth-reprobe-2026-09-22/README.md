# Opus 5.5 synthesis-worker re-probe (2026-09-22): INCONCLUSIVE, because the tool conditions were unequal

**Verdict: INCONCLUSIVE.** It is neither ADOPT B/C nor KEEP A for `roles.workflow_synthesis_worker`.
**Conviction: 85% that this run cannot certify either direction.** That rests on a defect that was
measured, not hypothesised. The brief allowed "Read, Grep, Glob, no Bash". But **the Grep and Glob
tools do not exist in Workflow subagents on 2.1.280**: every call returned
`No such tool available: Grep … search file contents with grep via the Bash tool instead`. The arms
split on that:

- Sonnet 5 (A) followed the harness hint and ran read-only `grep`/`sed -n` through Bash, 6–14 calls
  per cell in 5 of 6 cells.
- Opus 5.5 (B, C) obeyed the brief and worked from `Read` alone, with **no search capability at all**.

So the "same tools" condition failed, and it failed in the incumbent's favour. One sample per cell;
recall against the key and judged quality are the only measures.

**What the data does say.** It is directional, and it was measured under that handicap:

- **C = Opus 5.5 @xhigh vs A = Sonnet 5 @max.** C wins 3 briefs (T2, T4, T5), loses 1 (T6), ties 1
  (T1), and T3 has no majority.
  - C makes fewer wrong claims (25 vs 55 judge-flagged) and has fewer bad citations (3.6% vs 5.1% of
    those checked).
  - C has the higher mean score: 7.83 vs 7.33.
  - A leads on key recall, 88.5% vs 83.1%. The gap is concentrated in T6, the find-every-site brief
    (15/15 vs 10/15), which is the brief a Read-only worker can least answer.
  - The judges' reasons attribute A's advantage to exhaustive repo-wide discovery, which is exactly
    what search buys. They attribute C's advantage to correctness: A repeated stale comments as fact
    (T4) and asserted a false exclusivity (T5).
- **B = Opus 5.5 @high vs A.** 3–3. Each of B's three losses (T1, T3, T6) was unanimous. The judges
  cite coverage: B "left [items] UNVERIFIED ('six guessed names returned does not exist')", i.e. it
  was guessing paths without a find tool.
- **C vs B.** C wins 5 briefs and ties 1. Effort buys synthesis quality on this class, at ~2.1× B's
  output tokens.

Directional convictions, pending the settle run: **65%** that C ≥ A at equal tools, and **50%** on
B vs A. Neither clears the 90% bar.

**What settles it.** Run [`instruments/settle-run.js`](instruments/settle-run.js) on the same frozen
corpus, judges and permutations. Its only change is one working, equal tool rule for all three
arms: Read, plus Bash for read-only search. That is the real production condition of a Workflow
synthesis worker on 2.1.280, where Grep and Glob are absent. Cost: 18 arm cells + 18 judges, ≈9.2M
subagent tokens, the size of this run. It exceeds this session's frozen budget of 18 arm cells, so
it was not run here (brief § STOP ON ISSUE). Setup is in § Settle run.

## Results

Strict-majority pairwise verdicts over 3 blind judges. The bracket shows the three judges' calls
in order J0, J1, J2.

| Brief | Hard | A vs B | A vs C | B vs C | Majority recall A / B / C |
|---|---|---|---|---|---|
| T1 custody lifecycle | yes | **A** [A,A,A] | tie [tie,tie,C] | **C** [C,C,C] | 16 / 13 / 16 of 21 |
| T2 recycle /goal inheritance | yes | **B** [B,B,B] | **C** [C,C,C] | **C** [C,tie,C] | 24 / 23 / 23 of 25 |
| T3 frontier spawn budget | yes | **A** [A,A,A] | no-majority [C,A,tie] | **C** [C,C,C] | 26 / 28 / 27 of 32 |
| T4 session-continue Stop arms | yes | **B** [B,B,B] | **C** [C,C,C] | **C** [C,C,C] | 20 / 20 / 20 of 20 |
| T5 deploy-live exec sites | yes | **B** [tie,B,B] | **C** [C,C,C] | **C** [C,C,C] | 14 / 12 / 12 of 17 |
| T6 Stop-blocking emissions | yes | **A** [A,A,A] | **A** [A,A,A] | tie [tie,tie,tie] | 15 / 10 / 10 of 15 |
| **Tally** | 6/6 | **A 3 · B 3** | **C 3 · A 1 · tie 1 · no-maj 1** | **C 5 · tie 1** | **115 (88.5%) / 106 (81.5%) / 108 (83.1%) of 130** |

**Majority recall** counts a key item as hit when at least 2 of the 3 judges marked it. Other
columns, summed over all judges:

| Arm | Bad citations / citations checked | Wrong claims | Mean score (1–10) |
|---|---|---|---|
| A Sonnet 5 @max | 32 / 630 (5.1%) | 55 | 7.33 |
| B Opus 5.5 @high | 14 / 633 (2.2%) | 29 | 6.94 |
| C Opus 5.5 @xhigh | 25 / 696 (3.6%) | 25 | 7.83 |

Panel agreement: 14 of 18 pair verdicts were unanimous. The four split ones divide across judge
models with no single-model pattern. Per-judge detail is in `instruments/tally.txt` and `judges/`.

## Cost, in the quota currency

Deduped per `message.id` from the Workflow's own transcripts. Every assistant record carries
`usage`. Cache reads are shown for completeness; they draw ≈0 quota.

| Arm | Output tokens (6 cells) | cache_creation | cache_creation net of the fixed turn-1 prefix* | cache_read |
|---|---|---|---|---|
| A Sonnet 5 @max | 207,508 | 1,252,787 | ≈0.58M | 17.6M |
| B Opus 5.5 @high | 123,932 | 1,796,299 | ≈1.15M | 25.9M |
| C Opus 5.5 @xhigh | 254,235 | 2,168,188 | ≈1.52M | 24.9M |

\* Every cell pays a ~108–112K-token cache_creation prefix on turn 1: the injected CLAUDE.md and the
rules, measured in the pin check.

- **Output tokens:** B uses 0.60× of A's, and C uses 1.23× of A's.
- **cache_creation:** Opus's larger figure is partly the same confound. A worker without search
  `Read`s whole file ranges into context, where `grep` returns a few lines.
- **Conversion to weekly points is not possible from what this fleet has measured:**
  - Per-token quota weights for Sonnet 5 and Opus 5.5 are not measured here. The Opus 5.5 meter
    read is in flight on `next4`.
  - The only fleet coefficient is Opus 5's price list: ~360K output tokens/[W-pp] and ~3.4M
    cache_creation tokens/[W-pp] (`docs/research/opus55-utilization-2026-09-22/census/L2b-quota-effort-method.md`).
  - At that one weight for every arm: A ≈ 0.94, B ≈ 0.87, C ≈ 1.34 [W-pp] for 6 cells.
  - Sonnet's true weight is lighter, and 0.75× if the meter tracks list output price, which is
    unverified; that puts A ≈ 0.71.

## Method

- **Repo pin.** `47c3317eb90bca9bf7f0fcbd8adb7651110da705`, exported with `git archive` to
  `/tmp/o55probe-repo-47c3317eb`: 3,743 files, equal to `git ls-files`. Arms and judges read only
  that snapshot. It predates this directory, so no key could leak into it.
- **Step 0, pin check** (`wf_77bc63e6-197`, `instruments/o55-synth-pincheck-*.js`). Every
  model+effort pin was honoured: each transcript's `.message.model` equals the requested id
  (`claude-sonnet-5`, `claude-opus-5-5` ×2, `claude-fable-5-1`, `claude-opus-5`).
- **Corpus** (`wf_9e75c0d7-bc5`, `instruments/o55-synth-corpus-*.js`):
  - Drafting: 6 key-drafters on `claude-opus-5` @xhigh. That model is not an arm, which keeps
    self-preference out of the keys. Each draft then went to an independent `claude-opus-5` @xhigh
    refuter.
  - Byte-check: I checked all 130 kept items (95 drafted + 35 refuter additions) with a script.
    Every quote is verbatim at its cited line.
  - Corrections: 4 imprecise items were annotated and 1 wrong claim corrected (T5 N4, the scheduled
    entry-point exclusivity).
  - Semantic spot-check against code: T2 K1–K4 and K9, T3 K7 and K10–K12, T4 k5 and k6, T5 S1, S2
    and S5. T6's site list matches an independent grep exactly: 10 qualifying emissions plus the 8
    PostToolUse near-misses in `hooks/waiting-recycle.sh`.
  - All 6 briefs meet the HARD bar: each spans ≥4 files and both drafter and refuter asserted
    `hard_ok`. T5 and T6 are find-every-site briefs with deliberate near-miss traps.
  - Frozen `2026-09-22T23:16:55Z`, before any arm ran; hashes in `corpus/corpus.sha256`.
- **Arms** (`wf_137eab40-244`, `instruments/o55-synth-reprobe-*.js`):
  - Prompt: one wrapper, identical for all arms. It reads the brief from a file, sets a saturation
    bound of 25 tool calls after the brief (the incumbent slot's mandated bound), and requires
    path:line for every claim.
  - Effort passed explicitly on every call; fresh context per cell.
  - Reliability: 18/18 cells completed, with 0 retries and 0 × 429.
- **Judges.** 3 per brief, blind, default-to-refute, with repo access. Each had to open ≥8 cited
  lines per output byte-for-byte.
  - Label permutation is per (judge, brief): `PERMS[(i*3+j) % 6]`, recorded as `label_map` in each
    judge file.
  - Fable 5.1 @high sat in one seat per brief (6 spawns, within `max_fable_spawns_per_session: 6`);
    the other seats were Opus 5 @xhigh.
  - Opus 5.5 never judged.
  - Verdicts: strict majority; a pair with no two agreeing judges is "no-majority".
- **Tools actually used per cell** (`instruments/usage-per-cell.json`):
  - A: Bash in 5 of 6 cells, all read-only. The full command list is recoverable from the
    transcripts; none writes.
  - B and C: `Read` only, plus one ToolSearch in T5.

## Settle run (what the lead fires to close this)

1. `mkdir -p /tmp/o55probe-repo-47c3317eb && git -C <checkout> archive 47c3317eb | tar -x -C /tmp/o55probe-repo-47c3317eb`
   (the pinned tree; it predates this directory, so it holds no keys).
2. `mkdir -p /tmp/o55-briefs && cp corpus/briefs/*.md /tmp/o55-briefs/`. The briefs live outside
   the repo so that the arms are never pointed at `corpus/keys/`.
3. Run `instruments/settle-run.js` as a Workflow. Relative to the probe it changes exactly one
   line, the arm tool rule: Read, plus Bash for read-only search, stay inside the snapshot. The
   judges read the keys from this directory's `corpus/keys/`.
4. Tally with `instruments/usage.py <workflow transcript dir>` and the same majority rule.
5. Decide by the lexicographic rule in `~/.claude/model-routing-freewin-probe.md` § Purpose.
6. Keep the same account constraints: not `next4`, not `~/.claude-tertiary`.

Residual risk to watch: an arm with Bash can reach the live checkout, which now contains these keys.
Grep each arm transcript for `opus55-synth-reprobe` before scoring it.

## Files

- `corpus/`: `briefs/` (the exact text the arms read), `keys/` (the text the judges read),
  `corpus-final.json` (keys with file, line, quote and provenance), `corpus.sha256`, `frozen-at.txt`.
- `arms/<brief>-<A|B|C>.md`: the 18 raw worker outputs, verbatim.
- `judges/<brief>-J<n>.json`: 18 judge records, with model, effort, `label_map` and the full
  structured verdict.
- `instruments/`: the three Workflow scripts as run, `settle-run.js`, `usage.py`,
  `usage-per-cell.json` and `tally.txt`.

## Settle run — results

**Verdict: ADOPT C, Opus 5.5 @xhigh, for `roles.workflow_synthesis_worker`.
Conviction: 85%.** That number is two separate calls:

- **≥95% that A (Sonnet 5 @max) should be replaced.** At equal tools, C beats A 5–1 in the primary
  scoring and 6–0 in the sensitivity scoring. The Fable seats alone give 6–0. C's key recall is
  98.5% vs 89.2%, and it makes about a third of A's wrong claims (18 vs 52).
- **~80% that C beats B (Opus 5.5 @high).** C wins the pairwise 4–2 in the primary scoring and ties
  3–3 in the sensitivity scoring. But every other quality measure favours C in both scorings:
  recall, bad-citation rate and mean score.

Under the lexicographic rule, B at lower quality by any margin is a reject. C being cheaper than A
in tokens makes C a double win over A, not a trade.

**The one change held.** Every arm, Opus included, searched with read-only Bash inside the
snapshot: 106–129 Bash calls per arm over 6 cells. So the confound that made the first run
INCONCLUSIVE is gone. This is the production condition of a Workflow synthesis worker on 2.1.280.

### Equal-tools results

Strict majority over 3 blind judges, same briefs, keys, permutations and rule as § Results.

**Primary scoring.** The 13 clean run-1 cells, plus the 5 re-run cells, with T3–T5 re-judged.

| Brief | A vs B | A vs C | B vs C | Majority recall A / B / C |
|---|---|---|---|---|
| T1 custody lifecycle | **B** [B,B,B] | **C** [C,C,C] | **B** [B,B,B] | 17 / 21 / 21 of 21 |
| T2 recycle /goal inheritance | **B** [B,B,B] | **C** [C,C,C] | **C** [C,C,C] | 23 / 23 / 25 of 25 |
| T3 frontier spawn budget | tie [tie,B,tie] | **C** [C,C,C] | **C** [C,C,C] | 27 / 30 / 32 of 32 |
| T4 session-continue Stop arms | **B** [B,B,B] | **C** [C,C,C] | **C** [C,C,C] | 18 / 19 / 20 of 20 |
| T5 deploy-live exec sites | **B** [tie,B,B] | **A** [A,A,C] | **B** [B,B,tie] | 16 / 16 / 15 of 17 |
| T6 Stop-blocking emissions | **B** [B,B,B] | **C** [C,C,C] | **C** [C,C,C] | 15 / 15 / 15 of 15 |
| **Tally** | **B 5 · tie 1** | **C 5 · A 1** | **C 4 · B 2** | **116 (89.2%) / 124 (95.4%) / 128 (98.5%) of 130** |

| Arm | Bad citations / checked | Wrong claims | Mean score | Output tokens | cache_creation | **Output + cache_creation** |
|---|---|---|---|---|---|---|
| A Sonnet 5 @max | 70 / 546 (12.8%) | 52 | 6.72 | 135,868 | 1,265,293 | **1,401,161 (1.00×)** |
| B Opus 5.5 @high | 70 / 604 (11.6%) | 24 | 7.89 | 66,517 | 924,452 | **990,969 (0.71×)** |
| C Opus 5.5 @xhigh | 33 / 632 (5.2%) | 18 | 8.44 | 85,532 | 981,609 | **1,067,141 (0.76×)** |

**Sensitivity scoring.** All 18 run-1 cells, including the 5 string-positive cells, judged by the
original seats. The lead required this; the tool-level check is the stronger instrument (see
Deviations).

- Pairwise: A vs B = **B 6**; A vs C = **C 6**; B vs C = **B 3 · C 3**.
- Recall: 116 (89.2%) / 125 (96.2%) / 128 (98.5%) of 130.
- Bad citations: 15.4% / 10.6% / 6.8%.
- Wrong claims: 56 / 21 / 21.
- Mean score: 6.50 / 8.17 / 8.39.
- Output + cache_creation: A 1,380,340 · B 1,016,164 (0.74×) · C 1,089,772 (0.79×).

Both scorings agree that C and B beat A. They differ only on B vs C, which is why that half of the
verdict carries 80% rather than 95%.

**Against the first run.** Search moved the Opus arms, not Sonnet.
- A's recall is flat: 88.5% → 89.2%.
- B's recall rose 81.5% → 95.4%, and C's rose 83.1% → 98.5%.
- The one brief A had won on discovery was T6, the find-every-site brief. With search, A drops from
  15/15 vs 10/15 to 15/15 across all three arms, and loses T6 to both Opus arms unanimously.
- A's bad-citation rate there is 27/82.
- Token use changed too. Without search, C cost 1.23× A's output; with it, C costs 0.63×.

### What it cannot tell

- **Sample size.** It is one sample per cell, over 6 briefs from one repo and one task class:
  repo-grounding synthesis with path:line citations. It says nothing about open-web research
  synthesis.
- **Weekly quota points.** Tokens cannot be converted to quota points, because per-token quota
  weights for Sonnet 5 and Opus 5.5 are unmeasured here (see § Cost). Sonnet's weight is likely
  lighter, so A's token-cost disadvantage may shrink or reverse in quota points. That does not
  change the verdict, because quality decides first.
- **Judge family.** 15 of 18 primary seats are Opus 5, the same family as arms B and C. The Fable
  seats alone agree on direction (B and C each beat A 6–0), but that check covers only 6 seats.
- **Bad-citation rates.** They rose for every arm against the first run (A: 5.1% → 12.8%). The cause
  was not isolated, so compare the rates only within this run.

### Deviations (recorded, not hidden)

1. **Cwd leak, my harness error.** Workflow agents inherit the session's cwd at spawn. A Bash `cd`
   left this session sitting in the probe directory, so 5 arm cells were spawned with it as their
   working directory: T3:C, T4:A, T4:B, T4:C and T5:A. The path `opus55-synth-reprobe` therefore
   appeared in their injected context, as cwd and as git status. It was also in 0 of the other 13.
   - Tool-level check: every tool call in all 5 cells targeted the snapshot or the harness's own
     overflow files. No tool input or result carried key text.
   - The brief's mechanical rule still applied: all 5 were re-run once from the worktree root with a
     clean tree (`wf_a8c18432-bb3`). All 5 re-runs are string-clean.
   - The originals are kept in `settle/arms-string-positive/` and scored only in the sensitivity arm.
2. **Seat swap.** The re-judges of T3, T4 and T5 needed 3 Fable 5.1 seats. Run 1 had already spent
   this session's `max_fable_spawns_per_session: 6`. The Workflow tool does not gate on that cap,
   but that is no licence to exceed it. On the lead's ruling, those 3 seats were filled by
   `claude-opus-5` @xhigh (`wf_9380a9b0-f89`, `noFable`). Permutations and the other seats are
   unchanged.
3. **Budget.** Spend was 7.11M tokens for run 1 (`wf_e43f474d-ad0`), 0.99M for the re-runs and
   2.09M for the re-judges: 10.19M in total against the ≈9.2M estimate. The overage is the re-run of
   deviation 1.
   - 36 + 5 + 9 agents, all completed.
   - 0 errors, 0 × 429, 0 retries. Every arm transcript's `.message.model` was the requested id.

### Settle files

Everything below is in `settle/`:

- `arms/`: the 18 scored outputs, with provenance in each header.
- `arms-string-positive/`: the 5 replaced originals.
- `judges/`: the primary set, run-1 records for T1, T2 and T6 plus the re-judges.
- `judges-run1/`: all 18 original-seat records, used for the sensitivity scoring.
- Tallies: `tally-primary.txt` and `tally-sensitivity.txt`.
- Per-agent usage: `usage-{run1,rerun,rejudge}.json`.
- Tools:
  - `tally.py` reproduces § Results exactly when run on `../judges`: 115/106/108, 55/29/25.
  - `contam.py` is the key-string and outside-snapshot scan.
  - `extract.py` writes a Workflow's return value out to files.
  - `settle-rejudge.js` is the re-run/re-judge driver as run, with the kept texts embedded
    byte-exact. Its prompts are byte-identical to `instruments/settle-run.js`.
