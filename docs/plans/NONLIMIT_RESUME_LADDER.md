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
| T7 | Investigate the ladder as CLAUDE.md default | **DONE** | W3 | § W3 — six answers, proposed diff, R1-R4 |
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

---

## W3 — the ladder as a default

**T7, session `624e04a1`, Opus 5 @ high, 2026-09-09.** Read-only research plus this section; no
CLAUDE.md file was edited (the diff below is a PROPOSAL, per the brief's hard constraint).

**The finding that reorganises every other answer:** the policy this section was asked to amend is
**already false in both directions, and has been for a month.** It says the frontier tier is opt-in
via three commands and that the lead never runs on it. Measured over all 4,117 transcripts in the
four config dirs:

| Claim in § Frontier Tier Routing | Measured | Command |
|---|---|---|
| escalate via `/frontier-run` | **1 invocation, ever** | `grep -rhao '"content":"/frontier-[a-z]*'` over `.claude*/projects` ⇒ `1 frontier-run` |
| panels are the frontier product | **2 `frontier-derivation` panelists** ran on Fable | cross of the fable-model list with `grep -l frontier-derivation` |
| "the lead itself never runs on it" | **52 Fable LEAD sessions**, 30 of them ≥20 turns (median 72, max 899) | `grep -rl '"model":"claude-fable'` minus `/subagents/`; verified per-file with `jq 'select(.type=="assistant").message.model'` |
| the tier is bounded by a spawn cap | **the session path is uncapped** — `frontier-spawn-gate.sh` is registered only as `PreToolUse` `matcher:"Agent"` (`~/.claude/settings.json:490-503`), so a `handoff-fire --model fable` spends the meter with no gate; `handoff-fire.sh` only prints a cost warning | `sed -n '490,503p' ~/.claude/settings.json` |

Fable lead sessions by month: **25 in 2026-08, 27 in 2026-09** (9 days). Fable *subagent* runs: 140
(99 Aug, 41 Sep) — of which **2** came from the ceremony. So ~99% of frontier spend already bypasses
the machinery the policy names, and the one sentence that would have stopped it (`the lead itself
never runs on it`) has been contradicted 52 times without ever refusing anything.

This is the repo's own *"a resident rule restating a perishable fact cannot learn it changed"* and
*"enforcement must live at the chokepoint"* in one place: the rule is prose, the chokepoint covers a
path nobody uses, and practice went around both.

### 1 — The trigger predicate

**The predicate already exists, is already resident, is already mechanical, and is already
evaluated by every session on itself without asking: it is Follow-On Gate F2's conviction number.**

F2 (`~/.claude/CLAUDE.md:542`) says, verbatim:

> *"If conviction of a decision is not >90% then research exhaustively, and then implement if now
> >90% or then ask the user if below."*

That sentence has exactly **two** outcomes below 90 after exhaustive research: implement anyway, or
**hand it to the human**. The ladder is the missing third — *escalate the MODEL before escalating to
the OPERATOR* — and it is the branch this operator's standing values were already asking for
(§ Session Close Protocol: *"Offering is the defect"*; *"the answer will always be yes"*).

So the trigger is a conjunction of three self-evaluable facts, no operator involved:

- **T-a — conviction < 90% after this session's exhaustive research, on a FRAMING question.** Not a
  missing fact (that is more research at the default tier); an unresolved *framing*, where the
  session cannot name the measurement that would settle it. F2 already forces the number and
  `cc-decide open --class C` already refuses without it.
- **T-b — there is a stage 3.** The deliverable must be a design that something later implements.
  With nothing to implement, this is a research pass, not a ladder — and paying 2× for a document
  nobody builds from is the tax case.
- **T-c — the Fable meter admits it.** `claude-accounts` carries a **separate weekly-Fable column**
  per account; measured 2026-09-09 16:51: `next 17% · next4 20% · next3 30% · next2 68%`, with the
  router already publishing `➤ fable → next4`. A ladder fire reads that row; no headroom ⇒ no
  stage 2, and stage 1's document is the deliverable.

**Why this fires rarely by construction, which is the whole design point.** Most work clears 90%
after ordinary research — that is what the F2 number is for. The predicate cannot fire on routine
work because routine work *is the >90% case*. It fires precisely where today's policy dead-ends into
a round-trip with the operator, which is the state the operator has said repeatedly he does not
want. It is therefore **not** a ladder that fires on everything; it is a ladder that fires exactly
where the alternative is a question.

**Cost, corrected.** The resident sentence "Fable is 2× the price ($10/$50 vs $5/$25)" is
**base-rate only, and the SSOT says so in terms**: `model-config.yaml:538-539` — *"⚠️ That verdict is
BASE-RATE-ONLY; re-check it against Fable 5.1's 0.025× cache reads before reusing it."* On the line
that dominates a long session, **Fable 5.1 cache reads are $0.25/MTok against Opus 5's $0.50**
(`model-config.yaml:530-531`, `:539`) — *half*, not double. The 2× figure is true of new input
tokens and false of the dominant term. Fable 5.1 also bills the plan's Fable-scoped weekly meter,
not credits (`model-config.yaml:266-274`, measured by an A/B on the meter itself).

### 2 — The conflict with existing policy, resolved rather than glossed

Three sentences must change. All three are in one paragraph, `~/.claude/CLAUDE.md:293` (the repo copy
at `CLAUDE.md:293` is **byte-identical** — `diff -q` reports no difference, so the diff lands in both).

**S1, quoted:** *"The frontier tier (currently Fable 5) is **opt-in only** — its value is exclusively
the *delta above the default* (unknown-unknowns the default is blind to), NEVER routine/identified
work; the lead itself never runs on it."*

**S2, quoted:** *"…so escalate on a *named* Fable strength rather than by default — the routing
economics are open work…"*

**S3, quoted:** *"Because the human never model-switches or starts frontier sessions, the agent
**escalates autonomously but BOUNDED** (hook-enforced per-session spawn cap; a blocked spawn = PARK,
never retry)…"*

Also `~/.claude/skills/frontier-routing/SKILL.md:35` — *"the lead itself never runs on the frontier
model"* — and `frontier-run/SKILL.md:46` — *"**The lead session NEVER changes its own model.**"*

**Why the change is not simply a loosening, stated precisely.** Three reasons, in increasing force:

1. **The loosening already happened, silently.** The tier is *not* bounded on the path that is
   actually used: 52 Fable lead sessions passed no gate, because the only gate is `PreToolUse
   matcher:"Agent"`. S3 asserts a bound over a path with no bound. The proposal REPLACES an
   unenforced prohibition with an enforced admission — strictly tighter than the status quo on the
   axis that spends money.
2. **S1's stated reason does not survive its own mechanism.** `frontier-run/SKILL.md:53-55` grounds
   "the lead never changes its own model" in prompt-cache re-processing cost. A `--recycle` is
   exit-then-relaunch — a *new process* — so there is no cache to re-process; the rule's premise is
   about a transition the recycle path does not perform. (This is the repo's *"published figure
   decays with its source"* shape: the reason outlived the thing it reasoned about.)
3. **S2 tells you to escalate on a named strength, and this names one.** The strength is not "Fable
   is smarter". It is: *a model that did not produce the framing is not invested in it.* The one
   trial's nine refutations (§ W1.4) are nine attacks on the FRAMING, not nine better facts — items
   1, 2, 8 and 9 each say the Opus pass measured the wrong object. That is a named, testable
   strength, and it is the one S2 asks for. **It is also the item most confounded** — see §6.

**The honest residue:** the change genuinely does loosen one thing. Today an escalation requires an
agent to judge a wall qualifying; tomorrow it follows mechanically from a number. That is a real
transfer of discretion from judgment to arithmetic, and arithmetic cannot see a case where the
below-90 is *boring*. The bound in §6 is what pays for it.

### 3 — What already exists (composition, not new machinery)

**~85% composes.** `frontier-campaign` **already encodes stage 3 verbatim** —
`skills/frontier-campaign/SKILL.md:3`, *"Fable 5 as bounded **ARCHITECT/JUDGE** over default-tier
implementer teammates"*, with `:49-61` naming the Opus lead, default-tier implementers and
`set-teammate-effort.sh`. Stage 3 is that minus the Fable judge — a deletion, not an addition.

Genuinely missing, four items, only one of which is code:

- **(a) A bound on the SESSION path** — the real gap, and the one that makes the current state worse
  than either policy. `frontier-spawn-gate.sh` cannot see a `handoff-fire --model fable`.
- **(b) A ladder state object.** Holes have a status enum, campaigns have one, a ladder run has
  none. `frontier-campaign/SKILL.md:46-47` already states the principle: *"the per-session spawn cap
  cannot see a multi-session campaign; the ledger can."*
- **(c) Stage 2 is ANCHORED, and every frontier surface forbids that.**
  `frontier-run/SKILL.md:94-96` — *"never paste known findings, worklists, or prior reports into
  discovery briefs"*; `agents/frontier-derivation.md:31-36` calls leaked findings *"contamination"*.
  The ladder's stage 2 reads stage 1's exhaustive research **on purpose**. This is not a missing
  script, it is a **different product**, and the trial is one data point *against* the anti-anchoring
  doctrine for this use — recorded here as a tension, not resolved.
- **(d) The policy amendment** in §2.

Nothing in the frontier stack fires on its own: `frontier-status.sh` prints one SessionStart line
and exits 0; `frontier-spawn-gate.sh` can only refuse. Every trigger reads *"invoke YOURSELF"*.

### 4 — The self-recycle mechanics (measured, and the brief's premise is wrong)

**The brief says model is launch-time identity so an Opus→Fable transition "cannot be a --recycle of
the same process". That is right about processes and wrong about `--recycle`.** A recycle is
exit-then-relaunch in the same pane — a NEW process — so launch-time identity is honoured, not
violated. Measured, this session, dry-run:

```
$ CC_RECYCLE_SUBAGENT_GATE=off bash scripts/handoff-fire.sh --recycle \
    --model claude-fable-5-1 --effort xhigh --prompt-file <brief> --dry-run
⚠️  Fable 5 is the frontier tier — ~2× the default model's cost ($10/$50 per Mtok vs $5/$25).
account:  next4
launcher: claude4
command:  … claude4 --effort xhigh … --model claude-fable-5-1 "$(cat <brief>)"
```

Parser arms: `--model` `scripts/handoff-fire.sh:7569`, `--effort` `:7570`, `--recycle` `:7584`;
argv append `:9055-9066`; recycle CMD composition `:9551`. `--recycle` also relocates worktrees
(`:8325-8348`) and re-picks the account under pressure (`:8303`). **The three transitions:**

1. **stage 1 → 2:** `--recycle --model claude-fable-5-1 --effort xhigh --prompt-file <stage-1 doc>`.
   Same pane, new process, fresh context, brief on disk. **Expressible today.**
2. **stage 2 → 3:** `--recycle --model claude-opus-5 --effort high --prompt-file <stage-2 doc>`,
   then Agent Teams *inside* that session. **Expressible today.**
3. **stage 3 assignees:** teammate PANES (not subagents) plus
   `scripts/set-teammate-effort.sh <worktree> high|xhigh` at worktree setup.
   **Expressible today** — with the caveat in §5.

**The goal-arm failure, which happened TWICE and once was to this very session.** The brief cites the
W1 fire. It recurred at 13:55 today on `624e04a1` — the pane was on a blocking modal, and
`handoff-fire.sh:5056` fired its abstain path. Three corrections to the brief's model of it:

- **It is not silent.** The abstain arm notifies the fired session **in-band via `cc-notify`**
  (`:5056`), and the message names the cause and the exact `/goal` line to submit. I received it.
  Two sibling arms exist for `composer-occupied` (`:5045`) and `readback-mismatch` (`:5050`).
- **But it is addressed to the victim** — the same shape as this repo's *"a verdict goes WHERE THE
  OPERATOR LOOKS"* rule. A session told "you have no backstop" is being told by the thing that was
  supposed to be its backstop.
- **The real gap:** none of the three abstain arms arms a fallback driver. Grepped: `0` occurrences
  of `session-continue` in `:5041-5060`. **A goal-safe fallback already exists and is free** —
  `~/.claude/hooks/session-continue.sh set "<next step>"` writes a file, needs no composer, and is
  the lever the resident rules already name as *"the lever that actually drives the next turn"*.
  On goal-arm abstain the fire should set it. That single line converts a silent no-backstop into a
  driven one, and it is the minimum an unattended ladder needs.

Also relevant and already true: `--recycle` **inherits** a live goal from the predecessor
(`inherit_recycle_goal`, `:4994-5009`) and re-validates it, printing a refusal rather than dropping
it silently — so a ladder that arms one goal at stage 1 carries it across both recycles.

### 5 — The stepped-down assignee effort

**Verdict: UNTESTED for Opus 5 — and the only measurement this repo has points the OTHER WAY for the
subclass implementation actually falls in. Do not encode it.**

- **Mechanism: available, with one hard limit.** Per-teammate effort is settable for *panes*
  (`skills/agent-teams/SKILL.md:200-212`) via `set-teammate-effort.sh`, because panes re-resolve
  `<worktree>/.claude/settings.local.json`. It is **inert for in-process subagents** —
  `SKILL.md:243-244`: *"an assignee gets `--effort <lead's value>` on argv … inherited, never
  per-call. There is no effort field on the Agent tool in either version."* And `max` is
  **settings-inexpressible** (schema caps at `xhigh`), so "lead at max, assignees stepped down"
  can only mean lead-at-max-via-argv and assignees at ≤xhigh. Usage today: **3 of 21** worktree
  `settings.local.json` files carry an `effortLevel` at all.
- **Evidence: one certification, on the wrong model, pointing the wrong way.**
  `model-config.yaml:769-783` records T1 (`wf_771c1e9f-644`, blind judge panels over real briefs):
  xhigh did **not** tie max on grounding-heavy classes — *"mechanical-search (xhigh HALLUCINATED a
  fabricated diff against a non-existent file + misclassified an internal alias)"*, and
  `:791-793`: *"mechanical work that must SEARCH for the site … stays at default max — xhigh
  hallucinated a fabricated edit there. xhigh is safe only when the targets are given."* An
  implementation assignee working from a design doc is *search-heavy by definition*.
- **And that certification does not even transfer.** Same file, `:781-783`: *"That certification is
  MODEL-SCOPED and does not transfer to Opus 5 — Anthropic: 'run a fresh effort sweep on your evals
  rather than reusing' a setting tuned for an earlier model."* The current
  `effort_defaults.default: high` is described in its own comment as *"the guide's STARTING POINT,
  not a measured optimum — a real per-class sweep is still owed"* (`:763-771`, pointing at
  `docs/research/opus5-adaptation-2026-08-01.md` §D3).

