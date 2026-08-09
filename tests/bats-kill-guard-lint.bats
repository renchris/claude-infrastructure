#!/usr/bin/env bats
# bats-kill-guard-lint — the gate for a load-flake class that had been fixed BY HAND nine times and
# by a gate never.
#
# THE CLASS. `kill "$p" 2>/dev/null` with no `|| true`. Measured on /bin/bash 3.2.57, which is what
# bats runs here (f676d2f6): kill returns 0 while the child is ALIVE, 0 on an UNREAPED zombie, and 1
# only once bash has REAPED it. So the window opens after the REAP, not the exit — which is why it
# needs load to show and never reproduces in isolation. Under bats' errexit that rc 1 aborts the
# enclosing body: a test that passed on its own merits goes red, and a fixture helper aborts before
# its `echo`, leaving a TRUNCATED file the rest of the suite then misreads.
#
# WHY A GATE AND NOT ANOTHER SWEEP. debc016f fixed one site (at the cost of a refused push — the bats
# retry's extra executed count tripped the gate's own 1614≠1613 plan mismatch), 956f4545 one more,
# e90476e6 six, f676d2f6 one. Nothing looked for the tenth. By 2026-08-09 eleven sites had
# re-accumulated, three of them in cc-await-ping.bats, a suite written AFTER the sweep — which is the
# whole argument: a sweep is a snapshot, and this class regenerates because the defective spelling is
# the natural one to type. The corpus is at zero as of this suite, so the lint runs STRICT.
#
# Hermetic: every fixture lives in $BATS_TEST_TMPDIR and $HOME is fixtured. The three cases that
# touch the real tree read it only (the corpus scan and two wiring greps).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  L="$REPO/scripts/bats-kill-guard-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  D="$BATS_TEST_TMPDIR"
}

# A bats fixture built with printf — never a heredoc, whose `@test` bats' preprocessor strips.
mkb() { printf '#!/usr/bin/env bats\n%s\n' "$2" > "$D/$1.bats"; }

# ── the lint's own discrimination ─────────────────────────────────────────────────────────────────
@test "--selftest passes: the lint discriminates in both directions" {
  run "$L" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'all cases pass' || false
}

# ── THE CORPUS INVARIANT. This is the assertion that makes a tenth site impossible, and it is why
# the lint is strict rather than own-scoped: there is nothing to grandfather. Stated as ZERO, which
# unlike a count of sites cannot tripwire on the corpus merely GROWING
# (memory: exact-count-assertion-tripwires-its-own-subject).
@test "the real corpus carries ZERO unguarded kills — the ratchet's baseline" {
  run "$L" "$REPO/tests"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '0 unguarded kill' || false
}

# ── THE RULE, both directions, on the REAL artifacts ──────────────────────────────────────────────
# Each RED below is a byte-for-byte replay of a line that actually flaked, taken from the commit that
# fixed it; each GREEN is that same line as the fix left it. The pair differs by exactly the token
# under test, so neither can pass vacuously (memory: control-must-replay-the-real-artifact).
@test "RED: f676d2f6's deadpid helper — the line that flaked 1-in-3 at loadavg ~13" {
  mkb bad 'deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null || true; echo "$p"; }'
  run "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'KILL-GUARD' || false
  echo "$output" | grep -q 'stderr silenced, exit status not' || false
}

@test "GREEN: the same helper as f676d2f6 fixed it — the lint accepts its own remedy" {
  mkb ok 'deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; echo "$p"; }'
  run "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
}

@test "RED: e90476e6's teardown shape — a trailing '; true' does NOT shield the kill" {
  mkb bad 'teardown() { [ -n "${HOLDER_PID:-}" ] && kill "$HOLDER_PID" 2>/dev/null; true; }'
  run "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
}

@test "RED: pkill too — the class is the CONTRADICTION, not the spelling 'kill'" {
  mkb bad 'teardown() { pkill -f "$WEDGE" 2>/dev/null; sleep 1; pkill -9 -f "$WEDGE" 2>/dev/null; }'
  run "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
  # BOTH kills on the line are reported, not just the first: a per-line report would under-count
  # what a fix has to touch (memory: per-site-mutation-attributes-coverage).
  [ "$(echo "$output" | grep -c 'KILL-GUARD')" -eq 2 ]
}

# ── EXEMPTION 1 — silence is the discriminator — and its positive control ─────────────────────────
@test "GREEN: an ASSERTION kill (stderr NOT redirected) is not the class" {
  # cc-pane-headless.bats:195's real shape: it kills a `sleep 30` spawned two lines earlier, so the
  # kill MUST succeed and its failure SHOULD red the test. `|| true` there would delete an assertion.
  mkb ok '@test "x" {
  pid="$(live_pid "$id")"
  kill -9 "$pid"
}'
  run "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
}

