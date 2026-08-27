#!/usr/bin/env bats
# cloud-inbox — the cloud lane's RETURN channel.
#
# WHAT THIS SUITE IS FOR. The lane was one-way: 222 of 262 live sessions (85%) had ended a turn with
# `post_turn_summary.status_category == "need_input"` — a question — and a tree-wide grep for that
# field returned one hit, a comment. This suite pins the three properties that keep the channel
# honest, each with a case that can FAIL:
#
#   1. a question REACHES a reader, classified by the KIND of answer it wants;
#   2. a probe that cannot be read is `UNREADABLE` with its reason — never a silent drop and never
#      folded into "nothing is blocked" (memory: lookup-miss-is-not-absence);
#   3. NOTHING the remote asked for is ever executed. 13 of the 222 asks parse as runnable shell;
#      running one is remote code execution wearing a helpful shape.
#
# The control plane is stubbed through CC_CLOUD_VERIFY_BIN. Unstubbed, every case would reach the
# operator's real accounts over the network and assert against a fleet nothing here can pin.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  INBOX="$REPO/scripts/cloud-inbox.py"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/state" "$C/stubs" "$C/home"
  # HERMETIC $HOME. CC_CLOUD_STATE below already aims the enumerator at the fixture, but the
  # subject's DEFAULT is `~/.claude/autonomy/cloud`, so an unfixtured $HOME leaves the suite one
  # deleted export away from enumerating the operator's live fleet — and a suite that can read live
  # state has no pinnable population at all. Fixture the ambient thing, never just the override.
  export HOME="$C/home"
  export CC_CLOUD_STATE="$C/state"

  # The stub speaks EXACTLY the projection cloud-create-api.py --verify emits. If that projection
  # changes shape, this stub keeps passing while the real thing breaks — so case 6 pins the two
  # together by grepping the real emitter for the keys this stub returns.
  cat > "$C/stubs/verify" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
sid = sys.argv[sys.argv.index("--verify") + 1]
fx = os.path.join(os.environ["STUB_FIXTURES"], sid + ".json")
if not os.path.exists(fx):
    sys.stderr.write("stub: no fixture for %s\n" % sid)
    sys.exit(9)                      # a probe that fails, so UNREADABLE has a real producer
body = open(fx).read()
if body.strip() == "GARBAGE":
    sys.stdout.write("not json at all\n")
    sys.exit(0)                      # rc 0 with unparseable stdout — the nastier failure
sys.stdout.write(body)
sys.exit(0)
EOF
  chmod +x "$C/stubs/verify"
  export CC_CLOUD_VERIFY_BIN="$C/stubs/verify" STUB_FIXTURES="$C/fx"
  mkdir -p "$C/fx"
}

# decl <id> <item> — a declaration the enumerator will pick up.
decl() {
  printf 'id=%s\nitem=%s\naccount=next3\nbranch=claude/fire-x\nurl=https://claude.ai/code/%s\n' \
    "$1" "$2" "$1" > "$C/state/$1.decl"
}
# fx <id> <category> <detail> <needs_action> [requires_action_json]
fx() {
  python3 - "$C/fx/$1.json" "$2" "$3" "$4" "${5:-[]}" <<'EOF'
import json, sys
p, cat, detail, action, req = sys.argv[1:6]
json.dump({"id": "x", "accepted": True, "status_bucket": "blocked", "worker_status": "idle",
           "summary": {"status_category": cat, "status_detail": detail, "needs_action": action},
           "requires_action": json.loads(req)}, open(p, "w"))
EOF
}
run_inbox() { run python3 "$INBOX" "$@"; }

@test "1 a need_input session's QUESTION reaches the reader — detail and ask both surface" {
  decl session_A 289f2f73093c
  fx session_A need_input "item resolved on trunk; awaiting backlog close" "close the item please"
  run_inbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"session_A"* ]] || false
  [[ "$output" == *"item=289f2f73093c"* ]] || false
  [[ "$output" == *"awaiting backlog close"* ]] || false
  [[ "$output" == *"close the item please"* ]]
}

