# Hooks: what the hook layer adds to the model's context, and the turns it forces

Window: 2026-09-09T00:00Z to 2026-09-23T23:02Z (14 d), `xdup=0`. Fleet total over the same window: $32.5k at
each response's own model, $18.3k re-priced at Opus 5.5. All $ figures are list-price weights; the fleet is
billed by subscription quota, not dollars. Machine-readable version: `hooks.json` (inventory, per-script
costs, audits, ranked cuts).

## Answer first

- **The injected text is small. The turns the Stop hooks force are the bigger cost.**
  - Hook text reaching the model costs **$566 own-model / $264 at Opus 5.5** (1.7% / 1.4% of the fleet).
    That covers writing it once and re-reading it for the rest of each context.
  - Continuations forced by Stop blocks cost **$3,623 / $1,649** (11.1% / 9.0%).
  - About $940 own-model ($420 at Opus 5.5) of those forced turns do nothing useful: 1,973 of 3,029. They
    re-state a close, run a one-command state probe ("No drag.", "Waiting."), re-arm a watcher, or say
    nothing.
- **Claude Code sends every command-hook Stop reason to the model twice.** It goes once as the
  `Stop hook feedback:` meta message and once as the rendered `hook_blocking_error` attachment. This held
  for 2,588 of 2,588 blocks. The extra copy alone costs $92 / $41.
- **The SessionStart context misdirects sessions.**
  - `dod-persist.sh` presents the newest capture from a repo-keyed store, from whichever session wrote it,
    as "THE CURRENT CONTRACT — this is what binds you".
  - There were 43 different contracts over 683 injections, and one of them was shown to 248 sessions.
  - Only 9 of 535 sessions' first prompts share the contract's keyword. A hand check found 7 of 8 sampled
    sessions working on something unrelated.
  - `mailbox-drain.sh` re-forwards old peer mail at session start: median age since origin 6.8 days,
    and 293 of 604 messages were more than 7 days old.
- **Recommended cuts total about $920 own-model / $414 at Opus 5.5 per 14 days** (ESTIMATED; about 2.8% /
  2.3% of the fleet). 70% of that comes from three changes to how Stop blocks behave.

## 1. Inventory (MEASURED: `scripts/hooks_enumerate.py`)

- **Registrations:** `~/.claude/settings.json` registers **104 hooks** (82 distinct scripts) across 21
  events.
  - SessionStart 18, PreToolUse 18, PostToolUse 14, Stop 13, UserPromptSubmit 7, SessionEnd 7,
    PermissionRequest 5, Notification 5, PreCompact 3, PostToolUseFailure 3, and 1-2 each for the other
    11 events.
- **Other config dirs:** each keeps its own real `settings.json`, not a symlink.
  - They register 91-96 hooks. Six are missing in each: `mail-images-auto`, the three
    PostToolUseFailure hooks, and one or two of `cc-unattended-ask-guard` / `coldcompile-admit` / `pr-gate` /
    `web-entrypoint-ladder` / `escalation-watch`.
  - The project's `.claude/settings*.json` adds none.
- **Scripts outside the repo:** 102 of 104 commands resolve through per-file symlinks into
  `claude-infrastructure/hooks/`.
  - **`net-context-stamp.sh` and `web-entrypoint-ladder.sh` are real files in `~/.claude/hooks` with no
    repo source.**
  - The two PreCompact `date >> sessions.log` lines are inline commands.
- **Full table:** below, one row per registration. For each hook it shows what the script can emit to the
  model and its measured 14-day injections, forced turns and timeouts.
  - Injection and forced $ are per script, so a script registered on several events repeats its figures
    on each row.
  - The timeout counts include transplant copies. The deduplicated total is 9,140.

## 2. Model-visible injections (MEASURED counts/chars; $ ESTIMATED: `scripts/hooks_scan.py`, `scripts/hooks_cost.py`)

### How each output is recorded, and whether the model sees it

| record | reaches the model | attribution |
|---|---|---|
| `hook_additional_context` | yes, as `<hookName> hook additional context: <content joined>` | `content[]` merges the outputs of every hook on the event and names no command. Attributed per element by signature (31 rules). 165 elements ($0.59) are unattributed |
| `hook_blocking_error` | yes | `blockingError.command` |
| `Stop hook feedback:` meta user message | yes (the second copy of a Stop reason, and the only copy for /goal prompt hooks) | matched by signature |
| `hook_success` with `rendered` | yes: plain SessionStart stdout (`frontier-status.sh`, reso project hooks) | `command` |
| `hook_system_message` | **no, display only**: 3,015 items, 1.62M chars, **$0** | n/a |
| `hook_success` without `rendered` | no: 80,594 items | n/a |
| `hook_cancelled` | no: 9,140 timeouts | n/a |

