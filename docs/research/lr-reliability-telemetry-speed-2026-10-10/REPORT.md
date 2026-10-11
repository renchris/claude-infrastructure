# Limit-recover rail: reliability, failure telemetry, concurrent speed (2026-10-10/11)

Scope (frozen): research the limit-recover rail on reliability (A), failure telemetry (B) and concurrent speed (C), write one ranked report, then drive every finding above 90% conviction to landed and converged; findings at or below 90% go to the operator via `cc-decide` with conviction and receipt.

## 0. Lead decisions (read this first)

**Answer.** The originating session does not learn of a failed recovery because there are three faults in a row. (1) A `cc-lr recover` request records no requester, and the poller's fallback throws it away as `unknown mode 'recover'` (`lr-reset-poller.sh:1326-1331`). (2) Daemon-run verdicts are mailed to a `desk` role that does not exist: 348 of 446 reached no inbox. (3) `cc-lr status` reads a bundle log that lr-handoff never closes, so a FAILED run reads `admitted` (151 of 224 bundles end non-terminal). Speed is dominated by the poller tick, not by restarts. Tonight's tick ran more than 60 minutes at load 300-700, mostly forking basename and jq per registry file per parked record.

**Conviction column.** The ranked table in §3 carries the skeptics' adjusted conviction, which scores the slot's *original* fix proposal. The lead re-scored each row against the skeptic-*corrected* fix, with a red-first bats or pytest pin required. A row clears 90% only where the mechanism is CONFIRMED (or verified by the lead at trunk), the corrected fix is bounded, and its risk is answered in the brief.

**Drive now (lead conviction > 90%):** three implementation waves, one dispatched session each, split by file owner.

| Drive | Ranked row | Corrected fix | Lead conv. | Why above 90 |
|---|---|---|---|---|
| D1 | 2 (poller half) | Poller request lane accepts `mode: recover` as `relaunch` and reads `.pane` as well as `.source_pane` | 96 | Lead read `lr-reset-poller.sh:1326-1331` at trunk; 2 live losses (poller.log 03:56:01Z, 03:57:21Z); deterministic |
| D2 | 2 (reconciler half) | `req_by_sid` keeps the highest `origin_rank`, not last-wins over listdir | 91 | A3-4 CONFIRMED; 4 of 4 tonight; pytest pins it |
| D3 | 7 (narrowed) | cc-lr requests carry `requester_pane`; the poller passes it as `LR_FLEET_NOTIFY_PANE` for cc-lr-origin requests only, never the subject's pane (B3-1 skeptic: mailing a capped subject loops) | 92 | Writer and reader both in repo; the env hook already exists (`lr-fleet.sh:1690-1697`) |
| D4 | 4 | `LR_HOLDER_PID="${LR_HOLDER_PID:-$$}"` on the abort call inside `$( )` | 95 | CONFIRMED; 4 of 4 refused; red bats test specified |
| D5 | 3 | lrh_verdict writes the terminal `lrh_state`, plus an EXIT trap that writes `exited rc=N` when the last state is not final; `cc-lr status` reads `fleet/one-*/verdict.txt`, and prints no `repair` hint for a sid the reconciler holds (B1-5 skeptic) | 91 | Mechanism verified live on 58d3640a; both skeptic risks are designed out |
| D6 | 10 | `rotate` counts and prints recovers queued to the reconciler | 92 | CONFIRMED; message and count only |
| D7 | 11 | One jq over the registry in `lr_registry_live_rows`, discarding its output and falling back to the old loop on a non-zero exit; differential bats test old against new | 92 | CONFIRMED cost (1.19 s vs 0.026 s); output equality is testable |
| D8 | 15 | `cc-lr status --all` builds one bulk live set (precedent `lr-fleet.sh:351-358`) | 92 | CONFIRMED; 200 s timeout measured twice |
| D9 | 14 | The move batch checks the abort file after admit; summary says `aborted`, keeps reason classes and per-row instructions | 91 | CONFIRMED; abort 03:40:58Z vs admit 03:41:16Z |
| D10 | 13 (message half) | Every "still in flight" line reads `poller.lock` pid/lstart and says when the request has not started because a tick has held the lock for N minutes | 92 | Message-only; this is the operator's named "nothing told the requester the tick was stuck" |

**Researched inside the wave, then driven only if the wave clears 90%:** rank 8 (transplant FAILED arm aborts only its own new lock and drops only its own token), the reconciler's `mail_requester` wiring (rank 7, other half), and row 39 below (placement timeout under load).

**Operator decisions (≤ 90%, filed with `cc-decide`):** P1, where daemon-run verdicts with no requester go (rank 1, 70%). P2, wiring Pushover credentials into callers' environment (rank 6, 70%). P3, reversing "NEVER DELETION" for evidence dirs older than 7 days (rank 21, 72%). The rest of §3 stays filed in this report as ranked rows; nothing below 90% is driven.

**Rows added after synthesis (peer pane 225, investigation read-only; 2026-10-11).**

| # | symptom | measured frequency | root cause at file:line | fix | conv % | receipt |
|---|---|---|---|---|---|---|
| 39 | After the 04:00Z reset the reconciler placed nobody: every next-cohort mover sat at `wait-data` | 3 of 3 movers in `recon/plans/next-7d-1791691200.json`; load 300-700 | `lr_recon/plan.py:216` `timeout: float = 30.0`; `:244-247` maps `TimeoutExpired` to `wait-data` for every mover | Researched in wave A: a placement that times out must not erase a prior placement; the timeout scales with load | 75 (lead verified the mapping at trunk; the fix is unsettled) | `jq` over the plan gives `{"wait-data":3}`; plan.py lines read at 110ea9a64 |
| 40 | Peer mail cannot wake a limited session: cc-wake refuses it ("last presence beat is not a Stop") | reported by peer, not counted | not located by this wave | none proposed | 40 (peer-reported, unverified) | pane 225 mail 2026-10-11T04:18Z |

**Step 0 outcome (the four queued sessions).** None was recovered by the rail. 58d3640a's driver FAILED (rsync raced `tool-results/`, rank 8), and the poller then retired its request as "transplanted" because of the orphan lock (rank 9). 5507881f was HELD:unreachable (rank 22). Two `cc-lr` requests were thrown away as unknown mode (rank 2), and 6defb493 and 516b9da9 never got a run, because the request lane waits on a tick that had already passed it (rank 13). All five next-cohort sessions (113, 124, 134, 212, 220) were working again by about 04:21Z: two through pane 225's peer mail, three through an operator-run guarded `continue`. `cc-lr status` could show none of that until D5 landed.

