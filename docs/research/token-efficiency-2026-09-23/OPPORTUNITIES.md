# Opportunities: ranked, deduplicated (2026-09-09 → 2026-09-23 baseline)

Every candidate change from the eight `measure/` reports plus the `audit/` slim drafts, merged where two reports
proposed the same lever. Baseline and weights: `BASELINE.md`. Arithmetic: `scripts/synth_opportunities.py` →
`data/synth_opportunities.json` (overlaps, slim fractions, long-context tax), `scripts/synth_side_requests.py`.

**Units.** Savings are per window (14.96 d, "14 d" below), at list-price weights: **own** = each response at its own
model (fleet $32,517), **@5.5** = re-priced at Opus 5.5 (fleet $18,319, the forward-looking number since Opus 5.5
became the default on 2026-09-22). **Meter** = the part of the saving that is cache writes + output, the classes that
drive the plan meter (cache reads draw ≤¼ of list weight, plausibly 0: `USAGE_TELEMETRY_100P.md` §2.8). All savings
are ESTIMATED; the method column names how.

**Rank** = standalone saving (own) ÷ risk weight (low 1, low-med 1.5, med 2, high 4), per the spec's
share × removable ÷ risk. Overlapping items are ranked standalone; the **incremental** column and § Bundle remove
the overlap. **Category** follows the spec: DIRECT (telemetry, serialization, volatile content out of the prefix,
breakpoints, large outputs to files, reasoning passback, recurring tool-error fixes), FLAG (instruction edits,
tool offloading, output format, compaction, subagent prompting), PROPOSE (models, routing, effort, work split).

## 0. Do first: telemetry (DIRECT, $0 direct saving, prerequisite for every validation below)

| # | Change | Why |
|---|---|---|
| T1 | `bin/cc-quota-price`: price output from the **final** usage record (max over records per `message.id`), not the first | The census of record reads output **46% low** (first record carries a `message_start` placeholder; EXTRACT.md L1). Every per-task figure built on it undercounts the class that drives the meter |
| T2 | Make `scripts/census.py` + `scripts/synth_baseline.py` a standing per-task ledger: $ per session tree by billing type, at list and meter-proxy weights, per model and at Opus 5.5 | The spec's primary metric is cost per completed task; no standing instrument reports it today |
| T3 | Side-request accounting: per session, cost-state usage minus transcript usage, by model | ~$884 own / $452 @5.5 per window (2.7%) is invisible to every transcript-based figure (prompt suggestion, away summary, titles, goal evaluator, classifier) |
| T4 | Config guard (in `config-mirror-assert.sh` or `cc-upgrade-gate`): assert `ENABLE_PROMPT_CACHING_1H` unset and main threads on 1h | Keeps the verified TTL split (rank note N1): main at 5m would add **+$2,841 @5.5**, agents at 1h **+$1,226 @5.5** |

## 1. Ranked list

