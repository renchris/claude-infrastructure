#!/usr/bin/env bats
# lr-select.py — the shared resume-selection decision point (session-sprawl consolidation).
#
# Contract under test (register-criteria-FIRST, house 43de6d6 discipline). Origin: incident
# 2026-07-21, 14 sessions resurrected for ONE project (2.76 GB RSS) because selection had no
# consolidation rule and no ceiling. Plan: docs/plans/SESSION_SPRAWL_CONSOLIDATION_PLAN.md.
#
#   1. CONSOLIDATE: N candidates sharing a worktree yield exactly ONE winner (P1). This is the
#      regression test for the incident itself — 14 in, 1 fired.
#   2. WINNER = "holds real state" (§ Q3), a lexicographic tuple:
#        a. last INTERNAL transcript activity (never file mtime)
#        b. turn count, as tiebreak only
#        c. sid, deterministic final tiebreak
#      Uncommitted work is a WORKTREE property, constant across a group ⇒ annotation, NEVER a ranker.
#   3. CEILING (P2): --max-total bounds a whole run; --max-per-worktree defaults to 1. Raising either
#      is an explicit flag, never a silent default.
#   4. NO SILENT CAPS: every non-fired candidate is reported with a reason, so a truncated recovery
#      can never read as a complete one.
#   5. HARD FILTERS run before ranking: teammate sessions (lead-owned), already-running, vanished cwd,
#      agent-*/wf_* internals.
#   6. MACHINE CONTRACT: stdout is TSV winners only (callers consume it); the report goes to stderr.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SEL="$REPO/scripts/limit-recover/lr-select.py"
  export LR_SELECT_HOME="$BATS_TEST_TMPDIR/home"
  export LR_SELECT_PGREP_BIN="$BATS_TEST_TMPDIR/stub-pgrep"
  export LR_SELECT_GIT_BIN="$BATS_TEST_TMPDIR/stub-git"

  # pgrep stub: "running" only for sids listed in .running (default: nothing is running).
  cat > "$LR_SELECT_PGREP_BIN" <<'SH'
#!/bin/bash
pat="$2"
[ -f "$0.running" ] || exit 1
grep -qF "${pat#resume }" "$0.running" && exit 0
exit 1
SH
  chmod +x "$LR_SELECT_PGREP_BIN"

  # git stub: `status --porcelain` emits N dirty lines per <cwd> recorded in .dirty ("<cwd> <n>").
  cat > "$LR_SELECT_GIT_BIN" <<'SH'
#!/bin/bash
# args: -C <cwd> status --porcelain
cwd="$2"
n=0
[ -f "$0.dirty" ] && n=$(awk -v c="$cwd" '$1==c{print $2}' "$0.dirty")
[ -z "$n" ] && n=0
i=0; while [ "$i" -lt "$n" ]; do echo " M file$i.txt"; i=$((i+1)); done
exit 0
SH
  chmod +x "$LR_SELECT_GIT_BIN"
}

# mk <acct-store> <sid> <cwd> <last-ts> <turns> [teammate]
# Writes a transcript whose INTERNAL max timestamp is <last-ts>. The head record carries cwd/branch.
# An early "agentName" record marks a teammate session.
mk() {
  local store="$1" sid="$2" cwd="$3" ts="$4" turns="$5" teammate="${6:-}"
  local slug dir f i
  slug="$(printf '%s' "$cwd" | tr '/' '-')"
  dir="$LR_SELECT_HOME/$store/projects/$slug"
  mkdir -p "$dir" "$cwd"
  f="$dir/$sid.jsonl"
  if [ -n "$teammate" ]; then
    printf '{"type":"user","agentName":"worker-1","cwd":"%s","gitBranch":"main","timestamp":"2026-01-01T00:00:00Z"}\n' "$cwd" > "$f"
  else
    printf '{"type":"user","cwd":"%s","gitBranch":"main","timestamp":"2026-01-01T00:00:00Z"}\n' "$cwd" > "$f"
  fi
  i=1
  while [ "$i" -lt "$turns" ]; do
    printf '{"type":"assistant","timestamp":"2026-01-01T00:00:00Z"}\n' >> "$f"
    i=$((i+1))
  done
  # the max-timestamp record, written last
  printf '{"type":"assistant","timestamp":"%s"}\n' "$ts" >> "$f"
}

# bats `run` MERGES stderr into $output. Assertions about the machine contract (TSV winners) must
# therefore suppress the human report, or report lines get counted as winners. `--quiet` does exactly
# that; tests that assert ON the report call `python3 "$SEL" ... 2>&1` directly.
run_sel() { run python3 "$SEL" "$@" --quiet; }

