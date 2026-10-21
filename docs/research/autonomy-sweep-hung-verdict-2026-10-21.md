# Verdict — cc-backlog 291d7ef9a4a1: `tests/autonomy-sweep.bats` "HUNG" is REFUTED as a seam wedge

**Item:** `post-land HUNG: tests/autonomy-sweep.bats wedged at 501/21633 @ 216b39f178a0 — un-stubbed
external seam, timeout-wrap it (NOT a peer pkill)`.
**Verdict:** premise REFUTED. There is no un-stubbed seam to wrap, and the file does not wedge. The
HUNG came from `postland-verify.sh § confirm_hang`, which treats "did not finish inside 300 s" as
"never returns". That rule cannot tell apart a file that is *starved but advancing* and a file that is
*wedged*. **No code change to the suite is owed, and none is made here.** Close the row on this
artifact. File the follow-on below as its own row; it was not run here.

## Identity of the cited objects (cloud session, full clone, 2026-10-21)

- `216b39f178a0…` is a **tree**, not a commit (`git cat-file -t` → `tree`). It is the tree of
  `dc13d1a09925` (`docs(plans): sustained-load implementation plan…`, 2026-10-20). The falsifier
  names that commit too.
- `git merge-base --is-ancestor dc13d1a09925 origin/main` → 0 (landed).
- `git log dc13d1a09925..origin/main -- tests/autonomy-sweep.bats scripts/autonomy-sweep.sh` → empty.
  The bytes that were judged HUNG are the bytes on trunk now. `git rev-list --count HEAD..origin/main`
  → 0.
- Dispatcher vintage: `git rev-parse origin/main:bin/cc-dispatch` = `73b9577e45cd…`, which **equals**
  the blob that composed the brief. The dispatcher that fired this session IS trunk.

## What was run, and what it showed

Box: Linux VM, 4 cores, bats 1.13.0, `/usr/bin/timeout` present. Every run had stdin closed, the
same way `confirm_hang` runs it.

1. **Unloaded, file alone:** `timeout 900 bats -T tests/autonomy-sweep.bats </dev/null`
   → **finished in 214 s**, 103/103 planned, 102 ok, 1 not ok. The slowest test took 6.7 s (#24, D2
   damped banner). The one red is #70 (`load1 is not a number: null`). It is a Linux-box property:
   there is no `sysctl vm.loadavg` here. It is not a hang, and it is out of scope.
2. **Seam audit:** all 139 sweep invocations go through `"${SWEEP_TO[@]}"` (`timeout -k 5 30`,
   resolved by absolute path, fail-open), and that includes every `$deployed/autonomy-sweep.sh` copy.
   This is the cure from cc-backlog `6b42d1f49770`, and it is still on trunk. Direct
   `cc-backlog` / `cc-decide` calls in the fixtures are local file-store verbs under a hermetic `HOME`.
   None of them waits on the network or on a tty.
3. **Positive control: `confirm_hang`'s exact shape under contention.** Six nice-0 busy loops ran on 4
   cores, plus `timeout 300 nice -n 19 bats -T tests/autonomy-sweep.bats </dev/null`
   → **rc 124 after 301 s with 6 of 103 tests done.** Each of those 6 tests took ~32 s (31.7–34.5 s).
   That is the suite's own 30 s `SWEEP_TO` wrap firing, plus `-k 5` and fixture overhead. So the file
   was **advancing steadily**, at one test about every 32 s: the inner bound ladder turns starvation
   into bounded per-test cuts, exactly as designed. At that rate the file needs ~55 min (103 × 32 s).
   That is 11× `FILE_TO=300`.

At the desk, `confirm_hang` runs the file under `QOS=(nice -n 19 taskpolicy -c background)`, the
lowest band, on a box that is by construction busy with a full-suite post-land run. Run 3 is that
situation. rc 124 there is starvation. `classify_hang` reads it as `REPRODUCED=true` → HUNG.

## Why the remedy the page names is the wrong one

"Timeout-wrap the un-stubbed seam" is already done, and run 3 shows the wrap working. Adding another
bound inside the file can only make each starved test die sooner. The file would still not finish
inside 300 s, so the HUNG verdict would repeat on the next starved tick and point at the same file.

## Follow-on (NOT done here; file as its own row)

`scripts/postland-verify.sh § confirm_hang` decides on wall time alone. It should decide on
**progress**: capture the confirm run's TAP and convict only if no new `ok`/`not ok` line appeared
during the final stall window. The stall-watcher's `tap_planned`/`tap_done` already read that grammar.
The alternative is to size the confirm bound to `n_tests × per-test bound`. In both cases, a confirm
run that kept emitting results until the bound fired is a CUT, not a HUNG. This is the
"inner bound starves the tail" class (`docs/lessons/inner-bound-outer-bound-starves-the-tail.md`):
here the per-test bound is 30 s, the tests number 103, and the confirm bound is 300 s.
Off-box, `cc-backlog add` writes nothing, so this artifact is how the follow-on reaches the store. It
cites item 291d7ef9a4a1.
