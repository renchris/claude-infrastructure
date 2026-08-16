# W2 probe — durable evidence that a **Stop**-declared `asyncRewake` hook wakes an idle session

The gate on `docs/research/goal-safe-2way-comms-2026-08-13.md` §5 (build-list B1, backlog
`62e0b88a58b5`), which W2's registration (B2, `3118d712f668` → `migrations/0012-…`) is not allowed to
land without. §5's own words: *"Until it passes, W2 stays unbuilt — a documented-but-inert surface is
this repo's most-measured trap."*

**Why it could not be cited from W0.** `docs/research/w0-asyncrewake-proof/` proved the mechanism on
**SessionStart**. On **Stop**, `exit 2` is overloaded — it is also Stop's own *block* code — so the
one thing W2 needs (an idle session woken, not a retroactive blocking error) is precisely the thing
W0 says nothing about. The A4 dispatch gate *looks* event-agnostic in the binary, and that reading
turned out to be right, but "looks right in a decompiled bundle" is the citation this repo has been
burned by before.

**Ran on:** CC **2.1.233** (`/opt/claude-code/bin/claude`), 2026-08-16 ~09:41–09:53 UTC, on a Linux
worker. Model `claude-haiku-4-5` — the probe is about the harness, not the model.

**Hermetic.** `CLAUDE_CONFIG_DIR` was a throwaway dir holding **one** hook (two in phase C), cwd was
a throwaway dir with no project settings and no `CLAUDE.md`, and `--strict-mcp-config` kept servers
out. Nothing but the hook under test could manufacture a turn.

## The four questions and their answers

| | Question | Verdict | Where to see it |
|---|---|---|---|
| **P-W2a** | Is a Stop-declared `asyncRewake` hook dispatched ASYNC — stop neither blocked nor delayed? | **YES** | `phaseB-lifecycle.txt`: `START` at 09:53:04, and the turn's `result` lands 4 s after the prompt with a **600 s** watch registered. A sync dispatch could not have returned for ten minutes. |
| **P-W2b** | Does its `exit 2` while the session is idle synthesize a WAKE rather than a Stop blocking error? | **YES** | `phaseB-transcript.jsonl` **line 13** — a harness-authored *user* turn carrying `<task-notification><summary>` (from `rewakeSummary`) and a `<system-reminder>` holding `rewakeMessage` + the hook's output. The woken turn's own result record in `phaseB-stream.jsonl` reads `"origin": {"kind": "task-notification"}`. |
| **P-W2c** | Idempotency — does a second Stop launch a second watcher? | **IT DOES** — the harness dedupes nothing | `phaseB-lifecycle.txt`: a second `START` (pid 9327) 5 s after the first one fired. In phase C both watchers survived to the same mail line: `phaseC-stream.jsonl` carries **two** `exit_code: 2` hook responses and **two** `origin.kind = task-notification` results — two model turns for one message. |
| **P-W2d** | Does a same-Stop `decision:"block"` from an ordinary shell hook interact with it? | **NO — they coexist** | `phaseC-lifecycle.txt`: `BLOCKER fired` and the watcher's `START` at the same second (09:43:37); `phaseC-stream.jsonl` shows the block forcing its extra turn (`PROBE-TURN-2`) *and* the watcher waking later. |

**The external write was a single `echo >> mail.txt` from an unrelated shell — zero model
participation.** The subject was idle when it happened, both times.

## What P-W2c means for the registration

It is the reason `migrations/0012` refuses to register unless `hooks/mailbox-wake-arm.sh` carries the
claim guard, and the reason the guard lives in the hook rather than in the settings entry: **only the
hook can decline.** A Stop registration without it accumulates one watcher per idle boundary and
spends one model turn per accumulated watcher on the same mail — turning the mechanism that is
supposed to make idleness cheap into a turn-burner.

## The stream rule holds on Stop too

`grep -c W2-PROBE-WAKE-STDOUT phaseB-transcript.jsonl` → **0**; the `-STDERR` variant → **3**. Both
streams *are* recorded in the `hook_response` telemetry (see `phaseB-stream.jsonl`), but the text
carried into the model's turn is stderr. `zZf` composes it as `` `${rewakeMessage} ${stderr||stdout}` ``
— stderr preferred, stdout only as a fallback when stderr is empty — which is a slight refinement of
W0's "stdout is dropped", and does not change the adapter's obligation to print the mail body on
stderr.

## The static reading, recorded because it agreed

Both halves of the mechanism are event-agnostic in the 2.1.233 bundle, which is why this worked:

- dispatch: `let F = !xn() || Vcn(); if ((e.async || e.asyncRewake && F) && !f) { … backgrounded … }`
  — `f` is `forceSyncExecution`, passed `true` only on the `--init`/maintenance session-start path,
  and the hook **event** is never consulted. A backgrounded hook returns `{status: 0,
  backgrounded: true}` and the caller yields `outcome: "success"`, so it cannot block a Stop.
- wake: `zZf({… asyncRewake, rewakeMessage, rewakeSummary …})` fires `np({… mode:
  "task-notification", priority: "next"})` on `code === 2`. The `hookEvent` it receives is used for
  telemetry only.

## Cost this probe found, and did not hide

`flushPendingAsyncRewakeHooks` makes a **headless** run await pending rewake hooks at exit, bounded
by a 30 s race. A watcher armed at Stop is such a hook, so a streaming-input headless session can pay
up to 30 s on teardown. Plain `claude -p` one-shots are unaffected — the adapter's headless guard
skips them outright — and migration `0007` already carries the identical exposure from birth, so W2
adds another boundary at which the same one watcher exists, not a new class of cost.

## Reproducing

`watcher.sh` (the asyncRewake body) and `blocker.sh` (phase C's synchronous `decision:"block"` hook,
marker-guarded so it can never loop) are committed as run, with their `P=` paths pointing at the
throwaway probe dir. `settings.probe.phaseB.json` / `settings.probe.phaseC.json` are the exact
configs under test. The drivers fed a streaming-json stdin kept open across the wake — an idle
session with a live input stream is the state W2 is for.

**Positive control first, as W0 requires.** `watcher.sh` was run standalone and fed a line before any
harness was involved: it fired within one poll and exited 2, body on both streams. So a null result
could only have meant "the harness did not wake", never "the watcher was broken".

## One thing the probe found that is not about Stop at all

`mailbox_wake_armed` — the SSOT wake-path predicate the claim guard is built on — was returning
**NOT ARMED over a live watcher** on this Linux worker, because `stat -f %m` is BSD *mtime* and GNU
*--file-system*: the macOS-first idiom exits 0 on Linux printing an inode report, and the digit guard
reads it as epoch 0. Fixed in `hooks/lib/mailbox-pending.sh` (`_mbx_mtime`, GNU flag first because
its wrong-platform behaviour is an *error* rather than a success) in the commit before this one;
51 further call sites carry the same idiom (`grep -rn 'stat -f %m' hooks/ bin/ scripts/`) and are
**not touched and not yet in the backlog** — this worker had no reachable `cc-backlog` store, so the
follow-on is named here and in the lib comment rather than filed. Two of them have live suite reds
behind them on Linux: `hooks/session-continue.sh:328` (wake-floor 27/28) and `bin/cc-idl:52`
(ttl-lock-owner-token 7). Unnoticed until now because the fleet is macOS — but the cloud workers are
not, and this is the predicate they use to decide whether a peer can be woken at all.
