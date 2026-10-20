# Gap 2: decentralized self-recovery at PRI 31 (StopFailure-triggered self-move)

Date: 2026-10-20, about 05:20-05:40Z (00:20-00:40 CDT). The work was read-only. Code was read on
`/Users/chrisren/Development/claude-infrastructure` `main`. While I worked, `main` moved from 58885750c to **c82a349ce**
(`git log --oneline -1 main`). That commit touches only `hf_transcript_at_rest` in `handoff-fire.sh`, at about
:2985-3020, plus lr-upgrade.sh. Every `handoff-fire.sh` line cited here is at c82a349ce. Lines above :2985 are
unchanged from 58885750c. Lines below it sit 14 lines later than at 58885750c, so the brief's `:3975-4060` is
`:3989-4060` here.

Labels: **[M]** measured (the command or file is named), **[E]** estimated (the method is named), **[H]** hypothesis
(not verified).

The only process I started was my own `/bin/sleep 6` (a band probe, §2). It exited by itself. I sent no signals,
typed into no pane, ran no launchctl, and ran no cc-lr mutation.

---

## 0. Answer

**Feasible. It needs code, and it needs an operator ruling. No live test has run.** A capped session can move
itself without the reconciler. Every step of the path is one of three kinds:

- a disk read or write;
- a kernel call;
- a local rename that the pane's own shell performs.

All of it can run in the session's own PRI-31 tree, and all sessions can do it in parallel.

Most pieces already exist and have been exercised live:

| piece | evidence |
|---|---|
| The hook fires at the death, with all inputs | 7/7 incident sids carry sid, pane and config dir [M] |
| A setsid'd child of a claude tree stays at PRI 31 and is reparented to launchd | [M] |
| The staged successor works | 24/24 claimed since 2026-10-19T12Z [M] |
| The SIGTERM exit works | 8 rows in the incident, nothing typed [M] |
| A cheap target read works | `latest_usage` in 0.074 s at load 233 [M] |
| One-driver claims already exist | every actuator takes `runs/by-sid/<sid>` [M] |

What is missing is the glue, plus four code gates that send a self-initiated caller down the wrong path:

1. Nothing turns a StopFailure into an actor. The hook only writes a marker, a request and a fact.
2. The **remote** recycle form is the one that proves the session is at rest and can SIGTERM. It refuses any caller
   whose env still carries the subject's `CLAUDE_CODE_SESSION_ID` (R1). Every hook descendant inherits that variable.
3. The **self** form never sets `RCY_REST_PROVEN`, so it always *types* `/exit` through kitty. That is the 435 s
   pane-38 shape.
4. `lr-handoff`'s placed-move and admission seams accept only `reconciler` or `cc-lr-move` as the placer.

Two further gaps belong to the decentralized design itself:

- **No atomic per-account seat ledger.** N movers deciding at once would herd onto one account.
- **No operator flag scopes a new zero-human actuator.**

**Expected latency** [E]: about 2-4 min per session, all in parallel, so a whole cohort completes in roughly the
slowest member's time, about 5-8 min. The method is in §5.

For comparison, the incident measured [M]:

- death to engaged: 81-166 min per session;
- reconciler R spawn to engaged, on a successful attempt: 5.7-14.9 min;
- a failed first attempt: 24.5-33 min.

**Coverage limit.** The self path covers only sessions that *attempt a turn* on the capped account, because only
those fire StopFailure. Idle sessions recover lazily at their next turn attempt, which does fire it. They can also
stay on the existing idle lane. In the incident, panes 20 and 30 went LIMITED at their next turn: 03:13Z and 03:19Z
[M, markers].

---

## 1. Inputs and kitty dependencies

### 1.1 What the hook already has at the instant of death [M]

| input | source | evidence |
|---|---|---|
| session id, transcript path, cwd, `error` | the StopFailure payload | `hooks/stop-failure-marker.sh:23-27` (verbatim capture); `:109-114` |
| `resetsAt`, `rateLimitType`, death uuid | one bounded `tail -c 131072 \| jq` of the transcript; 0.01 s on 4 MB | `:325-371` |
| account and config dir | the inherited `CLAUDE_CONFIG_DIR`, resolved through accounts.json aliases | `:121-139` |
| pane id | `CC_PANE_ID` / `KITTY_WINDOW_ID` / `ITERM_SESSION_ID` env | `:163` |
| claude pid | the hook's **PPID is claude itself** | `ps -axo pid,ppid,pgid,sess,tty,stat,pri,command` ⇒ hook `mailbox-wake-arm.sh` 11020, PPID 5276, `Ss`, tty `??`, PRI 31; `ps -o … -p 5276` ⇒ `claude`, `ttys022`, PRI 31 |
| pane tty | `ps -o tty= -p $PPID`, kitty-free | same command: claude 5276 on ttys022 |
| `CLAUDE_CODE_SESSION_ID` | exported into every descendant of a session | `hooks/session-continue.sh:194` |
| scope (5h / 7d / auth / model) | the hook's own classifier | `:576-607` |

