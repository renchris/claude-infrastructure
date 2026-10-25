# Pane lifecycle map: launch, claude exit, and what keeps the shell alive (pane 289, 2026-10-24)

Mapper: lifecycle. Read-only. Repo: `/Users/chrisren/Development/.worktrees/wt-cc-203953-20264`.
The live layer `~/.claude/bin/cc-pane-runner` is a symlink to `~/Development/claude-infrastructure/bin/cc-pane-runner`,
and that copy matches this worktree's byte for byte (measured: `diff -q` gave no output).

## 1. How a fleet pane is launched

1. **Producer argv.** handoff-fire builds the launch line first and passes it as env plus argv:
   `scripts/handoff-fire.sh:1325-1326`:
   `--env CC_PANE_CMD=$CMD --env CC_PANE_CMD_INTERACTIVE=1 --env CC_PANE_RUNNER=… -- $SHELL -l -i -c 'exec /bin/bash "$CC_PANE_RUNNER"'`.
   bin/it2-kitty adds this to `kitty @ launch --type=window --location=… --keep-focus` (`bin/it2-kitty:1301`,
   `:1358-1363`). The argv-less file mode for Claude Code teammate splits is at `bin/it2-kitty:1378-1379`.
2. **What kitty actually runs** (measured with `ps -axo pid,ppid,tty,command`, kitty pid 1881):
   `/usr/bin/login -f -l -p chrisren …/kitten run-shell --shell /bin/zsh -l -i -c 'exec /bin/bash "$CC_PANE_RUNNER"' --shell-integration enabled --cwd=…`.
   kitty wraps the command in macOS `login` and in `kitten run-shell` (shell integration). Both hand over by exec,
   so the process tree of a live pane (ttys006, measured) is:
   ```
   2018 login (ppid 1881 kitty)
    └ 2197 /bin/bash cc-pane-runner          ← the zsh -l -i -c exec'd into it: the runner IS the window's process
       └ 5053 /bin/zsh -l -i -c "cd … && … claude4 …"   ← CC_PANE_CMD_INTERACTIVE=1 branch, cc-pane-runner:571-572
          └ 25452 bash cc-close-attrib → 25920 claude
   ```
   File mode uses `eval "$1"` in the runner's own process instead (`cc-pane-runner:574`).
