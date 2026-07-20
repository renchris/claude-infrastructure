#!/usr/bin/env bats
# T-P7-4/5 cc-dispatch — the L4 dispatcher spine. The tool's `selftest` RED-proves every branch
# against stubbed actuators; these bats add (a) the selftest exit-code + check-count contract and
# (b) CLI-level end-to-end runs against the REAL cc-backlog (temp CC_BACKLOG_FILE) so the backlog
# TRANSITION (open→claimed→reopen) is proven through the real fold — not just "claim was invoked".
# cc-wave-plan (unbuilt; T-P7-6) + the spawn bin + the pages dir are stubbed via the env seams.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="$REPO/bin/cc-dispatch"
  BACKLOG="$REPO/bin/cc-backlog"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/pages" "$C/stubs"

  # wave-plan stub: echoes placements keyed by the input --items ids (as a real planner would),
  # with a fixed account + fire_line argv; rc read from $WP_RC_FILE ("4" ⇒ quota-cliff).
  cat > "$C/stubs/waveplan" <<'EOF'
#!/bin/bash
items=""
while [ $# -gt 0 ]; do case "$1" in --items) items="$2"; shift 2 ;; *) shift ;; esac; done
rc="$(cat "$WP_RC_FILE" 2>/dev/null || echo 0)"
[ "$rc" = 0 ] || exit "$rc"
printf '%s' "$items" \
  | jq -c '[ .[] | {id, account:"next3", fire_line:["--prompt-file","/tmp/fire.txt","--account","next3"]} ]'
EOF

  # spawn stub: append argv to $SPAWN_LOG; rc from $SPAWN_RC_FILE.
  cat > "$C/stubs/spawn" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SPAWN_LOG"
exit "$(cat "$SPAWN_RC_FILE" 2>/dev/null || echo 0)"
EOF
  chmod +x "$C/stubs/waveplan" "$C/stubs/spawn"

  echo 0 > "$C/wp_rc"; echo 0 > "$C/spawn_rc"
  export CC_BACKLOG_FILE="$C/backlog.jsonl"
  export CC_DISPATCH_BACKLOG_BIN="$BACKLOG" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_PROJECT="/repo/proj" \
         CC_DISPATCH_MAX_SPAWN=2 \
         CC_DISPATCH_SID="bats"
  export WP_RC_FILE="$C/wp_rc" SPAWN_RC_FILE="$C/spawn_rc" SPAWN_LOG="$C/spawn.log"
}

# items use the ledger convention (basename); env stays path-style /repo/proj — the pair proves
# CC_DISPATCH_PROJECT basename-normalization through the real fold
add_item()   { "$BACKLOG" add --title "$1" --project proj --source bats; }   # echoes id
status_of()  { "$BACKLOG" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }
idl_action() { tail -1 "$C/idl.jsonl" | jq -r '.action'; }

@test "selftest passes and runs all 49 checks (a zero-check suite must not 'pass')" {
  run "$DISP" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  [ "$n_ok" -eq 49 ]
  ! printf '%s' "$output" | grep -q '^  FAIL'
}

@test "unknown arg → exit 3 (fail-loud, no silent no-op)" {
  run "$DISP" --bogus
  [ "$status" -eq 3 ]
}

@test "(a) empty backlog → IDL passed, ZERO spawn, exit 0" {
  run "$DISP" --once
  [ "$status" -eq 0 ]
  grep -q '"action":"passed"' "$C/idl.jsonl"
  [ "$(idl_action)" = summary ]
  [ ! -s "$C/spawn.log" ]
}

@test "(b) quota-cliff (wave-plan exit 4) → abstained + page written + ZERO spawn, item stays open" {
  id="$(add_item cliff)"
  echo 4 > "$C/wp_rc"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  grep -q '"action":"abstained"' "$C/idl.jsonl"
  [ -f "$C/pages/cc-dispatch-quota-cliff.page" ]
  head -1 "$C/pages/cc-dispatch-quota-cliff.page" | grep -qE '^[0-9]+$'
  [ ! -s "$C/spawn.log" ]
  [ "$(status_of "$id")" = open ]
}

@test "(c) green → item TRANSITIONS to claimed (real fold) + spawn got fire_line + IDL fired" {
  id="$(add_item green)"
  [ "$(status_of "$id")" = open ]
  run "$DISP" --once
  [ "$status" -eq 0 ]
  [ "$(status_of "$id")" = claimed ]
  grep -q -- '--prompt-file /tmp/fire.txt --account next3' "$C/spawn.log"
  grep -q '"action":"fired"' "$C/idl.jsonl"
}

