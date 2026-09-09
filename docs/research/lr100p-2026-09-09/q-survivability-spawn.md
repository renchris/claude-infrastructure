# Q — Survivability & spawn shape: making every recovered pane recyclable and husk-free

Research artifact for `docs/plans/LIMIT_RECOVER_100P.md`. Written 2026-09-09 from live measurement on
kitty **0.48.2** (`kitty --version` → `kitty 0.48.2 created by Kovid Goyal`), socket
`unix:/tmp/kitty-1427`, macOS Darwin 24.6.0. Every claim is labelled **MEASURED** (a probe in
§Measurements, or a read of live `ps`/`kitty @ ls`) or **INFERRED** (reasoned from source + a
measured adjacent fact).

---

## Verdict

**Do not invent a spawn shape. Adopt the one `handoff-fire.sh` already ships and `lr-handoff.sh`
never got: `hf_argv_launch()`'s pre-delivered-command transport through `bin/cc-pane-runner`**
(`scripts/handoff-fire.sh:1003-1018`, `bin/it2-kitty:975-981`). It is the only shape measured that
satisfies all four requirements at once — argv delivery (no typing race), a surviving login+interactive
shell, an operator-visible failure, and an affirmative `pane_shell_root=yes`.

Five findings, in descending order of how much they change the plan:

1. **MEASURED — the runner shape is a complete answer, end to end.** Probe A(ii) ran the REAL
   `bin/cc-pane-runner` with a launcher that refuses like `lr-fire-resume` does (exit 9). The window
   stayed **ALIVE**, the refusal text stayed **on screen**, and the gates read
   `pane_shell_root=yes · pane_cc_state=shell` — i.e. immediately re-runnable *and* recyclable. The
   same launcher under today's `-- /bin/bash <launcher>` argv (Probe A(i)) left `kitty @ launch`
   returning **rc 0 and a window id** while the window was **GONE** and the error unreadable.
2. **MEASURED — `pane_shell_root` has a reachable FALSE YES on kitty/macOS, and it is the exact
   class the gate was written to close.** kitty wraps any *shell* argv in `/usr/bin/login`, and
   `login` is in the gate's allowlist (`scripts/handoff-fire.sh:3151`). Probe 5 launched
   `-- /bin/zsh -l -i -c 'exec sleep 6'`: the gate answered **`yes`**, and the window **vanished**
   when the exec'd child exited. Any future "fix" that spells the launcher as a shell argv passes the
   survivability gate and still strands.
3. **MEASURED — `--cwd=current` / `--title=current` resolve against the operator's ACTIVE window,
   not the source.** Probe 4-B (the exact flag set at `scripts/limit-recover/lr-handoff.sh:479-481`)
   produced a pane carrying window **646's** cwd *and* window 646's title — an unrelated live
   session. `bin/it2-kitty:935` already carries the third pin (`--source-window`) and documents this
   as the 2026-08-07 pane-theft incident; `lr-handoff.sh` and `bin/kitty-split-launch.sh:146` do not.
4. **MEASURED — `--title` is STICKY.** Probe 7: with `--title`, the child's OSC-0 is ignored; without
   it, the child renames the window. So **never pass `--title` to a recovered claude pane** — it
   would freeze the title and destroy the `✳/◐/◑` liveness glyph the operator reads. Provenance goes
   in `--var` (machine-readable, `kitty @ ls`-visible, invisible to the eye).
5. **MEASURED — `kitty @ close-window` reaps the whole process group.** Probe 9: all three pids gone
   after the close. Ordering in the replace-in-place path is therefore a *data-safety* rule, not
   tidiness.

