#!/usr/bin/env bats
# lr-handoff.sh — the GENERATED LAUNCHER is source, not data.
#
# Contract under test (register-criteria-FIRST, house 43de6d6 discipline). Origin: deferred
# finding `deferred_lr_handoff_branch_name` (codex-security scan 38eec335, 2026-07-29), whose
# reachability this suite settles empirically rather than by argument.
#
# lr-handoff.sh mints a launcher with mktemp (lr-handoff.sh:173) and writes it from an
# interpolating heredoc, and that file is then EXECUTED — `write text "exec /bin/bash
# $LAUNCHER"` in both osascript branches, and by hand on the documented manual-fallback path.
# So every interpolated field is SOURCE.
#
# `git check-ref-format` ACCEPTS  $ ` ( ) ; | & ' "  in a branch name; it refuses only control
# characters, space, ~, ^ and : — and ${IFS} substitutes for the space. A branch this session
# did not NAME therefore carries a payload straight into the launcher.
#
#   1. NO EXECUTION: a branch name carrying a command substitution must not execute when the
#      generated launcher is run. This is the regression test for the finding itself.
#   2. POSITIVE CONTROL: the pre-fix heredoc form, run through this same harness, MUST create
#      the marker. Without it a green (1) is unfalsifiable — it would also pass if the payload
#      were inert or the launcher never ran.
#   3. VALUE INTEGRITY: the branch must reach the consumer WHOLE. The old
#      `${BRANCH:+--branch "$BRANCH"}` had the writing shell strip the inner quotes, so the
#      substitution was consumed and a truncated `--branch wip` reached argv — the exploit was
#      silent, and a merely-unusual branch name was silently corrupted.
#   4. ARGV STRUCTURE: %q must not weld arguments together. --prompt's value stays ONE argument
#      despite its spaces, and the fable path stays FOUR (--model X --effort high).
#   5. OMISSION: an empty branch emits no --branch flag at all.
#
# Hermeticity notes (house traps, learned the hard way):
#   * $LR is $HOME-based (lr-handoff.sh:41), so overriding HOME is the stub seam for
#     lr-audit.py / lr-preseed-env.sh / lr-fire-resume.sh. No source edit needed.
#   * `cursor` IS on PATH on this machine and lr-handoff.sh:250 invokes it on the --print-only
#     path — unshimmed, every test run opens the real editor. The stub bin dir is prepended.
#   * No background jobs in any fixture: a `&` in a bats fixture prints a fabricated `not ok`
#     beside the passing `ok`, and the land gate greps for `not ok`.
#   * The payload writes a RELATIVE marker and each launcher is run from a known cwd, so no
#     absolute path has to survive git's ref-name grammar.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HANDOFF="$REPO/scripts/limit-recover/lr-handoff.sh"

  # Fixture $HOME itself, not merely a $H we remember to pass through: lr-handoff derives
  # $LR, the account config dirs and the bundle root from $HOME, so anything reached without
  # an explicit `env HOME=` would otherwise run against the live ~/.
  export HOME="$BATS_TEST_TMPDIR/home"
  export STUBBIN="$BATS_TEST_TMPDIR/bin"
  # mktemp mints the launcher under $TMPDIR (lrh_tmpdir), so point it at the test dir
  export TMPDIR="$BATS_TEST_TMPDIR/tmp"
  mkdir -p "$TMPDIR"
  mkdir -p "$HOME/.claude/scripts/limit-recover" "$HOME/.claude/projects" \
           "$HOME/.claude-secondary/projects" "$STUBBIN"

  # --- stubs reached via $LR ($HOME/.claude/scripts/limit-recover) -----------
  cat > "$HOME/.claude/scripts/limit-recover/lr-audit.py" <<'PY'
import sys, json, os
a = sys.argv
out = a[a.index('--json') + 1]
os.makedirs(os.path.dirname(out), exist_ok=True)
json.dump({"session_dir": "/nonexistent",
           "transcript_sha256": "deadbeef",
           "counts": {"gaps": 0}}, open(out, "w"))
PY
  printf '#!/bin/bash\nexit 0\n' > "$HOME/.claude/scripts/limit-recover/lr-preseed-env.sh"
  # consumer stub: prints argv with unambiguous boundaries (bare $* would render
  # one argument and three identically, hiding a welding bug)
  cat > "$HOME/.claude/scripts/limit-recover/lr-fire-resume.sh" <<'SH'
#!/bin/bash
echo "argc=$#"
i=0; for a in "$@"; do i=$((i+1)); printf 'argv[%d]=<%s>\n' "$i" "$a"; done
SH
  chmod +x "$HOME/.claude/scripts/limit-recover/"*.sh

  # cursor shim — lr-handoff.sh:219 would otherwise launch the real editor
  printf '#!/bin/bash\nexit 0\n' > "$STUBBIN/cursor"
  chmod +x "$STUBBIN/cursor"
}

teardown() {
  [ -n "${LAUNCHER:-}" ] && rm -f "$LAUNCHER"
  return 0
}

# Put a git repo at $1 onto branch $2 (created, so the name is whatever we say).
mkrepo() {
  # `git -C ""` is a NO-OP, not an error — an empty $1 would write this identity into the cwd repo.
  : "${1:?mkrepo: repo path required}"
  git init -q "$1"
  git -C "${1:?repo path required}" config user.email t@t.t
  git -C "${1:?repo path required}" config user.name t
  git -C "$1" commit -q --allow-empty -m init
  git -C "$1" switch -q -C "$2"
}

