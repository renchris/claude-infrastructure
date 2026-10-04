# Shard "hillclimb": evals, judges and fixtures vs the claude-api hillclimb method

Scope: read-only audit of the repo at `/Users/chrisren/Development/.worktrees/wt-cc-003409-15565`
(branch `cc-003409-15565`, HEAD `7ad2ce9fd`) against `shared/evals/eval-hillclimb.md`,
`eval-audit.md`, `cost-hillclimb.md` and `build-eval.md`. No model calls were made. Every
quota figure below is ESTIMATED from the repo's own measured spend (method stated with each).
Patched copies of the two edited files, with all findings applied, are in `/tmp/capi-audit/hc-apply/`.
The findings JSON (exact old/new text, each checked to match the tree exactly once) is
`/tmp/capi-audit/hillclimb-findings.json`.

## Answer first

1. **`/evolve-skill` cannot run as written, and if forced it would spend dollars and measure the
   wrong thing.** Three defects, all verified on disk:
   - It calls `claude-latest`, which prints "Staying on 2.1.114". The API refuses `claude-opus-5-5`
     below 2.1.280 (memory `headless-trial-arm-model-from-init-line.md`). The production binary is
     `bin/cc-claude-bin`, which resolves to `~/.claude-284`.
   - It isolates with `--bare`. On 2.1.284, `--help` says `--bare` auth "is strictly ANTHROPIC_API_KEY
     or apiKeyHelper (OAuth and keychain are never read)". No key is set, and `accounts.json` has
     `spend.usage_credits_authorized: false`. The repo's subscription-safe isolation recipe already
     exists (`docs/research/opus55-effort-sweep-2026-09-22/run-arms.sh`).
   - Its single "Score" command passes the case input to the model under test with a
     `{score, feedback}` JSON schema. So the generator is forced to grade itself instead of writing
     the deliverable, and `## expected_behavior` (the rubric) never reaches any call. The fixture
     README describes the intended two-step flow; the command does not implement it.
   Findings hillclimb-01, -02 and -07/-08 fix these. -03 to -06 bring the loop in line with
   eval-hillclimb.md: state on disk, a noise floor before keep decisions, train-only generator input,
   the test delta as the headline, and the stopping rule.
2. **The best eval in the repo is the token-efficiency F1 gate, and its PASS for the slim
   instructions has no held-out tasks.** Rounds 2 to 4 edited `CLAUDE.global.slim.md` from dossiers
   of T03, T04, T08, T10, T16 and T19. The verdict was then read on the same 20 tasks; R4.5 added
   reps 11-30, not new tasks. Since the gated arm (`d570ed0bf`, sha `d446c60e…`), 8 more commits have
   changed the slim text. It grew from 53,769 chars to 58,378 across its two files (+8.6%), and none of
   that has been gated. This is the top-ranked run below.
3. **The codex-probe review eval does not discriminate models or efforts.** About 15 arms across
   three sweeps score 6-14 of 36. Two briefs, cp-02 (4 items) and cp-06 (6 items), score 0 for every
   arm. eval-audit §1 says a 0% across all variants "is more often a broken case than a hard one".
   Audit the eval before using it for any further routing decision or climb (zero quota on paper).

## Inventory and health check (eval-audit, done on paper)

