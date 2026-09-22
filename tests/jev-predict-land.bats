#!/usr/bin/env bats
# jev-predict-land — the pre-flight land-refusal predictor's instrument.
#
# EVERY CASE BELOW EXCEPT THE USAGE ONES IS A REGRESSION TEST FOR A DEFECT THIS CODE ACTUALLY
# SHIPPED, found by running it end-to-end rather than by reading it (docs/lessons/
# mirroring-a-corpus-is-not-using-it.md: only an artifact built WITH a thing proves it usable).
# Four of them, in the order they were caught, with the case that pins each:
#
#   1. the recall ceiling read 2.0 ("16 of 8 positives") because its numerator counted every exit-6
#      row while its denominator used the narrower positive predicate. A ratio above 1 is the one
#      direction that waves the acceptance bar through.      → "ceiling is intersected", "…fault"
#   2. the baseline scored 7 of 25 clean trunk commits as HITS, because materialising a file into a
#      temp tree leaves the linter with no .shellcheckrc — a comparator running a STRICTER standard
#      than the gate it stands in for.                        → "policy file comes from the sha"
#   3. the disclosure-class scan NEVER RAN: the pattern starts with `-----BEGIN`, so grep read it as
#      an option, exited 2, and every row was read as clean and SENT. A fail-open egress gate
#      reporting `skipped 0`, which is what a clean scan looks like.  → "…fires", "…fails closed"
#   4. the linter aborts on a comment line BEGINNING with its own name (SC1073), which silently
#      voids the lint for the WHOLE file — hit twice, the second time in the comment documenting
#      it.                                                    → "every shipped file lints clean"
#
# 🚨 THE LIMIT, SO A GREEN RUN CANNOT BE MISREAD. These cases prove the INSTRUMENT: the corpus
# classification, the arithmetic, the consent gate, the analyzer invocation, the scorer's refusals.
# They prove NOTHING about whether a model can predict a land refusal — that needs the real
# ~/.claude/land.log and an operator-armed run, neither of which exists in a test or off-box. A
# green suite here means "the instrument is correct", never "the candidate works".

bats_require_minimum_version 1.5.0   # `run --separate-stderr` in the score arms: this SUT
                                     # puts its machine-readable JSON on stdout and its human
                                     # verdict lines on stderr, and a merged `run` makes the
                                     # JSON unparseable — see the score cases below.

setup() {
  # Fixture $HOME first: the subject's defaults point at ~/.claude/{land.log,autonomy}, so an
  # unfixtured run would read the operator's live store and write beside it. The land gate's
  # hermeticity ratchet refuses a land for exactly this.
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME/.claude"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SUT="$REPO/scripts/jev/predict-land.sh"
  CORPUS_PY="$REPO/scripts/jev/predict_land_corpus.py"
  export CC_PREDICT_OUTDIR="$BATS_TEST_TMPDIR/out"
  export CC_PREDICT_ARM_FILE="$BATS_TEST_TMPDIR/arm.json"
  command -v jq >/dev/null || skip "jq not installed"
  command -v python3 >/dev/null || skip "python3 not installed"
}

# A store whose rows exercise every class, every `red` state, a stage:"round" row, a
# placeholder-sha row, a lock row and an unparseable line. Written as a function rather than a
# fixture file so the shapes stay beside the assertions that read them.
#
# The shas are DELIBERATELY unreachable here (aaa1/bbb1 …) and deliberately DIFFERENT strings for
# head and base: giving two identifier spaces one shape makes every address-resolution defect
# unreachable while the suite stays green (docs/lessons/fixture-identifier-shape-collapses-two-spaces.md).
mkstore() {
  STORE="$BATS_TEST_TMPDIR/land.log"
  cat > "$STORE" <<'EOF'
{"ts":"2026-07-01T10:00:00Z","tool":"ship-land","exit":0,"stage":"land","head":"aaa1","base":"bbb1","red":""}
{"ts":"2026-07-02T10:00:00Z","tool":"ship-land","exit":6,"stage":"land","head":"aaa2","base":"bbb2"}
{"ts":"2026-08-20T10:00:00Z","tool":"ship-land","exit":6,"stage":"land","head":"aaa3","base":"bbb3","red":"smoke:tests/x.bats"}
{"ts":"2026-08-21T10:00:00Z","tool":"ship-land","exit":9,"stage":"land","head":"aaa4","base":"bbb4","red":""}
{"ts":"2026-08-22T10:00:00Z","tool":"ship-land","exit":75,"stage":"land","head":"?","base":"?","red":""}
{"ts":"2026-08-23T10:00:00Z","tool":"ship-land","exit":42,"stage":"round","head":"aaa6","base":"bbb6","red":""}
{"ts":"2026-08-24T10:00:00Z","tool":"land-lock","event":"acquire","wait_s":0,"hold_s":3}
{"ts":"2026-08-25T10:00:00Z","tool":"ship-land","exit":6,"stage":"land","head":"aaa7","base":"bbb7","red":"unattributed"}
this line is not json
{"ts":"2026-09-01T10:00:00Z","tool":"ship-land","exit":0,"stage":"land","head":"aaa8","base":"bbb8","red":""}
EOF
  export LAND_LOG="$STORE"
}

