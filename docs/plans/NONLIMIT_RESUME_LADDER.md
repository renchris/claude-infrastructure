# Non-limit resume + the Opus→Fable→Teams escalation ladder

Opened 2026-09-09 from an operator ask in session `d79f408b`. **Status: RESEARCH CAPTURED (W0) · DESIGN
CAPTURED (W1, § W1 — Fable 5.1 discovery) · implementation NOT started.** W2 may begin from § W1.3;
see § Phase 0.

`Scope (frozen):` establish whether `/limit-recover` covers NON-quota interruptions (network drop,
reconnect, agent stall) with the same no-partial-results discipline; capture the disk truth
exhaustively; hand the design to Fable 5.1 rather than implementing at Opus reach; and separately
investigate making the three-stage Opus→Fable→Teams ladder the CLAUDE.md default.

---

## Phase 0 — Agent Team Orchestration (EXECUTION LOCUS PER WAVE)

| Wave | Locus | Model / effort | Why |
|---|---|---|---|
| W0 research capture | **L** (lead-inline, DONE) | Opus 5 / high | Disk-truth measurement is decomposable but small; the lead already held the audit context. Capacity gate refused fan-out (13 sessions mid-turn) and instructed serial execution. |
| W1 discovery | **S** — self-recycle | **Fable 5.1** / xhigh | Operator directive: the reachable fruit is picked; what remains is the unknown-unknown class Opus 5 is blind to. NOT a re-verification of W0 (that would be banned ceremony) — it is design of what W0 could not reach. |
| W2 implementation | **S** → in-session teammates | Lead Opus 5 / max; assignees Opus 5 / **stepped-down** effort | Implementing a SOLVED design needs less intelligence than discovering an unsolved one. |
| W3 ladder-as-default | **S** — separate session | Opus 5 / high | Distinct subject (CLAUDE.md policy), must not share W1's context. |

**Lead context budget:** W0 lead closed at ~50%; succession point is this document.

---

## The task table — THIS IS THE SHARED LIST

`TaskCreate`/`TaskList` are gated behind `CLAUDE_CODE_ENABLE_TODO_TOOLS=1`, unset in all five config
dirs (migration `0022`, operator-owned). Until it lands, per global CLAUDE.md, this table is the list.
Nothing here may be held in a context window.

| # | Task | State | Owner | Notes |
|---|---|---|---|---|
| T1 | Establish whether the audit engine is limit-specific | **DONE** | W0 | It is not. See § Finding 1 |
| T2 | Establish whether the fleet census is limit-specific | **DONE** | W0 | It was. Fixed + verified, `3a63bfd43` |
| T3 | Capture exact on-disk record shapes for network/stall deaths | **DONE** | W0 | § Finding 2 |
| T4 | Measure the live blast radius | **DONE** | W0 | 29 network vs 35 limit; 6 live panes |
| T5 | Fable 5.1 discovery pass on 100th-pct design | **DONE** | W1 | § W1 — six answers, design D1–D7, rejected R1–R8, W2 table, § W1.4 |
| T6 | Implement the design via Agent Teams | **OPEN** | W2 | Unblocked by T5. Task table + fixtures in § W1.3; W2-0 proof gates D4 |
| T7 | Investigate the ladder as CLAUDE.md default | **OPEN** | W3 | Separate session, § W3 brief |
| T8 | Resume the 6 live network-blocked panes | **DONE (by the operator, by hand)** | operator | All six re-engaged 17:36–17:37Z by the typed paragraph — § W1.0. The manual act IS the defect W2 removes |

---

## Finding 1 — the audit engine was ALREADY interruption-agnostic; only its trigger was quota-shaped

`lr-audit.py` classifies each delegated unit from disk terminal state, and the verdict never consults
the *reason* for the death:

- `slot_verdict` (`:279-282`) returns **NULL on ANY `api_error`**. `classify_limit_text` is called
  only to LABEL the evidence string — it does not gate the verdict.
- A non-limit error is classified `other_api_error` and **excluded from `limit_events`** (`:336`,
  `:662`). So a network kill yields **`limit_events: []` and a fully correct gap ledger**. Reading the
  empty event list as "nothing was interrupted" is the trap.
- Bare subagents route through the same predicate (`:534`); teammates via `last_kind == "api_error"`
  → NULL/PARTIAL (`:868-870`).
- Workflow runs are discovered from BOTH `session_dir/workflows/wf_*.json` and
  `session_dir/subagents/workflows/wf_*` (`:1322-1329`), so a stalled Dynamic Workflow is reachable.

**Consequence:** the whole audit → forced re-run → re-audit fixpoint, the verdict table, the Teams
member table and Iron rules 1-6 already apply verbatim to a network death. What does NOT apply is
Mode:recover step 1 (headroom check, wait-vs-switch, reset time), handoff/transplant, fleet
transplant, and the login-cliff branch — all of which presuppose the account is the problem.

