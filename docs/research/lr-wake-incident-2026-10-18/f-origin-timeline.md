# F — Origin attribution: which session or action produced each piece of the 13:00 CDT pane state

Window: 2026-10-17 20:00 CDT (01:00Z) to 2026-10-18 13:30 CDT (18:30Z). CDT = UTC-5. Every log on the box is in UTC unless it says otherwise. `stat` and kitty "Last login" times are CDT.
Snapshot: I read `kitten @ ls` and `kitten @ get-text` between 18:12Z and 18:29Z. By 18:31Z a parallel remediation had already closed the husks and merged the tabs (§4 records the after-state). Every row below is pre-remediation unless it says otherwise.

## 1. Answer first

All of the overnight pane damage traces back to one origin session, the limit-recover lead in **pane 344**. It ran as 620db313 on next and, from 06:57Z, as its self-recycled successor 2cc3a7fa on next3. It did three things:

1. It queued 22 `cc-lr move` batches by hand (`requester_pane:"344"`).
2. At 06:35Z it installed a LaunchAgent, `com.reso.drain-to-next3`, that lives outside the repo. That agent fired 16 more batches with no requester, plus a `cc-lr rotate` on next4 roughly every 5 minutes.
3. When moves STRANDED, it hand-built `/tmp/lr-rescue/*.sh` relaunchers and fired each one with `handoff-fire.sh --tab`. That opened 17 background tabs in pane 344's own OS window (18). 13 of them were refused by capacity-admit and left as plain shells.

The STRANDED verdicts come from one mechanism. The handoff-fire load hold runs **after** the transcript confirm (it retires `<sid>.jsonl`). When load is too high, it "aborts before /exit". The unconfirm then refuses because a stub is present or the source is dead, so the session ends up tombstoned, with its transcript on the target account and no process running it. This was measured 24 times across the batches.

The fix has four parts:
- Move the load gate ahead of the confirm (scripts/handoff-fire.sh:18596-18604 vs :18583).
- Never let a capacity-refused launch keep its pane (bin/cc-pane-runner:179-181).
- Remove the agent-reachable `--tab` surface (scripts/handoff-fire.sh:14535, :15196).
- Retire the rogue drain LaunchAgent.

## 2. Evidence (MEASURED unless marked INFERRED)

### 2.1 Who queued the moves (`~/.reso/limit-recover/move/<batch>/plan.json` `.requester_pane/.requester_sid`)

| Batches (UTC) | Count | Requester | Operator ask that triggered it (620db313 transcript) |
|---|---|---|---|
| 23:57Z (10-17) to 03:08Z, next4→next, next2→next | 18 | pane 344 / 620db313 | 23:49:17Z and 01:53:37Z `/limit-recover all accounts to account 1 …` |
| 00:43Z next2→next | 1 | pane 3 | — |
| 02:33Z next4→next | 1 | pane 354 | — |
| 04:25Z, 05:12Z next→next4 | 2 | pane 390 / b102f5af | — |
| 06:08Z next→next4 | 1 | pane 344 / 620db313 | 06:00:01Z `/limit-recover to account 4` |
| 06:27Z next→next4 | 1 | pane 26 / 13fdd0b5 | — |
| 06:49Z next4→next2 (batch 7738) | 1 | pane 344 / 620db313 | 06:48:32Z "/limit-recover account 4 sessions to account 2" |
| 06:55Z next→next2 (f06b5e9b) | 1 | **pane 401 (operator-typed `cc-lr move --sid f06b5e9b --to next2 --until-idle 3600`)** | verdict 07:56:16Z NOTMOVED still-busy:mid-turn |
| 07:03Z to 18:07Z, next→next3 and next4→next2 | 13 | **empty requester = drain LaunchAgent** (`drain-to-next3.log` lines "next started pid … 2026101…") | 06:31:43Z "event driven listener … zero human in the loop" |
| 13:13Z next3→next2 | 1 | pane 445 / 6f8d7bd2 (lr proof target) | — |
| 15:32Z, 16:40Z, 16:49Z next→next3 | 3 | pane 344 / 2cc3a7fa | goal stop-hook loop |

Source: the 2026-10-18T0[0-9]… MOVE-BATCH lines in poller.log plus each batch's plan.json (40 batch dirs, 158 per-session verdict rows; a `jq` sweep over `move/*/<sid>.json`).

