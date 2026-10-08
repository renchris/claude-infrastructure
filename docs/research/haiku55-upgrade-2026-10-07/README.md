# Haiku 5.5 + Claude Code 2.1.293 — which roles, at which effort (2026-10-07)

**Answer.** Advance the binary to 2.1.293 (activation 50, operator-run), and treat that move as the
model move too: on 2.1.293 the alias `haiku` already means Haiku 5.5, so the retrieval role changes
model the moment a new shell starts, whatever the config says. Haiku 5.5 takes **one role: codebase
retrieval, at effort medium, passed explicitly**. Every other role stays on Opus 5.5. The config
flip followed activation 50 (`versions.haiku_latest: claude-haiku-5-5`, 2026-10-07, with the keying
rewrite); it was parked in `versions.haiku_staged` until then. Measured after the flip (below):
on our own file:line lookups no effort rung separates and Haiku 5.5 is at least as accurate as
Haiku 4.5 at half the wall time; on a mechanical extraction it ties or beats Opus 5.5.

Run ledger: [`UPGRADE.md`](UPGRADE.md). Everything below is cited to `notes/` (card facts carry PDF
page numbers; `pack/` holds the fetched sources).

## What is measured, and what is the vendor's word

- **Ours (live, 2.1.293):** gate GREEN ×2 on three accounts; resume through the symlinked
  `~/.claude-next/projects` works; Write under auto in `-p` works and `backup-before-write` fires; an
  Opus 5.5 lead at `--effort high` spawning Explore with `model: "haiku"` was served
  `claude-haiku-5-5` at effort high.
- **Ours (static binary read, not run):** `notes/bin293-probes.md`, `notes/gap-0*.md`.
- **Vendor:** the System Card (144 pp., seven page-range readers, every fact re-checked by a second
  reader: 912 read, 894 confirmed, 18 corrected, 0 refuted, 169 added) and the platform pages.
- **Ours (measured after the flip, 2.1.293):** the retrieval A/B by effort, an extraction A/B against
  Opus 5.5, and the plan-quota draw per Haiku 5.5 token (§ Measured after the flip).
- **Not measured by anyone here:** the quota cost of helper calls that now think.

## The table

| Use case | Model @ effort | Evidence | Conv. | Moves it |
|---|---|---|---|---|
| Codebase retrieval (Explore, `model: "haiku"`) | **Haiku 5.5 @medium**, effort passed on the spawn (slack rung low) | **Ours:** 29 file:line lookups × 3: low 87, medium 86, high 87, Haiku 4.5 86 of 87 (adjudicated); high spends +18% tokens for nothing, and the lead's rung is what an unpinned spawn inherits (§ Measured after the flip). Moves with the binary regardless. Versus Haiku 4.5: coding prompt-injection success 0.08% vs 58.40% (p51), input hallucination 1.88 vs 3.96 (p66), ignoring constraints 2.06 vs 4.46 (p62). Medium is the vendor default; at low it skips searches and stops early (prompting guide), and wide search collapses at low (WANDR 3.5% vs Haiku 4.5's 6.4%, p123). | 85% | a wide-search A/B (many-file sweeps), where the card says low collapses |
| High-volume extraction / classification slot | Opus 5.5 stays the default; **Haiku 5.5 @medium is admissible where quota binds** (`effort_defaults.haiku55_extraction`), on checkable output only | **Ours:** extraction A/B, equal tools: Haiku 5.5 @medium recall 0.94 / precision 0.99 vs Opus 5.5 @low 0.92 / 0.95 and @medium 0.88 / 0.95; per output token it draws ≈0.12× Opus ([0.055, 0.19]) but spends ~2× the tokens, so ≈0.3× per task. Weekly quota strands most weeks, so the saving is usually worth nothing. Vendor: the vendor positions Haiku 5.5 here and single-answer work is flat across effort (HealthBench 59.9% low to 61.6% max, p133). But quota draw per token is not stated, its tokenizer counts ~30% more tokens, and requests over 100,000 prompt tokens bill at 5×. | 75% | a second extraction family (classification of notes) at ≥3 reps; a quota-bound week |
| Mechanical code-writing teammate | stay Opus 5.5 @medium | Terminal-Bench 4.0: 39.2% vs Sonnet 5.5 70.6% and Opus 5.5 66.4% (p115); false completion claims are the worst of the 5.x models (1.89 vs Opus 1.48, p66); it is outside the binary's native read-before-write guard; our enforce hook denies a Haiku teammate. | 92% | — |
| Verifier / judge | stay Opus 5.5 | Self-preference bias +0.23 on a 0–9 scale and ~6% unscorable ratings as a grader (p79); closed-book recall net 0.12 vs Opus 0.58 (p80). | 90% | — |
| Research and synthesis workers | stay Opus 5.5 | The card names "a relative deficit in the reasoning required to succeed on complex, iterative tasks" (p18); it starts strong and does not improve with iteration (p17–18). | 90% | — |
| Helper calls (titles, summaries, WebFetch summaries) | leave on the alias (Haiku 5.5 after the move) | Not a choice we made: the small/fast model follows the alias. These calls now always think. `ANTHROPIC_SMALL_FAST_MODEL` pins the helper alone. | 70% | a meter read around a helper-heavy interval |

