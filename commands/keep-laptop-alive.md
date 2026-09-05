Toggle whether this Mac keeps running with the lid closed, so a long session is not
suspended mid-turn.

Run exactly this, with `$ARGUMENTS` passed through (empty = status):

```bash
cc-lid $ARGUMENTS
```

`cc-lid` accepts `on` · `off` · `toggle` · `status` (default). With no argument the
user almost always means **toggle** — if `$ARGUMENTS` is empty and the request was
phrased as an action ("keep it alive", "let me close the lid", "turn it back on"),
pass `toggle`; if it was phrased as a question ("is it on?"), pass nothing.

Then **relay `cc-lid`'s output verbatim** — it is a shipped renderer and its
`▶ Run this:` block is already in the operator's copy-paste form. Do not paraphrase
it, do not re-wrap the command, do not add a second command.

- **exit 0** — the setting is already where it should be, or the script applied and
  verified it. Report the one line it printed and stop.
- **exit 10** — root is required and this shell cannot elevate (`sudo` is denied to an
  agent by `hooks/validate-bash.sh`, so you never can). The block it printed IS the
  answer. Relay it as-is; never re-prompt the user for the command, and **never
  substitute a `sudo …` line of your own** — with no TTY `sudo` cannot prompt at all
  and dies on "a terminal is required to read the password", which is exactly what
  happened on 2026-09-03 when the operator pasted one into the `!` surface. `cc-lid`
  already picked the form that works where it ran; it printed `osascript … with
  administrator privileges` for a reason.
- **exit 3 / 4** — pmset was unreadable, or the change did not verify. Say which,
  and do not claim the state changed.

Background: `caffeinate` takes an idle-sleep assertion only. Clamshell sleep is a
separate path that ignores it, which is why nine live caffeinate assertions still
let the machine sleep on lid-close. `pmset -a disablesleep 1` is the only setting
that covers it, and it **persists across reboot** — so a session that turns it on
should say so, and `cc-lid off` is the revert.
