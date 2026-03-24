#!/bin/bash
# Comprehensive test harness for backup-before-write.sh hook + restore-file.sh script
# Tests all 26 scenarios across hook and restore functionality
#
# Usage: ~/.claude/scripts/test-overwrite-guard.sh [--verbose]
# Exit: 0=all pass, 1=failures, 2=setup error

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test harness globals
TEST_DIR="/tmp/test-overwrite-guard"
BACKUP_DIR="$TEST_DIR/backups"
FIXTURE_DIR="$TEST_DIR/fixtures"
TEST_HOOKS_DIR="$TEST_DIR/hooks"
VERBOSE="${1:-}"

PASSED=0
FAILED=0
TESTS=()

# Cleanup from previous runs
cleanup_env() {
  rm -rf "$TEST_DIR" 2>/dev/null || true
  mkdir -p "$FIXTURE_DIR" "$BACKUP_DIR" "$TEST_HOOKS_DIR"
}

# Helper: Create a mock hook environment
# Args: $1=tool_name, $2=file_path, $3=extra_jq_fields (optional)
create_hook_input() {
  local tool="$1"
  local file="$2"
  local extra="${3:-}"

  if [ -z "$extra" ]; then
    cat <<EOF
{
  "tool_name": "$tool",
  "tool_input": {
    "file_path": "$file"
  }
}
EOF
  else
    cat <<EOF
{
  "tool_name": "$tool",
  "tool_input": {
    "file_path": "$file"
    $extra
  }
}
EOF
  fi
}

# Helper: Run the backup-before-write.sh hook
# Args: $1=tool, $2=file, $3=extra_json_fields (optional)
run_hook() {
  local tool="$1"
  local file="$2"
  local extra="${3:-}"

  HOME="$TEST_DIR" \
  create_hook_input "$tool" "$file" "$extra" \
    | ~/.claude/hooks/backup-before-write.sh 2>&1 || true
}

# Helper: Run restore-file.sh with HOME override
# Args: all args passed to restore-file.sh
run_restore() {
  HOME="$TEST_DIR" ~/.claude/scripts/restore-file.sh "$@" 2>&1 || true
}

# Test assertion helpers
assert_file_exists() {
  local file="$1"
  if [ -f "$file" ]; then
    return 0
  else
    echo "ASSERT FAILED: File does not exist: $file"
    return 1
  fi
}

assert_file_missing() {
  local file="$1"
  if [ ! -f "$file" ]; then
    return 0
  else
    echo "ASSERT FAILED: File should not exist: $file"
    return 1
  fi
}

assert_file_content_equals() {
  local file="$1"
  local expected="$2"
  local actual
  actual=$(cat "$file" 2>/dev/null || echo "")
  if [ "$actual" = "$expected" ]; then
    return 0
  else
    echo "ASSERT FAILED: Content mismatch in $file"
    echo "  Expected: '$expected'"
    echo "  Actual: '$actual'"
    return 1
  fi
}

