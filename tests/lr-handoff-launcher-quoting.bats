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
  # See the note in tests/lr-handoff-close-source.bats: the lr-fire-resume stub here is a bare argv
  # printer with no parser arms, and the live-parser preflight is not this suite's subject.
  export LRH_LIVE_PARSER_CHECK=off

  # HERMETICITY (land ratchet): this suite drives fires, so it must not read live machine load,
  # and the three seams that do NOT resolve under $HOME must resolve inside the test dir. An ABSENT
  # path is the right default — these sensors fail open on one. Cases may still override per call.
  export CC_ADMIT_GATE=off
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-"

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
  git -C "$1" config user.email t@t.t
  git -C "$1" config user.name t
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
  [[ "$output" == *"argv[7]=<claude-fable-5-1>"* ]] || false
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

# --- 7/8: EFFORT REACHES THE SUCCESSOR ---------------------------------------------------------
# A handoff CONTINUES one session on another account, so the reasoning tier is part of what has
# to survive the move. `--model fable` used to hardcode `--effort high`, silently demoting a
# Fable-5-at-MAX session — the kind of loss nothing notices, because the successor's statusline
# still reads "Fable 5". Test 4 above pins the DEFAULT (high) and these two pin the OVERRIDE, one
# per emitting site: the flag is set on two different branches and a test of only the fable one
# would call the opus branch covered while it stayed inert.

@test "7. --effort overrides the fable default rather than appending a second flag" {
  mkrepo "$BATS_TEST_TMPDIR/repo" "feat/ordinary"
  run gen "lrhq0007-0000-0000-0000-000000000007" "$BATS_TEST_TMPDIR/repo" --model fable --effort max
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ]

  cd "$BATS_TEST_TMPDIR"
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  # argc unchanged from test 4: an override, not an extra pair. Two --effort flags would be
  # last-wins in the binary and would hide a wrong default forever.
  [[ "$output" == *"argc=11"* ]] || false
  [[ "$output" == *"argv[8]=<--effort>"* ]] || false
  [[ "$output" == *"argv[9]=<max>"* ]] || false
  [[ "$output" != *"<high>"* ]]
}

@test "8. --effort also reaches the opus path, which passes no --model at all" {
  mkrepo "$BATS_TEST_TMPDIR/repo" "feat/ordinary"
  run gen "lrhq0008-0000-0000-0000-000000000008" "$BATS_TEST_TMPDIR/repo" --effort xhigh
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ]

  cd "$BATS_TEST_TMPDIR"
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"argc=9"* ]] || false
  [[ "$output" != *"--model"* ]] || false
  [[ "$output" == *"argv[6]=<--effort>"* ]] || false
  [[ "$output" == *"argv[7]=<xhigh>"* ]]
}

@test "9. an unrecognised --effort is refused before anything is transplanted" {
  # The launcher is %q-quoted, so this is a liveness guard, not a quoting one: an effort the
  # binary rejects would surface as a dead pane AFTER the transcript had already moved accounts.
  mkrepo "$BATS_TEST_TMPDIR/repo" "feat/ordinary"
  run gen "lrhq0009-0000-0000-0000-000000000009" "$BATS_TEST_TMPDIR/repo" --effort maximum
  [ "$status" -eq 2 ]
  [[ "$output" == *"--effort must be"* ]]
}

# --- 10/11/12: THE MODEL REACHES THE SUCCESSOR, AND ITS DEFAULT IS NOT A CONSTANT --------------
# Same family as 7/8, one level worse. `--effort` demoted the reasoning tier; the opus path demoted
# the MODEL GENERATION: lr-fire-resume defaulted `model="claude-opus-4-8"` and nothing on the opus
# path ever overrode it (lr-handoff appended --model only on the fable branch, and the account map
# sets one only for a fable account), so every non-fable transplant resumed on a previous-generation
# model while the SSOT had said `opus_latest: claude-opus-5` since 2026-07-25. Invisible, again:
# nothing in the resumed pane announces which model it came up on.
#
# The cure is a SINGLE COPY of that perishable fact, so the assertions split accordingly: the opus
# path must emit NO model id (test 11 — the SSOT decides, tests/lr-fire-resume-model-ssot.bats owns
# that half), and a caller pinning a generation must still be able to (test 10).