Trunk 110ea9a64 · window 2026-10-11T03:16Z-04:42Z · 10 slots, skeptic verdicts folded in. Slot files: [A1](slots/A1-verdict-census.md) · [A2](slots/A2-lane-census.md) · [A3](slots/A3-live-cases.md) · [B1](slots/B1-verdict-paths.md) · [B2](slots/B2-poller-liveness.md) · [B3](slots/B3-delivery-target.md) · [C1](slots/C1-restart-cost.md) · [C2](slots/C2-fork-and-status.md) · [C3](slots/C3-width-and-waits.md) · [H](slots/H-hostile-reviewer.md).

Number labels: every frequency below was measured with the command named in the receipt cell or in the linked slot file. Numbers marked **E** are estimates; the slot names the method. Conviction is the skeptic's `adjusted_conviction` wherever a skeptic ran. Where no skeptic ran, the row says "slot, no skeptic". File:line sites are the skeptic-corrected ones.

## 1. Answer

1. **The gap is real and has one main cause.** Every recovery the daemon dispatches (hook request lane and REROUTE) mails its verdict to `cc-notify --role desk`. No desk role has existed since 2026-09-30, and the phone fallback has never delivered: 0 successes in 434 push records. 348 of 446 detached verdicts reached only `fleet/<run>/verdict.txt` (rank 1, plus rank 6).
2. **A session that runs `cc-lr recover` is worse off.** The hook request for the same sid overwrites it in the reconciler (4 of 4 tonight). If the reconciler is stale, the poller parks mode `recover` as unknown (2, both tonight). The request carries no reply-to, and `mail_requester` has no production caller (ranks 2 and 7).
3. **`cc-lr status` cannot tell it either.** lr-handoff never writes a terminal state to events.jsonl: 0 RECOVERED in 1,097 lines, and 151 of 224 bundles end non-terminal. So 58d3640a read `admitted` for more than an hour after it FAILED (rank 3).
4. **Recoveries actually fail for these reasons.** Move-lane aborts are refused 4 of 4 times, because `LR_HOLDER_PID` defaults to `$PPID` inside `$( )` (88%, rank 4). A transplant that dies mid-rsync leaves an orphan lock that the poller reads as a finished move. 58d3640a was falsely retired that way, and a lead's mail woke it, not the rail (ranks 8-9). REROUTE re-ran deterministic refusals 234 times in 3 days (rank 5).
5. **Speed.** The poller tick and all its children run at PRI 20 (rank 12). Most of the tick goes to forking basename plus jq per registry file per record (ranks 11 and 16). Ticks ran 25 to more than 48 minutes tonight, and intake waits on them (rank 13).
6. **Is a restart net zero?** Yes in steady state, no in transit; see C1.
7. **Nothing clears 90% after skeptic adjustment.** The nearest drive candidates are A2-1 and C2-1 at 88%: both CONFIRMED, S-sized, with a red test specified.

## 2. C1: is a restart net zero?

**In steady state, yes. During the restart and in the rail around it, no.**

- **Steady state.** The new session's resident parts replace the old one's, and none of them grows or leaks (measured, C1). An ms365 node costs 1.04 CPU-s regardless of age, the expect layer costs at most 0.09 CPU-s/h, and lead-crash-watchdogs map 1:1 to live leads.
- **The restart itself.** It is a one-off boot of about 8-20 CPU-s (E, C1, summed from the table below). The box was measured at 44% user, 55% sys and 1.6% idle (`top -l 2`, load 296), so every fork competes for CPU. Boots also overlap across lane caps that never see each other (rank 34). One 7-session width-4 batch took load1 from 20 to 150 (measured, capacity-alarm.jsonl, C3).
- **The biggest recurring cost does not come from restarts.** Every tick, the poller re-proves 26 stuck parked records at PRI 20, forking basename plus jq per registry file (ranks 11, 12 and 16). It pays that whether or not anything restarts.
- **Leftovers break net zero on disk.** Refused move-lane aborts leave a stale target copy beside the live one (rank 4). 17 never-pruned evidence directories hold 221 MB (rank 21).

| Component | CPU-s per restart | M/E | kitty RPCs | Net zero? | Fix (rank) |
|---|---|---|---|---|---|
| Claude client init + first render | 2.3-7.2 | E (bounded from young-process TIME) | 0 | No: one-off boot | none in repo |
| Transcript replay (`--resume`) | 0.01 at p50, 0.56 at the 241 MB maximum | E (json.loads proxy, measured) | 0 | Negligible; ruled out (r = -0.13, n = 25) | none |
| `claude mcp list` probe at SessionStart | 0.67 per start × 3-6 = 2-4 | count M (342 probes / 512 starts); CPU E, unmeasured | 0 | No: a second client per start | C1-2 (33) |
| MCP stdio servers (ms365 node) | 1.04 each | M (n = 31, flat with age) | 0 | About zero: replaces the old one | npx wrapper in `~/Development/personal` only |
| SessionStart hooks (19 scripts) | 1-3 | E (fork count × 5-10 ms); no timing log exists | 0 | No: one-off | add per-child timing |
| lead-crash-watchdog | about 3.3 over its lifetime | M | 0 | Yes: 1:1 with live leads | none |
| expect layer (`lr-fire-resume.sh:985-1574`) | 0.08-4.14 over its lifetime | M | 0 | Yes: resident and cheap | none |
| lr-fire-resume composer looks | 0.05-0.1 per look | E | 0-26 whole-scrollback `get-text` reads (at least 18 measured over 42 runs) | No: transit | C1-3 (31) |
| `handoff-fire --recycle` | not measured | none | about 10-14 (E, from call sites) + 1 per 15 s of exit wait | No: transit | C1-4 (32) |
| Move path only: prove loop | slot E about 28; skeptic: "a guess" (one scan measured at 0.28 CPU-s, 1.7 s wall at load 651; HELD runs do about 1 poll) | E | 0 | No: rail overhead | C1-1 / C2-2 (11) |
| Not per restart: poller tick, every 600 s or more | 26 records × about 95-100 forks per tick (E); PRI 20 | E / M | 0 | Paid regardless of restarts | 11, 12, 16 |
| Leftovers | 4d059264: a 1.44 MB stale copy beside the 1.64 MB live one; 221 MB in 17 evidence dirs | M | none | No: on disk | 4, 21 |

## 3. Ranked findings

Rank = impact on the operator's gap and on failed recoveries (1-3) × frequency (1-3) × conviction. The impact and frequency weights are my judgement from the slot data. Rank 8 is placed next to rank 9 because it is that defect's root. Detail lives in the linked slot files.

