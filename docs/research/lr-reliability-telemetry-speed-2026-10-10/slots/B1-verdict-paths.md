# B1 — verdict paths: driver → requesting session, and every path that ends in silence

Slot B1-verdict-paths · trunk 110ea9a64 · read-only · measured 2026-10-11T03:49-03:58Z

## Answer first

- **The operator's gap is two separate defects.** (1) Every `lr-fleet --one` that the launchd poller fires mails its verdict to `cc-notify --role desk`. That role file does not exist, so the verdict is written to disk only: **348 of 446** verdicts were dropped this way, 134 of them `FAILED`. 58d3640a's `verdict=FAILED` (03:41:02Z) and 5507881f's `HELD:unreachable` are among them. (2) While the reconciler is live (`recon.on`, mode `act`), `cc-lr recover` writes a request that does not record who asked. The reconciler's `mail_requester` is never called. The doctrine still says "END THE TURN; the verdict comes back as MAIL", so the asking session waits for mail that never comes.
- **The status surfaces hide the failure.** `cc-lr status` reads bundle events only. A failed transplant writes no final bundle state, so 58d3640a shows `admitted 28m49s` while its run verdict says FAILED. A request the reconciler holds shows `no runs` (6defb493, 516b9da9). `cc-lr rotate` leaves recovers queued to the reconciler out of its verdict, which is why it printed "7 still in flight": all 7 were move rows.
- **A stuck poller tick holds back only what it consumes:** move batches (waited 14m56s), hook requests, and `cc-lr repair` requests. Callers are told "still in flight" for work that has not started.
- **No driver records a requester session id.** Only a pane id is recorded, and only by `move`, `switch`, `upgrade` and `repair`. `recover` while the reconciler is live records none. The `repair` pane is lost at the poller-to-`lr-fleet` hop, because `LR_FLEET_NOTIFY_PANE` has no writer anywhere in the repo.

## Verdict-path table

"Silent" means the requesting session gets no verdict, even if something reached Notification Center.