So: the operator's assertion is **an untested belief on this model**, and the nearest evidence is a
same-repo measurement contradicting it for search-heavy work. Encoding it as policy would be exactly
the defect the resident rules name.

**The probe that would settle it** (falsifiable, two arms, one variable):

- **Corpus:** ≥8 already-solved implementation tasks from `docs/plans/*` — each with a design
  section fixed *before* implementation and a landed commit, so ground truth exists.
- **Arms:** teammate panes at `high` vs at `xhigh` via `set-teammate-effort.sh`, identical briefs,
  identical worktree shape, same lead, tasks randomised across arms.
- **Metric:** blind judge (per `verify_judge: xhigh`, the one certified free win) scoring against the
  landed commit, plus mechanical arms that need no judge — gate-green on first run, count of
  edits to files not named in the brief, and a hallucinated-target count (edits to paths that do
  not exist), which is the specific T1 failure.
- **What makes it FALSE:** if `high` shows a higher hallucinated-target or off-brief-edit count than
  `xhigh` at any n where the difference clears its interval, stepping down is refuted for this
  class. **Guard the gate itself** against this repo's *"acceptance gate must be monotone in
  evidence"* rule — score on an interval, never on a sample extremum, or collecting more data will
  make certification *less* likely.

Until that runs, stage 3 should use the SSOT defaults unchanged and say so.

