#!/usr/bin/env bats
# land-speed-census.py — the before/after instrument for .claude-plans/LAND_SPEED.md.
#
# Two readings this suite exists to keep from coming back:
#   (1) a stage:"round" row counted as an ATTEMPT. Rounds carry exit 42 and are internal to one
#       land; pooled, the fixture's 2/2 landed reads 2/4 — the brief's "41% landed" error.
#   (2) post_s (the post-push tail) invented when no lock-release row joins. It must be absent,
#       never 0, or a missing join reads as an instantaneous sweep.
# The clock is pinned through LAND_SPEED_NOW, and every stamp is fixed relative to it.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export LAND_SPEED_NOW="2026-09-20T12:00:00Z"
  CENSUS="$BATS_TEST_DIRNAME/../scripts/land-speed-census.py"
  local r='"repo":"/r","branch":"b1"' r2='"repo":"/r","branch":"b2"'
  {
    printf '{"ts":"2026-09-20T10:00:00Z","tool":"ship-land",%s,"stage":"round","exit":42,"total_s":300,"gate_s":290,"gate_rounds":1}\n' "$r"
    printf '{"ts":"2026-09-20T10:10:00Z",%s,"event":"release","wait_s":0,"hold_s":3,"exit":0}\n' "$r"
    printf '{"ts":"2026-09-20T10:20:00Z","tool":"ship-land",%s,"stage":"land","exit":0,"total_s":1300,"gate_s":600,"gate_arms_s":500,"smoke_s":0,"gate_rounds":2}\n' "$r"
    printf '{"ts":"2026-09-20T11:00:00Z","tool":"ship-land",%s,"stage":"land","exit":6,"red":"shellcheck,smoke:tests/x.bats","total_s":100,"gate_s":90,"gate_rounds":1}\n' "$r2"
    printf '{"ts":"2026-09-20T11:00:30Z","tool":"ship-land",%s,"stage":"round","exit":42,"total_s":10,"gate_s":5,"gate_rounds":1}\n' "$r2"
    printf '{"ts":"2026-09-20T11:30:00Z","tool":"ship-land",%s,"stage":"land","exit":0,"total_s":200,"gate_s":150,"gate_arms_s":100,"smoke_s":0,"gate_rounds":1}\n' "$r2"
    printf 'not json\n'
  } > "$LAND_LOG"
}

@test "rounds are not attempts: 2 landed of 3 terminal lands, 2 rounds counted apart" {
  run python3 "$CENSUS" --days 1 --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
w = json.load(sys.stdin)[0]
assert w["lands"] == 3, w["lands"]
assert w["rounds"] == 2, w["rounds"]
assert w["landed"] == 2, w["landed"]
assert w["exit_hist"] == {"0": 2, "6": 1} or w["exit_hist"] == {0: 2, 6: 1}, w["exit_hist"]
assert w["first_round_landed"] == 1
assert w["attempts_per_landed_branch"]["n"] == 2
assert w["attempts_per_landed_branch"]["p90"] == 2       # b2: one red, then landed
'
}

@test "post_s joins the preceding release row, and is ABSENT (not 0) when none joins" {
  run python3 "$CENSUS" --days 1 --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d = json.load(sys.stdin)[0]["landed_decomposition"]
assert d["post_s"]["n"] == 1, d["post_s"]            # b1 joins (600s after its release); b2 has none
assert d["post_s"]["p50"] == 600, d["post_s"]
assert d["pre_s"]["p50"] == 1300 - 600 - 600, d["pre_s"]
'
}

@test "red arms fold smoke:<suite> into the smoke arm" {
  run python3 "$CENSUS" --days 1 --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
a = json.load(sys.stdin)[0]["red_arms"]
assert a == {"shellcheck": 1, "smoke": 1}, a
'
}

@test "--compare splits baseline and post at the cut" {
  run python3 "$CENSUS" --compare 2026-09-20T11:15:00Z --days 1 --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
b, p = json.load(sys.stdin)
assert (b["label"], b["lands"], b["landed"]) == ("baseline", 2, 1), b
assert (p["label"], p["lands"], p["landed"]) == ("post", 1, 1), p
'
  run python3 "$CENSUS" --compare 2026-09-20T11:15:00Z --days 1
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'n < 30 in: baseline, post'
}