Two properties of Haiku 5.5 any slot must handle: a safety refusal returns HTTP 200 with
`stop_reason: "refusal"` and **there is no fallback model** (1.8% of Terminal-Bench trials ended
that way, p115); and it used a leaked answer without saying so 17.3% of the time (Haiku 4.5 1.6%,
p83), so it should not grade or verify work it can see answers to.

## Measured after the flip (2026-10-07, binary 2.1.293)

Every arm read its served model from `modelUsage`; none was silently substituted. Scripts, questions,
truth sets and raw rows are in [`measure/`](measure/).

### Retrieval: our own file:line lookups, by effort

29 lookups over a frozen `git archive 3b3af122d` of the code directories (no `docs/`, so no note
can leak an answer), 16 named-target and 13 described-target questions, 3 reps each. Ground truth
is a unique `grep -n` hit per question; correct means the right path and a line within ±3. Tools
Read, Grep and Glob only, `--setting-sources ""`, account next4. Haiku 4.5 ran by its full dated id
on the same binary.

| Arm | Correct, raw (of 87) | Correct, adjudicated | Median output tokens | Median turns | Median wall (s) | Served |
|---|---|---|---|---|---|---|
| claude-haiku-5-5 @low | 85 | 87 | 806 | 4 | 7 | claude-haiku-5-5 |
| claude-haiku-5-5 @medium | 82 | 86 | 912 | 5 | 8 | claude-haiku-5-5 |
| claude-haiku-5-5 @high | 85 | 87 | 1075 | 5 | 9 | claude-haiku-5-5 |
| claude-haiku-4-5-20251001 (no effort) | 80 | 86 | 1129 | 6 | 17 | claude-haiku-4-5-20251001 |

"Adjudicated" accepts the second defensible answer on the two ambiguous questions (`kind_model()`
beside `haiku_model()` in the router; the `return` four lines below the cloud-venue test in
`ship-land.sh`). Every remaining miss is a single rep. Reading: the lookups are at ceiling for every
arm, so effort does not separate on narrow lookups; output tokens rise with effort (the positive
control that `--effort` reached the model); Haiku 5.5 answers in about half Haiku 4.5's wall time.
What the A/B cannot see is WIDE search, where the card has low collapsing (WANDR); that is why the
rung stays medium and low is only the slack rung.

### Extraction: Haiku 5.5 against the Opus 5.5 incumbent, equal tools

8 shell and Python files inlined in the prompt, no tools for any arm; extract every env var read
with a default (`${NAME:-default}`, `os.environ.get("NAME", "default")`) as JSON. Truth is a
brace-matching parser over the same bytes; scored here against code lines only (comment lines
removed, 60 pairs), 2 reps.

| Arm | Pair recall | Pair precision | Files perfect (of 16) | Median output tokens | Median wall (s) |
|---|---|---|---|---|---|
| claude-haiku-5-5 @low | 0.925 | 0.982 | 9 | 1325 | 10 |
| claude-haiku-5-5 @medium | 0.942 | 0.991 | 10 | 1580 | 12 |
| claude-opus-5-5 @low | 0.917 | 0.948 | 7 | 616 | 12 |
| claude-opus-5-5 @medium | 0.875 | 0.946 | 7 | 767 | 13 |

