# Post-mortem: account 1 ("next") left 21% of its weekly limit unused (revision 2)

Scope (frozen): measure how much of account 1's (next's) weekly limit went unused in the week ending 2026-10-18T04:00Z, explain why, and rank fixes that would have prevented it.

Produced by workflow `wf_06251d2d-207`, which ran 25 agents: 9 investigators, 9 adversarial verifiers, a synthesis agent, a completeness critic, 4 gap investigations and a final revision, with 0 errors. The working notes in /tmp/wk-postmortem/ are temporary and are not part of this commit. Section 7 records the rotation attempted the same night.

The week studied runs from 2026-10-11 04:00Z to 2026-10-18 04:00Z. All times are UTC; local CDT is UTC minus 5. Oct 11 was a Sunday.

Evidence tags:
- **[M: source]** means measured, from that file, line or command.
- **[E: method]** means estimated, by that method.

Notes and scripts are in /tmp/wk-postmortem/:
- The `<dimension>.md` and `<dimension>.verify.md` files, plus my spot-check scripts `synth_check.py`, `synth_check2.py` and `synth_day.py`.
- The gap notes: `banked-resets.md` (gap-1), `gap-2.md` and `gap2/` (gap-2), `gap-3.md` and `gap3/` (gap-3), and `crossweek.md` and `gap4/` (gap-4).
- The critic's `crit_*.py` scripts.

I used only claims that survived the adversarial verification, with the verifiers' corrections applied. Rows marked "06:28:55Z" come from my own read of ~/.claude/logs/account-utilization.jsonl:54771-54774 at 06:29Z on Oct 18. Section 6 lists the claims I dropped as refuted and the corrections made in this revision.

---

## 1. Answer

### Account 1 (next) left 21 points of its weekly limit unused

- **Measured.** It read 79% at 03:52:31Z and reset to 0 at 04:00:21Z [M: ~/.claude/logs/account-utilization.jsonl:54683 and :54687; re-checked with synth_check.py].
- **About one full 5-hour window.** One fully used 5-hour window moves the weekly meter about 24-27 points [M: median 5-hour-to-weekly ratio of 0.24-0.25 over 35 windows].
- **About 36 hours of active work.** That is at next's own rate of 0.58 points per active session-hour [E: 79 points / 137.2 active session-hours].
- **In money, two numbers:**
  - **Subscription cash: about $10.** [E: 21% × about $46-50 per account-week]. The operator's ruling is quoted at ~/.claude/logs/bash-commands.log:134598: "a week of a $200/mo plan is ~$50; unused weekly quota is gone".
  - **Value of the work at API list price: roughly $260-$550.** [E: $12.4-$26 per point]. This is what the same work would cost through the API, not cash lost. The range is wide because the data cannot tell whether cache reads count against the meter.
- **next's first miss in six windows.** Its previous five windows, Sep 13 to Oct 11, all ended at 100% [M]. Across the fleet, 22 of 24 resets since Sep 12 ended at 100% [M: resets.py].
- **next has slipped for two windows.** Its cumulative use at the end of day 6 was 97, 89, 100, 62, then 42 [M: v7.py]. The decline is 100 → 62 → 42.
- **The whole gap against last week opened on day 5** [M: python over account-utilization.jsonl, last poll before each 04:00Z; crossweek.md §1].
  - Daily gains last week: +13, +0, +4, +11, +20, +14, +38.
  - Daily gains this week: +14, +1, +9, +5, +0, +13, +37.
  - Days 1-4 reached 28 last week and 29 this week. The last 48 hours used 52 and 50.
  - The difference is Oct 8 (+20) against Oct 15 (+0).

### Fleet-wide, only next stranded this week

Four weekly windows closed during the week, and three of them reached 100% [M]:

| Account | Reached 100% | How far ahead of its reset |
|---|---|---|
| next2 | Yes | 5.9 hours |
| next3 | Yes, after a 99-point rescue sprint | 10.3 hours |
| next4 | Yes | 0.6 hours |
| next | No, ended at 79% | 21 points stranded |

So the fleet stranded 21 of 400 points (5%). Part of what filled next2 and next4 was work routed away from next. 272.3M PU of auto-routed burn whose originating fire fell inside the login-cliff window landed on other accounts [E: gap4/divert2.py]. So the cliff mostly decided which account stranded (section 2, cause 1).

**At risk right now** [M: account-utilization.jsonl:54771-54774, 06:28:55Z]:
- **next3** is at 11% (k 5), with its reset at Oct 20 12:00Z, about 53.5 hours away.
  - Its forecast strand is 81.3 points [M: `claude-accounts --rank general --json` wk_strand_pp, gap-2].
  - It needs 1.67 points an hour and is burning 0.16 [M: gap-2].
  - It sat at 0% with k=0 from Oct 13 12Z to Oct 16 12Z [M: g1_traj.py].
  - This is about four times this week's strand, roughly $37 of subscription value [E: 81 × $0.46].
- **next4** is at 97% (5-hour 39%, k 16), with its reset at 09:00Z. At most about 3 points are exposed.
  - The limit-recover rotation onto next4 (the parallel request) is aimed at exactly this.
  - After 09Z, nothing automatic will move those panes off next4's fresh 7-day window [M: gap-2 finding 4]. Point them at next3.
- **next is burning its fresh window.** It went from 0 to 19% between 04:00Z and 06:28:55Z, at k 22-32 [M: :54771; gap-2 util rows]. next3 could have absorbed that load [gap-2].
- **next2's 0% since its Oct 17 11Z reset is real idleness, not a meter error.**
  - About 3.8M PU ran on next2 from Oct 17 11Z to Oct 18 04Z. That is about 0.5 points at next2's 8.2M PU per point [M: activity.md hourly table; activity.verify.md #2].
  - It read 5-hour 0% with k 2 at 05:24Z, and weekly 0, 5-hour 0, k 2 at 06:28:55Z [M: :54774].

### Banked resets: a second asset that expires if unused (gap-1)

**Two unscheduled mid-window resets happened since Sep 15. Both were banked-reset redemptions.**
- next4 dropped 100 → 0 on Oct 1, 20:12-20:24Z. next3 dropped 100 → 0 on Oct 2, 01:51-01:58Z. In both cases weekly_reset_at did not move [M: crit_drops.py => lines 40660 and 40853]. quota-reset-detect.jsonl has 9 rows, all scheduled [M].
- The operator's own words identify them as redemptions [E: ~/.claude-quaternary/history.jsonl, sid fa8cd45f; ~/.claude-tertiary/history.jsonl 01:51:55Z].
- A redemption refills the 5-hour, weekly and Fable limits and keeps the weekly anchor [M: account-utilization.jsonl around :40660].

**Together they yielded 174 of 200 points.**
- next3 used its grant in full. It reached 100 at 2026-10-06T04:02Z, line 44501 [M: g1_wall.py].
- next4 stranded 26 points: it peaked at 74, account-utilization.jsonl:42892 [M].
- The cause was split demand, not too little time. next3 was redeemed 5.6 hours later, and the fleet burned only 131 points during next4's 60.75-hour runway [M: g1_burn.py].

**next and next2 probably each still hold one grant: up to 200 points (about $92 at $46 per grant), expiring Oct 22** [E; unverified].
- No live `?cedar_ember=1` read ever succeeded. Session 973d5003 was throttled with 429 errors [M: transcript L125, L241, L313].

**The bank explains 0 of this week's 21 points.**
- next never hit a limit: weekly peaked at 79 and no row had session_pct ≥ 100 [M: scan from Oct 11 04Z].
- A grant can be used only at a limit (`use_requires_limit` defaults to true in the CC 2.1.302 binary [E]).

**At last week's demand the two grants would yield about 0 points.**
- Capacity to Oct 25 04Z, about 475 points, already exceeds demand of about 395 [E: g1_burn.py, 401 points/week].
- Full value needs about 1.7 times last week's demand, routed onto next and next2 after their walls [E].

**The CLI can no longer redeem the bank.**
- In CC 2.1.302, tengu_cedar_ember is absent from all four account configs [M: `jq .cachedGrowthBookFeatures.tengu_cedar_ember`].
- On next2 and next3, `/limit-reset` is now tengu_nifty_lemur: a once-a-week reset of the 5-hour session that charges the weekly meter [M: binary strings].
- The bank is now offered at a wall through clau.de/reset.

**Nothing local can read the bank or record a redemption.**
- bin/claude-accounts mentions it only in comments [M: grep].
- 0 transcript records of a redemption were found [M: g1_cmd.py over 18,575 transcripts].

### Fable sub-cap

