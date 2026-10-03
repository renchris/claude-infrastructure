#!/usr/bin/env bats
# cc-instructions-variant — the operator's switch for the machine's global instructions variant.
#
# Pins the contract docs/plans/INSTRUCTION_BUDGET.md D2/D4 depends on: `set <variant>` records the
# global line and copies that variant into ~/.claude/CLAUDE.md as a REGULAR file (a symlink still
# double-loads on 2.1.114); `set <account> <variant>` is refused, because any account CLAUDE.md that
# resolves elsewhere re-creates the ancestor-walk double load; `reset` puts a legacy (0042) account back
# on the shared file through the real mirror; `status` names every account that still double-loads.
# Hermetic: scratch HOME with its own accounts.json and the repo's mirror lib linked in.
# RED-proof: on the pre-2026-10-03 tool, `set next3 slim` exits 0 and re-points the account, and
# `set slim` is a usage error — the refusal and global-set tests below both fail there.

setup() {
  unset CC_BATS_ACTIVE
  export HOME="$BATS_TEST_TMPDIR/home"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLI="$REPO/bin/cc-instructions-variant"
  mkdir -p "$HOME/.claude/lib" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary"
  ln -s "$REPO/lib/config-mirror.zsh" "$HOME/.claude/lib/config-mirror.zsh"
  printf 'full rules\n' > "$HOME/.claude/CLAUDE.full.md"
  printf 'slim rules\n' > "$HOME/.claude/CLAUDE.slim.md"
  cp "$HOME/.claude/CLAUDE.full.md" "$HOME/.claude/CLAUDE.md"
  printf '{"accounts":[{"name":"next3","config_dir":"~/.claude-tertiary"},{"name":"next4","config_dir":"~/.claude-quaternary"}]}\n' \
    > "$HOME/.claude/accounts.json"
  ln -s "$HOME/.claude/CLAUDE.md" "$HOME/.claude-tertiary/CLAUDE.md"
  ln -s "$HOME/.claude/CLAUDE.md" "$HOME/.claude-quaternary/CLAUDE.md"
  mkdir -p "$HOME/.claude/rules" "$HOME/.claude/rules.slim"
  ln -s "$HOME/.claude/rules" "$HOME/.claude-tertiary/rules"
  ln -s "$HOME/.claude/rules" "$HOME/.claude-quaternary/rules"
}

legacy_slim() {  # put next3 on the 0042 per-account arm, the state migration 0053 undoes
  printf '.claude-tertiary slim\n' > "$HOME/.claude/instruction-variants"
  ln -sfn "$HOME/.claude/CLAUDE.slim.md" "$HOME/.claude-tertiary/CLAUDE.md"
  ln -sfn "$HOME/.claude/rules.slim" "$HOME/.claude-tertiary/rules"
}

@test "set <variant>: global line recorded, variant copied over a symlinked CLAUDE.md as a regular file, logged" {
  rm "$HOME/.claude/CLAUDE.md"; ln -s "$HOME/.claude/CLAUDE.full.md" "$HOME/.claude/CLAUDE.md"
  run "$CLI" set slim
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.claude/CLAUDE.md" ]
  cmp "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.slim.md"
  [ "$(cat "$HOME/.claude/CLAUDE.full.md")" = "full rules" ]   # the copy did not write through the link
  grep -qx 'global slim' "$HOME/.claude/instruction-variants"
  grep -q '"account":"global","variant":"slim","action":"set"' "$HOME/.claude/autonomy/instruction-variants.jsonl"
  # account links are untouched: re-pointing them is migration 0053's, not this command's
  [ "$(readlink "$HOME/.claude-tertiary/CLAUDE.md")" = "$HOME/.claude/CLAUDE.md" ]
}

@test "set full: the full text goes back into CLAUDE.md, replacing the global line" {
  "$CLI" set slim
  run "$CLI" set full
  [ "$status" -eq 0 ]
  cmp "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.full.md"
  [ "$(grep -c '^global ' "$HOME/.claude/instruction-variants")" -eq 1 ]
  grep -qx 'global full' "$HOME/.claude/instruction-variants"
}

@test "set <account> <variant> is refused and changes nothing" {
  run "$CLI" set next3 slim
  [ "$status" -eq 2 ]
  [[ "$output" == *"variants are global"* ]] || false
  [ ! -e "$HOME/.claude/instruction-variants" ]
  [ "$(readlink "$HOME/.claude-tertiary/CLAUDE.md")" = "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude-tertiary/rules")" = "$HOME/.claude/rules" ]
  cmp "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.full.md"
}

@test "set with an undeployed variant refuses and changes nothing" {
  run "$CLI" set nosuch
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/.claude/instruction-variants" ]
  cmp "$HOME/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.full.md"
}

@test "reset: a legacy per-account arm goes back to the shared file through the mirror, logged" {
  legacy_slim
  run "$CLI" reset next3
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.claude-tertiary/CLAUDE.md")" = "$HOME/.claude/CLAUDE.md" ]
  [ "$(readlink "$HOME/.claude-tertiary/rules")" = "$HOME/.claude/rules" ]
  run grep -q 'claude-tertiary' "$HOME/.claude/instruction-variants"
  [ "$status" -ne 0 ]
  grep -q '"action":"reset"' "$HOME/.claude/autonomy/instruction-variants.jsonl"
}

@test "an unknown account is a usage error" {
  run "$CLI" reset nextX
  [ "$status" -eq 2 ]
  [ ! -e "$HOME/.claude/instruction-variants" ]
}

@test "status: DUPLICATE names an account whose CLAUDE.md or rules resolve elsewhere, and only that one" {
  run "$CLI" status
  [ "$status" -eq 0 ]
  [[ "$output" != *DUPLICATE* ]] || false
  echo "$output" | grep -q '^global variant: slim'
  echo "$output" | grep -q 'variants available: full slim'
  legacy_slim
  run "$CLI" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -Eq '^\.claude-tertiary +slim '
  echo "$output" | grep -q '^DUPLICATE: .claude-tertiary/CLAUDE.md resolves to'
  echo "$output" | grep -q '^DUPLICATE: .claude-tertiary/rules resolves to'
  [ "$(echo "$output" | grep -c '^DUPLICATE: .claude-quaternary')" -eq 0 ]
}

@test "status: a variant derived from the current full text is in sync; an edit to it makes it STALE" {
  local h; h="$(shasum -a 256 "$HOME/.claude/CLAUDE.full.md" | cut -c1-16)"
  printf '<!-- instructions-variant: slim · derived-from CLAUDE.global.md sha256:%s -->\nslim rules\n' "$h" \
    > "$HOME/.claude/CLAUDE.slim.md"
  run "$CLI" status
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "CLAUDE.slim.md: in sync with the full text ($h)"
  printf 'full rules, edited\n' > "$HOME/.claude/CLAUDE.full.md"
  run "$CLI" status
  echo "$output" | grep -q "CLAUDE.slim.md: STALE, derived from $h"
}
