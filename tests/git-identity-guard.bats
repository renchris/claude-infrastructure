#!/usr/bin/env bats
# git-identity-guard — the EFFECT half of the 2026-08-05 git-identity leak.
#
# The two defences that shipped on 2026-08-05 are both WRITE-side: scripts/git-identity-lint.sh
# (leaky source) and the validate-bash.sh PreToolUse rule (leaky agent one-liners). Between them
# they stop the identity from being written wrongly. Neither stands between a wrong identity and
# a COMMIT — so when one escaped before they landed, `user.email=t@e.com` sat in this repo's
# .git/config from 2026-08-05 to 2026-08-08 and produced 710 unattributable commits while every
# sensor read green. These tests pin the brake.
#
# THE LOAD-BEARING TEST IS 6, NOT 4. A guard that reads `git config user.email` catches the local
# override (test 4) and reads GREEN on the env, -c and --author paths (tests 6-8) — two of five.
# githooks/pre-commit reads `git var GIT_AUTHOR_IDENT`, the value git itself will stamp, so it
# cannot disagree with the commit it gates. Tests 6-8 are what discriminate the two designs; a
# config-reading rewrite passes 4 and 5 and fails those three.
#
# Every identity write below targets `git -C "${r:?repo path required}"`. That guard is not
# decoration: this file writes `t@e.com` dozens of times, which is the exact payload that escaped
# in the first place, and `git -C ""` is a NO-OP that would land every one of them in the caller's
# checkout. `${r:?}` aborts instead of expanding to empty. scripts/git-identity-lint.sh enforces
# the shape and flagged all 19 sites here on the first run — the guard caught its own test file.

setup() {
  # Hermetic HOME: the subject reads --global config, and a real ~/.gitconfig would make the
  # "wrong global" arm a function of the developer's machine.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig"
  git config --global user.email good@example.test
  git config --global user.name  Good
  git config --global init.defaultBranch main

  SRC="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$SRC/githooks/pre-commit"
  ASSERT="$SRC/scripts/git-identity-assert.sh"
  D="$BATS_TEST_TMPDIR/w"; mkdir -p "$D"

  # Pin the identity contract so these tests never depend on the operator's real address.
  export CC_GIT_IDENTITY_EMAIL=good@example.test
  export CC_GIT_IDENTITY_OWNER=owner
  export CC_GIT_IDENTITY_HOOK="$HOOK"
}

# mkrepo <name> [remote-url] — a fixture repo with a guaranteed-non-empty path.
mkrepo() {
  local r="$D/${1:?mkrepo: name required}"
  mkdir -p "$r"; git -C "$r" init -q
  [ -n "${2:-}" ] && git -C "$r" remote add origin "$2"
  echo seed > "$r/f"; git -C "$r" add f
  echo "$r"
}

check() { run "$HOOK" --check "$1"; }

# ── Reach control — this file must be able to go RED ──────────────────────────────────────────
# Every "allowed" assertion below is vacuously true if the hook cannot refuse anything at all
# (a missing subject, a bad shebang, an early exit 0). This pins the refusal itself, so an inert
# hook takes the file red instead of green.
@test "control: the hook is REACHED and can refuse" {
  local r; r="$(mkrepo ctl https://github.com/owner/x.git)"
  git -C "${r:?repo path required}" config user.email nobody@nowhere.test
  check "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"WRONG"* ]]
}

# ── Scope: the bats corpus must stay inert ────────────────────────────────────────────────────
@test "out of scope: a repo with NO remote is never gated" {
  local r; r="$(mkrepo noremote)"
  git -C "${r:?repo path required}" config user.email t@e.com
  git -C "${r:?repo path required}" config user.name t
  check "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == *"n/a"* ]]
}

@test "out of scope: a repo on someone ELSE's github is never gated" {
  local r; r="$(mkrepo foreign https://github.com/other-person/x.git)"
  git -C "${r:?repo path required}" config user.email t@e.com
  check "$r"
  [ "$status" -eq 0 ]
}

@test "out of scope: an ssh-form remote for the owner IS in scope" {
  local r; r="$(mkrepo sshform git@github.com:owner/x.git)"
  git -C "${r:?repo path required}" config user.email t@e.com
  check "$r"
  [ "$status" -eq 1 ]
}