| # | Path | file:line | What is written | What is mailed, and to whom | Silent |
|---|---|---|---|---|---|
| 1 | `cc-lr recover` while the reconciler is live → `.cc-lr.json` → reconciler | bin/cc-lr:598-600, 250-270; lr_recon/report.py:736 | `requests/<sid>.cc-lr.json` (no requester); `recon/sessions/<sid>.json`; cohort pages latch | Cohort OPEN/DELTA/CLOSE pages → `cc-notify --role desk` (exit 3) → lr-page Notification Center (NC). Never the requester. | **YES** |
| 2 | `cc-lr recover` while the reconciler is NOT live → `lr-fleet --one --detach`, normal completion | lr-fleet.sh:1690-1697, 1846-1897 | `fleet/<run>/verdict.txt`, `results.tsv` | `cc-notify <caller pane>` | no (67 delivered, 31 unverified) |
| 3 | Detached `lr-fleet` child exits early (already transplanted, ambiguous prefix, census rc 5/6, no transcript) | lr-fleet.sh:1710, 1759, 1775, 1788, 1789, 1798, 1804 | `detached.log` only | nothing (the parent already printed "the verdict arrives as mail") | **YES** |
| 4 | Detached `lr-fleet` child gets SIGTERM or SIGKILL | lr-fleet.sh:1838 (the only trap is the slot release) | partial `results.tsv` | nothing | **YES** |
| 5 | Poller-fired `lr-fleet` (hook request, `cc-lr repair`, reroute, `.cc-lr.json` when the reconciler is down) | lr-reset-poller.sh:1456, 2077 → lr-fleet.sh:1892 | `verdict.txt`; `results/<sid>.json` `verdict:"dispatched"` | `cc-notify --role desk` → exit 3 → phone fallback (damped or unwired) | **YES** |
| 6 | `lr-handoff` verdict on a limit (non-voluntary) run | lr-handoff.sh:766-770 | stderr only | nothing by design; the parent is meant to mail. Under the reconciler (act.py:105) no parent mails. | yes under the reconciler |
| 7 | `lr-handoff` transplant FAILED after admit | lr-handoff.sh:1556-1561 | stderr; the bundle's last state stays `admitted` | nothing | **YES** on the `cc-lr status` surface |
| 8 | Poller request unreadable (exception in the python helper) | lr-reset-poller.sh:1214-1226 | `results/<name>.malformed.json`; poller.log `REQUEST-SKIP` | nothing | **YES** |
| 9 | Poller request loop fails to parse under bash 3.2 | plist StandardErrorPath → poller.launchd.err | stderr only | nothing | **YES** (historical) |
| 10 | Poller request exhausted after N attempts | lr-reset-poller.sh:1425 | `results/<sid>.exhausted.json` | `lrp_page` → NC (operator, not the requester) | partly |
| 11 | Move-batch summary | lr-move-batch.sh:76-97 | `move/<b>/summary.json`, `<sid>.json` | `cc-notify $BY >/dev/null 2>&1 \|\| true` | unknown (the outcome is not recorded) |
| 12 | Move worker finishes after the watch bound | lr-move-batch.sh:226 | a late `<sid>.json` | nothing (the summary was already mailed) | **YES** |
| 13 | Upgrade/switch/marker drain | lr-upgrade.sh:138-147, 1148-1156, 1898-1904 | `results/switch-*.json`, `upgrade-*.json`, `markers-*.json` | `lru_mail`: outcome sent to /dev/null; requester `?` or empty → nothing; `poller-auto` → desk (unset) | partly; the outcome is not recorded |
| 14 | Run never starts because the consumer tick is stuck | lr-reset-poller.sh:285-314, 2127; bin/cc-lr:1452, 1688 | the request file sits there | nothing; cc-lr prints "still in flight" | **YES** |
| 15 | Reconciler page sink fails | lr_recon/report.py:584-598 | latch saved BEFORE the emit; `failures` counter is never read | nothing, and never retried | **YES** |
| 16 | `cc-notify` phone fallback | bin/cc-notify:514-521 | the damp stamp is written even when the push failed or is unwired | "operator was already phoned", which is false | misleading |

## How each driver records the requester (Q3)

| Driver | Requester field | Carried to the verdict? |
|---|---|---|
| `cc-lr recover`, reconciler live | `requested_by:"cc-lr"`. `pane` is the TARGET's pane, not the requester's (bin/cc-lr:262-266). Measured: `{"sid":"58d3640a…","at":1791689080,"requested_by":"cc-lr","mode":"recover","pane":"113","config_dir":"/Users/chrisren/.claude-next"}` | **No.** No address exists, and `mail_requester` has no caller. |
| `cc-lr recover`, reconciler not live | Taken from the caller's environment (`CC_PANE_ID`, then `ITERM_SESSION_ID`, then `KITTY_WINDOW_ID`) → `LR_FLEET_REQUESTER` (lr-fleet.sh:1690-1699) | Yes, but only when the child finishes normally (rows 2-4). |
| `cc-lr repair` | `requested_by` = `cl_this_pane` (bin/cc-lr:2118, 2124) → `requests/cc-lr-repair-<sid>.json` | **No.** The poller fires `lr-fleet` with no `LR_FLEET_NOTIFY_PANE`, a variable no code in the repo ever sets (`git grep LR_FLEET_NOTIFY_PANE` finds only its reader at lr-fleet.sh:1690). |
| Stop-failure hook | `requested_by:"stop-failure-marker"`, `source_pane` = the limited session itself | It goes to the desk (row 5). |
| `cc-lr move` / rotate batch | plan.json `requested_by` = `cl_this_pane` (bin/cc-lr:1388-1393). Measured: `223` for the live batch. | Yes, through the summary mail, but its outcome is not recorded. |
| `cc-lr switch`/`upgrade`/`repair-markers` | Queued `requested_by` = pane (bin/cc-lr:1013, 2363, 2211) | Yes, through `lru_mail`, but its outcome is not recorded. |
| Any driver | **No requester SESSION id (`CLAUDE_CODE_SESSION_ID`) is recorded anywhere.** A pane id goes stale when the pane recycles. | — |

