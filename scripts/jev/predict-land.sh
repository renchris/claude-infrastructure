#!/usr/bin/env bash
# predict-land.sh — the PRE-FLIGHT LAND-REFUSAL PREDICTOR's instrument: can a bounded typed judgment
# over a diff tell you the land gate will refuse it, BEFORE the gate spends its measured mean 829 s
# finding out? Candidate and label corpus are A10's recommendation
# (docs/research/jev-100p-2026-09-21/a10-prior-art-and-labels.md): ~/.claude/land.log, whose
# accept/refuse labels were adjudicated by a real gate RUN rather than by a predicate over the input.
#
# ── THE PHASES ARE SEPARATE SUBCOMMANDS BECAUSE THEY HAVE DIFFERENT COSTS ────────────────────
#   census    reads the store. Free. REFUSES if it disagrees with gate-red-census.sh.
#   null      the arithmetic that must precede every call. Free, and it can KILL the candidate.
#   sample    draws the stratified sample and FREEZES a holdout. Free.
#   baseline  runs the repo's OWN static analyzers over the same diffs. Free, no network.
#   ask       the only phase that spends anything, and the only one an operator must arm.
#   score     joins the three and answers the frozen acceptance conditions. Free.
# Split this way because the receipt's condition (c) — "it must beat the static baseline" — is the
# condition most likely to kill the arm, and it is measurable with NO calls at all. A pipeline that
# only reports after the spending has happened puts its cheapest falsifier last.
#
# ── WHAT THIS SENDS, AND WHY IT IS A WIDER PAYLOAD THAN ANY JEV CONSUMER BEFORE IT ───────────
# 🚨 Every existing consumer sends prose the MODEL wrote (a close message) or our own engineering
# lessons. This sends a DIFF of this repository, and for a REFUSED land that diff was by definition
# never pushed anywhere — so it is the first payload here that may contain bytes that have never
# left the machine. ZDR is Pro/Enterprise-only on this plan and 403s, so a call goes out under
# STANDARD retention. That is a value fork, it is the operator's alone, and it is why `ask` demands
# its own arm token naming this corpus and refuses without one. An agent must never write that token.
#
# WHY A SEPARATE ARM FILE RATHER THAN cc-jev arm's. The batch token carries `corpus` and
# jev-batch.sh dispatches to promote-memory.sh REGARDLESS of its value — so widening that token to
# name this corpus would hand a land-diff authorisation to a consumer that sends memory files, which
# is docs/lessons/closed-vocabulary-swallows-an-unrecognized-value.md performed on a consent token:
# a value written into a field another consumer dispatches on, with a fail-open default. One token,
# one corpus, one consumer. `arm-print` prints the operator's command and never runs it.
set -uo pipefail

