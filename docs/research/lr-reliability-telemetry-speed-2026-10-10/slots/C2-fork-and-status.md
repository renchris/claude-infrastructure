# C2: fork-and-status: who forks, and why the cc-lr status surface is slow

Slot C2, read-only, measured 2026-10-11T03:47-04:23Z on the live box. Load average was 144 at the start, about 190-320 during the timings and 596 at the end. Code is cited at trunk 110ea9a64. The deployed `~/.claude/bin/cc-lr` resolves to the main checkout, also at 110ea9a64, and `diff -rq` shows the deployed `scripts/limit-recover` matches it except for `__pycache__`.

## Answer first

- **status --all is slow because of one loop.** `cc-lr status --all` took **239.05 s**. Almost all of that is the liveness loop at `bin/cc-lr:1992-1996`. It calls `lr_registry_live_rows` once for every bundle of every dead session, because the loop only remembers sessions it found live: 206 calls for 224 bundles. Each call forks `basename` and `jq` once per registry file (37 files, `lr-lib.sh:284-287`). That is about 15,900 forks to draw one table. A single jq over the registry takes **0.01 s** and gives the same liveness answer.
- **The poller pays every fork 8-14 times over.** The plist has no `ProcessType`, so the poller runs throttled at PRI 20, while 802 interactive processes run at PRI 31. The same 37-file registry loop took **0.63-0.99 s at PRI 31** and **7.78-13.87 s under `taskpolicy -c utility`** (PRI 20) at load about 300. One tick is still running after 31 min. Five sampling profiles show where its time goes: the request lane (40% of samples are freshly forked subshells), `cc-limited --all --json` (about 300 s), the backstop `find` over about 17,200 project dirs per store, and one `lr-audit.py` that ran for more than 290 s.
- **The poller does expensive work it already knows the answer to.** All 31 parked records carry `.husk-noted`, and 26 of them reset 5-15 days ago. Each tick still re-proves every one of them with 2 python3 forks, `pgrep -f`, 4-5 globs over `projects/*` and at least one registry fork loop. The marker silences the log line only, not the work (`lr-reset-poller.sh:2140-2215`).
- **Fixes, in order of saving:**
  1. One-jq registry read inside `lr_registry_live_rows`. It has 41 call sites, and each call drops from 74 forks to 1.
  2. Build the live-sid set once in `cmd_status`, which takes status from 239 s to about 1 s.
  3. Per-tick memo for husk-noted parked records.
  4. One ps snapshot per verdict pass in `move --status` (37 s to about 5 s).
  5. Lift the poller's priority, but only after the fork counts are down.

---

## C2-1: `cc-lr status --all` re-walks the registry for every bundle of every dead session

- **Symptom (MEASURED).**
  - `/usr/bin/time -p cc-lr status --all` gave real 239.05 s, user 30.37 s, sys 48.86 s at load about 185-217. The output was 224 runs.
  - The brief's earlier run of `move --status` plus `status --all` went over 120 s.
- **Frequency (MEASURED for cost, not measurable for use).**
  - Every `status --all` call pays this. Cost grows with bundles of dead sessions, which is 193 today.
  - Invocations cannot be counted, because `cc-lr status` writes no log.
