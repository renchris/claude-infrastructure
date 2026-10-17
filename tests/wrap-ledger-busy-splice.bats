#!/usr/bin/env bats
# wrap-ledger-busy-splice — one ledger per Stop (docs/plans/LOAD_AND_PROMPT_HOOK_TIMEOUTS.md Wave 4c).
#
# WHAT IS UNDER TEST. Three cuts to the ledger's cost, each of which must leave every field as it was:
#   1. THE BUSY SPLICE. A BUSY reader asks under the BUSY-off memo key, so it is served (or computes)
#      the Stop's shared ledger and adds the eight BUSY lines itself. Measured before: operator-readout
#      computed a second full ledger beside the shared one, then ran the probe after it.
#   2. THE CONSUMER. A backlog-cache hit is parsed by jq from the entry, not `cat`ed through a pipe.
#   3. ONE DoD FILTER PASS per DoD file, not two.
# Each claim is checked two ways: the output against the UNCACHED / unchanged path, byte for byte,
# and a count of the processes the change exists to remove.
#
# The BUSY probe is a fixture (WRAP_SESSION_BUSY_LIB) so its answer is deterministic and every run of
# it is logged: the real probe samples the live process table, which no two runs see alike.
# Hermetic: throwaway repos, a fixtured $HOME, memo and cache dirs in $BATS_TEST_TMPDIR.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LEDGER="$REPO/scripts/wrap-ledger.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export WRAP_CACHE_DIR="$D/cache"
  export CC_CUSTODY_DIR="$D/custody"
  export WRAP_DOD_DIR="$D/dod"
  export WRAP_TRUNK="origin/main"
  export WRAP_LIVE_REPO="$D/no-live-layer"
  export WRAP_LIVE_ROOT="$D/no-live-root"
  export CC_POSTLAND_DIR="$D/postland"
  export CC_MIGRATIONS_STATE="$D/migrations"
  export CC_BACKLOG_BIN="$D/absent-cc-backlog"
  export CC_DECIDE_BIN="$D/absent-cc-decide"
  export CC_DECISIONS_DIR="$D/decisions"
  export CC_IDL="$D/idl.jsonl"
  export WRAP_PROJECT_ROOTS="$D/projects"
  export CC_WF_TEAM_ROOTS="$D/teams"; mkdir -p "$CC_WF_TEAM_ROOTS"
  unset WRAP_SESSION_ID CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID WRAP_TRANSCRIPT WRAP_CACHE WRAP_BUSY
  unset CC_PANE_ID ITERM_SESSION_ID CC_CUSTODY_BIN
  # The splice is opt-in; the BUSY asks below opt in, as operator-readout's ⏳ arm does.
  export WRAP_BUSY_SPLICE=on
  SID="sess-11111111-2222-3333-4444-555555555555"
  export WRAP_SESSION_ID="$SID"

  # The probe fixture: logs each run (with the custody count it was told) to $SB_LOG, answers BUSY.
  export SB_LOG="$D/probe.log"; : > "$SB_LOG"
  export EVENTS="$D/events.log"; : > "$EVENTS"
  export WRAP_SESSION_BUSY_LIB="$D/session-busy-fixture.sh"
  cat > "$WRAP_SESSION_BUSY_LIB" <<'LIB'
session_busy_live() {
  printf 'probe custody=%s sid=%s\n' "${CC_BUSY_CUSTODY_OPEN:-unset}" "${1:-}" >> "$SB_LOG"
  printf 'probe\n' >> "$EVENTS"
  printf 'BUSY 0 42 job 1 bash ./scripts/gate.sh --long run\n'
}
sb_permpend() { printf '7 Bash'; }
LIB

  ORIGIN="$D/origin.git"; WORK="$D/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || return 1
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt; git add base.txt; git commit -q -m base
  git push -q -u origin main
  TP="$D/transcript.jsonl"; printf 'turn 1\n' > "$TP"

  # Counting wrappers, first on PATH: each logs its name (and, for awk, whether it read the DoD
  # lineage file) and runs the real tool. git logs AFTER it finishes, so the order test below sees
  # when each call ended.
  WRAPS="$D/wraps"; mkdir -p "$WRAPS"
  export FORK_LOG="$D/forks.log"; : > "$FORK_LOG"
  local t real
  for t in git cat awk; do
    real="$(command -v "$t")"
    cat > "$WRAPS/$t" <<WRAP
#!/bin/bash
case "\$*" in *lineage.tsv*) printf '%s lineage\n' "$t" >> "\$FORK_LOG" ;; *) printf '%s %s\n' "$t" "\$*" >> "\$FORK_LOG" ;; esac
"$real" "\$@"; rc=\$?
[ "$t" = git ] && printf 'git\n' >> "\$EVENTS"
exit \$rc
WRAP
    chmod +x "$WRAPS/$t"
  done
  export PATH="$WRAPS:$PATH"
}

