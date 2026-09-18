# Files as run — W2-0 / T9

The verdict and the reasoning are in `../api-error-rewake-proof-2026-09.md`. This directory is the
evidence, committed as run rather than tidied, following `../w2-stop-rewake-proof/`'s convention.

| file | what it is |
|---|---|
| `syncstop.sh` | the SYNCHRONOUS Stop hook — the whole question ("did the chain run?") |
| `watcher.sh` | the `asyncRewake` Stop hook, shaped after `../w2-stop-rewake-proof/watcher.sh` |
| `settings.probe.json` | the throwaway settings passed with `--settings`; the live `settings.json` is never edited (C10) |
| `drive.sh` | the driver for the interactive arms — streaming-json stdin **held open across the turn end** |
| `mock400.py` / `mock500.py` | reachable local endpoints answering `/v1/messages` with an `api_error` body |
| `stop.arm*.txt` · `watch.arm*.txt` | one line per hook START, each carrying `arm=` |
| `stream.E.jsonl` · `result.armB.json` | the harness's own records for the two failing arms |
| `stream.armC1-killed.jsonl` · `stream.armC2-killed.jsonl` | the two DISCARDED arm-C runs, kept because they are the trap |

**Paths inside `syncstop.sh`, `watcher.sh` and `settings.probe.json` are the absolute scratchpad
paths of the run** — a hook subprocess is not guaranteed to inherit our env, so they were written
literally (same reason the sibling probe's are). To re-run, regenerate them against a fresh
scratchpad dir; `drive.sh` needs no edit, it resolves its own directory.

**Read the logs with `grep -c 'arm=<X>'`, never by whether a file is empty.** Arm D's `asyncRewake`
watcher polls for 80 s, so when the logs were rotated between arms its `WATCHER-TIMEOUT` line landed
in the next arm's file. The `arm=` label on every START line is what makes the negative readable;
`../api-error-rewake-proof-2026-09.md` § The contamination I had to design around has the detail.

**Two arms are DISCARDED and that is deliberate.** Arm C used a retryable 500, whose ladder is
`max_retries: 10` with exponential backoff; both runs were killed mid-ladder by the driver's own
timeout (exit 144, at attempts 6 and 7). A killed process is not an api-error turn end, and its
empty `stop.log` is byte-identical to a real negative — which is exactly why the runs are kept here
rather than deleted. Arm E replaces them with a NON-retryable 400, which ends the turn in 276 ms.

**Why the hook logs are `.txt` and not `.log`.** This repo gitignores `*.log`, so committing them
under their natural name needs `git add -f`, which the global rules forbid — a gitignore entry is
intentional. `../w2-stop-rewake-proof/` reached the same place (`phaseB-lifecycle.txt`).