---

## Findings

### B1-1 — Poller-fired lr-fleet verdicts go to an unset desk role and stay on disk
- **Symptom:** `fleet/one-20261011T031606Z-58d3640a/verdict.txt` says `verdict=FAILED rc=1 … lr-transplant exited 1`. Its `detached.log` says `cc-notify: verdict=unresolvable … fallback=phone-damped … lr-fleet: no requester pane and the desk role did not take it — the verdict is on disk only`. 5507881f's `HELD:unreachable` went the same way.
- **Frequency (MEASURED):** loop over `~/.reso/limit-recover/fleet/one-*/`. 509 runs, 446 with `verdict.txt`. **348 dropped to the desk**, by token: 154 PARKED, **134 FAILED**, 32 RECOVERED, 28 HELD:*. 98 were sent to a requester pane (67 `delivered`, 31 `unverified`). From 2026-10-01 on: 347 dropped, 36 sent. On 2026-10-10 and 10-11: 20 dropped, 5 sent.
- **Root cause:** lr-fleet.sh:1690-1697 takes the requester from the invoking environment. The launchd poller has no `CC_PANE_ID`, `ITERM_SESSION_ID` or `KITTY_WINDOW_ID`. lr-reset-poller.sh:1456 and :2077 do not pass `LR_FLEET_NOTIFY_PANE`, even when the request names a pane in `requested_by` (`cc-lr repair`). The fallback at lr-fleet.sh:1892 is `--role desk` only, and `~/.claude/cc-roles/desk` does not exist (`ls ~/.claude/cc-roles/` lists docs-lead, drain-lead, opus55-lead, orchestrator). The reconciler's `default_page` (report.py:511-522) has an lr-page leg; lr-fleet's fallback does not.
- **Fix:**
  - (a) lr-reset-poller.sh:1456: when `_rq_by` matches `^[0-9]+$`, prefix the call with `LR_FLEET_NOTIFY_PANE="$_rq_by"`.
  - (b) lr-fleet.sh:1891-1896: when there is no requester, or cc-notify exits non-zero or prints anything but `verdict=delivered`, also call lr-page.sh. Use the ladder from lr-fleet.sh:1270, the same leg report.py uses.
  - (c) Append every detached verdict as one JSON line to `$STATE/verdicts.jsonl`, keyed by sid, so a status surface can read it.
  - Bats tests: (1) A detached run with no pane env vars, a `CC_NOTIFY_BIN` stub that exits 3 for `--role desk`, and an `LF_PAGE_BIN` stub: the page stub receives the `verdict=FAILED` line. (2) A poller test with `cc-lr-repair-<sid>.json` holding `requested_by:"223"` and an `LR_FLEET_BIN` stub that dumps its environment: the stub saw `LR_FLEET_NOTIFY_PANE=223`.
- **Fix size:** S
- **Conviction:** 85
- **Receipt:** the counting loop above (348/446). `ls ~/.claude/cc-roles/` shows no desk file. lr-fleet.sh:1892.

