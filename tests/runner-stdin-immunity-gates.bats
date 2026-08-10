#!/usr/bin/env bats
# runner-stdin-immunity-gates — the SEVEN NON-LANDING bats runners hand bats a stdin that is
# /dev/null, always. The counterpart of tests/runner-stdin-immunity.bats, which pins the same
# property for the two LANDING runners (ship-land.sh, postland-verify.sh).
#
# WHY A SECOND FILE RATHER THAN A WIDER CENSUS IN THE FIRST. ce13bd08's evidence — 290 suites
# screened, none depends on inherited stdin — licenses the LANDING corpus only. These are seven
# subsystems with seven callers, and each needed its own screen: does that caller read stdin itself,
# and does anything pipe into it? All seven came back clean (nightly-regression and deploy-live read
# no stdin — their four while-read loops are every one of them fed from a file or heredoc; the four
# safety gates read none at all; task-quality-gate reads it exactly once, at the top, and see G10).
#
# THE MEASURED CORRECTION THIS FILE CARRIES (2026-08-06). ce13bd08 and 5e460544 shipped with the
# premise that the hazard is "the daemon's stdin" — a launchd pipe that never EOFs. That premise is
# FALSE and the probe was cheap: a throwaway RunAtLoad job reading its own `lsof -d 0` reports
# /dev/null. launchd already hands its children /dev/null, so `com.claude.nightly-regression` (04:00)
# and `com.claude.deploy-live --auto` were never the exposed path.
# The exposed path is the one nobody wrote down: an AGENT OR DESK invocation. A Claude Code session's
# fd 0 is a unix SOCKET, and a child that reads it never sees EOF — measured directly, rc 124. That
# is how every one of these seven scripts is actually run day to day, so the exposure is larger than
# the original framing, not smaller; it just lives somewhere else. The polarity is unchanged and is
# still the whole problem: a hand-run from a terminal gets a stdin that EOFs and is GREEN, so the
# hang is invisible to the only person who could see it, and a hung gate looks exactly like a slow
# one.
#
# WHAT IS PINNED:
#   G1   CENSUS — every bats EXECUTION site in all seven files carries the redirect, each file
#        FLOORED so a rename cannot empty a grep into a vacuous pass. This is the arm that goes red
#        when someone adds a new call site without one.
#   G2/3 nightly-regression — the redirect rides a FUNCTION INVOCATION (`run_check … </dev/null`) and
#        has to reach the `"$@"` inside. That propagation is the subtlest of the four shapes and the
#        easiest to "tidy" away, so it is proven, not asserted.
#   G4/5 session-lifecycle-safety-gate — the helper-function shape (`bats_green`), one redirect
#        covering two call sites.
#   G6/7 route-safety-gate — the inline `bats … && ok … || bad …` shape, standing for the three
#        identical safety gates (route, respawn, limit-reset). G1 holds their coverage.
#   G8/9 deploy-live — the command-substitution-inside-`bounded` shape, where the hang is quietest:
#        host_checks never blocks and never changes the exit code, so a wedged suite is not even a
#        red, just a deploy that never returns.
#   G10  task-quality-gate PREMISE — the one caller whose stdin use had to be re-checked rather than
#        assumed. Pins the MEASURED result, both directions, because the comment in that file makes
#        a claim a future reader would otherwise have to take on faith.
#
# Every even-numbered behavioural arm has an ANTI-VACUITY twin: the same artifact with `</dev/null`
# stripped must TIME OUT under the identical fixture. Without it, a probe that quietly stopped
# exercising anything — a drifted extraction, a fixture whose stdin EOFs after all — reports green
# forever. Every strip is anchored and asserted to match EXACTLY ONCE.
#
# Bounds are asymmetric on purpose, as in the counterpart file: a passing arm's bound is generous
# (only ever waited out ON failure, so a saturated box cannot convict it), a mutant's is short
# (paid in full on every green run).
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # hermeticity ratchet: never the live ~/
  NGR="$REPO/scripts/nightly-regression.sh"
  SLG="$REPO/scripts/session-lifecycle-safety-gate.sh"
  RTG="$REPO/scripts/route-safety-gate.sh"
  DPL="$REPO/scripts/deploy-live.sh"
  TQG="$REPO/hooks/task-quality-gate.sh"
  # The bound IS the instrument — with no timeout(1) a hang cannot be told from a pass, so the honest
  # move is to skip rather than run a probe that can only ever report green.
  TMO="$(command -v timeout || command -v gtimeout || true)"
  [ -n "$TMO" ] || skip "no timeout(1) — a hang would be unmeasurable"
}

