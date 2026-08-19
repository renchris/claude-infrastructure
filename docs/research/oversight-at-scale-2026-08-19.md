# Oversight at scale — how to run 30–50 units you actually oversee

**Question (operator, 2026-08-19):** *"How can we have more than 15 sessions that we WANT OVERSIGHT ON,
without things blindly going on by themselves?"*

**This is not the capacity question.** That one landed today (`orchestration-units-2026-08-19.md`,
`4a3bd3373`) and its answer — *fan-out is cheap if you express it as paneless in-process agents* — was
rejected, correctly: paneless is cheap **because** it removes the operator's view. Everything below is
scored on the operator's four levers, never on memory, load or quota.

**SEE** know a unit's state without going to look · **INTERRUPT** be pulled in when, and only when, a
unit needs a human · **STOP** halt or redirect any unit, at any time, from one place · **AUDIT**
reconstruct afterwards what a unit did and why.

**Sources.** Six measured axes in `docs/research/oversight-at-scale-2026-08-19/` (O1 + O1-VERIFY,
O2 + O2-VERIFY, O3, O4, O5, O6), read in full. Fresh measurements taken for this synthesis are marked
**MEASURED (here, 14:10–14:14Z)**. Labels throughout: **MEASURED** (someone ran it) · **INFERRED**
(read the code, did not execute the path) · **QUOTED** (vendor text) · **UNKNOWN**.

---

## 1. The answer

**You are already past 15, and past oversight — but not for the reason it feels like. Right now
16 live sessions produce 3 different totals from 3 instruments, 310 workflow agents fleet-wide have
started and never recorded a result, and the operator's real 4-hour reach is 4 sessions, not 15. The
binding constraint is not the unit count: it is that every oversight verb we own is addressed by a
PANE, so oversight costs one operator walk per unit and grows linearly with the thing you wanted to
scale. 30–50 units becomes overseeable exactly when the address stops being a pane — one census that
cannot omit a unit, one ranked queue that is silent by default, one stop that names any unit, one log
that stamps every action with the unit that took it. All four are reachable from things that already
exist; three of the four need wiring, not building.**

Four sentences that change what you build:

1. **The pane is not what makes a unit overseeable; the ADDRESS is.** `bin/cc-teardown:194` refuses an
   agent name outright — by construction, not neglect. Every empty STOP cell in §2 traces to the same
   missing thing: an id the operator can type.
2. **The stop button you were told does not exist, does — it is Anthropic's, not ours.** `/tasks` → `x`
   really aborts a running Dynamic Workflow (proved by a tripwire agent that never ran). But both keys
   you would instinctively press miss it, and one of them (`^X^K`) renders **no message at all**.
3. **The interrupt channel is not missing; it is unranked and 71% noise.** 2,383 alerts in 5.3 days,
   peak 235 in one hour, of which 1,691 mean "a unit stopped" — while 1,172 durable escalations sit
   100% unread because nothing is registered to read them.
4. **The cheapest brake is measured and it has a defect that makes it dangerous alone.** A `PreToolUse`
   deny reaches a Workflow agent mid-run and beats `--permission-mode bypassPermissions` — and the
   braked run **still reported `result:"DONE"`**. Ship the deny only with a HALTED stamp.

---

## 2. THE OVERSIGHT MATRIX — 7 unit classes × 4 verbs

`✅` works today, operator-reachable · `◐` partial or degraded · `❌` nothing · **(ours)** = a rail we
own · **(CC)** = Anthropic's. "by-construction" = the unit has no address in that channel and a patch
cannot close it without first minting one.

| Unit class | SEE | INTERRUPT | STOP | AUDIT |
|---|---|---|---|---|
| **1. Pane session, top-level** | ✅ **(CC)** `claude agents --json` 0.36 s, no TTY, name/cwd/status — but **per config dir**, 4 disjoint views · ✅ **(ours)** `cc-where` 12 panes. ⚠️ status carries **no age**: pid 43029 read `busy` with `statusUpdatedAt` **50.9 h** old | ◐ **(CC)** `waitingFor` ∈ {permission prompt, input needed, dialog open} — **1 of 11 rows populated**, and `grep -rIl waitingFor bin/ hooks/ scripts/` → **empty**: nothing of ours reads it · ◐ **(ours)** `notify.sh` chime, local only | ✅ **(ours)** `cc-teardown <pane-uuid>` out-of-band, 5-valued verdict token (`:188`) · ◐ **(CC)** `fleet_view_stop_session`, own strings say `kill_unconfirmed` / *"worker may still be running"* | ◐ transcript jsonl; **no unit id in our logs** (§2b) |
| **2. Pane session, fired/nested (`CHILD_SESSION=1`)** | ❌ **not registered at all** — 6 of 16 live sessions, MEASURED (here) · ◐ visible to `cc-where` if it has a kitty pane | ❌ same gate | ✅ **(ours)** `cc-teardown` if it has a pane | ◐ transcript only |
| **3. Named teammate `Agent({name})`** | ❌ **(CC)** `yB()!=null` blocks registration — **0 of 2** live `--agent-id` procs in the registry or in `agents --json` · ◐ **(ours)** `cc-where` shows its pane, but not labelled as a teammate | ◐ **(ours)** mailbox + full hook set (it is a real session) | ◐ **(ours)** `shutdown_request` + `cc-teardown --assignee-of` — **pane-uuid only** · ⚠️ `Qsn` bounds pane teardown at **10 s and fails open**, logging *"its separate `claude --agent-id` process may still be running"* — a stop that reports success over a live 382 MB process. STATIC only; never exercised | ✅ own transcript + `pane-spawns.jsonl` chain |
| **4. Unnamed subagent `Agent()`** | ❌ by-construction — no pid, no pane, no registry row | ✅ **inherited** — it holds the parent's turn, so it cannot silently wait | ◐ **downgraded from ✅**: subagents **auto-background**, so `Esc` sailed past one (heartbeat 10→17→24 lines); `^C` did stop it (froze at 28, child proc 1→0) — but only at **that pane's keyboard**, and work is **not** rolled back | ◐ `subagents/agent-<id>.jsonl` exists; **516 of the last 5,000 `bash-commands.log` rows sit under ONE session uuid** — no agent column |
| **5. Workflow `agent()`** | ❌ **on every one of our 14 tools.** Product-side only: `/workflows` + `/tasks` render in the PARENT pane. Enumerable ONLY by filesystem walk: `find … -name 'wf_*'` → **215 run dirs** MEASURED (here), up from 160 at 13:35Z | ◐ inherited (blocks the parent turn) + a pre-flight dialog *"Run a dynamic workflow?"* that computes `estimatedAgents` | ◐ **`/tasks` → `x` is REAL** — MEASURED by tripwire: a post-stop agent due 4 min later never ran. But **only at that parent's keyboard**; `Esc`, `^C` and `^X^K` all miss it, and `^X^K` renders **no message at all**. ❌ in anything we own | ❌ journal vocabulary is exactly `{started, result}` — **no `error`, no `failed`**. One tested run: **6 started · 5 did work · 3 recorded a result**; `.meta.json` is 48 bytes with no timestamp, no prompt, no parent |
| **6. `--bg` worker** | ✅ **(CC)** `agents --json --all`, `kind:"bg"` + `jobs/<id>/state.json` | ✅ **(CC)** reply → respawn → **queue-to-disk** if dead. ❌ **(ours)** arms `cc-await-ping` on a session with no pane — a wake that can never fire, 3/3 | ◐ **(CC)** `claude stop\|kill\|logs\|attach\|respawn\|rm <id>` — RUN-verified, **absent from `--help`** (`claude --help \| grep -cE '^\s+(stop\|kill\|…)'` → 0); 3/3 measured needed `kill -9`. ❌ **(ours)** `cc-teardown` needs a pane | ✅ **`timeline.jsonl`** append-only `{at,state,detail,text}` — the best AUDIT artifact CC ships, and this box has used it **3 times, 26 days ago** |
| **7. Headless `claude -p`** | ❌ by-accident — has a pid and a sid, deliberately filtered out of `k` (`bin/claude-accounts:499-504`) | ❌ by-construction — no TTY, a permission need is a failure not a question | ❌ `kill <pid>` only, outside every sanctioned rail | ◐ normal transcript |
| **8. Cloud `--cloud`** | ◐ **(ours)** `cc-where` names them and gives a URL; **every row `state=UNKNOWN`** (16–84 rows depending on sample) | ◐ claude.ai push — QUOTED, not verified from this box | ❌ from here. `POST /v1/sessions/$SID/events {"type":"user.interrupt"}` EXISTS but is **API-key-scoped**; ours are subscription-auth | ❌ from here |

