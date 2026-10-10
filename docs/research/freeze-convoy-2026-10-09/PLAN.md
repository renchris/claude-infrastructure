# Freeze fix plan (2026-10-09 incident, 21:26–21:34 CDT)

File:line references marked (verified) were re-read this pass; everything else is from the dossier or the two reviews as cited.

## 1. CAUSE CHAIN

Both freezes are one stall of the user-session trust-evaluation path, about 7.5 minutes long, with two different victims.

**Shared stall**
- S1 MEASURED. At 21:26:13.874 lsd thread 0x3f7c45fc opened the registration connection for pid 55043, a `com.google.Chrome.helper`. That same thread is the database-lock holder in `/tmp/lsd.sample` at 21:32:12, 1700/1700 samples in `registerSelf`, parked in a code-signature timestamp check waiting on trustd by synchronous XPC. This corrects the dossier, which named pid 54682 at 21:29:14.
- S2 MEASURED. The user trustd's serial evaluation queue was blocked 881/881 samples at 21:33:32, waiting on the keychain daemon by synchronous XPC.
- S3 MEASURED. tccd entered a trust evaluation at 21:26:48.258 and replied at 21:34:06.467. INFERRED: it waited on that same trustd.
- S4 MEASURED. secd answered unrelated requests in milliseconds mid-stall, and a batch of older secd threads woke at 21:34:04.6–06.3. The system launchservicesd finished trust evaluations in 3–6 ms at 21:28. INFERRED: a subset of secd operations was blocked throughout. What blocked it is UNKNOWN; secd was never sampled.
- S5 MEASURED, what does not explain it:
  - Load average: no convoy at load 503, a convoy at about 197.
  - Default-band CPU: 9 of 3,458 default-band threads were runnable, and the standard band got 4.69 cores.
  - Background queue length alone: 262–427 runnable background entries with lsd at 7 threads and no convoy.
  - INFERRED and unproven: starvation of the priority-4 daemon threads on the 2 efficiency cores contributes.

**Freeze 1 (Claude TUI, about 4 min)**
1. MEASURED. Claude Code 2.1.293 calls `Bun.Image.hasClipboardImage()` synchronously on the main thread 1,000 ms after each terminal focus regain. The cooldown applies only after a positive result, and there is no switch. Ctrl+V image paste uses the same path. NOT DETERMINED: which of the two fired in pane 170.
2. MEASURED. The main thread sat 1753/1753 samples in an NSPasteboard read that makes a synchronous XPC call to lsd with no timeout.
3. MEASURED. 19 readers were queued on the lsd lock, including 6 claude sessions, some running since Oct 8. Any session can freeze, not only fresh ones.
4. The lock was held by S1.
5. MEASURED. 24 more `registerSelf` writers were queued, and 23 of 46 registrants in 13 minutes were automation Chrome family. Cold starts continued into the stall: 54682 at 21:29:14 went defunct and was relaunched as 22801 at 21:34:13. INFERRED: the relaunch was a timeout retry.
6. MEASURED. It released by itself at about 21:34:04–06.

**Freeze 2 (Hammerspoon, 264.1 s)**
1. MEASURED, to-the-second match. At 21:26:48 the notify log reads `Playing Purr.aiff for complete [e1a70544]`; the same second coreaudiod logged a TCC request for afplay 75681. The fleet's own completion chime was admitted by the HOT gate (120 s gap).
2. MEASURED. coreaudiod's client-serving thread blocked 438 s in that one synchronous TCC microphone preflight (S3).
3. MEASURED. At 21:29:42 a screenshot's clipboard copy finished in 5.8 ms. Then `pop:play()` at `hsc/screenshot/thumbnail.lua:202` (verified) ran on the main thread: 8 HAL calls timing out at 30 s each plus 24 s, 1759/1759 samples.
4. READ from Hammerspoon source, not measured. The smartpaste tap is disabled for the whole hang and the hotkeys are swallowed.
5. MEASURED. Nothing detects a hung Hammerspoon; launchd KeepAlive sees only exits.
6. MEASURED. It ended at 21:34:06 when tccd replied; coreaudiod then cleared 11 queued TCC requests in about 240 ms.

**Capacity background, in neither chain (MEASURED):** Docker used about 0.98 core for 31 h, and fseventsd used 0.9–1.5 cores until its restart at 21:37:37, which was 3.5 minutes after both freezes ended.

## 2. RANKED FIXES

