# A lead with live teammates cannot exit unattended — `/exit` raises a modal

**Measured 2026-09-19 on Claude Code 2.1.260** (probe P1, wave W5 of
`docs/plans/SUBAGENT_LIFECYCLE_ROOT_CAUSE.md`; evidence in
`docs/research/subagent-lifecycle-2026-09-19/P-probes.md` and
`tests/fixtures/teammate-probe/captures/`).

## The rule

`/exit` on a lead that still has live named teammates **does not exit**. It raises a blocking
confirmation:

```
  Background work is running
  The following will stop when you exit:

  subagent · <each live teammate's brief, truncated>

  ❯ 1. Exit and stop tasks
    2. Move to background and exit
    3. Stay

  Enter to confirm · Esc to cancel
```

So the vendor's `cleanupSessionTeams` — the thing that closes every member pane on lead exit —
sits **behind an interactive confirmation** whenever members are alive. Nothing reaches it
unattended.

## Why it matters, and why it is easy to misread as a vendor bug

The probe's first reading at +30 s was `survivor_windows=5, survivor_procs=4` for a lead plus four
members. That looks exactly like "the vendor failed to clean up". **It is not.** Five windows for a
lead plus four members means the *lead's own window survived too* — and that is the tell: the lead
never exited, so the cleanup path was never entered. The number measured the probe's exit
mechanism, not the vendor's cleanup.

Once the modal was answered (option 1, "Exit and stop tasks" — the pre-selected default), both runs
came back **0 surviving windows and 0 surviving member processes at +30 s**, on a box at 0.0–1.6%
CPU idle with load 64→133. The cleanup works; *reaching* it is the problem.

**The general shape:** when a teardown path appears not to run, check whether the thing that
triggers it actually happened. A survivor count that includes the *trigger's own* artifact (here,
the lead's window) is evidence the trigger never fired, not that the teardown is broken.

## Consequences

- **Any automation that ends a lead non-interactively leaves everything alive** — a `claude -p`
  run, a cron or launchd job, a script sending `/exit` into a pane. Both the lead and its members
  persist indefinitely. This is the lead-side twin of
  [`a-subagent-cannot-answer-a-permission-prompt-so-a-prompt-trigger.md`](a-subagent-cannot-answer-a-permission-prompt-so-a-prompt-trigger.md):
  the member cannot answer a prompt, and neither can an unattended lead.
- **"The vendor cleans up on lead exit" is true only of ATTENDED exits on this build.** Any
  decision resting on that cleanup must say which kind of exit it assumes.
- **Sending `/exit` needs a carriage return, not a newline** — `kitten @ send-text` with a bare LF
  inserts a newline in the composer instead of submitting it. And if the lead is mid-turn, the text
  queues and fires at an arbitrary later point.

## The arm that was NOT run

Exit **option 2, "Move to background and exit"**, was never exercised. It is a different code path
and may well leave members alive. Do not quote P1's pass as covering it.
