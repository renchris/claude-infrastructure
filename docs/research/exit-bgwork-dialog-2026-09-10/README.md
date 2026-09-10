# The exit-time background-work dialog — the instrument, so the claim can be re-measured

`exit-dialog-probe.py` is what established that `/exit` does not exit when the harness is tracking
a `run_in_background` shell, and which menu key ends the session without stopping that work. It is
committed for the reason `../composer-scrub-2026-09-09/` is: a resident claim about a live binary
is a perishable fact, and the fix for that is not a better sentence but the command that re-derives
it.

    python3 -m venv .v && ./.v/bin/pip install pyte
    ./.v/bin/python exit-dialog-probe.py <claude-binary> "$HOME/.claude-tertiary" <a-TRUSTED-cwd> <arm>

`<arm>` is `control` (no background work), `none` (background work, answer nothing) or a menu
index. It spawns a real Claude Code under a PTY and renders the screen with `pyte`.

**Use a trusted cwd.** In an untrusted directory the workspace-trust dialog fires first and the run
reports `never reached an empty composer` — a NON-VERDICT that reads like a negative. Do not pass
`--permission-mode bypassPermissions` to get past a Bash prompt either: that mode raises its own
consent dialog, and scripting an answer to it is granting yourself unrestricted execution.

## Measured 2026-09-10, binary 2.1.260 (`~/.claude-260/.../bin/claude.exe`)

| arm | background work | key sent | dialog rendered | process exited |
|---|---|---|---|---|
| `control` | none | — | **no** | **yes** |
| `none` | `sleep 600` | — | **yes** | **no** |
| `2` | `sleep 600` | `2`, one byte, no CR | yes | **yes** |

The two negative readings are the point: an instrument that cannot report *no dialog* and *did not
exit* says nothing when it reports the opposite.

Rendered verbatim in the `none` arm:

```
   Background work is running
   The following will stop when you exit:

   shell · sleep 600

   ❯ 1. Exit and stop tasks
     2. Move to background and exit
     3. Stay

   Enter to confirm · Esc to cancel
```

Three facts the fix turns on:

1. **The default cursor sits on the destructive option.** A blind `Enter` stops the tasks — on this
   box usually a land in flight. That is why nothing about this path may submit a bare CR.
2. **A digit alone selects AND submits.** No `Enter` is needed, despite the footer.
3. **There is no composer box while the dialog is up**, which is why `composer_content` reads
   UNKNOWN, `recycle_nudge_decision` answers `unknown`, and every nudge checkpoint HOLDS. The
   watcher then dies at 600 s having typed nothing, and its terminal alarm asserts the predecessor
   is GONE — the one thing that is certainly false in this state.

## What is NOT established

* The dialog also fires for async agents and remote sessions (the binary's task vocabulary covers
  all three); only the **shell** arm was driven. Nothing in the fix depends on which kind it is —
  the matcher reads the header and the menu, not the task list.
* `2` is what this menu rendered on this date. The shipped code therefore **reads the index off the
  screen it is about to answer** (`pane_bgwork_choice`) rather than carrying the number; an
  unindexed or ambiguous menu refuses instead of guessing. `tests/handoff-recycle-bgwork-dialog.bats`
  drives a reordered menu as the mutant that proves the index is read and not assumed.
* Present in **2.1.220** (the binary the 2026-09-01 incident ran) and **2.1.260** by fixed-string
  grep, so this is not a version we grew into.
