# Symptom (c): husk panes, meaning plain shells left where Claude Code used to run

Investigated 2026-10-18 13:12–13:40 CDT, read-only. Times are UTC unless marked CDT (CDT = UTC−5).
Live kitty state comes from `kitten @ ls` (snapshot `/tmp/c-husk-kls.json`, 13:2x CDT) and from `kitten @ get-text --extent all`.
**M** = measured (the source is named). **I** = inferred (the reasoning is given).

## 1. Answer first

There are 17 husk panes. They come from two independent defects, plus one family that only makes the misleading text worse.

- **Recycle race.** During an in-place move, the detached watcher's 60-second "retype `/exit`" nudge fires before the foreground has typed `/exit` at all (the foreground's confirm, last read and load gate take minutes at load 15–37/core). The watcher's nudge is what exits Claude. The foreground then reaches its load hold, and that hold disarms the watcher, which was about to type the relaunch. This produced panes 1, 242 and 332 (families 2/3), each verdict `STRANDED`.
- **Two capacity gates.** Every pane-creating relaunch is admitted by one gate and then refused by a second gate inside the new pane (exit 9). That left 13 tabs plus one window (403–435, 428) as shells. The tabs were mostly opened by the rescue agent in pane 344, which retried in a fresh tab each time, on purpose, to use up the refusal budget.
- **The fix:**
  - (a) the watcher may not type `/exit` until the foreground says it committed;
  - (b) a hold whose subject has already exited yields to the watcher and never disarms it;
  - (c) a gate refusal in a pane the fleet just created closes that pane and requeues the session, instead of keeping a shell;
  - (d) the watchdog banner and resume line understand a transplanted session.

## 2. Evidence (measured)

### 2.1 Census of the husk panes

Every pane below runs only `/bin/zsh` as its foreground process (M: `kitten @ ls` `foreground_processes`).

| win | OS win / tab | family | screen says (M, get-text) | session | where the session lives now (M) |
|---|---|---|---|---|---|
| 403 | 18 / 156 | 1* | `zsh:cd:1: no such file or directory: whose\n/Users/…/claude-infrastructure` → `exited 1` | 5232121f | LIVE pane 429, next2 (`cc-lr find`) |
| 409, 412, 416 | 18 / 157, 159, 162 | 1 | `REFUSING resume 5232121f … refusal 1/2/3 of 3` → `exited 9` | 5232121f | LIVE pane 429 |
| 410, 413, 419 | 18 / 158, 160, 165 | 1 | `REFUSING resume e52f1f63 … refusal 1/2/3 of 3` | e52f1f63 | LIVE pane 430, next2 |
| 414, 417, 425 | 18 / 161, 164, 166 | 1 | `REFUSING resume 22a76c8a … refusal 1/2/3 of 3` | 22a76c8a | resumed 10:44Z under cc-pane-runner pid 18302 in window 433, then a fresh successor took over (cc-close-attrib pid 83085). Transcript on next3, last write 10:51Z (M: `ps`, `ls -la`) |
| 418, 426, 435 | 18 / 163, 167, 173 | 1 | `REFUSING resume 2e9ed9f2 … refusal 1/2/3 of 3` | 2e9ed9f2 | live in pane 442, next3. Transcript active 14:20Z |
| 428 | **24** (its only pane) | 1 | poller launcher `lr-poller-launch-509e3aad…`, `REFUSING … on next4 (refusal 1 of 3)` | 509e3aad | recovered in place in pane 28. poller.log 12:12:17Z `REQUEST-RETIRED … no longer LIMITED` |
| 332 | 20 | 2 | `[lr-fire-resume] session ended (rc 0) — this pane is now an ordinary shell.`, then a lone typed `: hfv-77512-1-18249; unsetopt correct correct_all` and no launch line | 2e9ed9f2 (source) | pane 442 |
| 1 | 5 | 3 | three generations of `running the staged successor …ttys000.claimed.{2587,19793,22242}`, then `✅ CLOSED CLEANLY — e52f1f63 … safe to close … ▶ … claude4 --resume e52f1f63…` | e52f1f63 (source) | pane 430 (next2). The banner's `claude4` names the wrong account |
| 242 | 5 | 3 | `running the staged successor …ttys005.claimed.18978`, then `✅ CLOSED CLEANLY — 0d7c9a19 … ▶ … claude --resume 0d7c9a19…` | 0d7c9a19 | **runs nowhere**: `cc-lr find` reads DEAD on next. The full 2,672,309 B transcript is on next3, and next holds only a 4,249 B stub (M: `ls -la`) |
| 401 | 21 | (driver) | operator-typed `cc-lr move --sid f06b5e9b --to next2 --until-idle 3600`. The batch ended NOTMOVED | f06b5e9b | LIVE pane 350 on next (`cc-lr move --status`) |

