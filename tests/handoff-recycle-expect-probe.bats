#!/usr/bin/env bats
# handoff-fire.sh — the pane-state probe that decides whether it is safe to TYPE into a pane.
#
# THE INCIDENT (2026-08-06, memory reference-recycle-probe-types-into-live-composer). `--recycle`
# typed a shell command into a LIVE Claude Code composer and reported it as a success:
#   "→ recycled (no CC was running): typed relaunch into <sid>"
# The pane it typed into was demonstrably running a session at that moment.
#
# TWO defects rode one line — `if ! ps -o comm= -t <pane-tty> | grep -qE 'node|claude'; then TYPE`:
#   1. DETECTION. The standard resume path (bin/lr-fire-resume.sh) launches CC under `expect`, whose
#      spawn() gives the child its OWN pty. claude's controlling tty is therefore not the pane's, so
#      `ps -t <pane-tty>` reports `expect` alone and the grep misses. THE FIXTURES BELOW ARE THAT
#      SHAPE, transcribed from `ps -o pid=,ppid=,pgid=,tpgid=,comm=` on this box on 2026-08-06:
#        ttys009  expect(9568) ← kitty(567)   →  claude(9570) on ttys010
#      Not kitty-specific — kitty is only where it was noticed, because `kitty @ ls` exposes
#      foreground_processes. Any pty-allocating wrapper (script, tmux, a debugger) does the same.
#   2. FAIL-DANGEROUS DEFAULT, which is the one that generalises. "I could not find CC" and "there
#      is definitely a bare shell here" were the SAME branch, and only the second is safe to type
#      into. Fixing (1) alone leaves the class open for the next unmodelled wrapper.
#
# WHAT IS PINNED HERE:
#   A. THE CONTROL. `old_probe` below is the pre-fix predicate, VERBATIM. Every fixture asserts what
#      it answered, so each test states the defect it prevents instead of merely agreeing with the
#      current implementation. Without it, "cc on the expect fixture" would be satisfied by a probe
#      that answers `cc` for everything (memory control-must-replay-the-real-artifact).
#   B. THREE STATES, and `unknown` is NOT `shell`. A probe that only ever refuses is just as broken
#      as one that always types — it converts every legitimate recycle into a manual step — so the
#      affirmative shell verdict has its own positive control, on a fixture carrying the p10k
#      gitstatusd shape that tests/handoff-fire-inject.bats:351 records as the real wedged-pane one.
#   C. THE ACTUATOR, not just the predicate. recycle_fire is extracted and RUN: on `unknown` it must
#      exit non-zero having typed NOTHING, and on `cc` it must reach the watcher-arm path — a
#      correct predicate wired to a branch that types anyway is the same incident.
#
# NOTHING HERE EXECUTES A REAL FIRE. Functions are sed-extracted (the established idiom,
# tests/handoff-fire-pane-proof.bats:30) and `ps` is a fixture-driven stub, so no live pane is read
# and no keystroke reaches a terminal.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`: `[[ ]]` is errexit-EXEMPT in bats and is
# silently DEAD anywhere but a body's last line.

setup() {
  # PIN THE TERMINAL — handoff-fire's primitives branch on KITTY_WINDOW_ID, so an unpinned suite
  # becomes a function of the developer's terminal (the class tests/handoff-fire-kitty.bats names).
  unset KITTY_WINDOW_ID
  export IT2_WRAPPER_NO_KITTY=1
  unset CC_TERM
  export CC_FIRE_CAPACITY_GATE=off
  export CC_FIRE_HEADROOM_GATE=off

  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  HF="$REPO/scripts/handoff-fire.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude/bin"
  # Seams that do NOT resolve under $HOME — an absolute /tmp default and a bare PATH name — so
  # fixturing $HOME alone still lets this suite read the operator's live sweep stamp and EXECUTE
  # their deployed claude-accounts (scripts/test-hermeticity-lint.sh classes 5a/5b). Absent paths
  # are the right values here: every one of these sensors fails open on a missing file.
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"

  hf_bounded() { "$@"; }                       # the timeout(1) wrapper is out of scope when extracted

  # ── the process-table fixture + the `ps` that answers from it ────────────────────────────────
  # TSV: pid<TAB>ppid<TAB>pgid<TAB>tpgid<TAB>tty<TAB>comm<TAB>args
  # One table, every query form the subject makes. A stub that answered only the forms the CURRENT
  # implementation happens to call would silently pass a rewrite that asked a different question.
  PSTABLE="$BATS_TEST_TMPDIR/pstable.tsv"; export PSTABLE
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  cat > "$STUB/ps" <<'FAKEPS'
#!/usr/bin/env bash
# fixture-driven ps. Forms answered:
#   -o pid= -t TTY | -o tpgid= -t TTY | -o comm= -t TTY | -axo pid=,ppid=
#   -o pid=,comm= -g PGID | -o comm= -p PID | -o args= -p PID | -o tty= -p PID
fmt=""; sel=""; val=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o|-axo|-Ao) fmt="$2"; [ "$1" = -o ] || sel="all"; shift 2 ;;
    -t) sel="tty";  val="${2##*/}"; shift 2 ;;
    -g) sel="pgid"; val="$2"; shift 2 ;;
    -p) sel="pid";  val="$2"; shift 2 ;;
    -ax*) fmt="${1#-ax}"; fmt="${fmt#o}"; sel="all"; shift ;;
    *) shift ;;
  esac
