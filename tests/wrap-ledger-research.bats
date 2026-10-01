#!/usr/bin/env bats
# wrap-ledger.sh — the two verdicts a close carries (REPORT.md §8 item 13, operator ruling
# 2026-10-01): the SESSION's state (RUNG, unchanged) and, separately, the research PROGRAM's.
#
#   SCOPE            met | open | unknown — unknown when no durable DoD exists. RUNG stays ✅ on an
#                    absent DoD; only the readout's words change ("completeness UNKNOWN").
#   RESEARCH_*       the program verdict, read through `cc-research verdict --json <slug>` under a
#                    bound. Never moves RUNG. No program ⇒ no call at all.
#
# Planted inputs only: a throwaway repo, a fixtured registry (CC_RESEARCH_REGISTRY) and a stub
# cc-research (CC_RESEARCH_BIN) that counts its own calls.

setup_file() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
}

setup() {
  export HOME="$BATS_FILE_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LEDGER="$REPO/scripts/wrap-ledger.sh"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK" 2>/dev/null
  cd "$WORK" || return 1
  git checkout -q -b main
  echo base > base.txt; git add base.txt; git commit -q -m base
  git push -q -u origin main 2>/dev/null
  WORK="$(pwd -P)"
  # The same hermetic seams tests/wrap-ledger.bats pins, for the same reason: every store this
  # ledger reads defaults to the operator's live machine.
  export WRAP_TRUNK="origin/main"
  export WRAP_DOD_DIR="$BATS_TEST_TMPDIR/dod"
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/no-dod.md"
  unset WRAP_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_PANE_ID ITERM_SESSION_ID WRAP_TRANSCRIPT
  export CC_CUSTODY_DIR="$BATS_TEST_TMPDIR/custody"
  export CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/absent-cc-backlog"
  export CC_DECIDE_BIN="$BATS_TEST_TMPDIR/absent-cc-decide"
  export CC_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export WRAP_LIVE_REPO="$BATS_TEST_TMPDIR/no-live-layer"
  export WRAP_LIVE_ROOT="$BATS_TEST_TMPDIR/no-live-root"
  export CC_MIGRATIONS_STATE="$BATS_TEST_TMPDIR/migrations"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export WRAP_PROJECT_ROOTS="$BATS_TEST_TMPDIR/projects"
  export CC_WF_TEAM_ROOTS="$BATS_TEST_TMPDIR/teams"; mkdir -p "$CC_WF_TEAM_ROOTS"
  export CC_FIRED_DIR="$BATS_TEST_TMPDIR/fired"; mkdir -p "$CC_FIRED_DIR"
  export WRAP_CACHE=off
  unset WRAP_RESEARCH WRAP_RESEARCH_TIMEOUT_S
  # The research seams. The registry is ABSENT unless a test plants one, and the stub is always
  # installed so "never called" is a counted 0, not an absent binary.
  export CC_RESEARCH_REGISTRY="$BATS_TEST_TMPDIR/registry/programs.json"
  export CC_RESEARCH_BIN="$BATS_TEST_TMPDIR/bin/cc-research"
  CALLS="$BATS_TEST_TMPDIR/research-calls.log"
  export CALLS
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  stub_verdict 'certified' 2
}

field() { printf '%s' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

# stub_verdict <state> <pending> — a cc-research that logs argv and answers `verdict --json`.
stub_verdict() {
  cat > "$CC_RESEARCH_BIN" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CALLS"
case "\$1" in
  verdict) printf '{"program":"alpha","state":"%s","lines":[],"pending_concerns":%s,"waiting_since":null,"menu":[]}\n' '$1' '$2' ;;
  *) exit 2 ;;
esac
STUB
  chmod +x "$CC_RESEARCH_BIN"
}

stub_raw() {  # stub_raw <bash body>
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n%s\n' "$CALLS" "$1" > "$CC_RESEARCH_BIN"
  chmod +x "$CC_RESEARCH_BIN"
}

plant_registry() {  # plant_registry <root> [state]
  mkdir -p "$(dirname "$CC_RESEARCH_REGISTRY")"
  printf '{"programs":[{"slug":"alpha","aliases":[],"cwd_roots":["%s"],"state":"%s"}]}\n' \
    "$1" "${2:-certifying}" > "$CC_RESEARCH_REGISTRY"
}

ncalls() { [ -f "$CALLS" ] && grep -c . "$CALLS" || echo 0; }

# ── SCOPE ────────────────────────────────────────────────────────────────────────────────────────

