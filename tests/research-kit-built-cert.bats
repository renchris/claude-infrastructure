#!/usr/bin/env bats
# research-kit-built-cert — method v1.2, REPORT.md §11: the built certificate states BOTH halves of
# the forecast (lib/built_cert.py). Before implementation signoff is observed; after it is a
# forecast from the harness's first-pass mutant kill rate, with a Wilson lower bound for the 95%
# figure, and the assumed build-findable share never tightens a bound.

setup() {
  unset CC_BATS_ACTIVE
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CC_RESEARCH_HOME="$BATS_TEST_TMPDIR/research"
  export CC_RESEARCH_REGISTRY="$CC_RESEARCH_HOME/programs.json"
  export CC_RESEARCH_RECORDS="$BATS_TEST_TMPDIR/records"
  export CC_RESEARCH_CALIBRATION="$BATS_TEST_TMPDIR/calibration.jsonl"
  CC_NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  export CC_NOW
  mkdir -p "$CC_RESEARCH_RECORDS/cert" "$CC_RESEARCH_RECORDS/built" "$CC_RESEARCH_HOME"
  /usr/bin/python3 - "$CC_RESEARCH_RECORDS" "$CC_NOW" <<'PY'
import json, sys
rec, now = sys.argv[1:3]
json.dump({"profile": "lite", "method_version": "1.2"}, open(f"{rec}/frame.json", "w"))
json.dump({"cert": "CERT-v1", "issued": now, "changes_at_issue": [],
           "forecast": {"desk_mean": 6.0, "desk_n95": 9, "invisible_mean": 0.5, "invisible_bound95": 2,
                        "before_impl_mean": 3.8, "after_impl_mean": 2.7, "after_impl_bound95": 11,
                        "build_findable_share": 0.585}}, open(f"{rec}/cert/CERT-v1.json", "w"))
json.dump({"snapshot_sha": "abc123", "artifact_root": "/nowhere"}, open(f"{rec}/built/freeze.json", "w"))
# 20 mutants the harness could kill: 18 killed at first pass, 2 only after a harness fix
ms = [{"id": f"M-{i}", "status": "killed", "killed_by": ["AM-1"], "rerun": 0 if i <= 18 else 1}
      for i in range(1, 21)] + [{"id": "M-21", "status": "invalid", "killed_by": [], "rerun": 0}]
json.dump({"snapshot_sha": "abc123", "baseline_exit": 0, "mutants": ms, "killed": 20, "survived": 0},
          open(f"{rec}/built/mutation.json", "w"))
with open(f"{rec}/built/findings.jsonl", "w") as fh:
    for i in range(1, 5):
        fh.write(json.dumps({"id": f"BF-{i}", "severity": "material", "status": "fixed"}) + "\n")
    fh.write(json.dumps({"id": "BF-5", "severity": "material", "status": "rejected-no-repro"}) + "\n")
    fh.write(json.dumps({"id": "BF-6", "severity": "cosmetic", "status": "open"}) + "\n")
# one counted change after the research certificate was issued
open(f"{rec}/changes.jsonl", "w").write(json.dumps({"id": "CH-1", "cause": "escape", "status": "applied"}) + "\n")
PY
}

# py <code>: built_cert importable, with a Ctx over the fixture records.
py() {
  /usr/bin/python3 -c "
import json, sys
for p in ('$REPO/scripts/research-kit/lib', '$REPO/scripts/lib', '$REPO/scripts/research-kit'): sys.path.insert(0, p)
import built_cert as b, gate, kit
ctx = gate.make_ctx('demo')
rows = [gate.Row(n, 'r', gate.PASS) for n in range(20, 26)]
$1"
}

@test "the after-implementation forecast reproduces by hand" {
  # 4 material, 18 of 20 killed: 4 x 0.1/0.9 = 0.444, plus (1 - 0.585) x 0.5 = 0.2075 -> 0.65.
  # Wilson lower bound of 18/20 is 0.699: 4 x 0.301/0.699 = 1.72, plus the invisible bound 2 -> ceil 4.
  run py "
e = b.after_impl(4, 18, 20, 0.5, 2, 0.585)
print(e['after_mean'], e['after_bound95'], e['kill_rate'], round(b.kill_rate_lower95(18, 20), 3))"
  [ "$status" -eq 0 ]
  [ "$output" = "0.65 4 0.9 0.699" ]
}