**The same defect exists in three more places than the plan names**, all one cause (`exec expect`
as the pane's root): `lr-handoff.sh:479` (kitty vsplit), `:551` (kitty os-window), `:531`/`:578`
(both iTerm2 arms type `exec /bin/bash $LAUNCHER`), and `lr-reset-poller.sh:470` (kitty) / `:511`
(tmux). MEASURED: **all seven live `lr-resume-*` tmux panes read `pane_shell_root=no`** — the tmux
fleet is exactly as un-recyclable as panes 625/632.

---

## Measurements

All probes ran in throwaway kitty OS-windows titled `lr100p-probe`, created and closed by this
research. Gate functions were `sed`-extracted from `scripts/handoff-fire.sh` and evaluated in a
plain `bash` — nothing in `handoff-fire.sh` was executed.

### P1 — does kitty close a window when its launched process exits? And `--hold`?

```
kitty @ --to unix:/tmp/kitty-1427 launch --type=os-window --title lr100p-probe -- /bin/bash -c 'sleep 2'
```
| t | observation |
|---|---|
| 1 s | `FOUND id=650 cmdline=['sleep','2'] fg=[{'cmdline':['sleep','2'],'pid':22209}]` |
| 4 s | `WINDOW GONE (closed on process exit)` |

**MEASURED: yes, unconditionally.** Note `cmdline` is the *live* argv — `bash -c` exec'd into
`sleep`, and `kitty @ ls` reports the exec'd form. (This is why panes 625/632/167 report
`expect -c …`: their `/bin/bash <launcher>` exec'd into expect.)

With `--hold` (`-- /bin/bash -c 'sleep 1; echo EXITED_NOW'`):

```
window pid    = 83947   (BEFORE)  cmdline = ['/Applications/kitty.app/Contents/MacOS/kitten',
   'run-shell','--shell=/bin/zsh','--shell-integration=enabled','--env=KITTY_HOLD=1',
   '/bin/bash','-c','echo IAM_BASH $$; sleep 3']
window pid    = 83947   (AFTER)   cmdline = ['-zsh']
```

**MEASURED: `--hold` is not a frozen window — it is `kitten run-shell`, which `exec`s a
login+interactive shell IN PLACE (same pid) when the command exits.** `send-text` into it ran
`echo TYPED_INTO_HOLD` and printed `TYPED_INTO_HOLD` at a p10k prompt. Matches kitty's own help:
*"Keep the window open even after the command being executed exits, at a shell prompt. The shell
will be run after the launched command exits."*

**But `--hold` is invisible to the survivability gate.** While the command runs, the tty's root is
the `kitten` process (`comm=kitten`), which is not in `pane_shell_root`'s allowlist
(`scripts/handoff-fire.sh:3151`) ⇒ the gate answers **`no`** and `--recycle` REFUSES a pane that
would in fact have survived. **INFERRED** from the measured root argv + the allowlist; not separately
probed, because the design does not adopt `--hold` (see §Spawn design).

### P2 / live census — what the three real root shapes are, and what the gates say

`kitty @ ls` over the live fleet (35 windows at the time, 34 of them the operator's) shows exactly
three shapes. Measured `pane_shell_root` / `pane_cc_state` on one of each:

| pane | launched root argv (`ps -o command=`) | `pane_shell_root` | `pane_cc_state` | tty census |
|---|---|---|---|---|
| **634** (handoff-fire standard, 20 of 34 windows) | `/usr/bin/login -f -l -p chrisren …kitten run-shell --shell /bin/zsh -l -i -c 'exec "$CC_PANE_RUNNER"'` | **yes** | **cc** | login → `bash cc-pane-runner` → zsh → `bash cc-close-attrib` → {tee, claude→node, caffeinate} |
| **616** (operator pane, claude typed) | `/bin/zsh -l` | **yes** | **cc** | zsh → bash → {tee, claude→node} |
| **625 / 167** (lr-handoff fired) | `expect -c \012 set timeout 300 …` | **no** | **cc** | `expect` ALONE — claude is on a nested pty |

**MEASURED, and it settles question (d) both ways:** `pane_cc_state` correctly answers `cc` for pane
625 even though `ps -t <pane tty>` shows only `expect`, because its leg-(a) closure walks `ppid` over
`ps -axo` (`handoff-fire.sh:3072-3080`) and so crosses expect's nested pty. `pane_shell_root`
correctly answers `no` for the same pane, because it tests the **ROOT** only.

Two windows (`647`, `648`) are `tmux attach -t lr-resume-*` — someone has surfaced two of the seven
orphan tmux sessions into kitty.

### P3 — `--next-to` placement, and does the successor take the source's position?

Two-window case: `launch --type=window --location=vsplit --match window_id:654 --next-to id:654`
→ new id `656`, same tab 96, `654=77 cols · 656=77 cols` (was `654=156`). After
`close-window --match id:654`: `tab 96 layout=splits windows=[656]`, **`656 = 156 cols`** — the
successor absorbs the source's space exactly.

Three-window case (P8, replacing the **middle** window):

```
before:            tab 103 splits -> [(664,77),(665,38),(666,38)]      # 665 = the source
after spawn 667:   tab 103 splits -> [(664,77),(665,18),(666,38),(667,18)]
after close 665:   tab 103 splits -> [(664,77),(666,38),(667,38)]
```

**MEASURED: geometry is restored exactly** — 667 ends at 38 columns, the source's width, and the tab
is byte-for-byte the shape it had. ⚠ The `windows` array order is **creation order, not visual
order** (667 lists after 666), so a verifier must compare `columns`/position, never array index.

**MEASURED: every live tab uses the `splits` layout** (histogram over the whole fleet:
`{'splits': 10}`, 7 of them multi-window). The "layout where vsplit is not next to it" case does not
exist on this box today — but see §Replace-in-place for the rule that keeps it from mattering.

### P4 — `--env`, `--cwd=current`, `--title=current`, `--var` with `--next-to` (the exact lr-handoff form)

Source window **A** created with `--cwd /usr/share/dict --title lr100p-probe-SOURCE`. The operator's
**active** window at that instant was **646** (`cwd=/Users/chrisren/Development/claude-infrastructure`,
title `◐ Session close behavior and pane state`).

| launch | result |
|---|---|
| **B** — `--match window_id:A --next-to id:A --cwd=current --title=current --env LR_PROBE_ENV=hello --var lr_probe=yes` (no `--source-window`) | `cwd=/Users/chrisren/Development/claude-infrastructure` · `title='◐ Session close behavior and pane state'` · `user_vars={'lr_probe':'yes'}` · `env LR_PROBE_ENV=hello` |
| **C** — the same **plus `--source-window "id:A"`** | `cwd=/usr/share/dict` · `title='lr100p-probe-SOURCE'` · `user_vars={'lr_probe':'c'}` · `env LR_PROBE_ENV=hello2` |

**MEASURED.** `--env` and `--var` work with `--next-to`; `--cwd=current` and `--title=current` are
defined against `--source-window`, and `kitty @ launch --help` says *"When not specified the
currently active window is used."* B did not merely inherit a stranger's cwd — **it inherited a live
unrelated session's TITLE**, which is the provenance failure the plan's question 5 is about, produced
by the flag set that is in the tree today (`lr-handoff.sh:479-481`).

This independently reproduces the 2026-08-07 pane-theft incident already recorded at
`bin/it2-kitty:924-934`. `--dont-take-focus` held focus on 646 throughout.

### P5 — the FALSE YES in `pane_shell_root`

```
kitty @ launch --type=os-window --title lr100p-probe -- /bin/zsh -l -i -c 'exec sleep 6'
```
```
root argv: /usr/bin/login -f -l -p chrisren …kitten run-shell --shell /bin/zsh -l -i -c 'exec sleep 6'
tty census:  71679 1427 ttys057 Ss+ /usr/bin/login
             71725 71679 ttys057 S+  sleep
pane_shell_root=yes   pane_cc_state=unknown
… 6 s later:  WINDOW GONE
```

**MEASURED: the gate said `yes` and the pane did not survive.** Cause: on macOS kitty wraps every
*shell* argv in `/usr/bin/login`, and `login` is in the allowlist at
`scripts/handoff-fire.sh:3151`. `login` is not a shell that survives its children — it forks, waits,
and exits with the child. The gate's own header (`:3115-3135`) states the rule it is enforcing —
*"A SHELL there survives its children; anything else … is the session's own wrapper and dies with
it"* — and `login` violates it while satisfying the test.

Secondary, MEASURED: the operator's interactive zsh rc leaves **detached `-zsh` processes (ppid 1) on
the pane's tty** (powerlevel10k/gitstatus — e.g. `3492 1 /bin/zsh`, `3495 1 /bin/zsh` in Probe A(ii)'s
census). Those are ROOTS by `pane_shell_root`'s definition and are shells, so they can hold the
verdict at `yes` independently of the real root. Both paths lead to the same conclusion: **the gate's
`yes` is not evidence of survival.** Its `no` remains sound (affirmative-only refusal).

### P7 — `--title` stickiness

Child = `/bin/bash -c 'printf "\033]0;CHILD-SET-TITLE\007"; sleep 8'` (non-interactive, so no shell
integration to confound it):

| launch | title after the child's OSC-0 |
|---|---|
| `--title lr100p-probe-FROZEN` | `'lr100p-probe-FROZEN'` — child ignored |
| no `--title` (control) | `'CHILD-SET-TITLE'` — child wins |
| then `kitty @ set-window-title --match id:X 'lr100p-probe-RENAMED'` | `'lr100p-probe-RENAMED'` — remote control still overrides |

**MEASURED: `--title` is sticky against the child; `set-window-title` is not blocked by it.**

### P9 — does `close-window` kill the pane's processes?

Child `/bin/bash -c 'sleep 120 & echo CHILD=$!; sleep 120'`; census before the close showed
`41599 bash`, `41610 sleep`, `41611 sleep`. After `close-window --match id:668`: **no survivors.**
**MEASURED: `close-window` reaps the whole process group.**

### PA — where a refusal becomes visible (the (a)(ii) question)

Fake launcher reproducing `lr-fire-resume`'s capacity path (`scripts/limit-recover/lr-fire-resume.sh:319-323`
writes to stderr then `exit 9`; the tombstone path at `:207/:258` does the same with `exit 3`):

