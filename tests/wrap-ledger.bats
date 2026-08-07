#!/usr/bin/env bats
# wrap-ledger.sh — pure-read Session-Close ledger computer (P0-2).
# Emits the worst-open rung (⛔>📤>🔧>📦>🚀>👤>✅) and a --full block from LIVE git/gate/DoD reads
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
  cd "$WORK" || return 1
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
  # 🚀 rung: same hermetic discipline. An ABSENT live repo reads LIVE_SRC=unknown, which leaves the
  # rung exactly as it was — so every pre-existing case above is provably unaffected, and no test
  # forks git against the operator's REAL live checkout (a converger advances it on a 600s tick, so
  # a real-repo dependency would make this suite a function of that tick).
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-layer"
  export CC_MIGRATIONS_STATE="$BATS_TEST_TMPDIR/migrations"
  unset WRAP_LIVE_BUDGET_COMMITS WRAP_LIVE_BUDGET_MIN
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

# ── GATE is REPORTED, never the rung ──
# `gate-green` is a TRUNK-WIDE marker only the singleton postland verifier advances; the land path
# structurally cannot move it. Deciding a SESSION's close state on it made ✅ — and the whole
# "✅ SAFE TO CLOSE" certificate — unreachable in this repo for five days (marker pinned at 34e725d6
# since Jul 29, a sha not even an ancestor of HEAD), so the operator had to ask "are we good to
# close?" at every close. Contract per CLAUDE.md § Session Close Protocol: "your diff green +
# content-verified land is the standard — waiting on a trunk-wide stamp you do not control is not
# diligence, it is a hang." The marker must still be VISIBLE in the machine output.
@test "gate marker stale (≠ HEAD) ⇒ GATE=stale is REPORTED but the rung stays ✅" {
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
  echo next > next.txt; git add next.txt; git commit -q -m advance; git push -q origin main  # HEAD moves past marker, still landed
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" GATE)" = "stale" ]     # still surfaced — never silently dropped
  [ "$(field "$output" RUNG)" != "🔧" ]        # but it no longer manufactures a loose end
}
# A rung the session CAN act on still outranks ✅ — the change must not weaken a real 🔧.
@test "gate stale + a REAL loose end ⇒ still 🔧 (dirty tree outranks, gate change is scoped)" {
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
  echo next > next.txt; git add next.txt; git commit -q -m advance; git push -q origin main
  echo dirty > uncommitted.txt                 # a loose end the session owns
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

# ─────────────────────────────────────────────────────────────────────────────────────────────
# 🚀 — the LIVE LAYER: the enforcing store, one edge past trunk ("✅ moves one store right").
# ✅ used to terminate at TRUNK, but ~/.claude is a tree of per-file SYMLINKS into the live
# checkout, so what the machine EXECUTES is that checkout's tree — not origin/main. A session could
# close "✅ Complete & live on trunk" while the box ran code from 91 commits ago (measured
# 2026-08-07): landed and INERT. Two properties are load-bearing and each gets both directions:
#   (1) BOUNDED — the converger runs on a 600s tick, so a session that lands and closes at once
#       ALWAYS sees live < HEAD. Within budget that must stay ✅, or the rung fires at every close
#       and carries zero bits (MEMORY.md alarm-polarity). Past budget it must fire.
#   (2) INAPPLICABLE ELSEWHERE — this ledger runs in every repo. A different origin, or a live repo
#       that cannot be read, must leave the rung EXACTLY as it was and never manufacture a 🚀.
# ─────────────────────────────────────────────────────────────────────────────────────────────

# a live-layer fixture: a SECOND clone of the SAME origin, so the applicability gate opens. `-b main`
# is required — the bare origin's HEAD may still name refs/heads/master, and a clone landing on an
# unborn branch has no HEAD to compare, so the fixture would read `unknown` and prove nothing.
mk_live() {
  local dir="$BATS_TEST_TMPDIR/live"
  git clone -q -b main "$ORIGIN" "$dir"
  printf '%s' "$dir"
}

# advance trunk by $1 commits (committed AND pushed, so the session itself stays ✅-eligible), then
# let the live clone SEE them without moving its own HEAD — exactly the deploy lag this rung reads.
# The fetch is the fixture's job: the ledger is pure-read and never fetches.
advance_trunk() {
  local n="$1" i=1
  while [ "$i" -le "$n" ]; do
    echo "adv$i" > "adv$i.txt"; git add "adv$i.txt"; git commit -q -m "advance $i"
    i=$((i + 1))
  done
  git push -q origin main
  git -C "$WRAP_LIVE_REPO" fetch -q origin
}

# commit + push with a COMMITTER date $1 seconds in the past — the TIME-budget lever, isolated from
# the commit-count lever (one commit of lag is far under the 25-commit default).
commit_aged() {
  local age="$1" ts
  ts=$(( $(date +%s) - age ))
  echo aged > aged.txt; git add aged.txt
  GIT_AUTHOR_DATE="$ts +0000" GIT_COMMITTER_DATE="$ts +0000" git commit -q -m "aged work"
  git push -q origin main
}

# a failed-migration record: the converger reporting it could NOT put a landed conclusion into its
# enforcing store (settings.json, a plist, PATH).
mk_failed_migration() {
  mkdir -p "$CC_MIGRATIONS_STATE/failed"
  printf '{"id":"M-1","verdict":"failed","store":"settings.json"}\n' > "$CC_MIGRATIONS_STATE/failed/m-1.json"
}

# ── 1. POSITIVE CONTROL: the live layer is at/above HEAD ⇒ ✅ is still reachable ──
@test "live layer at/above HEAD ⇒ LIVE=1, LIVE_SRC=ok, RUNG=✅" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" LIVE)" = "1" ]
  [ "$(field "$output" LIVE_SRC)" = "ok" ]
  [ "$(field "$output" LIVE_SHA)" = "$(git rev-parse HEAD)" ]
}

