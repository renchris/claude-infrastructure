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
  # W2 hermeticity: the custody counter resolves the repo's own bin/cc-custody, whose store
  # defaults under $HOME — unfixtured, every test here would read the OPERATOR's live custody
  # ledger (the suite-is-a-function-of-who-runs-it class). An empty fixture dir = counted zero.
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
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
  # ⛔ rung: the same hermetic discipline, and it matters MORE here — ⛔ is computed
  # UNCONDITIONALLY (it outranks every rung, so it cannot ride the ✅-eligible path), and this
  # machine standingly carries ~21 open decision packets, several of them class-C. An unresolvable
  # cc-decide reads BLOCKED_SRC=error and leaves the rung exactly as it was, so every pre-existing
  # case above is provably unaffected and none of them forks the operator's REAL store.
  export CC_DECIDE_BIN="$BATS_TEST_TMPDIR/absent-cc-decide"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # ◎ goal term: same hermetic discipline. On the PULL path (--full/--readout/--goal) the ledger
  # resolves a transcript from a session id when none is passed — and $CLAUDE_CODE_SESSION_ID IS
  # set in an ordinary tool-call shell, so without these two lines every --full test on the
  # operator's box would fork a find and read that session's REAL transcript (the
  # suite-is-a-function-of-who-runs-it class). An empty roots dir = nothing to find = GOAL_SRC=none.
  unset CLAUDE_CODE_SESSION_ID
  export WRAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/projects"
}

# goal_status transcript fixtures — the record dictionary is hooks/lib/goal-state.sh's header.
g_arm()   { printf '{"type":"attachment","timestamp":"%s","attachment":{"type":"goal_status","met":false,"sentinel":true,"condition":"%s"}}\n' "$2" "$1"; }
g_unmet() { printf '{"type":"attachment","timestamp":"%s","attachment":{"type":"goal_status","met":false,"condition":"%s"}}\n' "$2" "$1"; }
g_met()   { printf '{"type":"attachment","timestamp":"%s","attachment":{"type":"goal_status","met":true,"condition":"%s"}}\n' "$2" "$1"; }
g_now()   { date -u +%Y-%m-%dT%H:%M:%S.000Z; }

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

# ── DIRTY IS CONTENT-TRUTHFUL, NOT THE STAT BIT (2026-08-07, backlog 1162f51b1cf3) ───────────────
# THE FILED CLAIM: "completion-assert inflates 'dirty tree' — 10 of 17 files were STAT-dirty only
# (byte-identical, touched at one instant); `git update-index --refresh` drops 17→7 ⇒ refresh, or
# use `git diff --quiet`, not the stat bit." It is REFUTED, and pinned here so that nobody
# implements it later and turns a non-bug into a real one.
#
# The premise names an instrument that is not in this path. `git status --porcelain` — the ONLY
# dirty read this ledger makes (wrap-ledger.sh's "Dirty tree" block) — REFRESHES the index: on a
# stat-mismatched entry git re-hashes the file and compares the OID, so byte-identical-but-touched
# files are reported CLEAN. Measured on git 2.54.0 with a positive control: `git diff-index` (the
# plumbing read that DOES trust the stat bit) saw 10 files at the same instant `git status
# --porcelain` saw 0 — and the same held with a stale `index.lock` and a read-only `.git`. A
# repo-wide census found ZERO `git diff-index` / `git diff-files` consumers, so the stat-bit reader
# the item describes exists nowhere in the close path.
#
# Both prescribed remedies are worse than the bug:
#   · `git update-index --refresh` is a strict NO-OP here — `git status` already refreshes AND
#     writes the index back (measured: the index hash changes across one `status`, and a following
#     `diff-index` drops to 0). It would add a fork to every Stop hook and change no verdict.
#   · `git diff --quiet` is a REGRESSION — it compares worktree against index, so it is blind to
#     untracked AND staged-but-uncommitted files. Those are not corner cases in this repo: eight
#     staged orphan assets blocked every /ship in wt-149789b69fc4 (2026-07-31) and the same shape
#     was still sitting in wt-1162f51b1cf3 when this was written. Swapping to it would report a
#     clean tree over unsaved work — the false ✅ this whole ledger exists to prevent.
#
# One test pins the refutation; two pin what `git diff --quiet` would lose.
@test "stat-only dirt (byte-identical, mtime bumped) ⇒ DIRTY=0, never a phantom 🔧" {
  local dod="$BATS_TEST_TMPDIR/dod-done.md"
  printf -- '- [x] item one\n' > "$dod"
  export WRAP_DOD_FILE="$dod"
  echo a > a.txt; echo b > b.txt; echo c > c.txt
  git add a.txt b.txt c.txt; git commit -q -m "three files"; git push -q origin main
  touch -t 202601011200 a.txt b.txt c.txt      # stat now differs; bytes are identical

  # POSITIVE CONTROL — without it this fixture passes VACUOUSLY whenever the files are not
  # actually stat-dirty (any earlier `git status` silently refreshes them clean, which is exactly
  # how the first hand-run of this probe "passed" while measuring nothing). `diff-index` is the
  # plumbing read that trusts the stat bit, so it must see all three before the assertion means
  # anything. It is also a pure read — it does not write the index — so it cannot launder the
  # fixture it is checking.
  [ "$(git diff-index HEAD --name-only | grep -c .)" -eq 3 ]

  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" DIRTY)" = "0" ]
  [ "$(field "$output" DIRTY_N)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "staged-but-uncommitted ⇒ DIRTY=1, where 'git diff --quiet' reports clean" {
  echo staged > staged.txt; git add staged.txt        # in the index, never committed

  # The prescribed remedy's blind spot, asserted as a measured fact rather than an argument.
  run git diff --quiet
  [ "$status" -eq 0 ]                                 # ← "clean tree" per the prescription

  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" DIRTY)" = "1" ]
  [ "$(field "$output" RUNG)" = "🔧" ]
}

@test "untracked file ⇒ DIRTY=1, where 'git diff --quiet' reports clean" {
  echo orphan > orphan.txt                            # the worktree-orphan shape, verbatim

  run git diff --quiet
  [ "$status" -eq 0 ]

  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" DIRTY)" = "1" ]
  [ "$(field "$output" RUNG)" = "🔧" ]
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
#
# IT EDITS AN EXISTING FILE AND NEVER ADDS ONE (2026-08-09). An ADD breaches at lag 1 with NO budget,
# so the original fixture — which wrote a fresh adv$i.txt per commit — would make every budget
# assertion below fire for the added-file reason instead: #2 ("within budget ⇒ ✅") would simply go
# red, and #3/#4 would stay green while testing a lever they do not name. That is the control
# decaying into a vacuous one (MEMORY.md control-calibrated-to-implementation-decays). The edit case
# is the one the budget actually governs, so this is now the honest control for it, and
# advance_trunk_adding below is the deliberate lever for the other kind.
advance_trunk() {
  local n="$1" i=1
  while [ "$i" -le "$n" ]; do
    echo "adv$i" >> base.txt; git add base.txt; git commit -q -m "advance $i"
    i=$((i + 1))
  done
  git push -q origin main
  git -C "$WRAP_LIVE_REPO" fetch -q origin
}

# the ADD lever: $1 commits that each ADD a NEW tracked path. Identical LAG to advance_trunk, and a
# categorically different deployment state — ~/.claude is per-file symlinks, so a file that did not
# exist has no link and is not in the live checkout at all, which is why no budget may cover it.
advance_trunk_adding() {
  local n="$1" i=1
  while [ "$i" -le "$n" ]; do
    echo "new$i" > "newfile$i.txt"; git add "newfile$i.txt"; git commit -q -m "add $i"
    i=$((i + 1))
  done
  git push -q origin main
  git -C "$WRAP_LIVE_REPO" fetch -q origin
}