### B1-2 — While the reconciler is live, `cc-lr recover` promises mail that cannot arrive
- **Symptom:** `cc-lr recover 58d3640a`, `6defb493` and `5507881f` (03:24:40-43Z) printed `QUEUED for the reconciler`. In the rotate fan-out, `cmd_recover_limited` also prints "Verdicts arrive as mail; END THE TURN" (bin/cc-lr:516). The doctrine (~/.claude/commands/limit-recover.md:79, 132-134) says to end the turn and wait for mail. The reconciler is holding all three as `PRE-MOVE/WAIT_RESET, wakes at 04:00Z`, and no session has been told.
- **Frequency (MEASURED):** 3 of 3 live `.cc-lr.json` requests have no requester address. The cohort latch `recon/cohorts/next-7d-1791691200.pages.act.json` = `{"open":…,"delta":…}` and has no `mail` key. `~/.reso/limit-recover/claimed/` holds 95 files and **0** `*.cc-lr.json`, because the reconciler moves a request there only on `NOT_NEEDED` (`__main__.py:245-252`).
- **Root cause:** `cl_recon_queue` (bin/cc-lr:262-266) records no requester pane or session. `Reporter.mail_requester` (report.py:736) has no production caller: `git grep mail_requester` finds only its definition and test_report.py:152, 187, 609. `_report` (`__main__.py:1088-1108`) only pages.
- **Fix:**
  - Add `requester_pane:(cl_this_pane)` and `requester_sid:$CLAUDE_CODE_SESSION_ID` to the request in `cl_recon_queue`.
  - Carry them on `T.Request` and the record.
  - In `_report`, for each record whose request origin is `cc-lr`, call `rep.mail_requester` when the record changes bucket (WAIT with ETA, ESCALATED, terminal). This needs a per-record latch key, not the one per-cohort `mail` key.
  - Until then, change bin/cc-lr:269 and :516 to say "no mail will come — check `cc-lr status --cohort`".
  - Tests: extend tests/cc-lr-request.bats:77 to assert `requester_pane`. Add an lr_recon unittest: a cohort with a cc-lr request carrying `requester_pane:"7"` reaches CLOSE, and the mail sink is called with pane `7` and the outcome.
- **Fix size:** M
- **Conviction:** 80
- **Receipt:** `cat requests/58d3640a-….cc-lr.json`; `git grep -n mail_requester`; the latch file contents above.

### B1-3 — `cc-lr rotate` leaves reconciler-queued recovers out of its verdict
- **Symptom:** "0 rotated · 0 not · 7 still in flight after 600s". The 7 are the move-batch rows. The 3 recovers queued at the same moment are not counted at all.
- **Frequency:** every `rotate` run while the reconciler is live (`recon.on` since 2026-10-10 14:47Z, mode `act`). Measured: 1 of 1 live case.
- **Root cause:** `cmd_recover` returns at bin/cc-lr:598-600 before the `CL_RL_OUT` append at :647. `cmd_rotate` (bin/cc-lr:1641-1688) counts only the `recover` and `batch` rows of `CL_RL_OUT`.
- **Fix:**
  - `cl_recon_queue` appends `queued\t<sid>\t<pane>\t<request path>` to `CL_RL_OUT`.
  - `cmd_rotate` prints one `QUEUED → reconciler (cc-lr status --cohort)` line per queued recover and counts them in a fourth bucket, `queued`.
  - Bats test: rotate with `lr_recon_live` stubbed true and a single limited row; the output contains `queued` and that sid8.
- **Fix size:** S
- **Conviction:** 85
- **Receipt:** bin/cc-lr:598-600, 647, 1688.

### B1-4 — Early exits and signals in the detached lr-fleet child skip the verdict block
- **Symptom:** the parent printed "DETACHED … the verdict arrives as mail" (lr-fleet.sh:1703). The child then exits with no `verdict.txt` and no mail.
- **Frequency (MEASURED):** 8 of 509 runs have `detached.log` but no `verdict.txt`, all from the exit-0 "already TRANSPLANTED … nothing to do" path (ac0f0123 ×4, c28362b6, 4d059264, 7f5deb68, 1c0f7f90). Error exits (2/5/6) and signal deaths: none on disk; their frequency cannot be measured because they leave no record.
- **Root cause:** `exit` at lr-fleet.sh:1710, 1759, 1775, 1788, 1789, 1798 and 1804 runs before the verdict block at :1846-1897. The only EXIT trap is `lf_one_slot_release` (:1838), and it is installed after those exits.
- **Fix:**
  - Move :1846-1897 into `lf_detached_verdict(rc)`.
  - When `LR_FLEET_DETACHED=1`, install `trap 'lf_detached_verdict $?' EXIT` and `trap 'exit 143' TERM INT` before the first `lf_resolve_sid`.
  - With no results row: rc 0 maps to `verdict=NOOP` (already held). Any other rc maps to `FAILED` "driver exited rc N before lf_one" (or "signal").
  - Bats tests: (1) `LR_FLEET_DETACHED=1 --one <ambiguous prefix>` writes `verdict.txt` with `verdict=FAILED` and the notify stub is called. (2) A stubbed `lf_one` that sleeps, killed with TERM, leaves `verdict.txt` naming the signal.
