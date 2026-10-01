#!/usr/bin/env bats
# shellcheck disable=SC2016,SC2088  # fixture strings carry literal $HOME/~ exactly as settings.json stores them
# scripts/c10-batch.sh — one operator act for every pending c10 migration.
#
# Pinned: the step list is the staged ledger ∪ un-ledgered c10 files, minus superseded, live and held
# ones; 0037 runs first and 0024 last whatever their numbers; --check rehearses in a scratch HOME and
# leaves the real one byte-identical; --confirm runs, verifies each step and keeps every account
# linked; a failing step stops the batch and --rollback restores the forked files byte-for-byte; a
# decision hold opens only when its packet is actioned.
#
# Hermetic: a fixture repo (the REAL 0037 + bin/cc-settings-parity, plus small fake migrations) and a
# scratch HOME holding forked account settings, exactly the live shape on 2026-09-30.

setup() {
  REAL="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  FX="$BATS_TEST_TMPDIR/repo"; mkdir -p "$FX/migrations" "$FX/bin" "$FX/scripts" "$FX/hooks"
  cp "$REAL/migrations/0037-settings-parity.sh" "$FX/migrations/"
  cp "$REAL/bin/cc-settings-parity" "$FX/bin/"
  cp "$REAL/scripts/c10-batch.sh" "$FX/scripts/"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/autonomy/migrations/staged" "$HOME/Development"
  ln -s "$FX" "$HOME/Development/claude-infrastructure"
  ln -s "$FX/bin" "$HOME/.claude/bin"
  export CC_C10_REPO="$FX" CC_MIGRATIONS_STATE="$HOME/.claude/autonomy/migrations"
  export CC_DECIDE_BIN="$BATS_TEST_TMPDIR/cc-decide"
  printf '#!/bin/bash\necho "[]"\n' > "$CC_DECIDE_BIN"; chmod +x "$CC_DECIDE_BIN"
  printf '{"accounts":[{"name":"next","config_dir":"~/.claude-next"},{"name":"next3","config_dir":"~/.claude-tertiary"}]}\n' > "$HOME/.claude/accounts.json"
  jq -n '{alive: true, hooks: {PreToolUse: [{matcher: "Bash", hooks: [{type: "command", command: "~/.claude/hooks/a.sh"}]}]}}' > "$HOME/.claude/settings.json"
  for a in next tertiary; do mkdir -p "$HOME/.claude-$a"; cp "$HOME/.claude/settings.json" "$HOME/.claude-$a/settings.json"; done
  # a jq edit of the REAL shared file (README rule 7), as every fixture migration does
  EDIT='f="$HOME/.claude/settings.json"; r="$(cd "$HOME/.claude" && pwd -P)/settings.json"; jq "$1" "$r" > "$r.t" && mv "$r.t" "$r"'
  mk 0050-add-key        'bash -c '"'$EDIT'"' _ ".fixture_key = 1"' 'jq -e ".fixture_key == 1" "$HOME/.claude/settings.json"'
  mk 0060-prepend-other  'bash -c '"'$EDIT'"' _ ".hooks.PreToolUse = [{matcher:\"*\",hooks:[{type:\"command\",command:\"~/.claude/hooks/other.sh\"}]}] + .hooks.PreToolUse"' \
                         'jq -e "[.hooks.PreToolUse[].hooks[].command] | index(\"~/.claude/hooks/other.sh\") != null" "$HOME/.claude/settings.json"'
  mk 0024-unit-gate-registration 'bash -c '"'$EDIT'"' _ ".hooks.PreToolUse = [{matcher:\"*\",hooks:[{type:\"command\",command:\"~/.claude/hooks/unit-gate.sh\"}]}] + .hooks.PreToolUse"' \
                         'jq -e "[.hooks.PreToolUse[].hooks[].command] | index(\"~/.claude/hooks/unit-gate.sh\") != null" "$HOME/.claude/settings.json"'
  mk 0051-superseded 'exit 1' 'false' '# migration-superseded-by: 0050 — fixture'
  mk 0052-manual 'exit 1' 'false' '# migration-batch-hold: manual — drives a TUI'
  mk 0053-decided 'bash -c '"'$EDIT'"' _ ".decided = 1"' 'jq -e ".decided == 1" "$HOME/.claude/settings.json"' '# migration-batch-hold: decision abc123def456'
  mk 0054-live 'exit 1' 'jq -e ".alive == true" "$HOME/.claude/settings.json"'
  for n in 0037-settings-parity 0050-add-key 0060-prepend-other 0024-unit-gate-registration 0051-superseded 0052-manual 0053-decided 0054-live; do
    printf '{"name":"%s","class":"c10"}\n' "$n" > "$CC_MIGRATIONS_STATE/staged/$n.json"
  done
}

