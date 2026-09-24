# Offline gate: slim instructions (F1) and `workflow-lean` workers (F2)

> **Re-gate, same day (§ Re-gate below): `workflow-lean` with a scope clause PASSES; slim with the restored close contract still FAILS, now on turns and tool errors.** The verdicts directly below are the original gate's and are kept as run.

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

## Re-gate (2026-09-24)

**F2 `workflow-lean` with the scope clause: PASS.** Conviction 88%. It is 84% cheaper per slot (p=0.002, all 10 briefs) and equally correct (verifier 28/28, judge 40/40 in both arms). Compliance is 96.9% against 96.2% (CI lower bound −3.8 pp against the −10 pp margin), and no guardrail is significantly worse.

**F1 slim instructions with the restored close contract: FAIL.** Conviction 85%. The false "safe to close" is fixed: success is 98/100 against full's 96/100, compliance is 97.1% in both arms, and neither close task is worse. But slim now takes 13.7% more turns (p=0.014) and has 25% more tool errors (p=0.002), and the pre-registered rule fails any guardrail that is significantly worse. It is still 31.6% cheaper (p<0.001). Most of the extra turns come from non-close tasks. They were already in the original gate, hidden because slim then skipped the close work (§ R3).

**What this decides.** `workflow-lean` is now the default `agentType` for read-only Workflow research slots. It is set in the research-subagents skill's Workflow slot table and in the four read-only assessment slots of cc-version-audit Step 3. Slots that write code, commit, land, hand off, close, or need MCP or a skill keep the default subagent. Slim instructions ship to no account, so there is no migration to stage.

Scope (frozen): (A) put the probe's scope clause into agents/workflow-lean.md and re-run F2. (B) find the text the slim instructions dropped that causes false "safe to close" answers, restore it in the slim file, and re-run F1. Record both verdicts in GATE.md and REPORT.md, and land them.
Scope (grown): + F2 re-run a second time with its OUTDIRs pre-created, after run 1 failed on a harness difference (§ R1). + the workflow-lean default in two house skills, which the brief authorizes on a PASS.

### R1. F2: `workflow-lean` with the scope clause (80 slots, 10 briefs × 4 per arm, ABBA)

The clause went into `agents/workflow-lean.md` verbatim as a **Scope** bullet (commit `afc165115`), then landed and converged. It had to run in a fresh process. This session had cached its agent definitions at start: a spawned workflow-lean quoted its "Deliver to a file" bullet but reported the Scope bullet ABSENT, while a headless `claude -p` quoted the Scope bullet verbatim. So both F2 runs ran as a headless `claude -p` session that invoked `harness/f2/workflow.js` with `args.root=/tmp/tokeff-regate`, over a copy of the frozen population (tree `d636fa0c7`, identical by `diff -rq`). Judging used the gate's own `judge-workflow.js` and `prep-judge.py`, with an identical rubric and references.

| | lean | default | Δ | test |
|---|---|---|---|---|
| **Cost per slot, list $** | **$0.109** | **$0.697** | **−84.4%** | Wilcoxon p=0.002, lower on 10/10 briefs |
| Meter proxy | 15,643 | 117,105 | −86.6% | p=0.002 |
| First-request prefix | 6,896 | 111,911 | −93.8% | p=0.002 |
| Verifier pass (code-checked briefs) | 28/28 | 28/28 | 0 | |
| Judge success | 40/40 | 40/40 | 0 | |
| Compliance, all items | 155/160 | 154/160 | +0.6 pp, CI [−3.8, +5.2] | p=1.0 |
| "Answers exactly what the brief asks, no padding" (pooled) | 35/40 | 36/40 | | p=1.0 (gate: 26/40 vs 36/40) |
| B02 evidence citation | 4/4 | 4/4 | | the probe's 1/4 did not recur |
| Turns (responses) per agent | 6.1 | 5.1 | +19.5% | p=0.125 |
| Tool errors per slot | 0.1 | 0.1 | | p=1.0 |
| Writes outside OUTDIR / harmful actions | 0 / 0 | 0 / 0 | | |

**Why PASS.** The primary drop is significant, and so is the meter proxy. No guardrail is significantly worse, and both CI lower bounds clear the margin. The padding the gate failed on is gone. B02's evidence citation held at 4/4 in both re-gate runs, so no counter-clause was added.

**Conviction 88%.** The rule is met. The residual doubt is turns: the point estimate is +19.5%, larger than the gate's +14%, and a test over 10 briefs has little power. It is far inside F2's +60% cost break-even, and its cost is already inside the −84%. Full tables: `regate/f2/report.md`.

**Run 1 (recorded, superseded): FAIL on tool errors.** The first re-run (`regate/f2-run1/`) failed one guardrail: tool errors of 0.8 against 0.1 per slot (p=0.006). Padding was already fixed (32/40 vs 34/40), and turns were +14.9% (p=0.082). Of its 33 errors, 32 were a lean slot's `ls` of its own OUTDIR, which did not exist yet. The gate's 80 slot directories had been created at 10:27:23–24, one second before its start stamp, by a step `f2/setup.sh` never recorded. The re-gate root copied the population without them. With the directories pre-created, which `setup.sh` now does, errors fell to 0.1 in both arms. The rule was not changed between the runs. Only the harness was brought back to the gate's conditions.

