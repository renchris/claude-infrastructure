#!/usr/bin/env bats
# ship-land.sh's OUTER-TIMEOUT PREFLIGHT (TrueMemory §3.6 step 2) and its killed-verdict lesson
# pointer. `timeout N … ship-land.sh` convicts healthy lands under lock contention; the killed
# verdict named that after the fact and the pattern still recurred, so a land now refuses BEFORE the
# lock when timeout/gtimeout is in its ancestry. Scratch bare "origin" + clone in BATS_TEST_TMPDIR;
# nothing here reaches a real origin, lock, log or live layer.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO/scripts/ship-land.sh"
  LESSON="$REPO/docs/lessons/never-wrap-ship-in-your-own-timeout.md"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK" 2>/dev/null
  cd "$WORK" || return 1
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m base
  git push -q -u origin main

  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export LAND_LOCK_WAIT=10
  export SHIP_LAND_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export SHIP_LAND_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/nope"
  export CLAUDE_CODE_SESSION_ID="test-sid-outer-timeout"
  export CC_BACKLOG_BIN="$REPO/bin/cc-backlog"
  export POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export POSTLAND_VERIFY=off
  export SHIP_LAND_CONVERGE=off
  export DEPLOY_REPO="$BATS_TEST_TMPDIR/nope-deploy-repo"
  export CC_GATE_MAX_LOAD=0
  # The subject of this suite: an inherited opt-out would pass every refusal case vacuously.
  unset SHIP_ALLOW_OUTER_TIMEOUT SHIP_LAND_T0 SHIP_LAND_LANE SHIP_LAND_GATE_ROUNDS 2>/dev/null || true

  # A fake timeout(1): a COPY of bash named `timeout`, so its ucomm is exactly what the real one's
  # is. It stays the parent (the `; exit` keeps bash from exec'ing the last command away).
  FAKE_TIMEOUT="$BATS_TEST_TMPDIR/bin/timeout"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cp "$(command -v bash)" "$FAKE_TIMEOUT"
}

REFUSAL='verdict=refused reason=outer-timeout'

@test "a land under a timeout ancestor is refused with rc 2 and names an existing lesson" {
  run "$FAKE_TIMEOUT" -c '"$@"; exit $?' _ bash "$SHIPLAND" --trunk main
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "$REFUSAL" || false
  printf '%s\n' "$output" | grep -qF "ancestry=[" || false
  printf '%s\n' "$output" | grep -qF "Override: SHIP_ALLOW_OUTER_TIMEOUT=1" || false
  local f
  f="$(printf '%s\n' "$output" | sed -n 's/.*lesson: \([^ ]*\.md\)\..*/\1/p' | head -1)"
  [ "$f" = "$LESSON" ] || false
  [ -f "$f" ] || false
  # Refused BEFORE the landing lock: nothing was ever acquired under the fixture lock dir.
  [ -z "$(ls -A "$LAND_LOCK_DIR" 2>/dev/null)" ] || false
}

@test "a real timeout(1) ancestor is refused the same way" {
  local t; t="$(command -v timeout 2>/dev/null || command -v gtimeout 2>/dev/null || true)"
  [ -n "$t" ] || skip "no timeout(1)/gtimeout on PATH"
  run "$t" 60 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 2 ]
  printf '%s\n' "$output" | grep -qF "$REFUSAL" || false
}

@test "SHIP_ALLOW_OUTER_TIMEOUT=1 gets past the preflight" {
  run env SHIP_ALLOW_OUTER_TIMEOUT=1 "$FAKE_TIMEOUT" -c '"$@"; exit $?' _ bash "$SHIPLAND" --trunk main
  # Only the preflight is asserted: what the fixture land does next is other suites' subject.
  if printf '%s\n' "$output" | grep -qF "$REFUSAL"; then false; fi
  [ "$status" -ne 2 ] || false
}

@test "--dry-run pushes nothing, so it is not refused" {
  run "$FAKE_TIMEOUT" -c '"$@"; exit $?' _ bash "$SHIPLAND" --dry-run --trunk main
  if printf '%s\n' "$output" | grep -qF "$REFUSAL"; then false; fi
}

@test "a land with NO timeout ancestor is not refused" {
  # Whatever runs THIS suite may itself sit under timeout(1) (ship-land's smoke gate does), so
  # detach first: the double fork reparents the land away from the bats tree, leaving an ancestry
  # of one bash subshell. Bounded poll on the rc file the detached child writes.
  local out="$BATS_TEST_TMPDIR/detached.out" rcf="$BATS_TEST_TMPDIR/detached.rc" n=0
  ( ( bash "$SHIPLAND" --trunk main >"$out" 2>&1; echo $? >"$rcf" ) </dev/null & )
  while [ ! -s "$rcf" ] && [ "$n" -lt 600 ]; do sleep 0.1; n=$(( n + 1 )); done
  [ -s "$rcf" ] || false
  if grep -qF "$REFUSAL" "$out"; then false; fi
  [ "$(cat "$rcf")" -ne 2 ] || false
}

@test "the killed verdict points at the lesson only on its timeout-ancestry branch" {
  # Static pin on the signal handler: the pointer is gated on _sv_own, which only the timeout arm
  # sets and the orphan arm clears.
  local body
  body="$(sed -n '/^_land_sig_verdict() {/,/^}/p' "$SHIPLAND")"
  # shellcheck disable=SC2016  # literal source text, deliberately unexpanded
  printf '%s\n' "$body" | grep -qF '_sv_anc="$(_land_ancestry_ucomms)"' || false
  # shellcheck disable=SC2016  # literal source text, deliberately unexpanded
  printf '%s\n' "$body" | grep -qE '\[ "\$_sv_own" = "1" \] && _land_lesson_line never-wrap-ship-in-your-own-timeout' || false
  [ -f "$LESSON" ] || false
}

@test "the deploy-live core.bare concede carries a lesson pointer that exists" {
  # (The UNGATED pointer is pinned behaviourally in tests/ship-land.bats' shed case.)
  grep -qF 'docs/lessons/cause-refuted-effect-discharged.md' "$REPO/scripts/deploy-live.sh" || false
  [ -f "$REPO/docs/lessons/cause-refuted-effect-discharged.md" ] || false
}
