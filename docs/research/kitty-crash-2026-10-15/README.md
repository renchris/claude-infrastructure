# kitty crash 2026-10-15 00:01:27 — root-cause investigation

Status: investigation complete (workflow `wf_496e7f13-644`, 6 angles + synthesis + adversarial skeptic); fix NOT yet implemented.
Status (2026-10-15, phase 2): the guard and every caller landed at `fb3edd4ff` and are live (converged; `~/.claude/bin/kitty-fullscreen-guard` linked); the post-land repro waits on an unlocked screen — see § "Phase 2 landed".
Status (2026-10-15, phase 1): precondition reproduced (32/32 unguarded fullscreen destroys close the window while still in fullscreen; the segfault itself 0/32); fix chosen and corrected by a 4-lens adversarial review — see § "Repro and chosen fix" at the end. Phase 2 implements it.
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
  - CORRECTED (2026-10-15, phase 1 repro): refuted as written (a fixed wait, a blind read-back), adopted in a corrected form. The CGS Space type reads native fullscreen reliably for a window at rest, and a deliberate toggle-off runs its exit transition on a LIVE window. The guard therefore waits for a stable windowed read longer than any transition, and only then acts. See § "Repro and chosen fix".

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
---

# Repro and chosen fix (2026-10-15, phase 1)

**Result.** Destroying a native-fullscreen kitty window by any path closes the window while it is still in fullscreen: AppKit's fullscreen teardown (the toolbar window's removal) runs after the window has closed. This held in 32 of 32 unguarded trials, through move, close-window and child exit, and in the same order as the incident. The segfault itself did not reproduce: 0 of 32, and 0 of 8 under NSZombieEnabled + MallocScribble. A guard that leaves fullscreen, waits until the window is stably windowed, and only then acts removes the precondition. The fix is that guard, placed at every chokepoint our tools own. An adversarial review (4 lenses, below) found three defects in the first guard design, and they are corrected in the spec here.

## How it was run

- Harness:
  - [`repro/run.sh`](repro/run.sh): the matrix driver.
  - [`repro/probe.swift`](repro/probe.swift): reads the Space type, reads the front app, provides the stand-in helper app, and sends the activate Apple Event addressed by pid.
  - [`repro/close-order.py`](repro/close-order.py): orders each window's close against its fullscreen teardown.
  - [`repro/trial.sh`](repro/trial.sh): the first version, one kitty per trial. A cold kitty start once took ~2 min at load 58, so `run.sh` keeps one throwaway kitty and relaunches it only after a crash.
- The throwaway kitty:
  - same binary as the live one (`/Applications/kitty.app`, 0.48.2), running a copy of the live `kitty.conf`;
  - `--listen-on unix:~/Development/.worktrees/kitty-repro/k.sock` and `--instance-group=kcrash-repro`;
  - launched under `env -i`, so no `KITTY_LISTEN_ON`, `KITTY_WINDOW_ID` or `ITERM_SESSION_ID` from the live instance leaked in.
