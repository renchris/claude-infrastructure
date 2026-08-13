#!/bin/bash
# bats-testname-eval-lint — a STRICT, zero-baseline ratchet on SHELL EXPANSION inside an @test name.
#
# WHY. bats EVALS every test description. bats-core 1.13, test_functions.bash:471:
#
#     eval "printf -v test_description '%s' \"$2\""
#
# The name is therefore expanded inside DOUBLE QUOTES, where three constructs are live:
# a backtick pair, `$(...)`, and `$VAR` / `${VAR}`. Whatever they expand to REPLACES the text in the
# rendered TAP name — and for an unset variable or a silent command that is the empty string, so the
# word is simply DELETED.
#
# TWO VARIANTS, and the quiet one is the dangerous one:
#   LOUD    the word is not a command (`auto`, `what`) → one "command not found" on stderr per test
#           in the file, which at least someone can see (19 lines for kitty-recovery-launch).
#   SILENT  the word IS a command, or the variable is merely unset (`run`, `cat`, `read`, `$pdir`)
#           → no error at all, the test PASSES, and the name is quietly wrong forever.
#
# BOTH MEASURED IN THIS TREE, 2026-08-13, which is why this lint exists rather than a fourth
# paragraph in a memory file:
#   tests/announce-before-retire.bats:356  `run`   → "INVISIBLE to the bats  harness"   (two-space gap)
#   tests/handoff-recycle-engagement.bats:101 $pdir → "writes (/<slug>/<sid>.jsonl)"
# Both were GREEN. Neither produced a diagnostic. Both are fixed; this stops the next one.
#
# WHY IT MATTERS BEYOND TIDINESS: the NAME is the only durable pointer into a suite. A TAP index
# shifts the moment anyone adds a test above, so every triage path — a postland stamp's failing[],
# a CI fold, a backlog row citing a case — quotes the name. Corrupting the name corrupts the
# fallback precisely when it is needed, which is after something has already gone wrong.
#
# WHY A LINT AND NOT A SWEEP: the class was swept across tests/ on 2026-08-10 and had regressed to
# two live sites by 2026-08-13. Detection inside a suite is not enforcement — this repo's own rule
# (ship-land.sh's kill-guard block) is that a lint enforced solely by its own bats suite is post-hoc
# DETECTION, because gate-select will not pick that suite for an unrelated diff. So this is wired at
# the two chokepoints its siblings use: ship-land's run_gate, and hooks/task-quality-gate.sh.
#
# STRICT AND WHOLE-CORPUS, with NO allowlist, deliberately — the same argument bats-kill-guard-lint
# records: the baseline was swept to ZERO first (measured: 8942 @test lines, 0 offenders in all three
# classes), and with a clean baseline the strictest rule is the free one. No own-set to derive, no
# exemption list to rot into a permanent hole.
#
# THE CURE IS ONE BACKSLASH, and the lint prints it. An author who WANTS the literal text writes
# \` or \$; an author who wanted expansion in a test NAME did not want that.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unusable scan dir (LOUD, never silent-green).
#
# SC2016 is disabled FILE-WIDE, which is unusual and deliberate — the same decision
# scripts/permission-gate-lint.sh records for the same reason. This lint's whole subject is text that
# MUST NOT EXPAND: the awk detector, and every --selftest fixture, contains literal `$pdir`,
# `$(hostname)`, `${HOME}` and backtick pairs. Expanding any of them would substitute THIS script's
# environment for the sample being matched and quietly destroy the fixtures — turning every RED case
# into a name with nothing to detect, i.e. a selftest that passes while proving nothing. That is the
# exact vacuity this file exists to prevent, so single quotes are load-bearing here, not a style
# choice. ship-land runs `shellcheck` bare, so at default severity these infos are a hard RED, and
# per-line directives would outnumber the fixtures they annotate.
# (Note the capital in "ShellCheck" wherever this file discusses the tool in prose: a comment whose
# first word is the lowercase directive name parses as a MALFORMED DIRECTIVE and aborts analysis of
# the whole file — memory slug shellcheck-prose-comment-aborts-analysis.)
# shellcheck disable=SC2016
set -uo pipefail

