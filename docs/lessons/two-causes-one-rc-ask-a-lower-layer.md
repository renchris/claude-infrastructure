# Two causes, one rc — ask a lower layer

cc-backlog item `e9bea40e7af8`, closed 2026-09-20.

## The incident

`self-close --source-pane` refused to retire two husk panes (kitty windows 110 and 126) with:

> `REMOTE-PANE-RESOLVER-UNAVAILABLE — no terminal control socket answered at all`

Measured at the time of filing: kitty pid 73832 had been alive 3d8h, `allow_remote_control` was
socket-only, `/tmp/kitty-73832` was present **and accepting**, and load was 197 on 10 cores.
`kitty @ ls` was returning `read unix: i/o timeout`. So the sentence was false in the direction
that costs the most — it described a *world* ("there is no terminal here") when the fact was about
a *moment* ("the terminal was too busy to answer"). The operator's next action for those two states
is opposite: investigate the terminal, versus come back when the box is quieter.

Re-measured four days later on the same box at load 17, the same socket answered in **0.06 s**. The
cause was a load spike, and a spike is precisely the thing a retry beats.

## Why the resolver could not tell

`kitty_socket_answers` is a bounded `kitty @ --to <sock> ls`, and it collapses every failure into
one non-zero. That collapse is not sloppiness — it is forced, because **the client exits 1 for both
causes**. Measured on kitty 0.48.2, 2026-09-20:

| state | `kitty @ ls` says | rc |
|---|---|---|
| leftover socket file, kitty SIGKILLed | `connect: connection refused` | 1 |
| live kitty, saturated | `read unix …: i/o timeout` | 1 |

The *wording* separates them, and keying on it is the trap this repo has already been burned by
(memory: `error-wording-drifts-between-versions` — grepping version A's error string in version B
manufactures only false negatives). There is also no lever to wait longer: kitty 0.48.2's `kitty @`
exposes no `--response-timeout`, so the client gives up on its own schedule and widening the
`hf_bounded` window buys nothing. A retry does not buy a longer wait; it buys **a different moment**.

## The discriminator is one layer down

`connect(2)` answers the same question from the kernel and cannot drift:

| socket | connect(2) |
|---|---|
| live kitty | accepts |
| bound but never `listen()`ed (≡ a SIGKILLed kitty's leftover file) | `ECONNREFUSED` |
| absent path | `ENOENT` |

So `kitty_socket_accepting` probes the socket directly, and only on the failure path. A socket that
accepts but does not answer is a **live terminal**, and that is retryable; one that refuses is a
leftover, and retrying it can only waste time.

## The rule

**When two opposite causes produce the same exit code from a client, the client cannot be the
instrument. Its message text is a version-drifting string; go one layer down and ask the kernel —
or whatever layer both causes actually differ at — for a discriminator that cannot drift.**

Two corollaries the fix turns on:

- **A non-verdict that cannot be sub-classified will be read as a verdict.** rc 3 was already
  documented "park and retry, never conclude the pane is gone", and it still stranded two panes,
  because the *sentence* underneath it asserted absence. Splitting the sentence — not the return
  code — is what the callers and sibling suites could absorb.
- **"Retryable" is a claim you have to pay for.** Saying a state is retryable and then not retrying
  leaves the work exactly where it was. The retry is bounded (`CC_REMOTE_PANE_TERM_TRIES`, default
  3, with `=1` disabling it outright) and fires *only* on the accepting-but-silent sub-state, so a
  genuinely dead socket is never re-asked.

## Where it landed

`scripts/handoff-fire.sh` — `kitty_socket_accepting` (new), `hf_remote_pane_term`,
`hf_remote_pane_term_say`. Red-proofed in `tests/handoff-remote-pane-term.bats`; the fixture that
carries the whole lesson is one syscall wide — `mksock` binds without `listen()`, `mklistener`
listens and never `accept()`s.