### 2a. The one-line reading

Only **two** classes score non-❌ on all four: the top-level pane session and the `--bg` worker — and
`--bg` gets there on a CC artifact we have used three times in a month. **The class this repo's own
capacity answer recommended as the fan-out primitive — the Workflow `agent()` — is ❌ on SEE, ❌ on
STOP-in-anything-we-own, and ❌ on AUDIT.** That is the operator's sentence, restated as a matrix cell.

### 2b. The AUDIT blindness that spans rows 3, 4 and 5

```
$ tail -5000 ~/.claude/logs/bash-commands.log | grep -o '^\[[0-9T:-]*Z\] \[[0-9a-f-]*\]' \
    | sed 's/.*\] \[//;s/\]//' | sort | uniq -c | sort -rn | head -3
 516 f285654f-850c-4ada-96b5-407c5c01ccf0     ← this wave's lead; ~16 agents behind it
 380 020aafc9-88f5-4dc0-ac6c-33c6bd961b0e
  31 161874bb-37f6-4bbd-8c55-9c7d5e3451a6
```
Positive control that the field is absent and not mis-grepped: `grep -c 'agentId' bash-commands.log`
→ 12, and all twelve are commands whose *text* contains the word. **Our own execution log is
session-keyed, and an in-process agent shares its lead's session id.** Same defect at the land:
**75 commits on `origin/main` in 24 h, 75/75 authored "Chris Ren", 74/75 with no agent trailer.**

### 2c. Where the verifier refuted the finder — and which I took

| Claim | Finder | Verifier | **Taken** | Why |
|---|---|---|---|---|
| Unnamed subagent STOP | ✅ safe, `Esc` reaches it | REFUTED by run: subagents auto-background, `Esc` sailed past, only `^C` worked | **Verifier** | Observation beats a static predicate read |
| `waitingFor` is dead (0/12 rows) | capability claim | REFUTED: 1 of 11 populated; the domain is real | **Verifier** | A snapshot is not a capability |
| PreToolUse fires for a workflow agent | UNMEASURED | **CONFIRMED by run**, rows carry `agent_type:"workflow-subagent"` + `agent_id`; deny brakes mid-run and beats `bypassPermissions` | **Verifier** | This is the design's load-bearing measurement |
| A braked run's status | — | **NEW DEFECT**: journal wrote `result:"DONE"`, run completed, 2,093-byte output, zero side effects | **Verifier** | Changes what must ship in the same diff |
| `units = 3.75/h × 4 h ≈ 15` | derived | **REFUTED**: rolling union at W=4 h is median **4**, mean **4.9** (naive predicts 14.6); 15 needs W ≈ **16 h** | **Verifier** | A rate × a window is invalid when the touched sets overlap; the finder's own §2.4 already contradicted it (3 of 14 in tolerance, not 15) |
| "79% unattended" = unsupervised | implied | **REFUTED**: 2-sample CPU delta, **2 of 13** sessions >0.5 cpu-s/5 s; the other 11 at 0.4–2.4% = idle event loop | **Verifier** | Separates the fear (busy-and-unattended) from the noise (idle-and-parked) |
| "99.3% of glass painted, 3 of 3 kitty windows on screen" | MEASURED | **REFUTED, method and fact**: `.optionOnScreenOnly` is a Spaces filter, not z-order; kitty #10502 was **0/37 samples** on screen and it holds the *autonomous drain* session. 79.3% | **Verifier** | The pane that vanished is the unattended one — the polarity matters |
| "Nothing emits a BEL — oversight is 100% pull" | MEASURED | **REFUTED**: `hooks/lead-crash-watchdog.sh:1074` `printf '\a' >/dev/tty`, 3 instances running; 14 files already `display notification`. The null came from BSD `grep -r` over the symlink layer (`grep -rl '' ~/.claude/hooks/` visits **0 of 78** files) | **Verifier** | Makes the remedy *cheaper*: re-point an emitter, do not build one |
| "A running Dynamic Workflow has NO abort path" (landed doc) | — | REFUTED for the harness by two axes, CONFIRMED for our tooling | **Both, split** | True of ours, false of the product — the doc must say which |