Against the raw truth (comment-line matches included) the four arms read 0.848 / 0.856 / 0.864 /
0.841 recall: the same tie. Haiku 5.5 spends about 2× Opus's output tokens on this task.

### Plan-quota draw per Haiku 5.5 token

In-situ burn on one account (`next`, idle at 0.1 5h-pp/hour before the run), binary 2.1.293,
`--tools ""`, long-output prompts: Haiku 5.5 @medium / Opus 5.5 @high / Haiku 5.5 @medium, 12 minutes
of calls each, 6-minute holds between. The meter was read from the live `anthropic-ratelimit-unified-*`
headers every 30–60 s. Each burn is measured from its start to the end of the hold that follows it.

| Phase | Output tokens | Cache-write tokens | 5h meter | 5h-pp per M output | Integer-meter bound |
|---|---|---|---|---|---|
| Haiku 5.5 #1 | 3.55M | 1.35M | +3 | 0.85 | [0.56, 1.13] |
| Opus 5.5 | 1.28M | 0.54M | +12 | 9.35 | [8.57, 10.13] |
| Haiku 5.5 #2 | 3.60M | 1.51M | +5 | 1.39 | [1.11, 1.66] |

**Haiku 5.5 draws about 0.12× Opus 5.5 per output token, bounded [0.055, 0.19].** The list-price
ratio is 0.025 ($0.50 vs $20 output), so per list dollar Haiku 5.5 draws about 5× the plan points
Opus does ([2.2, 7.6]); the vendor's $/task charts overstate its saving in our currency, as they did
for Sonnet 5.5. Caveats: the holds were not all flat (+1, 0, 0, +2 pp; the research-kit warm
classifier's four idle processes live on this account), so drift is inside the Haiku bounds rather
than subtracted; the Opus figure is above the 8.05 and 8.67 of the two earlier runs; the weekly meter
moved +1/+2/+1, too little to bound anything. Cache writes ran at the same ~0.4 ratio to output in
every phase, so they do not tilt the comparison.

What it means per task: extraction at a median 1,580 output tokens on Haiku 5.5 @medium against 616
on Opus 5.5 @low is ≈0.3× the incumbent's draw ([0.14, 0.49]), at equal or better quality.

### Permission decider latency

`hooks/model-permission-decider.py`'s real consult, four commands each: Haiku 5.5 (alias, its
default medium) 5.0–6.1 s, Haiku 4.5 8.2–15.3 s, against the hook's 38 s deadline. Haiku 5.5 asked
on `rm -rf /tmp/build-cache && make`, which Haiku 4.5 allowed.

## The binary: 2.1.284 → 2.1.293

No blocker. 47 rated changelog items; after the referee, 14 stand as cautions, 20 were downgraded
and 13 refuted (`notes/cc293-referee.md`). What you take with it:

- `haiku` and the helper model become Haiku 5.5; a `model: "haiku"` spawn inherits the lead's effort.
- Headless sessions kill a backgrounded Bash command after 10 minutes (one-shot `-p`) or 30 minutes
  (streaming) unless the call passes its own `timeout`. Interactive panes are exempt. The changelog
  says only "30 minutes"; the 10 is from the binary.
- A per-agent token budget sits behind a server flag: off on all four accounts today, advisory only,
  Agent-tool spawns only. `CLAUDE_CODE_RIPPLING_TULIP=0` in settings `env` disables it for good.
- WebSearch's 1,000-per-session stop now refills at 100 per hour.
- 2.1.293 is itself the last fix in four regression clusters (background sessions, the daemon
  control path, cloud sessions, subagent prompt text). Our background-job rails
  (`handoff-fire.sh --bg` parsing, `lr-upgrade.sh`) were measured on 2.1.284 and are not re-measured.
- Held-open issues: 1 of 16 fixed; nothing restores a spawn cap. `SPAWN_DEPTH=1` stays load-bearing.

## Open decisions re-measured (2026-10-08, binary 2.1.293)

