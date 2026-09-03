# W6 — WHO SENDS THE SIGKILL: attributed, and it is `timeout` killing itself

**Verdict: the sender is the `timeout` process itself.** Not `cc-reaper`, not jetsam, not
`compressor-sentinel`, not `capacity-alarm`, not `lead-supervisor`, not `qos-census`, not any
external process at all. GNU coreutils `timeout`, when invoked WITHOUT `--foreground`, puts itself
and its child in a NEW PROCESS GROUP and delivers the `-k`/`--kill-after` escalation to that whole
group with `kill(0, SIGKILL)` — which includes `timeout`. `SIGKILL` cannot be caught or ignored, so
coreutils' own anti-self-signal guard (`signal(sig, SIG_IGN)` before `kill(0, sig)` in `send_sig()`)
is a **no-op for signal 9**. The escalation is self-inflicted by construction.

The box: `/opt/homebrew/bin/timeout` → `coreutils/9.1/bin/timeout`, GNU coreutils 9.1. That is the
binary `_tmo` resolves to under the launchd job's own PATH (verified through `zsh -lc` with the
plist's exact `PATH` export).

## The premise this wave was given, and why it was false

> "A `timeout` killing its own child surfaces as rc 124 or the child's status, so this SIGKILL
> arrives from OUTSIDE the process group."

The first clause is true of the CHILD's death and false of `timeout`'s own. Because `timeout` is a
member of the group it signals, it dies before it can reach its `status = EXIT_TIMEDOUT` assignment.
The parent shell therefore reports its direct child (the `timeout` pid) as killed by signal 9 and
yields 137. Every downstream conclusion built on "137 + a job-control line ⇒ an external sender"
inherits that error. Three correct code fixes were spent on the phantom it created.

## The evidence — an intervention, not a correlation

All arms run on this box, 2026-09-03T11:53Z, with every daemon in the suspect list loaded and
running. `TMO=/opt/homebrew/bin/timeout`.

### Arm A — the production signature, reproduced on demand

```
bash -c 'TMO=$(command -v timeout); "$TMO" -k 2 1 bash -c "trap \"\" TERM; sleep 40"; echo rc=$?'

bash: line 1: 22764 Killed: 9   "$TMO" -k 2 1 bash -c "trap \"\" TERM; sleep 40"
rc=137
```

Byte-for-byte the shape in `autonomy-sweep.err.log` — a job-control line naming the **`timeout`
pid**, and rc 137.

### Arm B — the SCOPE proof: a bystander that no matcher could select

`kill(0, SIG)` reaches the process GROUP. An external killer selects by name or argv and cannot
select on "shares a pgid with a process I matched". So put a bystander in the group whose argv
matches nothing on this box:

```
child      pid=36267  pgid=36265
bystander  pid=36272  pgid=36265     argv: /tmp/w6-pgid-victim.sh
bash: line 9: 36265 Killed: 9  "$TMO" -k 2 1 bash -c "..."
rc=137
--- bystander still alive? ---  NO w6-pgid-victim process remains
```

**All three members of pgid 36265 died** — `timeout` (36265, the group leader), its child (36267),
and the bystander (36272). The victim set is exactly the process group. That scope is reachable only
by a group-directed signal, and the only member positioned to send one at that instant is `timeout`
executing its `-k` escalation.

### Arm C — the COUNTER-arm: flip one flag, the group kill disappears

Identical command, same second, same daemons, one variable changed — `--foreground`, which is
precisely the flag that stops `timeout` creating and signalling its own group:

```
child      pid=39282  pgid=39277
bystander  pid=39283  pgid=39277
rc=137
--- bystander alive after --foreground arm? ---  39283 /bin/bash /tmp/w6-pgid-victim.sh
```

The bystander **SURVIVES**, and there is **no `Killed: 9` line** — `timeout` itself lived and merely
*reported* 137 as an exit code. The group kill is a property of the group-signalling path, nothing
else. If an external daemon were the sender, `--foreground` would not have saved the bystander.

### Arm D — control, and repeatability

A child that DOES die on SIGTERM never reaches the escalation: `timeout -k 2 1 sleep 40` → **rc 124**,
no job-control line. So the harness can produce the other verdict; it is not stuck on 137.