Nothing in the finders survived where a verifier ran the path. Two finder cells the verifiers could
**not** reach stay UNPROVEN and are carried as such: the teammate 10 s fail-open (`JEd=1e4`, static
only) and `--bg` stop reliability (inherited from an earlier axis, not re-run).

---

## 3. The numbers that bind the design

Every cell carries the command. Fresh readings are timestamped; earlier ones name their axis.

| # | Quantity | Value | Command / source |
|---|---|---|---|
| N1 | Live claude session procs **(here, 14:12Z)** | **16** (14 pane + 2 `--agent-id`) | `ps -Aww -o pid=,args= > /tmp/f; LC_ALL=C /usr/bin/grep -aE 'claude-220/node_modules/(\.bin/claude\|.*bin/claude\.exe)' /tmp/f \| grep -av cc-close-attrib \| wc -l` — **redirect first**: a `ps \| grep` pipeline undercounted by 35% because argv holds embedded newlines |
| N2 | …CC-native registry rows | **10** ⇒ **6 of 16 (38%) unregistered** | `ls ~/.claude{,-secondary,-tertiary,-quaternary}/sessions/*.json \| wc -l` |
| N3 | The discriminator, **16/16 no exceptions** | `CLAUDE_CODE_CHILD_SESSION=1` on all 6 missing, 0 of 10 present. `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE` set on **0/16** | `ps eww -p <pid> -o command= \| tr ' ' '\n' \| grep -c '^CLAUDE_CODE_CHILD_SESSION='` (O3 §2.2) |
| N4 | Census disagreement at one instant | ps **18** · `cc-where` **12** · CC registry **11** · capacity-alarm **18** | O5 §2.1 — only the memory alarm is complete, and it knows nothing about what a unit is *doing* |
| N5 | Census half-life | population moved **18 → 13 → 16** in 90 min | O2 §2.1, O2-VERIFY 2.9, N1 |
| N6 | Workflow run dirs **(here, 14:12Z)** | **215** — up from **160** at 13:35Z | `find ~/.claude*/projects -type d -name 'wf_*' \| wc -l` |
| N7 | Workflow agents fleet-wide **(here)** | **3,464 started · 3,154 result · 310 never returned**; **5 runs in flight**, one **18.7 h** stale | journal parse over `wf_*/journal.jsonl`. At 13:35Z: 2,716 / 2,433 / **283** / 4 — **+27 unreturned agents in 37 min** |
| N8 | Largest historical run | **229 agents · 7 h 12 m · 39 pp of a weekly meter · 33 never returned** — no pane, no registry row, no live spend meter, journal vocabulary `{started, result}` only | O5 §2.4 |
| N9 | Operator's real reach | rolling union of human-touched sessions: **W=4 h → median 4, mean 4.9** · W=8 h → 8.4 · **W=16 h → ≈15** · W=24 h → 21.3 | O2-VERIFY §4.3, n=182 active hours |
| N10 | Touch rate | **3.65–3.75** distinct sessions / *active* hour (median 3, p90 7, max 17 twice in 173 h), 50–52% duty cycle | O2 §2.3 + O2-VERIFY 4.1 (independently replicated) |
| N11 | Permission-block wait | n≈1,545: p50 **37 s** · p90 **28.3 m** · p95 **2.55 h** · max **22.6 h**; **17.0% >10 min**, **7.8% >1 h** | `~/.claude/autonomy/permission-archive/*.jsonl`. Positive control that the tail is human: p90 by start-hour = **33,909 s at 04:00** vs **294 s at 15:00** |
| N12 | Permission-block rate | **0.428 / session-hour** (781 blocks ÷ 1,825.5 session-hours, 11 d, 4 stores) ⇒ **6.4/h at 15 units, 12.8/h at 30** | O4 §4b |
| N13 | Blocked-unit steady state | mean wait 1,810 s × 0.428/h = **21.5% of all unit wall-time frozen on a human** ⇒ **3.2 blocked at 15, 6.5 at 30** | Little's law over N11+N12 |
| N14 | Ambient chime | **2,383 alerts / 5.32 d = 18.7/h**, peak **235 in one hour**; **71.0% `complete`** (needs nothing), 28.4% permission | `${TMPDIR}/cc-notify/claude-notify.log` |
| N15 | Durable escalations | **1,172 / 1,172 `SEEN=no`**, oldest 19 d; **14,941 unacked mailbox lines** across 309 boxes | `bin/cc-escalations list`; per-box `.acked` cursor |
| N16 | Remote reach | **0** — `hooks/push-critical.sh` wired into 4 `Notification` slots in **all 5** config dirs, `PUSHOVER_TOKEN`/`USER` unset everywhere ⇒ `exit 0`, silently | positive-controlled by RUNNING it: `echo '{…}' \| bash hooks/push-critical.sh` → rc 0, no output |
| N17 | Admission gates a Workflow agent fires | **0 of 9** (`agent-teams-enforce.sh` 8 deny sites + `frontier-spawn-gate.sh`) — 9 agents minted, **0** `agent-tool` ledger rows in a window that took 874 other rows | `grep -n 'permissionDecision.*deny' hooks/agent-teams-enforce.sh` → 119,219,416,428,481,532,571,655 |
| N18 | PreToolUse chain, live **(here)** | `Bash` **9** hooks · `Write\|Edit\|MultiEdit` **3** · `Agent` **2** · `AskUserQuestion` **1** · **NO `*` matcher exists** | `jq '.hooks.PreToolUse' ~/.claude/settings.json` |
| N19 | Cost of one trivial `*` hook **(here)** | **p50 2.85 ms · p90 3.12 ms · max 3.80 ms** per tool call, n=60, fast path (no HALT file) | `/bin/bash` fork + stdin read, timed in python `perf_counter` |
| N20 | Presence beat already on disk **(here)** | **1,832** `~/.claude/cc-beats/<sid>.json` rows, 15 fresher than 60 min, carrying **`who` ∈ {operator: 658, auto: 1,174}** + `operatorT` | `hooks/session-beat.sh` (UserPromptSubmit + Stop). **This is the "was that a human or a fired brief" discriminator O5 could not find.** |
| N21 | True stop latency | `control_request{subtype:"interrupt"}` → `mmr()` killed a workflow in **~1 ms** (`task_updated status:killed`) — filter is exactly `local_agent ∪ local_workflow` | driven over `--input-format stream-json`. **NOT REACHABLE** from a TUI: the Remote Control bridge enumerates **14** subtypes and `interrupt` is absent (a real negative — `set_permission_mode` **is** present) |
| N22 | Landing authority | all 16 sessions run `--permission-mode auto`; `Bash(scripts/ship-land.sh:*)` is on **allow**; `com.claude.deploy-live` makes a landed commit the executing `~/.claude` layer within **~10 min** | `python3 -c "json.load(open('~/.claude/settings.json'))['permissions']"` → 339 allow / 41 deny / 6 ask |

