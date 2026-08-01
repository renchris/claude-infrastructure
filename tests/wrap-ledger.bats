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
  # 👤 rung: keep the suite hermetic. No inherited session id, and a cc-backlog that cannot
  # resolve — so no test forks the REAL backlog (a peer edits it live) unless it opts in.
  unset WRAP_SESSION_ID CLAUDE_SESSION_ID
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/absent-cc-backlog"
  SID="sess-11111111-2222-3333-4444-555555555555"   # the 👤 cases' fixture session id
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
  ! printf '%s' "$output" | grep -q "✅" || false
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

# ─────────────────────────────────────────────────────────────────────────────────────────────
# 👤 — operator-only steps THIS SESSION filed and left unrun (G-CS-1).
# ✅ claims "safe to close, nothing unsaved" while steps only the operator can run sit filed.
# The count is SESSION-SCOPED by contract: this machine standingly carries ~200 blocked backlog
# items, and a rung counting those would fire at every close forever (MEMORY.md alarm-polarity).
# cc-backlog is STUBBED via CC_BACKLOG_BIN — a peer edits the real binary live, so a real-binary
# dependency would make this suite a function of their half-finished state.
# ─────────────────────────────────────────────────────────────────────────────────────────────

# a cc-backlog stub that prints $1 (a JSON array) for `list --blocked --json`
mk_backlog_stub() {
  local out="$BATS_TEST_TMPDIR/cc-backlog-stub"
  { printf '#!/usr/bin/env bash\n'; printf "printf '%%s\\\\n' '%s'\n" "$1"; } > "$out"
  chmod +x "$out"; printf '%s' "$out"
}

# one blocked item filed by session $1, with the two new carried fields (.run, .session)
blocked_json() {
  printf '[{"id":"B-77","project":"claude-infrastructure","title":"%s","status":"blocked","needs":"%s","run":"launchctl bootstrap gui/501 ~/Library/LaunchAgents/x.plist","session":"%s"}]' \
    "activate the dispatcher plist" "load the plist (operator-only)" "$1"
}

# the ✅-eligible git state every 👤 case starts from: clean · landed · DoD all checked · gate green
ok_state() {
  local dod="$BATS_TEST_TMPDIR/dod-ok.md"
  printf -- '- [x] item one\n- [x] item two\n' > "$dod"
  export WRAP_DOD_FILE="$dod"
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
}

# ── 1. ✅-eligible git state + ONE step filed by THIS session ⇒ 👤 (the whole point) ──
@test "clean+landed+DoD-satisfied with one session-filed operator step ⇒ RUNG=👤, YOURS=1" {
  ok_state
  export WRAP_SESSION_ID="$SID"
  CC_BACKLOG_BIN="$(mk_backlog_stub "$(blocked_json "$SID")")"; export CC_BACKLOG_BIN
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "👤" ]
  [ "$(field "$output" YOURS)" = "1" ]
  ! printf '%s' "$output" | grep -q "^RUNG=✅" || false
  run bash "$LEDGER"                       # default readout: one 👤 line naming the count
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  printf '%s' "$output" | grep -q "👤"
  printf '%s' "$output" | grep -qi "need you"
}

# ── 2. same git state, ZERO filed ⇒ still ✅ (the rung is not sticky) ──
@test "same git state with zero filed steps ⇒ RUNG=✅, YOURS=0" {
  ok_state
  export WRAP_SESSION_ID="$SID"
  CC_BACKLOG_BIN="$(mk_backlog_stub '[]')"; export CC_BACKLOG_BIN
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" YOURS)" = "0" ]
  [ "$(field "$output" YOURS_SRC)" = "WRAP_SESSION_ID" ]   # counted for real, not "could not tell"
}

# ── 3. THE always-fires guard: items filed by a DIFFERENT session are NOT ours ⇒ ✅ ──
@test "blocked items filed by a DIFFERENT session ⇒ RUNG=✅, YOURS=0 (never the standing pile)" {
  ok_state
  export WRAP_SESSION_ID="$SID"
  CC_BACKLOG_BIN="$(mk_backlog_stub "$(blocked_json "sess-someone-else")")"; export CC_BACKLOG_BIN
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" YOURS)" = "0" ]
  ! printf '%s' "$output" | grep -q "^RUNG=👤" || false
}

# ── 4. 🔧 still outranks 👤 — and the count is not even paid for (cost discipline) ──
@test "dirty tree + a filed operator step ⇒ RUNG=🔧 (👤 does not outrank loose ends)" {
  ok_state
  echo dirt >> base.txt
  export WRAP_SESSION_ID="$SID"
  CC_BACKLOG_BIN="$(mk_backlog_stub "$(blocked_json "$SID")")"; export CC_BACKLOG_BIN
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" YOURS_SRC)" = "skip" ]   # never forked on a path where it cannot decide
}

# ── 5. 📦 still outranks 👤 ──
@test "unlanded commit + a filed operator step ⇒ RUNG=📦 (👤 does not outrank parked work)" {
  ok_state
  echo more > more.txt; git add more.txt; git commit -q -m "unlanded work"
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
  export WRAP_SESSION_ID="$SID"
  CC_BACKLOG_BIN="$(mk_backlog_stub "$(blocked_json "$SID")")"; export CC_BACKLOG_BIN
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "📦" ]
  [ "$(field "$output" YOURS_SRC)" = "skip" ]
}

# ── 6. unresolvable session ⇒ fail-OPEN: ✅, and say "could not tell" (never a manufactured 👤) ──
@test "unresolvable session id ⇒ RUNG=✅, YOURS=0, YOURS_SRC=none" {
  ok_state
  CC_BACKLOG_BIN="$(mk_backlog_stub "$(blocked_json "$SID")")"; export CC_BACKLOG_BIN
  run bash "$LEDGER" --machine                 # no --session, no WRAP_SESSION_ID/CLAUDE_SESSION_ID
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" YOURS)" = "0" ]
  [ "$(field "$output" YOURS_SRC)" = "none" ]
  run bash "$LEDGER" --machine --session "$SID"   # the flag resolves it ⇒ the same state is 👤
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "👤" ]
  [ "$(field "$output" YOURS_SRC)" = "flag" ]
}

# ── 7. an unreadable backlog is fail-OPEN, never a block ──
@test "cc-backlog stub exits 1 ⇒ RUNG=✅, YOURS_SRC=error, exit 0 (fail-open)" {
  ok_state
  local stub="$BATS_TEST_TMPDIR/cc-backlog-broken"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$stub"; chmod +x "$stub"
  export CC_BACKLOG_BIN="$stub"
  export WRAP_SESSION_ID="$SID"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" YOURS)" = "0" ]
  [ "$(field "$output" YOURS_SRC)" = "error" ]
}

# ── the --full ledger carries the operator row, and the next-verb is NOT "continue" ──
@test "--full on 👤 shows the Yours row and a next-verb pointing at the OPERATOR block" {
  ok_state
  export WRAP_SESSION_ID="$SID"
  CC_BACKLOG_BIN="$(mk_backlog_stub "$(blocked_json "$SID")")"; export CC_BACKLOG_BIN
  run bash "$LEDGER" --full
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi "^Yours"
  printf '%s' "$output" | grep -q "👤"
  printf '%s' "$output" | grep -qi "OPERATOR"
  ! printf '%s' "$output" | grep -qi "Next:.*continue" || false
}
