# Prompt audit — shard hooks-b (hook-injected model-facing text, second alphabetical half)

## Step 0 assumptions
- Scope: 26 files = second half (alphabetical) of `git grep -lE 'additionalContext|systemMessage|permissionDecisionReason|"reason"' hooks` (52 files): mailbox-drain, memory-index-drain, memory-nudge, model-permission-decider.py, operator-readout, plan-agent-teams-default, pr-gate, read-before-write-parity, recover-inject, relay-verbatim, research-precognition-nudge, reset-hard-shadow-allow, rm-safe-allowlist, session-continue, session-index-start, session-start, setup-plan-symlinks, setup-task-symlinks, ship-rail-push-allow, subagent-stop, tests/validate-bash.test.sh, unit-gate, validate-bash, validate-plan-structure, waiting-recycle, workflow-script-edit-allow.
- Audited only text that reaches the model: additionalContext (all events), PreToolUse deny reasons, Stop/PostToolUse `decision:block` `reason`, exit-2 stderr. `systemMessage` is operator-only (repo-measured, CLAUDE.global.md:486) and allow-reasons are shown to the operator, so operator-readout.sh (pure systemMessage) and the allow hooks' reasons were checked and are out of scope. hooks/tests/validate-bash.test.sh is a test harness (no injected text).
- Target model: Opus 5.5 (default), Fable 5.1, Sonnet 5.5 workers. model-permission-decider.py pins its own judge model (claude-haiku-4-5-20251001).
- settings.json was not read (secrets rule); hook registration was inferred from transcripts and the IDL.

## Measurement method (the per-turn question)
Claude Code 2.1.28x writes each hook injection into the transcript with a `rendered` field = the exact system-reminder text the model receives. Script `/tmp/capi-audit/hb_census.py` summed those over every main transcript modified in the last 14 days across all 6 config dirs (5,176 sessions). Earlier CC versions do not write `rendered`, so all counts are LOWER bounds.

### Per-turn / high-frequency injections owned by this shard (14 d unless noted)
| hook | event / cadence | rendered size | fires | note |
|---|---|---|---|---|
| mailbox-drain.sh wake nudge, live-/goal branch (:470) | UserPromptSubmit, EVERY prompt while unwatched | ~1,330 chars (~330 tok) | 2,320 in 7 d, 218 sessions, max 84 in ONE session | finding hooks-b-01 |
| mailbox-drain.sh wake nudge, no-goal branch (:474) | UserPromptSubmit, every prompt while unwatched | ~340 chars | 1,801 in 7 d | finding hooks-b-02 |
| mailbox-drain.sh peer-mail frame | UPS / PostToolUse, on delivery | 1.6-2.7K incl. mail | ~1,600 | frame ~250 chars; fine |
| memory-nudge.sh | UPS, every 12th prompt | ~3,660 chars | 723 / 356 sessions | finding hooks-b-08 (small) |
| plan-agent-teams-default.sh PLAN DEFAULTS | PreToolUse plan edit | ~1,365 chars | 1,159 | already deduped once per (session,file) on 2026-09-28 — clean |
| research-precognition-nudge.sh | UPS on research-intent regex | ~770 chars | 794 | trigger text, keyword-gated — clean |
| session-continue.sh Stop reasons | Stop block | wake floor 1,239; ship floor ~720; loose-ends ~650-850 | 403 / ~400 / ~150 | bounded by budgets; clean |
| setup-task-symlinks / setup-plan-symlinks / session-start / session-index-start | SessionStart once | part of 2-8K combined block | ~1 per session | findings hooks-b-03..06 (stale facts) |
| waiting-recycle.sh | PostToolUse, rare | 570-1,000 chars, delivered TWICE | 3 in 30 d | finding hooks-b-07 |

## Summary
Highest impact: (1) mailbox-drain's live-/goal wake nudge re-inserts the same ~330-token paragraph at every user prompt (84 copies in one session) while validate-bash.sh:347 already denies the unsafe arm with the same explanation at the moment of the act — a 1d "instruction re-insertion" fossil; dedupe to once per (session, goal). (2) setup-task-symlinks tells every session false task facts ("Tasks: 186 active ... (0 total)") — `totalOnDisk` includes completed tasks and `find` does not descend the symlinked tasks dir on 3 of 4 accounts (measured 0 vs 863). (3) session-start still tells every session to fall back from BrowserMCP, retired per the global instructions.
Counts: Group 1 = 3 (re-insertion x2, restatement x1); Group 2 = 6 (stale facts x4, dangling reference x2); Group 3 = 0 (no tool descriptions in scope); Group 4 = 1 (duplicated channel delivery) + flags.

