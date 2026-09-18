# W2-0 / T9 — does a Stop hook run when the turn it is ending died with an API error?

The gate on `docs/plans/NONLIMIT_RESUME_LADDER.md` D4 (`net-recover-arm.sh`), carried there as
**👤 ON-BOX ONLY**. That refusal was right for the session that made it: the cloud VM which
implemented D1-D7 ran **2.1.268**, every measurement in the plan is on **2.1.260**, and no second
track was installed there to control against — one arm on one binary is the *oracle is only true at
its measured geometry* error.

## Both arms, and the verdict

**Arm 1 — does a watcher armed EARLIER synthesize a turn after an api-error turn end? YES.**
**Arm 2 — do Stop hooks run AT that boundary? NO.**

**Together: D4 is implementable exactly as § W1.2 specifies it** — arm at SessionStart and at every
prior Stop, idempotently, so the watcher already exists when the death happens. Arm 2 is the reason
that "arm it earlier" clause is load-bearing rather than defensive; arm 1 is the proof that it
works. **T14 (build D4) is unblocked.**

⚠️ **An earlier version of this file, landed as `0dc8ed879`, concluded "D4 as specified is not
implementable."** That was wrong twice over and § The two errors keeps the record: it generalised
arm 2's result to arm 1, and D4 had never proposed arming at the death in the first place. The
sentence was corrected before anything acted on it.

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

## Arm 2 — the four arms, one variable each

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

## Arm 2 — what it does NOT establish

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

## Arm 1 — the hermetic rig, and its result

Arm 1 needs a config dir holding ONLY the hook under test. The merged-`--settings` rig used for
arms A/B/D/E cannot do it: `--settings <file>` **merges with** the live config rather than replacing
it, so the fleet's own Stop hooks run too and a synthesized wake is indistinguishable from a
hook-forced turn — one record in an early attempt is literally
`Stop hook feedback: 🔔 WAKE FLOOR …`. A throwaway `CLAUDE_CONFIG_DIR` answers `Not logged in ·
Please run /login` because auth here is keychain/`oauth-tokens`-backed.

**The unlock: `ANTHROPIC_API_KEY=<any string>` + a local endpoint.** With a dummy key the client
takes the API-key path and reaches the API layer normally, and `mockapi.py` then answers
`/v1/messages` in two modes — a valid SSE assistant turn, or HTTP 400 with an `api_error` body. So
the whole arm is hermetic: **no credentials, no quota, and nothing but the hook under test can
manufacture a turn.** That last clause is the property the merged rig lacked, and it is what makes
the stream readable.

| arm | mock mode | how the first turn ended | watcher | stream records |
|---|---|---|---|---|
| **H** control | `ok` (valid SSE) | normally, assistant said `OK` | `WATCHER-FIRE … exiting 2` at 01:33:13 | **4 → 8** |
| **I** test | `error` (400, `api_error`) | `API Error: 400 {"type":"error","error":{"type":"api_error"…}}` | `WATCHER-FIRE … exiting 2` at 01:34:20 | **4 → 8** |
| **J** test, repeat | `error` | same | `WATCHER-FIRE … exiting 2` at 01:35:31 | **4 → 8** |

The four records the wake adds are identical in all three: `system/hook_response` (the watcher's
`exit 2`), then `system/init`, `assistant`, `result` — **a second turn ran**. The test arms match
the control exactly, so an api-error turn end does not suppress the wake.

In I and J that synthesized turn immediately hits the mock's 400 again, because the mock never
recovers. That is an artefact of the fixture, not of the mechanism: the question is whether the turn
was SYNTHESIZED, and it was. In the case D4 exists for, the network has come back by then — which is
what the watcher was waiting to observe.

## The two errors, kept because they are the transferable part

**1. I wrote a conclusion broader than my arms.** W2-0 has two arms and the plan names both in
W2-0's own row; I ran arm 2 and wrote arm 1's verdict on top of it. Worse, § W1.2's hazard table
already carried the row `nothing can be armed at the death` with the remedy *"D4 arms at SessionStart
and at every PRIOR Stop, idempotently — it must already exist when the death happens"* — so the
design had anticipated arm 2's result before I measured it, and I had that table open. **When a probe
has a named arm you did not run, that belongs in the verdict line, not in a caveat below it.**

**2. I fed the mailbox from inside the driver that truncates the mailbox.** An early arm-G driver did
`: > mail.txt` and then backgrounded its own feeder; the two raced and every run ended with an empty
mailbox — a state in which the watcher *could not* have fired. Read naively that null says "the
harness refused to wake". It is a verdict about my driver. `../w2-stop-rewake-proof/`'s README says
to feed from an unrelated shell, and I had read it. `drive3.sh` takes the mail path as a per-arm
file and never truncates it after arming.

**3. Two arm-C runs were discarded for being KILLED rather than ending** — see § Two arms DISCARDED
above. Same family as (2): a process that never reached its verdict, whose evidence file is
byte-identical to a real negative.

## What follows for D4 (T14)

Build it as specified. `hooks/net-recover-arm.sh`, `asyncRewake`, declared on **SessionStart** (and
re-armed at every Stop, idempotently, via the claim-guard pattern in `hooks/mailbox-wake-arm.sh` —
the W2 probe's P-W2c result is that the harness dedupes nothing, so only the hook can decline). Its
body waits on the condition W1.2 names — `[api-error ∧ turn_duration ∧ 2 greens]` — and exits 2 to
wake. Registration is a c10 migration (the `0007`/`0012`/`0026`/`0029` pattern), staged for the
operator.

## Reproducing

`docs/research/w2-0-api-error-stop-proof/` holds every file as run.

**Arm 2** (Stop-hook absence): `syncstop.sh`, `watcher.sh`, `settings.probe.json`, `drive.sh`,
`mock400.py` / `mock500.py`, and each arm's `stop.arm*.txt` / `watch.arm*.txt` / stream, including
the two discarded C runs.

**Arm 1** (the wake): `drive3.sh` + `mockapi.py` — fully hermetic, one command per arm and no
credentials:

```
bash drive3.sh H ok    8801 100    # control — the mock serves a valid turn
bash drive3.sh I error 8802 150    # test    — the mock returns an api_error
# then, from an UNRELATED shell while the session idles:
echo "mail" >> mail.I.txt
```

`watch.<arm>.txt` records the watcher; `stream.<arm>.jsonl` goes from 4 records to 8 when the wake
lands. `drive2.sh` and `settings.probe.sessionstart.json` are the superseded merged-config rig, kept
only because their failure mode (§ The two errors) is the reusable part.