- Isolation from the live kitty: every `kitty @` call carried `--to` the throwaway's socket. No osascript ran, and nothing named `application "kitty"`. The live kitty was never addressed.
- Native fullscreen was verified before every action by the window's CGS Space type (`CGSCopySpacesForWindows` + `CGSSpaceGetType` = 4).
- The stand-in helper copies the activation of `kitty-pane-menu-native.swift:272-296`:
  - it is an `.accessory` app that activates itself and pops an NSMenu at the pointer;
  - it cancels the menu after 250 ms, holds 300 ms (the real helper's exit sat ~300 ms on the analytics barrier, unilog `:305`), then exits;
  - the action fired right after it exited.
- `post=menu` replays the menu's tail after the action: `equalize_tab_of`, then a `kitty @ ls`, then the activate Apple Event that `refocus()` sends, addressed to the throwaway's pid.
- Load averaged 55–59 during the runs (the incident: ~47–70).
- Evidence, outside the repo: `~/.claude/autonomy/incidents/kitty-crash-2026-10-15/repro-2026-10-15/` holds `results-*.tsv`, `run-*.log`, one AppKit Window-category log per throwaway (`window-<pid>.log`) and `close-order-<pid>.tsv`.

## Matrix

"Close order" comes from `close-order.py`:
- **in fullscreen**: the window logged `finishing close`, and its `NSToolbarFullScreenWindow` was removed from the group and closed afterwards.
- **left fullscreen first**: the toolbar window was gone before the window closed.

The number is the toolbar's close time minus the window's.

| Configuration | Action | Context | Trials | Crashed | Close order |
|---|---|---|---|---|---|
| Destination windowed | move (`detach-window --target-tab`) | idle / after helper | 1 / 1 | 0 | in fullscreen, +21 / +16 ms |
| Destination windowed | close (`close-window`) | idle / after helper | 1 / 1 | 0 | in fullscreen, +19 / +19 ms |
| Destination windowed | child exit | idle / after helper | 1 / 1 | 0 | in fullscreen, +23 / +21 ms |
| Destination + 2 more windows fullscreen | move, then the menu's tail | after helper | 3 | 0 | in fullscreen, +21..+29 ms |
| same | move, then the menu's tail | idle | 3 | 0 | in fullscreen, +23..+26 ms |
| same | move | after helper | 3 | 0 | in fullscreen, +19..+20 ms |
| same, source had 2 panes, one closed 1 s before | move, then the menu's tail | after helper | 3 | 0 | in fullscreen, +20..+25 ms |
| same | close, then the menu's tail | after helper | 3 | 0 | in fullscreen, +20..+29 ms |
| same | child exit | idle | 3 | 0 | in fullscreen, +21..+30 ms |
| Zombies + scribble, destination + 1 window fullscreen | move, then the menu's tail | after helper | 2 | 0, no zombie message | in fullscreen, +19 / +26 ms |
| same | move / close / child exit | idle | 2 / 2 / 2 | 0, no zombie message | in fullscreen, +22..+29 ms |
| same, **guarded** (focus, toggle, poll, settle 1 s) | move, then the menu's tail | after helper | 2 | 0 | **left fullscreen first** |
| same, **guarded** | close | idle | 2 | 0 | **left fullscreen first** |
| **Incident**, kitty 64211 | move (most likely) | after helper | 1 | **SIGSEGV** | in fullscreen, **+40 ms** |

Totals:
- **Unguarded:** 32 trials, 0 crashes, 32 of 32 closed in fullscreen.
- **Guarded:** 4 trials, 0 crashes, 4 of 4 left fullscreen first.
- **Zombies:** confirmed active in the throwaway before the zombie trials ran (`heap` listed `_NSZombie_*` classes).

## What the repro settles, and what it does not

1. **The precondition is deterministic and path-independent.** Every destroy of a native-fullscreen window closes the window while AppKit still holds it in fullscreen. The crash stack is in exactly that state: `_NSExitFullScreenTransitionController dealloc` drops the last reference to a window that has already closed. Move, close-window and child exit behave identically, so guarding the menu's move alone would leave two thirds of the trigger class open.
2. **The repro did not reach the crash phase. It shows the precondition, not the fault.**
   - The kitty-side sequence differs from the incident in two ways. In every repro close, an `_NSFullScreenMouseDetectionWindow` closes 5–17 ms after the window; the incident has none. In the incident, kitty also reordered its other fullscreen window a87e relative to 8471 in the same millisecond, which happened in 0 of 32 repro closes.
   - WindowServer kept the incident's 33905 past its close (still not removed at the crash). Its SkyBridge log never recorded the repro windows, so that hold cannot be compared.
   - 0 of 32 caps the per-destroy rate at ~9% (95%). It cannot tell a rare race from a crash that needs a missing co-factor.
   - The zombie null shows only that the repro path holds no latent freed-object dereference. The `.ips` x0 (`0x600000793100 | 1`) is an odd value read out of a slot, which zombies cannot flag.
3. **The co-factor was untested, not ruled out.** The incident destroyed the window 15 ms after kitty reactivated; the repro's fastest was 20 ms. kitty's main loop logged nothing from .121 to .447 in the incident (probably stalled ≥300 ms, with 18 streaming sessions across 6 fullscreen windows), while the repro kitty answered every time. The stand-in cancels its menu instead of performing a pick, never follows a right mouse-down, and is not kitty's child. And Mission Control, which ran 3 s before the incident, was not replayed. **The fix does not depend on which co-factor it was**: whatever opens the race, the guard removes the state the race runs in.
4. **The fullscreen read-back premise is corrected, for this detector only.** `session-durability-2026-10.md:72` ("every read-back tried so far is blind") measured frame heuristics and AX. The CGS Space type read 4 on all 36 at-rest fullscreen verifications and on the live windows, and `/usr/bin/python3` reads it through ctypes. It is not a transition detector: the type leaves 4 0.17–0.39 s *before* an exit animation ends, and it never reads 4 *during* an enter animation. So "not 4" means windowed only after it has held steady for longer than a transition takes (§ Chosen fix).
5. **The earlier objection to "toggle off, then act" is answered by ordering plus a stability gate, not by the toggle alone.** A deliberate toggle-off runs the exit transition on a live window. In the 4 guarded trials the transition ended 0.61–0.83 s before the destroy, and that margin came from the fixed 1 s settle, not from the poll. The guard below replaces the fixed settle with a positive stability read.
6. **A second kitty defect, found by the review:** `kitty @ action --match id:N <action>` ignores the match. In 0.48.2 the client sends `match_window` (`rc/action.py:58`), the server reads only `match` (`rc/base.py:381`), and the action runs on the *active* window. The guarded trials only worked because `run.sh` focused the target first.
   - This also explains the measured `--match … equalize` no-op (`kitty-pane-menu:259-266`).
   - It explains the "still windowed after its toggle, focusing it and toggling once more" retry in `cc-resume-layout.sh:883-889`: that toggle hits whichever window is active, not the one named.
   - `kitty @ kitten --match` does honor its match (`rc/kitten.py`).

## Adversarial review (workflow `wf_8d3c744e-7e1`, four lenses at xhigh)

| Claim | Verdict | What changed |
|---|---|---|
| Unguarded destroys always close in fullscreen, as in the incident | WEAKENED | Holds as measured. It is the precondition, not the crash phase; the repro's sequence differs from the incident's (point 2 above). |
| The crash is a race; the helper co-factor is not needed | WEAKENED; "not needed" REFUTED | Restated as "untested". The co-factor arms are listed in point 3. |
| Guard: toggle, poll until not 4, settle 1 s, act | WEAKENED | Wrong target (`action --match` ignored), an early signal (Space type flips before the transition ends), and it fails open (an unknown read counts as windowed). All three are corrected below. |
| Placement: menu, confirm-close, it2 close, runners | WEAKENED | Must be the LAST gate before the destroy. The autonomous closers' 8–10 s outer timeouts cannot fit a toggle and wait. Native kitty bindings, ⌃⇧Q, `lr-fleet.sh:2109`, `cc-pane-close`'s SIGHUP fallback and typed `exit` / Ctrl-D were uncovered. |

## Chosen fix (implemented in phase 2)

**The guard: `bin/kitty-fullscreen-guard`** (new; Python 3, stdlib and ctypes only).

- **Usage:** `--window <kitty window id> [--to <address>] --mode toggle|refuse`. Exit codes: 0 = safe to empty the window now; 3 = refused, the caller must not empty it.
- **Last-pane check and targeting:** done inside kitty by a small no-UI kitten (`kitty @ kitten --match id:<wid> <repo>/lib/kitty-fs-kitten.py`). `--match` resolves exactly, and a missing pane is a MatchError, never a fallback to the active window. The kitten:
  - reports whether `wid` is the last pane of its OS window, and the OS window's `platform_window_id`;
  - when asked to, calls `toggle_fullscreen(os_window_id)` and returns its boolean result. True means the call ENTERED fullscreen: the guard toggles back and refuses.
  - The kitten runs only kitty's own API; no ctypes runs inside the live kitty process.
- **State read:** three-valued, from the CGS Space types of `platform_window_id`, read outside kitty:
  - **FS**: the types include 4;
  - **WINDOWED**: the types are exactly `[0]` and the window is onscreen;
  - **UNKNOWN**: anything else — SPI load failure, a missing window row, an empty Space list, another type value, a null or ≤0 id.
  - UNKNOWN refuses.
- **Before toggling:** proceed with no toggle only if the window reads WINDOWED on every 100 ms sample for ≥1.0 s, which is longer than the longest transition measured (0.90 s); this closes the enter-animation gap. FS means toggle. UNKNOWN means poll to a 3 s wall-clock deadline, then refuse.
- **After toggling:** poll every 100 ms to an 8 s wall-clock deadline. The window must read WINDOWED with identical bounds for ≥1.0 s, then the guard re-reads once and returns 0.
- **Failure:** never toggle a second time; refuse with an alert naming the window and its last state.
- **Mode and visibility:** `--mode toggle` (operator-initiated callers) toggles only when the window's Space is the one its display is currently showing, so the operator never gets pulled across Spaces. `--mode refuse` (autonomous callers) never toggles: if the pane is the last one of an FS or UNKNOWN window, it exits 3.
- **Logging:** every verdict appends a row to the action log below.

**Callers.** The guard is always the LAST gate, run after every other check has passed and immediately before the destructive call:

- **`bin/kitty-pane-menu`**: Move to <window> (after re-checking that the destination tab still exists), Move to New Window and Close Pane. Mode toggle. Exit 3 means no action, plus an alert: "This is the last pane of a fullscreen window and it did not leave fullscreen cleanly; leave fullscreen and try again."
- **`bin/kitty-confirm-close`**: `close(ids)`, only when `ids` is every pane of the OS window, and only after the dialog said Close or the not-busy decision. Mode toggle. A Cancel must leave fullscreen untouched.
- **`bin/it2-kitty` `session close`** (`:1477`, after the composer guard): mode refuse. Exit 3 becomes exit 1 plus a stderr line. A last pane in a fullscreen window stays open, and the operator closes it by hand through a guarded path. This is the shared actuator for handoff self-close, `cc-pane-close`, `cc-teardown`, teammate shutdown, lr-upgrade and Claude Code's own pane kill. Its callers' 8–10 s timeouts (`hf_bounded`, `pane-close-retry`, `teammate-auto-shutdown`) cannot fit a toggle and wait, and it never toggles a window on a Space the operator may not be looking at.
- **`bin/cc-pane-runner` `_close_on_exit`** (`:169-200`) **and `bin/reso-resume-one` `rr_close_on_clean_exit`** (`:1007-1029`): mode refuse. Exit 3 keeps the shell (their existing keep branch). The accepted cost: a husk shell stays in a fullscreen window when its last session ends cleanly.
- **A pane's root shell exiting by hand** (typed `exit` or Ctrl-D, the likely way pane 8 left window 5): a `zshexit` hook registered from `lib/pane-successor.sh`, which the kitty-setup block in `~/.zshrc` already sources, so `~/.zshrc` needs no hand edit.
  - It acts only when the shell is the pane's root process, meaning its parent is the window's `pid` in `kitty @ ls`.
  - Mode toggle.
  - It skips on SIGHUP: a HUP means kitty is already closing the window. A `TRAPHUP` that records the flag and still exits handles this.
  - Measured here: zsh runs `zshexit` on a normal exit and on SIGHUP, but not on `exec`.
- **kitty's native bindings** (`config/kitty.conf:879-886`: ⌘⇧O `detach_window ask`, ⌘⌥O `detach_window`, ⌘⌥⇧O `detach_tab ask`, plus kitty's unoverridden default ⌃⇧Q `close_tab`): rebind each to a background launch that runs the guard in toggle mode and then the same native action with `kitty @ action --self` (`KITTY_WINDOW_ID` set). kitty's own chooser UI is unchanged. This changes key routing, not the fullscreen mode or the one-window-per-Desktop layout, so it needs no ruling. Update `tests/kitty-conf-bindings.bats:395-417`.
- **`scripts/limit-recover/lr-fleet.sh:2109`**: replace the raw `kitty @ close-window` with the `it2` shim, so it gets the guard.
- **`bin/cc-pane-close:219-222` SIGHUP fallback** (runs only when remote control is dead): refuse whenever any kitty window reads Space type 4, because without remote control it cannot prove the pane is not the last one.