### 2.2 Family 1: two gates, opposite answers, in this order

- **Outer gate admits.** `~/.claude/logs/handoffs.jsonl` holds the rescue rows `admitted … 6 sessions mid-turn (ceiling 8)` at 07:19:18Z, 07:59:29Z, 08:00:53Z, 08:40:44Z and 08:42:44Z. That is handoff-fire's gate (`scripts/handoff-fire.sh:10463`, `_cc_fire_bound active`), and it does not count admission tokens.
- **The tab opens.** handoff-fire `--tab`, from `/tmp/lr-rescue/fire-round.sh:3` and `fire-next3-batch.sh:5`.
- **Inner gate refuses.** `lr-fire-resume.sh:777-797` refuses: `7 sessions mid-turn + 2 admission token(s) in flight + 1 > active ceiling 8`, then `exit 9`. That gate counts tokens, and in the parallel `fire-round.sh` (`fire … &`) the tokens in flight are the sibling rescues' own.
- **No token was carried.** The rescue launchers `/tmp/lr-rescue/resume-*.sh` exec `lr-fire-resume.sh` with no `LR_ADMIT_TOKEN`. That is the 2026-09-19 "split decision" (`lr-fire-resume.sh:748-756`) returning on a path the token fix never covered.
- **The runner keeps the shell.** `bin/cc-pane-runner:179-182`: `if [ "$2" != 0 ]; then … keeping a shell for diagnosis/resume`.
- **The origin session.** It is `2cc3a7fa-01ea-4c5d-82da-c06018901409` (next3, pane 344, worktree wt-cc-184726-89776). From its transcript (`~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-cc-184726-89776/2cc3a7fa….jsonl`):
  - 07:19:05Z and 07:19:07Z: first `handoff-fire.sh … --launcher /tmp/lr-rescue/resume-*.sh --tab`.
  - 08:40:38Z, quoted: "Refusal 2 of 3. The gate's own message says the next evaluation is admitted once its budget is spent. Firing 5232121f a third time."
  - `fire-round.sh` rounds at 08:42:39Z, 09:18:43Z, 10:05:01Z, 10:44:22Z, 10:50:31Z and 10:55:50Z.

  Each refused attempt was a new tab, and nothing closed it.
- **Window 403 is a cwd bug in the agent's own code.** At 07:13:12Z it ran `sed -n 's/.*next2 \([^ ]*\) .*/\1/p'` over `resume-5232121f.sh`. That file's comment line reads "transplanted next4 -> next2 whose relaunch…", so the extracted cwd became `whose\n<path>`.
- **The poller (window 428).** `lr-reset-poller.sh:2600-2601` logs `RESUMED 509e3aad on next4 (autofire, gui) — pane opened` (poller.log 10:00:12Z) as soon as the pane is spawned. It never reads `relaunch.rc` 9. Its launcher (`/var/folders/…/lr-poller-launch-509e3aad-DTj06v.sh`) also carries no admission token.
- **The refusal text invites retries.** The `capacity-admit.sh:1640` message ends "once the budget is spent the next evaluation ADMITS and pages". Next to it, lr-fire-resume's own line, "re-run this exact command" (`:790`), is what the agent followed.

### 2.3 Families 2 and 3: the watcher's own nudge exits Claude, then the hold disarms the watcher