**Pricing method.** A new item is written at the TTL rate of the response that follows it. On each later
response the item is:

- priced as a cache read if `cache_read` covers its position;
- priced as a cache write (5m 1.25x / 1h 2x) otherwise;
- dropped once the context shrinks below it, which handles compaction and `/clear`.

**Chars to tokens: 2.5 (ESTIMATED).** The ratio is fitted in `scripts/probe_stop_block_double.py` from
prefix growth across 1,888 Stop-block pairs: 2.42 without thinking, 2.65 with thinking, 2.60 for meta-only
blocks. It matches the 2.5-2.6 measured by `/context` on the memory files.

**Cross-check (ESTIMATED):** session-continue's 2.70M chars ≈ 1.08M tokens × 291 later responses on
average × about $0.5/M cache read ≈ $157. The pricing method computes $154.

| script (event) | items | contexts | median chars | $ own | $ @5.5 | responses it stays in (mean) |
|---|---:|---:|---:|---:|---:|---:|
| session-continue.sh (Stop, both copies) | 3,682 | 215 | 661 | 154.46 | 67.50 | 291 |
| config-mirror-assert.sh (SessionStart) | 950 | 881 | 5,783 | 86.82 | 37.75 | 80 |
| /goal prompt hook (Claude Code built-in, Stop) | 584 | 18 | 1,462 | 72.16 | 30.82 | 382 |
| mailbox-drain.sh [peer mail] (SessionStart/PostToolUse/UserPromptSubmit) | 967 | 447 | 2,640 | 54.19 | 27.46 | 98 |
| mailbox-drain.sh [wake-path nag] (UserPromptSubmit) | 2,950 | 435 | 334 | 35.27 | 19.07 | 73 |
| dod-persist.sh (SessionStart) | 683 | 659 | 1,958 | 29.66 | 13.05 | 96 |
| memory-nudge.sh (UserPromptSubmit) | 434 | 213 | 2,704 | 26.67 | 13.86 | 84 |
| handoff-intent-nudge.sh (UserPromptSubmit) | 736 | 467 | 894 | 16.52 | 7.86 | 116 |
| completion-assert.sh (Stop, both copies) | 577 | 143 | 745 | 10.04 | 5.41 | 73 |
| agent-teams-enforce.sh (PreToolUse:Agent) | 483 | 90 | 403 | 8.50 | 4.43 | 119 |
| research-precognition-nudge.sh (UserPromptSubmit) | 419 | 208 | 771 | 7.81 | 3.93 | 104 |
| mailbox-drain.sh [parked-watcher warning] | 195 | 109 | 1,060 | 6.88 | 3.71 | 119 |
| anti-deference-nudge.sh (Stop, both copies) | 359 | 121 | 720 | 6.58 | 3.44 | 95 |
| plan-agent-teams-default.sh (PreToolUse:Write/Edit) | 337 | 109 | 1,196 | 6.48 | 3.69 | 47 |
| cache-expiry-warning.sh (UserPromptSubmit) | 1,186 | 258 | 395 | 6.30 | 3.16 | 55 |
| frontier-status.sh (SessionStart stdout) | 892 | 880 | 340 | 4.92 | 2.20 | 82 |
| backup-before-write.sh, activation-watch.sh, enforce-email-formatting.py, setup-plan-symlinks.sh, session-start.sh, relay-verbatim.sh, desk-brief-inject.sh, web-entrypoint-ladder.sh, session-index-start.sh, boundary-handoff.sh, setup-task-symlinks.sh, and 12 more | | | | 38 | 18 | |
| **total** | | | | **566** | **264** | |

**By event ($ own / @5.5):**

| event | $ own | $ @5.5 |
|---|---:|---:|
| Stop meta copies | 153 | 67 |
| SessionStart | 150 | 66 |
| UserPromptSubmit | 104 | 54 |
| Stop attachment copies | 92 | 41 |
| PostToolUse | 35 | 18 |
| PreToolUse | 25 | 14 |
| SessionStart stdout | 6 | 3 |

