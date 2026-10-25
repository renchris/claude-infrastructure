#!/usr/bin/env bats
# lever-verdicts.bats — the usage levers' statistics, guards and verdicts (docs/plans/USAGE_LEVERS.md
# § W7+ §2 "Common to all four levers", "Shared guards", "Plumbing gate"; §3 "Scorer"; wave S5):
# bin/cc-lever-score score|aa|report|failures|guards over scripts/lib/{lever_stats,lever_guards}.py
# and the pre-registration config/levers.json.
#
# Contracts held here, at the CLI boundary over a seeded synthetic fleet (tests/fixtures/lever-score/
# mkfleet.py plants a known D3 effect and prints the truth) and at the library boundary for the ports:
#   · the stats ports reproduce the plan's own numbers (MDE 2.85/1.48/14.36/2.55 pp/wk, T3 false-trip
#     0.27/0.67/4.1%, Wilson n 16/25/6, HP ×1.37) and Newcombe's published example
#   · a planted effect is recovered within 15% and reads stat ADVANCE; no effect never ADVANCEs; a
#     planted harm REVERTs; plumbing (here only the check S11/S12 builds) holds the final verdict
#   · Haybittle-Peto: KEEP before the first look, |z| 3.0 at an interim look, 1.96 at the final
#   · the pseudo-salt A/A has an FPR inside [2%, 8%] on synthetic nulls; without a qualifying S0 A/A
#     an S2 lever is offline-only
#   · Holm step-down; a planted tool-error harm breaches T1 and exits 1, equal rates exit 0
#   · failures and score refuse the sealed test split; a moved thresholds pin refuses score
#   · guards read no transcript (identical with the roots emptied) and finish under 60 s
# RED-proof: (a) file-absence: before S5 every verb here exited 3 ("wave S5 owns it"). (b) earlier
# cuts of this wave, run by hand 2026-10-25 on the test 2 fleet: an A/A over all events (treated
# ones included) failed test 2's plumbing list (bootstrap vs A/A 33% apart); D3/D4 session arms by
# "any treated event" with no control floor read guard BREACH on T4 (test 2's .guard == "OK").

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd -P)"
  CLI="$REPO/bin/cc-lever-score"
  FX="$BATS_TEST_TMPDIR/fx"
  NOW=1791072000
  export HOME="$FX/home" CC_LEVER_STATE_DIR="$FX/state" CC_LEVER_LOG_DIR="$FX/logs" \
         CC_LAND_LOG="$FX/land.jsonl" CC_NOW="$NOW" CC_TOKEN_LEDGER_WORKERS=1
  unset CC_LEVER_ALL CC_LEVER_D1 CC_LEVER_D2 CC_LEVER_D3 CC_LEVER_D4 CC_LEVER_EXCLUDE CC_MODEL_CONFIG \
        CC_IRS CC_WORKFLOW_SHADOW CC_IDLE_KEEPALIVE CC_SUBAGENT_LONG_BASH
}

fleet() { mkdir -p "$FX" && /usr/bin/python3 -I "$REPO/tests/fixtures/lever-score/mkfleet.py" "$FX" "$NOW" "$@"; }
s() { /usr/bin/python3 -I "$CLI" "$@"; }
d3() { s score --lever D3 --json 2>/dev/null; }