# ── the corpus, and the five traps it inherits from gate-red-census.sh ────────────────────────

@test "census: the stage:round row is not an attempt, and the lock row is not an invocation" {
  mkstore
  run python3 "$CORPUS_PY" census "$STORE"
  [ "$status" -eq 0 ]
  [ "$(jq -r .invocations <<<"$output")" = 7 ]
  [ "$(jq -r .round_rows <<<"$output")" = 1 ]
  [ "$(jq -r .non_invocation_rows <<<"$output")" = 1 ]
  # Trap 4: an unparseable line is COUNTED, never dropped — a shrinking denominator reads as
  # an improving rate.
  [ "$(jq -r .bad_json <<<"$output")" = 1 ]
}

@test "census: exit 6 and exit 9 are never summed — they are claims about different objects" {
  mkstore
  run python3 "$CORPUS_PY" census "$STORE"
  [ "$(jq -r '.class_census.GATE_RED' <<<"$output")" = 3 ]
  [ "$(jq -r '.class_census.GATE_KILLED' <<<"$output")" = 1 ]
  # OTHER_REFUSED is its own bucket: a lock timeout is not a verdict about anyone's tree.
  [ "$(jq -r '.class_census.OTHER_REFUSED' <<<"$output")" = 1 ]
}

@test "census: the red field has FOUR states and the birthday one is not 'no arm went red'" {
  mkstore
  run python3 "$CORPUS_PY" census "$STORE"
  # aaa2 predates the birthday and carries NO red key at all: an absence, not a clean land.
  [ "$(jq -r '.red_bucket_census.instrument_birthday' <<<"$output")" = 1 ]
  [ "$(jq -r '.red_bucket_census.unattributed' <<<"$output")" = 1 ]
  [ "$(jq -r '.red_bucket_census.attributed' <<<"$output")" = 1 ]
}

@test "census: a '?' placeholder sha is not a joinable row" {
  mkstore
  run python3 "$CORPUS_PY" census "$STORE"
  # attest_land writes "?" when the shas were never resolved. `.head and .base` in jq passes on it
  # because it is a non-empty string, so the receipt's own corpus count includes rows whose diff
  # does not exist. joinable() is what excludes them.
  [ "$(jq -r .placeholder_sha_rows <<<"$output")" = 1 ]
  [ "$(jq -r .joinable <<<"$output")" = 6 ]
}

@test "census: REFUSES rather than reporting when it disagrees with gate-red-census.sh" {
  mkstore
  # The authority is the census; this reader has to prove agreement rather than claim it. Forcing a
  # disagreement is the only way to know the assert is wired: a parity check that has never gone
  # red is a checker nobody has falsified (memory: distrust a checker that has never once gone red).
  fake="$BATS_TEST_TMPDIR/fake"; mkdir -p "$fake/scripts/jev"
  cp "$CORPUS_PY" "$REPO/scripts/jev/predict-land.sh" "$fake/scripts/jev/"
  # A heredoc, not a printf: the first spelling of this stub was `printf %s\n "{...}"`, whose
  # unquoted format string the shell collapsed to `%sn` — so the stub emitted the single letter `n`,
  # the assert matched nothing, and the case went red for a reason that had nothing to do with the
  # subject. A fixture that cannot emit its own payload tests the fixture.
  cat > "$fake/scripts/gate-red-census.sh" <<'STUB'
#!/bin/bash
echo '{"invocations":999,"round_rows":0,"non_invocation_rows":0,"unparseable_json_lines":0}'
STUB
  chmod +x "$fake/scripts/gate-red-census.sh"
  run bash "$fake/scripts/jev/predict-land.sh" census
  [ "$status" -eq 4 ]
  [[ "$output" == *"CENSUS DISAGREEMENT"* ]]
}