**Pane 332 (2e9ed9f2)** (M: `~/.reso/limit-recover/move/20261018T070336Z-next-next3-37630/2e9ed9f2-….handoff.log`, `handoffs.jsonl`, and the watcher log `/var/folders/…/handoff-recycle-332-1792308018-59eorR.log`):

| time | event | source |
|---|---|---|
| 07:20:18 | watcher 77512 armed | watcher log line 1, epoch 1792308018 |
| 07:23:01 | claude pid 39396 ends: exit 0, no signal, class RECYCLE | `claude-crashes.jsonl` 07:23:20Z, close record `close-records/39396-1792294796.json` |
| ~07:22–07:24 | `pane 332 CONFIRMED at a shell prompt after 125s — typing relaunch` | watcher log |
| 07:24:22 | watcher types the disarm line (`line=disarm … verdict=submitted`) | `handoffs.jsonl` |
| 07:24:33 | foreground holds: `recycle-held-load … load 15.72/core > 8/core … unconfirm rc 2`. The unconfirm answer was `{"reason":"source-dead"}`, yet the operator text says "/exit NOT submitted … The session stays alive" (false) | `handoffs.jsonl`, handoff.log:44-45 |
| 07:24:45 | `STRANDED … the source pane 332 is a tombstoned husk with no successor carrying it` | `bundle-20261018T071345Z/events.jsonl` |

**The same shape on the other stranded moves** (M: per-sid `handoff.log`):

| pane | session | claude exited | hold | unconfirm answer | load |
|---|---|---|---|---|---|
| 1 | e52f1f63 | 07:06:31 | 07:06:39 | `stub-present` | 27.26/core |
| 21 | 5232121f | — | — | `stub-present` | 27.26 |
| 242 | 0d7c9a19 | — | 10:39:28 STRANDED | `stub-present` | 31.54 |

No stranded log contains `→ exit: typed /exit`. The foreground never typed it.

**The successful moves in the same batches prove who typed `/exit`.**
- Pane 8 (43e6eb4b): intent at 07:09:05. The watcher then answers `recycle-bgwork-stopped-dead-source background-work dialog at 75s` at 07:10:51, so a `/exit` had been submitted near watcher-second 60. Claude exits at 07:11:14. The foreground's own line is `exit: NOT typed — claude pid 26335 exited on its own before the last read`.
- Pane 47 (7b50757e): `recycle-subject-exited … exited on its own before the last read`.

When the exit lands before the foreground's subject check 1, the move succeeds. When it lands after check 1 and before the load gate, the move strands.

**The code (M):**
- `scripts/handoff-fire.sh:11718-11741`, watcher nudge at 60, 150 and 300 s: `retype` sends `/exit` plus CR when the composer is empty and Claude is alive.
- `recycle_nudge_decision`, `:5409-5422`: an empty composer returns `retype`, whether or not the foreground ever typed.
- The watcher's wait loop starts at arm time (`:11395`).
- The foreground tail (`:18586-18604`) is: subject check 1, then the last read, then the load gate and its `hf_recycle_hold`. Check 2 comes only after the load gate (`:18612`).
- `hf_recycle_hold` (`:3615-3651`) unconfirms and disarms without asking `hf_recycle_subject_gone`.

**(I) Why this attribution holds.** The watcher's 60-second retype is the only arm on this path that types `/exit`, and the retype arm writes no log row. The timing matches in all six moves. I did not find a logged line that names the retype firing.

### 2.4 The staged successor (`~/.claude/run/pane-successor/`): it ran, but was not used for the step that failed

