#!/usr/bin/env bats
# shellcheck disable=SC2016  # the bash -c bodies expand their own positional args
# attribution-keys.bats — the three faces of the attribution API agree (wave W2 of
# docs/plans/ZERO_HITL_ROTATION.md): lib/billing.sh (sourced by shell callers, incl. launchd jobs
# under /bin/bash 3.2), bin/cc-billing and the scripts/lib/billing.py module answer the same three
# keys for the same session, and the shell fast path that skips python gives python's answer.
#
# Contracts held here:
#   · for every case in the matrix, cc_billing_of / cc_identity_of / cc_home_of == `cc-billing --json`
#     == billing.billing_of / identity_of / home_of
#   · the fast path answers with python unavailable when the caller names its home and the switch is
#     off, the ledger is absent, or the ledger never mentions the sid; it defers to python otherwise
#   · lib/billing.sh sources and answers under /bin/bash 3.2 with `set -u`
# RED-proof: (a) file-absence: before W2 none of the three faces existed. (b) mutants on a scratch
# copy, 2026-10-26: a fast path that skips the ledger grep reds 3.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd -P)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_LANES_DIR="$BATS_TEST_TMPDIR/lanes"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"
  export CC_ACCOUNTS_JSON="$REPO/accounts.json"
  unset CC_BILLING CC_BILLING_LEDGER
  mkdir -p "$HOME" "$CC_LANES_DIR" "$CC_REGISTRY_DIR"
  LEDGER="$CC_LANES_DIR/ledger.jsonl"
  printf '{"paneUUID":"1","session_id":"S1","account":"claude-tertiary","startedAt":1}\n' > "$CC_REGISTRY_DIR/1.json"
  printf '{"t":100,"sid":"S1","state":"committed","billing":"next4","prev_billing":"next3"}\n' > "$LEDGER"
  # a python3 that fails, for proving the fast path never forks one
  NOPY="$BATS_TEST_TMPDIR/nopy"
  # shellcheck source=helpers/cc-stub.bash disable=SC1091  # resolved at runtime beside this file
  . "$BATS_TEST_DIRNAME/helpers/cc-stub.bash"
  mkdir -p "$NOPY"
  cc_stub "$NOPY" python3 $'#!/bin/sh\necho python-called >&2\nexit 99\n'
}

# keys <sid> <at> <home>: "billing identity home" from each face, one line per face.
keys() {
  local sid="$1" at="$2" home="$3"
  bash -c '. "$1/lib/billing.sh"; printf "%s %s %s\n" "$(cc_billing_of "$2" "$3" "$4")" "$(cc_identity_of "$2" "$3" "$4")" "$(cc_home_of "$2" "$4")"' _ "$REPO" "$sid" "$at" "$home"
  local a=() ; [ -n "$at" ] && a+=(--at "$at"); [ -n "$home" ] && a+=(--home "$home")
  "$REPO/bin/cc-billing" --sid "$sid" "${a[@]}" --json | jq -r '[.billing,.identity,.home]|join(" ")'
  python3 -I -c '
import sys; sys.path.insert(0, sys.argv[1] + "/scripts/lib"); import billing
sid, at, home = sys.argv[2], (billing.parse_t(sys.argv[3]) if sys.argv[3] else None), (sys.argv[4] or None)
print(billing.billing_of(sid, at, home), billing.identity_of(sid, at, home), billing.home_of(sid, home))' \
    "$REPO" "$sid" "$at" "$home"
}

@test "shell, CLI and module agree across the matrix" {
  local sw sid at home out
  for sw in 0 1; do
    for sid in S1 S9; do
      for at in 50 150; do
        # shellcheck disable=SC2088  # a literal ~ is a spelling under test
        for home in "" "$HOME/.claude" "~/.claude-tertiary" claude4 fable2 bogus; do
          out=$(CC_BILLING=$sw keys "$sid" "$at" "$home")
          [ "$(printf '%s\n' "$out" | sort -u | wc -l | tr -d ' ')" -eq 1 ] \
            || { echo "DISAGREE sw=$sw sid=$sid at=$at home=$home"; echo "$out"; return 1; }
        done
      done
    done
  done
  # and the matrix reached the interesting answers, not only one
  [ "$(CC_BILLING=1 keys S1 150 "" | head -1)" = "next4 unknown next3" ]
  [ "$(CC_BILLING=1 keys S1 50 "" | head -1)" = "next3 home next3" ]
  [ "$(CC_BILLING=0 keys S1 150 "" | head -1)" = "next3 home next3" ]
  [ "$(keys S9 "" claude4 | head -1)" = "next4 home next4" ]
}

@test "fast path answers with no python when the ledger cannot speak" {
  # switch off; ledger mentions nobody's sid; ledger absent
  run env PATH="$NOPY:/usr/bin:/bin" CC_BILLING=0 bash -c '. "$1/lib/billing.sh"; cc_billing_of S1 "" "$2"; cc_identity_of S1 "" "$2"' _ "$REPO" "$HOME/.claude-tertiary"
  [ "$output" = $'next3\nhome' ]
  run env PATH="$NOPY:/usr/bin:/bin" CC_BILLING=1 bash -c '. "$1/lib/billing.sh"; cc_billing_of S7 "" claude2' _ "$REPO"
  [ "$output" = next2 ]
  rm "$LEDGER"
  run env PATH="$NOPY:/usr/bin:/bin" CC_BILLING=1 bash -c '. "$1/lib/billing.sh"; cc_billing_of S1 "" claude3' _ "$REPO"
  [ "$output" = next3 ]
}

@test "fast path defers to python when the ledger mentions the sid" {
  run env PATH="$NOPY:/usr/bin:/bin" CC_BILLING=1 bash -c '. "$1/lib/billing.sh"; cc_billing_of S1 "" claude3 2>&1' _ "$REPO"
  # the failing python proves it was asked; the shell then says unknown, never home
  [ "$output" = unknown ]
  run env CC_BILLING=1 bash -c '. "$1/lib/billing.sh"; cc_billing_of S1 "" claude3' _ "$REPO"
  [ "$output" = next4 ]
}

@test "lib/billing.sh sources and answers under /bin/bash 3.2 with set -u" {
  run /bin/bash -c 'set -u; . "$1/lib/billing.sh"; cc_billing_of S1 "" claude3; cc_home_of S1; cc_billing_on && echo on || echo off; cc_billing_json S1 | /usr/bin/python3 -c "import json,sys; print(json.load(sys.stdin)[\"billing\"])"' _ "$REPO"
  [ "$status" -eq 0 ]
  [ "$output" = $'next3\nnext3\noff\nnext3' ]
  CC_BILLING=on run /bin/bash -c 'set -u; . "$1/lib/billing.sh"; cc_billing_of S1; cc_identity_of S1' _ "$REPO"
  [ "$output" = $'next4\nunknown' ]
}
