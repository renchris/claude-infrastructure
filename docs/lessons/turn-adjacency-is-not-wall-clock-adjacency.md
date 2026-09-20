# Turn adjacency is not wall-clock adjacency

**The rule.** A session's turns are adjacent in the *transcript*, never necessarily in *time*. An
idle-driven session can sit hours between one turn and the next, so any duration you infer from
"this happened right after that" is unmeasured. When a duration is load-bearing for a verdict,
measure it — `date`, `stat -f %SB/%Sm`, a process's own `etime` — and never read adjacency as
elapsed time.

## The incident (2026-09-20)

`cc-await-ping` was armed as a background Bash task. It came back `failed with exit code 2`, and
its own output explained why, in as many words:

```
verdict=timeout term=full elapsed=14499s budget=14400s uuid=286 — no ping arrived.
A term=full outcome is the DESIGNED end of a watch that ran its term, not a failure:
exit 2 here means 'nothing came', and the harness labels every non-zero exit 'failed'.
Nothing is wrong and nothing needs debugging.
```

That was read correctly and reported to the operator as benign. The watcher was then re-armed, and
the *second* arm returned the same shape with `elapsed=16782s` — 4 h 39 m.

The re-arm had happened **one turn earlier**, so it was asserted to the operator that the watcher
had "exited within a minute, not after a 4-hour term", that the benign explanation therefore did
not cover it, and that `elapsed` must be anchored to some stale per-pane stamp a re-arm fails to
reset — i.e. that every re-arm was born past its budget and the fleet's wake path was structurally
dead. A confident, specific, wholly invented mechanism.

**It was refuted by reading the script.** `T0="$(date +%s)"` is stamped at the top of
`bin/cc-await-ping`, before arg parsing — the file says so directly: *"Stamped HERE, before arg
parsing and before the owner-guard oracles, so the delta covers the watcher's WHOLE life."* There
is no shared anchor. `elapsed` is, and always was, that process's own lifetime.

**Then by measuring.** `stat` on the two task-output files:

| task | created | last write | delta | reported |
|---|---|---|---|---|
| arm 1 | 04:10:03 | 08:11:42 | 14 499 s | `elapsed=14499s` |
| arm 2 | 08:12:18 | 12:52:00 | 16 782 s | `elapsed=16782s` |

Both match to the second. Both ran full terms. The session had simply been idle for 4 h 41 m
between the arm and the notification — one turn, nearly five hours.

## Why it is worth a rule

The error is not arithmetic; it is that **a model has no clock**. Wall time is not perceptible
from inside a transcript, so "recently", "just now" and "within a minute" are *inferences from
turn position* wearing the clothes of observation. Every one of them is free to be hours wrong,
and the direction of the error is unbounded in exactly the case that matters — an idle session,
which is when background work is running and when its results come back.

It is a sibling of [`narrated-verdict-is-indistinguishable-from-a-computed-one`](../../.claude/rules/agent-operating-lessons.md):
both are about the model as a *fabricating instrument*, producing something that reads back as
evidence. Here the fabricated quantity was a duration, and it was used to overturn a correct
verdict that the subject had printed about itself.

Note the aggravating factor: the tool was unusually loud and unusually right. It stated its own
verdict, named its own exit code, and said *"nothing needs debugging"*. Inventing a mechanism to
contradict that required ignoring a plain-language explanation the subject had already supplied —
which is what a wrong duration was sufficient to justify.

## The 39-minute overshoot, which is also not a defect

Arm 2 exceeded its 14 400 s budget by 2 382 s. `cc-await-ping` documents this at ~line 1001: the
wait loop re-tests `elapsed < TIMEOUT` once per `--interval` (15 s), and 7 % of observed runs
report `elapsed >= budget`. Under the load average of ~197 on 10 cores measured that day, a 15 s
interval starves by minutes at a time. An overshoot is evidence about the *box*, not the watcher.

## What to do instead

1. **Never infer a duration from turn order.** If a verdict turns on how long something took, run
   a clock: `date`, `stat -f '%SB' -t '%F %H:%M:%S'` on the artifact, `ps -o etime=` on the pid.
2. **Read the subject's own explanation before building a mechanism to contradict it.** A tool
   that prints `verdict=`, its budget and a sentence about what its exit code means has already
   done the work; a contradicting theory needs evidence at least as strong.
3. **Grep for the anchor before claiming state is stale.** The claim "this stamp is never reset"
   is one `grep -n T0` away from being settled either way.
4. **Correct the correction.** Having published the invented mechanism, the honest repair was to
   measure, say plainly which of the two statements was wrong, and carry on — not to leave two
   contradicting claims standing for the reader to adjudicate.

## Companions

- `narrated-verdict-is-indistinguishable-from-a-computed-one` — the model fabricating a verdict.
- [`a-0-byte-output-file-is-not-a-dead-process`](a-0-byte-output-file-is-not-a-dead-process-it-is-a-process-that.md) —
  a sibling misreading of background-task liveness from an artifact rather than a measurement.
- [`freshness-is-relative-to-the-subject-not-the-clock`](freshness-is-relative-to-the-subject-not-the-clock.md) —
  the converse trap: having a clock, and comparing it to the wrong thing.
