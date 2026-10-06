# q8 — what the suites pin, how they fake sessions, how they run, and replay controls

Slot scope: tests and controls only. Tags: MEASURED (I ran it), READ (source or record), INFERRED.
Repo paths are relative to `/Users/chrisren/Development/.worktrees/lr-zero-memory`; record paths to
`/Users/chrisren/.reso/limit-recover` (written `$R`).

## Answer

- The suites pin every cap **as an env-set value, never as its default**, and pin **no memory gate in
  the move lane at all**: the shared fixture exports `LR_MOVE_KERNEL_CHECK=off`
  (`tests/helpers/lr-move-fixture.sh:29`). Raising the move width, the recover pool width or deleting
  the move lane's kernel-safety read turns 0 tests red. Exactly one default is pinned: the `--one`
  lane's 2 (`tests/lr-fleet.bats:2008-2010`).
- In the one multi-session record, the memory read admitted 8 of 8 probes at 32.98-34.75 GB
  reclaimable (floor 4 GB) and 4.33-4.50 % segments (ceiling 90 %); the delay was the slot width:
  3 of 7 workers waited 166.8-167.3 s for a slot. Memory is not the binding term in that record.
- Two defects sit in the same record and are invisible to the suites because the suites run under
  brew bash 5.3 while launchd runs `/bin/bash` 3.2: the batch summary and its mail said "no rows"
  for 7 MOVED sessions.

## 1. What pins what (file:line)

