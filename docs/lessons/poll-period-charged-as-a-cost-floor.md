# A watchdog's poll period is a sampling rate — charge it as a cost floor and the fast case pays it forever

2026-09-20, cc-backlog `4f7bf7b75181` ("post-land HUNG: tests/postland-verify.bats wedged at
11426/14327"). Cure: `scripts/postland-verify.sh` `stall_wait` + `POSTLAND_STALL_TICK_S`; red-proof
in `tests/postland-verify.bats` ("stall_wait: …", 4 tests).

## The shape

A watchdog that supervises a child by polling is written the obvious way:

```bash
child & cpid=$!
while kill -0 "$cpid" 2>/dev/null; do
  sleep "$poll"            # ← the whole defect
  … read progress, decide whether to cut …
done
wait "$cpid"
```

The loop is entered unconditionally — the child is alive by construction one line after `&`. So the
**first statement executed is a full-period sleep**, and the child's own runtime cannot shorten it.
A child that finishes in 300 ms costs `poll`. `poll` is not the resolution of the decision any
more; it is the **floor on the whole operation**.

Nothing about this is visible where the period was chosen. `POSTLAND_STALL_POLL_S=60` was picked
against a corpus run of ~45 minutes, where one 60-second tail is 2% and nobody would ever look. The
period was right. The placement of the sleep was the fault, and the two are easy to confuse because
**the only symptom is a duration, and the period is the obvious thing a duration points at.**

## Where it actually bit — the caller nobody sized it for

`scripts/postland-verify.sh` is not only a daemon. It is also the SUT of four bats suites, and those
suites drive it against a **two-file fixture corpus**. Every `--run-if-needed` in them is a real
corpus run through the real watcher, so every one of them paid the full 60 s.

Measured 2026-09-20 on `tests/postland-verify.bats` (148 tests at the time), Linux VM, unloaded:

| test | before | after |
|---|---|---|
| 1 `POSTLAND_VERIFY=off is an immediate no-op` (never reaches the watcher) | 124 ms | 142 ms |
| 2 `C7: CC_POSTLAND_WORKTREE is still honored verbatim` | **60 442 ms** | **1 448 ms** |
| 3 `C7: a trailing-slash TMPDIR reaches the corpus` | **60 421 ms** | **1 409 ms** |
| `C29: CC_POSTLAND_CONVICT=off restores the one-window red` | **60 831 ms** | **2 782 ms** |

Test 1 is the control that makes the rest a measurement rather than a coincidence: it is the one
test whose kill switch returns before `run_target`, and it is the one test that did not move.

The fourth row is a true A/B — the same test, the same box, minutes apart, with
`POSTLAND_STALL_POLL_S=2` as the only difference. 60 831 → 2 782 ms with **no code change at all**
is what identifies the period as the subject; the code change then removes it as a floor.

At ~2 SUT runs per test that is **~5 hours of pure `sleep` in one suite file**, and the suite runs
inside the very corpus it tests. What the post-land net saw was a suite that emitted no TAP line for
longer than `POSTLAND_STALL_S`, so it cut the run and filed a HUNG naming it. The verdict was
accurate about the symptom and the attribution was correct; the **subject was the watcher's own
loop**, i.e. the net had convicted itself.

## What the filing said, and why it was wrong in a load-bearing way

The row's remedy line read *"un-stubbed external seam, timeout-wrap it (NOT a peer pkill)"*. That
cause is **refuted**: the seam (`bats`) is the most thoroughly bounded call in the file — it runs
under `timeout -k 10 "$SUITE_TO"` in its own process group, with a progress-keyed stall watcher
above it and a pre-plan grace below. There was no un-stubbed seam to wrap, and wrapping anything in
a further `timeout` would have added a third bound over a duration that was 100% sleep.

The filer inferred an external cause from the fact that the time was not being spent in any code
they could see. It was not being spent in any code at all. **A duration with no CPU behind it is
not evidence of a foreign seam — it is evidence of a `sleep`, and the sleeps in a supervisor are
its own.** Check the supervisor's own waits before reaching for the subject's.

("NOT a peer pkill" was right, and independently so: `C15–C17` already partition a machine event
(cut, retried) from a suite that genuinely never returns (hung, named). This was neither.)

## The fix, and why it changes no clock

Slice the wait, keep the arithmetic:

```bash
STALL_TICK_S="${POSTLAND_STALL_TICK_S:-1}"   # 0 restores the old whole-poll sleep
stall_wait() {                               # <poll> <cpid> — rc 1 the moment <cpid> is gone
  local left="$1" cpid="$2" tick="$STALL_TICK_S"
  case "$tick" in ''|*[!0-9]*) tick=1 ;; esac
  if [ "$tick" -le 0 ] || [ "$tick" -ge "$left" ]; then sleep "$left"; return 0; fi
  while [ "$left" -gt 0 ]; do
    [ "$tick" -le "$left" ] || tick="$left"
    sleep "$tick"; left=$(( left - tick ))
    kill -0 "$cpid" 2>/dev/null || return 1
  done
  return 0
}
```

`still` and `preplan` still advance by **whole `poll` units, once per completed outer iteration**,
and an outer iteration still takes `poll` wall seconds whenever the child is alive for all of it.
The stall and pre-plan predicates are byte-for-byte the arithmetic they were. The tick only decides
how soon a **dead** child ends the wait. That distinction is what makes this a latency fix rather
than a bound change — get it wrong and the stall bound starts cutting healthy corpora at a multiple
of the rate it was calibrated for, which is the false-cut class the progress-keyed bound exists to
end.

`|| break`, not `|| true`: on early exit the loop must **skip the accounting**, not run it with a
partial period. Running it would let a run that finished normally inside its last partial period be
convicted by `still + poll >= stall` and forced to rc 124 — a healthy run cut at the finish line.

## Red-proof, and what the mutants proved

The three behavioural tests drive `stall_wait` **as a unit**, read out of the SUT with
`eval "$(sed -n '/^stall_wait() {/,/^}/p' "$SUT")"` (the `cond_slug`/`C13f` idiom, so a copy of the
rule cannot drift from the rule). Deliberately **not** a wall-clock assertion on a whole
`--run-if-needed`: that would be a load sensor, and the band this corpus runs in is measured at an
84x tax (`2514226e`). `stall_wait`'s cost is sleeps, and a sleep costs its wall time at any load.

- child exits mid-period → rc 1 in < 8 s of a 20 s period. **Mutant** (`stall_wait` → plain
  `sleep "$left"; return 0`): 20 121 ms, rc 0. Dies.
- live child → rc 0 and the **full** period paid. This is the control for the paragraph above; it
  is what a "make it faster" edit has to keep green.
- `POSTLAND_STALL_TICK_S=0` → the whole-poll sleep is back. A kill switch nothing exercises is a
  claim, not a switch.
- a grep arm on the **call site** (`sleep "$poll"` count 0, `stall_wait "$poll" "$cpid" || break`
  count 1). **Mutant** (call site reverted to `sleep "$poll"`, helper untouched): dies. That is the
  half a helper-position bug leaves broken while every unit test stays green — see
  `helper-position-bounds-a-fixs-reach`.

The recycled-pid hazard runs the safe way: a stranger inheriting the pid reads as LIVE, so the wait
runs to the full period and the test goes **red**. This test cannot go green because a pid was
re-issued.

## The transferable rule

For any supervisor that polls — a stall watchdog, a lock-acquire retry, a CI status poller, a
queue-drain wait — ask the two questions separately:

1. **How often must the decision be re-made?** That is the period, and it should be sized by the
   cost of being late to the decision.
2. **How soon must the wait end once there is nothing left to wait for?** That is a *different*
   number, and it is usually "immediately".

Collapsing them into one `sleep` charges every caller the first number as a floor. The tell is that
the cost is invisible to the calling pattern the period was sized against, and **total** for every
caller whose work is shorter than the period — and the second population is normally the test
suites, which is exactly where it reads as a hang.
