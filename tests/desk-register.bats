#!/usr/bin/env bats
# bin/desk-register — the standalone desk-role registration primitive. handoff-fire writes
# cc-roles/<role> on an `--as-role` fire; this is the same claim for a HAND-started desk
# (`claude-desk`, `/desk`) that handoff-fire never touched.
#
# What these prove: the pane actually written (UUID parsed out of the iTerm2 "wNtNpN:UUID" form),
# idempotency, atomicity (no half-written file, no tmp litter), and — the load-bearing one — that a
# malformed $ITERM_SESSION_ID FAILS LOUD instead of writing a garbage role file. A garbage role file
# silently breaks ping routing, the reaper's page target and cc-classify's desk never-reap, so
# "wrote something" is a WORSE outcome than "refused".

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DR="$REPO/bin/desk-register"
  export CC_ROLES_DIR="$BATS_TEST_TMPDIR/roles"
  PANE="8B90BC66-9853-4F63-9C1C-39B161174221"
  export ITERM_SESSION_ID="w2t0p3:$PANE"
  unset SESSION_ID
}
role_file() { cat "$CC_ROLES_DIR/${1:-desk}" 2>/dev/null; }

@test "fresh: parses the pane UUID out of \$ITERM_SESSION_ID and writes it" {
  run "$DR"
  [ "$status" -eq 0 ]
  [[ "$output" == "registered desk → $PANE" ]]
  [ "$(role_file)" = "$PANE" ]
}

@test "idempotent: re-registering the SAME pane is a no-op, not a rewrite" {
  run "$DR"; [ "$status" -eq 0 ]
  before="$(stat -f %m "$CC_ROLES_DIR/desk")"
  run "$DR"
  [ "$status" -eq 0 ]
  [[ "$output" == already\ desk\ →\ * ]]
  [ "$(stat -f %m "$CC_ROLES_DIR/desk")" = "$before" ]   # untouched, not rewritten
  [ "$(role_file)" = "$PANE" ]
}

@test "reassign: a DIFFERENT pane takes the role and the move is reported (never silent)" {
  printf 'OLD-PANE-UUID\n' > "$CC_ROLES_DIR/desk" 2>/dev/null || { mkdir -p "$CC_ROLES_DIR"; printf 'OLD-PANE-UUID\n' > "$CC_ROLES_DIR/desk"; }
  run "$DR"
  [ "$status" -eq 0 ]
  [[ "$output" == "reassigned desk: OLD-PANE-UUID → $PANE" ]]
  [ "$(role_file)" = "$PANE" ]
}

@test "malformed \$ITERM_SESSION_ID (no colon) → FAILS LOUD, writes NOTHING" {
  export ITERM_SESSION_ID="garbage-no-colon"
  run "$DR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not yield a pane UUID"* ]]
  [ ! -f "$CC_ROLES_DIR/desk" ]        # the whole point: no garbage role file
}

@test "no \$ITERM_SESSION_ID and no --pane → FAILS LOUD, writes NOTHING" {
  unset ITERM_SESSION_ID
  run "$DR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"cannot tell which pane"* ]]
  [ ! -f "$CC_ROLES_DIR/desk" ]
}

@test "--force accepts a non-UUID pane (documented escape hatch)" {
  export ITERM_SESSION_ID="w0t0p0:some-pane-name"
  run "$DR" --force
  [ "$status" -eq 0 ]
  [ "$(role_file)" = "some-pane-name" ]
}

@test "--pane is taken VERBATIM (role files legitimately hold a uuid, sid or name)" {
  run "$DR" --pane "rSID"
  [ "$status" -eq 0 ]
  [ "$(role_file)" = "rSID" ]
}

@test "--role targets a non-desk role without disturbing desk" {
  run "$DR"; [ "$status" -eq 0 ]
  run "$DR" --role operator --pane "OP-1"
  [ "$status" -eq 0 ]
  [ "$(role_file operator)" = "OP-1" ]
  [ "$(role_file desk)" = "$PANE" ]     # untouched
}

@test "--print reads the holder without writing; exit 1 when unregistered" {
  run "$DR" --print
  [ "$status" -eq 1 ]
  [ ! -f "$CC_ROLES_DIR/desk" ]         # a read must never create the file
  run "$DR"; [ "$status" -eq 0 ]
  run "$DR" --print
  [ "$status" -eq 0 ]
  [ "$output" = "$PANE" ]
}

@test "--quiet is silent on success but still writes" {
  run "$DR" --quiet
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(role_file)" = "$PANE" ]
}

@test "unknown argument → exit 2 (fail-loud, never a silent no-op)" {
  run "$DR" --nope
  [ "$status" -eq 2 ]
  [ ! -f "$CC_ROLES_DIR/desk" ]
}

@test "atomic: no tmp litter left in the roles dir" {
  run "$DR"; [ "$status" -eq 0 ]
  run "$DR" --pane "SECOND"; [ "$status" -eq 0 ]
  # only the role file itself — a reader must never see (or trip over) a partial .desk.$$ file
  [ "$(find "$CC_ROLES_DIR" -name '.*' -type f | wc -l | tr -d ' ')" = "0" ]
}

@test "\$SESSION_ID outranks \$ITERM_SESSION_ID (explicit beats derived)" {
  export SESSION_ID="EXPLICIT-SID"
  run "$DR"
  [ "$status" -eq 0 ]
  [ "$(role_file)" = "EXPLICIT-SID" ]
}
