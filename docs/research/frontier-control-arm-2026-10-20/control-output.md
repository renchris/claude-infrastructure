Read-only replay: nothing was written, committed or sent. The machine capacity gate refused two of my three planned subagents, so I ran the harness-binary and incident-transcript checks myself. The fleet-wide correlation ran as a read-only subagent, and I spot-checked its headline finding.

---

## W1 — Fable 5.1 discovery (T5)

**Model of record:** this pass ran on `claude-opus-5-5`, the default tier, not Fable 5.1. If a frontier-tier pass is still wanted, treat this section as its input, not a substitute.

**Evidence rules:**
- **Harness binary:** claims are read from the incident's own harness, `~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe` (`"version": "2.1.260"`, installed 2026-09-03). Drift is checked against 2.1.220 (`~/.claude-220`, installed 2026-08-01). Later installs (2.1.280 and up, from 2026-09-22) fall outside the window and are not used. Offsets are byte offsets from `mmap.find`.
- **Transcripts:** only records before 2026-09-09T18:07Z.
- **Fleet numbers:** a read-only probe over all four stores, 2026-08-10 → 2026-09-09T18:07Z. Records are deduplicated by `uuid`: 70 synthetic-error records appeared in two stores, leaving 260.

### The answer

The framing assumed a non-quota interruption is a new kind of death that needs a new detector. The disk shows three things that contradict this:

1. **The 09-09 "network outage" was almost certainly the machine sleeping.**
   - No session on the box wrote a single real model record from 14:38:39 to 17:22:51Z. Records appear only in short bursts about every 17 minutes, which looks like dark wakes.
   - All 25 ENOTFOUND clusters in the last 30 days sit inside machine-wide silences like this one.
   - This is INFERRED: nothing on disk says "sleep" directly (E9).
2. **The harness already classifies and announces every turn-ending error.**
   - The `error` field is a closed set.
   - `StopFailure` is a hook event that matches on that field, and a handler for it already landed here.
   - The harness itself reports, on resume, that delegated units died with their process.
3. **The missing piece is the moment of re-entry, not detection.**
   - Every observed recovery re-entered the turn from context.
   - The fix is to run the disk audit in a hook and put its verdict table into the wake message. The model's first context after a death is then the ledger, not its own narrative.

**Recommended design: Reconcile at Re-entry (§ a).** It needs no new death classes, no new regexes and no record-age liveness checks.

### New evidence

