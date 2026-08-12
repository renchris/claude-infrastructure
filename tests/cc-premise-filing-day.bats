#!/usr/bin/env bats
# cc-premise `screen` — THE SECOND SCREEN: would this probe have FAILED on the day its item was filed?
#
# WHY THIS EXISTS. `run_falsifier` asks "does the probe pass NOW?" — the first screen, and it catches
# the probe that agrees with a world where the item is finished. It is blind to the commoner failure.
# The CURRENCY pass (docs/plans/BACKLOG_CONSOLIDATION_2026-08-09.md) hand-reviewed 26 stored probes,
# refuted 16, and measured the dominant class at 8 instances against 2 for the next: **the grep was
# already true at filing**. Such a probe discriminates NOTHING — it would have retracted its item the
# moment it was written — so the row reads as covered while being a guaranteed false retraction.
#
# THE THREE-STATE ANSWER IS THE POINT, and cases 3-6 + 9 are what stop it collapsing back to two.
# Most stored probes are not tree questions at all (they call a script, read $HOME, pipe through awk),
# and this repo has paid for a two-state answer to a three-state question before
# (memory: abstain-rule-can-retire-the-common-case). Folding UNDECIDABLE into DISCRIMINATING issues a
# clean bill of health over a population never examined; folding it into ANTI-COVERAGE convicts every
# probe the parser is merely too narrow to read. It is its own state and it is the DEFAULT on failure.
#
# THE TWO DIRECTIONS OF THE WIRING ARE BOTH PINNED (cases 7 and 8), and only pinning one would be
# worse than pinning neither: case 7 proves an anti-coverage probe no longer retracts an item, and
# case 8 proves a DISCRIMINATING probe still does. Without case 8, an arm that simply disabled the
# falsifier would pass this suite — a screen that always downgrades is the falsifier deleted.
#
# Assertions use `printf | grep -q` or an explicit `|| false`: a non-final `[[ ]]` is errexit-EXEMPT
# under bats and would be a DEAD assertion that can never fail (the land gate's lint refuses those).
#
# RED-PROOF (re-runnable): `git show origin/main:bin/cc-premise` has no `screen` verb and no
# filing-day arm, so every case below fails against it — 1-6 and 9-13 because the verb exits 2
# ("unknown verb screen"), and case 7 because that build REFUSES the claim (rc 3) exactly as this
# change exists to stop. Case 8 passes there too, which is correct: it pins behaviour this change had
# to PRESERVE, and is the control that the downgrade is one-way rather than universal. Replay with:
#   CC_PREMISE_UNDER_TEST=<(git show origin/main:bin/cc-premise) is NOT usable (no exec bit) — copy:
#   git show origin/main:bin/cc-premise > /tmp/old-premise && chmod +x /tmp/old-premise \
#     && CC_PREMISE_UNDER_TEST=/tmp/old-premise bats tests/cc-premise-filing-day.bats

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # The SUBJECT is overridable for the RED-PROOF replay above and defaults to this worktree's copy,
  # so the green run and the red run execute one identical suite rather than two hand-kept variants
  # (memory: control-must-replay-the-real-artifact).
  PREMISE="${CC_PREMISE_UNDER_TEST:-$REPO/bin/cc-premise}"
  BACKLOG_BIN="$REPO/bin/cc-backlog"

  # HERMETIC $HOME, not merely a redirected store — both subjects DEFAULT to
  # ~/.claude/autonomy/backlog.jsonl, so a suite that only overrides the override is one unset
  # variable away from the operator's live ledger.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/autonomy"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  : > "$CC_BACKLOG_FILE"

  # ── THE FIXTURE REPO ────────────────────────────────────────────────────────────────────────────
  # Three landings on a fake trunk, with FIXED dates, straddling one filing instant:
  #   2020-01-01  early.txt  contains EARLY_TOKEN      ← already there when the item was filed
  #   2020-02-01  ══ items below are filed at this instant ══
  #   2020-03-01  late.txt   contains LATE_TOKEN       ← the remedy's own signature
  # `origin/main` is a real remote-tracking ref because `_git_usable` resolves exactly that one, and
  # a fixture that skipped it would exercise the fail-open path instead of the arm.
  export FIXREPO="$BATS_TEST_TMPDIR/repo"; mkdir -p "$FIXREPO"
  git -C "$FIXREPO" init -q
  git -C "$FIXREPO" config user.email t@t; git -C "$FIXREPO" config user.name t
  _commit "$FIXREPO" 2020-01-01T00:00:00Z early.txt EARLY_TOKEN
  _commit "$FIXREPO" 2020-03-01T00:00:00Z late.txt LATE_TOKEN
  git -C "$FIXREPO" update-ref refs/remotes/origin/main HEAD
  export CC_PREMISE_REPO="$FIXREPO"
}