```
#!/bin/bash
echo "✗ capacity-admit REFUSED: load 16.1/core > 2.0 — resume 52e35019 on next3" >&2
exit 9
```

| arm | launch | outcome |
|---|---|---|
| **A(i) argv-rooted** — today's `lr-handoff.sh:479/551` | `launch --type=os-window -- /bin/bash <launcher>` | `kitty @ launch` returned **rc 0 and id 669** — a "successful fire". 3 s later: window **GONE**; `get-text` → `Error: No matching windows for expression: id:669`. **The refusal text was destroyed with the window.** |
| **A(ii) runner-rooted** — the proposal | `launch --type=os-window --env "CC_PANE_CMD=bash <launcher>" --env CC_PANE_CMD_INTERACTIVE=1 --env "CC_PANE_RUNNER=$HOME/Development/claude-infrastructure/bin/cc-pane-runner" -- /bin/zsh -l -i -c 'exec "$CC_PANE_RUNNER"'` | window **ALIVE**. Screen: the echoed command line, then `✗ capacity-admit REFUSED: load 16.1/core > 2.0 …`, then a prompt. Census: `login → /bin/zsh`. **`pane_shell_root=yes · pane_cc_state=shell`.** |

**MEASURED, using the real `bin/cc-pane-runner`.** A(i) is the shape commit `40c7e5cfd`
("a kitty window is not a resume") added `lrh_kitty_window_alive` to *detect*; A(ii) is the shape
that makes the failure **unnecessary to detect**, because it never destroys the evidence.

