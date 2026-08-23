#!/usr/bin/env bats
# THE VENUE VERDICT AN `advance <plan>` ROW WOULD GET — scripts/plan-venue-census.py.
#
# THE DEFECT THIS CENSUS MEASURES (BACKLOG_DRAIN_24_7 §2.1, 2026-08-23). cc-discover's C2 critic
# mints one backlog row per open plan and its whole specification span is
# `advance <one-line title>` + the plan's path + the source word `plan-open` (cc-discover:273).
# cc-eligible classifies exactly that span, so a 15,000-line plan about `~/.claude` is judged on a
# ten-word headline. Live on this repo: 27 of 44 open plans mint a row reading `eligible`, i.e. the
# cloud lane will send it off-box — BACKLOG_DRAIN_24_7 itself among them, and the session that wrote
# this file is the exhibit.
#
# WHAT EACH ARM PINS, and the pair that matters is 1 + 2:
#   1  THE GAP ITSELF — a plan whose BODY names launchd and whose TITLE does not reads `eligible`.
#   2  POSITIVE CONTROL — the same word IN the title refuses. Without arm 2, arm 1 is equally
#      consistent with "the classifier is simply broken", and the census would be measuring nothing.
#   6  ONE TABLE, NOT A COPY — the property most likely to rot, and invisible to every other arm: a
#      re-typed spelling table passes arms 1-5 forever while drifting from the gate. Pointed at a
#      MUTANT cc-eligible carrying one extra spelling, the census verdict must move.
#   4+5 THE CONTROL ARM IS TWO-SIDED — it must print UNINFORMATIVE when the body refuses everything
#      and `discriminating` when it does not. A one-sided arm would pass against a hardcoded string.
#
# HERMETIC: fixture $HOME (rule 1 of test-hermeticity-lint), fixture plans dir, no backlog store, no
# network, no live layer. The census reads only files this suite creates plus the repo's own
# find-plan.sh and bin/cc-eligible.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CENSUS="$REPO/scripts/plan-venue-census.py"
  PLANS="$BATS_TEST_TMPDIR/plans"; mkdir -p "$PLANS"
  export CC_PLAN_SCAN_ROOTS="$PLANS"
  export CC_PLAN_INDEX="$BATS_TEST_TMPDIR/no-such-plan-index.json"
}

# plan <file> <title> <body...> — one open plan. `status: open` so find-plan.sh enumerates it;
# driven through the real find-plan.sh rather than a fixture list, because the census's contract is
# that the population comes from THAT reader and not from a fourth copy of plan_status().
plan() {
  local f="$PLANS/$1" title="$2"; shift 2
  { printf -- '---\nstatus: open\n---\n\n# %s\n\n' "$title"
    printf '%s\n' "$@"; } > "$f"
}

run_census() { run python3 "$CENSUS" --repo "$REPO" "$@"; }

# $output SUBSTRING ASSERTIONS AS ORDINARY COMMANDS. bash exempts `[[ ]]` from errexit, so a
# non-final `[[ "$output" == *x* ]]` in a bats body is evaluated and DISCARDED — the test passes on
# a false assertion (scripts/bats-assert-liveness.py; it flagged five of them in this file's first
# draft). `grep` is a simple command and is errexit-live in EVERY position, so these stay live no
# matter what is appended below them later.
has_out()   { printf '%s\n' "$output" | grep -qF -- "$1"; }
lacks_out() { ! printf '%s\n' "$output" | grep -qF -- "$1"; }

@test "1 THE GAP: a plan whose BODY names launchd and whose TITLE does not reads eligible" {
  plan gap.md "Widget rebuild — phase two" "the work runs under launchd on this box"
  run_census --json
  [ "$status" -eq 0 ]
  local v; v="$(printf '%s' "$output" | jq -r '.rows[] | select(.title | test("Widget rebuild")) | .span_verdict')"
  [ "$v" = eligible ]
}

