# E — why `cc-lr move` holds or waits a session, and which holds a healthy in-place move could carry

Worktree `lr-inplace-immediacy` at `4ca1364f3`. Measured 2026-10-18T02:13Z–02:29Z. Read-only: no
cc-lr, lr-*.sh, launchctl, kitten or kill was run. The deployed `~/.claude` copies of `bin/cc-lr`,
`lr-upgrade.sh`, `lr-move-worker.sh`, `lr-handoff.sh` and `handoff-fire.sh` are byte-identical to the
worktree (measured: `cmp -s`), so the line numbers below are the code that ran.

Helpers (all read-only) are in `/tmp/lri-e/`: `summary.py`/`count.py` (plan.json + `<sid>.json`
join), `spans.py` (worker events), `goaltl.py` (goal/turn timeline), `bgcmds.py` (run_in_background
commands from a transcript).

**Correction to the brief.** The rejected-source rule (commit `1b97389dd`) carries **background
jobs** and releases **hold:goal-live** (`d33082629`). It does **not** carry drafts. Draft carry is a
separate rule: a transplanted remote recycle whose source is retired or unfocused
(`handoff-fire.sh:4744-4776`, operator ruling 2026-10-10). In the move lane the precheck probe's
`HELD:draft` (`handoff-fire.sh:13085-13105`) cuts it off before it can run, on every source.

---

## 0. Bottom line

- **0 of 84 plan rows ended MOVED**, across all 17 batches (measured: `summary.py`, every
  `<sid>.json`). The holds are not the only blocker: every `move` row also failed when the lane
  tried to act. Those failures are listed in §1c and not analysed further here.
- **What the holds cost.** None of them prevented a move. They turned four moves into lossy ones:
  4736324c, 04b3cbc3, 381200c5 and ab512c88 sat in waits. Then the operator typed `/limit-recover`
  into three of them, and ab512c88 hit a context boundary. All four left on a **fresh-context**
  `handoff-fire --recycle` (new session ids 48765eaa, 984d1eb2, d6ae5d72, a3da0696). In 4736324c
  that recycle answered keep-work, and its background copy was then stopped. Its 12-hour poller
  died with no record (handoffs.jsonl 02:02:21Z `recycle-bgwork-answered … '2' (Move to background
  and exit)`, 02:02:25Z `recycle-bgcopy-stop`).
- **Background-job waits cannot succeed.** In this window the jobs were pollers designed to live
  6 h, 12 h, until load < 120, or 4 h. All 3 of 3 completed `wait:background-job` workers ran
  their full 3600 s and ended `still-busy:background-job`.
- **Every hold:in-flight row was a self-collision.** All 14 in-window rows were the lane's own
  earlier workers holding the claim, mostly parked in W2 waits. This is measured: every claim pid
  named in a `claim-held`/`in-flight` row appears in a batch's `workers.tsv`.

---

## 1. Disposition counts

### 1a. Per batch (measured: `python3 -I /tmp/lri-e/summary.py`, 02:28:58Z)

| batch (plan time Z) | from→to | until_idle_s | dispositions |
|---|---|---|---|
| 1017T073813 *(outside window)* | next2→next | 0 | move 6 · hold:mid-turn 1 |
| 1017T235745-69993 | next4→next | 3600 | wait:background-job 1 |
| 1017T235745-69995 | next4→next | 3600 | wait:subagents-in-flight 1 |
| 1017T235745-69998 | next4→next | 0 | move 1 |
| 1017T235745-70005 | next4→next | 3600 | wait:background-job 1 |
| 1017T235746-69994 | next4→next | 3600 | wait:background-job 1 |
| 1018T000816-49288 | next4→next | 0 | move 1 |
| 1018T000922-71757 | next4→next | 3600 | move 1 |
| 1018T002357-40187 | next4→next | 0 | move 1 |
| 1018T002443-84451 | next4→next | 3600 | wait:subagents-in-flight 1 |
| 1018T003928-31080 | next4→next | 0 | move 1 |
| 1018T004329-1739 | next2→next | 900 | wait:background-job 1 |
| 1018T005330-69593 | next4→next | 1800 | move 4 · hold:in-flight 6 · hold:no-transcript 3 · wait:background-job 1 · wait:mid-turn 1 · wait:subagents-in-flight 1 · hold:goal-live 1 |
| 1018T012244-22836 | next4→next | 8134 | move 8 · wait:background-job 4 · hold:no-transcript 3 · wait:subagents-in-flight 1 · hold:goal-live 1 |
| 1018T014908-23285 | next2→next | 8134 | move 4 |
| 1018T020022-2123 | next4→next | 5400 | move 4 · hold:in-flight 8 · hold:no-transcript 3 · hold:goal-live 1 |
| 1018T021322-22546 *(outside window)* | next4→next | 4799 | move 1 · hold:in-flight 6 · hold:no-transcript 3 · hold:goal-live 1 · wait:composer-unknown 1 |