@test "POSITIVE CONTROL for the above: the SAME kill WITH stderr silenced is RED" {
  mkb bad '@test "x" {
  pid="$(live_pid "$id")"
  kill -9 "$pid" 2>/dev/null
}'
  run "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
}

# ── EXEMPTION 2 — an already-failing path — and its positive control ─────────────────────────────
@test "GREEN: a kill inside a '|| { echo …; kill …; false; }' diagnostic is already-red" {
  mkb ok '@test "x" {
  [ "$status" -eq 1 ] || { echo "STOLE the lock from a live holder"; kill "$holder" 2>/dev/null; false; }
}'
  run "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
}

@test "POSITIVE CONTROL for the above: drop the terminal 'false' and the same group is RED" {
  # Without it the exemption would be unbounded — an abstain that deletes the common case
  # (memory: abstain-rule-can-retire-the-common-case).
  mkb bad '@test "x" {
  [ "$status" -eq 1 ] || { echo "STOLE the lock from a live holder"; kill "$holder" 2>/dev/null; }
}'
  run "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
}

# ── the AND-OR list rule, both directions ────────────────────────────────────────────────────────
@test "GREEN: an && chain whose LIST is consumed by a trailing || is guarded" {
  # git-worktree-guard.bats:26 as its fix leaves it. POSIX: -e is ignored for every command of an
  # AND-OR list but the last, and here the last is `true`.
  mkb ok 'teardown() { [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null && wait "$PROBE_PID" 2>/dev/null || true; }'
  run "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
}

@test "RED: the same && chain with NOTHING consuming it — a failing kill short-circuits the list" {
  mkb bad 'teardown() { [ -n "${PROBE_PID:-}" ] && kill "$PROBE_PID" 2>/dev/null && wait "$PROBE_PID" 2>/dev/null; }'
  run "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
}

@test "GREEN: a brace group guarded by a trailing || — suppression propagates into the compound" {
  mkb ok 'teardown() { { kill "$FOREIGN" && wait "$FOREIGN"; } 2>/dev/null || true; }'
  run "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
}

# ── kill -0 is a PROBE, not a signal ─────────────────────────────────────────────────────────────
@test "GREEN: a kill -0 liveness probe is out of scope — guarding one inverts its meaning" {
  mkb ok '@test "x" {
  kill -0 "$wpid" 2>/dev/null
}'
  run "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
}

# ── NOT a command: the shapes that made a naive detector 90% false positives ─────────────────────
@test "GREEN: a @test TITLE containing 'kill switch' is prose, not a command" {
  mkb ok '@test "R8 kill switch: CC_ROUTE_CLIFF_TERM=off restores pre-term scoring" {
  run true
}'
  run "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
}

@test "GREEN: 'kill' as an ARGUMENT — a subcommand name, a grep pattern — is not a command" {
  mkb ok '@test "x" {
  bash "$HOOK" kill >/dev/null 2>&1
  run grep -nE "session close|kill -9|pkill" "$S"
}'
  run "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
}

# ── THE BLINDNESS REGRESSION ─────────────────────────────────────────────────────────────────────
# The first draft detected heredoc openers on the RAW line, so a `<<EOF` mentioned inside a STRING
# opened one that never closed and swallowed the remaining 8,667 lines of the corpus (8.3%) —
# taking four genuine defects with it and reporting a confident clean verdict over the hole. Both
# halves are pinned, because only the pair distinguishes "heredocs are handled" from "heredoc
# handling is disabled" (memory: lint-blindness-composes-and-hides-the-next-defect).
@test "GREEN: a kill inside a REAL heredoc body is data — a stub script is not bats commands" {
  mkb ok '@test "x" {
  cat > "$D/s.sh" <<EOF
kill "$p" 2>/dev/null
EOF
  run true
}'
  run "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
}

@test "RED: a '<<EOF' inside a STRING must not blind the lint to the defect BELOW it" {
  printf '#!/usr/bin/env bats\n@test "x" {\n  printf %s > "$D/w.sh"\n  kill "$p" 2>/dev/null\n}\n' "'cat <<EOF'" > "$D/blind.bats"
  run "$L" "$D/blind.bats"
  [ "$status" -eq 1 ]
}