- **It ran (M).** On pane 1, three fresh self-recycle generations each ran their staged successor (`ttys000.claimed.2587` → `.19793` → `.22242`; stage file `ttys000.json`: pane 1, mode `fresh`). On pane 242, `ttys005.claimed.18978` (mode `fresh`) ran. The "running the staged successor" lines on screen are those earlier generations, and they worked.
- **The failing step never stages (M).** The last hop on each stranded pane was a move-lane resume/transplant recycle, and that kind never stages. handoff.log prints `→ successor: resume recycle — not staged; the watcher types the relaunch after its rails`, by design (`handoff-fire.sh:4527-4529`): "Resume, transplant and remote recycles never stage". So its relaunch has to be typed, and typing is exactly what the load hold blocks: "no successor of ours staged for /dev/ttys00N".
- **Why the shell stays.** Every shell-keeping branch exists so that a typed relaunch has a prompt to land on:
  - `lr-fire-resume.sh:1859-1870` always `exec $SHELL -l -i`, even after rc 0;
  - `cc-close-attrib:627` closes the pane on exit only when `CC_CLOSE_PANE_ON_EXIT=1`, which is unset everywhere (M: `git grep`; `~/.zshrc`, `~/.zprofile` and `~/.zshenv` contain no such setting);
  - panes 1, 242 and 332 are operator-opened `zsh -l` roots, not cc-pane-runner panes.

  When the relaunch is then disarmed, nobody owns that shell.

### 2.5 The watchdog says one thing and its closer does another

`lead-crash-watchdog.log` (M):

```
02:07:23 CDT … PAINTED on ttys000 (pane 1): ✅ CLOSED CLEANLY — e52f1f63 exited on its own
02:07:46 CDT … pane close of 1 via cc-pane-close rc=1: REFUSED — nothing says session e52f1f63 meant to end
05:40:54 CDT … pane close of 242 … REFUSED — nothing says session 0d7c9a19 meant to end
```

- The banner (`hooks/lead-crash-watchdog.sh:1733-1742`) tells the operator the pane is safe to close, while the closer refuses. Neither one sees the transplant tombstone (`*.HANDOFF.json`) or the `STRANDED` verdict.
- The resume line uses the source account's launcher, which is wrong after a move: `claude4` for a session on next2, and `claude` for one on next3.

## 3. Causal chain

- **A. Move lane, 06:49–10:39Z.** Batches `064955Z-next4-next2`, `070336Z-next-next3` and `101826Z-next-next3`, placed by `cc-lr move`.
  1. The recycle is armed.
  2. Within 60 s the watcher retypes `/exit` while the foreground is still in confirm and last read (load 15–37/core).
  3. Claude exits with code 0.
  4. The foreground's load gate holds, after the exit, and disarms the watcher.
  5. The unconfirm fails (`source-dead` / `stub-present`), so the verdict is `STRANDED`.

  The visible state follows from who owns the pane:
  - **Pane 332.** It runs under lr-fire-resume, so that script's unconditional `exec $SHELL` produces the "ordinary shell" banner (family 2).
  - **Panes 1 and 242.** These run under the successor loop (pane 1) or plain `zsh -l` (pane 242), with no lr-fire-resume in between. The watchdog paints "CLOSED CLEANLY … safe to close", and cc-pane-close refuses (family 3).
  - **Pane 21** (5232121f) was later closed by someone (it is absent from `kitten @ ls`).
