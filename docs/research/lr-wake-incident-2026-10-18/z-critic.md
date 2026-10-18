# Z: completeness critic over findings a–h (lr wake incident, 2026-10-18)

Read-only pass, 13:42–13:50 CDT (18:42–18:50Z). I read all nine findings files (a, b, c, c2, d, e, f, g, h),
then checked them against live state with `kitten @ ls` (snapshot `/tmp/zcritic-ls.json`, 13:42:31 CDT),
`kitten @ get-text`, `~/.claude/cc-registry/`, `history.jsonl` in all four config dirs, the live move batch,
the drain LaunchAgent, and `account-utilization.jsonl`. M = measured (the command is named). I = inferred.

## 1. Answer first

The findings agree on the two core defects and are largely right about them:

1. **The recycle race.** The watcher's silent 60 s `retype` types `/exit` before the foreground commits.
   A hold then disarms the watcher regardless of state.
2. **The two-gate capacity refusal.** A refused launch keeps its pane as a shell, and the refusal text
   invites retries. Agents retried with `--tab`.

The set is still incomplete in four ways that matter now:

- **The incident is still running.** Pane 350 is at the "Background work is running" modal again at
  13:43 CDT, and the next copy is the only one. Batch `20261018T180746Z` still has two workers armed
  for panes 3 and 374. The drain LaunchAgent is still loaded. It keeps piling sessions onto next3,
  now the hottest account, while next and next4 are healthy.
- **The fix proposals conflict.** The four reports propose three incompatible designs for a refused or
  failed pane (close on rc 9, requeue with rc 75, or a durable exit record), three names for the
  watcher's commit marker, and two orders for the load gate. Nobody owns the merge.
- **One "open root cause" is answered by data nobody joined.** f's unresolved "same-second exits"
  are the nudge. Both `/exit`s are in quaternary `history.jsonl` at 07:06:13Z.
- **Several fixes have no test.** These include h's five closer and reconciler defects, f's daemon and
  keystroke-provenance fixes, and a load-reduction plan that nobody wrote.

## 2. Gaps

### G1. Root causes that are unexplained or unowned

1. **f's "real open root cause" is resolved (M).** f-adversarial §5 calls the same-second exits of
   e52f1f63+5232121f (07:06:14Z) and 22a76c8a+2e9ed9f2 "unresolved".
   - `history.jsonl` grep (`"display":"/exit"`) shows `/exit` *submitted as a prompt* in both
     e52f1f63 and 5232121f at **2026-10-18T07:06:13Z** (claude-quaternary), and in 22a76c8a at
     07:22:38Z (next).
   - Their watchers were armed in the same second (07:04:13Z, f-adversarial), so their 60 s
     checkpoints lined up.
   - That is the a/c/d retype mechanism. f's main-body root cause ("load gate after confirm") and its
     fix 1a stay wrong. f's adversarial verifier already says so.
   - Action: drop f fix 1a and fold f's 24 holds into the a/c/d race.
2. **The next2 weekly-limit error is unexplained (c2-adversarial).** 5232121f hit "You've hit your
   weekly limit" 5 s after its swap onto next2 (06:51:35Z), while `account-utilization` shows next2
   at 0/0.
   - If next2 really was capped, every "move to account 2" before 09:00Z was futile.
   - Nobody resolved whether that error came from the next4 process or from next2.
3. **Why class-B did not auto-fire at its 05:00Z deadline (g-adversarial V2.3).** Its rows stayed
   "auto-fire ≤24h" for about 12 h and nothing fired. No slot owns this.
4. **The load itself has no owner.** Every hold in a/c/d is caused by load above 8/core.
   - c2 §2.8 lists the contributors (I): 39–43 TUIs, 109 MCP processes, 39 watchdog bash loops,
     46 cc-close-attrib, 15 cc-kqwait, bats suites running on the loaded box, Dia automation.
   - No finding proposes reducing any of them.
   - (M, `uptime` 13:43 CDT): 48.84 / 76.71 / 87.81 on 10 cores. That is still above the 8/core
     commit bound on the 5 and 15 min averages, so every in-place move keeps landing in the race
     window.
5. **The engagement window does not use the wall clock (e-adversarial).** `verify_engagement` adds
   up sleep intervals, so a 480 s window stretched to 49 min at load ~100. That delay is why 2cc3a7fa
   read "ENGAGEMENT UNPROVEN" and re-fired.
   - This is the same defect class that 1376807f4 fixed in the watcher. That fix is what exposed
     the race.
   - No finding owns a fix or a test for it.
