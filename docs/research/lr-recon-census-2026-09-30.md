# lr-reconciler census: which failure read 0 claude processes (W7a step 0, 2026-09-30)

## Verdict

The zero census was a **failed ps read**, not a matcher miss. Every recorded instance carries
`degraded: ps`: `observe.read_ps` raised, and `observe()` returned an empty `Snapshot`
(`procs`, `panes`, `sessions` all empty). ps returning rows in which no claude process was
recognised would have shown `degraded: none` with panes and sessions still populated. No
instance of that shape was found.

Whether ps **timed out** or **exited non-zero** is not recoverable. The old code recorded neither:
`observe()` swallowed the exception, a degraded pass wrote no event to `recon/events.jsonl`, and
`shadow/last-pass.json` is overwritten every pass.

## Evidence

| When | Load (1-min, 10 CPUs) | Census | Source |
|---|---|---|---|
| 23:56 on the audit's clock (2026-09-29 night) | ~87-116 | `0 claude procs … degraded: ps` | backlog audit, `claude-private/docs/research/backlog-audit-2026-09-30/systemic-findings.md` (ci-01) |
| 2026-09-30 ~18:53Z | 135-174 | `38 claude procs · 28 panes · degraded: none` | `shadow/last-pass.json`, read live |
| 2026-09-30 19:09:06Z | 344 | `0 claude procs · 0 panes on 0 kitty sockets · 0 sessions · degraded: ps`, `open 8`, `defects 5` | `shadow/last-pass.json`, read live |

- The degraded pass did not stop. Under the old code `run_pass` ran every stage over the empty
  snapshot. In the 19:09Z pass it wrote 4 `in-flight-expired` events at 19:08:58-19:09:01Z
  ("IN-FLIGHT 600s with no holder for the sid → ESCALATED", sids 46d14e14, 68691067, c28362b6,
  c8c2adc0) and 20 `RECON-DEFECT` events. A `ps` read at 19:10Z found all four sessions alive:
  their `claude` processes had been running for 3 h 23 m to 11 h 52 m, each under its
  `lr-fire-resume.sh` launcher. The verdicts were made on an empty world. Mode was `observe`, so
  nothing was typed or moved; in `act` mode the same pass would also have run wakes, release and
  dispatch.
- Escalations of the same four sids at 18:57Z and 19:03Z cannot be tied to a degraded pass,
  because those passes left no record of their census. Treat them as unattributed.
- `recon/events.jsonl` begins at 07:09Z on 2026-09-30, so nothing from the audit's 23:56 pass
  survives in it.
- The ps call itself is fast when it works. The reconciler's exact argv
  (`/bin/ps -axww -o pid=,ppid=,stat=,lstart=,args=`, `TZ=UTC LC_ALL=C`) took 0.8-1.2 s for
  ~2,520 rows at load 174, run in the foreground. At 19:12Z, load 339, three minutes after the
  degraded pass, it took 0.74-0.95 s for ~2,590 rows, and the reconciler's own next pass read
  38 claude procs again. The per-user process ceiling is not the cause either: 1,481 processes
  against `kern.maxprocperuid` 10,666. The reconciler runs at PRI 20 (launchd,
  `/usr/bin/python3` 3.9.6, no `taskpolicy` demotion), so a 20 s timeout is not ordinary
  slowness. The failure is episodic and co-occurs with extreme load (the backlog master also
  recorded wired kalloc at 14.75 GB that day). A longer bound alone cannot be trusted to fix it,
  which is why the abstain is the primary fix and the retry is secondary.
- The watchdog killed the reconciler at 15:06:26Z ("progress=51703 unchanged 185s"). That is a
  wedged pass, not an empty census, and it is out of W7a's scope.

## What W7a changed (for the reader of this note)

- `observe.untrusted()` makes one verdict for the pass. It returns a reason when ps is degraded,
  when ps sees fewer than half as many claude processes as kitty shows claude-foreground panes,
  or when the count falls from 8 or more to under a quarter of the previous pass's reading.
  `run_pass` checks it before any stage that decides anything, and on a reason calls `_abstain`:
  one `abstain` event naming the reason and the streak, the readout line
  (`… · census abstained, no decisions: <reason>`), and `last-pass.json` with an `abstain` field.
  Records, requests and ctl files are left for the next pass.
- `read_ps` bounds each call at `20 s × (1 + load-per-cpu / 10)`, capped at 40 s. Each call gets
  one retry, and all calls share a 90 s budget, which keeps the pass well inside the watchdog's
  180 s stall window. A failure now carries its reason (`timed out at 40s`, `exited 1`,
  `no rows`) into `Snapshot.degraded_why["ps"]` and so into the abstain event. A pass the retry
  saved says `ps took 2 tries` on its census line.
- Residual: a collapse is abstained once. The next pass compares against the collapsed reading,
  so a real mass exit costs one pass. The same comparison means a persistent matcher miss with
  kitty also blind would be believed from the second pass on. The kitty witness still holds
  whenever kitty answers.
