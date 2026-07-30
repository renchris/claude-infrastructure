#!/usr/bin/env bats
# qos-rewrite.sh — the PreToolUse(Bash) hook that moves QoS demotion to the TOOL boundary (§11.3 M7).
#
# A PreToolUse hook signals its effect through the JSON it prints, NOT through its exit code: every
# path in this hook exits 0 by contract (a hook failure must never block a tool), so "did nothing"
# and "did something" are distinguished ONLY by stdout. Every assertion below therefore keys on the
# emitted envelope, and "untouched" always means EMPTY OUTPUT — not exit status.
#
# Hermetic: $HOME is fixtured, the cc-bats target is a fixture executable, and every table fixture
# lives in $BATS_TEST_TMPDIR. Two properties are deliberately tested against the REAL shipped
# artifacts instead: config/qos-batch.patterns (its four day-one rows ARE a deliverable, so a
# fixture table would test nothing about them) and the $0-relative table resolution.
#
# The two prefix binaries are the real /usr/bin/nice and /usr/sbin/taskpolicy — present on every
# macOS, and the point of the rewrite is that THOSE paths are what lands in the command.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/qos-rewrite.sh"
  D="$BATS_TEST_TMPDIR"
  export HOME="$D/home"; mkdir -p "$HOME"      # never read the operator's live ~/
  # A fixture cc-bats, so transform (a) is exercised without depending on the deployed copy.
  mkdir -p "$D/bin"
  CCBATS="$D/bin/cc-bats"
  printf '#!/bin/bash\nexit 0\n' > "$CCBATS"; chmod +x "$CCBATS"
  export CC_QOS_CC_BATS="$CCBATS"
  NICE=/usr/bin/nice
  TP=/usr/sbin/taskpolicy
}

run_hook() { # $1 = the agent's command; env seams come from the caller
  jq -n --arg c "$1" '{tool_input:{command:$c}}' | bash "$HOOK"
}

# The rewritten command carried by the envelope ("" when nothing was emitted).
cmd_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.updatedInput.command // ""' 2>/dev/null; }

# A pattern table fixture: $1 = basename, then <band> <ere> pairs. printf, never a heredoc.
mktable() {
  local out="$D/$1.patterns"; shift
  : > "$out"
  while [ "$#" -ge 2 ]; do
    printf '%s\t%s\n' "$1" "$2" >> "$out"
    shift 2
  done
  printf '%s' "$out"
}

# ── transform (a): any spelling of bats converges on the proven artifact ────────────────────────
@test "absolute-path bats is rewritten to cc-bats, wrapper and args preserved" {
  run run_hook "timeout 90 /opt/homebrew/bin/bats t.bats"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "timeout 90 $CCBATS t.bats" ]
}

@test "bare bats is rewritten to cc-bats" {
  run run_hook "bats tests/qos-rewrite.bats"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$CCBATS tests/qos-rewrite.bats" ]
}

# The guard that makes the token pattern safe: an ABSOLUTE .bats FILE is an argument, not the tool.
# Without the "prefix must end in /" rule, `/a/b/tests/x.bats` matches as `/a/b/tests/x.` + `bats`.
@test "an absolute .bats file ARGUMENT is not rewritten — only the command token is" {
  run run_hook "bats /Users/x/repo/tests/foo.bats"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$CCBATS /Users/x/repo/tests/foo.bats" ]
}

