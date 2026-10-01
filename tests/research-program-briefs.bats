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
assert seen == {"frame", "cert", "extra-round", "reopen", "veto"}, seen
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
