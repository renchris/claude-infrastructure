#!/usr/bin/env bats
# bin/it2-kitty: no verb may degrade onto whatever pane the operator is currently using.
#
# Two defects found while investigating the 2026-08-07 pane theft
# (docs/plans/PANE_THEFT_2026-08-07.md §4.5, §4.6):
#
#   1. `send` and `run` fell through to a bare `kitty @ send-text -- "$text"` when no -s was given,
#      and kitty with no --match writes to the ACTIVE window. So the two verbs that TYPE — the ones
#      that can submit a composer or answer a [nyae] prompt — degraded on a lost id into a keystroke
#      injector aimed at the operator, while `close`, the merely destructive verb, had refused an
#      empty id all along. That asymmetry is backwards: an unaddressed close destroys a pane the
#      operator can reopen; an unaddressed send destroys text that exists nowhere on disk.
#
#   2. `split` pinned the tab (--match window_id:) and the neighbour (--next-to id:) but not the
#      SOURCE. `--cwd=current` is defined by kitty as "the working directory of the --source-window",
#      and unspecified means "the currently active window is used" — so a correctly-placed pane
#      inherited the operator's cwd. Measured on the incident: fired peers 246 and 248, whose
#      sessions run in two different worktrees, BOTH report cwd=…/lakehouse-lecture.
#
# Behavioural: the shipped bin/it2-kitty is executed with a stub `kitty` on PATH that records its
# argv, so these assertions observe what the real script would have asked the real kitty to do.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude"
  REPO="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SHIM="$REPO/bin/it2-kitty"
  [ -x "$SHIM" ] || skip "bin/it2-kitty not found or not executable at $SHIM"

  # Resolve the REAL kitty BEFORE the stub shadows it, so the documentary control below can still
  # interrogate kitty's own help. Captured, never hardcoded — a fixed /opt/homebrew path would be an
  # environment-specific one-off, and the control would rot the moment the box changed.
  REAL_KITTY="$(command -v kitty 2>/dev/null || true)"; export REAL_KITTY

  # Stub kitty: records argv, answers `ls` with a minimal live window so identity probes resolve.
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export KITTY_ARGV="$BATS_TEST_TMPDIR/kitty-argv.log"
  cat > "$BIN/kitty" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$KITTY_ARGV"
for a in "$@"; do
  if [ "$a" = "ls" ]; then
    printf '[{"id":1,"tabs":[{"id":1,"windows":[{"id":300,"is_focused":true,"pid":1,"cwd":"/tmp","foreground_processes":[]}]}]}]\n'
    exit 0
  fi
  if [ "$a" = "launch" ]; then echo 301; exit 0; fi
done
exit 0
SH
  chmod +x "$BIN/kitty"
  export CC_TERM_KITTY="$BIN/kitty"
  export PATH="$BIN:$PATH"
  export KITTY_WINDOW_ID=300
  export CC_KITTY_ARGV_SPAWN=0
  # THE PANE-IDENTITY ENV, PINNED — never inherited. KITTY_WINDOW_ID was commented here as making
  # "the shim believe it is inside kitty", and that was false: bin/it2-kitty refuses at its terminal
  # gate long before it reaches any verb unless BOTH hold — bin/cc-in-kitty agrees this pane is
  # kitty's, and a control socket is named. KITTY_WINDOW_ID alone satisfies NEITHER. cc-in-kitty
  # walks the process tree up to KITTY_PID and answers 2 UNVERIFIABLE without it, so the shim exits
  # 3 with "refusing to drive kitty from a pane that is not kitty's" and 7 of these 8 tests fail on
  # their `status` line having never run the subject at all — including the two the suite is named
  # for, which then "pass their point" for the wrong reason: no send-text is recorded because the
  # shim died at the gate, not because the guard refused.
  #
  # Inside a kitty session KITTY_PID/KITTY_LISTEN_ON arrive ambiently, so this suite passed in every
  # hand-run while being RED under launchd — which is precisely where postland-verify runs it
  # (com.claude.postland-verify sets PATH and nothing else). Measured: 3 postland REDs
  # (c53ea13efa44, 4b3b6b010e6c, 04470b5d4250), zero flakes.jsonl rows, and green on this same tree
  # the moment an ambient KITTY_PID leaked in. Same defect and same remedy as the sibling suite's
  # item 04e8028b980d (4857bb9b) — a green no developer could reproduce as red, and a red no rerun
  # could clear.
  #
  # CC_TERM=kitty is cc-in-kitty's OWN documented override, honoured verbatim ahead of every check,
  # so the precondition is DECLARED here rather than walked — no ps, no ancestry, no ambient state.
  # CC_TERM_KITTY_TO would satisfy both gates with one variable and is deliberately NOT used: it
  # adds `--to <socket>` to every kitty argv, and the argv these tests assert on (`--match id:300`,
  # `--source-window id:300`) is the one production actually issues.
  export CC_TERM=kitty
  export KITTY_LISTEN_ON="unix:$BATS_TEST_TMPDIR/kitty-sock"
  unset CC_TERM_KITTY_TO
  # …and the variables the subject puts on every pane it launches, inherited by every descendant of a
  # fired pane — bats included, when an agent runs this from the pane that fired it (0588d255).
  # In setup, not per-test: a per-test unset leaves every OTHER test inheriting.
  unset CC_PANE_CMD CC_PANE_CMD_DIR CC_PANE_CMD_INTERACTIVE
}

