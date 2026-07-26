#!/usr/bin/env bats
# Regression guard for the iTerm2 STICKY CUSTOM-COMMAND trap (incident 2026-07-25).
#
# The operator's complaint: pressing ⌘D for a plain shell kept launching Claude Code sessions
# instead. Root cause — AppleScript's
#     (create window|split vertically) with default profile command "X"
# does NOT run X once. iTerm2 records X as a SESSION-SCOPED PROFILE OVERRIDE
# (use_custom_command=Yes, command=X) on the created session. ⌘D is "Split with Current Profile",
# which copies the CURRENT session's profile — override included — so every split off that pane
# re-ran X, and the clones inherited it too (self-propagating for the life of the window).
#
# Measured live 2026-07-25 (discriminator pair, both windows closed after):
#     OLD form → use_custom_command=Yes command='/bin/bash /tmp/probe-launcher.sh'
#     NEW form → use_custom_command=No  command=''
# One `/limit-recover handoff` fire at 01:28 left 4 pinned panes; three ⌘D presses at 17:55/17:56/
# 17:57 each spawned a fresh `claude --resume 076a1186…` — three concurrent resumes of ONE transcript.
#
# The durable invariants locked down here:
#   1. NO repo script uses the banned `with default profile command "…"` form — the whole bug class;
#   2. the two limit-recover fire paths use the create-then-`write text` form instead;
#   3. the repair tool for panes created BEFORE the fix exists, is executable, and fails OPEN when
#      the iterm2 python module is absent (it is a convenience, never a gate).
#
# Invariant 1 is a source-shape guard on purpose: the failure is invisible at fire time (the pane
# launches correctly — only a LATER ⌘D misbehaves), so no runtime assertion in the fire path can
# catch it. The banned string is the whole signal.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLEAR="$REPO/scripts/iterm-clear-sticky-command.sh"
  # Hermeticity (scripts/test-hermeticity-lint.sh): never run against the live ~/. The repair
  # tool shells out to python3/iterm2, either of which can read real dotfiles; a fixtured $HOME
  # keeps that contained. Nothing here seeds state under it — the subject reads none.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

@test "no script creates an iTerm2 surface with the sticky 'default profile command' form" {
  # Scan executable surfaces only (docs/ legitimately quotes the banned form to explain the
  # incident), and only CODE lines — the fix's own comments name the banned form on purpose, so a
  # keyword-blacklist would be fragile. A shell/AppleScript comment starts with # or --.
  run bash -c "grep -rn 'with default profile command' \
      '$REPO/scripts' '$REPO/bin' '$REPO/hooks' '$REPO/commands' '$REPO/skills' 2>/dev/null \
      | grep -vE '^[^:]+:[0-9]+: *(#|--)'"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "lr-handoff split fires via create-then-write-text, not a profile command" {
  run grep -q 'set newPane to (split vertically with default profile)' "$REPO/scripts/limit-recover/lr-handoff.sh"
  [ "$status" -eq 0 ]
  run grep -q 'tell newPane to write text "exec /bin/bash \$LAUNCHER"' "$REPO/scripts/limit-recover/lr-handoff.sh"
  [ "$status" -eq 0 ]
}

@test "lr-handoff window fallback fires via create-then-write-text" {
  run grep -q 'set newWin to (create window with default profile)' "$REPO/scripts/limit-recover/lr-handoff.sh"
  [ "$status" -eq 0 ]
}

@test "lr-reset-poller spawn_gui fires via create-then-write-text" {
  run grep -q 'set newWin to (create window with default profile)' "$REPO/scripts/limit-recover/lr-reset-poller.sh"
  [ "$status" -eq 0 ]
  run grep -qF 'to write text \"exec /bin/bash $1\"' "$REPO/scripts/limit-recover/lr-reset-poller.sh"
  [ "$status" -eq 0 ]
  # The AppleScript must stay in ARGV (multi -e), not stdin: tests/lr-reset-poller.bats' stub reads
  # "$*", so a heredoc would silently blind its three GUI-spawn assertions.
  run grep -qF "osascript >/dev/null 2>&1 \\" "$REPO/scripts/limit-recover/lr-reset-poller.sh"
  [ "$status" -eq 0 ]
}

@test "repair tool exists and is executable" {
  [ -x "$CLEAR" ]
}

@test "repair tool fails OPEN (exit 0) when the iterm2 python module is unavailable" {
  # Shadow python3 with a stub whose `import iterm2` fails, exactly like a headless/CI machine.
  stub="$BATS_TEST_TMPDIR/bin"; mkdir -p "$stub"
  cat > "$stub/python3" <<'SH'
#!/usr/bin/env bash
# `python3 -c 'import iterm2'` → fail; anything else would be the real work (must not be reached).
exit 1
SH
  chmod +x "$stub/python3"
  run env PATH="$stub:$PATH" bash "$CLEAR" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"iterm2 python module unavailable"* ]]
}

@test "repair tool rejects an unknown argument rather than guessing" {
  run bash "$CLEAR" --wat
  [ "$status" -eq 2 ]
}
