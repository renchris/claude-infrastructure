#!/usr/bin/env bats
# dated-park-arm.sh — the standing watch over DATED PARKS (blocked rows whose precondition is a date).
#
# WHY THIS SUITE EXISTS. The subject's whole job is to stay silent for weeks and then, once, say "a
# parked row's date has arrived". That shape is the one this repo has been burned by twice: a watch
# that can never fire is indistinguishable from one that is merely still waiting, and a park nobody
# watches is an abandonment wearing a disposition's clothes. So the load-bearing cases are the ones
# whose expected verdict is PAGE and the ones whose expected verdict is NON-VERDICT — not the quiet
# "still waiting" case, which almost any wrong implementation also passes.
#
# THE THREE STATES THE SUBJECT MUST KEEP APART:
# EVERY DATE IN THIS SUITE IS IN THE PAST AND "today" IS ALWAYS SUPPLIED EXPLICITLY via
# CC_DATED_PARK_TODAY. A fixture seeded with a FUTURE absolute date silently changes meaning as the
# clock advances and goes red on a calendar boundary with no code change (the wall-clock ratchet
# names the 2026-07-27 fleet outage). Pinning in the past also makes the three NEGATIVES stronger:
# their dates have ALREADY passed, so each is a row that would page if the state/anchor filters
# were wrong, rather than one held back by its date.
#
#   a dated park whose date is today or past   → rc 0   PAGE
#   dated parks exist, none has arrived        → rc 1   keep waiting
#   the ledger is absent / wholly unparseable  → rc 2   NON-VERDICT, never "no signal"
#
# RED-PROOF. Every load-bearing assertion is proved by MUTATION: a copy of the real subject is
# deranged at the exact line the assertion depends on and the verdict must invert. Each mutant is
# asserted to have applied EXACTLY ONCE (a mutant anchored on an absent or non-unique string applies
# to nothing, and the green that follows proves nothing) and to still parse.
#
# NOT RED-PROOFS, and marked so: G1 and the report case are EQUIVALENCE guards.

setup() {
  # Fixture $HOME before anything else. The subject's ledger DEFAULT is
  # "$HOME/.claude/autonomy/backlog.jsonl", so a suite that leaves HOME ambient is one unset
  # CC_BACKLOG_FILE away from reading — and reporting on — the operator's live backlog.
  export HOME="${BATS_TEST_TMPDIR}/home"; mkdir -p "$HOME/.claude/autonomy"
  SUBJECT="${BATS_TEST_DIRNAME}/../scripts/dated-park-arm.sh"
  LED="${BATS_TEST_TMPDIR}/backlog.jsonl"
  # One fixture carrying every discrimination the subject must make. The three NEGATIVES are the
  # point: each is a row a sloppier matcher would page on.
  cat > "$LED" <<'JSON'
{"id":"aaaaaaaaaaaa","event":"add","title":"true dated park","project":"p"}
{"id":"aaaaaaaaaaaa","event":"block","needs":"On or after 2020-01-10, unblock this row and read A6."}
{"id":"bbbbbbbbbbbb","event":"add","title":"mentions a date mid-prose","project":"p"}
{"id":"bbbbbbbbbbbb","event":"block","needs":"Waits on a vendor flag. It was filed On or after 2020-01-01 by a sweep."}
{"id":"cccccccccccc","event":"add","title":"OPEN row carrying the phrase","project":"p"}
{"id":"cccccccccccc","event":"needs","needs":"On or after 2020-01-01, do the thing."}
{"id":"dddddddddddd","event":"add","title":"parked then released","project":"p"}
{"id":"dddddddddddd","event":"block","needs":"On or after 2020-01-01, unblock and proceed."}
{"id":"dddddddddddd","event":"unblock"}
JSON
  export CC_BACKLOG_FILE="$LED"
}

# Copy the subject, derange it at one anchor, assert the mutation applied EXACTLY ONCE and parses.
# LITERAL replacement, never a regex: every anchor below carries regex metacharacters (" ^ [ ( < .),
# and an awk/sed `sub` would either error or silently match something else. A mutant that does not
# apply is a green that proves nothing, so both facts are asserted.
mutate() { # <anchor> <replacement> -> echoes the mutant path
  local mut="${BATS_TEST_TMPDIR}/mutant-${BATS_TEST_NUMBER}.sh"
  MUT_A="$1" MUT_R="$2" MUT_SRC="$SUBJECT" MUT_DST="$mut" python3 - <<'PYMUT' || return 1
import os, sys
a, r = os.environ["MUT_A"], os.environ["MUT_R"]
src = open(os.environ["MUT_SRC"], encoding="utf-8").read()
n = src.count(a)
if n != 1:
    print(f"anchor matched {n}x, need exactly 1: {a!r}", file=sys.stderr); sys.exit(1)
open(os.environ["MUT_DST"], "w", encoding="utf-8").write(src.replace(a, r, 1))
PYMUT
  bash -n "$mut" || { echo "mutant does not parse" >&2; return 1; }
  echo "$mut"
}

# ── G1. EQUIVALENCE GUARD: before any date arrives the watch is silent. ───────────────────────────
@test "G1 no park has arrived -> rc 1, silent" {
  run env CC_DATED_PARK_TODAY=2020-01-05 bash "$SUBJECT" --arm
  [ "$status" -eq 1 ]
  [ -z "$output" ]
}

