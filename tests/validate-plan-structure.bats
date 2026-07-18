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
  repo="$BATS_TEST_TMPDIR/tracked"; mkdir -p "$repo/docs/plans"
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