**So the gap was DISCOVERY, not capability.** The command's frontmatter `description:` names only
quota and auth-cliff triggers, so "(Reconnected to internet, continue)" loads none of it, and the
operator lands in exactly the failure the command's own opening paragraph refutes: *the model
reconciles from CONTEXT, which still holds the pre-kill narrative and reads plausible, satisfices on
the units it remembers, and smooths the gaps into the conclusion.*

## Finding 2 — measured record shapes (quoted, not inferred)

**Network death**, `.claude-tertiary/projects/…wt-2ee30f87c370/137f37fe-….jsonl` line 1098:

```json
{"type":"assistant","message":{"model":"<synthetic>","role":"assistant",
 "content":[{"type":"text","text":"API Error: Can't reach the API server — check your internet or DNS (ENOTFOUND)"}]},
 "error":"server_error","isApiErrorMessage":true,"version":"2.1.260"}
```

The envelope is **identical to a cap's**. `model:"<synthetic>"` + `isApiErrorMessage:true` is the
structural discriminator that makes a text-widened predicate safe: a session merely *discussing*
ENOTFOUND in prose (this repo does constantly, including the session that wrote this document) is not
a synthetic api-error record and cannot match.

**Workflow stall** arrives differently and this matters: it is NOT an assistant api-error at all. In
`52e35019` (the operator's screenshotted pane) it lands as a `queue-operation` record followed by a
**`type:"user"` `<task-notification>`** carrying an `<output-file>` pointer. Operator-visible text:
`agent stalled on all 6 attempts (no progress for 180000ms each)`. The subagent variant is
`Agent stalled: no progress for 600s (stream watchdog did not recover)`.

⚠️ **`stalled` / `stream watchdog` appear NOWHERE in `scripts/limit-recover/`.** A stalled workflow
is therefore unmodelled at the census layer, and the lead's context simply holds "the workflow
failed" — which is precisely how the screenshotted session ended up parked at `> wait for it to
finish` for 11h 53m.

## Finding 3 — the census was blind, and is no longer (T2, landed `3a63bfd43`)

`lr-fleet.sh:86` gated every row on `LIMIT_RE` as the LAST assistant word. Six panes killed by one DNS
outage produced `(no limit-blocked session anywhere)`. Widened to a `BLOCK_RE` union keeping the
structural envelope, with `KIND` as a first-class column because it decides which recovery is *legal*:

| kind | recovery |
|---|---|
| `limit` | account out of quota ⇒ transplant (`--recover`) |
| `network` | account is FINE, pane usually still alive ⇒ **RESUME-IN-PLACE**; a transplant would spend an account move on a problem that no longer exists |

`--recover` and `--enqueue` both refuse network rows by default rather than "helpfully" moving them.

## Finding 4 — live blast radius, measured 2026-09-09

**29 network-blocked vs 35 limit-blocked sessions.** The network half was entirely invisible before
T2. Six distinct live panes are resumable in place right now:

```
553ff801  next   716  claude-opus-5/high  /Users/chrisren/Development/.worktrees/classify-beacon
fd1ab61c  next   694  claude-opus-5/high  /Users/chrisren/Development/.worktrees/reland-rowkey
2878d5d2  next   679  claude-opus-5/high  /Users/chrisren/Development/claude-infrastructure
9a547759  next3  719  claude-opus-5/high  /Users/chrisren/Development/.worktrees/rules-union-merge
bfe42820  next3  715  claude-opus-5/high  /Users/chrisren/Development/.worktrees/wt-09f8bb68dbf3
d85264e5  next4  672  claude-opus-5/high  /Users/chrisren/Development/claude-infrastructure
```

## Finding 5 — a hazard the quota path never had to model

A quota kill ends the session. **A network drop usually does not** — the TUI stays alive and a
delegated unit may still be running or retrying past the outage. The audit gives *teammates* a
`RUNNING` verdict for exactly this (active < 5 min ⇒ never respawn over a live member). **Bare
subagents and workflow slots have no `RUNNING` verdict**, so a still-live one reads PARTIAL and a
blind re-run doubles it. Any resume design must resolve this before it re-fires anything.

---

## Handoff brief — W1, Fable 5.1 discovery (T5)

Everything above is the *reachable* fruit, found at Opus 5 / high. **Do not re-verify it** — that is
banned ceremony. Design what it could not reach:

1. **The RUNNING gap (Finding 5).** What is the correct predicate for "this non-teammate unit is
   still alive" when the harness gives no liveness signal, the process may be mid-retry, and jsonl
   mtime is a stamp written at *record* time? Prior art in this repo says a stamp cannot be a
   liveness proxy and orphanhood is not discriminating.
2. **Stall is a third class, not a network variant.** A 6×180s stall means the harness already
   exhausted its own retries. Is re-firing correct, or does it reproduce the stall? What
   distinguishes a stall that will clear from one that is deterministic?
3. **The trigger problem is general.** Every future non-quota death class will be invisible the same
   way. Is there a formulation that does not enumerate spellings? (This repo's own rule: a denylist
   enumerates spellings, not the class.)
4. **Should this be a mode of `/limit-recover` at all**, or is `limit-recover` now a misnomer for a
   general *interrupted-work recovery* command?
5. **The operator's actual ask is prompt-free automation.** They currently type a paragraph. What is
   the design where a reconnect needs ZERO paragraph — and what is the failure mode of making it
   automatic?
6. **Unknown-unknowns.** What is wrong with this framing that Opus 5 could not see?

## W3 brief — the ladder as CLAUDE.md default (T7)

Operator directive, verbatim intent: research exhaustively at Opus 5, distill to a document, recycle
into **Fable 5.1** for the unreachable class, then recycle into **Agent Teams** with an Opus 5 max
lead and stepped-down-effort Opus 5 assignees — *"this should be the default behavior out of the box
with CLAUDE.md without having to explicitly prompt."*

Open questions: how does this interact with the existing § Frontier Tier Routing (which today makes
Fable **opt-in only** and says the lead never runs on it)? What is the trigger predicate for "this
problem is generator-class enough to earn the ladder" vs routine work where the ladder is pure cost?
Does `/frontier-campaign` already encode part of this?

---

## W1 — Fable 5.1 discovery (T5)

Run 2026-09-09 on `claude-fable-5-1`, worktree `nonlimit-resume-fable`, from the W0 capture above.
Nothing in W0 was re-verified; every claim below is a NEW read, and every one carries its receipt.
`Scope (frozen)` for this pass: answer the six questions, produce the design + rejected alternatives +
W2 breakdown + "What Opus 5 could not see", commit on this branch, land nothing, implement nothing.

### W1.0 The finding that reframes the problem: the sessions were never dead, and the operator was the runtime

Measured over the 149 transcripts modified today across all five config dirs, counting assistant
records whose `model` is a real model (not `<synthetic>`), per 10-minute UTC bucket:

```
13:50 654 · 14:00 661 · 14:10 502 · 14:20 483 · 14:30 490 · [14:40 → 17:10: NO bucket, zero records] · 17:20 158 · 17:30 425 · 17:40 558
```

**The whole fleet produced nothing from 14:40Z to 17:20Z** — a 2h40m outage — while every session
process stayed alive. The api-error records that W0 measured are not the outage; they are the
clients' retry ladders EXPIRING, in batches (distinct sessions per minute, all ENOTFOUND):
`16:27 ×4 · 16:39 ×1 · 16:56 ×4 · 17:12 ×1 · 17:18 ×1 · 17:19 ×3 · 17:20 ×1 · 17:22 ×1`. The first
error record landed **107 minutes after the silence began**. The ladders themselves are long and
uneven — measured on three units of the same outage:

| unit | silent from | error record | ladder |
|---|---|---|---|
| main turn, `137f37fe` (tertiary) | 15:38:54 (`:1097-1098` attachments) | 17:12:15 ENOTFOUND (`:1099`), `turn_duration` 5,601,349 ms (`:1100`) | **93.4 min** |
| main turn, `52e35019` (secondary) | 16:27:40 (`:1420`, the failed-workflow notification) | 17:19:10 ENOTFOUND (`:1423`) | 51.5 min |
| workflow slot `wf_acd6923d-9c5` key `v2:a990db61…` | 14:46:44 (last record of attempt 1 `agent-a6d8fc6…`) | 16:27:39 `failed`, 6 attempts | **100.9 min** |

Then the re-engagement, which W0 never looked at. For each of the six "RESUME-IN-PLACE" panes in
§ Finding 4, the first prompt after its api-error record was `origin.kind=human`,
`promptSource=typed`, text `(Re-connected to internet, continue. If there are any subagents…` —
timestamps **17:36:09, 17:36:10, 17:36:11, 17:36:12, 17:37:36, 17:37:42**, plus `52e35019:1425` at
17:36:30. **The operator hand-typed the paragraph into seven panes in 93 seconds.** All six now carry
24–272 real assistant records after the error and were active at 17:44–17:57Z; T8 is moot.

The seventh pane is the important one. `137f37fe` was re-engaged by **the harness itself**: a
background Bash task (`biek210ez`, a `/ship` land) finished at 17:28:48 and its
`<task-notification>` (`:1104`, `origin.kind=task-notification`, `promptSource=system`,
`<status>completed</status>`) woke the model with no human input; the model took a turn (`:1106`,
`tool_use:Bash`) and carried on landing — **from context, with no audit**. And the wake DID run the
UserPromptSubmit hook chain (`:1105`, `hook_additional_context`: "PROMPT CACHE EXPIRED: 172m idle").

So the problem is not "how do we trigger recovery on a network death". Every one of these sessions
was going to be re-engaged within the hour — by the operator or by the harness — and **no wake, from
either source, carried a disk-truth audit.** The paragraph is the operator doing by hand what the
wake should do by construction. That is the design target, and it collapses Q3, Q4 and Q5 into one
mechanism.

### W1.1 Answers to the six questions

**Q1 — the RUNNING gap.** The predicate is not computed from the unit at all; it is INHERITED from the
lead, in three lead states, and the unit's own file only says what it DID:

| lead state | test (all structural) | every in-process unit (bare subagent · workflow slot · background Bash) |
|---|---|---|
| **DEAD** | no live process holds the session: registry row + `kill -0` (`lr-lib.sh:116-126`) **and** no `--resume <sid>` leaf in argv (the registry alone missed `52e35019`: `lr_registry_live_rows` rc=1 while pid 77720 `claude --permission-mode auto … --resume 52e35019…` is alive, started Sep 8 19:51) | DEAD — a fresh process holds no promise. Re-run is safe and correct. |
| **IN-FLIGHT** | process alive **and** the last prompt has no `system/turn_duration` after it | the turn is running — mid-retry or working — and disk is silent for up to the ladder (93–101 min measured). DO NOT TOUCH. Not PENDING, not PARTIAL: `UNSETTLED-INFLIGHT`. |
| **IDLE** | process alive **and** `turn_duration` present after the last prompt | a unit with a terminal record is settled; a unit WITHOUT one is **PENDING** — the harness owns its promise and WILL settle it with a `<task-notification>` (status vocabulary over 300 recent transcripts: `completed` 5979 · `failed` 358 · `killed` 180 · `running` 29 · `stopped` 4). Action: **WAIT-FOR-NOTIFICATION**, never re-run. |

"Terminal record for unit U" = U's spawn `tool_use` id appears in a `tool_result` (foreground) **or**
in a `<task-notification><tool-use-id>` (background). The audit today tracks only the first
(`lr-audit.py:379`, `delivered_tool_ids`) and never reads a notification (`grep -c task-notification
lr-audit.py` ⇒ 0), and it never reads a pid (`grep -E 'kill -0|os.kill|psutil|lstart' lr-audit.py`
⇒ 0 hits) — so it cannot tell the three lead states apart and treats everything as DEAD.

Receipt that the gap is live right now: `wf_f3e13296-400` in `52e35019` has one slot,
`agent-aefd2e2…`, first record 17:38:56, last record 17:54:29 (an assistant `tool_use:Bash`), i.e.
**one minute before the audit ran**, in a live process. `lr-audit.py` reports it `PARTIAL —
substantive but unresulted (lines=234 tool_uses=52)`, flags the run "run dir exists but run-summary
json missing (killed mid-run)" (`:1335` — a death asserted, never measured), and its ACTION is
`RE-RUN` (`:1277`). A design that executed that plan would double a running slot.

The mid-retry half is what makes any stamp proxy fatal here, and it reaches TEAMMATES, which W0
believed were covered: `TEAM_ACTIVE_WINDOW_S = 300` (`:87`) turns a live member into `PARTIAL —
substantive but unfinished … last activity Ns ago` (`:879-885`) the moment an outage passes five
minutes — every outage does (2h40m today) — and the ACTION for PARTIAL is respawn over the live
member. The RUNNING verdict is right in its polarity and wrong in its evidence; it must key on the
member's pid and its `turn_duration`, exactly like the lead.

`turn_duration` as the turn-end marker: present after the api-error turn (`137f37fe:1100`,
`52e35019:1424`) and after normal turns (`52e35019:1469`, `:1492`); 12 occurrences of the string in
the 2.1.260 binary (`~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, Mach-O
arm64, 198,289,440 B). Caveat for W2: `52e35019` has 27 distinct `promptId`s and 24 `turn_duration`
records — three prompts (queued mid-turn, most likely) share a turn end, so the test is "no
`turn_duration` after the LAST prompt", never a 1:1 count. Pin it with a fixture.

**Q2 — stall is a third SYMPTOM, not a third cause, and the control arm decides per incident.** The
"stall" is the shortest watchdog's view of the same 14:40–17:20 outage: slot attempt 1 made real
progress until 14:46:44 (its last records: a 600 s tool timeout result, three `hook_cancelled`
attachments, a `total_tokens_reminder`), then no assistant record for 17.9 min, `[Request interrupted
by user]` at 15:04:37; the harness re-issued the SAME journal key five more times — `agent-aa08e85…`
15:04:37→15:21:31, `a2fce60…` 15:21→15:38, `a55f878…` 15:38→15:55, `a921bd0…` 15:55→16:12,
`a3cd836…` 16:12→16:27 — each exactly 7 lines (the prompt, five spawn attachments, the interrupt) with
**zero assistant records**, ~17 min apart; `journal.jsonl` holds six `started` under one key and one
`failed`; the run json reads `status: failed`, `error: agent stalled on all 6 attempts (no progress
for 180000ms each)`, `durationMs: 42825639`. Five identical re-fires into a live outage cost 85
minutes and produced nothing. The fleet counter above is the control arm: NOTHING streamed anywhere
in that window, so the stall was environmental, not request-specific.

What separates a stall that will clear from a deterministic one is therefore a **control, never the
stall's own text**: (1) the fleet arm — any real-model assistant record from any session in the
stall window proves the API path was live, which convicts the request; (2) a connectivity probe
independent of the request (an unauthenticated `HEAD` on the API host: DNS+TCP+TLS, no quota; two
greens 30 s apart — recovery needs hysteresis); (3) the re-fire itself as the last discriminator —
**at most one re-fire under a green control; a second stall under a green control convicts the
request** (prompt size, a tool that blocks, a headless permission prompt) and the remedy is to change
the request (split/shrink), never a third fire. Two receipts that the classes are entangled at the
unit level: the same run's `logs` carry `[security] failed: You've hit your session limit · resets
12:50am` — a LIMIT death (`agent-a2fc17f…`, 05:15:48) inside a network-stalled workflow — and the
watchdog kill is written to the slot as `[Request interrupted by user]`, byte-identical to a human
Ctrl-C; only the lead's `<status>failed</status>` (vs `stopped`) and the run json's `error:` separate
them. The audit currently calls those four retries `INTERRUPTED (TaskStop / user)`, lists 4 of the 6
attempt files (`a921bd0…` and `a3cd836…` are absent from its slot table), and its ACTION for
INTERRUPTED is RE-RUN (`:1278`) — right verb, wrong attribution, wrong population.

Re-fire mechanics by lead state: IDLE lead in the same process ⇒ `Workflow({scriptPath,
resumeFromRunId})` after `TaskStop` — the tool schema says completed `agent()` calls with unchanged
`(prompt, opts)` return cached results and only the failed calls re-run, **same-session only**;
DEAD lead ⇒ a new run from the salvage (the audit's `INCOMPLETE` action at `:1284` already says
resume, but it does not know the resume is unavailable after a process boundary). Either way the
probe gates the fire.

**Q3 — the trigger without spellings.** Three structural predicates, none of which names an error
text, replace the widened `BLOCK_RE` (`lr-fleet.sh:95`) as the RECOVERY trigger (the census may keep
its regex as a display label):

1. **The process boundary.** `SessionStart` with `source=resume` — the field is already consumed by
   `hooks/accounts-board.sh:70` (`jq -r '.source'`). On a resume every open delegation is DEAD by
   construction, whatever killed the process: quota, network, crash, reboot, `/exit`.
2. **The api-error record.** Last assistant record before this prompt has `isApiErrorMessage:true` —
   any `error` value. `rate_limit` and `server_error` differ only in which recovery MODE is legal.
   `classify_limit_text` keeps its one job: labelling (§ Finding 1).
3. **The non-success notification.** A delivered `<task-notification>` whose `<status>` is not
   `completed` (`failed` · `killed` · `stopped`), for a tool-use-id that spawned a delegation.

Every future death class — a new watchdog, a new HTTP code, a kernel-killed process — arrives as one
of those three shapes, because the harness has exactly three ways to end work: end the process,
write an error turn, or fail a task. The denylist rule in this repo's memory is satisfied because
nothing here enumerates a message.

**Q4 — yes, `/limit-recover` is a misnomer, and the name matters less than it did this morning.** The
engine is interrupted-work recovery; "limit" is one death class that selects one recovery mode
(headroom / wait-vs-switch / transplant, `commands/limit-recover.md:127-172`, `:278-316`). Two
changes: (a) a `/recover` command whose `description:` names the CLASS (any non-normal turn end,
any non-success notification, any resume boundary) with `limit` · `resume-in-place` · `stall` as
modes, and `commands/limit-recover.md` reduced to a pointer that keeps the old trigger phrases
loadable; (b) `scripts/limit-recover/` and `lr-*` keep their names — the live layer is per-file
symlinks and a rename is an ADD that is absent until the converger runs (global CLAUDE.md, the
`LIVE_ADDS` rule), and 40+ memory/doc citations name the path. The deeper reason the name matters
less: after Q5 the entry point is a HOOK, and a human types the name only to override it.

**Q5 — zero-paragraph automation: make the wake carry the audit, and make the wake exist.** Two
arms, both on rails this repo has already proven, plus the engine changes from Q1/Q2:

- **D3 `recover-inject.sh` (UserPromptSubmit).** On every prompt, read the transcript tail; if
  predicate 2 or 3 of Q3 holds, emit `additionalContext` that (i) names the death record and its
  uuid, (ii) lists the open delegations by tool-use-id and tool name, (iii) instructs the disk-truth
  audit before any other action, (iv) forbids re-firing before the probe is green. Latch once per
  death-record uuid. This is the belt: it makes the operator's paragraph correct if typed, and it
  makes the harness's own task-notification wake correct — proven reachable at `137f37fe:1105`.
- **D4 `net-recover-arm.sh` (asyncRewake, SessionStart + Stop, same shape as
  `hooks/mailbox-wake-arm.sh:1-25`).** A per-session watcher, idempotent under the same claim guard,
  that sleeps until [last assistant record is an api error ∧ `turn_duration` present ∧ probe green
  twice] and then exits 2 with the audit instruction on stderr — the harness synthesizes the turn.
  No keystrokes, no composer, no task-registry entry (goal-safe). This is what removes the paragraph.
- Re-fires go through the machine admission gate that `no-capacity` already cites — seven audits
  waking within seconds of each other on a just-recovered link is the burst shape measured above.

**Failure modes of making it automatic, each with its guard:**

| failure | why it is real | guard |
|---|---|---|
| re-fire into a still-dead network | the harness proved it: 5 re-fires, 85 min, nothing | the probe gates every fire; two greens 30 s apart |
| loop: wake → re-fire → error → wake | each error is a new record | latch per death-record uuid; the watcher never fires twice on one record |
| doubling a live unit | `wf_f3e13296` slot, PARTIAL while running | Q1's PENDING verdict; WAIT-FOR-NOTIFICATION is an action, not idling — the turn ends and the harness's own notification re-enters through D3 |
| side-effecting units re-run from zero | teammates commit on their branches; "no partial results" was written for read-only research units | verdict space split by unit class: research ⇒ re-run; side-effecting ⇒ resume from the worktree/branch state, never blank |
| **nothing can be armed at the death** | Stop hooks did not run on the api-error turn: Stop records at `137f37fe:1085` (prior turn) and `:1144` (next turn), **none in `:1099-1103`**; `52e35019:1423→1424` has no `stop_hook_summary` where normal turns do (`:1468`, `:1491`). goal · session-continue · completion-assert · mailbox-wake-arm's Stop re-arm are all absent exactly then | D4 arms at SessionStart and at every PRIOR Stop, idempotently — it must already exist when the death happens |
| wake lands on an IN-FLIGHT session | mid-retry turns last up to 101 min with nothing on disk | D4 keys on `turn_duration`; a synthesized prompt into a live turn is queued, not lost, but it must not fire the audit before the ladder resolves |
| session parked on a permission modal | no composer, no wake (this repo's "empty vs no-surface" rule) | not fixable from inside; the census keeps the row and it renders as 👤 |
| fail-safe mimics healthy | an audit that misses a new spawn tool prints "0 open" and reads clean | the audit prints its population by tool name (`Agent` n · `Workflow` n · background `Bash` n) and the settled/open split; a zero names its strata |
| unattended quota spend | seven wakes re-firing N units each | audit is always automatic; RE-FIRE is automatic only under probe-green ∧ admission ∧ idempotent-or-resumable; everything else is the `⛔` rung. `CC_RECOVER_AUTO=0` kill-switch |

**Q6 — what is wrong with the framing.** See § W1.4.

### W1.2 Recommended design

| id | change | where | replaces |
|---|---|---|---|
| **D1** | lead classifier DEAD / IN-FLIGHT / IDLE from pid (registry ∪ argv leaf) + `turn_duration`; unit liveness inherited; new verdicts `PENDING` (action WAIT-FOR-NOTIFICATION) and `UNSETTLED-INFLIGHT` (action NONE, name the ladder); teammate RUNNING re-keyed on the member's pid + turn end, `TEAM_ACTIVE_WINDOW_S` demoted to a display field | `lr-audit.py` — new `lead_state()` beside `scan_lead_transcript` (`:301`); `audit_bare_subagents` (`:520`), `audit_workflow_run` (`:397`, and `:1335`'s "killed mid-run" becomes conditional on DEAD), teammate branch `:879-885`; ACTION dict `:1275-1287` | the all-DEAD assumption |
| **D2** | notification ledger: settled ids = `tool_result` ids ∪ `<task-notification><tool-use-id>`; open delegations = spawn `tool_use` ids (`Agent`, `Workflow`, `Bash` with `run_in_background`) − settled; notification `<status>` recorded per unit; six attempts under one journal key fold to ONE unit with `attempts=6`, verdict `STALLED` (not INTERRUPTED) when the run json `error:` says so | `scan_lead_transcript` (`:301-395`), workflow journal fold (`:431-470`) | `delivered_tool_ids` only; INTERRUPTED "(TaskStop / user)" |
| **D3** | `recover-inject.sh` on UserPromptSubmit (Q5) | `hooks/` (new file — an ADD; 🚀 until converged) + `settings.json` registration (operator-run migration, like `0007`/`0012`) | the typed paragraph |
| **D4** | `net-recover-arm.sh` asyncRewake on SessionStart + Stop (Q5) | `hooks/` (new) + registration | the operator noticing the wifi came back |
| **D5** | probe + control-arm gate before any re-fire; stall policy (one re-fire under green control; second stall convicts the request); `resumeFromRunId` only when the lead is the same process | `scripts/limit-recover/lr-probe.sh` (new) called from `commands/…` Verdict→action (`:112-126`) | blind RE-RUN |
| **D6** | `/recover` command with modes; `limit-recover.md` becomes a pointer; frontmatter `description:` names the class | `commands/recover.md` (new), `commands/limit-recover.md` | the quota-only description (`:1-4`) |
| **D7** | census: `KIND` per UNIT not per session; `RESUME-IN-PLACE` renamed `IDLE-AFTER-ERROR` and carries the age of the error record; argv-leaf fallback for the registry hole | `lr-fleet.sh:95-147`, `:273` | a snapshot that expired within an hour |

**Rejected alternatives, and why:**

- **R1 — an external actuator that TYPES the continue-prompt into each pane** (the `resume-sessions`
  skill's keepalive shape, `it2 session send`). Rejected: a keystroke-free wake exists and is proven
  (`docs/research/mechanical-wake-asyncrewake-2026-07-29.md`, `docs/research/w2-stop-rewake-proof/`;
  and the harness's own notification wake measured at `137f37fe:1104-1106`); typed bytes into a pane
  on a modal are consumed as answers (this repo's empty-vs-no-surface rule); auto mode's classifier
  denies acting on a live session (memory `auto-mode-classifier-denies-acting-on-a-live-session`).
- **R2 — arm recovery from the dying turn's Stop hook.** Rejected: Stop does not run on an api-error
  turn end (receipt above). Anything armed "at the death" is unreachable.
- **R3 — mtime/stamp liveness for units.** Rejected by the strongest instance this repo has recorded:
  107 minutes of fleet-wide disk silence with every process alive. It is also the mechanism by which
  the teammate RUNNING rule fails.
- **R4 — the widened `BLOCK_RE` as the recovery trigger.** Rejected: it is a denylist of spellings;
  correct for a display column, wrong as the class. Q3's three predicates are the class.
- **R5 — rename `scripts/limit-recover/`.** Rejected: the live layer is per-file symlinks (an ADD is
  absent until converged), and the path is cited across memory and docs.
- **R6 — `resumeFromRunId` as the universal re-fire.** Rejected: same-session only and it needs
  `TaskStop` first (tool schema); unavailable across the process boundary; and without D5 it fires
  into the same outage.
- **R7 — sleeping inside the audit turn until PENDING units settle.** Rejected: it burns the turn and
  cannot outlast a 100-minute ladder; the harness's notification is the wake, and D3 re-enters it.
- **R8 — a Stop-hook `decision:block` that retries the API after an error.** Rejected: each block is
  a new API call into the same dead network, capped at 8 by `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, and
  Stop does not fire there anyway (R2).

### W1.3 W2 task breakdown — Opus 5 Agent Teams, stepped-down assignee effort

Locus **S → T**: one dispatched wave-lead session (Opus 5 / max) spawns the assignees below in its own
worktree family; the lead holds ≥50% of its window for merge + the two proofs. Independent tasks
first, in one spawn message. Every task ships a fixture built from the REAL transcripts named in this
section (copy the byte ranges into `tests/fixtures/`; never synthesize an api-error record).

| id | task | files (pre-greped anchors) | effort | blockedBy | done when |
|---|---|---|---|---|---|
| **W2-0** | **Proof: asyncRewake synthesizes a turn after an api-error turn end.** Replicate the P-W2 probe with the session's last turn ended by a forced api error; assert a synthesized prompt appears with `promptSource=system`. Second arm: Stop-hook absence on that boundary (assert no `stop_hook_summary`). | `docs/research/w2-stop-rewake-proof/blocker.sh` as the template; output `docs/research/api-error-rewake-proof-2026-09.md` | high | — | both arms measured on 2.1.260; if the first FAILS, D4 falls back to the desk sweep writing to the session mailbox and the plan records it |
| **W2-A** | D1 + D2 in `lr-audit.py`: `lead_state()`, notification ledger, PENDING / UNSETTLED-INFLIGHT / STALLED verdicts, journal fold, teammate RUNNING re-keyed | `lr-audit.py:87`, `:301-395`, `:397-470`, `:520-560`, `:879-885`, `:1275-1287`, `:1335` | high | — | fixtures: (a) `137f37fe:1097-1110`; (b) `wf_acd6923d-9c5/` journal + 6 attempt files; (c) `wf_f3e13296-400/` with a live-pid stub ⇒ PENDING, with a dead-pid stub ⇒ DEAD; (d) a teammate transcript silent >5 min under a live pid ⇒ RUNNING. `python3 -m pytest tests/limit-recover/` green; the 52e35019 re-audit prints `PENDING` for `aefd2e2…` while its pid lives |
| **W2-B** | D3 `hooks/recover-inject.sh` + bats | new; read pattern from `hooks/mailbox-drain.sh` (prompt arm) and `hooks/cache-expiry-warning.sh` (transcript-tail read on UserPromptSubmit) | medium | W2-A (imports the ledger) | bats: api-error tail ⇒ context emitted once; second prompt ⇒ silent (latch); normal tail ⇒ silent; non-success notification ⇒ emitted |
| **W2-C** | D4 `hooks/net-recover-arm.sh` + probe `scripts/limit-recover/lr-probe.sh` + bats | new; claim-guard pattern from `hooks/mailbox-wake-arm.sh` | medium | W2-0 | bats with a stubbed probe: fires exactly once on [api-error ∧ turn_duration ∧ 2 greens], never on IN-FLIGHT, never twice on one uuid |
| **W2-D** | D5 stall policy + Verdict→action rewrite in the command | `commands/limit-recover.md:112-126`, `:127-172` | medium | W2-A | the command's table maps every new verdict to exactly one action; `resumeFromRunId` branch gated on lead state |
| **W2-E** | D6 `/recover` + pointer; D7 census columns | `commands/recover.md` (new), `commands/limit-recover.md:1-12`, `lr-fleet.sh:95-147`, `:273` | low | W2-A | `lr-fleet --locate` prints KIND per unit and the error-record age; `/recover` loads on "reconnected", "stalled", "resume" |
| **W2-F** | registration migration for D3/D4 (`settings.json` hooks entries), staged as a numbered migration for the operator, never applied by an agent | `migrations/` (pattern: `0007`, `0012`) | low | W2-B, W2-C | migration file + `--check` green; listed in the close as 👤 |

Lead's own context budget: the two proofs (W2-0, and the live re-audit in W2-A's done-when) are the
only things the lead runs inline. Succession point: this section.

