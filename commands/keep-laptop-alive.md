---
name: keep-laptop-alive
description: Toggle whether this Mac keeps running with the lid shut — disables sleep on lid close. Use for "keep the laptop alive", "let me close the lid", "stop it sleeping", lid sleep, clamshell sleep, caffeinate, or /keep-laptop-alive.
argument-hint: "[on|off|toggle|status]"
---

Toggle whether this Mac keeps running with the lid closed, so a long session is not
suspended mid-turn.

Run exactly this, with `$ARGUMENTS` passed through — and when `$ARGUMENTS` is empty,
pass `toggle`:

```bash
cc-lid $ARGUMENTS      # $ARGUMENTS empty ⇒ run: cc-lid toggle
```

`cc-lid` accepts `on` · `off` · `toggle` · `status`. **A bare `/keep-laptop-alive` is a
TOGGLE, always** — lid-close sleep enabled ⇒ disable it; disabled ⇒ enable it. The
empty-argument case has exactly one meaning, so do not read the operator's phrasing and
do not fall back to `status`; `status`, `on` and `off` happen only when they are typed.
*(Corrected 2026-09-13: the rule used to branch on action-vs-question wording, and a bare
re-invocation with no words at all fell through to `status` — the operator had to say
what a toggle is. A heuristic that cannot fire on the commonest input is not a heuristic.)*

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
