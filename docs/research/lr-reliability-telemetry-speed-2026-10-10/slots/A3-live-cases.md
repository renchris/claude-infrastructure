# A3 — tonight's four live recovery cases, traced end to end

Slot A3-live-cases · read-only · trunk 110ea9a64 · observed 2026-10-11T03:47Z–04:10Z (the 04:00Z `next` weekly reset happened during the trace)

## Answer first

- **58d3640a is not "admitted". Its run FAILED at ~03:40Z, and the poller then falsely retired its request (03:58:43Z).** The admit-phase transplant died on an rsync error. lr-handoff's FAILED arm writes no state event, runs no abort and releases no token, so `cc-lr status` still says `admitted`. The orphan lock it left makes the poller treat the session as "transplanted to .claude-quaternary": the request was retired and the parked record will be LEFT PARKED. The reconciler record is plan-only. **Nothing will wake it after 04:00Z. No terminal verdict will come without a human.**
- **5507881f HELD:unreachable is the pre-`/exit` composer re-read in handoff-fire.** That read hit kitty and got no answer. The admit was cleanly aborted. HELD is terminal for the run, not for the session. The parked lane should wake it in place after the reset, in this tick (inferred ~04:15–04:25Z).
- **6defb493 and 516b9da9 have no run because no poller tick existed to read them.** The 03:15:46Z tick had already passed its request loop, and the next tick started at 03:51:11Z, inside the 900 s stay window before the reset. The reconciler holds both as WAIT_RESET plan-only and will not type. Both are woken in place by the poller's parked lane. 516b9da9 was census-parked at 04:11:01Z (MEASURED). The wake comes in the 03:51 tick, which at 04:25Z had not yet reached its parked loop at load average 725 (MEASURED `uptime`). So: a wake, not a move, ETA load-bound at ≥04:35Z.
- **No requester was told anything, in any of the four cases.** Daemon runs mail `--role desk`, and that role is unset (20 of 29 runs since 2026-10-10T04:04Z had verdicts on disk only). `cc-lr recover` requests carry no requester field. Two of the three were destroyed as `unknown mode 'recover'` while the reconciler's heartbeat flapped. The third was shadowed by the hook request and demoted to plan-only.

## Timeline (MEASURED: poller.log, bundle events.jsonl, fleet/one-*/detached.log, handoffs.jsonl, recon/sessions/*.json)

