# Claude API audit: prompt-audit, cost-optimize, hillclimb (2026-10-04)

Method: the claude-api skill's prompt-audit, cost-optimization, prompt-caching and eval guides (eval-hillclimb, eval-audit, cost-hillclimb), plus the three 2026 pages listed under Sources delta.
- Target models: Opus 5.5 at effort high (the default), Fable 5.1 (frontier), and Sonnet 5.5 and Haiku 4.5 where they are pinned.
- Cost is weekly plan quota, not dollars.
- 12 read-only shards produced 194 findings.
- Each finding was checked by two adversarial lenses: keep-list and mechanical. A finding survives only when both lenses accept it.
- Repo at `7ad2ce9fd`.

## Answer first

- **152 of 194 findings survived.**
  - 135 are exact string replacements. After merging 5 overlapping duplicates and adding 2 companion hunks the verifiers asked for, they become 132 hunks.
  - The other 17 are plan items: 9 new code, 7 operator decisions, 1 measurement.
- **Every one of the 132 hunks was checked:**
  - It matches its file exactly once at `7ad2ce9fd`.
  - Applied in order on a scratch copy, it still matches exactly once at its turn.
  - No new text re-contains its own old text.
  - Every edited script passes `bash -n` or `py_compile`.
- **What the apply set fixes:**
  - **Email recipe:** at 10,393 chars it is over Claude Code's 10,000-char hook cap. All 19 injections in 14 days arrived as a 2 KB preview, so rules 1-6 never reached the model. hooks-a-01..05 take it to 9,323.
  - **Global instructions:** 8 paths or commands in the global instructions do not resolve outside this repo.
  - **`/evolve-skill`:** it cannot run. It uses a 2.1.114 binary that refuses Opus 5.5, and `--bare`, which authenticates only with an API key. It also self-grades. hillclimb-01..08 fix this.
  - **Teammate and agent text:** it describes runtimes that no longer exist: TeamCreate, `team_name`, the eval track, `claude-previous`, and a 2026-06 effort mechanism.
  - **Headless helpers:** the probe, the nightly sweep and the router classifier load the operator's CLAUDE.md, hooks and tool schemas.
  - **dl-sweep:** a silent parse bug reports `candidates=0` whenever Sonnet 5.5 drafts text before its final JSON.
- **Largest applied cost lever:** read-only Workflow slots ran as the default agent. 258 slots in 3.25 days started at about 97k tokens each; a lean slot starts at 9.2k. Lean re-gated at equal correctness and -84% on 2026-09-24. slim-09 puts that default in the always-loaded venue rule.
- **The two biggest measured cost classes are not text edits, and both stay operator questions (§2):**
  - cold re-writes after more than 1 hour idle: 33% of main write tokens;
  - full-transcript resumes onto another account after a limit hit: 17%.
- **Hillclimb verdict:**
  - The one valid next run is a held-out confirm of the live slim instructions (hillclimb-09). The F1 PASS was read on the same 20 tasks that chose its edits, and the live text has drifted +8.6% since the gated pin.
  - The codex-probe review eval needs an instrument audit before it routes anything else.
  - `/evolve-skill` is not a climb target until the runner is repaired and it has 15+ cases.
- **Budgets after the set:**
  - User tier: 59,516 → 59,807 of 60,000 loader units (slim 26,939 → 27,182; close rules 30,293 → 30,341; mission board 2,284). That leaves only 193 of headroom. Run `bin/cc-instruction-budget assert` at land, and if the mission board has grown, drop slim-09's parenthetical (-72).
  - Skill listing: the repo-owned total goes 13,092 → 12,661, and the `skill-listing-budget` lengths check goes red → green (launch-film was 641 chars against a 250 cap). That check was run directly; cc-bats deferred under load.

## 1. Apply-ready set (string replacements, by file)

Land each group as one commit, with the same file and lockstep where noted. The exact old and new text is in this workflow's `apply` array (scratch copy at `/tmp/capi-audit/synth/apply.json`, ephemeral).

**CLAUDE.global.slim.md** (always loaded, every repo)
- **slim-09** (merges session-cost-01). Pattern: cost 2.2/2.3, progressive disclosure. Read-only Workflow slots take `workflow-lean`; a slot that writes code, commits, lands, closes or needs a skill or MCP keeps the default. Saves up to about 88k 5-minute write tokens per slot.
- **slim-01, -02, -03.** A repo-relative path, or a bare name not on PATH, becomes `~/.claude/scripts/handoff-fire.sh`. Round 3 measured this failure class as 26 of 43 slim non-zero exits.
- **slim-04.** `bin/cc-permission-audit` becomes the name that is on PATH.
- **slim-10.** Pattern 1d (expired conditional): deletes the 2.1.260 alias pin; no 2.1.260 process is left. -95 chars.

