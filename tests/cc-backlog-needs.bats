#!/usr/bin/env bats
# cc-backlog `needs` — the ONE-LINE front door to a BLOCKED-ON-OPERATOR item.
#
#   cc-backlog needs "<operator-only step>" [--run "<cmd>"] [--project P] [--session SID]
#
# It exists because the two-command path (`add` then `block`) is what made an agent PROSE an
# operator-only step at session close instead of filing it — and a step that lives nowhere on disk
# cannot be rendered by hooks/operator-readout.sh, which builds the close block BY CONSTRUCTION
# from disk truth. So the step gets buried in prose and missed.
#
# What this suite pins, beyond "it works":
#   · the two NEW record fields (`run`, `session`) SURVIVE THE FOLD. bin/cc-backlog's fold
#     WHITELISTS field names — anything unnamed there is dropped silently between the JSONL and
#     `list --blocked --json`. That silent drop is the single likeliest way to ship this broken,
#     so tests 2/3/5 are its regression pins (5 is the negative control: verified RED with the
#     bin/cc-backlog edit stashed — see § NEGATIVE CONTROL below).
#   · ABSENT vs empty-string when the flags are omitted, so a renderer can tell "no command" from
#     "an empty command" (an empty `run` in cc-do would be a blank line the operator is told to run).
#   · NO dispatch_kick. `add` kicks the dispatcher; a `needs` item is born `blocked`, i.e. outside
#     the wave by construction, so a kick is pure waste AND risks spawning a worker onto a step no
#     worker can perform. Asserted against the kick MARKER, with an `add` in the same test as the
#     positive control — otherwise "no marker" would also pass on a tree where kicking is broken.

setup() {
  # Project labels in this suite are FIXTURES, not projects — and `cc-backlog add` now WARNS on an
  # explicit --project outside the dispatch set (df2b6a40a5dc), which bats folds into $output. Off
  # here because dispatchability is not this suite's subject; tests/cc-backlog-project-dispatch.bats
  # owns it, unfixtured, in both directions.
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermeticity rule 1
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  # The kick default writes its marker under $HOME and spawns the LIVE cc-dispatch. Both are
  # fixtured here, not merely switched off: the no-kick test below has to turn the mechanism back
  # ON to get its positive control, and it must still not touch the operator's state when it does.
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
  # `session` falls back to the ambient env. Unset in setup() (never per-test) so a test asserting
  # ABSENCE cannot pass or fail on whether the operator's own shell happened to export one.
  # CLAUDE_CODE_SESSION_ID joined this list with the ladder rung that reads it: it is the ONE of the
  # three a Claude tool-call shell actually has, so leaving it ambient would make every absence
  # assertion below pass under CI and fail when the suite is run from a session — the same trap
  # tests/cc-decide.bats:17 and tests/completion-assert.bats:23 unset for.
  unset CLAUDE_SESSION_ID CLAUDE_CODE_SESSION_ID CC_SESSION_ID
  P=/repo/needs-suite
}

# the folded item for <id> from `list --blocked --json`, or "" when it is not blocked
blocked_json() { bash "$CB" list --blocked --json | jq -c --arg i "$1" 'map(select(.id==$i)) | first // empty'; }

@test "needs files a BLOCKED item in one command; list --blocked shows it with its needs prose" {
  run bash "$CB" needs "authenticate motion-plus in /mcp" --project "$P"
  [ "$status" -eq 0 ]
  id="$output"
  [[ "$id" =~ ^[0-9a-f]{12}$ ]] || false
  run bash "$CB" list --blocked
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "$id"
  # the positional step is BOTH the title and the needs prose — the table renders it as needs
  echo "$output" | grep -q '⟵ needs: authenticate motion-plus in /mcp'
  # …and the status really is blocked, i.e. cc-dispatch's status=="open" filter excludes it
  [ "$(blocked_json "$id" | jq -r '.status')" = blocked ]
  [ "$(blocked_json "$id" | jq -r '.title')" = "authenticate motion-plus in /mcp" ]
  [ "$(blocked_json "$id" | jq -r '.source')" = needs ]
}