kitty_argv() { cat "$KITTY_ARGV" 2>/dev/null; }

# ── unaddressed send / run are REFUSED ────────────────────────────────────────────────

@test "session send with no -s REFUSES instead of typing into the active window" {
  run "$SHIM" session send "hello"
  [ "$status" -eq 65 ]
  echo "$output" | grep -q 'requires -s'
  # the decisive assertion: kitty was never asked to send anything
  run bash -c "grep -c 'send-text' '$KITTY_ARGV' 2>/dev/null || echo 0"
  [ "$output" = "0" ]
}

@test "session run with no -s REFUSES instead of executing in the active window" {
  run "$SHIM" session run "rm -rf /tmp/whatever"
  [ "$status" -eq 65 ]
  echo "$output" | grep -q 'requires -s'
  run bash -c "grep -c 'send-text' '$KITTY_ARGV' 2>/dev/null || echo 0"
  [ "$output" = "0" ]
}

@test "the refusal explains the hazard, not just the syntax" {
  # An operator or an agent reading this must learn WHY an unaddressed send is dangerous, or the
  # next caller will simply drop the flag again.
  run "$SHIM" session send "hello"
  echo "$output" | grep -qi 'active window'
}

@test "an ADDRESSED send still works — the guard must not retire the common case" {
  run "$SHIM" session send -s 300 "hello"
  [ "$status" -eq 0 ]
  kitty_argv | grep -q 'send-text --match id:300'
}

@test "close already refused an empty id, and still does — parity, not regression" {
  run "$SHIM" session close -f -s ""
  [ "$status" -eq 65 ]
  run bash -c "grep -c 'close-window' '$KITTY_ARGV' 2>/dev/null || echo 0"
  [ "$output" = "0" ]
}

@test "an iTerm2 UUID is refused by every verb that takes an id" {
  local uuid=D40A5752-F313-4F2C-B5BF-2FADE3BADB2C
  run "$SHIM" session close -f -s "$uuid"; [ "$status" -eq 65 ]
  run "$SHIM" session send  -s "$uuid" hi;  [ "$status" -eq 65 ]
  run "$SHIM" session run   -s "$uuid" hi;  [ "$status" -eq 65 ]
  run bash -c "grep -cE 'close-window|send-text' '$KITTY_ARGV' 2>/dev/null || echo 0"
  [ "$output" = "0" ]
}

# ── split pins the SOURCE, not just the placement ─────────────────────────────────────

@test "split pins --source-window so the new pane cannot inherit the operator's cwd" {
  run "$SHIM" session split -v -s 300
  [ "$status" -eq 0 ]
  kitty_argv | grep -q -- '--source-window id:300'
  # all three pins must be present together: placement, neighbour, AND source
  kitty_argv | grep -q -- '--match window_id:300'
  kitty_argv | grep -q -- '--next-to id:300'
  kitty_argv | grep -q -- '--cwd=current'
}

@test "CONTROL: --cwd=current with no --source-window is what kitty resolves against the ACTIVE window" {
  # The control is documentary rather than executable — kitty's own help is the oracle, and quoting
  # it here is what stops the assertion above from being a cargo-culted flag nobody can justify.
  [ -n "$REAL_KITTY" ] || skip "no real kitty on this box — the claim is unfalsifiable here, not proven"
  run bash -c "'$REAL_KITTY' @ launch --help 2>/dev/null | grep -A4 -- '--source-window'"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  echo "$output" | grep -qi 'currently active window is used'
}
