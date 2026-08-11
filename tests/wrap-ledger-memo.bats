#!/usr/bin/env bats
# wrap-ledger-memo — the transcript-keyed `--machine` memo (P0-4, backlog 9414dfb87233).
#
# WHAT IS UNDER TEST. Seven Stop-hook call sites run `wrap-ledger.sh --machine` on every turn close,
# ~180 ms CPU / 19 git subprocesses each — ~1.26 s and ~133 git per session close, forever. The
# seven are ONE event dispatched CONCURRENTLY inside a ~45 ms window, so the memo's job is to serve
# ONE snapshot per event and NEVER across events.
#
# TWO PRIOR DESIGNS DIED, and this suite is written against both graves:
#   FAILURE 1 (9adc5120): benchmarked six SEQUENTIAL calls, shipped a 20% REGRESSION on six
#     CONCURRENT ones (72 git vs 60 uncached) because all six miss together. ⇒ the single-flight
#     cases below run CONCURRENTLY and carry a LOCK-NEUTERED mutant; a serial arm proves nothing.
#   FAILURE 2 (5da21949): keyed on store CONTENT via directory mtimes — and a directory's mtime does
#     not move when a file's contents change, so a class-C packet flipped open→vetoed served the
#     pre-veto ⛔. Its own 18-test suite was green; the CONSUMER suite (tests/wrap-ledger.bats) went
#     3 red. ⇒ the case below replays that exact flip through the REAL bin/cc-decide, and this
#     suite is explicitly NOT a substitute for running tests/wrap-ledger.bats.
#
# Hermetic: throwaway repos + a fixtured $HOME + a fixtured cache dir in $BATS_TEST_TMPDIR, so no
# case reads or writes the operator's live ~/ or their real memo dir.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LEDGER="$REPO/scripts/wrap-ledger.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  D="$BATS_TEST_TMPDIR"
  # The memo's own store: fixtured, so the suite can never serve (or poison) the operator's.
  export WRAP_CACHE_DIR="$D/cache"
  # Same hermetic pins as tests/wrap-ledger.bats — every sensor unresolvable or fixtured, so the
  # rung under test is a function of this fixture alone.
  export CC_CUSTODY_DIR="$D/custody"
  export WRAP_DOD_DIR="$D/dod"
  export WRAP_TRUNK="origin/main"
  export WRAP_LIVE_REPO="$D/no-live-layer"
  export CC_MIGRATIONS_STATE="$D/migrations"
  export CC_BACKLOG_BIN="$D/absent-cc-backlog"
  export CC_DECIDE_BIN="$D/absent-cc-decide"
  export CC_DECISIONS_DIR="$D/decisions"
  export CC_IDL="$D/idl.jsonl"
  unset WRAP_SESSION_ID CLAUDE_SESSION_ID WRAP_TRANSCRIPT WRAP_CACHE
  SID="sess-11111111-2222-3333-4444-555555555555"
  ORIGIN="$D/origin.git"; WORK="$D/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || return 1
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt; git add base.txt; git commit -q -m base
  git push -q -u origin main
  # The transcript IS the event clock: every append is a new Stop event, and its (mtime,size) is
  # the whole key. One line to start with, so the first call has something to stat.
  TP="$D/transcript.jsonl"; printf 'turn 1\n' > "$TP"
}

field() { printf '%s' "$1" | grep -E "^$2=" | head -1 | cut -d= -f2-; }

# a NEW Stop event: append to the transcript, which moves both mtime and size
tick() { printf 'turn %s\n' "$1" >> "$TP"; }

# how many files the memo store holds (0 when the dir does not exist)
cached_n() {
  local n=0 f
  for f in "$WRAP_CACHE_DIR"/m-*; do [ -f "$f" ] && n=$((n + 1)); done
  printf '%s' "$n"
}

# ══ 1. THE ABSENT-KEY LAW: no transcript ⇒ no cache, by construction ════════════════════════════
# This is what makes tests/wrap-ledger.bats — and /wrap, and the CLI — provably unaffected: they
# pass no transcript, so there is nothing to tune and nothing that can go stale for them.
@test "no --transcript ⇒ NOTHING is cached and every call recomputes" {
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(cached_n)" -eq 0 ]
  echo dirt >> base.txt                      # a tree change WITHIN what would be one event
  run bash "$LEDGER" --machine
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]       # seen immediately — no memo exists to serve
  [ "$(cached_n)" -eq 0 ]
}

