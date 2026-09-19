# A sum of per-process CPU averages is not system utilization

**2026-09-19.** The operator asked whether the `cc-bats` concurrency gate — which had been deferring
a test run — was a mission-critical blocker deserving a dedicated frontier research session. The
question turns entirely on one fact: **is the box actually saturated, or is the gate misfiring?**

## The two instruments that disagreed, and the story that almost shipped

```
sysctl -n vm.loadavg        →  { 116.35 120.63 109.73 }   on 10 cores
ps -Ao pcpu,comm | awk sum  →  ~390% of a 1000% ceiling   (~39%)
```

Load said 11.6× oversubscribed. `ps` said the machine was **61% idle**. I built a mechanism that
reconciled them and it was entirely plausible: Darwin's load average counts uninterruptible
(I/O-blocked) threads as well as runnable ones, and the process list showed 32 `mdworker_shared`
plus `mds` plus `XprotectService` at 99.6% — Spotlight indexing and XProtect scanning a 35-worktree
farm. Conclusion: the load figure is mostly I/O wait, the gate keys on `load/core ≥ 2.0`, therefore
the gate is deferring real work on a signal that is not CPU contention. Cheap fix, tidy story.

Then the third instrument:

```
top -l 2 -n 0 -s 1   →  CPU usage: 60.10% user, 39.63% sys, 0.26% idle
```

**The box was pegged.** Six concurrent `ship-land.sh` runs, ~11 Claude sessions, several whole-tree
bats suites. The gate was reading a real signal and reporting it correctly. Every step of the
reconciling story was individually true and the conclusion was backwards.

## Why `ps` undercounts, and why it undercounts *worst* exactly when you need it

`pcpu` is a **decayed average over each process's own lifetime**, and the sum is taken over the rows
that exist at one instant. Both properties fail on the same population:

- A fleet of short-lived forkers — here **124 `bash` processes**: hook chains, statusline renders,
  `cc-close-attrib`, mailbox drains — each accrues a tiny lifetime average while collectively eating
  the cores.
- Everything that already exited contributed CPU that **no surviving row carries**. The higher the
  churn, the more of the machine's real work is invisible to the census.

So the error is not noise and it is not symmetric: it is a systematic undercount that grows with
exactly the churn that causes saturation.

## The rule

**To ask whether a system is saturated, read the kernel's own aggregate — never a sum over
per-process rows.** On macOS that is `top`'s `CPU usage` line (`top -l 2 -n 0`; take the *second*
sample, the first is a since-boot average and is itself a different question). `ps` answers "what has
this process averaged", which is a fine question and not this one.

**And load average is not utilization either.** On Darwin it counts runnable *and* uninterruptible
threads, so it can be high on an I/O-bound idle box and is not a percentage of anything. It is a
queue-depth signal. Useful, not interchangeable.

## The meta-rule, which is the part worth carrying

Two instruments disagreed, and I reached for the mechanism that **reconciled** them rather than for a
third instrument that could **adjudicate** them. The reconciling story was seductive precisely
because it was well-informed — it required knowing a real Darwin detail — and being well-informed is
what made it convincing rather than what made it right.

This is the same shape the always-loaded rules already record for a disagreeing probe
(*"do not reach for the story that reconciles them; re-run BOTH arms and let the weaker instrument
lose"*), arriving here through measurement rather than through a version history. When two readings
of one quantity disagree, **the disagreement is the finding**: get an authoritative third reading
before any conclusion rests on either.

Companion: [[a-read-only-surface-must-not-be-able-to-hold-state]] — same session, and the same
failure twice more, where a green test suite was evidence about the fixture rather than about the
subject.

## Re-derive

```bash
sysctl -n vm.loadavg; sysctl -n hw.ncpu
ps -Ao pcpu,comm | awk 'NR>1{s+=$1} END{print s"% summed"}'
top -l 2 -n 0 -s 1 | grep '^CPU usage' | tail -1      # the arbiter
```
