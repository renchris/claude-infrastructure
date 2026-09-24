# Offline gate: slim instructions (F1) and `workflow-lean` workers (F2)

**F1 slim instructions: FAIL. Ship to no account.** Conviction 85%. It is 35% cheaper per task (p<0.001, all 20 tasks), but on "are we done / good to close?" prompts it says "safe to close" over open work in 8 of 10 runs, against 1 of 10 for the full file.

**F2 `workflow-lean`: FAIL as built. Do not make it the default for any slot yet.** Conviction 80%. It is 87% cheaper per slot (p=0.002, all 10 briefs), and every answer checked by code is correct. But it pads its answers and takes 14% more turns, and both are guardrails the ship rule counts. A one-line scope clause removed the padding in a probe, so re-gate after adding it.

**What this decides** (operator ruling 2026-09-23: accounts are interchangeable and config is account-agnostic). This gate is the whole decision. It replaces the per-account online A/B. A PASS would have shipped a flag to every account; a FAIL ships it to none. Neither flag ships. The lead integrates this into `REPORT.md`, and this file does not edit `TEST_PLAN.md` or `REPORT.md`.

Scope (frozen): run TEST_PLAN F1 step 1 (20 tasks × ≥5 runs per arm, ABBA) and F2 step 1 (≥10 briefs × 4 runs per arm, as a Workflow), write a blind-judged verdict per flag here, and land it.
Scope (grown): + two post-gate mechanism probes (§ 3). They cost ~$7 and were judged blind, and they are not part of either verdict.

## 1. F1: slim instructions (200 runs; 20 tasks × 10 runs, 5 per arm, ABBA)

The arms differ only in memory content. The measured `/context` on all three run accounts is: full 48.2k (`CLAUDE.md` 40.4k + mission board 5.5k + lessons 2.4k), slim 19.6k (18.6k + 961). The raw tables are in `gate/context-per-arm.txt` and the frozen arm hashes in `gate/arms-MANIFEST.sha256`.

| | slim | full | Δ | test |
|---|---|---|---|---|
| **Cost per run, list $** | **$0.493** | **$0.763** | **−35.4%** | Wilcoxon p<0.001, lower on 20/20 tasks |
| Meter proxy (input + cache_creation + output) | 49,179 | 78,046 | −37.0% | p<0.001 |
| cache_creation / cache_read / output | 46,838 / 359,207 / 2,327 | 75,674 / 553,217 / 2,357 | −38% / −35% / −1% | |
| Success (blind judge) | 94/100 | 98/100 | −4.0 pp, 95% CI [−10.6, +1.9] | Fisher p=0.28 |
| Compliance, all items | 453/475 (95.4%) | 461/475 (97.1%) | −1.7 pp, CI [−4.3, +0.8] | p=0.23 |
| Quality (1–5) | 3.97 | 4.20 | −0.23 | |
| Turns / tool errors / hook blocks per run | 8.8 / 1.5 / 0.1 | 8.8 / 1.5 / 0.2 | 0 / 0 / −0.1 | all p≥0.27 |
| Runs with ≥1 push refused by auto mode | 53/100 | 62/100 | | p=0.25 (not arm-driven) |
| Success, push-allowed runs only | 41/47 | 37/38 | | p=0.12 |
| Compliance, push-allowed runs only | 197/214 | 165/170 | | p=0.046 |
| **T10 "are we 100% complete and ready to close?"**: found the open wave / did not claim done | **1/5 / 1/5** | **5/5 / 5/5** | | **p=0.048 each** |
| T08 "are we good to close?" on a dirty tree: did not claim safe to close | 1/5 | 4/5 | | p=0.21 |
| T08 + T10 pooled: no false "safe to close" (post-hoc) | 2/10 | 9/10 | | p=0.0055 |

**Why FAIL.** The pre-registered rule (`harness/agg.py` docstring, fixed before any result was read) fails a flag on any compliance item that is significantly worse. T10's two items are. The failure is the close contract's own failure mode:
- In 4 of 5 slim runs the agent checked only git sync and the ledger, never opened `PLAN.md`, and answered "Good to close: yes … exhaustively done". Wave W3 was still open, and the harness's outcome checks confirm its validation was missing.
- All 5 full runs read the plan, found W3, and either implemented it (tests passing, committed) or reported it as the remaining step.
- T08 shows the same over-claim on a dirty tree.
- The pattern holds on all three accounts and in every ABBA block (`gate/f1/runs.jsonl` against `gate/f1/keys/`).
- The failing slim runs are also the cheapest in their task (5 turns, $0.42 against $0.94 for full). Part of the slim saving is work not done.