| # | Fact | Receipt |
|---|---|---|
| E1 | `error` is a closed set and is `StopFailure`'s documented matcher field | 2.1.260: `StopFailure:{summary:"When the turn ends due to an API error",description:"Fires instead of Stop when an API error (rate limit, auth failure, etc.) ended the turn. Fire-and-forget — hook output and exit codes are ignored.",matcherMetadata:{fieldToMatch:"error",values:["rate_limit","overloaded","authentication_failed","oauth_org_not_allowed",…?["account_on_hold"]:[],"billing_error","invalid_request","model_not_found","server_error","max_output_tokens","unknown"]}}` |
| E2 | Message spellings drift faster than the `error` set. 2.1.220's matcher list has 10 values (no `account_on_hold`); 2.1.260's has 11. `server_error` is in every version | `"Can't reach the API server"` is absent from 2.1.220 and present in 2.1.260. 2.1.220's "Connection interrupted by system sleep" is absent from 2.1.260, which uses "went to sleep mid-response". Corpus records also carry spellings absent from 2.1.260 ("Response stalled mid-stream", "Connection closed mid-response") |
| E3 | The census regex misses most transport deaths | `NET_RE` (`lr-fleet.sh:94`) against six live 2.1.260 spellings: MATCH on "Can't reach the API server… (EAI_AGAIN)" and "Connection refused… (ECONNREFUSED)". MISS on "Connection dropped (ECONNRESET)", "No internet route… (ENETUNREACH)", "Unable to connect to API. Check your internet connection" and "Request timed out…". Of the corpus's 92 transport records (`server_error`, no HTTP status), its alternatives reach only the 52 DNS rows. The other 40 are ECONNRESET 9, TLS/cert 10, closed/lost mid-response 9, stalled mid-stream 10, sleep 1, server mid-response 1 (matched by sub-class) |
| E4 | The `error` field separates quota exactly, and the status separates transport from API replies | `rate_limit` = 102 records = the 102 records with limit text. `server_error` + `apiErrorStatus:null` = 92 transport records; `server_error` + 529/500 = 31 server replies. `unknown` was 3 of 3 HTTP 400s (unsupported model; empty text block), so it is deterministic, not transient |
| E5 | The stall watchdog fires only on a silent stream with no tool in flight | 2.1.260 @163621546: ``if(Zt.size>0){t(`[AsyncAgent ${e}] stall watchdog deferred — ${Zt.size} tool(s) in flight…`),Nn();return}``. Workflow slot: `tr=180000,Gn=5` (180 s, 6 attempts). A schema loop is named at the throw site: "— N StructuredOutput validation failure(s) on the last attempt" |
| E6 | Delegated units run in-process | 2.1.260 @177063730: "Background agent "…" was running when the previous Claude Code process exited and did not complete. Its in-process state was lost." `orphaned_on_resume` appears 4 times |
| E7 | While background work runs, the goal check-in gives up after 3 tries | 2.1.260 @164237445: every `CLAUDE_CODE_GOAL_CHECKIN_MINUTES` (default 30), backoff ×2 up to ×4, capped at 3, then "· idle check-ins paused until your next message … Claude Code won't wake this session for another check-in until the user sends a message". The check-in text leaves stuck-or-progressing to the model: "If they are progressing, say so briefly and keep waiting; if they are stuck … fix or stop them" |
| E8 | 52e35019, workflow `wf_acd6923d-9c5` | `<status>failed</status>`, `<duration_ms>42825639</duration_ms>` (11h53m), `agents_done 3, agents_error 2`, `[security] failed: You've hit your session limit` (05:15:48Z), "agent stalled on all 6 attempts (no progress for 180000ms each)". Fixer slot (journal key `v2:a990db…`): attempt 1 ran 13:07:38→15:04:37, 484 records, peak context 341,373 tokens, last assistant record 14:36:24. Attempts 2–6 each restart from the 29,815-char original brief, write 7 records and zero assistant output over about 17 min, and end in `[Request interrupted by user]`. Journal: `started`×10, `result`×3, `failed`×2 |
| E9 | Sleep, not wifi (INFERRED) | My spot check over all four stores: `REAL assistant records in 14:38:39-17:22:51: 0`; 10-minute buckets of all records 2/30/12/7/13/7/7/18/2/20, then 423 and 1663 after wake. From the probe: records fall only at about 17-minute instants (14:46, 15:04, 15:21, 15:38, 15:55, 16:12, 16:27, 16:39, 16:56, 17:12); a 120 s Bash timeout returned 9m42s late; the fixer's logged attempt durations were 7019/1013/1044/1023/977 s |
| E10 | The death record marks the end of the silence, not its start | 137f37fe: last record 15:38:54, then ENOTFOUND at 17:12:15. 52e35019: notification 16:27:40, then ENOTFOUND at 17:19:10. Two subagents of d85264e5 were killed at 15:04:37. Their notifications were enqueued (`queue-operation`) at 15:04:37 and delivered at 16:56:50, 0.3 s after their lead's own ENOTFOUND |
| E11 | Observed recoveries reconciled from context, and neither ran `lr-audit.py` | 52e35019 at 17:36:47: "3 of 5 agents returned, security failed, and the harness retried it into a stall". The stalled unit was the fixer, not security. 137f37fe at 17:29:38: ran its own `ps` and concluded "No halted work — every background task returned a verdict" |
| E12 | `lr-audit.py` reads none of the harness's own terminal events | `grep -c` is 0 for `task-notification`, `"failed"`, `run_in_background`, `Monitor` and `background shell`. The journal parser keeps only `started`/`result` (:439, :441), so the fixer's 6 attempts become 6 separate gaps. The watchdog's `[Request interrupted by user]` marker (:232) yields INTERRUPTED, "TaskStop / user" (:288) |
| E13 | The teammate RUNNING verdict is a record-age check | `TEAM_ACTIVE_WINDOW_S = 300` (:87); `if age is not None and age < TEAM_ACTIVE_WINDOW_S` → RUNNING (:879) |
| E14 | The autonomous half is still quota-only, and its actuator types into panes | `lr-reset-poller.sh:740` selects only "You've hit your (session\|weekly) limit". `lr-audit.py:332` records `limit_events` only on `error == "rate_limit"`. The nudge types `/limit-recover` via `it2 session run` (:620). At 13:05:14Z a `/limit-recover` prompt reached 52e35019's stale copy (pid 80874) while pid 77720 carried the session; `handed-off-session-guard.sh` blocked it ("Original prompt: /limit-recover") |
| E15 | The trigger exists but is unregistered | `hooks/stop-failure-marker.sh` (landed `53edbbcf3`, 2026-09-06) writes `~/.claude/autonomy/stop-failure/<error>__<account>.jsonl`. `migrations/0019-hook-surface-registration.sh` registers it (class c10, staged 2026-09-07, operator-run). Line 42 of 0019 says "StopFailure has no matcher dimension"; E1 shows it has one |
| E16 | `asyncRewake` is a per-hook flag | Runs in the background and wakes the model on exit 2 (`hooks/mailbox-wake-arm.sh:5-10`, proven on 2.1.219/2.1.220). Watcher term is 14340 s (:194). "the harness dedupes NOTHING" (:20-22). Not honored in a plain one-shot `-p` (:59 HEADLESS ONE-SHOT GUARD) |
| E17 | Owner identity is already recorded | Registry row `{paneUUID, name, cwd, account, pid, startedAt}` (`hooks/session-register.sh:17`). `lr_registry_live_rows` only runs `kill -0` (`lr-lib.sh:126`), so a recycled pid reads as alive |
| E18 | A healthy idle state is recordable | 137f37fe assistant records: 20 `end_turn`, 366 `tool_use`, 1 synthetic `stop_sequence`. `is_error:true` marks only 4 of 165 tool results, so it can corroborate but not gate |
| E19 | Taint is real but sits after the wake, not during the outage | 0 network-failure tool results inside the 09-09 silence, because nothing ran. 2 genuine cases in 30 days, both `⚠ ship-land: fetch failed — using local origin/main | … Could not resolve host: github.com`, 3.7 and 13.5 min after API output resumed. Control case: a workflow agent hit `getaddrinfo ENOTFOUND` for an external site at 2026-08-25T21:09:23Z with the network fine, never mentioned it, and wrote "I have what I need. Writing up." |
| E20 | Stalls in 30 days | 4 stall notifications covering 5 units; 0 while other sessions were streaming. 7 of 10 synthetic "Response stalled mid-stream" errors did happen while others streamed: those are the only intrinsic stalls observed, and they are `server_error` records from the main loop and subagents, not watchdog kills |
| E21 | Fleet clusters | 80 network-class records form 42 clusters (gap > 10 min). 28 had zero real output anywhere within ±5 min; 2 sit at the tail of a long silence; 7 had other sessions streaming on both sides (all ECONNRESET or closed-mid-response, no ENOTFOUND); 5 had no control |
| E22 | Correction to Finding 2 | "11h 53m" is the workflow's own runtime (`duration_ms` 42825639), not a park. No "wait for it to finish" prompt exists in 52e35019 before 18:07Z; the string first appears after 20:00Z |