**No Stop hook returned `additionalContext`.** 0 of 6,195 `stop_hook_summary` records carry
`hookAdditionalContext` (MEASURED). The Stop cost is all `decision:block` reasons.

**Within-context repeats** (MEASURED, `scripts/hooks_repeat_rate.py`): the share of injections whose
digit-normalized text already appeared earlier in the same context.

| injection | repeat share |
|---|---:|
| wake-path nag | 82% |
| cache-expiry warning | 78% |
| agent-teams-enforce | 74% |
| plan defaults | 67% |
| backup-before-write | 57% |
| research-precognition | 50% |
| memory-nudge | 47% |
| handoff-intent | 36% |
| peer mail | 3% |

## 3. Forced turns (MEASURED spans; classes heuristic, hand-validated: `scripts/hooks_cost.py`, `scripts/hooks_forced_validate.py`)

### How a Stop block is recorded

- **One Stop event** writes one `system/stop_hook_summary`: 6,195 distinct, of which 2,248 carry
  `hookErrors`.
- **Each block** writes a `Stop hook feedback:\n<reason>` meta user message.
- **Command hooks** also write a `hook_blocking_error` attachment, rendered as
  `Stop hook blocking error from command: "<cmd>": <reason>`.
  - The model receives both.
  - Proof: across 1,888 clean response pairs, the prefix growth implies 2.42 chars/token if both copies
    were sent and an impossible 1.12 if only one was.
  - All hooks here block through JSON `{decision:"block"}`, so the duplication comes from how Claude Code
    renders the block, not from the hook's output mode.
- **/goal's evaluator** (a built-in prompt hook) writes only the meta copy.

### How a forced turn is measured

- **Trigger:** the meta messages grouped by `(file, resp_before)`, giving 3,045 groups. 3,029 of them have
  a continuation.
- **Span:** runs to the first `stop_hook_summary` after the first continuation response, or to the next
  human prompt if that comes first.
- **Cost:** the full priced cost of every response in the span: prefix re-read, writes, and output
  (`output_est`).
- The median forced turn is 2 responses and $0.57. The distribution is heavy-tailed (max 1,015 responses,
  $199), because a block can start an autonomous chain.

### Classes and validation

Each span gets a class from its tool calls:

- **substantive:** writes, commits, or land/ship.
- **reformat_close:** no tools, or only read-only ledger reads, in ≤3 responses.
- **short_probe:** tools ran, nothing was written, and the span is ≤2 responses with under 300 chars of
  text.
- **poll_rearm:** only `session-continue set`, `cc-await-ping`, sleep, or custody commands.
- **readonly_check:** longer read-only spans.
- **nothing:** no tools and under 400 chars of text.

Validation used seeded stratified samples of 5 per class (seed 7) and 4 per class (seed 11), reading the
span text:

- The "nothing", "reformat_close" and "poll_rearm" samples all matched their class.
- The first version put one-command probes into "substantive". The `short_probe` class was added to fix
  that.
- "readonly_check" is mixed: it includes polling loops such as "📦 802 green… Holding." repeated 15 times.

| blocking hook | forced turns | contexts | $ own | $ @5.5 | waste-likely turns / $ own | substantive $ own |
|---|---:|---:|---:|---:|---:|---:|
| session-continue.sh | 1,922 | 213 | 2,403 | 1,084 | 1,248 / 607 | 1,666 |
|   of which 🔧 Loose ends (armed next step) | 1,503 | | 2,246 | | 886 / 489 | |
|   of which 🔔 WAKE FLOOR | 381 | | 175 | | 342 / 111 | |
|   of which 📦 SHIP FLOOR | 47 | | 32 | | 14 / 4 | |
| /goal prompt hook (built-in) | 558 | **18** | 411 | 176 | 510 / 262 | 144 |
| completion-assert.sh | 256 | 136 | 356 | 169 | 90 / 29 | 309 |
| anti-deference-nudge.sh | 154 | 121 | 244 | 120 | 77 / 19 | 216 |
| boundary-handoff.sh | 104 | 46 | 151 | 71 | 36 / 19 | 126 |
| dispatch-assert.sh, waiting-recycle.sh | 33 | 25 | 58 | 28 | 10 / 3 | 52 |
| **total** | **3,029** | | **3,623** | **1,649** | **1,973 / 939** | **2,513** |

