#!/usr/bin/env bats
# smart-bash-allowlist — the COMPOUND-COMMAND axis.
#
# WHY THIS SUITE EXISTS (2026-08-20). The two existing suites for this hook
# (smart-bash-allowlist-narrow.bats, -sed-n.bats) each try exactly one shape: a SINGLE
# command. That is the shape on which nothing was ever wrong. On the shape that actually
# reaches this hook in production — 90.4% of the 1,693 blocking commands in
# ~/.claude/autonomy/permission-archive are compound, mean 11.9 segments — the hook was
# inverted in both directions at once:
#
#   * rule 1 (`^[[:space:]]*git\s+commit`) was anchored only at the START, so it allowed
#     any command BEGINNING with `git commit`, whatever rode behind the `&&`. A PreToolUse
#     `allow` bypasses the permission system completely, so this auto-approved commands
#     across EIGHT of the operator's own 36 Bash fence rules — including the hard `deny`
#     entries `git push --force` and `rm -rf .git`.
#   * rules 3/5/6 were whole-command-anchored (`[^;&|]+$`), so on a compound command the
#     SAFE rules could not fire at all.
#
# The suite that should have caught it could not: `git push origin main` alone was
# correctly refused, and that is all anyone ever asked it. The defect lived entirely in
# the axis no test varied. Hence this file, whose whole subject is that axis.
#
# CONTROL DISCIPLINE (same as the sibling suites): every fence assertion runs against BOTH
# the current hook and the PRE-FIX blob, pinned by content-addressed sha so the control can
# neither decay to a skip nor silently compare the fixed file against itself.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  # Fixturing $HOME is NOT sufficient: the hook resolves its config dir from
  # CLAUDE_CONFIG_DIR first, and a Claude Code session exports that. Left inherited, the
  # two fence tests below silently read the OPERATOR's live settings.json and passed for
  # the wrong reason — a suite that reads production state is not testing the mechanism.
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  HOOK="$REPO/hooks/smart-bash-allowlist.sh"
  [ -f "$HOOK" ] || skip "hook not found"
  export PROJ="$BATS_TEST_TMPDIR/proj"; mkdir -p "$PROJ"; : > "$PROJ/file.ts"

  # A FIXTURED fence, not the operator's live one. The hook reads permissions.ask/deny
  # live, which is the property under test; pinning it here means this suite asserts the
  # MECHANISM rather than today's contents of the operator's settings file.
  cat > "$HOME/.claude/settings.json" <<'JSON'
{
  "permissions": {
    "allow": [],
    "ask": ["Bash(git push:*)", "Bash(git reset --hard:*)", "Bash(fly deploy:*)"],
    "deny": ["Bash(git push --force:*)", "Bash(rm -rf .git)", "Bash(wget:*)"]
  }
}
JSON
}

# decide <hook-path> <command> -> allow | defer
decide() {
  local hook="$1" cmd="$2" json
  json=$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1]}}))' "$cmd")
  if (cd "$PROJ" && printf '%s' "$json" | bash "$hook" 2>/dev/null | grep -q '"permissionDecision": *"allow"'); then
    echo allow
  else
    echo defer
  fi
}

# The pre-fix hook, materialized from git by BLOB SHA — content-addressed, so it is immune
# both to the branch moving and to the fix landing.
PREFIX_BLOB=6141942ca3435e266a97e20708396d8d07f3e5f5   # hooks/smart-bash-allowlist.sh @ pre-fix

prefix_hook() {
  local out="$BATS_TEST_TMPDIR/prefix-hook.sh"
  if [ ! -s "$out" ]; then
    git -C "$REPO" cat-file blob "$PREFIX_BLOB" > "$out" 2>/dev/null || return 1
  fi
  [ -s "$out" ] || return 1
  # Positive control ON THE CONTROL: the pinned blob must actually contain the defect.
  # Without this a bad sha yields a file that refuses everything, and every assertion below
  # would "pass" against an artifact that never had the bug.
  grep -q 'git commit: safe (no --no-verify, local operation)' "$out" || return 1
  echo "$out"
}

# ── the fence: nothing behind ask/deny may ride in on an allowed prefix ──────────────

@test "a gated command riding behind git commit is refused — and the pre-fix hook allowed it" {
  local pre; pre="$(prefix_hook)" || { echo "control blob unusable"; return 1; }
  for tail in \
    'git push origin main' \
    'git push --force origin main' \
    'git reset --hard HEAD~5' \
    'fly deploy' \
    'rm -rf .git' \
    'wget http://example.com/x'
  do
    local cmd="git commit -m x && $tail"
    [ "$(decide "$HOOK" "$cmd")" = defer ] || { echo "FIXED HOOK ALLOWED: $cmd"; return 1; }
    # the control must FAIL the same assertion, else this test proves nothing
    [ "$(decide "$pre" "$cmd")" = allow ] || { echo "CONTROL did not exhibit the defect: $cmd"; return 1; }
  done
}

