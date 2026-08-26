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

  # it2 stub for the guarded prune (f9385874de10). `session list --json` echoes $D/panes, which is
  # EMPTY by default ⇒ pane liveness unknown ⇒ FAIL-CLOSED, prune disabled. Every pre-existing test
  # therefore keeps its exact old behaviour; the prune tests opt in via live_panes/gone_panes below.
  : > "$D/panes"
  cat > "$D/bin/it2" <<SH
#!/bin/bash
[ "\$1 \$2" = "session list" ] && cat "$D/panes"
exit 0
SH
  chmod +x "$D/bin/it2"
  export CC_RECONCILE_IT2_BIN="$D/bin/it2"
}

# declare the iTerm2-live pane set (a JSON array of {id}); any pane NOT listed reads as GONE.
set_live_panes() {
  local out="[" first=1 p
  for p in "$@"; do [ "$first" = 1 ] || out="$out,"; out="$out{\"id\":\"$p\"}"; first=0; done
  printf '%s]\n' "$out" > "$D/panes"
}
# a registry row for a pane with NO live claude proc — args: pane pid startedAt
add_orphan_row() {
  printf '{"paneUUID":"%s","name":"orphan","cwd":"/gone","account":"next","pid":%s,"startedAt":%s,"session_id":"sid-%s"}' \
    "$1" "$2" "$3" "$1" > "$CC_REGISTRY_DIR/$1.json"
}
# startedAt (ms) far enough in the past to clear the CC_REG_RETAIN_H forensic window.
old_ms() { echo $(( CC_RECONCILE_NOW_MS - 48 * 3600 * 1000 )); }

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
# like add_pane but argv0 = …/bin/claude.exe (the eval-track / claude-next install's OWN binary name).
# session-register.sh:63 registers it (claude|claude.exe|claude-*), so reconcile MUST also be able to
# heal one that missed SessionStart — its live_claude_pids argv scan has to accept the .exe form too.
add_pane_exe() {
  local pid="$1" pane="$2" ccd="$3" sid="$4" cwd="$5" started="${6:-1699000000000}" kind="${7:-interactive}"
  printf '%s /Users/x/.claude-183/node_modules/@anthropic-ai/claude-code/bin/claude.exe --permission-mode auto --model claude-opus-4-8 --effort max\n' "$pid" >> "$D/pslist"
  printf 'claude.exe --permission-mode auto ITERM_SESSION_ID=w1t0p0:%s CLAUDE_CONFIG_DIR=%s TERM_PROGRAM=iTerm.app\n' "$pane" "$ccd" > "$D/psenv/$pid"
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","startedAt":%s,"kind":"%s","status":"idle"}\n' \
    "$pid" "$sid" "$cwd" "$started" "$kind" > "$D/sessions/$pid.json"
}
# a pane whose env carries NO ITERM_SESSION_ID (unaddressable).
add_pane_no_iterm() {
  local pid="$1"
  printf '%s /Users/x/.claude-183/node_modules/.bin/claude --permission-mode auto\n' "$pid" >> "$D/pslist"
  printf 'claude --permission-mode auto CLAUDE_CONFIG_DIR=/Users/x/.claude TERM_PROGRAM=Apple_Terminal\n' > "$D/psenv/$pid"
  printf '{"pid":%s,"sessionId":"s","cwd":"/tmp/x","startedAt":1,"kind":"interactive"}\n' "$pid" > "$D/sessions/$pid.json"
}
# A RESIDENT headless agent: argv carries -p AND --input-format, env carries a `hdl-` pane address
# (bin/cc-pane-headless mints it). Field order is copied from the real invocation in
# scripts/headless-precondition-probe.sh:121-125 — load-bearing, because --input-format lands at
# field 9 there, PAST the 3..8 window the -p/--version exclusion scans. A marker scan reusing that
# narrow window detects nothing and the whole E9 change reads correct while doing nothing.
add_headless() {  # pid paneAddr sid cwd
  printf '%s /Users/x/.claude-183/node_modules/.bin/claude -p --strict-mcp-config --settings /tmp/s.json --model claude-opus-5 --input-format stream-json --output-format stream-json --verbose\n' "$1" >> "$D/pslist"
  printf 'claude -p CC_PANE_ID=%s CLAUDE_CONFIG_DIR=/Users/x/.claude TERM_PROGRAM=Apple_Terminal\n' "$2" > "$D/psenv/$1"
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","startedAt":1699000000000,"kind":"headless"}\n' "$1" "$3" "$4" > "$D/sessions/$1.json"
}
# A true ONE-SHOT probe: -p with NO --input-format. Given a perfectly good pane address and sessions
# file on purpose, so the only thing that can keep it out of the registry is the argv rule itself.
add_oneshot() {  # pid paneAddr
  printf '%s /Users/x/.claude-183/node_modules/.bin/claude -p hi\n' "$1" >> "$D/pslist"
  printf 'claude -p CC_PANE_ID=%s CLAUDE_CONFIG_DIR=/Users/x/.claude\n' "$2" > "$D/psenv/$1"
  printf '{"pid":%s,"sessionId":"sid-oneshot","cwd":"/tmp/probe","startedAt":1699000000000,"kind":"headless"}\n' "$1" > "$D/sessions/$1.json"
}
rows() { ls "$CC_REGISTRY_DIR"/*.json 2>/dev/null | wc -l | tr -d ' '; }
# a definitely-dead real pid (spawn → kill → reap) — for the recycle-in-place stale-row heal tests.
# The heal decision uses a REAL kill -0 on the row's recorded pid (aligned with cc-sessions), so a
# "present" row needs a live pid ($$) and a "stale" row needs a dead one. Mirrors session-registry.bats.
deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; echo "$p"; }

@test "backfills a live claude.exe pane (eval-track binary), not only bare claude" {
  # RED before the argv-scan fix: live_claude_pids matched only claude/*/claude/cli.js, so a live
  # …/bin/claude.exe pane with no registry row was never iterated ⇒ never backfilled (rows stay 0),
  # leaving it double-blind (invisible to the reaper self-check too). GREEN: it gets its row.
  add_pane_exe 4321 EE501111-2222-3333-4444-555566667777 /Users/x/.claude-next sid-exe /tmp/wt-pool-e
  run "$CCR"
  [ "$status" -eq 0 ]
  [ "$(rows)" = 1 ]
  [ -f "$CC_REGISTRY_DIR/EE501111-2222-3333-4444-555566667777.json" ]
}

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