**Never relaunch a dead kitty.** `refocus()` (`kitty-pane-menu:952`), the dialog's leading activate (`:915`) and `kitty-confirm-close`'s post-dialog activate (`:453-456`) must stop addressing kitty by name; `tell application "kitty"` launches a dead kitty, which is how kitty came back at 00:01:28. They should skip when the parent pid is not a live kitty (a `--type=background` child of a dead kitty is reparented to launchd), and otherwise activate that pid in a way that cannot launch an app.

**Action log.** `~/.claude/logs/kitty-pane-actions.jsonl` gets an intent row and a result row for every pane-menu choice, confirm-close action and guard verdict. Fields: ts, tool, choice, kitty window id, OS window id, `platform_window_id`, panes in the OS window, state read, guard verdict, rc. The intent row is flushed before the destructive call, so a crash still leaves the attribution whose absence capped the incident at 75%.

**Crash watchdog.** In `hooks/lead-crash-watchdog.sh` `classify_death` step 0 (`:686-718`), a close-record with `sig_reached_wrapper=HUP` no longer self-certifies as RECYCLE/clean-exit.
- A HUP death corroborated by at least 2 other HUP close-records ending within ±15 s, or by a `kitty-*.ips` within ±6 min, is CRASH `terminal-died`.
- An isolated HUP is RECYCLE `pane-hangup`, which stays silent, because an ordinary ⌘W also HUPs.
- Records without the key behave as before.