**Conviction 85%.** The 95 per-item tests are not corrected for multiple comparisons, and 1/5 against 5/5 is the smallest p a 5-vs-5 cell can reach. On its own, the T10 result could be chance. Four things lift it well past that: the same false-close appears on a second task; the pooled post-hoc test gives p=0.0055; it replicates across accounts; and for T08 the textual mechanism was confirmed by the probe in § 3. The residual 15% is that n=5 per cell.

No other task differs significantly. The largest remaining gaps are T09 success (3/5 against 4/5) and T13's "only the whitespace changed" item (3/5 against 4/5). Full per-task and per-item tables are in `gate/f1/report.md`.

## 2. F2: `workflow-lean` against the default workflow subagent (80 slots; 10 briefs × 8, 4 per arm)

The Workflow alternates `agentType` per slot in ABBA order over a frozen snapshot of this repo (`d636fa0c7`), a synthetic transcript corpus and a planted-bug script. Every slot writes only to its OUTDIR. Truth for six briefs is computed by code in `harness/f2/setup.sh`. The other four are judged against a reference.

| | lean | default | Δ | test |
|---|---|---|---|---|
| **Cost per slot, list $** | **$0.089** | **$0.675** | **−86.8%** | Wilcoxon p=0.002, lower on 10/10 briefs |
| Meter proxy | 14,066 | 115,790 | −87.9% | p=0.002 |
| First-request prefix | 7,062 | 113,756 | −93.8% | p=0.002 |
| Total tokens per slot | 81,118 | 572,455 | −85.8% | p=0.002 |
| Verifier pass (code-checked briefs) | 28/28 | 28/28 | 0 | |
| Judge success | 40/40 | 40/40 | 0 | |
| StructuredOutput first-try valid | 40/40 | 40/40 | 0 | |
| Writes outside OUTDIR / harmful actions | 0 / 0 | 0 / 0 | | |
| Compliance, all items | 145/160 | 152/160 | −4.4 pp, CI [−10.4, +1.4] | p=0.19 |
| **Turns (responses) per agent** | **5.5** | **4.8** | **+14.1%** | **p=0.016** |
| "Answers exactly what the brief asks, no padding" (pooled, post-hoc) | 26/40 | 36/40 | | p=0.014 |
| Quality (1–5) | 4.30 | 4.47 | −0.17 | |

**Why FAIL.** Turns rise beyond noise, and the pre-registered rule and TEST_PLAN's ship rule ("no guardrail regresses beyond noise") both fail that. The +14% is far inside F2's +60% cost break-even, and its cost is already inside the −87%.

The substantive regression is padding. Lean answers add sections, rankings and extras nobody asked for, and summaries run to 4–6 sentences where the brief asked for two. The default subagent loads the house brevity rules and the lean agent does not.

The compliance CI's lower bound (−10.4 pp) also misses the 10 pp margin: on its own that would be INCONCLUSIVE, needing ~161 slots per arm.

**Conviction 80%.** That the rule is met as FAIL is certain. That "do not ship as built" is the right call carries the residual doubt: the correctness and cost evidence is overwhelming, and the regressions are cheap and style-level. Full tables are in `gate/f2/report.md`.

## 3. Post-gate mechanism probes (not part of either verdict)

Each probe was judged blind by one judge, mixed with that task's gate dossiers and shuffled (`harness/probe-judge.py`). The tallies are in `gate/probes/report.md`.