# ── f9385874de10: the guarded prune ─────────────────────────────────────────────────────────────

@test "prune: a CONFIRMED-GONE row (pane absent + pid dead) past the retain window is removed" {
  local pane=AAAA0000-0000-0000-0000-000000000001 dead; dead="$(deadpid)"
  add_orphan_row "$pane" "$dead" "$(old_ms)"
  set_live_panes SOMEONE-ELSE-0000-0000-000000000009
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ ! -f "$CC_REGISTRY_DIR/$pane.json" ]
  [ "$(printf '%s' "$output" | jq -r .pruned)" = 1 ]
}

@test "prune: a LIVE pane's stale-pid row is HEALED, never pruned (that is cc-reconcile's heal case)" {
  local pane=AAAA0000-0000-0000-0000-000000000002 dead; dead="$(deadpid)"
  add_orphan_row "$pane" "$dead" "$(old_ms)"
  add_pane 51001 "$pane" "$HOME/.claude" "fresh-sid" "/work/x"   # a LIVE claude proc on that pane
  set_live_panes "$pane"
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ -f "$CC_REGISTRY_DIR/$pane.json" ]
  [ "$(jq -r .session_id "$CC_REGISTRY_DIR/$pane.json")" = "fresh-sid" ]   # healed
  [ "$(printf '%s' "$output" | jq -r .pruned)" = 0 ]
  [ "$(printf '%s' "$output" | jq -r .healed)" = 1 ]
}

