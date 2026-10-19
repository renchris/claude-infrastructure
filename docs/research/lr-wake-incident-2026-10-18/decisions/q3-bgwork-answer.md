# Q3 / decision 4dce9ca65af4: what the recycle answers when `/exit` raises the bg-work dialog over real work

Read-only research, 2026-10-18 (trunk `lr-wake-fixes` d247eeef7; Wave A `lrwake-A` 3fb8bd3e6 does not change answer selection).
The box was at load 229–328 during the research, so two long scans were cut short. They are named under "Unmeasured" below.

## Answer

**Keep today's answers ("keep-today"). Do not add "Stay and hold". Correct the decision's premise, and add one small change so that orphaned jobs reach a reader. Conviction 80%.**

The premise is wrong for the lane it names. The in-place **move lane** (`lr-move-worker` → `lr-handoff --in-place`, `LR_PLACED_BY=cc-lr-move`) has **never** answered "Move to background and exit". Since it was created on 2026-10-04 it has passed `CC_RECYCLE_BGWORK_ANSWER=stop-if-watcher`:
- that value stops a watcher-only session;
- for real work it falls to `cancel` (Esc = Stay, the source is unconfirmed, NOTMOVED `HELD:bg-work`).

So option (b) is already what the move lane does. The keep-work answer happens only on **self-initiated** recycles, where the session's own tool call ran `handoff-fire --recycle` or `cc-lr switch` from its own tty. In 14 days those jobs were pollers and loggers, never builds, servers or ports. Holding those sessions would hold a move the session asked for, to protect a poller whose result is lost either way. It would also reverse the 2026-10-14 lead scope rule ("no new HELD outcome where today completes", `handoff-fire.sh:11508`).

The real cost of keep-work is that the orphan's output reaches nobody. That is fixed by naming the jobs to the successor, not by holding.

### The 3 strongest facts

1. **The move lane already answers Stay over real work, and it reached that branch once in 14 days, on a misread watcher.**
   - `scripts/limit-recover/lr-move-worker.sh:404` sets `CC_RECYCLE_BGWORK_ANSWER="${LR_MOVE_BGWORK_ANSWER:-stop-if-watcher}"`. Commit `d46327fd2` (2026-10-04) introduced the lane with this value.
   - `scripts/limit-recover/lr-handoff.sh:1943-1945` forces `cancel` for any placed move unless the value is `stop-if-watcher`. Header `:36`: "the background-work dialog is never answered keep-work".
   - In `scripts/handoff-fire.sh:11621-11626`, the keep-work fallback needs `rcy_tp_siw=1` or `rcy_self_siw=1`. Both are set only when the answer was `on` (`:11509`, `:11533`). An explicit `stop-if-watcher` therefore falls to `CC_RECYCLE_BGWORK_ANSWER=cancel`, which is Esc plus `recycle-held-bgwork` (`:11629-11648`).
   - Pinned by `tests/handoff-recycle-bgwork-dialog.bats:746`: "[RED] stop-if-watcher: real background WORK is answered Stay and held — no index is sent".
   - Count of `HELD:bg-work` over all 78 move batches:
     ```
     grep -rh -o "HELD:bg-work[a-z:-]*" ~/.reso/limit-recover/move  →  2 HELD:bg-work   (one row: .json + .events of the same sid)
     20261013T043637Z-next3-next2-93676/c56c729c….events.jsonl: "NOTMOVED: HELD:bg-work — the recycle's watcher held after the confirm and handed the source back; live in pane 12 on the source, one copy"
     precheck in its handoff.log: "bg_work: none shipland=no pids=-"
     ```
   - The task behind that dialog was `bjxbs66y2`, "Wait for the next peer ping to this pane" (`cc-await-ping`). It failed with exit 2 at 05:24:28Z. The transcript is `~/.claude-tertiary/projects/-Users-chrisren-Development-personal-launch-film-2026/c56c729c….jsonl.handed-off`, lines 1167 and 1218.
   - So the only move-lane case in the window was a watcher, not real work. The move lane's real-work holds happen earlier, at the census:
     - 95 `wait:background-job` rows across 26 plans;
     - 0 `work` verdicts at the precheck (`68 none · 44 watcher · 1 unknown`).

