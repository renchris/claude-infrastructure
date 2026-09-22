# lr-ingest-verify 0/3 clean, first failure A6: the fault was the ingest, not the verifier (2026-09-22)

cc-backlog `1c4905d6b2ff` · filed from `docs/plans/VOLUNTARY_ACCOUNT_SWITCH.md` §9 · census source
`docs/research/voluntary-inplace-switch-2026-09-22/A06-state-observability.md` §2.5 (row 13 of §6).

## Verdict

**The ingest was wrong and the verifier was right.** A6 refused all 3 receipts because no bundle's
state log ever held a `killed_inflight` record, and it held none because no writer had run on any
path those recoveries took. Given no record, A6 is *supposed* to refuse. Its contract is that a
clause it cannot evaluate counts as a FAIL (`lr-ingest-verify.sh:179-199`). Loosening A6 would make
it pass with nothing measured. **No code change is owed by this row.** The cure is on trunk in three
commits, and each one closed a different path by which the value went unwritten:

| sha | when (UTC) | which unwritten path it closed |
|---|---|---|
| `a30670d8` | 2026-09-20 17:49 | **No writer existed at all.** `lrh_precheck` now records the probe's `live_subagents` as `killed_inflight=<n>`, but only on the DRIVER branch (`SOURCE_PANE` set). |
| `e508b234` | 2026-09-22 16:01 | **SELF recoveries (the most common in-place case) ran no probe.** `lrh_resolve_implied_pane` deliberately leaves `SOURCE_PANE` empty for self, so the B3 writer never ran. Adds `LRH_SELF_PANE` plus a record-only self probe (`lr-handoff.sh:970-996`). It also moves `live_subagents:` in `handoff-fire.sh` ahead of the limit gate, because a healthy pane exited `REFUSED:not-limited` before the count was printed. |
| `22ae2a1f` | 2026-09-22 18:39 | **An explicit `--in-place` skipped the resolver**, so the self pane went unnamed again through a different route (`lr-handoff.sh:375-389`; `cc lr switch` always passes `--in-place`). |

All three are ancestors of `origin/main` (`git merge-base --is-ancestor <sha> origin/main` → rc 0
for each).

## Why the three receipts fit this story

- The census names one of the bundles: `2825e1e5/bundle-20260922T155240Z`. It was cut at
  **15:52:40Z**, 9 minutes **before** `e508b234` was even committed (16:01:43Z). Landing and live
  convergence came later still.
- Across all 7 `events.jsonl` on the box, the census counts `admitted` 6, `gate-admitted` 6,
  `submit-token-armed` 6, `relaunch-typed` 4, `FAILED:submit` 4 and `SUBMIT-UNMEASURED` 3. **Zero
  `probed` records.** Both writer arms emit `lrh_state probed precheck "killed_inflight=<n>"`, so no
  run on the box ever reached a writer. On the driver arm a non-zero probe returns 6 *before* any
  transplant, so it cuts no bundle and writes no receipt. Every bundle-producing run was therefore
  a self or explicit-in-place run, which is exactly the population `e508b234` and `22ae2a1f` cure.
- The census was taken at 16:49Z (`b23328cf`), after `e508b234` was committed but before
  `22ae2a1f`. I cannot see the operator box's deploy log from here, so I cannot say whether
  `e508b234` was **live** for any of the three receipts. The zero-`probed` count says that, in
  effect, it was not.

## What I ran (off-box, tree == `origin/main`, `git rev-list --count HEAD..origin/main` → 0)

1. **Writer-to-reader join, end to end, in the exact form the writer emits.** The
   `tests/lr-ingest-verify.bats:109` happy-path fixture includes a top-level `killed_inflight:0`
   *and* the `detail` string. That is not the form `lrh_state` writes, so the fixture does not prove
   the join. Instead I called the real `lr_state_append` (`lr-lib.sh:441`) with
   `probed precheck 'killed_inflight=0'`, then ran A6's reader block extracted verbatim from the
   verifier over the result:
   ```
   {"state":"probed","stage":"precheck","detail":"killed_inflight=0",...}
   PASS A6 — killed_inflight=0 (recorded in events.jsonl)
   ```
   Control (the same log without the probed record, which is the shape of every real bundle):
   ```
   FAIL A6 — events.jsonl carries no killed_inflight record — ... UNRECORDED, not zero
   ```
   The control reproduces the census verdict, and the treatment clears it.
2. **Suites** (bats-core HEAD, plan line asserted on each):
   `lr-ingest-verify` 1..42 ok 42 · `lr-handoff-inplace-default` 1..8 ok 8 ·
   `lr-handoff-launcher-quoting` 1..36 ok 36 (includes the W3i and SELF writer cases at
   :586/:693/:713/:735) · `lr-handoff-voluntary` 1..14 ok 14 (includes the explicit-`--in-place`
   case at :281) · `handoff-probe-preconditions` 1..5 ok 5. No `not ok`.
3. **Dispatcher vintage:** `origin/main:bin/cc-dispatch` = `dc9130372d63…`, EQUAL to the blob that
   fired this session, so the dispatcher that composed this brief is trunk.

## Residuals, stated and not driven

1. **Not yet verified against the real world.** Everything above is a fixture test or code
   reading. Nothing off-box can produce a real recovery, so "the next receipt reads rc 0" is still a
   prediction. **Falsifier, for the desk:** on the first bundle cut after `22ae2a1f` is live, run
   `grep -c '"state":"probed"' <bundle>/events.jsonl` (expect ≥ 1) and read its `INGEST-VERIFIED.txt`.
2. **A6 was only the *first* failure.** The census read only the `verdict:` line. The verifier
   still evaluates every clause after a FAIL (`lr-ingest-verify.sh:557`), so each of the three
   receipts already lists every later clause's line. Whether any clause after A6 also failed is
   answered by `grep '^FAIL' ~/.reso/limit-recover/*/bundle-*/INGEST-VERIFIED.txt` on the desk. I
   could not run that off-box, and until someone does, "A6 was the only blocker" is **unmeasured**.
   Clearing A6 guarantees a clean receipt only if that grep shows A6 alone.
3. **The probe still prints the count after the registry-bind gate** (`handoff-fire.sh:7841` comes
   before `:7888`). If a self recovery's pane→session binding refuses, the run still records nothing
   and A6 still refuses. That is the fail-closed direction, so it is not a defect in the verifier.
   Whether that binding refuses in practice for a self pane before transplant has not been measured.