**CLAUDE.rules.slim.10-session-close.md**
- **slim-05..08.** Repo-relative paths in the close protocol (handoff-fire, operator-readout, desk-strand-replay) now run from any repo.

**.claude/rules/agent-operating-lessons.md, .claude/CLAUDE.md, bin/cc-memory-rotate**
- **project-rules-01.** The size claim is stale (~43K); the file is 9,871 B. The cleanup figure is kept as history.
- **project-rules-02.** The `ship-land.sh:3258` citation drifted. It now anchors on the literal `shellcheck "${sc_todo[@]}"` in `run_gate`.
- **project-rules-03.** The `validate-bash.sh:1352` citation drifted. It now names the test-pinned FF-GATE block.
- **project-rules-05, -06.** The rotor writes the false claim "both surfaces load unprompted". The destination is excluded by claudeMdExcludes, and the claim was re-stamped on 2026-10-02.

**agents/**
- **agents-01 + -02** (lockstep, deep-research-sonnet). Grants Write/Edit and drops heredoc delivery. edec03003 made this fix for deep-research only, after heredoc delivery killed 2 of 15 agents. Skill stays, since 4.6% of spawns use it.
- **agents-06.** The file allowed 800K against its own 500K hard ceiling.
- **agents-07.** Removes a 1d migration-relative sentence.
- **agents-13.** A dead `research-subagents.md` pointer shipped inside every critic REVISE verdict.
- **agents-14.** Removes a perishable "~2×" cost figure that the repo contradicts.

**commands/evolve-skill.md + evolve-fixtures/pyramid-principle/cases/README.md** (lockstep; supersedes commands-01, commands-02 and headless-04)
- **hillclimb-01.** Uses `cc-claude-bin` with plan-quota isolation flags, and records the served model and usage.
- **hillclimb-02.** Generate and judge become separate calls. The judge is `opus_prior` at `verify_judge`, sees the input and rubric, and must pass a known-negative check before any spend.
- **hillclimb-03.** Keeps state on disk, measures a baseline noise floor, gives the generator train cases only, and runs one hypothesis per round.
- **hillclimb-04.** Keep rule: the test score must beat the incumbent by more than the noise floor. Revert overfits; stop after 2 flat rounds or 4 rounds.
- **hillclimb-05.** README.md is no longer scored as a case. Below 15 cases, results are labeled directional.
- **hillclimb-06.** Headline is the test delta with its interval; spend is reported as `usage` in quota.
- **hillclimb-07.** The listing no longer advertises an API-key path (217 chars).
- **hillclimb-08 + 08b** (companion). README steps and run notes now match the command.

**commands/** (other)
- **commands-03.** limit-recover's fallback was hardcoded to `claude-opus-4-8`; it now reads `frontier_access.fallback` (the SSOT has opus-5-5).
- **commands-18.** Drops a pinned "Fable 5" from an example.
- **commands-04.** handoff's main example said `Opus@max`; the SSOT default is `@high` with no `--effort`.
- **commands-05.** The deleted `claude-nextN` launcher becomes `cc-lr recover`, which keeps the same session and worktree.
- **commands-06, -07, -21, -22** (lockstep). wrap claimed 👤 is not computed on the pull path. wrap-ledger has resolved `CLAUDE_CODE_SESSION_ID` since 2026-09-05. The never-guess rule is kept.
- **commands-08.** The ledger computes ⛔ from this session's class-C packets, so an unfiled ⛔ is invisible.
- **commands-09** (both corrections merged). "Relay at the top of your close" fails D6 line-1-rung. The relay now goes after the act line, and the hand-over is `▶ Run this:` with inline code.
- **commands-10.** A rule and its own "Superseded" note are merged into one current statement.
- **commands-11.** /recover has been live since 2026-09-11.
- **commands-13.** Removes a caps "DO NOT read files" that contradicted the file's own Read step.
- **commands-14, -15.** Pick the package manager from the lockfile; pnpm was missing.
- **commands-16.** Removes a third copy of a rule.
- **skills-c-08b** (companion). /research's per-brief budget now matches the corrected skill.

**skills/agent-teams/SKILL.md** (read before every teammate spawn)
- **skills-a-04..07.** Removes pinned versions and deleted launcher names, plus a stale allowlist (opus-4-8, fable-5) stated as a MUST. It now reads versions live, names the SSOT key, and spawns with the `model: opus` alias.
- **skills-a-08, -09.** Routing table and lifecycle named TeamCreate/TeamDelete, said "6 boxes" when there are 7, and treated "completion notifications" as completion.
- **skills-a-10.** An imperative for the dead set-teammate-effort mechanism plus its SUPERSEDED callout become one current rule.
- **skills-a-02.** Removes a false "the hook reaps idle teammates" guarantee: the hook closed zero panes for 9 days, and the vendor contract says only the lead ends a teammate.
- **skills-a-03.** Corrects the hook locus (RC-7) without restating the disputed $PPID mechanism.
- **skills-a-12..14** (lockstep). Fixes "TaskStop is authoritative" in place and removes its two downstream retractions.
- **skills-a-01.** Replaces `killall -9 tmux`, which kills every tmux session on the machine, with a per-pane close by recorded id, including the stale-id pin for kitty.
- **skills-a-15.** The hang recipe now leads with the fleet runtime and goes through the Shutdown Protocol, with no raw `pgrep -f` kill.
- **skills-a-16.** Corrects the brief-cost rationale: a brief is cache-read after turn 1, so its cost is context occupancy. The hook-enforced cap is unchanged.
- **skills-a-17.** Drops a "(NEW)" marker.

**Other skills**
- **skills-a-18..20** (browsermcp). The retired tool's imperative now reads as history; agent-browser is the live path.
- **skills-a-21, -22** (agent-browser). Text was conditioned on BrowserMCP, which is retired.
- **skills-a-25** (coding-standards). Removes a provenance aside from the heading.
- **skills-b-01..04, -06, -08, -09** (frontier-run).
  - Frontmatter `effort:` is honoured on 2.1.284.
  - The cost line is quota at about 2-5×.
  - `claude-prev` is the legacy launcher; the 🚨 narrative is kept.
  - Fixes a dead path and stale model names.
- **skills-b-02, -10** (frontier-campaign). The effort step was a no-op after 2.1.220.
- **skills-b-07, -19** (frontier-hole). Names SSOT keys and states cost as quota.
- **skills-b-11** (launch-film; merges session-cost-03). Description cut from 641 to 248 chars. It keeps "launch video" and the hyperframes boundary, and the listing test goes green.
- **skills-b-12** (frontend-design-vue). Playwright/BrowserMCP becomes the agent-browser CLI.
- **skills-b-13, -18, -20, -22** (demo-recording). Removes a duplicated paragraph, an iTerm2 reference (the host is kitty), a 1d quote of a wrong instruction, and a restatement.
- **skills-b-14..16** (dia-agent). The port is fixed at 9222 on 1.48.0. The three "start here" paths become one default: AppleScript first, then CDP.
- **skills-c-01, -02.** 1d vision fossil: 1568px was the Opus 4.6 tier. Claude Code clamps at 2000px (re-read in the 2.1.284 binary), so tile widths were understated by 22%.
- **skills-c-03..06, -08, -09, -11, -12, -14** (research-subagents).
  - Haiku 4.5 retrieval was given a 350K-1M budget and told "~1M" in every brief; its window is 200K.
  - "Prefer depth-2" contradicted the enforced depth-1 cap. c-06 fixes the stale reason for running flat. Both lenses accepted c-06; the harness flag read false only because of a duplicated verdict row.
  - The brief cap was unsatisfiable, and two rules each claimed the brief's last line.
  - Removes a retired Sonnet recipe and the "reinterpret below" routing.
  - Fixes four stale frontier facts and a false "Last revised" stamp.
- **skills-c-15 + hooks/validate-plan-structure.sh skills-c-30** (lockstep). Two Phase 0 defaults collapse to one: S by default, and the S session leads its own team.
- **skills-c-16, -17.** The cc-await-ping park step now applies only when no `/goal` is live. Under a live goal, validate-bash.sh denies it.
- **skills-c-18, -19, -21** (plan-update). The scaffold prescribed a teammate `/compact` (a crash), asserted a "1M / 500K free buffer" budget, and duplicated runtime detection with stale pins.
- **skills-c-22, -23, -25, -26** (resume-sessions). Fixes the wrong Fable id and false tools provenance, drops a burn-before-deadline rule (Fable has been permanent since 2026-07-20), and replaces a self-contradicting copy of the router math with a pointer to `bin/claude-accounts`.
- **skills-c-28** (permission-harvest). Drops the stale "every file is NEW" alarm and keeps the LIVE_ADDS rule.

**Hooks**
- **hooks-a-01..05** (enforce-email-formatting.py; one commit). The recipe was over the hook cap, plus 1d migration narration. Rendered size 10,393 → 9,323. With the R2 advisory (about 640 chars) the worst case is about 9,960, which is thin (see plan synth-email-guard). a-05 keeps the incident as recorded.
- **hooks-a-06, -07, -08** (agent-teams-enforce.sh).
  - The deny and the nudge pointed at TeamCreate/`team_name`; 0 of 1,251 calls carried `team_name`.
  - a-07 told the model to pass isolation beside `name:`, which silently demotes the teammate.
  - a-08 drops one migration-relative sentence. The measured 2.390 coefficient stays.
- **hooks-b-03, -04.** The model was told "(0 total)" on 4 of 5 accounts (BSD find on a symlink; 863 real), and "186 active" counted completed tasks (64 are open).
- **hooks-b-05, -06.** Removes BrowserMCP advice from every SessionStart.
- **hooks-b-09, -10.** "CLAUDE.md critical rule #2" resolves only in reso repos; it now points at the global Git Safety rule.

**Headless helpers**
- **headless-01** (handoff-fire probe). Adds `--setting-sources "" --tools ""`. Each probe cost about $1 of Fable cache-write, and a Stop hook forced false rejections.
- **headless-02** (dl-sweep). Adds `--setting-sources ""`, removing about 15K tokens of resident text and hooks from the nightly job.
- **headless-03** (dl-sweep). Parses the last array of objects instead of a first-[ to last-] span.
- **headless-05 + 05b** (router + its bats pin). The 6-second Haiku classifier gets `--tools "" --strict-mcp-config --no-session-persistence`.
- **headless-06** (model-permission-decider). The 15-name denylist becomes `--tools ""` (repo lesson "Denylist = examples"), and transcripts are no longer written per consult.
- **headless-07** (courier). Adds `--strict-mcp-config` to reviewers: zero-risk hardening, but the benefit is unproven.

### Plan items (not string replacements)

All 17 survivor plans plus synth-email-guard are listed in the `plans` array.
- **New code:** slim-15 (`CC_LADDER` is prose only), hooks-a-09 (PLAN GUARD 598 fires a week), hooks-a-11 (dod-persist shows the oldest captures), hooks-a-14 (activation parity repeats), hooks-b-01 (goal nudge every prompt), hooks-b-07 (advisory delivered twice), skills-c-24 (reaper kills reso-keepalive), synth-email-guard.
- **Measurement:** hillclimb-09.
- **Operator decisions:** slim-16 and skills-c-29 (bare cc-do needs an Enter under `!`), skills-c-27 (R1b wording), skills-c-20 (commit as you go), skills-a-24 (curl-gate script path), hooks-a-12 (config-mirror alarm plus a `.bak` bug fix), hooks-a-13 (escalation-watch contract), headless-08 (reviewer effort), session-cost-04 (local cafe-wifi description).

## 2. Cost profile

Source: session-cost shard, transcript `usage` from 2026-10-01 to 10-04 (about 3.25 days). On the plan meter cache reads count for about nothing. Writes are what bind (1-hour write = 2×, 5-minute = 1.25×), plus output.

| Static prefix of one main session (first request: 16,270 read + 64,935 written) | chars | ≈ tokens |
|---|---:|---:|
| ~/.claude/CLAUDE.md (slim) | 26,934 | 10.6k |
| rules/10-session-close.md | 30,247 | 11.9k |
| rules/00-mission-board.md | 2,281 | 0.9k |
| project .claude/CLAUDE.md + resident lessons | 16,459 | 6.4k |
| MEMORY.md index | 21,071 | 8.3k |
| **instructions block** (also in every default agent, not in workflow-lean) | **98,052** | **38.5k** |
| skill listing (at its 30k cap; 18 of 101 entries name-only) | 30,061 | 11.2k |
| deferred tool names (215; ms365 about 190 by operator ruling) | 7,129 | 3.6k |
| agent listing, SessionStart text, MCP instructions, env | 15,950 | 6.3k |

Before the W1/0053 dedupe a session's first write was 104-105k; it is now 64.9k.

| Main-session write tokens (150.0M) | tokens | share | events | mean |
|---|---:|---:|---:|---:|
| first request | 27.1M | 18% | 418 | 65k |
| **cold re-write after > 1 h idle** | **49.1M** | **33%** | 159 | 309k |
| **re-write after a limit hit or API error** | **25.9M** | **17%** | 58 | 447k |
| other cold re-writes | 3.4M | 2% | 16 | |
| incremental per-turn | ~44M | 29% | | |

Other measured items:
- Workflow agents: 131.2M 5-minute write tokens over 1,197 contexts. Default slots start at a mean of 97.3k (258 slots); lean slots at 9.2k (933 slots).
- Subagents: 22.0M.
- Per-prompt hook injections: about 0.4% of main writes.
- Memory re-attach on deploy: about 1.1%.

**Ranked levers and outcomes**
1. **Idle cold re-writes (33%).** Not applied.
   - Bounded keepalive, or lowering the idle-recycle line to 15%: both lenses rejected the text edit. waiting-recycle.sh enforces 35%/25%, 15% sits near a fresh session's size on small windows, and the keepalive was dropped on 2026-09-24 because a wake is a turn.
   - Reopen only as a cc-decide class-C packet with a conviction and a receipt.
   - The no-watcher human-return slice is 18.8M (12.5%).
2. **Limit-hit resume (17%).** Not applied. Resuming the full transcript is a recorded choice, because the summary path drops the session-scoped `/goal` hook. 24 of the 58 events are not account moves.
3. **workflow-lean for read-only Workflow slots.** Ceiling 22.7M of 5-minute writes (17% of workflow writes). Applied as slim-09.
4. **Clamp cc-await-ping --timeout to 3,300 s** (about 6-9M). Rejected. It would deafen `mailbox-wake-arm` (14,340 s) after 55 minutes and break `cc-wait` contract deadlines. The 3,300 s defaults already shipped.
5. **Skill listing back under its cap.** Token-neutral; applied for launch-film, plan item for cafe-wifi.
6. **`effort: medium` on workflow-lean.** Rejected. It conflicts with the 2026-09-22 slot table and the measured grounding floor, which F2 cannot measure.
7. **Headless isolation** (headless-01, -02, -05, -06, -07). Applied. The per-probe saving is measured; the fleet-wide share is small.

Not applicable to Claude Code on Max: Batch, keepalive or pre-warm requests, task budgets, stop sequences, spend limits.

## 3. Hillclimb verdict

| Eval | Valid target? | Why |
|---|---|---|
| token-efficiency F1 (20 tasks, ABBA, blind judge, pre-registered agg.py) | **Confirm, not climb** | Rounds 2-4 edited slim using failures on T03/T04/T08/T10/T16/T19, then read the PASS on the same 20 tasks; R4.5 added reps, not tasks. The live slim has grown 53,769 → 58,378 chars over 8 ungated commits past pin d446c60e. |
| token-efficiency F2 (10 briefs, code-verified truth) | No | Saturated (28/28, 40/40). A model × effort walk would push research slots to low, against the standing rule and the recorded grounding floor. |
| codex-probe review sweeps (36 items, 3-judge blind) | **Audit first** | Scores are flat (6-14 of 36) across about 15 arms. 17 of 36 items are never credited: all of cp-06, three of cp-02's four, and items in cp-04, -05, -08 and -09. Recall-only scoring, even though `reported` is stored. |
| memory-eval (sealed holdout) | Not yet | 19 queries leave a 2-query holdout (±23 pp). The proposed mining would select gold with the incumbent weights. |
| /evolve-skill + pyramid-principle (4 cases) | No | Runner broken (fixed by the set). n=4 is directional, and the skill lives in another repo. |

**Recommended next run: hillclimb-09, a held-out confirm of the live slim instructions.**
- Author 10 new tasks that no editing round has read. Do not reuse id T21; F4 uses it.
- Weight the tasks toward the patched classes: close honesty, one-command hand-over, refused push, open plan work.
- Run current slim against current full at 5 reps per arm, ABBA, with agg.py's rule unchanged.
- Re-judge about 20 round-4 dossiers as a drift anchor.
- Cost: about 100 runs × $0.63 ≈ $63 list, roughly 3-10 W-pp across 3 accounts. That is above the 2-4 W-pp band that needs no ask, so it needs operator approval.
- Attach it to the existing INSTRUCTION_BUDGET.md Known issue rather than filing a new row.

Zero-quota follow-up before any review-class routing change: compute precision (`reported` minus credited) from the existing scores.jsonl, and audit the gold for the 17 never-credited codex-probe items.

## 4. Rejected findings (verifier reason; do not re-propose without new evidence)

**slim**
- **slim-11:** "§ W3.6" means section 6 of W3, which exists; the anchor is not dangling.
- **slim-12, -13:** the two pointers are byte-identical files. Agreeing duplicates are working redundancy (split verdict).
- **slim-14:** it sits inside the paragraph 4fefb87ea restored verbatim to fix the T10/T08 false closes. Do not paraphrase it without a re-gate.
- **slim-17:** the research-program exemption is a 3-day-old dated ruling, pinned per-rule by bats.
- **slim-18:** F1 round 5 is underpowered as designed (R4 at that size was INCONCLUSIVE), the realistic cost is about $315-950, it drops resident guards, and re-gating is the operator's call.

**project-rules**
- **project-rules-04:** the land gate refuses it (resident_adds replay rc=1).

**agents**
- **agents-03:** dropping Skill narrows capability; 4.6% of spawns use it. The token study filed it as a gated FLAG.
- **agents-04, -05:** the lead skill still inlines 3-15K returns, so the fix needs a cross-file operator call.
- **agents-08:** it is a depth floor, inlined by the lead skill and used as a re-spawn trigger.
- **agents-09, -10:** recorded decision history, cited by a hook comment.
- **agents-11, -12:** the 09723d748 retention was deliberate, and the agent has 0 spawns.
- **agents-15:** overclaims what the guide says for Fable 5.1, and has no runtime effect.
- **agents-16:** a frontmatter effort pin could demote xhigh Workflow slots and Fable spawns; probe first.
- **agents-17:** deletes cited evidence before the measurement that would replace it.

**commands**
- **commands-12:** /commit is user-invoked and advertises autosquash; this is the operator's design (split verdict).
- **commands-17, -19:** dated Why records on the keep-list.
- **commands-20:** misread. SKILL.md:480 keeps the $ band and the 15-second abort.

**skills**
- **skills-a-11:** cc-model-registered is not the dispatch gate, and modelUsage is unverified for Agent spawns.
- **skills-a-23:** the descriptions agree; untested trigger change.
- **skills-b-05:** it would add an interactive Fable-lead command, which the global rule restricts.
- **skills-b-17:** misattributed, and it contradicts the skill's own Signal references.
- **skills-b-21:** this section is the designated home of that decision history.
- **skills-c-07, -13:** /research §6 requires the $ band, and cc-quota-price cannot price a wave before it spawns.
- **skills-c-10:** the override explicitly retains that math as history.

**hooks**
- **hooks-a-10:** the handoff-intent nudge is the rail for live-session teardown, and once-per-session would spend it on the turn-1 brief. Narrower idea: skip `<task-notification>` prompts.
- **hooks-b-02:** latent, because 0012 is not live, and `_watched=1` would already silence it.
- **hooks-b-08:** test-pinned (NUDGE10) and added deliberately on 2026-09-28.

**headless**
- **headless-09:** dl-sweep runs 2.1.114, where unpinned effort is unmeasured; a medium pin might lower it.
- **headless-10:** a Workflow script has no shell; low value.

**session-cost**
- **session-cost-02:** breaks mailbox-wake-arm and cc-wait.
- **session-cost-05:** the thresholds are hook-enforced, 15% fails on small windows, and the keepalive was dropped on 2026-09-24.
- **session-cost-06:** the full-session resume is deliberate (the summary path drops `/goal`), and the ceiling is inflated.
- **session-cost-07:** conflicts with the slot table and the grounding floor.

**hillclimb**
- **hillclimb-10:** wrong item set; refile as in §3.
- **hillclimb-11:** pushes research slots to low on a saturated eval.
- **hillclimb-12:** the mining step selects gold with the incumbent weights, and measured yield was 11 of 6,008 prompts.

Merged rather than rejected: commands-01, -02 and headless-04 into hillclimb-01..03; session-cost-01 into slim-09; session-cost-03 into skills-b-11.

## 5. Sources delta (the three 2026 pages vs the bundled guides)

Pages read: the claude.com blog post on reducing cost, the platform docs page on optimizing for cost and intelligence, and the cost-optimization cookbook. Numbers were checked against the raw page source. The cookbook's final cell is Sonnet medium with an explicit system breakpoint at $0.0223 a task, 10/10, a 13× cut from the $0.2906 Opus-high baseline. The WebFetch summary had this wrong.

**New and used**
- **Cache health benchmark:** median 84% of input read from cache, top 10% at 94% or more; below about 80%, look for a cache breaker.
- **1-hour TTL rule:** use it when more than about 1 gap in 20 falls between 5 and 60 minutes. This agrees with the existing 1h-main / 5m-agent split.
- **Cache-breaking timing:** make cache-breaking changes one request after compaction ($0.75 vs $0.95). Changing the output format also breaks the cache.
- **Forks** need the parent's effort to share its cache.
- **Tool search** at 502 tools stayed flat; deferring an MCP toolset cut 20%.
- **Context management by run length:** context editing cost +74% on a short run; pruning saved 39% and compaction 32% on a long one. Pruning invalidates preserved thinking.
- **Prompt-audit effects per pattern:** removing "verify twice" cut cost by a third; each stale setting removed restored 7-11 points. In the blog's case, migrating Opus 4.8 → 5.5 saved 18%, and the audit saved another 9%.
- **Answer format:** a one-line answer cost $0.49 vs $1.40 for a memo, at equal accuracy.
- **Elapsed-time clock** (new): cost -28 to -54% for -0.2 to -1.9 points. Here it could be a cache-safe end-of-conversation hook, but that form is untested and would need a gated A/B. It would address the lesson "Turn adjacency ≠ elapsed time".

**Stale in the guides**
- Caching saves 2.7-5.3×, not 2.5-3.7×.
- Opus 5.5's default effort is medium.
- Re-running only failed tasks gives about 97% for $0.17, against 95.3% for $0.29.
- Task budgets save 44% and 58%.
- An orchestrator loses 10-12 points, not 3-7.
- The guide says each effort step buys about 2.4 points; the docs now report Fable 5.1 flat from low to high on DeepResearch Bench II. This strengthens open decision P3 (Fable at low effort).
- The cookbook itself is stale on Opus pricing ($4/$20 now) and on "default effort is high".

**Not applicable here:** keep-alive requests, Batch, task budgets, stop sequences, token counting, spend limits, and advisor mode (2.1× cost).

**Unverified:** Claude Code support for task budgets; whether per-turn effort preserves the cache (model-config records that /effort did on Opus 5.5); screenshot pixel sizes.

## 6. Coverage and assumptions

**Shards and files covered (202 total):**
- slim 2, project-rules 3, agents 5, commands 25, skills-a 19, skills-b 25, skills-c 19
- hooks-a 25, hooks-b 26 (the 52 hook files that emit model-facing text)
- headless 17, session-cost 11, hillclimb 25
- handoff.md, limit-recover.md and compact-memory.md got signal greps and targeted reads only.

**Not covered:** hook files without model-facing output; docs/templates/desk-boot-brief.md; the pyramid-principle skill body (another repo; it has two direct fixes: drop its gpt-5 CONFIG block and add the "apply, never name, the framework" rule); settings.json (not read); vendored codex-security; side requests that do not appear in transcripts.

**Verification of the apply set:**
- Exactly-once match plus sequential apply on a scratch copy, and `bash -n` / py_compile.
- Rendered recipe and instruction-budget measurements.
- The listing-budget check logic, run directly.
- Bats suites were not run here because cc-bats deferred at the load ceiling. Re-run at land: skill-listing-budget, wrap-ledger, validate-plan-structure, research-router, agents-omit-claudemd, research-zero-allowed-prompts, the email suites and capacity-admit-coverage.

**Mirrors:** CLAUDE.global.md (the full variant, not loaded) carries optional mirrors for the slim hunks. ~/.claude converges via install.sh, never by hand edit.

**Operator follow-ups outside the repo:**
- The personal project's memory still teaches "Message.body (not Comment)", the "≤300-char Comment" limit and "set from=<one fixed alias>".
- The local cafe-wifi description.

**Keep-list applied:** dated operator rulings, Why lines, measured incidents, hook-enforced rules, and pressure language guarding destructive, credential, money or live-session constraints. Most rejections come from it.