# Map: the in-session self-close path, and why pane 289 got rc70 (2026-10-24)

Read-only mapper. Code at worktree HEAD 7cdb9adae. Log times are UTC (Z). Local file mtimes are CDT (UTC-5).
Every number below is labelled **measured** (with the command) or **estimated** (with the method).

## 1. Verdict in one paragraph

The guard was **right at the time**. It did not read the wrong window, and its state was not stale. At 23:53:36Z and again at 23:53:38Z, kitty window 289 really was the only pane (`panes:1`) of OS window 25 (platform window 18565). That window was in native fullscreen (Space types `[4]`) on a Space that was off screen. The "3 panes, not fullscreen" view came **later** and has two causes:

- **The 3 panes:** the placement policy split new sessions into OS window 25 around the husk: 293 at 00:16:58Z, 295 at 00:24:52Z, 296 at 00:26:51Z. Pane 293 then closed at 00:51:05Z, which left 289, 295 and 296.
- **"Not fullscreen":** this is refuted by measurement. At about 01:55Z the guard's own CGS reader still reads platform window 18565 as `FS types=[4] onscreen=False`. So does every other kitty OS window. No toggle row exists for OS window 25 after 23:53Z.

The real defect is in the design, not in the read:

- The self-close path treats `refused-fs` as "a fixed fact no retry changes" (`scripts/handoff-fire.sh:1872-1878`, `:11816-11822`). In fact it is a fact about the window's pane count, and that count changes.
- After refusing, the watcher hands the pane to a closer whose gate 4 (dirty cwd, `bin/cc-pane-close:511`) runs **before** its fullscreen gate (`:520`). So once the fullscreen condition went away (00:16:58Z), a different gate blocked the close forever: 138 changes, all from sibling sessions in a shared checkout.

## 2. The path, step by step (file:line)

Foreground: `handoff-fire.sh self-close --terminal --allow-dirty`, inside the session.

1. Arm loop, `scripts/handoff-fire.sh:15859-15893`. It detaches the watcher `__selfclose` into `/tmp/handoff-selfclose-<pane>-<epoch>.log` (`SC_LOG`, `:15645`; detach at `:15863`). Then it waits for the heartbeat (`await_armed`) and for pane proof (`await_pane_proof`). Proof rc 2/3 re-arms up to `CC_SELFCLOSE_NOANSWER_ARMS` (3) times (`sc_noanswer_wait`, `:2286-2296`). Nothing is typed until the pane is proven.
2. Tenant gate, then the close records are committed (`sc_commit_close_records`) and the teardown marker is written (`:15894-15917`).
3. `/exit` is typed through `as_write`, up to 3 tries (`:15919-15922`), followed by a best-effort empty CR (`:15928-15929`). The foreground then **exits 0** (`:15931`). From here on, **the session has no further part in the close.** The `/exit` kills its turn, and it never learns whether its pane closed.

Detached watcher (`__selfclose`, `scripts/handoff-fire.sh` about `:11740-11930`):

4. Grace loop: up to `HF_SELFCLOSE_GRACE_S` = 180 s in 5 s steps. It breaks as soon as `cc_alive` is false (`:11746-11748`). Under kitty, every 20 s it presses at most one exit-dialog key (`sc_exit_unblock`, `:11749-11760`).
5. Close-instant checks:
   - Successor pin re-verify (`:11785-11804`). This is skipped for `--terminal`.
   - Tenant-mismatch abort (`:11827-11830`).
6. Retry loop, at most 4 attempts with 2 s between them (`:11832-11859`). Each attempt:
   - First, `pane_enumerated` = absent means the pane was already closed from inside, so the attempt counts as success (`:11839-11842`).
   - Otherwise it calls `hf_close_pane "$SID" self-close self` (`:11850`).
   - **rc 3 = FS-GUARD stops the loop after attempt 1** (`:11854-11857`).
7. `hf_close_pane` (`:1879-1935`):
   - mode `self` skips the ownership guard.
   - It runs `hf_bounded $IT2_SHIM session close -f -s <id>` (`:1904`).
   - It then **verifies** with `kt_window_field <id> id` (`:1910`). Empty output means `closed`; a failed query means `unverified`; anything else means `STILL-PRESENT`. A non-zero transport rc appends `-rc<n>` (`:1912-1918`).
   - It writes a row to `~/.claude/logs/close-attrib.jsonl` (`hf_close_attrib`, `:1919`, `:1940ff`).
   - `STILL-PRESENT-rc70` and `unverified-rc70` both return 3 (`:1932`).
