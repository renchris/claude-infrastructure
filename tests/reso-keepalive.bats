#!/usr/bin/env bats
# bin/reso-keepalive — backlog 6ab41e312a13, the other half of stranded commit 410f920c9.
#
# WHAT WAS STRANDED. 410f920c9 tracked BOTH resume actuators; only `bin/reso-resume-one` reached
# origin/main. `bin/reso-keepalive` did not, so it kept living untracked at
# ~/.reso/bin/reso-keepalive while scripts/boot-resume.sh:85-86 resolved and ran it — outside the
# ship gate, outside shellcheck, outside every suite. That is the whole class this file closes: an
# actuator nothing can lint is an actuator nothing can detect rot in, and the on-disk copy had
# rotted exactly as predicted (it is still the pre-410f920c zsh version, with the frozen literal).
#
# THE TWO PROPERTIES ASSERTED HERE are the two the recovered file's own header claims, because a
# claim in a comment is not a mechanism — nothing executes a comment (memory:
# contract-prose-can-understate-the-mechanism, inverted: here the prose OVERstates until pinned).
#
#   1. MARKERS is env-overridable and an EMPTY list EXITS. It used to be a frozen literal — the 12
#      worktrees of the 2026-07-04 recovery, baked in where no caller could reach them, and
#      boot-resume.sh passes only the interval. Sampled 2026-08-09, some of those worktrees no
#      longer existed: a nudger aimed at nothing, looping forever, silently.
#   2. iTerm2 is addressed by BUNDLE ID behind an is-running guard, never by name. The name form
#      resolves via CFBundleName, loses terminology when the app is not already running (-2740 /
#      -2741), and can LAUNCH a terminal on a headless box. This is the ratchet
#      tests/iterm2-appname-lint.bats exists to hold, and it could not see this file while it was
#      untracked.
#
# The nudge loop itself is deliberately NOT executed: it is an infinite `while :` that sends
# keystrokes into live panes. A suite that ran it would type into the operator's real sessions.
# What is testable without actuating is the guard that decides whether the loop is entered at all,
# and the addressing form — so that is exactly what is tested.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  KA="$REPO/bin/reso-keepalive"
  export CC_KEEPALIVE_LOG="$BATS_TEST_TMPDIR/keepalive.log"
  # Own the actuator seam: with a stub it2 on the path the script resolves, no case can reach a
  # real pane even if the loop were entered.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$CC_KEEPALIVE_LOG.it2"\n' > "$BATS_TEST_TMPDIR/bin/it2"
  chmod +x "$BATS_TEST_TMPDIR/bin/it2"
  export CC_IT2_BIN="$BATS_TEST_TMPDIR/bin/it2"
}

@test "the actuator is TRACKED — the whole point of the row" {
  [ -f "$KA" ] || { echo "bin/reso-keepalive is not in the tree"; false; }
  [ -x "$KA" ] || { echo "bin/reso-keepalive is not executable"; false; }
}

@test "an EMPTY marker list exits 0 and SAYS so — it never loops blind" {
  # The failure this replaces is silent: a frozen list whose worktrees no longer exist gives a
  # nudger with nothing to aim at, looping forever with no output. Exiting loudly is the fix.
  run env CC_KEEPALIVE_MARKERS="" "$KA" 1 fake-session-id
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no target markers" || { echo "empty markers did not announce: $output"; false; }
}

@test "CONTROL: a whitespace-only marker list is also EMPTY, not a marker named ' '" {
  # `[ -z "${MARKERS// /}" ]` is the guard; a plain `[ -z "$MARKERS" ]` would let a space through
  # and re-enter the loop with one bogus marker. This is the case that tells them apart.
  run env CC_KEEPALIVE_MARKERS="   " "$KA" 1 fake-session-id
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "no target markers" || { echo "whitespace-only list was treated as a marker: $output"; false; }
}

@test "MARKERS is env-overridable — the literal is a DEFAULT, not a freeze" {
  # Proved without entering the loop: the default list must still be present in the file as a
  # fallback, AND the parameter expansion must be the overridable form. A file that hardcoded the
  # list would fail the second assertion while passing the first.
  grep -q 'CC_KEEPALIVE_MARKERS:-' "$KA" || { echo "MARKERS is not env-overridable"; false; }
  grep -q 'wt-cc-030951-65335' "$KA" || { echo "the original default was dropped — existing callers change behaviour"; false; }
}

@test "iTerm2 is addressed by BUNDLE ID, never by name" {
  grep -q 'application id "com.googlecode.iterm2"' "$KA" || { echo "not addressed by bundle id"; false; }
  run grep -nE 'application "iTerm' "$KA"
  [ "$status" -ne 0 ] || { echo "addresses iTerm2 by NAME — loses terminology and can launch it: $output"; false; }
}

@test "the is-running guard short-circuits BEFORE any tell block" {
  # Order is the property: a guard placed after `tell` has already resolved (and possibly launched)
  # the app. Assert the guard line precedes the first tell.
  local g t
  g="$(grep -n 'is running) then return' "$KA" | head -1 | cut -d: -f1)"
  t="$(grep -n '^tell application' "$KA" | head -1 | cut -d: -f1)"
  [ -n "$g" ] || { echo "no is-running short-circuit found"; false; }
  [ -n "$t" ] || { echo "no tell block found — the fixture no longer matches the subject"; false; }
  [ "$g" -lt "$t" ] || { echo "the is-running guard ($g) comes AFTER the tell ($t)"; false; }
}

@test "shellcheck can READ it — the reason it is bash and not zsh" {
  # 410f920c9's header records that as the repo's first zsh script under bin/, shellcheck refused
  # it outright (SC1071) — i.e. tracking a file the gates cannot read is only half the move. If a
  # later edit reintroduces a zsh shebang this goes red, which is the point.
  head -1 "$KA" | grep -q 'bash' || { echo "shebang is not bash — shellcheck cannot read it"; false; }
  run shellcheck -S error "$KA"
  [ "$status" -eq 0 ] || { echo "shellcheck -S error is not clean: $output"; false; }
}
