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
}

# The skip is PER-CASE, never in setup() (2026-08-11, grok-wiki tests shard candidate 1, backlog
# 9ea31151dd94). It used to be the last line of setup(), which skipped ALL 28 cases on a host
# without shellcheck — including the ones below that exist precisely to pin what happens when the
# tool is MISSING. A blanket skip makes the missing-tool contract untestable in the only
# environment where it matters, and that contract is now load-bearing: ship-land's ratchet arm
# routes this lint's exit 2 to GATE_KILLED, so a lint that stopped exiting 2 would silently turn
# the land gate's non-verdict back into the false RED it used to be.
need_sc() { command -v shellcheck >/dev/null 2>&1 || skip "shellcheck not installed"; }

# A bats fixture built with printf — never a heredoc, whose `@test` bats' preprocessor strips.
mkb() { printf '#!/usr/bin/env bats\n%s\n' "$2" > "$D/$1.bats"; }

# ── the lint's own discrimination — a ratchet whose selftest is unverified is not a gate ──────────
@test "--selftest passes: the lint discriminates in both directions" {
  need_sc
  run "$L" --selftest
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '19/19' || false
}

# ── the LINE-scope rule, both directions ─────────────────────────────────────────────────────────
@test "a finding on a line in the own-set BLOCKS" {
  need_sc
  mkb bad '@test "x" {
  foo= bar
}'
  run env CC_BATS_SC_OWN="$D/bad.bats:3" "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'SC1007' || false
  echo "$output" | grep -q 'lines THIS CHANGE WROTE' || false
}

@test "the SAME finding on a line NOT in the own-set is advisory, never blocking" {
  need_sc
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
  need_sc
  # The distinction ${VAR:-} cannot express, and the one the gate relies on when a range fails to
  # resolve: empty must NOT collapse into unset, or an unresolvable range becomes a whole-tree
  # outage on every land.
  mkb bad '@test "x" {
  foo= bar
}'
  run env CC_BATS_SC_OWN="" "$L" "$D/bad.bats"
  [ "$status" -eq 0 ]
}

@test "an ABSENT own-set is a CENSUS — everything is reported, and blamed on nobody" {
  need_sc
  # Naming a target with no own-set means "lint this file", which has no change-set to scope to. The
  # rc is unchanged from when this state was called "strict" — a census of a dirty file is honestly
  # non-zero. What it may NOT do is call those findings the caller's, which is what it used to do:
  # a bare hand-run printed "171 finding(s) … on lines THIS CHANGE WROTE" over the whole corpus.
  mkb bad '@test "x" {
  foo= bar
}'
  run env -u CC_BATS_SC_OWN "$L" "$D/bad.bats"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'CENSUS' || false
  ! echo "$output" | grep -q 'THIS CHANGE WROTE' || false
}

# ── THE BARE RUN — the defect this section exists for ────────────────────────────────────────────
# `bats-shellcheck-lint.sh` with no arguments used to census the whole corpus and word it as a
# verdict: "171 finding(s) above are on lines THIS CHANGE WROTE", naming suites the working tree had
# never touched. Proven a misattribution — stashing the session's only edit left the output
# BYTE-IDENTICAL. No gate was ever wrong (both callers always set CC_BATS_SC_OWN), but bare is the
# natural manual/agent invocation, and a red that fires every single time teaches its reader to skip
# the line that would have named a real regression.
#
# mkrepo builds the smallest tree that can tell the two apart: a suite carrying INHERITED debt on
# trunk, and a second suite added after it. A correct bare run blames only the second.
mkrepo() {  # $1=dir → git tree with the lint at scripts/, dirty trunk suite, and origin/main
  # `git -C ""` is a NO-OP, not an error — an empty $1 would write this identity into the cwd repo.
  : "${1:?mkrepo: repo path required}"
  mkdir -p "$1/scripts" "$1/tests"
  cp "$L" "$1/scripts/lint.sh"; chmod +x "$1/scripts/lint.sh"
  git -C "$1" init -q >/dev/null 2>&1
  git -C "$1" config user.email t@t; git -C "$1" config user.name t
  printf '#!/usr/bin/env bats\n@test "inherited" {\n  old= debt\n}\n' > "$1/tests/inherited.bats"
  git -C "$1" add -A >/dev/null 2>&1; git -C "$1" commit -qm base >/dev/null 2>&1
  # A remote-tracking ref without a remote — the trunk ladder reads refs, not network.
  git -C "$1" update-ref refs/remotes/origin/main HEAD
}