## Findings (confidence order)

### hooks-b-03 — HIGH — hooks/setup-task-symlinks.sh:183 — rewrite
Evidence: `TOTAL=$(find "$TASKS_DIR" -maxdepth 1 -mindepth 1 -type d ...)`. Pattern: Group 2 volatile/false fact. On next/next4/quaternary/secondary `tasks` is a symlink to ~/.claude/tasks (CLAUDE.md: shared store); BSD find does not follow a command-line symlink, so the count is 0 (measured: `find ~/.claude-quaternary/tasks ...` = 0, with trailing slash = 863). Every session there is told "(0 total)" beside "N active". Fix: `"$TASKS_DIR/"`.

### hooks-b-04 — HIGH — hooks/setup-task-symlinks.sh:187 — rewrite
Evidence: `ACTIVE_TASKS=$(jq -r '.totalOnDisk // 0' ...)` rendered as "Tasks: ${ACTIVE_TASKS} active". task-helpers.sh:182 defines totalOnDisk = ALL tasks incl. completed; observed "Tasks: 186 active". Fix: pending + in_progress.

### hooks-b-01 — HIGH (measurement) / MEDIUM (behavior) — hooks/mailbox-drain.sh:469-470 — needs-new-code
Pattern 1d instruction re-insertion. The goal-live branch fires on every UserPromptSubmit while no watcher is armed — which under a live goal is the CORRECT state the text itself recommends, so it never self-limits. The same content is enforced at the chokepoint (validate-bash.sh:347 denies the 4-hour park under a live goal with the idle-scoped command and full reason) and taught again at the idle Stop by the wake floor (session-continue.sh:909-913). Fix: emit it once per (session id, goal-condition hash) via a marker; keep the parked-watcher (E2) and inert-goal crumb alarms per-prompt (they are state alarms that clear themselves). Est. saving ≈ 90% of ~780K tokens/week of re-inserted context (plus their cache reads for the rest of each session). Tests: mailbox-drain.bats:374/744 assert first-fire content (unchanged); add a second-prompt-silent test.

### hooks-b-05 / hooks-b-06 — MEDIUM-HIGH — hooks/session-start.sh:422 and :426 — rewrite
Evidence: "If BrowserMCP tools fail with 'No such tool available', use agent-browser skill instead." From the initial commit (aa391e469, 2026-03-24). The global instructions (both variants) say BrowserMCP is retired and no mcp__browsermcp__* tools exist, so this is a fossil injected into every session. No test pins it.

### hooks-b-02 — MEDIUM — hooks/mailbox-drain.sh:473-474 — needs-new-code
Group 2 cross-file disagreement (latent). session-continue.sh:650 abstains its wake floor when `wake_arm_on_stop_registered` (mailbox-wake-arm.sh on Stop with asyncRewake — the mechanical arm, goal-safe), because then the watcher is armed at every Stop with no model action. mailbox-drain's per-prompt nudges (both branches) do not consult that predicate, so once migration 0012 is applied the drain keeps telling the model "peer mail will sit unread until someone types at you" — false at that point — and keeps asking for an arm the harness already does. Today the IDL shows 28 wake-floor fires and 0 mechanical-arm abstains in the last ~8 h, i.e. 0012 is not live, so this is latent; fix by moving `wake_arm_on_stop_registered` into hooks/lib/mailbox-pending.sh (SSOT; tests/wake-floor.bats already pins the two advisories agreeing) and gating both drain branches on it.

