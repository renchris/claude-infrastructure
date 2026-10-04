# FLEET_V2 W5b — real canaries, shadow, cutover (2026-09-29)

Plan: `docs/plans/LIMIT_RECOVER_FLEET_V2.md` § W5 ("Real canaries", "Shadow", "Cutover"). Backlog row
`8e67a18de9ad`. Raw transcripts of every canary run are beside this file (`canary-*.txt`, `$HOME`
rewritten to `~`).

## How the canaries ran, and why not the way the plan wrote it

The plan ran the canaries on the real launchd job in `mode=act` with `LR_RECON_CANARY=<sids>`. That
needs the operator's cutover switch (`recon.on`), and at fire time the hook lane was the live actuator
(`autorecover.on` present, `recon.on` absent). So the canary scope was built as its own daemon:

- `LR_RECON_CANARY=<sids>` makes the daemon see and act on those sids only (census and request lister),
  with its own tree `~/.reso/limit-recover/recon-canary/` and its own switch `recon-canary/canary.on`.
  It refuses to start in the live reconciler's root.
- It shares the real limit-recover tree's locks, runs and ledger with every legacy actor, so the launch
  lock still arbitrates against the poller's resume-debt sweep, and the fence (bash and python) defers
  legacy actors to a canary-owned sid exactly as to the live reconciler.
- The account fact that makes a session idle-eligible is written only into `recon-canary/facts`
  ("scoped canary"); pages go to a log (`LR_NOTIFY_BIN`).
- Driver: `tests/rig/lr-recon-canary.sh --canary N` — one throwaway real session per run (haiku, a fresh
  `--session-id`, on `next`) in its own kitty OS window, the daemon under a launchd-shaped supervisor.
  Faults 2 and 3 use `HF_CANARY_HOOK`, a test hook inert unless `LR_RECON_CANARY` is set.

## Verdicts

