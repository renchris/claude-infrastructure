#!/bin/bash
# run.sh — regression test runner for plan-phase-scan.sh
#
# For each fixture <name>.md, runs the scanner and asserts the output matches
# the invariants we care about (status, status_source, is_phase_0, commit_hashes,
# summary counters). Does NOT do byte-exact JSON diff — that's too brittle
# (line_count depends on trailing newlines). Instead uses Python to parse + assert.
#
# Usage: ./run.sh
# Exit: 0 all pass, 1 any fail.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"
SCANNER="$SCRIPT_DIR/../plan-phase-scan.sh"

if [[ ! -x "$SCANNER" ]]; then
  echo "FATAL: scanner not executable at $SCANNER" >&2
  exit 2
fi

PASS=0
FAIL=0
FAIL_NAMES=()

run_assertion() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAIL_NAMES+=("$name: expected [$expected], got [$actual]")
  fi
}

# ---------- Test: 01-simple ----------
echo "== 01-simple =="
JSON=$("$SCANNER" "$FIXTURES_DIR/01-simple.md")
SUMMARY=$(echo "$JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary'])")
run_assertion "01.summary" "{'sections': 4, 'done': 1, 'in_progress': 0, 'pending': 3, 'superseded': 0, 'phase_0': 0}" "$SUMMARY"

PHASE1_STATUS=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Phase 1' in s['title']][0]['status'])")
run_assertion "01.phase1_status" "DONE" "$PHASE1_STATUS"

PHASE1_HASH=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Phase 1' in s['title']][0]['commit_hashes'])")
run_assertion "01.phase1_hash" "['abc1234']" "$PHASE1_HASH"

PHASE1_SRC=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Phase 1' in s['title']][0]['status_source'])")
run_assertion "01.phase1_status_source" "heading" "$PHASE1_SRC"

PHASE2_STATUS=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Phase 2' in s['title']][0]['status'])")
run_assertion "01.phase2_status" "PENDING" "$PHASE2_STATUS"

# ---------- Test: 02-codeblocks ----------
echo "== 02-codeblocks =="
JSON=$("$SCANNER" "$FIXTURES_DIR/02-codeblocks.md")
SECTION_COUNT=$(echo "$JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['sections'])")
# Expected: 3 headings (title + Phase A + Phase B). Bash comments inside fences must NOT count.
run_assertion "02.section_count_ignores_fences" "3" "$SECTION_COUNT"

PHASE_A_STATUS=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Phase A' in s['title']][0]['status'])")
run_assertion "02.phase_a_done" "DONE" "$PHASE_A_STATUS"

PHASE_B_STATUS=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Phase B' in s['title']][0]['status'])")
run_assertion "02.phase_b_pending" "PENDING" "$PHASE_B_STATUS"

# ---------- Test: 03-body-status ----------
echo "== 03-body-status =="
JSON=$("$SCANNER" "$FIXTURES_DIR/03-body-status.md")

ALPHA_STATUS=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Alpha' in s['title']][0]['status'])")
run_assertion "03.alpha_status_via_body" "DONE" "$ALPHA_STATUS"

ALPHA_SRC=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Alpha' in s['title']][0]['status_source'])")
run_assertion "03.alpha_status_source_body" "body" "$ALPHA_SRC"

BETA_STATUS=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Beta' in s['title']][0]['status'])")
run_assertion "03.beta_v2_status_pattern" "DONE" "$BETA_STATUS"

GAMMA_STATUS=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Gamma' in s['title']][0]['status'])")
run_assertion "03.gamma_superseded_via_body" "SUPERSEDED" "$GAMMA_STATUS"

DELTA_STATUS=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Delta' in s['title']][0]['status'])")
run_assertion "03.delta_pending_no_marker" "PENDING" "$DELTA_STATUS"

# ---------- Test: 04-phase-0 ----------
echo "== 04-phase-0 =="
JSON=$("$SCANNER" "$FIXTURES_DIR/04-phase-0.md")
P0_COUNT=$(echo "$JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary']['phase_0'])")
# Expected: 2 — the L2 "Phase 0 — Agent Team Orchestration" matches both "PHASE 0" AND the
# orchestration keyword, and its L3 children don't (they're "Team Roster", "Task Dependency Graph").
# But wait — our detection uses the TITLE containing "Phase 0" OR "Agent Team Orchestration",
# so only the single L2 Phase 0 heading matches → 1.
run_assertion "04.phase_0_count" "1" "$P0_COUNT"

PHASE_2_HASH=$(echo "$JSON" | python3 -c "import json,sys; print([s for s in json.load(sys.stdin)['sections'] if 'Phase 2' in s['title']][0]['commit_hashes'])")
run_assertion "04.phase_2_hash" "['deadbeef']" "$PHASE_2_HASH"

# ---------- Report ----------
echo ""
echo "════════════════════════════════════════"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
  echo ""
  echo "  Failures:"
  for f in "${FAIL_NAMES[@]}"; do
    echo "    • $f"
  done
  exit 1
fi
echo "════════════════════════════════════════"
exit 0
