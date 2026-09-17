#!/usr/bin/env bats
# scripts/backlog-flow-assert.sh — BACKLOG_DRAIN_24_7 §6's weekly adds-vs-closes invariant.
#
# WHAT IS BEING PINNED. The subject is an ALARM whose conviction files a standing, condition-keyed
# row into the very store the program exists to drain, so its two failure directions are not
# symmetric and neither is testable by a smoke check:
#
#   a FALSE DRAINING     is §1.3 recurring with an instrument in the room — inflow outruns the drain,
#                        the report reads fine, and the program answers by adding drain horsepower
#                        against a generator nobody is fixing.
#   a FALSE NET-POSITIVE files a permanent row that never ages out. The structural instance is a
#                        store younger than the window: its first week is net-positive BY
#                        CONSTRUCTION, because everything in it is new and nothing has had time to
#                        close. §6's own trap, pointed the other way (cap-whose-population-is-empty).
#
# So every case below is a red-provable property rather than a shape assertion, and the four
# abstentions get as much room as the two verdicts.
#
# THE FIXTURE IS TWO-PART, DELIBERATELY, AND THE FIRST PART IS THE LOAD-BEARING ONE.
# `bin/cc-backlog` has no clock seam on its WRITE path (CC_BACKLOG_NOW is read at :4753 only, by the
# age/window arms), so a historical record cannot be produced by the real binary and the past has to
# be hand-written. Hand-written JSONL alone would pin this suite's idea of the record schema rather
# than cc-backlog's — the exact drift drain-chain-assert.bats avoids by building its fold from the
# real binary. Both halves are therefore used, for the parts each can prove:
#
#   case 1 (PARITY) writes every in-window event with the REAL bin/cc-backlog and asserts the
#          subject's counts. That is the guard against the schema moving underneath it: if `add`
#          ever stopped being one record per id, or `done` stopped being the closing verb, this
#          case goes red and the hand-written ones would not.
#   every other case hand-writes `{id,ts,event}` — the three fields case 1 has just certified —
#          because placing a record in the past is the one thing no seam allows.
#
# A single hand-written record 20 d old seeds the store's HISTORY DEPTH in every case that wants a
# verdict at all: without it the store is younger than the window and the subject correctly
# abstains, which is case 9's whole point.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUBJECT="$REPO/scripts/backlog-flow-assert.sh"
  CB="$REPO/bin/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/dispatch-kick"
  export CC_BACKLOG_BIN="$CB"
  NOW=1786000000
  export CC_BACKLOG_FLOW_NOW="$NOW"
  : > "$CC_BACKLOG_FILE"
}

# iso <epoch> — the store's stamp format (cc-backlog's now_iso, :866). BSD-first with a GNU
# fallback whose BSD attempt is CAPTURED AND VALIDATED rather than let through: `date -r` takes an
# epoch on BSD and a REFERENCE FILE on GNU, so the first arm fails on Linux — quietly, to stderr,
# unlike `stat -f`'s stdout leak (4d7bc86d). Validated anyway, because a fixture that silently
# stamps garbage makes every case below vacuous rather than red.
iso() {
  local v
  v="$(date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" || v=""
  case "$v" in ????-??-??T??:??:??Z) printf '%s' "$v"; return 0 ;; esac
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ
}

# rec <id> <ago_s> <event> [project] — one hand-written record, `ago_s` seconds before NOW.
rec() {
  local id="$1" ago="$2" ev="$3" proj="${4:-}"
  local ts; ts="$(iso $(( NOW - ago )))"
  if [ -n "$proj" ]; then
    jq -nc --arg i "$id" --arg t "$ts" --arg e "$ev" --arg p "$proj" \
      '{id:$i, ts:$t, event:$e, project:$p, title:("t-"+$i), source:"fx"}' >> "$CC_BACKLOG_FILE"
  else
    jq -nc --arg i "$id" --arg t "$ts" --arg e "$ev" '{id:$i, ts:$t, event:$e}' >> "$CC_BACKLOG_FILE"
  fi
}

# seed_history — one 20 d-old add, so the 7 d window fits the store's history.
seed_history() { rec anchor $(( 20 * 86400 )) add claude-infrastructure; }

jfield() { "$SUBJECT" --json "${@:2}" | jq -r ".$1"; }

