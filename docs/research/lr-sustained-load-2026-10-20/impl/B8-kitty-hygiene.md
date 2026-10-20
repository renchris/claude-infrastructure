# B8: kitty hygiene at a planned kitty restart (implementation design)

Item B8 of `../REPORT.md` §4(b): App Nap (`NSAppSleepDisabled`), kitty's priority while the screen is
locked, a patched build if any, and kitty's fd headroom.

This is read-only research, done 2026-10-20 between about 17:55 and 18:35Z on the live box:
- macOS 15.7.9 (24G830), 10 cores;
- load1 between 164 and 272 while I worked (`sysctl -n vm.loadavg`, several readings).

I typed into no pane, signalled no process, launched nothing, loaded nothing and edited nothing
outside `/tmp/b8/` and `/tmp/b8-*.txt`. Every kitty remote-control (RC) call was a read (`kitten @ ls --match`).

Labels:
- **[M]** measured, with the command named;
- **[E]** estimated, with the method named;
- **[H]** hypothesis, not verified.

Code citations are to this worktree (`main` at `28b25a119`).

**Verdict: OPERATOR. Conviction: 65%.**

What needs the operator:
- writing the defaults key;
- every kitty start or upgrade;
- the build choice.

What an agent can build end to end, read-only plus advisory hooks:
- a hygiene check;
- a nap-forensics verb;
- an overnight sampler.

The 65% is my estimate that the plan below, as written, is worth doing and removes the kitty-side App Nap
class it targets. It is not higher for two reasons:
- the key's effect on kitty is shown only through a natural control (Dia);
- a nap does not always make kitty deaf (§1.5).

The operator's 10-minute A/B (step O1/O3) settles both questions before anything is relied on.

---

## 0. Summary

**What B8 now is.** It has three parts, and none of them requires a dedicated kitty restart.

1. **The App Nap key: one operator command, now.**
   - `defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES`.
   - It is read when kitty starts [H: Mavericks-era sources, §1.3]. The running kitty's signal path is
     broken anyway (§1.6), so it rides whatever the next kitty start is: a reboot, a crash, or a planned
     `cc-restore --restart-kitty`.
   - The REPORT's risk line "a kitty restart ends all 32 windows" is therefore not a cost of B8.
2. **No patched build.** The operator ruled "stay on official kitty, no re-sign" (decision `891ea9e9d0f3`,
   actioned 2026-10-19T23:37:48Z, `docs/research/kitty-lastpane-move-2026-10-19/README.md:100`).
   The build step becomes the official Homebrew cask:
   - **0.49.2**, already released, carries the #10436 signal fix. That fix stops the zombie pile-up and
     restores SIGUSR1 config reload and graceful SIGTERM.
   - **0.50.0**, not yet released, carries the RC-listener fix #10632. It is what makes the talk thread
     survive fd exhaustion.
   - Source for both: upstream `docs/changelog.rst`, §1.6.
3. **fd watch.** kitty holds 121 fds against a 256 soft limit [M/H]. A read-only status check reports it.
   An optional in-kitty `setrlimit` watcher (C3 P1) is listed for operator approval.

**What this research changes in the REPORT's B8 entry.**

- **The mechanism is measured on this box.** App Nap is an assertion that kitty's own AppKit hands to
  RunningBoard, called "AppNap adapter assertion".
  - Active, it carries `PreventLowPriorirtyCPU`, `PreventSuppressedCPU` and `PreventDiskThrottle`.
  - Napped, it carries only `Enable` plus a timer tier (`PreventTimerThrottleTier4`/`Tier5`).
  - Napped and not the focal app, kitty reads **base priority 4 on every thread**, talk thread included.
    Measured on a second kitty that is live now (pid 41475) and on Console.app (§1.2).
- **kitty naps far more than assumed.** From RunningBoard's log:
  - kitty 853 was napped 24,159 s of its first 17.3 h;
  - kitty 44163 was napped 39,648 s straight during the 10-18 display-off;
  - **during the incident itself, kitty was napped from 03:56:48 to 04:08:41Z** (screen locked by the 3600 s
    screensaver idle timer at 03:56:04Z; `loginwindow` log), plus three non-focal naps of 61-122 s at
    02:28-02:54Z (§1.4).
- **Most naps were harmless.**
  - When kitty was the focal app, RC kept answering through a 5.8 h lock-screen nap (7 recycles engaged,
    0 unreachable rows) and through an 11 h display-off nap (17 engaged, 33 typed attempts).
  - In the incident's 12-minute nap, 3 of 3 prechecks read `kitty_probe: answers … tries=1` (§1.5).
  - The REPORT's "removes the overnight priority-4 class" overstates how often that class occurs.
- **Two harmful episodes remain:**
  - **10-01:** kitty non-focal at PRI 4 behind a lock. The REPORT's "9/9 failed at 10 s" came 1-2 min
    *after* the talk thread died at 07:06:47Z (C3:1-24). So it is a class C reading. The 180 late answers
    before the death are the class B evidence.
  - **10-17:** kitty was deaf for hours at 0.0% CPU during a **focal** display-off nap (13:52:45-17:53:30
    CDT), then recovered with no restart (`docs/lessons/two-causes-one-rc-ask-a-lower-layer.md:78-93`).
    The display coming on and the nap ending fell 3 s apart, so App Nap and display-off are confounded
    there.
- **kitty's "Broken pipe" log line is blind to nap deafness.** Kitty's own log has 0 such lines across the
  10-17 deaf window, and its log lines are retained for that window (12 lines in 30 min). Axis 07 §8 and B6
  should not use that count as a class-B detector.
- **`cc-restore --restart-kitty` would refuse today.** Its "exactly one main kitty" preflight sees 2: 853
  and a developer kitty, pid 41475 at `~/kitty-pr3`. I reproduced its selection read-only (§1.8).

---

## 1. Evidence

### 1.1 Live readings, 2026-10-20 18:00-18:32Z