### 6 — The honest case against, and the kill-switch

**One trial, and it has no control arm.** In the W1 run, the Fable pass had (i) a different model,
(ii) a completely fresh context, and (iii) a written, distilled brief instead of accumulated
session state. **Nobody ran the cheap arm** — recycle into a fresh *Opus 5* session with the same
brief — so the nine refutations cannot be attributed to the model. This repo has a rule for exactly
this, cited against itself: *"one-armed adjudication only convicts"* — a sibling running the same
population with the control arm reached the opposite conclusion. Two of the nine items (#5 the
task-notification substrate, #6 `turn_duration`) are *disk facts a fresh reader finds*, not model
insight. **Conservatively, the fresh-context arm explains an unknown but non-trivial share, and the
measurement to separate them costs one Opus recycle.**

Failure modes of a default:

- **It fires on a boring below-90.** T-b (a stage 3 must exist) is the only thing stopping this, and
  it is a judgment. A below-90 on a dull question buys a 2×-input-priced pass for nothing.
- **Stage 2 unavailable** — Fable meter at cap, account logged out, or the router routes nowhere.
  Then the ladder must degrade to "stage 1's doc is the deliverable" *without* the session treating
  the missing stage as a blocker. A ladder that stalls on a closed meter is worse than no ladder.
- **Stage 2 arms no goal.** Observed 2 for 2 in the fires this plan touched. Without §4's
  `session-continue` fallback, an unattended stage 2 has nothing driving it, and the measured
  outcome is drift onto whatever is in the inbox.
- **Fable 5.1's own documented failure modes hit stage 3 hardest** (`model-config.yaml` § FABLE 5.1,
  relayed in the resident rules): *fewer progress updates at higher effort* (our stall detectors read
  quiet as stuck — and note that **two of this session's own subagents were killed by exactly that
  watchdog at 600s today**), and *whole-file rewrites for small edits*, which is a direct hazard to
  the INTEGRATE-never-overwrite rule. Both argue for keeping Fable at stage 2 (a document) and never
  at stage 3 (edits) — which is what §3 recommends anyway.