# ── 2. behind but WITHIN budget ⇒ still ✅, with the fact attached (the alarm-polarity bound) ──
@test "live behind but within the converge budget ⇒ RUNG=✅ + converging note, never 🚀" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  advance_trunk 1
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" LIVE)" = "0" ]
  [ "$(field "$output" LIVE_SRC)" = "behind" ]
  [ "$(field "$output" LIVE_LAG)" = "1" ]
  run bash "$LEDGER"                       # the one line says it out loud, and is still ONE line
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  printf '%s' "$output" | grep -qi "converging"
  ! printf '%s' "$output" | grep -q "🚀" || false
}

# ── 3. past the COMMIT budget ⇒ 🚀, and the next-verb points at the converger ──
@test "live behind PAST the commit budget ⇒ RUNG=🚀 (landed but not live)" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  export WRAP_LIVE_BUDGET_COMMITS=2
  advance_trunk 3                          # 3 > 2, while the commits are seconds old (time lever off)
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🚀" ]
  [ "$(field "$output" LIVE_LAG)" = "3" ]
  run bash "$LEDGER"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  printf '%s' "$output" | grep -q "🚀"
  printf '%s' "$output" | grep -qi "not live"
  run bash "$LEDGER" --full
  printf '%s' "$output" | grep -q "PAST budget"
  printf '%s' "$output" | grep -qi "deploy-live"      # the next verb is the converger, not /ship
}

# ── 4. past the TIME budget with lag UNDER the commit budget ⇒ 🚀 (whichever trips FIRST, not AND) ──
@test "live behind PAST the time budget, lag under the commit budget ⇒ RUNG=🚀" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  commit_aged 7200                          # HEAD committed 2h ago; the default budget is 60 min
  git -C "$WRAP_LIVE_REPO" fetch -q origin
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "behind" ]
  [ "$(field "$output" LIVE_LAG)" = "1" ]   # 1 ≤ 25 — the commit budget is NOT what tripped
  [ "$(field "$output" RUNG)" = "🚀" ]
}