@test "10. an explicit claude-* model id is passed through verbatim" {
  mkrepo "$BATS_TEST_TMPDIR/repo" "feat/ordinary"
  run gen "lrhq0010-0000-0000-0000-000000000010" "$BATS_TEST_TMPDIR/repo" --model claude-opus-5
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ]

  cd "$BATS_TEST_TMPDIR"
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"argv[6]=<--model>"* ]] || false
  [[ "$output" == *"argv[7]=<claude-opus-5>"* ]] || false
  # and it did NOT pick up the fable branch's forced effort
  [[ "$output" != *"<high>"* ]]
}

@test "11. --model opus emits NO model id — the SSOT is the only copy" {
  # The load-bearing NEGATIVE. Naming an id here would put a second copy of a perishable fact in the
  # tree, and the first copy is exactly what pinned every non-fable transplant to Opus 4.8.
  mkrepo "$BATS_TEST_TMPDIR/repo" "feat/ordinary"
  run gen "lrhq0011-0000-0000-0000-000000000011" "$BATS_TEST_TMPDIR/repo" --model opus
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ]

  cd "$BATS_TEST_TMPDIR"
  run /bin/bash "$LAUNCHER"
  [ "$status" -eq 0 ]
  [[ "$output" != *"--model"* ]] || false
  [[ "$output" != *"claude-opus"* ]]
}

@test "12. a mistyped model LABEL is refused before anything is transplanted" {
  # Same liveness argument as test 9: `opus5` is not a model id, and the binary's refusal would land
  # in a freshly spawned pane AFTER the transcript had already moved accounts. It does not enumerate
  # valid ids — that list is perishable, and hardcoding one is the defect this change is about.
  mkrepo "$BATS_TEST_TMPDIR/repo" "feat/ordinary"
  run gen "lrhq0012-0000-0000-0000-000000000012" "$BATS_TEST_TMPDIR/repo" --model opus5
  [ "$status" -eq 2 ]
  [[ "$output" == *"--model must be"* ]]
}

# ── the LIVE-PARSER preflight ────────────────────────────────────────────────────────────────────
# Measured 2026-09-09 on an E2E of --in-place: the driver ran from a worktree whose lr-fire-resume.sh
# parses --permission-mode and minted a launcher that execs $HOME/.claude/... — the LIVE symlink into
# a shared checkout 25 commits behind trunk. The live copy printed `unknown arg --permission-mode`
# and exited; the recycle watcher then waited 90s for a claude process that could never appear, and
# the run ended with the pane a tombstoned husk whose session had ALREADY been transplanted. Code
# that is correct and landed but not live (the 🚀 rung) produced the exact outcome this wave exists
# to prevent. These two cases pin the refusal and its POSITION — before the first irreversible step.
parser_stub() { # $@ = the flags the fake live parser accepts
  { echo '#!/bin/bash'; echo 'case "$1" in'
    for f in "$@"; do echo "  $f) ;;"; done
    echo 'esac'
    # W2: the preflight now also asserts that the LIVE pair can REDEEM this recovery's admission
    # token — a live layer that predates the token would ignore the variable and re-gate the
    # relaunch inside the pane. This stub is the "live layer is current" fixture, so it carries
    # both markers; the case below that REFUSES on the token overwrites the library afterwards.
    echo '# LR_ADMIT_TOKEN is read by the real script'
  } > "$HOME/.claude/scripts/limit-recover/lr-fire-resume.sh"
  chmod +x "$HOME/.claude/scripts/limit-recover/lr-fire-resume.sh"
  mkdir -p "$HOME/.claude/scripts/lib"
  printf '#!/bin/bash\n_cc_admit_token_redeem() { return 1; }\n' > "$HOME/.claude/scripts/lib/capacity-admit.sh"
}
@test "live-parser preflight: a live lr-fire-resume missing a flag REFUSES, before any transplant" {
  unset LRH_LIVE_PARSER_CHECK
  parser_stub --branch --model --effort --prompt          # no --permission-mode: the measured case
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  run gen "lrhq0013-0000-0000-0000-000000000013" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 5 ]
  [[ "$output" == *"does not parse: --permission-mode"* ]] || { echo "$output"; false; }
  [[ "$output" == *"deploy-live.sh"* ]] || { echo "$output"; false; }
  # POSITION is the property: the transplant must not have run.
  [ "$(grep -c 'transplant ok' <<<"$output")" = 0 ]
}
@test "live-parser preflight CONTROL: a live parser that knows every flag does not refuse" {
  unset LRH_LIVE_PARSER_CHECK
  parser_stub --branch --model --effort --permission-mode --prompt
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  run gen "lrhq0014-0000-0000-0000-000000000014" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -ne 5 ]
  [ "$(grep -c 'does not parse' <<<"$output")" = 0 ]
}