- **Operator-time cost of a false positive** exceeds the token cost: a wrong stage-2 fire produces a
  confident, differently-framed document that a later session must adjudicate against stage 1.

**The kill-switch — and it must be mechanical, not prose.** Opus 5 *"will rationalise a prose rule …
but it cannot rationalise a chokepoint"* (`docs/research/opus5-adaptation-2026-08-01.md`, closing
principle). So:

1. **`CC_LADDER=off`** — one env var, read by the fire path, refusing the stage-1→2 recycle. The
   operator's single lever.
2. **Extend `frontier-spawn-gate.sh` to the SESSION path**, so `handoff-fire --model fable` is
   counted and capped like an Agent spawn. This is item (a) of §3 and it is the load-bearing one:
   *without it, this proposal has no bound at all* — and neither does the status quo.
3. **Meter-gated by construction:** no Fable weekly headroom ⇒ no stage 2, reported as a degrade,
   never as a block.

**Absence of (2) is what would make this a mistake.** A default that escalates automatically, over a
path with no counter, on the strength of one uncontrolled trial, is three unbounded things at once.

### The proposed CLAUDE.md diff

Lands in **both** `~/.claude/CLAUDE.md` and the repo `CLAUDE.md` (byte-identical today, `diff -q`
clean). Single paragraph at line 293; INTEGRATE — the surrounding section is untouched.