done
awk -F'\t' -v fmt="$fmt" -v sel="$sel" -v val="$val" '
  ($1 == "" || $1 ~ /^#/) { next }
  {
    keep = (sel == "all") || (sel == "tty" && $5 == val) \
        || (sel == "pgid" && $3 == val) || (sel == "pid" && $1 == val)
    if (!keep) next
    out = ""
    n = split(fmt, f, ",")
    for (i = 1; i <= n; i++) {
      gsub(/=/, "", f[i])
      v = (f[i] == "pid") ? $1 : (f[i] == "ppid") ? $2 : (f[i] == "pgid") ? $3 \
        : (f[i] == "tpgid") ? $4 : (f[i] == "tty") ? $5 : (f[i] == "comm") ? $6 : $7
      out = (out == "") ? v : out " " v
    }
    print out
  }' "$PSTABLE"
FAKEPS
  chmod +x "$STUB/ps"
  PATH="$STUB:$PATH"

  # THE CONTROL — the pre-fix predicate, verbatim from the shipped line it replaces. It MUST stay
  # a `ps | grep`: rewriting it to pgrep would make it a different predicate and the control would
  # stop reproducing the defect. (pgrep also excludes the caller's own ancestors on macOS — the
  # trap bin/cc-in-kitty's header records.)
  # shellcheck disable=SC2009
  old_probe() { ps -o comm= -t "${1##*/}" 2>/dev/null | grep -qE 'node|claude'; }

  eval "$(sed -n '/^pid_is_cc() {/,/^}/p' "$HF")"
  eval "$(sed -n '/^pane_cc_state() {/,/^}/p' "$HF")"
}

# ── fixtures, each transcribed from a measured pane ──────────────────────────────────────────────

fixture_expect_cc() {   # THE INCIDENT: CC under expect, claude on a NESTED pty (measured ttys009)
  cat > "$PSTABLE" <<'EOF'
567	1	567	-1	??	/Applications/kitty.app/Contents/MacOS/kitty	/Applications/kitty.app/Contents/MacOS/kitty
9568	567	9568	9568	ttys009	expect	expect -c set timeout 240 spawn -noecho env claude --resume 2b3223b7
9570	9568	9570	9570	ttys010	/Users/chrisren/.claude-220/node_modules/.bin/claude	/Users/chrisren/.claude-220/node_modules/.bin/claude --resume 2b3223b7
EOF
}

fixture_idle_shell() {  # A BARE PROMPT with the p10k daemon in a BACKGROUND group (measured ttys017)
  cat > "$PSTABLE" <<'EOF'
38853	37816	38853	38853	ttys017	/bin/zsh	-zsh
38887	1	38885	38853	ttys017	/bin/zsh	/bin/zsh
39507	38887	38885	38853	ttys017	gitstatusd-darwin-arm64	gitstatusd-darwin-arm64
EOF
}

fixture_direct_cc() {   # CC launched WITHOUT a wrapper — the case the old probe did get right
  cat > "$PSTABLE" <<'EOF'
14222	10152	14222	14222	ttys006	bash	bash
14255	14222	14222	14222	ttys006	/Users/chrisren/.claude-220/node_modules/.bin/claude	/Users/chrisren/.claude-220/node_modules/.bin/claude
14257	14255	14222	14222	ttys006	bash	bash
EOF
}

fixture_expect_orphan() {  # expect ALIVE, its claude GONE — the naive "grep the whole argv" trap
  cat > "$PSTABLE" <<'EOF'
9568	567	9568	9568	ttys009	expect	expect -c set timeout 240 spawn -noecho env claude --resume 2b3223b7
EOF
}

fixture_foreground_editor() {  # a shell pane with a NON-shell in the foreground group
  cat > "$PSTABLE" <<'EOF'
38853	1	38853	40000	ttys017	/bin/zsh	-zsh
40000	38853	40000	40000	ttys017	vim	vim notes.md
EOF
}

# ── 1. THE INCIDENT: a CC-under-expect pane must NOT be classified shell-only ────────────────────

@test "expect-wrapped CC: the OLD probe sees no CC — the defect, reproduced" {
  # The control for the whole file. If this ever passes, the fixture has stopped modelling the
  # incident and every assertion below is proving something else.
  fixture_expect_cc
  run old_probe /dev/ttys009
  [ "$status" -ne 0 ]
}

@test "expect-wrapped CC: pane_cc_state says cc — NOT shell, NOT unknown" {
  fixture_expect_cc
  run pane_cc_state /dev/ttys009
  [ "$output" = "cc" ]
}

@test "expect-wrapped CC: the verdict comes from the CHILD, not from expect's argv" {
  # expect's argv contains the word "claude" (it is the spawn line), so a probe "fixed" by grepping
  # the full argv would answer cc here for the wrong reason and would go on matching any agent brief
  # that mentions claude (memory pgrep-f-matches-agent-briefs). With the child gone there is no live
  # CC and no confirmed prompt either — the only correct answer is REFUSE.
  fixture_expect_orphan
  run pane_cc_state /dev/ttys009
  [ "$output" = "unknown" ]
}

