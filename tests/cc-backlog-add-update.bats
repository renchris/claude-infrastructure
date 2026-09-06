#!/usr/bin/env bats
# cc-backlog `add` on a KNOWN id — THE UPDATE ARM (backlog ce1e9d1adab8 · W2).
#
# THE DEFECT THIS PINS. `cmd_add` resolves the id, hits `has_id`, echoes it and returns rc 0 having
# written nothing. That is the idempotency contract, and it also made a whole class of caller a
# permanent no-op: a generator that RE-FILES a condition-keyed row to refresh its wording is not
# adding an item, it is reporting a new measurement of a standing state — and the store kept the
# FIRST wording forever. `scripts/backlog-consolidation-trigger.sh --file` runs on every autonomy
# sweep for exactly that purpose ("repeated runs update rather than mint", its own header), and its
# row 5df742fb3894 sat frozen at its pre-R6 wording from 2026-08-11 while the sweep re-filed it every
# few minutes, each pass a silent rc-0 no-op.
#
# EVERY POSITIVE HERE IS PAIRED WITH THE NEGATIVE IT MUST NOT BREAK. The update arm sits inside the
# idempotency path, so the tests that matter most are the ones asserting what did NOT change: no new
# item, no re-open, no ledger growth on an unchanged re-file (memory:
# control-must-replay-the-real-artifact).

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  # Verbatim shapes from the live row this arm was built for: one condition, two measurements.
  T1="backlog consolidation: 3 cluster(s) at/above threshold 5 — 14 rows in the largest"
  T2="backlog consolidation: 1 cluster(s) at/above threshold 5 — 6 rows in the largest"
}

refute_match() { [ "$(printf '%s' "$1" | grep -c "$2")" -eq 0 ]; }

fld() { bash "$CB" list --all --json | jq -r --arg i "$1" --arg f "$2" '.[]|select(.id==$i)|(.[$f] // "")'; }
n_items() { bash "$CB" list --all --json | jq 'length'; }
n_lines() { grep -c '' "$CC_BACKLOG_FILE"; }

@test "a condition-keyed re-file with a NEW title UPDATES the row (the frozen-row defect)" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  b=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T2" --source trig)
  [ "$a" = "$b" ]
  [ "$(n_items)" -eq 1 ]
  [ "$(fld "$a" title)" = "$T2" ]
}

@test "CONTROL — the row is still ONE item and still open; an update is not an add or a reopen" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T2" --source trig
  [ "$(n_items)" -eq 1 ]
  [ "$(grep -c '"event":"add"' "$CC_BACKLOG_FILE")" -eq 1 ]
  [ "$(fld "$a" status)" = "open" ]
  refute_match "$(cat "$CC_BACKLOG_FILE")" '"event":"reopen"'
}

@test "CONTROL — an UNCHANGED re-file appends NOTHING (an idempotent caller cannot grow the ledger)" {
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig
  before=$(n_lines)
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig
  [ "$(n_lines)" -eq "$before" ]
}

@test "--dod-ref and --source update too, and the update record carries ONLY what changed" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig --dod-ref old/path.md)
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig --dod-ref "origin/main:docs/plans/NEW.md"
  [ "$(fld "$a" dodRef)" = "origin/main:docs/plans/NEW.md" ]
  [ "$(fld "$a" title)" = "$T1" ]
  # The appended record must not carry the unchanged title — a whole-row rewrite would make every
  # re-file a diff against itself and defeat the unchanged-is-silent rule above.
  upd="$(grep '"event":"update"' "$CC_BACKLOG_FILE" | tail -1)"
  [ "$(printf '%s' "$upd" | jq -r 'has("dodRef")')" = "true" ]
  [ "$(printf '%s' "$upd" | jq -r 'has("title")')" = "false" ]
}

@test "a DONE row is never re-worded — its title is what its evidence refers to" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  bash "$CB" "done" "$a" --evidence "landed abc1234"
  # stdout ONLY. The done-guard writes a multi-line WARNING to stderr, and bats' `run` folds the two
  # streams together — so comparing $output against the id fails on the warning, not on the contract.
  echoed="$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T2" --source trig 2>/dev/null)"
  [ "$echoed" = "$a" ]                     # idempotency contract survives
  [ "$(fld "$a" title)" = "$T1" ]          # …and the history is intact
  [ "$(fld "$a" status)" = "done" ]
  refute_match "$(cat "$CC_BACKLOG_FILE")" '"event":"update"'
}