**BEFORE** (`~/.claude/CLAUDE.md:293`, the two clauses that change, quoted exactly):

> The frontier tier (currently Fable 5) is **opt-in only** — its value is exclusively the *delta above the default* (unknown-unknowns the default is blind to), NEVER routine/identified work; the lead itself never runs on it.

> Because the human never model-switches or starts frontier sessions, the agent **escalates autonomously but BOUNDED** (hook-enforced per-session spawn cap; a blocked spawn = PARK, never retry): capture holes with `/frontier-hole`, escalate with `/frontier-run` (inline ≤2 panelists on a blocking wall; batch at wrap-up when OPEN holes ≥ 2 and the window is active), long-horizon generator-class problems via `/frontier-campaign`.

**AFTER:**

> The frontier tier (currently Fable 5.1) is **not opt-in and not a default — it is the third branch of Follow-On Gate F2.** Its value is exclusively the *delta above the default*, NEVER routine/identified work. F2 leaves a below-90%-conviction decision two outcomes, implement or ask the operator; **the third is to escalate the MODEL before escalating to the HUMAN**, and that is this tier's standing job. Fire the ladder when all three hold, self-evaluated, no operator ask: **(T-a)** conviction is still <90% after this session's exhaustive research AND the residue is a *framing* question, not a missing fact; **(T-b)** there is an implementation for the answer to feed — no stage 3 ⇒ this is a research pass, not a ladder; **(T-c)** `claude-accounts` shows weekly-Fable headroom on a routable account — no headroom ⇒ stage 1's document IS the deliverable, degrade and say so, never block. The ladder is three same-pane recycles, each a NEW process, so launch-time model identity is honoured: `handoff-fire.sh --recycle --model claude-fable-5-1 --effort xhigh --prompt-file <stage-1 doc>` → back to `--model claude-opus-5` → Agent Teams there. **Fable writes DOCUMENTS, never edits** (5.1 rewrites whole files for small edits — § File Update Rule). **The lead MAY run on it, for stage 2 only** — that sentence's premise was prompt-cache cost, which a fresh process does not pay; it had also been contradicted 52 times before it was changed.

