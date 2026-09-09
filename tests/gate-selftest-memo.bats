#!/usr/bin/env bats
# gate-selftest-memo.bats — the `--selftest` preamble memo (Tier 0 of the ratchet-arm memo rollout).
#
# WHAT IS BEING PINNED. Ten of run_gate's eleven `--selftest` preambles are unconditional and re-run
# on EVERY round of EVERY land. Measured 2026-09-09 over 294 land.log rows: the ratchet arms are
# 71.5% of all gate time at a median 623s/round, and 149 of the 294 rounds (50.6%) were exit-42
# stale re-rounds that burned 34.1h of arms for ZERO lands. A `--selftest` runs the lint against its
# OWN EMBEDDED FIXTURES in a mktemp sandbox, so its verdict is a pure function of the lint's blob
# plus the interpreters already in gate-memo's salt — the soundest key in the gate.
#
# THE FAILURE DIRECTION IS THE WHOLE POINT. A memoized selftest that returns a green it did not
# earn does not merely cost seconds — it retires the proof that the DETECTOR still discriminates,
# which is the one thing standing between a stale lint and a clean-looking gate. So the cases that
# matter here are the ones where the memo must NOT carry: a mutated lint, a failing selftest, a
# non-verdict rc 2, and the one lint deliberately excluded from the tier.
#
# EXECUTIONS ARE COUNTED, NEVER GREPPED FOR A PHRASE. Each stub lint appends one line per
# `--selftest` invocation to a log outside the fixture repo; "it was skipped" is asserted as a count
# that did not move. A phrase-grep would pass just as well for a memo that is silently OFF.
#
# CASE 1 IS A POSITIVE CONTROL AND COMES FIRST BY CONSTRUCTION. memo_init refuses on a dirty tree,
# an unresolvable git dir or a broken hasher — all of which read as "nothing to carry". A suite
# whose memo never armed would pass every skip-assertion below by never skipping. Case 1 proves the
# memo ARMS before anything else claims it behaves, and case 2 is its vacuous-pass control.
#
# TWO CONTROLS, BOTH RUN AND BOTH RECORDED — because either alone attributes nothing.
#
#   A. THE PRE-FIX TREE (`git checkout HEAD~ -- scripts/ship-land.sh`, no selftest_ok at all).
#      Measured 2026-09-09: 1, 3, 4, 7 RED · 2, 5, 6, 8 green. The greens are the cases that must
#      hold with or without a memo, so their staying green is the evidence they are not part of the
#      claim; the four reds are what this suite adds.
#
#   B. THE NAIVE MUTANT — tests/fixtures/gate-memo-naive.sh, a memo keyed on the PATH ALONE with no
#      blob and no salt, treating mere existence as green. Run with
#      CC_MEMO_LIB=tests/fixtures/gate-memo-naive.sh. Measured 2026-09-09: 3, 4, 8 RED · the rest
#      green. Case 8 is the one that matters — the path-only key LAUNDERED A RED INTO A GREEN,
#      carrying the old blob's proof across the edit that broke the detector. That is the failure
#      this whole tier is a hair away from, and it is what attributes cases 3/4/8 to the BLOB key
#      rather than to the memo merely existing (memory: per-site-mutation-attributes-coverage).
#
# A suite that only ran control A would credit the blob key for a skip any cache would deliver; one
# that only ran control B would never prove the fix does anything at all.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO/scripts/ship-land.sh"
  export SHIP_LAND_MEMO_LIB="$REPO/${CC_MEMO_LIB:-scripts/lib/gate-memo.sh}"

  export HOME="$BATS_TEST_TMPDIR/home"      # hermeticity: never the operator's live ~
  mkdir -p "$HOME"
  # Identity through the ENVIRONMENT, never `git config user.email` — this repo is one bare git dir
  # shared by ~100 linked worktrees, so a bare `git config` in a fixture re-authors every session on
  # the box. The env form cannot persist anywhere.
  export GIT_AUTHOR_NAME=tester GIT_AUTHOR_EMAIL=tester@example.com
  export GIT_COMMITTER_NAME=tester GIT_COMMITTER_EMAIL=tester@example.com

  # THE LOGS AND THE RC SWITCH LIVE OUTSIDE THE FIXTURE REPO, deliberately. Inside it they would
  # dirty the tree (memo_init refuses on a dirty tree, so every case would go vacuous) and a stub's
  # rc switch would move its own blob, which is the one variable the mutation cases must own alone.
  UTC_LOG="$BATS_TEST_TMPDIR/utc-selftest.log"
  UTC_RC="$BATS_TEST_TMPDIR/utc-selftest.rc"
  UNATT_LOG="$BATS_TEST_TMPDIR/unatt-selftest.log"
  : > "$UTC_LOG"; : > "$UNATT_LOG"; echo 0 > "$UTC_RC"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || return 1
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m base
  git push -q -u origin main

  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export LAND_LOCK_WAIT=10
  export SHIP_LAND_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export SHIP_LAND_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/nope"
  export CLAUDE_CODE_SESSION_ID="test-sid-selftest-memo"
  export POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export POSTLAND_VERIFY=off
  export SHIP_LAND_FAILURE_INBOX=off
  export CC_GATE_MAX_LOAD=0
  # Same env-bleed immunity as the sibling gate suites: when THIS suite runs inside an outer land,
  # the outer pipeline's tuning must not decide a fixture pipeline's verdict.
  unset SHIP_LAND_GATE_SCOPE SHIP_LAND_GATE_SCOPE_DEFAULT SHIP_LAND_GATE_POLICY \
        SHIP_LAND_GATE_SELECT SHIP_LAND_FIRST_BASE SHIP_LAND_GATE_EFFECTIVE_FULL \
        SHIP_LAND_SELECTED_N POSTLAND_STALENESS_GUARD \
        SHIP_LAND_GATE_ROUNDS SHIP_LAND_VERIFY_RETRIES \
        SHIP_LAND_LANE SHIP_LAND_SMOKE_BUDGET_S SHIP_LAND_SMOKE_NICE SHIP_LAND_TIMEOUT_BIN \
        SHIP_LAND_SMOKE_PER_SUITE_S SHIP_LAND_SMOKE_BUDGET_CAP_S \
        SHIP_LAND_SMOKE_STATE SHIP_LAND_SMOKE_N SHIP_LAND_SMOKE_S SHIP_LAND_NET_STATE \
        SHIP_LAND_BACKUP_REF SHIP_BACKUP_REAP SHIP_LAND_MEMO \
        2>/dev/null || true

  # THE STUB LINTS ARE TRACKED FILES IN THE FIXTURE REPO. They have to be: the memo keys on the blob
  # of the file on disk and refuses to arm at all on a dirty tree, so a mutation case has to be able
  # to change a stub AND leave the tree clean.
  mkdir -p scripts
  write_utc_stub "the original"
  {
    echo '#!/usr/bin/env bash'
    echo 'case "$1" in'
    echo "  --print-scope) echo 'scripts/*'; exit 0 ;;"
    echo "  --selftest)    echo run >> \"$UNATT_LOG\"; exit 0 ;;"
    echo 'esac'
    echo 'exit 0'
  } > scripts/unatt-stub.sh
  chmod +x scripts/utc-stub.sh scripts/unatt-stub.sh
  # The unattended arm is gated on `[[ -d hooks ]] || [[ -d launchd ]]` (ship-land.sh, its arm
  # header). Without one of those the arm never fires and the exclusion case below asserts nothing.
  mkdir -p hooks
  printf '#!/usr/bin/env bash\nexit 0\n' > hooks/noop.sh
  chmod +x hooks/noop.sh
  git add scripts/utc-stub.sh scripts/unatt-stub.sh hooks/noop.sh
  git commit -q -m "test: selftest-memo stubs"

  git checkout -q -b feat/selftest-memo main
  printf '#!/usr/bin/env bash\necho hello\n' > scripts/hello.sh
  git add scripts/hello.sh && git commit -q -m "feat: hello"

  export SHIP_LAND_UTC_LINT="$WORK/scripts/utc-stub.sh"
  export SHIP_LAND_UNATTENDED_LINT="$WORK/scripts/unatt-stub.sh"
}