- **Root cause.**
  - **The loop (INFERRED from code, confirmed by arithmetic).**
    - `bin/cc-lr:1992-1996` runs once per bundle: `_cl_bd="$(dirname …)"; _cl_sid="$(basename "$(dirname …)")"`, then `lr_registry_live_rows "$_cl_sid"`.
    - The skip at `:1994` matches only sids already appended to `cl_live`, and only live sids are appended (`:1995`). So a dead sid with k bundles is probed k times.
    - Each probe (`scripts/limit-recover/lr-lib.sh:284-287`) forks `basename` and `jq` per registry file.
  - **Store counts (MEASURED with `ls`/`jq`/`kill -0` over `~/.reso/limit-recover/*/bundle-*/events.jsonl` and `~/.claude/cc-registry/*.json`).**
    - 224 bundles and 110 sids.
    - 13 live sids hold 31 bundles; 97 dead sids hold 193 bundles.
    - That gives **206 probes**, at 37 registry files × 2 forks each.
  - **Attribution (MEASURED sub-steps at load about 217, PRI 31).**

    | step | measured | count in status --all | total |
    |---|---|---|---|
    | one `lr_registry_live_rows`-shaped loop over 37 files | 1.33 s | 206 | about 229-274 s |
    | 224 × `dirname` + `basename "$(dirname)"` | 9.31 s | 1 | 9.3 s |
    | `cl_events_bulk` (one jq over 224 events.jsonl) | 0.19 s | 1 | 0.2 s |
    | one `stat` over all files | not timed, 1 fork | 1 | about 0 |
    | **alternative**: one jq over all 37 registry files | **0.01 s** | 1 | 0.01 s |

    The sum (about 239-283 s) brackets the 239 s measured.
  - **Why the test suite missed it (MEASURED by reading).**
    - `tests/cc-lr-front.bats:443` asserts that status "forks jq ONCE".
    - `setup` exports `HOME="$BATS_TEST_TMPDIR/home"`, so the registry dir does not exist. The probe loop then globs nothing and forks nothing.
    - The fixture also uses one sid. The budget test therefore cannot see the per-bundle registry walk.
- **Fix (size S).**
  - In `cmd_status`, build `cl_live` once, before the bundle loop:

    ```bash
    while IFS=$'\t' read -r _s _p; do case "$_p" in ''|*[!0-9]*) continue;; esac
      kill -0 "$_p" 2>/dev/null && cl_live="$cl_live$_s"$'\n'; done <<EOF
    $(jq -r '[(.session_id // .sessionId // ""), (.pid // "" | tostring)] | @tsv' "$regdir"/[!.]*.json 2>/dev/null)
    EOF
    ```

  - Keep `CL_LIVE_KNOWN` fail-open: if jq exits non-zero, use today's per-sid path.
  - Replace `dirname`/`basename` with `${f%/*}` and `${d##*/}`.
  - Expected: 239 s becomes about 0.3-2 s at the same load. The remaining work is 0.19 s of bulk jq, 0.01 s of registry jq, 37 `kill -0` builtins and awk.
  - **Bats.** Extend `cc-lr-front.bats:443`:
    - Set `CC_REGISTRY_DIR` to 30 files: 1 with pid `$$`, 29 with dead pids, and one dotfile.
    - Spread 20 bundles across 10 dead sids.
    - Add counting stubs for `jq`, `basename` and `dirname`.
    - Assert `jq.calls ≤ 2` and `basename.calls + dirname.calls == 0`.
    - The existing ":404 dead session is never offered repair" and ":416 CONTROL" cases must stay green.
- **Conviction:** 90.
- **Receipt.**
  - `time -p cc-lr status --all` gave `real 239.05 user 30.37 sys 48.86`.
  - Sub-step timings, in order: `real 1.33` (A), `0.01` (B), `0.19` (C), `9.31` (D).
  - Liveness count: `live sids 13 bundles 31 ; dead sids 97 bundles 193 ; registry calls = 206`.

## C2-2: `lr_registry_live_rows` forks 2 processes per registry file, and 41 call sites inherit that

