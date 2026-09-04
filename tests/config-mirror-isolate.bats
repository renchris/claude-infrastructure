#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# SC2317 ("command appears unreachable") is the same bats false-positive as SC2329 beside it:
# the linter cannot see that `@test` bodies are invoked by the bats runner, so each one reads as
# dead code. File-level, because it is a property of the harness rather than of any single line.
# (NB: no comment line here may BEGIN with the linter's own name — it would be parsed as a
# directive, SC1073/SC1072, and abort the scan of this entire file.)
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

# --- transient lock/pid artifacts must never be shared (2026-08-02) -----------------------------
# A dangling lock symlink is not inert: proper-lockfile reads mkdir=EEXIST + stat=ENOENT as
# ELOCKED, i.e. "held forever", so the guarded operation can never run. Live instance: the mirror
# captured ~/.claude/.oauth_refresh.lock on 2026-07-31 (14:58-16:36) into all four account dirs;
# the real lock was then released, and from 70 minutes later every in-session OAuth token refresh
# on every account failed at lock acquisition — an 8-hourly forced /login for two days.

@test "EFFECT: a transient lock in ~/.claude is NOT symlinked into an account dir" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  export HOME="$D/fh-lock"
  mkdir -p "$HOME/.claude" "$HOME/.claude-secondary"
  printf '{}\n' > "$HOME/.claude/.claude.json"
  : > "$HOME/.claude/.oauth_refresh.lock"
  : > "$HOME/.claude/history.jsonl.lock"
  mkdir -p "$HOME/.claude/session-index.lock.d"
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-secondary\""
  [ "$status" -eq 0 ]
  for n in .oauth_refresh.lock history.jsonl.lock session-index.lock.d; do
    if [ -L "$HOME/.claude-secondary/$n" ]; then
      echo "REGRESSION: transient '$n' was shared into the account dir" >&2; return 1
    fi
  done
  return 0
}

@test "EFFECT: an ALREADY-dangling link into ~/.claude is reaped (source since deleted)" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  export HOME="$D/fh-dangle"
  mkdir -p "$HOME/.claude" "$HOME/.claude-secondary"
  printf '{}\n' > "$HOME/.claude/.claude.json"
  # exactly the production shape: target never existed / was released
  ln -s "$HOME/.claude/.oauth_refresh.lock" "$HOME/.claude-secondary/.oauth_refresh.lock"
  [ -L "$HOME/.claude-secondary/.oauth_refresh.lock" ]
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-secondary\""
  [ "$status" -eq 0 ]
  if [ -L "$HOME/.claude-secondary/.oauth_refresh.lock" ]; then
    echo "REGRESSION: dangling lock link survived the sync — refresh stays permanently ELOCKED" >&2
    return 1
  fi
  return 0
}

@test "EFFECT: the reaper is scoped — a dangling link NOT into ~/.claude is untouched" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  export HOME="$D/fh-scope"
  mkdir -p "$HOME/.claude" "$HOME/.claude-secondary"
  printf '{}\n' > "$HOME/.claude/.claude.json"
  ln -s "$D/somewhere-else/gone" "$HOME/.claude-secondary/operator-link"
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-secondary\""
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude-secondary/operator-link" ]
}

@test "EFFECT: a HEALTHY shared link survives the reaper (it is not over-broad)" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  export HOME="$D/fh-healthy"
  mkdir -p "$HOME/.claude/tasks" "$HOME/.claude-secondary"
  printf '{}\n' > "$HOME/.claude/.claude.json"
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-secondary\""
  [ "$status" -eq 0 ]
  [ -L "$HOME/.claude-secondary/tasks" ]
  [ -e "$HOME/.claude-secondary/tasks" ]
}

# ── the FORK report (2026-09-04) ───────────────────────────────────────────────────────────────────
# Safe mode cannot convert a forked real dir, by design (converting is not race-safe with live
# panes). That is correct and stays. What was wrong is that it skipped SILENTLY, while all three
# sibling outcomes in the same loop print — so the one condition that PERSISTS across every future
# run was the only one nothing announced. ~/.claude-next carried a frozen `commands` for seven weeks
# and the operator found it by typing a slash command that did not exist there.

@test "EFFECT: safe mode REPORTS a forked real dir instead of skipping it silently" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  export HOME="$D/fh-fork"
  mkdir -p "$HOME/.claude/commands" "$HOME/.claude-next/commands"
  printf '{}\n' > "$HOME/.claude/.claude.json"
  printf 'shared\n' > "$HOME/.claude/commands/real.md"
  printf 'forked\n' > "$HOME/.claude-next/commands/stale.md"
  run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/.claude-next\" 2>&1"
  [ "$status" -eq 0 ]
  # COUNT, never `grep -q`: under pipefail a matching -q SIGPIPEs its producer and the pipeline
  # reports failure on the very input it matched. And the assertion is `[ ] || {…}`, never
  # `A && {…}` — errexit cannot reach the latter, so it passes whatever the subject does.
  n_fork="$(printf '%s\n' "$output" | grep -c "FORKED real 'commands'" || true)"
  [ "${n_fork:-0}" -ge 1 ] || {
    echo "SILENT SKIP: safe mode passed over a forked real dir and said nothing" >&2; return 1; }
  # …and it must still NOT have touched it — reporting is not converting.
  # Separate statements, not `A && B`: errexit does not fire inside an && list, so the compound
  # form asserts nothing when A is false.
  [ -d "$HOME/.claude-next/commands" ]
  [ ! -L "$HOME/.claude-next/commands" ]
  [ -f "$HOME/.claude-next/commands/stale.md" ]
}

@test "NON-VACUITY: strip the report line and the same fixture goes silent" {
  command -v zsh >/dev/null 2>&1 || skip "zsh unavailable"
  # Replays the PRE-FIX subject: the mutant restores the bare `(( convert )) || continue`. If this
  # goes on printing, the test above is passing on some other line and proves nothing about the fix.
  local mut="$D/mirror-mutant.zsh"
  # python3, not sed: the line being mutated contains `||` and `{`, which collide with sed's
  # delimiter and flag parsing. A mutant built by a quoting accident is an inert control.
  python3 -c '
import sys
src, dst = sys.argv[1], sys.argv[2]
out, hit = [], 0
for line in open(src):
    if "FORKED real" in line and "(( convert ))" in line:
        out.append("      (( convert )) || continue\n"); hit += 1
    else:
        out.append(line)
open(dst, "w").writelines(out)
sys.exit(0 if hit == 1 else 1)
' "$MIRROR" "$mut" || { echo "MUTANT NOT APPLIED — anchor matched $? times, not once; control is inert" >&2; return 1; }
  n_marker="$(grep -c "FORKED real" "$mut" || true)"
  [ "${n_marker:-0}" -eq 0 ] || {
    echo "MUTANT NOT APPLIED — marker survives, so this control is inert" >&2; return 1; }
  export HOME="$D/fh-fork-mut"
  mkdir -p "$HOME/.claude/commands" "$HOME/.claude-next/commands"
  printf '{}\n' > "$HOME/.claude/.claude.json"
  printf 'forked\n' > "$HOME/.claude-next/commands/stale.md"
  run zsh -fc "source '$mut'; _cc_sync_config_mirror \"\$HOME/.claude-next\" 2>&1"
  [ "$status" -eq 0 ]
  n_mut="$(printf '%s\n' "$output" | grep -c "FORKED real" || true)"
  [ "${n_mut:-0}" -eq 0 ] || {
    echo "MUTANT STILL REPORTS — the assertion above is not keyed on the fix" >&2; return 1; }
  return 0
}