- next used 1% of its Fable sub-cap. Every account left 86-100% unused [M: highest fable_pct per account].
- **This is not extra money. Fable is a slice of the weekly limit.**
  - Of 117 polls since Sep 20 where fable_pct rose, 0 had both the 5-hour and weekly meters flat.
  - The weekly-to-5-hour ratio was 0.229 when Fable rose and 0.242 when it was flat [M: /tmp/wk-postmortem/crit_fable.py over account-utilization.jsonl].
- **Coupling.** In those same polls weekly use rose 117 while Fable rose 161. That is at most 0.73 weekly points per Fable point [M: crit_fable.py]. It undercuts the earlier 0.24 estimate from two bursts; ~/.claude/accounts.json:36 assumes 0.5.

### Why, in plain terms

- **This week matched last week except on day 5.** Days 1-4 and the last 48 hours came within 2 points of last week. Oct 15 (+0) against Oct 8 (+20) is the gap [M: crossweek.md §1].
- **For account 1, the main cause was a routing penalty.**
  - From Oct 15 04:12Z, the login-cliff ×0.25 penalty ranked next last in the general (automatic) lane and in recycle repicks.
  - The desk lane exempted next until Oct 17 16:12Z.
  - Last week, 91% of next's Oct 8 burn came from automatic routing [M: gap4/lineage3.py]. This week that automatic supply went to next2 and next4 instead: 272.3M PU, about 24-28 points at next's rate [E: gap4/divert2.py].
- **For the fleet, the main cause was the operator being away on day 5, with nothing to replace him.**
  - On Oct 15 the fleet burned 132M PU, the lowest of 14 days. Oct 8 burned 269M [M: gap4/cw.py].
  - 93% of Oct 8's burn on next came from fires made while the operator was present [M: gap4/dep.py].
- **The idle middle was not new.** next used 24 points from Oct 12 to Oct 16 with 1.6-5.6 sessions open, mostly idle. Last week's middle was idler, and next still filled [M: crossweek.md §1; synth_day.py].
- **The finish was limited by working sessions, not by a ceiling.**
  - next's 5-hour meter peaked at 77%, and no hour was capped [M].
  - From 19Z to 23Z on Oct 17, weekly use went only from 56 to 58 at k 13-20 [M: activity.md hourly table]. In that stretch, 4 lane sessions waited 3-4 hours on `git push` permission prompts [M: gap-3].
- **Nothing acts on the forecast.**
  - The shortfall was forecast from Oct 12, but nothing turns that forecast into work.
  - That earlier weeks were filled by the operator's own sprint is an inference from the memory file feedback-quota-is-filled-on-purpose-not-a-concurrency-limit.md, not a measurement (mechanisms.verify.md #1).
  - What was measured last week: automatic routing onto next on Oct 8 while the operator was present. Then over the last two days, one operator-launched session (58d3640a, 98.2% subagents) ran about 24 hours unattended [M: gap4/cw.py; rows_prev.pkl].
  - Probably some untracked headless "quota burn on next" as well [E: gap4/headless.py].

---

## 2. Root-cause tree

### Root: filling the weekly limit depends on people and lucky routing, not on a mechanism

Nothing turns a forecast shortfall into work when no one acts. This was necessary for all 21 points.

- **No fill mechanism exists.** Three of the nine investigations (demand, mechanisms, policy) independently grepped bin/, scripts/ and hooks/ and found nothing that fills unused quota.
- **The only arm that creates work never fired.** drain-revival-arm ran 320 times in log-only "would-fire" mode and fired 0 times [M: idl.jsonl plus its gz rotations]. The ruling it waits on (decision 58d62776eb1f, backlog c109e9e850fb) has been open since Sep 30 and was due Oct 7.
- **The forecast was there.** wk_strand_pp showed next stranding 21 or more points from Oct 12 04:07Z, 144 hours ahead [M: alarms replay, which matches `claude-accounts --strand-score`].
- **But the forecast is weak far out.** At 48-96 hours ahead it is right only 11-25% of the time [M: `--strand-score` cells].
- **Nothing acts on it.** Its only uses are readout text and two re-rankers that act only on nearly-full accounts.
- **What filled last week was circumstance, not a mechanism.** Automatic routing happened to favour next while the operator was present (Oct 8), plus one long unattended session the operator launched [M: gap4/lineage3.py, gap4/dep.py, gap4/cw.py].

### How the points split, and how sure we are

The causes are ranked by points explained on next. The ranges are estimates and overlap, so they do not add up to 21. Two methods were used:
- **Cross-week Shapley.** This splits the credit over two factors: whether the operator was present on Oct 15, and whether the ×0.25 cliff applied (Oct 15 04:12Z to Oct 17 16:12Z). In this week's points (9.63M PU per point) it gives [E: crossweek.md §7]:
  - cliff about 14.5-20
  - operator absence about 1-6.5
  - late sprint about 0-2
  - idle middle about 0
- **Bottom-up estimates per mechanism**, given under each cause below.

**Calibration caveat.** next cost 6.74M PU per point last week and 9.63M this week [M: gap4/calall.py]. Part of that difference is untracked headless use last week [E]. So converting PU to points across weeks is uncertain.

### Cause 1: the login-cliff penalty sent next's automatic work to other accounts (routing). Estimated 5-20 points on next.

The bottom-up estimate is 5-10 points; the cross-week estimate is 14.5-20. For the fleet as a whole the net loss is about 0-5 points: most of this moved unused quota between accounts rather than creating it.

**What the rule did.**
- next's login token was due to expire Oct 22 04:12Z [M: auth-timeseries.jsonl].
- From Oct 15 04:12Z, the general-lane score multiplied next by 0.25 [M: bin/claude-accounts:3330-3332; :5740 score_general multiplies _dispatch_cliff_factor].
- Recycle repicks inherit that factor. A recycle moves when best/current ≥ REPICK_RATIO 4.0 (bin/claude-accounts:3530; scripts/handoff-fire.sh:15208). So a recycle on next moved whenever next was not the raw top pick [M: gap-4].
- **The desk lane did not apply the factor until late on Oct 17** [M: ~/.claude/route/route.jsonl:5073-5148]:
  - Its rows give next a desk factor of 1.0 on Oct 15 (03:23, 05:01 and 17:16Z), on Oct 16 (05:16-15:53Z) and on Oct 17 (00:41, 04:31 and 07:23Z).
  - next was the desk's pick in those three Oct 17 rows.
  - The 0.25 first appears in desk rows at 22:54Z on Oct 17 [M: route.jsonl:5158].
- The expiry falls after the weekly reset, so this week the penalty protected nothing.

**What it changed.**
- **Oct 15.** After the kitty crash, repair fires worth 47.9M PU were auto-routed to next4 at 05:37-05:46Z. Without the cliff, the replay ranks next first all day [M: gap4/divert2.py; scripts/replay_general.py].
- **Oct 16.** Automatic fires went next2 23, next4 10, next 0 [M: handoffs.jsonl; re-checked].
  - next was ranked last in 25-26 of the 32-33 rankings recorded that day [M].
  - Without the factor, 38 of the 45 rankings next lost would have gone to next: 21 taken from next4 and 17 from next2 [M: verify/cf.py].
- **Over the whole cliff window,** 272.3M PU of auto-routed burn landed on other accounts: 51.0M on Oct 15, 105.8M on Oct 16 and 115.6M on Oct 17. That is about 24-28 points at next's rate, more than the 21 stranded [E: gap4/divert2.py at 9.63M PU per point, with routing.md's 85% capture].

**Related rules kept next starved on the last day.**
- The desk lane's exemption (DESK_LIFE_H, login_h ≤ 108h) lapsed at Oct 17 16:12Z, so 4 desk launches at 22:54-23:47Z went to next4 [M: route.jsonl:5158-5164].
- 7 limit-recover placements on Oct 17 went to next4 [M].
- DESK_5H_FLOOR=0.60 sent the operator's own `claude` to next4 at 02:57Z on Oct 18 [M; route.jsonl:5166].

**The protection the penalty exists for could never have worked.**
- cc-relogin-poll was checking next from Oct 15 05:02:40Z. It logged SKIP each time because live sessions were above zero ("k=3 (>0) — cc-relogin would refuse"); the log holds 181 "SKIP next" rows [M: ~/.claude/logs/cc-relogin-poll.log:2023; `grep -c`].
- Its first ATTEMPT came at Oct 16 07:07:24Z, about 27 hours in, with the session count unmeasured ("k=?") [M: cc-relogin-poll.log:2046]. The blocker was the k==0 gate, not a late start.
- All 8 automatic re-login attempts failed: live sessions never reached 0, `ps` failed, or the attempt timed out [M: cc-relogin-poll.log, cc-relogin.log].
- The re-login that finally succeeded, at 23:27:59Z, did so with 15 sessions live [M: auth-timeseries.jsonl:62633]. So the zero-live-sessions requirement isn't actually needed.
- The renewal did not lift the penalty at once. Desk rows at 23:37:50Z and 23:47:18Z still show runner_up=next with factor 0.25, 10-20 minutes after the renewal [M: route.jsonl:5162, :5164].
  - When the factor actually cleared is not recorded. The next desk row (02:56:59Z, route.jsonl:5166) has next3 as runner-up.