# ══ W2 — EVERY REFUSABLE READ BEFORE THE TRANSPLANT, AND A LAUNCHER THAT LEAKS NOTHING ═════════
# THE ORDERING DEFECT (U02; D1-FT R5, D2-safety R2, D3-safety R3). `--in-place` moved the transcript
# FIRST and discovered only afterwards that the recycle could not proceed: an operator draft in the
# composer (the recycle's own gate, 180 s later), a pane not holding a claude, a session that died
# on a network error rather than a limit, a teammate. Each of those is readable in ~1 s, and after
# the transplant the source is a tombstoned husk whose only exit is a manual relaunch.
#
# RED AT 6a6f9a129, all four: lrh_precheck does not exist, so every one of them TRANSPLANTS —
# `[ ! -e "$MOVED_LOCK" ]` fails with the lock and the tombstone both on disk.
#
# The fixture's discriminator is the LOCK and the TOMBSTONE, not a log line: they are what the real
# lr-transplant.sh writes and what makes the step irreversible.

lrh_inplace_setup() { # → stubs for the irreversible step, the registry row and the fire actuator
  MOVED_LOCK="$BATS_TEST_TMPDIR/moved.lock"
  MOVED_TOMB="$BATS_TEST_TMPDIR/moved.HANDOFF.json"
  cat > "$HOME/.claude/scripts/limit-recover/lr-transplant.sh" <<SH
#!/bin/bash
# stands in for the ONE irreversible step: it writes the split-brain lock and the tombstone
printf '{"sid":"x"}\n' > "$MOVED_LOCK"
printf '{"handed_off_to":"x"}\n' > "$MOVED_TOMB"
printf '{"target_transcript":"/x/y.jsonl"}\n'
SH
  chmod +x "$HOME/.claude/scripts/limit-recover/lr-transplant.sh"
  export CC_REGISTRY_DIR="$BATS_TEST_TMPDIR/reg"; mkdir -p "$CC_REGISTRY_DIR"
  export CC_PROJECTS_DIRS="$HOME/.claude/projects"
  mkdir -p "$HOME/.claude/projects/-x-y"
  # the capacity gate is pinned OFF: this suite's subject is ORDERING, and a live probe would make
  # every case here depend on the desk's mood (test-hermeticity RULE 4).
  export CC_ADMIT_GATE=off
  export CC_ADMIT_STATE_DIR="$BATS_TEST_TMPDIR/admit"
  export CC_ADMIT_IDL="$BATS_TEST_TMPDIR/idl.jsonl"
}
lrh_row() { # $1=sid — the registry row that binds pane 616 to it
  printf '{"paneUUID":"616","session_id":"%s","pid":%d,"cwd":"%s"}\n' "$1" "$$" "$BATS_TEST_TMPDIR" \
    > "$CC_REGISTRY_DIR/616.json"
}
lrh_tx() { # $1=sid $2=limit|network|teammate — the SOURCE transcript the precheck reads
  local f="$HOME/.claude/projects/-x-y/$1.jsonl"
  case "$2" in
    limit)   printf '{"type":"assistant","timestamp":"2026-09-19T20:00:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit"}]}}\n' > "$f" ;;
    network) printf '{"type":"assistant","timestamp":"2026-09-19T20:00:00.000Z","error":"server_error","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"API Error: Can'"'"'t reach the API server (ENOTFOUND)"}]}}\n' > "$f" ;;
    teammate) printf '{"type":"user","agentName":"reviewer","message":{"role":"user","content":"x"}}\n' > "$f"
              printf '{"type":"assistant","timestamp":"2026-09-19T20:00:00.000Z","isApiErrorMessage":true,"message":{"role":"assistant","content":[{"type":"text","text":"You'"'"'ve hit your session limit"}]}}\n' >> "$f" ;;
  esac
}
gen_inplace() { # $1=sid $2=cwd [$3=handoff-fire bin] → the REAL --in-place path, stubbed at its edges
  local sid="$1" cwd="$2" hf="${3:-$REPO/scripts/handoff-fire.sh}"
  env PATH="$STUBBIN:$PATH" CLAUDE_CONFIG_DIR="$HOME/.claude" \
      CC_HANDOFF_FIRE_BIN="$hf" CC_FIRE_CAPACITY_GATE=off \
      HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep.json" \
      CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-accounts" CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-" \
      IT2_BIN="$BATS_TEST_TMPDIR/absent-it2" \
      "$HANDOFF" --sid "$sid" --target next2 --cwd "$cwd" --launch --in-place --source-pane 616
}
stub_hf() { # $1=verdict line $2=rc → a handoff-fire whose PROBE answers as told, and records a fire
  cat > "$BATS_TEST_TMPDIR/hf-stub.sh" <<SH
#!/bin/bash
case "\$1" in
  --probe-recycle-preconditions) echo "$1"; exit $2 ;;
  *) echo "STUB FIRE: \$*" >> "$BATS_TEST_TMPDIR/fired.log"; echo "lr-handoff stub recycled" >&2; exit 0 ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/hf-stub.sh"
  printf '%s' "$BATS_TEST_TMPDIR/hf-stub.sh"
}

