#!/usr/bin/env bats
# cc-dispatch V2 — the DECISION/ADMISSION split (docs/plans/AUTONOMY_DISPATCH_V2.md §3 S1,S2,S6,S7).
#
# WHAT THIS SUITE IS FOR. Every test here is a PAIR: the same fixture is run against the shipped
# bin/cc-dispatch AND against the PRISTINE pre-change tree recovered with `git archive` from the
# pinned base sha, and the pristine half must FAIL the very assertion the new half passes. A test
# that cannot fail on the old code proves nothing about the new code, and a hand-typed
# "approximation" of the old code proves nothing about the old code (memory:
# control-must-replay-the-real-artifact). So the control IS the artifact, byte for byte.
#
# WHY A PINNED SHA AND NOT origin/main: the moment this work lands, `origin/main:bin/cc-dispatch`
# BECOMES the new version, and every "the old tree fails this" assertion would invert and go red for
# the whole fleet. bf796c57 is this branch's base and an ancestor of main forever, so the control
# stays the control.
#
# ABSENCE ASSERTIONS ALWAYS COME WITH A POSITIVE CONTROL. "zero wave-plan calls", "zero spawns" and
# "no page written" are only evidence if the SAME harness demonstrably observes those effects when
# the condition is reversed — otherwise a broken stub reads as a passing guard (memory:
# absence-alarm-needs-existence-evidence). Test 3 is that control, and each absence test names it.
#
# Every actuator is stubbed through cc-dispatch's env seams: the backlog, the wave planner, the spawn
# bin AND the live-worker oracle (`claude-accounts --json`). $HOME is fixtured: unstubbed, the oracle
# seam resolves the operator's REAL claude-accounts, so the suite would read the live fleet — slow,
# flaky, and with a real live count >= CEILING every fire assertion here would silently invert.

BASE_SHA="bf796c57"   # immutable ancestor of origin/main; carries the pre-change bin/cc-dispatch

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  DISP="$REPO/bin/cc-dispatch"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/stubs" "$C/home" "$C/pristine"
  export HOME="$C/home"          # hermetic: nothing here may read or write the operator's live ~/

  # the pre-change control, recovered from git (never hand-edited)
  git -C "$REPO" archive "$BASE_SHA" bin/cc-dispatch 2>/dev/null | tar -x -C "$C/pristine"
  PRISTINE="$C/pristine/bin/cc-dispatch"
  chmod +x "$PRISTINE" 2>/dev/null || true
  # FAIL LOUD if the control could not be recovered. Without this the RED halves below would run an
  # absent binary that writes nothing, and every "the old tree does NOT do this" assertion would pass
  # VACUOUSLY — the exact way a control silently stops being a control (this bit once already: a copy
  # of this suite run from outside the repo resolved $REPO to a non-repo and recovered nothing).
  if [ ! -x "$PRISTINE" ]; then
    echo "cc-dispatch-v2.bats: cannot recover the pristine control — 'git -C $REPO archive $BASE_SHA bin/cc-dispatch' produced nothing. The RED-proof cannot run." >&2
    return 1
  fi

  # backlog stub: items from $C/items.json; claim/reopen logged to $C/backlog.log.
  cat > "$C/stubs/backlog" <<EOF
#!/bin/bash
[ -n "\${STUB_LIST_SLEEP:-}" ] && [ "\$1" = list ] && sleep "\$STUB_LIST_SLEEP"
case "\$1" in
  list)
    shift
    case "\$*" in
      *--all*)
        [ -n "\${STUB_LIST_ALL_RC:-}" ] && exit "\$STUB_LIST_ALL_RC"
        if [ "\${STUB_LIVE:-0}" = x ]; then echo 'definitely not json'
        else jq -cn --argjson n "\${STUB_LIVE:-0}" '[range(\$n) | {id:"c\(.)", status:"claimed"}]'; fi ;;
      *) cat "$C/items.json" ;;
    esac ;;
  claim)  printf 'claim %s\n'  "\$2" >> "$C/backlog.log"; echo "\$2" ;;
  reopen) printf 'reopen %s\n' "\$2" >> "$C/backlog.log"; echo "\$2" ;;
