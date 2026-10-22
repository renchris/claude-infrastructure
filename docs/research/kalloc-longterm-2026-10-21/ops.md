# kalloc long-term, ops axis: make the residual leak a non-event (2026-10-21/22)

Scope: the operations side only. That covers a leak-rate SLO and forecast, automatic reboot prep at the
forecast, choosing the reboot window, the limits of `fdesetup authrestart`, how today's restore fixes
change what a reboot costs, and reboots per month at 0.92, 0.3 and 0.1 GiB/day. Nothing here was
built. I made no repo, settings or launchd edits.

Labels: **MEASURED** means a command or file was read, and the source is named. **INFERRED** means
derived or estimated, and the method is named. Times are CDT unless they carry a Z.

## 0. Answer

1. **Rebooting on the forecast already works at today's rate. What is missing is a scheduler, not a
   detector.** The alarm measures the level, a trailing least-squares slope and an ETA
   (`scripts/capacity-alarm.sh:1486-1524`). It posts a banner at tier 1, which is 50% of the
   ceiling (`:2326-2330`). Nothing chooses a reboot time, nothing runs prep before a human asks, and
   there is no phone leg: `~/.config/lr-page/pushover.env` is absent (MEASURED, `test -f`). The 10-18
   panic happened because a detected alarm was never acted on (research doc lines 42-58).
