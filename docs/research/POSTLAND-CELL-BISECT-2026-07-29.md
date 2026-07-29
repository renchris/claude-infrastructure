# BISECT of the 0-green-stamp cell — reused vs fresh worktree

**Backlog:** `ba63751cea54` · **DoD ref:** `docs/research/RESTART-BRIEF-2026-07-27.md#6-correction`
**Owner of the parent deadlock:** `da18f179ac50` (blocked, handoff) · **Date:** 2026-07-29

## VERDICT

**Accumulated worktree state is NOT the cause.** The cell hypothesis fails on three independent
grounds, and the phenomenon it was invented to explain has a different, already-documented cause.

1. **The variable is nearly empty.** The reused `ci-postland` cell's *entire* non-tracked content is
   **3 python bytecode files** (`bin/__pycache__/{cc-authbrowser,cc-relogin,claude-accounts}cpython-311.pyc`).
   630 files on disk, 627 tracked, **0 symlinks**, 0 untracked-non-ignored. `git clean -fd` — v1's
   step — is a provable no-op on it.
2. **That residue cannot act.** All three `.pyc` sources are **byte-identical** between the cell's
   old tree (`9b4436ad`) and trunk (`59f7eb38`), so after the cross-tree checkout the bytecode is
   *valid*, not even stale. CPython validates cached bytecode against source mtime+size; a PEP-3147
   `__pycache__` entry is never importable without its source.
3. **Measured: the cell makes no difference.** Same sha, same window, same load, disk differing by
   exactly those 3 files (table below). The one apparent difference that did appear was falsified by a
   **same-minute, both-cell control** that failed identically 2 seconds apart — the variable was the
   clock, not the cell. The red flipped **under observation**, and the cause is named to the file and
   the second (see *The mechanism, caught live*).

**What actually produced the 6-suite red set:** those six suites *are* `scripts/host-suites.manifest`
— they assert the **deployed** `~/.claude` layer, which is by construction *behind* the tree under
verification. The manifest's own header names this as the cause of "22 postland stamps produced 0
greens" (the deployed-layer bootstrap circle). v2 stopped convicting them because **v2 no longer runs
them** (set-difference partition), not because it mints a fresh cell.

## THE ONE-VARIABLE ISOLATION (proved, not assumed)