**Same root fact, smallest change.** `bin/cc-resume-layout.sh:883-889` toggles fullscreen with `action --match`, which kitty ignores. It should target with `--self` and `KITTY_WINDOW_ID`, or through the guard's kitten. That makes the existing one-window-per-Desktop restore toggle the window it names, and leaves the layout unchanged.

**Still exposed**, because it is kitty-internal: the red traffic-light button, kitty's menu-bar close items, and a pane whose root process is neither a zsh nor one of our runners and exits on its own. A kitty-side guard cannot be a synchronous watcher or kitten, because the exit transition needs kitty's main loop and blocking it would deadlock. Closing these needs a kitty patch (decision below).

**Before phase 2 calls it done, the repro gets the review's missing arms:**
- the guard driven against an unfocused target, the target on a background Space, and a second display;
- a destroy during AppKit's automatic fullscreen of a new window;
- the probe rows logged with timestamps, and load recorded for each trial;
- `front_at_action` sampled before the action;
- `quit_kitty` targeting with `--self`: its `action --match` toggle missed and destroyed fullscreen windows at quit;
- the `.ips` scan restricted to the throwaway's own pid.

## Not built: dropped or filed

- `macos_traditional_fullscreen yes`: dropped. The guard removes the precondition without touching the 2026-09-30 one-native-fullscreen-window-per-Desktop ruling (e950bde6d), and kitty #9572 is a separate crash with that option.
- Detachable terminal holder: dropped here. `session-durability-2026-10.md` § "What not to build" already rules out a tmux migration, and this crash class is closed at our own chokepoints.
- Upgrade to kitty 0.49.x: dropped. The destroy path is unchanged on master.
- Upstream reports for both kitty defects, plus a local patch that leaves fullscreen inside `_glfwPlatformDestroyWindow` and would cover kitty's own paths: filed as operator decision `a41897063971`. The reports are outbound acts, and the patch rides on the open patched-build decision 0a8ffe58562a.

