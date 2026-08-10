#!/usr/bin/env bats
# cc-premise — the EVIDENCE-AGE arm (backlog f46261b23ec2).
#
# WHAT THIS ARM IS FOR. An item's evidence is frozen at `add` and nothing re-reads it. 149789b69fc4
# named six unpadded TSV readers at 2026-07-31T17:36:44Z; 68e17e2a discharged exactly those six
# THIRTY-NINE MINUTES later; the item was auto-blocked for thrash, unblocked seven days on, and
# re-dispatched with the original file list verbatim. The incumbent path arm was structurally blind
# to it — all six files were at their cited locations throughout, discharged by a change to their
# CONTENTS — so `cc-premise check` returned `verdict=clear` with an EMPTY contract on an item whose
# entire content was "my evidence is stale".
#
# WHAT THIS FILE IS REALLY GUARDING, and it is the same discipline cc-premise.bats states for the
# refutation arm: this arm is ADVISORY and fires on roughly a quarter of live items, so the danger
# is not a false refusal but AMBIENCE — an alarm that fires on everything carries the same zero bits
# as one that cannot fire at all (memory: alarm-polarity-and-attention-budget). Every "it speaks"
# assertion below is therefore PAIRED with a near-miss control that must stay SILENT: an item under
# the age floor, a cited file nothing has touched, a stamp we cannot read, a repo that cannot
# answer, the kill switch. A suite asserting only the positives would go green on an arm that
# appends its block to every brief in the store.
#
# THE STAMP CONTROL IS THE LOAD-BEARING ONE. The item's timestamp becomes `git log --since=<ts>`,
# and git does NOT fail on a date it cannot parse — it ignores the filter and returns the whole
# history. Delete RE_ISO_TS and a garbage stamp stops meaning "say nothing" and starts meaning
# "report every commit that ever touched this file", which is a fabricated finding wearing the exact
# shape of a real one.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CP="$REPO/bin/cc-premise"
  # $HOME first: cc-premise defaults its store under $HOME, so an unfixtured suite would read the
  # operator's live ledger (memory: unfixtured-sensor-executes-the-deployed-subject). The explicit
  # CC_BACKLOG_FILE beside it says WHICH store this suite means.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  # EXPLICITLY EMPTY, not unset: an unset variable defaults to cc-premise's own checkout, and these
  # assertions would then depend on this repo's real history.
  export CC_PREMISE_REPO=
  : > "$CC_BACKLOG_FILE"
}

# `! cmd` is exempt from errexit in bash, so a negative written that way only fails as the LAST line
# of a body. These return non-zero directly and so fail anywhere.
refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

# RELATIVE TO THE CLOCK, never hardcoded. A fixed stamp satisfies an age floor only until the clock
# arrives at it; cc-premise.bats already lost four tests that way and documents the incident at
# `future_ts`. The `-` in `-v-5d` is load-bearing: bare `date -v 5d` SETS the day rather than
# subtracting. Note `date` is asked for UTC so the Z suffix is honest.
ts_ago() { date -u -v-"$1" +%Y-%m-%dT%H:%M:%SZ; }

# mkrepo — a fixture checkout with a real `origin/main`, owned by this file. Testing the git arms
# against the operator's trunk would make every assertion decay the next time somebody touches one
# of the named files (memory: control-calibrated-to-implementation-decays).
mkrepo() {
  local r="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$r/scripts" "$r/bin"
  printf 'seed\n' > "$r/scripts/target.sh"
  printf 'seed\n' > "$r/scripts/untouched.sh"
  printf 'seed\n' > "$r/bin/deep-tool.sh"
  git -C "$r" init -q -b main .
  git -C "$r" config user.email t@t
  git -C "$r" config user.name t
  git -C "$r" add -A
  GIT_AUTHOR_DATE="$(ts_ago 30d)" GIT_COMMITTER_DATE="$(ts_ago 30d)" \
    git -C "$r" commit -qm seed
  git -C "$r" update-ref refs/remotes/origin/main HEAD
  printf '%s' "$r"
}

# commit_at <repo> <iso-ts> <relpath> <subject> — a dated commit on the fixture trunk. `--since`
# filters on the COMMITTER date, so both stamps are set: an author-date-only fixture would be
# invisible to the very filter under test.
commit_at() {
  local r="$1" ts="$2" p="$3" subj="$4"
  printf '%s\n' "$ts" >> "$r/$p"
  git -C "$r" add -A
  GIT_AUTHOR_DATE="$ts" GIT_COMMITTER_DATE="$ts" git -C "$r" commit -qm "$subj"
  git -C "$r" update-ref refs/remotes/origin/main HEAD
}

# add <id> <title> <ts> — one well-formed `add` record. Ids are hand-chosen so the relationship
# under test is explicit in the file rather than emerging from a hash.
add() { printf '{"id":"%s","ts":"%s","event":"add","project":"claude-infrastructure","title":%s,"source":"t"}\n' \
          "$1" "$3" "$(printf '%s' "$2" | jq -Rs .)" >> "$CC_BACKLOG_FILE"; }

