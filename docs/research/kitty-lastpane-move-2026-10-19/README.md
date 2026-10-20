# Right-click "Move to" on the last pane of a fullscreen kitty window: why it strands you on the desktop

Code is at commit 9ebe93520. The jsonl log times are UTC (Z). Unified-log times are CDT (UTC−5).

## 1. Root cause

The pane is the window's last one, so the guard has to take the window out of fullscreen before kitty may empty it. macOS answers that by moving the window, and the operator's view with it, to the display's only regular desktop.

- **On success:** nothing ever takes the operator on to the destination, so they are left on the desktop.
- **On refusal:** the guard only passes if the operator stays on that desktop for about 1.15 s after the window lands. A natural swipe toward the destination during that time becomes a refusal. The alert appears and the window is left behind on the desktop, still holding the pane.

### The chain, step by step

1. **Menu.** The pick writes an intent row (`bin/kitty-pane-menu:1144-1146`). The destination is re-checked (`:1178`). Then `guarded()` runs (`:1183`), which calls the guard with `--mode toggle` (`:1012`). That call has no time limit (`:1009-1013`).
2. **No relax.** fsfix is false and there is no policy file, so the policy is block-stock and `relax_reason()` returns None (`bin/kitty-fullscreen-guard:493-502`). The guard takes the toggle path (`:720-739`).
3. **Before the toggle.** `_before_toggle` returns on its first fullscreen read (`:606-614`):
   - window on screen: send the toggle;
   - window not on screen: refused-not-visible, rc 3.
4. **The toggle.** One toggle goes through the kitten.
   - macOS leaves fullscreen in 0.63-0.67 s: 19:39:40.018→.645, 19:41:47.159→.826, 19:45:06.434→07.088. The load average was about 250, so the old "load slows the exit" theory is refuted.
   - The window goes to the only regular desktop (type 0) on display 1B6097CB. That is Space 44, at index 0, to the left of all 7 kitty fullscreen Spaces. The display switches there too: WindowServer logs "current space changed 94→44" at 19:39:40.591 and "90→44" at 19:45:07.014.
   - During the animation the real window is ordered out and a snapshot window (0x4534) stands in for it (19:39:40.020→.645).
5. **After the toggle.** `_after_toggle` (`:626-644`) needs a WINDOWED read, which means Space types exactly `[0]` **and** on screen (`:387-392`).
   - The bounds must stay identical for `STABLE_S=1.0` (`:111`), followed by a confirming re-read.
   - All of that must happen by `AFTER_DEADLINE_S=8.0` (`:113`). The clock starts after the kitten returns (`:627`).
   - In practice a pass needed about 1.15 s after the exit ended (47.826→48.974 and 07.088→08.228).

### (a) "Moves into the desktop and stays there" happens on two paths

**Success path (16 of 20).**
- The menu runs `detach-window --target-tab` (`menu:1189`). kitty's `_move_window_to` ends in `target_tab.make_active()`, which only changes the active tab inside the destination window (`~/kitty-482/kitty/boss.py:3312-3354`, `tabs.py:1156-1159`). It never focuses the destination's OS window.
- The emptied source window closes. kitty's own `cocoa_focus_last_window` (`kitty/glfw.c:2034-2071`) only hands focus to a kitty window on the same Space as the closed one, and Space 44 normally has none.
- `refocus()` activates the kitty app without naming a window (`menu:963-983`, `activateWithOptions(2)` at `:980`).
- The menu avoids `focus-window` on purpose (`:280-281`).
- Result: the pane moves, but the operator is left on the desktop. Proven twice:
  - The source closed at 19:45:14.559 and there was no Space switch until 44→58 at 19:45:18.138.
  - The source closed at 19:41:49.038 and the next switch came at 19:41:56.957.
- If an earlier refusal stranded a window on Space 44, kitty makes that window the focused one right after the close (19:41:49.040 and 19:45:08.293). That is what the operator sees as "landing on the desktop with a leftover window".