write_utc_stub() {  # $1 = a marker that changes the stub's BYTES and nothing else
  {
    echo '#!/usr/bin/env bash'
    echo "# marker: $1"
    echo 'case "$1" in'
    echo "  --print-scope) echo 'scripts/*'; exit 0 ;;"
    echo "  --selftest)    echo run >> \"$UTC_LOG\"; exit \"\$(cat \"$UTC_RC\")\" ;;"
    echo 'esac'
    echo 'exit 0'
  } > scripts/utc-stub.sh
  chmod +x scripts/utc-stub.sh
}

precheck()   { run bash "$SHIPLAND" --precheck --trunk main; }
# ONE value, ALWAYS. `grep -c . f || echo 0` prints "0" AND exits 1 on an empty file, so the `||`
# fires and the caller receives "0\n0" — which `[ … -eq 1 ]` reports as "integer expected", a red
# that reads like a logic defect and is really the instrument.
utc_runs()   { awk 'END{print NR}' "$UTC_LOG"   2>/dev/null; }
unatt_runs() { awk 'END{print NR}' "$UNATT_LOG" 2>/dev/null; }

# -- 1. the memo arms and carries -----------------------------------------------------------------

@test "POSITIVE CONTROL: the memo arms, and a second gate over an UNCHANGED lint SKIPS its selftest" {
  precheck
  [ "$status" -eq 0 ]
  [ "$(utc_runs)" -eq 1 ]                       # cold: it ran, and was recorded
  printf '%s\n' "$output" | grep -F "selftest memo" >/dev/null \
    || { echo "MEMO NEVER ARMED — every skip-assertion in this suite would be vacuous"; return 1; }

  precheck
  [ "$status" -eq 0 ]
  [ "$(utc_runs)" -eq 1 ]                       # THE ASSERTION: it did not run a second time
  printf '%s\n' "$output" | grep -E "selftest memo — [1-9][0-9]* detector proof" >/dev/null
}