@test "prune: FAIL-CLOSED — it2 unreadable (pane liveness unknown) prunes NOTHING" {
  local pane=AAAA0000-0000-0000-0000-000000000003 dead; dead="$(deadpid)"
  add_orphan_row "$pane" "$dead" "$(old_ms)"
  : > "$D/panes"                      # it2 answers nothing ⇒ unknown, NOT "every pane is gone"
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ -f "$CC_REGISTRY_DIR/$pane.json" ]
  [ "$(printf '%s' "$output" | jq -r .pruned)" = 0 ]
}

# write $D/panes as the needle pane followed by $1 filler panes, so the id list handed to the
# liveness membership test is past the pipe-buffer regime with the needle on line 1.
set_live_panes_bulk() {
  local needle="$1" n="$2"
  awk -v needle="$needle" -v n="$n" 'BEGIN{
    printf "[{\"id\":\"%s\"}", needle
    for (i = 1; i <= n; i++) printf ",{\"id\":\"FILL%04d-0000-0000-0000-%012d\"}", i, i
    printf "]\n" }' > "$D/panes"
}

@test "prune: a LIVE pane is retained when the live-pane list is past the pipe-buffer regime" {
  # THE MECHANISM ARM for the liveness membership test in the prune loop. Every prune case above
  # declares two or three live panes — a ~40-byte id list, which is three orders of magnitude below
  # the regime where this predicate can invert, so all of them stay green over a `grep -q` that
  # answers NOT-LIVE for a pane iTerm2 just reported as live. The consequence is not a wrong
  # message: the `continue` is skipped and the row falls through to the prune arm, so a live pane's
  # registry row is DELETED. This arm is the one that can see that.
  #
  # 2,600 filler panes ⇒ an id list past the measured always-inverted floor of 87,122 bytes for
  # this two-stage shape, needle on line 1, so a re-introduced -q fails every run, not one in
  # twenty. The size is asserted rather than assumed.
  local pane=AAAA0000-0000-0000-0000-000000000004 dead; dead="$(deadpid)"
  add_orphan_row "$pane" "$dead" "$(old_ms)"
  set_live_panes_bulk "$pane" 2600
  local idbytes; idbytes="$(jq -r 'if type=="array" then .[].id // empty else empty end' "$D/panes" | wc -c | tr -d ' ')"
  [ "$idbytes" -ge 87122 ] || { echo "live-pane id list is $idbytes B — under the inverting floor, cannot discriminate" >&2; return 1; }

  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ -f "$CC_REGISTRY_DIR/$pane.json" ] || { echo "a LIVE pane's row was PRUNED at a $idbytes B live-pane list" >&2; return 1; }
  [ "$(printf '%s' "$output" | jq -r .pruned)" = 0 ]

  # NEGATIVE control: an ABSENT pane at the same list size must still be pruned, so this arm cannot
  # pass by simply never pruning once the list is large.
  local gone=AAAA0000-0000-0000-0000-000000000005
  add_orphan_row "$gone" "$dead" "$(old_ms)"
  set_live_panes_bulk "$pane" 2600          # $gone is deliberately NOT in the list
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ ! -f "$CC_REGISTRY_DIR/$gone.json" ] || { echo "an ABSENT pane survived — the arm cannot discriminate" >&2; return 1; }
  true
}

@test "prune: P8 forensics — a gone row INSIDE the retain window survives (age, not liveness)" {
  local pane=AAAA0000-0000-0000-0000-000000000004 dead; dead="$(deadpid)"
  add_orphan_row "$pane" "$dead" "$CC_RECONCILE_NOW_MS"   # just died — still investigable
  set_live_panes SOMEONE-ELSE-0000-0000-000000000009
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ -f "$CC_REGISTRY_DIR/$pane.json" ]
  [ "$(printf '%s' "$output" | jq -r .pruned)" = 0 ]
}

