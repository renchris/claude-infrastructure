#!/usr/bin/env bats
# Phase 3 autonomy — handoff-fire.sh pre-trust: fired sessions skip the workspace-trust dialog
# (a gate separate from --permission-mode auto) so a --notify-back peer never stalls.
#
# The two helpers are self-contained, so we extract + source them to test the real code, plus
# assert the dir-resolution via --dry-run (no real fire).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  eval "$(sed -n '/^config_dir_for_launcher() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^pre_trust() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^write_role() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^refresh_roles_for() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^check_goal_length() {/,/^}/p' "$HF")"
}

# A minimal side-effect-free fire harness (HOME isolates config/projects/registry/roles; IT2_BIN
# stubs the it2 transport; the shim must EXIST so the REAL_IT2 sed|head probe doesn't abort under
# pipefail). Shared by the --as-role E2E and the /goal-guard tests below.
_fire_harness() {
  HOMEDIR="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOMEDIR/.claude/projects/p" "$HOMEDIR/.claude/cc-registry" "$HOMEDIR/.claude/bin" "$BATS_TEST_TMPDIR/bin"
  PANE="FAKEPANE-0000-0000-0000-000000000001"
  cat > "$BATS_TEST_TMPDIR/bin/it2" <<STUB
#!/bin/bash
LAST="$BATS_TEST_TMPDIR/it2-last-send"
case "\$1 \$2" in
  "session send"|"session run") printf '%s' "\${!#}" > "\$LAST" ;;
esac
case "\$*" in
  *"session split"*) echo "Created new pane: $PANE" ;;
  *"session read"*)  cat "\$LAST" 2>/dev/null ;;
  *) : ;;
esac
STUB
  chmod +x "$BATS_TEST_TMPDIR/bin/it2"
  cp "$BATS_TEST_TMPDIR/bin/it2" "$HOMEDIR/.claude/bin/it2"
}

@test "pre_trust: marks an untrusted dir trusted (hasTrustDialogAccepted:true)" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"; echo '{"projects":{}}' > "$cfg/.claude.json"
  run pre_trust /tmp/untrusted-abc "$cfg"
  [ "$status" -eq 0 ]
  run jq -r '.projects["/tmp/untrusted-abc"].hasTrustDialogAccepted' "$cfg/.claude.json"
  [ "$output" = "true" ]
}

@test "pre_trust: canonicalizes — trusts the RESOLVED path (/tmp → /private/tmp), not the raw one" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"; echo '{"projects":{}}' > "$cfg/.claude.json"
  real="$(mktemp -d /tmp/pt-canon-XXXXXX)"           # /tmp/… which macOS resolves to /private/tmp/…
  resolved="$(cd "$real" && pwd -P)"
  pre_trust "$real" "$cfg"
  run jq -r --arg d "$resolved" '.projects[$d].hasTrustDialogAccepted' "$cfg/.claude.json"
  [ "$output" = "true" ]                              # stored under the resolved path Claude checks
  if [ "$real" != "$resolved" ]; then                # …and NOT under the raw /tmp path
    run jq -r --arg d "$real" '.projects[$d] // "absent"' "$cfg/.claude.json"
    [ "$output" = "absent" ]
  fi
  rm -rf "$real"
}

@test "pre_trust: creates the projects entry when the dir is absent" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"; echo '{}' > "$cfg/.claude.json"
  pre_trust /tmp/brand-new "$cfg"
  run jq -r '.projects["/tmp/brand-new"].hasTrustDialogAccepted' "$cfg/.claude.json"
  [ "$output" = "true" ]
}

@test "pre_trust: preserves existing project keys (surgical merge, not overwrite)" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"
  echo '{"projects":{"/x":{"allowedTools":["Bash"],"hasTrustDialogAccepted":false}}}' > "$cfg/.claude.json"
  pre_trust /x "$cfg"
  run jq -c '.projects["/x"]' "$cfg/.claude.json"
  [[ "$output" == *'"allowedTools":["Bash"]'* ]]
  [[ "$output" == *'"hasTrustDialogAccepted":true'* ]]
}