# ── 5. a FAILED migration is independent of lag: live AT HEAD and it still fires ──
@test "failed migration with the live layer at HEAD ⇒ RUNG=🚀, MIG_FAILED=1" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  mk_failed_migration
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "ok" ]   # nothing is behind…
  [ "$(field "$output" MIG_FAILED)" = "1" ]
  [ "$(field "$output" RUNG)" = "🚀" ]       # …and it fires anyway: no tick clears a failed migration
  run bash "$LEDGER"
  printf '%s' "$output" | grep -qi "migration"
}

# ── 6. THE no-op guarantee for every other repo: a different origin URL ⇒ n-a, rung UNCHANGED ──
# The fixture is deliberately set to 🚀 twice over — HEAD is 2h old AND a migration has failed — so
# a gate that failed to hold would be caught here rather than passing vacuously.
@test "live repo with a DIFFERENT origin URL ⇒ LIVE_SRC=n-a, RUNG unchanged, MIG not even counted" {
  ok_state
  local foreign_origin="$BATS_TEST_TMPDIR/foreign.git" foreign="$BATS_TEST_TMPDIR/foreign-live"
  git init -q --bare "$foreign_origin"
  git clone -q "$foreign_origin" "$foreign"
  git -C "$foreign" config user.email tester@example.com
  git -C "$foreign" config user.name tester
  git -C "$foreign" checkout -q -b main
  echo other > "$foreign/other.txt"; git -C "$foreign" add other.txt; git -C "$foreign" commit -q -m other
  export WRAP_LIVE_REPO="$foreign"
  mk_failed_migration
  commit_aged 7200
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "n-a" ]
  [ "$(field "$output" MIG_FAILED)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  ! printf '%s' "$output" | grep -q "^RUNG=🚀" || false
  run bash "$LEDGER" --full
  printf '%s' "$output" | grep -qi "not the live layer"
}

# ── 7. an unreadable live repo is `unknown`, never `n-a` and never a manufactured rung ──
@test "WRAP_LIVE_REPO pointing at a non-repo ⇒ LIVE_SRC=unknown, RUNG unchanged, never 🚀" {
  ok_state
  mkdir -p "$BATS_TEST_TMPDIR/not-a-repo"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/not-a-repo"
  mk_failed_migration
  commit_aged 7200
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "unknown" ]
  [ "$(field "$output" MIG_FAILED)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  ! printf '%s' "$output" | grep -q "^RUNG=🚀" || false
}

# ── 8. worse rungs are unaffected: the live read is neither PAID FOR nor APPLIED on 🔧/📦 ──
@test "dirty tree with a past-budget live layer ⇒ RUNG=🔧 and LIVE_SRC=skip" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  export WRAP_LIVE_BUDGET_COMMITS=0
  advance_trunk 3                            # past budget — and it must still not decide this rung
  echo dirt >> base.txt
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" LIVE_SRC)" = "skip" ]
}

@test "unlanded commit with a past-budget live layer ⇒ RUNG=📦 and LIVE_SRC=skip (📦 outranks 🚀)" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  export WRAP_LIVE_BUDGET_COMMITS=0
  advance_trunk 3
  echo parked > parked.txt; git add parked.txt; git commit -q -m "unlanded work"   # NOT pushed
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "📦" ]
  [ "$(field "$output" LIVE_SRC)" = "skip" ]
}

