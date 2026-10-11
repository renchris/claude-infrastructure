# A1 — verdict census of the limit-recover state store (2026-10-11T03:52Z)

## Answer first

- **The source of truth is `fleet/one-*/verdict.txt`, not the bundle state log.** 30 d (508 runs): FAILED 172, PARKED 166, RECOVERED 67, no verdict file 62, HELD 40, UNPROVEN 1. 7 d (69 runs): RECOVERED 23, HELD 25, FAILED 10, PARKED 6, no verdict 4, UNPROVEN 1. Move lane over 7 d: MOVED 9, NOTMOVED 16, FAILED 4. Switch over 30 d: 16 SWITCHED, 12 NOTMOVED.
- **About 70% of non-success runs over 30 d (235 of 338 FAILED+PARKED) come from just three sessions.** The poller's REROUTE arm re-dispatched each of them every 15 min against a refusal that would never change. It has no attempt cap (A1-3).
- **The operator's gap, measured.** In the last 7 d, 59 of 68 detached `lr-fleet --one` verdicts were delivered to nobody. That includes every daemon-driven FAILED, and the live 58d3640a FAILED at 03:41Z. A request does not carry who asked for it, and no desk was alive (A1-1).
- **The state log behind `cc-lr status` never gets a terminal line.** Of 224 `events.jsonl` files, 0 hold RECOVERED. 132 FAILED runs over 30 d wrote no `events.jsonl` at all. Live 58d3640a reads `admitted 39m16s` while its run FAILED at 03:41:02Z (A1-2).
- **`cc-lr status --all` timed out**: `real 200.04`, rc 124, 0 bytes of output, at loadavg 185 (A1-7).

Windows: 30 d = run start ≥ 2026-09-11T03:52Z; 7 d = run start ≥ 2026-10-04T03:52Z. Run start comes from the `one-<ts>-<sid8>` directory name, and for bundles from `bundle-<ts>`.

## Census tables (MEASURED, python3 -I over `~/.reso/limit-recover/fleet/one-*`)

| class | 30 d runs | 30 d distinct sids | 7 d runs | 7 d distinct sids |
|---|---|---|---|---|
| RECOVERED (recycle-in-place 52, spawn 8, nudge 6, husk-recycle 1 over 30 d) | 67 | 58 | 23 | 22 |
| FAILED | 172 | 17 | 10 | 5 |
| PARKED | 166 | 17 | 6 | 4 |
| HELD:* | 40 | 17 | 25 | 11 |
| UNPROVEN | 1 | 1 | 1 | 1 |
| no verdict.txt | 62 | — | 4 | — |

Top causes for each non-success class. The cause is taken from the lr-handoff/lr-transplant line in `<run>/<sid>.stderr`.

| class | cause | 30 d | 7 d | emitter |
|---|---|---|---|---|
| FAILED | `lr-transplant: REFUSED (lock-mismatch)` (46bc0436, a286f0c7) | 117 | 4 | lr-transplant.sh:372 → lr-handoff.sh:1560 → lr-fleet.sh:1878 `*) FAILED` |
| FAILED | lr-handoff said `verdict=NOTMOVED … precheck refused`; lr-fleet reports it as FAILED | ~27 | 0 | lr-handoff precheck → lr-fleet.sh:1878 catch-all `*) _lf_v=FAILED` |
| FAILED | `REFUSED (stub-beside-retired)` (8e18da3f) | 15 | 4 | lr-transplant.sh (stub-beside-retired) → lr-handoff.sh:1560 |
| FAILED | rsync `mkstempat tool-results/… No such file` during admit copy (58d3640a) | 1 | 1 | lr-transplant admit → lr-handoff.sh:1560 |
| PARKED | `CWD-GONE` (492a787a, all 103 dispatched by REROUTE) | 103 | 0 | lr-fleet.sh:272 / :1625 |
| PARKED | router `--max-wait expired mid-sweep` | 14 | 6 | lr-fleet rank (lr-fleet.sh:736 ff) |
| PARKED | every candidate already holds the session | 13 | 0 | lr-fleet rank |
| HELD | `HELD:bg-work` | 16 | 11 | lr-handoff.sh:1267 / lr-fleet.sh:1395 |
| HELD | `HELD:unreachable` (handoff-fire before /exit) | 7 | 7 | lr-handoff.sh:1964 |
| move FAILED | `source-ambiguous … HELD:unreachable` | 4 | 4 | lr-move-worker / lr-move-lib.sh:82 |
| move NOTMOVED | 7 aborted by operator · 3 slot-wait · 4 HELD (exit-readback 3, pane 1) · 1 still-busy · 1 became-limited · 1 composer-unreadable | 16 | 16 | lr-move-lib.sh:82 |

