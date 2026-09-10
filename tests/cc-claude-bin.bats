#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# cc-claude-bin — the ONE resolver for "which claude binary do we actually run".
#
# The defect it replaced: two scripts each hardcoded ~/.claude-183/node_modules/.bin/claude. That
# directory was later advanced IN PLACE to 2.1.215 (name stopped describing content) while the
# interactive launcher moved to ~/.claude-219 — so limit-recover and claude-kimi launched a
# different, older binary than every interactive session, on a build with no claude-opus-5. Neither
# copy of the constant could observe the other (worklist #116).
#
# So the property under test is not "it prints a path". It is:
#   (a) the zshrc `_bin=` pin WINS over any local guess — that is what makes it an SSOT, and
#   (b) a prose mention of an OLD version dir must NOT be mistaken for the pin (the launcher header
#       documents ~/.claude-170 / ~/.claude-161 as rollback notes; a looser grep returns those), and
#   (c) it fails CLOSED — an unresolvable binary must exit non-zero with EMPTY stdout, because a
#       caller that silently substitutes another binary is the original bug wearing a new hat.
#
# Hermetic: every test builds its own $HOME and its own fake zshrc under BATS_TEST_TMPDIR, and
# pins CC_ZSHRC, so nothing reads the operator's real ~/.zshrc or real ~/.claude-NNN dirs.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  C="$REPO/bin/cc-claude-bin"
  export CC_ZSHRC="$BATS_TEST_TMPDIR/zshrc"
  : >"$CC_ZSHRC"
  unset CC_CLAUDE_BIN
  # A real PATH is required: the resolver has a `#!/usr/bin/env bash` shebang, so blanking PATH
  # makes the SCRIPT fail to start (127) rather than exercising its fail-closed path — a control
  # that cannot distinguish those two is vacuous.
  export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

  mkbin() { # <version-dir-name> — plant an executable stub binary in a fake version dir
    local p="$HOME/.$1/node_modules/.bin/claude"
    mkdir -p "$(dirname "$p")"
    printf '#!/usr/bin/env bash\necho stub\n' >"$p"; chmod +x "$p"
    printf '%s\n' "$p"
  }
  pin() { # <version-dir-name> — write a launcher whose _bin= names that dir
    printf 'claude() {\n  local _bin="$HOME/.%s/node_modules/.bin/claude"\n}\n' "$1" >"$CC_ZSHRC"
  }
}

@test "zshrc _bin pin is the SSOT — resolves to the pinned dir" {
  mkbin claude-219 >/dev/null
  pin claude-219
  run "$C"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-219/node_modules/.bin/claude" ]
}

@test "the pin WINS over a newer version dir that is present but not pinned" {
  # This is the whole point: ~/.claude-220 existing must NOT silently become what we launch.
  # Only the launcher moving (the pin) moves us. Without this, staging a parallel install would
  # hijack every consumer — the reverse of the property we want.
  mkbin claude-219 >/dev/null
  mkbin claude-220 >/dev/null
  pin claude-219
  run "$C"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-219/node_modules/.bin/claude" ]
}

@test "a PROSE mention of an older version dir is not mistaken for the pin" {
  # The real launcher's header comments cite ~/.claude-170 and ~/.claude-161 as rollback notes.
  # A grep not anchored on `_bin=` returns whichever appears first — which would resolve us onto
  # a binary nobody runs. Positive control: .claude-170 IS installed here, so a wrong match would
  # succeed rather than error, i.e. this test can actually fail.
  mkbin claude-170 >/dev/null
  mkbin claude-219 >/dev/null
  {
    printf '# Kept ~/.claude-170 as rollback (repoint the two path refs below to roll back).\n'
    printf '#   binary   ~/.claude-170/node_modules/.bin/claude   (old eval track)\n'
    printf 'claude() {\n  local _bin="$HOME/.claude-219/node_modules/.bin/claude"\n}\n'
  } >"$CC_ZSHRC"
  run "$C"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-219/node_modules/.bin/claude" ]
}

@test "CC_CLAUDE_BIN override beats the pin" {
  mkbin claude-219 >/dev/null
  pin claude-219
  export CC_CLAUDE_BIN=/bin/echo
  run "$C"
  [ "$status" -eq 0 ]
  [ "$output" = "/bin/echo" ]
}

@test "CC_CLAUDE_BIN pointing at a non-executable fails closed (never falls through)" {
  # Falling through to the pin here would silently ignore an explicit operator instruction.
  mkbin claude-219 >/dev/null
  pin claude-219
  export CC_CLAUDE_BIN="$BATS_TEST_TMPDIR/nope"
  run "$C"
  [ "$status" -ne 0 ]
  [ -z "$output" ] || [[ "$output" != *"/.claude-219/"* ]]
}