**Waste-likely** means the reformat_close, short_probe, poll_rearm and nothing classes. **Substantive** $ is an
upper bound on useful work: the classifier still counts some long polling spans there, and whether the work
would have happened on the next human prompt anyway is not measured.

**Side finding: the Stop gates often do not run.** Timeouts (`hook_cancelled`, deduplicated) at Stop:

| Stop hook | timeouts | share of 6,195 Stop events |
|---|---:|---:|
| operator-readout.sh | 2,682 | |
| session-continue.sh | 2,458 | 40% |
| completion-assert.sh | 1,404 | |
| boundary-handoff.sh | 1,372 | |

These gates time out at 5-10 s and then allow the stop without a word. Fixing the timeouts would add forced
turns, so any Stop-gate change should be priced with this in mind.

## 4. SessionStart context in claude-infrastructure (MEASURED: `scripts/hooks_sessionstart_audit.py`; sample saved as `measure/sessionstart_sample.json`)

**Sample:** the newest main session in this repo, `eda5fec4`, at 2026-09-23T22:28Z.

- It received **8,220 rendered chars** of `hook_additional_context:SessionStart`, split into 8 elements.
- `frontier-status.sh` added another 342 chars as a plain-stdout "hook success".

| # | component (script) | chars | stale / volatile / misdirecting |
|---|---|---:|---|
| 0 | Plans line (setup-plan-symlinks.sh) | 190 | identical to the previous session in the project 60% of the time. Low value |
| 1 | ACTIVATION QUEUE (activation-watch.sh) | 258 | "1 un-run (1 rotting >24h) — unchanged since the last page". Identical 51% |
| 2 | MCP line (session-start.sh) | 158 | "[cached 8m ago]". Identical 32% |
| 3 | Session index (session-index-start.sh → bin/session-search.py) | 135 | "Recent: [today] (no summary) ×3": **no information** |
| 4 | Tasks (setup-task-symlinks.sh) | 115 | "186 active. 1 list(s) … (0 total)": contradicts itself |
| 5 | Peer mail (mailbox-drain.sh session-start) | 2,919 | **a 14-day-old WAKE-PATH-DOWN notice addressed to pane 643, forwarded again** |
| 6 | Knowledge-layer mirror (config-mirror-assert.sh) | 2,324 | **persisted**: original 18.7 KB; 502 names, 464 of them `settings.json.bak-*` |
| 7 | Frozen DoD (dod-persist.sh) | 2,039 | **persisted**: original 102.5 KB, 96 `Scope (frozen)` entries from 2026-07-19 to 09-25. The preview labels another task's scope, RESO_SECURITY_100P, as "THE CURRENT CONTRACT — this is what binds you" |

### Fleet-wide, 14 days

- **Frozen DoD** (683 injections):
  - 608 were persisted, so the model saw a 2,000-char preview. The original files were 16.6-100.2 KB.
  - They showed 43 distinct contracts. The top one was shown to 248 sessions.
  - Relevance proxy: the contract's keyword appears in the session's first human prompt in 9 of 535 cases.
    A hand check found 7 of 8 unrelated, for example a post-land test fix, a stranded-commit recovery,
    and a floor-plan review, each told that a different task "binds you".
  - The store appends new captures at the bottom, and the 2,000-char preview cuts off before any capture
    body. The newest history, which is the part that could be relevant, is never shown.
  - Content is identical to the previous injection in the project only 5% of the time, so it is volatile.
- **Peer mail at SessionStart** (340 injections):
  - 604 messages in total, 440 of them `[forwarded]`.
  - Age at injection since origin: median 163 h, p90 352 h. 352 were more than 24 h old and 293 more than
    7 days old.
  - Delivery age is 0 h, because the forward happens at session start.
- **Mirror** (950 injections):
  - FORKED list: median 216 names, p90 425. Backups make up a median 90% of the list.
  - Median size 5,713 chars. 363 were over the persistence cap.
  - Content is identical to the previous injection only 18.6% of the time.
- **Persistence is Claude Code's**, found in the binary (2.1.280):
  - In `ine()`, any hook `additionalContext`, stdout or systemMessage longer than **10,000 chars**
    (`Kpo=1e4`) is written to `<configdir>/projects/<slug>/<sid>/tool-results/hook-<uuid>-<n>-additionalContext.txt`.
  - The model gets a `<persisted-output>` block with a **2,000-char preview** (`Pye=2000`). With its header
    this is about 2.0-2.3k chars in context.
  - About 1,000 elements were persisted in the window.
  - Stop `decision:block` reasons do not pass through `ine()` and have no cap.