field() { printf '%s' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }
cached_n() {
  local n=0 f
  for f in "$WRAP_CACHE_DIR"/m-*; do [ -f "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}
forks() { grep -c "^$1 " "$FORK_LOG" | tr -d ' '; }
probes() { grep -c '^probe' "$SB_LOG" | tr -d ' '; }

# ══ 1. THE BUSY SPLICE: same bytes, one computation ══════════════════════════════════════════════
@test "a BUSY ask served from the shared BUSY-off memo is byte-identical to the uncached BUSY ledger" {
  run env WRAP_CACHE=off bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]; want="$output"
  # The fixture's answer is in it — so the equality below compares real BUSY lines, not defaults.
  [ "$(field "$want" BUSY_STATE)" = "BUSY" ]
  [ "$(field "$want" BUSY_SAMPLE)" = "1 bash ./scripts/gate.sh --long run" ]
  [ "$(field "$want" PERMPEND_AGE)" = "7" ]
  run env WRAP_BUSY=off bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" BUSY_STATE)" = "UNKNOWN" ]
  [ "$(cached_n)" -eq 1 ]
  : > "$FORK_LOG"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$output" = "$want" ]
  [ "$(forks git)" -eq 0 ]                   # served from the BUSY-off ledger's memo, not recomputed
  [ "$(cached_n)" -eq 2 ]                    # + the event's published BUSY ledger
}

@test "a second BUSY reader in the same event is served the first one's sample, no probe" {
  # Both kinds: the spliced first reader publishes under the key a DEFAULT BUSY ask reads.
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]; first="$output"
  # A probe that would now answer differently: the second reader must not run it.
  printf 'session_busy_live() { printf "probe\\n" >> "$SB_LOG"; printf "IDLE-DEAF 0 9 none other\\n"; }\nsb_permpend() { return 1; }\n' \
    > "$WRAP_SESSION_BUSY_LIB"
  : > "$SB_LOG"; : > "$FORK_LOG"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$output" = "$first" ]
  [ "$(probes)" -eq 0 ]
  [ "$(forks git)" -eq 0 ]
  run env -u WRAP_BUSY_SPLICE bash "$LEDGER" --machine --transcript "$TP"
  [ "$output" = "$first" ]
  [ "$(probes)" -eq 0 ]
  [ "$(forks git)" -eq 0 ]
}

@test "a BUSY ask that computes stores the BUSY-off ledger, which a BUSY-off ask is then served unchanged" {
  run env WRAP_CACHE=off bash "$LEDGER" --machine --transcript "$TP"
  want_on="$output"
  run env WRAP_CACHE=off WRAP_BUSY=off bash "$LEDGER" --machine --transcript "$TP"
  want_off="$output"
  [ "$want_on" != "$want_off" ]
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$output" = "$want_on" ]
  [ "$(cached_n)" -eq 2 ]                    # the shared BUSY-off ledger + the event's BUSY ledger
  run env WRAP_BUSY=off bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$output" = "$want_off" ]
}

@test "the served BUSY ask starts no git and runs the probe once (fork ceiling)" {
  run env WRAP_BUSY=off bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(forks git)" -gt 5 ]                   # control: a compute really does start git
  : > "$FORK_LOG"; : > "$SB_LOG"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(forks git)" -eq 0 ]
  [ "$(probes)" -eq 1 ]
}

@test "without WRAP_BUSY_SPLICE=on a BUSY ask keeps its own key and its own computation" {
  run env WRAP_BUSY=off bash "$LEDGER" --machine --transcript "$TP"
  : > "$FORK_LOG"
  run env -u WRAP_BUSY_SPLICE bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" BUSY_STATE)" = "BUSY" ]
  [ "$(cached_n)" -eq 2 ]
  [ "$(forks git)" -gt 5 ]
}

@test "the probe is told the CUSTODY_OPEN the ledger computed, on the served path too" {
  export CC_CUSTODY_BIN="$D/cc-custody-stub"
  printf '#!/bin/bash\ncase "$1" in count) echo 2 ;; *) exit 1 ;; esac\n' > "$CC_CUSTODY_BIN"
  chmod +x "$CC_CUSTODY_BIN"
  run env WRAP_CACHE=off bash "$LEDGER" --machine --transcript "$TP"
  want="$output"
  [ "$(field "$want" CUSTODY_OPEN)" = "2" ]
  [ "$(tail -1 "$SB_LOG")" = "probe custody=2 sid=$SID" ]
  run env WRAP_BUSY=off bash "$LEDGER" --machine --transcript "$TP"
  : > "$SB_LOG"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$output" = "$want" ]
  [ "$(cat "$SB_LOG")" = "probe custody=2 sid=$SID" ]
}