@test "2 the ask is classified by the KIND of answer it wants — RUNNABLE vs PROSE vs PERMISSION" {
  decl session_R r1; fx session_R need_input d "cc-backlog done r1 --evidence abc"
  decl session_P p1; fx session_P need_input d "please re-dispatch this somewhere local"
  decl session_M m1; fx session_M need_input "Waiting on permission: Bash" "Approve or deny Bash" \
      '[{"tool_name":"Bash","raw_command":"rm -rf /tmp/x"}]'
  run_inbox
  [ "$status" -eq 0 ]
  [[ "$output" =~ RUNNABLE[[:space:]]+session_R ]] || false
  [[ "$output" =~ PROSE[[:space:]]+session_P ]] || false
  [[ "$output" =~ PERMISSION[[:space:]]+session_M ]] || false
  # POSITIVE CONTROL for the classifier: the three labels are genuinely distinct, so a matcher that
  # collapsed them would fail here rather than pass three ways.
  [ "$(printf '%s\n' "$output" | grep -c '^RUNNABLE')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^PROSE')" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c '^PERMISSION')" -eq 1 ]
}

@test "3 NOTHING the remote asked for is executed — the reader is not an actuator" {
  decl session_X x1
  # The ask is a command that would leave an unmistakable trace if it ever ran.
  fx session_X need_input d "cc-backlog done x1 && touch $C/EXECUTED"
  run_inbox
  [ "$status" -eq 0 ]
  [[ "$output" == *"session_X"* ]] || false # it was READ…
  [ ! -e "$C/EXECUTED" ]                  # …and NOT run
  # CONTROL: the marker path is writable, so its absence is evidence and not a broken assertion.
  touch "$C/EXECUTED"; [ -e "$C/EXECUTED" ]; rm -f "$C/EXECUTED"
}

@test "4 a probe that FAILS is UNREADABLE with its reason — never a silent drop, never 'clear'" {
  decl session_MISSING m1            # no fixture ⇒ the stub exits 9
  decl session_GARBAGE g1; printf 'GARBAGE' > "$C/fx/session_GARBAGE.json"   # rc 0, junk stdout
  decl session_OK o1; fx session_OK need_input d "an ask"
  run_inbox
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '^UNREADABLE')" -eq 2 ]
  [[ "$output" == *"session_MISSING"* ]] || false
  [[ "$output" == *"session_GARBAGE"* ]] || false
  [[ "$output" == *"session_OK"* ]] || false
  # rc 0 with unparseable stdout is the trap this pins: a reader that only checked the exit code
  # would report session_GARBAGE as read-and-clear.
  [[ "$output" =~ UNREADABLE[[:space:]]+session_GARBAGE ]]
}

@test "5 a retired declaration is not probed, and a --limit says what it did NOT read" {
  decl session_LIVE l1; fx session_LIVE need_input d "ask"
  decl session_GONE g1; fx session_GONE need_input d "ask"
  : > "$C/state/session_GONE.retired"
  run_inbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"session_GONE"* ]] || false
  [[ "$output" == *"probed 1 of 1 active session(s)"* ]] || false

  # …and the bound is ANNOUNCED. A truncated sweep printing like a complete one reads as all-clear.
  decl session_B b1; fx session_B need_input d "ask"
  decl session_C c1; fx session_C need_input d "ask"
  run_inbox --limit 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"the rest were NOT read and are not reported as clear"* ]] || false
  [[ "$output" == *"probed 1 of 3 active session(s)"* ]]
}

@test "6 the stub speaks the SAME projection the real emitter does (the two cannot drift apart)" {
  # Without this, the suite pins a shape only the stub has. Every key the stub returns must be a key
  # cloud-create-api.py --verify actually emits.
  for k in summary status_category status_detail needs_action requires_action; do
    grep -q "\"$k\"" "$REPO/scripts/cloud-create-api.py" || {
      echo "cloud-create-api.py --verify no longer emits '$k' — this suite is testing a fiction" >&2
      false
    }
  done
}