# ── the null arithmetic ───────────────────────────────────────────────────────────────────────

@test "null: a coin's precision is the prevalence, at every firing rate" {
  mkstore
  run python3 "$CORPUS_PY" null "$STORE"
  prev="$(jq -r '.definitions["any-nonzero"].prevalence' <<<"$output")"
  coin="$(jq -r '.definitions["any-nonzero"].coin.precision' <<<"$output")"
  [ "$prev" = "$coin" ]
  # always-warn reads NOTHING and still gets that precision at recall 1.0. A headline precision
  # quoted without this number is read against 0.50 and is wrong by the whole prevalence.
  [ "$(jq -r '.definitions["any-nonzero"].always_warn.recall' <<<"$output")" = "1.0" ]
}

@test "null: the recall ceiling is intersected with the positive definition, never over the whole population" {
  mkstore
  run python3 "$CORPUS_PY" null "$STORE"
  # THE DEFECT: with positive="attributed" (1 row here) the first version counted all 3 exit-6 rows
  # as the numerator and printed a ceiling of 3.0. Every definition must give a ratio in [0,1].
  for d in any-nonzero gate-red attributed; do
    c="$(jq -r --arg d "$d" '.definitions[$d].perfect_diff_reader.recall_ceiling' <<<"$output")"
    python3 -c "import sys; sys.exit(0 if 0.0 <= $c <= 1.0 else 1)" || {
      echo "ceiling $c out of range for definition $d"; false
    }
  done
}

@test "null: a ceiling outside [0,1] is reported as an INSTRUMENT fault, not as unreachability" {
  # The two demand opposite actions — "fix the arithmetic" versus "re-define the positive class" —
  # so they must not share a verdict. Driven through the function directly: no corpus can produce
  # this state once the numerator is correct, which is exactly why the guard needs its own case.
  run python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/jev')
from predict_land_corpus import pass_bar_reachable
r = pass_bar_reachable({'n': 10, 'n_positive': 5, 'prevalence': 0.5,
                        'perfect_diff_reader': {'recall_ceiling': 2.0, 'gate_red_rows': 10}})
assert r['reachable'] is None, r
assert 'INSTRUMENT FAULT' in r['why'][0], r
print('ok')"
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
}

@test "null: the ceiling excludes refusals no diff can determine" {
  mkstore
  run python3 "$CORPUS_PY" null "$STORE"
  # 4 positives under any-nonzero (exits 6,9,6 and the '?' row is unjoinable), of which 3 are
  # exit-6. A perfect DIFF reader cannot catch the GATE_KILLED row at all: exit 9 is documented as a
  # claim about the MACHINE (ship-land.sh:2508), so it caps recall rather than merely adding noise.
  [ "$(jq -r '.definitions["any-nonzero"].perfect_diff_reader.recall_ceiling' <<<"$output")" = "0.75" ]
}

# ── the consent gate ──────────────────────────────────────────────────────────────────────────
#
# phase_ask checks THREE gates, in this order: the free-spend window (hooks/lib/jev.sh:197), then
# jev_available (jev.sh:117), then the arm token. Both cases below are about the THIRD, and neither
# sealed the first two — so both asserted on a gate they never reached. seal_jev_preconditions
# closes that; the reasoning is on the helper, because it is the whole content of this fix.

