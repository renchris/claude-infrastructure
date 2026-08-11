#!/usr/bin/env bats
# cc-wf-harvest — harvest a Workflow result into a durable research doc + per-axis dir.
#
# Every assertion here is anchored to a defect that actually cost tokens on 2026-08-11, and each
# has a MUTANT control proving the test can fail (this repo has repeatedly shipped controls that
# could only pass — see memory `control-must-replay-the-real-artifact`).

setup() {
  BIN="${BATS_TEST_DIRNAME}/../bin/cc-wf-harvest"
  # Fixture $HOME even though the subject does not read it today: the hermeticity ratchet asserts
  # the INVARIANT, not this suite's current reads, so a future edit cannot silently start running
  # against the operator's live ~/. $BATS_TEST_TMPDIR is per-test, so concurrent runs cannot collide.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  TMP="$BATS_TEST_TMPDIR"
  OUT="$TMP/docs"
  mkdir -p "$OUT"
}

# The REAL shape a Workflow task-output file has: the script's return value is nested under
# `result`, beside `summary`/`agentCount`/`logs`.
nested_fixture() {
  cat > "$TMP/in.json" <<'JSON'
{
  "summary": "a wave",
  "agentCount": 4,
  "logs": ["did a thing"],
  "result": {
    "memo": "# The synthesis\n\nThis is the load-bearing body of the wave.",
    "critic": "What was missed: nothing.",
    "axes": [
      {"axis": "alpha", "title": "Alpha axis",
       "found": {"verdict": "alpha holds", "top_claim": "A is true", "at_100p": "YES",
                 "findings": [{"claim": "a1", "evidence": "measured a1", "source": "f.sh:1",
                               "status": "MEASURED", "gap_or_strength": "STRENGTH"}],
                 "unknowns": ["what about a2"]},
       "verdict": {"refuted": false, "confidence": "high", "corrected_claim": "A is true, narrowly"}},
      {"axis": "beta", "title": "Beta axis",
       "found": {"verdict": "beta fails", "top_claim": "B is false", "findings": []},
       "verdict": {"refuted": true, "confidence": "medium", "corrected_claim": "B is false",
                   "instrument_defect": "wrong ruler"}}
    ]
  }
}
JSON
}

@test "harvests a nested Workflow result into synthesis + per-axis dir" {
  nested_fixture
  run python3 "$BIN" "$TMP/in.json" --name wave-2026-08-11 --title "Wave" --out "$OUT" --run-id wf_test
  [ "$status" -eq 0 ]
  [ -f "$OUT/wave-2026-08-11.md" ]
  [ -f "$OUT/wave-2026-08-11/alpha.md" ]
  [ -f "$OUT/wave-2026-08-11/beta.md" ]
  grep -q "load-bearing body" "$OUT/wave-2026-08-11.md"
  grep -q "completeness critic" "$OUT/wave-2026-08-11.md"
  grep -q "measured a1" "$OUT/wave-2026-08-11/alpha.md"
  grep -q "REFUTED" "$OUT/wave-2026-08-11/beta.md"
  grep -q "SURVIVED" "$OUT/wave-2026-08-11/alpha.md"
}

# DEFECT 1 (measured): reading the TOP level returns nothing and reads as "the wave produced no
# output". MUTANT: a payload whose synthesis exists ONLY nested. A tool that forgot to unwrap
# `result` finds no string field at all and must exit non-zero — so this control CAN fail.
@test "unwraps result: a synthesis reachable only when nested is still found" {
  nested_fixture
  run python3 "$BIN" "$TMP/in.json" --name w2 --out "$OUT"
  [ "$status" -eq 0 ]
  grep -q "load-bearing body" "$OUT/w2.md"

  # mutant: strip the nesting wrapper's payload -> nothing to harvest -> must REFUSE, not write.
  printf '{"summary":"x","agentCount":4,"logs":[],"result":{}}\n' > "$TMP/empty.json"
  run python3 "$BIN" "$TMP/empty.json" --name w3 --out "$OUT"
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/w3.md" ]
  echo "$output" | grep -q "journal.jsonl"
}

