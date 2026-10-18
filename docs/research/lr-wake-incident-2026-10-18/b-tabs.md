# (b) Tabs in kitty OS window 18 — root cause, chain, fix

## 1. Answer first

Every tab in OS window 18 came from one place: `handoff-fire.sh`'s kitty **bg-tab** arm (`kt_launch --type=tab --match id:<anchor>`), called with an explicit `--tab` by agents. Nothing in the lr machinery (lr-fire-resume, cc-pane-runner, lr_kitty_spawn, the recycle) made a tab. The lead in pane 344 (620db313, later its successor 2cc3a7fa) picked `--tab` for its first rescues at 03:02Z. It then wrote that choice into its successor's brief and into `/tmp/lr-rescue/fire-*.sh`. That turned 16 rescue fires into 16 tabs. 13 of them failed the capacity gate and stayed behind as plain shells.

No guard fired because the "no tabs" rule exists nowhere in code. The only check is an advisory warning, and the `--surface-reason` the agent passed switches that warning off by design.

**Fix:** remove tabs as a surface at the launch chokepoint. A pane goes either into a vertical split of an OS window that has fewer than 4 panes, or into a NEW fullscreen OS window. Back this with a validate-bash deny on raw `launch --type=tab`, and with a fleet check that flags any OS window holding more than 1 tab or more than 4 panes.

## 2. Evidence (MEASURED unless marked)

**Live layout.** `kitten @ ls` at ~13:12 CDT: OSW 18 had 18 tabs (146, 156-167, 170-174).
- Tabs 156-167 and 173 each held one bare `/bin/zsh -l -i`.
- Each of those shells has `CC_PANE_CMD=… /tmp/lr-rescue/resume-<sid8>.sh …` and `CC_PANE_RUNNER=…/bin/cc-pane-runner`.
- Shells per session:
  - 5232121f: 403, 409, 412, 416
  - e52f1f63: 410, 413, 419
  - 22a76c8a: 414, 417, 425
  - 2e9ed9f2: 418, 426, 435
- Pane 403's command is `cd $'whose\n/Users/chrisren/Development/claude-infrastructure' && …`. The agent's `sed` took its cwd from the comment line of the resume script ("next2 whose relaunch…").

A re-read at 13:18:43 CDT showed the 13 shell tabs already closed by someone else. OSW 18 now holds tabs 146 [344], 170 [430], 171 [433], 172 [434, 454] and 174 [442].

**Spawn provenance.** `~/.claude/logs/pane-spawns.jsonl`, overnight rows. Every tab row is `surface:"bg-tab" caller:handoff-fire.sh detail:"it2py bgtab --match id:<anchor>"`.

| UTC | pane | anchor | claude pid in ancestry (session) |
|---|---|---|---|
| 03:04:18, 03:07:27 | 376, 377 | 344 | 22757 (620db313; rescues of 8db0e6f1, e739e5b5) |
| 07:13:38 | 403 | 344 | 16342 (2cc3a7fa) |
| 07:19:58, 07:20:17 | 409, 410 | 344 | 16342 |
| 07:59:58, 08:00:15, 08:01:16 | 412, 413, 414 | 344 | 16342 |
| 08:41:16, 08:43:16, 08:44:00, 08:44:15 | 416, 417, 418, 419 | 344 | 16342 (`fire-round.sh`) |
| 09:19:54, 09:20:22 | 425, 426 | 344 | 16342 |
| 10:06:39 | 430 | 344 | 16342 (engaged: e52f1f63) |
| 10:44:49 | 433 | 344 | 16342 (engaged: 22a76c8a) |
| 10:49:00 | 434 | **433** | 27898 (22a76c8a, the TrueMemory lead itself firing W2 `--tab`) |
| 10:57:12 | 435 | 344 | 16342 |
| 11:31:46 | 442 | 344 | 16342 (engaged: 2e9ed9f2) |

