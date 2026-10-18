# WP-26 (X20, lr_recon half): mkdtemp leaks in the lr_recon unit suite

Plan: `docs/plans/LOAD_ROOT_CAUSE_2026_10_17.md`, W4 row; design row X20 / WP-26 in `DESIGN.md` §2 and §5.
Done on 2026-10-17 from a cloud session (branch `claude/fire-20261017T125703Z-87835-1`). Trunk read at
`b9bc84e1`; dispatcher blob `03e82d02` equal to `origin/main:bin/cc-dispatch`.

## Change

Each bare `tempfile.mkdtemp()` in `scripts/limit-recover/lr_recon/tests/` that had no matching `rmtree` now
registers `self.addCleanup(shutil.rmtree, <dir>, True)` right after it. This is the idiom `test_store.py:39` and
`test_restore_budget_bound.py:121` already use. Unlike a `tearDown`, the cleanup also runs when `setUp` fails
after the mkdtemp. The module-level `test_act._paths()` now takes the test case, so it can register the
cleanup. There are 21 sites over 9 files. Sites that already cleaned up (`test_settle`, `test_clock`, the
prefixed `lr-*` dirs) are untouched. Nothing outside `tests/` changed.

## Evidence (what was run)

`python3 -m unittest discover -s lr_recon/tests -t .` from `scripts/limit-recover`, each arm with `TMPDIR`
pointing at a fresh empty directory, then a count of what was left in it:

| arm | tests | leftover entries in TMPDIR | failures |
|---|---|---|---|
| trunk `b9bc84e1` | 509 | **180** (all bare `tmpXXXXXXXX`) | 6 failures + 1 error |
| this branch | 509 | **0** | the same 7, compared by name with `diff` |

The 7 failures come from the VM, not from this change. They fail the same way on both arms: `HOME=/root` has
no `.reso/limit-recover`, and `/bin/sleep` stands in for the actuator. This was Linux, run under `unittest`
because there is no pytest on the VM. The desk gate's pytest/bats run is the authoritative one. At the design's
measured ~2,700 leaked trees/day, this suite's share should now be zero. The design-side check (count
`$TMPDIR/tmp*` older than one gate before and after a day of gates) is still to be done on the desk.

## Not covered by this WP

The other half of X20, dead pytest basetemp `.lock` files, belongs to WP-3 (agent-context-sync `tests/conftest.py`).