8. `kt_window_field` (`:1775-1798`) is one `kitty @ ls` walk across os-windows, tabs and windows. It matches on window id, which is a global kitty id and not per-OS-window, so it cannot read "the wrong window". It returns 1 only when the query fails.
9. The it2 shim close arm, `bin/it2-kitty` about `:1560-1688`, runs these gates in order: the identity pin (66/68), then the composer guard (67, `:1617-1641`), then **the fullscreen guard** (`:1643-1684`). The fullscreen guard calls `kitty-fullscreen-guard --window N --mode refuse --scope pane --tool it2-kitty`. Its stderr containing `refused (refused-fs)` maps to **exit 70** (`:1680`). Any other non-zero result maps to exit 1. If it passes, `kitty @ close-window --match id:N` runs (`:1686`).
10. `bin/kitty-fullscreen-guard` `decide()` (`:744-806`):
    - The kitten query returns `last_for[scope]`. False gives `safe-not-last`, rc 0 (`:767-768`).
    - True leads to `_refuse_mode()` (`:653-663`), which reads the CGS Space types. FS gives `refused-fs`, rc 3. WINDOWED held for 1.0 s gives safe.
    - Relaxing a refusal requires fsfix or a relax policy **and** `onscreen=True` (`relaxed_rc`, `:736-741`). Pane 289 had `onscreen=False`, so **no policy setting would have let it close**.
    - Each verdict writes one row to `kitty-pane-actions.jsonl` (`:967-990`).
11. Failure arm (`handoff-fire.sh:11860-11920`):
    - It re-reads the tty (`pane_cc_state`, `:11888`). `shell` plus rc 3 gives `husk-fs` (`:11898-11903`).
    - `hf_alarm` writes a record to `~/.claude/handoff-alarms/` and posts one OS banner. husk-fs is deliberately **not** re-paged (`:10357-10362`).
    - `hf_husk_row <pane> guard-fullscreen <tty>` (`:2251-2261`) writes a `husk` row to the pane-close queue. `scripts/pane-close-retry.sh` then drives that row through `bin/cc-pane-close`.
12. A parallel closer races the watcher. `bin/cc-pane-runner` is the pane's own process. When claude exits 0 it runs the same guard and, on refused-fs, writes its own `guard-fullscreen` husk row (`bin/cc-pane-runner:300-335`). In every rc70 episode, the cc-pane-runner refusal comes 0-6 s before the watcher's refusal (section 4).

Flags:

- `--terminal` declares end-of-line. It only skips the successor pin and focus hand-over; it has no effect on the close mechanics.
- `--allow-dirty` relaxes only handoff-fire's own pre-close dirty check (documented at `:348`). **It is not carried into the husk row** (`hf_husk_row` passes only reason, tty, producer and kitty_sock/pid, `:2253`). So `bin/cc-pane-close` gate 4 re-judges the same cwd with no waiver. That is the pane-289 hand-off failure.

## 3. Pane 289 timeline (all measured)

| ts (Z) | source | event |
|---|---|---|
| 23:17:53 | pane-spawns.jsonl | pane 287 split into os_window 25, anchor 13, panes_before 1 |
| 23:23:13 | pane-spawns.jsonl:5706 | **pane 289** split into os_window 25, anchor 13, `panes_before:2` (3 panes) |
| 23:30:21 | kitty-pane-actions.jsonl:1439 | 287 closed by cc-pane-runner, `safe-not-last panes:2`. Pane 13 had already left; it has no guard row on 10-24, so the path that removed it is unattributed |
| 23:53:22 | /tmp/handoff-selfclose-289-1792885988.log | watcher armed (pid 31607), pane proven, `close sid=289 kind=terminal` |
| 23:53:36 | ~/.claude/run/pane-exit/289.json `ts:1792886016` | claude exited rc 0, 14 s after /exit |
| 23:53:36.772 | kitty-pane-actions.jsonl:1441 | guard (caller cc-pane-runner): `os_window_id:25 platform_window_id:18565 panes:1 state:FS types:[4] onscreen:false verdict:refused-fs` |
| 23:53:38.874 | kitty-pane-actions.jsonl:1442 | guard (caller it2-kitty, i.e. the watcher): the identical verdict |
| 23:53:38 | close-attrib.jsonl:1256 | `site:self-close mode:self id_requested:289 verdict:STILL-PRESENT-rc70` |
| 23:53:39 | handoff-alarms/alarm-20261024T235339Z-31607-1516.json | `class:husk-fs address:role:desk paged:os-banner`. The watcher log says `push=refused-rc3` |
| 23:53:39 | watcher log | `→ pane 289 handed to the pane closer (reason guard-fullscreen)` |
| 23:55:00 | pane-say.jsonl | lead-crash-watchdog: `7555024a ended cleanly … prompt_input_exit` and `warn uncommitted work in personal` |
| 00:00:13 → 01:33:14 | pane-close.jsonl:394-402 | 9 refusals: `/Users/chrisren/Development/personal holds 138 uncommitted change(s)` |
| 00:16:58 | pane-spawns.jsonl | pane 293 split into os_window 25, `panes_before:1`. **From here on the fullscreen guard would have passed** (not last pane) |
| 00:24:52 / 00:26:51 | pane-spawns.jsonl | 295 and 296 split into os_window 25 (panes_before 2 and 3) |
| 00:51:05 | kitty-pane-actions.jsonl:1448 | 293 closed, `safe-not-last panes:4`, leaving 3 panes (289, 295, 296) |
| …01:38:50 | pane-close-retry.log:25912-25936 | husk attempts 17-21. Attempts that ran into the closer's 60 s bound end `rc=124 with no output` |
| 01:45:55 | pane-close-retry.log:25942 | `its tty was typed in since — the operator owns it; row removed, never closed` |
| ≤01:49:31 | `ps -t ttys046` | ttys046 had been reused by a new pane (login started 20:49:31 CDT = 01:49:31Z), so pane 289 was gone by then. No close-attrib, kitty-pane-actions or pane-close row records who closed it |
| ~01:55 | `kitty @ ls` (read-only) | os_window 25 now holds only windows 295 and 296. Window 289 is absent |