esac
exit 0
EOF
  # wave-plan stub: captures the wave it was handed to $C/wave.json (its ABSENCE is how "zero
  # wave-plan calls" is observed) and places EXACTLY the items it was given, as the real planner
  # does. A stub that answers with a fixed plan regardless of its input cannot see an admission bug
  # at all: it would return 3 placements for a 1-item wave and the spawn loop would fire 2.
  cat > "$C/stubs/waveplan" <<EOF
#!/bin/bash
items='[]'
while [ \$# -gt 0 ]; do case "\$1" in --items) items="\$2"; printf '%s' "\$2" > "$C/wave.json"; shift 2 ;; *) shift ;; esac; done
rc="\${STUB_WP_RC:-0}"
[ "\$rc" = 0 ] && printf '%s' "\$items" \
  | jq -c '[ .[] | {id, account:"next3", fire_line:["--prompt-file","/dev/null"]} ]'
exit "\$rc"
EOF
  # spawn stub: argv logged to $C/spawn.log.
  cat > "$C/stubs/spawn" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$C/spawn.log"
exit "\${STUB_SPAWN_RC:-0}"
EOF
  chmod +x "$C/stubs/backlog" "$C/stubs/waveplan" "$C/stubs/spawn"

  export CC_DISPATCH_BACKLOG_BIN="$C/stubs/backlog" \
         CC_DISPATCH_WAVEPLAN_BIN="$C/stubs/waveplan" \
         CC_DISPATCH_SPAWN_BIN="$C/stubs/spawn" \
         CC_DISPATCH_PAGES_DIR="$C/pages" \
         CC_DISPATCH_IDL="$C/idl.jsonl" \
         CC_DISPATCH_LOCK_DIR="$C/dispatch.lock" \
         CC_DISPATCH_PROJECT="/repo/proj" \
         CC_DISPATCH_MAX_SPAWN=2 \
         CC_DISPATCH_SID="bats"
  seed_items 3
}

# ── fixtures ──────────────────────────────────────────────────────────────────────────────────────
seed_items() { jq -cn --argjson n "$1" '[range(1;$n+1)|{id:("i"+(tostring)),project:"proj",status:"open",title:"t"}]' > "$C/items.json"; }
# fresh — a clean observation slate before EVERY pass, so each assertion reads only that pass.
fresh() { : > "$C/idl.jsonl"; : > "$C/spawn.log"; : > "$C/backlog.log"; rm -rf "$C/pages" "$C/wave.json" "$C/dispatch.lock"; }

# dec [extra-predicate] → count of decision records matching it. The predicate is interpolated INSIDE
# select(...): appended after the closing paren it would read as `select(…) and …`, a truthiness
# expression that emits one true/false per input record and counts the WHOLE file — a silently
# wrong number, not an error.
dec()        { jq -rs "[.[]|select(.action==\"decision\"${1:-})]|length" "$C/idl.jsonl" 2>/dev/null || echo 0; }
verdicts()   { jq -rs '[.[]|select(.action=="decision")|.verdict]|sort|unique|join(",")' "$C/idl.jsonl" 2>/dev/null; }
# `grep -c .` prints 0 AND exits 1 on an empty file, so a bare `|| echo 0` emits "0\n0" and every
# numeric comparison against it dies with "integer expression expected".
spawns()     { local n; n="$(grep -c . "$C/spawn.log" 2>/dev/null || true)"; echo "${n:-0}"; }

# ── S1 — a decision for every open item, every pass ───────────────────────────────────────────────
@test "S1/A1: 12-item backlog at ceiling 3 → 12 decisions (3 admit, 9 defer at positions 4..12); the PRISTINE tree journals none" {
  seed_items 12
  fresh; CC_DISPATCH_CEILING=3 "$DISP" --once >/dev/null 2>&1
  [ "$(dec)" -eq 12 ] || false
  [ "$(dec ' and .verdict=="admit"')" -eq 3 ] || false
  [ "$(dec ' and .verdict=="defer"')" -eq 9 ] || false
  [ "$(jq -rs '[.[]|select(.verdict=="defer")|.position]|sort|@csv' "$C/idl.jsonl")" = '4,5,6,7,8,9,10,11,12' ] || false
  [ "$(jq -rs '[.[]|select(.action=="decision")|.pass]|unique|length' "$C/idl.jsonl")" -eq 1 ] || false

  # RED against the real pre-change artifact: no decision stage existed at all, so an item past the
  # MAX_SPAWN slice got NO record of any kind — the ⌈P/2⌉-ticks-to-a-decision latency this replaces.
  fresh; CC_DISPATCH_CEILING=3 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(dec)" -eq 0 ] || false
  [ -s "$C/idl.jsonl" ]
}

