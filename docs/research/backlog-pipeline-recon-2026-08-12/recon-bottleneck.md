# recon-bottleneck — what actually consumes session slots, what the real cap is, and what crowded the operator out

**Measured 2026-08-12 ~08:45Z on this box. Read-only.** Every number below carries its command or its
file:line. Where an instrument could not attribute, that is said rather than guessed.

---

## 1 · THE CAP — there is no "15". There are four different caps, and none of them is a session count.

**The operator's "~15" is a documented folklore figure, and this repo already said so before I looked.**

- `docs/plans/CONCURRENCY_PROGRAM.md:574` — *"'~15 sessions' is folklore precisely because a number
  once got published without one [a measurement]."*
- `docs/plans/CLOUD_OBSERVABILITY.md:1160` — *"an unmeasured ceiling is how '15 sessions' became
  folklore."*
- The nearest thing to a real origin is `docs/plans/MACHINE_CAPACITY_V2.md:1026`: the load gate
  *"refusing LIVE at LOW session count — `vm.loadavg` 52.02 on 10 cores = 5.20/core vs 2.0 ceiling
  **at only 12–15 sessions**"*. **"15" is the session count at which the LOAD gate starts refusing on
  this hardware — not a limit anyone set, and not a number any code reads.**

### What actually binds, in order of who enforces it

| # | Cap | Value | Where it lives | Enforced by | Scope |
|---|---|---|---|---|---|
| C1 | **Load per core** | `2.0`/core | `scripts/lib/capacity-admit.sh:121` `CC_HW_DEFAULT_MAX_LOAD_PER_CORE=2.0` (shared literal; `scripts/handoff-fire.sh:4076` expands the same constant) | `capacity_gate()` in handoff-fire (UNBOUNDED) + `cc_capacity_admit()` (BUDGET-BOUNDED) | every `handoff-fire.sh` fire |
| C2 | **Memory headroom** | `4 GB` reclaimable | `scripts/lib/capacity-admit.sh:122` `CC_HW_DEFAULT_MIN_HEADROOM_GB=4` | same pair | same, **plus** the Agent tool |
| C3 | **Agent spawns per session** | `60` | `hooks/agent-teams-enforce.sh:327` `CC_SPAWN_MAX_PER_SESSION:-60` | PreToolUse deny, **hard, not bounded** (`:315-320`) | the `Agent` tool only |
| C4 | **Agent spawn depth** | `2` | `hooks/agent-teams-enforce.sh:328` `CC_SPAWN_MAX_DEPTH:-2` | PreToolUse deny, hard | the `Agent` tool only |
| C5 | **Dispatcher fleet ceiling** | `6` | `bin/cc-dispatch:332` `CEILING="${CC_DISPATCH_CEILING:-6}"` | `cc-dispatch` admission | **only cc-dispatch's own claimed workers** |

**It is a LOCAL POLICY + MACHINE limit. It is not Anthropic-side.**
- No API-side concurrent-session cap is observable: one literal `too many concurrent` across the
  whole of `~/.claude/logs/bash-execution.log`; the off-box ceiling is explicitly recorded as
  **UNMEASURED** with the blocker named as *create reliability, not quota*
  (`CONCURRENCY_PROGRAM.md` §S5-CEILING, l.578-604).
- Quota is not binding now: `claude-accounts --json` → weekly 48 / 44 / 8 / 52 %.

### 🚨 The load ceiling cannot hold the line — by design, in two separate ways

1. **`CC_ADMIT_BUDGET` default 3.** `scripts/lib/capacity-admit.sh:398-412` (`_cc_admit_spend`): after
   3 **consecutive** refusals the next evaluation **ADMITS** with `basis:"budget-expired"` and pages.
   Stated intent (`:35-40`) is to stop a saturated box permanently blocking a *recovery* path. Effect:
   **no unattended spawner can ever be held out for more than 3 attempts.**