---

## A1-1 — Verdicts for daemon-dispatched recoveries reach nobody, so the originating session never learns the run failed

- **Symptom:** a FAILED, HELD or PARKED verdict is written only to `fleet/<run>/verdict.txt`. The session that typed `cc-lr recover` sees `QUEUED for the reconciler` and nothing more. Live case: 58d3640a FAILED at 03:41:02Z. Its `detached.log:42` reads `lr-fleet: no requester pane and the desk role did not take it — the verdict is on disk only`.
- **Frequency (MEASURED, python census of `detached.log` lines):**
  - 7 d: 59 of 68 detached verdicts reached nobody: RECOVERED 22, HELD 22, FAILED 9, PARKED 6. The remaining 9 runs left no such line.
  - 30 d: 348 of 455. All 9 daemon-driven FAILED in the 7 d window are among them.
- **Root cause (INFERRED from code; the count above is MEASURED):**
  - The poller dispatches `"$FLEET" --one … --from-daemon --detach` at lr-reset-poller.sh:1456 (request drain) and :2077 (REROUTE). It runs under launchd, so `CC_PANE_ID`, `ITERM_SESSION_ID` and `KITTY_WINDOW_ID` are all unset, and nothing sets `LR_FLEET_NOTIFY_PANE`. `grep -n LR_FLEET_NOTIFY_PANE` matches only lr-fleet.sh:1690.
  - With no requester, lr-fleet.sh:1690-1696 leaves `_lf_req` empty, and lr-fleet.sh:1892 falls back to `cc-notify --role desk`. That fails when no desk is alive, and the verdict then exists on disk only.
  - The request schema has no field that could carry the requester. bin/cc-lr:266 writes `{sid, at, requested_by:"cc-lr", mode, pane, config_dir}`, and `pane` there is the SUBJECT's pane (live: 58d3640a's request has `pane:"113"`, which is the subject).
  - A non-success verdict does not page.
- **Fix:**
  1. `cl_recon_queue` (bin/cc-lr:250-270) adds `reply_to` = the caller's `${CC_PANE_ID:-$KITTY_WINDOW_ID}`.
  2. The poller drain reads `.reply_to` next to `_rq_pane` (lr-reset-poller.sh:1227) and runs `LR_FLEET_NOTIFY_PANE="$_rq_reply" "$FLEET" --one …` at :1456.
  3. Hook-origin requests have no caller. For them, and whenever the notify at lr-fleet.sh:1891-1892 fails on a non-RECOVERED verdict, call `lr-page.sh` (damped per sid) instead of falling silent.
  4. Bats tests: (a) a stub FLEET that dumps its env, driven from a request carrying `reply_to:"P9"`, must show `LR_FLEET_NOTIFY_PANE=P9`; (b) with `LR_FLEET_DETACHED=1`, an empty requester, a failing stub cc-notify and stub results.tsv `recycle-in-place/FAILED`, assert the stub lr-page was called once.
- **Fix size:** M.
- **Conviction:** 85.
- **Receipt:**
  - `grep -c 'desk role did not take it' fleet/one-20261011T031606Z-58d3640a/detached.log` → 1.
  - census row `('lr-reset-poller request drain','FAILED','desk-not-taken') 9` (7 d).
  - `jq -c . requests/58d3640a-….cc-lr.json` → `{"sid":…,"requested_by":"cc-lr","mode":"recover","pane":"113",…}` (no requester).