@test "prune: a gone pane whose recorded pid is still ALIVE is not confirmed gone → kept" {
  local pane=AAAA0000-0000-0000-0000-000000000005
  add_orphan_row "$pane" "$$" "$(old_ms)"                 # $$ = this bats process, definitely alive
  set_live_panes SOMEONE-ELSE-0000-0000-000000000009
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ -f "$CC_REGISTRY_DIR/$pane.json" ]
  [ "$(printf '%s' "$output" | jq -r .pruned)" = 0 ]
}

# cc-sessions ages a row out only when startedAt > 0, so an undated row was IMMORTAL — the shape the
# 82-row pile was made of. mtime is the fallback clock (the file is backdated here to prove it).
@test "prune: an UNDATED gone row ages out by file mtime (the immortality gap)" {
  local pane=AAAA0000-0000-0000-0000-000000000006 dead; dead="$(deadpid)"
  printf '{"paneUUID":"%s","name":"undated","cwd":"/gone","account":"next","pid":%s,"session_id":"s"}' \
    "$pane" "$dead" > "$CC_REGISTRY_DIR/$pane.json"
  touch -t 202001010000 "$CC_REGISTRY_DIR/$pane.json"
  set_live_panes SOMEONE-ELSE-0000-0000-000000000009
  run env CC_RECONCILE_NOW_MS=$(( $(date +%s) * 1000 )) "$CCR" --json
  [ "$status" -eq 0 ]
  [ ! -f "$CC_REGISTRY_DIR/$pane.json" ]
}

@test "prune: --dry-run reports the count but deletes nothing" {
  local pane=AAAA0000-0000-0000-0000-000000000007 dead; dead="$(deadpid)"
  add_orphan_row "$pane" "$dead" "$(old_ms)"
  set_live_panes SOMEONE-ELSE-0000-0000-000000000009
  run "$CCR" --dry-run --json
  [ "$status" -eq 0 ]
  [ -f "$CC_REGISTRY_DIR/$pane.json" ]
  [ "$(printf '%s' "$output" | jq -r .pruned)" = 1 ]
}

# ── f9385874de10: the WIRING (the actual root cause — the hook existed but nothing called it) ────

@test "wiring: session-deregister.sh is registered as a SessionEnd hook in the settings template" {
  run jq -e '[.hooks.SessionEnd[]?.hooks[]?.command]
             | any(. == "~/.claude/hooks/session-deregister.sh")' \
    "$REPO/settings-templates/settings.example.json"
  [ "$status" -eq 0 ]
}

@test "wiring: an activation script exists to wire the hook into the LIVE settings.json (C10)" {
  local A="$REPO/docs/activation/pending-activation/08-session-deregister-activate.sh"
  [ -f "$A" ]
  run bash -n "$A"
  [ "$status" -eq 0 ]
  grep -q 'session-deregister.sh' "$A"
  run env CONFIRM=0 bash "$A"      # no CONFIRM ⇒ dry run, must never touch the live settings
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qi 'dry run'
}