- **Fix size:** S
- **Conviction:** 80
- **Receipt:** the no-verdict loop above; lr-fleet.sh:1838.

### B1-5 — A failed transplant leaves the bundle `admitted`, and `cc-lr status` reads only bundles
- **Symptom:**
  - `cc-lr status 58d3640a` prints `admitted 28m49s token …` (measured, `/usr/bin/time -p`: real 1.00 s). Its run had already ended FAILED at 03:41:02Z, and writer pid 96991 is dead (`ps -p 96991` prints nothing).
  - `cc-lr status 6defb493` and `cc-lr status 516b9da9` print `no runs under … for '<sid8>'` (real 0.08 s). The reconciler record for each says `PRE-MOVE/WAIT_RESET`, wakes 04:00Z.
- **Frequency (MEASURED):** 14 of 224 bundles end on `admitted`, a state that is not final. At least one is a FAILED run (58d3640a) and at least three are armed successes (1c0f7f90, 4d059264, 7f5deb68 were later found "already TRANSPLANTED … live process"). So `admitted` is ambiguous.
- **Root cause:**
  - lr-handoff.sh:1556-1561 calls `lrh_verdict FAILED` and exits without calling `lrh_state`.
  - `lrh_verdict` returns at :770 (stderr only) for limit runs.
  - The EXIT trap at :864 only drops the git lock.
  - `cmd_status` (bin/cc-lr:1927-1963) never reads `fleet/*/verdict.txt`, `requests/` or `recon/sessions/`.
- **Fix:**
  - (a) Add `lrh_state FAILED transplant "rc=$_lrh_txrc"` before `exit` at :1561. Extend the EXIT trap to append `exited rc=$?` whenever `lr_state_current` is not a final state (size S).
  - (b) `cmd_status <sid>`: when the newest bundle is not in a final state and its writer pid is dead, print the newest `fleet/one-*-<sid8>/verdict.txt`. When there is no bundle, print the reconciler record's phase/substate/next_action and any unclaimed `requests/<sid>*.json` with its age (size M).
  - Bats tests: (1) lr-handoff with an `lr-transplant` stub that exits 2: the bundle's last state is `FAILED`. (2) `cc-lr status` with a fixture `recon/sessions/<sid>.json` and no bundle prints `WAIT_RESET`.
- **Fix size:** M
- **Conviction:** 80
- **Receipt:** the three status commands above; `tail -4 …/bundle-20261011T032034Z/events.jsonl` (last state `admitted` 03:25:26Z); `fleet/one-20261011T031606Z-58d3640a/results.tsv` shows `recycle-in-place/FAILED … 2026-10-11T03:41:02Z`.

### B1-6 — Work the stuck tick never started is reported as "still in flight"
- **Symptom:** batch `20261011T032613Z-next-next4-91646` was requested at 03:26:13Z. poller.log shows `MOVE-BATCH started pid 15968` at 03:41:09Z (14m56s later). In the meantime `cc-lr move`/`rotate` reported "still in flight; the workers keep running", but no worker existed. Hook request 516b9da9 (ts 03:24:21Z) is still unclaimed at 03:52Z.
- **Frequency:** 1 batch and 1 hook request in the live case (measured). A history count is not measurable: neither the wait loops nor the poller record how long a request waited to be claimed.
- **Root cause:**
  - The poller is a single-instance launchd job (`StartInterval` 600). `launchctl kickstart` on a running job does nothing, so the re-kick at bin/cc-lr:~1431 is inert.
  - `lrp_move_kick` (lr-reset-poller.sh:285-314) runs only at the start of a tick, so new work waits for the whole current tick. Here that tick was stuck in the parked loop at :2127.
  - bin/cc-lr:1452 and :1688 do not check whether `move/requests/<batch>.json` is still unclaimed (no `request.claimed.json`).