# ── 1. CONSOLIDATE — the incident regression ─────────────────────────────────────────────
@test "14 sessions in one worktree fire exactly ONE (incident regression)" {
  local wt="$BATS_TEST_TMPDIR/wt/voiceink"
  for i in $(seq 1 14); do
    mk .claude-next "sid-$i" "$wt" "2026-07-21T06:$(printf '%02d' "$i"):00Z" 5
  done
  run_sel --scan --recency-min 0
  [ "$status" -eq 0 ]
  # stdout = TSV winners only
  [ "$(echo "$output" | grep -c "$wt")" -eq 1 ]
}

@test "14-in-one-worktree: the other 13 are LISTED, not silently dropped" {
  local wt="$BATS_TEST_TMPDIR/wt/voiceink"
  for i in $(seq 1 14); do
    mk .claude-next "sid-$i" "$wt" "2026-07-21T06:$(printf '%02d' "$i"):00Z" 5
  done
  run python3 "$SEL" --scan --recency-min 0 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"firing 1; 13 listed-not-spawned"* ]]
  [ "$(echo "$output" | grep -c 'per-worktree cap (1)')" -eq 13 ]
}

# ── 2. WINNER SELECTION (§ Q3) ───────────────────────────────────────────────────────────
@test "winner = latest INTERNAL activity, even when a rival has far more turns" {
  local wt="$BATS_TEST_TMPDIR/wt/a"
  mk .claude-next stale-but-deep "$wt" "2026-07-21T01:00:00Z" 400
  mk .claude-next fresh-but-thin "$wt" "2026-07-21T09:00:00Z" 3
  run_sel --scan --recency-min 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"fresh-but-thin"* ]]
  [[ "$output" != *"stale-but-deep"* ]]
}

@test "turn count breaks a last-activity tie" {
  local wt="$BATS_TEST_TMPDIR/wt/a"
  mk .claude-next thin "$wt" "2026-07-21T09:00:00Z" 3
  mk .claude-next deep "$wt" "2026-07-21T09:00:00Z" 400
  run_sel --scan --recency-min 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"deep"* ]]
  [[ "$output" != *"thin"* ]]
}

@test "uncommitted work annotates the group but does NOT pick the winner" {
  # Both sessions share the worktree ⇒ both see the same dirty tree. Recency must still decide.
  local wt="$BATS_TEST_TMPDIR/wt/dirty"
  mk .claude-next older "$wt" "2026-07-21T01:00:00Z" 9
  mk .claude-next newer "$wt" "2026-07-21T09:00:00Z" 2
  echo "$wt 322" > "$LR_SELECT_GIT_BIN.dirty"
  run python3 "$SEL" --scan --recency-min 0 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"322 uncommitted"* ]]     # annotated
  [[ "$output" == *"▶ RESUME  newer"* ]]     # recency still decided
}

@test "selection is deterministic across runs (sid is the final tiebreak)" {
  local wt="$BATS_TEST_TMPDIR/wt/a"
  mk .claude-next aaa "$wt" "2026-07-21T09:00:00Z" 5
  mk .claude-next bbb "$wt" "2026-07-21T09:00:00Z" 5
  run_sel --scan --recency-min 0
  local first="$output"
  run_sel --scan --recency-min 0
  [ "$output" = "$first" ]
}

# ── 3. CEILING (P2) ──────────────────────────────────────────────────────────────────────
@test "--max-total bounds a whole run across many worktrees" {
  for i in 1 2 3 4 5 6; do
    mk .claude-next "sid-$i" "$BATS_TEST_TMPDIR/wt/p$i" "2026-07-21T0$i:00:00Z" 5
  done
  run_sel --scan --recency-min 0            # default max-total 4
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | grep -c 'wt/p')" -eq 4 ]
}

@test "total ceiling truncates the LEAST recently active worktrees" {
  mk .claude-next hot "$BATS_TEST_TMPDIR/wt/hot" "2026-07-21T23:00:00Z" 5
  mk .claude-next cold "$BATS_TEST_TMPDIR/wt/cold" "2026-07-01T01:00:00Z" 5
  run_sel --scan --recency-min 0 --max-total 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"wt/hot"* ]]
  [[ "$output" != *"wt/cold"* ]]
}

@test "exceeding one per worktree requires an EXPLICIT flag" {
  local wt="$BATS_TEST_TMPDIR/wt/a"
  mk .claude-next s1 "$wt" "2026-07-21T09:00:00Z" 5
  mk .claude-next s2 "$wt" "2026-07-21T08:00:00Z" 5
  run_sel --scan --recency-min 0
  [ "$(echo "$output" | grep -c "$wt")" -eq 1 ]      # default: 1
  run_sel --scan --recency-min 0 --max-per-worktree 2
  [ "$(echo "$output" | grep -c "$wt")" -eq 2 ]      # opt-in: 2
}

@test "a cap below 1 is refused (usage error), never silently coerced" {
  run_sel --candidate "next:x:/tmp" --max-per-worktree 0
  [ "$status" -eq 2 ]
}