@test "the separator does not matter — ; and || carry a payload just as && does" {
  for sep in ';' '&&' '||'; do
    [ "$(decide "$HOOK" "git commit -m x $sep git push origin main")" = defer ]
  done
}

@test "a gated command in ANY position is refused, not just the second" {
  [ "$(decide "$HOOK" "git commit -m a && git commit -m b && git push origin main")" = defer ]
}

@test "the fence is read LIVE — a rule the operator adds arms the hook with no code change" {
  # `git commit` is otherwise allowed; gating it must make the same command defer.
  [ "$(decide "$HOOK" 'git commit -m x')" = allow ]
  cat > "$HOME/.claude/settings.json" <<'JSON'
{ "permissions": { "allow": [], "ask": ["Bash(git commit:*)"], "deny": [] } }
JSON
  [ "$(decide "$HOOK" 'git commit -m x')" = defer ]
}

@test "an unreadable fence refuses to decide — never auto-allows while blind" {
  printf '{ not json' > "$HOME/.claude/settings.json"
  [ "$(decide "$HOOK" 'git commit -m x')" = defer ]
}

# ── indirection: a command we cannot see is a command we cannot judge ────────────────

@test "command substitution, backticks and heredocs get no decision" {
  [ "$(decide "$HOOK" 'git commit -m "$(cat msg)"')" = defer ]
  [ "$(decide "$HOOK" 'git commit -m `cat msg`')" = defer ]
  [ "$(decide "$HOOK" 'git commit -m x <<EOF
body
EOF')" = defer ]
}

@test "an interpreter taking a command as DATA gets no decision" {
  [ "$(decide "$HOOK" 'git commit -m x && bash -c "git push"')" = defer ]
  [ "$(decide "$HOOK" 'git commit -m x && xargs rm')" = defer ]
}

@test "an unbalanced quote gets no decision rather than a guess" {
  [ "$(decide "$HOOK" "git commit -m 'unterminated && git push origin main")" = defer ]
}

# ── the bundled-flag hole in the git-clean danger pattern ────────────────────────────

@test "git clean -x is refused under bundled short flags — the pre-fix regex missed them" {
  local pre; pre="$(prefix_hook)" || { echo "control blob unusable"; return 1; }
  # `-[xX]\b` required a boundary right after the letter, so every bundled spelling passed.
  [ "$(decide "$HOOK" 'git commit -m x && git clean -xdf')" = defer ]
  [ "$(decide "$pre"  'git commit -m x && git clean -xdf')" = allow ]
}

# ── no over-rejection: the single-command behaviour the other suites pin is unchanged ─

@test "the surviving single-command allows are byte-for-byte unchanged" {
  [ "$(decide "$HOOK" 'git commit -m "x"')" = allow ]
  [ "$(decide "$HOOK" 'sed -n 1,20p file.ts')" = allow ]
  [ "$(decide "$HOOK" 'chmod 755 file.ts')" = allow ]
  [ "$(decide "$HOOK" "sed -i 's/a/b/' file.ts")" = allow ]
}

@test "a compound made ONLY of independently-allowed segments is allowed" {
  # This is the point of decomposition: the safe rules can now reach a compound command,
  # which under the whole-command anchors they never could.
  [ "$(decide "$HOOK" 'git commit -m a && git commit -m b')" = allow ]
  local pre; pre="$(prefix_hook)" || { echo "control blob unusable"; return 1; }
  [ "$(decide "$pre" 'chmod 755 file.ts && chmod 644 other.ts')" = defer ]   # pre-fix: inert
  [ "$(decide "$HOOK" 'chmod 755 file.ts && chmod 644 other.ts')" = allow ]
}

@test "one un-allowlisted segment sinks the whole command" {
  [ "$(decide "$HOOK" 'git commit -m x && npm publish')" = defer ]
}

@test "kill switch still disarms every rule" {
  SMART_ALLOWLIST_DISABLED=1 run bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$HOOK'"
  [ -z "$output" ]
}

@test "a missing python3 defers rather than failing in the allow direction" {
  # /bin has bash and cat but no python3, so this removes the interpreter without also
  # removing the shell — an earlier spelling used PATH=/nonexistent and merely proved that
  # `bash` itself was unfindable (exit 127), which asserts nothing about the hook.
  run env PATH=/bin bash -c "printf '%s' '{\"tool_input\":{\"command\":\"git commit -m x\"}}' | bash '$HOOK'"
  [ -z "$output" ]
  [ "$status" -eq 0 ]
}
