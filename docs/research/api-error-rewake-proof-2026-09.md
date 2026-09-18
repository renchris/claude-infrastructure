# W2-0 / T9 — does a Stop hook run when the turn it is ending died with an API error?

The gate on `docs/plans/NONLIMIT_RESUME_LADDER.md` D4 (`net-recover-arm.sh`), carried there as
**👤 ON-BOX ONLY**. That refusal was right for the session that made it: the cloud VM which
implemented D1-D7 ran **2.1.268**, every measurement in the plan is on **2.1.260**, and no second
track was installed there to control against — one arm on one binary is the *oracle is only true at
its measured geometry* error.

**Answer: NO.** On a turn whose end is an API error, the Stop hook chain does not run at all. An
`asyncRewake` hook therefore cannot ARM at that boundary, and **D4 as specified — arm the recovery
watcher at the api-error turn end — is not implementable.** The plan's own stated fallback, the desk
sweep writing to the session mailbox, is what D4 must be. Nothing already landed depended on the
other answer.

**Ran on:** Claude Code **2.1.114** (`~/.claude/bin/claude-latest`, the fleet's pinned stable),
2026-09-17, macOS, model `claude-haiku-4-5-20251001`. The probe is about the harness, not the model.

**Cost: two haiku turns.** Both failing arms point `ANTHROPIC_BASE_URL` at a local endpoint and
spend no quota at all; only the two controls reach the real API.

**Hermetic, and the live config is never touched.** The two probe hooks are declared in a throwaway
settings file passed with `--settings` — `settings.json` is C10 and is not edited to run an
experiment. cwd is a scratchpad dir, and `--strict-mcp-config` keeps servers out.

## The instrument

Two Stop hooks, declared together:

- `syncstop.sh` — a plain **synchronous** Stop hook. Logs one line at START, exits 0. This alone
  answers the question: did the chain run?
- `watcher.sh` — the **asyncRewake** hook, copied in shape from
  `docs/research/w2-stop-rewake-proof/watcher.sh`, which proved the wake mechanism at a normal Stop.

Both log at START and never only at exit: an exit-time log cannot separate "never started" from
"started then reaped" (W0's rule). Both log their arm label, which is what makes the negative
readable — see § The contamination I had to design around.

## The four arms — one variable each

| arm | shape | endpoint | how the turn ended | `syncstop` | `watcher` |
|---|---|---|---|---|---|
| **A** control | `-p` headless one-shot | **real API** | normally | **FIRED** | **STARTED** |
| **D** control | `--input-format stream-json`, stdin held open | **real API** | normally | **FIRED** | **STARTED** |
| **B** test | `-p` headless one-shot | `127.0.0.1:9`, connection refused | `API Error: Unable to connect to API (ConnectionRefused)` · `terminal_reason:"completed"` · 176508 ms | **SILENT** | **SILENT** |
| **E** test | `--input-format stream-json`, stdin held open | local server answering **HTTP 400** with an `api_error` body | `api_error_status:400` · `result:"API Error: 400 {…\"type\":\"api_error\"…}"` · 276 ms | **SILENT** | **SILENT** |

Verbatim control output — this is what the failing arms do not have:

```
A: 01:16:33 SYNC-STOP-FIRED pid=70353 arm=A
   01:16:33 WATCHER-START   pid=70355 ppid=66326 arm=A
D: 01:21:50 SYNC-STOP-FIRED pid=29764 arm=D
   01:21:50 WATCHER-START   pid=29761 ppid=25118 arm=D
```

Arm B's own result record:

```
"result":"API Error: Unable to connect to API (ConnectionRefused)",
"num_turns":1,"terminal_reason":"completed","duration_ms":176508
```

`terminal_reason:"completed"` is the load-bearing detail. The harness considers the turn FINISHED —
not hanging, not crashed, not mid-retry — and still runs no Stop hook. `grep -c 'arm=B' stop.log`
and `grep -c 'arm=E' stop.log` are both **0**; the same greps for `arm=A` and `arm=D` are both 1.

## Why two failing arms and not one

Arm B refuses the TCP connection, which a client may classify **earlier** and differently than an
`api_error` returned by a server that actually answered — so B alone cannot distinguish "an api
error does not reach Stop" from "a transport failure never becomes a turn at all". Arm E closes
that: the endpoint is reachable, speaks HTTP, and returns an `api_error` body that the harness
surfaces as `api_error_status: 400`. Same silence, from the opposite end of the error space, in the
interactive shape.

## Two arms DISCARDED, and why either would have been a false positive

An arm C — a reachable endpoint returning **500** — was run twice and thrown away both times. 500 is
**retryable**, and the harness's ladder is `max_retries: 10` with exponential backoff (measured
delays 1, 2, 4, 9, 18, 37, 75 s … — the stream records them as
`{"type":"system","subtype":"api_retry","attempt":N,"max_retries":10,"error_status":500}`). Both
runs were **killed mid-ladder** by my own timeout (exit 144, at attempts 6 and 7 of 10). A killed
process is not an api-error turn end, and reading its empty `stop.log` as "no Stop hook fired" would
have been a conclusion about my timeout wearing the evidence's clothes — the two discarded runs
produce byte-identical log files to the kept ones. Arm E replaces C by making the error
**non-retryable**, so the turn ends on its own in 276 ms. Arm B is the slow-path companion that did
exhaust naturally, in 176 s.

## The contamination I had to design around

Arm D's `asyncRewake` watcher polls for 80 s after it starts. I rotated the log files between arms
while that watcher was still alive, so its `WATCHER-TIMEOUT` line landed in the NEXT arm's file. A
reader counting lines would see a watcher entry in a failing arm's log and conclude the hook fired.
It did not — that is D's watcher finishing. This is why every START line carries `arm=`, and why the
verdict above is stated as `grep -c 'arm=<X>'` rather than as "the file is empty".

## What this does NOT establish

1. **One binary.** 2.1.114 only. The plan's measurements are 2.1.260 and the implementing VM was
   2.1.268. This repo's rule is that a disagreement between binaries is not evidence about VERSIONS
   until both arms are run — so this is a fact about 2.1.114, which happens to be the binary most
   sessions on this fleet actually run. **Re-run both arms on 2.1.260+ before treating the answer as
   fleet-wide.** The reproduction is one command per arm.
2. **`--max-turns 1` on every arm.** A turn dying on an api error with turns remaining may reach a
   different path. The controls carry the same flag, so it cannot explain the difference BETWEEN
   arms, but it bounds what "an api-error turn end" means here.
3. **It says nothing about the WAKE half.** `docs/research/w2-stop-rewake-proof/` already proved an
   armed `asyncRewake` hook's `exit 2` synthesizes a turn at a normal Stop. This probe shows the
   hook never gets the chance to arm after an api error. Two different claims; both were needed.

## What follows for D4

- **The desk sweep is the design.** An external observer reads each session's transcript for the
  api-error tail (`lr_last_api_error`, already built and tested — `tests/lr-audit-nonlimit.bats`
  29/29) and writes the session mailbox, which `mailbox-wake-arm` (migration `0007`, `asyncRewake`
  on **SessionStart** — not Stop) already wakes. Nothing new has to be discovered; it is composition
  of parts that exist.
- **D3 covers the other half and never depended on this answer.** `hooks/recover-inject.sh` fires on
  `UserPromptSubmit`, so the moment anything prompts the session — the operator, or the harness's own
  `<task-notification>` wake — the audit instruction arrives.

## Reproducing

`docs/research/w2-0-api-error-stop-proof/` holds every file as run: `syncstop.sh`, `watcher.sh`,
`settings.probe.json`, `mock500.py` / `mock400.py` (the reachable endpoints), `drive.sh` (the
streaming-json driver that holds stdin open across the turn end), and each arm's logs and streams,
including the two discarded C runs.