# ── a suite DESCRIBING a kill is not a suite running one ─────────────────────────────────────────
# This corpus writes fixtures as multi-line single-quoted strings, so the kill lands on its own line
# with no quote THAT LINE can see. A per-line stripper calls it a violation — and this very suite
# would then be reported as a corpus defect, which is exactly how the case was found.
@test "GREEN: a kill inside a suite's own multi-line fixture string is described, not run" {
  printf '#!/usr/bin/env bats\n@test "x" {\n  mkb bad %s@test "y" {\n  kill "$p" 2>/dev/null\n}%s\n  run true\n}\n' "'" "'" > "$D/embedded.bats"
  run "$L" "$D/embedded.bats"
  [ "$status" -eq 0 ]
}

@test "RED: a nested command substitution must not blind the lint to the defect below it" {
  # `"$(mkfix "…")"` — the inner quote OPENS a string rather than closing the outer one. Fifteen
  # suites (4.2% of the corpus) ended mid-string on this before the quote context became a stack.
  printf '#!/usr/bin/env bats\n@test "x" {\n  run runhook "$(mkfix "Youll need to run gcloud auth login")"\n  kill "$p" 2>/dev/null\n}\n' > "$D/nested.bats"
  run "$L" "$D/nested.bats"
  [ "$status" -eq 1 ]
}

# ── THE THIRD STATE: a file that cannot be read to the end is a NON-VERDICT, and fails closed ────
@test "a file ending INSIDE an unterminated string is UNREADABLE, not clean" {
  printf '#!/usr/bin/env bats\n@test "x" {\n  echo "never closed\n  run true\n' > "$D/unread.bats"
  run "$L" "$D/unread.bats"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'UNREADABLE' || false
  # …and it is NOT folded into the kill count — the two states name different problems, and a
  # non-verdict reported as a violation would send the author hunting for a kill that is not there.
  # Written `! …`, never `… && false`: the latter is DEAD both ways under bats' errexit (the AND-list
  # fails when the grep MISSES, which is the passing case) and the trailing `true` then swallows it,
  # so it asserts nothing at all. The land gate's dead-assertion ratchet caught exactly that here.
  ! echo "$output" | grep -q 'KILL-GUARD'
}

@test "POSITIVE CONTROL for the above: the same fixture with the string closed is clean" {
  printf '#!/usr/bin/env bats\n@test "x" {\n  echo "closed"\n  run true\n' > "$D/read.bats"
  run "$L" "$D/read.bats"
  [ "$status" -eq 0 ]
}

@test "the whole corpus is READABLE — 0 unreadable, so 'clean' is a claim about every line" {
  run "$L" "$REPO/tests"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '0 unreadable' || false
}

# ── the kill switch, with the RED as its positive control ────────────────────────────────────────
@test "CC_BATS_KILL_GUARD=off disables the lint over a real RED" {
  mkb bad 'deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null || true; echo "$p"; }'
  run env CC_BATS_KILL_GUARD=off "$L" "$D/bad.bats"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'DISABLED' || false
}

@test "POSITIVE CONTROL: the identical run WITHOUT the kill switch is rc 1" {
  # Without this pair, "green" and "switched off" are the same observation
  # (memory: sensor-default-off-makes-blindness-the-shipping-path).
  mkb bad 'deadpid() { sleep 1 & local p=$!; kill "$p" 2>/dev/null; wait "$p" 2>/dev/null || true; echo "$p"; }'
  run "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
}

# ── a lint that CANNOT RUN must not look like a lint that found nothing ──────────────────────────
@test "nothing scannable is exit 2 and LOUD, never a silent green" {
  mkdir -p "$D/empty"
  run "$L" "$D/empty"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q '⛔' || false
}

# ── ENFORCEMENT LIVES AT THE CHOKEPOINT, not in this file ────────────────────────────────────────
# A lint asserted only by its own suite is detection, not a gate: the suite has to be selected to run
# at all, and a smoke lane that maps suites to a diff will not select it for a land that touches
# neither (memory: enforcement-must-live-at-the-chokepoint). Both callers are therefore pinned.
@test "WIRING: ship-land's gate invokes the lint AND its selftest" {
  run grep -c 'bats-kill-guard-lint.sh' "$REPO/scripts/ship-land.sh"
  [ "$status" -eq 0 ]
  [ "$output" -ge 1 ]
  grep -q 'KILL_GUARD_LINT" --selftest' "$REPO/scripts/ship-land.sh" || false
  grep -q 'gate_red kill-guard' "$REPO/scripts/ship-land.sh" || false
}

@test "WIRING: the task-quality-gate hook invokes it too, at the earlier chokepoint" {
  grep -q 'bats-kill-guard-lint.sh' "$REPO/hooks/task-quality-gate.sh" || false
  grep -q 'bats-kill-guard' "$REPO/hooks/task-quality-gate.sh" || false
}