@test "W2: a session that died on a NETWORK error is REFUSED before the transplant" {
  lrh_inplace_setup
  sid="lrhw0001-0000-4000-8000-000000000001"
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  lrh_row "$sid"; lrh_tx "$sid" network
  run gen_inplace "$sid" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 6 ] || { echo "$output"; false; }
  [[ "$output" == *"REFUSED:not-limited"* ]] || { echo "$output"; false; }
  [ ! -e "$MOVED_LOCK" ] || { echo "THE TRANSPLANT RAN — a husk over a session that was never limited"; false; }
  [ ! -e "$MOVED_TOMB" ]
}

@test "W2: a TEAMMATE session is REFUSED before the transplant" {
  lrh_inplace_setup
  sid="lrhw0002-0000-4000-8000-000000000002"
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  lrh_row "$sid"; lrh_tx "$sid" teammate
  run gen_inplace "$sid" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 6 ] || { echo "$output"; false; }
  [[ "$output" == *"REFUSED:teammate"* ]] || { echo "$output"; false; }
  [ ! -e "$MOVED_LOCK" ] || { echo "THE TRANSPLANT RAN — a teammate's pane belongs to its lead"; false; }
  [ ! -e "$MOVED_TOMB" ]
}

# ══ W8 SPLIT THIS CASE IN TWO, and the original assertion had become BOX-DEPENDENT ══════════════
# This was ONE test asserting `REFUSED:pane:` for "a pane whose state cannot be READ". W8
# (LIMIT_RECOVER_100P § 10) gave the remote-pane resolver THREE codes, because absent and wedged
# have opposite remedies:
#     a resolver ANSWERED and lists no such window  → REMOTE-PANE-ABSENT      → REFUSED (terminal)
#     no resolver answered at all                   → RESOLVER-UNAVAILABLE    → HELD    (park/retry)
# After W8 this test's verdict depended on WHETHER A REAL KITTY HAPPENED TO BE RUNNING ON THE BOX:
# with a live control socket the probe said REFUSED and it passed; with none it said HELD and it
# failed. It passed on a developer box and went red on trunk for a reason that was not in the diff
# (docs/lessons/a-suite-red-can-belong-to-the-box-not-the-branch.md). Both arms are now PINNED, and
# the invariant both of them share — an abstention never admits a transplant — is asserted in each.
@test "W2: a pane the resolver ANSWERS about and cannot find is REFUSED before the transplant" {
  # CC_REMOTE_PANE_TERM=off is the deterministic lever for this arm: with W8's resolver disabled the
  # pin falls back to the ancestry verdict, the iTerm2 branch answers "" for a pane it does not
  # enumerate, and an ANSWERED-and-empty query is the ABSENT verdict — a definite negative.
  lrh_inplace_setup
  sid="lrhw0003-0000-4000-8000-000000000003"
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  lrh_row "$sid"; lrh_tx "$sid" limit
  # `run env VAR=x gen_inplace` cannot work: gen_inplace is a bats FUNCTION, and env execs a BINARY.
  # Each bats test body is its own subshell, so an export here leaks nowhere.
  export CC_REMOTE_PANE_TERM=off
  run gen_inplace "$sid" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 6 ] || { echo "$output"; false; }
  [[ "$output" == *"REFUSED:pane:"* ]] || { echo "$output"; false; }
  [ ! -e "$MOVED_LOCK" ] || { echo "THE TRANSPLANT RAN on a pane nobody could read"; false; }
  [ ! -e "$MOVED_TOMB" ]
}