| Eval / judge / fixture set | What it scores | Health (eval-audit §1-5) | Valid hillclimb target now? |
|---|---|---|---|
| `commands/evolve-skill.md` + `evolve-fixtures/pyramid-principle/cases/` (4 cases) | 1-5 LLM judge vs a per-case rubric for the `pyramid-principle` skill | **Broken runner** (above). Human-written rubrics, good both-direction criteria. n=4, so no split is possible and any result is directional. Prompt-grader mismatch: every rubric penalises naming the framework, but the skill body names MECE/SCQA/key line throughout and has no "do not name it" rule; that is an artifact gap round 1 would find. The target skill is outside this repo (`~/Development/convert-pdf-to-md/pyramid-principle-prompt.md`) and opens with a dead `## CONFIG model: gpt-5 / temperature: 0.2` block. `cases/*.md` also matches `README.md`. Never run: `~/.reso/evolve/pyramid-principle/` holds only the `cases` symlink. | **No.** Fix the runner first (findings 01-08). Make the two obvious skill fixes directly; per eval-hillclimb Step 4, a clear change skips the analyzer. Climb only after growing the set to 15+ cases. |
| `docs/research/token-efficiency-2026-09-23/eval/` (F1: 20 agentic tasks, ABBA, blind judge workflow, pre-registered `agg.py` rule; F2: 10 briefs with code-verified truth) | slim vs full instructions (cost, success, compliance, turns, tool errors); `workflow-lean` vs the default worker | **Strongest eval here.** Pre-registered decision rule, blind keys kept apart from dossiers, arm-identifying text redacted, cost from `total_cost_usd` plus a meter proxy, failures classed, and quota stops. Gaps against the guide: (1) no held-out tasks across the rounds that edited the arm (selection set = verdict set); (2) the extension after INCONCLUSIVE is optional stopping, mitigated because the new 200 runs pass on their own; (3) judge leniency drifts between rounds (R4.5 names the T09 split) with no fixed re-judged anchor; (4) the live slim text has drifted 8 commits from the gated arm. | **Yes, for a confirm, not a climb** (rank 1). F2 is a valid cost-walk target (rank 2). |
| `tests/fixtures/codex-probe/` + `docs/research/{fable51,opus55,sonnet55}-effort-sweep-*`, `review-judge-followup-2026-09-22` (`judge.py`, `paired.py`, `run-arms.sh`) | recall of 36 anchored defects in 7 briefs, blind 3-judge panel, model × effort routing | Excellent construction: real pre-fix artifacts, sibling-inert, clean controls, labels shuffled per judge, anchors re-judged in each panel, served model recorded, paired sign tests. But: score is flat across ~15 model/effort arms (the mechanism under test does not drive it); cp-02 and cp-06 are 0 for every arm (suspect gold or a too-strict "mechanism" rule); precision is not scored, though the judges already return `reported`; the noise is large (same config read 10/15/13). `judge.py` takes the first fenced json block, already filed in `docs/research/sonnet55-utilization-2026-09-28/notes/harness-hazards-b.md:120`. | **Not as a climb.** Audit first (rank 3). The briefs' preamble is not the production review prompt (`commands/review.md`), so climbing it would tune a non-shipping artifact (eval-audit §2, "Eval config matches production config"). |
| `docs/research/memory-eval/` (`recall_eval.py`, `fusion_eval.py`; fixture 10 queries; private gold `~/.claude/autonomy/memory-eval/field-queries.json`, 19 queries) | R@1/R@5/MRR of `cc-memory-search` | Deterministic, no model calls, Wilson intervals, a **sealed holdout** (`sha1(id)%5==0`), gold kept out of the repo. Too small: the 19 field queries leave a 2-query holdout, a noise floor of about ±23 pp on R@5. The 50 authored queries were written with the gold known (an upper bound). `bin/cc-memory-search:41-44` says the bm25 weights 10/5/1 are "unproven". | **Yes, at zero quota**, once the field set grows (rank 4). |
| `docs/research/opus55-synth-reprobe-2026-09-22/`, `sonnet55-synth-probe-2026-09-28/` | synthesis-worker routing, 6 briefs × 1 sample, blind judges | The reprobe's own README records a wiring failure: Grep/Glob were absent in Workflow subagents, so the arms had unequal tools. That is exactly eval-hillclimb Step 0.5's "prove the mechanism is wired". n=6 at 1 sample is directional. | No; it is a routing probe. |
| `bench/` (design-review perception pipeline) | deterministic DOM and pixel rules vs 13 ground-truth pages | Calls no Claude model; `score.py` is a gate. | No (not an LLM eval). |
| `scripts/cc-upgrade-gate.sh` + `lib/cc-upgrade-gate/check*.sh` | functional PASS/FAIL of each way of working on a candidate binary × model | A regression gate, not a metric. Retries flaky probes up to 3 times without recording passed-on-retry separately (eval-audit §2 retry semantics); worth noting, not a finding. | No. |
| `hooks/model-permission-decider.py` (Haiku 4.5 allow/ask classifier) | — | Not registered in `~/.claude/settings.json` (0 hits); no labeled set. | No, until it is live. |

## What the hillclimb protocol changes in our tooling