## 4. Fourteen-day counts (window: ts ≥ 2026-10-11T00:00Z, through 2026-10-25 ~01:55Z)

Measured with `python3 -I` over `~/.claude/logs/close-attrib.jsonl`, `kitty-pane-actions.jsonl`, `pane-close.jsonl`, `pane-close-retry.log` and `~/.claude/handoff-alarms/alarm-*.json`. Episodes are consecutive rows for the same pane within the same hour.

- close-attrib rows: 106, all `site:self-close`, in 82 close episodes.
- Verdicts:
  - closed 29
  - closed-rc1 18
  - closed-rc67 17
  - **STILL-PRESENT-rc1 16**
  - **STILL-PRESENT-rc70 10**
  - **STILL-PRESENT-rc67 8**
  - unverified-rc124 7
  - closed-rc124 1
- **rc70 rows: 10, in 10 episodes. All 10 ended as husks (10/10, 100%).** Claude was gone and the pane stayed at a shell:
  - 9 got the alarm class `husk-fs`.
  - Pane 165 got `close-failed-unknown` because its tty read failed. However, cc-pane-runner's own refused-fs row (13:01:15Z) proves claude had exited, so it was a husk too.
- **STILL-PRESENT rows: 34, in 16 episodes. 14 of the 16 were husks (87.5%):**
  - 10 rc70 episodes.
  - 3 rc1 episodes on 2026-10-16 (panes 55, 80, 181). These were `refused-fs` before exit 70 existed, so each was retried 4 times: kitty-pane-actions shows 4 it2-kitty refused-fs rows per pane.
  - 1 rc1 episode (pane 170, 2026-10-20) was `refused-unknown` on a last pane, giving alarm `husk-pane`.
  - The other 2 (rc67, panes 201 and 16) were `close-failed-live`: the composer guard refused because claude was still running, so they were not husks.
  - **So all 14 husk episodes in the STILL-PRESENT set were fullscreen-guard refusals on the last pane of an OS window.**
- How each rc70 husk ended (measured, kitty-pane-actions plus the retry log). The closer is `bin/cc-pane-close`. "Operator ⌘W" means a kitty-confirm-close row.

| pane | refused at (Z) | how it ended | husk time |
|---|---|---|---|
| 210 | 10-16 22:20 | operator ⌘W at 00:23; the first ⌘W got refused-timeout | 2h03m |
| 149 | 10-20 09:30 | operator ⌘W at 18:59 | 9h29m |
| 363 | 10-21 09:25 | no later row within 30 h | unknown |
| 476 | 10-21 18:56 | no later row within 30 h | unknown |
| 54 | 10-22 01:26 | operator ⌘W at 02:18 | 52m |
| 56 | 10-22 01:56 | operator ⌘W at 02:17, after panes were added (panes:3) | 21m |
| 165 | 10-23 13:01 | closer refused 14 times (refused-fs); operator ⌘W at 21:17 once panes:2 | 8h16m |
| 280 | 10-24 21:32 | closer at 22:36, after 282 was placed into window 25 (panes:2) | 1h04m |
| 282 | 10-24 22:41 | closer at 23:27-23:30, after 287 and 289 were placed (panes:3) | ~46-49m |
| 289 | 10-24 23:53 | closer blocked at gate 4 (dirty); gone ≤01:49:31Z, closer unattributed | ≥1h52m |

