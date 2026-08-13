#!/bin/bash
# test-walltime-lint — a RATCHET on wall-clock time bombs in bats fixtures.
#
# WHY: on 2026-07-27T00:00Z the whole fleet's gate went RED and no branch had changed.
# tests/cc-relogin-status.bats seeded `login_expires_at=2026-07-29T00:00:00Z` annotated "100h out";
# bin/claude-accounts RE-DERIVES the remaining hours from that absolute stamp and ignores the
# annotation. As the clock advanced the fixture aged to 46.8h, crossed RELOGIN_ESCALATE_H=48, and
# four tests began asserting the wrong band. Every lander on the box inherited that red until a
# sibling fixed it (`87f0f51c`). Retrying could never clear it — it would have stayed red past
# 2026-07-29 too. See GATE_ARCHITECTURE_PLAN §9: this is the DETERMINISTIC blocker class that
# §1's probabilistic (1-q)^n model does not contain.
#
# THE RULE: a FUTURE absolute date literal in non-comment test code is a time bomb, because its
# distance from `now` is what the subject actually measures, and that distance is not stable.
# The fix is always the same shape — seed RELATIVE to now:
#     exp="$(date -u -v+100H +%Y-%m-%dT%H:%M:%SZ)"     # BSD date, this box
# WARN: use a SIGNED offset. Bare `date -v 12H` SETS the hour to 12 rather than adding 12h — a
# silent wrong answer, not an error.
#
# WHY ONLY *FUTURE* DATES — a deliberately narrow rule, chosen from measurement, not taste.
# Scanning tests/ on 2026-07-27: 81 suites contain some YYYY-MM-DD, 43 have one in code, 37 fall
# within +/-2 years. Flagging all 37 would be mostly false positives — the great majority are inert
# log-line timestamps used for ORDERING or display, which nothing compares against now, and a lint
# that cries wolf 34 times gets disabled. Exactly 3 suites carry a FUTURE in-band date, and that is
# precisely the class that detonated. High precision beats high recall for a rule that BLOCKS lands.
#
# KNOWN LIMIT, stated rather than hidden: a PAST date inside a "within the last N days" assertion
# rots the same way (`cc-relogin-status` test 2, "inside the 7d attempt window", is exactly that)
# and this lint does NOT catch it — the seed and the window are in different files, so it is not
# decidable by scanning one suite. Detecting it needs the subject's threshold, not the fixture.
# Filed as future work; do not mistake a green here for "no wall-clock coupling anywhere".
#
# FAR-FUTURE SENTINELS PASS. `2099-01-01` and friends (8 suites) are the CORRECT idiom for "never
# expires" — they cannot cross a band in any operational timeframe. The horizon below is what
# separates a sentinel from a bomb.
#
# Exit: 0 = clean · 1 = violation · 2 = bad usage / unreadable scan dir (LOUD, never silent-green)
#
# Env seams: CC_WALLTIME_ALLOWLIST overrides the embedded ratchet · CC_WALLTIME_OWN scopes which
# violations may BLOCK (see OWN-SCOPE) · CC_WALLTIME_TODAY pins "now" (YYYYMMDD) for tests.
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

# ── the ratchet: suites grandfathered with a future absolute date. ONLY EVER DELETE LINES. ──
# Each entry was CHECKED, not merely observed failing — grandfathering an unexamined hit is how a
# ratchet becomes an exemption list:
#   cc-relogin-status.bats  VERIFIED INERT (false positive). Its `2026-07-28` reaches cc-blockers,
#                           which at bin/cc-blockers:81 RENDERS login_expires_at into a display cell
#                           and never re-derives a band from it; the test asserts the SEEDED state
#                           plus a row count. No comparison against now ⇒ cannot rot.
#   cc-relogin.bats         real absolute seeds (2026-08-01 / 2026-09-01 / 2027-01-01) in the
#                           hottest file on the board (~10 in-flight relogin branches) — left to its
#                           owner to convert rather than collide mid-flight.
#   (claude-accounts-core.bats was grandfathered here for frontier-window parser fixtures seeded
#    `end: "2026-07-31"`. That date ELAPSED on 2026-08-01 and the suite's remaining absolute dates
#    are all 2099 sentinels, so the ratchet reported it fixed-but-grandfathered and this line was
#    deleted 2026-08-04. Note the shape: nobody edited the file — the calendar retired the
#    exemption, which is exactly the rot the ratchet exists to force someone to look at.)
EMBEDDED_ALLOWLIST="$(cat <<'ALLOW'
cc-relogin.bats
ALLOW
)"

