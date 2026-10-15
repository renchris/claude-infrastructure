# kitty crash 2026-10-15 00:01:27 — root-cause investigation

Status: investigation complete (workflow `wf_496e7f13-644`, 6 angles + synthesis + adversarial skeptic); fix NOT yet implemented.
Evidence copies (outside the repo, survive the /tmp boot wipe): `~/.claude/autonomy/incidents/kitty-crash-2026-10-15/`
(`.ips`, `unilog-0127.txt` = unified log 23:58–00:02:30, `log.txt` = kitty-script log, `cocoa_window_v0.48.2.m`, `hb.kitty-ls.json`, `workflow-raw-findings.json`).

## Verdict (lead's reading of synthesis + skeptic)

- kitty 0.48.2 (pid 64211, one process holding every pane) segfaulted in AppKit while freeing a native-fullscreen NSWindow whose last pane had just been removed: `_NSExitFullScreenTransitionController dealloc → NSWindow dealloc → _removeForwardedObserver → objc_retain` on a dead object (registers point at AppKit's NSCGSWindow proxy).
- Trigger (~75-85%): the operator's right-click pane menu (`bin/kitty-pane-menu`), choice "Move to <other window>" (`detach-window --target-tab`) on the LAST pane of a native-fullscreen OS window. Pick at 00:01:27.124, window ordered out .462, crash .587. No autonomous script acted.
- Co-factor (~40%, untested): the window was destroyed 5–15 ms after kitty was re-activated by the menu helper app quitting. A close while kitty is idle and active may not crash; this would explain one crash in ~2 weeks of fullscreen layouts.
- `_glfwPlatformDestroyWindow` never exits fullscreen or checks `in_fullscreen_transition`, and does a zero-size `setFrame` on every macOS version (`cocoa_window_v0.48.2.m:2543-2583`). Unchanged on master, so upgrading to 0.49.x is not expected to fix it.
- Relaunch at 00:01:28 came from our own menu's `refocus()` (`osascript … activate` on a dead kitty), not a watchdog.
- 18 sessions died of SIGHUP (close-records `sig_reached_wrapper=HUP`), 05:01:34–36Z.

## Refuted claims (do not rebuild on these)

- "Pane 8 closed itself on rc 0." `lr-fire-resume.sh` always `exec zsh -l -i` on a terminal stdin (`:1703`); only `reso-resume-one` closes on rc 0. Pane 8 was an idle shell, most likely closed by hand just before.
- "1b1eb844 surviving until the SIGHUP proves it was moved." `ended_at` measures claude's 4–9 s shutdown lag.
- "Fix #1: toggle fullscreen off, wait, then act." Toggling off STARTS the very exit transition whose controller is in the crash stack; fullscreen read-back is unreliable on this Mac (`docs/research/session-durability-2026-10.md:72`) and load is ~70.

## Fix candidates, after the skeptic

1. Repro first, as the gate for every fix: a throwaway kitty with its own socket and config (NEVER the live instance), 2 OS windows, one native-fullscreen; matrix = move-last-pane vs child-exit × kitty idle-active vs right after a background helper app activates and quits.
2. Guard in our tools at the chokepoint: `kitty-pane-menu` and `kitty-confirm-close` refuse (or hide) move/close of the LAST pane of a native-fullscreen window, or (if the co-factor reading holds in repro) settle activation BEFORE the destructive action instead of after it.
3. `refocus()` must not relaunch a dead kitty (check the socket first).
4. Log every pane-menu and confirm-close choice (the missing log capped attribution at 75%).
5. Crash-watchdog: classify SIGHUP deaths from `sig_reached_wrapper=HUP`, not as RECYCLE/clean exit (17 of 18 misfiled).
6. Strategic, not tonight: a detachable terminal holder (3 distinct kitty crash classes in a month: 09-15, 09-16, 10-15).
7. Low: kitty 0.49.2 upgrade; `macos_traditional_fullscreen yes` (breaks the 2026-09-30 operator ruling e950bde6d; needs a ruling).

The full synthesis and skeptic texts follow verbatim.

---

# Synthesis: kitty 64211 crash, 2026-10-15 00:01:27 CDT

Overall conviction is about 80% on this chain: removing the last pane from a native-fullscreen kitty OS window made kitty 0.48.2 tear the window down while it was still in fullscreen, and that crashed AppKit's exit-fullscreen cleanup. The crash has not been reproduced, and it is the only crash with this signature on record.

## 1. Root cause chain, from trigger to SIGSEGV

**L0. Every OS window was in native macOS fullscreen, one per Desktop.** (95%)
- `cc-resume-layout` set this up with `toggle_fullscreen` by window id (`bin/cc-resume-layout.sh:883-889`, read this pass).
- `kitty.conf` does not set `macos_traditional_fullscreen` (grep this pass, no hit). `docs/research/session-durability-2026-10/C2-skeptic-code.md:75` says the same.
- `hb.displays.tsv` row 33905 has fullscreen=1.
- The closing window had a fullscreen toolbar window, b017 (unified log, 00:01:27.506).

**L1. Kitty OS window 5 (macOS window 0x8471 = 33905) held two panes, 8 and 410.** (95%)
- Pane 8 ran session 66936177. Pane 410 ran session 1b1eb844.
- I checked this myself from `~/.claude/autonomy/heartbeat/753919F0-.../64211/hb.kitty-ls.json` (written 23:57:46): `oswin 5 pwid 33905 tabs 1 panes [8, 410]`.
- The inventory angle said all of window 8's siblings had left. That is incomplete: pane 410 was in the window at 23:57.

**L2. Pane 8 most likely closed itself at about 00:01:17, leaving pane 410 as the last pane.** (65%, unverified)
- Its claude exited with code 0 at 05:01:17Z (close-record `16065-1791856357.json`).
- The resume launcher is `zsh -ic "$cmd || exec zsh -i"` (`bin/cc-resume-layout.sh:805` and `:1026`). The comment at `:1022-1023` says "rc 0 is reso-resume-one's 'ended on purpose, close the pane'".
- Unverified: the exact moment the pane closed (pane closes inside an OS window leave no unified-log line), and whether reso-resume-one itself returned 0.

**L3. The operator picked an item from our right-click pane menu at 00:01:27.124.** (90%)
- Right mouse button down at 00:01:24.852, just after Mission Control (00:01:23.5 to 00:01:24.7).
- `kitty-pane-menu-native` pid 40243 showed the menu at 00:01:25.180, and an item was performed at 00:01:27.124.
- A real (not cancelled) choice is proven separately. In `bin/kitty-pane-menu`, `if not choice: return 0` comes before `refocus()`, and refocus's osascript (pid 43801) started at 00:01:27.558.

**L4. That choice took the last pane out of OS window 5, so kitty destroyed the fullscreen window.** (80% that a pane-menu action emptied it; 60% that it was "Move to <other window>" on pane 410)
- Unified log: 8471 ordered out at 00:01:27.462, "finishing close" at .466, b017 removed and closed at .506.
- "Move to <other window>" (`detach-window --target-tab`, which deliberately writes no log; `bin/kitty-pane-menu` about lines 1084-1095) is the only reading that fits all three of these facts:
  - session 1b1eb844 stayed alive until the crash's SIGHUP at 05:01:34-36Z;
  - only 340 ms passed between the menu pick and the close, too short to answer a confirm dialog;
  - the pane menu's process exited at 00:01:27.427.
- Ruled out:
  - "Move to New Window": it writes a `pane-spawns.jsonl` row, and none exists.
  - "Close Pane" on pane 410: it was busy, so a dialog would have shown, and it survived.
- Possible but less likely: "Close Pane" on pane 8 sitting at a bare prompt. That needs pane 410 to have left earlier without any log.
- The window ordered above 8471 as it closed is a87e = 43134 = kitty OS window 11 (panes 32, 14, 11, 460), computed this pass. It is either the window AppKit promoted next or the move destination (unverified).

**L5. kitty's window-destroy code never leaves fullscreen first.** (70%: the code reading is solid, the AppKit behaviour is inferred)
- `_glfwPlatformDestroyWindow` (v0.48.2 `cocoa_window.m:2543-2583`, the same apart from formatting on master) does orderOut, setDelegate:nil, releases the delegate and view, sets a zero-size frame, then `[w close]`.
- It never exits fullscreen and never checks `ns.in_fullscreen_transition`. It has no handler for windowDidFailToExitFullScreen or windowWillClose.
- Closing a fullscreen window makes AppKit create an `_NSExitFullScreenTransitionController` that holds a reference to the window.

**L6. At the run loop's autorelease-pool pop, the freed window touched a dead object and kitty segfaulted at 00:01:27.6478.** (95% on the stack; 40% on which object was dead)
- The controller was freed and dropped the last reference to the KVO-swizzled NSWindow.
- `-[NSWindow dealloc]` then ran `_termWindowIfOwner`, then `_setWindowNumber:`, then `_removeForwardedObserver`, and `objc_retain` was handed a freed or reused object.
- Register evidence:
  - `x0=0x600000793101` is odd, so it cannot be a valid heap object;
  - its isa read back as junk (0x20c6878);
  - the fault address 0x20c6898 is unmapped (`.ips:46-48`).
- The dead object could be AppKit's window-server proxy (NSCGSWindow) or kitty's already-released content view or delegate. That is unresolved and needs a repro under Zombies.

**L7. All 18 claude sessions were children of that single kitty, pid 64211, so they all received SIGHUP between 05:01:34Z and 05:01:36Z.** (97%, close-records)

**Contradictions resolved:**
- The infra-trigger angle concluded "pane 8 closed itself and that closed the OS window; no pane-menu involvement". Its own caveat (pane 410 was in the same tab) and the unified-log pane-menu sequence refute that. The self-close was most likely the earlier half (L2), not the trigger.
- The history angle's "no pane close before the crash" read only `pane-close-retry.log`, which covers neither the pane-menu nor the self-close paths.

## 2. What relaunched kitty (85%)

Our own `bin/kitty-pane-menu` relaunched it. `refocus()` (about line 952) runs `osascript -e 'tell application "kitty" to activate'` after any non-cancelled choice.

- osascript pid 43801 started at 00:01:27.558 as a child of the dying kitty.
- Because kitty was gone, "activate" launched it again through LaunchServices and CoreServicesUIAgent: launched at 00:01:28.364, check-in at 00:01:28.544, new pid 44163 with parent pid 1.
- The new kitty inherited the dead one's environment: `_=~/.claude/bin/cc-restore`, `TERM_PROGRAM=Apple_Terminal`, `LCW_ORPHAN_CLOSE=1`.
- No LaunchAgent or watchdog was involved.
- There is no `startup_session`, so it opened one default window. Kitty window ids restart from 1 in the new process.

## 3. Did our automation trigger it?

No autonomous script, daemon or hook acted (80%). These were all quiet in the window: `pane-spawns.jsonl`, `handoffs.jsonl`, `pane-close.jsonl`, `idl.jsonl`, the launchd spawns and `bash-commands.log`. b351c528's `fire-lanes.sh` spawned nothing.

The trigger was an operator click routed through our tool (`kitty-pane-menu`), which sent a kitty remote-control move or close with no fullscreen guard. Our resume layout supplied both preconditions:
- native fullscreen on every OS window;
- the pane pattern that closes itself on exit code 0, which most likely left pane 410 as the last pane.

## 4. Candidate fixes, ranked

1. **One safe-close guard shared by every path that can empty an OS window.**
   - Paths to cover: `kitty-pane-menu` (Move to, Move to New Window, Close Pane), `kitty-confirm-close`, `it2-kitty` close-window (`:1477`), `cc-pane-close`, `cc-restore:746`, and the resume pane's own exit wrapper.
   - Behaviour: if the target OS window is in native fullscreen and the action would leave it with no panes, toggle fullscreen off first, wait for the exit animation to finish, then act. Use a bounded wait with a System Events AXFullScreen read-back where it works, otherwise a fixed settle. Read-back is unreliable on this Mac (`docs/research/session-durability-2026-10.md:72`).
   - Pros: cheap, lives in our repo, lands through `/ship`.
   - Cons: does not cover closes kitty makes on its own outside our wrappers. Its value depends on a repro showing that a close while windowed does not crash.
   - Route the self-close too: the resume pane's wrapper should run the guard before exiting, rather than reversing the deliberate "exit 0 closes the pane" design.
2. **Patch kitty's GLFW code** (`_glfwPlatformDestroyWindow`): while the window is fullscreen or mid-transition, keep a strong reference until windowDidExitFullScreen (or the fail callback), and add windowDidFailToExitFullScreen. This is the approach WebKit and Electron took.
   - Pros: covers every close path.
   - Cons: we maintain a fork on top of the staged build, which is waiting on open decision 0a8ffe58562a. It needs a repro plus Zombies to find the dead object. Filing upstream with the `.ips` is an outbound act, so it is the operator's call.
3. **Crash resilience:** hold each claude's terminal in a detachable process (tmux, dtach, abduco, or our own daemon) so a kitty crash costs only the view.
   - Pros: the only option that covers every kitty crash class. That is three incidents in a month: 09-15 (child-monitor thread race), 09-16 (fonts_data, about 55 sessions killed) and 10-15 (18 sessions). It would also keep in-flight tool calls, goals and watchers alive.
   - Cons: the highest cost. It conflicts with kitty's graphics protocol, title bands, and tooling keyed on kitty window ids (cc-registry, it2-kitty, notify-back addresses). It belongs in a research or plan item, not tonight's work.
4. **Upgrade kitty to 0.49.2.** Not expected to fix this, because the teardown code is unchanged on master (upstream angle, 80%). Worth doing only for other reasons.
5. **Set `macos_traditional_fullscreen yes`.** It probably avoids the transition controller (inference, untested). But it breaks the operator's 2026-09-30 ruling of one native-fullscreen window per Desktop (e950bde6d), and kitty #9572 is a separate crash with that option. It needs an operator ruling and is not recommended.

**Smaller follow-ups:**
- (a) Log every pane-menu choice and every `kitty-confirm-close` action. That missing log is why L4 stays at 60%.
- (b) `refocus()` should not relaunch a dead kitty. Check the socket before calling activate.
- (c) The crash watchdog filed 17 of the 18 SIGHUP deaths as RECYCLE/clean-exit. It should classify from the close-record field `sig_reached_wrapper=HUP`.
- (d) Remove the second `toggle_fullscreen` retry that commit dc8b87027 added (`cc-resume-layout.sh:883-889`). The design doc (`:72`) and the skeptic review both ruled it out.

**Risk for the resume handoff:** restoring the layout in native fullscreen re-arms the crash. Until fix 1 lands, the next move or close of a last pane in a fullscreen window may kill every restored session. The options are to warn the operator or to restore windowed, and that choice is the lead's.

**For the root-fix handoff:** reproduce first in a throwaway kitty with its own socket and config, never the live pid 44163. Two OS windows, fullscreen one, then move its last pane out with `detach-window --target-tab`; also try the variant where the last pane's child process exits. Be aware the repro will create a fullscreen Space on the operator's screen.

## 5. Session inventory to resume (verbatim from the inventory angle)

18 Claude Code sessions were alive in kitty pid 64211 when it crashed at 00:01:27 CDT, and all 18 died of SIGHUP between 00:01:34 and 00:01:36. Two more had exited cleanly just before the crash, and a third had exited at 18:33. All 18 victims' worktrees still exist, none of their transcripts is missing, and the worktree GC run at 00:01:30 deleted nothing.

The resume classifier, anchored on the crash time, sorts them as:
- 3 INTERRUPTED: 1b1eb844, 8d9a564f, b351c528
- 3 WAKE-LOST (background work died with the process): 4d059264, ebbc7b61, 519d2fd4
- 12 AT-REST

Two cautions for the resume session:
- lr-select's defaults (1 per worktree, 4 total) would drop most of them. ~/Development/personal alone holds 3 victims on separate topics, so it needs `--max-per-worktree 3 --max-total 18`.
- The new kitty (pid 44163) numbers its windows from 1 again. Every notify-back address that embeds an old window id (4, 7, 16, 319) now points at a different or missing pane.

Output files: /tmp/crash-inv-lrselect.tsv and .err; /tmp/crash-inv/victims.tsv (the 18 victims in TSV form, ready for reso-resume-one / cc-resume-layout.sh); /tmp/crash-inv/scan.out; /tmp/crash-inv/classify.tsv and .err; /tmp/crash-inv/lost.json.

The per-session victim list (account, session id, old window, cwd, last activity, verdict, title) is kept out of this public repo, in `~/.claude/autonomy/incidents/kitty-crash-2026-10-15/victims.md`.

Not victims (excluded):
- 66936177 (window 8): clean exit at 00:01:17.
- 99e83151 (window 460): clean exit at 00:00:17.
- 366a5a2b (window 459): exited 10-14 18:33.
- The new sessions f7351f3b (this lead, new window 1) and 383282c1 (the resume peer already fired, new window 2), both started after 00:01:28.
- ~/.claude-tertiary and ~/.claude-next4 had no transcripts written since 22:00.

Inventory notes:
- The classifier anchor epoch 1792040487 = 2026-10-15T05:01:27Z (`date -j -u`, checked this pass).
- Backlog row c076f54ba660 holds the recovery command `cc-restore --after-crash --kitty-pid 64211`. Whether that command goes through the double-toggle retry is unverified.

## Still unverified
- Which menu item was picked (L4, 60%).
- When pane 8 actually closed, and what reso-resume-one returned (L2).
- Which object's observer info was dead (L6).
- Whether the crash reproduces, and whether it is deterministic or depends on the load (about 47-70).
- Whether `macos_traditional_fullscreen` avoids it.
- Whether kitty `launch --hold` behaves on 0.48.2 as needed for a no-self-close variant.
- Whether macOS window a87e (kitty OS window 11) was the move destination.

Scratch files from the investigators: `/tmp/kcrash-scripts/log.txt`, `/tmp/unilog-0127.txt`, `/tmp/kcrash-src/`, `/tmp/kitty-upstream-research/`, `/tmp/crash-inv/`.

---

# Adversarial skeptic

**Verdict.** The core chain mostly holds: a pane-menu action emptied a native-fullscreen kitty OS window, and AppKit crashed while tearing that window down. Two of the synthesis's supporting claims fail. Pane 8 did not close itself (L2). The "1b1eb844 survived until the SIGHUP" argument cannot separate a moved pane from one closed with the window. The fix ranking also has a weak point: the top-ranked guard would itself start the exit-fullscreen transition whose controller object is in the crash stack.

## Claims that survive (re-checked)

1. **Crash stack and timing (95%).** The faulting chain is in the .ips: objc_retain, then `_NSKeyValueRetainedObservationInfoForObject`, … `-[NSWindow dealloc]`, `NSKVODeallocate`, `-[_NSExitFullScreenTransitionController dealloc]`, autorelease pool pop, `glfwRunMainLoop`. The fault address is 0x20c6898 and is not in any region.
   - `/tmp/unilog-0127.txt:840`: the kernel made the crash record ("Corpse allowed") at 00:01:27.587.
   - `:899`: launchd logged "exited due to SIGSEGV" at 00:01:27.596. The .ips captureTime of .6478 is when the report was written, not when the fault happened.
2. **The closing window was in native fullscreen (90%).** `unilog:522-524`: AppKit removed NSToolbarFullScreenWindow b017 from 8471's group and closed it at .506.
   - Nit: the `hb.displays.tsv` "fullscreen=1" column only means the window fills the display (`scripts/lib/restore-heartbeat.sh:35-37`). It is weak evidence for native fullscreen.
3. **A pane-menu action caused the close (85%).** The pick was at .124 (`unilog:131`). The 300 ms after it is the helper's analytics exit timeout ("Timed out waiting for the exit barrier block", `:305`, at .425). The helper exited at .427 (`:311`). kitty ordered 8471 out at .462 (`:459`).
   - Python's `subprocess.run` cannot return before the helper exits, so the action reached kitty within about 35 ms.
4. **The action was "Move to <another window>" on the window's last pane (75%; the synthesis said 60%).** The 35 ms gap fits only a single `kitty @` round trip.
   - **Close Pane is excluded (about 92%).** It goes through `kitty-confirm-close`, which starts Python, runs a full `kitty @ ls` (`kitty-confirm-close:391`; the menu's own comment measures 72-95 ms), then `close-window` (`:444`/`:449`). That cannot fit in 35 ms.
   - **Move to New Window is excluded.** It runs a bash logger before the detach (`kitty-pane-menu:1069-1070`). The unified log also shows no new kitty window number: only 8471, a87e and b017 appear.
   - **Paste cannot empty a window.**
   - The live `kitty-pane-menu` is unchanged since 2026-10-01 (sha 62c7eda9 matches the reviewed copy).
5. **Our menu's `refocus()` relaunched kitty (90%; the synthesis said 85%).** New kitty 44163 has parent pid 1 and started at 00:01:28. Its environment carries the dead kitty's launchd job label, `XPC_SERVICE_NAME=application.net.kovidgoyal.kitty.330945848.330945854` (the label in `unilog:899`), plus `_=…/cc-restore` (from `ps eww 44163`).
   - So the launch request carried the dead kitty's environment. That fits the osascript started by our menu (a grandchild of the dead kitty, pid 43801 at .558). It rules out a Dock click.
6. **18 sessions died of SIGHUP (97%).** I counted 18 close-records with `sig_reached_wrapper=HUP`, ended 05:01:34-36Z, in `~/.claude/logs/close-records`.

## Claims that fail or weaken

1. **L2 fails: pane 8 did not close itself (85% that it stayed open).**
   - Pane 8's foreground at 23:57 was `lr-fire-resume.sh … 66936177` (`hb.kitty-ls.json`).
   - It was started by a typed `bash …/lr-launch-66936177-VqCnCS.sh` (`~/.zsh_history:978`), which ends in `exec … lr-fire-resume.sh`, so stdin was the pane's terminal.
   - `lr-fire-resume.sh` exits only when stdin is not a terminal (`:1667`). Otherwise it always runs `exec zsh -l -i` (`:1703`; also in the version in force at launch, 04f9be43a:1637). It has no "close the pane on rc 0" step. That rule exists only in `reso-resume-one:1007-1029`, which is what the synthesis cited via `cc-resume-layout.sh:805/1026`.
   - The transcript shows the operator typed "af" at 05:01:08 and interrupted at 05:01:14.84. Claude exited 0 at 05:01:17. After that, pane 8 was an idle shell, not a closed pane.
   - For the menu move to empty OS window 5, a second pane had to be removed with no log entry. The most likely case is the operator closing pane 8's leftover shell with ⌘W, `exit` or Ctrl-D between 00:01:17 and 00:01:24. Two kitty focus-change events, at 00:01:17.83 and 00:01:18.67 (`/tmp/kcrash-scripts/log.txt`), fit this but do not prove it.
   - So the claim "our resume layout supplied the pane that closes itself" fails. Who held the last pane is open: 410 at about 60%, pane 8 (with 410 moved out earlier) at about 25%.
2. **"1b1eb844 survived until the crash's SIGHUP" proves nothing.** kitty was dead at .596. Yet 1b1eb844 wrote an assistant reply at 05:01:31.670Z and exited at 05:01:36Z. So `ended_at` measures claude's 4-9 s shutdown lag, not when the SIGHUP arrived.
   - A pane closed together with window 5 at .466 would get a SIGHUP from kitty (`child-monitor.c:1458-1472`, `killpg` SIGHUP). Its records would look the same.
   - Close Pane on 410 stays excluded, but only by the busy check (`kitty-confirm-close:249`) and the timing.
3. **"a87e was the move destination" is weak.** The `a87e op:1 relative:8471` ordering at .462 happens during kitty's re-activation:
   - LaunchServices brought the next app to the front at .432 (`:331`).
   - kitty ordered 8471 to the front at .447 (`:374`).
   - runningboard marked kitty as the focused app at .457 (`:417`).
   - AppKit reorders an app's windows on activation, so this explains a87e as well as a move would.
4. **L6 (which object was dead): the registers point at an AppKit object, not kitty's view or delegate.** At the fault, x15 is the address of the NSCGSWindow class and x14 is an NSCGSWindow isa value (0x050000020C67FCE7). So the object being un-observed is AppKit's window-server proxy.
   - x0 = 0x600000793101. Reading 8 bytes at that odd address gives a masked value (0x20C6878) that looks like a valid isa shifted by one byte. That suggests x0 is a real object pointer with its low bit set, not random junk.
   - This favors corrupt AppKit-internal observer bookkeeping on the NSCGSWindow (55%). It weighs against "kitty's already-released content view or delegate".
5. **A new lead for the repro.** kitty's destroy path shrinks the window to zero size, a workaround meant for macOS Tahoe, but it runs on every macOS version, including this 15.7.9 (`cocoa_window_v0.48.2.m:2578-2580`).
   - It has been in kitty since 0.43.x (`changelog.rst:1314`), so it is not a recent regression. That, plus this being the only occurrence, points to a race or a co-factor rather than a crash on every close.

## Strongest alternative explanation (about 40%, untested)

The AppKit teardown mechanism is the same, but the deciding co-factor is timing: the window was destroyed in the middle of kitty's re-activation after the menu helper quit.
- The helper is a separate background-style app that brings itself to the front to show the menu (`kitty-pane-menu-native.swift:273-274`).
- When it quit, kitty became the front app (front-app switch at .432, 8471 ordered front at .447, kitty marked focused at .457), and 8471 was destroyed at .462, 5-15 ms later.

Under this reading, closing a fullscreen window while kitty is already active and idle may never crash. That fits one crash in roughly two weeks of fullscreen layouts and pane moves. The cheapest fix would then be in our menu: call `refocus()` and let activation settle before the destructive action, rather than after it (`kitty-pane-menu:1063-1098`).

## Fix ranking

1. **Fix #1 as written is risky.** "Toggle fullscreen off, bounded wait, then act" itself starts an exit-fullscreen transition, which creates the same `_NSExitFullScreenTransitionController` that is in the crash stack.
   - Reading the fullscreen state back is unreliable on this Mac (`session-durability-2026-10.md:72`), and load is about 70. A fixed wait can run out mid-transition and recreate the hazard.
   - Safer interim option: a refusal guard. `kitty-pane-menu` and `kitty-confirm-close` would refuse to move or close the last pane of a native-fullscreen window (or hide those menu items) and tell the operator to leave fullscreen first.
   - Its coverage list is also off. `lr-fire-resume` panes never close themselves. The plain path where the last pane's child exits on its own goes through kitty directly, and no wrapper can guard it.
2. **Make the repro a gate for every fix, not only the kitty patch.** The test matrix should cover:
   - kitty active and idle versus right after a background-style helper app has come to the front and quit;
   - Move versus the child process exiting;
   - kitty's zero-size-frame step on versus off (needs a patched build).
3. **Fix #3 (detachable terminal sessions) is undervalued.** There have been three different kitty crash types in a month. It is the only option that covers every type, so it deserves the strategic slot even if it is not tonight's work.
4. **Agree:** fix #4 (upgrade; the 0.49.x changelog has no fix for closing fullscreen windows) and fix #5 (traditional fullscreen) stay low. Follow-up (a), logging menu and confirm-close choices, is the cheapest high-value item. Add logging of what happens to the pane when `lr-fire-resume` / `reso-resume-one` exits.

## Effect on the two handoffs

- **Resume session:** restoring in native fullscreen keeps the risk. The operator-level mitigation is to leave fullscreen before moving or closing a window's last pane.
- **Also:** `lr-fire-resume` panes leave an idle shell behind after a clean exit. That invited the manual close that most likely set this up.

Evidence: `~/Library/Logs/DiagnosticReports/kitty-2026-10-15-000214.ips`, `/tmp/unilog-0127.txt`, `/tmp/kcrash-scripts/log.txt`, `~/.claude/autonomy/heartbeat/753919F0-7855-45C2-8449-023706DAEAFD/64211/hb.kitty-ls.json`, `~/.claude/logs/close-records/`, `~/.reso/limit-recover/66936177-b305-4678-b95a-73404985e324/bundle-20261013T014941Z/lr-launch-66936177-VqCnCS.sh`, `/Users/chrisren/Development/.worktrees/wt-cc-000146-45877/scripts/limit-recover/lr-fire-resume.sh`, `bin/kitty-pane-menu`, `bin/kitty-confirm-close`, `bin/reso-resume-one`, `/tmp/kitty-upstream-research/cocoa_window_v0.48.2.m`.