@test "2 POSITIVE CONTROL: the same word IN the title refuses, so arm 1 is a span gap not a dead table" {
  plan named.md "Widget rebuild — the launchd job" "the work runs under launchd on this box"
  run_census --json
  [ "$status" -eq 0 ]
  local v t
  v="$(printf '%s' "$output" | jq -r '.rows[] | select(.title | test("Widget rebuild")) | .span_verdict')"
  t="$(printf '%s' "$output" | jq -r '.rows[] | select(.title | test("Widget rebuild")) | .span_tokens | join(",")')"
  [ "$v" = ineligible-box ]
  [ "$t" = launchd ]
}

@test "3 the ELIGIBLE bucket is PRINTED by title, not merely counted" {
  plan gap.md "Widget rebuild — phase two" "the work runs under launchd on this box"
  run_census
  [ "$status" -eq 0 ]
  has_out "ELIGIBLE bucket"
  has_out "Widget rebuild — phase two"
}

@test "4 CONTROL ARM, refusing side: every body local ⇒ UNINFORMATIVE" {
  plan a.md "Alpha rebuild"  "this runs under launchd"
  plan b.md "Bravo rebuild"  "this reads ~/.claude every pass"
  run_census
  [ "$status" -eq 0 ]
  has_out "body refuses 2 of 2"
  has_out "UNINFORMATIVE"
}

@test "5 CONTROL ARM, discriminating side: a body naming nothing local flips the message" {
  plan a.md "Alpha rebuild"  "this runs under launchd"
  plan b.md "Bravo rebuild"  "ordinary repo text about parsing a file and writing a report"
  run_census
  [ "$status" -eq 0 ]
  has_out "body refuses 1 of 2"
  has_out "discriminating here"
  lacks_out "UNINFORMATIVE"
}

@test "6 ONE TABLE: a spelling added to cc-eligible moves the census verdict" {
  plan gap.md "Widget rebuild — phase two" "ordinary repo text"
  # Baseline against the REAL table.
  run_census --json
  [ "$status" -eq 0 ]
  local before; before="$(printf '%s' "$output" | jq -r '.rows[0].span_verdict')"
  [ "$before" = eligible ]

  # A MUTANT cc-eligible whose BOX list gains one spelling that the fixture title carries. Built by
  # editing a copy, so nothing here can touch the real file. The anchor is counted before and after
  # so a silently-missed edit cannot pass this arm as a false green.
  local mut="$BATS_TEST_TMPDIR/cc-eligible-mutant"
  cp "$REPO/bin/cc-eligible" "$mut"
  run grep -c '^BOX = \[$' "$mut"
  [ "$output" = 1 ]
  sed -i.bak 's/^BOX = \[$/BOX = [\n    ("widget", r"\\bwidget\\b"),/' "$mut"
  run grep -c '("widget"' "$mut"
  [ "$output" = 1 ]

  CC_CENSUS_ELIGIBLE="$mut" run_census --json
  [ "$status" -eq 0 ]
  local after tok
  after="$(printf '%s' "$output" | jq -r '.rows[0].span_verdict')"
  tok="$(printf '%s' "$output" | jq -r '.rows[0].span_tokens | join(",")')"
  [ "$after" = ineligible-box ]
  [ "$tok" = widget ]
}

@test "7 CENSUS, NOT A GATE: exit 0 even when every plan reads ineligible" {
  plan a.md "Alpha — the launchd job" "this runs under launchd"
  run_census
  [ "$status" -eq 0 ]
  has_out "ineligible-box"
}

@test "8 an empty plans dir is a census of nothing, not an error" {
  run_census
  [ "$status" -eq 0 ]
  has_out "open plans  0"
  has_out "nothing to census"
}

@test "9 UNUSABLE ENVIRONMENT is exit 3, distinct from a clean census" {
  plan a.md "Alpha rebuild" "ordinary repo text"
  CC_CENSUS_ELIGIBLE="$BATS_TEST_TMPDIR/absent-cc-eligible" run_census
  [ "$status" -eq 3 ]
  has_out "cc-eligible absent"
}