---

## 4. THE DESIGN — a control plane for 30–50 units

**The governing rule, and this repo's standing failure mode:** *do not build a second thing beside a
working one.* `bin/cc-panes` is named in 3 docs and task #145 "completed" and **does not exist in the
tree or the graveyard** (`git log --all --diff-filter=A -- 'bin/cc-panes*'` → empty). The real tool is
`cc-where`. Below, **REUSE** means a thing that runs today; **WIRE** means a thing that exists and is
unregistered; **NEW** means code that must be written.

### 4.1 SEE — how the operator sees 30 units at a glance

**Artifact: `bin/cc-where --fleet`** (extend the existing tool; one command, one screen, ≤30 rows).

| Layer | Status | What it contributes |
|---|---|---|
| Process table, file-based | **REUSE** | The spine. It is the only instrument that was complete (N4: capacity-alarm and `ps` both said 18; every opt-in surface said less). **A census must be derived from a source that cannot omit a unit.** Redirect to a file and read with `LC_ALL=C /usr/bin/grep -a` — the pipeline form undercounts 35% on embedded newlines |
| `claude agents --json` × 4 config dirs | **REUSE** | name · cwd · kind · sessionId · status · `waitingFor`. 0.36 s, no TTY, **zero side effects** (`sessions/` byte-identical before/after). Dedupe on **`(pid, procStart)`**, never filename — `.claude-next/sessions` is a symlink to `.claude/sessions` |
| `sessions/<pid>.json` on disk | **REUSE** | Take the **file's** status, not the view's: `EMm()` collapses `shell` → `busy` (4 of 10 rows misreported). Pin **`TZ=UTC`** on the `procStart` compare — `~/.claude/sessions/1378.json` points at a **postgres walwriter** and a naive `ps -p` says ALIVE |
| `~/.claude/cc-beats/<sid>.json` | **REUSE (N20)** | `who` ∈ {operator, auto} + `operatorT` ⇒ the **"last human touch"** column, already written per turn boundary, O(1), 1,832 rows on disk. This is what makes V1's staleness tolerance measurable instead of asserted |
| `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` | **WIRE** | The gate is `if(yB()!=null\|\|Zkt())return!1`, and `Zkt()` line 1 is `if(Z.CLAUDE_CODE_FORCE_SESSION_PERSISTENCE)return!1`. Set on **0 of 16**. Exporting it from `scripts/handoff-fire.sh` and the `claude*` launchers converts 6 invisible sessions into first-class rows in **Anthropic's own** surface. INFERRED + 16/16 correlation — probe in §8 |
| `wf_*/journal.jsonl` walk | **NEW, small** | The only enumeration of the paneless population (N6/N7). Cheap because it is a `find` over 4 roots; expensive to leave out, because it is 310 unreturned agents |
| `~/.claude/logs/units.jsonl` | **NEW** (§5.3) | One row per in-process unit at its first tool call: `(unit_id, class, parent_sid, agent_type, started_at)`. This is the namespace everything else needs |

**Two rendering rules, each forced by a measurement:**

- 🚨 **Every status renders with its AGE.** `claude agents --json` drops `statusUpdatedAt`, and the
  write is **edge-triggered** (a React `useEffect` on transition), so a wedged-but-alive session
  latches forever: pid 43029 read `busy` with an age of **50.9 hours** and looked identical to a
  healthy one. **A status without an age is not SEE.**
- 🚨 **Sort by "needs a human", not by pid.** At 30 rows the fleet view has no cap and no pager — a
  plain scrolling Ink list, and only the *done* bucket folds (`doneCap = terminalRows − const −
  (1+needs+live)` → squeezed to 0 as live grows). Scanning is O(n) in both surfaces, so the
  **ordering** is the whole product.

**What SEE must NOT try to do:** buy more glass. 79.3% of a 3-display, 9.3 Mpt² desktop is already
kitty; four live panes are 19 rows and one of them rendered **no status line at all**; 30 units on the
same glass is 21 rows each. And a kitty window holding the *autonomous drain* session was **0 of 37
samples on screen** while every existence-based instrument reported it present. **Derive state from a
store; reserve glass for the units that are asking for something.**

### 4.2 INTERRUPT — pulled in only when it matters

**Artifact: `cc-notify --class {now|hour|day|never}` + one ordered queue: `cc-blockers --units`.**

The channel today has no rank anywhere (`grep -n '\-\-priority\|--urgent\|--severity' bin/cc-notify`
→ empty; the mailbox line is flat; the drain is FIFO). The **one** priority field in the whole system
belongs to the one inert channel.