### 1b. Totals

| disposition | rows in window (23:57Z–02:01Z) | distinct sessions in window | rows, all 17 batches |
|---|---|---|---|
| move | 25 | 12 | 32 |
| hold:in-flight | 14 | 8 | 20 |
| wait:background-job | 9 | 5 (6db28068 509e3aad 4736324c 04b3cbc3 ab512c88) | 9 |
| hold:no-transcript | 9 | 3 (76ad8362 021711f4 ed29c5a1) | 12 |
| wait:subagents-in-flight | 4 | 1 (756b68c8) | 4 |
| hold:goal-live | 3 | 1 (3e929a81) | 4 |
| wait:mid-turn | 1 | 1 (381200c5) | 1 |
| hold:mid-turn | 0 | 0 | 1 (5423f92a) |
| wait:composer-unknown | 0 | 0 | 1 |
| **total** | **65** | | **84** |

Three things the brief cited do not appear in any of the 18 plan.json files (measured):

- **hold:goal-live for ab512c88.** Its goal was cleared at 2026-10-18T00:28:14Z (a `goal_status`
  record with `sentinel:true met:true`). Its earlier goal hold is the 2026-10-13 pane-297 block-cap
  incident in `d33082629`.
- **Teammates.** There was no next3 batch. The next3 team is examined in §2.8.
- **HELD:bg-work.** It never occurred in these batches.

### 1c. Final verdict per wait/move row (measured: `summary.py` and `<sid>.json`, 02:28:58Z)

| row | verdict / reason | n |
|---|---|---|
| wait:background-job | NOTMOVED `still-busy:background-job after 3600s` (6db28068, 509e3aad, 4736324c) | 3 |
| wait:background-job | NOTMOVED `still-busy:unread` (ab512c88 after 900 s; 04b3cbc3 after 1800 s): the session had already left its pane | 2 |
| wait:background-job | NOTMOVED claim-held · still waiting | 1 · 3 |
| wait:subagents-in-flight | admit-refused 1 · claim-held 2 · still waiting 1 | 4 |
| wait:mid-turn | NOTMOVED `still-busy:unread after 1800s` (381200c5 had left at 01:54Z) | 1 |
| move | REFUSED:intent-invalid 6 · HELD:unreachable 5 · HELD:load 4 · claim-held 7 · STRANDED 5 · REFUSED:not-limited 1 · HELD:draft 1 · HELD:unknown 1 · slot-wait 1 · admit-refused 1 | 32 |

What caused the move-row failures (measured from the handoff logs; not analysed further here):

- **intent-invalid / not-limited.** Each intent expires at `plan + until_s + 900` (`cc-lr:1484`).
  Workers for batches planned at 00:24Z, 00:43Z and 00:53Z only spawned at 01:50–01:52Z.
  `1739/batch.log`: "move-admit lock held by a dead process; taking it" at 01:51:45Z.
- **unreachable.** The kitty socket refused connections (handoffs.jsonl 00:30:54Z).
- **load.** "load 27.41/core is above the 8/core bound".

---

## 2. One section per class

### 2.1 `wait:background-job` / `hold:background-job` (and `HELD:bg-work` at the actuator)

**Where it is assigned**

- **Census:** `lr-upgrade.sh:1051`. `lru_bg_kind` (`:540-556`) reads `work` when any direct
  child of the claude pid is a Bash-tool shell (`shell-snapshots` or `claude-<hex>-cwd` in its
  argv) other than a cc-await-ping watcher. The row reads `move` only at `:1056`, after this test,
  so the census never calls a session `move` while a non-watcher job lives.