## A1-2 — The bundle state log that `cc-lr status` reads never records how a run ended

- **Symptom:** `cc-lr status 58d3640a` prints `admitted 39m16s` with no NEXT, while `fleet/one-20261011T031606Z-58d3640a/verdict.txt` says `verdict=FAILED … lr-transplant exited 1` (03:41:02Z).
  - Successful runs end at `submitted` or `READY-NOT-SEEN`. HELD runs show as in flight forever.
- **Frequency (MEASURED, jq/python over `*/bundle-*/events.jsonl`):**
  - Over all 1,097 event lines, the state RECOVERED appears **0** times.
  - 30 d: 390 bundles. 166 have no `events.jsonl`: 132 of those match a fleet FAILED run (the Oct 2-4 storm) and 34 match no fleet run. Of the 224 bundles that do have events, 150 end non-terminal: submitted 58, HELD 45, READY 14, admitted 14, READY-NOT-SEEN 11, queued 7, relaunch-typed 1.
  - 7 d: 68 of 90 bundles end non-terminal.
  - Cross-check, 30 d: 41 bundles last at `submitted` and 8 at `READY-NOT-SEEN` match a fleet RECOVERED. 8 last at `HELD` and 1 at `admitted` match a fleet FAILED.
- **Root cause (INFERRED from code):**
  - `lrh_verdict` (lr-handoff.sh:766) writes stderr plus an optional mail, and never calls `lrh_state`.
  - Each terminal exit calls `lrh_verdict` only, then exits: FAILED at :1560 and :1969, STRANDED at :1977, NOTMOVED at :1501, :1520 and :1941, SWITCHED and SWITCHED-UNPROVEN at :1896, :1915 and :1917.
  - lr-fleet's verdict (lr-fleet.sh:1888) goes to `fleet/<run>/verdict.txt`, a different tree.
  - `klass()` (bin/cc-lr:2000-2004) counts only RECOVERED/DONE/ENGAGED as ok and FAILED/REFUSED/STALE/INDETERMINATE/PARKED as bad. Everything else, HELD and NOTMOVED included, is "run".
- **Fix:**
  1. `lrh_verdict` appends `lrh_state "$tok" verdict "$note"` as its first statement. One line covers all 9 exits.
  2. lr-fleet, right after writing verdict.txt, appends `lr_state_append "$bundle" "$_lf_v" fleet "$_lf_msg"`. The bundle is lr-handoff's stdout (`echo "$BUNDLE"`).
  3. `klass()` adds HELD, NOTMOVED and STRANDED as bad and SWITCHED as ok.
  4. Bats test: lr-handoff with a stub lr-transplant that exits 2. Assert `tail -1 events.jsonl | jq -r .state` = `FAILED`, and that `cc-lr status <bundle>` prints FAILED and a NEXT.
- **Fix size:** S.
- **Conviction:** 85.
- **Receipt:**
  - `cat */bundle-*/events.jsonl | jq -r .state | sed 's/:.*//' | sort | uniq -c` → no RECOVERED row (probed 237 … queued 8).
  - `~/.claude/bin/cc-lr status 58d3640a` → `58d3640a/bundle-20261011T032034Z admitted 39m16s token …`.
  - `fleet/one-20261011T031606Z-58d3640a/results.tsv` → `recycle-in-place/FAILED … 2026-10-11T03:41:02Z`.

## A1-3 — The REROUTE arm retries a deterministic refusal every 15 minutes with no cap

- **Symptom:** three parked sessions produced 235 FAILED/PARKED runs in 3 days.
  - 46bc0436: 116 runs of `REFUSED (lock-mismatch) — the lock names .claude-quaternary as the owner, not .claude-tertiary`.
  - 492a787a: 103 runs of `CWD-GONE`.
  - 8e18da3f: 15 runs of `stub-beside-retired`.
  - Every one of those runs was a full `lr-fleet --one` dispatch, and each one mailed a desk that was not there (A1-1).