# ── 4. NO SILENT CAPS ────────────────────────────────────────────────────────────────────
@test "every ceiling-dropped candidate is reported with its reason" {
  for i in 1 2 3 4 5 6; do
    mk .claude-next "sid-$i" "$BATS_TEST_TMPDIR/wt/p$i" "2026-07-21T0$i:00:00Z" 5
  done
  run python3 "$SEL" --scan --recency-min 0 2>&1
  [[ "$output" == *"total-ceiling (4) reached"* ]]
  [[ "$output" == *"firing 4; 2 listed-not-spawned"* ]]
}

# ── 5. HARD FILTERS ──────────────────────────────────────────────────────────────────────
@test "teammate sessions are filtered (lead-owned recovery)" {
  local wt="$BATS_TEST_TMPDIR/wt/a"
  mk .claude-next mate "$wt" "2026-07-21T09:00:00Z" 5 teammate
  mk .claude-next lead "$wt" "2026-07-21T01:00:00Z" 5
  run python3 "$SEL" --scan --recency-min 0 2>&1
  [[ "$output" == *"teammate-session"* ]]
  [[ "$output" == *"▶ RESUME  lead"* ]]   # the older LEAD wins; the newer teammate never competes
}

@test "an already-running session is never re-fired" {
  local wt="$BATS_TEST_TMPDIR/wt/a"
  mk .claude-next live "$wt" "2026-07-21T09:00:00Z" 5
  mk .claude-next idle "$wt" "2026-07-21T01:00:00Z" 5
  echo "live" > "$LR_SELECT_PGREP_BIN.running"
  run python3 "$SEL" --scan --recency-min 0 2>&1
  [[ "$output" == *"already-running"* ]]
  [[ "$output" == *"▶ RESUME  idle"* ]]
}

@test "subagent and workflow-internal transcripts are not candidates" {
  local wt="$BATS_TEST_TMPDIR/wt/a" slug dir
  mk .claude-next real "$wt" "2026-07-21T09:00:00Z" 5
  slug="$(printf '%s' "$wt" | tr '/' '-')"
  dir="$LR_SELECT_HOME/.claude-next/projects/$slug"
  cp "$dir/real.jsonl" "$dir/agent-abc.jsonl"
  mkdir -p "$LR_SELECT_HOME/.claude-next/projects/wf_run1"
  cp "$dir/real.jsonl" "$LR_SELECT_HOME/.claude-next/projects/wf_run1/slot.jsonl"
  run_sel --scan --recency-min 0
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$output" == *"real"* ]]
}

@test "a candidate whose cwd no longer exists is filtered, not fired" {
  run python3 "$SEL" --candidate "next:ghost:/nonexistent/worktree" 2>&1
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *"no-transcript"* || "$output" == *"cwd-missing"* ]]
}

@test "the .claude/.claude-next mirror counts as ONE session, not two" {
  local wt="$BATS_TEST_TMPDIR/wt/a"
  mk .claude-next dup "$wt" "2026-07-21T09:00:00Z" 5
  mk .claude dup "$wt" "2026-07-21T09:00:00Z" 5
  run_sel --scan --recency-min 0
  [ "$(echo "$output" | grep -c dup)" -eq 1 ]
}

# ── 6. MACHINE CONTRACT ──────────────────────────────────────────────────────────────────
@test "stdout is TSV winners only; the report goes to stderr" {
  mk .claude-next only "$BATS_TEST_TMPDIR/wt/a" "2026-07-21T09:00:00Z" 5
  run bash -c "python3 '$SEL' --scan --recency-min 0 2>/dev/null"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [[ "$output" != *"RESUME TRIAGE"* ]]
  [ "$(printf '%s' "$output" | awk -F'\t' '{print NF}')" -eq 4 ]
}

@test "--json records winners, listed, and filtered with reasons" {
  local wt="$BATS_TEST_TMPDIR/wt/a"
  mk .claude-next win "$wt" "2026-07-21T09:00:00Z" 5
  mk .claude-next lose "$wt" "2026-07-21T01:00:00Z" 5
  run_sel --scan --recency-min 0 --json "$BATS_TEST_TMPDIR/out.json" --quiet
  [ "$status" -eq 0 ]
  run jq -r '.winners[0].sid' "$BATS_TEST_TMPDIR/out.json"
  [ "$output" = "win" ]
  run jq -r '.listed[0].reason' "$BATS_TEST_TMPDIR/out.json"
  [[ "$output" == *"per-worktree cap"* ]]
  run jq -r '.policy.max_per_worktree' "$BATS_TEST_TMPDIR/out.json"
  [ "$output" = "1" ]
}

@test "no candidates is a decision, not an error (exit 0, empty stdout)" {
  run bash -c "python3 '$SEL' --scan --recency-min 0 2>/dev/null"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "neither --candidate nor --scan is a usage error" {
  run_sel
  [ "$status" -eq 2 ]
}
