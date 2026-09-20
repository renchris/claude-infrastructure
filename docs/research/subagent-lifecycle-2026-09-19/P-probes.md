# P — the two controlled probes (W5), 2026-09-19

Wave W5 of `docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md`. **This wave measures; it does not fix.**
No fleet code was changed. The scratch project is `tests/fixtures/teammate-probe/` and every agent
in this report was created by this wave inside it.

Runtime: **Claude Code 2.1.260** (`~/.claude-260/node_modules/.bin/claude --version` →
`2.1.260 (Claude Code)`, captured per run). Terminal: kitty, with `teammateMode: "iterm2"` routed
through the `~/.claude/bin/it2` → `kitty @` shim. Waves **W1 (3cdaa2552)**, **W2 (c9e70fcca)** and
**W4 (46ccdf23c)** are landed and live, so the transport and closer these probes run against are the
**fixed** versions, not the pre-W1 ones.

---

## 0. The instrument, and why it took three tries to make it honest

Both probes count "surviving members". Every census in this report is a **set difference** against a
pre-launch snapshot, plus a conjunction that anchors on **`argv[0]`**. That shape is not fastidiousness;
a naive census was wrong three separate times on this box, and each failure is a live instance of a
lesson already on file:

| attempt | what it did | measured result | the lesson it re-proved |
|---|---|---|---|
| 1 | `ps … \| grep -- '--agent-id'` | **5 rows, all 5 false** — one was the census's own shell, four were full SESSIONS whose argv carries a brief that merely *mentions* the flag (this wave's own brief does) | memory `pgrep-f-matches-agent-briefs`; `docs/lessons/census-matches-itself.md` |
| 2 | `CC_PROBE_PAT='--agent-id' ps … \| awk 'index($0,ENVIRON["CC_PROBE_PAT"])'` | **1302 rows** — the whole process table | `docs/lessons/empty-selector-is-a-universal-selector.md`: `VAR=x cmd` binds to **ps**, not to awk, so awk read it empty and `index($0,"")` is 1 for every line |
| 3 | same, with the assignment moved onto `awk` | **1–2 rows, still false** — the pattern literals are in *awk's own argv* | `census-matches-itself.md` again: the matcher must not be expressible on any command line |
| **final** | `$2 ~ /claude\.exe$/` **and** all three membership flags, patterns in the **environment**, matcher read from a **file** | **0 false positives** | — |

The final form carries **both arms**, and both are re-runnable:

```
./run-p1.sh --census                                   # control A: must print 0 when no member of ours is live
awk '$2 ~ /claude\.exe$/ && …' captures/p2/agents.spawned   # control B: must still find the real member, pid 73991
```

Control A printed `count=0`; control B returned pid 73991. **An instrument that can only ever say
"no" is not a verification** — B is the arm that proves this one can still say yes.

---

## 1. PROBE P2 — the R2 control (K, RC-11). Outcome **(c): a clean exit.**

### Setup
One named teammate, `probeR2`, spawned by **this session as the lead** — deliberately, because the
control's whole content is that the `shutdown_request` be *structurally* exact, and a model-driven
lead might send prose instead (a prose "please shut down" does nothing on this runtime; §2.2).

The fleet closer (`hooks/teammate-auto-shutdown.sh`) was neutralised with its **own documented
cooperative marker** — `.teammate-busy` in the member's cwd (`teammate-auto-shutdown.sh:929`), which
defers it unconditionally. No fleet code was touched and no kill switch was flipped in any config.
The marker was removed afterwards. Without this the probe would have measured the *fleet actuator*
reaping the member and learned nothing about the vendor.

**A forced deviation, stated rather than hidden:** the brief asked that probes run in the scratch
project only. A named spawn **cannot** take `cwd` — passing it silently demotes the spawn to an
in-process subagent with no pane and no member (RC-11, §2.2). So `probeR2`'s cwd is structurally the
lead's worktree; the fixture confines its *work* (the only file it touched), not its cwd.