2. **The Agent tool turns the load term OFF.** `hooks/agent-teams-enforce.sh:183` —
   `CC_ADMIT_LOAD_TERM=off cc_capacity_admit agent-tool "…"`. The file's own comment (`:311-319`)
   calls the Agent tool *"the HIGHEST-volume spawn surface"*. So the single largest source of panes is
   gated on **memory headroom only** and reads `basis:"headroom-only"` — confirmed live: today's IDL
   has `8 × admit / headroom-only / agent-tool` and **zero** `measured` rows for that caller.

**Net: C1 (the thing the operator experiences as "~15") applies in full ONLY to `handoff-fire` fires,
i.e. to the operator's own `/handoff` and `/ship`-adjacent paths — and is disabled or budget-released
for everything unattended.** That asymmetry is the crowd-out generator, stated below in §4.

---

## 2 · LIVE CENSUS — 8 panes, and 5 of them are one research wave's teammates

**Counting method used, and why not the naive pgrep.** Memory `pgrep-f-matches-agent-briefs` is live
here: `pgrep -f claude` returns **96** on this box right now, because argv carries whole agent briefs
and every hook/watchdog path contains the string. I used the **argv[0]-anchored** predicate that
`bin/claude-accounts:416 concurrency()` uses — `ps -wwEo command=`, then `argv[0] == claude` or
`endswith /claude` or `endswith claude.exe` or contains `cli.js`, with `-p/--print/--version`
one-shots excluded and attribution by the **last** `CLAUDE_CONFIG_DIR=` match (`:2373`, deliberately
last, so prompt text that merely mentions the var cannot win). `claude.exe` is **not** a third
spelling to be thorough about — `bin/claude-accounts:2355-2362` records that it is the argv[0] of
every dispatcher/teammate/subagent session, and that omitting it once read *2 live where the truth
was 10*.

| Category | N | Evidence |
|---|---|---|
| Operator/lead top-level sessions | **3** | pids 83661 (57 m), 34451 (7 m), 52645 (7 h 03) — argv `…/.bin/claude --permission-mode auto --model claude-opus-5 --effort high` |
| **Agent-team teammates (this recon wave)** | **5** | pids 25808/34428/46791/58292/71218, all `…/bin/claude.exe --agent-id recon-*@session-ebbd173a --agent-type deep-research` |
| Autonomy/backlog-dispatched | **0** | dispatcher is `VENUE_ONLY=cloud` since 2026-08-11T19:0xZ (§3) |
| Orphans / derelicts | **2 surfaced, 0 reaped** | `cc-reaper.out.log`: `PAGE! claude-infrastructure-292 [crashed]`, `PAGE! wt-b384effb4100-56 [crashed]` — **both pages REFUSED (`cc-notify rc=2`)**, so the operator was never told |
| Off-box (cloud) | **41 rows, 1 ALIVE** | `cc-sessions --offbox`: 1 ALIVE · 8 STALLED · 7 ABANDONED · 12 NOT-STARTED · 7 LANDED |

**Cross-checks agree:** `cc-sessions` table = 8 local rows (399, 408, 415, 416-420);
`cc-reaper self-check: 8 live pane(s)`; `it2 session list --json` = 8 panes.
`claude-accounts --json` reported `k=9 / k_work=8` in the same minute — Δ1 is a transient (this wave
is churning); it is a race, not a disagreement about method.

🔑 **5 of 8 slots (62%) are one lead's research fan-out.** Teammates register in
`~/.claude/cc-registry` as ordinary pane sessions (uuids 416-420, `claude-infrastructure-4xx`,
account `claude-secondary`), carry their own `mailbox-wake-arm` + `cc-await-ping` + `lead-crash-watchdog`
child processes, and are counted by `concurrency()` exactly like a human's pane. **There is no
accounting anywhere that separates "the operator's 15" from "the agent's fan-out".**

**Peak concurrency, measured (`~/.claude/logs/account-utilization.jsonl`, summing `k` across accounts
per sweep timestamp):**

| Day | PEAK | MEAN | samples |
|---|---|---|---|
| 2026-08-10 | **54** | **40.5** | 130 |
| 2026-08-11 | 31 | 14.7 | 232 |
| 2026-08-12 (to 08:45Z) | 11 | 7.0 | 85 |

