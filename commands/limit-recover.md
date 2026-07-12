---
name: limit-recover
description: Recover perfectly from a usage-limit interruption (5-hour / weekly / model-scoped Fable) — disk-truth audit of every Dynamic Workflow slot, subagent, and task; re-run everything not provably COMPLETE (accepting partial results is banned); or continue with zero loss on another of the 4 accounts via validated transcript transplant + salvage bundle. Use when: a session was killed by "You've hit your session/weekly limit", when resuming after a limit ("continue, we hit our limit"), when workflow/subagent results came back null/partial/empty, or when the reset is too far away and work should continue NOW on another account.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, Workflow, TaskList, TaskCreate, TaskUpdate, AskUserQuestion
argument-hint: "[audit | handoff [next|next2|next3|next4|auto] [opus|fable] | ingest <bundle-dir>] — bare = full same-session recovery"
---

# /limit-recover — limit-interruption recovery, no partial-result acceptance

The ad-hoc "continue, we hit our limit, re-run partial results" prompt fails intermittently because
the model reconciles from its CONTEXT (which contains pre-kill narrative and looks plausible) instead
of from DISK, satisfices on the units it happens to remember, and smooths gaps into the conclusion.
This command replaces that with a deterministic audit → forced re-run → re-audit fixpoint. Scripts:
`~/.claude/scripts/limit-recover/` (`lr-audit.py`, `lr-transplant.sh`, `lr-handoff.sh`,
`lr-fire-resume.sh`, `lr-preseed-env.sh`). Artifacts: `~/.reso/limit-recover/<sid>/`. Invoking this
command IS the authorization to call the Workflow tool for resume/re-run of the session's own workflow runs.

**Autonomous resume is prompt-free at the SOURCE (no human in the loop).** `lr-fire-resume.sh` calls
`lr-preseed-env.sh <target-cfg> <worktree>` before spawning the TUI, which removes the two startup
blockers `expect` structurally CANNOT answer (both live OUTSIDE the PTY): (1) the iTerm2 GUI modal
*"A control sequence attempted to clear scrollback history. Allow this?"* — a sheet above the terminal
that froze every keystroke (the 2026-07-11 stranded-ingest bug) — suppressed globally + live via the
iTerm2 default `PreventEscapeSequenceFromClearingHistory=true`; (2) the *"Is this a project you trust?"*
folder-trust menu — pre-accepted in the target account's `.claude.json` (`hasTrustDialogAccepted`). The
fullscreen-renderer upsell + terminal-query gibberish stay handled by `lr-fire-resume.sh`'s `expect`
layer (both ARE in the PTY). The trust write is guarded by Claude's own `.claude.json.lock` (never clobbers
a concurrent same-account write; skips → expect fallback if the lock is busy), and lr-handoff.sh runs the
preseed BEFORE opening the pane so the iTerm2 pref lands seconds ahead of the resumed TUI. **One-time
machine setup (NOT per-resume):** grant osascript the "control iTerm2" Automation permission (macOS prompts
once; already granted here). Full detail + preconditions: `resume-sessions/REFERENCE.md § 4a`.

## Iron rules (bind every mode; quote back any you are about to break and STOP)

1. **Disk truth outranks conversation memory.** The unit inventory comes from `lr-audit.py`
   (journals, agent jsonls, run summaries, transcript), never from what you recall spawning.
   Compaction hides calls from context; disk still has them.
2. **Synthesis and conclusions may consume COMPLETE / COMPLETE_UNDELIVERED / COMPLETE_SALVAGED /
   SUPERSEDED units ONLY.** Every other verdict must be re-executed or surfaced as a named gap.
3. **null ≠ "the agent found nothing".** A schema'd agent that found nothing returns a valid
   object saying so. A null/dangling slot is absence-of-execution → re-run.
4. **Bridging is banned**: no "based on the available results", no proportional-confidence
   hedging over missing axes, no silently dropping an axis, no treating a TAINTED_COMPLETE
   run's final result as usable while its gap slots stand.
5. **Re-audit after every re-run wave** (same lr-audit command). Loop to fixpoint: gaps=0, or
   blocked → STOP-ASK / handoff. A verdict flips only on new un-fakeable evidence (journal
   result, jsonl terminus) — never on your confidence.
6. **Idempotent + owned**: append to `~/.reso/limit-recover/<sid>/ledger.jsonl` BEFORE each
   dispatch (`{ts, action, unit, note}`); respect the transplant lock (one recovery owner per
   session uuid). If the limit re-hits mid-recovery, the next invocation re-derives everything
   from ledger + disk.
7. **Never push / ship / deploy from a recovery.** Task-clean local commits are allowed; landing
   is the user's explicit call.

## Step 0 — ground truth (every mode, before any judgment)

