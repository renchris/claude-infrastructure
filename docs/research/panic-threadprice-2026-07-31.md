# The measuring instrument panicked the machine — 2026-07-31T11:46:47

**One line.** A research subagent asked to "price a parked thread on this box" wrote a thread-spawning
microbenchmark, ran an unbounded escalation ladder `2000 → 8000 → 16000`, and at **8,368 live threads
in one task** the kernel took a **spinlock-timeout panic** and the machine hard-rebooted — destroying
the operator's 19 live Claude Code sessions and the 11h57m-uptime 48-pane kitty that was itself the
irreplaceable evidence for the study the probe was serving.

**The instrument became the outage it was studying.** The workflow prompt that spawned this agent
contained the sentence *"The instrument must never be the cause of the outage it is studying"* — and
it was enforced only by a `loadavg` guard, which cannot see thread creation. 8,368 parked threads
contribute ~nothing to loadavg (they are blocked, never runnable), so the one guard in place was
**structurally blind to the one resource being exhausted**.

---

## 1. The evidence, and it is unambiguous

`/Library/Logs/DiagnosticReports/panic-base+socd-2026-07-31-114647.000.panic`:

```
panic(cpu 0 caller 0xfffffe00272d9930): Spinlock[0xfffffe28cbeed5e8] timeout after 12583200 ticks;
  current owner: 0xfffffe22f605efe0 (on cpu 6), start time: 2416660914538, now: 2416673497738,
  timeout: 12582912 @locks.c:446

Panicked task 0xfffffe2407420eb8: 8444 pages, 8368 threads: pid 57267: threadprice
Kernel Extensions in backtrace:
  com.apple.kec.pthread(1.0)[47578D84-B49B-33E9-BC55-38795586C3FA]
```

Machine: MacBookPro18,2 · M1 Max · 64 GiB · macOS 15.6.1 (24G90) · xnu-11417.140.69.

**Attribution chain, each link checked rather than assumed:**

| link | evidence |
|---|---|
| the panicked task is the probe | `pid 57267: threadprice` — named in the panic log itself |
| the probe was ours | exactly **1** of 4 agent transcripts contains the string `threadprice`; it is the R4 agent (`agent-ade7ae9c6601ba3f4.jsonl`, 6 occurrences) |
| the probe was thread-exhaustion by design | its own header: *"price a PARKED thread on this box. N threads, each blocked forever on a condvar"* |
| the ladder was unbounded | invocations recorded in the transcript: `threadprice 2000 32`, `8000 32`, `1 32` (control), **`16000 32`** |
| timing is causal, not coincidental | last transcript write **11:45:07**, panic **11:46:47** — 100 s later, mid-climb toward 16,000 |
| the kernel subsystem matches | `com.apple.kec.pthread` in the backtrace; the spinlock is in `locks.c` |

**It is NOT a recurrence of the 2026-07-30 panic.** That one reads
`watchdog timeout: no checkins from watchdogd in 92 seconds`, panicked task `pid 0: kernel_task`,
731 threads — a different class entirely. The compressor-segment guard shipped for it is not
implicated, and this incident must not be filed against it. (Two panics in two days on one box invites
exactly that conflation; the panic strings are the discriminator.)

---

## 2. The generalisable defect: a probe that finds a limit BY HITTING IT

The brief said *"measure or cite the kernel constant"* — an either/or that let the agent choose the
destructive branch. On a shared machine hosting the operator's live work, that is not a 50/50 choice:

> **A resource limit discovered by exhausting the resource is discovered by breaking the machine.**
> The number is obtainable from `sysctl`, from XNU's `kernel_stack_size`, or by differencing two
> populations that already exist for other reasons — none of which can panic anything.

The second, subtler half: **the two-point slope was already free.** The very study this probe served
had measured WezTerm at **33 threads @ 6 panes** and **257 threads @ 38 panes**. That is a complete
two-point measurement of per-thread cost against real RSS, at thread counts the machine already
survives daily. The probe re-derived, destructively, a number the corpus already contained.

**Guards must bind the resource actually being consumed.** A `loadavg` ceiling, a memory-pressure
rung, and a swap alarm were all in place and all read GREEN through the entire climb, because parked
threads consume none of those three. Cross-check: which resource does this probe *increase*, and is
anything watching *that*?

---

## 3. What it cost, stated plainly

- 19 live Claude Code sessions, killed mid-turn.
- The `kadv` kitty at **11h57m uptime / 48 panes / 4 OS windows / 10 threads** — the run that was
  about to close `terminal-for-30-panes-2026-07-31.md` §6.1 ("No multi-hour run of any challenger …
  **This is the single largest gap**"). Its T0 reading survives only because it was captured in
  conversation before the reboot; **the second drift reading never landed, so §6.1 remains OPEN.**
- The salvaged T0, which is a level and explicitly **not** a leak verdict:

  ```
  terminal-bench — app=kitty pid=46345 panes=48 interval=900s  2026-07-31T18:38:44Z
    T0  app   cpu=26.6 mem=710MB th=10 ports=381 win=23 off=23
    T0  WS    cpu=50.0 mem=1659MB th=26 ports=5053 win=13 off=8
  ```

  **10 threads at 48 panes after 12 hours** — kitty's flat-thread finding holds at double the
  previously-tested pane count. iTerm2 at the same moment: 83.4% CPU, 12 threads, ~19 sessions.

---

## 4. One real finding, and the arithmetic that keeps it honest

There is a hard ceiling near **~8k threads in a single task** where this box **panics rather than
degrades**. That is worth knowing and was not previously recorded here.

It must not be allowed to imply a verdict it does not support. WezTerm's measured **~7.0 threads per
pane** is **~210 threads at 30 panes** — *two orders of magnitude* below the ceiling. **The panic does
not condemn WezTerm.** A dramatic failure discovered while investigating a candidate is not evidence
against that candidate unless the arithmetic connects them, and here it does not.

---

## 5. The fix that is now in force

Written into the workflow brief for every agent, replacing the single loadavg guard:

- Hard ceilings: **≤512 threads · ≤64 panes · ≤16 windows · ≤64 processes**, total, ever.
- **No open-ended escalation ladders.** Want a slope? Take two points *inside* the ceiling and fit a
  line. Two points inside the cap beat a third point that reboots the box, and a rebooted box
  measures nothing.
- **Never write a program whose purpose is to exhaust a kernel resource to find its limit.** Read the
  limit from `sysctl` / kernel source / documentation.
- If a measurement genuinely requires exceeding a ceiling: **do not do it.** Return `PARTIAL` and name
  what would have been needed. An unmeasured number is a cost; a panic is a catastrophe.

Related: `terminal-for-30-panes-2026-07-31.md` · `iterm2-freeze-30-sessions-2026-07-30.md` ·
[[load-is-not-a-function-of-session-count]] (loadavg is not attributable to what you think) ·
[[bounding-external-calls]] (a per-fork bound multiplies across a loop).