- **Plan:** `cc-lr:1201-1211` writes `wait:` when `--until-idle` > 0 and `hold:` otherwise. On a
  source that `lr_source_dead` calls rejected it writes `move` instead (`:1208-1209`).
- **Worker:** `lr-move-worker.sh:99-120` (W2) needs two consecutive shared-census snapshots that
  read `move`. Otherwise it ends at `:116` with `still-busy:<disp> after <budget>s; nothing touched`.
- **Actuator:** `hf_bg_work_gate` (`handoff-fire.sh:2959-3003`) holds `HELD:bg-work:ship-land`
  (`:2990`) or `HELD:bg-work:other` (`:2997`). At the dialog, the move lane's
  `CC_RECYCLE_BGWORK_ANSWER=stop-if-watcher` (`lr-move-worker.sh:165`; `handoff-fire.sh:11374-11454`)
  stops a watcher-only session and answers Stay to any other.

**The harm it prevents (documented).** `/exit` kills every job the session runs. The documented
reasons:

- "a land killed between rebase and push is the costliest of them" (`handoff-fire.sh:13061-13062`).
- `d33082629` kept this hold even for a rejected source: pane 16's `zprint -d` "no reader can tell
  from real work, and /exit kills a job whatever the account's state".
- The keep-work alternative "leaves a SECOND live copy of the session in the background"
  (`handoff-fire.sh:11378`).

**Does the rejected-source rule carry it?** Yes, since `1b97389dd` (operator ruling 2026-10-13):

- `cc-lr:1208` turns the row into `move`.
- `hf_bg_work_gate` releases work (`:2992-2995`).
- The watcher answers "Exit and stop tasks" (`:11362-11373`) after `rcy_jobs_capture` records each
  job's command and cwd (`:3408`). `rcy_jobs_mail` (`:3445`) sends the list to the successor.
- Ship-land jobs, team leads with live members and team members are still held.

It is limited to rejected sources because "No turn runs there until the reset, so nothing the job
produces can be used" (`cc-lr:1202-1207`). On a healthy source the job's output feeds a later turn.

**What the jobs were in this window** (measured: `ps -axo pid,ppid,etime,command`, `bgcmds.py`)

| session (pane) | job(s) besides the watcher | lifetime |
|---|---|---|
| 6db28068 (342) | `until load15 < 120; do sleep 60; done; scripts/ship-land.sh --lock /tmp/b13-r14-land.lock` | unbounded; etime 2:02:25 at 02:13Z |
| 509e3aad (28) | read-only sqlite poll of VoiceInk `stats.store`, `end=now+21600` | 6 h from 01:18Z |
| 4736324c (21) | `find … -newer` cohort poll, `end=now+43000` | 12 h from 2026-10-17T20:58Z |
| 04b3cbc3 (10) | `CC_0065_WAIT_S=14400 bash migrations/0065-load-plist-throttles.sh --confirm launchd` | a migration with a 4 h internal wait, i.e. real work |
| ab512c88 (3) | the operator's own `! env -u CLAUDE_CODE_SESSION_ID ~/.claude/bin/cc-lr move --sid ab512c88 --to next --until-idle 900`, typed in the subject's pane at 00:42Z. Claude Code moved it to the background after 120 s (task `br5w63fao`). | self-inflicted |

**The case for keeping the hold (adversarial)**

1. A job's output is what the session's next turn reads. Killing it on a source that can still
   take turns loses real work.
2. Neither argv nor process tree reliably separates a poll from work. `d33082629` refused to try,
   for exactly this reason.
3. The ship-land detector checks descendants only (`c != j`, `handoff-fire.sh:2873`). A deferred
   land like 6db28068's (`ship-land.sh` only in the eval string) reads `shipland=no` while it
   sleeps, so a looser rule would kill it.