# HORIZON_YEARS — beyond this a date is a "never" SENTINEL, not a bomb. 10 years: far past any
# plausible band comparison, and it keeps the 2099 idiom legal without special-casing a literal.
# Read at CALL time, not load time: a load-time global cannot be overridden by an env prefix on the
# function, which made the horizon inert and its own selftest case vacuous — caught by that case.
horizon_years() { printf '%s' "${CC_WALLTIME_HORIZON_YEARS:-10}"; }

today_ymd() { printf '%s' "${CC_WALLTIME_TODAY:-$(date -u +%Y%m%d)}"; }

# OWN-SCOPE — identical contract to test-hermeticity-lint, and deliberately built in from day one:
# a whole-tree blocking lint is a FLEET-WIDE hard stop (a lander refused over a suite it never
# touched), which is the very defect §9 measures. THREE states: own-set ABSENT ⇒ strict whole-tree;
# SET-BUT-EMPTY ⇒ "I change no suite" ⇒ nothing blocks; SET ⇒ block on those only. `${VAR:-}` cannot
# express that, so presence rides on argument count here and `${CC_WALLTIME_OWN+set}` at the entry.
in_own() {  # $1=basename · $2=own-set text · $3=1 if an own-set was supplied at all
  [ "${3:-0}" = "1" ] || return 0
  [ -n "$2" ] || return 1
  printf '%s\n' "$2" | sed 's:.*/::' | grep -qxF "$1"
}

# ── COULD-NOT-CHECK is a THIRD state, never a verdict ─────────────────────────────────────────
# Ported from the twin, scripts/test-hermeticity-lint.sh, which took this fix at afaf40de ("a check
# that could not RUN is a non-verdict, not a leak") + ed4e6c6a ("retry the pure predicates before
# condemning the run"). This file kept the pre-afaf40de shape.
#
# grep answers 0=found / 1=not-found / >1=I FAILED, and BOTH predicates below discarded the third
# answer — in OPPOSITE directions, which is why neither was obvious:
#   · in_allowlist  was a bare `grep -qxF`, so a lost fork returned non-zero = "not allowlisted" and
#     the caller reported the suite as a TIMEBOMB. A FABRICATED RED about a clean tree.
#   · future_dates  was an unchecked 4-stage pipeline whose output is consumed as a string, so a lost
#     fork yielded "" = "no future dates" and a REAL bomb went unreported. A false GREEN.
# One lint, both failure directions (memory: gate-default-decides-failure-direction).
#
# This matters more here than in the twin: tests/test-walltime-lint.bats is in
# scripts/host-suites.manifest, so deploy-live runs this at nice -n 19 BESIDE a full corpus — exactly
# the fork pressure that produces rc>=2 — and the wrapper asserts -eq 0, so a fabricated RED gets
# filed automatically.
#
# Both predicates are PURE and CHEAP (a grep over a string / over one file), so re-running is free and
# side-effect-free, and the failure being retried is transient by definition. Three tries, 1s apart,
# then CHECK_FAILED — reserved for a box genuinely unable to run a grep three times in a row.
CHECK_FAILED=0

in_allowlist() { # 0 = allowlisted · 1 = not · sets CHECK_FAILED if grep could not RUN
  local rc
  for _ in 1 2 3; do
    printf '%s\n' "$2" | grep -qxF "$1"; rc=$?
    case "$rc" in
      0) return 0 ;;
      1) return 1 ;;
    esac
    sleep 1                       # transient fork pressure — see COULD-NOT-CHECK above
  done
  CHECK_FAILED=1
  return 1
}

