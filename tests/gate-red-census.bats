#!/usr/bin/env bats
# gate-red-census — the four ways of reading the gate-red rate QUIETER than it is.
#
# The controls that carry this suite are the ones whose fixture makes a NAIVE census print a
# different number, not merely a differently-labelled one:
#
#   (1) LOCK ROWS IN THE DENOMINATOR. land.log's lock rows mostly predate the `event` field, so the
#       filter everyone reaches for first — "exclude rows carrying event" — keeps 90 of them. The
#       fixture is built so that reading 5/10 (50%) as 5/100 (5%) is the difference between an
#       emergency and a rounding error.
#   (2) exit 9 POOLED WITH exit 6. exit 9 is GATE-KILLED, a claim about the machine. Pooled, the
#       fixture reads 100%; kept apart it reads 40% with six non-verdicts a reader can subtract.
#   (3) AN UNPARSEABLE ROW DROPPED. Dropping one invocation whose `exit` is unreadable turns 9/10
#       into 9/9 — a shrinking denominator reads as an improving rate.
#   (4) "unattributed" READ AS AN ARM NAME. It is the producer's word for a red NO arm claimed; as
#       an arm it becomes the leading "cause" of gate reds and indicts the tree for the instrument.
#
# Every fixture stamp is seeded RELATIVE to now (test-walltime-lint's class: an absolute future date
# ages across the window boundary it was written to sit inside), and the attribution birthday is
# likewise passed in relative wherever a test depends on which side of it a row falls.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"                 # RULE 1 — fixture HOME
  mkdir -p "$HOME"
  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"         # the non-$HOME seam, pinned
  : > "$LAND_LOG"
  CENSUS="$BATS_TEST_DIRNAME/../scripts/gate-red-census.sh"
}

ago() {  # <hours> -> a UTC stamp that many hours in the PAST. Signed offset: bare `-v 3H` SETS
  date -u -v-"$1"H +%Y-%m-%dT%H:%M:%SZ   # the hour to 3 rather than subtracting 3.
}

# land <hours-ago> <exit> [red] [smoke]
#   red omitted entirely -> the `red` KEY is absent (the pre-2026-08-08 producer)
#   red given as ''      -> "red":"" (no arm went red)
# ${3-} / ${4-} without the colon: an explicitly EMPTY red must stay empty, not fall to the default.
land() {
  local ts red smoke
  ts="$(ago "$1")"
  smoke="${4-none}"
  if [ "$#" -lt 3 ]; then
    printf '{"ts":"%s","tool":"ship-land","repo":"/r","branch":"b","exit":%s,"smoke":"%s"}\n' \
      "$ts" "$2" "$smoke" >> "$LAND_LOG"
  else
    red="${3-}"
    printf '{"ts":"%s","tool":"ship-land","repo":"/r","branch":"b","exit":%s,"smoke":"%s","red":"%s"}\n' \
      "$ts" "$2" "$smoke" "$red" >> "$LAND_LOG"
  fi
}

# An invocation from the pre-schema producer: no `smoke` key at all. Its own helper because `land`
# always emits one, and a fixture that silently supplied "none" here would have made the "absent"
# bucket untestable while looking like it tested it.
land_nosmoke() {
  printf '{"ts":"%s","tool":"ship-land","repo":"/r","branch":"b","exit":%s,"red":""}\n' \
    "$(ago "$1")" "$2" >> "$LAND_LOG"
}

# An invocation whose exit is a STRING. It is still an invocation, so it is still a denominator.
land_badexit() {
  printf '{"ts":"%s","tool":"ship-land","repo":"/r","branch":"b","exit":"six","smoke":"none"}\n' \
    "$(ago "$1")" >> "$LAND_LOG"
}