| Move | Status | Detail |
|---|---|---|
| **Rank at the source** | **NEW** | `--class` on `cc-notify`, a class field in the mailbox line, and **budget per class per hour, not per unit** — otherwise volume is a linear function of fan-out and attention is not |
| **Consume `waitingFor`** | **WIRE** | The harness already writes it; `grep -rIl waitingFor bin/ hooks/ scripts/` → **empty**, positive-controlled (5 hits + 47 `"permission prompt"` in the bundle). It is a free, harness-authored *"this unit needs a human right now"* signal |
| **Silence `complete`** | **WIRE** | `hooks/notify.sh:35-53` already suppresses `complete` for background assignees. Widen it: **71% of 2,383 alerts** are "a unit stopped", which is never an action. This one change halves the channel's volume and doubles its meaning |
| **Page on STUCKNESS, not on occurrence** | **NEW, tiny** | The load-bearing arithmetic. Paging every permission block = **12.8/h at 30 units** — unusable. Paging only blocks that have already gone unanswered past a threshold uses the measured tail: **17.0% >10 min → 2.2 pages/h at 30 units; 7.8% >1 h → 1.0 page/h at 30 units.** The emitter already exists and already polls: `com.claude.lead-supervisor` reads `/tmp/cc-permission-pending/` on a timer |
| **Turn the remote channel on — SECOND, not first** | **WIRE + operator credential** | `PUSHOVER_TOKEN`/`PUSHOVER_USER`. ⚠️ **This corrects O5's "cheapest repair on the board" framing: cheapest is not first.** `push-critical.sh` is wired to `permission_prompt`, so exporting the creds today lights **5.3 phone pushes/hour at 15 units** — a pager that trains you to ignore it. Re-point it at the stuck-block class first, then export |
| **Fix the deaf session** | **WIRE** | `migrations/0012-mailbox-wake-arm-stop-rearm.sh` exists in-tree with a 21/21 bats suite and its own `migration-verify` returns **rc 1** against live settings. The watcher is one-shot: a long-lived session is deaf from the moment its birth watcher is spent until a human types |
| **Register the guaranteed reader** | **WIRE** | `hooks/escalation-watch.sh` is on **0 hook events in 5/5 config dirs**; the activation script is already written: `~/.claude/autonomy/pending-activation/33-escalation-watch-activate.sh`. **The 1,172 unseen escalations are unseen because nothing reads them, not because the operator ignored them** |

🚨 **The invariant that three of our five durable paths violate:** *no interrupt path may depend on
the thing it reports on.* `cc-await-ping:525` writes its WAKE-PATH-DOWN notice **into the inbox whose
watcher just died** (467 events / 11 d); the supervisor's `PERMISSION-PENDING` page lands in a box
whose pane died on 2026-07-31; the "guaranteed reader" for the dead-letter stores is itself
unregistered. Each converts a loud failure into a silent one.

### 4.3 STOP — see §5. It gets its own section because it is the operator's stated fear.

### 4.4 AUDIT — what survives

| Move | Status | Detail |
|---|---|---|
| **Unit id in the execution log** | **NEW, one line** | `bash-commands.log` schema is `[ts] [session-uuid] <cmd>`. Add the unit id — the `*` PreToolUse hook (§5.2) already has `agent_id` in its stdin. Without it, every incident is *"one of sixteen agents did this"* |
| **Trailer at the land** | **NEW, one line in `scripts/ship-land.sh`** | 75/75 commits authored "Chris Ren", 74/75 with no trailer, and `deploy-live` makes a landed commit **executing code within ~10 min**. `Unit-Id: <sid>[/<agent_id>]` costs nothing at any scale and is the *only* thing that makes "which unit landed this" answerable |
| **Copy `timeline.jsonl` to every unit** | **NEW, pattern REUSED** | Append-only `{at,state,detail,text}`. It is the strongest artifact CC ships and exists **only** for `--bg` jobs (3 on this box, all 26 days old). Written *by the unit*, never reconstructed afterwards |
| **Absence must be an event** | **NEW** | An ager over `wf_*/journal.jsonl`: `started > result` past a deadline ⇒ a `now`-class exception. Today the vocabulary is `{started, result}` with **no `failed`**, so 310 unreturned agents are not an error count — they are the count of rows that never appeared. One run has been in that state for **18.7 hours** |
| **An index of runs** | **NEW, small** | Reconstructing one workflow agent needs 4 coordinates (account store · project slug · parent sid · `wf_` id) and **there is no index anywhere** — the entry point from *"an agent did something wrong yesterday"* is a 3,409-file grep. Write `~/.claude/logs/wf-runs.jsonl` at spawn |
| 🚨 **A stopped run must not audit as a completed one** | **NEW, same diff as the brake** | Two independent instances: a killed workflow's task output is **0 bytes** while a completed one is 5,262 (`GHs` writes `outputFile`, `GRo`/`oEe` does not); and a fully-braked run wrote **`result:"DONE"`**. Resume compounds it — the cache replays the agent's **answer, not its side effect**: a resumed run returned `{"a":"DONE","b":"DONE"}` in 18 s with the file P1 had written **still deleted** |

---

## 5. THE STOP BUTTON

### 5.1 What exists, exactly

