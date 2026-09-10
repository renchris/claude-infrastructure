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

# ── --record: the ephemeral read becomes evidence `cc-cloud classify()` can consult ──────────────
# classify() is disk + ls-remote by contract, so it cannot ask the control plane whether a session
# ever ran — and its C1 arm asserted NOT-STARTED from ref-absence alone, which a session that
# booted, ran and declined produces identically to one that never existed. `--record` writes the
# answer down as a durable `<id>.cp` sidecar, under the same three laws the `.seen` sidecar obeys:
# positive-only, never on a non-read, never deleted.

@test "8 --record writes ran=1 for a session that ENDED A TURN, and nothing without the flag" {
  decl s1 item1
  fx s1 need_input "tests green" "cc-backlog done item1"

  # CONTROL: the default is unchanged. --record is a flag precisely so the reader stays a reader,
  # and a case that only asserted the write could not tell the two apart.
  run_inbox --all
  [ "$status" -eq 0 ]
  [ ! -f "$C/state/s1.cp" ]

  run_inbox --all --record
  [ "$status" -eq 0 ]
  [ -f "$C/state/s1.cp" ]
  grep -q '^ran=1$' "$C/state/s1.cp"
  # the fields the sidecar is FOR, carried verbatim from the one projection --verify emits
  grep -q '^status_category=need_input$' "$C/state/s1.cp"
  grep -q '^status_bucket=blocked$' "$C/state/s1.cp"
  grep -qE '^probed_at=[0-9]+$' "$C/state/s1.cp"
  # the tally names what it wrote — a silent side effect is not auditable
  printf '%s' "$output" | grep -q 'recorded 1 .cp sidecar'
}

@test "9 an UNREADABLE probe writes NO sidecar — a failed instrument never manufactures evidence" {
  decl good item1
  fx good need_input "done" "cc-backlog done item1"
  decl missing item2          # no fixture ⇒ the stub exits 9 ⇒ UNREADABLE

  run_inbox --all --record
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'UNREADABLE  missing'

  # POSITIVE CONTROL in the same run: the readable sibling DID get one, so this is a discriminating
  # absence rather than a --record that quietly did nothing at all.
  [ -f "$C/state/good.cp" ]
  [ ! -f "$C/state/missing.cp" ]
  # …and no half-written temp is left behind for classify() to read as a truncated store.
  [ ! -f "$C/state/missing.cp.tmp" ]
}

@test "10 a session with NOTHING to ask still records ran=1 — the evidence is the TURN, not the ask" {
  decl quiet item3
  # An empty category is what a record with no post_turn_summary yields. A session that has taken no
  # turn cannot carry the claim, and `ran=` must be ABSENT rather than 0 — absence is what
  # classify() already reads as "no evidence".
  fx quiet "" "" ""
  run_inbox --all --record
  [ "$status" -eq 0 ]
  [ -f "$C/state/quiet.cp" ]
  run grep -q '^ran=' "$C/state/quiet.cp"
  [ "$status" -ne 0 ]

  # POSITIVE CONTROL: the same session once it HAS ended a turn, with nothing to ask of us. It is
  # not in the blocked view at all, and it must still be recorded — recording only what gets
  # PRINTED would make durable evidence a function of a display flag.
  fx quiet completed "shipped it" ""
  run_inbox --record
  [ "$status" -eq 0 ]
  grep -q '^ran=1$' "$C/state/quiet.cp"
  grep -q '^status_category=completed$' "$C/state/quiet.cp"
}

@test "11 --id addresses ONE session by id — the key --item cannot express" {
  decl a1 shared
  decl a2 ""                 # many declarations carry no item= at all
  fx a1 need_input "one" "ask one"
  fx a2 need_input "two" "ask two"

  run_inbox --all --id a2 --record
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$C/out.txt"
  grep -q 'a2' "$C/out.txt"
  run grep -q 'a1' "$C/out.txt"
  [ "$status" -ne 0 ]
  # the scope is real, not cosmetic: the unselected session was never probed, so it has no sidecar
  [ -f "$C/state/a2.cp" ]
  [ ! -f "$C/state/a1.cp" ]
}