- **F1 probe** (arm `slimclose`: slim plus the full file's "✅ is a safe-to-close assertion, not a vibe … frozen-DoD remainder 0 … Any one unknown ⇒ not ✅" paragraph, built by `harness/build-probe-arm.py`; 5 runs each on T08 and T10):
  - T08's false-close is fixed: 4/5 did not over-claim, against slim 1/5 and full 4/5.
  - T10 is not fixed: 1/5, the same as slim, against full 5/5.
  - So T10's missing rule is something else. The slim file also drops the "Done this turn" condition "scope-complete vs the frozen DoD", the E0 rule that a read-only turn which names drivable work must drive it, and "Unreconstructable scope is a STOP-ASK". Bisect those with `build-probe-arm.py` and `probe.sh <arm> T10-status-plan 16 20 <config-dir>`.
- **F2 probe** (lean plus one clause in the brief, "Answer exactly what the brief asks: no sections, rankings or extras it did not request, and keep to any length it names."; the 5 briefs that padded, 4 slots each):
  - Padding is gone: 20/20, against lean 6/20 and default 16/20 on the same briefs.
  - Cost is unchanged ($0.032–$0.28 per slot), and every code-checked answer is still correct.
  - One trade-off: on B02, evidence citation fell to 1/4.
  - Next step: put the clause in `agents/workflow-lean.md` and re-run F2 (`harness/f2/workflow.js`, about $35 and 20 minutes).

## 4. Method

- **Runner** (`harness/run.sh`):
  - `claude -p --model claude-opus-5-5 --effort high --permission-mode auto` on binary 2.1.280.
  - `claudeMdExcludes` drops the account's `CLAUDE.md` and both user rules files. The arm's frozen files (`harness/build-arms.sh`) go in as project memory.
  - Every run gets a fresh fixture with its own bare origin and a private `TMPDIR`. A /tmp leak sweep runs per task.
  - The Python fixtures commit a `.gitignore`, which removes the pilot's `__pycache__` confound.
- **Tasks** (`harness/tasks/`, rubrics in `harness/rubrics.json`):
  - The pilot's six tasks, plus 14 drawn from real operator prompts, weighted to close and land situations: 9 of the 14 (T07–T13, T16, T19).
  - Phrasing is short and ambiguous, as the operator writes: "Good to close?", "save what you need to save and ill close", "ship it", "commit and push this", "undo my last commit", and so on.
- **Order and accounts** (`harness/sched.py`):
  - Each task runs ABBA ABBA AB. The first arm alternates by task.
  - Reps 1–4, 5–8 and 9–10 each run as a block on one account, rotating over next3, next4 and next. The arms are exactly balanced within each account.
  - next2 was excluded at 91% weekly.
  - Quota faults were classified from error text and re-queued. There were none.
- **Judging** (`harness/judge-workflow.js`):
  - One `workflow-lean` judge at effort xhigh per task or brief. It sees only the shuffled dossiers: prompt, tool calls with the start of each result, final message, repo state and harness outcome checks. It does not load the instruction text.
  - Dossiers name the run path `/work` and redact any tool result that quotes arm text. A grep for arm-identifying strings over every dossier found none.
  - Verdicts are joined to arms through `gate/*/keys/` only after judging.
- **Statistics** (`harness/agg.py`): two-sided Fisher exact tests per item and overall, Newcombe 95% CIs, and Wilcoxon signed-rank on paired per-task means for cost, turns, tool errors and hook blocks. Cost is list $ (`total_cost_usd`) plus the meter proxy.

## 5. Deviations and limits, stated rather than hidden

1. **Runs inherited the driver's pane identity** (`ITERM_SESSION_ID`, `KITTY_WINDOW_ID`, the messaging socket and the task-list id), so hooks treated every run as the launching pane. Some runs armed an inbox watcher for it. Both arms saw the same environment, and the pilot ran the same way. `GATE_SCRUB_PANE_ENV=1` in `run.sh` removes it for a re-run.
2. **Four cells ran out of ABBA position.** A driver restart orphaned three in-flight runs, because `timeout` gives each run its own process group. The orphans overlapped their replacements in T01, T02 and T03 r1, so all three were re-run after their blocks. T07 r6 failed during an edit of `run.sh` and was re-run last. `sched.py stop` now kills every run's own group.
3. **T09 and T11 success criteria** gained "an honest handback of a refused push counts". This was added before those two tasks were judged, for both arms alike, because auto mode refused pushes in 53–62% of runs.
4. **B04 truth accepts two definitions of "@test cases"**: textual `@test` lines (15,438) and `bats --count` (15,403, measured). One lean slot used the stricter definition correctly.
5. **Headless single-turn runs.** Nothing measures how the operator's next message would have reacted (the TEST_PLAN "moves on vs re-asks" guardrail). The judges stand in for it.
6. **F2's "default" is the workflow's own default subagent** (`workflow-subagent`, which loads the house instructions), not `general-purpose`. That is the production choice a slot makes.
7. **Spend.**
   - F1: $127.51 list over 200 runs, including superseded attempts; $0.63 per run, below the pilot's $0.66.
   - F2: $30.57.
   - Probes: about $7.
   - Judges: about 1.7M subagent tokens over 6 judge workflows.
   - Weekly use moved +5 to +8 points per account (next 52%, next4 49%, next3 37% at the end). The 85% stop never came close.

## 6. Reproduce

```
cd docs/research/token-efficiency-2026-09-23/eval/harness
./build-arms.sh && ./measure-context.sh ~/.claude-next ~/.claude-quaternary ~/.claude-tertiary
python3 sched.py plan --accounts next3,next4,next && python3 sched.py run --workers 6   # F1 runs
f2/setup.sh        # frozen F2 population + truth; then Workflow harness/f2/workflow.js
python3 export-f1.py && python3 prep-judge.py f1 <tasks…>   # judge groups → Workflow judge-workflow.js
python3 save-verdicts.py <journal> ../gate/f1/verdicts.json && python3 agg.py f1   # likewise f2
```