- **Tab ids match the spawn order.** Pane 426 is tab 167. Panes 428 and 429 are `lr_kitty_spawn` os-windows at 10:00Z and 10:04Z (tabs 168 and 169, in OSW 24 and OSW 25). Pane 430 is tab 170. So no lr path created a tab in OSW 18. The other kitty `--type=tab` callers (`bin/cc-relayout:363`, `bin/cc-resume-layout.sh:946`) have no overnight rows.
- **The brief's time range is off.** The shells' "Last login" lines (02:02-05:49 CDT) are the *previous* login that macOS prints, so they trail creation. Example: pane 403's banner says 02:02:35, but it was spawned at 07:13:38Z = 02:13 CDT. Use the spawn log for times.
- **Why the shells stayed.** Pane text quoted in the 2cc3a7fa transcript at 07:59:08Z and 08:40:33Z: `✗ capacity-admit: REFUSING resume … > active ceiling 8 (refusal N of 3)` and then `cc-pane-runner: the fleet launch line exited 9 — keeping a shell for diagnosis/resume`. Pane 435 still showed `refusal 3 of 3` at 13:15 CDT.

**Where `--tab` came from** (transcripts):
- 620db313 (`~/.claude-next/projects/-Users-chrisren-Development--worktrees-wt-cc-184726-89776/620db313-….jsonl`):
  - 03:02:14Z, thinking: repair failed; "the rail only suggests a raw relaunch… I'll relaunch both sessions through handoff-fire.sh".
  - 03:02:38Z, command: `handoff-fire.sh … --account next --tab --surface-reason "rescue relaunch of a stranded session, not new work"`.
  - Result: `surface: bg-tab, background (operator focus preserved)`.
  - 03:08:33Z: it mails the method as "the method that worked" to pane 362.
- Successor brief `/tmp/fire-lr-344-successor.txt:11`, used by the 06:57Z `--recycle`, hard-codes `--account <acct> --tab --surface-reason "rescue relaunch" --no-notify-back`. 2cc3a7fa's first user turn (06:58:49Z) carries the same line.
- 2cc3a7fa (`~/.claude-tertiary/projects/…/2cc3a7fa-….jsonl`):
  - 07:13:06Z: runs `handoff-fire.sh --help | grep -- '--tab'` and reads "Background tab in the FIRING pane's window".
  - 07:13:12Z onward: every fire carries `--tab`.
  - 08:00:42Z: writes `fire-next3-batch.sh`. 08:42:35Z: writes `fire-round.sh` (`--tab` at line 3 of the script).
  - It re-ran `fire-round.sh` at 08:42, 09:18, 10:05, 10:44, 10:50, 10:55 and 11:30Z. Each re-run minted a NEW tab instead of reusing the refused shell.
  - 07:18:37Z it said "hasn't opened a tab yet" and killed the bad-cwd fire. But pane 403 had already been spawned at 07:13:38Z.
- 22a76c8a used `--tab` in all 12 of its `handoff-fire.sh` calls (`grep -o 'handoff-fire.sh [^"]*' | uniq -c` → `12 --tab`). Its 10:47:58Z W2 fire had no `--surface-reason`.

