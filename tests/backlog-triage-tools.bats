#!/usr/bin/env bats
# scripts/backlog-consolidation/{prune,verify,citegraph}.py — the triage toolkit (backlog ce1e9d1adab8).
#
# WHY THESE HAVE TESTS AT ALL NOW. All three ran once, in one hand-driven wave, from an UNTRACKED
# directory: `prune.py` closed 161 rows with 0 failures — the largest reduction this pile has ever
# seen — and nothing could have told anyone if it had closed the wrong 161. `prune.py` is the only
# tool in that directory that can destroy work rather than re-file it, so its verdict scoping is the
# assertion that matters and it is pinned in BOTH directions.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  D="$REPO/scripts/backlog-consolidation"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  export CC_BACKLOG_BIN="$CB"
  T="$BATS_TEST_TMPDIR/triage"; mkdir -p "$T"
}

refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }
add() { bash "$CB" add --project claude-infrastructure --title "$1" --source fx; }
status_of() { bash "$CB" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }

# ── prune.py — the only destructive tool here ───────────────────────────────────────────────────

@test "prune.py closes PRUNE and MERGE and NOTHING else" {
  p=$(add "a row the wave pruned"); m=$(add "a row the wave merged")
  k=$(add "a row the wave kept");   u=$(add "a row the wave wants updated")
  { printf '| id | verdict | reason |\n'
    printf '%s | PRUNE | refuted by measurement\n' "$p"
    printf '%s | MERGE | absorbed by a sibling\n' "$m"
    printf '%s | KEEP | still real\n' "$k"
    printf '%s | UPDATE | still real, reworded\n' "$u"; } > "$T/OUT-dispatch.md"
  run python3 "$D/prune.py" --dir "$T" --run
  [ "$status" -eq 0 ]
  [ "$(status_of "$p")" = "done" ]
  [ "$(status_of "$m")" = "done" ]
  [ "$(status_of "$k")" = "open" ]
  [ "$(status_of "$u")" = "open" ]
}

@test "prune.py is DRY by default — a verdict table alone closes nothing" {
  p=$(add "a row the wave pruned")
  printf '| %s | PRUNE | refuted |\n' "$p" > "$T/OUT-dispatch.md"
  run python3 "$D/prune.py" --dir "$T"
  [ "$status" -eq 0 ]
  [ "$(status_of "$p")" = "open" ]
  [ "$(printf '%s' "$output" | grep -c 'DRY RUN')" -eq 1 ]
}

@test "prune.py records WHY it closed, so a close is distinguishable from a silent drop" {
  p=$(add "a row the wave pruned")
  printf '| %s | PRUNE | its own date list ends before it was filed |\n' "$p" > "$T/OUT-dispatch.md"
  python3 "$D/prune.py" --dir "$T" --run --stamp "unit-test-pass"
  ev="$(bash "$CB" list --all --json | jq -r --arg i "$p" '.[]|select(.id==$i)|.evidence')"
  [ "$(printf '%s' "$ev" | grep -c 'unit-test-pass \[PRUNE/dispatch\]')" -eq 1 ]
  [ "$(printf '%s' "$ev" | grep -c 'date list ends before it was filed')" -eq 1 ]
}

@test "prune.py tolerates every shape the reports actually use, INCLUDING a markdown table row" {
  # THE LIVE FORMAT IS THE BARE ONE. Every verdict line in the 2026-08-09 reports begins with the id
  # (`grep -cE '^\| *`?[0-9a-f]{12}' OUT-*.md` = 0 across all ten), which is why the parser anchored
  # there — and why a markdown table row silently parsed as nothing until 2026-08-12.
  a=$(add "row a"); b=$(add "row b"); c=$(add "row c")
  { printf '%s | PRUNE | the live shape: bare id first |\n' "$a"
    printf '**%s** | PRUNE | bold id |\n' "$b"
    printf '| `%s` | **PRUNE** | a markdown table row |\n' "$c"; } > "$T/OUT-tail.md"
  python3 "$D/prune.py" --dir "$T" --run
  [ "$(status_of "$a")" = "done" ]
  [ "$(status_of "$b")" = "done" ]
  [ "$(status_of "$c")" = "done" ]
}

@test "prune.py refuses a directory that does not exist rather than reporting zero" {
  run python3 "$D/prune.py" --dir "$BATS_TEST_TMPDIR/nope" --run
  [ "$status" -eq 2 ]
  refute_match "$output" '0 rows to close'
}

# ── verify.py — the gate that makes prune.py safe to run ────────────────────────────────────────

@test "verify.py rc 1 on a GAP: a row handed to a slice with no verdict is not 'kept'" {
  printf '[{"id":"aaaaaaaaaaaa"},{"id":"bbbbbbbbbbbb"}]\n' > "$T/cluster-C-dispatch.json"
  printf '| aaaaaaaaaaaa | KEEP | adjudicated |\n' > "$T/OUT-dispatch.md"
  run python3 "$D/verify.py" --dir "$T"
  [ "$status" -eq 1 ]
  [ "$(printf '%s' "$output" | grep -c 'MISSING')" -eq 1 ]
}

@test "verify.py rc 0 when a slice is complete, and it emits verdicts.json for link.py" {
  printf '[{"id":"aaaaaaaaaaaa"},{"id":"bbbbbbbbbbbb"}]\n' > "$T/cluster-C-dispatch.json"
  { printf '| aaaaaaaaaaaa | KEEP | adjudicated |\n'
    printf '| bbbbbbbbbbbb | PRUNE | refuted |\n'; } > "$T/OUT-dispatch.md"
  run python3 "$D/verify.py" --dir "$T" --slices <(printf '{"dispatch":["C-dispatch"]}\n')
  [ "$status" -eq 0 ]
  [ -f "$T/verdicts.json" ]
  [ "$(jq -r '.aaaaaaaaaaaa[1]' "$T/verdicts.json")" = "KEEP" ]
}

# ── citegraph.py — the derived ordering signal ──────────────────────────────────────────────────

@test "citegraph.py counts a real citation and refuses a self-reference" {
  a=$(add "the root row")
  b=$(add "a sibling that names $a as its cause")
  run python3 "$D/citegraph.py" --scope all --top 5
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | grep -c "in= 1 .* $a")" -eq 1 ]
  # $b cites $a, so $b has out-degree 1 and in-degree 0 — it must not appear in the in-degree list.
  refute_match "$output" "in= 1 .* $b"
}

@test "citegraph.py does not count a 12-hex token that resolves to no row (a git sha)" {
  a=$(add "a row citing commit deadbeef1234 which is a sha, not a row")
  run python3 "$D/citegraph.py" --scope all --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq --arg i "$a" '.[]|select(.id==$i)|.out')" -eq 0 ]
  [ "$(printf '%s' "$output" | jq '[.[]|select(.id=="deadbeef1234")]|length')" -eq 0 ]
}
