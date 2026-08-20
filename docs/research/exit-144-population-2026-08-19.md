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

## UPDATE 2026-08-19 (recycle #53) — the recorder needs NO compiled binary, and the suspect list is shorter than both docs say

Three corrections, each measured. The row (`b38279c10c55`) stays OPEN — the recorder is designed and
proven but not yet wired — and the remainder is named at the foot of this section.

### 1. The stated build constraint is FALSE: pure-python `ctypes` reaches `SA_SIGINFO` on macOS

The section above concluded that because macOS ships no `sigwaitinfo`/`sigtimedwait`,
`signal.sigwaitinfo` is unavailable and **a compiled `sigaction(SA_SIGINFO)` helper is the only
route** — which forces a NEW FILE in `bin/`, i.e. a `LIVE_ADDS` breach at a lag of 1, the single
thing that made this row expensive.

That inference is wrong. `signal.sigwaitinfo` being absent says nothing about `sigaction`, which
`ctypes` can call directly, passing a `CFUNCTYPE` handler that receives the `siginfo_t *` and reads
`si_pid` out of it. Measured twice on this box, both captures naming the true sender:

| Shape | Signal delivery | Captured |
|---|---|---|
| group TERM (`kill -TERM -<pgid>`) — the 144 shape | recorder in the victim group | `sig=15 si_pid=82922 si_uid=501 si_code=0` — the driver shell, exactly |
| single-pid TERM (`kill -TERM <pid>`) — the 143 shape | recorder is the target | `sig=15 si_pid=33361 si_uid=501 si_code=0` — this shell, exactly |

Two properties matter for the wiring: the Darwin `sigset_t` is a bare `uint32` (so `struct sigaction`
is `{handler, uint32 mask, int flags}`, not the glibc layout), and the `CFUNCTYPE` thunk **must be
held in a live variable** or ctypes frees it and the handler segfaults on delivery.

Reference implementation — this is the verified probe, not a sketch; both captures above came from
it. No build step, no toolchain:

```python
import ctypes, ctypes.util, os, signal
libc = ctypes.CDLL(ctypes.util.find_library("c"), use_errno=True)
SA_SIGINFO = 0x0040

class SIGINFO(ctypes.Structure):            # Darwin sys/signal.h
    _fields_ = [("si_signo", ctypes.c_int), ("si_errno", ctypes.c_int),
                ("si_code", ctypes.c_int),  ("si_pid",   ctypes.c_int),
                ("si_uid", ctypes.c_uint),  ("si_status", ctypes.c_int),
                ("si_addr", ctypes.c_void_p), ("si_value", ctypes.c_void_p),
                ("si_band", ctypes.c_long), ("__pad", ctypes.c_ulong * 7)]

class SIGACTION(ctypes.Structure):          # sigset_t is a bare uint32 on Darwin
    _fields_ = [("sa_handler", ctypes.c_void_p), ("sa_mask", ctypes.c_uint32),
                ("sa_flags", ctypes.c_int)]

HANDLER = ctypes.CFUNCTYPE(None, ctypes.c_int, ctypes.POINTER(SIGINFO), ctypes.c_void_p)

def _on_term(signo, info, _ctx):
    i = info.contents
    with open(OUT, "a") as fh:              # append + fsync: we are already dying
        fh.write(f"sig={i.si_signo} si_pid={i.si_pid} si_uid={i.si_uid} si_code={i.si_code}\n")
        fh.flush(); os.fsync(fh.fileno())
    os._exit(0)

_KEEP = HANDLER(_on_term)                   # MUST outlive the call — ctypes frees the thunk otherwise
act = SIGACTION()
act.sa_handler = ctypes.cast(_KEEP, ctypes.c_void_p)
act.sa_mask, act.sa_flags = 0, SA_SIGINFO
assert libc.sigaction(signal.SIGTERM, ctypes.byref(act), None) == 0
```

**Consequence: the recorder can live INSIDE an already-symlinked file, so `LIVE_ADDS` stays 0.**

