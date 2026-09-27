# A detached bash process is reaped after ten minutes — detach.sh is necessary, not sufficient

2026-09-27, during the Jev Outlook read-only pass.

**What happened.** The pass's runner, `bash jev_run_when_funded.sh`, was launched through
`scripts/lib/detach.sh`: its own session, pgid equal to its pid, ppid 1. That is everything the
house rule for outliving a tool call asks for. It was killed anyway, at age 3,142 s. A second
detached bash (`bash -c 'while kill -0 <pid>; do sleep 60; done; …'`), started as a follow-up,
was killed at 891 s. Their child, a Python classifier, kept running untouched. Neither death left
anything in the job's own log; the evidence was in `~/.claude/logs/cc-reaper.log`:

    [2026-09-27T19:41:04Z] garbage: TERM orphan-bash pid=96881 age=3142s argv=<bash …/jev_run_when_funded.sh …>
    [2026-09-27T19:58:55Z] garbage: TERM orphan-bash pid=56424 age=891s  argv=<bash -c while kill -0 59477 …>

**Why.** `bin/cc-reaper` runs every 300 s from launchd. Its garbage sweep classifies as
`orphan-bash` any process whose comm is `bash`, that is launchd-parented, older than 600 s, and
whose argv matches nothing in `GARBAGE_WL` (`bin/cc-reaper:710`). A correctly detached long-lived
bash is exactly that shape. Detaching defeats the tool call's group kill; it does nothing about
the reaper. The reaper is right to exist: 374 orphan-bash TERMs sit in the current log, most of
them genuine residue of dead sessions.

**The rule.** A process meant to run unattended for more than ten minutes must not be a bare
bash on this machine. In order of preference:

1. **A launchd job** when it is recurring or must survive reboots.
2. **A non-bash process** (Python, node) for a one-shot wait. The follow-up that replaced the two
   killed ones was a Python script and ran to completion.
3. **A name on `GARBAGE_WL`** only for a genuine house daemon, added in the same commit as the daemon.

And, as with every detached process: **re-check the pid after ten minutes**. A pid that was alive
at launch proves nothing about one that has to live for hours.

**Companion.** Memory `nohup-does-not-detach-from-a-tool-call` (corrected the same day): its 09-20
incident, a bash watcher that vanished "minutes later" with ppid 1, fits this reaper's shape too,
though that attribution was not verified.
