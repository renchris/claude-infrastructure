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

@test "RED-PROOF: two cold fires sharing one TMPDIR mint DISTINCT deps files" {
  # INCIDENT (2026-07-29, ground-up campaign wave 1): BSD mktemp substitutes ONLY a trailing
  # XXXXXX. The template `handoff-deps-XXXXXX.sh` therefore created a file named LITERALLY that,
  # so fire #1 on a box succeeded and fire #2 died `mkstemp failed ... File exists` — the whole
  # remaining campaign blocked. Invisible to any single-fire test, which is why this one fires
  # TWICE. It executes the real source lines, so it goes RED against the pre-fix tree.
  export TMPDIR="$BATS_TEST_TMPDIR/tmp/"; mkdir -p "$TMPDIR"
  local mint first second
  mint="$(sed -n '/^    WT_DEPS="\$(mktemp/,/^    chmod +x "\$WT_DEPS"/p' "$HF")"
  [ -n "$mint" ] || { echo "could not extract the deps-file minting block"; false; }
  local WT_INSTALL='echo hermetic-stub'
  eval "$mint"; first="$WT_DEPS"
  eval "$mint"; second="$WT_DEPS"
  [ -f "$first" ] || { echo "first fire minted no file"; false; }
  [ -f "$second" ] || { echo "second fire minted no file (the collision bug)"; false; }
  [ "$first" != "$second" ] || { echo "both fires minted the SAME path: $first"; false; }
}

@test "POSITIVE CONTROL: on this host the pre-fix suffixed template really does collide" {
  # Proves the guard above discriminates rather than passing vacuously — the OLD template, run
  # through the same two-call predicate, must trip on this machine's mktemp.
  export TMPDIR="$BATS_TEST_TMPDIR/tmp/"; mkdir -p "$TMPDIR"
  local a
  a="$(mktemp "${TMPDIR}pc-XXXXXX.sh" 2>/dev/null || true)"
  if [ "$a" = "${TMPDIR}pc-XXXXXX.sh" ]; then
    run mktemp "${TMPDIR}pc-XXXXXX.sh"
    [ "$status" -ne 0 ] || { echo "expected the pre-fix template to collide; it succeeded"; false; }
  else
    skip "this host's mktemp is suffix-aware (GNU); the pre-fix shape cannot collide here"
  fi
}

@test "the deps file keeps its .sh suffix (operators read this path off a parked pane)" {
  export TMPDIR="$BATS_TEST_TMPDIR/tmp/"; mkdir -p "$TMPDIR"
  local mint
  mint="$(sed -n '/^    WT_DEPS="\$(mktemp/,/^    chmod +x "\$WT_DEPS"/p' "$HF")"
  # ShellCheck cannot see through `eval "$mint"` — the extracted source writes "$WT_INSTALL" into
  # the deps file, so the variable IS consumed. (This prose line deliberately does NOT begin with
  # the tool's name: a comment whose first word is that name parses as a malformed DIRECTIVE and
  # aborts analysis of the whole file.)
  # shellcheck disable=SC2034
  local WT_INSTALL='echo hermetic-stub'
  eval "$mint"
  [ "${WT_DEPS%.sh}" != "$WT_DEPS" ] || { echo "deps file lost its .sh suffix: $WT_DEPS"; false; }
  [ -x "$WT_DEPS" ] || { echo "deps file is not executable: $WT_DEPS"; false; }
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

# ── item 7146aab37a9a: the LAUNCHER is the word the 2026-07-29 fix left exposed ─────────────────
# Removing the package managers from the typed line closed the `go`→`god` wedge but not the CLASS.
# `${LAUNCHER}` is still a bare word in command position in every typed shape, and it is the one
# token that can NEVER be validated before typing: the launchers are zsh aliases/functions from the
# operator's INTERACTIVE rc, so `command -v` from this script sees nothing (`zsh -c 'whence -w
# claude-next4'` → none). They are also mutual near-misses inside CORRECT's own dictionary —
# measured live: `claude-nex` → `correct 'claude-nex' to 'claude-next' [nyae]?`. And `--launcher`
# is unvalidated (:2291), unlike `--account`, so a typo or a 5th account without a matching alias
# types a word that parks the pane instead of failing cleanly.

@test "EVERY typed launch shape shields the launcher with 'nocorrect'" {
  # The invariant is per-SHAPE, not "the file mentions nocorrect somewhere": a new fire mode that
  # composes its own CMD would otherwise inherit the wedge silently.
  local shapes n=0 line
  shapes="$(grep -n 'CMD="' "$HF" | grep 'LAUNCHER' || true)"
  [ -n "$shapes" ] || { echo "found no typed CMD shapes — the grep drifted"; false; }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    n=$((n + 1))
    grep -q '${NC}${PREFIX}${LAUNCHER}' <<<"$line" \
      || { echo "unshielded typed shape: $line"; false; }
  done <<<"$shapes"
  # All six known shapes: 2x --recycle, cold + existing --worktree, --cwd, bare.
  [ "$n" -eq 6 ] || { echo "expected 6 typed launch shapes, found $n — a shape was added or lost"; false; }
}

@test "NC is exactly the zsh reserved word, with its separating space" {
  # A bare `nocorrect` with no trailing space would concatenate into `nocorrectclaude-next4`.
  grep -q '^NC="nocorrect "$' "$HF" || { echo "NC is not 'nocorrect ' — check the definition"; false; }
}

@test "POSITIVE CONTROL: the pre-fix unshielded shape WOULD fail the guard above" {
  # Proves the guard discriminates rather than passing vacuously — the exact pre-fix construction,
  # checked by the same predicate, must trip it.
  local old='    CMD="cd $(printf %q "$WT") && ${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""'
  ! grep -q '${NC}${PREFIX}${LAUNCHER}' <<<"$old" || false
}

@test "the shield is NOT applied by quoting (which would kill alias expansion)" {
  # Quoting the launcher also suppresses correction, but suppresses ALIAS EXPANSION with it — and
  # claude-next2/3/4 and claude-fable2/3/4 are aliases, so a quoted form simply would not resolve.
  ! grep -qE "CMD=.*'\\\$\{LAUNCHER\}'" "$HF" || false
  ! grep -qE 'CMD=.*\\"\$\{LAUNCHER\}\\"' "$HF" || false
}
