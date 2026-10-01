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

## Census step

Operator step `f0df9145b73a` (the live observe census) was closed with the launchd daemon's own pass:
`census: 21 claude procs · 17 panes on 1 kitty sockets · 44 sessions (10 bg-work, 0 iterm) ·
degraded: none`, mode observe, 0 actuations.