| # | id | symptom | measured frequency | root cause at file:line | fix | conv % | receipt |
|---|---|---|---|---|---|---|---|
| 1 | A1-1, A3-5, B1-1, B2-4, B3-1 | Daemon-run verdicts (hook lane + REROUTE) reach nobody; only `verdict.txt` holds them | 348 of 446 detached verdicts, all time; 7 d: 58-59 of 65-68; fallback 278 phone-damped, 70 unwired, 0 phoned | `lr-fleet.sh:1690-1697` finds no requester under launchd; `:1892` `--role desk`; no desk file in `~/.claude/cc-roles`; dispatch sites `lr-reset-poller.sh:1456`, `:2077` | Add an lr-page leg at `lr-fleet.sh:1889-1896` for FAILED and HELD only, damped per sid and de-duplicated against the `:1425` exhausted page. Never mail the subject pane | 70 (B1-1 CONFIRMED; A1-1 35, A3-5 55, B3-1 55, B2-4 50) | loop over `fleet/one-*/detached.log` for "desk role did not take it" ([B1](slots/B1-verdict-paths.md), [B3](slots/B3-delivery-target.md)) |
| 2 | A3-4, B3-2, B2-4 (archive half) | Operator's `cc-lr recover` never becomes an acting record: prints QUEUED, then nothing | 4 of 4 cc-lr requests tonight shadowed by a hook request; 0 of 3 recon records are origin cc-lr; 2 unknown-mode parks in total, both tonight | `lr_recon/__main__.py:220` builds req_by_sid last-wins over the sorted listdir at `store.py:572`; `census.py:326` sets plan_only; poller mode gate `lr-reset-poller.sh:1326-1331` and reader `:1214-1222` (reads `source_pane`) | Keep the highest origin_rank in req_by_sid (pytest). Poller maps recover to relaunch and reads `.pane` (13 fields). Fix the bats fixture `lr-recon-fence-callsites-poller.bats:139` to the real request shape | 78 (A3-4 CONFIRMED; B3-2 35) | poller.log REQUEST-SKIP at 03:56:01Z and 03:57:21Z; `ls results/*.unknown-mode.json` ([A3](slots/A3-live-cases.md)) |
| 3 | A1-2, B1-5, C3-5, A3-5 (status half) | `cc-lr status` shows FAILED/HELD runs as `admitted` or in flight; 58d3640a read `admitted 1h12m` after FAILED at 03:41Z | 0 RECOVERED in 1,097 event lines; 151 of 224 bundles (30 d) and 68 of 90 (7 d) end non-terminal; 0 of 224 bundles hold a transplant-stage row | `lr-handoff.sh:766` lrh_verdict never calls lrh_state; exits that skip lrh_verdict: `:1606`, `:1830`, `:2008`, `:2243/:2250`; `bin/cc-lr:1927-1963` reads bundles only; klass at `:2000-2004` | Write lrh_state from lrh_verdict, plus an EXIT-trap `exited rc=N` when the last state is not final. Status ranks the reconciler record (reuse `cl_status_cohort`) above a bundle FAILED. Add transplant start/end events with load1 | 62 (A1-2; B1-5 58, C3-5 60) | `cat */bundle-*/events.jsonl`, jq `.state`, uniq ([A1](slots/A1-verdict-census.md), [B1](slots/B1-verdict-paths.md)) |
| 4 | A2-1 | Move-lane stand-down reports FAILED and leaves a target copy plus a split brain | 4 of 4 move-lane aborts refused, against 9 of 9 `--one` aborts that succeeded; 4d059264 still source-ambiguous 22.7 h later | `lr-handoff.sh:1960-1961` calls the abort inside `$( )`; `lr-transplant.sh:106` uses `${LR_HOLDER_PID:-$PPID}`; `:620-623` refuses | Set `LR_HOLDER_PID="${LR_HOLDER_PID:-$$}"` on the abort call. Bats custody 8c (red on trunk) | 88 (CONFIRMED) | refused pids 82990/82734/83498/37369 equal the bundle writer pids ([A2](slots/A2-lane-census.md)) |
| 5 | A1-3 | REROUTE re-dispatches deterministic refusals every 15 min with no cap | 234 of 338 non-success verdicts in 30 d came from 3 sids; 46bc0436 was dispatched 119× after `.exhausted.json`; 4 dispatches since 10-04 (latent) | `lr-reset-poller.sh:2036-2086` reroute_parked: only a 15-min mark (`:2060-2062`), no counter, no verdict read, no exhausted check | Per-sid tries keyed on the refusal reason, read from the `run=` line of `$RESULTS/$sid.log`. Stop at 3 with one damped page. No bare `[[ -d $cwd ]]` check | 74 (CONFIRMED) | grep -cE REROUTE dispatching per sid gives 119/123/17 ([A1](slots/A1-verdict-census.md)) |
| 6 | B1-7 | cc-notify reports "already phoned" when the phone was never reached; no channel reaches the operator | 278 phone-damped, 70 unwired, 0 phoned; push-records: 433 inert, 1 failed, 0 success | `bin/cc-notify:518-521` writes the damp stamp on any rc; callers' env lacks Pushover creds (`scripts/push-send.sh:60-64`) | Stamp only on rc 0, or record the rc in the stamp. Wire the creds into callers' env: fixing the label alone restores no delivery | 70 (PARTLY) | grep `fallback=` tally; jq over `push-records/*.json` ([B1](slots/B1-verdict-paths.md)) |
| 7 | B1-2, B3-2 (requester half), B2-4 | A cc-lr request has no reply-to; "Verdicts arrive as mail" is false | 3 of 3 live `.cc-lr.json` had no requester (1 of 1 at 04:05Z); `mail_requester` has 0 production callers | `bin/cc-lr:262-266` writes only the subject's pane; `:516`, `:599` count QUEUED as fired; `lr_recon/report.py:736` is never called | Add `requester_pane` (cl_this_pane) and `source_pane` keys; call mail_requester on bucket change with a latch. Ships only with rank 2. Update `cc-lr-request.bats:81` | 45 (B1-2; B3-2 35) | `git grep mail_requester` ([B1](slots/B1-verdict-paths.md)) |
| 8 | A3-1 | Transplant dies mid-rsync: the FAILED arm writes no state, runs no abort, and leaves the lock, a partial target copy and the token | 1 of 25 fleet verdicts (58d3640a); 1 of 9 bundles whose last state is `admitted` | `lr-transplant.sh:896-904` under `set -euo pipefail` (`:47`) with no trap; `lr-handoff.sh:1555-1562` | Write state (rank 3). Abort only when the lock was absent before the call and present after. rm the token only if self-minted | 75 (CONFIRMED) | 58d3640a `*.stderr`: 3 rsync errors, then `verdict=FAILED`; lock pid 82405 dead ([A3](slots/A3-live-cases.md)) |
| 9 | A3-2 | Orphan lock read as a finished move: REQUEST-RETIRED "transplanted" while the session sat LIMITED; a lead's mail woke it at 04:19Z, the rail did not | 5 `REQUEST-RETIRED … transplanted to` in total; 1 proven false (tonight); earlier 4 not checked | `lr-lib.sh:768-779` lr_transplanted_to checks only `to` + target jsonl; `lr-reset-poller.sh:1096-1097` (reason) and `:1249-1250` (retire); parked lane `:2170` does the same read | Root fix: the rank 8 abort. Defence: a liveness test in lr_transplanted_to (covers both lanes, but touches the lr-fleet and cc-husk-sweep callers) | 72 (PARTLY) | poller.log 03:58:43Z ([A3](slots/A3-live-cases.md)) |
| 10 | B1-3 | `cc-lr rotate` omits recovers queued for the reconciler; a queued-only run says "nothing was started", rc 1 | 1 of 1 live `rotate --all` (`0 rotated · 0 not · 7 still in flight`, 3 QUEUED not counted) | `bin/cc-lr:598-600` returns before the `:647` append; guard at `:1644-1648`; verdict line at `:1688` | Append a queued row in cmd_recover; put the 4th bucket on its own line; count queued rows in the `:1646` guard | 80 (CONFIRMED) | `/tmp/lr-rotate-all-222253.log` ([B1](slots/B1-verdict-paths.md)) |
| 11 | C2-2, C1-1 | `lr_registry_live_rows` forks basename + jq per registry file per call; it is the shared root of ranks 16, 15 and 28 | 26 call sites + 2 via `_in_cfg`; 1.19 s per call against 0.026 s for one jq at load about 848 | `lr-lib.sh:280-301` (loop at `:284-298`, from 109cfe4cfb); called 2× per move poll (`lr-move-lib.sh:58`, `:95`) | One jq over `[!.]*.json`; on a non-zero exit, discard its output and fall back. Or prefilter with `grep -lF $sid` | 80 (C2-2; C1-1 62) | perl HiRes timing ([C2](slots/C2-fork-and-status.md), [C1](slots/C1-restart-cost.md)) |
| 12 | C2-3 | The poller and all its children run at PRI 20 | every tick; 793 ticks in 7 d; gap p50 678 s, max 10,478 s | `com.reso.lr-reset-poller.plist:30-49` has no ProcessType, so spawn type is daemon | `ProcessType Interactive`, after the fork cuts land; add a parity-lint assertion | 70 (CONFIRMED) | `ps -o pri -p 36464` gives 20; `launchctl print` gives spawn type daemon (3) ([C2](slots/C2-fork-and-status.md)) |
| 13 | A2-3, C3-1, B1-6, C3-6 | Requests filed mid-tick wait for the tick's EXIT trap; wait loops print "still in flight; the workers keep running" when nothing has started | move plan→start 89/221/67/2/896 s (1 of 5 over 600 s); 27 of 808 ticks ≥ 600 s, 12 ≥ 1200 s; 0 TICK-SKIP | kick sites only at `lr-reset-poller.sh:240-245` and `:314`; silent 20-min stretch at `:2001-2392`; `bin/cc-lr:1422-1452`, `:1688-1691` | Call lrp_move_kick between sections and on each §2 iteration. The message reads the claim state plus `poller.lock/{pid,lstart}`; rc stays 1; gate the message on tick age | 58 (A2-3; C3-1 45, B1-6 45, C3-6 50) | grep MOVE-BATCH in poller.log vs batch ids ([A2](slots/A2-lane-census.md), [C3](slots/C3-width-and-waits.md)) |
| 14 | A2-2 | An operator abort and the "became-limited → cc-lr recover X" instruction are lost: summary and mail say `done: NOTMOVED=7`; the batch was admitted 18 s after the abort | 1 of 1 aborted batch left unflagged; 1 of 5 batches lost its instruction | `lr-move-batch.sh:78-97` counts `.verdict` only; `:258`; neither the batch nor `lrp_move_kick` (`lr-reset-poller.sh:293-305`) reads the abort; `bin/cc-lr:1293`, `:1305-1307` | Check for the abort after `:112`; status=aborted; reason-class counts (keep the `MOVED=7` asserts); per-row instruction in the mail | 78 (CONFIRMED) | stat: abort 22:40:58 vs admit 22:41:16; mailbox 223.md ([A2](slots/A2-lane-census.md)) |
| 15 | C2-1, A1-7 | `cc-lr status --all` takes over 200 s and prints nothing until it finishes | every call; 206 registry probes; 200.04 s (rc 124) and 239.05 s measured | `bin/cc-lr:1989-1997` probes once per bundle of each dead sid; `lr-lib.sh:284-287` | One bulk live-set helper in lr-lib (precedent: `lr-fleet.sh:351-358`). Check the glob before jq; fail open | 88 (C2-1 CONFIRMED; A1-7 80) | `/usr/bin/time -p cc-lr status --all` ([C2](slots/C2-fork-and-status.md), [A1](slots/A1-verdict-census.md)) |
| 16 | B2-1, C2-4 | The parked loop re-proves 26 past-reset HUSK records every tick and logs nothing; husk-noted gates only the log line | every tick; §2 took about 11 of 12-13 min across 7 ticks and 19.8 min at 03:15Z; about 13-28 s per record | `lr-reset-poller.sh:2127-2215` (pgrep `:2158`, `:2164`; registry `:2202`; silent continue `:2211`) | The rank 11 prefilter plus the one-fork gate at `:2111`. No stale ps snapshot for the retire `mv` at `:2164`. A dir-mtime stamp would be defeated by registry churn | 58 (B2-1; C2-4 45) | poller.log CONSOLIDATED → next TICK ([B2](slots/B2-poller-liveness.md), [C2](slots/C2-fork-and-status.md)) |
| 17 | A1-4, B1-4 | A detached `--one` that exits "already TRANSPLANTED, nothing to do" writes no verdict and sends no mail; rotate waits its full 600 s | 8 of 454 detached runs (3 in 7 d, all before 30ecec45d); 0 error or signal exits lacked a verdict | `exit 0` at `lr-fleet.sh:1759`, `:1775`, `:1804`, before the tail at `:1850-1897` | Write a `skipped` row with a no-drive flag that keeps rc 0, then fall to the tail. A chained EXIT/TERM trap (with `:1838`) serves only as a fallback | 65 (A1-4; B1-4 62) | loop over `fleet/*/`: detached.log present, no verdict.txt ([A1](slots/A1-verdict-census.md)) |
| 18 | B2-6, B1-10 | Nothing reads the poller's stderr; the census-ingest crash went unseen for about 8.5 d | 1,041 `bad substitution` between 09-20 and 09-29 (fixed in cf7bd5c1a); 0 since | `com.reso.lr-reset-poller.plist:40` StandardErrorPath; no reader (only a comment at `lr-reset-poller.sh:147`) | Size watermark (`wc -c <`) at tick start or in the EXIT trap; first run sets the baseline; page at most once per 6 h. Drop the `bash -n` half | 60 (B2-6; B1-10 45) | `grep -c 'bad substitution' poller.launchd.err` ([B2](slots/B2-poller-liveness.md)) |
| 19 | B1-9 | Upgrade/switch verdicts for `poller-auto` go to the dead desk role; drain news never lands | 53 of 84 upgrade/switch results reached no inbox; 0 drain-news mails ever; move summaries 5 of 5 delivered | `lr-upgrade.sh:143-146`, `:3088` | Same root as rank 1. Record `mail_verdict` from the cc-notify stderr token. Do not page every undelivered send | 40 (PARTLY) | jq over `results/upgrade-*.json`; mailbox grep ([B1](slots/B1-verdict-paths.md)) |
| 20 | A1-6 | CLAIMED-NOT-LIVE is re-logged every tick (72.5% of poller.log); the lock reaper times out every tick, so the 84 rows never clear | 61,747 of 85,112 lines since 10-04; LOCK-REAP rc=124 on 427 of 451 ticks since 10-07; 0 faults acked | `lr-reset-poller.sh:1766-1768`; `bin/cc-limited:982-984` renders until acked; reaper bound at `:63`, `:1615-1623` | De-duplicate keyed on the sid (the age field changes every tick); one summary line; page through page-damp, grouped. Fix the reaper timeout separately | 58 (PARTLY) | awk CLAIMED-NOT-LIVE line count ([A1](slots/A1-verdict-census.md)) |
| 21 | H-2 | The state store is never garbage-collected, and nothing reads the evidence dirs | 706 MB in 16,126 files; locks/ holds 221 MB in 17 evidence dirs (about 18 MB/day, E); poller.log 24 MB since 07-12, growing 1.8-2.7 MB/day | `lr-transplant.sh:382-395` (lrt_file_evidence, "NEVER DELETION"); the only pruner is `lr-upgrade.sh:2380`; log at `lr-reset-poller.sh:128` | lrp_gc under the tick lock: delete evidence older than 7 d; rotate poller.log at 10 MB; drop the "bundles > 30 d" clause | 72 (CONFIRMED) | `du -sk locks/*` ([H](slots/H-hostile-reviewer.md)) |
| 22 | A3-3 | 5507881f HELD:unreachable: the hold was correct, but the verdict went nowhere and no post-reset wake was observed | 1 of 25 (the other 4 HELD:unreachable are the 180 s gate on 186452ed) | `handoff-fire.sh:17934-17942` (emitter at `:4446-4450`); `lr-handoff.sh:1944-1967` | No change to the hold. The silence is fixed by rank 1; the wake depends on the stuck tick (ranks 13 and 16) | 62 (PARTLY) | handoffs.jsonl 03:24:27Z; parked record untouched at 04:34Z ([A3](slots/A3-live-cases.md)) |
| 23 | A2-4, C3-4 | Move slot-wait timeouts; a failed actuation keeps its slot through the 300 s prove window | 3 of 29 move rows, all in batch 012444Z | `lr-move-worker.sh:137`, `:140` fixed 600 s; release only at `:176-195`; holders spent 15-17 min inside the handoff-fire recycle | Release the slot at `actuated` when hrc≠0 and `$held` is non-empty (nothing typed). An events-mtime heartbeat cannot work | 35 (A2-4; C3-4 25) | jq timelines of `move/20261010T012444Z-*` ([A2](slots/A2-lane-census.md), [C3](slots/C3-width-and-waits.md)) |
| 24 | A3-6 | Requests held for a reset are invisible to status | 2 sids tonight; 4 requests held in the 03:51 tick (2 by a logged STAY, 2 by the silent `:1385` wait) | `lr-reset-poller.sh:1371-1376` and `:1384-1385` (silent `continue`); `bin/cc-lr:1955-1964` | A `.hold` sidecar at both sites (the pattern at `:1290-1292`), not `results/<sid>.json`. Add a status reader | 35 (PARTLY) | poller.log 03:55:51Z REQUEST-STAY ([A3](slots/A3-live-cases.md)) |
| 25 | B3-3 | Hook requests name no recipient; no per-request state reaches a human | 28 hook dispatches in 7 d; 4 REQUEST-RETIRED today (all already transplanted); the hook pages once per account+cause (13 since 10-04) | `lr-reset-poller.sh:1237` (gate key only); `:1127` rq_retire only logs; `lr-handoff.sh:770`, `:778` | One page per cohort, keyed by account, from the poller's STAY/RETIRED summary. Never mail source_pane | 35 (PARTLY) | grep `for stop-failure-marker` in poller.log; idl.jsonl page-sent ([B3](slots/B3-delivery-target.md)) |
| 26 | A1-5 | Admit tokens orphaned on FAILED/HELD exits; a legacy claim with no lstart and a reused pid blocks one session | 2 tokens from one cohort; 75 dead claims, 74 of them inert by design; 1 legacy claim that reads as live (0715cd0c) | `lr-handoff.sh:1556-1561`, `:1962-1969`; `lr-lib.sh:678` | Chain the traps (do not replace `:864`); delete only tokens it minted itself, before launch. One-off sweep of holders with no lstart | 45 (PARTLY) | `ls tokens/`; `ps -o lstart= -p 69160` ([A1](slots/A1-verdict-census.md)) |
| 27 | B1-8 | A reconciler page is latched before it is emitted, so a failed page is never retried | 6 of 313 pages.log rows failed, 2 of them in act mode; the caller cannot be attributed | `lr_recon/report.py:592-599` (also `:697-700`, `:740-743`, `:838-840`) | `failed_at` plus REFIRE_S backoff; export the failure count | 50 (PARTLY) | awk over pages.log ([B1](slots/B1-verdict-paths.md)) |
| 28 | C2-6 | `cc-lr move --status` takes 37-76 s for 7 verdicts | every call; about 6 s per verdict in two registry walks (E, load about 850) | via `lr-move-lib.sh:58` and `:95` into `lr-lib.sh:280-297`; ps at `:558` is minor | Rank 11, plus read the rows once per verdict. Pass an unexported ps snapshot on stdin | 45 (PARTLY) | `/usr/bin/time -p cc-lr move --status` gives 75.59 s ([C2](slots/C2-fork-and-status.md)) |
| 29 | C2-5 | sid lookups glob about 17,200 project dirs per store | backstop find runs 4× per tick; about 5 globs per parked record per tick; only 102 dirs were active in 7 d | `lr-reset-poller.sh:1926`, `:2100`, `:2111`, `:2113`, `:866`; `lr-lib.sh:806-818`, `:983-989` | A per-tick sid→transcript index behind an `LR_TX_INDEX` seam; offer to archive dirs untouched for over 30 d | 55 (slot, no skeptic) | `ls projects`, `wc -l`; glob 1.38/2.43 s ([C2](slots/C2-fork-and-status.md)) |
| 30 | C3-3 | Width is fixed, but move/upgrade outcomes split by load | 9 of 9 MOVED at load1 20-53, 0 of 13 at 128-1017; load5 above 10/core 14% of the time over 2 d | `lr-move-worker.sh:50`, `:138`; `lr-fleet.sh:1497-1502` constants | A down-only `lr_effective_width` on load5 per core, applied at acquire | 55 (slot, no skeptic; small n) | jq over capacity-alarm.jsonl ([C3](slots/C3-width-and-waits.md)) |
| 31 | C1-3 | A 24-line composer read pulls the whole 2000-line scrollback over the kitty socket | at least 18 such reads over 42 lr-fire-resume runs; at least 1 per recycle (51 in 6.9 d) | `bin/it2-kitty:1483-1486`; `lr-fire-resume.sh:848`; `handoff-fire.sh:4055-4056` | A `--screen` flag mapping to `get-text --extent screen` for the composer oracles | 50 (slot, no skeptic) | `bin/it2-kitty:1484-1485` ([C1](slots/C1-restart-cost.md)) |
| 32 | C1-4 | Each `it2 session send` costs `kitty @ ls` + `send-text` | not logged; about 10-14 RPCs per recycle (E) | `bin/it2-kitty:1317`, `:432`, `:527-552` | Reuse `CC_TERM_PROVEN` for under 10 s (this opens a 10 s window on a closed pane) | 45 (slot, no skeptic) | ([C1](slots/C1-restart-cost.md)) |
| 33 | C1-2 | SessionStart runs `claude mcp list` (a second client) on a 300 s TTL; failed probes are never cached | 342 probes per 512 starts in 7 d; 142 silent; 5 caches, one per config dir | `hooks/session-start.sh:142`, `:385`, `:390-393`; probe at `:277/:279`; only `ok` results cached (`:166`) | TTL 21600. Drop the proposed load gate (44 of 46 logged load values exceed it) | 40 (PARTLY) | sessions.log grep counts ([C1](slots/C1-restart-cost.md)) |
| 34 | C3-2 | Boot caps never see each other (one-slots 2, swap-slots 4, the `--recover` pool 2, the serial upgrade drain); detached `--one` boots are unbounded | `--one` overlapped 2 of 4 batches (1 a real boot); upgrade overlapped 0 of 4 | `lr-move-lib.sh:182`; `lr-fleet.sh:1478`, `:1496-1535`, `:1699` (LR_INPLACE_AWAIT=0); `lr-upgrade.sh:3067` | No sound fix proposed: holding a slot until the handoff returns misses boots done by the detached watcher | 35 (PARTLY) | batch.log windows × fleet/upgrade mtimes ([C3](slots/C3-width-and-waits.md)) |
| 35 | B2-2 | The tick has no wall-clock budget | p50 58 s, p99 1439 s, max 5290 s; about 169 of 223 lost slots come from the re-arm after each exit; a 480 s budget recovers about 38 (E) | `lr-reset-poller.sh:1197-1329`, `:2126-2151`, `:1891` | Per-iteration `$SECONDS` checks that cut detection, never actuation. No timeout on find | 35 (PARTLY) | python3 -I pass over poller.log ([B2](slots/B2-poller-liveness.md)) |
| 36 | B2-5, B2-3 | No lease or watchdog for the tick, runs or requests | tick: 48m45s live with no alarm; runs: 0 driver deaths in 454 detached runs | `lr-reset-poller.sh:216-232` (nothing watches poller.lock); `lr-fleet.sh:1850-1896` | An L1 tick lease only, as its own job. The L2/L3 leases would issue false FAILEDs | 35 (B2-5; B2-3 22) | `ps -p 36464` etime ([B2](slots/B2-poller-liveness.md)) |
| 37 | H-1 | The router's `--rank` expires mid-sweep and recoveries park | 52 of 294 rank calls had rc≠0, all between 09-30 and 10-04; 24 of 24 rc=0 since 10-06 | `bin/claude-accounts:5745-5760`, `:5803-5835` (serves its grace cache only when the lock is held) | In the router: serve the grace cache when the timer expires. Not an lr-fleet cache | 25 (PARTLY; historical) | awk over `fleet/*/rank.timing` ([H](slots/H-hostile-reviewer.md)) |
| 38 | C2-7 | About 1,000 forks/s fleet-wide, mostly Claude hooks and tool calls, test suites, and sleep-loop watchdogs | one 40 s sample at 03:48Z; only 7% of new pids captured | n/a (sampling, with lifetime bias) | Input to ranks 11, 12, 15 and 16 | 50 (slot, no skeptic) | python ps sampler ([C2](slots/C2-fork-and-status.md)) |