# ── 10. THE NO-OP GUARANTEE, PINNED FROM THE OUTSIDE ──
# #6 asserts the FIELDS a foreign repo produces. This asserts what an operator in a foreign repo
# actually SEES: the readout must be BYTE-IDENTICAL whether the live-layer seam is unset, pointed at
# a repo with a different origin, or pointed at something unreadable. Those three are every state a
# non-live-layer repo can be in, and if any of them moved the one line, the rung would be reachable
# from a normal close in another repo — the property the whole change lives or dies on.
# The fixture is LOADED FOR 🚀 — HEAD committed 2h ago (time budget blown) AND a migration has
# FAILED — so a gate that leaked in any of the three states moves at least one of these readouts.
@test "foreign repo: readout is BYTE-IDENTICAL with and without WRAP_LIVE_REPO (🚀 unreachable)" {
  ok_state
  mk_failed_migration
  commit_aged 7200
  local a b c

  # (a) the seam UNSET — the REAL default path. This is the control on purpose: it is the exact
  # code path a session in any other repo takes, and it must be inert there. Read-only (one
  # `git config --get`), and its verdict is stable by construction — a local bare-repo fixture
  # origin can never equal the live layer's remote URL.
  unset WRAP_LIVE_REPO
  a="$(bash "$LEDGER")"

  # (b) the seam pointed at a real repo with a DIFFERENT origin URL ⇒ n-a
  local foreign_origin="$BATS_TEST_TMPDIR/foreign2.git" foreign="$BATS_TEST_TMPDIR/foreign2-live"
  git init -q --bare "$foreign_origin"
  git clone -q "$foreign_origin" "$foreign"
  git -C "$foreign" config user.email tester@example.com
  git -C "$foreign" config user.name tester
  git -C "$foreign" checkout -q -b main
  echo other > "$foreign/other.txt"; git -C "$foreign" add other.txt; git -C "$foreign" commit -q -m other
  export WRAP_LIVE_REPO="$foreign"
  b="$(bash "$LEDGER")"

  # (c) the seam pointed at something unreadable ⇒ unknown
  mkdir -p "$BATS_TEST_TMPDIR/not-a-repo-2"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/not-a-repo-2"
  c="$(bash "$LEDGER")"

  [ "$a" = "$b" ]
  [ "$b" = "$c" ]
  # …and what they agree ON is a close that never mentions the live layer at all.
  ! printf '%s' "$b" | grep -q "🚀" || false
  ! printf '%s' "$b" | grep -qi "live layer" || false
  ! printf '%s' "$b" | grep -qi "converging" || false
}

# ── 9. the --full block carries the Live layer row between Unlanded and Yours ──
@test "--full carries the Live layer row with its budget verdict" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  advance_trunk 1
  run bash "$LEDGER" --full
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "^Live layer:"
  printf '%s' "$output" | grep -q "BEHIND"
  printf '%s' "$output" | grep -q "within budget"
}

# ── 10. LADDER PARITY — a rung the producer can EMIT must reach the docs that ROUTE it ──────────
#
# THE DEFECT THIS PINS (backlog 804e832f4283; docs/plans/INERTNESS_FACES_3_4_DELTA.md). Adding the
# 🚀 rung to this script was ONE edit; teaching every consumer what to DO with it was four more,
# and they were made by hand, one session apart. Three landed (CLAUDE.md's ladder,
# hooks/completion-assert.sh, hooks/operator-readout.sh) and one did not: `commands/wrap.md` — the
# PULL-path renderer — still documented `⛔ > 📤 > 🔧 > 📦 > ✅` and told the reader "if the ledger
# says 🔧 or 📦, the work is not done". A 🚀 matches neither term, so it fell through as done. That
# is the FAIL-OPEN direction: the rung built to stop a close asserting `✅ Complete & live on trunk`
# over a stale live layer was, on that path, invisible.
#
# WHY IT LIVES IN *THIS* SUITE and not its own file: scripts/gate-select.sh maps a changed file to
# `tests/<stem>.bats` by name (`naming()`), so a guard here is GUARANTEED selected the moment
# wrap-ledger.sh grows a rung — which is the only edit that can create this drift. A separate
# tests/rung-ladder-parity.bats would ride clause (e)'s token match instead, and be inert exactly
# when it matters. The other drift direction is covered too: CLAUDE.md and commands/*.md are index
# files (gate-select.sh:174), so editing them selects FULL.
#
# The assertion is emitted ⊆ documented, NOT equality — ⛔ and 📤 are model-state overlays this
# script cannot derive from git, so they appear in the ladders without ever being emitted here.