### Live tmux shape (read-only, no probe window)

Seven `lr-resume-*` sessions; `tmux list-panes -a`:

```
lr-resume-0edc7e64 tty=/dev/ttys042 pid=75824 cmd=expect   pane_shell_root=no  pane_cc_state=cc
lr-resume-1bd8904c tty=/dev/ttys026 pid=51990 cmd=expect   pane_shell_root=no  pane_cc_state=cc
lr-resume-3c4bdc06 tty=/dev/ttys032 pid=52298 cmd=expect   pane_shell_root=no  pane_cc_state=cc
lr-resume-52e35019 tty=/dev/ttys043 pid=76500 cmd=expect   pane_shell_root=no  pane_cc_state=cc
lr-resume-609597db tty=/dev/ttys008 pid=65575 cmd=expect   pane_shell_root=no  pane_cc_state=cc
lr-resume-9e3074fc tty=/dev/ttys018 pid=65933 cmd=expect   pane_shell_root=no  pane_cc_state=cc
lr-resume-0edc7e64/52e35019 …  (control) `dev` session: /bin/zsh → pane_shell_root=yes cc_state=shell
```

**MEASURED.** Each pane's root is `expect` with ppid = the tmux server (65481), i.e. a root by
`pane_shell_root`'s definition. Claude is on a nested pty and is still found by `pane_cc_state`'s
closure. **All six lr-resume panes are un-recyclable for the identical reason as panes 625/632.**

---

## Spawn design

### (a) The answer: neither of the two options in the brief — use the third, which already exists