# ── 1. PARITY — the subject reads what cc-backlog actually writes ──────────────────────────────
# The only case whose in-window records come from the real binary. It anchors the schema: `add` is
# one record per id, `done` is the closing verb, `reopen` re-enters. Everything below trusts that.
@test "the counts agree with what the real cc-backlog writes for add/done/reopen" {
  seed_history
  local a b c
  a="$(bash "$CB" add --project claude-infrastructure --title "parity one"   --source fx)"
  b="$(bash "$CB" add --project claude-infrastructure --title "parity two"   --source fx)"
  c="$(bash "$CB" add --project claude-infrastructure --title "parity three" --source fx)"
  bash "$CB" "done" "$b" --evidence "landed abc123" >/dev/null
  # `--force` because cc-backlog REFUSES to reopen terminal work without it (:1657, the done-latch:
  # re-opening completed work puts it back in the dispatch wave). So a production reopen is always a
  # deliberate one — which is the other half of why §6 must not fold reopens into the inflow count.
  bash "$CB" reopen "$b" --force >/dev/null
  # NOW must sit after those real stamps, or the window excludes them.
  CC_BACKLOG_FLOW_NOW="$(date +%s)"; export CC_BACKLOG_FLOW_NOW
  run "$SUBJECT" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .added)" = 3 ]
  [ "$(printf '%s' "$output" | jq -r .closed)" = 1 ]
  [ "$(printf '%s' "$output" | jq -r .reopened)" = 1 ]
  [ "$(printf '%s' "$output" | jq -r .net)" = 2 ]
  [ "$(printf '%s' "$output" | jq -r .verdict)" = net-positive ]
  [ -n "$a$c" ]
}

# ── 2-4. the verdict and its boundary ──────────────────────────────────────────────────────────
@test "closing more than was filed is DRAINING, and --assert exits 0" {
  seed_history
  rec a1 3600 add claude-infrastructure
  rec x1 3600 "done"; rec x2 3600 "done"; rec x3 3600 "done"
  run "$SUBJECT"; [ "$status" -eq 0 ]
  [[ "$output" == *DRAINING* ]] || false
  [[ "$output" == *"1 filed / 3 closed (net -2)"* ]] || false
  # rc 0 is unchanged and is the ONLY rc that still means "the condition is gone". What is new is
  # that it now SPEAKS: cc-premise renders `output:` on its exit-0 branch too, so a closer citing
  # this run gets the figures instead of the "(silent)" that closed backlog 40250b0f698a.
  run "$SUBJECT" --assert; [ "$status" -eq 0 ]
  [[ "$output" == *"DRAINING"* ]] || false
  [[ "$output" == *"1 filed / 3 closed (net -2)"* ]] || false
}

@test "closing exactly as many as were filed is DRAINING, not net-positive — B5 is close >= file" {
  seed_history
  rec a1 3600 add claude-infrastructure; rec a2 3600 add claude-infrastructure
  rec a1 1800 "done"; rec a2 1800 "done"
  [ "$(jfield verdict)" = draining ]
  run "$SUBJECT" --assert; [ "$status" -eq 0 ]
}

@test "filing more than was closed is NET-POSITIVE, --assert exits 1, and it names the INFLOW list" {
  seed_history
  rec a1 3600 add claude-infrastructure; rec a2 3600 add claude-infrastructure
  rec a1 1800 "done"
  run "$SUBJECT" --assert
  [ "$status" -eq 1 ]
  [[ "$output" == *NET-POSITIVE* ]] || false
  [[ "$output" == *"INFLOW list (C1-C4)"* ]]
}

# ── 5-7. the filing arm ────────────────────────────────────────────────────────────────────────
@test "a draining week files nothing" {
  seed_history
  rec a1 3600 add claude-infrastructure; rec x1 3600 "done"; rec x2 3600 "done"
  run "$SUBJECT" --file; [ "$status" -eq 0 ]
  run bash "$CB" list --open --json
  [ "$(printf '%s' "$output" | jq '[.[] | select(.source=="backlog-flow-assert")] | length')" = 0 ]
}

@test "a net-positive week files ONE condition-keyed row carrying --assert as its falsifier" {
  seed_history
  rec a1 3600 add claude-infrastructure; rec a2 3600 add claude-infrastructure
  run "$SUBJECT" --file; [ "$status" -eq 0 ]
  run bash "$CB" list --open --json
  local row
  row="$(printf '%s' "$output" | jq -c '[.[] | select(.source=="backlog-flow-assert")]')"
  [ "$(printf '%s' "$row" | jq 'length')" = 1 ]
  [ "$(printf '%s' "$row" | jq -r '.[0].condition')" = backlog-inflow-net-positive ]
  # the row retires itself: its falsifier is the subject's own conviction arm, which returns to 0
  # the week the sign flips, so nothing human is in the retirement loop.
  [[ "$(printf '%s' "$row" | jq -r '.[0].falsifier')" == *"backlog-flow-assert.sh --assert"* ]]
}