@test "WRAP_CACHE=off ⇒ no cache is read or written even WITH a transcript" {
  run env WRAP_CACHE=off bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(cached_n)" -eq 0 ]
  echo dirt >> base.txt
  run env WRAP_CACHE=off bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(cached_n)" -eq 0 ]
}

@test "an UNSTATTABLE transcript ⇒ no key, no cache, and a correct ledger anyway" {
  run bash "$LEDGER" --machine --transcript "$D/no-such-transcript.jsonl"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(cached_n)" -eq 0 ]
}

@test "--readout and --full are NEVER memoized (human surfaces, called once)" {
  run bash "$LEDGER" --readout --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(cached_n)" -eq 0 ]
  run bash "$LEDGER" --full --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(cached_n)" -eq 0 ]
  printf '%s' "$output" | grep -q 'SESSION LEDGER'
}

# ══ 2. ONE SNAPSHOT PER EVENT ═══════════════════════════════════════════════════════════════════
@test "same event ⇒ the second caller is SERVED the first caller's ledger" {
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  first="$output"
  [ "$(field "$first" RUNG)" = "✅" ]
  [ "$(cached_n)" -eq 1 ]
  echo dirt >> base.txt                      # the tree moves INSIDE the event
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]       # served, not recomputed — the contract
  [ "$output" = "$first" ]                   # …and byte-identical, not merely same-rung
}

@test "the SERVED ledger is byte-identical to the UNCACHED one for the same state" {
  run env WRAP_CACHE=off bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  uncached="$output"
  run bash "$LEDGER" --machine --transcript "$TP"       # cold: computes and stores
  [ "$status" -eq 0 ]
  cold="$output"
  run bash "$LEDGER" --machine --transcript "$TP"       # warm: served
  [ "$status" -eq 0 ]
  [ "$cold" = "$uncached" ]
  [ "$output" = "$uncached" ]
}

# ══ 3. NEVER ACROSS EVENTS — the FAILURE-2 class, retired by the key ════════════════════════════
@test "a NEW event (the transcript grew) recomputes and sees the tree change" {
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$(field "$output" RUNG)" = "✅" ]
  echo dirt >> base.txt
  tick 2                                     # the operator's next turn ⇒ a new key
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]
  [ "$(field "$output" DIRTY)" = "1" ]
}

# THE EXACT CASE THAT WITHDREW 5da21949, replayed through the REAL bin/cc-decide (a stub would test
# a hand-written approximation of the producer, not the artifact — MEMORY.md
# control-must-replay-the-real-artifact). The flip edits an EXISTING packet file, which is precisely
# what a store-directory mtime cannot see and what an event key does not need to.
@test "a class-C packet flipped open→vetoed BETWEEN events is SEEN (5da21949's grave)" {
  export CC_DECIDE_BIN="$REPO/bin/cc-decide"
  export WRAP_SESSION_ID="$SID"
  id="$(bash "$REPO/bin/cc-decide" open --class C --session-sid "$SID" --what "drop the legacy table")"
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "⛔" ]
  bash "$REPO/bin/cc-decide" veto "$id" --by operator >/dev/null
  tick 2                                     # the operator resolved it BETWEEN turns — always
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" != "⛔" ]      # the withdrawn memo served ⛔ here
  [ "$(field "$output" BLOCKED)" = "0" ]
}

# ── MUTATION CONTROL for the two cases above: neuter the KEY's transcript term (exactly what
# 5da21949 lacked) and the staleness comes straight back. Without this, "it recomputed" could be
# true because the memo never engaged at all.
@test "MUTATION CONTROL: a key blind to the transcript serves a STALE rung across events" {
  mutant="$D/wrap-ledger-STATICKEY.sh"
  sed 's/|\$_wl_ms|/|STATIC|/' "$LEDGER" > "$mutant"
  ! cmp -s "$LEDGER" "$mutant" || false                 # the mutation must have applied
  grep -q '|STATIC|' "$mutant" || false
  run bash "$mutant" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  echo dirt >> base.txt
  tick 2
  run bash "$mutant" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]                  # STALE — the defect, reproduced on demand
  [ "$(field "$output" DIRTY)" = "0" ]
}

