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

---

# Second pass (same lens, re-run 2026-10-01 about 15:00-15:20 CDT)

The first pass above was committed in 55753e737, and the workflow asked for this report at the same path. The never-overwrite rule applies, so this pass is **appended**. Where the two passes disagree, this one says so. Every number is measured with the command named; anything else is marked UNMEASURED.

## Answer first

**No fatal flaw. Recommended conviction: 50** (first pass 55; dossier 70).

The forensics reproduce again. Five findings are new and bear on the design:

1. **Main has moved under the dossier.**
   - ba04df7b3 landed at 14:23, after the dossier was written. It is not on this branch.
   - It already ships a retire filter in `boot-resume.sh`, keyed on modes `terminal|successor`. It states that "`recycle` … is not a retirement".
   - C2 §2.2 specifies `terminal|recycle`, which is the opposite rule for recycle.
   - Live IDL rows carry `retired_skipped` from 19:45:52Z on.
2. **Nothing serializes two restores.** The tick's dead-kitty detector would start a second, parallel restore during every `cc-restore --restart-kitty`.
3. **The reboot roster order prefers a stale source.** C2 reads the alarm roster first, and that roster may be up to 24 h old, ahead of a 5-minute heartbeat.
4. **The tombstone baseline does not exist.** The hook landed after the 09-30 reboot. Today's 18 of 32 is the only mass-kill measurement, and the misses cluster on panes that `cc-resume-layout.sh` made. Those are exactly the panes a C2 restore creates.
5. **Transcript confirmation cannot tell "landed" from "acted".** A better nudge path exists that the dossier missed: `claude -r <sid> "<prompt>"` at launch.

## Verdicts on the 10 key claims (this pass)

| # | Verdict | Evidence (re-run now) |
|---|---|---|
| 1 Load term refused 11th at 2.05/core; tail of 22 shed | **stands** | idl.jsonl capacity-admit rows parsed: 10 admits 18:31:44Z to 18:33:40Z at 1.64 to 1.91/core, refuse 18:33:53Z "2.05/core > ceiling 2.0/core (refusal 1 of budget 3)". `cc-resume-layout.sh:250-252` shed; `capacity-admit.sh:1250-1258` switch. The C18 cite is wrong: `:92-103` is the env list, and the rule is at `:150-160`. |
| 2 "8 of 32" = 10 − 2 self-retired | **stands** | `undelivered-1790879683.page` reads "⏸ 8 not launched … already running". sessions.log shows `prompt_input_exit` at 13:33:17 and 13:33:42. Teardown markers have mode terminal, ts 18:33:14Z and 18:33:39Z. |
| 3 5 resurrections; 4 alive in p12-15 | **stands, now 3 alive** | pane-spawns: p5→12, p6→13, p7→14, p8→15, p25→39. `cc-registry/12.json` pid 71342 is now dead (`kill -0`); 13, 14 and 15 are alive on kitty 48854. |
| 4 1 of 31 prompts landed; one-write text+CR does not submit | **stands; now 3 of 31 have landed late** | `grep -l 'kitty was restarted at 13:29'` finds d86e6bd4 (enqueue 18:51:40Z), 13d7be20 (enqueue 19:12:56Z) and **5fb8968b, a user record at 20:14:21.611Z**, 2 h 24 min after the send. It is the bare 690-char prompt, and the reply is "You've hit your weekly limit · resets Oct 4". kitty `rc/send_text.py` `--bracketed-paste` defaults to `disable` (confirmed). The cause is the single-write burst, not the bracketed-paste setting itself. |
| 5 Title fullscreen 12/12 nomatch; toggle by id rc 0 on 8/8 | **stands** | `grep -c 'read back: nomatch' state/last-layout.txt` → 12; `grep -c 'fullscreen os-window .*rc=0' finish.log` → 8; `boss.py:1350-1356` and `glfw.c:1374-1382` (native Space) confirmed in /tmp/kittysrc. |
| 6 Tombstones 19 of 32 | **weakened** | **18** in 13:29:20-13:30:00, all `kitty_pid` 610. The basis "On 09-30 the same mechanism caught 19 of 20" is **wrong**: `git log -S'SHUTDOWN TOMBSTONE'` → 2d0b45bc9, 2026-09-30 **18:16**, after the 15:25 reboot. The earliest tombstone on disk is 09-30 19:2x. The `session-deregister.sh:65-71` comment counts SessionEnd log lines, not tombstones. |
| 7 Native notice in exactly 10; naive rule 24 | **stands** (for the 18:29Z-19:00Z window) | The same 10 reproduce. An 11th (13d7be20, 20:00:12Z) comes from a later relaunch. 6 of the 10 have no assistant record after the notice, which agrees with the first pass that the notice does not wake a session. The "24" was not re-run (UNMEASURED). |
| 8 3 keepalives, 5 pages | **stands** | keepalive.log "started" at 13:34:05, 13:37:20 and 13:44:51; `ls undelivered-*.page` → 5. Update: cc-reaper has since TERMed both survivors. cc-reaper.log: `orphan-bash pid=217 age=2256s` at 19:24:51Z and `pid=94882 age=2707s` at 19:38:39Z. |
| 9 6/core: 25/25, peak 3.28, 12.7 s/launch | **stands** (ceiling never bound) | Rows 18:38:56Z to 18:44:12Z: max 3.28/core, reclaimable min 34.45 GB; 316 s / 25. |
| 10 `.start` bug persists | **stands** | `tr -d '[:space:]' < reboot-2026-10-01.start` → `17908780611790878061kalloc1024_gb=1.12`. Writer `alarm-reboot-prep.sh:52`, reader `boot-resume.sh:298-299`. |

