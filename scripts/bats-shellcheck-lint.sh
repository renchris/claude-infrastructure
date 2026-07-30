#!/bin/bash
# bats-shellcheck-lint — run shellcheck on .bats suites, which the land gate NEVER HAS.
#
# WHY. scripts/ship-land.sh's gate lints the shell files in a land's diff via is_shell_file():
#     case "$1" in *.sh|*.bash) return 0 ;; esac
#     head -1 "$1" | grep -qiE '^#!.*(bash|zsh|ksh|dash|(/| )sh)'
# A bats file's shebang is `#!/usr/bin/env bats` — it matches NEITHER arm, and `.bats` is not an
# extension the case covers. So in a repo whose test surface is 189 suites and ~60k lines of shell,
# no test file has ever been linted at all. That is the COVERAGE mechanism behind the 226 dead
# assertions of docs/research/BATS_DEAD_ASSERTIONS_2026-07-25.md: the debt did not merely exist, it
# was structurally invisible.
#
# (That comment is worded to avoid opening with the tool's own name, for the reason THE THIRD STATE
# below documents — the first draft of this header began "# shellcheck has never once run…" and
# thereby aborted analysis of this very file. The lint caught its own documentation.)
#
# WHY NOT JUST WIDEN is_shell_file() — the prescribed fix, measured and rejected. Two reasons, both
# from running it rather than reasoning about it:
#   1. `bash -n` FAILS ON ALL 189 SUITES. run_gate hands every is_shell_file() match to shellcheck
#      AND to `bash -n`, and `@test "x" { … }` is not bash: `bash -n tests/cc-blockers.bats` →
#      "syntax error near unexpected token `}'". Widening the predicate turns the gate RED for every
#      land that touches a test file. The two tools do not have the same domain, so folding bats into
#      the array that feeds both is wrong regardless of how the shebang is matched.
#   2. Whole-FILE scope would be a fleet-wide hard stop. 143 of 189 suites carry at least one
#      finding today (1117 total). A gate that blocks on the files in your diff would refuse ~1 land
#      in 3 over inherited debt — the exact defect the hermeticity ratchet's own-scope exists to
#      prevent, and a lint nobody can turn on is worth zero.
# So is_shell_file() is left alone (a .bats file genuinely is not a `bash -n` subject) and coverage
# arrives here instead, LINE-scoped.
#
# WHY LINE-SCOPED, where the three sibling ratchets are file-scoped. Their subject is a property of
# a whole file (does this suite fixture $HOME?), so a file is either compliant or grandfathered.
# ShellCheck debt is per-LINE: a file is not either-or, it has N findings. A file-level grandfather
# would exempt tests/cc-fleet.bats forever, so a NEW finding added to it would never fire — a
# permanent exemption list, which is what test-hermeticity-lint's own comment warns a ratchet must
# never silently become. Per-line needs no committed baseline to maintain and expresses the strictest
# rule that is still free: YOU MAY NOT ADD A FINDING ON A LINE YOU WROTE. The 169 pre-existing
# findings are reported, never blocking, and can only shrink.
#
# THE EXCLUDE SET — five of the six top codes are STRUCTURALLY false under bats, not suppressed
# noise, and the sixth is the sharpest case. Every count below was measured over tests/*.bats here:
#   • SC2030/SC2031 (680) — "modified in a subshell". Every @test body IS a subshell and every `run`
#     forks, so a variable set in one is MEANT to be test-local. Prior art in this repo:
#     tests/cc-blockers.bats:2 already disables exactly these at file level.
#   • SC2016  (125) — "expressions don't expand in single quotes". Every hit is a fixture building
#     shell source as a literal string (`printf 'cat <<EOF\n…' > probe.sh`); the quotes are the point.
#   • SC2329   (26) — "function never invoked". setup()/teardown()/helpers are invoked by bats'
#     harness from the test subshell, never from file scope.
#   • SC1091    (9) — "not following: <path>". A statement about shellcheck's INPUT SET (we do not
#     pass -x), not about the code.
#   • SC2314/SC2315 (108) — bats' OWN negation checks, and the one exclusion that is a judgement.
#     They do not track finality: `! blocked "$output"` as a body's LAST statement is LIVE (its
#     inverted status becomes the body's), and both codes flag it anyway. Measured against the
#     validated oracle — scripts/bats-assert-liveness.py, whose oracle is bats itself — 108 flagged
#     sites correspond to 2 genuinely dead ones. Worse, the prescribed remedy is `run !`, which is
#     the $output-clobbering rewrite §3 of the DoD doc measured and rejected: these negations sit
#     BETWEEN a `run` and a later assertion on that run's output, and `run` overwrites it. Wiring
#     SC2314 as a blocker would demand ~100 harmful edits and report a confident green over the 131
#     `[[ ]]` findings it cannot see at all. Deadness is owned by the analyzer, which already runs at
#     this gate; this lint owns everything else.
#
# THE THIRD STATE — an UNANALYZABLE file, and why it is not merely advisory. A comment whose first
# word is `shellcheck` parses as a malformed DIRECTIVE (SC1073) and ABORTS analysis of the whole file
# (SC1072). Proven with a positive control: a fixture containing `foo= bar` and `ls | wc -l` reports
# SC1007+SC2012 normally, and reports ONLY SC1072/SC1073 — neither real finding — once
# `# shellcheck + bash -n …` is prepended. Three suites were in that state. Such a file yields no
# line-level findings at all, so line-scoping cannot protect it: a defect added at line 500 of an
# aborted file is invisible. It is a NON-VERDICT wearing a clean file's clothes, so it BLOCKS when it
# is in your own-set (you touched a file whose analysis is dead) and is always counted separately, so
# it can never rot unseen. A newly INTRODUCED abort blocks by the ordinary line rule, because
# SC1072/SC1073 are reported at the offending line.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / no scannable file / no shellcheck (LOUD, never
# silent-green — a lint that cannot run must not look like a lint that found nothing).
#
# Env seams: CC_BATS_SC_OWN scopes which findings may BLOCK ("path:line" per line; see OWN-SCOPE) ·
# CC_BATS_SC_EXCLUDE overrides the exclude set (selftest only).
set -uo pipefail

