---
name: limit-recover
description: Recover perfectly from ANY interruption to delegated work — disk-truth audit of every Dynamic Workflow slot, subagent, task, AND Agent-Team assignee session; re-run everything not provably COMPLETE (accepting partial results is banned); or continue with zero loss on another of the 4 accounts via validated transcript transplant + salvage bundle. Use when a session was killed by "You've hit your session/weekly limit", when teammates died mid-wave ("Teammate @x failed - You've hit your monthly spend limit"), when resuming after a limit ("continue, we hit our limit"), when workflow/subagent results came back null/partial/empty, or when the reset is too far away and work should continue NOW on another account. ALSO use when an account died on its LOGIN CLIFF rather than on quota — `invalid_grant` on every refresh, `auth: logged-out` / `token-invalid`, "Not logged in · Please run /login" — because the recovery is the same transplant and the alternative is losing the work (there is NO reset to wait for; see § A login cliff is not a quota limit). AND USE IT FOR EVERY NON-QUOTA INTERRUPTION TOO, because the audit engine was never limit-specific — only this description was: a network drop or reconnect ("reconnected to the internet, continue", "wifi came back", "API Error: Can't reach the API server", ENOTFOUND/ECONNRESET/socket hang up), a stalled workflow or agent ("agent stalled on all N attempts", "no progress for 180000ms", "stream watchdog did not recover"), a background task that came back failed/killed/stopped, a session that was RESUMED after a crash/reboot//exit and needs to know what its delegations were doing when the process died. Those select a different recovery MODE (resume-in-place or stall, never a transplant — the account is fine), not a different engine; see /recover for the class-named front door.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent, Workflow, TaskList, TaskCreate, TaskUpdate, AskUserQuestion
argument-hint: "[<ref> | audit | handoff [next|next2|next3|next4|auto] [opus|fable] [--spawn] | fleet [--locate|--recover|--enqueue|--duplicates|--retire-husks] | ingest <bundle-dir>] — <ref> (a pane id, a sid8) is the fast path: cc-lr recover <ref>, then END THE TURN; bare = full same-session recovery; handoff is IN-PLACE by default"
---

# /limit-recover — limit-interruption recovery, no partial-result acceptance

The ad-hoc "continue, we hit our limit, re-run partial results" prompt fails intermittently because
the model reconciles from its CONTEXT (which contains pre-kill narrative and looks plausible) instead
of from DISK, satisfices on the units it happens to remember, and smooths gaps into the conclusion.
This command replaces that with a deterministic audit → forced re-run → re-audit fixpoint. Scripts:
`~/.claude/scripts/limit-recover/` (`lr-audit.py`, `lr-transplant.sh`, `lr-handoff.sh`,
`lr-fire-resume.sh`, `lr-preseed-env.sh`, `lr-select.py`).
**`lr-select.py` is the session-resume consolidation gate** (one session per worktree + a total
ceiling; incident 2026-07-21) used by `lr-reset-poller.sh`, `boot-resume.sh` and the
`resume-sessions` skill. **This command does not need it**: `handoff` transplants exactly ONE lead
session, and the re-runs below are workflow slots / subagents / teammates, not session resumes. If
you ever add a path here that resumes MULTIPLE sessions, it must route through `lr-select.py`. Artifacts: `~/.reso/limit-recover/<sid>/`. Invoking this
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

## A login cliff is not a quota limit — and it changes exactly one branch of the decision tree

Added 2026-07-30 (ACCOUNT_ROUTING_V2, row 7). Every trigger above used to name a QUOTA event, so a
session killed by its account's **login cliff** matched none of them — while this command's transplant
machinery is precisely the right recovery for it. The capability existed and the failure that needed
it could not reach it.

**Recognise it, and do not mistake it for a cap.** `invalid_grant` on every refresh · `auth:
logged-out` or `token-invalid` in `claude-accounts --json` · a launcher greeting with "Not logged in ·
Please run /login". Confirm from the credential store, not the symptom:
`claude-accounts --relogin-status` (exit 2 = ESCALATED/overdue). A REAL cap returns HTTP 200 with
percent ≈ 100; an auth death is not a percentage at all.

**The one branch that differs — `wait for the reset` DOES NOT EXIST.** A 5-hour / weekly / Fable cap
has a `resets_at` and waiting is a legitimate option. A login cliff has no reset: past
`refreshTokenExpiresAt` every refresh grant is refused **by construction**, and only an INTERACTIVE
login recovers the account. Measured: six successful refreshes did not move next3's wall, it died
anyway, and 24 automated re-attempts inside 7.7 h all failed — the account stayed down **93.5 hours**
until a human logged in. So on a cliff:

1. **Never wait, and never retry the grant.** Retrying is the 24-attempt failure above. There is
   nothing to poll.
2. **Transplant is the ONLY zero-loss path** — `handoff [next|next2|next3|next4|auto]`, exactly as
   for a cap. The 4 accounts are isolated, so a cliff on one says nothing about the others; pick the
   target from `claude-accounts --rank general`, which now DEPRIORITIZES an account inside its own
   cliff window so `auto` will not hand you a second account that is about to die.
3. **Repair runs in PARALLEL, not first** — `cc-relogin <acct>` (or `/relogin`). It needs the account
   at `k == 0`, so it cannot run while the work is still there; move the work, then repair. Landing
   the repair before the transplant inverts the dependency and strands the work for the whole repair.
4. **If it is the LAST healthy account**, this is a genuine STOP-ASK: the operator must perform an
   interactive `/login`. Surface the exact command and the deadline
   (`claude-accounts --relogin-status`), and salvage a bundle so nothing is lost while you wait.

## The fast path — `cc-lr recover <ref>`, then END THE TURN

**`/limit-recover <ref>` is ONE command and one turn.** `<ref>` is whatever you have in hand — a
pane id (`117`, `⌗117`, `#117`) or a sid8 (`cb227486`):