_commit() {  # repo date path content
  printf '%s\n' "$4" > "$1/$3"
  git -C "$1" add "$3"
  GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" commit -qm "add $3"
}

# An item filed at a CHOSEN instant. Written straight to the ledger rather than through
# `cc-backlog add`, because the whole subject under test is the relationship between the filing
# timestamp and the tree — and `add` can only ever stamp `now`.
_file_item() {  # id ts [falsifier]
  python3 - "$CC_BACKLOG_FILE" "$1" "$2" "${3-}" <<'PY'
import json, sys
path, iid, ts, fals = sys.argv[1:5]
rec = {"id": iid, "ts": ts, "event": "add", "project": "claude-infrastructure",
       "title": "a condition observed at filing time"}
if fals:
    rec["falsifier"] = fals
open(path, "a").write(json.dumps(rec) + "\n")
PY
}

FILED=2020-02-01T00:00:00Z

# ── 1-2 · THE CORE DISCRIMINATION ────────────────────────────────────────────────────────────────

@test "a token ALREADY in the tree at filing -> ANTI-COVERAGE" {
  _file_item aaaaaaaaaaaa "$FILED"
  run "$PREMISE" screen aaaaaaaaaaaa --probe 'grep -q EARLY_TOKEN early.txt'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=ANTI-COVERAGE"
}

@test "a token that arrived AFTER filing -> DISCRIMINATING" {
  _file_item bbbbbbbbbbbb "$FILED"
  run "$PREMISE" screen bbbbbbbbbbbb --probe 'grep -q LATE_TOKEN late.txt'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=DISCRIMINATING"
}

# ── 3-6 · UNDECIDABLE IS ITS OWN STATE, ON EVERY FAILURE PATH ────────────────────────────────────

@test "a probe that is not a tree question at all -> UNDECIDABLE, not either neighbour" {
  _file_item cccccccccccc "$FILED"
  run "$PREMISE" screen cccccccccccc --probe 'scripts/some-helper.sh --assert'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=UNDECIDABLE"
}

# An absolute path is the sharpest case: it is not in ANY git tree, so a parser that resolved it
# would report "absent at filing" for the whole $HOME/-reading class and convict it as
# DISCRIMINATING on a lookup that could only ever miss (memory: lookup-miss-is-not-absence).
@test "a probe reading a path outside the repo -> UNDECIDABLE, never 'absent'" {
  _file_item dddddddddddd "$FILED"
  run "$PREMISE" screen dddddddddddd --probe 'test -f /etc/hosts'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=UNDECIDABLE"
}

@test "an unreadable repo -> UNDECIDABLE — a sensor failure is never a verdict" {
  _file_item eeeeeeeeeeee "$FILED"
  CC_PREMISE_REPO="" run "$PREMISE" screen eeeeeeeeeeee --probe 'grep -q EARLY_TOKEN early.txt'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=UNDECIDABLE"
}

@test "an item filed BEFORE any trunk commit -> UNDECIDABLE, not a free pass" {
  _file_item ffffffffffff 2019-01-01T00:00:00Z
  run "$PREMISE" screen ffffffffffff --probe 'grep -q EARLY_TOKEN early.txt'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=UNDECIDABLE"
}

# ── 7-8 · THE WIRING, BOTH DIRECTIONS ────────────────────────────────────────────────────────────

# THE LOAD-BEARING CASE. The probe exits 0 today, so `check` is about to refuse the claim (rc 3) —
# and it already passed on filing day, so that refusal retracts work no one ever did. The screen
# downgrades it to advisory. Against origin/main this test returns 3 and fails, which is the RED.
@test "a falsifier that ALREADY passed at filing does NOT retract the item" {
  _file_item 111111111111 "$FILED" 'grep -q EARLY_TOKEN early.txt'
  run "$PREMISE" check 111111111111
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=clear"
  printf '%s' "$output" | grep -q "ANTI-COVERAGE"
  # …and the contradicted instruction is GONE: a contract must not carry "close it citing this run"
  # beside a line explaining that the run proves nothing.
  run bash -c "'$PREMISE' check 111111111111 2>&1"
  # `! A || false`, NOT `A && false || true`: the latter is the `&&`-absorbed form the land gate's
  # dead-assertion ratchet refuses, because both branches reach the trailing `|| true` and the
  # assertion can never fail. Mutant-verified in both directions, not by the analyzer alone.
  ! printf '%s' "$output" | grep -q "Close it citing this run" || false
}

