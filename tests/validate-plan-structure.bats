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

# ── status ALIASES: this hook and find-plan.sh's plan_status() must agree ──────────────────────
# A disagreement means a plan is complained about here while being read as `unknown` there — the
# split that let STOP_CHAIN_WAVE2.md close itself into a state no consumer could see (2026-09-03).
#
# These drive the file through a GIT-BACKED dir, and that is load-bearing rather than incidental.
# `is_new_plan` answers from git when one is present and only otherwise reaches
# `stat -f %m` — the BSD form. Under GNU stat that reads `%m` as a filesystem operand, fails, and
# prints a multi-line report on STDOUT, so `mt` becomes text beginning `File:` and `$(( now - mt ))`
# dies on `set -u` ("File: unbound variable", exit 1). On a Linux runner the whole gate is therefore
# DEAD for a non-git plan dir, and an assertion made there would pass VACUOUSLY on both branches —
# the silent-green trap §W5 of STOP_CHAIN_WAVE2 names by hand. Going through git keeps these honest
# on either platform. (The stat portability defect is pre-existing on trunk and filed separately;
# it is not what these tests are about.)

alias_drive() {  # <status-value> → hook output for an UNTRACKED plan carrying that status
  local v="$1" repo="${BATS_TEST_TMPDIR:?}/alias-$2"
  mkdir -p "$repo/docs/plans"; git -C "$repo" init -q
  local f="$repo/docs/plans/p.md"; printf -- '---\nstatus: %s\n---\n# Plan\n' "$v" > "$f"
  drive "$f"
}

@test "negative control: an unrecognised status still complains (proves the assertion is live)" {
  run alias_drive wibble neg
  echo "$output" | grep -q 'PLAN STATUS'
}

@test "control: alias 'completed' draws no status complaint (green on both branches)" {
  run alias_drive completed ctl
  ! echo "$output" | grep -q 'PLAN STATUS'
}

@test "alias 'done' draws no status complaint, matching plan_status()'s normalization (the arm)" {
  run alias_drive done arm
  ! echo "$output" | grep -q 'PLAN STATUS'
}

@test "the schema NAMED to the author stays the canonical four — 'done' is accepted, not advertised" {
  run alias_drive wibble adv
  echo "$output" | grep -qE 'open\|in-progress\|complete\|superseded'
  ! echo "$output" | grep -qE '\|done\|'
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