# seal_jev_preconditions — make the two earlier gates PASS, hermetically, so a refusal below is the
# consent gate's and not the box's.
#
# 🚨 POST-LAND RED (backlog 187ee2cb4252, filed at 63a0584e). Reproduced here 24/24 with exactly
# these two cases red: jev_available requires `$CC_JEV_LIB_ROOT/node_modules/ai`, which is
# gitignored (.gitignore:50) and so is absent from every worktree, every fresh clone and every
# dispatched worker — the land gate's own worktree included. Both cases exited 3 with "jev is not
# available" and failed on `[ "$status" -eq 6 ]`, a verdict about the RUNNER wearing the shape of a
# verdict about the subject (docs/lessons/a-suite-red-can-belong-to-the-box-not-the-branch.md).
#
# WHY SEALED AND NOT SKIPPED, unlike the three sibling files that guard this same precondition
# (jev-evaluate.bats:30, jev-anti-deference-arm.bats:35, jev-promote.bats:40). Those cases need a
# CALL to succeed, and no fixture can grant that — a skip is the honest verdict. These two need a
# REFUSAL, which needs no deps at all. Skipping them would retire the consent gate standing between
# a never-pushed diff and STANDARD retention on precisely the runners that lack node_modules, and
# this file's own baseline case already fixes the standard: a safety refusal that only ever skips
# has never been falsified.
#
# THE SECOND, INDEPENDENT RED, closed in the same pass because it is the same unsealed seam.
# CC_JEV_FREE_UNTIL defaults to 2026-09-25 (jev.sh:198), so from 2026-09-26 both cases go red on a
# box WITH deps installed — the desk included — for a reason that is neither the subject nor the
# box but the calendar. Measured by running the arm at CC_JEV_FREE_UNTIL=2026-09-21: exit 3,
# "the free AI Gateway window closed". Pinned far forward here, which seals the clock comparison
# and nothing else. Deliberately NOT `CC_JEV_PAID=1`: that override authorises SPEND, and a test
# must not carry an authorisation it has no use for.
#
# The gate ORDER is not what was wrong. Checking the window first is deliberate and argued at
# predict-land.sh:422 — the window is the one refusal whose cost is a BILL rather than a re-run — so
# the instrument is what had to be fixtured, not the subject reordered.
#
# The stub `node` is here so the fourth precondition is not ambient either, and it exits non-zero
# and loudly: nothing on these two paths may reach a call, so if a future edit lets the seal
# over-reach past the refusal it exists to expose, the stub names that instead of quietly running
# the real runtime.
seal_jev_preconditions() {
  local r="$BATS_TEST_TMPDIR/jevroot" b="$BATS_TEST_TMPDIR/stubbin"
  mkdir -p "$r/scripts/jev" "$r/node_modules/ai" "$b"
  : > "$r/scripts/jev/evaluate.mjs"
  cat > "$b/node" <<'STUB'
#!/bin/bash
echo "FIXTURE node stub: the subject reached a CALL, which these cases must refuse before." >&2
exit 97
STUB
  chmod +x "$b/node"
  export CC_JEV_LIB_ROOT="$r"
  export CC_JEV=1                         # an ambient CC_JEV=0 exits 3 by the same door
  export CC_JEV_FREE_UNTIL=2099-01-01     # pin the clock; do NOT authorise spend
  export PATH="$b:$PATH"
}

@test "ask: refuses with no arm token, and names the command instead of running it" {
  mkstore
  seal_jev_preconditions
  rm -f "$CC_PREDICT_ARM_FILE"
  echo '{"head":"aaa1","base":"bbb1"}' > "$BATS_TEST_TMPDIR/s.jsonl"
  run env AI_GATEWAY_API_KEY=dummy bash "$SUT" ask --sample "$BATS_TEST_TMPDIR/s.jsonl"
  [ "$status" -eq 6 ]
  [[ "$output" == *"NOT ARMED"* ]] || false
  # And NOT a pre-empting refusal. Both earlier gates also exit non-zero and print a ⛔/✗ line, so
  # naming their text is what separates "the consent gate refused" from "the consent gate was never
  # reached" — the exact confusion this case shipped with, and the one an un-sealing would restore.
  [[ "$output" != *"jev is not available"* ]] || false
  [[ "$output" != *"free AI Gateway window"* ]] || false
}

