#!/usr/bin/env bats
# pty-census.sh — the gauge for the one finite table nothing on this box was watching.
#
# WHY TEST 3 IS THE ONE THAT MATTERS. This instrument exists because every prior pty census in the
# concurrency program used `ls /dev/ttys* | wc -l`, and that glob matches TWO disjoint device
# classes: the ptmx clones (/dev/ttys000..999, allocated and released) and 16 static legacy BSD
# nodes (/dev/ttys0..ttysf, present since boot, governed by nothing). The naive count therefore
# carries a constant +16 offset. At the fleet sizes the published figures were taken at — 6 and 15
# sessions — that offset WAS the reported effect: 21 glob matches read as "21 ptys at 6 sessions"
# when the truth was 5, and 33 read as 2.2/session when the truth was 1.13.
#
# So the predicate is the whole instrument, and test 3 pins it against a fixture containing both
# classes. Tests 7 and 8 are the MUTATION CHECKS that stop this suite passing vacuously: each
# neuters exactly one behaviour in a COPY of the real file and asserts a positive test above flips.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  P="$REPO/scripts/pty-census.sh"
  D="$BATS_TEST_TMPDIR"

  # Fixtured $HOME. The subject reads no dotfile today, but a suite that runs against the operator's
  # live ~/ is one edit away from mutating it, and the whole run's results stop being trustworthy.
  export HOME="$D/home"; mkdir -p "$HOME"

  # A fixture /dev carrying BOTH device classes, in the exact naming production sees:
  #   2 ptmx clones      ttys000 ttys001          ← the resource
  #  16 legacy nodes     ttys0..ttys9 ttysa..ttysf ← NOT the resource
  # A predicate that cannot tell them apart reports 18.
  mkdir -p "$D/dev"
  touch "$D/dev/ttys000" "$D/dev/ttys001"
  for c in 0 1 2 3 4 5 6 7 8 9 a b c d e f; do touch "$D/dev/ttys$c"; done

  # `ps -axo comm=` emits the executable path alone — no argv. The fourth row is the contamination
  # shape that broke wave A, rendered as this column actually renders it.
  cat > "$D/ps.txt" <<'EOF'
/Users/x/.claude-220/node_modules/.bin/claude
/Users/x/.claude-220/node_modules/.bin/claude
/bin/bash
/usr/bin/ssh
EOF

  export CC_PTY_DEV_DIR="$D/dev"
  export CC_PTY_PS_FILE="$D/ps.txt"
  export CC_PTY_MAX=511
}

@test "1 runs clean and reports the three quantities" {
  run bash "$P"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ptys"* ]] || false
  [[ "$output" == *"sessions"* ]] || false
  [[ "$output" == *"511"* ]]
}

@test "2 --json emits one parseable object with the documented keys" {
  run bash "$P" --json
  [ "$status" -eq 0 ]
  echo "$output" | python3 -c '
import json,sys
d = json.load(sys.stdin)
for k in ("pty_used","pty_max","pty_pct","pty_arch_max","pty_legacy_nodes","sessions","ptys_per_session"):
    assert k in d, "missing key: " + k
'
}

@test "3 counts ONLY the 3-digit ptmx clones — the 16 legacy nodes are excluded" {
  run bash "$P" --json
  [ "$status" -eq 0 ]
  # 2 clones present, 16 legacy present. The naive `ttys*` glob would say 18.
  [[ "$output" == *'"pty_used":2'* ]] || false
  [[ "$output" == *'"pty_legacy_nodes":16'* ]]
}

@test "4 the legacy offset is REPORTED, not silently corrected" {
  # A reader holding an old inflated number must be able to reconcile it from this output alone.
  run bash "$P"
  [ "$status" -eq 0 ]
  [[ "$output" == *"legacy"* ]]
}

@test "5 sessions counted by command POSITION, and ptys/session derived from it" {
  run bash "$P" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"sessions":2'* ]] || false
  [[ "$output" == *'"ptys_per_session":"1.00"'* ]]   # 2 ptys / 2 sessions
}

@test "6a an unreadable limit reports UNKNOWN — never a reassuring 0%" {
  # Caught live during this wave: `sysctl` is in /usr/sbin, which a restricted PATH (hooks, hermetic
  # harnesses) does not carry. The limit read 0 and the gauge printed "0%" — one value meaning both
  # "empty" and "could not ask", which is the fleet's sensor-default-off-ships-blindness shape.
  CC_PTY_MAX=x run bash "$P"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unknown"* ]] || false
  [[ "$output" != *"(0%)"* ]] || false
  CC_PTY_MAX=x run bash "$P" --json
  [[ "$output" == *'"pty_max":null'* ]] || false
  [[ "$output" == *'"pty_pct":null'* ]]
}

