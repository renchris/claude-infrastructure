#!/usr/bin/env bats
# cc-reconcile — self-heal the cross-session registry: backfill a cc-registry row for any LIVE
# interactive claude pane that missed SessionStart, deriving paneUUID+account from proc env and
# sessionId+cwd+startedAt from CC's own ~/.claude*/sessions/<pid>.json. Additive-only, idempotent,
# P8-safe (never a null-sid row), schema-identical to hooks/session-register.sh.
#
# Fully hermetic: CC_REGISTRY_DIR (temp out), CC_RECONCILE_SESSIONS_DIRS (temp <pid>.json fixtures),
# and a stub CC_RECONCILE_PS_BIN that answers the two arg forms the tool uses:
#   ps -wwo pid=,command=        → $D/pslist  (canned "pid  argv" lines)
#   ps eww -p <pid> -o command=  → $D/psenv/<pid>  (canned env blob for that pid)

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CCR="$REPO/bin/cc-reconcile"
  D="$BATS_TEST_TMPDIR"
  export CC_REGISTRY_DIR="$D/reg";        mkdir -p "$CC_REGISTRY_DIR"
  export CC_RECONCILE_SESSIONS_DIRS="$D/sessions"; mkdir -p "$D/sessions"
  export CC_RECONCILE_LOG="$D/reconcile.log"
  export CC_RECONCILE_NOW_MS=1700000000000
  mkdir -p "$D/bin" "$D/psenv"
  : > "$D/pslist"

  cat > "$D/bin/ps" <<SH
#!/bin/bash
if [ "\$1" = "-wwo" ]; then
  cat "$D/pslist"
elif [ "\$1" = "eww" ]; then
  cat "$D/psenv/\$3" 2>/dev/null || true
fi
exit 0
SH
  chmod +x "$D/bin/ps"
  export CC_RECONCILE_PS_BIN="$D/bin/ps"
}

