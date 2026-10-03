#!/usr/bin/env bats
# instruction-budget — the Write/Edit/MultiEdit gate for always-loaded instruction files, run
# through its live host hooks/backup-before-write.sh (docs/plans/INSTRUCTION_BUDGET.md D7).
#
# The defect this pins: always-loaded instruction files grew to 180k-430k chars per session with
# nothing refusing growth (reso's 151.7k bottle ledger was an always-loaded rule). The gate refuses
# only GROWTH past a budget; shrinking or same-size writes always pass, so it can never refuse the
# cure for its own condition. `paths:` frontmatter is judged against its own conditional cap, so it
# is not an unbudgeted escape (critic.md §2.5).
#
# RED-proof: every refusal below is selected by arithmetic on a projected size; with the
# INSTRUCTION BUDGET block deleted from the host (or placed after its `[ ! -f ] && exit 0`), the
# "growth refused" and "new rule file refused" tests fail, because no deny is emitted. The
# allow-cases are paired with a refused twin on the same fixture, so an allow cannot pass because
# a different guard or an early exit swallowed the write.
#
# Every hook run goes through a SYMLINK to the host: live, ~/.claude/hooks/backup-before-write.sh is
# a symlink into the checkout, and a lib resolved from the undereferenced path fails open silently.
# shellcheck disable=SC2016  # bash -c bodies are literal; their $1/$2 are the child's positionals

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$CLAUDE_CONFIG_DIR"
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  mkdir -p "$BATS_TEST_TMPDIR/hooks"
  ln -s "$REPO/hooks/backup-before-write.sh" "$BATS_TEST_TMPDIR/hooks/bbw.sh"
  HOOK="$BATS_TEST_TMPDIR/hooks/bbw.sh"
  # The real budgets, with enforcement switched on; the seam is honoured only under CC_IB_TEST=1.
  jq '.enforce = true' "$REPO/config/instruction-budget.json" > "$BATS_TEST_TMPDIR/ib.json"
  export CC_IB_TEST=1 CC_IB_CONFIG="$BATS_TEST_TMPDIR/ib.json"
  R="$BATS_TEST_TMPDIR/repo"; mkdir -p "$R/.git" "$R/.claude/rules" "$R/docs"
}

has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }
xs()    { head -c "$1" /dev/zero | tr '\0' x; }

write_payload() { # <file> <content>
  jq -nc --arg f "$1" --arg c "$2" --arg cwd "$R" \
    '{tool_name:"Write", session_id:"t", cwd:$cwd, tool_input:{file_path:$f, content:$c}}'
}
edit_payload() { # <file> <old> <new>
  jq -nc --arg f "$1" --arg o "$2" --arg n "$3" --arg cwd "$R" \
    '{tool_name:"Edit", session_id:"t", cwd:$cwd, tool_input:{file_path:$f, old_string:$o, new_string:$n}}'
}
gate() { run bash -c 'printf "%s" "$1" | "$2"' _ "$1" "$HOOK"; }

@test "growth of an always-loaded rule past 40k is refused, naming a destination and not paths:" {
  f="$R/.claude/rules/ledger.md"; xs 39000 > "$f"
  gate "$(write_payload "$f" "$(xs 41000)")"
  [ "$status" -eq 0 ]
  has "$output" '"permissionDecision": "deny"'
  has "$output" 'non-loaded record file'
  has "$output" '41,000'
  hasnt "$output" 'paths:'
}

@test "a file already over budget is shrink-only: shrink and same-size pass, one more char is refused" {
  f="$R/.claude/rules/fat.md"; xs 45000 > "$f"
  gate "$(write_payload "$f" "$(xs 44000)")"
  [ "$status" -eq 0 ]
  hasnt "$output" '"deny"'
  gate "$(edit_payload "$f" "xxxx" "yyyy")"
  hasnt "$output" '"deny"'
  gate "$(edit_payload "$f" "xxxx" "xxxxx")"
  has "$output" '"permissionDecision": "deny"'
}

@test "creating a new rules file that pushes the repo tier past 60k is refused (judged before the fast exit)" {
  xs 35000 > "$R/.claude/rules/a.md"
  f="$R/.claude/rules/new.md"
  [ ! -e "$f" ]
  gate "$(write_payload "$f" "$(xs 30000)")"
  has "$output" '"permissionDecision": "deny"'
  has "$output" 'repo tier'
  gate "$(write_payload "$f" "$(xs 20000)")"
  hasnt "$output" '"deny"'
}

@test "adding paths: to a rule under the conditional cap passes; to one over it is refused" {
  xs 35000 > "$R/.claude/rules/a.md"
  f="$R/.claude/rules/b.md"; xs 30000 > "$f"   # repo tier 65k, already over
  gate "$(write_payload "$f" "$(printf -- '---\npaths:\n  - src/**\n---\n%s' "$(xs 30000)")")"
  hasnt "$output" '"deny"'
  g="$R/.claude/rules/c.md"; xs 45000 > "$g"
  gate "$(write_payload "$g" "$(printf -- '---\npaths:\n  - src/**\n---\n%s' "$(xs 45001)")")"
  has "$output" '"permissionDecision": "deny"'
  has "$output" 'conditional'
}