Live check: all 7 incident StopFailure markers carry `pane` and `config_dir`. Measured with
`jq … rate_limit__next3.jsonl` ⇒ 3d1d988a/30, 3e929a81/20, 769b7294/48, 7aae55e1/38, d7eb73d2/32, db755a94/41,
e80b61f4/55, all on `.claude-tertiary`. The hook fired within the first minute of each death:

- 7aae55e1 02:32:05Z;
- db755a94 02:31:07Z, re-fired 21 times;
- d7eb73d2 02:32:27Z.

Hooks are spawned as **session leaders with no controlling tty** (`Ss`, `??` above). A hook therefore cannot use
its own tty. It must read claude's tty from `ps`.

Registration: `~/.claude/settings.json` `.hooks.StopFailure` has `timeout: 10`. All four account dirs symlink to it
(`jq '.hooks.StopFailure'` over each `settings.json`) [M]. An actor therefore has to detach from the hook.

### 1.2 What `lr-handoff.sh` and `handoff-fire.sh --recycle` need

`lr-handoff.sh` takes `--sid`, `--config-dir`, `--cwd`, `--target` and `--launch --in-place`, plus
`--source-pane P` for the driver form (`lr-handoff.sh:3-12`). The reconciler's R passes exactly this, with
`--record-id`/`--attempt` (`lr_recon/act.py:101-130`). The env is `LR_PLACED_BY=reconciler`, `LR_INPLACE_AWAIT=0`,
`CC_RECYCLE_BGWORK_ANSWER=cancel`, `LR_WAKE_GUARD_S=30`, `LR_ADMIT_TOKEN_PATH` and so on (`act.py:55-92`).

lr-handoff selects its form as follows:

- **SELF** when `SID == $CLAUDE_CODE_SESSION_ID` and `KITTY_WINDOW_ID` is set (`lr-handoff.sh:404-413`,
  `:460-464`).
  - Its precheck is then *record-only*: the probe's rc is ignored (`:1531-1560`).
- **DRIVER** otherwise: the pane comes from the registry (`:414-435`), and the probe's verdict gates
  (`:1435-1493`).
- **Target `auto`** calls `claude-accounts --route` (`:719`).
- **Router re-check** (`lrh_target_routable`, `:1358`) runs unless `lrh_placed` holds. That accepts only
  `reconciler` or `cc-lr-move` (`:306-312`).
- **Admission** is the first of these that applies:
  - a caller token (`:1572-1586`);
  - a swap, which needs `--no-prompt` (`:328-330`);
  - otherwise `lr_capacity_probe_corrected` (`:1592`), the 30-s-bounded probe that returned `probe-error` all
    night.

handoff-fire's in-place transplant recycle (`RCY_ARGS`, `lr-handoff.sh:1961`) takes `--resume-launcher`,
`--resume-cfg` and `--transplanted-source`. In the driver form it adds `--source-pane/--source-session`.

### 1.3 The kitty reads, and which ones a self-initiated path can skip

"Self-initiated" here means a detached worker that already holds claude's pid and lstart, its tty, its sid and its
pane id from §1.1.

