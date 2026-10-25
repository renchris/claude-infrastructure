# A3 — Restart, Perfected: the best restart-based mid-turn mover that never waits for idle

Architect A3-restart-perfected · judge-panel design study · 2026-10-25.
Philosophy (assigned): **assume no credential trick is acceptable.** No bearer-swapping proxy (M7/M8),
no per-session `CLAUDE_SECURESTORAGE_CONFIG_DIR` lane (M6), no keychain/store rewrite (M5), no
setup-token (M13). The only account change the server can attribute is the vendor's own supported one:
a process launched under the target account's `CLAUDE_CONFIG_DIR`. Everything here is built from the
mechanism the vendor itself uses for crash revival (S12 §4, M2): **kill at the safest instant → `--resume`
the same session uuid on the target config dir with `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` → re-arm
everything the restart kills.**

This document is honest about the ceiling. A restart-based mover **cannot** meet the frozen DoD
(D-brief:24-28). It meets `0 forks`. It cannot meet `0 lost turns`, `0 killed background tasks`, or
`within 1 API call`. §4 quantifies exactly how far it misses and what each move costs. The value of
building it anyway is that it is the only option in the acceptable-policy envelope (S08: restart on own
account = Low exposure, 75% not a breach, D-brief:76), and it strictly dominates the incumbent by never
waiting for idle (the incumbent moved 5/149 busy/goal rows, 3.4%, D-brief:21).

---

## 0. Answer first (the honest ceiling)

| DoD clause (D-brief:26) | Restart-perfected verdict | Why |
|---|---|---|
| 0 transcript forks | **MET** | One writer enforced by a kill-before-relaunch barrier + same-store resume (§3, R1). P8's fork needs two live writers; this design proves the source is dead before the target launches. |
| 0 lost turns | **MISSED** | SIGTERM aborts the in-flight model stream. The partial assistant message since the last tool boundary, and any tool call executing at kill time, are not completed; resume re-drives the turn as a *new* turn (`pL` synthetic result + "Continue from where you left off.", S04:76-104). The conversation continues but the turn does not *complete on the same API call*. |
| 0 killed background tasks | **MISSED** | Background Bash, Monitor tasks, in-process subagents, workflows all die with the process (P7; S04 table §2). Re-arm (§6) relaunches them, but there is a kill→relaunch gap and the model, not the mover, must re-run Bash work — safe only if idempotent (P7). |
| within 1 API call of the order | **MISSED, by ~2 orders of magnitude** | Boot latency: incumbent actuate→proof p50 207 s, p90 823 s, max 1396 s (S05 §3). Even a perfected boot is seconds-to-minutes, plus a cold prompt-cache rebuild on the new org (273K-479K tokens measured, S05 §3). "1 API call" is unreachable by any mechanism that launches a new process. |

**So the restart-perfected mover is a strictly better *incumbent* — it moves busy sessions the incumbent
refuses — but it is not a DoD-meeting mover.** Its honest pitch is: *move any session at the next tool
boundary (seconds away under "idle never happens", not the never-arriving idle), losing only the current
tool call's in-flight work and a cache rebuild, with zero forks and full state re-arm.*

---

## 1. Mechanism

### 1.1 The safest instant: a tool boundary, no API stream in flight

The incumbent waits for a *turn* boundary (`end_turn`), which never comes (D-brief:19, S06 §3: 11/20
sessions ≥99.8% mid-turn). The restart-perfected mover instead picks a **tool boundary**: the moment
after a batch of tool calls has produced results and before the next model request is issued. At that
instant the main thread holds **no `/v1/messages` stream** (G3 §3: the bearer is captured per client, a
stream in flight finishes on its old bearer; killing between requests avoids a mid-stream abort of an
HTTP body).

The vendor fires a hook at exactly this point: **`PostToolBatch`** (S10 Part A; `lSn` @12716338, driven
at @18202625 "before attachments / next model request" and @18134707 at end-turn). `PostToolBatch` runs
once per tool batch, synchronously, with the main loop parked between tool results and the next model
call (S10 §3). This is the mover's trigger and its sequencing point. It is denser than `end_turn`:
under tonight's load a mid-turn session hits a tool boundary every few seconds (S06 §3: tool-exec p50
3 s), so "wait for the next `PostToolBatch`" is a sub-10 s wait, not an infinite one.