> Because the human never model-switches or starts frontier sessions, the agent **escalates autonomously but BOUNDED — and the bound is a chokepoint, never this paragraph.** `hooks/frontier-spawn-gate.sh` counts Agent-tool spawns; **it does not yet see the SESSION path**, so a `--model fable` fire is currently uncounted — until it does, treat `frontier_discovery_budget` as advisory and say so in the close. A blocked spawn = PARK, never retry. Kill-switch: `CC_LADDER=off`. Surfaces: capture holes with `/frontier-hole`, escalate with `/frontier-run` (inline ≤2 panelists on a blocking wall; batch at wrap-up when OPEN holes ≥ 2), long-horizon generator-class problems via `/frontier-campaign` — measured 2026-09-09, these have been invoked **once between them across 4,117 transcripts** while Fable ran 52 lead sessions and 140 subagent runs, so a rule written only about them describes ~1% of the spend.

Companion edits, same land: `skills/frontier-routing/SKILL.md:35` and `frontier-run/SKILL.md:46`
(the two *"the lead never runs on it"* sentences) get the stage-2 carve-out and a pointer here.

**NOT proposed:** any policy sentence about stepped-down assignee effort. See §5 — untested on
Opus 5, and the nearest measurement contradicts it.

### Recommendation and conviction

Split, because the parts have very different evidence:

| | Recommendation | Conviction | Why |
|---|---|---|---|
| **R1** | Land the CLAUDE.md diff above (reconcile the policy with measured practice; state the trigger as F2's third branch; name the missing chokepoint honestly) | **92%** | The three sentences are *measurably false* — 52 lead sessions, 1 command invocation, an uncapped path. Leaving text that describes ~1% of the spend is worse than any candidate replacement, and the diff adds a bound where there is none. |
| **R2** | Extend `frontier-spawn-gate.sh` to the session/fire path | **93%** | Pure safety gap; the only real bound. Not built here (outside this brief's scope) — **filed**. |
| **R3** | Make the ladder fire **automatically** on every T-a∧T-b∧T-c | **72%** | One trial, **no control arm**. The cheap refuting experiment — same brief into a fresh *Opus 5* recycle — was never run, and 2 of the 9 refutations are plainly fresh-context effects. Per F2 this is the operator's, WITH the number. |
| **R4** | Encode stepped-down assignee effort | **REJECT** | Untested on Opus 5; the one same-repo certification points the other way for search-heavy work. Probe designed in §5. |

**What I would do:** land R1, file R2, run the §6 control arm before R3. R3 is the one genuine
operator decision, and it is a small one: *does the ladder fire on its own, or does it stay a
recipe a session chooses?* R1 makes the recipe correct and available either way.
