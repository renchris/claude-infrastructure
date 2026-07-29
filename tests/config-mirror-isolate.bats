#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329
# config-mirror.zsh — which state each account config dir SHARES with ~/.claude vs isolates.
#
# This file exists because the isolate-set is a one-word-per-entry list with very large blast radius:
# adding `tasks` to it split the operator's task board four ways for months, and nothing anywhere
# failed. So the guard is not "the string is absent" alone — the last test RUNS the mirror against a
# fake $HOME and reads the EFFECT (is tasks/ actually a symlink to the shared store?), because a
# grep-only assertion still passes if the mirror stops symlinking for some unrelated reason.
#
# The isolated-set assertions are the positive control. Without them a test that only checks `tasks`
# is absent would also pass if someone emptied the isolate-set entirely — which would start sharing
# credentials and transcripts between DIFFERENT accounts.

setup() {
  # Hermetic $HOME: these suites drive tools whose defaults are $HOME/.claude/... — without
  # this, a leaked default reads (or writes) the operator's LIVE board and the verdict starts
  # depending on whatever the fleet happens to be doing. Enforced by ship-land's hermeticity
  # ratchet, which blocks the land rather than letting the suite look green against live state.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIRROR="$REPO/lib/config-mirror.zsh"
  D="$BATS_TEST_TMPDIR"
  isolate_line() { grep "^_CC_ISOLATE\[\$HOME/$1\]" "$MIRROR"; }
}

@test "the mirror is version-controlled in the repo (not an unversioned live-only file)" {
  [ -f "$MIRROR" ]
  git -C "$REPO" ls-files --error-unmatch lib/config-mirror.zsh >/dev/null 2>&1
}

@test "tasks is NOT isolated for any cross-account dir — the board is shared" {
  for acct in .claude-secondary .claude-tertiary .claude-quaternary; do
    run isolate_line "$acct"
    [ "$status" -eq 0 ]
    # `cmd && false` is the repo's known dead-assertion shape (errexit-exempt in some positions),
    # so failure is signalled with an explicit `return 1` that cannot be skipped. Word-boundary
    # match so it can never be satisfied by the tasks-index.json substring.
    if echo "$output" | grep -Eq "[ ']tasks[ ']"; then
      echo "REGRESSION: 'tasks' is isolated again for $acct — the board is split per account" >&2
      return 1
    fi
    if echo "$output" | grep -q "tasks-index.json"; then
      echo "REGRESSION: 'tasks-index.json' is isolated again for $acct" >&2
      return 1
    fi
  done
  return 0
}

@test "account-identity state IS still isolated — the positive control" {
  for acct in .claude-secondary .claude-tertiary .claude-quaternary; do
    run isolate_line "$acct"
    [ "$status" -eq 0 ]
    for key in .credentials.json projects sessions history.jsonl statsig; do
      echo "$output" | grep -q "$key" || false
    done
  done
}

@test "install.sh deploys lib/*.zsh so the repo copy is what actually runs" {
  grep -q 'REPO_DIR"/lib/\*\.zsh' "$REPO/install.sh" || false
}

@test "EFFECT: the mirror symlinks tasks/ into an account dir (not just absent from a string)" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  export HOME="$D/fakehome"
  mkdir -p "$HOME/.claude/tasks/someboard" "$HOME/.claude-secondary"
  printf '{}\n' > "$HOME/.claude/.claude.json"
  echo hi > "$HOME/.claude/tasks/someboard/1.json"
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-secondary\""
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude-secondary/tasks" ]
  [ "$(readlink "$HOME/.claude-secondary/tasks")" = "$HOME/.claude/tasks" ]
  [ -f "$HOME/.claude-secondary/tasks/someboard/1.json" ]
}

@test "EFFECT: credentials are still NOT shared into a cross-account dir" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  export HOME="$D/fakehome2"
  mkdir -p "$HOME/.claude" "$HOME/.claude-secondary"
  printf '{}\n' > "$HOME/.claude/.claude.json"
  printf 'SECRET\n' > "$HOME/.claude/.credentials.json"
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-secondary\""
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude-secondary/.credentials.json" ]
}
