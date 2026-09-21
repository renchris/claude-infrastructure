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

# ── THE TWO STREAMS ARE CAPTURED SEPARATELY, AND THIS IS A BUG FIX, NOT TIDINESS ──────────────
# bats' `run` MERGES stderr into $output. `predict-land.sh score` prints machine JSON on stdout and
# the human verdict on stderr, so `jq <<<"$output"` was handed a stream with prose in it — and
# `$(jq …)` inside `[ … ]` DISCARDS jq's exit code, which is what hid it. On this author's shell
# stdout flushed first: jq printed the right answer, THEN errored on the trailing prose, and the
# comparison passed. **The test was green while jq was failing.** Under scripts/offbox-run.sh's
# hermetic env (`env -i`, fresh empty HOME, TERM=dumb, LC_ALL=C) stderr flushed first, jq hit prose
# at line 1, printed nothing, and three cases went red — the honest result, and the only reason the
# defect was ever seen. Measured with cat -A on both: hermetic $output line 1 is the verdict line.
#
# Files rather than `run --separate-stderr`, which needs bats >= 1.5 and would make this suite's
# greenness depend on the runner's version — the exact class of thing the off-box gate exists to
# catch. A redirect works on every bats, and it turns the stdout/stderr CONTRACT into an assertion
# (JSON is parseable ALONE; the verdict really is on stderr) instead of an accident of buffering.
#
# Scoped deliberately to the subjects that write BOTH streams (`score`, `baseline`). The census and
# null cases below invoke predict_land_corpus.py directly, which writes stdout only, so they are not
# in this class and are left as they are rather than churned on a cycle-2 land.
_split() {            # _split <out-file> <err-file> <cmd...>
  local o="$1" e="$2"; shift 2
  "$@" >"$o" 2>"$e"
}
# jq WITH ITS RC VISIBLE. Called through `run`, so a parse error becomes a failing status the case
# asserts on, instead of an empty string a comparison silently blames on the value.
_jqf() {              # _jqf <file> <filter>
  jq -r "$2" "$1"
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

@test "ask: refuses with no arm token, and names the command instead of running it" {
  mkstore
  rm -f "$CC_PREDICT_ARM_FILE"
  echo '{"head":"aaa1","base":"bbb1"}' > "$BATS_TEST_TMPDIR/s.jsonl"
  run env AI_GATEWAY_API_KEY=dummy bash "$SUT" ask --sample "$BATS_TEST_TMPDIR/s.jsonl"
  [ "$status" -eq 6 ]
  [[ "$output" == *"NOT ARMED"* ]]
}

@test "ask: a token naming another corpus is refused AND left intact for its own consumer" {
  mkstore
  jq -n '{created:"2026-09-21T00:00:00Z",expires:"2099-01-01T00:00:00Z",max_calls:5,corpus:"memory-orphans"}' \
    > "$CC_PREDICT_ARM_FILE"
  echo '{"head":"aaa1","base":"bbb1"}' > "$BATS_TEST_TMPDIR/s.jsonl"
  run env AI_GATEWAY_API_KEY=dummy bash "$SUT" ask --sample "$BATS_TEST_TMPDIR/s.jsonl"
  [ "$status" -eq 6 ]
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

# ── the disclosure gate: both directions, because one alone proves nothing ────────────────────
#
# 🚨 THE KEY-SHAPED SAMPLES ARE ASSEMBLED AT RUN TIME AND NEVER WRITTEN AS LITERALS, AND THAT IS
# THE GATE'S RULING, NOT A PREFERENCE. This file's first version carried the full
# `<dashes>BEGIN RSA PRIVATE KEY<dashes>` string on three lines, and ship-land's escape scan refused
# the land — DISCLOSURE class, which `esc_exempt_path` documents as never exemptible. It was right:
# a key-shaped literal in the repository is precisely what that scan exists to stop, and "it is only
# a test fixture" is not a carve-out the scan can be given without being given to everyone. So the
# samples are built from fragments and no single line of source — and therefore no line of the diff
# the scan reads — carries the pattern. `pat` below is the REGEX, whose own bracket expressions stop
# it matching itself (the same reason ship-land.sh can hold ESC_RE_SECRET_DEFAULT in the clear).
#
# These helpers exist so the two arms of the mutant below differ in EXACTLY the -e flag. Inlining
# them would put the flag beside three other differences and the A/B would stop being a control.
_scan_no_e() { printf '%s' "$1" | grep -qE "$2"; }
_scan_with_e() { printf '%s' "$1" | grep -qE -e "$2"; }
# Assembled here rather than in each test: one definition, one place the scan could ever regress to.
_key_sample() { printf '%s %s %s' '-----BEGIN' "$1" 'KEY-----'; }

@test "disclosure: the DEFAULT pattern matches a real key block and not ordinary diff text" {
  # A positive control on the DEFAULT value, not on a substituted one. The bug was that this scan
  # could not run at all, so the pattern itself had never once been exercised.
  pat='-----BEGIN[[:space:]A-Z]*PRIVATE[[:space:]]+KEY'
  p=PRIVATE
  for mid in "RSA $p" "$p" "OPENSSH $p"; do
    run _scan_with_e "$(_key_sample "$mid")" "$pat"
    [ "$status" -eq 0 ] || { echo "default pattern missed the $mid form"; false; }
  done
  run _scan_with_e 'an ordinary +++ b/file.sh line' "$pat"
  [ "$status" -eq 1 ]
}

@test "disclosure: the pattern needs -e, or grep reads it as an option and the gate fails OPEN" {
  # THE DEFECT, pinned as a mutant. Without -e the leading dashes make grep treat the pattern as an
  # OPTION and exit non-zero-but-not-1, which is FALSY in an `if` — so the row read as clean and was
  # SENT. This case is the only thing standing between that spelling and a silent re-introduction.
  pat='-----BEGIN[[:space:]A-Z]*PRIVATE[[:space:]]+KEY'
  sample="$(_key_sample "RSA PRIVATE")"
  run _scan_no_e "$sample" "$pat"
  # Asserted as "neither a match nor a clean no-match" rather than as `-eq 2`: GNU grep says
  # "unrecognized option" and BSD "illegal option", both exiting 2 today, but the CLAIM is that the
  # rc cannot be read as a verdict — and that claim must not rest on one platform's exact number.
  [ "$status" -ne 0 ]
  [ "$status" -ne 1 ]
  run _scan_with_e "$sample" "$pat"
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
  run _split "$BATS_TEST_TMPDIR/o.jsonl" "$BATS_TEST_TMPDIR/e.txt" \
      bash "$SUT" baseline --sample "$BATS_TEST_TMPDIR/s.jsonl"
  [ "$status" -eq 0 ]
  run _jqf "$BATS_TEST_TMPDIR/o.jsonl" 'select(.analyzers)|.analyzers.shellcheck'
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [ "$output" != "ABSENT" ]
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
  o="$BATS_TEST_TMPDIR/o.json"; e="$BATS_TEST_TMPDIR/e.txt"
  run _split "$o" "$e" bash "$SUT" score --baseline "$b" --ask "$a"
  [ "$status" -eq 0 ]
  # The human verdict is on STDERR — asserted there, so the contract is tested rather than assumed.
  grep -q '(a) FAIL' "$e"
  grep -q '(b) FAIL' "$e"
  grep -q '(c) FAIL' "$e"
  # …and the machine JSON is on STDOUT, parseable ON ITS OWN. Through `run`, so a jq parse error is
  # a failing status this case reports instead of an empty string it blames on the value.
  run _jqf "$o" '.definitions["any-nonzero"].rollup.auroc'
  [ "$status" -eq 0 ]
  [ "$output" = "0.5" ]
  run _jqf "$o" '.definitions["any-nonzero"].rollup.best_at_min_recall.precision'
  [ "$status" -eq 0 ]
  prec="$output"
  run _jqf "$o" '.definitions["any-nonzero"].rollup.prevalence'
  [ "$status" -eq 0 ]
  [ "$prec" = "$output" ]
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
  o="$BATS_TEST_TMPDIR/o.json"; e="$BATS_TEST_TMPDIR/e.txt"
  run _split "$o" "$e" bash "$SUT" score --baseline "$b" --ask "$a"
  [ "$status" -eq 0 ]
  run _jqf "$o" '.definitions["any-nonzero"].jev_abstained'
  [ "$status" -eq 0 ]
  [ "$output" = 4 ]
  run _jqf "$o" '.definitions["any-nonzero"].jev_answered'
  [ "$status" -eq 0 ]
  [ "$output" = 0 ]
  grep -q 'NO JEV ARM' "$e"
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
  o="$BATS_TEST_TMPDIR/o.json"; e="$BATS_TEST_TMPDIR/e.txt"
  run _split "$o" "$e" bash "$SUT" score --baseline "$b"
  [ "$status" -eq 0 ]
  run _jqf "$o" '.comparator.shellcheck'
  [ "$status" -eq 0 ]
  [ "$output" = "9.9.9" ]
  run _jqf "$o" '.definitions["any-nonzero"].baseline.n'
  [ "$status" -eq 0 ]
  [ "$output" = 2 ]
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