- **Frequency (MEASURED):**
  - poller.log REROUTE dispatches: 46bc0436 47 (10-02), 60 (10-03), 12 (10-04); 492a787a 55, 59, 7; 8e18da3f 15 (10-04).
  - That is 235 of 338 non-success fleet verdicts over 30 d (70%), and 8 of 16 over 7 d.
  - 46bc0436 had already been filed `.exhausted.json` by the request lane at 2026-10-01T20:16:29Z (`attempts:3`), and REROUTE drove it 119 more times.
  - The storm ended at `2026-10-04T08:50:18Z REROUTE-STAY 46bc0436 … resets in 582s` — that is, the account reset ended it, not a cap.
- **Root cause (INFERRED from HEAD code):**
  - `reroute_parked` (lr-reset-poller.sh:2034-2087) limits repeats only with the 15-min mark file (:2060-2062).
  - It keeps no attempt counter. The request lane has `LR_REQUEST_MAX_ATTEMPTS` and exhausted filing plus a page at :1419-1425.
  - It never reads back the verdict of its previous dispatch.
  - It never checks CWD-GONE, which § 2 skips at :1695.
  - None of this changed after the storm: `git log -S're-driving a transplanted session'` → only b4eef1cb8 (2026-09-27).
- **Fix:**
  1. Keep `$REROUTE_DIR/<sid>.tries` with `n` and the last verdict reason, read from `$RESULTS/<sid>.log` or the newest `fleet/one-*-<sid8>/verdict.txt`.
  2. After `LR_REROUTE_MAX` = 3 dispatches with the same non-transient reason (REFUSED:*, CWD-GONE, stub-beside-retired), stop and send one damped page, `reroute exhausted`.
  3. Pre-check `[ -d "$cwd" ] || lf_cwd_recreatable` before the dispatch.
  4. Bats test: a stub FLEET writes `verdict=FAILED … REFUSED (lock-mismatch)`. Call `reroute_parked` 6 times, back-dating the mark each time. Assert exactly 3 FLEET invocations and 1 stub-page call.
- **Fix size:** M.
- **Conviction:** 80.
- **Receipt:**
  - `grep -E ' REROUTE [0-9a-f]{8}' poller.log | awk '{print substr($1,1,10), substr($3,1,8)}' | sort | uniq -c` (counts above).
  - `jq -c . results/46bc0436-*.exhausted.json` → `attempts:3 … ts 2026-10-01T20:16:29Z`.
  - Last storm line: `2026-10-04T07:42:31Z REROUTE 46bc0436`.

## A1-4 — Early "already TRANSPLANTED, nothing to do" exits write no verdict and send no mail

- **Symptom:** a detached `--one` run leaves a fleet dir containing only `detached.log` and `results.tsv`. `cc-lr rotate` and the requester wait on a verdict that never arrives.
- **Frequency (MEASURED, fleet dirs with detached.log and no verdict.txt):** 8 over 30 d, 3 over 7 d (4d059264, 7f5deb68, 1c0f7f90 at 2026-10-10T05:32Z). All 8 end with `already TRANSPLANTED→… ; nothing to do`.
- **Root cause (INFERRED from code):** `case "$_tl" in 0) exit 0` at lr-fleet.sh:1759, :1775 and :1804 exits before the verdict.txt and mail block at lr-fleet.sh:1862-1897.
- **Fix:** replace the three `exit 0` with `lf_row "$SID" "$pane" "$pane" "$acct" "-" "skipped" "already transplanted; a live holder carries it"`, then fall through to the report and mail tail, which already maps `skipped*` → SKIPPED (:1870). Bats test: stub `lr_holder_count` returns 1 and `lr_transplanted_to` returns a cfg; with `LR_FLEET_DETACHED=1`, assert verdict.txt contains `verdict=SKIPPED`.
- **Fix size:** S.
- **Conviction:** 75.
- **Receipt:** `for d in fleet/*/; do [ -f $d/verdict.txt ] || [ ! -f $d/detached.log ] || …; done` → 8 directories, each with tail `lr-fleet: --one <sid> — already TRANSPLANTED→next and a live process holds it; nothing to do`.