# commit + push with a COMMITTER date $1 seconds in the past — the TIME-budget lever, isolated from
# the commit-count lever (one commit of lag is far under the 25-commit default) AND from the
# added-file lever (it appends to a tracked file; a fresh aged.txt would have breached on the ADD
# and left the time budget untested).
commit_aged() {
  local age="$1" ts
  ts=$(( $(date +%s) - age ))
  echo aged >> base.txt; git add base.txt
  GIT_AUTHOR_DATE="$ts +0000" GIT_COMMITTER_DATE="$ts +0000" git commit -q -m "aged work"
  git push -q origin main
}

# the LIVE-LAYER time lever: put the live clone's HEAD ON a commit whose committer date is $1 seconds
# in the past, then move trunk ONE fresh pure-edit commit ahead of it. That is the quantity
# deploy-live.sh's hours budget reads (deploy-live.sh:1451-1452 — "the age of the commit the live
# layer is ON, which is the only clock that keeps ticking when trunk is quiet"). Isolated from the
# commit lever (lag 1, far under 25), from the added-file lever (it appends to a tracked file), and
# from the divergence lever (the live HEAD stays an ancestor of trunk, so LIVE_DIVERGED is 0).
# commit_aged above is its exact complement: that one ages OUR commit and leaves the live layer's
# fresh, and the pair differ in one variable — WHICH commit carries the age.
live_at_aged() {
  local age="$1" ts
  ts=$(( $(date +%s) - age ))
  echo agedlive >> base.txt; git add base.txt
  GIT_AUTHOR_DATE="$ts +0000" GIT_COMMITTER_DATE="$ts +0000" git commit -q -m "aged live commit"
  git push -q origin main
  git -C "${WRAP_LIVE_REPO:?live repo path required}" fetch -q origin
  git -C "$WRAP_LIVE_REPO" reset -q --hard origin/main   # the live layer is now ON the aged commit
  echo fresh >> base.txt; git add base.txt; git commit -q -m "fresh work"
  git push -q origin main
  git -C "$WRAP_LIVE_REPO" fetch -q origin
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
  [ "$(field "$output" LIVE_ADDS)" = "0" ]   # emitted on every path, so consumers never guess
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
  [ "$(field "$output" LIVE_ADDS)" = "0" ]   # an EDIT — the only kind the budget is entitled to cover
  run bash "$LEDGER"                       # the one line says it out loud, and is still ONE line
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  printf '%s' "$output" | grep -qi "converging"
  ! printf '%s' "$output" | grep -q "🚀" || false
}

# ── 2b. THE PAIRED OPPOSITE — the same lag of ONE commit, but the commit ADDS a file ⇒ 🚀 ──
# The defect this closes (backlog 99b715f31a98): #2 above and this test differ in exactly one
# variable — the KIND of change in the lag — and the ledger used to answer both with the ✅ of #2.
# Measured for real on scripts/lib/pane-spawn-log.sh: "BEHIND 7, within budget (25)", a plain OK,
# and every `command -v cc_log_pane_spawn` call site short-circuiting to nothing. An edit at lag N
# runs OLD; an add at lag N does not run at all, because ~/.claude is per-file symlinks and the file
# is in no tree the box can reach.
@test "live behind by ONE ADDING commit ⇒ RUNG=🚀 even deep inside the budget" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  advance_trunk_adding 1
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "behind" ]
  [ "$(field "$output" LIVE_LAG)" = "1" ]     # 1 ≤ 25, and seconds old — NEITHER budget tripped
  [ "$(field "$output" LIVE_ADDS)" = "1" ]
  [ "$(field "$output" RUNG)" = "🚀" ]
  run bash "$LEDGER"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  printf '%s' "$output" | grep -q "🚀"
  printf '%s' "$output" | grep -qi "NEW file"
  # the two sentences that would be FALSE here, pinned as absent: within-budget lag is not
  # "converging" when the file is missing, and the budget is not what tripped.
  ! printf '%s' "$output" | grep -qi "converging" || false
  ! printf '%s' "$output" | grep -qi "past its converge budget" || false
  run bash "$LEDGER" --full
  printf '%s' "$output" | grep -q "ABSENT"
  ! printf '%s' "$output" | grep -q "PAST budget" || false
  printf '%s' "$output" | grep -qi "deploy-live"
}

# ── 2c. THE SPAN — an add ANYWHERE in the lag, not only at the tip ──
# The read is a TREE diff (live tree vs HEAD tree), so a file added three commits ago and never
# touched since is still absent from the live layer and still counted. A tip-only check would have
# read 0 here and re-shipped the defect for every landing that is not the newest commit.
@test "an ADD buried under later edits still counts ⇒ RUNG=🚀" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  advance_trunk_adding 1
  advance_trunk 2                             # two pure edits on top; the add is no longer the tip
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_LAG)" = "3" ]
  [ "$(field "$output" LIVE_ADDS)" = "1" ]
  [ "$(field "$output" RUNG)" = "🚀" ]
}

# ── 2d. FAIL-OPEN: a live sha THIS repo cannot read is `?`, and `?` never manufactures a rung ──
# The added-file set is computed here, against our own object store, because the live repo may never
# have fetched our HEAD. The converse gap is this one: a live layer sitting on a commit we have
# never seen. That question was asked and NOT answered, so it must fall through to the budget and
# leave the pre-existing verdict untouched — the same law as LIVE_SRC=unknown. Without the guard the
# `-gt` would be a hard error thrown from inside a Stop hook.
@test "live layer on a sha this repo lacks ⇒ LIVE_ADDS=?, budget decides, never a manufactured 🚀" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  # a divergent commit that exists ONLY in the live clone — never pushed, so $WORK cannot resolve it
  git -C "${WRAP_LIVE_REPO:?live repo path required}" config user.email tester@example.com
  git -C "${WRAP_LIVE_REPO:?live repo path required}" config user.name tester
  echo live-only >> "$WRAP_LIVE_REPO/base.txt"
  git -C "$WRAP_LIVE_REPO" add base.txt
  git -C "$WRAP_LIVE_REPO" commit -q -m "live-only commit"
  advance_trunk_adding 1                      # …and OUR side adds a file, which would breach if read
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "behind" ]
  [ "$(field "$output" LIVE_ADDS)" = "?" ]
  # THE RUNG HERE WAS ✅ UNTIL 2026-08-25 (recycle #230), AND THAT WAS THE BLIND SPOT, NOT A CONTRACT.
  # This fixture's "divergent commit that exists ONLY in the live clone" is not merely a sha we lack
  # — it is a live layer `merge --ff-only` CANNOT ADVANCE, which is the one converge state no time
  # budget cures. LIVE_DIVERGED reads it now, so the rung is 🚀 on the DIVERGENCE.
  [ "$(field "$output" LIVE_DIVERGED)" = "1" ]
  [ "$(field "$output" RUNG)" = "🚀" ]
  # …and it is still NOT the `?` that raised it. That property is what this case has always been
  # for, and it survives the rung change: an unresolvable added-file read may not breach, so the
  # reason must never be the added file.
  run bash "$LEDGER"
  [ "$(printf '%s' "$output" | grep -ci "NEW file")" -eq 0 ]
  run bash "$LEDGER" --machine
  run bash "$LEDGER" --full
  printf '%s' "$output" | grep -qi "UNRESOLVED"
  # STDERR MUST BE EMPTY, and this is the assertion that makes the `!= "?"` guards load-bearing.
  # Dropping them does NOT change any verdict — `[ ? -gt 0 ]` exits 2, which an `if` reads as false,
  # so the budget still decides — it only makes bash print `integer expression expected` FROM INSIDE
  # A STOP HOOK, on every close, for a state that is not an error at all. Without this line the
  # guards are an untested site (MEMORY.md per-site-mutation-attributes-coverage) and the next
  # simplification deletes them.
  bash "$LEDGER" --machine >/dev/null 2>"$BATS_TEST_TMPDIR/err.txt"
  [ ! -s "$BATS_TEST_TMPDIR/err.txt" ]
}