| option | argv delivery | pane survives `/exit` | refusal visible | `pane_shell_root` | verdict |
|---|---|---|---|---|---|
| `-- /bin/bash <launcher>` (today, `lr-handoff.sh:479,551`) | ✔ | ✘ (P1, PA(i)) | ✘ **destroyed** (PA(i)) | `no` (measured, pane 625) | **reject** |
| `-- /bin/zsh -l` + TYPED `bash <launcher>` | ✘ — reintroduces the prompt race `cc-pane-runner:12-26` and `handoff-fire.sh:969-976` exist to remove | ✔ | ✔ | `yes` (P2, pane 616) | **reject — regresses a solved problem** |
| `-- /bin/bash <launcher>` **+ `--hold`** | ✔ | ✔ (P1) | ✔ | **`no`** — root is `kitten` (INFERRED from P1c's argv + the `:3151` allowlist) ⇒ recycle refuses | **reject unless the gate is also taught `kitten`** |
| **`--env CC_PANE_CMD=… --env CC_PANE_CMD_INTERACTIVE=1 --env CC_PANE_RUNNER=… -- "$SHELL" -l -i -c 'exec "$CC_PANE_RUNNER"'`** | ✔ | ✔ | ✔ | `yes` | **ADOPT** — all four, MEASURED in PA(ii) |

The exact form, copied from `scripts/handoff-fire.sh:1016-1017` / `bin/it2-kitty:975-981`:

```sh
CMD="bash $LAUNCHER"                  # NOT `exec bash …` — the exec is what kills the pane
kitty @ launch --type=window --location=vsplit \
  --match "window_id:$P" --next-to "id:$P" --source-window "id:$P" \
  --cwd=current --dont-take-focus \
  --var "lr_continuation_of=$SID" --var "lr_source_pane=$P" --var "lr_target_account=$ACCT" \
  --env "CC_PANE_CMD=$CMD" --env "CC_PANE_CMD_INTERACTIVE=1" --env "CC_PANE_RUNNER=$CC_RUNNER_BIN" \
  -- "${SHELL:-/bin/zsh}" -l -i -c 'exec "$CC_PANE_RUNNER"'
```

Why each piece, all load-bearing:

- **`-l -i`** — `~/.zprofile` puts `~/.claude/shims` on PATH and `~/.zshrc` synthesises
  `ITERM_SESSION_ID="w0t0p0:$KITTY_WINDOW_ID"`, the identity every hook, `cc-notify` address and
  registry row is keyed on (`bin/cc-pane-runner:37-46`). Without `-i` the relaunch verb a later
  recycle types (`claude4`, `nocorrect claude4 …`) is a zsh **function** that does not resolve
  (`bin/reso-resume-one:530-534`).
- **`CC_PANE_CMD_INTERACTIVE=1`** — the runner then runs the command under `$SHELL -l -i -c`
  (`bin/cc-pane-runner:196`) rather than bash `eval`, which is what makes launcher functions
  resolvable at all (`handoff-fire.sh:983-990`).
- **`bash $LAUNCHER`, never `exec bash $LAUNCHER`.** MEASURED-adjacent/INFERRED: `$LAUNCHER`'s own
  last line is `exec lr-fire-resume …` (`lr-handoff.sh:390`), which itself `exec expect`s. Run
  non-exec, that whole chain replaces the *child* bash and returns to the runner when claude exits;
  run with `exec`, it replaces the pane's own shell and the pane dies. This is precisely the
  distinction `lr-handoff.sh:588` already documents in its printed fallback.
- **`--source-window "id:$P"`** — without it, `--cwd=current` silently takes the operator's active
  window (P4, MEASURED). Add it to `lr-handoff.sh:479-481` and `bin/kitty-split-launch.sh:146`
  regardless of the rest of this design; `bin/it2-kitty:935` is the reference implementation.
- **No `--title`** — it is sticky (P7) and would freeze the recovered pane's title forever, killing
  the `✳/◐/◑` glyph. Provenance rides in **`--var`**, which `kitty @ ls` exposes as `user_vars`
  (P4, MEASURED) and no child process can forge.
- **`--dont-take-focus`** — MEASURED in P4 to hold focus. Take focus only when the SOURCE pane was
  the focused one, so a fleet recovery of six panes does not steal the operator's cursor six times.

### (a)(i)/(a)(ii) — the two outcomes, stated

| | resume ENGAGES | `lr-fire-resume` REFUSES (capacity exit 9 · tombstone exit 3) |
|---|---|---|
| argv-rooted (today) | works; pane is a **dead end** — the next recycle is refused by the survivability gate (`handoff-fire.sh:10278-10287`), and a fleet recovery is a one-shot | **window destroyed, message destroyed** (PA(i)). `kitty @ launch` still exits 0. `lrh_kitty_window_alive` (commit `40c7e5cfd`) now catches the *fact*, never the *reason* — and it can only see it if it polls before macOS tears the window down |
| runner-rooted (proposed) | works; pane is **recyclable next time** — `pane_shell_root=yes` over a root that genuinely survives, because the runner ends in `exec "$SHELL" -l -i` (`bin/cc-pane-runner:145-148, 200`) | **window alive, refusal on screen, prompt underneath** (PA(ii)). The operator (or the actuator, via `kitty @ get-text`) reads the reason and re-runs one line. No husk: the pane is a shell that never held a session |

### The gate has to be fixed too, or the class stays open

`pane_shell_root`'s `yes` is not evidence (P5). Two changes, both narrow, both preserving the
affirmative-refusal polarity (`handoff-fire.sh:3128-3135`):

1. **`login` must not clear the gate on its own.** When the *only* shell-ish root is
   `/usr/bin/login`, descend one generation: the verdict is the comm of `login`'s child on the same
   tty. That child is `bash cc-pane-runner` (pane 634, MEASURED) or `zsh` (P2) for a survivable pane,
   and `sleep`/`expect`/a bare binary for one that is not (P5). This is still a ROOT test — it just
   sees through kitty's macOS wrapper, which is not a process the pane's design chose.
2. **Ignore `ppid == 1` shells that are not the launched pid.** They are p10k/gitstatus detritus
   (P5 secondary, MEASURED) and can hold the verdict at `yes` over a dead root.

Neither can turn a working recycle into a refusal on the shapes measured here: pane 634 and pane 616
both still answer `yes` (their `login`-child is `bash cc-pane-runner` / their root is a real `zsh`).

---

## Replace-in-place path (for panes whose root is already a launcher)

This is the migration path for panes 625/632/167 and the six tmux sessions — panes that exist today
and cannot be recycled. **INFERRED design, built on the P3/P4/P7/P9 measurements.**

```
0. PRECONDITION — the source is PROVABLY retired, not merely quiet:
   registry row ~/.claude/cc-registry/<P>.json carries session_id == S
   AND the tombstone <src-cfg>/<S>.HANDOFF.json exists (or handed-off-session-guard is already
   blocking S's prompts). Nothing below runs on a live, un-transplanted session.

1. READ the source's identity BEFORE touching anything:
     kitty @ ls  →  P's tab id, its columns, its user_vars, whether it is_focused
     ps -o tty=  →  P's tty, for the pane_cc_state / pane_shell_root reads

2. SPAWN the successor beside it, same tab, geometry-neutral:
     kitty @ launch --type=window --location=vsplit \
       --match "window_id:$P" --next-to "id:$P" --source-window "id:$P" \
       --cwd=current $( [ "$P_was_focused" = 1 ] || printf %s --dont-take-focus ) \
       --var "lr_continuation_of=$S" --var "lr_source_pane=$P" \
       --env CC_PANE_CMD="bash $LAUNCHER" --env CC_PANE_CMD_INTERACTIVE=1 \
       --env CC_PANE_RUNNER="$CC_RUNNER_BIN" \
       -- "${SHELL:-/bin/zsh}" -l -i -c 'exec "$CC_PANE_RUNNER"'
   → capture the printed id N; reject anything that is not a bare integer (lr-handoff.sh:485-489)

3. VERIFY ENGAGEMENT of N — never window-existence. Reuse recycle_engaged()'s discriminator
   (handoff-fire.sh:3196+): the registry row for N names a session_id whose transcript shows an
   ASSISTANT turn, or the marker embedded in the prompt copy appears in a transcript with one.
   Window-alive is the check that was already proven insufficient (commit 40c7e5cfd).

4. ONLY THEN close the source:   kitty @ close-window --match "id:$P"
   MEASURED (P9): this SIGHUPs the whole group. That is safe here and only here, because step 0
   proved S is retired and step 3 proved the continuation is live somewhere else.

5. ON NON-ENGAGEMENT: do NOT close P. Report the pair (P alive, N showing its refusal on screen —
   which is readable precisely because N is runner-rooted). The operator ends with one husk and one
   diagnosis, never two mysteries.
```

**Geometry.** MEASURED (P3, P8): the successor absorbs the source's exact width when the source
closes, in both the 2-window and middle-of-3 cases; the tab returns to its prior shape. Verify by
`columns`/position, not by array index (the array is creation-ordered).

**When `--location=vsplit` is not available.** All 10 live tabs are `splits` (P3, MEASURED), so this
is a future case, not a present one. The rule that makes it a non-event: **`--next-to` is a
preference, `--match window_id:$P` is the requirement.** kitty's `launch.py` drops `--next-to` when
the target tab does not contain the anchor, and `--match` (which matches the **TAB** — `kitty @ launch
--help`) is what keeps the successor in the *right tab* regardless. In a `stack` layout the successor
lands in the same tab, stacked; step 4 then leaves exactly one window where there was one. Never fall
back to `--type=os-window` for a source that has a tab — that is how a recovery starts creating the
detached windows this plan exists to eliminate.

**Title.** Do **not** carry it with `--title` (P7: sticky, kills the liveness glyph) and do **not**
carry it with `--title=current` without `--source-window` (P4: steals a stranger's title). Carry
provenance in `--var`; let claude own the title, exactly as it does in the 20 windows that already
work. If a frozen human label is ever wanted, `kitty @ set-window-title` applies it *after*
engagement and can be re-applied — MEASURED in P7 to override even a sticky `--title`.

**tmux.** The same shape, one flag different: the launcher must not be the pane's argv. Either
`tmux new-session -d -s <n>` (default shell) then a verified `send-keys` of `bash $LAUNCHER`, or
`tmux set-option -t <n> remain-on-exit on` — tmux's `--hold` analogue. INFERRED; the six live
`lr-resume-*` panes measured `pane_shell_root=no` for the identical `exec expect` reason, so the
identical fix applies at `lr-reset-poller.sh:511`.

---

## Bare-shell rule

**A bare shell prompt is the honest normal state of an operator pane. It is only a husk when a
session died in it and left work.** That distinction is already implemented, and the answer to
question (b) is: adopt the existing classifier's model rather than invent a "husk" predicate.

`bin/cc-husk-sweep` (the 2026-09-04 incident tool) is the detector of record. Its model, read from
source:

- **Population**: every enumerated pane with no claude anywhere under its launched pid
  (`has_claude_under`, `cc-husk-sweep:65`). A plain operator shell is in this population.
- **Resolution**: registry row → scrollback → transcript. A pane that resolves to **no session** is
  emitted as `UNKNOWN / unresolved` and — critically — **is skipped by `--resume`** (`:196`,
  `[ "$sid" != "-" ] || continue`). So an ordinary shell is *listed* and never *acted on*.
- **Verdict**: `RESUME` when the session's last close said "Good to close: no" or its cwd holds
  uncommitted/unlanded work; `DONE` when clean and landed; `UNKNOWN` otherwise, and UNKNOWN is
  resumed (`lookup-miss-is-not-absence`).

The rails should enforce exactly three post-session end-states, and nothing else:

| how the session ended | what the pane becomes | who enforces it |
|---|---|---|
| **recycle** (`--recycle`) | same pane, relaunched — never idles at a prompt | the `__recycle` watcher types the relaunch (`handoff-fire.sh:5820+`) and `recycle_engaged` proves it |
| **self-close** (a fired peer retiring) | the **window closes** | `self-close`; the pane is not left behind at all |
| **crash / limit / operator `/exit`** | a bare shell **with a resolvable session**, i.e. a real husk | `cc-husk-sweep --resume` types the pinned launcher; `hooks/lead-crash-watchdog.sh` is the other arm |
| operator opened a shell and never launched | a bare shell with **no** session | nothing — this is not a husk and must never be swept |

**Consequence for this plan:** the runner-rooted spawn *cannot* create a new husk class. Its two
terminal states are (1) claude running, or (2) a shell showing why the launcher refused, with no
registry row and no session — i.e. `cc-husk-sweep`'s `unresolved` row, which is inert. Contrast the
argv-rooted shape, whose failure state is a **vanished window**: invisible to `cc-husk-sweep`
(nothing to enumerate), invisible to `pane_cc_state` (no tty), and the origin of the "which pane is
which" ambiguity the plan's §1 records.

One gap worth naming: `cc-husk-sweep` is **manual** (`--resume` behind a typed-yes gate) and is not
wired into `lr-reset-poller`. A fleet recovery that ends with husks it did not create should
*report* them via `cc-husk-sweep --json`, not re-implement the classification.

---

## Tests to red-proof

Each must fail on the pre-fix tree and pass after. Fixture shapes are given because
`pane_shell_root`/`pane_cc_state` are `sed`-extracted as isolated units by the existing suites
(`tests/handoff-recycle-expect-probe.bats:113`), so a `ps` fixture is the whole harness.

1. **`pane_shell_root` false-yes** — fixture: a tty whose only root is `/usr/bin/login` and whose
   `login`-child is `sleep` (P5's exact census). Pre-fix: `yes`. Post-fix: `no`.
   **Control that must stay green:** the same fixture with the child `bash cc-pane-runner` (pane 634's
   census) → `yes`; and a bare `/bin/zsh` root (pane 616) → `yes`. Without both controls the fix is
   indistinguishable from deleting `login` from the allowlist, which would refuse every working pane.
2. **`pane_shell_root` ignores ppid-1 shell detritus** — fixture: root `expect` (ppid = kitty) plus a
   detached `-zsh` at ppid 1 on the same tty. Pre-fix: `yes` (the detritus carries it). Post-fix: `no`.
3. **The recovered spawn is runner-rooted** — assert the composed argv contains
   `CC_PANE_CMD=`, `CC_PANE_CMD_INTERACTIVE=1`, `-- <shell> -l -i -c exec "$CC_PANE_RUNNER"`, and
   **does not** contain `-- /bin/bash $LAUNCHER`. Assert the delivered command is `bash $LAUNCHER`
   and **not** `exec bash $LAUNCHER`. ⚠ A grep for `cc-pane-runner` alone is vacuous — the string
   appears in comments; key on the `--env CC_PANE_CMD=` pairing.
4. **`--source-window` is present on every kitty launch that uses `current`** — a repo-wide lint, in
   the family of `scripts/pane-spawn-coverage-lint.sh`: any `launch` argv containing `--cwd=current`
   or `--title=current` must also contain `--source-window`. Pre-fix: `lr-handoff.sh:479` fails.
   This is the one that stops the class rather than the instance.
5. **No `--title` on a recovered claude pane** — assert the composed argv has no `--title`, and that
   provenance is carried by `--var lr_continuation_of=`.
6. **Ordering: engagement before close** — with a stubbed `kitty @`, assert `close-window` is
   never issued when the engagement probe returns "not engaged", and that when it is issued its
   `--match id:` names the SOURCE, never the successor. Pair with the P9 fact in the comment so the
   next reader knows the close is a kill.
7. **Refusal is visible** — a launcher stub that exits 9 with a message; assert the window is still
   enumerable afterwards and `get-text` contains the message. This is PA promoted to a test, and it
   is what makes `lrh_kitty_window_alive` stop being the only line of defence.
8. **tmux parity** — the poller's tmux spawn must not put the launcher in the pane's argv. Assert the
   `new-session` argv is the default shell (or that `remain-on-exit on` is set), and that a
   subsequent `send-keys` carries `bash <launcher>` without `exec`.

---

## Open risks

- **`login`-descent (fix 1) is one generation deep by design.** A launcher spelled
  `zsh -l -i -c 'exec bash -c "exec expect …"'` would put `bash` in the child slot and pass. The
  honest bound: the fix closes the shapes that exist (P5, pane 634, pane 616) and narrows, but does
  not eliminate, the class. The lint (test 4) and the argv assertion (test 3) are what actually keep
  new launcher shapes out; the gate is the backstop, not the guard.
- **`--hold` was not adopted and is not fully characterised.** Its `pane_shell_root=no` is INFERRED
  from the measured `kitten` root argv, not separately probed. If a future caller cannot use the
  runner (no `CC_PANE_RUNNER` on disk — `handoff-fire.sh:1007` degrades to typing in that case),
  `--hold` is the correct second choice, and it needs `kitten` added to the allowlist first.
- **kitty's `login` wrapping is version- and platform-specific.** Measured on kitty 0.48.2 / macOS.
  A kitty bump can change whether the wrapper appears at all, which flips both the false-yes and the
  fix. Test 1's controls are what will catch that; do not encode "the root is `login`" anywhere as a
  fact about the world.
- **Focus policy is asserted, not measured against operator preference.** `--dont-take-focus` works
  (P4, MEASURED); whether a fleet recovery *should* focus the last successor is a judgment this
  research did not settle.
- **The auto-mode classifier may deny `close-window` from an agent's Bash tool.** Context §
  auto-mode records the boundary as "the TARGET is a live Claude session", and that `kitten @
  close-window` on husks 627/628 ran unprompted. Step 4 closes only a pane whose session is
  provably retired, which should sit on the permitted side — but this was **not** probed (doing so
  would require closing a real pane) and is the one step of the path that could be refused at
  runtime. The launchd poller has no classifier, so the actuator's daemon path is unaffected.
- **The registry↔pane binding for tmux panes has no kitty window id.** The replace-in-place path as
  written is kitty-only; the six live `lr-resume-*` sessions need the tmux variant, which is
  INFERRED here and unprobed.
- **Nothing here addresses whether a limit-blocked TUI accepts `/exit`** (plan question 1). The
  spawn shape decides whether a recycle *can* land; it says nothing about whether the source pane
  will reach a shell. Those are independent, and both must hold.

---

## Probe-window cleanup — confirmed

Every kitty window created by this research (ids 650, 651, 652, 654, 655, 656, 657, 658, 659, 660,
661, 664, 665, 666, 667, 668, 669, 670) is closed. Verified after the sweep:

```
lr100p-probe windows remaining: 0
probe ids still live: NONE
total windows now: 33
```

33 = the operator's own fleet, unchanged (the pre-probe inventory listed 34 windows, of which one —
id 654 — was mine). ⚠ One probe window (658) had **stolen window 646's title** via the P4 defect, so
it could not have been matched by `--match title:lr100p-probe`; all closes were issued by explicit
id. No operator pane, tmux session, or process was typed into, signalled, or closed.
