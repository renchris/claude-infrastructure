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
# a definitely-dead real pid (spawn → kill → reap) — for the recycle-in-place stale-row heal tests.
# The heal decision uses a REAL kill -0 on the row's recorded pid (aligned with cc-sessions), so a
# "present" row needs a live pid ($$) and a "stale" row needs a dead one. Mirrors session-registry.bats.
deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null || true; echo "$p"; }

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

@test "idempotent: an existing LIVE-pid row is left untouched (never overwritten)" {
  local f="$CC_REGISTRY_DIR/AAAA1111-2222-3333-4444-555566667777.json"
  # pid = $$ (this test proc, alive) → kill -0 passes → genuinely present, untouched.
  printf '{"paneUUID":"AAAA1111-2222-3333-4444-555566667777","name":"orig","cwd":"/orig","account":"next","pid":%s,"startedAt":1,"session_id":"orig-sid","sentinel":true}' "$$" > "$f"
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

@test "two live panes, one already registered (live pid) → backfills only the missing one" {
  add_pane 1234 AAAA1111-2222-3333-4444-555566667777 /Users/x/.claude sid-a /tmp/w1
  add_pane 2345 BBBB2222-2222-3333-4444-555566667777 /Users/x/.claude sid-b /tmp/w2
  # AAAA's row carries a LIVE pid ($$) → present (untouched); BBBB has no row → backfilled.
  printf '{"paneUUID":"AAAA1111-2222-3333-4444-555566667777","name":"x","cwd":"/tmp/w1","account":"claude","pid":%s,"startedAt":1,"session_id":"sid-a"}' "$$" > "$CC_REGISTRY_DIR/AAAA1111-2222-3333-4444-555566667777.json"
  run "$CCR"
  [ "$status" -eq 0 ]
  [ "$(rows)" = "2" ]
  echo "$output" | grep -q 'backfilled 1'
  echo "$output" | grep -q '1 present'
  [ -f "$CC_REGISTRY_DIR/BBBB2222-2222-3333-4444-555566667777.json" ]
}

# ── STALE-ROW HEAL (recycle-in-place) — item a60d62a215f1 ──────────────────────────────────────────
# A monitoring desk recycles in place: same pane uuid, new pid + session + cwd (often a new account).
# Its WRITE-ONCE row rots to a dead pid, so cc-sessions sweeps it stale and cc-classify stops enumerating
# the (still-LIVE) pane → the reaper self-check false-pages Δ1. Aligning reconcile's present-test with
# cc-sessions' liveness (kill -0 on the recorded pid) HEALS the row instead of miscounting it "present".

@test "heals a stale-pid row on a live pane (recycle-in-place → new pid/session/cwd; full rewrite)" {
  local pane=D08B4FC0-9253-4F54-A699-7D45CE568F84
  local dead; dead="$(deadpid)"
  # a rotted row from the PRIOR incarnation: dead pid + old session/cwd/account + a stale extra field.
  printf '{"paneUUID":"%s","name":"tmp-D08B4FC0","cwd":"/private/tmp","account":"claude-secondary","pid":%s,"startedAt":1,"session_id":"old-sid-aaaa","stale_extra":true}' \
    "$pane" "$dead" > "$CC_REGISTRY_DIR/$pane.json"
  # the CURRENT live occupant of the SAME pane: new pid, new session, new cwd + account.
  add_pane 2345 "$pane" /Users/x/.claude-quaternary new-sid-bbbb /Users/chrisren/Development/claude-infrastructure 1699222222000
  run "$CCR"
  [ "$status" -eq 0 ]
  local f="$CC_REGISTRY_DIR/$pane.json"
  [ "$(jq -r '.session_id' "$f")" = "new-sid-bbbb" ]                            # rewritten to the live occupant
  [ "$(jq -r '.cwd' "$f")" = "/Users/chrisren/Development/claude-infrastructure" ]
  [ "$(jq -r '.pid' "$f")" = "2345" ]
  [ "$(jq -r '.account' "$f")" = "claude-quaternary" ]
  [ "$(jq -r '.startedAt' "$f")" = "1699222222000" ]                           # CC's real start, not the stale 1
  [ "$(jq -r '.stale_extra' "$f")" = "null" ]                                  # full rewrite — stale field gone
  echo "$output" | grep -q 'healed 1'
  echo "$output" | grep -q '0 present'                                        # NOT miscounted present
}

@test "--json reports a stale-row heal as healed, not backfilled or present" {
  local pane=CAFED00D-1111-2222-3333-444444444444
  local dead; dead="$(deadpid)"
  printf '{"paneUUID":"%s","name":"old","cwd":"/old","account":"next","pid":%s,"startedAt":1,"session_id":"old"}' \
    "$pane" "$dead" > "$CC_REGISTRY_DIR/$pane.json"
  add_pane 2345 "$pane" /Users/x/.claude new-sid /tmp/new
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.healed')" = "1" ]
  [ "$(echo "$output" | jq -r '.backfilled')" = "0" ]
  [ "$(echo "$output" | jq -r '.present')" = "0" ]
}

@test "--dry-run heals nothing (row unchanged) but reports would-heal" {
  local pane=CAFED00D-1111-2222-3333-444444444444
  local dead; dead="$(deadpid)"
  printf '{"paneUUID":"%s","name":"old","cwd":"/old","account":"next","pid":%s,"startedAt":1,"session_id":"old-sid"}' \
    "$pane" "$dead" > "$CC_REGISTRY_DIR/$pane.json"
  add_pane 2345 "$pane" /Users/x/.claude new-sid /tmp/new
  run "$CCR" --dry-run
  [ "$status" -eq 0 ]
  [ "$(jq -r '.session_id' "$CC_REGISTRY_DIR/$pane.json")" = "old-sid" ]   # NOT rewritten
  echo "$output" | grep -q 'would heal 1'
}

@test "P8 forensics: a dead-pid row whose pane is NOT live is never touched (reconcile scans only live panes)" {
  local pane=DEADBEEF-0000-0000-0000-000000000000
  local dead; dead="$(deadpid)"
  printf '{"paneUUID":"%s","name":"gone","cwd":"/gone","account":"next","pid":%s,"startedAt":1,"session_id":"forensic-sid"}' \
    "$pane" "$dead" > "$CC_REGISTRY_DIR/$pane.json"
  # NO add_pane for this pane → no live claude proc resolves to it → reconcile never iterates it.
  run "$CCR"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.session_id' "$CC_REGISTRY_DIR/$pane.json")" = "forensic-sid" ]  # forensic row untouched
  echo "$output" | grep -q '0 live'
}

@test "unknown option → exit 2" {
  run "$CCR" --bogus
  [ "$status" -eq 2 ]
}