**The fixes came too late or have not landed.**
- Commit c33e5c0b2 was authored at 00:33Z and committed at 02:08Z on Oct 18, after the re-login. It changed nothing this week [M: `git show -s`]. It also keeps the 108-hour condition that lapsed on Oct 17.
- DESK_5H_FLOOR = 1.00 was committed on branch cc-022337-11276 as 367539c52 at 06:02Z Oct 18, following the operator ruling of Oct 17. Trunk still has 0.60 [M: `git log`; `git grep` main:bin/claude-accounts:3579; wt-cc-022337-11276 bin/claude-accounts:3587].

**Why the two estimates differ.**
- **The bottom-up estimate (5-10) holds back for four reasons:**
  - next's second flat run started 8 hours before the penalty did.
  - Oct 15 had only about 5 fires that could have moved.
  - Fires turn into quota use only weakly.
  - next2 had only about 6 points of room to give up.
- **The cross-week estimate (14.5-20) counts more:**
  - Last week's day 5 (+20) was 91% automatic routing onto next.
  - A replay of last week with ×0.25 on next puts every hour of Oct 7-10 on next4 [E: gap4/replay_prev.py, which omits k_native].
  - The 272M diverted PU exceeds the strand.
- **For the fleet:** next2 reached 100% at its Oct 17 reset and next4 is at 97% [M]. So the diverted work was used; it mostly changed which account stranded.

### Cause 2: the operator was away on day 5, and nothing replaced him (demand). Estimated 1-6.5 points on next; about 14 points-equivalent fleet-wide.

This is the only cause that removed demand from the fleet rather than moving it [E: crossweek.md §7; 132M vs 269M PU].

**Day 5 compared.**
- On Oct 15 the fleet burned 132M PU, the lowest of 14 days. Oct 8 burned 269M, with 57 prompts over 7.0 presence-hours [M: gap4/cw.py].
- Oct 15 had 14 prompts over 2.4 presence-hours on the UTC day; activity.md counts 5 daytime prompts on the CDT day [M].
- next started 0 new sessions and burned 1.7M PU. Its share of fleet burn fell from 41% on Oct 8 to 1.3% [M: gap4/hops.py, gap4/cw.py].
- Oct 8's burn depended on the operator being present: 93% (101.6M) came from fires made while he was present [M: gap4/dep.py].
- When only day 5 is varied (Oct 16-17 held fixed) the split is [E: crossweek.md §7]:
  - cliff 6-11.5 points
  - absence 8.5-14 points
  - 2-13 points of interaction: a day like Oct 8 needs both a present operator and no cliff.

**next sat flat for long stretches.**
- It used 0 points in 119 of 168 hours [M].
- The two longest flat runs were 28 hours at 14% (Oct 11 23Z to Oct 13 03Z) and about 32 hours at 29% (Oct 14 20Z to Oct 16 04Z) [M].

**Sessions were open but idle.**
- next averaged 2.8-5.6 open sessions on Oct 13-16, and 1.6 on Oct 12 [M: synth_day.py].
- Only about 17% of open session-hours had any token activity [M: tokens.verify].
- From Oct 15 06Z to Oct 16 00Z, next used zero tokens with 3 sessions open [M].

**The slowdown was fleet-wide.**
- The fleet used 45, 42 and 18 points on Oct 13-15, against about 57 a day at a steady pace [M].
- The fleet averaged 25.6 open sessions all week [M]. So what was short was work inside sessions, not sessions.

**Usage follows the operator.**
- The fleet used quota 2.35 times faster during the 54-58 hours the operator was typing [M].
- On Oct 15 the fleet sat nearly idle for about 18 hours [M].