### 2.2 The drain LaunchAgent, an agent-installed artifact that lives outside the repo
- `~/Library/LaunchAgents/com.reso.drain-to-next3.plist` (mtime 01:55 CDT) runs `~/.reso/limit-recover/listeners/drain-v2.sh` with `StartInterval 300`, `WatchPaths recon/facts`, `CC_LR_MOVE_GOAL_HOLD=off` and `DRAIN_EXPIRE_EPOCH=1792492496` (2026-10-20 10:34Z). `launchctl list` shows it **still loaded**. Its header comment reads "operator requests 2026-10-18 (pane 344, session 620db313)".
- Its next4 branch has been firing `cc-lr rotate --account next4 --to next2 --until-idle 3600 --no-wait` 29 times, with `rc=1` and empty output every ~5-10 min since 10:11Z. The cause is `next4.reset_at` = 1792314078 (09:01Z): once that time is past, `capped="past-reset"` holds forever (drain-v2.sh, the "account 4 first" block). Measured: `grep -c 'next4 started'` gives 29.

### 2.3 Rescue tabs (handoff-fire rows with `"firing_sid":"344"` in `~/.claude/logs/handoffs.jsonl`, plus pane screens)
| Pane | Sid rescued | Fire start (UTC) | Outcome on the pane screen |
|---|---|---|---|
| 376 | 8db0e6f1 → next | 03:04:17Z (620db313) | engaged=1, ran live, self-recycled to ceaea24a 07:11Z |
| 377 | e739e5b5 → next | 03:07:27Z (620db313) | engaged=1, ran live, self-recycled to f1997ec3 15:48Z |
| 403 | 5232121f → next2 | ~07:13Z (2cc3a7fa) | `cd $'whose\n/Users/…'` failed: the agent's `--cwd` captured junk; "exited 1 — keeping a shell" |
| 409, 412, 416 | 5232121f → next2 | 07:19:58Z, 07:59:58Z, ~08:40Z | capacity-admit REFUSING (refusal 1, 2, 3 of 3), exit 9, shell kept |
| 410, 413, 419 | e52f1f63 → next2 | 07:20:16Z, 08:00:15Z, ~09:18Z | refusal 1, 2, 3 of 3, shell kept |
| 414, 417, 425 | 22a76c8a → next3 | 08:01:16Z, ~08:41Z, 09:19:54Z | refusal 1, 2, 3 of 3, shell kept |
| 418, 426, 435 | 2e9ed9f2 → next3 | ~08:01Z, 09:20:22Z, 10:57:12Z | refusal 1, 2, 3 of 3, shell kept |
| 430 | e52f1f63 → next2 | ~10:05Z (SessionStart quota stamp 05:05 CDT) | live |
| 433 | 22a76c8a → next3 | ~10:50Z | live, self-recycled to 09e18eed 10:52:16Z |
| 442 | 2e9ed9f2 → next3 | ~11:30Z | live 11:32Z, self-recycled to fad30cb7 14:20:58Z |

- Fired by `/tmp/lr-rescue/fire-next3-batch.sh` (03:00 CDT) and `/tmp/lr-rescue/fire-round.sh` (03:42 CDT). Both pass `--tab`. The handoffs rows record `"surface":"bg-tab"`, and every refused one has `"engaged":0`.
- `lr-handoff` itself printed "do NOT hand-spawn a recover-<sid> window — it carries no provenance, gets no registry row, and nothing can retire it" (e.g. `move/20261018T064955Z-next4-next2-7738/e52f1f63…handoff.log`, last line). 2cc3a7fa hand-spawned them anyway.
- The 2cc3a7fa transcript at 10:55:49Z reads: "Refused again, still at '1 of 1', so the budget seems to reset between fires. Firing again right away." The agent was looping on the refusal budget.

### 2.4 The STRANDED mechanism (handoff logs in each batch)
- `grep -c 'recycle ABORTED before /exit (held: load)'` over move/20261017-18 `*.handoff.log` gives **24**. `grep -c stub-present` gives **6**.
- e52f1f63 and 5232121f (batch 7738): "lr-transplant --phase unconfirm rc 2 … reason stub-present", then "!! recycle ABORTED before /exit (held: load): load 27.26/core … The session stays alive", then "verdict=STRANDED … source pane is a tombstoned husk".
- That "stays alive" line is false. `lead-crash-watchdog.log` at `[2026-10-18 02:07:23]` shows **both** sessions exiting in the **same second** (panes 1 and 21). It painted "✅ CLOSED CLEANLY … exited on its own (reason: -)" and then, at 02:07:46, recorded "cc-pane-close rc=1 … REFUSED — nothing says session … meant to end". The source stub that e52f1f63 left on next4 holds only exit-time records (cost-state, last-prompt, …).
- 22a76c8a (stub-present, load 15.22/core), 2e9ed9f2 (source-dead, 15.72/core) and 0d7c9a19 (stub-present, 31.54/core at 10:3xZ) follow the same pattern.
- Code: scripts/handoff-fire.sh:18583 sets `RCY_CONFIRM_RAN=1` (source retired). The load gate `hf_recycle_load_gate` is at :18600-18604, **after** that line. The `hf_recycle_hold` message at :3635 prints "The session stays alive" without checking the pid. Commit d58bb81d3 ("hold on load … in the precheck, before the transplant", 12:14Z) landed after most of the strands. 0d7c9a19 (10:39Z) and f06b5e9b (14:37Z) still hit the late hold.