6. **The self-close watcher was never audited.** d-adversarial notes that the `__selfclose` /
   `sc_exit_unblock` retype at `waited ≥ 40` (`handoff-fire.sh:10692-10725`) may have the same
   pre-commit race. c-adversarial says "leave it alone". Nobody checked it.
7. **The lr-fire-resume screen reader does not drop dim text (I, code read).**
   - `LR_SCREEN_SH` reads with `"$LR_IT2" session read` and no `--ansi`
     (`lr-fire-resume.sh:1033`, `:1079`).
   - `cc_tui_composer_rows` (`cc-tui.sh:239`) and `composer_content` (`handoff-fire.sh:4694-4701`)
     both drop faint runs.
   - So CC's dim prompt suggestion can read as DRAFT in the submit check. This is untested and
     could explain part of (e).
8. **Which pane is image #1 is unknown.** a says pane 332; g-adversarial V2.1 says pane 1. No worker
   could see the images. The mechanism is the same either way, but the remediation targets differ.
   Ask the operator, or match the screen text.

### G2. Live panes that are unaccounted for or unremediated (M: `kitten @ ls` 13:42 CDT, 34 windows / 10 OS windows)

| pane | state now (M) | what the findings say | gap |
|---|---|---|---|
| **350** f06b5e9b (next) | **the bg-work modal again** (`get-text`: "❯ 1. Exit and stop tasks … 3. Stay") | h: "answered Stay" (13:1x). d-adversarial: re-raised by batch 180746Z at 18:24–18:26Z | **Unremediated.** No watcher is alive and next holds the only copy. h's "done" is stale. The right answer is the "Stay" index, never 1. |
| 3 (a3da0696), 374 (7df606ba) | still targets of live batch `20261018T180746Z` (M: `ps`: lr-move-batch pid 77157 and workers 80986/81633; events `wait:background-job` / `wait:mid-turn`; no `abort` file) | d-adversarial: abort it | **Not done.** a3da0696 has a background job, so the next fire reproduces 350's modal |
| **258** 9f6593c5 (next) | idle TUI, launched by **`/tmp/resume-9f6593c5-retry.sh`** (written 10-17 03:24: a 24× loop that "retries until the capacity gate admits"). Last user turn 2026-10-11, transcript mtime 10-17 03:29. Batch 180746Z read HELD:no-shell | f: "pre-existing, decision 56c6862291f2" | The retry-to-spend-budget pattern **predates** this incident (an agent did it on 10-17), so c2's rescue loop is a recurrence. This script sits outside `/tmp/lr-rescue/` and no retirement list names it. |
| 19 (76033be2), 27 (30c3a88d), 28 (509e3aad) | live claude, **no `cc-registry/<pane>.json`** (M). The watchdog log has registrations from 10-15/10-16 | f: "no lr damage" | Missing registry rows are what made cc-pane-close refuse with "no session registration" (h defect 1). Meanwhile closed panes 1, 21, 22, 242 and 409–435 **still have** registry rows (`ls cc-registry`). Registry hygiene runs the wrong way round. Nobody found the cause. |
| OS windows 16 and 20 | **5 panes each**, 45 columns (M) | b-adversarial re-scoped only OSW 26 (1 pane) and 7/18/21/22 (3 panes) | Above the operator's 4-pane rule. Nobody flagged it, and nobody checked fullscreen state (kitten @ ls does not expose it; b §6 admits this). |
| 386 d7eb73d2 | moved to next3 **during the investigation** (batch 180746Z: `SWITCHED-UNPROVEN` then "MOVED … one copy"). 📬1 unread, idle | f: "still on next" | Stale. Engagement was not awaited, so confirm that the turn it was in when the move fired was not cut off. |
| 430 e52f1f63 | live, idle since 06:02Z, waiting on **an operator question** (backlog 661a8652d2f6). The rescue brief was never delivered | e: "do not re-deliver" | Nobody tells the operator that this pane is waiting on *them* |
| 429 / 344 / 25 | composers show `/limit-recover to account 3`, `replace by default`, `what's still open for me` | c-adversarial: 429 "still holds an unsubmitted `/limit-recover to account 3`" | **Contradicted (M).** `get-text --ansi` shows `ESC[22;2m` before each string, so all three are CC's dim suggestions, as f §2.6 says. c-adversarial is wrong here. |

### G3. Work that may be lost