3. **kitty options** (`~/.config/kitty/kitty.conf`): `close_on_child_death no` (:1038, kitty's default),
   `confirm_os_window_close -1` (:1031), `macos_quit_when_last_window_closed no` (:1034). No launch uses `--hold`
   (measured: no `--hold` in `bin/it2-kitty` or `scripts/handoff-fire.sh`). ⌘W is remapped to `kitty-confirm-close` (:279).
   So **the window closes exactly when its root child (login→runner) exits.** `close_on_child_death no` only keeps a
   window whose root exited while other processes still hold the pty. That did not apply here: the orphaned zsh
   forks on ttys006 (pids 6392 and 6395, ppid 1) have fds 1 and 2 on /dev/null, not on the tty (measured with `lsof -p 6392`).

## 2. What happens when claude exits (cc-pane-runner)

`_launch` (`bin/cc-pane-runner:546-580`) runs the command, writes the exit record `~/.claude/run/pane-exit/<wid>.json`
(`:576-577`, contract at `:377-395`), then calls `_close_on_exit` (`:257-278`), then **`_fallback ""` (`:579`)**.

- `_close_on_exit` closes only on rc 0, rc 75, or (claude never started AND an owed record exists) (`:267-276`).
  Every other rc goes to `_kept_line` and returns, which means a shell.
- `_close_pane` (`:283-349`) closes only if three gates pass, in this order: the recycle lib loads and nothing is pending
  (`:286-298`), then `kitty-fullscreen-guard --mode refuse --scope pane` returns 0 (`:305-344`). Only then does it `exit 0` (`:348`).
  **Any guard rc≠0 returns 0 ("keep"). The cases are refused-fs (`:331-335`) and unreadable/kitten-failed (`:336-340`).**
- `_fallback` (`:100-105`) ends in **`exec "${SHELL:-/bin/zsh}" -l -i`** (`:104`). This is the single line that turns
  a pane into a husk. Once it runs, the runner is gone and the window's process is an interactive login zsh, which lives
  until something external closes it (⌘W, `kitty @ close-window`, or a SIGHUP from `cc-pane-close:538`). Its header calls the
  shell the parity default: "we `exec` an interactive login shell when the command returns" (`:46-51`).
- The no-command deadline path (`:614-623`) also ends in `_fallback` when its guard refuses.

**Answer to "what keeps the shell alive":** not kitty, not `--hold`, not `close_on_child_death`. It is the runner's own
`exec $SHELL -l -i` at `bin/cc-pane-runner:104`, reached at `:579` whenever any keep branch fires. A *transient
safety refusal* (fullscreen-last pane, or kitty not answering) gets the same answer as a crash, a pending recycle, or the
kill switch: a permanent interactive shell. The runner throws away the one capability that needs no socket and
no gates, which is closing from inside by exiting.

## 3. Pane 289 timeline (all times Z, 2026-10-24/25)

| time | event | evidence |
|---|---|---|
| 23:23:13 | handoff-fire places 289 into os-window 25 (`panes_before:2`, anchor 13) | `pane-spawns.jsonl` row `"pane":"289"…"os_window:25 step:2 panes_before:2"` |
| 23:53:23 | self-close types `/exit` into 289 | `pane-keys.jsonl` `"head40":"/exit\r","verb":"type"` |
| 23:53:36 | claude exits **rc 0, claude_started true** | `~/.claude/run/pane-exit/289.json` = `{"rc":0,"claude_started":true,…,"ts":1792886016}` (`date -r` gives 23:53:36Z) |
| 23:53:36.772 | runner's guard: **refused-fs, panes:1, state FS, types [4], onscreen:false** (289 is the only pane of fullscreen os-window 25, which is on a Space the display is not showing) | `kitty-pane-actions.jsonl` `"wid":289,"os_window_id":25,"panes":1,"state":"FS","onscreen":false,"verdict":"refused-fs","caller":"cc-pane-runner"` |
| 23:53:37 | runner paints DONE "⌘W closes it · last pane of a fullscreen window", logs `kept: last pane of a fullscreen window`, then `exec zsh -l -i` | `pane-say.jsonl` ts 1792886016/1792886017 |
| 23:53:38 | handoff-fire self-close `hf_close_pane` → it2-kitty guard refused-fs again → rc 70 → `STILL-PRESENT-rc70` | `close-attrib.jsonl` row for 289; guard row `caller:"it2-kitty"` 23:53:38.874; mapping at `scripts/handoff-fire.sh:1928-1935` |
| 23:54:59 | lead-crash-watchdog: "ended cleanly … last close verdict: yes … dirty:138", paints CANTTELL | `pane-say.jsonl` ts 1792886100 |
| 00:00:13 → 01:38:50 | pane-close-retry gives the husk row to `cc-pane-close` 21 times: 9 refused at **gate 4** "138 uncommitted change(s)" (`bin/cc-pane-close:508-512`) and 12 rc 124 (60 s bound) | `pane-close-retry.log` lines 25849-25936 |
| 00:00:14 | `cc-pane-verdict --recompute` maps the gate-4 text to RESUME ("⛔ resume 7555024a / 138 unsaved files") | `bin/cc-pane-verdict:86-87`; `pane-say.jsonl` ts 1792886414; `~/.claude/run/pane-verdict/1881-289.json` |
| **00:24:52 / 00:26:51** | **panes 295 and 296 placed into os-window 25. From this point 289 is NOT the last pane, so the guard would return safe-not-last.** Nothing re-asked the runner-level question, because the runner had already exec'd away | `pane-spawns.jsonl` rows for 295 and 296; `kitten @ ls` now shows os 25 = [295, 296] |
| 01:45:55 | retry row removed: "its tty was typed in since  — the operator owns it" (note the empty `first_ts`) | `pane-close-retry.log:25942`; `scripts/pane-close-retry.sh:279` |
| ≤ 01:53 | window 289 is gone. Measured: `kitten @ --to unix:/tmp/kitty-1881 ls` has no window id 289. No close-attrib, pane-close or kitty-pane-actions row records the close, so it went through an unlogged path (the tty atime moved at 01:45, consistent with the operator typing at it) | `/tmp/lifecycle-kls.json` |

**Current pane state: closed.** No open, resume or close action is needed for 289. Its session ended on purpose (rc 0,
`prompt_input_exit`, "Good to close: yes"), so RESUME was the wrong verdict.

## 4. Root cause (lifecycle view)

1. **A ruled close becomes a permanent shell on a transient precondition.** The runner had already decided "close"
   (rc 0, no recycle). Only the crash-safety precondition (fullscreen last pane) failed, and that precondition cleared 31 minutes later
   when 295 joined. `_close_pane` returns "keep" (`:342`) and `_fallback` execs a shell (`:104`), so the decision is
   lost. That leaves the close to outside actors.
2. **The outside closer re-judges the intent with different, stricter gates.** `cc-pane-close` was built for husks
   whose intent is unknown, and it re-runs session gates 3 and 4 (`bin/cc-pane-close:25-34`, `:190-213`). Gate 4 counts the whole
   shared checkout's `git status`, which was 138 files from sibling sessions in `~/Development/personal`. Its exit-record arm accepts only
   `claude_started=false && rc≠0` (`:424`), so the runner's own record "rc 0, started" carries no weight. The runner's
   policy (close on rc 0) and the closer's policy (rc 0 is not enough, the cwd must be clean) contradict each other, and
   `cc-pane-verdict --recompute` then reads the contradiction as RESUME (`bin/cc-pane-verdict:86-87`).
3. **The close-on-exit decision is copied per launcher, and some launchers never close.** Measured with
   `grep -rn 'exec "${SHELL' bin scripts lib`:
   - `bin/cc-pane-runner:104`: shell on any keep (the gated close is at `:283-349`).
   - `bin/reso-resume-one:1145-1186`: a second, hand-copied close (rc 0 + recycle + guard). A guard refusal at `:1177-1179`
     falls through to `exec $SHELL -l -i` (`:1216`) and writes **no husk row**, so nothing ever retries it.
   - `scripts/limit-recover/lr-fire-resume.sh:2249-2304`: **always** `exec $SHELL -l -i` in a real pane, even after a
     clean rc 0. There is no close-on-clean-exit branch. When it runs inside cc-pane-runner (lr-lib `bash <resume script>`), the runner
     never gets control back, so it writes no exit record for the session's end and no husk row.
   - `lib/pane-successor.sh:236-240`: a staged successor runs with a trailing `exec $SHELL -l -i` by default.
   - `scripts/boot-resume-launch.sh:258` and `bin/cc-resume-layout.sh:1053,1359`: `zsh -ic "$CMD || exec zsh -i"`.
   - `lib/pane-successor.sh:337-341`: the zshexit hook execs `zsh -i` again when the guard refuses.
4. **A doctrine pins the shell as the default.** `scripts/boot-resume-launch.sh:240-242`: "any pane an agent may later be asked
   to recycle must end its command with an interactive shell". It cites
   `docs/research/recycle-pane-survivability-2026-08-26.md`. It made sense while recycle *typed* its relaunch at a prompt. Since
   `lib/pane-successor.sh` (keystroke-free staged successor, claimed by whichever process regains the tty), it no longer
   holds: recycle needs a **consumer of the stage**, not an idle shell.

## 5. How often this happens (measured)

`jq` over `~/.claude/logs/kitty-pane-actions.jsonl`, rows with `caller=="cc-pane-runner"` and phase verdict, since
2026-10-15T08:55Z: **390 runner close attempts. 36 refused and became shells:** 13 refused-fs, 22 kitten-failed,
1 refused-unknown. The rest were 348 safe-not-last, 3 safe-windowed and 3 safe-windowed-offscreen. On 2026-10-24 alone, os-window 25 (fullscreen,
off-screen) produced three of these husks: 280 (21:32Z), 282 (22:41Z) and 289 (23:53Z). Their retry outcomes, from `pane-close-retry.log`:
- 280: 18 attempts, then closed.
- 282: held for ⌘W 23:08-23:19. Released when "os window + panes: 25 1 → 25 2". Gone 23:30.
- 165 (2026-10-23): ≥23 refused-fs attempts while off-screen.

The retrier's hold-until-window-changes (`scripts/pane-close-retry.sh:280-286`) already *detects* the moment the
precondition clears. It then gives the close to the session gates instead of the runner's ruling.

## 6. The simplest structural fix: "claude exits ⇒ window closes unless a recorded reason says keep"

**One tail, owned by the window's own process, where keeping a shell needs a named reason.**

A. **Invert `_fallback` in cc-pane-runner (one file).** After the command returns:
   1. A staged successor for this tty (`cc_pane_successor_take`) ⇒ exec it. That covers recycle without needing an idle shell.
   2. Recycle pending (`cc_pane_recycle_pending`) ⇒ exec a shell, with `keep:"recycle"` recorded in the exit record.
   3. `rc≠0 && claude_started` (crash) ⇒ exec a shell, with `keep:"crash"`. This is the human-call case the watchdog paints.
      `CC_PANE_CLOSE_ON_EXIT=0` ⇒ exec a shell, with `keep:"kill-switch"`.
   4. **Everything else ⇒ close. If the guard refuses, HOLD; never exec a shell.** The runner stays the window's process.
      It paints "✓ done · closes when this window has another pane or leaves fullscreen · any key = shell" and loops:
      re-ask `kitty-fullscreen-guard --scope pane --mode refuse` on a backoff (for example 5 s, rising to 60 s), and `exit 0` once it returns 0.
      Any byte on the tty (`read -t`) is operator takeover and execs a shell, with `keep:"operator"`.
      Write `{"state":"close-held","reason":"guard-fs|guard-unreadable"}` to `pane-exit/<wid>.json`, so auditors can read it.
   The close never needs a socket and never meets session gates: the process that knows the intent closes the pane.
   With this, pane 289 would have closed itself at about 00:24:52 when 295 joined, and 282 at about 23:19. kitten-failed (22 of 36) clears
   as soon as kitty answers again.
B. **Make it the only tail.** Move steps 1-4 into one sourced lib (for example `lib/pane-tail.sh: cc_pane_tail <rc> <started>`) and
   call it from `cc-pane-runner:579`, `reso-resume-one:1183-1216` and `lr-fire-resume.sh:2249-2304` instead of their own
   shell tails. Change the `|| exec zsh -i` wrappers (`boot-resume-launch.sh:258`, `cc-resume-layout.sh:1053,1359`) to call
   the same tail. Retire the doctrine at `boot-resume-launch.sh:240-242`, since the staged successor replaced the typed relaunch.
C. **Stop the auditors from re-judging a ruled exit.** In `cc-pane-close`, an exit record with `rc==0 && claude_started` that
   post-dates the registration satisfies gates 3 and 4, symmetric to the never-launched arm at `:424`. `cc-pane-verdict --recompute` and
   `cc-husk-sweep` then read the same record, and a `close-held` record maps to DONE, never RESUME. Gate 4's shared-checkout
   false positive (sibling sessions' files) is a separate defect for the gate mapper. Once (A) is in place, this path only matters for legacy husks.

What NOT to change: kitty's `close_on_child_death` and `--hold` are not involved, and the `login`/`kitten run-shell` wrapping
already gives exit ⇒ close. The crash guard itself is correct. Only the runner's *reaction* to it (exec a shell) is the defect.

## 7. Side findings

- `scripts/pane-close-retry.sh:279` prints `$(pcq_get "$row" first_ts)` as empty ("typed in since  —"): the row has no `first_ts`.
- Typed transport (`FIRE_ARGV_LAUNCH=0`, or a missing runner at `bin/it2-kitty:1364-1365`) makes the pane root an interactive
  shell, so every claude exit leaves a shell. Fix (A) covers only runner-launched panes, so these paths should refuse rather than degrade.
- Why 289 ended up alone in a fullscreen off-screen window (placement policy filling os-window 25) is outside this map, but it is the
  trigger of all three husks from 2026-10-24.