# ── idempotency: never wrap what is already wrapped ────────────────────────────────────────────
@test "a command already naming cc-bats is untouched" {
  run run_hook "$CCBATS tests/foo.bats"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a command already carrying taskpolicy -c is untouched" {
  run run_hook "$NICE -n 19 $TP -c background uv run pytest"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── transform (b): the four SHIPPED day-one rows, each a measured consumer (§11.2) ─────────────
@test "pytest (uv run form) gets the background demotion prefix" {
  run run_hook "uv run pytest -m load"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$NICE -n 19 $TP -c background uv run pytest -m load" ]
}

@test "shellcheck gets the background demotion prefix" {
  run run_hook "shellcheck hooks/qos-rewrite.sh"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$NICE -n 19 $TP -c background shellcheck hooks/qos-rewrite.sh" ]
}

@test "npm install gets the background demotion prefix" {
  run run_hook "npm install --frozen-lockfile"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$NICE -n 19 $TP -c background npm install --frozen-lockfile" ]
}

@test "recursive du gets the background demotion prefix" {
  run run_hook "du -sh /Users/x/Development"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$NICE -n 19 $TP -c background du -sh /Users/x/Development" ]
}

# ── the conservative detector: structure means hands off (never string-surgery a compound) ─────
@test "a compound command that would otherwise match is untouched" {
  run run_hook "du -sh . | sort -h"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# A DELIBERATE day-one coverage residual, pinned in both directions so that changing it is a
# conscious decision rather than drift (lead review 2026-07-30). The form is common in this fleet's
# agent Bash calls, so the residual is real; the reason transform (b) declines is that the prefix is
# PREPENDED, and `taskpolicy -c background PYTEST_ADDOPTS=-q pytest` execs the assignment and dies.
# Three halves, because emptiness alone would also pass if the hook did nothing at all:
#   1. the skip itself                       2. the control: no assignment ⇒ prefixed
#   3. the ASYMMETRY: transform (a) is unaffected, because it replaces a token in place
@test "a leading VAR=value assignment skips transform (b) but not transform (a)" {
  run run_hook "PYTEST_ADDOPTS=-q pytest -m load"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run run_hook "pytest -m load"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$NICE -n 19 $TP -c background pytest -m load" ]
  run run_hook "CC_X=1 timeout 500 /opt/homebrew/bin/bats t.bats"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "CC_X=1 timeout 500 $CCBATS t.bats" ]
}

@test "a command matching nothing produces NO output at all" {
  run run_hook "git status --short"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── fail-open contract: every degradation is silent, exit 0, no partial JSON ────────────────────
@test "malformed stdin JSON exits 0 with empty output" {
  run bash -c 'printf "not json at all" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "CC_QOS_REWRITE=off emits nothing for a command that would otherwise match" {
  export CC_QOS_REWRITE=off
  run run_hook "uv run pytest -m load"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# The two seams are INDEPENDENT kill switches, and set-but-EMPTY is honoured verbatim at both.
@test "CC_QOS_PATTERNS set-but-EMPTY turns the table off while transform (a) stays on" {
  export CC_QOS_PATTERNS=
  run run_hook "uv run pytest -m load"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run run_hook "bats t.bats"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$CCBATS t.bats" ]
}

@test "CC_QOS_CC_BATS set-but-EMPTY turns transform (a) off while the table stays on" {
  export CC_QOS_CC_BATS=
  run run_hook "bats t.bats"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run run_hook "uv run pytest -m load"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$NICE -n 19 $TP -c background uv run pytest -m load" ]
}

# Rewriting to a cc-bats that is not deployed would turn a working gate run into exit 127. The
# refusal is the whole point: one undemoted process beats one broken command.
@test "an unexecutable cc-bats target refuses the rewrite rather than emit a broken command" {
  export CC_QOS_CC_BATS="$D/bin/does-not-exist"
  run run_hook "bats t.bats"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# taskpolicy(8) parses ONLY utility|background|maintenance and on anything else exits 64 WITHOUT
# running the program — so an unvalidated band in a config file would break every matching command.
@test "a band outside the taskpolicy allowlist is refused; a valid one is admitted (control)" {
  CC_QOS_PATTERNS="$(mktable bogus bogus '(^|[[:space:]])du -s')" run run_hook "du -sh ."
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  CC_QOS_PATTERNS="$(mktable ok utility '(^|[[:space:]])du -s')" run run_hook "du -sh ."
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$NICE -n 19 $TP -c utility du -sh ." ]
}

# nice -n 19 ALONE leaves PRI at 31 on Darwin (cc-bats:150-159) — a nice-only prefix would cost two
# forks and demote nothing, so a missing taskpolicy must refuse (b) entirely, not degrade.
@test "a missing taskpolicy refuses transform (b) with no nice-only fallback; (a) still works" {
  export CC_QOS_TASKPOLICY="$D/nope/taskpolicy"
  run run_hook "uv run pytest -m load"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run run_hook "bats t.bats"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$CCBATS t.bats" ]
}

# The stdin bound is a real cap, and the control proves the SAME command shape rewrites when small
# — otherwise an always-empty hook would pass this test vacuously.
@test "an oversized command is bounded and falls open; the same shape rewrites when small" {
  pad="$(head -c 250000 /dev/zero | tr '\0' 'x')"
  run run_hook "echo $pad bats t.bats"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run run_hook "echo small bats t.bats"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "echo small $CCBATS t.bats" ]
}

# ── the envelope is a parsed contract: shape asserted field by field ────────────────────────────
@test "the envelope is one line of valid JSON, correctly named, and carries NO permissionDecision" {
  run run_hook "uv run pytest -m load"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e . >/dev/null
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" = 1 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.hookEventName')" = PreToolUse ]
  # Probe-verified 2026-07-30: the rewrite applies with NO decision field, leaving the permission
  # flow to the hooks that own it. Claiming a decision here would silently take that over.
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput | has("permissionDecision")')" = false ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.updatedInput | keys | join(",")')" = command ]
}

# ── the deployed copy: ~/.claude/hooks/<name> is a SYMLINK into the checkout ────────────────────
# Resolved naively, `dirname $0/../config` becomes ~/.claude/config — a directory that does not
# exist and never will, because a symlinked directory acquires no links for NEW files. This test
# invokes the hook through a symlink whose sibling ../config is ABSENT: the table can only be found
# by resolving $0 physically first.
@test "the table resolves through a symlinked \$0 into the checkout, not the symlink's parent" {
  mkdir -p "$D/deployed/hooks"
  ln -s "$HOOK" "$D/deployed/hooks/qos-rewrite.sh"
  [ ! -d "$D/deployed/config" ]
  run bash -c 'jq -n --arg c "$2" "{tool_input:{command:\$c}}" | bash "$1"' \
    _ "$D/deployed/hooks/qos-rewrite.sh" "uv run pytest -m load"
  [ "$status" -eq 0 ]
  [ "$(cmd_of "$output")" = "$NICE -n 19 $TP -c background uv run pytest -m load" ]
}