# ── The five identity paths ───────────────────────────────────────────────────────────────────
@test "4/5 local .git/config override is REFUSED (the 2026-08-05 fault)" {
  local r; r="$(mkrepo loc https://github.com/owner/x.git)"
  git -C "${r:?repo path required}" config user.email t@e.com
  git -C "${r:?repo path required}" config user.name t
  check "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"t@e.com"* ]]
}

@test "5/5 the sanctioned identity is ALLOWED" {
  local r; r="$(mkrepo good https://github.com/owner/x.git)"
  check "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == ok* ]]
}

@test "6/5 GIT_AUTHOR_EMAIL env is REFUSED — a config read would pass this" {
  local r; r="$(mkrepo env https://github.com/owner/x.git)"
  GIT_AUTHOR_EMAIL=t@e.com GIT_AUTHOR_NAME=t run "$HOOK" --check "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ENVIRONMENT"* ]]
}

@test "7/5 a wrong GLOBAL with no local override is REFUSED" {
  git config --global user.email t@e.com
  local r; r="$(mkrepo glob https://github.com/owner/x.git)"
  check "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--global"* ]]   # the cure must name the layer the fault is actually in
}

# ── End to end: the gate must stop a real commit, in the repo AND its worktrees ───────────────
@test "a real commit under a wrong identity is BLOCKED" {
  local r; r="$(mkrepo e2e https://github.com/owner/x.git)"
  mkdir -p "$r/.git/hooks"; ln -sf "$HOOK" "$r/.git/hooks/pre-commit"
  git -C "${r:?repo path required}" config user.email t@e.com
  git -C "${r:?repo path required}" config user.name t
  run git -C "$r" commit -q -m "should not land"
  [ "$status" -ne 0 ]
  run git -C "$r" log --oneline
  [[ "$output" != *"should not land"* ]]
}

@test "a real commit under the sanctioned identity LANDS" {
  local r; r="$(mkrepo e2eok https://github.com/owner/x.git)"
  mkdir -p "$r/.git/hooks"; ln -sf "$HOOK" "$r/.git/hooks/pre-commit"
  run git -C "$r" commit -q -m "should land"
  [ "$status" -eq 0 ]
  run git -C "$r" log --oneline
  [[ "$output" == *"should land"* ]]
}

@test "a LINKED WORKTREE inherits the gate (one install covers ~200 worktrees)" {
  local r; r="$(mkrepo wtree https://github.com/owner/x.git)"
  mkdir -p "$r/.git/hooks"; ln -sf "$HOOK" "$r/.git/hooks/pre-commit"
  git -C "$r" commit -q -m base
  git -C "$r" worktree add -q "$D/wtlinked" -b side
  git -C "${r:?repo path required}" config user.email t@e.com
  echo x > "$D/wtlinked/g"; git -C "$D/wtlinked" add g
  run git -C "$D/wtlinked" commit -q -m "wt should not land"
  [ "$status" -ne 0 ]
}

# ── Exemption: a recorded decision, never a silent hole ───────────────────────────────────────
@test "an exemption WITH a reason is honoured" {
  local r; r="$(mkrepo exempt https://github.com/owner/x.git)"
  git -C "${r:?repo path required}" config user.email contributors@project.test
  git -C "${r:?repo path required}" config --local cc.identity.exempt "upstream requires the project address"
  check "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exempt"* ]] || false
  [[ "$output" == *"upstream requires"* ]]   # the reason is surfaced, not swallowed
}

@test "an EMPTY exemption is not an exemption" {
  local r; r="$(mkrepo exempt0 https://github.com/owner/x.git)"
  git -C "${r:?repo path required}" config user.email t@e.com
  git -C "${r:?repo path required}" config --local cc.identity.exempt ""
  check "$r"
  [ "$status" -eq 1 ]
}

# ── The cure must be one this same gate ACCEPTS ───────────────────────────────────────────────
# A gate that prints a Fix it would itself reject is a known failure in this tree
# (memory: work-item-remedy-can-become-forbidden). This runs the printed cure and re-checks.
@test "the printed cure for a local override actually clears the gate" {
  local r; r="$(mkrepo cure https://github.com/owner/x.git)"
  git -C "${r:?repo path required}" config user.email t@e.com
  git -C "${r:?repo path required}" config user.name t
  check "$r"
  [ "$status" -eq 1 ]
  [[ "$output" == *"remove-section user"* ]] || false
  git -C "${r:?repo path required}" config --local --remove-section user
  check "$r"
  [ "$status" -eq 0 ]
}

