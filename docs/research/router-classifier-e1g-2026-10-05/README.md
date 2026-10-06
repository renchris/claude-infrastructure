# Re-ask classifier, fast plus careful: the live tuning-set measurement (wave E1g, 2026-10-05)

The record is `docs/plans/RESEARCH_PROGRAM_BUILD.md`, wave E1g. This directory holds the harness and
the per-call data behind that wave's tuning table. Nothing here reads a sealed set; both scripts read
the v1 tuning set and its two-rater labels, which live outside the repo.

- `e1g-tune.py REPS OUT.json` calls `router.py classify` once per tuning row and repeat, one after
  another, the way `heldout.py evaluate` calls it (a `bash -c` child stopped at 9 s of the caller's
  clock), and keeps the label, the wall time, the load and which call and path answered.
- `e1g-score.py TUNE.json` applies the pass rule the plan fixed before the run, with
  `e1c-choose.py`'s definitions. Exit 0 is a pass.
- `tune-2reps.json` is the run of 2026-10-05 21:30-21:43 CDT (96 rows, 2 repeats, an in-session
  daemon of commit `1e4486e03`'s code on its own socket). It is keyed by tuning row index and holds
  no prompt. Three calls where the careful classifier replied in prose had that reply text removed.
- `result.txt` is `e1g-score.py`'s output on it.

The design receipt (an offline replay of wave E1c's per-call data) is
`../router-classifier-union-2026-10-05/`.