- **Symptom (MEASURED).**
  - One call costs 1.33 s at PRI 31 (load about 217).
  - Under `taskpolicy -c utility` (PRI 20, the poller's class) it costs 7.78 s and 13.87 s, against 0.63 s and 0.99 s at default priority (load about 300).
  - One jq over the same 37 files takes 0.01 s.
- **Frequency (MEASURED, static).**
  - 41 references (`grep -c`): lr-fleet 15, lr-reset-poller 12, lr-lib 7, cc-lr 3, lr-move-lib 2, lr-handoff 2.
  - Each call costs 74 forks: 37 `basename` plus 37 `jq`. Each matching row adds 4 more jq.
  - Per-tick call counts are not measurable: the poller does not log them.
- **Root cause.** `scripts/limit-recover/lr-lib.sh:284-293`, in commit 109cfe4cfb (2026-09-08):
  - `case "$(basename "$f")"` and `jq -r '.session_id…' "$f"` run per file.
  - Then `jq` runs per field (pid, paneUUID, account, cwd) on the matching file.
- **Fix (size S-M).**
  - Do one pass: `jq -r --arg s "$sid" 'select((.session_id // .sessionId // "") == $s) | [input_filename, (.pid//""|tostring), (.paneUUID//""), (.account//""), (.cwd//"")] | join("\u001f")' "$regdir"/[!.]*.json`.
  - Read it with `IFS=$'\037'`. That separator is not IFS whitespace, so empty cells survive (the repo rule "Empty TSV cells vanish").
  - Keep `kill -0`, the pane fallback to the file name, and the `${acct:--}` padding.
  - If jq exits non-zero (a malformed file aborts the whole invocation), fall back to today's per-file loop, so a corrupt row still costs only its own row. This is the same pattern as `cl_events_bulk` at `bin/cc-lr:1885`.
  - It stays bash-3.2 safe: no associative arrays.
  - Expected: 74+ forks become 1 per call, about 40-130× faster per call (1.33 s to about 0.01-0.03 s at PRI 31).
  - This one change shrinks C2-1, C2-4 and C2-5 at every call site.
  - **Bats** in `tests/lr-lib.bats`, next to `:108`, with 20 registry files that include:
    - a dotfile;
    - a dead pid;
    - a row with no `.account`;
    - a row with no `paneUUID`;
    - one malformed file.

    Assert the rows are byte-identical to the current output (golden, captured before the change), and `jq.calls == 1` without the malformed file and `≥ 2` with it.
- **Conviction:** 85. The residual risk is jq's abort on a malformed file; the fallback covers it.
- **Receipt.**
  - Commands: `/usr/bin/time -p bash -c '<37-file loop>'` gave `real 1.33`; `/usr/bin/time -p jq … "$R"/*.json` gave `real 0.01`.
  - Priority comparison: `default pri=31 real=0.63s`, `utility pri=20 real=7.78s`, `default pri=31 real=0.99s`, `utility pri=20 real=13.87s`.

## C2-3: the poller runs throttled (PRI 20), so its forks cost 8-14× more than the same forks in a session

- **Symptom (MEASURED).**
  - `ps -o pri -p 36464` (the live tick) gives **20**.
  - Across the box, `ps -axo pri` counts 132 processes at PRI 20 and 802 at PRI 31.
  - The registry loop takes 8-14× longer at PRI 20 (C2-2 receipt).
  - The tick that started at 03:51:11Z was still running at 04:22:50Z (`ps etime 31:39`) and had not yet reached its parked loop.
  - Children inherit the class: a detached `handoff-fire.sh __recycle` (pid 73584, ppid 1) also showed PRI 20. Panes spawned through kitty show PRI 31 (lr-fire-resume ×7).
- **Frequency (MEASURED, `poller.log` "TICK start" since 2026-10-04T03:52Z).**
  - 794 ticks.
  - Gaps between tick starts: p50 678 s, p90 882 s, max 10,478 s. 72 gaps were over 900 s and 33 over 1,200 s.
  - "TICK start to last logged line" was over 600 s in 25 ticks, with a max of 5,290 s.
- **Where the current tick's time went (MEASURED, five ps sampling profiles of pid 36464's leaf children at about 1.2-1.6 Hz, 215-275 s each).**

  | phase (log anchor) | dominant leaf (share of samples) |
  |---|---|
  | request lane, 03:51-04:02 | a forked poller subshell not yet exec'd 109/274 (40%), python3 58/274 (21%), `ps -axo` census 31/274 (11%) |
  | lock reap / detect, 04:03-04:07 | `cc-limited --all --json` 188/297 (63%), `cc-resume-debt sweep` 36 plus per-file `basename` of resume-debt meta |
  | detect, 04:07-04:11 | `cc-limited --all --json` 184/266 (69%), census ingest python 77/266. Together the census is about 300 s |
  | backstop walk, 04:11-04:15 | `find -H ~/.claude-next/projects -maxdepth 2 …` 170/420 (40%), `lr-audit.py --quiet` 76, `ps -axo` 22, `pgrep -f` 20 |
  | backstop walk, 04:16-04:20 | one `lr-audit.py --quiet` (same tmp json) 286/375 (76%), so that single audit ran for more than 290 s. `find` on secondary 62 |

