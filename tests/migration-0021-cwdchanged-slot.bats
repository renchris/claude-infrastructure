#!/usr/bin/env bats
# migrations/0021 — REPLACE file-changed.sh with cwd-changed.sh in the CwdChanged slot
# (backlog e35329880deb, found by claude-infrastructure-330; handler owned by W3-E).
#
# WHAT CREDITS THIS DIFF, and why it is not the usual "the migration file exists" control.
# 0021 was already on origin/main when this suite was written, so a file-existence arm would be
# GREEN pre-fix and credit nothing (MEMORY.md per-site-mutation-attributes-coverage). What this
# diff adds is the PRECONDITION: the landed version guarded on `-x` alone, which passes on any
# executable file at that path — including `hooks/file-changed.sh`, the very handler being replaced.
#
# So the credit arm is "REFUSES a live copy that re-arms but writes NO RECEIPT", and it is proved
# able to fail by EXECUTING the real pre-fix artifact out of git rather than by describing it
# (MEMORY.md control-must-replay-the-real-artifact).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/migrations/0021-cwdchanged-slot-replace.sh"

  export HOME="$BATS_TEST_TMPDIR/home"
  export CC_CLAUDE_DIR="$HOME/.claude"
  mkdir -p "$HOME/.claude/hooks"

  # shellcheck disable=SC2088  # the UNEXPANDED tildes are the subject under test: CC expands them
  # at hook-run time, so expanding here would assert this machine's $HOME instead of the contract
  OLD_CMD='~/.claude/hooks/file-changed.sh'
  # shellcheck disable=SC2088  # a lint directive binds to the NEXT construct only (MEMORY.md
  # lint-directive-binds-to-the-next-construct), so the line above does not cover this one
  NEW_CMD='~/.claude/hooks/cwd-changed.sh'

  install_handler good
}

# install_handler <good|silent|dead> — plants the LIVE copy the migration probes.
#   good   — re-arms AND writes the receipt row (the real cwd-changed.sh contract)
#   silent — re-arms but writes NO row: this is `file-changed.sh`'s measured behaviour, the
#            handler 0021 exists to replace, and the one an `-x` guard cannot tell apart
#   dead   — executable, emits nothing: the pre-fix-handler shape 0017 was bitten by
install_handler() {
  local mode="$1" f="$HOME/.claude/hooks/cwd-changed.sh"
  case "$mode" in
    good)   cat > "$f" <<'EOF'
#!/bin/bash
IFS= read -r -d '' IN || true
WL="${CC_FILECHANGED_WATCHLIST:-$HOME/.claude/file-watch-paths}"
LD="${CC_CWDCHANGED_LOG_DIR:-$HOME/.claude/logs}"
paths=$(jq -R -s -c 'split("\n")|map(select(length>0))' < "$WL" 2>/dev/null || printf '[]')
printf '{"hookSpecificOutput":{"hookEventName":"CwdChanged","watchPaths":%s}}' "$paths"
mkdir -p "$LD"
printf '%s\t%s\t%s\n' "$(printf '%s' "$IN" | jq -r '.old_cwd // .cwd')" \
                      "$(printf '%s' "$IN" | jq -r '.new_cwd')" \
                      "$(printf '%s' "$paths" | jq -r 'length')" >> "$LD/cwd-changed.log"
exit 0
EOF
            ;;
    silent) cat > "$f" <<'EOF'
#!/bin/bash
IFS= read -r -d '' IN || true
WL="${CC_FILECHANGED_WATCHLIST:-$HOME/.claude/file-watch-paths}"
paths=$(jq -R -s -c 'split("\n")|map(select(length>0))' < "$WL" 2>/dev/null || printf '[]')
printf '{"hookSpecificOutput":{"hookEventName":"CwdChanged","watchPaths":%s}}' "$paths"
exit 0
EOF
            ;;
    dead)   printf '#!/bin/bash\nexit 0\n' > "$f" ;;
  esac
  chmod +x "$f"
}

# fleet_config <dir> — settings.json shaped like the measured live state on 2026-09-07: 0017 has
# run, so CwdChanged holds file-changed.sh and ONLY that; FileChanged carries the arm/dispatch pair.
fleet_config() {
  mkdir -p "$1"
  jq -n '{hooks:{
    Stop:[{hooks:[{type:"command",command:"~/.claude/hooks/session-continue.sh",timeout:5}]}],
    PreToolUse:[{hooks:[{type:"command",command:"~/.claude/hooks/validate-bash.sh",timeout:5}]}],
    FileChanged:[{matcher:"/Users/x/.claude/file-watch-paths",
                  hooks:[{type:"command",command:"~/.claude/hooks/file-changed.sh",timeout:5}]},
                 {matcher:"*",
                  hooks:[{type:"command",command:"~/.claude/hooks/file-changed.sh",timeout:5}]}],
    CwdChanged:[{hooks:[{type:"command",command:"~/.claude/hooks/file-changed.sh",timeout:5}]}]
  }}' > "$1/settings.json"
}