4. Mutating loops (rsync, git fetch, migrations like 04b3cbc3's) do harm if killed mid-step.
5. The jobs mail says "moved this session off an account the server is rejecting". It is wrong
   for a healthy source and would need rewording.

**The case against keeping it, from this window**

1. The wait cannot succeed: 3 of 3 completed waits ran their full 3600 s, because the job outlives
   any budget by design.
2. The status quo already kills these jobs, only worse. 4736324c's poller died through the
   manual fresh recycle's keep-work answer and bgcopy-stop, with no record kept and the
   conversation's context lost.
3. Killing a loop while it sleeps interrupts no mutation. The successor can re-arm it from the
   carried command.

**Verdict: CHANGE.** Carry a narrow new kind, `waiter`, on a healthy source using the
rejected-source mechanism (record, stop, mail). Keep holding everything else. A job is a
`waiter` only if both hold when the probe reads it and again at the dialog:

- every live descendant of the job shell is `sleep`/`/bin/sleep`, i.e. it is between polls;
- the job's own eval string is a `while`/`until` loop or starts with `sleep`, and names no
  `ship-land.sh` or `migrations/`.

Separately, end the wait early when a job's declared deadline (`end=$(( … + N ))`, `--timeout N`)
is past the budget.

- **Would unblock:** 509e3aad and 4736324c. 6db28068 only if the operator rules that a deferred
  land may be killed while it sleeps.
- **Would not unblock:** 04b3cbc3 (work) or ab512c88 (see R4).
- **Risks:** a re-armed loop restarts its window; a mutating step that runs between sleeps is
  re-run by the successor; the state can change between the probe and the dialog (the dialog
  already re-reads, `:11400`). This narrows `1b97389dd`'s "Holds for a healthy source are
  unchanged", so it **needs an operator ruling**.

### 2.2 `hold:in-flight`

**Where it is assigned:** `cc-lr:1233-1246`. The row is held when `$MUTEX_DIR/<sid>.active`
(`runs/by-sid`) has a live holder (`lr_claim_holder_state`). The same claim produces the batch-time
`claim-held` verdicts.

**The harm it prevents:** two actuators on one session, meaning two `/exit`s or two transplants,
which leaves two writers or a stranded copy ("one actuator per session"). The harm is real and
severe.

**Rejected-source rule:** does not apply.

**This window (measured):** 14/14 in-window rows (20/20 across all batches), plus all 7
`claim-held` move verdicts in batch 22836, were held by the lane's own workers. The pid in each
row's action text was checked against every `workers.tsv` with
`jq '.rows[]|select(.disposition=="hold:in-flight")|.action'`. The holder pids (38052, 38260, 38577, 42086, 45363,
45965, 99147, 83778–89368) are all in `<batch>/workers.tsv`, and the `.active/holder` file names
`lr-move-worker (<batch>)`. Two compounding effects:

- **Stale budgets.** A session stays locked into an older batch's budget. 6db28068 is in batch
  22836's 8134 s W2 wait, so batches 2123 and 22546 could only show it as in-flight.
- **Waiting for sessions that have left.** W2 keeps waiting after the session is gone. Measured
  by comparing when each session left with the result time: ab512c88 waited about 9 min,
  04b3cbc3 about 20 min, 381200c5 about 28 min. In each case `snap.tsv` no longer had the row,
  `d=""`, and the reason read `still-busy:unread`.

**Verdict: KEEP the mutual exclusion, CHANGE the waiting around it:**

- end W2 at once when the row has been absent for two snapshots (verdict
  `gone: the session left this pane`);
- let a newer batch supersede an older worker that is still in W2, via a per-sid abort marker.
  Today's abort is per-batch (`lr-move-worker.sh:97,108`). W2 has touched nothing (`:116`).
- name the holder (batch, stage, budget left) in the plan row.

**Risk:** a worker may leave W2 at the same instant it is superseded. The abort checks before slot
and actuate (`:142,156`) already cover that.

### 2.3 `hold:no-transcript`

**Where it is assigned:** `lr-upgrade.sh:1042` (`lru_transcript` finds no
`<cfg>/projects/*/<sid>.jsonl`). It becomes `hold:no-transcript` through the catch-all `cc-lr:1230`.
It is deliberately not waitable (`lr-upgrade.sh:1119-1121`: "a structural one … no transcript
would be waited out for the whole budget and then refused anyway").

**What they are (measured):** registry rows `C46A75F2-…`, `61E0DF3B-…` and `813D0E0C-…`.

- **They are real processes.** Live claude pids 27166, 27167 and 59571, started 00:38–00:40Z,
  each under `cc-close-attrib` under a login `-zsh`. The LIVE pass requires a running pid with a
  matching lstart (`lr-upgrade.sh:636-662`).
- **They are iTerm2 panes,** not kitty. Their env has `ITERM_SESSION_ID=w0t0p0..p2:<UUID>` and
  `TERM_PROGRAM=iTerm.app`.
- **They never received a prompt.** No `<sid>.jsonl` exists in any `~/.claude*/projects`, and
  there is no project dir for their cwds (`.worktrees/wt-cc-193636-7967x`).
- **They inherited pane 332's identity.** Their env carries `KITTY_WINDOW_ID=332` and
  `CLAUDE_CODE_SESSION_ID=2e9ed9f2`, and pane 332's transcript holds an `osascript … tell
  application "iTerm2"`. iTerm2 was therefore started from pane 332's session, and its restored
  panes auto-launched claude.

**The harm it prevents:** nothing can be carried, because no conversation exists.

**A latent hazard:** their registry rows claim `kitty_listen_on unix:/tmp/kitty-44163`. Anything
keyed on the inherited `KITTY_WINDOW_ID=332` would type into pane 332, a different live session.
The paneUUID (an iTerm UUID) matches no kitty window, so today's actuator would simply miss.

**Rejected-source rule:** does not apply.

**Verdict: KEEP.** Relabel it `hold:empty-session (never prompted; nothing to carry)`. Moving it
has zero quota value because it takes no turns. **Risk:** none.

### 2.4 `wait:subagents-in-flight`

**Where it is assigned:** `lr-upgrade.sh:1050` (`lru_live_subagents`, `:487-493`, which calls
`handoff-fire --probe-live-subagents`, `:12674`). It becomes `wait:`/`hold:` at `cc-lr:1212-1214`.

**The harm it prevents:** an in-process Agent or Workflow dies with `/exit`. The healthy source's
subagents are really running.

**Rejected-source rule:** `--transplant-cause limit` implies `--allow-live-subagents`
(`lr-handoff.sh:350`, `handoff-fire.sh:3552`), only because on a limited account they are already
dead.

**This window:** 756b68c8 is running a 10-lane research Workflow, started 23:40Z and still running
at 02:20Z. At 23:56Z the session itself told the operator: "Switching mid-run would kill the
running steps, and I can't confirm a resume would find the workflow log from the new account."
The transplant does copy `<sid>/` (subagents, workflows, journals; `lr-transplant.sh:11`). Whether
Claude Code resumes a running Workflow after `--resume` is **unverified**.

**Verdict: KEEP.** The waiting improvements in §2.2 apply. **Risk of loosening:** losing hours of
agent work.

### 2.5 `hold:goal-live`

**Where it is assigned:** `cc-lr:1247-1254`. It requires `goal_live_condition`
(`hooks/lib/goal-state.sh:206`, which fails closed) and a source that is not rejected. Introduced
in `d46327fd2` with the action text "a /goal is live; its goal would drive it on mid-move". Kill
switch `CC_LR_MOVE_GOAL_HOLD=off`.

**Rejected-source rule:** carries it (`d33082629`). `cc-lr:1247-1250`: "THE GOAL HOLD GUARDS A TURN
THE SOURCE COULD TAKE … The goal moves with the transcript and drives the session again on the
target."

**Is the stated harm real for an in-place `/exit` + resume?** Mostly not, for an at-rest, dormant
goal:

- **The goal survives the move.** "A same-uuid --resume carries an UNMET goal with it
  (recycle-100p §2.3, measured on 2.1.220)" (`handoff-fire.sh:18776-18778`).
- **No backgrounded copy can keep driving it.** The goal-driving background copy appears only on a
  keep-work answer (`:11499-11500`), and the goal-clear dance runs only outside resume mode
  (`:11479`). The move lane never sends keep-work: stop-if-watcher stops tasks or answers Stay
  (`:11383-11384`).

**The case for keeping the hold (adversarial)**

1. **A real race window.** An actively looping goal reads "at rest" in the gap between `end_turn`
   and the Stop-hook feedback record. Measured on 3e929a81: 06:57:21.352→06:57:24.662 and
   06:58:28.464→06:58:31.432, about 3 s each. An `/exit` landing there interrupts a goal-driven
   continuation.
2. **Goal sessions start turns on their own.** Claude Code injected "Goal check-in: background work
   still running" turns (07:28Z, 08:55Z, 10:21Z on 10-17).

Against that:

1. **3e929a81's goal is dormant, not looping.** Its last `goal_status` record is
   2026-10-17T06:58:31Z, 19.5 h before measurement. Its only job is an idle-scoped watcher, during
   which Claude Code skips /goal evaluation (`goal-state.sh:6-11`). Its turns are watcher re-arms
   every ~55 min, ~15 s each (measured: `goaltl.py`).
2. **The existing last read already catches a started turn.** `lr-handoff`'s probe re-reads at
   rest just before `/exit` (`hf_bg_work_gate` → `HELD:mid-turn`, `handoff-fire.sh:2976-2983`).
   A spontaneous turn has the same small window as a mail wake on any watcher session, which the
   lane already moves.

**Verdict: CHANGE.** Key the hold on goal **activity**, not on whether a goal is armed. Move the
session when the epoch of the last `goal_status` record (`goal_liveness`, `goal-state.sh:247`)
and `idle_s` are both older than N (e.g. 600 s). Otherwise make the row `wait:goal-active` under
W2's two-snapshot calm rule.

- **Unblocks:** 1 session (3e929a81).
- **Risk:** low. The goal rides the resume; the leftover race is seconds wide and the last read
  guards it.

### 2.6 `wait:mid-turn` / `hold:mid-turn`

**Where it is assigned:** `lr-upgrade.sh:1044-1047` (`! lru_at_rest`; `:261-303`). It becomes
`wait:`/`hold:` at `cc-lr:1212-1214`. The actuator backstop is `HELD:mid-turn`
(`handoff-fire.sh:2976-2983`).

**The harm it prevents:** `/exit` interrupting a running turn. Real and severe.

**Rejected-source rule:** a limited source is released only when every record after the limit is
a harness notification (`hf_dead_source_notification`, `:2920`). A typed prompt still holds.

**This window:**

- **381200c5** was mid-turn in a live operator conversation (prompt 00:48:06Z, end_turn
  00:56:47Z). Its worker spawned only at 01:52Z. The operator had meanwhile typed `/limit-recover`
  at 01:50Z, and the session left on a fresh recycle at 01:54Z. The worker then waited until
  about 02:22Z (`unread`).
- **5423f92a** (outside the window) was `hold:mid-turn` with `idle_s` 29500. Its last record is an
  unanswered teammate `shutdown_request` from 2026-10-16T23:25:38Z. That is a stale unanswered
  record, not a running turn. Its argv could not be checked because the process is gone.

**Verdict: KEEP** for a live turn. CHANGE two things:

- apply §2.2's "row gone ⇒ stop waiting";
- treat a turn with no transcript write for more than N min, and no live subagent or child shell,
  as a structural `hold:stalled-turn`, not waitable. Do not move it: a pending permission prompt
  looks identical.

**Risk:** none from the change. It only stops spending wait budget.

### 2.7 `hold:draft` (plan) / `HELD:draft` (actuator)

**Where it is assigned:**

- **Plan:** `cc-lr:1215` (`composer-occupied`, from `lr-upgrade.sh:1055-1056`).
- **Actuator:** the probe's focus gate and composer read (`handoff-fire.sh:13078-13105`).
- **Worker:** `lr-move-worker.sh:25`: "Draft carry (W4/W7) is not built".

**The harm it prevents:** "An operator draft is theirs. The /exit would MERGE with it into one
text message" (`:13066-13067`).

**Carry:** not part of the rejected-source rule. The existing transplant carry
(`hf_rcy_carry_eligible`, `:4767-4776`) would carry an **unfocused** live source's draft. It
refuses a focused one, and a `[Pasted text]` block that exists only in memory. But the move lane's
probe holds the draft before that carry can run. The switch drive has its own carry
(`lr-upgrade.sh:1136-1143`, operator ruling 2026-10-03).

**This window: 1 row, and the hold was right.** 1bf14662 (pane 33) at 01:56Z showed
`focused: yes`, `hid_idle_s: 0`, composer `/limit-recover to account1 now if we have any remaining`.
The operator was typing it and submitted it at 01:58:53Z.

**Verdict: KEEP** for focused panes. Small CHANGE: for an unfocused pane whose draft can be
carried, let the probe report `composer: carry` and leave it to the recycle's carry arm. A carry
that fails after the confirm already unconfirms (`lr-handoff.sh:1975-1984`).

- **Unblocks:** 0 sessions in this window (measured).
- **Risk:** medium. Typing can start between the focus read and the clear.

### 2.8 Teammates (`hold:teammate`, `hold:lead-with-teammate`)

**Where it is assigned:** `lr-upgrade.sh:1038-1039`, through `cc-lr:1230`. Not waitable.

**The harm it prevents:** "A TEAMMATE never moves (its pane, its account and its close belong to
its lead), and a LEAD with a live teammate never moves either: … every graceful lead exit runs
cleanupSessionTeams, which kills the members" (`lr-upgrade.sh:788-791`).

**Rejected-source rule:** explicitly does not carry them (`handoff-fire.sh:11365-11366`; `1b97389dd`
"Still held on a rejected source, each on purpose").

**On next3 now (measured: registry plus `ps eww`):** 4 of the 9 next3 registry rows are one team.
The lead is pane 262 (eadacd8f). The members are panes 269, 270 and 271 (w2-removers, w2-gc,
w2-resume-shell), with etime about 15 h 48 min and `CLAUDE_CONFIG_DIR=~/.claude-tertiary`.

**Verdict: KEEP.** A CHANGE would mean porting the same-account upgrade team procedure
(`lr-upgrade.sh:387-412`: members first with their identity flags, then the lead with its team dir
held aside and `CLAUDE_INTERNAL_ASSISTANT_TEAM_NAME` to adopt it) across accounts. That adds moving
`teams/<team>` between config dirs, and it inherits a vendor limit: a resumed lead's roster holds
only itself, so members' replies land unread. **Risk:** high. This is a build, not a toggle.

### 2.9 An adjacent hold that pushed sessions into the lossy path: `hold:self`

- **What happened.** 4736324c's own `/limit-recover switch to account 1 now` (01:58Z) hit two
  refusals. `cc-lr switch` returned "REFUSED — the reconciler is live and it has no switch lane …
  Use: cc-lr move". Then `cc-lr move --pane 21` returned `hold:self`. With both in-place routes
  refused, the session fell back to a fresh-context `handoff-fire --recycle` (transcript
  01:58:25Z–02:01:11Z).
- **The same thing happened elsewhere.** 04b3cbc3, 381200c5 and ab512c88 also ended on
  `handoff-fire --recycle --account next --prompt-file …`, each with a new session id.
- **Verdict: CHANGE**, owned by another report. A subject asking to move itself needs an in-place
  route while the reconciler is live.

---

## 3. Direct answers

**(a) Why do background-job sessions wait over an hour?**

- **Why the wait never ends.** The census has no "idle while a job runs" state for a non-watcher
  job. `background-job` is decided at `lr-upgrade.sh:1051`, before the only `move` assignment
  (`:1056`). W2 needs `move` twice (`lr-move-worker.sh:113-114`). The jobs here are pollers built
  to outlive any budget: until load < 120 (still running after 2 h), 6 h, 12 h, and a 4 h
  migration. So 3 of 3 completed waits ended at the full 3600 s.
- **The census does report a session idle when its only job is a cc-await-ping watcher.** The
  watcher is stopped at `/exit` (stop-if-watcher).
- **`cc-lr switch`'s "stop + transplant" is a different object.** `lru_switch_bg_drive`
  (`lr-upgrade.sh:1569`) moves a Claude Code **background session** (`--bg`, daemon-hosted;
  census rows `bg-session`/`bg-busy`):
  1. quit the viewer;
  2. stop the job (`lru_bg_stop`, `:1452`);
  3. transplant the transcript;
  4. relaunch in the pane.

  It never moves a Bash `run_in_background` job inside an interactive session. No lane carries
  such a job alive. `/exit` either kills it ("Exit and stop tasks") or, on keep-work, forks the
  whole conversation into a background copy, which the recycle then stops (`rcy_bgcopy_stop`). The
  rejected-source rule's "carry" means record command and cwd, kill, and mail them so the
  successor can restart them.

**(b) What are the hold:no-transcript rows (UUID panes, idle null)?** They are real, live claude
processes (pids 27166, 27167, 59571) in three iTerm2 panes that inherited pane 332's environment.
They are not phantom registry rows: the pids are running with matching lstarts. They are **empty
sessions**: never prompted, no transcript in any config dir. `idle_s` is null because there is no
transcript to stat (`cc-lr:1191-1197`). Nothing can be carried, and moving them has no quota value.

**(c) Is "its goal would drive it on mid-move" real for an in-place `/exit` + resume?** Not for an
at-rest, **dormant** goal like 3e929a81's, whose last goal record is 19.5 h old. The unmet goal
rides `--resume` (`handoff-fire.sh:18776`), and the move lane never answers keep-work, so no
background copy can keep driving. The real but narrow harm is an **actively looping** goal. During
the ~3 s evaluator gap (measured above) it reads at rest, and an `/exit` landing then interrupts a
goal-driven continuation. That justifies keying the hold on goal activity, not on whether a goal is
armed.

---

## 4. Recommended changes, ranked by sessions unblocked × safety

Session counts are in-window distinct sessions (measured). "Unblocked" means the session becomes
movable by the lane in place, with its context intact.

| # | change | unblocks | safety | why it ranks here |
|---|---|---|---|---|
| R1 | **W2 bookkeeping.** End the wait when the row is gone for two snapshots. Let a newer batch supersede an older worker still in W2 (per-sid abort). Name the holder in `hold:in-flight` rows. | 0 moves directly. Removes 14/14 self-collision in-flight rows across 8 sessions and the ~9–28 min ghost waits. | **high**: W2 has touched nothing (`lr-move-worker.sh:116`) | Prerequisite for every other change: today a re-issued `cc-lr move` cannot reach a session parked in an older batch. |
| R2 | **Carry sleep-only `waiter` jobs on a healthy source** (record, stop, mail; §2.1 rule). Exclude ship-land and migrations. Fail fast when a job's declared deadline is past the budget. | 2 (509e3aad, 4736324c); 3 with a ruling on deferred lands (6db28068) | **medium-high**: kills only between polls; successor re-arms from the mail | Largest unblock in the window. The status quo killed 4736324c's poller anyway, unrecorded and with its context lost. **Needs an operator ruling** (narrows `1b97389dd`). |
| R3 | **Key the goal hold on activity.** Move when the last `goal_status` record and `idle_s` are both older than N; otherwise `wait:goal-active`. | 1 (3e929a81) | **high**: the goal rides `--resume`; no keep-work in this lane | Cheap: `goal_liveness` already returns the epoch. Kill switch `CC_LR_MOVE_GOAL_HOLD` exists. |
| R4 | **Don't let the requester's own `cc-lr move` be the job that holds its subject.** Refuse `cc-lr move --sid X` run as `!`-input inside X's pane, or have the census ignore a shell whose eval string is `cc-lr move … <X>`. | 1 (ab512c88 pattern) | **high** | A self-inflicted hold; trivial to detect. |
| R5 | **Stale mid-turn:** a turn with no write for over N min and no subagent or shell becomes `hold:stalled-turn`, not waited. | 0 moves (stops wasted budget; 5423f92a sat 8.2 h) | high | Hygiene only. |
| R6 | **Relabel no-transcript** as `hold:empty-session`; never move it. | 0 (nothing to carry) | n/a | Makes the plan table honest; 3 rows per batch. |
| R7 | **Unfocused, carryable draft** goes to the recycle's existing carry arm instead of probe `HELD:draft`. | 0 in window | medium | The only observed case was the operator typing; the hold was right. |
| — | **KEEP:** subagents-in-flight (756b68c8), live mid-turn (381200c5), focused draft (1bf14662), ship-land in flight, real-work jobs (04b3cbc3), teams (4 sessions on next3). | — | — | Each guards work that an `/exit` destroys and the successor cannot rebuild. |

**Cross-cutting.** In this window the holds did not stop sessions moving. The operator worked
around them by hand, and 4 sessions were moved on lossy fresh-context recycles. A change is worth
making when it beats *that* outcome, not when it beats an idealised "wait until idle".