| t (Z) | event |
|---|---|
| 03:06:18 / 03:07:25 / 03:18:05 / 03:24:02 | Limit deaths: 58d3640a / 5507881f / 6defb493 / 516b9da9. stop-failure-marker writes `requests/<sid>.json` for each. |
| 03:15:46 | Poller TICK start (the long tick, pid 91502). |
| 03:16:01–03:16:06 | `REQUEST … dispatching the in-place recovery DETACHED` for 5507881f (pane 220) and 58d3640a (pane 113). `lr-fleet --one --from-daemon --detach`. |
| 03:17:26 / 03:18:17 | `PARKED` 5507881f and 58d3640a [census], then 6defb493 (resets 04:00:00Z). 516b9da9 had not died yet. |
| ~03:20 | Both drivers waited at the `--one lane is at its cap (2 live recoveries)` gate, then started. Bundles `bundle-20261011T032034Z`. |
| 03:21:33 / 03:25:26 | `admitted` (capacity token, TTL 1020 s) for 5507881f / 58d3640a. |
| 03:24:27 | handoffs.jsonl `recycle-held-unreachable` pane 220: "freshness re-read pre-/exit: composer UNREADABLE". |
| 03:24:40–43 | `cc-lr recover` writes `requests/<sid>.cc-lr.json` for 58d3640a, 6defb493 and 5507881f (reconciler live). |
| 03:25:09 | 5507881f `HELD recycle "HELD:unreachable before confirm; admit aborted"`. Lock renamed to `locks/5507881f….aborted-20261011T032509Z`. |
| 03:25:28 | lr-transplant (pid 82405) writes `locks/58d3640a.lock` (to=.claude-quaternary), then rsync fails (`mkstempat: 'tool-results/…': No such file or directory`). |
| ~03:40–03:41:02 | 58d3640a `verdict=FAILED … lr-transplant exited 1`. fleet results.tsv row at 03:41:02Z. Mail: `cc-notify: verdict=unresolvable reason=role-unset target=--role desk` → "verdict is on disk only". |
| 03:41:09 | Long tick ends (`MOVE-BATCH started pid 15968`). |
| 03:42:59 | Reconciler sets all four records to `PRE-MOVE/WAIT_RESET`, eta 1791691200, `origin:"hook"`, `plan_only:true`. |
| 03:51:11 | Next TICK start (= 03:41:09 + 602 s). 03:51:12 `PAGE recon backup — … reconciler heartbeat is stale`. |
| 03:55:51 | `REQUEST-STAY 516b9da9 … resets in 249s (< 900s)`. |
| 03:56:01 | `REQUEST-SKIP 5507881f — unknown mode 'recover'; parked` (the cc-lr request, filed to results/). |
| 03:57:20 | `REQUEST-STAY 5507881f`. |
| 03:57:21 | `REQUEST-SKIP 58d3640a — unknown mode 'recover'; parked`. |
| 03:58:43 | **`REQUEST-RETIRED 58d3640a — transplanted to /Users/chrisren/.claude-quaternary; nothing was done`**. |
| 04:02:19 | `RECON-OWNED 1 cc-lr request(s) left for the live reconciler` (6defb493's: liveness had flipped back). |

---

## A3-1 — 58d3640a "admitted" is a dead run's last word: lr-handoff's transplant-FAILED arm writes no terminal state and leaves its residue

- **Symptom.** `cc-lr status 58d3640a` prints `58d3640a/bundle-20261011T032034Z  admitted  35m8s  token …ZhrhQeGJ`. MEASURED: `/usr/bin/time -p timeout 200 ~/.claude/bin/cc-lr status 58d3640a`, real 1.34 s, at ~04:00Z. The run actually ended FAILED: `fleet/one-20261011T031606Z-58d3640a/verdict.txt` = `verdict=FAILED rc=1 … lr-handoff rc=1`. Residue MEASURED on disk:
  - `locks/58d3640a-….lock` (pid 82405, `ps -p 82405` → dead; `"to":"/Users/chrisren/.claude-quaternary"`)
  - a partial target copy: `.claude-quaternary/projects/-Users-chrisren-Development-reso-landing-design-research/58d3640a….jsonl` plus a session dir holding only `subagents/ workflows/`. The source has `tool-results/` with 296 entries.
  - an unconsumed `capacity-admit/tokens/58d3640a….ZhrhQeGJ`
  - `transplant.json` 0 bytes
- **Which state machine.** Only lr-handoff's run log. `lrh_state` → `lr_state_append` writes `$BUNDLE/events.jsonl`, with the sequence `probed → probed → admitted (stage gate)` (lr-handoff.sh:1476). The step after `admitted` is the transplant at lr-handoff.sh:1527-1555 (`--phase admit` for in-place). On success it goes on to the in-place recycle (lr-handoff.sh:1896-1991), which writes `HELD`/verdicts. The bound is the token TTL of 1020 s (expired 03:42:26Z). No watchdog advances or closes a bundle's events.jsonl.
- **Why it did not advance.** lr-transplant.sh:904 `rsync -a "$SRC_DIR/$SID/" "$DST_DIR/$SID/"` failed under `set -euo pipefail` (lr-transplant.sh:47, no trap). It had already written the lock (lr-transplant.sh:896) and the transcript copy (:901). lr-handoff.sh:1556-1561 then only calls `lrh_verdict FAILED` and `exit`:
  ```
  if [[ $_lrh_txrc -ne 0 ]]; then
    lrh_verdict FAILED no "lr-transplant exited $_lrh_txrc; …"
    exit "$_lrh_txrc"
  ```
  This arm has no `lrh_state FAILED`, no `lr-transplant --phase abort` (the HELD arm at :1960 does run one), and no token release. On the limit path `lrh_verdict` is stderr-only (lr-handoff.sh:770 `[[ $VOLUNTARY -eq 1 ]] || return 0`).
- **Frequency.** MEASURED: 1 tonight. In `find ~/.reso/limit-recover -path '*/bundle-*/events.jsonl' -newermt 2026-10-04`, 9 of 89 bundles end at `admitted`. Only 58d3640a's is proven FAILED; the other 8 are unverified and may include SELF recycles that died mid-fire. Across `fleet/one-2026101*/verdict.txt`, FAILED is 1 of 25.
- **Fix (S).** In lr-handoff.sh:1556-1561, before `exit`:
  1. `lrh_state FAILED transplant "lr-transplant rc $_lrh_txrc"`.
  2. When no tombstone exists (`! compgen -G "$CFG/projects/*/$SID.HANDOFF.json"`), run the same `lr-transplant --phase abort --sid … --from … --to …` the HELD arm runs at :1960. That withdraws the lock and the partial target copy. Report `FAILED` only if the abort refuses, and `NOTMOVED` otherwise.
  3. Remove `$LRH_ADMIT_TOKEN`.

  **Bats:** stub `lr-transplant.sh` so `--phase admit` writes `locks/<sid>.lock` and a target jsonl and then exits 1, while `--phase abort` records its argv. Assert:
  - `tail -1 events.jsonl | jq -r .state` == `FAILED`
  - the abort stub was called
  - the lock is gone
  - the token file is gone
- **Conviction 85.** The root cause is certain from code and disk. Whether abort is safe on every rc-1 shape (abort refuses on a live holder) needs one more read of lr-transplant's abort preconditions.
- **Receipt.** `cat fleet/one-20261011T031606Z-58d3640a/58d3640a-*.stderr` shows the three rsync errors followed by the `verdict=FAILED` line. `cat locks/58d3640a-*.lock` → `"pid":82405`. `ls -la .claude-quaternary/projects/…/58d3640a…/` → `subagents workflows` only.

## A3-2 — The orphan lock makes all three lanes treat 58d3640a as "transplanted": request falsely retired, parked record stuck, no wake at reset

- **Symptom.** MEASURED: poller.log `2026-10-11T03:58:43Z REQUEST-RETIRED 58d3640a … — transplanted to /Users/chrisren/.claude-quaternary; nothing was done`, and `results/58d3640a….retired.json` exists. At that moment the session was alive and LIMITED: source pid 37013 in pane 113, recon record `source_pid 37013`, and the transcript tail shows the limit error at 03:33:21Z. Nothing moved.
- **Root cause.**
  - **Request lane.** `rq_stale_reason` calls `lr_successor_state`, which returns rc 1 on "a LOCK alone is no durable move" (lr-lib.sh:982). The rc-1 branch then *does* treat the lock as a move. It calls `lr_transplant_target` → `lr_transplanted_to` (lr-lib.sh:768-779), which needs only that the lock's `to` differs and that a target jsonl exists. It checks no pid liveness, no tombstone and no target registry row. That gives `echo "transplanted to …"; return 0` at lr-reset-poller.sh:1097 → `rq_retire`.
  - **Parked lane.** At reset, lr-reset-poller.sh:2170-2171 enters the TRANSPLANTED block, because `lrp_unmoved` needs an *admit tombstone* and there is none. With no RECOVERED state and no target live row it logs `HUSK … record LEFT PARKED` once (2211-2215) and then skips silently on every tick. It never reaches the nudge arm at 2265.
  - **Reconciler.** Plan-only (A3-4), so its reset wake is refused.
- **When the terminal verdict comes.** INFERRED: never, automatically. 58d3640a stays at its limit error in pane 113 after 04:00Z until a person types. A later death re-files a hook request, which is retired again by the same lock. The lock persists: 93 `*.lock` files sit in `locks/` (`ls locks/*.lock | wc -l`), and the poller only reports them (`CLAIMED-NOT-LIVE`).
- **Frequency.** MEASURED: `grep -c 'REQUEST-RETIRED .* — transplanted to ' poller.log` = 5 (2026-09-29 ×3, 2026-10-04 ×1, tonight ×1). Whether the other 4 were also false is not measured.
- **Fix (S).** The root fix is A3-1's abort-on-FAILED. As defence in depth, in `rq_stale_reason` (lr-reset-poller.sh:1094-1098), accept the lock as a move only if one of these holds:
  - the lock's pid is alive;
  - a tombstone exists;
  - `lr_registry_live_rows_in_cfg "$sid" "$to"` shows a target holder.

  Otherwise fall through to the LIMITED test. **Bats:** fixture with a lock (dead pid, `to`=other store), a target jsonl, no tombstone, a live source registry row and a last record that is a limit error. Assert that `rq_stale_reason` returns 1, that the request stays queued, and that no `REQUEST-RETIRED` line is logged.
- **Conviction 85.**
- **Receipt.** poller.log line above. lr-lib.sh:768-779 and 982. lr-reset-poller.sh:1094-1098 and 2170-2215. `ls ~/.claude/projects/…reso-landing-design-research/ | grep 58d3640a` shows no `.HANDOFF.json` and no `.handed-off`.

## A3-3 — 5507881f HELD:unreachable: the pre-/exit composer re-read got no answer from kitty; the hold is clean, but its verdict reached nobody

- **What "unreachable" means.** handoff-fire's freshness re-read of pane 220's composer, between arming and `/exit`, returned rc 2: no box could be read. `rcy_composer_unreadable fresh` (handoff-fire.sh:4447-4450) emits `recycle-held-unreachable` and aborts with nothing typed. lr-handoff then:
  - reads that reason with `lrh_held_reason` (lr-handoff.sh:1259-1270, newest `recycle-held-*` row for the pane);
  - confirms the source was never retired (`lrh_source_retired`, :1253);
  - runs `lr-transplant --phase abort` (rc 0);
  - writes `lrh_state HELD recycle "HELD:unreachable before confirm; admit aborted"` (:1964) and `verdict NOTMOVED`, and exits 6 (:1965-1967).
- **Is HELD terminal?** It is terminal for the *run*: lr-fleet maps `*/HELD:*` to token `HELD:unreachable`, rc 6 (lr-fleet.sh:1876 arm). It is not terminal for the *session*:
  - The hook request stays queued with `attempts:1`.
  - At 03:57:20Z it got `REQUEST-STAY` (MEASURED).
  - After the reset, parked record #15 of 31 in the glob is processed by the parked loop (lr-reset-poller.sh:2265-2281). If `account_has_headroom next` passes, `nudge_in_place` types `[limit-recover] The usage limit has reset on next. Continue …` (:950) and waits up to 120 s for a turn. The record then moves to resumed/.
  - The following tick retires the request as "no longer LIMITED".
  - INFERRED ETA: the wake comes ~10–12 min after this tick's parked loop starts (record #15–#16 at ~38–48 s/record). The loop had not started at 04:25Z (load average 725), so the ETA is ≥04:35Z. The retire lands one tick later. If the account still reads capped, `WAIT … retry next tick` adds another full tick.
- **Was the requester told?** No. MEASURED, from `fleet/one-20261011T031601Z-5507881f/detached.log`: `cc-notify: verdict=unresolvable … reason=role-unset target=--role desk` → `the verdict is on disk only`. lrh_verdict is stderr-only on the limit path (lr-handoff.sh:770). handoff-fire's RECYCLE-HELD wake mail is not sent on this remote form (no "retry ticket" line in detached.log).
- **Frequency.** MEASURED: `HELD:unreachable` in 5 of 25 `fleet/one-2026101*/verdict.txt`, window 2026-10-10T04:04Z–2026-10-11T03:16Z.
- **Root cause of the hold.** A kitty socket read did not answer under load (loadavg ~260 at the time, per the brief). handoff-fire.sh:4441-4446 documents the same class from 2026-09-30. Transport is the other slots' subject. This slot's finding is the silence (A3-5).
- **Fix.** None needed for the hold itself, which is correct behaviour. The silence is fixed under A3-5.
- **Conviction 90** (on the trace).
- **Receipt.**
  - `jq` on handoffs.jsonl → `{"ts":"2026-10-11T03:24:27Z","class":"recycle-held-unreachable","target_pane":"220",…}`
  - bundle events.jsonl line 4
  - `ls locks/ | grep 5507881f` → `….aborted-20261011T032509Z`

## A3-4 — The operator's `cc-lr recover` (03:24:40–43Z) was silently demoted or destroyed: last-wins request shadowing in the reconciler, and an unknown `mode` in the poller's fallback drain

- **Symptom.** cc-lr printed `QUEUED for the reconciler` (bin/cc-lr:270, via :599). MEASURED outcomes:
  - All four recon records (`recon/sessions/<sid>.json`) read `"origin":"hook","plan_only":true`, PRE-MOVE/WAIT_RESET.
  - The poller filed two of the three cc-lr requests as `results/<sid>.cc-lr.unknown-mode.json` at 03:56:01Z and 03:57:21Z.
  - The third (6defb493) was left for the reconciler at 04:02:19Z (`RECON-OWNED 1`).
- **Root cause, part (a): reconciler shadowing.** `store.list_requests` sorts names (lr_recon/store.py:572), so `<sid>.cc-lr.json` comes before `<sid>.json`. `req_by_sid = {r.sid: r for r in reqs}` (lr_recon/__main__.py:220, again at :309-310) is last-wins, so the **hook** request overwrites the operator's. `merge_origin` (lr_recon/census.py:322-326) then sets `plan_only = not autorecover_on and origin != "cc-lr"`. `recon/autorecover.on` is absent (MEASURED `ls`), so `zero_human()` is false (__main__.py:202-208) and `plan_only` stays True. `may_actuate` returns `plan-only` (lr_recon/act.py:455). `_dispatch` drops that with `if not ok: continue` and writes no event (__main__.py:956-959).
  - **Consequence at the reset.** `_wakes` (__main__.py:337-377) selects the wake at eta+120 s+jitter, `_dispatch` refuses it silently, and `wake_eta` is never set. The reconciler types nothing for any of the four.
- **Root cause, part (b): poller fallback drain.** `lr_recon_live` needs `progress_wall` within 180 s (lr-recon-fence.sh:319-331). The reconciler's progress advanced only 2896→2902 between 03:47:41Z and 03:58:17Z (MEASURED heartbeat), so liveness flapped request by request inside one tick. When it reads not-live, lr-reset-poller.sh:1204-1206 drains `*.cc-lr.json` "exactly as a cc-lr-origin request always has". But the mode switch at :1326-1331 accepts only `relaunch|prompt`, and cl_recon_queue writes `mode:"recover"` (bin/cc-lr:262-266), so the request goes to `REQUEST-SKIP … unknown mode 'recover'; parked`. The poller also reads `.source_pane` while cc-lr writes `.pane`.
- **Requester recorded.** `.cc-lr.json` = `{sid, at, requested_by:"cc-lr", mode, pane, config_dir}` (MEASURED file). `pane` is the *subject's* pane, and **no field names the session that ran `cc-lr recover`**, so no lane can address a verdict to it.
- **Frequency.** MEASURED: `ls results/*.unknown-mode.json | wc -l` = 2, both tonight, the first ever. Recon-stale pages: `grep -c 'recon backup — recon.on is set' poller.log` = 3 (2026-10-10 ×2, 2026-10-11 ×1). Shadowing affects every sid that has both a hook request and a cc-lr request: 3 of 3 tonight.
- **Fix (M).**
  1. lr_recon/__main__.py:220 and :309: build `req_by_sid` keeping the highest `census.origin_rank`. Pytest: two requests for one sid → record `origin=="cc-lr"`, `plan_only is False`.
  2. lr-reset-poller.sh:1326: for `*.cc-lr.json`, map `mode recover → relaunch` and read `.pane` as the source pane. Bats: recon not live, a `.cc-lr.json` with `mode:"recover"` → stub `lr-fleet.sh` invoked with `--one <sid> --source-pane <pane>`; no `unknown-mode.json`.
  3. bin/cc-lr:266: add `requester_pane` (`CC_PANE_ID`/`KITTY_WINDOW_ID`), and pass it as `LR_FLEET_NOTIFY_PANE` from both drainers.
- **Conviction 85.**
- **Receipt.** poller.log 03:56:01Z / 03:57:21Z / 04:02:19Z lines. `python3 -I -c '…'` over `recon/sessions/*.json` → `hook True PRE-MOVE WAIT_RESET None` ×4. `ls recon/autorecover.on` → No such file.

## A3-5 — Daemon-run verdicts mail `--role desk`, which is unset: the operator's named gap, measured

- **Symptom.** In both live runs the verdict reached no session: `lr-fleet: no requester pane and the desk role did not take it — the verdict is on disk only`.
- **Root cause.**
  - lr-fleet.sh:1690-1696 resolves the requester from the invoking env (`LR_FLEET_NOTIFY_PANE`, `CC_PANE_ID`, `ITERM_SESSION_ID`, `KITTY_WINDOW_ID`). The launchd poller has none of these, so `LR_FLEET_REQUESTER` is empty.
  - That empty value sends the mail to `cc-notify --role desk` (lr-fleet.sh:1892). There is no `desk` file in `~/.claude/cc-roles/` (MEASURED `ls`: docs-lead, drain-lead, opus55-lead, orchestrator), so the result is `unresolvable`.
  - The phone fallback is damped (`phone-damped … 599s ago (TTL 1800s)`).
  - The status surface does not join `fleet/one-*/verdict.txt`, so even `cc-lr status` hides FAILED (A3-1).
- **Frequency.** MEASURED: over `fleet/one-2026101*`, 29 runs (2026-10-10T04:04Z → 2026-10-11T03:16Z):
  - 20 logged `verdict is on disk only` (all `reason=role-unset`)
  - 5 `verdict=delivered`
  - 4 have neither line
- **Fix (S/M).**
  1. When `LR_FLEET_REQUESTER` is empty and the token is not RECOVERED, write the verdict through `lr-page.sh` (pages.log + operator page) with per-sid damping instead of the desk role. Do **not** mail the limited subject pane. The repo's own measurement (lr-handoff.sh:776-778, design-swap-v3 F10) and tonight's 58d3640a show that a turn taken on a limited account just re-dies: the 03:33:17Z task-notification turn did exactly that.
  2. `cc-lr status <sid8>` joins the newest `fleet/one-*-<sid8>/verdict.txt` newer than the bundle and prints its token.

  **Bats:** run `lr-fleet --one --detach` with no pane env and a stub cc-notify returning `unresolvable`. Assert that a page line is written and that `cc-lr status` prints `FAILED`.
- **Conviction 70.** The cause is certain. The channel choice (page vs desk claim) is a design decision.
- **Receipt.** The tails of both detached.log files (above). `grep -h '^cc-notify: verdict=' fleet/one-2026101*/detached.log | … | uniq -c` → `20 verdict=unresolvable reason=role-unset`.

## A3-6 — 6defb493 / 516b9da9: no run because the request lane did not tick for 35 min, then the reset stay held them; after the reset the wake comes from two different lanes at two different times

- **Consumers.** `requests/<sid>.json` (hook) is read by the poller's request loop (lr-reset-poller.sh:1198-1504). `*.cc-lr.json` is read by the reconciler when it is live, and otherwise by the same poller loop (:1204-1206). The reconciler also reads both through `list_requests`.
- **Why no run.**
  - 6defb493's request (03:18:06Z) and 516b9da9's (03:24:21Z) landed after the 03:15:46Z tick's request loop (03:15:57–03:16:06Z), and that tick ran until 03:41:09Z.
  - launchd's `StartInterval 600` (com.reso.lr-reset-poller.plist:37) fires 600 s after the previous exit. MEASURED TICK starts: 02:59:32, 03:15:46, 03:51:11 (= 03:41:09 + 602 s). So no consumer ran for 33–35 min.
  - At 03:51 both were within `RQ_STAY_S` = 900 s of reset (lr-reset-poller.sh:1371-1376), giving `REQUEST-STAY` (MEASURED 03:55:51Z for 516b9da9). D1.4 says moving minutes before a reset buys nothing.
  - The reconciler holds both at WAIT_RESET, eta 04:00:00Z, plan-only (A3-4), so it will not act.
- **What happens at the reset (INFERRED from code, partially MEASURED).**
  - The request lane wakes only at reset + 120 s + `cksum(sid) % 90` (lr-reset-poller.sh:1384-1388), paced 3 per account per tick. In the 03:51 tick 6defb493.json produced no line, which is consistent with the silent `continue` at :1387.
  - The parked lane (2127-2281) uses `now` captured at :1936, after the request loop and the census, so in this tick it sees the reset as passed.
  - **6defb493** has a parked record (#20 of 31). Expected: `nudge_in_place` in this tick, then `REQUEST-RETIRED … no longer LIMITED` the next tick.
  - **516b9da9** had no parked record until this tick. CORRECTION, MEASURED: at `04:11:01Z PARKED 516b9da9 … resets 2026-10-11T04:00:00Z [census]`, the census parks it even though its reset has passed. So it joins the parked loop of the same tick, ahead of 5507881f in glob order, and does not wait a tick.
  - **Load.** At 04:25Z, 0 of the 4 sids had a parked-loop line yet. The tick started at 03:51:11Z and was 34 min old (`ps` etime of pid 36464). `uptime` load averages were 725.80 / 569.43 / 407.63. Any ETA here is load-bound: at the last tick's ~38–48 s/record, records #15–#21 land 10–17 min after the loop starts, and the loop had not started by 04:25Z.
- **Requester recorded.** `requested_by: stop-failure-marker` for both (MEASURED request files). 6defb493 also has the `cc-lr` request, now owned by the reconciler and still shadowed. No requester pane exists, and `nudge_in_place` mails no one (lr-reset-poller.sh:912-984 logs only). The only signal the session receives is the typed `[limit-recover] The usage limit has reset on next…` prompt.
- **Frequency.** MEASURED: 2 sids tonight with request files and no run. The tick cadence (600 s after exit) is MEASURED from TICK start gaps of 12–16 min across 01:45–03:51Z.
- **Fix (S).** When the request loop sees a stay or an exhausted budget, write `results/<sid>.json` with `verdict:"stay"` and the ETA. Then `cc-lr status` can say "held for reset at 04:00Z, wake ≈ +2–3.5 min after a tick reaches it" instead of showing no run at all. The 35 min with no consumer is the tick cadence (600 s after a 25-min tick); that is the speed slots' subject. **Bats:** a request with `reset_at_epoch` = now+300 → the results file says stay with that ETA, and `cc-lr status <sid8>` prints it.
- **Conviction 70.** The stay and lane mechanics are certain from code and logs. The ETAs depend on tick length under load and on `account_has_headroom` after the reset; both are unmeasured.
- **Receipt.** poller.log `TICK start` lines (`grep -n 'TICK start' poller.log | tail -8`). `ls parked/*.json | nl` → 5507881f #15, 58d3640a #16, 6defb493 #20. `ls parked/ | grep 516b9da9` → none.

---

## Ruled out

- **The reconciler drove 58d3640a or 5507881f.** Ruled out: both runs were poller-dispatched. detached.log shows `lr-recon-fence: verdict=act … reason=not-owned` and `[daemon-run: lr-reset-poller request drain]`. The writers were lr-handoff pids 96991 and 75710, now dead (`ps -p`).
- **58d3640a is still running a transplant.** Ruled out: pid 82405 is dead, `fleet/…/results.tsv` closed at 03:41:02Z, and no lr-handoff/lr-transplant process is in `ps`.
- **5507881f HELD = a draft, or the 2026-10-10 slash-menu residue.** Ruled out: the row class is `recycle-held-unreachable` with "freshness re-read pre-/exit: composer UNREADABLE". Not a draft.
- **5507881f left a husk.** Ruled out: the abort ran (lock renamed `.aborted-…`), `lrh_source_retired` was false, and the session stays alive in pane 220 (recon `source_pid 95136`).
- **The 6defb493/516b9da9 requests were refused by the autorecover gate.** Ruled out: `autorecover.on` exists (2026-09-29), and the 03:15 tick dispatched hook requests through that gate.
- **The poller's `.cc-lr.json` fallback is a safe drain.** Refuted live (A3-4b).

## Uncertain

- **Why rsync failed.** The receiver-side `mkstempat`/`utimensat` "No such file or directory" on `tool-results/` suggests the destination subdir vanished or was never created mid-copy. Not reproduced. The admitted→FAILED gap was ~15 min (03:25:26→~03:40Z), which suggests a slow copy under load. Not measured.
- **The other 8 bundles stuck at `admitted`** since 2026-10-04 are not individually verified as FAILED.
- **The post-reset outcome was not observed.** At 04:30:35Z, poller.log still had no parked-loop line for any of the four (last non-census line: `04:11:06Z PAGE 5 session(s) on next still held by seven_day`). The wake predictions for 5507881f, 6defb493 and 516b9da9, and the `HUSK … LEFT PARKED` prediction for 58d3640a, are untested. Re-check with `grep -E '5507881f|58d3640a|6defb493|516b9da9' ~/.reso/limit-recover/poller.log | tail`.
- **Post-reset ETAs** (A3-3, A3-6) are inferred from 38–48 s per parked record and the 600 s-after-exit cadence. They will shift if `account_has_headroom next` still reads capped right after 04:00Z (that gives a `WAIT` line and one more tick).
- **Re-death of 58d3640a.** The hook rewrite of `requests/58d3640a.json` at 03:33:23Z (new death after a task-notification turn) dropped the `attempts` field, which resets the retry budget. That does not matter tonight because the request was retired, but it is a budget leak on any re-death.
- **Who ran `cc-lr recover` at 03:24:40Z.** Not determinable from the store: the schema has no requester field.