@test "a bare run infers <trunk>...HEAD and blames ONLY what that range wrote" {
  need_sc
  mkrepo "$D/r"
  printf '#!/usr/bin/env bats\n@test "mine" {\n  foo= bar\n}\n' > "$D/r/tests/mine.bats"
  git -C "$D/r" add -A >/dev/null 2>&1; git -C "$D/r" commit -qm mine >/dev/null 2>&1

  run env -u CC_BATS_SC_OWN "$D/r/scripts/lint.sh"
  [ "$status" -eq 1 ]
  # The inferred frame is ANNOUNCED — a guess the reader cannot see is indistinguishable from a fact.
  echo "$output" | grep -q 'inferred own-scope origin/main\.\.\.HEAD' || false
  # It blocks on the line this change really wrote…
  echo "$output" | grep -q 'mine.bats' || false
  echo "$output" | grep -q 'THIS CHANGE WROTE' || false
  # …and the inherited debt sitting on trunk is NOT attributed to the caller. This single assertion
  # is the regression: before the fix, inherited.bats was listed under that same banner.
  ! echo "$output" | grep -q 'inherited.bats' || false
}

@test "a bare run on a branch that wrote no .bats line is GREEN, not a corpus red" {
  need_sc
  mkrepo "$D/r2"
  run env -u CC_BATS_SC_OWN "$D/r2/scripts/lint.sh"
  [ "$status" -eq 0 ]
  # …and it says what the green does NOT cover, so it is never read as "the corpus is clean".
  echo "$output" | grep -q 'census' || false
  ! echo "$output" | grep -q 'THIS CHANGE WROTE' || false
}

@test "a bare run that cannot resolve a trunk REFUSES, rather than inventing a change-set" {
  need_sc
  # The other half of the fix: with no range derivable, reporting the corpus as your work is the
  # same lie in a quieter voice. A non-verdict must be LOUD (exit 2), never a confident red.
  mkrepo "$D/r3"
  git -C "$D/r3" update-ref -d refs/remotes/origin/main
  run env -u CC_BATS_SC_OWN "$D/r3/scripts/lint.sh"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'REFUSING TO GUESS' || false
  ! echo "$output" | grep -q 'THIS CHANGE WROTE' || false
}

@test "--census is the whole-corpus report, and attributes its findings to nobody" {
  need_sc
  mkrepo "$D/r4"
  run env -u CC_BATS_SC_OWN "$D/r4/scripts/lint.sh" --census
  [ "$status" -eq 1 ]                                   # a census of a dirty corpus is honestly non-zero
  echo "$output" | grep -q 'inherited.bats' || false     # it DOES report the debt…
  echo "$output" | grep -q 'attributed to NOBODY' || false
  ! echo "$output" | grep -q 'THIS CHANGE WROTE' || false # …and never calls it yours
}

@test "the own-set and the scan speak one path dialect — an absolute target still matches" {
  need_sc
  # own_lines emits repo-root-relative "tests/f.bats:N". When the scan held ABSOLUTE paths the
  # own-set matched none of them and the run exited "clean — no scanned suite carries a line from
  # this change": a false green, which is the one outcome worse than the false red fixed above.
  # Verified reachable before the normalisation, so this is a regression test, not a hypothetical.
  mkrepo "$D/r5"
  printf '#!/usr/bin/env bats\n@test "mine" {\n  foo= bar\n}\n' > "$D/r5/tests/mine.bats"
  git -C "$D/r5" add -A >/dev/null 2>&1; git -C "$D/r5" commit -qm mine >/dev/null 2>&1
  run env -u CC_BATS_SC_OWN "$D/r5/scripts/lint.sh" --range 'origin/main...HEAD' "$D/r5/tests"
  [ "$status" -eq 1 ]
  echo "$output" | grep -q 'THIS CHANGE WROTE' || false
  ! echo "$output" | grep -q 'no scanned suite carries a line' || false
}

@test "a range git cannot resolve is LOUD — never an empty own-set that reads as clean" {
  need_sc
  # `git rev-parse --verify` cannot validate a RANGE (it returns 1 for every one, valid or not), so
  # the check is `git diff --quiet <range> --`, which answers 128 for a range git cannot resolve.
  # Without it a typo yields an empty own-set, which means "I wrote no line" ⇒ a confident green.
  mkrepo "$D/r6"
  run env -u CC_BATS_SC_OWN "$D/r6/scripts/lint.sh" --range 'no-such-ref...HEAD'
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'NOT a clean verdict' || false
}

@test "an unknown option is a usage error, not a silently-scanned path" {
  need_sc
  run "$L" --no-such-flag
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'unknown option' || false
}

