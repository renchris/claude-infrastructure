# CC 2.1.280 -> 2.1.284: adversary sweep (2026-09-28)

Role: adversary. The default is to flag risk. Scope: CHANGELOG `/tmp/s55/cl.md` lines 3-471 (2.1.281-2.1.284), read in full. Also covered: the GitHub tracker (via `gh`) and this fleet's config.
Every number below says whether it was **measured** (with the command) or **estimated** (with the method).

## Verdict

**YELLOW: do not advance today. Advancing is technically feasible but premature.** Nothing in the changelog is a hard BLOCKER for this fleet. Three things argue against moving the launcher today:

1. **Age.** 2.1.284 was about 1.8 h old at audit. Measured: `npm view @anthropic-ai/claude-code time` gives 17:11:59Z; `date -u` gives 19:00Z. The skill's bar is at least 7 d since publish. Sonnet 5.5 cannot be reached any other way: the 2.1.280 binary contains 0 `claude-sonnet-5-5` strings and 2.1.284 contains 24 (measured, `grep -a -o | wc -l` on both `claude.exe`). This is the same binary-gate shape as Opus 5.5 on 2.1.280.
2. **A live auto-mode classifier incident today, which the upgrade widens.** The fleet is already hit on 2.1.280. Measured: `grep -o 'gave no verdict'` over transcripts newer than 2026-09-27 finds 103 hits in 10 files on the secondary, tertiary and quaternary accounts, every one stamped `"version":"2.1.280"`, from 00:56Z to 18:57Z. One of those files is a workflow agent in this very run. 2.1.281 L428 makes read-only and sandboxed shell commands also wait for the server-side review, so on 284 even `git status` and `grep` stop when the classifier gives no verdict. The tracker has at least 13 open "no verdict" issues filed 2026-09-28 (#97870, #97884, #97854, #97812, #97766 and others) on 2.1.282 and 2.1.283. A gate run today would flake on probe #03 (auto-mode tool turn) for reasons that have nothing to do with the binary.
3. **No held-open issue is discharged** (table below). The changelog band is silent on every spawn cap and depth limit.

## Held-open issues (measured: `gh issue view N -R anthropics/claude-code --json state,stateReason,closedAt,updatedAt`)

| Issue | State | Verdict |
|---|---|---|
| #84974 SPAWN_DEPTH=1 off-by-one | OPEN, `stale` label, updated 09-21, last repro 2.1.234 | **still open**. The 284 binary still reads the variable: 5 occurrences, same as 280 (measured). The changelog has no depth or cap entry for 281-284. |
| #85264 fork subagents nest | OPEN, no assignee | **still open** |
| #85015 bg subagent 46 GiB | OPEN. Corroborated 09-14 ("crashing multiple times a day … even with two agents") | **still open**. Also a new Desktop sibling: #97862, bg processes pushing macOS to about 45 GB swap. |
| #84224 auto-updater prefix | OPEN, `reproduced` | **still open**. Our launcher's `DISABLE_AUTOUPDATER=1` is still what protects us. |
| #85154 stub without bin | CLOSED 09-09, **NOT_PLANNED (stale bot)** | **not fixed**, only closed as stale. Do not count it as discharged. |
| #85886 daemon inbox socket | CLOSED COMPLETED, fixed in 2.1.228 | discharged (it already was) |
| #85497 socket never bound | OPEN, `stale` | **still open** |
| #85412 same-second bind race | CLOSED 09-08, **NOT_PLANNED (stale)** | **not fixed**. The *race* leg is undischarged. |
| #85690 self-delivery | CLOSED 09-10, **NOT_PLANNED (stale)** | **not fixed** |
| #85764 ListAgents omits in-process | OPEN, `stale` | **still open** |

## Changelog ratings for this fleet

### CAUTION

- **284 L5: `sonnet` alias is now Sonnet 5.5.** `agents/deep-research-sonnet.md` and `agents/research-decomposition-critic.md` both say `model: sonnet` with no `effort:`. `skills/frontier-campaign/SKILL.md:29` also spawns with `model: sonnet`. All three silently move to Sonnet 5.5 on upgrade (measured by grep of the frontmatter). The SSOT still says `sonnet_latest: claude-sonnet-5` (`model-config.yaml:127`), so after the upgrade the SSOT and the runtime disagree. Two related open issues:
  - #97829 (283): frontmatter `effort` is ignored on the `--agent` path.
  - #93646 (open): the `sonnet` alias resolves inconsistently across providers.
  Pin by id, or flip the SSOT in the same diff.
- **284 L67: Ultracode is now its own toggle and "no longer forces xhigh".** Up to 2.1.283 the `ultracode` keyword pinned xhigh (#97442, open). On 284, ultracode leads run at the launcher's `--effort high`. That is a silent step down for every `/handoff` ultracode payload (`commands/handoff.md:200,409`). It is still unverified whether the payload *keyword* triggers ultracode at all on 284: the changelog names only Tab and `/effort ultracode`. **This needs a live probe before the upgrade.**
- **281 L428-429 and 282 L262: the server-side classifier covers more.** Read-only and sandboxed commands now wait for its verdict. See Verdict item 2. #97911 (open) adds that unattended `--bg` sessions hang for hours on an auto-mode ask with no timeout.
- **284 L68: retries after a dropped connection now share one budget.** A failing request gives up sooner. During today's overload and no-verdict bursts, unattended waves will fail faster instead of riding the problem out (estimated from the changelog wording).
- **283 L170: interactive sessions on third-party providers now start in auto mode.** `bin/claude-kimi` is designed *not* to force auto (its lines 34-36: "metered $ + un-burned-in agentic behaviour"). Its live settings at `~/.config/claude-kimi/settings.json` have **no `permissions.defaultMode`** (measured, python json read). On 283 and later it therefore flips silently to auto. Fix by adding `"defaultMode": "default"`. The launcher is dormant unless a key is configured.
- **284 L62: auto-memory now neutralizes markup-like tags.** 7 of 502 memory notes quote CC markup literally (measured, grep for `<task-notification>`, `<system-reminder>` and similar). One is `bare-json-key-is-unforgeable-by-content.md`, which teaches an exact forgery-detection literal. If the recalled text is neutralized, a model may rebuild a detector that no longer matches. Read one neutralized recall before trusting those notes.
- **281 L327 and L430: `rm -rf "$(…)"` now asks even with an allow rule, then denies after 2 minutes.** Agents that type `rm -rf "$(git rev-parse --git-common-dir)/ship-land-memo"` inline, as the idiom appears in our bats files, will stall for 2 minutes and then be denied. The repo lesson "a subagent cannot answer a prompt" applies: ban this form by name in briefs.
- **281 L331 plus open #97888 (283).** `claude --bg` in an untrusted directory now asks for trust, or exits when not interactive. Separately, `hasTrustDialogAccepted` reverts to false for projects that were already trusted, which blocks resume on the trust prompt. handoff-fire, the pane runner and recycle all resume sessions without anyone at the terminal.
- **Open #97634 (283): `/tasks` no longer shows a subagent's model or effort.** Also open, #97687: an `opus` subagent silently falls back to opus-4-8 after a cyber refusal, and the parent is not told. Both make it hard to see model routing in the TUI, which is exactly what a Sonnet 5.5 rollout needs to measure. Read `message.model` from the transcripts instead.
- **Open #97763 (281, 282): subagent transcripts keep the start-of-stream `output_tokens` and `stop_reason: null` on about 75% of turns.** Any usage or telemetry script in this repo that sums subagent `output_tokens` from the JSONL undercounts on these builds. The Sonnet 5.5 vs Opus cost comparison depends on exactly those numbers.
- **281 L427: "send now" moves running tools to the background instead of cancelling them.** Background tools keep holding memory, and #85015 is still open.
- **Open #97833 (283): two processes resuming the same session fork the transcript, and one branch is dropped silently.** Our fleet has 4 accounts and uses `cc` to resume.

### IMPROVEMENT
- 282 L211-214: preserved thinking survives `/model`, resume with `--tools`, and bad `redacted_thinking` blocks. 281 L305-310: resume no longer drops reasoning or breaks the cache.
- 282 L219-220: login-refresh races across processes are fixed, which helps with 4 accounts.
- 283 L125: a dynamic workflow started during a model fallback now retries the configured model.
- 284 L56: Workflow sandbox hardening.
- 284 L14-16: stream corruption and overloaded-after-thinking errors are retried; compaction retries on "Prompt is too long".
- 283 L112 and L163: `/doctor prompt-audit`, useful for retuning CLAUDE.md and agents for Sonnet 5.5. Use it read-only.
- 284 L41: failed-hook stderr and status code are now logged.
- 281 L319 and L385: fd exhaustion and temp-snapshot pile-up are fixed.

### NEUTRAL (checked)
- **284 L66 / 283 L170, default auto mode.** All 5 account `settings.json` files have `defaultMode: auto` and the launcher passes `--permission-mode auto` (measured). Kimi is the exception, listed above.
- **284 L38, symlinked `.claude/rules` or `.claude` now needs approval.** No symlinked project `.claude` or rules exist under `~/Development` at depth 5 or less (measured, `find -type l`). The per-file symlink farm lives in user-level `~/.claude` (493 links), which is not the project scope this entry covers. No symlink-following GC or cleanup entry anywhere in 281-284.
- **Standing hazard checks:**
  - 284 L69-70 safety switch: `switchModelsOnFlag: false`, and only `claude-kimi` pins `ANTHROPIC_DEFAULT_OPUS_MODEL`, against a third-party host.
  - 282 L222 mid-pattern `:*`: no such rule in any settings file (measured).
  - 282 L264 OTEL: project settings contain no OTEL variables.
  - 282 L266-268 / 283 L182 namespace: we have no `claude-ai` or `anthropic-skills` skill folder.
  - 281 L332 `--setting-sources` forwarding: our only users are `-p` children with `''` (more restrictive), namely `hooks/model-permission-decider.py` and `bin/cc-memory-extract`.
  - 281 L298 `attribution:false`: we use the object form. Keep it while the fleet runs mixed 280 and 284.
  - No hook schema change for Stop, additionalContext or systemMessage anywhere in the band. 284 L42 (Elicitation) does not apply: we have no Elicitation hooks.
  - Write-without-read: only 281 L334, which covers duplicate parameters.
  - `CLAUDE_CODE_WORKFLOW_MAX_CONCURRENT_AGENTS`: the string count is 7 in 280 and 6 in 284 (measured). There is no changelog entry, so it is presumed unchanged. Verify with the gate's #08.
- **Today's Sonnet 5.5 tracker traffic** (measured, `gh search issues`): #97946, Sonnet 5.5 blocked by safeguards for CVP members on 2.1.284. No harness regressions filed yet.

## Before any flip
Wait for the classifier incident to clear, which you can check by counting `gave no verdict` in new transcripts. Then:
- Run the full cc-upgrade-gate on `~/.claude-284` across all 4 accounts. Add a probe that the `ultracode` keyword still triggers and records its effort.
- Pin or flip the `model: sonnet` agents in the SSOT diff.
- Add `defaultMode: default` to the kimi settings.
- Keep `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1`, keep `DISABLE_AUTOUPDATER=1`, and keep the stable-track `status` at skip until publish age reaches 7 days.

Sources:
- [github.com/anthropics/claude-code/issues](https://github.com/anthropics/claude-code/issues)
- [#93646](https://github.com/anthropics/claude-code/issues/93646)
- [#97442](https://github.com/anthropics/claude-code/issues/97442)
- [#97870](https://github.com/anthropics/claude-code/issues/97870)
- [#84974](https://github.com/anthropics/claude-code/issues/84974)