# ── G2. THE SIGNAL. The date arrives; exactly the true park pages, and the three negatives do not. ─
@test "G2 on the arming date -> rc 0 and ONLY the true park is named" {
  run env CC_DATED_PARK_TODAY=2020-01-10 bash "$SUBJECT" --arm
  [ "$status" -eq 0 ]
  [[ "$output" == *"aaaaaaaaaaaa"* ]] || false
  [[ "$output" != *"bbbbbbbbbbbb"* ]] || false # phrase mid-prose is not a park
  [[ "$output" != *"cccccccccccc"* ]] || false # an OPEN row is not a park
  [[ "$output" != *"dddddddddddd"* ]]   # a released row is not a park
}

# ── G3. "On or after" is INCLUSIVE — the boundary day is the arming day, not the day after. ───────
@test "G3 the arming date itself arms (inclusive boundary)" {
  run env CC_DATED_PARK_TODAY=2020-01-09 bash "$SUBJECT" --arm
  [ "$status" -eq 1 ]
  run env CC_DATED_PARK_TODAY=2020-01-10 bash "$SUBJECT" --arm
  [ "$status" -eq 0 ]
}

# ── G4/G5. NON-VERDICT must never be spent as "no signal". ────────────────────────────────────────
@test "G4 absent ledger -> rc 2, never rc 1" {
  run env CC_BACKLOG_FILE="${BATS_TEST_TMPDIR}/nope.jsonl" CC_DATED_PARK_TODAY=2020-01-10 bash "$SUBJECT" --arm
  [ "$status" -eq 2 ]
}

@test "G5 wholly unparseable ledger -> rc 2, never rc 1" {
  printf 'not json\nalso not json\n' > "${BATS_TEST_TMPDIR}/junk.jsonl"
  run env CC_BACKLOG_FILE="${BATS_TEST_TMPDIR}/junk.jsonl" CC_DATED_PARK_TODAY=2020-01-10 bash "$SUBJECT" --arm
  [ "$status" -eq 2 ]
}

@test "G6 report lists every park with its state" {
  run env CC_DATED_PARK_TODAY=2020-01-05 bash "$SUBJECT" --report
  [ "$status" -eq 1 ]
  [[ "$output" == *"dated parks: 1"* ]] || false
  [[ "$output" == *"waiting 2020-01-10"* ]]
}

# ── M1. RED-PROOF: the match must be START-anchored, or mid-prose dates page. ─────────────────────
# The mutant is `.match` -> `.search`, NOT the removal of the pattern's `^`. Dropping `^` was tried
# first and could not be killed: `re.match` anchors at position 0 by definition, so the two spellings
# are genuinely equivalent and that mutant proves nothing about the assertion. The anchoring lives in
# the METHOD, so that is what this derangement has to reach.
@test "M1 mutant searching instead of matching pages on a mid-prose date" {
  mut="$(mutate 'ANCHOR.match(' 'ANCHOR.search(')"
  run env CC_DATED_PARK_TODAY=2020-01-10 bash "$mut" --arm
  [ "$status" -eq 0 ]
  [[ "$output" == *"bbbbbbbbbbbb"* ]]   # the control G2 forbids exactly this
}

# ── M2. RED-PROOF: the comparison must be inclusive, or the boundary day is missed. ───────────────
@test "M2 mutant using strict < misses the arming day" {
  mut="$(mutate 'if p[0] <= today' 'if p[0] < today')"
  run env CC_DATED_PARK_TODAY=2020-01-10 bash "$mut" --arm
  [ "$status" -eq 1 ]                    # G3's second half inverts
}

# ── M3. RED-PROOF: only BLOCKED rows are parks, or open work pages as parked. ─────────────────────
@test "M3 mutant ignoring the blocked state pages on an open row" {
  mut="$(mutate 'if r.get("st") != "block":' 'if False:')"
  run env CC_DATED_PARK_TODAY=2020-01-10 bash "$mut" --arm
  [ "$status" -eq 0 ]
  [[ "$output" == *"cccccccccccc"* ]]   # G2 forbids exactly this
}

# ── M4. RED-PROOF: an unreadable store must not collapse into the "no" code. ──────────────────────
@test "M4 mutant spending rc 1 on an unreadable ledger hides the blindness" {
  mut="$(mutate '"$LEDGER" >&2; exit 2; }' '"$LEDGER" >&2; exit 1; }')"
  run env CC_BACKLOG_FILE="${BATS_TEST_TMPDIR}/nope.jsonl" CC_DATED_PARK_TODAY=2020-01-10 bash "$mut" --arm
  [ "$status" -eq 1 ]                    # G4 inverts — this is the blindness G4 pins
}

# ── G7. The DEFAULT ledger path is the one the sweep uses with no env set. Reachable only because
# setup() fixtures $HOME; before that this case would have read the operator's live backlog.
@test "G7 with no CC_BACKLOG_FILE the default \$HOME ledger is read" {
  cp "$LED" "$HOME/.claude/autonomy/backlog.jsonl"
  run env -u CC_BACKLOG_FILE CC_DATED_PARK_TODAY=2020-01-10 bash "$SUBJECT" --arm
  [ "$status" -eq 0 ]
  [[ "$output" == *"aaaaaaaaaaaa"* ]]
}