### W1.4 What Opus 5 could not see

1. **It measured deaths and never looked at wakes.** Every "blocked" pane was re-engaged within ~40
   minutes — seven by the operator's hands, one by the harness — and not one wake audited. The
   design target is the content of the wake, not the trigger's spelling.
2. **It read the error record's timestamp as the death's time.** The fleet went silent at 14:40; the
   first record is 16:27. During those 107 minutes every process was alive and mid-retry, disk was
   silent everywhere, and this repo's own "a stamp is not liveness" rule was being violated by
   `TEAM_ACTIVE_WINDOW_S` for every live teammate — the population W0 believed was safe.
3. **It read "stall" as a third cause because it was a third record shape.** The control arm shows
   one outage seen through three timeout ladders (18-min watchdog, 52-min and 93-min turn ladders).
   Classes are per UNIT and can mix in one run (a limit death inside a network stall).
4. **It did not see that Stop hooks do not run on an api-error turn**, so the entire Stop rail —
   goal, session-continue, completion-assert, the mailbox re-arm — is absent at the one boundary
   this plan is about. A "just arm it at Stop" design would have shipped and never fired.
5. **It did not see the harness's own re-engagement path as the substrate.** A `<task-notification>`
   wake is keystroke-free, already proven, runs the UserPromptSubmit chain, and is the majority wake
   in the fleet (5,979 `completed` notifications in 14 days on two accounts). The census's
   `RESUME-IN-PLACE` told the operator to type; the machine was about to type for them.