# ── the instrument (idiom proven in stub-stdin-drain.bats / runner-stdin-immunity.bats) ───────────

# A stub `bats` in the HISTORICAL HAZARD SHAPE: it drains stdin unconditionally. It stands in for any
# suite that consumes stdin, which is the whole population these redirects immunise — not only the
# three stubs 5e460544 fixed. Its own correctness is not the subject; the RUNNER's handling of it is.
install_draining_bats() {   # → $STUBDIR/bats
  STUBDIR="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUBDIR"
  printf '#!/bin/bash\ncat >/dev/null\nexit 0\n' > "$STUBDIR/bats"
  chmod +x "$STUBDIR/bats"
}

# Run a command with an stdin that is OPEN and will never EOF — a FIFO held by a live writer that
# writes nothing. This reproduces the agent/desk socket condition measured above. Prints the exit
# code; 124 is timeout(1)'s "still running when the bound expired", i.e. the hang.
#
# The two hard-won properties are stub-stdin-drain.bats':
#   · the writer's stdio is redirected AWAY from the test's — bats reads a test's output pipe to EOF,
#     so a background child inheriting it keeps the TEST alive for the child's whole lifetime;
#   · the second `exec` REPLACES the subshell with sleep, so $! is the process that actually holds
#     fd 9 and `kill` reaches it.
# The sleep outlives the probe's bound so stdin never EOFs while the probe runs — an early EOF would
# let a BROKEN call site exit and read as a pass — and self-reaps if cleanup never runs.
rc_with_never_eof_stdin() {   # $1=bound seconds; $2… = the command
  local bound="$1"; shift
  local fifo w rc
  fifo="$(mktemp -u "$BATS_TEST_TMPDIR/fifo.XXXXXX")"   # trailing Xs only — BSD mktemp ignores others
  mkfifo "$fifo"
  ( exec 9>"$fifo"; exec sleep "$(( bound + 3 ))" ) >/dev/null 2>&1 </dev/null &
  w=$!
  "$TMO" "$bound" "$@" <"$fifo" >/dev/null 2>&1
  rc=$?
  kill "$w" 2>/dev/null || true
  wait "$w" 2>/dev/null || true
  rm -f "$fifo"
  printf '%s' "$rc"
}

# Pull the ONE line matching an anchor out of a real file, refusing anything but an exact single
# match. A multi-match anchor makes the mutation below ambiguous; a zero-match anchor is the drift
# that would otherwise turn every downstream assertion vacuous.
real_line() {   # $1=file $2=fixed-string anchor
  local hit
  hit="$(grep -F -- "$2" "$1" | grep -v '^[[:space:]]*#')"
  [ "$(printf '%s\n' "$hit" | grep -c .)" = "1" ] || return 1
  printf '%s\n' "$hit"
}

# Strip the redirect from an extracted artifact, asserting it was there exactly once and is gone
# after. This is what makes an anti-vacuity arm a real mutant rather than a hopeful one.
strip_redirect() {   # stdin = artifact text → stdout = mutant
  local body; body="$(cat)"
  [ "$(printf '%s\n' "$body" | grep -cF '</dev/null')" = "1" ] || return 1
  body="$(printf '%s\n' "$body" | sed 's|[ ]*</dev/null||')"
  if printf '%s\n' "$body" | grep -qF '</dev/null'; then return 1; fi
  printf '%s\n' "$body"
}

# ── G1 — the census ──────────────────────────────────────────────────────────────────────────────