### hooks-b-07 — MEDIUM (low impact) — hooks/waiting-recycle.sh:1111-1112, 1320-1321, 1351-1352, 1493, 1498, 1520, 1551-1552 — needs-new-code
Group 4 / 1c repetition: these 7 sites set `reason`, `systemMessage` AND `additionalContext` to the SAME string. On PostToolUse a `decision:block` reason is rendered to the model as "PostToolUse:Bash hook blocking error ..." (measured: transcript 846419e4 rendered field) and additionalContext is rendered separately, so the model reads each advisory twice (both attachments observed for one toolUseID in transcripts 8f3653c5 / b1140d32). The script's own header (:124) and tests/waiting-recycle.bats:630 assume reason is operator-facing; it is not. The canonical Stage-1 site (:1591) already uses a short `sysmsg` as reason. Fix: `reason:($s|split(" — ")[0])` (headline) at each site; systemMessage stays full for the operator; tests assert only additionalContext. Fires only ~3 times in 30 d now, so the saving is small; the value is a correct channel model.

### hooks-b-08 — MEDIUM — hooks/memory-nudge.sh:685 — rewrite (partial)
Pattern 1d re-insertion / 1c repetition: every 12th prompt the nudge restates rules already resident in both global variants (CLAUDE.global.slim.md:41-48, CLAUDE.global.md:100-122): the what-not-to-record list, cc-memory-search first, Write-not-Bash. Proposed: replace only that unpinned sentence pair with a pointer (~250 chars saved per fire). The CORRECTED / superseded_by / Replaces clause is deliberately duplicated (c92df1f22) and pinned by tests/cc-memory-supersession-check.bats:122-136 — left alone. The FILING and UNITS clauses were checked against provenance (4e2d45a79: the 21 mints happened UNDER the limit) and are load-bearing — left alone.

### hooks-b-09 / hooks-b-10 — MEDIUM — hooks/validate-bash.sh:1154, :1168 — rewrite
Group 2 dangling reference: "See CLAUDE.md critical rule #2." The numbered Critical Rules exist only in the reso-* project CLAUDE.md files; validate-bash runs in every repo, and the global rule (CLAUDE.global.slim.md Git → Safety) is unnumbered. Re-point to the global section. (The DDL deny at :1096 "critical rule #1" is reso/Drizzle-specific and resolves where it can fire — left alone.)

## Flags (no edit proposed)
- validate-plan-structure.sh:125 "Agent Teams are the DEFAULT for all implementation work (9/10 sessions)" followed by "S = dispatched handoff session — the DEFAULT" reads self-contradictory, but the same wording is in CLAUDE.global.md:175 and skills/plan-conventions/SKILL.md:36 ("Agent Teams" as umbrella for Phase-0 orchestration), so the files agree; slim variant reframes it. Operator wording decision, not cruft.
- model-permission-decider.py: a `claude -p` judge on Haiku 4.5 retired 2026-09-30 by measurement (migration 0022 header: ~12M tokens/day, 8.7 s p50). If re-staged: `claude -p` carries the full Claude Code system prompt for a one-word ALLOW/ASK verdict; a replacement `--system-prompt` (or a direct Messages API call with structured output) would cut that per-call cost by an order of magnitude. The prompt text itself is clean (reasoned asymmetry, no pressure language).
- read-before-write-parity.sh:38 "Claude Code no longer applies this guard to this model" — migration-relative phrasing (1d), but it is the reason the deny exists; harmless.
- Cross-shard: the WAKE-PATH-DOWN mail body written by bin/cc-await-ping (~2.5K chars, observed in a SessionStart block) and the global-instructions claim "mailbox-wake-arm wakes an idle session" (not registered on Stop per IDL today) belong to other shards.
- Peer mail delivered as PostToolUse additionalContext after tool results (mailbox-drain post-tool mode): Sonnet 5.5 can read mid-turn text after a tool_result as possible injection; the frame already labels provenance ("Notice from peer Claude sessions on this machine"). Watch on Sonnet 5.5 workers; no edit.

## Clean
relay-verbatim, recover-inject (once per death record, fragile-op script with reasons), memory-index-drain (conditional, factual), research-precognition-nudge (keyword-gated trigger text), plan-agent-teams-default (deduped 2026-09-28), pr-gate (operator policy with escape hatch), unit-gate, session-index-start, setup-plan-symlinks, the allow-hooks (reasons are operator-facing), subagent-stop (emits nothing model-facing by design), session-continue's ship/loose-ends/custody reasons (bounded, reasoned, enforced).
