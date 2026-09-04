#!/usr/bin/env bats
# validate-plan-structure.sh — PostToolUse plan-structure lint.
#   NEW status-schema gate (G-P14-6): a NEW hand-authored plan (docs/plans,
#   .claude-plans, AGENT_TEAM…) lacking a valid `status:` frontmatter key FAILS
#   (exit 2). Pre-existing plans only WARN (never retro-break). The ExitPlanMode
#   global sink (~/.claude/plans) is machine-authored → never gated.
#   Existing Phase 0 warn behavior is preserved.
#
# "New" = untracked in git, else mtime-fresh (< CC_PLAN_NEW_AGE_S).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-plan-structure.sh"
  export CC_PLANS_DIR="$BATS_TEST_TMPDIR/global-plans"   # stands in for ~/.claude/plans
  mkdir -p "$CC_PLANS_DIR"
  PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ/docs/plans"
}

# Drive PostToolUse (stdout+stderr merged so exit-2 messages are visible).
drive() { printf '{"tool_input":{"file_path":"%s"}}' "$1" | bash "$HOOK" 2>&1; }

@test "NEW authored plan lacking status → FAILS exit 2, names the schema" {
  f="$PROJ/docs/plans/fresh.md"; printf '# Plan\nbody\n' > "$f"   # non-git, fresh ⇒ new
  run drive "$f"
  [ "$status" -eq 2 ]
  echo "$output" | grep -qi 'status'
  echo "$output" | grep -qE 'open\|in-progress\|complete\|superseded'
}

@test "NEW plan WITH a valid status → not blocked (exit 0)" {
  f="$PROJ/docs/plans/ok.md"; printf -- '---\nstatus: open\n---\n# Plan\n' > "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
}

@test "NEW plan with an INVALID status value → treated as lacking → exit 2" {
  f="$PROJ/docs/plans/bad.md"; printf -- '---\nstatus: wibble\n---\n# Plan\n' > "$f"
  run drive "$f"
  [ "$status" -eq 2 ]
}

@test "pre-existing (git-tracked) plan lacking status → WARNS, exit 0 (no retro-break)" {
  # `git -C ""` is a NO-OP, not an error — an unset tmpdir would write this identity into the cwd repo.
  repo="${BATS_TEST_TMPDIR:?}/tracked"; mkdir -p "$repo/docs/plans"
  git -C "$repo" init -q; git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  f="$repo/docs/plans/legacy.md"; printf '# Legacy Plan\nbody\n' > "$f"
  git -C "$repo" add -A; git -C "$repo" commit -qm init
  run drive "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'status'
  echo "$output" | grep -q 'additionalContext'
}

@test "pre-existing via old mtime (non-git) lacking status → WARNS, exit 0" {
  f="$PROJ/docs/plans/aged.md"; printf '# Aged\n' > "$f"
  touch -t 202001010000 "$f"                                    # far past ⇒ not new
  run drive "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'additionalContext'
}

@test "global sink (~/.claude/plans) plan lacking status → never gated (exit 0)" {
  f="$CC_PLANS_DIR/adjective-noun.md"; printf '# Machine Plan\n' > "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qi 'PLAN STATUS'
}

@test "non-plan file → exit 0, silent" {
  f="$PROJ/src/main.ts"; mkdir -p "$(dirname "$f")"; printf 'code\n' > "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "regression: plan WITH status but missing Phase 0 still warns (Phase 0 check preserved)" {
  f="$PROJ/docs/plans/impl.md"
  printf -- '---\nstatus: open\n---\n# Impl Plan\n\n## Phase 1\nTask 1 do a thing\n\n## Phase 2\nmore\n' > "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi 'Agent Team'
}

# === EXECUTION LOCUS (2026-08-07) ===
# Phase 0 answered "who does the work" but never "WHERE does it run", so its only
# delegation unit (in-session teammates) routed every teammate's output back into the
# LEAD's context. These pin the third state: Phase 0 PRESENT but locus UNDECLARED.