### (a) Design: Reconcile at Re-entry

**D1 Trigger: three structural sources, no message text.**
- **Lead death:** `StopFailure` (E1, E15).
- **Unit death:** the earliest terminal record the harness writes:
  - the `queue-operation enqueue` of a `<task-notification>`, which can be up to 112 min earlier than its delivery (E10);
  - that notification's `<status>`;
  - journal `failed` rows;
  - the orphan notice the harness writes on resume (E6).
- **Backstop, the quiescence invariant:**
  - A session is healthy-idle if and only if its last assistant record is non-synthetic with `stop_reason:"end_turn"` (E18), and every unit it launched has a terminal record or a live owner (D3).
  - Any idle session that is not healthy-idle is interrupted, whatever killed it.
  - This covers deaths that emit no event: kill -9, OOM, a kernel panic, a sleep ended by a watchdog kill, a duplicate process.
  - It defines health instead of listing failures, so a new death class cannot slip past it.

**D2 Route on `(error, apiErrorStatus)`, never on text.**

| Key | Class | Continuation |
|---|---|---|
| `rate_limit` (429), `billing_error` | QUOTA | existing limit path: wait or transplant |
| `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold` | AUTH | login-cliff branch |
| `server_error` with no status | BLACKOUT (sleep or network) | resume in place once ready (D4) |
| `server_error` 5xx, `overloaded` / 529 | API | resume once reachable; stagger re-runs (529 burst rule) |
| `invalid_request`, `model_not_found`, `max_output_tokens`, `unknown` + 4xx | DETERMINISTIC | never auto-retry; change the request (compact, split, recycle) |
| `unknown` with no status, or any value not in this table | UNROUTED | audit and surface; no automatic re-entry |