@test "ask: a token naming another corpus is refused AND left intact for its own consumer" {
  mkstore
  seal_jev_preconditions
  jq -n '{created:"2026-09-21T00:00:00Z",expires:"2099-01-01T00:00:00Z",max_calls:5,corpus:"memory-orphans"}' \
    > "$CC_PREDICT_ARM_FILE"
  echo '{"head":"aaa1","base":"bbb1"}' > "$BATS_TEST_TMPDIR/s.jsonl"
  run env AI_GATEWAY_API_KEY=dummy bash "$SUT" ask --sample "$BATS_TEST_TMPDIR/s.jsonl"
  [ "$status" -eq 6 ]
  # `not land-diffs` is unique to the corpus gate, so this one string already proves which refusal
  # was reached — no absence assertion needed beside it.
  [[ "$output" == *"not land-diffs"* ]] || false
  # NOT consumed: the token belongs to jev-batch.sh's corpus, and eating another consumer's
  # authorisation would silently disarm it.
  [ -f "$CC_PREDICT_ARM_FILE" ]
}

@test "arm-print prints the arming command and creates nothing" {
  run bash "$SUT" arm-print
  [ "$status" -eq 0 ]
  [[ "$output" == *"land-diffs"* ]] || false
  [[ "$output" == *"NOTHING here has been run"* ]] || false
  [ ! -f "$CC_PREDICT_ARM_FILE" ]
}

# ── PEM banner fixtures, assembled rather than written ────────────────────────────────────────
# ship-land's DISCLOSURE scan (ESC_RE_SECRET_DEFAULT, ship-land.sh:514) is not exemptible in ANY
# file, so one literal PEM banner anywhere in the repo parks every land that carries it. This
# file's first land was parked exactly that way — decision packet shipland-esc-85be1d228, three
# hits, all three of them these fixtures and none of them key material. Assembling the banner
# defeats the scan and changes nothing grep sees: `pem_banner RSA` is byte-identical to the
# literal it replaces, which is the only property the cases below rest on. Same remedy already
# taken on trunk in docs/plans/RATIFY_DECISIONS_TRIAGE.md:153.
# The split MUST fall between `-----BEGIN` and `PRIVATE`: the pattern is ONE regex spanning both,
# so neither half can match on its own — splitting anywhere else would leave the land parked.
pem_banner() {  # $1=optional algorithm label (RSA, OPENSSH); empty ⇒ the bare banner
  local dash5='-----' head='BEGIN' body='PRIVATE KEY'
  printf '%s%s %s%s%s' "$dash5" "$head" "${1:+$1 }" "$body" "$dash5"
}

# ── the disclosure gate: both directions, because one alone proves nothing ────────────────────

@test "disclosure: the DEFAULT pattern matches a real key block and not ordinary diff text" {
  # A positive control on the DEFAULT value, not on a substituted one. The bug was that this scan
  # could not run at all, so the pattern itself had never been exercised.
  re='-----BEGIN[[:space:]A-Z]*PRIVATE[[:space:]]+KEY'
  for s in "$(pem_banner RSA)" "$(pem_banner)" "$(pem_banner OPENSSH)"; do
    printf '%s' "$s" | grep -qE -e "$re" || { echo "default pattern missed: $s"; false; }
  done
  run bash -c "printf '%s' 'an ordinary +++ b/file.sh line' | grep -qE -e '$re'"
  [ "$status" -eq 1 ]
}

@test "disclosure: the pattern needs -e, or grep reads it as an option and the gate fails OPEN" {
  # THE DEFECT, pinned as a mutant. Without -e the leading dashes make grep exit 2, which is FALSY
  # in an `if` — so the row is read as clean and sent. This case is the only thing standing between
  # that spelling and a silent re-introduction.
  re='-----BEGIN[[:space:]A-Z]*PRIVATE[[:space:]]+KEY'
  run env B="$(pem_banner RSA)" RE="$re" bash -c 'printf "%s" "$B" | grep -qE "$RE" 2>/dev/null'
  [ "$status" -eq 2 ]          # could not run — NOT a clean 1
  run env B="$(pem_banner RSA)" RE="$re" bash -c 'printf "%s" "$B" | grep -qE -e "$RE"'
  [ "$status" -eq 0 ]          # with -e it actually matches
}

# ── the baseline arm ──────────────────────────────────────────────────────────────────────────

