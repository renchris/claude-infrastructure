# B2 — poller liveness: the stuck tick and a lease that turns a missing verdict into a delivered FAILED

Checkout: trunk 110ea9a64. Live data: `~/.reso/limit-recover/` read 2026-10-11T03:48Z to 04:28Z. Every number below is labelled MEASURED (with the command) or INFERRED/ESTIMATED (with the method).

## Answer first

- **Why the 03:15Z tick ran 25 min.** The parked loop re-judges **26 parked records** every tick. They passed their reset days ago (between 2026-09-26 and 2026-10-06), and each one stays parked for good as a HUSK. Per record the code forks about 91 processes. That includes 2 full process-table scans (`pgrep -f`) and a scan of all 37 registry files, which runs `basename` and `jq` once per file. The `husk-noted` marker silences the log line for these records, so 20 minutes of work left no log lines at all. MEASURED: 1188 s / 31 records = **38 s per record**.
- **Overruns are routine, and launchd makes them cost double.** Over 7 days, **25 of 792 ticks ran longer than 600 s** (11 longer than 1200 s), and launchd never catches up. The next tick starts 600 s after the overrunning one exits (MEASURED: exit 03:41:09Z, next start 03:51:10Z). The tick has no wall-clock budget, and 4 of its child processes have no timeout. The 03:51Z tick was still running at 37 min when I stopped watching. In that tick I watched the census take about 7 min, `lr-audit.py` 5.25 min, and the transcript `find` 4 min or more.
- **Nothing watches the tick or the runs for progress.** `poller.lock` and the run claims record an owner pid+lstart, but only to prevent overlap. **75 of 76 run claims have a dead holder** and 68 are older than 24 h. 73 of 519 fleet runs never wrote a verdict. 348 of 446 verdicts that were written went "on disk only": the poller-dispatched driver has no requester address, and its fallback, the desk role, is not set.
- **Fix: a lease keyed on the owner's mutex.** Write the lease inside the claim directory (and inside `poller.lock` for the tick itself). An existing, independent 30-second launchd job reaps it: `com.reso.lr-reconciler-watchdog`, running bash 3.2 and importing nothing. When the holder is dead, or alive past its deadline, and no verdict exists, the reaper writes `verdict=FAILED` once. It sends that to a requester address recorded in the request, falling back to `lr-page.sh` and never to the desk role alone.
- **The `poller.launchd.err` errors.** The "bad substitution" lines came from a heredoc inside `<( )` under bash 3.2. It was introduced in 7c7a5261b and fixed in passing by cf7bd5c1a. It killed the census-park arm for about 8.5 days: zero `[census]` parks before 2026-09-29. No code reads that file. This is the second time this exact file has hidden a failure.

---

## B2-1 — The parked loop re-judges permanently stuck HUSK records every tick, at about 91 forks each, and logs nothing while doing it

- **Symptom.** In the 03:15Z tick, `poller.log` went silent from 03:21:21Z ("CONSOLIDATED 26 ready → 0 winner(s)") to 03:41:09Z ("MOVE-BATCH started", written by the EXIT trap `lrp_tick_end`, `lr-reset-poller.sh:239-242`). The operator saw a new bash/basename subshell about once a second.
- **Measured frequency.**
  - Every tick while these records stay parked.
  - MEASURED (bash census of `parked/*.json`): 31 records. **26 are past their reset** (reset dates 2026-09-26 to 2026-10-06), 28 have a `.jsonl.handed-off` and a tombstone, and **31 of 31 carry `.husk-noted`**.
  - Loop wall time 03:21:21 to 03:41:09 = 1188 s, so 38 s per record (MEASURED from poller.log). The brief's estimate was ~48 s.
  - Registry: `ls ~/.claude/cc-registry/*.json | wc -l` = **37**.
