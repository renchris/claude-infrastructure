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
#   • it DISCRIMINATES — red on the real scar shapes, green on every legitimate form in the tree.
#     The builtin producer splits ON ITS ARGUMENT and BOTH halves are pinned here: a LITERAL is one
#     bounded write and must stay green (a false red there is as fatal as a miss), while a
#     variable-sourced one is unbounded by inspection and must be red. Until 2026-08-17 test 3
#     asserted the second case GREEN on the strength of a 4 KiB measurement — see test 7;
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

@test "1: the lint's own --selftest passes (30/30, both directions)" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep '30/30' >/dev/null \
    || { echo "selftest count changed — update this assertion deliberately: $output"; false; }
}

@test "2: RED on the ec9a43a9 scar, byte-for-byte" {
  mkfile scar "if \"\$ACCOUNTS_BIN\" -h 2>/dev/null | grep -q -- '--login-status'; then :; fi"
  run census
  printf '%s' "$output" | grep 'scripts/scar.sh:' >/dev/null || { echo "$output"; false; }
}

@test "3: the builtin producer splits on its ARGUMENT — literal GREEN, variable RED" {
  # Until 2026-08-17 this test asserted the variable form GREEN, citing "229 of 367 sites" and the
  # 4 KiB 0/200 measurement. That measurement is of a SIZE, not of a command word: the same printf is
  # 10/10 FALSE once the write passes 64 KiB (test 7). Left as it was, this control certified the bug.
  # Both halves are asserted, because "flags the variable one" alone would also pass against a lint
  # that flagged every builtin producer — which is the false positive the old title feared.
  mkfile lit1 "if printf '%s\\n' 'ready' | grep -q ready; then :; fi"
  mkfile lit2 "if echo done | grep -q done; then :; fi"
  run census
  [ -z "$output" ] || { echo "a pure-LITERAL builtin producer was flagged: $output"; false; }
  rm -f "$FIX/scripts/lit1.sh" "$FIX/scripts/lit2.sh"
  mkfile var1 "if printf '%s' \"\$MSG\" | grep -qE \"\$TELLS\"; then :; fi"
  run census
  printf '%s' "$output" | grep 'scripts/var1.sh:' >/dev/null \
    || { echo "a VARIABLE-sourced builtin producer was not flagged: $output"; false; }
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

@test "7: MECHANISM — the builtin exemption is a SIZE, not a command word (both sides of 64 KiB)" {
  # This is the empirical basis for clause 3's builtin exemption, and for its 2026-08-17 narrowing.
  # The exemption is real BELOW the pipe buffer and false above it, so both arms are asserted: an
  # exemption keyed on `printf`/`echo` alone would be sound on the first and wrong on the second.
  run bash -c 'set -uo pipefail; V="MATCHME$(head -c 4096 /dev/zero | tr "\0" x)"; printf "%s" "$V" | grep -q MATCHME'
  [ "$status" -eq 0 ] || { echo "builtin producer took SIGPIPE at 4 KiB — the exemption is unsound"; false; }

  # A payload well UNDER the pipe buffer still fits one write; 64 KiB does not. The command word
  # cannot decide it — a variable's length is not readable off the line, so the ARGUMENT decides.
  #
  # THIS ARM WAS 63488 AND IT WAS FLAKY, for a reason worth keeping (backlog 418628734437, measured
  # here 2026-08-24 at loadavg 11-15). Two corrections to what this comment used to claim:
  #
  # (1) THE SIZE WAS NOT WHAT IT SAID. `head -c 63488` is 62 KiB of payload, but `fold -w 80` adds
  #     794 newlines and the MATCHME prefix adds 9, so the arm actually wrote 64290 bytes — 1246
  #     under the 65536 buffer, not the ~2 KiB of headroom "62 KB" implies. The arithmetic omitted
  #     the framing it had itself introduced.
  # (2) "Deterministic on this box (0/10 and 10/10), because the boundary is the buffer rather than
  #     a scheduling race" WAS FALSE — measured 9/40 nonzero on this very arm, i.e. it red an
  #     innocent land ~22% of the time. The transition is a GRADED BAND, not a step, which is the
  #     signature of a race and not of a boundary:
  #       writes 60750 -> 1/40 · 62775 -> 3/40 · 64290 -> 9/40 and 12/40 · 64800 -> 12/40
  #       · 65200 -> 6/40 · 65821 -> 120/120
  #     Whether the producer sees EPIPE depends on whether grep exits before the write completes, so
  #     near the buffer it is genuinely probabilistic.
  #
  # 57344 (56 KiB raw -> 58069 bytes written) is 0/120 at loadavg 15.3, with 7.4 KB of margin, and
  # still 14x the 4 KiB arm above — so it proves what this arm exists to prove (the exemption holds
  # for a LARGE sub-buffer payload, not merely a tiny one) without sitting on the cliff. Do not
  # raise it back toward 64 KiB: the band above is where the flake lives. The 128 KB arm below is
  # the one that must fail, and it saturates, so the two arms still bracket the buffer.
  run bash -c 'set -uo pipefail; V="MATCHME
$(head -c 57344 /dev/zero | tr "\0" x | fold -w 80)"; printf "%s\n" "$V" | grep -q MATCHME'
  [ "$status" -eq 0 ] || { echo "builtin producer failed UNDER the pipe buffer (56 KiB) — the literal exemption would be unsound too"; false; }
  run bash -c 'set -uo pipefail; V="MATCHME
$(head -c 131072 /dev/zero | tr "\0" x | fold -w 80)"; printf "%s\n" "$V" | grep -q MATCHME'
  [ "$status" -ne 0 ] || { echo "builtin producer survived 128 KB — clause 3's NARROWING is over-scoped and 127 sites are false positives"; false; }
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

# ── the scan's non-verdict must survive the COMMAND SUBSTITUTION (backlog 57ff249657e0) ──────────
#
# Test 12 above already proved a dead scan exits 2 — but only through `--census`, where scan() runs
# in THIS shell. That is the one entry point where `exit 2` was never in danger, so it stood as a
# vacuous guard for the two that were: `--scan` and `--regen` both read scan through `$( … )`, and
# `exit` cannot leave a command substitution. It ends the subshell and hands back a status, which
# `|| true` discarded. `hits` was then empty — indistinguishable from a clean tree.
#
# Measured on the pre-fix file, 2026-08-14, ROOT=/nonexistent: `--scan` exited 1 (a claim about the
# tree) and named 16 grandfathered files as newly FIXED, none of which the operator had touched.

@test "15: --scan on an unusable ROOT is a NON-VERDICT (exit 2), not a tree claim" {
  run env CC_PIPEFAIL_ROOT=/nonexistent-scan-root bash "$LINT" --scan
  [ "$status" -eq 2 ] || { echo "expected 2 (non-verdict), got $status: $output"; false; }
  printf '%s' "$output" | grep -F 'NON-VERDICT' >/dev/null \
    || { echo "the non-verdict was not announced: $output"; false; }
}

@test "16: a dead scan may never FABRICATE the ratchet's downward half" {
  # The inversion, and the reason this is worse than a lost verdict: against a NON-EMPTY allowlist,
  # empty hits read as cur=0 < alw=N for every grandfathered file, so the lint did not merely fail
  # to judge — it asserted that 16 sites had been fixed, and exited 1 to make it stick.
  run env CC_PIPEFAIL_ROOT=/nonexistent-scan-root bash "$LINT" --scan
  if printf '%s' "$output" | grep -F 'was FIXED but its allowlist count was not lowered' >/dev/null; then
    echo "a dead scan fabricated the downward half — it judged files it never read: $output"; false
  fi
}

@test "17: --regen on an unusable ROOT writes NOTHING (it is invoked as > the allowlist)" {
  # The destructive half, and the one the broken --scan report actively PRESCRIBED: its FIX line
  # says "Regenerate with: … --regen > scripts/pipefail-sigpipe-allow.txt". The shell truncates the
  # destination before the script runs, so on a dead scan the old form wrote four header lines and
  # zero rows at exit 0 — a well-formed allowlist declaring every grandfathered site clean.
  run env CC_PIPEFAIL_ROOT=/nonexistent-scan-root bash "$LINT" --regen
  [ "$status" -eq 2 ] || { echo "expected 2 (non-verdict), got $status: $output"; false; }
  # stdout is what lands in the file; stderr is diagnosis. `run` merges them, so assert on the
  # stream that actually matters, captured on its own.
  env CC_PIPEFAIL_ROOT=/nonexistent-scan-root bash "$LINT" --regen 2>/dev/null > "$BATS_TEST_TMPDIR/regen-dead.txt" || true
  [ ! -s "$BATS_TEST_TMPDIR/regen-dead.txt" ] \
    || { echo "a dead --regen still wrote an allowlist:"; cat "$BATS_TEST_TMPDIR/regen-dead.txt"; false; }
}

@test "18: CONTROL — the healthy tree is unmoved by the non-verdict plumbing" {
  # A guard that could only ever return 2 would be indistinguishable from a broken lint. This pins
  # the other direction: on the real tree, --scan still judges and --regen still reproduces the
  # committed allowlist byte-for-byte (test 14 asserts the content; this asserts they still RUN).
  run bash "$LINT" --scan
  [ "$status" -eq 0 ] || { echo "healthy --scan is no longer green: $status $output"; false; }
  run bash "$LINT" --regen
  [ "$status" -eq 0 ] || { echo "healthy --regen no longer exits 0: $status $output"; false; }
  printf '%s\n' "$output" | grep -v '^#' | awk 'NF' | grep -c . > "$BATS_TEST_TMPDIR/n.txt"
  [ "$(cat "$BATS_TEST_TMPDIR/n.txt")" -gt 0 ] \
    || { echo "healthy --regen produced no rows — the guard is firing on a good tree"; false; }
}
