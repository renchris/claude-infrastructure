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
  # NOT cosmetic: handoff-fire's capacity_gate() refuses a net-new fire above 2.0/core, and this box
  # lives well above that — unpinned, the fire assertions below go red BY LOAD rather than by their
  # subject. Same idiom as tests/fire-engagement.bats:20 and handoff-fire-pane-parked.bats:32.
  # (The spawn bin is stubbed here anyway, so this pins a coupling rather than changing a verdict —
  # which is exactly why it went unnoticed until the hermeticity ratchet scoped this suite.)
  export CC_FIRE_CAPACITY_GATE=off

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
  # The stderr line is the FIXTURE for the failure-evidence assertion in (d): a real handoff-fire
  # diagnoses itself on stderr, and until that stream was captured the dispatcher threw it away.
  cat > "$C/stubs/spawn" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >> "$SPAWN_LOG"
echo "handoff-fire: no pane anchor resolved" >&2
exit "$(cat "$SPAWN_RC_FILE" 2>/dev/null || echo 0)"
EOF
  # live-worker oracle stub (v2 admission reads it every pass). MUST be stubbed: unstubbed,
  # cc-dispatch resolves the operator's REAL claude-accounts, so free_slots would be computed from
  # the live fleet and every fire assertion below would invert whenever the operator has >= CEILING
  # sessions open — a suite whose verdict depends on what the desk happens to be doing.
  cat > "$C/stubs/accounts" <<'EOF'
#!/bin/bash
printf '{"rows":[{"acct":"a","k":0}]}\n'
EOF
  chmod +x "$C/stubs/waveplan" "$C/stubs/spawn" "$C/stubs/accounts"

  echo 0 > "$C/wp_rc"; echo 0 > "$C/spawn_rc"
  export CC_BACKLOG_FILE="$C/backlog.jsonl"
  export CC_DISPATCH_BACKLOG_BIN="$BACKLOG" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_ACCOUNTS_BIN="$C/stubs/accounts" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_PROJECT="/repo/proj" \
         CC_DISPATCH_MAX_SPAWN=2 \
         CC_DISPATCH_CEILING=6 \
         CC_DISPATCH_SID="bats"
  export WP_RC_FILE="$C/wp_rc" SPAWN_RC_FILE="$C/spawn_rc" SPAWN_LOG="$C/spawn.log"
}

# items use the ledger convention (basename); env stays path-style /repo/proj — the pair proves
# CC_DISPATCH_PROJECT basename-normalization through the real fold
add_item()   { "$BACKLOG" add --title "$1" --project proj --source bats; }   # echoes id
status_of()  { "$BACKLOG" list --all --json | jq -r --arg i "$1" '.[]|select(.id==$i)|.status'; }
idl_action() { tail -1 "$C/idl.jsonl" | jq -r '.action'; }