# ── 2e. `?` composed with a REAL budget breach: the rung fires, on the budget's reason, quietly ──
# The unresolvable case must not just decline to breach — it must stay out of the way of the breach
# somebody else raises. This is the path that reaches the readout and next-verb compares (a `?` on
# a 🚀 close), which the test above cannot reach because its rung is ✅.
@test "LIVE_ADDS=? with the lag PAST budget ⇒ 🚀 on the BUDGET reason, stderr clean" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  export WRAP_LIVE_BUDGET_COMMITS=1
  advance_trunk 3                             # edits only; 3 > 1 ⇒ the COMMIT budget is what trips
  # THE `?` IS FORCED BY THE BOUND, NOT BY A LIVE-ONLY COMMIT (decoupled 2026-08-25, recycle #230).
  # This case's subject is "`?` stays out of the way of a breach somebody ELSE raises", so its
  # vehicle must not raise one itself. It used to make `?` with a divergent live commit — which
  # LIVE_DIVERGED now reads as its own no-budget breach, so the divergence would have become the
  # reason and the budget arm this case exists to exercise would never have been reached. The
  # timeout shim produces the identical `?` while leaving the live layer strictly BEHIND.
  mk_timeout_shim '--diff-filter=A' "$BATS_TEST_TMPDIR/shim-adds-2e"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/shim-adds-2e" ]     # the shim WAS on the executed path
  [ "$(field "$output" LIVE_ADDS)" = "?" ]
  [ "$(field "$output" LIVE_DIVERGED)" = "0" ]   # behind, never diverged ⇒ the budget must decide
  [ "$(field "$output" RUNG)" = "🚀" ]
  run bash "$LEDGER"
  printf '%s' "$output" | grep -qi "past its converge budget"
  ! printf '%s' "$output" | grep -qi "NEW file" || false
  bash "$LEDGER" --full >/dev/null 2>"$BATS_TEST_TMPDIR/err2.txt"
  [ ! -s "$BATS_TEST_TMPDIR/err2.txt" ]
}

# ── the BOUNDED-READ lever (2026-08-21, backlog 4fe8d531ce68) ────────────────────────────────────
# `_bounded` runs `timeout <secs> <cmd…>`. A shim FIRST on PATH makes ONE named read fail exactly
# the way a real timeout does — empty stdout, rc 124 — while every other read passes through
# untouched, so the fixture is a scalpel rather than a broken box.
#
# THE MARKER FILE IS THE CONTROL THAT CAN FAIL. Both cases below assert a `?`, and `?` is also what
# a shim that never ran would NOT produce — but a fixture that silently stopped reaching the read at
# all would leave the same green if the assertion were only on the ledger's output. So each test
# asserts the shim was on the executed path before reading its verdict (MEMORY.md
# positive-control-the-denominator). It also makes these cases deterministic on a runner with no
# coreutils: real `timeout` is homebrew-only on this box, and `command -v timeout` finds this one
# either way — without it, `_bounded` would silently run UNBOUNDED and both cases would go vacuous.
mk_timeout_shim() {                        # $1 = argv token to fail on ; $2 = marker path
  local dir="$BATS_TEST_TMPDIR/shimbin"
  mkdir -p "$dir"
  # ONE redirect, not four (SC2129) — and it is not only style here: a half-written shim would
  # still be +x and would exec as a broken interpreter, turning a real verdict into a crash.
  # `shift` drops _bounded's seconds argument; everything unmatched passes straight through.
  printf '#!/usr/bin/env bash\nshift\nfor a in "$@"; do case "$a" in %s) echo fired >> "%s"; exit 124 ;; esac; done\nexec "$@"\n' \
    "$1" "$2" > "$dir/timeout"
  chmod +x "$dir/timeout"
  PATH="$dir:$PATH"; export PATH
}

# ── 2f. THE ROW ITSELF: a FAILED added-file read is not a read of zero added files ──
# `_adds="$(_bounded … || true)"` swallowed the bound's rc, and a swallowed failure is
# INDISTINGUISHABLE at that point from a clean read of no adds: `_adds` is empty either way and
# `grep -c .` answers 0. 0 means "no added file" — the one converge lag that gets NO budget — so the
# ledger rendered ✅ SAFE TO CLOSE off a sensor that never reported. The `?` arm existed but was
# reachable only through the cat-file miss, never through the bound.
@test "bounded added-file read FAILS ⇒ LIVE_ADDS=?, never the phantom 0 that clears the close" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  advance_trunk_adding 1
  # CONTROL: unaided, this exact fixture SEES the add and breaches. Without it a `?` below could
  # come from a fixture that never had an add to find.
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_ADDS)" = "1" ]
  [ "$(field "$output" RUNG)" = "🚀" ]

  mk_timeout_shim '--diff-filter=A' "$BATS_TEST_TMPDIR/shim-adds"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/shim-adds" ]              # the shim WAS on the executed path
  [ "$(field "$output" LIVE_ADDS)" = "?" ]          # pre-fix: 0
  # ✅ is the CORRECT rung here and the point of the fix is not to change it: an unresolvable sensor
  # may not manufacture a rung either. What changes is that the close now SAYS the check did not
  # resolve, instead of asserting a clean bill of health over a question nothing answered.
  [ "$(field "$output" RUNG)" = "✅" ]
  run bash "$LEDGER" --full
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -qi "UNRESOLVED"
  bash "$LEDGER" --machine >/dev/null 2>"$BATS_TEST_TMPDIR/err-adds.txt"
  [ ! -s "$BATS_TEST_TMPDIR/err-adds.txt" ]
}

# ── 2h. DIVERGED vs BEHIND — the state the ledger could not tell apart (2026-08-25, recycle #230) ─
# LIVE_LAG is `rev-list --count HEAD..TRUNK`, a ONE-DIRECTIONAL distance, so it is blind to the
# ahead side by construction — and the ahead side is exactly what stops the converger, which
# advances with `merge --ff-only "$TARGET"` (scripts/deploy-live.sh:1969, its case B at :1808).
# MEASURED before the fix, against an isolated clone with ONE variable moved:
#     behind 4 / ahead 0  →  LIVE_SRC=behind LIVE_LAG=4  "converging (4 behind; within the budget)"
#     behind 4 / ahead 1  →  LIVE_SRC=behind LIVE_LAG=4  "converging (4 behind; within the budget)"
# BYTE-IDENTICAL, while `merge-base --is-ancestor HEAD TRUNK` answered rc 0 for the first and rc 1
# for the second. A converge BUDGET is a claim about TIME; time does not cure a divergence, so the
# second line asserted a bound over a state that was never going to clear on its own.
#
# ONE MUTANT PER SITE, and the sites are separable: the read (2h), the breach arm (2h vs 2i), the
# `?` guard (2j), and emission on the non-behind path (2k).
@test "live layer DIVERGED but lag INSIDE budget ⇒ 🚀 on the divergence, never 'within budget'" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  # CONTROL FIRST, and it must SPEAK: this same fixture, BEHIND ONLY, is ✅ + "within the converge
  # budget". Without it a 🚀 below could come from the lag, the clock or the fixture being broken.
  advance_trunk 2                                   # edits only, 2 < the default commit budget
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "behind" ]
  [ "$(field "$output" LIVE_DIVERGED)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  run bash "$LEDGER"
  printf '%s' "$output" | grep -qi "within the converge budget"

  # ONE VARIABLE MOVES: the live layer acquires a commit of its own. Nothing else changes — same
  # fixture, same trunk, same lag, same clock.
  git -C "${WRAP_LIVE_REPO:?live repo path required}" config user.email tester@example.com
  git -C "${WRAP_LIVE_REPO:?live repo path required}" config user.name tester
  echo diverged >> "$WRAP_LIVE_REPO/base.txt"
  git -C "$WRAP_LIVE_REPO" add base.txt
  git -C "$WRAP_LIVE_REPO" commit -q -m "live-only divergent commit"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "behind" ]
  [ "$(field "$output" LIVE_DIVERGED)" = "1" ]
  [ "$(field "$output" RUNG)" = "🚀" ]
  run bash "$LEDGER"
  printf '%s' "$output" | grep -qi "cannot advance it"
  # THE FALSE SENTENCE MUST BE GONE, not merely outranked — this is the whole defect.
  [ "$(printf '%s' "$output" | grep -ci "within the converge budget")" -eq 0 ]
  bash "$LEDGER" --machine >/dev/null 2>"$BATS_TEST_TMPDIR/err-div.txt"
  [ ! -s "$BATS_TEST_TMPDIR/err-div.txt" ]
}

