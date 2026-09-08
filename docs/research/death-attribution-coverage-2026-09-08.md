# Crash-cause attribution coverage — why 80% of session deaths land in the catch-all

**Date:** 2026-09-08 · **Backlog:** `b33d837c8a86` · **Store:** `~/.claude/logs/claude-crashes.jsonl`
(1,079 rows), `~/.claude/logs/close-records/` (1,831 records), `~/.claude/logs/stderr/` (50 logs).

## The answer in one line

The coverage gap is **exactly** the close-record gap, and the close-record is missing because
`bin/cc-close-attrib` only ever wrote it on its **normal exit path** — so any kill that reached the
wrapper itself produced no record at all, and the classifier had nothing left to read.

## The measurement that makes it one question, not two

Partitioning September's deaths by whether a close-record was joined:

| cause | with a close-record | without |
|---|---|---|
| `clean-exit` (RECYCLE) | 283 | 0 |
| `external-sigterm` | 6 | 0 |
| `error-exit` | 5 | 0 |
| `deliberate-teardown` | 5 | 10 |
| **`abrupt-unknown`** | **0** | **151** |
| `suspected-oom-large-context` | 0 | 4 |
| `no-transcript` | 0 | 12 |

**Every** September crash that carries a close-record is attributed to a named cause, and **151 of
151** `abrupt-unknown` crashes carry none. The classifier is not weak; it is being asked to decide
with no evidence. (The 49 all-time `abrupt-unknown` rows that *do* carry a record are all from
before 2026-08-09 and were cured by the `external-sigterm` arm — every one is exit 143.)

Coverage collapses in bursts, exactly as the backlog row reports: `abrupt-unknown` was 44/60 on
09-03 and 41/95 on 09-06, but only 14/149 on 09-07 — a day with far more deaths and a healthy box.

## The mechanism, confirmed on live data

`bin/cc-close-attrib` runs the real binary as a backgrounded `exec`, waits for it, and then calls
`write_record`. The file's own header already named the consequence — *"a group SIGKILL (OOM killer,
force-quit) takes this wrapper down with its child and write_record never runs"* — but treated it as
a limitation of the stderr tail rather than as the attribution gap itself.

The confirming case is pid **29662** (2026-09-05, session `53b20d64`). It has a durable stderr log,
`~/.claude/logs/stderr/20260905T041807-29662.log`, which the wrapper hard-links **at launch** — so
the launch *was* wrapped and the wrapper *was* running. Its crash row reads:

```
"cause":"abrupt-unknown", "exit_code":"", "signal":"", "stderr_tail_path":"",
"stderr_log":"/Users/chrisren/.claude/logs/stderr/20260905T041807-29662.log"
```

Start-time artifact present, exit-time artifact absent. That is the signature, and it is not
recoverable after the fact — nothing else on disk carries the exit status.

## What changed

**A start-registered record** (`bin/cc-close-attrib`). The record is now written **twice to the same
path** — the filename is keyed on `START_EPOCH`, so it does not move. Once as
`"record_state":"open"` the moment the child pid is known, and once as `"closed"` on the exit path.
An abrupt death therefore leaves a *partial* record instead of none.

The open record is deliberately invisible to every pre-existing consumer: its `exit_code` is the
bare JSON literal `null`, which `close_record_field` (matching only `"key":"…"` or `"key":<digits>`)
reads as **absent** — byte-for-byte the behaviour it had when the file did not exist.