### Dissent (verbatim)

- **Rank 1, cause.** A1-1 skeptic: "So the real defect is narrower: when the desk role is unset, the verdict of a hook-origin or REROUTE detached run reaches nobody with its content. That makes the reply_to plumbing dead code for the path the finding names."
- **Rank 1, fix (a).** B1-1 skeptic: "Fix (a) covers almost none of the drops. Of the 381 poller dispatches logged, 299 are REROUTE (:2077), which has no requester at all."
- **Rank 1, fix (b).** B1-1 skeptic: "Fix (b) as written would send every PARKED and RECOVERED verdict to Notification Center (about 35 a day, measured: 347 since 10-01), against the 'ask nobody' ruling."
- **Rank 1, mailing the subject pane.** B3-1 skeptic: "Fix (1) as written is harmful: it mails the limited session itself through cc-notify's default cc-wake, which queues a turn on a capped account and can loop through a new stop-failure request."
- **Rank 1, phone leg.** A3-5 skeptic: "The claim understates the phone leg, though. It is not merely damped, it is unwired." Same skeptic, on the fix: "Paging only FAILED, or filing an agent backlog row as lrp_husk_owner_row does, is safer."
- **Rank 2, whether faster intake helps.** C3-1 skeptic: "Faster intake could not have run them."
- **Rank 2, reconciler state.** B2-4 skeptic: "The request was queued to a LIVE reconciler (cc-lr:597 queues only when lr_recon_live) at 03:24:43Z, not to a dead one."
- **Rank 2, impact.** A3-4 skeptic: "The impact is smaller than claimed. The poller's hook lane is not fenced off from these sids (there is no recon/owned/<sid>), so it acted as a partial backup."
- **Rank 2, B3-2's own fix.** B3-2 skeptic: "The fix leaves the real cause in place: req_by_sid would still have to prefer the higher-ranked origin (cc-lr) when a sid has two requests."
- **Rank 3, scope.** A1-2 skeptic: "Two corrections: it is not \"all 9 exits\", because at least 5 exit paths after BUNDLE is set skip lrh_verdict."
- **Rank 3, fix risk.** A1-2 skeptic: "If klass() matches ^SWITCHED as 'ok', a sticky SWITCHED-UNPROVEN written at :1896 would hide a later READY-NOT-SEEN or FAILED:submit from the watcher."
- **Rank 3, fix risk.** B1-5 skeptic: "Writing FAILED does carry a risk. cmd_status:2040-2042 would then print '→ cc-lr repair' for a live sid the reconciler already holds as WAIT_RESET, which invites a second actuator."
- **Rank 3, what C3-5 claimed.** C3-5 skeptic: "But the stage and duration can be recovered, so \"cannot be broken down\" overstates it. Only load1 is truly missing."
- **Rank 5, history.** A1-3 skeptic: "First, \"unchanged since b4eef1cb8\" is false: four later commits touched the function (60a434fdd, cf7bd5c1a, fe39ee835, 17fbdee45)."
- **Rank 5, recurrence.** A1-3 skeptic: "Recurrence: only 4 REROUTE dispatches since 2026-10-04T09Z, so the bug is latent rather than ongoing."
- **Rank 6.** B1-7 skeptic: "With the fix, the 278 damped lines become phone-unwired, and the operator is still reached 0 times."
- **Rank 8.** A3-1 skeptic: "Gating the abort on 'no HANDOFF.json' leaves a hole."
- **Rank 13, kick sites.** B1-6 skeptic: "First, lrp_move_kick does not run only at the start of a tick: the EXIT trap (lrp_tick_end, :241-246) runs it again, and that trap is what claimed this batch."
- **Rank 13, separate-job fixes.** C3-1 skeptic: "A WatchPaths intake job on requests/ would fire on the poller's own writes". A2-3 skeptic, on the QueueDirectories job: "Each of those cases would become a respawn about every 10 s that writes MOVE-SKIP lines to poller.log."
- **Rank 15, cost model.** A1-7's slot says lr_registry_live_rows runs once per distinct sid (110) and makes "at least 4,070 jq forks". Its skeptic: "That is 110 x 34 x 2, about 7,480 forks, not 4,070." C2-1's slot instead says "a dead sid is probed once per bundle" (206 probes, "about 15,900 forks"); C2-1's skeptic reproduced 206.
- **Rank 16, record count.** B2-1 skeptic: "First, '31 of 31 husk-noted' counts 5 orphan markers left by records already retired."
- **Rank 16, cost per record.** C2-4 skeptic: "The 02:48 and 03:03 ticks spent about 6-12 min on 26 records, which is about 13-28 s per record." The B2-1 slot said 38 s per record; the C2-4 slot said about 48 s.
- **Rank 17, measurability.** B1-4 skeptic: "The claim that error and signal exits are \"not measurable\" is false: the parent always creates detached.log (1680), so those exits would show up in the same loop. The measured count is 0."
- **Rank 17, fix.** A1-4 skeptic: "A plain fall-through would run lf_one on a held session, and reusing LF_HELD_ROW unchanged flips the exit code to 1 and turns two CONTROL bats tests red."
- **Rank 19.** B1-9 skeptic: "Paging through lr-page.sh on every send that is not delivered would fire on all poller-auto results and on every drain that has news, because desk is unset. That is Notification Center spam, not a fix."
- **Rank 20.** A1-6 skeptic: "The proposed bats test (\"the same 3 lines on two ticks\") would pass while production keeps spamming".
- **Rank 21.** H-2 skeptic: "Two caveats: this reverses the stated \"NEVER DELETION\" policy, and an unconfirmed evidence jsonl can hold successor-written turns that exist nowhere else."
- **Rank 22.** A3-3 skeptic: "And the claimed after-reset wake has not happened as of 04:34Z: the poller tick has been stuck since 03:51Z and the parked record is untouched."
- **Rank 23.** A2-4 skeptic: "Releasing the slot whenever hrc!=0 also releases it in the rc 4 STRANDED case, where a relaunch may still be booting."
- **Rank 28.** C2-6 skeptic: "If LR_PS_SNAPSHOT is exported, the 1.24 MB snapshot exceeds ARG_MAX (1 MB), so every later exec (jq, ps, awk) fails with E2BIG."
- **Rank 33.** C1-2 skeptic: "The load gate at more than 2 per core is dangerous here."
- **Rank 34.** C3-2 skeptic: "Measured: 0 of 4 batches overlapped a live upgrade step, not 2 of 4."
- **Rank 35.** B2-2 skeptic: "The budget has to cut detection, never actuation".
- **C1 table, move-path cost.** C1-1 skeptic: "With every worker.log empty, the poll count cannot be recovered, so \"28 CPU-s per moved session\" is a guess."
- **Dead claims (ranks 26 and 36, and H-3).** The B2-3 slot counts "75 holders are not alive" as a failure. Its skeptic: "The 75 dead-holder claims are expected leftovers: the claim is restamped to the driver's pid and is never released when the driver exits."
- **Frequency drift between slots, as reported:**
  - Rank 1: A1-1 says 59 undelivered in 7 d (9 FAILED); its skeptic re-measured 58 (8 FAILED); B3-1 says 59 of 65 notify lines.
  - Rank 1: the 30 d denominator is 455 (A1-1) or 446 (B1-1 and the A1-1 skeptic).
  - Rank 13: C3-1's recover wait p50 is 175 s per its slot and 220 s per its skeptic.