Critically, a hook **cannot perform the move** (S10 §4-5: no hook output touches credentials, config dir,
or process env; a hook is a child process and cannot set its parent's env). It can only *signal* an
external actor (M4, D-brief:109). So `PostToolBatch` writes a "boundary reached, safe to kill now"
breadcrumb that the out-of-process mover is already blocking on.

### 1.2 The kill and the resume

At the signalled boundary the mover:

1. **Quiesces re-armable state first** (§6): snapshots background jobs, workflows (`resumeFromRunId`),
   teammates, `/goal`, inbox watchers, composer draft — *before* the kill, while the process is alive
   and readable.
2. **SIGTERM** the worker process (not `/exit`: `/exit` raises the bg-work modal and types into the
   composer, S05 §1.5; SIGTERM at a tool boundary behaves like a clean exit per commit `819b3342b`
   "SIGTERM exits like /exit on five of six assertions", S05 §4.1). A 5 s SIGKILL backstop mirrors the
   vendor's own `hoe.kill` → SIGKILL-after-5 s (S12 §4).
3. **Proves the source is dead** (R1): waits for the pid to leave the ps-free census (§5) and for the
   source store's live-session registry row to clear. Only then does it launch the target.
4. **Relaunches** `claude --resume <same uuid>` under the **target** `CLAUDE_CONFIG_DIR`, in the same
   kitty pane, with `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` so the resumed process auto-continues the
   interrupted turn with "Continue from where you left off." (S04:76-104; the interactive REPL auto-submit
   gate @18279143 requires exactly this env var). It also sets
   `CLAUDE_CODE_RESUME_INTERRUPTED_TURN_MAX_AGE_MS` large enough to cover the boundary→boot gap (default
   bound 6 h, `eLt`/`emo`, S04 §1), so the continuation is not silently dropped as stale.

### 1.3 Why the transcript must already be visible under the target store

`--resume <uuid>` reads `<targetConfigDir>/projects/<slug>/<uuid>.jsonl`. The four accounts' stores are
physically separate for secondary/tertiary/quaternary; next and `~/.claude` share via symlink
(S04 §3 per-config-dir scope; S05 §1.6; G1 §0). So the mover must place the transcript in the target
store before launch. It reuses the incumbent's content-verified transplant (`lr-transplant.sh`:
copy `<sid>.jsonl` + `<sid>/` sidechains, sha-verify, split-brain lock, tombstone, retire source only on
confirm, S05 §1.6). The transplant is the **only** copy in the system and it is proven (R3). This is
unchanged from the incumbent; what changes is *when* the recycle fires (at a tool boundary, not at idle)
and *what re-arm follows it*.

### 1.4 What this is NOT

It is not M3 (Esc→/exit→"continue"): Esc writes a `user-cancel` marker that classifies as
`{kind:"none"}` and never auto-continues (S04 §1, D-brief:109). It is not M22 (SIGSTOP source, launch
target, kill source): that is two live holders on one transcript until the source is killed, a fork
window (P8). It is not `/bg` (M21): `/bg` forks to a new session id (S12 §5). It is the crash-revival
recipe (M2) driven deliberately at a chosen safe instant instead of on an unplanned crash.

---

## 2. Components (new files and changed files, by path)

All paths under the worktree root `/Users/chrisren/Development/.worktrees/research/midturn-account-move`.
Time and effort of implementation are zero-factors per the brief; this is the structural inventory.

### 2.1 New files