```bash
cc-lr recover <ref>            # add --target next3 to pin the account; --source-pane P if you have it
```

Print its three lines verbatim and **END THE TURN**. Do not poll, do not confirm, do not re-census
to check the pane id you were handed. The verdict comes back as MAIL — a `cc-notify` line carrying
`verdict=RECOVERED|PARTIAL|PARKED|FAILED`, its note and the evidence dir — which `mailbox-drain`
delivers at your next turn boundary like any other message.

Measured 2026-09-19 (`docs/research/lr100p-2026-09-19/research/U11-today-run-audit.md` §2):
recovering five sessions cost **98.7 minutes**, of which **24.4 lead turn-minutes were foreground
`until` polling loops** — 17 of them, every one exiting 1–5 s *after* a `task-notification` that
would have woken the session anyway — and **86 min 52 s** of the operator's own screenshots queued
behind those turns. The work itself is ~3 s. The polling was the cost.

### What `cc-lr recover` does, so you do not re-do any of it

1. **Resolves** the ref through `cc-find` (0.18 s registry join, against the 30.4–41.0 s
   `cc-sessions` walk that printed no session id at all — U07 §0, §6b).
2. **REFUSES**, rc 2, creating no mutex, on any of three things — and these are enforced NOWHERE
   ELSE, so do not route around them:

   | refusal | why it is cc-lr's alone |
   |---|---|
   | a **TEAMMATE** | lead-owned; nothing is owed by anyone on it. `lr-fleet.sh --one` has no teammate guard at all — its one precondition is "already TRANSPLANTED". |
   | an **AMBIGUOUS** ref | panes 122 and 124 rendered the byte-identical statusline (U07 §4). An identification that silently picks one is how the wrong pane gets recycled. |
   | a session that is **not LIMITED** | its last assistant word is not a usage-limit error, so there is nothing to recover. |

3. **Takes the one-actuator-per-session mutex** (`~/.reso/limit-recover/runs/by-sid/<sid>.active`),
   then fires `lr-fleet.sh --one <sid> --target … --source-pane … --detach`, which re-execs the
   driver under `setsid` and returns in ≤3 s.

### The other three verbs

```bash
cc-lr status [<ref>|--all]     # one row per run's events.jsonl: STATE, AGE, CAUSE / NEXT
cc-lr repair <bundle|sid8>     # queue a poller request (mode relaunch|prompt) and kick the daemon
cc-lr find <ref…>              # the bare resolver: pane | sid8 | --tuple | --kw | --limited
```

`cc-lr status` is where a run's verdict is read back; its NEXT column names the ONE command for a
failed or parked run, which is always `cc-lr repair <bundle>`. `repair` writes a request and kicks
the LaunchAgent — **it never types into a pane**, because the daemon runs outside every session
and every classifier, which is the whole reason the request lane exists.

**Banned on this path, by name.** Each of these is a measured defect, not a style preference:

| banned | why (measured) |
|---|---|
| a foreground `while`/`until` loop polling for a file, a row or a pane state | the 24.4 lead-minutes above. The verdict is pushed to you; polling for it spends a turn to learn nothing sooner. |
| `cc-pane send` to put text in a composer | its text path is iTerm2 AppleScript and iTerm2 is not running on this box: it returned **rc 0 and delivered nothing**, costing 13.1 min on pane 111 (U11 §3). |
| `it2 session send` / `it2 session run` to deliver a MESSAGE | `send` types keystrokes — `it2 session send CR` typed the letters `C` and `R` into a live composer; `run` is the LAUNCH verb, whose armed-pane branch writes a `$CMD_DIR/<id>.cmd` file instead of reaching the screen (`handoff-fire.sh:1419-1431`). Messages go by `cc-notify`, which lands at a safe boundary. |
| `kitty @ send-key` for control keys | Claude Code pushes the kitty keyboard protocol, so `ctrl+u` rendered as the literal text `^[[117;5u` in the composer (U08 §3). |

If a pane genuinely must be told something, the one sanctioned write is a single `printf` to its own
tty path — which is what `handoff-fire.sh`'s terminal recycle arm now does.

### When you have no ref at all

