#!/usr/bin/env bats
# bats-shellcheck-lint — the ratchet that finally puts .bats suites under shellcheck.
#
# WHY THIS SUITE EXISTS AT ALL. The land gate's is_shell_file() matches `*.sh|*.bash` or a shell
# shebang; a bats file's is `#!/usr/bin/env bats`, which matches neither. So no test file in this
# repo had ever been linted — the coverage mechanism behind the 226 dead assertions in
# docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md. Two properties below are the load-bearing ones,
# because getting either wrong makes the gate worse than absent:
#   1. bats files must NEVER join the array that feeds `bash -n` (it fails on all 189 suites).
#   2. Blocking is LINE-scoped. 143 of 189 suites carry a finding, so file-scoped blocking is a
#      fleet-wide hard stop and a file-level grandfather is a permanent exemption list.
#
# Hermetic: every case runs against fixtures in $BATS_TEST_TMPDIR, and $HOME is fixtured, so no
# assertion here reads or writes the operator's live ~/. The two cases that DO touch the real tree
# read it only (a grep over tests/ and over scripts/ship-land.sh).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  L="$REPO/scripts/bats-shellcheck-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  D="$BATS_TEST_TMPDIR"
  if ! command -v shellcheck >/dev/null 2>&1; then skip "shellcheck not installed"; fi
}

# A bats fixture built with printf — never a heredoc, whose `@test` bats' preprocessor strips.
mkb() { printf '#!/usr/bin/env bats\n%s\n' "$2" > "$D/$1.bats"; }

# ── the lint's own discrimination — a ratchet whose selftest is unverified is not a gate ──────────
@test "--selftest passes: the lint discriminates in both directions" {
  run "$L" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '14/14' || false
}

# ── the LINE-scope rule, both directions ─────────────────────────────────────────────────────────
@test "a finding on a line in the own-set BLOCKS" {
  mkb bad '@test "x" {
  foo= bar
}'
  run env CC_BATS_SC_OWN="$D/bad.bats:3" "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'SC1007' || false
  echo "$output" | grep -q 'lines THIS CHANGE WROTE' || false
}

@test "the SAME finding on a line NOT in the own-set is advisory, never blocking" {
  mkb bad '@test "x" {
  foo= bar
}'
  run env CC_BATS_SC_OWN="$D/bad.bats:999" "$L" "$D/bad.bats"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'NOT on a line in your diff' || false
  # …and the finding must NOT be printed as a blocking line
  ! echo "$output" | grep -q 'SHELLCHECK ' || false
}

@test "a SET-BUT-EMPTY own-set means 'I wrote no line' — nothing blocks" {
  # The distinction ${VAR:-} cannot express, and the one the gate relies on when a range fails to
  # resolve: empty must NOT collapse into unset, or an unresolvable range becomes a whole-tree
  # outage on every land.
  mkb bad '@test "x" {
  foo= bar
}'
  run env CC_BATS_SC_OWN="" "$L" "$D/bad.bats"
  [ "$status" -eq 0 ]
}

@test "an ABSENT own-set is strict — a bare hand-run reports the whole truth" {
  mkb bad '@test "x" {
  foo= bar
}'
  run env -u CC_BATS_SC_OWN "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
}

@test "a clean suite is GREEN under every scope" {
  # shellcheck disable=SC2016   # bats source written literally; the $ must not expand here
  mkb ok '@test "x" {
  run true
  [ "$status" -eq 0 ]
}'
  run env -u CC_BATS_SC_OWN "$L" "$D/ok.bats"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '0 blocking finding' || false
}

# ── the third state: a file shellcheck ABORTS on ────────────────────────────────────────────────
# A comment whose first word is `shellcheck` parses as a malformed directive (SC1073) and stops
# analysis of the WHOLE file (SC1072). Such a file yields no line-level findings, so line-scoping
# cannot protect it: a defect added at line 500 would be invisible. It is a NON-VERDICT wearing a
# clean file's clothes.
@test "an UNANALYZABLE file hides a REAL defect — the positive control for the abort" {
  mkb abort '# shellcheck + prose that opens with the tool name
@test "x" {
  foo= bar
}'
  mkb plain '# ShellCheck + the same prose, reworded
@test "x" {
  foo= bar
}'
  # Identical bodies. The only difference is the comment's first word.
  run env -u CC_BATS_SC_OWN "$L" "$D/plain.bats"
  echo "$output" | grep -q 'SC1007' || false        # the defect IS seen when analysis runs
  run env -u CC_BATS_SC_OWN "$L" "$D/abort.bats"
  ! echo "$output" | grep -q 'SC1007' || false       # …and is INVISIBLE when it aborts
  echo "$output" | grep -q 'UNANALYZABLE' || false   # …but the abort itself is never silent
}