@test "a served body not in emit_machine's BUSY-off shape is a miss, never spliced" {
  run env WRAP_CACHE=off bash "$LEDGER" --machine --transcript "$TP"
  want="$output"
  run env WRAP_BUSY=off bash "$LEDGER" --machine --transcript "$TP"
  local m; for m in "$WRAP_CACHE_DIR"/m-*; do :; done
  # Forge line 12 (BUSY_SRC) in place, key line untouched: the body no longer has the BUSY-off shape.
  sed 's/^BUSY_SRC=none$/BUSY_SRC=forged/' "$m" > "$m.x" && mv "$m.x" "$m"
  grep -q '^BUSY_SRC=forged$' "$m"
  : > "$FORK_LOG"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$output" = "$want" ]
  [ "$(forks git)" -gt 5 ]                   # it computed rather than trusting the body
  [[ "$output" != *forged* ]]
}

@test "the probe runs after the ledger's last git call, never beside it" {
  # Its job scan would read the ledger's own `git -C <worktree>` children as a running job.
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  grep -q '^git$' "$EVENTS"
  [ "$(tail -1 "$EVENTS")" = "probe" ]
  [ "$(grep -c '^probe$' "$EVENTS")" -eq 1 ]
}

# ══ 2. THE CONSUMER: a backlog-cache hit is parsed from the entry ═════════════════════════════════
@test "a backlog-cache hit is read by jq from the entry (no cat), with the counts the pipe gave" {
  export WRAP_CACHE=off WRAP_BUSY=off WRAP_BACKLOG_CACHE=on WRAP_BACKLOG_CACHE_DIR="$D/blc"
  export CC_BACKLOG_FILE="$D/backlog.jsonl"; printf '{"id":"A-1"}\n' > "$CC_BACKLOG_FILE"
  export CC_BACKLOG_BIN="$D/cc-backlog-stub"
  printf '[{"id":"A-1","status":"open","filedBy":"%s"},{"id":"A-2","status":"done","closedSession":"%s"}]\n' \
    "$SID" "$SID" > "$D/all.json"
  printf '[]\n' > "$D/blocked.json"
  printf '#!/bin/bash\ncase "$*" in *--all*) cat "%s" ;; *) cat "%s" ;; esac\n' "$D/all.json" "$D/blocked.json" \
    > "$CC_BACKLOG_BIN"; chmod +x "$CC_BACKLOG_BIN"
  printf -- '- [x] done\n' > "$D/dod-ok.md"; export WRAP_DOD_FILE="$D/dod-ok.md"
  git rev-parse HEAD > "$(git rev-parse --git-common-dir)/gate-green"
  run env WRAP_BACKLOG_CACHE=off bash "$LEDGER" --machine
  want_f="$(field "$output" FILED_MINE)"; want_c="$(field "$output" CLOSED_MINE)"
  [ "$want_f" = "1" ] && [ "$want_c" = "1" ]
  run bash "$LEDGER" --machine               # the miss: fills both entries
  [ "$(field "$output" FILED_MINE)" = "$want_f" ]
  : > "$FORK_LOG"
  run bash "$LEDGER" --machine               # the hit
  [ "$status" -eq 0 ]
  [ "$(field "$output" FILED_MINE)" = "$want_f" ]
  [ "$(field "$output" CLOSED_MINE)" = "$want_c" ]
  [ "$(field "$output" FILED_SRC)" = "WRAP_SESSION_ID" ]
  run grep -c '^cat .*--all_--json' "$FORK_LOG"
  [ "$output" = "0" ]
  grep -q '^cat .*--blocked_--json' "$FORK_LOG"   # control: the --blocked read still cats its hit
}

# ══ 3. ONE DoD FILTER PASS PER FILE ══════════════════════════════════════════════════════════════
@test "the DoD lineage is read once per DoD file, and SCOPE/REMAINDER are unchanged" {
  export WRAP_CACHE=off WRAP_BUSY=off
  mkdir -p "$WRAP_DOD_DIR"
  printf '2026-10-16T00:00:00Z\t/elsewhere\t%s\tfixture\n' "$(pwd -P)" > "$WRAP_DOD_DIR/lineage.tsv"
  # The Scope line names the backlog, so DRAIN_SCOPE=1 proves it was read through the filter.
  printf 'Scope (frozen): drain the backlog fixture\n- [ ] one\n- [x] two\n* [ ] three\n' > "$D/dod.md"
  export WRAP_DOD_FILE="$D/dod.md"
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" DOD)" = "present" ]
  [ "$(field "$output" REMAINDER)" = "2" ]
  [ "$(field "$output" SCOPE)" = "open" ]
  [ "$(field "$output" DRAIN_SCOPE)" = "1" ]
  [ "$(grep -c '^awk lineage$' "$FORK_LOG" | tr -d ' ')" -eq 1 ]
}
