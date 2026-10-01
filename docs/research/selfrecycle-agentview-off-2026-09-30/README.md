# A self-recycle's /exit, under agent-view-off: what the exit dialog counts

FLEET_V2 W7c. The W5b2 shadow session (pane 38, 2.1.284, `CLAUDE_CODE_DISABLE_AGENT_VIEW=1`) ran
`handoff-fire.sh --recycle` on itself twice on 2026-09-30. Both /exits raised "Background work is
running", whose agent-view-off menu is only `1. Exit and stop tasks · 2. Stay`. The watcher answered
Stay (recovery never chooses stop-tasks, operator decision 2), so nothing relaunched, and afterwards
TaskStop found no running task.

## The instrument

`selfrecycle-probe.py` spawns a throwaway Claude Code (haiku, hooks disabled, its own PTY and cwd)
and renders it with `pyte`. The in-flight call is `bash wait45.sh`, a 45 s foreground script standing
in for `bash handoff-fire.sh --recycle`, because 2.1.284's Bash tool refuses a bare `sleep`. The
probe finds the call by process tree under the claude pid, not by screen text, since 2.1.284
collapses a running call to `Running … script`.

    python3 -m venv .v && ./.v/bin/pip install pyte
    cp wait45.sh <cwd>/ && ./.v/bin/python selfrecycle-probe.py <claude-binary> <config-dir> <cwd> <arm> <off|on>

Arms: `control` (idle), `fgbash` (/exit typed 5 s into the call), `fgdone` (/exit after the call
returned and the turn ended), `bgbash` (a `run_in_background` shell). In `fgbash`, once the dialog is
up the probe does what the shipped watcher does: sends nothing until the call has ended, then Esc,
then /exit again.

## Measured 2026-09-30, 2.1.284

| arm | view | dialog at /exit | call alive under the dialog | dialog still up after the call ended | Esc, then /exit again | exited |
|---|---|---|---|---|---|---|
| control | off | no | — | — | — | yes |
| bgbash | off | **yes** (`shell · sleep 600`) | — | — | — | no |
| fgbash | off | **yes** (`shell · bash wait45.sh`) | yes (ended 36 s later) | **yes** | no dialog | **yes** |
| fgbash | on | **yes** (`shell · bash wait45.sh`) | yes (ended 34 s later) | **yes** | no dialog | **yes** |

The dialog rendered for the in-flight call, verbatim (agent view off):

```
   Background work is running
   The following will stop when you exit:

   shell · bash wait45.sh

   ❯ 1. Exit and stop tasks
     2. Stay
```

## What this establishes

1. **The dialog counts the recycle's own foreground Bash call.** An in-flight foreground call is a
   `shell` task, the same kind as a `run_in_background` one. No Monitor or background shell is
   needed. A self-recycle types /exit from inside that call, so every self-recycle raises the dialog.
2. **The call keeps running under the dialog and returns normally.** The model even finishes its
   turn behind it. The dialog does not close when the call ends. That fits pane 38's TaskStop
   finding nothing: by the time the session looked, the call it would have stopped had returned.
3. **Once the call has returned, Esc then /exit exits with no dialog**, in both view modes, even
   when the /exit lands while the model is still thinking (the `on` arm).

## Replicated independently, with the foreign-task case (`pane48/`)

A twin W7c session (pane 48, sid 28d7958b) ran its own instrument (`pane48/probe2.py`) on the same
binary the same evening. Its results agree on every row above, and add three facts
(`pane48/STEP0-EVIDENCE.md`, raw screens `pane48/p2-*.txt`):

* A call counts once it has run for more than about 1-2 s (0.3 s in: no dialog; 4 s in: dialog).
  The foreground types /exit about 10 s into its call, so a self-recycle always meets the dialog.
* **With a real `run_in_background` task beside the call, Esc and /exit after the call returns
  raise the dialog again, listing only that task** (`p2-latebg.txt`). This is the property the
  cure depends on to keep Stay for work the recycle did not start, and it holds on the real binary.
* An asyncRewake Stop hook (the inbox wake watcher) is not listed.

## What is NOT established

* The agent-view-ON self-recycle still takes the watcher's existing keep-work answer ("Move to
  background and exit"). The table shows it could use the same Esc-then-/exit cure. That is not W7c's
  scope and is left unchanged.