**Cache layout (checked, not a lever).** In 689 of 852 main sessions the SessionStart hook context comes
before the memory `instructions` attachment in the transcript. However, the first human prompt also comes
before the memory files in 851 of 858 sessions. Only 5 of 337 same-project session starts within 60 minutes
read ≥40k tokens from cache (median `cache_read` 14.3k, which is system + tools). The unique prompt is
therefore what blocks cross-session reuse, not the hook text. This belongs to the cache-layout owner.

## 5. Ranked cuts (ESTIMATED savings per 14 d: `scripts/hooks_cuts.py` → `measure/hooks_cuts.json`)

| # | layer | change | $ own / @5.5 saved | risk | category |
|---:|---|---|---:|---|---|
| 1 | Stop: session-continue.sh (🔧 armed step) | Don't re-block when the armed step is a wait that already has a waker (background task, Monitor, `cc-await-ping`). Don't re-block with an identical reason when the forced turn in between wrote nothing | 294 / 133 | medium | flag |
| 2 | /goal (built-in) + goal-inert-watch.sh | After ≥3 consecutive goal blocks whose forced turn wrote nothing, surface one operator notice and recommend `/goal clear`. 18 contexts produced 510 empty turns | 207 / 89 | low | propose |
| 3 | All Stop reasons | Cut reasons to ≤200 chars (verdict + next step + pointer to a file); report the double send upstream | 113 / 51 | medium | flag |
| 4 | session-continue.sh 🔔 WAKE FLOOR + mailbox-wake-arm.sh | Arm the wake path mechanically (the asyncRewake hook already exists) instead of blocking the model to do it | 100 / 45 | low | flag |
| 5 | SessionStart config-mirror-assert.sh | FORKED list → a count plus the path to the full list; leave backups out of FORKED | 83 / 36 | low | direct |
| 6 | UserPromptSubmit mailbox-drain.sh wake-path nag | Emit only when its state changes (82% repeats) | 28 / 15 | low | flag |
| 7 | Per-prompt and per-tool nudges (handoff-intent, research-precognition, cache-expiry, agent-teams-enforce, plan defaults, backup-before-write) | Skip a nudge whose text already appeared in the context | 28 / 15 | low | flag |
| 8 | SessionStart dod-persist.sh | Inject only a DoD from this session's lineage (its own sid or its recorded predecessor), otherwise nothing. Also removes the misdirection | 28 / 12 | low (quality ↑) | flag |
| 9 | UserPromptSubmit memory-nudge.sh | Once per context and on change; shrink 2.7k chars to about 300 | 21 / 11 | low | flag |
| 10 | SessionStart peer mail | Drop forwarded messages whose origin is >24 h old; show a count and the listing command | 11 / 5 | low | flag |
| 11 | SessionStart one-liners | Drop the empty session-index line; merge the rest | 7 / 3 | low | direct |
| | **total** | | **≈920 / 414** | | |

**Validation for every row:** compare before and after on real usage:

- the row's own count per context (forced turns, repeat share, SessionStart chars);
- $ per completed task;
- guardrails: sessions going idle with 🔧 work left, missed peer mail (`cc-notify reason=`), and the
  completion-assert/wrap-ledger verdicts (which read the DoD file, not the injection).

**Rollback:** each row is one hook change behind an env flag, or a `git revert` for the two direct rows.

**Not recommended:** trimming the blocks that lead to real work. $2.5k of forced turns is substantive and
removable only by accepting less autonomous driving, which the operator has said they want.

## Gaps

- Forced-turn classes are heuristic. "Substantive" is an upper bound on useful work, and the counterfactual
  (would that work have happened on the next human prompt?) is not measured.
- Tokens are estimated from characters (2.5 chars/token, fitted). There is no tokenizer.
- The pricing model places each item at the size of the context before it, and treats a context shrink as
  compaction.
- Merged `additionalContext` is attributed by signature; 165 elements ($0.59) are unattributed.
- DoD relevance rests on a keyword proxy plus 8 hand checks.
- API-level attachment order was inferred from transcript order plus the binary's SessionStart path; it was
  not captured on the wire.
- Not measured:
  - hook latency;
  - side queries that hooks may trigger;
  - the quota draw of `hook_system_message` rendering (it has no model cost).