### Precondition, and the command that proves it held
`captures/p2/precondition.txt`, taken at `2026-09-19T21:01:29Z`, immediately before the send:

```
-- member process, three-flag conjunction --
73991 …/claude.exe --agent-id probeR2@session-d8eee83b --agent-name probeR2 --team-name session-d8eee83b …
-- member transcript last assistant turn (idle assertion) --
Idle now, taking no further turns
-- transcript byte size stable across 15s (quiesced) --
666707
```

Three independent legs: the process is alive under the full conjunction; the member's own last
assistant turn asserts idleness; and its transcript stopped growing across a 15 s window. Its pane
(kitty window **161**, pinned by set difference against a 15-window pre-spawn snapshot) showed a bare
composer — `captures/p2/pane-T0.txt`.

### Delivery, proven from the member and not from the send
`SendMessage` returned `{"success":true,…,"request_id":"shutdown-1789851695026@probeR2"}`. **That
return is not the oracle** — 2.1.224 fixed SendMessage falsely reporting delivery, so the proof is
the member's own transcript, which carries the request as a `<teammate-message>` user record:

```
=== user 2026-09-19T21:01:35.468Z role= user
<teammate-message teammate_id="team-lead">
{"type":"shutdown_request","requestId":"shutdown-1789851695026@probeR2","from":"team-lead",
 "reason":"P2 control (RC-11 / K R2): probe complete, shutting the team down.",
 "timestamp":"2026-09-19T21:01:35.026Z"}
…To approve it, call SendMessage with exactly this input… Approving ends your process; a plain-text
acknowledgment does not shut you down.…
</teammate-message>
```

Sent `21:01:35.026Z`, landed in the member `21:01:35.468Z` — **442 ms**. (§2.1's live specimen
measured ≈70 s for the same hop. Same runtime, same transport, two orders of magnitude apart; the
inbox latency in §2.1 is therefore not a fixed property of the poller.)

### The two captures

| t | capture | kitty window 161 | pid 73991 |
|---|---|---|---|
| **+10 s** (`21:01:45Z`) | `captures/p2/pane-T10.txt` | `Error: No matching windows for expression: id:161` (`kitten @ get-text` rc=1) | **gone** |
| **+60 s** (`21:02:37Z`) | `captures/p2/pane-T60.txt` | same, and `kitty @ ls` confirms 161 absent, total back to the pre-spawn 15 | **gone** |

The member row is also gone from the team file: `~/.claude-secondary/teams/session-d8eee83b/config.json`
lists `member names: ['team-lead']`.

### What the transcript tail shows, and why it matters
`captures/p2/transcript-tail.txt`: after the `<teammate-message>` record at `21:01:35.468Z` there is
**no assistant turn at all** — the next records are `last-prompt` / `bridge-session` / `cost-state`
end-of-session rows. The idle teammate was terminated by the **runtime**, without a model turn. That
is byte-for-byte the shape §2.1 recorded on the operator's own screenshot, reproduced on demand.

### Verdict — P2
**Outcome (c): a clean exit** — an idle named teammate on 2.1.260 consumed a structured
`shutdown_request` and was gone (pane, process and member row) inside 10 s, with no modal on screen
at +10 s or +60 s; so the 2026-08-26 "idle 0/4" episode was **environment, not vendor**, and the arm
that did **not** run is the modal arm — no permission dialog ever appeared, because this member was
briefed to use only `Read` and `SendMessage`, so outcome (a) was never put to the test and this probe
cannot speak to a teammate blocked behind one.

**What in the environment differs** — the three candidates this probe can name, in order of how much
of the 0/4 each could carry:
1. **The fleet closer was racing the lead.** In the 0/4 configuration `teammate-auto-shutdown.sh` was
   live and reaps on its own schedule (deferring on a dirty tree up to 3×). This probe deferred it
   deliberately. A member the closer is mid-defer on is not a clean reading of the vendor path.