| | ARM A (reused) | ARM B (fresh) |
|---|---|---|
| cell | `~/Development/.worktrees/ci-postland` — v1's long-lived cell | `~/Development/.worktrees/ci-bisect-fresh` — minted for this run |
| prepared by | `git checkout --detach 59f7eb38` (v1's *exact* reuse step; residue preserved) | `git worktree add --detach … 59f7eb38` |
| tree hash | `3d7ff70e921a3ede13f6a1248b436e46fc483c58` | `3d7ff70e921a3ede13f6a1248b436e46fc483c58` (identical) |
| disk delta | **exactly** the 3 `.pyc` files | — |

Invocation is postland's, verbatim: private `TMPDIR`, `timeout -k 10`, the 147-suite explicit file
list (`tests/*.bats` minus the 8-line host manifest), postland's PATH normalization, run
**concurrently** so both arms see the identical load window.

One deliberate deviation, taken through postland's own seam: `CC_POSTLAND_TASKPOLICY_BIN` set-but-empty
⇒ `nice -n 19` alone (`postland-verify.sh:162-168`, "honored verbatim"). Darwin's throttled BACKGROUND
band delivered **24 tests / 5 min at load 48** — ~8 h/arm, where a backstop-cut arm is a non-verdict.
QoS is identical across arms, so the cell comparison is unaffected; load was already eliminated as a
cause (reds at load 5.8 and 9.34).

### Results

| measurement | cell | sha | when (UTC) | result |
|---|---|---|---|---|
| ARM A2 — full corpus (147 suites, plan `1..2324`) | reused | 59f7eb38 | 21:53-23:52 | 2324/2324 done, **14 not-ok** in 5 files, run_s 7145 |
| ARM B2 — full corpus (147 suites, plan `1..2324`) | fresh | 59f7eb38 | 21:53-23:52 | 2324/2324 done, **13 not-ok** in 6 files, run_s 7145 |
| C1 — the 6, session PATH | fresh | 6a7088e8 † | 21:31 | **155 ok / 0 not-ok** |
| C2 — the 6, real v1 daemon PATH | fresh | 6a7088e8 † | 21:38 | **155 ok / 0 not-ok** |
| D1 — the 6 convicted suites | fresh | 59f7eb38 | 22:18-22:26 | **155 ok / 0 not-ok** (470 s) |
| D2 — the 6 convicted suites | **reused** | 59f7eb38 | 23:24 | 154 ok / **1 not-ok** |
| **same-minute control** — deploy-parity alone | **reused** | 59f7eb38 | **23:26:17** | 15 ok / **1 not-ok** |
| **same-minute control** — deploy-parity alone | **fresh** | 59f7eb38 | **23:26:19** | 15 ok / **1 not-ok** |

D2's single not-ok looks at first like the cell effect the item went looking for. It is not: the
same-minute control — the same file, both cells, **2 seconds apart** — fails **identically**. What
changed between D1 and D2 was not the cell but the clock.

### The arms, per file — the reused cell produced NOTHING the fresh cell did not

Both arms ran to completion (`done == plan == 2324`) in the *same* 7145 s window, so neither is a cut.

| file | A2 reused | B2 fresh | alone, sequential, per cell |
|---|---|---|---|
| `tests/cc-authbrowser.bats` | red (165/176/189/191) | red (184/191) | **35 ok / 0** in *both* cells ⇒ concurrency |
| `tests/mailbox-drain.bats` | red | red | shared — symmetric |
| `tests/postland-verify.bats` | red | red | shared — symmetric |
| `tests/tsv-field-collapse.bats` | red | red | shared — symmetric |
| `tests/wake-floor.bats` | red | red | shared — symmetric |
| `tests/idl-abstain-alarm.bats` | — | **red** | **11 ok / 0** in *both* cells ⇒ concurrency |
| **reused-cell-only failures** | **NONE** | — | — |

The asymmetry runs the *wrong way* for the hypothesis: the **fresh** cell failed one file more than the
reused cell, and that file passes 11/0 alone in both. Re-running the two asymmetric files alone and
**sequentially** (postland's own retry-ladder discipline) clears both in both cells — so every observed
difference is cross-run interference between the two concurrent corpora, not cell state.

Five files red in **both** cells. Those are either genuine reds at `59f7eb38` or artifacts of running
two corpora at once; either way they are cell-independent, which is the question this item asked.
Notably `tests/postland-verify.bats` — the suite postland convicts in 4 of its last 6 stamps — reproduces
red **outside postland, in both cells**, which is an independent confirmation for `da18f179ac50` that its
current red is real rather than a verdict-path artifact.

† `6a7088e8` is the sha of the **last** v1 six-suite conviction (stamp 2026-07-28T20:21:26Z) — the
control replays the artifact rather than an approximation.

## THE MECHANISM, CAUGHT LIVE (the strongest evidence in this file)

The red flipped **under observation, with the cell held constant**, and the cause is named to the file
and the second:

```
22:18-22:26Z  D1  the 6 suites, FRESH cell @ 59f7eb38 ............... 155 ok / 0 not-ok   GREEN
22:31:50Z     21b68c60 lands on the shared checkout: two BRAND-NEW tracked files
                 bin/cc-bats · scripts/qos-census.sh
23:24Z        D2  the 6 suites, REUSED cell @ 59f7eb38 .............. 154 ok / 1 not-ok   RED
23:26:17Z     control: deploy-parity alone, REUSED ................. 15 ok / 1 not-ok    RED
23:26:19Z     control: deploy-parity alone, FRESH .................. 15 ok / 1 not-ok    RED  ← same
```

The failing test is `tests/deploy-parity.bats:88`:

```bash
@test "the real repo passes its own assertion (guards the live host deployment)" {
  run env -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY "$ASSERT"
```

It **unsets** every parity override, so its subject is the real repo and the real `~/.claude` — not the
cell it is invoked from. Running the assert directly names the drift:

```
MISSING: ln -sf …/claude-infrastructure/bin/cc-bats            …/.claude/bin/cc-bats
MISSING: ln -sf …/claude-infrastructure/scripts/qos-census.sh  …/.claude/scripts/qos-census.sh
deploy-parity-assert: 2 tracked runtime file(s) have NO live counterpart under /Users/chrisren/.claude.
A bare ff-sync of the checkout can never create these links — run ./install.sh (or the ln -sf lines above).
```

`~/.claude/{bin,scripts,hooks,commands}` are directories of **per-file** symlinks, so a brand-new
tracked file is never linked however current the checkout (memory: `deploy-lag-checkout-behind-origin`).
**Any land of a new file reds these suites instantly, in any cell, at any load** — which is precisely
the deployed-layer bootstrap circle, and exactly the shape of a red that is deterministic (survives the
≥2/3 retry ladder, `flakes=0`), load-independent, and cell-independent. That is the 6-set, explained.

## COMPETING EXPLANATIONS, EACH KILLED WITH ITS OWN MEASUREMENT

**PATH — refuted, and the brief's PATH model was wrong.** The launchd job has exported
`PATH="$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"` since the *first* commit of
its plist (`95438bbb`, 2026-07-25T16:40) — the live plist matches the repo SSOT. So `.claude/bin` was
**never** missing; only `$HOME/bin` was. C2 ran the 6 under exactly that PATH: 155/0.
`postland-verify.sh`'s header claim ("its PATH lacks `$HOME/.claude/bin` and `$HOME/bin`") is
therefore half-wrong for this job, and the PATH normalization it added is hygiene, not the fix —
consistent with the elimination chain having already RETRACTED hypothesis (6).

**Concurrent runs mutating the one shared cell — refuted on data.** Reconstructed every run's window
from `stamp.ts - run_s` across all 33 stamps: **zero overlaps**. `try_acquire` never reaps a lock
whose holder is alive (`kill -0`), so `LOCK_TTL=3600` is not stealable out from under a 13,248 s run.

**Load — already refuted, and re-confirmed.** The 6 pass at load 25-50 here; postland convicted them
at load 5.8 and 9.34.

## WHAT THE v1→v2 CUTOVER ACTUALLY SHOWS

v2 landed as one commit (`0152be39`, 2026-07-28T11:16) carrying *five* changes at once: fresh cell per
run, the host partition, standalone prelints, PATH normalization, background QoS + a stall bound. Its
first live run began **2026-07-28T20:55:03Z**; the last six-suite conviction was stamped
**2026-07-28T20:53:48Z** — 75 s earlier. So the stamp record cannot, by itself, attribute the
disappearance to any one of the five.

The attribution is settled by content, not timing: the six convicted suites are *exactly* the six
non-lint entries of `scripts/host-suites.manifest`, and v2's corpus is `tests/*.bats` **minus** that
manifest. v1 ran `nice -n 10 bats tests/` — the bare directory, all 155 suites. **v2 cannot convict
them because it does not run them.**

| | v1 (`0152be39^`) | v2 |
|---|---|---|
| cell | `$HOME/Development/.worktrees/ci-postland` (reused) | `$STATE/wt-run-$$` (minted per run) |
| corpus | `bats tests/` — bare dir, **includes** the 6 | explicit 147-file list, **excludes** the 6 |
| 6-set convictions | **18 stamps** (2026-07-26T02:16Z → 07-28T20:53:48Z) | **0** in 10 verdicts |

Stamp ledger overall: **33 stamps, 0 green, ever** — 30 red, 2 cut, 1 hung.

## THREE NEW DEFECTS FOUND WHILE RUNNING THIS

**1. The stall bound is blind to bats' counting pass (latent false-cut).** `bats <141 files>` first
runs a `bats-exec-suite --dummy-run` counting pass that emits **no TAP**. `run_target`'s stall watcher
(`postland-verify.sh:851-866`) keys on `tap_done` (which counts `ok|not ok` only) with its clock
starting at t=0, so a healthy run looks frozen from the start. **Measured:** >600 s in the counting
pass at load 33-48 under background QoS, with a 0-byte TAP and a live `bats-exec-suite` — against a
900 s `POSTLAND_STALL_S`. Honest bound on the claim: no stamp has yet exhibited this (both `cut`
stamps, run_s 2737 and 5437, match the *older* 2700 s/5400 s wall bounds). It is a latent
load-conditional false-cut, and a false cut is indistinguishable from a real one in the ledger.
*Fix shape:* give the pre-plan phase its own grace and start the stall clock at the `1..N` line.

**2. `waiting-recycle` (445 s alone) cannot survive v1's retry ladder.** ⚠️ **CONVERGENT — already
found and FIXED by a sibling stream while this bisect ran.** `LANDING_GATE_ROOT_CAUSE_2026-07-26.md` §5
(backlog `10941179f8ec`) reports the same defect with independent evidence and landed the C23 fix (rc 124
in the ladder becomes an abstention, and the re-run is the failing *test* rather than its whole file).
My duplicate backlog item was closed against theirs rather than re-worked. Recorded here because the
measurement below was taken blind to theirs and so is an independent replication — **with one
correction to their point 4**, which generalises "the convicted suites are exactly the heaviest":

Per-suite alone runtimes at
load 25, sha `6a7088e8`: deploy-parity 9 s, desk-arm-live 9 s, desk-recycle-durable 11 s,
lr-team-audit 2 s, session-continue 14 s, **waiting-recycle 445 s**. v1 re-ran each red file alone
under `FILE_TO=300` and convicted at ≥2/3 — so `waiting-recycle` was convicted **by the bound**,
deterministically, cell-independently, with `flakes=0` as the tell. This is the concrete instance of
"a verifier that cannot distinguish *killed* from *failed*".

**The correction:** the bound explains **one** of the six. The other five run **2-14 s** solo, so no
300 s bound can convict them — and if a bound were deciding, the corpus's genuinely heavy suites would
be convicted first, yet `cc-notify` (75 s) never was while `deploy-parity` (9 s) always was. Two eras,
two mechanisms: the *post-v2* single-suite red (`postland-verify.bats`, ~50 min solo) is the ladder's
bound, which C23 fixes; the *pre-v2* 6-set is the host/deployed-layer partition, which is why that
set's membership never varied — it is literally the manifest. C23 does not retire the first mechanism,
and the host partition does not retire the second.

**3. `cc-authbrowser` cross-run port contention.** Two concurrent corpora produced not-ok only in
`cc-authbrowser`'s port/launch tests, at *different* indices per arm (A: 165/176/189/191; B: 184/191).
Concurrent full-corpus runs are therefore **not independent** — a sibling gate can red a suite through
a fixed port. Relevant to any "concurrent gates" reasoning and to postland's flake accounting.

## WHAT THIS DOES NOT CLOSE

- **Why the 6 are still an open question at all.** They are now partitioned out of the tree verdict and
  belong to `deploy-live.sh`, which runs them against the layer they describe. But `deploy.log`'s last
  three lines are `/Users/chrisren/.claude/scripts/deploy-live.sh: No such file or directory` — the
  deploy leg is **not deployed** (a missing per-file symlink; cf. memory `deploy-lag-checkout-behind-origin`).
  So nothing currently runs the host suites anywhere. Not this item's scope; surfaced for the deploy owner.
- **The current red.** 4 of the last 6 stamps convict `tests/postland-verify.bats` — a *different*
  suite from the 6, and outside this bisect. `da18f179ac50` remains the owner.
- **The historical cell state is unrecoverable.** The residue that existed on 2026-07-27 is gone
  (`clean -fd` on v1's last run, then v2 abandoning the cell). A green in ARM A proves the *current*
  cell is innocent; the mechanistic argument (points 2 and 3 of the verdict) is what extends that to
  the historical cell, not the A/B alone. Stated explicitly so no later reader over-reads the table.
- **`bats tests/` (v1's bare-directory corpus, all 155 suites) was not re-run in both cells.** It would
  cost ~2 h/arm to re-derive a conclusion already settled by content (the partition) and by D1/D2/C1/C2
  on the six suites themselves. Deliberately not run; named here so the gap is auditable, not silent.