| Lever | Reaches | Reachable by | Verdict |
|---|---|---|---|
| **`/tasks` → `x`** | **every class**: `local_bash`, `local_agent`, `in_process_teammate`, **`local_workflow`**, `monitor_mcp`, `mcp_task`, `remote_agent` — one key, per unit | a human **at that parent's keyboard** | **MEASURED REAL.** Footer verbatim `↑↓ select · x stop workflow · p pause · esc back · s save`; header flipped to `stopped`; **a tripwire agent the script would have run 4 min later never ran** |
| **`/workflows`** | a running Dynamic Workflow | same | QUOTED verbatim from the binary: *"Stop a running workflow at any time with `/workflows`, or disable dynamic workflows in `/config`"* |
| **`Esc`** (`chat:cancel` → `H(true)`) | the in-flight turn **only** — skips the kill branch by construction | any pane | **Misses every background unit**, including auto-backgrounded subagents (measured: heartbeat kept ticking 10→17→24) |
| **`ctrl+c`** (`app:interrupt`) | `local_agent` ∪ `in_process_teammate` — the predicate `Xrl` **excludes `local_workflow`** | any pane | Confirmed by run: workflow timer still advancing at 1m32s |
| **`ctrl+x ctrl+k`** (`chat:killAgents`) | same set as `^C`, with a double-press confirm | any pane | 🚨 **Silently does nothing to a workflow — and rendered NO message at either press.** Zero feedback that the key was a no-op |
| **`claude stop\|kill\|logs\|attach\|respawn\|rm <id>`** | `--bg` jobs | any shell, out-of-band | RUN-verified; **absent from `--help`**; conversation is kept and resumable. But 3/3 measured survived by ~13 min and needed `kill -9` |
| **`bin/cc-teardown <pane-uuid>`** | anything with a pane | any shell, out-of-band, ours | ✅ the sanctioned rail. **Refuses an agent NAME** (`:194`, `reason_kind=target-not-a-pane-uuid`) — correctly, because the address is unverifiable |
| **`TaskStop`** | a teammate or a **named** bg agent | **the model, in-session, ownership-gated** (`Task X is owned by Y; agent Z cannot stop it`) | Gives the *operator* nothing. An unnamed subagent and a Workflow `agent()` have nothing to pass — that is *why* the workflow has no abort path in our hands |
| **`control_request{subtype:"interrupt"}` → `mmr()`** | exactly `local_agent ∪ local_workflow`, **~1 ms** | `--input-format stream-json` / Remote Control | **EXISTS, NOT REACHABLE.** The RC bridge enumerates 14 subtypes and `interrupt` is not one of them; `set_permission_mode` **is** |

**What does not exist anywhere: one command that halts a paneless unit from outside its parent.**
STOP is pane-shaped, so its cost is O(units) in *operator walks* — that, and not memory or load, is
what makes 15 feel like a ceiling.

### 5.2 The smallest buildable thing — `hooks/unit-gate.sh`, one hook, three verbs

**Register ONE new `PreToolUse` entry with `matcher: "*"`, first in the chain.** There is no `*`
matcher today (N18), so this is additive, not a rewrite.

```jsonc
// ~/.claude/settings.json  →  .hooks.PreToolUse  (new entry, placed FIRST)
{ "matcher": "*", "hooks": [ { "type": "command", "command": "~/.claude/hooks/unit-gate.sh" } ] }
```

**Why this hook and not a spawn gate.** MEASURED: `PreToolUse` **does** fire for a Workflow agent's
own tool calls, carrying `agent_type:"workflow-subagent"` and a distinct `agent_id`; a `deny` brakes
it **mid-run** and **beats `--permission-mode bypassPermissions`**, the fleet's most permissive mode.
Meanwhile our `Agent` spawn matcher fires **0 times** for `agent()` (N17). **The kill switch must live
at tool granularity, not spawn granularity.**

⚠️ **Do not use `transcript_path` to identify a workflow agent** — it is the **parent's**. The
discriminating fields are `agent_id` and `agent_type`.

**Contract, in four lines:**

| | Behaviour |
|---|---|
| **Check** | `[ -e ~/.claude/HALT ]` (fleet) · `[ -e ~/.claude/HALT.d/$session_id ]` (one session) · `[ -e ~/.claude/HALT.d/$agent_id ]` (one unit). Miss on all three ⇒ `exit 0` |
| **Deny** | `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"HALT <scope> — set by cc-halt at <ts>"}}` |
| 🚨 **Stamp** | On every deny, append `~/.claude/units/<agent_id>.halted`. **Without this the brake is worse than the runaway:** the measured braked run wrote `result:"DONE"`, completed, and produced a 2,093-byte output with zero side effects. Every SEE surface must render **halted**, never **completed** |
| **Register** | On the **first** tool call carrying an `agent_id`, append one row to `~/.claude/logs/units.jsonl`. This is the namespace §5.3 needs, and it costs one `[ -e ]` + one `touch` |

**Cost, MEASURED here (N19): p50 2.85 ms · p90 3.12 ms · max 3.80 ms per tool call** (n=60, `/bin/bash`
fast path, no HALT file). Read against N18: on `Bash` this is a 10th hook on an already-9-deep chain
(+11%); on `Read`/`Grep`/`WebFetch`/`Task`/`Workflow` it is a new ~3 ms fork where there was none.

**The cure must not be blocked by the flag.** `cc-halt clear` and the hook itself must be exempt, or
the guard refuses its own remedy — this repo has shipped that defect twice
(`guard-refusal-fires-on-its-own-harness`, `denylist-enumerates-spellings-not-the-class`). Exempt by
`session_id` env stamp, not by matching the command text.

🚨 **Call it a BRAKE, not a STOP, in every doc and every message.** A denied tool call does not abort
the agent: it keeps its turn, keeps thinking, keeps spending. It removes the blast radius, not the
spend. It converts runaway *action* into runaway *talk*.

### 5.3 The namespace — the thing that is actually missing

Every empty STOP cell traces to one absence: **an id the operator can type.** `cc-teardown` is not too
weak; it is correctly refusing an address it cannot verify (`:194`). Once `units.jsonl` exists:

- `cc-halt <unit-id>` brakes one agent · `cc-halt <sid>` one session · `cc-halt --fleet` everything.
- `cc-teardown` can accept a unit id, because there is now a store that says what it is and who owns it.
- `cc-where --fleet` can render the paneless classes as rows instead of omitting them.
- `bash-commands.log` and the commit trailer get a real actor.

### 5.4 Re-site the nine gates onto the verb that is actually used

A Workflow agent fires **0 of 9** admission gates (N17), each of which encodes a separate incident: a
duplicate worker, a kernel panic, a 91-session cascade, a wave stall, a silent model demotion, five
stranded reports. **Changing the orchestration verb from `Agent({name})` to `agent()` discards all
nine at once, with no ledger row anywhere.**

The chokepoint is measured and it is one matcher edit: with a HALT flag pre-set, a run ended in 6.9 s
with `permission_denials:[{"tool_name":"Workflow"}]` and **the workflow was never created.** So
**add `Workflow` to the `agent-teams-enforce.sh` PreToolUse matcher** (today `Agent` only) and G1/G2/G3/G4/G9
fire at workflow creation, with the pre-flight dialog's own `estimatedAgents` as the capacity term.

### 5.5 The true stop is a launch-flag decision, not a subsystem

