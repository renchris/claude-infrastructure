#!/usr/bin/env bats
# hook-jq-abstain — the two PreToolUse bash safety gates must never fail open SILENTLY (audit 09 D-4).
#
# `validate-bash.sh` and `rm-safe-allowlist.sh` had no `command -v jq` guard (every other
# PreToolUse hook does — backup-before-write.sh:17, git-worktree-guard.sh, check-edit-boundary.sh,
# agent-teams-enforce.sh, frontier-spawn-gate.sh, cc-unattended-ask-guard.sh,
# plan-agent-teams-default.sh). With jq absent or the payload malformed, CMD went empty, every
# DANGER pattern missed, and the hook exited 0: the bash validator was disabled with ZERO signal.
# Fail-OPEN is the right availability posture; failing open *silently* on a safety gate is the
# defect (contrast keychain-guard.sh:19-21, which documents and logs its fail-open).
#
# The sink is the EXISTING ~/.claude/logs/validate-bash-unclear.log — lib/is-true-flag.sh:200-205
# already writes its own "could not decide" case there in the same TSV shape (ts \t kind \t
# detail), so one file carries one meaning: "the bash validator did not actually validate this".
#
# Harness laws: L1 fixtures are literal PreToolUse payloads; L2 assertions key on the
# failure-distinct abstain line in validate-bash-unclear.log; L3 `[ ]` / `grep -q` only;
# L4 each hook has BOTH a no-jq/malformed fixture (must log) and a healthy fixture (must NOT
# log), so an always-log bug goes RED too.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  VALIDATE_BASH="$REPO/hooks/validate-bash.sh"
  RM_SAFE="$REPO/hooks/rm-safe-allowlist.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/logs"
  UNCLEAR="$HOME/.claude/logs/validate-bash-unclear.log"
  # A PATH with NO jq but with everything else the hooks need. Stripping real PATH dirs is not an
  # option (macOS 26 ships /usr/bin/jq, so a "system PATH" still has it, and removing /usr/bin
  # would take grep/sed/date with it) — so build a curated symlink farm instead.
  NOJQ_BIN="$BATS_TEST_TMPDIR/nojq-bin"
  mkdir -p "$NOJQ_BIN"
  local b p
  for b in cat date dirname basename grep sed mkdir rm ls wc tr cut head tail sort find git; do
    p="$(command -v "$b" 2>/dev/null)" || continue
    [ -n "$p" ] && ln -sf "$p" "$NOJQ_BIN/$b"
  done
}

# run a hook in a real "jq unavailable" environment (absolute bash — the curated PATH has none)
run_without_jq() { # <hook> <stdin-text>
  printf '%s' "$2" | env PATH="$NOJQ_BIN" /bin/bash "$1"
}

@test "validate-bash: jq unavailable → exits 0 (fail-open) but logs ONE loud abstain line" {
  run_without_jq "$VALIDATE_BASH" '{"tool_input":{"command":"sudo rm -rf /"}}'
  [ "$?" -eq 0 ]
  [ -f "$UNCLEAR" ]
  grep -q 'validate-bash' "$UNCLEAR"
  grep -q 'jq' "$UNCLEAR"
  [ "$(grep -c . "$UNCLEAR")" -eq 1 ]
}

@test "validate-bash: unparseable payload → exits 0 but logs the abstain" {
  run bash "$VALIDATE_BASH" <<<'{not json at all'
  [ "$status" -eq 0 ]
  [ -f "$UNCLEAR" ]
  grep -q 'validate-bash' "$UNCLEAR"
}

@test "validate-bash: a healthy payload logs NO abstain line" {
  run bash "$VALIDATE_BASH" <<<'{"session_id":"sid-1","tool_input":{"command":"echo ok"}}'
  [ "$status" -eq 0 ]
  [ ! -s "$UNCLEAR" ]
}

@test "rm-safe-allowlist: jq unavailable → exits 0 but logs ONE loud abstain line" {
  run_without_jq "$RM_SAFE" '{"tool_input":{"command":"rm -rf node_modules"}}'
  [ "$?" -eq 0 ]
  [ -f "$UNCLEAR" ]
  grep -q 'rm-safe-allowlist' "$UNCLEAR"
  [ "$(grep -c . "$UNCLEAR")" -eq 1 ]
}

@test "rm-safe-allowlist: unparseable payload → exits 0 but logs the abstain" {
  run bash "$RM_SAFE" <<<'{oops'
  [ "$status" -eq 0 ]
  grep -q 'rm-safe-allowlist' "$UNCLEAR"
}

@test "rm-safe-allowlist: a healthy payload still ALLOWS a regenerable target and logs nothing" {
  run bash "$RM_SAFE" <<<'{"session_id":"sid-2","tool_input":{"command":"rm -rf node_modules"}}'
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '"permissionDecision": "allow"'
  [ ! -s "$UNCLEAR" ]
}

@test "rm-safe-allowlist: the kill switch stays silent (no abstain spam when disabled on purpose)" {
  RM_SAFE_ALLOWLIST_DISABLED=1 run bash "$RM_SAFE" <<<'{"tool_input":{"command":"rm -rf /"}}'
  [ "$status" -eq 0 ]
  [ ! -s "$UNCLEAR" ]
}

@test "validate-bash: the kill switch stays silent" {
  VALIDATE_BASH_DISABLED=1 run bash "$VALIDATE_BASH" <<<'{"tool_input":{"command":"sudo rm -rf /"}}'
  [ "$status" -eq 0 ]
  [ ! -s "$UNCLEAR" ]
}
