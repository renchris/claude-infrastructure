#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031,SC2329,SC2317
# config-mirror.zsh — a DERIVATIVE of an isolated name must be isolated too (backlog fa475126f710).
#
# The isolate-set is a list of SPELLINGS, and the identity family has many. Measured on this box:
# ~/.claude-quaternary held 28 `.claude.json*` entries, 25 of them `.claude.json.tmp.<pid>.<hash>`
# full identity snapshots, and ~/.claude-next held 8 including `.claude.json.bak-ms365-restore` —
# against exactly TWO listed spellings. It is the same failure the transient-lock arm already
# records in its own comment: the lists carried session-index.lock and still missed
# .oauth_refresh.lock when the vendor added it.
#
# THE EFFECT IS WHAT IS ASSERTED, not the string — this suite's sibling exists because a grep-only
# guard passed while `tasks` split the board four ways for months. Every case below RUNS the mirror
# against a fake $HOME and reads whether a symlink was created.
#
# L4 CONTROLS, both directions: a derivative of a name this dir does NOT isolate must still be
# SHARED (`settings.json.bak-*`), and `.credentials.json.*` must follow its base per-dir — isolated
# for account 2, shared into .claude-next, which shares account 1's credentials by design. A rule
# that over-reached into "anything with a dot" goes red on the first; one that hardcoded the
# identity family instead of deriving from the declared policy goes red on the second.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  MIRROR="$REPO/lib/config-mirror.zsh"
  SRC="$HOME/.claude"; mkdir -p "$SRC"
}

seed() { printf 'x\n' > "$SRC/$1"; }
sync_into() { run zsh -fc "source '$MIRROR'; _cc_sync_config_mirror \"\$HOME/$1\" 2>&1"; }

@test ".claude.json.tmp.<pid>.<hash> is NOT shared — it follows .claude.json" {
  seed '.claude.json.tmp.9182.abcdef'
  sync_into .claude-secondary
  [ ! -e "$HOME/.claude-secondary/.claude.json.tmp.9182.abcdef" ]
}

@test ".claude.json.bak-ms365-restore is NOT shared, in the same-account dir too" {
  seed '.claude.json.bak-ms365-restore'
  sync_into .claude-next
  [ ! -e "$HOME/.claude-next/.claude.json.bak-ms365-restore" ]
}

@test "an existing WRONG symlink for a derivative is healed away" {
  seed '.claude.json.bak-tenantfix'
  mkdir -p "$HOME/.claude-quaternary"
  ln -sfn "$SRC/.claude.json.bak-tenantfix" "$HOME/.claude-quaternary/.claude.json.bak-tenantfix"
  [ -L "$HOME/.claude-quaternary/.claude.json.bak-tenantfix" ]
  sync_into .claude-quaternary
  [ ! -e "$HOME/.claude-quaternary/.claude.json.bak-tenantfix" ]
}

@test ".credentials.json.bak follows its BASE per dir: isolated for account 2" {
  seed '.credentials.json.bak'
  sync_into .claude-secondary
  [ ! -e "$HOME/.claude-secondary/.credentials.json.bak" ]
}

# CONTROL — .claude-next shares account 1's credentials by design, so the derivative must too.
# A rule that hardcoded the identity family rather than deriving it from the declared policy
# goes RED here.
@test ".credentials.json.bak is SHARED into .claude-next, because its base is" {
  seed '.credentials.json.bak'
  sync_into .claude-next
  [ -L "$HOME/.claude-next/.credentials.json.bak" ]
}

# CONTROL — settings.json is isolated NOWHERE, so no spelling of it may be swept up.
@test "settings.json.bak-kitty-20260904 is still SHARED (the rule is not 'anything dotted')" {
  seed 'settings.json.bak-kitty-20260904'
  sync_into .claude-secondary
  [ -L "$HOME/.claude-secondary/settings.json.bak-kitty-20260904" ]
}

# CONTROL — the ordinary shared case still works, so a green run cannot mean "the mirror stopped
# symlinking altogether".
@test "an ordinary shared file is still symlinked" {
  seed 'model-config.yaml'
  sync_into .claude-secondary
  [ -L "$HOME/.claude-secondary/model-config.yaml" ]
}

@test "daemon and jobs are isolated in every dir the map names" {
  for acct in .claude-next .claude-secondary .claude-tertiary .claude-quaternary; do
    run grep "^_CC_ISOLATE\[\$HOME/$acct\]" "$MIRROR"
    [ "$status" -eq 0 ]
    echo "$output" | grep -Eq "[ ']daemon[ ']" || { echo "daemon not isolated for $acct" >&2; return 1; }
    echo "$output" | grep -Eq "[ ']jobs[ ']"   || { echo "jobs not isolated for $acct" >&2;   return 1; }
  done
}

@test "daemon/ present in ~/.claude is NOT shared into an account dir" {
  mkdir -p "$SRC/daemon"
  sync_into .claude-secondary
  [ ! -e "$HOME/.claude-secondary/daemon" ]
}