| Guide element | `/evolve-skill` today | token-efficiency gate today | Change |
|---|---|---|---|
| Runnable eval with per-case transcript, `model` from the response, `usage`, grade from the same call (Step 0) | none of it: one call that self-grades | yes (dossiers, `runs.jsonl`, `modelUsage`) | evolve: findings 01-02 |
| Step 0.5: noise floor vs headroom vs smallest win | "strictly beats baseline across >=2 reruns" | pre-registered margins (5 pp / 10 pp) and Wilcoxon/Fisher | evolve: 03-04 |
| Oracle/null check on the judge | none | rubric judged blind; no known-negative check recorded | evolve: 02 (empty, "I don't know", wrong-case) |
| Judge is not the model under test | same model and same call | judges at xhigh, blind | evolve: 02 uses `versions.opus_prior` |
| Train/test split; the analyzer reads train only; test is the headline | seeded with failing cases, no split | every round read the same 20 tasks it was scored on | evolve: 03, 05, 06. Gate: rank-1 run with new held-out tasks |
| `_state.json` + `baseline/` `vN/` (`results.jsonl`, `traces/`, `change.md`, `change.patch`), report builder | `~/.reso/evolve/<slug>/<run>/` with no schema | `gate/`, `regate/`, `round3/`, `round4/` with keys and dossiers: equivalent in substance | evolve: 03 (lite report builder). The gate's layout is fine; no change |
| Stopping rule: plateau of K rounds inside noise; cost-hillclimb caps prompt rounds at 3-4 | cap 2-3 generations | operator-approved per round | evolve: 04 |
| Re-baseline when the fingerprint changes | n/a | the slim text has changed 8 times since `d570ed0bf` | rank-1 run |
| Judge drift: re-grade every variant when the judge changes | n/a | a new judge batch each round | Add ~20 fixed anchor dossiers to every judge batch, the codex-probe sweeps' own practice |

## Ranked hillclimb runs worth doing

Quota method (ESTIMATED): the repo's measured list spend converted at its measured rate. F1 gate:
$165 list moved the weekly meter +5 to +8 pp on each of 3 accounts (GATE.md §5 item 7), so about
$7-11 list per weekly point for agentic runs. Codex-probe Opus 5.5 phase: $64 list ≈ 4.0 W-pp, so
about $16 per point for output-heavy single shots. Memory `feedback-small-quota-spend-needs-no-ask`
allows about 2-4 W-pp without an operator ask; runs above that need one.

| Rank | Run | Eval it uses | Why it is worth it | Est. quota |
|---|---|---|---|---|
| 1 | **Held-out confirm of the live slim instructions** (a confirm, then optionally a cost climb). Author 10 new tasks T21-T30 that no editing round has read, weighted to the classes the rounds patched (close honesty, hand-over, refused push, plan-open work). Run current slim vs current full at 5 reps per arm, ABBA, blind judge, with `agg.py`'s rule unchanged and about 20 round-4 dossiers re-judged as a drift anchor. | token-efficiency F1 harness (`sched.py`, `run.sh`, `judge-workflow.js`, `agg.py`) | Slim rides every session on every account at -34% cost per task. Its PASS was read on the tasks that chose its edits, and the live text has drifted +8.6% since. This one run answers both questions. | 100 runs × $0.63 ≈ $63 list plus judging: **≈7-10 W-pp across 3 accounts** (operator ask) |
| 2 | **workflow-lean model × effort staircase walk** (cost-hillclimb Step 2). Enter at Opus 5.5 low and step down to Sonnet 5.5 low on a pass. Floor: F2 verifier correctness at 100% and compliance within the 10 pp margin. Re-check turns and output tokens per cell. | F2 harness (10 briefs, code-verified truth, `harness/f2/workflow.js`) | workflow-lean is now the default for every read-only Workflow slot, so the effort per slot is the biggest unmeasured multiplier on research-wave quota. Quality is saturated, so cost is the only axis left (eval-audit §1, headroom). | about 5 cells × 20 slots at $0.10-0.40 ≈ $10-40 list: **≈1-4 W-pp** |
| 3 | **Codex-probe instrument audit, before any further routing decision on the review class.** (a) On paper: read cp-02 and cp-06's ground truth against all ~15 arms' stored outputs; decide whether the gold is wrong, the mechanism-not-topic rule is too strict, or the briefs are genuinely beyond reach. (b) Compute precision from the existing `scores.jsonl` (`reported` - credited, plus findings on the clean cp-03 and cp-07). (c) Only if (a) convicts the gold: re-judge those two briefs from stored outputs. | `tests/fixtures/codex-probe/`, existing `scores.jsonl` | Every review/judge routing row in `model-config.yaml` rests on this eval. Ten of 36 items are unreachable for every arm, and recall-only scoring rewards "report everything". | (a)(b) **0**; (c) about 6 judge calls per panel ≈ $4 list ≈ **0.3 W-pp** |
| 4 | **bm25 weight climb for `cc-memory-search`** with the sealed holdout. First grow the field queries from 19 to about 80-100, mined from transcripts where a memory file was read after the operator's prompt, with an operator spot-check. Then grid about 20 weight triples on dev and unseal holdout once at the end. | `docs/research/memory-eval/recall_eval.py` | Retrieval decides which rules reach a session; the weights are self-declared "unproven". The climb itself makes no model calls. | climb **0**; query mining as a read-only workflow **≈1-2 W-pp** |
| 5 | **`/evolve-skill pyramid-principle`**, after findings 01-08 and the two direct skill fixes (drop the gpt-5 CONFIG block; add the "apply, never name, the framework" rule the rubrics already score). Worth a climb only after the set grows to 15+ cases. | `evolve-fixtures/pyramid-principle/` | It exercises the repaired loop end to end. The value is low: the skill lives in another repo and its usage is unmeasured. | 4 cases × 3 reps × up to 5 variants × (generate + judge) ≈ $15-30 list ≈ **1-3 W-pp**; at 15 cases ≈ $56-113 ≈ **4-11 W-pp** |

