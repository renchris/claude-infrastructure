# C2 skeptic (code and evidence lens): restore-command

Skeptic report, 2026-10-01, read-only. Each number is labeled **measured** (with the command) or **estimated** (with the method). UNMEASURED means not checked.

## Answer first

**No fatal flaw. Recommended conviction: 55 (dossier: 70).**

- **The forensic half holds up.** 8 of 10 key claims reproduce from disk: capacity, the "8 of 32" arithmetic, resurrections, keepalive stacking, the 6/core run and the `.start` bug.
- **Two claims are weaker than stated:**
  - Tombstones caught 18 of 32 at the kill, not 19.
  - The native "didn't finish" notice does **not** wake a session, which refutes one of the dossier's premises.
- **The nudge-delivery mechanism is now measured, not inferred.** A stale prompt sat in a composer for 23 min and was then submitted by an unrelated Enter.
- **Four design details would fail as specified:**
  1. The CoreGraphics fullscreen read-back mis-reads this Mac's notched display, and its retry would turn fullscreen **off**.
  2. cc-reaper would TERM the reboot-path `boot-resume.sh` after 600 s.
  3. The deaf-socket detector cannot tell a dead accept thread from a recoverable stall of 12+ min.
  4. The heartbeat's "keep the previous file if the count fell by more than 2" rule ratchets, so the roster goes stale.

Each one has a small fix, which is why none of them is fatal.

## Verdicts on the 10 key claims

| # | Claim | Verdict | Evidence |
|---|---|---|---|
| 1 | Round 1 admitted 10, then refused at 2.05/core and shed 22 | **stands** | Measured, by parsing idl.jsonl capacity-admit rows from 18:3x to 18:4xZ: 10 admits at 1.64 to 1.91/core, then refuse at 18:33:53Z, "load 20.49 on 10 cores = 2.05/core". The shed is at `cc-resume-layout.sh:249-252` (`shed=$((N - done_rows)); break`). The term switch is at `capacity-admit.sh:1250-1258`. Wrong cite: the C18 "TERM SWITCH, never a ceiling" rule is at `capacity-admit.sh:156`, not `:92-103`. |
| 2 | "8 of 32" = 10 launched minus 2 self-retired | **stands** | `teardown/16798199…json` mode=terminal, ts 18:33:14Z; `40ebc527` ts 18:33:39Z. sessions.log: `prompt_input_exit` at 13:33:17 and 13:33:42. `undelivered-1790879683.page`: "⏸ 8 not launched … already running". |
| 3 | 5 purposeful ends were resurrected; 4 are alive in panes 12-15 | **stands** (cause partly mis-attributed) | pane-spawns.jsonl resume-layout rows: p5→p12, p6→p13, p7→p14, p8→p15, p25→p39. `cc-registry/{12,13,14,15}.json` have kitty 48854 and live pids (`kill -0`). `6.json` = 90040b85. The cited `kitty-restart-supervisor.py:111-113` never ran a round (supervisor.log has 1 line). Round 3's resurrection came from `kitty-restart-resume.py`'s loop re-running `boot-resume.sh`, whose `--check-only` returns 0 for any sid with no live holder (`boot-resume.sh:461-466`). `grep teardown\|prompt_input_exit` over reso-resume-one, boot-resume.sh, boot-resume-launch.sh and the classifier returns 0 hits. |
| 4 | 1 of 31 prompts reached a transcript; text+CR in one write does not submit | **stands, and the mechanism is now measured** | Re-run over the 32 roster transcripts: **2** files now hold "kitty was restarted at 13:29". The second, 13d7be20, is a `queue-operation enqueue` at **19:12:56.834Z**. Its content is the recovery prompt, then `\n`, then the keepalive NUDGE (917 chars). `~/.reso/keepalive.log` shows "nudged idle kitty:32" at 14:12:56 local, the same second. So the 18:50:00Z `send-text prompt+"\r"` left `prompt\n` in the composer (the CR became a newline), and the keepalive's text plus separate `\r` (`reso-keepalive:236-238`) submitted both 23 min later. Kitty source: `rc/send_text.py:121-124`, bracketed paste is off by default. |
| 5 | Title-matched fullscreen failed 12/12; `toggle_fullscreen` by id returned rc 0 on 8/8 | **stands** (counts) | `state/last-layout.txt`: 12 × "read back: nomatch" (3+1+7+1). finish.log: 8 × "rc=0". Source answers the dossier's open question: `rc/action.py:61-69` sets `window` to the **matched** window and `boss.toggle_fullscreen` (`boss.py:1351-1356`, v0.48.2, `cmp` identical to the tag) uses `window_for_dispatch`'s OS window. Caveats: the 8 were never read back; plan:39's "verified on 4" is a different set (`inboot-finish.py:37,75` skips OS windows that existed before it ran). Separately, the plan's mechanism ("Claude overwrites the title") is refuted by source: a non-temporary `set-window-title` sets `override_title`, and child title changes are ignored while it is set (`window.py:1291-1296, 1535-1539`). Likelier causes are the two the plan also lists: an ambiguous `process "kitty"` (2 kitty processes) and AX enumerating only the current Space. |
| 6 | Tombstones caught 19 of 32 at the kill; 13 missing all had pane ids ≤ 24 | **weakened** | Measured (python over `shutdown-tombstones/*.json`, `endedAt` in 13:29:20-13:30:00): **18** of 32. The 19th is d86e6bd4's later tombstone (endedAt 13:54:44, kitty 48854, pane 39). **14** are missing, and d86e6bd4 was **pane 75** in kitty 610, so "all ≤ 24" is false. The loss is skewed by account: quaternary 10 of 14 missing, tertiary 3 of 13, next 1 of 5 (cause UNMEASURED). sessions.log at 13:29:3x shows 32 × `reason=other` (reproduced). The conclusion that a heartbeat roster is needed stands. |
| 7 | The native notice hit exactly 10 sessions; a naive rule flags 24; calibrate WAKE-LOST to the 10 | **weakened** | The 10 reproduce exactly (scan of post-18:29Z records for `<status>stopped</status>` plus "finish before the previous session ended"). The dossier's corollary, "background shells are already reported natively and wake the session, as 16798199 did", is **refuted**. 7 of 10 (68691067, 89bdedfa, 90b6aee4, f8b54aee, aee9bc26, dcbd2f8e, f4c84c9d) have **no assistant record after the notice**. 16798199's turn came after a peer-mail notification at 18:32:40Z, 09c26b2b's after an operator message, and d86e6bd4's after peer mail. So the oracle covers only the half (shells) that Claude Code detects but does not act on. Nothing calibrates Monitor, subagent or workflow detection. The "24" was not re-run (UNMEASURED by me). |
| 8 | 3 keepalives and 5 pages from stacked runs | **stands** | keepalive.log has "started" at 13:34:05, 13:37:20 and 13:44:51, and 5 `undelivered-*.page` files exist. Addition: **2 are still live now**: pid 94882 (13:37:20) and pid 217 (13:44:51). Both have `CC_KEEPALIVE_MARKERS=…/agent-context-sync` (`ps eww`), and both nudged pane 32 at 14:12:56 and 14:13:26. cc-reaper.log has `TERM orphan-bash … reso-keepalive 240` at 18:47:26Z (age 717 s), which is likely the third one. |
| 9 | Ceiling 6/core admitted 25/25, peak 3.28/core, 12.7 s per launch | **stands** (but the 6 is not calibrated) | idl rows 18:38:56Z to 18:44:12Z: 25 admits, max 3.28, reclaimable ≥ 34.45 GB; 316 s / 25 = 12.6 s. The ceiling never bound (peak 3.28 < 6), so this run is no evidence for 6 over 3.5. It was a post-kill box, not a boot storm. |
| 10 | The `.start` bug persists | **stands** | Re-run: `tr -d '[:space:]' < ~/.claude/autonomy/reboot-2026-10-01.start` ⇒ `17908780611790878061kalloc1024_gb=1.12`. Writer at `alarm-reboot-prep.sh:52`, reader at `boot-resume.sh:298-299`. `git log -S'kalloc1024_gb='` ⇒ 200827256. |

