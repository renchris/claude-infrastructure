# A — Vendor exit paths for a teammate child process (2.1.260 vs 2.1.220)

**Subject**: `claude.exe --agent-id <n>@session-<t> --agent-name <n> --team-name <t> --parent-session-id <p>`
(argv built at `260:30776919` / `220:19960676`; a *pane-backed* teammate is a separate OS process, and the
lead still registers a task of type **`in_process_teammate`** for it — the type name is a misnomer and is the
single biggest source of confusion in this subsystem).

**Instrument**: `strings -a` dumps of the two Bun/Mach-O binaries. Offsets below are **byte offsets into
`cc260.strings` / `cc220.strings`**, not into the Mach-O. Reproduce any row with
`python3 -c "d=open(P,errors='replace').read(); i=d.find(N); print(d[i-1500:i+1500])"`.
Everything marked **[E]** is empirical (literal read out of the binary); **[I]** is inferred.

**Backends** (`Cyt(e)` = `e==="tmux"||e==="iterm2"`, `260:15479307`): `killPane` is
`tmux kill-pane -t <pane>` (`260:30660996`) or `it2 session close -f -s <sessionId>` (`260:38286531`);
`backendType:"in-process"` has **no pane** and `Cyt` is false for it.

**Team file** = `<teamsRoot>/<sanitized-team>/config.json` (`ire()`, `260:15479505`); written whole,
`JSON.stringify(...,null,2)`, under a lockfile or storage-v5 CAS (`RV`/`H`, `260:15481000-15482100`).

---

## The table

