# LEAD-NOTES — independent measurements by the lead session, for the synthesis

Lead session `b418b97a` (Fable 5.1 @ max, pane 615, `.claude-secondary`), 2026-09-08 21:20–22:40Z. These are
measurements the lead ran itself, outside the twelve axes. Where they disagree with an axis, the
disagreement is stated, not resolved — the skeptic for that axis and the synthesis decide.

## 1. Stop-hook wall time vs transcript size (synthetic Stop payload, load 16–22 on 10 cores)

| hook (registered timeout) | 2 MB | 24 MB | 69 MB |
|---|---|---|---|
| anti-deference-nudge (5 s) | 0.14 s | 0.24 s | 0.54 s |
| completion-assert (5 s) | 0.13 s | 0.37 s | 4.14 s |
| dispatch-assert (10 s) | 0.30 s | 0.66 s | 1.39 s |
| session-continue (5 s) | 2.46 s | 3.51 s | 4.80 s |
| goal-inert-watch (5 s) | 0.22 s | 0.33 s | 0.87 s |
| operator-readout (10 s) | 5.86 s* | 3.61 s | 0.71 s |

\* the 5.86 s run was the lead's own live session, whose operator pile renders 253 rows; the other two
were foreign transcripts with no pile. **Consistent with A01's finding that the transcript is not the
binding variable** — but `completion-assert` and `session-continue` DO climb with size at the top end.

## 2. `scripts/wrap-ledger.sh --machine` in the SHARED checkout `~/Development/claude-infrastructure`

- Without `WRAP_TRANSCRIPT` (no session attribution terms), at **load average 152**: 1.84 s, 1.63 s.
  `dod_lineage_ancestors` alone for this toplevel: 0.13 s (3 ancestors, 445-row lineage.tsv).
- **This disagrees with A01's 14.3 s for the same repo.** Possible reconciliations, none verified by the
  lead: (a) A01 timed with `WRAP_TRANSCRIPT` set, which enables the session-attribution terms
  (`session_writes_paths` streams the transcript with jq); (b) A01's runs coincided with a load spike
  (the box hit load 152–173 during W0); (c) the lineage walk's cost depends on the toplevel's ancestor
  count, and the shared checkout has only 3. The follow-up timing WITH `WRAP_TRANSCRIPT` attached is in
  § 2a below when it lands; the A01 skeptic should re-run A01's exact command.

## 3. Coverage of the Stop chain, today (14 h window, four roots, main-chain transcripts only)

- All five config dirs register the identical 12-hook Stop chain (none missing any of the seven
  enforcement hooks). Registration parity is NOT the gap.
- 66 sessions produced 738 closes; 17 sessions with 127 closes wrote ZERO `anti-deference-nudge` IDL
  records; **104 of those 127 closes ran on binary 2.1.220** (4 live `.claude-220` processes, 4–13 days
  old; backlog `76c714390f4d`). Per account: primary 176 closes / 169 records, secondary 136 / 32,
  tertiary 200 / 127, quaternary 222 / 175. The residual on 2.1.260 is 23 closes, mostly 1–2-close
  probe sessions.

## 4. Task tools (Shared Task List)

- Binary `pM()` @163543938: enabled iff not in the model table, OR `CLAUDE_CODE_ENABLE_TODO_TOOLS===true`,
  OR remote flag `tengu_rosy_wren`. Changelog text in the binary: "no longer available on Opus 4.8,
  Sonnet 5, Fable 5, Mythos 5, and newer models; set `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` to bring them back".
- **Concurrency probe (22:12Z):** two simultaneous `claude -p` sessions, `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`,
  same `CLAUDE_CODE_TASK_LIST_ID`, three `TaskCreate` each → ids 1–6, six distinct subjects (A: 2,5,6;
  B: 1,3,4), nothing lost or overwritten. The allocator is atomic across processes. Probe list removed.
- A model asked to "list your tools" under the flag did NOT name the Task tools (they are deferred);
  A03's schema-level A/B is the right instrument. Backlog `ebe84950e98a` closed with this evidence.
- The lead wrote items 198–207 straight into `~/.claude-secondary/tasks/claude-infrastructure-main/`
  (format copied from an existing item; summary regenerated with `hooks/lib/task-helpers.sh`).

## 5. Headless `-p` sessions

- Default env, `.claude-secondary`: tools = Agent, Bash, Edit, ListAgents, Read, ReportFindings,
  ScheduleWakeup, Skill, ToolSearch, **Workflow**, Write. Dynamic Workflows ARE available headless
  (A06's open question).
- Side-defect: a `-p` child launched from a pane inherits `KITTY_WINDOW_ID`/`ITERM_SESSION_ID`; its own
  hooks armed and then SIGTERM'd a `cc-await-ping` keyed on the PARENT pane (615) and paged the desk with
  `WAKE-PATH-DOWN` naming the `-p` command as the sender. Probes should run with
  `env -u KITTY_WINDOW_ID -u ITERM_SESSION_ID`; the hooks should refuse pane identity under `-p`.

## 6. `ENABLE_STOP_REVIEW`

- Set to `"0"` in the `env` block of every account's `settings.json`; first appears in
  `settings.json.bak-0005-20260810012050`; **no occurrence of `STOP_REVIEW` / `stopReview` / "stop review"
  anywhere in the 2.1.260 binary** (python byte search over the 198 MB file). It is a dead setting.
  `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` does exist ("check stop_hook_active … Set CLAUDE_CODE_STOP_HOOK_BLOCK_CAP
  to raise this limit").

## 7. IDL window

- `~/.claude/autonomy/idl.jsonl` holds only records from 2026-09-08 08:22Z; any "30-day" IDL census is a
  ~14-hour census. Corpus-derived numbers (transcripts) are the 30-day instrument.

### 2a. Follow-up: `wrap-ledger.sh --machine` WITH `WRAP_TRANSCRIPT` attached (shared checkout, load 102–152)

| transcript | size | wall | note |
|---|---|---|---|
| the lead's own (`b418b97a`) | 2.7 MB | **2.06 s** | uncached compute — the session-attribution terms ran |
| `0516875a` (foreign) | 24 MB | 0.06 s | memo HIT — A01 had already computed it |
| `432f864d` (foreign) | 69 MB | 0.06 s | memo HIT |

So on this box, at load ~100–150, a fresh ledger for a real session costs ~2 s in the shared checkout.
The lead could not reproduce A01's 14.3 s. Two readings remain compatible with both measurements:
(a) A01's runs landed inside a load spike (the box spent W0 at load 100–173; a 2 s script can take
10 s+ there), which would make the 4,839 kills a **load-regime** problem — Stop budgets of 5 s / 10 s
are simply too tight for a box that routinely runs 50 sessions — rather than an intrinsic-cost
problem; (b) a cwd-dependent path the lead's cwd does not exercise. Either way, A01's *kill counts*
come from `hook_cancelled` attachments in the transcripts and stand on their own; only the *cause*
attribution is in dispute. The remedies are not exclusive: read `.last_assistant_message` from the Stop
payload, make the lineage walk in-memory, AND size the timeouts to the measured load regime.
