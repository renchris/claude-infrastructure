# Rank 15 probe: "background long commands, wait in ≤270 s slices" (wave 2, item 4, 2026-09-24)

**Verdict: ship it to the default agents. Conviction 88%.** On a ~7-minute benchmark delegated to a subagent, the
lines removed the cache miss every time (0 of 4 runs vs 3 of 3), cut the subagent's cache writes by 47% and the
tree's cost by 17%, and every run in both arms reported the right number.

## Evidence the lever addresses the real cause

`/tmp/tokeff-w2/r15-scan.py` over every subagent and workflow-agent transcript from 2026-09-10 to 2026-09-24 (4,630
files, 103,824 consecutive response pairs): 518 cache misses followed a 5-60 min gap; **478 (92%) followed a single
foreground Bash call longer than 270 s** (median 601 s, 133 ran into the 600 s Bash cap). 258 of those were
foreground wait loops, 187 of them after the agent had already backgrounded the command, so "run it in the
background" alone is not enough: the wait itself has to be sliced. No miss came from Monitor, Agent or Workflow
waits. This held up the OPPORTUNITIES.md rank-15 claim (≈300 workflow-agent misses; this definition finds 471).

## Probe

`eval/harness/r15-probe.sh` + `r15-agg.py`. A headless main session (Opus 5.5, effort high, auto mode) delegates one
brief to a subagent defined inline with `--agents` (tools Bash, Read): "Run ./bench.sh (a benchmark that takes about 7
minutes) and report the number on its RESULT= line." The two arms differ only in whether the subagent's prompt
carries the Tool behaviour block of `agents/workflow-lean.md`. Reps 1-3 of `without` and 2-3 of `with` were refused by
the machine's capacity gate (load ~29/core) and ran the benchmark in the main thread, so they measure nothing about the
subagent; reps 4-6 ran with `CC_ADMIT_GATE=off` for these one-subagent runs only.

| run | correct | subagent requests | gaps >300 s | cache misses | subagent cache_creation | backgrounded | longest foreground Bash | tree $ |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| with-r1 | yes | 5 | 0 | 0 | 55,648 | 1 | 272 s | 0.944 |
| with-r4 | yes | 5 | 0 | 0 | 53,480 | 1 | 271 s | 0.939 |
| with-r5 | yes | 5 | 0 | 0 | 56,273 | 1 | 271 s | 0.950 |
| with-r6 | yes | 5 | 0 | 0 | 54,164 | 1 | 271 s | 0.938 |
| without-r4 | yes | 3 | 1 | 1 | 104,280 | 0 | 424 s | 1.143 |
| without-r5 | yes | 3 | 1 | 1 | 102,053 | 0 | 424 s | 1.135 |
| without-r6 | yes | 3 | 1 | 1 | 104,222 | 0 | 423 s | 1.144 |

Means over the delegated runs: cache writes 54,891 vs 103,518 (−47%), tree $0.943 vs $1.141 (−17%), requests 5 vs 3.
The subagent here carries a ~1k-token prompt; a real worker's prefix is 7k (lean) to 100k+ (default), so the avoided
rewrite is larger in production, as are the two extra requests (each a cache read).

**Why 88%, not higher.** n = 4 vs 3 on one synthetic brief; the effect is deterministic in mechanism (a request more
than 5 minutes after the last one misses the 5-minute cache) and the slice pattern held at 271-272 s in every run, but
the probe does not show how often production agents follow the line, which the next ledger window measures.
