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

## The arm-1 rig — hermetic, and it answered

`drive3.sh` + `mockapi.py` are the rig for W2-0's FIRST arm: the watcher declared on **SessionStart**
so it is armed before the turn that dies, then mail fed from an unrelated shell while the session
idles.

**It is hermetic, and that is the whole trick.** A throwaway `CLAUDE_CONFIG_DIR` holding only the
hook under test is what makes the stream readable — but it has no credentials here (keychain /
`oauth-tokens`), so it answers `Not logged in`. `ANTHROPIC_API_KEY=<any string>` plus `mockapi.py`
on `ANTHROPIC_BASE_URL` fixes that: the client takes the API-key path, the mock answers
`/v1/messages` either as a valid SSE turn (`ok`) or as HTTP 400 with an `api_error` body (`error`),
and **no credential and no quota are involved at all**.

```
bash drive3.sh H ok    8801 100    # control
bash drive3.sh I error 8802 150    # test
echo "mail" >> mail.I.txt          # from an UNRELATED shell, while it idles
```

`stream.arm{H,I,J}.jsonl` go from 4 records to 8 when the wake lands — `hook_response`, `init`,
`assistant`, `result`. Identical in the control and both test runs: **an api-error turn end does not
suppress the wake.**

`drive2.sh` and `settings.probe.sessionstart.json` are the SUPERSEDED merged-config rig, kept only
for their failure mode: `--settings <file>` MERGES with the live config rather than replacing it, so
the fleet's own Stop hooks ran and forced turns of their own — one record reads
`Stop hook feedback: 🔔 WAKE FLOOR …`. A synthesized wake and a hook-forced turn are then the same
thing in the stream. That is why arm 1 needs its own config dir and not an overlay.

**Do not re-derive the feeder bug.** An earlier `drive2.sh` fed the mail from inside itself, racing
its own `: > mail.txt`, so every run ended with an empty mailbox — a state in which the watcher
*could not* fire, whose null reads exactly like "the harness refused to wake". `drive3.sh` takes a
per-arm mail file and never truncates it after arming.