# The OLD lock schema — no `event` key at all. 1592 of the live store's 1637 lock rows look like
# this, which is exactly why "absent event" is the wrong discriminator.
lock_legacy() {
  printf '{"ts":"%s","repo":"/r","branch":"b","wait_s":0,"hold_s":3,"exit":0,"pid":1}\n' \
    "$(ago "$1")" >> "$LAND_LOG"
}

lock_evented() {
  printf '{"ts":"%s","repo":"/r","branch":"b","event":"release","wait_s":0,"hold_s":3,"exit":0,"depth":0,"pid":2}\n' \
    "$(ago "$1")" >> "$LAND_LOG"
}

@test "CONTROL: lock rows are excluded from the denominator (pooling them reads 5% not 50%)" {
  # 10 invocations, 5 of them gate-red = 50%. Then 90 lock rows, 89 of them in the LEGACY schema
  # that carries no `event` key. A census keying on the absence of `event` computes 5/99 = 5.1%,
  # and a census keying on nothing at all computes 5/100 = 5%. Both read as a healthy pipeline.
  for _ in 1 2 3 4 5; do land 2 6 'shellcheck'; done
  for _ in 1 2 3 4 5; do land 2 0 ''; done
  for _ in $(seq 1 89); do lock_legacy 2; done
  lock_evented 2
  run "$CENSUS" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invocations": 10'* ]] || false
  [[ "$output" == *'"non_invocation_rows": 90'* ]] || false
  [[ "$output" == *'"gate_red": 5'* ]] || false
  [[ "$output" == *'"rate": 0.5'* ]] || false
  run "$CENSUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"50.0%"* ]] || false
  [[ "$output" != *" 5.0%"* ]] || false
}

@test "CONTROL: exit 9 is not pooled into the gate-red rate (pooling reads 100% not 40%)" {
  # exit 9 is GATE-KILLED: the gate died without earning a verdict, so it is not evidence about the
  # tree. Pooled with exit 6 this fixture says every land in the window was refused by its own gate.
  for _ in 1 2 3 4; do land 2 6 'shellcheck'; done
  for _ in 1 2 3 4 5 6; do land 2 9; done
  run "$CENSUS" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"gate_red": 4'* ]] || false
  [[ "$output" == *'"gate_killed": 6'* ]] || false
  [[ "$output" == *'"rate": 0.4'* ]] || false
  [[ "$output" != *'"rate": 1.0'* ]] || false
  run "$CENSUS"
  [[ "$output" == *"40.0%"* ]] || false
}

@test "CONTROL: an unparseable exit stays in the denominator (dropping it reads 100% not 90%)" {
  for _ in 1 2 3 4 5 6 7 8 9; do land 2 6 'shellcheck'; done
  land_badexit 2
  run "$CENSUS" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invocations": 10'* ]] || false
  [[ "$output" == *'"unparseable_exit": 1'* ]] || false
  [[ "$output" == *'"rate": 0.9'* ]] || false
  [[ "$output" != *'"rate": 1.0'* ]] || false
  run "$CENSUS"
  [[ "$output" == *"90.0%"* ]] || false
  [[ "$output" == *"unparseable exit"* ]] || false
}

@test "CONTROL: \"unattributed\" is its own bucket, never an arm in the cause breakdown" {
  # Counted as an arm it would be the single largest named cause here (3 vs shellcheck's 2) — an
  # instrument failure rendered as a property of the tree.
  for _ in 1 2; do land 2 6 'shellcheck'; done
  for _ in 1 2 3; do land 2 6 'unattributed'; done
  run "$CENSUS" --json
  [ "$status" -eq 3 ]
  [[ "$output" == *'"arm": "shellcheck"'* ]] || false
  [[ "$output" != *'"arm": "unattributed"'* ]] || false
  [[ "$output" == *'"unattributed": 3'* ]] || false
  [[ "$output" == *'"attributed": 2'* ]] || false
}

