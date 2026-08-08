#!/usr/bin/env bats
# cycle-time-census — the §8 revisit trigger, and the two ways of reading it BACKWARDS.
#
# The two controls that carry this suite are (5) and (6). Both build a store whose POOLED median sits
# under the threshold while the scheduled-completed median sits well over it, so each one goes RED the
# moment its exclusion is removed from the script. Without them the other tests would still pass
# against a census that simply medians everything — which is exactly the reading that produced the
# filed measurement this script exists to replace.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"          # RULE 1 — fixture HOME
  mkdir -p "$HOME"
  export CC_POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"   # RULE 5 — the non-$HOME seam, pinned
  STAMPS="$CC_POSTLAND_DIR/stamps"
  mkdir -p "$STAMPS"
  CENSUS="$BATS_TEST_DIRNAME/../scripts/cycle-time-census.sh"
  SEQ=0
}

# stamp <verdict> <run_s> <cc>   — cc "unknown" = the launchd lane; anything else = session-invoked.
# The ts is synthetic and strictly increasing; the census only sorts and windows on it, and never
# compares it to a clock, so these cannot age into a different band (test-walltime-lint's class).
stamp() {
  SEQ=$((SEQ + 1))
  printf '{"tree":"t%03d","commit":"c%03d","verdict":"%s","failing":[],"ts":"2026-01-%02dT%02d:00:00Z","run_s":%s,"retries":0,"suites":300,"checks":"bats+bash-n","shellcheck_advisory":0,"env":{"bats":"1.13.0","cc":"%s","load":"9.0"}}\n' \
    "$SEQ" "$SEQ" "$1" "$(( (SEQ / 24) + 1 ))" "$(( SEQ % 24 ))" "$2" "$3" > "$STAMPS/t$(printf '%03d' $SEQ).json"
}

@test "BREACH: the scheduled lane over the threshold opens the trigger" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 11300 unknown; done
  run "$CENSUS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=BREACH"* ]] || false
}

@test "WITHIN: the scheduled lane under the threshold, uncensored, is a pass" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 4000 unknown; done
  run "$CENSUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=WITHIN"* ]] || false
}

@test "NO-VERDICT: a median over too few scheduled runs is not a measurement" {
  for _ in 1 2 3; do stamp red 11300 unknown; done
  run "$CENSUS"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=NO-VERDICT"* ]] || false
}

@test "NO-VERDICT: an absent stamp store abstains rather than passing" {
  rm -rf "$STAMPS"
  run "$CENSUS"
  [ "$status" -eq 3 ]
  [[ "$output" == *"verdict=NO-VERDICT"* ]]
}

@test "CONTROL: non-verdicts must not enter the median (pooled would read WITHIN)" {
  # 10 completed runs at 3.14h — BREACH on its own. Then 14 cuts at 0.1h. A census that medianed
  # every stamp would land at ~0.1h and report WITHIN: a lane collapsing into truncated runs would
  # read as a lane that got fast. This test is the tripwire on that exclusion.
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 11300 unknown; done
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14; do stamp cut 360 unknown; done
  run "$CENSUS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=BREACH"* ]] || false
  [[ "$output" == *"non-verdicts excluded (cut|hung): 14"* ]] || false
}

@test "CONTROL: session-invoked runs must not enter the median (pooled would read WITHIN)" {
  # Same shape, different confound: 10 scheduled runs at 3.14h against 30 hand-run diagnostics at
  # 0.5h. Pooling answers a question nobody asked — the criterion is about the launchd lane.
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 11300 unknown; done
  for _ in $(seq 1 30); do stamp red 1800 claude.exe; done
  run "$CENSUS" --all
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=BREACH"* ]] || false
  [[ "$output" == *"completed runs: 30"* ]] || false # the session population is REPORTED, not merged
}

@test "CENSORED: a sub-threshold median over runs that recorded the bound is unproven, not a pass" {
  # 9 runs at exactly the suite bound would be BREACH, so pull the bound down under the threshold:
  # with SUITE_TO=3600 and runs at 3600s (1h), p50 is under 2h but every run recorded the WALL.
  export POSTLAND_SUITE_TIMEOUT_S=3600
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 3600 unknown; done
  run "$CENSUS"
  [ "$status" -eq 4 ]
  [[ "$output" == *"verdict=CENSORED"* ]] || false
  [[ "$output" == *"UNPROVEN"* ]] || false
}

@test "censoring is reported as a fraction beside the verdict" {
  for _ in 1 2 3 4 5; do stamp red 11300 unknown; done   # >= 10800 bound
  for _ in 1 2 3 4 5; do stamp red 4000  unknown; done   # under it
  run "$CENSUS"
  [[ "$output" == *"censored at the 10800s suite bound: 5/10 (50%)"* ]] || false
}

@test "--window restricts to the newest N stamps" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 11300 unknown; done   # old: breaching
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 3000  unknown; done   # new: fine
  run "$CENSUS" --window 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=WITHIN"* ]] || false
}

@test "--threshold-h moves the trigger, both ways" {
  # 9000s = 2.5h, and deliberately UNDER the 10800s suite bound so censoring cannot confound this —
  # the only variable between the two runs below is the threshold. (An earlier spelling used 11300s
  # and read CENSORED at 4h rather than WITHIN, correctly: every one of those runs had recorded the
  # wall rather than its own work, so "within 4h" was unproven. Kept as a note because it is the
  # distinction the CENSORED state exists to make.)
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 9000 unknown; done
  run "$CENSUS" --threshold-h 4
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=WITHIN"* ]] || false
  run "$CENSUS" --threshold-h 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=BREACH"* ]] || false
}

@test "--json emits the partitioned fields" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 11300 unknown; done
  for _ in 1 2 3; do stamp cut 360 unknown; done
  run "$CENSUS" --json
  [ "$status" -eq 1 ]
  [[ "$output" == *'"verdict": "BREACH"'* ]] || false
  [[ "$output" == *'"scheduled_completed_n": 10'* ]] || false
  [[ "$output" == *'"non_verdicts_excluded": 3'* ]] || false
}

@test "an unparseable stamp is skipped, not fatal" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 11300 unknown; done
  printf 'not json at all' > "$STAMPS/broken.json"
  run "$CENSUS"
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=BREACH"* ]] || false
}

@test "it writes nothing to the stamp store" {
  for _ in 1 2 3 4 5 6 7 8 9 10; do stamp red 11300 unknown; done
  # name+mtime+size of every file, not a hash: `md5` lives in /sbin, which is absent from the
  # nightly-regression plist's PATH (unattended-path-lint's own class — and the defect that reddened
  # cc-queue 23 times). stat(1) is /usr/bin and reachable everywhere.
  before="$(find "$CC_POSTLAND_DIR" -type f -exec stat -f '%N %m %z' {} + | sort)"
  run "$CENSUS" --all
  after="$(find "$CC_POSTLAND_DIR" -type f -exec stat -f '%N %m %z' {} + | sort)"
  [ "$before" = "$after" ]
}

@test "an unknown argument is refused rather than ignored" {
  run "$CENSUS" --nope
  [ "$status" -eq 2 ]
}
