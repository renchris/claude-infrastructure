#!/usr/bin/env bats
# safe-disk-cleanup-kit.bats — templates/safe-disk-cleanup/install-wsl.sh in CLEANUP_KIT_TEST mode
# (system steps and the Claude launch skipped). Hermetic: HOME is a fixture under $BATS_TEST_TMPDIR.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  KIT="$REPO/templates/safe-disk-cleanup/install-wsl.sh"
  export HOME="$BATS_TEST_TMPDIR/home" USER=tester CLEANUP_KIT_TEST=1
  mkdir -p "$HOME/.claude"
  printf '%s' '{"model":"opus","permissions":{"allow":["Bash(ls *)"],"deny":["Bash(curl *)"]},"hooks":{"PreToolUse":[{"matcher":"Edit","hooks":[{"type":"command","command":"echo existing"}]}]}}' \
    > "$HOME/.claude/settings.json"
}

guard() { # <command> → the hook's exit status
  python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","tool_input":{"command":sys.argv[1],"description":"Start sizing"}}))' "$1" \
    | bash "$HOME/.claude/hooks/no-destructive-bash.sh" 2>/dev/null
}

@test "install merges into existing settings, keeps them, and a re-run adds nothing twice" {
  run bash "$KIT"; [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash "$KIT"; [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"READY (test mode"* ]] || false
  run python3 - "$HOME/.claude/settings.json" <<'PY'
import json, sys
s = json.load(open(sys.argv[1])); d = s["permissions"]["deny"]; sb = s["sandbox"]
assert s["model"] == "opus" and s["permissions"]["allow"] == ["Bash(ls *)"] and "Bash(curl *)" in d
assert len(d) == len(set(d)) and len(s["hooks"]["PreToolUse"]) == 2
assert sb["enabled"] is True and sb["allowUnsandboxedCommands"] is False and sb["failIfUnavailable"] is True
assert "Edit(//mnt/**)" in d and s["permissions"]["disableBypassPermissionsMode"] == "disable"
PY
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -f "$HOME/.claude/settings.json.before-cleanup-kit" ]
  grep -q 'wsl.localhost\\Ubuntu\\home\\tester\\cleanup-workspace' "$HOME/cleanup-workspace/CLAUDE.md"
  run grep -q '__WINUSER__\|__LINUXUSER__' "$HOME/cleanup-workspace/CLAUDE.md"
  [ "$status" -eq 1 ]
}

@test "guard blocks every destructive spelling and Windows program, allows read-only scans" {
  run bash "$KIT"; [ "$status" -eq 0 ] || { echo "$output"; false; }
  for c in 'rm -rf /mnt/c/x' 'cd /mnt/c && rm b' 'find /mnt/c -name x -delete' 'find . -exec rm {} +' \
           'mv a b' 'python3 -c "import shutil; shutil.rmtree(1)"' 'echo hi > /mnt/c/x' 'ls | xargs rm' \
           'powershell.exe -c ls' '/mnt/c/Windows/System32/cmd.exe /c del x' 'cmd /c del x' 'wsl.exe --shutdown' \
           'cat x > ~/.claude/settings.json'; do
    run guard "$c"; [ "$status" -eq 2 ] || { echo "not blocked: $c"; false; }
  done
  for c in 'du -sh /mnt/c/Users/* 2>/dev/null | sort -h' 'find /mnt/c/Users -size +500M -type f 2>/dev/null' \
           'df -h /mnt/c' 'sha256sum /mnt/c/Users/me/a.iso' 'du -sh /mnt/c/Users/me/cmd-tools'; do
    run guard "$c"; [ "$status" -eq 0 ] || { echo "wrongly blocked: $c"; false; }
  done
}

@test "guard fails closed on a payload it cannot parse" {
  run bash "$KIT"; [ "$status" -eq 0 ] || { echo "$output"; false; }
  run bash -c 'printf "not json" | bash "$HOME/.claude/hooks/no-destructive-bash.sh"'
  [ "$status" -eq 2 ]
}