@test "--falsifier on a known id stays a NO-OP: only \`falsify\` may store a probe (it runs it first)" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig --falsifier "true"
  [ -z "$(fld "$a" falsifier)" ]
  refute_match "$(cat "$CC_BACKLOG_FILE")" '"event":"update"'
}

@test "the update event lands in the CARRY-FORWARD arm of the status fold, not in a default" {
  a=$(bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T1" --source trig)
  bash "$CB" block "$a" --needs "waiting on a decision"
  bash "$CB" add --project P --condition backlog-duplicate-cluster-over-threshold --title "$T2" --source trig
  # An `update` carries NO status field, so a blocked row must still read blocked afterwards. A new
  # event member that reset status (or landed in a fail-closed default) is this repo's recurring
  # defect (memory: new-enum-member-falls-into-fail-closed-default).
  [ "$(fld "$a" status)" = "blocked" ]
  [ "$(fld "$a" title)" = "$T2" ]
  [ "$(fld "$a" needs)" = "waiting on a decision" ]
}

@test "the trigger's own --file path can now move its row's wording (the live caller)" {
  # THE REAL ARTIFACT, not a paraphrase: the escalation row is minted by
  # backlog-consolidation-trigger.sh --file, which is why the freeze mattered. Two --file runs over
  # two different stores must leave the row wearing the SECOND measurement.
  trig="$REPO/scripts/backlog-consolidation-trigger.sh"
  seed() { # <n-rows> — one cluster whose size decides the escalated wording
    : > "$CC_BACKLOG_FILE"
    for i in $(seq 1 "$1"); do
      bash "$CB" add --project P --title "autonomy sweep suite FAILED at sha deadbee$i (run $i)" --source postland >/dev/null
    done
  }
  seed 7
  run bash "$trig" --file --threshold 5
  [ "$status" -eq 0 ]
  id="$(bash "$CB" list --all --json | jq -r '.[]|select(.condition!=null and (.condition|startswith("backlog-duplicate")))|.id' | head -1)"
  [ -n "$id" ]
  first="$(fld "$id" title)"
  # A second, LARGER cluster in the same store must re-word the same row rather than mint a sibling.
  bash "$CB" add --project P --title "autonomy sweep suite FAILED at sha deadbee8 (run 8)" --source postland >/dev/null
  bash "$CB" add --project P --title "autonomy sweep suite FAILED at sha deadbee9 (run 9)" --source postland >/dev/null
  run bash "$trig" --file --threshold 5
  [ "$status" -eq 0 ]
  second="$(fld "$id" title)"
  [ "$first" != "$second" ]
  [ "$(bash "$CB" list --all --json | jq '[.[]|select(.condition!=null and (.condition|startswith("backlog-duplicate")))]|length')" -eq 1 ]
}

# ── ADD-TIME COVERAGE WARNING (backlog-zero W2a) ─────────────────────────────────────────────────
# A row with no --falsifier, no --condition and no --dod-ref has no retraction path and no anchor:
# nothing can ask whether it is still needed. Measured 2026-09-04, coverage is 14.4% live / 7.3%
# working and the zero-coverage classes are the model-authored ones (free-hand 21/381, needs 1/148)
# — docs/research/backlog-zero-2026-09-04/inflow.md §5.4. ADVISORY BY DESIGN: `cmd_needs` documents
# why a fabricated probe is worse than none, so a refusal would buy coverage in invented falsifiers.

@test "add with no falsifier, no condition and no dod-ref WARNS on stderr" {
  run bash "$CB" add --project P --title "a bare row nothing can retract"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'cannot retract itself'
  printf '%s' "$output" | grep -q 'FILED is the exception'
}

@test "CONTROL — the warned row is still FILED (advisory, never a refusal)" {
  local id; id=$(bash "$CB" add --project P --title "a bare row nothing can retract")
  [ -n "$id" ]
  [ "$(n_items)" -eq 1 ]
  [ "$(fld "$id" status)" = "open" ]
}

@test "CONTROL — ANY ONE of the three silences it (falsifier / condition / dod-ref)" {
  run bash "$CB" add --project P --title "probed" --falsifier "true"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -q 'cannot retract itself'; then echo "falsifier did not silence" >&2; false; fi

  run bash "$CB" add --project P --title "keyed" --condition some-standing-state
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -q 'cannot retract itself'; then echo "condition did not silence" >&2; false; fi

  run bash "$CB" add --project P --title "anchored" --dod-ref "docs/plans/X.md#phase-2"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -q 'cannot retract itself'; then echo "dod-ref did not silence" >&2; false; fi
}

@test "CC_BACKLOG_COVERAGE_WARN=off is the fixture opt-out" {
  CC_BACKLOG_COVERAGE_WARN=off run bash "$CB" add --project P --title "a bare row nothing can retract"
  [ "$status" -eq 0 ]
  if printf '%s' "$output" | grep -q 'cannot retract itself'; then echo "opt-out ignored" >&2; false; fi
}

@test "CONTROL — the needs path stays silent: its stdout IS the id, read off a merged stream" {
  run bash "$CB" needs "authenticate motion-plus in /mcp" --project P
  [ "$status" -eq 0 ]
  # bats `run` folds stderr into $output, which is exactly how cc-backlog-needs.bats:58 reads the id
  [[ "$output" =~ ^[0-9a-f]{12}$ ]]
}

# ── FILING IS ATTRIBUTED, AND THE HAND-OFF IS A FIELD (2026-09-05, BACKLOG_ZERO §5) ──────────────
# Pre-fix an `add` recorded no author (108/108 adds by:null, inflow.md §7.6) and no `--why-not-now`
# existed, so `filedBy`/`whyNotNow` were absent from every record and every fold — each case below
# is red on the pre-fix binary because the field it reads is simply not there.

@test "add stamps filedBy from CLAUDE_CODE_SESSION_ID; --session overrides it; unset ⇒ no field" {
  a=$(CLAUDE_CODE_SESSION_ID=sess-A bash "$CB" add --project P --title "attrib one" --source s)
  [ "$(fld "$a" filedBy)" = "sess-A" ]
  b=$(CLAUDE_CODE_SESSION_ID=sess-A bash "$CB" add --project P --title "attrib two" --source s --session sess-Z)
  [ "$(fld "$b" filedBy)" = "sess-Z" ]
  c=$(env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID -u CC_SESSION_ID bash "$CB" add --project P --title "attrib three" --source s)
  [ "$(fld "$c" filedBy)" = "" ]
  refute_match "$(grep '"attrib three"' "$CC_BACKLOG_FILE")" 'filedBy'
}

@test "--why-not-now is stored on the add and survives the fold into list --json" {
  a=$(bash "$CB" add --project P --title "handed off" --source s --why-not-now "needs-credential: the prod credential")
  [ "$(fld "$a" whyNotNow)" = "needs-credential: the prod credential" ]
  bash "$CB" list --all --json | jq -e --arg i "$a" '.[]|select(.id==$i)|.whyNotNow=="needs-credential: the prod credential"' >/dev/null
}

@test "re-running the same add WITH --why-not-now folds onto the live row as an update (the hand-off of a bare row)" {
  a=$(bash "$CB" add --project P --title "bare then handed" --source s)
  [ "$(fld "$a" whyNotNow)" = "" ]
  b=$(bash "$CB" add --project P --title "bare then handed" --source s --why-not-now "needs-human: operator-only deploy")
  [ "$a" = "$b" ]
  [ "$(n_items)" -eq 1 ]
  [ "$(grep -c '"event":"add"' "$CC_BACKLOG_FILE")" -eq 1 ]
  [ "$(grep -c '"event":"update"' "$CC_BACKLOG_FILE")" -eq 1 ]
  [ "$(fld "$a" whyNotNow)" = "needs-human: operator-only deploy" ]
  [ "$(fld "$a" status)" = "open" ]
}

@test "CONTROL — the same add re-run with an UNCHANGED --why-not-now writes nothing" {
  a=$(bash "$CB" add --project P --title "idem" --source s --why-not-now "no-capacity: same")
  bash "$CB" add --project P --title "idem" --source s --why-not-now "no-capacity: same"
  [ "$(n_lines)" -eq 1 ]
}

# ── THE IMPOSSIBILITY CLASS (2026-09-05, .claude-plans/WORK_ON_NOT_FILE.md) ──────────────────────
# Pre-fix `--why-not-now` took any string, so every arm that enforced the FILED test discharged on a
# sentence. The first case replays the ACTUAL trigger incident's reason verbatim; it is red pre-fix
# because the row was minted and rc was 0. The controls bound the gate in the other direction — it
# must not reject a real class, and it must not reject the absent flag (bare adds are how every
# generator files, and an omitted why-not-now is already the filer's 🔧 via wrap-ledger FILED_MINE).

@test "a free-text reason is REFUSED (rc 2) and writes no row — the trigger incident's own words" {
  run bash "$CB" add --project P --title "48 schema discrepancies" --source s \
        --why-not-now "the operator said don't start new work, and remediation is the operator's"
  [ "$status" -eq 2 ]
  printf '%s' "$output" | grep -q 'names no impossibility class'
  printf '%s' "$output" | grep -q 'needs-credential'
  [ "$(n_items)" -eq 0 ]
}

@test "each of the four classes is accepted, bare and with a ': <detail>' tail" {
  i=0
  for c in needs-credential needs-human not-yet-true no-capacity; do
    i=$((i+1))
    run bash "$CB" add --project P --title "bare $c" --source s --why-not-now "$c"
    [ "$status" -eq 0 ]
    run bash "$CB" add --project P --title "tail $c" --source s --why-not-now "$c: because $i"
    [ "$status" -eq 0 ]
  done
  [ "$(n_items)" -eq 8 ]
}

@test "the class must OPEN the value — a sentence that merely CONTAINS one is still prose" {
  run bash "$CB" add --project P --title "buried" --source s \
        --why-not-now "we have no-capacity to look at this right now"
  [ "$status" -eq 2 ]
  [ "$(n_items)" -eq 0 ]
}

@test "CONTROL — an add with NO --why-not-now is unaffected; the gate is on the value, not presence" {
  run bash "$CB" add --project P --title "bare generator row" --source s
  [ "$status" -eq 0 ]
  [ "$(n_items)" -eq 1 ]
  [ "$(fld "$(bash "$CB" list --all --json | jq -r '.[0].id')" whyNotNow)" = "" ]
}

@test "done stamps closedSession from the closing session's env; unset ⇒ no field" {
  a=$(CLAUDE_CODE_SESSION_ID=sess-A bash "$CB" add --project P --title "to close" --source s)
  CLAUDE_CODE_SESSION_ID=sess-B bash "$CB" "done" "$a" --evidence "closed in a test"
  [ "$(fld "$a" closedSession)" = "sess-B" ]
  [ "$(fld "$a" filedBy)" = "sess-A" ]            # the two halves of the per-session net coexist
  b=$(bash "$CB" add --project P --title "to close anon" --source s)
  env -u CLAUDE_CODE_SESSION_ID -u CLAUDE_SESSION_ID -u CC_SESSION_ID bash "$CB" "done" "$b" --evidence "anon"
  refute_match "$(grep "\"id\":\"$b\"" "$CC_BACKLOG_FILE" | grep '"done"')" 'closedSession'
}