@test "the three red states stay three: named, empty, unattributed" {
  land 2 6 'shellcheck'
  land 2 6 'unattributed'
  land 2 6 ''                       # red:"" on an exit-6 row — self-contradictory, its own bucket
  land 2 0 ''                       # red:"" on a clean land — the ordinary case, not a cause
  run "$CENSUS" --json
  [ "$status" -eq 3 ]
  [[ "$output" == *'"attributed": 1'* ]] || false
  [[ "$output" == *'"unattributed": 1'* ]] || false
  [[ "$output" == *'"empty_on_red": 1'* ]] || false
  [[ "$output" == *'"red_rows": 3'* ]] || false
}

@test "an absent red field before the birthday is instrument-birthday, after it is not" {
  # Assigned then exported separately (SC2155): `export X="$(cmd)"` masks the command's exit
  # status behind export's own 0, so a broken `ago` would seed an empty birthday and the test
  # would still run — measuring nothing.
  local birthday
  birthday="$(ago 6)"                                # relative: no wall-clock time bomb
  export GATE_RED_ATTRIB_BIRTHDAY="$birthday"
  land 10 6                                          # 10h ago: before the field existed
  land 8  6                                          # 8h ago:  before the field existed
  land 2  6                                          # 2h ago:  after it — a stale producer
  land 1  6 'shellcheck'
  run "$CENSUS" --json
  [ "$status" -eq 3 ]
  [[ "$output" == *'"instrument_birthday": 2'* ]] || false
  [[ "$output" == *'"field_absent_post_birthday": 1'* ]] || false
  [[ "$output" == *'"attributed": 1'* ]] || false
  # Coverage is priced against the ATTRIBUTABLE population, not against all reds: 1 of 2, not 1 of 4.
  [[ "$output" == *'"attributable": 2'* ]] || false
}

@test "a multi-arm red counts once per arm, and the panel says so" {
  land 2 6 'shellcheck,hermeticity'
  land 2 6 'shellcheck'
  run "$CENSUS"
  [ "$status" -eq 3 ]
  [[ "$output" == *"2 gate-reds, 3 arm-mentions"* ]] || false
  [[ "$output" == *"NOT a partition"* ]] || false
}

@test "an arm subject is folded into its arm, and a truncated tail is not minted as an arm" {
  land 2 6 'smoke:tests/a.bats,smoke:tests/b.bats'
  land 2 6 'shellcheck,dead-asser+truncated'
  run "$CENSUS" --json
  [ "$status" -eq 3 ]
  [[ "$output" == *'{"arm": "smoke", "n": 2}'* ]] || false
  [[ "$output" != *'"arm": "dead-asser"'* ]] || false
  [[ "$output" == *'"truncated": 1'* ]] || false
  [[ "$output" == *'"subject": "smoke:tests/a.bats"'* ]] || false
}

@test "a line that is not JSON is counted OUTSIDE the population, never dropped in silence" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do land 2 6 'shellcheck'; done
  printf 'not json at all\n' >> "$LAND_LOG"
  printf '{"ts":"broken\n' >> "$LAND_LOG"
  run "$CENSUS" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"unparseable_json_lines": 2'* ]] || false
  [[ "$output" == *'"invocations": 10'* ]] || false
}

@test "--window restricts to the newest N invocations" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do land 5 6 'shellcheck'; done   # older: all red
  for _ in 1 2 3 4 5 6 7 8 9 10; do land 1 0 ''; done             # newer: all clean
  run "$CENSUS" --json --window 10
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invocations": 10'* ]] || false
  [[ "$output" == *'"gate_red": 0'* ]] || false
}

@test "--days bounds the population and reports that single window" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do land 100 6 'shellcheck'; done  # ~4d ago
  for _ in 1 2 3 4 5 6 7 8 9 10; do land 2   0 ''; done
  run "$CENSUS" --json --days 1
  [ "$status" -eq 0 ]
  [[ "$output" == *'"invocations": 10'* ]] || false
  [[ "$output" == *'"gate_red": 0'* ]] || false
  [[ "$output" == *'"label": "1d"'* ]] || false
  [[ "$output" != *'"label": "14d"'* ]] || false
}