@test "S1: the decision record carries the exact field names scripts/dispatch-acceptance.sh reads" {
  fresh; CC_DISPATCH_CEILING=6 "$DISP" --decide >/dev/null 2>&1
  # A1 groups by .pass and counts distinct .id; A3 selects .verdict=="defer"; A7 reads .live_workers
  # on admit records. A rename here silently turns the acceptance read into a phantom failure.
  run jq -rs '[.[]|select(.action=="decision")][0]|[has("pass"),has("id"),has("verdict"),has("position"),has("reason"),has("free_slots"),has("live_workers")]|all' "$C/idl.jsonl"
  [ "$status" -eq 0 ] || false
  [ "$output" = true ] || false
  [ "$(jq -rs '[.[]|select(.action=="decision")][0].actor' "$C/idl.jsonl")" = cc-dispatch ]
}

# ── S2 — capacity-driven admission ────────────────────────────────────────────────────────────────
@test "S2: free_slots == 0 → ZERO wave-plan calls, ZERO claims, ZERO spawns, ZERO pages, every item deferred at-ceiling (control: test 3)" {
  fresh; CC_DISPATCH_CEILING=0 "$DISP" --once >/dev/null 2>&1
  [ "$(dec)" -eq 3 ] || false
  [ "$(verdicts)" = defer ] || false
  [ "$(dec ' and .reason=="at-ceiling"')" -eq 3 ] || false
  [ ! -f "$C/wave.json" ] || false          # the oracle was never even asked
  [ ! -s "$C/backlog.log" ] || false
  [ "$(spawns)" -eq 0 ] || false
  [ ! -d "$C/pages" ] || false              # a full queue is a NORMAL state, never a cliff
  ! grep -q '"action":"abstained"' "$C/idl.jsonl" || false

  # RED: the pre-change tree has no ceiling term anywhere — it plans and fires regardless.
  fresh; CC_DISPATCH_CEILING=0 "$PRISTINE" --once >/dev/null 2>&1
  [ -f "$C/wave.json" ] || false
  [ "$(spawns)" -eq 2 ]
}

@test "S2 POSITIVE CONTROL: this harness DOES observe wave-plan calls, spawns, claims and pages when the condition is reversed" {
  fresh; CC_DISPATCH_CEILING=3 "$DISP" --once >/dev/null 2>&1
  [ -f "$C/wave.json" ] || false
  [ "$(spawns)" -eq 2 ] || false
  grep -q '^claim i1$' "$C/backlog.log" || false
  # and the page channel is observable too (a genuine cliff still pages, unchanged)
  fresh; STUB_WP_RC=4 CC_DISPATCH_CEILING=3 "$DISP" --once >/dev/null 2>&1
  [ -f "$C/pages/cc-dispatch-quota-cliff.page" ] || false
  grep -q '"action":"abstained"' "$C/idl.jsonl"
}

@test "S2: admission is driven by the LIVE worker count, not by a constant (live 5 vs ceiling 6 ⇒ 1 admit; live 6 ⇒ 0)" {
  fresh; STUB_LIVE=5 CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .verdict=="admit"')" -eq 1 ] || false
  [ "$(jq -rs '[.[]|select(.verdict=="admit")|.live_workers]|first' "$C/idl.jsonl")" = 5 ] || false
  [ "$(spawns)" -eq 1 ] || false

  fresh; STUB_LIVE=6 CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .verdict=="admit"')" -eq 0 ] || false
  [ "$(spawns)" -eq 0 ] || false

  # RED: the pre-change tree never reads a live-worker count, so both cases fire MAX_SPAWN=2 — this
  # is the unbounded 2/tick that exhausted the fleet's quota and then paged about its own wall.
  fresh; STUB_LIVE=6 CC_DISPATCH_CEILING=6 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 2 ]
}

