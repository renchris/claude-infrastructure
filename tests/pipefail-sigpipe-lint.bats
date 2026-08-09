#!/usr/bin/env bats
# pipefail-sigpipe-lint — the RATCHET that stops `producer | early-exit-consumer` under pipefail.
#
# The scar is in-tree history: cc-relogin-poll's capability probe was
#     if "$ACCOUNTS_BIN" -h 2>/dev/null | grep -q -- '--login-status'; then
# and `ec9a43a9` fixed it. `grep -q` exits on the match, the producer takes SIGPIPE on its next
# write, and pipefail promotes that 141 — so the `if` reads FALSE for a flag that IS advertised.
# The poller exited 3 DETECTION-UNAVAILABLE with the surface in front of it, and separately faked a
# WINDOW-CAPPED that narrowed a declared T-7d window to 72h. Both were misread as deploy lag.
#
# Four properties are proved here, and all four matter:
#   • it DISCRIMINATES — red on the real scar shapes, green on every legitimate form in the tree
#     (the builtin-producer form is 229 of the 367 status-consuming sites; flagging it would make
#     the lint unusable, so a false positive there is as fatal as a miss);
#   • the MECHANISM is real and the FIX repairs it — asserted by running actual bash, not by
#     re-reading the detector. A lint for a race nobody re-measures is a lint for a rumour;
#   • it is GREEN on the tree as it stands — a lint that ships standing-red is rot, and the nightly
#     runs every scripts/*lint*.sh, so a false red here poisons the whole nightly signal;
#   • it is WIRED AT THE CHOKEPOINT — enforcement by its own suite alone is detection, not a gate
#     (memory: enforcement-must-live-at-the-chokepoint), so run_gate must invoke it.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/pipefail-sigpipe-lint.sh"
  ALLOW="$REPO/scripts/pipefail-sigpipe-allow.txt"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # dogfood the sibling hermeticity rule
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX/scripts"
}

mkfile() { # $1=name $2=body  [$3=set line]
  { echo '#!/bin/bash'; echo "${3:-set -euo pipefail}"; printf '%s\n' "$2"; } > "$FIX/scripts/$1.sh"
}
census() { CC_PIPEFAIL_ROOT="$FIX" CC_PIPEFAIL_ALLOWLIST=/dev/null bash "$LINT" --census 2>/dev/null; }

@test "1: the lint's own --selftest passes (24/24, both directions)" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep '24/24' >/dev/null \
    || { echo "selftest count changed — update this assertion deliberately: $output"; false; }
}

@test "2: RED on the ec9a43a9 scar, byte-for-byte" {
  mkfile scar "if \"\$ACCOUNTS_BIN\" -h 2>/dev/null | grep -q -- '--login-status'; then :; fi"
  run census
  printf '%s' "$output" | grep 'scripts/scar.sh:' >/dev/null || { echo "$output"; false; }
}

@test "3: GREEN on the builtin-producer form (229 of 367 sites — a false red here is fatal)" {
  mkfile ok1 "if printf '%s' \"\$MSG\" | grep -qE \"\$TELLS\"; then :; fi"
  run census
  [ -z "$output" ] || { echo "unexpected hit: $output"; false; }
}

@test "4: GREEN on both canonical fixes (drained grep, and awk NR<=N for head -N)" {
  mkfile fix1 "if git status --porcelain | grep . >/dev/null; then :; fi"
  mkfile fix2 "v=\$(git log --oneline | awk 'NR<=1')"
  run census
  [ -z "$output" ] || { echo "a FIX was flagged as a violation: $output"; false; }
}

@test "5: GREEN on the neutralise fix — { p || true; } keeps the early exit" {
  mkfile fix3 "{ strings -a \"\$b\" 2>/dev/null || true; } | grep -q 'X' && return 0" 'set -uo pipefail'
  run census
  [ -z "$output" ] || { echo "the neutralise idiom was flagged: $output"; false; }
}

@test "6: MECHANISM — the scar really does read FALSE on a match, and the fix really repairs it" {
  # Not a re-read of the detector: real bash, real SIGPIPE, real pipefail. The producer must still
  # be writing when the consumer exits, so the payload after the match is what makes it fire.
  seq 1 200000 > "$BATS_TEST_TMPDIR/big.txt"
  run bash -c "set -uo pipefail; cat '$BATS_TEST_TMPDIR/big.txt' | grep -q '^1\$'"
  [ "$status" -ne 0 ] || { echo "the defect did NOT reproduce — this suite proves nothing"; false; }
  run bash -c "set -uo pipefail; cat '$BATS_TEST_TMPDIR/big.txt' | grep '^1\$' >/dev/null"
  [ "$status" -eq 0 ] || { echo "the drain fix did not repair the pipeline (status=$status)"; false; }
  run bash -c "set -uo pipefail; { cat '$BATS_TEST_TMPDIR/big.txt' || true; } | grep -q '^1\$'"
  [ "$status" -eq 0 ] || { echo "the neutralise fix did not repair the pipeline (status=$status)"; false; }
  # and the fix must still be able to say NO
  run bash -c "set -uo pipefail; cat '$BATS_TEST_TMPDIR/big.txt' | grep '^NOPE\$' >/dev/null"
  [ "$status" -ne 0 ] || { echo "the fix returns TRUE on a non-match — it is not a predicate"; false; }
}