- **Root cause.** For each past-reset record, the loop body does this:

  | Step | Location | Processes forked |
  |---|---|---|
  | python3 reads the record's fields | `lr-reset-poller.sh:2140` | 1 |
  | python3 computes the reset epoch | `:2151` | 1 |
  | `husk_file_request` greps the registry | `:2112` | 1 |
  | **`pgrep -f "resume $sid"`, first call** | `:2158` | 1 full process-table scan |
  | **`pgrep -f`, second call** | `:2164` | 1 full process-table scan |
  | `lr_transplant_target` (subshells, sed, cd/pwd, ls) | `:2170` | about 6 |
  | `lrp_unmoved` grep | `:2100` | 1 |
  | `lr_state_current` (tail + jq) | `:2199` | 3 |
  | **`lr_registry_live_rows_in_cfg`** (calls `lr-lib.sh:316-321`, which calls `lr_registry_live_rows` at `lr-lib.sh:280-299`: `$(basename "$f")` at :286 and `$(jq …)` at :287 for each of 37 files) | `:2202-2203` | 76 |

  - The successor never recovers, so the record reaches `husk-noted` and `continue` (`:2211-2215`). Nothing changes, and the next tick pays the same cost again.
  - Total: about 91 forks per record × 26 records ≈ **2,370 forks and 52 process-table scans per tick** (INFERRED by counting from the code).
  - MEASURED in the 03:51Z tick at loadavg 280-314: one `pgrep -f "resume 58d3640a…"` child lived 10 s (04:13:56 to 04:14:06, from ps sampling of the tick's children).
  - MEASURED interactively at loadavg 174: `pgrep -f` took 0.09 s, `ps -axww` 0.37 s, and the 37-file basename+jq scan **1.00 s**.
  - So the 38 s per record seen in the launchd job is roughly 2 pgrep scans at about 10 s each plus about 76 forks at 0.2 s each (ESTIMATED from the sampled pgrep time and the per-record total).
- **Fix (S/M).**
  1. Add a **no-change fast path** at the top of the loop body. When `$PARKED/$sid.husk-noted` is newer than the record's tombstone, its newest `bundle-*`, the newest file in `cc-registry/`, and the target store's `<sid>.jsonl`, skip the record. The test is a handful of `[[ -nt ]]` checks with no fork. The `husk-noted` marker already exists, and is cleared on retire (`:2243`).
  2. Use **per-tick snapshots** for the non-spawning arms:
     - Run `ps -axo pid=,command=` once when the loop starts, and match `--resume $sid` against that text with no fork.
     - Run `jq -r '[input_filename, (.session_id//.sessionId//""), (.pid//""), (.paneUUID//""), (.account//""), (.cwd//"")]|@tsv' cc-registry/*.json` once into `LR_REGISTRY_INDEX`, which `lr_registry_live_rows` reads when it is set. MEASURED: this single jq pass takes 0.02 s.
     - Run `kill -0` only on rows whose sid matches.
     - Keep a fresh `pgrep` right before every nudge (`:2273`) and spawn (`:2362`). A stale snapshot there could mint a duplicate resume, which is the 2026-07-26 incident.
  - **Bats test.** Build a fixture of 30 HUSK parked records and 40 registry files. Put PATH shims for `pgrep`, `jq` and `basename` that append to a counter file. Assert that the loop calls `pgrep` at most once and `jq` at most twice per tick. Then add one record that needs a RESUME and assert its log lines and state are byte-identical to the current code.
- **Single-process rewrite cost (ESTIMATED from the measured single-pass timings).** Fork the python3 helper once for the whole loop: read every record, the registry and one ps snapshot, and emit one action line per record that needs work, which bash then dispatches. That drops about 2,400 forks per tick to about 3 plus the actions. Expected loop time is under 5 s, based on 0.02 s for the jq pass and 0.37 s for `ps` measured interactively. Size **M-L**: the loop has about 10 arms whose order matters (comments at `:2245-2250`). A Python copy would be a second spelling of `lr_transplant_target`, `lr_successor_state` and `lr_husk_state`, the "two spellings of one predicate" defect this file warns about at `:2226-2228`. **Ship the S fix first.**
- **Conviction:** 72. The live 03:51Z tick did not reach the parked loop while I was watching, so the per-record split between pgrep and the registry scan is inferred, not sampled.
- **Receipt.**
  - `grep -n 'CONSOLIDATED\|MOVE-BATCH' poller.log` gives 03:21:21Z and 03:41:09Z.
  - The parked census (bash -c loop over `parked/*.json`) gave `reset past 26, future 5; ho=1 28; husk-noted 31`.
  - `/usr/bin/time -p bash -c 'for f in ~/.claude/cc-registry/*.json; do case "$(basename "$f")" …; jq …; done'` printed `real 1.00`.

## B2-2 — The tick has no budget and 4 unbounded child processes; launchd turns every overrun D into D + 600 s with no tick

- **Symptom.** Requests written at 03:24-03:26Z were first read by the request lane at 03:51-03:57Z (MEASURED: REQUEST lines at 03:56:01, 03:57:21 and 03:58:43). That is a 27-33 min wait, and `cc-lr rotate --all` timed out at 600 s. The next tick (pid 36464) started at 03:51:10Z and was still running at 04:28Z, 37 min in, with no log line after 04:11:39Z.
- **Measured frequency.** One read-only `python3 -I` pass over `poller.log`, window 2026-10-04T03:55Z to 2026-10-11T03:15Z (792 ticks).
  - **Method:** a tick starts at its `TICK start` line. It ends at the last line before the next `TICK start`, which is a lower bound because a tick can work silently. The gap is start-to-start.
  - **Duration:** p50 58 s, p90 210 s, p95 409 s, p99 1445 s, max 5290 s.
  - **Overruns:** **25 ticks > 600 s, 13 > 900 s, 11 > 1200 s.**
  - **Gaps:** p50 678 s; 71 > 900 s; 13 > 1800 s.
  - **Ticks lost:** 792 observed against 1004 expected for 167.3 h at 600 s, so **212 interval slots lost (21%)**.
  - **What launchd does after an overrun.** It never starts a second instance and never catches up:
    - `grep -c TICK-SKIP poller.log` = **0**.
    - After each of the 12 longest ticks, the time from its last line to the next start was 435-1027 s.
    - Live case: exit 03:41:09Z, then `TICK start` at 03:51:10Z (601 s).
    - `launchctl print` shows `run interval = 600 seconds`, `runs = 1191`.
  - **Live phase times in the 03:51Z tick** (ps sampling of pid 36464's children):
    - `cc-limited --all --json`: about 04:04 to 04:11:02 (7 min).
    - `lr-audit.py` for 58d3640a: 04:14:14 to 04:19:29 (5.25 min).
    - The `find -H ~/.claude-tertiary/projects … -mmin -2880` walk: etime 4:08 and still running at 04:28.
- **Root cause.**
  - No wall-clock budget anywhere in the tick: the lock at `lr-reset-poller.sh:216-232` guards overlap only.
  - These calls have no timeout:
    - census `"$CC_LIMITED_BIN" --all --json` at `:1734`
    - `--reaper --persist` at `:1768`
    - `python3 "$AUDIT"` at `:1891`
    - the transcript-walk `find` at `:1926`

    By contrast, `lrp_bounded` (`:74-77`) wraps only osascript and launchctl.
  - Launchd re-arms the `StartInterval` timer at job exit (MEASURED above), so an overrun D delays the next request lane by D + 600 s plus the time to reach the lane.
- **Fix (M).**
  1. Add `LR_POLLER_TICK_BUDGET_S` (default 480). Store the start in `$SECONDS`, which is a bash 3.2 builtin and costs no fork. Check `(( SECONDS > budget ))` between phases and at the top of each `for pf` / `for _rq` iteration. On breach, log `TICK-BUDGET phase=<p> elapsed=<s> left=<n records>` and break. Work left over waits for the next tick, which is already the semantics for CAP (`:2311`).
  2. Wrap the census, `--reaper`, `lr-audit` and the walk in `lrp_bounded_long` with their own timeouts, e.g. `LR_POLLER_CENSUS_TIMEOUT_S=120`, and log `CENSUS-TIMEOUT` on rc 124.
  3. Move the request lane so it runs both at the start of the tick and in `lrp_tick_end`. The EXIT trap already re-kicks the move lane for this exact reason (`:233-242`).
  - **Bats tests.**
    - A shim `cc-limited` that sleeps 30 s, run with `LR_POLLER_CENSUS_TIMEOUT_S=2`: assert the tick ends in under 10 s and logs CENSUS-TIMEOUT.
    - 50 fixture parked records with `LR_POLLER_TICK_BUDGET_S=0`: assert one TICK-BUDGET line and that the records are untouched.
    - A request written after the first request pass: assert the EXIT-trap pass drains it in the same tick.
- **Conviction:** 85.
- **Receipt.**
  - The `python3 -I` duration script printed `dur lower-bound p50 58 p90 210 p95 409 p99 1445 max 5290; >600 s: 25; gap>1800: 13; expected ticks 1004`.
  - `ps -axo pid,ppid,etime,command | awk '$2==966'` showed `969 966 04:08 find -H /Users/chrisren/.claude-tertiary/projects -maxdepth 2 -name *.jsonl -mmin -2880`.

## B2-3 — Nothing watches the tick or the runs for progress; existing locks key on pid for overlap only

- **Symptom.** A run can sit with no verdict and no alarm:
  - 58d3640a's bundle-20261011T032034Z was "admitted" at 03:25:26Z, holding a capacity-admit token.
  - 6defb493 and 516b9da9 have request files and no run.
  - The 20-min tick was silent by design: `husk-noted` damping at `:2207-2214`.
- **Measured frequency.**
  - `runs/by-sid`: **76 claims; 75 holders not alive (`ps -p`); 68 older than 24 h** (bash census reading `holder` JSON).
  - `fleet/`: **519 runs; 446 have `verdict.txt`, 73 do not** (bash loop). Runs without a verdict by date: 31 on 2026-09-19, 3 on 2026-10-10, 1 on 2026-10-11.
- **Inventory of existing guards** (`grep -rnoiE 'lease|heartbeat|dead[- ]?man|watchdog' scripts/limit-recover bin/cc-lr`):

  | Mechanism | Location | Keyed on | Reaped by | Alarms? |
  |---|---|---|---|---|
  | Tick mutex `poller.lock/{pid,lstart}` | `lr-reset-poller.sh:216-232` | owner pid+lstart | the next tick steals it if the owner is dead | never; a long tick is not an event |
  | Run claim `runs/by-sid/<sid>.active/holder` | `:1035-1056`, `lr-lib.sh:702-751` | holder pid+lstart, re-stamped to the detached driver | the **next `lr_claim_take` only**, which is lazy | never; a dead or hung holder delivers nothing |
  | Reconciler heartbeat | `lr-recon-fence.sh:319-331` (fresh ≤ 180 s) | output age of `recon/heartbeat` | `lrp_recon_watchdog` (`:255-276`) pages and kickstarts | yes (`recon-backup.page`, 15 min) |
  | Reconciler watchdog | `lr-recon-watchdog.sh` (launchd StartInterval 30) | holder (pid, lstart) + `progress` counter unchanged across two reads ≥ 30 s + ≥ 180 s + `kern.waketime` | itself; it kills a stalled holder | yes (lr-page) |
  | `lr-lock.py` TTL | `lr-lock.py` | evidence on disk, not age | `reap` verb | no |
  | `lr-fleet` verdict mail | `lr-fleet.sh:1876-1896` | written only when the driver reaches its end | — | the `''` arm, "driver died before lf_one returned", can only fire if the driver survives to print it |

- **Root cause.**
  - No component owns the question "this run or tick has an owner and a bound, the bound has passed, and there is no verdict".
  - Run claims are reaped only lazily, at `lr-lib.sh:702`, when someone tries to take the same sid.
  - The verdict is written by the same process whose death is the failure, at `lr-fleet.sh:1887`.
- **Fix:** the lease in B2-5 (M).
- **Conviction:** 80.
- **Receipt.**
  - `ls runs/by-sid | wc -l` = 76. The bash holder census printed `live=0 dead=75 older_than_24h=68`.
  - The fleet loop printed `fleet runs=519 with_verdict=446`.

## B2-4 — The lease's delivery leg has no address today: verdicts go "on disk only", and a `cc-lr recover` queued to a dead reconciler is archived without telling anyone

This is a precondition for B2-5. It may overlap B1 and B3; I kept it to what the lease needs.

- **Symptom.**
  - 58d3640a's run reached `verdict=FAILED rc=1 … lr-handoff rc=1`. `fleet/one-20261011T031606Z-58d3640a/detached.log` ends: "no requester pane and the desk role did not take it — the verdict is on disk only" (cc-notify: `fallback=phone-damped`).
  - The operator's `cc-lr recover` for 5507881f and 58d3640a was moved to `results/<sid>.cc-lr.unknown-mode.json` by `REQUEST-SKIP … unknown mode 'recover'; parked` (poller.log 03:56:01Z and 03:57:21Z). No mail went out. This is the named gap, "session recovered failed but the originating session didn't know."
- **Measured frequency.**
  - **348 of 446** fleet verdicts carry "verdict is on disk only" in `detached.log` (all time).
  - **56 of 62** in the 7 days since 2026-10-03, including 6 FAILED, 7 HELD:unreachable and 22 RECOVERED.
  - Unknown-mode skips: 2, both on 2026-10-11 (`grep -c 'REQUEST-SKIP.*unknown mode' poller.log` = 2).
- **Root cause.**
  1. `lr-fleet.sh:1689-1693` derives the requester only from its **caller's** environment (`LR_FLEET_NOTIFY_PANE`, `CC_PANE_ID`, `ITERM_SESSION_ID`, `KITTY_WINDOW_ID`). The launchd poller has none of these, so every poller-dispatched run notifies `--role desk` (`:1892`), and the desk role is unset (detached.log: `desk-role-unset`).
  2. `bin/cc-lr:599` queues `mode:"recover"` for the reconciler, and `bin/cc-lr:266` records no requester field. When the reconciler is not live, the poller drains `.cc-lr.json` (`lr-reset-poller.sh:1201-1205`, "so none strands on a dead daemon"). Its mode gate only accepts `relaunch|prompt` (`:1326-1330`), so it archives the request. In 03:51-04:02Z the reconciler went stale, was kickstarted and came back: one tick shows both `REQUEST-SKIP unknown mode` (03:56Z) and `RECON-OWNED 1` (04:02:19Z).
- **Fix (S).**
  1. Every request writer records `requester` (`cc-lr`: its own `CC_PANE_ID`; the stop-failure hook: `source_pane`), and the poller exports `LR_FLEET_NOTIFY_PANE` from it on dispatch (`:1456`, `:2077`).
  2. Map `mode=recover` to the request lane's default (relaunch) at `:1326`.
  3. Every terminal REQUEST-* line (SKIP, EXHAUSTED, RETIRED, STAY past its bound) also delivers one verdict line to `requester`, with `lr-page.sh` as the fallback, never desk alone.
  - **Bats tests.**
    - With reconciler-live false, a `.cc-lr.json` with mode recover must reach the dispatch shim, not `results/*.unknown-mode.json`.
    - A poller-dispatched fleet run must see `LR_FLEET_NOTIFY_PANE=<requester>` in the dispatch shim's env.
- **Conviction:** 80.
- **Receipt.**
  - The `grep -q "verdict is on disk only"` loop over `fleet/*/detached.log` printed `verdicts=446 on_disk_only=348` and, for the last 7 days, `56 disk / 6 sent`.
  - `cat results/58d3640a-…cc-lr.unknown-mode.json` gave `{"…","requested_by":"cc-lr","mode":"recover","pane":"113",…}`.

## B2-5 — Lease spec: a lease on the owner's mutex, reaped by the existing 30-second watchdog job, delivering FAILED once

- **Symptom.** When an expected verdict never arrives, nobody learns that it is missing (B2-3, B2-4).
- **Measured frequency.** 73 runs with no verdict, 75 claims with dead holders, 2 requests with no run (6defb493, 516b9da9), and 1 tick of 25 min plus 1 of 37+ min in the live window. Sources are in B2-2 and B2-3.
- **Root cause.** Covered in B2-3. Verdicts are written only by the actor whose death or wedge is the failure.
- **Design.**

  **L1 — tick lease.**
  - Written by `lr-reset-poller.sh` to **`$STATE/poller.lock/lease`**, inside the existing mutex dir, so it lives and dies with the owner.
  - Fields: `pid lstart start_epoch budget_s phase progress progress_wall`.
  - `progress` is incremented at each phase boundary and on **every** parked-loop and request-loop iteration. The log is damped, so log mtime is not usable as a progress signal. The beat uses `start_epoch + $SECONDS` and costs no fork under bash 3.2.

  **L2 — run lease.**
  - **`runs/by-sid/<sid>.active/lease.json`** (and the `cc-lr` MUTEX_DIR claim), written at `run_claim_take` and re-stamped in `run_claim_handoff` (`:1048-1056`). It is keyed on the claim holder's (pid, lstart), which is already stored there.
  - Fields: `run_dir` (fleet/<RUN>), `bundle`, `requester` (from B2-4), `request_file`, `deadline_epoch` (now + 900 s, from lr-fleet's own 115-658 s price at `lr-fleet.sh:977`), `verdict_path`.
  - The driver extends `deadline_epoch` when it appends a state to `events.jsonl`.

  **L3 — request lease.**
  - A `requests/*.json` older than 2 × budget + 600 s (≈ 26 min) with no claim and no result is overdue.

  **Reaper.**
  - **`lr-recon-watchdog.sh`** (`com.reso.lr-reconciler-watchdog`, launchd StartInterval 30, bash 3.2, imports nothing it watches), or a sibling job built on the same skeleton.
  - It reuses the job's existing rules: holder (pid, lstart) alive and not a zombie; progress unchanged across two reads ≥ 30 s apart; ≥ 180 s since the last advance; `now − kern.waketime > 120 s`. The waketime rule matters: the 2.9 h gap after 2026-10-10T19:07Z coincides with `pmset -g log` Sleep/DarkWake at 14:06-14:11 local.

  **Verdicts the reaper writes.**
  - L1 progress frozen ⇒ `TICK-STALLED` page, once per 15 min (no kill by default).
  - L1 still progressing past `budget + 300 s` ⇒ `TICK-OVERRUN phase=<p>` page, once per tick.
  - L2 with no `verdict.txt`:
    - Holder **dead** ⇒ write `verdict=FAILED reason=driver-died state=<last events.jsonl state>` with noclobber (write once). Release the capacity-admit token named in the last `admitted` row, then `lr_claim_release` the claim, naming the dead holder pid.
    - Holder **alive past its deadline** ⇒ write `verdict=FAILED reason=lease-expired-alive` and page. Do **not** steal the claim: a live holder may still act.
  - L3 ⇒ `results/<sid>.undrained.json` + `verdict=FAILED reason=no-run-started request_age=<s> poller_phase=<L1.phase>`.

  **Delivery.**
  - Exactly once, marked by a `delivered` file in the claim dir.
  - First choice: `cc-notify <requester>` when `lr_registry_live_rows` shows that pane live.
  - Otherwise `lr-page.sh`, which has no liveness dependency (`lr-page.sh:1-30`).
  - Desk alone is never the only route.

- **Why it is keyed on the mutex and not on output age.** The parked loop is silent by design (`:2207-2214`), and sleep inflates every age. A pid+lstart owner plus a progress counter separates "dead" from "slow" from "wedged". The watchdog already uses that discipline for the reconciler.
- **Fix size:** M (about 120 lines in the watchdog, about 20 in the poller and lr-fleet).
- **Bats tests** (seams `LR_WD_NOW` and a waketime shim):
  1. Claim with a dead holder and no verdict ⇒ one FAILED `verdict.txt`, one cc-notify shim call carrying the requester, claim removed. A second run delivers nothing more.
  2. Holder alive (a background `sleep 60`) and deadline past ⇒ FAILED lease-expired-alive, claim kept.
  3. Holder alive and deadline in the future ⇒ no-op.
  4. Recent waketime ⇒ no verdict.
  5. L1 progress frozen across two reads 30 s apart ⇒ one TICK-STALLED page. Progress advancing ⇒ none.
  6. A 30-min-old request with no claim ⇒ an `undrained` result plus delivery.
- **Conviction:** 65. The design reuses proven parts, but the capacity-token release and the requester field are new contracts.
- **Receipt.**
  - `launchctl list | grep reso.lr` shows `- 0 com.reso.lr-reconciler-watchdog`.
  - `com.reso.lr-reconciler-watchdog.plist` has `StartInterval 30`.
  - `lr-recon-watchdog.sh:1-30` has the 4-condition kill rule.

## B2-6 — 1,041 "bad substitution" errors in `poller.launchd.err` disabled the census-park arm for about 8.5 days, and nothing reads the file

- **Symptom.** `poller.launchd.err` is 1.26 MB, last written 2026-09-29 03:54 local (08:54Z), and nobody noticed for 12 days.
- **Measured frequency.**
  - `grep -c 'bad substitution'` = **1041**.
  - Reported at script line 1111 (380), 1028 (248), 1128 (140), 1125 (114) and 1088 (57): 5 deployed versions of one construct.
  - About 995 ticks ran 2026-09-21 to 09-28 (TICK start per day: 132, 136, 133, 115, 124, 114, 123, 118), so roughly one error per tick.
  - **Zero `[census]` PARKED lines before 2026-09-29**; 1-14 per day afterwards (awk over poller.log).
- **Root cause.**
  - `done < <(python3 - "$_cj" <<'PY' … PY)`: a heredoc inside a process substitution, which /bin/bash 3.2 (launchd's interpreter) rejects on an apostrophe in the program.
  - **Introduced** 7c7a5261b (2026-09-20T15:45-05:00, "point the fleet and the poller at the landed census"). **Fixed** cf7bd5c1a (2026-09-29T03:25-05:00), whose message says: "The census ingest is lrp_census_ingest, reading its python from a temp file: the heredoc inside `<( … )` died with `bad substitution` under /bin/bash 3.2". Found by `git log -S"<(python3 - \"\$_cj\" <<'PY'"`.
  - The error killed only the substitution, so every tick still exited 0.
  - **Readers:** `git grep -n 'poller\.launchd\.err' -- ':!docs'` matches only the plist's `StandardErrorPath` (`com.reso.lr-reset-poller.plist:40`) and a comment at `lr-reset-poller.sh:147`. That comment records the **previous** silent loss in this same file: 160 `_LRP_SELF: unbound variable` lines up to 2026-09-10.
- **Fix (S).** Add a stderr watermark alarm at tick start, implemented as a function in the poller (or in the B2-5 watchdog so it also covers its own and the reconciler's err files):
  - Compare `stat -f %z poller.launchd.err` to `$STATE/launchd-err.offset`.
  - On growth: log `STDERR-GREW <n> bytes: <first new line, 160 chars>`, `lr-page.sh` at most once per 6 h, and advance the offset.
  - If size < offset (truncated): reset the offset and stay silent.
  - Also run `bash -n` under `/bin/bash` 3.2 in the suite for every launchd-run script. The rules file already names this trap: "Deployment interpreter ≠ yours".
  - **Bats tests.** The fixture err file grows by one line ⇒ one PAGE and the offset advances. No growth ⇒ silent. Truncation ⇒ the offset resets and nothing pages.
- **Conviction:** 90.
- **Receipt.**
  - `grep 'bad substitution' poller.launchd.err | sed 's/^[^:]*: //' | sort | uniq -c` printed `380 line 1111 … 57 line 1088`.
  - `git log -S…` printed `cf7bd5c1a 2026-09-29T03:25:42-05:00` and `7c7a5261b 2026-09-20T15:45:17-05:00`.

---

## Ruled out

- **Overlapping ticks or lock contention as the cause of the wait.** `grep -c TICK-SKIP poller.log` = 0, and launchd never starts a second instance (`:233-236`, measured).
- **A single hung child wedging the 03:15Z loop.** The operator saw a new subshell about every second, and my samples of the 03:51Z tick show children changing every 1-2 s outside the long phases. The loop was slow, not stopped.
- **The reroute dispatch (`lr-fleet --one`) inside the loop.** There is no REROUTE line between 03:21Z and 03:41Z, and 26 of the 31 records were past reset, which takes them down § 2, not § 2a.
- **python3 field reads as the main cost.** 2 python3 per record is 62 forks per tick, against about 2,000 in the registry scan.
- **The bad-substitution bug in the live case.** The err file has been unchanged since 2026-09-29.
- **cc-reaper killing the tick.** The 03:15Z tick ended through its EXIT trap: the MOVE-BATCH line comes from `lrp_tick_end`.
- **Machine sleep in the live case.** Loadavg was 260-314 with active forking. Sleep does explain the 2026-10-10T19:07Z 2.9 h gap (pmset Sleep/DarkWake at 14:06-14:11 local).

## Uncertain

- **How the 38 s per record splits** between pgrep, the registry scan and the rest. The live 03:51Z tick had not reached the parked loop by 04:28Z, so the split is inferred from the code plus one sampled 10 s pgrep. The interactive registry scan was 1.00 s at loadavg 174. The gap to the launchd job's pace (launchd resource limits on an unset ProcessType, or the load difference) is not measured.
- **Whether some of the 25 overruns are inflated by sleep.** The method cannot see sleep. At least the 2026-10-10T19:07Z tick is contaminated.
- **Whether the 03:51Z tick ended before 04:28Z.** Not observed. Its final duration is ≥ 37 min.
- **The capacity-admit token held by 58d3640a's run.** I did not trace which file holds it or whether it has its own TTL. B2-5's token release assumes the `admitted` event names the token path; the event's detail field starts "token /Users/chrisren/…".
- **Claim 00b363d4's holder pid 144.** It may be pid wrap or a wrong parse by `lr_detached_driver_pid`. Not traced.
- **Overlap with B1 (verdict paths) and B3 (delivery target)** on B2-4. Their files exist in `slots/`; I did not read them.