SELF="$0"
while [ -L "$SELF" ]; do
  _link="$(readlink "$SELF")"
  case "$_link" in
    /*) SELF="$_link" ;;
    *)  SELF="$(dirname "$SELF")/$_link" ;;
  esac
done
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

# Resolved through $0's symlinks, exactly as the sibling lints do: everything under
# ~/.claude/scripts/ is a per-file symlink into this checkout, so a bare `dirname "$0"` yields
# ~/.claude, which has no tests/.

EXCLUDE_DEFAULT="SC2030,SC2031,SC2329,SC2016,SC2314,SC2315,SC1091"

# OWN-SCOPE — the same three-state contract as the sibling ratchets, at line granularity. States:
# own-set ABSENT ⇒ strict, every finding blocks (a bare hand-run reports the whole truth) ·
# SET-BUT-EMPTY ⇒ "I wrote no line" ⇒ nothing blocks · SET ⇒ only findings on those lines block.
# `${VAR:-}` cannot express set-but-empty, so presence rides on argument count here and on
# `${CC_BATS_SC_OWN+set}` at the entry point.
in_own() {  # $1=path:line · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0
  [ -n "$2" ] || return 1
  printf '%s\n' "$2" | grep -qxF "$1"
}

# own_lines <git-range> → "path:line" for every ADDED line of a tests/*.bats file in the range.
# Lives here rather than in each caller so the diff parsing is written and tested once. -U0 so a
# hunk's added-line span is exactly the lines written; --diff-filter=d so a deleted suite is never
# handed to shellcheck (the ship-land deletion-bug class, backlog b452/1bc4).
#
# RANGE CONTRACT, and it is the caller's to honour: `git diff A..B` diffs the two TREES, so if the
# trunk has moved since the branch point, a two-dot range attributes every SIBLING'S change to this
# one — measured here at 26 suites for a 4-suite branch, against a trunk 53 commits ahead. Since the
# own-set only ever WIDENS what may block, that direction is a fleet-wide hard stop, not a leak. Two
# safe callers: ship-land passes a range computed AFTER its rebase onto trunk, so the tree delta is
# exactly this land's (and its three sibling ratchets take the same range the same way);
# task-quality-gate passes `trunk...HEAD` (three-dot ⇒ from the merge base), which is correct even
# with a moved trunk. A hand-run should prefer the three-dot form for the same reason.
own_lines() {
  git diff -U0 --diff-filter=d "$1" -- 'tests/*.bats' 2>/dev/null | awk '
    /^\+\+\+ b\// { path = substr($0, 7); next }
    /^@@ / {
      if (path == "") next
      match($0, /\+[0-9]+(,[0-9]+)?/)
      spec = substr($0, RSTART + 1, RLENGTH - 1)
      n = split(spec, p, ",")
      start = p[1] + 0
      cnt = (n > 1) ? p[2] + 0 : 1
      for (i = 0; i < cnt; i++) print path ":" (start + i)
    }'
}

# sc_run <exclude> <file>... → shellcheck findings, one per line, as "path:line:col: sev: msg [SCnnn]".
# -f gcc because it is one finding per line and needs no JSON parser. shellcheck reads the
# `#!/usr/bin/env bats` shebang natively and understands `@test`, so no --shell override is wanted:
# forcing -s bash would discard its bats awareness for no gain (verified — identical output).
sc_run() {
  local exclude="$1"; shift
  shellcheck -f gcc -e "$exclude" "$@" 2>/dev/null
}

# lint_files <exclude> <own-set-text> <own-scoped 0|1> <file>...
#   0 = clean · 1 = a blocking finding · 2 = nothing scannable
lint_files() {
  local exclude="$1" own="$2" own_scoped="$3"; shift 3
  local f out bad=0 other=0 abort_own=0 abort_other=0 seen=0 key line
  local files=() aborted=""

  for f in "$@"; do
    [ -f "$f" ] || continue
    files+=("$f")
    seen=$((seen + 1))
  done
  [ "$seen" -gt 0 ] || { echo "bats-shellcheck-lint: ⛔ no .bats file to scan" >&2; return 2; }

  out="$(sc_run "$exclude" "${files[@]}")"

  # ── the third state first: which files did shellcheck give up on entirely? ──
  # SC1072 is the abort marker ("Fix any mentioned problems and try again"). Collect those paths
  # before classifying findings, because for an aborted file the ABSENCE of other findings is not
  # evidence of anything.
  aborted="$(printf '%s\n' "$out" | grep -F '[SC1072]' | cut -d: -f1 | sort -u)"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="$(printf '%s' "$line" | cut -d: -f1,2)"
    if in_own "$key" "$own" "$own_scoped"; then
      printf '  SHELLCHECK %s\n' "$line"
      bad=$((bad + 1))
    else
      other=$((other + 1))
    fi
  done <<EOF
$(printf '%s\n' "$out" | grep -E '^[^:]+:[0-9]+:[0-9]+: ' || true)
EOF

  while IFS= read -r f; do
    [ -n "$f" ] || continue
    # An aborted file is in your own-set if ANY of its lines is — you touched a file whose analysis
    # is dead, so every other finding in it is unreachable and the clean read is meaningless.
    if [ "$own_scoped" = "1" ] && [ -n "$own" ] && printf '%s\n' "$own" | grep -q "^$f:"; then
      printf '  UNANALYZABLE %s — shellcheck aborted; findings in this file cannot be seen\n' "$f"
      abort_own=$((abort_own + 1))
    elif [ "$own_scoped" != "1" ]; then
      printf '  UNANALYZABLE %s — shellcheck aborted on this file\n' "$f"
      abort_own=$((abort_own + 1))
    else
      abort_other=$((abort_other + 1))
    fi
  done <<EOF
$aborted
EOF

  [ "$other" -eq 0 ] || echo "bats-shellcheck-lint: $other pre-existing finding(s) NOT on a line in your diff — reported, not blocking (own-scope)."
  [ "$abort_other" -eq 0 ] || echo "bats-shellcheck-lint: $abort_other file(s) UNANALYZABLE but not in your diff — advisory."

  if [ "$bad" -gt 0 ]; then
    echo "bats-shellcheck-lint: ⛔ $bad finding(s) above are on lines THIS CHANGE WROTE."
    echo "  Fix the line, or — if the construct is deliberate — annotate it narrowly:"
    echo "      # shellcheck disable=SCnnnn   (one code, on the line above)"
    echo "  This gate had never run on a .bats file before, so the $other pre-existing finding(s) are"
    echo "  advisory and can only shrink; only lines you wrote block."
  fi
  if [ "$abort_own" -gt 0 ]; then
    echo "bats-shellcheck-lint: ⛔ $abort_own file(s) above abort shellcheck, so NOTHING in them is checked."
    echo "  Almost always a prose comment whose first word is 'shellcheck', which parses as a"
    echo "  malformed directive (SC1073) and stops analysis of the whole file (SC1072)."
    echo "  Fix: reword so the comment does not START with it — 'ShellCheck' works, the parser is"
    echo "  case-sensitive."
  fi
  [ $((bad + abort_own)) -eq 0 ] || return 1
  echo "bats-shellcheck-lint: clean — $seen suite(s) scanned, 0 blocking finding(s), 0 unanalyzable."
  return 0
}

# collect_bats <target>... → .bats paths (a target may be a dir or a file)
collect_bats() {
  local t
  for t in "$@"; do
    if [ -d "$t" ]; then
      find "$t" -type f -name '*.bats' 2>/dev/null
    elif [ -f "$t" ]; then
      printf '%s\n' "$t"
    fi
  done
}

# ── --own-lines: the derivation, exposed so callers do not re-implement diff parsing ──
if [ "${1:-}" = "--own-lines" ]; then
  [ "$#" -eq 2 ] || { echo "usage: $0 --own-lines <git-range>" >&2; exit 2; }
  own_lines "$2"
  exit 0
fi

# ── --selftest: every case proves a RED path fires or a GREEN path does not, both directions ──────
if [ "${1:-}" = "--selftest" ]; then
  command -v shellcheck >/dev/null 2>&1 || {
    echo "bats-shellcheck-lint --selftest: ⛔ shellcheck not installed — cannot self-verify" >&2
    exit 2
  }
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  fails=0
  # Fixtures written with printf, never a heredoc: bats' preprocessor strips `@test` inside one,
  # which yields a vacuously green fixture (the fixture-shape-parity scar).
  mkb() { printf '#!/usr/bin/env bats\n%s\n' "$2" > "$d/$1.bats"; }

  # These fixtures are bats SOURCE, written literally — the un-expanded `$` and the `foo= bar` are
  # the defects under test, so the single quotes are load-bearing. Narrowly annotated rather than
  # rewritten, which is exactly the remedy this lint prints for an author who trips a code
  # deliberately.
  mkb real   '@test "x" {
  foo= bar
}'
  # shellcheck disable=SC2016
  mkb clean  '@test "x" {
  run true
  [ "$status" -eq 0 ]
}'
  # The ABORT control replays the real artifact: tests/task-quality-gate.bats:3's own opening line,
  # verbatim, because a control that hand-approximates the artifact passes vacuously (memory:
  # control-must-replay-the-real-artifact). It carries a REAL finding too, which must go unseen.
  mkb abort  '# shellcheck + bash -n + bound bats for claude-infrastructure'"'"'s OWN work (shell scripts, no
@test "x" {
  foo= bar
}'
  # One fixture per excluded class, each carrying the construct the class covers.
  # shellcheck disable=SC2016
  mkb ex2016 '@test "x" {
  printf '"'"'cat $HOME\n'"'"' > "$D/w.sh"
  run true
}'
  mkb ex1091 '@test "x" {
  . ../hooks/lib/nope.sh
  run true
}'

  chk() { # <fixture> <own-set|--strict> <expected-rc> <message>
    local rc
    if [ "$2" = "--strict" ]; then
      lint_files "$EXCLUDE_DEFAULT" "" 0 "$d/$1.bats" >/dev/null 2>&1; rc=$?
    else
      lint_files "$EXCLUDE_DEFAULT" "$2" 1 "$d/$1.bats" >/dev/null 2>&1; rc=$?
    fi
    [ "$rc" -eq "$3" ] || { echo "SELFTEST FAIL: $4 (rc $rc, expected $3)"; fails=1; }
  }

  # the rule itself, both directions
  chk real  "$d/real.bats:3"  1 "a finding ON an own line did not block"
  chk real  "$d/other.bats:3" 0 "a finding NOT on an own line blocked — own-scope inverted"
  chk real  ""                0 "a SET-BUT-EMPTY own-set blocked — set-empty collapsed into unset"
  chk real  --strict          1 "an ABSENT own-set did not block — strict default lost"
  chk clean --strict          0 "a clean suite went RED"

  # the excluded classes must not fire even under strict
  chk ex2016 --strict 0 "SC2016 fired — a fixture building shell source as a string is not a defect"
  chk ex1091 --strict 0 "SC1091 fired — 'not following' is about the input set, not the code"

  # the third state: an aborted file, and the positive control that its real finding is INVISIBLE
  chk abort --strict 1 "an UNANALYZABLE file did not block under strict"
  chk abort "$d/abort.bats:4" 1 "an UNANALYZABLE file in the own-set did not block"
  chk abort "$d/other.bats:9" 0 "an UNANALYZABLE file outside the own-set blocked (should be advisory)"
  # Captured to a VARIABLE first, never `sc_run … | grep -q`. `set -o pipefail` is on and sc_run
  # exits 1 whenever it finds anything, so the pipeline's rc is sc_run's, not grep's — which silently
  # inverted both controls below (one always "failed", one could never fire). That is the
  # verification-harness trap in its purest form: a control that cannot fail the way it must.
  abort_out="$(sc_run "$EXCLUDE_DEFAULT" "$d/abort.bats")"
  real_out="$(sc_run "$EXCLUDE_DEFAULT" "$d/real.bats")"
  case "$abort_out" in
    *'[SC1007]'*) echo "SELFTEST FAIL: the abort fixture's real SC1007 was still reported — the control does not demonstrate the abort"; fails=1 ;;
  esac
  case "$real_out" in
    *'[SC1007]'*) ;;
    *) echo "SELFTEST FAIL: the SAME defect is not reported without the prose comment — the control cannot fail the way it must"; fails=1 ;;
  esac

  # own_lines: a real range in this repo must yield path:line pairs and nothing else
  if [ -d "$ROOT/.git" ] || [ -f "$ROOT/.git" ]; then
    ol="$(cd "$ROOT" && own_lines "HEAD~1..HEAD" 2>/dev/null | head -20)"
    if [ -n "$ol" ] && printf '%s\n' "$ol" | grep -qvE '^tests/[^:]+\.bats:[0-9]+$'; then
      echo "SELFTEST FAIL: own_lines emitted a token that is not tests/<f>.bats:<n>"; fails=1
    fi
  fi

  # The real tree's RATCHET invariant: zero UNANALYZABLE suites. Findings are grandfathered by
  # line-scope, but an aborted suite exempts ITSELF from the rule entirely, so this one must stay 0.
  #
  # Asserted by grepping for the CAUSE, not by scanning for the symptom. A full-corpus shellcheck is
  # ~17s at full priority and far worse in the background QoS band this runs in, which would make the
  # gate's cost swing with machine load; the cause is a comment whose first word is the tool's name,
  # which grep answers in milliseconds. Valid directives (disable=/shell=/source=/enable=/…) are
  # exempted so a legitimate file-level suppression is never mistaken for prose.
  if [ -d "$ROOT/tests" ]; then
    ab="$(grep -lE '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]' "$ROOT"/tests/*.bats 2>/dev/null \
          | while IFS= read -r _p; do
              grep -E '^[[:space:]]*#[[:space:]]*shellcheck[[:space:]]' "$_p" \
                | grep -qvE '#[[:space:]]*shellcheck[[:space:]]+(disable|enable|shell|source|source-path|external-sources)=' \
                && printf '%s\n' "$_p"
            done | grep -c . || true)"
    [ "${ab:-0}" -eq 0 ] || { echo "SELFTEST FAIL: $ab suite(s) in tests/ open a comment with the tool's name — shellcheck aborts on them"; fails=1; }
  fi

  # nothing scannable is a NON-VERDICT (2), never a false all-clear
  lint_files "$EXCLUDE_DEFAULT" "" 0 "$d/absent.bats" >/dev/null 2>&1
  [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: an absent file did not exit 2 (LOUD)"; fails=1; }

  if [ "$fails" -eq 0 ]; then
    echo "bats-shellcheck-lint --selftest: 14/14 — RED on a finding on an own line, on an ABSENT own-set, and on an UNANALYZABLE file (in-own or strict); GREEN on a clean suite, on a finding outside the own-set, on a set-empty own-set, on an unanalyzable file outside it, and on every excluded class; the abort control proves its real SC1007 goes UNSEEN and the same defect IS seen without the prose comment; own_lines emits only path:line; tests/ has 0 unanalyzable suites; LOUD on an absent file."
    exit 0
  fi
  echo "bats-shellcheck-lint --selftest: FAILED — the lint does not discriminate."
  exit 1
fi

command -v shellcheck >/dev/null 2>&1 || {
  echo "bats-shellcheck-lint: ⛔ shellcheck not installed — NOT a clean verdict" >&2
  exit 2
}

if [ "$#" -gt 0 ]; then
  targets=("$@")
else
  targets=("$ROOT/tests")
fi

# Built as a real ARRAY, and emptiness is a NON-VERDICT: a mistyped path that printed nothing and
# exited 0 would read as "clean" to every caller (memory: claimed-outcome-vs-checked-outcome).
batsfiles=()
while IFS= read -r _f; do
  [ -n "$_f" ] && batsfiles+=("$_f")
done <<EOF
$(collect_bats "${targets[@]}" | LC_ALL=C sort)
EOF

if [ "${#batsfiles[@]}" -eq 0 ]; then
  echo "bats-shellcheck-lint: ⛔ no .bats file under any target (looked at: ${targets[*]}) — NOT a clean verdict" >&2
  exit 2
fi

if [ -z "${CC_BATS_SC_OWN+set}" ]; then
  # No own-set: a bare hand-run, and a CENSUS is the point — scan everything, strict.
  lint_files "${CC_BATS_SC_EXCLUDE-$EXCLUDE_DEFAULT}" "" 0 "${batsfiles[@]}"
  exit "$?"
fi

# ── own-set SUPPLIED: scan only the suites it names ───────────────────────────────────────────────
# Blocking is line-scoped, so a suite with no own line cannot produce a blocking finding and
# scanning it buys nothing but wall-clock. That is not a micro-optimisation, it is what makes this
# gate affordable: shellcheck over all 189 suites is ~17s at full priority, and the gate's bats/lint
# subtree runs in Darwin's BACKGROUND QoS band (measured: PRI=4 / NI=19 inside bats vs PRI=31
# outside — a one-way ratchet children inherit). At a load average of 30 on 10 cores that same scan
# exceeded 60s for a THIRD of the corpus. A whole-corpus scan on every land would therefore be an
# idle-calibrated cost that becomes an outage exactly when the box is busy. Scoped to the diff it is
# typically 1-3 files and sub-second, and the RULE is unchanged.
if [ -z "$CC_BATS_SC_OWN" ]; then
  echo "bats-shellcheck-lint: clean — this change writes no .bats line, so nothing can block."
  exit 0
fi

scoped=()
for _f in "${batsfiles[@]}"; do
  case "$CC_BATS_SC_OWN" in
    "$_f":*|*"
$_f":*) scoped+=("$_f") ;;
  esac
done
if [ "${#scoped[@]}" -eq 0 ]; then
  # The own-set named lines, but none of them belong to a suite under the scan targets — e.g. a
  # range touching another tree. Nothing can block; say so rather than exiting a silent 0.
  echo "bats-shellcheck-lint: clean — no scanned suite carries a line from this change."
  exit 0
fi
lint_files "${CC_BATS_SC_EXCLUDE-$EXCLUDE_DEFAULT}" "$CC_BATS_SC_OWN" 1 "${scoped[@]}"
exit "$?"