**Correction to the first pass:** `reso-keepalive:231-233` **is** the kitty arm (`"$KT" session send`). The iTerm2 arm is `:217-219` (grep on this branch and on the live checkout). The dossier's cite was right, and the first pass's `:236-238` was wrong. The point that no `^U` is sent stands.

## New design defects found against code

1. **The retire rule conflicts with landed code, and C2's own rule has a hole.**
   - ba04df7b3 skips `terminal|successor` markers newer than the last user/assistant record, and resumes `recycle`. Under it, 3a06361f (marker `recycle`, 18:36:16Z) would still come back as a duplicate of 90040b85.
   - C2 drops recycle because "its successor … has its own roster row". That is false for the 5-minute heartbeat: a recycle inside the window leaves only the old sid in the roster.
   - The successor then returns only if its tombstone landed, and only 18 of 32 did.
   - The rule has to be reconciled with main (resolve the successor sid from handoffs.jsonl `recycle-engaged`) before W3.
2. **No lock in the chain.**
   - `grep -n lock` finds none in `boot-resume.sh` or `cc-resume-layout.sh`.
   - `reso-resume-one` has no per-sid lock (`spawn … --resume $sid`, `:560`).
   - `--check-only` (`boot-resume.sh:463`) refuses only a sid with a live holder.
   - So after `cc-restore` kills K, the next tick (≤300 s) sees K dead, and no `events/K.done` exists, because §2.6 item 4 writes it only at shed=0 or the deadline. It starts a crash restore with its own ledger, racing the planned restore on every row not yet registered.
   - Results: duplicate `claude --resume` of one sid, and a second `toggle_fullscreen` that turns fullscreen **off**.
   - A manual `/resume-sessions` after a crash races the same way.
   - Fix: `cc-restore` writes `events/K.inprogress` before the kill, plus a `mkdir` lock in boot-resume.
3. **The reboot order prefers a stale roster.**
   - `alarm-reboot-prep.sh:19` says "reboot within 24 h of the alarm".
   - Today's `reboot-2026-10-01.roster.json` (32 rows, `.start` 13:07:41, kitty 610) would be read first at a reboot tonight once the `.start` fix lands.
   - It would win over a 5-minute heartbeat. Sessions started since 13:07 would be lost, and the 5 retired ones offered again.
   - The `.start` bug is the only thing keeping it out today.
   - Pick the source with the newest `.start`, or take the union.