# ── repair / install ──────────────────────────────────────────────────────────────────────────
@test "repair drops a shadowing local override and never invents an identity" {
  local r; r="$(mkrepo rep https://github.com/owner/x.git)"
  git -C "${r:?repo path required}" config user.email t@e.com
  git -C "${r:?repo path required}" config user.name t
  run bash "$ASSERT" repair "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == *"repaired"* ]] || false
  run git -C "${r:?repo path required}" config --local --get user.email
  [ -z "$output" ]
}

@test "repair REFUSES to guess when the global itself is wrong" {
  git config --global user.email t@e.com
  local r; r="$(mkrepo repglob https://github.com/owner/x.git)"
  run bash "$ASSERT" repair "$r"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NEEDS-HUMAN"* ]]
}

@test "install never clobbers a foreign pre-commit" {
  local r; r="$(mkrepo inst https://github.com/owner/x.git)"
  mkdir -p "$r/.git/hooks"
  printf '#!/bin/sh\nexit 0\n' > "$r/.git/hooks/pre-commit"
  chmod +x "$r/.git/hooks/pre-commit"
  run bash "$ASSERT" install "$r"
  [ "$status" -ne 0 ]
  [[ "$output" == *"SKIP-FOREIGN"* ]] || false
  run cat "$r/.git/hooks/pre-commit"
  [[ "$output" == *"exit 0"* ]]   # the incumbent hook is untouched
}

@test "install is idempotent" {
  # One statement per line. A non-final `[[ ]]` is a bash KEYWORD, not a command, and errexit
  # does NOT abort on it — measured: a failing non-final `[[ ]]` is silently swallowed while a
  # failing `[ ]` two lines away is caught. Five assertions in this file were dead on first
  # write; scripts/bats-assert-liveness.py caught them and its fixer repaired four, DECLINING
  # this semicolon-compound rather than guessing. Hand-edited, mutation-verified both ways.
  local r; r="$(mkrepo inst2 https://github.com/owner/x.git)"
  run bash "$ASSERT" install "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == *"installed"* ]] || false
  run bash "$ASSERT" install "$r"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already"* ]]
}

@test "selftest's own controls discriminate" {
  run bash "$ASSERT" selftest
  [ "$status" -eq 0 ]
  [[ "$output" == *"PASS"* ]]
}

# ── postland-verify's restore predicate — the RECURRENCE ENGINE ───────────────────────────────
# scripts/postland-verify.sh:identity_assert used to restore the run-start [user] section
# VERBATIM. A sweep beginning while .git/config already held `t@e.com` therefore snapshotted the
# poison and wrote it back at the end — so the guard built to undo a corpus leak instead PINNED
# it. Measured 2026-08-08: pid 27946 snapshotted at 01:40, a human unset at 02:13, restore due
# ~04:40. That is why the 2026-08-05 fix landed and the operator still saw `t` three days later.
# identity_snap_ok is the discriminator that stops it; these are its arms.
load_snap_ok() {
  eval "$(sed -n '/^identity_snap_ok() {/,/^}/p' "$SRC/scripts/postland-verify.sh")"
  [ "$(type -t identity_snap_ok)" = function ]   # extraction control: a sed miss must not pass
}

@test "postland: an ABSENT baseline is restorable (the normal, healthy case)" {
  load_snap_ok
  run identity_snap_ok ""
  [ "$status" -eq 0 ]
}

@test "postland: a SANCTIONED baseline is restorable" {
  load_snap_ok
  # The sanctioned address is whatever CC_GIT_IDENTITY_EMAIL pins (setup() sets it), NOT a literal
  # — pinning the operator's real address here would make the suite a function of this machine.
  run identity_snap_ok "user.email $CC_GIT_IDENTITY_EMAIL
user.name Good"
  [ "$status" -eq 0 ]
}