Arm A repeated N=5: **5/5** produced `Killed: 9` + rc 137, each within ~3 s of invocation. An
external killer on a 300 s tick cannot fire deterministically 3 seconds after an arbitrary command,
five times running.

## Why the escalation is reached in production (the precondition holds by construction)

`scripts/cloud-return.sh:776` — `trap 'lock_release' EXIT INT TERM`. A bash trap runs only *between*
commands. When the 900 s bound fires, the pass is typically inside `handle()` → `cloud-reconcile
--land` → `desk-land` → `ship-land`, a gate measured in minutes. The TERM trap cannot run until that
returns, so the child cannot exit inside the `-k 10` grace, so the escalation fires **every time**.
`cloud-return.sh:194-205` already states the trap cannot run on SIGKILL; what was missing is that the
SIGKILL is `timeout`'s own.

Live timing agrees. `cloud_return_rc` rows, `~/.claude/autonomy/idl.jsonl`:

```
2026-09-03T09:18:15Z 137   2026-09-03T10:08:11Z 137   2026-09-03T11:01:21Z 137
2026-09-03T09:44:09Z 137   2026-09-03T10:33:01Z 137   2026-09-03T11:37:54Z 137
```

And the same mechanism, at a different bound, on the sibling call: `autonomy-sweep.sh:461` runs
`timeout -k 10 180 bash cloud-refusal-route.sh --sweep` and it is SIGKILLed in the same ticks
(`autonomy-sweep.err.log`, interleaved with the :433 lines). **Two children, two different bounds,
one signature** — which no external argv matcher explains cleanly and the self-kill explains exactly.

## The honest limit on this attribution

I did not read the send out of the kernel. `dtrace` reports *"system integrity protection is on …
DTrace requires additional privileges"* and `ktrace` reports *"must be run as root"*. So what is
proven is: **this mechanism reproduces the exact observed signature, deterministically, in
isolation, and is removed by flipping the one flag that governs group signalling** — and no external
sender is *required* to explain any observation. I cannot prove no external daemon *ever* also fires.

The ONE method that would settle that residue is a kernel signal-send probe naming the sender pid:

```
sudo dtrace -n 'proc:::signal-send /args[2] == 9/ { printf("%d %s -> %d %s", pid, execname, args[1]->pr_pid, args[1]->pr_fname); }'
```

It needs **root (sudo)**, which this session cannot obtain. It is not needed for the verdict above;
it would only close the "also" case. Filed as an operator-runnable step rather than guessed at.

## Corollary — a live misclassification risk, evidenced, NOT fixed here

`scripts/postland-verify.sh:34-35` defines **CUT** as "truncated by a MACHINE event — a peer pkill,
OOM, starvation", and `:2837` states the discriminator in its own words:

> `NOT a cut: no signal reached this run (a peer pkill shows rc>128 / a job-control line).`

That is *exactly* the signature `timeout -k`'s own escalation produces. The classifier therefore
cannot tell "an external peer pkilled us" from "our own bound fired and self-killed the group". The
suite is wrapped in that shape — observed live during this wave:

```
pid 46358  pgid 46358  started 02:06:05  etime 02:50:03
/opt/homebrew/bin/timeout -k 10 10800 nice -n 19 /usr/sbin/taskpolicy -c background bats tests/…
```

This matters because CUT is what keeps `last-green` behind live HEAD and blocks `deploy-live`
(DRAIN_CIRCUIT §W5). **Stated as a risk, not as the established cause of any particular cut** — the
§W5 stamp carries `run_s: 2157`, which is not a 10800 s bound, so that one was something else.
Establishing whether CUT has actually misfired needs the per-run rc, which this wave did not chase.

## What this does NOT license

No bound, limit, timeout, retry or cap is touched by this finding, and none should be. The bound is
not the defect; **the reading of 137 was**. `--foreground` is not a fix either: Arm C shows the child
is still SIGKILLed and the pass still cut — it only stops the blast reaching `timeout` and the group.
The remaining engineering question is unchanged and belongs to W5's deadline: a single `handle()`
unit can exceed the whole remaining budget once started. That is a different problem, with a
different owner, and it is now free of a phantom killer.

---
*Reproduce any arm: the commands above are complete and self-contained. Bystander script written to
`/tmp/w6-pgid-victim.sh` during the run; it is disposable.*