## A1-5 — Orphaned in-flight state: counts against each bound the code sets

MEASURED at 03:52-04:05Z. None of the items below is a live process. Each is a record that outlived its bound.

| record | bound (code) | count over bound | notes |
|---|---|---|---|
| bundle whose last event is `admitted` | admit token TTL 1020 s (scripts/lib/capacity-admit.sh:1082; value printed by lr-handoff.sh:1475) | 14 over 30 d, 9 over 7 d | 7 are move-lane `gate-exempt … placed_by=cc-lr-move`, whose verdict is in `move/<batch>/<sid>.json`. 7 token-holding lr-fleet runs (07e30aeb, c060ddcd, 7c8201f8, ac0f0123, 29596290, ebbc7b61, 58d3640a) ended with no terminal line (A1-2). |
| bundle at `queued` / `relaunch-typed` | none | 7 / 1 | All are at least 18 h old. |
| capacity-admit tokens whose run has ended | TTL 1020 s | 2 (5507881f issued 03:21Z, 58d3640a issued 03:25Z) | lr-handoff never deletes its token on the FAILED (:1560) or HELD (:1964) exit. The damage is limited to 1020 s, because `cc_capacity_tokens_inflight` counts only live tokens. |
| request files in `requests/` | launchd StartInterval 600 s | 7 (ages 19-36 min) | 6defb493 (2 requests) and 516b9da9 have no fleet run dir at all. 58d3640a has a second stop-failure request (03:33Z), written while its own run was in flight. |
| `runs/by-sid/*.active` claims | steal on dead holder (lr-lib.sh:602-620); no age bound | 75, all with dead holders (`ps -p`), 0 live | The oldest is from 2026-09-23. Nothing releases them when a detached driver exits. Harmless by design. |
| transplant `locks/*.lock` | lr-lock.py evidence-TTL (lr-lock.py:18-40); CUSTODY locks never expire | 93 locks, 84 older than 1 day | The reaper names 84 sids CLAIMED-NOT-LIVE. Oldest: 46bc0436, age 287 h. |
| fleet detached run with no verdict | none (no wall-clock bound on the lr-handoff call at lr-fleet.sh:1000) | 8 over 30 d | Same population as A1-4. |

## A1-6 — CLAIMED-NOT-LIVE log spam: 72.5% of poller.log over 7 days, naming 84 dead claims every tick and acting on none

- **Symptom:** every tick re-logs one CLAIMED-NOT-LIVE line per dead transplant claim. poller.log has reached 24 MB, and the real tick lines are buried among them.
- **Frequency (MEASURED):**
  - 61,663 of 85,012 poller.log lines since 2026-10-04T03:52Z, covering 84 distinct sids.
  - `faults/` holds 84 records, all claim kind `lock`: 24 first seen within 7 d, 60 within 30 d.
- **Root cause (INFERRED from code):** lr-reset-poller.sh:1766-1768 logs every `cc-limited --reaper --persist` line on every tick. It neither de-duplicates nor pages, and nothing escalates a claim that stays stale.
- **Fix:**
  1. Keep the last-seen set in `$STATE/reaper.seen`.
  2. Log only claims that appear or clear, plus one `CLAIMED-NOT-LIVE n=84` summary per tick.
  3. Page once per sid when it first passes 24 h.
  4. Bats test: a stub `CC_LIMITED_BIN` prints the same 3 lines on two ticks. Assert tick 2 adds exactly 1 line to poller.log.
- **Fix size:** S.
- **Conviction:** 75.
- **Receipt:** `awk '$1>="2026-10-04T03:52" && /CLAIMED-NOT-LIVE/' poller.log | wc -l` → 61663, and `awk '$1>="2026-10-04T03:52"' poller.log | wc -l` → 85012.

## A1-7 — `cc-lr status --all` does not finish within 200 s under load, and prints nothing while it runs

- **Symptom:**
  - `/usr/bin/time -p timeout 200 ~/.claude/bin/cc-lr status --all` → `real 200.04 user 20.79 sys 35.07`, rc 124, 0 bytes on stdout, at loadavg 185.57.
  - `cc-lr status 58d3640a` → `real 0.78` at loadavg 317.