@test "postland: the SHIPPED DEFAULT is the address that attributes, with no env pin" {
  # The three tests around this one run under a pinned contract, so they would all pass even if
  # the shipped fallback were wrong. This is the arm that reads what actually ships: unset the
  # pin and confirm the built-in default admits ren.chris@outlook.com and refuses the poison.
  # (That address → account `renchris` was verified against the GitHub API on 2026-08-08; it is a
  # perishable fact, re-derivable with `git-identity-assert.sh verify-attribution`.)
  unset CC_GIT_IDENTITY_EMAIL
  load_snap_ok
  run identity_snap_ok "user.email ren.chris@outlook.com
user.name Chris Ren"
  [ "$status" -eq 0 ]
  run identity_snap_ok "user.email t@e.com
user.name t"
  [ "$status" -ne 0 ]
}

@test "postland: a POISONED baseline is NOT restorable — the fix" {
  load_snap_ok
  run identity_snap_ok "user.email t@e.com
user.name t"
  [ "$status" -ne 0 ]
}

# identity_assert's UNCHANGED-but-wrong arm. Guarding only the CHANGED case left the machine
# wedged: once a bad value is resident, every later sweep reads now == snap and returns early, so
# nothing clears it — and with the pre-commit gate installed, every commit is refused until a
# human intervenes. Fail-closed is right for one commit and wrong as a resting state.
load_assert_fns() {
  # These four look unused to shellcheck and are not: they are the ambient state the extracted
  # postland functions read and append to, and the eval below is opaque to static analysis.
  # Annotated per variable rather than file-wide, so a genuinely unused one still gets caught.
  # shellcheck disable=SC2034
  REPO="$1"
  FAILING=()
  # shellcheck disable=SC2034
  FAILNAME=()
  # shellcheck disable=SC2034
  FAILTEST=""
  log() { :; }
  eval "$(sed -n '/^identity_snapshot() {/,/^}/p'  "$SRC/scripts/postland-verify.sh")"
  eval "$(sed -n '/^identity_snap_ok() {/,/^}/p'   "$SRC/scripts/postland-verify.sh")"
  eval "$(sed -n '/^identity_assert() {/,/^}/p'    "$SRC/scripts/postland-verify.sh")"
  [ "$(type -t identity_assert)" = function ] || return 1   # extraction control
}

@test "postland: a RESIDENT unsanctioned identity is dropped even when UNCHANGED" {
  local r; r="$(mkrepo resident https://github.com/owner/x.git)"
  git -C "${r:?repo path required}" config user.email t@e.com
  git -C "${r:?repo path required}" config user.name t
  load_assert_fns "$r"
  IDENTITY_SNAP="$(identity_snapshot)"          # snapshot the poison, as a real sweep would
  [ -n "$IDENTITY_SNAP" ] || false              # control: the fixture really is poisoned
  identity_assert
  run git -C "${r:?repo path required}" config --local --get user.email
  [ -z "$output" ]                              # dropped → falls through to the global
}

@test "postland: that drop does NOT convict the run (no auto-revert of an inherited fault)" {
  # A red here reaches red_actions, which can auto-revert. This run did not cause the fault.
  local r; r="$(mkrepo resident2 https://github.com/owner/x.git)"
  git -C "${r:?repo path required}" config user.email t@e.com
  load_assert_fns "$r"
  IDENTITY_SNAP="$(identity_snapshot)"
  identity_assert
  [ "${#FAILING[@]}" -eq 0 ]
}

@test "postland: a SANCTIONED resident identity is left alone" {
  # The mirror arm — without it the test above passes for a function that drops unconditionally.
  local r; r="$(mkrepo resident3 https://github.com/owner/x.git)"
  git -C "${r:?repo path required}" config user.email "$CC_GIT_IDENTITY_EMAIL"
  load_assert_fns "$r"
  IDENTITY_SNAP="$(identity_snapshot)"
  identity_assert
  run git -C "${r:?repo path required}" config --local --get user.email
  [ "$output" = "$CC_GIT_IDENTITY_EMAIL" ]
}

@test "postland: the OTHER unattributed family is not restorable either" {
  # ren.chris+claude@outlook.com looks legitimate and is just as unattributable on GitHub
  # (verified 2026-08-08). A denylist keyed on `t` would have restored this one.
  load_snap_ok
  run identity_snap_ok "user.email ren.chris+claude@outlook.com
user.name Chris Ren"
  [ "$status" -ne 0 ]
}