54 was **sustained**, not a spike: 54 at every sweep from 14:23Z to 17:37Z on 08-10. Breakdown at
17:37:08Z — `next3` **36 sessions at 92% weekly**, next 7, next2 6, next4 5.
*(This log begins 2026-08-10T05:58Z, so the earlier half of the operator's "week" has no concurrency
series. Do not read its absence as low.)*

---

## 3 · SPAWN SITES — every place backlog/autonomy work creates a session, and its throttle

Coverage claim is sound because `scripts/lib/pane-spawn-log.sh` instruments **every in-tree spawn
primitive** and `scripts/pane-spawn-coverage-lint.sh` fails the gate when a new one lands without it
(`pane-spawn-log.sh:29-36`). A pane with no row here was spawned outside this tree.

| Spawn site | Trigger | Throttle | Status |
|---|---|---|---|
| **`Agent` tool** (teammates + research subagents) | any agent, in-session | C2 headroom only (load term OFF, `agent-teams-enforce.sh:183`) + C3 60/session + C4 depth 2 + a duplicate-worker lease gate (`:120`) | **LIVE, the highest-volume surface** |
| **`scripts/handoff-fire.sh`** (dispatched sessions, `/handoff`, waves) | agents and operator | C1 load + C2 headroom, **unbounded** refusal (`capacity-admit.sh:107-111`: unbounded is deliberate "a human is at the keyboard") | LIVE |
| **`bin/cc-dispatch`** (launchd `com.claude.dispatcher`, 300 s) | backlog rows | C5 ceiling 6 over its **own claimed workers only**, + `CC_DISPATCH_MAX_SPAWN:-2` per pass | LIVE but **venue-filtered to cloud** |
| `scripts/limit-recover/lr-reset-poller.sh` (launchd, ~10 min) | limit-parked sessions | routes through handoff-fire ⇒ C1+C2; own budget via `cc_capacity_admit lr-fire-resume` | LIVE, **and failing 24×/h — see §5** |
| `scripts/boot-resume-launch.sh` | GUI login | `cc_capacity_admit boot-resume-launch` (budget-bounded) | armed |
| `bin/kitty-split-launch.sh` / `kitty-pane-menu` | operator keystroke | none (human-initiated) | n/a |
| **`scripts/autonomy-sweep.sh`** (launchd, 300 s) | — | — | **does NOT spawn panes.** Its `fired` counters are notify/page verdicts (`:345-398`, `:827-912`). It fires `backlog-consolidation-trigger.sh` and `cloud-return.sh` as subprocesses only. |
| `bin/cc-respawn` | recovery | — | no pane-spawn-log call site |

**cc-dispatch's ceiling deliberately does NOT charge for the operator's panes** — `bin/cc-dispatch:418-436`:
an earlier revision summed live sessions, measured 12 live vs 0 claimed, which at ceiling 6 gives
`free_slots = max(0, 6−12) = 0` **permanently and silently**. The fix charges only dispatch's own
claimed workers. The comment is explicit about the trade: *"Charging dispatch for human activity lets
the operator silently throttle autonomy to zero."* **The converse is the live defect: nothing charges
autonomy for the operator's need, so the two never see each other.**

**Dispatcher's own fires are small** (`~/.claude/autonomy/idl.jsonl*`, `actor=="cc-dispatch"`):
18 (08-08) · 30 (08-09) · 25 (08-10) · 33 (08-11) · 8 (08-12). It is **not** the volume source.

---

## 4 · CROWD-OUT EVIDENCE

### 4a · Panes created per day (`~/.claude/logs/pane-spawns.jsonl`, rows carrying a real pane id)

| Day | total panes | **Agent-tool teammates** (`chain:"it2-kitty"`, `ppid_comm:"claude"`) | **dispatched sessions** (`chain:"handoff-fire.sh>it2-kitty"`) | operator keystroke (`kitty-pane-menu`) |
|---|---|---|---|---|
| 2026-08-07 | 199 | **183 (92%)** | 13 | 0 |
| 2026-08-08 | 136 | 49 | 81 | 0 |
| 2026-08-09 | 90 | 28 | 57 | 1 |
| 2026-08-10 | 125 | 59 | 54 | 4 |
| 2026-08-11 | 145 | 43 | 89 | 6 |
| 2026-08-12 (partial) | 17 | 10 | 2 | 2 |
| **5 full days** | **695** | **362 (52%)** | **294 (42%)** | **11 (1.6%)** |