# Resolve $0 through symlinks before deriving ROOT: ~/.claude/scripts/ is per-file symlinks into the
# checkout, so a bare dirname would scan the live layer and report it clean (self-path-lint's rule,
# and this file must pass that lint too). BSD userland has no `readlink -f`.
SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# ── the detector ──────────────────────────────────────────────────────────────────────────────────
# ONE awk pass. Escaped forms are REMOVED first, so `\$` and a backslash-escaped backtick are legal
# and invisible to the three tests below — that is the whole cure, and a detector that flagged them
# would forbid its own fix. Order matters: strip escapes, THEN look for what survives.
DETECT='
/^@test/ {
  line = $0
  gsub(/\\\$/, "", line)          # an escaped dollar is literal — remove before testing
  gsub(/\\`/,  "", line)          # an escaped backtick likewise
  why = ""
  if (index(line, "`"))                             why = "a backtick pair is a COMMAND SUBSTITUTION"
  else if (index(line, "$("))                       why = "$( ... ) is a COMMAND SUBSTITUTION"
  else if (match(line, /\$\{[A-Za-z_]/))            why = "${VAR} EXPANDS"
  else if (match(line, /\$[A-Za-z_][A-Za-z_0-9]*/)) why = "$VAR EXPANDS"
  if (why != "") printf "%s:%d: %s — the word is DELETED from the rendered TAP name\n", FILENAME, FNR, why
}'

detect() { awk "$DETECT" "$@" 2>/dev/null; }

lint_dir() {  # <tests-dir> → 0 clean · 1 violations · 2 unusable scan dir
  local dir="$1" hits seen=0 f
  [ -d "$dir" ] || { echo "bats-testname-eval-lint: ⛔ not a directory: $dir" >&2; return 2; }
  for f in "$dir"/*.bats; do [ -e "$f" ] || continue; seen=$((seen + 1)); done
  # Scanning NOTHING is a non-verdict, not a pass — the fail-closed direction, and the same rule the
  # sibling ratchets carry. Without it a mistyped root prints nothing and exits 0, which every caller
  # reads as "clean".
  [ "$seen" -gt 0 ] || { echo "bats-testname-eval-lint: ⛔ no .bats files under $dir — NOT a clean verdict" >&2; return 2; }
  hits="$(detect "$dir"/*.bats)"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits" | sed 's/^/  /'
    echo "  FIX: backslash-escape it — \\\` or \\\$ — so the name is LITERAL text." >&2
    echo "  WHY: bats evals the description (test_functions.bash:471), so it expands in double quotes." >&2
    return 1
  fi
  echo "bats-testname-eval-lint: clean — $seen suite(s) scanned; no expanding construct in any @test name."
  return 0
}

# ── --selftest: every case proves a RED path FIRES or a GREEN path does NOT, in both directions ────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)" || { echo "bats-testname-eval-lint --selftest: ⛔ mktemp failed" >&2; exit 2; }
  mkdir -p "$d/t"
  fails=0
  mk() { printf '%s\n' "$2" > "$d/t/$1.bats"; }
  one() {  # <file> <expect-hits 0|1> <label>
    local n; n="$(detect "$d/t/$1.bats" | grep -c . || true)"
    if [ "$2" = "1" ] && [ "$n" -lt 1 ]; then echo "SELFTEST FAIL: $3 — detector stayed SILENT"; fails=1; fi
    if [ "$2" = "0" ] && [ "$n" -ne 0 ]; then echo "SELFTEST FAIL: $3 — detector FIRED on a legal name"; fails=1; fi
    rm -f "$d/t/$1.bats"
  }

  # RED: the three expanding constructs, each on its own — these are the real measured shapes.
  mk red_bt   '@test "INVISIBLE to the bats `run` harness" {'          ; one red_bt   1 "an unescaped backtick pair"
  mk red_sub  '@test "writes $(hostname) somewhere" {'                 ; one red_sub  1 'an unescaped $( ... )'
  mk red_var  '@test "the NESTED layout ($pdir/<slug>.jsonl)" {'       ; one red_var  1 'an unescaped $VAR'
  mk red_brc  '@test "the ${HOME} of it" {'                            ; one red_brc  1 'an unescaped ${VAR}'

  # GREEN: the cure itself must be legal, or the lint forbids its own fix — the failure mode that
  # makes a guard unusable (a guard whose remedy it rejects).
  mk grn_bt   '@test "INVISIBLE to the bats \`run\` harness" {'        ; one grn_bt   0 "an ESCAPED backtick (the cure)"
  mk grn_var  '@test "the NESTED layout (\$pdir/<slug>.jsonl)" {'      ; one grn_var  0 'an ESCAPED $ (the cure)'
  mk grn_none '@test "a perfectly ordinary name, 100% fine" {'         ; one grn_none 0 "a plain name"
  mk grn_math '@test "costs 5 dollars and 0 cents" {'                  ; one grn_math 0 "prose with no sigil"

  # SCOPE: a backtick that is NOT on an @test line is out of scope — the eval only ever sees the name.
  mk grn_body '@test "a fine name" {
  local x="`date`"          # a real substitution in the BODY, which bats does not eval as a name
}'                                                                     ; one grn_body 0 "a backtick in the test BODY"

  # NON-VERDICT: an unusable scan dir must be 2, never a silent green.
  lint_dir "$d/nope" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a missing scan dir did not exit 2 (LOUD)"; fails=1; }
  mkdir -p "$d/empty"
  lint_dir "$d/empty" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a dir with no .bats did not exit 2 (LOUD)"; fails=1; }

  # THE REAL TREE must be clean — the baseline this lint's strictness depends on.
  lint_dir "$ROOT/tests" >/dev/null 2>&1; rc_real=$?
  case "$rc_real" in
    0) ;;
    2) echo "SELFTEST FAIL: could not scan $ROOT/tests — a NON-VERDICT, not a clean tree"; fails=1 ;;
    *) echo "SELFTEST FAIL: the real tests/ tree carries an expanding @test name"; fails=1 ;;
  esac

  rm -rf "$d"
  if [ "$fails" -eq 0 ]; then
    echo "bats-testname-eval-lint --selftest: 12/12 — RED on an unescaped backtick, \$( ), \$VAR and \${VAR}; GREEN on both ESCAPED cures (so the lint cannot forbid its own fix), on plain prose, on a dollar-free sentence and on a backtick in the test BODY (out of scope — bats evals only the name); LOUD (2) on a missing dir and on a dir with no suites; real tests/ tree clean."
    exit 0
  fi
  echo "bats-testname-eval-lint --selftest: FAILED — the lint does not discriminate."
  exit 1
fi

case "${1:-}" in
  -h|--help) echo "usage: bats-testname-eval-lint.sh [<tests-dir>]   ·   --selftest"; exit 0 ;;
esac
lint_dir "${1:-$ROOT/tests}"
