#!/usr/bin/env bats
# scripts/drain-chain-assert.sh — the BACKLOG_DRAIN_24_7 §6 liveness invariant.
#
# WHAT IS ACTUALLY BEING PINNED, and it is not "does the script print a word". The subject is an
# ALARM, so the properties that matter are its two failure directions, which are not symmetric:
#
#   a FALSE ALIVE  costs one dead chain nobody notices — the incident §1.2 measured, where the
#                  drain stopped at 06:45Z and the operator was the detector, hours later.
#   a FALSE DEAD   costs a permanent row in the very store this program exists to drain, and a
#                  condition-keyed one, so it never ages out on its own.
#
# So every guard below is a red-provable case rather than a smoke check: the empty store (the
# SUCCESS state, which must never file), the unreadable store ("I could not ask" ≠ "the answer was
# no"), the stale-vs-fresh boundary on both disjuncts, and — the one that would have shipped broken
# — the mtime read, whose naive BSD-first form is a silent no-op on every Linux host (4d7bc86d).
#
# THE FIXTURE STORE IS BUILT WITH THE REAL bin/cc-backlog, never hand-written JSONL: the subject
# reads the FOLD, so a hand-rolled fixture would pin this suite's idea of the fold rather than
# cc-backlog's (memory: sibling-auditors-must-share-the-state-model).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJECT="$REPO/scripts/drain-chain-assert.sh"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  export CC_BACKLOG_BIN="$CB"
  BRIEFS="$BATS_TEST_TMPDIR/briefs"; mkdir -p "$BRIEFS"
  export CC_DRAIN_BRIEF_GLOB="$BRIEFS/fire-drain-recycle*.txt"
}

add() { bash "$CB" add --project claude-infrastructure --title "$1" --source fx; }
verdict() { bash "$SUBJECT" --json | jq -r '.verdict'; }
why()     { bash "$SUBJECT" --json | jq -r '.why'; }
n_rows()  { bash "$CB" list --all --json | jq '[.[]|select(.condition=="local-drain-chain-dead")]|length'; }

# ── the alarm fires when, and only when, the pile is non-empty and nothing is on it ─────────────

@test "a non-empty pile with no brief and no lease is DEAD, and --assert exits 1" {
  add "a row that needs draining" >/dev/null
  [ "$(verdict)" = dead ]
  run bash "$SUBJECT" --assert
  [ "$status" -eq 1 ]
  # The refusal names the remedy, not just the state — a dead-chain row whose title does not say
  # how to restart the chain sends its reader back to the plan to find out.
  [ "$(printf '%s' "$output" | grep -c 'BACKLOG_DRAIN_24_7.md §4.1')" -eq 1 ]
}

@test "an EMPTY store is the success state: alive, and --file writes nothing" {
  [ "$(verdict)" = alive ]
  [ "$(why)" = drained ]
  run bash "$SUBJECT" --file
  [ "$status" -eq 0 ]
  [ "$(n_rows)" -eq 0 ]
}

# The regression this pins: §6's terminal condition is "at true zero live rows, write the
# chain-complete entry". A detector keyed on "no recycle fired recently" alone would file its first
# row on the day the program SUCCEEDED and hold it open forever (memory: cap-whose-population-is-
# empty — the trap that left backlog-ratchet.sh red on every run it had ever made).
@test "draining the last row silences the alarm rather than latching it" {
  id=$(add "the last row")
  [ "$(verdict)" = dead ]
  # `done` QUOTED: unquoted it is the loop keyword, and bats-shellcheck-lint reads this line as a
  # `done` with no matching `do` (SC1010). The quotes change nothing at runtime and make the verb a
  # word rather than syntax.
  bash "$CB" "done" "$id" --evidence "landed abc1234" >/dev/null 2>&1
  [ "$(verdict)" = alive ]
  [ "$(why)" = drained ]
}

# ── disjunct A: the brief, and the mtime read that would have shipped broken ────────────────────

@test "a brief younger than the window proves the chain alive" {
  add "a row" >/dev/null
  : > "$BRIEFS/fire-drain-recycle10.txt"
  [ "$(verdict)" = alive ]
  [ "$(why)" = fresh-brief ]
}

# RED-PROVES THE PORTABILITY BUG DIRECTLY. `stat -f` is "format" on BSD and "--file-system" on GNU,
# and the naive `stat -f %m || stat -c %Y` form leaks a filesystem block onto STDOUT on GNU — so the
# age never parses, every brief is skipped, and the detector reports DEAD on a box that is draining
# fine. That is the false-DEAD direction, i.e. the one that files a permanent row. Asserting the
# AGE (not merely the verdict) is what makes this test see the bug: a verdict-only assertion passes
# on any host where some other disjunct happens to hold.
@test "the brief's age is read as a number on this host (BSD/GNU stat)" {
  add "a row" >/dev/null
  : > "$BRIEFS/fire-drain-recycle10.txt"
  age="$(bash "$SUBJECT" --json | jq -r '.brief_age_s')"
  # ONE ASSERTION PER LINE. `[ A ] && [ B ]` is an and-absorbed compound: bash exempts every
  # component but the last from errexit, so in non-final position it can fail and the test still
  # passes — a green that certifies nothing, which is exactly what bats-assert-liveness.py flags.
  [ -n "$age" ]
  [ "$age" != null ]
  case "$age" in ''|*[!0-9]*) return 1 ;; esac
  [ "$age" -lt 60 ]
}