# ── S2 — the ceiling source: unknown is a third state ─────────────────────────────────────────────
@test "S2: an unparseable ledger is UNKNOWN → at most 1 admit, live_workers:null, reason live-count-unknown, and NO page" {
  seed_items 5
  fresh; STUB_LIVE=x CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  [ "$(dec)" -eq 5 ] || false
  [ "$(dec ' and .verdict=="admit"')" -eq 1 ] || false
  [ "$(dec ' and .reason=="live-count-unknown"')" -eq 1 ] || false
  [ "$(dec ' and .live_workers==null')" -eq 5 ] || false   # unknown is null, never 0
  [ ! -d "$C/pages" ] || false                             # unknown NEVER pages (control: test 3)
  ! grep -q '"action":"abstained"' "$C/idl.jsonl" || false

  # an unreadable ledger is the same third state, not a cliff
  fresh; STUB_LIST_ALL_RC=7 CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .reason=="live-count-unknown"')" -eq 1 ] || false
  [ ! -d "$C/pages" ] || false

  # RED: pre-change there is no oracle to be unknown ABOUT — it just fires the slice.
  fresh; STUB_LIVE=x CC_DISPATCH_CEILING=6 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(dec ' and .reason=="live-count-unknown"')" -eq 0 ] || false
  [ "$(spawns)" -eq 2 ]
}

@test "A14: the ceiling counts CLAIMED items — never a live-SESSION count (regression guard)" {
  # The signal this rebuild corrected. An earlier revision summed `claude-accounts --json .rows[].k`
  # (every live session: leads, desk panes, teammates, sibling rebuilds). Measured live that was 12
  # against a claimed count of 0, so CEILING=6 gave free_slots=0 PERMANENTLY — a dispatcher that
  # admits nothing, forever, and SILENTLY (deferrals never page). This test exists so that cannot
  # come back. See AUTONOMY_DISPATCH_V2 §3 S2 + F16.
  seed_items 5

  # 2 claimed ⇒ free_slots = 5-2 = 3 admitted, and live_workers is recorded as the claimed count.
  fresh; STUB_LIVE=2 CC_DISPATCH_CEILING=5 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .verdict=="admit"')" -eq 3 ] || false
  [ "$(jq -rs '[.[]|select(.verdict=="admit")|.live_workers]|first' "$C/idl.jsonl")" = 2 ] || false

  # POSITIVE CONTROL: the ceiling really does bind — one more claim admits one fewer.
  fresh; STUB_LIVE=3 CC_DISPATCH_CEILING=5 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .verdict=="admit"')" -eq 2 ] || false

  # cc-dispatch must not consult an account/session oracle for the ceiling at all: with NO accounts
  # binary reachable anywhere on PATH, admission still works. Under the old signal this hung or
  # degraded to the unknown path.
  fresh; PATH=/usr/bin:/bin STUB_LIVE=2 CC_DISPATCH_CEILING=5 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .verdict=="admit"')" -eq 3 ] || false
  [ "$(dec ' and .reason=="live-count-unknown"')" -eq 0 ] || false

  # and the source is the ledger, structurally — no .rows[].k in any EXECUTABLE line. Comments may
  # (and do) name the rejected signal to explain why it is rejected; a doc reference is not a call.
  run bash -c "grep -vE '^[[:space:]]*#' '$REPO/bin/cc-dispatch' | grep -c 'rows\[\]' || true"
  [ "$output" -eq 0 ]
}

# ── S6 — singleton, skip-not-queue ────────────────────────────────────────────────────────────────
@test "S6/A9: two concurrent passes → exactly ONE journal pass; the loser records pass-in-flight and exits 0" {
  fresh
  STUB_LIST_SLEEP=3 CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1 &
  local first=$!
  sleep 1                                    # the first pass now holds the lock and is mid-pull
  run env CC_DISPATCH_CEILING=6 "$DISP" --once
  [ "$status" -eq 0 ] || false               # a skip is a normal outcome, never an error
  grep -q '"reason":"pass-in-flight"' "$C/idl.jsonl" || false
  wait "$first"
  [ "$(jq -rs '[.[]|select(.action=="decision")|.pass]|unique|length' "$C/idl.jsonl")" -eq 1 ] || false
  [ "$(dec)" -eq 3 ] || false                # exactly one pass's worth of decisions
  [ ! -d "$C/dispatch.lock" ] || false       # released on exit, never leaked

  # RED: the pre-change tree has no lock, so both passes run and BOTH claim the same items.
  fresh
  STUB_LIST_SLEEP=3 "$PRISTINE" --once >/dev/null 2>&1 &
  first=$!
  sleep 1
  "$PRISTINE" --once >/dev/null 2>&1
  wait "$first"
  ! grep -q '"reason":"pass-in-flight"' "$C/idl.jsonl" || false
  [ "$(grep -c '^claim i1$' "$C/backlog.log")" -eq 2 ]   # the double-claim S6 exists to prevent
}