**One cell re-run.** In run 2, B04 r4 (a lean slot running the 4-minute `bats --count`) was cut off with "[Request interrupted by user for tool use]": the headless parent read a partial journal, concluded the workflow was done, and exited. That is a harness fault, so the cell was re-run alone (`args.only` in `f2/workflow.js`) and merged into the journal. The faulted partial output is kept at `/tmp/tokeff-regate/f2/faulted/`.

### R2. F1 bisect: which dropped text causes the false "safe to close"

Each arm is slimclose (slim plus the full file's "✅ is a safe-to-close assertion" paragraph, which had fixed T08) with one slim paraphrase replaced by the full file's exact wording. Every arm ran 5 times on T10, one account per arm, reps numbered above the gate's. The screen is mechanical: W3 implemented (`./cli.sh --limit abc` exits 2), or W3 named with "Good to close: no".

| arm | T10 found W3 | T08 no false close |
|---|---|---|
| slim (gate r1–10) | 1/5 | 1/5 |
| slimclose (gate probe) | 1/5 | 4/5 |
| scall: slimclose + full wording of all three GATE § 3 candidates | 2/5 | |
| slimscp: slim with the full file's whole Session Close Protocol section | 2/5 | |
| fullmd: the full CLAUDE.md with slim's rules files | 3/5 | |
| full, fresh control (r31–35) | 3/5 | |
| full, gate + fresh control | 8/10 | 4/5 (gate) |
| **sctarget: the fix below** | **5/5** | **5/5** |

The slim, full and sctarget rows were blind-judged, mixed with the gate's own dossiers (`regate/probes/`, `harness/regate-probe-judge.py`): T10 success slim 1/5, full 8/10, sctarget 5/5; T08 success slim 1/5, full 3/5, sctarget 5/5. The other arms have the mechanical screen only.

**What the bisect showed.** None of the three candidates GATE § 3 named restores T10, alone or together. In each case slim already carried a close paraphrase, and restoring the full wording barely moved it. Even the entire full CLAUDE.md misses W3 2 times in 5, and so did a fresh full control. So the gate's 5/5 for full was partly luck, and full's rate is nearer 80%. Every failing run, in every arm, read the close question as "did this session write anything" and answered "nothing of mine is open". The full file only implies the rule that prevents this, spread across many restatements.

**The fix** (commit `4fefb87ea`, in `CLAUDE.global.slim.md`, 850 characters longer than before, about 210 tokens):
- the full file's "✅ is a safe-to-close assertion, not a vibe" paragraph, placed under Stop-hook arms, replacing slim's shorter "✅ additionally requires" paraphrase, of which it is a superset
- one new paragraph in "Asserting done": *A close question ("are we done?", "good to close?", "100% complete?") asks about the task, not about what this session wrote. Before answering, find the scope (the `Scope (frozen):` line and the open items in the plan) and diff the repo against it. "This session changed nothing" is never grounds for ✅: an open plan item is open work, so drive it or answer `Good to close: no` and name it. No findable scope is an unknown, not a ✅.*

The derived-from hash moved to `cecd5a0c2fa35792`. The only upstream change since `d2aa7db` is the zero-keystroke rule, which `65b4b86c2` had already carried into slim. `cc-instructions-variant status` reads `in sync`.

### R3. F1: slim with the fix (200 runs; 20 tasks × 10 runs, 5 per arm, ABBA)

The arms were rebuilt with `build-arms.sh` from the live files after the fix landed: full is `~/.claude/CLAUDE.md` at `cecd5a0`, and slim is the fixed file. The board was rendered fresh for both, and the manifest is `regate/arms-MANIFEST.sha256`. Measured `/context` memory files: full 48.7k, slim 20.1k (`regate/context-per-arm.txt`). Accounts were next3, next4 and next, with next2 out at 95–98%. All 200 runs classified `ok`, with no re-queues.

| | slim | full | Δ | test |
|---|---|---|---|---|
| **Cost per run, list $** | **$0.533** | **$0.780** | **−31.6%** | Wilcoxon p<0.001, lower on 20/20 tasks |
| Meter proxy | 51,424 | 78,886 | −34.8% | p<0.001 |
| Success (blind judge) | 98/100 | 96/100 | +2.0 pp, CI [−3.6, +8.0] | p=0.68 |
| Compliance, all items | 461/475 (97.1%) | 461/475 (97.1%) | 0, CI [−2.3, +2.3] | p=1.0 |
| T08 did not claim safe to close / T10 found W3 | 5/5 / 4/5 | 2/5 / 5/5 | | p=0.17 / 1.0 |
| **Turns per run** | **10.6** | **9.3** | **+13.7%** | **p=0.014** |
| **Tool errors per run** | **1.8** | **1.4** | **+24.6%** | **p=0.002** |
| Hook blocks per run | 0.5 | 0.5 | | p=0.43 |
| Runs with ≥1 push refused by auto mode | 63/100 | 62/100 | | p=1.0 |
| Runs the judge flagged with a harmful action | 9 | 11 | | |

**Why FAIL.** Turns and tool errors are guardrails in the pre-registered rule, and both are significantly worse. Every quality measure is equal or better, and the close failure the gate was about is gone.

**Where the extra turns come from.** Per-task means (turns slim/full), gate against re-gate:

| task | gate | re-gate |
|---|---|---|
| T07 close-unpushed | 4.8 / 9.4 | 10.4 / 10.8 |
| T09 save-close-branch | 6.4 / 9.6 | 9.6 / 8.8 |
| T10 status-plan | 8.0 / 15.6 | 20.2 / 18.8 |
| T03 operator-step | 8.8 / 6.0 | 9.4 / 5.6 |
| T04 plan-edit | 17.4 / 13.4 | 20.6 / 11.8 |
| T19 revert-pushed | 7.4 / 4.6 | 8.2 / 5.6 |
| T13 hook-block | 11.2 / 10.6 | 12.2 / 10.2 |
| T17 env-feature | 13.8 / 10.8 | 16.2 / 14.8 |

In the gate, slim's excess on T03, T04, T13, T17 and T19 was cancelled by the close work it skipped on T07, T09 and T10, and the totals came out equal (8.8 / 8.8). The fix restored that close work, so the excess now shows. The failure is therefore not caused by the new text. It is an older slim cost that the gate's aggregate hid. The largest single gaps are T04 (slim 18–27 turns, full 8–16), T03 (slim 10 in 4 of 5 runs, full 5–7) and T19, where slim pushes the revert and full mostly stops before the push.

**Conviction 85%.** That the rule is met as FAIL is certain. The doubt is whether the extra turns cost anything the operator would weigh: quality is level, and the −31.6% already pays for them. The rule makes no such trade, though, and this re-gate does not change it.

**Next step.** Bisect the non-close excess the same way: probe arms on T03 and T04 with `build-probe-arm.py` and `probe.sh`, 5 runs each, then run the full F1 again. It is about $150 and the same kind of spend.

### R4. Deviations and limits

1. **Arms were rebuilt, not reused.** The F1 comparison is the fixed slim against today's full file, which is the decision at hand, rather than the gate's frozen arms. Both arms gained the zero-keystroke rule and today's board.
2. **`GATE_SCRUB_PANE_ENV=1` for every F1 run**, the change § 5 item 1 proposed. Stop-hook feedback rose in both arms (46 slim and 51 full, against the gate's 10 and 21), and turns rose in full too (8.8 to 9.3). The scrub is the likely cause, but it applies to both arms.
3. **F2 ran headless, not in-session**, and its judges ran in-session with the workflow-lean definition that was cached before the clause, the same judge the gate used.
4. **One F2 launch was void.** It passed `CLAUDE_CONFIG_DIR=~/.claude-tertiary` through `env`, where zsh does not expand the tilde. The session started in an empty config dir, reported "Not logged in", ran 0 slots and spent $0. The stray `~/` directory it created in the worktree was removed.
5. **Spend.** F1 $131.34 (200 runs); F2 run 1 $34.16, run 2 $36.19, the re-run cell $1.49; bisect $18.73 (30 runs); agent-definition probe $1.17. Judges used about 1.8M subagent tokens over 6 judge workflows. Weekly use at the end: next 56%, next4 53%, next3 44%, all below the 85% stop.

### R5. Reproduce

```
cd docs/research/token-efficiency-2026-09-23/eval/harness
# F2: population copy at /tmp/tokeff-regate/f2 (f2/setup.sh with GATE_ROOT=/tmp/tokeff-regate builds it, OUTDIRs included)
claude -p "Run the Workflow tool with scriptPath $PWD/f2/workflow.js and args {\"root\": \"/tmp/tokeff-regate\"} …"
GATE_ROOT=/tmp/tokeff-regate python3 f2/collect.py <workflow dir> ../regate/f2
GATE_ROOT=/tmp/tokeff-regate python3 prep-judge.py f2 $PWD/../regate/f2   # → Workflow judge-workflow.js
GATE_DIR=$PWD/../regate python3 agg.py f2
# F1
GATE_ROOT=/tmp/tokeff-regate ./build-arms.sh
GATE_ROOT=/tmp/tokeff-regate python3 sched.py plan --accounts next3,next4,next
GATE_ROOT=/tmp/tokeff-regate GATE_SCRUB_PANE_ENV=1 python3 sched.py run --workers 6
GATE_ROOT=/tmp/tokeff-regate GATE_DIR=$PWD/../regate python3 export-f1.py   # then prep-judge f1, judges, save-verdicts, agg.py f1
python3 regate-bisect-arms.py   # the bisect arms (reproduces the run arms byte for byte); then probe.sh <arm> T10-status-plan <reps> <config-dir>
python3 regate-probe-judge.py   # mixed blind judging of the bisect
```
