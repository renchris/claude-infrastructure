#!/usr/bin/env bats
# backup-prune-identity — the write-backup prune must be keyed by SOURCE PATH, not basename
# (audit 09 D-8).
#
# `hooks/backup-before-write.sh:83-92` kept 10 per BASENAME. Every CLAUDE.md, SKILL.md,
# README.md, page.tsx across every repo shared ONE 10-slot bucket, so a busy repo could evict
# another repo's only backup — the exact failure the overwrite guard exists to prevent. The
# `.path` sidecar already preserves the identity; the prune ignored it. Secondary bug:
# `find -print0 | xargs -0 ls -t | tail -n +11` re-sorts PER xargs BATCH, so at high counts it
# deletes from the wrong end.
#
# Harness laws: L1 the fixture drives the REAL hook with the literal PreToolUse payload (no
# hand-built backup files — the naming/sidecar contract comes from the producer); L2 the
# assertion keys on the failure-distinct count (a shared bucket leaves one source with <10);
# L3 `[ ]` / `grep -q` only; L4 a positive (both sources keep 10) AND a negative (a single
# source is still capped at 10, so a "prune nothing" bug goes RED).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/backup-before-write.sh"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  BACKUP_DIR="$HOME/.claude/backups"
  SRC_A="$BATS_TEST_TMPDIR/repo-a/CLAUDE.md"
  SRC_B="$BATS_TEST_TMPDIR/repo-b/CLAUDE.md"
  mkdir -p "$(dirname "$SRC_A")" "$(dirname "$SRC_B")"
  printf 'alpha\n' > "$SRC_A"
  printf 'beta\n'  > "$SRC_B"
}

payload() { # <file>
  jq -nc --arg f "$1" \
    '{session_id:"sid-bk",hook_event_name:"PreToolUse",tool_name:"Write",
      tool_input:{file_path:$f,content:"x"}}'
}

# drive the real hook N times against <file>
write_n() { # <file> <n>
  local f="$1" n="$2" i
  for ((i = 0; i < n; i++)); do
    printf '%s' "$(payload "$f")" | bash "$HOOK" >/dev/null
  done
}

# how many surviving .bak files have a sidecar naming <file> as their source
backups_for() { # <file>
  local p c=0
  for p in "$BACKUP_DIR"/*.path; do
    [ -f "$p" ] || continue
    [ "$(cat "$p")" = "$1" ] || continue
    [ -f "${p%.path}.bak" ] && c=$((c + 1))
  done
  printf '%s' "$c"
}

@test "two same-basename sources × 12 writes each → EACH keeps 10 (no cross-repo eviction)" {
  write_n "$SRC_A" 12
  write_n "$SRC_B" 12
  [ "$(backups_for "$SRC_A")" -eq 10 ]
  [ "$(backups_for "$SRC_B")" -eq 10 ]
}

@test "interleaved writes do not let the busier source evict the quieter one" {
  local i
  for ((i = 0; i < 12; i++)); do
    write_n "$SRC_A" 1
    # GUARD, not an assertion: SRC_B is written only on the first 3 iterations, so the
    # condition being FALSE is the intended path for i>=3. Written as an `if` rather than
    # `[ … ] && … || true` so a future dead-assertion sweep cannot "revive" it back into
    # `|| false` — which is exactly how it broke (47a53504). errexit still covers write_n.
    if [ "$i" -lt 3 ]; then write_n "$SRC_B" 1; fi
  done
  [ "$(backups_for "$SRC_A")" -eq 10 ]
  [ "$(backups_for "$SRC_B")" -eq 3 ]
}

@test "a single source is still capped at 10 (prune is not a no-op)" {
  write_n "$SRC_A" 14
  [ "$(backups_for "$SRC_A")" -eq 10 ]
}

@test "every surviving .bak keeps its .path sidecar (no orphans left by the prune)" {
  write_n "$SRC_A" 12
  local b n=0
  for b in "$BACKUP_DIR"/*.bak; do
    [ -f "$b" ] || continue
    [ -f "${b%.bak}.path" ]
    n=$((n + 1))
  done
  [ "$n" -eq 10 ]
}

@test "the overwrite-guard JSON is still emitted (prune change is additive)" {
  run bash "$HOOK" <<<"$(payload "$SRC_A")"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'OVERWRITE GUARD'
}
