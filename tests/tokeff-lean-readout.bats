#!/usr/bin/env bats
# scripts/tokeff-lean-readout.sh — the self-reporting 7-day workflow-lean saving readout (token-efficiency
# wave 2, item 8). Pins: the estimate is lean spend x (1/0.156 - 1) from the ledger's by-agent-type JSON;
# the falsifier says "not yet" before the window closes, exits 0 only once origin/main carries the
# readout, and after a failed attempt waits out the retry window instead of re-launching a land.
#
# Hermetic: the ledger is a stub (TOKEFF_LEDGER_BIN), the repo is a fixture clone with a bare origin
# (TOKEFF_LEAN_REPO), and the store is under BATS_TEST_TMPDIR (TOKEFF_LEAN_STORE). Nothing lands.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  S="$REPO_ROOT/scripts/tokeff-lean-readout.sh"
  T="$BATS_TEST_TMPDIR"
  export HOME="$T/home"; mkdir -p "$HOME"
  export TOKEFF_LEAN_STORE="$T/store" TOKEFF_LEDGER_BIN="$T/ledger"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  printf '%s\n' '#!/bin/bash' \
    'printf "%s" "{\"agent_types\":[{\"ctx_type\":\"workflow_agent\",\"agent_type\":\"workflow-lean\",\"contexts\":4,\"usd_total\":6.0,\"usd_total_reprice\":3.0},{\"ctx_type\":\"subagent\",\"agent_type\":\"workflow-lean\",\"contexts\":1,\"usd_total\":4.0,\"usd_total_reprice\":2.0},{\"ctx_type\":\"workflow_agent\",\"agent_type\":\"workflow-subagent\",\"contexts\":2,\"usd_total\":5.0,\"usd_total_reprice\":2.5}],\"excluded_contexts\":7}"' \
    > "$T/ledger"
  chmod +x "$T/ledger"
  R="docs/research/token-efficiency-2026-09-23/REPORT.md"
}

fixture_repo() { # $1 = text REPORT.md carries on origin/main
  git init -q --bare "$T/origin.git"
  git init -q -b main "$T/seed"
  mkdir -p "$T/seed/$(dirname "$R")"
  printf '%s\n' "$1" > "$T/seed/$R"
  git -C "$T/seed" add -A && git -C "$T/seed" commit -q -m seed
  git -C "$T/seed" push -q "$T/origin.git" main
  git clone -q "$T/origin.git" "$T/repo"
  export TOKEFF_LEAN_REPO="$T/repo"
}

@test "readout: saving = lean spend x (1/0.156 - 1), with the cross-check and the exclusion count" {
  run bash "$S" --since 2026-09-01 --until 2026-09-08
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"Realized lean-worker saving, 2026-09-01 to 2026-09-08"* ]] || false
  [[ "$output" == *"5 \`workflow-lean\` worker contexts (4 workflow slots, 1 subagents) cost \$10.00"* ]] || false
  # 10 x (1/0.156 - 1) = 54.10; @5.5: 5 x 5.4103 = 27.05
  [[ "$output" == *"saving about \$54.10 list (\$27.05 at Opus 5.5) over 7 days"* ]] || false
  [[ "$output" == *"mean per workflow slot \$1.50 lean vs \$2.50 for \`workflow-subagent\` (2 slots)"* ]] || false
  [[ "$output" == *"leaves out 7 eval/probe worker contexts"* ]] || false
}

@test "falsify: before the window closes it says not yet and exits 1" {
  run bash "$S" --falsify --until "$(date -u -v+30d +%Y-%m-%d)"
  [ "$status" -eq 1 ] || false
  [[ "$output" == "not yet:"* ]] || false
}

@test "falsify: after the window, exit 0 only when origin/main's REPORT.md carries the readout" {
  fixture_repo "- **Realized lean-worker saving, 2026-01-01 to 2026-01-08** (…)"
  run bash "$S" --falsify --since 2026-01-01 --until 2026-01-08
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "landed:"* ]] || false
}

@test "falsify: after a failed attempt it waits out the retry window and starts nothing" {
  fixture_repo "no readout yet"
  mkdir -p "$TOKEFF_LEAN_STORE"
  date +%s > "$TOKEFF_LEAN_STORE/lean-readout.last-attempt"
  run bash "$S" --falsify --since 2026-01-01 --until 2026-01-08
  [ "$status" -eq 1 ] || false
  [[ "$output" == "retry pending:"* ]] || { echo "$output"; false; }
  [ ! -e "$TOKEFF_LEAN_STORE/lean-readout.pid" ] || false
}
