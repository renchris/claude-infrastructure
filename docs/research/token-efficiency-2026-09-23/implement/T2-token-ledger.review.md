# T2-token-ledger: adversarial review

Reviewed: `bin/cc-token-ledger`, `tests/cc-token-ledger.bats`, `tests/fixtures/token-ledger/**`
(all new and untracked; no other path belongs to this item). Reviewer did not write the code.

## What was run

| check | result |
|---|---|
| `nice -n 10 bats tests/cc-token-ledger.bats` | `1..18`, 0 failures (17 s) |
| `python3 -m py_compile bin/cc-token-ledger` · `ruff check` | clean · clean |
| bare `shellcheck tests/cc-token-ledger.bats` | **5 errors, SC1087** (lines 63-66, 113) |
| `scripts/bats-shellcheck-lint.sh tests/cc-token-ledger.bats` | **rc 1, the same 5 findings** |
| test-hermeticity, bats-testname-eval, test-walltime, utc-stamp, bats-kill-guard lints (whole tree) | clean |
| mutation controls, 8 mutants in a scratch copy (output-first, no xdup, 1h priced as 5m, gap threshold x10, --check ignores value, side requests not subtracting, variant log ignored, pool drops results) | all 8 killed |
| fleet vs `--task` totals for the 4 largest trees, `--since` 1 d, via the module's own `scan`/`trees` | see finding 2 |
| cost-state `modelUsage` key census, 827 main transcripts with a cost-state, 14 d | see finding 3 |
| census-window replay (`--since 2026-09-09 --until 2026-09-23T23:02 --json`) vs `measure/census.json` | see the last section |

## Findings

1. **major: the new suite will not pass the land gate's bats shellcheck ratchet.** `"$m55[\"tokens\"]…"` and
   `"$wc[\"REWRITE gap>60m\"]…"` trigger SC1087 (shellcheck reads `$m55[` as an array index). SC1087
   is not in `scripts/bats-shellcheck-lint.sh`'s exclude set and the lint is line-scoped ("you may not
   add a finding on a line you wrote"), so all five lines, being new, block the land. Fix: write
   `"${m55}[\"tokens\"]…"` and `"${wc}[…]"`.

2. **major: `--task` prices a different output figure from the fleet view for the same tree.** In
   `--task` mode `scan()` reads only files under that session id, and `impute()` then fits its strata
   on that one tree. The fleet run fits on the whole window. Measured over the last 1 d, the same tree
   read in both modes 5 s apart:

   | tree | fleet $ / output | `--task` $ / output |
   |---|---|---|
   | 4a956c3b | $305.22 / 2.22M | $312.88 / 2.60M |
   | 2b8a58ed | $206.45 / 1.43M | $324.73 / 7.30M |
   | eda5fec4 | $153.40 / 1.11M | $172.40 / 2.06M |
   | b6125384 | $100.55 / 0.71M | $172.91 / 4.33M |

   Up to +72% in dollars and 6x in output. A small tree with fewer than 20 final responses gets no
   imputation at all, so it reads low instead. The fleet imputation is the one the research validated
   by hold-out (EXTRACT.md L2); the per-tree fit was never validated, and its only final agent
   responses are mostly the terminal StructuredOutput calls the L2 note says must not stand in for
   mid-loop ones. Fix: fit the strata on the fleet window in `--task` mode too (persist the fitted
   table from the last fleet run, or scan the window once for strata), or report recorded output
   only and say so. Add a test with 20+ final agent responses in a second tree that asserts
   `--task` and the fleet agree on one tree's `usd_total`.