2. **A blocking settings `Stop` hook returns before the `TeammateIdle` block** (§2.2), so a member
   whose Stop pass is blocked emits **no idle notification at all** — it looks like "ignored the
   request" and is in fact "never went idle". W1 (`3cdaa2552`) fixed this class; the 0/4 predates it.
3. **The 0/4 figure never captured the teammate's screen** (K, R2). It is one 2.1.2xx measurement
   with no pane capture, so it cannot distinguish any of these from a modal.

This is the reproduction the plan wanted **in the negative**: on 2.1.260, with the fleet actuator
held off, the vendor path is not broken. **Nothing here supports filing issue #81807's shape
upstream**, and W5 files nothing.

### A side finding, recorded because it cost the probe its report channel
`probeR2` was briefed to `SendMessage` its result to `"W5-probes-lead"` — a name this session invented.
The send was **refused**, and the refusal read:

> "No agent named 'W5-probes-lead' is reachable. Your session list was too long to check completely,
> so a session by that name may exist beyond what was searched."

The correct address for a member replying to its lead is **`team-lead`** (the name the runtime itself
uses in the `<teammate-message>` envelope above). Two things follow. First, a teammate brief must name
`team-lead`, not an invented label, or the member's findings go nowhere — which is the measured
`0/207` named-spawn delivery failure in `skills/agent-teams/SKILL.md:87` seen from the member's side.
Second, **that refusal is ambiguous by construction**: it reports a lookup miss over a truncated list,
which is not absence (memory `lookup-miss-is-not-absence`). The member said so itself before idling.

---

## 2. PROBE P1 — RC-10, the lead-exit cleanup budget

### What it measures
`cleanupSessionTeams` closes every member pane inside a **2 000 ms** race (`Qge=2000`, D §4), each
close a separate CLI round trip through the it2 shim, result discarded. Whether that completes for
N > 2 panes is undecidable from strings — hence a probe. A lead spawns **4** named teammates, waits
for all four idle notifications, then exits gracefully; survivors are counted at **+30 s**.

**Verdict rule, fixed before the first run:** survivors == 0 on both graceful exits ⇒ the vendor's
cleanup is sufficient and **no fleet-side SessionEnd close is licensed**. survivors > 0 ⇒ the probe
FAILED, and only then is a fleet-side change licensed — scoped to this fixture, with this probe as
its control, and only after messaging the lead.

### Why a busy box cannot be allowed to answer this
The budget is **wall-clock**, so a loaded box makes the vendor miss it for reasons that have nothing
to do with the vendor — and "survivors > 0" is precisely the direction that licenses a fleet-side
change. The asymmetry is the whole point and it cuts one way only:

* **survivors == 0 under load** is *stronger* than the same result on a quiet box — the cleanup
  completed despite adverse conditions.
* **survivors > 0 under load** licenses **nothing**, and must be re-run on a quiet box with both
  readings printed side by side.

`run-p1.sh` therefore records `uptime` and `top -l 2 -n 0 | grep '^CPU usage'` immediately **before**
and **after** every run (`captures/p1-<run>/box-before.txt`, `box-after.txt`), and refuses to start
until the box is quiet.

### Attempt 1 — INVALID, and it is recorded because each defect is a finding

The first attempt of run 1 produced `survivor_windows=1 survivor_procs=0` at
`2026-09-19T21:07:57Z`. **That number is not a P1 result and is not reported as one**: the run never
reached its own precondition (`idle_observed=0/4`, `spawned_procs=0` — nothing was ever spawned). It
is discarded. It exposed four defects, three in the instrument and two in the environment:

1. **The idle oracle matched its own instruction text.** The completion marker `P1-ALL-FOUR-IDLE` is
   *in the lead's brief*, so the pane displays it the moment the prompt is echoed. The runner tested
   for `>= 1` occurrence and fired `/exit` **10 seconds in**, before any teammate existed. The lead
   printing it is the *second* occurrence; the test is now `>= 2` **and** `>= 4` live members.
2. **`send-text` with a bare LF does not submit the composer** — it inserts a newline. `/exit` sat
   unsent in the lead's composer for minutes. Only a **carriage return** submits.