@test "7: MECHANISM — a single-write builtin producer is genuinely safe (why clause 3 exempts it)" {
  # This is the empirical basis for the biggest exemption in the rule. If it ever stops holding,
  # the exemption is wrong and this test is the thing that says so.
  run bash -c 'set -uo pipefail; V="MATCHME$(head -c 4096 /dev/zero | tr "\0" x)"; printf "%s" "$V" | grep -q MATCHME'
  [ "$status" -eq 0 ] || { echo "builtin producer took SIGPIPE at 4 KiB — clause 3 is unsound"; false; }
}

@test "8: the tree as it stands is GREEN against the committed allowlist" {
  run bash "$LINT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "9: the ratchet blocks a NEW violation in an allowlisted file" {
  # A bare path allowlist would exempt the whole file; the count is what keeps protecting it.
  local first count tmp
  first="$(awk -F'\t' '!/^#/ && NF>=2 {print $1; exit}' "$ALLOW")"
  count="$(awk -F'\t' -v p="$first" '$1==p {print $2}' "$ALLOW")"
  tmp="$BATS_TEST_TMPDIR/allow.txt"
  awk -F'\t' -v p="$first" -v n="$((count-1))" \
    'BEGIN{OFS="\t"} !/^#/ && NF>=2 && $1==p {$2=n} {print}' "$ALLOW" > "$tmp"
  run env CC_PIPEFAIL_ALLOWLIST="$tmp" bash "$LINT"
  [ "$status" -eq 1 ] || { echo "a file over its allowlisted count did not go RED: $output"; false; }
}

@test "10: the DOWNWARD half fires — fixing a site without lowering the count is RED" {
  # Without this, the allowlist silently becomes a permanent exemption list.
  local first count tmp
  first="$(awk -F'\t' '!/^#/ && NF>=2 {print $1; exit}' "$ALLOW")"
  count="$(awk -F'\t' -v p="$first" '$1==p {print $2}' "$ALLOW")"
  tmp="$BATS_TEST_TMPDIR/allow2.txt"
  awk -F'\t' -v p="$first" -v n="$((count+1))" \
    'BEGIN{OFS="\t"} !/^#/ && NF>=2 && $1==p {$2=n} {print}' "$ALLOW" > "$tmp"
  run env CC_PIPEFAIL_ALLOWLIST="$tmp" bash "$LINT"
  [ "$status" -eq 1 ] || { echo "a fixed-but-not-delisted file did not go RED: $output"; false; }
  printf '%s' "$output" | grep 'was FIXED' >/dev/null \
    || { echo "the downward message did not name the cause: $output"; false; }
}

@test "11: own-scope narrows what BLOCKS without narrowing what is REPORTED" {
  local first tmp
  first="$(awk -F'\t' '!/^#/ && NF>=2 {print $1; exit}' "$ALLOW")"
  tmp="$BATS_TEST_TMPDIR/allow3.txt"
  awk -F'\t' -v p="$first" 'BEGIN{OFS="\t"} !/^#/ && NF>=2 && $1==p {$2=0} {print}' "$ALLOW" > "$tmp"
  # not in this land's diff ⇒ advisory, exit 0
  run env CC_PIPEFAIL_ALLOWLIST="$tmp" CC_PIPEFAIL_OWN="some/other/file.sh" bash "$LINT"
  [ "$status" -eq 0 ] || { echo "an out-of-land file BLOCKED: $output"; false; }
  # in this land's diff ⇒ blocking, exit 1
  run env CC_PIPEFAIL_ALLOWLIST="$tmp" CC_PIPEFAIL_OWN="$first" bash "$LINT"
  [ "$status" -eq 1 ] || { echo "an in-land file did not block: $output"; false; }
}

@test "12: a broken detector is a LOUD non-verdict (exit 2), never a clean tree" {
  # This failure actually happened while writing the lint: one apostrophe inside the single-quoted
  # awk string truncated the program, and --census printed 0 sites. A silent-green detector is
  # strictly worse than no detector, so it must be impossible to reach.
  local broken="$BATS_TEST_TMPDIR/broken.sh"
  sed "s/^DETECT_AWK='/DETECT_AWK='function bad( { syntax error here/" "$LINT" > "$broken"
  run bash "$broken" --census
  [ "$status" -eq 2 ] || { echo "a broken detector exited $status, not 2: $output"; false; }
}

@test "13: WIRED AT THE CHOKEPOINT — ship-land's run_gate invokes the lint" {
  # A lint enforced only by its own suite is post-hoc detection: gate-select will not pick this
  # suite up when the edited file is a PRODUCER rather than the lint.
  grep 'pipefail-sigpipe-lint' "$REPO/scripts/ship-land.sh" >/dev/null \
    || { echo "ship-land.sh does not invoke pipefail-sigpipe-lint — the ratchet is not a gate"; false; }
}

@test "14: the allowlist may only ever SHRINK — it is regenerable from the tree" {
  run bash "$LINT" --regen
  [ "$status" -eq 0 ]
  # regen must reproduce the committed list exactly, or the committed list is stale
  printf '%s\n' "$output" | grep -v '^#' | awk 'NF' > "$BATS_TEST_TMPDIR/regen.txt"
  grep -v '^#' "$ALLOW" | awk 'NF' > "$BATS_TEST_TMPDIR/committed.txt"
  run diff -u "$BATS_TEST_TMPDIR/committed.txt" "$BATS_TEST_TMPDIR/regen.txt"
  [ "$status" -eq 0 ] || { echo "committed allowlist is stale vs the tree:"; echo "$output"; false; }
}