### 2. `cc-reaper`'s garbage arm is excluded by MECHANISM, not merely "for one window"

This doc says the 08-07 doc "already exonerated the garbage arm for one window only". That
undersells it, and the difference decides whether the suspect is worth re-testing. §4 gives a second,
**window-independent** ground: the arm "kills a single positive pid, not a group, so it cannot
produce a 144 at all". Re-derived in the code today rather than taken on trust —
`bin/cc-reaper:485` is `kill "-$sig" "$pid"`, and the candidate loop guards
`case "$pid" in *[!0-9]*) continue ;;`, so the target is always a validated positive integer. A
negative target is unreachable from that arm. `cc-await-ping` is whitelisted there besides.

The memory-pressure reaper is likewise excluded by §3 on a ground independent of timing: it reports
through `nFs(…,"killed",…)`, whose text is `"<desc>" was stopped`, **not** `failed with exit code N`.
Every event in this population is an exit *code*. "Mid-session is consistent with a pressure reaper"
remains true and remains not evidence — but it is arguing against a hypothesis §3 already excluded on
the message shape.

So: **neither named suspect is live.** Treat the sender as unidentified rather than as one of two.

### 3. The repo has no group-kill site — re-derived with an instrument that can actually answer

`await-ping-exit-144-2026-08-07.md` §5 asserts this. It is TRUE, but grep cannot establish it and a
grep that looks like it did is the trap here: `kill -0 "$p"` (signal 0) is regex-indistinguishable
from a negative target, and this repo *discusses* `` `kill -0` `` on several hundred comment lines, so
a naive pattern returns ~60 hits that are all prose. Re-derived by stripping comments and quoted
spans first and then parsing `kill`'s **argument positions** (signal flag vs target):
**0 negative-target kill sites** across `bin/ scripts/ hooks/ commands/ tests/`, plus 0 `killpg`,
0 `pkill -g`. Same family as the direct-exec census trap — the string you match is not the act you
mean.

### 4. Where the recorder goes, and what it will and will not cover

`bin/cc-await-ping` already traps TERM (`trap '_sig_verdict TERM 15' TERM`, line 539) and
`_sig_verdict` already clears the wake marker, appends a `WAKE-PATH-DOWN` line to the watched inbox,
prints `verdict=killed`, and exits `128+signal`. **It does everything except name the sender** — its
own comment says so: "an SA_SIGINFO recorder is the only thing that yields si_pid". So the recorder
belongs there, as a sidecar armed at startup and cleaned up by the existing EXIT trap; no new file,
no new transport, no new convention.

Two honest bounds on that placement:

- **Coverage is 109 of 352 (31%)**, not all of it. The watcher/wake-path arms are ours to instrument;
  the 243 ordinary backgrounded polls and builds die in the harness's own shell wrapper, which we do
  not own. 109 events at the measured rate still yields an `si_pid` within days.
- **Footprint: 15.0 MB RSS per armed recorder** (measured). Non-trivial on a box running ~16
  sessions, so the arm wants an env gate; this interacts with `master-fleet-footprint` and the
  default should be chosen deliberately rather than inherited.

### 5. The remainder, and the test hazard already paid for

Left to do: wire the sidecar into `bin/cc-await-ping`, have `_sig_verdict` fold the captured sender
into its verdict line and inbox notice (bounded read — that handler must not block), and red-proof it.

**The red-proof is the hard part, and the hazard is not hypothetical.** A test that exercises the 144
shape must `kill -TERM -<pgid>`, and under the Bash tool the backgrounded task and everything it
spawns share ONE process group whose leader is the wrapper — so a group kill aimed at "the child"
takes the runner with it. This pass hit exactly that: the feasibility probe derived its child's pgid,
signalled the group, and **killed its own driver shell, which the harness reported as exit 144**. The
probe reproduced the very defect it was investigating, on itself. Any bats case here must put the
victim in its own session/group first, and must never signal a group it is a member of.