@test "G1: EVERY bats execution site in all EIGHT runners redirects stdin — census is FLOORED" {
  # The behavioural arms prove the property at four sites; this proves COVERAGE at all of them, and
  # it is the arm that fails when a NEW call site is added without a redirect. Comment lines are
  # excluded throughout: each of these files now carries a rationale that names both `bats` and
  # `</dev/null`, and a census that counted its own explanation would be self-congratulatory.
  #
  # THE EIGHTH RUNNER, added 2026-08-10 (backlog b4f93c9fa73c). scripts/offbox-run.sh is the off-box
  # corpus runner, and it is in this census because it shipped WITHOUT the redirect and CI proved the
  # hazard is real rather than screened-clean: three matrix shards stopped after 3, 25 and 17 of their
  # 37-38 suites, each immediately after a stdin-reading suite that ate the rest of the shard's suite
  # list out of the runner's own `while read` pipe. The step exited 0 and its log simply ended.
  # It is the first CONFIRMED instance of this class here — the seven above were screened and came
  # back clean — and it moves the exposure once more. Not the daemon's stdin (launchd hands
  # /dev/null), and not only an agent session's socket fd 0: ANY runner that feeds itself a work list
  # on a pipe is exposed to its own children, with no launchd and no session involved at all.
  #
  # FLOORED PER FILE, not merely non-empty. A rename (`$BATS_BIN`, `$SUITE`, a renamed helper) would
  # empty the grep and make the "every matched line has the redirect" test pass over zero lines —
  # the exact vacuous-pass shape this repo has been bitten by. Dropping below a floor means GO
  # RE-VERIFY the sites; it never means lower the number.
  local spec f anchor floor hits missing bad=""
  # file|fixed-string anchor for the EXECUTION site|expected minimum count
  for spec in \
    "scripts/nightly-regression.sh|run_check \"bats:|1" \
    "hooks/task-quality-gate.sh|bats \"\${runbats[@]}\"|2" \
    "scripts/session-lifecycle-safety-gate.sh|bats \"\$suite\" </dev/null|1" \
    "scripts/route-safety-gate.sh|bats tests/cc-route.bats|1" \
    "scripts/respawn-safety-gate.sh|bats tests/cc-respawn.bats|1" \
    "scripts/limit-reset-safety-gate.sh|bats \"\$SUITE\"|1" \
    "scripts/deploy-live.sh|\"\$BATS_BIN\" \"\$s\"|1" \
    "scripts/offbox-run.sh|\"\$BATS_BIN\" \"\$suite\"|1" \
  ; do
    f="${spec%%|*}"; anchor="${spec#*|}"; floor="${anchor##*|}"; anchor="${anchor%|*}"
    [ -f "$REPO/$f" ] || { bad="$bad"$'\n'"$f: ABSENT from this worktree"; continue; }
    hits="$(grep -nF -- "$anchor" "$REPO/$f" | grep -v '^[0-9]*:[[:space:]]*#' || true)"
    if [ "$(printf '%s\n' "$hits" | grep -c .)" -lt "$floor" ]; then
      bad="$bad"$'\n'"$f: census FLOOR breached — anchor '$anchor' matched fewer than $floor line(s); the anchor has drifted, RE-VERIFY the sites"
      continue
    fi
    missing="$(printf '%s\n' "$hits" | grep -vF '</dev/null' || true)"
    [ -z "$missing" ] || bad="$bad"$'\n'"$f: unredirected bats call site(s):"$'\n'"$missing"
  done
  [ -z "$bad" ] || { echo "$bad"; false; }
}

# ── G2/G3 — nightly-regression: does the redirect reach through a FUNCTION INVOCATION? ────────────

# Extract the REAL run_check plus the REAL invocation line. run_check's own dependencies are stubbed
# to their inert forms — `outfile` is a tmpfile-namer and NCHECK/REDS are tallies; none of them
# touches stdin, so reducing them keeps the probe hermetic without weakening what it measures.
build_ngr_probe() {   # $1=variant(fixed|mutant) → $BATS_TEST_TMPDIR/ngr.sh
  local body line
  body="$(sed -n '/^run_check() {/,/^}/p' "$NGR")"
  [ -n "$body" ]                                              # an empty extraction is a vacuous pass
  printf '%s\n' "$body" | grep -qF '"$@" >"$out" 2>&1' || false   # …and a non-empty one can be wrong
  line="$(real_line "$NGR" 'run_check "bats:')"
  if [ "$1" = mutant ]; then line="$(printf '%s\n' "$line" | strip_redirect)" || return 1; fi
  { printf 'REDS=(); NCHECK=0\n'
    printf 'outfile() { printf "%%s" "/dev/null"; }\n'
    printf 'BATS_DIR="tests"\n'
    printf '%s\n' "$body"
    printf '%s\n' "$line"
  } > "$BATS_TEST_TMPDIR/ngr.sh"
}

@test "G2: nightly-regression's run_check invocation carries the redirect INTO the child" {
  # The shape here is unique among the seven: the redirect sits on a FUNCTION CALL, and has to apply
  # to the whole body so that the `"$@"` inside gets it. That is correct bash and it is also exactly
  # the kind of thing a tidy-up moves onto the wrong line, so it is measured rather than trusted.
  install_draining_bats
  build_ngr_probe fixed
  [ "$(rc_with_never_eof_stdin 20 env PATH="$STUBDIR:$PATH" bash "$BATS_TEST_TMPDIR/ngr.sh")" = "0" ]
}

