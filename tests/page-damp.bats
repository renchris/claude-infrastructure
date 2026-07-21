#!/usr/bin/env bats
# Producer send-damping (v3 D7) — hooks/lib/page-damp.sh.
#
# Closes failure S-3: nothing damped the SEND itself, so a producer re-deriving the same conclusion
# every sweep re-sent it every sweep (570 near-duplicate pages into one box over three days). The
# contract that makes this work — and the one thing that silently breaks it — is the FINGERPRINT: it
# must be the page's STATE, never a clock/counter/elapsed value. Tests below pin both directions.
#
# Isolation: CC_PAGE_DAMP_DIR only — never the live ~/.claude tree.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export CC_PAGE_DAMP_DIR="$BATS_TEST_TMPDIR/damp"
  # shellcheck source=../hooks/lib/page-damp.sh
  . "$REPO/hooks/lib/page-damp.sh"
  T="AAAAAAAA-1111-2222-3333-444444444444"
}

@test "first send always goes through (nothing to damp against)" {
  run damp_should_send "$T" "DEAD:coordination-hang"
  [ "$status" -eq 0 ]
}

@test "an IDENTICAL (target,fingerprint) re-send inside the TTL is SUPPRESSED" {
  damp_should_send "$T" "DEAD:coordination-hang"
  run damp_should_send "$T" "DEAD:coordination-hang"
  [ "$status" -eq 1 ]
}

@test "a CHANGED fingerprint passes immediately — state change is signal, not noise" {
  damp_should_send "$T" "STALL?:stale-telemetry"
  run damp_should_send "$T" "DEAD:pid-gone"
  [ "$status" -eq 0 ]
}

@test "damping is PER-TARGET — the same state to a different pane is not suppressed" {
  damp_should_send "$T" "DEAD:pid-gone"
  run damp_should_send "BBBBBBBB-1111-2222-3333-444444444444" "DEAD:pid-gone"
  [ "$status" -eq 0 ]
}

@test "TTL EXPIRY re-asserts an unchanged-but-still-true condition (silence ≠ resolved)" {
  damp_should_send "$T" "DEAD:pid-gone"
  run damp_should_send "$T" "DEAD:pid-gone"; [ "$status" -eq 1 ]      # damped…
  # backdate the marker past the TTL — a real past mtime, not a 0-TTL degenerate threshold
  local mk; mk="$(find "$CC_PAGE_DAMP_DIR" -type f | head -1)"
  printf '%s\n' "$(( $(date +%s) - 4000 ))" > "$mk"
  run damp_should_send "$T" "DEAD:pid-gone"
  [ "$status" -eq 0 ]                                                # …then re-asserts
}

@test "CC_PAGE_DAMP_TTL_S tunes the window" {
  damp_should_send "$T" "S:x"
  local mk; mk="$(find "$CC_PAGE_DAMP_DIR" -type f | head -1)"
  printf '%s\n' "$(( $(date +%s) - 60 ))" > "$mk"
  CC_PAGE_DAMP_TTL_S=3600 run damp_should_send "$T" "S:x"; [ "$status" -eq 1 ]   # 60s < 3600 ⇒ damped
  CC_PAGE_DAMP_TTL_S=30   run damp_should_send "$T" "S:x"; [ "$status" -eq 0 ]   # 60s > 30   ⇒ sends
}

@test "FAIL-OPEN: an empty target or fingerprint SENDS (damping never eats a page)" {
  run damp_should_send "" "some-state";  [ "$status" -eq 0 ]
  run damp_should_send "$T" "";          [ "$status" -eq 0 ]
}

@test "FAIL-OPEN: an unwritable marker dir SENDS rather than suppressing" {
  export CC_PAGE_DAMP_DIR="/proc/nonexistent-cannot-create/damp"
  run damp_should_send "$T" "DEAD:x"
  [ "$status" -eq 0 ]
}

@test "fingerprints with path/shell metacharacters are filename-safe (no escape, no collision)" {
  damp_should_send "$T" "surface:../../etc/passwd:hang"
  run damp_should_send "$T" "surface:../../etc/passwd:hang"
  [ "$status" -eq 1 ]                                    # same key damps → it was stored, not escaped
  [ ! -e "$CC_PAGE_DAMP_DIR/../../etc/passwd" ]
  [ "$(find "$CC_PAGE_DAMP_DIR" -type f | wc -l)" -eq 1 ]
}

@test "THE CONTRACT: a timestamped fingerprint defeats damping — pin why state-only is required" {
  # Not a bug in the helper; a demonstration of the misuse it is documented against. A fingerprint
  # that embeds a clock changes every call, so nothing ever matches and every page re-sends — the
  # exact storm this closes, reappearing while LOOKING correctly wired.
  damp_should_send "$T" "DEAD at 10:00:01"
  run damp_should_send "$T" "DEAD at 10:00:02"
  [ "$status" -eq 0 ]        # undamped — which is why producers must fingerprint STATE, not time
}