@test "S6: a holder whose pid matches but whose lstart does not (a RECYCLED pid) is STALE — the lock is broken, not honoured forever" {
  fresh
  sleep 30 & local holder=$!
  mkdir -p "$C/dispatch.lock"
  # kill -0 on this pid SUCCEEDS; only the lstart mismatch reveals it is not the recorded process.
  printf '%s|%s\n' "$holder" 'Mon Jan  1 00:00:00 2001' > "$C/dispatch.lock/owner"
  CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  [ "$(dec)" -eq 3 ] || false
  [ "$(spawns)" -eq 2 ] || false
  ! grep -q '"reason":"pass-in-flight"' "$C/idl.jsonl" || false

  # and the live-holder case is the positive control for that same read
  fresh
  mkdir -p "$C/dispatch.lock"
  printf '%s|%s\n' "$holder" "$(ps -o lstart= -p "$holder" 2>/dev/null)" > "$C/dispatch.lock/owner"
  CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  grep -q '"reason":"pass-in-flight"' "$C/idl.jsonl" || false
  [ "$(spawns)" -eq 0 ] || false
  kill "$holder" 2>/dev/null || true
  wait "$holder" 2>/dev/null || true
  [ "$(dec)" -eq 0 ]
}

# ── S7 — fair ordering, no head-of-line block ─────────────────────────────────────────────────────
@test "S7/F10: a repeatedly-failing head item SINKS — the one slot goes to the item behind it (control: no history ⇒ the head keeps it)" {
  seed_items 2
  fresh
  printf '%s\n' '{"actor":"cc-dispatch","action":"failed","detail":"i1: spawn non-zero (reopened)"}' \
                '{"actor":"cc-dispatch","action":"failed","detail":"i1: claim failed"}' >> "$C/idl.jsonl"
  CC_DISPATCH_CEILING=1 "$DISP" --once >/dev/null 2>&1
  [ "$(jq -rs '[.[]|select(.action=="decision" and .id=="i1")|.verdict]|first' "$C/idl.jsonl")" = defer ] || false
  [ "$(jq -rs '[.[]|select(.action=="decision" and .id=="i2")|.verdict]|first' "$C/idl.jsonl")" = admit ] || false
  [ "$(jq -r '.[0].id' "$C/wave.json")" = i2 ] || false

  # POSITIVE CONTROL: with no thrash history the order is unchanged — the demotion is caused by the
  # history, not by the sort merely shuffling the queue.
  fresh; CC_DISPATCH_CEILING=1 "$DISP" --once >/dev/null 2>&1
  [ "$(jq -r '.[0].id' "$C/wave.json")" = i1 ] || false

  # RED: the pre-change slice is positional only, so the thrashing head item keeps the slot forever.
  fresh
  printf '%s\n' '{"actor":"cc-dispatch","action":"failed","detail":"i1: spawn non-zero (reopened)"}' \
                '{"actor":"cc-dispatch","action":"failed","detail":"i1: claim failed"}' >> "$C/idl.jsonl"
  CC_DISPATCH_MAX_SPAWN=1 "$PRISTINE" --once >/dev/null 2>&1
  [ "$(jq -r '.[0].id' "$C/wave.json")" = i1 ]
}

