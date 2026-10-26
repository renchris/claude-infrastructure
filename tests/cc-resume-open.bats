#!/usr/bin/env bats
# cc-resume-open — reopen one session by id in a new kitty window, retrying through capacity
# refusals. Hermetic: fixture stores via CC_RESUME_STORES, a stub engine, a stub kitten.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  OPEN="$REPO/bin/cc-resume-open"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Named like the real store so cc-resume-resolve maps it to an account (next3).
  S="$BATS_TEST_TMPDIR/.claude-tertiary"
  export CC_RESUME_STORES="$S"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_RESUME_OPEN_GAP_S=0
  WT="$BATS_TEST_TMPDIR/wt-x"; mkdir -p "$WT"
  SID=11111111-aaaa-4bbb-8ccc-111111111111
  local hash; hash="$(printf '%s' "$WT" | sed 's/[^a-zA-Z0-9]/-/g')"
  mkdir -p "$S/projects/$hash"
  printf '{"type":"user","cwd":"%s","sessionId":"%s","gitBranch":"feat-x"}\n' "$WT" "$SID" \
    > "$S/projects/$hash/$SID.jsonl"
}

load helpers/cc-stub   # stubs the kernel never execs as #! (kalloc leak)

# stub_engine <rc...> — an engine that exits with the next code in the list on each call.
stub_engine() {
  local T="$BATS_TEST_TMPDIR"
  printf '%s\n' "$@" > "$T/codes"
  cc_stub "$T/bin" engine "#!/bin/bash
echo \"\$*\" >> '$T/calls'
rc=\$(head -n 1 '$T/codes'); tail -n +2 '$T/codes' > '$T/codes.n'; mv '$T/codes.n' '$T/codes'
exit \"\$rc\""
  export CC_RESUME_OPEN_ENGINE="$T/bin/engine"
}

@test "dry run resolves account, recorded cwd and the transcript's branch from an id prefix" {
  run "$OPEN" "${SID:0:8}" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"sid=$SID account=next3 cwd=$WT branch=feat-x"* ]] || return 1
  [[ "$output" == *"--in-pane next3 $WT $SID feat-x"* ]] || return 1
}

@test "an unknown id is refused before any window opens" {
  export CC_KITTEN_BIN="$BATS_TEST_TMPDIR/no-kitten"
  run "$OPEN" 99999999-0000-4000-8000-000000000000
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=failed reason=unresolvable"* ]] || return 1
}

@test "a session already live in the registry is not opened a second time" {
  printf '{"session_id": "%s", "pid": %s}\n' "$SID" "$$" > "$CC_REGISTRY_DIR/7.json"
  run "$OPEN" "$SID" --dry-run
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=live"* ]] || return 1
}

@test "in-pane: capacity refusals (rc 9) are re-asked until admitted" {
  stub_engine 9 9 9 0
  CC_RESUME_OPEN_NO_SHELL=1 run "$OPEN" --in-pane next3 "$WT" "$SID" feat-x
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/calls")" -eq 4 ]
  [[ "$(head -n 1 "$BATS_TEST_TMPDIR/calls")" == "next3 $WT $SID feat-x" ]] || return 1
}

@test "in-pane: a non-capacity refusal is final, not retried" {
  stub_engine 5 0
  CC_RESUME_OPEN_NO_SHELL=1 run "$OPEN" --in-pane next3 "$WT" "$SID"
  [ "$status" -eq 5 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/calls")" -eq 1 ]
}

@test "in-pane: retries stop at CC_RESUME_OPEN_TRIES" {
  stub_engine 9 9 9 9 9 9
  CC_RESUME_OPEN_TRIES=3 CC_RESUME_OPEN_NO_SHELL=1 run "$OPEN" --in-pane next3 "$WT" "$SID"
  [ "$status" -eq 9 ]
  [ "$(wc -l < "$BATS_TEST_TMPDIR/calls")" -eq 3 ]
}
