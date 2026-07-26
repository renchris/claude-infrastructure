# t6-flakefixes  (session d4b12ddf-50d1-4b42-ae8f-66d8ff8feec7)

Harvested 2026-07-26 from disk after lead a3f68174 self-closed leaving this teammate orphaned.
Last assistant turn: 2026-07-25T23:38:32.763Z
Total records: 291

---


## turn @ 2026-07-25T23:26:30.887Z

Now the full verification run across all six suites:

## turn @ 2026-07-25T23:37:33.713Z

All 139 tests green (`1..139`, EXIT=0, zero failures). Committing:

## turn @ 2026-07-25T23:38:32.763Z

All six mission items are done, verified, and committed as `33c557f` on `tm/gr-t6` (not pushed).

## What was done

| # | Fix | Result |
|---|---|---|
| 1 | `tests/land-lock.bats:59` — appended `\|\| true` to the unguarded `kill "$dead"` | matches the correct idiom on line 54 |
| 2 | `tests/lead-supervisor.bats` — hoisted the 36-check e2e into `setup_file()`, cached to `$BATS_FILE_TMPDIR`; `setup()` re-reads it into `$output`/`$status` | 78s → 34s, 5× less flake exposure; all 5 `@test` names byte-identical |
| 3 | `tests/session-continue.bats` — `export CC_IDL` in `setup()` | live IDL leak measured before/after: **294 fixture rows historically → delta 0** |
| 4 | `${LR_POLLER_LAUNCH_DIR:-/tmp}` seam in `lr-reset-poller.sh` (1 line, prod default unchanged) + suite exports it to `$BATS_TEST_TMPDIR` | all 8 `/tmp` assertion sites retargeted |
| 5 | `cc-reaper.bats` — pinned `CC_REAPER_LOCK_STAMP_GRACE_S=60` in the UNSTAMPED test + new companion at grace=0 | RED-proven against a mutant that turns the grace into a permanent exemption |
| 6 | New `scripts/test-hermeticity-lint.sh` (225 LOC) + `tests/test-hermeticity-lint.bats` (79 LOC, 8 tests) | tree: 118 suites, 109 grandfathered, 9 hermetic; `--selftest` 6/6; **exit 0 on HEAD** |

## Verification

`bats` across all six suites: plan `1..139`, **139 ok / 0 not-ok, EXIT=0** — captured to a file rather than piped to `tail`, so no false green. Ran while another worktree was executing the full 118-suite gate, i.e. under real concurrent load. `shellcheck` + `bash -n` clean on both shell files.

## Two things worth flagging

- **Scope note (item 4):** I retargeted all 8 `/tmp/lr-poller-launch-*` assertions, not only lines 274-279 — they are the same collision site, and fixing half would have left the race live.
- **Judgment call (item 6):** a *stale* allowlist entry (suite renamed or deleted) is reported as an advisory, not a failure. The mission named exactly two FAIL conditions, and making a rename break the nightly would recreate the standing-RED rot this lint exists to prevent.

The new lint's filename ends in `-lint.sh` and contains `--selftest`, so `nightly-regression.sh` picks it up through its existing glob with no wiring change — there's a test asserting exactly that.