# add a live claude proc to the ps list + its env blob + (optionally) a CC sessions/<pid>.json.
# args: pid paneUUID configdir sid cwd [startedAt] [kind]
add_pane() {
  local pid="$1" pane="$2" ccd="$3" sid="$4" cwd="$5" started="${6:-1699000000000}" kind="${7:-interactive}"
  printf '%s /Users/x/.claude-183/node_modules/.bin/claude --permission-mode auto --model claude-opus-4-8 --effort max\n' "$pid" >> "$D/pslist"
  printf 'claude --permission-mode auto ITERM_SESSION_ID=w1t0p0:%s CLAUDE_CONFIG_DIR=%s TERM_PROGRAM=iTerm.app\n' "$pane" "$ccd" > "$D/psenv/$pid"
  if [ "$sid" != "__NOFILE__" ]; then
    local sidjson="\"$sid\""; [ "$sid" = "__NULL__" ] && sidjson=null
    printf '{"pid":%s,"sessionId":%s,"cwd":"%s","startedAt":%s,"kind":"%s","status":"idle"}\n' \
      "$pid" "$sidjson" "$cwd" "$started" "$kind" > "$D/sessions/$pid.json"
  fi
}
# a pane whose env carries NO ITERM_SESSION_ID (unaddressable).
add_pane_no_iterm() {
  local pid="$1"
  printf '%s /Users/x/.claude-183/node_modules/.bin/claude --permission-mode auto\n' "$pid" >> "$D/pslist"
  printf 'claude --permission-mode auto CLAUDE_CONFIG_DIR=/Users/x/.claude TERM_PROGRAM=Apple_Terminal\n' > "$D/psenv/$pid"
  printf '{"pid":%s,"sessionId":"s","cwd":"/tmp/x","startedAt":1,"kind":"interactive"}\n' "$pid" > "$D/sessions/$pid.json"
}
rows() { ls "$CC_REGISTRY_DIR"/*.json 2>/dev/null | wc -l | tr -d ' '; }

@test "backfills a live pane that has no registry row" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude-next sid-abc /tmp/wt-pool-9 1699111111000
  run "$CCR"
  [ "$status" -eq 0 ]
  local f="$CC_REGISTRY_DIR/AAAA1111-2222-3333-4444-555566667777.json"
  [ -f "$f" ]
  [ "$(jq -r '.paneUUID' "$f")" = "AAAA1111-2222-3333-4444-555566667777" ]
  [ "$(jq -r '.session_id' "$f")" = "sid-abc" ]
  [ "$(jq -r '.cwd' "$f")" = "/tmp/wt-pool-9" ]
  [ "$(jq -r '.pid' "$f")" = "1234" ]
  [ "$(jq -r '.startedAt' "$f")" = "1699111111000" ]   # CC's real start, not NOW
}

@test "name = basename(cwd)-<short-uuid> and account = config-dir basename sans dot (session-register parity)" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude-next sid-abc /tmp/wt-pool-9
  run "$CCR"
  local f="$CC_REGISTRY_DIR/AAAA1111-2222-3333-4444-555566667777.json"
  [ "$(jq -r '.name' "$f")" = "wt-pool-9-AAAA1111" ]
  [ "$(jq -r '.account' "$f")" = "claude-next" ]
}

@test "written row has EXACTLY session-register.sh's key set" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude sid-abc /tmp/wt
  run "$CCR"
  local f="$CC_REGISTRY_DIR/AAAA1111-2222-3333-4444-555566667777.json"
  run jq -S 'keys' "$f"
  [ "$output" = '[
  "account",
  "cwd",
  "name",
  "paneUUID",
  "pid",
  "session_id",
  "startedAt"
]' ]
}

@test "idempotent: an existing row is left untouched (never overwritten)" {
  local f="$CC_REGISTRY_DIR/AAAA1111-2222-3333-4444-555566667777.json"
  printf '{"paneUUID":"AAAA1111-2222-3333-4444-555566667777","name":"orig","cwd":"/orig","account":"next","pid":1234,"startedAt":1,"session_id":"orig-sid","sentinel":true}' > "$f"
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude-next sid-NEW /tmp/wt
  run "$CCR"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.name' "$f")" = "orig" ]              # not clobbered
  [ "$(jq -r '.sentinel' "$f")" = "true" ]
  echo "$output" | grep -q '1 present'
}

@test "P8: a session with a NULL sessionId is skipped (never a false spawn-death row)" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude __NULL__ /tmp/wt
  run "$CCR"
  [ "$status" -eq 0 ]
  [ "$(rows)" = "0" ]
  echo "$output" | grep -q 'no-sid 1'
}

@test "a live pane with no CC sessions/<pid>.json is skipped (no-sid), not written" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude __NOFILE__ /tmp/wt
  run "$CCR"
  [ "$status" -eq 0 ]
  [ "$(rows)" = "0" ]
  echo "$output" | grep -q 'no-sid 1'
}

@test "a pane with no ITERM_SESSION_ID is skipped (no-pane), not written" {
  add_pane_no_iterm 1234
  run "$CCR"
  [ "$status" -eq 0 ]
  [ "$(rows)" = "0" ]
  echo "$output" | grep -q 'no-pane 1'
}

@test "claude --version / --print invocations are not counted as live sessions" {
  printf '5555 /Users/x/.claude-183/node_modules/.bin/claude --version\n' >> "$D/pslist"
  printf '6666 /Users/x/.claude-183/node_modules/.bin/claude -p hello\n' >> "$D/pslist"
  run "$CCR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '0 live'
  [ "$(rows)" = "0" ]
}

@test "--dry-run writes NOTHING but reports what it would backfill" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude-next sid-abc /tmp/wt-pool-9
  run "$CCR" --dry-run
  [ "$status" -eq 0 ]
  [ "$(rows)" = "0" ]                               # nothing written
  echo "$output" | grep -q 'would backfill 1'
  echo "$output" | grep -q 'wt-pool-9-AAAA1111'
}

@test "startedAt falls back to NOW_MS when the sessions file omits it" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude sid-abc /tmp/wt
  # rewrite the CC sessions file WITHOUT a startedAt field to exercise the fallback
  printf '{"pid":1234,"sessionId":"sid-abc","cwd":"/tmp/wt","kind":"interactive","status":"idle"}' > "$D/sessions/1234.json"
  run "$CCR"
  local f="$CC_REGISTRY_DIR/AAAA1111-2222-3333-4444-555566667777.json"
  [ "$(jq -r '.startedAt' "$f")" = "1700000000000" ]
}

@test "--json emits a machine-readable summary" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude sid-abc /tmp/wt
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.backfilled')" = "1" ]
  [ "$(echo "$output" | jq -r '.live')" = "1" ]
  [ "$(echo "$output" | jq -r '.mode')" = "backfill" ]
}

@test "two live panes, one already registered → backfills only the missing one" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude sid-a /tmp/w1
  add_pane 2345 BBBB2222-2222-3333-4444-555566667777 /Users/x/.claude sid-b /tmp/w2
  printf '{"paneUUID":"AAAA1111-2222-3333-4444-555566667777","name":"x","cwd":"/tmp/w1","account":"claude","pid":1234,"startedAt":1,"session_id":"sid-a"}' > "$CC_REGISTRY_DIR/AAAA1111-2222-3333-4444-555566667777.json"
  run "$CCR"
  [ "$status" -eq 0 ]
  [ "$(rows)" = "2" ]
  echo "$output" | grep -q 'backfilled 1'
  echo "$output" | grep -q '1 present'
  [ -f "$CC_REGISTRY_DIR/BBBB2222-2222-3333-4444-555566667777.json" ]
}

@test "unknown option → exit 2" {
  run "$CCR" --bogus
  [ "$status" -eq 2 ]
}