verdict() { printf '%s' "$1" | sed -n 's/^verdict=//p'; }

# ── the arm speaks ───────────────────────────────────────────────────────────────────────────────

@test "an AGED item whose cited file trunk has moved under gets the churn block, named commit and all" {
  # assigned before export: `export X="$(cmd)"` makes the exit status that of `export` (SC2155), so
  # a failed mkrepo would hide behind a green line and silently disable the arm under test.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 1a1a1a1a1a1a "the reader in scripts/target.sh is unpadded" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader at the emitter"

  run "$CP" check 1a1a1a1a1a1a
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "EVIDENCE AGE"
  printf '%s' "$output" | grep -q "1 commit(s) have landed"
  printf '%s' "$output" | grep -q "pad the reader at the emitter"
  printf '%s' "$output" | grep -q "scripts/target.sh"
  # ADVISORY. This is the half that must never regress into a gate: the arm reports that trunk moved,
  # which is a reason to go read a commit, not proof the premise is dead. A refusal here would strand
  # real work, and `suspect` would tag a healthy item as a dead-pointer finding in the sweep report.
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "verdict=superseded"
  refute_match "$output" "verdict=suspect"
}

@test "the block REACHES THE BRIEF — contract is the worker's enforcing store, not check's stderr" {
  # cc-premise's own header says the enforcing store for a worker is its BRIEF. An arm that only
  # printed on `check` would be read by the claim gate's shell and by nobody who does the work —
  # which is exactly how the measured incident burned a worker (memory:
  # conclusion-must-reach-the-enforcing-store).
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 1a1a1a1a1a1a "the reader in scripts/target.sh is unpadded" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader at the emitter"

  run "$CP" contract 1a1a1a1a1a1a
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "EVIDENCE AGE"
  printf '%s' "$output" | grep -q "pad the reader at the emitter"
}

@test "the cap PRINTS ITS OWN TOTAL — a silent truncation reads as 'this is everything'" {
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 1a1a1a1a1a1a "the reader in scripts/target.sh is unpadded" "$(ts_ago 20d)"
  for i in 1 2 3 4 5 6 7 8 9; do
    commit_at "$r" "$(ts_ago "$((20 - i))d")" scripts/target.sh "fix(target): pass $i"
  done

  run "$CP" check 1a1a1a1a1a1a
  [ "$status" -eq 0 ]
  # The TOTAL is the headline and must be exact — deriving it from the capped list would report the
  # cap as the total, which is the failure the two-read implementation exists to avoid.
  printf '%s' "$output" | grep -q "9 commit(s) have landed"
  printf '%s' "$output" | grep -q "showing 6 of 9"
}

# ── the controls that must stay SILENT ───────────────────────────────────────────────────────────

@test "AGE FLOOR: an item younger than the floor is silent even with churn under its cited file" {
  # The floor's positive control. Without it the floor could be deleted outright and every assertion
  # above would still pass, on an arm that then appends its block to freshly-filed items whose
  # description is by construction current.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 2b2b2b2b2b2b "the reader in scripts/target.sh is unpadded" "$(ts_ago 1H)"
  commit_at "$r" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" scripts/target.sh "fix(target): moments ago"

  run "$CP" check 2b2b2b2b2b2b
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "EVIDENCE AGE"
}

@test "NO CHURN: an aged item whose cited file nothing has touched since filing is silent" {
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 3c3c3c3c3c3c "the reader in scripts/untouched.sh is unpadded" "$(ts_ago 5d)"
  # A commit lands in the window, but on a DIFFERENT file. The pathspec is what makes this arm a
  # statement about the item's own evidence rather than about repo traffic.
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): unrelated"

  run "$CP" check 3c3c3c3c3c3c
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "EVIDENCE AGE"
}

@test "UNREADABLE STAMP fails open to silence" {
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  printf '{"id":"4d4d4d4d4d4d","ts":"not-a-timestamp","event":"add","project":"claude-infrastructure","title":"the reader in scripts/target.sh is unpadded","source":"t"}\n' \
    >> "$CC_BACKLOG_FILE"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader"

  run "$CP" check 4d4d4d4d4d4d
  [ "$status" -eq 0 ]
  refute_match "$output" "EVIDENCE AGE"
  refute_match "$output" "pad the reader"
}