Not worth a run now: F3 (rules split) and F4 (compact board). Both are INCONCLUSIVE only for lack
of n; the lever is more reps on the existing arms, not a climb. The synthesis-worker probes need
equal tools before any rerun.

## Findings (exact edits in the JSON; each verified to apply exactly once)

| id | file:line | kind | mode |
|---|---|---|---|
| hillclimb-01 | commands/evolve-skill.md:23 | binary + isolation + served-model capture | string-replace, REQUIRED |
| hillclimb-02 | commands/evolve-skill.md:32 | split generate/judge, judge model, judge negatives | string-replace, REQUIRED |
| hillclimb-03 | commands/evolve-skill.md:28 | on-disk state, baseline reps, train-only generator | string-replace, TUNE |
| hillclimb-04 | commands/evolve-skill.md:46 | keep rule = test delta beyond the noise floor; stopping | string-replace, TUNE |
| hillclimb-05 | commands/evolve-skill.md:20 | README.md excluded from cases; set sizing and split | string-replace, REQUIRED (README) / TUNE (sizing) |
| hillclimb-06 | commands/evolve-skill.md:53 | report headline = test delta; spend from usage | string-replace, TUNE |
| hillclimb-07 | commands/evolve-skill.md:3 | description no longer says API-only (217 chars, under the 250 cap) | string-replace, REQUIRED |
| hillclimb-08 | evolve-fixtures/pyramid-principle/cases/README.md:9 | README's run steps match the command | string-replace, REQUIRED |
| hillclimb-09 | docs/research/token-efficiency-2026-09-23/eval/GATE.md:443 | held-out confirm of the live slim text | needs-measurement |
| hillclimb-10 | tests/fixtures/codex-probe/manifest.json | cp-02/cp-06 zero-for-all-arms audit + precision | needs-measurement |
| hillclimb-11 | agents/workflow-lean.md | model × effort walk on the F2 harness | needs-measurement |
| hillclimb-12 | bin/cc-memory-search:41 | grow field queries, then climb the bm25 weights on dev | needs-new-code |

## Not covered

The pyramid-principle SKILL.md itself (it is in `~/Development/convert-pdf-to-md`, outside this repo;
its two fixes are described, not drafted). Full-text read of every judge.py copy beyond the opus55
one (they are documented as byte-identical copies). Whether `--json-schema` returns a parsed object
under `--tools ""` on 2.1.284: finding 02 makes that a one-call premise probe instead of asserting it.
Live skill-usage frequency (which skill most merits `/evolve-skill`) was not measured.