The `chain:"it2-kitty"` + `ppid_comm:"claude"` = Agent-tool classification is **not my inference** —
`hooks/agent-teams-enforce.sh:300-313` re-derived it independently on this same log: bare
`chain:"it2-kitty"` rows carry `ppid_comm=claude` **319/324**, against `chain:"kitty-split-launch.sh"`
rows carrying `ppid_comm=zsh` **16/16** as the positive control (a Bash tool call necessarily puts a
shell between, so the first shape cannot be one).

**~139 panes/day, 94% of them agent-initiated, 1.6% operator-initiated.**

### 4b · Where those panes worked — 71% never touched the operator's product

`cwd` of the 719 real-pane rows: **329 worktree-pool** · **181 claude-infrastructure** · 187 `/`
(the lr-poller's null cwd) · 13 `$HOME` · **7 lakehouse-lecture** · 2 `/tmp`.

### 4c · The operator's product work stopped

Commits in the last 7 days, per repo (`git log --since="7 days ago"`):

| repo | commits |
|---|---|
| **claude-infrastructure** | **884** |
| lakehouse-lecture | 124 — and **zero since 2026-08-10** (13/88/6/10/7 on Aug 6-10) |
| reso-landing-app | 1 |
| **reso-management-app** | **0** — last commit **2026-08-05** |

### 4d · 🔑 THE MECHANISM, in the repo's own words

Commit **`25f369292`** (2026-08-11 16:33 -0700), subject verbatim:

> `chore(dispatcher): pause to DECIDE-ONLY — 189 worker panes a day against an operator budget of ~15`
>
> CAPACITY: 189 panes fired in one day. The box sat at 2.19 load/core against handoff-fire's own 2.0
> ceiling, **which REFUSED this session's fire — i.e. the dispatcher had become a competitor to the
> operator for a ~15-session budget.**

That is the crowd-out, named and dated by the machine itself. It is **not** slot exhaustion — it is
**load exhaustion converted into a refusal that only the operator's path is subject to** (§1: C1 is
unbounded for handoff-fire, budget-released for unattended callers, and OFF for the Agent tool).

**The refusals are counted** (`~/.claude/logs/handoffs.jsonl`, `class=="refused"`,
`refuse_reason=="capacity"`): **12** on 08-09 · **46** on 08-10 · **6** on 08-11 — 64 total in the
window the log retains (it starts 08-09; earlier is rotated away). Sample details:

```
2026-08-09T10:36:15Z  load 307.26 on 10 cores = 30.73/core > ceiling 2.0/core
2026-08-10T07:55:24Z  load  60.72 on 10 cores =  6.07/core > ceiling 2.0/core
2026-08-10T07:46:43Z  load  47.94 on 10 cores =  4.79/core > ceiling 2.0/core
```

⚠️ **Attribution limit, stated rather than hidden:** all 64 rows carry `firing_sid: null`, so the log
cannot prove *which* of those 64 were the operator's fires versus a script's. The commit message
above is the one attributed instance. Treat 64 as the population and 1 as the confirmed operator hit.

**Second, independent corroboration** — `cc-reaper.out.log`, same period:

> `cc-backlog reap: 145 self-release(s) across 118 item(s) NOT counted as thrash — the dispatcher
> could not FIRE them (capacity/compose/worktree); that is a machine…`

**Third — the attention channel is also saturated:** `~/.claude/autonomy/pages/` holds **543** pending
desk pages, and the two crashed-session pages from today could not be delivered at all
(`cc-notify rc=2`). Backlog store: **322 open · 209 blocked · 6 claimed · 1369 done = 1906 rows**.

### 4e · What has already been done about it (and what it left behind)