@test "pre_trust: idempotent — an already-trusted dir leaves the file byte-identical" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"
  echo '{"projects":{"/x":{"hasTrustDialogAccepted":true}}}' > "$cfg/.claude.json"
  before="$(cat "$cfg/.claude.json")"
  pre_trust /x "$cfg"
  [ "$(cat "$cfg/.claude.json")" = "$before" ]
}

@test "pre_trust: keeps --permission-mode auto tool-safety (sets ONLY trust/onboarding keys)" {
  cfg="$BATS_TEST_TMPDIR/cfg"; mkdir -p "$cfg"; echo '{"projects":{}}' > "$cfg/.claude.json"
  pre_trust /x "$cfg"
  run jq -r '.projects["/x"] | keys | join(",")' "$cfg/.claude.json"
  [ "$output" = "hasCompletedProjectOnboarding,hasTrustDialogAccepted" ]
}

@test "pre_trust: missing .claude.json is a clean no-op" {
  run pre_trust /x "$BATS_TEST_TMPDIR/does-not-exist"
  [ "$status" -eq 0 ]
}

@test "pre_trust: empty dir arg is a no-op" {
  run pre_trust "" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
}

@test "config_dir_for_launcher maps launcher → account config dir" {
  [ "$(config_dir_for_launcher claude-next)"  = "$HOME/.claude" ]
  [ "$(config_dir_for_launcher claude-next2)" = "$HOME/.claude-secondary" ]
  [ "$(config_dir_for_launcher claude-next3)" = "$HOME/.claude-tertiary" ]
  [ "$(config_dir_for_launcher claude-next4)" = "$HOME/.claude-quaternary" ]
  [ "$(config_dir_for_launcher claude-fable2)" = "$HOME/.claude-secondary" ]
}

@test "dry-run: --worktree fire pre-trusts the worktree path in the account config" {
  printf 'x\n' > "$BATS_TEST_TMPDIR/p.txt"
  run bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/p.txt" --worktree wslug --account next2 --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qE 'pre-trust: .*/\.worktrees/wslug → \.claude-secondary'
}

@test "dry-run: --cwd fire pre-trusts the cwd in the account config" {
  printf 'x\n' > "$BATS_TEST_TMPDIR/p.txt"
  run bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/p.txt" --cwd /tmp/somedir --in-place --account next4 --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'pre-trust: /tmp/somedir → .claude-quaternary'
}

# ---- P0-15 role indirection (SO-1 ping-to-dead-pane break) -----------------------------------

@test "write_role: writes the pane uuid to cc-roles/<role>" {
  dir="$BATS_TEST_TMPDIR/roles"
  write_role "$dir" operator PANE-NEW-0001
  [ "$(cat "$dir/operator")" = "PANE-NEW-0001" ]
}

@test "write_role: empty pane arg is a no-op (no file created)" {
  dir="$BATS_TEST_TMPDIR/roles2"
  write_role "$dir" operator ""
  [ ! -e "$dir/operator" ]
}

@test "refresh_roles_for: repoints a role naming the OLD pane to the successor (self-close)" {
  dir="$BATS_TEST_TMPDIR/roles3"; mkdir -p "$dir"
  printf 'OLD-PANE\n' > "$dir/operator"
  refresh_roles_for "$dir" OLD-PANE SUCCESSOR-PANE
  [ "$(cat "$dir/operator")" = "SUCCESSOR-PANE" ]
}

@test "refresh_roles_for: post-recycle role file still points at the (same-pane) successor" {
  dir="$BATS_TEST_TMPDIR/roles4"; mkdir -p "$dir"
  printf 'SID-PANE\n' > "$dir/operator"      # recycle keeps the pane: old == new == SID
  refresh_roles_for "$dir" SID-PANE SID-PANE
  [ "$(cat "$dir/operator")" = "SID-PANE" ]
}

@test "refresh_roles_for: a role NOT naming the old pane is left untouched" {
  dir="$BATS_TEST_TMPDIR/roles5"; mkdir -p "$dir"
  printf 'SOMEONE-ELSE\n' > "$dir/monitor"
  refresh_roles_for "$dir" OLD-PANE SUCCESSOR-PANE
  [ "$(cat "$dir/monitor")" = "SOMEONE-ELSE" ]
}