| path | role |
|---|---|
| `hooks/move-boundary-signal.sh` | `PostToolBatch` hook (and `UserPromptSubmit`, `Stop` as denser fallbacks, S10 §3). If a move is armed for this session (reads `~/.reso/move/arm/<sid>.json`), it writes `<sid>.boundary` with the current tool-batch id and ts, then returns `{}` (never `continue:false`, never `decision:block` — those would end or re-drive the turn, S10 §4). Idempotent, locked, 5 s timeout. |
| `scripts/limit-recover/lr-move2-worker.sh` | the restart-perfected worker (replaces `lr-move-worker.sh`'s wait loop). Arms the hook, blocks on the boundary breadcrumb (not on an idle census), runs the quiesce→kill→prove→relaunch→re-arm protocol (§3). |
| `scripts/limit-recover/lr-rearm.sh` | re-arm library (§6): bg-job relaunch, workflow `resumeFromRunId`, teammate relaunch, goal re-issue, inbox-watcher re-arm, draft carry. Each sub-arm has its own kill switch and its own disk-truth verdict. |
| `scripts/limit-recover/lr_recon/proctable.py` | the ps-free census module (S07 §6), folded into the reconciler's `observe.read_ps`. Verbatim from S07: `kern_proc_all()`, `tty_map()`, `ArgsReader`, `render_args()`. |
| `scripts/limit-recover/lr-move2-verdict.sh` | the disk-truth verdict (§8), redefining "on account Y" for a restart move: new pid under target store, target bearer billed (response-header or usage-feed fact), single writer, no resume debt, all re-arms confirmed. |

### 2.2 Changed files

| path | change |
|---|---|
| `bin/cc-lr` | `cmd_move` / `cl_move_rows`: a busy disposition (`mid-turn`, `subagents-in-flight`, `background-job`, `goal-live`) becomes `move-at-boundary` instead of `wait:`/`hold:` (D-brief vs S05 §1.2). The `hold:goal-live` and `wait:mid-turn` rows that stalled every move tonight (S06 §2) are now actionable. |
| `scripts/limit-recover/lr-handoff.sh` | `--in-place` recycle path: replace the `/exit`-typed handoff with a SIGTERM-at-boundary handoff; drop the composer-draft `/exit`-merge gate (no `/exit` is typed); keep transplant/custody rails unchanged. |
| `scripts/handoff-fire.sh` | `recycle_fire_armed`: the watcher no longer types `/exit`; it waits for the boundary breadcrumb, sends SIGTERM, proves death, types the launcher. The bg-work modal handling (`:12605-12820`) is retired on this path — no modal is raised because no `/exit` runs. |
| `lib/claude-launcher.zsh` | the launch env-injection point (D-brief:94): sets `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` and `..._MAX_AGE_MS` for a restart-move relaunch, and exports the re-arm handles (task-list id, goal spec path, bg-job manifest path). |
| `settings.json` | register `hooks/move-boundary-signal.sh` on `PostToolBatch` (10 s), `UserPromptSubmit` (5 s), `Stop` (5 s). Via a numbered operator migration — agents never edit settings.json (D-brief:91). |
| `scripts/limit-recover/lr_recon/observe.py`, `store.py`, `act.py`, `fence.py` | swap `/bin/ps` reads for `proctable` per S07 §6 ("Also replace"). |

---

## 3. Move protocol, step by step (order → billing changes) with timings

Order arrives (e.g. "put pane 217 / sid 15f652bd on next4"). Sid is on next (source), target next4.
Timings are **estimated** from the named measured sources; none is newly measured here.

| # | step | file | timing (source) |
|---|---|---|---|
| P0 | **Admit + claim.** Router read (fail-closed), per-sid claim by (pid, lstart), intent check. Unchanged from incumbent W0/intent (S05 §1.4). | `lr-move2-worker.sh` | <1 s |
| P1 | **Census.** One ps-free census (§5): confirm the sid's live pid, store, pane binding; confirm single holder (no fork already present). | `proctable.py` | **3.3 ms** [M, S07 §4 `B_kern_proc_all_ms`] + ≤9 ms claude-family args [M, S07 §4] |
| P2 | **Arm the hook.** Write `~/.reso/move/arm/<sid>.json`. The next `PostToolBatch`/`UserPromptSubmit`/`Stop` fire writes `<sid>.boundary`. | `move-boundary-signal.sh` | boundary arrives in **≤10 s** [E: tool-exec p50 3 s, S06 §3; boundaries denser than turns] |
| P3 | **Quiesce-snapshot (process alive).** Read and persist: bg-job manifest (command+cwd+pid, as `rcy_jobs_capture` already does, S10 Part B), workflow run-ids, teammate roster + agent-ids, `/goal` spec, composer draft, inbox-watcher state, task-list id. | `lr-rearm.sh --snapshot` | <1 s |
| P4 | **Transplant.** Copy `<sid>.jsonl` + `<sid>/` to target store, sha-verify, take split-brain lock, write tombstone. **Do not retire source yet.** | `lr-transplant.sh --phase admit` | p50 ~0.1 s [C, S05 §3 "transplant cost 0.109 pp median"] |
| P5 | **Wait for the boundary breadcrumb.** Block on `<sid>.boundary` with a bounded budget. Re-check intent and limit every poll. **This is the only wait, and it is a tool-boundary wait, not an idle wait.** | `lr-move2-worker.sh` | ≤10 s typical; budget e.g. 120 s then page |
| P6 | **SIGTERM the source.** At the breadcrumb instant, send SIGTERM to the worker pid; SIGKILL backstop at 5 s. **Billing: the last in-flight request (if any) already completed on next's bearer before the boundary; no request is in flight at SIGTERM (§1.1).** | `handoff-fire.sh` | ≤5 s |
| P7 | **Prove death (R1).** Poll the ps-free census until the pid is gone and the source store's registry row clears. Only now is a second launch fork-safe. | `proctable.py` | ≤2 s [E: census 3.3 ms × polls] |
| P8 | **Retire source transcript.** `unconfirm`→confirm: rename source `<sid>.jsonl`→`.handed-off` (link-then-unlink), now that the source is provably dead (S05 §1.6 "the only moment the source is provably quiesced"). | `lr-transplant.sh` | <0.1 s |
| P9 | **Relaunch on target.** `claude --resume <uuid>` under `CLAUDE_CONFIG_DIR=~/.claude-quaternary`, same pane, env `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1`, `..._MAX_AGE_MS` large, re-arm handles exported. **Billing changes here: the new process bootstraps against next4, every `EN()` client build reads next4's store (G3 §1-2), the first `/v1/messages` carries next4's bearer AND next4's `account_uuid` (restart re-syncs identity: `ot()`/bootstrap stamps the live token's account, G4 §answer — unlike every zero-restart swap where account_uuid stays stale, P6).** | `lib/claude-launcher.zsh` → `lr-fire-resume` | boot to first request **p50 ~tens of s** [E: incumbent actuate→proof p50 207 s is the full proof window, S05 §3; first-request is earlier] |
| P10 | **Auto-continue the turn.** The resumed process appends `pL` synthetic results for the dangling tool_use(s) and auto-submits "Continue from where you left off." (S04:76-104). First model request on next4. **Prompt cache cold** (account-scoped, S04 §5): full context re-written, 273K-479K tokens [C, S05 §3]. | CC internal | 1 API call |
| P11 | **Re-arm.** Relaunch bg jobs, resume workflows (`resumeFromRunId`), relaunch teammates with `--agent-id`, re-issue `/goal`, re-arm inbox watcher, carry draft (§6). | `lr-rearm.sh --apply` | seconds; some re-runs are model-driven |
| P12 | **Prove (R4).** `lr-move2-verdict`: target store, target bearer billed (response header / usage feed), single writer, no resume debt, all re-arms confirmed. Write atomic `<sid>.json`; release claim/lock/slot. | `lr-move2-verdict.sh` | bounded; MOVED needs same pid on 2 reads ≥5 s apart (incumbent W6, S05 §1.4) |

**Net wall per move (estimated):** boundary wait ≤10 s + kill/prove ≤7 s + boot tens of s + re-arm seconds +
cache rebuild on first turn ≈ **30-250 s**, dominated by boot and proof. The *billing* changes at P9
(first request on next4). The order-to-effect latency is therefore **tens of seconds minimum** — this is
the `within 1 API call` miss, structural to launching a process.

---

## 4. Exactly how far it misses the DoD (P7), and the cost per move

### 4.1 The miss, clause by clause (quantified)

