#!/usr/bin/env bats
# rm-safe-allowlist.sh — PreToolUse(Bash) hook that auto-allows `rm` of regenerable within-tree
# targets and stays SILENT (defer to the ask prompt) for everything else. Safety is the whole
# point: the allow set is an OPT-IN whitelist, so these tests exhaustively pin both directions.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  H="$REPO/hooks/rm-safe-allowlist.sh"
}

# decision <cmd> → prints ALLOW (hook emitted permissionDecision:allow) or DEFER (silent / no decision)
decision() {
  local out
  out="$(printf '{"tool_input":{"command":%s}}' "$(jq -Rn --arg c "$1" '$c')" | "$H" 2>/dev/null)"
  [ -z "$out" ] && { echo DEFER; return; }
  printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "DEFER"' | tr '[:lower:]' '[:upper:]'
}

@test "hook is executable (a non-+x hook silently defers everything)" {
  [ -x "$H" ]
}

# ── MUST ALLOW — regenerable within-tree targets ──────────────────────────────────────────────
@test "allows rm -rf of build/cache/artifact dirs" {
  for c in "rm -rf artifacts/" "rm -rf artifacts" "rm -rf .next" "rm -rf __pycache__" \
           "rm -rf dist build" "rm -rf ./node_modules" "rm -r .pytest_cache" \
           "rm -rf .mypy_cache .ruff_cache" "rm -rf coverage test-results" "rm -rf .turbo"; do
    [ "$(decision "$c")" = ALLOW ] || { echo "expected ALLOW: $c"; false; }
  done
}

@test "allows deletion WITHIN a regenerable tree (nested + files)" {
  for c in "rm -rf packages/foo/dist" "rm -rf apps/web/.next" "rm -rf src/__pycache__" \
           "rm -f dist/bundle.js"; do
    [ "$(decision "$c")" = ALLOW ] || { echo "expected ALLOW: $c"; false; }
  done
}

@test "allows rm under /tmp and /private/tmp scratch (subpath only)" {
  [ "$(decision "rm -rf /tmp/claude-501/foo")" = ALLOW ]
  [ "$(decision "rm -rf /private/tmp/scratch/x")" = ALLOW ]
}

# ── MUST DEFER — catastrophic / outside-repo / non-regenerable / ambiguous ─────────────────────
@test "defers the catastrophic roots (/ ~ .git)" {
  S=/; TILDE='~'
  [ "$(decision "rm -rf $S")" = DEFER ]
  [ "$(decision "rm -rf $TILDE")" = DEFER ]
  [ "$(decision "rm -rf $TILDE/Development")" = DEFER ]
  [ "$(decision "rm -rf .git")" = DEFER ]
  [ "$(decision "rm -rf .git/hooks")" = DEFER ]
}

@test "defers outside-repo absolute paths and bare tmp root" {
  [ "$(decision "rm -rf /etc/foo")" = DEFER ]
  [ "$(decision "rm -rf /Users/chrisren/Development/reso")" = DEFER ]
  [ "$(decision "rm -rf /tmp")" = DEFER ]
  [ "$(decision "rm -rf /private/tmp")" = DEFER ]
}

@test "defers .. traversal, globs, and non-regenerable names" {
  [ "$(decision "rm -rf dist/../src")" = DEFER ]
  [ "$(decision "rm -rf ../dist")" = DEFER ]
  [ "$(decision "rm -rf build/../..")" = DEFER ]
  [ "$(decision "rm -rf src")" = DEFER ]
  [ "$(decision "rm -rf artifactsX")" = DEFER ]
  [ "$(decision "rm mydist")" = DEFER ]
  [ "$(decision "rm -rf tmp")" = DEFER ]
}

@test "defers glob targets even mixed with a safe one" {
  G='*'
  [ "$(decision "rm -rf $G")" = DEFER ]
  [ "$(decision "rm -rf dist $G")" = DEFER ]
  [ "$(decision "rm -rf artifacts ../secrets")" = DEFER ]
}

@test "defers sudo / compound / substitution (an unsafe rm may hide after the safe one)" {
  SUDO=sudo; AMP='&&'; SEMI=';'; SLASH=/
  [ "$(decision "$SUDO rm -rf artifacts")" = DEFER ]
  [ "$(decision "rm -rf artifacts $AMP rm -rf $SLASH")" = DEFER ]
  [ "$(decision "rm -rf node_modules$SEMI rm -rf $SLASH")" = DEFER ]
  [ "$(decision "rm -rf \$(cat x)")" = DEFER ]
}

@test "kill switch RM_SAFE_ALLOWLIST_DISABLED=1 defers even a safe target" {
  out="$(printf '{"tool_input":{"command":"rm -rf artifacts"}}' | RM_SAFE_ALLOWLIST_DISABLED=1 "$H" 2>/dev/null)"
  [ -z "$out" ]
}