# ── 2. the affirmative verdict, so the fix cannot be "always refuse" ─────────────────────────────

@test "bare prompt: pane_cc_state says shell — the positive control" {
  fixture_idle_shell
  run pane_cc_state /dev/ttys017
  [ "$output" = "shell" ]
}

@test "bare prompt: a background gitstatusd does not spoil the shell verdict" {
  # The measured wedged-pane shape (tests/handoff-fire-inject.bats:351). A probe that demanded the
  # whole tty be free of non-shells would refuse on every powerlevel10k prompt — i.e. always.
  fixture_idle_shell
  run grep -c gitstatusd "$PSTABLE"
  [ "$output" = "1" ]
  run pane_cc_state /dev/ttys017
  [ "$output" = "shell" ]
}

@test "unwrapped CC still reads cc — the fix does not regress the case that worked" {
  fixture_direct_cc
  run old_probe /dev/ttys006
  [ "$status" -eq 0 ]
  run pane_cc_state /dev/ttys006
  [ "$output" = "cc" ]
}

# ── 3. unknown is its own state, and it is what an unreadable pane gets ──────────────────────────

@test "a tty with no processes is unknown, never shell" {
  fixture_idle_shell
  run pane_cc_state /dev/ttys999
  [ "$output" = "unknown" ]
}

@test "an empty tty argument is unknown, never shell" {
  fixture_idle_shell
  run pane_cc_state ""
  [ "$output" = "unknown" ]
}

@test "a non-shell in the foreground group is unknown — a prompt is not merely 'no CC'" {
  fixture_foreground_editor
  run old_probe /dev/ttys017
  [ "$status" -ne 0 ]                          # the old probe would have TYPED into vim
  run pane_cc_state /dev/ttys017
  [ "$output" = "unknown" ]
}

# ── 4. THE ACTUATOR — the branch that types, not just the predicate that advises ─────────────────

setup_recycle() {
  # recycle_fire up to its branch needs: mktemp (real), pin_term_verdict_for_watcher, as_tty,
  # it2_type_verified, and — on the cc path — detach/await_armed. Everything that writes is stubbed
  # and LOGGED, so "typed nothing" is an assertion about a file, not about an absence of noise.
  TYPED="$BATS_TEST_TMPDIR/typed.log"; : > "$TYPED"
  export TYPED
  # Read by the sed-extracted recycle_fire, not by this file. `export` rather than four bare
  # assignments + a disable: shellcheck's directive covers only the NEXT command, so on a
  # semicolon-joined line it silences the first and leaves the other three — measured here.
  export SID="PANE-1" CMD="claude --resume abc" LAUNCHER="claude" RECYCLE_MARKER="MK"
  pin_term_verdict_for_watcher() { :; }
  as_tty() { printf '/dev/%s' "$STUB_TTY"; }
  it2_type_verified() { printf '%s\n' "$3" >> "$TYPED"; return 0; }
  cc_sid_for_pane() { printf 'old-sid'; }
  write_teardown_marker() { :; }
  detach() { printf '4242'; }
  await_armed() { return 1; }                  # stop the cc path at its first gate, loudly
  eval "$(sed -n '/^recycle_fire() {/,/^}/p' "$HF")"
}

@test "recycle_fire: an UNCONFIRMED pane is REFUSED — exit non-zero, nothing typed" {
  fixture_foreground_editor
  setup_recycle
  STUB_TTY=ttys017
  run recycle_fire
  [ "$status" -ne 0 ]
  # The decisive assertion: not one keystroke reached the pane.
  run cat "$TYPED"
  [ "$output" = "" ]
}

@test "recycle_fire: the refusal is LEGIBLE — it never claims a recycle happened" {
  # The 2026-08-06 mis-fire printed "→ recycled (no CC was running)" while a session was live, so
  # the log itself asserted success. The two outcomes must not share vocabulary.
  fixture_foreground_editor
  setup_recycle
  STUB_TTY=ttys017
  run recycle_fire
  [[ "$output" == *"recycle REFUSED"* ]] || false
  [[ "$output" != *"→ recycled"* ]] || false
}

@test "recycle_fire: an expect-wrapped LIVE session is never typed into — it arms instead" {
  # The incident, end to end. Pre-fix this pane took the type-now branch; post-fix it must reach the
  # watcher arm, which the stubbed await_armed then refuses — proving the path, not the outcome.
  fixture_expect_cc
  setup_recycle
  STUB_TTY=ttys009
  run recycle_fire
  run cat "$TYPED"
  [ "$output" = "" ]
}

@test "recycle_fire: a CONFIRMED bare prompt still types — the fix is not a blanket refusal" {
  fixture_idle_shell
  setup_recycle
  STUB_TTY=ttys017
  run recycle_fire
  [ "$status" -eq 0 ]
  run cat "$TYPED"
  [ "$output" = "claude --resume abc" ]
}