## Design claims that fail against code or live state

1. **The CG fullscreen read-back mis-reads the built-in display, and its retry would undo good work.**
   - Measured with Swift `CGWindowListCopyWindowInfo` and `NSScreen.screens`, read-only, no socket:
     - The built-in screen frame is 1728×1117.
     - **9** of kitty 48854's large windows sit at `0,37 1728×1080`.
     - **2** sit at `-63,-1050 1680×1050`, which is exactly the external screen frame.
   - On the notched display, fullscreen content sits below the 37-pt notch band. Its bounds therefore never equal the screen frame, and they match a zoomed window's bounds.
   - So the §2.4 rule "must equal a screen frame" reads all 9 as failures, and the step-4 retry (`toggle_fullscreen` again) would **leave fullscreen**.
   - Use a Space-aware check instead, such as AX `AXFullScreen` on `AXUIElementCreateApplication(<new kitty pid>)`, which also removes the `process "kitty"` ambiguity.
2. **Interleaving fullscreen with launches is untested.** §2.4 toggles each window before the next `launch --type=os-window`. Today every toggle ran after the layout had finished (`inboot-finish.py:64-90`), and the shipped layout fullscreens at the end on purpose (`cc-resume-layout.sh:290`). How a new OS window behaves while a fullscreen Space is active is UNMEASURED.
3. **cc-reaper would kill the reboot-path restore.**
   - The rule: `orphan-bash` is a launchd-parented `bash` older than 600 s whose argv misses `GARBAGE_WL` (`bin/cc-reaper:933`, list at `:713`). `boot-resume` is not on the list.
   - The plist execs `taskpolicy -c utility …/boot-resume.sh` (`plutil -p …boot-resume.plist`), so the job's process is `bash` with ppid 1.
   - The C2 reboot run is a start gate of up to 10 min plus about 7 min of launches, well past 600 s.
   - cc-reaper is loaded (`launchctl list`), with **96** orphan-bash TERMs today, including a reso-keepalive at 717 s.
   - The crash path survives only by accident: its argv `--kitty-pid` contains the whitelisted word `kitty`.
   - The dossier knew this rule (it chose Python for `cc-restore`, `kitty-restart-resume.py:19`) but did not apply it to `boot-resume.sh`. The fix is one line in GARBAGE_WL.