# ── class-B pane identity: CC_PANE_ID out of ANOTHER pid's env blob (item 0f796daa0c76) ────────────
# a headless/kitty pane: CC_PANE_ID only, in its BARE (colon-free) spelling, no ITERM_SESSION_ID.
add_pane_headless() { # pid paneUUID configdir sid cwd
  printf '%s /Users/x/.claude-183/node_modules/.bin/claude --permission-mode auto\n' "$1" >> "$D/pslist"
  printf 'claude --permission-mode auto CC_PANE_ID=%s CLAUDE_CONFIG_DIR=%s TERM_PROGRAM=WezTerm\n' "$2" "$3" > "$D/psenv/$1"
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","startedAt":1699000000000,"kind":"interactive","status":"idle"}\n' \
    "$1" "$4" "$5" > "$D/sessions/$1.json"
}
# a pane carrying BOTH keys, DISAGREEING — the shape $ITERM_SESSION_ID's inheritance across exec and
# across pane boundaries actually produces: a re-keyed pane holding a stale iTerm2 id beside its real one.
add_pane_both() { # pid realPaneUUID stalePaneUUID configdir sid cwd
  printf '%s /Users/x/.claude-183/node_modules/.bin/claude --permission-mode auto\n' "$1" >> "$D/pslist"
  printf 'claude --permission-mode auto ITERM_SESSION_ID=w1t0p0:%s CC_PANE_ID=%s CLAUDE_CONFIG_DIR=%s TERM_PROGRAM=iTerm.app\n' \
    "$3" "$2" "$4" > "$D/psenv/$1"
  printf '{"pid":%s,"sessionId":"%s","cwd":"%s","startedAt":1699000000000,"kind":"interactive","status":"idle"}\n' \
    "$1" "$5" "$6" > "$D/sessions/$1.json"
}

@test "class B: backfills a HEADLESS pane identified only by a bare CC_PANE_ID" {
  # RED pre-fix: the pane id was read from ITERM_SESSION_ID alone, so this pane resolved to EMPTY,
  # counted n_no_pane and was skipped — permanently unregistered and invisible to the reaper, which
  # is the exact double-blindness cc-reconcile exists to close. Bare (colon-free) on purpose:
  # CC_PANE_ID is a superset that accepts it, and `${pane##*:}` must be a no-op there, not a mangle.
  add_pane_headless 5150 BB011111-2222-3333-4444-555566667777 /Users/x/.claude-next sid-hl /tmp/wt-headless
  run "$CCR"
  [ "$status" -eq 0 ]
  [ "$(rows)" = 1 ]
  [ -f "$CC_REGISTRY_DIR/BB011111-2222-3333-4444-555566667777.json" ]
}

@test "class B: with BOTH keys set and disagreeing, the row is keyed on CC_PANE_ID" {
  # The load-bearing half, and the reason this is a PREFERENCE rather than an either-key match.
  # Pre-fix the row was written under the STALE iTerm2 id — a registry row filed against a pane this
  # process does not occupy, which is worse than no row at all: the reaper acts on it.
  add_pane_both 5151 CC021111-2222-3333-4444-555566667777 DEAD9999-2222-3333-4444-555566667777 \
    /Users/x/.claude-next sid-both /tmp/wt-both
  run "$CCR"
  [ "$status" -eq 0 ]
  [ -f "$CC_REGISTRY_DIR/CC021111-2222-3333-4444-555566667777.json" ]
  if [ -f "$CC_REGISTRY_DIR/DEAD9999-2222-3333-4444-555566667777.json" ]; then
    echo "row was keyed on the STALE ITERM_SESSION_ID — preference not honoured" >&2
    false
  fi
}

# --- spec 03 E9: -p no longer means "not a session" ------------------------------------------------
# 33 pane-less sessions ran on this box invisible to the whole fleet because the argv scan dropped
# every -p process. The discriminator is --input-format: a resident headless agent streams, a
# one-shot probe does not. Liveness stays (pid,lstart) — argv never becomes the liveness oracle.

@test "E9: a RESIDENT headless session (-p with --input-format) is COUNTED LIVE, not dropped" {
  # THE E9 DELTA, stated exactly. Pre-fix the argv scan dropped every -p process, so a resident
  # headless agent was never iterated at all and live=0 — invisible to the whole fleet. Post-fix it
  # is a live session the scan yields. It does NOT yet get a ROW: cc-reconcile:220 requires the CC
  # sessions file to read kind=="interactive", and what CC writes there for a resident -p session is
  # the SPEC OWN OPEN QUESTION Q1 (03-headless-substrate.md:446, "All 9 live rows read interactive.
  # Measure.") — re-measured 2026-08-19 and still unanswerable: 9 session files on this box, all
  # interactive, zero headless processes running. So the gate is asserted where the evidence ends.
  add_headless 5150 hdl-0123456789abcdef sid-headless /tmp/wt-headless
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.live')" = 1 ]
  [ "$(printf '%s' "$output" | jq -r '.skipped')" = 1 ]
}