@test "selftest passes and runs its full check set (a zero-check suite must not 'pass')" {
  run "$DISP" selftest
  [ "$status" -eq 0 ]
  n_ok="$(printf '%s' "$output" | grep -c '^  ok ')"
  # FLOOR + TALLY, not `-eq N`. The exact-count form this replaces could only ever red on the
  # SUITE'S OWN GROWTH — it fired on 156 → 161 when the self-release rollback added its cases, and
  # over its whole history it caught zero regressions while costing an edit at every real
  # improvement (memory: exact-count-assertion-tripwires-its-own-subject). The two halves cover what
  # the count was reaching for and the count could not: the FLOOR kills a suite that silently stopped
  # running its checks, and the TALLY — the selftest's own summary line, with failures pinned at
  # zero — kills a suite that ran them and let some fail. Neither degrades as the suite grows.
  [ "$n_ok" -ge 156 ]
  [[ "$output" == *"$n_ok passed, 0 failed"* ]] || false
                        # 49 pre-v2 + the decision/admission split (S1,S2,S6,S7 + kill switches).
                        # 156 → 161: the SELF-RELEASE rollback (backlog 98e0e325b3ed) — (d) 2 for the
                        # flagged shape, (d2) 3 for the refused-flag fallback that must still release
                        # the claim without letting the journal claim a self-release it never made.
                        # 142 → 156: the ACTUATOR-ARBITER branch (5a) — (m2) 7 + (m2b) 4 + (m3) 3.
                        # The done latch is now enforced by `cc-backlog claim` itself, because step
                        # 1b's filter is pull-time and the landing can arrive during the wave-plan +
                        # admission tail (backlog dadc3c2410aa, measured on 5690b9d11bee). rc 4 has
                        # TWO causes since the lease landed, so (m2) and (m2b) are each other's
                        # control at the SAME rc: done-latch ⇒ skip, lease ⇒ failed. Without the
                        # pair, a bare `[ "$crc" -eq 4 ]` would stay green while reclassifying every
                        # lease refusal. (m3) holds the line on ordinary claim failures.
                        # 121 → 142: the STALE-PREMISE guard (1d) — 18 cases (v1-v6) covering the
                        # retraction, its positive control, the source-scope control that keeps a
                        # human-filed item citing a finished plan dispatchable, both fail-OPEN paths
                        # and the kill switch — plus 2 assertions that de-vacuum case (m). (m)'s
                        # claim/spawn assertions passed with the wasDone predicate stripped, so the
                        # PER-ITEM property was unproven; wave.json is the observable that fails.
                        # 113 → 121: the singleton gates ADMISSION, not DECISION (de5e3e24be8f) —
                        # case (t) asserts the lock-loser's full decision set plus four zero-effect
                        # reads, each mirrored by a (t2) positive control.
                        # 111 → 113: the spawn-failure record now names its rc AND carries the
                        # fire's own stderr, so (d) asserts the cause is present, not just the verdict.
                        # 108 → 106 when the ceiling moved off the accounts oracle onto the ledger's
                        # `claimed` fold (§3 S2): the oracle-hang bound and the zero-timeout config
                        # case had nothing left to bound. Fewer checks here is a DELETION of dead
                        # surface, not lost coverage — A14 in cc-dispatch-v2.bats now guards the
                        # signal itself, which is the property those two were circling.
                        # 106 → 111 with multi-project coverage (f7abcbdee98c): the brief's rails
                        # line is now read from the project, so (c) asserts BOTH branches instead of
                        # one unconditional '/ship', plus the (c6) positive control that a
                        # conf-declared FOREIGN project is dispatched and gets the ship rail when its
                        # repo carries one. This count is deliberately exact — it is what stops a
                        # selftest that silently stops running checks from reading as a pass.
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
  # …and the verdict NAMES ITS CAUSE (§1(c)/R3). The rc and the fire's own diagnostic both ride on
  # the record; without them "spawn non-zero" is exactly the un-evidenced verdict this rebuild
  # exists to remove, and 112 of them accrued in a single 10 h window saying nothing.
  grep -q '"detail":"'"$id"': spawn rc=7 (reopened, self-release)' "$C/idl.jsonl"
  # SELF-RELEASE is asserted, not incidental. The rollback reopens with --self-release, so reap's
  # rule B will not count this pair as thrash (bin/cc-backlog § SELF-RELEASE) — 228 items were
  # permanently blocked as "the worker cannot land" by exactly this shape before the flag existed.
  # The journal is the only surface where an operator can see that the exclusion happened.
  [ "$(jq -rs '[.[]|select(.action=="failed")]|last|.detail|test("self-release")' "$C/idl.jsonl")" = true ]
  grep -q 'no pane anchor resolved' "$C/idl.jsonl"
  # the id prefix survives verbatim — thrash_map recovers the id by splitting detail on the FIRST
  # colon, so an excerpt appended after it must not disturb S7 ordering
  [ "$(jq -rs '[.[]|select(.action=="failed")]|last|.detail|split(":")|.[0]' "$C/idl.jsonl")" = "$id" ]
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
