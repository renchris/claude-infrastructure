# A session launched from a non-interactive shell cannot create a named teammate at all

**Measured 2026-09-19** by the W5 probe wave of `docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md`,
proven in both directions (`captures/env-control/RESULT.txt`: unset before, `w0t0p0:171` after).
Full record: `docs/research/subagent-lifecycle-2026-09-19/P-probes.md` § "Attempt 1".

## The mechanism

Claude Code gates its iTerm2 pane backend on **`ITERM_SESSION_ID`**. This fleet runs
`teammateMode: "iterm2"` under **kitty**, and bridges the two in `~/.zshrc`, which synthesises
`ITERM_SESSION_ID=w0t0p0:$KITTY_WINDOW_ID`.

**A non-interactive shell never runs that block.** So a lead launched by anything that does not
source `.zshrc` — a kitty-launched `/bin/bash`, a `launchd` job, a cron entry, a wrapper script —
comes up with `ITERM_SESSION_ID` unset and **cannot spawn a named teammate at all**. The probe's
lead said so itself: *"teammateMode is set to `iterm2` but this session is not running inside
iTerm2 … this session cannot create a named teammate at all."*

## Why it is worth its own lesson

**It is a REFUSAL, not a demotion, and that makes it a different failure class from the one the
register already documents.** RC-11's `isolation:`/`cwd:`-beside-`name:` trap *silently* demotes a
named spawn to a plain subagent — no pane, no member, no warning. This one refuses out loud. The two
look nothing alike in a transcript and want opposite responses: the silent one needs a spawn-time
advisory, this one needs the environment fixed before the session is launched.

## The rule

Any automation that launches a Claude session and expects it to spawn teammates must **reproduce the
`.zshrc` synthesis verbatim**, or verify `ITERM_SESSION_ID` is set before relying on a teammate
spawn. Do not reach for a `teammateMode` change — that is a global setting, and swapping it to work
around one launcher's environment breaks every session that was fine.

The same class reaches further than teammates: `memory:transplanted-session-loses-dispatch-identity`
records that a session with no `ITERM_SESSION_ID` also has no registry row, so every `handoff-fire`
aborts at its back-channel gate. One missing variable, two unrelated-looking failures.

## Companion, found by the same probe

**`send-text` with a bare LF does not submit a composer — it inserts a newline.** Only a carriage
return submits. The probe's `/exit` sat unsent in a lead's composer for minutes looking like a hung
session.
