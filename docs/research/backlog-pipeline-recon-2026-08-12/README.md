# Backlog pipeline recon — 2026-08-12

Five read-only recons, run concurrently, that produced the diagnosis behind
`docs/plans/BACKLOG_SELF_DRAINING_2026-08-12.md` and commits `c221caa58` / `39388b17d`.
Preserved verbatim because the plan carries the *conclusions* and these carry the **file:line anchors,
the measured distributions, and the adversarial passes** — the parts a successor would otherwise
re-derive from scratch.

| file | question it answers | the finding that mattered most |
|---|---|---|
| `recon-staleness.md` | how does an item go stale, and what re-validates it? | `run_falsifier` has ONE call site, reached only on claim; **205 of 327 live rows have never been claimed**, and `cc-premise sweep` / `screen --all` have **zero callers** |
| `recon-consolidation.md` | the pile was consolidated once — why is it still 536? | the pile is **93–95% genuinely distinct**; a fold removes **zero** rows by design; the only thing that ever reduced it (`prune.py`/`link.py`) is **untracked** |
| `recon-cloud.md` | can backlog work run end-to-end in Claude Cloud today? | it does — and it **wedged the dispatcher**: `live_workers()` had no venue predicate, and `cc-cloud retire` had zero callers |
| `recon-bottleneck.md` | what actually consumes the "15 sessions"? | there is no 15; the bind is **load 2.0/core**, enforced UNBOUNDED on the operator's own path and **OFF for the Agent tool** |
| `recon-wave.md` | can one session work a whole backlog for days? | calendar time is not the limit — **cumulative context** is; `Prompt is too long` is the only 100%-fatal class, and teammate-leads peak 1.6× dispatch-leads |

## Read these with two caveats

**Every number has a date and this repo's figures decay fast** — published p95s here have gone stale
inside 36 hours. Re-derive before quoting; each doc names the command it used.

**One finding in `recon-staleness.md` was corrected by measurement after it was written.** It reports
`--fold` as timing out (rc 124, 10/10 runs) and infers the bound is too small for the work. The bound
was too small *for the band*: the fold completes in 17.5 s foreground / 20.3 s utility and only
overruns at **68.1 s** in the Background QoS band launchd actually gives it. The correction matters
because it inverts the remedy — raising the timeout made the sweep **3.6× faster**, not slower
(94.1 s → 26.0 s per sweep), since the fold was never approaching that ceiling, it was dying at it.
See the plan's BAND section.