# Future in-band dates in one suite, one per line. Comment lines are skipped: prose dates ("observed
# 2026-07-25") are documentation, never a fixture, and flagging them would train people to ignore this.
# RETURNS 3 (not CHECK_FAILED=1) when it could not run. This function is consumed inside a COMMAND
# SUBSTITUTION at the call site — `d="$(future_dates "$f" | …)"` — which is a SUBSHELL, so a global
# assigned here would be discarded and the guard would be vacuous: exactly the could-not-run-reads-as-
# an-answer defect this change exists to remove. A return code survives the subshell (pipefail carries
# it past the `tr`/`sed` stages); the caller translates it into CHECK_FAILED in the parent shell.
future_dates() { # $1=file · stdout = future in-band dates · rc 0 = answered · rc 3 = COULD NOT RUN
  local today horizon out rc
  today="$(today_ymd)"; horizon=$(( ${today%????} + $(horizon_years) ))${today#????}
  for _ in 1 2 3; do
    # rc 1 is a real ANSWER here, not a failure: `grep -oE` exits 1 when the file carries no date at
    # all, which under pipefail becomes the pipeline's rc. Only >=2 means a stage could not run.
    out="$(grep -vE '^[[:space:]]*#' "$1" 2>/dev/null \
      | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' \
      | sort -u \
      | awk -v t="$today" -v h="$horizon" '{ y=$0; gsub("-","",y); if (y+0 > t+0 && y+0 <= h+0) print $0 }')"
    rc=$?
    case "$rc" in
      0|1) printf '%s' "$out"; return 0 ;;
    esac
    sleep 1                       # transient fork pressure — see COULD-NOT-CHECK above
  done
  return 3
}

