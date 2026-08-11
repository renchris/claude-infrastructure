---
status: closed
created: 2026-08-11
owner: desk
---

# What does 100th percentile look like OUTSIDE this fleet

*Axis `state-of-the-art` of the context-economy 100th-percentile assessment `wf_5e9f820e-438`. Verdict: [`../context-economy-100p-2026-08-11.md`](../context-economy-100p-2026-08-11.md).*

**At 100th percentile:** `NO`

**Verdict.** No — the fleet is not at 100th percentile, because the one automatic context-management primitive its own harness ships and enables BY DEFAULT (`autoCompactEnabled`) is explicitly switched OFF in all four accounts with no recorded rationale, which is both the cause of the "dead in place" deaths and the reason the fleet's flagship measurement concluded the primitive does not exist.

**Load-bearing claim.** This fleet turned off the only automatic context-management primitive its harness exposes, and then measured its absence and concluded the primitive does not exist — so every comparable system in 2026 (Claude Code default, Codex CLI, OpenCode, OpenHands, Cursor, Warp) has a mechanical brake before the ceiling and this one has only an advisory the agent obeys 5 times in 2,545.

**Shortest fix.** One settings change per account, plus one doc correction. In each of the four settings.json: set `"autoCompactEnabled": true` and `"autoCompactWindow": 800000` (also fix settings-templates/settings.example.json:14 so installs stop shipping the disabled state). This keeps the full 1M window — it is a brake POSITION, not a cap — and places the mechanical net at 80%, ABOVE the existing discipline thresholds (idle 35 / pause-point 50 / drain 75 / never past 85), so recycle discipline remains the primary lever and auto-compact only catches the tail the advisory currently misses. Add a `# Compact instructions` section to CLAUDE.md so a compaction that does run preserves the frozen DoD, the open decision, and the landed shas rather than guessing. Correct docs/plans/CONTEXT_ECONOMY_V2.md:94, whose "autoCompactEnabled is unset / nothing in this repo configures it" invalidates that document's central "zero auto-compactions" conclusion. Estimated effort: under an hour; reversibility ~1.0.

**Skeptic: REFUTED** (confidence high)

> REFUTED as stated; a much narrower core survives.

What is TRUE (I confirmed it independently): `autoCompactEnabled: false` is set in all four account settings.json files, in ~/.claude/settings.json, and at the top level of ~/.claude.json, while the running binary's default is `true` (2.1.220: `JI(){... return Hc("autoCompactEnabled",!0).value}`; `DEFAULT_GLOBAL_CONFIG` has `autoCompactEnabled:!0`). The harness's own brake is off fleet-wide.

What is FALSE — the three load-bearing conjuncts:

1. "then measured its absence and concluded the primitive does not exist." CONTEXT_ECONOMY_V2.md:86-92 explicitly REFUSES that conclusion in its own words ("this row does not claim 'zero auto-compacts happened'; it reports that the metric counts an event with no observed instance and no proven emitter"), and the fleet SETTLED the cause on 2026-08-01: `docs/research/opus5-adaptation-2026-08-01.md:168` — "Also settled: `autoCompactEnabled: false` in settings.json — that is why 39/39 compactions are manual. There is genuinely no net at the ceiling." The investigator built its story on ONE stale sentence (V2:94, "unset in all three live settings roots"), which is false and was already superseded in-repo two days later.

2. "which is the cause of the dead-in-place deaths." Not established, and false for at least one of five. Exact-match scan of 9,063 transcripts across all five config dirs: 6 files, 5 distinct sessionIds, 8 refusal events, newest 2026-08-02. Four died at 946K-977K total input on a 1M window (ceiling-riders — a brake plausibly saves them). The fifth (c786f80f, opus-5, 2026-08-02) died at 444,604 tokens = 44% fill, refusing 0.111 s after a "Reply with exactly: RESUMED" wake following an 11-hour idle, after a 442K request had SUCCEEDED that morning. No compaction threshold reaches 44%. And "it would have braked at ~88%" is unverifiable here: the trigger fraction comes from a remote dynamic-config table keyed on windowSize (`$ds` → `Ke(Gn_,null)`) that is NOT cached locally (`autoCompactWindowsCache: null`).

