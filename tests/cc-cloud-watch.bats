#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
#   Structurally false under bats, not suppressed noise: every @test body IS its own subshell, so an
#   `export` inside one is meant to be test-local (SC2030/SC2031), and setup()'s helpers are invoked
#   from those test subshells rather than from file scope (SC2329).
#
# cc-cloud-watch — the observable set for off-box (cloud) sessions. One test per arm of the verdict
# function (fresh · waiting · dark · nofetch · retired), plus the two refusals that carry the whole
# point of the item: preflight refuses an UNPUSHED branch, and `record` refuses a missing --id.
#
# HERMETIC BY CONSTRUCTION: setup() fixtures $HOME and CC_CLOUD_DIR, and every git operation runs
# against a bare remote created inside BATS_TEST_TMPDIR. Nothing touches the operator's real store.
# This is not theoretical — the first draft of the subject's own --selftest exported CC_CLOUD_DIR
# AFTER the script had already resolved it, and wrote two cse_test*.json records into the real
# ~/.claude/cloud-sessions. The repo's hermeticity ratchet (scripts/test-hermeticity-lint.sh) runs
# in the land gate and fail-fasts on an unfixtured HOME.
#
# POSITIVE CONTROLS: the two "refuses" tests are paired with the matching ACCEPT case off the same
# fixture (a pushed branch passes preflight; a complete `record` succeeds). A refusal that refuses
# everything is not a gate, and would pass a suite that only ever asserted the refusal.
#
# WHAT THIS SUITE DELIBERATELY DOES NOT TEST: that scripts/lead-supervisor.sh's reobserve_effects()
# returns `dark` for an absent cwd. That is the DEFECT this file exists because of, measured
# 2026-08-07 — and pinning it in a test would convert a bug into a contract, so that fixing the
# supervisor to return `unknown` would turn this suite red. The measurement belongs in the design
# doc and in the subject's header, never in an assertion.
#
# DEAD-ASSERTION DISCIPLINE: bats runs each body under `set -eET`, and bash exempts `[[ ]]`, `(( ))`
# and `! cmd` from errexit — a non-final occurrence of those is a DEAD assertion that always passes
# (scripts/bats-assert-liveness.py). This suite uses POSIX `[ ]` and appends `|| false` wherever a
# non-final `!` / `A && B` is used.
#
# RED-PROOF: every test fails against a tree without bin/cc-cloud-watch:
#   t=$(mktemp -d); git archive HEAD | tar -x -C "$t"
#   CC_CLOUD_WATCH_SUBJECT_ROOT="$t" bats tests/cc-cloud-watch.bats

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ROOT="${CC_CLOUD_WATCH_SUBJECT_ROOT:-$REPO}"
  CCW="$ROOT/bin/cc-cloud-watch"

  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"
  export CC_CLOUD_DIR="$D/store"; mkdir -p "$CC_CLOUD_DIR"
  export CC_CLOUD_PROBE_TIMEOUT_S=15

  BARE="$D/remote.git"; WORK="$D/work"
  git init -q --bare "$BARE"
  git init -q "$WORK"
  git -C "$WORK" config user.email t@t
  git -C "$WORK" config user.name t
  git -C "$WORK" remote add origin "$BARE"
  : > "$WORK/f"; git -C "$WORK" add f; git -C "$WORK" commit -qm one
  git -C "$WORK" branch -M main
  git -C "$WORK" push -q -u origin main
}

rec() { jq -r "$1" "$CC_CLOUD_DIR/$2.json"; }

@test "subject exists and is executable" {
  [ -x "$CCW" ]
}

@test "selftest is green (the subject's own hermetic proof)" {
  run bash "$CCW" --selftest
  [ "$status" -eq 0 ]
}

# ── preflight: the executable form of "design the observable set BEFORE firing" ──────────────────

@test "preflight PASSES for a branch that is on the remote (positive control)" {
  run bash "$CCW" preflight --repo "$WORK" --branch main
  [ "$status" -eq 0 ]
}

@test "preflight REFUSES a branch that exists only locally — a cloud VM clones from the remote" {
  git -C "$WORK" branch local-only
  run bash "$CCW" preflight --repo "$WORK" --branch local-only
  [ "$status" -eq 1 ]
  printf '%s' "$output" | grep -q "is NOT on" || false
}

@test "preflight names the push command for the branch it refused" {
  git -C "$WORK" branch local-only
  run bash "$CCW" preflight --repo "$WORK" --branch local-only
  printf '%s' "$output" | grep -q "git push -u origin local-only" || false
}

@test "preflight REFUSES a repo with no remote — there is no channel to observe" {
  bare2="$D/norem"; git init -q "$bare2"
  run bash "$CCW" preflight --repo "$bare2" --branch main
  [ "$status" -eq 1 ]
}

# ── record: O1/O2/O3, capturable only at fire time ───────────────────────────────────────────────

@test "record REFUSES without --id (O1 is unrecoverable after the fire)" {
  run bash "$CCW" record --branch main --repo "$WORK"
  [ "$status" -ne 0 ]
}

@test "record REFUSES without --branch (O2: nothing tells the observer which ref to poll)" {
  run bash "$CCW" record --id cse_x --repo "$WORK"
  [ "$status" -ne 0 ]
}