Constraints from review that apply to every item: nothing new goes into the background band, no load-average gates, no waiting inside a shim, no SIGSTOP. Conviction figures are mine unless the dossier's is quoted.

**F1. Drop the Pop sound.** Reduces how OFTEN. Conviction 95.
- Repo: `/Users/chrisren/Development/hammerspoon-config` (tree clean, verified).
- Change in `hsc/screenshot/thumbnail.lua`: set `sound = false` at :23, remove the `pop` variable at :34 and `hs.sound.getByName("Pop")` at :109, remove the play line at :202, and make :232 report `sound = false`.
- Change in `hsc/screenshot/init.lua`: remove `hs.sound.getByName("Pop")` at :350. Change :428 to `sound = false`; verified, `benchMode(false)` otherwise sets `sound = true` again.
- Change in `hsc/dock.lua:12-13`: add `hs.sound` to the banned-on-timer list.
- No afplay replacement: a per-screenshot afplay is the client shape that parked coreaudiod.
- Verify: `grep -rn 'hs\.sound' init.lua hsc` shows only the ban comment. After reload and one screenshot, `log show --last 30m --predicate 'process == "Hammerspoon" AND eventMessage CONTAINS "HALC_"'` is empty, and `screenshot.log` has no thumb-shown to dismissed gap above about 3.3 s.
- Operator: yes, for the reload only. Agents may not message Hammerspoon.

**F2. No afplay while HOT.** Reduces how OFTEN. Conviction 70. Raised by both reviewers; not itself adversarially reviewed.
- Repo: claude-infrastructure, `hooks/notify.sh`, `tests/notify.bats`.
- Change: in the sound gate (the `NTY_PLAY=1` block, verified), after `NTY_HOT` is computed and before the per-class gap logic: if `NTY_HOT` is non-empty and `CC_NOTIFY_HOT_AFPLAY` is not 1, set `NTY_PLAY=0` and `NTY_GATE_WHY="hot-no-afplay ${NTY_HOT}"`, and touch no stamp. Write nothing to the `coreaudiod-hot` flag, which `scripts/coreaudiod-watch.sh` owns. After F4 lands, also treat a fresh convoy flag as HOT.
- Cost, stated: at the HOT threshold of load 40, completion chimes would have been silent all of this evening. Permission, question and plan banners keep their sound through NotificationCenter.
- Verify: the notify log shows `Gated … (hot-no-afplay load=N)` and no `Playing` lines while load is 40 or more. A `log show` for coreaudiod `TCCAccessRequest` shows none for an afplay pid while HOT.
- Operator: no to land. The close must state the audible change and the restore seam.
- Limit: NOT DETERMINED whether Hammerspoon's own play would have triggered its own blocked TCC preflight. F1 is what protects Hammerspoon; F2 stops the fleet from parking coreaudiod for every other audio client.

**F3. Upstream report on the clipboard-image hint.** Reduces how OFTEN, to zero for this path, on upstream's timeline. Dossier conviction 85 on the cause.
- One report, drafted by the lead and sent by the operator. Asks: move the pasteboard read off the main thread with a time bound; check `clipboardChangeCount` first; add a setting to disable the hint; apply the cooldown to negative results.
- Corrections to carry: say any session can block (6 queued readers, some since Oct 8), not only fresh ones. The changelog was read to 2.1.296 with no fix. Redact `/Users` paths and session ids from `/tmp/pane170-claude.sample` and `/tmp/lsd.sample`. Fold in the lsd-axis reader evidence.
- Verify: after a release with the fix, sample a session during an lsd stall; the main thread is not in NSPasteboard.