@test "7 an unmodelled control-plane category is reported under its OWN name, never bucketed" {
  decl session_N n1; fx session_N some_future_state "a state we do not model" "an ask"
  run_inbox --all
  [ "$status" -eq 0 ]
  [[ "$output" == *"cat=some_future_state"* ]] || false
  # …and it is NOT in the default (blocked-only) view, so a new upstream state cannot silently
  # inflate the blocked count either.
  run_inbox
  [ "$status" -eq 0 ]
  [[ "$output" != *"some_future_state"* ]]
}

# ── THE WRITER: `<id>.turn`, the work evidence cc-cloud's C7 arm reads ────────────────────────────
# Printing the question fixed the CHANNEL and not the BOARD. `cc-cloud classify()` is the arbiter
# cc-offload, cc-backlog's reap, custody-deathwatch and cloud-return all ask, and its "never
# started" rung derived that verdict from git-ref absence alone — so the same 222 sessions that
# reach a human here were still filed NOT-STARTED everywhere a machine looked, and the reap maps
# that to "return it to the wave": a second peer fired at work whose only remaining need is an
# answer. These five pin the evidence this pass leaves behind, and case 12 pins the two halves
# together through the real files rather than through a shared belief about the format.

# turnfield <id> <key> → the value, or '' — read the way cc-cloud's dfield reads it.
turnfield() { sed -n "s/^$2=//p" "$C/state/$1.turn" 2>/dev/null | head -1; }

@test "8 a session that TOOK A TURN leaves the evidence cc-cloud reads, with the waiting verdict" {
  decl session_T t1; fx session_T need_input "gate issues block ship" "cc-backlog done t1"
  run_inbox --now 1900000000
  [ "$status" -eq 0 ]
  [ -f "$C/state/session_T.turn" ]
  [ "$(turnfield session_T at)" = "1900000000" ]
  [ "$(turnfield session_T cat)" = "need_input" ]
  [ "$(turnfield session_T worker)" = "idle" ]
  # THE VERDICT IS MADE HERE, ONCE, because this is the only party holding the whole record.
  [ "$(turnfield session_T waiting)" = "1" ]
  # The tally must distinguish a pass that stamped from one that did not — the arm on the far side
  # can only ever fire on evidence this pass wrote.
  [[ "$output" == *"turn evidence — stamped 1"* ]]
}

@test "9 a 200 that is NOT a turn is NEVER stamped — C1 stays right about a never-started session" {
  # THE ONE WAY THIS CHANGE COULD MAKE THE BOARD WORSE. A session that never booted also returns 200
  # with accepted:true; stamping every readable probe would refute NOT-STARTED for exactly the
  # sessions NOT-STARTED is correct about. The predicate is a `post_turn_summary` (or an outstanding
  # permission request), never a successful GET.
  decl session_Q q1
  printf '{"id":"x","accepted":true,"status_bucket":"queued","worker_status":"idle"}' > "$C/fx/session_Q.json"
  run_inbox --all --now 1900000000
  [ "$status" -eq 0 ]
  [ ! -f "$C/state/session_Q.turn" ]
  [[ "$output" == *"turn evidence — no-turn 1"* ]] || false

  # POSITIVE CONTROL: a permission request with NO status_category at all IS a turn, and it is
  # waiting on us — the case a category test alone would miss, which is why `waiting` is decided
  # from the whole record rather than from the category that survives into the sidecar.
  decl session_P p1
  printf '{"id":"x","accepted":true,"worker_status":"idle","requires_action":["approve write"]}' > "$C/fx/session_P.json"
  run_inbox --id session_P --now 1900000000
  [ -f "$C/state/session_P.turn" ]
  [ "$(turnfield session_P waiting)" = "1" ]
  [ "$(turnfield session_P cat)" = "" ]
}