**A third state, not a guess** (`hooks/lead-crash-watchdog.sh`). `record_is_orphaned` reports
`killed-before-report` only when the record is `open` **and** the wrapper that owns it (its `ppid`
field, which is the wrapper's own `$$`) is gone. The liveness half is what makes it a fact rather
than a race: the wrapper writes its record *before* it exits, so "wrapper gone + record open" means
the writer was prevented from running. While the wrapper is alive we are inside the millisecond
window between the child's death and the record's close, and the arm **abstains** — a false CRASH
pages, and this must never manufacture one. A reused pid reads ALIVE and also abstains.

The claim is narrow on purpose. `killed-before-report` says *the wrapper was alive and was destroyed
before it could report*; it says nothing about **what** killed it. A wrong named cause is worse than
`abrupt-unknown`, which at least advertises that it does not know.

**Placement.** The arm sits at rung 3, below jetsam and below both deliberate-teardown arms, so it
can only ever refine what would otherwise be the catch-all — it can never flip a RECYCLE into a
CRASH. It *does* outrank `suspected-oom-large-context`, because that is an inference from transcript
size and this is read off a file the wrapper wrote.

## Two defects found alongside, both fixed here because the change above requires it

**1. The death anchor was the session's BIRTH.** `resolve_death_epoch` read the epoch out of the
close-record's *filename* and documented it as *"the exact death instant, not a proxy"*.
`cc-close-attrib` names the file `${pid}-${START_EPOCH}.json`, and `START_EPOCH` is taken before the
binary is exec'd. Measured over the 1,831 records carrying both stamps: median session life **43.5
min**, and **87.7% live longer than the ±6-min jetsam window** that this epoch feeds. One sample —
pid 5148, filename epoch `2026-09-08T00:04:10Z`, actual `ended_at` `02:02:57Z`, off by 1h58m. It now
reads the record's own `ended_at`; an open record has none and correctly falls through to the
transcript mtime rather than asserting its start time as its death.

This fix is **required**, not incidental: the start-record gives every wrapped session a record, so
without it the wrong anchor would go from occasional to universal.

*Honest bound on its value:* this box holds exactly **one** `JetsamEvent-*.ips` (2026-09-01), so
macOS jetsam is not the mechanism behind these deaths and correcting the anchor buys almost no
coverage today. It is fixed as a correctness defect and as a precondition, not as a coverage win.

**2. `close_record_field` on a missing key — a hazard that is NOT reachable, and the guard for it
was therefore removed again.** It runs under `set -euo pipefail`; a `grep` matching nothing exits 1
and pipefail promotes it, so asking for a key a record does not carry looks like it should take
`classify_death` down mid-ladder. `record_state` is absent from all 1,831 legacy records and
`ended_at` from every hand-written fixture, so this change is the first to take that path — and the
first instinct was to add `|| true`.

That guard was written, then deleted, because it could not be given a control. Removing it and
re-running the whole 28-arm suite left **every arm green**: `set -e` is suspended inside an `if`
condition and inside a command substitution feeding an assignment, and both new call sites
(`record_is_orphaned`, `resolve_death_epoch`) are exactly those two shapes. The abort has no
reachable call site today. What survives is the comment recording the measurement and the shape that
*would* abort — a bare-statement call — so the next person adding one knows to bring a red test with
it. The arm that pins the behaviour (`a LEGACY record missing the new keys still classifies`) is
labelled in the suite as a regression pin, not a control, because it is green on both sides.

## The other coverage hole — fixed too

**Resumed sessions are never wrapped.** `scripts/limit-recover/lr-fire-resume.sh:410` spawns the
binary directly under `expect`:

```
spawn -noecho env -u CLAUDE_CODE_CHILD_SESSION DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR=$cfg \
  $bin --permission-mode auto --model $model --effort $effort --resume $sid
```

There is no `cc-close-attrib` in that line, so those sessions can produce no close-record however
they die — and the start-record above cannot help them. Live census, 2026-09-08: of **20** running
leads, **15** are wrapped and **5** are not; all five unwrapped ones are `lr-fire-resume` spawns.

The spawn now has two branches differing only by the wrapper prefix. **Fail-open is the whole reason
it is a branch and not an interpolated prefix:** on the limit-recovery path a session that does not
come back is strictly worse than one that comes back unattributed, so an unresolvable wrapper costs
the *record*, never the *recovery* — and an empty prefix could not simply be spliced in, because
expect would hand `env` an empty argument to exec.

**The doubt worth naming is not the wiring, it is the pty.** `cc-close-attrib` background-execs its
child, routes fd2 through a FIFO into a `tee`, and traps INT/TERM/HUP — and under `spawn` all of
that runs as the process expect owns the terminal through. A `grep` for the wrapper's name in the
file would say nothing about it. So `tests/lr-fire-resume-close-attrib.bats` extracts the expect
program **verbatim from the subject** and runs it against a stub binary, with the real wrapper; the
verdict is the close-record, a file that exists only if the wrapper was interposed *and* survived to
its exit path. Three arms: the record appears with the stub's real exit status; an empty `LR_WRAP`
still recovers the session and writes no record; and both streams still reach the pty, which is what
every menu pattern in that program is matched against.

## What this does and does not raise

It converts, into an attributed cause, every future death **of a session whose wrapper was destroyed
with it**, and it brings resumed sessions inside that instrument for the first time — 5 of the 20
leads running when this was written.

It converts nothing retroactively. The historical rows cannot be recovered: the evidence was never
written. And it names no cause it cannot support — a death with no record at all still reads
`abrupt-unknown`, which after this change means the launch was not instrumented, a third and
narrower problem than the one this started as.