@test "E9: a true one-shot probe (-p, NO --input-format) still gets NO row" {
  # The over-widening this guards (spec T8): dropping the -p exclusion outright would mint a row for
  # every transient `claude -p` probe. It is handed a valid hdl- address and a sessions file, so the
  # argv rule is the ONLY thing that can exclude it.
  add_oneshot 5151 hdl-fedcba9876543210
  run "$CCR" --json
  [ "$status" -eq 0 ]
  # Asserted on the LIVE count, NOT on rows. rows==0 is VACUOUS here: cc-reconcile:220 also rejects
  # it at the kind gate, so a mutant that drops the -p rule outright still leaves rows at 0 and this
  # case passes having tested nothing. Measured by exactly that mutant, which reded its cc-reaper
  # sibling and not this one.
  [ "$(printf '%s' "$output" | jq -r '.live')" = 0 ]
  [ "$(rows)" = 0 ]
}

@test "E9: the two are told apart in ONE pass — the resident is registered, the probe is not" {
  add_headless 5150 hdl-0123456789abcdef sid-headless /tmp/wt-headless
  add_oneshot  5151 hdl-fedcba9876543210
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.live')" = 1 ]      # the resident only — never the probe
  [ "$(rows)" = 0 ]
}

@test "E9: --version is STILL excluded, even carrying the streaming marker" {
  # --version is unconditional: the marker re-admits -p only. Without this, "drop --version always"
  # is asserted by nothing and a later simplification could fold it into the -p rule unnoticed.
  printf '5152 /Users/x/.claude-183/node_modules/.bin/claude --version --input-format stream-json\n' >> "$D/pslist"
  printf 'claude --version CC_PANE_ID=hdl-aaaabbbbccccdddd CLAUDE_CONFIG_DIR=/Users/x/.claude\n' > "$D/psenv/5152"
  printf '{"pid":5152,"sessionId":"sid-v","cwd":"/tmp/v","startedAt":1699000000000,"kind":"headless"}\n' > "$D/sessions/5152.json"
  run "$CCR" --json
  [ "$status" -eq 0 ]
  # LIVE, not rows — same vacuity as the one-shot case: the kind gate would hold rows at 0 anyway,
  # so a mutant folding --version under the marker rule passed this case until it asserted here.
  [ "$(printf '%s' "$output" | jq -r '.live')" = 0 ]
  [ "$(rows)" = 0 ]
}

@test "E9: the marker is found PAST the narrow -p window — a same-window scan would see nothing" {
  # THE VACUITY THIS EXISTS FOR. The -p/--version exclusion scans argv fields 3..8. In the real
  # invocation --input-format is field 9 (headless-precondition-probe.sh:121-125), so a marker scan
  # reusing that window returns "absent" for every genuine resident headless session and the fix is
  # inert. Pin the marker even FURTHER out so the scan cannot be quietly narrowed back.
  printf '5153 /Users/x/.claude-183/node_modules/.bin/claude -p --strict-mcp-config --settings /tmp/s.json --model claude-opus-5 --allowedTools Bash --permission-mode auto --verbose --input-format stream-json\n' >> "$D/pslist"
  printf 'claude -p CC_PANE_ID=hdl-1111222233334444 CLAUDE_CONFIG_DIR=/Users/x/.claude\n' > "$D/psenv/5153"
  printf '{"pid":5153,"sessionId":"sid-far","cwd":"/tmp/far","startedAt":1699000000000,"kind":"headless"}\n' > "$D/sessions/5153.json"
  run "$CCR" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.live')" = 1 ]
}