**Guards that exist, and why each stayed silent:**
- `scripts/handoff-fire.sh:19356-19361`: advisory only. It warns when `--tab`/`--window` has no `--surface-reason`. The agents passed one, which silences it by design (`:147-149`). 22a76c8a passed none, got the warning, and the fire went ahead.
- `scripts/handoff-fire.sh:15195-15197`: honours an explicit `--tab` by normalizing it to `bg-tab`. The `bg-tab` arm (`:18364-18391`) then calls `it2_bgtab`. Its kitty branch (`:17615-17638`) runs `kt_launch --type=tab --keep-focus --match id:$bsid`, with no pane or tab count check.
- `scripts/handoff-fire.sh:18319`: the only room/overflow logic (cap 5, overflow → new window). It runs only for HEADLESS fires (`FIRING_SID` empty). A named anchor (344) is never counted, so even the default split-right would have stacked 16 splits on pane 344. The overflow window from `spawn_frontmost` (`:18215`) is `--type=os-window` with no `--os-window-state=fullscreen`. `git grep os-window-state` → 0 hits in bin and scripts, so no spawned OS window ever gets its own Space.
- Stale help text: `scripts/handoff-fire.sh:112-115` and `:126-129` still say "the AUTONOMOUS default already IS a background tab". That stopped being true with the `:15192` change, but it is what `--help` shows agents.
- `hooks/validate-bash.sh`: 0 hits for `--tab`, `type=tab` or `bg-tab`. Its spawn gates (`:510` worker-claim, `:564` lineage cap) cover duplicates and generations, not surfaces.
- `bin/kitty-fullscreen-guard`: a destroy-side guard only. It runs before a close or move empties a fullscreen window and has no say over creation.
- `commands/handoff.md:528-535` and `:570-575`: prose that *allows* `--tab` for overflow (~4+ panes). Neither lr agent read it; both worked from `--help`.
- `config/kitty.conf:930`: `map cmd+t new_tab_with_cwd`. The repo still binds a tab key.
- `git grep -E 'no-tabs|NO_TAB|CC_NO_TABS'` → 0 hits. The operator's no-tabs rule is not encoded anywhere.

## 3. Causal chain