**Refusal path, timeout with state UNKNOWN (2 of 20: 10-18T05:00:45, 10-20T00:39:39).**
- The window landed at 19:39:40.645. The operator swiped away about 0.95 s later: 44→70 at 41.592 (70 is the destination, window 386), then 70→235 at 42.287.
- A window on a desktop the display is not showing reads not-on-screen, so it classifies as UNKNOWN. The 1.0 s hold can never finish, and the deadline returns rc 3 at 00:39:48.119Z.
- Nothing is undone: the docstring says "never toggles again" (`:38`), and `decide` simply returns rc 3 (`:738-739`). The menu then breaks out (`:1183-1184`).
- Window 0x1ef stayed windowed on Space 44, still holding wid 41, for 5.5 minutes (until 19:45:14.559). The retry at 00:45:13Z read safe-windowed in 1.48 s.
- For 05:00:45 the exit itself is proven (spaces.fullscreen.end at 00:00:49.685 CDT). The window was put back into fullscreen at 00:02:32 or 00:06:58, before the retry at 05:07:29Z, which had to leave fullscreen a second time. Who re-entered fullscreen is not recorded.

**Refusal path, timeout with state WINDOWED (1 of 20: 10-19T04:25:48).**
- The exit happened (fullscreen.end at 23:25:50.901 CDT). Something reset the hold every time: a bounds change, a non-WINDOWED sample, or a confirming read that disagreed (`:633-641`). Which one is not recorded.
- The alert ran its full 55 s unanswered (verdict at 04:25:58Z, result row at 04:26:54Z).
- The window was back in fullscreen before the retry (fullscreen.begin at 23:47:31.880 CDT), so the retry had to leave fullscreen again.

**Refusal path, not visible (1 of 20: 10-19T06:08:34).**
- The first fullscreen read came 2.19 s after the pick and read not-on-screen, so the display had left that Space in between (`:614`).
- No toggle was sent and nothing was stranded, but the alert still appeared.

### (b) The macOS pop-up

- It is the guard's own osascript `display alert`, titled "kitty: pane not moved or closed" (`:579`). The message is at `:580-584` and it gives up after 55 s (`:576`).
- It fires on **every** toggle-mode rc 3 (`:927-928`).
- The log has 10 such refusals. 4 came from the menu and 6 from `kitty-confirm-close`, the Close path, which matches the operator's "moved **or closed**":
  - 10-16T13:31 refused-unknown
  - 10-16T23:27 refused-timeout WINDOWED
  - 10-18T17:57 refused-timeout WINDOWED
  - 10-19T05:26 refused-unknown
  - 10-19T16:38:04 refused-not-visible
  - 10-19T16:38:17 refused-timeout UNKNOWN
- The text is wrong in every branch. "Did not leave fullscreen … Leave fullscreen and try again" is shown after the window has already left (timeout), and when no toggle was sent at all (not-visible).

**What is not recorded anywhere:**
- The menu is a `--type=background` child, and kitty pid 853 has stdin/stdout/stderr on `/dev/null`, so the guard's stderr line is lost.
- The verdict row (`:901-920`) has no types, on-screen flag or bounds.
- Two different waits both produce the verdict "refused-timeout": `_after_toggle` (`:643`) and `_undo_entered` (`:669`).

### Frequencies (menu attempts on a last pane, n=20)

| Outcome | n | Toggle sent | End state |
|---|---|---|---|
| safe-after-toggle, moved | 15 | yes | pane moved, operator on Space 44 |
| safe-windowed, moved (retry of a stranded window) | 1 | no | same |
| refused-timeout, state UNKNOWN | 2 | yes | stranded (00:39 proven, 05:00 likely) |
| refused-timeout, state WINDOWED | 1 | yes | stranded, later back in fullscreen |
| refused-not-visible | 1 | no | untouched, alert shown anyway |

- 19 of 20 attempts put the operator on the desktop.
- 4 of 20 (20%) ended in a refusal with the alert, and every retry succeeded.
- 2 of those retries had to leave fullscreen a second time.

A smaller issue: the "N desktops right/left" labels are measured from the source's fullscreen position (`menu:856-857`, `:810-817`). Once the window is out of fullscreen, they are wrong for a source more than 2 Spaces from the left.

## 2. Why now, and why the relax path never fires

**This is not a recent regression.** It began with toggle mode itself, the design adopted after the 10-15 crash. The first logged attempt is 10-16T03:32:45Z.

**Why the relax path never fires:**
- It only fires when kitty has the ObjC class `GLFWFsFixV2` (`lib/kitty-fs-kitten.py:43-57`), and only our rebuilt kitty has it.
- Live pid 853 is stock v0.48.2 (team NTY7FVCEKP), restarted 10-18 19:40:35 after the unplanned reboot (README:619). Its cache file `fsfix-853-1792370435` reads false, and no row in the log has ever had fsfix true.