@test "re-filing after the figures move appends NOTHING — the title carries no volatile number" {
  # THE UNBOUNDED-GROWTH GUARD, and it is the reason the title has no counts in it. The caller is
  # autonomy-sweep at 300 s, and cc-backlog's update arm rewrites a known row's title whenever it
  # CHANGED — so a title carrying live figures would append an `update` record on every tick whose
  # numbers moved, up to 288 a day, from the detector whose whole subject is filing rate.
  seed_history
  rec a1 3600 add claude-infrastructure; rec a2 3600 add claude-infrastructure
  "$SUBJECT" --file
  local after1; after1="$(wc -l < "$CC_BACKLOG_FILE")"
  rec b1 1800 add claude-infrastructure; rec b2 1800 add claude-infrastructure
  rec b3 1800 add claude-infrastructure   # the figures have moved: 2 filed → 5 filed
  "$SUBJECT" --file
  local after2; after2="$(wc -l < "$CC_BACKLOG_FILE")"
  [ "$after2" -eq "$(( after1 + 3 ))" ]   # the 3 records this test wrote, and nothing from --file
  [ "$(jq -r 'select(.event=="update")' "$CC_BACKLOG_FILE" | wc -l)" -eq 0 ]
}

# ── 8-11. the four abstentions, none of which may convict ─── AND none of which may ACQUIT ─────
# 🚨 THE `--assert` EXPECTATION IN THESE CASES WAS `-eq 0`, AND IT PINNED THE DEFECT
# (backlog 40250b0f698a). Inverted in place rather than deleted: the old expectation is the record
# of what was believed, and it was believed on the subject header's argument that "an unknown must
# read exactly like a healthy week to every consumer". `--assert` has exactly ONE consumer — the
# `--falsifier` string the --file arm stores on the row it files — and for cc-premise exit 0 is not
# "a healthy week", it is THE CONDITION IS GONE. So each of these cases was asserting that a
# measurement which never ran RETRACTS the standing inflow alarm. 2 is cc-premise's
# _FALSIFIER_UNASKABLE_RCS ("UNVERIFIED, not confirmed"), and case 11d below pins that join.
# The FILING polarity is untouched and is still asserted in every one of them: an abstention files
# nothing, so no abstention can mint a row on a healthy new box.
@test "no store at all is skipped, not draining and not net-positive" {
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/absent.jsonl"
  [ "$(jfield verdict)" = unknown ]
  [ "$(jfield why)" = skipped ]
  run "$SUBJECT" --assert; [ "$status" -eq 2 ]
  [[ "$output" == *"CANNOT TELL (skipped)"* ]] || false
}

@test "a store that parses to no records is read-failed — 'I could not ask' is never 'no'" {
  printf 'not json\n{oops\n' > "$CC_BACKLOG_FILE"
  [ "$(jfield verdict)" = unknown ]
  [ "$(jfield why)" = read-failed ]
  # Both lines are now COUNTED rather than silently discarded — see case 11a.
  [ "$(jfield dropped)" = 2 ]
  run "$SUBJECT" --assert; [ "$status" -eq 2 ]
  run "$SUBJECT" --file; [ "$status" -eq 0 ]
  [ "$(grep -c backlog-flow-assert "$CC_BACKLOG_FILE" || true)" -eq 0 ]
}

@test "a store younger than the window ABSTAINS however net-positive it looks" {
  # THE FALSE-POSITIVE GUARD. No seed_history: every record is 1 h old, and a fresh store's first
  # week is net-positive by construction. Convicting here files a permanent row on a healthy box.
  local i
  for i in 1 2 3 4 5 6 7 8; do rec "a$i" 3600 add claude-infrastructure; done
  [ "$(jfield verdict)" = unknown ]
  [ "$(jfield why)" = short-history ]
  [ "$(jfield added)" = 8 ]          # the figures are still REPORTED; only the verdict abstains
  run "$SUBJECT" --assert; [ "$status" -eq 2 ]
  run "$SUBJECT" --file;   [ "$status" -eq 0 ]
  [ "$(grep -c backlog-inflow-net-positive "$CC_BACKLOG_FILE" || true)" -eq 0 ]
}