- **Root cause.**
  - `scripts/limit-recover/com.reso.lr-reset-poller.plist` and the installed copy (same keys) have no `ProcessType`. launchd then applies its default light resource limits, which throttle CPU and I/O.
  - The repo already records this class as "utility" in its own words at `launchd/com.claude.boot-resume.plist:46-54`.
  - The cost multiplies with fork count; it is not a separate fault. Under contention, each fork/exec/exit cycle has to win a PRI-20 slot against 800 PRI-31 threads.
- **Fix (size S).**
  - Land C2-2, C2-4 and C2-6 first. Then add `<key>ProcessType</key><string>Interactive</string>` to the repo plist and reinstall. `scripts/launchd-parity-lint.sh` already enforces that the repo and installed copies match.
  - Expected: the 8-14× fork penalty disappears. The census `cc-limited` (about 300 s at PRI 20) should drop by a similar factor. That is INFERRED; it was not run at PRI 31, because the brief does not list it as allowed.
  - **Bats.** Assert in the launchd parity suite that the poller plist carries `ProcessType=Interactive`. A runtime check (`launchctl print` plus `ps -o pri` of the tick being at least 31) belongs in the nightly parity lint, not bats.
- **Conviction:** 60. The root cause is about 90: measured 12-14× under the same QoS clamp. The fix carries a trade-off: an unthrottled daemon that does 300 s of census CPU competes with interactive sessions. Hence the "after the fork cuts" ordering.
- **Receipt.**
  - `ps -o pid,pri,nice -p 36464` gave `36464 20 0`.
  - Plist keys: Label, ProgramArguments, RunAtLoad, StartInterval, StandardErrorPath, StandardOutPath, EnvironmentVariables. No ProcessType.
  - Profiles: the task outputs summarised in the table above.

## C2-4: the parked loop re-proves 31 records it has already marked husk-noted, every tick

- **Symptom.**
  - MEASURED in the brief's live case: 31 records took about 20 min (03:21:21Z to 03:41:09Z), about 48 s per record at load about 260.
  - MEASURED by me: 31 `parked/*.json` and **31 `.husk-noted`**.
  - Reset dates: 26 records reset between 2026-09-26 and 10-06, and 5 are due 2026-10-11T04:00Z.
  - Of the 31, 28 have a `.jsonl.handed-off` and 5 are named in the registry. 2 have both, so they also run `lr_successor_state` through `husk_file_request` on every tick (no `.husk-filed` marker exists).
- **Frequency (MEASURED).**
  - Every tick that reaches section 2 (794 ticks in 7 d).
  - "CONSOLIDATED 26 ready → 0 winner(s)" repeats at 02:48:43, 03:03:48 and 03:21:21, and each is followed by 11-20 min with no log lines.
- **Root cause (INFERRED from code plus the measured cost of each primitive).**
  - Per record, `lr-reset-poller.sh` runs:
    - 2 × `python3` at `:2140` and `:2151`;
    - `husk_file_request` (`:2103-2120`): a `projects/*` glob and a registry grep;
    - `pgrep -f` and `sid_claimed` at `:2158-2164`;
    - `lr_transplant_target` (`lr-lib.sh:801-821`): 2 globs over `projects/*`;
    - `lrp_unmoved` (`:2098-2101`): 1 glob;
    - `lr_state_current`;
    - `lr_registry_live_rows_in_cfg`, which wraps one `lr_registry_live_rows` (74 forks).
  - Only after all of that does the `.husk-noted` check at `:2211` `continue`. The marker stops the log line, not the work.
  - Per-primitive costs at PRI 20 and load about 300 (MEASURED): registry loop 7.8-13.9 s; one `projects/*/<sid>.X` glob 2.43 s; python3 about 0.09 s at PRI 31 times the 8-14× penalty. With about 5 globs, 1-2 registry loops, 2 python3 and 1-2 `pgrep`, a record costs about 25-45 s. That brackets the 48 s observed.