**What blocks the patched kitty:**
- The staged bundle (`/Applications/kitty.app.staged`) carries the marker, but it is ad-hoc signed, so `arm` and `swap` refuse it (`scripts/kitty-build-swap.sh:105-113`, called at `:208` and `:224`).
- Decision 891ea9e9d0f3 was actioned at 2026-10-19T23:37:48Z as "stay on official kitty, no re-sign". The restart marker was disarmed and the background-Space trial (661a8652d2f6) was closed as superseded.
- README:612 and README:619 still describe e3920969aba9 and 891ea9e9d0f3 as open. Both lines are out of date.

**Upstream:**
- The upstream fix, commit 7e88f51ed7 (2026-10-16), is in no release. The latest is v0.49.2 (10-01); the nightly build dates from 10-14, before the fix; 0.50.0 is marked "[future]".
- Even 0.50.0 will report fsfix false, because upstream declined the deferred close (README:604). The guard will keep toggling.

**What would unblock it:**
1. **The operator reverses 891ea9e9d0f3.**
   - Re-sign the staged bundle. The only signing identity on this Mac is "VoiceInk Dev", so kitty loses all 35 privacy (TCC) grants either way.
   - Then `arm`, `swap --confirm`, and restart kitty. The restart ends about 30 sessions and quits 7 fullscreen windows on stock code, which is the unguarded close-from-fullscreen path.
   - Then `verify --clear-marker`.
2. **A new decision to relax the guard on official kitty ≥0.50.0, keyed on version.** This reopens the crash path on stock code, and README R4 says a trial with 0 crashes has no power to clear it.

**Even unblocked, the patched kitty does not fix the landing.**
- The relax forces refuse mode (`:701-714`), and refuse mode still refuses windows that are off screen or UNKNOWN, with the alert (`:595-600`, `:711-712`).
- Its deferred close still leaves fullscreen first (README:512-517), so the operator most likely still lands on the desktop. That has not been measured.
- It removes the stranding and the 1 s race. It does not remove the landing.

## 3. Fix options, ranked

| # | Option | Crash safety | UX effect | Effort | Conviction |
|---|---|---|---|---|---|
| A | Accurate alert text and a complete verdict row | no change | explains the stranding; makes every refusal diagnosable | S | 95% |
| B | Follow the pane to its destination after a last-pane move | low risk | fixes the desktop landing on 16 of 20 attempts | S | 80% |
| C | Survive the swipe-away (narrow relaxation in `_after_toggle`) | medium, trial first | removes the swipe-away refusals (UNKNOWN timeouts) | M | 70% crash-neutral / 85% effective |
| D | Run the patched kitty (GLFWFsFixV2) | best evidence (14/14) | removes the toggle and stranding for on-screen windows; landing still needs B | blocked by the operator | 85% removes stranding / 30% fixes the landing alone |
| E | Official ≥0.50.0 with a version-keyed relax | reopens the stock crash path | like D | S code, new decision | <50% safe |
| F | Placeholder pane: move without leaving fullscreen | safe | leaves a spare shell whose close goes through the same guard | S | 60% usable |

**A. Accurate alert and complete verdict row** (`bin/kitty-fullscreen-guard`)
- `:571-592`: pick the message per verdict.
  - Timeout with last types `[0]`: "Window N left fullscreen and is now a normal window on Desktop 1, still holding the pane. Go there and choose Move again; it will not leave fullscreen a second time."
  - not-visible or unknown: "Nothing changed: that window's Space was not on screen when the move started."
  - Remove "Leave fullscreen and try again".
- `:901-920`: add the last read's types, on-screen flag and bounds; timestamps for the toggle, the exit, and the first WINDOWED read; the display's current Space id; and whether the alert was shown.
- `:669`: rename the verdict to `refused-entered-timeout`. Grep the tests and `GUARD_VERDICTS` for the old string first.
- Docs:
  - Correct the claim "never pulled across Spaces" in the guard docstring (`:36-38`) and README:373. The exit itself moves the operator's view.
  - Update README:612 and README:619.