cwd_cmds() { jq -r '[.hooks.CwdChanged[]?.hooks[]?.command]|join(",")' "$1"; }

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# THE CREDIT ARM AND ITS CONTROL
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "CREDIT: REFUSES a live copy that re-arms but writes NO receipt" {
  # `file-changed.sh`'s exact behaviour. An `-x` guard, and even 0017's emit-only probe, clear it.
  install_handler silent
  fleet_config "$HOME/.claude"
  run bash "$SUT"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'NO receipt row'
  # and it must not have touched the slot on the way to refusing
  [ "$(cwd_cmds "$HOME/.claude/settings.json")" = "$OLD_CMD" ]
}

@test "PRE-FIX CONTROL: the dde8d2dec artifact ACCEPTS that same silent copy" {
  # Executes the REAL pre-fix migration, so the arm above is proved able to fail rather than
  # asserted to be. If this ever goes red, the credit arm has stopped crediting anything.
  #
  # 🚨 THE REF IS A LITERAL SHA, NOT `origin/main`, AND THAT IS THE WHOLE POINT.
  # The first version of this arm replayed `origin/main:migrations/0021-…`. That ref ADVANCES past
  # this fix the moment it lands, after which the "pre-fix" artifact IS the post-fix artifact and
  # the control compares the fix to itself — it would have gone vacuous rather than red, which is
  # the worse of the two failures because nothing ever gets fixed. Caught by
  # scripts/moving-ref-control-lint at the land gate (MEMORY.md control-population-must-be-stable).
  # dde8d2dec is the commit that ADDED the pre-fix 0021 and is an ancestor of trunk.
  pre="$BATS_TEST_TMPDIR/pre-fix-0021.sh"
  git -C "$REPO" show dde8d2dec:migrations/0021-cwdchanged-slot-replace.sh > "$pre"

  # Second half of the fix: a pin alone re-goes-vacuous if the sha is ever re-pointed, so assert a
  # MARKER the fix INTRODUCED is ABSENT from the replay. `probe_rows` is derived from the measured
  # diff of the two artifacts (pre=0, post=2), not from either file's prose.
  ! grep -q 'probe_rows' "$pre" || false

  install_handler silent
  fleet_config "$HOME/.claude"
  run bash "$pre"
  [ "$status" -eq 0 ]
  [ "$(cwd_cmds "$HOME/.claude/settings.json")" = "$NEW_CMD" ]
}

@test "REFUSES a live copy that does not re-arm at all (0017's trap)" {
  install_handler dead
  fleet_config "$HOME/.claude"
  run bash "$SUT"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'does not re-arm'
  [ "$(cwd_cmds "$HOME/.claude/settings.json")" = "$OLD_CMD" ]
}

@test "REFUSES when the subject is missing or not executable" {
  rm -f "$HOME/.claude/hooks/cwd-changed.sh"
  fleet_config "$HOME/.claude"
  run bash "$SUT"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'missing or not executable'
}

@test "the probe is side-effect free: no row in the operator's real log" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  [ ! -e "$HOME/.claude/logs/cwd-changed.log" ]
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# THE REPLACEMENT ITSELF — one mutant per site
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "REPLACES: cwd-changed.sh in, file-changed.sh OUT of the CwdChanged slot" {
  fleet_config "$HOME/.claude"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  [ "$(cwd_cmds "$HOME/.claude/settings.json")" = "$NEW_CMD" ]
}

@test "APPEND would also satisfy 'present' — so assert the OLD command is GONE" {
  # The whole call is REPLACE-not-APPEND; an any(== new) check passes under either.
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run jq -e '[.hooks.CwdChanged[]?.hooks[]?.command] | length' "$HOME/.claude/settings.json"
  [ "$output" = "1" ]
}

@test "FileChanged's own arm/dispatch pair is NOT touched" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run jq -r '[.hooks.FileChanged[]?.hooks[]?.command]|unique|join(",")' "$HOME/.claude/settings.json"
  [ "$output" = "$OLD_CMD" ]
  run jq -r '[.hooks.FileChanged[]?.matcher]|join(",")' "$HOME/.claude/settings.json"
  [ "$output" = "/Users/x/.claude/file-watch-paths,*" ]
}