@test "the history boundary is the window itself, and one second either side decides it" {
  rec a1 3600 add claude-infrastructure
  rec anchor 604799 add claude-infrastructure     # 1 s short of a week of history
  [ "$(jfield why)" = short-history ]
  rec anchor2 604800 add claude-infrastructure    # exactly a week: the window now fits
  [ "$(jfield verdict)" = net-positive ]
}

@test "more unreadable timestamps than the margin the verdict rests on is an abstention" {
  # An excluded record is not an absent one: if the pile this pass could not place is bigger than
  # the net, that pile alone could reverse the sign.
  seed_history
  rec a1 3600 add claude-infrastructure; rec a2 3600 add claude-infrastructure   # net +2
  local i
  for i in 1 2 3; do
    jq -nc --arg i "u$i" '{id:$i, ts:"not-a-timestamp", event:"add"}' >> "$CC_BACKLOG_FILE"
  done
  [ "$(jfield unparsed)" = 3 ]
  [ "$(jfield verdict)" = unknown ]
  # Still named for the ts channel: `why` reports whichever channel DOMINATES, and here `dropped`
  # is 0. The threshold itself is now `excluded` = unparsed + dropped (case 11a).
  [ "$(jfield why)" = unparsed-could-flip ]
  [ "$(jfield dropped)" = 0 ]
  [ "$(jfield excluded)" = 3 ]
  run "$SUBJECT" --assert; [ "$status" -eq 2 ]
}

@test "a margin wider than the unreadable pile survives it, and the pile is still reported" {
  seed_history
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do rec "a$i" 3600 add claude-infrastructure; done
  for i in 1 2 3; do
    jq -nc --arg i "u$i" '{id:$i, ts:"", event:"add"}' >> "$CC_BACKLOG_FILE"
  done
  [ "$(jfield verdict)" = net-positive ]
  [ "$(jfield unparsed)" = 3 ]
}

# ── 11a-11d. THE TWO DEFECTS backlog 40250b0f698a CLOSED ───────────────────────────────────────
# Each of these is red against the pre-fix subject and green after; 11a and 11b are the two halves
# of one incident, and they compose — 11a MANUFACTURES a false verdict and 11b DELIVERS it to the
# only consumer as "the condition is gone", which is how the row that prompted this fix was closed
# on `output: (silent)`.

# splice <n> <event> — cut the first n records of that event in two, the way a concurrent appender
# lands between the >=2 write() calls of a record over the writer's 4,096-byte stdio buffer. Both
# halves then stop parsing. This is not a synthetic corruption: it is the measured shape that cost
# one census 12.33% of THIS store (W2-B17, 1550268e6).
#
# seed_history's anchor is itself an `add`, so it MUST be held out: splicing it destroys the store's
# history depth and the subject then abstains at guard 3 (short-history) instead of guard 4. Both
# are abstentions and both exit 2, so the case would still look green while exercising a different
# guard from the one it names — the axis under test held constant by the fixture (memory:
# fixture-identifier-shape-collapses-two-spaces). Caught by asserting `why`, not just `verdict`.
splice() {
  local want="$1" ev="$2" n=0 l; local tmp="$BATS_TEST_TMPDIR/pre-splice.jsonl"
  mv "$CC_BACKLOG_FILE" "$tmp"; : > "$CC_BACKLOG_FILE"
  while IFS= read -r l; do
    case "$l" in
      *'"id":"anchor"'*) printf '%s\n' "$l" >> "$CC_BACKLOG_FILE" ;;
      *"\"event\":\"$ev\""*)
        n=$(( n + 1 ))
        if [ "$n" -le "$want" ]; then printf '%s\n%s\n' "${l:0:18}" "${l:18}" >> "$CC_BACKLOG_FILE"
        else printf '%s\n' "$l" >> "$CC_BACKLOG_FILE"; fi ;;
      *) printf '%s\n' "$l" >> "$CC_BACKLOG_FILE" ;;
    esac
  done < "$tmp"
}