- **Text:** it only labels within a class, for example ENOTFOUND vs ECONNRESET in the report.
- **Drift test:** reads the installed binary's `StopFailure` `matcherMetadata.values` and fails when any value is unrouted. The 10→11 drift (E2) becomes a red test instead of landing silently in a default arm.
- **Scope:** comes free from the existing markers, which are keyed `<error>__<account>`. The same cause on two or more accounts in one window is machine-scoped; on one account, account-scoped.

**D3 Unit state (answers Q1).** Applies to every launched unit: Agent, Workflow slot, background Bash, Monitor, teammate.

| State | Test | Action |
|---|---|---|
| TERMINAL | a terminal record exists | existing verdict table, plus D5 |
| ORPHANED | no terminal record, and no live process that (i) holds this session, via registry row or resume census, (ii) has `startedAt ≤ launch timestamp`, and (iii) matches `(pid, lstart)` read under `TZ=UTC` | re-run; the harness itself says the state is lost (E6) |
| RUNNING | no terminal record, and such an owner is alive | never re-fire; wait for the harness's terminal record |

- **RUNNING sub-labels:** PROGRESSING (real records since the death), RETRYING (repeated `started` rows under one key, synthetic errors) or SILENT. These are labels only; they never decide alive or dead.
- **Escalation:** only when RETRYING against a non-BLACKOUT cause, or SILENT past the harness ceiling (Bash timeout + watchdog). The owner calls `TaskStop` on that task, which exists in 2.1.260 and writes a terminal record, then re-runs. The actuator decides; the predicate never guesses.
- **Teammates:** use the same test, with the teammate's own process as owner. The 300 s window (E13) becomes a label.
- **New terminal sub-verdicts:**
  - **SLEPT:** killed by the watchdog inside a machine-wide silence (D5). Re-run verbatim; it says nothing about the brief.
  - **STALLED:** killed by the watchdog while other sessions were streaming. Change the request before re-running.

**D4 Readiness is a positive read, never a timer.** Ready when (a) or (b) holds, and (c) also holds:
- (a) another session on the box has written a real assistant record after this session's death. This is free and proves the API path end to end;
- (b) an unauthenticated HTTPS request to the API host returns any HTTP status;
- (c) the git remote resolves. DNS for github.com lagged the API by up to 13.5 min (E19).

A probe that errors is not a verdict, so it never reads as "still down". It also requires a full wake, because work started during a dark wake is suspended again (probe P5 picks the read).

**D5 Silence window and taint.**
- **Blackout window:** machine-wide silence, meaning no real assistant record from any session in any store. It is bracketed by the last real record before it and the first real record after (E9). Never use the synthetic record's timestamp (E10).
- **Units killed inside the window:** SLEPT.
- **TAINT_SUSPECT:** complete units whose active span overlaps the window, or any tool call in the 15 minutes after it ends. Read output against brief as for VACUOUS_SUSPECT, and re-verify claims that rest on fetch, push, gh, WebFetch or MCP.
- **Ambiguous writes:** before re-running any write attempted in that span (push, land, PR, backlog change), re-read the remote. A client-side failure can be a server-side success.

**D6 Re-entry injection (answers Q5).** The deterministic part runs in a hook, not in the model.
- **Where:** extend the existing `asyncRewake` watcher (`hooks/mailbox-wake-arm.sh`, registered on SessionStart and Stop) with a second wake condition. Do not add a parallel watcher, because the harness deduplicates nothing (E16).
- **Wake only when all of these hold:**
  - this session has a `StopFailure` marker line newer than the watcher's arm time, of class BLACKOUT or API;
  - D4 says ready;
  - no user prompt has arrived since the death;
  - the watcher's claude ancestor is the transcript's current writer, not a superseded copy (E14);
  - the per-death wake budget is unspent (3, with backoff);
  - the machine admission gate admits.