assert_backup_count() {
  local basename="$1"
  local expected="$2"
  local actual
  actual=$(find "$BACKUP_DIR" -maxdepth 1 -name "${basename}__*.bak" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$actual" -eq "$expected" ]; then
    return 0
  else
    echo "ASSERT FAILED: Backup count mismatch for $basename"
    echo "  Expected: $expected, Actual: $actual"
    return 1
  fi
}

assert_output_contains() {
  local output="$1"
  local pattern="$2"
  if echo "$output" | grep -q "$pattern"; then
    return 0
  else
    echo "ASSERT FAILED: Output does not contain pattern: $pattern"
    echo "  Output: $output"
    return 1
  fi
}

# Test runner
run_test() {
  local name="$1"
  local func="$2"

  TESTS+=("$name")

  if [ -n "$VERBOSE" ]; then
    echo "▶ $name"
  fi

  if $func 2>/dev/null; then
    PASSED=$((PASSED + 1))
    if [ -n "$VERBOSE" ]; then
      echo -e "${GREEN}✓${NC} $name"
    fi
  else
    FAILED=$((FAILED + 1))
    echo -e "${RED}✗${NC} $name"
  fi
}

# ============================================================================
# HOOK TESTS (1-15)
# ============================================================================

test_hook_1_write_existing_non_plan() {
  # Write to existing non-plan file → backup created + OVERWRITE GUARD
  local file="$FIXTURE_DIR/test.txt"
  echo "original content" > "$file"

  local output
  output=$(run_hook "Write" "$file")

  assert_backup_count "test.txt" 1 || return 1
  assert_output_contains "$output" "OVERWRITE GUARD" || return 1
}

test_hook_2_write_existing_plan_file() {
  # Write to existing plan file → backup + OVERWRITE GUARD + PLAN RULES
  local file="$TEST_DIR/.claude/plans/test-plan.md"
  mkdir -p "$(dirname "$file")"
  echo "# Plan" > "$file"

  local output
  output=$(run_hook "Write" "$file")

  assert_backup_count "test-plan.md" 1 || return 1
  assert_output_contains "$output" "OVERWRITE GUARD" || return 1
  assert_output_contains "$output" "PLAN UPDATE RULES" || return 1
}

test_hook_3_edit_existing_plan_file() {
  # Edit to existing plan file → PLAN GUARD + PLAN RULES (no backup)
  local file="$TEST_DIR/.claude/plans/another-plan.md"
  mkdir -p "$(dirname "$file")"
  echo "# Plan" > "$file"

  local output
  output=$(run_hook "Edit" "$file")

  assert_backup_count "another-plan.md" 0 || return 1
  assert_output_contains "$output" "PLAN GUARD" || return 1
  assert_output_contains "$output" "PLAN UPDATE RULES" || return 1
}

test_hook_4_edit_existing_non_plan_file() {
  # Edit to existing non-plan file → silent (no output)
  local file="$FIXTURE_DIR/code.ts"
  echo "let x = 1;" > "$file"

  local output
  output=$(run_hook "Edit" "$file")

  # Silent = empty output or only whitespace
  if [ -z "$(echo "$output" | tr -d ' \t\n')" ]; then
    return 0
  else
    echo "ASSERT FAILED: Edit on non-plan should be silent, got: $output"
    return 1
  fi
}

test_hook_5_write_non_existent_file() {
  # Write to non-existent file → silent (no backup, no warning)
  local file="$FIXTURE_DIR/nonexistent.txt"

  local output
  output=$(run_hook "Write" "$file")

  # Should not create backup (file doesn't exist yet)
  assert_backup_count "nonexistent.txt" 0 || return 1
}

test_hook_6_edit_non_existent_file() {
  # Edit to non-existent file → silent
  local file="$FIXTURE_DIR/missing.ts"

  local output
  output=$(run_hook "Edit" "$file")

  # Should be silent
  if [ -z "$(echo "$output" | tr -d ' \t\n')" ]; then
    return 0
  else
    return 1
  fi
}

test_hook_7_multiedit_existing_file() {
  # MultiEdit to existing file → backup + OVERWRITE GUARD
  local file="$FIXTURE_DIR/component.tsx"
  echo "export function Foo() {}" > "$file"

  local output
  output=$(run_hook "MultiEdit" "$file")

  assert_backup_count "component.tsx" 1 || return 1
  assert_output_contains "$output" "OVERWRITE GUARD" || return 1
}

test_hook_8_symlink_plan_file() {
  # Symlink plan file → backup of real content (not symlink)
  local real_file="$TEST_DIR/.claude/real-plan.md"
  local symlink_file="$TEST_DIR/.claude/plans/symlink-plan.md"
  mkdir -p "$(dirname "$symlink_file")"

  echo "# Real Plan Content" > "$real_file"
  ln -s "$real_file" "$symlink_file"

  run_hook "Write" "$symlink_file" >/dev/null

  # Verify backup exists and contains real content (not symlink target)
  local backup
  backup=$(find "$BACKUP_DIR" -name "symlink-plan.md__*.bak" | head -1)
  [ -n "$backup" ] || return 1
  assert_file_content_equals "$backup" "# Real Plan Content" || return 1
}

test_hook_9_empty_file() {
  # Empty file → handles gracefully (0 lines)
  local file="$FIXTURE_DIR/empty.txt"
  touch "$file"

  local output
  output=$(run_hook "Write" "$file")

  assert_backup_count "empty.txt" 1 || return 1
  # Should mention 0 lines in output
  assert_output_contains "$output" "0 lines" || return 1
}

test_hook_10_pid_timestamp_uniqueness() {
  # PID timestamp uniqueness → two rapid calls get different filenames
  local file="$FIXTURE_DIR/rapid-test.txt"
  echo "content" > "$file"

  run_hook "Write" "$file" >/dev/null
  local backup1
  backup1=$(find "$BACKUP_DIR" -name "rapid-test.txt__*.bak" | sort | tail -1)

  run_hook "Write" "$file" >/dev/null
  local backup2
  backup2=$(find "$BACKUP_DIR" -name "rapid-test.txt__*.bak" | sort | tail -1)

  # Filenames should be different (different timestamps/PIDs)
  if [ "$backup1" != "$backup2" ]; then
    return 0
  else
    echo "ASSERT FAILED: Timestamps not unique: $backup1 vs $backup2"
    return 1
  fi
}

test_hook_11_plan_detection_absolute_path() {
  # Plan detection: ~/.claude/plans/test.md → IS_PLAN=true
  local file="$TEST_DIR/.claude/plans/absolute-test.md"
  mkdir -p "$(dirname "$file")"
  echo "# Plan" > "$file"

  local output
  output=$(run_hook "Edit" "$file")

  # Should output PLAN GUARD (only plan files get Edit context output)
  assert_output_contains "$output" "PLAN GUARD" || return 1
}

test_hook_12_plan_detection_relative_path() {
  # Plan detection: docs/plans/test.md → IS_PLAN=true
  # Create file in fixture with relative path structure
  local fixture_subdir="$FIXTURE_DIR/project"
  mkdir -p "$fixture_subdir/docs/plans"
  local file="$fixture_subdir/docs/plans/relative-test.md"
  echo "# Plan" > "$file"

  # Change to fixture_subdir so relative path is detectable
  (
    cd "$fixture_subdir"
    HOME="$TEST_DIR" \
    create_hook_input "Edit" "docs/plans/relative-test.md" \
      | ~/.claude/hooks/backup-before-write.sh 2>&1 | grep -q "PLAN GUARD"
  ) || return 1
}

test_hook_13_plan_detection_master_plan() {
  # Plan detection: AGENT_TEAM_IMPLEMENTATION_PLAN → IS_PLAN=true
  local file="$FIXTURE_DIR/AGENT_TEAM_IMPLEMENTATION_PLAN.md"
  echo "# Plan" > "$file"

  local output
  output=$(run_hook "Edit" "$file")

  assert_output_contains "$output" "PLAN GUARD" || return 1
  assert_output_contains "$output" "PLAN UPDATE RULES" || return 1
}

test_hook_14_plan_detection_non_plan() {
  # Plan detection: src/components/Foo.tsx → IS_PLAN=false
  local file="$FIXTURE_DIR/Foo.tsx"
  echo "export function Foo() {}" > "$file"

  local output
  output=$(run_hook "Edit" "$file")

  # Non-plan Edit should be silent (no PLAN GUARD)
  if ! echo "$output" | grep -q "PLAN GUARD"; then
    return 0
  else
    echo "ASSERT FAILED: Non-plan file should not trigger PLAN GUARD"
    return 1
  fi
}

test_hook_15_backup_failure_graceful() {
  # Backup failure simulation → warn but don't block (test with read-only dir)
  local file="$FIXTURE_DIR/readonly-test.txt"
  echo "content" > "$file"

  # Temporarily make backup dir read-only
  chmod 444 "$BACKUP_DIR" 2>/dev/null || true

  local output
  output=$(run_hook "Write" "$file") || true

  # Restore permissions for cleanup
  chmod 755 "$BACKUP_DIR" 2>/dev/null || true

  # Should warn about backup failure but not block
  # (the hook still returns 0 and outputs context)
  assert_output_contains "$output" "WARNING" || \
  assert_output_contains "$output" "Backup of" || return 1
}

# ============================================================================
# RESTORE TESTS (16-24)
# ============================================================================

test_restore_16_restore_latest_backup() {
  # Restore latest backup → file content matches backup
  local file="$FIXTURE_DIR/restore-test.txt"
  echo "original" > "$file"

  # Create backup
  run_hook "Write" "$file" >/dev/null

  # Modify file
  echo "modified" > "$file"

  # Restore
  run_restore "$file" >/dev/null

  assert_file_content_equals "$file" "original" || return 1
}

test_restore_17_list_backups() {
  # --list → shows all backups with correct metadata
  local file="$FIXTURE_DIR/list-test.txt"
  echo "backup1" > "$file"
  run_hook "Write" "$file" >/dev/null

  echo "backup2" > "$file"
  run_hook "Write" "$file" >/dev/null

  local output
  output=$(run_restore "$file" --list)

  # Should list multiple backups
  assert_output_contains "$output" "#1" || return 1
  assert_output_contains "$output" "#2" || return 1
  assert_output_contains "$output" "lines" || return 1
}

test_restore_18_diff_backup() {
  # --diff → shows unified diff
  local file="$FIXTURE_DIR/diff-test.txt"
  echo "old line" > "$file"

  run_hook "Write" "$file" >/dev/null

  echo "new line" > "$file"

  local output
  output=$(run_restore "$file" --diff)

  # Should contain unified diff markers
  assert_output_contains "$output" "---" || return 1
  assert_output_contains "$output" "+++" || return 1
}

test_restore_19_pick_nth_backup() {
  # --pick N → restores Nth backup
  local file="$FIXTURE_DIR/pick-test.txt"
  echo "backup1" > "$file"
  run_hook "Write" "$file" >/dev/null

  echo "backup2" > "$file"
  run_hook "Write" "$file" >/dev/null

  echo "backup3" > "$file"
  run_hook "Write" "$file" >/dev/null

  # Restore backup #2 (middle one = "backup2")
  run_restore "$file" --pick 2 >/dev/null

  assert_file_content_equals "$file" "backup2" || return 1
}

test_restore_20_recent_backups() {
  # --recent → shows recent backups across all files
  local file1="$FIXTURE_DIR/recent1.txt"
  local file2="$FIXTURE_DIR/recent2.txt"

  echo "content1" > "$file1"
  run_hook "Write" "$file1" >/dev/null

  echo "content2" > "$file2"
  run_hook "Write" "$file2" >/dev/null

  local output
  output=$(run_restore --recent 5)

  # Should list both files
  assert_output_contains "$output" "recent1.txt" || return 1
  assert_output_contains "$output" "recent2.txt" || return 1
  assert_output_contains "$output" "Most Recent Backups" || return 1
}

test_restore_21_no_backups_exist() {
  # No backups exist → graceful error message
  local file="$FIXTURE_DIR/never-backed.txt"
  echo "content" > "$file"
  # Don't create backup

  local output
  output=$(run_restore "$file" 2>&1) || true

  assert_output_contains "$output" "No backups found" || return 1
}

test_restore_22_basename_collision_sidecar() {
  # Basename collision → .path sidecar disambiguates
  local file1="$TEST_DIR/dir1/testfile.txt"
  local file2="$TEST_DIR/dir2/testfile.txt"

  mkdir -p "$(dirname "$file1")" "$(dirname "$file2")"

  echo "content1" > "$file1"
  run_hook "Write" "$file1" >/dev/null

  echo "content2" > "$file2"
  run_hook "Write" "$file2" >/dev/null

  # Both backups should have .path sidecars pointing to correct originals
  local backup1
  backup1=$(find "$BACKUP_DIR" -name "testfile.txt__*.bak" -print0 \
    | xargs -0 ls -t | head -1)

  local path_sidecar
  path_sidecar="${backup1%.bak}.path"

  assert_file_exists "$path_sidecar" || return 1

  # Verify sidecar contains one of the correct paths
  local sidecar_content
  sidecar_content=$(cat "$path_sidecar")
  if [ "$sidecar_content" = "$file1" ] || [ "$sidecar_content" = "$file2" ]; then
    return 0
  else
    echo "ASSERT FAILED: Sidecar contains unexpected path: $sidecar_content"
    return 1
  fi
}

test_restore_23_atomic_restore() {
  # Atomic restore → file not corrupted if interrupted (test with signal)
  # Note: This test simulates atomicity by verifying temp file cleanup
  local file="$FIXTURE_DIR/atomic-test.txt"
  echo "backup_content" > "$file"

  run_hook "Write" "$file" >/dev/null

  echo "modified" > "$file"

  # Restore
  run_restore "$file" >/dev/null

  # Verify file has correct content (not corrupted)
  assert_file_content_equals "$file" "backup_content" || return 1

  # Verify no .restore temp files left behind
  local temp_files
  temp_files=$(find "$FIXTURE_DIR" -name "*.restore.*" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$temp_files" -eq 0 ]; then
    return 0
  else
    echo "ASSERT FAILED: Temp files not cleaned up: $temp_files"
    return 1
  fi
}

test_restore_24_permission_preservation() {
  # Permission preservation → restored file has same permissions
  local file="$FIXTURE_DIR/perms-test.txt"
  echo "content" > "$file"
  chmod 644 "$file"

  run_hook "Write" "$file" >/dev/null

  echo "modified" > "$file"
  chmod 755 "$file" # Different permissions

  run_restore "$file" >/dev/null

  # File should have original permissions (644) after restore
  local perms
  perms=$(stat -f '%OLp' "$file" 2>/dev/null || stat -c '%a' "$file" 2>/dev/null)

  # macOS vs Linux stat output differs; both should be close to 644
  if [ "$perms" = "644" ] || [ "$perms" = "-rw-r--r--" ]; then
    return 0
  else
    echo "ASSERT FAILED: Permissions not preserved: $perms"
    return 1
  fi
}

# ============================================================================
# INTEGRATION TESTS (25-26)
# ============================================================================

test_integration_25_full_cycle() {
  # Full cycle: create file → Write (backup created) → modify → restore → content matches original
  local file="$FIXTURE_DIR/full-cycle.txt"

  # Create original
  echo "first version" > "$file"

  # Trigger Write (creates backup)
  run_hook "Write" "$file" >/dev/null

  # Modify
  echo "second version" > "$file"

  # Restore
  run_restore "$file" >/dev/null

  # Verify
  assert_file_content_equals "$file" "first version" || return 1
}

test_integration_26_prune_old_backups() {
  # Prune: create 12 backups → verify only 10 remain after hook fires
  local file="$FIXTURE_DIR/prune-test.txt"
  echo "initial" > "$file"

  # Create 12 backups by writing 12 times
  for i in {1..12}; do
    echo "backup $i" > "$file"
    run_hook "Write" "$file" >/dev/null
    sleep 0.01 # Small delay for timestamp uniqueness
  done

  # Verify only 10 remain
  assert_backup_count "prune-test.txt" 10 || return 1
}

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

main() {
  echo "=== Backup-Before-Write Test Harness ==="
  echo "Test directory: $TEST_DIR"
  echo ""

  cleanup_env

  # Hook tests (1-15)
  echo "Hook Tests (backup-before-write.sh):"
  run_test "1. Write existing non-plan file" test_hook_1_write_existing_non_plan
  run_test "2. Write existing plan file" test_hook_2_write_existing_plan_file
  run_test "3. Edit existing plan file" test_hook_3_edit_existing_plan_file
  run_test "4. Edit existing non-plan file" test_hook_4_edit_existing_non_plan_file
  run_test "5. Write non-existent file" test_hook_5_write_non_existent_file
  run_test "6. Edit non-existent file" test_hook_6_edit_non_existent_file
  run_test "7. MultiEdit existing file" test_hook_7_multiedit_existing_file
  run_test "8. Symlink plan file" test_hook_8_symlink_plan_file
  run_test "9. Empty file" test_hook_9_empty_file
  run_test "10. PID timestamp uniqueness" test_hook_10_pid_timestamp_uniqueness
  run_test "11. Plan detection (absolute path)" test_hook_11_plan_detection_absolute_path
  run_test "12. Plan detection (relative path)" test_hook_12_plan_detection_relative_path
  run_test "13. Plan detection (master plan)" test_hook_13_plan_detection_master_plan
  run_test "14. Plan detection (non-plan)" test_hook_14_plan_detection_non_plan
  run_test "15. Backup failure graceful" test_hook_15_backup_failure_graceful

  echo ""
  echo "Restore Tests (restore-file.sh):"
  run_test "16. Restore latest backup" test_restore_16_restore_latest_backup
  run_test "17. List backups" test_restore_17_list_backups
  run_test "18. Diff backup" test_restore_18_diff_backup
  run_test "19. Pick Nth backup" test_restore_19_pick_nth_backup
  run_test "20. Recent backups" test_restore_20_recent_backups
  run_test "21. No backups exist" test_restore_21_no_backups_exist
  run_test "22. Basename collision sidecar" test_restore_22_basename_collision_sidecar
  run_test "23. Atomic restore" test_restore_23_atomic_restore
  run_test "24. Permission preservation" test_restore_24_permission_preservation

  echo ""
  echo "Integration Tests:"
  run_test "25. Full cycle (create→write→modify→restore)" test_integration_25_full_cycle
  run_test "26. Prune old backups (keep last 10)" test_integration_26_prune_old_backups

  # Summary
  echo ""
  echo "========================================="
  local total=$((PASSED + FAILED))
  if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED${NC} ($PASSED/$total)"
    cleanup_env
    return 0
  else
    echo -e "${RED}✗ TESTS FAILED${NC}"
    echo "  Passed: $PASSED"
    echo "  Failed: $FAILED"
    echo "  Total:  $total"
    echo ""
    echo "Test directory preserved for debugging: $TEST_DIR"
    return 1
  fi
}

# Run only if not sourced
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
  main "$@"
  exit $?
fi
