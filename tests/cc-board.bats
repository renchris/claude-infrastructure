#!/usr/bin/env bats
# cc-board — the operator all-sessions glance view, pinned on ONE property: it must never print a
# DEATH VERDICT it cannot support.
#
# WHY THIS FILE EXISTS (CLOUD_OBSERVABILITY.md §5.2, liar #2). Both of cc-board's death words are
# `kill -0` on a LOCAL pid:
#   · the telemetry loop's `DEAD`            (a row whose exported pid fails kill -0)
#   · the registry join's `DIED-UNRENDERED`  (registered, never rendered, pid fails kill -0)
# A session running in an Anthropic-managed VM has no pid on this box, so both fail EVERY TIME by
# construction. The board was therefore structurally guaranteed to report a healthy cloud session
# as dead — not a gap, a fabricated verdict.
#
# The registry arm is the subtler one and it is pinned separately below: an off-box row has no
# local pid AT ALL, so it never reached the dead-pid branch — it fell to `NO-RENDER?`, whose own
# gloss ("up, but never rendered: hung/GO-deaf") is a claim about a LOCAL process and is just as
# unsupportable. A fix that only guarded the `DEAD` word would have left it.
#
# Assertions are `[ ]` / `|| false`; `[[ ]]` and `(( ))` are errexit-EXEMPT in bats.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  B="$REPO/bin/cc-board"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # Hermetic spines: our own telemetry dir and registry dir, never the operator's live fleet.
  export CC_TELEMETRY_DIR="$BATS_TEST_TMPDIR/telemetry"; mkdir -p "$CC_TELEMETRY_DIR"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/registry";   mkdir -p "$CC_REGISTRY_DIR"
  export CC_BOARD_GRACE_S=0          # no startup grace — every seeded row must render
  # A PATH with no claude-accounts, so the quota join is absent rather than reading live accounts.
  D="$BATS_TEST_TMPDIR/bin"; mkdir -p "$D"
  export PATH="$D:/usr/bin:/bin:/usr/sbin:/sbin"
  # jq is required by the subject; expose the real one without exposing the rest of the toolchain.
  JQ="$(command -v jq 2>/dev/null || true)"; [ -n "$JQ" ] || JQ=/opt/homebrew/bin/jq
  ln -sf "$JQ" "$D/jq"
  # Off-box lookup OFF by default: every pre-existing verdict is measured against the subject as it
  # was. Set-to-EMPTY is honored verbatim by cc-board; the off-box tests re-enable it.
  export CC_CLOUD_BIN=""
}

use_cc_cloud() {
  export CC_CLOUD_BIN="$REPO/bin/cc-cloud"
  export CC_CLOUD_STATE="$BATS_TEST_TMPDIR/cloud"
  mkdir -p "$CC_CLOUD_STATE"
}
declare_cloud() { printf 'id=%s\nbranch=b\n' "$1" > "$CC_CLOUD_STATE/$1.decl"; }

# A telemetry row. $1=session-id $2=pid ('' for none). Timestamp is NOW, so the row is fresh and
# only the pid arm can move the state.
telemetry_row() {
  printf '{"session_id":"%s","ts":%s,"used_pct":10,"config_dir":"/x/.claude","cwd":"/tmp","pid":"%s"}\n' \
    "$1" "$(date +%s)" "$2" > "$CC_TELEMETRY_DIR/$1.json"
}

# A registry row with NO telemetry counterpart — the join arm's input. $1=session-id $2=pid ('' none).
registry_row() {
  printf '{"session_id":"%s","name":"n-%s","pid":"%s","startedAt":1,"cwd":"/tmp/wt"}\n' \
    "$1" "$1" "$2" > "$CC_REGISTRY_DIR/$1.json"
}

# A pid that is guaranteed not to be running. 99999 is within the pid_max range on Darwin but is
# not in use here; asserted rather than assumed, so a collision fails loudly instead of silently
# turning a DEAD test green for the wrong reason.
dead_pid() {
  local p=99999
  while kill -0 "$p" 2>/dev/null; do p=$((p - 1)); done
  printf '%s' "$p"
}

@test "the subject's own preconditions hold (control: a live pid does NOT read DEAD)" {
  telemetry_row session_LOCALLIVE "$$"
  run "$B"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'session_' || false
  ! echo "$output" | grep -q 'DEAD' || false
  true
}

@test "DEAD is still reachable for a genuine local death (control for the abstain)" {
  telemetry_row session_LOCALDEAD "$(dead_pid)"
  run "$B"
  echo "$output" | grep -q 'DEAD' || false
}

@test "OFFBOX replaces DEAD when the telemetry row's session is DECLARED off-box" {
  use_cc_cloud
  declare_cloud session_01CLOUD
  telemetry_row session_01CLOUD "$(dead_pid)"
  run "$B"
  echo "$output" | grep -q 'OFFBOX' || false
  ! echo "$output" | grep -q 'DEAD' || false
  true
}

@test "DIED-UNRENDERED is still reachable for a genuine local death (control)" {
  registry_row session_REGDEAD "$(dead_pid)"
  run "$B"
  echo "$output" | grep -q 'DIED-UNRENDERED' || false
}

@test "OFFBOX replaces DIED-UNRENDERED in the registry join" {
  use_cc_cloud
  declare_cloud session_01REGCLOUD
  registry_row session_01REGCLOUD "$(dead_pid)"
  run "$B"
  echo "$output" | grep -q 'OFFBOX' || false
  ! echo "$output" | grep -q 'DIED-UNRENDERED' || false
  true
}

# THE ARM A NARROWER FIX WOULD HAVE MISSED. An off-box row has no local pid, so it never enters the
# dead-pid branch — it lands on NO-RENDER?, which asserts just as much about a local process.
@test "OFFBOX replaces NO-RENDER? too — a pid-LESS off-box row is not a hung local session" {
  use_cc_cloud
  declare_cloud session_01NOPID
  registry_row session_01NOPID ""
  run "$B"
  echo "$output" | grep -q 'OFFBOX' || false
  ! echo "$output" | grep -q 'NO-RENDER' || false
  true
}

# THE CONTROL ON THE ABSTAIN ITSELF. Without it, an implementation that renders OFFBOX for every
# row would pass every test above. An abstain that cannot convict is as useless as a verdict that
# cannot abstain.
@test "an UNDECLARED id is NOT off-box — the abstain is not blanket" {
  use_cc_cloud
  telemetry_row session_01UNDECLARED "$(dead_pid)"
  run "$B"
  echo "$output" | grep -q 'DEAD' || false
  ! echo "$output" | grep -q 'OFFBOX' || false
  true
}

@test "a RETIRED declaration stops abstaining — retire is terminal" {
  use_cc_cloud
  declare_cloud session_01RETIRED
  printf 'retired_at=1\n' > "$CC_CLOUD_STATE/session_01RETIRED.retired"
  telemetry_row session_01RETIRED "$(dead_pid)"
  run "$B"
  echo "$output" | grep -q 'DEAD' || false
}

@test "no cc-cloud on the box degrades to the old verdicts, never to a crash" {
  export CC_CLOUD_BIN=""
  telemetry_row session_NOTOOL "$(dead_pid)"
  run "$B"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'DEAD' || false
}