| Lane / bound | Source (default) | Assertions that go red if the cap is raised or removed | Not pinned |
|---|---|---|---|
| Move lane slot width | `lr-move-lib.sh:179,183` (4); `lr-move-worker.sh:50` reads `plan.slots`, else `LR_MOVE_SLOTS:-4`; wait loop `:120-127` | Semaphore removed: `lr-move-concurrency.bats:74` (`max <= 4`, N=15 W=4 set at `:52`); `lr-move-worker.bats:69` (slot count `= 1` while the actuator runs); `lr-move-worker.bats:105-107` (full lane -> `NOTMOVED capacity:*`, never invoked). Width reached: `lr-move-concurrency.bats:75` (`max >= 2`) | The default 4. `mvf_plan` always writes `.slots` (`lr-move-fixture.sh:72`); a real plan has no `.slots` key unless `--slots` is passed (`bin/cc-lr:1316`; MEASURED `jq 'del(.rows)' $R/move/20261006T060534Z-next3-next2-64630/plan.json` shows none). `--slots` is used by 0 tests (MEASURED `grep -rn -- '--slots' tests/*.bats tests/helpers \| wc -l` = 0) |
| Move lane kernel-safety read | `lr-move-worker.sh:128-135`, `lr-move-batch.sh:151-155` (on) | None. `lr-move-fixture.sh:29` sets `LR_MOVE_KERNEL_CHECK=off` for all three move suites; it is the only reference to that variable under `tests/` (MEASURED grep) | The whole gate in this lane, both the admit and the refuse arm |
| The probe itself (`lr_capacity_probe_corrected`, `lr-lib.sh:410-440`, swap ceiling 90 % at `:436`) | — | `capacity-admit-coverage.bats:563` (60.5 % admits), `:565` (95 % refuses, rc 9), `:568` (explicit 50 % wins), `:584-588` (self not counted), `:495-534` (probe and launcher enable the same terms) | — |
| Recover pool width | `lr-fleet.sh:1362-1363` (2) | Pool made serial: `lr-fleet.bats:1762` (`overlapped HF` at width 2). Cap ignored: `:1771` (`no_overlap HF` at width 1). Admit lock removed: `:1753` (`no_overlap RANK`) | The default 2. `lr-fleet.bats:22` exports `LR_RECOVER_MAX_CONCURRENT=1` suite-wide; `:1898,:1905` (junk, 0) run one session, so the fallback value is not observed. No other suite drives the real pool (MEASURED grep) |
| Recover lane capacity wait | `lr-fleet.sh:546-578` (120 s, 20 s interval) | None. `lr-fleet.bats:12` pins `CC_ADMIT_GATE=off`; 0 matches for `PARKED on capacity`, `capacity not admitted`, `LR_FLEET_CAP_WAIT_S` under `tests/` (MEASURED grep). Only the phantom subtraction is tested (`lr-fleet.bats:657-671`) | The wait, the park and the reason row |
| `--one` lane cap | `lr-fleet.sh:1381-1382` (2), wait 900 s in 10 s steps `:1386` | **Default raised above 2**: `lr-fleet.bats:2008` (rc 1), `:2009` (actuator not run), `:2010` (`concurrency cap (2 live recoveries`). Helper fills exactly slot-1 and slot-2 (`:2000-2002`) | — |
| Poller dispatch caps | `lr-reset-poller.sh:1113` (4 per account per tick), `:403` (4 per run), `:410` (1 per worktree) | `lr-reset-poller-requests.bats:508` (4 of 6 dispatched), `:511` (2 unspent), `:512` (log text with `4/account/tick` and `ETA ~15 min`), `:530`; `lr-reset-poller.bats:270-272`; `lr-reset-poller-consolidate.bats:68` | — |
| Serial drainer (switch, upgrade, marker set-aside) | `lr-upgrade.sh:2347-2357` (one lock dir), gap `LRU_GAP_S` 10 s `:88,:2395` | Lock removed: `lr-upgrade.bats:345-346` (no second drainer), `:363` (lock released, queue empty). Gate before exit: `:404-409`. Queueing: `lr-switch-driver.bats:230` (C1), `:539` (F4) | The 10 s gap (every suite sets `LRU_GAP_S=0`: `lr-upgrade.bats:48`, `lr-upgrade-custody.bats:30`, `lr-switch-driver.bats:39`). No ordering log across two driven requests: C5's two requests both fail re-judgement, so the actuator stub never runs (`lr-upgrade.bats:349-364`) |
| `cc-lr` verbs | `bin/cc-lr:2203-2225` | Usage and unknown-verb line: `cc-lr-front.bats:853-862`, `cc-lr-request.bats:238-243`. `plan`: `lr-move-plan.bats:92-101` (one row and disposition each, counts line, the `recover --limited` hint), `:107-109` (writes nothing). `move`: `:123-128` (dry run), `:133-144` (plan, one 0600 intent, one request, kick without `-k`), `:221-229` (driver `switch` runs the move lane). `recover --limited`: `cc-lr-front.bats:971-1089` (fires only that account, queues idle sessions when capped) | `cc-lr move` exit 0. Every non-dry `move --from` in the suites passes `--wait 0` and returns before `bin/cc-lr:1369-1376` (MEASURED grep) |

Suite sizes (MEASURED `bats --count tests/<f>.bats`): lr-move-verdict 16, lr-move-worker 14,
lr-move-concurrency 13, lr-move-plan 15, lr-fleet 138, lr-upgrade 54, lr-switch-driver 39, cc-lr 17,
cc-lr-front 72, cc-lr-request 18, cc-limited 24, lr-reset-poller 38, lr-reset-poller-requests 44,
capacity-admit-coverage 20, lr-recon-fence-callsites-fleet 7, lr-drill-selftest 62,
lr-autorecover-drill 5.

## 2. How the suites fake panes and sessions