| # | Path | Trigger | Runs in | Pane action: in-process \| tmux \| iterm2 | `teams/<t>/config.json` mutation | 2.1.260 offsets | Same in 2.1.220? |
|---|---|---|---|---|---|---|---|
| **P1** | `shutdown_response {approve:true}` → `zs()`, member's `backendType==="in-process"` | teammate's own model calls SendMessage | **teammate** (= the lead, for a true in-process agent) | n/a \| n/a \| n/a — `abortController.abort()` on its own task record | none here; removal happens in P5/P6 | `29616171` (`handleShutdownApproval`), `29616378` (`z_n{requestId,from,paneId,backendType}`) | **yes** — `oJ_`, `220:20491080` |
| **P2** | same, **pane-backed**, *fallback* arm: an `in_process_teammate` task with a live `abortController` is found in this process's AppState | as P1 | **teammate** | — \| `abort()` → the spawn-time `abort` listener fires `killPane` \| same | none directly | `29616734` (in-process arm), `29616900`–`29617100` (fallback arm); listener at `260:30781519` + `if(n.register(D),k)C.signal.addEventListener("abort",…)` | **yes** — `220:19964781` |
| **P3** | same, **pane-backed**, normal arm | as P1 | **teammate** | — \| **`setImmediate(()=>Rn(0,"other"))` → full graceful self-shutdown of its own process** \| same | **none** — the teammate never edits the team file on the way out | `29617342`; `Rn` = `B$().shutdown(e,"other")` at `21278128` | **yes** — `Ps(0,"other")`, `220:20492137`, `Ps` def `220:23147913` |
| **P4** | `shutdown_response {approve:false}` → `Ks()` | teammate declines | teammate | nothing | none | `29617500`–`29617800` | yes (`iJ_`) |
| **P5** | Lead's TUI **InboxPoller** sees `shutdown_approved` | P1–P3 wrote the frame to `team-lead`'s inbox | **lead** | skipped if no `paneId`/`backendType` \| `killPane(paneId,!insideTmux)` \| same | **`ape()` removeTeammateFromTeamFile** (filter by agentId **or** name) + `nAe()` unassigns that member's open tasks (`owner:undefined,status:"pending"`) and returns `"<n> has shut down."` | `36415488` (kill), `36417319` (`ape`), `36417387` (`nAe`); defs `15484193`, `15170780` | **yes** — `220:30911640` / `30913529` |
| **P6** | Lead's **print.ts** (headless `-p`) poll loop sees `shutdown_approved` | as P5 | **lead** | **no killPane at all on this path** — only member removal | `ape()` + `nAe(...,"shutdown")` + drop from `teamContext.teammates` | `32721071`, `32721228`, `32721320` | **yes** — `220:31752691` |
| **P7** | **TaskStop** (`task_id` = agent id, bare name, or `name@team`) → `k2t.kill` → `Ugt()` | lead's model, or user | **lead** | `abort()` only \| `paneTeardown()` = `killPane`, bounded **10 s** (`VLn=1e4`) \| same | **`L5e()` removeMemberByAgentId** with `onlyIfJoinedBefore:Date.now()` (stale-removal guard) | `19133830` (`InProcessTeammateTask`), `19133984` (`Ugt`), `19133976`, `19134464`, `19135212` | **yes** — `Qsn`, `220:19930988`, `JEd=1e4`, `Zrn` `220:18121264` |
| **P8** | Task-panel **kill / dismiss** (`uD`) | user, in the lead's task UI | **lead** | identical to P7 (calls `Ugt`); if not running → `registry.remove()` = "dismissed", **no** config.json write | as P7 when running; none when dismissing | `35511785` | yes (structurally) |
| **P9** | "stop background agents" bulk sweep (Esc/Ctrl-C affordance) | user | **lead** | calls `Ugt` per `in_process_teammate` ⇒ as P7 | as P7 | `35513938` (`Background agent "…" was stopped by the user.`) | yes (structurally) |
| **P10** | **Lead process shutdown** — `/exit` (`Rn(0,"prompt_input_exit")`, `35058165`), SIGINT→`shutdown(0)`, SIGTERM→`shutdown(143)`, SIGHUP→`shutdown(129)`, orphan check (30 s, stdout unwritable)→`shutdown(129)`, uncaught-exception breaker→`shutdown(1)` | any of the above | **lead** | `cleanup.drain()` runs `cleanupSessionTeams` → for every member with `name!=="team-lead"` **and** `Cyt(backendType)`: `killPane` \| \| — **raced against a 2000 ms budget** | **the entire `teams/<t>/` directory is `rm -rf`'d** (`J()`), after removing each member's worktree | `21266800` (`class cpr`.install), `21274536` (`shutdown`), `11383510` (`Qge=2000`), `11383523` (`Tt`=cleanup.register), `24851074` (registration), `15487292` (`Qmr`), `15488124` (killPane), `15488468` (dir rm) | **yes** — `220:23147913` (same 2000 ms race at `220:23148290`), `UP_` `220:18123534`, registration `220:31274205` |
| **P11** | Headless lead, **stdin closes with live teammates** | `-p` input EOF | **lead** | none directly — injects a system-reminder prompt telling the model to `requestShutdown` each member, then **parks up to `CLAUDE_CODE_TEAM_TEARDOWN_PARK_TIMEOUT_MS ?? 10000` ms**, then tears down anyway (→ P10) | none directly | `32629904` (park ms), `32629292` (`pf` reminder text), `32703464` (`Input closed with active swarm…`), `32703906` (give-up log + `tengu_headless_team_teardown_park_timeout`) | **yes** — `Ikm`, `220:31700146` |
| **P12** | **Spawn rollback** — pane created, then a post-pane step fails | lead's Teammate spawn tool | **lead** | rollback closure `D(()=>killPane(A,!O))` fires | **`h_n()` removeTeamMember** (only if the failure is pre-commit; post-commit keeps the row) | `30776692`, `30774719`, def `15482101` | **yes** — `220:19960541` / `19958800` / `j0s` `220:18120346` |
| **P13** | **Teammate dies from outside** — its pane is closed (SIGHUP), `/exit` typed in the pane, SIGTERM, SIGKILL, crash | operator / OS / P5/P7/P10's own killPane | **teammate** | its own `cpr.install()` signal handlers → `shutdown(129/143/…)` → SessionEnd hooks; SIGKILL runs nothing | **NONE. The member row survives in config.json indefinitely**, with `isActive` frozen at its last value | handlers `21266800`; see § Findings 4 | **yes** |
| **P14** | **Agent-loop crash** (in-process runner only) | exception out of the agent loop | lead (that runner is lead-hosted) | task → `status:"failed"` | none | `30754778` — the **only** `completedStatus:"failed"` write in the binary | **yes** — `220:19949802` |
| **P15** | `idle_timeout` | **nothing** | — | — | would call `L5e()` — **unreachable** | `case"idle_timeout"` at `30746967`; `type:"idle_timeout"` occurs **0 times** | **yes** — `220:19943071`, also 0 constructors |
| **P16** | System sweep `wX()` (`--max-budget-usd` halt, SDK/IDE interrupt, `-p` wait ceiling) | budget/interrupt | lead | **does not reach teammates** — `lM(e)` admits only `local_agent`/`local_workflow` | none | `19144482` (`wX`), `18707975` (`lM`) | **yes** — `JTe`, `220:18537736` |