@test "an UNANALYZABLE file BLOCKS when this change wrote in it, and never otherwise" {
  mkb abort '# shellcheck + prose that opens with the tool name
@test "x" {
  foo= bar
}'
  run env CC_BATS_SC_OWN="$D/abort.bats:2" "$L" "$D/abort.bats"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'UNANALYZABLE' || false
  # An own-set naming no scanned suite blocks nothing — and says so, rather than exiting a bare 0.
  # (The advisory-report branch for an unanalyzable file OUTSIDE the own-set lives one layer down in
  # lint_files, where --selftest exercises it; the entry point never scans such a file, by design —
  # that is what makes the gate's cost proportional to the diff.)
  run env CC_BATS_SC_OWN="$D/other.bats:2" "$L" "$D/abort.bats"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'UNANALYZABLE' || false
  echo "$output" | grep -qE 'no scanned suite|clean' || false
}

@test "the diff-proportional scope is real — an untouched suite is not even scanned" {
  # The cost property, asserted rather than assumed: a corpus where ONE suite is dirty and another
  # carries the own line must report zero findings, because the dirty one is never opened.
  mkb dirty '@test "x" {
  foo= bar
}'
  # shellcheck disable=SC2016
  mkb mine '@test "x" {
  run true
  [ "$status" -eq 0 ]
}'
  run env CC_BATS_SC_OWN="$D/mine.bats:3" "$L" "$D/dirty.bats" "$D/mine.bats"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -q 'SC1007' || false
  echo "$output" | grep -q '1 suite(s) scanned' || false
}