- **Fix (size M).**
  1. **Read all parked records once.** One `jq -r '[input_filename,.sid,.acct,.cfg,.cwd,(.reset_at_utc|fromdateiso8601? // 0)]|@tsv' "$PARKED"/*.json` replaces 62 python3 forks (measured 0.03 s for 31 files). Keep a NUL-safe field check for `cwd`: today's comment at `:2131-2139` explains why `eval` was dropped.
  2. **Memoise husk-noted records.** Write into `.husk-noted` the stamp of its inputs: tombstone mtime, `cc-registry` dir mtime, and newest bundle `events.jsonl` mtime. Skip the transplant probes while the stamp is unchanged. This costs about 3 `stat` per record per tick.
  3. **Move long-dead records out of the per-tick loop.** A record whose reset is more than 7 days old, with an unchanged husk stamp, goes to a `parked/stale/` dir with one page, instead of being walked forever.

  - Expected: the parked phase drops from about 31 × 48 s (about 25 min at load 260) to under 5 s when nothing changed. That shrinks the tick that requests and move batches queue behind. The lane-latency effect is C1/C3's to quantify.
  - **Bats** in `tests/lr-reset-poller-inplace.bats`:
    - Fixture: 30 husk-noted parked records with past resets, plus counting stubs for `python3`, `jq`, `pgrep`, and a `CC_REGISTRY_DIR` with 10 files.
    - Run two ticks.
    - Assert tick 2 makes 0 registry-file jq calls and at most 1 `python3` call in section 2.
    - Then touch one tombstone and assert exactly that record is re-probed.
- **Conviction:** 60. The per-record cost is decomposed from primitive timings, not from a profile of the parked phase itself. Profile 5 ended at 04:20 before the live tick reached section 2.
- **Receipt.**
  - `ls parked | sed …suffix… | uniq -c` gave `31 .husk-noted, 31 .json, 1 .draft-paged`.
  - `jq -r '[.acct,.reset_at_utc]'` showed the reset distribution above.
  - The handed-off and registry walk gave `parked=31 handed-off=28 registry-named=5 both=2`.

## C2-5: every `projects/*/<sid>.X` glob and the backstop `find` walk about 17,200 project dirs per store

- **Symptom (MEASURED).**
  - Project dirs per store: `.claude-next` (→ `~/.claude/projects`) 17,239; `.claude-secondary` 17,150; `.claude-tertiary` 17,135; `.claude-quaternary` 17,194.
  - In quaternary, only **102** dirs hold a `.jsonl` modified in the last 7 days.
  - One bash glob `projects/*/<sid>.HANDOFF.json` takes 1.38 s at PRI 31 and 2.43 s at PRI 20 (load about 323).
  - `find -H <store>/projects -maxdepth 2 -name '*.jsonl' -mmin -2880` takes 3.07-4.18 s per store at PRI 31.
  - Profile 4 caught the poller's copy of that `find` in 170 of 420 samples (about 107 s) for one store at PRI 20.
- **Frequency (MEASURED).**
  - The backstop `find` runs once per store per tick (`lr-reset-poller.sh:1926`), so 4 per tick.
  - Globs run about 5 times per parked record per tick (C2-4).
  - In `move --status`, `lr_session_location` (`lr-move-lib.sh:38-47`) globs once per store per verdict, so 4 per row.
- **Root cause.**
  - Session lookups by sid glob over every project dir instead of an index: `lr-lib.sh:806-818`, `:983-989`; `lr-reset-poller.sh:2100, 2111, 2113, 866`; `lr-move-lib.sh:41-44`.
  - The dir count is about 170× the active set.