@test "6b --assert-under REFUSES while blind (rc 2) — 'could not measure' is not 'under'" {
  CC_PTY_MAX=x run bash "$P" --assert-under 50
  [ "$status" -eq 2 ]
}

@test "6 --assert-under is the ONLY mode that can exit non-zero" {
  # 2 of 511 is 0%. Under 50 ⇒ pass; under 0 ⇒ impossible ⇒ fail. A gauge that always exits 0
  # could never be used by a test, and one that exits non-zero by default would become a gate.
  run bash "$P" --assert-under 50
  [ "$status" -eq 0 ]
  run bash "$P" --assert-under 0
  [ "$status" -eq 1 ]
}

# ── MUTATION CHECKS ───────────────────────────────────────────────────────────────────────────────
# Each neuters ONE behaviour in a copy and asserts a positive test above flips. Without these, every
# assertion here could be true of a script that does nothing.

@test "7 MUTANT: widening the predicate back to ttys* breaks test 3" {
  cp "$P" "$D/mutant.sh"
  # This is precisely the naive census this instrument replaces.
  # Anchored on the CODE site, not the two prose mentions of the same pattern — a mutant that also
  # rewrote the comments would still be a one-site mutation, but the count would stop proving it.
  n=$(grep -c '"\$DEV"/ttys\[0-9\]\[0-9\]\[0-9\]' "$D/mutant.sh")
  [ "$n" -eq 1 ]                      # anchor matches exactly once — a broad mutant proves nothing
  sed -i '' 's|"\$DEV"/ttys\[0-9\]\[0-9\]\[0-9\]|"$DEV"/ttys*|' "$D/mutant.sh"
  bash -n "$D/mutant.sh"              # a mutant that does not parse would red everything vacuously
  run bash "$D/mutant.sh" --json
  [ "$status" -eq 0 ]
  # 2 clones + 16 legacy = 18 — the inflated number, reproduced on demand.
  [[ "$output" == *'"pty_used":18'* ]] || false
  [[ "$output" != *'"pty_used":2'* ]]
}

@test "8 MUTANT: matching argv instead of the comm column breaks test 5" {
  cp "$P" "$D/mutant.sh"
  n=$(grep -c 'if (p\[n\]=="claude") c++' "$D/mutant.sh")
  [ "$n" -eq 1 ]
  # Substring matching is what `pgrep -f` does, and what contaminated the wave A census.
  sed -i '' 's|if (p\[n\]=="claude") c++|if ($0 ~ /claude/) c++|' "$D/mutant.sh"
  bash -n "$D/mutant.sh"
  # A ps snapshot whose rows MENTION claude without being claude — the contamination shape.
  cat > "$D/ps-contaminated.txt" <<'EOF'
/Users/x/.claude-220/node_modules/.bin/claude
/Users/x/.claude-220/node_modules/.bin/claude
/bin/bash
/usr/bin/ssh
EOF
  # A path that merely CONTAINS "claude" but is not the binary.
  echo "/Users/x/.claude/hooks/lead-crash-watchdog.sh" >> "$D/ps-contaminated.txt"
  CC_PTY_PS_FILE="$D/ps-contaminated.txt" run bash "$D/mutant.sh" --json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"sessions":3'* ]] || false # over-counts: the watchdog matched
  CC_PTY_PS_FILE="$D/ps-contaminated.txt" run bash "$P" --json
  [[ "$output" == *'"sessions":2'* ]]         # the real file is immune
}

@test "9 capacity-alarm carries the pty gauge and uses the SAME narrow predicate" {
  # The gauge is embedded in the fleet's capacity readout — the surface that already carries a row
  # per finite resource — so the pty table stops being the one nothing reports. This guards against
  # a later "simplification" back to `ttys*` in the copy the fleet actually reads.
  R="$REPO/scripts/capacity-alarm.sh"
  grep -q 'ttys\[0-9\]\[0-9\]\[0-9\]' "$R"
  ! grep -q 'ls -d /dev/ttys\* ' "$R" || false
  grep -q 'ptys_used' "$R"
  grep -q 'ptys_max' "$R"
}
