# Prompt audit — shard skills-b

## Assumptions (Step 0)
- Scope: skills/ entries 13-25 of /Users/chrisren/Development/.worktrees/wt-cc-003409-15565: demo-recording, dia-agent, frontend-design-vue (SKILL + 7 references), frontier-campaign, frontier-hole, frontier-routing, frontier-run, grok-wiki-audit, ground-up, launch-film (SKILL + pipeline/design-gate/reference-film-method/studio-method/operator-feedback), LOCAL_ONLY.md, manual-command-delivery, model-upgrade. 26 prompt-surface .md files.
- Not audited as prompt text: launch-film/kit/** code (render.mjs, scene.js, *.py, *.sh), kit/brag-slim/SKILL.md (vendored MIT upstream, not a loaded skill — it sits under kit/), kit/sound/BRIEF.md and kit/example/brag-plan-v3.md (worked-example data). LOCAL_ONLY.md is a record read by a falsifier and config/live-only.manifest, not loaded as a skill — clean, not applicable.
- Target model: Claude Opus 5.5 (lead default, `roles.lead_default`), Fable 5.1 for frontier panels. Read-only; no edits applied.

## Summary
The highest-impact findings are Group 2 stale facts that the repository itself contradicts:
1. frontier-run tells panel leads that subagent frontmatter `effort` is "unparsed"; the repo's own 2.1.284 probe (docs/research/sonnet55-utilization-2026-09-28/notes/probe-effort-binding.md:84,127) shows it is honoured on the Agent(subagent_type) path. frontier-campaign likewise prescribes `set-teammate-effort.sh` as the binding effort lever, which the script itself (lines 15-23) and agent-teams say is SUPERSEDED from 2.1.220.
2. frontier-run's cost line ("Fable 5 = $10/$50 ≈ 2× Opus, drawn from the 5-hour plan windows") contradicts CLAUDE.global.md § Frontier Tier Routing (quota not dollars; 50% weekly sub-cap; 2-5× draw) and model-config (`source: plan-usage`, window era closed). It also names launchers (`claude-fable`, `claude-previous`/`cc-previous`, "eval-track") that model-config.yaml:1256 records as deleted by launcher consolidation v2.
3. launch-film's description is 641 chars against the 250-char DESC_MAX enforced by tests/skill-listing-budget.bats (OVERRIDES empty); commit 09723d748 records the test red on trunk from this file.

Counts: Group 1: 3 (1c duplication x2, 1d migration-relative phrasing x2 — one folded into a Group 2 rewrite). Group 2: 13. Group 3: not applicable (no tool definitions). Group 4: not applicable (no request-building code in shard).

## Findings (highest confidence first)

| id | Location | Pattern | Why | Conf | Action |
|---|---|---|---|---|---|
| skills-b-01 | frontier-run/SKILL.md:70-77 | G2 volatile specifics (repo-contradicted) | "frontmatter `effort` unparsed" refuted by probe-effort-binding.md:84,127 (2.1.284: honoured on Agent subagent_type path); frontier-derivation pins no effort, so the inheritance conclusion holds but for a different reason | high | rewrite |
| skills-b-02 | frontier-campaign/SKILL.md:53-58 | G2 volatile / conflict | prescribes set-teammate-effort.sh as binding; scripts/set-teammate-effort.sh:15-23 and agent-teams SKILL:210-213 say from 2.1.220 the member gets `--effort <lead>` and the file does not bind | high | rewrite |
| skills-b-03 | frontier-run/SKILL.md:31-32 | G2 conflict with CLAUDE.global.md | dollar price + "5-hour plan windows" vs CLAUDE.global.md (quota, 50% weekly sub-cap, ~2-5× draw) and model-config `source: plan-usage` | high | rewrite |
| skills-b-04 | frontier-run/SKILL.md:18-27 | G2 volatile + 1d migration-relative | names `claude-previous`/`cc-previous` (consolidation v2 kept only `claude` and `claude-prev`, model-config.yaml:1256) and pins "claude (2.1.260)"; the "This step used to read…" archaeology is a diff against a prior prompt | high | rewrite |
| skills-b-05 | frontier-run/SKILL.md:64-69 | G2 volatile | `claude-fable` launcher and "eval-track only" — both deleted (model-config.yaml:1254-1257; the same file's step 2 says so) | high | rewrite |
| skills-b-06 | frontier-run/SKILL.md:109 | G2 dead path | `~/.claude/rules/research-subagents.md` — rules/ removed (install.sh:1035, 270baf8); the content is the research-subagents skill | high | rewrite |
| skills-b-07 | frontier-hole/SKILL.md:8 | G2 pinned model name | "Opus 5 @ high"; lead_default is claude-opus-5-5 (model-config.yaml:911). Use the SSOT keys as frontier-routing does | high | rewrite |
| skills-b-08 | frontier-run/SKILL.md:9 | G2 pinned model name | "Opus 5 @ high" | high | rewrite |
| skills-b-09 | frontier-run/SKILL.md:46-47 | G2 pinned model name | "(typically Opus 4.8)" — two generations stale | high | remove |
| skills-b-10 | frontier-campaign/SKILL.md:59 | G2 pinned model name | "(Opus 5 teammates)" | high | remove |
| skills-b-11 | launch-film/SKILL.md:3 | G2 trigger enumeration / repo gate | 641-char description vs DESC_MAX 250 (tests/skill-listing-budget.bats:38, OVERRIDES={}); rides in every session's skill listing | high | rewrite (248 chars) |
| skills-b-12 | frontend-design-vue/SKILL.md:105 | G2 conflict with CLAUDE.global.md | "Playwright / BrowserMCP" — global: browser automation is the agent-browser CLI, not Playwright; BrowserMCP retired | high | rewrite |
| skills-b-13 | demo-recording/SKILL.md:189-193 | 1c padding: verbatim duplicate | the ffmpeg/Pillow/webpinfo paragraph appears twice back to back (a76834f08 re-added it) | high | remove |
| skills-b-14 | dia-agent/SKILL.md:153-156 | G2 intra-file drift | PRIMARY step 2 says port is ephemeral and changes per toggle; the newer 2026-09-14 § Corrections (blame 686136b7c) and VERDICT.md:126 say fixed 9222 on 1.48.0, stable across toggles | high | rewrite |
| skills-b-15 | dia-agent/SKILL.md:307-308 | G2 intra-file drift | same stale "ephemeral" hard fact | high | rewrite |
| skills-b-16 | dia-agent/SKILL.md:12-18 | G2 option menu / intra-file conflict | top says PRIMARY "Start here"; § ZERO-PROMPT RAIL says AppleScript BEFORE CDP; § Status says use SECONDARY for autonomous work. One default + escape hatches | medium | rewrite |
| skills-b-17 | frontend-design-vue/SKILL.md:13 | 1e frontend exception + G2 conflict | Signal default (cream + burnt-orange accent) is pitched as anti-AI-slop, but launch-film/studio-method.md §3 (2026-09-28) and the Opus 5.5 guidance name cream + clay-orange, italic-serif accent words, 01/02/03 labels, mono labels, pill buttons as the model's own fallback look. Extend the named list; do not change the default (operator's call) | medium | add |
| skills-b-18 | demo-recording/SKILL.md:3 | G2 volatile | description says "iTerm2 sizing"; body line 201 says host is kitty and the it2 forms fail as typed | medium | rewrite |
| skills-b-19 | frontier-hole/SKILL.md:12 | G2 conflict (cost currency) | "the 2× cost" — global: 2-5× quota draw | medium | rewrite |
| skills-b-20 | demo-recording/SKILL.md:265-268 | 1d migration-relative | "This line previously read…" — keeps the measurement, drop the phantom prior text | medium | rewrite |
| skills-b-21 | manual-command-delivery/SKILL.md:96-110 | 1d migration-relative / G2 history narrative | restates the superseded spec (commented step-by-step document) the rule exists to prevent; keep the Why, operator quotes and the still-true rule | medium | rewrite |
| skills-b-22 | demo-recording/SKILL.md:374-375 | 1c repetition | "PIL is the path; render one PNG per frame so captions can fade, rise…" restates the previous sentence | medium | rewrite |

### Flag-only (low confidence / out of shard)
- frontier-run:139-145 and frontier-campaign:64-68 name `SendUserMessage` + beta `mid-conversation-system-2026-04-07` (2.1.170). Current sessions expose SendUserFile; whether SendUserMessage still exists could not be verified from the repo. Flag.
- dia-agent:196-198 (step 6 "EPHEMERAL 127.0.0.1 port") and :327 (troubleshooting "the port is ephemeral") carry the same stale port fact as skills-b-14/15; and the § Status 2026-06-29 block remains a version-dated menu. A restructure (fold § Corrections into the body, drop dated Status) is proposed only — needs the operator's approval per repo rule.
- demo-recording:199-254 leads with iTerm2 recipes and appends kitty equivalents although the host is kitty; reorder kitty-first is a restructure — flag.
- frontier-run:114 heading "makes it worth 2×", frontier-campaign:11 "at 2× price" — same stale cost currency as skills-b-19; low value.
- Out of shard: skills/agent-teams/SKILL.md:222-223 and :249-251 repeat the "in-process subagents … no override surface" claim refuted by probe-effort-binding.md (frontmatter effort is honoured). Companion to skills-b-01; belongs to the shard owning agent-teams.
- model-config.yaml:956 comment "eval-track teammates" — companion to skills-b-05, outside the shard.
- frontend-design-vue:98-100 "Naming conflict policy" is rename history with no behavioral content (low).

### Checked and clean
- model-upgrade (fresh 2026-09-28 stub, disable-model-invocation, costs no context).
- frontier-routing (uses SSOT keys, no pinned names; consistent with CLAUDE.global.md).
- ground-up, grok-wiki-audit (paths named exist: LAND_PIPELINE_V2.md, GROUND_UP_DISPATCH.md, GROUND_UP_REBUILD_MAP.md, STRANDED_EXPOSURE_2026-07-26.md, grok-wiki-audit-2026-08-10/, workflow-lean agent).
- manual-command-delivery pressure language (6 markers) guards credentials/consent and is enforced elsewhere (keep-list); only the history section is flagged.
- launch-film body, studio-method, pipeline: operator-ruled, dated, recent; the Do-NOT list carries reasons (1e keep). tools/hero-film, hero:pacing and the hero-brag branch exist.
- frontend-design-vue references: author-specific design-system tokens and a11y contract (keep).
