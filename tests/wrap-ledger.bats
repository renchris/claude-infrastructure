#!/usr/bin/env bats
# wrap-ledger.sh — pure-read Session-Close ledger computer (P0-2).
# Emits the worst-open rung (⛔>📤>🔧>📦>✅) and a --full block from LIVE git/gate/DoD reads
# ONLY — never self-report. The load-bearing assertion: committed-but-unlanded ⇒ 📦, NEVER a
# silent ✅ (the FM1 "park-and-call-it-done" hazard). Absent DoD ⇒ says so out loud, never ✅-silent.
#
# Fixtures are throwaway repos (bare "origin" + working clone) in BATS_TEST_TMPDIR so
# origin/main tracking + git cherry work with no network and no real repo touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LEDGER="$REPO/scripts/wrap-ledger.sh"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK"
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt; git add base.txt; git commit -q -m base
  git push -q -u origin main
  # DoD lives in a per-test dir by default; individual tests point WRAP_DOD_FILE where needed.
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"
  export WRAP_TRUNK="origin/main"
}

# read a KEY=value field from --machine output
field() { printf '%s' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

# ── 📦: committed-but-unlanded is 📦, NEVER a silent ✅ (the load-bearing case) ──
@test "committed-but-unlanded ⇒ RUNG=📦, never ✅" {
  echo more > more.txt; git add more.txt; git commit -q -m "unlanded work"   # ahead of origin/main, not pushed
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "📦" ]
  [ "$(field "$output" UNLANDED)" = "1" ]
  [ "$(field "$output" DIRTY)" = "0" ]
  printf '%s' "$output" | grep -q "^RUNG=📦"       # machine-parseable
  ! printf '%s' "$output" | grep -q "^RUNG=✅"
}

@test "committed-but-unlanded default readout is one 📦 line (not ✅)" {
  echo more > more.txt; git add more.txt; git commit -q -m "unlanded work"
  run bash "$LEDGER"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "📦"
  printf '%s' "$output" | grep -qi "ship"
  ! printf '%s' "$output" | grep -q "✅"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]   # exactly one line
}

# ── 🔧: dirty tree ──
@test "dirty tree ⇒ RUNG=🔧" {
  echo dirt >> base.txt   # unstaged modification
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" DIRTY)" = "1" ]
}

# ── 🔧: DoD remainder (clean + landed but scope items remain) ──
@test "clean+landed with unchecked DoD items ⇒ RUNG=🔧, REMAINDER>0" {
  local dod="$BATS_TEST_TMPDIR/dod-remainder.md"
  printf -- '- [x] item one\n- [ ] item two\n- [ ] item three\n' > "$dod"
  export WRAP_DOD_FILE="$dod"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" REMAINDER)" = "2" ]
  [ "$(field "$output" DOD)" = "present" ]
}

# ── ✅: clean + landed + DoD fully checked + gate green ──
@test "clean+landed+DoD-all-checked+gate-green ⇒ RUNG=✅" {
  local dod="$BATS_TEST_TMPDIR/dod-done.md"
  printf -- '- [x] item one\n- [x] item two\n' > "$dod"
  export WRAP_DOD_FILE="$dod"
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"   # gate green on HEAD
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" REMAINDER)" = "0" ]
  [ "$(field "$output" GATE)" = "green" ]
}

# ── ✅-eligible git state but DoD ABSENT ⇒ never a silent ✅ (says "no durable DoD") ──
@test "clean+landed but DoD absent ⇒ DOD=absent + loud 'no durable DoD' (never silent ✅)" {
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/does-not-exist.md"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" DOD)" = "absent" ]
  printf '%s' "$output" | grep -qi "no durable dod"
  run bash "$LEDGER"          # default readout also says it out loud
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi "no durable dod"
}

# ── 🔧: gate marker present but stale (points to an older commit than HEAD) ──
@test "gate marker stale (≠ HEAD) ⇒ RUNG=🔧, GATE=stale" {
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
  echo next > next.txt; git add next.txt; git commit -q -m advance; git push -q origin main  # HEAD moves past marker, still landed
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" GATE)" = "stale" ]
  [ "$(field "$output" RUNG)" = "🔧" ]
}

# ── --full emits the dense SESSION LEDGER block ──
@test "--full emits the SESSION LEDGER block with fact fields" {
  echo more > more.txt; git add more.txt; git commit -q -m "unlanded"
  run bash "$LEDGER" --full
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "SESSION LEDGER"
  printf '%s' "$output" | grep -qi "committed"
  printf '%s' "$output" | grep -qi "next"
}

# ── machine output surfaces the DoD file path it derived (transparency + derivation test) ──
@test "--machine reports the derived DOD_FILE path under WRAP_DOD_DIR" {
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  local f; f="$(field "$output" DOD_FILE)"
  case "$f" in "$BATS_TEST_TMPDIR/dod/"*.md) : ;; *) echo "unexpected DOD_FILE: $f" >&2; false ;; esac
}

# ── default readout = exactly ONE line ──
@test "default (no args) prints exactly one readout line" {
  run bash "$LEDGER"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

# ── fail-loud (never fail-silent-open): outside a git repo ⇒ non-zero + stderr, RUNG=? ──
@test "outside a git repo ⇒ fail-loud non-zero, never a silent ✅" {
  cd "$BATS_TEST_TMPDIR"
  mkdir -p notarepo; cd notarepo
  run bash "$LEDGER" --machine
  [ "$status" -ne 0 ]
  ! printf '%s' "$output" | grep -q "^RUNG=✅"
}