| # | What | Reading | Command | |
|---|---|---|---|---|
| 1 | kitty processes | 853 `/Applications/kitty.app/Contents/MacOS/kitty`, up since 10-18 19:40:35 CDT, PRI 47. 41475 `/Users/chrisren/kitty-pr3/base/kitty/launcher/kitty --config=NONE …`, PRI 4 | `ps -axo pid,ppid,pri,…,comm \| grep -i kitty` | M |
| 2 | kitty 853 threads | main `47T` (46T at 18:31Z); 25 threads `31T`; one `20T`, one `4T` (kitty's own background threads) | `ps -M -p 853` | M |
| 3 | kitty 853 task base | **31** | `python3 -I scripts/limit-recover/lr_recon/band.py 853` (`proc_pidinfo` PROC_PIDTASKINFO, `band.py:74-92`) | M |
| 4 | kitty 41475 (napped, not focal) | task base **4**, every thread `4T` | `band.py 41475`; `ps -M -p 41475` | M |
| 5 | Other napped apps | Console.app 1125: base 4, `4T`; WiFiAgent PRI 4 | `band.py 1125`; `ps -axo pid,pri,comm` over `.app` mains | M |
| 6 | Dia (`NSAppSleepDisabled=1`), not frontmost | base **31**, PRI 55 | `band.py 1037`; `ps` | M |
| 7 | The key | `defaults read net.kovidgoyal.kitty NSAppSleepDisabled` → "domain/default pair … does not exist". The whole domain does not exist. `defaults find NSAppSleepDisabled` → only `company.thebrowser.dia` and `company.thebrowser.Browser` | as named | M |
| 8 | kitty 853's identity | `bundleID="net.kovidgoyal.kitty"`, `LSLaunchedWithLaunchD=true`, `LSModifierLaunchedForPersistence=true`; 41475 has `bundleID=[ NULL ]` (anon), so no defaults key can reach it | `lsappinfo info -app 853`, `-app 41475` | M |
| 9 | fds | 853: **121** numeric fds (55 PIPE, 34 CHR, 30 REG, 2 unix) | `lsof -n -P -p 853 -a -d 0-65535` | M |
| 10 | Zombie children | 853: **157 `Z`**, 33 `S` (axis 07 read 111 at about 05:00Z) | `ps -axo ppid=,stat= \| awk '$1==853'` | M |
| 11 | Build | live: cask 0.48.2, Developer ID team NTY7FVCEKP, `strings … \| grep -c 'still serving'` = 0. Staged: 1, and `GLFWDeferredClose`/`GLFWFsFixV2` present, but `Signature=adhoc` and it links `/opt/homebrew/opt/python@3.14` and `xxhash` | `strings`, `codesign -dv`, `otool -L`, `grep -c -a` | M |
| 12 | Cask | `kitty: 0.48.2 → 0.49.2`, installed from `/opt/homebrew/Caskroom/kitty/0.48.2` | `brew info --cask kitty` | M |
| 13 | Power and lock settings | `displaysleep 0`, `sleep 0` (caffeinate). Screensaver idle **3600 s**, then lock (`loginwindow`: `idleTime: 3600`, `kLWLockFromScreenSaverIdleLaunch`) | `pmset -g`; `log show … process == "loginwindow"` | M |
| 14 | RC round trip from priority 31 | 853: rc 0 in 76-375 ms (`kitten @ ls --match id:$KITTY_WINDOW_ID`) | `/tmp/b8/kitty-lock-sampler.sh`, 3 one-shot rows | M |

### 1.2 What App Nap is on this box: RunningBoard's own record [M]

Command:

```
log show --style compact --start … --end … --predicate 'process == "runningboardd" AND eventMessage CONTAINS ":853]"'
```

Captures are in `/tmp/b8-rb-*.txt`.

- **kitty originates the App Nap state itself.** RunningBoard logs `Acquiring assertion targeting
  [app<application.net.kovidgoyal.kitty…>:853] from originator [app<…kitty…>:853] with description
  <RBSAssertionDescriptor| "AppNap adapter assertion" …>`. The originator is kitty, so this is AppKit's
  App Nap adapter running inside kitty, which is the layer `NSAppSleepDisabled` configures.
- **Active state:** `com.apple.appnap:{Enable, Inactive, PreventDiskThrottle, PreventSuppressedCPU,
  PreventLowPriorirtyCPU, PreventBackgroundSockets, PreventTimerThrottleTier0}` (Apple's spelling).
- **Napped state:** `{Enable, PreventTimerThrottleTier5}`, with `{Enable, PreventTimerThrottleTier4}` as a
  short intermediate. Every `Prevent*CPU` and `PreventDiskThrottle` is gone.
- **Timing:** the nap engages 34-49 s after kitty is occluded or loses focus.
  - 10-18: display off 21:53:57, nap 21:54:31 CDT;
  - 10-19: lock 22:56:04, occluded 22:56:05.315, nap 22:56:48.503;
  - 10-20, test kitty: active 12:56:09, napped 12:56:50.
- **The darwin role is separate.** Through the incident lock kitty's role stayed `UserInteractiveFocal`. No
  `Set darwin role` line appeared between 21:54:53 and 23:08:49 CDT.
- **Napped plus not focal means priority 4** [M]. The test kitty 41475's last adapter state, since 12:59:20
  CDT, is `{Enable, PreventTimerThrottleTier5}`. At 13:00 and 13:09 CDT it read base 4 with every thread
  `4T` (rows 1, 4).
- **Apple's description** ([Energy Efficiency Guide, App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)):
  - App Nap applies "priority reduction, … timer throttling, … I/O throttling".
  - An app is a candidate when "it isn't the foreground app", has not updated visible content recently,
    is not audible, and holds no power or NSProcessInfo assertions.

### 1.3 What the key does: Dia as the natural control [M; the inference is H]

- `defaults find NSAppSleepDisabled` finds the key only for Dia and Arc (row 7).
- **Dia never holds an App Nap adapter assertion.** In both RunningBoard state dumps captured, Dia (pid
  1037) appears with `AppDrawing`, `AppVisible`, `frontmost`, `FUSBProcessWindowState: occluded/visible`,
  and **0** "AppNap adapter assertion" entries. In the same dumps:

  | Dump | Chrome adapters | kitty adapters |
  |---|---|---|
  | 10-18 21:50-22:20 CDT | 12 | 3 |
  | 10-19 22:58/23:18 CDT | 4 | 2 |

  Command: `grep -c` over `/tmp/b8-rb-1018.txt` and `/tmp/b8-rb-incident.txt`.
  - The Chrome processes are unbundled Chromium; Dia is Chromium-based.
  - Dia was occluded by the same 10-19 lock (22:56:05.316) and acquired no adapter (`/tmp/b8-rb-dia.txt`).
- **Dia is not frontmost and sits at base 31** (row 6). Console.app, also not frontmost but occluded and
  without the key, sits at base 4 (row 5).
- **Inference [H, about 80%]:** with the key set, AppKit never enrolls the process in App Nap, so RunningBoard
  has no nap state to apply.
- **When the key applies.** Web sources are all from the OS X 10.9-10.11 era and agree that the app must be
  relaunched:
  - [Omnis TN0008](https://omnis.net/developers/resources/technotes/tnid0008.jsp): "You must restart …
    before the change can take effect";
  - [TekRevue](https://www.tekrevue.com/tip/disable-app-nap-os-x-mavericks/);
  - [Jamf](https://community.jamf.com/t5/jamf-pro/prevent-app-nap/td-p/94670).

  Whether the running kitty would pick it up live is unknown. Step O2 tests it at no cost.

### 1.4 How much kitty naps [M]

Command: `python3 -I /tmp/b8/parse_life.py <capture>`, a prototype of K1's parser that I validated on the
incident window.

| kitty pid | Window (CDT) | Napped | Of that, not focal | Context |
|---|---|---|---|---|
| 44163 | 10-17 13:40-18:10 | 14,445 s (13:52:45-17:53:30), 1 interval | 0 | display off 13:52:11-17:53:27 (`pmset -g log`) |
| 44163 | 10-18 01:50-13:05 | 39,648 s (01:56:31-12:57:20) | 0 | display off 01:55:58-12:57:18 |
| 853 | 10-18 19:40 → 10-19 13:01 (the query hit its 270 s bound there: coverage ends, unknown after) | 24,159 s in 18 intervals | 1,570 s (11-504 s each, daytime) | includes **04:33:45-10:24:22, 21,036 s** (overnight lock, unlocked 10:24:22 per `pmset` "Loginwindow User Activity") |
| 853 | 10-19 21:25 → 23:20 (the incident, 02:25-04:20Z) | 990 s | 277 s (02:28-02:29, 02:48-02:49, 02:52-02:54Z) | **713 s at 03:56:48-04:08:41Z, focal, screen locked** |

Every lock and display-off episode I queried produced a nap: 6 of 6. The episodes, all CDT, are:
- display-off: 10-17 13:52, 10-18 01:55, 10-18 21:53, 10-19 01:09 (01:10:25-01:13:22);
- lock: 10-19 04:33, 10-19 22:56.

In all 6 kitty stayed the focal app, and the role never changed. Earlier display-offs on 10-17
(02:51-08:23, 08:23-10:43) were not queried.

### 1.5 Does a napped kitty stop answering? [M]

| State | Episode | Load | RC outcome | Source |
|---|---|---|---|---|
| Focal, lock screen | 10-19 09:33:45-15:24:22Z, 5.8 h | load1 median 261, max 359 (`~/.reso/load.jsonl`, 1,513 rows) | **answered**: 9 `recycle-intent` → 7 `recycle-engaged`; `kitty-probe@0-27s`; 2 `recycle-refused-no-pane` whose resolver *answered* "no such session"; 0 unreachable rows | `~/.claude/logs/handoffs.jsonl` |
| Focal, lock screen | 10-20 03:56:48-04:08:41Z, 12 min | 181-396 (43 rows) | **answered**: `7aae55e1.2.R`, `e80b61f4.2.R` and `769b7294.3.A` all read `precheck kitty_probe: answers (/tmp/kitty-853, tries=1)`, plus window, pid and composer fields from kitty | `recon/actlogs/*.log` |
| Focal, display off | 10-18 06:56-17:57Z, 11 h | 12-29/core in the rows | **answered**: 17 engaged, 33 `recycle-type-attempt` (typed through kitty) | `handoffs.jsonl` |
| Focal, display off | 10-17 13:52:45-17:53:30 CDT, 4 h | ~237 | **DEAF**: connect accepted in 0.00 s, no reply in 30 s, 3 retries failed, kitty at 0.0% CPU; "recovered on its own" later | `two-causes-one-rc-ask-a-lower-layer.md:78-93`; commits `753097359` (17:50:41 CDT), `6e11df1ff` (19:42:55 CDT) |
| Not focal, lock | 10-01 (kitty 610) | 120-250 | **PRI 4** in 6 samples, `loginwindow` frontmost; 180 late answers before 07:06:47Z, then talk-thread death | `recycle-unreachable-2026-10-01.md:11-12`; `session-durability-2026-10/C3-socket-robustness.md:1-24` |
| Not focal, hidden or occluded | now (41475; Console) | 164-272 | base 4 on every thread; RC not measurable (41475 has no socket) | rows 4-5 |

Reading:
- **Measured harm path:** a nap while kitty is not the focal app gives priority 4. A priority-4 thread at
  15-40/core is starved:
  - axis 07 row 9: a priority-4 *client* got >30 s on 4 of 4 calls;
  - axis 09 R1: a background-band micro-task got 0 CPU in 7 min.
- **Focal naps answered in 3 of 4 episodes.** The 10-17 exception is unexplained.
  - Candidate causes: App Nap [H, 40%], display-off itself [H], or something else.
  - O3b is a same-moment test that separates them.
- **Instrument finding [M].** `log show --predicate 'processID == 44163 AND eventMessage CONTAINS "peer
  socket failed"'` over 10-17 13:40-18:30 returns **0** lines. Kitty's own lines are retained for that span
  (12 lines in 17:30-18:00). The same query over the 10-18 display-off nap and over 10-19 04:33-18:51 CDT
  also returns 0.

  So the "broken pipe" count cannot detect nap deafness. My first reading of "0 broken pipes overnight
  means kitty answered" was wrong and is not used above.

### 1.6 The build [M]

- **The patched build is closed by the operator.**
  - Decision `891ea9e9d0f3` was actioned 2026-10-19T23:37:48Z as "stay on official kitty, no re-sign"
    (`kitty-lastpane-move-2026-10-19/README.md:100`). The restart marker is absent:
    `ls ~/.claude/autonomy/kitty-restart-pending` → no such file.
  - The staged bundle is ad-hoc signed, so `arm` and `swap` refuse it: `adhoc_refuse`,
    `scripts/kitty-build-swap.sh:105-113`, called at `:208` and `:224`.
  - It would also have lost the 35 TCC grants (`README:109`).
  - It links Homebrew `python@3.14` and `xxhash` (row 11), so a `brew upgrade` could break it.
- **Upstream** (`curl -sL https://raw.githubusercontent.com/kovidgoyal/kitty/master/docs/changelog.rst`;
  `/tmp/b8/dl/changelog.rst`):
  - `:832-838`, under **0.49.0 [2026-09-21]**: "macOS: Fix all signal handling being permanently disabled
    after the first window that used the graphics protocol is closed. This caused exited window shells to
    accumulate as zombie processes and also broke reloading the config with `SIGUSR1` and quitting on
    `SIGINT`/`SIGTERM`/`SIGHUP` (:iss:`10436`)".
  - `:482-484`, under **0.50.0 [future]**: "Remote control: Fix a single unresponsive peer blocking all
    remote control communication and the remote control listener stopping after transient errors such as
    running out of file descriptors (:pull:`10632`)".
  - The latest release is v0.49.2 of 10-01 ([releases](https://github.com/kovidgoyal/kitty/releases)).
  - This corrects `kitty-crash-2026-10-15/README.md:620`, which places f3fdc21850 in 0.50.0. C3:27-28
    ("shipped in **v0.49.0+**") had it right.
- **Live kitty 853 is in the #10436 state** [M row 10 + changelog]: 157 zombies, and growing. So SIGUSR1
  config reload and SIGTERM are dropped.
  - No kitty.conf change, a `watcher` included, reaches 853. kitty reloads config through
    `kitten __watch_conf__` → SIGUSR1 (`bin/cc-kitty-reload:18-33`).
  - `cc-restore`'s TERM, 3 s, KILL step (`bin/cc-restore:20`, "kitty 0.48.2 can drop the first") is
    required, not belt-and-braces.
- **The cask** (`curl -sL https://formulae.brew.sh/api/cask/kitty.json`, `/tmp/b8/dl/kitty-cask.json`):
  - artifacts: `app`, two `command_wrapper` entries, and `zap`;
  - **no `uninstall quit:`**, so `brew upgrade --cask kitty` does not quit the running kitty;
  - **`zap` trashes `~/Library/Preferences/net.kovidgoyal.kitty.plist`**, which is where the key lives.

### 1.7 fd headroom [M; the limit is H]

- 121 fds now (row 9); axis 07 read 121 and its skeptic 125.
- The soft limit is probably 256:
  - `launchctl limit maxfiles` read "256 unlimited" on 10-01 (C3 §1.1) and today (B1 M9);
  - kitty never calls `setrlimit` (C3 §1.1);
  - I did not run `launchctl`.
- Abandoned peers hold an fd until the main thread answers (`prune_peers`, axis 07 §2). A deaf episode of
  about 135 abandoned calls (256 − 121) therefore reaches EMFILE, and on 0.48.2 and 0.49.x EMFILE kills the
  talk thread (C3). 0.50.0 stops that.
- `cc-restore` already stops a restore if the new kitty holds more than 180 fds (`CC_RESTORE_FD_MAX`,
  `bin/cc-restore:31`).

### 1.8 The restart path [M]

- **Main-kitty preflight.** `bin/cc-restore:137-152` (`kitties`, `main_kitties`) treats any process whose
  executable basename is `kitty` as main, unless it has `--instance-group` or a `+` helper argument.
  Replaying that rule read-only on today's `ps -axo pid=,lstart=,args=` gives **2** (853 and 41475). So
  `preflight` (`:498-523`) prints "expected exactly one main kitty, found 2" and a real run exits 3.
- **Restore start gate.** It waits for load/core ≤ `CC_RESTORE_START_LOAD` 6 for at most
  `CC_RESTORE_GATE_MAX_S` 600 s, then goes ahead (`scripts/boot-resume.sh:956-966`, `:1245-1250`). That is
  bounded, but under the premise it always costs the full 600 s.
- **Deaf-kitty page.** It tells the operator "do NOT restart yet, wait until it is under"
  (`boot-resume.sh:452`). Under the operator premise that is an unbounded human wait. The gate behind it is
  bounded anyway, so the advice should be dropped (flagged for the restore owner; not B8 code).
- **Runtime injection points** (rule "Binary-only names your layer",
  `.claude/rules/agent-operating-lessons-situational.md:124`):
  1. A kitty.conf `watcher`: blocked on 853 by #10436 (no SIGUSR1).
  2. An RC command: none touches App Nap.
  3. The key read live: unknown; O2 tests it.
  4. `taskpolicy -B -p <pid>`. Its man page says "Move target process out of PRIO_DARWIN_BG". Whether
     RunningBoard re-applies the nap at the next transition is [H]. It is an operator-only diagnostic on a
     non-production kitty, never the fix.

  So only (3) could avoid waiting for the next kitty start.

---

## 2. The design

### 2.1 Principles

- **P1. No dedicated restart.** Everything kitty-side lands at the next kitty start, whatever causes it.
  B8 adds no restart and no window loss of its own.
- **P2. Measure before relying.** A same-moment A/B with a throwaway kitty (O1/O3) proves the key on this
  macOS build. The control arm must be red (base 4) for the treatment arm to count (rule "Green in both
  arms", `situational.md:62`).
- **P3. Our timeout is never a verdict.** `log show` took 60-270 s per query at load 230-270 [M, this
  session's runs; one hit its 270 s bound]. `lsof` and `ps` can also stall. Every bounded read that fires
  reports **UNKNOWN**, never "no naps", "healthy" or "dead" (REPORT G2; rule "Fail-safe mimics healthy",
  `situational.md:8`).
- **P4. Hooks are advisory.** The hygiene check prints lines into `cc-restore` and `alarm-reboot-prep`. It
  never fails a restore or a reboot prep.
- **P5. Agent code never writes the key, never signals or launches kitty, and never upgrades the cask.**
  K1's tests enforce this (T9).

### 2.2 Operator script (exact commands, in order)

Run each block in a **kitty pane**, which runs at priority 31. Nothing here touches the 32 live windows
until O4.

**O0. Baseline (read-only; an agent may run it too).**

```bash
defaults read net.kovidgoyal.kitty NSAppSleepDisabled 2>&1 | tail -1   # expect: "... does not exist"
ps -axo pid=,args= | awk '{ n = split($2, a, "/"); if (a[n] == "kitty" && $0 !~ /--instance-group/ && $3 !~ /^\+/) print }'
#   expect today: 2 lines (853 and the ~/kitty-pr3 dev kitty 41475) — cc-restore will refuse until it is 1
python3 -I ~/Development/claude-infrastructure/scripts/limit-recover/lr_recon/band.py 853   # 31 while kitty is visible
```

**O1. Control arm: a throwaway kitty without the key (~4 min). It must come out red.**

- The probe has no config, its own socket and its own instance group:
  - the socket name `/tmp/kitty-b8-ctl` has a non-numeric suffix, so `lr_recon/observe.py:205-207` and
    `bin/cc-kitty-socket:78-79` both skip it;
  - `--instance-group` keeps it out of `cc-restore`'s main-kitty count (`:149-152`);
  - it has no sessions, so the restore heartbeat never records it (`scripts/lib/restore-heartbeat.sh:471-475`).
- The sampler is `/tmp/b8/kitty-lock-sampler.sh` (validated; its text is in Appendix B; K1 `sample` replaces
  it once landed).

```bash
open -n -a /Applications/kitty.app --args --config NONE --instance-group b8-ctl \
  -o allow_remote_control=socket-only -o listen_on=unix:/tmp/kitty-b8-ctl
sleep 5; P=$(pgrep -f 'instance-group b8-ctl' | head -1); echo "control probe pid=$P"
# Click the probe's window once, press ⌘H (hides only that instance), click back into this pane.
KS_SOCK=unix:/tmp/kitty-b8-ctl KS_MATCH=id:1 KS_EVERY=30 KS_N=6 \
  bash /tmp/b8/kitty-lock-sampler.sh "$P" /tmp/b8-ctl.tsv; column -t /tmp/b8-ctl.tsv
log show --style compact --last 5m --predicate "process == \"runningboardd\" AND eventMessage CONTAINS \":$P]\" AND eventMessage CONTAINS \"AppNap adapter\"" | grep -c 'AppNap adapter assertion" ID'
kill "$P"     # a fresh kitty still handles SIGTERM
```

- **Expected (red):** `kitty_base` 4 within about 90 s of ⌘H; ≥1 adapter acquisition.
- **Also read `rc_rc` and `rtt_ms` at base 4 under today's load.** This is the first direct measurement of
  RC to a priority-4 kitty. `rc_rc` 124 or multi-second RTTs mean the harm is real at this load. rc 0 in
  under 1 s means the priority-4 class barely matters for RC, and B8's value drops to insurance.
- **If base never reaches 4, the control has no power.** Do not draw conclusions from O3; report it.

**O2. Write the key (seconds, no restart).**

```bash
defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES
defaults read  net.kovidgoyal.kitty NSAppSleepDisabled                 # expect: 1
stat -f '%Sm (%m)' ~/Library/Preferences/net.kovidgoyal.kitty.plist     # adoption reference: kitty must start after this
```

Live-adoption check, answering open question Q1. The next time kitty 853 is occluded or hidden for more
than 60 s (or press ⌘H on it for 90 s now), run:

```bash
log show --style compact --last 10m --predicate 'process == "runningboardd" AND eventMessage CONTAINS ":853]" AND eventMessage CONTAINS "AppNap adapter"' \
  | grep -A8 'AppNap adapter assertion" ID' | grep -o 'name:"[A-Za-z0-9]*"' | sort | uniq -c
```

- `PreventTimerThrottleTier5` without `PreventLowPriorirtyCPU` means 853 still naps. That is expected [H];
  the key rides the next start.
- No new adapter acquisition means the key applied live, which is a bonus.

**O3. Treatment arm: the same probe, now with the key (~4 min). It must come out green.**

Repeat O1 with `b8-trt` in place of `b8-ctl`. Expected: `kitty_base` ≥ 31 throughout, `rc_rc` 0, and 0
adapter acquisitions for the probe's pid.

**O3b (optional, about 20 min away from the desk): separating display-off from App Nap (the 10-17 class).**
Keep the treatment probe running and hidden, then sample both kittys at once:

```bash
( KS_SOCK=unix:/tmp/kitty-b8-trt KS_MATCH=id:1 bash /tmp/b8/kitty-lock-sampler.sh "$P" /tmp/b8-trt-dark.tsv & \
  bash /tmp/b8/kitty-lock-sampler.sh 853 /tmp/b8-853-dark.tsv & wait ) &
pmset displaysleepnow            # displays off; leave for >= 20 min; unlock on return
```

Then compare the two TSVs row by row, and check 853's adapter state with the O2 command:

| 853 (no key, napped) | probe (key, not napped) | Reading |
|---|---|---|
| rc 124 | rc 0 | App Nap is the cause and the key fixes it |
| rc 124 | rc 124 | display-off itself is the cause; the key does not cover it; report |
| rc 0 | rc 0 | focal display-off naps are harmless at this load, as on 10-18 |

Stop the samplers with `kill %1` (or close the pane), then `kill "$P"`.

**O4. At the next kitty start, whatever triggers it.**

An unplanned start (reboot or crash) needs only the post-start checks.

For a planned restart:

```bash
defaults read net.kovidgoyal.kitty NSAppSleepDisabled          # 1 (re-run O2 if a cask zap removed it)
# exactly ONE main kitty: close the ~/kitty-pr3 dev kitty first, or cc-restore refuses (exit 3)
ps -axo pid=,args= | awk '{ n = split($2, a, "/"); if (a[n] == "kitty" && $0 !~ /--instance-group/ && $3 !~ /^\+/) print }'
cc-lr status                                                      # read-only: no record mid-actuation; an
                                                                  # actuator working a pane dies with kitty
~/.claude/bin/cc-restore --restart-kitty --dry-run                # expect verdict=DRY-RUN-OK
```

Optional build step (decision D-B8-2, §10). Do it as the **last** step before the restart, so a 0.49.2
`kitten` never talks to the running 0.48.2 kitty for long [H: version skew untested]:

```bash
ditto /Applications/kitty.app /Applications/kitty.app.stock       # rollback copy; not a .app name, so LaunchServices ignores it
brew upgrade --cask kitty                                         # 0.48.2 -> 0.49.2; the cask has no uninstall-quit stanza
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' /Applications/kitty.app/Contents/Info.plist   # 0.49.2
codesign -dv /Applications/kitty.app 2>&1 | grep -E 'TeamIdentifier|Signature='                            # NTY7FVCEKP; not adhoc
```

Then restart:

```bash
~/.claude/bin/cc-restore --restart-kitty --confirm <main kitty pid>
```

Expect it to sit at the restore start gate for up to 600 s under load (bounded, §1.8), then restore.

Post-start verification (green = all four):

```bash
NEW=$(ps -axo pid=,args= | awk '$2 == "/Applications/kitty.app/Contents/MacOS/kitty" { print $1 }'); echo "$NEW"
python3 -I ~/Development/claude-infrastructure/scripts/limit-recover/lr_recon/band.py "$NEW"      # 31
log show --style compact --last 20m --predicate "process == \"runningboardd\" AND eventMessage CONTAINS \":$NEW]\" AND eventMessage CONTAINS \"AppNap adapter\"" \
  | grep -c 'AppNap adapter assertion" ID'                                                          # 0 (853 today: >= 1)
ps -axo ppid=,stat= | awk -v k="$NEW" '$1 == k && $2 ~ /^Z/' | wc -l                                  # 0, and still 0 after
                                                                                                    # closing a pane (0.49.2 only)
```

Once K1 lands, `bash ~/.claude/scripts/kitty-hygiene.sh status` replaces the first three lines.

**O5. The first nights after adoption: verify under the load that causes the harm** (rule "Verify a cure
under its load", `situational.md:83`).

Before leaving, in a kitty pane, start `bash /tmp/b8/kitty-lock-sampler.sh "$NEW" ~/kitty-lock-$(date +%F).tsv`,
or K1's `sample` verb once it has landed. B6's `box.kitty` row gives the same band reading permanently.

Pass criteria:
- every row with `locked=1` or `front=loginwindow` has `kitty_base` ≥ 31 and `rc_rc` 0;
- `load1` in those rows is ≥ 150 (15/core), so the load was present;
- `kitty-hygiene.sh naps --since '<start>'` → NO-ADAPTER.

**On at least one night, leave another app (for example Dia) frontmost when walking away.** That is the
at-risk configuration (not focal at lock), and the only real test of the class.

**O6. When kitty 0.50.0 is released** (it carries #10632): repeat O4's build step and restart. The key
survives, because an upgrade does not zap.

**Rollback.**
- **Key:** `defaults delete net.kovidgoyal.kitty NSAppSleepDisabled`, effective at the next start.
- **Cask:** `bash ~/.claude/scripts/kitty-build-swap.sh rollback --confirm /Applications/kitty.app`, then a
  restart.
  - It moves the live app aside and renames `kitty.app.stock` back (`cmd_rollback`, `:249-274`).
  - Because `kitty.app.staged` exists, the aside copy lands in `~/.Trash` under a `patched-` name, which is
    a misnomer but harmless.
- **Probes:** `kill <pid>`. A forgotten probe is excluded from every production census (O1 notes).

### 2.3 What an agent can build safely

**K1. `scripts/kitty-hygiene.sh` (new, read-only, bash 3.2-clean) and `scripts/lib/kitty-naps.py` (new).**

```
kitty-hygiene.sh status [--pid P]                                    # exit 0 OK · 1 WARN · 2 usage
kitty-hygiene.sh naps   [--pid P] [--since 'Y-m-d H:M:S'] [--timeout S]   # 0 NO-ADAPTER · 1 NAPPING/ENROLLED · 3 UNKNOWN
kitty-hygiene.sh sample [--pid P] [--every S] [--count N] [--out F]  # the Appendix B sampler as a verb
```

`status` prints one `key=value` line per check, then a verdict:

| Line | Source | WARN when |
|---|---|---|
| `key=on\|absent\|?` | `defaults read net.kovidgoyal.kitty NSAppSleepDisabled`. "does not exist" means `absent`; any other failure means `?` | absent or `?` |
| `adopted=yes\|pending\|n/a` | kitty start epoch (`ps -o lstart=` → `date -j -f`) against the plist mtime (`stat -f %m`) | pending |
| `band=<base>/<main-thread>` | `band.py <pid>`; `ps -M` row 2 | base < 31, or `?` |
| `fds=<n>/<soft>` | `lsof -a -d 0-65535` with a 30 s bound; soft limit `CC_KH_FD_SOFT` (256) | ≥ `CC_KH_FD_WARN` (180), the same as `CC_RESTORE_FD_MAX`, or `?` |
| `zombies=<n>` | `ps -axo ppid=,stat=` | > 0 on a version below 0.49.0 (kitty#10436) |
| `version=… team=… signature=…` | PlistBuddy; `codesign -dv` | adhoc |
| `fixes=signal:<y/n> listener:<y/n>` | version ≥ 0.49.0 / ≥ 0.50.0 | (informational) |
| `main_kitties=<n>` plus one `probe=<pid> group=<g>` line per probe | the `bin/cc-restore:137-152` rule | n ≠ 1 ("cc-restore --restart-kitty will refuse") |

- Every read is bounded. A bound that fires prints `?` and makes the verdict `WARN(unknown:<field>)`, never
  OK (P3).
- `naps` runs one bounded `log show` (default 240 s) with the O2 predicate for `:<pid>]`, then
  `kitty-naps.py`, which is the validated `/tmp/b8/parse_life.py` grown into a module. Its verdicts:

  | Verdict | Meaning | Exit |
  |---|---|---|
  | `NAPPING` | ≥ 1 adapter acquisition lacking `PreventLowPriorirtyCPU`; prints intervals with role, and totals | 1 |
  | `ENROLLED` | adapters present but none napped: the key is not in effect, the window just held no nap | 1 |
  | `NO-ADAPTER` | ≥ 1 line for the pid (a role change) and no adapter acquisition | 0 |
  | `UNKNOWN` | `log show` rc 124/137, no line for the pid at all, or the first returned line is more than 1 h after `--since` (log retention; measured: about 3 days are kept) | 3 |

  The rule "Empty vs no-surface" (`situational.md:56`) is why "no lines" must be UNKNOWN: absence of output
  is not absence of naps.

**K2. `bin/cc-restore` hooks (advisory).**

- Add `"CC_RESTORE_HYGIENE_BIN": os.path.join(SCRIPTS, "kitty-hygiene.sh")` to `DEFAULTS` (`:64-75`). This
  puts it under the harness stub guard at `:125-133`.
- In `preflight()`, after the build-status block (`:513-518`), print `hygiene:` lines. `ok` is never
  changed.
- In the worker, after "new kitty pid %d answers" (`:728`), take one `status --pid <new>` and carry
  `appnap=adopted|NOT-ADOPTED|unknown` into the final verdict line (`:832`).

**K3. `scripts/alarm-reboot-prep.sh` hook (advisory).** Next to the kitty-restart block (`:347-352`), if
`status` reports `key=absent`, print the one `defaults write` line: "this reboot is also a kitty start".
`verdict=READY` is unchanged.

**K4 (optional; needs operator approval because it runs code inside the terminal that hosts every
session): the fd-headroom watcher.**
- It is C3 P1 (`session-durability-2026-10/C3-socket-robustness.md:183-206`): a global kitty `watcher`
  whose `on_load` raises `RLIMIT_NOFILE` to 8192, plus one `watcher …` line in `config/kitty.conf`.
- It takes effect at the next start. On 0.49.2+ it also takes effect on a config reload.
- It matters only until 0.50.0 (#10632).

**K5 (a request to B6, optional).** Add `lock` (`ioreg -n Root -d1` → `CGSSessionScreenIsLocked`, 75-140 ms
per B5 M1) and `front` (`lsappinfo front`, 37-65 ms) to `box.kitty` rows, only when kitty's base is below
31. A napped reading can then be classed focal or not focal without log forensics.

### 2.4 Considered and rejected

| Option | Why not |
|---|---|
| Re-sign the staged patched build | Operator decision `891ea9e9d0f3` (no re-sign). It loses 35 TCC grants. Its talk-thread fix is superseded by 0.50.0 |
| A C patch adding `beginActivityWithOptions:` to kitty | It is a patched build, so the same decision applies. Upstreaming is an outbound step for the operator. The key does the same with no code |
| An in-process opt-out from a kitty.conf watcher via ctypes `objc_msgSend` | It cannot reach 853 (#10436, no SIGUSR1). On arm64 a wrong ctypes signature segfaults kitty and ends every session. The key is strictly better |
| `defaults write NSGlobalDomain NSAppSleepDisabled` | It wakes every background app under 15-40/core. B8 needs one app |
| Disabling the screen lock (screensaver `idleTime` 3600 s) | A security setting. Display-off naps still happen. Not our call |
| Hammerspoon raising kitty before a lock | A hack. Focal naps still happen, and 10-17 was focal |
| `taskpolicy -B -p <kitty>` | Re-applied by RunningBoard at each transition [H]. It signals a production process. Diagnostic only |
| A dedicated kitty restart now | Costs about 32 windows and at least 600 s of restore gate for a class that hit 0 of the 6 queried locks and display-offs this week. The next natural start costs B8 nothing |

---

## 3. Exact changes

### 3.1 `scripts/kitty-hygiene.sh` (new, about 200 lines)

```bash
#!/bin/bash
# kitty-hygiene.sh — READ-ONLY kitty hygiene for limit-recover (REPORT B8; impl/B8-kitty-hygiene.md).
# Never writes a setting, never signals, launches or upgrades kitty (tests/kitty-hygiene.bats T9).
set -u
DOMAIN=net.kovidgoyal.kitty
HERE="$(cd "$(dirname "$(readlink "${BASH_SOURCE[0]}" || echo "${BASH_SOURCE[0]}")")" && pwd)"
DEFAULTS="${CC_KH_DEFAULTS_BIN:-/usr/bin/defaults}"; PS="${CC_KH_PS_BIN:-/bin/ps}"
LSOF="${CC_KH_LSOF_BIN:-/usr/sbin/lsof}";           LOG="${CC_KH_LOG_BIN:-/usr/bin/log}"
BAND="${CC_KH_BAND_PY:-$HERE/limit-recover/lr_recon/band.py}"; NAPS="${CC_KH_NAPS_PY:-$HERE/lib/kitty-naps.py}"
PLIST="${CC_KH_PLIST:-$HOME/Library/Preferences/$DOMAIN.plist}"; APP="${CC_KITTY_APP:-/Applications/kitty.app}"
FD_SOFT="${CC_KH_FD_SOFT:-256}"; FD_WARN="${CC_KH_FD_WARN:-180}"; TO="${CC_KH_TIMEOUT_BIN:-timeout}"
warn=""; addw() { warn="${warn:+$warn,}$1"; }

main_kitties() {   # the bin/cc-restore:137-152 rule; prints "pid" per main kitty, "probe pid group" per probe
  "$TO" 10 "$PS" -axo pid=,args= 2>/dev/null | awk '{ n = split($2, a, "/"); if (a[n] != "kitty") next
    if ($3 ~ /^\+/) next
    if (match($0, /--instance-group[ =][^ ]+/)) { print "probe", $1, substr($0, RSTART + 17, RLENGTH - 17); next }
    print $1 }'
}
key_state() {
  local out rc; out="$("$TO" 10 "$DEFAULTS" read "$DOMAIN" NSAppSleepDisabled 2>&1)"; rc=$?
  [ $rc = 0 ] && [ "$out" = 1 ] && { echo on; return; }
  case "$out" in *"does not exist"*) echo absent ;; *) echo '?' ;; esac
}
start_epoch() {    # kitty's start epoch, or empty
  LC_ALL=C /bin/date -j -f '%a %b %d %T %Y' "$("$TO" 10 "$PS" -p "$1" -o lstart= 2>/dev/null | sed 's/  */ /g;s/^ //')" +%s 2>/dev/null
}
cmd_status() { …one line per row of the §2.3 table; the verdict line is "verdict=OK" or "verdict=WARN(<warn>)"…; [ -z "$warn" ] }
cmd_naps()   { …"$TO" "${S:-240}" "$LOG" show --style compact --start "$since" --predicate "$pred" > "$tmp"; rc=$?
               [ $rc = 124 ] || [ $rc = 137 ] && { echo "naps=UNKNOWN (log show passed its ${S:-240}s bound; narrow --since)"; exit 3; }
               /usr/bin/python3 -I "$NAPS" "$tmp" --pid "$pid" --since "$since" ; exit $? }
cmd_sample() { …Appendix B, with --every/--count/--out… }
case "${1:-}" in status|naps|sample) c="$1"; shift; "cmd_$c" "$@" ;; *) echo "usage: …" >&2; exit 2 ;; esac
```

### 3.2 `scripts/lib/kitty-naps.py` (new, about 110 lines)

This is `/tmp/b8/parse_life.py` (validated against the incident capture: 5 intervals, 990 s, of which 277 s
were not focal), plus:
- `--pid` filtering, so an `anon<kitty>(501):<pid>]` line also matches;
- the verdict rules of §2.3;
- a coverage check: the first line's timestamp against `--since`;
- `--json` output for B6 and B1.

### 3.3 `bin/cc-restore` (about 20 lines)

```diff
@@ DEFAULTS = {   (:64-75)
     "CC_RESTORE_LAYOUT_BIN": os.path.join(BIN, "cc-resume-layout.sh"),
+    "CC_RESTORE_HYGIENE_BIN": os.path.join(SCRIPTS, "kitty-hygiene.sh"),
 }
@@ def preflight(confirm=None, need_one=True):   after the build-status block (:513-518)
+    # B8: advisory. kitty reads NSAppSleepDisabled at start, so say so BEFORE the restart; never fails preflight.
+    hp = str(mk[0][0]) if len(mk) == 1 else "0"
+    hrc, hout, herr = sh([seam("CC_RESTORE_HYGIENE_BIN"), "status", "--pid", hp], timeout=90)
+    for ln in (hout + herr).splitlines():
+        say("  hygiene: " + ln)
+    if "key=absent" in hout:
+        say("  hygiene: the NEW kitty will App Nap; first run: defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES")
@@ Worker, after say("new kitty pid %d answers on %s" ...)   (:728)
+                    self.appnap = hygiene_appnap(pid)     # "adopted" / "NOT-ADOPTED" / "unknown"; never raises
@@ final verdict (:832)
-        say("cc-restore: verdict=%s restored=%d/%d maybe=%d dup=%d shed=%d events=%s" %
+        say("cc-restore: verdict=%s restored=%d/%d maybe=%d dup=%d shed=%d appnap=%s events=%s" %
```

Also update the usage docstring's seam list (`:39-46`).

### 3.4 `scripts/alarm-reboot-prep.sh` (about 6 lines, after `:352`)

```bash
# B8: the reboot is also a kitty start, and kitty reads NSAppSleepDisabled at start (advisory).
if [ "${CC_KITTY_HYGIENE:-on}" != off ] && \
   "${CC_REBOOT_PREP_HYGIENE_BIN:-$HOME/.claude/scripts/kitty-hygiene.sh}" status 2>/dev/null | grep -q '^key=absent'; then
  echo "  Before rebooting (it is also a kitty start): defaults write net.kovidgoyal.kitty NSAppSleepDisabled -bool YES"
fi
```

### 3.5 Tests (new or changed)

- `tests/kitty-hygiene.bats` (new);
- `tests/cc-restore.bats`: setup gains `export CC_RESTORE_HYGIENE_BIN="$T/hygiene"` with a stub next to
  `:94`, plus 2 tests;
- `tests/alarm-reboot-prep.bats`: 1 test;
- fixtures `tests/fixtures/kitty-naps/*.txt`, which are real RunningBoard lines from `/tmp/b8-rb-*.txt`
  trimmed to the kitty pid.

### 3.6 Not changed

- the reconciler (`lr_recon`) and the move lane;
- `classify.py`: A3's TRANSIENT classes at `:34` already absorb short non-focal naps;
- `kitty-build-swap.sh`;
- `boot-resume.sh`: the `:452` wording is flagged in §10 R8 for its owner.

---

## 4. Data and format changes

- **No new persistent state.**
  - `status` reads the plist mtime as the key's write time.
  - `sample` writes only the `--out` file the operator names (TSV; the header is in Appendix B).
  - `naps` writes a temporary file under `$TMPDIR`.
- **`cc-restore`'s final verdict line gains `appnap=`.** Readers of that line: `bin/cc-restore --compare`
  does not parse it (`:1013` prints its own line). A grep for `verdict=` still matches.
- **The key** lives in `~/Library/Preferences/net.kovidgoyal.kitty.plist`, created by O2 (the domain does
  not exist today, row 7). The cask's `zap` trashes it (§1.6).

---

## 5. Failure modes under permanent 15-40/core load

| # | Failure | Handling |
|---|---|---|
| F1 | `log show` is slow (60-270 s per query at load 230-270 [M]; one hit 270 s) | `naps` is bounded (240 s by default). rc 124/137 gives **UNKNOWN** with exit 3 and a hint to narrow `--since`. It is never NO-ADAPTER. Run it from a priority-31 shell |
| F2 | Log retention has rolled past `--since` | The coverage check: if the first returned line is more than 1 h after `--since`, the result is UNKNOWN with the coverage start printed. Measured: 3 days were still available |
| F3 | `lsof` or `ps` stall | 30 s and 10 s bounds. The result is `?` and `WARN(unknown:…)`, never OK |
| F4 | `band.py` cannot read the pid (the kitty exited) | `band=?`, so WARN |
| F5 | The key is written but kitty does not restart for days | `adopted=pending` stays WARN, which is honest. B6's `box.kitty` shows any napped reading meanwhile. A3 keeps retrying kitty-latency holds (TRANSIENT, ≤ 300 s, `classify.py:18,34`) |
| F6 | The key disappears (`brew uninstall --zap`, a profile, a migration) | K2 and K3 print `key=absent` at the next restart or reboot prep, along with the one-line fix |
| F7 | The key has no effect on kitty (O3 red) | B8's key path stops there. Record the measurement. The class falls back to A3 retries and B5/C2 (less kitty on the critical path) |
| F8 | Focal display-off deafness (10-17) is not App Nap (O3b, row 2) | The key does not cover it. Record it. B5 and C2 are then the levers |
| F9 | A planned restart runs under load | The restore start gate waits at most 600 s (`boot-resume.sh:957`), then restores. An LR actuator that is mid-pane dies with its pane; its record re-drives through A3/A6. O4's `cc-lr status` check reduces that |
| F10 | Two main kitties (the `kitty-pr3` dev kitty) | `status` prints `main_kitties=2` as a WARN with the cause. The operator closes the dev kitty. `cc-restore` refuses safely (exit 3) in any case |
| F11 | A probe kitty is left running | It is excluded from `main_kitties`, sockets and the heartbeat (O1 notes). `status` lists it as `probe=<pid>`. Cost: 16-180 MB RSS (41475: 70 MB [M]) |
| F12 | Version skew after a cask upgrade, before the restart | O4 puts the upgrade last, immediately before `--confirm`. The restart's own `kitten` calls go to the new kitty |
| F13 | The hygiene script is missing or broken during a restore | `sh()` returns rc ≠ 0 and output is printed as `hygiene: …`. `ok` is untouched (P4). Unit test T11 |
| F14 | The sampler's own cost at priority 31 | One `kitten` round trip (76-375 ms [M]), two `ps`, one `lsof` (about 0.1 s [M, C3]) per 60 s. Negligible |

---

## 6. Test plan

**Unit tests** (`tests/kitty-hygiene.bats`; every binary is a stub; run under `/bin/bash` 3.2 per the rule
"Deployment interpreter ≠ yours"):

| T | Case | Expected | Red before the fix / what it guards |
|---|---|---|---|
| T1 | `defaults` stub prints "does not exist" | `key=absent`, `verdict=WARN(key)`, exit 1 | Red: today's live state (row 7) |
| T2 | `defaults` stub exits 1 with a cfprefsd error | `key=?`, `WARN(unknown:key)`, never OK | Mutant: "error means absent" or "error means on" turns it red |
| T3 | key on; plist mtime 1000 > kitty start 900 | `adopted=pending`, WARN | Red until the next start |
| T4 | key on; mtime 900 < start 1000 | `adopted=yes`, `verdict=OK` | Green arm |
| T5 | `band` stub prints 4; prints `?` | WARN(napped-now); WARN(unknown:band) | Red: kitty 41475's real reading |
| T6 | `lsof` stub with 190 lines; `lsof` stub that sleeps past `CC_KH_LSOF_TIMEOUT_S=1` | WARN(fds); `fds=?` WARN | Mutant: an unbounded `lsof` hangs the test |
| T7 | `ps` fixture: 853 plus a `--config=NONE` dev kitty | `main_kitties=2` WARN; a `--instance-group b8-ctl` probe is listed as `probe=` and not counted | Red: today's live `ps` (§1.8) |
| T8 | zombies 157 on 0.48.2; on 0.49.2 | WARN(signals, kitty#10436); not WARN | |
| T9 | every verb, with the `defaults`, `kill`, `open` and `brew` stubs logging argv | no `write`, `delete`, `kill`, `open` or `brew` ever logged | P5 guard. Mutant: adding a `defaults write` turns it red |
| T10 | `naps` with fixture A (incident: 853, 22:56:05-23:08:41 CDT) | NAPPING, 713 s focal, exit 1 | Red: production today |
| T10b | fixture B (role lines only, Dia-like) | NO-ADAPTER, exit 0 | Green |
| T10c | an empty capture; `log` stub rc 124 | UNKNOWN, exit 3 (not NO-ADAPTER) | "Empty vs no-surface" |
| T10d | first line 3 h after `--since` | UNKNOWN (coverage) | |
| T10e | adapters with the full Prevent set only | ENROLLED, exit 1 | |

**Hook tests:**
- T11 (`cc-restore.bats`): the hygiene stub exits 1 and prints `key=absent`. The dry run still ends
  `verdict=DRY-RUN-OK`, prints the `defaults write` hint, and the stub is called with `status --pid`.
  - Mutation guard: a version where hygiene WARN sets `ok=False` must turn this test red.
  - Also: every existing `cc-restore.bats` test still passes. Without the new export in setup the harness
    guard REFUSES them all; that is the control for the setup change.
- T12 (`alarm-reboot-prep.bats`): `key=absent` prints the hint and leaves `verdict=READY`. With
  `CC_KITTY_HYGIENE=off` it prints nothing.

**Integration and live checks (red first):**
- **L1, production red now:** `kitty-hygiene.sh naps --pid 853 --since '2026-10-18 19:40:00'` → NAPPING (≥18
  intervals; prototype measured 18 [M]).
- **L2, operator A/B (O1 control → O3 treatment):** the control probe reaches base 4 with ≥1 adapter
  acquisition. The treatment probe stays at base ≥31 with 0 acquisitions. Same box, minutes apart, `load1`
  recorded in every row. If the control does not go red, the A/B has no power (P2).
- **L3, production green:** after the next kitty start with the key, `naps --pid <new>` → NO-ADAPTER and
  `status` → `adopted=yes`.
- **L4, under the causing load (O5):** rows with `locked=1` and `load1` ≥ 150 show base ≥ 31 and `rc_rc` 0.
  At least one such night has a non-kitty app frontmost at lock.
- **L5 (B1, optional):** the harness's `kitty-napped` bins. O1's hidden probe is a deliberate way to produce
  a napped kitty for B1's fault matrix.

---

## 7. Rollout and kill switches

1. **Operator, now:** O0, then O1 → O2 → O3, optionally O3b (about 15 min, plus 20 min away for O3b). No
   production window is touched.
   - **Kill switch for the key:** `defaults delete net.kovidgoyal.kitty NSAppSleepDisabled`.
2. **Agent:** K1-K3 land through the project-local `/ship`. They are read-only and advisory, so landing
   changes no behaviour except output lines.
   - **Kill switches:** `CC_KITTY_HYGIENE=off` (K3); for K2, point `CC_RESTORE_HYGIENE_BIN` at `/usr/bin/true`;
     or delete `scripts/kitty-hygiene.sh` (K2 then prints "hygiene: unavailable").
3. **The next kitty start** (natural or planned): O4, with D-B8-2 deciding whether it is also the 0.49.2
   upgrade.
   - **Kill switch for the cask:** `kitty-build-swap.sh rollback --confirm /Applications/kitty.app` and a
     restart.
4. **The nights after:** O5. B6's `box.kitty` takes over permanent monitoring once B6 lands.
5. **0.50.0:** O6.
6. **Optional:** K4 after operator approval. To roll it back, remove the `watcher` line; that applies at the
   next start, or at the next reload on 0.49.2+.

---

## 8. Estimated size [E, from the sketches above]

| Part | Lines |
|---|---|
| `scripts/kitty-hygiene.sh` | about 200 |
| `scripts/lib/kitty-naps.py` | about 110 |
| `bin/cc-restore` | about 20 |
| `scripts/alarm-reboot-prep.sh` | about 6 |
| `tests/kitty-hygiene.bats` | about 170 |
| `cc-restore.bats` and `alarm-reboot-prep.bats` additions | about 45 |
| fixtures | about 60 |
| **Total** | **about 610 (about 336 non-test)** |
| K4, optional | about 20 code, 1 config line, about 30 tests |

---

## 9. Dependencies on other items

| Item | Relation |
|---|---|
| B6-telemetry | **Soft; the permanent instrument.** B6's `box.kitty` (task and main-thread base every 60-300 s, overnight included; `B6-telemetry.md:144,801`) is how B8 stays verified after O5. K5 asks B6 for optional `lock` and `front` fields. B6 must **not** adopt kitty's "Broken pipe" count as a nap detector (§1.5) |
| B5-kitty-off-critical-path | Complementary. B8 cuts how often kitty goes deaf; B5 limits what it costs. B5's residual R2 and F16 name B8 as their fix (`B5-…md:504-506,576`). If O3 or O3b goes red, B5 becomes the main lever |
| C2-socket-prompt | Complementary (kitty-free delivery of the owed prompt) |
| G2-self-recovery | Soft. A priority-4 kitty fails every lane, G2 included (`G2-…md:770,995`) |
| B1-load-harness | Soft. B1 bins `kitty-napped` rows (`B1-…md:127,589`). O1's probe recipe gives B1 a deliberate napped-kitty fault arm |
| A6-restart-safety | No code coupling. A *kitty* restart, unlike a daemon restart, kills any actuator mid-pane. O4's `cc-lr status` check covers it |
| A3 (landed, `9316d9842`) | Already absorbs short non-focal naps: kitty-latency holds are TRANSIENT with backoff ≤ 300 s |
| B2, B3, B4, B7, A7, D1, D2, C1 | None |

---

## 10. Risks, decisions and open questions

**Operator decisions:**
- **D-B8-1:** run O1-O3 and write the key. Recommended. It costs minutes and no windows.
- **D-B8-2:** take the official cask 0.49.2 at the next kitty start.
  - For: the #10436 signal fix (zombies, SIGUSR1 reload, graceful quit). Same Developer ID team, so every
    TCC grant is kept. It is LOAD_ROOT_CAUSE X14 "Path A" (`docs/research/load-root-cause-2026-10-17/DESIGN.md:239`).
  - Against: the repo's kitty tooling has never run against 0.49.x (R7).
- **D-B8-3:** approve or decline K4, the in-kitty fd watcher.

**Risks:**
- **R1.** The key's effect on kitty is inferred from Dia (§1.3). O1/O3 measures it.
- **R2.** The 10-17 deaf focal nap is unexplained. The key may not cover display-off deafness. O3b measures
  it.
- **R3.** The harmful configuration (not focal at lock) occurred in 0 of the 6 queried locks and display-offs since 10-17 [M]; 10-01 is
  the one case on record. B8 is insurance: its expected effect on an average night is small, and the
  worst-case night it prevents is RC blinded for hours plus talk-thread death on 0.48.2/0.49.x.
- **R4.** A cask zap erases the key (F6).
- **R5.** Version skew if the cask is upgraded early (F12).
- **R6.** O3b turns the displays off and locks the screen. That is the operator's action, at their
  convenience.
- **R7.** 0.49.2 compatibility with the repo's `kitten @` consumers is unmeasured. The rollback copy and
  `kitty-build-swap.sh rollback` bound it.
- **R8.** `boot-resume.sh:452` tells the operator to wait for load to fall before a deaf-kitty restart,
  which contradicts the operator premise. The gate itself is bounded at 600 s. Flagged for the restore
  owner.

**Open questions, each with the step that answers it:**
- **Q1.** Is the key read live? (O2)
- **Q2.** What is kitty's base priority during a *focal* nap? It is unmeasured; the RC evidence says it kept
  answering in 3 of 4 episodes. (O5 sampler, or B6)
- **Q3.** What deafened kitty on 10-17? (O3b)
- **Q4.** What is kitty's exact soft fd limit? (`launchctl limit maxfiles`, operator; or K4 makes it moot)

---

## Appendix A. Commands run

All read-only, or writing only under `/tmp/b8/` and `/tmp/b8-*.txt`.

| Command | Established |
|---|---|
| `date -u; sysctl -n vm.loadavg hw.ncpu` | 18:00:06Z, load1 271.88, 10 cores |
| `ps -axo pid,ppid,pri,nice,stat,lstart,etime,rss,comm \| grep -i kitty`; `ps -M -p 853`; `ps -M -p 41475` | §1.1 rows 1, 2, 4 |
| `python3 -I scripts/limit-recover/lr_recon/band.py <pid>` for 853, 41475, 1125, 1037 | 31, 4, 4, 31 |
| `lsappinfo front`; `lsappinfo info -app 853`, `-app 41475`, `-all -app 853` | bundle IDs, launch facts |
| `defaults read net.kovidgoyal.kitty [NSAppSleepDisabled]`; `defaults read -g NSAppSleepDisabled`; `defaults find NSAppSleepDisabled` | the key is absent; only Dia and Arc set it |
| `ps -axo pid,pri,…,comm` filtered to `.app` mains | Console and WiFiAgent at 4; Dia at 55 |
| `strings`/`grep -c -a` for `still serving`, `beginActivity`, `GLFWDeferredClose`, `GLFWFsFixV2`; `codesign -dv`; `otool -L`; PlistBuddy | §1.1 row 11 |
| `pmset -g`; `pmset -g log \| grep …` | power settings; display-off/on and unlock times |
| `defaults read com.apple.screensaver`; `log show … process == "loginwindow"` (10-19 21:25-23:20, 22:56-23:10 CDT) | 3600 s idle → lock at 22:56:04 CDT |
| `log show … process == "runningboardd" AND eventMessage CONTAINS ":<pid>]"` over 10-17 (44163), 10-18 AM (44163), 10-18 19:40 → 10-19 13:01 (853; rc 124 at its 270 s bound), 10-18 21:50-22:20, 10-19 21:25-23:20, the last 40 min (41475), Dia 10-19 22:50-23:12 | §1.2-§1.4 |
| `python3 -I /tmp/b8/parse_life.py <capture>` | nap intervals and roles |
| `log show … processID == <kitty> AND eventMessage CONTAINS "peer socket failed"` over 10-17, 10-18 and 10-19 windows; line-count retention checks | 0 lines; retention confirmed |
| python reads of `~/.reso/load.jsonl`, `~/.claude/logs/handoffs.jsonl`, `~/.reso/limit-recover/recon/events.jsonl`, `recon/actlogs/{769b7294.3.A,7aae55e1.2.R,e80b61f4.2.R}.log` | §1.5 |
| `lsof -n -P -p 853 -a -d 0-65535`; `ps -axo ppid=,stat=` | 121 fds; 157 zombies |
| `sysctl kern.maxprocperuid kern.maxproc kern.maxfilesperproc` | 10666 / 16000 / 245760 |
| `brew info --cask kitty`; `brew list --cask`; Caskroom metadata | cask 0.48.2, 0.49.2 available |
| `curl -sL` of upstream `docs/changelog.rst` and `formulae.brew.sh/api/cask/kitty.json` (into `/tmp/b8/dl/`) | §1.6 |
| WebFetch: Apple App Nap guide; GitHub releases and commit f3fdc21850. WebSearch: NSAppSleepDisabled sources | §1.2, §1.3, §1.6 |
| `man taskpolicy` | `-B` moves a process out of PRIO_DARWIN_BG |
| An inline python replay of `bin/cc-restore:137-152` over live `ps` | 2 main kitties |
| `KS_N=1 bash /tmp/b8/kitty-lock-sampler.sh 853 …` (×3) and `… 41475 …`; `/bin/bash -n` on it | the sampler is validated, bash 3.2 parse ok |
| `sed`/`grep`/`git show`/`git log -S` over the cited files | line numbers and commit times |
| `.claude/rules/*.md` read | rules cited inline |

## Appendix B. The overnight sampler (validated; `/tmp/b8/kitty-lock-sampler.sh`)

Measured output from three one-shot rows (`KS_N=1`) at load1 164-175:
- 853 (frontmost): base 31, `46T`/`47T`, rc 0, 76-375 ms, 121 fds;
- 853 with Dia frontmost (kitty visible but not focal): base 31, `46T`;
- 41475 (napped, not focal): base 4, `4T`, 5 threads at 4.

```bash
#!/usr/bin/env bash
# kitty-lock-sampler.sh — one row per interval: screen-lock flag, frontmost app, a kitty's base band,
# its main thread's priority, a remote-control round trip, its fd count and load1. READ-ONLY.
#   usage: bash kitty-lock-sampler.sh <kitty-pid> [out.tsv]
#   env:   KS_SOCK (unix:/tmp/kitty-<pid>)  KS_MATCH (id:$KITTY_WINDOW_ID, else id:1)  KS_EVERY (60)  KS_N (0 = until the pid exits)
# rc_rc: 0 = kitty answered · 124 = our 12 s bound fired (unknown, never "dead") · other = error
set -u
KPID="${1:?usage: kitty-lock-sampler.sh <kitty-pid> [out.tsv]}"; OUT="${2:-/tmp/kitty-lock-samples.tsv}"
SOCK="${KS_SOCK:-unix:/tmp/kitty-$KPID}"; MATCH="${KS_MATCH:-id:${KITTY_WINDOW_ID:-1}}"
EVERY="${KS_EVERY:-60}"; N="${KS_N:-0}"
BAND="${KS_BAND_PY:-$HOME/Development/claude-infrastructure/scripts/limit-recover/lr_recon/band.py}"
KITTEN="${KS_KITTEN:-/Applications/kitty.app/Contents/MacOS/kitten}"
ms() { /usr/bin/python3 -I -c 'import time; print(int(time.time() * 1000))'; }
[ -s "$OUT" ] || printf 'ts\tpid\tlocked\tfront\tkitty_base\tmain_thr_pri\tthreads_at_4\trc_rc\trtt_ms\tfds\tload1\n' > "$OUT"
i=0
while kill -0 "$KPID" 2>/dev/null; do
  ts="$(date -u +%FT%TZ)"
  if ioreg -n Root -d1 2>/dev/null | grep -q '"CGSSessionScreenIsLocked"=Yes'; then locked=1; else locked=0; fi
  front="$(lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | sed -n 's/.*"LSDisplayName"="\(.*\)".*/\1/p')"
  base="$(/usr/bin/python3 -I "$BAND" "$KPID" 2>/dev/null)"
  thr="$(ps -M -p "$KPID" 2>/dev/null | awk 'NR == 2 { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+[A-Z]?$/ && $(i-1) ~ /^[A-Z+<]+$/) { print $i; exit } }')"
  n4="$(ps -M -p "$KPID" 2>/dev/null | awk 'NR > 1' | grep -c -E '[[:space:]]4T[[:space:]]')"
  t0="$(ms)"; timeout 12 "$KITTEN" @ --to "$SOCK" ls --match "$MATCH" >/dev/null 2>&1; rc=$?; t1="$(ms)"
  fds="$(timeout 30 lsof -n -P -p "$KPID" -a -d 0-65535 2>/dev/null | awk 'NR > 1' | wc -l | tr -d ' ')"
  l1="$(sysctl -n vm.loadavg | awk '{ print $2 }')"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$ts" "$KPID" "$locked" "${front:-?}" "${base:-?}" \
    "${thr:-?}" "$n4" "$rc" "$((t1 - t0))" "${fds:-?}" "$l1" >> "$OUT"
  i=$((i + 1)); [ "$N" -gt 0 ] && [ "$i" -ge "$N" ] && break
  sleep "$EVERY"
done
```

---

## Review — efficacy-under-permanent-load

An adversarial review. The question: does B8 bound recovery time at 15-40/core with every lane at PRI 31, and does any wait, bound or gate it adds or relies on assume load falls?

The review was read-only, 2026-10-20 18:45-19:05Z, with load1 between 185 and 216 (`sysctl -n vm.loadavg`). My shell was at PRI 31 (`ps -o pri= -p $$` → 31). I wrote only under `/tmp/b8rev/`. I signalled no process, ran no `kitten @` call and no `launchctl`, and did not run O1-O3; those are operator steps. Labels are as in the design: [M] measured, [E] estimated, [H] hypothesis.

**Verdict: NEEDS-CHANGES. Adjusted conviction: 50%** (the design says 65%).

O0-O3 are sound and cheap. The key is plausibly the right lever. As written, though, the design has four problems:
- its main verification instrument gives a measured false green;
- its whole-night forensics can never finish at the premise load;
- the only fix it ships has no time bound to take effect, although a no-restart path exists;
- its restart path carries a hazard that turns a planned restart into a full kitty outage, plus a load gate that runs once per round.

### What holds [M]

- **No gate is added to the recovery rail.** Nothing in K1-K5 reads the load average, so G1 is intact.
- **A nap is per process.**
  - At 18:49:47Z, the napped dev kitty 41475 read PRI 4 while its children (42565, 42568, 42574, 42579) read PRI 31.
  - All 33 live children of kitty 853 read 31.
  - Command: `ps -axo pid,ppid,pri,…`.
  - So the sampler, run from a pane, keeps its band, and so do the sessions. Their pty drain does not (see E-10).
- **Citations re-read and correct:**
  - `bin/cc-restore`: :39-46, :64-75, :125-133, :137-152, :189 (`CC_RESTORE_FD_MAX` 180), :498-523, :513-518, :728, :832.
  - `scripts/boot-resume.sh`: :452, :956-969, :1245-1250.
  - `observe.py:205-207`, `bin/cc-kitty-socket:78-79`, `alarm-reboot-prep.sh:347-352`, `bin/cc-kitty-reload:18-33`.
  - `classify.py`: `BACKOFF_S` at :18 and `BACKOFF_CAP_S` 300 at :19. The TRANSIENT set is at :33-35; the design cites :34.
  - `band.py:74-92`; the rule lines `situational.md` :8, :56, :62, :83, :124.
  - Upstream changelog: 0.49.0 at :690 with #10436 at :838; 0.50.0 `[future]` at :231 with #10632 at :482-484.
  - The latest release is v0.49.2 (`api.github.com/repos/kovidgoyal/kitty/releases/latest` → `v0.49.2 2026-10-01`).
- **Live counts at 18:55Z:** 157 zombies, and 122 fds (CHR 35, REG 30, PIPE 55, unix 2) (`lsof -n -P -p 853 -a -d 0-65535`).
- **I tested and refuted my own version-skew hypothesis.** kitty 0.48.2 refuses a client whose (major, minor) is newer than its own (`kitty/remote_control.py:217-220` at v0.48.2: "newer than this kitty instance"). But the Go kitten always sends the fixed `ProtocolVersion {0,26,0}` (`tools/cmd/at/main.go:34` and `template.go:41` at v0.49.2). No repo tool speaks the wire protocol directly (`grep -rln kitty-cmd bin scripts` → none). So a 0.49.2 `kitten` still drives 0.48.2, and F12 stands.

### Findings

**E-1. The `naps` verb's NO-ADAPTER verdict gives a false green on today's unkeyed kitty [M].**

The capture:
- `timeout 250 log show --style compact --last 30m --predicate 'process == "runningboardd" AND eventMessage CONTAINS ":853]"'` → rc 0, 1,158 lines.
- `grep -c 'AppNap adapter assertion" ID'` → **0**, and `grep -c 'Acquiring assertion.*AppNap adapter'` → **0**.
- Yet `RBSStateCaptureSet Segment 24` (13:32:37 CDT) lists `identifier:637-853-453725 … explanation:"AppNap adapter assertion" active … doms:com.apple.appnap:Enable,…:Inactive,…:PreventLowPriorirtyCPU…`. Kitty is enrolled and holds its adapter.
- The design's own parser prototype, `python3 -I /tmp/b8/parse_life.py`, on that capture returns `intervals=0 napped_total=0s napped_nonfocal=0s events=13`.

§2.3 says NO-ADAPTER means "≥ 1 line for the pid (a role change) and no adapter acquisition". So the verb returns NO-ADAPTER, exit 0, for 853, which has no key.

The parser counts only acquisitions, which happen at transitions. A window with no transition looks exactly like "the key works". The same flaw sits in O4's post-start check: it greps acquisitions over `--last 20m`. The restore takes at least 600 s per round (E-4), so by the time the operator runs that check, the launch can already be outside the window. This is the "Fail-safe mimics healthy" rule (`situational.md:8`).

**E-2. Whole-night `naps` queries cannot finish at the premise load [M + E].**

- A 30-minute window took **86.9 s** at load1 215.65, about 21.6 per core, from PRI 31 (the capture above).
- [E, linear in window length] The 240 s bound therefore covers about 80 minutes of log. A 12-hour night costs about 35 minutes of query.
- The design's own 17.3 h query hit its 270 s bound (§1.4).

So O5's pass criterion (`naps --since '<start>'` → NO-ADAPTER) and L1 (`naps --since '2026-10-18 19:40:00'` → NAPPING) come out UNKNOWN on every run under the premise. "Narrow `--since`" (F1) hands that wait to a human.

There is a second cost. Each query holds a PRI-31 core for 60-270 s, competing with the rail that A1 put at 31.

**E-3. A probe left running captures `cc-restore`'s relaunch, and the result is a full kitty outage [M code; H ~85% on LaunchServices].**

- `open_kitty` runs `open -a /Applications/kitty.app` with no `-n` (`bin/cc-restore:711`).
- `man open`: `-n` means "Open a new instance of the application(s) even if one is already running". Without it, `open` activates the instance that is already running.
- An O1/O3 probe is a `net.kovidgoyal.kitty` instance started through LaunchServices (`open -n -a …`). The design deliberately excludes it from `main_kitties` (`--instance-group`, `:149-152`), so preflight passes.

So `--restart-kitty` kills 853, `open -a` brings the probe to the front and launches nothing, and `wait_socket` stops with exit 5 after 60 s (`:716-731`). Every window is gone and no main kitty is running. Every lane then fails until a human notices. `--after-crash` (`:740-746`) has the same exposure.

F11 ("cost: RSS") is wrong. The exclusion that keeps a probe out of the census is exactly what hides it from preflight.

**E-4. O4 relies on a load gate that runs once per round [M].**

- `restore_start_gate` waits for load per core ≤ 6 (`boot-resume.sh:956-969`).
- It runs on every boot-resume round that admits at least one session: `n_adm` is per round (`:1161`), and the gate is at `:1248-1250`. `cc-restore.rounds()` calls boot-resume again every 30 s until the event is done (`bin/cc-restore:755-791`).
- The event closes done at its epoch + `CC_RESTORE_DEADLINE_S` 1800 s, whether or not anything was shed (`boot-resume.sh:961`).

Under the premise, each round costs the full 600 s, so gates eat most of the 1800 s. §1.8's "always costs the full 600 s" understates this, and O4's "expect up to 600 s" is wrong for any restore that needs a second round.

The bypass exists today with no code change:
- `clean_env` passes every non-`KITTY_*` variable through (`bin/cc-restore:401-407`);
- `CC_RESTORE_GATE_MAX_S=0` returns at the first reading (`:969`);
- that path is already tested (`tests/boot-resume.bats:1027`).

R8 flags only the `:452` wording, not the gate.

**E-5. The fix's time to take effect is unbounded, and the injection-point list missed one [M source].**

P1 lets everything ride "the next kitty start". Kitty 853 has been up 1 day 18 hours (`ps … etime` → `01-18:09:12`), so the class stays open for an unknown time.

The §1.8 list of runtime injection points (rule `situational.md:124`) misses the RC **`kitten`** command:
- `kitty @ kitten <path.py>` runs a custom kitten (`kitty/rc/kitten.py:12-45` at v0.48.2).
- For a `no_ui` kitten, `boss.run_kitten_with_metadata` calls `handle_result` **inside kitty's process** (`kitty/boss.py:2325-2326` at v0.48.2). No signal, window or config reload is involved, so #10436 does not block it.
- `allow_remote_control socket-only` with no password allows it (`config/kitty.conf:136,152`).
- The bundle ships `resource.so` (`ls …/kitty-extensions` → `resource.so`).

So:
- **K4's `setrlimit`, which is pure standard library, can reach 853 today** through one operator-run RC call. Nothing else in B8 protects 853 before its next start.
- The §2.4 rejection of an in-process App Nap opt-out ("It cannot reach 853") is refuted. Only its segfault-risk half still stands. That risk can be tested first on the O1 throwaway probe, which has the same binary and the same Python.
- Apple counts an `NSProcessInfo` activity as disqualifying App Nap (the guide quoted in §1.2). [H] that `beginActivityWithOptions:` via ctypes works in-process.

**E-6. K4 is not optional on 0.48.2 or 0.49.x [M source + H].**

The 10-01 permanent death was a PRI-4 (napped) main thread plus abandoned peers, each holding a kitty fd until answered (`prune_peers`), until accept hit EMFILE (C3:7-18). The design's correction (§0, "a class C reading, not App Nap evidence") is right about the 9/9 data point. But it hides that class B *caused* that class C.

Under the premise, every lane now retries our own timeouts (A3, `classify.py:19,33-35`). A3 now retries timeouts that once ended the record, so a deaf kitty plausibly piles up abandoned peers faster [H]. About 135 fds of headroom (256 − 122) is all that separates a recoverable nap from a dead talk thread that only a restart fixes.

The leading indicator is the unix-socket count, not the total fd count (2 now [M]).

**E-7. The K2 worker hook sits on the restore's critical path.**

It runs right after "answers" (`:728`), which is inside `wait_socket` and before `rounds()` (`:755`). So every restored window waits for a full `status`: `defaults` 10 s, `ps` 10 s up to three times, `lsof` 30 s, plus `band.py`, `codesign` and PlistBuddy, which the §3.1 sketch does not bound. The value it adds (`appnap=`) is only read at the verdict line (`:832`).

**E-8. The advisory hooks call the full `status`, and K3 has no outer bound.**

- K3 runs inside the capacity-alarm reboot procedure (`capacity-alarm.sh:1531` prints it) with no bound at all.
- K2's preflight hook allows 90 s. On timeout, `sh()` drops stdout (`:110-111`), so the `key=absent` hint disappears exactly when the box is loaded.
- `TO="${CC_KH_TIMEOUT_BIN:-timeout}"` assumes Homebrew is on PATH. If it is not, every read returns rc 127, which gives `key=?`, so K3's `grep '^key=absent'` never matches. The repo's resolver, `_hb_to` (`restore-heartbeat.sh:82-90`, which falls back to a perl alarm), is the pattern to reuse.

**E-9. O1, O3, O3b and O5 treat our 12 s bound as a verdict.**

O5 passes only if `rc_rc 0` in every locked row, and the O3b table reads `rc 124` as "deaf". Under the premise, rc 124 means "unknown, ≥ 12 s". It is neither a pass nor a fail.

**E-10. The harm accounting looks only at remote control.**

- "Most naps were harmless" ignores B5 F16 (`B5-…md:576`): a PRI-4 main thread stops draining pty output, so hosted sessions stall [H].
- The incident's 277 s of non-focal naps were **unexposed, not harmless.** `~/.claude/logs/handoffs.jsonl` has 0 rows, and `recon/events.jsonl` has 0 kitty-class events, in 02:27:30-02:30, 02:47:30-02:50 and 02:51:30-02:55Z (python window scan) [M].
- Daytime non-focal naps are frequent: 1,570 s over 17.3 h (§1.4). That is where the key pays most often.

**E-11. #10632 does more than the design credits.**

The changelog line also fixes "a single unresponsive peer blocking all remote control communication" (`changelog.rst:482-484`). Under permanent load a starved client is the norm: the boot-resume job runs every 300 s (`StartInterval` 300) at PRI 20 (`ps`), and its heartbeat pulls the whole `kitten @ ls` tree, about 650 KB (axis 07). That adds weight to O6 [H on 0.48.2's blocking path].

**E-12. Smaller issues.**
- **`main_kitties` churns.** A sibling session (ppid 41398) is cycling `~/kitty-pr3` dev kitties. 41475 had exited by 18:55Z, and 3428 (`…/patched/kitty/launcher/kitty`) started 10 s before my read, giving `main_kitties 2 ['853', '3428']` [M]. "Close the dev kitty first" is a moving target, so `status` should name the dev kitty's parent pid.
- **The K2 preflight's `--pid 0` sentinel** gives `band.py 0` → `?`, rc 1 [M]: a spurious WARN.
- **`adopted=` from the plist mtime** turns into a false `pending` if anything rewrites the plist after kitty starts.

### Required changes

1. **Rebuild `naps` on a positive surface (E-1).**
   - Parse `RBSStateCaptureSet` entries. An `explanation:"AppNap adapter assertion"` held on the pid means **ENROLLED**, with or without an acquisition.
   - NO-ADAPTER requires both a dump in the window that lists the pid's assertions with no adapter, and a challenge line (occluded, hidden, or a role change away from focal). Anything else is UNKNOWN.
   - Add a test T10f built from this review's capture (`/tmp/b8rev/ls30.txt`): role lines plus a held adapter in a dump must give ENROLLED, never NO-ADAPTER.
2. **Make O4's post-start check, L3 and O5 challenge-based (E-1, E-9).**
   - Use `--start "<new kitty lstart>"`, not `--last 20m`.
   - Press ⌘H on the new kitty for 90 s, then require `band.py` ≥ 31 and no napped adapter (the O1/O3 recipe on production).
   - Make band under challenge (base below 31 while `front` ≠ kitty, or while `locked`=1; B6 plus K5) the primary verdict, with log forensics secondary.
3. **Bound the work of `naps`, not just its wall time (E-2).**
   - Either slice the window into chunks of 20 minutes or less, each bounded, with coverage reported per slice; or capture adapter lines live with a bounded `log stream --predicate '… "AppNap adapter" …'` from the `sample` verb overnight.
   - A partial capture that shows a napped adapter still counts as NAPPING, because it is positive evidence. UNKNOWN applies only to uncovered slices.
   - Never run `naps` inside `cc-restore`.
4. **Guard against a leftover probe capturing the relaunch (E-3).**
   - O1, O3 and O3b end with a check: `pgrep -f 'instance-group b8-'` must print nothing.
   - The O4 pre-check adds the same line.
   - K1 `status` prints `probe=` as a **WARN**: "cc-restore's `open -a` would activate this probe".
   - Rewrite F11.
   - Flag `open -n -a` at `bin/cc-restore:711` to the restore owner.
5. **Remove the per-round load gate from O4 (E-4).**
   - The restart command becomes `CC_RESTORE_GATE_MAX_S=0 ~/.claude/bin/cc-restore --restart-kitty --confirm <pid>`.
   - Correct §1.8, O4 and F9: the gate runs once per round, and the deadline is 1800 s.
   - Widen R8 to cover the gate itself.
6. **Add an operator step O2b: apply fd headroom to 853 now (E-5, E-6).**
   - Use a `no_ui` kitten that calls `resource.setrlimit(RLIMIT_NOFILE, (8192, hard))` through `kitten @ --to unix:/tmp/kitty-853 kitten <file>`.
   - Try it first on the O1 probe and read the result back with a `no_ui` `getrlimit` kitten.
   - Move K4 from optional to recommended until 0.50.0.
7. **Re-open the in-process App Nap opt-out as operator decision D-B8-4 (E-5).**
   - Correct the §2.4 row.
   - Validate it only on the O1 throwaway probe (red to green with `band.py` while hidden) before any use on 853.
8. **Add `fds_unix=` to `status` and `sample` (E-6).** It is the abandoned-peer indicator; WARN when it rises across two samples.
9. **Move K2's worker read to `finish()`, just before `:832`, or into a thread joined there (E-7).** Bound it to 20 s and read only the key and the band.
10. **Give K2's preflight and K3 a cheap verb (E-8).** Use `status --only key,main,probe`: one bounded `defaults read` and one `ps`. Bound K3 as a whole, and resolve `timeout` the way `_hb_to` does.
11. **Treat rc 124 as UNKNOWN in O1, O3, O3b and O5 (E-9).** A night counts only if the band reads ≥ 31 in every locked or non-focal row that has a band reading. Too many unknown rows make the night UNKNOWN, to be run again.
12. **Restate R3 and §1.5 (E-10, E-11).**
    - "Unexposed" replaces "harmless".
    - Count daytime non-focal naps as a benefit.
    - Cite B5 F16.
    - Record #10632's single-peer half as a reason to value O6.
13. **Fix the small issues (E-12).**
    - Leave out `--pid` when `len(mk) != 1`.
    - Name the dev kitty's parent pid in `main_kitties`.
    - Derive `adopted=` from the challenge result (item 2), not from the plist mtime alone.

---

## Review — correctness-and-safety

Adversarial review, 2026-10-20, read-only. I re-checked the design's file:line claims against `28b25a119` and
the live box (load1 196-206, `sysctl -n vm.loadavg`). I wrote only `/tmp/b8rev/` (one pipefail
reproduction). **Verdict: NEEDS-CHANGES. Adjusted conviction: 55%** (design: 65%).

**What holds.** The core plan is safe: write the key now, let it ride the next kitty start, and keep K1-K3
read-only and advisory. These citations check out:
- `bin/cc-restore:64-75`, `:108-117`, `:124-133`, `:137-152`, `:500-524`, `:832`;
- `scripts/kitty-build-swap.sh:105-113`, `:208`, `:224`, `:249-274`;
- `boot-resume.sh:452`, `:956-966`, `:1245-1250`;
- `classify.py:34`, `observe.py:204-206`, `restore-heartbeat.sh:471-475`;
- the cask JSON (no `uninstall quit`, and `zap` trashes the plist);
- the cited rule lines in `situational.md` (8, 56, 62, 83, 124).

The defects below are in the details of the operator script and the agent code. Several of them would
strand sessions, lose drafts, or turn a self-healing kitty outage into a permanent one.

### Defects, most severe first

**S1. The probe socket lands inside the production glob, and a leftover probe captures the fleet.**
- **The socket name is not what O1 assumes.** kitty appends `-{kitty_pid}` to a `listen_on` that comes
  from config, and `-o` is config (`~/kitty-pr3/base/kitty/main.py:480-482`, `:556-560`). So
  `-o listen_on=unix:/tmp/kitty-b8-ctl` creates `/tmp/kitty-b8-ctl-<pid>`.
- **That name passes `bin/cc-kitty-socket`.** Its check `pid="${s##*-}"` (`:78-79`) pulls out the numeric
  pid, and the `ucomm` check accepts it, because the probe is a kitty.
- **While a probe lives:** every `--unique` caller gets exit 5. Those are `cc-reaper:120` and `cc-pane:343`;
  the repo's own note is `cc-reaper:118-119`.
- **If a probe outlives a restart of 853:** O4 or O3b leave probes running, and F11 calls a leftover probe
  harmless. It is not. The default mode picks the *oldest* live socket (`cc-kitty-socket:90`), so the LR
  lane's resolvers start driving the hidden throwaway kitty:
  - `lr-lib.sh:1220-1235`;
  - `cc-tui.sh:68-77`;
  - `lr-handoff.sh:188-200`.

  Recovered sessions then launch into the probe. A later `kill "$P"` kills those sessions.
- **The sampler measures nothing.** `KS_SOCK=unix:/tmp/kitty-b8-ctl` does not exist, so every `rc_rc` in
  O1 and O3 reads a connect failure. O3's expected green ("`rc_rc` 0") cannot happen.
- **The repo already forbids this layout.** Rule S2 (`scripts/kitty-drag-w4.sh:26-29`, `:175-181`) says a
  sandbox kitty's socket must live outside `/tmp/kitty-*`.

**S2. The O5 overnight sampler can cause the class-C talk-thread death it is meant to watch for.**
- **Each unanswered call costs kitty an fd.** `prune_peers` frees a peer only once the main thread has
  answered it (`child-monitor.c:2374-2386`, 0.49.2 tree; axis 07 §2 for 0.48.2).
- **The sampler keeps calling during a deaf episode.** It calls RC once a minute against production and
  keeps going after rc 124, so a deaf main thread gains 1 fd per minute from the sampler alone.
- **The headroom runs out in about 2 hours.** It is about 135 fds (256 − 121), so EMFILE comes in at most
  about 135 minutes. On 0.48.2 and 0.49.x that kills the talk thread; only 0.50.0 (#10632) survives it.
- **10-17 shows what this would do.** Kitty was deaf for 4 h, then recovered with no restart. The sampler
  would have turned that into a permanent RC loss.
- **The design says the opposite.** F14 calls the sampler's cost negligible.

**S3. O2 tells the operator to put production into the harmful state.**
- The instruction "press ⌘H on [853] for 90 s now" hides production kitty. Once the nap engages (34-49 s,
  §1.2), 853 is non-focal and napped, which the design itself measures as priority 4 (§1.5). That is the
  10-01 configuration, and it would be entered on purpose with recoveries in flight.
- Q1 can be answered without touching 853: re-hide the O1 control probe, which started before the key was
  written.
- O1's own ⌘H depends on keyboard focus. If the click misses, ⌘H hides 853 instead (rule "The screen is
  global", `situational.md:122`).

**S4. K3 never prints its hint.**
- `alarm-reboot-prep.sh:57` sets `set -uo pipefail`.
- `status` exits 1 exactly when `key=absent` (T1). Under pipefail that makes the
  `status … | grep -q '^key=absent'` pipeline return 1.
- Measured with `/bin/bash` 3.2 and a stub that prints `key=absent` and exits 1: `HINT-NOT-PRINTED`.

**S5. K2 breaks an existing test.**
- `tests/cc-restore.bats:279` matches `…shed=0 events=$EVENTS/$ev`.
- §3.3 inserts `appnap=` between `shed=` and `events=`, so that test turns red. §4 and T11 say no test
  breaks.

**S6. K2's worker hook sits on the restore's critical path.**
- `:728` is inside `wait_socket()`. In a restart it runs after the old kitty is dead and before `rounds()`
  (`:702`, `:712`). It also runs in `after_crash` (`:738`).
- With `timeout=90`, an advisory read can therefore hold the relaunch of the whole fleet for up to 90 s, in
  both a planned restart and a crash restore.
- `self.appnap` is never initialised in `__init__` (`:576-586`).

**S7. Planned restart (O4) loses every unsent draft.**
- `bin/cc-restore` has no draft capture. `grep -n -i draft bin/cc-restore` returns 0 lines.
- `boot-resume.sh:1367` types drafts back only when `[ -z "$EVENT" ]`, which is never true for cc-restore's
  `--event` run.
- So O4 ends 32 panes with no draft step. The gap predates B8, but O4 is new guidance that walks the
  operator into it.

**S8. F12 is wrong: the cask upgrade does reach the old kitty.**
- cc-restore's worker waits up to `--land-wait` 600 s (`:653-666`). It then runs `hb_tick` (`:669`), which
  does `kitten @ ls` from `/Applications/kitty.app/Contents/MacOS/kitten` against the **old** kitty
  (`restore-heartbeat.sh:38`, `:149-153`). That tree is the snapshot the restore is built from.
- After `brew upgrade` the kitten is 0.49.2 talking to a 0.48.2 kitty.
- The protocol version gate passes: the kitten sends 0.26.0 (`tools/cmd/at/main.go:34`,
  `template.go:41`) and the server compares at `remote_control.py:220`.
- Payload compatibility is unmeasured [H]. On failure, the last good tree on disk is used instead.

**S9. The fd threshold in O4 compares two different counts, and the planned restart can trip it.**
- cc-restore's `fd_count` counts every `lsof -p` row (`:175-179`).
- Measured today:
  - `lsof -n -P -p 853 | wc -l` gives 208 rows, of which 86 are `txt` and 1 is `cwd`;
  - the numeric-fd count (`-a -d 0-65535`) is 121.
- So "`CC_KH_FD_WARN` 180, the same as `CC_RESTORE_FD_MAX`" is false: they measure different things.
- Consequence: a 32-window kitty is already over `fd_gate`'s 180 on any second restore round
  (`:188-194`, `:765`). The restore goes STOPPED, and the `--after-crash` continuation hits the same gate.
- This also predates B8, but O4 sends the operator into it.

**S10. Two of the design's green checks can pass on empty output.**
- **The naps check.** §2.3 runs `naps` with the O2 predicate, which includes `AND eventMessage CONTAINS
  "AppNap adapter"`. That filter removes role lines, but NO-ADAPTER requires one.
  - In production, NO-ADAPTER is therefore unreachable, and L3 can never pass.
- **The post-start check.** O4 checks the new kitty's adapter count over `--last 20m` and treats 0 as
  green. That window can easily miss the launch:
  - kitty acquires its first adapter about 33 s after launch (853: launched 19:40:35, adapter 19:41:08
    CDT, `/tmp/b8-rb-life.txt`), and after that only at transitions;
  - a restore can run 600 s of gate plus up to 2700 s (`CC_RESTORE_MAX_S`).

  So a keyless kitty reads 0 too. This is the "Empty vs no-surface" trap (`situational.md:56`). The O1 and
  O3 counts have the same problem.

**S11. `start_epoch` fails in the operator's locale.**
- With `LANG=en_CA.UTF-8`, `ps -o lstart=` prints `Sun 18 Oct 19:40:35 2026`. The `%a %b %d …` parse then
  fails ("Failed conversion", measured).
- The cause: `LC_ALL=C` in the sketch applies to `date` only, not to `ps`.
- `restore-lock.sh:43-48` already pins `TZ=UTC LC_ALL=C` for this reason.
- With the start epoch empty, `adopted` has no defined state. An implementation could fall through to
  `yes`.

**S12. Smaller correctness defects.**
- **(a) `naps` reads partial output.** Only rc 124/137 become UNKNOWN; any other non-zero `log show` rc is
  parsed. rc 137 only exists with `timeout -k`.
  - Also, `TO=timeout` ignores the repo's resolver pattern (`bin/cc-desk-page:82-87`,
    `bin/cc-inbox-guard:136-144`).
- **(b) The pid can be reused.** A `--since` earlier than the kitty's start can count another process's
  lines, because `:<pid>]` is all the filter checks.
- **(c) The coverage check fires on quiet kitties.** It is keyed on pid-filtered lines, so any quiet focal
  kitty reads UNKNOWN.
- **(d) `version` and `fixes` come from the bundle, not the running process.** After an early upgrade,
  853 would read `version=0.49.2 fixes=signal:y`, which suppresses the zombie WARN.
- **(e) T9 cannot catch the things it guards against.**
  - `kill` is a bash builtin, so a PATH stub never sees it.
  - A hard-coded `/usr/bin/defaults write` bypasses the seam.
- **(f) O3b's reading table mixes three differences.** The probe is hidden while 853 is focal, and the probe
  is idle while 853 has 32 busy panes. Row 1 cannot conclude "App Nap is the cause".
- **(g) O4's `NEW=` also matches probes.** It selects every `/Applications/kitty.app/.../kitty`, including
  probes started from the same path.
- **(h) `--pid 0` reads nothing.** It is what K2 passes when `len(mk) != 1`; `band.py 0` gives `?`
  (measured).
- **(i) K4 goes live when it lands.** Its `watcher` line is deployed by the land itself on 0.49.2+, because
  `__watch_conf__` reloads about 100 ms after a converge (`bin/cc-kitty-reload:18-33`). Approval must
  come before the land.

### Required changes
1. **Probes.**
   - Use `--listen-on unix:/tmp/b8probe/<arm>.sock`. The CLI flag gets no pid appended, and the path is
     outside `/tmp/kitty-*`.
   - Derive `KS_SOCK` from that path.
   - O4's pre-check requires that no `--instance-group b8-*` process is alive.
   - Correct F11.
2. **Sampler.**
   - After the first rc ≠ 0, stop RC calls to that kitty. Either wait until the band shows it has
     recovered, or back off, doubling the interval up to 30 min or more.
   - Hard cap of 10 or fewer unanswered calls per run.
   - RC off by default for the production kitty in K1 `sample`.
   - Rely on B6's band reads, which make no RC call.
   - Rewrite F14.
3. **Hiding.**
   - Drop "⌘H on 853" from O2. Answer Q1 by re-hiding the O1 control probe after O2.
   - Hide probes by pid, not by keyboard focus, or confirm 853 still reads base 31 after the ⌘H.
4. **K3.** Capture the `status` output, then match on it. The T12 stub must exit 1, as the real `status`
   does.
5. **K2.**
   - Put `appnap=` at the end of the verdict line.
   - Run the hook in `finish()` before `:832`, not at `:728`.
   - Initialise `self.appnap` in `__init__`.
   - Bound the hook at 30 s or less and make it never raise.
   - Skip per-pid checks when there is not exactly one main kitty, and skip the hook in `--after-crash`.
6. **O4.**
   - Capture drafts, or state plainly that every draft is lost. Flag the gap to the restore owner, with
     `boot-resume.sh:1367` and the missing capture in cc-restore.
   - Flag the fd metric mismatch at `:175-194`, or set `CC_RESTORE_FD_MAX` for the planned restart.
   - Before upgrading: wait until no `ship-land.sh` is in flight.
   - After upgrading: run `kitten @ ls` and `get-text` against the old kitty and parse the result; roll back
     if that fails.
   - On the reboot path, upgrade only after `alarm-reboot-prep.sh` has saved the drafts and the heartbeat.
   - Rewrite F12.
7. **Log checks.**
   - Run every adapter check (`naps`, O1, O3, O4) over `--start <process lstart>`, with no `AppNap
     adapter` filter.
   - Require at least one role line for the pid before reading 0 as green.
   - The default `--since` is the process start; refuse an earlier one.
   - Decide coverage with a separate retention probe that is not filtered by pid.
8. **K1 robustness.**
   - Run `ps` as `TZ=UTC LC_ALL=C ps`, and add `adopted=?` as a WARN.
   - Use the repo's timeout resolver with `-k`, and treat any rc ≠ 0 as UNKNOWN.
   - Print `version=?` WARN when the bundle is newer than the process.
   - Print both fd metrics.
   - Add a static source lint to T9, allowing `kill -0` only.
9. **Smaller fixes.**
   - O3b: add the keyless control probe as a concurrent arm, or downgrade its readings to "consistent
     with".
   - Filter `NEW=` the same way as `main_kitties`.
   - K4: approval before the land.