# mk <name> <body> <verify> [extra header line]
mk() {
  { printf '#!/bin/bash\n# migration-class: c10\n# migration-step: fixture %s\n' "$1"
    printf '# migration-run: bash ~/Development/claude-infrastructure/migrations/%s.sh\n' "$1"
    printf '# migration-verify: %s\n' "$3"
    [ -n "${4:-}" ] && printf '%s\n' "$4"
    printf 'set -u\n%s\n' "$2"
  } > "$FX/migrations/$1.sh"
}
batch() { bash "$FX/scripts/c10-batch.sh" "$@"; }
sums() { for f in "$HOME"/.claude/settings.json "$HOME"/.claude-*/settings.json; do [ -L "$f" ] && printf 'L '; shasum "$f"; done; }

@test "--list: 0037 first, 0024 last, the rest lexical; superseded, live and held are named, not run" {
  run batch --list
  [ "$status" -eq 0 ]
  local steps; steps="$(printf '%s\n' "$output" | sed -n 's/^ *[0-9][0-9]*\. //p' | tr '\n' ' ')"
  [ "$steps" = "0037-settings-parity 0050-add-key 0060-prepend-other 0024-unit-gate-registration " ]
  [[ "$output" == *"dropped 0051-superseded — superseded: 0050"* ]] || false
  [[ "$output" == *"held    0052-manual — manual"* ]] || false
  [[ "$output" == *"held    0053-decided — decision abc123def456"* ]] || false
  [[ "$output" == *"live    0054-live"* ]] || false
}

@test "the step list is exactly the staged ledger's runnable c10 entries" {
  run batch --list
  local listed staged
  listed="$(printf '%s\n' "$output" | sed -n 's/^ *[0-9][0-9]*\. //p' | sort | tr '\n' ' ')"
  staged="$(for j in "$CC_MIGRATIONS_STATE"/staged/*.json; do basename "$j" .json; done | grep -v -e 0051 -e 0052 -e 0053 -e 0054 | sort | tr '\n' ' ')"
  [ "$listed" = "$staged" ]
}

@test "--check rehearses GREEN on a FORKED fleet and leaves the real HOME byte-identical" {
  local before; before="$(sums)"
  run batch --check
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"PASS  0037-settings-parity"* ]] || false
  [[ "$output" == *"PASS  final — PreToolUse[0] is unit-gate.sh"* ]] || false
  [[ "$output" == *"REHEARSAL GREEN — 4 step(s)"* ]] || false
  [ "$(sums)" = "$before" ]
}

@test "--confirm: runs in order, links every account, unit-gate ends first, --verify then passes" {
  run batch --verify; [ "$status" -eq 1 ]
  run batch --confirm settings.json
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -L "$HOME/.claude-next/settings.json" ] && [ -L "$HOME/.claude-tertiary/settings.json" ] || false
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$HOME/.claude/settings.json")" = "~/.claude/hooks/unit-gate.sh" ]
  run batch --verify; [ "$status" -eq 0 ]
  [[ "$output" == *"HELD      0052-manual"* ]] || false
}

@test "a failing step STOPS the batch, and --rollback restores the forked files byte-for-byte" {
  mk 0055-fails 'exit 7' 'false'
  local before; before="$(sums)"
  run batch --confirm settings.json
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL  0055-fails — run exited 7"* ]] || false
  [[ "$output" != *"0060-prepend-other"* ]] || false
  local bk; bk="$(printf '%s\n' "$output" | sed -n 's/.*--rollback //p' | head -1)"
  [ -f "$bk/MANIFEST" ]
  run batch --rollback "$bk"; [ "$status" -eq 0 ]
  [ "$(sums)" = "$before" ]
}

@test "a decision hold opens only once its packet is actioned" {
  printf '#!/bin/bash\necho %s\n' "'[{\"id\":\"abc123def456\",\"status\":\"actioned\"}]'" > "$CC_DECIDE_BIN"
  run batch --list
  [[ "$output" == *"0053-decided"* ]] && [[ "$output" != *"held    0053-decided"* ]] || false
}

@test "usage: --confirm must name its target; an unknown verb is rc 2" {
  run batch --confirm; [ "$status" -eq 2 ]
  run batch --bogus; [ "$status" -eq 2 ]
}
