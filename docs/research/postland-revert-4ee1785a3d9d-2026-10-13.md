# Post-land revert of 4ee1785a3d9d (cc-backlog 4bf4653947b1) — verdict, 2026-10-13

**Item:** post-land AUTO-REVERT FAILED (step=land rc=124) for `tests/cc-claude-bin.bats` @ `4ee1785a3d9d`,
revert `ff1aa7357b19`.

## Verdict

1. **The revert is already on trunk.** `git merge-base --is-ancestor ff1aa7357b19fe0b3553b6c010bf99646f115d54 origin/main`
   → 0, and `ff1aa735` was trunk's tip when this ran (`git rev-list --count HEAD..origin/main` = 0 after
   `fetch --unshallow`). The "auto-revert FAILED" part of the premise is stale: a later attempt landed it.
2. **The conviction was REAL, not reachability noise.** A/B in detached worktrees, `bats tests/cc-claude-bin.bats`:
   - `4ee1785a^`: 11/11 ok
   - `4ee1785a`: `not ok 11 RATCHET: no runtime file pins its own versioned claude binary`, printed path
     `scripts/limit-recover/lr_recon/tests/test_observe.py:358: bin_ = "/Users/chrisren/.claude-293/node_modules/.bin/claude"`
   - `ff1aa735` (trunk): 11/11 ok

   The fix's own NEW test fixture spelled a versioned `~/.claude-NNN/node_modules` path, which the whole-tree
   ratchet (`git grep` over `bin scripts hooks lib`) refuses. The code change in `observe_rows.py` was not involved.
3. **The revert threw away a correct fix** (resume_leaves counting `cc-close-attrib`'s launch-watchdog subshell
   as a second `--resume` holder → false SPLIT-BRAIN, canary 4fe9935f). This branch re-lands it verbatim
   except for the fixture: `bin_` is now the unversioned `/Users/chrisren/.local/bin/claude`. The test's subject
   is the wrapper/watchdog argv shape; the version dir carried no meaning.

## Evidence after the re-land (this branch)

- `bats tests/cc-claude-bin.bats`: plan `1..11`, 11 `ok` (before the fixture edit in this same tree: `not ok 11`, same path).
- `python3 -m unittest lr_recon.tests.test_observe.Tree.test_the_close_attrib_launch_watchdog_is_not_a_second_holder`: OK.
- `python3 -m unittest discover -s lr_recon/tests -t .` (from `scripts/limit-recover`): 509 run, 6 failures + 1 error.
  These are the **same set of 7** (diffed by name) that trunk `ff1aa735` itself fails with 508 run on this Linux cloud
  VM: `test_act`, `test_main` ×4, `test_launcher_rooted`, `test_restore_budget_bound`. They are not caused by this
  diff. Not investigated here: the run happened off the operator's box, so they may depend on the environment.

## Dispatcher vintage

`git rev-parse origin/main:bin/cc-dispatch` = `03e82d02b1fc534d11df9cd4939541225bdb6829`, EQUAL to the brief's
blob: the dispatcher that fired this session is trunk's.