- **Fix:**
  - In both wait loops, when the deadline passes and the request is unclaimed, print `NOT STARTED — the poller has not claimed it; tick pid <$STATE/poller.lock/pid> running <age>s` and return a distinct rc (4).
  - Make the same check in `cmd_status` for `requests/*.json` (see B1-5b).
  - The tick-length cure itself belongs to another slot.
  - Bats test: `cmd_move` with a poller stub that never claims and `--wait 1` prints `NOT STARTED` and the holder pid from a fixture `poller.lock`.
- **Fix size:** S
- **Conviction:** 75
- **Receipt:** `tail poller.log` (03:21:21Z → 03:41:09Z gap); `batch.log` (`admitted; 7 worker(s) started` 03:42:30Z); lr-reset-poller.sh:216 (`LOCKD`).

### B1-7 — cc-notify says "already phoned" when the phone was never reached
- **Symptom:** all 348 desk-dropped verdicts log either `fallback=phone-damped — the operator was already phoned` or `phone-unwired`. None logs `phoned`.
- **Frequency (MEASURED):** across `fleet/one-*/detached.log`: 278 `phone-damped`, 70 `phone-unwired`, **0** `phoned`. pages.log: `phone=skipped` in 304 of 305 lines.
- **Root cause:** bin/cc-notify:521 writes the damp stamp unconditionally after `rc=$?` (:520). An unwired push (rc 3) therefore damps every page for the next `PHONE_DAMP_TTL` (1800 s, measured from the log text), and :514-516 reports those pages as "already phoned". The damp key is the reason (`desk-role-unset`), so the text of every later verdict is discarded.
- **Fix:**
  - Write the stamp only when `rc=0`.
  - Bats test: a push-send stub that exits 3, called twice; the second call prints `fallback=phone-unwired`, not `phone-damped`.
- **Fix size:** S
- **Conviction:** 85
- **Receipt:** the fallback tally loop above; bin/cc-notify:514-521.

### B1-8 — A failed reconciler page is latched as sent and never retried
- **Symptom:** a page-sink exception increments `self.failures`, and the latch already says the page was sent.
- **Frequency:** not measurable. `failures` lives only in memory and is never persisted. The lr-page leg currently posts (pages.log: 305 of 305 `os=posted`).
- **Root cause:** report.py:596-598 calls `_save(latch)` before `_emit`. `_emit` (:584-590) swallows the exception. `failures` is read nowhere (`git grep` finds only report.py:545 and :590).
- **Fix:**
  - Emit first and save the latch only on success; otherwise save `{key:{"failed_at":t}}` and retry after `REFIRE_S`.
  - Export `failures` into `recon/heartbeat` and `readout.line`.
  - Unittest: a page sink that raises once; on the second pass the page is emitted again.
- **Fix size:** S
- **Conviction:** 65
- **Receipt:** report.py:584-598.

### B1-9 — Mail outcomes are thrown away in the move, switch and upgrade drains
- **Symptom:** whether the requester received the mail is not recorded anywhere.
- **Frequency:** not measurable for that reason. `poller-auto` drain news always goes to the unset desk (lr-upgrade.sh:143, 146).
- **Root cause:** `lru_mail` (lr-upgrade.sh:138-147) and `summary` (lr-move-batch.sh:93-96) send to `>/dev/null 2>&1 || true`. A requester of `?` or empty returns 0 without sending.
- **Fix:**
  - Capture the `cc-notify: verdict=` token into the result or summary json as `mail_verdict`.
  - On anything other than `delivered`, call lr-page.sh.
  - Bats test: a notify stub that exits 4; `summary.json.mail_verdict == "unverified"` and the page stub was called.