## Re-running the repro

```
cd docs/research/kitty-crash-2026-10-15/repro
swiftc -O -o ~/Development/.worktrees/kitty-repro/probe probe.swift
mkdir -p ~/Development/.worktrees/kitty-repro/conf && cp ~/.config/kitty/kitty.conf ~/Development/.worktrees/kitty-repro/conf/ && cp -R ~/.config/kitty/drag-arm.d ~/Development/.worktrees/kitty-repro/conf/
KCR_BFS=1 KCR_EXTRA=1 ./run.sh 2 move:helper:0:menu close:idle exit:idle fsoff-move:helper:0:menu
log show --start '<run start>' --style compact --predicate 'processID == <throwaway pid> AND category == "Window"' | ./close-order.py
```

Each trial takes over the operator's screen with a native-fullscreen Space for ~10 s. On exit, `run.sh` toggles its fullscreen windows off and quits its kitty, but its toggle has the `--match` defect above, so check for leftover fullscreen Spaces.

# Phase 2 landed (2026-10-15)

**Result.** The § "Chosen fix" spec landed on `origin/main` at `fb3edd4ff` (19 commits, `34c5b2186`..`fb3edd4ff`), content-verified by `ship-land.sh` (35 paths present and identical) and converged (`CC_DEPLOY_MAX_LAG_COMMITS=0 deploy-live.sh`, live tip `fb3edd4ff`). A 4-lens adversarial review of the diff (workflow `wf_bf440f65-940`, 31 agents, every finding sent to a skeptic) confirmed 24 findings; every high and medium one is fixed in the landed code, the rest are listed under Residuals. The pre-land smoke against a throwaway kitty read LEFT-FULLSCREEN-FIRST on both guarded trials. The post-land matrix could not run: the screen was locked from 02:43, and a locked screen cannot enter native fullscreen (below).

