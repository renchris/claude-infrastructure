# `--idle-scoped` could not survive the turn that armed it

**Date:** 2026-08-27 · **Backlog:** `b60eb29e97dd` · **Subject:** `bin/cc-await-ping` (C2, the
stand-down oracle) · **Fixed in:** the commit that adds this file.

## The finding, first

`cc-await-ping --idle-scoped` — the one wake path sanctioned under a live `/goal` — stood itself
down within seconds of every arm, at the very Stop that ended the turn it was armed in. Measured
**2/2** in the field, the two watchers announcing `beat seq > 3` and `beat seq > 6` and then
exiting `verdict=stood-down` on `seq` 4 and 7 respectively.

The wake floor (`hooks/session-continue.sh`) then spent its whole `CC_WAKE_FLOOR_MAX=2` budget
re-instructing the same arm, hit `wake floor exhausted — allowing stop, unarmed`, and the session
went idle **deaf** — the exact failure the floor exists to prevent. A peer's `--notify-back` ping
would land in the inbox and sit there until someone typed.

## Root cause: the allowance was gated on a beat kind that path can never produce

The arm gate captured the baseline and then set the one-beat allowance conditionally:

```bash
BEAT_BASE_SEQ="$(_beat_field "$SID" '.seq')"
[ "$(_beat_field "$SID" '.kind')" = "prompt" ] && BEAT_STOP_ALLOWANCE=1
```

That gate encodes an assumption: *turns alternate prompt/stop, so a sample taken inside a turn is
that turn's own prompt beat, and the only boundary still to come is its trailing Stop at
baseline+1.* True of an arm typed inside an operator's turn — which is the shape every test in
`tests/cc-await-ping.bats` modelled, all of them baselining on `beat N prompt`.

**The site that demands the arm does not produce one.** The three sites that instruct it do not share
a channel, and only one of them opens a turn the way the gate assumed:

| Instructing site | Channel | Does its arm turn open with a prompt beat? |
|---|---|---|
| `hooks/session-continue.sh` wake floor — **the site that blocks the stop to demand it** | Stop hook `decision:"block"` | **No** |
| `hooks/mailbox-drain.sh` (goal-aware branch) | `UserPromptSubmit` `additionalContext` | Yes |
| `hooks/validate-bash.sh` | PreToolUse `deny` — a `tool_result` inside whichever turn is running | Either |

An oracle that must be right on all three therefore cannot be keyed on the arm turn's opening beat
at all. And the one that demands it is the one that has none, because a Stop-hook continuation turn
**fires no `UserPromptSubmit`**. Decompiled from
`@anthropic-ai/claude-code` `cli.js` (2.1.42; the shape is unchanged from the 2.1.220 reading in
`docs/research/final-response-shaping-2026-08-08.md`):

1. On a Stop hook's `blockingError`, the harness builds the feedback user message *itself*:
   `let y = d6({content: mSA(k.blockingError), isMeta:!0})` where
   `mSA(A) = "Stop hook feedback:\n" + A.blockingError`. It is pushed onto `blockingErrors` and
   yielded straight into the message stream.
2. The query loop consumes it by **continuing**, not by re-entering input processing:
   `if(L1.blockingErrors.length>0){ … messages:[...G,...k,...L1.blockingErrors], stopHookActive:!0 … continue}`.
3. `executeUserPromptSubmitHooks` (`iSA`) has exactly **one** call site in the bundle, inside
   `processUserInput` — which that `continue` never reaches.

So `hooks/session-beat.sh` writes no `prompt` beat for the arm turn. The newest beat the arm can
sample is the **previous** turn's Stop, `kind = stop`, the gate failed, the allowance stayed `0`,
the threshold was the baseline itself, and the arm turn's own trailing Stop at baseline+1 tripped
C2 on the next poll. Deterministic, not flaky — hence 2/2, and hence the two announced thresholds
being the raw baselines `3` and `6`.

The field values also corroborate the mechanism independently: under strict prompt/stop alternation
a Stop beat would carry even `seq`, and `3` is odd. A session whose auto-driven turns contribute
only Stop beats produces exactly this parity drift.

## The fix

The allowance is now **unconditional**, and the invariant it rests on is kind-independent:

> At most one boundary beat can be written by the arm turn *after* the arm — its own trailing Stop —
> because a turn's opening beat, when it has one at all, precedes the arm.

So tolerate exactly one, always. The `_turn_moved` second clause is what keeps that from becoming a
blind spot: a `prompt`-kind beat above the baseline is never the arm turn's own, so a queued
operator prompt or a task notification still stands the watcher down at +1.

| Baseline sampled at arm | Next beat | Before | After |
|---|---|---|---|
| `N prompt` (operator-turn arm) | `N+1 stop` — own trailing Stop | keep watching | keep watching |
| `N stop` (**the real path**) | `N+1 stop` — own trailing Stop | **stand down** ✗ | keep watching ✓ |
| `N stop` | `N+1 prompt` — a new prompted turn | stand down | stand down ✓ |
| `N stop` | `N+2 stop` — another blocked-stop turn | stand down | stand down ✓ |
| `N prompt` | `N+2` or beyond | stand down | stand down ✓ |

Behaviour on the previously-working `prompt` baseline is byte-for-byte unchanged; only the
`stop`-baseline column moves, and only for the single beat the arm turn itself is owed.

## Tests

`tests/cc-await-ping.bats`, block `b60eb29e97dd`: the arm-turn survival case on a `stop` baseline,
two controls (baseline+2 stop, and a prompt at baseline+1 — both must still cancel, so the fix
cannot be satisfied by a watcher that never self-cancels), and a **red-proof against the pinned
pre-fix sha `6e7a4bf1`** that reproduces the field failure exactly: `verdict=stood-down` at
`beat seq > 3`.

## The generalisable lesson

The design doc states C2 as *"a UserPromptSubmit-kind beat newer than the baseline taken at arm"*
(`docs/research/goal-safe-2way-comms-2026-08-13.md` §4). That sentence is not implementable as
written on this substrate, because the code path that arms the watcher is precisely the one that
produces no UserPromptSubmit. **A stand-down oracle keyed on an event class must be checked against
the invocation path that will actually arm it** — and the suite that would have caught this
modelled the arm as an operator typing it, which is the one way it is never armed.