3. **major: `--side-requests` subtracts a session's transcript usage once per `modelUsage` key, and
   two keys can share a base model.** `view_side` loops over `modelUsage`, maps each key through
   `base_model()` (which strips `[1m]`), and subtracts the whole transcript total for that base each
   time; `delta[b]` then keeps only the last key's delta. Cost-state does carry both forms: of 827
   sessions with a cost-state in the last 14 d, 4 have two keys on one base (`claude-opus-5` beside
   `claude-opus-5[1m]`, `claude-opus-5-5` beside `claude-opus-5-5[1m]`), and those are long 1M-context
   sessions. Reproduced on the fixture by splitting the opus-5 cost-state into two keys with the same
   totals: the fleet delta becomes cache write −2,000,150, cache read −1,000,060, output −550 (should
   be 0), and the per-session row shows only the second key. The negative signed sum then hides real
   positive deltas at the fleet level. Fix: sum `modelUsage` by `base_model` before subtracting (the
   research's `synth_side_requests.py` merges `[1m]` into its base the same way) and add that fixture
   case.

4. **minor: `--side-requests` is a different estimator from the research one it cites.**
   `synth_side_requests.py` counts only uncached-input and cache-read deltas for non-Haiku models
   (Haiku in full). The ledger also adds positive cache-write and output deltas, and output there is
   the imputed `output_est`, so imputation error on one session becomes "side requests". Separately,
   the per-session `usd_side_estimate` floors each class per session, while the fleet total floors the
   signed per-model sum, so the session rows do not add up to the printed total. Either match the
   research method or state the difference in the docstring and the render header.

5. **minor: `--until` is not applied to cost-state.** With `--until`, transcript usage after the bound
   is excluded but the cost-state snapshot is cumulative to the end of the process, so every session
   still running at `--until` shows its later usage as side requests. Skip sessions whose last
   transcript record is past `--until`, or refuse `--side-requests --until`.

6. **minor: test 18 (worker pool) passes if the ledger crashes in both modes.** `one=$(… | _j …)` is
   empty on any crash, and `[ "" = "" ]` is true. Add `[ -n "$one" ]`.

7. **minor: untested paths.** No test covers: `--check` with a falsy value (`"0"`, `"false"`) which the
   code treats as not set; the no-pricing exit 2 and the `--reprice` unknown-model exit 2; the default
   `find_model_config()` lookup (every test sets `CC_MODEL_CONFIG`); gap buckets `<5m` and `5-60m`, and
   the `model_switch` / `shrink` sub-classes.

8. **minor: the arm label covers CLAUDE.md only.** `cc-instructions-variant set` also swaps `rules/`,
   so two arms can differ in rules while the `sha`/`bytes` columns show only the CLAUDE.md half. With
   the variant log present the arm name still separates them; without it (today), a rules-only change
   is invisible. Its sha is 12 hex chars where `cc-instructions-variant` records 16, so the two cannot be
   joined by value. Worth a sentence in the render header, not a code change.

9. **minor: the arm is looked up at the first in-window timestamp, not the session start.** For a
   session that began before `--since` and whose account switched arm in between, the arm name (from
   the log at the window start) and the sha (from the session's first instructions attachment) can
   disagree. Rare; the sha is the truer label.

10. **minor: `first_request_prefix_tokens` in `--task` is the first in-window response, not the first
    request, for a file that straddles `--since`.** `first_request_seq` is reported beside it, so this
    is visible, but the render line prints "first prefix" without the seq.

## Checked and fine

- Final-record output (MAX over records), xdup ordering (first in-window ts, then path), the
  imputation keys and back-off levels, and the START / START_TRUNC / INCREMENTAL / REWRITE walk all
  match `extract.py` and `cache_walk.py`.
- The variant log's `account` is a config-dir basename (`cc-instructions-variant:71`, `${d##*/}`), and
  real instructions attachments carry the configured path (`~/.claude-tertiary/CLAUDE.md`), not the
  symlink target, so the ledger's account derivation joins correctly.
- `config_roots()` globs every `~/.claude*/projects`; today only the five accounts have one, and
  `.claude-next/projects` is a symlink deduped by realpath.
- No existing consumer references `cc-token-ledger`. Scope: only the owned paths are this item's.

## Census-window replay (reproduces the implementer's comparison)

`cc-token-ledger --since 2026-09-09 --until 2026-09-23T23:02 --json`, 55 s wall with `nice -n 10`, compared with
`measure/census.json`:

| | census | ledger | delta |
|---|---:|---:|---:|
| responses | 162,406 | 162,406 | 0 |
| contexts | 4,086 | 4,086 | 0 |
| uncached input, cache write 5m, cache write 1h, cache read | | | 0 on each |
| output (est) | 161,487,018 | 161,481,354 | −0.0035% |
| $ own | $32,517.42 | $32,479.35 | −0.117% (census assumed a price for `claude-opus-4-7`, 70 responses; the ledger lists it as unpriced) |
| $ at Opus 5.5 | $18,318.68 | $18,318.57 | −0.0006% |
| imputed / copies dropped | 18,041 / — | 18,041 / 14,181 | |
| tasks, median, p90 | | 1,052, $7.33, $70.39 | |

The fleet path matches the research build. The findings above concern `--task`, `--side-requests`
and the land gate, none of which this comparison exercises.