@test "a clean suite is GREEN under every scope" {
  need_sc
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
  need_sc
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
  need_sc
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
  need_sc
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
  need_sc
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
  need_sc
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
  need_sc
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
  need_sc
  cd "$REPO"
  run "$L" --own-lines "HEAD~1..HEAD"
  [ "$status" -eq 0 ]
  # Every emitted token must be tests/<f>.bats:<n> — a malformed token would silently widen or
  # narrow the blocking set.
  ! echo "$output" | grep -vE '^tests/[^:]+\.bats:[0-9]+$' | grep -q . || false
}

@test "--own-lines on a range with no .bats change is EMPTY, not an error" {
  need_sc
  cd "$REPO"
  run "$L" --own-lines "HEAD..HEAD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ── LOUD, never silent-green ─────────────────────────────────────────────────────────────────────
@test "nothing scannable is a NON-VERDICT (exit 2), never a clean verdict" {
  need_sc
  run "$L" "$D/no-such-dir"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'NOT a clean verdict' || false
}

# ── the wiring: a lint enforced only by its own suite is detection, not a gate ───────────────────
@test "the gate calls this lint, with --selftest and an own-scope, and NOT via bash -n" {
  need_sc
  cd "$REPO"
  # Present at the chokepoint…
  grep -q 'bats-shellcheck-lint.sh' scripts/ship-land.sh || false
  # Keyed on the VARIABLE NAME, not the assignment spelling. This read `CC_BATS_SC_OWN=` until the
  # P2 own-scope work routed all thirteen arms through own_run(), which passes the name as an
  # ARGUMENT — so the `=` vanished and this went red. That is the assertion working: the wiring it
  # guards (the gate hands this lint an own-scope) is intact, only its spelling moved.
  grep -q 'CC_BATS_SC_OWN' scripts/ship-land.sh || false
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
  need_sc
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

# ── the MISSING-TOOL contract — the three cases that must NOT skip ───────────────────────────────
# These run the REAL lint with shellcheck genuinely absent, by re-execing it under a PATH that has
# none (`/usr/bin:/bin`; verified in-case, so a future host that ships shellcheck there cannot turn
# these green by accident). They are the half nothing asserted before: the whole suite skipped on a
# host without the tool, so "what does this lint do without it" was pinned nowhere, while
# scripts/ship-land.sh's ratchet arm depends on the answer being exactly `2`.
#
# That reword is not cosmetic. The line above once began with the tool's own name, which shellcheck
# parses as a malformed directive (SC1073) and which stops analysis of the ENTIRE file (SC1072) —
# so this suite went UNANALYZABLE and its 27 cases were checked by nothing. Caught by running this
# very lint over the diff. It is the defect this file exists to ratchet, written into this file.
nosc() { env PATH=/usr/bin:/bin "$@"; }
# A DIRECT file test, not `command -v` under a modified PATH: bash hashes lookups and a builtin
# with a temporary assignment is exactly the shape that answers from the cache. This asks the
# filesystem the same question the stripped PATH will ask.
no_sc_on_stripped_path() {
  if [ -x /usr/bin/shellcheck ] || [ -x /bin/shellcheck ]; then
    skip "this host ships shellcheck in /usr/bin:/bin — the stripped PATH is not stripped"
  fi
}

@test "MISSING TOOL: --selftest is a LOUD exit-2 non-verdict, never a pass and never a RED" {
  # No need_sc: absent is the condition under test, so this case is valid on any host.
  no_sc_on_stripped_path
  run nosc bash "$L" --selftest
  [ "$status" -eq 2 ]                       # 2 = could not run. NOT 0 (a lie) and NOT 1 (a verdict)
  echo "$output" | grep -q 'shellcheck not installed' || false
  echo "$output" | grep -q 'cannot self-verify' || false
}

@test "MISSING TOOL: a SCAN is a LOUD exit-2 non-verdict, never 'clean'" {
  no_sc_on_stripped_path
  mkb clean '@test "x" {
  run true
}'
  run nosc bash "$L" "$D/clean.bats"
  [ "$status" -eq 2 ]
  echo "$output" | grep -q 'NOT a clean verdict' || false
  ! echo "$output" | grep -q 'clean —' || false     # it must never claim the tree is clean
}

@test "MISSING TOOL: --own-lines still WORKS — it parses a diff and needs no shellcheck" {
  # ship-land builds the own-set BEFORE the lint's tool probe can fire, and degrades permissive on
  # an empty one. If --own-lines started exiting 2 with the rest, every shellcheck-less land would
  # silently lose own-scope as well — a second failure hiding inside the first.
  no_sc_on_stripped_path
  cd "$REPO"
  run nosc bash "$L" --own-lines HEAD~1...HEAD
  [ "$status" -eq 0 ]
}