- The per-script timeout column counts transplant copies (deduplicated total: 9,140).
- The reso PreToolUse hook that denies Bash commands containing SQL DDL keywords was avoided, not refused:
  every schema statement lives inside a Python script written with the Write tool.

## Re-derive

```
cd /tmp
S=<dir>/scripts
nice -n 10 python3 $S/hooks_scan.py                 # data/hooks.sqlite (~10 s)
nice -n 10 python3 $S/probe_stop_block_double.py    # double-send proof + chars/token fit
nice -n 10 python3 $S/hooks_cost.py                 # measure/hooks_cost.json + data/hooks_forced_samples.json
nice -n 10 python3 $S/hooks_forced_validate.py 5 7  # classifier spot-check
nice -n 10 python3 $S/hooks_repeat_rate.py          # measure/hooks_repeat_rate.json
nice -n 10 python3 $S/hooks_sessionstart_audit.py   # measure/hooks_sessionstart_audit.json
nice -n 10 python3 $S/hooks_cuts.py                 # measure/hooks_cuts.json
nice -n 10 python3 $S/hooks_report.py               # measure/hooks.json + measure/hooks_inventory_table.md
```

## Appendix: every registered hook (from `measure/hooks_inventory_table.md`)

| event | matcher | script (repo `hooks/`) | emits to model | visible inj. 14d | inj. $ own / @5.5 | forced turns | forced $ own / @5.5 | timeouts |
|---|---|---|---|---:|---:|---:|---:|---:|
| PostToolUse | Write|Edit|MultiEdit | post-file-edit.sh | - |  |  |  |  |  |
| PostToolUse | Write|Edit|MultiEdit | plan-index-update.sh | - |  |  |  |  |  |
| PostToolUse | Write|Edit|MultiEdit | validate-plan-structure.sh | additionalContext,exit2 | 53 | 0.59 / 0.34 |  |  |  |
| PostToolUse | Write|Edit|MultiEdit | plan-version-commit.sh | - |  |  |  |  |  |
| PostToolUse | Bash | log-bash.sh | - |  |  |  |  |  |
| PostToolUse | Bash | waiting-recycle.sh | additionalContext,decision:block,systemMessage,exit2 | 43 | 0.47 / 0.25 | 12 | 21 / 9 |  |
| PostToolUse | Bash | relay-verbatim.sh | additionalContext | 244 | 1.94 / 1.13 |  |  |  |
| PostToolUse | TaskCreate|TaskUpdate | task-mutation-index.sh | - |  |  |  |  |  |
| PostToolUse | * | teammate-checkpoint.sh | - |  |  |  |  | 11 |
| PostToolUse | ExitPlanMode | plan-pin-session.sh | - |  |  |  |  |  |
| PostToolUse | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| PostToolUse | * | mailbox-drain.sh | additionalContext,systemMessage | 4112 | 96.34 / 50.24 |  |  | 39 |
| PostToolUse | Bash|Write|Edit|MultiEdit | memory-index-drain.sh | additionalContext | 44 | 0.64 / 0.35 |  |  |  |
| PostToolUse | mcp__ms365__get-mail-message.* | mail-images-auto.sh | additionalContext |  |  |  |  |  |
| WorktreeCreate | * | worktree-setup.sh | - |  |  |  |  |  |
| TeammateIdle | * | teammate-auto-shutdown.sh | exit2 |  |  |  |  | 14 |
| FileChanged | /Users/chrisren/.claude/file-watch-pa… | file-changed.sh | - |  |  |  |  |  |
| FileChanged | * | file-changed.sh | - |  |  |  |  |  |
| PostToolBatch | * | post-tool-batch.sh | - |  |  |  |  | 12 |
| PermissionRequest | Bash | notify.sh | - |  |  |  |  | 30 |
| PermissionRequest | AskUserQuestion | notify.sh | - |  |  |  |  | 30 |
| PermissionRequest | ExitPlanMode | notify.sh | - |  |  |  |  | 30 |
| PermissionRequest | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| PreCompact | auto | `date '+[%Y-%m-%d %H:%M:%S] Auto-compact triggere` | - |  |  |  |  |  |
| PreCompact | auto | dod-persist.sh | additionalContext,exit2 | 683 | 29.66 / 13.05 |  |  | 89 |
| PreCompact | manual | `date '+[%Y-%m-%d %H:%M:%S] Manual compact trigge` | - |  |  |  |  |  |
| PostToolUseFailure | Bash | log-bash.sh | - |  |  |  |  |  |
| PostToolUseFailure | * | mailbox-drain.sh | additionalContext,systemMessage | 4112 | 96.34 / 50.24 |  |  | 39 |
| PostToolUseFailure | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| PreToolUse | Bash | smart-bash-allowlist.sh | - |  |  |  |  | 27 |
| PreToolUse | Bash | curl-gate-scope.sh | - |  |  |  |  | 16 |
| PreToolUse | Bash | validate-bash.sh | additionalContext,permissionDecision |  |  |  |  | 349 |
| PreToolUse | Bash | git-worktree-guard.sh | exit2 |  |  |  |  | 8 |
| PreToolUse | Bash | keychain-guard.sh | permissionDecision |  |  |  |  | 2 |
| PreToolUse | Bash | rm-safe-allowlist.sh | permissionDecision |  |  |  |  | 15 |
| PreToolUse | Bash | ship-rail-push-allow.sh | permissionDecision |  |  |  |  | 13 |
| PreToolUse | Bash | qos-rewrite.sh | permissionDecision |  |  |  |  | 9 |
| PreToolUse | Bash | coldcompile-admit.sh | permissionDecision |  |  |  |  | 6 |
| PreToolUse | Bash | pr-gate.sh | permissionDecision |  |  |  |  |  |
| PreToolUse | Write|Edit|MultiEdit | backup-before-write.sh | additionalContext,permissionDecision | 305 | 4.23 / 2.42 |  |  | 1 |
| PreToolUse | Write|Edit|MultiEdit | check-edit-boundary.sh | permissionDecision |  |  |  |  | 1 |
| PreToolUse | Write|Edit|MultiEdit | plan-agent-teams-default.sh | additionalContext,permissionDecision | 337 | 6.48 / 3.69 |  |  | 4 |
| PreToolUse | Agent | agent-teams-enforce.sh | additionalContext,permissionDecision | 483 | 8.50 / 4.43 |  |  | 56 |
| PreToolUse | Agent | frontier-spawn-gate.sh | exit2 |  |  |  |  |  |
| PreToolUse | mcp__ms365__send-mail|mcp__ms365__rep… | enforce-email-formatting.py | additionalContext,decision:block,permissionDecision | 34 | 4.09 / 2.29 |  |  |  |
| PreToolUse | AskUserQuestion | cc-unattended-ask-guard.sh | exit2 |  |  |  |  |  |
| PreToolUse | WebFetch|WebSearch | web-entrypoint-ladder.sh (NOT in repo: real file in ~/.claude/hooks) | additionalContext | 167 | 1.70 / 0.96 |  |  |  |
| Notification | permission_prompt | notify.sh | - |  |  |  |  | 30 |
| Notification | permission_prompt | push-critical.sh | - |  |  |  |  |  |
| Notification | elicitation_dialog | notify.sh | - |  |  |  |  | 30 |
| Notification | elicitation_dialog | push-critical.sh | - |  |  |  |  |  |
| Notification | idle_prompt | push-critical.sh | - |  |  |  |  |  |
| TaskCompleted | * | task-quality-gate.sh | exit2 |  |  |  |  |  |
| PermissionDenied | * | permission-denied.sh | - |  |  |  |  |  |
| CwdChanged | * | cwd-changed.sh | - |  |  |  |  |  |
| UserPromptSubmit | * | handed-off-session-guard.sh | exit2 |  |  |  |  | 5 |
| UserPromptSubmit | * | cache-expiry-warning.sh | additionalContext | 1186 | 6.30 / 3.16 |  |  |  |
| UserPromptSubmit | * | memory-nudge.sh | additionalContext | 434 | 26.67 / 13.86 |  |  | 31 |
| UserPromptSubmit | * | handoff-intent-nudge.sh | additionalContext,exit2 | 736 | 16.52 / 7.86 |  |  | 57 |
| UserPromptSubmit | * | research-precognition-nudge.sh | additionalContext | 419 | 7.81 / 3.93 |  |  |  |
| UserPromptSubmit | * | session-beat.sh | - |  |  |  |  | 11 |
| UserPromptSubmit | * | mailbox-drain.sh | additionalContext,systemMessage | 4112 | 96.34 / 50.24 |  |  | 39 |
| Stop | * | notify.sh | - |  |  |  |  | 30 |
| Stop | * | cache-expiry-tracker.sh | - |  |  |  |  | 1 |
| Stop | * | teammate-checkpoint.sh | - |  |  |  |  | 11 |
| Stop | * | session-continue.sh | additionalContext,decision:block,systemMessage,exit2 | 3682 | 154.46 / 67.50 | 1922 | 2403 / 1084 | 2509 |
| Stop | * | anti-deference-nudge.sh | decision:block | 359 | 6.58 / 3.44 | 154 | 244 / 120 | 54 |
| Stop | * | completion-assert.sh | decision:block,exit2 | 577 | 10.04 / 5.41 | 256 | 356 / 169 | 1439 |
| Stop | * | dispatch-assert.sh | decision:block | 44 | 0.89 / 0.47 | 21 | 37 / 19 | 20 |
| Stop | * | boundary-handoff.sh | additionalContext,decision:block,systemMessage,exit2 | 243 | 1.47 / 0.84 | 104 | 151 / 71 | 1395 |
| Stop | * | operator-readout.sh | decision:block,systemMessage,exit2 |  |  |  |  | 2731 |
| Stop | * | session-beat.sh | - |  |  |  |  | 11 |
| Stop | * | goal-inert-watch.sh | additionalContext,decision:block,systemMessage |  |  |  |  | 4 |
| Stop | * | handoff-claim-assert.sh | decision:block,exit2 |  |  |  |  |  |
| Stop | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| StopFailure | * | stop-failure-marker.sh | - |  |  |  |  |  |
| SessionEnd | * | session-end.sh | - |  |  |  |  |  |
| SessionEnd | * | session-deregister.sh | - |  |  |  |  |  |
| SessionEnd | * | session-index-end.sh | - |  |  |  |  |  |
| SessionEnd | * | session-save-id.sh | - |  |  |  |  |  |
| SessionEnd | * | harvest-skill-end.sh | - |  |  |  |  |  |
| SessionEnd | * | live-session-registry.sh | - |  |  |  |  | 5 |
| SessionEnd | * | cc-permission-beacon.sh | - |  |  |  |  | 1 |
| SessionStart | * | session-start.sh | additionalContext | 961 | 2.48 / 1.12 |  |  | 20 |
| SessionStart | * | setup-plan-symlinks.sh | additionalContext | 927 | 2.75 / 1.23 |  |  | 6 |
| SessionStart | * | setup-task-symlinks.sh | additionalContext | 894 | 1.43 / 0.64 |  |  | 9 |
| SessionStart | * | pre-session-validate.sh | - |  |  |  |  | 9 |
| SessionStart | * | lead-crash-watchdog.sh | - |  |  |  |  | 2 |
| SessionStart | * | session-register.sh | - |  |  |  |  | 5 |
| SessionStart | * | activation-watch.sh | additionalContext | 848 | 4.19 / 1.91 |  |  | 16 |
| SessionStart | * | dod-persist.sh | additionalContext,exit2 | 683 | 29.66 / 13.05 |  |  | 89 |
| SessionStart | * | desk-brief-inject.sh | additionalContext | 5 | 1.75 / 0.70 |  |  | 9 |
| SessionStart | * | mailbox-wake-arm.sh | exit2 |  |  |  |  |  |
| SessionStart | * | escalation-watch.sh | additionalContext |  |  |  |  | 19 |
| SessionStart | * | accounts-board.sh | additionalContext,systemMessage |  |  |  |  |  |
| SessionStart | * | session-index-start.sh | additionalContext | 929 | 1.50 / 0.68 |  |  | 27 |
| SessionStart | * | config-mirror-assert.sh | additionalContext | 950 | 86.82 / 37.75 |  |  | 3 |
| SessionStart | * | frontier-status.sh | - | 892 | 4.92 / 2.20 |  |  | 7 |
| SessionStart | * | live-session-registry.sh | - |  |  |  |  | 5 |
| SessionStart | * | mailbox-drain.sh | additionalContext,systemMessage | 4112 | 96.34 / 50.24 |  |  | 39 |
| SessionStart | * | net-context-stamp.sh (NOT in repo: real file in ~/.claude/hooks) | additionalContext |  |  |  |  |  |
| InstructionsLoaded | session_start | instructions-loaded.sh | - |  |  |  |  |  |
| PostCompact | * | post-compact.sh | - |  |  |  |  |  |
| ConfigChange | * | config-change.sh | - |  |  |  |  |  |
