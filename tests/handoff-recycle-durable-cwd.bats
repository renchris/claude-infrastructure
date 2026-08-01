#!/usr/bin/env bats
# --recycle must survive its OWN exit destroying its cwd.
#
# THE INCIDENT (2026-07-29, session e891e080, /tmp/handoff-recycle-71B42B48-*.log): the session ran
# in a worktree the CC HARNESS created (EnterWorktree). The recycle typed `/exit`; the harness reaped
# its session-owned worktree on exit; the watcher then typed `cd <worktree> && <launcher> …`, the cd
# failed, `&&` short-circuited, and NOTHING relaunched. The guards were correct but unrecoverable —
# loud, then stranded. A recycle whose only cd target can be destroyed BY the exit it performs has no
# survivor by construction.
#
# The fix bakes a survivor in (the main checkout, via --git-common-dir) ONLY when $PWD is a linked
# worktree. Tests 1/2 pin the two command shapes; tests 3/4 are the BEHAVIORAL pair — the shape is
# worthless if the chain does not actually recover, and test 4 is test 3's positive control.

# Execute an emitted launch chain THE WAY PRODUCTION EXECUTES IT — in zsh.
#
# These BEHAVIORAL tests take the real emitted command and run it; running it under bats' own bash
# via `eval` was an accident of the host shell, not a modelling decision, and it silently diverged
# from production. The emitted string is zsh-specific BY CONSTRUCTION — it is typed into the
# operator's interactive zsh pane, and the launcher it names is a zsh alias/function that no bash
# could resolve anyway (these tests only run at all because they stub the launcher as a PATH
# binary). It also now carries `nocorrect` (item 7146aab37a9a), a zsh RESERVED WORD that shields
# the launcher from `setopt CORRECT`'s `[nyae]` spell-prompt; bash has no such word, so a bash
# `eval` reports `command not found` and the chain dies before the launcher — a RED that says
# nothing about the cd/fallback logic these tests exist to prove.
#
# `zsh -f` = no operator rc (hermetic); PATH is exported by the caller so the launcher stubs still
# resolve, and `nocorrect` is a reserved word in non-interactive zsh too (verified: `zsh -f -c
# 'nocorrect echo ok'` → ok).
run_emitted() { # $1=the emitted chain
  command -v zsh >/dev/null 2>&1 || { echo "zsh absent — cannot run the emitted chain faithfully"; return 1; }
  zsh -f -c "$1"
}

setup() {
  # HERMETIC $HOME (test-hermeticity-lint.sh — binds every NEW suite), with the gate's own idiom:
  # the fixture $HOME SYMLINKS the read-only config the subject must resolve (~/.claude carries the
  # launcher/account layout) and owns everything else. A bare empty $HOME makes the subject exit 1
  # before it ever prints the command this suite is about — an ABSENT path manufactures a false red,
  # which is precisely what gate_home_setup's symlink farm exists to prevent. A --dry-run writes
  # nothing, so the link stays read-only in practice.
  local real_home="$HOME"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  [ -e "$real_home/.claude" ] && ln -s "$real_home/.claude" "$HOME/.claude"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  PF="$BATS_TEST_TMPDIR/payload.txt"; echo "resume the work" > "$PF"
  # A real repo + a real LINKED worktree — the exact topology the incident occurred in. Nothing is
  # simulated: --git-common-dir must resolve through genuine git plumbing, not a fixture's guess.
  # PHYSICAL paths throughout: BATS_TEST_TMPDIR lives under /var/… which is a symlink to
  # /private/var/…, and git reports resolved paths — comparing the two spellings is the trap that
  # made this suite's first RED run look like a logic failure when it was a fixture failure.
  git init -q "$BATS_TEST_TMPDIR/main"
  MAIN="$(cd "$BATS_TEST_TMPDIR/main" && pwd -P)"
  git -C "$MAIN" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$MAIN" worktree add -q --detach "$BATS_TEST_TMPDIR/linked" HEAD
  WT="$(cd "$BATS_TEST_TMPDIR/linked" && pwd -P)"
}

