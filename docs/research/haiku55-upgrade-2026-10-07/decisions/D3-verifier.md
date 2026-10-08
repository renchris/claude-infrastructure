# D3 — bounded verifiers: Haiku 5.5 against Opus 5.5 (2026-10-07, binary 2.1.293)

## Recommendation

Keep Opus 5.5 as the default for verifier and judge slots, and admit **Haiku 5.5 at medium** for one
narrow class only: checking a claim that cites a line against a source file inlined in the prompt
(no tools, one file, up to about 330 lines). On that class Haiku 5.5 passed zero false claims in 60
tries at either rung, the same as Opus 5.5, and no arm can be told apart from another. The test
sits at ceiling, so it shows Haiku 5.5 is not worse here; it does not show the two models are equal
on harder checks, and it says nothing about judges. Conviction in this recommendation: 80%.

Rung: medium. High bought nothing measurable (0 of 60 false accepts at both) and spent 45% more
output tokens (11,300 against 7,809 over 20 calls).

## Result

All numbers measured by `/tmp/haiku55-decisions/d3/score.py` over
`/tmp/haiku55-decisions/D3-verifier.rows.jsonl`, unless marked estimated. Each arm: 20 calls
(10 files x 2 reps), 120 claim verdicts (60 on true claims, 60 on false claims).

| Arm | Accuracy | False-accept (false claim passed) | False-reject (true claim refused) | Unscorable | Cited the right line (within 3) | Median output tokens per call | Total output tokens | Median wall (s) | Median API duration (s) | Served |
|---|---|---|---|---|---|---|---|---|---|---|
| claude-haiku-5-5 @medium | 119/120 | 0/60 | 1/60 | 0 | 120/120 | 431.5 | 7,809 | 5.0 | 2.4 | claude-haiku-5-5, 20 of 20 |
| claude-haiku-5-5 @high | 120/120 | 0/60 | 0/60 | 0 | 120/120 | 503 | 11,300 | 5.4 | 2.5 | claude-haiku-5-5, 20 of 20 |
| claude-opus-5-5 @medium | 120/120 | 0/60 | 0/60 | 0 | 120/120 | 150 | 3,816 | 5.1 | 2.2 | claude-opus-5-5, 20 of 20 |
| claude-opus-5-5 @high | 120/120 | 0/60 | 0/60 | 0 | 120/120 | 150 | 3,751 | 5.55 | 2.3 | claude-opus-5-5, 20 of 20 |

- **What 0 of 60 bounds.** The 95% Wilson upper bound on the false-accept rate is 6.0% for every arm
  (n=60 false-claim verdicts each). The data cannot rule out a true rate of a few percent for
  either model, and cannot rank them.
- **Sign test.** Paired on the 120 claim-reps, every pair of arms has at most one discordant pair
  (two-sided p = 1.0 for all six comparisons). The sign test cannot distinguish any arm from any
  other: not Haiku from Opus, not medium from high.
- **The one error.** Haiku 5.5 @medium, rep 2, `scripts/land-speed-census.py`: it refused the true
  claim "The store path falls back to ~/.claude/land.log when LAND_LOG is unset or empty (line
  279)". It got the same claim right in rep 1. A false reject is the cheap error for a verifier.
- **No row dropped.** 81 model calls, all served the model requested (read from `modelUsage` on
  every call), none errored, none refused, every reply parsed. 80 are scored; the 81st is a
  duplicate of one cell from the smoke run (identical verdicts; the scorer keeps the first).
- **Tokens and quota (estimated).** Haiku 5.5 @medium spent 2.05x the output tokens of Opus 5.5
  @medium (7,809 against 3,816, measured). At the record's 0.12x draw per output token (bounded
  0.055 to 0.19), that is about 0.25x Opus's plan-quota draw per check (0.11 to 0.39), estimated
  by multiplying the two. Wall time is the same for all arms: about 5 s per call including CLI
  start, about 2.3 s inside the API.
- **Effort did reach Haiku, not visibly Opus.** Haiku's output tokens rise from medium to high
  (431.5 to 503 median); Opus's do not (150 at both), so on this task the Opus rungs are in
  practice one arm.

## Method (five lines)

1. Ten files frozen from `claude-infrastructure` at `c3ed0a381` (`bin/cc-lid`, `bin/claude-bump-models`, `bin/cc-wait`, `scripts/scratchpad-reaper.sh`, `scripts/pool-floor.sh`, `scripts/branch-reaper.sh`, `scripts/fsevents-top.py`, `scripts/norm-share.py`, `scripts/research-kit/heldout-rate.py`, `scripts/land-speed-census.py`; 158 to 327 lines; sha256 in `d3/corpus.sha256`).
2. Six one-sentence claims per file, each with a line cite; a seeded RNG (20261007) shows three as written and three after one mechanical string substitution (30 false: 13 changed number, 10 negated or altered condition, 5 wrong default, 2 swapped name), and shuffles the order.
3. The key is fixed by a program before any model ran (`d3/build.py`, key frozen 2026-10-08T04:59:13Z, sha256 in `d3/key.sha256`, re-verified after the run): for all 60 it asserts that a code substring grounding the true claim is on the cited line and that the code the mutated claim would need is not.
4. One headless call per file per arm per rep on the 2.1.293 binary, account `~/.claude-next`, file inlined with line numbers, `--tools ""`, `--setting-sources ""`, from an empty temp directory, at most 4 in parallel; the reply is a JSON verdict per claim (`d3/run.py`, modeled on `measure/extraction/cell.sh`).
5. Scoring is exact match of verdict to key; an unparseable verdict would count as wrong (there were none); paired sign test per claim-rep; Wilson bounds on the two error rates.

Deviations from the brief: `--strict-mcp-config` was added to the command (as the record's own
`cell.sh` does) so no MCP tool could load. The first launch put the prompt after `--tools ""`, which
swallowed it; 14 launches exited with a usage error before reaching a model (0 model calls, rows
kept in `d3/launch-failures.jsonl`) and the argument order was fixed. Nothing outside
`/tmp/haiku55-decisions/` was written.

## Not settled

- **The test is at ceiling.** With every arm at 119 or 120 of 120 it cannot show where Haiku 5.5
  starts to fall behind. A harder set is needed to find that edge: claims with no line cite (the
  verifier must find the evidence), claims that need two lines read together, files over 1,000
  lines, several files at once.
- **Rates below 6% are not bounded.** A verifier that passes 1 false claim in 50 would likely look
  the same here. Bounding the false-accept rate under 1% takes about 300 false-claim verdicts with
  zero misses.
- **Judges were not measured.** Grading the quality of work on a scale, where the vendor reports
  Haiku 5.5's self-preference bias and unscorable ratings, is a different task. D3 stands on vendor
  evidence for that half.
- **Verifying with tools was not measured.** Our live verifier slots often Read and Grep the source
  themselves; this run inlined it.
- **Adversarial or leaked content was not measured.** The record notes Haiku 5.5 used a leaked
  answer without saying so 17.3% of the time; no claim here carried a planted hint or an
  instruction inside the file.
- **Claims were authored by one Opus 5.5 session.** The mutations are single-token and local; real
  wrong claims from a worker may be wrong in ways a substitution does not produce.
- **Whether the saving is worth anything.** About 0.25x the draw per check is an estimate from one
  ratio, and the record says weekly quota strands most weeks.
- **Two reps.** Rep-to-rep variance is seen once (the single false reject), not measured.