# every rung this script can ASSIGN — the producer's own truth, never a hand-kept list
rungs_emitted() { /usr/bin/grep -o 'RUNG="[^"]*"' "$LEDGER" | sed 's/^RUNG="//; s/"$//' | sort -u; }

# the ONE ladder line in a doc: it carries the priority ordering, so a rung dropped from it is a
# rung the reader cannot route. Checking the whole FILE would pass vacuously — every one of these
# docs discusses rungs in prose elsewhere.
ladder_line() { /usr/bin/grep -n 'priority' "$1" | /usr/bin/grep '⛔'; }

# rungs absent from $1's ladder line, one per line (empty = parity holds)
missing_from_ladder() {
  local line r; line="$(ladder_line "$1")"
  for r in $(rungs_emitted); do
    case "$line" in *"$r"*) ;; *) printf '%s\n' "$r" ;; esac
  done
}

@test "parity: the extractor is not vacuous — it finds every rung this script assigns" {
  # POSITIVE CONTROL ON THE DENOMINATOR. An extractor that silently returned nothing would make
  # every parity test below pass while asserting exactly nothing, so pin the SET, not just a count.
  run rungs_emitted
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c .)" -eq 5 ]
  local r; for r in '✅' '🔧' '📦' '🚀' '👤'; do
    printf '%s' "$output" | grep -q "$r" || { echo "extractor lost rung $r"; false; }
  done
}

@test "parity: every emitted rung appears in CLAUDE.md's ladder" {
  run missing_from_ladder "$REPO/CLAUDE.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "CLAUDE.md ladder is missing: $output"; false; }
}

@test "parity: every emitted rung appears in commands/wrap.md's ladder" {
  run missing_from_ladder "$REPO/commands/wrap.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ] || { echo "commands/wrap.md ladder is missing: $output"; false; }
}

# ── the controls: a guard that cannot go RED is decoration ───────────────────────────────────────
# Both replay the REAL doc (copied, then mutated) rather than a hand-written approximation — an
# approximation passes vacuously and proves nothing about the file that actually ships.

@test "control: dropping 🚀 from a COPY of CLAUDE.md's ladder makes the guard FAIL" {
  local m="$BATS_TEST_TMPDIR/CLAUDE.md"
  sed 's/📦 > 🚀 > 👤/📦 > 👤/' "$REPO/CLAUDE.md" > "$m"
  ! cmp -s "$m" "$REPO/CLAUDE.md" || false # the mutation actually landed
  run missing_from_ladder "$m"
  [ "$output" = '🚀' ]
}

@test "control: dropping 🚀 from a COPY of commands/wrap.md's ladder makes the guard FAIL" {
  local m="$BATS_TEST_TMPDIR/wrap.md"
  sed 's/📦 > 🚀 > 👤/📦 > 👤/' "$REPO/commands/wrap.md" > "$m"
  ! cmp -s "$m" "$REPO/commands/wrap.md" || false
  run missing_from_ladder "$m"
  [ "$output" = '🚀' ]
}

@test "control: the ladder anchor matches EXACTLY ONE line in each doc" {
  # A `grep` anchor that matched two lines (or zero) would make the checks above read a line that
  # is not the ladder — the failure mode where a guard is green about the wrong subject.
  local f; for f in "$REPO/CLAUDE.md" "$REPO/commands/wrap.md"; do
    [ "$(ladder_line "$f" | grep -c .)" -eq 1 ] || { echo "anchor is not unique in $f"; false; }
  done
}