```bash
mkdir -p ~/.reso/limit-recover/$CLAUDE_CODE_SESSION_ID
python3 ~/.claude/scripts/limit-recover/lr-audit.py \
  --json ~/.reso/limit-recover/$CLAUDE_CODE_SESSION_ID/audit-$(date -u +%H%M%S).json \
  --md   ~/.reso/limit-recover/$CLAUDE_CODE_SESSION_ID/audit-latest.md \
  --salvage-dir ~/.reso/limit-recover/$CLAUDE_CODE_SESSION_ID/salvage
~/.claude/hooks/session-continue.sh clear 2>/dev/null || true   # stale pre-limit auto-continue = ordering hazard
git branch --show-current    # pool/* → git switch -C recovered/<sid8> (refresher hard-resets pool branches)
```

Read the emitted audit (it prints; exit 0 = no gaps, 1 = gaps, 2 = artifacts missing → everything
is UNVERIFIABLE → report that and STOP-ASK). Then reconcile: every delegated call you remember or
see in context MUST appear in the audit; anything in one source but not the other is itself a
finding (say so). The audit also lists limit events with kind, absolute reset time (UTC), and the
model that was interrupted.

## Verdict → action (from the audit's gap ledger — execute, don't re-judge)

| Verdict | Meaning | Action |
|---|---|---|
| COMPLETE | journaled result / clean final turn, above floors | consume freely |
| SUPERSEDED | slot re-issued + completed under another agentId | none |
| COMPLETE_UNDELIVERED | finished on disk; result never reached the lead (lead died first) | **READ from disk — zero re-spend**: workflow → run-summary `.result`; subagent → final message in its jsonl |
| COMPLETE_SALVAGED | StructuredOutput validated in agent jsonl, never journaled | use the payload; cite provenance `(salvaged)` |
| VACUOUS_SUSPECT | mechanically complete, below signal floors | READ output vs its brief. Adversarial/refuter briefs must cite what they examined — a bare "no issues" is vacuous. Vacuous → re-run |
| NULL | killed at/near spawn (limit / 529 / api error) | re-run |
| PARTIAL | substantive work, no result | re-run; salvage text is seed-context only, never a substitute |
| INTERRUPTED | TaskStop / user interrupt | re-run unless salvaged payload exists |
| TAINTED_COMPLETE (run) | run "completed" over gap slots (e.g. all-null 529 storm still returns) | final result is CONTAMINATED until its gap slots resolve |
| UNVERIFIABLE | artifacts missing/contradictory | surface as a named gap — never infer |

## Mode: recover (default, no args)

1. **Still limited?** Map this config dir → account (`~/.claude`+`~/.claude-next`→next,
   `-secondary`→next2, `-tertiary`→next3, `-quaternary`→next4) and check live headroom:
   `~/bin/claude-accounts --json | jq '.[] | select(.acct=="<label>")'`. If `session_pct`/
   `weekly_pct` ≥ 100 (or the first re-run comes back with a genuine "You've hit your…" error):
   STOP and present — reset time (from the audit), wait cost, and the exact escape hatch
   `/limit-recover handoff auto`. Waiting vs switching accounts is the user's call; **only if the
   user already told you to continue autonomously** (e.g. a /goal), fire the handoff yourself.
   If ONLY `fable_pct` ≥ 100 (model-scoped): re-run fable-tagged slots on the house fallback
   `claude-opus-4-8` and mark each `(tier-fallback)` in the report.
2. **Zero-spend first**: consume every COMPLETE_UNDELIVERED / COMPLETE_SALVAGED unit from disk.
   Then VACUOUS_SUSPECT reviews. Only then paid re-runs.
3. **Workflow re-runs**: ledger-append, then `Workflow({scriptPath: <audit's scriptPath>,
   resumeFromRunId: <runId>, args: <original args from audit's lead.workflow_calls>})`. Journaled
   results replay free; dangling slots re-run (validated: nulls are never cached). If the original
   deaths were a same-second 529 burst across many slots, EDIT the script first to stagger stage-1
   launches (90s base + 20-30s/index — memory `reference-workflow-burst-529-stagger-launches`).
4. **Bare-subagent re-runs**: re-spawn with the ORIGINAL prompt from
   `salvage/subagents/<agentId>.json` (verbatim — do not paraphrase from memory).
5. **Re-audit** (rule 5). A slot STILL dangling after a resume means the script did not re-issue
   that call (changed conditional / `.filter(Boolean)` tail): hand-author a continuation script
   seeded with the salvaged COMPLETE results (`salvage/<runId>/slots.json`) that runs ONLY the
   missing slots, run it as a fresh Workflow, re-audit again.
6. **Teams**: if the audit lists team dirs / `refs/wip` checkpoints, surface them and point at
   `scripts/team/respawn-team.sh <team>` — do not silently re-implement teammate work.