3. **A kitty-launched `/bin/bash` never reads `.zshrc`, so the lead could not create a teammate at
   all.** The lead's own words: *"teammateMode is set to `iterm2` but this session is not running
   inside iTerm2 … this session cannot create a named teammate at all."* Claude Code gates its iTerm2
   pane backend on `ITERM_SESSION_ID` and `~/.zshrc:678-696` synthesises it as
   `w0t0p0:$KITTY_WINDOW_ID` for exactly this reason; a non-interactive shell never runs that block.
   The wrapper now reproduces the fleet's own synthesis verbatim. **This is not a `teammateMode`
   change** — that is forbidden for this wave, and nothing here alters it.
4. **The fleet's admission gate refused 3 of 3 spawns.** `hooks/agent-teams-enforce.sh` →
   `cc_capacity_admit`: *"8 sessions mid-turn + 1 > active ceiling 8"*. The refusal is bounded — it
   releases itself after `CC_ADMIT_BUDGET` consecutive refusals — and its own remedy is *"let the
   running turns finish… shed first, then spawn"*.

Defect 4 and the load addendum want the same thing, so the runner now has **one preflight for both**:
`cc_sp_active <= 3` (a lead plus four members must stay under the ceiling of 8) **and** CPU idle
`>= 40%`. It exits 3 rather than running on a box that cannot answer the question.

**`CC_ADMIT_GATE=off` was available and was not used.** Overriding a protective gate in order to
measure a race would buy a measurement of the box in exactly the state the gate exists to prevent.

### Attempt 1's environmental findings are themselves results

Two of the four defects above are facts about **this fleet**, not about the probe, and both belong in
the register even though W5 changes nothing:

* **A session that is not `ITERM_SESSION_ID`-tagged cannot create a named teammate at all** under
  `teammateMode: "iterm2"`, and the failure is a clear refusal, not a silent demotion. It is
  therefore a *different* failure mode from RC-11's `isolation`/`cwd` demotion, which is silent. Any
  fleet automation that launches a Claude session from a non-interactive shell inside kitty — cron, a
  `launchd` job, a wrapper that does not source `.zshrc` — gets a lead that cannot spawn teammates.
  Proven in both directions by `captures/env-control/RESULT.txt`: unset before, `w0t0p0:171` after.