| Family | Used by | A "session" is | Stubs and seams | Reuse note |
|---|---|---|---|---|
| Live-process fixture `tests/helpers/lr-move-fixture.sh` | lr-move-verdict, -worker, -concurrency | a real `sleep 900` + registry row + one-line transcript + a file standing in for `ps -E` (`mvf_session :38-48`) | `mvf_setup :13-30` (HOME, `LR_STATE_DIR`, `CC_REGISTRY_DIR`, `LR_MOVE_ENV_DIR`, `CC_RESUME_DEBT_DIR` all under `$BATS_TEST_TMPDIR`; poll periods 0.2-1 s); `mvf_plan :59-76` (plan + intents); `mvf_handoff_stub :80-114` records `argv.log`, `env.log`, `typers.log`, `slots.log` (live slot count), modes move, hold, strand, tomb, boot time `STUB_BOOT_S` | Best base for a replay control. Turn the gate on per test with `LR_MOVE_KERNEL_CHECK=on`, unset `CC_ADMIT_GATE`, and pin readings with `CC_ADMIT_SEGMENT_OVERRIDE`, `CC_ADMIT_HEADROOM_OVERRIDE`, `CC_ADMIT_IDL`, `CC_ADMIT_STATE_DIR`, `CC_BEAT_DIR` (the seams `capacity-admit-coverage.bats:556-561` uses) |
| Snapshot fixture | lr-upgrade, lr-switch-driver, lr-move-plan | registry row + a line in a `ps` snapshot FILE + transcript (`sess`, `lr-switch-driver.bats:47-60`, `lr-move-plan.bats:63-74`) | `LRU_REG_DIR`, `LRU_PS_SNAPSHOT`, `LRU_CFG_ROOT`, `LRU_TUI_LIB` (composer, type, submit stub library, `lr-switch-driver.bats:65-99`), `LRU_IT2_BIN`, `LRU_SA_PROBE`, `LRU_NOTIFY_BIN`, a `launchctl` recorder on PATH, `CC_ACCOUNTS_BIN` with `RANK_MODE` | No live process at all; right for the two-command surface (list, plan, queue) |
| Fleet fixture | lr-fleet | transcript ending in a limit error (`blocked_tx :126-131`) + registry row (`row :132`) + marker row (`mark :104-108`) | `LR_HANDOFF_BIN` recorder with `LRH_SLEEP` and the `HF-START/HF-END` ordering log (`:54-71`), `acct_stub` with `ACC_RANK_SLEEP` (`:1635-1649`), `overlapped` / `no_overlap` (`:1664-1678`) | Ordering logs, never wall clocks. `lr_resume_procs` reads the real process table, so sids must be unique per test (`:40-51`: 16 of 65 failed when the file ran twice at once) |
| Poller fixture | lr-reset-poller*, lr-autorecover-drill | request JSON + transcript | `LR_FLEET_BIN` recorder reproducing the `--detach` contract (`lr-autorecover-drill.bats:31-37`), `osascript` stub, `LR_POLLER_NO_CENSUS=1` | Right for dispatch-rate controls |
| Function extraction | handoff-recycle-* | registry row + transcript | `eval "$(sed -n '/^fn() {/,/^}/p' …)"`, fake HOME with `it2` and `cc-notify` recorders (`handoff-recycle-engagement.bats:44-63`) | Predicate tests only |

`tests/lr-drill.sh` is the only path that types into real panes and is operator-only by
construction (`:13-20`); `$R/drill/` holds one empty run directory and a 124-byte `live.log`
(MEASURED `ls`), so it offers no record to replay.

## 3. How suites are run here

- `bats` on PATH is `~/.claude/bin/bats`, a symlink to `claude-infrastructure/bin/cc-bats`; the real
  runner is bats-core 1.13.0 (MEASURED `which -a bats`, `ls -la`, `ps`).
- `cc-bats` clamps to the utility QoS band (`bin/cc-bats:750`) and **sheds, never waits**: it
  refuses with rc 75 and empty stdout when live roots >= `CC_BATS_MAX_ROOTS` (2, `:465`) AND 1-min
  load per core >= 2.0 (`:466`). `--count` executes nothing and skips admission (`:484`).
- MEASURED, `bats tests/lr-move-verdict.bats` (the one suite run):
  attempt 1 at 2 live roots and load 90-115 on 10 CPUs: `rc=75`, 0 s, no plan line, stderr
  `cc-bats: REFUSED — 2 concurrent bats execution root(s) … DEFERRAL, not a test result`.
  Attempt 2, same 2 roots, load 18.1 (1.8 per core): `rc=0`, 11 s, plan line `1..16`, `ok` 16,
  `not ok` 0, skip 0.