`control_request{subtype:"interrupt"}` → `mmr()` already does exactly what a fleet kill switch should
do: **~1 ms**, filter `local_agent ∪ local_workflow`. It is unreachable **only** because our sessions
are TUIs. Making it reachable is a decision about how `scripts/handoff-fire.sh` launches a session
(`--input-format stream-json` / Remote Control), not a new mechanism. Until that decision is made,
`cc-halt --keys` can only drive `/tasks`+`x` by keystroke into each parent — an O(units) *simulation*
of oversight, and it must be labelled as one.

**And fix the one false-success we own:** teammate stop bounds pane teardown at 10 s and **fails
open**, logging *"its separate `claude --agent-id` process may still be running"*. A stop must return
a verdict — killed / refused / unreachable — never a silent success. `cc-teardown` already proves the
shape with its 5-valued token (`:188`); the teammate path does not use it.

---

## 6. THE HONEST TRADE

Two regimes, defined so the operator can choose between them rather than discover the difference.

- **GLANCE-OVERSEEN** — the operator's knowledge of a unit comes from having **looked at it**.
  Cost: one pane-walk per unit per revisit interval.
- **EXCEPTION-OVERSEEN** — the operator's knowledge comes from a **store**; he is pulled in per
  ranked exception, can stop any unit from one place, and can reconstruct any unit afterwards.
  Cost: one decision per exception, and ~zero attention when nothing is wrong.

| Tier | SEE | INTERRUPT | STOP | AUDIT | Units it supports | What you give up | Basis |
|---|---|---|---|---|---|---|---|
| **T0 — today** | walk the pane; 3 instruments, 3 totals | ambient chime 18.7/h, 71% noise, **0 remote** | pane-addressed, O(units) walks | transcript, no unit id | **glance ceiling 4–5** at a 4 h tolerance; ≈15 at a 16 h tolerance. **310 unreturned workflow agents are already outside it** | — | N4, N9, N7, N14 |
| **T1 — census + brake** (~1 diff each) | `cc-where --fleet`: one command, all classes, **age beside every status**, last-human-touch column | unchanged | **one keystroke brakes every in-process class**, fleet/session/unit scoped; panes still `cc-teardown` | + unit id in `bash-commands.log`, + HALTED stamp | **~30, exception-overseen** | The brake **starves, it does not abort** — spend continues. A braked run must render *halted* or it launders green | N19, N20, O1-VERIFY F6a |
| **T2 — ranked queue + absence-as-event** | as T1 | **silent by default**; one ordered queue; pages on **stuckness** (1.0/h at 30 units), not occurrence (12.8/h) | as T1 + typeable namespace, `cc-teardown <unit-id>` | + `wf-runs.jsonl` index, + `timeline.jsonl` per unit, + `Unit-Id:` commit trailer | **30–50, exception-overseen** | 🚨 **You stop glancing.** A unit may run **16 h** with no human look. Safe only because STOP and AUDIT hold **without** SEE | N11, N12, O6 §5 |
| **T3 — true stop** | as T2 | as T2 | **`control_request{interrupt}` ~1 ms, from one place, every paneless class** | as T2 | 50+ | Every fired session changes launch shape (`--input-format stream-json`); the TUI is no longer the only surface | N21 |

**What 30 FULLY (glance) overseen units would cost, and why it is not achievable.** 79.3% of a
three-display desktop is already spent; 30 units on the same glass is **21 rows each**, and panes at
19 rows already fail to render their own status line. The operator's own measured 4-hour union is
**4–5 sessions**, and raising the *touch rate* buys little because the touch rate is
**revisit-dominated** (the naive product predicts 14.6 where the measurement is 4.9 — a 3× overlap
collapse). **The only term with headroom is the staleness tolerance, and raising it means making a
16-hour-stale unit safe — which is STOP and AUDIT, not SEE.**

**The arithmetic that makes 30 exception-overseen units feasible.** At 0.428 permission blocks per
session-hour, paging on every block is 12.8/h at 30 units — a full-time job. Paging only on blocks
that have already gone unanswered uses the measured tail: **17.0% exceed 10 min → 2.2/h; 7.8% exceed
1 h → 1.0/h.** One page an hour, each one a unit that is genuinely stuck, is an oversight budget a
person can hold. **Every unit added must raise the selectivity of the page in the same diff, or you
have traded SEE for INTERRUPT and called it progress.**

**The admission rule that keeps the trade honest** — a unit class may carry overseen work iff it has:

| | Requirement | Failing today |
|---|---|---|
| **S** | appears in ONE census, with live state + age, without opening its window | unnamed subagent · workflow agent · headless · cloud (`state=UNKNOWN`) |
| **T** | a name in a namespace the operator can **type**, and one command that stops that one unit | unnamed subagent · workflow agent · `--bg` (ours) · headless |
| **A** | every action carries **its own** id in our logs, not its parent's | unnamed subagent · workflow agent |
| **I** | *(inheritable)* surfaces its own `waitingFor`, **or** blocks a parent that is itself overseen | `--bg` (arms a pane-addressed wake with no pane, 3/3) · headless |

**Corollary the operator should hold us to:** *no unit class may be the recommended fan-out primitive
while it fires zero admission gates.* Today that disqualifies the Workflow `agent()` — until §5.4
lands.

---

## 7. WHAT TO DO FIRST

**Ship `hooks/unit-gate.sh` as a `PreToolUse matcher:"*"` hook — the brake, the HALTED stamp, and the
unit-ledger row, in one diff.**

```
▶ The registration, verbatim:

`~/.claude/settings.json → .hooks.PreToolUse, new FIRST entry: {"matcher":"*","hooks":[{"type":"command","command":"~/.claude/hooks/unit-gate.sh"}]}`
```

**Why it is first, and not the census or the credential.**

1. **It is the only chokepoint every in-process class traverses**, and it is MEASURED — the deny fires
   for a Workflow agent mid-run and beats `bypassPermissions`. There is no `*` matcher today (N18), so
   nothing is being replaced.
2. **It mints the namespace in the same pass.** Every other verb is downstream of an address: STOP
   cannot name a unit, AUDIT cannot attribute an action, INTERRUPT cannot rank one unit against
   another. `cc-teardown:194` is refusing an address that does not exist yet — this hook creates it.