# ══ 4. THE KEY SEPARATES CALLERS THAT ARE ASKING DIFFERENT QUESTIONS ════════════════════════════
# completion-assert.sh passes `--session $SID`; the other six call sites do not. Same transcript,
# same instant, DIFFERENT answers — so the key carries the session inputs, not just the transcript.
@test "different --session in the SAME event ⇒ different keys, never a cross-serve" {
  stub="$D/cc-backlog-stub"
  { printf '#!/usr/bin/env bash\n'
    printf "printf '%%s\\\\n' '%s'\n" \
      "[{\"id\":\"B-77\",\"title\":\"load the plist\",\"status\":\"blocked\",\"session\":\"$SID\"}]"
  } > "$stub"
  chmod +x "$stub"
  export CC_BACKLOG_BIN="$stub"
  printf -- '- [x] done\n' > "$D/dod-ok.md"; export WRAP_DOD_FILE="$D/dod-ok.md"
  run bash "$LEDGER" --machine --transcript "$TP"                       # no session ⇒ not counted
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ "$(field "$output" YOURS_SRC)" = "none" ]
  run bash "$LEDGER" --machine --transcript "$TP" --session "$SID"      # same event, other question
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "👤" ]
  [ "$(field "$output" YOURS)" = "1" ]
}

@test "the key carries the cwd: two repos in one event never share a ledger" {
  other="$D/other"
  git clone -q "$ORIGIN" "$other"
  ( cd "$other" && git config user.email t@e.com && git config user.name t && echo dirt >> base.txt )
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  cd "$other" || return 1
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]
}

@test "a FOREIGN key in the cache file is a MISS, never a wrong ledger (collision safety)" {
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(cached_n)" -eq 1 ]
  f="$(echo "$WRAP_CACHE_DIR"/m-*)"
  { printf '#WLKEY someone-elses-key\n'; printf 'RUNG=✅\nREADOUT=poison\n'; } > "$f"
  echo dirt >> base.txt
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "🔧" ]                  # recomputed, not served
  ! printf '%s' "$output" | grep -q 'poison' || false
}

# ══ 5. FAIL-OPEN ON EVERY BRANCH — the memo may never cost a caller its answer ══════════════════
@test "an unwritable cache dir ⇒ a full, correct ledger anyway (never a lost answer)" {
  printf 'not a directory\n' > "$D/blocker"
  run env WRAP_CACHE_DIR="$D/blocker/cache" bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  printf '%s' "$output" | grep -q '^TRUNK=origin/main'
}

@test "a STALE lock (its winner crashed) is cleared and the caller answers — never a wait behind a corpse" {
  run bash "$LEDGER" --machine --transcript "$TP"           # mint the cache file to learn its path
  [ "$status" -eq 0 ]
  f="$(echo "$WRAP_CACHE_DIR"/m-*)"
  rm -f "$f"                                                # force a MISS…
  mkdir "$f.lock"                                           # …behind a lock nobody will ever free
  touch -d '1970-01-02 00:00:00' "$f.lock" 2>/dev/null || touch -t 197001020000 "$f.lock"
  run env WRAP_CACHE_LOCK_STALE_S=1 WRAP_CACHE_WAIT_TRIES=1 WRAP_CACHE_WAIT_MS=10 \
      bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ ! -d "$f.lock" ]                                        # the corpse is cleared for the next event
}

@test "a LIVE lock does not deadlock a caller: it waits, then computes (bounded, fail-open)" {
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  f="$(echo "$WRAP_CACHE_DIR"/m-*)"
  rm -f "$f"
  mkdir "$f.lock"                                           # fresh ⇒ NOT stale ⇒ never cleared
  run env WRAP_CACHE_WAIT_TRIES=2 WRAP_CACHE_WAIT_MS=10 \
      bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]                      # answered anyway
  [ -d "$f.lock" ]                                          # and someone else's live lock is intact
}

@test "the store sweep clears a DEAD winner's lock, which no later key could ever reclaim" {
  bash "$LEDGER" --machine --transcript "$TP" >/dev/null        # mint the store dir
  dead="$WRAP_CACHE_DIR/m-99999999-1.lock"
  mkdir "$dead"
  touch -d '1970-01-02 00:00:00' "$dead" 2>/dev/null || touch -t 197001020000 "$dead"
  tick 2                                                        # a new event ⇒ a compute ⇒ a store
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ ! -d "$dead" ]                                              # every event has its own key, so
  [ "$(cached_n)" -ge 1 ]                                       # nothing else would ever clear it
}

