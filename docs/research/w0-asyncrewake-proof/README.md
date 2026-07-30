# W0 probe — durable evidence that `asyncRewake` wakes an idle session

Evidence bundle for the claim in `docs/research/mechanical-wake-asyncrewake-2026-07-29.md` §2, which
falsifies `wake-on-ping-2026-07-26.md` §4's premise *"the harness floor is immovable: only the model can
arm its own watcher."* That premise carried three sessions of design, so the artifact that overturns it
should not live in a session scratchpad — the original citation pointed at
`scratchpad/w0probe/…`, which is reaped with the session. Committed here so the claim stays
independently checkable.

**Ran on:** CC **2.1.219** (`~/.claude-219`), 2026-07-30 ~06:16–06:17 UTC.

| File | What it proves |
|---|---|
| `settings.probe.json` | The exact config under test: a `SessionStart` hook with `asyncRewake: true`, plus `rewakeMessage` / `rewakeSummary`. This was the ONLY hook in a hermetic `CLAUDE_CONFIG_DIR` — no inherited Stop/SessionStart hook could have manufactured a turn. |
| `watcher.sh` | The hook body — a poll loop that prints the new mail line and `exit 2`. Note `nlines()`: `grep -c ''` prints `0` **and** exits 1 on an empty file, so a `\|\| echo 0` fallback yields `base="0\n0"` and every later `-gt` dies as "integer expression expected" — a watcher that can never fire. Found and fixed before the run. |
| `watcher-lifecycle.txt` | Harness-side lifecycle: `START pid=99121` at session birth (so the harness backgrounded it — `asyncRewake` *implies async*), `alive poll=10` 21 s later (it outlives the birth turn), then `FIRE … exiting 2` one second after an external write. |
| `probe-transcript.jsonl` | The subject session's own transcript. Line 13 is the payoff: a **harness-synthesized user turn** carrying `<task-notification><summary>` (from `rewakeSummary`) and a `<system-reminder>` holding `rewakeMessage` + the hook's output. |

## How to read the payoff

```
$ python3 -c "import json;[print(json.loads(l)['message']['content'][0]['text']) \
    for i,l in enumerate(open('probe-transcript.jsonl'),1) if i==13]"
```

The external write was a single `echo >> mail.txt` from an unrelated shell — **zero model
participation**. The subject was idle at its prompt when it happened.

## Two things this bundle also documents

1. **`stderr` is the carried stream; `stdout` is dropped.** `grep -c W0-PROBE-WAKE-STDOUT
   probe-transcript.jsonl` → **0**; the `-STDERR` variant → 2. The watcher deliberately wrote both to
   settle it. Consequence: `mailbox_take` / `cc-await-ping` print the mail body to *stdout*, so wiring
   this as-is would wake a session with an **empty** reminder — a working mechanism that says nothing.
2. **The woken assistant turn is `Not logged in · Please run /login`.** The hermetic config dir had no
   credentials. That is an *orthogonal* failure and does not touch the claim: what was under test is
   whether the harness re-invokes an idle model from an external file write, and it did — the turn
   exists, with the mail body in hand. Anyone re-running this should authenticate the probe config if
   they want to see the model's reply as well as the wake.

## Positive control (why a null result here would have meant something)

The watcher was first run standalone and fed a line: it fired within one poll and exited 2, body on
both streams. So a later null could only have meant "the harness did not wake" — never "the watcher was
broken." Documented-but-inert surfaces are the known failure mode in this repo (Stop
`additionalContext` is documented and empirically dead), which is why this was probed rather than cited.

## One more silent-omission trap, met while committing this bundle

The lifecycle log was originally `watcher.log`, and `.gitignore:11` carries `*.log`. `git add` exited
**0 and simply did not add it** — the commit landed with 4 of 5 files and no error anywhere. Renamed to
`watcher-lifecycle.txt` rather than force-added, because a gitignore entry is intentional. Worth
recording here because it is the same shape as everything this bundle is about: a success exit that
proves a command *ran*, never that the *effect* landed.
