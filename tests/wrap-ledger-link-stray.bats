#!/usr/bin/env bats
# wrap-ledger.sh § LINK_STRAY — the advisory surface for deploy-link-parity's STRAY leg, the one leg
# of that detector no executed auditor owns (backlog a4eec664b579). THE FACTS UNDER TEST:
#   · it is never run inline (the leg takes ~10 s; the ledger runs inside 5-10 s Stop bounds) — a
#     cache is read, and a stale/absent one starts ONE detached refresh;
#   · absent cache reads `?`, never a 0 that would read clean;
#   · it is ADVISORY: RUNG is identical with the field on and off;
#   · outside the live layer's source repo it is `n-a`.
# Hermetic: $HOME, the live repo, the cache and the parity script are all fixtures.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LEDGER="$REPO_ROOT/scripts/wrap-ledger.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK" 2>/dev/null
  cd "$WORK" || return 1
  git checkout -q -b main
  echo base > base.txt; git add base.txt
  git -c user.email=tester@example.com -c user.name=tester commit -q -m base
  git push -q -u origin main 2>/dev/null
  export WRAP_TRUNK="origin/main"
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/absent-cc-backlog"
  export CC_DECIDE_BIN="$BATS_TEST_TMPDIR/absent-cc-decide"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export WRAP_LIVE_ROOT="$BATS_TEST_TMPDIR/no-live-root"
  export CC_MIGRATIONS_STATE="$BATS_TEST_TMPDIR/migrations"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export WRAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/projects"
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teams"; mkdir -p "$CC_WF_TEAM_ROOTS"
  export CC_SESSIONS_BIN="$BATS_TEST_TMPDIR/absent-cc-sessions"
  export WRAP_CACHE=off
  unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID
  # The live repo IS this work tree (same origin ⇒ applicable), and the parity script is a stub
  # that records each run and prints the real summary-line shape.
  export WRAP_LIVE_REPO="$WORK"
  export WRAP_LINK_STRAY_CACHE="$BATS_TEST_TMPDIR/state/link-stray.last"
  RUNS="$BATS_TEST_TMPDIR/stub.runs"
  export WRAP_LINK_STRAY_SCRIPT="$BATS_TEST_TMPDIR/parity-stub.sh"
  printf '#!/bin/bash\necho run >> "%s"\necho "  stray-only: 2 live-extra · 4 actionable (forward, orphan and unmapped legs not run)"\nexit 1\n' \
    "$RUNS" > "$WRAP_LINK_STRAY_SCRIPT"
}

field() { printf '%s' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

@test "no cache yet: reads ?, never 0 — and a detached refresh fills it" {
  out="$(bash "$LEDGER" --machine 2>/dev/null)"
  [ "$(field "$out" LINK_STRAY)" = "?" ]
  for _ in $(seq 1 100); do [ -s "$WRAP_LINK_STRAY_CACHE" ] && break; sleep 0.1; done
  [ -s "$WRAP_LINK_STRAY_CACHE" ]
  out="$(bash "$LEDGER" --machine 2>/dev/null)"
  [ "$(field "$out" LINK_STRAY)" = "4" ]
  [[ "$(field "$out" LINK_STRAY_AGE)" =~ ^[0-9]+$ ]] || false
}

@test "a fresh cache is served and the parity script is NOT run" {
  mkdir -p "$(dirname "$WRAP_LINK_STRAY_CACHE")"
  printf '%s 7\n' "$(date +%s)" > "$WRAP_LINK_STRAY_CACHE"
  out="$(bash "$LEDGER" --machine 2>/dev/null)"
  [ "$(field "$out" LINK_STRAY)" = "7" ]
  sleep 1
  [ ! -f "$RUNS" ]
}

@test "a stale cache is still reported, and starts a refresh" {
  mkdir -p "$(dirname "$WRAP_LINK_STRAY_CACHE")"
  printf '%s 9\n' "$(( $(date +%s) - 90000 ))" > "$WRAP_LINK_STRAY_CACHE"
  out="$(bash "$LEDGER" --machine 2>/dev/null)"
  [ "$(field "$out" LINK_STRAY)" = "9" ]
  for _ in $(seq 1 100); do [ -f "$RUNS" ] && break; sleep 0.1; done
  [ -f "$RUNS" ]
}

@test "ADVISORY: RUNG and READOUT are identical with the field on and off" {
  mkdir -p "$(dirname "$WRAP_LINK_STRAY_CACHE")"
  printf '%s 50\n' "$(date +%s)" > "$WRAP_LINK_STRAY_CACHE"
  on="$(bash "$LEDGER" --machine 2>/dev/null)"
  off="$(WRAP_LINK_STRAY=off bash "$LEDGER" --machine 2>/dev/null)"
  [ "$(field "$on" LINK_STRAY)" = "50" ]
  [ "$(field "$off" LINK_STRAY)" = "n-a" ]
  [ "$(field "$on" RUNG)" = "$(field "$off" RUNG)" ]
  [ "$(field "$on" READOUT)" = "$(field "$off" READOUT)" ]
}

@test "outside the live layer's source repo it is n-a and nothing runs" {
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-layer"
  out="$(bash "$LEDGER" --machine 2>/dev/null)"
  [ "$(field "$out" LINK_STRAY)" = "n-a" ]
  sleep 1
  [ ! -f "$RUNS" ]
}