- **None confirmed lost (M).** 0d7c9a19's next3 transcript ends 10:03:16Z with "✅ Good to close: yes —
  nothing of mine is open". 2e9ed9f2, 22a76c8a, b102f5af, 8db0e6f1 and e739e5b5 each continue in a
  successor (f §3.4).
- **At risk:**
  - f06b5e9b (pane 350). One wrong modal answer ("1") stops its `cc-await-ping` task and exits the
    only copy while nothing is armed to relaunch it.
  - e52f1f63 (pane 430). Its open question is unanswered and its brief was never delivered. Delivered,
    that brief would have self-retired it (e-adversarial §4).
  - 9f6593c5 (pane 258). Idle 7+ days, and every mover holds it as HELD:no-shell.
  - 3e929a81 (FBAR, pane 23). For about 10 h a guarded husk blocked the poller's nudge (f §2.5). No
    `handed-off-guard.log` refusal row exists for it (M: grep returns 0), so we cannot prove that no
    operator prompt was swallowed. h defect 4 says a rail cleared its *paused* goal, but no
    `recycle-bgwork-goal-clear` row names pane 23 (M: `handoffs.jsonl` grep). f §2.6 calls the
    `/goal clear` on screen a dim suggestion. **h defect 4 is unproven and probably a misread.**

### G4. Proposed fixes that conflict

1. **Fate of a pane whose launch failed.** These proposals are mutually incompatible:
   - f fix 2: close on rc 9.
   - c F4 / c2 §5.1: write a request, `exit 75`, close on 75.
   - e fix 11: close on any non-zero exit of a fleet line.
   - e-adversarial: a durable exit record that handoff-fire reads first, because rc 1 cannot
     distinguish a failed `cd` from claude exiting 1.
   - f-adversarial: close only after an owed record exists.
   - c2-adversarial: never for in-place panes, and dedupe against `parked/`, `runs/by-sid/` and
     `requests/`.

   One spec is needed: an rc 75 "queued" contract, a runner exit record, the fullscreen guard, and
   in-place exemption.
2. **The watcher commit marker.** a calls it `"$cmdfile.exit-typed"`, c calls it
   `$cmdfile.exit-committed`, d calls it `$RCY_RUN_DIR/exit-committed` and adds `exit-aborted`.
   - a says the checkpoints count from the marker. d-adversarial says delete the retype arm.
   - a-adversarial adds a no-marker timeout that unconfirms. d-adversarial adds an exit when the
     foreground dies.
   - Pick one name and one location. Decide whether retype survives. Both failure-path behaviours
     must be specified together, or a gated watcher strands a live claude behind the handed-off guard
     for 600 s.
3. **The hold yield.** a F2 and c F2 return 0 from `hf_recycle_hold`, and f-adversarial repeats it.
   a-adversarial and c-adversarial show that this falls through to `hf_exit_readback` and types
   `/exit` into the relaunch. The yield has to happen at each call site (`:18595`, `:18603`) or use
   `exit 0`. Three docs still carry the unsafe form.
4. **Load gate order.** f fix 1a moves the gate before the confirm. f-adversarial shows that would not
   have saved anyone. d-adversarial asks for hysteresis instead (precheck 6/core against commit
   8/core; 350 passed at 7.36 and held at 8.72).
5. **Tokens.** c F5 and c2 §5.1 have handoff-fire and the poller *mint more* tokens. c2 §2.4 shows
   that unredeemed tokens inflate the active term for 1020 s, and that the redeem path is broken today
   (`lr-handoff.sh:1537`, 12+ `token ABSENT` rows still firing). The extra mints have to land
   *after* the redeem and orphan fix, or they make refusals worse.
6. **Poller autofire.** c2 §5.1 says probe, then mint and spawn. c2-adversarial shows that path
   would have admitted a duplicate of live 509e3aad (pane 28). A live-beat-holder check must come
   first.
7. **Watchdog banner and closer.**
   - f fix 5 treats a tombstone as "meant to end" and auto-closes. f-adversarial: that hides strands.
   - g Q3 dry-runs the closer before painting. g-adversarial V2.1: that is the wrong mechanism; join
     the lr facts.
   - c F6 paints MOVED and enqueues `lr-fleet --one`.
   - Only c F6 combined with g V2.1 is safe.
8. **Background-work modal.**
   - d F3(a) prefers SIGTERM via `hf_exit_signal`, which stops the session's background tasks.
   - Meanwhile the watcher's bgwork arm answered "1 Exit and stop tasks" on panes 20, 22 and 242 for
     recycles the foreground then abandoned (a-adversarial).
   - Both destroy operator background jobs. No fix says which background tasks a recycle may kill.