@test "the ledger is emitted even when the store write fails outright" {
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  f="$(echo "$WRAP_CACHE_DIR"/m-*)"
  rm -rf "$WRAP_CACHE_DIR"
  printf 'not a directory\n' > "$WRAP_CACHE_DIR"            # mkdir -p can never succeed here
  run bash "$LEDGER" --machine --transcript "$TP"
  [ "$status" -eq 0 ]
  [ "$(field "$output" RUNG)" = "✅" ]
  [ ! -d "$WRAP_CACHE_DIR" ]
  [ -n "$f" ]
}

# ══ 6. SINGLE-FLIGHT — the FAILURE-1 arm. CONCURRENT, because that is the only shape that can
#      see the defect: six callers arriving inside one ~45 ms window all miss together, and a memo
#      without a lock adds six fingerprints to six full computes. ═══════════════════════════════

# Run $1 concurrent `--machine` callers of script $2; echo the number of git subprocesses they
# spent, counted by a PATH shim. Every caller's output is written to $D/out.<i>.
concurrent_git_count() {
  local n="$1" script="$2" i p pids=()
  mkdir -p "$D/shim"
  { printf '#!/bin/sh\n'
    printf 'printf "g\\n" >> "$WLB_COUNT"\n'
    printf 'exec %s "$@"\n' "$(command -v git)"
  } > "$D/shim/git"
  chmod +x "$D/shim/git"
  : > "$D/gitcount"
  for (( i=0; i<n; i++ )); do
    ( WLB_COUNT="$D/gitcount" PATH="$D/shim:$PATH" \
        bash "$script" --machine --transcript "$TP" > "$D/out.$i" 2>/dev/null ) &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p" || true; done
  # `grep -c` exits 1 on a count of zero while still PRINTING it, so the rc must be swallowed
  # separately from the value — `|| printf 0` appends a second line and the caller's `[ -eq ]`
  # then dies with "integer expression expected".
  local g; g="$(grep -c . "$D/gitcount" 2>/dev/null)" || g=0
  case "$g" in ''|*[!0-9]*) g=0 ;; esac
  printf '%s' "$g"
}

@test "six CONCURRENT cold callers spend ONE compute's worth of git, not six" {
  # the per-compute baseline, measured in this fixture rather than assumed
  baseline="$(concurrent_git_count 1 "$LEDGER")"
  [ "$baseline" -gt 5 ]
  rm -rf "$WRAP_CACHE_DIR"; tick 2
  six="$(concurrent_git_count 6 "$LEDGER")"
  # ≤2 computes: one winner plus at most one loser that legitimately failed open under load.
  [ "$six" -le $((baseline * 2)) ]
  # and every caller must have got the SAME real ledger — a cheap wrong answer is not the goal
  for i in 1 2 3 4 5; do cmp -s "$D/out.0" "$D/out.$i" || false; done
  grep -q '^RUNG=' "$D/out.0" || false
}

@test "six CONCURRENT callers on a WARM event spend ZERO git" {
  bash "$LEDGER" --machine --transcript "$TP" >/dev/null
  warm="$(concurrent_git_count 6 "$LEDGER")"
  [ "$warm" -eq 0 ]
  grep -q '^RUNG=' "$D/out.5" || false
}

# ── MUTATION CONTROL for the lock. Without it the case above proves nothing: a memo that never
# engaged and a memo that single-flights perfectly are indistinguishable from a green test.
@test "MUTATION CONTROL: with the lock neutered, six concurrent cold callers all compute" {
  mutant="$D/wrap-ledger-NOLOCK.sh"
  sed 's|if mkdir "\$WL_LOCK" 2>/dev/null; then|if true; then|' "$LEDGER" > "$mutant"
  ! cmp -s "$LEDGER" "$mutant" || false
  baseline="$(concurrent_git_count 1 "$mutant")"
  [ "$baseline" -gt 5 ]
  rm -rf "$WRAP_CACHE_DIR"; tick 2
  six="$(concurrent_git_count 6 "$mutant")"
  # SIX computes — the 20%-worse-than-uncached shape 9adc5120 shipped.
  [ "$six" -ge $((baseline * 6)) ]
}