* **The admission gate is reached by teammate spawns and is load-bound**, so a 4-member wave is not
  schedulable on a box already at its ceiling. The plan anticipated this (*"the capacity gate refuses
  once and then admits, so the next attempt is effectively unguarded and the moment has to be chosen
  by hand"*), and this wave chose to **wait** rather than spend the release.

### The fallback bar, declared BEFORE the runs, so it cannot be a post-hoc rationalisation

The preflight above (`cc_sp_active <= 3`, idle `>= 40%`) may not be reachable while the sibling waves
W1/W2/W3 are still running — readings during this wave ranged `cc_sp_active` 7→11 and idle 0.86%→37.8%.
If it is not met inside the wait budget, this wave relaxes to `cc_sp_active <= 4` and idle `>= 25%`
and runs anyway, **because the addendum's rule is asymmetric and applies at interpretation time, not
at run time**:

* a **survivors == 0** result stands at any load, and stands *more* strongly the busier the box was;
* a **survivors > 0** result at any load below the 40% bar licenses **nothing**, and is re-run on a
  quiet box with both readings printed side by side before any fleet-side change is even discussed.

Every run below prints its own `uptime` and CPU idle immediately before and after, and the box state
is stated **in the verdict sentence itself**.

### The preflight bar was WRONG, and it cost 78 minutes — the measurement that proves it

The first preflight demanded `cc_sp_active <= 3` (later 4), reasoned as *"a lead plus four members
must stay under the ceiling of 8"*. **That is not the gate's condition.** `cc_capacity_admit` refuses
when `active + 1 > 8` — the refusal text says so in its own words, *"8 sessions mid-turn + 1 > active
ceiling 8"* — so it **admits at `active <= 7`**, and it counts sessions **mid-turn**, which probe
members stop being seconds after they spawn.

78 one-minute samples, 22:30Z–23:49Z (`captures/preflight-census/`):

| condition | met | |
|---|---|---|
| `active <= 3` | **0/78 (0.0%)** | the probe's first bar |
| `active <= 4` | **0/78 (0.0%)** | the probe's fallback bar |
| `active <= 6` | 35/78 (44.9%) | the corrected bar |
| **`active <= 7`** | **64/78 (82.1%)** | **the gate's own condition** |
| `idle >= 25%` | 34/78 (43.6%) | |
| `active <= 4` **and** `idle >= 25%` | **0/78 (0.0%)** | the conjunction that blocked everything |
| `active <= 6` **and** `idle >= 25%` | 15/78 (19.2%) | reachable within minutes |

`cc_sp_active` ranged 5–10, median 7. **The admission gate was never the blocker.** The probe's own
preflight was, and it was *stricter than the gate it existed to satisfy* — so a bar written to respect
a protective mechanism instead blocked the work for 78 minutes while the mechanism itself would have
admitted 82% of the time. This is `docs/lessons/the-blocking-gate-was-stricter-than-the-repo-s-own-verifier.md`
in a new place: **when two gates judge one population, adopt the standard of the one that actually
adjudicates, and read its refusal text for the predicate rather than deriving your own.**

The corrected bar is `active <= 6` — one slot of margin below the gate's 7, because the spawn burst
briefly makes the four members mid-turn themselves — with `idle >= 25%` retained for interpretation.

### The finding that decided P1: a lead with live teammates CANNOT exit unattended

Both runs reached their precondition cleanly — `idle notifications observed = 4/4` on each, with the
lead printing its marker only after four members were live (`captures/p1-run1/run.log`,
`captures/p1-run2/run.log`). Then `/exit` was typed into the lead's own composer, and **the lead did
not exit.** It raised a confirmation modal:

```
  Background work is running
  The following will stop when you exit:

  subagent · You are a probe teammate. Do exactly one thing an…   (× 4)

  ❯ 1. Exit and stop tasks
    2. Move to background and exit
    3. Stay

  Enter to confirm · Esc to cancel
```

**`cleanupSessionTeams` sits behind an interactive confirmation whenever members are alive.** The
first measurement at +30 s therefore read `survivor_windows=5, survivor_procs=4` — five windows for a
lead plus four members, *including the lead's own window*, which is the tell: the lead was still
there, so the cleanup path had never been entered. That number is **not** a P1 result and is not
reported as one. It measures the probe's exit mechanism, not the vendor's cleanup.

Two consequences beyond this probe, and the first is the one the register should carry:

1. **An unattended lead exit never reaches the vendor's cleanup at all.** Any automation that ends a
   lead non-interactively — a `-p` run, a cron job, a script sending `/exit` — leaves the modal
   unanswered, and both the lead and its members stay alive indefinitely. This is the *lead-side*
   twin of the member-side lesson already on file
   (`docs/lessons/a-subagent-cannot-answer-a-permission-prompt-so-a-prompt-trigger.md`): the member
   cannot answer a prompt, and neither can an unattended lead.
2. **It is why run 2's census read 8 members for a 4-member probe.** Run 1's four survived into run 2's
   window, so `spawned_procs=8` counted run 1's residue. The set-difference census was correct about
   what was on the box; the *runs* were not independent. Each run's survivors are therefore scoped by
   **team id** below, never by the raw count.

### P1 result — both runs, after a genuine graceful exit

The modal was answered with **option 1, "Exit and stop tasks"** (the pre-selected default, which is
what a human pressing Enter gets), on each lead's own pane. Survivors were then counted at +30 s,
scoped by team id so the two runs cannot contaminate each other.

| | run 1 | run 2 |
|---|---|---|
| team | `session-38a2d14c` | `session-d9605166` |
| idle notifications observed | **4/4** | **4/4** |
| windows at spawn | 5 (202–206) | 5 (207–211) |
| **survivor windows at +30 s** | **0** | **0** |
| **survivor member processes at +30 s** | **0** | **0** |
| box before (load / CPU idle) | 64.08 / **0.94%** | 115.19 / **0.0%** |
| box after (load / CPU idle) | 109.21 / **1.58%** | 132.70 / **0.8%** |
| capture | `captures/p1-run1-exitmodal/` | `captures/p1-run2-exitmodal/` |

Fleet-wide check immediately afterwards: `./run-p1.sh --census` → `count=0`. No member of either team
survived anywhere on the box.

### Verdict — P1

**PASS: survivors == 0 on both graceful lead exits — 0 windows and 0 member processes at +30 s for
each of two teams — and the box was at 0.0–1.6% CPU idle with load 64→133 across both runs, which
makes this the strong direction of the addendum's asymmetry rather than the weak one (the vendor
closed five windows and four member processes inside its 2 000 ms race on a box with essentially no
idle CPU); so the vendor's cleanup is sufficient and NO fleet-side SessionEnd close is licensed —
and the arm that did NOT run is exit option 2, "Move to background and exit", which is a different
code path that may well leave members alive and was never exercised here.**

