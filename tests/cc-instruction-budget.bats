#!/usr/bin/env bats
# cc-instruction-budget — the fleet auditor (census / assert / file / publish) and the land ratchet
# (range) over the one predicate in hooks/lib/instruction_budget.py (INSTRUCTION_BUDGET.md D7).
#
# The defect the auditor pins is the one nothing saw: migration 0042 re-pointed each account's
# CLAUDE.md at CLAUDE.slim.md, which broke the realpath dedupe that had hidden the ancestor-walk copy
# of ~/.claude/CLAUDE.md, so every session loaded the global instructions twice for a week. A census
# that emulates the loader per (config dir x cwd) sees it; the dedupe invariant names it.
#
# RED-proof: the dedupe test runs the 0042 shape and then the D2 shape on ONE fixture, so it fails if
# the invariant is not computed (both shapes would read alike). The range tests pair each refusal
# with a passing twin on the same repo (shrink, a sibling's untouched over-budget file), so a
# refusal cannot come from an unrelated error: errors are rc 2, asserted separately.
#
# Hermetic: $HOME is a fixture (the census reads ~/.claude*/projects transcripts and accounts.json
# under it, and only cwds under $HOME are fleet), CLAUDE_CONFIG_DIR is unset, and cc-backlog is a
# stub that records argv.
# shellcheck disable=SC2030,SC2031  # per-test env exports are deliberate

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  IB="$REPO/bin/cc-instruction-budget"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/rules"
  unset CLAUDE_CONFIG_DIR
  export CC_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
  jq '.enforce = true' "$REPO/config/instruction-budget.json" > "$BATS_TEST_TMPDIR/ib.json"
  export CC_IB_TEST=1 CC_IB_CONFIG="$BATS_TEST_TMPDIR/ib.json"
  # the global layer: full text at ~/.claude/CLAUDE.md, the slim variant beside it
  xs 30000 > "$HOME/.claude/CLAUDE.md"
  ys 10000 > "$HOME/.claude/CLAUDE.slim.md"
  jq -n '{accounts:[{config_dir:"~/.claude-a"}]}' > "$HOME/.claude/accounts.json"
  mkdir -p "$HOME/.claude-a"
  ln -s "$HOME/.claude/CLAUDE.slim.md" "$HOME/.claude-a/CLAUDE.md"   # the 0042 shape
  R="$HOME/Development/app"; mkdir -p "$R/.git" "$R/.claude/rules"
  printf 'app rules\n' > "$R/CLAUDE.md"
  mkdir -p "$HOME/.claude/projects/-app"
  jq -nc --arg c "$R" '{type:"user", cwd:$c}' > "$HOME/.claude/projects/-app/s1.jsonl"
}

xs() { head -c "$1" /dev/zero | tr '\0' x; }
ys() { head -c "$1" /dev/zero | tr '\0' y; }
has()   { printf '%s' "$1" | grep -qF -- "$2"; }
hasnt() { if printf '%s' "$1" | grep -qF -- "$2"; then return 1; fi; }

@test "census + assert name the 0042 double load, and the D2 link shape clears it" {
  run "$IB" census --days 1
  [ "$status" -eq 0 ]
  has "$output" '| repo '
  has "$output" "/Development/app "
  has "$output" 'DUP'
  run "$IB" assert --class dedupe
  [ "$status" -eq 1 ]
  has "$output" 'BREACH [dedupe]'
  has "$output" "/.claude/CLAUDE.md loaded as Project"
  # D2: the account links back to the canonical ~/.claude/CLAUDE.md, holding the chosen variant
  cp "$HOME/.claude/CLAUDE.slim.md" "$HOME/.claude/CLAUDE.md"
  ln -sfn "$HOME/.claude/CLAUDE.md" "$HOME/.claude-a/CLAUDE.md"
  run "$IB" assert --class dedupe
  [ "$status" -eq 0 ]
  has "$output" 'GREEN'
}

@test "identical content under two realpaths is a duplicate load too" {
  cp "$HOME/.claude/CLAUDE.slim.md" "$HOME/.claude/CLAUDE.md"   # W1 step 1, before the links move
  run "$IB" assert --class dedupe
  [ "$status" -eq 1 ]
  has "$output" 'identical content loaded twice'
}

@test "assert: an over-budget repo tier is its own class, keyed by repo, and --repo reaches it" {
  xs 35000 > "$R/.claude/rules/a.md"; xs 30000 > "$R/.claude/rules/b.md"
  run "$IB" assert --class repo-app --repo "$R"
  [ "$status" -eq 1 ]
  has "$output" 'BREACH [repo-app]'
  has "$output" 'repo tier 65,'
  printf -- '---\npaths:\n  - src/**\n---\n%s' "$(xs 30000)" > "$R/.claude/rules/b.md"
  run "$IB" assert --class repo-app --repo "$R"
  [ "$status" -eq 0 ]
}

