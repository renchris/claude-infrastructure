#!/usr/bin/env bats
# cc-teardown-safety-gate — the standalone work-safety decision module. Its --selftest RED-proves
# G-a/G-b with temp git repos; these bats add CLI-level regression on the exit-code contract
# (0 TEARDOWN / 10 DEFER / 2 REFUSE) and the JSON verdict, per-decision.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  G="$REPO/bin/cc-teardown-safety-gate.sh"
}
mkrepo() { # <dir> — clean shipped repo: origin/main == HEAD, origin/HEAD → origin/main (no network)
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" config user.email t@t; git -C "$1" config user.name t
  echo a > "$1/f"; git -C "$1" add f; git -C "$1" commit -qm c1
  git -C "$1" update-ref refs/remotes/origin/main HEAD
  git -C "$1" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
}

@test "selftest passes and runs all 8 checks (a zero-check suite must not 'pass')" {
  run "$G" --selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 8 ]
}

@test "G-a shipped+clean + done-evidence → TEARDOWN (exit 0)" {
  mkrepo "$BATS_TEST_TMPDIR/clean"
  run "$G" decide --cwd "$BATS_TEST_TMPDIR/clean" --done-evidence "shipped d283997"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "TEARDOWN" ]
}

@test "G-a dirty tree → DEFER (exit 10)" {
  mkrepo "$BATS_TEST_TMPDIR/dirty"; echo x >> "$BATS_TEST_TMPDIR/dirty/f"
  run "$G" decide --cwd "$BATS_TEST_TMPDIR/dirty" --done-evidence "x"
  [ "$status" -eq 10 ]
  [ "$(printf '%s' "$output" | jq -r '.reason_kind')" = "dirty-tree" ]
}

@test "G-a untracked-only litter → TEARDOWN (exit 0) — cc-reaper reaps THROUGH this gate" {
  # Was DEFER: the bare `status --porcelain` counted untracked files, so any co-cwd session in a
  # shared checkout deferred forever and 13+ finished workers stranded awaiting a hand-close. The
  # reaper-side relaxation is INERT without this one — every promoted auto-reap would land here.
  mkrepo "$BATS_TEST_TMPDIR/untracked"; echo litter > "$BATS_TEST_TMPDIR/untracked/stray-scratch.md"
  run "$G" decide --cwd "$BATS_TEST_TMPDIR/untracked" --done-evidence "x"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "TEARDOWN" ]
}

@test "G-a committed-not-pushed → DEFER (exit 10)" {
  mkrepo "$BATS_TEST_TMPDIR/ahead"; echo x >> "$BATS_TEST_TMPDIR/ahead/f"; git -C "$BATS_TEST_TMPDIR/ahead" commit -aqm c2
  run "$G" decide --cwd "$BATS_TEST_TMPDIR/ahead" --done-evidence "x"
  [ "$status" -eq 10 ]
  [ "$(printf '%s' "$output" | jq -r '.reason_kind')" = "unpushed" ]
}

@test "G-b missing done-evidence → REFUSE (exit 2) — done never inferred" {
  mkrepo "$BATS_TEST_TMPDIR/c2"
  run "$G" decide --cwd "$BATS_TEST_TMPDIR/c2"
  [ "$status" -eq 2 ]
  [ "$(printf '%s' "$output" | jq -r '.decision')" = "REFUSE" ]
}

@test "bad input (no --cwd) → exit 2" {
  run "$G" decide --done-evidence "x"
  [ "$status" -eq 2 ]
}