@test "11a a line that will not parse is EXCLUDED EVIDENCE and is weighed as such" {
  # RED-PROOF, and the control is the same store one variable apart. Pre-fix, `fromjson? // empty`
  # dropped a spliced line into neither `records` nor `unparsed`, so guard 4 — whose stated job is
  # "excluded evidence is not absent evidence" — compared its margin against a pile that excluded
  # the store's dominant channel, and emitted a CONFIDENT verdict of the opposite sign.
  seed_history
  local i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do rec "a$i" 3600 add claude-infrastructure; done
  for i in 1 2 3 4 5 6; do rec "d$i" 3600 "done"; done
  # the control arm: intact, the week really is net-positive, and the row must STAY OPEN.
  [ "$(jfield verdict)" = net-positive ]
  [ "$(jfield net)" = 6 ]
  run "$SUBJECT" --assert; [ "$status" -eq 1 ]

  splice 12 add
  # PRE-FIX this read `verdict=draining, net=-6, unparsed=0` and `--assert` exited 0 — a sign flip
  # of 12 on a pile the guard reported as empty, handed to cc-premise as "the condition is GONE".
  [ "$(jfield verdict)" = unknown ]
  [ "$(jfield why)" = unreadable-lines-could-flip ]
  [ "$(jfield unparsed)" = 0 ]              # the OLD pile is still empty — that is the whole point
  [ "$(jfield dropped)" -gt 0 ]             # the NEW one is not
  run "$SUBJECT" --assert; [ "$status" -eq 2 ]
}

@test "11b the mirror direction: splicing CLOSINGS may not mint a confident net-positive either" {
  # The hole reaches both forbidden directions. Splicing `done` records inflates the net instead of
  # flipping it, which is the FALSE NET-POSITIVE that files a standing row into the store this
  # program exists to drain. Pre-fix: net +1 -> +8, verdict net-positive, unparsed 0, --file FILES.
  seed_history
  local i
  for i in 1 2 3 4 5 6 7 8; do rec "a$i" 3600 add claude-infrastructure; done
  for i in 1 2 3 4 5 6 7; do rec "d$i" 3600 "done"; done
  [ "$(jfield net)" = 1 ]
  splice 7 "done"
  [ "$(jfield verdict)" = unknown ]
  run "$SUBJECT" --file; [ "$status" -eq 0 ]
  [ "$(grep -c backlog-inflow-net-positive "$CC_BACKLOG_FILE" || true)" -eq 0 ]
}

@test "11c a blank line is not a lost record, so it cannot drag the store into an abstention" {
  # The over-statement in 11a is deliberate and bounded; this is the boundary. A blank line carries
  # no record and is not evidence of one, so counting it would let a store with a trailing newline
  # abstain forever — an alarm that can never speak (memory: gate-must-ease-with-evidence).
  seed_history
  rec a1 3600 add claude-infrastructure
  printf '\n   \n\n' >> "$CC_BACKLOG_FILE"
  [ "$(jfield dropped)" = 0 ]
  [ "$(jfield verdict)" = net-positive ]
}

@test "11d the abstention rc is the one cc-premise renders as UNVERIFIED (canary)" {
  # THE JOIN THAT MAKES THE WHOLE FIX LOAD-BEARING, and the reason 2 rather than a fresh code: a
  # falsifier rc outside cc-premise's unaskable set renders "NOT REFUTED", which is a different and
  # weaker claim than "could not ask" (memory: new-enum-member-falls-into-fail-closed-default). If
  # that set is ever re-spelled, this goes red here rather than silently at a closer.
  grep -qE '^_FALSIFIER_UNASKABLE_RCS = frozenset\(\(2,' "$REPO/bin/cc-premise" || false
  # and exit 0 must still be the one blocking answer, or `draining` stops closing the row at all
  grep -qF 'if p.returncode == 0:' "$REPO/bin/cc-premise" || false
  # the five states must be DISTINGUISHABLE through that one consumer — pre-fix, four abstentions
  # and a genuine `draining` all returned an identical rc 0 with no output at all.
  seed_history; rec a1 3600 add claude-infrastructure
  run "$SUBJECT" --assert; [ "$status" -eq 1 ]
  rec x1 3600 "done"; rec x2 3600 "done"
  run "$SUBJECT" --assert; [ "$status" -eq 0 ]; [ -n "$output" ]
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/absent.jsonl"
  run "$SUBJECT" --assert; [ "$status" -eq 2 ]; [ -n "$output" ]
}