---

## Findings

**(a) `shutdown_response approve:true` — the actuator is a real `process` shutdown, in the teammate, and the
prior fleet doc understates it.** `zs()` reads the team file to recover its own `tmuxPaneId`/`backendType`,
mints `shutdown_approved{requestId,from,paneId,backendType}`, writes it to `team-lead`'s mailbox, and then
branches: `in-process` → `abortController.abort()`; **pane-backed → `setImmediate(()=>Rn(0,"other"))`**, i.e.
`B$().shutdown(0,"other")` — failsafe timer, cleanup drain, **SessionEnd hooks with `reason:"other"`**,
`process.exit(0)` (`260:29617342`, `21274536`). `SUBAGENT_LIFECYCLE_SIGNAL_DISCONNECT_2026-08-04.md` says *"the
only actuator is … `abortController.abort()`"* — that is the in-process arm only; the self-exit arm is present
in **both** binaries (`220:20492137`). **[E]** Two independent kills then race for a pane teammate: its own
`Rn(0,"other")`, and the lead's `killPane` on receiving the frame (P5). `killPane` is idempotent-ish (returns
`code===0`), so the loser just reports failure. **[I]**

**(b) Lead death.** Every `shutdown()` path drains the cleanup registry, which holds `cleanupSessionTeams`
registered unconditionally at init (`260:24851074`). It `killPane`s every pane-backed member and then
**deletes the whole team directory** — config.json, mailboxes and all. Two hard caveats: it is **raced against
a 2000 ms budget** (`Qge`, `260:11383510`) inside which it must dynamic-`import()` two chunks, register
backends, and shell out once per member — plausibly exceeded for a wide team, in which case panes survive with
their team dir already gone **[I, unmeasured]**; and SIGKILL of the lead runs none of it. The headless lead
additionally parks ≤10 s asking its own model to shut the team down first (P11). **[E]**

**(c) There is no idle timeout anywhere.** `type:"idle_timeout"` has **zero constructors in both binaries**;
the poll loop computes a last-activity stamp `c=Date.now()` and never compares it (`260:30744206`). Every
`idleTimeout`/`IDLE_TIMEOUT` string in the binary belongs to an unrelated family — `CLAUDE_STREAM_IDLE_TIMEOUT_MS` /
`CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS` / `API_FORCE_IDLE_TIMEOUT` (HTTP stream watchdogs),
`CLAUDE_CODE_MCP_TOOL_IDLE_TIMEOUT`, Bun's `ERR_{POSTGRES,MYSQL,REDIS}_IDLE_TIMEOUT`, QUIC `max_idle_timeout`,
`grpc.client_idle_timeout_ms`. `evictAfter` (`Xw=30000`, `zze=3000`, `260:18708727`) gates **only** removal
from the in-memory task map and requires an already-terminal `status` (`260:18712634`, `18713760`) — it can
never end a process. **[E]**

**(d) TaskStop.** Resolution accepts `name@team`, a bare teammate name, or the task id (`260:14934786`), then
`k2t.kill` → `Ugt()`: abort the record, call `paneTeardown()` (= `killPane`) bounded at 10 s, drop the member
from `teamContext.teammates`, **`removeMemberByAgentId` from config.json**, mark the task `killed`, evict after
3 s. For a pane teammate the abort is cosmetic — the binary says so itself: *"the backend could not find/kill
the pane; its separate `claude --agent-id` process may still be running"* (`260:19134532`). So TaskStop is a
**pane kill plus a team-file edit**, not a signal to the teammate's model. **[E]**

**(e) After a turn.** A pane teammate is an ordinary REPL process; nothing special happens. Its `Stop` hook
(id `teammate-idle-notification`, 10 s timeout, `260:35335038`) sets `isActive=false` in config.json and mails
an `idle_notification` to `team-lead`. It is then woken by its own **InboxPoller at 1 Hz** (`fIo=1000`,
`260:36402287`; 500 ms in `-p`), which classifies inbound frames and, when `Ji()` (self is an agent) is true,
**delivers `shutdown_request` to the model as an ordinary prompt** — confirming that a shutdown request is
advisory and model-mediated at the code level. Permission responses, plan-approval responses and plain messages
wake it the same way; `team_permission_update` and `mode_set_request` are dropped from the inbox by policy.
On re-entering a turn it writes `isActive=true` (`260:36318391`). **[E]**