@test "the trailing windows are reported side by side and the trend is named" {
  for _ in $(seq 1 10); do land 200 6 'shellcheck'; done  # >3d, inside 14d: 10 red
  for _ in $(seq 1 10); do land 200 0 ''; done            #                  10 clean -> 50%
  for _ in $(seq 1 10); do land 2  6 'shellcheck'; done   # inside 1d:       10 red -> 100%
  run "$CENSUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"trend=RISING"* ]] || false
  [[ "$output" == *"100.0%"* ]] || false
  [[ "$output" == *"66.7%"* ]] || false   # 20/30 over 14d
}

@test "trend abstains rather than moving a rate on a thin window" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do land 200 6 'shellcheck'; done
  land 2 0 ''                                   # a single land inside 1d cannot establish a trend
  run "$CENSUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"trend=NO-VERDICT"* ]] || false
}

@test "NO-VERDICT: too few invocations to compute a rate" {
  for _ in 1 2 3; do land 2 6 'shellcheck'; done
  run "$CENSUS"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=NO-VERDICT"* ]] || false
  [[ "$output" == *"not a measurement"* ]] || false
}

@test "NO-VERDICT: an absent store abstains rather than reporting a 0% rate" {
  rm -f "$LAND_LOG"
  run "$CENSUS"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=NO-VERDICT"* ]] || false
  [[ "$output" == *"an absence, not a zero rate"* ]] || false
}

@test "the smoke distribution carries the headline's own evidence, absent field kept apart" {
  for _ in 1 2 3 4 5 6; do land 2 6 'shellcheck' 'none'; done
  for _ in 1 2; do land 2 0 '' 'skipped'; done
  land 2 0 '' 'green'
  land 2 6 'smoke:tests/a.bats' 'red'
  land_nosmoke 2 0                               # no smoke key at all (the pre-schema producer)
  run "$CENSUS" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"none": 6'* ]] || false
  [[ "$output" == *'"skipped": 2'* ]] || false
  [[ "$output" == *'"absent": 1'* ]] || false
  [[ "$output" == *'"smoke_quiet_n": 8'* ]] || false
  [[ "$output" == *'"smoke_field_carried": 10'* ]] || false
}

@test "the exit histogram shows every code, not only 6" {
  for _ in 1 2 3 4 5 6; do land 2 0 ''; done
  for _ in 1 2 3; do land 2 6 'shellcheck'; done
  land 2 3 ''
  land 2 143 ''
  run "$CENSUS" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"0": 6'* ]] || false
  [[ "$output" == *'"6": 3'* ]] || false
  [[ "$output" == *'"3": 1'* ]] || false
  [[ "$output" == *'"143": 1'* ]] || false
}

@test "--json is one object and carries the same verdict as the panel" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do land 2 6 'shellcheck'; done
  run "$CENSUS" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"verdict": "MEASURED"'* ]] || false
  run bash -c 'printf "%s" "$1" | python3 -c "import json,sys; json.load(sys.stdin)"' _ "$output"
  [ "$status" -eq 0 ]
}

@test "it writes nothing to the store" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do land 2 6 'shellcheck'; done
  # name+mtime+size, not a hash: `md5` lives in /sbin, absent from the nightly-regression plist PATH.
  before="$(stat -f '%N %m %z' "$LAND_LOG")"
  run "$CENSUS"
  [ "$status" -eq 0 ]
  after="$(stat -f '%N %m %z' "$LAND_LOG")"
  [ "$before" = "$after" ]
}

@test "an unknown argument is refused rather than ignored" {
  run "$CENSUS" --nope
  [ "$status" -eq 2 ]
}

@test "a non-numeric --days is refused rather than silently emptying the window" {
  run "$CENSUS" --days notanumber
  [ "$status" -eq 2 ]
}