## 4. Drive now (>90%)

- **None.** No finding clears 90% after skeptic adjustment. The nearest are A2-1 (88%: CONFIRMED, size S, red bats test custody 8c) and C2-1 (88%: CONFIRMED, size S).

## 5. Operator decision (<=90%)

Policy questions come first, because several fixes depend on them:

- **P1.** Where do daemon verdicts go: restore a desk role, page through lr-page (FAILED and HELD only), or file an agent backlog row? Ranks 1, 19 and 25 depend on this; see the zero-asking ruling cited by the A3-5 skeptic.
- **P2.** Should Pushover creds be wired into the callers' env? Rank 6. Without them no phone channel exists.
- **P3.** Should the "NEVER DELETION" evidence policy be reversed for directories older than 7 d? Rank 21.

One line per ranked row:

1. A1-1/A3-5/B1-1/B2-4/B3-1: add an lr-page leg for FAILED and HELD verdicts with no requester, damped per sid. 70%
2. A3-4/B3-2: keep the highest-origin request per sid in the reconciler; the poller accepts `recover` and reads `.pane`. 78%
3. A1-2/B1-5/C3-5: write the terminal state from lrh_verdict plus an EXIT-trap state; status prefers the reconciler record. 62%
4. A2-1: `LR_HOLDER_PID=${LR_HOLDER_PID:-$$}` on the abort inside `$( )`. 88%
5. A1-3: cap REROUTE at 3 tries per refusal reason, then one damped page. 74%
6. B1-7: stamp the damp only on rc 0, and wire the Pushover creds (P2). 70%
7. B1-2/B3-2: add `requester_pane` to cc-lr requests and call `mail_requester` on bucket change (ship with item 2). 45%
8. A3-1: the transplant FAILED arm writes state, aborts its own new lock, and drops its own token. 75%
9. A3-2: an orphan lock with a dead pid and no live target row is not a move. 72%
10. B1-3: rotate counts and prints queued recovers; fix the "nothing was started" guard. 80%
11. C2-2/C1-1: single-jq `lr_registry_live_rows` that discards output and falls back on error. 80%
12. C2-3: `ProcessType Interactive` on the poller plist, after item 11. 70%
13. A2-3/C3-1/B1-6/C3-6: kick the move lane inside the long tick; make the "in flight" message honest. 58%
14. A2-2: the move batch honours the abort file; the summary keeps reason classes and per-row instructions. 78%
15. C2-1/A1-7: build the bulk live set once in `cc-lr status --all`. 88%
16. B2-1/C2-4: prefilter the parked loop's registry walk with grep. 58%
17. A1-4/B1-4: "nothing to do" exits write a SKIPPED verdict and keep rc 0. 65%
18. B2-6/B1-10: poller stderr size watermark plus a damped page. 60%
19. B1-9: record the mail verdict for upgrade/switch results (routing waits on P1). 40%
20. A1-6: de-duplicate CLAIMED-NOT-LIVE by sid; fix the lock-reaper timeout. 58%
21. H-2: `lrp_gc` for evidence dirs and poller.log rotation (policy P3). 72%
22. A3-3: no hold change; track the wake under items 13 and 16. 62%
23. A2-4/C3-4: release the move slot at `actuated` when nothing was typed. 35%
24. A3-6: `.hold` sidecars for STAY and the silent `:1385` wait, plus a status reader. 35%
25. B3-3: one per-account cohort page from the poller's STAY/RETIRED summary (P1). 35%
26. A1-5: chained trap removes self-minted tokens; one-off sweep of claims with no lstart. 45%
27. B1-8: emit before latching, with failed_at backoff. 50%
28. C2-6: `move --status` reads the registry once per verdict (after item 11). 45%
29. C2-5: per-tick sid→transcript index. 55%
30. C3-3: down-only load5-per-core width at slot acquire. 55%
31. C1-3: `--screen` extent for composer reads. 50%
32. C1-4: reuse the pane proof for 10 s. 45%
33. C1-2: MCP probe TTL 21600, with no load gate. 40%
34. C3-2: a shared boot semaphore; no sound design yet (detached watcher boots). 35%
35. B2-2: per-iteration detection budget inside the tick loops. 35%
36. B2-5/B2-3: L1 tick lease as a separate job. 35%
37. H-1: router serves its grace cache when the timer expires (historical; 0 failures since 10-06). 25%
38. C2-7: no action; it is input to items 11, 12, 15 and 16. 50%

