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
#   2. the two limit-recover fire paths CREATE A BARE PANE and put the command in afterwards;
#   3. the repair tool for panes created BEFORE the fix exists, is executable, and fails OPEN when
#      the iterm2 python module is absent (it is a convenience, never a gate).
#
# Invariant 1 is a source-shape guard on purpose: the failure is invisible at fire time (the pane
# launches correctly — only a LATER ⌘D misbehaves), so no runtime assertion in the fire path can
# catch it. The banned string is the whole signal.
#
# ── INVARIANT 2 RE-ANCHORED 2026-08-10 (these two tests were STALE, not red) ───────────────────────
# Invariant 2 used to be spelled as a grep for a literal `tell newPane to write text "exec …"` —
# i.e. it pinned the create-then-`write text` SPELLING, not the property. 5fff9df6 then split create
# from type at all three spawn sites, for a defect of its own (backlog 270106134cc8): `write text`
# appends the newline itself, so the combined form EXECUTED the line before anything could confirm
# it arrived intact, and a line mangled by a freshly-starting zsh could park the pane forever on an
# unanswerable `zsh: correct … [nyae]?` — unattended, from a LaunchAgent. The command now goes in
# through osa_type_verified (scripts/lib/cc-type-verified.sh), which types WITHOUT submitting,
# echo-verifies against a per-attempt nonce, and only then sends the bare CR.
#
# So the subject moved toward safety and the assertion stayed behind. Left alone it stops being
# stale and starts GUARDING THE BUG — it would redden any future land and read as a demand to go
# back to the blind single-shot send. Both sides carry an incident; the side with the LATER one, and
# the one whose failure is silent and unattended, wins. The assertions below therefore pin the
# PROPERTY invariant 2 always meant: the surface is created BARE (no `command "…"` rider — that is
# what ⌘D would copy), and the command arrives as a separate, verified step.

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

@test "lr-handoff split creates a BARE pane, then types the launcher as a verified second step" {
  run grep -q 'set newPane to (split vertically with default profile)' "$REPO/scripts/limit-recover/lr-handoff.sh"
  [ "$status" -eq 0 ]
  # The split returns the new pane's id so the command can be addressed at it afterwards; without
  # this the type step has nowhere to go and the site would have to fold back into the banned form.
  run grep -q 'return id of newPane' "$REPO/scripts/limit-recover/lr-handoff.sh"
  [ "$status" -eq 0 ]
  run grep -qF 'osa_type_verified "$NEWPANE" "exec /bin/bash $LAUNCHER"' "$REPO/scripts/limit-recover/lr-handoff.sh"
  [ "$status" -eq 0 ]
}

@test "lr-handoff window fallback creates a BARE window, then types the launcher verified" {
  run grep -q 'set newWin to (create window with default profile)' "$REPO/scripts/limit-recover/lr-handoff.sh"
  [ "$status" -eq 0 ]
  run grep -qF 'osa_type_verified "$WINPANE" "exec /bin/bash $LAUNCHER"' "$REPO/scripts/limit-recover/lr-handoff.sh"
  [ "$status" -eq 0 ]
}

@test "lr-reset-poller spawn_gui creates a BARE window, then types the launcher verified" {
  run grep -qF "-e 'set newWin to (create window with default profile)'" "$REPO/scripts/limit-recover/lr-reset-poller.sh"
  [ "$status" -eq 0 ]
  run grep -qF "-e 'return id of (current session of newWin)'" "$REPO/scripts/limit-recover/lr-reset-poller.sh"
  [ "$status" -eq 0 ]
  run grep -qF 'osa_type_verified "$pane" "exec /bin/bash $1"' "$REPO/scripts/limit-recover/lr-reset-poller.sh"
  [ "$status" -eq 0 ]
  # The AppleScript must stay in ARGV (multi -e), not stdin: tests/lr-reset-poller.bats' stub reads
  # "$*", so a heredoc would silently blind its three GUI-spawn assertions. The call is bounded
  # through lrp_bounded (osa-bounds AC22) — the shape moved, the ARGV property did not.
  # The trailing backslash is a line continuation in the SUBJECT, so it is matched as data via -F.
  # Spelled with a variable rather than inline, and DOUBLE-quoted: single quotes cannot express a
  # lone backslash without shellcheck reading it as an attempted escape (SC1003), while "\\" is
  # unambiguously one character to both.
  bslash="\\"
  run grep -qF "lrp_bounded osascript 2>/dev/null $bslash" "$REPO/scripts/limit-recover/lr-reset-poller.sh"
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
