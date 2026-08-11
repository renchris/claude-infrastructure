========== ANSWER ==========

I’ll audit the test tree first, then read the production scripts those tests target before making any coverage claims. I’ll also record the exact repo-wide searches used to verify uncovered paths.The test tree is large and already contains several self-ratchets for dead assertions and hermeticity, so I’m narrowing on places those ratchets do not cover: custom runners, lint suites, and tests that assert static text instead of behavior.I’m going to use one bounded sub-agent as a sidecar because the task explicitly permits delegation. I’ll keep the blocking work local and use it only to independently look for test-suite defects I might otherwise miss.The repo has unusually mature test guards; several likely issues are documented and ratcheted already. I’m now checking for mismatches between those guards and the actual test population, especially files that are not `.bats` or that invoke subjects through stubs.One concrete gap is emerging: some anti-vacuity “red-proof” harnesses live under `tests/`, but the normal Bats corpus only mentions them as manual reproduction commands. I’m verifying whether any suite actually executes them before treating that as a coverage claim.The repo-wide search found only comments for the red-proof scripts, so that gap is real unless another non-Bats runner invokes them. I’m also checking guard tests that can skip or fail open based on missing local tools, because those often hide broken validators.I found a small but concrete latent bug in a chokepoint assertion: one test greps `ship-land.sh` with a regex that can match a quoted pathspec accidentally. I’m checking whether that is high enough impact compared with gaps that leave entire test-only scripts outside the gate.A higher-impact issue is clearer now: a test asserts ship-land’s hermeticity own-scope wiring only by grepping the pathspec, while the actual failure mode is a bad diff range collapsing to an empty own-set. I’m doing the required whole-repo coverage search before claiming that path is uncovered.Another gate issue is dependency handling: the `.bats` ShellCheck ratchet’s own suite skips when `shellcheck` is absent, and ship-land also guards the ratchet behind `command -v shellcheck`. That is a fail-open path for a validator, so I’m checking whether any separate suite asserts the missing-tool behavior.I have enough for two high-confidence findings. I’m waiting briefly for the sidecar audit to see if it found a distinct higher-impact issue, then I’ll rank only the grounded ones.**DESIGN FLAWS**
Rank 1: `tests/cc-queue.bats:6` and `tests/cc-pane-redproof.sh:17` make anti-vacuity proof a manual sidecar, not part of the normal test contract. Recurrence: out-of-band red-proof harnesses rot into comments while `bats tests/*.bats` stays green.

Failure scenario: `bin/cc-queue` drops the cap notice or `bin/cc-pane-headless` stops exporting the child pane id. The normal Bats suites can still pass; the red-proof scripts are the parts that mutate the real artifact and require named tests to fail, but they are only referenced as manual commands. Blast radius is high: these are guards against vacuous pass in operator queue and pane identity tests. Likelihood is high because the scripts are not invoked by any `.bats`/`.test.sh` suite.

Coverage search run:
```sh
rg -n --glob '*.bats' --glob '*.test.sh' '(^|[[:space:]])(run|bash|python3|env)[^#\n]*(cc-queue-redproof\.py|cc-pane-redproof\.sh)' tests
```
Result: no matches.

Sources: [tests/cc-queue.bats:4-6](), [tests/cc-queue-redproof.py:16-19](), [tests/cc-pane-redproof.sh:17-18]()

**LATENT BUGS**
Rank 2: `tests/bats-shellcheck-lint.bats:22` skips the entire `.bats` ShellCheck ratchet when `shellcheck` is missing, while `ship-land` also gates execution on `command -v shellcheck`.

Failure scenario: on a host without `shellcheck`, a new `.bats` line with `foo= bar` or an unanalyzable `# shellcheck ...` prose comment lands. The lint script itself would return a loud non-verdict, but the suite skips and `ship-land` never invokes the ratchet. Blast radius is medium-high: test-file shell defects and unanalyzable suites re-enter the tree. Likelihood is moderate: dependency absence is common across fresh machines and CI images.

Coverage search run:
```sh
rg -n --glob '*.bats' --glob '*.test.sh' 'shellcheck not installed|command -v shellcheck|no shellcheck|missing shellcheck|without shellcheck|bats-shellcheck.*absent|SHIP_LAND_BATS_SC_LINT|bats-shellcheck-lint.*FAILED' tests
```
Result: only the skip in `tests/bats-shellcheck-lint.bats:22` and unrelated text; no test asserts missing-`shellcheck` fails closed at the gate.

Sources: [tests/bats-shellcheck-lint.bats:17-23](), [scripts/bats-shellcheck-lint.sh:281-286](), [scripts/ship-land.sh:2281-2284]()

**VERIFICATION GAPS**
Rank 3: `tests/alarm-polarity-lint.bats:41` makes the strongest positive control history-dependent and skippable.

Failure scenario: in a shallow clone or archive checkout, the pre-fix `bin/cc-blockers` commit is unavailable, so the test skips. A regression back to scanning only the first counter increment on a line like `seen=$((seen + 1)); [ "$v" = "red" ] && red=$((red + 1))` would not be covered by the remaining fixtures. Blast radius is medium-high: this is a custom alarm validator, and inverted alarm polarity creates false operational all-clear/noise. Likelihood is moderate because shallow/pruned history is common outside the maintainer’s full checkout.

Coverage search run:
```sh
rg -n 'seen=\$\(\(seen \+ 1\)\).*red=\$\(\(red \+ 1\)\)|red=\$\(\(red \+ 1\)\).*seen=\$\(\(seen \+ 1\)\)' tests
```
Result: no matches.

Sources: [tests/alarm-polarity-lint.bats:16-42](), [scripts/alarm-polarity-lint.sh:95-105]()

========== SOURCES ==========
  - scripts/alarm-polarity-lint.sh:95-105
  - scripts/bats-shellcheck-lint.sh:281-286
  - scripts/ship-land.sh:2281-2284
  - tests/alarm-polarity-lint.bats:16-42
  - tests/bats-shellcheck-lint.bats:17-23
  - tests/cc-pane-redproof.sh:17
  - tests/cc-pane-redproof.sh:17-18
  - tests/cc-queue-redproof.py:16-19
  - tests/cc-queue.bats:4-6