@test "a brief older than the window does not count, and the title says how old it was" {
  add "a row" >/dev/null
  : > "$BRIEFS/fire-drain-recycle10.txt"
  # 25 h, via the script's own injectable clock — no touch(1) date-format portability in the way.
  export CC_DRAIN_NOW=$(( $(date +%s) + 90000 ))
  [ "$(verdict)" = dead ]
  run bash "$SUBJECT" --assert
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'newest: 9[0-9]*s old')" -eq 1 ]
}

@test "the window is the boundary, not the existence of a brief" {
  add "a row" >/dev/null
  : > "$BRIEFS/fire-drain-recycle10.txt"
  CC_DRAIN_CHAIN_MAX_AGE_S=1 CC_DRAIN_NOW=$(( $(date +%s) + 2 )) run bash "$SUBJECT" --assert
  [ "$status" -eq 1 ]
  CC_DRAIN_CHAIN_MAX_AGE_S=100 CC_DRAIN_NOW=$(( $(date +%s) + 2 )) run bash "$SUBJECT" --assert
  [ "$status" -eq 0 ]
}

# ── disjunct B: the lease ───────────────────────────────────────────────────────────────────────

@test "a live claim proves the chain alive; the same claim past its TTL does not" {
  id=$(add "a row somebody is working")
  bash "$CB" claim "$id" --by "fixture-$$" >/dev/null 2>&1
  [ "$(verdict)" = alive ]
  [ "$(why)" = live-lease ]
  # The TTL is READ FROM THE SAME ENV cc-backlog reap reads, so the two cannot fork — pinned by
  # driving the subject with it rather than with a private knob.
  CC_BACKLOG_STALE_CLAIM_S=1 CC_DRAIN_NOW=$(( $(date +%s) + 10 )) run bash "$SUBJECT" --assert
  [ "$status" -eq 1 ]
}

@test "a blocked row is live work but not a lease — an operator-gated pile still reads dead" {
  id=$(add "a row the operator must unblock")
  bash "$CB" block "$id" --needs "the operator must rotate a key" >/dev/null 2>&1
  [ "$(verdict)" = dead ]
}

# ── the fail-open guards: "I could not ask" must never render as "the answer was no" ────────────

@test "an unreadable store abstains rather than convicting" {
  add "a row" >/dev/null
  CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/no-such-tool" run bash "$SUBJECT" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.verdict')" = alive ]
  [ "$(printf '%s' "$output" | jq -r '.why')" = skipped ]
}

@test "a store that folds to garbage is read-failed, not dead" {
  add "a row" >/dev/null
  printf 'not json at all\n' > "$BATS_TEST_TMPDIR/broken"
  # A cc-backlog that exits 0 with a non-array body is the exact shape the premise pass hit
  # (`_die_open` exiting 0 with an unparseable stdout) — the detector must name it, not swallow it.
  printf '#!/usr/bin/env bash\nprintf "not json\\n"\n' > "$BATS_TEST_TMPDIR/fake-cb"
  chmod +x "$BATS_TEST_TMPDIR/fake-cb"
  CC_BACKLOG_BIN="$BATS_TEST_TMPDIR/fake-cb" run bash "$SUBJECT" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.why')" = read-failed ]
}

# ── the filer: ONE row forever, and it carries its own way out ──────────────────────────────────

@test "--file writes ONE condition-keyed row however many times it runs" {
  add "a row" >/dev/null
  bash "$SUBJECT" --file
  bash "$SUBJECT" --file
  bash "$SUBJECT" --file
  [ "$(n_rows)" -eq 1 ]
}

@test "the filed row carries --assert as its falsifier, so it retires itself" {
  add "a row" >/dev/null
  bash "$SUBJECT" --file
  f="$(bash "$CB" list --all --json | jq -r '.[]|select(.condition=="local-drain-chain-dead")|.falsifier')"
  [ "$(printf '%s' "$f" | grep -c 'drain-chain-assert.sh --assert')" -eq 1 ]
  # And the probe genuinely retracts once the chain restarts: cc-premise's contract is exit 0.
  : > "$BRIEFS/fire-drain-recycle11.txt"
  run bash -c "$f"
  [ "$status" -eq 0 ]
}

@test "--file is silent while the chain is alive" {
  add "a row" >/dev/null
  : > "$BRIEFS/fire-drain-recycle10.txt"
  run bash "$SUBJECT" --file
  [ "$status" -eq 0 ]
  [ "$(n_rows)" -eq 0 ]
}

# ── the caller ──────────────────────────────────────────────────────────────────────────────────

# A FAST CANARY, NOT THE PROOF. A grep pins a string; the caller is pinned END-TO-END by
# tests/autonomy-sweep.bats § "§6 · the drain-chain check RUNS from the sweep and files a dead
# chain" (+ its silent-when-alive CONTROL), both red-proved against origin/main's sweep through the
# suite's CC_TEST_SWEEP seam. This case exists so a deleted call site fails HERE too, beside the
# subject, rather than only in a suite nobody re-runs when editing this file.
@test "autonomy-sweep calls the check and journals its rc (canary; see autonomy-sweep.bats §6)" {
  run grep -c 'drain-chain-assert.sh' "$REPO/scripts/autonomy-sweep.sh"
  [ "$status" -eq 0 ]
  run grep -c 'drain_chain_rc' "$REPO/scripts/autonomy-sweep.sh"
  [ "$status" -eq 0 ]
}