**B. Follow the pane on a last-pane move** (`bin/kitty-pane-menu`, the rc 0 branch after `equalize_tab_of`, `:1196-1199`)
- Act only when the source OS window is gone from a fresh `kitty @ ls`. Do not key on guard rc 0, because rc 0 also covers moves that were not the last pane.
- Wait until the source window id is gone from CGWindowList, at most about 2 s.
- Then run `kitty @ focus-window --match id:<wid>` and skip `refocus()`.
- Ordinary moves keep today's no-focus behavior. Amend the rationale at `:280-281`.
- It must run only after detach rc 0 and after the source window has closed. That avoids the README S4 correlates: kitty re-activated 5-15 ms before the close, and another fullscreen window reordered in the same millisecond.
- Never move this ahead of the guard or the detach. That would destroy a fullscreen source, which is the crash path.

**C. Survive the swipe-away** (`bin/kitty-fullscreen-guard:626-644`)
- After the toggle, require at least one on-screen WINDOWED read with bounds, and start the 1.0 s clock from it. That read shows the real window was put back in place, so the exit animation ended on the visible display.
- After that read, accept types `[0]` with on-screen false, as long as the bounds stay identical, for the rest of the hold and the confirming read.
- Keep refusing an empty Space list, several Spaces, and any type 4.
- The animation interval stays UNKNOWN. During it the window is ordered out while its type already reads non-fullscreen, up to 0.39 s early (`:33-35`). That is why on-screen cannot simply be dropped.
- It would have passed the 00:39:39 case: first on-screen WINDOWED read at about 19:39:40.69, swipe at 41.59, hold complete at about 41.7.
- The detach would then run on a desktop the operator is not looking at, so ship it together with B.
- Land it only after a trial on a throwaway kitty (the `repro/post-land.sh` harness).

**D. The structural fix: the patched kitty**
- The steps are in §2. It removes the toggle for on-screen fullscreen windows.
- It still shows the alert for off-screen and UNKNOWN reads, still needs B for the landing, and is blocked until the operator decides otherwise.

**E. Official kitty ≥0.50.0** has its recheck filed as backlog 64cd62f75524 (on or after 2026-11-02). It needs a new operator decision, and per README R4 no trial can clear it.

**Rejected options** (premise refuted, or they reopen the crash):
- Raising or load-scaling `AFTER_DEADLINE_S`. The exit is fast, the operator stays away, and the menu waits on the guard with no time limit (`:1004-1017`).
- Dropping on-screen entirely in `_after_toggle`.
- Going ahead with the move on a timeout.
- Toggling back into fullscreen after a refusal. It pulls the operator across Spaces, an enter never reads type 4 (`:33-35`), and it breaks the one-toggle rule (`:38`).
- Re-running the guard automatically in toggle mode. That is a second exit, as the 04:47:44Z and 05:07:37Z retries show.
- Tolerating small bounds changes.
- Telling the operator to press ⌃⌘F. On a window that is already windowed it re-enters fullscreen.

**Recommendation:** ship A and B now; neither touches the crash guard. Ship C after the trial. D only if the operator reverses the decision.

## 4. Open questions that need a throwaway kitty

1. Does `kitty @ focus-window` on a pane in a fullscreen window on another Space switch the display there? The "switch to a Space with open windows" setting (auto-swoosh) is at its default, on. What is the shortest safe delay after the source window leaves CGWindowList?
2. For C: after an on-screen WINDOWED read, swipe away, then detach, so the window closes on a background desktop. Over N trials, does the ordering probe confirm the exit animation finished before the close?
3. What does a windowed window on a desktop the display is not showing read for on-screen? So far this is inferred, not measured. The Mac has 3 displays; all 7 kitty windows are on display 1B6097CB at (−1358,−1440).
4. What causes the WINDOWED timeouts (menu 10-19T04:25:48; Close path 10-16T23:27 and 10-18T17:57): bounds changes, a Space bounce, or a confirming read that disagrees? This needs A's logging or a bounds trace.
5. If another kitty window sits on Space 44, does `cocoa_focus_last_window` pull the display back there after a background close? This bears on C.
6. Where does the display land after the patched kitty's deferred close?
7. Does an exit on a background Space switch the operator to that Space? This is still open in README:576 and README:611.
8. Which display does the osascript alert appear on (the 56 s unanswered alert at 10-19T04:25:58Z)? And who put the stranded windows back into fullscreen before the retries: the operator, or `bin/cc-resume-layout.sh:1045`?

Method: workflow wf_fad8a7f5-946 (5 investigation axes, each with an xhigh adversarial skeptic, then synthesis), 2026-10-19.