- Convention (READ `.claude/rules/agent-operating-lessons.md:49`, `-situational.md:254`): assert the
  `1..N` line AND that `ok` + `not ok` equals N. A refusal has zero `not ok`; `--jobs` without GNU
  parallel prints the plan and runs 0 tests. `command -v parallel` is empty here (MEASURED): run serially.
- Cost note (READ `lr-move-concurrency.bats:47-50`): 15 workers run once; the other 12 cases use
  N=4, W=2, because 13 x 15 workers took 25 minutes on a loaded box.

## 4. Replay controls

Each is a new bats case on an existing fixture. "Pre-fix" must be observed red-to-green: run on the
unfixed tree first and keep the output.

| # | Record | What it replays | Pre-fix behaviour it must reproduce | The fix flips it to |
|---|---|---|---|---|
| RC1 | `$R/move/20261006T060534Z-next3-next2-64630/` (`plan.json`, 7 x `<sid>.events.jsonl`) | The 7-row batch at the default width, on the live-process fixture: the real plan shape (no `.slots`), stub durations taken from the record (actuate to actuated 105.6-110.7 s wave 1, 16.1-16.6 s wave 2; actuated to proof-first 56.8-190.9 s), scaled down | Waves of 4 then 3: `slots.log` max = 4; exactly 3 workers have a `slot-wait`-to-`slot` gap equal to wave 1's time to first proof (record: 166.8, 167.2, 167.3 s; MEASURED from events); batch worker wall = last result at 386.7 s | With no slot wait, each worker's own duration stands: last result about 220 s (ESTIMATED: result time minus slot wait per worker; assumes durations do not grow at width 7, which the record cannot show) |
| RC2 | Same batch: 8 x `*.capacity.log`, all 0 bytes (MEASURED `ls -la`); corroborated by 8 rows in `~/.claude/autonomy/idl.jsonl` for callers `lr-move-batch` and `lr-move-worker`. Positive arm: `$R/fleet/one-20261002T043358Z-fe370fb2/detached.log` | The kernel-safety read with the gate ON and the recorded readings pinned: 33.16 GB / 4.50 % at admit, 32.98-34.75 GB / 4.33-4.50 % per worker | Admits 8 of 8, adds 0 s, writes 8 `admit` rows with `terms: headroom,segments`. Positive arm: 54.27 % segments is refused under `CC_ADMIT_MAX_SEGMENT_PCT=50` (the only memory-term wait in the fleet logs, one 20 s step) and admitted at the swap ceiling 90; 95 % yields `NOTMOVED capacity:*` with the actuator never invoked | Whatever replaces N+1 probes per batch must keep the positive arm red-capable. This control is what makes removing or moving the read testable; today nothing does |
| RC3 | `$R/fleet/one-20261006T060347Z-e131c8d2/detached.log` line 1, with siblings `one-20261006T060346Z-4ad354fc`, `one-20261006T060347Z-7913752f`; `poller.log` 06:03:46-47Z | Three `--one` drivers dispatched within 1 s against the default cap, on the fleet fixture with `LRH_SLEEP` | The third prints `the --one lane is at its cap (2 live recoveries); waiting up to 900s for a slot` and starts only after a sibling ends, on a 10 s step (record: its rank stamp is 25 s after dispatch against 9 s and 12 s for the siblings; ESTIMATED from 1 s timestamps in `rank.timing` and `poller.log`). 38 runs on record carry this line (MEASURED `grep -l`: 19 on 10-01, 3 on 10-02, 15 on 10-04, 1 on 10-06) | All three overlap in the `HF-START/HF-END` log with no cap line; `lr-fleet.bats:2004-2012` must be re-pinned in the same change |
| RC4 | `$R/fleet/one-20261001T202119Z-bb231dfd/detached.log` (lines 1, 4, 6) and the same-tick runs `…202117Z-3a06361f`, `…202117Z-68691067`, `…202119Z-dcbd2f8e` | The bound behind the cap: the active-turn term with admission tokens counted, stubbed through `cc_sp_active` and `cc_capacity_tokens_inflight` as `capacity-admit-coverage.bats:577-580` does | Probe refuses with `4 sessions mid-turn + 3 admission token(s) in flight + 1 > active ceiling 8 − operator reserve 1 = 7`, waits 20 s per step; the 4 runs ended 20:25:00, 20:28:24, 20:32:33, 20:34:43Z (1 RECOVERED, 3 FAILED on `lr-handoff rc=6` holds), 13.4 min for 4 sessions; 2 of the 4 also waited at the cap of 2 first | A wider recover lane must show its own in-flight tokens do not refuse its own cohort. Without this control, raising the cap of 2 moves the wait into `lf_capacity_wait`, which has no test |
| RC5 | `$R/move/20261006T060534Z-next3-next2-64630/batch.log` and `summary.json` | The batch runner executed with `/bin/bash` explicitly (as `lr-reset-poller.sh:292` does), 7 MOVED rows on disk | `batch.log` holds `command substitution: line 84: syntax error near unexpected token 'newline'`; `summary.json` has `"verdicts":"none"`; the requester mail reads `done: no rows` | `verdicts` = `MOVED=7`; no syntax error in `batch.log` |

