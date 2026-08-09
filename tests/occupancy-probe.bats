#!/usr/bin/env bats
# occupancy-probe.sh — the instrument Phase A is measured with.
#
# WHY THE ARGV TEST IS THE ONE THAT MATTERS. This probe exists because the Phase A brief's own
# census was wrong: it reported "19 cc-reaper, 20 cc-await-ping, 6 cc-reconcile" running per-session,
# and re-measured with a command-position predicate the true counts were 0, 1 and 0. The brief was
# taken with an argv-substring match, and every session whose PROMPT quoted those names matched
# itself, once per pane — the fleet's own `pgrep-f-matches-agent-briefs` failure, committed against
# the very number a wave was scoped on. Test 4 below is that failure, pinned: a row whose executable
# is `claude` but whose argv contains the literal text `cc-reaper` must bucket as `claude`.
#
# The two MUTATION CHECKS at the bottom carry the suite. Each neuters exactly one behaviour in a
# COPY of the real file and asserts a positive test above flips, so neither can be passing
# vacuously.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="$REPO/scripts/occupancy-probe.sh"
  D="$BATS_TEST_TMPDIR"

  # A canned `ps -axo state=,pid=,ppid=,command=` capture. State is RIGHT-ALIGNED exactly as macOS
  # ps emits it, because a fixture that left-aligned it would silently exercise a different parse
  # than production and every test here would be a statement about a format that does not exist.
  cat > "$D/ps.txt" <<'EOF'
    S   100     1 /bin/bash /Users/x/.claude/hooks/lead-crash-watchdog.sh
    R   101     1 /bin/bash /Users/x/.claude/bin/cc-await-ping --timeout 14400 --interval 15
   RN   102   101 /usr/bin/grep -c  /Users/x/.claude/mailbox/AAA.md
    S   103     1 /usr/bin/sleep 30
    R   104     1 /Users/x/.claude-220/node_modules/.bin/claude --model opus WAVE A 19 cc-reaper 20 cc-await-ping 6 cc-reconcile
    R   105     1 /bin/bash -c while :; do :; done
    R   106     1 (jq)
   Rs  107     1 /usr/libexec/notifyd
EOF
}

run_fixture() { # <self_pid>
  CC_OCC_SELF_PID="${1:-0}" run "$P" --fixture "$D/ps.txt"
}

# ── the classifier ────────────────────────────────────────────────────────────────────────────────

@test "1: only RUNNABLE rows are emitted — sleeping rows never appear" {
  run_fixture 0
  [ "$status" -eq 0 ]
  # 100 and 103 are S; neither may appear.
  ! grep -qE '^100 ' <<< "$output" || false
  ! grep -qE '^103 ' <<< "$output" || false
  grep -qE '^101 ' <<< "$output"
}

@test "2: interpreter extension — a bash-run script buckets on the SCRIPT, not on bash" {
  run_fixture 0
  [ "$status" -eq 0 ]
  grep -qE '^101 cc-await-ping$' <<< "$output"
  # If this regressed to the interpreter, every hook on the box would collapse into one bucket and
  # the attribution the wave depends on would be gone.
  ! grep -qE '^101 bash$' <<< "$output" || false
}

@test "3: 'bash -c' keeps its own name — there is no script there to name" {
  run_fixture 0
  grep -qE '^105 bash$' <<< "$output"
}

@test "4: ARGV IMMUNITY — a claude row whose argv quotes 'cc-reaper' buckets as claude" {
  run_fixture 0
  grep -qE '^104 claude$' <<< "$output"
  # The exact defect that produced the brief's 19/20/6: nothing may bucket on a name that appears
  # only inside another process's arguments.
  ! grep -qE ' cc-reaper$' <<< "$output" || false
  ! grep -qE ' cc-reconcile$' <<< "$output" || false
}

@test "5: self-exclusion follows the FULL ancestry, not just one level" {
  # 102's parent is 101, whose parent is 1. Declaring 101 as self must exclude BOTH 101 and its
  # child 102 — the real shape, where `$(ps …)` puts a subshell between the probe and its fork.
  run_fixture 101
  [ "$status" -eq 0 ]
  ! grep -qE '^101 ' <<< "$output" || false
  ! grep -qE '^102 ' <<< "$output" || false
  grep -q '^#self 2$' <<< "$output"
  # An unrelated runnable row must survive the exclusion — a filter that dropped everything would
  # pass the two assertions above for entirely the wrong reason.
  grep -qE '^104 claude$' <<< "$output"
}