@test "SCOPE=unknown with no DoD; RUNG stays ✅ and the readout says completeness UNKNOWN" {
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" DOD)" = "absent" ]
  [ "$(field "$output" SCOPE)" = "unknown" ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [[ "$(field "$output" READOUT)" == *"completeness UNKNOWN"* ]] || false
  run bash "$LEDGER"
  [ "$status" -eq 0 ]
  [[ "$output" == "✅ Clean & landed — completeness UNKNOWN: no durable DoD to confirm scope"* ]]
}

@test "SCOPE=met with a DoD whose remainder is 0" {
  printf -- '- [x] one\n- [x] two\n' > "$BATS_TEST_TMPDIR/dod.md"
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/dod.md"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" REMAINDER)" = "0" ]
  [ "$(field "$output" SCOPE)" = "met" ]
  [ "$(field "$output" RUNG)" = "✅" ]
}

@test "SCOPE=open with unchecked DoD items" {
  printf -- '- [x] one\n- [ ] two\n' > "$BATS_TEST_TMPDIR/dod.md"
  export WRAP_DOD_FILE="$BATS_TEST_TMPDIR/dod.md"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" SCOPE)" = "open" ]
}

# ── RESEARCH_* ───────────────────────────────────────────────────────────────────────────────────

@test "outside a program: RESEARCH_PROGRAM=none and cc-research is never called" {
  plant_registry "$BATS_TEST_TMPDIR/somewhere-else"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESEARCH_PROGRAM)" = "none" ]
  [ "$(field "$output" RESEARCH_PENDING)" = "-" ]
  [ "$(ncalls)" -eq 0 ]
}

@test "no registry at all: RESEARCH_PROGRAM=none and cc-research is never called" {
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESEARCH_PROGRAM)" = "none" ]
  [ "$(ncalls)" -eq 0 ]
}

@test "inside a program: RESEARCH_VERDICT is cc-research's state, read once via verdict --json" {
  plant_registry "$WORK"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESEARCH_PROGRAM)" = "alpha" ]
  # the stub says certified while the registry says certifying: the verdict is the stub's
  [ "$(field "$output" RESEARCH_VERDICT)" = "certified" ]
  [ "$(field "$output" RESEARCH_PENDING)" = "2" ]
  [ "$(ncalls)" -eq 1 ]
  grep -q 'verdict --json alpha' "$CALLS"
}

@test "a hanging cc-research yields RESEARCH_VERDICT=unknown within the timeout" {
  plant_registry "$WORK"
  stub_raw 'sleep 30'
  export WRAP_RESEARCH_TIMEOUT_S=1
  local t0 t1
  t0="$(date +%s)"
  run bash "$LEDGER" --machine
  t1="$(date +%s)"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESEARCH_PROGRAM)" = "alpha" ]
  [ "$(field "$output" RESEARCH_VERDICT)" = "unknown" ]
  [ "$(field "$output" RESEARCH_PENDING)" = "-" ]
  [ $((t1 - t0)) -lt 10 ]
}

@test "a failing or garbled cc-research yields RESEARCH_VERDICT=unknown" {
  plant_registry "$WORK"
  stub_raw 'echo not-json; exit 0'
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESEARCH_VERDICT)" = "unknown" ]
  stub_raw 'exit 3'
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESEARCH_VERDICT)" = "unknown" ]
}

@test "the program verdict never moves RUNG: identical with and without a program" {
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  local rung0 read0; rung0="$(field "$output" RUNG)"; read0="$(field "$output" READOUT)"
  plant_registry "$WORK"
  stub_verdict 'certifying' 7
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESEARCH_PROGRAM)" = "alpha" ]
  [ "$(field "$output" RUNG)" = "$rung0" ]
  [ "$(field "$output" READOUT)" = "$read0" ]
}

@test "WRAP_RESEARCH=off: no call, RESEARCH_PROGRAM=none, inside a program" {
  plant_registry "$WORK"
  export WRAP_RESEARCH=off
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RESEARCH_PROGRAM)" = "none" ]
  [ "$(ncalls)" -eq 0 ]
}

@test "--full renders one Program line only when a program resolves" {
  run bash "$LEDGER" --full
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^Program:')" -eq 0 ]
  plant_registry "$WORK"
  run bash "$LEDGER" --full
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^Program:')" -eq 1 ]
  printf '%s\n' "$output" | grep -q '^Program: alpha — certified'
}
