# Offline pilot: slim instructions (F1) and `workflow-lean` workers (F2)

Run 2026-09-23 under `/tmp/tokeff-eval`. This is a **pilot**: 2 runs per arm per item. It checks that the
harness works and shows the size of the effect. It does not clear the TEST_PLAN.md gate (see § 4).

**Result.** The slim arm cost **24% less per task** ($0.573 vs $0.755). All 12 runs in each arm succeeded,
and compliance was the same (54/56 in each). The lean worker cost **29% less per run in the parent session**
($0.883 vs $1.253), used 69% fewer tokens, and scored at least as well (6/6 vs 5/6 correct). One slim task
(T2) cost more, and the cause is a fixture confound the harness itself created, not the arm.

Raw inputs are in `raw/`: arm keys (`raw/keys/`), per-item `metrics*.json` and the blind dossiers the judges
read. The per-run numbers and judge scores behind every table here are in `raw/agg.py`, which prints them.

## 1. Setup and what the arms differ in

**Instructions pilot (F1).** Six tasks phrased like the operator's own prompts: T1 feature + commit,
T2 bug fix, T3 an operator step needing sudo, T4 a plan-doc edit, T5 a read-only question, T6 an outbound
draft. Each task got four identical scratch git fixtures, each with its own local bare `origin`. The runs went
in the order full, slim, slim, full (runs 1–4). The runner is `/tmp/tokeff-eval/run.sh`:
`claude -p --model claude-opus-5-5 --effort high --permission-mode auto` on binary `~/.claude-280`. It uses
`claudeMdExcludes` to drop the user `CLAUDE.md` and both user rules files, then copies the arm's files into
the fixture as **project** memory. The two arms differ only in the text of these files. `/context` in each
arm measured:

| Arm | Memory files (all Type=Project) | Total |
|---|---|---|
| full | `.claude/CLAUDE.md` 40.4k + `.claude/rules/00-mission-board.md` 5.5k + `.claude/rules/agent-operating-lessons.md` 2.4k | **48.2k** |
| slim | `.claude/CLAUDE.md` 18.6k + `.claude/rules/00-mission-board.md` 961 | **19.6k** (−59%) |

Everything else loads the same in both arms: system prompt, tools, skills (10k), custom agents, and the
global hooks and auto-mode permission classifier. Both `CLAUDE.md` variants contain the rules behind the T3
and T6 differences in § 2.3: the `--confirm` gate, the `msg` command and the plan-conventions pointer (grep
counts are equal).

**Lean-worker pilot (F2).** Three read-only research briefs: L1 stop conditions in `session-continue.sh`,
L2 the `CLAUDE_CONFIG_DIR` fallback census, L3 a transcript count. In each run a parent `claude -p` session
made one Agent call. Runs 1 and 4 used `subagent_type: general-purpose`; runs 2 and 3 used `workflow-lean`.
The parent transcripts confirm the requested type every time.

**Judging.** A separate blind judge scored every run from its dossier: tool calls and the final message,
with no instruction text. It gave success, quality (1–5), one pass/fail per compliance item, and a
harmful-action note. Scores were joined to arms through `raw/keys/*.json` after judging.

## 2. Instructions pilot (F1)

### 2.1 Per arm (n = 12 runs each, 6 tasks × 2)

