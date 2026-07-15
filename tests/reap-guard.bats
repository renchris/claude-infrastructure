#!/usr/bin/env bats
# reaper-safety — reap-guard: the standalone REAP|DEFER decision module. The tool's --selftest RED-proves
# R-a/b/c with real git fixtures; these bats add CLI-level regression on the exit-code contract
# (0=REAP, 10=DEFER) and the outcome-record.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  G="$REPO/scripts/reap-guard.sh"
  export CC_REAP_RECORDS_DIR="$BATS_TEST_TMPDIR/records"
  NOW="$(date +%s)"
}
mkgit() { # <dir> [<committer-epoch>]
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" config user.email t@t; git -C "$1" config user.name t
  echo seed > "$1/a.txt"; git -C "$1" add a.txt
  if [ -n "${2:-}" ]; then GIT_AUTHOR_DATE="@$2" GIT_COMMITTER_DATE="@$2" git -C "$1" commit -qm seed
  else git -C "$1" commit -qm seed; fi
}

@test "selftest passes and runs all 6 checks (a zero-check suite must not 'pass')" {
  run "$G" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 6 ]
}

@test "R-a: a just-born teammate (clean tree, within grace) → DEFER (exit 10), not reaped" {
  mkgit "$BATS_TEST_TMPDIR/young"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/young" --member young --spawn-time "$NOW" --grace-s 300
  [ "$status" -eq 10 ]
  [ "$output" = "DEFER" ]
}

@test "R-b: past grace, clean, products since spawn → REAP (exit 0)" {
  mkgit "$BATS_TEST_TMPDIR/prod"                                    # commit now (newer than spawn below)
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/prod" --member prod --spawn-time "$((NOW-1000))" --grace-s 60
  [ "$status" -eq 0 ]
  [ "$output" = "REAP" ]
}

@test "R-b: past grace, clean, NO products since spawn → DEFER (exit 10) — the just-born ambiguity" {
  mkgit "$BATS_TEST_TMPDIR/np" "$((NOW-5000))"                      # commit predates spawn
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/np" --member np --spawn-time "$((NOW-1000))" --grace-s 60
  [ "$status" -eq 10 ]
  [ "$output" = "DEFER" ]
}

@test "R-c: every decision writes an outcome record with the decision (no silent reap)" {
  mkgit "$BATS_TEST_TMPDIR/prod"
  "$G" decide --worktree "$BATS_TEST_TMPDIR/prod" --member prod --spawn-time "$((NOW-1000))" --grace-s 60 >/dev/null
  rec="$(find "$CC_REAP_RECORDS_DIR" -name 'reap-prod-*.json' | head -1)"
  [ -n "$rec" ]
  [ "$(jq -r '.decision' "$rec")" = "REAP" ]
  [ "$(jq -r '.reason_kind' "$rec")" = "finished" ]
}

@test "preserved: a dirty tree still DEFERs (the module only ADDS safety, removes no existing defer)" {
  mkgit "$BATS_TEST_TMPDIR/dirty"; echo change >> "$BATS_TEST_TMPDIR/dirty/a.txt"
  run "$G" decide --worktree "$BATS_TEST_TMPDIR/dirty" --member dirty --spawn-time "$((NOW-1000))" --grace-s 60
  [ "$status" -eq 10 ]
}