| kitty read (07 §6) | where | what it proves | the self path's answer |
|---|---|---|---|
| pane → tty resolver, registry bind and pin | `as_tty_classified` `handoff-fire.sh:2051`; `hf_remote_source_bind` `:2690`; `hf_remote_source_pin` `:2932-2966` (refuses `RESOLVER-CANNOT-TELL`) | pane P holds session S, and S's pid sits on P's tty | **Skip.** The hook's PPID *is* the claude. Pin by `(pid, lstart)` (`hf_exit_signal_pin` already does this kitty-free: `:3996-4031`, through `~/.claude*/sessions/*.json` and the tty tree). The registry is also not needed: 14 of 44 sessions had no row (`LIMIT_DETECT_100P.md` §1 table). |
| connect probe | `hf_recycle_kitty_probe` `:1566` | later kitty steps will work | **Skip** (advisory). With a staged successor and a SIGTERM exit, no later step needs kitty. |
| focus | `hf_focus_gate` in the last read, `:3826-3830` | the operator is not in the pane | **Replace** with `lsappinfo front` ≠ kitty, or HID idle ≥ the age of the death (07 §6). From PRI 31 the kitty read itself costs 0.05-0.08 s (07 §0 table) [M, axis 07]. |
| composer | `recycle_composer_gate` `:3832`; unreadable ⇒ hold at `:3833` | no operator draft is lost | **Keep, demoted.** It is cheap at PRI 31 (`get-text` 0.08-0.09 s, 07 §1 #7). On *unreadable*, proceed only when HID idle exceeds the seconds since death, since nobody can have typed. Whether an unsent draft survives SIGTERM is [H] (07 §6). |
| watcher pane probe (`it2 session list`) | 07 §6: `:4362-4421`, `:19967-20004` | the watcher could type the relaunch | **Advisory.** It is needed only for the typed fallback (no claim within 20 s). Measured from PRI 31: 0.38-1.25 s, 5/5 (07 §0). |
| typed `/exit` and read-back | `hf_exit_readback` `:3936ff` | the session exits | **Avoid** with SIGTERM (`hf_exit_signal` `:4033-4060`). This needs `RCY_REST_PROVEN=1` (see B4). |
| background-work dialog keystrokes | watcher; e.g. pane 38's 22:36Z rows | the exit is not blocked | Avoided by SIGTERM. CC 2.1.293 SIGTERM runs `shutdown()`, which stops background shells itself (`:3962-3968`). For a limited source, jobs do not hold: "the source account is rejected … they end with the exit" (`:3268`). |

So the kitty-free critical path is:

1. transplant (disk);
2. at-rest and limit re-read (disk);
3. stage (disk, `lib/pane-successor.sh:99-123`);
4. SIGTERM (kernel);
5. claim (the pane shell's local rename, `lib/pane-successor.sh:125-182`);
6. engagement (disk).

kitty is left with three jobs:

- a launcher-rooted pane, which has no shell to claim the stage and goes to REPLACE via `kitty @ launch`;
- the typed fallback when no claim arrives;
- optional advisory reads.

From PRI 31 all three answer in at most 1.25 s (07 §0 [M]). That matters because the incident's "deaf kitty" was
the PRI-20 *caller*: kitty answered `ls` in 70 ms at 20/core (03 §0.2 [M]).

---

## 2. Process survival and band

**A setsid'd descendant of a session tree stays at PRI 31 and is reparented to launchd** [M]:
```
/usr/bin/python3 -c 'Popen(["/bin/sleep","6"], start_new_session=True)'; ps -o pid,ppid,pgid,pri -p <child>
⇒ 91833  PPID 1  PGID 91833  PRI 31  (load1 232.88; own tree: zsh 31 → claude 31 → bash 31 → zsh 31 → kitty 47)
```

**Hook-spawned daemons live for days at PRI 31 with PPID 1** [M]. Measured with
`ps -axo pid,ppid,pri,etime,command | awk '$2==1 && /lead-crash-watchdog/'`: 31 at PRI 31 and 1 at PRI 26, elapsed
up to 1 d 04:41. These are `lead-crash-watchdog.sh` daemons that a SessionStart hook spawned with `( … ) & disown`
and HUP ignored (`hooks/lead-crash-watchdog.sh:2208-2604`). The PRI-26 one is ordinary timeshare decay below base 31.

**Surviving the claude's own exit is proven by the recycle watcher.** handoff-fire spawns it through
`detach()` = python `start_new_session=True` (`handoff-fire.sh:2140-2157`). The header explains why: CC SIGKILLs the
tool call's whole process group on `/exit`, so a plain nohup child dies. A setsid child survives. All 16 in-session
self recycles since 2026-10-19T12Z completed `successor-claimed` and then `engaged` *after* their own claude exited
(handoffs.jsonl, §5) [M].

That the band stays exactly 31 *after* the ancestor claude has exited is [H], strongly supported:

- XNU sets the task role/QoS at fork and does not re-derive it on reparent (04 §3.4: "the role survives `exec`").
- The PPID-1 daemons above read 31.

The live test in §8 settles it with one `ps -o pri`.

**Can the worker stage a successor and SIGTERM the claude that spawned its hook?** Yes. After setsid the claude is
no longer its parent. It is a same-uid process pinned by `(pid, lstart)`.

- `hf_exit_signal` (`:4033-4060`) is the actuator. It requires:
  - `RCY_REST_PROVEN=1` (`:4037`);
  - a stage whose `watcher_pid` is the calling watcher (`hf_succ_ours_staged` `:4902-4908`).
- The stage's consumer refuses unless the watcher is alive with the same lstart (`lib/pane-successor.sh:162-165`),
  so the detached worker, or the watcher it spawns, must outlive the claim.
- Measured on this path in the incident: 8 `recycle-exit-signal` rows. For example pane 38: SIGTERM 04:14:27Z,
  claimed 04:14:37Z, engaged 04:15:16Z. The rows read "nothing typed". Since 12Z there were 24/24 claims of 24
  stages (`jq … handoffs.jsonl | sort | uniq -c`) [M].

**The hook's budget.** Its header bans a python fork on the death path (`stop-failure-marker.sh:239-241`,
`:325-330`). A python interpreter start at PRI 31 costs 0.20-0.30 s (03 §0.2 [M]), and ARM 3 already forks python
under a 2 s bound (`:620-623`). A perl or python double-fork plus setsid fits easily in the 10 s timeout. A
`perl -MPOSIX` fork+setsid+exec keeps the hook itself under about 50 ms [E, perl start-up versus python's 0.2 s].

---

## 3. Target choice without `claude-accounts --place`

**The tail read is cheap and sufficient** [M]. Measured at PRI 31, load1 ≈ 228, with
`python3 -I -c '…capped.latest_usage(~)'`: **0.074 s wall**. Readings:

| account | weekly | 5h | resident sessions (`k_native`) |
|---|---|---|---|
| next | 41 % | 22 % | 11 |
| next2 | 67 % | 31 % | 17 |
| next3 | 100 % (`wire_7d_status: rejected`) | 11 % | 1 |
| next4 | 14 % | 5 % | 3 |

All rows are from 05:28:12Z. `latest_usage` (`lr_recon/capped.py:59-87`) tail-reads 256 KB and drops rows older
than 900 s. `capped()` (`:97-133`) is pure. It combines reset, wire rejection, live fact and pct.

Facts are files: `~/.reso/limit-recover/recon/facts/next3.7d.json` holds `resets_at 1792497600`, `src hook`. The
StopFailure hook writes them itself under `recon.on` (`stop-failure-marker.sh:609-629`).

So the "safe target" predicate is local and needs no network:

```
not capped(a, 5h) and not capped(a, 7d) and not (model scope capped)
  and weekly / 5h headroom ≥ the recovery floors (claude-accounts recovery_floors)
```

**The stay rule ports directly.** `EPS_STAY_S = 900` (`lr_recon/plan.py:36`, applied at `:396-404`): stay when the
source resets within 15 min. The hook already holds `resetsAt`.

**The seat cap.** `KMAX = 24` and `KMAX_RESIDENT = 40` (`jq '.router.KMAX, .router.KMAX_RESIDENT'
~/.claude/accounts.json`) [M].

- The placer gives `cap = max(0, KMAX − k_work − k_phantom)` (`bin/claude-accounts:6556-6567`).
- `_excluded` refuses `kmax-concurrency` when `k ≥ k_cap` (`:6052-6055`).
- The usage row carries `k_native`, a resident count that is ≥ the active count. Using it in place of `k_work` is
  conservative.

**The decentralized blocker is herding.** Nine movers reading the same row at the same second all pick the same
argmax account.

- The phantom ledger `logs/account-assignments.jsonl` (`claude-accounts:3907-3908`, read by `apply_assignments`
  `:4512-4543`) is an append-and-TTL count, not an atomic reservation.
- **What is needed: a lock-free seat ledger.** Seats are `seats/<acct>/slot.<i>` for `i < KMAX − k_native`, each
  created with `O_EXCL` (`( set -C; : > f )`, the hook's own latch idiom at `stop-failure-marker.sh:270`).
  - Pick the target by weight on headroom rather than by argmax, so collisions are rare.
  - On a full account, try the next one.
  - Also append a phantom row, so the router and the placer charge the seat.
  - Release the seat on `engaged` or on failure. A stale seat expires by TTL (pid + lstart in the file).

**The weight question** (lead obs #6). The reconciler charges `1 + subagents written in the last 10 min`
(`plan.mover_weight`, `plan.py:153`). That made db755a94 un-placeable at weight 19. A resumed lead restarts none of
its subagents by itself, so the self path would charge 1. This is a policy choice; see Open questions.

---

## 4. Ownership and policy

**One driver.** Every actuator takes the per-sid claim `runs/by-sid/<sid>.active` through `lr_claim_take`
(`scripts/limit-recover/lr-lib.sh:839`):

| actuator | where it takes the claim |
|---|---|
| reconciler | `hold_claim` `lr_recon/act.py:493-520` |
| poller | `lr-reset-poller.sh:1281-1291` |
| lr-fleet | `lr-fleet.sh:646-650` |
| cc-lr | `bin/cc-lr:375-383` |

The rule is: holder alive ⇒ `held`; holder dead or pid reused ⇒ steal (`lr-lib.sh:844-860`). A self worker that
takes the claim first, as owner `lr-self-recover` with its pid and lstart, makes the reconciler's `hold_claim`
return `held`, and nothing gets spawned or minted.

handoff-fire's R2 check (`handoff-fire.sh:16283-16287`) accepts a holder that "is this process or an ancestor". The
worker is the ancestor of its lr-handoff → handoff-fire chain, so that check passes.

**The fence comes first.** `lr_recon_may_act <sid> self-recover` returns `act/not-owned` before the reconciler owns
the record (`lr-recon-fence.sh` rules 1-6). The incident's ownership lag after death was 11-30 min [M,
`events.jsonl`]:

| sid | death | `own taken` |
|---|---|---|
| 7aae55e1 | 02:32:05Z | 02:43:16Z |
| d7eb73d2 | 02:32:27Z | 02:43:15Z |
| e80b61f4 | 02:45:04Z | 03:14:35Z |

A self worker at t≈1 s therefore always meets `not-owned`. If the reconciler already owns the record with a fresh
heartbeat, the worker defers and today's path runs. That makes the design strictly additive.

The hook's ARM-2 request (`stop-failure-marker.sh:445-553`) would otherwise reach the poller, which in the incident
dispatched a second `lr-fleet --one` (lead obs #4). The poller takes the same claim, so it gets `held`. Cleaner:
have the self worker mark the request self-handled, or skip ARM 2 while self-recover is on.

**Zero-human gate.** The flags are not what the brief assumed [M, `ls ~/.reso/limit-recover`]:

- `~/.reso/limit-recover/autorecover.on` **exists** (2026-09-29). It holds the operator ruling of 2026-09-28,
  "auto-recover ON" (`cat` of the file).
- `recon/autorecover.on` is absent.
- `recon.on` exists.

`recon/autorecover.on` gates only the reconciler's own scope (D1.9: `lr_recon/__main__.py:217-223`;
`census.py:345-350` sets `plan_only`). `autorecover.on` "is the single zero-human switch" for the hook and legacy
lanes (`docs/plans/LIMIT_RECOVER_FLEET_V2.md:143`, `:476`, `:531`). A hook-driven self-move is a hook-origin
unattended move, so the existing ruling plausibly covers it.

The house pattern, though, is one flag per actuator, never created by code:

- D1.9 split the reconciler out;
- the hook's kick and request arms each have their own file switches (`stop-failure-marker.sh:54-56`, `:319-323`).

So a new actuator should ship behind its own operator-created sentinel, for example `self-recover.on`, and go
through a shadow phase. **That is the operator's call.**

**The VOLUNTARY_ACCOUNT_SWITCH ruling.** "NOT a Stop-hook nudge" (`docs/plans/VOLUNTARY_ACCOUNT_SWITCH.md:40`,
`:382-390`) rejects an *advisory to healthy sessions* that spends model turns. Its evidence is the 1.5 % ceiling of
*voluntary* relocation (`:360-375`). 10-proactive §7 rejects the same thing for the voluntary shed.

This design differs on three counts:

- it is triggered by **StopFailure**, not Stop;
- its subject is **already capped**, so nothing is voluntary;
- it spends **no model turn**.

The ruling's scope does not reach it. That reading of scope is mine [H]; the repo lesson "Partial evaluation reads
as complete" (`.claude/rules/agent-operating-lessons-situational.md:154`) argues for asking the operator, not
assuming.

---

## 5. Expected latency

**Self-initiated recycles, all handoff-fire at PRI 31 from inside the session** [M]. Command:
`jq 'select(.ts>="2026-10-19T12")…' ~/.claude/logs/handoffs.jsonl`. These are fresh-mode (context) recycles with a
typed `/exit`. The measure is handoff-fire start to `engaged` (`elapsed_s`), n = 16:

| min | p50 | max |
|---|---|---|
| 79 s | 114.5 s | 459 s |

The values were 79, 101, 103, 105, 105, 106, 108, 113, 116, 133, 143, 145, 160, 181, 269 and 459 s.

The brief's F9 trio, measured intent → engaged:

| pane | time | note |
|---|---|---|
| 24 | 104 s | |
| 55 | 144 s | |
| 38 | 435 s | 2× `nudge-held`, a `/exit` retype, a background-work dialog answered by keystroke at 22:35-22:36Z |

Pane 38's tail is the typed-exit tax. SIGTERM removes it.

**Placed recycles, handoff-fire at PRI 20 under the reconciler or the move lane** [M, same file], start to
`engaged`, n = 8:

| min | p50 | max |
|---|---|---|
| 126 s | 386.5 s | 726 s |

The values were 126, 128, 159, 340, 433, 559, 725 and 726 s. Even here the SIGTERM → claim → engaged tail was
30-40 s (pane 38: 04:14:27 → 04:14:37 → 04:15:16Z; pane 30: 05:14:52 → 05:15:42Z).

**Reconciler R, whole attempt** [M, `recon/events.jsonl` spawn/exit, plus the handoffs rows]:

| sid | spawn → handoff-fire start | spawn → engaged |
|---|---|---|
| 7aae55e1 #3 | 213 s | 341 s |
| e80b61f4 #2 | 340 s | 773 s |
| 3e929a81 #1 | 221 s | 562 s |
| db755a94 #3 | 445 s | 604 s |
| 3d1d988a #1 | 767 s | 893 s |

Failed first attempts:

| sid | spawn → exit | result |
|---|---|---|
| 7aae55e1 #1 | 24.5 min | rc 6 |
| d7eb73d2 #1 | 33.1 min | rc 6 |
| e80b61f4 #1 | 31.0 min | |
| db755a94 #1 | 31.0 min | |

**Death to engaged in the incident** [M, markers plus `engaged` rows]:

| sid | time |
|---|---|
| d7eb73d2 | 81 min |
| e80b61f4 | 81 min |
| 7aae55e1 | 103 min |
| 3d1d988a | 116 min |
| 3e929a81 | 130 min |
| db755a94 | 166 min |

**Self path estimate** [E]. Method: measured phase costs at PRI 31 where they exist, and a scaled PRI-20 prelude
where they do not.

| phase | estimate | basis |
|---|---|---|
| hook → detached worker | ≤ 1 s | measured setsid spawn; hook p50 0 s (`LIMIT_DETECT_100P.md:101`) |
| fence, claim, seat | < 1 s | file operations |
| target read | 0.074 s | [M] |
| wait for at-rest (limit record already written) | 0-30 s | [H] |
| lr-handoff prelude: audit, bundle, git-status, transplant copy + sha, preseed | 15-60 s | the PRI-20 213-767 s, divided by the measured 17-44× band factor for CPU-bound reads (03 §0.2), floored for disk I/O |
| handoff-fire start → SIGTERM | ≈ 40 s | pane 38 R#3 reached SIGTERM 79 s after its start *at PRI 20* |
| claim + engagement | 30-45 s | measured on 8 exit-signal rows |

The total is about **2-4 min per session**. N sessions run in parallel, so a cohort finishes in about **5-8 min**
[E]. The incident took 81-166 min. The parallel load cost is one claude out and one in per session. The lead
measured fired sessions engaging in 25-46 s at load 333-356 (00-lead §Gate timeline).

---

## 6. Blockers

| # | blocker | file:line |
|---|---|---|
| B1 | Nothing turns StopFailure into an actor. The hook writes a marker, a request and a fact, and the request waits for poller → fence → reconciler. | `hooks/stop-failure-marker.sh:445-553`, `:609-629`; `lr-reset-poller.sh:172-176` |
| B2 | The hook has a 10 s timeout and a death-path budget ("no python fork"), so it must detach through setsid in milliseconds. | `~/.claude/settings.json` `.hooks.StopFailure[0].hooks[0].timeout = 10`; `stop-failure-marker.sh:239-241`, `:325-330`; pattern at `handoff-fire.sh:2140-2157` |
| B3 | R1 self-refusal. The remote form refuses when `$CLAUDE_CODE_SESSION_ID` equals the named sid. Every hook descendant inherits that variable. | `handoff-fire.sh:2634-2639`, `:16243-16245`, `:16258-16259`, `:16270-16272`; `hooks/session-continue.sh:194` |
| B4 | The self form cannot use the SIGTERM exit. Its last read returns before `RCY_REST_PROVEN=1`, so `hf_exit_signal` declines and `/exit` is typed through kitty. An unreadable composer holds. | `handoff-fire.sh:3837` vs `:3918`; `:4037`; `:3833`; typed read-back `:3936ff`. lr-handoff picks SELF on the env: `lr-handoff.sh:404-413`, `:460-464` |
| B5 | The remote form's kitty-dependent identity and safety reads | resolver `handoff-fire.sh:2051`; registry bind `:2690`; pin `:2932-2966`; focus `:3826-3830`; composer `:3832-3833`; watcher pane probe (07 §6 `:4362-4421`, `:19967-20004`) |
| B6 | Routing re-check and placer seam. `auto` calls `--route`. `lrh_target_routable` runs unless `LR_PLACED_BY ∈ {reconciler, cc-lr-move}`. | `lr-handoff.sh:719`, `:1358`, `:306-312`, `:1429-1434` |
| B7 | Admission. Without a caller token the 30 s-class probe runs. A swap needs `--no-prompt`, but a limited move wants a continue prompt. | `lr-handoff.sh:1572-1612`, `:328-330`; mint at `scripts/lib/capacity-admit.sh:810-849` (a file write) |
| B8 | No atomic seat ledger, so concurrent movers herd past `KMAX`. | `bin/claude-accounts:6556-6567`, `:6052-6055`, `:3907-3908`, `:4512-4543`; `KMAX=24` |
| B9 | Coexistence: the claim must be taken first, and the ARM-2 request makes a second actor (lead obs #4) | `lr_recon/act.py:493-520`; `lr-lib.sh:839-892`; `lr-reset-poller.sh:1281-1291`; `stop-failure-marker.sh:548-551` |
| B10 | Policy. No per-actuator zero-human flag exists, and the scope of the voluntary-switch ruling needs to be confirmed. | `LIMIT_RECOVER_FLEET_V2.md:143`, `:476`; `__main__.py:217-223`; `VOLUNTARY_ACCOUNT_SWITCH.md:40`, `:382-390` |
| B11 | Population edges: idle sessions (no StopFailure; ceff45c5 had 0 markers [M]); teammates; panes with no pane env; launcher-rooted panes (REPLACE needs `kitty @ launch`); leads with live teammates; the 2/128 `sdk-cli` misses | `stop-failure-marker.sh:425-474`; `lr-handoff.sh:1497-1508`; `handoff-fire.sh:3893-3902`; `LIMIT_DETECT_100P.md:101` |
| B12 | Re-fires, up to 30× per sid, need a per-sid, per-death latch | `stop-failure-marker.sh:484-501` |
| B13 | At-rest misreads. Lead defect #3 (goal replay) is fixed on main by c82a349ce (`hf_transcript_at_rest` at about `:2985-3020`), but any future "turn in flight" misread blocks both paths alike. | `git show c82a349ce` |

---

## 7. Minimal design

The principle: **strictly additive.** Any refusal falls back to today's request → reconciler path.

**Stage 0: in the hook.** Inside `stop-failure-marker.sh`, for `rate_limit` only.

- Gate it on all of the following:
  - a new operator-created `$LR_STATE/self-recover.on`;
  - not `.request-off`;
  - not a teammate;
  - not already handed off;
  - a non-empty pane and pid.
- Take an `O_EXCL` latch `self-latch/<sid>.<death_uuid>`, the same idiom as `:534`.
- Spawn the worker with a double fork plus setsid:
  `/usr/bin/perl -MPOSIX -e 'fork and exit; POSIX::setsid(); exec @ARGV' lr-self-recover.sh …`. Pass sid, pane,
  claude pid = `$PPID` and its lstart, cfg, tp, `resetsAt`, `rateLimitType` and scope.
- Exit 0 with empty stdout. The hook stays fail-open.

**Stage 1: `lr-self-recover.sh`, the new worker.** It runs at PRI 31 with PPID 1.

1. **Fence and claim.** If `lr_recon_may_act <sid> self-recover` defers, exit. Then `lr_claim_take` with owner
   `lr-self-recover`; if it returns `held`, exit.
2. **Stay rule.** If `resetsAt − now < 900`, release the claim, let today's path handle it, and exit.
3. **Target and seat.**
   - Read `latest_usage` and `facts/` and keep the non-capped candidates above the floors.
   - Take an `O_EXCL` seat from `seats/<acct>/slot.<i>` for `i < KMAX − k_native`, choosing by weight on headroom.
   - Append a phantom row to `account-assignments.jsonl`.
   - If there is no seat, release, leave the ARM-2 request, and exit. The reconciler then puts it in WAIT_SLOT, as
     today.
4. **At rest.** Bounded wait, about 60 s, until the transcript tail is at rest and the last record is the limit
   (`lr_last_api_error` plus `hf_transcript_at_rest`).
5. **Admission.** `cc_capacity_token_mint <sid>` (a file write; it is net-zero: one claude exits, one starts), then
   pass `LR_ADMIT_TOKEN_PATH`.
6. **Run lr-handoff.** Use the R argv (`act.py:101-130`) with `--source-pane <pane>`. The env mirrors `act.py:55-92`,
   with these differences:
   - `LR_PLACED_BY=self`, which needs one clause in `lrh_placed`, `lr-handoff.sh:306-312`;
   - a new origin marker, for example `HF_RECYCLE_ORIGIN=self-detached`. `hf_remote_is_self` (`:2634-2639`) treats
     it as not-self when the named claude pid is **not** an ancestor and the at-rest proof will run. That is R1's
     own premise, made explicit. Do not just `env -u` the variable;
   - kernel-identity hints (`HF_SELF_CLAUDE_PID/LSTART/TTY`), so the resolver, bind and pin are replaced by `ps`
     checks (07 §6 table, row 1).
7. **The proven remote tail runs unchanged.** Transplant, confirm, last read (at rest and limited, so
   `RCY_REST_PROVEN=1`), stage the successor in resume mode, SIGTERM the pinned claude, the pane's consumer claims,
   and the watcher verifies engagement. Focus, composer and pane-probe reads stay *advisory*, under the HID-idle rule
   in §1.3.
8. **Settle.** Release the seat and the claim, and write the outcome next to the request so the poller drops it. On
   any failure, unconfirm (existing), release, and leave the request for the reconciler.

**Coexistence.** The reconciler's census later sees the session live on its target (`r-in-place` / NOT_NEEDED, the
same as d7eb73d2's `stale … live on .claude-next already`). Its `hold_claim` refuses while the worker runs.

**Rollout.** Start in shadow mode: the worker logs its decisions and seat picks, then exits before step 6. Then
enable it on one account.

Size [E]: about 250 lines of new worker. Edits: about 30 lines in handoff-fire (origin, kernel identity), 5 lines in
lr-handoff (the placer value), 20 lines in the hook. Plus bats tests.

---

## 8. What only an operator-run live test can settle

Use a throwaway session on an account that is genuinely capped, after the operator creates `self-recover.on`.

1. **Survival and band after claude exits.** Does the hook-spawned, setsid'd worker survive the 10 s hook timeout
   and the claude's SIGTERM, and does `ps -o pri` read 31 *after* the claude is gone? The stand-in measurement and
   the claim history make both likely ([H], §2).
2. **TUI state at death.** On a weekly cap, does the TUI show a modal (rate-limit options or upgrade) that changes:
   - the at-rest proof;
   - the SIGTERM shutdown, which is proven only "at rest" (`proof-sigterm-2.1.293.md`);
   - or the composer read?

   Measure the time from the hook firing to the transcript being at rest.
3. **End to end without kitty RC.** Run with the kitty reads marked advisory, then time StopFailure → engaged. One
   session first, then N ≥ 9 at once, to measure transplant I/O and boot contention at the fleet's normal 20-35/core.
4. **The seat ledger under contention.** N movers at once: no account over `KMAX`, seats released on every path,
   no herd.
5. **Coexistence with `recon.on` live.** The reconciler and the poller yield (`held`) with no RECON-DEFECT, and the
   census closes each record once.
6. **Rulings, which no test can supply.**
   - a per-actuator zero-human flag for StopFailure self-recovery;
   - whether VOLUNTARY_ACCOUNT_SWITCH's "NOT a Stop-hook nudge" covers this;
   - seat weight 1 against the reconciler's subagent weight;
   - whether an unreadable composer may proceed under the HID-idle rule.

---

## 9. Deviations and limits

- I did not run `claude-accounts --rank` or `--route`. They may refresh caches, and the brief requires read-only
  work. Router and placer costs at PRI 31 come from axis 03 (§F7: 1.6-3.1 s for the CPU parts; network and keychain
  bounded at 12 s and 8 s).
- The R spawn → bundle gap is about 10 min on 3d1d988a (spawn 05:00:49Z, bundle 05:11:10Z). It is not broken down
  here. Whether that is preseed, wake guard or interpreter starts at PRI 20 is [H].
- The PRI-31 self-recycle sample is context recycles, which have no transplant. The transplant cost at PRI 31 is
  estimated, not measured.