- **Frequency:** measured once, as the brief asked. The brief's earlier observation of more than 120 s is consistent.
- **Root cause:** INFERRED from code; the cost is ESTIMATED from measured unit costs.
  - bin/cc-lr:1990-1996 calls `lr_registry_live_rows` once per distinct sid. That is 110 sids, measured with `ls */bundle-*/events.jsonl | cut -d/ -f1 | sort -u | wc -l`.
  - Each call forks `jq` on every registry file (lr-lib.sh:284-287). There are 37 files (`ls ~/.claude/cc-registry/*.json | wc -l`).
  - That gives ≥ 4,070 jq forks. One measured jq fork takes `real 0.02`, so the forks alone cost ≥ 81 s, before the `$( )` subshell forks and load spikes.
  - One sid costs 0.78 s ≈ 37 forks × 0.02 s, which matches the model.
  - All output is printed by a single awk END block, after the loop, so a timeout leaves nothing on screen.
- **Fix:**
  1. Build the live set once: one `jq -r '[input_filename,(.session_id//.sessionId),.pid]|@tsv' "$regdir"/*.json` and one `ps -o pid= -p <list>`, then membership is a string test.
  2. Render rows as they are read, or cap `--all` to the newest N runs by default.
  3. Bats test: 40 stub registry files and 100 bundles with a PATH-shim `jq` that counts its invocations. Assert the count is ≤ 3.
- **Fix size:** S.
- **Conviction:** 65. Not profiled; `cl_events_bulk` is a single jq, so it is unlikely to be the cost.
- **Receipt:** commands and outputs as listed above. `/tmp/a1-status-all.out` is 0 bytes.

---

## Ruled out

- **`results/*.json` as a run census.** These files are per sid and overwritten on each run. The `verdict` field reads `dispatched`, which records the dispatch, not the outcome (64 files in the mode/rc schema). They cannot count runs.
- **`fleet-drive-ledger.jsonl`.** 3 lines, the last on 2026-09-10. Dormant.
- **`fire-fail/`.** 7 counters, last written 2026-09-22: 4 inside 30 d, 0 inside 7 d. Dormant lane.
- **`runs/` and `one-slots/`.** `runs/` holds only claims (A1-5). `one-slots/` has 0 entries, so no slot leak.
- **"The REROUTE storm was fixed."** HEAD `reroute_parked` has no counter. The storm stopped at REROUTE-STAY near next4's reset (poller.log 2026-10-04T08:50:18Z).
- **`faults/` as a separate failure class.** All 84 records are the reaper's lock-claim records, the same population as A1-6.
- **The live 58d3640a run as a stuck process.** Its driver finished at 03:41:02Z (FAILED, rsync `mkstempat … tool-results` ENOENT during the admit copy). What remains stale is the state log (A1-2), plus a token that will not be released until its TTL (A1-5).

## Uncertain

- **Why the 132 storm runs on Oct 2-4 skipped the lr-handoff precheck.** Their stderr begins at `lr-transplant: REFUSED`, so they wrote no `events.jsonl` (probably the stranded/confirm path, `LF_STRANDED_TO`). Not traced.
- **About 27 FAILED runs (30 d) where lr-handoff said NOTMOVED.** lr-fleet's catch-all at lr-fleet.sh:1878 maps them to FAILED. The count is a pattern match on stderr tails and was not re-verified per run.
- **Move batch 20261006T060534Z.** Its `summary.json` says `verdicts:"none"`, yet 7 per-session MOVED records exist. The summary may have been written before the workers finished.
- **Who stood behind the desk-not-taken line.** It cannot tell "no desk alive" from "desk resolution failed". Runs labelled `interactive/none` (no `[daemon-run:]` tag), 154 PARKED among them over 30 d, may include REROUTE dispatches. Not split.
- **A1-7's cost model** is estimated from unit timings; the run was not profiled.
- **The admit-token leak's effect on admission decisions.** Limited by TTL; impact not measured.