# The `command:` line of a recycle --dry-run, run FROM <dir>. Real artifact, real dry-run.
# --launcher is EXPLICIT so the assertion cannot depend on which account the RUNNING session uses
# (account derivation reads CLAUDE_CONFIG_DIR — a caller-identity leak, the hermetic-suite trap).
cmd_line() { ( cd "$1" && bash "$HF" --recycle --dry-run --prompt-file "$PF" --session-id "fake:UUID" --launcher claude 2>&1 ) | grep -E '^command:' | head -1; }

@test "linked worktree: the relaunch cd carries a durable fallback to the main checkout" {
  run cmd_line "$WT"
  [ -n "$output" ] || false
  echo "$output" | grep -qF "cd $WT" || false          # still prefers the worktree
  echo "$output" | grep -qF "|| cd $MAIN" || false     # …but survives its removal
}

@test "main checkout: NO fallback chain — the 90% case keeps its single cd (non-regression)" {
  # The fix must add zero surface where the incident cannot occur: a main checkout is not reaped by
  # a session exit. Pre-fix this suite's other assertion did not exist; THIS one must hold on BOTH
  # sides of the change, which is what makes it a regression guard rather than a restatement.
  run cmd_line "$MAIN"
  [ -n "$output" ] || false
  echo "$output" | grep -qF "cd $MAIN" || false
  ! echo "$output" | grep -q '||' || false
}

@test "BEHAVIORAL: the emitted chain relaunches from the fallback when the cwd VANISHED" {
  # The incident, replayed: take the REAL emitted command, destroy the worktree exactly as the
  # harness does, and run it. Pre-fix this reproduces the strand (cd fails, && short-circuits, the
  # launcher never runs) — the whole point of the fix is that it now lands in the fallback instead.
  cmd="$(cmd_line "$WT")"; cmd="${cmd#command:}"
  [ -n "$cmd" ] || false
  # Stub launcher: records the cwd it was launched from. The command names the real launcher, so a
  # PATH stub is what lets the chain execute end-to-end without a real account or iTerm2.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  local rec="$BATS_TEST_TMPDIR/launched-from"
  for l in claude claude2 claude3 claude4 claude-prev; do
    printf '#!/bin/bash\npwd > %s\n' "$rec" > "$BATS_TEST_TMPDIR/bin/$l"
    chmod +x "$BATS_TEST_TMPDIR/bin/$l"
  done
  git -C "$MAIN" worktree remove --force "$WT"     # ← the harness's exit-time reap
  [ ! -d "$WT" ] || false                          # the fixture's own contract
  # shellcheck disable=SC2030,SC2031  # the subshell IS the point: the stub PATH and the cd must not
  # leak into the next test, and `cd "$MAIN"` proves the chain's own cd moved us, not the caller.
  ( export PATH="$BATS_TEST_TMPDIR/bin:$PATH"; cd "$MAIN" && run_emitted "$cmd" ) >/dev/null 2>&1 || true
  [ -f "$rec" ] || false                           # pre-fix: never written — the strand
  [ "$(cat "$rec")" = "$MAIN" ] || false           # landed in the survivor
}

@test "BEHAVIORAL control: with the cwd INTACT the chain still prefers it (no silent redirect)" {
  # Positive control for the test above: if the fallback fired unconditionally, the recovery test
  # would pass for the wrong reason and every healthy recycle would silently change directory.
  cmd="$(cmd_line "$WT")"; cmd="${cmd#command:}"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  local rec="$BATS_TEST_TMPDIR/launched-from-intact"
  printf '#!/bin/bash\npwd > %s\n' "$rec" > "$BATS_TEST_TMPDIR/bin/claude"
  chmod +x "$BATS_TEST_TMPDIR/bin/claude"
  # shellcheck disable=SC2030,SC2031  # the subshell IS the point: the stub PATH and the cd must not
  # leak into the next test, and `cd "$MAIN"` proves the chain's own cd moved us, not the caller.
  ( export PATH="$BATS_TEST_TMPDIR/bin:$PATH"; cd "$MAIN" && run_emitted "$cmd" ) >/dev/null 2>&1 || true
  [ -f "$rec" ] || false
  [ "$(cat "$rec")" = "$WT" ] || false
}
