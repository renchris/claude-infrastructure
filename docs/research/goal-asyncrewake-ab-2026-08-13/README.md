# The 0007 A/B — an `asyncRewake` watcher keeps the wake path AND lets the goal evaluate

Evidence bundle for the last open half of backlog item `d9d0012229b7`: *"asyncRewake wake-path fix
would let goals evaluate AND keep the wake path — staged migration 0007, needs a live A/B."*

**Ran on:** CC **2.1.231**, 2026-08-13 14:52–15:03 UTC, Linux container, subject model
`claude-sonnet-5`. Three hermetic `CLAUDE_CONFIG_DIR` sessions, driven headless over
`--input-format stream-json`.

---

## What was already settled, and what this closes

`migrations/0007-mailbox-wake-arm-registration.sh` registers `hooks/mailbox-wake-arm.sh` as a
SessionStart hook with `asyncRewake: true`, so every session is inbox-armed at birth with no model
action. Two of its three load-bearing claims were already evidence-backed when it landed:

| Claim | Status before this bundle |
|---|---|
| an `asyncRewake` hook is backgrounded and wakes an idle model on exit 2 | **MEASURED** — `docs/research/w0-asyncrewake-proof/` (W0, CC 2.1.219) |
| a parked background Bash defers goal evaluation at every Stop | **MEASURED** — `goal-in-handoff-2026-08-08.md` § RESOLVED + its own A/B (`d33abf12` vs `1d46d9c4`) |
| **an `asyncRewake` hook does NOT defer it — the goal still evaluates** | **read out of the binary only** (`bip()` @237768400 tracks it in a module Set, not `taskRegistry`) |

The third row is the one the item was filed against, and it is the one that matters operationally:
it is the whole reason 0007 is a *fix* rather than a lateral move. A binary reading is not nothing,
but this repo's most-measured trap is the documented-but-inert surface — Stop `additionalContext`
was documented and provably dead — so the standing rule is *probe it, do not cite it*. **This bundle
probes it.**

## Method — one variable, and CC's own registry as the oracle

Three arms. The **same** poll-the-mailbox watcher, the **same** unmet goal, the **same** Stop hook.
The only thing that differs is **how the watcher is registered**:

| Arm | Registration | File |
|---|---|---|
| `armB` | SessionStart hook, `"asyncRewake": true` — what 0007 does | `run-probe.sh async` |
| `armA` | the model launches it as a background Bash — the pre-0007 habit | `run-probe.sh parked` |
| `armA2` | same, with a task that outlives several Stops — the strong control | `run-probe.sh parked-long` |

**The oracle is not `ps`, and not the assistant's prose.** `stop-probe.sh` is a Stop hook that
records the harness's own `background_tasks` array at every Stop. That array is the very population
CC's deferral predicate scans, spread into every Stop hook's input — so each row below pairs *CC's
own view of the task registry* with *whether the goal was judged at that Stop*. Goal evaluations are
counted as `goal_status` **attachments** with `sentinel` absent; the sentinel record is the arm, not
a verdict, and a bare `grep goal_status` also matches the assistant's own prose (6 hits where the
truth was 1, on the transcript that produced the original finding). `timeline.py` and `tally.py`
apply both filters.

The goal condition is deliberately unmet and its truth lives **outside** the session — *"the file
`/tmp/probe-approval.txt` contains the line APPROVED — only the operator writes that file; never
create or edit it yourself"* — so every evaluation returns `met=false` and the **count** of
evaluations is the signal. Without the final clause the subject would satisfy its own goal and end
the series after one verdict.

## Result

```
armB      registry-EMPTY stops=9   → evaluations=9   | registry-OCCUPIED stops=0   → evaluations=0
armA      registry-EMPTY stops=14  → evaluations=14  | registry-OCCUPIED stops=1   → evaluations=0
armA2     registry-EMPTY stops=1   → evaluations=1   | registry-OCCUPIED stops=5   → evaluations=0
TOTAL     registry-EMPTY stops=24  → evaluations=24  | registry-OCCUPIED stops=6   → evaluations=0
```

**30 Stops, perfect separation, no exceptions in either direction.** Occupancy of the task registry
predicts goal evaluation exactly; nothing else does.

The two rows that answer the item:

- **`armB` — the asyncRewake watcher was alive across 5 of those 9 Stops and the registry was empty
  at every one of them.** `armB-watcher-lifecycle.txt` shows `START pid=19385` at 14:52:16 and
  `alive` polls running continuously to `FIRE poll=114` at 14:54:10; the Stops at 14:52:41, 14:52:52,
  14:53:00, 14:53:12 and 14:53:19 all fall inside that window, all read `background_tasks=0`, and
  all five produced an evaluation. A live watcher that the registry cannot see is precisely the
  property 0007 is built on, and it is now observed rather than derived.
- **`armA2` — 5 consecutive Stops holding one `shell/running` task produced ZERO evaluations**,
  in a session whose very first Stop (registry empty, same goal, same hooks) had evaluated
  normally 20 seconds earlier. This is a *within-session* control, which is stronger than the
  between-session A/B in the 08-08 doc: session identity, model, config and condition are held
  fixed by construction, and only the registry moves.

And the wake half held in the same run. `armB-wake-record.json` is the harness-synthesized turn:

```
origin.kind = "task-notification"
<task-notification><summary>📬 probe mail</summary></task-notification>
<system-reminder>📬 PROBE mail arrived while you were idle: PROBE-WAKE-LINE-B …</system-reminder>
```

The external write was a single `echo >>` from an unrelated shell while the subject was idle —
zero model participation — and the model took a turn on it 8 seconds later. So `armB` delivered
**both** properties in one session: 9 goal evaluations *and* a working idle wake. `armA` also woke
(its parked task completed, which re-invokes an idle model), which is the honest statement of the
trade the fix removes: **the pre-0007 shape buys the same wake by spending the goal.**

## Positive control

`watcher.sh` was run standalone first and fed a line: it fired within 3 polls and exited 2 with the
body on stderr (`POSITIVE CONTROL rc=2 stderr='PC-MAIL-LINE'`). A null result in `armB` could
therefore only have meant *"the harness did not dispatch or wake"* — never *"the watcher was
broken."* Same discipline as W0, and for the same reason.

## How to re-run

```
PROBE_ROOT=/tmp/probe CC_BIN=/path/to/claude ./run-probe.sh async
PROBE_ROOT=/tmp/probe CC_BIN=/path/to/claude ./run-probe.sh parked-long
python3 tally.py /tmp/probe/async /tmp/probe/parked-long
```

Two environment facts the harness depends on, both of which will silently produce a null if
disregarded. `--input-format stream-json` makes `hasStreamingInput` true, which is the `K` half of
the dispatch gate `(e.async || e.asyncRewake && K) && !d`; under a plain one-shot `claude -p`, K is
false and an `asyncRewake` hook is dispatched **synchronously**, so the arm would measure a blocked
birth instead of the mechanism (this is exactly what `mailbox-wake-arm.sh`'s headless guard exists
to prevent). And a nested session inherits `CLAUDE_CODE_SESSION_ID` from its parent and will write
into the **parent's** transcript — `run-probe.sh` unsets it, and the first draft of this probe did
not, which is how that was found.

## What this does and does not establish

**Establishes**, on 2.1.231: an `asyncRewake` SessionStart hook is dispatched asynchronously, is
absent from `background_tasks` for its whole life, does not defer goal evaluation, and wakes an idle
session on exit 2. That is every claim 0007's header makes about the mechanism, now measured
end-to-end in one session rather than assembled from a code read plus a separate wake proof.

**Does not establish** — and these are deliberately left open:

- **The Stop-side (W2) probe is still un-run.** A4 in `goal-safe-2way-comms-2026-08-13.md` remains
  "MEASURED on SessionStart / UNPROBED on Stop", and P-W2a–d are still gated on backlog
  `62e0b88a58b5`. Nothing here transfers: the gate expression looks event-agnostic, but exit 2 is
  overloaded as Stop's *block* code, which is the whole reason that one needs a probe.
- **The version is 2.1.231, not the 2.1.220 the fleet was measured on.** This is corroboration in
  the forward direction — the mechanism survives three tracks — not a re-measurement of 2.1.220.
- **Headless streaming, not the TUI.** The deferral lives in the Stop-hook dispatch path, which is
  shared, but no TUI arm was run.
- **Nothing about evaluation *cadence*.** `armA`'s 14 evaluations over ~4 minutes on an unchanged
  world are the spin pole that `goal-safe-2way-comms-2026-08-13.md` §4 exists to address. This
  bundle shows the goal *is judged*; it makes no claim that judging it that often is desirable.