4. **The deaf-socket detector cannot tell "dead" from "slow".**
   - The design pages after a backlog of ≥ 120 on 2 ticks (5 min).
   - recycle-unreachable-2026-10-01.md:87 measured **recoverable** deaf episodes "up to more than 12 min".
   - With the opt-in auto-restart, the tick would end 32 live sessions during a stall that would have cleared on its own.
   - The discriminator that was actually measured is the thread list: `sample <pid>` showing no `KittyPeerMon` (husk-panes-2026-09-30.md:89).
5. **The heartbeat rule ratchets.** "Keep the previous file if the row count fell by more than 2" (ported from `kitty-restart-resume.py:229`, where it guarded a 15-min window) never records a drop of 3 or more within one tick until the fleet grows back. As a standing 5-min heartbeat it keeps closed sessions on the roster, and they come back after a crash or reboot unless the retire filter catches them (frequency UNMEASURED).
6. **The retire filter leaks on both legs.**
   - Teardown markers are deleted by `gc_teardown_marker` (`hooks/lead-crash-watchdog.sh:680-697`) once a death is handled.
   - A self-close can end as `reason=other`, not `prompt_input_exit`. d86e6bd4 retired at 18:51:38Z (marker) and its session ended `reason=other` at 13:54:44 (sessions.log), which also wrote a tombstone that looks like a shutdown.
   - The launched-once ledger covers only rounds within one event.
7. **The nudge send is mis-described.**
   - The keepalive sends **no** `^U`. Its kitty arm is text, 0.5 s, `\r`, 0.3 s, `\r` (`reso-keepalive:236-238`; `:231-233` is the iTerm2 arm).
   - A `^U` would likely clear only the last line of a multi-line composer such as 13d7be20's `prompt\n` (UNMEASURED).
   - The verified paste (`handoff-fire.sh:4070`) returns HOLD (rc 3) on any non-empty composer, and resumed panes can start non-empty: pane 35 held kitty's terminal replies (handoffs.jsonl `recycle-held-draft` 18:47:46Z, reproduced).
   - Its own population shows about 6% mangled (`handoff-fire.sh:4042-4044`).
8. **The timing estimate leaves out the lands wait.** `cc-restore` ports the wait for in-flight lands (up to 4 h). Today it alone took 13.6 min (run.log 13:15:47 to 13:29:22), on top of the "about 10 min".
9. **Smaller line drifts:** the effort default is at `reso-resume-one:392` (the dossier says `:384`; `CC_RESUME_EFFORT` already exists). The 5-column `read` at `boot-resume.sh:455` must also change for columns 6-7.

Checked and confirmed:
- `boot-resume.sh` cites (`:217, :220, :238-239, :285-290, :298-299, :359, :505, :548-566, :615, :649`) and `cc-resume-classify.py:494` (`print(row + "\t" + verdict)`).
- `kitty.conf` does not set `macos_traditional_fullscreen`, so fullscreen uses native Spaces.
- The `it2` wrapper diverts to kitty only when kitty is a verified ancestor, so a heartbeat run under launchd plausibly makes no kitty-socket calls. The dossier's grep for `kitten|kitty @` alone did not prove this, because `cc-sessions:182-202` calls `it2 session list`.

## Live hazards measured now (reported, not touched)

- **Unsubmitted prompts get submitted by the next Enter.** This is now measured: 13d7be20 received the 18:50Z prompt at 19:12:56Z. The other 29 composers may still hold one (UNMEASURED: it needs `get-text`).
- Two stacked keepalives (pids 94882 and 217) still nudge pane 32 every 240 s each.
- The duplicate 3a06361f in pane 13 shares film-mvk with 90040b85 in pane 6. Panes 12 to 15 hold resurrected sessions.

## Probes

- 0 of 3 `kitten @` calls.
- No tmux server started.
- No process signaled.
- Network: read-only fetches of kitty v0.48.2 `rc/action.py`, `rc/set_window_title.py`, `rc/send_text.py`, `rc/base.py` and `boss.py`.
- Scratch files in `/tmp/sd-skc2/`.
