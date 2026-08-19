# exit 144 is not a rare cc-await-ping event — it is 352 measured deaths, 99% of them mid-session

Corrects the premise of backlog row `b38279c10c55` ("capture the sender of cc-await-ping's
group-SIGTERM: **3 fresh exit-144s in one session**"), which rests on
`docs/research/await-ping-exit-144-2026-08-07.md` §5 — *"Two instances, no surviving evidence."*
That doc's mechanism is untouched and still correct; what was wrong is how big the class is, whose
class it is, and therefore how hard the row is. Recycle #51, 2026-08-19. **The row stays OPEN — the
sender is still uncaptured and no recorder was built here.**

## The corrected numbers

Over all four per-account transcript stores, deduped by realpath (6,996 `.jsonl` files):

| | measured |
|---|---|
| distinct exit-144 events (deduped on `task-id`) | **352** |
| …that are **mid-session** (>3 records follow in the same transcript) | **348** |
| …that are terminal (the session ended with it) | 4 |
| …whose task description is a watcher / wake-path arm | **109 (31%)** |
| …other backgrounded work (polls, waits, builds) | 243 |
| rate | up to **42/day**; **17 on the day this was written** |

Three consequences, and the third is the one that changes the work:

1. **It is not primarily a `cc-await-ping` phenomenon.** 69% of these deaths are ordinary
   backgrounded work — `Wait for ship-land to finish`, `Hold and watch for all-clear`, build and
   test drivers. The watcher is the most *visible* victim (its death takes the wake path down and
   says so), not the only one or even the usual one.
2. **The pane-teardown explanation is refuted.** If a group-TERM came from the session's own
   shutdown, the 144 would be the last thing in its transcript. 348 of 352 have a median of **293
   records after them** — the session lived on for hundreds of turns. Whatever sends this signal
   sends it at a *running* session's background task.
3. **The hit does not have to be waited for.** The row is filed as if the sender were unobservable
   because the event is rare — §5's *"Anyone who sees another 144 should capture the sender"* reads
   like advice for a once-a-quarter accident. At ~1 event every few hours on this box, an
   `SA_SIGINFO` recorder armed in **any** backgrounded task's process group will capture an `si_pid`
   within a day. That answers the question that was blocking the row ("how would you prove a
   recorder fires before you build it?") without changing anything about the recorder itself.

Also confirmed, by grepping the tree for `SA_SIGINFO` / `si_pid` / `sigwaitinfo`: **no recorder
exists in the repo.** The only hit is `bin/cc-await-ping`'s own comment saying one would be needed.
The §2 instrument was ad hoc to that investigation and was never landed. Note for whoever builds it:
macOS has no `sigwaitinfo`/`sigtimedwait`, so Python's `signal.sigwaitinfo` is unavailable here and a
compiled `sigaction(SA_SIGINFO)` helper is the only route — which makes it a new file in `bin/`, i.e.
a `LIVE_ADDS` breach until the converger runs.

## Five instruments, four of them wrong, all four reading as a clean answer

Recorded because the failure mode repeated and each wrong answer was *plausible*:

| # | instrument | reading | why it was wrong |
|---|---|---|---|
| 1 | `grep -rl "exit code 144"` over the stores | 215 files | matches transcripts that **discuss** 144 — briefs, backlog rows, this very session |
| 2 | same, on the fuller phrase `failed with exit code 144` | 215 files — *identical* | the fuller phrase is quoted just as often; the identical count was the tell |
| 3 | classify `tool_result` records as events | 1,016 events | a Bash `tool_result` that merely **printed** `bin/cc-await-ping`'s comments is a `tool_result` |
| 4 | count `type=="queue-operation"` records | 627 | right record type, but the notification is written **twice** per event — ~2× inflation |
| 5 | dedupe on `<task-id>` | **352** | the answer |

The discriminator that finally worked is structural, not lexical: the harness's own death report is a
`type="queue-operation"` record with keys `{content, operation, sessionId, timestamp, type}`, and
**quoting cannot forge a record type**. The positive control is what proved it — this session had
displayed the phrase nine times and had suffered no 144, and it carries **zero** `queue-operation`
matches.

A sixth error nearly shipped a wrong headline: testing "is this a cc-await-ping death?" by looking
for `await-ping` in the notification returned **1 of 352**, which reads exactly like "the row's
subject is a non-event". The field is the *operator-written prose description* of the Bash call, so
the real watcher arms are spelled `Arm inbox watcher`, `Re-arm inbox wake watcher`, `Arm inbox
watcher for wake path` — 109 of them. Same law as `pgrep-f-matches-agent-briefs` and
`caller-census-keyed-on-path-misses-the-name`: **the name you search for is not the name the field
holds.**

## What this does not establish

The sender. Nothing here names a culprit — it re-scopes the search and shows the search is cheap. The
two suspects `await-ping-exit-144-2026-08-07.md` §4 names (the harness memory-pressure reaper, and
`cc-reaper`'s garbage arm) are both still untested, and the mid-session finding is *consistent* with
the memory-pressure reaper in a way the teardown story is not — but "consistent with" is not
evidence, and that doc already exonerated the garbage arm for one window only. A recorder is still
the way to get `si_pid`.