# The launcher path is MINTED by mktemp, so it cannot be predicted from the sid — read it
# back from the script's own contract line on stderr. Call this from the test body, never
# through `run`: `run` executes in a subshell, so an assignment made inside it is lost and the
# later `/bin/bash "$LAUNCHER"` would silently degrade to a bare `/bin/bash` (rc 127).
launcher_from_output() {
  printf '%s\n' "$output" \
    | sed -n 's/^lr-handoff: launch script ready (not fired): //p' | tail -1
}

# Run the real lr-handoff.sh --print-only for sid $1, cwd $2, extra args $3...
gen() {
  local sid="$1" cwd="$2"; shift 2
  env PATH="$STUBBIN:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      "$HANDOFF" --sid "$sid" --target next2 --cwd "$cwd" \
      --no-transplant --print-only "$@"
}

# The hostile branch name. No space is needed: ${IFS} supplies one, and the
# marker is relative so the path never has to satisfy git's ref grammar.
EVIL_BRANCH='wip$(touch${IFS}pwned-marker)'

@test "1. a command-substitution branch name does not execute when the launcher runs" {
  mkrepo "$BATS_TEST_TMPDIR/repo" "$EVIL_BRANCH"
  run gen "lrhq0001-0000-0000-0000-000000000001" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ]
  [ -f "$LAUNCHER" ]

  cd "$BATS_TEST_TMPDIR"
  rm -f pwned-marker
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/pwned-marker" ]
}

@test "2. positive control: the pre-fix heredoc form DOES execute the same payload" {
  # Guards test 1 from passing vacuously. This is the OLD generator, verbatim:
  # an interpolating heredoc with ${BRANCH:+--branch "$BRANCH"}.
  mkrepo "$BATS_TEST_TMPDIR/repo" "$EVIL_BRANCH"
  local BRANCH FIRE_MODEL
  BRANCH="$(git -C "$BATS_TEST_TMPDIR/repo" branch --show-current)"
  [ -n "$BRANCH" ]
  FIRE_MODEL=""
  LAUNCHER="$BATS_TEST_TMPDIR/old-form.sh"
  cat > "$LAUNCHER" <<EOF
#!/bin/bash
echo "old-form" \\
  ${BRANCH:+--branch "$BRANCH"} $FIRE_MODEL
EOF
  chmod +x "$LAUNCHER"

  cd "$BATS_TEST_TMPDIR"
  rm -f pwned-marker
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  # The marker MUST appear — proving payload, harness and execution all work,
  # so test 1's absence is a real verdict rather than a broken probe.
  [ -e "$BATS_TEST_TMPDIR/pwned-marker" ]
}

@test "3. the branch reaches the consumer whole, not truncated at the substitution" {
  mkrepo "$BATS_TEST_TMPDIR/repo" "$EVIL_BRANCH"
  run gen "lrhq0003-0000-0000-0000-000000000003" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ]

  cd "$BATS_TEST_TMPDIR"
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  # whole value, not the pre-fix `--branch wip`
  [[ "$output" == *"argv[5]=<${EVIL_BRANCH}>"* ]]
}

@test "4. %q does not weld argv: --prompt stays one argument, fable stays four" {
  mkrepo "$BATS_TEST_TMPDIR/repo" "feat/ordinary"
  run gen "lrhq0004-0000-0000-0000-000000000004" "$BATS_TEST_TMPDIR/repo" --model fable
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ]

  cd "$BATS_TEST_TMPDIR"
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"argc=11"* ]] || false
  [[ "$output" == *"argv[4]=<--branch>"* ]] || false
  [[ "$output" == *"argv[5]=<feat/ordinary>"* ]] || false
  [[ "$output" == *"argv[6]=<--model>"* ]] || false
  [[ "$output" == *"argv[7]=<claude-fable-5>"* ]] || false
  [[ "$output" == *"argv[8]=<--effort>"* ]] || false
  [[ "$output" == *"argv[9]=<high>"* ]] || false
  # the ingest prompt has spaces and must survive as ONE element
  [[ "$output" == *"argv[11]=</limit-recover ingest "* ]]
}

@test "5. a non-git cwd yields no --branch flag at all" {
  mkdir -p "$BATS_TEST_TMPDIR/plain"
  run gen "lrhq0005-0000-0000-0000-000000000005" "$BATS_TEST_TMPDIR/plain"
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ]

  cd "$BATS_TEST_TMPDIR"
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"argc=5"* ]] || false
  [[ "$output" != *"--branch"* ]]
}

@test "6. quote and backtick metacharacters in a branch name are also neutralised" {
  # $(...) is not the only accepted spelling — a denylist that knows one is not a fix.
  mkrepo "$BATS_TEST_TMPDIR/repo" 'wip`touch${IFS}tick-marker`'
  run gen "lrhq0006-0000-0000-0000-000000000006" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ]

  cd "$BATS_TEST_TMPDIR"
  rm -f tick-marker
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  [ ! -e "$BATS_TEST_TMPDIR/tick-marker" ]
  [[ "$output" == *'argv[5]=<wip`touch${IFS}tick-marker`>'* ]]
}