# lint <tests-dir> <allowlist-text> [own-set-text] — 0 clean · 1 violations · 2 unusable scan dir
lint_dir() {
  local dir="$1" allow="$2" own="${3:-}" own_scoped=0 f base d bombs=0 seen=0 other=0 stuck=0
  [ "$#" -ge 3 ] && own_scoped=1
  [ -d "$dir" ] || { echo "test-walltime-lint: ⛔ not a directory: $dir" >&2; return 2; }
  for f in "$dir"/*.bats; do
    [ -e "$f" ] || continue
    seen=$((seen + 1)); base="$(basename "$f")"
    d="$(future_dates "$f" | tr '\n' ' ' | sed 's/ $//')"
    # rc 3 = the date scan could not RUN for this file (see future_dates). Translate it into
    # CHECK_FAILED HERE, in the parent shell — the function itself is inside a command substitution
    # and cannot set a global that survives. Without this the empty "$d" would read as "no future
    # dates", the file would pass, and a real timebomb would go unreported: a false GREEN.
    if [ "$?" -eq 3 ]; then
      CHECK_FAILED=1
      echo "test-walltime-lint: ⛔ could not scan $base for dates after 3 tries — NOT a clean verdict for this file" >&2
      continue
    fi
    if [ -n "$d" ]; then
      if in_allowlist "$base" "$allow"; then
        continue                                   # grandfathered — known bomb, already on the list
      elif in_own "$base" "$own" "$own_scoped"; then
        printf '  TIMEBOMB %s: future absolute date(s) %s — seed RELATIVE to now, not an absolute stamp\n' "$base" "$d"
        bombs=$((bombs + 1))
      else
        printf '  bomb?    %s: future date(s) %s (NOT in your diff — advisory, not blocking)\n' "$base" "$d"
        other=$((other + 1))
      fi
    elif in_allowlist "$base" "$allow"; then
      if in_own "$base" "$own" "$own_scoped"; then
        printf '  RATCHET  %s has no future absolute date now — delete its allowlist line\n' "$base"
        stuck=$((stuck + 1))
      else
        printf '  ratchet? %s is fixed but still grandfathered (NOT in your diff — advisory)\n' "$base"
        other=$((other + 1))
      fi
    fi
  done
  [ "$seen" -gt 0 ] || { echo "test-walltime-lint: ⛔ no .bats suites under $dir" >&2; return 2; }
  [ "$other" -eq 0 ] || echo "test-walltime-lint: $other pre-existing item(s) NOT in your diff — reported, not blocking (own-scope)."

  if [ "$bombs" -gt 0 ]; then
    echo "test-walltime-lint: ⛔ $bombs suite(s) above seed a FUTURE absolute date."
    echo "  Why it matters: the subject re-derives the remaining time from the stamp, so the fixture"
    echo "  silently changes meaning as the clock advances and the suite goes red on a calendar"
    echo "  boundary with no code change. That took the whole fleet's gate down on 2026-07-27."
    # shellcheck disable=SC2016  # the single quotes are the POINT: this prints the literal
    # `$(date …)` the author must type. Expanding it here would print this machine's clock and
    # tell them to paste a fixed stamp — the exact bug the lint exists to stop.
    echo '  Fix: seed relative — exp="$(date -u -v+100H +%Y-%m-%dT%H:%M:%SZ)"   (SIGNED offset:'
    # shellcheck disable=SC2016  # ditto — literal guidance text, not an expansion
    echo '       bare `date -v 12H` SETS the hour to 12 instead of adding 12h.)'
  fi
  if [ "$stuck" -gt 0 ]; then
    echo "test-walltime-lint: ⛔ $stuck suite(s) above are fixed but still grandfathered."
    echo "  Fix: delete their lines from EMBEDDED_ALLOWLIST in $0 — the ratchet only shrinks."
  fi
  [ $((bombs + stuck)) -eq 0 ] || return 1
  echo "test-walltime-lint: clean — $seen suite(s); $(printf '%s\n' "$allow" | grep -c .) grandfathered, 0 new time bombs."
  return 0
}

# ── --selftest: every case proves a RED path fires or a GREEN path does not, both directions ──────
if [ "${1:-}" = "--selftest" ]; then
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  mkdir -p "$d/bomb" "$d/safe" "$d/sentinel" "$d/past" "$d/comment"
  mk() { printf '#!/usr/bin/env bats\n%s\n@test "x" { true; }\n' "$2" > "$d/$1/zz-fixture.bats"; }
  mk bomb     'setup() { exp="2030-01-01T00:00:00Z"; }'
  # shellcheck disable=SC2016  # written verbatim INTO a fixture file; expanding here would bake
  # an absolute stamp into the "relative seed" fixture and make the GREEN case vacuous.
  mk safe     'setup() { exp="$(date -u -v+100H +%Y-%m-%dT%H:%M:%SZ)"; }'
  mk sentinel 'setup() { exp="2099-01-01T00:00:00Z"; }'
  mk past     'setup() { exp="2020-01-01T00:00:00Z"; }'
  mk comment  '# a bomb in PROSE: 2030-01-01 was when we observed it
setup() { true; }'
  T=20260727; fails=0
  CC_WALLTIME_TODAY=$T lint_dir "$d/bomb" ""     >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a future absolute date did not go RED"; fails=1; }
  CC_WALLTIME_TODAY=$T lint_dir "$d/safe" ""     >/dev/null 2>&1 || { echo "SELFTEST FAIL: a relative-seeded suite did not go GREEN"; fails=1; }
  CC_WALLTIME_TODAY=$T lint_dir "$d/sentinel" "" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a far-future SENTINEL (2099) went RED — the never-expires idiom must stay legal"; fails=1; }
  CC_WALLTIME_TODAY=$T lint_dir "$d/past" ""     >/dev/null 2>&1 || { echo "SELFTEST FAIL: a PAST date went RED — out of scope by design"; fails=1; }
  CC_WALLTIME_TODAY=$T lint_dir "$d/comment" ""  >/dev/null 2>&1 || { echo "SELFTEST FAIL: a date in a COMMENT went RED — prose is not a fixture"; fails=1; }
  CC_WALLTIME_TODAY=$T lint_dir "$d/bomb" "zz-fixture.bats" >/dev/null 2>&1 || { echo "SELFTEST FAIL: a grandfathered bomb did not go GREEN"; fails=1; }
  CC_WALLTIME_TODAY=$T lint_dir "$d/safe" "zz-fixture.bats" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a fixed-but-still-allowlisted suite did not go RED (ratchet not shrinking)"; fails=1; }
  # own-scope, both directions + the docs-only (set-but-empty) case
  CC_WALLTIME_TODAY=$T lint_dir "$d/bomb" "" "other.bats"       >/dev/null 2>&1 || { echo "SELFTEST FAIL: a bomb OUTSIDE the own-set blocked"; fails=1; }
  CC_WALLTIME_TODAY=$T lint_dir "$d/bomb" "" "zz-fixture.bats"  >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: a bomb INSIDE the own-set did not block — own-scope disabled the rule"; fails=1; }
  CC_WALLTIME_TODAY=$T lint_dir "$d/bomb" "" ""                 >/dev/null 2>&1 || { echo "SELFTEST FAIL: an EMPTY own-set blocked — set-empty collapsed into unset"; fails=1; }
  CC_WALLTIME_TODAY=$T lint_dir "$d/bomb" ""                    >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: an ABSENT own-set did not block — strict default lost"; fails=1; }
  # the horizon is what separates sentinel from bomb — prove it MOVES the verdict
  CC_WALLTIME_TODAY=$T CC_WALLTIME_HORIZON_YEARS=200 lint_dir "$d/sentinel" "" >/dev/null 2>&1; [ "$?" -eq 1 ] || { echo "SELFTEST FAIL: with a 200y horizon the 2099 sentinel should be IN band and RED — the horizon is inert"; fails=1; }
  # the real tree must be clean, and a bad dir is a NON-VERDICT (2), never a stale-allowlist claim
  lint_dir "$ROOT/tests" "$EMBEDDED_ALLOWLIST" >/dev/null 2>&1; rc_real=$?
  case "$rc_real" in
    0) ;;
    2) echo "SELFTEST FAIL: could not scan $ROOT/tests — a NON-VERDICT (bad ROOT?), NOT a stale allowlist"; fails=1 ;;
    *) echo "SELFTEST FAIL: the embedded allowlist is stale — the real tree carries an unlisted time bomb"; fails=1 ;;
  esac
  lint_dir "$d/nope" "" >/dev/null 2>&1; [ "$?" -eq 2 ] || { echo "SELFTEST FAIL: a missing scan dir did not exit 2 (LOUD)"; fails=1; }
  if [ "$fails" -eq 0 ]; then
    echo "test-walltime-lint --selftest: 14/14 — RED on a future stamp + on a stuck ratchet entry; GREEN on relative, sentinel, past and comment-only; own-scope blocks INSIDE / advises OUTSIDE / passes set-empty / stays strict when absent; the horizon changes the verdict; real tree clean; LOUD on a bad dir."
    exit 0
  fi
  echo "test-walltime-lint --selftest: FAILED — the lint does not discriminate."
  exit 1
fi

if [ -n "${CC_WALLTIME_OWN+set}" ]; then
  lint_dir "${1:-$ROOT/tests}" "${CC_WALLTIME_ALLOWLIST-$EMBEDDED_ALLOWLIST}" "$CC_WALLTIME_OWN"
else
  lint_dir "${1:-$ROOT/tests}" "${CC_WALLTIME_ALLOWLIST-$EMBEDDED_ALLOWLIST}"
fi
rc=$?
# A predicate that could not RUN outranks BOTH answers: such a run has not earned the right to call
# the tree clean, nor to name a file as a timebomb. 2 is this file's established could-not-run code
# (lint_dir already returns it for an unusable scan dir), so no caller learns a new number.
if [ "$CHECK_FAILED" -ne 0 ]; then
  echo "test-walltime-lint: ⛔ a predicate could not RUN after 3 tries — exiting 2 (could-not-run), never 0 (clean) or 1 (timebomb)" >&2
  exit 2
fi
exit "$rc"