2. **Every keep-work copy in 14 days came from a self lane. 7 of 58 carried a non-watcher job, and all 7 were pollers, loggers or stale shells.**
   - Each "Move to background and exit" leaves a job dir `<cfg>/jobs/<short>/state.json` with `interactiveLineage:true`, plus `adopt.json` listing the shells it inherited:
     ```
     58 copies 2026-10-05..10-18 · state: 56 stopped, 1 done, 1 failed (all copies stopped or ended; 0 running)
     adopted non-watcher shells (the orphans):
       fd99d4dc 10-08  until gh run list … (CI poller)
       8fbca4ab 10-07  python urllib health poll, 2400 s
       5b7881fc 10-08  cc-upgrade-gate.sh started 04:20, still listed 16 h later (stale), + a hung `cat > /tmp/fire-… <<EOF`
       82d14397 10-13  bash /tmp/shc/loadlog.sh + wait-load.sh
       3ad5a1c7 10-16  VoiceInk sqlite poll (1080 iterations)
       95c275e1 10-18  cohort poller, 43000 s  (+ cc-await-ping)
       1ad7a4c9 10-18  cohort poller, 14000 s
     all others: only cc-await-ping, or no adopted shells
     ```
   - Cross-check: the partial `continued-in` scan found 44 unique copy ids. All 44 have a job dir (`in-jobs=44 missing=0`).
   - The 5 keep-work rows still in `handoffs.jsonl` (10-16..10-18: panes 22, 21, 333, 21, 374) are all self-recycles:
     - each has a `recycle-bgwork-selfcall` row ("own tool call pid … returned"), a `prompt_file` and `attempt:null`;
     - each `recycle-bgcopy-stop` says "stopped … job state stopped".
   - Open jobs at those exits (transcript scan):
     - 0be7fbec: `until ! pgrep gate.sh …` poller;
     - 4736324c: cohort poller and `cc-await-ping`;
     - ad2417e7: `dr16.sh` bench, whose log stopped at 03:25:39Z;
     - 48765eaa: cohort poller;
     - 9cc0a58e: a Monitor on a workflow journal. A Monitor is in-process and ends with the stopped copy.
   - Across the window: 0 dev servers, 0 bats, 0 builds holding ports.

3. **What Stay costs when it does hold: hours on the source, and under a limit it protects nothing.**
   - c56c729c was held at 04:41Z on a weekly-limited next3. Its job's completion woke it at 05:24:28Z, and the turn was eaten: `"You've hit your weekly limit · resets 7am"` at 05:24:29Z. It moved about 1 h later (`/exit` at 05:41Z). Stay kept the job alive, but the session could not consume the result.
   - Census holds on pollers in the move lane:
     - a3da0696 waited on `until … --census-ab-report …; do sleep 1800` through 10 batches, 07:03Z → 18:07Z (11 h). Its source was not limited (no limit record on 10-18), so the cost was only an undrained session.
     - ebbc7b61 waited through 4 batches on 10-11 behind a VoiceInk sqlite poller.
   - A Stay leaves a **live** session at its composer (Esc, scrub of our own `/exit`, unconfirm). The pane is not dead, but it is stuck where it is until the job ends or the limit resets.

## Answers to the four questions

**1. How often.**
- Move lane: 0 real-work dialogs in 14 days (78 batches). It reached the dialog over "work" once, and that was a misread `cc-await-ping`.
- Self lanes: 58 keep-work copies in 14 days, about 4 a day. 7 of them carried a non-watcher job, all pollers, loggers or stale shells.
- `handoffs.jsonl` keeps only about 2.5 days: the trim rows dropped 3 `recycle-bgwork-answered` and 1 `recycle-held-bgwork` (rows `class:"trim"`). That is why the job dirs are the census used here.

**2. What an orphan costs.**
- The task keeps running, reparented to pid 1. Measured in decision 75ea14d27d0f's receipt: `sleep 1777` survived `claude stop`.
- Its output file survives the predecessor's exit, until reboot: 3 of 3 predecessors recycled since boot still have `/private/tmp/claude-501/<proj>/<sid>/tasks/`.
- So a resumed same-sid session could Read the output by path. Nothing tells it to: no harness notification reaches the successor, and the copy that would have received it is stopped.
- The orphan ends at its own bound (14000–43000 s for the pollers).
- No port or lock holding was observed. The one lock-shaped risk, a `ship-land`, is held everywhere (`hf_bg_work_gate` returns `HELD:bg-work:ship-land`, `handoff-fire.sh:3147`). It never reached the keep-work arm in this window.