@test "no mutant killed, or no mutant at all, refuses the forecast instead of dividing by zero" {
  run py "
for killed, total in ((0, 20), (0, 0)):
    try:
        b.after_impl(4, killed, total, 0.5, 2, 0.585)
    except kit.KitError as e:
        print('REFUSED', 'cannot be stated' in str(e))"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "REFUSED True" ]
  [ "${lines[1]}" = "REFUSED True" ]
}

@test "the assumed share moves the mean and never tightens the 95% bound" {
  run py "
lo, hi = b.after_impl(4, 18, 20, 0.5, 2, 0.1), b.after_impl(4, 18, 20, 0.5, 2, 0.9)
print(lo['after_mean'] > hi['after_mean'], lo['after_bound95'] == hi['after_bound95'])"
  [ "$output" = "True True" ]
}

@test "a mutant killed only after a harness fix counts as missed at first pass" {
  run py "print(b.first_pass(ctx.json('built/mutation.json')))"
  [ "$output" = "{'killed': 18, 'total': 20}" ]
}

@test "the built certificate states both halves of the forecast, in the record and in words" {
  run py "print(b.write_built_certificate(ctx, rows))"
  [ "$status" -eq 0 ]
  c="$CC_RESEARCH_RECORDS/built/BUILT-CERT-v1.json"
  [ "$output" = "$c" ]
  # before: 1 counted change since the research signoff + 4 material findings
  [ "$(/usr/bin/python3 -c "import json; c=json.load(open('$c')); f=c['forecast']; print(f['before_observed'], f['before_forecast'], f['after_mean'], f['after_bound95'], f['share'], f['assumed'], c['findings'], c['rows']['25'], c['research_cert'], c['snapshot_sha'])")" \
    = "5 3.8 0.65 4 0.585 ['build_findable_share'] {'fixed': 4, 'material': 4, 'rejected_no_repro': 1} PASS CERT-v1 abc123" ]
  grep -qx 'Before implementation signoff: 5 material changes observed (forecast about 3.8)' "${c%.json}.md"
  grep -q '^After implementation signoff: forecast about 0.7; at most 4 at 95% (mutant kill rate 18 of 20, lower bound 0.70; build-findable share 0.585, share assumed)$' "${c%.json}.md"
}

@test "a second built certificate is version 2 and leaves version 1 in place" {
  run py "b.write_built_certificate(ctx, rows); print(b.write_built_certificate(ctx, rows))"
  [ "$status" -eq 0 ]
  [ -f "$CC_RESEARCH_RECORDS/built/BUILT-CERT-v1.json" ]
  [ "$output" = "$CC_RESEARCH_RECORDS/built/BUILT-CERT-v2.json" ]
}

@test "a research certificate from method 1.1 has no before-forecast, and the certificate says so" {
  /usr/bin/python3 -c "import json; p='$CC_RESEARCH_RECORDS/cert/CERT-v1.json'; c=json.load(open(p)); [c['forecast'].pop(k) for k in ('before_impl_mean','after_impl_mean','after_impl_bound95','build_findable_share')]; json.dump(c, open(p,'w'))"
  run py "b.write_built_certificate(ctx, rows)"
  [ "$status" -eq 0 ]
  grep -q 'observed (no forecast: the research certificate predates method 1.2)' "$CC_RESEARCH_RECORDS/built/BUILT-CERT-v1.md"
}

@test "the certificate is refused without the mutation run, and without a research certificate" {
  rm "$CC_RESEARCH_RECORDS/built/mutation.json"
  run py "
try:
    b.write_built_certificate(ctx, rows)
except kit.KitError as e:
    print('REFUSED', 'mutation run' in str(e))"
  [ "$output" = "REFUSED True" ]
  rm "$CC_RESEARCH_RECORDS/cert/CERT-v1.json"
  run py "
try:
    b.write_built_certificate(ctx, rows)
except kit.KitError as e:
    print('REFUSED', 'no research certificate' in str(e))"
  [ "$output" = "REFUSED True" ]
  run compgen -G "$CC_RESEARCH_RECORDS/built/BUILT-CERT*"
  [ "$status" -ne 0 ]
}