# ── add --run (2026-09-06, BACKLOG_ZERO §6) ──────────────────────────────────────────────────────
# `run` used to ride ONLY the block record, so the one verb that could carry a runnable command was
# the one that parked the row in `blocked` — the state no lane reads. A machine producer filing agent
# work (ship-land's re-land row) needs the command on an OPEN row; the fold already carries `run`
# from any record, so this is the writer half. RED-proved on the pre-fix binary: `add --run` was
# `unknown arg`, exit 2, and no record was written.

@test "add --run stores the command on the add record and it survives the fold to list --open --json" {
  id=$(bash "$CB" add --title "re-land feat/x" --project P --source needs --run "cd /repo && bash scripts/ship-land.sh")
  [ "$(jq -r 'select(.event=="add") | .run' "$CC_BACKLOG_FILE")" = "cd /repo && bash scripts/ship-land.sh" ]
  [ "$(bash "$CB" list --open --json | jq -r --arg i "$id" '.[] | select(.id==$i) | .run')" = "cd /repo && bash scripts/ship-land.sh" ]
  [ "$(bash "$CB" list --open --json | jq -r --arg i "$id" '.[] | select(.id==$i) | .status')" = "open" ]
}

@test "re-running the same add with a DIFFERENT --run folds onto the live row as an update carrying run" {
  id=$(bash "$CB" add --title "re-land feat/y" --project P --source needs --run "old cmd")
  before=$(n_lines)
  id2=$(bash "$CB" add --title "re-land feat/y" --project P --source needs --run "new cmd")
  [ "$id2" = "$id" ]
  [ "$(n_lines)" -eq $((before + 1)) ]
  [ "$(tail -1 "$CC_BACKLOG_FILE" | jq -r '.event')" = "update" ]
  [ "$(tail -1 "$CC_BACKLOG_FILE" | jq -r '.run')" = "new cmd" ]
  [ "$(bash "$CB" list --open --json | jq -r --arg i "$id" '.[] | select(.id==$i) | .run')" = "new cmd" ]
}

@test "CONTROL — the same add re-run with an UNCHANGED --run writes nothing" {
  bash "$CB" add --title "re-land feat/z" --project P --source needs --run "same cmd" >/dev/null
  before=$(n_lines)
  bash "$CB" add --title "re-land feat/z" --project P --source needs --run "same cmd" >/dev/null
  [ "$(n_lines)" -eq "$before" ]
}