**(f) Deltas 220 → 260.** Every *path* above is structurally identical. Three real changes:
1. **`idle_notification` gains `result`** (`260:15182786`; absent from the 220 schema at `220:18150949`) — the
   teammate's last assistant text, truncated at 4 000 chars per frame and 16 000 per drain, with
   `senderReachable` (new; 0 occurrences in 220) choosing the truncation wording. The lead's panel renderer now
   destructures `{…,summary,completedTaskId,result,expanded}` and renders the result body when expanded
   (`260:34681718`). **This is the first real payload on the completion channel.** `completedTaskId` still has
   **no producer**, and `completedStatus` is still written only as `"failed"` on the crash path (`260:30754778`).
   The green *"✓ Teammate @X finished"* at every turn boundary is **unchanged** in 2.1.260.
2. **The text renderer `JSb`/`Mda`** (`"Agent idle · Task N · Last DM:"`, `220:26016559`) is **gone** in 260 —
   `"Agent idle"` has 0 occurrences. That accounts for `teammate_terminated` dropping 9→5.
3. Plumbing: storage-v5 handles threaded through every team-file mutation; `degradedClass:"mailbox_write_failed"`
   surfaced on the approval result; SessionEnd hooks take `({id,project}, reason, opts)` instead of `(reason,opts)`;
   lifecycle moved into a `cpr` singleton with `ownsControllingTerminal` SIGHUP handling.

---

## Adversarial pass — what would show these paths do *not* exist

| Claim | Falsifier I ran | Result |
|---|---|---|
| "no vendor idle auto-shutdown" | grep for `type:"idle_timeout"` constructors; every `evictAfter` comparison site; every `killPane` call site (only 4 + 2 backend impls); `wX`'s admission predicate | all negative — no timer path reaches a teammate **[E]** |
| "a teammate's exit doesn't reap its siblings" | `initializeSessionTeam` is the **only** caller of `registerTeamForSessionCleanup` (`260:37511257`) and is gated `if(zr() && !ke() && !U.agentId)` (`260:24771082`; `220:31296960`) — a `--agent-id` process **never registers a team** | confirmed: `cleanupSessionTeams` is lead-only **[E]** |
| "the lead kills panes on exit" | could be defeated by the 2 s `Qge` race, by `Cyt` excluding the backend, or by `getBackendByType` failing | the code path exists and is reached; **whether it completes within 2 s for N>2 panes is unmeasured** — see Uncertainties |
| "TaskStop doesn't signal the teammate's model" | looked for any mailbox write in `Ugt`/`k2t.kill` | none — it only aborts, kills the pane, and edits config.json **[E]** |
| "`shutdown_approved` is unforgeable by a teammate" | `SendMessage` blacklists hand-crafted lifecycle frames (`errorCode:9`, `260:29627823`) and the structured union is closed to `{shutdown_request, shutdown_response, plan_approval_response}` (`260:29605595`) | holds — but the blacklist omits `shutdown_approved` itself (it lists `idle_notification, teammate_terminated, task_assignment, task_completed, shutdown_rejected`) **[E, unexploited]** |

---

## Load-bearing consequences for our tooling

1. **A dead teammate leaves its row in `config.json` forever.** Enumerating `N5e`/`L5e`/`ape`/`h_n` call sites
   (`260:35334544, 35335200, 36318391` / `19135212, 30747114` / `32721228, 36417319` / `30774719`) shows **every
   removal runs in the lead**. No teammate-side path — not SessionEnd, not SIGHUP, not `/exit` — removes the
   member. So `config.json` membership is a record of *spawns the lead has not yet reaped*, never of live
   processes; `isActive` is a turn-boundary flag, not liveness.
2. **`isActive` is the closest thing to a vendor liveness bit, and it is wrong in the same two directions as
   `idleReason`** — set `false` at every `Stop`, `true` at every turn start, never touched on death.
3. **A graceful self-close is available and cheap**: the teammate's model sending
   `{to:"team-lead", message:{type:"shutdown_response", request_id, approve:true}}` exits its own process
   *and* gets its pane killed *and* gets its config.json row removed *and* unassigns its open tasks — the full
   teardown, in one tool call. Nothing else in the vendor surface does all four.