@test "record SUCCEEDS with id+branch and seeds baseSha from the live remote (positive control)" {
  run bash "$CCW" record --id cse_a --branch main --repo "$WORK" --item deadbeef
  [ "$status" -eq 0 ]
  [ "$(rec .baseSha cse_a)" = "$(git -C "$WORK" rev-parse main)" ]
  [ "$(rec .item cse_a)" = "deadbeef" ]
}

# ── the verdict function: one test per arm ───────────────────────────────────────────────────────

@test "no advance inside the silence window ⇒ waiting, NOT dark" {
  bash "$CCW" record --id cse_b --branch main --repo "$WORK" >/dev/null
  run bash "$CCW" observe --json
  printf '%s' "$output" | jq -e 'select(.id=="cse_b") | .verdict=="waiting"' >/dev/null || false
}

@test "a push advances the remote sha ⇒ fresh" {
  bash "$CCW" record --id cse_c --branch main --repo "$WORK" >/dev/null
  : > "$WORK/g"; git -C "$WORK" add g; git -C "$WORK" commit -qm two
  git -C "$WORK" push -q origin main
  run bash "$CCW" observe --json
  printf '%s' "$output" | jq -e 'select(.id=="cse_c") | .verdict=="fresh"' >/dev/null || false
}

@test "the advance is PERSISTED — an immediate re-probe is waiting, not a second fresh" {
  bash "$CCW" record --id cse_d --branch main --repo "$WORK" >/dev/null
  : > "$WORK/g"; git -C "$WORK" add g; git -C "$WORK" commit -qm two
  git -C "$WORK" push -q origin main
  bash "$CCW" observe --json >/dev/null
  run bash "$CCW" observe --json
  printf '%s' "$output" | jq -e 'select(.id=="cse_d") | .verdict=="waiting"' >/dev/null || false
}

@test "silence past the declared window ⇒ dark (go look at the web UI)" {
  bash "$CCW" record --id cse_e --branch main --repo "$WORK" >/dev/null
  t="$CC_CLOUD_DIR/cse_e.json"
  jq -c '.silenceMaxS=0 | .lastAdvanceAt=(.lastAdvanceAt-10)' "$t" > "$t.x" && mv "$t.x" "$t"
  run bash "$CCW" observe --json
  printf '%s' "$output" | jq -e 'select(.id=="cse_e") | .verdict=="dark"' >/dev/null || false
}

@test "THE INVARIANT: an unreachable remote reads nofetch, never dark" {
  # The record is first driven PAST its silence window, so a naive implementation that ignored the
  # probe failure would answer `dark` here. That is what makes this a real test rather than a
  # tautology: folding "could not look" into "no progress" manufactures the very escalation the
  # third state exists to prevent (scripts/lead-supervisor.sh:427).
  bash "$CCW" record --id cse_f --branch main --repo "$WORK" >/dev/null
  t="$CC_CLOUD_DIR/cse_f.json"
  jq -c '.silenceMaxS=0 | .lastAdvanceAt=(.lastAdvanceAt-10) | .remote="file:///nonexistent-'"$$"'.git"' \
     "$t" > "$t.x" && mv "$t.x" "$t"
  run bash "$CCW" observe --json
  printf '%s' "$output" | jq -e 'select(.id=="cse_f") | .verdict=="nofetch"' >/dev/null || false
}

@test "a branch absent from the remote is waiting inside the first-push grace, dark past it" {
  bash "$CCW" record --id cse_g --branch never-pushed --repo "$WORK" --first-push-s 3600 >/dev/null
  run bash "$CCW" observe --json
  printf '%s' "$output" | jq -e 'select(.id=="cse_g") | .verdict=="waiting"' >/dev/null || false

  t="$CC_CLOUD_DIR/cse_g.json"
  jq -c '.firstPushDeadlineS=0 | .firedAt=(.firedAt-10)' "$t" > "$t.x" && mv "$t.x" "$t"
  run bash "$CCW" observe --json
  printf '%s' "$output" | jq -e 'select(.id=="cse_g") | .verdict=="dark"' >/dev/null || false
}

@test "retire is terminal and stops observation" {
  bash "$CCW" record --id cse_h --branch main --repo "$WORK" >/dev/null
  bash "$CCW" retire cse_h >/dev/null
  run bash "$CCW" observe --json
  printf '%s' "$output" | jq -e 'select(.id=="cse_h") | .verdict=="retired"' >/dev/null || false
}

# ── read-only discipline over the repo ───────────────────────────────────────────────────────────

@test "observe never mutates the repo — no fetch, no ref write, no push" {
  bash "$CCW" record --id cse_i --branch main --repo "$WORK" >/dev/null
  before="$(git -C "$WORK" rev-parse HEAD):$(git -C "$WORK" status --porcelain | wc -l | tr -d ' ')"
  bash "$CCW" observe --json >/dev/null
  after="$(git -C "$WORK" rev-parse HEAD):$(git -C "$WORK" status --porcelain | wc -l | tr -d ' ')"
  [ "$before" = "$after" ]
  # and it must not have created remote-tracking refs (it uses ls-remote, never fetch)
  [ -z "$(git -C "$WORK" for-each-ref --format='%(refname)' refs/remotes/ 2>/dev/null | grep -v 'refs/remotes/origin/main' || true)" ]
}

@test "list renders last-known verdicts WITHOUT probing" {
  bash "$CCW" record --id cse_j --branch main --repo "$WORK" >/dev/null
  bash "$CCW" observe --json >/dev/null
  run bash "$CCW" list --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e 'select(.id=="cse_j") | .detail=="last known; no probe run"' >/dev/null || false
}