@test "RATCHET — no suite in tests/ opens a comment with the tool's name" {
  # The one whole-tree invariant this lint asserts. Findings are grandfathered (line-scoped), but an
  # UNANALYZABLE suite silently exempts ITSELF from the rule forever, so this count must stay 0.
  #
  # Asserted by grepping for the CAUSE, not by scanning 189 suites for the symptom. The scan is ~17s
  # at full priority — and this suite runs in Darwin's BACKGROUND QoS band (measured: PRI=4 / NI=19
  # inside bats vs PRI=31 outside, a one-way ratchet children inherit), where at a load average of
  # 30 on 10 cores a third of the corpus exceeded 60s. A test whose cost swings with machine load is
  # an idle-calibrated check that becomes a timeout exactly when the box is busy. grep is
  # milliseconds, and it names the file.
  cd "$REPO"
  bad=""
  for p in tests/*.bats; do
    if grep -E '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]' "$p" 2>/dev/null \
       | grep -qvE '#[[:space:]]*shellcheck[[:space:]]+(disable|enable|shell|source|source-path|external-sources)='; then
      bad="$bad$p"$'\n'
    fi
  done
  [ -z "$bad" ] || {
    printf 'suites whose shellcheck analysis ABORTS (nothing in them is checked):\n%s' "$bad"
    printf 'fix: reword so the comment does not START with the tool name — the parser is case-sensitive,\n'
    printf '     so "# ShellCheck …" is enough.\n'
    return 1
  }
}

# ── the excluded classes: structurally false under bats, not suppressed noise ────────────────────
@test "the bats-structural codes never fire, even under strict scope" {
  # SC2030/SC2031 (every @test body is a subshell), SC2016 (fixtures build source as literal
  # strings), SC2329 (bats' harness invokes setup/helpers), SC1091 (a statement about shellcheck's
  # input set, not the code). Each fixture carries the construct its code covers.
  # shellcheck disable=SC2016
  mkb structural 'setup() { helper() { :; }; }
@test "x" {
  export SEEN=1
  printf '"'"'cat $HOME\n'"'"' > "$D/w.sh"
  . ../hooks/lib/nope.sh
  run true
}'
  run env -u CC_BATS_SC_OWN "$L" "$D/structural.bats"
  [ "$status" -eq 0 ]
}

@test "SC2314/SC2315 are excluded — they are finality-blind and their remedy is forbidden here" {
  # `! cmd` as a body's LAST statement is LIVE (its inverted status becomes the body's), and both
  # codes flag it regardless of position. Measured over tests/: 108 flagged sites against the
  # validated analyzer's 2 genuinely dead ones. Their prescribed fix, `run !`, is the
  # $output-clobbering rewrite §3 of the DoD doc measured and rejected — these negations sit between
  # a `run` and a later assertion on that run's output. Deadness is owned by
  # scripts/bats-assert-liveness.py, which uses bats itself as its oracle and runs at the same gate.
  # Built on ONE line, unlike the other fixtures here: this body contains an assertion-shaped line
  # (`! echo …`), and the liveness analyzer tracks quotes per line, so a MULTI-line single-quoted
  # argument leaves its continuation lines looking like this suite's own code — a false positive on
  # the fixture, and the fixer would then edit the fixture. Any fixture body carrying `!`, `[[ ]]`
  # or `(( ))` belongs on one line for the same reason.
  # shellcheck disable=SC2016
  printf '%s\n' '#!/usr/bin/env bats' '@test "x" {' '  run true' '  [ "$status" -eq 0 ]' '  ! echo "$output" | grep -q nope' '}' > "$D/neg.bats"
  run env -u CC_BATS_SC_OWN "$L" "$D/neg.bats"
  [ "$status" -eq 0 ]
  # …and shellcheck really does flag it, so the exclusion is what keeps this green (not its absence)
  run shellcheck -f gcc "$D/neg.bats"
  echo "$output" | grep -qE 'SC231[45]' || false
}

# ── own_lines: the diff derivation lives in ONE place ───────────────────────────────────────────
@test "--own-lines emits path:line for ADDED lines only, and nothing else" {
  cd "$REPO"
  run "$L" --own-lines "HEAD~1..HEAD"
  [ "$status" -eq 0 ]
  # Every emitted token must be tests/<f>.bats:<n> — a malformed token would silently widen or
  # narrow the blocking set.
  ! echo "$output" | grep -vE '^tests/[^:]+\.bats:[0-9]+$' | grep -q . || false
}

@test "--own-lines on a range with no .bats change is EMPTY, not an error" {
  cd "$REPO"
  run "$L" --own-lines "HEAD..HEAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── LOUD, never silent-green ─────────────────────────────────────────────────────────────────────
@test "nothing scannable is a NON-VERDICT (exit 2), never a clean verdict" {
  run "$L" "$D/no-such-dir"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'NOT a clean verdict' || false
}

# ── the wiring: a lint enforced only by its own suite is detection, not a gate ───────────────────
@test "the gate calls this lint, with --selftest and an own-scope, and NOT via bash -n" {
  cd "$REPO"
  # Present at the chokepoint…
  grep -q 'bats-shellcheck-lint.sh' scripts/ship-land.sh || false
  grep -q 'CC_BATS_SC_OWN=' scripts/ship-land.sh || false
  grep -q 'SC_BATS_LINT" --selftest' scripts/ship-land.sh || false
  # …and at the task-quality-gate hook.
  grep -q 'bats-shellcheck-lint.sh' hooks/task-quality-gate.sh || false
  # THE INVARIANT that keeps the gate landable: is_shell_file() must not claim .bats, because every
  # match is handed to `bash -n`, which fails on all 189 suites. If a future change widens it, this
  # fails here rather than turning every test-touching land red.
  run bash -c 'source_fn() { sed -n "/^is_shell_file()/,/^}/p" scripts/ship-land.sh; }; source_fn'
  ! echo "$output" | grep -q 'bats' || false
}

@test "bash -n really does fail on a bats file — the reason .bats stays out of \$shellfiles" {
  # Pins the measurement the design rests on, so nobody re-litigates it from intuition.
  # shellcheck disable=SC2016
  mkb any '@test "x" {
  run true
}'
  run bash -n "$D/any.bats"
  [ "$status" -ne 0 ]
  cd "$REPO"
  run bash -n tests/bats-shellcheck-lint.bats
  [ "$status" -ne 0 ]
}