| Canary | Result | Evidence (the operator's `cc-lr status --cohort` line) |
|---|---|---|
| 1 cross-account idle no-prompt move | **PASS** (run 2) | `CLOSED 1/1 (ENGAGED 0, MOVED 1) · … · double-typer 0 · split-brain 0 · lost-records 0` — `97e01e47` next→next4, window 1312, same uuid, 1 lock taker |
| 2 draft injected after confirm | **PASS** | same DoD shape — `29596290` held `A rc=6 → HOLD`, UNCONFIRM, HOLD-DRAFT, re-probed after the draft cleared, re-planned next→next3, MOVED; window 1313, same uuid |
| 3 watcher SIGKILLed after `/exit` | **PASS** (run 4) | same DoD shape — `c97525a2` EXITED, B relaunched in place, `recycle-engaged … engagement by process (no-prompt relaunch) within 15s`, next→next2, window 1318, same uuid |
| 4 SIGKILL of the reconciler mid-cohort | **PASS** | same DoD shape — `7ff7c958`: reconciler SIGKILLed 5 s after its move spawn, restarted by the supervisor 10 s later, the in-flight actuator adopted; exactly one `recycle-intent` (one `/exit`), next→next4, window 1321, same uuid, 1 move spawn and 1 lock taker for attempt 1 |

Independent read on every PASS: the canary window's own registry row holds the sid under the target's
config dir, and `launch.log` shows at most one lock taker and one move spawn per attempt.

The two throwaways stranded by defects 1 and 5 (`b742e38b`, `da0f282f`) stayed in the canary list;
on the fixed code the daemon moved both: `b742e38b` CLOSED via MOVED next→next3 (its record's stale
`~/.claude` source healed by the PRE-MOVE source refresh), and `da0f282f` reached MOVED next→next2 through the fixed
husk path (the teardown ended its sentinel before the close; its resume debt reads `proven`). All canary windows were
closed at 19:23:35Z by `--teardown`, which also removed `recon-canary/canary.on`.

## What the failed runs found (each fixed with a pin that is red on the old code)

The rig's stub could not see any of these; each needed a real Claude Code session. Every fix commit
names W5b in its message: `git log origin/main --grep 'W5b' --oneline` lists them with their pins.

1. **Every `next` session's source config read as `~/.claude`** (canary 1, run 1). `~/.claude-next/
   sessions` and `projects` are symlinks to `~/.claude`'s, so the census read each row twice and kept
   the alias no account maps; `lr-handoff` refused every `next` move. Fixed in `observe_rows.py`, plus a
   PRE-MOVE source refresh in `census.py` so records the pre-fix observe daemon already wrote heal at
   cutover.
2. **The daemon claimed a trust preseed it never ran** (read-through, before canary 1). `LR_PRESEED_DONE`
   made every move skip the target's folder-trust seed. `bf00f9045` (landed with `371128ac0`).
3. **B could never succeed** (canary 3, run 1). The resume launcher pinned the attempt it was minted
   under, overriding the attempt B types after taking the launch lock, so `lr-fire-resume` refused its
   own rescuer rc 10. Fixed in `lr-handoff.sh` (the typed pair wins).
4. **A placed move mailed the session it was moving** (canary 3, run 2). The voluntary verdict mail woke
   the subject mid-move; it took a turn and the last read held it. Canaries 1-2 won the same race.
   Fixed in `lr-handoff.sh` (`lrh_verdict`).
5. **The husk gate read the stub alone** (canary 3, run 2). The at-rest proof read retired + stub, then
   the background-work gate got the stub and held an at-rest session `HELD:mid-turn`. Fixed in
   `handoff-fire.sh` (`hf_recycle_last_read`).
6. **A held husk re-spawned every ~4 s** (canary 3, run 2: 181 spawns). Fixed in `settle.py`.
7. **A no-prompt relaunch was judged by an assistant turn** (canary 3, run 3). The rescue worked and was
   declared dead after 180 s (`recycle-dead` paged); canaries 1-2 passed only because their sessions
   happened to take a turn. Fixed in `act.py` (`HF_ENGAGE_BY_PROCESS` for idle moves); and the late
   rc 1 re-opened a MOVED record, fixed in `settle.py`.

## Shadow

`tests/rig/shadow_lib.py` (pinned by `tests/lr-recon-shadow.bats`) computes the plan's three gate
checks per real cohort. `watch` runs detached, archiving each cohort's records, fact history and plans
(the observe daemon reaps expired facts and overwrites `shadow/<cid>.json` every pass) and mailing the
waiting session per new cohort. No real limit has happened since the observe daemon started at 17:42Z;
all four accounts sat at 0-6% of their 5-hour window.

**Which cohorts count (agreed with the origin lead, 2026-09-30 02:53Z).** The observe daemon was
restarted onto the W5b fixes at 21:14Z (operator step `ff7bd8ba875e`). The operator then ruled the six
open decisions (plan § W6), and W6d rewrites `lr_recon/**` to match. A cohort shadowed before the W6
code runs validates a planner that cutover will not run, so each cohort's verdict names the planner
code it ran (compare the cohort's time with the latest `recon/restarts.jsonl` row and the W6d/W6f land
times), and only cohorts judged by post-W6 code (W6d and W6f landed, then the reconciler restarted —
an operator step the lead files) count toward the 2 needed for cutover. Earlier cohorts are still
compared and recorded as evidence.

Still waiting at 02:53Z: no real limit since 19:40Z. The first likely one is a weekly limit (`next2`
at 79%, rising about 1 point an hour).

### Second run (W5b2), counted from the reboot

**Cutoff.** The host rebooted at 20:26Z on 2026-09-30, which restarted the reconciler onto the final
code (W6f and W7a had been on the shared checkout since 19:43Z): pid 68005, started 20:43:55Z, the last
row of `recon/restarts.jsonl` (t=1790801043.8), confirmed by `launchctl print` (running, pid 68005).
The five `lr_recon` modules it imports are byte-identical to origin/main at `cda13e6a1`, and no
`lr_recon` commit has landed since. Mode is observe: `recon/mode` and `recon.on` are both absent, and
`autorecover.on` is present, so the hook lane is the actuator. Only cohorts whose limit began after
20:43:55Z count toward the 2. If the reconciler restarts again, its new start time is the cutoff and
the count starts over.

**Watcher.** The reboot killed the first one. Restarted at 21:39Z as pid 73698, detached (parent 1,
its own process group), `watch ~/.reso/limit-recover --interval 20 --notify lr-fv2-w5b2-38`, log
`~/.reso/limit-recover/shadow-archive/watch-w5b2.log`; it is the only `shadow_lib.py` process.

**Cohorts at 21:47Z.** None has opened since the cutoff. The one open cohort is
`next2-7d-1791025200`, next2's weekly limit: opened 07:09:55Z (the `open` stamp in its
`.pages.json`), resets 2026-10-03 11:00Z, 9 members. It began before the cutoff, so it is evidence
only. Compared while still open, at 21:40Z:

```
SHADOW next2-7d-1791025200: members 9 · legacy found 17 · census misses 11 (0715cd0c,3c85fe54,3d42fa49,46bc0436,4a956c3b,7c395da7,84f3533b,8ea01453,a87593c9,cfb177b2,e44c8e8c) · placements feasible 3/3 · phase agree 0/6 (false-RECOVERED resolved 3, plan differed 2) → FAIL
```

- The 11 census misses are not misses. All 11 are stop markers from 2026-09-24 and 2026-09-29, earlier
  next2 limits that came days before this cohort. They count because the cohort record carries
  `opened_at: 0.0`, so the compare's marker window starts at the epoch, and `resets_at: null`, so no
  hook request can match (defect A).
- The placements were all feasible (3 of 3).
- Phase: 2 plan differed (46d14e14 and 68691067: the recon planned next3, legacy moved them to next4)
  and 4 disagree: c28362b6 and c8c2adc0 (legacy recovered them before the cutoff; the recon had no
  target), cd3bd860 (defect B) and 4d7c9bce, this session and the only member limited after the
  cutoff (defect C).

**Instrument fix, same run.** Defect A reached the gate through `shadow_lib.py`, which trusted the
cohort record's reset and opening time; the pin's fixture wrote both, a shape the daemon never writes.
The compare now takes the reset from the cid and the opening from the open page's stamp (the cohort's
`.pages.json`, archived beside it as `pages.json`), falling back to the earliest member detection, and
prints a `window:` line whenever it had to. The watcher also stopped archiving `<cid>.pages.json` as a
cohort of its own: the archive index still holds the one stale `next2-7d-1791025200.pages` row it made.
Pinned in `tests/lr-recon-shadow.bats` with the daemon's real record shape. The same cohort, at 21:52Z:

```
SHADOW next2-7d-1791025200: members 9 · legacy found 6 · census misses 0 · placements feasible 3/3 · phase agree 0/6 (false-RECOVERED resolved 0, plan differed 2) → FAIL
  window: opened 2026-09-30T07:09:55Z, resets 2026-10-03T11:00:00Z (reset from the cid, opened at the open page's stamp; the cohort record left it unset)
```

Checks 1 and 2 now pass, and the FAIL is check 3 alone. One more pre-cutoff fact: for cd3bd860 the
recon planned next3 and legacy used next3, yet between its 07:18Z engagement there and the reboot the
recon never derived ENGAGED. The final code never judged that session live, so this is evidence only.

**Defects on the final code.** Messaged to the lead at 21:48Z. Not fixed here: `lr_recon/**` is
outside this wave.

- **A. The cohort record loses its key.** Each pass, `_report` (`lr_recon/__main__.py:992`) rebuilds
  `T.Cohort(cid, acct, scope, members)` without `resets_at` or `opened_at`, and `report.write_cohort`
  persists it. `recon/cohorts/next2-7d-1791025200.json` therefore reads `resets_at: null,
  opened_at: 0.0`, though its own cid encodes the reset. The same object feeds the pages: the open page
  renders `until ?` (`report.py:619`), and an all-good close page would time the cohort from the epoch
  (`report.py:700-701`). Every future cohort carries it, and so does the shadow gate's check 2.
- **B. A reboot-parked record flaps every pass.** cd3bd860 (legacy recovered it to next3 at 07:18Z;
  its pane died in the reboot) is set to `PARKED-REBOOT` by the census stale pass ("planned before
  kern.boottime", `census.py:497-505`), and the same pass's derive overwrites that with
  `PANE-GONE/R` (row 11, "resume owed", `phase.py:147-149`). The §4.4 invariant then flags it:
  408 `stale` and 408 `RECON-DEFECT PANE-GONE/R` events from 20:46:46Z to 21:43:51Z, one each per
  pass. The cohort status buckets it "moving". In act mode `act.may_actuate` has no reboot-park guard
  and `act.choose` returns `R`, so `cmd_replace` would run `boot-resume-launch.sh` for a session the
  daemon's own status says to relaunch by hand.
- **C. A session legacy recovers to an account the recon did not place never reads as engaged.** This
  session was limited on next2 at 21:26:29Z; the hook lane recovered it to next at 21:37:08Z (watcher
  ENGAGED) and it has worked there since. Its record is plan-only with no target: it went `IN-FLIGHT`
  at 21:36:33Z ("relaunch gap"), is still `PRE-MOVE/IN-FLIGHT` at 21:47Z, and has drawn
  `RECON-DEFECT PRE-MOVE/IN-FLIGHT` every pass since its 600 s bound ran out at 21:46Z. The four
  pre-cutoff records of the same shape (46d14e14, 68691067, c28362b6, c8c2adc0) expired `IN-FLIGHT`
  and were paged ESCALATED at 18:38Z and IMPOSSIBLE at 19:13Z, while legacy had recovered all four
  and each had engaged.

Wherever B or C occurs it fails gate check 3. C occurs whenever legacy recovers a session the recon
did not place, which is what happened to the only member limited since the cutoff. B occurs for a
record that straddles a reboot. A fix to either means a reconciler restart, and that resets the
cutoff.

### Cutoff moved: the reconciler restarted onto W7b (2026-10-01 01:02:56Z)

The lead's W7b wave fixed all three on trunk: `49f77447d` (A: a rebuilt cohort keeps its reset and
opening time), `95264bd12` and `7996dcb9a` (B: the census owns the reboot park, so a parked record
is never re-derived or actuated, and only an open resume debt reads as open), and `cb4bc0207` (C: a
session engaged on a holder the reconciler did not place settles). The reconciler restarted onto them
as pid 79972 at 01:02:56Z: the last row of `recon/restarts.jsonl` (t=1790816578.19), confirmed by
`launchctl print` (running, pid 79972). Every live `lr_recon` module is byte-identical to origin/main,
and no `lr_recon` commit has landed since. **This start time is the cutoff now.** Only cohorts whose
limit began after 01:02:56Z count toward the 2; none had at 01:05Z. Nothing that opened before it
ever counts, including `next2-7d-1791025200`, which keeps gaining members until its reset at
2026-10-03 11:00Z (ceaa8922 joined at 21:58:48Z).

**The fixes, read off live data two minutes after the restart.**
- A: `recon/cohorts/next2-7d-1791025200.json` now carries `resets_at: 1791025200` and
  `opened_at: 1790752192.1` (07:09:52Z, the first member's detection).
- B: cd3bd860 drew one reboot-park `stale` event, then `engaged-elsewhere`, and closed
  `ENGAGED/CLOSED`. No `PANE-GONE/R` and no `RECON-DEFECT` event since the restart.
- C: this session's record, 4d7c9bce, read `engaged-elsewhere` and closed `ENGAGED/CLOSED`, as did
  ceaa8922.

The same evidence cohort, compared again at 01:05Z, needs no fallback (no `window:` line):

```
SHADOW next2-7d-1791025200: members 10 · legacy found 7 · census misses 0 · placements feasible 3/3 · phase agree 3/7 (false-RECOVERED resolved 0, plan differed 2) → FAIL
```

The FAIL now rests only on c28362b6 and c8c2adc0. The old code drove them to `IMPOSSIBLE` before the
fix, and a terminal record is not re-judged, so they stay that way although both sessions are alive
(46d14e14 and 68691067 likewise, counted as plan differed). This is history from a cohort that does
not count.

**Watcher.** Since 22:49Z the watcher is pid 36821, restarted onto `e2ae5d6c5`'s code (the pid 73698
named above was the pre-fix run). It is the only one and notifies `lr-fv2-w5b2-38`.

### Cutoff moved again: watchdog restarts under host load (2026-10-01 06:50:36Z)

No cohort opened between 01:02:56Z and this restart, so the count was still 0 when it started over.
The reconciler's watchdog (`recon/watchdog.log`) killed pid 79972 at 06:46:04Z (`progress=8312
unchanged 185s`), then its successor 38808 at 06:50:35Z (`progress=0 unchanged 194s`). It paged
`crash loop — holder pid changed 2 times within 10 min`. `reconciler.err` stayed empty. The host's
load average read `174 427 354` at 06:55Z, which explains a stall without any code defect. The
holder is now pid 92597, started 06:50:36Z: the last row of `recon/restarts.jsonl`
(t=1790837436.80), confirmed by `launchctl print` (running, pid 92597, runs 5), with its progress
counter advancing (42 at 06:55Z). **This start time is the cutoff now.** Only cohorts whose limit
began after 06:50:36Z count toward the 2.

The planner code it runs: the shared checkout at `cb7e1e4f6`, whose `scripts/limit-recover/` is
byte-identical to origin/main `85c2d837e`. The one `lr_recon` change since the previous cutoff is
`476712b2f` (`settle.py`: a recycle held as `unreachable` maps to `HOLD-COMPOSER`). It affects
recycle actuation only, and the previous holder never loaded it (`lr_recon` has no hot reload).

**The watchdog fix did not move the cutoff.** W7d's `b6a352f08` went live at 07:51Z: the watchdog
now kills only a reconciler whose CPU is frozen (under 0.5 s in 180 s) and gives a first pass 600 s of
grace. It changed the watchdog, not the reconciler, so pid 92597 kept running and the cutoff stays
06:50:36Z (re-read at 20:16Z, after the kitty restart below).

### The kitty restart (2026-10-01 18:29Z), and a new comparer rule

**What the restart changed.** It renumbered every pane. This pane went from 38 to 28, so the watcher's
`--notify lr-fv2-w5b2-38` named an address that no longer existed, and it drops send errors, so four
cohort mails went nowhere. The watcher process itself survived and archived all four. It now runs as
pid 68472 with `--notify` set to this session's id (`f8b54aee-…`), which renumbering cannot change.
The reconciler did not restart. Three of the four cohorts, `next-none-0`, `next3-none-0` and
`next4-none-0`, opened at 18:29:38Z, the restart itself: their members are `idle` panes with no limit
scope, being re-recovered. They are not limit cohorts and do not count. The fourth,
`next4-7d-1791104400` (opened 19:59:05Z, a weekly limit on next4), is the first cohort to count.

**The rule (lead ruling, claude-infrastructure-20, 2026-10-01, conviction 91%; `4f8e99aac`).** A
provisional compare of that cohort failed on one census miss, 9c4a2015. It was a dead session in
`/private/tmp/sd-c5-pT3ezY` on next4: legacy found it only through a stop-failure marker, both of its
legacy runs found no pane (`PANE→ -`) and moved nothing (`HELD:unknown`), no process ran in its
directory, and the daemon logged `NOT_NEEDED dead-before-claim`. A found sid is now **not owed**
only when every legacy run for it in the window found no pane and moved nothing, *and* the daemon
judged it dead before any claim. The legacy evidence decides and the daemon only confirms, so the
comparer never clears the reconciler on the reconciler's own word. It is printed as its own count
(`census misses 0 · not owed 1 (9c4a2015)`) and never dropped, so a regression that marks a live
session dead still shows. Three bats pins in `tests/lr-recon-shadow.bats` cover the not-owed case and
both ways it must stay a miss.

**Known minor, for the `lr_recon` owner (no fix needed for cutover).** The daemon re-emits the same
`stale NOT_NEEDED dead-before-claim` event for 9c4a2015 every 6-10 s (32 rows by 20:22Z), which
grows `recon/events.jsonl` (5 MB) with no new information.

### First counted cohort: FAIL, and the defect it found (2026-10-01 21:20-22:35Z)

**Verdict: `next4-7d-1791104400` FAILS** (lead ruling, claude-infrastructure-20). It is the cohort
that found the defect below. Compared at 22:35Z on the cutoff above (pid 92597; the reconciler
ran the shared checkout, whose `scripts/limit-recover/` matched origin/main), with the comparer as
of the commit that adds this section:

```
SHADOW next4-7d-1791104400: members 13 · legacy found 15 · census misses 0 · not owed 1 (9c4a2015) · placements feasible 0/0 · phase agree 4/8 (false-RECOVERED resolved 0, plan differed 0) · legacy-corrected 2: 89bdedfa,8e18da3f → FAIL
  3a06361f legacy RECOVERED→next4 watcher=nudge:ENGAGED · recon PRE-MOVE/LAUNCHER-ROOTED via=None · DISAGREE
  46bc0436 legacy RECOVERED→next4 watcher=nudge:ENGAGED · recon PRE-MOVE/LAUNCHER-ROOTED via=None · DISAGREE
```

**The defect (`lr_recon`, a cutover blocker; the lead's W7f fixes it).** Legacy nudged 3a06361f
and 46bc0436 in place on next4 at 21:28:40Z and 21:28:35Z (`nudge-in-place/RECOVERED`, "a fresh
assistant turn followed within 20s"). Their transcripts under `~/.claude-quaternary` hold real turns
at 21:29:43Z and 21:30:04Z, and `recon/facts/next4.7d.json` reads `contradicted: true`. The recon
still held both as `PRE-MOVE/LAUNCHER-ROOTED` and logged `RECON-DEFECT PRE-MOVE/LAUNCHER-ROOTED` for
them on every pass (1,238 such events since 07:36Z across 19 sids; the cohort's status reads
`unowned-non-terminal 4`). In act mode a launcher-rooted pane maps to R (`census.py:163`), so the
daemon would relaunch sessions that are answering on an account whose limit no longer holds. Lead
ruling: a session observed answering after a contradicted limit must never be held for R. The fix
restarts the reconciler, so **the cutoff moves to that restart** and the count starts again from 0.
`next-7d-1791086400` (opened 20:52:23Z) therefore never counts either. At 22:35Z it compared clean
(`census misses 0 · not owed 0 · placements feasible 0/0 · phase agree 1/1 · legacy-corrected 0 →
PASS`; f8b54aee agreed, 492a787a legacy-parked with no routable target), but it had not settled.

**Three comparer rules this cohort forced** (lead rulings, each 90-92%; pinned in
`tests/lr-recon-shadow.bats`, each positive pin red on the comparer before it). All three are in
`tests/rig/shadow_lib.py`, which judges and never changes what the daemon does.

- **`parked` moved nothing** (`db67ec01a`). 9c4a2015's later legacy runs at 20:35Z and 20:57Z wrote
  `parked` ("no routable target", no pane, no target) and flipped it back to a census miss. A park
  now counts with the HELD/NOTMOVED verdicts, but only with PANE `-` and ACCT_AFTER `-`. A park that
  saw a pane or named a target stays a miss.
- **Legacy-corrected engagement** (`db67ec01a`). The legacy watcher logged `recycle-dead` for
  89bdedfa and 8e18da3f at 20:36:46Z and 20:37:15Z ("no assistant turn within 180s"), yet their
  transcripts on next3 hold turns at 20:33:07Z and 20:33:49Z, and both processes were alive. The
  recon's `engaged-elsewhere` was right; the comparer had charged the watcher's false negative to
  it. The legacy truth is now corrected to ENGAGED only when the sid's transcript under the
  account the recon says it moved to holds a turn after the legacy relaunch, *and* a `claude
  --resume <sid>` process is live at compare time or was at an archive pass after the relaunch
  (the watcher now writes `live.json` per cohort). The comparer prints it as `legacy-corrected N`,
  outside the agree count. The watcher's false negative is legacy-side and the lead's to route.
- **Nudge truth** (the commit that adds this section). A nudge-in-place writes no watcher row, so
  the comparer read 3a06361f and 46bc0436 as false-RECOVERED. That "agreed" with the recon's
  PRE-MOVE and printed `phase agree 6/8 … → PASS` over a real defect. A nudge row is now legacy
  ENGAGED only when the sid's transcript under ACCT_AFTER's config dir holds an assistant turn
  after the row's timestamp. This makes the gate stricter.

**What the shadow cannot test: act-mode actuation of launcher-rooted panes.** W7f landed
(`4365d93e9`, `2f6993024`, `3a241ed58`, `8cd2daca8`). The lead then found a second defect the
shadow could not see: in act mode the reconciler never planned R for a launcher-rooted limited
session. In observe mode legacy does all the moving, so a compare can only check that the recon
*judges* such a session the way legacy's outcome says. It never sees whether the recon would
*actuate* it. That is why `placements feasible 0/0` held for every launcher-rooted member above.
W7g fixes it, and the reconciler restart is held so one restart loads W7f and W7g together. That
restart is the next cutoff. A PASS on this gate therefore says nothing about act-mode actuation for
launcher-rooted panes; act mode has to be tested separately.

**Watcher.** Since 22:36Z it is pid 92452, on the comparer code above (it writes `live.json`), the
only one, notifying the shadow session by id (`4079f342-…`), log `shadow-archive/watch-w5b2.log`.
Its predecessor pid 3437 (21:22Z, the old code) wrote no `live.json`, so the archive-time arm has
evidence only from 22:36Z on.

### Cutoff moved: the reconciler restarted onto W7f and W7g (2026-10-02 01:21:36Z)

The lead restarted the reconciler onto W7f and W7g (`2f6993024` .. `7d92d8d1e`): pid 28574, started
01:21:36Z, the last row of `recon/restarts.jsonl` (t=1790904115.07), confirmed by `launchctl print`
(running, pid 28574, runs 6). The shared checkout is at `62d1960cd`, and its `scripts/limit-recover/`
is byte-identical to origin/main. **This start time is the cutoff now, and the count is 0.** Only
cohorts whose limit began after 01:21:36Z count toward the 2. Every cohort open at the restart
(`next-7d-1791086400`, `next4-7d-1791104400`, `next2-7d-1791025200` and the three `*-none-0`) began
before it and is evidence only.

W7e (`75642a817`, live 00:40Z) also changed the legacy side: the watcher no longer logs
`recycle-dead` for a cross-account relaunch that answers. The legacy-corrected rule above should
therefore fire rarely from here on; when it does, that is worth a look.

**Cohort 1 of 2: `next3-7d-1791288000` PASSES** (opened 01:50:20Z, 29 min after the cutoff; settled
02:27Z with every member terminal CLOSED). Compared at 02:27Z on pid 28574 (shared checkout
`62d1960cd`, `scripts/limit-recover/` identical to origin/main), comparer at `a3ba677bc`:

```
SHADOW next3-7d-1791288000: members 3 · legacy found 3 · census misses 0 · not owed 0 · placements feasible 0/0 · phase agree 3/3 (false-RECOVERED resolved 0, plan differed 0) · legacy-corrected 0 → PASS
  0962ca47 legacy RECOVERED→next4 watcher=ENGAGED · recon ENGAGED/None via=ENGAGED · agree
  1aa4e1c1 legacy RECOVERED→next3 watcher=nudge:ENGAGED · recon PRE-MOVE/None via=IN-PLACE · agree
  4079f342 legacy RECOVERED→next3 watcher=nudge:ENGAGED · recon PRE-MOVE/None via=IN-PLACE · agree
```

- **W7f, observed live.** Two members (4079f342, the shadow session itself, and 1aa4e1c1) were
  nudged in place on next3 after its limit was contradicted. Within about two minutes the recon
  logged `engaged-in-place` ("answered in place on next3 after its limit: nothing to move") and
  closed both CLOSED via `IN-PLACE`, with no R held. This is the shape that failed
  `next4-7d-1791104400`.
- **Comparer vocabulary** (`a3ba677bc`). W7f's in-place close leaves the phase PRE-MOVE and sets
  `close.via = IN-PLACE`. The comparer only knew ENGAGED and MOVED, so its first provisional compare
  printed DISAGREE on both. It now reads `IN-PLACE` as engaged, pinned in
  `tests/lr-recon-shadow.bats`. This reads the recon's own terminal verdict; it changes no judgment.
- **Check 1 is vacuous here** (`placements feasible 0/0`). Legacy recovered every member before the
  recon planned a target, so this cohort says nothing about placement feasibility. That is the
  observe-mode limit recorded above.

**Not countable: `next3-auth-0`** (opened 08:18Z). It is an auth-scope cohort on next3, not a
usage limit. All 4 members are `kind: idle` panes (06ef69f7, 705115e9, 75277dd9 and the dead
9c4a2015), held `HOLD:iterm` ("relaunch this session by hand"). `recon/facts/next3.auth.json` reads
`contradicted: true`, and next3's login read `ok` at 17:20Z. Legacy found none of them, so its
compare (`legacy found 0 · placements feasible 0/0 · phase agree 0/0 → PASS`) judged nothing. Like
the three `*-none-0` cohorts above, it does not count. The count stays at 1 of 2.

### Second real limit: next4's 5h cap FAILS, and three things it showed (2026-10-04 07:56-09:40Z)

next4 hit its 5-hour limit on 2026-10-04 (`recon/facts/next4.5h.json`: observed 07:56:48Z,
`resets_at` 1791106800 = 09:40Z, first sid b8778ec0). It began after the cutoff and it is a real
usage limit, so it is the second candidate cohort. **It does not pass, and the count stays at 1 of
2.** Reconciler pid 28574 (no restart row since 01:21:36Z Oct 2; shared checkout `1bcbd636e`,
`scripts/limit-recover/` identical to origin/main, and `lr_recon/` unchanged since `62d1960cd`),
comparer at `a3ba677bc`. Compared at 09:08Z, 10:04Z and hourly to 14:46Z with the same line:

```
SHADOW next4-5h-1791106800: members 1 · legacy found 13 · census misses 1 (d425afab) · not owed 0 · placements feasible 1/1 · phase agree 0/0 (false-RECOVERED resolved 1, plan differed 0) · legacy-corrected 0 → FAIL
  filed in another cohort (not a miss): 34ee838d, 42097363, 7b1dea4d, 840ca76c, 884aa5bc, b671b47e, b8778ec0, bc218f5d, c5cd1b06, ca3b517d, d8964eb2 → next4-7d-1791104400
  762a6daa planned next4→next2 feasible
  d425afab legacy RECOVERED→next2 (watcher NONE) · no recon record
```

The lead has not ruled on any of this: its own session is the cohort's one member and has been
stopped at the limit since 09:07:56Z (item 3). Evidence, for the lead to judge:

1. **A new 5h limit was filed under the old 7d cohort.** The 14 sessions the reconciler detected on
   next4 between 06:11Z and 08:48Z (among them 7b1dea4d, this shadow session, and 34ee838d) all got
   `scope: 7d` and `cohort_id: next4-7d-1791104400`, the cohort opened on Oct 1 before the cutoff
   (`opened_at` 1790884745, 37 members, still not closed). Its reset, 1791104400 = 09:00Z, had not
   passed, so the Oct 1 7d fact still covered next4 and the 5h limit was read as that one. The 5h
   cohort `next4-5h-1791106800` opened only at 09:08:00Z, after the 7d fact expired, with one member.
   In act mode a waiting member would have been scheduled to wake at 09:00Z, 40 minutes before the
   real reset. The comparer cannot separate the two events inside the 7d cohort: on it, it prints
   `members 37 · legacy found 27 · census misses 1 (d425afab) · placements feasible 7/7 · phase agree
   16/19 · legacy-corrected 1: 7b1dea4d → FAIL`, and the two DISAGREE rows traced (40ebc527,
   c28362b6) are Oct 1 members. Of the 14 detected today, 12 closed ENGAGED via ENGAGED and 2 are
   PRE-MOVE/HOLD:iterm.
2. **Census miss: d425afab.** `recon/events.jsonl` has five `stale` rows for it at 07:57-07:59Z
   ("NOT_NEEDED no longer LIMITED — its last assistant record is not the limit") with an empty
   `record_id`, and `recon/sessions/` has no record. Legacy bundled it at 08:55:35Z and moved it to
   next2 (its transcript is now under `.claude-secondary`, worktree `wt-cc-142226-72029`). Whether
   it was limited again after 07:59Z, or legacy moved a session that was not limited, is not settled
   here.
3. **Draft hold: 762a6daa, the lead (pane 20).** Its last assistant record is the limit message at
   09:07:56.312Z. Legacy's handoff precheck held it both times (bundles 090810Z and 092157Z:
   `focused=no hid_idle_s=5567 verdict=HELD:draft`), because its input box holds unsent text. The
   recon record reads `PRE-MOVE/PLANNED`, target next2, with `seen` = PRE-MOVE, DETECTED, WAIT_SLOT,
   PLANNED and the cohort's `dod` line counting `HOLD named 0/1 (draft 0, bgwork 0)`: it planned a
   move where legacy saw a draft. The pane was still stopped at 14:46Z, five hours after the reset;
   it is filed for the operator as backlog `b9fdad06b82b`.

Events the reconciler logged against the 7d cohort that day: `RECON-DEFECT TRANSPLANTED/None` 11
times and `RECON-DEFECT RELAUNCHED/UNPROMPTED` 3 times (two of them 34ee838d and 7b1dea4d at
09:06Z, each followed by `engaged-elsewhere … moved there by another recovery path`).

**Lead ruling (2026-10-04 15:55Z, 90%).** The FAIL stands and the count stays at 1 of 2 for now.
Items 1 and 3 are `lr_recon` defects that block the cutover: in item 1 the census takes the scope
of the covering fact over the session's own death record; in item 3 the death path never reads the
composer, so a draft is held only on the idle path, where the design holds a draft on every move.
Both go to wave W7h (`briefs/fire-w7h-scope-draft-stale.txt`), which also settles item 2 (whether
d425afab was a real miss or legacy moving a healthy session). **When W7h lands, the reconciler is
restarted, the cutoff moves to that restart, and the count resets to 0 of 2**, because cohort 1
ran on pre-fix code. Until then every cohort is evidence only. Pane 20 is live again and
`b9fdad06b82b` is closed.

## Census step

Operator step `f0df9145b73a` (the live observe census) was closed with the launchd daemon's own pass:
`census: 21 claude procs · 17 panes on 1 kitty sockets · 44 sessions (10 bg-work, 0 iterm) ·
degraded: none`, mode observe, 0 actuations.