# DEFECT 3 (measured): the synthesis field is named differently per workflow (`memo`, `verdict`,
# ...). Requiring one name means editing this tool per wave — i.e. rotting back into hand-written
# code. MUTANT: a field name in NO known list; the longest-string fallback must still find it.
@test "finds the synthesis under an unknown field name via longest-string fallback" {
  cat > "$TMP/novel.json" <<'JSON'
{"result": {"tiny": "x",
            "some_bespoke_name": "# Novel\n\nA much longer body that is clearly the synthesis text."}}
JSON
  run python3 "$BIN" "$TMP/novel.json" --name novel --out "$OUT"
  [ "$status" -eq 0 ]
  grep -q "clearly the synthesis" "$OUT/novel.md"
  echo "$output" | grep -q "synthesis field: some_bespoke_name"
}

# DEFECT 2 (measured): rendering every axis inline produced a 271 KB doc, 5x the largest sibling
# in docs/research/ — unloadable, therefore inert. Split is the DEFAULT; --flat is opt-in.
@test "splits by default and only inlines under --flat" {
  nested_fixture
  run python3 "$BIN" "$TMP/in.json" --name split --out "$OUT"
  [ "$status" -eq 0 ]
  [ -d "$OUT/split" ]

  run python3 "$BIN" "$TMP/in.json" --name flat --out "$OUT" --flat
  [ "$status" -eq 0 ]
  [ ! -d "$OUT/flat" ]
  # with no axis dir there must be no link into one (else the doc ships a dead link)
  run grep -c "](flat/" "$OUT/flat.md"
  [ "$status" -ne 0 ]
}

# A research doc accumulates corrections across sessions (INTEGRATE-never-overwrite). Silently
# replacing one destroys that history, so the refusal is the safe default.
@test "refuses to overwrite an existing doc, and --force is required to replace it" {
  nested_fixture
  run python3 "$BIN" "$TMP/in.json" --name dup --out "$OUT"
  [ "$status" -eq 0 ]
  printf 'HAND-EDITED CORRECTION\n' >> "$OUT/dup.md"

  run python3 "$BIN" "$TMP/in.json" --name dup --out "$OUT"
  [ "$status" -ne 0 ]
  grep -q "HAND-EDITED CORRECTION" "$OUT/dup.md"   # the correction survived the refusal

  run python3 "$BIN" "$TMP/in.json" --name dup --out "$OUT" --force
  [ "$status" -eq 0 ]
  run grep -c "HAND-EDITED CORRECTION" "$OUT/dup.md"
  [ "$status" -ne 0 ]
}

@test "a bash task log is rejected as not-a-Workflow-result rather than half-harvested" {
  printf 'ok 1 - some test\nnot ok 2 - another\n' > "$TMP/log.txt"
  run python3 "$BIN" "$TMP/log.txt" --name fromlog --out "$OUT"
  [ "$status" -ne 0 ]
  [ ! -f "$OUT/fromlog.md" ]
  echo "$output" | grep -q "not JSON"
}

@test "--dry-run reports without writing anything" {
  nested_fixture
  run python3 "$BIN" "$TMP/in.json" --name dry --out "$OUT" --dry-run
  [ "$status" -eq 0 ]
  [ ! -f "$OUT/dry.md" ]
  [ ! -d "$OUT/dry" ]
  echo "$output" | grep -q "would write"
}

# The tool's own output claims "links: all resolve". That claim must be earned, not printed —
# a dead link in a landed doc is the spec-named-but-not-built defect.
@test "emitted axis links actually resolve on disk" {
  nested_fixture
  run python3 "$BIN" "$TMP/in.json" --name links --out "$OUT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "links: all resolve"
  while read -r rel; do
    [ -e "$OUT/${rel%/}" ]
  done < <(grep -o "](links/[^)]*)" "$OUT/links.md" | sed 's/^](//; s/)$//')
}