@test "needs appends exactly the SAME records the add→block path would (no third writer)" {
  id=$(bash "$CB" needs "restart Cursor" --project "$P")
  # add → block → link. The third record is the operator-gate keying (2026-08-15, O3 of
  # MASTER_OPERATOR_GATED.md); it is written by cmd_link on the `block` transition, which is why it
  # is still not a third WRITER — the assertion below proves that by producing the identical trail
  # from the two-command path.
  [ "$(jq -rs 'length' "$CC_BACKLOG_FILE")" = 3 ]
  [ "$(jq -rs '.[0].event' "$CC_BACKLOG_FILE")" = add ]
  [ "$(jq -rs '.[0].id'    "$CC_BACKLOG_FILE")" = "$id" ]
  [ "$(jq -rs '.[0].title' "$CC_BACKLOG_FILE")" = "restart Cursor" ]
  [ "$(jq -rs '.[1].event' "$CC_BACKLOG_FILE")" = block ]
  [ "$(jq -rs '.[1].id'    "$CC_BACKLOG_FILE")" = "$id" ]
  [ "$(jq -rs '.[1].needs' "$CC_BACKLOG_FILE")" = "restart Cursor" ]
  [ "$(jq -rs '.[2].event'     "$CC_BACKLOG_FILE")" = link ]
  [ "$(jq -rs '.[2].id'        "$CC_BACKLOG_FILE")" = "$id" ]
  [ "$(jq -rs '.[2].condition' "$CC_BACKLOG_FILE")" = master-operator-gated ]

  # THE COMPOSITION ITSELF, asserted rather than described: drive the two-command path cc-dispatch
  # prints into every worker brief, in a second store, and require the event sequence to be
  # identical. This is what "no third writer" means — `needs` reaches cmd_add and cmd_transition, it
  # does not hand-roll records, so a future edit to either path cannot make the two diverge silently.
  local two="$BATS_TEST_TMPDIR/two.jsonl"
  CC_BACKLOG_FILE="$two" bash "$CB" add --title "restart Cursor" --source needs --project "$P" >/dev/null
  CC_BACKLOG_FILE="$two" bash "$CB" block "$id" --needs "restart Cursor" >/dev/null
  [ "$(jq -rs '[.[].event] | join(",")' "$two")" = "$(jq -rs '[.[].event] | join(",")' "$CC_BACKLOG_FILE")" ]
  [ "$(jq -rs '[.[].id]    | unique | join(",")' "$two")" = "$id" ]
}

@test "block keys the row into the operator-gated group at FILING time (not by a later sweep)" {
  id=$(bash "$CB" add --title "the launchd dispatcher needs a bootout" --project "$P")
  # An ordinary add is UNGROUPED — the negative control, without which the assertion below would
  # also pass on a store that keys every row it ever sees.
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" '.[]|select(.id==$i)|.condition // ""')" = "" ]
  run bash "$CB" block "$id" --needs "launchctl bootout the dispatcher"
  [ "$status" -eq 0 ]
  [ "$(blocked_json "$id" | jq -r '.condition')" = master-operator-gated ]
}

@test "the keying is NON-FORCE: a row already grouped elsewhere keeps its condition, and says so" {
  id=$(bash "$CB" add --title "re-land the stranded wt-foo patch" --project "$P")
  bash "$CB" link "$id" --condition master-stranded-work >/dev/null
  run bash "$CB" block "$id" --needs "the operator must approve the lossy re-land"
  # The STEP is filed regardless — losing the group costs a place in the rendered batch; failing the
  # transition would lose the operator's step, which is the worse outcome by construction.
  [ "$status" -eq 0 ]
  [ "$(blocked_json "$id" | jq -r '.condition')" = master-stranded-work ]
  [ "$(blocked_json "$id" | jq -r '.needs')" = "the operator must approve the lossy re-land" ]
  # …and the caller is TOLD, in one line, rather than being handed cmd_link's four-line re-key
  # instructions for a move it never asked for.
  echo "$output" | grep -q 'NOT in the "master-operator-gated" batch'
  ! echo "$output" | grep -q 'To re-key deliberately' || false
  # No `force` record was written — O1's demotions have to stick.
  [ "$(jq -rs '[.[] | select(.event=="link" and (.force // false))] | length' "$CC_BACKLOG_FILE")" = 0 ]
}

@test "CC_BACKLOG_OPERATOR_CONDITION=off disables the keying; the block itself is untouched" {
  id=$(bash "$CB" add --title "paste the API key" --project "$P")
  run env CC_BACKLOG_OPERATOR_CONDITION=off bash "$CB" block "$id" --needs "paste the API key"
  [ "$status" -eq 0 ]
  [ "$(blocked_json "$id" | jq -r '.condition // ""')" = "" ]
  [ "$(blocked_json "$id" | jq -r '.needs')" = "paste the API key" ]
  [ "$(jq -rs '[.[] | select(.event=="link")] | length' "$CC_BACKLOG_FILE")" = 0 ]
}

