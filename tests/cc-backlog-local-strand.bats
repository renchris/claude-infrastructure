#!/usr/bin/env bats
# cc-backlog `reap` — THE LOCAL STRAND REPORT, and the prose join it rests on.
#
# WHAT THIS PINS (measured hermetically 2026-08-25, BACKLOG_DRAIN_24_7 §2.1 recycle #213,
# backlog 3595c391fc71). The cure sweep re-adjudicates the reap's OWN blocks, but only on
# `venue != local`. Six reap-authored blocks in one store showed what that costs:
# `unreswt000006` (local) and `cloudabst007` (cloud) carry the SAME SENTENCE from the SAME
# emitter — "the worktree occupancy oracle could not be RESOLVED past the …s ceiling" — and
# both match the cure select's regex. The cloud row was UNBLOCKED; the local row stayed blocked
# through every later tick, and nothing printed a word about it. One clause, `select(.venue !=
# "local")`, is the whole difference, and ~79% of this backlog is structurally local.
#
# The report is deliberately NOT a cure: `unblock` folds to "open", which is cc-dispatch's fire
# predicate, and two of the four classes below are blocks written BECAUSE a worker was alive.
# See THE LOCAL STRAND in bin/cc-backlog for the full argument.
#
# THE JOIN IS PROSE, because a block record persists only {by,event,id,needs,ts} — there is no
# token field. That is the same join the cure sweep uses, and it is the join that drifted on it
# (matched 0 rows for five days, fixed 2026-08-23). So test 1 hard-codes NO sentence: it renders
# all six out of cc-backlog's OWN assignments and runs the shipped regex against them — four POS,
# two NEG. Reword any emitter and this suite goes red instead of silently emptying the report
# (memory: control-calibrated-to-implementation-decays).
#
# RED-PROOF, stated so the reader knows which line is load-bearing: point CC_TEST_BIN_DIR at a
# pre-fix bin/ and tests 1 and 2 FAIL (verified 2026-08-25 against origin/main dc8300df). Test 3
# is GREEN IN BOTH DIRECTIONS on purpose — it pins "report-only, never writes", a property that
# must hold before and after, and a control that flipped would mean the arm had grown a write.

setup() {
  export CC_BACKLOG_PROJECT_WARN=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CB="${CC_TEST_BIN_DIR:-$REPO/bin}/cc-backlog"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"        # hermeticity rule 1
  export CC_BACKLOG_FILE="$BATS_TEST_TMPDIR/backlog.jsonl"
  export CC_BACKLOG_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  export CC_BACKLOG_KICK=off
  export CC_BACKLOG_KICK_MARKER="$BATS_TEST_TMPDIR/.dispatch-kick"
  export CC_BACKLOG_KICK_BIN="$BATS_TEST_TMPDIR/no-such-dispatch"
}

# Render one of the reap's block sentences straight out of the SOURCE assignment, so no sentence
# in this file can drift away from its producer. Anchored on the assignment (not the phrase), and
# the interpolation vars are supplied here — the same trick tests/cc-backlog-cure-sweep.bats uses
# on cloud_map's printf.
render_needs() {  # $1=grep anchor for the assignment line → the expanded sentence
  local line by id claims fast ageS owned starved liveclaimmax ownedmax unresolvedmax
  line="$(grep -F "$1" "$CB" | grep -E '^[[:space:]]*(local )?[bls]msg=' | head -1)"
  [ -n "$line" ] || return 1
  line="${line#"${line%%[![:space:]]*}"}"; line="${line#local }"; line="${line#*msg=\"}"
  line="${line%\"}"
  # Read by the `eval` on the next line, which shellcheck cannot see through.
  # shellcheck disable=SC2034
  by=vm-4242 id=abcd1234abcd claims=3 fast=2 ageS=40000 \
  owned="live process tree in /wt/wt-abcd1234abcd (2 proc)" \
  starved="worktree root /wt is absent — the occupancy oracle could not be asked at all" \
  liveclaimmax=21600 ownedmax=21600 unresolvedmax=21600
  eval "printf '%s' \"$line\""
}

# The regex the shipped report actually selects on, lifted out of bin/cc-backlog itself rather
# than retyped — retyping it would let the test pass against a regex the tool does not use.
strand_regex() {
  grep -F 'select(.needs | test(' "$CB" | grep -F 'wedged live worker past the' \
    | sed -e 's/.*test("//' -e 's/")).*//' | head -1
}