@test "stats ports reproduce the plan's numbers and Newcombe's published example" {
  run /usr/bin/python3 -I -c '
import math, sys
sys.path.insert(0, sys.argv[1])
import lever_stats as s
d4sd = 2.63 / (2 * s.ZPOW * math.sqrt(932))
lam = lambda p: 0.087 / 100 * 863.5 * p
print("%.2f %.2f %.2f %.2f" % (s.mde(0.0358, 906, 4, r2=0.11), s.mde(0.0358, 906, 1, r2=0.94),
                               s.mde(0.4028, 162, 4), s.mde(d4sd, 932, 1, r2=0.06)))
trips = [(0.1, 2), (0.5, 3), (1.0, 3)]
print("%.2f %.2f %.1f" % tuple(100 * s.poisson_sf(k, lam(p)) for p, k in trips))
print(s.wilson_n_min(0.8, 1.0), s.wilson_n_min(0.8, 0.95), s.wilson_n_min(0.6, 1.0), "%.2f" % s.hp_mde_factor())
d, lo, hi = s.newcombe(56, 70, 48, 80)
print("%.4f %.4f" % (lo, hi), s.hp_bound(1, 3), s.hp_bound(3, 3))' "$REPO/scripts/lib"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # §2 D3 "2.85 pp/wk at 28 d", "1.48 ... at 1 wk" [C]; §1 D1 "14.4"; §4 D4 1-wk 2.55; §2 T3 false-trip
  # 0.27/0.67/4.1%; D2/D4 Wilson n >= 16 / 25 / 6; §2 interim x1.37; Newcombe (1998) method 10 example
  [ "$output" = "2.85 1.48 14.36 2.55
0.27 0.67 4.1
16 25 6 1.37
0.0524 0.3339 3.0 1.959964" ] || { echo "$output"; false; }
}

@test "score recovers a planted D3 effect: stat ADVANCE at the d14 look, plumbing holds the verdict" {
  truth="$(fleet --effect 0.5)"
  planted="$(printf '%s' "$truth" | jq -r .planted_pp_wk)"
  r="$(d3)"
  [ "$(printf '%s' "$r" | jq -r .stat_verdict)" = ADVANCE ] || { echo "$r"; false; }
  printf '%s' "$r" | jq -e --argjson p "$planted" \
    '(.estimate.pp_wk - $p | fabs) <= 0.15 * $p and .estimate.ci_lo[0] > 0 and .estimate.ci_hi[0] > 0
     and .look.k == 2 and .look.z == 3.0 and .guard == "OK" and .cuped.covariate == "ctx"' >/dev/null \
    || { echo "planted $planted: $r"; false; }
  # every other plumbing check passes on this fleet; the one left is built by S11/S12
  [ "$(printf '%s' "$r" | jq -c .plumbing)" = '["no-data:treatment exposure >= 80%"]' ] || { echo "$r"; false; }
  [ "$(printf '%s' "$r" | jq -r .verdict)" = PLUMBING ] || false
  # the D4 population gate (3 would-deny calls) parks it
  [ "$(s score --lever D4 --json 2>/dev/null | jq -r .verdict)" = PARK ] || false
}

@test "no effect never ADVANCEs (CI spans 0); a planted harm REVERTs" {
  fleet --effect 0 >/dev/null
  r="$(d3)"
  printf '%s' "$r" | jq -e '.stat_verdict == "KEEP" and .estimate.ci_lo[0] < 0 and .estimate.ci_lo[1] > 0' >/dev/null \
    || { echo "$r"; false; }
  FX="$BATS_TEST_TMPDIR/harm" CC_LEVER_STATE_DIR="$BATS_TEST_TMPDIR/harm/state" \
    CC_LEVER_LOG_DIR="$BATS_TEST_TMPDIR/harm/logs" HOME="$BATS_TEST_TMPDIR/harm/home" \
    CC_LAND_LOG="$BATS_TEST_TMPDIR/harm/land.jsonl"
  export FX CC_LEVER_STATE_DIR CC_LEVER_LOG_DIR HOME CC_LAND_LOG
  fleet --effect -0.5 >/dev/null
  r="$(d3)"
  printf '%s' "$r" | jq -e '.stat_verdict == "REVERT" and .estimate.ci_lo[1] < 0' >/dev/null || { echo "$r"; false; }
}

@test "Haybittle-Peto: KEEP before d7, |z| 3.0 at the d7 interim, 1.96 and NOT-MERGED at the final" {
  fleet --day 5 >/dev/null
  r="$(d3)"
  printf '%s' "$r" | jq -e '.stat_verdict == "KEEP" and .look.k == 0 and (.reasons[0] | startswith("before the first look"))' \
    >/dev/null || { echo "$r"; false; }
  for day in 10 29; do
    d="$BATS_TEST_TMPDIR/d$day"
    FX="$d" CC_LEVER_STATE_DIR="$d/state" CC_LEVER_LOG_DIR="$d/logs" HOME="$d/home" CC_LAND_LOG="$d/land.jsonl"
    export FX CC_LEVER_STATE_DIR CC_LEVER_LOG_DIR HOME CC_LAND_LOG
    if [ "$day" = 10 ]; then fleet --day 10 >/dev/null; else fleet --day 29 --effect 0 >/dev/null; fi
    r="$(d3)"
    if [ "$day" = 10 ]; then
      printf '%s' "$r" | jq -e '.look.k == 1 and .look.of == 3 and .look.z == 3.0' >/dev/null || { echo "$r"; false; }
    else
      printf '%s' "$r" | jq -e '.look.k == 3 and .look.z == 1.959964 and .stat_verdict == "NOT-MERGED"' >/dev/null \
        || { echo "$r"; false; }
    fi
  done
}

@test "pseudo-salt A/A: FPR in [2%, 8%] on synthetic nulls; no qualifying S0 A/A makes S2 offline-only" {
  run /usr/bin/python3 -I -c '
import random, sys
sys.path.insert(0, sys.argv[1])
import lever_stats as s
hits = runs = 0
for seed in range(1, 6):
    rng = random.Random(seed); units = []
    for c in range(400):
        base = rng.lognormvariate(0, 0.5)
        for e in range(rng.randrange(1, 6)):
            units.append((c % 4, c, "%d:%d" % (c, e), base + rng.gauss(0, 1)))
    r = s.pseudo_salt_aa(units, 200, salt="null-%d" % seed)
    hits += r["hits"]; runs += r["runs"]
print("%.4f %d" % (hits / float(runs), runs))' "$REPO/scripts/lib"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  fpr="${output%% *}"
  [ "${output##* }" -eq 1000 ] || { echo "$output"; false; }
  awk -v f="$fpr" 'BEGIN { exit !(f >= 0.02 && f <= 0.08) }' || { echo "FPR $fpr"; false; }
  fleet --no-aa >/dev/null
  r="$(d3)"
  printf '%s' "$r" | jq -e '.stat_verdict == "KEEP" and (.reasons[0] | startswith("offline-only"))' >/dev/null \
    || { echo "$r"; false; }
  run s aa --lever D3 --json
  [ "$status" -eq 0 ] || false
  printf '%s' "$output" | jq -e '.kind == "aa" and .status == "ok" and .band_ok and .online_ok' >/dev/null \
    || { echo "$output"; false; }
}

@test "Holm steps down; a planted T1 harm breaches (exit 1), equal rates do not (exit 0)" {
  run /usr/bin/python3 -I -c '
import sys
sys.path.insert(0, sys.argv[1])
import lever_stats as s
print(sorted(k for k, v in s.holm({"a": 0.009, "b": 0.009, "c": 0.5}, 0.01).items() if v),
      sorted(k for k, v in s.holm({"a": 0.001, "b": 0.004, "c": 0.5}, 0.01).items() if v))' "$REPO/scripts/lib"
  [ "$output" = "[] ['a', 'b']" ] || { echo "$output"; false; }
  mkdir -p "$CC_LEVER_LOG_DIR" "$CC_LEVER_STATE_DIR"
  for r in .claude .claude-secondary .claude-tertiary .claude-quaternary; do mkdir -p "$HOME/$r/projects"; done
  cp "$REPO/tests/fixtures/lever-score/state/flags.json" "$CC_LEVER_STATE_DIR/"
  for rate in 9 3; do
    /usr/bin/python3 -I -c '
import json, random, sys
rng = random.Random(5); hi = int(sys.argv[1])
for i in range(120):
    arm = "treat" if i % 2 else "ctrl"
    errs = sum(1 for _ in range(100) if rng.random() < (hi if arm == "treat" else 3) / 100.0)
    print(json.dumps({"kind": "ledger", "sid": "s%03d" % i, "acct": "a%d" % (i % 4), "eval": False,
                      "last_ts": "2026-10-03T12:00:00", "arms": {"D1": {"arm": arm}}, "responses": 100,
                      "tool_errors": errs, "lands": {"ok": 1, "failed": 0, "unknown": 0},
                      "ptl": {"death": False}, "first_arm": {}}))' "$rate" > "$CC_LEVER_LOG_DIR/lever-ledger.jsonl"
    : > "$CC_LEVER_LOG_DIR/claude-crashes.jsonl"
    run s guards --json
    if [ "$rate" = 9 ]; then
      [ "$status" -eq 1 ] || { echo "$output"; false; }
      printf '%s\n' "$output" | jq -e 'select(.lever == "D1") | .verdict == "BREACH" and .guards.T1.status == "breach"' \
        >/dev/null || { echo "$output"; false; }
    else
      [ "$status" -eq 0 ] || { echo "$output"; false; }
      printf '%s\n' "$output" | jq -e 'select(.lever == "D1") | .verdict == "OK"' >/dev/null || { echo "$output"; false; }
    fi
  done
}

@test "the sealed test split: failures and score refuse it (exit 3); failures reads train" {
  fleet >/dev/null
  run s failures --split test
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"train split only"* ]] || false
  run s score --split test --lever D3
  [ "$status" -eq 3 ] || false
  [[ "$output" == *"needs --unseal"* ]] || false
  run s failures --split train --lever D3
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == "D3: "*" treated train event(s)"* ]] || { echo "$output"; false; }
}

