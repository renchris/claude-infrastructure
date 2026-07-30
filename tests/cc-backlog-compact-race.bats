#!/usr/bin/env bats
# cc-backlog compact must not lose a concurrent append (a15/D2).
#
# THE DEFECT. compact is the one verb that REWRITES this store; everything else appends. It read the
# whole file into a tmp and `mv`'d it over the original, unlocked and unchecked, so any record
# appended between the read loop and the mv was silently discarded. The record that gets lost is
# specific and expensive: a cc-dispatch `claim` landing in that window vanishes, the item folds back
# to status "open" (status is the FOLD of the trail, so a missing claim is indistinguishable from
# never having been claimed), and the next dispatch tick claims and spawns a SECOND worker on
# in-flight work. That is the double-dispatch class the reopen guards exist to prevent, arriving
# through the compaction door instead.
#
# WHY THE FIX IS NOT "TAKE A LOCK". The appenders are deliberately lock-free — bare O_APPEND of a
# sub-PIPE_BUF line is atomic, and that is what lets ~14 writers share this store with no
# coordination. So the lock added here only serializes compact against another compact; correctness
# against appenders comes from optimistic concurrency, and it is FAIL-CLOSED: if compact cannot prove
# the file is unchanged, it does not rewrite at all. A skipped compaction costs disk; a lost claim
# costs a double-dispatched worker.
#
# Tests 1-2 are the deterministic core (a append is CARRIED, not lost; an unprovable read ABORTS).
# Test 5 is the real interleaving and is honest about being probabilistic.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  # $HOME is fixtured even though CC_BACKLOG_FILE redirects the ledger: cc-backlog resolves other
  # paths under $HOME (the kick marker, the sessions-bin lookup), and the hermeticity ratchet's rule
  # is the file, not the specific read — a suite that touches live ~/ at all contaminates the run.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_LOCK_DIR="$BATS_TEST_TMPDIR/compact.lock.d"
  export CC_BACKLOG_KICK=off          # no detached cc-dispatch kick from `add` during tests
  OLD="2026-01-01T00:00:00Z"
}

# an aged-out DONE item (compact's drop set) written straight to the ledger
seed_aged_done() { # $1=id
  printf '{"id":"%s","ts":"%s","event":"add","project":"p","title":"t","dodRef":"","source":"s"}\n' "$1" "$OLD" >> "$CC_BACKLOG_FILE"
  printf '{"id":"%s","ts":"%s","event":"done","evidence":"e"}\n' "$1" "$OLD" >> "$CC_BACKLOG_FILE"
}

lines() { grep -c '' "$CC_BACKLOG_FILE" 2>/dev/null || echo 0; }

@test "1: a record appended DURING compact is carried through, not erased" {
  seed_aged_done aaaaaaaaaaaa
  seed_aged_done bbbbbbbbbbbb
  printf '{"id":"cccccccccccc","ts":"%s","event":"add","project":"p","title":"live","dodRef":"","source":"s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_BACKLOG_FILE"

  # THE WINDOW HAS TO BE THE RIGHT ONE. Injecting the append DURING the read loop does not reproduce
  # the bug: the loop reads the ledger as a stream, so a line appended while it is running is picked
  # up by the loop itself and copied into the tmp — preserved by accident. (Verified: an earlier
  # version of this test stubbed `jq` that way and PASSED against the unfixed binary.) The real loss
  # window is the one the audit names — after the read loop, before the `mv` — where the original code
  # has nothing at all. `mv` is used at exactly one executable site in cc-backlog (the commit), so a
  # stub that appends and then performs the real rename lands in that window every time.
  local bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"
  cat > "$bin/mv" <<SH
#!/bin/bash
printf '{"id":"cccccccccccc","ts":"%s","event":"claim","by":"worker-1"}\n' \
  "\$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_BACKLOG_FILE"
exec /bin/mv "\$@"
SH
  chmod +x "$bin/mv"

  PATH="$bin:$PATH" run bash "$CB" compact --older-than-days 1
  # Either outcome is correct for a fixed binary: the guard notices the change and CARRIES the record
  # on a retry (rc 0), or it cannot get a stable read and refuses to rewrite (rc 5). What is NOT
  # acceptable is a "successful" compaction that dropped the record.
  case "$status" in 0|5) ;; *) echo "unexpected rc $status: $output"; false ;; esac

  # THE ASSERTION: the claim that landed in the commit window must still be in the ledger. Without it
  # the item folds back to "open" — status is the FOLD of the trail — and the next dispatch tick
  # spawns a SECOND worker onto work already in flight.
  grep -q '"event":"claim"' "$CC_BACKLOG_FILE" || {
    echo "the concurrent claim was ERASED by the rewrite — this is the double-dispatch bug"
    echo "ledger now:"; cat "$CC_BACKLOG_FILE"
    false
  }
  # and the item must fold to claimed, not back to open
  run bash "$CB" list --all --json
  printf '%s' "$output" | grep -q 'claimed' || { echo "item did not fold to claimed: $output"; false; }
}

