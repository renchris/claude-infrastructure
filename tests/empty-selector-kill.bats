#!/usr/bin/env bats
# The EMPTY-SELECTOR contract (2026-09-09 mass application termination).
#
# WHAT HAPPENED: a session moved a census pattern into an env prefix to keep it out of its own argv
#     count() { LA_PAT='handoff-fire.sh late-arm' ps -axo pid=,command= | awk -v p="$LA_PAT" 'index($0,p)' ; }
# An env-prefix assignment binds to ONE command, so awk — the next pipeline stage — read the SHELL's
# unset LA_PAT and got "". index($0,"") is 1 on every line, so the census returned every process and
# the kill loop below it SIGTERMed the box: Kitty, Dia, Discord, Hammerspoon, ~17 Claude Code
# sessions, nine seconds, three waves. Measured: 875 of 878 processes selected, against 2 for the
# same census with the pattern actually reaching awk.
#
# WHY A STATIC SCAN. hooks/lib/kill-selection.py evaluates a selection live, but only for a
# pgrep-shaped census; this line used a bare `kill` over `ps | awk`. What is decidable with no fork
# is that the selector was provably EMPTY at its use site — a property of the code, not a spelling.
#
# Assertions use `|| false` where they are non-final: a bare `[[ ]]` / `!` / `A && B` is
# errexit-EXEMPT in bats and would be a DEAD assertion (memory: bats-dead-assertions).

setup() {
  # HERMETIC $HOME — validate-bash.sh's last act appends to ~/.claude/logs/bash-commands.log, and
  # this gate also writes ~/.claude/logs/empty-selector-gate.jsonl. Unfixtured, every probe here
  # would write to the OPERATOR's live audit logs.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  # This suite never fires anything — but its FIXTURE text contains the literal
  # `handoff-fire.sh late-arm` (that is the census pattern the incident was hunting), and
  # test-hermeticity-lint keys on that name. Pinned per the lint's own prescribed fix, so the
  # suite can never go red-by-load instead of red-by-subject.
  export CC_FIRE_CAPACITY_GATE=off
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  # The incident, verbatim from ~/.claude/logs/bash-commands.log at 2026-09-09T23:55:14Z.
  INCIDENT='cd /tmp/wt
count() { LA_PAT='"'"'handoff-fire.sh late-arm'"'"' ps -axo pid=,command= | awk -v p="$LA_PAT" '"'"'index($0,p)'"'"' ; }
echo "=== before ==="; count | wc -l
for i in 1 2 3; do
  for p in $(count | awk '"'"'{print $1}'"'"'); do kill "$p" 2>/dev/null || true; done
  sleep 1
done'
}

decision() {  # $1 = command → DENY | ASK | ALLOW | PASS  (PASS = no decision emitted)
  local out
  out="$(python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1" \
        | bash "$HOOK" 2>/dev/null)"
  [ -z "$out" ] && { printf 'PASS'; return 0; }
  printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["permissionDecision"].upper())'
}

reason() {  # $1 = command → the decision's reason text (empty when no decision)
  local out
  out="$(python3 -c 'import json,sys;print(json.dumps({"tool_input":{"command":sys.argv[1]}}))' "$1" \
        | bash "$HOOK" 2>/dev/null)"
  [ -z "$out" ] && return 0
  printf '%s' "$out" | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"].get("permissionDecisionReason",""))'
}

# ── the incident itself ──────────────────────────────────────────────────────────────────────────

@test "the 2026-09-09 command that terminated the box is DENIED" {
  [ "$(decision "$INCIDENT")" = DENY ] || false
}

@test "the denial names the variable that is empty" {
  reason "$INCIDENT" | grep -q 'LA_PAT' || false
}

@test "the denial states the selection is universal, not narrow" {
  reason "$INCIDENT" | grep -qi 'EVERY process' || false
}

@test "an xargs-executed kill over the same empty census is DENIED" {
  [ "$(decision 'V=late-arm ps -ax | grep "$V" | awk "{print \$1}" | xargs kill')" = DENY ] || false
}

@test "the same empty selector with pkill is DENIED" {
  [ "$(decision 'V=x ps -ax | awk -v p="$V" "index(\$0,p)" ; pkill -f leftover')" = DENY ] || false
}

# ── the three documented abstentions: the value DOES reach the shell ─────────────────────────────

@test "a BARE assignment reaches the shell, so the census is not empty" {
  [ "$(decision 'LA_PAT="late-arm"; ps -ax | awk -v p="$LA_PAT" "index(\$0,p)" | while read p; do kill "$p"; done')" != DENY ] || false
}

@test "an exported assignment reaches the shell" {
  [ "$(decision 'export LA_PAT="late-arm"; ps -ax | awk -v p="$LA_PAT" "0" ; kill 123')" != DENY ] || false
}

@test "a local assignment reaches the shell" {
  [ "$(decision 'f() { local LA_PAT="x"; ps -ax | awk -v p="$LA_PAT" "0"; kill 5; }')" != DENY ] || false
}

@test "a reference inside the prefixed command's OWN environment is correct" {
  [ "$(decision 'FOO=bar sh -c "echo \$FOO"; kill 99')" != DENY ] || false
}

# The two cases above are reached only because a `NAME=value;` is never a prefix-assignment
# CANDIDATE in the first place (the scan requires a command word after the value), so they do not
# credit the abstention itself. These two DO: each carries the prefix form AND a shell-level
# assignment of the same name, which is the only shape where the abstention decides anything.

@test "a shell-level assignment ELSEWHERE means the prefix reference is not empty" {
  [ "$(decision 'FOO=x; FOO=y ps -ax | grep "$FOO" | awk "{print \$1}" | xargs kill')" != DENY ] || false
}

@test "an exported assignment elsewhere likewise acquits the prefix form" {
  # EQUIVALENCE GUARD, not a red-proof: the bare-assignment arm already matches `export FOO=x;`
  # (the boundary before FOO= is a space), so removing the export/local arm alone leaves this green.
  # It is kept as defence in depth and asserted so a future edit cannot make it DENY.
  [ "$(decision 'export FOO=x; FOO=y ps -ax | awk -v p="$FOO" "0"; kill 1')" != DENY ] || false
}

# ── polarity: the gate must not fire where there is no harm ──────────────────────────────────────

@test "a provably-empty selector that signals nothing is not this gate's business" {
  [ "$(decision 'LA_PAT="x" ps -axo pid= | awk -v p="$LA_PAT" "index(\$0,p)"')" != DENY ] || false
}

@test "an env prefix with no later reference is untouched" {
  [ "$(decision 'FOO=1 make build; kill 4242')" != DENY ] || false
}

@test "the PATH-prefix idiom is untouched" {
  [ "$(decision 'PATH=/opt/homebrew/bin:$PATH pnpm build')" != DENY ] || false
}

@test "a targeted kill by pid is untouched" {
  [ "$(decision 'kill 12345')" != DENY ] || false
}

@test "a commit message that merely MENTIONS a kill is untouched" {
  [ "$(decision 'git commit -m "fix: do not kill peers with $LA_PAT"')" != DENY ] || false
}

# ── the seam ─────────────────────────────────────────────────────────────────────────────────────

@test "CC_EMPTY_SELECTOR_GATE=off is a real kill switch" {
  export CC_EMPTY_SELECTOR_GATE=off
  [ "$(decision "$INCIDENT")" != DENY ] || false
}