- **B. Rescue agent 2cc3a7fa (pane 344), 07:13–10:55Z.** It acted on the `STRANDED` verdicts but bypassed the rail the verdict names (`lr-fleet.sh --one <sid>`). The verdict says "do NOT hand-spawn a recover window", and the agent instead hand-wrote `/tmp/lr-rescue/resume-*.sh` and ran `handoff-fire.sh --launcher … --tab`, in parallel.
  1. The outer gate admits.
  2. A new tab opens in OS window 18.
  3. The inner gate refuses (counting its siblings' tokens) and exits 9.
  4. cc-pane-runner keeps the shell.

  The agent re-fired to use up the 3-refusal budget, so every retry added a tab. The result is 12 exit-9 tabs plus 403 (its own cwd bug), and OS window 18 now has 18 tabs (symptom b).
- **C. Poller autofire, 10:00:12Z.** It spawns 509e3aad in a new OS window 24 with no token. The inner gate refuses (exit 9) and the runner keeps the shell. The poller has already logged RESUMED. It later refunds the attempt and recovers the session in pane 28 (10:25:56Z), but never closes window 428.

## 4. Immediate remediation (described, not performed)

### 4.1 When a shell pane is safe to close

Close a shell pane only when all four of these hold:
1. Its tty has only shells in the foreground (true for all 17 at the snapshot).
2. No recycle watcher is alive for the pane (`cc_pane_recycle_pending <win>` is false, and no `__recycle` process exists for its tty).
3. The session it last held is LIVE elsewhere, or its transcript is complete on the target store and a recovery owner exists. A shell pane holds no conversation; the transcript is on disk, so closing it loses only scrollback.
4. If it is the last pane of its OS window, the close goes through `kitty-fullscreen-guard`, because of the 2026-10-15 kitty crash.

### 4.2 Close now (live copy confirmed elsewhere)

- 403, 409, 412, 416 → 5232121f is live in pane 429.
- 410, 413, 419 and **1** → e52f1f63 is live in pane 430.
- 418, 426, 435 and **332** → 2e9ed9f2 is live in pane 442.
- 414, 417, 425 → 22a76c8a was resumed in window 433 at 10:44Z, and its work continued there in a successor.
- 401 → the driver shell. Its batch is finished (NOTMOVED) and f06b5e9b is live in pane 350.
- 428 → 509e3aad is recovered in pane 28. Window 428 is the **only pane of OS window 24**, so close it through `kitty-fullscreen-guard --window 428 --mode toggle --scope pane --then close-window`, or have the operator Cmd-W it after leaving fullscreen.

`cc-pane-close` will refuse these, as it did for panes 1 and 242, because there is no custody ruling. A direct close behind the fullscreen guard is the way to do it. Afterwards, re-read `kitten @ ls` to confirm.

### 4.3 Pane 242 is not a plain close: start the successor first

0d7c9a19 runs nowhere. Its full transcript is on next3, and a 4,249 B stub on next still needs folding.

1. Re-drive it on the rail, in place: `lr-fleet.sh --one 0d7c9a19-0b8b-4cfc-ac61-5f30e12aedbe --source-pane 242`. The rail folds the stub and launches on next3.
2. Close 242 only if the successor comes up elsewhere.

Do **not** type the banner's `claude --resume 0d7c9a19`, which opens the next-account stub.

### 4.4 Pane 344 (rescue agent 2cc3a7fa, live)

Tell it to stop: all four of its targets are live now, and another `fire-round.sh` round only adds tabs. Ask it to close the tabs it opened (the list in 4.2).

### 4.5 Not tested here

`cc-husk-sweep` (list mode) was refused by the auto-mode classifier in this read-only run. The census above was built by hand instead.

## 5. Long-term fix (file:line targets) and the tests that would have caught it

### F1, the race root (`scripts/handoff-fire.sh`)

The watcher must not exit Claude before the foreground commits.
- In `recycle_fire_commit`, have the foreground write `$cmdfile.exit-committed` immediately before either exit actuator: after check 2 at `:18612`, before `hf_exit_signal` (`:18626`) and the typed `/exit`.
- In the watcher nudge (`:11718-11741`), allow `retype` and `cr` only when that file exists. Before that, the decision is `pre-commit` and the watcher does nothing.
- Log a `recycle-nudge-retype` row from the retype arm. Today it is silent, which is why this attribution rests on timing.

### F2, the hold (`:3615`)

A hold must never disarm a watcher whose subject is already gone.
- `hf_recycle_hold` should first call `hf_recycle_subject_gone || at_shell(tty)`. If either is true, call `hf_recycle_subject_yield "at the <reason> hold"` and return 0.
- Add a subject re-read between the last read and the load gate (`:18596`).
- When unconfirm returns `source-dead` or `stub-present`, the operator text must not say "The session stays alive". It should name the yield instead.

### F3, make the move-lane relaunch keystroke-free

- Stage a successor for resume/transplant recycles too (`handoff-fire.sh:4527-4529` and `lib/pane-successor.sh`). The staged command is the lr launcher itself (`bash <bundle>/lr-launch-*.sh`, which already runs `lr_launch_guard`, the fold and the holder rails inside lr-fire-resume).
- A staged claim proceeds at any load (`:3946-3948`), so the load hold stops applying to moves.
- Until then, enforce commit `d58bb81d3` (K3, hold on load in the precheck before the transplant) for every move-lane caller: assert `HF_PRECHECK_TYPED_RELAUNCH=1` from `lr-handoff`'s in-place path.

### F4, family 1 (`scripts/limit-recover/lr-fire-resume.sh:777-797` and `bin/cc-pane-runner:179-182`)

A refusal in a pane the fleet just created should requeue the session and close the pane.
- On a gate refusal, when the pane was created for this launch (`CC_PANE_RUNNER_OWNS_CLOSE=1` or `LR_RUN` set), write a request to `~/.reso/limit-recover/requests/` with reason `gate-refused` and exit 75.
- In `_close_on_exit`, treat 75 from an interactive fleet launch line as "requeued, close", still behind the fullscreen guard.
- Change the refusal text from "re-run this exact command" to "requeued to the poller; this pane closes".

### F5, one admission decision

- When handoff-fire's outer gate admits a `--launcher` fire, it mints the same `LR_ADMIT_TOKEN` that lr-fleet mints and passes it to the launcher. The inner gate then redeems it instead of re-evaluating.
- Align the terms: the outer `_cc_fire_bound active` (`handoff-fire.sh:10463`) must count tokens in flight the way `capacity-admit` does, or the two gates will keep disagreeing.
- Apply the same to the poller (`lr-reset-poller.sh:2589-2601`): probe or mint before the spawn, and log `RESUMED` only after reading `relaunch.rc`. On rc 9, close the pane it opened and refund at once.

### F6, the watchdog and the closer understand a move

- `hooks/lead-crash-watchdog.sh:1733` gets a new arm. When `<sid>.HANDOFF.json` exists or the session's lr verdict is `STRANDED`, paint `MOVED to <target> — relaunch was disarmed; the rail is re-driving it`, and enqueue `lr-fleet --one`. Never paint "exited on its own … safe to close" for such a session.
- The reopen line resolves the launcher from the store that holds the full transcript (claude2 or claude3), not from the source.
- `bin/cc-pane-close` accepts "moved, and a live successor or a queued request exists" as a custody ruling. That lets it close panes 1, 242 and 332 by itself once a successor is up.

### F7, rails, not hand-rolled rescues

- `handoff-fire.sh --tab` with `--launcher <path under /tmp>` should refuse, pointing at `lr-fleet.sh --one`. The STRANDED text already forbids hand-spawned recover windows, but nothing enforces it.
- `--tab` itself is symptom (b): the operator does not use tabs.

### Tests that would have caught it

- **`tests/handoff-fire-watcher-nudge-precommit.bats`**
  - Stubs: a fake it2 whose composer reads empty, and a foreground tail slowed past 60 s through `hf_recycle_last_read` / `HF_LOAD_PER_CORE` seams.
  - Assert: the watcher sends no `/exit` before `$cmdfile.exit-committed` exists.
  - Fixture: the pane-332 timeline, beside the existing `tests/fixtures/move-lane-2026-10-17/pane7`.
- **`tests/handoff-fire-hold-after-subject-gone.bats`**
  - Setup: the subject pid exits between the last read and the load gate, and load is above the bound.
  - Assert: `hf_recycle_hold` yields (a `recycle-subject-exited` row), never calls `hf_recycle_disarm`, and the watcher types the relaunch.
- **`tests/cc-pane-runner-gate-refusal-closes.bats`**
  - Run: `CC_PANE_CMD_INTERACTIVE=1` with a launcher that writes a request and exits 75.
  - Assert: the runner exits (the pane closes) and the request file exists.
  - Control: exit 9 without a request still keeps the shell.
- **A parity test.** For the same capacity fixture, handoff-fire's outer gate and capacity-admit's inner gate must return the same verdict when a token is carried.

## 6. Confidence and what would change it

**Overall: 85%.**

| finding | confidence | basis |
|---|---|---|
| Family 1 (two gates, rescue tabs, poller) | 95% | screens, logs and transcript all agree |
| Hold-after-exit disarm | 95% | same order in four logs, plus the code |
| The watcher's 60 s retype is what exits Claude | ~80% | inferred from timing in six moves and from the code; the retype arm writes no log row |

**What would change it:**
- If another actor typed the `/exit`, for example a self-close from the session or a second move worker on the same pane, F1 would be aimed at the wrong place, though F2 would still stand. A `recycle-nudge-retype` row, or a pty capture of the next strand, settles it.
- If 0d7c9a19 turns out to be finished work (its last close verdict reads `-`), then 4.3 becomes a plain close rather than a relaunch.

## Adversarial verification

Done 2026-10-18 13:30–13:40 CDT, read-only. I re-opened every cited line and log myself.

**Verdict: NOT REFUTED.** Both mechanisms hold against the code and the logs, and the attribution of who typed `/exit` is stronger than §6 claims. There are four corrections. One of them is a safety bug in the proposed fix F2.

### Citations that checked out (M)

- `handoff-fire.sh`:
  - `:11718-11741`: the nudge arm. `retype` at 60 s sends `/exit` and then a CR, and writes no log row.
  - `:5394-5406`: `recycle_nudge_decision`, where an empty composer returns `retype`.
  - `:11389-11395`: the wall-clock latches start at loop t0.
  - `:3612-3651`: `hf_recycle_hold` unconfirms, then disarms; `:3341-3345` shows the disarm is `kill $WATCHER_PID`.
  - `:18586-18612`: check 1, the last read, the load gate, then check 2.
  - `:4527-4532`: "Resume, transplant and remote recycles never stage".
  - `:10463`: the outer gate counts no tokens.
- `lr-fire-resume.sh:777-797`: refuses, prints "re-run this exact command", and exits 9. `lr-fire-resume.sh:1870` ends in `exec $SHELL -l -i`.
- `cc-pane-runner`: keeps the shell on a non-zero exit.
- `cc-close-attrib` `_cca_close_pane`: `CC_CLOSE_PANE_ON_EXIT:-0`.
- `lr-reset-poller.sh:~2600`: logs RESUMED right after `spawn_resume`.
- `lead-crash-watchdog.sh:1733`: the `RECYCLE:*` banner. Its launcher comes from `pane_launcher_for_cfg "$LEAD_CFG"` (`:1674`), which is the source account, so the wrong-account claim holds.

### Evidence the doc missed, all supporting "the watcher's 60 s retype exits Claude"

- **Pane 242 watcher log** (`/var/folders/…/handoff-recycle-242-1792319809-5YgRrY.log`, M):
  - The log reads `bgwork@101s: the /exit raised the background-work dialog; stop-if-watcher answered '1'`.
  - So a `/exit` was submitted within 101 s of arming (10:36:49Z). The foreground never typed one: it held at load. Only the watcher could have submitted it.
  - The watcher then also answered the dialog. This ties family 3 to symptom (d).
- **Pane 332 watcher log** (M):
  - It has no `nudge@60s HELD` line. Only the `cr` and `retype` arms are silent.
  - The precheck read `composer: empty`, and the foreground never typed. That leaves `retype`.
- **Pane 332 exit record and transcript** (M):
  - Close record `39396-1792294796.json`: `exit_code 0`, `signal ""`. That is a submitted `/exit`, not a SIGTERM.
  - The next3 transcript has a `file-history-snapshot` at 07:22:53.945Z, 7 s before the exit at 07:23:01. That is a submit event (I).
- **The same race one day earlier**, commit `475d66ced` (pane 7, 2026-10-17):
  - The watcher armed at 07:54:14 and claude exited at 07:55:26, 72 s later.
  - The commit says "What ended 65405 … is not recorded anywhere on disk (no recycle row, no keystroke log…)". That is the silent retype arm.
  - That fix added the subject re-reads but put none before the load hold. So this incident is the unfixed half of the same defect.

### Corrections

1. **The doc's claim that "the tokens in flight are the sibling rescues' own" (§2.2) is wrong (M).**
   - The rescue launchers carry no token (`/tmp/lr-rescue/resume-5232121f.sh`).
   - `cc_capacity_admit` does not mint a token when it admits. The only callers of `cc_capacity_token_mint` are `lr-handoff.sh:1554`, `lr-upgrade.sh:2006`, `lr-fleet.sh:1369` and `lr_recon/admit.py:202`.
   - So the tokens in flight belonged to other lane actors (moves, fleet, recon). Some were likely minted for moves that then held or stranded and never redeemed them. Those still count for the 1,020 s TTL (`capacity-admit.sh:1095-1121`) (I).
   - F5 should add: every hold or stand-down that minted a token deletes it.
2. **One outer-gate row is misquoted (M).** The 08:40:44Z row (`handoffs.jsonl:950`) reads `7 sessions mid-turn (ceiling 8)`, not 6. The point stands: 7+1 is not over 8 for the outer gate, while 7+tokens+1 is over 8 for the inner gate.
3. **F2 as written is unsafe.** `hf_recycle_hold`'s contract is `exit 1`, and none of its callers expects it to return.
   - If it yields with `return 0`, control falls through. At `:18633` (exit-signal-ignored), the next statement after `esac` is `hf_exit_readback` (`:18646`). That types `/exit`, possibly into the watcher's fresh relaunch, which is the pane-7 failure again.
   - The yield must instead go at each call site, `if hf_recycle_subject_gone; then hf_recycle_subject_yield "…"; return 0; fi`, before the hold calls at `:18595` and `:18603`. Or the hold must `exit 0`.
   - `at_shell` is a watcher-local function (`:10676`, `:11202`) and does not exist in the foreground. Use `pane_cc_state "$tty"`.
4. **F3's "meanwhile enforce K3" is already done.**
   - `d58bb81d3` landed at 12:14Z (07:14 CDT), after every strand (07:06Z, 07:24Z, 10:39Z). `lr-handoff` already sets `HF_PRECHECK_TYPED_RELAUNCH=1`.
   - With it deployed, these moves would have held before the transplant (load 15–37/core against a bound of 8) (I).
   - F1 and F2 are still needed for load that rises between the precheck and the gate, and for the silent retype in general.
5. **The rescue code ran from the main checkout (M).** The rescue launchers exec `/Users/chrisren/Development/claude-infrastructure/scripts/limit-recover/lr-fire-resume.sh`, not the `~/.claude` layer. So the inner gate's code version is whatever that checkout held at the time.

### The live state changed after the census (M: `kitten @ ls`, 13:35 CDT)

- None of the 17 husk panes exist any more: 1, 242, 332, 401, 403–435 and 428 are all gone. Every OS window now has exactly 1 tab. Section 4.2 has been carried out by someone.
- **Pane 242 was closed before its successor came up, which is what §4.3 said not to do.**
  - `pgrep -fl 0d7c9a19` is empty.
  - The transcript is intact: next3 holds 2,672,309 B (mtime 05:12 CDT), and the next stub is 4,249 B.
  - Re-drive it with `lr-fleet.sh --one 0d7c9a19-0b8b-4cfc-ac61-5f30e12aedbe`, without `--source-pane`, because the pane is gone.
- **Pane 429 (5232121f) is alive but has gone quiet.**
  - Its composer still holds an unsubmitted `/limit-recover to account 3`, and its transcript was last written at 10:06 CDT.
  - `idl.jsonl` shows lead-supervisor `ESCALATED … pid alive but … transcript 11947s stale` at 18:26Z.
  - "LIVE" in §2.1 means only that the process is alive.

### Fixes checked for collateral damage

- F4 and F6 close only panes whose foreground is a shell after a gate refusal (no claude was ever spawned) or a move. A shell holds no transcript, so neither fix can close the only copy of a session.
- F1 keeps the typed-but-lost `/exit` rescue, because the marker is written before the foreground types. `recycle_fire_commit` (`:18501`) is the only commit path (caller `:19309`).
- The self-close twin's retype (`:10716-10721`) is a different case, because the subject itself chose to exit. Leave it alone.

**Confidence after verification:**

| finding | confidence |
|---|---|
| Recycle race (retype, then hold-after-exit) | 90% |
| Two-gate family | 90%, with the token-source sub-claim corrected |
| Overall | 85% |