@test "2: when the ledger cannot be read cleanly, compact ABORTS without rewriting (fail-closed)" {
  seed_aged_done aaaaaaaaaaaa
  local before_n before_sum
  before_n="$(lines)"; before_sum="$(shasum -a 256 < "$CC_BACKLOG_FILE" | cut -d' ' -f1)"

  # To reach the abort path the append has to land in the ONE window the guard protects: after the
  # tail-carry read and before the count re-check. `tail` is used at exactly one site in cc-backlog —
  # that carry — so a stub that appends right after doing its real job lands there every time, on
  # every retry, and the retry budget is provably spent. (An earlier version of this test stubbed
  # `jq` to append on every call; that made compact CARRY the appends and exit 0, which is the
  # correct behaviour and therefore not a test of the abort path at all.)
  # TWO stubs are needed, each targeting a different point, because one attempt has two conditions:
  #   • `jq` (called per line inside the read loop, i.e. AFTER the n0 snapshot) appends, so the file
  #     GROWS during the attempt — that is what makes the tail-carry run at all. Seeding a late line
  #     before compact starts does NOT work: n0 is taken at the top of each attempt and would already
  #     include it.
  #   • `tail` (used at exactly one site — the carry) appends right after doing its real job, so the
  #     count moves in the one window the guard protects: between the carry read and the re-check.
  # Both fire on every attempt, so the retry budget is provably spent and the rewrite is refused.
  local bin="$BATS_TEST_TMPDIR/bin"; mkdir -p "$bin"
  cat > "$bin/jq" <<SH
#!/bin/bash
printf '{"id":"yyyyyyyyyyyy","ts":"%s","event":"add","project":"p","title":"grow","dodRef":"","source":"s"}\n' \
  "\$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_BACKLOG_FILE"
exec /opt/homebrew/bin/jq "\$@"
SH
  cat > "$bin/tail" <<SH
#!/bin/bash
/usr/bin/tail "\$@"
printf '{"id":"zzzzzzzzzzzz","ts":"%s","event":"add","project":"p","title":"noise","dodRef":"","source":"s"}\n' \
  "\$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_BACKLOG_FILE"
SH
  chmod +x "$bin/jq" "$bin/tail"

  PATH="$bin:$PATH" run bash "$CB" compact --older-than-days 1
  [ "$status" -eq 5 ] || { echo "expected rc 5 (aborted), got $status: $output"; false; }
  printf '%s' "$output" | grep -q 'ABORTED' || { echo "abort was not reported loudly: $output"; false; }
  # every original line must still be present — the abort may not have dropped anything
  [ "$(lines)" -ge "$before_n" ] || { echo "ledger SHRANK during an aborted compact"; false; }
  grep -q 'aaaaaaaaaaaa' "$CC_BACKLOG_FILE" || { echo "an original record was lost by the aborted run"; false; }
}

@test "3: a second compact is refused while one holds the lock (no interleaved rewriters)" {
  seed_aged_done aaaaaaaaaaaa
  mkdir -p "$CC_BACKLOG_LOCK_DIR"
  printf '%s\n' "$$" > "$CC_BACKLOG_LOCK_DIR/owner"     # a LIVE holder (this test)
  run bash "$CB" compact --older-than-days 1
  [ "$status" -eq 5 ] || { echo "expected rc 5 while the lock is held, got $status: $output"; false; }
  grep -q 'aaaaaaaaaaaa' "$CC_BACKLOG_FILE" || { echo "refused run still mutated the ledger"; false; }
  rm -rf "$CC_BACKLOG_LOCK_DIR"
}

@test "4: a DEAD holder's compact lock is reclaimed, and the lock is released afterwards" {
  seed_aged_done aaaaaaaaaaaa
  seed_aged_done bbbbbbbbbbbb
  printf '{"id":"cccccccccccc","ts":"%s","event":"add","project":"p","title":"keep","dodRef":"","source":"s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_BACKLOG_FILE"
  mkdir -p "$CC_BACKLOG_LOCK_DIR"
  sleep 1 & local p=$!; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true
  printf '%s\n' "$p" > "$CC_BACKLOG_LOCK_DIR/owner"     # dead holder
  run bash "$CB" compact --older-than-days 1
  [ "$status" -eq 0 ] || { echo "a dead holder's lock blocked compact: $output"; false; }
  [ ! -d "$CC_BACKLOG_LOCK_DIR" ] || { echo "compact did not release its lock"; false; }
  refute_aged() { [ "$(grep -c 'aaaaaaaaaaaa' "$CC_BACKLOG_FILE")" -eq 0 ]; }
  refute_aged || { echo "aged item was not actually dropped — compact did no work"; false; }
  grep -q 'cccccccccccc' "$CC_BACKLOG_FILE" || { echo "the recent item was dropped"; false; }
}

@test "5: real concurrent appenders lose nothing across a compact (probabilistic backstop)" {
  # Honest label: the interleaving here is not deterministic — tests 1 and 2 are the proof. This
  # asserts the end-to-end invariant (no appended record is ever absent afterwards) against real
  # concurrency, so it can only fail for a real reason.
  local i
  for i in $(seq 1 12); do seed_aged_done "$(printf 'old%09d' "$i")"; done
  ( for i in $(seq 1 25); do
      printf '{"id":"new%09d","ts":"%s","event":"add","project":"p","title":"n","dodRef":"","source":"s"}\n' \
        "$i" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$CC_BACKLOG_FILE"
    done ) &
  local writer=$!
  bash "$CB" compact --older-than-days 1 >/dev/null 2>&1 || true   # rc 5 (abort) is a valid outcome
  wait "$writer" 2>/dev/null || true
  # every id the writer emitted must be present, whether compact rewrote or aborted
  local missing=0
  for i in $(seq 1 25); do
    grep -q "$(printf 'new%09d' "$i")" "$CC_BACKLOG_FILE" || missing=$((missing + 1))
  done
  [ "$missing" -eq 0 ] || { echo "$missing appended record(s) LOST across compact"; false; }
}