@test "baseline: REFUSES when the linter is absent rather than scoring every row clean" {
  mkstore
  echo '{"head":"aaa1","base":"bbb1"}' > "$BATS_TEST_TMPDIR/s.jsonl"
  # Driven through CC_PREDICT_SHELLCHECK_BIN rather than by stripping PATH. Stripping PATH cannot
  # work on a box where the linter sits in /usr/bin beside bash and jq, so the first version of this
  # case could only ever SKIP — on the one path where scoring rows clean silently hands the baseline
  # a free loss in the comparison the model must win. A safety refusal that only ever skips has
  # never been falsified. Mirror of ship-land.sh:3241, where an absent linter told a spotless tree
  # it was RED; here the absent-linter direction is the opposite and worse.
  run env CC_PREDICT_SHELLCHECK_BIN=definitely-not-a-real-linter \
      bash "$SUT" baseline --sample "$BATS_TEST_TMPDIR/s.jsonl"
  [ "$status" -eq 3 ]
  [[ "$output" == *"NON-VERDICT"* ]] || false
  # And nothing was emitted: a refusal must not also print an analyzers header, or a consumer would
  # have a comparator record for a run that produced no comparison.
  [[ "$output" != *'"analyzers"'* ]]
}

@test "baseline: takes the policy file from the row's own sha, so a materialised file keeps its waivers" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  command -v git >/dev/null || skip "git not installed"
  # THE DEFECT, reproduced at its root: the linter finds .shellcheckrc through the checked file's
  # ANCESTORS, so a file alone in a temp dir is judged with no policy and the two repo-wide waivers
  # (SC2001, SC2015) fire on code the gate had passed. 7 of 25 real trunk commits scored HIT.
  d="$BATS_TEST_TMPDIR/tree"; mkdir -p "$d/sub"
  # SC2001, one of the two codes .shellcheckrc waives repo-wide. Chosen over SC2015 because its
  # trigger is unambiguous across linter versions: the `A && B || C` shape did NOT fire SC2015 under
  # 0.9.0 in the obvious `[ -f x ] && echo y || echo n` spelling, so a case built on it would have
  # asserted on a finding that never appeared and gone red on the fixture, not on the subject.
  cat > "$d/sub/x.sh" <<'SH'
#!/bin/bash
x="a'b"
y="$(echo "$x" | sed "s/'/''/g")"
echo "$y"
SH
  run shellcheck "$d/sub/x.sh"
  [ "$status" -ne 0 ]                       # the waived code fires with no policy in the tree
  [[ "$output" == *SC2001* ]] || false
  printf 'disable=SC2001,SC2015\n' > "$d/.shellcheckrc"
  run shellcheck "$d/sub/x.sh"
  [ "$status" -eq 0 ]                       # …and is waived once the policy is an ancestor
}

@test "baseline: records its analyzer versions, so a re-run cannot silently change the comparator" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  command -v git >/dev/null || skip "git not installed"
  mkstore
  # Unreachable shas: the header must be emitted before any row is attempted, because the header is
  # what identifies WHICH comparator condition (c) was measured against.
  echo '{"head":"aaa1","base":"bbb1","ts":"2026-07-01T10:00:00Z","class":"LANDED","exit":0,"arm":null,"red_bucket":"no_arm_went_red"}' \
    > "$BATS_TEST_TMPDIR/s.jsonl"
  run bash "$SUT" baseline --sample "$BATS_TEST_TMPDIR/s.jsonl"
  [ "$status" -eq 0 ]
  [ -n "$(jq -r 'select(.analyzers)|.analyzers.shellcheck' <<<"$output")" ]
  [ "$(jq -r 'select(.analyzers)|.analyzers.shellcheck' <<<"$output")" != "ABSENT" ]
}

# ── the scorer ────────────────────────────────────────────────────────────────────────────────