@test "VACUOUS-PASS CONTROL: with SHIP_LAND_MEMO=off the second gate runs the selftest AGAIN" {
  # Without this, "the count did not move" would pass just as well for a stub that is never invoked
  # at all — a memo silently OFF and a memo with nothing to carry look identical from the outside.
  # gate-memo.sh already shipped that exact defect once (memo_batch_hit's read-at-EOF bug made
  # EVERY lookup a miss) and only a positive control found it.
  SHIP_LAND_MEMO=off precheck
  [ "$status" -eq 0 ]
  [ "$(utc_runs)" -eq 1 ]
  SHIP_LAND_MEMO=off precheck
  [ "$status" -eq 0 ]
  [ "$(utc_runs)" -eq 2 ]
}

# -- 2. THE RED HALF: the key tracks CONTENT ------------------------------------------------------

@test "THE RED HALF: changing the lint's BYTES makes the selftest RUN AGAIN" {
  # This is the case that would launder a red. A key too coarse to see the lint's own edit would
  # carry a stale "the detector discriminates" proof across the edit that broke the detector.
  precheck
  [ "$status" -eq 0 ]
  [ "$(utc_runs)" -eq 1 ]
  precheck
  [ "$(utc_runs)" -eq 1 ]                       # warm, unchanged => carried

  write_utc_stub "MUTATED — one comment line, nothing else"
  git add scripts/utc-stub.sh && git commit -q -m "test: mutate the stub lint"
  precheck
  [ "$status" -eq 0 ]
  [ "$(utc_runs)" -eq 2 ]                       # THE ASSERTION: the mutation convicted the memo
}

@test "the key is the CONTENT, not the path or the mtime: reverting byte-for-byte restores the carry" {
  precheck
  [ "$(utc_runs)" -eq 1 ]
  write_utc_stub "MUTATED"
  git add scripts/utc-stub.sh && git commit -q -m "test: mutate"
  precheck
  [ "$(utc_runs)" -eq 2 ]

  write_utc_stub "the original"                 # byte-identical to the version that earned green
  git add scripts/utc-stub.sh && git commit -q -m "test: revert"
  touch scripts/utc-stub.sh                     # a NEW mtime over the ORIGINAL bytes
  precheck
  [ "$status" -eq 0 ]
  [ "$(utc_runs)" -eq 2 ]                       # carried again — the original blob's green stands
}

# -- 3. a red is never cached, and a non-verdict stays a non-verdict ------------------------------