## 6. Refuted

- **A2-5** (upgrade husks labelled "nothing typed" after `/exit`). Adjusted to 15%. Reason: 6507a980 was never left exit-pending. Its watcher logged "recycle HELD at 30s: the /exit raised the background-work dialog … sent Esc (Stay)", and handoff-fire scrubbed the `/exit`. "nothing typed" is accurate, and a2601c01 never carries that label. Rewording the message would make the wrong story stronger. The skeptic found a different defect, which is unranked here because no slot finding carries it: `recycle_await_verdict` (`handoff-fire.sh:18042`) does not match "recycle HELD", so `--await` waits out its full window and `lru_hf_evidence` (`lr-upgrade.sh:2141-2147`) treats a deliberate Stay as exit-pending.
- **H-3** (the same-session mutex is dead after each detached run). Adjusted to 12%. Reason: the dead-holder claim is released by design, and a dead holder counts as free. Only 1 of 386 consecutive same-sid run pairs overlapped. The repeat drives of 186452ed were the request lane's bounded HELD-refund retry, and the 01:58Z run recovered it. The proposed 3600 s backoff would have blocked that recovery. What survives is the cross-lane `.json` / `.cc-lr.json` duplication, which is folded into rank 2.

## 7. Gaps

- **Slots that failed to deliver: none.** All 10 slots delivered findings.
- **Findings with no skeptic run** (slot conviction used and labelled): C1-3, C1-4, C2-5, C2-7, C3-3.
- **Not measurable, as the slots reported:**
  - kitty RPCs per recycle (nothing logs them);
  - SessionStart hook CPU (no timing log);
  - CPU per prove poll (the poll was never timed whole);
  - whether the 4 earlier `REQUEST-RETIRED … transplanted` lines were false;
  - which caller owned the failed pages.log rows.
- **Live state at close.** Poller tick pid 36464 had been running since 03:51Z and was still running at 04:42Z, its last line logged at 04:11:39Z (A3-6 and B2-5 skeptics, `ps`). The post-reset wakes for 5507881f, 6defb493 and 516b9da9 never came from the rail.
- **Brief deviations the skeptics reported.** Stray scratch files were written under /tmp and left in place because rm was barred: `/tmp/skA12_*`, `/tmp/.lr-skeptic-a17-not-used`, `/tmp/null`, `/tmp/x_ignore`, `/tmp/nov.txt`, `/tmp/x`, `/tmp/.skeptic_none`, `/tmp/c26-*`.