@test "an Edit that adds an @import of a big doc grows the tier and is refused" {
  printf 'Project rules.\n' > "$R/CLAUDE.md"
  xs 70000 > "$R/docs/big.md"
  gate "$(edit_payload "$R/CLAUDE.md" "Project rules." "Project rules. @docs/big.md")"
  has "$output" '"permissionDecision": "deny"'
  gate "$(edit_payload "$R/CLAUDE.md" "Project rules." "Project rules, docs/big.md")"
  hasnt "$output" '"deny"'
}

@test "the user tier is judged through the config dir, with the user destination" {
  xs 39000 > "$CLAUDE_CONFIG_DIR/CLAUDE.md"
  gate "$(write_payload "$CLAUDE_CONFIG_DIR/CLAUDE.md" "$(xs 41000)")"
  has "$output" '"permissionDecision": "deny"'
  has "$output" 'CLAUDE.global.md'
}

@test "a rules file excluded by claudeMdExcludes is never judged" {
  jq -n '{claudeMdExcludes:["**/.claude/rules/agent-operating-lessons-situational.md"]}' \
    > "$HOME/.claude/settings.json"
  f="$R/.claude/rules/agent-operating-lessons-situational.md"; xs 50000 > "$f"
  gate "$(write_payload "$f" "$(xs 90000)")"
  hasnt "$output" '"deny"'
  f2="$R/.claude/rules/agent-operating-lessons.md"; xs 50000 > "$f2"
  gate "$(write_payload "$f2" "$(xs 90000)")"
  has "$output" '"permissionDecision": "deny"'
}

@test "enforce=false is shadow mode: no deny, a shadow-deny IDL row" {
  jq '.enforce = false' "$REPO/config/instruction-budget.json" > "$CC_IB_CONFIG"
  f="$R/.claude/rules/ledger.md"; xs 39000 > "$f"
  gate "$(write_payload "$f" "$(xs 41000)")"
  hasnt "$output" '"deny"'
  run jq -r 'select(.hook=="backup-before-write:instruction-budget") | .disposition' "$CC_IDL"
  [ "$output" = "shadow-deny" ]
}

@test "the config seam is sealed: without CC_IB_TEST=1 the landed config decides" {
  enforce="$(jq -r '.enforce' "$REPO/config/instruction-budget.json")"
  f="$R/.claude/rules/ledger.md"; xs 39000 > "$f"
  p="$(write_payload "$f" "$(xs 41000)")"
  run env -u CC_IB_TEST bash -c 'printf "%s" "$1" | "$2"' _ "$p" "$HOOK"
  if [ "$enforce" = true ]; then
    has "$output" '"deny"'
  else
    hasnt "$output" '"deny"'
    # the lib RAN and judged under the landed config — not an early exit that skipped it
    run jq -r 'select(.hook=="backup-before-write:instruction-budget") | .disposition' "$CC_IDL"
    [ "$output" = "shadow-deny" ]
  fi
}

@test "fails open: an unreadable config allows the write and logs abstained" {
  export CC_IB_CONFIG="$BATS_TEST_TMPDIR/missing.json"
  f="$R/.claude/rules/ledger.md"; xs 39000 > "$f"
  gate "$(write_payload "$f" "$(xs 41000)")"
  [ "$status" -eq 0 ]
  hasnt "$output" '"deny"'
  run jq -r 'select(.hook=="backup-before-write:instruction-budget") | .disposition' "$CC_IDL"
  [ "$output" = "abstained" ]
}

@test "fails open: a host copy with no lib beside it allows the write" {
  mkdir -p "$BATS_TEST_TMPDIR/bare"; cp "$REPO/hooks/backup-before-write.sh" "$BATS_TEST_TMPDIR/bare/bbw.sh"
  f="$R/.claude/rules/ledger.md"; xs 39000 > "$f"
  run bash -c 'printf "%s" "$1" | "$2"' _ "$(write_payload "$f" "$(xs 41000)")" "$BATS_TEST_TMPDIR/bare/bbw.sh"
  [ "$status" -eq 0 ]
  hasnt "$output" '"deny"'
}

@test "measure counts as the loader does: frontmatter and comment blocks free, astral = 2 units" {
  f="$R/.claude/rules/m.md"
  printf -- '---\ndescription: d\n---\n<!-- note -->\nab\xf0\x9f\x98\x80' > "$f"
  run "$REPO/bin/cc-instruction-budget" measure "$f"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | cut -f2)" = "5" ]
  printf -- '---\npaths:\n  - "**"\n---\nx' > "$f"
  run "$REPO/bin/cc-instruction-budget" measure "$f"
  [ "$(printf '%s' "$output" | cut -f3)" = "always" ]
}