## What landed, by spec item

| Spec item | Where | Notes |
|---|---|---|
| Guard + no-UI kitten | `bin/kitty-fullscreen-guard`, `lib/kitty-fs-kitten.py` | As specified, plus three review corrections: `--then` acts **inside** the kitten after re-checking the window exists and is still active (bare `detach_window` and the `ask` chooser's new-window/new-tab branches move the ACTIVE window, `boss.py:3318`); an undo after a toggle that ENTERED fullscreen waits for FS to hold 1.0 s (kitty drops a toggle mid-transition, `cocoa_window.m:2339`); `--any-fs` samples for 1.0 s. |
| Menu / confirm-close | `bin/kitty-pane-menu`, `bin/kitty-confirm-close` | Guard last, toggle mode; Close Pane is guarded once, in confirm-close, after the dialog. One alert per refusal, the guard's. Paste now targets with `--self` too. |
| Autonomous closers | `bin/it2-kitty` session close, `bin/cc-pane-runner`, `bin/reso-resume-one`, `scripts/limit-recover/lr-fleet.sh` (now through the it2 shim) | Refuse mode; refusal keeps the pane/shell. |
| Root-shell exit | `lib/pane-successor.sh` `cc_pane_fs_zshexit` | Toggle mode; a refusal execs a fresh shell (the pane stays). **No TRAPHUP** — a function trap replaced zsh's own HUP handling and left a pane's foreground claude alive after its window closed (review, measured). A hangup is recognised by kitty no longer listing the window; opening `/dev/tty` after a hangup blocks forever and isatty still answers on a dead pty, both measured. |
| Native bindings | `config/kitty.conf` ⌘⇧O / ⌘⌥O / ⌘⌥⇧O / ⌃⇧Q | Background launch of the guard `--then <same action>`; `@active-kitty-window-id` is substituted for background launches (kitty 0.48.2 `launch.py:751`). Fullscreen mode and the one-window-per-Desktop layout unchanged. |
| SIGHUP fallback | `bin/cc-pane-close` | `--any-fs` refusal, and no SIGHUP at all once remote control has answered and refused. |
| Never relaunch kitty | menu `refocus()` and `choose()`, confirm-close post-dialog | Activate the parent pid through `NSRunningApplication` only when it is a live kitty; nothing names `application "kitty"`. |
| Action log | `lib/kitty_pane_actions.py` → `~/.claude/logs/kitty-pane-actions.jsonl` | Intent row fsynced before the destroy; guard verdict rows. |
| Watchdog | `hooks/lead-crash-watchdog.sh` | HUP + ≥2 sibling HUPs within ±15 s, or a kitty `.ips` within ±6 min ⇒ CRASH `terminal-died`; a lone HUP ⇒ RECYCLE `pane-hangup`. |
| Restore toggle | `bin/cc-resume-layout.sh` | `KITTY_WINDOW_ID=<head> action --self toggle_fullscreen` after an existence check. |
| Deploy link | `scripts/kitty-setup.sh` | Links the guard; callers also find it beside their real path. Without this the four rebinds, ⌘W and the menu would have failed closed on every pane (review, high). |

## Suites run (plan line → result)

- All changed suites, before the review fixes: `1..685`, 684 ok; the one red (`lr-fleet.bats` #395, a ≤3 s timing test, 41 s at load 37) passed alone at load 18 (`1..1`).
- Suites that reach the guarded paths through the real `it2-kitty` or runners: `1..401`, 399 ok; the two reds (`spawn-wedge-watchdog.bats` "arming") fail identically on trunk `545fde903`, so they are not this change's.
- After the review fixes and the rebase onto `545fde903`: `1..544` across 21 suites, 543 ok + the hangup case, fixed in `22532a37b`; then `pane-successor.bats` + `lr-fleet.bats` `1..190` all ok, `kitty-pane-guard.bats` `1..14`, `kitty-fullscreen-guard.bats` `1..23`, `kitty-setup-guard-link.bats` `1..2`, `cc-pane-close.bats` `1..20`, the watchdog HUP cases `1..9`, all ok. Bare `shellcheck` clean on every changed shell file.
- RED-proofs: each new or changed regression case was run against the pre-fix file (or the reviewed first draft) and failed for the intended reason; the file headers record which.

## Repro against the throwaway kitty

Pre-land smoke (02:13, the branch before the review fixes; same kitten query/toggle and CGS read as landed):

| Cell | Trials | Crashed | A fullscreen before | Guard rc | Close order of A |
|---|---|---|---|---|---|
| guard-move/idle | 1 | 0 | 1 | 0 | LEFT-FULLSCREEN-FIRST −2276 ms |
| menu-move/idle (landed-shape menu, fake native helper, fake osascript) | 1 | 0 | 1 | 0 | LEFT-FULLSCREEN-FIRST −1910 ms |

The harness's own quit also left fullscreen first once `quit_kitty` targeted with `--self` (two more windows, −5305 / −2596 ms).

Post-land (03:28, landed code): **not measurable — the screen was locked** (`CGSSessionScreenIsLocked = 1` since 02:43). On a locked screen `toggle_fullscreen` does not take and every window reads offscreen, so all 14 trials ran with A windowed (`fs=0`). What that run does show: 0 crashes, and the guard refused every last-pane trial `refused-unknown` (fail-closed when it cannot read the state). `repro/post-land.sh` runs the full post-land matrix with the review's arms (unfocused / background-Space target, a second display, a destroy during AppKit's automatic fullscreen of a new window, probe rows timestamped, load per trial, `.ips` restricted to the throwaway's pid) and prints the table; it refuses with exit 3 while the screen is locked.

Refocus (landed menu, real osascript, 03:34): from a process reparented to launchd — what a background child of a dead kitty is — `refocus()` launched nothing, and an activation lookup of the dead throwaway pid returned nil. The set of kitty processes was the live one alone before and after.

## Residuals (confirmed by the review, not fixed here)

- The `ask` choosers (⌘⇧O, ⌘⌥⇧O) are asynchronous: the guard leaves fullscreen before the chooser opens, so a cancelled chooser leaves the window windowed, and the move itself happens in kitty's callback after the guard returned. Closing it needs the kitty patch (decision `a41897063971`).
- `lead-crash-watchdog.sh`: a deliberate ⌘Q / kitty restart HUPs every pane at once and reads `terminal-died`; any `kitty-*.ips` within 6 min corroborates, including a throwaway repro kitty's.
- `scripts/handoff-fire.sh` `hf_close_pane` discards it2's stderr, so a deliberate fullscreen refusal looks like a transient failure to its retry loop.
- The converge's `install.sh` pass did not create the new `bin/kitty-fullscreen-guard` link (it silences `kitty-setup.sh`); running `scripts/kitty-setup.sh` from the canonical tree did. A brand-new `bin/kitty-*` file needs that until the install pass is fixed.