| Rank | Change | Layer | Cat. | Saving own $/14d (% fleet) | @5.5 $ (%) | Meter $ own | Incremental after higher ranks (own / @5.5) | Quality risk | Score |
|---:|---|---|---|---:|---:|---:|---|---|---:|
| 1 | **Lean agent type for Workflow and research agents**: a custom agent with `omitClaudeMd: true` and an explicit `tools:` list without `Skill` or MCP, passed as `agentType` in workflow scripts and used for deep-research; the rules those agents need go in the brief (2-5k tokens) | agent config + workflow scripts | FLAG | **4,169 (12.8%)** | **2,390 (13.0%)** | ~1,550 | – | med | 2,085 |
| 2 | **Cache breakpoint after the setup attachments**, setup ahead of the per-agent brief, so sibling agents read the ~95k setup instead of re-writing it | CC binary (request assembly) | DIRECT class; blocked upstream → PROPOSE + flagged workaround | 890-1,210 (2.7-3.7%) | 750-1,011 (4.1-5.5%) | ~1,000-1,300 (all write) | ~150-200 / ~130-170 (lean agents leave ~17% of the setup) | low | 1,050 |
| 3 | **Slim the global CLAUDE.md** (audit C1-C5 drafts: 105,272 → 50,560 chars, −52%) | user memory | FLAG | 2,036 (6.3%) | 1,143 (6.2%) | 660 | 1,029 / 565 (main contexts only) | med | 1,018 |
| 4 | **Slim the claude-infrastructure rules file** to 16 resident bullets + `docs/lessons/INDEX.md` (audit C7: 74,780 → 7,567 chars, −90%) | project memory | FLAG | 1,639 (5.0%) | 899 (4.9%) | 525 | 909 / 484 | med | 820 |
| 5 | **Prompt suggestion off** (drop `CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION=true`, which overrides a server gate that defaults off); away summary likewise where recaps go unread | settings env (side requests) | DIRECT (config; the agent's context is unchanged) — confirm: the operator set it on deliberately | ≤745 **outside** the $32.5k (≤2.3%) | ≤318 (≤1.7%) | ≈0 (fork cache reads) | – | low (UX only) | 745 |
| 6 | **Idle keepalive for main threads**: re-touch the 1h cache every 55 min while idle, cap H=4h (H=24h turns negative) | harness / binary idle behaviour | PROPOSE | net ≥549 (1.7%) | net ≥575 (3.1%) | ~1,200 (pings are reads) | includes rank 8 | low | 549 |
| 7 | **Skill listing fits its budget**: every own skill/command description ≤250 chars (20 drafted in `listings.json`, ~38 to go), `skillOverrides: name-only` for the 8 bundled skills with 0 uses, tighter descriptions for 3 custom agents | skill/agent frontmatter, settings | FLAG | 442 (1.4%) | 229 (1.3%) | 142 | ~226 / ~117 (agents lose the listing in rank 1) | low (all 75 skills become described instead of 44) | 442 |
| 8 | **`cc-await-ping` term ≤3,300 s**: `--idle-scoped` default 3600 → 3300 (`bin/cc-await-ping:195`, env `CC_AWAIT_IDLE_TIMEOUT_S` already exists) and the stand-down hint's `--timeout 14400` → a 55-min re-arm (`:365`) | our script | DIRECT | 345 (1.1%) | 261 (1.4%) | ~345 | subset of rank 6 | low | 345 |
| 9 | **Remove the global rules essay** `~/.claude/rules/agent-operating-lessons.md` from context (a correction log, no operative rule; audit C6) and relocate it verbatim to `docs/lessons/` | user memory | FLAG (toggle = `mv`) | 339 (1.0%) | 184 (1.0%) | 108 | 161 / 84 | low | 339 |
| 10 | **Slim the claude-infrastructure project `.claude/CLAUDE.md`** (audit C6: 6,289 → 3,036 chars) | project memory | FLAG | 304 (0.9%) | 159 (0.9%) | 97 | 254 / 131 | low | 304 |
| 11 | **Mission board compact render** (`CC_MISSION_COMPACT`, built and bats-verified in audit C6: 5.5k → ~0.97k tokens) and move it out of memory position 1 (rename so it sorts after stable files, or deliver it as main-only SessionStart context) | user memory / cache layout | FLAG (render) + DIRECT (reorder) | 253 (0.8%) | 145 (0.8%) | 81 | 121 / 67; also fewer mid-session re-injections (part of the $183 re-attach row) | low | 253 |
| 12 | **Large non-read Bash output to a file** (path + size + head/tail) above ~8k chars, via a wrapper or an upstream option; deliberate file reads stay inline | Bash tool results (vendor) | DIRECT class; no mechanism to rewrite Bash output was found by these reports → PROPOSE | gross ≤453 (1.4%) | ≤243 (1.3%) | ~160 | overlaps rank 16 | med | 226 |
| 13 | **/goal empty-turn notice**: after ≥3 consecutive goal-forced turns that wrote nothing, one operator notice recommending `/goal clear` (18 contexts made 510 empty turns); also caps the Haiku evaluator's sliding-window rewrites on long sessions | built-in goal hook + `goal-inert-watch.sh` | PROPOSE | 207 (0.6%) | 89 (0.5%) | ~72 | – | low | 207 |
| 14 | **Hook text trims**: config-mirror FORKED list → count + path ($83, DIRECT), drop empty SessionStart one-liners ($7, DIRECT); wake-path nag only on change, skip nudges already in context, dod-persist only from the session's own lineage (also removes misdirection: 7 of 8 sampled sessions got an unrelated "CURRENT CONTRACT"), memory-nudge once per context, drop forwarded peer mail >24h old ($116, FLAG) | hooks | DIRECT + FLAG | 206 (0.6%) | 97 (0.5%) | 43 | – | low (quality ↑ for dod-persist) | 206 |
| 15 | **Agents background long commands**: never block a foreground call longer than ~4.5 min; poll with Monitor (until-loop) in ≤270 s slices, since the built-in guard refuses `sleep N; cmd` | workflow-authoring skill, agent briefs | FLAG | 298 (0.9%) | 214 (1.2%) | ~270 | – | low-med (+2,520 cheap polls replace 312 rewrites) | 199 |
| 16 | **`bashOutputMaxChars: 16000`** (default 30,000; clamp 4k-128k): output above the cap is persisted with a 2 KB preview, not truncated | CC settings | FLAG | gross ≤419, net ~172 (0.5-1.3%) | gross ≤227, net ~93 | ~60-150 | overlaps rank 12 | med (59% of the gross is deliberate reads that would be re-read) | 148 |
| 17 | **session-continue.sh re-block suppression**: no re-block when the armed step is a wait that already has a waker, and no identical re-block after a forced turn that wrote nothing | Stop hook | FLAG | 294 (0.9%) | 133 (0.7%) | ~103 | – | med (less autonomous driving if misclassified) | 147 |
| 18 | **Identify `total_tokens_reminder`** (165k per-turn attachments, ~35 tokens each) and disable it where optional | harness attachment | FLAG after identification | ≤263 (0.8%) | ≤138 (0.8%) | ≤84 | – | med (unknown purpose) | 131 |
| 19 | **Two instruction lines for recurring tool errors**: "The Bash tool refuses `sleep N` followed by another command; wait with Monitor (until-loop) or the completion notification" (337 blocks) and "Edit and Write accept only files opened with the Read tool in this context; a Bash cat/sed read does not count" (79 errors); plus drop the backgrounded `cc-await-ping` line from the CLAUDE.md recipe (41 denies), name StructuredOutput required fields in workflow prompts (78 misses), guard zsh aliases `g/t/gg/rd` when `CLAUDECODE` is set | CLAUDE.md, workflow skill, shell env | FLAG | 104-138 (0.3-0.4%) | 55-70 | ~50 | fold the two lines into the rank 3 slim | low | 121 |
| 20 | **WAKE FLOOR armed mechanically** (`mailbox-wake-arm.sh` asyncRewake) instead of blocking the model to arm it (342 of 381 such forced turns were waste-likely) | Stop hook | FLAG | 100 (0.3%) | 45 (0.2%) | ~35 | – | low | 100 |
| 21 | **Scope ms365 out of the user MCP config** (used in 3.0% of main sessions; ~2.7k tokens of names + instructions in every context) | MCP config | FLAG (tool offloading); needs an operator ruling: conflicts with the email-images rule | ~200 (0.6%) | ~100 (0.5%) | ~64 | ~100 / ~50 (agent part gone in rank 1) | med | 100 |
| 22 | **Report the Stop-reason double send upstream** (every command-hook Stop reason is sent as a meta message and as a `hook_blocking_error`: 2,588/2,588) | CC binary | PROPOSE (upstream) | 92 (0.3%) | 41 | ~30 | overlaps rank 26 | low | 92 |
| 23 | **Narrow allow rules** for recurring safe shapes denied in agents that cannot answer an ask (scratchpad writes, `/tmp` probe cleanup, `cd <worktree> && …`), and for recurring classifier denials | permissions (operator-owned) | PROPOSE | 66-104 (0.2-0.3%) | 35-55 | ~35 | – | low | 85 |
| 24 | **Recurring tool-error fixes in our code**: `validate-bash.sh` matches on commands with heredoc bodies and quoted literals stripped (keep a raw match for `sh -c`/`bash -c`/`eval`; tie the `git add -f` rule to a `git … add` clause; 56 of 81 checked denies are false positives); `agent-teams-enforce.sh` capacity-admit waits in a bounded queue or says when capacity returns (114 refusals, up to 12 retries); rename `report-<agent>.md` in `skills/research-subagents/SKILL.md:237` (the 2.1.280 built-in blocks `^(REPORT\|SUMMARY\|FINDINGS\|ANALYSIS).*\.md` subagent writes, and the findings then return inline); `curl-gate.py` falls back to a token scan on a shlex failure | hooks, skills | DIRECT | 72-87 (0.2-0.3%) | ~40 | ~32 | – | low | 80 |
| 25 | **Disable the unused claude.ai Claude Docs connector** (0 calls; 629 always-loaded tool tokens + 1,895-char instructions in 50-90% of new contexts since 2026-09-16) | account connectors | FLAG | 69 (0.2%) | 36 | ~22 | – | low | 69 |
| 26 | **Stop reasons ≤200 chars** (verdict + next step + file pointer) | Stop hooks | FLAG | 113 (0.3%) | 51 | ~40 | – | med (reasons carry the close contract) | 57 |

**Model, routing and effort (PROPOSE; sensitivities, not point estimates: no slot-level quality data exists)**

| # | Change | Estimate | Risk |
|---|---|---|---|
| P1 | A cheaper worker model (Sonnet 5, $2/$10) for mechanical Workflow slots (extraction, formatting, re-verification) | each 10% of workflow-agent spend moved from Opus 5.5 → **$319 @5.5** (1.7%); measure the whole tree, since cheaper workers can raise planner and retry spend | med-high |
| P2 | Lower effort on mechanical Workflow slots only (never the main thread: fewer output tokens can mean less thinking and worse results) | each 10% less thinking in workflow agents (generated ~$968 + retained $584 own) → **$155 own / ~$95 @5.5** | med |
| P3 | Confine Fable 5.1 to ladder stage 2 (operator decision R3 is open) | Fable is 8.1% of own $ ($2,642); the same tokens at Opus 5.5 cost $1,200. On the meter Fable draws 3.2-3.7× per token | high (Fable's value is the frontier delta) |

**Session lifecycle (PROPOSE; not recommended without a quality study)**

| # | Change | Estimate | Why not recommended |
|---|---|---|---|
| L1 | Recycle or `/clear` instead of resuming a main thread after >1h idle | ≤$1.4k own / ≤$1.1k @5.5 (517 wakes × (390k − 124k) × 2x) | 174 of 517 wakes are operator prompts that continue the work ("Good to close?", "Did you ping the lead?"); the context is the asset. Ranks 6 and 8 capture most of the value without losing it |
| L2 | Recycle long autonomous threads at a fill threshold | net upper bound after the recycle's own 124k START: 300k → $2,210 own / $711 @5.5; 400k → $1,127 / $382 (`long_context_tax_main`) | The gain is almost all cache reads, so on the meter it is **negative** (each recycle adds a START write: $532-665 at 300k). Also loses judgment a successor cannot re-derive |

**Verified keep-as-is and null results**

| # | Item | Finding |
|---|---|---|
| N1 | TTL split | Keep 1h on main, 5m on agents. Main at 5m: +$3,547 own / +$2,841 @5.5; agents at 1h: +$1,633 / +$1,226. Never set `ENABLE_PROMPT_CACHING_1H` (it forces 1h on every agent). The verdict holds under the meter too: both sides are writes |
| N2 | Retained thinking ($2,548 re-read, 7.8%) | Keep: reasoning continuity, a spec trap; deltas prove it is passed back intact |
| N3 | Sparse Read line numbers | $27 / $15 (0.08%): Read is 5% of growth; files are read through Bash `sed`/`cat` |
| N4 | ANSI stripping, JSON minify, grouped grep output, repo-relative paths in our CLIs | $1 / ≤$12 / ≤$21 / ~$5: format overhead in tool results totals $192 (0.6%) |
| N5 | Shorter subagent returns | Returns are 0.3% of spend; the 46%-of-a-window case in `context-ceiling-397428c4` is one outlier session |
| N6 | Hook text as a cross-session cache blocker | Not the blocker: no breakpoint follows the setup at all (rank 2) |

## 2. Detail per item: method, validation, rollback, interactions

| Rank | Method (ESTIMATED unless stated) | How to validate | Roll back | Interactions |
|---:|---|---|---|---|
| 1 | Static-prefix cost rows restricted to agent contexts: 80% of agent memory-file $ ($3,348 / $1,917) + agent skill listing ($605 / $348) + agent deferred names ($151 / $89) + workflow MCP instructions (3.3/4.3 of $86). Measured basis: one subagent prefix 42,275 → 1,795 tokens with `omitClaudeMd` (`binary-and-cache.md` exp. b) | A/B the same workflow scripts with `agentType: lean` vs default, alternating runs: $ per run (both weightings), turns per agent, StructuredOutput first-try validity (4.2% error today), the script's own verifier pass rate, hook-deny rate on git/safety rules, commits by agents that later fail a gate | Remove `agentType` from the scripts; delete the agent file | Removes most of what rank 2 would share; shrinks the agent part of ranks 3, 4, 7, 9-11, 21. Agents may spend turns rediscovering rules they lost (watch turns per agent). Restating the needed rules in the brief is the mitigation |
| 2 | 2,075 of 2,400 workflow STARTs had a same-session same-model sibling START in the prior 5 min; setup is 92% of their first message; 2,199 of 2,396 agents carry setup byte-identical to their run's majority. (1.25 − read mult) × input price × setup tokens | Workaround experiment first: `claudeMdExcludes` + `--append-system-prompt-file` for mains, `CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1` + `--append-subagent-system-prompt-file` for agents (untested), then first-request `cache_read` share of siblings (13.2% today) | Unset the env var / flags | Needs the mission board moved out of position 1 (rank 11) for any cross-session reach. Overlaps rank 1 |
| 3 | Row $ × 0.52 cut (sizes MEASURED from the audit drafts). Main-only figure = the main-context part of the row | Point one account's `CLAUDE.md` symlink at the slim file; compare accounts over the same window: $ per task, turns per task, close-contract compliance (`completion-assert` verdicts), hook-deny rates, operator re-asks ("Good to close?"). Resolve the major findings in `audit/C1-C5.verify.md` first (email images R51, R5 agent-spawn carve-out, F18 migration owner, R53 90% boundary, rule 26 imperative) | Re-point the symlink | Also shrinks memory re-attachments and every side-request fork. Carry rank 19's two lines into it |
| 4 | Row $ × 0.90 (resident text only; INDEX.md stays on disk) | `claudeMdExcludes` per account to switch full vs slim copy (untested; audit F5: a per-account symlink cannot reach a tracked project file), or a time-window A/B. Fix audit C7 F1-F4 first (hook messages that still route rules into the file, 47 memory topics orphaned under `/compact-memory`, pointer triggers, the kitty title ruling must stay resident) | `git revert` | The memory rotor keeps appending here (`cc-memory-rotate`); without F1/F6 fixed the file regrows |
| 5 | Cost-state minus transcript cache reads on Opus 5 over 812 sessions (1.21B tokens, $650), scaled by 40.95/35.73 to the fleet. Upper bound: includes away summaries, compaction forks and `/btw` | Switch off on one account; compare that account's cost-state-minus-transcript reads before and after | Restore the env line | Removes the ghost-text suggestion in the TUI. Prompt-suggestion forks also refresh the TTL (19 main hits after >1h gaps are probably these), so a few more idle rewrites may appear |
| 6 | 517 main rewrites after >1h: avoided 2x rewrites for gaps 1h-H minus ping reads in gaps and idle tails (tail cost is an upper bound). Own-model net scales rewrites by 1.376 and reads by 2.5 | Replay on the next window with the ping log; count long-gap rewrites | Stop the keepalive | Pure reads on the meter, so its meter value (~$1.2k own) exceeds its list value. Needs a no-op request mechanism in the binary; user-space via watcher wakes gives ≥$328 @5.5 |
| 7 | `listings.md` scenarios S2 + S3 + agent descriptions, scaled ×1.115 from chars/3 to the measured 2.69 chars/token | Re-run `listings_skill_render.py` / `listings_usage.py`: every skill described, Skill-call rate per main session ≥17.4% (guardrail) | `git revert` the frontmatter | Headroom after S1 alone is only 879 chars; S2 leaves 9.4k. Quoted trigger phrases appear in 9 of 169 prompts, so dropping them costs little |
| 8 | 116 watcher wakes (102 are exit-2 timeouts) re-priced as 474 hit-wakes at two prefix reads each | Count long-gap rewrites whose wake is `cc-await-ping` (116 today) | `CC_AWAIT_IDLE_TIMEOUT_S=3600` | More wakes (4×), each a cheap hit |
| 9-11 | Row $ × cut fraction (essay 100%; project CLAUDE.md 52%; board 82% from a `/context` measurement) | `mv` toggle (essay); flag file / `CC_MISSION_COMPACT` (board, byte-identical when off, 9 bats cases); symlink or window A/B (project CLAUDE.md) | Reverse `mv`; unset flag; revert | The board compact render also stops most mid-session re-injections (546 in 14 d) |
| 12 | `of_threshold_sim.py` at an 8k cap on the non-read subset: Σ (chars − 2,260) × persistence weight | Behind a flag; watch follow-up reads of the persisted file within 3 turns and turns per task | Remove the wrapper | More turns when the agent needs the tail; fewer tokens per request |
| 13-14, 17, 20, 26 | `hooks_cuts.py`: measured waste-likely forced-turn $ or injection $ × the removable share per rule | Per hook: forced turns per context, repeat share, SessionStart chars; guardrails: sessions idling with 🔧 work left, missed peer mail (`cc-notify reason=`), `completion-assert` and `wrap-ledger` verdicts | Env flag per hook; `git revert` for the DIRECT rows | Fewer forced turns = fewer responses per task. $2.5k of forced turns lead to real work: do not trim those |
| 15 | 312 agent rewrites after 5-60 min foreground calls → 2,520 polls | Count agent rewrites with a 5-60 min gap (300 in workflow agents today) | Revert the skill text | Must use Monitor, not `sleep; cat` (rank 19). More turns, each a cheap hit |
| 16 | `of_threshold_sim.py` at 16k over all Bash results; net assumes the deliberate-read share is re-read in full | Per-account A/B: $ per task, turns, `persisted` rate, follow-up `sed`/Read within 3 turns | Remove the key | Output is persisted, not truncated (spec trap avoided). Interacts with rank 12 |
| 18 | Growth-report source total | First identify the trigger in the binary | – | – |
| 19, 24 | `tool-errors.md` pattern $ (incl. recovery turns) × removable fraction (0.5-0.9 by mechanism) | Error rate per pattern per 14 d; bats suites for `validate-bash.sh` | Revert the line / hook | Each line costs ~40 resident tokens (~$3 per 14 d); net figures already include it |
| 21, 25 | Listing-cost share (names + instructions) × presence | ms365 call success and `cc-mail-images` use; Docs: none | Restore the MCP entry / toggle | ms365 names already sit in agents; rank 1 removes those |
| 22-23 | Pattern $ × removable fraction | Upstream fix / deny counts per rule | – | Authorization stays operator-owned |

## 3. Bundle: what the non-overlapping set adds up to

| Bundle | Items | own $/14d (% of $32,517) | @5.5 $ (% of $18,319) | Meter proxy $ own (% of $13,512) |
|---|---|---:|---:|---:|
| A. Context the harness sends (FLAG) | 1, 3-4, 7, 9-11 (incremental after 1), 19 | ~6,990 (21.5%) | ~3,900 (21.3%) | ~2,500 (18.5%) |
| B. Cache and idle (DIRECT + FLAG) | 8, 15, 2 (incremental); 6 adds ~$200-250 own if built | ~820-1,070 (2.5-3.3%) | ~625-940 | ~790 (~1,650 with 6: its pings are reads) |
| C. Hooks (DIRECT + FLAG + PROPOSE) | 13-14, 17, 20, 26 (22 overlaps 26) | ~920 (2.8%) | ~414 (2.3%) | ~290 |
| D. Tool output (FLAG) | 16 (net) | ~172 (0.5%) | ~93 | ~60 |
| E. Tool errors (DIRECT) | 24 | ~80 (0.2%) | ~40 | ~32 |
| F. Listings and connectors (FLAG) | 21 (after 1), 25 | ~169 (0.5%) | ~86 | ~54 |
| **Total** | | **~9,150-9,400 (28-29%)** | **~5,160-5,470 (28-30%)** | **~3,730-4,590 (28-34%)** |
| Side requests (outside the fleet total) | 5 | +≤745 | +≤318 | ≈0 |

- **Read this as an upper-leaning estimate.** Rank 1's 80% removal and the slims' cut fractions assume the verify
  findings are fixed without adding text back. A realized 60-80% of the estimate is a reasonable planning range:
  **~17-23% of list-weighted spend**. The spec's reference team cut 7% from a leaner starting point; this harness
  carries ~200k chars of memory into every context, which is why the lever is larger here.
- **Per task.** A median task (one main context, 42 responses) gains mostly from ranks 3, 4, 9-11: in
  claude-infrastructure the main-thread static prefix drops by ~54k tokens (~47% of it, ~16% of a mean request).
  The top 10% of tasks (67% of $) are worker-heavy; rank 1 dominates there.
- **Order of work.** Section 0 (telemetry), then the DIRECT items (8, 11-reorder, 14-DIRECT rows, 24), then FLAG
  items one A/B at a time in rank order (1 before 3-4, because 1 changes their incremental value), then PROPOSE items
  as written proposals.

## 4. Interactions (fewer tokens per request vs more turns)

| Change | Tokens per request | Turns | Net direction |
|---|---|---|---|
| Rank 1 lean agents | −~80k per agent request | may rise if agents rediscover lost rules | Saves ~80k × (1.25 + 0.1 × 22.6) ≈ 281k input-price tokens per 23.6-response workflow agent; an extra turn costs ~20k (a ~110k re-read, a small write, ~1k output). Break-even ≈ 14 extra turns, i.e. turns per agent up ~60% (ESTIMATED) |
| Ranks 3-4, 9-11 slims | −21k to −54k per main request | may rise if a moved rule is looked up on demand (INDEX grep) | Saving; watch operator re-asks and close-contract failures |
| Rank 8 watcher term | none | +358 wakes | Saving: a hit-wake costs ~2 prefix reads vs a 2x rewrite |
| Rank 15 agent polls | none | +2,208 polls | Saving: 312 rewrites avoided |
| Ranks 12, 16 output to file | −up to 28k chars per large result | + follow-up reads when the tail matters | Net unknown: A/B |
| Ranks 13, 17, 20 forced-turn cuts | none | −up to 1,973 waste-likely turns | Saving; risk is work left undone → more operator prompts |
| Rank 6 keepalive | none | + pings (≤$263 @5.5 of reads) | Saving; larger on the meter |
| P2 lower effort | − thinking generated and re-read | may rise (more errors / retries) | Unknown: slot-level A/B only |
| L2 recycle at threshold | −reads above threshold | + recycles, briefs, re-derivation | Negative on the meter |

## 5. Traps checked

| Spec trap | Status in this list |
|---|---|
| Asking the model to use fewer tokens | None of the items does. Rank 19 describes tool behaviour; rank 15 describes how to wait |
| Truncating tool output | Ranks 12 and 16 persist full output to a file with a preview; nothing is dropped |
| Dropping reasoning items | Rejected (N2) |
| Volatile content in the cached prefix | Mission board at memory position 1 (rank 11). SessionStart context is 88.6% volatile but main-only and per-session |
| Offloading a tool the model needs on turn 1 | ms365 (rank 21) is used in 3% of sessions; Skill stays in main contexts (17.4% use) |
| Emphasis-heavy prompts | The audit slims strip caps and 🚨; the two added lines are plain descriptions |
| Optimizing per request instead of per task | § 4 and the per-task ledger (T2) |
| Switching models mid-conversation | Not proposed; P1-P3 are per slot / per launch. 45 in-place model switches cost $136 in rewrites this window |