- `25f369292` set `CC_DISPATCH_DECIDE_ONLY=on` (0 spawns, 306 journalled decisions).
- `8e179c429` + `9d2e50e34` added `CC_DISPATCH_VENUE_ONLY` and staged the flip behind an interlock —
  because *"the config flip alone fired 2 local panes"* (the deployed `~/.claude/bin/cc-dispatch`
  symlink trailed origin/main and the running binary did not know the flag).
- **The live plist has since dropped `DECIDE_ONLY`.** `~/Library/LaunchAgents/com.claude.dispatcher.plist`
  now reads `…CC_FIRE_CLOUD=on; export CC_DISPATCH_VENUE_ONLY=cloud; exec …cc-dispatch --once`,
  annotated `✅ INTERLOCK DISCHARGED 2026-08-11T19:0xZ … venue-only=cloud parked 272 of 315
  dispatchable item(s) and fired 0 local panes`.
- 🚨 **Tree ≠ live.** `launchd/com.claude.dispatcher.plist` in git **still exports
  `CC_DISPATCH_DECIDE_ONLY=on`**. The installed plist is a **real file, not a symlink**
  (`-rwxr-xr-x … Aug 11 20:22`), so nothing converges it. Anyone reading the repo will conclude the
  dispatcher is paused; it is not — it is cloud-only. Same class as memory
  `[[conclusion-must-reach-the-enforcing-store]]`, inverted: here the enforcing store is *ahead* of
  the tree.

---

## 5 · EXISTING GUARDS — one is inert, one is blind, one is dead

### G1 · Operator-presence beat — MEASURED, and consulted by NOTHING that spawns
`hooks/session-beat.sh` (write side) + `hooks/lib/cc-beat.sh` (read side, SESSION_REGISTRY_V2 §4.1/4.2)
maintain a real operator-presence signal, including `operatorT`, *"the sticky high-water mark of
operator presence"* (`cc-beat.sh:55`).

**Consumers (`grep -rln 'cc-beat\|cc_beat' hooks/ scripts/ bin/`): `hooks/teammate-auto-shutdown.sh`
and the library itself. That is all.**
`grep -l 'cc_beat\|cc-beat' scripts/handoff-fire.sh bin/cc-dispatch hooks/agent-teams-enforce.sh
scripts/autonomy-sweep.sh scripts/lib/capacity-admit.sh` → **NONE**.

**So the fleet knows whether the human is at the keyboard, and uses it only to decide whether to
CLOSE a teammate pane — never to decide whether to OPEN one.** This is the single highest-leverage
inert guard found.

### G2 · No quiet hours, no working-hours window, anywhere
`grep -rn 'quiet.hour|QUIET_HOUR|working_hours|WORK_HOURS|do_not_disturb'` over `hooks/ scripts/ bin/`
returns **zero** spawn-side hits. The only `quiet hours` in the tree is
`hooks/push-critical.sh:13` — about piercing **Pushover's** quiet hours, i.e. the opposite polarity.
The 08-10 peak of 54 held 14:23–17:37Z (07:23–10:37 local) — squarely inside the operator's day.

### G3 · The capacity gate — present, and structurally unable to protect the operator
Three independent reasons, all cited above: budget-releases after 3 (§1), load term OFF for the Agent
tool (§1), and `gate-off` admissions in the live population — `handoffs.jsonl` `class=="admitted"`:
**72 `gate-off` (08-09) · 97 `gate-off` (08-10) · 8 (08-11)** against 308/166/128 `measured`. On 08-10
that is **37% of admissions with no capacity term evaluated at all**. `capacity-admit.sh:71-77` warns
about exactly this: *"SPLIT ON `basis` BEFORE BELIEVING ANY RATIO COMPUTED FROM THESE ROWS."*

