#!/usr/bin/env bats
# Regression guard: the command handoff-fire TYPES into an interactive zsh must contain no
# command word that zsh might not resolve (2026-07-29 hang).
#
# INCIDENT: firing a Node worktree parked forever on `zsh: correct 'go' to 'god' [nyae]?`. The
# cold-worktree path used to type its whole package-manager detection chain inline, and that chain
# NAMES managers that need not exist on the machine (go, uv, poetry, pipenv, cargo, bun, yarn).
# `setopt CORRECT` (this operator's ~/.zshrc:53) offers a spelling correction for an unknown
# COMMAND WORD as it READS the line — so it fired on the `go mod download` branch, which a Node
# repo can NEVER reach. Result: no session, no error, no timeout, a pane parked on a prompt.
#
# WHY READ-TIME MATTERS: because the trigger is reading, not executing, prefixing the same line
# with `unsetopt correct` cannot fix it — that command has not run when the line is read. The only
# deterministic fix is to keep every correctable word OUT of the typed line: write the chain to a
# file and type `bash <file>`, whose command words (cd, bash, launcher) always resolve. The chain
# then runs under bash, which has no such option at all.
#
# These are SOURCE-level invariants: building a real CMD needs a live iTerm2 + a real worktree, so
# the durable checkable guarantee is the SHAPE of the cold-path command construction.

setup() {
  # Hermetic by construction: this suite only reads the repo's own source, but a live $HOME is a
  # standing hazard (a suite can encode WHO ran it), so fixture it unconditionally.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  # the cold-worktree branch: from the WT_INSTALL assignment through its CMD= line
  COLD="$(sed -n '/^    WT_INSTALL=/,/^    CMD=/p' "$HF")"
}

@test "the cold-path CMD types 'bash <script>', never the install chain inline" {
  [ -n "$COLD" ] || false
  grep -q 'bash \$(printf %q "\$WT_DEPS")' <<<"$COLD" || false
  # the chain must NOT be interpolated into the typed command
  ! grep -q 'CMD=.*\$WT_INSTALL' <<<"$COLD" || false
}

@test "the install chain is written to a file and made executable" {
  grep -q 'WT_DEPS="\$(mktemp' <<<"$COLD" || false
  grep -q '"\$WT_INSTALL"' <<<"$COLD" || false
  grep -q '> "\$WT_DEPS"' <<<"$COLD" || false
  grep -q 'chmod +x "\$WT_DEPS"' <<<"$COLD" || false
}

@test "RED-PROOF: no correctable manager survives into the EFFECTIVE typed command" {
  # The invariant is about what is TYPED, i.e. the CMD line AFTER shell expansion — not the source
  # line. Scanning the raw CMD= line is a DEAD assertion: pre-fix the managers lived in
  # $WT_INSTALL and CMD merely interpolated it, so a raw scan passed on the very bug this guards.
  # Reconstruct the effective command: substitute WT_INSTALL's value wherever CMD references it.
  local install cmdline effective
  install="$(sed -n "s/^    WT_INSTALL='\(.*\)'$/\1/p" <<<"$COLD")"
  [ -n "$install" ] || { echo "could not extract WT_INSTALL"; false; }
  cmdline="$(grep '^    CMD=' <<<"$COLD" | head -1)"
  [ -n "$cmdline" ] || false
  effective="${cmdline//\$WT_INSTALL/$install}"
  local mgr
  for mgr in go uv poetry pipenv cargo bun yarn pnpm npm; do
    if grep -qE "(^|[^-[:alnum:]_])${mgr}([^-[:alnum:]_]|$)" <<<"$effective"; then
      echo "EFFECTIVE typed command names '$mgr' — zsh CORRECT can prompt on it at READ time"
      false
    fi
  done
}

@test "POSITIVE CONTROL: the pre-fix inline shape WOULD fail the guard above" {
  # Proves the guard discriminates rather than passing vacuously: the old construction, checked by
  # the same predicate, must trip it.
  local old='    CMD="cd $(printf %q "$WT") && { $WT_INSTALL ; } ; ${PREFIX}${LAUNCHER}${ARGS}"'
  grep -q 'CMD=.*\$WT_INSTALL' <<<"$old" || false
}

@test "the chain still covers every package manager (the file, not the typed line)" {
  # Moving it to a file must not have silently dropped support.
  local mgr
  for mgr in pnpm bun npm yarn uv poetry pipenv go cargo; do
    grep -q "$mgr" <<<"$COLD" || { echo "chain lost $mgr"; false; }
  done
}

@test "the recycle path types no correctable word either" {
  # --recycle types `cd <cwd> && <launcher> ...` into the plain shell; assert no manager leaked in.
  local rec
  rec="$(grep -n 'cd .* && .*LAUNCHER' "$HF" | grep -v WT_DEPS || true)"
  local mgr
  for mgr in go uv poetry pipenv cargo; do
    if grep -qE "(^|[^-[:alnum:]_])${mgr}([^-[:alnum:]_]|$)" <<<"$rec"; then
      echo "a typed launch line names '$mgr': $rec"
      false
    fi
  done
}