- **0 forks — MET.** The kill-before-launch barrier (P6-P7) plus same-store single-transcript (P4/P8)
  means there is never a second live writer. P8's fork requires two concurrent `--resume` on one uuid;
  this design launches the target only after proving the source pid is gone. Residual fork risk: a late
  append by a not-fully-dead source after transplant (S04 §3 "silent fork with no CC-side detection") —
  closed by R1 (prove death before launch) and the 5 s SIGKILL backstop.

- **0 lost turns — MISSED.** SIGTERM at the tool boundary discards: (a) the partial assistant message the
  model had begun since the last tool boundary (none, if we kill exactly at `PostToolBatch` before the
  next request — so this is ~0 if timing is exact); (b) the result of any tool call still executing at
  kill time (P7: the in-flight tool is marked `pL` "outcome unknown"; its side effects are not undone,
  S04 §1). The turn is **re-driven** as a fresh turn via auto-continue, not completed on its original API
  call. Measured analog: P7's foreground step and bg job were re-run by the model. **Count: 1 re-driven
  turn per move; 0-1 interrupted tool results per move** (0 if we kill in the `PostToolBatch` gap with no
  tool executing; the gap is real because `PostToolBatch` fires after results are in, @18202625).

- **0 killed background tasks — MISSED.** Background Bash (`run_in_background`), Monitor tasks, in-process
  subagents, workflows all die with SIGTERM (P7; S04 §2 table). Re-arm (§6) relaunches them, but:
  - there is a kill→relaunch gap (seconds to tens of seconds);
  - Bash jobs are re-run **by the model**, not restored, so only *idempotent* jobs are safe (P7
    explicitly: "safe only if idempotent"). A `ship-land` killed between rebase and push is "the worst
    single loss" (S05 §2.1) and re-run is not safe.
  - **Count: N background tasks killed per move, N re-armed, of which the non-idempotent ones are at
    risk.** This is the hardest structural miss and no restart mechanism closes it.

- **within 1 API call — MISSED by ~2 orders of magnitude.** Boot + proof is tens-to-hundreds of seconds
  (S05 §3). Plus a cold cache rebuild (below). "1 API call" is reachable only by a mechanism that keeps
  the live process (M6/M7), which this philosophy rejects.

### 4.2 Cost per move (measured sources)

| cost | magnitude | source |
|---|---|---|
| Prompt-cache rebuild on the new org (unavoidable on any account change) | 273,235-479,138 cache-write tokens on the first turn; ~1.9× context | [C] S05 §3 (REPORT R11); S04 §5 (caches isolated between orgs) |
| Boot→proof outage | p50 207 s, p90 823 s, max 1396 s (incumbent; a perfected boot targets the low end) | [C] S05 §3 |
| Re-driven turn | 1 turn's model work re-run | P7 |
| Re-run background work | each killed Bash job re-run by the model | P7 |
| Interrupted tool result | 0-1 per move, marked `pL` | S04 §1 |
| Census per move | 3.3 ms + ≤9 ms args | [M] S07 §4 |

**The per-move cost is dominated by the cache rebuild and the boot outage — both intrinsic to "launch a
new process on another org."** They do not shrink with better engineering; they are the price of the
acceptable-policy envelope.

---

## 5. The ps-free reconciler census (S07), folded in

The move lane decides holders, the no-fork guard and SPLIT-BRAIN on a process census; a census that goes
blind freezes every move regardless of mechanism (S07 §6 "Why it matters"). Tonight's incumbent ran
`/bin/ps -ax` which timed out at 42 s under load 624, 97 "ps degraded" abstains, a 15-pass blind streak
(S07 §5). The restart-perfected mover uses the ps-free table verbatim from S07:

- **One `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_ALL)`** supplies pid/ppid/zombie/lstart/tdev for all rows,
  including the root-owned `login` pane roots that `proc_pidinfo` EPERMs on (S07 §1-2). **3.3 ms for 2167
  rows at load 624** [M, S07 §4], vs ps timing out at 42 s.
- **tty** from a `/dev/tty*` `st_rdev` map (0.7 ms/scan, S07 §2).
- **args** from `KERN_PROCARGS2` on a bounded worker thread, claude-family first (9 ms for 93 claude
  rows), with a per-call deadline and the fail-closed rule: an unread claude-family arg is never rendered
  `(comm)` (that would undercount a holder → a move over a live session), it marks `snap.degraded` and
  abstains that pid only (S07 §6).
- **Kill switch:** `LR_RECON_PSFREE=off` (env) or `touch ~/.reso/limit-recover/recon/ps-free.off`
  (no restart), falling back to `/bin/ps` unchanged (S07 §6).
- **Shadow mode** first: run both, log per-field parity, switch to "on" after N passes with 0 mismatches
  on ppid/zombie/lstart/tty and 0 claude-family token mismatches (S07 §6).

This is the census for P1, P7 (prove death) and P12 (single-writer proof), and it is what makes the
move decision survive load 650-770.

---

## 6. Strand-aware rebalance flow and limit-recovery flow

### 6.1 Strand-aware rebalance (the 01:55 order)

The trigger order (D-brief:9-13) was "put every active session onto next4 (84% weekly, 2 h to reset)."
Strand-aware = put work where weekly quota would otherwise expire unused (D-brief:8). The flow:

1. **Read utilization per account** from the usage feed / response headers already captured by
   `claude-accounts --readout` (P-probes:11: next 2%, next3 18%, …; next4 84% 2 h to reset in the order).
   Compute "strand risk" = quota that resets unused before the window closes.