2. **An unattended reboot is not possible on this Mac today, and authrestart does not change that.**
   FileVault is On (MEASURED, `fdesetup status`). `authrestart` needs root and a typed password
   (man fdesetup). On Apple silicon its token works for one restart only
   ([Eclectic Light](https://eclecticlight.co/2023/02/20/macos-13-2-1-authenticated-restart-and-fdesetup/)),
   and a vendor FAQ says "the user's password is still required at Login Window"
   ([Twocanoes](https://twocanoes.com/knowledge-base/password-utility-faq/)). This Mac has not tested
   that. Boot-resume is a user LaunchAgent (`RunAtLoad`, MEASURED with `plutil -p`), so nothing
   restores until someone logs in. So the reboot window has to be chosen around when the operator is
   present, not just the lowest-load hour.
3. **Recommended window: the operator's wind-down, about 01:30-03:00. Fallback: the morning return,
   about 09:30-11:30.** At wind-down the operator types one password, and the restore surge (load
   614 at login on 10-21) lands in the load trough (02-09 h, median load 17-37). See §3.
4. **Today's fixes cut the restore from 86 min to an estimated 10-15 min. The leak still decides how
   many reboots there are.** Reboots per month to a 14 GiB line (INFERRED, §5): **2.0 at 0.92
   GiB/day, 0.65 at 0.3 and 0.22 at 0.1**. At 0.1 GiB/day, ordinary OS-update reboots come first, so
   leak-driven reboots are about 0.01 a month. **0.3 GiB/day is the point where the leak stops
   setting the reboot cadence.** Treat it as the SLO target for the prevention axis.

## 1. Current state (MEASURED unless marked)

| Fact | Value | Source |
|---|---|---|
| Boot | 2026-10-21 14:06:30 (epoch 1792609590) | `sysctl kern.boottime` |
| Zone now | 379,780 elements (0.36 GiB) at 1792645118; cred 3,704 | `zprint data.kalloc.1024` / `cred` |
| State file | 0.35 GiB, 2%, tier 0, slope 0.91 GiB/day ("trailing 0.4 d"), ETA 2026-11-12 | `~/.claude/autonomy/kalloc-zone.state` |
| Slope check | 0.914 GiB/day over 20 measured rows (0.37 d); last 6 h 0.825 | LS fit of `kalloc-zone-series.tsv` rows ≥ boot |
| Elements per day | 0.92 GiB/day = 11.2 elements/s = 965k/day | arithmetic. The brief's "~11k elements/s" should read ~11/s |
| Boot-start bias | the 10-21 leak test left ~47 MiB (~48k elements) early in this boot | research doc :337-338. So the 0.37-day slope reads high, and the last 6 h (0.825) is closer |
| Ceiling | 20,955,520 elements = 19.98 GiB | `capacity-alarm.sh:386` |
| Page floor / banner | page at ≥ 4 GB (`KALLOC_WARN_GB`, :368, :2304); banner at tier ≥ 1 = 50% (:2326-2330) and daily after that | code |
| Phone leg | absent: no Pushover file | `test -f ~/.config/lr-page/pushover.env` → absent |
| Load now | 97 / 116 / 114 on 10 cores | `sysctl vm.loadavg` |
| Exec census | still running at 23:59. `exec.jsonl` was 2.95 GB after 8 min, no `summary.txt` yet. Not used here | `ls -la ~/.cache/kalloc-exec-census/20261021T235112/` |

## 2. Leak-rate SLO and forecast

### SLIs (all are in files the alarm already writes)
- **L (level)**: elements / ceiling, read every 900 s, carried at any age within a boot
  (`capacity-alarm.sh:222-231`).
- **R (rate)**: least-squares slope of the measured rows. Today the window is the trailing 3 days
  (:1487-1506).
- **R/call**: growth per Bash tool call, which `scripts/kalloc-leak-rate.sh` already computes (header
  :1-12; baseline 52.1 elements/call before 0070, research doc :304-308). This separates "the fleet
  was busier" from "a new by-path `#!` exec appeared".

### SLOs (proposed)
| SLO | Target | Error budget / response |
|---|---|---|
| S1 safety | no zone-map panic; every reading < 70% of the ceiling (14 GiB) | 0 per quarter. A reading ≥ 70% is an incident review; tier 3 (85%) means reboot today |
| S2 leak rate | 7-day median of per-boot R ≤ **0.30 GiB/day** (target for the shim wave); stretch ≤ 0.10 | a 24 h R > 1.5× the target, or R/call > 1.5× the previous boot's, files a regression row (new by-path `#!`) |
| S3 reboot cost | from the restart command to the restore page ≤ 20 min; ≤ 1 operator action (the FileVault password); every WAKE verdict prompted ≤ 15 min after login | measured on each reboot from the event dir (`events/boot-<epoch>/`) |
| S4 forecast stability | the reboot-by date never moves > 2 days earlier within 24 h | a jump pages (it means a rate regression) |

Why 0.30 (INFERRED, §5): at 0.30 the 14 GiB line comes every 46.7 days, which is longer than the
natural reboot interval. Leak reboots fall to about 0.3 a month, and most of them coincide with an
OS update.

### Forecast change (design)
The current ETA is level → ceiling at the 3-day LS slope (:1512-1514). That gives one date with no
error bar, and it targets the ceiling, not the reboot line. Proposed additions to `kalloc-zone.state`
(new keys, so existing readers are unaffected):
- `slope_hi_gib_day` = max(24 h LS slope, 3-day LS slope) × 1.5. INFERRED margin: the post-0070
  hourly bins ran up to 14.3/s against a 10.8/s mean, about 1.3× (research doc :359-366). Before 0070
  the peak boot ran 3.6-4.4 GiB/day against a 1.06 mean (:59-62).
- `reboot_line_gib` = min(14, ceiling − 6 × slope_hi). That leaves at least 3 days of headroom at
  the high slope, plus 3 days of scheduling slack.
- `reboot_by` = the date the level crosses the reboot line at `slope_hi`.
- `window_next` = the last operator window (§3) on or before `reboot_by`.
- `coalesce` = whether a macOS update or `kitty-restart-pending` is outstanding, so the leak reboot
  takes it along (prep already reads the kitty marker, `alarm-reboot-prep.sh:349-352`).

At 0.92 GiB/day: slope_hi ≈ 1.4, line = 14 GiB, reboot_by ≈ boot + 10 d (at the high slope) and
≈ 15 d (at the mean). Each day the planner re-forecasts and takes whichever comes first.

## 3. Choosing the window

### Load by local hour (MEASURED)
Command: `capacity-alarm.jsonl` plus its 2026-10-09 rotation, `jq` → `[ts, load_1m]`, binned by
America/Chicago hour, 33 days (2026-09-19 → 10-21, 30,144 rows). The second set covers 10-08 → 10-21
only, because load rose sharply from 10-18 (daily medians 117, 195, 83, 81 for 10-18..10-21).

| Hour | 00 | 01 | 02 | 03 | 04 | 05 | 06 | 07 | 08 | 09 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| median, 10-08..10-21 | 93 | 41 | 37 | 29 | 22 | 20 | 20 | 18 | 18 | 17 | 24 | 43 | 36 | 48 | 56 | 44 | 26 | 28 | 30 | 37 | 41 | 31 | 49 | 65 |
| p90, 10-08..10-21 | 463 | 442 | 179 | 141 | 147 | 143 | 74 | 90 | 113 | 104 | 156 | 206 | 214 | 279 | 256 | 230 | 155 | 194 | 251 | 224 | 332 | 267 | 319 | 408 |
| median, 33 d | 35 | 29 | 23 | 18 | 17 | 15 | 15 | 13 | 13 | 13 | 14 | 23 | 28 | 26 | 27 | 26 | 20 | 21 | 20 | 26 | 32 | 28 | 33 | 35 |

Caveat (MEASURED): busy hours have fewer rows (hour 00 has 378 rows, hour 07 has 710), because the
alarm's ticks slip under load. The busy-hour medians are therefore biased low. The ordering of the
hours still holds: 05-09 is the trough, and 22-01 is the peak.

### Operator presence (MEASURED)
`~/.claude/history.jsonl` `.timestamp`, last 30 days, 1,948 prompts. Prompts by hour: 07:13, 08:15,
09:31 at the bottom; 18-23 at 110-123 each. Absences ≥ 4 h: the operator's last prompt before the
overnight gap was usually 00:46-03:26 (10-09 00:46, 10-08 02:58, 10-07 01:46, 10-06 02:37, 10-01
02:00, 10-10 03:26). The return was 09:36-11:49 (09-24 09:36, 10-10 09:40, 10-08 10:36, 10-09 10:39,
10-12 11:20, 10-14 11:49). **The 10-18 panic (16:33) fell inside a 5.8 h absence (14:05 → 19:50).**
That is why the Mac sat at the FileVault pre-boot screen for ~3 h (boot 16:34:02 per
`date -r 1792359242`; restore began 19:42:59 per the `lost.json` mtime).

### Recommendation (INFERRED from the two tables)
- The trough (05-09) is unusable. The operator is absent then, and with FileVault no session restores
  until someone logs in (§4).
- **Primary: wind-down, about 01:30-03:00.** The operator restarts as the last act of the day and
  types one password. The restore surge (load 614 = 61/core at 14:57 on 10-21,
  `events/boot-1792609590/load.log` line 1) then runs into falling load (02 h median 37 → 05 h median
  20). The sessions work through the night. One drawback: hours 00-01 are the load peak (p90
  442-463), so the shutdown and prep's kitty tree read run under load. Prep retries the tree three
  times and marks a failure (`alarm-reboot-prep.sh:30-38, 199-216`).
- **Fallback: the morning return, about 09:30-11:30**, which is the operator's first prompt after a gap
  of 4 h or more. Load is median 17-24 there. The cost is that the operator's working start waits
  10-15 min for the restore.
- Prefer an event trigger to a clock time: "the window is open" is the operator's first prompt after
  00:00 on `reboot_by − 1` (wind-down), or after a 4 h gap (morning). The data shows a schedule that
  moves by ±2 h from day to day.
- Coalesce: if a macOS update is pending, take it in the same window. On 10-21 the Software Update
  restart **logged in automatically** after Template Migration (REPORT.md:5), so an update reboot
  needs no password. Leave 25+ min for migration (it ran 1534 s on 10-21).

## 4. FileVault and `fdesetup authrestart`: what it can and cannot do

| Limit | Evidence |
|---|---|
| Must run as root and prompts for a password to unlock the volume. An agent cannot run it (no sudo), and `-inputplist` would pipe a password through, which the no-secrets rule forbids | `man fdesetup` (authrestart, quoted: "fdesetup must be run as root and itself prompts for a password") |
| `-delayminutes N` delays the restart; `-1` means "never", i.e. no automatic restart | `man fdesetup` lines 176-183 |
| On Apple silicon the token works for one restart only | [Eclectic Light 2023-02-20](https://eclecticlight.co/2023/02/20/macos-13-2-1-authenticated-restart-and-fdesetup/); [Apple dev forums](https://developer.apple.com/forums/thread/774703) |
| Weakens FileVault while armed: an unlock key stays in memory / SMC (Secure Enclave on Apple silicon) | `man fdesetup` WARNING paragraph |
| Skips the pre-boot unlock only. "The user's password is still required at Login Window", so user LaunchAgents (boot-resume) still wait for a login | [Twocanoes FAQ](https://twocanoes.com/knowledge-base/password-utility-faq/). **Not tested on this Mac** |
| Can fail into Recovery, asking for the password anyway | Eclectic Light, same article (13.2.1 incident) |
| Useless for a panic, which is unplanned | by construction. The panic is where the 3 h FileVault wait came from (§3) |
| An institutional recovery key needs a keychain file holding a private key, which is a stored secret | `man fdesetup` (`-key path_to_keychain_file`) |

Conclusion (INFERRED): for an attended reboot, authrestart saves nothing. The operator types the
FileVault password once, FileVault single sign-on logs in, and boot-resume starts. For an unattended
reboot it most likely stops at the login window. **Backlog `0822e916af70` ("Reboot this Mac with
FileVault auto-unlock", `run: sudo fdesetup authrestart`) assumed authrestart solves an unattended
reboot. It was closed done on 10-21 by the update reboot** (MEASURED, `backlog.jsonl` done event
2026-10-21T23:57:10Z). Do not re-file it as the plan.

One cheap test for the operator, since the reboot is attended anyway: at the next planned reboot run
`sudo fdesetup authrestart` instead of Restart, and note whether the Mac lands at the login window or
on the desktop. If it lands on the desktop, an unattended trough reboot becomes possible:
`sudo fdesetup authrestart -delayminutes -1` at wind-down, then a restart in the trough. That restart
must not need root, and **whether a later non-root restart uses the armed token is untested**. The
operator also has to accept that FileVault is weakened for those hours. Without that test result,
plan only around the operator being present.

## 5. Reboots per month (INFERRED; method stated)

Method: interval T = reboot line / rate, line = min(14 GiB, 19.98 − 6 × rate), month = 30.44 d. The
"with natural reboots" columns model other reboots (OS updates, kitty restarts) as a Poisson process
at rate λ, which resets the zone. Leak-driven reboots per month = 30.44 · e^(−λT) / E[min(T, Exp(λ))].
λ = 1/month is an estimate. MEASURED reference: `last reboot` shows 5 boots from 09-16 to 10-21 (two
on 09-16, the 09-30 kalloc reboot, the 10-18 panic and the 10-21 update), so non-leak reboots are
about 1 a month.

| Rate (GiB/day) | elements/s | Days to 14 GiB | Days to ceiling | Leak reboots/mo (no other reboots) | Leak reboots/mo, λ = 1/mo | All reboots/mo, λ = 1/mo | λ = 0.5/mo: leak / all |
|---|---|---|---|---|---|---|---|
| **0.92** (now) | 11.2 | 15.2 | 21.7 | **2.0** | 1.54 | 2.54 | 1.76 / 2.26 |
| **0.30** | 3.6 | 46.7 | 66.6 | **0.65** | 0.28 | 1.28 | 0.43 / 0.93 |
| **0.10** | 1.2 | 140 | 200 | **0.22** | 0.01 | 1.01 | 0.06 / 0.56 |

Planned-reboot downtime per month (INFERRED, at the §6 estimate of ~20 min each, leak-driven only, no
other reboots): 0.92 → ~40 min; 0.30 → ~13 min; 0.10 → ~4 min, and in practice ~0 because update
reboots come first. At today's cost (86 min restore + 47 min migration + shutdown, the 10-21
measurement) the 0.92 row would be ~4.5 h a month.

What this means: the prevention axis (shim plus lint) is worth doing mainly to get from 0.92 to
≤ 0.3. Below 0.3 the leak no longer sets the reboot cadence, and further cuts buy little on the ops
side.

## 6. How today's restore fixes change the cost of each reboot

All seven commits are on origin/main (MEASURED, `git branch -r --contains`, each prints
origin/main): T1 `1d9c25e83 7c59a11e9 c79df4865 b259a9a14`, T2 `160bd4cb3 af5eda439`, T4
`8519389c7`. The live boot-resume plist has no Nice and no LowPriorityIO, and logs to
`~/.claude/logs/boot-resume.stdout.log` (MEASURED, `plutil -p`). T3 (prep and land) is **still open**
(`REBOOT_RESUME_PERFECTION_2026-10-21.md:77`).

| Phase | 10-18 panic (MEASURED) | 10-21 planned + OS update (MEASURED) | Next planned reboot (INFERRED) |
|---|---|---|---|
| Shutdown | none (panic 16:33:33 → boot 16:34:02) | kitty quit dialog and Dia vetoed 13:54:55-13:59:53 (REPORT.md:112); boot 14:06:30 | still needs clicks until T3's `--arm-restart` (R14) lands |
| Boot → login | ~3 h at the FileVault screen (operator absent) | 47 min (Template Migration 1534 s, then automatic login) | ~1-2 min if attended; no migration on a plain reboot |
| Load gate | opened after 1.5 min (19:42:59 → 19:44:36) | 600 s, never opened (`load.log` 1792612629 → 1792613229, 61.47 → 6.99/core) | 0, telemetry only (R4) |
| Layout | 19:44 → 20:08 (24 min, utility priority) | 15:07:09 → 15:35:11 (28 min); stagger 12 s, admission 4 → 278 s | normal priority (R5), 2 s stagger, prompted rows first (R17); est. 5-10 min |
| Confirm + page | 20:08 → 20:14:58 | 15:35 → 16:10 confirm, page 16:23:23 to the backlog (no desk role) | wall-clock bound ~90 s (R7); page right after the layout, to the owner (R8) |
| Whole restore | 32 min | **86 min** (14:57:05 → 16:23:23) | **~10-15 min** |
| Who resumes working | n/a | 11 of 26 prompted; the lead and the sevenrooms lead sat idle until the operator typed (REPORT.md:1-3) | true cut (R1), owner, promise, mail and unblocked kinds (R2, R3): T1 replay woke 551eb39b and 9240c6a9 (plan :65-69) |
| Handoffs, drafts | none (panic) | written, drafts saved | same, and the owner is recorded once T3 lands |

INFERRED net effect: a planned reboot falls from ~2.4 h of wall time (13:59 → 16:23 on 10-21, of
which 47 min was update-only) to ~15-20 min plus one password. A panic still costs hours, because it
strikes when the operator is absent (§3), plus every in-flight turn. That asymmetry, ~20 min planned
against ~3.7 h unplanned (16:33 → 20:14 on 10-18), is the case for rebooting early on the forecast
rather than late. **Not yet measured:** no reboot has run on the fixed code. The first planned reboot
should record S3 (§2) from its event dir.

Costs that remain whatever the speed (INFERRED, unmeasured): every session's prompt cache goes cold,
MCP servers restart, and in-flight tool calls die. The restore surge itself runs about 40 Claude
Code startups at once (load 614 at login).

## 7. Automatic reboot prep at the forecast (design; T3 is a dependency)

A daily planner tick, plus one at each alarm tier, inside capacity-alarm's existing zone block
(:2300-2355) or as its own small launchd job:

1. **T − 3 d** (computed from `reboot_by`): add `reboot planned <window> (zone X%, reboot-by D)` to
   the `operator-readout.sh` ⚠ line. No banner.
2. **T − 1 d**: banner plus phone (needs the Pushover file, backlog `516d31862158`). Run
   `alarm-reboot-prep.sh --dry-run`, which writes no reboot record (`:46-48`). This proves the
   arrangement is capturable and lists lands in flight, so window-day problems show up a day early.
3. **Window open** (the event trigger in §3): a banner every 30 min. Also give one command,
   `cc-reboot-now`, which runs prep (non-dry), then `--arm-restart` (R14: final heartbeat,
   `confirm_os_window_close=0`, list the vetoing apps), then a non-root restart through System
   Events. The operator running it is the consent. Agents never run it.
4. **Overdue** (past `reboot_by`): page every 4 h. At tier 3 (85%), "reboot today" on every channel.
   The 10-18 lesson is that ALARM without escalation never acted.
5. **Every reboot, whatever caused it, resets the plan.** Boot-resume records S3. The planner appends
   one row per boot (boot, hours, LS slope, mean load, Bash calls, elements/call) to a per-boot rate
   ledger, which is S2's data. `kalloc-zone-series.tsv` already holds all boots (191 rows, MEASURED
   `grep -c`). The ledger only summarizes it.

Dependencies still open: T3 (R13 phase-aware prep, R14 no-click restart, the owner file R2), the
Pushover file, and decision `ee0ad84e8974` (the standing reboot rule, recorded as "actioned",
resolved 2026-10-19T07:43:47Z, no recorded option field, MEASURED `jq .resolved`).

## 8. Uncertainties and untested items
- Post-authrestart login behaviour on this Mac (§4). The single most valuable test on the ops side.
- Restore time on the fixed code (§6). The first planned reboot measures it.
- λ for natural reboots (§5) is estimated from 5 boots in ~5 weeks. Two of those were leak-related.
- The ×1.5 slope margin is a judgement, set from one boot's hourly spread.
- The exec census (prevention axis) had not finished when this was written. It does not change the
  ops design, only which row of §5 applies.

## Critique

Adversarial review, 2026-10-22 00:05-00:25 CDT. I re-ran the cited commands and re-read the cited
lines; nothing was edited except this section. One slip, the same kind as the researcher's: I wrote
a scratch file, `/tmp/kalloc-crit-hist.tsv`, which the rules did not allow, and deleted it at once
(`rm -f`, then `test -e` → gone). Everything after that ran as pipes.

### Verdicts on the main claims

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Detector exists, scheduler missing, no phone leg | **Holds, one omission** | `test -f ~/.config/lr-page/pushover.env` → ABSENT. `zone_notify` (`capacity-alarm.sh:2227-2244`) has only osascript plus Pushover. The omission is that the banner also fires on the first `osr_code: 9` line at any tier (`:2327`), so "only at 50%" is incomplete |
| 2 | Unattended plain reboot is impossible; authrestart does not change that | **Holds for plain reboots, three corrections** | `fdesetup status` → On. `DisableFDEAutoLogin` is absent (`defaults read /Library/Preferences/com.apple.loginwindow`), so the FileVault unlock logs the user in, and one password is the whole attended cost. `fdesetup supportsauthrestart` → true. (a) The "untested" `-delayminutes -1` question is answered in `man fdesetup` (`-delayminutes`, lines ~323-330): "the auth restart operation will occur whenever the user next restarts". It is still unproven on this Mac. (b) The [Apple forums thread 774703](https://developer.apple.com/forums/thread/774703) does **not** support "single-use": DTS declined to answer. Only [Eclectic Light](https://eclecticlight.co/2023/02/20/macos-13-2-1-authenticated-restart-and-fdesetup/) says it ("the token used to authorise them on Apple silicon models can only be used once"). (c) The [Twocanoes](https://twocanoes.com/knowledge-base/password-utility-faq/) quote checks out verbatim |
| 3 | Operator presence from `history.jsonl` is MEASURED | **Refuted as a measure of the operator** | The file records automated prompts. Over the last 30 days, counting each prompt's first token with jq, 1,941 prompts include `/exit` 407, `/goal` 215, `[locate]` 94, "You are …" briefs 95, `TASK` 38, "(Checking in)" 35 and "Reply with only OK …" 28. Four of the six "last prompt" anchors in §3 are `/exit` (10-06 02:37, 10-07 01:46, 10-09 00:46) or a "You are the TrueMemory 2.0 research program LEAD" brief (10-10 03:26). The 10-18 "return" at 19:50 is boot-resume's own `[restore] The Mac rebooted at 16:34…` prompt. The real return is the login at 19:42:59 (`lost.json` mtime), and the last human prompt was 13:14. So the absence was about 6.5 h, not 5.8 h |
| 3a | …what a filtered read shows | MEASURED, heuristic filter | Dropping those first tokens and prompts of 1,500 characters or more keeps 925 prompts. Overnight stops then fall at 23:26-03:57 (median about 02:07), returns at 09:19-13:22 (median about 10:39), and there are **five absences of 21 h or more in 30 days** (55.6, 54.3, 31.3, 23.6 and 21.7 h). The window centres roughly survive. Two things do not: the event trigger in §3 ("first prompt after 00:00") would be opened by automation, and the design needs a rule for a reboot-by date that falls inside a multi-day absence |
| 4 | Load-by-hour table | **Holds** | Recomputed from `capacity-alarm.jsonl` plus the `.20261009T015023Z.gz` file, hours shifted to CDT. Medians and p90s match to within ±2, with n = 378 at 00 h and 710 at 07 h. Daily medians for 10-18..10-21 are 117, 195, 83, 81 |
| 5 | §2 worked example: "slope_hi ≈ 1.4, line = 14 GiB, reboot_by ≈ 10 d / 15 d" | **Refuted (arithmetic)** | §2's own formula gives min(14, 19.98 − 6 × 1.38) = **11.7 GiB**, not 14. That puts reboot_by at about 8.5 d (high slope) and 12.7 d (mean). §5 uses 6 × *rate* instead (19.98 − 5.5 = 14.5 → 14), so the two sections define the line differently. Under the §2 planner, the 0.92 row is about **2.4-2.7 reboots a month, not 2.0**. The 0.3 and 0.1 rows are unaffected (line = 14 either way) |
| 6 | Reboots a month and "0.3 GiB/day is the point" | **Arithmetic holds; the threshold is a λ-dependent judgement** | λ/(e^{λT} − 1) reproduces 1.54, 0.275 and 0.010 (λ = 1) and 1.76, 0.43 and 0.056 (λ = 0.5). But λ comes from a short window. `last reboot` lists 11 boots since 08-09 (73 d). Leaving out 09-30 and 10-18, about 6 distinct non-kalloc reboot days gives λ ≈ 2-2.5 a month. At λ = 2 the leak reboots are 1.17 a month at 0.92 and 0.10 at 0.3. At λ = 0.5 the leak still causes 46% of reboots at 0.3. So the bolded §0 line is INFERRED, not a measured threshold |
| 7 | "~4.5 h a month at the old cost" | **Overstated** | It counts the 47 min Template Migration, which §6 itself says a plain reboot does not have. Without it the figure is 2 × (86 + about 5) ≈ **3 h** |
| 8 | "T3 still open; the restart still needs clicks until `--arm-restart` lands" | **Stale, refuted** | `3d9085132` "feat(alarm-reboot-prep): owner file, phase-aware lands, lock, temp pruning, --arm-restart" (R2, R13, R14, R22) landed at 2026-10-21 23:51:26 CDT, before ops.md was written (00:03). `git branch -r --contains 3d9085132` → origin/main, and the shared checkout's HEAD is that commit, so it is live. Plan line `:77 T3 — open` is itself stale. Not verified: T3's R15 (ship-land) and the R1 terminal-intent and `--until` parts (plan `:22`) |
| 9 | Dependency: "decision `ee0ad84e8974` (the standing reboot rule)" | **Wrong id: the rule already exists** | `ee0ad84e8974.json` evidence: "superseded by open decision 95563f6aa4dc". `95563f6aa4dc.json`: status actioned, resolved 2026-10-21T04:56:13Z, evidence "operator approved 2026-10-20: reboot with sudo fdesetup authrestart, timed from the live zone alarm". Its question covers "before the kernel leak reaches 14 GB … and again whenever the forecast puts the 20 GB ceiling under 3 days away". So the standing rule is ruled, and **the operator picked authrestart**. §4's "saves nothing, do not re-file it" is a proposal to amend that ruling. It should go to the operator as a proposal, not be settled in this doc |
| 10 | S3: "≤ 20 min, one operator action" | **Incomplete** | It leaves out the operator's wait between Restart and the FileVault prompt: shutting down about 40 sessions at the 00-01 h load peak, then the boot. On 10-21 the restart was released at 13:59:53 and kern.boottime is 14:06:30 (6.6 min, including the update apply). This is unmeasured for a plain reboot, and at wind-down it is the operator's entire cost |
| 11 | Slope 0.914, 6 h 0.825 | **Holds** | My least-squares fit over the 21 series rows since boot gives 0.908 GiB/day, the last 6 h 0.826, and 0.877 without the 14:59 pre-test row. Live: the residual (data.kalloc.1024 − cred) rose 6,443 elements in 617 s between the doc's read and mine (388,727 / 6,208 at 1792645735) = 10.4/s ≈ 0.86 GiB/day. Caveat: every row this boot is from 15:00-24:00. The research doc's quiet-hour read is about 0.75 GiB/day, and the 1.5× margin covers the post-0070 hourly spread (1.3×), not the pre-0070 restore-surge spread (3.4-4.2×) |

The core thesis survives. Reboot-on-forecast with automated prep and one operator action is the
ops answer, and authrestart does not unlock an unattended *plain* reboot. Leaked elements cannot be
reclaimed without a reboot (INFERRED): the A/B ran the *same* `leaf.sh` 3000 times per arm
(`~/.cache/kalloc-158-ab/run2.sh`, arm S) and still kept 1.1 per exec. A per-vnode cache would not
grow that way, so vnode recycling would not free the elements.

### Cheaper or more robust options the doc missed

1. **A level trigger instead of a forecast planner.** Rule: reboot at the first operator window
   after tier 1 (50%, ~10 GiB). The alarm already banners there and repeats daily (`:2328-2329`).
   At 0.92 GiB/day that leaves about 10.8 d to the ceiling, against the longest observed absence of
   2.3 d. At the worst measured boot (pre-0070, 4.4 GiB/day) it leaves 2.3 d. It costs about 0.8
   extra reboots a month at 0.92 (an interval of 10.9 d instead of 15.2), so about 16 min a month
   at the §6 estimate. In return there are no `slope_hi`, `reboot_line` or `window_next` keys to
   get wrong (row 5 shows how easy that is). INFERRED.
2. **A phone leg that does not wait on the Pushover credential**, which has been operator-blocked
   since 09-30 (`516d31862158`). The reboot duty died in exactly that kind of row on 10-18 (research
   doc :45-49). iCloud Reminders is enabled here (`defaults read MobileMeAccounts` → REMINDERS
   `Enabled = 1`). A dated "reboot by D" reminder, created once per boot and moved on each
   re-forecast (osascript → Reminders, one TCC approval), would reach the phone. That assumes the
   phone uses the same Apple ID, which is unverified. INFERRED, untested.
3. **Presence from human input, not `history.jsonl`.** `ioreg -c IOHIDSystem` → `HIDIdleTime` is
   readable without root (it read 1005 s at 00:09). `pmset -g log` keeps `UserIsActive` records from
   the HID tickle, a no-root history of real input. Caveat: a CGEventPost or Karabiner virtual
   keyboard also resets it. Use either one for the window trigger and for "is the operator away".
4. **A dead-man's switch for the multi-day absence.** At tier 3, or on the first `osr_code: 9`,
   with HID idle over N h: run prep and then a graceful non-root restart instead of waiting for the
   panic. The downtime is the same, because FileVault waits for the operator either way. The
   difference is that handoffs and drafts are saved and in-flight turns end cleanly instead of
   dying. This needs an operator ruling, since agents never reboot today.
5. **An unattended zone reset when an update is pending.** The 10-21 update restart logged in by
   itself (REPORT.md:5, MEASURED), so an update-coalesced reboot does not need the operator. Software
   Update's "Try Tonight" ([Ntiva](https://support.ntiva.com/hc/en-us/articles/11977338074381-macOS-Software-Update-Experience))
   can put it in the 05-09 trough that §3 calls unusable. INFERRED for 15.8.x, and it must exclude
   the macOS 27 upgrade (operator ruling).
6. **FileVault off with automatic login.** This is the only no-code route to unattended reboots
   and self-healing panics, at a real at-rest-security cost. The doc should list it for the operator
   as an explicitly rejected option rather than leave it out
   ([decision recheck 10-20](../decision-recheck-2026-10-20/REPORT.md) already names "FileVault
   password at every boot" as the operator's lever).

Sources for this section: the commands and files named in the table, plus
[Twocanoes](https://twocanoes.com/knowledge-base/password-utility-faq/),
[Eclectic Light](https://eclecticlight.co/2023/02/20/macos-13-2-1-authenticated-restart-and-fdesetup/),
[Apple forums 774703](https://developer.apple.com/forums/thread/774703) and
[Ntiva](https://support.ntiva.com/hc/en-us/articles/11977338074381-macOS-Software-Update-Experience).
