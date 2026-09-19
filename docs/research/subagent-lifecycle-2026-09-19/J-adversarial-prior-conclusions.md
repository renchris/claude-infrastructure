# J — Adversarial audit of the fleet's prior "why teammates don't close" conclusions, against 2.1.260

Offsets are into the strings dumps `…/scratchpad/cc260.strings` / `cc220.strings` (sibling D uses raw-binary offsets). Worktree = origin/main `adff31b2f`. Log = `~/.claude/logs/teammate-lifecycle.log` (2,153 September lines). `[G]` = sibling census `G-teammate-end-states.csv` (278 teammates: 136 on 220, 142 on 260).

## (i) Claim table

| # | Prior claim (source) | 2.1.260? | Evidence |
|---|---|---|---|
| 1 | Completion channel has no producer: `completedTaskId` assigned nowhere, `completedStatus` only `"failed"` on crash (SIGNAL_DISCONNECT §The code; memory shutdown-request…§ROOT CAUSE) | **partly** | Crash path still the only `completedStatus` writer (30754778); but the schema gained **`result:s().optional()`** (15182664) and the TeammateInit Stop hook now mails `{idleReason:"available",summary,result}` (35334625, telemetry `swarm_idle_result_delivery`). A completion-*content* channel exists. And the proof method died: **1,645 Bun bytecode chunks in 260 vs 8 in 220** — a bytecode chunk's literals live only in the constants table (`completedStatus`@7394293, `hold_evict`, `idle_timeout`@7394641), so "nowhere in the binary" is no longer decidable by grep. |
| 2 | `"available"` is a literal in the TeammateInit Stop hook `teammate-idle-notification`, fired every turn, also writes `isActive:false` | **yes** | 35334625 (`N5e(Se,Ee,!1,fe)`), hook id at 35335038 |
| 3 | Summary excludes messages to `team-lead` | **yes** | 15198947 `o.input.to!==ms` — moot now that `result` rides regardless |
| 4 | Lead renders each idle as green `✓ Teammate @X finished` with no information | **partly** | Wording survives (34681718 `"was interrupted":"finished"`), but the panel now destructures and renders `result` (`Zyt(xy,…)`) — the lead is shown the turn's result body |
| 5 | No idle timeout: `idle_timeout` never constructed, case body unreachable; `evictAfter` is a UI filter | **partly / undecidable** | `case"idle_timeout"` (30746971) exits the loop and de-registers the member — identical on 220 (19943127), so "unreachable" only meant "producer not found"; the waiter is now bytecode (constants carry `idle_timeout`@7394641). `Xw=30000` (18708740). Both are **in-process-runner** facts; the fleet does not run it. |
| 6 | `shutdown_request` is a prompt, not an actuator | **yes** | In-process: 30746154 "passing to model". Pane: the teammate's own InboxPoller enqueues it as a prompt (36415166 `_o→Co→N.enqueue({mode:"prompt"…})`) — still the model's call |
| 7 | Only actuator is the teammate's `abortController.abort()`; a lead receiving `shutdown_approved` "does nothing mechanical" | **NO — wrong for the fleet's shape on both binaries** | Lead InboxPoller kills the pane on `shutdown_approved{paneId,backendType}`: 260 @36415488, **220 @30911679**; `ITermBackend.killPane` = `it2 session close -f -s <id>` (38286501). The doc generalised the in-process branch. **New in 260:** the approving pane teammate exits its own process — `setImmediate(async()=>{await Rn(0,"other")})` (29617371; `Rn(0,"prompt_input_exit")` is the ordinary exit, `"other"` a SessionEnd reason @12142655); 220 only *said* "is now exiting" (20492234) |
| 8 | F-a: `Agent({name,isolation:"worktree"})` silently demotes to in-process | **yes, now in code** | 19024382+: teammate branch is `if(Ne&&E&&!Wt&&!PF(f,je)&&!C&&!ye)` — `C`=isolation, `ye`=**cwd**; either set ⇒ subagent path, no error |
| 9 | F-c: a pane cannot close by the member exiting — the runner execs a shell | **yes (fleet)** | `bin/cc-pane-runner:83` `exec "${SHELL:-/bin/zsh}" -l -i`. Vendor tmux does the opposite: `remain-on-exit failed` + `respawn-pane -k` (30659588). With #7's self-exit, every approved teammate on 260 becomes a bare-shell pane whose foreground no longer carries `--agent-name` |
| 10 | RE-MEASURED 08-10: composer guard `rc=67` refuses 100% of agent panes; no retry/escalation | **partly stale** | `AGENT-PANE/AGENT-NO-BOX/DEAD-PANE` arms shipped that day (`5f5fd7270`, `bin/it2-kitty:777,925,930`); rc=67 fell 57 (08-10) → 31 for all September; residue is the "unreadable / permission modal" arm (log 09-04 04:02:27). No retry still true (`teammate-auto-shutdown.sh:320-323`); those panes closed on a later TeammateIdle |
| 11 | `SubagentStop` unregistered; `hooks/subagent-stop.sh` inert | **yes** | settings.json hook events lack it; binary lists it (12142655) |
| 12 | Named = real child session; the three `--agent-*` flags are required together | **yes** | 24773039; plus two 260 refusals the fleet docs lack: `subagent_nested_teammate` ("team roster is flat") and `subagent_teammate_background_denied` (19024382+) |
| 13 | Memory THE SPLIT: mid-turn 3/3, idle 0/4; `TaskStop` de-registers without reaping | **partly** | `TaskStop` on a pane teammate = `Ugt` (19134169): abort + `paneTeardown()` = backend `killPane`, 10 s settle, logged "the backend could not find/kill the pane; its separate `claude --agent-id` process may still be running" — the vendor naming the shim failure. Idle 0/4 is a 2.1.219 measurement; 260's poller enqueues the request (#6). **[G]: 229/278 (82%) never received a `shutdown_request`** |
| 14 | R-8: `LCW_ORPHAN_CLOSE` default OFF, staged unactivated | **stale** | `10-lead-crash-orphan-close-activate.sh.done` exists; `~/.zshrc:674-675` sources `watchdog.env`; `LCW_ORPHAN_CLOSE=1` live in this shell |
| 15 | D1: shared-cwd gates defer forever; `MAX_DEFERS` backstop never discharges | **yes — the dominant fleet non-close today** | September: 62 `SHARED-CWD-NEVER-REAPS`, 81 "Pane NOT closed", 18 own-footprint holds (reap-guard rc 11 → `teammate-auto-shutdown.sh:978,996`) against 117 closes. Vendor applies **no git gate** on any close path |
| 16 | `TeammateIdle` fires in the LEAD | **yes** | `ugn` (20842427) runs inside the lead's query loop; 19652016 — the hook can `preventContinuation` on the **lead** |
| 17 | F-d: vendor teardown with lead alive, zero fleet log lines | **yes, now named** | InboxPoller approval → `yIo` removes the member, mints `teammate_terminated` "X has shut down." (36417916); lead exit → `cleanupSessionTeams` kills every member pane (15487414/15488124). Neither writes the fleet log |
| 18 | `teammate_terminated` proves the process died (memory THE SPLIT) | **no** | Minted lead-side after the approval frame (36417916), not a process observation |