@test "G3: ANTI-VACUITY — nightly-regression's invocation WITHOUT the redirect hangs" {
  # Proves three things G2 cannot prove alone: the fixture really presents a stdin that never EOFs,
  # the stub really reads it, and the redirect is what makes G2 green.
  install_draining_bats
  build_ngr_probe mutant
  [ "$(rc_with_never_eof_stdin 5 env PATH="$STUBDIR:$PATH" bash "$BATS_TEST_TMPDIR/ngr.sh")" = "124" ]
}

# ── G4/G5 — session-lifecycle-safety-gate: the helper-function shape ──────────────────────────────

# RE-ANCHORED 2026-08-09 onto bats_row. The old anchor was `bats_green(){`, a ONE-LINE helper that
# `real_line` could lift whole; item 38e4601fa933 (2026-08-08) DELETED it — deliberately, and the
# subject says so at scripts/session-lifecycle-safety-gate.sh:48 — replacing it with the three-state
# `bats_row` so that cc-bats' rc 75 (EX_TEMPFAIL: "nothing ran, nothing was verified") stops being
# laundered into RED. The property these arms assert did NOT change: the successor still redirects
# (`bats "$suite" </dev/null >/dev/null 2>&1`, line 71). Only the anchor died, which is exactly the
# drift G1's floor exists to catch — and its instruction is RE-VERIFY the sites, never lower the
# number, so the site was re-verified and the anchor moved to the surviving execution line.
#
# bats_row is multi-line, so instead of lifting a whole function this lifts the REAL execution line
# and supplies the one variable it reads. That keeps the mutant honest: strip_redirect still asserts
# `</dev/null` was present exactly once and is gone after, on bytes taken from the shipping file.
build_slg_probe() {   # $1=variant → $BATS_TEST_TMPDIR/slg.sh
  local line
  line="$(real_line "$SLG" 'bats "$suite" </dev/null')" || return 1
  if [ "$1" = mutant ]; then line="$(printf '%s\n' "$line" | strip_redirect)" || return 1; fi
  { printf 'suite="tests/foo.bats"\n'; printf '%s\n' "$line"; } > "$BATS_TEST_TMPDIR/slg.sh"
}

@test "G4: session-lifecycle bats_green returns PROMPTLY on a stdin that never EOFs" {
  # One redirect in the helper covers both of that gate's call sites (CL and RP).
  install_draining_bats
  build_slg_probe fixed
  [ "$(rc_with_never_eof_stdin 20 env PATH="$STUBDIR:$PATH" bash "$BATS_TEST_TMPDIR/slg.sh")" = "0" ]
}

@test "G5: ANTI-VACUITY — bats_green WITHOUT the redirect hangs under the same fixture" {
  install_draining_bats
  build_slg_probe mutant
  [ "$(rc_with_never_eof_stdin 5 env PATH="$STUBDIR:$PATH" bash "$BATS_TEST_TMPDIR/slg.sh")" = "124" ]
}

# ── G6/G7 — route-safety-gate: the inline `bats … && ok … || bad …` shape ─────────────────────────

# Stands for all three identically-shaped safety gates (route, respawn, limit-reset); G1 holds the
# other two's coverage. The real line is evaluated VERBATIM with `ok`/`bad` stubbed to their inert
# forms — they are reporters, they touch no stdin, and stubbing them is what lets the artifact under
# test be the shipped text rather than a hand-written approximation of it.
build_rtg_probe() {   # $1=variant → $BATS_TEST_TMPDIR/rtg.sh
  local line
  line="$(real_line "$RTG" 'bats tests/cc-route.bats')"
  if [ "$1" = mutant ]; then line="$(printf '%s\n' "$line" | strip_redirect)" || return 1; fi
  { printf 'ok() { :; }\nbad() { :; }\n'
    printf 'cd "%s" || exit 1\n' "$BATS_TEST_TMPDIR"
    printf 'mkdir -p tests && : > tests/cc-route.bats\n'
    printf '%s\n' "$line"
  } > "$BATS_TEST_TMPDIR/rtg.sh"
}

@test "G6: route-safety-gate's bats line returns PROMPTLY on a stdin that never EOFs" {
  install_draining_bats
  build_rtg_probe fixed
  [ "$(rc_with_never_eof_stdin 20 env PATH="$STUBDIR:$PATH" bash "$BATS_TEST_TMPDIR/rtg.sh")" = "0" ]
}