@test "an INVALID operator-condition slug is a no-op, never a refused block (fail-open)" {
  id=$(bash "$CB" add --title "rotate the token" --project "$P")
  # A digit is exactly what valid_condition bans — a measurement is not a state. The arm must fall
  # through silently rather than refuse a transition that is already carrying the operator's step.
  run env CC_BACKLOG_OPERATOR_CONDITION=master-operator-gated-2 bash "$CB" block "$id" --needs "rotate the token"
  [ "$status" -eq 0 ]
  [ "$(blocked_json "$id" | jq -r '.condition // ""')" = "" ]
  [ "$(blocked_json "$id" | jq -r '.needs')" = "rotate the token" ]
}

@test "--run survives the fold to list --blocked --json as .run (fold-whitelist regression)" {
  id=$(bash "$CB" needs "authenticate motion-plus" --run 'claude mcp auth motion-plus' --project "$P")
  [ "$(blocked_json "$id" | jq -r '.run')" = 'claude mcp auth motion-plus' ]
  # …and it is on the BLOCK record, not the add record
  [ "$(jq -rs '.[1].run' "$CC_BACKLOG_FILE")" = 'claude mcp auth motion-plus' ]
}

@test "--session survives the fold to list --blocked --json as .session (fold-whitelist regression)" {
  id=$(bash "$CB" needs "restart Cursor" --session 'sid-abc123' --project "$P")
  [ "$(blocked_json "$id" | jq -r '.session')" = sid-abc123 ]
  [ "$(jq -rs '.[1].session' "$CC_BACKLOG_FILE")" = sid-abc123 ]
}

@test "a run command containing SPACES survives whole (not word-split into flags)" {
  id=$(bash "$CB" needs "re-auth the account" --run 'claude-accounts --relogin next3 --wait 30' --project "$P")
  [ "$(blocked_json "$id" | jq -r '.run')" = 'claude-accounts --relogin next3 --wait 30' ]
}

@test "session resolution order: --session > CLAUDE_SESSION_ID > CLAUDE_CODE_SESSION_ID > CC_SESSION_ID > omitted" {
  # CC_SESSION_ID alone
  id=$(CC_SESSION_ID=from-cc bash "$CB" needs "step cc" --project "$P")
  [ "$(blocked_json "$id" | jq -r '.session')" = from-cc ]
  # CLAUDE_SESSION_ID wins over CC_SESSION_ID
  id=$(CC_SESSION_ID=from-cc CLAUDE_SESSION_ID=from-claude bash "$CB" needs "step claude" --project "$P")
  [ "$(blocked_json "$id" | jq -r '.session')" = from-claude ]
  # an explicit --session beats ALL — a caller filing on another session's behalf can say so
  id=$(CC_SESSION_ID=from-cc CLAUDE_SESSION_ID=from-claude CLAUDE_CODE_SESSION_ID=from-code \
       bash "$CB" needs "step flag" --session from-flag --project "$P")
  [ "$(blocked_json "$id" | jq -r '.session')" = from-flag ]
}

# ══ THE RUNG THAT WAS MISSING ══════════════════════════════════════════════════════════════════
# The contract above used to name only CLAUDE_SESSION_ID and CC_SESSION_ID. Neither is ever set in
# a Claude tool-call shell — the only shell an agent runs `cc-backlog needs` in — and
# CLAUDE_CODE_SESSION_ID, which IS set there, occurred ZERO times in bin/cc-backlog. So every
# unflagged `needs` an agent filed recorded an EMPTY session, and scripts/wrap-ledger.sh:691
# (`select((.session // "") == $sid)`, with :684 returning YOURS=0 on an empty $SID) could match it
# in neither branch: the 👤 rung went uncounted and a close could render ✅ over an operator step.
# Same shape as the ⛔ hole one store over, fixed in b96a513bc. These pin each rung SEPARATELY so a
# green suite credits a specific site (MEMORY.md per-site-mutation-attributes-coverage).

@test "CLAUDE_CODE_SESSION_ID alone resolves — the rung a tool-call shell actually has" {
  # Guards the exact no-op a ladder ending at CLAUDE_SESSION_ID would have been: unset at every
  # real agent call site, so the fix would resolve "" and ship the identical bug, green.
  id=$(CLAUDE_CODE_SESSION_ID=from-code bash "$CB" needs "step from a tool-call shell" --project "$P")
  [ "$(blocked_json "$id" | jq -r '.session')" = from-code ]
}

