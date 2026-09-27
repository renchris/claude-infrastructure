#!/usr/bin/env bats
# Auto-memory writes spelled through a SYMLINKED config dir must never raise a permission prompt.
#
# The defect (2026-09-27): on .claude-next/-secondary/-tertiary/-quaternary the session's memory dir
# is reached through a symlink into ~/.claude/projects/, and bin/cc-close-attrib pins the harness's
# autoMemoryDirectory to the REAL path. CC's write carve-out matches the path AS SPELLED, so a Write
# to ~/.claude-next/projects/<slug>/memory/x.md prompted — and hooks/memory-nudge.sh was the thing
# telling the model to use that spelling. Two remedies, both pinned here:
#   1. backup-before-write.sh rewrites file_path to the real path via `updatedInput` (headless A/B
#      on 2.1.280: no hook ⇒ permission_denials 1, rewrite ⇒ 0, same file written).
#   2. memory-nudge.sh names the physical path.
# Lesson: docs/lessons/symlinked-auto-memory-dir-prompts-on-every-write.md

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/backup-before-write.sh"
  NUDGE="$REPO/hooks/memory-nudge.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/projects/-proj/memory" "$HOME/.claude-secondary/projects/-proj"
  # .claude-next style: the WHOLE projects/ dir is a symlink.
  mkdir -p "$HOME/.claude-next"; ln -s "$HOME/.claude/projects" "$HOME/.claude-next/projects"
  # .claude-secondary style: only projects/<slug>/memory is a symlink.
  ln -s "$HOME/.claude/projects/-proj/memory" "$HOME/.claude-secondary/projects/-proj/memory"
  REALMEM="$(cd -P "$HOME/.claude/projects/-proj/memory" && pwd -P)"
  unset CC_MEMPATH_CANON
}

# errexit-live helpers (a bare `[[ ]]` mid-body is exempt from errexit and would pass vacuously)
eq()  { [ "$1" = "$2" ] || { printf 'expected [%s]\n     got [%s]\n' "$2" "$1" >&2; return 1; }; }
has() { printf '%s' "$1" | grep -qF -- "$2"; }

call() { # call <hook> <tool> <file_path> → hook stdout
  jq -nc --arg t "$2" --arg f "$3" '{tool_name:$t, tool_input:{file_path:$f, content:"body", old_string:"a", new_string:"b"}}' \
    | bash "$1"
}
# Empty hook output (no JSON at all) must also read as NONE — jq prints nothing for empty input.
upd() { local v; v="$(printf '%s' "$1" | jq -r '.hookSpecificOutput.updatedInput.file_path // "NONE"')"; printf '%s' "${v:-NONE}"; }

@test "Write of a NEW memory file through a symlinked projects/ is rewritten to the real path" {
  out="$(call "$HOOK" Write "$HOME/.claude-next/projects/-proj/memory/new.md")"
  eq "$(upd "$out")" "$REALMEM/new.md"
  # every other field survives, and no permission decision is taken on the operator's behalf
  eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.content')" "body"
  eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "none"')" "none"
  eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "PreToolUse"
}

@test "a per-slug symlinked memory/ (the -secondary layout) is rewritten too" {
  out="$(call "$HOOK" Write "$HOME/.claude-secondary/projects/-proj/memory/new.md")"
  eq "$(upd "$out")" "$REALMEM/new.md"
}

@test "overwriting an existing memory file keeps the OVERWRITE GUARD and adds the rewrite" {
  printf 'old\n' > "$REALMEM/old.md"
  out="$(call "$HOOK" Write "$HOME/.claude-next/projects/-proj/memory/old.md")"
  eq "$(upd "$out")" "$REALMEM/old.md"
  has "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')" "OVERWRITE GUARD"
  # the backup is keyed on the ONE real path, so every account's writes share one prune bucket
  side="$(ls "$HOME/.claude/backups/"old.md__*.path)"
  eq "$(cat "$side")" "$REALMEM/old.md"
}

@test "Edit of an existing memory file is rewritten (the silent non-plan Edit path)" {
  printf 'a\n' > "$REALMEM/e.md"
  out="$(call "$HOOK" Edit "$HOME/.claude-next/projects/-proj/memory/e.md")"
  eq "$(upd "$out")" "$REALMEM/e.md"
  eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.new_string')" "b"
}

@test "polarity: the real spelling is left alone and a new file emits nothing" {
  out="$(call "$HOOK" Write "$REALMEM/new.md")"
  eq "$out" ""
}

@test "a symlinked path that is NOT a memory file is never rewritten" {
  mkdir -p "$HOME/.claude/projects/-proj/other"
  out="$(call "$HOOK" Write "$HOME/.claude-next/projects/-proj/other/x.md")"
  eq "$out" ""
}

@test "kill switch CC_MEMPATH_CANON=off leaves the input untouched" {
  out="$(CC_MEMPATH_CANON=off call "$HOOK" Write "$HOME/.claude-next/projects/-proj/memory/new.md")"
  eq "$out" ""
}

@test "control: the pre-fix hook from git emits no rewrite for the same write" {
  base="$(git -C "$REPO" log --format=%H -1 --diff-filter=M -S'AUTO-MEMORY PATH CANON' -- hooks/backup-before-write.sh 2>/dev/null)"
  [ -n "$base" ] || skip "fix not committed yet — control replays its parent"
  git -C "$REPO" show "$base^:hooks/backup-before-write.sh" > "$BATS_TEST_TMPDIR/pre.sh"
  out="$(call "$BATS_TEST_TMPDIR/pre.sh" Write "$HOME/.claude-next/projects/-proj/memory/new.md")"
  eq "$(upd "$out")" "NONE"
}

@test "memory-nudge names the PHYSICAL index path, never the symlinked spelling" {
  proj="$BATS_TEST_TMPDIR/proj"; mkdir -p "$proj"; git init -q "$proj"
  slug="$(cd "$proj" && pwd -P | tr '/.' '--')"
  mkdir -p "$HOME/.claude/projects/$slug/memory"
  out=""
  for _ in $(seq 1 12); do
    out="$(printf '{"session_id":"s-canon","cwd":"%s"}' "$proj" \
      | CLAUDE_CONFIG_DIR="$HOME/.claude-next" MEMORY_NUDGE_STATE_DIR="$BATS_TEST_TMPDIR/st" bash "$NUDGE" || true)"
  done
  ctx="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')"
  real="$(cd -P "$HOME/.claude/projects/$slug/memory" && pwd -P)/MEMORY.md"
  has "$ctx" "the index is $real"
  if has "$ctx" ".claude-next/projects"; then echo "nudge still names the symlinked spelling" >&2; return 1; fi
}