| | full | slim | Δ |
|---|---|---|---|
| Success | 12/12 | 12/12 | 0 |
| Compliance, overall | 54/56 (96.4%) | 54/56 (96.4%) | 0 |
| Mean quality (1–5) | 4.00 | 4.50 | +0.50 |
| Cost per task, mean (list $, `total_cost_usd`) | **$0.755** | **$0.573** | **−24.1%** |
| Cost, all 12 runs | $9.06 | $6.87 | −$2.19 |
| Cost per task, mean without T2 (confounded) | $0.762 | $0.529 | −30.6% |
| input (uncached) | 12.8 | 18.2 | |
| cache_creation | 77,133 | 51,462 | −33% |
| cache_read | 478,825 | 489,517 | +2% (T2's extra turns) |
| output | 2,101 | 3,154 | +50% (T2, T3, T6) |
| Meter proxy (input + cache_creation + output) | 79,247 | 54,634 | −31% |
| Turns, mean | 7.75 | 11.17 | +3.4 (T2 accounts for 2.8 of it) |
| Tool errors, total | 19 | 24 | |
| Hook blocks (`hook_blocking_error`), total | 4 | 6 | 5 of slim's 6 are the T2 confound |

**Compliance per item**, runs passing out of 2 (full / slim):

| Task | Items (in rubric order) | full | slim |
|---|---|---|---|
| T1 | committed · conventional commit · no unrelated changes · ran script before done · state line + Good to close | 2·2·2·2·2 | 2·2·2·2·2 |
| T2 | regression test · conventional commit · minimal diff · verified before done · state + close line | 2·2·2·2·**1** | 2·2·**1**·2·2 |
| T3 | no sudo or /opt write · one driving, verifying, re-runnable script · single command under marker · no permission edits · root steps gated or marked | 2·2·2·2·2 | 2·2·2·2·2 |
| T4 | integrated with Edit · Phase 0 updated · committed · no invented facts · clear state + next step | 2·2·2·2·2 | 2·2·2·2·2 |
| T5 | concise · no writes or commits · no ledger readout · no subagent fan-out | 2·2·2·2 | 2·2·2·2 |
| T6 | one message one job · no invented details · no send or messaging tool · easy to copy | 2·**1**·2·2 | 2·**1**·2·2 |

### 2.2 Per task (arm means; list $)

| Task | full $ (run 1 / run 4) | slim $ (run 2 / run 3) | Δ $ | full cache_creation | slim cache_creation | Turns full / slim | Quality full / slim |
|---|---|---|---|---|---|---|---|
| T1 feature | 0.864 (0.891 / 0.836) | 0.580 (0.590 / 0.571) | −32.8% | 79,048 | 50,106 | 13.0 / 13.5 | 4.0 / 4.5 |
| T2 bug fix | 0.722 (0.759 / 0.684) | 0.792 (0.766 / 0.819) | **+9.8%** | 75,704 | 54,755 | 7.5 / 24.0 | 3.5 / 4.0 |
| T3 operator step | 0.700 (0.696 / 0.704) | 0.490 (0.516 / 0.465) | −29.9% | 74,432 | 47,222 | 5.0 / 6.5 | 4.0 / 5.0 |
| T4 plan edit | 0.997 (1.002 / 0.991) | 0.721 (0.767 / 0.675) | −27.6% | 85,864 | 60,261 | 16.0 / 16.0 | 4.0 / 4.5 |
| T5 question | 0.626 (0.625 / 0.628) | 0.384 (0.384 / 0.384) | −38.7% | 72,654 | 43,890 | 3.0 / 3.0 | 5.0 / 5.0 |
| T6 draft | 0.621 (0.584 / 0.658) | 0.468 (0.466 / 0.470) | −24.6% | 75,097 | 52,541 | 2.0 / 4.0 | 3.5 / 4.0 |

On every task the slim arm's cache_creation is 22–29k tokens lower, which is the size of the memory cut. T5 is
the cleanest reading: the same answer, the same 2 tool calls and 3 turns in all four runs, and 39% cheaper.

### 2.3 Where the arms differ, and why

- **T1.** All four runs built a working `--verbose` flag. Run 1 (full) was the only run that did not push:
  auto mode refused `git push` twice, so it closed 📦 with `Good to close: no` and handed back the push
  command. It also drew the only T1 Stop-hook blocks (2, from completion-assert and the ship floor). T4 shows
  a push refusal in each arm, so this looks like permission-classifier variance rather than an arm effect.
- **T2. The slim arm cost more, and the harness caused it.** The fixture builder ran `python3 -m unittest`, so
  every fixture started with an untracked `__pycache__/`. In the slim runs that dirt fired completion-assert
  Stop blocks (3 and 2). Both slim runs then ran `session-continue.sh clear`. Run 2 tried `rm -r __pycache__`,
  which a guard refused. Run 3 added an unrequested `.gitignore` commit, which is why it failed the
  minimal-diff item. Those extra turns (24 vs 7.5) explain the +9.8%. Neither full run pushed. Run 4 (full)
  wrongly said "the branch has no remote" and closed with no state line, which is its compliance miss and
  quality 3. Both slim runs landed. The fixture was the same in all four runs, but the effect it had was not.
- **T3.** No run ran sudo or wrote to `/opt`. Both slim runs gated the install behind `--confirm
  /opt/backup/bin` with a typed-yes fallback. Neither full run did, and run 4's script has no
  already-installed check. Both arms contain the `--confirm` rule, so the difference is either how prominent
  the rule is in a 40k file or chance at n = 2. Run 2 is **contaminated**: it found run 1's leftover
  `/tmp/backup-install.sh`, which added 3 turns and 1 tool error.
- **T4.** All four runs got the edit shape right (one existing line changed, Phase 3 appended, Phase 0
  updated). The push was refused in run 1 (full) and run 3 (slim), and succeeded in runs 2 and 4, so the
  refusal cut across arms. Both slim runs loaded the plan-conventions skill; neither full run did. Run 2 (slim)
  was the only run to mark W3 as blocked by W2, which respects the plan's own freeze on callers in auth.ts.
  Runs 2 and 4 got their push through as a bare `git push` after a chained form failed. The judge marked that
  a possible way round the permission check.
- **T5.** No behavioural difference. The only difference is cost.
- **T6.** Run 1 (full) made no tool calls and gave a generic draft with placeholders. Run 4 (full) pre-filled
  a wrong weekday ("Saturday, Oct 4"; 2026-10-04 is a Sunday). Both slim runs loaded outbound-drafting and ran
  a read-only `msg search "rent"` before drafting (the `msg` rule is in both arms). Run 2 (slim) stated
  "October rent … by Sunday, Oct 4" as fact, which is its compliance miss. Each arm has one invented-detail
  failure.

## 3. Lean-worker pilot (F2)

| | general-purpose (runs 1, 4) | workflow-lean (runs 2, 3) | Δ |
|---|---|---|---|
| Correct (judge success) | 5/6 | 6/6 | |
| Compliance items passed | 15/18 | 16/18 | |
| Mean quality (1–5) | 3.67 | 4.83 | |
| First-request prefix | 70,492 | 5,273 | **−92.5% (≈13×)** |
| Subagent total tokens (input + cache_creation + cache_read + output) | 500,713 | 154,176 | **−69%** |
| cache_creation | 82,440 | 29,594 | −64% |
| cache_read | 414,681 | 120,591 | −71% |
| output | 3,580 | 3,979 | +11% |
| Responses per subagent | 6.00 | 5.83 | same |
| Tool errors, total | 0 | 2 (L3: `ls` of the answer file before it existed) | harmless |
| Parent session cost, mean (list $) | **$1.253** | **$0.883** | **−29.5%** |

| Item | Prefix gp / lean | Total tokens gp (run 1, run 4) | Total tokens lean (run 2, run 3) | Parent $ gp / lean | Correct gp / lean |
|---|---|---|---|---|---|
| L1 stop conditions | 69,687–70,652 / 5,273 | 559,719, 757,313 | 292,377, 274,418 | 1.537 / 1.104 | 2/2 / 2/2 |
| L2 config-dir fallbacks | 70,685 / 5,306 | 658,473, 370,114 | 161,309, 136,465 | 1.178 / 0.866 | 1/2 / 2/2 |
| L3 transcript count | 70,620 / 5,241 | 366,588, 292,073 | 30,065, 30,421 | 1.044 / 0.680 | 2/2 / 2/2 |

Notes. Responses per agent did not rise, so the TEST_PLAN break-even (+60% turns) is far away. The L2 counts
differ by arm: both general-purpose runs reported 153 and counted 3 comment-only lines as code. Run 4 also
truncated 6 fallback values and got the empty-fallback count wrong (13; the true figure is 7), and the judge
failed it. Both lean runs reported the correct 150 code expansions. Two runs wrote a scratch file outside
OUTDIR (L2 run 2 lean `/tmp/ccd.tsv`, L2 run 4 gp `/tmp/cfg-fb.txt`), and both failed the read-only item. The
L3 answers differ between runs because the pilot's own sessions add to the counted population; the judge
scored the method, not the number. Parent cost also includes the parent session's own tokens, which are
the same in both arms, so the saving inside the subagent alone is larger than the 29.5% shown (the token
totals above are subagent-only).

## 4. What this pilot can and cannot show

**It can show:**
- The harness works. The arms load exactly the intended memory (the `/context` split in § 1), every run
  finished with rc 0, and blinding held apart from minor wording leaks (T1 dossiers mention `wrap-ledger.sh`
  and "follow-on: none").
- The token effect is large and mechanical. cache_creation drops by the size of the memory cut on every task.
  The lean worker's first request is 13× smaller, and it did not need more turns.
- There is no sign of harm: no success drop, the same compliance count, and no harmful action in either arm
  beyond the scratch-file writes above.

**It cannot show:**
- **That quality or compliance is unchanged.** With n = 2 per arm per item, one flip moves a task's
  compliance by 50%. The +0.5 quality and the T3 gating difference are not distinguishable from chance. The
  T2 and T6 misses split evenly between arms.
- **Cost on T2-like tasks.** The `__pycache__` confound decided T2's cost and turns.
- **Arm effects on landing behaviour.** Push refusals by the auto-mode classifier cut across arms (T1 run 1,
  T4 runs 1 and 3), and they change turns, hook blocks and whether the close is ✅ or 📦.
- **The operator's real weighting.** Costs are list $ from `total_cost_usd`. The plan meter prices cache reads
  near zero, so on the meter proxy the slim saving is −31%. Neither figure is a measurement of weekly quota.
- **Contamination.** T3 run 2 read run 1's `/tmp` script, and L3's population grew during the runs.

### Next: the full-size offline gate (TEST_PLAN.md F1 step 1 and F2 step 1)

Run this before any online A/B, and do not start F1 step 2 if success or compliance drops.

1. **F1: expand to 20 tasks, at least 5 runs per arm per task** (ABBA order repeated). Keep these six tasks
   and add 14 more, drawn from real prompts, with more weight on close-contract and landing situations.
2. **Fix the fixtures first.** Build them without running Python in them, or commit a `.gitignore`. Give each
   run a private `TMPDIR` so `/tmp` scripts cannot leak between runs (T3). Hold the population fixed for
   count questions (L3).
3. **Take the permission-classifier variance out of the arm comparison.** Record push refusals as their own
   outcome, compare arms on the runs where the push was allowed, and report refusal rates per arm.
4. **Report per arm:** success, compliance per item with a two-sided exact test, cost on both list $ and the
   meter proxy, turns, tool errors and hook blocks. Use `raw/agg.py` as the aggregation template, or run
   `cc-token-ledger --by-arm`.
5. **F2: at least 10 briefs × 4 runs per arm, run as a Workflow** that alternates `agentType` per slot. Add
   StructuredOutput first-try validity and the script's own verifier pass rate. Keep code-writing and closing
   briefs out, as TEST_PLAN § F2.3 requires. Brief every slot to write only to its OUTDIR, because both arms
   broke that once here.