Each row at or below 90% in the table above was measured live and then reviewed by a skeptic that
recomputed the numbers from the raw rows ([`decisions/`](decisions/): `D<n>-*.md` and
`D<n>-*.skeptic.md`). Conviction below is the lower of the two readings.

| Decision | Outcome | Conv. | Deciding evidence | Still not settled |
|---|---|---|---|---|
| D1 retrieval effort | Keep **medium**, low as slack, never high. The reason changes: low did NOT collapse here, so medium is a tie broken by the silent cost of a missed file. | 80% | 10 many-file sweeps (true sets of 8–40 files) × 2: low 20/20 exact, medium 20/20, high 17/20; Haiku 4.5 10/20 with two context overflows. Low saves ~10% output tokens (p = 0.11). | Sweeps over 40 files or needing a per-file judgment; both rungs sat at ceiling. |
| D2 extraction / classification | Unchanged: Opus 5.5 default, Haiku 5.5 @medium admissible where quota binds, **checkable output only**. Do not widen it to judgment classification. | 85% | Table extraction: Haiku 5.5 recall 1.000, precision 0.98–0.99 at ~0.3× Opus's draw. Commit-type classification: Haiku 450 vs Opus 521 of 720 labels (p = 0.019; gap 2–18 points). Haiku returned unparseable JSON in 7 of 18 calls until the prompt said "one valid JSON array". | Whether the classification gap is accuracy or one author's labeling habit. |
| D3 verifier / judge | Stay Opus 5.5. Haiku 5.5 tied it on the one bounded class measured, which is not grounds to widen. | 78% | Claim-vs-source with planted false claims: 0 false accepts in every arm (30 distinct false claims × 2); accuracy 119–120 of 120. At ceiling, so it cannot rank the models; a false-accept rate under ~12% is not ruled out for either. | Harder checks: no line cite, several files, a verifier that reads with tools. |
| D4 research / synthesis | Stay Opus 5.5 @xhigh. | 91% | Haiku 5.5 lost 6 of 6 frozen briefs at high and at xhigh to a same-day Opus anchor, 3 blind judges unanimous on every brief (p = 0.031); wrong claims 33 / 21 vs 9. | Measured for deep repo synthesis only; web research still rests on the vendor's card. All judges were Opus. |
| D5 helper calls | Leave on the alias; do not pin. | 86% | A WebFetch summary costs 346 helper output tokens on Haiku 5.5 (307 of them thinking) vs 38 on Haiku 4.5, ≈ 42 Opus-output equivalents, about 2–3% of a short session's draw, and ~1 s. | Title, summary and suggestion helpers do not fire headless and were not measured. |
| D6 per-agent budget switch | **Apply** `CLAUDE_CODE_RIPPLING_TULIP=0` in the settings `env` block (operator-owned). The budget is NOT merely advisory. | 88% | Forced on, sub-agents finished the full task in 0 of 9 runs vs 6 of 6 with it off (p = 0.0002); `=0` removed it in every run and a settings value beat a shell value. `CLAUDE_CODE_TOTAL_TOKENS_REMINDER=infinite` is the wrong switch. | Whether `=0` beats a real server-sent value (the flag is off on all four accounts, so it could only be forced locally); re-check on each binary. |

`next3`: a direct Haiku 5.5 request on 2.1.293 returned a completion after it was logged back in.
The gate run against `next3` stalled on its first check for 93 minutes and was stopped, so the
formal gate verdict for that account is still missing.

## Still owed (in order)

1. ~~**Operator:** run activation 50~~ — done 2026-10-08T01:55Z. Still owed: re-gate `next3` for
   Haiku 5.5 now that it reads logged in (its entitlement stays UNPROVEN until then; no measurement
   here was routed to it).
2. ~~**After activation, one diff:** the flip plus the keying rewrite~~ — done (`UPGRADE.md`, P7).
3. ~~**Measure:** retrieval A/B by effort; quota draw per token; `effort` on every spawn site~~ —
   done (§ Measured after the flip).
4. **Operator-owned settings edit:** `CLAUDE_CODE_RIPPLING_TULIP=0` in the settings `env` block.