4. **The strict `<` drops the heartbeat in one crash case.** `boot-resume.sh:300` requires `st < BOOT`. With no tombstones and no `.ips` (a SIGKILLed or hung kitty writes no crash report), the anchor equals `hb.start` and the heartbeat roster is rejected.
5. **Tombstones fail on the population C2 creates.**
   - 12 of the 14 panes that `cc-resume-layout.sh` made in kitty 610 on 09-30 (20:48-20:56Z, pane-spawns.jsonl) left no tombstone. Only 2 of the 18 other panes missed.
   - I ruled out the register/deregister address asymmetry for live layout panes. Register `:173` falls back to `KITTY_WINDOW_ID` and deregister `:47` does not, but `ps eww` on pids 20276, 71342, 75541 and 50818 shows `ITERM_SESSION_ID=w0t0p0:<wid>` set, so `:47` resolves.
   - Cause UNMEASURED.
   - Implication: after the first C2 restore, the heartbeat is the primary crash and reboot source, not one leg of a union.
6. **Transcript confirmation is not proof of effect.** 5fb8968b shows a user record that lands while the account is at its weekly limit. §2.7 step 4 would log success. Confirm on a non-error assistant reply, and skip limit-hit accounts.
7. **A safer delivery path was missed.**
   - The CLI reference lists `claude -r "<session>" "query"` ("Resume session by ID or name", code.claude.com/docs/en/cli-reference).
   - The classifier runs before launch (`boot-resume.sh:480-487`), so the WAKE-LOST text is known at spawn time. It could be passed through reso-resume-one's `spawn` line, with no typing into a live pane and no composer race.
   - It also sidesteps the addendum's classifier refusal of agent send-key.
   - Whether the large-session dialog in reso-resume-one's expect block tolerates a positional prompt is UNMEASURED.
8. **cc-reaper versus the reboot path (first pass, now with the timing).**
   - The plist execs `taskpolicy … boot-resume.sh`, so the process is `bash` with ppid 1.
   - `cc-reaper:918,933` TERMs such a process after 600 s unless its argv matches `GARBAGE_WL` (`:713`), and boot-resume is not on that list.
   - The 17-min 09-30 run survived only because no garbage sweep fell between 20:25:27Z and 20:59:10Z (cc-reaper.log).
9. **The heartbeat takes the iTerm2 branch under launchd** (latent).
   - Without `KITTY_WINDOW_ID` or `CC_TERM`, `bin/it2:111-112` keeps the iTerm2 path.
   - If iTerm2 is ever running, `cc-sessions:202-205,326-327` marks every kitty row stale, and `:329-336` deletes rows older than 24 h (`:276`).
   - It is safe today only because iTerm2 is not running (`pgrep -x iTerm2`). The clean-env snapshots today still returned 32 (run.log).

Checked and confirmed this pass:
- `boot-resume.sh:217,220,237-241,285-290,455,463,505` (`open -a kitty` by name) and `:548-566`.
- `cc-resume-layout.sh:117,177-190,232-237,250-252,290-309`. `:378-391` prints X and Y only, so the read-back needs width and height added.
- `capacity-admit.sh:1398-1420`; `cc-resume-classify.py:12-25,116-120,154-158,494`; `handoff-fire.sh:4070,6992`; `reso-resume-one:173,392`.
- All 32 live sessions run `--model claude-opus-5-5 --effort high` (`ps -o args=` tally), so after one restore the argv carries only the launcher's defaults.

## Missed risks (not in the dossier)

- C2 must merge with ba04df7b3 (the recycle semantics differ). As written, the change list would conflict.
- Concurrent restores (tick versus `cc-restore`, tick versus a manual resume) with no lock.
- A stale alarm roster outranks the heartbeat at reboot.
- The crash anchor can equal `hb.start` and void the heartbeat roster (`:300`).
- After the first restore, tombstones are least reliable on restored panes.
- Nudges into accounts at their weekly limit are "confirmed" but inert. 5fb8968b's quaternary account is out until Oct 4.
- Stale composer prompts keep firing hours later: 3 of 31 so far, the latest at 20:14:21Z.
- WAKE-LOST re-pings sessions that were idle at the crash. The 08-24 ruling (`cc-resume-classify.py:23-25`) says idle sessions are not re-pinged, so the dossier's "keeps the ruling" needs an operator ruling, not an assertion.

## Probes (this pass)

- 0 of 3 `kitten @` calls. No tmux server. Nothing signaled.
- Read-only `ps eww` and `ps -o args` on live claude pids; `netstat -anv -f unix` (Recv-Q 0 on `/tmp/kitty-48854`).
- 1 WebFetch (Claude Code CLI reference).
- Two scratch files in /tmp, created and deleted.