@test "W2: a pane NO resolver can answer about is HELD, not refused — and still transplants nothing" {
  # The arm W8 added. A non-verdict about the RESOLVER says nothing about the pane, so concluding
  # "the pane is gone" would tombstone a live session — the 9-of-9 husk class § 10.1 measured. It
  # must PARK. Determinism: point the socket discovery at an empty directory and the kitty binary at
  # a path that does not exist, so no candidate socket can answer whatever is running on the box.
  lrh_inplace_setup
  sid="lrhw0003-0000-4000-8000-000000000003"
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  lrh_row "$sid"; lrh_tx "$sid" limit
  mkdir -p "$BATS_TEST_TMPDIR/no-sockets"
  export CC_FIRE_KITTY_SOCK_DIR="$BATS_TEST_TMPDIR/no-sockets"
  export CC_KITTY_CONF="$BATS_TEST_TMPDIR/absent-kitty.conf"
  export CC_KITTY_BIN="$BATS_TEST_TMPDIR/absent-kitty"
  export CC_TERM_KITTY_TO=""
  run gen_inplace "$sid" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 6 ] || { echo "$output"; false; }
  [[ "$output" == *"HELD:pane:"* ]] || { echo "$output"; false; }
  [[ "$output" == *"RESOLVER-UNAVAILABLE"* ]] || { echo "$output"; false; }
  # THE INVARIANT, identical in both arms: an abstention must not admit a transplant.
  [ ! -e "$MOVED_LOCK" ] || { echo "THE TRANSPLANT RAN on a HELD verdict"; false; }
  [ ! -e "$MOVED_TOMB" ]
}

@test "W2: a HELD operator draft stops the recovery before the transplant, not 180s after it" {
  # rc 3 is the HOLD channel — nothing is wrong, the recovery simply must not proceed yet. The
  # stub stands in for the composer read itself (that read has its own cases against the real verb);
  # what this pins is that lr-handoff treats a HOLD as pre-transplant, exactly like a REFUSAL.
  lrh_inplace_setup
  sid="lrhw0004-0000-4000-8000-000000000004"
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  lrh_row "$sid"; lrh_tx "$sid" limit
  run gen_inplace "$sid" "$BATS_TEST_TMPDIR/repo" "$(stub_hf 'verdict: HELD:draft' 3)"
  [ "$status" -eq 6 ] || { echo "$output"; false; }
  [[ "$output" == *"HELD:draft"* ]] || { echo "$output"; false; }
  [ ! -e "$MOVED_LOCK" ] || { echo "THE TRANSPLANT RAN over an operator's unsent draft"; false; }
  [ ! -e "$MOVED_TOMB" ]
  [ ! -e "$BATS_TEST_TMPDIR/fired.log" ] || { echo "the recycle was FIRED after a HOLD"; false; }
}