## 5. Defects the record shows and the suites cannot see

- `lr-move-batch.sh:80-83` puts `case … in a|b) …` inside `$( )`. bash 3.2 ends the substitution at
  the pattern's `)`. MEASURED: `/bin/bash -c 'x="$(for f in a.json plan.json; do case "$f" in plan.json|admit.json) continue ;; esac; echo "$f"; done)"'`
  prints the same syntax error on 3.2.57; the form `(plan.json|admit.json)` returns `MOVED=2` there.
- Why green today: `lr-move-concurrency.bats:64` runs `bash …` and PATH bash is 5.3.15 (MEASURED);
  no case reads `summary.json .verdicts` (MEASURED grep); `/bin/bash -n` and
  `scripts/bash32-parse-lint.sh` both pass the file (MEASURED rc 0).
- Same shape at `bin/cc-lr:1370-1373` (`#!/usr/bin/env bash`). MEASURED under `/bin/bash`: the count
  becomes text and `[ "$v" -eq 0 ]` fails, so `cc-lr move` would exit 1 after a fully moved batch
  whenever PATH resolves to 3.2. That path has no test (section 1, last row).

## 6. Alternatives considered

- A replay from the serial drainer (`$R/upgrade-drain.log:825-861`, 12 requests: 3 SWITCHED,
  7 NOTMOVED, 2 parked). Rejected as a control: the log has no timestamps and 5 of the 10 result
  files were overwritten by later drains (MEASURED `ls -lT $R/results/switch-*.json`), so the
  pre-fix timeline cannot be stated. Intact mtimes span 12:15:29 to 12:42:00 local, about 2-4 min
  per subject (132 s, 173 s, then 996 s for 4 subjects, then 290 s for 2).
- A mutation run (delete the kernel read, run the move suites) to prove "0 tests red". Not run: one
  suite was allowed, and the fixture line makes the block unreachable, so the result is deductive.
- Wall-clock assertions. Rejected for every control: the suites use ordering logs and slot counts
  because timing cases failed under load (`lr-fleet.bats:57-59`).
- Waiving the bats admission bound (`CC_BATS_MAX_ROOTS=0`). Not used: it writes a waiver under
  `~/.claude/state`; I waited for load to fall instead.

## 7. Uncertainties

- RC1's 220 s is an estimate. Wave 1 spent 105-111 s inside `lr-handoff` against 16 s for wave 2 and
  the record does not say why; if that cost rises with width, a wider lane saves less.
- RC5's pre-fix reproduction on the fixture is INFERRED from the record plus the reduced `/bin/bash`
  reproduction; I did not run the batch runner under `/bin/bash`.
- "0 tests red" for the recover pool default covers `lr-fleet.bats` and
  `lr-recon-fence-callsites-fleet.bats`, the only suites that run the real pool; the roughly 30
  older cases pinned to width 1 were not each read.
- Whether the "no rows" mail was delivered was not checked; only its text is established
  (`lr-move-batch.sh:88,92` and `batch.log`).
- The 38 cap waits are counted, not timed; only the 10-06 one has an estimated length.