@test "assert is a NON-VERDICT (rc 3), not green, when it cannot measure" {
  export CC_IB_CONFIG="$BATS_TEST_TMPDIR/missing.json"
  run "$IB" assert
  [ "$status" -eq 3 ]
  hasnt "$output" 'GREEN'
}

@test "file: one condition-keyed, self-falsifying row per breach class; nothing when clean or unmeasured" {
  log="$BATS_TEST_TMPDIR/filed.argv"; stub="$BATS_TEST_TMPDIR/cc-backlog"
  printf '#!/bin/bash\nprintf "%%s\\n" "$@" >> "%s"\nexit 0\n' "$log" > "$stub"; chmod +x "$stub"
  export CC_BACKLOG_BIN="$stub"
  run "$IB" file
  [ "$status" -eq 1 ]
  grep -qxF 'instruction-budget-dedupe' "$log"
  grep -qxF -- '--falsifier' "$log"
  grep -qE 'assert --class dedupe$' "$log"
  [ "$(grep -cxF -- '--condition' "$log")" -eq "$(grep -c 'filed/updated' <<<"$output")" ]
  # clean fleet: D2 shape, small tiers ⇒ nothing filed
  : > "$log"
  cp "$HOME/.claude/CLAUDE.slim.md" "$HOME/.claude/CLAUDE.md"
  ln -sfn "$HOME/.claude/CLAUDE.md" "$HOME/.claude-a/CLAUDE.md"
  run "$IB" file
  [ "$status" -eq 0 ]
  [ ! -s "$log" ]
  # non-verdict ⇒ nothing filed
  export CC_IB_CONFIG="$BATS_TEST_TMPDIR/missing.json"
  run "$IB" file
  [ "$status" -eq 3 ]
  [ ! -s "$log" ]
}

@test "publish writes the @import targets the gate's pre-screen matches" {
  xs 100 > "$R/notes.md"
  printf 'see @notes.md\n' > "$R/CLAUDE.md"
  run "$IB" publish --days 1
  [ "$status" -eq 0 ]
  grep -qxF "$R/notes.md" "$HOME/.claude/state/instruction-budget/loaded-set.txt"
}

# ── range: the land ratchet ──────────────────────────────────────────────────────────────────────

mkgit() {
  G="$BATS_TEST_TMPDIR/g"; mkdir -p "$G/.claude/rules"
  g() { git -C "$G" -c core.hooksPath=/dev/null -c core.excludesFile=/dev/null -c commit.gpgSign=false \
          -c user.name=t -c user.email=t@t "$@"; }
  g init -q
  xs 20000 > "$G/.claude/rules/lessons.md"
  xs 45000 > "$G/.claude/rules/sibling-fat.md"   # a sibling already left this over budget
  g add -A; g commit -qm base
}

@test "range refuses this land's own growth past budget and passes a shrink" {
  mkgit
  xs 41000 > "$G/.claude/rules/lessons.md"; g commit -qam grow
  run "$IB" range HEAD~1..HEAD --repo "$G"
  [ "$status" -eq 1 ]
  has "$output" 'REFUSE'
  has "$output" 'lessons.md'
  xs 100 > "$G/.claude/rules/lessons.md"; g commit -qam shrink
  run "$IB" range HEAD~1..HEAD --repo "$G"
  [ "$status" -eq 0 ]
  has "$output" 'clean'
}

@test "range does not convict a land for a sibling's over-budget file it did not grow" {
  mkgit
  printf 'more\n' >> "$G/.claude/rules/lessons.md"; g commit -qam small
  run "$IB" range HEAD~1..HEAD --repo "$G"
  [ "$status" -eq 0 ]
  printf 'more\n' >> "$G/.claude/rules/sibling-fat.md"; g commit -qam grow-fat
  run "$IB" range HEAD~1..HEAD --repo "$G"
  [ "$status" -eq 1 ]
}

@test "range is SHADOW (rc 0) while enforce is false, and a NON-VERDICT (rc 2) on a bad range" {
  mkgit
  xs 41000 > "$G/.claude/rules/lessons.md"; g commit -qam grow
  jq '.enforce = false' "$REPO/config/instruction-budget.json" > "$CC_IB_CONFIG"
  run "$IB" range HEAD~1..HEAD --repo "$G"
  [ "$status" -eq 0 ]
  has "$output" 'SHADOW'
  run "$IB" range nosuchref..HEAD --repo "$G"
  [ "$status" -eq 2 ]
  has "$output" 'NON-VERDICT'
}

@test "selftest is green on this tree (the land gate's selftest_ok contract)" {
  run "$IB" --selftest
  [ "$status" -eq 0 ]
  has "$output" '0 failed'
}