3. "an advisory the agent obeys 5 times in 2,545." Wrong population. Scanning 7,406 transcripts (per-message input+cache_read+cache_creation, per-file max): p50 133K · p90 300K · p95 410K · p99 683K. Only 7 sessions of 7,100 ever reached 880K — 0.099%. The fleet does not ride toward the ceiling and get rescued by advisories one time in 500; it stays at 41% of window at p95, and the brake's whole eligible population is one session in a thousand. The load-bearing mechanism is architectural, not advisory: 69 sessions begin life as a fired notify-back peer, ~1,387 begin with some brief/handoff header — work is moved into fresh windows rather than compacted in place.

4. "no recorded rationale" is the wrong shape too. There is no rationale for the disable, but there IS a ratified fleet decision on exactly this knob saying the opposite: `docs/research/SESSION_AUTONOMY_RESEARCH.md:138` D-F — "Widen the auto-compaction margin at the source ... **Never disable auto-compact (survival backstop)**". So this is not defensible drift into an undocumented position; it is a live config that contradicts the fleet's own decision record.

THE SURVIVING CORE (strongest correct form): at the ~0.1% of sessions that actually reach the auto-compact zone there is no net of any kind — the harness's brake is switched off against the fleet's own D-F decision, AND the fleet's own deterministic forced-recycle successor has zero observed instances (0 of 7,408 first-user-messages carry waiting-recycle.sh:1091's successor literal). Of the 7 sessions that reached ≥880K, 4 died — a 57% mortality in the brake-eligible band. That is a real, small, last-resort gap in an otherwise healthy distribution; it is not the systemic cause the claim asserts, and re-enabling auto-compact is not obviously its fix, because compaction is lossy summarization (the operator's policy explicitly wants detail preserved) and the fleet's own panel measured that "imperfect recycle WITH a handoff brief strictly dominates certain 90% auto-compaction WITHOUT one" (desk-self-handoff-2026-07-19/panel-findings.md:63). The correct remedy shape is a MECHANICAL recycle at ~85% of the live window — the D-F margin plus a fire that actually fires — not a summarizer.

The axis VERDICT (not at 100th percentile) happens to be right; its stated reason is not.

Evidence: SETTING (MEASURED, instrument: rg over each config root)
- `"autoCompactEnabled": false` — ~/.claude-next/settings.json:1037 · ~/.claude-secondary/settings.json:1063 · ~/.claude-tertiary/settings.json:1063 · ~/.claude-quaternary/settings.json:1063 · ~/.claude/settings.json:1107 · plus top-level `autoCompactEnabled: False` in ~/.claude.json (python json load).
- Binary default TRUE (MEASURED, instrument: `strings` over the RUNNING binary — `ps -o command= -p $PPID` → /Users/chrisren/.claude-220/node_modules/.bin/claude, resolving to @anthropic-ai/claude-code/bin/claude.exe, 2.1.220): `function JI(){if(Z.DISABLE_COMPACT)return!1;if(Yt(process.env.DISABLE_AUTO_COMPACT))return!1;return Hc("autoCompactEnabled",!0).value}` and `DEFAULT_GLOBAL_CONFIG` = `{...autoCompactEnabled:!0...}`. The /config toggle writes this key (`wO("autoCompactEnabled",B)` + `tengu_auto_compact_setting_changed`), so it is an explicit switch-off, not drift.
- Trigger fraction is REMOTE (MEASURED): `$ds()` reads `Ke(Gn_,null)` — a windowSize-keyed table (`table_exact` / `table_default`) — with `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` / `CLAUDE_CODE_MAX_CONTEXT_TOKENS` as overrides. UNKNOWN locally: ~/.claude.json has `autoCompactWindowsCache: null` and only 2 cachedDynamicConfigs, none compaction-related ⇒ where the brake would engage on a 1M window is not derivable from disk.

DEATHS (MEASURED, instrument: python exact-match on a bare assistant message equal to "prompt is too long", case/whitespace-normalised, over 9,063 .jsonl across .claude-next/-secondary/-tertiary/-quaternary/.claude)
- 6 files, 5 distinct sessionIds, 8 events (4fe8d91c appears in BOTH ~/.claude-next and ~/.claude — a dir mirror; V2's "7 sessions / 10 events over 4,890" is likely counting such duplicates, since my corpus is 1.85× larger and finds fewer).
- Per-death total input at the last successful request before the refusal: 968,390 (4fe8d91c, opus-4-8, 07-19) · 976,563 (526aa752, opus-4-8, 07-12) · 970,045 (8a34082e, opus-4-8, 07-17) · 976,626 (076a1186, opus-4-8/fable-5, 07-26) · **444,604 (c786f80f, opus-5, 08-02)**.
- c786f80f detail: line 1050 user "Reply with exactly: RESUMED" at 19:07:43.693Z → line 1052 assistant `<synthetic>` "Prompt is too long" at 19:07:43.804Z. Prior successful request 442,584 cache_read at 08:28 the same day. Instant refusal at 44% fill, on a wake — not a ceiling ride.
- compact_boundary events in all five: 0.

DISTRIBUTION (MEASURED, instrument: python, 7,406 transcripts in the four ACCOUNT dirs, per assistant message input_tokens+cache_read+cache_creation, per-file max; 7,100 files had usage rows)
- p50 133,353 · p90 299,502 · p95 410,359 · p99 683,364 · max 976,626.
- Bands: <200K 5,270 · 200-500K 1,610 · 500-800K 201 · 800-880K 12 · 880-920K 2 · ≥920K 5.
- Sessions ever ≥880K: **7 of 7,100 (0.099%)** — and 4 of those 7 are the ceiling deaths (57% mortality inside the brake-eligible band).

RECYCLE / HANDOFF FIRING (MEASURED, instrument: python over first user message of 7,408 transcripts)
- 0 first-messages contain waiting-recycle.sh:1091's deterministic successor literal ("predecessor context was" / "monitoring DESK, resumed") ⇒ the fleet's own forced self-recycle has no observed successor. (Caveat: if that prompt text changed, this instrument under-counts — but the literal is at HEAD.)
- 69 begin as a fired peer (`notify-back` in the brief); 28 mention self-recycle; 1,387 carry some handoff/brief header (this last match is POLLUTED — sampling shows many are dispatched wave briefs and branch names containing "handoff", not recycles; report it as dispatch volume, not recycle count).
- ~/.claude/logs/handoffs.jsonl spans only 2026-08-08→08-11 (1,167 rows, mostly capacity-gate admits, many `under_test:true`) — it cannot support any fleet-lifetime rate claim in either direction.

REPO RECORD (MEASURED, cited)
- docs/plans/CONTEXT_ECONOMY_V2.md:86-92 — refuses the absence claim explicitly; :94 asserts "`autoCompactEnabled` is **unset** in all three live settings roots" — FALSE against the five files above, and superseded by:
- docs/research/opus5-adaptation-2026-08-01.md:168 — "Also settled: `autoCompactEnabled: false` in settings.json — that is why 39/39 compactions are manual. There is genuinely no net at the ceiling; but at 1M the ceiling is ~5× further away than the thresholds assume. `boundary-handoff.sh:88`'s 'autocompact at 90' comment is stale."
- docs/research/SESSION_AUTONOMY_RESEARCH.md:138 (D-F) — "`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=90`; the boundary hook fires at T≤73%. **Never disable auto-compact (survival backstop)**." Ratified decision, contradicted by the live config.
- docs/research/desk-self-handoff-2026-07-19/panel-findings.md:63 — "an imperfect recycle WITH a handoff brief strictly dominates certain 90% auto-compaction WITHOUT one (both strand, only one writes a brief; `/compact` also kills teammates)" — the recorded reason to prefer recycle over compaction.

SAMPLING DEFECTS FOUND IN THE CLAIM
(a) Single-sentence sourcing: the whole "the fleet doesn't know" story rests on V2:94, one stale line, with the correcting line (opus5-adaptation:168, nine days older than the claim) unread.
(b) Population inversion: "5 in 2,545" implies the advisory is the load-bearing brake over the whole fleet; measured, the brake-eligible population is 7 of 7,100 and p95 fill is 41%.
(c) Heterogeneous outcome treated as one cause: 1 of 5 deaths is at 44% fill and is not reachable by any compaction threshold.
(d) Counterfactual with no positive control: the trigger fraction is server-side and uncached, and V2's own 7th session compacted and died anyway — so "it would have saved them" is INFERRED, never measured.

**Instrument defect:** The claim's instrument was a single grep for `autoCompactEnabled` that stopped at CONTEXT_ECONOMY_V2.md:94 — one stale, false sentence ("unset in all three live settings roots") — and never checked the same repo's correcting record (opus5-adaptation-2026-08-01.md:168, which states the setting is false and that this is why 39/39 compactions are manual) or the ratified decision that forbids the disable (SESSION_AUTONOMY_RESEARCH.md:138 D-F). It then converted a policy/config observation into a causal claim about the deaths without profiling the deaths: 4 of 5 are ceiling-riders at 946K-977K, but the newest (2026-08-02, opus-5) refused at 444K = 44% fill, 0.111 s after a resume wake, where no compaction threshold could fire. Finally, its "5 in 2,545" frames the brake's population as the whole fleet, when only 7 of 7,100 sessions ever reach 880K (p95 max-fill is 410K of 1M) — an algebraic mismatch between the numerator (advisory obediences) and a denominator that includes ~7,093 sessions the advisory was never meant to act on.

---

## Findings

### `[MEASURED][GAP]` Auto-compaction is disabled fleet-wide: `"autoCompactEnabled": false` is present in all four account settings.json files, and is shipped in the reproducible install template.

- **Evidence:** Direct read of ~/.claude-next, ~/.claude-secondary, ~/.claude-tertiary, ~/.claude-quaternary settings.json — all four contain `"autoCompactEnabled": false`. Template: /Users/chrisren/Development/claude-infrastructure/settings-templates/settings.example.json:14. Platform default is `true` (https://code.claude.com/docs/en/settings — 'Automatically compact the conversation when context approaches the limit. Default: true; env override DISABLE_AUTO_COMPACT'). CC docs on the fill-up path: 'Claude Code compacts automatically as you approach the limit, so a full context window doesn't end your session.' (https://code.claude.com/docs/en/context-window).
- **Source:** `settings.json x4 (direct read) + code.claude.com/docs/en/settings + /docs/en/context-window`

### `[MEASURED][GAP]` The fleet's own flagship context doc states the opposite of the live config, so the headline conclusion 'no existence evidence the harness ever emits auto' rests on a population where the emitter was configured off.

- **Evidence:** docs/plans/CONTEXT_ECONOMY_V2.md:94 — '`autoCompactEnabled` is **unset** in all three live settings roots — the feature sits at its CC default and nothing in this repo configures it.' Contradicted by the live files above and by the fleet's own docs/research/opus5-adaptation-2026-08-01.md:168 — '(Also settled: `autoCompactEnabled: false` in settings.json — that is why 39/39 compactions are manual. There is genuinely no net at the ceiling…)'. The two docs disagree; the config file settles it.
- **Source:** `docs/plans/CONTEXT_ECONOMY_V2.md:94 vs docs/research/opus5-adaptation-2026-08-01.md:168`

### `[MEASURED][GAP]` The operator's stated policy — full 1M window, never a static cap, discipline as the lever — is exactly satisfiable by `autoCompactWindow`, which the fleet does not set. It is a BRAKE POSITION, not a window size.

- **Evidence:** code.claude.com/docs/en/settings: `autoCompactWindow` — 'How full the context window gets before Claude Code compacts automatically, in tokens from 100000 to 1000000. When unset, Claude Code uses a window tuned for your model.' Settable three ways (/docs/en/context-window §Set the auto-compact window): `/autocompact 800k` (writes user settings), `--autocompact` per launch (not preempted by managed settings), `CLAUDE_CODE_AUTO_COMPACT_WINDOW` (highest precedence). Grep of the repo returns zero occurrences of autoCompactWindow / CLAUDE_CODE_AUTO_COMPACT_WINDOW.
- **Source:** `code.claude.com/docs/en/context-window + repo rg (0 hits)`

### `[MEASURED][GAP]` The fleet's recycle actuator is ADVISORY and acts ~0.2% of the time; every comparable system condenses mechanically with zero agent consent.

- **Evidence:** ~/.claude/autonomy/recycle-events.jsonl, 2,545 rows, all hook=context-econ: verdict advised=2,505, nudged=23, shadow-would-fire=12, executed=5. Floor caveat, stated by the code itself: scripts/handoff-fire.sh:622-631 — 'a successful recycle and a recycle that never happened produce byte-identical ledgers. Measured 2026-08-09: 1012 rows spanning 41h carry ZERO recycle rows of any class' — so 5 is a lower bound and the true execution rate is UNMEASURABLE from this store. Contrast: OpenHands LLMSummarizingCondenser fires on max_size with keep_first (docs.openhands.dev/sdk/guides/context-condenser); Codex CLI auto-compacts at model_auto_compact_token_limit 180k-244k; OpenCode prunes when isOverflow(); CC's own auto-compact fires at ~95%.
- **Source:** `~/.claude/autonomy/recycle-events.jsonl (python3 counter) + scripts/handoff-fire.sh:622-631 + vendor docs`

### `[MEASURED][GAP]` The window denominator is still null in 98.8% of rows of the DURABLE store built specifically to preserve it.

- **Evidence:** Same parse of recycle-events.jsonl: window field is null in 2,515 of 2,545 rows; 1000000 in 30. hooks/lib/context-econ.sh documents the design intent — the denominator 'is captured where the record is actually DURABLE, and only there: ce_log_drop → idl.jsonl, and the recycle-outcome store' — but the field is empty at write time in almost every row, so the durable store inherits the ephemeral store's blindness.
- **Source:** `~/.claude/autonomy/recycle-events.jsonl + hooks/lib/context-econ.sh header`

### `[INFERRED][GAP]` Re-enabling auto-compaction reaches the SAME memory outcome the fleet's #1-ranked lever was chasing, without the static cap the operator rejects.

- **Evidence:** docs/research/jcode-due-diligence-2026-08-11.md:115 ranks 'L7 context-ceiling cap (CLAUDE_CODE_DISABLE_1M_CONTEXT / cap 200K)' as the #1 lever, score 0.95 reversibility, on the cost model MB = 228 + 0.343 x K-input-tokens + 0.071 x min, noting 'Every live session runs a 1M window with autocompact off ⇒ a 343 MB per-session ceiling.' Because the coefficient is on RESIDENT input tokens, not on the window SETTING, auto-compaction at an 800K brake cuts the same term — the reading in the brief is correct and it argues for the brake, not the cap.
- **Source:** `docs/research/jcode-due-diligence-2026-08-11.md:115,764 (measured model) + arithmetic`

### `[MEASURED][GAP]` Platform-level context editing and server-side compaction exist but are NOT reachable from Claude Code — so their absence here is a platform boundary, not fleet negligence; the equivalent is implemented CLIENT-SIDE by a competitor.

- **Evidence:** platform.claude.com/docs/en/build-with-claude/context-editing ships `clear_tool_uses_20250919` (trigger default 100k input tokens, keep=3 tool uses, clear_at_least, exclude_tools, clear_tool_inputs) and `clear_thinking_20251015`, plus memory-tool integration (`memory_20250818`) where Claude is warned to save to memory files before results are cleared. Same page: 'Claude Code does not explicitly use context editing strategies.' platform.claude.com/docs/en/build-with-claude/compaction ships `compact_20260112` (trigger default 150,000 input tokens, min 50,000; pause_after_compaction; custom instructions) — 'Compaction is NOT available in Claude Code.' OpenCode implements the equivalent itself: backward scan over tool calls, protect the last 40k tokens, prune beyond that when >20k is prunable (gist.github.com/badlogic/cd2ef65b0697c4dbe2d13fbecb0a0a5f).
- **Source:** `platform.claude.com context-editing + compaction docs; badlogic cross-harness gist`

### `[MEASURED][GAP]` Custom compaction instructions are supported by this harness and unused here, so any compaction that does run guesses what to keep.

- **Evidence:** code.claude.com/docs/en/costs: '/compact Focus on code samples and API usage' and a `# Compact instructions` section in CLAUDE.md. rg for 'compact instruction|# Compact' across /Users/chrisren/Development/claude-infrastructure/CLAUDE.md and ~/.claude/CLAUDE.md returns NONE. The only PreCompact hooks configured are two `date >> sessions.log` loggers (~/.claude-next/settings.json:992-1000) — pure telemetry, no content policy. Field contrast: Codex CLI keeps ~20k tokens of recent user messages verbatim beside the summary; OpenCode uses a dedicated compaction system prompt distinct from its UI summary.
- **Source:** `repo rg (NONE) + ~/.claude-next/settings.json:992 + code.claude.com/docs/en/costs + badlogic gist`

### `[INFERRED][GAP]` No episodic recall over the fleet's own transcripts: after a recycle, everything not hand-written into a brief is unreachable. The field ships thread reopen/fork and retrieval-backed memory tiers.

- **Evidence:** Field: Codex `resume` reopens a prior thread with the same repo state and `fork` branches it from a decision point; Amp's Handoff is file-backed with thread references and a secondary model doing selective on-demand extraction from the prior thread (badlogic gist; codex.danielvaughan.com). Letta/MemGPT's three-tier main-context / recall-store / archival-store, Zep+Graphiti's temporal knowledge graph, Mem0 — the 2026 production pattern is 'small always-in-context core + retrieval layer + explicit forgetting policy'. Here: MEMORY.md (semantic/procedural) and plan docs (task state) exist, but the 4,890-transcript corpus is measured over and never queried at succession time; the succession payload is an agent-written brief. The fleet's own memory index records the failure mode this produces — 'recycle announced but never fired: died holding a WRITTEN successor brief; preparing a recycle costs the context it escapes'.
- **Source:** `badlogic gist + agent-memory 2026 surveys + fleet MEMORY.md index entry recycle-announced-but-never-fired.md`

### `[MEASURED][STRENGTH]` AHEAD OF THE FIELD: a written, three-way disposition rule that decides succession BEFORE the wall (Recycle / Handoff / Hold), with the Hold branch defined so it converts itself into a Recycle.

- **Evidence:** CLAUDE.md § Session Close Protocol context table, incl. the Hold test ('what would a successor reading only the disk get wrong?' — a concrete answer's FIRST action is writing it down, which converts Hold into Recycle). No surveyed harness has a pre-wall succession POLICY: Codex/OpenCode/OpenHands/Cursor act only at overflow; Amp's 'keep conversations short & focused' is doctrine with no decision procedure.
- **Source:** `CLAUDE.md § Session Close Protocol; badlogic gist for the four harnesses`

### `[MEASURED][STRENGTH]` AHEAD OF THE FIELD: a durable, reboot-surviving decision ledger for context events. No surveyed harness records context-management decisions at all.

- **Evidence:** ~/.claude/autonomy/idl.jsonl = 48,820 rows; recycle-events.jsonl = 2,545 rows, each carrying hook, verdict, used_pct, trigger, mode. Vendor docs for Codex/OpenCode/OpenHands/Amp describe compaction mechanisms with no decision ledger; CC itself records compaction only as `compactMetadata` inside the transcript.
- **Source:** `direct wc/parse of the two stores; vendor docs`

### `[MEASURED][STRENGTH]` AHEAD OF THE FIELD: offloading has three units, and the biggest one charges the work to a DIFFERENT window rather than summarizing it.

- **Evidence:** Anthropic documents only subagent offloading ('Delegate verbose operations to subagents … the verbose output stays in the subagent's context', code.claude.com/docs/en/costs) and warns agent teams use ~7x tokens. The fleet's CLAUDE.md mandates a stronger form — one dispatched `/handoff` session per implementation wave, lead retains >=50% of its window, teammates only where synthesis must be immediate. This is a superset of what Amp achieves with Handoff and of what Codex is still requesting (openai/codex issue #23218 asks for an agent-controlled task transition that clears context and carries the session id — a capability handoff-fire already has).
- **Source:** `CLAUDE.md § Agent Teams Reinforcement; code.claude.com/docs/en/costs; github.com/openai/codex/issues/23218`

### `[MEASURED][STRENGTH]` AHEAD OF THE FIELD: deliberate anti-summarization on recovery, with a measured reason specific to this harness.

- **Evidence:** skills/resume-sessions/SKILL.md:104-110 — resume answers the large-session dialog with option 2 'Resume full session as-is', never option 1, because option 1 runs /compact and drops the session-scoped /goal Stop hook; the trigger is the 5-char token `as-is` because the 19-char literal wraps on a narrow pane and never matches. Field default is to accept the summary.
- **Source:** `skills/resume-sessions/SKILL.md:104-110`

### `[MEASURED][STRENGTH]` AHEAD OF THE FIELD: the memory index is budgeted in BYTES against the harness's documented loader truncation point.

- **Evidence:** hooks/lib/memory-index-budget.sh + bin/cc-memory-rotate + tests/memory-index-budget.bats, sized to CC's auto-memory cap. CC docs confirm the cap exists: auto memory loads 'the first 200 lines or 25KB, whichever comes first' (code.claude.com/docs/en/context-window simulation, Auto memory event). Letta/Mem0/Zep manage memory size against a store; none size it to a specific harness loader's truncation boundary.
- **Source:** `hooks/lib/memory-index-budget.sh; code.claude.com/docs/en/context-window`

## Unknowns

- WHY autoCompactEnabled was set to false — no rationale is recorded anywhere in the repo, the template comment does not mention it, and `git log -S` returned only checkpoint noise. If there is a real reason (e.g. compaction destroying session-scoped /goal hooks, which resume-sessions:104-110 documents for the resume path), it must be found before flipping it, and it would argue for a high autoCompactWindow rather than for leaving the net off.
- Whether the 7 'Prompt is too long' deaths occurred under autoCompactEnabled:false — the setting's history is not reconstructable from git, so the causal link between the disabled net and those deaths is INFERRED, not measured.
- The TRUE recycle execution rate. handoff-fire.sh:622-631 states a successful recycle and a recycle that never happened write byte-identical ledgers, so 5/2,545 is a floor of unknown tightness. Until a successful recycle emits a row, no claim about discipline compliance is measurable — including a post-fix claim that the brake was unnecessary.
- Whether Claude Code exposes any per-turn tool-result eviction under a different name (the docs deny context editing and server-side compaction; I found no evidence of a 'microcompact' primitive in the current docs, only /compact, /autocompact, /clear, /context and subagent offloading). Not confirmed either way against the running 2.1.220 binary.
- Whether the fleet already filters verbose tool output at the hook layer (Anthropic's documented PreToolUse output-filter pattern). The machinery exists (hooks/qos-rewrite.sh rewrites Bash commands) but I did not verify any hook that truncates or greps tool output for context economy.