7. **Report** (final message): per-unit table of actions taken (re-run / read-from-disk /
   salvaged / tier-fallback), re-spend estimate, and the closing line — either
   `RECOVERY COMPLETE — gaps: 0 (fixpoint)` or `RECOVERY PARTIAL — named gaps: …` with each gap's
   blocker. Never the second dressed as the first.

## Mode: audit

Step 0 + reconcile + present the audit and the recommended plan. No re-runs, no mutations
(read-only turn). Use before deciding wait-vs-handoff, or to inspect any session:
`lr-audit.py --config-dir <dir> --session <sid> --cwd <path>` works cross-account.

## Mode: handoff [next|next2|next3|next4|auto] [opus|fable]

Continue NOW on another account with zero loss (validated: transplanted sessions resume with full
conversational context; new turns land in the target account's store).

1. Run Step 0. **Commit in-scope WIP** (task-clean, explicit paths — never sweep unrelated files).
2. **Write `HANDOFF-CONTEXT.md`** to the bundle-to-be (temp file, passed via `--context`):
   the frozen scope/DoD verbatim, decisions made this session + why, the single next action,
   open questions (each marked STOP-ASK), hard constraints. This is the one artifact only you
   can write — the scripts capture everything else.
3. Fire:
   ```bash
   ~/.claude/scripts/limit-recover/lr-handoff.sh --target <arg-or-auto> --model <opus|fable> \
     --context /tmp/lr-context-$CLAUDE_CODE_SESSION_ID.md --launch
   ```
   This audits + salvages into a bundle, copies the transcript + session dir (workflow journals
   included) + task list into the target account under the SAME uuid, sha-verifies, writes the
   split-brain lock + source tombstone, and fires the resume in a **split pane to the RIGHT of
   the invoking pane** (⌘D-style; a new iTerm2 window only when no invoking pane exists or the
   split fails), auto-submitting `/limit-recover ingest <bundle>` with a **verified submit** —
   the fire script re-sends CR until the running-turn indicator ("esc to interrupt") appears,
   because a leading-`/` prompt's autocomplete menu can eat the first CR (composer submits on
   `\r` only; observed stranded 2026-07-11). `--print-only` writes
   `/tmp/lr-launch-<sid8>.sh` instead (manual fallback is always printed).
4. **This session is now DONE.** Emit the handoff report (target account, bundle path, gaps
   handed over). Do not dispatch further delegated work here — the target session owns recovery
   (split-brain rule). Suggest the user close/park this pane.

## Mode: ingest <bundle-dir>

You are the TARGET session (same uuid, new account). Trust nothing until verified:

1. Read `MANIFEST.json`. Verify ALL of: `$CLAUDE_CONFIG_DIR` == `target_cfg`;
   `$CLAUDE_CODE_SESSION_ID` == `sid`; the lock file exists and names this target;
   `shasum -a 256` of your live transcript's transplanted prefix is moot post-append — instead
   verify your transcript PATH sits under `target_cfg` and quote its first user message to confirm
   it is the expected session; current branch != `pool/*`; run
   `~/.claude/hooks/session-continue.sh clear`. Any check failing → STOP-ASK with the discrepancy.
2. Read `HANDOFF-CONTEXT.md` (scope is FROZEN there; if it says UNRECONSTRUCTED, ask before
   assuming) and `audit.md`.
3. Re-run Step 0 fresh in THIS location (artifacts moved with you). Then proceed exactly as
   **recover**. For workflow resumes, verify after the call that new `agent-*.jsonl` files
   appeared under the ORIGINAL runId dir in YOUR session dir; a fresh runId dir means the journal
   didn't carry — fall back to the salvage-seeded continuation script (bundle `salvage/` +
   `workflow-scripts/` hold everything needed).
4. Report per **recover** step 7, prefixed with the ingest verification results.

## Failure-mode guards (red-team derived — check when something looks off)

| Smell | Guard |
|---|---|
| Run says "completed", results look thin | TAINTED_COMPLETE: `.filter(Boolean)` swallows nulls by design — trust slot verdicts, not run status |
| Same uuid in two accounts both live | lock + tombstone; source stops delegating after handoff fires |
| Audit inventory smaller than memory | compaction hid calls from context, not from disk — reconcile explicitly |
| Reset time looks odd | audit parses "resets 5:30pm (America/Vancouver)" → absolute UTC; monthly-spend has none |
| "Server is temporarily limiting requests" | that is a 529, NOT your usage limit — re-run with stagger, don't wait for reset |
| Worktree files reverted underneath you | branch was `pool/*` — refresher reset it; recover via reflog, rename branch first |
| Agent output discusses limits/interrupts | detector requires the `isApiErrorMessage` envelope / structural markers — text alone is not evidence |