**Estimated** (from the eight rows with an end time; 289 counted at its ≥1h52m floor): median husk time ≈ 1h28m, or 1h04m without 289; range 21m-9h29m.

**Measured:** OS window 25 produced three rc70 husks in a row on 10-24 (280, 282, 289).

## 5. Why the husks happen: ranked by evidence

1. **The terminal pane in an OS window cannot self-close while it is the only pane.**
   - This is by design. The guard protects against the 2026-10-15 kitty crash precondition, and stock kitty runs with fsfix=false and policy block-stock (every guard row).
   - The guard needs the window **on screen** to relax, and fleet windows sit on background Spaces. Pane 289 had `onscreen:false`.
   - The self-close path has **no step that makes the pane non-last** before closing it. It never leaves fullscreen, moves the pane, or merges windows. The watcher only refuses, banners, and queues a row.
2. **The "fixed fact" assumption is false.**
   - `handoff-fire.sh:1874-1878` and `it2-kitty:1664-1668` say no retry can change a refused-fs verdict.
   - The logs show the opposite. The verdict changes whenever placement adds a pane: 280, 282, 56 and 165 all cleared that way, and so would 289 from 00:16:58Z on.
   - The only thing that re-tests is the pane-close queue via `bin/cc-pane-close`. That closer runs gate 4 (dirty cwd, `:511`) **before** the fullscreen gate (`:520`), and `--allow-dirty` is not carried in the husk row.
   - For a session that already wrote "Good to close: yes" and ran `self-close --allow-dirty` in a shared checkout, gate 4 is a permanent block (pane-close.jsonl:394-402).
3. **Placement fills a window that holds a husk.** `cc_place_pane` counts the husk as a tenant ("window with room"), so new live panes are split in next to it. That produces the mixed "3 panes, one of them a bare shell" view the operator saw. It also accidentally un-strands the husk, but only for closers that reach the fullscreen gate.
4. **Nobody re-pages, and the session is gone.**
   - husk-fs is deliberately excluded from re-paging (`handoff-fire.sh:10357-10362`).
   - The desk push failed (`push=refused-rc3`; there is no desk role). The only notice was one OS banner.
   - The session itself exited 14 s after `/exit`, so no agent is left to act on the refusal.

## 6. What the session does after a refused self-close

Nothing, because it is already dead. The refusal happens in the **detached watcher, after claude exits**. The foreground exits 0 right after typing `/exit` (`handoff-fire.sh:15919-15931`); it printed "self-close armed …" and never sees the outcome. The watcher then:

1. stops after one attempt on rc 3 (`:11854-11857`);
2. re-reads the tty (`:11888`);
3. prints the husk-fs line to its log (`:11901`);
4. writes the alarm record and one OS banner (`hf_alarm`);
5. queues a `husk` row (`hf_husk_row`, `:11918`);
6. exits 0 (`:11932`).

Recovery depends entirely on three things: `scripts/pane-close-retry.sh` with `bin/cc-pane-close`, which is gated as described above; the operator pressing ⌘W; or placement adding a pane.

## 7. Fix levers (for the design phase, not applied)

- **L1: make the terminal close non-last first.** Before the watcher's close, if `kitty-fullscreen-guard` says `last_for.pane=true`, do one of the following:
  - move the pane into an OS window that already has other panes (`detach-window --target-tab`, the same machinery as `bin/kitty-pane-menu` "Move to"), so its close is `safe-not-last`;
  - or close the whole OS window through a path that leaves fullscreen first (the ⌘W equivalent) when it is off screen.

  Either one dissolves 14 of the 14 measured husk episodes. The Space-switch side effects documented in `docs/research/kitty-lastpane-move-2026-10-19/README.md` §1 have to be handled.
- **L2: treat refused-fs as a condition, not a fact.** Keep the pane-close queue row keyed on `refused-fs`, and re-test it whenever the pane count of `os_window_id` changes. pane-spawns.jsonl already records `os_window:N panes_before:K` for every split.
- **L3: carry the self-close's own verdict into the husk row**, for example `selfclosed=1 allow_dirty=1 sid=…`. With that, `bin/cc-pane-close` gate 4 can skip a session that already stamped Good-to-close plus `--allow-dirty`, or limit the dirty check to paths the session itself touched instead of a shared checkout's whole `git status`. Running the fullscreen gate before gate 4 would at least make the refusal reason honest.
- **L4: one closer, one state.** cc-pane-runner and the watcher both run the guard and both queue a husk row within 0-6 s of each other in all 10 episodes. Pick one owner.
- **L5: placement should not count a husk as a tenant**, or should consolidate the husk out first, so the operator never sees a mixed window.