2. **Rank sessions × targets** in the router (fail-closed, S05 §1.2 R5). A session whose source account
   has headroom and whose target would otherwise strand gets a `move-at-boundary` row.
3. **Fan out** one `lr-move2-worker` per row, each arming its own `PostToolBatch` hook. Because the wait
   is a tool-boundary wait (≤10 s) not an idle wait (∞), **all rows actually fire** — the 01:55 batch that
   "queued them all" (D-brief:12) and moved 0/7 busy rows (S06 §2) would instead move them within seconds
   each. This is the whole point of the design.
4. **Slot semaphore** (width 4, incumbent W3) still throttles concurrent kitty boots (S05 §1.4).

### 6.2 Limit-recovery flow (the wall)

A session that tails `rate_limit` (D-brief:72 reconciler acts only on a `rate_limit` tail):

1. The capped turn **ends** (S05 §2.1 "a capped turn ends"), so this is the one case where a restart is
   *least* lossy — there is no in-flight turn to abort. The reconciler detects the `rate_limit` tail
   (facts.py).
2. **"Owes a turn" nudge.** The incumbent's `hold:limited` exists because a no-prompt resume lands the
   session at rest, unanswered, and falsely reads MOVED (S05 §2, R-A class). The restart-perfected mover
   relaunches with `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` **and** a nudge prompt so the recovered session
   restarts its turn on the new account (S04:76-104 auto-continue covers this when the tail classifies
   `interrupted_turn`; a plain capped `end_turn` does not, so the nudge is explicit).
3. Everything else (transplant, prove-death, re-arm) is identical to the rebalance flow.
4. **Recovery latency** today is median 81 min detection→ENGAGED (S05 §3). The restart-perfected mover
   does not improve detection; it improves the *act* once engaged, by not waiting for idle.

### 6.3 Re-arm (what a restart kills, and how each is restored)

Driven by `lr-rearm.sh`, snapshotted at P3 (alive) and applied at P11 (post-boot). Every item cites S04 §2
/ S10 Part B.

| state | kills? | re-arm | residual loss |
|---|---|---|---|
| Transcript | no (same-uuid resume) | — | none |
| In-flight turn | yes | `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1` auto-continue | the turn is re-driven, not continued (DoD miss) |
| Background Bash | yes | relaunch from the captured manifest (command+cwd), as a fresh `run_in_background` | kill→relaunch gap; non-idempotent work at risk (P7) |
| Monitor tasks | yes | re-create from the snapshot | gap |
| Workflows | yes | relaunch `Workflow({scriptPath, resumeFromRunId})`; completed `agent()` calls return cached (S04 §2 `fs` @26065485) | in-flight workflow subagents restart from the beginning (S12 §5) |
| In-process subagents | yes | ≤48 h transcripts auto-restart from saved transcript (S04 §2 `us` @26055731); others get a SendMessage-resume note | unfinished subagent work re-run |
| Teammates | yes (lead exit kills members) | relaunch each with `--agent-id`, `--parent-session-id` (S10 Part B; lazily resumed by SendMessage, S04 §2 @35483700) | member in-flight work |
| /goal | yes (dies with process) | re-issue from captured spec; CC also restores from last `goal_status` attachment with counters reset (S04 §2 `S5t`; `tengu_goal_restored_on_resume`) | counters/timer reset (acceptable) |
| Inbox watcher (cc-await-ping) | yes | auto: `mailbox-wake-arm.sh` on SessionStart+Stop (S10 Part B) | short deaf window |
| Composer draft | yes | carry unsent text (incumbent `hf_rcy_carry`); a `[Pasted text #N]` is **not** carryable (S10 Part B) | pasted blocks lost |
| Task board / cwd / pane binding | — | launcher exports task-list id, `--resume-cwd`, SessionStart re-registers (S10 Part B) | none |
| Permission "session" grants | yes | not restored | re-prompts (moot under allowlists) |
| Prompt cache | yes (account change) | not restorable | full rebuild (§4.2) |

---

## 7. Invariants R1..R10 (carried from S05 §5, adapted to a restart move)