@test "the strand regex matches all four DECAYABLE premises and neither PERMANENT one" {
  re="$(strand_regex)"
  [ -n "$re" ]

  # POS — a premise with a half-life: a liveness or oracle state nothing re-checks.
  for anchor in 'wedged live worker past the' \
                'wedged owned wait past the' \
                'the worktree occupancy oracle could not be RESOLVED' \
                'could not be RESOLVED past the ${unresolvedmax}s ceiling — the liveness registry'; do
    msg="$(render_needs "$anchor")"
    [ -n "$msg" ]
    printf '%s' "$msg" | jq -Rr --arg re "$re" 'if test($re) then "HIT" else "MISS" end' | grep -qx HIT
  done

  # NEG — a claim about the WORK, permanent, correctly a human's. These are the controls that
  # make the four above a fact about the CLASS and not about a regex that matches everything.
  for anchor in 'persistent thrash' 'dead-worker stall after'; do
    msg="$(render_needs "$anchor")"
    [ -n "$msg" ]
    printf '%s' "$msg" | jq -Rr --arg re "$re" 'if test($re) then "HIT" else "MISS" end' | grep -qx MISS
  done
}

# Seed one blocked row exactly as the reap writes it: add, claim at a venue, then the reap's own
# block carrying the sentence.
seed() {  # $1=id  $2=venue  $3=by  $4=needs
  {
    jq -cn --arg id "$1" '{ts:"2026-08-18T09:00:00Z",id:$id,event:"add",title:"strand fixture",project:"p"}'
    jq -cn --arg id "$1" --arg v "$2" '{ts:"2026-08-18T09:20:00Z",id:$id,event:"claim",by:"vm-4242",venue:$v}'
    jq -cn --arg id "$1" --arg b "$3" --arg n "$4" '{ts:"2026-08-18T09:33:16Z",id:$id,event:"block",by:$b,needs:$n}'
  } >> "$CC_BACKLOG_FILE"
}

@test "reap NAMES a local decayed-premise block, and stays silent on the three that are not one" {
  : > "$CC_BACKLOG_FILE"
  wedged="$(render_needs 'wedged live worker past the')"
  thrash="$(render_needs 'persistent thrash')"
  [ -n "$wedged" ] && [ -n "$thrash" ] || false

  seed aaaa1111aaaa local cc-backlog-reap "$wedged"   # the subject
  seed bbbb2222bbbb local cc-backlog-reap "$thrash"   # NEG: permanent premise
  seed cccc3333cccc cloud cc-backlog-reap "$wedged"   # NEG: the cure sweep's territory
  seed dddd4444dddd local a-human           "$wedged" # NEG: not the machine's own block

  run bash "$CB" reap --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'LOCAL reap-authored block(s) rest on a premise that has DECAYED'
  echo "$output" | grep -q 'aaaa1111aaaa'
  # Each NEG excluded for a DIFFERENT reason — premise class, venue, authorship. One shared reason
  # would make three assertions into one (memory: positive-control-the-denominator).
  #
  # `[[ != ]]`, NEVER `! … | grep -q`: bats emulates errexit through the ERR trap, and a `!`-negated
  # pipeline suppresses it, so a negated grep DOES NOT FAIL THE TEST (shellcheck SC2314). Measured
  # here 2026-08-25 — with these three written as `! echo "$output" | grep -q …`, flipping one to
  # assert the SUBJECT id was absent still reported `ok`. All three controls were inert and the
  # suite was green over an assertion it had just contradicted.
  [[ "$output" != *bbbb2222bbbb* ]] || false
  [[ "$output" != *cccc3333cccc* ]] || false
  [[ "$output" != *dddd4444dddd* ]] || false
  # exactly one row counted, so the line is not passing on a wider match than it claims
  echo "$output" | grep -q 'reap: 1 LOCAL reap-authored'
}

@test "the report is silent when nothing is stranded, and NEVER writes" {
  : > "$CC_BACKLOG_FILE"
  seed bbbb2222bbbb local cc-backlog-reap "$(render_needs 'persistent thrash')"
  before="$(cat "$CC_BACKLOG_FILE")"

  run bash "$CB" reap
  [ "$status" -eq 0 ]
  # A report that fires on an empty population is a report that carries no information at all.
  # `[[ != ]]` for the SC2314 reason documented in the test above.
  [[ "$output" != *"rest on a premise that has DECAYED"* ]] || false
  # LIVE mode, not --dry-run: the arm must be report-only on the real write path too.
  [ "$(cat "$CC_BACKLOG_FILE")" = "$before" ]
  [ "$(bash "$CB" list --all --json | jq -r '.[]|select(.id=="bbbb2222bbbb")|.status')" = blocked ]
}