Two further arms not run, named rather than buried: a lead exiting with **no** live members (the
modal does not appear, so the path differs), and a lead killed rather than exited (`forceExit`/SIGKILL,
which D §4 already documents as skipping cleanup entirely).

**Nothing about RC-10 licenses a fleet-side change.** The probe's verdict rule was fixed before the
first run and it is met: `survivors == 0 on both graceful exits ⇒ the vendor's cleanup is sufficient`.
W5 writes no fleet code.

---

## 3. What these two probes hand to decision D1

D1 chooses between **(a)** keeping the closer as W1 left it and **(b)** restricting it to members whose
lead is dead. Its stated condition is *"choose (b) only if W3 moves the shutdown rate above the
closer's live-lead reap share (36.7%) AND P1 passes; otherwise (a)"*.

**P1 passes.** So the P1 term of that conjunction is satisfied and D1 turns entirely on W3's number,
which this wave does not measure and does not pre-empt.

Both probes point the same way on the underlying question: **the vendor's own lifecycle works when it
is actually reached.** P2 showed the `shutdown_request` path closing an idle member in under 10 s; P1
showed the lead-exit path closing four members and five windows on a box with no idle CPU. What fails
in both cases is *reaching* those paths — a blocked Stop hook that suppresses the idle notification
(W1's subject), and now an exit modal that no unattended lead can answer.

⚠️ **One caveat D1 must not skip:** P1's pass was obtained with a **human-equivalent keystroke**
answering the exit modal. If the fleet's leads exit unattended, they never reach the cleanup that
P1 just certified, and the 2 000 ms race is not the binding constraint — the modal is. That does not
license a SessionEnd close (the operator's constraint stands, and no measured population of
unattended lead exits was gathered here), but it does mean "the vendor cleans up on lead exit" is
true only of *attended* exits on this build.

---

## 4. Census — nothing of this wave's is standing

`captures/final-census.txt`, taken at `2026-09-20T00:18:07Z`:

* **member processes belonging to this wave: 0** (`./run-p1.sh --census` → `count=0`, the
  argv[0]-anchored three-flag matcher whose both-arm control is in §0).
* **every window this wave ever created — 13 of them — is closed**: 161 (P2's member), 162 (the
  discarded attempt-1 lead), 171 (the env control), 202–206 (run 1), 207–211 (run 2).
* **no probe shell runner is alive.**

Every close was performed by the session itself: P2's member exited on its own `shutdown_request`,
both P1 leads exited through their own confirmation modal and took their members with them, and the
env-control window ran a script that returned. **No `it2 session close`, no `kitty @ close-window`,
no `TaskStop`, and no kill against any Claude session was used at any point in this wave.** The only
`kill` calls in this wave's history targeted this wave's **own bash runner scripts** — pinned by pid
*and* verified by command string immediately before acting — never a session, pane or agent.