@test "(k) blocked-on-operator item is NOT dispatched (real fold): ZERO spawn, stays blocked, IDL passed" {
  id="$(add_item parked)"
  "$BACKLOG" block "$id" --needs "operator: run claude-kimi set-key" >/dev/null
  [ "$(status_of "$id")" = blocked ]
  run "$DISP" --once
  [ "$status" -eq 0 ]
  grep -q '"action":"passed"' "$C/idl.jsonl"   # filtered out → backlog looks empty → passed
  [ ! -s "$C/spawn.log" ]                       # no worker slot burned (the anti-loop guard)
  [ "$(status_of "$id")" = blocked ]            # untouched: not claimed, not reopened
}

@test "(d) spawn non-zero → item REOPENED (open again) + IDL failed" {
  id="$(add_item fail)"
  echo 7 > "$C/spawn_rc"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  # was claimed then reopened → open; the attempt is proven by the spawn log + failed IDL.
  [ "$(status_of "$id")" = open ]
  grep -q -- '--prompt-file /tmp/fire.txt' "$C/spawn.log"
  grep -q '"action":"failed"' "$C/idl.jsonl"
}

@test "(e) --dry-run → plan printed, backlog UNCHANGED, spawn NOT called" {
  id="$(add_item dry)"
  before="$("$BACKLOG" list --all --json)"
  run "$DISP" --dry-run
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'PLAN:'
  [ "$("$BACKLOG" list --all --json)" = "$before" ]
  [ ! -s "$C/spawn.log" ]
  [ "$(status_of "$id")" = open ]
}

@test "(f) cc-backlog list --json emits valid JSON AND leaves default table output unchanged" {
  add_item jsontest >/dev/null
  # machine branch: a valid JSON array carrying the item.
  run bash -c '"$1" list --all --json | jq -e "type==\"array\" and (any(.[]; .title==\"jsontest\"))"' _ "$BACKLOG"
  [ "$status" -eq 0 ]
  # default (table) branch: pipe-delimited, NOT JSON.
  run "$BACKLOG" list --all
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q ' | proj'
  ! printf '%s' "$output" | grep -q '^\['
}

# ── done-guard: completed work never re-enters the wave (incident 2026-07-20) ───────────────────
@test "(l) a re-opened DONE item is SKIPPED, not dispatched; --force re-arms it (real fold)" {
  id="$(add_item guarded)"
  "$BACKLOG" done "$id" --evidence "6488617 landed" >/dev/null
  # a hand-appended UNFORCED reopen — the exact shape that burned a session: status is "open"
  # again, which is cc-dispatch's fire predicate, but the done latch is still set.
  printf '{"id":"%s","ts":"2026-07-20T09:00:00Z","event":"reopen"}\n' "$id" >> "$CC_BACKLOG_FILE"
  [ "$(status_of "$id")" = open ]
  run "$DISP" --once
  [ "$status" -eq 0 ]
  [ ! -s "$C/spawn.log" ]                        # no worker session burned
  [ "$(status_of "$id")" = open ]                # and not even claimed
  grep -q '"action":"skipped"' "$C/idl.jsonl"    # never a silent fence
  grep -q '6488617' "$C/idl.jsonl"               # the skip carries the prior evidence
  # the deliberate override clears the latch and the item becomes dispatchable again
  "$BACKLOG" reopen "$id" --force >/dev/null
  run "$DISP" --once
  [ "$status" -eq 0 ]
  [ -s "$C/spawn.log" ]
  [ "$(status_of "$id")" = claimed ]
}

@test "(d2) spawn-fail rollback survives the live-claim guard when SID is a LIVE host-pid" {
  # Regression on the rollback path itself: cc-dispatch claims --by \$SID and, on spawn-fail,
  # reopens. \$SID is its OWN still-running <host>-<pid> — maximally live — so the reopen is only
  # legal as a SELF-release (--by \$SID). Drop that flag and the live-claim guard refuses the
  # rollback and the item strands as `claimed` until reap. Proven against the REAL cc-backlog.
  export CC_DISPATCH_SID="$(hostname -s 2>/dev/null || hostname)-$$"
  id="$(add_item selfrelease)"
  echo 7 > "$C/spawn_rc"
  run "$DISP" --once
  [ "$status" -eq 0 ]
  [ "$(status_of "$id")" = open ]                 # rolled back, NOT stranded as claimed
  grep -q '"action":"failed"' "$C/idl.jsonl"
}

@test "MAX_SPAWN cap → 3 dispatchable items, only 2 spawned in one pass" {
  add_item one   >/dev/null
  add_item two   >/dev/null
  add_item three >/dev/null
  run "$DISP" --once
  [ "$status" -eq 0 ]
  [ "$(grep -c . "$C/spawn.log")" -eq 2 ]
  [ "$(tail -1 "$C/idl.jsonl" | jq -r '.fired')" -eq 2 ]
}
