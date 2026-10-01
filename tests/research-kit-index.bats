#!/usr/bin/env bats
# research-kit-index — scripts/research-kit/research-index.py writes docs/research/INDEX.jsonl
# (REPORT.md §3.2 step 1): one {topic, path, date, status} row per entry, and --check fails on a
# stale index, so mining never reads an index that silently misses new research.

setup() {
  unset CC_BATS_ACTIVE
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  X="$REPO/scripts/research-kit/research-index.py"
  R="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$R/docs/research/prog-2026-09-30/evidence"
  git -C "$R" init -q
  git -C "$R" config user.email t@example.com
  git -C "$R" config user.name t
  printf -- '---\nstatus: open\n---\n# Dated note\n' > "$R/docs/research/NOTE_2026-08-01.md"
  printf '# Program report\n**Status:** research complete — see below\n' > "$R/docs/research/prog-2026-09-30/REPORT.md"
  printf 'no heading here\n' > "$R/docs/research/LEDGER.md"
  git -C "$R" add -A
  GIT_AUTHOR_DATE="2026-07-04T12:00:00" GIT_COMMITTER_DATE="2026-07-04T12:00:00" git -C "$R" commit -qm init
}

row() { /usr/bin/python3 -c "
import json
for l in open('$R/docs/research/INDEX.jsonl'):
    r = json.loads(l)
    if r['path'] == '$1': print(r['$2'])"; }

@test "every entry gets a topic, date and status from its own text or git" {
  run "$X" --root "$R"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$R/docs/research/INDEX.jsonl")" -eq 3 ]
  [ "$(row docs/research/NOTE_2026-08-01.md topic)" = "Dated note" ]
  [ "$(row docs/research/NOTE_2026-08-01.md status)" = "open" ]
  [ "$(row docs/research/NOTE_2026-08-01.md date)" = "2026-08-01" ]
  [ "$(row docs/research/prog-2026-09-30/ topic)" = "Program report" ]
  [ "$(row docs/research/prog-2026-09-30/ status)" = "research complete" ]
  [ "$(row docs/research/LEDGER.md topic)" = "LEDGER" ]
  [ "$(row docs/research/LEDGER.md date)" = "2026-07-04" ]
  [ "$(row docs/research/LEDGER.md status)" = "unknown" ]
}

@test "--check fails when research was added after the index was written" {
  "$X" --root "$R"
  run "$X" --root "$R" --check
  [ "$status" -eq 0 ]
  printf '# New finding\n' > "$R/docs/research/NEW_2026-10-01.md"
  run "$X" --root "$R" --check
  [ "$status" -eq 1 ]
  [[ "$output" == *"1 entry(ies) missing"* ]]
}

@test "--check fails when there is no index at all" {
  run "$X" --root "$R" --check
  [ "$status" -eq 1 ]
}