`cc-lr find --limited` lists every session sitting on a usage-limit error; `cc-limited --json` is the
machine surface over the same stores, and `lr-fleet.sh --locate` is its screen form
(`--locate --json` execs into it). `LF_SLOW_SCAN=1` forces the old 35 s transcript walk back, which
is what `--deep` means. Then hand the sid or the pane to `cc-lr recover`.

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
7. **Never land a RECOVERED session's work on its behalf.** Its commits were made on
   reconstructed state; they stay on their branch for that session (or its successor) to finish
   and land. Code THIS session writes and verifies — a fix to the recovery machinery itself, with
   its tests run green this turn — lands via `/ship` under the ordinary ship policy, without
   asking. *(Revised 2026-09-10. The old rule — "never push / ship / deploy from a recovery;
   landing is the user's explicit call" — covered both cases, so a verified two-line poller fix
   that six limited panes were waiting on sat unlanded behind an operator "yes" for two hours
   while every Stop hook said to drive it. The operator's verdict: "why do you even need my yes?")*
   **Reversible choices are taken, never asked.** Holding one expensive session out of the
   auto-resume, staggering re-runs, or deferring a workflow re-run are undoable in one command:
   take the safe one, name it in the report, and say how to reverse it. Ask only for a choice
   that cannot be undone.

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

**Two lines of the audit gate everything below. Read them BEFORE the ledger.**

1. **`lead process: DEAD | IN-FLIGHT | IDLE | UNKNOWN`.** This is a measured pid, not an
   assumption, and every in-process verdict inherits it. A quota kill ends the session; **a network
   drop usually does not** — measured 2026-09-09, the whole fleet produced nothing from 14:40Z to
   17:20Z while every process stayed alive, and the first api-error record landed 107 minutes after
   the silence began. So disk silence is not death, and the state decides which actions are even
   legal (next table).
2. **`No genuine QUOTA limit events…`** is the quota SUBSET and is **empty on every network death,
   crash and stall** — `limit_events: []` sits beside a fully correct gap ledger. Reading that
   emptiness as "nothing was interrupted" is the trap this command exists to remove. The general
   death record is `last_api_error` (any `error` value), and the delegation population line names
   the strata so a zero cannot read like a clean session.

## Verdict → action (from the audit's gap ledger — execute, don't re-judge)

| Verdict | Meaning | Action |
|---|---|---|
| COMPLETE | journaled result / clean final turn, above floors | consume freely |
| SUPERSEDED | slot re-issued + completed under another agentId | none |
| COMPLETE_UNDELIVERED | finished on disk; result never reached the lead (no tool_result AND no task-notification) | **READ from disk — zero re-spend**: workflow → run-summary `.result`; subagent → final message in its jsonl |
| COMPLETE_SALVAGED | StructuredOutput validated in agent jsonl, never journaled | use the payload; cite provenance `(salvaged)` |
| VACUOUS_SUSPECT | mechanically complete, below signal floors | READ output vs its brief. Adversarial/refuter briefs must cite what they examined — a bare "no issues" is vacuous. Vacuous → re-run |
| NULL | killed at/near spawn (limit / 529 / api error) | re-run |
| PARTIAL | substantive work, no result | re-run; salvage text is seed-context only, never a substitute |
| INTERRUPTED | a genuine TaskStop / user interrupt — one attempt, no terminal run error | re-run unless salvaged payload exists |
| **STALLED** | N attempts under ONE journal key, no result, and the run json carries a terminal error. The harness already exhausted its OWN retries. The `[Request interrupted by user]` marker in each dead attempt is the WATCHDOG's, byte-identical to a human Ctrl-C — only the run error separates them, so this is never "the user did this" | **AT MOST ONE re-fire, and only under a green control** (§ Stall policy). A second stall under a green control convicts the REQUEST, not the network: change the request (split it, shrink the prompt, remove the blocking tool), never a third fire |
| **PENDING** | lead IDLE (alive, turn ended) and this unit has no terminal record | **WAIT-FOR-NOTIFICATION — never re-run.** The harness owns the promise and will settle it with a `<task-notification>`; that notification re-enters this audit on arrival, so waiting is the ACTION, not idling |
| **UNSETTLED-INFLIGHT** | lead IN-FLIGHT (alive, mid-turn) | **NONE. Do not touch.** Disk stays silent for as long as the retry ladder runs — 93–101 min measured on three units of one outage. Re-running here doubles a live unit |
| **RUNNING** (teammate) | the member's OWN pid is alive | **NONE — never respawn over a live member.** To hand it work, WAKE it. Keyed on the member's pid + turn end, not on a stamp: any outage past five minutes used to turn a live member into PARTIAL, whose action is respawn |
| TAINTED_COMPLETE (run) | run "completed" over gap slots (e.g. all-null 529 storm still returns) | final result is CONTAMINATED until its gap slots resolve |
| UNVERIFIABLE | artifacts missing/contradictory — **including a lead whose liveness could not be determined** | surface as a named gap — never infer. UNKNOWN liveness is deliberately NOT folded into DEAD: DEAD authorises a re-run |

**The three wait verdicts are not gaps and not COMPLETE.** The audit reports them in their own
**Wait ledger** and `counts.waiting`, and exits 0 — nothing is owed by *you*. Never restate that as
"all delegated work is complete": something is still moving, and the two are different states.

### Stall policy (what separates a stall that will clear from a deterministic one)

Never the stall's own text — a control:

1. **The fleet arm.** Any real-model assistant record from ANY session in the stall window proves
   the API path was live, which convicts the request rather than the network.
2. **A connectivity probe independent of the request** — DNS+TCP+TLS+HTTP only, no credential, no
   quota, and **two greens 30 s apart** (recovery needs hysteresis; one green is a coin flip):

   ```bash
   bash ~/.claude/scripts/limit-recover/lr-probe.sh        # rc 0 = GREEN (two greens, 30s apart)
   ```

   Any 3-digit HTTP status is green — the request is unauthenticated, so a refusal that travelled
   the whole path is proof the path works (measured 2026-09-10: the live endpoint answers a HEAD
   with **405**, so a 200-keyed check would be red forever). Only a transport failure is red. A
   green is **necessary and not sufficient**: it never licenses touching a unit a live process
   still holds.
3. **The re-fire itself, as the last discriminator.** One re-fire under a green control. A second
   stall under a green control is the request.

Receipt for why a blind re-fire is not free: on the measured run the harness re-issued one journal
key five times into a live outage — 85 minutes, six attempts, nothing produced.

## Mode: recover (default, no args)

1. **Still limited?** Map this config dir → account (`~/.claude`+`~/.claude-next`→next,
   `-secondary`→next2, `-tertiary`→next3, `-quaternary`→next4) and check live headroom:
   `claude-accounts --json | jq '.rows[] | select(.acct=="<label>")'` (rows live under
   `.rows` — a bare `.[]` iterates the top-level values and dies on the `cached` boolean).
   🚨 **In a RECOVERED session the binary is NOT on PATH** (measured 2026-09-19: an
   `lr-fire-resume.sh`/expect-launched successor inherits a PATH without `~/bin`, and
   `claude-accounts` returned `command not found` — silently EMPTY through `2>/dev/null | jq`).
   Call it by its repo path, `~/Development/claude-infrastructure/bin/claude-accounts`; this
   bullet used to say "resolve the binary from PATH, not `~/bin`", which is wrong in exactly the
   launch shape an ingesting session has. Treat a row carrying `error` or
   `stale_quota: true` as NOT a live reading — check `quota_as_of` before concluding
   anything about headroom, and note `poll_throttled` is a transient poll failure, never a
   cap. If `session_pct`/
   `weekly_pct` ≥ 100 (or the first re-run comes back with a genuine "You've hit your…" error):
   STOP and present — reset time (from the audit), wait cost, and the exact escape hatch
   `/limit-recover handoff auto`. Waiting vs switching accounts is the user's call; **only if the
   user already told you to continue autonomously** (e.g. a /goal), fire the handoff yourself.
   **Unattended (`CC_UNATTENDED=1`): do NOT present — the blocking prompt becomes an idle strand
   with no human to answer it; route the decision to a class-B packet + default instead (see
   [Unattended mode](#unattended-mode-cc_unattended1) below).**
   If ONLY `fable_pct` ≥ 100 (model-scoped): re-run fable-tagged slots on the house fallback
   `claude-opus-4-8` and mark each `(tier-fallback)` in the report.
   **`monthly_spend` limit events have NO reset** (extra-usage credits cap, not plan quota —
   incident 2026-07-18: teammates 429'd on the cap while the lead kept working). Decision rule:
   read `credits_on`/`credits_used_usd` (dollars; raw `credits_used` is CENTS) +
   `session_pct`/`weekly_pct` from `claude-accounts --json` —
   plan-quota headroom present → re-runs proceed on the SAME account (they bill plan quota; the
   cap only blocks credit-billed overflow); no plan headroom either → handoff to another account,
   or the user raises the cap at claude.ai/settings/usage (their call — surface both).
2. **Zero-spend first**: consume every COMPLETE_UNDELIVERED / COMPLETE_SALVAGED unit from disk.
   Then VACUOUS_SUSPECT reviews. Only then paid re-runs.
3. **Workflow re-runs — GATED ON THE LEAD STATE, and the gate is not advisory.**
   - **`UNSETTLED-INFLIGHT` or `PENDING` slots: fire nothing.** They are held by a live process.
     Report them from the Wait ledger and move to the next unit.
   - **`STALLED` slots: run the § Stall policy control FIRST** (two probe greens 30 s apart). The
     audit's run-level action for such a run reads `GATED RESUME`, not a bare resume, precisely so
     this step cannot be skipped by reading the run row instead of the slot row.
   - **`resumeFromRunId` is same-session-DIRECTORY, not same-process** (corrected 2026-09-19; this
     bullet used to say "same-session only … unavailable once the process boundary has been
     crossed"). The cache is the run's `journal.jsonl` under `<session dir>/subagents/workflows/<runId>/`,
     and `lr-transplant.sh` copies that directory with the transcript — so an INGESTING session on
     another account resumes the run it inherited: measured on `wf_b0f2a31c-e7d` (next4 → next3),
     the resume wrote its new agents under the ORIGINAL run dir, replayed the 13 completed slots
     from the journal at zero spend, and re-ran only the 10 dangling ones (24/24). What a resume
     cannot do is replay a slot that has no `result` row — a `DEAD` lead's dangling slots are
     re-run, never recovered, and the PREFIX rule below decides how many completed slots re-run
     with them. Verify after the call that new `agent-*.jsonl` files appeared under the ORIGINAL
     runId dir in YOUR session dir (ingest step 3); a fresh runId dir means the journal did not
     carry. Under `UNKNOWN` liveness, fire nothing and surface it.
   - 🚨 **At ingest, a run's delivered `<task-notification>` outranks `lr-audit`'s lead-liveness
     verdict.** The ingest turn is itself mid-turn, so the audit reads the lead as `IN-FLIGHT` and
     labels a SETTLED run's dead slots `UNSETTLED-INFLIGHT → do not touch` (measured 2026-09-19:
     10 slots, `agents_error 10`, notification already in the transcript). A delivered notification
     (or a run summary with a terminal status) means no retry ladder holds those slots: treat them
     as NULL and resume/re-run. The wait-verdicts protect only runs with NO notification record.
   - 🚨 **…and its cache is a PREFIX, not a set** (corrected 2026-09-15; this bullet used to say
     "journaled results replay free, dangling slots re-run"). A resume replays completed calls only
     up to the FIRST call that is not a cache hit — an EDITED call (any change to prompt or opts),
     a NEW call, or a DANGLING one (a failed or null slot is never cached). That call and every
     call after it in issue order re-run live, completed or not, because each journal key is
     chained on the calls before it. Measured on one run: after an earlier prompt was edited, an
     unchanged research prompt got a NEW key; with the edit reverted its key matched the original
     byte-for-byte and it re-ran anyway, because an earlier failed slot had broken the prefix. So a
     resume is free only when the dangling slots come AFTER every completed one in call order (a
     failed final stage). In a `pipeline()` every stage-1 call is issued before any stage-2 call,
     so ONE failed stage-1 slot re-runs every later stage-1 item and ALL of stage 2. When the
     dangling slots sit early, skip the resume and go straight to step 5's continuation — each
     journal `result` event carries the full schema'd object, so the completed results can be
     seeded from disk. And never "fix" a dangling call's prompt before resuming: the edit re-keys
     the rest of the run. Companion trap, same mechanism: inside ONE run an identical
     `(prompt, opts)` call is deduplicated by its key, so a script-level retry wrapper that
     re-issues the same request never actually runs — give the retry attempt a distinct `label`.
   - Then: ledger-append, `Workflow({scriptPath: <audit's scriptPath>, resumeFromRunId: <runId>,
     args: <original args from audit's lead.workflow_calls>})`. Results journaled BEFORE the first
     dangling call replay free; that call and everything after it re-run (prefix rule above). If
     the original deaths were a same-second 529 burst across many slots, EDIT the script first to
     stagger stage-1 launches (90s base + 20-30s/index — memory
     `reference-workflow-burst-529-stagger-launches`).
4. **Bare-subagent re-runs**: re-spawn with the ORIGINAL prompt from
   `salvage/subagents/<agentId>.json` (verbatim — do not paraphrase from memory).
5. **Re-audit** (rule 5). A slot STILL dangling after a resume means the script did not re-issue
   that call (changed conditional / `.filter(Boolean)` tail): hand-author a continuation script
   seeded with the salvaged COMPLETE results (`salvage/<runId>/slots.json`, or the `result`
   events in the run's `journal.jsonl`) that runs ONLY the missing slots, run it as a fresh
   Workflow, re-audit again. Take this route FIRST, without resuming, whenever a dangling slot sits
   before completed ones in call order (step 3's prefix rule) — a resume there re-spends everything
   after it. Seed through files the agents read (a per-unit digest on disk), not through `args`:
   everything in `args` is typed out by the lead as output tokens.
6. **Teams**: the audit now classifies every assignee session of every team this session LEADS
   (per-member verdict table + `salvage/teams/<team>/<member>.json`). Execute § Teams below —
   never re-implement teammate work the disk already holds, never respawn over a RUNNING member.
7. **Report** (final message): per-unit table of actions taken (re-run / read-from-disk /
   salvaged / tier-fallback), re-spend estimate, and the closing line — either
   `RECOVERY COMPLETE — gaps: 0 (fixpoint)` or `RECOVERY PARTIAL — named gaps: …` with each gap's
   blocker. Never the second dressed as the first.

## Teams — assignee-session recovery (implicit-team model, lead executes)

Assignee sessions are FULL Claude Code sessions (own transcripts, own panes) killed by the same
limits. Ground rule (incident 2026-07-18, team `session-44f5331d`): **the lead's "Teammate
failed" notification is NOT ground truth** — all 4 "failed" teammates had retried past the 429,
finished, and written their reports; only the handshake died ("SendMessage isn't available in
this subagent context" is a known teammate failure mode — the report then exits as final text).
The audit's per-member verdict comes from un-fakeable evidence, in rank order: brief-declared
output paths written during the member's tenure (mtime ≥ joinedAt, size > 0) → worktree commits /
`refs/wip/<member>` checkpoints → transcript terminal state → (never) lead-side perception.

Execute the member table top-to-bottom — each verdict has ONE action:

| Member verdict | Action (no re-judging) |
|---|---|
| COMPLETE | consume the deliverable from disk |
| COMPLETE_UNDELIVERED | **READ deliverable(s) from disk — zero re-spend.** Never respawn |
| RUNNING | wait (active < 5 min ago). NEVER respawn over a live member |
| PARTIAL / NULL / INTERRUPTED | respawn: `Agent({name, subagent_type, model, prompt})` with the VERBATIM brief from `salvage/teams/<team>/<member>.json` `.respawn_call` — never paraphrase from memory; list `partial_output_seeds` paths in a PREFIX line if seeding helps. Max 6 concurrent (agent-teams skill discipline) |
| VACUOUS_SUSPECT | read output vs brief; vacuous → respawn as above |
| UNVERIFIABLE | surface as a named gap — never infer |

Constraints: teammates bill the LEAD's account — a spend-capped account with plan-quota headroom
still respawns fine (step 1 decision rule). Whole-team handoff: `lr-handoff.sh` moves the LEAD
only; after ingest, respawn gap members on the target from their salvage briefs (teammate
in-flight context does not transplant; their disk deliverables survive and are re-read in place).
Course-change respawns (new ruling, not limit recovery) go through `bin/cc-respawn` instead.
The reset poller deliberately SKIPs teammate transcripts (lead-owned recovery, this section).

## Unattended mode (`CC_UNATTENDED=1`)

`/limit-recover` fires at a limit event — which, on the 24×7 desk, happens exactly when no human
is watching. A blocking `AskUserQuestion` there is the P15 strand: the turn halts on a click nobody
makes (gate #13, p15 §1). Under `CC_UNATTENDED=1`, EVERY wait-vs-switch elicitation in
**Mode: recover** step 1 is REPLACED by a durable decision packet + its default — never a block.
The interactive path (no `CC_UNATTENDED`) is UNCHANGED: wait-vs-switch stays the user's call and
`AskUserQuestion` still elicits. This only swaps the *blocking* elicitation for a *durable packet +
default*, honoring the anti-deference rule (surface the ONE fork, keep everything else moving).

This routing is no longer prose-only: the **`cc-unattended-ask-guard.sh`** PreToolUse hook (matcher
`AskUserQuestion`) is the deterministic backstop (T-P15-7). Under `CC_UNATTENDED`, an `AskUserQuestion`
is refused with `exit 2` and a reason that routes the fork to the `cc-decide` class-B packet below —
so even if this doctrine is forgotten mid-turn, the strand cannot form. Same steer-then-backstop shape
as `frontier-spawn-gate.sh`. Interactive sessions never trip it (the hook keys off `CC_UNATTENDED`
alone, not the payload). Kill switch: `CC_UNATTENDED_ASK_GUARD_DISABLED=1`.

Route every limit decision through `scripts/gate-classify.sh "<the limit text>"` first — both cases
below classify **B** (a value-fork the standing values settle toward continuation), never A, never a
C money-path. Then:

- **5-hour / weekly limit (reset time known)** → open a class-B packet and PROCEED on the default
  immediately (the deadline is the operator's early-veto window — a veto before it flips back to
  wait; `CC_UNATTENDED_VETO_HOURS`, default 1):

  ```
  cc-decide open --class B \
    --what "hit a 5h/weekly limit on <acct>; reset <ISO>. Wait for reset, or continue cross-account?" \
    --conviction <N: 0..100, past 90 means implement it> --receipt "<docs/research path, or: <command> => <output>>" \
    --option "wait::idle until <ISO>, then resume on <acct>" \
    --option "switch::continue NOW on <other-acct> (quota-plane isolation)" \
    --recommendation "switch — cross-account continuation keeps the mission moving (operator decision #3)" \
    --default "continue cross-account via /limit-recover handoff auto" \
    --deadline "<now + CC_UNATTENDED_VETO_HOURS>"
  ```

  then fire `/limit-recover handoff auto` on that default. This IS operator **decision #3**'s
  default-if-no-veto: cross-account continuation (quota-plane isolation).

  **Kimi overflow — the last-resort hedge (T-P8-6, gated on the operator key).** Cross-account
  continuation only helps while *some* Max account still has headroom. When EVERY Max account is
  capped — the true quota cliff (a full Anthropic cap / outage) — the metered Kimi hedge (a
  non-Anthropic endpoint) is the one remaining overflow. It is **gated on the operator key**:
  `cc-route`'s cliff branch runs `claude-kimi wired` and, only when WIRED, **OFFERS** it on the
  same exit-4 STOP (`claude-kimi` — metered, ~$3/$15 per MTok, isolated from the 4 Max accounts)
  alongside `/limit-recover`. It is an **OFFER, never an auto-route** — a cliff never
  silent-down-tiers to a paid endpoint or fires blind; actuation is one explicit `claude-kimi`
  invocation (a standing-authorization auto-fire, if ever wanted, is the separate autonomy policy,
  not this always-a-STOP branch). Not wired → `claude-kimi set-key` enables it for next time
  (OPERATOR key — the operator's metered spend).

- **Monthly-spend cap (NO reset time)** → there is nothing to wait for, and raising the cap is a C6
  money-path the desk must never sign. `gate-classify.sh` routes the monthly-spend text to **B** (a
  spend-LIMIT event, not a money COMMITMENT → never C). Open a class-B packet whose default is
  **park-to-backlog + continue other work** — never a silent park, never an inline cap raise:

  ```
  cc-decide open --class B \
    --what "monthly spend cap reached on <acct> — no reset time" \
    --conviction <N> --receipt "<docs/research path, or: <command> => <output>>" \
    --recommendation "park this account's remaining work to the backlog and continue other mission work on another account" \
    --default "cc-backlog add the parked unit, then continue other mission work cross-account" \
    --deadline "<now + CC_UNATTENDED_VETO_HOURS>"
  ```

  `autonomy-sweep.sh` actuates the fired default (append-to-backlog) at the deadline, and `cc-digest`
  surfaces it next morning. A cap RAISE stays a class-C, operator-only decision (staged artifact,
  never auto-signed).

## Mode: audit

Step 0 + reconcile + present the audit and the recommended plan. No re-runs, no mutations
(read-only turn). Use before deciding wait-vs-handoff, or to inspect any session:
`lr-audit.py --config-dir <dir> --session <sid> --cwd <path>` works cross-account.

## Mode: handoff [next|next2|next3|next4|auto] [opus|fable] [effort]

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
     --effort <the effort THIS session is running at> \
     --context /tmp/lr-context-$CLAUDE_CODE_SESSION_ID.md --launch
   ```
   **`--effort` is not optional in practice: a handoff continues ONE session, so the successor
   must be the same reasoning tier, not merely the same model.** Omitted, `--model fable` falls
   back to `--effort high` and the opus path to lr-fire-resume's account default — so a session
   running Fable 5 at `max` transplants DOWN to `high` while its statusline still reads "Fable 5",
   which is why nobody catches it. Read your own tier off the statusline (or `/effort`) and pass it.
   This audits + salvages into a bundle, copies the transcript + session dir (workflow journals
   included) + task list into the target account under the SAME uuid, sha-verifies, writes the
   split-brain lock + source tombstone, and fires the resume in a **split pane to the RIGHT of
   the invoking pane** (⌘D-style; a new iTerm2 window only when no invoking pane exists or the
   split fails), auto-submitting `/limit-recover ingest <bundle>` with a **verified submit** —
   the fire script re-sends CR until the running-turn indicator ("esc to interrupt") appears,
   because a leading-`/` prompt's autocomplete menu can eat the first CR (composer submits on
   `\r` only; observed stranded 2026-07-11). `--print-only` writes
   `$TMPDIR/lr-launch-<sid8>-XXXXXX.sh` instead (manual fallback is always printed).
4. **This session is now DONE.** Emit the handoff report (target account, bundle path, gaps
   handed over). Do not dispatch further delegated work here — the target session owns recovery
   (split-brain rule). Suggest the user close/park this pane.
5. 🚨 **IN-PLACE IS THE DEFAULT** (§ 10 W11, 2026-09-20; operator ruling: *"recover split panes in
   place so we are never at this confused middle case of untouched limited original sessions being
   resumed elsewhere in a new session"*). `--launch` recycles the pane that HOLDS the session —
   same window id, same uuid, new account — whenever a pane is resolvable. Nothing needs passing.
   The pane is found in one of three ways, in order: an explicit `--source-pane <P>`; SELF, when
   `--sid` is this process's own session and it is sitting in a pane; otherwise the DRIVER path —
   the session's live `cc-registry` row. **Two live rows is REFUSED, never guessed** — that is the
   `DUPLICATE` state, and picking one would type `/exit` into a session somebody else is still
   using; resolve it with `fleet --duplicates` first, or name the pane.

   **`--spawn`** is the explicit opt-out: today's split-pane / os-window behaviour, for when you
   want the limited pane's scrollback beside the successor. `--in-place` is still accepted and is
   now a no-op. The default never fires under `--spawn`, `--print-only`, `--no-transplant`,
   `--close-source`, or without `--launch`, and the automatic fallback to a spawn happens on exactly
   two conditions — **NO-PANE**, and the launcher-rooted REPLACE class (an expect-rooted pane whose
   `/exit` closes the window, so no shell survives to relaunch into). Every other refusal PARKS with
   nothing moved. Kill switch `LR_INPLACE_DEFAULT=off`.

   **When the recycle fails AFTER the transplant (`handoff-fire` rc 4), RETRY — do not hand-spawn.**
   `lr-transplant.sh` is now idempotent on a same-target retry (the lock names this target and the
   copy is present ⇒ rc 0, nothing moved), so `lr-fleet.sh --one <sid> --source-pane <P>` re-drives
   the whole recovery. The old prescription was an improvised `recover-<sid8>` os-window; four were
   made on 2026-09-19 and **none of them had `--var` provenance, a registry row, or a watcher — so
   nothing on the box could prove or retire them.** That shape is forbidden. If a successor is
   already carrying the session, the source pane is a `HUSK`: retire it with `fleet --retire-husks`.
   A lock naming a *different* target still refuses, and now says so rather than reporting the
   transcript missing.

## Mode: fleet [--locate | --recover [--target A] | --enqueue | --duplicates] — the pane IS the continuation

Added 2026-09-09 (docs/plans/LIMIT_RECOVER_100P.md; operator ruling 2026-09-08: *every limited
session located, self-closed, and resumed IN THAT SAME PANE on an unrestricted account — no husk,
no orphan, no ambiguity about which pane is which*). Script: `scripts/limit-recover/lr-fleet.sh`.

1. **`fleet --locate`** — the census, disk truth only: every session whose LAST assistant word is a
   limit error, across all four stores, joined to the registry (`~/.claude/cc-registry/<pane>.json`,
   written by each session's own SessionStart hook — the store argv can never replace). One row per
   session: pane · pid · account · cwd · **runtime tier from the transcript** (never argv: pane 616
   ran Fable/xhigh while its argv said Opus/high) · disposition — `RECOVERABLE` (a live pane holds
   it), `NO-PANE`, `TRANSPLANTED→acct` (already moved; nothing to do), `TEAMMATE` (lead-owned),
   `DUPLICATE` (more than one live process — resolve with `--duplicates` first, never recover over
   two writers), **`HUSK`** (§ 10 W10, 2026-09-20 — a LIVE pane on this store whose session has
   already MOVED: the process is alive, the composer is empty, the limit error is still on its
   screen, and the session is being worked on under another account. Neither this plan nor
   `LIMIT_DETECT_100P` modelled it, because both state models are keyed on the SESSION and a
   transplant makes one session into two objects with OPPOSITE dispositions. `bin/cc-husk-sweep`
   models the OTHER husk — a bare shell where a session used to be; this one is the opposite shape,
   the process is real and what is stale is its CLAIM on the session. Measured 2026-09-19: panes
   110, 126 and 150 were all in that state and `--locate` listed none of them while `--duplicates`
   found all three. The predicate is a three-part conjunction — a live registry row on THIS store's
   account, a transplant LOCK naming another store whose successor copy is on disk, and NO recovery
   in flight — and the third conjunct is what stops an in-progress recovery reading as a husk, since
   the lock is never deleted and the source row stays live until the typed `/exit` lands. Kill
   switch `LR_HUSK_RETIRE=off` returns the census to its pre-W10 output byte for byte).

   🚨 `HUSK` outranks `TRANSPLANTED→acct` for the SOURCE row, and the discriminator is whether the
   source pane is still alive: a live source row is a `HUSK` (something is standing and needs
   retiring), no source row is `TRANSPLANTED→` (the move is complete; nothing to act on).
2. **`fleet --recover`** — sequenced, one session at a time, each behind the NON-charging capacity
   probe (`cc_capacity_probe`: same terms as the admit gate, spends none of its 3-refusal budget — a
   pane is never `/exit`ed unless its relaunch can be admitted; at the wait cap the session stays
   PARKED with the term named). The target is `claude-accounts --rank` walked PAST the limited
   account; a Fable session routes on the fable lane. Each session runs
   `lr-handoff.sh --in-place --source-pane <P>`: transplant (lock + tombstone — the session is now
   PROVABLY retired at its pane, which is what admits a driver that does not own the pane), then
   `handoff-fire.sh --recycle --transplanted-source --source-pane P --source-session S
   --resume-launcher <launcher> --resume-cfg <target>`: `/exit` typed into the blocked TUI, its shell
   waited for, `bash <launcher>` (never `exec`) typed there — **same window id, same uuid, new
   account**, engagement proven by a fresh non-error assistant turn in the target's copy. A
   launcher-rooted source (an expect-rooted pane an older lr-handoff fired) cannot host a relaunch, so
   it is REPLACED in place: the successor is spawned beside the SOURCE (`--source-window`-pinned,
   runner-rooted via `bin/cc-pane-runner`, recyclable next time) and the source retired through the
   existing `self-close --transplanted-source` path once the successor is verified engaged.
3. **The report** proves the operator's question cannot arise: one row per session — `SID · PANE→ ·
   PANE← · ACCT→ · ACCT← · MECHANISM/VERDICT · NOTE` — closing with `RECOVERY COMPLETE — N in place
   (same pane id), M replaced beside their source, 0 left over` or `RECOVERY PARTIAL — named gaps`.
   Evidence: `~/.reso/limit-recover/fleet/<run>/` (census, per-session stderr, results.tsv).
4. **`fleet --enqueue`** — when a session's own Bash tool is refused (auto mode's classifier denies
   acting on a live pane from inside a session — measured 401 denials in 30 days across shapes no
   rule predicts), write the same request for the **launchd reset poller**, which runs outside every
   session and every classifier and drains `~/.reso/limit-recover/requests/` on its next tick
   (`launchctl kickstart gui/$(id -u)/com.reso.lr-reset-poller` runs it now — no `-k`, which would
   KILL a tick that may be mid-transplant). Results:
   `~/.reso/limit-recover/results/<sid>.json`. **The driver never hands the human a raw pane-close
   command** (operator ruling 2026-09-09); a `cc-do` row is minted only when the daemon itself cannot.
5. **`fleet --duplicates`** — sessions held by MORE than one live process (the 2026-09-09 shape: the
   poller resumed 52e35019 into tmux while pane 616 still held the original; one transcript, two
   writers, one account, and no tombstone for any guard to see). Lists both with start times; the
   LATER process took the conversation over (Claude Code hands it Remote Control), the earlier one is
   stale. `--mark <sid> --live <pid>` writes the SUPERSEDED tombstone (`superseded_by_pid`) beside the
   transcript: `handed-off-session-guard.sh` then blocks the stale copy's prompts by PROCESS identity
   (it acquits only the copy whose own claude pid is the successor), and
   `self-close --transplanted-source --source-pane <stale> --source-session <sid> --successor <live
   pane>` retires it — the class admits a same-account tombstone iff its successor pid is alive.
   **`--mark` refuses a session that has already been TRANSPLANTED** (§ 10 W9a, 2026-09-20): its
   existence check used to be keyed on whichever store the transcript search stopped in, so a
   session moved to another account kept its `handed_off_to` tombstone in the target root and the
   check never saw it. The cost was worse than the duplicate itself — `hf_transplant_evidence`
   refuses outright on finding two tombstones, so the stale pane the mark existed to retire became
   UNRETIRABLE. The check now scans every `lr_config_dirs` root with a resolved-path dedupe, because
   `~/.claude-next/projects` is a symlink onto `~/.claude/projects` and counting PATHS reads one
   physical tombstone as two. `--duplicates` also prints each sid ONCE (it iterated registry files,
   so the very population it exists to report — a session with two rows — printed its whole block
   twice).

Iron rules 1-7 bind unchanged: the fleet never lands a recovered session's work; every verdict is a disk
read; a PARTIAL is reported as PARTIAL. The reset poller is the daemon half of the same design:
registry-based liveness (a live original pane is NUDGED in place, never re-spawned), transplanted
records retired as such, visible runner-rooted kitty windows via the resolved socket, tier carried
from the transcript, and **no silent tmux** — a resume nobody can see is a resume nobody can answer.

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

## Mode: upgrade — same account, new binary + model, in place

Not a recovery: the sessions are healthy. `cc-lr upgrade` moves every IDLE live session onto the
CURRENT launcher binary (`cc-claude-bin`) and model (SSOT `versions.opus_latest`; a Fable session
keeps `frontier_access.model`, so its move is binary-only). Same pane, same session uuid, same
account, same effort and permission mode, all context kept by `--resume`.

```
cc-lr upgrade --all --dry-run      # one row per live session: pane · sid · binary · model → target · disposition
cc-lr upgrade --all                # queue every `upgrade` row; wait for the verdicts (--wait S, --no-wait)
cc-lr upgrade <pane|sid8>          # one session
cc-lr upgrade --report             # the last 24 h of verdicts: ✓ upgraded · · skipped <reason> · ✗ failed <cause + command>
```

**It never acts from inside a session.** It reads (one `ps` snapshot, the registry, transcripts) and
writes `kind:"upgrade"` requests into the poller's request dir, then kicks the poller (`kickstart`,
never `-k`). The poller queues them and starts ONE detached drainer
(`scripts/limit-recover/lr-upgrade.sh --drain`), which takes sessions one at a time and for each:
re-judges the selection at execution time → probes capacity and mints a one-shot admission token
BEFORE anything is typed → mints a pure-ASCII launcher (`lr-fire-resume` of the same uuid on the same
account) → runs `handoff-fire.sh --recycle --same-account --source-pane P --source-session S
--resume-launcher L --resume-cfg CFG --await`. If the gate refuses the relaunch after `/exit`, the
drainer retypes the launcher (≤5, 20 s apart; the gate admits a given resume after 3 refusals) so a
pane is never left at a bare shell without a named command.

**`upgraded` means the PROCESS moved** — a live `--resume <sid>` on the target binary and model. The
one-line confirmation turn is reported beside it, never instead of it: `confirmed by a fresh
assistant turn`, or `confirmation UNCONFIRMED (lr-fire-resume: FAILED:submit)`. Measured on the
first field run (2026-09-22): 2 of 3 relaunches came up correctly while the prompt injection failed
in ~25-column split panes (the composer read-back is width-dependent). An UNCONFIRMED session is idle
on the new binary; press Enter in its pane if the prompt is still in the composer, or Ctrl-U.

**Excluded, each by name:** `teammate` (its lead's) · `lead-with-teammate` (a live claude whose argv
names it `--parent-session-id`) · `mid-turn` (last main-thread record is not an assistant `end_turn`
— re-read again immediately before `/exit`) · `background-job` (a Bash-tool shell doing real work; a
lone `cc-await-ping` inbox watcher is NOT work — the relaunch ends it, it mails WAKE-PATH-DOWN, and the
relaunch prompt says to re-arm it; `LRU_WATCHER_IS_JOB=1` treats watchers as work) ·
`composer-occupied` / `composer-unknown` · `duplicate` (two live rows for one sid) · `self` ·
`no-transcript` · `stale-row` (registry lstart ≠ process lstart).

**The same-account evidence class** (`--same-account`, exclusive with `--transplanted-source`): the
registry row binds pane→session, the row's process is alive on that pane's tty, the row's account IS
`--resume-cfg`, the session has a transcript there and no tombstone, it is not a teammate, and its
transcript is at rest. Tests: `tests/handoff-recycle-same-account.bats`, `tests/lr-upgrade.bats`.

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
| Lead saw "Teammate @x failed" | NOT ground truth — teammates retry past 429s and finish; trust the deliverable-path stat in the member table (all 4 "failed" members had reports on disk, 2026-07-18) |
| Teammate transcript: "SendMessage isn't available" | known handshake failure — the report exits as final text + disk file; read it there, never re-run |
| Teammate limit-parked but pane alive | lead nudges via SendMessage once headroom returns; the reset poller intentionally skips teammate sessions |