# An impl plan carrying Phase 0 but no locus declaration. Used as both subject and control.
write_phase0_plan() {
  printf -- '---\nstatus: open\n---\n# Impl Plan\n\n## Phase 0: Agent Team Orchestration\n\n### Team Roster\n\n| Agent | Role |\n|---|---|\n| a1 | build |\n\n## Phase 1\nTask 1 do a thing\n\n## Phase 2\nmore\n' > "$1"
}

@test "locus: Phase 0 present but NO locus declared → warns EXECUTION LOCUS MISSING" {
  f="$PROJ/docs/plans/noloc.md"; write_phase0_plan "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'EXECUTION LOCUS MISSING'
  # It must name the DEFAULT, else the warning cannot be acted on.
  echo "$output" | grep -q 'dispatched session'
}

@test "locus: declaring the locus SILENCES the warning (control — same plan, one line added)" {
  f="$PROJ/docs/plans/withloc.md"; write_phase0_plan "$f"
  # The ONLY delta from the failing case above:
  printf '\n### Execution Locus\n\n| Wave | Locus |\n|---|---|\n| 1 | S — dispatched session |\n' >> "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'EXECUTION LOCUS MISSING'
}

@test "locus: the warning is valid JSON (message embeds backticks and pipes)" {
  f="$PROJ/docs/plans/json.md"; write_phase0_plan "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("EXECUTION LOCUS MISSING")' >/dev/null
}

@test "locus: no-Phase-0 plan emits the Phase 0 warning ONLY — never both (elif, not two ifs)" {
  f="$PROJ/docs/plans/nophase0.md"
  printf -- '---\nstatus: open\n---\n# Impl Plan\n\n## Phase 1\nTask 1\n\n## Phase 2\nmore\n' > "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'AGENT TEAMS REQUIRED'
  ! echo "$output" | grep -q 'EXECUTION LOCUS MISSING' || false
  # Two concatenated JSON objects would break any consumer: assert exactly one parse.
  [ "$(echo "$output" | jq -s 'length')" -eq 1 ]
  # The Phase 0 warning must itself now teach the locus (it is the first field).
  echo "$output" | grep -q 'EXECUTION LOCUS PER WAVE'
}

@test "locus: non-implementation plan (no phases/waves) is never asked for a locus" {
  f="$PROJ/docs/plans/research.md"
  printf -- '---\nstatus: open\n---\n# Research\n\n## Findings\na\n\n## Method\nb\n' > "$f"
  run drive "$f"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── `done` as an accepted alias, asserted on the TRACKED branch ──────────────────────────────────
# Deliberately driven through the git-tracked (pre-existing) path, not the NEW path: the NEW path's
# discriminator is exit 2 vs exit 0, and on the pre-existing path an unrecognised word emits the
# status WARN while a recognised one falls through to the Phase 0 check. That warn is the clean
# discriminator, and — unlike the NEW path — it never reaches is_new_plan's `stat`, whose BSD `-f %m`
# spelling makes the NEW-path tests platform-dependent. A test that cannot fail proves nothing (the
# vacuous-pass trap docs/plans/STOP_CHAIN_WAVE2.md §W5 recorded), so this one is anchored where the
# arm actually moves.

tracked_plan() {   # tracked_plan <status-line-or-empty> → path to a git-TRACKED plan carrying it
  local body="$1" repo="${BATS_TEST_TMPDIR:?}/tr-$$-${BATS_TEST_NUMBER:-0}"
  mkdir -p "$repo/docs/plans"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  local f="$repo/docs/plans/p.md"
  if [ -n "$body" ]; then printf -- '---\nstatus: %s\n---\n# P\nbody\n' "$body" > "$f"
  else printf -- '# P\nbody\n' > "$f"; fi
  git -C "$repo" add -A; git -C "$repo" commit -qm init
  printf '%s\n' "$f"
}

@test "tracked plan saying 'done' is accepted — no status WARN" {
  f="$(tracked_plan "done")"
  run drive "$f"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'PLAN STATUS'
}

@test "CONTROL: tracked plan with an unrecognised word STILL warns" {
  f="$(tracked_plan "wibble")"
  run drive "$f"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'PLAN STATUS'
}

@test "CONTROL: tracked plan saying 'complete' is accepted — no status WARN" {
  f="$(tracked_plan "complete")"
  run drive "$f"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'PLAN STATUS'
}