# ── 2i. DIVERGENCE OUTRANKS THE ADDED FILE, because it is the cause the add is a symptom of ──
# An absent file is cured by the next converge tick; a divergence is what stops every converge tick.
# So when both hold the operator must be told the one that names the actual remedy.
@test "DIVERGED composed with a real added file ⇒ the divergence wins the sentence" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  # CONTROL: unaided, this fixture breaches on the ADD and says so.
  advance_trunk_adding 1
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_ADDS)" = "1" ]
  [ "$(field "$output" RUNG)" = "🚀" ]
  run bash "$LEDGER"
  printf '%s' "$output" | grep -qi "NEW file"

  git -C "${WRAP_LIVE_REPO:?live repo path required}" config user.email tester@example.com
  git -C "${WRAP_LIVE_REPO:?live repo path required}" config user.name tester
  echo diverged >> "$WRAP_LIVE_REPO/base.txt"
  git -C "$WRAP_LIVE_REPO" add base.txt
  git -C "$WRAP_LIVE_REPO" commit -q -m "live-only divergent commit"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_DIVERGED)" = "1" ]
  [ "$(field "$output" RUNG)" = "🚀" ]
  run bash "$LEDGER"
  printf '%s' "$output" | grep -qi "cannot advance it"
}

# ── 2j. A FAILED ahead read is not a read of "no divergence" ──
# Same law as LIVE_ADDS and LIVE_LAG (backlog 4fe8d531ce68): an unresolvable sensor may not breach
# and may not clear. 0 here would be the phantom that clears the close, because 0 is the one value
# that gets no budget scrutiny at all. The two ranges are deliberately distinct argv tokens —
# `origin/main..HEAD` for this read, `HEAD..origin/main` for the lag — so the shim cannot hit both.
@test "bounded ahead read FAILS ⇒ LIVE_DIVERGED=?, no manufactured 🚀, stderr clean" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  advance_trunk 2                                   # inside budget ⇒ ✅ unless something breaches
  # CONTROL: unaided, this fixture reads a real 0 and stays ✅ — so a `?` below is the read failing.
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_DIVERGED)" = "0" ]

  mk_timeout_shim 'origin/main..HEAD' "$BATS_TEST_TMPDIR/shim-ahead"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/shim-ahead" ]             # the shim WAS on the executed path
  [ "$(field "$output" LIVE_DIVERGED)" = "?" ]
  [ "$(field "$output" LIVE_LAG)" = "2" ]           # the SIBLING read is untouched — a scalpel
  [ "$(field "$output" RUNG)" = "✅" ]              # unresolvable may not manufacture a rung
  bash "$LEDGER" --machine >/dev/null 2>"$BATS_TEST_TMPDIR/err-ahead.txt"
  [ ! -s "$BATS_TEST_TMPDIR/err-ahead.txt" ]
}

# ── 2k. EMITTED ON EVERY PATH, so a consumer never has to guess whether the question was asked ──
# The read lives inside the `behind` branch, which is what preserves the no-op guarantee for every
# other LIVE_SRC — but the FIELD must still be printed, exactly as LIVE_ADDS is.
@test "LIVE_DIVERGED is emitted on the ok path too, as 0" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "ok" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" LIVE_DIVERGED)" = "0" ]
  printf '%s' "$output" | grep -q "^LIVE_DIVERGED="
}

# ── 2g. THE SIBLING READ, one line up: a FAILED lag read is not a lag of zero ──
# `lag="$(_bounded … || echo 0)"` had the same shape and a worse landing: 0 is INSIDE every commit
# budget, so an unreadable live layer rendered "converging (0 commit(s) behind; within the converge
# budget)" — a comparison reported as made against a number nothing read. LIVE_LAG feeds arithmetic,
# so it takes `?` plus a guard rather than LIVE_SRC=unknown: returning early would ALSO skip the
# added-file read, and an add breaches at lag 1, so one transient failure would have silenced a 🚀
# the other sensor could still have found.
@test "bounded lag read FAILS ⇒ LIVE_LAG=?, commit budget abstains, no phantom 'within budget'" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  export WRAP_LIVE_BUDGET_COMMITS=1
  advance_trunk 3                                   # edits only; 3 > 1 ⇒ the COMMIT budget is the lever
  # CONTROL: unaided, this fixture breaches ON THE COUNT — so the `?` below is the read failing,
  # not the lag being small.
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_LAG)" = "3" ]
  [ "$(field "$output" RUNG)" = "🚀" ]

  mk_timeout_shim 'HEAD..*' "$BATS_TEST_TMPDIR/shim-lag"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/shim-lag" ]
  [ "$(field "$output" LIVE_LAG)" = "?" ]           # pre-fix: 0
  [ "$(field "$output" LIVE_SRC)" = "behind" ]      # --is-ancestor still answered; only the COUNT failed
  [ "$(field "$output" LIVE_ADDS)" = "0" ]          # and the added-file read still ran — not skipped
  [ "$(field "$output" RUNG)" = "✅" ]
  run bash "$LEDGER"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  printf '%s' "$output" | grep -qi "UNREADABLE"
  # the two phantom comparisons, pinned as ABSENT — each asserts a bound against a lag nothing read
  ! printf '%s' "$output" | grep -qi "within the converge budget" || false
  run bash "$LEDGER" --full
  [ "$status" -eq 0 ]
  ! printf '%s' "$output" | grep -q "within budget (1)" || false
  bash "$LEDGER" --machine >/dev/null 2>"$BATS_TEST_TMPDIR/err-lag.txt"
  [ ! -s "$BATS_TEST_TMPDIR/err-lag.txt" ]
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
# THE CLOCK IS THE LIVE LAYER'S COMMIT, NOT THIS SESSION'S HEAD (2026-08-26, recycle #235). Until
# then this test aged THIS session's HEAD by 2h and left the live clone sitting on a base commit
# seconds old, then credited the pass to "past the time budget". That fixture makes only the WRONG
# arm reachable: the quantity deploy-live.sh budgets on is the age of the commit the LIVE LAYER IS
# ON, which was ZERO in it — so the arm's only positive control proved the clock the subject should
# not have been reading. Both directions are pinned now, one variable apart, and 4b is that old
# fixture with its assertion inverted.
@test "live layer ON a commit past the time budget, lag under the commit budget ⇒ RUNG=🚀" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  live_at_aged 25200                        # the live layer is ON a 7h-old commit; the budget is 6h
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "behind" ]
  [ "$(field "$output" LIVE_LAG)" = "1" ]   # 1 ≤ 25 — the commit budget is NOT what tripped
  [ "$(field "$output" LIVE_ADDS)" = "0" ]  # an EDIT — nor is the added-file cause
  [ "$(field "$output" LIVE_DIVERGED)" = "0" ]   # nor divergence: three arms pinned OFF, one left
  [ "$(field "$output" RUNG)" = "🚀" ]
  run bash "$LEDGER" --full
  [ "$(printf '%s' "$output" | grep -c "PAST budget")" -ge 1 ]
}

# ── 4b. THE PAIRED OPPOSITE: MY commit is old, the LIVE layer's commit is fresh ⇒ ✅, never 🚀 ──
# One variable apart from #4 — which commit carries the age. A session that has been working for
# hours and lands onto a live layer the converger advanced seconds ago is not past ANY converge
# budget: the bytes the machine runs are current, and the next tick carries the rest. Asserting ✅
# on the exact fixture the pre-#235 test asserted 🚀 on is what makes the clock change falsifiable.
@test "MY HEAD past the time budget but the live layer's commit is fresh ⇒ RUNG=✅, never 🚀" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  commit_aged 25200                         # HEAD committed 7h ago — the pre-#235 arm tripped here
  git -C "$WRAP_LIVE_REPO" fetch -q origin  # the live clone SEES it and stays on its own fresh HEAD
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "behind" ]
  [ "$(field "$output" LIVE_LAG)" = "1" ]
  [ "$(field "$output" LIVE_ADDS)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(printf '%s' "$output" | grep -c "^RUNG=🚀")" -eq 0 ]
}