**F4. Convoy gauge: detect, capture evidence, write a flag.** Shortens how LONG indirectly, and is the precondition for F5, F8c, F9 and the root cause. Dossier conviction 85.
- Repo: claude-infrastructure. New single-shot `scripts/convoy-gauge.sh` called once per tick from `scripts/capacity-alarm.sh`, plus `tests/convoy-gauge.bats`.
- Why a call from the existing job and not a new daemon (reviewer 2's option): no operator bootstrap, `capacity-alarm` is already in the reaper allowlist at `bin/cc-reaper:725` (verified), and that job was measured alive at load 500. The price is its measured 61–138 s cadence. Promote to a 5 s daemon only if a week of rows shows late trips.
- Each tick: thread counts of the user's lsd, trustd, secd and tccd from `ps -M -p` (measured cost 0.00 s), and runnable counts per priority band from one `ps -axo state=,pri=`. Append to `~/.claude/logs/convoy-gauge.jsonl`.
- Trip: maximum thread count at or above 16, confirmed by a second read 5 s later in the same run. Clear at 8 or below. Both are env seams resting on three data points: 2–7 at rest under load 297–503, 45 in Freeze 1, 84 on 2026-10-04.
- On the trip edge: one `ps -M` and one `sample <pid> 1` each of secd, trustd, lsd and tccd into a dated directory, single-flight. This is the evidence nobody has.
- Flag: touch `$(getconf DARWIN_USER_TEMP_DIR)/cc-shed/active` every tick while tripped. Consumers ignore it when older than 300 s. That is my adjustment from the reviews' 120 s, which the writer's measured 138 s gap would make flap.
- Page: on its own transition, outside the combined verdict (which is pinned at ALARM by kalloc). While tripped, use the desk-pane rung only, with no osascript or afplay. My one grep of `bin/cc-desk-page` option cases found only `--source`, so add a desk-only mode or call `cc-notify --role desk` directly.
- Page text: the gauge numbers plus "a Claude pane can freeze about 1 s after you focus it; avoid cycling panes until the clear line". No run-queue-owner advice and no would-stop list.
- Verify: a fixture with a thread count of 45 trips, captures, flags and pages; a fixture at 7 does not; a `tests/capacity-alarm.bats` case shows the combined verdict unmoved. Live: a row every tick.
- Operator: no.

**F5. Dedicated agent-browser shim: space cold starts, cap per owner, refuse on the convoy flag.** Shortens how LONG, and modestly how OFTEN. Conviction 60. Consolidates four cap proposals, the shed-flag proposal and the skill-text proposal.
- Repo: claude-infrastructure. New `bin/cc-agent-browser` and `tests/cc-agent-browser.bats`. Remove `agent-browser` from `config/qos-shim.names` and link `$CONFIG_DIR/bin/agent-browser` to the new shim at `install.sh:1184-1188` (verified). Keep the `config/qos-batch.patterns:64` row. Check the names-to-rows pin in `tests/cc-qos-exec.bats`.
- Behavior: still exec under `taskpolicy -c utility`. Fail open on any doubt. Kill switch `CC_AGENT_BROWSER_GATE=off`, waiver env plus log. Warm commands pass with no added fork.
- A cold start is a `--session X` whose `~/.agent-browser/X.sock` is absent or whose `X.pid` fails `kill -0` (file layout verified). No pgrep.
- On a cold start only, refuse with exit 75 and never wait when any of these holds:
  - the convoy flag is fresh;
  - the last cold-start stamp is younger than N s (the timestamp-stamp pattern in `hooks/notify.sh`, no lock holder, since the shim execs);
  - the calling Claude session already owns M live daemons, counted from a sidecar the shim writes at each cold start.
- Starting values: M = 4, the dossier's figure. N = 10 s is unmeasured.
- The refusal names the caller's live sessions, the reuse and `agent-browser --session X close` commands, and the retry delay. No load term, no batch-tool refusals, no pausable-roots registry.
- `skills/agent-browser/SKILL.md:87-92` (verified, teaches one session per site): one worker-owned session name per worker, sites visited one after another inside it, close on finish. State the cost of a new session name. No `--cdp` sharing on 0.27.1.
- Verify: bats for warm pass, the three refusals and fail-open. Live: `registerSelf` frame count in one lsd sample during a crawl, before and after; no new `--remote-debugging-port` roots started inside a trip window.
- Operator: no.
- Limit, from both reviewers: it would not have prevented Freeze 1, because the lock holder was a helper of a Chrome that was already running. The gain is a shorter writer queue and no launches into a live convoy.

**F6. Hammerspoon hang watchdog, detect-first.** Shortens how LONG for hang classes not yet seen. Dossier conviction 80. Land after F1.
- Repo: hammerspoon-config. New `hsc/heartbeat.lua` (1 Hz `hs.fs.touch` of a heartbeat file in the existing state dir, `scripts/supervise.sh:38`), new `scripts/hangwatch.sh`, new `launchd/org.hammerspoon.Hammerspoon.hangwatch.plist` (10 s interval, not background band).
- Stale means: heartbeat pid equals the launchd job pid, process age over 60 s, and mtime age over 30 s on 2 consecutive runs. The 30 s is raised from 15 to match `supervise.sh:42` (verified). Keep the self-lateness check.
- On stale, permanently: one `sample` to a dated file, one JSON line, one page that fails soft.
- Kill stays off by default. When enabled, kill only if the sampled main-thread stack is not a synchronous wait on lsd, the pasteboard, coreaudiod or WindowServer; at most 1 per 10 minutes and under 3 per day. Never use `hs.ipc`.
- Verify: heartbeat mtime advances each second; compare would-kill lines against `screenshot.log` gaps during the observe period.
- Operator: yes, to install the agent and reload.

**F7. Measure, then opt in: an ad-hoc-signed browser for agent-browser.** Reduces how OFTEN if the inference holds. Dossier conviction 60; the test decides.
- First, on an idle box: through agent-browser, launch Google Chrome.app, Chrome for Testing and chrome-headless-shell 10 times each. Count lsd `modifydb` activations with their durations and launchservicesd CHECKINs. Confirm `--headless=new` is accepted and diff the renders.
- Then add `CC_AGENT_BROWSER_SHELL=on` to the F5 shim. It sets `AGENT_BROWSER_EXECUTABLE_PATH` on cold start only, through `resolve_headless_chrome` in `scripts/lib/cc-common.sh:46-80`. It becomes the default only if `modifydb` connections are zero and argv and render pass.
- Why it matters: it is the only proposal that could reach the measured holder class, a Chrome helper pinning the lsd lock during a trust stall. The trustd skip is INFERRED from signature shape. 23 of 46 registrants were not automation Chrome.
- Operator: yes, for the idle window.

**F8. Capacity recovery.** No measured link to either freeze.
- a. Operator quits Docker Desktop and leaves it off: 0 running containers, about 1 core. The dead-stdio-pipe cause is refuted (lsof shows fd 0 and 1 on `/dev/null`, fd 2 on a regular file). No deny rule. Verify: the ghost bucket in `~/.claude/logs/attrib.jsonl` falls from about 1.0 to about 0.1 core.
- b. A burner alert from `attrib.jsonl` in `scripts/capacity-alarm.sh`, as the single detector for ghost and non-session buckets including fseventsd. Separately damped (once per bucket per 6 h, window 30–60 min at 0.7 core or more, name allowlist, pid and command in the text), never a verdict rung. Acceptance: replay today's log and report how often it fires.
- c. `scripts/fseventsd-watch.sh`: add the CPU rate from `ps -o time=` deltas to the row; the verdict stays footprint-only (:153-155, verified). The CPU restart sits behind an env seam, off by default, with a 6 h cooldown, daemon age of 24 h and 3 consecutive runs. Enable it only after a week of rows and one operator-triggered restart under load shows no rise in F4's lsd count. The root copy redeploy is the operator's (`migrations/0057`).

**F9. Simulator: one operator experiment, then page-only.** The operator confirms device 87375EAB is unowned and runs `xcrun simctl shutdown 87375EAB` once, with F4 rows before and after. Only if the rows change, add `launchd_sim` age and process count to the F4 row with a page-only line. No automatic shutdown, no simctl polling. A measured counterexample exists: the same simulator was booted with no convoy.

**F10. Label fix.** `bin/cc-close-attrib:498` and `:501` (verified) hard-code "blocked in the keychain/system-CA query". Change the text to cause unknown and record the 1-minute load. pid 30683 carried that label while idle in `kevent64` with CPU advancing. Diagnostic accuracy only.

## 3. KILLED

1. Machine-wide agent-browser session cap in `bin/cc-qos-exec`: duplicate of F5, breaks that shim's fail-open contract, and one crawl would lock out the other sessions.
2. `CLAUDE_CODE_SHELL_PREFIX` utility demotion: targets a non-cause, and 17 of 20 PreToolUse hooks have 5–10 s timeouts that fail open when slowed.
3. Dedupe the fseventsd `top` and set ProcessType Background: under 0.5% of a core, and background would starve the watchdogs when they are needed.
4. LaunchServices probe by `log show`: dominated by F4's free `ps -M` read, and its signature is unvalidated.
5. Pasteboard upstream report from the lsd axis: duplicate of F3.
6. Dock launches through an async `open`: never observed; Hammerspoon's pasteboard calls took 0.3–1.05 ms with lsd wedged, and `open` waits on the same lsd.
7. Skip a chime when an afplay is stuck: acts after the damage and would have gated one play. Replaced by F2.
8. Automation Chrome cap as a PreToolUse hook: duplicate, and adds a scan to a 20-hook chain.
9. Launch watchdog for post-registration stalls: its trigger matches every idle TUI. Residue kept as F10.
10. Admission check on typed launches: keyed on load, which does not predict the freeze, and would be a permanent banner.
11. Settings-template alignment: changes nothing on this machine. Reviewer 2 would keep it as hygiene outside this plan.
12. Bound smartpaste's pasteboard read: unobserved, and the watcher adds a standing main-thread poll.
13. Lint pinning utility as the floor: unmeasurable as a build item. Kept as the constraint at the top of section 2.
14. Daemon cap in the generic shim with fall back to reuse: duplicate, and reuse silently crosses sessions' cookies.
15. Band occupancy fed to the fire gate: telemetry folded into F4; the gate half would refuse session fires for a queue that sessions do not own.
16. Restart Docker and widen the spin guard: duplicates F8a and F8b with a weaker instrument.
17. Reap the orphaned Playwright tree: 3–5% CPU, unattributed, and the repo's own scripts launch that binary.
18. SIGSTOP shed (Stage 2): stopping a client releases nothing held inside lsd, trustd or secd; it adds a second stop-and-continue actuator beside the compressor sentinel; a 120 s hold always crosses the Bash default timeout.
19. Hammerspoon watchdog from the detect-and-shed axis: duplicate of F6 and weaker. Its sample-before-kill is merged.
20. Capacity-alarm load rung change: premise false. The rung already has edges (53 ALARM entries in 1,400 rows), and OK is unreachable while kalloc is in chronic ALARM.

Parts cut from surviving proposals: the afplay replacement for Pop, the Docker deny rule, the load term and lock-holder in the shim, batch-tool refusals, automatic simulator shutdown, default-on fseventsd CPU restart, and default-on headless shell.

## 4. OPEN

1. What blocked the keychain daemon for 7.5 minutes, the root of both freezes. Settled by F4's trip-edge samples of secd, trustd, lsd and tccd at the next convoy.
2. Whether trustd's wait was CPU starvation or a network step. One `log show` of `process == "trustd"` for 21:26:00–21:31:00, while the log is still retained.
3. Whether anything ends a live convoy sooner, such as restarting the user's secd or trustd agent. Untested. An operator-only experiment at the next trip, after the capture. Until this is answered there is no evidence-backed break-glass command.
4. Whether an ad-hoc-signed browser skips the trustd hop. Settled by F7's test.
5. Who launches the registrants outside agent-browser: 15 null-bundle pids in groups of three, 3 Electron helpers queued first at 21:26:42.70, and Chrome for Testing 29499, 84091 and 96748. Run `ps -o pid,ppid,command` on `modifydb` pids as they appear in a 2-minute `log show`.
6. The single 7.2 GB shellcheck process at 21:30:15, the 1.6 GB newly compressed in 12 s, and swap going from 10.0 to 17.1 GB at 21:32–21:37. Did compressor or swap-in latency feed the stall? Read the statics batch in `scripts/ship-land.sh` (about :3493) and line up `compressor-sentinel.jsonl` rows against 21:26:13.
7. The keychain traffic on the system securityd about every 3 s at 21:26:05–21:27:00. Grep both repos for `security find-generic-password` callers and their cadence.
8. Hook fork cost: 337–561 forks/s and 33–48% kernel time; one session ran the notify hook 8 times in 113 s. Compare per-session new-process counts in `attrib.jsonl` against tool-call counts.
9. kitty's main thread was never sampled. Take one `sample` of kitty the next time a pane, not the TUI, stops responding.
10. Reboot as an operator option: uptime 9.3 days, kalloc.1024 at 8.5 GB against a 6 GB alarm, 15 swapfiles. Its effect on the stall is unmeasured.
11. Gauge thresholds rest on three points. A week of F4 rows settles them.
12. Not recoverable from existing logs: the makeup of the 343–547 runnable peak at 01:02–02:00Z, and the 1.35–3.86 cores of unseen CPU.

## 5. FIRST THREE

1. **F1, drop the Pop sound.** No dependency. It needs the operator's Hammerspoon reload to take effect. F6 must not land before it.
2. **F2, no afplay while HOT.** Independent of F1. Lands through the project `/ship`. Its convoy-flag clause is added after F4.
3. **F4, the convoy gauge.** No dependency. It must precede the flag gate in F5, the enable test in F8c, the before-and-after in F9, and the open root-cause question.

Alongside these, at no ordering cost: draft F3 for the operator to send. Next come F5, then F6, then F7's test when the box is idle.
