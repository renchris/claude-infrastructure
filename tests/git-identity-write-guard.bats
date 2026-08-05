#!/usr/bin/env bats
# git-identity-write-guard — the AGENT-TYPED half of the 2026-08-05 git-identity leak.
#
# The corpus half is a tree-wide source lint. Reso has NO leaky source at all: it was poisoned by
# an agent hand-typing `git -C "$SOMEDIR" config user.email …` inside an adversarial repro (the
# advV/advJ rows approved into its .claude/settings.local.json:470-476 are the evidence). A source
# lint is structurally blind to a one-liner that never lands in a file — only a PreToolUse hook
# sees it. These tests RED-prove that half.
#
# The load-bearing invariant is the SHAPE rule, not a spelling: the hook reads the command BEFORE
# expansion, so `-C "$VAR"` is statically undecidable — it is empty exactly when the accident
# happens and never when you test it. A guard matching only a literal `-C ""` would pass every
# real occurrence (memory: denylist-enumerates-spellings-not-the-class), so test 2 — the actual
# reso shape — is the one that matters most.
#
# Red-proof: every DENY test below exits 0 with no output against the pre-fix hook (the guard did
# not exist), and the reach control catches the one way the whole file could pass VACUOUSLY —
# validate-bash.sh fails OPEN when jq is missing, which would turn every ALLOW test green while
# proving nothing.

setup() {
  # HERMETICITY (run_gate's blocking ratchet) — and load-bearing here, not ceremony: the hook
  # appends to ~/.claude/logs/bash-commands.log on its success path.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HOOK="$REPO/hooks/validate-bash.sh"
}

# run_hook <command-string> — feed one Bash tool call through the hook.
# jq builds the payload: every command under test contains quotes and `$`, and hand-rolled JSON
# would corrupt exactly the tokens the guard is reading.
run_hook() {
  local payload
  payload="$(jq -nc --arg c "$1" '{tool_name:"Bash",session_id:"t",tool_input:{command:$c}}')"
  run "$HOOK" <<<"$payload"
}

denied()  { [ "$status" -eq 0 ] && [[ "$output" == *'"permissionDecision": "deny"'* ]] && [[ "$output" == *"identity write"* ]]; }
allowed() { [ "$status" -eq 0 ] && [[ "$output" != *"identity write"* ]]; }

# ── Reach control — the harness must be able to FAIL ────────────────────────────────────────
# validate-bash.sh fails OPEN (exit 0, no output) when jq is unavailable or the payload does not
# parse. In that state every `allowed()` assertion below is vacuously true. This pins a deny that
# predates this change, so a silently-abstaining hook takes the file red instead of green.
@test "control: the hook is REACHED and can still deny (pre-existing --no-verify rule)" {
  run_hook 'git commit --no-verify -m x'
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision": "deny"'* ]] || false
  [[ "$output" == *"no-verify"* ]]
}

# ── DENY: every way the write collapses into the CURRENT repo ───────────────────────────────

@test "literal empty -C is denied (git -C \"\" is a documented no-op, verified git 2.54.0)" {
  run_hook 'git -C "" config user.email t@t.t'
  denied
}

@test "THE RESO SHAPE: bare variable -C is denied — undecidable now, empty when it matters" {
  run_hook 'git -C "$SOMEDIR" config user.email t@t.t'
  denied
}

@test "unbraced bare variable -C is denied (same class, different spelling)" {
  run_hook 'git -C $REPO config user.name t'
  denied
}

@test "positional \$1 -C is denied (the helper-called-with-no-argument shape)" {
  run_hook 'git -C "$1" config user.email t@t'
  denied
}

@test "no -C at all is denied — the write lands in whatever repo is cwd" {
  run_hook 'git config user.email t@t.t'
  denied
}

@test "--local does not name a target and is denied" {
  run_hook 'git config --local user.name t'
  denied
}

@test "unchecked command substitution as -C is denied (mktemp -d can fail to empty)" {
  run_hook 'git -C "$(mktemp -d)" config user.name t'
  denied
}

@test "cd with a bare variable is denied — 'cd \"\"' EXITS 0 and stays put, so && never fires" {
  run_hook 'cd "$D" && git config user.email t@t.t'
  denied
}

@test "a sibling clause does not exonerate the write (compound-command escape hatch)" {
  run_hook 'echo setting up; git config user.email t@t.t'
  denied
}

# ── ALLOW: shapes that cannot collapse — over-denial on the hottest path is its own defect ──

@test "literal path -C passes" {
  run_hook 'git -C /tmp/my-fixture config user.email t@t.t'
  allowed
}

@test "expansion WITH a literal segment passes (doc rule 2: \"\$tmp/repo\" is safe)" {
  run_hook 'git -C "$tmp/repo" config user.email t@t.t'
  allowed
}

@test "\${dir:?} passes — it aborts on empty instead of expanding to it" {
  run_hook 'git -C "${dir:?repo path required}" config user.email t@t.t'
  allowed
}

@test "literal relative path passes (a literal cannot expand to nothing)" {
  run_hook 'git -C repo config user.name t'
  allowed
}

@test "governing cd to a literal path passes" {
  run_hook 'cd /tmp/my-fixture && git config user.email t@t.t'
  allowed
}

@test "THE RECOMMENDED FORM passes: transient -c cannot persist at all" {
  run_hook 'git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base'
  allowed
}

@test "reads are never blocked (--get)" {
  run_hook 'git config --get user.email'
  allowed
}

@test "a bare key with no value is a READ, not a write" {
  run_hook 'git config user.email'
  allowed
}

@test "--list is never blocked" {
  run_hook 'git config --list'
  allowed
}

@test "THE GUARD DOES NOT DENY ITS OWN FIX: --unset-all is the repair this incident needed" {
  run_hook 'git config --unset-all user.email'
  allowed
}

@test "--global names its own target — no cwd to collapse into" {
  run_hook 'git config --global user.email me@example.com'
  allowed
}

@test "--file names its own target" {
  run_hook 'git config --file /tmp/x/.gitconfig user.name t'
  allowed
}

@test "an unrelated git command is untouched" {
  run_hook 'git -C "$REPO" status --short'
  allowed
}