**3. What Stay costs.**
- See fact 3: hours on the source, and nothing gained under a limit.
- A dated ruling cuts against a new hold, but it is the **2026-10-14** lead scope rule, not 2026-10-10:
  - `handoff-fire.sh:11505-11508`: "whenever stop-if-watcher holds (real work), a keep-work menu keeps today's answer — the lead's ruling 2026-10-14: no new HELD outcome where today completes";
  - `docs/research/recycle-failure-2026-10-14.md` F4: "the change adds no new HELD outcome".
- The 2026-10-10 items are different rulings:
  - the lead ruling "no operator confirmation needed" for the watcher stop (`:11527`);
  - the operator ruling in `docs/research/lr-stranded-husk-2026-10-10/ROOT-CAUSE.md:7`: "zero human in the loop and zero asking the human as a pause idle step".
  - Both lean against hold-and-page.
- Settled FLEET_V2 decision 2 (`docs/plans/LIMIT_RECOVER_FLEET_V2.md:532-533`: hold real jobs, page at 20 or 60 min) governs **recovery** lanes. Those already cancel: `lr_recon/act.py:62`, the move lane, and `lr-upgrade.sh:2817`.
- No memory file has a 10-10 no-hold ruling (grep of `memory/` for "new hold", "today completes" and "new HELD": no hit).

**4. The recommendation and the code change.**
- Keep the answer matrix as it is:
  - move lane, reconciler and team: Stay;
  - rejected source: stop and carry;
  - watcher-only: stop;
  - self or unplaced keep-work over real work: keep-work plus `rcy_bgcopy_stop`.
- Add a "jobs still running" note to the successor on the keep-work arm:
  - `scripts/handoff-fire.sh:11686-11692` (Wave A: around `:11881`). Just before `hf_bounded "$IT2" session send -s "$RSID" "$bgk"`, call `rcy_jobs_capture "$(jq -r '.pid // empty' "$REG_DIR/$RSID.json")" ""`, which already exists at `:3565`. It records each Bash shell's pid, start time, directory and command while it is alive.
  - Set `RCY_JOBS_KEPT=1`.
  - `scripts/handoff-fire.sh:3602-3611` `rcy_jobs_mail`: branch on `RCY_JOBS_KEPT`. The subject becomes "your background jobs are still running", and the body says "JOBS-ORPHANED: the move kept N background job(s) running headless; nobody will be notified when they finish; their output is at /private/tmp/claude-501/<proj>/<old-sid>/tasks/<id>.output; check or kill: <pid list>".
  - The mail call sites at `:12206`, `:12270` and `:12329` already fire it after engagement.
  - Row: `recycle-jobs-orphaned`.
  - Kill switch: `CC_RECYCLE_KEEPWORK_JOBS_MAIL=off`.
- Test: in `tests/handoff-recycle-bgwork-dialog.bats`, next to `:610` and `:915`, a keep-work answer over a stubbed non-watcher shell (`HF_PS_SNAPSHOT`) writes a carried-jobs file and one `recycle-jobs-orphaned` row, and sends no Esc.
- Optional, and outside this decision: the census-level cost (11 h behind `sleep 1800` pollers) belongs to the move lane's `wait:background-job` budget, not to the dialog answer.

## Why not (b) with a time cap
- In the lane where (b) would matter, the move lane, it is already the behaviour.
- In the self lanes, (b) turns a self-requested move into a held session plus a retry ticket. The jobs it protects are pollers whose results the predecessor cannot consume, because it is limited or leaving.
- A cap that then applies (a) only adds latency before the same outcome.

## What would lower this conviction (20% residual)
- A self-recycle that orphans a stateful job: a dev server holding a port, a build writing into a worktree the successor also writes, or a `ship-land`. None was seen in 58 copies, but n is small and the job dirs cover only about 14 days.
- Evidence that the operator reads "in-place move" as `cc-lr switch` typed by the session. That lane is self, so it answers keep-work, and the operator might want it to hold.

## Unmeasured
- The `continued-in` grep across 14,091 transcripts did not finish under this load. 44 ids were found, all with job dirs. The job-dir census of 58 is the count used.
- Whether each orphaned poller ran to its timeout: not checked. The reboot at 21:34Z cleared `/private/tmp`, so the pre-reboot task outputs are gone.
- Why the `dr16.sh` log stopped at 03:25:39Z (killed or hung?): not checked.