@test "G7: ANTI-VACUITY — route-safety-gate's line WITHOUT the redirect hangs" {
  install_draining_bats
  build_rtg_probe mutant
  [ "$(rc_with_never_eof_stdin 5 env PATH="$STUBDIR:$PATH" bash "$BATS_TEST_TMPDIR/rtg.sh")" = "124" ]
}

# ── G8/G9 — deploy-live: the command-substitution-inside-`bounded` shape ──────────────────────────

# The REAL `bounded` is extracted, not stubbed: it is the wrapper the redirect has to survive, and a
# stub of it would be measuring the test's own idea of the call rather than the shipped one.
# TIMEOUT_BIN is left EMPTY on purpose so `bounded` takes its no-timeout(1) branch — otherwise this
# probe would be measuring deploy-live's bound instead of the redirect, and would go green on a
# broken site for the wrong reason.
build_dpl_probe() {   # $1=variant → $BATS_TEST_TMPDIR/dpl.sh
  local body line
  body="$(sed -n '/^bounded() {/,/^}/p' "$DPL")"
  [ -n "$body" ]
  printf '%s\n' "$body" | grep -qF 'TIMEOUT_BIN' || false
  line="$(real_line "$DPL" '"$BATS_BIN" "$s"')"
  if [ "$1" = mutant ]; then line="$(printf '%s\n' "$line" | strip_redirect)" || return 1; fi
  { printf 'TIMEOUT_BIN=""\n'
    printf 'DEPLOY_REPO="%s"\n' "$BATS_TEST_TMPDIR"
    printf 'HOST_TIMEOUT_S=60\n'
    printf 'BATS_BIN="%s/bats"\n' "$STUBDIR"
    printf 's="tests/foo.bats"\n'
    printf '%s\n' "$body"
    printf '%s\n' "$line"
    printf 'exit 0\n'
  } > "$BATS_TEST_TMPDIR/dpl.sh"
}

@test "G8: deploy-live's host-check bats call returns PROMPTLY on a stdin that never EOFs" {
  # The quietest of the seven: host_checks never blocks and never changes the exit code, so a suite
  # wedged here is not even a red — it is a deploy that simply never returns.
  install_draining_bats
  build_dpl_probe fixed
  [ "$(rc_with_never_eof_stdin 20 bash "$BATS_TEST_TMPDIR/dpl.sh")" = "0" ]
}

@test "G9: ANTI-VACUITY — deploy-live's host-check call WITHOUT the redirect hangs" {
  install_draining_bats
  build_dpl_probe mutant
  [ "$(rc_with_never_eof_stdin 5 bash "$BATS_TEST_TMPDIR/dpl.sh")" = "124" ]
}

# ── G10 — task-quality-gate: the premise that had to be re-checked, not assumed ───────────────────

@test "G10: task-quality-gate's stdin hazard is at INPUT=\$(cat), NOT at its bats call" {
  # THE ONE CALLER WHOSE OWN STDIN USE HAD TO BE MEASURED. Its redirect is defence in depth, and the
  # comment in that file says so; this is what stops that claim from rotting into folklore. Both
  # directions, against the REAL hook:
  #
  #   A. writer CLOSES (how the harness invokes a hook) — the drain returns, fd 0 stays at EOF, the
  #      hook completes. bats would inherit a benign already-EOF descriptor.
  #   B. writer NEVER closes — the hook wedges on line 12 and never reaches the bats call at all.
  #      A redirect at the bats site could not have prevented this, which is precisely why the fix
  #      for this file is NOT a hang fix and must not be recorded as one.
  #
  # `jq` gates the hook's first line: absent, it exits 0 before the drain and B could not fire. That
  # would be a probe that can only report green, so skip instead of running it.
  command -v jq >/dev/null 2>&1 || skip "no jq — the hook exits before its stdin drain, so B cannot fire"
  [ -f "$TQG" ] || skip "task-quality-gate.sh not present in this worktree"

  # A — empty TEAM_NAME sends it down its own early-exit, so nothing downstream of stdin is exercised
  run env HOME="$HOME" "$TMO" 10 bash "$TQG" <<< '{"task_subject":"x"}'
  [ "$status" -eq 0 ]

  # B — the hang, and it must land BEFORE bats. Proven by making bats unrunnable: PATH holds no bats
  # at all here, so if the wedge were at the bats call this would exit rather than time out.
  [ "$(rc_with_never_eof_stdin 5 env HOME="$HOME" PATH=/usr/bin:/bin bash "$TQG")" = "124" ]
}