- **R1 — Prove death before launch.** No target process starts until the source pid is gone from the
  ps-free census and the source store's registry row has cleared. Closes P8's fork and S04 §3's late-append
  silent fork. (S05 R1; this is the hard barrier a restart move adds over the incumbent's `/exit` race.)
- **R2 — No in-flight work destroyed without capture.** Every killable item (turn, subagents, bg jobs,
  workflows, teammates, draft) is snapshotted at P3 while the process is alive, so re-arm is possible.
  The DoD-missed items (§4.1) are the ones that cannot be *continued*, only *re-run*. (S05 R2; A04 I4.)
- **R3 — No silent truncation; continuity content-verified.** The single transplant is sha-verified
  (admit + confirm), and R4 proves the conversation continued on the same bytes. (S05 R3.)
- **R4 — Verdict from disk/process facts, re-derivable.** "On account Y" is redefined for a restart move
  (§8): it is *true* here because the process genuinely runs under Y's config dir and bootstraps Y's
  account_uuid (G4), so P2 (env config dir = target) and P3 (transcript under target store) from the
  incumbent verdict (S05 §1.7) both hold — unlike every zero-restart mechanism which fails them by
  definition. The billing proof is still a measured response-header/usage fact, never prose. (S05 R4.)
- **R5 — Absence is loud.** Two-read `gone` rule, loud missing `killed_inflight`, page when a boundary
  never arrives within budget, page when a re-arm cannot be confirmed. An unreadable census/store is its
  own verdict, never a silent pass. (S05 R5.)
- **R6 — Nothing refuses after the point of no return.** Every refusal (intent, limit, census-degraded,
  router) sits before P6 (SIGTERM). After SIGTERM the move is committed and only drives forward or pages.
  (S05 R6; incumbent "NOTHING REFUSES AFTER /exit".)
- **R7 — One actuator per session**, (pid, lstart) claim, released on every path. (S05 R7.)
- **R8 — Credential safety is trivially satisfied here and must stay so.** This design **writes no
  credential, copies no token, creates no keychain item, runs no proxy** (its whole premise). Each account
  keeps exactly one live grant in one store (G1 §2). The `invalid_grant` erase, the refresh-token race,
  the sibling-login hazards (S01/S09/G1 §5) are all structurally impossible. **This is the single largest
  safety advantage over the credential-swap designs.** No token is ever printed.
- **R9 — One time-aware account-attribution source of truth.** "session S billed to account A from time
  t" drives the router, the reconciler facts (else the source account looks un-capped, S05 finding 5), the
  usage sweep and the verdict. ~68 files key on `config_dir` (S05 §0.4) — and for a restart move
  `config_dir` *is* correct again (the process really moved dirs), so the existing attribution keying
  keeps working without the redefinition that a zero-restart move forces. (S05 R9.)
- **R10 — Bounded external calls under load 300-900.** Every wait has a budget (boundary wait, prove-death,
  boot proof); no unbounded `ps`; the census is ps-free (§5); no step depends on kitty's control socket
  except the final pane relaunch (which has a `HELD:unreachable` retry, S05 §1.4). (S05 R10.)
- **R11 — Operator authority / fail-closed binary drift.** Intent re-checked at every hold; router admits
  fail-closed; every mechanism has an env kill switch (§9); every anchor into the minified binary is
  pinned to 2.1.293 and refuses on an uncertified binary (S05 R11/R14). No turn typed into an unowned
  session.

(R12-R14 from S05 — no filler sessions, teams never orphaned, fail-closed on drift — are carried verbatim;
R12 is automatic here as the design launches nothing speculative.)

---

## 8. Redefining "on account Y" (why a restart move passes the incumbent verdict)

The incumbent verdict P1-P7 (S05 §1.7) was built *for* a restart move, so it mostly transfers:

- **P1** registry pid is live — holds after boot.
- **P2** process env `CLAUDE_CONFIG_DIR` == target — **holds** (the new process is launched under the
  target dir). A zero-restart move fails P2 by definition (S05 §1.7); a restart move passes it.
- **P3** exactly one live transcript under the target store — **holds** (transplant + retire source).
- **P4** no foreign tombstone, **P5** exactly one live holder, **P6** admitted with target ranked,
  **P7** no open resume debt — all hold.

**Added for the restart-perfected verdict:**
- **P8 (billing fact):** the first post-boot `/v1/messages` response header `anthropic-organization-id`
  (and `anthropic-ratelimit-unified-7d-utilization`) equals the target account's org (the technique
  P-probes used to identify billing, P-probes:9-11). This is the disk-truth read that "billed to Y" from
  a measured fact (R4), not from the config dir alone.
- **P9 (re-arm confirmed):** each snapshotted re-armable item has a confirmed relaunch (bg manifest
  cleared, workflow run resumed, teammate live, goal re-issued, watcher armed) or a loud note that it
  could not be (R5).

---

## 9. Kill switches (env)

Every new mechanism ships with an env kill switch (D-brief:92). Narrow-first:

| switch | effect |
|---|---|
| `LR_MOVE2=off` | disable the restart-perfected lane entirely; fall back to the incumbent `cc-lr move`. |
| `LR_MOVE2_BOUNDARY=turn` | revert to waiting for a real `end_turn` boundary instead of a tool boundary (effectively the incumbent's behavior; for debugging). |
| `LR_MOVE2_HOOK=off` | do not arm the `PostToolBatch` hook; the worker falls back to polling the ps-free census for a tool boundary (no hook dependency). |
| `LR_MOVE2_REARM=off` | kill and resume only; do not re-arm bg jobs/workflows/teammates/goal (for isolating re-arm bugs). Per-arm: `LR_REARM_BGJOBS=off`, `LR_REARM_WORKFLOWS=off`, `LR_REARM_TEAMMATES=off`, `LR_REARM_GOAL=off`, `LR_REARM_WATCHER=off`. |
| `LR_RECON_PSFREE=off` / `touch …/ps-free.off` | ps-free census off → `/bin/ps` (S07 §6). |
| `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=0` | relaunch idle instead of auto-continuing (vendor env; for a move where the operator wants a manual nudge). |
| `LR_MOVE2_SIGKILL_MS` | SIGTERM→SIGKILL backstop (default 5000, mirrors vendor `hoe.kill`). |

---

## 10. Acceptance criteria as disk-truth reads

All reads are from disk/process facts (R4), re-runnable, no prose. Per move `<sid>`:

1. **No fork:** ps-free census shows exactly one live holder of `<uuid>` across all four stores
   (`proctable` + registry join). Source store has `<uuid>.jsonl.handed-off`, target store has live
   `<uuid>.jsonl`. No second leaf in the target jsonl (`A$` leaf count == 1, S04 §3). [verifies forks0]
2. **Account changed:** target process `CLAUDE_CONFIG_DIR` == target dir (`proctable` args / `/proc`-equiv
   env read); first post-boot response-header `anthropic-organization-id` == target org (P-probes
   technique); `metadata.user_id.account_uuid` == target (restart re-syncs, G4 — a positive test the
   zero-restart designs fail, P6). [verifies the move happened]
3. **Turn continued:** target jsonl tail shows the `pL` synthetic result(s) for the interrupted tool_use
   and a subsequent assistant turn (not stuck at the interrupt marker). [bounds the lost-turn miss]
4. **Re-arm confirmed:** bg-job manifest consumed (each relaunched job has a live pid or a completion
   record); workflow run shows `resumeFromRunId`; teammates live (`lr-team.sh` roster); `/goal`
   `goal_status` attachment present with `origin:"restored"`. Any gap is a loud note, not a pass. [bounds
   the killed-bg miss]
5. **Timing honesty:** the verdict records `order_ts`, `boundary_ts`, `sigterm_ts`, `first_request_ts`,
   so the `within 1 API call` miss is measured per move (expected tens-to-hundreds of seconds), not
   claimed met.

---

## 11. Rejected alternatives (with reasons)

- **Any credential mechanism (M5/M6/M7/M8/M13).** Out of scope by assigned philosophy, but also: M6/M7 are
  the only ones that could meet `within 1 API call` and `0 killed bg`, and they are rejected here on
  policy (S08: proxy Moderate-High 45% clear violation; store rewrite Low-Moderate 60%) and on the
  refresh-token hazard (G1 §5: a copy creates sharing that is self-destructive). A sibling architect owns
  those. This document's job is the best *restart* design.
- **Wait for a real turn boundary (M1, incumbent).** Rejected: idle never happens (D-brief:16-22);
  5/149 busy rows moved. The tool-boundary trigger is the fix.
- **Esc → /exit → "continue" (M3).** Rejected: Esc writes `user-cancel`, classifies `{kind:"none"}`,
  never auto-continues (S04 §1). Loses the turn with no auto-recovery.
- **SIGSTOP source / launch target / kill source (M22).** Rejected: two holders on one uuid until the
  source is killed = a fork window (P8). R1 (prove death first) is strictly safer.
- **`/bg` handover (M21).** Rejected: forks to a new session id (S12 §5), and stays in the same config
  dir (cannot change account, S12 §6).
- **`claude respawn` / bg supervisor restart (M17).** Rejected: the worker env forcibly pins
  `CLAUDE_CONFIG_DIR` to the supervisor's own dir (S12 §6 `qe()`); a respawn cannot change account by
  design.
- **`/login` in-session (M15).** Rejected: needs a browser OAuth flow, is queued until the turn ends
  (S04 §4, not scriptable mid-turn), and overwrites the whole config dir's stored login.
- **Type `/exit` (incumbent recycle).** Rejected in favor of SIGTERM-at-boundary: `/exit` raises the
  bg-work modal (nothing may answer it, S05 §2.1 `hold:bg-work-dialog`), merges with a composer draft
  (S05 §2.1 `draft`), and kills the turn with no auto-continue. SIGTERM at a `PostToolBatch` gap avoids
  the modal and the draft-merge, and pairs with `CLAUDE_CODE_RESUME_INTERRUPTED_TURN=1`.

---

## 12. Residual risks

1. **The DoD is not met (§4).** `0 lost turns`, `0 killed bg`, `within 1 API call` all miss. If the judge
   panel requires the DoD, this design loses to a credential mechanism on the merits and wins only on
   policy safety. This must be stated plainly to the operator (decision D1).
2. **Non-idempotent background work.** A `ship-land` killed between rebase and push, re-run by the model,
   can double-apply or leave a dirty tree (S05 §2.1 "the worst single loss"). Re-arm cannot make a
   non-idempotent Bash job safe. Mitigation: a pre-kill guard that *refuses to move* (before P6, R6) a
   session whose bg manifest contains a known non-idempotent command (ship-land) — i.e. for those specific
   sessions the mover degrades back to "wait for this job to finish." This reintroduces a bounded wait for
   a narrow class.
3. **Boundary timing precision.** If SIGTERM lands slightly after `PostToolBatch` and the next model
   request has already started, the in-flight stream is aborted mid-body (G3 §3). Harmless to billing
   (that request finishes or fails on next's bearer, not next4's) but costs a retry. Mitigation: kill
   inside the hook's synchronous window (the main loop is parked, S10 §3) by having the hook itself block
   briefly while the mover sends SIGTERM — bounded by the hook's 10 s timeout.
4. **Parallel subagent requests at the boundary.** `PostToolBatch` parks the main thread, but in-process
   subagents keep issuing requests (S10 §3, G3 §2). A subagent request in flight at SIGTERM is aborted and
   re-run on resume. Already covered by re-arm's subagent auto-restart (≤48 h, S04 §2), but it widens the
   re-run surface.
5. **Boot sits on a dialog.** A relaunched pane can land on the cold-resume "Resume this conversation?"
   dialog (`pIe` @32345823, S04 §5) if the last message is older than the cache TTL. Mitigation: the
   per-config `resumeReturnDismissed` flag suppresses it (S04 §5); set it in the target store's config.
6. **Binary drift.** The `PostToolBatch` offset and the `CLAUDE_CODE_RESUME_INTERRUPTED_TURN` semantics are
   pinned to 2.1.293 (S04, S10). An auto-update changes them; R11 fail-closes on an uncertified binary.
7. **ps-free census parity.** 24 unexplained args mismatches in shadow (S07 §4); must clear in shadow
   before "on" (S07 §6). Until then the census is shadow-only and the move lane uses `/bin/ps` with its
   blind-streak risk.
8. **Policy drift.** Even restart-on-own-account is only 75% not-a-breach today, 65% after 2026-11-12
   ("circumvent product guardrails", S08 M1). This is the lowest-exposure option but not zero.

---

## 13. Operator decisions I cannot settle at >90% conviction

**D1 — Ship a mover that provably misses the DoD?** Conviction 70% that the restart-perfected mover is
the right thing to ship *given the policy constraint*, but <90% because it depends on whether the operator
weights DoD-compliance over policy-safety.
- Options: (a) ship restart-perfected as the acceptable-envelope mover and treat the DoD as aspirational;
  (b) ship a credential mechanism (M6/M7) that meets the DoD and accept the policy exposure; (c) ship
  both, restart-perfected as default, credential as a flagged fast-path for idempotent-only sessions.
- Recommendation: **(a)** for the default lane, because the single-grant credential safety (R8) and the
  Low policy exposure (S08) are worth more than hitting a DoD that *no* policy-clean mechanism can hit;
  revisit (c) if the operator later accepts the exposure.

**D2 — Kill at `PostToolBatch` or at a denser boundary (`UserPromptSubmit`/`Stop`)?** Conviction 75%
for `PostToolBatch`.
- Options: (a) `PostToolBatch` only (cleanest "no request in flight"); (b) add `Stop` and
  `UserPromptSubmit` as fallbacks for text-only turns that never call a tool (S10 §3); (c) poll the
  ps-free census for a boundary with no hook at all (`LR_MOVE2_HOOK=off`).
- Recommendation: **(b)** — `PostToolBatch` primary, `Stop`/`UserPromptSubmit` fallback, because a
  text-only turn never reaches `PostToolBatch` and would otherwise wait forever.

**D3 — Refuse-to-move non-idempotent bg sessions, or move-and-hope?** Conviction 60%.
- Options: (a) refuse (reintroduce a narrow bounded wait for ship-land-class jobs); (b) move and re-run,
  trusting idempotency; (c) move but quarantine the re-run (relaunch the job in a dry-run/verify mode and
  page the operator).
- Recommendation: **(a)** for a known non-idempotent denylist (ship-land), **(b)** otherwise. The denylist
  is small and the downside of (b) on ship-land is severe (S05 §2.1).

**D4 — Does `metadata.user_id.account_uuid` re-sync reliably on every restart, or only after a bootstrap
fetch?** Conviction 80% it re-syncs on boot (G4: bootstrap `ot()` stamps the live token's account at
launch), but G4's own open question (does the server even compare it) is unresolved.
- Options: (a) rely on boot re-sync and verify in acceptance read #2; (b) add an explicit bootstrap-refresh
  trigger post-boot; (c) ignore account_uuid (bearer is what bills).
- Recommendation: **(a)** with the acceptance read as the guard — if read #2 ever shows a stale uuid after
  boot, escalate to (b).

**D5 — Is the tool-boundary kill safe enough to not need the 5 s SIGKILL to ever fire?** Conviction 65%
that SIGTERM at `PostToolBatch` lets the process exit cleanly before SIGKILL.
- Options: (a) 5 s backstop (vendor default); (b) longer backstop to let a tool's own cleanup finish;
  (c) no SIGKILL, SIGTERM-only and page if it hangs.
- Recommendation: **(a)**, matching the vendor's own `hoe.kill` 5 s (S12 §4), with the hang paged (R5).

---

## 14. Citations index

D-brief:8-28 (problem, idle-never, DoD), :72-78 (policy), :94 (launcher). P-probes:9-11 (billing
identification), P7:99-107 (restart fallback losses), P8:109-114 (fork), P5/P6 (account_uuid staleness
contrast). S01 §method (OAuth offsets). S04:76-104 (resume repair, `CLAUDE_CODE_RESUME_INTERRUPTED_TURN`
auto-continue @18279143), §2 (restore table), §3 (two writers / per-config scope), §5 (cold-resume dialog
`pIe` @32345823, account-scoped cache). S05 §1 (incumbent mechanism), §1.7 (verdict P1-P7), §2 (gate
classes), §3 (casualty counts: boot p50 207 s, cache 273K-479K), §5 (invariants). S06 §2 (0/7 busy moved
tonight), §3 (mid-turn 66.8%, tool-exec p50 3 s). S07 §1-6 (ps-free census; 3.3 ms; kill switch;
fail-closed). S08 M1 (restart exposure Low, 75%). S09:159 (StopFailure resume = incumbent), :221 (only
wild mid-loop no-fork is credential substitution — rejected here). S10 Part A (33 events, `PostToolBatch`
`lSn` @12716338 driven @18202625), §3-5 (hook cannot touch creds; trigger only), Part B (re-arm table).
S12 §4 (M2 crash-revival recipe; `hoe.kill` 5 s), §5 (`/bg` forks), §6 (respawn cannot change account).
G1 §2/§5 (four independent grants; copy = self-destructive). G3 §1-3 (every inference path runs the
change-check; in-flight stream finishes on old bearer). G4 (identity re-sync only on restart/login).
Source offsets re-confirmed here: `PostToolBatch` `lSn` @12716338, drive sites @18134707/@18202625;
`--reply-on-resume` `Ozt`/`Hzt` @9572024; env allowlist `GWe` @9568587.