## (ii) The vendor's contract, and where the expectation diverges

**Contract:** a teammate is "finished" when its turn ends — it writes `isActive:false`, mails `idle_notification{available,summary,result}`, and sits at its prompt indefinitely; it ends only when the lead acts: `shutdown_request` → model approves → teammate mails `shutdown_approved{paneId,backendType}` and (260) exits itself (29617371) while the lead kills the pane (36415488); or `TaskStop` → abort + `paneTeardown` (19134169); or lead exit → `cleanupSessionTeams` (15488124).

**Divergence:** "closes down gracefully by itself" assumes an *unprompted* end-of-work exit. None exists: the only self-exit is inside `zs`, the `shutdown_response approve` handler (29616378 → 29617371), which needs a `request_id` from a lead's `shutdown_request` — and [G] says 82% never got one. The Stop hook (35334625) notifies and returns `!0`; it never exits.

## (iii) Attribution of every non-close mechanism

| Mechanism | Vendor / fleet | Evidence |
|---|---|---|
| No unprompted self-exit; "finished" rendered every turn | **vendor** | 35334625; 34681718 |
| Lead never sends `shutdown_request` (82%) | **fleet (lead discipline)** | [G] `sdshape=no-shutdown_request` 229/278 |
| Runner execs a shell after exit | **fleet** | `cc-pane-runner:83`; vendor tmux closes on exit (30659588), vendor iTerm2 runs the command bare (`it2 session run`, 38286501 region) |
| Composer guard rc=67 / identity pin rc=66 | **fleet — and it sits inside the vendor's actuator**: shim `bin/it2:123` execs `it2-kitty`, which **discards `-f`** (`bin/it2-kitty:275`) so InboxPoller kill, `TaskStop` teardown and `cleanupSessionTeams` all meet the guards | 42 of 51 September identity refusals are a second run on a pane `✓ closed` ≤6 lines earlier (evgo-policy 19:27:22/:23) — double-fire artefact, not a non-close |
| Settings `Stop` chain (12 hooks) running inside each pane teammate; wake floor (R-10) | **fleet** | settings.json `Stop`; vendor registers only its function hook |
| Shared-cwd gates (reap-guard rc 11, dirty-defer, `SURFACE`) | **fleet policy on a vendor constraint** (F-a: no per-teammate cwd via the tool) | #15; 19024382 `!C&&!ye` |
| Naming research agents | **fleet practice** on a vendor cost (`name:` ⇒ persistent member) | 19024382 teammate branch keyed on `E` |
| Vendor closes leave no fleet-log trace | **vendor path, fleet blind spot** | #17 |
| Idle teammate not answering `shutdown_request` (2.1.219: 0/4) | **unattributed** — vendor poller enqueues it (36415166); fleet Stop chain is the candidate; never re-measured on 260 | #13 |

