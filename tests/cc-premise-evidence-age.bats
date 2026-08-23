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
# THE STAMP CONTROL IS THE LOAD-BEARING ONE, and it is not the obvious one — see the note on the
# LOOSE STAMP test. One stamp is read TWICE, by two different parsers: Python computes the age
# against the floor from it, and git takes it as `--since=`. Garbage is the harmless case, because
# both refuse it. The shapes that bite are the ones BOTH accept and read DIFFERENTLY, because a
# stamp neither parser flags is the one that produces a confident sentence counting commits over a
# window that is not the window the age was measured from.
#
# The last half of this file covers the other question the arm raises — not "is the answer right"
# but WHO IS ASKED IT AND WHEN — at `cc-backlog unblock`, the one transition that re-admits an item
# to the dispatch wave with nothing re-reading what it says.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CP="$REPO/bin/cc-premise"
  CB="$REPO/bin/cc-backlog"
  # $HOME first: cc-premise defaults its store under $HOME, so an unfixtured suite would read the
  # operator's live ledger (memory: unfixtured-sensor-executes-the-deployed-subject). The explicit
  # CC_BACKLOG_FILE beside it says WHICH store this suite means.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # EXPLICITLY EMPTY, not unset: an unset variable defaults to cc-premise's own checkout, and these
  # assertions would then depend on this repo's real history.
  export CC_PREMISE_REPO=
  # …AND THE SIBLING SET IS THE SECOND SUCH STORE, which this suite did not know it read. The path
  # arm now widens a miss across every `repo=` row in scripts/dispatch-projects.conf before it may
  # convict, so leaving this unset points three of these tests at the OPERATOR's checkouts. It is
  # not even a stable dependency: the rows expand with `~`, which resolves against the fixtured
  # $HOME above, so they land on paths that do not exist, degrade to "could not ask" — and the arm
  # correctly declines to convict, turning three suspect assertions green-side-up. MEASURED, not
  # reasoned: instrumenting the widening showed exactly this file (3 hits) and
  # cc-premise-postland-red.bats (1) reaching it unpinned. Explicit-empty disables the widening.
  export CC_DISPATCH_PROJECTS_CONF=
  : > "$CC_BACKLOG_FILE"
}