- **Before waking:** run `lr-audit.py` (disk only, seconds) and exit 2 with:
  - the gap count;
  - one line per gap with its action;
  - RUNNING units by name, marked "do not re-fire";
  - the path to the full audit;
  - "re-read the world first (fetch, ledger)".
- **No keystrokes:** never type into live panes for BLACKOUT or API rows. The poller keeps only dead-pane (ORPHANED) sessions, routed through `lr-select.py`.
- **Kill switch:** `CC_REENTRY_WAKE=0`.
- **Why not wake from `StopFailure` itself:** its hook output and exit codes are ignored (E1). Probe P1 checks whether `asyncRewake` is honored on that event anyway, but the design does not depend on it.

**D7 Command surface (answers Q4).**
- Add `/recover` as the front door and keep `/limit-recover` as a permanent alias. Keep every path unchanged.
- Add `Mode: resume-in-place`.
- Add verdict rows RUNNING, ORPHANED, SLEPT, STALLED and TAINT_SUSPECT.
- Add iron rule 8: re-read the remote before re-running any ambiguous write.
- Rename the census KIND `network` to `blackout`.

**Rejected alternatives**

| Alternative | Why rejected |
|---|---|
| Widen `NET_RE` with more spellings | A denylist enumerates spellings, not the class (memory `denylist-enumerates-spellings-not-the-class`). It already misses 40 of 92 corpus transport deaths, and the spellings changed between 2.1.220 and 2.1.260 (E2, E3) |
| Extend the teammate record-age window to subagents and slots | Record age is not liveness (memory `liveness-proxy-cannot-be-output-age`). The watchdog defers during tool calls, so a healthy unit can stay silent for a full tool timeout (E5), and the teammate rule already misreads long tool calls (E13) |
| A heartbeat file per unit | In-process units have no OS identity. A heartbeat from inside the parent proves only the parent, and its absence is an age check again. Owner `(pid, startedAt)` plus a terminal record is stronger and already on disk (E17) |
| The poller types `/limit-recover` into live panes | Keystrokes land on whatever owns the pane. A permission modal consumes them as answers (`.claude/rules/agent-operating-lessons.md`, "Empty vs no-surface"), and on 09-09 the typed prompt hit a stale copy (E14). `asyncRewake` injects without keystrokes |
| Wake from the `StopFailure` hook | Its output and exit codes are ignored (E1) |
| Automatically re-prompt the turn on every `StopFailure` | Re-enters from context, the exact defect `/limit-recover` exists for (E11); loops on deterministic causes; wakes N panes at once |
| A separate `/network-recover` | One engine; the class changes only the continuation (D2) |
| Longer retries and timeouts | The dominant cause is suspension (E9, E21). Retries do not run while the machine sleeps, and longer timeouts stretch the post-wake hang, during which nothing is written to disk |

### (b) The six questions

**Q1, the RUNNING gap.** Liveness is decidable, and on its own it is the wrong gate.
- **Decidable:** background agents and workflow slots live inside the parent process and die with it (E6). A unit is alive if and only if the process that launched it is alive, which is D3's test on `(pid, startedAt ≤ launch)`, with no record age and no orphanhood.
- **Why the launching process, not the session:**
  - 52e35019 was held by two processes at 13:05Z: pid 80874, the stale copy, and pid 77720 (E14).
  - A resume carries no in-process workflow (E6), so the workflow that kept writing until 16:27Z can only have belonged to the older process (INFERRED).
  - Asking "is the session alive in its live copy" would have orphaned a running unit.
- **Wrong gate on its own:** what parked 52e35019 was a unit the harness correctly reported as running. The goal check-in said "background work still running" and then stopped after 3 tries (E7). So RUNNING never re-fires, but it always ends: the harness writes a terminal record within its own ceiling, and past that ceiling the owner uses `TaskStop` and re-runs.
- **Measured:** on 09-09, 0 delegated units spanned the silence. 8 ended inside it, each killed by the watchdog at a wake instant. The hazard that actually occurred was the reverse of Finding 5: healthy units killed, not live units doubled. The predicate is still needed for short blips (the 7 clusters with others streaming, E21) and for duplicate processes.