## (iv) Would `teammateMode: tmux` or `in-process` dissolve fleet apparatus?

- **`tmux` does not force tmux.** `Ndt` (27455798) has an explicit branch only for `"iterm2"`; tmux is picked when the lead is *inside* tmux (`a6()`), else as an `isNative:false` fallback → `createExternalSwarmSession` = `tmux new-session -d` (30662533): a **detached**, invisible session. Visible splits need the lead under tmux (kitty can host it). Then the vendor's `kill-pane` (30661035) + `remain-on-exit failed` handle every close — **dissolved for teammates:** runner exec-shell, shim, rc=66/67, PPID-forensic, `teammate-auto-shutdown.sh:198`'s `it2 session close`. **Not dissolved:** Stop chain in teammates, reap-guard/shared-cwd policy, wake floor, unsent requests.
- **`in-process`** removes pane, process and both guards; adds `evictAfter` 30 s and the `idle_timeout` exit (if produced); teammates cannot spawn background agents (`subagent_teammate_background_denied`); and it is the "hidden subagent" shape the operator rejected 2026-07-19 (memory `feedback-dedicated-split-pane…`).
- **What the panes are FOR:** that memory's population is **dispatched handoff sessions** (`--split-right --follow --notify-back`), which call `it2-kitty`/`cc-pane-runner` directly (`handoff-fire.sh:1014-1022`) and never touch `teammateMode`; 59 fleet files depend on the shim (`cc-teardown`, `self-close`, `cc-await-ping`). Switching teammateMode changes which population the guards bite; it retires none of the apparatus.

## (v) Three dimensions this wave is not exploring

1. **Bytecode blindness.** 1,645 bytecode chunks in 260 vs 8 in 220: the 08-04 method ("enumerate every literal") is unsound now, and every carried-forward "nowhere in the binary" (idle_timeout producer, `completedTaskId` writer) needs a runtime probe (`--debug` lines `[inProcessRunner]`/`[InboxPoller]`). The debug dirs hold 1–5 files, none with such lines — nobody runs the binary instrumented.
2. **The `result` channel.** The "no completion producer" frame and the Delivery-field remedy were derived on 220. Nobody has measured what `result` carries for a pane teammate on 260 or whether any lead reads it (`result:s()`/`swarm_idle_result_delivery` across docs, skills, hooks, bin, memory: 0 hits).
3. **Instrument timezone.** The box is now **CDT (UTC-5)**; fleet conversions assume PDT. [G]'s `pane-closed-delayed(115-121m)` for 94/142 teammates on 260 is a 2 h artefact: evgo-policy log `19:27:18` CDT = `00:27:18Z`, transcript last record `00:27:20Z`, `✓ closed` 4 s later. `F-close-latency.csv` is suspect on the same axis (memory `process-start-time-renders-in-ambient-timezone`).

## Ruled out / open

Ruled out: "260 added a 2 h close delay" (v.3 artefact); "rc=67 is fixed" (modal arm remains, 31 in September); "identity_refused is new on 260" (42/51 are echoes). Open: whether the Stop chain runs inside *in-process* teammates; why TeammateIdle fires twice per idle (`log_auto_shutdowns=2`, 80/278); the idle non-response rate on 260 (needs a live spawn).