4. **`SessionEnd` in a teammate is the one reliable terminal hook**, and its `reason` discriminates the cause:
   `"other"` = self-close via shutdown approval (P3); `"prompt_input_exit"` = a human typed `/exit` in the pane;
   signal-driven exits also land as `"other"` with exit codes 129/143. Enum at `260:12142871`.

## Uncertainties / not measured

- Whether `cleanupSessionTeams` finishes inside its 2 000 ms budget for a real N-pane team **[I]** — this is the
  single highest-value dynamic measurement left, and it decides whether "lead dies ⇒ panes die" is true in
  practice. Probe: fire N teammates, `kill -TERM` the lead, count surviving `--agent-id` processes.
- `[InboxPoller] Killed pane` is dispatched in a floating async IIFE that is **not awaited** before the member
  removal (`260:36415488`) — so on a lead that exits immediately after processing an approval, the pane kill can
  be cut off. Unmeasured.
- `Ji()`/`LC()` were resolved from their definitions (`260:12829109`, `12830257`) rather than observed at runtime.
- The `shutdown_approved` gap in the SendMessage lifecycle-frame blacklist is a code reading only; I did not test
  whether a plain-text `shutdown_approved` from a teammate would be parsed by the lead's poller. **Do not test
  this against a live team.**

---

## § Two version deltas found during the retracted follow-up

*Context: a sibling axis reported a +120 min lag on `TeammateIdle` in 2.1.260. That premise was **retracted** —
a timezone artifact (log CDT UTC-5, conversion assumed UTC-7); the lead re-measured 12/12 recent 2.1.260
closes at 2-3 s after the teammate's last transcript record. No timing claim below depends on it. These two
findings are version deltas read from the binaries and stand on their own.*

### Item 1 — `TeammateIdle` fires in the TEAMMATE, not the lead **[E]**