@test "E2E: --as-role writes cc-roles/<role> = the FIRED pane on an engaged fire" {
  _fire_harness
  # Engagement needs a real ASSISTANT turn, not just a transcript carrying the marker (transcript
  # BIRTH is what a rejected/never-submitted prompt also produces — item ff2d6609a33e).
  { printf '{"type":"user","message":{"role":"user","content":"brief ROLE-MARK ok"}}\n'
    printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}\n'
  } > "$HOMEDIR/.claude/projects/p/s.jsonl"
  printf 'BRIEF\n' > "$BATS_TEST_TMPDIR/brief.md"
  run env HOME="$HOMEDIR" IT2_BIN="$BATS_TEST_TMPDIR/bin/it2" TMPDIR="$BATS_TEST_TMPDIR" \
    FIRE_ENGAGE_TIMEOUT=5 FIRE_ENGAGE_INTERVAL=1 FIRE_REG_TIMEOUT=0 FIRE_ENGAGE_MARKER=ROLE-MARK \
    bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/brief.md" --launcher claude-test --split-right \
      --session-id FIRING-0000 --cwd "$BATS_TEST_TMPDIR" --no-self-retire --as-role operator
  [ "$status" -eq 0 ]
  [ "$(cat "$HOMEDIR/.claude/cc-roles/operator")" = "$PANE" ]
}

# ---- P0-16 /goal >4000-char guard (a19 D-11) ------------------------------------------------
# (GOAL_MAX_CHARS shrinks the 4000 cap so fixtures stay tiny.)

@test "check_goal_length: a /goal body over the cap fails loud (exit 1, names the size + pointer fix)" {
  printf '/goal %s\n' "$(head -c 30 </dev/zero | tr '\0' x)" > "$BATS_TEST_TMPDIR/g.md"
  GOAL_MAX_CHARS=20
  run check_goal_length "$BATS_TEST_TMPDIR/g.md"
  [ "$status" -eq 1 ]
  printf '%s\n' "$output" | grep -qE '/goal condition is [0-9]+ chars'
  printf '%s\n' "$output" | grep -q 'POINTER form'
}

@test "check_goal_length: /goal body exactly at the cap passes (0)" {
  printf '/goal %s\n' "$(head -c 20 </dev/zero | tr '\0' x)" > "$BATS_TEST_TMPDIR/g.md"
  GOAL_MAX_CHARS=20
  run check_goal_length "$BATS_TEST_TMPDIR/g.md"
  [ "$status" -eq 0 ]
}

@test "check_goal_length: no /goal line -> ok (0)" {
  printf 'a normal brief\nmore lines\n' > "$BATS_TEST_TMPDIR/g.md"
  GOAL_MAX_CHARS=20
  run check_goal_length "$BATS_TEST_TMPDIR/g.md"
  [ "$status" -eq 0 ]
}

@test "check_goal_length: a long NON-/goal line does not trip the guard" {
  printf 'DELIVERABLE: %s\n' "$(head -c 50 </dev/zero | tr '\0' x)" > "$BATS_TEST_TMPDIR/g.md"
  GOAL_MAX_CHARS=20
  run check_goal_length "$BATS_TEST_TMPDIR/g.md"
  [ "$status" -eq 0 ]
}

@test "E2E: over-cap /goal is rejected PRE-fire (--dry-run), non-zero, no command printed" {
  printf '/goal %s\n' "$(head -c 30 </dev/zero | tr '\0' x)" > "$BATS_TEST_TMPDIR/g.md"
  run env GOAL_MAX_CHARS=20 bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/g.md" \
    --launcher claude-test --cwd "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -q 'HARD-CAPS /goal'
  ! printf '%s\n' "$output" | grep -q 'command:'
}

@test "E2E: an under-cap /goal passes the guard (--dry-run exit 0)" {
  printf '/goal do the thing\n\nbrief body\n' > "$BATS_TEST_TMPDIR/g.md"
  run env GOAL_MAX_CHARS=4000 bash "$HF" --prompt-file "$BATS_TEST_TMPDIR/g.md" \
    --launcher claude-test --cwd "$BATS_TEST_TMPDIR" --dry-run
  [ "$status" -eq 0 ]
}