@test "6: self rows are COUNTED, not silently dropped" {
  run_fixture 0
  grep -q '^#self 0$' <<< "$output"
}

@test "7: a parenthesised comm keeps its own bucket rather than folding into a real one" {
  run_fixture 0
  grep -qE '^106 jq$' <<< "$output"
}

@test "8: an unknown argument is a usage error, not a default" {
  run "$P" --bogus
  [ "$status" -eq 64 ]
}

@test "9: a non-numeric seam is refused at startup rather than reaching awk as 0" {
  CC_OCC_HZ=abc run "$P" --seconds 1
  [ "$status" -eq 64 ]
  [[ "$output" == *"HZ must be a positive integer"* ]]
}

@test "10: an unreadable fixture is refused" {
  run "$P" --fixture "$D/does-not-exist.txt"
  [ "$status" -eq 64 ]
}

@test "11: BLIND sampling exits 3 — zero readable samples never reads as an idle box" {
  # A stub `ps` that produces nothing must not yield a clean 0.000 occupancy. "Could not measure"
  # and "measured zero" are different facts and only one of them is safe to act on.
  mkdir -p "$D/stub"
  printf '#!/bin/sh\nexit 1\n' > "$D/stub/ps"; chmod +x "$D/stub/ps"
  PATH="$D/stub:$PATH" run "$P" --seconds 1 --hz 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"instrument blind"* ]] || [[ "$output" == *"ZERO readable"* ]]
}

@test "12: a live run reports the self-exclusion it applied" {
  run "$P" --seconds 1 --hz 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"self-excluded"* ]] || false
  [[ "$output" == *"MEAN RUNNABLE"* ]]
}

@test "13: --json emits one parseable object carrying both terms" {
  run "$P" --seconds 1 --hz 2 --json --label probe
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mean_runnable":'* ]] || false
  [[ "$output" == *'"mean_load1":'* ]] || false
  [[ "$output" == *'"label":"probe"'* ]] || false
  # It must be ONE line: a multi-line "JSON" object is what makes a consumer's parse succeed on the
  # first field and silently drop the rest (compressor-sentinel.sh:427 records the same defect).
  [ "$(printf '%s\n' "$output" | grep -c '^{')" -eq 1 ]
}

# ── MUTATION CHECKS — each must FLIP a positive test above ────────────────────────────────────────

@test "M1: MUTATION — removing the interpreter extension collapses the script into 'bash'" {
  m="$D/mutant1.sh"
  sed 's|if (base ~ /\^(bash\|sh\|zsh\|dash\|ksh\|python\[0-9.\]\*\|perl\|ruby\|osascript)\$/ \&\& nf >= 2|if (0 \&\& nf >= 2|' "$P" > "$m"
  chmod +x "$m"
  # The mutation must actually have applied — a no-op sed would pass this test vacuously.
  grep -q 'if (0 && nf >= 2' "$m"

  CC_OCC_SELF_PID=0 run "$m" --fixture "$D/ps.txt"
  [ "$status" -eq 0 ]
  # Test 2 asserted 'cc-await-ping'. Neutered, it must read 'bash'.
  grep -qE '^101 bash$' <<< "$output" || {
    echo "MUTATION SURVIVED: interpreter extension removed but bucket still not 'bash'"; false
  }
  ! grep -qE '^101 cc-await-ping$' <<< "$output" || false
}

@test "M2: MUTATION — a one-level self test lets the grandchild through" {
  m="$D/mutant2.sh"
  sed 's|if (is_self(pid\[r\])) { selfn++; continue }|if (ppid[r] == self) { selfn++; continue }|' "$P" > "$m"
  chmod +x "$m"
  grep -q 'if (ppid\[r\] == self)' "$m"
  ! grep -q 'if (is_self(pid\[r\]))' "$m" || false

  CC_OCC_SELF_PID=101 run "$m" --fixture "$D/ps.txt"
  [ "$status" -eq 0 ]
  # Test 5 asserted 102 (self's CHILD, reached only by the walk) is excluded. With a one-level test
  # keyed on ppid, 102 IS excluded but 101 ITSELF — whose ppid is 1 — leaks back in. That is exactly
  # the bug this probe shipped with and the measured symptom was a `ps` bucket pinned at 1.000.
  grep -qE '^101 ' <<< "$output" || {
    echo "MUTATION SURVIVED: one-level self test but pid 101 still excluded"; false
  }
}