# ── 12-15. what counts, and what deliberately does not ─────────────────────────────────────────
@test "a reopen is not an add — it is reported on its own line and never folded into the inflow" {
  # §6 routes a net-positive week to the INFLOW list (C1-C4) and every member of that list is a
  # FILING generator. Folding reopens into `added` would point a real remedy at the wrong list.
  # Red-proof: fold them in and this store reads net +3 net-positive instead of net -2 draining.
  seed_history
  rec a1 3600 add claude-infrastructure
  local i; for i in 1 2 3 4 5; do rec "r$i" 3000 reopen; done
  rec c1 2400 "done"; rec c2 2400 "done"; rec c3 2400 "done"
  [ "$(jfield added)" = 1 ]
  [ "$(jfield closed)" = 3 ]
  [ "$(jfield reopened)" = 5 ]
  [ "$(jfield verdict)" = draining ]
}

@test "a row closed twice is TWO closings — flow, not the stock reading cc-value takes" {
  seed_history
  rec a1 3600 add claude-infrastructure
  rec a1 3000 "done"; rec a1 2400 reopen; rec a1 1800 "done"
  [ "$(jfield added)" = 1 ]
  [ "$(jfield closed)" = 2 ]        # bin/cc-value's tasks_closed would say 1, and is right for its
  [ "$(jfield reopened)" = 1 ]      # own question — how much work is FINISHED, a stock, not a rate
  [ "$(jfield verdict)" = draining ]
}

@test "annotations are neither filings nor closings" {
  seed_history
  local e; for e in update link venue falsify claim block unblock; do rec "n-$e" 3600 "$e"; done
  [ "$(jfield added)" = 0 ]
  [ "$(jfield closed)" = 0 ]
  [ "$(jfield reopened)" = 0 ]
}

@test "an add is counted once per id however many add records carry it" {
  # cc-backlog appends at most one `add` per id (a known id takes the update arm, :1440), so this
  # can only diverge on a hand-edited or badly-compacted store — where the truthful count of rows
  # filed is the distinct one.
  seed_history
  rec a1 3600 add claude-infrastructure
  rec a1 3000 add claude-infrastructure
  rec a1 2400 add claude-infrastructure
  [ "$(jfield added)" = 1 ]
}

# ── 16-17. the project filter, and the hole it must not hide ───────────────────────────────────
@test "--project scopes BOTH sides through the add records' project map" {
  # A transition record carries no project field, so a filter that scoped adds and counted every
  # project's closings would produce a net that is about no project at all.
  seed_history
  rec p1 3600 add claude-infrastructure
  rec p2 3600 add claude-infrastructure
  rec q1 3600 add other-project
  rec p1 1800 "done"            # a claude-infrastructure close
  rec q1 1800 "done"            # an other-project close
  [ "$(jfield net)" = 1 ]                                        # whole store: 3 filed, 2 closed
  [ "$("$SUBJECT" --json --project claude-infrastructure | jq -r .net)" = 1 ]
  [ "$("$SUBJECT" --json --project other-project | jq -r .net)" = 0 ]
  [ "$("$SUBJECT" --json --project other-project | jq -r .verdict)" = draining ]
}

@test "a transition whose row was never added is counted as unattributed, not silently dropped" {
  seed_history
  rec p1 3600 add claude-infrastructure
  rec ghost 1800 "done"          # no `add` anywhere in the trail: unattributable to any project
  [ "$(jfield closed)" = 1 ]                                     # whole store counts it
  [ "$(jfield unattributed)" = 0 ]                               # and excludes nothing
  [ "$("$SUBJECT" --json --project claude-infrastructure | jq -r .closed)" = 0 ]
  [ "$("$SUBJECT" --json --project claude-infrastructure | jq -r .unattributed)" = 1 ]
}

# ── 18-19. the knobs and the caller ────────────────────────────────────────────────────────────
@test "a garbage window falls back to the default rather than disabling the check" {
  # Polarity: this term RESTRAINS what the verdict may look at, so ignoring a typo fails SAFE. A
  # term that AUTHORISED an action would have to refuse the typo instead.
  seed_history
  rec a1 3600 add claude-infrastructure; rec a2 3600 add claude-infrastructure
  CC_BACKLOG_FLOW_WINDOW_S=off run "$SUBJECT" --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r .window_s)" = 604800 ]
  [ "$(printf '%s' "$output" | jq -r .verdict)" = net-positive ]
}

@test "autonomy-sweep calls the check and journals its rc (canary; see autonomy-sweep.bats)" {
  run grep -F 'backlog-flow-assert.sh' "$REPO/scripts/autonomy-sweep.sh"
  [ "$status" -eq 0 ]
  run grep -F 'flow_rc' "$REPO/scripts/autonomy-sweep.sh"
  [ "$status" -eq 0 ]
}