- **Fix (size M).**
  - Build one sid → transcript index per tick, one `find` per store, already paid at `:1926` if its `-mmin` filter is dropped into a second output. Store it as a sorted temp file and look up with one `awk` per batch of sids. bash 3.2 has no associative arrays.
  - Alternatively, read the sid → path map from the `cc-limited --all --json` census the tick already produces (`:1733`).
  - Separately, offer the operator an archive of project dirs untouched for more than 30 days (out of the rail's scope; that is a write).
  - Expected: about 5 globs × 2.4 s per record become about 0, and the backstop walk is paid once instead of again per lookup.
  - **Bats.** Fixture store with 2,000 empty project dirs and 3 transcripts, a stub `find` counter. Assert that section 2 makes no `projects/*` glob per record (instrument through a `LR_TX_INDEX` seam) and that lookups return the same paths as today.
- **Conviction:** 55. The cost is measured; whether reusing the index is correct for every glob site (handed-off, HANDOFF.json, successor in the target store) needs a per-site check.
- **Receipt.**
  - `ls <store>/projects | wc -l` for each store.
  - `find … -mtime -7 | awk … | sort -u | wc -l` gave 102.
  - `time -p bash -c '<glob>'` gave `real 1.38` and `real 2.43`.
  - `time -p find -H …` gave 4.18, 3.24, 3.07 and 3.22 s.

## C2-6: `cc-lr move --status` walks the registry twice and runs a full ps census per verdict

- **Symptom (MEASURED).**
  - `/usr/bin/time -p cc-lr move --status 20261011T032613Z-next-next4-91646` gave real 36.96 s, user 4.40 s, sys 8.39 s at load about 186.
  - The batch has 12 rows: 7 `NOTMOVED` verdicts re-derived, and 5 hold rows that each take one jq on `plan.json`.
- **Frequency.** Every call: about 5 s per moved row. The batch summary itself records `155s` for the move.
- **Root cause (INFERRED from code plus primitive timings).** Per verdict, `lr_move_verdict` (`lr-move-lib.sh:82-170`) runs:
  - `lr_move_holders` (`:57-59`), which calls `lr_registry_live_rows` (1.1-1.3 s) and `lr_resume_procs`. That is a full `ps -axo pid,ppid,command` (`lr-lib.sh:558`, 0.72 s measured).
  - **A second** `lr_registry_live_rows` at `:95` for the same sid.
  - `lr_session_location`: 4 store globs (C2-5).
  - One jq over all registry files at `:121`.
  - `ps -o lstart` up to 2 times, `ps -E` up to 2 times, `lr_move_phys` subshells, and several `sed`, `cut` and `grep -c` forks.
  - About 7 × (2 × 1.2 + 0.7 + globs) comes to about 25-35 s, consistent with the 37 s measured.
- **Fix (size S).**
  - Call `lr_registry_live_rows` once per verdict and derive holders from those rows plus `lr_resume_procs`.
  - Take one `ps -axo pid=,ppid=,command=` snapshot per `cmd_move_status`. Pass it in through an env seam (for example `LR_PS_SNAPSHOT=<file>`) read by `lr_resume_procs` in place of its own `ps`. Pass the env through, never argv: argv is the census-matches-itself trap.
  - With C2-2 in place, every registry read is 1 jq.
  - Expected: 37 s becomes about 3-5 s at the same load. 7 × 1.2 s are saved by deduplication, 6 × 0.7 s by the snapshot, and 14 × 1.2 s by C2-2.
  - **Bats** in the move-lib suite: 7-row plan fixture with a stub `ps` counter. Assert `ps -axo` is called once per `cmd_move_status` and the verdict table is unchanged (golden).
- **Conviction:** 75.
- **Receipt.** `real 36.96 user 4.40 sys 8.39`, and the row table ending `summary: done: NOTMOVED=7; target auth after the batch: ok; 155s`.

## C2-7: fleet-wide ranking of forkers (sampled; method has known blind spots)

- **System fork rate (MEASURED).** About **1,000 forks/s**. The delta of ps-call pids was 39,932 in 40.0 s at load about 140-200.
- **Method.**
  - 43-55 full `ps -axo pid,ppid,etime,ucomm,command` snapshots over 34-40 s. One snapshot took 0.72 s on average and 1.37 s at most.
  - Every pid absent from the first snapshot was attributed to its parent command.
  - **Captured 2,878 of about 39,932 new pids (7%).**
- **Ranking of captured new processes by parent (40 s window).**

  | count | parent / owner |
  |---|---|
  | 527 | Claude CLI sessions (wrapped by `cc-close-attrib`, 46 processes): 389 bash, 64 git, 30 zsh, 27 python, 17 bash from a second CLI build. These are hooks and tool calls |
  | 566 + 82 jq + 53 sed + 45 awk + 44 sleep | parent shown as `(bash)`: an exiting or just-forked bash whose argv was unreadable, so the owner is unknown |
  | 86 | `cc-lr status --all` (39 bash + 24 basename) and `cc-lr move --status` (23), run by sibling slots |
  | 130 | test suites: `test-hermeticity-lint.sh --selftest` 54+16, bats `linked-lint.sh --selftest` 47+20, pytest 48 git + 22 bash + 12 pandoc |
  | 49 | `lead-crash-watchdog.sh` sleeps (31 instances on the box) |
  | 42 | `postland-verify.sh --run-if-needed` sleeps |
  | 48 | `wait-contract-lint.sh --sweep` (33 jq + 15 bash) |
  | 45 | `cc-cloud list --json` (31 + 14) |
  | 25 | `registration-state.sh --json` |
  | 15 + 13 | `compressor-sentinel.sh`, `lead-supervisor.sh --daemon` |

- **Blind spots.**
  - **Lifetime bias.** A 0.72 s snapshot interval misses most ms-lived `basename`/`jq`. Long `sleep` loops are therefore over-represented, and `basename`/`jq` fork loops (C2-1, C2-2) under-represented.
  - **Lost parents.** Parent argv is lost for exiting or just-forked processes, shown as `(bash)`.
  - **Self-inclusion.** The sampler's own `ps` children appear: 82 `ps` under the Python parent.
- **Fix.** Not a single code site; this table is the input to C2-1 through C2-6. For lr itself, the per-tick fork budget is set by C2-2, C2-4 and C2-5.
- **Size and conviction.** Size not applicable. Conviction 50 on the ranking order (sampling bias), 85 on the rate.
- **Receipt.** `ps-pid delta forks 39932 over 40.0s = 998.2/s ; captured new pids 2878 (7%)`.

---

## Ruled out

- **jq parsing of run state as the status cost.** `cl_events_bulk` reads all 224 `events.jsonl` in 0.19 s (MEASURED).
- **`stat` per row.** Status already does one `stat` for all files (`bin/cc-lr:1968`).
- **The poller is wedged.** Five profiles show it advancing through request lane, lock reap, census, ingest and backstop walk, with log lines at 03:52-04:11Z. It is slow, not stuck. This is the repo rule that a driver's CPU is not its pipeline's progress.
- **`ps -S` (summing exited children into the parent) as a cost-per-parent method.** It returned 0.2 CPU-s in total over 47 s on this macOS build, so it is not usable. Sampling was used instead.
- **Load alone explains the slowness.** No: the same code is 8-14× faster at PRI 31 under the same load (C2-2 receipt). The cost is fork count × priority class × load.

## Uncertain

- **The parked-phase decomposition (C2-4) is inferred.** A direct profile of section 2 is still pending: the live tick passed 31 min, load went from 300 to 596, and it had not reached section 2 when sampling stopped.
- **`cc-limited --all --json` at PRI 31 was not measured.** Running it falls outside the brief's allowed commands. Its about 300 s inside the tick is MEASURED by sampling.
- **`ProcessType=Interactive` trade-off.** It is not measured how much it would slow interactive sessions while the census runs. Whether `Adaptive` or a `taskpolicy` wrapper suits better is open.
- **Out of slot, seen in passing (MEASURED in poller.log, for the A/B slots).**
  - `03:56:01Z REQUEST-SKIP 5507881f … unknown mode 'recover'; parked`.
  - `03:57:21Z REQUEST-SKIP 58d3640a … unknown mode 'recover'`, then `03:58:43Z REQUEST-RETIRED 58d3640a … transplanted to …claude-quaternary; nothing was done`.
  - So `cc-lr recover` requests reach a lane that does not know their mode. This bears directly on "the originating session didn't know".
- **kitty snapshots are not profiled.** `kitten @ ls` appears in lr-lib 1, lr-fleet 2, lr-upgrade 3 (`grep -c`). None showed in any poller profile. The move worker and upgrade drain were not sampled.