3. **It directly answers the fear.** After this diff, one file (`~/.claude/HALT`) stops every
   in-process unit on the box from taking another action, including the class with the largest
   measured blast radius (229 agents / 7 h 12 m / 39 pp).
4. **It is cheap and the cost is known**: 2.85 ms p50 per tool call, +11% on the Bash chain.
5. **The stamp must be in the same diff, not the next one.** A brake without it produces a run that
   reports `result:"DONE"` over zero work — a *silent* runaway, strictly worse than the loud one.

**Then, in order:** (2) `CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` in the launchers — one line, after
the §8 probe, makes 6 of 16 sessions first-class in Anthropic's own view · (3) `cc-where --fleet`
over the union · (4) silence `complete` in `notify.sh` · (5) apply `migrations/0012` and register
`escalation-watch.sh` (both already written and tested) · (6) the stuck-block pager, **then** the
Pushover credential.

---

## 8. RISKS + OPEN QUESTIONS, each with the probe that settles it

| # | Risk / question | Why it matters | Probe |
|---|---|---|---|
| R1 | **The brake laundering into a green result** — MEASURED once, on one workflow | Every status-keyed surface is blind to a fully-braked run | Re-run `brake.workflow.mjs` (fixture preserved in the O1-VERIFY scratchpad) with HALT set from t=0; count `hooks-deny.jsonl` rows and read `total_cost_usd` — also settles whether a braked agent's **spend** is bounded |
| R2 | **`CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1` is INFERRED, not RUN** (branch read + 16/16 correlation) | It is step 2 of §7 and the entry fee for adopting CC's store | `CLAUDE_CONFIG_DIR=<copy> CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1 script -q /dev/null claude` in a throwaway pane → `ls <copy>/sessions`. **Positive control: the same launch without the FORCE var must produce no file** |
| R3 | **Teammate stop fails open at 10 s** (`JEd=1e4`) — STATIC only, and it is the class we run most | A stop that reports success over a live 382 MB process is a false negative in the STOP column | Throwaway kitty window: spawn one `Agent({name})`, `/tasks`→`x`, then `ps \| grep -c '[-]-agent-id'` **before, immediately after, and at T+30 s** |
| R4 | **`--bg` stop reliability** — 3/3 needed `kill -9`, inherited and never re-tested; zero bg workers were alive in any axis window | T1 lists `--bg` as safe-with-caveat; if `claude stop` is unreliable the caveat is the finding | `claude --bg -p '<long task>'` in a scratch repo → `claude agents --json --all` → `claude stop <id>` → poll `ps` for 15 min |
| R5 | **The fleet view at 30–50 rows has never been seen** | T2 assumes the native surface is usable at that scale; the fold logic is code-truth, not a screenshot | Open the view at ≥30 registered sessions at a known `LINES`; screenshot; compare against `doneFoldHidden` telemetry |
| R6 | **NotificationCenter behaviour at 30 units** — coalescing, drops, Focus/DND | The chime numbers are **emissions, not receipts**; perceived volume is unmeasured and strictly smaller | Fire 100 notifications over 10 min from a throwaway session and count banners that survive; repeat with Focus on |
| R7 | **Why CC's registry misses 6 of 16 beyond `CHILD_SESSION`** — 3 are `expect`-driven, 3 plain; no second discriminator found | If R2's fix does not cover all six, the census still has a hole | `fs_usage -w -f filesys \| grep 'sessions/'` across one cold start of each launch shape |
| R8 | **`waitingFor` under a real prompt** — the value domain is read from the binary; only 1 of 11 rows was ever observed populated | §4.2's free ranking substrate depends on it being reliably written | Park a session on a permission prompt in a copied config dir and read its `sessions/<pid>.json` |
| R9 | **Whether `/workflows` is session-scoped or global** | Decides whether the operator has *one* workflow stop or one per pane | Operator runs `/workflows` in a pane holding no workflow while another pane has one running |
| R10 | **A `*` PreToolUse hook's real fleet cost** — 2.85 ms is a microbenchmark, not a session under load | 10 concurrent sessions × N tool calls; if the cost is superlinear the brake taxes the thing it protects | Run the fleet's own `bash-commands.log` rate against a hook-count A/B; count **execs on the executed path**, never `$(` |
| R11 | **The census's own shelf life is under an hour** (18 → 13 → 16 in 90 min) | Any number in this doc that has a live population as its denominator decays fast | Re-derive with the §3 commands rather than quoting; publish coverage beside every figure |
| R12 | **2.1.232 makes it worse by default** — QUOTED: *"non-teammate agent spawns in interactive sessions now run in the background by default"* + *"Removed the 200-subagent-per-session spawn cap"* | The paneless, unregistered, ungated population grows **without anyone asking for it**. A plane that only enumerates panes is obsolete at the version after ours | Install 2.1.235 into a throwaway prefix; `ToolSearch` for `ListAgents`; check whether `messagingSocketPath` is populated (it would light CC's own shipped peer-control transport, today dark because `VAs(){return}` is a stub) |

**One hygiene rule this wave earned the hard way.** A tripwire watcher in O1-VERIFY printed
*"TRIPWIRE FIRED — the stop was COSMETIC"* because it could not distinguish *the stopped run
continuing* from *the verifier resuming it*. **A control that cannot separate the two hypotheses it is
deciding between will convict the innocent one.** Every alarm in §4.2 must carry that discriminator,
or it will page the operator about a unit behaving exactly as instructed.

---

## 9. What this document does NOT claim

- **That 30 fully (glance) overseen units are achievable.** They are not, on this glass and this
  operator's measured union. §6 offers 30–50 *exception*-overseen units and states the price.
- **That the brake is a stop.** It is a starve. The true stop (§5.5) is a launch-flag decision that
  has not been made.
- **That any live-population number here survives the hour** (R11).
- **That the paneless classes are safe to fan out today.** They fire 0 of 9 gates, have no address,
  and 310 of their agents fleet-wide started and never recorded a result — **27 of them in the 37
  minutes this wave spent measuring them.**