@test "no pin → falls back to the NEWEST version dir, numerically not lexically" {
  # Lexical sort puts .claude-99 above .claude-220; numeric is the only correct order.
  mkbin claude-99  >/dev/null
  mkbin claude-220 >/dev/null
  run "$C"
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.claude-220/node_modules/.bin/claude" ]
}

@test "nothing resolvable → exit non-zero with EMPTY stdout" {
  # Fail-closed is the load-bearing behaviour: callers treat empty STDOUT as fatal. A resolver that
  # printed a plausible-but-wrong path here would recreate the exact bug it replaced.
  #
  # stderr is discarded deliberately. bats merges stderr into $output, and the resolver DOES emit a
  # diagnostic there — so asserting on the merged stream would fail for the wrong reason and read as
  # "the resolver leaked a path" when it leaked nothing. The contract is about stdout alone, so the
  # test must observe stdout alone.
  run bash -c "'$C' 2>/dev/null"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
}

@test "fail-closed still EXPLAINS itself on stderr (a silent refusal is undebuggable)" {
  run bash -c "'$C' 2>&1 1>/dev/null"
  [ -n "$output" ]
  [[ "$output" == *"no claude binary resolved"* ]]
}

@test "--explain names the rung that produced the answer" {
  mkbin claude-219 >/dev/null
  pin claude-219
  run "$C" --explain
  [ "$status" -eq 0 ]
  [[ "$output" == *"zshrc claude() _bin pin"* ]]
}

@test "the LIVE launcher pin resolves — the real ~/.zshrc names a binary that exists" {
  # The one non-hermetic assertion, and the one that would have caught the original drift: if the
  # operator's real launcher pins a path that is not on disk, every consumer is launching something
  # other than what the pin says. SKIP (not fail) where there is no real zshrc, e.g. under CI.
  [ -r "$HOME_REAL_ZSHRC" ] || HOME_REAL_ZSHRC="/Users/$(id -un)/.zshrc"
  [ -r "$HOME_REAL_ZSHRC" ] || skip "no real ~/.zshrc on this machine"
  run env -u CC_CLAUDE_BIN HOME="/Users/$(id -un)" CC_ZSHRC="$HOME_REAL_ZSHRC" "$C" --explain
  [ "$status" -eq 0 ]
  [[ "$output" == *"_bin pin"* ]] || skip "live zshrc carries no claude() _bin pin"
}

@test "RATCHET: no runtime file pins its own versioned claude binary — consumers go through this resolver" {
  # cc-backlog e8b753cac339, measured 2026-09-03: six runtime defaults (cc-offload, cloud-create.sh,
  # capacity-ramp.sh, model-permission-decider.py, both mcp-modal probes) hardcoded
  # ~/.claude-220/... after the launcher moved to 2.1.260. ~/.claude-220 stayed on disk as the
  # rollback, so every `-x` check passed and each site silently kept running the old build — a copy
  # of the pin cannot see the pin move. This case makes the next copy visible at land time.
  # Runtime trees only. Comment lines are exempt (history may name old dirs); tests/ is not scanned
  # (fixtures carry ps rows that name versioned paths, which is data, not a pin).
  git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || skip "not a git checkout — git grep cannot scan"
  # shellcheck disable=SC2016  # the $ is regex text (a literal $HOME in source), not an expansion
  local pat='(\$HOME|~|/Users/[A-Za-z0-9._-]+)/\.claude-[0-9]+/node_modules'
  local code_only='^[^:]+:[0-9]+:[[:space:]]*#'

  # Positive control through the SAME instrument: a planted pin must be found, and a planted
  # comment naming the same path must not. Without this an empty scan below proves nothing.
  local ctl="$BATS_TEST_TMPDIR/ctl"; mkdir -p "$ctl"
  # shellcheck disable=SC2016  # literal source text, planted verbatim
  printf '%s\n' '# history: this used to read $HOME/.claude-220/node_modules/.bin/claude' \
                'BIN="${X:-$HOME/.claude-220/node_modules/.bin/claude}"' >"$ctl/site.sh"
  local ctl_hits
  ctl_hits="$(git -C "$ctl" grep --no-index -n -E "$pat" -- site.sh | grep -vE "$code_only" || true)"
  [ "$(printf '%s\n' "$ctl_hits" | grep -c .)" -eq 1 ]
  [[ "$ctl_hits" == site.sh:2:* ]] || false

  local hits
  hits="$(git -C "$REPO" grep -n -E "$pat" -- bin scripts hooks lib | grep -vE "$code_only" || true)"
  [ -z "$hits" ] || { printf 'versioned claude binary hardcoded — route it through bin/cc-claude-bin:\n%s\n' "$hits" >&2; false; }
}