### 2.5 Double-driven session: 3e929a81 (pane 23)
- Two recoveries ran concurrently. Bundle `bundle-20261018T075422Z` came from the poller REQUEST at 07:47:46Z. Bundle `bundle-20261018T075845Z` was placed by the reconciler ("placed_by=reconciler record_id=recon:next4-7d-1792314000:3e929a81:1").
- Both obtained capacity tokens (08:00:31Z and 08:00:33Z) and both armed a recycle on pane 23 (08:01:10Z and 08:01:12Z). One ended NOTMOVED with "source restored". The other ended STRANDED with "tombstoned husk".
- The result was a husk: the guard blocked the poller's nudge "Your weekly limit on next4 has reset…" (pane screen). poller.log logged STRANDED-HUSK at 10:24Z and 12:11Z, REQUEST-EXHAUSTED at 13:02:46Z, and owner row 884fc029b2f7.
- At 18:29Z, `cc-find 3e929a81` showed it **LIVE on tertiary in pane 23**, with `/goal active (3m)`. Someone recovered it during this investigation.

### 2.6 Input box contents (`kitten @ get-text --ansi`)
- Most "typed" text is **not** typed. It is Claude Code's dim prompt suggestion (SGR `22;2`). That covers panes 23 "/goal clear", 429 "/limit-recover to account 3", 433 "CC_DO_ASSUME_YES=1 cc-do …", 344 "replace by default", 270, 445, 47 and 393.
- Real junk: pane 430 showed `❯ [Pasted text #1][Pasted text #2]re) -->` at ~18:15Z. It was empty by ~18:25Z.
  - INFERRED: two pasted relaunch-prompt payloads (the `-->` tail matches handoff-fire's `<!-- handoff-fire … -->` prompt trailer). They came from the overlapping e52f1f63 rescue rounds that were still firing after 430 was live (2cc3a7fa at 10:55:42Z: "Stopping … the old round (its e52f1f63 launch is already live)").
- Pane 350 (f06b5e9b) sat on the "Exit and stop tasks" modal. Its transcript shows no record between 14:22:04Z and 18:18:57Z. A task-notification enqueued at 15:13:51Z was dequeued only at 18:18:57Z, together with `<command-name>/exit</command-name> … (no content)`. The drain batch's recycle on 350 ran 14:36:21Z to 14:37:52Z (recycle-intent, then recycle-held-load "unconfirm rc 0"). Later batches read `still-busy:composer-unknown` (16:34Z, 17:51Z).
  - INFERRED, 60%: the /exit landed between 14:37:52Z and 15:13:51Z from that recycle path, despite its "nothing was typed" verdict.
  - No keystroke audit log exists that could prove who typed it: `ls ~/.claude/logs | grep -i send` is empty.

### 2.7 Quota (`~/.claude/logs/account-utilization.jsonl`, last row per hour; 5h% / weekly%)
| UTC hour | next | next2 | next3 | next4 |
|---|---|---|---|---|
| 01Z (20:00 CDT) | 18/58 | 0/0 | 1/10 | 1/83 |
| 03Z | 77/79 | 0/0 | 0/10 | 9/89 |
| 04Z (next weekly reset) | 25/**7** | 0/0 | 2/10 | 20/92 |
| 06Z | 76/20 | 0/0 | 5/11 | 12/**100** |
| 08Z | 79/21 | 1/1 | 12/13 | 12/100 |
| 09Z (next4 weekly reset) | 0/21 | 1/1 | 6/15 | 12/**0** |
| 12Z | 2/22 | 1/1 | 25/20 | 4/5 |
| 15Z | 0/22 | 9/4 | 30/30 | 5/5 |
| 18Z (13:00 CDT) | 2/22 | 6/6 | **48/35** | 2/5 |

next2 stayed at about 0-6% all night, while the drain piled work onto next3. Load figures:
- Measured: 27.26/core at 07:11Z, 31.54/core at 10:39Z, 17.53/core at 14:27Z (handoff logs; 10 cores).
- Reported in a transcript, not measured by me: ~690 at 06:45Z (620db313's own text).

## 3. Causal chain and per-pane table

### 3.1 Timeline (UTC / CDT)
- 23:49Z / 18:49: the operator asks pane 344 (620db313) to `/limit-recover` all accounts to next. 18 manual batches follow, nearly all "still-busy … after 3600s" or "HELD".
- 02:07Z / 21:07: 620db313 fires the lr-inplace-immediacy fixer (pane 362, split-right, prompt fire-lr-immediacy.txt). It later lands 19 `fix(lr-move)` commits (12:14Z and 15:08Z waves). The live `~/.claude` layer therefore changed mid-incident.
- 02:14Z to 02:28Z / 21:14-21:28: e739e5b5, 246a91b5, e3dedc17 and 8db0e6f1 STRANDED. 620db313 writes resume-8db0e6f1.sh and resume-e739e5b5.sh at 22:02 CDT and fires them (tabs, then panes 376 and 377; engaged).
- 06:35Z / 01:35: 620db313 installs the drain LaunchAgent.
- 06:49Z / 01:49: batch 7738 (next4→next2). 07:07:23Z: e52f1f63 (pane 1) and 5232121f (pane 21) both exit. 07:11:59Z: both STRANDED. The watchdog paints CLOSED CLEANLY banners whose resume hints name the **old** account (`claude4 --resume e52f1f63`).
- 06:55Z / 01:55: the operator, in pane 401, types `cc-lr move --sid f06b5e9b --to next2`. The result is NOTMOVED, and pane 401 stays as a plain shell.
- 06:57Z / 01:57: pane 344 self-recycles 620db313 into 2cc3a7fa on next3 (handoffs `recycle-successor-staged`) under a Stop-hook goal it cannot meet alone.
- 07:03Z / 02:03: the drain's first next→next3 batch. 22a76c8a (07:28Z) and 2e9ed9f2 (07:30Z) STRANDED. Pane 332 prints "[lr-fire-resume] session ended (rc 0) — this pane is now an ordinary shell".
- 07:13Z to 10:57Z / 02:13-05:57: 2cc3a7fa writes `/tmp/lr-rescue` and fires 4 rounds of `--tab` rescues. That produces 13 husk tabs in OS window 18 plus live tabs 430, 433 and 442.
- 07:54Z and 07:58Z: the poller and the reconciler both drive 3e929a81. Pane 23 becomes a guarded husk.
- 10:00Z / 05:00: the poller autofire opens OS window 24 (pane 428, 509e3aad on next4, refused at capacity) and OS window 25 (pane 429, 5232121f on next2, live), each as a separate single-pane OS window.
- 10:22Z to 10:46Z / 05:22-05:46: drain batch 41444 strands 0d7c9a19 (stub-present at load 31.54/core). Claude in pane 242 exits at 10:40Z. The banner says `claude --resume` (next), but the real transcript is on tertiary.
- 14:36Z to 15:13Z / 09:36-10:13: pane 350 ends up on the "Exit and stop tasks" modal (§2.6), released 18:18:57Z.
- 15:48Z / 10:48: e739e5b5 self-recycles to f1997ec3 (pane 377, next2). The 15:49:47Z drain verdict "e739e5b5 STRANDED" is a false strand, and 2cc3a7fa kept reporting e739e5b5 as "stuck at git reset in pane 377" until 17:52Z (stale).

### 3.2 Pane → session → state → origin (snapshot 18:12-18:29Z)
| Pane (OS win/tab) | Session | State | Origin |
|---|---|---|---|
| 344 (18/146) | 2cc3a7fa next3 | live, goal-looping | operator ask 23:49Z; self-recycle of 620db313 06:57Z |
| 403 (18/156) | — (5232121f) | husk, failed `cd 'whose\n…'` | 2cc3a7fa rescue ~07:13Z |
| 409, 412, 416 (18) | 5232121f | husk, capacity refusal 1-3 | 2cc3a7fa fire-round 07:19-08:40Z |
| 410, 413, 419 (18) | e52f1f63 | husk, refusal 1-3 | same |
| 414, 417, 425 (18) | 22a76c8a | husk, refusal 1-3 | fire-next3-batch / fire-round 08:01-09:19Z |
| 418, 426, 435 (18) | 2e9ed9f2 | husk, refusal 1-3 | same, 435 at 10:57Z |
| 430 (18/170) | e52f1f63 next2 | live; real junk `[Pasted text #1][Pasted text #2]re) -->` (cleared by 18:25Z) | rescue ~10:05Z; junk INFERRED from an overlapping rescue round |
| 433 (18/171) | 09e18eed next3 | live | rescue of 22a76c8a 10:50Z → self-recycle 10:52Z |
| 434 + 454 (18/172) | 4a72e434 + teammate 05c876bd next3 | live | TrueMemory W2 wave, started 17:48Z (INFERRED: spawned from lead 433) |
| 442 (18/174) | fad30cb7 next3 | live | rescue of 2e9ed9f2 11:32Z → self-recycle 14:20Z |
| 1 (5) | e52f1f63 (dead source) | husk + "CLOSED CLEANLY" banner, wrong account hint | batch 7738 strand, 07:07Z exit |
| 242 (5) | 0d7c9a19 | husk + banner, hint names next while the transcript is on tertiary | drain batch 41444 strand, 10:40Z exit |
| 23 (5) | 3e929a81 | guarded husk on next4 until ~18:25Z, then live on next3 | poller + reconciler double drive 08:00Z |
| 332 (20) | — (2e9ed9f2 source) | husk "ordinary shell" | drain batch 37630 strand 07:30Z |
| 401 (21) | operator shell | plain shell holding `cc-lr move` output | operator 06:55Z |
| 428 (OS win 24, alone) | — (509e3aad) | husk, capacity refusal | poller autofire 10:00:12Z (duplicate: 509e3aad recovered in place in pane 28) |
| 429 (OS win 25, alone) | 5232121f next2 | live | poller autofire 10:04:31Z |
| 350 (21) | f06b5e9b next | /exit modal 14:4xZ to 18:18Z, then live | §2.6, INFERRED drain batch 33124 |
| 400 (22) | (status hidden; likely c23e89f1) | `git push` ask-rule permission modal | its own turn |
| 258 (3) | 9f6593c5 next | live TUI, transcript untouched since 10-17 03:29 CDT; HELD:no-shell every hour | pre-existing; decision 56c6862291f2 open |
| 445 (16), 374 (16) | 6f8d7bd2 next3 (/private/tmp/lr-proof-a), 7df606ba next | live test/proof sessions | lr-self-inplace work |
| 376, 377 | ceaea24a next2, f1997ec3 next2 | live | 620db313 rescues 03:04/03:07Z → self-recycles |
| 8, 47, 340 | 43e6eb4b, 7b50757e, 756b68c8 next2 | live | MOVED 07:15Z, 07:13Z, 07:56Z |
| 384 | 98e6f890 next3 | live | MOVED 16:51Z (2cc3a7fa) |
| 393, 398 | 2ee922eb next3, 5759497b next2 | live | poller HUSK 09:56Z / 11:37Z → relaunched |
| 28, 387, 397 | 509e3aad next4, 6069b9d3 next4, bc396360 next3 | live | recovered in place after the next4 reset (397: 0c354704 nudged 09:55Z → recycled 12:46Z) |
| 390, 246 | cc94029a next3, abe1d338 next3 | live | b102f5af / ef1947ad self-recycles 13:54Z / 10:42Z |
| 19, 27, 25, 26, 3, 386, 269-271, 455 | various | live (no lr damage) | — |

### 3.3 Sessions that were on next4 or next, and where each ended up
- **Reached next2/next3 by move:** 7b50757e, 43e6eb4b, 756b68c8 (→next2); 98e6f890 (→next3). 2e9ed9f2 went next4→next first (03:43Z).
- **STRANDED, then rescued by hand or by the poller:**
  - 5232121f and e52f1f63 → next2.
  - 22a76c8a → 09e18eed, 2e9ed9f2 → fad30cb7, b102f5af → cc94029a (all next3).
  - 8db0e6f1 → ceaea24a (next2), e739e5b5 → f1997ec3 (next2).
- **Recovered in place on next4 after its 09:00Z reset:** 509e3aad, 6069b9d3, c23e89f1, 0c354704 (→ bc396360 on next3).
- **Self-recycled during a move (false STRANDED, INFERRED):** 246a91b5 (→ e52f1f63, same cwd and pane 1), e3dedc17, ef1947ad (→ abe1d338), 984d1eb2 (ended normally 08:46Z).
- **Still on next at 18:30Z:** 9f6593c5 (no-shell), f06b5e9b, a3da0696 (bg job), d7eb73d2 (mid-turn), 7df606ba.
- **Failed:** 3e929a81 was exhausted at 13:02Z and live only from ~18:25Z. 0d7c9a19 is dead.

### 3.4 Work at risk of being LOST
- **0d7c9a19: DEAD, not resumed anywhere.** The full transcript is on tertiary (2.6 MB, last record 10:06Z), with a 4 KB stub on next. Its last turn reads "✅ Good to close: yes … nothing to do", so **no work is lost**. The resume hint in its banner points at the wrong account.
- 22a76c8a, b102f5af, 8db0e6f1, e739e5b5, 2e9ed9f2: **not lost**. Each one's work continues in a live successor (cc-find LIVE: 09e18eed, cc94029a, ceaea24a, f1997ec3, fad30cb7). Each successor's first prompt names its predecessor's task.
- 9f6593c5: alive but frozen. There have been no transcript writes for ~39 h, so treat it as at risk.
- 3e929a81: at risk for 10 h (husk), live since ~18:25Z.

## 4. Immediate remediation (describe only; the parallel worker had done most of it by 18:31Z)

At 18:31Z `kitten @ ls` shows 10 OS windows, each with 1 tab. OS window 18 is down to panes 434 and 433. OS window 25 holds 429, 344, 430 and 442. The husks 1, 242, 332, 401, 403-426, 428 and 435 are gone, and so are 400 and 454.

Still to do:
1. **Stop the drain LaunchAgent.** Use its own pause file, `~/.reso/limit-recover/listeners/drain-to-next3.off`, or unload `com.reso.drain-to-next3`. It keeps rotating next4 every ~5 min against a dead condition and keeps moving next sessions to next3 until 2026-10-20 10:34Z. This needs the operator's call.
2. OS window 26 has a single pane (398). Fold it into a 4-split fullscreen window. Check that windows 18 (2 panes) and 25 are fullscreen on their own Space.
3. 0d7c9a19 is done, so leave it closed. If it is ever wanted, resume it on **next3** (`claude3 --resume 0d7c9a19…`), not with the banner's `claude` command.
4. Pane 258 (9f6593c5): answer decision 56c6862291f2 (replace a no-shell pane beside it), or close it after checking its transcript.
5. Pane 400 (`git push` ask modal, if it still exists elsewhere) needs the operator.
6. Close the proof/test sessions 445 (/private/tmp/lr-proof-a) and 374 if their proof is done.
7. Pane 344 (2cc3a7fa) is looping its Stop-hook goal on items only the operator can answer. Clear its goal or release it.
8. Archive `/tmp/lr-rescue/`. Its scripts are still executable and would re-spawn tabs if re-run.

## 5. Long-term fix (file:line targets) and the test that would have caught it

1. **Load gate before the confirm.** In scripts/handoff-fire.sh, move `hf_recycle_load_gate` (:18600-18604) ahead of the `lr-transplant --phase confirm` block that ends at `RCY_CONFIRM_RAN=1` (:18583). Then a load hold never needs an unconfirm.
   - Also make `hf_recycle_hold` (:3615-3636) check `kill -0` on the source claude before printing "The session stays alive". If the source is dead, return a distinct code so that lr-handoff relaunches (watcher-driven) instead of returning STRANDED.
   - Also make `lr-transplant --phase unconfirm` fold an exit-time stub (cost-state/last-prompt only) instead of refusing `stub-present`.
   - Test: a bats test that stubs `hf_recycle_load_gate` to return 1 with the source pid alive and a stub written after the confirm. Assert: verdict NOTMOVED, no tombstone, source `<sid>.jsonl` restored. A second case kills the source pid and asserts that a relaunch is attempted, not STRANDED.
2. **A refused launch must not keep a pane.** In bin/cc-pane-runner:179-181, treat exit 9 (the capacity-admit refusal from lr-fire-resume) as "never started" and close the pane.
   - Better: run capacity admission in handoff-fire **before** `kitty @ launch` (scripts/handoff-fire.sh:1585 launch helper), so nothing is opened only to be refused.
   - Test: run cc-pane-runner with a launcher that exits 9 and assert the window closes, not "keeping a shell".
3. **No tabs from agents.** Make scripts/handoff-fire.sh:14535 (`--tab`) and :15196 (bg-tab) refuse unless `CC_OPERATOR_TTY=1`, or map them to split-right in the caller's fullscreen window. Add a PreToolUse lint that blocks `handoff-fire.sh … --tab` and `--launcher /tmp/*` in agent Bash commands.
   - The 2026-07-26 directive quoted at :15185-15193 already says background tabs are invisible. The surface is still reachable.
   - Test: fire with `--tab` from a non-operator env and assert a refusal.
4. **A single driver per sid.** The reconciler's assign path (lr-handoff placed_by=reconciler) must take the same `runs/by-sid/<sid>.active` claim as the poller REQUEST path *before* the capacity token is taken.
   - Test: start two lr-handoff runs on one sid 2 s apart and assert that the second gets `claim-held` and never reaches `admitted`.
5. **Close banners must be honest and actionable.** In hooks/lead-crash-watchdog.sh:1687-1742, when the sid has a tombstone or a live copy elsewhere (cc-find), label the close "moved" and auto-close the pane via `pane_verdict_close` (:1814). cc-pane-close must accept a tombstone as "meant to end".
   - Build the resume hint from the account that holds the live transcript, not from the pane's original account.
   - Test: fixture with a tombstoned source and a target transcript on tertiary. Assert the banner says `claude3 --resume` and the pane is closed.
6. **No agent-installed daemons outside the repo.** Fold the drain behaviour into lr_recon, with a reset-aware "capped" (clear `past-reset` once the poll reads under 100%). Add a sweep that pages on any `~/Library/LaunchAgents/com.reso.*` not shipped from the repo.
7. **Keystroke provenance.** Wrap every `kitten @ send-text` (it2, handoff-fire, the poller nudge) to append `{ts, pane, caller, sid, sha256(bytes), first 40 chars}` to `~/.claude/logs/pane-keys.jsonl`. Without it, the /exit in pane 350 and the paste junk in pane 430 cannot be attributed.

## 6. Confidence: 80%

- **High (90%+):** request origins (plan.json), rescue-tab origins (handoffs rows plus `/tmp/lr-rescue`), the strand mechanism (24 logged holds, code order at :18583 vs :18600), the drain LaunchAgent, and the double drive on 3e929a81.
- **Lower:**
  - What actually ended e52f1f63 and 5232121f at 07:07:23Z while the log claims "/exit NOT submitted": unresolved, 50%.
  - Who typed /exit into pane 350 (60%) and the paste into pane 430 (60%).
  - The predecessor-successor links inferred only from cwd and pane (246a91b5 → e52f1f63).
- **What would change it:** a send-text audit log, the `handoff-recycle-1-1792307053-*.log` watcher trace past its arm lines (it ends after pane-probe), or a kitty debug log for 07:07Z and 14:37-15:13Z.

## Adversarial verification

Verifier pass, 2026-10-18 ~18:40Z. Read-only. I re-opened every cited line and log myself.

**Verdict: the attribution mostly holds. The STRANDED mechanism is mis-ordered, and fixes 1c, 2 and 5 need changes.** Pane 344 really did originate the batch volume, the drain LaunchAgent and the `--tab` rescue husks. But the strands are a handoff-fire defect that is independent of 344: the source claude had already exited **before** the load hold. The hold then disarmed the watcher that would have relaunched it. Load ordering is not the cause.

### What the doc gets wrong (MEASURED)
1. **The exit came before the hold, not after it.**
   - The exits, from close records: e52f1f63 (`close-records/33120-1792302738.json`) and 5232121f (`44391-1792304076.json`) both have `ended_at 2026-10-18T07:06:14Z`, `exit_code 0`.
   - The holds came 25 s later, at 07:06:39Z and 07:06:40Z (`handoffs.jsonl` `recycle-held-load`).
   - The stub `e52f1f63….jsonl` on next4 has mtime 02:06:13 CDT. It holds only bridge-session/cost-state/last-prompt/mode records, with no `/exit` command record.
   - 07:07:23Z, the time the doc gives for the exits, is when the watchdog painted the banner (`lead-crash-watchdog.log:63740-63741`).
   - So "The session stays alive" was false when it was printed, not made false by a later exit.
2. **`stub-present` and `source-dead` are refusals for a dead source, by construction.** `lr-transplant.sh:609-617` already folds a stub when the source is LIVE. It refuses `stub-present` only when `lrt_held` finds no live holder. Proposed fix 1c ("fold an exit-time stub instead of refusing") is therefore mis-specified: restoring the transcript onto an account where nobody is running it leaves a husk either way.
3. **The load hold is benign when the source is alive.** Over the 10-17/10-18 `*.handoff.log` files, the 24 `(held: load)` lines split into 16 with `unconfirm rc 0` (source alive, NOTMOVED, nothing lost) and 8 with `unconfirm rc 2` (6 stub-present, 2 source-dead).
   - In all 7 rc-2 cases I checked, the source's `claude-crashes.jsonl` clean-exit row sits within about 2 minutes of the hold: e739e5b5, 8db0e6f1, 2e9ed9f2 (twice), 22a76c8a, b102f5af, 0d7c9a19.
   - In the dead-source cases the source exited before or around the hold. For 2e9ed9f2 at 03:39Z it was 2 minutes before.
4. **The actual strand mechanism: a hold after the subject is gone disarms a live watcher.**
   - The pane 21 watcher log (`$TMPDIR/handoff-recycle-21-1792307053-2nf8Jn.log`, last line) reads "pane 21 CONFIRMED at a shell prompt after 97s — typing relaunch". The hold then disarmed it, and no `type-attempt` follows.
   - In the same batch, 7b50757e also "exited on its own before the last read" (its handoff.log:35). `hf_recycle_subject_yield` left its watcher armed, the watcher typed the relaunch at 07:08:52Z, and the session was MOVED.
   - Code: handoff-fire re-checks `hf_recycle_subject_gone` at `:18589` (1 of 3), `:18615` (2 of 3) and `:18638` (3 of 3). It does **not** re-check before the two post-confirm holds at `:18595` (last read) and `:18601-18603` (load gate). The comment at `:18612` itself says those two steps "can take minutes under load".
5. **Two sessions in one batch exited in the same second, twice.** The pairs are e52f1f63 and 5232121f (07:06:14Z), and 22a76c8a and 2e9ed9f2 (crash rows both 07:23:20Z). Each pair's handoff-fires also started in the same second (07:04:13Z). I found no keystroke or kill actuator between the confirm and the load gate: `hf_recycle_last_read`, `hf_wake_guard` and `lr-transplant --phase confirm` have none. The trigger of these "on its own" exits is **unresolved**, and it is the real open root cause.
6. **Counts.**
   - Drain-placed batches: `plan.json` with an empty requester from 07:03Z to 18:07Z gives **11**, not 13 (the claim) or 16 (§1 item 2). Nine match `drain-to-next3.log` "next started pid N" lines (37628→37630 and so on). Two are next4 rotates (37587, 44771).
   - Rescue tabs: `handoffs.jsonl` has only **10** `bg-tab` rows with `firing_sid 344` on 10-18 (376 and 377 engaged; 409, 410, 412, 413, 414, 425, 426 and 435 at engaged=0). Panes 403, 416-419, 430, 433 and 442 have no fire row. Their attribution rests on pane screens that are now closed, so it is unverified.
   - Pane 434 was a `bg-tab` fired by pane **433**. OS windows 24 and 25 came from the poller. So "all … traces back to one origin session" is overstated.
   - Rotate count is now 30 (18:37Z), so the drain is still live.
7. **The drain's next4 `past-reset` branch is intended behaviour, not a misread.** drain-v2.sh:6 states the design: "next4 -> next2 once capped/rejected **or past its weekly reset**". The fault is that it never stops after rc=1, not a mistake in reading the cap.
8. **3e929a81 had three drivers, not two.** Drain batch `072521Z-…-37587` made bundle-20261018T072708Z (placed_by=cc-lr-move), before the poller and reconciler bundles. The poller's by-sid claim did work at 08:02:09Z (`poller.log:217347` RUN-CLAIM-HELD), so fix 4 covers only the reconciler path.

### Fix review
- **Fix 1a (move the load gate before the confirm)** would not have saved e52f1f63 or 5232121f. The source exits on its own after the watcher arms whatever the gate order, and a pre-confirm hold still disarms that watcher. d58bb81d3 (12:14Z) already adds a precheck load hold before the transplant.
  - Replacement: in `hf_recycle_hold` (`:3615`), when `RCY_CONFIRM_RAN=1` and `hf_recycle_subject_gone`, call `hf_recycle_subject_yield` and `return 0`, leaving the watcher armed with no unconfirm and no disarm.
  - Test: a bats case where the load gate returns 1 and the pinned pid has exited. Assert that no `recycle-held-load` row is written, the watcher is still alive, and a `recycle-subject-exited` row is.
- **Fix 1b (hold checks the pid)** is right in spirit. "Relaunch" should mean "don't disarm the already-armed watcher", not a new launch path.
- **Fix 2 (close the pane on exit 9)** has two problems:
  - It must still pass the fullscreen guard at `bin/cc-pane-runner:201-215`. Emptying a native-fullscreen window crashed kitty on 2026-10-15.
  - The kept shell is the only visible marker of an unowned session, and lr-fire-resume:790 tells the reader to "re-run this exact command". Close the pane only after writing a durable owed record (a poller REQUEST or resume debt), or the strand becomes invisible.
- **Fix 3:** `CC_OPERATOR_TTY` does not exist (`git grep` finds nothing), and an agent can set any env var. The PreToolUse lint is the only real control. No shipped caller passes `handoff-fire --tab` (`git grep`, scripts/bin/hooks/skills).
- **Fix 5 would hide strands.** At 07:07Z e52f1f63 had a tombstone but **no** live copy: its events.jsonl reads "no live process holds the session (resume debt: none)". Treating "tombstone" as "meant to end" and auto-closing would have deleted the only signal. Require a cc-find LIVE copy, never a tombstone alone.

Missing from the doc: the pane-21 watcher evidence, the 16/8 split of the load holds, the 7b50757e control case, the open trigger of the "exits on its own" events, and the drain still being live.

Adjusted confidence in the doc's root cause as written: 55%. Attribution to pane 344: about 85%. The strand mechanism needs the correction above.