**Q2, stall.** A stall is a third channel for the same causes, not a third cause.
- **What a stall is:** the watchdog fires only on a silent API stream with no tool in flight (E5). So a stall is a dead socket (sleep, network), a server that never answered, or a schema loop.
- **Measured:** 4 stall notifications in 30 days, 0 while other sessions streamed (E20). 52e35019's six attempts were six dark wakes (E8, E9).
- **Re-firing:** correct, and it will not reproduce once the machine is fully awake and D4 passes.
- **Three structural separators:**
  1. **Control arm:** did any other session write real output during the stall's silent window? No: SLEPT or transport, re-run verbatim. Yes: STALLED, the request is the suspect; change it before re-running. Attempt 1 ran at 341,373 tokens of context, so split or compact.
  2. **Throw-site text:** a StructuredOutput-failure suffix means a deterministic schema loop; fix the schema or the brief.
  3. **Repetition:** the same unit stalling across attempts while the machine is awake.
- **Main-loop "Response stalled mid-stream" errors** are single requests and retry-class.

**Q3, a trigger without spellings.** Yes: D1 plus D2.
- `StopFailure` and the task-notification `<status>` are harness events.
- `(error, apiErrorStatus)` is a closed key, protected by the drift test.
- The quiescence invariant catches anything that emits nothing.
- Text never gates. The regex route is already failing on this corpus (E3).

**Q4, misnomer.** Yes in the name, no in the engine.
- **Engine is class-agnostic:** the audit, the verdict table and the iron rules apply to every death class; the class changes only the continuation (D2).
- **So:** one engine, a `/recover` front door, `/limit-recover` kept as a permanent alias.
- **Why not rename the paths:** the `~/.reso/limit-recover/` locks are read by eleven scripts (`hooks/handed-off-session-guard.sh:16`), and the poller types the literal (`lr-reset-poller.sh:620`).
- **Why not a separate command:** it would fork the iron rules.
- **Description:** the frontmatter `description:` at `commands/limit-recover.md:3` is what loads the procedure when the operator types "reconnected…". It should name classes ("the turn ended on any API error, a delegated unit failed or stalled, the process restarted or slept"), not spellings.

**Q5, zero-paragraph.** The design is D6. Failure modes of making it automatic, each with its guard:

| Failure | Guard |
|---|---|
| Flapping network, or a dark wake kills the resumed turn again, so the wake loops all night | D4 readiness including full wake; 3 wakes per death, with backoff |
| Thundering herd: N panes wake at once (6 in Finding 4; this pass's own spawns were refused at 9 mid-turn sessions against a ceiling of 8) | wakes pass the admission gate, staggered |
| Waking a session the operator meant to leave | stand down on any user prompt after the death; only `StopFailure` deaths qualify (Esc writes a user interrupt, not a `StopFailure`) |
| Double recovery: the operator types the paragraph and the watcher also fires | stand down on a user prompt; ledger lock (iron rule 6) |
| Doubling live units | D3 |
| Retry loop on deterministic causes | DETERMINISTIC and UNROUTED never wake |
| Keystrokes into a modal or a half-typed prompt | `asyncRewake`, no keystrokes |
| Two processes, two wakes, one transcript | only the current writer's watcher acts |
| Resuming onto a world that moved for hours | wake text opens with fetch and the ledger; D5 taint |
| Watcher fails silently ("loud into a dead log") | `StopFailure` markers are the durable record; the readout renders "N died BLACKOUT since T, M re-entered, K not" |
| No watcher alive (term 3h59m, E16) | quiescence census, plus the poller for dead panes |
| The model ignores the injected audit | measured: W2 acceptance replays the wake on the incident transcripts and checks that the first action after the wake is the verdict table |

**Q6, unknown unknowns:** see § (d).

### (c) W2 task breakdown

**Phase 0 for W2**

| Wave | Locus | Model / effort | Why |
|---|---|---|---|
| W2-0 probes P1–P6 | L (lead-inline) | Opus 5 / max | Minutes each, zero quota (throwaway config dirs); their results choose D6's branch and must be read together before any brief is written |
| W2-1 build A–F | T (6 teammates in their own worktrees) inside one dispatched session (S) | Opus 5 / medium | Implementing a solved design; at most 6 concurrent |
| W2-2 integrate G and acceptance replay | L | Opus 5 / max | One owner for `lr-audit.py` wiring; acceptance needs the whole picture |
| W2-3 registration H | operator (c10) | — | Edits `settings.json` |

**Lead budget:** hand off at about 50% after W2-1 merges. The succession point is this section plus the task table.

**Probes (W2-0).** Each prints its verdict. They must use streaming-input sessions, because `asyncRewake` is not honored in a one-shot `-p` run (E16).
- **P1:** is `asyncRewake` honored on a `StopFailure`-registered hook in 2.1.260? Positive control: an unauthenticated throwaway config dir fails deterministically (`docs/plans/HOOK_SURFACE_100P.md:746`).
- **P2:** does a Stop-armed `asyncRewake` watcher survive a turn that ends in `StopFailure`, and does its exit 2 wake the idle session? Fixture: `ANTHROPIC_BASE_URL` pointed at a closed localhost port.
- **P3:** which `(error, apiErrorStatus)` each fixture produces: closed port, unresolvable host, TLS mismatch. Expected: `server_error` with no status.
- **P4:** the largest wake text that reaches the model intact.
- **P5:** an unprivileged read that tells a dark wake from a full wake, and whether a background watcher gets CPU during a dark wake.
- **P6:** does `caffeinate -i -w <claude pid>` prevent idle sleep while work is in flight, and what happens on lid close? This is a physical step, filed as `cc-backlog needs … --class needs-human`.

**Teammates (W2-1).** Each brief is at most 150 lines, with these line ranges embedded.

| ID | Deliverable | Files and anchors | Size | Acceptance |
|---|---|---|---|---|
| A | Terminal-record ingestion | `lr-audit.py`: in `scan_lead_transcript` :301-396, parse `<task-notification>` (task-id, tool-use-id, status, failures, usage), including `queue-operation enqueue`; in the journal parse :439-441, read `failed` rows and group attempts by key; at the interrupt marker :232/:288, add a STALLED/SLEPT hand-off field; inventory background Bash and Monitor | ~300 LOC + tests | Fixture cut from 52e35019 `wf_acd6923d-9c5`: 3 COMPLETE; security NULL[rate_limit]; the fixer as 1 slot × 6 attempts; 0 INTERRUPTED blamed on the user |
| B | Owner predicate | new `scripts/limit-recover/lr-owner.py` (pure functions); `lr-lib.sh:116-137` gains a `(pid, lstart)` UTC check | ~250 | 4 cells {terminal, none} × {owner alive, dead}; recycled pid; two-process case (52e35019 shape); a teammate inside a 10-minute tool call reads RUNNING |
| C | Silence window and taint | new `scripts/limit-recover/lr-blackout.py`: machine-wide silence across the four stores; SLEPT vs STALLED; TAINT_SUSPECT including the 15-minute post-wake span | ~200 | At the cutoff: 09-09 window 14:38:38→17:22:51; d85264e5's two subagents SLEPT; 9a547759's 17:36:22 ship-land fetch failure TAINT_SUSPECT |
| D | Routing, census, poller | `lr-lib.sh`: new `lr_death_class`, plus a drift test that reads the binary's `matcherMetadata`; `lr-fleet.sh:86-115`: gate on envelope plus `error`, KIND = class; `lr-reset-poller.sh:735-760`: consume the class, no typing into live panes for BLACKOUT or API | ~200 | grep test shows no message-text regex in any gate; drift test goes red when a value is removed; census lists every session whose last assistant record is synthetic |
| E | Re-entry wake | `hooks/mailbox-wake-arm.sh`: second wake condition per P1/P2; D4 readiness; stand-down rules; wake budget; admission gate; wake text from the `lr-audit.py --md` summary; `CC_REENTRY_WAKE` | ~250 | P2 fixture: a dead session is woken with the audit in context, and stays asleep on a user prompt, a DETERMINISTIC class, failed readiness, or a superseded copy |
| F | Command and docs | new `commands/recover.md`; in `commands/limit-recover.md`: description :3, verdict table :114-125, Teams table :187-194, `Mode: resume-in-place`, iron rule 8 | docs | The description names classes, no spellings |

**Integration and registration.**
- **G (W2-2):** wire B and C into `lr-audit.py` `main` (:1290 onward) and `GAP_VERDICTS` (:84): add ORPHANED, STALLED, SLEPT and TAINT_SUSPECT; RUNNING is not a gap. Run the acceptance replay on 52e35019, d85264e5, 137f37fe and 9a547759 at the cutoff.
- **H (W2-3):** one `/tmp` script for the operator. It runs the staged 0019 migration (`StopFailure`) and the watcher registration, gated on `--confirm`.

### (d) What Opus 5 could not see

1. **The incident it was designing for was sleep** (E9, E21: 25 of 25 ENOTFOUND clusters fall inside machine-wide silences).
   - Nothing runs during the outage, so the "running gap" barely occurred: 0 units spanned the 09-09 silence.
   - The opposite did happen. The watchdog counts wall-clock time across suspension, so it killed every in-flight unit at a dark wake and wrote `[Request interrupted by user]`.
   - A workflow slot in flight at lid close is dead after about six dark wakes (~1.5 h), whatever it was doing.
   - "Reconnected to internet" most likely meant opening the lid.
2. **Stall is a channel, not a cause** (Q2).
3. **The trigger and the classifier already existed, unwired** (E1, E15). W0 widened a regex instead. On this corpus it reaches 52 of 92 transport deaths, and the spellings it keys on did not exist one minor version earlier (E2, E3).
4. **The death record is written when the silence ends** (E10): up to 93 minutes after the last real record. Any window keyed on synthetic timestamps is late, and notifications can arrive 112 minutes after they were queued.
5. **Liveness was the wrong question; progress is the right one.** The harness's own "running" check is what parked 52e35019 (E7).
6. **The teammate RUNNING verdict it planned to extend is itself the record-age check this repo rejects** (E13).
7. **The engine's verdicts are class-agnostic, but it is blind to the evidence** (E12). It reads no task-notification, no `failed` journal row, no background shell and no Monitor, though "background processes" are the first thing the operator's paragraph names. It also blames watchdog kills on the user.
8. **Network deaths can corrupt completed work; quota deaths cannot.** Here the taint comes after the wake, not during the outage: DNS for github.com lagged the API, and ship-land silently fell back to a stale `origin/main` (E19).
9. **The daemon half is still quota-only, and its actuator types into panes** (E14).
10. **One session can be two processes.** "Is the session alive" is not the same question as "is the unit's owner alive" (Q1).
11. **A harness retry of a workflow slot starts from scratch.** Each retry threw away attempt 1's two hours and 484 records (E8). A recovery re-run pays full price unless it seeds from salvage.
12. **The automation has to be the reconciliation, not the re-prompt.** Any auto-resume that re-enters from context reproduces the defect faster, and without the operator's warning paragraph. That includes one the harness might add itself. The audit has to be inside the wake.
13. **Two smaller corrections:**
    - "11h 53m" in Finding 2 is the workflow's runtime, not a park (E22).
    - `migrations/0019` line 42 says `StopFailure` has no matcher; it has one (E15).

### Open decision for the operator

**Should a session with in-flight delegated work hold a sleep assertion (`caffeinate -i -w <claude pid>`) so idle sleep cannot kill it?**
- **My recommendation:** yes on AC power only, at 70% conviction.
- **Why not higher:** the benefit is indirect (28 of 42 network-class clusters were machine-wide silences, E21), the battery cost is unmeasured, and lid-close behavior stays unverified until P6, which needs a physical step.
- **Options:**
  - on AC only;
  - always;
  - never, and rely on recovery after the fact.

### Task-table delta (for the lead to apply)

| # | Task | State |
|---|---|---|
| T5 | Discovery pass | DONE: this section (ran on Opus 5.5; see header) |
| T6 | Implement via Agent Teams | READY once the W2-0 probes return |
| T8 | Resume the 6 live panes | Unchanged. They are most likely sleep victims; resume-in-place is still right |
| T9 | W2-0 probes P1–P6 | OPEN |
| T10 | Registration (0019 + watcher) | Operator, c10 |
| T11 | Sleep-assertion decision | Operator |