# ── 4c. THE CALIBRATION, pinned by ONE fixture and ONE variable ──
# 60 minutes was calibrated for the session-HEAD clock, where "my landing is an hour old and still
# not live" is reasonable impatience about a session's OWN work. On the live-layer clock the
# sibling's own calibrated value for this same quantity is CC_DEPLOY_MAX_LAG_HOURS=6, and
# re-pointing the arm without re-calibrating it would fire 🚀 at every close on a lane that is
# legitimately mid-converge — the alarm-polarity bound this rung's header block opens with. Both
# halves are asserted so that neither the default nor the seam can go vacuous.
@test "live commit 2h old is INSIDE the 6h default ⇒ ✅; the same fixture at BUDGET_MIN=60 ⇒ 🚀" {
  ok_state
  WRAP_LIVE_REPO="$(mk_live)"; export WRAP_LIVE_REPO
  live_at_aged 7200                         # 2h — inside the 6h default, outside the old 60m one
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "behind" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  export WRAP_LIVE_BUDGET_MIN=60            # the seam, set to the pre-#235 default
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
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
# The fixture is deliberately set to 🚀 THREE times over — HEAD is 2h old, a migration has failed,
# AND the tree carries a file added since base — so a gate that failed to hold would be caught here
# rather than passing vacuously. The third loading is the 2026-08-09 cause: it must be as unreachable
# from a foreign repo as the other two, and it is computed one branch deeper, so it needs its own.
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
  echo brandnew > brandnew.txt; git add brandnew.txt; git commit -q -m "adds a file"; git push -q origin main
  commit_aged 7200
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LIVE_SRC)" = "n-a" ]
  [ "$(field "$output" MIG_FAILED)" = "0" ]
  [ "$(field "$output" LIVE_ADDS)" = "0" ]   # not counted — never even asked in a foreign repo
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
# The fixture is LOADED FOR 🚀 — HEAD committed 2h ago (time budget blown), a migration has FAILED,
# AND the tree carries a newly ADDED file (the 2026-08-09 no-budget cause) — so a gate that leaked in
# any of the three states moves at least one of these readouts.
@test "foreign repo: readout is BYTE-IDENTICAL with and without WRAP_LIVE_REPO (🚀 unreachable)" {
  ok_state
  mk_failed_migration
  echo brandnew > brandnew.txt; git add brandnew.txt; git commit -q -m "adds a file"; git push -q origin main
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

# ─────────────────────────────────────────────────────────────────────────────────────────────
# ⛔ — an open class-C decision THIS SESSION filed (2026-08-07).
# The HIGHEST-priority rung was the ONLY one with no sensor: "the model overlays it" is not a
# mechanism, it is the absence of one. A close rendered "✅ SAFE TO CLOSE — nothing of mine is open"
# — true over every git fact — while the model held a blocking operator decision it had demoted to
# paragraph 4 of its own prose. Two properties are load-bearing and each gets BOTH directions:
#   (1) SESSION-SCOPED — ~21 open decisions stand on this machine. A top rung counting those would
#       fire at every close forever and carry zero bits (MEMORY.md alarm-polarity). The "another
#       session" case below is the important negative, and it is proved LIVE before it is asserted.
#   (2) CLASS C ONLY — a class-B packet's default FIRES at its deadline if nobody vetoes, so it
#       resolves itself and is not a blocker. C is human-gated and waits.
# cc-decide is the REAL binary here, against a per-test CC_DECISIONS_DIR: the predicate under test
# is precisely the producer/consumer contract between the two files, so stubbing the producer would
# test a hand-written approximation of the thing that ships (MEMORY.md control-must-replay-the-real-artifact).
# ─────────────────────────────────────────────────────────────────────────────────────────────

# point the ledger at the real cc-decide, whose store is this test's temp dir
use_real_decide() { CC_DECIDE_BIN="$REPO/bin/cc-decide"; export CC_DECIDE_BIN; }

# open a class-C decision owned by session $1, with prose $2. Echoes the packet id.
open_blocking() { bash "$REPO/bin/cc-decide" open --class C --session-sid "$1" --what "$2"; }

# ── 1. a class-C decision filed by THIS session ⇒ ⛔, and it names the decision ──
@test "open class-C decision from THIS session ⇒ RUNG=⛔, BLOCKED=1, named in one line" {
  ok_state
  use_real_decide
  export WRAP_SESSION_ID="$SID"
  open_blocking "$SID" "drop the legacy sessions table" >/dev/null
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "⛔" ]
  [ "$(field "$output" BLOCKED)" = "1" ]
  [ "$(field "$output" BLOCKED_SRC)" = "WRAP_SESSION_ID" ]
  ! printf '%s' "$output" | grep -q "^RUNG=✅" || false
  run bash "$LEDGER"                    # the default readout is ONE line that names the decision
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  printf '%s' "$output" | grep -q "⛔"
  printf '%s' "$output" | grep -q "need your call: drop the legacy sessions table"
}

# ── 2. N>1 collapses to the command that lists them, never one fork's prose ──
@test "two open class-C decisions ⇒ RUNG=⛔, BLOCKED=2, readout points at cc-decide list" {
  ok_state
  use_real_decide
  export WRAP_SESSION_ID="$SID"
  open_blocking "$SID" "first fork"  >/dev/null
  open_blocking "$SID" "second fork" >/dev/null
  run bash "$LEDGER" --machine
  [ "$(field "$output" BLOCKED)" = "2" ]
  [ "$(field "$output" RUNG)" = "⛔" ]
  run bash "$LEDGER"
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  printf '%s' "$output" | grep -q "2 decision(s) need your call"
  printf '%s' "$output" | grep -q "cc-decide list --open"
  ! printf '%s' "$output" | grep -q "first fork" || false   # never one fork's prose for many
}

# ── 3. NEGATIVE: class B is not a blocker — its default fires itself ──
@test "open class-B from THIS session ⇒ NOT ⛔ (a B resolves itself at its deadline)" {
  ok_state
  use_real_decide
  export WRAP_SESSION_ID="$SID"
  bash "$REPO/bin/cc-decide" open --class B --session-sid "$SID" --what "which account to continue on" \
    --default "continue on next2" --deadline "2099-01-01T00:00:00Z" >/dev/null
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" BLOCKED)" = "0" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  # PROVE THE FIXTURE CAN FIRE: same session, same store, only the CLASS differs.
  open_blocking "$SID" "the human-gated one" >/dev/null
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "⛔" ]
  [ "$(field "$output" BLOCKED)" = "1" ]      # the B is still not counted
}

# ── 4. NEGATIVE: a RESOLVED packet is not a blocker (the rung is not sticky) ──
@test "a vetoed/actioned class-C ⇒ NOT ⛔ (status is the arbiter's, and it moved)" {
  ok_state
  use_real_decide
  export WRAP_SESSION_ID="$SID"
  local id; id="$(open_blocking "$SID" "settle this one")"
  run bash "$LEDGER" --machine                 # live first — the fixture provably fires
  [ "$(field "$output" RUNG)" = "⛔" ]
  bash "$REPO/bin/cc-decide" veto "$id" --by operator >/dev/null
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED)" = "0" ]
  local id2; id2="$(open_blocking "$SID" "and this one")"
  bash "$REPO/bin/cc-decide" action "$id2" --evidence "commit:abc" >/dev/null
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED)" = "0" ]
}

