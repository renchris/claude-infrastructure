# T1-quota-price-output: adversarial review

Reviewed: `git diff -- bin/cc-quota-price tests/cc-quota-price.bats` on branch
`feat/token-efficiency-2026-09-23` (uncommitted, 2026-09-23). No major defects. The fix is correct and
the numbers match `data/EXTRACT.md` at fleet scale. There are four minor findings: two about tests and
two about the docs.

## What was checked, and the result

| check | result |
|---|---|
| Scope | Only `bin/cc-quota-price` and `tests/cc-quota-price.bats` changed among the owned paths. No new test files. |
| py_compile | OK |
| `--selftest` | 18 passed, 0 failed |
| `bats tests/cc-quota-price.bats` | plan `1..16`, 16 ok |
| `scripts/bats-assert-liveness.py` | rc 0 |
| bare `shellcheck` on the bats file | clean, before and after the change |
| Seam equals the pre-change tool | On a hermetic 10-record fixture (repeats, window edge, unkeyed, requestId-only), `HEAD:bin/cc-quota-price` and the new tool with `CC_QP_OUTPUT=first` give identical `--census --json` (after removing the two new meta keys) and byte-identical `--census` text. |
| New default on that fixture | output 3,410 (the old tool reads 116). The message whose first record is outside the window stays out. The input classes don't change. |
| Live read-only census, `--since 2026-09-09` | default: output **140,434,351**. Seam: **76,048,872** (+84.7%). EXTRACT.md self-check (b) gives 139.7M vs 75.4M (+85.2%). input, cache_creation and cache_read agree between the two runs (the small gap is 30 responses written by live sessions in between). 48,165 responses were raised. Runtime 42 s. |
| Mutant M1: raise disabled | case 11 goes RED |
| Mutant M2: counted index never set | case 11 goes RED |
| Mutant M3: seam ignored in the raise | case 11b goes RED |
| Mutant M7: "last" instead of "max" | survives. This is expected: EXTRACT L1 measured the count as monotone, so the two are equivalent, and the task allowed either. |
| Mutant M6: index assigned before the window check | **survives the whole selftest and bats suite.** See finding 1. |
| Callers | No code consumes `--census`/`--json` output or the new meta keys. The only other place that reads `output_tokens` with a first-record dedup is `scripts/meter-experiment/analyse.py` (finding 3). |

## Findings

1. **minor: no test covers the window-edge rule the new code depends on.** The fix keeps
   `counted[key] = None` when a message's first record falls outside `--since`, so later records can't
   raise a message that was never counted. The comment says so, but no test does. Mutant M6 moves
   `counted[key] = len(recs)` above the ts/since checks, so that index points at whichever record is
   appended next. M6 passes 18/18 selftest and 16/16 bats. On a window-edge fixture it raises
   `IndexError: list index out of range`. When another message is appended in between, it would
   silently raise that other message's output instead. Fix: add a selftest case (and a bats case)
   where the first record is older than `--since` and later in-window records have a larger output.
   Assert the message is excluded, output 0 and `output_raised == 0`. M6 should then go red.

2. **minor: case 11 never asserts `input`.** The implementer's summary says input is counted once, but
   `t11` only checks cache_creation, cache_read and deduped. Add `t11.get("input") == 10`, or drop the
   claim from the summary. Case 1 already covers input dedup, so this is only a precision fix.

3. **minor: the same bug is still in a file this item does not own.**
   `scripts/meter-experiment/analyse.py:44-52` dedups on `message.id`, keeping the first record, and
   sums `output_tokens`. It also hardcodes `3.83 pp/Mtok` output, which may come from a first-record
   fit. That script's arm-session output reads low by the same mechanism. Its H_free/H_list verdict
   turns on cr/cc rather than output, so the impact is bounded, but the constant and the sum should
   be re-derived. Filed here because it is outside the owned files.

4. **minor: two docstring accuracy points in `bin/cc-quota-price`.**
   (a) The new paragraph says the final figure "agrees with Claude Code's own `cost-state`". EXTRACT
   L2 measures final/cost-state = **0.887**. The one that agrees is `output_est` (0.997), and the gap
   is the missing agent final records described in the next paragraph. Suggested wording: "and the
   final figure is confirmed by Claude Code's own cost-state to within the agent shortfall below
   (final/cost-state 0.887, EXTRACT.md L2)".
   (b) The invariant paragraph above it still says "the identical COMPLETE `usage` object on every
   one of them … 98.5% byte-identical". EXTRACT L1 says this no longer holds: 22% of repeat records
   differ in `output_tokens`. The new paragraph qualifies it, but a reader of that paragraph alone
   gets a false statement. Change it to "identical input-side `usage`" or add "(input side; see
   below for output)" in place.

## Not findings

- The fix is the default rather than a flag. The task text asked for exactly that, so the working
  rule "a flag defaults to the current behaviour" doesn't apply. The old behaviour is still available
  through `CC_QP_OUTPUT=first`, and the byte-compare above proves it is identical.
- As before, output is attributed to the bucket of the first record's timestamp. The final record
  can land a few seconds or minutes later, so a long response can cross a 6 h bucket edge. The effect
  on the fit is negligible, and this item did not change it.