6. **It did not see `turn_duration`.** A structural, spelling-free turn-end marker that separates
   IN-FLIGHT from IDLE on disk — the one axis the RUNNING gap actually turns on.
7. **It did not open the retry files.** Five 7-line attempts under one journal key, written as user
   interrupts; the audit lists four of six and blames the user. "Re-run" was the right verb applied to
   the wrong object with the wrong population.
8. **"No partial results" was read as universal.** It is an iron rule for read-only research units and
   a doubling hazard for side-effecting ones; the verdict space needs the unit's class.
9. **It framed the operator's ask as a trigger problem.** It is an agency problem: a hand-off that
   makes the human the runtime (global CLAUDE.md § Manual-Command Delivery), performed seven times in
   93 seconds.

**Unmeasured, stated as such:** whether asyncRewake synthesizes a turn after an api-error end
(evidence by parity with the task-notification wake; W2-0 proves it); the binary's exact watchdog
and ladder constants (`no progress for` ×5 and `stalled on all` present in 2.1.260; the context grep
timed out at 198 MB — W2-A pins them from the measured intervals, which is what the design keys on
anyway); whether `resumeFromRunId` accepts a run whose json reads `status: failed` (W2-D fixture).

**Stale peer mail, disposed:** a 2026-08-07 message about `wt-1a226422cb37` (11 sessions on one
worktree, uncommitted work under pid 49875) was forwarded into this session on 2026-09-09; the
worktree exists, pid 49875 is dead, the orchestrator role file is empty. No action; recorded here so
the next reader does not re-forward it.