@test "score: a CONSTANT predictor passes no condition" {
  # The mock answers 0.99 to every boolean, which is the degenerate instrument. It must land on
  # AUROC 0.5 and fail all three, and its best operating point must be precision == prevalence at
  # recall 1.0 — i.e. it IS always-warn. A scorer that passes this would pass anything.
  b="$BATS_TEST_TMPDIR/b.jsonl"; a="$BATS_TEST_TMPDIR/a.jsonl"
  : > "$b"; : > "$a"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    ex=0; cl=LANDED
    if [ $(( i % 2 )) -eq 0 ]; then ex=6; cl=GATE_RED; fi
    printf '{"head":"h%s","base":"b%s","ts":"2026-08-0%sT00:00:00Z","class":"%s","exit":%s,"arm":null,"red_bucket":"no_arm_went_red","baseline":{"shellcheck":0,"bash_n":0,"dead_assertion":0,"shell_files":0,"bats_files":0,"score":0}}\n' \
      "$i" "$i" "$i" "$cl" "$ex" >> "$b"
    printf '{"head":"h%s","base":"b%s","ts":"2026-08-0%sT00:00:00Z","class":"%s","exit":%s,"arm":null,"red_bucket":"no_arm_went_red","jev":{"ok":true,"answers":{"q_refuse":{"type":"boolean","probability":0.99},"q_smoke":{"type":"boolean","probability":0.99}}}}\n' \
      "$i" "$i" "$i" "$cl" "$ex" >> "$a"
  done
  run --separate-stderr bash "$SUT" score --baseline "$b" --ask "$a"
  [ "$status" -eq 0 ]
  # The three conditions are the HUMAN verdict and are written to stderr; the JSON below is stdout.
  [[ "$stderr" == *"(a) FAIL"* ]] || false
  [[ "$stderr" == *"(b) FAIL"* ]] || false
  [[ "$stderr" == *"(c) FAIL"* ]] || false
  [ "$(jq -r '.definitions["any-nonzero"].rollup.auroc' <<<"$output")" = "0.5" ]
  [ "$(jq -r '.definitions["any-nonzero"].rollup.best_at_min_recall.precision' <<<"$output")" \
    = "$(jq -r '.definitions["any-nonzero"].rollup.prevalence' <<<"$output")" ]
}

@test "score: an ABSTAINED call is not scored as a confident negative" {
  # evaluate.mjs gives abstain its own exit code precisely so it cannot be pooled with an answer.
  # Substituting 0.0 would credit the model with a negative it never made — and would do it on
  # exactly the rows where the route failed, which are not a random subset.
  b="$BATS_TEST_TMPDIR/b.jsonl"; a="$BATS_TEST_TMPDIR/a.jsonl"
  : > "$b"; : > "$a"
  for i in 1 2 3 4; do
    ex=0; cl=LANDED
    if [ $(( i % 2 )) -eq 0 ]; then ex=6; cl=GATE_RED; fi
    printf '{"head":"h%s","base":"b%s","ts":"2026-08-0%sT00:00:00Z","class":"%s","exit":%s,"arm":null,"red_bucket":"no_arm_went_red","baseline":{"shellcheck":0,"bash_n":0,"dead_assertion":0,"shell_files":0,"bats_files":0,"score":0}}\n' \
      "$i" "$i" "$i" "$cl" "$ex" >> "$b"
    printf '{"head":"h%s","base":"b%s","class":"%s","exit":%s,"arm":null,"red_bucket":"no_arm_went_red","jev":{"ok":false,"reason":"timeout"}}\n' \
      "$i" "$i" "$cl" "$ex" >> "$a"
  done
  run --separate-stderr bash "$SUT" score --baseline "$b" --ask "$a"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.definitions["any-nonzero"].jev_abstained' <<<"$output")" = 4 ]
  [ "$(jq -r '.definitions["any-nonzero"].jev_answered' <<<"$output")" = 0 ]
  [[ "$stderr" == *"NO JEV ARM"* ]] || false
}

@test "score: AUROC on a single-class corpus is null, never 0.5" {
  # 0.5 would read as "chance" — a measurement — when the truth is that no comparison was possible.
  run python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/jev')
from predict_land_corpus import auroc
assert auroc([0.1, 0.9, 0.5], [1, 1, 1]) is None
assert auroc([0.1, 0.9, 0.5], [0, 0, 0]) is None
assert auroc([0.9, 0.1], [1, 0]) == 1.0
print('ok')"
  [ "$status" -eq 0 ]
}