@test "CLAUDE_SESSION_ID outranks CLAUDE_CODE_SESSION_ID — it stays the FIRST env rung" {
  id=$(CLAUDE_SESSION_ID=from-claude CLAUDE_CODE_SESSION_ID=from-code \
       bash "$CB" needs "first env rung" --project "$P")
  [ "$(blocked_json "$id" | jq -r '.session')" = from-claude ]
}

@test "CLAUDE_CODE_SESSION_ID outranks CC_SESSION_ID — it is the SECOND env rung, not the last" {
  id=$(CLAUDE_CODE_SESSION_ID=from-code CC_SESSION_ID=from-cc \
       bash "$CB" needs "second env rung" --project "$P")
  [ "$(blocked_json "$id" | jq -r '.session')" = from-code ]
}

@test "with NO session variable set the key stays ABSENT — the ladder's fail direction is monotone" {
  # The property that makes this safe to land: unresolvable ⇒ byte-identical to the behaviour
  # replaced, never a wrong attribution. setup() already unset all three.
  id=$(bash "$CB" needs "nothing to resolve" --project "$P")
  blocked_json "$id" | jq -e 'has("session") | not'
  jq -cs '.[1]' "$CC_BACKLOG_FILE" | jq -e 'has("session") | not'
  # POSITIVE CONTROL — the same query DOES see the key when a rung resolves, so "absent" above is a
  # real omission and not a query that can never find anything.
  id2=$(CLAUDE_CODE_SESSION_ID=ctl bash "$CB" needs "something to resolve" --project "$P")
  blocked_json "$id2" | jq -e '.session == "ctl"'
}

@test "the id does NOT depend on the session — a re-file from another session FOLDS onto the row" {
  # Unlike cc-decide's mk_id (class+sid+what), `session` is not an input to cmd_add: it rides only
  # the block record. That is what keeps the event-keyed fold that migrations/README.md:69 and the
  # four unflagged automated callers depend on (deploy-migrations.sh:297, deploy-live.sh:505,
  # deploy-parity-assert.sh:203, custody-deathwatch.sh:355) working across differing environments.
  a=$(CLAUDE_CODE_SESSION_ID=sid-one bash "$CB" needs "converge the live layer" --project "$P")
  b=$(CLAUDE_CODE_SESSION_ID=sid-two bash "$CB" needs "converge the live layer" --project "$P")
  [ "$a" = "$b" ]
  [ "$(bash "$CB" list --blocked --json | jq -r 'length')" = 1 ]
}

@test "omitting --run/--session leaves the keys ABSENT, not empty-string (consumer can tell)" {
  id=$(bash "$CB" needs "operator-only step with no command" --project "$P")
  j="$(blocked_json "$id")"
  # has(), not == "" — an empty `run` handed to cc-do is a blank line the operator is told to paste
  echo "$j" | jq -e 'has("run") | not'
  echo "$j" | jq -e 'has("session") | not'
  # the record itself carries neither
  jq -cs '.[1]' "$CC_BACKLOG_FILE" | jq -e 'has("run") | not'
  jq -cs '.[1]' "$CC_BACKLOG_FILE" | jq -e 'has("session") | not'
  # POSITIVE CONTROL — the same assertion shape DOES see the keys when the flags are passed, so
  # "absent" above is a real omission and not a broken query that can never find anything.
  id2=$(bash "$CB" needs "operator step with a command" --run 'echo hi' --session s1 --project "$P")
  blocked_json "$id2" | jq -e 'has("run") and has("session")'
}

# ── NEGATIVE CONTROL ───────────────────────────────────────────────────────────────────────────
# Verified RED on the pre-change tree: with the bin/cc-backlog edit stashed, `needs` is an unknown
# verb, and with ONLY the fold's `run`/`session` whitelist lines removed (the subtler half of the
# defect — the verb works, the fields vanish silently between the JSONL and the JSON), this test
# fails on the .run/.session assertions while every other blocked-item test in the house suite
# stays green. A test that passes on both branches proves nothing.
@test "NEGATIVE CONTROL: run + session are BOTH present and correct after needs --run --session" {
  id=$(bash "$CB" needs "authenticate motion-plus in /mcp" \
         --run 'claude mcp auth motion-plus' --session 'sid-neg-ctl' --project "$P")
  j="$(blocked_json "$id")"
  [ -n "$j" ]
  echo "$j" | jq -e '.run == "claude mcp auth motion-plus"'
  echo "$j" | jq -e '.session == "sid-neg-ctl"'
  echo "$j" | jq -e '.needs == "authenticate motion-plus in /mcp"'
  echo "$j" | jq -e '.status == "blocked"'
}