- **Fix size:** S
- **Conviction:** 70
- **Receipt:** lr-upgrade.sh:138-147; lr-move-batch.sh:93-96. The live batch's `summary.json` has no mail field.

### B1-10 — Request-loop crashes go to a stderr log nothing reads
- **Symptom:** poller.launchd.err holds 1041 `bad substitution` errors (23136 lines in total). The last was written 2026-09-29 and went unnoticed for 12 days.
- **Frequency (MEASURED):** `grep -c 'bad substitution'` = 1041. They come from lines 1111 (380), 1028 (248), 1128 (140), 1125 (114) and 1088 (57) of the then-installed request-drain section. The cause was a python heredoc inside `<( )` under bash 3.2. While it failed, the request lane wrote no poller.log line, no result and no mail.
- **Root cause:** the plist's `StandardErrorPath` is the only sink, and nothing reads that file. `git grep poller.launchd.err` finds only the plist and a comment at lr-reset-poller.sh:147. The heredoc defect itself is gone: the current reader uses `python3 -c` (:1214-1222).
- **Fix:**
  - At the end of each tick, compare the size of poller.launchd.err with the last recorded size. On growth, log `STDERR-GREW +N lines: <last line>` to poller.log and call `lrp_page` once per day.
  - Bats test: append to a fixture err file between two dry ticks; poller.log contains `STDERR-GREW`.
- **Fix size:** S
- **Conviction:** 70
- **Receipt:** the grep above; `stat poller.launchd.err` → Sep 29 03:54 local.

---

## Ruled out
- **"The 3 `cc-lr recover` requests sat behind the stuck poller tick."** Not so. While the reconciler is live the poller skips `*.cc-lr.json` (lr-reset-poller.sh:1205). The reconciler's heartbeat was fresh: progress_wall 03:47:41Z, pid 9004. It processed all four sids during the stuck tick (`rebucket … LIMITED` at 03:32:50Z and 03:40:11Z in `recon/events.jsonl`) and holds them as `WAIT_RESET` until 04:00Z by design. The stuck tick held back only the hook request 516b9da9 and the move batch.
- **"58d3640a is a live run holding a token."** Not so. Writer pid 96991 is dead, and the run ended FAILED: rsync `mkstempat` errors, then `lr-transplant exited 1`. The admit token's TTL is 1020 s (from the run's stderr), so it expires by itself; it is not a leak. The defect is the misleading status line (B1-5).
- **`set -e` aborts as a source of silence.** lr-fleet, lr-move-batch, lr-move-worker, lr-upgrade, the poller and cc-lr all use `set -uo pipefail` without `-e`. lr-handoff does use `-e` (:105, :986, :1902), but its verdict is not what reaches the requester on limit runs.
- **cc-notify missing, or the send to the requester pane failing:** 0 of 446 runs.
- **A move batch killed mid-watch, or a worker finishing past the watch bound:** 0 of 5 batches lack `summary.json`; 0 `batch.log` files contain "the watch bound passed".

## Uncertain
- Which callers fired the 98 runs whose mail was sent. They were not matched to requests. Inferred: cc-lr direct fires made before the reconciler went live.
- Whether push-send is wired today. The credentials were not read. 70 `unwired` and 0 `phoned` suggest it is not.
- Whether anyone reads the reconciler's and lr-page's Notification Center posts. pages.log does not log the page text.
- How the other 13 `admitted`-final bundles split between FAILED and armed-success.
- What the reconciler will do at 04:00Z, and whether any surface will report it. Only Notification Center pages are wired.
- B1-2's per-record mail design must respect lr-handoff.sh:771-778. A mailed placed or no-prompt subject takes a turn mid-move, so mail goes only to the REQUESTER pane, never the subject's.