9. **Remediation knobs.** a §4.5 says do not bypass the load hold. d §4.3 offers
   `HF_RECYCLE_HOLD_LOAD_PER_CORE=off`. The operator needs one answer.
10. **`--tab` doctrine.** b removes `--tab` and routes overflow to new fullscreen windows. The briefs'
    stated motive is "use --tab if splits time out" (b-adversarial). Without an answer to kitty RC
    split timeouts, agents will move to `--window`. That produces the single-pane OS windows that b's
    own policy and the 4-pane rule forbid.

### G5. Fixes without a test

| fix | source | missing test |
|---|---|---|
| cc-pane-close "never-launched" arm, and a transcript reader that crosses account stores | h defect 1 | none, and no file:line |
| cc-husk-sweep must consult recycle/handoff lineage before RESUME | h defect 2 | none |
| reconciler cohort exits NOT_NEEDED when the source account is healthy again | h defect 3 | none |
| failure path scrubs its own `/goal clear` paste | h defect 4 | none (and the premise is unproven, G3) |
| tombstone with a silent successor becomes a first-class STRANDED state | h defect 5 | none |
| every husk closer asks `kitty-fullscreen-guard --scope os-window` | h defect 7 | none |
| retire agent-installed LaunchAgents and make the drain reset-aware | f fix 6 | none |
| keystroke provenance log `pane-keys.jsonl` | f fix 7 | none |
| `cmd+t` rebind, fleet invariant (>1 tab / >4 panes) | b fixes 5, 7 | none, apart from the pane-spawns ratchet |
| CPU-active admission signal, ceiling in cores | c2 §5.3 | none |
| token dropped once its spawn is gone | c2 §5.2 | test 3 covers redeem only, not orphan expiry |
| precheck/commit hysteresis | d-adversarial | none |
| engagement window on the wall clock | e-adversarial | none |
| `session-index-end` SQLITE_BUSY handling | a F6 | none |
| `/tmp` rescue launchers refused (`--launcher /tmp/*`) | c F7, f fix 3 | b's validate-bash case covers `--tab` only |

### G6. Live-state hazards that no finding escalates

- **The drain is still live (M).** `launchctl list` shows `com.reso.drain-to-next3` loaded.
  `drain-to-next3.log` shows `cc-lr rotate --account next4` started at 18:15:07Z, 18:25:19Z and
  18:41:45Z, each ending `rc=1`.
- **The direction is now wrong (M, `account-utilization.jsonl` 18:45:45Z).**

  | account | 5h % | weekly % | sessions |
  |---|---|---|---|
  | next | 2 | 22 | 4 |
  | next2 | 14 | 9 | 12 |
  | next3 | 53 | 36 | 18 |
  | next4 | 2 | 5 | 5 |

  The original reason to drain accounts 1 and 4 is gone, and the drain keeps loading the
  busiest account. At this rate, next3's 5-hour cap starts the next lr cycle (I).
- **Old rescue scripts remain executable (M: `ls -la`).** `/tmp/lr-rescue/*.sh` and
  `/tmp/resume-9f6593c5-retry.sh` are still there.
- **Successor briefs remain (b).** `/tmp/fire-lr-344-successor.txt` still carries `--tab`.

## 3. Immediate remediation implied by the gaps (describe only; nothing was done)

1. Pane 350: answer the modal with the "Stay" index, read with `_pane_bgwork_index "Stay"` and
   checked by read-back. Then `touch …/move/20261018T180746Z-next-next3-6778/abort`.
2. Operator call: pause the drain with `~/.reso/limit-recover/listeners/drain-to-next3.off`, or unload
   it. Accounts 1 and 4 are healthy.
3. Archive `/tmp/lr-rescue/`, `/tmp/resume-9f6593c5-retry.sh` and `/tmp/fire-lr-344-successor.txt`.
4. Tell the operator that pane 430 is waiting on their answer (661a8652d2f6), and decide what happens
   to pane 258.
5. Rebalance OS windows 16 and 20 (5 panes each) to 4, through `kitty-fullscreen-guard`.

## 4. Confidence

- **85%** that the gaps above are real. G2 and G6 are measured directly at 13:42–13:46 CDT.
- G1.7 (the dim reader) is inferred from a code read, and G1.8 is unknowable without the images.
- Two things would lower it:
  - a live re-read showing pane 350 already answered;
  - a test showing `LR_SCREEN_SH`'s `it2` read already strips SGR-2.