@test "10 a value the REMOTE composed cannot forge a field in the store the arbiter trusts" {
  # The sidecar is `key=value`, one line per field. `status_category` is remote-authored, so a
  # newline in it would write `waiting=1` into a session that is not waiting — the arbiter reading
  # an attacker-chosen verdict out of its own state dir. Shape allowlist, never a scrub of spellings.
  decl session_X x1
  python3 - "$C/fx/session_X.json" <<'PY'
import json, sys
json.dump({"id": "x", "accepted": True, "worker_status": "idle",
           "summary": {"status_category": "need_input\nwaiting=1\nat=9999999999",
                       "status_detail": "d", "needs_action": "a"}}, open(sys.argv[1], "w"))
PY
  run_inbox --all --now 1900000000
  [ "$status" -eq 0 ]
  [ "$(turnfield session_X cat)" = "unmodelled" ]
  [ "$(turnfield session_X at)" = "1900000000" ]
  # The forged line never reached the file at all — not merely overridden by ordering.
  [ "$(grep -c . "$C/state/session_X.turn")" -eq 4 ]
  # …and the injected category is NOT read as blocking, so the forgery buys nothing either way.
  [ "$(turnfield session_X waiting)" = "0" ]
}

@test "11 --no-stamp reports without writing, and --id probes exactly one declaration" {
  decl session_1 i1; fx session_1 need_input d "ask"
  decl session_2 i2; fx session_2 need_input d "ask"

  run_inbox --no-stamp
  [ "$status" -eq 0 ]
  [ ! -f "$C/state/session_1.turn" ]
  [ ! -f "$C/state/session_2.turn" ]
  [[ "$output" == *"turn evidence — off 2"* ]] || false

  run_inbox --id session_2 --now 1900000000
  [ "$status" -eq 0 ]
  [ -f "$C/state/session_2.turn" ]
  [ ! -f "$C/state/session_1.turn" ]
  # `--id` defines the population the way `--item` does: the filter is applied before the tally, so
  # the pass reports what it was ASKED to read, not a fraction of the whole store.
  [[ "$output" == *"probed 1 of 1 active session(s)"* ]]
}

@test "12 END TO END: one inbox pass flips the REAL cc-cloud board off NOT-STARTED" {
  # The two halves meet through the files, not through a shared belief about the format. Either
  # side alone can be green while the lane stays broken: this is the only case that fails if the
  # writer's key names, its epoch, or its freshness guard drift from what the arbiter reads.
  CLOUD="$REPO/bin/cc-cloud"
  [ -x "$CLOUD" ]
  git init -q --bare "$C/rem.git"
  export CC_CLOUD_NOW=2000000000
  # `--account` is not decoration: a session id is not a globally-addressable handle, so a
  # declaration without one is `unreadable` at the probe and nothing is ever stamped.
  "$CLOUD" declare --id e2e --branch feat/a --remote "$C/rem.git" --repo "" --boot 900 \
    --account next3 >/dev/null
  fx e2e need_input "fix verified & tests green; gate issues block ship" "cc-backlog done b60eb29e97dd"

  # CONTROL: the exact verdict 151 live declarations were sitting on, off this exact fixture.
  export CC_CLOUD_NOW=$((2000000000 + 5000))
  [ "$("$CLOUD" --table | awk '$1=="e2e"{print $2}')" = "NOT-STARTED" ]

  run_inbox --now $((2000000000 + 100))
  [ "$status" -eq 0 ]
  [ "$("$CLOUD" --table | awk '$1=="e2e"{print $2}')" = "NEEDS-INPUT" ]
  # And it reaches the ROW consumers, pointing at the reader rather than at a browser.
  [ "$("$CLOUD" --json | grep -c '"state":"NEEDS-INPUT"')" -eq 1 ]
  [[ "$("$CLOUD" --json)" == *'"recover_cmd":"cc-cloud inbox --id e2e"'* ]]
}