@test "the load-bearing sibling arrays survive — one bad write disables ~97 registrations" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run jq -e '(.hooks.Stop|length) > 0 and (.hooks.PreToolUse|length) > 0' "$HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
  run jq -e . "$HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "writes EVERY fleet config dir, not just the primary" {
  for d in .claude .claude-next .claude-secondary .claude-tertiary .claude-quaternary; do
    fleet_config "$HOME/$d"
  done
  run bash "$SUT"
  [ "$status" -eq 0 ]
  for d in .claude .claude-next .claude-secondary .claude-tertiary .claude-quaternary; do
    [ "$(cwd_cmds "$HOME/$d/settings.json")" = "$NEW_CMD" ]
  done
}

@test "the stored command is the LITERAL tilde, not this machine's expanded \$HOME" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run jq -r '.hooks.CwdChanged[0].hooks[0].command' "$HOME/.claude/settings.json"
  # shellcheck disable=SC2088  # asserting the LITERAL tilde reached settings.json unexpanded
  [ "$output" = '~/.claude/hooks/cwd-changed.sh' ]
  ! printf '%s' "$output" | grep -q "$HOME"
}

@test "a backup is written before the file is replaced" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run bash -c 'ls "$HOME"/.claude/settings.json.bak-0021-* | wc -l | tr -d " "'
  [ "$output" = "1" ]
  # the backup must hold the PRE-edit state, or it cannot undo anything
  run bash -c 'jq -r "[.hooks.CwdChanged[]?.hooks[]?.command]|join(\",\")" "$HOME"/.claude/settings.json.bak-0021-*'
  [ "$output" = "$OLD_CMD" ]
}

@test "idempotent: a second run replaces nothing further and says so" {
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'already replaced'
  [ "$(cwd_cmds "$HOME/.claude/settings.json")" = "$NEW_CMD" ]
}

@test "a dir where 0017 never ran is SKIPPED, not invented into existence" {
  mkdir -p "$HOME/.claude"
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"x",timeout:5}]}]}}' \
    > "$HOME/.claude/settings.json"
  run bash "$SUT"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | grep -q 'no CwdChanged array; skipped'
  run jq -e 'has("hooks") and (.hooks|has("CwdChanged")|not)' "$HOME/.claude/settings.json"
  [ "$status" -eq 0 ]
}

@test "a CwdChanged slot holding a THIRD party is left alone for a human, loudly" {
  mkdir -p "$HOME/.claude"
  jq -n '{hooks:{Stop:[{hooks:[{type:"command",command:"x",timeout:5}]}],
                 CwdChanged:[{hooks:[{type:"command",command:"~/.claude/hooks/someone-else.sh",timeout:5}]}]}}' \
    > "$HOME/.claude/settings.json"
  run bash "$SUT"
  [ "$status" -ne 0 ]
  printf '%s' "$output" | grep -q 'left ALONE for a human'
  # shellcheck disable=SC2088  # the UNEXPANDED tilde is the assertion: the third party's command
  # must survive byte-for-byte, and expanding it would assert this machine's $HOME instead
  [ "$(cwd_cmds "$HOME/.claude/settings.json")" = '~/.claude/hooks/someone-else.sh' ]
}

# ─────────────────────────────────────────────────────────────────────────────────────────────────
# THE DECLARED CONTRACT
# ─────────────────────────────────────────────────────────────────────────────────────────────────

@test "declares c10 and the four required migration- headers" {
  grep -q '^# migration-class: c10' "$SUT"
  for h in step run subject verify; do
    grep -q "^# migration-$h:" "$SUT"
  done
}

@test "the declared migration-verify passes after the run — and is NOT a tautology" {
  verify="$(sed -n 's/^# *migration-verify: *//p' "$SUT" | head -1)"
  case "$verify" in true|:|'exit 0'|'/usr/bin/true') return 1 ;; esac
  fleet_config "$HOME/.claude"
  bash "$SUT"
  run bash -c "$verify"
  [ "$status" -eq 0 ]
}

@test "the declared migration-verify FAILS before the run — it can observe the defect" {
  # A verify that cleared on the pre-migration state would report success forever.
  verify="$(sed -n 's/^# *migration-verify: *//p' "$SUT" | head -1)"
  fleet_config "$HOME/.claude"
  run bash -c "$verify"
  [ "$status" -ne 0 ]
}
