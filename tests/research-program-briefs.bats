#!/usr/bin/env bats
# research-program-briefs — wave B2 (REPORT.md §8 item 8): the skill's frozen briefs, rubric and
# checklist are consumed by code that was written first, so each is pinned to its consumer:
#   - the reviewer brief's return shape is what courier.extract_panel reads, with all 11 kit.LENSES,
#     or gate row 13 fails the slot as "attested n/11 lenses";
#   - the seed-author brief's records carry every field seed.validate requires, with omission ops;
#   - checklist.jsonl is exactly gate row 1's FAC-01..FAC-33, worded as REPORT.md §3.2 step 5;
#   - the skill names every cc-signoff research action, each one operator_sign.parse_row accepts,
#     and never tells a session to open a program packet with a bare `cc-decide open`.
# The last case is a mutation control: the lens check goes red on a copy with one lens dropped.

setup() {
  REPO="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/h"; mkdir -p "$HOME"   # hermetic: never the operator's live ~/
  SK="$REPO/skills/research-program"
  CHECK="$BATS_TEST_TMPDIR/lenses.py"
  cat > "$CHECK" <<'PY'
import re, sys
sys.path[:0] = [sys.argv[1] + "/scripts/research-kit/lib", sys.argv[1] + "/scripts/lib"]
import courier, kit
text = open(sys.argv[2]).read()
block = re.findall(r"```json\s*(\{.*?\})\s*```", text, re.S)
assert len(block) == 1, f"{len(block)} json blocks"
panel = courier.extract_panel(block[0])
assert panel is not None, "extract_panel cannot read the brief's shape"
lenses = [x["lens"] for x in panel["lenses"]]
assert lenses == list(kit.LENSES), lenses
table = re.findall(r"^\| `([a-z-]+)` \|", text, re.M)
assert table == list(kit.LENSES), table
assert {"rows", "findings"} <= set(panel)
PY
}

