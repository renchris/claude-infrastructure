#!/usr/bin/env bats
# validate-bash SINGLE PAYLOAD PARSE — the hook reads its stdin ONCE.
#
# WHY. The fork census of 2026-08-17 measured this hook exec'ing `jq` three times on one stdin
# payload — .tool_input.command, .tool_input.run_in_background, .session_id — 11.6 ms of a 71.9 ms
# modal path, two thirds pure duplication (backlog 054499f0c342). Collapsing them touches the
# GATE'S OWN INPUT PATH, so the contract is pinned here rather than assumed.
#
# THE RISK THE SHAPE IS CHOSEN AGAINST. $CMD is the value every danger pattern is matched against.
# Line 1 of the parse carries the three scalars tab-separated and everything after the FIRST newline
# is the command verbatim — `@tsv` is deliberately not used, because it escapes a tab as `\t` and
# would silently rewrite any command containing one. (4) and (5) are the assertions that would catch
# that, and (8) is the one that can fail: a mutant using @tsv must corrupt a tab-bearing command.
#
# Cases (1)-(3) and (7) were removed as duplicates: the plain round-trip, the session id and the
# absent-sid placeholder are owned by tests/validate-bash-audit-log.bats (4), (2), (3); the
# run_in_background read is owned behaviourally by tests/validate-bash-goal-guard.bats (the
# background DENY and the foreground PASS under a live goal).

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
  D="$BATS_TEST_TMPDIR"
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  export CC_SHARED_CHECKOUT="$D/shared"; mkdir -p "$D/shared"
  if ! command -v jq >/dev/null 2>&1; then skip "jq not installed"; fi
}

# logline <command> [session-id] [hook] — drive the hook, echo the audit line it appended.
logline() {
  local cmd="$1" sid="${2:-sid-x}" hook="${3:-$HOOK}"
  rm -rf "$HOME/.claude/logs"
  jq -nc --arg c "$cmd" --arg s "$sid" \
    '{tool_name:"Bash",tool_input:{command:$c},session_id:$s}' \
    | bash "$hook" >/dev/null 2>&1 || true
  # `|| true`: a MUTANT hook may abstain before it ever logs, so the file legitimately does not
  # exist on that path. Without this the command substitution in (8) inherits the failure and the
  # control dies before it can assert anything.
  cat "$HOME/.claude/logs/bash-commands.log" 2>/dev/null || true
}

@test "(4) a command containing a TAB survives the parse byte-for-byte" {
  # The whole reason @tsv is not used. A tab here must stay a tab, not become a literal backslash-t.
  cmd="$(printf 'echo r15-tab\tsecond-field')"
  run logline "$cmd"
  [[ "$output" == *"r15-tab"*"second-field"* ]] || false
  [[ "$output" != *'r15-tab\tsecond-field'* ]]
}

@test "(5) a MULTI-LINE command keeps every line, and the meta line is not one of them" {
  cmd="$(printf 'echo one\necho two\necho three')"
  run logline "$cmd"
  [[ "$output" == *"echo one"* ]] || false
  [[ "$output" == *"echo two"* ]] || false
  [[ "$output" == *"echo three"* ]] || false
  # the tab-separated scalars must NOT have leaked into the command body
  [[ "$output" != *"sid-x	"* ]]
}

@test "(6) an EMPTY session_id string is padded, not left to shift the columns" {
  # `//` substitutes for null and false but never for a present-but-empty string — the exact case
  # that would slide run_in_background into the session-id slot.
  rm -rf "$HOME/.claude/logs"
  run bash -c 'jq -nc "{tool_name:\"Bash\",tool_input:{command:\"echo r15-empty-sid\"},session_id:\"\"}" | bash "$0" >/dev/null 2>&1; cat "$HOME/.claude/logs/bash-commands.log"' "$HOOK"
  [[ "$output" == *"[-]"* ]] || false
  [[ "$output" == *"echo r15-empty-sid"* ]]
}

@test "(8) CONTROL — an @tsv mutant CORRUPTS a tab-bearing command, so (4) is not vacuous" {
  MUT="$D/mutant-tsv.sh"
  anchor='(.tool_input.command // empty)'
  grep -qF -- "$anchor" "$HOOK"
  # Replace the two-output form with a single @tsv row: the shape (4) exists to reject.
  # Delimiter is `#`, not `|` — the replacement text CONTAINS a pipe, and sed reads it as the end of
  # the substitution ("bad flag in substitute command: '@'"). Caught by this control failing.
  sed 's#(.tool_input.command // empty)#(.tool_input.command // "") | @tsv#' "$HOOK" > "$MUT"
  chmod +x "$MUT"
  cmd="$(printf 'echo r15-tab\tsecond-field')"
  good=$(logline "$cmd")
  mline=$(logline "$cmd" "sid-x" "$MUT")
  [[ "$good" == *"r15-tab"*"second-field"* ]] || false
  # What the mutant actually does, measured: `A, B | @tsv` parses as `A, (B | @tsv)`, and @tsv on a
  # STRING is a jq error — so the mutant hook abstains via abstain_unclear and never logs at all.
  # That is a strictly worse corruption than a mangled tab: the bash validator silently stops
  # validating. Either way the control's job is to show the real form is load-bearing.
  # Negations LAST — errexit skips a failing negation placed mid-test, which makes it dead code.
  ! [[ "$mline" == "$good" ]]
}