1. Around 02:15-03:00Z, the `cc-lr repair` and `lr-fleet --one` rail fails for transplanted-but-dead sessions (8db0e6f1, e739e5b5). It only prescribes a raw new-window `lr-fire-resume`.
2. At 03:02Z, 620db313 in pane 344 improvises a rescue through `handoff-fire.sh` and picks `--tab` (INFERRED reason: `--help` says it is the background, no-focus-steal surface, and split-right would slice the lead's own pane). It passes `--surface-reason`, which mutes the only advisory. This creates panes 376 and 377 as tabs; both were later detached.
3. At 06:57Z, 620db313 recycles itself into 2cc3a7fa, and the successor brief (`/tmp/fire-lr-344-successor.txt:11`) bakes in `--tab`.
4. From 07:13Z to 11:31Z, 2cc3a7fa fires 16 rescues with `--tab`. Each one runs `kt_launch --type=tab --match id:344` in OSW 18.
5. Each rescue's `lr-fire-resume` hits `capacity-admit` (ceiling 8, load ~85-230), and `cc-pane-runner` "keeps a shell" on exit 9. The agent re-fires with a new tab instead of reusing that shell. Result: 13 shell tabs (156-167, 173) plus 3 engaged tabs (170, 171, 174).
6. At 10:49Z, 22a76c8a, now living in tab 171, fires W2 with its habitual `--tab`. That makes tab 172 [434, plus 454 split later].
7. Visible state: an 18-tab OS window. Only tab 146 is on screen, the other 17 are hidden, and the tab bar appears (default `tab_bar_min_tabs 2`).

## 4. Immediate remediation (describe only; nothing was done by this worker)

As of 13:18 CDT, the 13 shell tabs are gone. Remaining: OSW 18 has 5 tabs holding 6 live sessions (344 2cc3a7fa lead, 430 e52f1f63, 433 22a76c8a, 434 + 454 W2/J5, 442 2e9ed9f2).

1. **Merge into tab 146 as vertical splits, up to 4 panes:** move 430, 433 and 442 into tab 146. Use kitty-pane-menu, or `kitten @ detach-window --match id:430 --target-tab id:146` (and the same for 433 and 442). None of these moves empties the OS window, so `kitty-fullscreen-guard` returns safe-not-last.
2. **Move tab 172 [434, 454] to its own fullscreen OS window:** use kitty-pane-menu "detach tab" (⌘⌥⇧O, `config/kitty.conf:910`, which goes through the fullscreen guard), then make the new window fullscreen. Do not use ⌃⇧Q `close_tab`.
3. **Merge the single-pane windows:** OSW 25 [429 5232121f], OSW 24 [428 bare shell, if still present] and OSW 26 [398, 400] break the "4 panes per Space" layout. Merge them the same way, and close shell 428 only after `cc-lr find` confirms nothing depends on it.
4. **Stop the scripts being re-run:** rename or retire `/tmp/lr-rescue/fire-round.sh` and `fire-next3-batch.sh`, and the successor brief `/tmp/fire-lr-344-successor.txt`. Any future successor or continuation that re-runs them mints tabs again. MEASURED: no `~/.claude-tertiary/state/continue-*` sentinel mentions `fire-round` now.

## 5. Long-term fix

**Placement policy (one rule, one chokepoint):** a session pane is created in exactly one of two ways.
- **(A) Split.** `--type=window --location=vsplit` into the firing pane's OS window, only if that OS window has exactly 1 tab and fewer than `CC_MAX_PANES_PER_SPACE` panes (default 4). Otherwise use the next operator OS window that has room.
- **(B) New fullscreen window.** `--type=os-window --os-window-state=fullscreen --keep-focus` (its own macOS Space).
- `tab` is not a value in the type. Fill overflow windows to 4 before minting another, so fullscreen one-pane windows (the husk-fs precondition, `handoff-fire.sh:9382-9392`) stay rare.

Code changes:
1. **Shared placement library.** New `scripts/lib/pane-placement.sh: cc_place_pane <anchor> <cwd> -- <argv>`. It reads `kitten @ ls` once, applies (A)/(B), returns the window id, and writes the `cc_log_pane_spawn` row with `requested=<flag> given=<split|os-window-fs>`. Called from:
   - `handoff-fire.sh spawn()` (`:18248`). All of the `bg-tab`, `tab`, `split-*` and `window` arms route through it.
   - `lr-lib.sh:lr_kitty_spawn` (`:1286-1313`). Its no-anchor os-window branch at `:1299` gains fullscreen plus a room search.
   - `bin/cc-relayout:363` (its placeholder tab becomes a fullscreen os-window).
2. **`handoff-fire.sh`:**
   - `:14535`: `--tab` becomes a deprecated alias. Set `SURFACE=place` and print a one-line stderr: "--tab is retired; placed by policy (split or new fullscreen window)". This keeps old briefs working with no tab.
   - `:15195-15197`: delete the bg-tab normalization.
   - `:17615-17638` (kitty bgtab) and `:18133-18151` (kitty `as_tab`): stop calling `--type=tab`.
   - `:18319`: room checks apply to NAMED anchors too, not just headless.
   - `:18215`: add `--os-window-state=fullscreen`.
   - `:108-149` and `:19356-19361`: rewrite the help and drop the advisory, which no longer has anything to warn about.
3. **Primitive-level refusal.** `handoff-fire.sh:kt_launch` (`:1595`) and `bin/it2-kitty`'s launch wrapper refuse any argv containing `--type=tab` with rc 2, unless `CC_ALLOW_TAB=1`. Only `bin/cc-resume-layout.sh:946` (restoring a recorded layout) and `scripts/checks/restore-tree-live-verify.py` set it. This is what makes a tab impossible from our code even if a caller regresses.
4. **`hooks/validate-bash.sh`.** Deny agent Bash that contains `(kitty|kitten) @ .*launch .*--type[= ]tab` or `new_tab`, with the message "tabs are retired; use handoff-fire (placement is automatic)". Put it next to the spawn gates at `:492-564`.
5. **`config/kitty.conf:930`.** Rebind `cmd+t` to `new_os_window_with_cwd` (and set kitty to fullscreen new OS windows on macOS), or unmap it.
6. **Docs.** Rewrite `commands/handoff.md:500-575` to remove every `--tab` recommendation. The lr skill / rescue template should prescribe no surface flag at all.
7. **Fleet invariant.** In the kitty census (`bin/cc-where:360` already computes `hidden_by="tab"`), alert on any OS window with more than 1 tab or more than 4 panes. When every pane in the surplus tab is agent-owned, auto-compact by detaching it to a new fullscreen window, through `kitty-fullscreen-guard`.

**Tests that would have caught this:**
- `tests/handoff-fire-no-tab.bats`, using a stub `kitty @` that records argv and serves a mutable fake `ls`:
  - (a) `--tab` with and without `--follow` → recorded argv never contains `--type=tab`.
  - (b) Anchor OS window has 3 panes → `--type=window --location=vsplit`.
  - (c) Anchor has 4 panes → `--type=os-window --os-window-state=fullscreen`.
  - (d) 16 sequential fires from one named anchor (tonight's replay) → 4 OS windows, each with 1 tab and at most 4 panes.
- A `kt_launch` unit test: `--type=tab` → rc 2 unless `CC_ALLOW_TAB=1`.
- A `validate-bash` bats case: `kitten @ launch --type=tab …` → deny.
- A pane-spawn ratchet over `pane-spawns.jsonl`: rows with `surface ∈ {tab, bg-tab}` and caller ≠ cc-resume-layout must be 0. Tonight it would read 19.

## 6. Confidence

**90%** that the account above is complete: all OSW 18 tabs come from agent `--tab` → handoff-fire bg-tab, the cause originates in 620db313's 03:02Z choice propagated via the brief and the scripts, and no guard exists.
- The *motive* for `--tab` is INFERRED. The summarized thinking never states it, and the brief only names "rescue relaunch".
- Tab ids 147-155 are not fully mapped (376 and 377 were detached out; 148, 152 and 153 belong to other OS windows).
- I did not check whether OSW 18 itself is in native fullscreen.
- Confidence would drop if a non-handoff-fire tab creator showed up with no spawn-log row. The log is written at the primitive, but `bin/cc-relayout` coverage was not verified.

## Adversarial verification

**Verdict: NOT refuted.** The mechanism holds: OSW 18's tabs came from agent `--tab`, which became `bg-tab`, which ran `kt_launch --type=tab`. Three parts of the report are wrong or incomplete, though. The advisory claim is wrong. The origin story is too narrow. And the fix on its own would not have kept the 13 dead shells off screen.

**Confirmed (MEASURED, opened myself):**
- `scripts/handoff-fire.sh:14535` (`--tab` → `SURFACE=tab`) and `:15195-15197` (autonomous `tab` → `bg-tab`) say what the report says.
- `:17631` is `kt_launch --type=tab --keep-focus --cwd=current --match "id:$bsid"` and does no pane or tab count. `:18364-18391` is the bg-tab arm.
- `:18282` gates the room check on `[ -z "$FIRING_SID" ] && ANCHOR_INTENT=0`, so it covers headless fires only. `:18319` is the cap.
- `:18215` makes an os-window with no fullscreen. `git grep os-window-state` over bin/scripts/hooks/lib gives 0 hits.
- The help text at `:126-129` is stale.
- `config/kitty.conf:930` is `map cmd+t new_tab_with_cwd`.
- `bin/cc-relayout:363` and `bin/cc-resume-layout.sh:946` are the other `--type=tab` callers.
- `lr-lib.sh lr_kitty_spawn` makes only os-window or vsplit.
- `~/.claude/logs/pane-spawns.jsonl` has exactly the 19 rows in the table: 18 anchored on id:344 and pane 434 on id:433.
- `/tmp/fire-lr-344-successor.txt:11`, `/tmp/lr-rescue/fire-round.sh:3` and `fire-next3-batch.sh:5` each carry `--tab`.
- The 620db313 fire at 03:02:38Z ran with `--tab --surface-reason …`.

**Corrections:**
1. **The advisory is dead code for every autonomous `--tab`, with or without `--surface-reason`.**
   - `:15195` rewrites `SURFACE` to `bg-tab` before the top-level advisory at `:19358`, which tests `"$SURFACE" = tab`. Between them the only `SURFACE=` writes are `:18322`/`:18348`, both `window` (grep).
   - So the report's line "22a76c8a passed none, got the warning, and the fire went ahead" is wrong. Its W2 fire (`--notify-back 433 --account auto --tab --effort high …`, no reason) printed no warning: the 22a76c8a transcript has 0 hits for the advisory text (`grep 'overrides the'`; its one hit is unrelated skill prose).
   - Fix target: the advisory can only fire for `--follow --tab` or `--window`.
2. **"Neither lr agent read handoff.md" is false for 620db313.**
   - At 02:06:27Z (transcript line 604) it called `Skill handoff`, which injected `commands/handoff.md` in full, including `:500` ("**5 · Surface** … `--tab` (background tab…)") and `:547-549` ("--tab is for OVERFLOW ONLY (window already ~4+ panes)").
   - That was 56 min before it picked `--tab`. The doc is a likely source, alongside `--help`. Its motive is still unstated (thinking at 03:01:44Z mentions only "a properly tracked pane").
3. **`--tab` did not start with 620db313. It is a fleet habit that already existed.**
   - pane-spawns.jsonl has 9 bg-tab rows on 2026-10-17 before 03:02Z, from 3 different claude pids (84190, 23842, 73883), all `--match id:22`: panes 254, 255, 256, 259, 311, 329, 330, 333, 358.
   - 22a76c8a's own predecessor brief (first user turn, 22:07:41Z) says "Fires: … use --tab", and another note says "use --tab --surface-reason if splits time out". The motive given there is kitty RC split timeouts under load.
   - So 620db313 → brief → fire-round.sh explains the 16 rescue tabs in OSW 18, but the root is the doctrine (handoff.md overflow-to-tab, stale `--help`, briefs passed from lead to lead), not one agent's improvisation.
4. **The ratchet count is 22, not 19.** Bg-tab rows between 01:00Z and 15:00Z are the report's 19 plus pane 358 (01:50Z, id:22), pane 392 (04:35Z, id:22, fired by 22a76c8a's earlier pid 73883) and pane 448 (14:41Z = 09:41 CDT, `--match id:433`, claude pid 83250). That is 22 (grep of pane-spawns.jsonl). The report never mentions 448.
5. **The live state has already changed, so §4 is stale.** `kitten @ ls` at 13:22 CDT shows:
   - OSW 18 = 1 tab (172: 434, 454, 433).
   - 344, 430 and 442 now sit with 429 in OSW 25 tab 169 (4 panes).
   - OSW 26 = only pane 398.
   - Every OS window now has 1 tab. Steps 1-2 are done. Step 3 should be re-scoped to OSW 26 (1 pane), plus OSW 7, 18, 21 and 22 (3 panes each).

**Missing: the fix would not have prevented what the operator sees.**
- `handoff-fire.sh` never calls `cc_capacity_admit`; its only gate is memory headroom (`:10386`, "headroom ADMIT"). The active-ceiling-8 refusal runs only inside the new pane (`lr-fire-resume.sh:788-796` → `lr_relaunch_rc 9`), after the surface already exists. `cc-pane-runner:180` then keeps a shell.
- Under the proposed placement policy, the replay test (d) would turn 16 fires into about 4 fullscreen Spaces, 13 of whose panes are dead shells. The junk becomes visible instead of hidden, which is the (c) complaint.
- Needed alongside it:
  - (i) In `handoff-fire.sh`, run `cc_capacity_admit` (same key/caller as lr-fire-resume) before `spawn()` whenever the launcher is an lr resume, and refuse with no surface minted.
  - (ii) On launcher rc 9, `cc-pane-runner` should close a pane it created, using a kitty-fullscreen-guard-safe close. A pane holding the only copy of a session never reaches rc 9 before claude starts, so this cannot lose a session.
  - (iii) Rescue retries should reuse the refused pane, not fire again.
  - Test: a stub capacity-admit returns 9, and handoff-fire must emit 0 `kitty @ launch` calls.
- Smaller items:
  - The `CC_ALLOW_TAB` exemption (fix 3) misses `bin/cc-relayout`. It calls `kitty @ launch` through its own `k()`, not `kt_launch`, so the refusal never applies to it. Fix 1 also changes its recorded-layout restore semantics, so treat it as a deliberate change with its own test.
  - The split-timeout motive in the briefs ("use --tab … if splits time out") needs an answer, or agents will route around a split-only policy with `--window`.

**Adjusted confidence: about 80%** on the mechanism plus the OSW 18 chain. The prevention claim of the fix as written is lower, about 50%, unless admit-before-spawn is added.