**The work queue was empty.**
- Rows an agent could run numbered 1-3 at every 12-hour check [M: activity.verify.md #10; demand.verify.md #3].
- 72% of 2,861 dispatcher passes found the backlog empty [M].
- 165 of 170 live rows are blocked, 94 of them waiting on the operator [M: `cc-backlog list --json`].
- The drain chain has been dead since Sep 22 [M].

**The idle middle is not a cross-week cause.**
- Days 1-4 reached 29 this week against 28 last week, and last week's middle was idler [M: crossweek.md §1].
- The backlog was just as thin the week before, and next still filled [M: demand.verify].
- So the empty queue explains why automation never fills anything, but not why this week was different.

### Cause 3: the finish was the same size as last week's, and was limited by working sessions, not a ceiling (timing and supply). Estimated 0-2 points as a cross-week cause; permission stalls at most 5-11 points.

**It matched last week.** The last 48 hours used 50 points against 52 last week [M: crossweek.md §1]. Last week next was at 62% with 24 hours left, this week at 42% [M]; that 20-point gap was already there 48 hours out.

**The 5-hour ceiling never bound.**
- next's 5-hour use peaked at 77% (:54683) and never reached 95% [M]. No hour was capped [M].
- The 18-23Z 5-hour window ended at 20%, and the 23Z-04Z window peaked at 77% [M: gap3/util_hourly.out].
- The final window left about 23% of its 5-hour room unused, roughly 6 weekly points [E: timeline.md §5 ratio]. The 18-23Z window left about 20-22 weekly points unused [E: gap-3, at 0.25-0.27 weekly points per 5-hour point].
- From 19Z on Oct 17, reaching 100% needed 4.9 points an hour [M/E: timeline.md:59]. That is about the 5-hour window's sustainable maximum of 5.0-5.5 [E: gap-3], so 100% was marginal from then on. Yet weekly use went only from 56 to 58 between 19Z and 23Z, at k 13-20 [M: activity.md hourly table].

**The machine was not the brake.**
- Burn per hour tracked active sessions, not load: correlation with active sessions 0.94, with k_native 0.88, with load_1m +0.41 [M: gap-3 §1; gap3/cap_hourly.out, util_hourly.out, active.out].
- The best hour, 03Z (+8 weekly points), ran at load 321 with the CPU 100% busy. The quietest hours, 21-22Z (load 22-28), were flat at 58 [M].
- Model latency p50 was 3-5 s in every hour, from load 22 to 413 [M: gap3/lat_agg.out]. Tool-call p90 stretched to 46-48 s at 19-20Z [M].

**What did limit it: few working sessions and permission stalls.**
- About 5-8 sessions were active against k_native 12-20 [E: gap-3].
- 4 next lane sessions sat blocked on a `git push origin HEAD:main` prompt between 19:23Z and 00:52Z, about 14.6 session-hours together [M: ~/.claude/autonomy/idl.jsonl kind=permission_pending => gap3/perm2.out]:
  - a2458487: 4.2 hours
  - 647665ed: 4.0 hours
  - 6956f777: 3.5 hours
  - a0e6a1fb: 2.9 hours
- Earlier that day, b18a0aed waited 7.3 hours on an `rm -rf` prompt [M].
- Upper bound for the stalls: 5-11 points [E: × 0.37-0.75 points per active session-hour]. It is only an upper bound because those lanes might have gone idle after pushing anyway.
- The 8-session active ceiling barely bound: 7 of the week's 47 capacity/active refusals fell in 16Z-04Z [M: gap3/hf.py].

**Room went unused earlier that day.**
- Oct 17's earlier 5-hour windows peaked at 11-20% while 9-15 sessions were open [M].
- next sat at 50% from 11Z to 15Z with 9 sessions open and 0% 5-hour use [M].
- That is roughly 45 points of unused 5-hour room [E: same ratio].

**The human loop was slow.**
- The operator asked at 07:25Z on Oct 17, and the agent diagnosed the problem at 07:39Z. It had a small fix it rated 85% likely to work, then waited 16.8 hours for a yes or no.
- It never said that logging back in, which takes the operator minutes, would lift the ×0.25 [M: transcript ef1947ad]. The route rows show the lift took effect some time after 23:47Z, not instantly.

**Resets were bunched together.**
- next2 (Oct 17 11Z), next (Oct 18 04Z) and next4 (Oct 18 09Z) reset within 22 hours of each other.
- Earliest-reset-first, which is correct for each account, kept next2 ahead all mid-week. next was the next account to reset only for its final 17 hours [M].

### Cause 4: the rescue tools failed when they were used (execution). Estimated 2-8 points.

About 6 points of this is from moves, the hours next2 sat full [E: gap-2]. The dispatcher's share is under 1-2 points.

**Session moves failed.**
- At 07:38Z on Oct 17, a move of 6 sessions off the full next2 onto next moved none: intents expired and the terminal was unreachable [M: ~/.reso/limit-recover/move/20261017T073813Z-next2-next-26358].
- 19 later batches onto next, from 23:57Z to 03:08Z, moved 1 of 17 sessions across 47 verdict rows [M: gap2/moves.py]. The main failure verdicts:

| Verdict | Rows | Cause |
|---|---|---|
| Claim held | 13 | Pane 344 re-queued the same sessions while earlier batches still held them. 43e6eb4b appears in 6 batches. |
| Admit-section refusal | 2 | Same re-queueing |
| Still busy | 11 | |
| Intent expired | 5 | The time limit is now + until + 900 s (bin/cc-lr:1484). Batch 012244Z ran 13,263 s against a 9,034 s limit (summary.json wall_s). |
| HELD: load | 5 | 28-37 load per core against an 8-per-core bound (handoffs.jsonl:986, :988) |
| STRANDED | 4 | |
| REFUSED: not limited | 1 | |

- About 67 session-hours sat on accounts that had hit their weekly limit [M].

**No automatic path moves a live session that isn't at a limit** [M].
- lr-fleet, the lr_recon reconciler and lr-reset-poller act only on LIMITED or launcher-rooted sessions.
- lr-handoff `--voluntary` refuses as "not limited" without an operator intent.
- recycle_repick acts only on self-recycles in the auto arm.
- cc-offload creates new cloud sessions and moves nothing.
- Evidence: scripts/limit-recover/lr_recon/census.py:247, :352; lr-fleet.sh:1-5; lr-handoff.sh:541-546, :641-655, :691; scripts/handoff-fire.sh:15090, :15505-15516; bin/cc-offload:339.
- From Oct 15 23:23Z to Oct 18 05:50Z, recycles were mostly in place: 1 recycle-repick against 40 recycle-engaged and 55 recycle-intent rows [M: handoffs.jsonl].

**Rebalances overshoot.**
- On Oct 11, batches onto next3 moved 11 sessions. next3 filled 10.3 hours early, and that set off the Oct 13 migration of 10 sessions from next3 to next2 [M: move/20261013T014855Z-next3-next2-79553].
- next2's live-session count jumped from 5 to 13 and stayed at 11-20 until Oct 17, while next sat at 3-9. next2 then hit its limit 6 hours early, at 05:04Z, and sat full until its 11:01Z reset on Oct 17 [M: gap2 hourly.py, util log].
- Routing to next2 (desk, lead, fires) sustained the skew more than the moved sessions did [M: gap2 track.py].

**Moving idle sessions moves little quota.**
- Burn per live session is 0.054-0.36 points per session-hour, against 0.58 per active session-hour [M: gap2/ppk.py].
- Rebalancing next2's sessions onto next would have put the full 21 points on next, but next2 would then have stranded most of it. That is a shift, not a gain [E: gap-2].
- The only fleet gain was next2's 6 walled hours at about 1 point an hour, so about 6 points [E].

**The dispatcher failed under load.**
- 47 background launches were refused because no agent-owned kitty window existed. 29 of them were the same item, retried every 12 minutes overnight on Oct 15-16.
- 91 passes failed to place work because the account check took longer than its 20-second limit.
- A hung child process stalled the dispatcher for the last 5.8 hours [M: dispatch-fires.log, idl.jsonl, ps].
- The backlog dispatcher launched 24 sessions all week, 1 of them on next [M]. For scale, 938 main transcripts were started in the week, 242 of them on next [M: disruptions.md §0, os.stat birthtime, realpath-deduped].
- The direct cost is small, but any future fill mechanism would launch through this same path.

**Sessions stalled on permission prompts all week.** next sessions spent 101 session-hours waiting on prompts [M], mostly the final `git push origin HEAD:main` of a task. The final-window share is counted under cause 3.

**The working-session count was mostly blind.**
- It was unmeasured on 60% of checks (881 of 1,466), because its directory walk runs past its 15-second budget across 17-20k project folders [M: claude-accounts.log:28250].
- next used 77 of its 79 points while it was unmeasured [M].

**The machine was overloaded for long stretches.**
- The capacity alarm read ALARM on this share of its rows each day [M: policy.verify.md C9]:

| Oct 11 | Oct 12 | Oct 13 | Oct 14 | Oct 15 | Oct 16 | Oct 17 | Oct 18 |
|---|---|---|---|---|---|---|---|
| 57% | 58% | 68% | 44% | 12% | 46% | 48% | 100% |

- On Oct 18, every hourly bucket from 00Z to 05Z was ALARM, at mean load_1m 204-586 on 10 cores [M: /tmp/wk-postmortem/crit_cap.py].
- Load was above 300 for 29.2 hours, 18% of the week. That came from CPU-heavy test and build work: b13 lane gates, and on Oct 18 the TrueMemory tm2 build team, including ad2417e7 on next [M: gap3/load300.py; docs/research/load-reinvestigate-2026-10-17/FINDINGS.md].
- The load cost burn little (cause 3), but it held 5 moves and coincides with the dispatcher's timeouts.

**Ruled out [M].**
- No reboot (the machine has been up since Sep 30), no sleep, and no network outage.
- No login outage: 3 keychain errors in 1,466 checks.
- No sessions killed by the reaper.
- The 5-hour limit never bound.
- The kitty terminal crash at 05:01Z on Oct 15 killed 18 sessions, 3 of them on next. Its direct cost was about 0: next burned 0.8M PU in the 7 hours before, and k_native was back to 3 by 08Z [M: activity.md hourly rows]. Its indirect cost was the repair fires routed to next4, counted under cause 1.

### Hours by what limited them (next, 168 hours)

| Period | Hours | next weekly use | What limited it | Why |
|---|---|---|---|---|
| Oct 11 04Z to Oct 13 02Z | 46 | 0 to 14% (+14) | Deadline order (correct), then demand | next3 reset first, from 1%, and needed a 99-point rescue. The fleet put 70-84 points a day there; the Oct 11 move batches onto next3 overshot, so it filled 10.3 hours early. ALARM on 57-58% of capacity-alarm rows. |
| Oct 13 02Z to Oct 15 04Z | 50 | 14 to 29% (+15) | Demand | next got the most handoff fires (9, then 17), but the fleet used only 45 and 42 points. 10 sessions migrated next3 → next2 (next2 k 5 → 13). The desk lane correctly favored next2. |
| Oct 15 04Z to Oct 17 19Z | 63 | 29 to 56% (+27) | Routing penalty (general lane and recycles), overlapping with operator absence | Oct 15: fleet used 18 points with the operator away; repair fires went to next4. Oct 16: 0 of 33 automatic fires went to next. Oct 17: moves onto next failed. |
| Oct 17 19Z to Oct 18 04Z | 9 | 56 to 79% (+23) | Working sessions: few active, 4 blocked on `git push` prompts. The 5-hour ceiling never bound (peak 77%). | 19-23Z: +2 at k 13-20. Re-login at 23:27:59Z. 23Z-04Z: +21. |

- Hours actually capped by the 5-hour limit or by hitting 100% weekly: 0 [M].
- Hours with zero use: 119 [M].
- The period boundaries and labels are my inference from the measured events.

---

## 3. Timeline

| Day (UTC) | next weekly use | Points used | Avg open sessions on next | Peak 5-hour use | Fleet points | What happened |
|---|---|---|---|---|---|---|
| Sun Oct 11 (from 04Z) | 0 to 14% | 14 | not measured | 41% | 70 | Carry-over from last week's finish. The fleet moves to next3 (at 1%, resets Oct 13); 11 sessions are moved there in 23 batches. ALARM on 57% of rows. next goes flat from 23Z. |
| Mon Oct 12 | 14 to 14% | 0 | 1.6 | 1% | 84 | next3 rescue: up to 34 sessions, +67 points. The forecast first flags next at 01:45Z and shows 21 or more points at 04:07Z. ALARM on 58% of rows. |
| Tue Oct 13 | 14 to 22% | 8 | 5.6 | 16% | 45 | next3 hits 100% at 01:40Z, 10.3 hours early. 10 sessions migrate next3 → next2 from 01:48Z (next2 k 5 → 13). next3 resets at 12Z, then sits at 0% with k=0 until Oct 16. At 07:04Z the operator overrides a "wait" decision; 6 fires go to next, which moves from 15% to 20%. The desk lane picks next2. 6 next sessions sit about 7 hours on git prompts. |
| Wed Oct 14 | 23 to 29% | 7 | 4.4 | 12% | 42 | next gets 17 handoff fires. It goes flat at 29% from 20Z. The reso.gl lead asks a design question at 20:43Z that is still unanswered. ALARM on 44% of rows. |
| Thu Oct 15 | 29 to 29% | 0 | 2.8 | 0% | 18 | The ×0.25 penalty starts at 04:12Z in the general lane and recycles; the desk lane still uses 1.0. The kitty crash at 05:01Z kills 18 sessions, 3 of them on next; its 47.9M PU of repair fires go to next4 at 05:37-05:46Z. cc-relogin-poll starts checking next at 05:02Z but SKIPs because k>0. The operator is mostly away: fleet burn is 132M PU, the lowest of 14 days. next uses 0 tokens from 06Z. 17 of 22 fires go to next3, mostly one item failing over and over. |
| Fri Oct 16 | 29 to 38% | 9 | 3.2 | 9% | 60 | Automatic fires: next2 23, next4 10, next 0. next ranks last in 25-26 of 32-33 rankings. The fleet-pace warning first appears at 05Z: "~55pp dies by next's reset". The first re-login ATTEMPT is at 07:07:24Z (k unmeasured); all fail. next2 uses 31 points. |
| Sat Oct 17 | 38 to 61% | 23 | 9.2 | 20% | 59 | next2 hits 100% at 05:04Z and sits full until 11:01Z. limit-recover sends 7 sessions to next4; the move of 6 sessions onto next fails. The operator asks at 07:25Z, and the agent waits for a yes. next is the desk's pick at 00:41, 04:31 and 07:23Z. next sits at 50% from 11Z to 15Z with 9 sessions open. The desk exemption lapses at 16:12Z. From 19Z, 100% needs 4.9 points an hour, about the 5-hour-sustainable maximum; next gains only 56 → 58 by 23Z while 4 lane sessions wait on `git push` prompts (19:23Z to 00:52Z). Desk launches at 22:54-23:47Z go to next4. The re-login at 23:27:59Z renews the token, but desk rows at 23:37:50Z and 23:47:18Z still apply 0.25 to next. |
| Sun Oct 18 (to 04Z) | 61 to 79% | 18 | 21.4 | 77% | 23 | Sprint at about 4.5 points an hour (61 → 79 in 4 hours); 03Z alone gains 8 at load 321. The 5-hour meter peaks at 77%, leaving about 23% of the window (about 6 weekly points) unused. 19 move batches onto next move 1 of 17 sessions. c33e5c0b2 (authored 00:33Z) is committed at 02:08Z and has no effect. The operator's `claude` lands on next4 at 02:57Z. ALARM in every hour, load_1m 204-586. Reset at 04:00:21Z, at 79%. |

- Numeric columns: [M: synth_day.py over account-utilization.jsonl, non-stale rows, counting only increases in weekly use].
- Fleet total for the week: 401 points [M].
- next fell furthest behind an even pace at 00Z on Oct 17: 45.3 points behind [M]. The last day's sprint recovered 24 of those points.

---

## 4. Ranked improvements

Item 0 is time-bound. After that, the order puts fixes that work with no one at the keyboard first. Items 1, 2 and 7 belong together: a fill mechanism needs work to run, and a way to launch it that actually works.

### 0. Act on the current windows today (operator)

The ordering principle is earliest expiry first: next3 (Oct 20 12Z), then the banked grants (Oct 22), then the windows that reset Oct 24-25 [E: inference from gap-1, gap-2 and gap-3].

| Action | Deadline | Evidence |
|---|---|---|
| Point load at next3. It needs 1.67 points an hour, about 3 continuously active sessions or 5-17 open ones, against 0.16 now. Use cold-only move batches from next now and from next4 after 09Z, stopping at next3's 5-hour floor; or pin new general work to next3. | Oct 20 12Z | `--rank general --json` => next3 weekly 10, reset in 54.0 h, wk_strand_pp 81.3 [M: gap-2]. next3's need is about a fifth of next's current ~8 points an hour, so it doesn't starve next [E]. |
| When next4 resets at 09Z, re-point the sessions the rotation put there at next3. Their only value on next4 is its last ~3 points. | Oct 18 09Z | next4 97% at 06:28:55Z [M]. Nothing automatic moves them afterwards [M: gap-2]. |
| Check the bank for next and next2 at clau.de/reset, in a browser logged into each account. Record resets_left, ends_at and clears. Do not use the CLI `/limit-reset`: on next2 and next3 it is the session reset that charges the weekly meter. Update the dl row admin.claim-the-banked-claude ("via /limit-reset" is now wrong) and the memory reference-banked-limit-resets-cedar-ember.md. | Before Oct 22 | gap-1 findings 5-6 |
| If next holds a grant, redeem it at next's weekly 100% wall, expected about Oct 18 22Z to Oct 19 if k≈25 holds. Do not redeem at the 5-hour wall it will hit at about 25% weekly. | Before Oct 22 | Up to 100 points (about $46) instead of about 25 [E: gap-1]. Yield depends on demand: about 0 at last week's 401 points a week [E]. |
| Decide next2: either route fill to it from Oct 18 09Z so it hits its wall by about Oct 21 12Z (about 31 points a day), or redeem at its first wall before Oct 22 00Z. Space the two redemptions at least a day apart. | Oct 21 | The Oct 1-2 redemptions split demand and stranded 26 points on next4 [M: g1_burn.py]. |

| | |
|---|---|
| Expected | next3: up to about 81 points (about $37) [E]. Bank: up to 200 points (about $92) if the grants exist [E, unverified]. |
| Size | S |
| Owner | Operator |

### 1. Build a strand-fill arm that starts work when an account is falling behind

**How it works**
- Add a new arm in scripts/autonomy-sweep.sh next to drain-revival-arm (around line 2057).
- Give it off, would-fire and on modes, plus a kill switch.
- It runs about every 31 minutes, which is the drain arm's measured cadence.
- It checks every account, not only the one resetting next, using `claude-accounts --json`.

**When it fires.** Gap-3 recommends a pace check over a 72-hour horizon, widened to 96 hours when two or more accounts reset within 24 hours of each other. next2 (Oct 24 11Z), next (Oct 25 04Z) and next4 (Oct 25 09Z) do.
- **Rule:** fire when 100 − weekly_pct > (hours_to_reset − 12) × r.
- **Choose r with care.** At gap-3's r = 2.5 points an hour, the rule would have fired on next only at about Oct 16 14Z: 38 hours out, 66 points left against a threshold of 65. That is barely earlier than the draft's 36-hour trigger. At r = 1.0, it fires about 83 hours out, around Oct 14 17Z [E: arithmetic on next's measured rows: 29% at Oct 16 04Z, 33% at 12Z, 35% at 16Z].
- **Keep the draft's two extra checks:**
  - The needed rate is more than 1.5 times the actual rate over the last 24 hours.
  - The full 5-hour windows needed, (100 − %) / 24.5, fit in the windows left, hours / 5.
- **Why horizon matters** [E: gap3/replay.py]:
  - A 36-hour trigger this week fell entirely after the quiet stretch, and inside ALARM for 25.8 of its 36 hours [M].
  - Under gates that respect the alarm, it would have had 52 fill slot-hours, against the 28-57 session-hours needed for 21 points.
  - A 72-96-hour trigger has 220-304.

**How it admits work**
- Reserve active slots, not load headroom. Admit only when active + in-flight + 1 ≤ 8 − 1, keeping the operator's reserve slot. Call cc_capacity_admit with caller `strand-fill` (scripts/lib/capacity-admit.sh, active term near :1446, reserve-active at :1502-1521).
- Do not fire while capacity-alarm reads ALARM, unless the reset is under 12 hours away and the pace check is failing.
- Keep the load term off, since load does not slow burn (r = +0.41) [M: gap-3].

**What it does when it fires**
- Launches fill sessions pinned to that account (`handoff-fire.sh --account <acct>`), drawing work from the pool in item 2.
- Stays within the per-account session cap (KMAX).
- Stops once the account is projected to reach 100%.
- Logs every decision to idl.jsonl.

**Why trigger on pace instead of the long-range forecast**
- The 96-hour forecast is right only 11-25% of the time at 48-96 hours out, and runs about 19 points high. At 12-24 hours it is right 43-50% of the time [M].
- A false alarm costs little: the account reaches 100% a few hours early and limit-recover moves its sessions.
- A miss costs a week like this one.

**On this week's data.** The draft's 36-hour trigger would have fired at about Oct 16 16Z, and by 04Z on Oct 17 at the latest [E: arithmetic on the measured rows]. At Oct 16 16Z, next was at 35% and needed 1.8 points an hour against 0.25 over the prior 24 hours. At Oct 17 04Z it was at 42% and needed 2.4 points an hour against 0.54, with 2.4 full 5-hour windows needed and 4.8 left.

| | |
|---|---|
| Expected | Most or all of next's 21 points, plus next3's forecast ~81 now [E] |
| Size | M |
| Owner | The agent builds it and replays it in would-fire mode over 6 weeks of data. The operator turns it on once: the auto-mode classifier refused to let an agent switch on its own spending on Sep 16 (backlog c109e9e850fb). |
| Half-built? | Yes. drain-revival-arm already has the off/would-fire/on modes. The inputs already exist in bin/claude-accounts: wk_strand_pp (:5068), pace_need_ppd (:4640), burst_start_by (:4752) and fleet_pace (:5403). |

### 2. Keep a pool of work the fill arm can draw on without the operator

**How it works**
- Add a `fill` class in bin/cc-backlog that only the fill arm draws from.
- **Seed it with:**
  - Plan phases that scripts/plan-phase-scan.sh confirms are still open, added one per phase through bin/cc-discover. Gate this step: a flood of 387 rows had to be retracted before.
  - Premise checks on the 165 blocked rows.
  - research-kit refreshes.
  - Test hardening.
- **Pre-stage long autonomous jobs.** For example, research or audit workflows from the 157 open plans, launched on the account with the nearest reset when operator presence drops and the forecast shortfall passes the floor. Last week's fill came from such a job: 58d3640a ran about 24 hours unattended [M: gap-4]. This must first fix the headless anchor refusal (the "NONE agent-owned" window).
- **Keep fill work CPU-light:** research, reading, review, planning. Exclude `pytest -n auto`, hostmatrix, corpus runs and build gates. Model latency stayed at p50 3-5 s at load 413, so CPU-light fill burns at full rate even under ALARM. CPU-heavy work is what drove load above 300 [M: gap-3].
- Fix cc-discover's `added` count, which is a `wc -l` difference at :154-155.

| | |
|---|---|
| Expected | No points on its own: it is the fuel for item 1. Without it, item 1 fires into an empty queue, just as the drain arm would today (drain-pick finds 2 eligible rows [M]). With it, it recovers the ~137M PU a day (about 14 points-equivalent) lost on days like Oct 15 [E: gap-4]. This is the only lever that cuts fleet strand rather than moving it. |
| Size | L |
| Owner | Agent. The operator approves the list of work types once. |
| Half-built? | Yes. The drain pipeline, cc-discover and plan-phase-scan all exist. |

### 3. Stop the login-cliff penalty from applying to an account that is falling behind, in every lane

**How it works**
- In bin/claude-accounts `_strand_cliff_factor` / `_dispatch_cliff_factor` (:3402-3466), return 1.0 (no penalty) when both of these hold, regardless of DESK_LIFE_H:
  - the forecast shortfall is at least DESK_CLIFF_STRAND_PP;
  - the weekly reset comes before login expiry minus 48 hours (CLIFF_DRAIN_H).
- An alternative is to replace ×0.25 with an exclusion that applies only inside CLIFF_DRAIN_H.
- Apply the same rule to:
  - recycle_repick (scripts/handoff-fire.sh:15208);
  - the recovery lane's target choice;
  - the `_dispatch_first` cliff block (:6466).
- Merge DESK_5H_FLOOR = 1.00 from branch cc-022337-11276 (367539c52). It is not on trunk yet.
- Add regression tests:
  - a replay of the Oct 15-17 rankings (the gap4/divert2.py pool) asserting next wins;
  - route.jsonl at 22:54Z on Oct 17;
  - handoffs.jsonl at 04:11:41Z on Oct 16.

| | |
|---|---|
| Expected | 5-21 points on next in a week like this (bottom-up 5-10; cross-week about 15-21) [E]. About 0-5 for the fleet unless paired with items 1-2. |
| Size | S |
| Owner | Agent |
| Half-built? | Yes. c33e5c0b2 (general and Fable lanes), 27987efa8 (desk lane) and 367539c52 (desk 5-hour floor, on a branch). The gaps are the DESK_LIFE_H lapse, recycle_repick, the recovery target, and merging 367539c52. |

### 4. Let cc-relogin renew the login while sessions are running

**How it works**
- In bin/cc-relogin and cc-relogin-poll, drop the k==0 gate, or keep it only as a preference with a deadline. The poller was checking next from Oct 15 05:02Z but logged SKIP because k>0 [M: cc-relogin-poll.log:2023]. Its first ATTEMPT came about 27 hours later [M: :2046]. The gate was the blocker, not when the poller started.
- When `ps` fails, fall back to the native session count that claude-accounts already has.
- After a renewal, refresh the router's cached login expiry at once. The penalty persisted at least 20 minutes after the renewal [M: route.jsonl:5162, :5164].

**Evidence:** the successful renewal at 23:27:59Z happened with 15 sessions live [M: auth-timeseries.jsonl:62633].

| | |
|---|---|
| Expected | Removes the ~67-hour penalty window at its source. The points are counted under item 3. |
| Size | S-M |
| Owner | Agent. First confirm on a quiet account that renewing doesn't disturb live sessions. |
| Half-built? | Yes |

### 5. Make limit-recover session moves land, and rebalance when a reset strands another account

**How it works**
- **Fix move intents that expire.** Refresh expires_epoch at admission, or add the admission and slot wait to the time limit (bin/cc-lr:1484; lr-move-batch.sh admission path). This removes 5 of the 47 Oct 17-18 verdicts, plus 2 of 6 in the 07:38Z batch [M: gap-2].
- **Refuse or merge duplicate batches.** If a session is already claimed by a live batch from the same requester, print the existing batch id instead of queueing a competing one (bin/cc-lr move plan stage, checking move/*/intent/<sid>.json). This removes 15 of 47 verdicts [M: gap-2].
- **Fix the remaining failure modes:**
  - moves held because the terminal can't be reached when `kitten @ ls` is slow;
  - 90-second contention over the admission step;
  - moves refused because the session is still busy.
- **Rebalance after a reset.** This needs an operator ruling, because the automation would be writing operator intents (lr-intent.sh). In scripts/limit-recover/lr-reset-poller.sh, when an account resets and another has wk_strand_pp ≥ 20 with an earlier reset:
  - file one cold-only batch (`cc-lr move --from A --to B --cold-only --until-idle 1800`);
  - allow at most one live batch per (from, to) pair;
  - stop at the target's 5-hour or weekly floor, so it doesn't overshoot the way Oct 11 → 13 did.
- **Add a strand basis to recycle_repick** (scripts/handoff-fire.sh:15090, :15505-15516). When the top account has wk_strand_pp ≥ 20 and an earlier reset, re-pick even for explicit self-successor fires, and log basis=strand. REPICK_RATIO stays at 4.0.
- Choose move targets by forecast shortfall, with item 3's exemption applied.

**Evidence:** 1 of 17 sessions moved onto next in 19 batches (47 verdicts) on Oct 17-18, and 0 of 6 at 07:38Z [M: gap2/moves.py].

| | |
|---|---|
| Expected | About 6 points this week, from next2's walled hours [E]. Going forward, the reset hook would have pointed next's 27 sessions (8.5 points an hour) at next3 at 04Z today. next3 can absorb up to about 5.5 points an hour; that recovers 14 points so far and up to ~81 by Oct 20 12Z if load persists [E: gap-2]. |
| Size | M |
| Owner | Agent; operator for the rebalance ruling |
| Half-built? | Yes |

### 6. Clear end-of-task permission stalls

**How it works**
- In the lane runner's land path, or in the lead-supervisor path that watches pending permission prompts, send `git push origin HEAD:main` from b13 lane worktrees through the ship-land path, or add allow rules for it.
- Page the operator when a permission_pending row in ~/.claude/autonomy/idl.jsonl is older than 15 minutes on an account inside its fill window.
- If a session has been blocked for 30 minutes while the operator is away, re-launch the remaining work.

| | |
|---|---|
| Expected | Up to 5-11 points this week (upper bound) [E: gap-3]. Covers 14.6 session-hours blocked 19:23Z-00:52Z, plus b18a0aed's 7.3 hours. next sessions spent 101 session-hours stalled all week [M]. |
| Size | M |
| Owner | Operator (permission rules), agent (paging) |

### 7. Make background launches reliable when the machine is busy

**How it works**
- In scripts/handoff-fire.sh, give background launches an approved agent-owned window that launchd keeps alive. This is item F9 in docs/plans/SESSION_LIFECYCLE_V2.md:379. Keep the guard that stops agents taking over the operator's panes.
- Stop retrying an item after N refusals that fail the same way.
- In bin/cc-wave-plan, use the cached `--rank general` result when the 20-second limit runs out.
- In bin/cc-dispatch, put a time limit on child processes and treat a stale lock holder as dead.

| | |
|---|---|
| Expected | Under 1-2 points this week [E]. It is still required for item 1, which launches through the same path. |
| Size | M |
| Owner | Agent |
| Half-built? | Yes. F9 is already logged. |

### 8. Make the bank visible and advise on redemption

**How it works**
- Add a throttle-aware `--bank` read in bin/claude-accounts, using `?cedar_ember=1&skip_spend=1` and obeying the per-account 429 backoff in claude-accounts-pollstate.json. Surface resets_left, ends_at, clears and use_requires_limit in `--readout` and `--json`.
- Add an advisor in keepwarm that sends cc-notify mail when an account with an unused grant reaches weekly ≥ 99% with ≥ 20 hours to its natural reset, before ends_at. It should also warn when the only reachable wall gives a partial yield close to expiry.
- Fix the runbook: the memory reference-banked-limit-resets-cedar-ember.md, commands/limit-recover.md section "A banked reset was redeemed", and the dl row. Redemption is web-only (clau.de/reset) in CC 2.1.302.

| | |
|---|---|
| Expected | Catches walls like next2's on Sep 30 (75.8 hours left) and next's on Oct 1 (55.7 hours left), which were missed with no visibility into the bank [M: g1_wall.py]. Prevents spending the weekly-charging session reset by mistake. |
| Size | M |
| Owner | Agent; the operator authorises the read |

### 9. Fix the working-session count (k_work)

**How it works:** in bin/claude-accounts `working_concurrency`, limit the directory walk to project folders modified recently, or keep an index. Log a per-minute active census, not just one at admission time. The transcript-derived series correlates with the census at only r = 0.54 [M: gap-3].

| | |
|---|---|
| Expected | 0 points directly. It lets item 1 and the router tell idle open sessions from busy ones. On Oct 15 the count correctly read 0 for next's 3 idle sessions in the checks where it was measured. |
| Size | S |
| Owner | Agent |
| Half-built? | Yes. k_work and its CC_ROUTE_KWORK switch already exist. |

### 10. Raise the effort level on accounts the fill arm flags

**How it works**
- Wire the SLACK RULE into how handoff-fire and cc-route pick an effort level. Today it is only text, at ~/.claude/model-config.yaml:1470-1476.
- On a flagged account, judgment and research work runs at xhigh.
- Scoped coding work is never raised.

| | |
|---|---|
| Expected | Small and unmeasured. It increases use from sessions that are already open. |
| Size | M |
| Owner | Agent |
| Half-built? | The rule's text exists. |

### 11. Meter headless usage

**How it works**
- Wrap headless `claude -p --no-session-persistence` calls (research-kit, A/B harnesses) to write {account, tokens} to a jsonl file.
- Base desk-strand-replay.py and claude-accounts forecasts on the utilization meter, not on transcript PU alone.

| | |
|---|---|
| Expected | Removes the 6.74 vs 9.63M PU-per-point ambiguity. An estimated 10-29 points were untracked last week [E: gap-4]. |
| Size | M |
| Owner | Agent |

### 12. Operator decisions that unblock the items above

The decisions:
- **(a)** Rule on decision 58d62776eb1f / backlog c109e9e850fb, the drain-arm default (open since Sep 30). Turn item 1 on after its replay.
- **(b)** Make decisions where waiting costs expiring quota "class B", meaning they carry a default and a deadline (cc-decide). 62 class-C decisions are open with no default [M].
- **(c)** Decide whether the login-cliff penalty should ever take priority over an account that is falling behind.
- **(d)** Decide whether automation may write operator intents for strand rebalances (item 5).
- **(e)** Check and redeem the bank (item 0).

| | |
|---|---|
| Expected | These unblock other items. Turning the drain arm on by itself is worth about 0 points, since only 2 rows qualify [M]. |
| Size | S |
| Owner | Operator |

### 13. Displays and records (lowest priority: warnings already existed and nobody acted on them)

What to change:
- Have the session-start board show the account with the biggest forecast shortfall within 72 hours, not just the next reset (`soonest_reset_line`, :5310).
- Make the readout's "no strand — on pace to fill" line resistant to a sprint.
- Add a carry-over alarm. Fire when an account less than 6 hours past its reset has burned 5 or more points while another account has wk_strand_pp ≥ 20 and an earlier reset (wk_strand_pp/readout drain block around :5068). It would have flagged today's next → next3 mismatch at about 04:30Z [E: gap-2].
- **Log every weekly reset with the percentage it reset from.** quota-reset-detect only arms a window that reads RESET_HIGH_PCT = 99.0 or more (bin/claude-accounts:2583, :2666), so by design it never records a reset after a strand. That is why next's 79 → 0 reset has no row [M].
- Log the forecast's state to a jsonl file.
- Archive handoffs.jsonl and account-assignments.jsonl instead of trimming them (ASSIGN_PRUNE_LINES).
- Break the capacity-attrib "ghost" bucket down by command (scripts/lib/capacity-attrib.py around :553). It took 20-29% of the box in some sprint hours [M: gap3/attrib_hourly.out].
- Add an agent rule: when diagnosing a shortfall, name the operator's fastest fix. This week that was logging back in.

| | |
|---|---|
| Expected | 0 points directly. The paging channel already carries 314-442 new pages per sweep [M]. |
| Size | S |
| Owner | Agent |

---

## 5. What we could not determine

- **How the 21 points split between causes.**
  - The bottom-up and cross-week methods disagree on the cliff: 5-10 against 14.5-20.
  - The cross-week cell "operator present + cliff" ranges from 81 to 92, because Oct 16's +13 included catch-up and explicit `--account next` fires [E: crossweek.md §7].
  - After the 23:28Z re-login, next used 21 points in about 4.5 hours. But the permission stalls cleared at 23:33Z and the sprint was already under way, so the gain can't be credited to one cause.
- **The fleet-wide change in PU per point between weeks.** next went from 6.74 to 9.63M PU per point; next2 rose 9% and next4 28%. It could be a meter change or untracked headless use. Transcripts can't settle it [gap-4].
- **The API-price value of a point.** Fits with and without cache reads explain the data equally well: $22-26 per point with cache reads, $12.4 without. The subscription value is known: about $46-50 per account-week.
- **Whether next and next2 actually hold an unused grant, and their exact ends_at** (Oct 22 00:00 UTC, or end of day Pacific). Also unknown [gap-1]:
  - whether a 5-hour wall counts as "at a limit";
  - why tengu_cedar_ember disappeared;
  - why next's config has a null cachedGrowthBookFeaturesAt.
- **Whether the 4 blocked b13-r14 lanes would have kept burning after their push.** This decides whether the 5-11-point upper bound is real [gap-3].
- **What makes up the "ghost" CPU bucket** in the 16-17Z and 23Z-01Z sprint hours [gap-3].
- **How next's k climbed from 12 to 33 between 22Z and 03Z** when only 7 handoff-fire assignments went to next [gap-2].
- **How many fires the 272M diverted PU really reflects.** The current-week lineage leaves 42-85M PU a day unmatched, so 272M is a lower bound [gap-4].
- **Whether anyone saw the mid-week forecast and chose to wait.** There are no read receipts. Agents repeated "next strand ~N pp" 14 times from Oct 12 on [M].
- **Routing on Oct 11-14.** handoffs.jsonl starts at 23:15Z on Oct 15. account-assignments.jsonl starts on Oct 13 because it is trimmed to 200 lines. For Oct 13-14 we can't tell automatic fires from manual ones.
- **True working-session hours.** k_work was empty on 60% of checks.
- **Whether the 45 open or in-progress infrastructure plans still contain work.**
- **Where the 112 sessions that died within a minute came from** (Oct 16, 08-11Z, killed by hangup). They were not launched by the dispatcher, and their effect on quota is negligible.
- **Why the operator took 16.8 hours** between the diagnosis and the go-ahead.
- **Whether next4 fills by 09Z today** (97% at 06:28:55Z) **and next3 by Oct 20**, and where next4's sessions go after 09Z. If next4 fills, routing work away from next was a shift between accounts rather than a fleet loss.
- **Why next3 sat at 0% with k=0 from Oct 13 12Z to Oct 16 12Z.**

---

## 6. Appendix: refuted claims (dropped) and corrections

### Refuted claims (dropped)

1. **Timeline:** "0.097 points per pane-hour against 0.491 per working-session-hour; points per 100 pane-hours fell steadily, 35.2 to 9.7."
   - Refuted because k_work was unmeasured on 60% of checks, and the measured checks were mostly idle ones.
   - next used 77 of its 79 points while k_work was unmeasured.
   - Recomputed, the decline is real but not steady: 29.2, 20.9, 21.5, 12.2, 8.9.
2. **Timeline:** "6.1 constant panes, or 1.21 working sessions, would have filled the week; 21 points ≈ 43 working-session-hours."
   - Refuted because quota use doesn't grow in step with open panes. next's pane-hours rose from 343 to 898 over five windows while use per pane fell.
3. **Demand:** "15-21 of the 21 points come from a shortage of backlog work."
   - Refuted because the backlog was just as thin the week before, and next filled.
   - A routing defect explains a measurable share.
4. **Tokens:** "The fleet used 401 of 400 points, so this was a placement and timing loss, not a lack of work."
   - Refuted because about 620 points were available across the span: three accounts crossed a reset.
   - Mid-week use ran at about 60% of a steady pace, and about 30% on Oct 15.
5. **Policy:** "Filling four accounts needs about 20 constant sessions, but the operator can oversee only 4-5."
   - Refuted because the fleet already averaged 25.6 open sessions and used 402 points.
   - The shortfall was work inside sessions, allocation and timing, not the number of sessions.

### Corrections applied from weakened claims

- next was furthest behind pace at 00Z on Oct 17, by 45.3 points (not 43.7).
- Zero-use hours were 119 (not 98).
- From 19Z on Oct 17, reaching 100% needed 4.9 points an hour, about the 5-hour-sustainable maximum. The earlier "infeasible from 23Z on Oct 16" was based only on past demand.
- On Oct 16 next ranked last in 25-26 rankings, not all of them.
- 38 rankings would have flipped (not 39), and 17 of them came from next2.
- The forecast dipped to 26.9% once and to about 22% at the end.
- The fleet-pace warning named next in 5 of the 27 hours it fired.
- Active time was about 17% of open session-hours (not 19%).
- Stop-hook continuations drove about 21% of next's use (not 43%).
- The desk-invariant job is disabled on purpose, so loading it would do nothing.
- Parked session-hours were about 67 (not 82).
- The machine-load alarm's share of rows was 57/58/68/44/12/46/48/100% on Oct 11-18. Only Oct 15 was quiet (policy.verify.md C9). The earlier "Oct 11-13 ran at the alarm" understated it.
- The dispatcher sent 17 fires to next3 (not 15).
- 120 of the week's 162 new backlog rows were completed, mostly outside the dispatcher.
- The rule "idle accounts are capacity" is already loaded into every session. The problem is that it is buried in a filing sub-clause.

### Corrections made in this revision (critic and gap findings)

- **The ×0.25 applied to the general lane and recycles from Oct 15 04:12Z, not to "every lane".** The desk lane used 1.0 for next until it lapsed at 16:12Z on Oct 17; desk rows show 0.25 from 22:54Z (route.jsonl:5073-5158).
- **The re-login did not end the penalty instantly.** Desk rows at 23:37:50Z and 23:47:18Z still applied 0.25 (route.jsonl:5162, :5164).
- **The 5-hour ceiling never bound.** The "ran at its ceiling" wording and the hours-table label are replaced. The peak was 77%, and 19-23Z went 56 → 58 at k 13-20.
- **The money headline now gives both numbers:** about $10 in subscription cash (bash-commands.log:134598) and $260-550 in value at API list price.
- **Fable is a slice of the weekly limit, not separate money** (crit_fable.py). At most 0.73 weekly points per Fable point.
- **quota-reset-detect logs only resets from ≥ 99%, by design** (bin/claude-accounts:2583, :2666).
- **next2's 0% is real idleness:** about 3.8M PU, about 0.5 points.
- **"Slipping for three windows" is now two windows** (100 → 62 → 42).
- **"24 sessions launched" covers only the backlog dispatcher.** 938 transcripts were started in the week, 242 of them on next (disruptions.md §0).
- **Oct 12-16 open sessions were 1.6-5.6, not 3-6.**
- **cc-relogin-poll was blocked by its k==0 gate, not a late start** (cc-relogin-poll.log:2023, :2046).
- **DESK_5H_FLOOR = 1.00 is committed on branch cc-022337-11276 (367539c52, 06:02Z Oct 18), not yet on trunk.** At the critic's check it was uncommitted.
- **"The operator's own sprint filled earlier weeks" is now labelled an inference** (mechanisms.verify.md #1), and gap-4's measured account of last week replaces it.
- **Rows an agent could run numbered 1-3, not 1-4.**
- **Cause ranking revised per gap-4.** The cliff dominates for account 1 and operator absence for the fleet. The idle middle and the late sprint explain about 0-2 points across weeks.
- **Gap-1** added the banked-reset section and item 8. **Gap-2** added the move-failure breakdown, the overshoot, and the item 5 additions. **Gap-3** added the supply-bound finish, the trigger and admission design, and the permission-stall estimate. **Gap-4** added the day-5 divergence and item 11.

---

Deviations:
- **The report file was not written.** The worker rules forbid writing report .md files, and the Write tool refused this path on the previous pass, so /tmp/wk-postmortem/REPORT.md does not exist. This message is the full report.
- **The DESK_5H_FLOOR status moved on since the critic checked it.** Read-only `git log` now shows the change committed on branch cc-022337-11276 as 367539c52 at 06:02Z, still not on main.
- **New checks, all read-only:**
  - route.jsonl desk rows, Oct 15-18 (inline python);
  - cc-relogin-poll.log lines 2023 and 2046, and `grep -c` (181 "SKIP next" rows);
  - c33e5c0b2's author and commit times (`git show -s`);
  - account-utilization.jsonl:54771-54774 at 06:28:55Z;
  - next's weekly % at the trigger-check instants, for the item 1 arithmetic;
  - a re-run of /tmp/wk-postmortem/crit_fable.py ("fable-up polls 117 with 5h AND weekly flat 0").

---

## 7. Addendum: the rotation onto next4, 2026-10-18 04:25-05:30Z (measured by the lead)

The operator asked for every session to move onto next4 (97% weekly, resetting 09Z). That repeated cause 4 live.

**What happened, by time and batch:**
- **04:25Z.** `cc-lr move --from next --to next4 --until-idle 3600` queued batch `20261018T042503Z-next-next4-55824`: 6 sessions to move at once, 12 to move once idle, 10 held (teammates and leads with live teammates). next3 held all 5 of its sessions; next2 had none.
- **04:35Z.** The batch was admitted, 10 minutes after it was queued.
- **The idle moves parked.** Each read `HELD:pane:resolver-unavailable`. The kitty control socket answered from an agent session in 0.15 s. From the poller, both `kitty @ ls` (a 610 KB reply) and the 3 s python connect probe timed out at load ~570 on 10 cores, with swap at 8.3 of 9.2 GB. The message wrongly says "no socket … would even accept a connection", when the socket was there but slow (scripts/handoff-fire.sh:2588, :2665).
- **Two sessions gave up waiting for a slot**, each with `slot-wait: no move slot freed in 600s`.
- **The poller wedged.** The tick that began at 04:25Z was still running at 05:29Z, 66 minutes later, so batch `20261018T051256Z-next-next4-50309` was never claimed. Result: 0 of 18 sessions moved in 64 minutes.
- **Pane 389 (session 0c354704) exited cleanly mid-turn at 04:49Z**, 2 minutes after the operator submitted a prompt there. Its move verdict says nothing touched it. The crash watchdog classed the exit as RECYCLE, so nothing owed it a resume. Recovering it took three refusals from the capacity-admit gate (8 mid-turn sessions against an active ceiling of 8, the ceiling item 1 has to fit under), each with a fresh pane. It was admitted on the fourth attempt, once the gate's 3-refusal budget was spent, and is now live on next4.

**What it adds to section 4:**
- **Item 7 needs a load-aware resolver.** When the socket accepts the connection but the reply is slow, that is a TIMEOUT and must not be reported as "unavailable". Use a cheaper probe than a full `ls`, for example `kitty @ ls --match id:<P>`.
- **The poller tick needs its own time limit.** One wedged tick blocks every queued move.
- **A clean exit while the operator's prompt is still unanswered should create a resume debt,** not be classed as a recycle.
- **The rotation aimed at the wrong account.** next4 had at most ~7 points that would expire unused. next3 (about 81 points, resetting Oct 20 12Z) and next2 (about 78 points) are where unused quota is about to expire; see item 0.