@test "A LOOSE STAMP IS ALSO SILENT — the age and the --since window must name ONE instant" {
  # THE MUTANT CONTROL FOR RE_ISO_TS, and it had to be rebuilt once, which is the lesson. The first
  # version of this test used the garbage stamp above and claimed to pin the format guard; it does
  # not. `strptime` rejects garbage on its own, so that test passes identically with RE_ISO_TS
  # deleted — a control that cannot fail the way it says it can (memory:
  # control-must-replay-the-real-artifact). Its stated reason was wrong too: measured 2026-08-10,
  # `git rev-list --since=not-a-timestamp` returns ZERO commits, not the whole history.
  #
  # The shapes where the guard actually bites are the ones BOTH parsers accept and neither flags.
  # `2026-08-05T1:2:3Z` is read by strptime (lenient on zero-padding) AND by git's approxidate, so
  # without the guard the arm speaks — over a window that is not the one the age was measured from.
  #
  # The unpadded part is the TIME, never the date, and that is calendar-safety not style: a month or
  # day that happens to be two digits today would make an unpadded-date fixture identical to a padded
  # one and this control would go quietly vacuous eleven months a year (the decay `future_ts` in
  # cc-premise.bats documents). `1:2:3` is unpadded on every date there is.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  loose="$(date -u -v-5d +%Y-%m-%d)T1:2:3Z"
  printf '{"id":"4e4e4e4e4e4e","ts":"%s","event":"add","project":"claude-infrastructure","title":"the reader in scripts/target.sh is unpadded","source":"t"}\n' \
    "$loose" >> "$CC_BACKLOG_FILE"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader"

  run "$CP" check 4e4e4e4e4e4e
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "EVIDENCE AGE"
  refute_match "$output" "pad the reader"
}

@test "FAIL-OPEN: a repo that cannot ANSWER reports nothing — 'could not ask' is never 'unchanged'" {
  mkdir -p "$BATS_TEST_TMPDIR/not-a-repo"
  add 5e5e5e5e5e5e "the reader in scripts/target.sh is unpadded" "$(ts_ago 5d)"
  for bad in "" "$BATS_TEST_TMPDIR/not-a-repo" "$BATS_TEST_TMPDIR/does-not-exist-at-all"; do
    CC_PREMISE_REPO="$bad" run "$CP" check 5e5e5e5e5e5e
    [ "$status" -eq 0 ]
    [ "$(verdict "$output")" = clear ]
    refute_match "$output" "EVIDENCE AGE"
  done
}

@test "kill switch CC_PREMISE_EVIDENCE_CHURN=off silences this arm and nothing else" {
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 1a1a1a1a1a1a "the reader in scripts/target.sh is unpadded" "$(ts_ago 5d)"
  # A second item carrying an ABSENT path, so the run below can prove the switch is scoped to THIS
  # arm rather than to the git arms as a whole.
  add 6f6f6f6f6f6f "fix scripts/no-such-file-at-all.sh — it is red" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader"

  CC_PREMISE_EVIDENCE_CHURN=off run "$CP" check 1a1a1a1a1a1a
  [ "$status" -eq 0 ]
  refute_match "$output" "EVIDENCE AGE"

  CC_PREMISE_EVIDENCE_CHURN=off run "$CP" check 6f6f6f6f6f6f
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = suspect ]
  printf '%s' "$output" | grep -q "no-such-file-at-all"
}

# ── the arm's boundary against the path arm it sits beside ───────────────────────────────────────

@test "an ABSENT path is the path arm's finding ALONE — it is never re-reported as churn" {
  # One file under two headings makes a reader distrust both. The exclusion is structural (the churn
  # arm receives only the paths the path arm resolved through cat-file), and this pins it.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 7a7a7a7a7a7a "scripts/target.sh and scripts/no-such-file-at-all.sh are both unpadded" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader"

  run "$CP" check 7a7a7a7a7a7a
  [ "$status" -eq 0 ]
  # The path arm still convicts the absent one…
  [ "$(verdict "$output")" = suspect ]
  printf '%s' "$output" | grep -q "not at that location on origin/main: scripts/no-such-file-at-all.sh"
  # …and the churn arm still speaks about the present one, in the same contract…
  printf '%s' "$output" | grep -q "EVIDENCE AGE"
  printf '%s' "$output" | grep -q "pad the reader"
  # …but its `cited:` line names ONLY the resolvable path.
  cited="$(printf '%s' "$output" | sed -n 's/^ *cited: //p')"
  [ "$cited" = "scripts/target.sh" ]
}

@test "a BARE BASENAME is excluded from the pathspec — it has no known directory to ask about" {
  # `deep-tool.sh` lives at `bin/deep-tool.sh`. The path arm clears it via the trunk basename set
  # WITHOUT learning where it is, so it is not a usable pathspec: handing git a bare basename either
  # matches nothing or matches a root file that does not exist. Excluding it is the honest read, and
  # the item below has no other cited path, so the arm must fall silent entirely.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 8b8b8b8b8b8b "the converger deep-tool.sh refuses" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" bin/deep-tool.sh "fix(deep-tool): stop refusing"

  run "$CP" check 8b8b8b8b8b8b
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "EVIDENCE AGE"
}

@test "a CROSS-PROJECT item is silent — this arm only ever speaks about THIS repo" {
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  printf '{"id":"9c9c9c9c9c9c","ts":"%s","event":"add","project":"reso-management-app","title":"the reader in scripts/target.sh is unpadded","source":"t"}\n' \
    "$(ts_ago 5d)" >> "$CC_BACKLOG_FILE"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader"

  run "$CP" check 9c9c9c9c9c9c
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "EVIDENCE AGE"
}