This **corrects** `docs/research/SUBAGENT_LIFECYCLE_SIGNAL_DISCONNECT_2026-08-04.md` § "The lever we actually
control", whose table row reads `TeammateIdle | **NO — fires in the LEAD** | it is the lead's *trigger* …;
the teammate never sees it`. Three independent reads say otherwise, and this is true of **both** binaries:

- Vendor hook documentation, verbatim: *"When a teammate is about to go idle … Exit code 2 — show stderr to
  **teammate** and prevent idle (teammate continues working)"* — `260:41436937`, `220:27113357`.
- The call site is inside the **teammate's own** turn-end Stop generator `p2n`, guarded by `if(Ji())`
  ("this session has an agentId + teamName", `260:12829109`): `let lr = ugn(Mt, bn, …)` at `260:19651530`,
  where `ugn` = `executeTeammateIdleHooks` (`260:20842361`). 220's counterpart: `let re = Ron(B, j, …)` at
  `220:18427529`.
- Its refusal record names the teammate as the audience: `hook_stopped_continuation` with
  `hookName:"TeammateIdle"` (`260:19651911`, `220:18427857`).

**Consequence for fleet tooling:** a `TeammateIdle` hook is a *teammate-side* lever, in the same position as
`Stop`, and its exit 2 prevents the teammate going idle. Anything written on the assumption that it is the
lead's wake-up trigger — including the 2026-08-04 doc's rule *"Idleness may be a TRIGGER. It may never be a
PREMISE."* as applied to this specific event — is aimed at the wrong process.

### Item 2 — 2.1.260 adds a third population source to the turn-end blocking accumulator

The accumulator (`Ce` in 260, `T` in 220) short-circuits the teammate's turn-end chain **upstream of**
`executeTeammateIdleHooks`, the `teammate-idle-notification` function hook and therefore the `isActive:false`
write and the `idle_notification` to the lead:

```js
if (Me) return yield* ex(f, U.messages, {stopHookActive:E}), {blockingErrors:[], preventContinuation:!0};
if (Ce.length > 0) return {blockingErrors:Ce, preventContinuation:!1};   // 260:19650647 — and NO ex() here
if (Ji()) { …TaskCompleted…; let lr = ugn(Mt, bn, …); … }                // 260:19651530 — TeammateIdle
```

220 has the byte-equivalent shape (`220:18426723` → `220:18427529`), so **the early return is not new.**
What is new is a third way to fill the accumulator:

| source | 2.1.220 | 2.1.260 |
|---|---|---|
| hook returned `blockingError` | `T.push(…)` `220:18425343` | `Ce.push(…)` `260:19649162` |
| hook returned `additionalContexts` | `T.push(…)` `220:18425791` | `Ce.push(…)` `260:19649705` |
| **the yielded message IS a `hook_blocking_error` attachment** | **absent** — loop is `if(B.message){…; yield B.message}` with no push (`220:18423645`) | **`if(yield Mt.message, Fct(Mt.message) && wFe()) Ce.push(Mt.message)`** (`260:19647021`) |

- `Fct(e)` = `e.type==="attachment" && e.attachment.type==="hook_blocking_error"` (`260:19640039`).
- `wFe()` = `WCe() && I("tengu_joyful_globe", !0)` (`260:19609016`) — remote flag, **defaults true**.
  `tengu_joyful_globe` has **0 occurrences in 2.1.220** (`260`: `7761313`, `19608996`).

**What a fleet Stop hook must do to stay out of it — exit 0 and emit no blocking verdict.** Traced through
the script-hook runner, for `type:"script"` hooks (what `settings.json` `hooks.Stop` entries are):

| hook behaviour | runner outcome | attachment | hits the accumulator? |
|---|---|---|---|
| `exit 0` (stdout ignored or benign JSON) | `success` | `hook_success` (`260:20904014`) | **no** |
| `exit 2` | `blocking` (`260:20904701`) | `hook_blocking_error` | yes — **in both versions** |
| JSON stdout `{"decision":"block", …}` at exit 0 | `blocking` via `nme` (`260:20850509`) | `hook_blocking_error` (`260:20855931`) | yes — **in both versions** |
| JSON `{"continue":false}` / `additionalContext` | `preventContinuation` / `additionalContexts` | — | yes — **in both versions** |
| any other non-zero exit | `non_blocking_error` (`260:20905300`) | `hook_non_blocking_error` — a **different** attachment type that `Fct` does **not** match | no |
| a script hook that could not RUN on a guarded event | `blocking` via `tEt` (`260:20857644`) — *"did not run (…) — a … guard that cannot run blocks"* | `hook_blocking_error` | yes |

⇒ **The rule for our hooks: `exit 0`, and never emit `decision:"block"`, `continue:false` or
`additionalContext` on a turn where the teammate's idle notification matters.** A `session-continue.sh` /
`completion-assert.sh` that blocks a teammate's Stop costs that teammate its `TeammateIdle` fire, its
`isActive:false` write and its `idle_notification` — **on 2.1.220 as well as 2.1.260**. Note the block is not
a delay: the query loop re-runs the turn with the feedback appended (`260:19768986`), and the fire lands on
whichever later turn ends clean; the cap-override path (`260:19769262`) ends the turn calling only `ex()`
and never re-enters `p2n`, so it fires on **no** turn.

**Observation in a teammate transcript that shows it happened:** the record
`{"type":"attachment","attachment":{"type":"hook_blocking_error", …}}` at the turn boundary. It is `yield`ed
*before* being pushed (`260:19647021`), so it is written to the teammate's JSONL even on the suppressed
path, and it names the hook. Its **absence** on a clean turn end, paired with an `idle_notification` in the
lead's `teams/<t>/` mailbox timestamped at that boundary, is the negative control. The positive control that
the fire *did* happen is `{"type":"hook_stopped_continuation","hookName":"TeammateIdle"}` (`260:19651911`) —
that record is only constructible after `ugn()` ran.

⚠️ **Honest residual on item 2, stated rather than buried.** Every path I traced that produces a
`hook_blocking_error` attachment *also* sets `blockingError` on the same yield — `nme` returns
`message: N.blockingError ? hook_blocking_error : hook_success` (`260:20855931`), and the exit-2 branch
yields `{blockingError, outcome:"blocking"}` (`260:20904701`). **I could not construct a case where the new
`260:19647021` push fires alone**, so on the evidence it is a *redundant second count* of an event 220
already caught via `blockingError`, not an independently new suppression. The delta is real in the code and
the flag is real and 260-only; the behavioural reach is **unestablished**. Treat item 2's table (what a hook
must do) as the load-bearing part — that holds for both versions — and the 19647021 push as an open
question. Falsifier: find a runner path yielding a `hook_blocking_error` attachment with
`blockingError === undefined`; if none exists, this row is cosmetic.