# Resolve through the symlink before deriving anything from $0: ~/.claude/scripts is a per-file
# symlink farm over the checkout, so an unresolved dirname walks out of the live layer and the
# sibling library is silently not found (docs/lessons/symlinked-0-splits-sibling-sources.md).
_resolve_self() {
  local p="$1" d
  while [ -L "$p" ]; do
    d="$(cd -P "$(dirname "$p")" && pwd)"; p="$(readlink "$p")"
    case "$p" in /*) ;; *) p="$d/$p" ;; esac
  done
  printf '%s' "$p"
}
SELF="$(_resolve_self "${BASH_SOURCE[0]}")"
ROOT="$(cd "$(dirname "$SELF")/../.." && pwd)"
CORPUS_PY="$ROOT/scripts/jev/predict_land_corpus.py"

LOG="${LAND_LOG:-$HOME/.claude/land.log}"
OUTDIR="${CC_PREDICT_OUTDIR:-$HOME/.claude/autonomy}"
ARM_FILE="${CC_PREDICT_ARM_FILE:-$HOME/.claude/autonomy/jev-predict-land.arm}"
# 16000, not the library's 24000: jev_ask's ceiling is over the WHOLE spec, and the question block
# below is ~3.5 KB of instructions. A cap set at the library's number would make the largest diffs
# abstain `oversize` — an abstain that correlates with diff SIZE, i.e. with the very rows most
# likely to be refused, which would bias the measurement toward the easy half.
CAP_B="${CC_PREDICT_CAP_B:-16000}"
# The DISCLOSURE class, taken verbatim from ship-land.sh's ESC_RE_SECRET_DEFAULT rather than
# re-spelled, so the two cannot drift. A payload matching it is SKIPPED, never truncated around:
# truncating would leave the row in the sample with a silently different payload.
SECRET_RE="${CC_PREDICT_SECRET_RE:------BEGIN[[:space:]A-Z]*PRIVATE[[:space:]]+KEY}"
MIN_RECALL="${CC_PREDICT_MIN_RECALL:-0.20}"
MIN_PRECISION="${CC_PREDICT_MIN_PRECISION:-0.85}"

usage() {
  cat <<'USAGE'
predict-land.sh <phase> [options]

  census                      read land.log; REFUSE (4) if it disagrees with gate-red-census.sh
  null                        the perfect-detector / coin arithmetic; exit 5 if the bar is unreachable
  sample   [--n N] [--holdout F] [--seed S]
                              stratified by (class, month), holdout frozen within each stratum
  baseline --sample FILE      the repo's own shellcheck / bash -n / dead-assertion analyzers
  ask      --sample FILE      the Jev arm. Requires an operator arm token naming corpus land-diffs
  score    --sample FILE --baseline FILE [--ask FILE]
                              AUROC+CI, the PR curve, and the three frozen acceptance conditions
  arm-print                   print the operator's arming command. Never runs it.

Seams: LAND_LOG · CC_PREDICT_OUTDIR · CC_PREDICT_ARM_FILE · CC_PREDICT_CAP_B · CC_PREDICT_SHELLCHECK_BIN ·
       CC_PREDICT_MIN_RECALL · CC_PREDICT_MIN_PRECISION · CC_PREDICT_SECRET_RE · CC_PREDICT_GAP_S
exit: 0 ok · 2 usage · 3 no corpus · 4 census disagreement · 5 bar unreachable · 6 not armed
USAGE
}

die() { printf '%s\n' "$*" >&2; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || die "predict-land: $1 is not installed"; }

# ── census ────────────────────────────────────────────────────────────────────────────────────
# The parity assert is the whole reason this phase is separate. gate-red-census.sh's header states
# the rule: land.log is ONE store and a second reader of it is a second authority. This reader has
# to join diffs onto rows, which a renderer cannot serve — so it proves agreement instead of
# claiming it. A disagreement means one of the five traps drifted, and that is a REFUSAL, not a
# warning: every number downstream is a rate over this population.
phase_census() {
  need python3; need jq
  [ -s "$LOG" ] || { printf '⛔ no corpus: %s is missing or empty\n' "$LOG" >&2; return 3; }
  local ours theirs a b
  ours="$(python3 "$CORPUS_PY" census "$LOG")" || return 3
  # GATE_RED_CENSUS_MIN_N=1: the floor exists to stop the census QUOTING a rate off a handful of
  # rows, which is a different question from whether its population count agrees with ours. Left at
  # its default, a small fixture store would make the authority exit 3 and the assert unrunnable —
  # i.e. the check would be skipped exactly where it is cheapest to test.
  theirs="$(LAND_LOG="$LOG" GATE_RED_CENSUS_MIN_N=1 bash "$ROOT/scripts/gate-red-census.sh" --json 2>/dev/null)"
  if [ -z "$theirs" ]; then
    printf '⛔ REFUSING: gate-red-census.sh --json produced nothing, so this reader cannot be\n' >&2
    printf '  checked against the authority. An unchecked second reader of land.log is the defect\n' >&2
    printf '  its header exists to prevent. Nothing downstream may run.\n' >&2
    return 4
  fi
  local k rc=0
  for k in invocations round_rows non_invocation_rows; do
    a="$(printf '%s' "$ours"   | jq -r --arg k "$k" '.[$k]')"
    b="$(printf '%s' "$theirs" | jq -r --arg k "$k" '.[$k]')"
    if [ "$a" != "$b" ]; then
      printf '⛔ CENSUS DISAGREEMENT on %s: this reader %s, gate-red-census.sh %s\n' "$k" "$a" "$b" >&2
      rc=4
    fi
  done
  a="$(printf '%s' "$ours"   | jq -r '.bad_json')"
  b="$(printf '%s' "$theirs" | jq -r '.unparseable_json_lines')"
  if [ "$a" != "$b" ]; then
    printf '⛔ CENSUS DISAGREEMENT on unparseable lines: %s vs %s\n' "$a" "$b" >&2; rc=4
  fi
  printf '%s\n' "$ours"
  if [ "$rc" = 0 ]; then
    printf '✓ census parity with gate-red-census.sh: invocations, rounds, non-invocations, bad JSON\n' >&2
  fi
  return "$rc"
}

# ── null ──────────────────────────────────────────────────────────────────────────────────────
phase_null() {
  need python3; need jq
  [ -s "$LOG" ] || { printf '⛔ no corpus: %s is missing or empty\n' "$LOG" >&2; return 3; }
  local out rc=0
  out="$(python3 "$CORPUS_PY" null "$LOG")" || rc=$?
  printf '%s\n' "$out"
  printf '%s' "$out" | jq -r '
    "",
    "NULL ARITHMETIC — what a PERFECT detector and a COIN would return, before any call",
    (.definitions | to_entries[] |
      "  positive = \(.key)",
      "    n=\(.value.n)  positives=\(.value.n_positive)  prevalence=\(.value.prevalence)",
      "    a coin:            precision \(.value.coin.precision) at EVERY firing rate, AUROC 0.50",
      "    always-warn:       precision \(.value.always_warn.precision) at recall 1.00 — reads nothing",
      "    perfect diff-reader: recall CEILING \(.value.perfect_diff_reader.recall_ceiling) " +
      "(\(.value.perfect_diff_reader.gate_red_rows) of \(.value.n_positive) positives are exit-6, " +
      "the only class whose producer calls it a verdict about the TREE)",
      "    arm question:      scoreable on \(.value.perfect_diff_reader.arm_scoreable_rows) rows " +
      "(ceiling \(.value.perfect_diff_reader.arm_recall_ceiling)) — and that bucket has a BIRTHDAY",
      "    lift the bar asks:  precision must beat the coin by \(.value.pass_bar.lift_required_over_coin) " +
      "— read the bar as THAT, never as a margin over 0.50",
      "    recall headroom:   \(.value.pass_bar.headroom_recall) above the required floor",
      "    bar reachable:     \(.value.pass_bar.reachable)  \(.value.pass_bar.why | join("; "))"
    )' >&2
  if [ "$rc" = 5 ]; then
    printf '\n⛔ REFUSING TO SPEND: on the primary label definition no PERFECT instrument clears the\n' >&2
    printf '  acceptance bar. The ceiling is a property of the LABEL DEFINITION, not of the sample,\n' >&2
    printf '  so collecting more rows cannot reach it. Re-define the positive class (try gate-red)\n' >&2
    printf '  or move the bar — deliberately, in the open — before any call is made.\n' >&2
  fi
  return "$rc"
}

# ── sample ────────────────────────────────────────────────────────────────────────────────────
# Reachability is checked HERE and not in the corpus module because it needs git, and it is checked
# per ROW rather than sampled: a rebased or pruned branch head leaves a row whose diff does not
# exist (docs/lessons/cited-sha-may-not-survive-the-land.md), and dropping those AFTER the
# allocation would quietly deflate whichever stratum lost most of them.
phase_sample() {
  need python3; need git
  local n=1200 holdout=0.3333 seed=20260921
  while [ $# -gt 0 ]; do
    case "$1" in
      --n) n="${2:?--n needs a number}"; shift 2 ;;
      --holdout) holdout="${2:?--holdout needs a fraction}"; shift 2 ;;
      --seed) seed="${2:?--seed needs a number}"; shift 2 ;;
      *) die "sample: unknown argument $1" ;;
    esac
  done
  [ -s "$LOG" ] || { printf '⛔ no corpus: %s is missing or empty\n' "$LOG" >&2; return 3; }
  mkdir -p "$OUTDIR" || die "cannot create $OUTDIR"
  local reach; reach="$(mktemp)" || die "mktemp failed"
  local kept=0 lost=0 head base
  while IFS= read -r row; do
    head="$(printf '%s' "$row" | jq -r '.head')"
    base="$(printf '%s' "$row" | jq -r '.base')"
    if git -C "$ROOT" cat-file -e "${head}^{commit}" 2>/dev/null \
       && git -C "$ROOT" cat-file -e "${base}^{commit}" 2>/dev/null; then
      printf '%s\n' "$row" >> "$reach"; kept=$((kept+1))
    else
      lost=$((lost+1))
    fi
  done < <(python3 "$CORPUS_PY" rows "$LOG")
  printf 'reachable %s · unreachable %s (rebased or pruned heads)\n' "$kept" "$lost" >&2
  [ "$kept" -gt 0 ] || { printf '⛔ no reachable rows — is this the right checkout?\n' >&2; rm -f "$reach"; return 3; }

  local stamp out; stamp="$(date -u +%Y%m%dT%H%M%SZ)"
  out="$OUTDIR/jev-predict-sample-$stamp"
  CC_N="$n" CC_HOLDOUT="$holdout" CC_SEED="$seed" CC_REACH="$reach" \
  CC_TRAIN="$out.train.jsonl" CC_HELD="$out.holdout.jsonl" CC_PY="$CORPUS_PY" \
  python3 - <<'PY'
import json, os, sys
sys.path.insert(0, os.path.dirname(os.environ['CC_PY']))
from predict_land_corpus import stratified_sample
rows = [json.loads(l) for l in open(os.environ['CC_REACH']) if l.strip()]
train, held = stratified_sample(rows, int(os.environ['CC_N']),
                                float(os.environ['CC_HOLDOUT']), int(os.environ['CC_SEED']))
for path, rs in ((os.environ['CC_TRAIN'], train), (os.environ['CC_HELD'], held)):
    with open(path, 'w') as fh:
        for r in rs:
            fh.write(json.dumps(r, sort_keys=True) + '\n')
sys.stderr.write('train %d · holdout %d (frozen: do not read it until the thresholds are set)\n'
                 % (len(train), len(held)))
PY
  local prc=$?
  rm -f "$reach"
  [ "$prc" = 0 ] || return 3
  printf '%s.train.jsonl\n%s.holdout.jsonl\n' "$out" "$out"
}

# ── baseline ──────────────────────────────────────────────────────────────────────────────────
# Condition (c) of the acceptance bar, and the receipt names it as the one most likely to kill this
# arm: "run shellcheck, bash -n and the dead-assertion analyzer over the same diffs and require the
# model's precision to exceed the baseline's by a margin whose CI excludes zero."
#
# THE ANALYZERS ARE THE REPO'S OWN, INVOKED THE WAY THE GATE INVOKES THEM — never re-implemented.
# A hand-rolled approximation of shellcheck would be a third authority on the same signal, and it
# would be the one whose disagreements get read as the model's win. `is_shell_file` /
# `is_python_file`'s classification is mirrored from ship-land.sh:525-535 for the same reason.
#
# 🚨 A MISSING ANALYZER IS A NON-VERDICT, NOT A CLEAN ROW. ship-land.sh:3241 records this exactly:
# unguarded, shellcheck exits 127 and the else-arm files a RED, so a box without the binary is told
# its code is broken — identically whether the code is spotless or filthy. Here the direction is the
# mirror image and worse: an absent binary would score every row CLEAN and hand the baseline a free
# loss, which is the comparator the model is measured against. So it refuses instead.
_is_shell_file() {
  case "$1" in *.sh|*.bash) return 0 ;; esac
  [ -f "$2" ] || return 1
  head -1 "$2" 2>/dev/null | grep -qiE '^#!.*(bash|zsh|ksh|dash|(/| )sh)'
}

phase_baseline() {
  need git; need jq; need python3
  local sample=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --sample) sample="${2:?--sample needs a file}"; shift 2 ;;
      *) die "baseline: unknown argument $1" ;;
    esac
  done
  [ -s "$sample" ] || die "baseline: --sample FILE is required and must be non-empty"
  # A SEAM, and it exists so the refusal below is TESTABLE. Without it the only way to exercise
  # "the analyzer is absent" is to strip PATH, which on a box where the binary sits in /usr/bin
  # cannot be done without taking bash and jq with it — so the case could only ever SKIP, on the one
  # path where scoring rows clean would silently hand the baseline a free loss. A safety refusal
  # that has never once been executed is a refusal nobody has falsified.
  local SC_BIN="${CC_PREDICT_SHELLCHECK_BIN:-shellcheck}"
  command -v "$SC_BIN" >/dev/null 2>&1 || {
    printf '⛔ REFUSING: the shell linter (%s) is NOT INSTALLED. That is a NON-VERDICT about\n' "$SC_BIN" >&2
    printf '  every row, and scoring them clean would hand the baseline a free loss in the one\n' >&2
    printf '  comparison the model must win. Install it and re-run (ship-land.sh:3241 records\n' >&2
    printf '  the mirror defect: an absent linter telling a spotless tree it was RED).\n' >&2
    return 3
  }
  local dead="$ROOT/scripts/bats-assert-liveness.py"
  [ -f "$dead" ] || { printf '⛔ REFUSING: %s is missing — same non-verdict as above.\n' "$dead" >&2; return 3; }

  # THE ANALYZER VERSIONS GO IN THE OUTPUT, not in a run log. Condition (c) compares a model against
  # THIS comparator, and a re-run months later under a different linter version is a different
  # comparator wearing the same name — the baseline would move while reading as a constant. The
  # .shellcheckrc note below is measured against 0.9.0; the rc's own header cites 0.11 behaviour, so
  # the two are already known to differ on this box.
  local sc_ver bash_ver py_ver
  sc_ver="$("$SC_BIN" --version 2>/dev/null | awk '/^version:/{print $2}')"
  bash_ver="${BASH_VERSION%%(*}"
  py_ver="$(python3 -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])' 2>/dev/null)"
  printf '{"analyzers":{"shellcheck":"%s","bash":"%s","python3":"%s"}}\n' \
         "${sc_ver:-ABSENT}" "${bash_ver:-?}" "${py_ver:-ABSENT}"

  local work; work="$(mktemp -d)" || die "mktemp -d failed"
  # shellcheck disable=SC2064
  trap "rm -rf '$work'" EXIT
  local row head base files f sc bn da n_sh n_bats score
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    head="$(printf '%s' "$row" | jq -r '.head')"
    base="$(printf '%s' "$row" | jq -r '.base')"
    rm -rf "$work/t"; mkdir -p "$work/t"
    # ── THE POLICY FILE MUST COME FROM THE SAME SHA, AND THIS WAS MEASURED, NOT ANTICIPATED ─────
    # The linter reads .shellcheckrc from the checked file's directory and its ANCESTORS, so a file
    # (and note the lead-in: a comment BEGINNING with the tool's name is parsed as a directive and
    # kills the lint for the whole file. That trap is documented 160 lines up in this same script and
    # it still caught the comment explaining it, one run later. Never open a line with the name.)
    # materialised into a bare temp tree is judged with no policy at all. Measured 2026-09-21 on the
    # real-diff fixture: 7 of 25 trunk commits scored a baseline HIT, every one of them an SC2015 or
    # SC2001 that this repo waives repo-wide — i.e. the baseline was a SECOND AUTHORITY running a
    # STRICTER standard than the gate it is supposed to stand in for, on code the gate had passed.
    # A/B on one row: 2x SC2015 without the rc, clean with it.
    # Taken from the HEAD SHA rather than the working tree, because the policy is version-controlled
    # and a row from 2026-07 must be judged under the policy in force THEN. Absent at that sha ⇒ no
    # rc, which is the right answer and not a failure.
    git -C "$ROOT" show "$head:.shellcheckrc" > "$work/t/.shellcheckrc" 2>/dev/null \
      || rm -f "$work/t/.shellcheckrc"
    # --diff-filter=d: a DELETED file has no content at head, and `git show head:path` on one fails.
    # Without the filter those failures read as unanalyzable rows and drop out of the baseline only.
    files="$(git -C "$ROOT" -c core.quotePath=false diff --name-only --diff-filter=d \
             "$base".."$head" 2>/dev/null)" || files=""
    n_sh=0; n_bats=0; sc=0; bn=0; da=0
    local shlist=() batslist=()
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      mkdir -p "$work/t/$(dirname "$f")" 2>/dev/null || continue
      git -C "$ROOT" show "$head:$f" > "$work/t/$f" 2>/dev/null || continue
      case "$f" in
        *.bats) batslist+=("$work/t/$f"); n_bats=$((n_bats+1)); continue ;;
      esac
      if _is_shell_file "$f" "$work/t/$f"; then shlist+=("$work/t/$f"); n_sh=$((n_sh+1)); fi
    done <<EOF
$files
EOF
    if [ "${#shlist[@]}" -gt 0 ]; then
      # One call over the whole set, as the gate does: the linter judges the set, so naming one
      # file would be a guess. A red says nothing about WHICH file was clean.
      #
      # ZERO vs NON-ZERO, never rc 1 vs rc 2. Measured 2026-09-21 on one materialised file carrying
      # a single SC2016: 0.9.0 exits 2 and 0.11.0 exits 1 for the IDENTICAL finding. So the rc does
      # not stably separate "findings" from "could not parse" across versions, and any consumer that
      # keyed on that distinction would reclassify rows on a linter upgrade with no diff at all.
      # ship-land.sh:3258 tests zero/non-zero for the same reason; this matches it deliberately.
      "$SC_BIN" "${shlist[@]}" >/dev/null 2>&1 || sc=1
      for f in "${shlist[@]}"; do bash -n "$f" >/dev/null 2>&1 || { bn=1; break; }; done
    fi
    if [ "${#batslist[@]}" -gt 0 ]; then
      # rc alone cannot classify this lint: rc 1 with EMPTY stdout is an uncaught exception, and rc 1
      # with findings is a red (ship-land.sh:3757). Keying on non-empty stdout is the gate's own
      # discriminator, so a traceback cannot be read as a finding.
      [ -n "$(python3 "$dead" --format text "${batslist[@]}" 2>/dev/null)" ] && da=1
    fi
    score=$((sc + bn + da))
    printf '%s' "$row" | jq -c \
      --argjson sc "$sc" --argjson bn "$bn" --argjson da "$da" \
      --argjson nsh "$n_sh" --argjson nbats "$n_bats" --argjson score "$score" \
      '{head, base, ts, class, exit, arm, red_bucket,
        baseline:{shellcheck:$sc, bash_n:$bn, dead_assertion:$da,
                  shell_files:$nsh, bats_files:$nbats, score:$score}}'
  done < "$sample"
  rm -rf "$work"; trap - EXIT
}

# ── ask ───────────────────────────────────────────────────────────────────────────────────────
# THE DECOMPOSITION IS THE POINT, and it is a claim that has to be scoreable rather than asserted.
# The obvious shape is ONE boolean — "will the gate refuse this?" — which is what A10 proposed. Five
# aimed booleans plus that roll-up cost 6x the tokens, so the run must be able to say whether they
# bought anything: each sub-boolean has its OWN label from the `red` arm, so a miss localises to a
# question instead of indicting "the model", and `score` reports max(sub-booleans) BESIDE the
# roll-up. If the roll-up wins, the decomposition was a bill.
#
# WHICH BOOLEANS, AND WHY NOT THE OTHER NINE ARMS. The receipt's adversarial pass §2 settles it:
# the static arms (209 + 41 + 106 + 218 rows — the linter, bash -n, the .bats linter and
# dead-assertion) are produced by DETERMINISTIC analyzers, so asking a model to predict them is
# paying for what those tools do free and exactly. (That sentence is deliberately not led by the
# linter's own name: a comment line BEGINNING with it parses as a directive, SC1073, and aborts the
# lint for the WHOLE file — ship-land.sh:3246 records the same paraphrase for the same reason, and
# this file tripped it on its first run anyway.)
# The semantic arms are smoke (238, a real test failed) and hermeticity
# (95, a test reached the live machine). So four questions aim at what no analyzer can reach, and
# `q_dead` aims deliberately AT an analyzed arm — as a positive control ON THE BASELINE. If the
# model does not lose that one to bats-assert-liveness.py, the baseline is not running.
_question_block() {
  cat <<'JSON'
{
  "q_refuse": { "type": "boolean",
    "instructions": "Will this repository's land gate REFUSE this diff — that is, will some check it runs go red because of what this diff changes? Judge only what the diff itself determines. A land can also fail for reasons no diff can cause (a lock timeout, a loaded machine, a push race, a missing tool on the box); those are NOT what this question asks about.",
    "criteria": { "true": "a check this diff's own content causes will go red", "false": "nothing in this diff will make a check go red" } },
  "q_smoke": { "type": "boolean",
    "instructions": "Will an existing test that covers the files this diff changes now FAIL against the new code? Judge behaviour, not style: a renamed variable that no assertion reads is not a failure, while a changed output string that a test compares against is.",
    "criteria": { "true": "a test mapped to these files asserts something the new code no longer does", "false": "the covering tests still pass, or there are none" } },
  "q_smoke_sibling": { "type": "boolean",
    "instructions": "Will a test OUTSIDE the set mapped to this diff's own files fail because of this change? This is the case where a test somewhere else COUNTS occurrences in a changed file, asserts a total, or pins a list that this diff extends — so adding a correct new site reddens a suite the author never looked at.",
    "criteria": { "true": "a test elsewhere in the tree pins a count, a total or a list that this diff moves", "false": "no test outside this diff's own mapped set reads what changed" } },
  "q_hermeticity": { "type": "boolean",
    "instructions": "Does a test this diff adds or changes reach the REAL machine instead of a fixture — reading or writing a path under the user's home directory, spawning or signalling a live process, opening a socket, or calling a scheduler — rather than going through a seam the test controls?",
    "criteria": { "true": "a changed test touches real machine state instead of a fixture", "false": "every changed test is sealed, or the diff changes no test" } },
  "q_counted_pin": { "type": "boolean",
    "instructions": "Does this diff add a NEW instance of something the repository counts or enumerates — a new call site of a guarded function, a new entry in a list some checker walks, a new file in a directory some glob audits — such that a checker asserting 'there are exactly N of these' would now be wrong?",
    "criteria": { "true": "it adds an instance of a counted or enumerated class", "false": "it changes no population that anything counts" } },
  "q_dead": { "type": "boolean",
    "instructions": "Does this diff add or change a test assertion that can NEVER FAIL — one that errexit cannot reach, such as a negated command in a non-final position, or an assertion whose both branches succeed?",
    "criteria": { "true": "an added or changed assertion is unreachable by the failure path", "false": "every added or changed assertion can actually fail" } },
  "arm": { "type": "choice",
    "instructions": "If this repository's land gate refuses this diff, WHICH check will be the one that refuses it? Choose not-diff-determined when the diff itself would pass every check, so any failure would have to come from the machine, the lock or the remote rather than from this content.",
    "criteria": {
      "none": "the gate will accept this diff",
      "not-diff-determined": "nothing in this diff causes a failure; only a machine, lock or remote fault could refuse it",
      "smoke": "a test covering the changed files fails",
      "smoke-sibling": "a test outside the changed files' own mapped set fails",
      "hermeticity": "a test reaches real machine state instead of a fixture",
      "dead-assertion": "an added or changed assertion can never fail",
      "shellcheck": "a shell static-analysis finding",
      "bash-n": "a shell file does not parse",
      "bats-shellcheck": "a static-analysis finding inside a .bats file",
      "movingref": "it moves or depends on a ref that is not stable",
      "other-arm": "some other named check in the gate" } }
}
JSON
}

phase_ask() {
  need jq; need python3; need git
  local sample=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --sample) sample="${2:?--sample needs a file}"; shift 2 ;;
      *) die "ask: unknown argument $1" ;;
    esac
  done
  [ -s "$sample" ] || die "ask: --sample FILE is required and must be non-empty"
  # shellcheck source=/dev/null
  . "$ROOT/hooks/lib/jev.sh"

  # The free-window guard first: it is a pure local read and it is the one refusal whose cost is a
  # BILL rather than a re-run. Checked before the token is spent, for the reason jev-batch.sh
  # records — burning a scarce human arming on a precondition that makes no call is the cheapest
  # possible waste.
  jev_window_open || return 3
  jev_available || {
    printf '⛔ jev is not available (no key, no deps, or CC_JEV=0). Nothing sent; arm untouched.\n' >&2
    printf '  Diagnose with: cc-jev status\n' >&2
    return 3
  }

  # ── THE AUTHORISATION. An agent must never write this file; see the header. ──────────────────
  if [ ! -f "$ARM_FILE" ]; then
    printf '⛔ NOT ARMED. This phase sends DIFFS of this repository under STANDARD retention, and\n' >&2
    printf '  a refused land'"'"'s diff may never have left this machine. That is the operator'"'"'s call.\n' >&2
    printf '  The command to authorise it:  %s arm-print\n' "$SELF" >&2
    return 6
  fi
  local corpus expires max_calls now exp_s
  corpus="$(jq -r '.corpus // empty' "$ARM_FILE" 2>/dev/null)"
  expires="$(jq -r '.expires // empty' "$ARM_FILE" 2>/dev/null)"
  max_calls="$(jq -r '.max_calls // empty' "$ARM_FILE" 2>/dev/null)"
  if [ "$corpus" != "land-diffs" ]; then
    printf '⛔ REFUSING: the arm token names corpus %s, not land-diffs. A token authorising one\n' "${corpus:-<none>}" >&2
    printf '  corpus may not be spent on another; that is consent-laundering one layer down.\n' >&2
    return 6
  fi
  [ -n "$expires" ] && [ -n "$max_calls" ] || {
    printf '⛔ REFUSING: the arm token is malformed (needs expires and max_calls). Consuming it.\n' >&2
    rm -f "$ARM_FILE"; return 6
  }
  now="$(date -u +%s)"
  exp_s="$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$expires" +%s 2>/dev/null || date -u -d "$expires" +%s 2>/dev/null)"
  if [ -z "$exp_s" ] || [ "$now" -ge "$exp_s" ]; then
    printf '⛔ the arm token expired at %s — consuming it, no call made.\n' "$expires" >&2
    rm -f "$ARM_FILE"; return 6
  fi

  # PREFLIGHT BEFORE CONSUME. One trivial call proves the route answers; without it a dead path
  # spends the whole sample and reports zeros, which is what rank-memory.sh:260 exists to prevent.
  local pf
  pf="$(jq -n '{state:"ok", questions:{p:{type:"boolean",instructions:"Is this text non-empty?"}}}' | jev_ask)" || true
  if [ -z "$(printf '%s' "$pf" | jq -r '.answers.p.probability // empty' 2>/dev/null)" ]; then
    printf '⛔ preflight produced no verdict (reason: %s). Arm PRESERVED, nothing spent.\n' "$(jev_reason "$pf")" >&2
    return 3
  fi

  # CONSUME BEFORE THE FIRST REAL CALL. A crash mid-run must not leave a live authorisation behind.
  rm -f "$ARM_FILE" || { printf '⛔ cannot consume the arm token; refusing to call.\n' >&2; return 6; }
  printf '✓ armed for land-diffs, ceiling %s calls, expires %s — token consumed.\n' "$max_calls" "$expires" >&2

  local qblock; qblock="$(_question_block)"
  local row head base stat body spec out grc calls=0 skipped_secret=0 skipped_empty=0
  local gap="${CC_PREDICT_GAP_S:-3}"
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    if [ "$calls" -ge "$max_calls" ]; then
      printf '… call ceiling %s reached; %s rows unasked. The token consented to a bound.\n' \
             "$max_calls" "$(( $(wc -l < "$sample") - calls ))" >&2
      break
    fi
    head="$(printf '%s' "$row" | jq -r '.head')"
    base="$(printf '%s' "$row" | jq -r '.base')"
    stat="$(git -C "$ROOT" diff --stat "$base".."$head" 2>/dev/null)"
    body="$(git -C "$ROOT" diff "$base".."$head" 2>/dev/null | head -c "$CAP_B")"
    if [ -z "$stat" ] && [ -z "$body" ]; then skipped_empty=$((skipped_empty+1)); continue; fi
    # ── THE DISCLOSURE GATE, AND IT SHIPPED FAIL-OPEN FOR ONE RUN ────────────────────────────
    # 🚨 `grep -qE "$SECRET_RE"` is WRONG and the end-to-end run caught it: the pattern begins with
    # `-----BEGIN`, so grep parsed it as an OPTION, printed "unrecognized option" and exited 2. In an
    # `if` that rc is falsy, so every row read as "no secret found" and was SENT — and the summary
    # line honestly reported `skipped (disclosure class) 0`, which is exactly what a clean scan looks
    # like. A safety gate that cannot run, reading as a pass, on the one check standing between an
    # unpushed diff and a third party. `-e` is what makes a leading-dash pattern a pattern.
    #
    # And rc 2 is separated from rc 1 rather than pooled, because they demand opposite actions
    # (the repo's standing `predicate-refusal-is-not-a-negative`): rc 1 is "no secret here, proceed",
    # rc 2 is "the scanner could not run", which is a NON-VERDICT over every remaining row. A
    # non-verdict on a disclosure gate stops the run; it does not quietly skip a row.
    printf '%s' "$body" | grep -qE -e "$SECRET_RE"
    grc=$?
    case "$grc" in
      0) # SKIPPED, not truncated around: a row whose payload was silently altered is no longer the
         # row the label belongs to.
         skipped_secret=$((skipped_secret+1)); continue ;;
      1) : ;;
      *) printf '⛔ ABORTING: the disclosure-class scan could not run (grep rc %s on pattern %s).\n' \
                "$grc" "$SECRET_RE" >&2
         printf '  That is a NON-VERDICT over every remaining row, not a clean pass. %s rows sent so\n' "$calls" >&2
         printf '  far; nothing further will be. Fix CC_PREDICT_SECRET_RE and re-arm.\n' >&2
         return 3 ;;
    esac
    spec="$(jq -n --arg stat "$stat" --arg diff "$body" --argjson q "$qblock" \
      '{state:("DIFFSTAT\n" + $stat + "\n\nDIFF (may be truncated)\n" + $diff), questions:$q}')"
    out="$(printf '%s' "$spec" | jev_ask)" || true
    local tries=0
    while [ "$(printf '%s' "$out" | jq -r '.reason // ""' 2>/dev/null)" = "rate-limited" ] \
          && [ "$tries" -lt "${CC_PREDICT_RETRIES:-5}" ]; do
      tries=$((tries+1))
      printf '  … rate-limited, backing off %ss (retry %s)\n' "$(( 10 * tries ))" "$tries" >&2
      sleep "$(( 10 * tries ))"
      out="$(printf '%s' "$spec" | jev_ask)" || true
    done
    calls=$((calls+1))
    printf '%s' "$row" | jq -c --argjson a "$out" '{head, base, ts, class, exit, arm, red_bucket, jev:$a}'
    sleep "$gap"
  done < "$sample"
  printf 'calls %s · skipped (empty diff) %s · skipped (disclosure class) %s\n' \
         "$calls" "$skipped_empty" "$skipped_secret" >&2
}

phase_arm_print() {
  # PRINTS. Never runs. arm.sh states the rule for its own token and it binds here identically: an
  # agent writing this file would be scripting its own authorisation, which is the thing the
  # classifier refusal exists to prevent, performed one layer down.
  cat <<EOF
The operator's command — read it, then decide. NOTHING here has been run.

  What it authorises: predict-land.sh may send DIFFS of this repository to typesafe-ai/jev under
  STANDARD retention (ZDR is Pro/Enterprise-only on this plan and 403s). For a REFUSED land that
  diff was never pushed, so these are bytes that may never have left this machine. That is the
  widening; every other Jev consumer here sends model-authored prose or our own lessons.

  Bounded by: one run (consumed before the first real call), a clock, and a call ceiling.

  mkdir -p "$(dirname "$ARM_FILE")" && jq -n \\
    --arg c "\$(date -u +%Y-%m-%dT%H:%M:%SZ)" \\
    --arg e "\$(date -u -v+180M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '+180 minutes' +%Y-%m-%dT%H:%M:%SZ)" \\
    '{created:\$c, expires:\$e, max_calls:1200, cap_b:$CAP_B, corpus:"land-diffs"}' \\
    > "$ARM_FILE"

  take it back:  rm -f "$ARM_FILE"
EOF
}

# ── score ─────────────────────────────────────────────────────────────────────────────────────
phase_score() {
  need python3
  local sample="" baseline="" ask=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --sample) sample="${2:?}"; shift 2 ;;
      --baseline) baseline="${2:?}"; shift 2 ;;
      --ask) ask="${2:?}"; shift 2 ;;
      *) die "score: unknown argument $1" ;;
    esac
  done
  [ -s "$baseline" ] || die "score: --baseline FILE is required and must be non-empty"
  CC_BASELINE="$baseline" CC_ASK="${ask:-}" CC_PY="$CORPUS_PY" \
  CC_MIN_RECALL="$MIN_RECALL" CC_MIN_PRECISION="$MIN_PRECISION" \
  python3 "$ROOT/scripts/jev/predict_land_score.py"
}

[ $# -gt 0 ] || { usage; exit 2; }
CMD="$1"; shift
case "$CMD" in
  census)    phase_census "$@" ;;
  null)      phase_null "$@" ;;
  sample)    phase_sample "$@" ;;
  baseline)  phase_baseline "$@" ;;
  ask)       phase_ask "$@" ;;
  score)     phase_score "$@" ;;
  arm-print) phase_arm_print "$@" ;;
  -h|--help) usage ;;
  *)         usage; exit 2 ;;
esac