### G4 · Limit-recover auto-resume — firing 24 GUI window-creations/hour into an app that is not running
`lr-reset-poller.sh` has logged **784 `spawn_gui create-window` attempts** since 2026-08-10T12:24Z —
exactly **24/hour, every hour, unbroken** (4 parked sessions × 6 polls/h). **Every one fails:** the
GUI arm targets iTerm2 by bundle id (`lr-reset-poller.sh:311`), and **iTerm2 is not running** — this
fleet migrated to kitty (`ps`: kitty only). Its kitty arm is gated on `[ -n "${KITTY_WINDOW_ID}" ]`
(`:275`), which a **launchd job can never have**, so the poller is structurally incapable of using the
terminal that exists. The tmux fallback also produced nothing: `tmux ls` → no server.
Not a slot consumer — but 4 limit-parked sessions have been unrecoverable for 44 hours, silently, and
`docs/plans/backlog-consolidation-2026-08-09/OUT-panes.md` counts on this path.

### G5 · Caps that DO work
`CC_SPAWN_MAX_PER_SESSION=60` and `CC_SPAWN_MAX_DEPTH=2` are **hard** refusals, explicitly *not*
budget-bounded (`agent-teams-enforce.sh:315-320`: *"a budget that expires into an admit is not a
budget"*), built after a measured incident of **224 Agent spawns / 167 sessions over 3 generations**,
named as *"the measured ignition of the kernel watchdog panics"* — **4 panics in 7 days**
(`agent-teams-enforce.sh:212-213`; also `backlog-consolidation-2026-08-09/TRIAGE-CONTRACT.md:13`:
*"The machine is under load (4 kernel watchdog panics in the last week, 15+ live sessions)"*).
The duplicate-worker lease gate (`:120`) is the other working one.

---

## 6 · ADVERSARIAL PASS — what I checked because it would have refuted the above

| Hostile question | Checked | Result |
|---|---|---|
| "Is there an Anthropic-side concurrent-session cap you're ignoring?" | `grep -iE 'too many concurrent\|concurrent session limit'` over `bash-execution.log`; `CONCURRENCY_PROGRAM.md` §S5-CEILING | **1** literal hit; the off-box ceiling is recorded UNMEASURED with the blocker named as create-reliability, not quota. No API cap observable. |
| "Is the real constraint quota, not slots?" | `claude-accounts --json` | Weekly 48/44/8/52%. **Not binding now.** But at the 08-10 peak `next3` sat at **92% weekly with 36 sessions** — quota WAS binding on that account then. Both are true at different times; the honest statement is *load binds first on this box, quota binds per-account under burst*. |
| "Did the operator actually get blocked, or did they choose infra work?" | `handoffs.jsonl` capacity refusals; `cc-reaper` self-release line | 64 capacity refusals; 145 self-releases across 118 items attributed to "the dispatcher could not FIRE them (capacity/…)". **But `firing_sid` is null on all 64**, so only the `25f369292` instance is provably the operator's. Stated as a limit, not laundered. |
| "Are the `it2-kitty`+`claude` rows really teammates, or could they be a Bash tool call?" | `agent-teams-enforce.sh:300-313` independent re-derivation with its own positive control | Confirmed 319/324 vs 16/16. Not my inference. |
| "8 live sessions is nowhere near 15 — is there a bottleneck at all right now?" | live census | **Correct — it is not binding at this instant.** The bottleneck is episodic: mean 40.5 on 08-10, 14.7 on 08-11, 7.0 today. It binds during *waves*, which is when the operator wants to work. |
| "Is autonomy-sweep a spawner?" | `grep` over its spawn sites + pane-spawn-log | **No.** It fires notifications and backlog writes only. My initial assumption was wrong; corrected above. |
| "Is the dispatcher still paused, as the repo says?" | tree plist vs `~/Library/LaunchAgents` | **No** — live dropped `DECIDE_ONLY` at 2026-08-11T19:0xZ. The tree is stale. Would have made the whole §4e conclusion wrong. |

**Residual unknowns, named:**
- Concurrency series begins **2026-08-10T05:58Z**; `handoffs.jsonl` begins **08-09**. The first ~4 days
  of the operator's "week" have **no** concurrency or refusal series. Absence ≠ low.
- 112 git worktrees registered; **206 directories** under `~/Development/.worktrees/`. The 94-dir gap
  is unregistered residue. Not measured for disk/inode cost here.