# blocked <id> <title> <ts> — an item filed and then blocked, i.e. the exact population the
# re-admission tests are about. Written as records rather than driven through the verbs so the
# filing STAMP is under this file's control; `add` would stamp it at now and no age test could exist.
blocked() {
  add "$1" "$2" "$3"
  printf '{"id":"%s","ts":"%s","event":"block","needs":"an operator step"}\n' "$1" "$3" \
    >> "$CC_BACKLOG_FILE"
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
  # The two names that make the basename arm's boundary testable, and both are needed: `shared.sh`
  # is carried by TWO directories (the only case where "no known directory" is actually true), and
  # `café.sh` is what `ls-tree --name-only` mangles into `"bin/caf\303\251.sh"` unless the read asks
  # for -z. The non-ASCII spelling is the REACHABLE one and an embedded quote is not: RE_PATH's
  # character class is `[\w./@-]`, which excludes `"` (so a `wei"rd.sh` fixture is only ever seen as
  # `rd.sh`) but `\w` is unicode-aware in Python 3 and matches `café`. Verified on this box —
  # core.precomposeunicode is true, so git stores the NFC form this file is written in.
  printf 'seed\n' > "$r/scripts/shared.sh"
  printf 'seed\n' > "$r/bin/shared.sh"
  printf 'seed\n' > "$r/bin/café.sh"
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

@test "a UNIQUELY-carried bare basename REACHES the arm, named by where it resolved" {
  # THIS TEST USED TO ASSERT THE OPPOSITE, and the reversal is the lesson worth keeping. It read
  # "a BARE BASENAME is excluded — it has no known directory to ask about", and its reasoning was
  # true of the implementation rather than of the world: `_trunk_basenames` cleared the name against
  # a SET built by discarding the directory, and the exclusion was then justified by that discard.
  # `deep-tool.sh` is carried by exactly one file on trunk, so its directory was never unknown.
  #
  # What moved the judgment was a measurement, not an argument. Over the 385 live items on
  # 2026-08-11 the exclusion silenced this arm for 47 of the 179 that name a file — 26% — with 22
  # already sitting on reportable churn, while the ambiguity it guarded against reached exactly ONE
  # (memory: caller-census-keyed-on-path-misses-the-name; stale-assertion-becomes-an-inverted-guard,
  # since a test pinning a decision its own premise has outlived guards the defect).
  #
  # The `cited:` assertion is the load-bearing half: the block must name bin/deep-tool.sh, the path
  # it ASKED GIT ABOUT, not the bare spelling the item happened to use. A reader who cannot tell
  # which file the commit list came from cannot check the finding.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 8b8b8b8b8b8b "the converger deep-tool.sh refuses" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" bin/deep-tool.sh "fix(deep-tool): stop refusing"

  run "$CP" check 8b8b8b8b8b8b
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "EVIDENCE AGE"
  printf '%s' "$output" | grep -q "1 commit(s) have landed"
  printf '%s' "$output" | grep -q "stop refusing"
  cited="$(printf '%s' "$output" | sed -n 's/^ *cited: //p')"
  [ "$cited" = "bin/deep-tool.sh" ]
  # Still ADVISORY. Resolving a name tells us where to look; it says nothing about whether the
  # premise died, so the verdict must be untouched exactly as it is for a literal path.
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "not at that location"
}

@test "an AMBIGUOUS bare basename stays excluded — there the directory really IS unknown" {
  # The other half of the boundary, and the control that stops the fix above from becoming "resolve
  # every name somehow". `shared.sh` is carried by scripts/ AND bin/; picking either would report
  # churn from a file the item never meant, and reporting both would attribute one file's commits to
  # another. Silence is the honest answer, and it is the answer the old blanket exclusion was
  # actually right about.
  #
  # BOTH CARRIERS ARE COMMITTED TO, and that is the whole reason this control can fail. Its first
  # version touched only scripts/shared.sh and went green against the mutant that deletes the
  # `len(hits) == 1` guard — that mutant takes hits[0], which ls-tree orders as bin/shared.sh, so it
  # resolved to the WRONG file, found nothing under it, and fell silent for a reason that has
  # nothing to do with the property under test (memory: control-must-replay-the-real-artifact).
  # With churn under both, every possible resolution speaks and only the exclusion is silent, so the
  # assertion no longer depends on which name ls-tree happens to return first.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 8c8c8c8c8c8c "the helper shared.sh drops a field" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" scripts/shared.sh "fix(shared): pad the field"
  commit_at "$r" "$(ts_ago 2d)" bin/shared.sh "fix(shared): pad the other one"

  run "$CP" check 8c8c8c8c8c8c
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "EVIDENCE AGE"
  # …and it is excluded, never CONVICTED: an ambiguous name is still present on trunk.
  refute_match "$output" "not at that location"
}

@test "a bare basename NO trunk file carries is REPORTED, never CONVICTED — it named no location" {
  # THE FALSE POSITIVE BY CONSTRUCTION (backlog a431c71076e6, measured on cf6eb3e47b12). The
  # ambiguous case above is acquitted for a reason that reads as "still present on trunk", which
  # left the ZERO-carrier case convicted by default — and that case is not a rare tail here. The
  # memory-index condition re-mints an item citing `MEMORY.md` every few days; that file is the
  # user auto-memory index under ~/.claude*/projects/<encoded-cwd>/memory/, is not a repo file at
  # all, and therefore can NEVER carry a trunk basename. Live on origin/main at filing time both
  # open memory-index rows (0b3d53bcd1fd, 7c266e16fc94) read `verdict=suspect` off this sentence
  # alone. The cost is not the wasted detour: an alarm that fires on a whole population trains a
  # worker to discount it where it is REAL (memory: alarm-polarity-and-attention-budget).
  #
  # "not at THAT location" presupposes the item named one. A bare basename does not, so git was
  # never told where to look and a miss is not absence (memory: lookup-miss-is-not-absence).
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 8e8e8e8e8e8e "MEMORY.md is 25.9KB over its 24.4KB loader cap" "$(ts_ago 5d)"

  run "$CP" check 8e8e8e8e8e8e
  [ "$status" -eq 0 ]
  # VERDICT-NEUTRAL, exactly like the churn arm: "I was not told where this lives" is not evidence
  # that the premise died, and `suspect` is what cc-backlog claim surfaces to the worker.
  [ "$(verdict "$output")" = clear ]
  refute_match "$output" "not at that location"
  # …but it is not SILENT either — the name is still reported, in words that concede what git was
  # never asked. Silence would lose the genuinely-never-landed bare name along with the false ones.
  printf '%s' "$output" | grep -q "CITED NAME(S) with no directory component"
  printf '%s' "$output" | grep -q "MEMORY.md"
}

@test "the split does NOT soften the real finding — a directory-bearing absent path still convicts" {
  # The control that stops the fix above from becoming "stop convicting cited paths". Both kinds are
  # cited by ONE item, with the bare name FIRST so the pre-fix ordering is the one under test: with
  # a single list the sentence read `MEMORY.md, scripts/no-such-file-at-all.sh` and the real finding
  # was buried behind the fabricated one. The two must now appear under different headings.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 8f8f8f8f8f8f \
    "MEMORY.md is over cap and scripts/no-such-file-at-all.sh is unpadded" "$(ts_ago 5d)"

  run "$CP" check 8f8f8f8f8f8f
  [ "$status" -eq 0 ]
  [ "$(verdict "$output")" = suspect ]
  # The real finding, ALONE on its line — pre-fix the bare name preceded it and this grep missed.
  line="$(printf '%s' "$output" | grep 'not at that location')"
  printf '%s' "$line" | grep -q "origin/main: scripts/no-such-file-at-all.sh — moved"
  # …and the bare name is NOT inside that sentence, which is the whole boundary.
  refute_match "$line" "MEMORY.md"
  printf '%s' "$output" | grep -q \
    "CITED NAME(S) with no directory component and no carrier on origin/main: MEMORY.md"
}

@test "the trunk read is -z, so a QUOTED path is neither convicted nor mis-asked" {
  # `ls-tree -r --name-only` C-quotes any path carrying a non-ASCII byte, so bin/café.sh comes back
  # as the literal characters `"bin/caf\303\251.sh"`. Under that read the basename set holds a
  # mangled key, the cited name misses it, and the path arm convicts a file that has never moved.
  # Now that the same entry is handed to git AS A PATHSPEC the second failure is quieter and worse:
  # a pathspec matching nothing counts zero commits, so the arm falls silent while looking like it
  # asked (memory: lookup-miss-is-not-absence).
  #
  # BOTH assertions are needed and they fail differently — the first catches the mangled SET (a
  # fabricated "not at that location"), the second catches the mangled PATHSPEC (a silent arm). A
  # test asserting only the first would pass with the -z dropped from the churn read alone.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 8d8d8d8d8d8d "the wrapper café.sh mis-splits" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" "bin/café.sh" "fix(cafe): split on tabs"

  run "$CP" check 8d8d8d8d8d8d
  [ "$status" -eq 0 ]
  refute_match "$output" "not at that location"
  printf '%s' "$output" | grep -q "EVIDENCE AGE"
  printf '%s' "$output" | grep -q "split on tabs"
}

@test "ONE file cited under TWO spellings is one pathspec, not two" {
  # An item that says both `scripts/target.sh` and `target.sh` resolves to the same file twice. The
  # list is printed to a human and handed to git, so the duplicate is noise in the contract and a
  # repeated pathspec in the count — and a `cited:` line naming one file twice reads as two pieces
  # of evidence.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 8e8e8e8e8e8e "scripts/target.sh is unpadded, and target.sh has no test" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader"

  run "$CP" check 8e8e8e8e8e8e
  [ "$status" -eq 0 ]
  cited="$(printf '%s' "$output" | sed -n 's/^ *cited: //p')"
  [ "$cited" = "scripts/target.sh" ]
  # The COUNT must not double either — the headline number is the one a reader acts on.
  printf '%s' "$output" | grep -q "1 commit(s) have landed"
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

# ── the re-admission re-read: cc-backlog unblock (backlog f46261b23ec2) ──────────────────────────
#
# The arm above answers the question; this half decides WHO IS ASKED IT AND WHEN. `unblock` is the
# one transition that returns an item to cc-dispatch's fire predicate without anything re-reading
# what it says, and blocked items are the ones that have sat longest — so it is the transition where
# stale evidence is most likely and least visible. Everything below is advisory by construction: the
# assertions pair "it speaks" with "and the transition still happened anyway".

@test "unblock SURFACES the contract, and the transition still succeeds" {
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  blocked 1a1a1a1a1a1a "the reader in scripts/target.sh is unpadded" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader at the emitter"

  run --separate-stderr "$CB" unblock 1a1a1a1a1a1a
  [ "$status" -eq 0 ]
  # STDOUT IS THE ID CONTRACT and every caller captures it. The advisory must not reach it, and
  # neither must cc-premise's `verdict=` line — which is what the `2>&1 >/dev/null` ORDER buys. The
  # reversed spelling `>/dev/null 2>&1` captures nothing and this test's stderr half goes silent;
  # a bare `2>&1` publishes the verdict into the advisory, which the last assertion catches.
  [ "$output" = "1a1a1a1a1a1a" ]
  printf '%s' "$stderr" | grep -q "RE-READ ITS EVIDENCE FIRST"
  printf '%s' "$stderr" | grep -q "EVIDENCE AGE"
  printf '%s' "$stderr" | grep -q "pad the reader at the emitter"
  refute_match "$stderr" "verdict="
  # …and it ADVISED, it did not gate: the fold is open, which is the whole point of the verb.
  run "$CB" list --all --json
  [ "$(printf '%s' "$output" | jq -r '.[0].status')" = open ]
}

@test "unblock is SILENT when the premise has nothing to say" {
  # The ambience control. Without it the advisory could print its header unconditionally and every
  # assertion above would still pass, on a channel that says the same thing about every item and so
  # says nothing about any of them (memory: alarm-polarity-and-attention-budget).
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  blocked 3c3c3c3c3c3c "the reader in scripts/untouched.sh is unpadded" "$(ts_ago 5d)"

  run --separate-stderr "$CB" unblock 3c3c3c3c3c3c
  [ "$status" -eq 0 ]
  [ "$output" = "3c3c3c3c3c3c" ]
  refute_match "$stderr" "RE-READ ITS EVIDENCE"
}

@test "REOPEN does not carry it — the machine paths would make this ambient" {
  # `reopen` folds to "open" exactly as unblock does, so the scoping is a decision, not an accident:
  # it is overwhelmingly cc-dispatch self-releasing a fire it could not make and reap returning a
  # dead worker's claim, where there is no deciding reader to inform. This pins the decision so a
  # later "make it consistent" cannot quietly flood those paths.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  add 1a1a1a1a1a1a "the reader in scripts/target.sh is unpadded" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader at the emitter"

  run --separate-stderr "$CB" reopen 1a1a1a1a1a1a
  [ "$status" -eq 0 ]
  refute_match "$stderr" "RE-READ ITS EVIDENCE"
}

@test "CC_BACKLOG_PREMISE_GATE=off silences the re-read, same switch as the claim gate" {
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  blocked 1a1a1a1a1a1a "the reader in scripts/target.sh is unpadded" "$(ts_ago 5d)"
  commit_at "$r" "$(ts_ago 2d)" scripts/target.sh "fix(target): pad the reader at the emitter"

  CC_BACKLOG_PREMISE_GATE=off run --separate-stderr "$CB" unblock 1a1a1a1a1a1a
  [ "$status" -eq 0 ]
  [ "$output" = "1a1a1a1a1a1a" ]
  refute_match "$stderr" "RE-READ ITS EVIDENCE"
}

@test "FAIL-OPEN: a cc-premise that is absent, or that crashes, cannot fail the unblock" {
  # THE STAKES CLAUSE. unblock is a RECOVERY verb — scripts/thrash-block-recover.sh drives it to pull
  # work back out of the operator-only `blocked` state — so an advisory that could break it would
  # convert a sensor failure into a permanently un-recoverable queue. Both shapes are asserted: no
  # binary at all, and a binary that exits non-zero with nothing useful to say.
  r="$(mkrepo)"
  export CC_PREMISE_REPO="$r"
  crasher="$BATS_TEST_TMPDIR/crasher"
  printf '#!/bin/sh\nexit 9\n' > "$crasher"; chmod +x "$crasher"

  blocked 1a1a1a1a1a1a "the reader in scripts/target.sh is unpadded" "$(ts_ago 5d)"
  CC_BACKLOG_PREMISE_BIN="$BATS_TEST_TMPDIR/no-such-cc-premise" run "$CB" unblock 1a1a1a1a1a1a
  [ "$status" -eq 0 ]
  [ "$output" = "1a1a1a1a1a1a" ]

  blocked 2b2b2b2b2b2b "the reader in scripts/target.sh is unpadded" "$(ts_ago 5d)"
  CC_BACKLOG_PREMISE_BIN="$crasher" run "$CB" unblock 2b2b2b2b2b2b
  [ "$status" -eq 0 ]
  [ "$output" = "2b2b2b2b2b2b" ]
  run "$CB" list --all --json
  [ "$(printf '%s' "$output" | jq -r 'map(select(.id=="2b2b2b2b2b2b"))[0].status')" = open ]
}