@test "a FAILING selftest is never cached — it re-runs and re-reds on the identical tree" {
  echo 1 > "$UTC_RC"
  precheck
  [ "$status" -eq 6 ]
  printf '%s\n' "$output" | grep -F "utc-stamp-lint --selftest FAILED" >/dev/null
  [ "$(utc_runs)" -eq 1 ]

  precheck                                       # identical tree, identical blob
  [ "$status" -eq 6 ]
  printf '%s\n' "$output" | grep -F "utc-stamp-lint --selftest FAILED" >/dev/null
  [ "$(utc_runs)" -eq 2 ]                        # it RAN again and printed its own finding
}

@test "a selftest rc is returned UNCHANGED: bats-shellcheck rc 2 stays a NON-VERDICT (9), not a red (6)" {
  # selftest_ok returns the lint's own rc rather than a boolean, because this one call site
  # discriminates 2 from 1. Collapsing them would report "your tree is bad" for a lint that never
  # rendered a verdict — arm_nonverdict's whole reason for existing.
  {
    echo '#!/usr/bin/env bash'
    echo 'case "$1" in --own-lines) exit 0 ;; --print-scope) echo "tests/*"; exit 0 ;; esac'
    echo 'echo "stub: cannot self-verify" >&2'
    echo 'exit 2'
  } > "$BATS_TEST_TMPDIR/batsc-stub.sh"
  chmod +x "$BATS_TEST_TMPDIR/batsc-stub.sh"
  mkdir -p tests && printf '#!/usr/bin/env bats\n@test "x" { true; }\n' > tests/zz.bats
  git add tests/zz.bats && git commit -q -m "test: a suite for the bats arm to reach"

  run env SHIP_LAND_BATS_SC_LINT="$BATS_TEST_TMPDIR/batsc-stub.sh" \
      bash "$SHIPLAND" --precheck --trunk main
  [ "$status" -eq 9 ]
  printf '%s\n' "$output" | grep -F "GATE-KILLED" >/dev/null
  # `|| false` is not decoration: errexit does not evaluate an inverted rc, so a bare `! cmd` that is
  # not the LAST line of the test always passes and asserts nothing (memory:
  # negated-assertion-dead-unless-final; the gate's own dead-assertion ratchet convicts it).
  ! printf '%s\n' "$output" | grep -F "GATE RED" >/dev/null || false
}

# -- 4. the deliberate exclusion ------------------------------------------------------------------

@test "unattended-path-lint is EXCLUDED: its selftest runs on EVERY round, memo warm or not" {
  # Not an oversight — a tripwire. That lint's selftest verdict is a function of the invoker's
  # environment as well as its blob (installed_anywhere() probes ${PATH} and three $HOME dirs,
  # unattended-path-lint.sh:999; its own header records --selftest FAILING 2/23 for a caller without
  # /sbin and passing 23/23 for one with it). A blob-only key would carry a green earned under one
  # environment into another. If someone later "completes" the tier by memoizing it, this case goes
  # red and the comment tells them why.
  precheck
  [ "$status" -eq 0 ]
  [ "$(unatt_runs)" -eq 1 ]
  precheck
  [ "$status" -eq 0 ]
  [ "$(unatt_runs)" -eq 2 ]                      # ran again over the identical blob, by design
  [ "$(utc_runs)" -eq 1 ]                        # ...while the memoized sibling did NOT
}

# -- 5. the memo changes no verdict ---------------------------------------------------------------

@test "a warm gate reaches the SAME exit code as a cold one, green and red" {
  # GREEN, cold vs warm.
  SHIP_LAND_MEMO=off precheck; [ "$status" -eq 0 ]
  precheck; [ "$status" -eq 0 ]
  precheck; [ "$status" -eq 0 ]

  # RED, cold vs warm — and the red arrives as a NEW BLOB, never as an out-of-band switch over the
  # blob that already earned green. A green earned for a blob IS honoured for that blob; that is the
  # contract, not a defect, and a fixture that flips a hidden rc file would be testing an input the
  # real selftests do not have.
  echo 1 > "$UTC_RC"
  write_utc_stub "a lint whose detector no longer discriminates"
  git add scripts/utc-stub.sh && git commit -q -m "test: break the detector"
  SHIP_LAND_MEMO=off precheck
  cold_red="$status"
  [ "$cold_red" -eq 6 ]
  precheck
  [ "$status" -eq "$cold_red" ]                  # the memo cannot launder a red into a green
  precheck
  [ "$status" -eq "$cold_red" ]                  # …and still cannot, a round later
}