@test "the reviewer brief returns the panel shape courier reads, with exactly the 11 kit lenses" {
  run python3 "$CHECK" "$REPO" "$SK/briefs/reviewer.md"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "every brief allows zero, and none demands a count" {
  local f
  for f in reviewer rater; do
    grep -qi 'zero .* is a correct and expected outcome' "$SK/briefs/$f.md" || { echo "$f"; false; }
  done
  if grep -niE '\b(find|list|name)[[:space:]]+(at least )?[1-9]' "$SK"/briefs/*.md; then false; fi
}

@test "the rubric and the rater brief carry the same seven clauses, a to g" {
  local c
  for c in a b c d e f g; do
    grep -q "^| $c |" "$SK/RUBRIC.md" || { echo "rubric lacks $c"; false; }
    grep -q "^- ($c) " "$SK/briefs/rater.md" || { echo "rater brief lacks $c"; false; }
  done
  grep -q "blind to the" "$SK/briefs/rater.md"
}

@test "the seed-author brief's records carry every field seed.py validates, omission ops included" {
  python3 - "$REPO" "$SK/briefs/seed-author.md" <<'PY'
import json, re, sys
sys.path[:0] = [sys.argv[1] + "/scripts/research-kit", sys.argv[1] + "/scripts/research-kit/lib"]
import importlib.util
spec = importlib.util.spec_from_file_location("seed", sys.argv[1] + "/scripts/research-kit/seed.py")
seed = importlib.util.module_from_spec(spec); spec.loader.exec_module(seed)
text = open(sys.argv[2]).read()
lines = [l for l in re.findall(r"^\{.*\}$", text, re.M)]
assert len(lines) >= 2, lines
recs = [json.loads(l) for l in lines]
for r in recs:
    assert r["op"] in seed.OPS, r
    for f in ("sid", "cohort", "class", "defect_statement", "detect_span"):
        assert r.get(f), (f, r)
    assert re.match(r"^[^:]+:\d+-\d+$", r["detect_span"]), r
assert any(r["op"] != "replace" for r in recs), "no omission op in the example"
for op in seed.OPS:
    assert f"`{op}`" in text, f"brief never names {op}"
assert str(seed.MIN_ANCHOR) in text
PY
}

@test "checklist.jsonl is gate row 1's FAC-01..FAC-33, worded as REPORT.md §3.2 step 5" {
  python3 - "$REPO" <<'PY'
import json, re, sys
root = sys.argv[1]
sys.path[:0] = [root + "/scripts/research-kit/lib", root + "/scripts/lib"]
import gate_rows_a
rows = [json.loads(l) for l in open(root + "/skills/research-program/checklist.jsonl")]
assert [r["id"] for r in rows] == gate_rows_a.FAC_IDS
report = open(root + "/docs/research/upfront-research-exhaustion-2026-09-30/REPORT.md").read()
table = dict(re.findall(r"^   \| (\d+) \| (.+?) \|$", report, re.M))
for r in rows:
    assert table[str(int(r["id"][4:]))] == r["carries"], r["id"]
PY
}

@test "the skill names every cc-signoff research action, and each parses in operator_sign's namespace" {
  python3 - "$REPO" <<'PY'
import re, sys
root = sys.argv[1]
sys.path[:0] = [root + "/scripts/research-kit/lib", root + "/scripts/lib"]
import operator_sign
text = open(root + "/skills/research-program/SKILL.md").read()
named = re.findall(r"cc-signoff (research:<slug>/[A-Za-z<>/_-]+)", text)
seen = set()
for n in named:
    p = operator_sign.parse_row(n.replace("<slug>", "demo").replace("<DECISION-ID>", "DR-01"))
    assert p, n
    seen.add(p["action"])
assert seen == set(operator_sign.ACTIONS), (seen, operator_sign.ACTIONS)  # E3c: + extend-decision (§12.3)
PY
}

@test "program packets go through gate.sh file-packet; no skill text tells a session to run cc-decide open" {
  grep -q 'gate.sh file-packet' "$SK/SKILL.md"
  run grep -nE 'cc-decide open' "$SK/SKILL.md" "$REPO/commands/research-program.md" "$SK"/briefs/*.md
  # the only mention is the prohibition itself
  [ "$(printf '%s\n' "$output" | grep -c 'never a bare')" -eq "$(printf '%s\n' "$output" | grep -c .)" ]
}

@test "the command and the skill point at each other and at files that exist" {
  grep -q 'research-program' "$REPO/commands/research-program.md"
  local f
  for f in RUBRIC.md checklist.jsonl briefs/reviewer.md briefs/rater.md briefs/verifier.md briefs/seed-author.md; do
    [ -f "$SK/$f" ] || { echo "missing $f"; false; }
    grep -q "$f" "$SK/SKILL.md" || { echo "SKILL.md never names $f"; false; }
  done
  [ -x "$REPO/scripts/research-kit/intake.py" ]
}

@test "mutation control: the lens check goes red on a reviewer brief with one lens dropped" {
  # shellcheck disable=SC2016  # the backticks are literal markdown in the brief's lens table
  sed -e '/"lens": "drift"/d' -e '/^| `drift` |/d' "$SK/briefs/reviewer.md" > "$BATS_TEST_TMPDIR/mutant.md"
  run python3 "$CHECK" "$REPO" "$BATS_TEST_TMPDIR/mutant.md"
  [ "$status" -ne 0 ]
  run python3 "$CHECK" "$REPO" "$SK/briefs/reviewer.md"
  [ "$status" -eq 0 ]
}

# ── wave E3c: Stage 9 and the yield stop in the skill; the built-round briefs (REPORT.md §11, §12) ──

built_check() { # <brief>: extract_panel reads it, and its lens table equals its JSON lenses
  python3 - "$REPO" "$1" <<'PY'
import re, sys
sys.path[:0] = [sys.argv[1] + "/scripts/research-kit/lib", sys.argv[1] + "/scripts/lib"]
import courier
text = open(sys.argv[2]).read()
block = re.findall(r"```json\s*(\{.*?\})\s*```", text, re.S)
assert len(block) == 1, f"{len(block)} json blocks"
panel = courier.extract_panel(block[0])
assert panel is not None, "extract_panel cannot read the brief's shape"
lenses = [x["lens"] for x in panel["lenses"]]
table = re.findall(r"^\| `([a-z-]+)` \|", text, re.M)
assert lenses and table == lenses, (table, lenses)
assert re.search(r'^\{"fid"(?:(?!```).)*?"test_cmd": "', text, re.M | re.S), "the example finding carries no test_cmd"
PY
}

@test "E3c: the skill walks Stage 9 and the yield stop, citing §11 and §12, with the kit's own numbers" {
  python3 - "$REPO" <<'PY'
import re, sys
root = sys.argv[1]
sys.path[:0] = [root + "/scripts/research-kit/lib", root + "/scripts/lib"]
import kit
t = open(root + "/skills/research-program/SKILL.md").read()
assert re.search(r"^## Stage 9 .*§11", t, re.M), "no Stage 9 heading citing §11"
assert re.search(r"^## .*yield.*§12", t, re.M | re.I), "no yield-stop section citing §12"
for verb in ("gate.sh built-freeze", "gate.sh built-run", "built finding add", "built finding fix",
             "built mutate", "built contact", "built soak sample", "built soak restart", "built show",
             "--kind built", "cc-research job soak", "cc-research yield show", "cc-research yield find",
             "cc-research budget end", "cc-research menu", "briefs/built-reviewer.md",
             "briefs/built-verifier.md", "briefs/built-rater.md"):
    assert verb in t, verb
P = kit.PROFILES
k = "K is {} (lite), {} (standard), {} (full)".format(*(P[n]["quiet_probes_to_stop"] for n in ("lite", "standard", "full")))
assert k in t, k
cap = "{} (lite), {} (standard), {} (full) built rounds".format(*(P[n]["built_hard_cap"] for n in ("lite", "standard", "full")))
assert cap in t, cap
assert f"{kit.CAPS['yield_ceiling_factor']:g} × its stage budget" in t
assert f"{kit.CAPS['yield_probe_ceiling']} counted probes" in t
assert f"{kit.CAPS['soak_min_hours']} hours and {kit.CAPS['soak_min_samples']} samples" in t
for row in ("18", "19", "20", "21", "22", "23", "24", "25"):
    assert re.search(rf"\b{row}\b", t), row
assert t.count("Updated 2026-10-04 (v1.2)") >= 3, "the v1.2 additions carry dated notes"
for kept in ("## Stage 1 — intake and the signed frame (§3.2)", "## Stage 7 — certification (§3.8, §3.9)",
             "## Stage 8 — gate, certificate, signoff (§3.10)", "| 3. Contact |", "| 5. Acceptance and skeleton |"):
    assert kept in t, f"existing stage text deleted: {kept}"
PY
}

@test "E3c: the built reviewer brief returns a panel courier reads, every finding with a failing-test command" {
  run built_check "$SK/briefs/built-reviewer.md"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qi 'zero .* is a correct and expected outcome' "$SK/briefs/built-reviewer.md"
}

@test "E3c: the built rater brief carries the rater's seven clauses verbatim and never rates a no-repro material" {
  diff <(grep '^- ([a-g]) ' "$SK/briefs/rater.md") <(grep '^- ([a-g]) ' "$SK/briefs/built-rater.md")
  grep -q "rejected-no-repro" "$SK/briefs/built-rater.md"
  grep -q "blind to the" "$SK/briefs/built-rater.md"
  grep -qi 'zero .* is a correct and expected outcome' "$SK/briefs/built-rater.md"
  grep -q 'RUBRIC.md' "$SK/briefs/built-rater.md"
}

@test "E3c: the built verifier brief reproduces in the as-built environment the kit records" {
  python3 - "$REPO" "$SK/briefs/built-verifier.md" <<'PY'
import sys
sys.path[:0] = [sys.argv[1] + "/scripts/research-kit/lib", sys.argv[1] + "/scripts/lib"]
import kit
t = open(sys.argv[2]).read()
env = kit.AS_BUILT_ENV
for s in (f"PATH={env['path']}", env["interpreter"], env["interpreter_major"], "HOME",
          "`CONFIRMED`", "`REFUTED`", "`NO-REPRO`", "rejected-no-repro", "test_cmd"):
    assert s in t, s
PY
}

@test "E3c: the built briefs exist and the skill names each" {
  local f
  for f in briefs/built-reviewer.md briefs/built-verifier.md briefs/built-rater.md; do
    [ -f "$SK/$f" ] || { echo "missing $f"; false; }
    grep -q "$f" "$SK/SKILL.md" || { echo "SKILL.md never names $f"; false; }
  done
}

@test "E3c mutation control: the built lens check goes red on a built reviewer brief with one table lens dropped" {
  # shellcheck disable=SC2016  # the backticks are literal markdown in the brief's lens table
  sed -e '/^| `harness` |/d' "$SK/briefs/built-reviewer.md" > "$BATS_TEST_TMPDIR/mutant.md"
  run built_check "$BATS_TEST_TMPDIR/mutant.md"
  [ "$status" -ne 0 ]
  run built_check "$SK/briefs/built-reviewer.md"
  [ "$status" -eq 0 ]
}