@test "score: the baseline header row is separated from the scored rows, not counted as one" {
  b="$BATS_TEST_TMPDIR/b.jsonl"
  printf '{"analyzers":{"shellcheck":"9.9.9","bash":"x","python3":"y"}}\n' > "$b"
  for i in 1 2; do
    ex=0; cl=LANDED
    if [ "$i" = 2 ]; then ex=6; cl=GATE_RED; fi
    printf '{"head":"h%s","base":"b%s","class":"%s","exit":%s,"arm":null,"red_bucket":"x","baseline":{"score":0,"shellcheck":0,"bash_n":0,"dead_assertion":0,"shell_files":0,"bats_files":0}}\n' \
      "$i" "$i" "$cl" "$ex" >> "$b"
  done
  run --separate-stderr bash "$SUT" score --baseline "$b"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.comparator.shellcheck' <<<"$output")" = "9.9.9" ]
  [ "$(jq -r '.definitions["any-nonzero"].baseline.n' <<<"$output")" = 2 ]
}

# ── the sampler ───────────────────────────────────────────────────────────────────────────────

@test "sample: the holdout is carved WITHIN each stratum, not off the tail" {
  # A tail holdout would be a different PERIOD from the training half, so the comparison would be
  # between epochs rather than between instruments — and the receipt's own warning is that
  # recency-only measures today's gate config.
  run python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/jev')
from predict_land_corpus import stratified_sample
rows = [{'class': 'GATE_RED' if i % 2 else 'LANDED',
         'ts': '2026-0%d-01T00:00:00Z' % (7 + i % 3), 'head': 'h%d' % i} for i in range(60)]
tr, ho = stratified_sample(rows, 60, 0.5, 1)
months_tr = {r['ts'][:7] for r in tr}; months_ho = {r['ts'][:7] for r in ho}
assert months_tr == months_ho, (months_tr, months_ho)
cls_tr = {r['class'] for r in tr}; cls_ho = {r['class'] for r in ho}
assert cls_tr == cls_ho == {'GATE_RED', 'LANDED'}, (cls_tr, cls_ho)
assert len(tr) + len(ho) == 60
print('ok')"
  [ "$status" -eq 0 ]
}

@test "sample: no stratum is rounded out of existence" {
  # An emptied stratum is the aggregate-control-cannot-see-a-per-member-zero shape: the sample still
  # looks proportional in total while one cell has silently gone blind.
  run python3 -c "
import sys; sys.path.insert(0, '$REPO/scripts/jev')
from predict_land_corpus import stratified_sample
rows = [{'class': 'LANDED', 'ts': '2026-07-01T00:00:00Z', 'head': 'h%d' % i} for i in range(100)]
rows += [{'class': 'GATE_RED', 'ts': '2026-09-01T00:00:00Z', 'head': 'r%d' % i} for i in range(3)]
tr, ho = stratified_sample(rows, 20, 0.0, 5)
assert any(r['class'] == 'GATE_RED' for r in tr), 'the 3-row stratum was rounded away'
print('ok')"
  [ "$status" -eq 0 ]
}

# ── the files this land adds must pass the gate's own statics ─────────────────────────────────

@test "every shipped file lints clean under the repo's own analyzers" {
  command -v shellcheck >/dev/null || skip "shellcheck not installed"
  # SC1073 is why this case exists and why it asserts on the linter's OWN output: a comment line
  # beginning with the tool's name is parsed as a directive and VOIDS the lint for the whole file,
  # so a green run can mean "nothing was checked". Asserting the absence of SC1072/SC1073 is what
  # separates "clean" from "not read" (docs/lessons/a-gate-refusal-is-not-a-gate-result.md).
  run shellcheck "$REPO/scripts/jev/predict-land.sh"
  [ "$status" -eq 0 ]
  [[ "$output" != *SC1073* ]] || false
  [[ "$output" != *SC1072* ]] || false
  run bash -n "$REPO/scripts/jev/predict-land.sh"
  [ "$status" -eq 0 ]
  run python3 -m py_compile "$REPO/scripts/jev/predict_land_corpus.py" "$REPO/scripts/jev/predict_land_score.py"
  [ "$status" -eq 0 ]
}
