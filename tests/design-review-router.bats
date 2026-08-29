#!/usr/bin/env bats
# design-review-router — the routing law of bench/route.py, executed rather than described.
#
# WHY THIS SUITE EXISTS AT ALL. The perception bench (bench/detect_dom.py,
# bench/detect_xcheck.py, bench/fp_budget.py) needs numpy, Pillow and a Chromium, and a
# landing gate that has to provision those in order to check anything is a gate that gets
# skipped. bench/route.py is deliberately stdlib-only for that reason -- it is the stage
# that decides what earns a model call, which is the stage whose mistakes cost money and
# credibility, and it must therefore be the one stage a bare `python3` can prove.
#
# The proof that matters is the POSITIVE CONTROL inside `route.py --selftest`: every
# assertion that the router does NOT route something is paired with the case that makes it
# route. A subtraction test with nothing to subtract passes whether or not the subtraction
# exists (memory: control-must-replay-the-real-artifact), and this router's whole value is
# a subtraction -- the abstentions a NumPy cross-check already answered never reach a model.
#
# The mutation checks below are the second half of that: they edit a copy of the router,
# assert the selftest goes RED, and restore. A green selftest over an un-mutated file only
# says the file agrees with itself.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  R="$REPO/bench/route.py"
  P="$REPO/bench/profiles.json"
}

@test "the router is stdlib-only, so the gate can run it with no perception stack" {
  run grep -nE '^(import|from) ' "$R"
  [ "$status" -eq 0 ]
  # numpy/PIL/playwright are the bench's heavy deps; none may reach this stage.
  ! grep -qE '^(import|from) +(numpy|PIL|playwright)' "$R"
}

@test "the routing law holds" {
  run python3 "$R" --selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"ok -- route.py selftest"* ]]
}

# --- the selftest is not vacuous: each law, broken, must turn it red ----------------
mutate() {   # $1 = sed expression; prints the selftest exit code
  cp "$R" "$BATS_TEST_TMPDIR/route.py"
  cp "$P" "$BATS_TEST_TMPDIR/profiles.json"
  sed -i.bak "$1" "$BATS_TEST_TMPDIR/route.py"
  ! cmp -s "$BATS_TEST_TMPDIR/route.py" "$R" || { echo "mutation matched nothing: $1"; return 99; }
  python3 "$BATS_TEST_TMPDIR/route.py" --selftest >/dev/null 2>&1
}

@test "RED-proof: deleting the abstention subtraction fails the selftest" {
  run mutate 's|hit = answered.get(key)|hit = None|'
  [ "$status" -eq 1 ]
}

@test "RED-proof: collapsing by target instead of by class fails the selftest" {
  run mutate 's|by_class.setdefault(a.get("abstains_as", a\["rule"\]), \[\])|by_class.setdefault(a["target"], [])|'
  [ "$status" -eq 1 ]
}

@test "RED-proof: letting a weight raise a severity fails the selftest" {
  run mutate 's|item\["severity"\] = demote(f\["severity"\])|item["severity"] = "high"|'
  [ "$status" -eq 1 ]
}

# --- the two prohibitions that keep the substrates apart ---------------------------
@test "every routed item carries its prohibition and its question" {
  run python3 - "$R" <<'PY'
import json, pathlib, sys, importlib.util
spec = importlib.util.spec_from_file_location("route", sys.argv[1])
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
prof = m.load_profile(pathlib.Path(sys.argv[1]).parent / "profiles.json", "default")
out = m.route_page(m._SNAP, [m._f("contrast-indeterminate", "div.hero > p.a")], [], prof)
assert out["routed"], "expected one routed item"
for item in out["routed"]:
    assert item["prohibition"] and "number" in item["prohibition"].lower()
    assert item["question"]
    assert item["crop_source"].startswith("getBoundingClientRect")
assert out["gestalt"]["blind"] is True
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "no profile can promote a judgement finding into a pass/fail verdict" {
  # The June 2026 ruling, mechanically: nothing in the queue may carry an ASSERTED
  # verdict that came from the model side, and no profile key may name a gate.
  run python3 -c "
import json,sys
p=json.load(open('$P'))
for name,prof in p.items():
    if name=='_doc': continue
    assert 'gate' not in json.dumps(prof).lower(), name
    g=prof.get('gestalt',{})
    assert set(g) <= {'enabled','weight'}, (name, sorted(g))
print('ok')"
  [ "$status" -eq 0 ]
}

@test "every profile weight is in [0,1] and every app names its problem" {
  run python3 -c "
import json
p=json.load(open('$P'))
for name,prof in p.items():
    if name=='_doc': continue
    assert prof.get('problem'), name
    for rule,w in prof.get('rules',{}).items():
        assert 0.0 <= float(w) <= 1.0, (name,rule,w)
for app in ('reso-landing-app','reso-management-app','reso-web-app'):
    assert app in p, app
print('ok')"
  [ "$status" -eq 0 ]
}

@test "the three apps are weighted differently, or the profile file is decorative" {
  run python3 -c "
import json
p=json.load(open('$P'))
sigs={a: json.dumps(p[a]['rules'],sort_keys=True)+str(p[a]['gestalt'])
      for a in ('reso-landing-app','reso-management-app','reso-web-app')}
assert len(set(sigs.values()))==3, sigs
print('ok')"
  [ "$status" -eq 0 ]
}