@test "thresholds sha: a pin config/levers.json no longer matches refuses score; the matching pin scores" {
  fleet >/dev/null
  sha="$(shasum -a 256 "$REPO/config/levers.json" | cut -d' ' -f1)"
  f="$CC_LEVER_STATE_DIR/flags.json"
  jq --arg s "$sha" '.levers.D3.thresholds_sha = $s' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  run s score --lever D3 --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  jq '.levers.D3.thresholds_sha = "0000000000000000000000000000000000000000000000000000000000000000"' "$f" > "$f.tmp" \
    && mv "$f.tmp" "$f"
  run s score --lever D3 --json
  [ "$status" -eq 3 ] || { echo "$output"; false; }
  [[ "$output" == *"changed mid-stage"* ]] || false
}

@test "score --write: one verdict row per lever under 2 KB, the ledger merged; guards read no transcript, < 60 s" {
  fleet >/dev/null
  run s score --write
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$(jq -r 'select(.kind == "score") | .lever' "$CC_LEVER_LOG_DIR/lever-score.jsonl" | tr '\n' ' ')" = "D1 D2 D3 D4 " ] || false
  [ "$(awk 'length($0) >= 2048' "$CC_LEVER_LOG_DIR/lever-score.jsonl" | wc -l | tr -d ' ')" -eq 0 ] || false
  [ "$(s report --json | jq -r '.D3.score.stat_verdict')" = ADVANCE ] || false
  [ -s "$CC_LEVER_LOG_DIR/lever-ledger.jsonl" ] || false
  t0=$SECONDS
  run s guards --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  before="$output"
  printf '%s\n' "$before" | jq -e 'select(.lever == "D3") | .verdict == "OK"' >/dev/null || { echo "$before"; false; }
  for r in .claude .claude-secondary .claude-tertiary .claude-quaternary; do
    mv "$HOME/$r/projects" "$HOME/$r/projects.gone" && mkdir "$HOME/$r/projects"
  done
  run s guards --json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ "$output" = "$before" ] || { diff <(printf '%s\n' "$before") <(printf '%s\n' "$output"); false; }
  [ $((SECONDS - t0)) -lt 60 ] || false
}
