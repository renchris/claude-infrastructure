#!/usr/bin/env bats
# deploy-parity-assert.sh — the ~/bin deployment drift assertion.
#
# Guards the failure that motivated the script: bin/claude-accounts was deployed to ~/bin as a
# COPY, so a repo edit did not reach the running tool. It drifted for two days undetected while
# every consumer ran the old code, and sync.sh (which copies ~/bin BACK into the repo with no
# direction guard) would have clobbered the newer repo file with the stale copy.
#
# FULLY HERMETIC: every case builds a fake repo + fake bindir in BATS_TEST_TMPDIR and drives the
# script via CC_PARITY_REPO / CC_PARITY_BINDIR / CC_PARITY_STRICT / CC_PARITY_COPY. Nothing here
# reads the real ~/bin or the real checkout, so it passes on a fresh clone, a worktree and CI.
# (The live host is asserted by running the script itself, not by this suite.)

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export ASSERT="$REPO_ROOT/scripts/deploy-parity-assert.sh"
  export CC_PARITY_REPO="$BATS_TEST_TMPDIR/repo"
  export CC_PARITY_BINDIR="$BATS_TEST_TMPDIR/bin"
  export CC_PARITY_STRICT="toolA"
  export CC_PARITY_COPY="toolB"
  mkdir -p "$CC_PARITY_REPO/bin" "$CC_PARITY_BINDIR"
  printf 'echo A v2\n' > "$CC_PARITY_REPO/bin/toolA"
  printf 'echo B v1\n' > "$CC_PARITY_REPO/bin/toolB"
  # PATH must resolve the strict tool to our fake bindir, never the operator's real one.
  export PATH="$CC_PARITY_BINDIR:$PATH"
}

@test "strict tool symlinked into the repo ⇒ LINKED, exit 0" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LINKED"* ]]
}

@test "strict tool is a STALE copy ⇒ drift, exit 1 (the 2026-07-19 regression)" {
  printf 'echo A v1\n' > "$CC_PARITY_BINDIR/toolA"     # the old, drifted content
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"STALE"* ]]
  [[ "$output" == *"toolA"* ]]
}

@test "strict tool is a copy that currently MATCHES ⇒ still drift (it will rot again)" {
  cp "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"   # identical today, copy not link
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"UNLINKED"* ]]
}

@test "strict tool not deployed at all ⇒ MISSING, exit 1" {
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"MISSING"* ]]
}

@test "copy-class tool differing ⇒ drift, but the strict tool stays LINKED" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  printf 'echo B v0\n' > "$CC_PARITY_BINDIR/toolB"
  run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"LINKED"* ]]
  [[ "$output" == *"STALE"*  ]]
}

@test "an earlier PATH entry shadowing the strict tool is caught even when ~/bin is correct" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  mkdir -p "$BATS_TEST_TMPDIR/shadow"
  printf 'echo A imposter\n' > "$BATS_TEST_TMPDIR/shadow/toolA"
  chmod +x "$BATS_TEST_TMPDIR/shadow/toolA"
  PATH="$BATS_TEST_TMPDIR/shadow:$PATH" run "$ASSERT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"SHADOWED"* ]]
}

@test "a tool absent from the checkout is skipped, not reported as drift" {
  ln -sfn "$CC_PARITY_REPO/bin/toolA" "$CC_PARITY_BINDIR/toolA"
  cp "$CC_PARITY_REPO/bin/toolB" "$CC_PARITY_BINDIR/toolB"
  CC_PARITY_COPY="toolB toolZZ" run "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" != *"toolZZ"* ]]
}

@test "the real repo passes its own assertion (guards the live host deployment)" {
  run env -u CC_PARITY_REPO -u CC_PARITY_BINDIR -u CC_PARITY_STRICT -u CC_PARITY_COPY "$ASSERT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-accounts"* ]]
}
