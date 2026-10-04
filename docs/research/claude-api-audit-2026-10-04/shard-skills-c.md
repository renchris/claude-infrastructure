# Prompt audit, shard skills-c

## Assumptions
- Scope: skills/ entries 26-37: outbound-drafting, permission-harvest, plan-conventions, plan-update, read-twitter, research-program (SKILL.md, RUBRIC.md, checklist.jsonl, briefs/*.md), research-subagents, resume-sessions (SKILL.md, REFERENCE.md), self-explaining-artifact, test-audit (SKILL.md; LICENSE-OpenClaw not prompt text), video-understanding, visual-direction. 19 prompt files. One companion hunk outside the shard (hooks/validate-plan-structure.sh:125) because it injects the same contradicting rule as plan-conventions.
- Target model: Claude Opus 5.5 (claude-opus-5-5), the default for sessions that load these skills; Haiku 4.5 where research-subagents pins the retrieval slot.
- Read-only: nothing in the repo was edited. Settings files were not read.
- Repo keep-list applied: dated operator rulings, Why lines, measured incident evidence and hook-enforced rules were not flagged as cruft. Pressure language guarding sends, credentials and permissions was kept.

## Summary
The three findings with the most impact:
1. **The vision budget is stale.** video-understanding builds its whole sampling plan on a ~1568px resample; Opus 5.5 is in the 2576px tier and Claude Code clamps at 2000px. The repo's own research (A9-capture-fidelity.md:55) already says so. read-twitter repeats the wrong reason.
2. **The Phase 4 keepalive is killed by our own reaper.** reso-keepalive is a bash script that is not on cc-reaper's GARBAGE_WL; cc-reaper.log shows it TERMed 4 times (most recently 2026-10-02). This is a code defect behind the prompt text: the resume runbook's success criterion fails silently.
3. **research-subagents and plan-conventions contradict newer rules.** They say depth-2 fan-out is preferred (global: depth is 1 on purpose), Haiku retrieval workers get 350K-1M of context (Haiku 4.5 has 200K), Agent Teams are the default (same file, global and hook: dispatched session S is the default), and teammates should /compact at 75% (global: teammates do not survive /compact).

Counts: Group 1: 0 standalone (1b/1d/1f folded into Group 2 rows where they overlap). Group 2: 30 (12 contradiction, 12 volatile or stale fact, 6 history or time-sensitive). Group 3: not applicable (no tool descriptions in shard). Group 4: not applicable (no request-building code), except one cost-lever note (skills-c-13). 3 findings are operator decisions because the newer rule loosens a prohibition or a consent gate.

## Findings (highest confidence first)

### skills-c-01 · skills/video-understanding/SKILL.md:25 · high · string-replace

- **Pattern:** Group 2 volatile specifics (claim the repository contradicts); 1d visual-input fossil
- **Why:** The skill's core budget rule says every image is resampled to ~1568px. That was the standard-tier limit of Opus 4.6 and earlier. Opus 4.7 and later, Opus 5.5 included, are in the 2576px high-resolution tier (model-migration.md: 'High-resolution vision ... 2576 pixels on the long edge (up from 1568px on Opus 4.6 and prior)'). The repo's own measured research already corrects this exact line: docs/research/cv-design-review-2026-08-26/agents/A9-capture-fidelity.md:55 says 'agent-video-understanding-2026-07-26.md:64 states ... 1568px ... is now the wrong tier', and Claude Code's 2000px client clamp binds first, so the effective ceiling is 2000px. Every tile-width figure in the table is about 22% too small, so the skill steers toward more columns and more image reads than needed. The legibility labels are left alone: more pixels per tile only make them more conservative.
- **Impact:** Correct sampling budget on every video task: per-tile width rises 28% (392->500px at 4 columns), so fewer image reads are needed for the same legibility; no token cost added


```diff
- ## The binding constraint: ~1568px
- 
- Any image you read is resampled to roughly **1568px on its long edge**. For an
- N-column contact sheet each tile arrives at about `1568 / N` px wide:
- 
- | Columns | Tile width | Legible |
- | --- | --- | --- |
- | 1 | 1568px | Everything — 12px UI text, source code |
- | 2 | 784px | Headings, most body text |
- | 4 | 392px | Composition and large text only |
- | 6+ | ≤261px | Shot type and colour. Text is gone. |
- 
- Total visual information = `(image reads) × 1568²`. **You cannot have both full
+ ## The binding constraint: ~2000px
+ 
+ Claude Code downscales any image you Read to at most **2000px on its long edge**
+ before the model sees it (the model's own 2576px high-resolution limit never
+ binds first; `docs/research/cv-design-review-2026-08-26/agents/A9-capture-fidelity.md` §0).
+ For an N-column contact sheet each tile arrives at about `2000 / N` px wide:
+ 
+ | Columns | Tile width | Legible |
+ | --- | --- | --- |
+ | 1 | 2000px | Everything — 12px UI text, source code |
+ | 2 | 1000px | Headings, most body text |
+ | 4 | 500px | Composition and large text only |
+ | 6+ | ≤333px | Shot type and colour. Text is gone. |
+ 
+ Total visual information = `(image reads) × 2000²`. **You cannot have both full
```

### skills-c-03 · skills/research-subagents/SKILL.md:578 · high · string-replace

- **Pattern:** Group 2 volatile specifics (claim contradicted by a documented model fact); 1d model-version fossil
- **Why:** The retrieval-worker depth budget (350-500K modal, up to 1M) is impossible on the model the same file pins for retrieval: the slot table (line 449) and the Explore note (lines 611-614) route retrieval to claude-haiku-4-5, whose context window is 200K (models.md: 'Claude Haiku 4.5 | claude-haiku-4-5 | ... | 200K'). A lead following this text would brief a Haiku worker for 2.5-5x more context than it has. The budget was written when 'Explore Haiku' and 1M-window models were not distinguished.
- **Impact:** Prevents retrieval briefs that overflow a 200K Haiku window (failed or truncated workers, then re-spawns); correct sizing per slot


```diff
- - **Retrieval workers** (pure lookup + extraction, no inferential synthesis —
-   Explore Haiku, or rare retrieval-only Sonnet slot): **350-500K modal, up
-   to 1M for genuinely retrieval-only briefs**, with explicit caveat on
-   lost-in-middle (TACL 2024: 40-60% middle adherence even on retrieval).
-   Above 500K expect ~15-25% degradation on multi-needle retrieval per MRCR v2.
+ - **Retrieval workers** (pure lookup + extraction, no inferential synthesis):
+   on the pinned retrieval model (`roles.research_retrieval`, `claude-haiku-4-5`)
+   the whole context window is **200K**, so budget **≤150K** and split a larger
+   source set across more workers. A retrieval-only brief that genuinely needs
+   more goes to a 1M-window model (`roles.research_worker`) at **350-500K modal**,
+   with the lost-in-middle caveat (TACL 2024: 40-60% middle adherence even on
+   retrieval); above 500K expect ~15-25% degradation on multi-needle retrieval per MRCR v2.
```

### skills-c-05 · skills/research-subagents/SKILL.md:960 · high · string-replace

- **Pattern:** Group 2 instruction files that contradict each other; 1d migration-relative phrasing
- **Why:** The Recursion Regression section tells the lead that depth-2 fan-out works on 2.1.183 and to 'prefer it over re-spawn-from-lead when sub-axes emerge'. The global instructions (CLAUDE.global.slim.md:109, CLAUDE.global.md:296; newer, added from 2026-07-24 on) say nesting is off on purpose: CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1, 'Keep it: since 2.1.224 removed the per-session spawn cap, depth is the only runaway bound.' A worker told to spawn mid-tier leaves will hit the depth cap. The section also still calls 2.1.114 'the stable track', which model-config.yaml:767-770 now calls the held legacy path.
- **Impact:** Removes an instruction that contradicts the enforced depth cap and the global rule; avoids failed nested spawns


```diff
- > Recursion status (May 2026 — SUPERSEDED on CC 2.1.183; see Update below): depth-2 fan-out NOT operational in stock Claude Code. The `Agent` tool is not exposed to subagents regardless of frontmatter declaration (GH #46424 primary blocker; also #4182, #19077, #31977, #30703). Default to depth-1 flat fan-out and re-spawn from lead context when sub-axes emerge. Workarounds + re-evaluation trigger: `~/.claude/memory/research-subagents-recursion-regression.md`.
- >
- > **Update 2026-06-19 — RESOLVED on CC 2.1.183 (claude-next), empirically verified.** A controlled headless probe against the 2.1.183 binary (`--safe-mode --permission-mode auto`, Opus parent) returned `{"fanout4_completed": true, "depth2_DEPTH2OK": true}`: a worker subagent spawned its own leaf sub-subagent via the `Agent` tool and relayed the result up (depth-2 works → #46424 cleared), and four parallel workers under an Opus parent all completed with no session termination (→ GH #61258 does not reproduce on 2.1.183). So on the **2.1.183 runtime** hierarchical fan-out (lead → mid-tier synthesizers → leaf workers — the § Synthesis Bottleneck N>50 pattern) is available; prefer it over re-spawn-from-lead when sub-axes emerge. **Scope:** verified depth-2 (the operationally relevant tier; the 2.1.172 changelog claims up to 5, untested past 2). The **stable track (2.1.114, reached as `claude-previous` since the 2026-07-31 entrypoint consolidation renamed it off `claude`) keeps the old non-recursive behavior** — hold depth-1 discipline there. Probe provenance: claude-next 2.1.170→2.1.183 upgrade session, 2026-06-19.
+ > **Depth is 1 on purpose.** `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1` (global CLAUDE.md § Research subagents) stops any subagent from spawning its own; since 2.1.224 removed the per-session spawn cap it is the only runaway bound, so keep it. Fan out flat from the lead and re-spawn emerging sub-axes from the lead. The § Synthesis Bottleneck mid-tier synthesizers are lead-spawned workers that read leaf artifacts from disk, not parents of leaves. History (the GH #46424 blocker, the 2026-06-19 depth-2 probe on 2.1.183): `~/.claude/memory/research-subagents-recursion-regression.md`.
```

### skills-c-07 · skills/research-subagents/SKILL.md:843 · high · string-replace

- **Pattern:** Group 2 instruction files that contradict each other (same file)
- **Why:** Line 843 says the abort manifest 'names projected $$'. Lines 480-486 of the same file, explicitly decided later (item-3 probe wf_b0f4b091-172, 2026-07-01), say 'Do NOT put a projected quota/$ number in the 15-second abort manifest ... any figure is un-anchored false precision'. The model is told both.
- **Impact:** One rule for the manifest instead of two opposite ones


```diff
- The 15-second abort window lets the human decide on cost (manifest names projected $$ + wall-clock band), not on plan quality.
+ The 15-second abort window lets the human decide on scale (the manifest names N, tiers and a wall-clock band, never a projected quota or $ figure; § Quota-Aware Wave Sizing), not on plan quality.
```

### skills-c-15 · skills/plan-conventions/SKILL.md:34 · high · string-replace

- **Pattern:** Group 2 instruction files that contradict each other (same file, and against the global rules and the hook injection)
- **Why:** Lines 36-39 (text from 2026-06-06) say 'Agent Teams are the DEFAULT for all implementation work ... MUST use Agent Teams ... The user expects 9/10 implementation sessions to use Agent Teams.' The same file at line 82 (2026-08-07) says 'the DEFAULT is a dispatched SESSION, not a teammate' and T needs a justification. The global rules (CLAUDE.global.slim.md: 'An implementation wave or phase runs by default as a dispatched session') and the PLAN_RULES text that hooks/backup-before-write.sh:244 injects on every plan edit ('S = dispatched handoff session (the DEFAULT ...) | T = in-session teammates ... justify') agree with line 82. The older lines are the outlier.
- **Impact:** One locus default on every plan edit; stops plans from defaulting to teammates that spend the lead's context


```diff
- **Phase 0 Rule (MANDATORY — Agent Teams Default)**
- 
- **Agent Teams are the DEFAULT for all implementation work.** Any plan with 2+ tasks that
- write or modify code MUST use Agent Teams and include Phase 0 as the FIRST section.
- Only use background subagents for research/exploration (no code changes) or 50+ parallel
- read-only tasks. The user expects 9/10 implementation sessions to use Agent Teams.
+ **Phase 0 Rule (MANDATORY)**
+ 
+ Any plan with 2+ tasks that write or modify code includes Phase 0 as the FIRST section. Its
+ default unit of execution is a dispatched session (locus S, below); in-session Agent Teams (T)
+ and lead-inline work (L) each need a one-line reason. Background subagents do read-only
+ research and exploration only; they never write code.
```

### skills-c-18 · skills/plan-update/SKILL.md:368 · high · string-replace

- **Pattern:** Group 2 instruction files that contradict each other
- **Why:** The intervention table tells the lead to send a teammate 'Pause, I'll /compact, then resume' at 75% context. The global rules state 'Teammates do not survive /compact (GH #49593)', and skills/agent-teams/SKILL.md:274-277 treats a /compact crash as a recovery case. The 2026-07-03 row predates that rule and prescribes the failure.
- **Impact:** Removes a step that crashes teammates; the scaffold is copied into every Phase 0


```diff
- | Context at 75%+ | Send "Pause, I'll /compact, then resume" | During wave |
- | Context at 90%+ | Shutdown + respawn | During wave |
+ | Context at 75%+ | Have it commit, then shutdown + respawn on its branch (teammates do not survive `/compact`, GH #49593) | During wave |
```

### skills-c-22 · skills/resume-sessions/SKILL.md:108 · high · string-replace

- **Pattern:** Group 2 volatile specifics (claim contradicted by the repository)
- **Why:** Says the fable accounts keep a resumed session 'on claude-fable-5'. bin/reso-resume-one:402-405 pins every fable arm to claude-fable-5-1 (model-config.yaml:762 frontier_access.model: claude-fable-5-1). A reader checking whether a resume kept its model would compare against the wrong id.
- **Impact:** Correct model id for verifying a Fable resume


```diff
- to keep it on `claude-fable-5` — and
+ to keep it on `claude-fable-5-1` — and
```

### skills-c-23 · skills/resume-sessions/SKILL.md:9 · high · string-replace

- **Pattern:** Group 2 volatile specifics (claim contradicted by the repository)
- **Why:** 'its two neighbours are still untracked' is stale: reso-keepalive is tracked at bin/reso-keepalive with tests/reso-keepalive.bats (its header: tracked 2026-08-09), ~/.reso/bin/reso-keepalive is a symlink into the checkout, and reso-quota is a compat shim onto claude-accounts (the skill says so itself at line 287).
- **Impact:** Removes a false provenance claim at the top of the runbook


```diff
- The tools live in `~/.reso/bin/` (`reso-resume-one`, `reso-keepalive`, `reso-quota`) — `reso-resume-one`
- is a symlink to the tracked, gated, tested `bin/reso-resume-one` in claude-infrastructure; its two
- neighbours are still untracked, which is the state that let this one rot. Deep rationale,
+ The tools live in `~/.reso/bin/` (`reso-resume-one`, `reso-keepalive`, `reso-quota`). The first two
+ are symlinks to the tracked, gated, tested `bin/` copies in claude-infrastructure; `reso-quota` is a
+ compat shim onto `claude-accounts`. Deep rationale,
```

### skills-c-24 · skills/resume-sessions/SKILL.md:244 · high · needs-new-code

- **Pattern:** Group 2 volatile specifics; repo lesson docs/lessons/detached-bash-is-reaped-after-ten-minutes.md (measured defect, not prompt text alone)
- **Why:** The Phase 4 keepalive does not survive. reso-keepalive is a bash script; bin/cc-reaper's orphan-bash sweep TERMs any launchd-parented bash older than 600 s whose argv misses GARBAGE_WL (bin/cc-reaper:713), and reso-keepalive is not on that list. ~/.claude/logs/cc-reaper.log shows it killed 4 times, most recently '[2026-10-02T08:29:15Z] garbage: TERM orphan-bash pid=79678 age=1042s argv=<bash /Users/chrisren/.reso/bin/reso-keepalive 240>'. The `nohup … & disown` form the skill hands over is also the one scripts/lib/detach.sh:4-11 documents as dying with the tool call's process group. scripts/boot-resume.sh:674 launches the same daemon through detach and is reaped the same way. So the skill's success criterion ('keepalive covering it') silently fails after ~10-15 minutes.
- **Impact:** Phase 4 keepalive stays alive instead of being TERMed within ~10-15 min; interrupted sessions keep being re-nudged as designed

- **Plan:** 1) Add `reso-keepalive` to GARBAGE_WL in bin/cc-reaper:713 as a house daemon (lesson option 3), with a fixture pair in tests/cc-reaper.bats like the public-publish one (bin/cc-reaper:710-712). 2) Apply this hunk so the hand-launched form uses detach.sh, which survives the tool call's group kill. 3) Verify: launch, wait more than 600 s plus one reaper sweep (300 s), confirm the pid is alive and no new TERM line for reso-keepalive in ~/.claude/logs/cc-reaper.log.


```diff
- CC_KEEPALIVE_MARKERS="wt-a wt-b" nohup ~/.reso/bin/reso-keepalive 240 >>~/.reso/keepalive.out 2>&1 & disown
+ . ~/.claude/scripts/lib/detach.sh && detach ~/.reso/keepalive.out env CC_KEEPALIVE_MARKERS="wt-a wt-b" ~/.reso/bin/reso-keepalive 240
```

### skills-c-25 · skills/resume-sessions/REFERENCE.md:216 · high · string-replace

- **Pattern:** Group 2 volatile specifics (claim contradicted by the repository); time-sensitive content
- **Why:** Tells the reader that Fable (claude-fable-5) has a plan-inclusion end date and to 'drive Fable usage hard before it (credits-only after = unaffordable)'. model-config.yaml:771-787 records the opposite: 'PERMANENT plan inclusion ... No longer credits-only after a window', permanent: true, end: '2099-12-31' as a sentinel ('read permanent: true first'), model claude-fable-5-1. The stale text urges a burn-before-deadline policy for a deadline that no longer exists.
- **Impact:** Removes a stale urgency rule that could misdirect weekly-Fable spend


```diff
- - **Fable** (`claude-fable-5`) plan-inclusion end = **SSOT `frontier_access.end` in
-   `~/.claude/model-config.yaml`** (was 2026-07-07, operator-extended to 2026-07-14 on Jul-9 —
-   the reason no date is ever hardcoded again) → drive Fable usage hard before it
-   (credits-only after = unaffordable). Fable = a ~50% sub-cap of the shared weekly.
+ - **Fable** (`frontier_access.model`, currently `claude-fable-5-1`) is a permanent plan inclusion
+   (`frontier_access.permanent: true` since 2026-07-20; `end` is a far-future sentinel) at a ~50%
+   sub-cap of the shared weekly. Read the model and any window from the SSOT
+   `~/.claude/model-config.yaml`, never a remembered date.
```

### skills-c-27 · skills/outbound-drafting/SKILL.md:212 · high · operator-decision

- **Pattern:** Group 2 instruction files that contradict each other (newer rule loosens a prohibition, so flagged)
- **Why:** The skill says all five ms365 send tools, send-draft-message included, are 'denied by a PreToolUse hook, absolutely, with no override' (2026-08-31). The hook itself records a later operator ruling (hooks/enforce-email-formatting.py:147-151, 2026-09-08: 'block sending emails from being written, but we should be able to send it from drafts'): send-draft-message is gated by R1b (refused in any turn that composed or revised the draft), not denied outright. The resident global rules already state the R1b form. The skill's description of the mechanism is wrong; its behavior (draft, then stop) is unchanged by the fix. Flagged because the accurate text describes a looser gate.
- **Impact:** Skill matches the enforcing hook and the global rule; no change to the draft-then-stop behavior

- **Plan:** Operator confirms the 2026-09-08 ruling is the intended steady state, then apply. If the ruling was reverted, the hook needs changing instead.


```diff
- > 🔒 **For EMAIL this is now MECHANICAL, not a matter of discipline (2026-08-25).** The ms365 send
- > tools — `send-mail`, `reply-mail-message`, `reply-all-mail-message`, `forward-mail-message`,
- > `send-draft-message` — are **denied by a PreToolUse hook**, absolutely, with **no override**.
- > Compose with `create-draft-email` / `create-reply-draft` / `create-reply-all-draft` /
- > `create-forward-draft`, then tell him the draft is in Drafts and ready.
+ > 🔒 **For EMAIL this is MECHANICAL, not a matter of discipline.** `send-mail`,
+ > `reply-mail-message`, `reply-all-mail-message` and `forward-mail-message` are **denied by a
+ > PreToolUse hook** with **no override**; `send-draft-message` is refused in any turn that composed
+ > or revised the draft (R1b, operator ruling 2026-09-08). Compose with `create-draft-email` /
+ > `create-reply-draft` / `create-reply-all-draft` / `create-forward-draft`, then tell him the draft
+ > is in Drafts and ready, and stop.
```

### skills-c-29 · skills/permission-harvest/SKILL.md:138 · high · operator-decision

- **Pattern:** Group 2 instruction files that contradict each other (consent/safety rule, so flagged)
- **Why:** The skill hands the operator `▶ Run this: cc-do <id>` and says cc-do 'takes the operator's typed yes'. The global Manual-Command rule says the operator runs handed commands through `!`, 'which has no keyboard, so a prompt-only gate reads EOF', and that consent rides in the handed line. bin/cc-do:51-58 confirms it: with stdin not a TTY and no CC_DO_ASSUME_YES=1, cc-do prints the board, says NOTHING RAN, and exits 3. So the handed command fails under `!` every time. The obvious fix (`CC_DO_ASSUME_YES=1 cc-do <id>`) moves consent into the handed line for a permission-widening step, which the global rule also restricts ('A file you hand over contains no permission grants'). That is the operator's call.
- **Impact:** The weekly apply step stops failing silently when run through `!`

- **Plan:** Operator decides whether the permission-apply step may carry consent in the handed line (CC_DO_ASSUME_YES=1) or must be run from a real terminal. In the latter case, keep `cc-do <id>` and add one line above the marker: 'run in a terminal tab, not through !'.


```diff
- ▶ Run this:
- 
- `cc-do <id>`
+ ▶ Run this:
+ 
+ `CC_DO_ASSUME_YES=1 cc-do <id>`
```

### skills-c-30 · hooks/validate-plan-structure.sh:125 · high · string-replace

- **Pattern:** Group 2 instruction files that contradict each other (companion hunk to skills-c-15: hook-injected text)
- **Why:** The PostToolUse hook injects, into every implementation plan saved without Phase 0, 'Per CLAUDE.md: Agent Teams are the DEFAULT for all implementation work (9/10 sessions)' and in the same sentence 'S = dispatched handoff session — the DEFAULT'. Two defaults in one injected message. It quotes CLAUDE.md for a rule the current global files no longer contain (they make S the default). Per the guide, a removal is complete only when every copy goes, so this hunk ships with skills-c-15.
- **Impact:** The hook stops injecting a contradicting default into plan sessions


```diff
- Per CLAUDE.md: Agent Teams are the DEFAULT for all implementation work (9/10 sessions). Add Phase 0
+ Per CLAUDE.md: an implementation plan with 2+ code tasks needs Phase 0. Add Phase 0
```

### skills-c-02 · skills/read-twitter/SKILL.md:53 · medium · string-replace

- **Pattern:** Group 2 volatile specifics (stated reason contradicted by the repository)
- **Why:** The measured part (orig cost ~41% more tokens with no readable gain on the test chart, per commit b2708804d) stands. The stated reason, that the vision pipeline downscales to ~1568px, is the same stale standard-tier figure the repo's own research corrects (A9-capture-fidelity.md:55): Claude Code clamps at 2000px and Opus 5.5 accepts 2576px. With the wrong reason, a reader thinks orig can never help, but the skill's own escape hatch two bullets down (CC_RT_IMG_SIZE=orig for dense screenshots) only makes sense because orig can deliver up to 2000px against medium's 1200px.
- **Impact:** Stops the skill from contradicting its own escape hatch; keeps the measured medium default


```diff
- - **Size is already right — do not "optimise" it.** The tool fetches
-   `?name=medium` (1200 px). `orig` is ~41 % more tokens for zero readable gain,
-   because the vision pipeline downscales to ~1568 px regardless.
+ - **Size is already right — do not "optimise" it.** The tool fetches
+   `?name=medium` (1200 px). `orig` cost ~41 % more tokens and showed no readable
+   gain on the test chart; Claude Code clamps any image to 2000 px on its long
+   edge, so `orig` buys at most 1200 → 2000 px, which matters only for dense text.
```

### skills-c-04 · skills/research-subagents/SKILL.md:528 · medium · string-replace

- **Pattern:** Group 2 history narratives / pinned model names; 1d model-version fossil (text inlined verbatim into every brief)
- **Why:** The synthesis contract is pasted verbatim into every research brief (line 525-526), so it reaches every worker on every wave. Its first sentence tells the worker it has ~1M tokens of context, which is false for the Haiku 4.5 retrieval slice (200K), and its justification cites retired models (Opus 4.6, LongSWE-Bench on Claude 3.5 Sonnet) that the worker cannot act on. The numbers (150-250K target, 500K cap) stay; only the false window claim and the archaeology go. The evidence remains in § Per-Subagent Depth and the validation log.
- **Impact:** ~40 fewer tokens in every brief (N=10 per wave) and no false context-window claim to Haiku workers


```diff
- > "You have ~1M tokens of nominal context. Effective working ceiling is
- > ~400K before reasoning quality degrades (LongSWE-Bench, MRCR v2, Opus 4.6
- > self-degradation curve). Target 150-250K on exploration; hard cap 500K.
+ > "Target 150-250K tokens of exploration and stop well before 500K (before
+ > 150K on a 200K-window model such as Haiku): reasoning quality degrades long
+ > before the context window fills.
```

### skills-c-06 · skills/research-subagents/SKILL.md:617 · medium · string-replace

- **Pattern:** Group 2 instruction files that contradict each other (stale reason)
- **Why:** States that the Agent tool declaration is 'currently NOT honored by stock Claude Code', which the file's own § Recursion Regression update marks RESOLVED since 2.1.183. The behavior it predicts (flat) is still right, but for a different reason: the depth cap of 1 set on purpose (global CLAUDE.md § Research subagents). agents/deep-research.md still lists Agent in its tools, so the wrong reason invites a nested spawn attempt.
- **Impact:** Consistent reason for flat fan-out across the file


```diff
-   multi-axis depth research. ⚠️ See § Recursion Regression — the `Agent`
-   tool declaration is currently NOT honored by stock Claude Code; the
-   subagent runs as flat (non-recursive) deep research.
+   multi-axis depth research. It runs flat: subagent spawning is capped at
+   depth 1 on purpose (§ Recursion Regression), so it never fans out on its own.
```

### skills-c-08 · skills/research-subagents/SKILL.md:313 · medium · string-replace

- **Pattern:** Group 2 instruction files that contradict each other; 1b/1f numeric cap tuned on older models
- **Why:** The 150-400-token brief cap (justified by a 2023-era lost-in-middle study) cannot be met by a compliant brief: the same file makes the ~300-word synthesis contract mandatory 'inlined verbatim per brief' (line 525-526), and the newer 2026-09-22 note (lines 475-478) says the research agents run with omitClaudeMd: true, so 'a brief must carry every rule a worker needs'. The serial-position rule also says the stop-line MUST be the final line while field 7 (Delivery) is defined as the last field 'in this order'. Re-expressed so both hold.
- **Impact:** Removes an unsatisfiable cap that pushes leads to cut context from briefs; resolves the last-line ordering clash


```diff
- **Length**: 150-400 tokens (≈ 80-250 words). Briefs above 400 tokens suffer
- lost-in-middle exposure (TACL 2024 Liu et al. — middle-position instructions
- have 40-60% adherence vs 95% at primacy). Briefs below 150 tokens
- under-specify; subagent satisfices on the first axis it finds.
- 
- **Serial-position discipline** (arxiv 2406.15981): last-position instructions
- have 2-4× adherence vs middle. The stop-line ("if you reach saturation
- before 30 tool calls, return early; if you can predict the next call's
- result, stop") MUST be the brief's final line.
+ **Length**: keep fields 1-6 tight (roughly 80-250 words). The brief also
+ carries the verbatim synthesis contract (§ Cost Asymmetry) and every rule the
+ worker needs, because the research agents run with `omitClaudeMd: true`
+ (§ Quota-Aware Wave Sizing), so a complete brief runs past 400 tokens by
+ design. Spend extra length on context, never on restating the contract.
+ 
+ **Serial-position discipline** (arxiv 2406.15981): last-position instructions
+ have 2-4× adherence vs middle. End the brief with field 7's delivery path,
+ then the stop-line ("if you reach saturation before 30 tool calls, return
+ early; if you can predict the next call's result, stop") as the final line.
```

### skills-c-09 · skills/research-subagents/SKILL.md:704 · medium · string-replace

- **Pattern:** 1d patch accretion / migration-relative phrasing (superseded text kept with a 'reinterpret' instruction)
- **Why:** The re-spawn triggers still say 'Sonnet worker' and 're-spawn on Opus', and close with 'Pure Opus for a typical wave overpays ~47%'. The QUALITY-FIRST ROUTING OVERRIDE (lines 662-675) says the worker slot is roles.research_worker (Opus 5.5 per model-config.yaml:985), the escalation is the frontier, and the cost-win math is SUPERSEDED, then asks the reader to 'Reinterpret the section below'. Every load makes the model reconcile two routing rules; writing the current rule directly removes the maze.
- **Impact:** One routing rule instead of a superseded one plus a reinterpretation note


```diff
- **Failure-mode signal (automatic re-spawn triggers)** — two distinct signals
- trigger automatic re-routing:
- 
- 1. **Sonnet worker return <3K on non-trivial question** → lead inspects at
-    synthesis time; if not a satisficing-failure (worker did try) → re-spawn
-    on Opus OR re-decompose into smaller independent axes.
- 2. **Sonnet worker's predict-next-call falsifiability check fails on an
-    inferential gap** (worker explicitly flags: *"I couldn't determine X
-    without multi-hop inference Y"*) → **automatic re-spawn on Opus**, no
-    re-decomposition first. The inferential gap is itself the signal that the
-    sub-question required multi-hop reasoning Sonnet couldn't complete;
-    further decomposition doesn't help.
- 
- Pure Opus for a typical wave overpays ~47%; pure Sonnet underperforms on adversarial briefs; pure Explore misses synthesis. The mix wins on $/insight when ≥20% of sub-questions are pure retrieval — almost always true for codebase-adjacent research. Full V2 R3 routing rationale: `~/.claude/memory/research-subagents-validation-log.md § V2 R3`.
+ **Failure-mode signal (automatic re-spawn triggers)** — two distinct signals
+ trigger automatic re-routing:
+ 
+ 1. **Worker return <3K on a non-trivial question** → lead inspects at
+    synthesis time; if not a satisficing-failure (worker did try) → re-spawn
+    on the frontier (`versions.frontier_latest`) OR re-decompose into smaller
+    independent axes.
+ 2. **Worker's predict-next-call falsifiability check fails on an
+    inferential gap** (worker explicitly flags: *"I couldn't determine X
+    without multi-hop inference Y"*) → **automatic re-spawn on the frontier**,
+    no re-decomposition first. The gap itself shows the sub-question needs
+    multi-hop reasoning; further decomposition doesn't help.
+ 
+ Pure Explore misses synthesis, so keep the `roles.research_retrieval` slice to genuinely retrieval-only axes. The superseded Sonnet-era tier-mix rationale: `~/.claude/memory/research-subagents-validation-log.md § V2 R3`.
```

### skills-c-10 · skills/research-subagents/SKILL.md:691 · medium · string-replace

- **Pattern:** 1d patch accretion (superseded cost claim stated as current)
- **Why:** 'Cost win: ... mixed-tier ≈ $8.80 vs homogeneous Opus ≈ $16.50 — ~47% reduction at iso-performance' is the Sonnet-worker cost math the override at lines 662-675 marks SUPERSEDED for worker selection. Stated as a present-tense win, it argues against the routing the file now prescribes. The record stays in the validation log the override cites.
- **Impact:** Removes a present-tense argument for the retired Sonnet-worker mix


```diff
- **Cost win**: at N=15 typical wave, mixed-tier ≈ $8.80 vs homogeneous Opus
- ≈ $16.50 — ~47% reduction at iso-performance (Anthropic prod pattern; MALBO
- arxiv 2511.11788; X-MAS arxiv 2505.16997).
- 
+ (delete)
```

### skills-c-11 · skills/research-subagents/SKILL.md:424 · medium · string-replace

- **Pattern:** Group 2 history narratives; Group 2 contradiction inside the retired block
- **Why:** An 11-line retired recommendation (Sonnet 5 @max as the Workflow synthesis worker, certified against Opus 4.8) is kept in imperative form ('spawn ... as agent(brief, {model: 'claude-sonnet-5', effort: 'max'})', 'HARD requirements: effort MUST be max'). It also says 'In-process /research can't pin effort', which the newer 2026-09-22 measurement at lines 467-474 refutes ('In-process effort is pinnable per AGENT DEFINITION'). The record exists at ~/.claude/model-routing-freewin-probe.md; one line pointing there keeps the history without the retired imperative.
- **Impact:** ~250 fewer tokens per load; removes a retired spawn recipe and a refuted claim


```diff
- - *(Retired 2026-09-22.)* **Workflow bulk synthesis-worker free win (T2 effort grid, CERTIFIED 2026-07-01).** In a
-   Workflow, spawn breadth-first synthesis/inferential workers as
-   `agent(brief, {model: 'claude-sonnet-5', effort: 'max'})` — **NOT** Opus-4.8@max. Sonnet-5@max
-   ties Opus-4.8@max on quality across easy AND hard synthesis briefs (0 reliable Opus wins, blind
-   4-judge default-to-refute) at **~2-3× lighter quota-draw** — so it frees the scarce Opus headroom
-   for the decisive slots. HARD requirements: effort MUST be `max` (Sonnet@xhigh drops below the
-   floor — wrong-file citations on hard grounding), AND the brief MUST carry a saturation bound
-   (~15-25 tool calls; unbounded max-effort Sonnet overflowed context once). In-process `/research`
-   can't pin effort → those workers stay on `roles.research_worker` (the Workflow slot is
-   `roles.workflow_synthesis_worker`, both in `~/.claude/model-config.yaml`). The free win was
-   certified vs Opus 4.8 only; re-probed against Opus 5.5 on 2026-09-22, it lost on quality.
+ - *(Retired 2026-09-22.)* The 2026-07-01 Sonnet-5@max synthesis free win was certified
+   against Opus 4.8 only and lost on quality when re-probed against Opus 5.5. Its conditions
+   (effort `max`, a 15-25 tool-call saturation bound) and evidence: `~/.claude/model-routing-freewin-probe.md`.
```

### skills-c-12 · skills/research-subagents/SKILL.md:635 · medium · string-replace

- **Pattern:** Group 2 history narratives / pinned model names; Group 2 volatile specifics
- **Why:** This paragraph narrates its own past errors, then restates facts that have since gone stale again: 'eval-track teams', 'Agent TEAMS run on both tracks' (model-config.yaml:767-770: 'consolidation v2 deleted the claude-next launcher. There is ONE track now'), 'claude-fable-5 verified ... allowlisted' (frontier is claude-fable-5-1, model-config.yaml:762), and 'lead_default reverted to Opus 4.8' (lead_default is claude-opus-5-5, model-config.yaml:911). The rewrite keeps the current rules, the 2026-06-09 reason for keeping leads off Fable, and one line on why the text names keys rather than values.
- **Impact:** Removes four stale facts from a routing paragraph; ~150 fewer tokens


```diff
- 🚨 **This paragraph carried THREE dead conjuncts until 2026-09-04** — the same
- triple `436f3435` cut out of `commands/research.md`, and the reason this text
- now names KEYS instead of facts. It asserted (a) a usage window
- "2026-06-09 → 2026-06-23" that died two windows before it was read
- (`frontier_access.permanent: true` since 2026-07-20 — there is no window and no
- "after the window"), (b) "ONLY on the claude-next eval track", a track launcher
- consolidation v2 DELETED, so the routing condition was unsatisfiable by any
- session, and (c) a fallback and model id that had both since moved. A doc that
- restates a perishable fact has no path to learn the fact changed. The shipped
- enforcer `hooks/frontier-spawn-gate.sh` checks `active` + `end` and reads no
- track at all; `frontier_access.tracks` is a stale label with no code consumer.
- Agent-definition frontmatter stays `model: opus` so the definitions remain
- valid on both tracks — the override is always call-time. Agent TEAMS run on
- both tracks too; teammate models are gated by the auto-mode allowlist in
- the SSOT, not by the track — default `versions.opus_latest`; `claude-fable-5` verified
- in auto mode 2026-06-09 and allowlisted, so eval-track teams may pin
- `roles.teammate_frontier` per-member where judgment density warrants
- the 2× cost. **Lead/default sessions do NOT ride the frontier tier**
- (`lead_default` reverted to Opus 4.8 on 2026-06-09 — Fable-by-default burned
- 5-hour plan windows). Panel frontier work runs AGENT-INITIATED
- under the bounded-autonomy policy (global CLAUDE.md § Frontier Tier Routing +
- SSOT `frontier_discovery_budget`, hook-enforced cap): `/frontier-run` over the
- per-project `docs/research/FRONTIER_HOLES.md` ledger — blocking walls escalate
- inline, queued holes batch at wrap-up; capture via `/frontier-hole`. The
- `claude-fable` launcher is an optional human surface, not the pipeline. Panel workers use the `frontier-derivation` agent definition
- (baseline-blind; frontmatter `opus`, call-time `model: "fable"`).
+ This text names SSOT keys rather than values because restated values went stale
+ here three times (`436f3435`). The shipped enforcer `hooks/frontier-spawn-gate.sh`
+ checks `frontier_access.active` + `end`; agent-definition frontmatter stays
+ `model: opus`, and the frontier override is always call-time. Teams may pin
+ `roles.teammate_frontier` per member where judgment density warrants Fable's 2×
+ cost. **Lead/default sessions do NOT ride the frontier tier** (`roles.lead_default`
+ follows `versions.opus_latest`; Fable-by-default burned 5-hour plan windows on
+ 2026-06-09). Panel frontier work runs AGENT-INITIATED
+ under the bounded-autonomy policy (global CLAUDE.md § Frontier Tier Routing +
+ SSOT `frontier_discovery_budget`, hook-enforced cap): `/frontier-run` over the
+ per-project `docs/research/FRONTIER_HOLES.md` ledger — blocking walls escalate
+ inline, queued holes batch at wrap-up; capture via `/frontier-hole`. The
+ `claude-fable` launcher is an optional human surface, not the pipeline. Panel workers use the `frontier-derivation` agent definition
+ (baseline-blind; frontmatter `opus`, call-time `model: "fable"`).
```

### skills-c-13 · skills/research-subagents/SKILL.md:505 · medium · string-replace

- **Pattern:** Group 2 volatile specifics (stale pricing); cost-optimization 'price per completed task, re-measure per model'
- **Why:** The dollar table is priced at 'Opus 4.8 $5/$25' and 'Fable 5 ... $10/$50' with Batch columns. Opus 5.5 lists at $4/$20 with cache reads at 0.05x (models.md), Message Batches are not a surface Claude Code subagent spawns use, and the file itself says dollars are not this fleet's binding currency. cost-optimization.md: 'the per-task numbers ... were measured on Claude Opus 5, so re-measure on Claude Opus 5.5 rather than extrapolating.' The repo has the right instrument for the real currency (bin/cc-quota-price, census over transcripts). The '$100-150 per question' ceiling is a stopping rule in the wrong unit; OASIS is the stop rule.
- **Impact:** ~350 fewer tokens per load; replaces stale dollar math with the quota instrument the fleet actually budgets against


```diff
- **Calibrated cost (Opus 4.8 $5/$25 pricing, ~600K input per subagent at
- 80% input / 20% output split; Fable 5 slots — `claude-fable-5`, $10/$50 —
- cost 2× the corresponding row)**. Dollars are not this fleet's binding currency — weekly plan
- quota is (see CLAUDE.global.md § Frontier Tier Routing); read the table as a historical scale proxy:
- 
- | N subagents | No-cache | 70% cache hit | Batch | Cache + batch |
- |---|---|---|---|---|
- | 10 | $54 | $37 | $27 | $19 |
- | 20 | $108 | $74 | $54 | $37 |
- | 30 | $162 | $112 | $81 | $56 |
- 
- At pinned depth (~180K per subagent, not 600K), divide above by ~3 — a
- 20-subagent wave is ~$36 no-cache, ~$12 with cache+batch.
- 
- Marginal value approaches zero around **$100-150 per question** for typical
- complex research; $250 is the practical ceiling. The "rounding error vs
- engineer-hours" framing holds when research substitutes for >3 engineer-hours
- of investigation (≈ $500); breaks down for trivial questions (15-min
- investigations ≠ rounding error against $50 wave).
+ **Scale is quota, not dollars.** Weekly plan quota is this fleet's binding
+ currency (see CLAUDE.global.md § Frontier Tier Routing). A wave's draw scales with
+ N × per-worker depth (§ Per-Subagent Depth) × the slot's tier, and a Fable slot
+ draws roughly 2-5× an Opus slot. For a measured figure, run `cc-quota-price --census`
+ over the wave's transcripts; never extrapolate list prices. The OASIS stop (below),
+ not a spend ceiling, decides when a wave is wide enough.
```

### skills-c-14 · skills/research-subagents/SKILL.md:9 · medium · string-replace

- **Pattern:** Group 2 time-sensitive content (date claim contradicted by git history)
- **Why:** 'Last revised: 2026-05-24 — V2 validation' is false: git log shows the file revised through 2026-10-01 (7310c4ac8), including the Opus 5.5 slot table (2026-09-22) and workflow-lean (2026-09-24). A reader dating the file's guidance from this header would treat 2026-09 rules as May rules.
- **Impact:** Removes a misleading date stamp


```diff
- *Last revised: 2026-05-24 — V2 validation (Category C gate; depth caps split by task class; NF-1 diversity finding; R2/R3/E1 routing refinements). Forensic case studies, recursion-regression tracking, and validation evidence live in `~/.claude/memory/research-subagents-*.md` and are pointed-to where load-bearing.*
+ *Forensic case studies, recursion-regression tracking, and validation evidence live in `~/.claude/memory/research-subagents-*.md` and are pointed-to where load-bearing.*
```

### skills-c-16 · skills/plan-conventions/SKILL.md:90 · medium · string-replace

- **Pattern:** Group 2 instruction files that contradict each other (rule a hook enforces)
- **Why:** The S recipe tells the lead to arm cc-await-ping in the background unconditionally. The global rules say to omit it 'whenever a /goal is live in the firing pane (the usual case for a wave lead): a running background Bash makes Claude Code skip goal evaluation at every Stop. hooks/validate-bash.sh denies that park.' The guard (validate-bash.sh:195-215, widened 2026-08-11) postdates this table row (2026-08-07/10). Following the skill as written gets a hook denial in the usual case.
- **Impact:** Stops a recipe step that the hook denies for goal-armed leads


```diff
- lead arms `cc-await-ping` in background |
+ lead arms `cc-await-ping` in background only when no `/goal` is live in its pane (`hooks/validate-bash.sh` denies the park otherwise) |
```

### skills-c-17 · skills/plan-update/SKILL.md:298 · medium · string-replace

- **Pattern:** Group 2 instruction files that contradict each other (rule a hook enforces)
- **Why:** Same conflict as skills-c-16 in the Phase 0 scaffold that gets pasted into plans: 'lead arms cc-await-ping <lead-uuid> in the background' with no /goal condition, against the global rule and the validate-bash.sh LIVE-/goal guard.
- **Impact:** Plans scaffolded from this template stop prescribing a hook-denied step


```diff
- lead arms
- `cc-await-ping <lead-uuid>` in the background.
+ lead arms
+ `cc-await-ping <lead-uuid>` in the background only when no `/goal` is live in its pane
+ (`hooks/validate-bash.sh` denies the park otherwise).
```

### skills-c-19 · skills/plan-update/SKILL.md:382 · medium · string-replace

- **Pattern:** Group 2 instruction files that contradict each other; volatile specifics
- **Why:** plan-conventions/SKILL.md:111-113 names this exact budget as the defect it fixed: 'the only Context Budget section ... budgeted the teammate at 1M tokens with "Free buffer 500K+ · Unlikely to hit context limit"'. The scaffold still ships it. The global rules add that the window size 'cannot be imputed from the model id'. The per-wave rows stay; the false 1M total and the 'unlikely to hit context limit' reassurance go.
- **Impact:** Scaffolded plans stop asserting a context window and a buffer nobody measured


```diff
- **Per-agent**: 1M tokens total
- 
- | Phase | Budget | Notes |
- |-------|--------|-------|
- | Base (docs + code context) | ~50K | CLAUDE.md, schema, operationBuilder |
- | Wave 1 (schema edits) | ~100–150K | Grep + read scoped sections |
- | Wave 2 (mutations) | ~100–150K | Full file context, careful typing |
- | Wave 3 (UI + build output) | ~80–120K | Components + typecheck |
- | **Free buffer** | **500K+** | Unlikely to hit context limit |
+ **Per-agent** (size the work, not the window: plan-conventions § Task size, 40–150K output per unit):
+ 
+ | Phase | Budget | Notes |
+ |-------|--------|-------|
+ | Base (docs + code context) | ~50K | CLAUDE.md, schema, operationBuilder |
+ | Wave 1 (schema edits) | ~100–150K | Grep + read scoped sections |
+ | Wave 2 (mutations) | ~100–150K | Full file context, careful typing |
+ | Wave 3 (UI + build output) | ~80–120K | Components + typecheck |
```

### skills-c-20 · skills/plan-update/SKILL.md:180 · medium · operator-decision

- **Pattern:** Group 2 instruction files that contradict each other (newer rule loosens this prohibition, so flagged)
- **Why:** Step 6 says 'Do NOT commit to the cwd git repo — the user decides when' (2026-07-03). The global rules (CLAUDE.global.slim.md, restated 2026-09-23) say 'Commit as you go without being asked: one atomic commit for each completed logical task', and session-continue.sh blocks the stop while files the session wrote are uncommitted, so a plan-update run that obeys the skill trips the mechanical close gate. The /commit it suggests is disable-model-invocation. Because the newer rule removes a prohibition, the guide says flag rather than rewrite; the proposed text is offered for the operator.
- **Impact:** Ends a skill-vs-hook clash on every plan-update run in a repo

- **Plan:** Operator rules whether plan edits commit as-you-go (global rule + session-continue.sh) or wait for the user (this skill). If as-you-go, apply the replacement.


```diff
- Do NOT commit to the cwd git repo — the user decides when. Suggest: `/commit docs(plans): compact <plan-name>` when ready.
+ Commit the plan edit as its own atomic commit (`docs(plans): compact <plan-name>`), per the global Git rules. A plan outside any repo (`~/.claude/plans/`) is versioned by the plan-history hook instead.
```

### skills-c-21 · skills/plan-update/SKILL.md:426 · medium · string-replace

- **Pattern:** Group 2 duplicated info across files / history narrative / version pins
- **Why:** This block restates skills/agent-teams/SKILL.md § Runtime assumption (which it cites) and adds a history narrative pinned to versions ('it reports 2.1.219; before that it reported 2.1.114'). model-config.yaml:767-770 now records one track (`claude` → ~/.claude-260) with 2.1.114 as the held legacy path, and the global rules reference 2.1.260/2.1.280 sessions, so the copied numbers are stale and will drift again. The scaffold needs only the teardown step and a pointer.
- **Impact:** ~200 fewer tokens in a scaffold pasted into plans; one owner for runtime detection


```diff
- Tear down every teammate FIRST, then the worktrees/branches. The teardown call is
- **runtime-conditional** — see `skills/agent-teams/SKILL.md` § "Runtime assumption":
- 
- - **Stable (CC 2.1.114)** — the classic `TeamCreate`/`TeamDelete` tools exist: call `TeamDelete`.
- - **Eval track (CC 2.1.178+, implicit-team model)** — there is **no `TeamDelete` tool**. Send each
-   teammate a structured `shutdown_request` (`SendMessage`); plain-text broadcasts do NOT close panes
-   → orphaned panes + worktrees. Absence of `TeamDelete` means *use the implicit-team model*, never
-   "teams are unavailable".
- 
- Detect the running runtime by tool availability (or `CLAUDE_CODE_EXECPATH`), **not** by
- `claude --version` — `claude` is a shell function, so its version answers *which launcher the
- name currently points at*, never *which binary this session is running*. (Since the 2026-07-31
- entrypoint consolidation it reports 2.1.219; before that it reported 2.1.114 even inside an
- eval-track session. Both readings are wrong for the same reason, so the rule is unchanged —
- only the wrong number moved. `claude-previous --version` is the 2.1.114 stable launcher.)
+ Tear down every teammate FIRST, then the worktrees/branches: send each teammate a structured
+ `shutdown_request` (`SendMessage`); plain-text broadcasts do NOT close panes, which leaves orphaned
+ panes and worktrees. On the held legacy 2.1.114 runtime call `TeamDelete` instead. Detect which
+ runtime you are on per `skills/agent-teams/SKILL.md` § "Runtime assumption", never by `claude --version`.
```

### skills-c-26 · skills/resume-sessions/REFERENCE.md:178 · medium · string-replace

- **Pattern:** Group 2 volatile specifics / history narrative (self-contradicting summary of code)
- **Why:** The header says 'the Jul-7 constant is GONE ... KMAX raised 4→8 ... Historical algorithm below is otherwise accurate', but the formulas below still use H_jul7 = hours_to(2026-07-07), KF = clamp(1 − k/4, …) and hard-exclude at k ≥ 4. bin/claude-accounts:408-465 now carries tunable ROUTER_KEYS including KMAX and KMAX_RESIDENT, so the copy is wrong in its specifics and the code is the source. A pointer avoids a second copy that drifts.
- **Impact:** ~600 fewer tokens on a reference read during recovery; no stale router math


```diff
- > **2026-07-10 promotion deltas** (scoring math unchanged): the Jul-7 constant is GONE — the
- > Fable deadline reads live from `~/.claude/model-config.yaml frontier_access.{active,end}`
- > (the hardcode silently killed all Fable routing when the operator extended the window);
- > `k` now counts ALL live claude processes per CLAUDE_CONFIG_DIR (argv[0]=claude match), not
- > just `--resume` ones (2 vs 14 observed) — KMAX raised 4→8 in `~/.claude/accounts.json`;
- > missing scoped-Fable limit = no entitlement (never "100% headroom"). Historical algorithm
- > below is otherwise accurate.
- 
- Percents are 0..100 USED. Per account, from `.limits[]` + `.extra_usage`:
- 
- - **General** (Opus, draws weekly_all only): `score = RBR × SF × KF × CF`
-   - `RBR = w_rem / T_week`; `w_rem = max(0, wTgt − weekly%/100)`, `wTgt = 0.98 if credits else 1.00`;
-     `T_week = max(hours_to_weekly_reset − 0.5, 0.25)`.
-   - `SF = clamp((0.85 − sess%/100)/(0.85 − 0.50), 0.05, 1)` (5-hour safety).
-   - `KF = clamp(1 − k/4, 0.10, 1)` (concurrency spread; `k` = live sessions on the account).
-   - `CF = credits ? (weekly<0.90 ? 1 : 0.5) : 1` (deprioritize $ spend).
- - **Fable** (draws BOTH the Fable sub-cap AND weekly_all): `score = (f_eff/H)·JB × SF × KF × CF`
-   - **coupling fix**: `f_eff = min(0.5·(1 − fable%/100), w_rem)` — 0.5 = fable_cap/weekly_cap; the naive
-     `min(fable_rem, weekly_rem)` overstates fresh-account Fable headroom up to 2×.
-   - `H = max(min(T_fable, H_jul7), 0.25)`; `H_jul7 = max(hours_to(2026-07-07) − 2, 0)`;
-     `JB = 1.25 if T_fable > H_jul7 else 1` (single-tranche accounts whose weekly resets AFTER Jul-7).
- - **Hard-exclude** an account if: `sess% ≥ 85` (5h cutoff; waive if 5h resets <0.25h) · `k ≥ 4`
-   (rate-limit spread) · general `w_rem ≤ 0.005` · fable `f_eff ≤ 0.02` · fable & `H_jul7 ≤ 0`
-   (window closed → no plan-feasible Fable; never auto-spend credits).
- - **concurrency `k`**: count `claude … --resume <sid>` processes per `CLAUDE_CONFIG_DIR`, **deduped by
-   `<sid>`** (expect wrapper + claude.exe are 2 processes / 1 session on different ptys — dedup by tty
-   FAILS; dedup by the --resume session-id).
+ The live scoring, its constants (`ROUTER_KEYS`: `KMAX`, `KMAX_RESIDENT`, `S_CUT`, …) and their
+ validation are in `bin/claude-accounts` (search `ROUTER_KEYS`); read the code, not a copy. What
+ holds across versions: percents are 0..100 USED; general work draws weekly_all only; Fable draws
+ BOTH the Fable sub-cap and weekly_all, so Fable headroom is `min(0.5·(1 − fable%/100), weekly
+ remaining)`, never `min(fable_rem, weekly_rem)`, which overstates a fresh account up to 2×;
+ concurrency `k` is deduped by session id, not by tty (an expect wrapper and claude.exe are two
+ processes for one session); credits are never auto-spent.
```

### skills-c-28 · skills/permission-harvest/SKILL.md:197 · medium · string-replace

- **Pattern:** Group 2 recency trap / time-sensitive content
- **Why:** '🚨 Every file in this loop is NEW, so nothing is live until scripts/deploy-live.sh converges' was true at the 2026-09-09 land (63734f039). The files have been live since (~/.claude/bin/cc-permission-harvest is a symlink into the checkout, dated Sep 10), so the alarm now describes a state that ended. The general rule it carries (an added file is not live until the converger runs: the LIVE_ADDS rung) is kept in calm form.
- **Impact:** Removes a stale alarm from a weekly-loaded skill


```diff
- 🚨 **Every file in this loop is NEW**, so nothing is live until `scripts/deploy-live.sh` converges —
- an added file has no symlink, is absent from the live tree, and every consumer guard on it is a
- SILENT skip. That is the `LIVE_ADDS` rung: a land that adds files is not live until the converger
- has run.
+ A file newly added to this loop has no symlink, is absent from the live tree, and every consumer
+ guard on it is a silent skip until `scripts/deploy-live.sh` converges (the `LIVE_ADDS` rung).
```


## Flag-only (low confidence, not in the diff)
- research-subagents:496-503: "Anthropic dropped prompt-cache default TTL from 1h → 5min around Mar 2026" and "4-7× cost inflation". The API default has always been 5 min (prompt-caching.md); what Claude Code does on Max plans is not documented here. The ~4.2% sibling hit rate matches prompt-caching.md § Concurrent-request timing (parallel siblings cannot read each other's writes). Possible lever: fire one worker first and the rest once it streams, so N-1 siblings read the shared system+tools prefix. Needs measurement with cc-quota-price --census before it is worth a rule.
- research-subagents:401-402: "Opus draws [quota] down ~5× faster than Sonnet/Haiku". Opus 5.5 lists at 2× Sonnet 5.5 and 4× Haiku 4.5 per token; quota draw is not list price. Re-measure.
- research-subagents:564-570, 878-893: depth and lead-budget figures rest on Claude 3.5 Sonnet / Opus 4.6 measurements and a "1M nominal, ~400K usable" lead window. The file itself says the floor was not re-measured on Opus 5.5 (lines 407-408). Re-measure before changing numbers.
- research-subagents:12-14, 966-972: "agent-teams.md" now lives at skills/agent-teams/SKILL.md.
- plan-update:516-526: "Trigger Phrases" list in the body. Routing reads only the frontmatter description, so the list does nothing once loaded.
- resume-sessions SKILL.md:283, 296-298: "Fable window ... frontier_access.end". `end` is now a far-future sentinel (model-config.yaml:781-783); companion to skills-c-25.
- resume-sessions SKILL.md:237 and Phase 3: "Because the Stop-hook is gone". Since 2026-08-10 the resume takes the full session, so this is true only for sessions already compacted (REFERENCE.md §5 says so). The wording could mislead.
- outbound-drafting:43: `./bin/wa` is a relative path that does not resolve in this repo (it lives with `msg` in ~/Development/personal). Outside the project, so not probed.
- bin/cc-read-twitter:31 carries the same stale 1568px comment as skills-c-02 (a code comment, not prompt text).
- research-program/briefs/reviewer.md:12: "You are not graded on count". Grader vocabulary (1c), but the brief is frozen and hash-recorded on certificates (RUBRIC.md:3-5, SKILL.md:149-150). Editing it is a method change, so it is left alone.

## Checked and clean
- research-program: frozen briefs, rubric and protocol are modern (zero is a valid answer, no quotas, JSON contracts, signatures gated by cc-signoff). Every named script and test exists.
- test-audit, self-explaining-artifact, visual-direction: no dated patterns. visual-direction's named-template list is the form prompt-audit 1e says to keep on Opus 5.5.
- outbound-drafting rules 1-7 and §8: the 🚨 markers guard irreversible third-party sends, each with a measured incident. Kept.
- permission-harvest §3 gates, §6 NEVER list: hard permission and safety constraints with reasons. Kept.
- Every repo path named in the shard was checked and exists, except ./bin/wa (outside the repo).
- Out-of-band dependencies: tests/research-zero-allowed-prompts.bats asserts on research-subagents text the hunks do not touch; no test asserts the replaced strings.
