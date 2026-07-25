# shellcheck shell=bash
# gate-policy.sh — the COMMITTED default gate scope for scripts/ship-land.sh.
# SOURCED, never executed (it only sets a variable; no shebang, not +x, on purpose).
#
# Precedence:  env SHIP_LAND_GATE_SCOPE  >  this file  >  ship-land's hardcoded `full`
# (a missing / unreadable / corrupt policy file therefore degrades SAFE — back to the
# pre-scoping full-suite behavior — instead of silently narrowing the gate).
#
#   full    every land runs `bats tests/`. The pre-scoping behavior and the KILL SWITCH:
#           `SHIP_LAND_GATE_SCOPE=full /ship` is byte-identical to before scoping existed.
#   shadow  the FULL suite still runs and still decides; the selector runs alongside it for
#           observability only (one `→ gate[shadow]: would select N suites` stderr line).
#           Zero risk — use it to calibrate gate-select.sh against real lands before flipping.
#   scoped  only the suites gate-select.sh maps to the landing range run (selector says FULL
#           ⇒ full suite; selects nothing ⇒ lint-only land), each as its own `bats <file>`
#           invocation, with one flake-exoneration re-run per failing NON-direct suite.
#           A scoped run never advances the gate-green marker — that marker asserts "the FULL
#           suite proved this tree", a claim a scoped run cannot make.
SHIP_LAND_GATE_SCOPE_DEFAULT=scoped
export SHIP_LAND_GATE_SCOPE_DEFAULT