# THE CONTROL WITHOUT WHICH CASE 7 PROVES NOTHING. A probe that genuinely discriminates and passes
# today is a real retraction and must STILL refuse — otherwise "downgrade anti-coverage" and "delete
# the falsifier" are the same implementation and this suite cannot tell them apart.
@test "a DISCRIMINATING falsifier that passes today still REFUSES the claim" {
  _file_item 222222222222 "$FILED" 'grep -q LATE_TOKEN late.txt'
  run "$PREMISE" check 222222222222
  [ "$status" -eq 3 ]
  printf '%s' "$output" | grep -q "verdict=falsified"
}

# ── 9-11 · THE PARSER'S OWN EDGES, EACH MEASURED RATHER THAN ASSUMED ─────────────────────────────

# A `$` inside double quotes is a regex ANCHOR, not an expansion. The first draft screened raw
# substrings and retired this class — 4 of the 16 hand-refuted probes, i.e. exactly the precise,
# anchored ones. Quoting is judged by POSITION, so this must stay decidable.
@test "a quoted regex anchor is shell-literal, so the probe stays decidable" {
  _file_item 333333333333 "$FILED"
  run "$PREMISE" screen 333333333333 --probe 'grep -q "^EARLY_TOKEN$" early.txt'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=ANTI-COVERAGE"
}

@test "a REAL expansion is still beyond the parser -> UNDECIDABLE" {
  _file_item 444444444444 "$FILED"
  run "$PREMISE" screen 444444444444 --probe 'grep -q "$HOME" early.txt'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=UNDECIDABLE"
}

# 🚨 THE CASE THAT REVERSED ONE OF THE PLAN'S OWN THREE NAMED ITEMS. `80e6637dfd9e` is listed there
# as anti-coverage because its token "landed 8 days before its item" — read off an AUTHOR date of a
# commit that reached trunk a day AFTER the filing. Only the COMMIT date can make a probe pass, and
# a log search sorted the other way says the opposite of the tree. Unpinned, this regresses silently.
@test "authored before filing but LANDED after -> DISCRIMINATING (commit date, never author date)" {
  printf 'LATE_LANDING_TOKEN\n' > "$FIXREPO/slow.txt"
  git -C "$FIXREPO" add slow.txt
  GIT_AUTHOR_DATE=2020-01-15T00:00:00Z GIT_COMMITTER_DATE=2020-04-01T00:00:00Z \
    git -C "$FIXREPO" commit -qm "authored early, landed late"
  git -C "$FIXREPO" update-ref refs/remotes/origin/main HEAD
  _file_item 555555555555 "$FILED"
  run "$PREMISE" screen 555555555555 --probe 'grep -q LATE_LANDING_TOKEN slow.txt'
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "verdict=DISCRIMINATING"
}

# ── 12-13 · THE RETRO-SCAN ───────────────────────────────────────────────────────────────────────

# THE DENOMINATOR CONTROL FOR THE SCAN ITSELF. `screen --all` reads the FOLD (cc-backlog) while
# `screen <id>` reads the raw ledger, so a zero from the scan is only meaningful once the scan path
# has been shown able to fire at all (memory: positive-control-the-denominator).
@test "the retro-scan reports a three-way tally and NAMES its anti-coverage rows" {
  _file_item 666666666666 "$FILED" 'grep -q EARLY_TOKEN early.txt'
  _file_item 777777777777 "$FILED" 'grep -q LATE_TOKEN late.txt'
  _file_item 888888888888 "$FILED" 'scripts/some-helper.sh --assert'
  run "$PREMISE" screen --all
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "DISCRIMINATING *1"
  printf '%s' "$output" | grep -q "ANTI-COVERAGE *1"
  printf '%s' "$output" | grep -q "UNDECIDABLE *1"
  printf '%s' "$output" | grep -q "666666666666"
  # The evidence, not merely the verdict: the sha/date proving the token pre-dated the filing.
  printf '%s' "$output" | grep -q "already in the tree before filing"
}

# IT REPORTS, IT DOES NOT ACT. A non-zero here would invite a caller to wire the scan into a gate
# that clears probes automatically — and the CURRENCY pass earned the opposite rule: 16 of 26
# "checked" probes did not survive a reader briefed to refute them, so retirement stays a human's
# call through `cc-backlog falsify --clear`.
@test "the scan never clears a probe and never exits non-zero" {
  _file_item 999999999999 "$FILED" 'grep -q EARLY_TOKEN early.txt'
  run "$PREMISE" screen --all
  [ "$status" -eq 0 ]
  run "$BACKLOG_BIN" list --all --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q "EARLY_TOKEN"
}