@test "W2 CONTROL: when every precondition passes, the transplant DOES run" {
  # Without this the four cases above pass for a script that refuses everything.
  lrh_inplace_setup
  sid="lrhw0005-0000-4000-8000-000000000005"
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  lrh_row "$sid"; lrh_tx "$sid" limit
  run gen_inplace "$sid" "$BATS_TEST_TMPDIR/repo" "$(stub_hf 'verdict: OK' 0)"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [ -e "$MOVED_LOCK" ] || { echo "the transplant did NOT run on a clean precheck: $output"; false; }
  [ -e "$BATS_TEST_TMPDIR/fired.log" ] || { echo "the recycle was never fired: $output"; false; }
}

@test "W2: the launcher exports exactly the five LR_* variables and ZERO CC_ADMIT_*" {
  # D1-safety R1, FATAL: anything exported here is inherited by the recovered session and every hook
  # it runs for the rest of its life. The mapping to CC_ADMIT_* happens call-scoped inside
  # lr-fire-resume, and the spawn line unsets all of it.
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  run gen "lrhw0006-0000-4000-8000-000000000006" "$BATS_TEST_TMPDIR/repo"
  [ "$status" -eq 0 ]
  LAUNCHER="$(launcher_from_output)"
  [ -n "$LAUNCHER" ] && [ -f "$LAUNCHER" ] || false
  for v in LR_RUN LR_RUN_DIR LR_ADMIT_TOKEN LR_SUBMIT_TOKEN LR_LOAD_TERM; do
    grep -qE "^export $v=" "$LAUNCHER" || { echo "missing export $v:"; cat "$LAUNCHER"; false; }
  done
  # the closed half of the list: no admission variable may reach the session's environment
  ! grep -q 'CC_ADMIT' "$LAUNCHER" || { echo "a CC_ADMIT_* export LEAKS into the recovered session:"; cat "$LAUNCHER"; false; }
  # and the launcher is DURABLE — in the run's bundle, not a temp dir this box wipes at boot
  [[ "$LAUNCHER" == *"/.reso/limit-recover/"* ]] || { echo "launcher is not in the bundle: $LAUNCHER"; false; }
}

@test "W2: a LIVE capacity-admit that cannot redeem a token REFUSES (5) before the transplant" {
  # The launcher carries an admission token; a live layer that predates it would ignore the variable
  # and re-gate the relaunch inside the pane — the split that made four husks. Same position as the
  # parser preflight: before the first irreversible step.
  unset LRH_LIVE_PARSER_CHECK
  lrh_inplace_setup
  parser_stub --branch --model --effort --permission-mode --prompt   # knows every flag…
  # …and then the LIBRARY is rolled back to one with no token support. That single variable is the
  # whole subject: the parser preflight above it passes, and this still refuses.
  # The rollback text must NOT NAME the function it lacks: the check is a grep, and a comment
  # mentioning the symbol satisfies it (this repo's own prose-match hole — a lint convicting, or
  # here ACQUITTING, on its own documentation).
  printf '#!/bin/bash\n# an OLD library, before the admission token existed\n' > "$HOME/.claude/scripts/lib/capacity-admit.sh"
  sid="lrhw0007-0000-4000-8000-000000000007"
  mkrepo "$BATS_TEST_TMPDIR/repo" main
  lrh_row "$sid"; lrh_tx "$sid" limit
  run gen_inplace "$sid" "$BATS_TEST_TMPDIR/repo" "$(stub_hf 'verdict: OK' 0)"
  [ "$status" -eq 5 ] || { echo "$output"; false; }
  [[ "$output" == *"cannot redeem this recovery's token"* ]] || { echo "$output"; false; }
  [ ! -e "$MOVED_LOCK" ]
}