@test "needs does NOT fire dispatch_kick, where the same-shaped add DOES" {
  unset CC_BACKLOG_KICK                          # mechanism back ON (marker + bin stay fixtured)
  run bash "$CB" needs "operator: do the thing" --project "$P"
  [ "$status" -eq 0 ]
  sleep 0.4
  # a blocked item is outside the wave by construction ⇒ a kick could only burn a pass, or spawn a
  # worker onto a human-only step
  [ ! -e "$CC_BACKLOG_KICK_MARKER" ]
  # POSITIVE CONTROL — same binary, same env, same tmpdir: `add` stamps the marker. Without this,
  # the assertion above would also pass on a tree where kicking is simply broken.
  run bash "$CB" add --title "ordinary open work" --project "$P"
  [ "$status" -eq 0 ]
  sleep 0.4
  [ -e "$CC_BACKLOG_KICK_MARKER" ]
}

@test "re-running the same needs is idempotent — one item, same id" {
  a=$(bash "$CB" needs "authenticate motion-plus in /mcp" --project "$P")
  b=$(bash "$CB" needs "authenticate motion-plus in /mcp" --project "$P")
  [ "$a" = "$b" ]
  [ "$(bash "$CB" list --blocked --json | jq 'length')" = 1 ]
  [ "$(bash "$CB" list --all --json | jq 'length')" = 1 ]
  # still blocked, still carrying its prose after the second pass
  [ "$(blocked_json "$a" | jq -r '.status')" = blocked ]
  [ "$(blocked_json "$a" | jq -r '.needs')" = "authenticate motion-plus in /mcp" ]
}

@test "--source needs keys a needs item APART from a same-titled ordinary add" {
  a=$(bash "$CB" add   --title "same words" --project "$P")
  b=$(bash "$CB" needs "same words"         --project "$P")
  [ "$a" != "$b" ]
  [ "$(bash "$CB" list --all --json | jq 'length')" = 2 ]
  # the add is dispatchable (open); the needs item is parked (blocked)
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$a" 'map(select(.id==$i))[0].status')" = open ]
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$b" 'map(select(.id==$i))[0].status')" = blocked ]
}

@test "unblock returns a needs item to open (the operator's completion path still works)" {
  id=$(bash "$CB" needs "operator: set the API key" --run 'claude-kimi set-key' --project "$P")
  bash "$CB" unblock "$id" >/dev/null
  [ "$(bash "$CB" list --all --json | jq -r --arg i "$id" 'map(select(.id==$i))[0].status')" = open ]
  [ "$(bash "$CB" list --blocked --json | jq 'length')" = 0 ]
}

# ── refusals (house style: rc 2, loud, name the fix) ───────────────────────────────────────────
@test "needs with NO step text fails loud (rc 2) and writes nothing" {
  run bash "$CB" needs --project "$P"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'required'
  [ ! -s "$CC_BACKLOG_FILE" ] || [ "$(jq -rs 'length' "$CC_BACKLOG_FILE")" = 0 ]
}

@test "needs with an unknown flag fails loud (rc 2)" {
  run bash "$CB" needs "a step" --bogus x --project "$P"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'unknown arg --bogus'
}

@test "needs with a SECOND positional fails loud — an unquoted step is not filed truncated" {
  run bash "$CB" needs "authenticate motion-plus" "in /mcp" --project "$P"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'extra argument'
  [ ! -s "$CC_BACKLOG_FILE" ] || [ "$(jq -rs 'length' "$CC_BACKLOG_FILE")" = 0 ]
}

@test "the needs verb is documented in usage/--help" {
  run bash "$CB" --help
  [ "$status" -eq 0 ]
  # anchored at the VERB column, not a bare 'needs' — the pre-existing `block <id> --needs
  # "<operator-only step>"` line contains both those strings, so an unanchored grep passed on the
  # pristine tree (measured 2026-08-01) and documented nothing.
  echo "$output" | grep -qE '^[[:space:]]*needs[[:space:]]'
}