# ── 5. THE always-fires guard, and the most important negative: ANOTHER session's decision ──
@test "class-C filed by a DIFFERENT session ⇒ RUNG=✅, BLOCKED=0 (never the standing pile)" {
  ok_state
  use_real_decide
  open_blocking "sess-someone-else" "a decision that is not mine" >/dev/null

  # PROVE IT CAN FIRE FIRST — flip ONLY the session identity and nothing else. Without this the
  # negative below passes vacuously for any reason at all (a broken binary, an empty store, a
  # mis-resolved seam) and would keep passing after the session filter was deleted.
  run bash "$LEDGER" --machine --session "sess-someone-else"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "⛔" ]
  [ "$(field "$output" BLOCKED)" = "1" ]

  # ...now the assertion: same store, same packet, THIS session's id.
  run bash "$LEDGER" --machine --session "$SID"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED)" = "0" ]
  [ "$(field "$output" BLOCKED_SRC)" = "flag" ]     # counted for real, not "could not tell"
  ! printf '%s' "$output" | grep -q "^RUNG=⛔" || false
}

# ── 6. ⛔ OUTRANKS EVERYTHING — including a dirty tree, the rung it must beat ──
@test "dirty tree + a blocking decision ⇒ RUNG=⛔ (⛔ outranks 🔧)" {
  ok_state
  use_real_decide
  export WRAP_SESSION_ID="$SID"
  echo dirt >> base.txt                        # a real 🔧 the session owns
  open_blocking "$SID" "authorise the destructive migration" >/dev/null
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" DIRTY)" = "1" ]         # the loose end is real and still reported…
  [ "$(field "$output" RUNG)" = "⛔" ]          # …and ⛔ still governs
  # the CONTROL on the same fixture: remove only the decision and 🔧 comes back
  rm -f "$CC_DECISIONS_DIR"/*.json
  run bash "$LEDGER" --machine
  [ "$(field "$output" RUNG)" = "🔧" ]
}

@test "unlanded commit + a blocking decision ⇒ RUNG=⛔ (⛔ outranks 📦)" {
  ok_state
  use_real_decide
  export WRAP_SESSION_ID="$SID"
  echo more > more.txt; git add more.txt; git commit -q -m "unlanded work"
  open_blocking "$SID" "pick the rollback strategy" >/dev/null
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" UNLANDED)" = "1" ]
  [ "$(field "$output" RUNG)" = "⛔" ]
}

# ── 7. an unreadable/absent cc-decide leaves the rung EXACTLY where it was (fail-OPEN) ──
@test "absent cc-decide ⇒ BLOCKED_SRC=error, never ⛔, readout byte-identical to no-sensor" {
  ok_state
  export WRAP_SESSION_ID="$SID"
  # (a) the seam pointed at a path that does not exist
  export CC_DECIDE_BIN="$BATS_TEST_TMPDIR/no-such-cc-decide"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" BLOCKED)" = "0" ]
  [ "$(field "$output" BLOCKED_SRC)" = "error" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  local a; a="$(bash "$LEDGER")"

  # (b) a binary that exists but exits non-zero — the other failure shape
  local broken="$BATS_TEST_TMPDIR/cc-decide-broken"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$broken"; chmod +x "$broken"
  export CC_DECIDE_BIN="$broken"
  run bash "$LEDGER" --machine
  [ "$(field "$output" BLOCKED_SRC)" = "error" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  local b; b="$(bash "$LEDGER")"

  # (c) a binary that returns a well-formed EMPTY board — the "read fine, zero rows" control
  local empty="$BATS_TEST_TMPDIR/cc-decide-empty"
  printf '#!/usr/bin/env bash\nprintf "[]\\n"\n' > "$empty"; chmod +x "$empty"
  export CC_DECIDE_BIN="$empty"
  local c; c="$(bash "$LEDGER")"

  # An unreadable sensor must produce the SAME close as a sensor that read zero rows — that is what
  # "never manufactures a rung" means from the operator's side, not just in a machine field.
  [ "$a" = "$b" ]
  [ "$b" = "$c" ]
  ! printf '%s' "$b" | grep -q "⛔" || false
}

@test "cc-decide emitting UNPARSEABLE output ⇒ BLOCKED_SRC=error, never ⛔" {
  ok_state
  export WRAP_SESSION_ID="$SID"
  local junk="$BATS_TEST_TMPDIR/cc-decide-junk"
  printf '#!/usr/bin/env bash\nprintf "not json at all\\n"\n' > "$junk"; chmod +x "$junk"
  export CC_DECIDE_BIN="$junk"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" BLOCKED)" = "0" ]
  [ "$(field "$output" BLOCKED_SRC)" = "error" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

# ── 8. an unresolvable session NEVER manufactures a ⛔ (the YOURS_SRC=none law) ──
@test "unresolvable session id ⇒ RUNG=✅, BLOCKED=0, BLOCKED_SRC=none (never a manufactured ⛔)" {
  ok_state
  use_real_decide
  open_blocking "$SID" "a decision nobody can attribute" >/dev/null
  run bash "$LEDGER" --machine                 # no --session, no WRAP_SESSION_ID/CLAUDE_SESSION_ID
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" BLOCKED)" = "0" ]
  [ "$(field "$output" BLOCKED_SRC)" = "none" ]
  run bash "$LEDGER" --machine --session "$SID"   # the flag resolves it ⇒ the same state is ⛔
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "⛔" ]
  [ "$(field "$output" BLOCKED_SRC)" = "flag" ]
}

# ── 9. the --full ledger carries the Blocked row and a STOP-ASK next-verb ──
@test "--full on ⛔ shows the Blocked row and a next-verb that is not 'continue'" {
  ok_state
  use_real_decide
  export WRAP_SESSION_ID="$SID"
  open_blocking "$SID" "authorise the DROP" >/dev/null
  run bash "$LEDGER" --full
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "^Blocked on you:"
  printf '%s' "$output" | grep -q "authorise the DROP"
  printf '%s' "$output" | grep -q "⛔"
  printf '%s' "$output" | grep -qi "STOP-ASK"
  ! printf '%s' "$output" | grep -qi "Next:.*continue" || false
}

@test "--full with no decision of mine says so positively (not 'could not tell')" {
  ok_state
  use_real_decide
  export WRAP_SESSION_ID="$SID"
  open_blocking "sess-someone-else" "not mine" >/dev/null
  run bash "$LEDGER" --full
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "^Blocked on you:.*none — no decision of mine is open"
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
  [ "$(printf '%s' "$output" | grep -c .)" -eq 6 ]
  local r; for r in '✅' '🔧' '📦' '🚀' '👤' '⛔'; do
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

# ── the trunk ladder, and the rung that abstains when it finds nothing ────────────────────────────
# Every test above exports WRAP_TRUNK, so none of them exercises the ladder itself — which is how
# the origin/HEAD capture (fixed in 7bc4b4e5) shipped and stayed live for months with no test, and
# how the rung it feeds kept a second false-✅ afterwards. These unset it.

@test "trunk ladder: origin/main resolves when origin/HEAD is ABSENT (pins 7bc4b4e5)" {
  # `rev-parse --abbrev-ref origin/HEAD` ECHOES ITS ARGUMENT on stdout when the ref is absent, so
  # the naive ladder captured the literal string, skipped the origin/main + origin/master rungs as
  # "already resolved", and the final --verify blanked it ⇒ TRUNK=none on a repo with a good trunk.
  # The fixture (a clone of an EMPTY bare repo) has exactly that shape: no refs/remotes/origin/HEAD.
  # Written as a plain `[ ]`, not `! git …`: errexit does not fire on a `!`-negated command, so the
  # negated spelling is a DEAD assertion — it cannot fail this test no matter what the repo holds.
  [ -z "$(git for-each-ref refs/remotes/origin/HEAD --format='%(refname)')" ]
  unset WRAP_TRUNK
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" TRUNK)" = "origin/main" ]
  ! printf '%s' "$output" | grep -q "^TRUNK=origin/HEAD" || false # the captured non-ref
  ! printf '%s' "$output" | grep -q "^TRUNK=none"          # the symptom it decayed into
}

@test "trunk ladder: unlanded commits ⇒ 📦 with no origin/HEAD (the false ✅ 7bc4b4e5 killed)" {
  unset WRAP_TRUNK
  echo more > more.txt; git add more.txt; git commit -q -m "unlanded work"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" AHEAD)" = "1" ]
  [ "$(field "$output" UNLANDED)" = "1" ]
  [ "$(field "$output" RUNG)" = "📦" ]
  ! printf '%s' "$output" | grep -q "^RUNG=✅"
}

@test "trunk ladder: a PRESENT origin/HEAD is still honoured (the probe must not skip its rung)" {
  unset WRAP_TRUNK
  git remote set-head origin main            # writes refs/remotes/origin/HEAD → origin/main, no network
  git rev-parse --verify -q origin/HEAD >/dev/null
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" TRUNK)" = "origin/main" ]
}

@test "no trunk resolves at all ⇒ 🔧 landing UNPROVEN, never ✅ 'Clean & landed'" {
  # With no trunk, UNLANDED=0 is a DEFAULT and not a measurement. This rung used to sit BELOW the
  # absent-DoD arm, whose readout opens "✅ Clean & landed" — so the abstain was shadowed on exactly
  # the branch this case reaches, a repo with no trunk having no DoD either. The 👤/🚀 carve-out
  # above it in the source already says a missing trunk must not ASSERT landed; this is the third
  # arm that rule has to reach.
  unset WRAP_TRUNK
  git remote remove origin                                   # takes refs/remotes/origin/* with it
  [ -z "$(git for-each-ref refs/remotes)" ]
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/does-not-exist.md" # the common case: no DoD either
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" TRUNK)" = "none" ]
  [ "$(field "$output" DOD)" = "absent" ]
  [ "$(field "$output" RUNG)" = "🔧" ]
  ! printf '%s' "$output" | grep -q "^RUNG=✅" || false
  # scoped to the READOUT sentence: the machine block legitimately carries an UNLANDED= field, so a
  # whole-output grep for "landed" would match it and pass/fail for the wrong reason.
  local say; say="$(field "$output" READOUT)"
  ! printf '%s' "$say" | grep -qi "landed" || false
  printf '%s' "$say" | grep -qi "unproven"
}

# ── W2 CUSTODY — dispatched work in flight folds into the rung (CLOSE_INTEGRITY G1) ─────────────
# An originator whose wave has not returned must not read ✅ (the certificate rides RUNG=✅), and
# a custody store that is absent/unreadable must never manufacture a rung (fail-OPEN like YOURS).

_cust_repo() { # $1=tag → echoes a clean landed repo (HEAD == origin/main)
  local o="$BATS_TEST_TMPDIR/o-$1.git" w="$BATS_TEST_TMPDIR/w-$1"
  git init -q --bare "$o"; git clone -q "$o" "$w" 2>/dev/null
  ( cd "$w" && git checkout -q -b main && echo x > f && git add f \
    && git -c user.email=t@e.com -c user.name=t commit -q -m c && git push -q -u origin main ) >/dev/null 2>&1
  printf '%s' "$w"
}
_cust_stub() { # $1=name $2=body-line → echoes an executable stub path
  local s="$BATS_TEST_TMPDIR/$1"
  printf '%s\n' '#!/usr/bin/env bash' "$2" > "$s"; chmod +x "$s"; printf '%s' "$s"
}

@test "custody: open dispatches on an otherwise-✅ tree ⇒ RUNG 🔧 + CUSTODY keys" {
  local w; w="$(_cust_repo cust)"
  local STUB BSTUB; STUB="$(_cust_stub cust-stub 'echo 2')"; BSTUB="$(_cust_stub b-stub 'echo []')"
  run bash -c "cd '$w' && CC_CUSTODY_BIN='$STUB' CC_DECIDE_BIN='$BSTUB' CC_BACKLOG_BIN='$BSTUB' WRAP_TRUNK=origin/main bash '$BATS_TEST_DIRNAME/../scripts/wrap-ledger.sh' --machine"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^RUNG=🔧'
  printf '%s' "$output" | grep -q '^CUSTODY_OPEN=2'
  printf '%s' "$output" | grep -q '^CUSTODY_SRC=cwd'
  printf '%s' "$output" | grep -q 'dispatched session(s) have NOT returned'
}

@test "custody CONTROL: count 0 ⇒ the ✅ path is untouched (SRC=cwd, counted zero)" {
  local w; w="$(_cust_repo cust0)"
  local STUB BSTUB; STUB="$(_cust_stub cust0-stub 'echo 0')"; BSTUB="$(_cust_stub b0-stub 'echo []')"
  run bash -c "cd '$w' && CC_CUSTODY_BIN='$STUB' CC_DECIDE_BIN='$BSTUB' CC_BACKLOG_BIN='$BSTUB' WRAP_TRUNK=origin/main bash '$BATS_TEST_DIRNAME/../scripts/wrap-ledger.sh' --machine"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^RUNG=✅'
  printf '%s' "$output" | grep -q '^CUSTODY_OPEN=0'
  printf '%s' "$output" | grep -q '^CUSTODY_SRC=cwd'
}

@test "custody fail-OPEN: an erroring custody binary never manufactures a rung (SRC=error)" {
  local w; w="$(_cust_repo custE)"
  local STUB BSTUB; STUB="$(_cust_stub custE-stub 'exit 3')"; BSTUB="$(_cust_stub bE-stub 'echo []')"
  run bash -c "cd '$w' && CC_CUSTODY_BIN='$STUB' CC_DECIDE_BIN='$BSTUB' CC_BACKLOG_BIN='$BSTUB' WRAP_TRUNK=origin/main bash '$BATS_TEST_DIRNAME/../scripts/wrap-ledger.sh' --machine"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q '^RUNG=✅'
  printf '%s' "$output" | grep -q '^CUSTODY_SRC=error'
}

# ── LAND IN FLIGHT (land-architecture-100p §5 P4, defect 3) ──────────────────────────────────────
# `trunk..HEAD` is unlanded for the WHOLE duration of a land, not only before one. A land is
# minutes long (episode p90 991 s) and its only workable shape is backgrounded, so the close
# protocol routinely ran mid-flight, rendered "📦 … /ship to land it" as the ONE command, and
# pressed for a SECOND /ship on the same worktree — which can only queue behind its own sibling on
# the machine-wide mutex. The rung is deliberately UNCHANGED (the commits really are unlanded, and
# 📦 must keep outranking ✅); what inverts is the instruction.

@test "land in flight ⇒ LANDING=1 and the 📦 line says AWAIT, not /ship" {
  echo more > more.txt; git add more.txt; git commit -q -m "unlanded work"
  sleep 30 & lander=$!
  printf 'pid=%s\nlstart=%s\nstarted=%s\nbranch=feat/x\n' \
    "$lander" "$(ps -o lstart= -p "$lander")" "$(date +%s)" > "$(git rev-parse --absolute-git-dir)/ship-land-inflight"

  run bash "$LEDGER" --machine
  kill "$lander" 2>/dev/null || true
  [ "$status" -eq 0 ]
  [ "$(field "$output" LANDING)" = "1" ]
  [ "$(field "$output" LANDING_PID)" = "$lander" ]
  [ "$(field "$output" RUNG)" = "📦" ]              # NOT laundered into ✅ — the work is still unlanded
  [ "$(field "$output" UNLANDED)" = "1" ]
  printf '%s' "$output" | grep -q "do NOT fire a second /ship"
}

@test "land in flight: a STALE marker leaves the 📦 instruction exactly as it was" {
  # THE CONTROL, and the fail direction that matters. A false IN-FLIGHT suppresses the /ship nudge
  # over genuinely parked work — the FM1 park-and-call-it-done hazard, i.e. losing the commits — so
  # anything unadjudicable must read as NOT in flight. `$$` is alive; its lstart cannot match.
  echo more > more.txt; git add more.txt; git commit -q -m "unlanded work"
  printf 'pid=%s\nlstart=%s\nstarted=%s\nbranch=feat/x\n' \
    "$$" 'Thu Jan  1 00:00:00 2020' "$(date +%s)" > "$(git rev-parse --absolute-git-dir)/ship-land-inflight"

  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LANDING)" = "0" ]
  printf '%s' "$output" | grep -q "/ship to land it"
}

@test "land in flight: NO marker at all ⇒ LANDING=0 (absence is not an in-flight land)" {
  echo more > more.txt; git add more.txt; git commit -q -m "unlanded work"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" LANDING)" = "0" ]
  printf '%s' "$output" | grep -q "/ship to land it"
}

# ══ ◎ GOAL LIVENESS (E5, docs/research/goal-safe-2way-comms-2026-08-13.md §9 B5) ═════════════════
#
# The oracle that makes zero-eval-vs-healthy-deferral measurable AT THE CLOSE. Two properties are
# load-bearing and each has a mutation control below:
#   1. it is REPORTED, NEVER A RUNG — a live goal is a normal state, and a rung on it would fire at
#      every close of every goal-armed session (the alarm-polarity law that bounds 👤/⛔/🚀 here);
#   2. the STOP PATH never forks a `find` — machine mode uses the exported $WRAP_TRANSCRIPT or
#      reports `none`; only the pull surfaces (/wrap) resolve a transcript from a session id.

@test "goal: armed + never evaluated ⇒ GOAL_SRC=live, GOAL_EVALS=0 (the starvation pole)" {
  g_arm "land the wave" "$(g_now)" > "$BATS_TEST_TMPDIR/t.jsonl"
  run bash "$LEDGER" --machine --transcript "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$(field "$output" GOAL_SRC)" = "live" ]
  [ "$(field "$output" GOAL_EVALS)" = "0" ]
  [ "$(field "$output" GOAL_LAST)" = "arm" ]
  printf '%s' "$output" | grep -q "^GOAL_LINE=◎ goal: 0 evals"
  printf '%s' "$output" | grep -q "NEVER judged"
}

@test "goal: evaluations counted + last verdict reported" {
  { g_arm "land the wave" "$(g_now)"; g_unmet "land the wave" "$(g_now)"
    g_unmet "land the wave" "$(g_now)"; } > "$BATS_TEST_TMPDIR/t.jsonl"
  run bash "$LEDGER" --machine --transcript "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$(field "$output" GOAL_EVALS)" = "2" ]
  [ "$(field "$output" GOAL_LAST)" = "unmet" ]
  printf '%s' "$output" | grep -q "^GOAL_LINE=◎ goal: 2 eval(s) · last unmet@"
}

@test "goal: a LIVE goal NEVER moves the rung (it reports, it does not rank)" {
  # An otherwise-✅ tree: clean, landed, DoD present with nothing unchecked. The goal is live and
  # unjudged — the loudest state this term has — and the rung must still read ✅. THE CONTROL for
  # property 1: if the goal ever became a rung, this goes red.
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/dod.md"; printf -- '- [x] done\n' > "$WRAP_DOD_FILE"
  g_arm "land the wave" "$(g_now)" > "$BATS_TEST_TMPDIR/t.jsonl"
  run bash "$LEDGER" --machine --transcript "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$(field "$output" GOAL_SRC)" = "live" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  printf '%s' "$output" | grep -q "^READOUT=✅"
}

@test "goal: the default readout stays ONE line — the rung — with a live goal" {
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/dod.md"; printf -- '- [x] done\n' > "$WRAP_DOD_FILE"
  g_arm "land the wave" "$(g_now)" > "$BATS_TEST_TMPDIR/t.jsonl"
  run bash "$LEDGER" --transcript "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  ! printf '%s' "$output" | grep -q "◎"
}

@test "goal: --goal prints the ◎ line for a LIVE goal and NOTHING otherwise (rc 0 either way)" {
  g_arm "land the wave" "$(g_now)" > "$BATS_TEST_TMPDIR/live.jsonl"
  run bash "$LEDGER" --goal --transcript "$BATS_TEST_TMPDIR/live.jsonl"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "^◎ goal: 0 evals"

  # met ⇒ the FIELDS survive (that is the measurement) but the line does not — a "goal met" note
  # re-printed at every close for the rest of the session is an alarm that always fires.
  { g_arm "x" "$(g_now)"; g_met "x" "$(g_now)"; } > "$BATS_TEST_TMPDIR/met.jsonl"
  run bash "$LEDGER" --goal --transcript "$BATS_TEST_TMPDIR/met.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run bash "$LEDGER" --machine --transcript "$BATS_TEST_TMPDIR/met.jsonl"
  [ "$(field "$output" GOAL_SRC)" = "cleared" ]
  [ "$(field "$output" GOAL_EVALS)" = "1" ]

  # and a goal-less session gains no chrome at all
  printf '{"type":"user","message":{"content":"hi"}}\n' > "$BATS_TEST_TMPDIR/none.jsonl"
  run bash "$LEDGER" --goal --transcript "$BATS_TEST_TMPDIR/none.jsonl"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "goal: --full carries the ◎ row in every state, including 'none armed'" {
  printf '{"type":"user","message":{"content":"hi"}}\n' > "$BATS_TEST_TMPDIR/none.jsonl"
  run bash "$LEDGER" --full --transcript "$BATS_TEST_TMPDIR/none.jsonl"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "^Goal (◎): *none armed in this session"

  { g_arm "land the wave" "$(g_now)"; g_unmet "land the wave" "$(g_now)"; } > "$BATS_TEST_TMPDIR/t.jsonl"
  run bash "$LEDGER" --full --transcript "$BATS_TEST_TMPDIR/t.jsonl"
  printf '%s' "$output" | grep -q "^Goal (◎): *LIVE · 1 evaluation(s) · last unmet@"
  printf '%s' "$output" | grep -q '"land the wave"'
}

@test "goal: an UNREADABLE transcript is 'error', never the positive finding 'absent'" {
  run bash "$LEDGER" --machine --transcript "$BATS_TEST_TMPDIR/does-not-exist.jsonl"
  [ "$status" -eq 0 ]
  [ "$(field "$output" GOAL_SRC)" = "error" ]
  [ "$(field "$output" GOAL_EVALS)" = "0" ]
  [ -z "$(field "$output" GOAL_LINE)" ]
  run bash "$LEDGER" --full --transcript "$BATS_TEST_TMPDIR/does-not-exist.jsonl"
  printf '%s' "$output" | grep -q "^Goal (◎): *unknown"
}

@test "goal: MACHINE mode never forks the pull-path find — no transcript ⇒ none" {
  # THE CONTROL for property 2. The fixture is discoverable BY THE PULL PATH (same roots, same
  # sid), so a machine-mode read that reported `live` here would prove the Stop path had gone
  # looking — seven callers × one find across four account roots, per close, forever.
  mkdir -p "$WRAP_PROJECT_ROOTS/proj"
  g_arm "land the wave" "$(g_now)" > "$WRAP_PROJECT_ROOTS/proj/$SID.jsonl"
  export WRAP_SESSION_ID="$SID"

  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" GOAL_SRC)" = "none" ]

  # …while the PULL path finds exactly that transcript and reports the pole.
  run bash "$LEDGER" --goal
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "^◎ goal: 0 evals"
}

@test "goal: WRAP_CACHE=off must not change the ANSWER — only how often it is computed" {
  # The memo kill-switch blanks $WL_TRANSCRIPT (it is a cache-KEY variable), so a term reading the
  # transcript through it answers a different question under the benchmark's control arm. Caught
  # by tests/wrap-ledger-memo.bats §2 as a cached-vs-uncached byte difference; pinned here at the
  # field that caused it, so the next reader of $WL_TRANSCRIPT sees why it is not the input.
  g_arm "land the wave" "$(g_now)" > "$BATS_TEST_TMPDIR/t.jsonl"
  run env WRAP_CACHE=off bash "$LEDGER" --machine --transcript "$BATS_TEST_TMPDIR/t.jsonl"
  [ "$(field "$output" GOAL_SRC)" = "live" ]
  [ "$(field "$output" GOAL_EVALS)" = "0" ]
}