# ── kill switches ─────────────────────────────────────────────────────────────────────────────────
@test "kill switch CC_DISPATCH_LANE=v1: byte-for-byte behavioural parity with the pristine tree (same wave, same spawns, no journal)" {
  seed_items 5
  fresh; CC_DISPATCH_LANE=v1 CC_DISPATCH_CEILING=0 CC_DISPATCH_MAX_SPAWN=2 "$DISP" --once >/dev/null 2>&1
  local v1_wave v1_spawns
  v1_wave="$(cat "$C/wave.json")"; v1_spawns="$(spawns)"
  [ "$(dec)" -eq 0 ] || false                        # no decision journal in the v1 lane

  fresh; CC_DISPATCH_MAX_SPAWN=2 "$PRISTINE" --once >/dev/null 2>&1
  [ "$v1_wave" = "$(cat "$C/wave.json")" ] || false  # the incumbent slice, verbatim
  [ "$v1_spawns" = "$(spawns)" ] || false
  [ "$v1_spawns" -eq 2 ]
}

@test "kill switch --decide / CC_DISPATCH_DECIDE_ONLY: decisions journalled, ZERO claims / spawns / pages / wave-plan calls" {
  fresh; CC_DISPATCH_CEILING=6 "$DISP" --decide >/dev/null 2>&1
  [ "$(dec)" -eq 3 ] || false
  [ "$(dec ' and .verdict=="admit"')" -eq 3 ] || false   # admitted on paper, actuated not at all
  [ ! -f "$C/wave.json" ] || false
  [ ! -s "$C/backlog.log" ] || false
  [ "$(spawns)" -eq 0 ] || false
  [ ! -d "$C/pages" ] || false

  fresh; CC_DISPATCH_DECIDE_ONLY=on CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  [ "$(dec)" -eq 3 ] || false
  [ "$(spawns)" -eq 0 ] || false

  # --dry-run outranks decide in BOTH argument orders (precedence by blast radius, not by position)
  fresh; "$DISP" --decide --dry-run >/dev/null 2>&1
  [ ! -s "$C/idl.jsonl" ] || false
  fresh; "$DISP" --dry-run --decide >/dev/null 2>&1
  [ ! -s "$C/idl.jsonl" ] || false

  # RED: pre-change, --decide is not a flag at all (exit 3) and the env switch fires anyway.
  fresh; run "$PRISTINE" --decide
  [ "$status" -eq 3 ] || false
  fresh; CC_DISPATCH_DECIDE_ONLY=on "$PRISTINE" --once >/dev/null 2>&1
  [ "$(spawns)" -eq 2 ]
}

@test "config-fail is LOUD for every new switch (a garbage ceiling must never read as 0 or as unlimited)" {
  run env CC_DISPATCH_CEILING=abc "$DISP" --once
  [ "$status" -eq 3 ] || false
  run env CC_DISPATCH_LANE=v3 "$DISP" --once
  [ "$status" -eq 3 ] || false
  # and a LOUD failure never actuates
  [ "$(spawns)" -eq 0 ]
}

# ── A12 — the pre-existing ledger invariants survive the redesign ─────────────────────────────────
@test "A12: the done-latch (wasDone) and the blocked-exclusion still hold UNDER v2 admission" {
  # a done-latched item is decided (verdict skip) but never planned and never claimed…
  jq -cn '[{id:"i1",project:"proj",status:"open",wasDone:true,title:"t",evidence:"6488617 fix(x)"},
           {id:"i2",project:"proj",status:"blocked",title:"t",needs:"operator: do the thing"}]' > "$C/items.json"
  fresh; CC_DISPATCH_CEILING=6 "$DISP" --once >/dev/null 2>&1
  [ "$(dec ' and .id=="i1" and .verdict=="skip"')" -eq 1 ] || false
  [ ! -s "$C/backlog.log" ] || false
  [ "$(spawns)" -eq 0 ] || false
  grep -q '"action":"skipped"' "$C/idl.jsonl" || false
  grep -q '6488617' "$C/idl.jsonl" || false
  # …and a blocked item is NOT decided at all: it is parked OUT of the wave by contract.
  [ "$(dec ' and .id=="i2"')" -eq 0 ] || false
  [ "$(dec)" -eq 1 ]
}

@test "A12: the in-script selftest still RED-proves every branch (106 checks, zero FAIL)" {
  run "$DISP" selftest
  [ "$status" -eq 0 ] || false
  [ "$(printf '%s' "$output" | grep -c '^  ok ')" -eq 106 ] || false
  ! printf '%s' "$output" | grep -q '^  FAIL'
}
