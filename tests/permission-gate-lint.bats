#!/usr/bin/env bats
# permission-gate-lint — the per-file RATCHET that stops an UNBOUNDED permission gate from being
# added to an actuation path (install · deploy · land).
#
# The failure it exists for is in-tree history, not a hypothetical. deploy-live.sh's green-stamp gate
# — `no GREEN stamp among the newest N commits of origin/main ⇒ die` — was a perfectly sound
# predicate. Once the verifier stopped stamping it emitted 545 IDENTICAL refusals and froze the live
# layer for days, and every one of them read as normal, because a refusal is a STANDING STATE and a
# standing state generates no event. The fix (dcf2f11a) did not loosen the predicate; it gave it a
# CLOCK — MAX_LAG_COMMITS / MAX_LAG_HOURS, whose expiry authorises a degraded advance plus a page.
#
# The class REPRODUCES because the blame is asymmetric (inertness-generator-2026-08-07 §2.3): an
# advance that breaks something has an author — the gate that let it through — while a refusal that
# strands 104 commits has none. §6 F3 predicts more of them "unless a land-chokepoint lint forbids
# new affirmative-permission predicates on actuation paths"; §9 narrowed that after the deploy lane's
# adversarial reply, because some gates must exist. The narrowed law, which is what this enforces:
# no gate on an actuation path may be UNBOUNDED, and every affirmative-permission predicate must
# carry a finite budget whose expiry converts the standing state into an EVENT.
#
# Five properties are proved here, and all five matter:
#   • it DISCRIMINATES ON DECLAREDNESS — the two controls are the REAL artifact either side of the
#     REAL fix, and they share a predicate, a `die` and a message. Only the declaration differs. A
#     control that hand-approximates the artifact passes vacuously
#     (memory: control-must-replay-the-real-artifact);
#   • the MARKER IS A CONTRACT, not a word — a bare comment does not suppress, and neither does a
#     `gate_bounded:` with nothing after the colon;
#   • the RATCHET MOVES IN BOTH DIRECTIONS — up is a new gate, down is a stale line. Without the
#     second half a ratchet is a permanent exemption list, and a per-file COUNT (not a path
#     allowlist) is the whole point: an allowlist would exempt ship-land.sh and every future gate
#     leg added to it;
#   • it is GREEN on the tree as it stands — a lint that ships standing-red is rot, and the nightly
#     runs every scripts/*lint*.sh, so a false red here poisons the whole nightly signal;
#   • it is WIRED AT THE CHOKEPOINT — enforcement by its own suite alone is detection, not a gate
#     (memory: enforcement-must-live-at-the-chokepoint), so run_gate must invoke it.
#
# Assertions use the explicit `|| { …; false; }` form throughout: a non-final `[[ ]]` is
# errexit-EXEMPT under bats and would be a DEAD assertion that can never fail
# (memory: bats-dead-assertions-errexit-exemptions).

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/permission-gate-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"   # dogfood the sibling hermeticity rule
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
}

# mk <case> <relpath> <body> — a scan root $FIX/<case> holding one shell file
mk() {
  mkdir -p "$FIX/$1/$(dirname "$2")"
  { printf '#!/bin/bash\n'; printf '%s\n' "$3"; } > "$FIX/$1/$2"
}

# ── the ship-land leg, lifted from the REAL file and EXECUTED (cases 21-24) ──────────────────────
# Case 19 greps for the call site, which proves PRESENCE and nothing else. A leg that is present but
# never reached is precisely the inert class this whole item exists to stop, so presence is the one
# thing that must not be the test. These helpers extract the leg from scripts/ship-land.sh BY ANCHOR
# — never a copy pasted into this file, which would pass vacuously once the real leg was edited or
# deleted (memory: control-must-replay-the-real-artifact) — and run it against a stub lint whose exit
# code is the mutation.

extract_leg() {   # the real leg: from its own first line to the `fi` that closes it (2-space indent)
  awk '/^  PERMGATE_LINT=/{on=1} on{print} on && /^  fi$/{exit}' "$REPO/scripts/ship-land.sh"
}

# mk_stub <path> <rc-for---selftest> <rc-for-the-scan> <env-log>
mk_stub() {
  { printf '#!/bin/bash\n'
    printf 'if [ "${1:-}" = "--selftest" ]; then exit %s; fi\n' "$2"
    printf 'printf "OWN=[%%s]\\n" "${CC_PERMGATE_OWN-<UNSET>}" >> %s\n' "$4"
    printf 'exit %s\n' "$3"
  } > "$1"
  chmod +x "$1"
}

# The three mutants below were RUN against a scratch copy of ship-land.sh and all three are KILLED —
# a mutation test that cannot fail is worth nothing, and this harness very nearly was one:
#   · drop `GATE_RED=1; return 1` from the SCAN arm    → GATE_RED=1 rc=1 becomes 0/0  (case 22 reds)
#   · drop `GATE_RED=1; return 1` from the SELFTEST arm → 1/1 becomes 0/0 AND the scan runs (case 23)
#   · pass CC_PERMGATE_OWN="" instead of "$pgown"       → OWN=[…] becomes OWN=[]        (case 24 reds)
# THE TRAP, met while building this: a stub named by a RELATIVE path is not invocable by name, so
# bash returns 127, `if ! …` reads that as a refusal, and EVERY mutant scored "blocked" — a uniform
# false pass that looks exactly like a working guard. Absolute paths plus the -x precondition below
# close it, and case 22's clean CONTROL is the real backstop: an unreachable stub makes the green
# direction go red, so the pair cannot both pass vacuously.

# run_leg <stub> — execute the REAL leg with that stub as the lint; echoes "GATE_RED=n rc=n"
run_leg() {
  local h="$BATS_TEST_TMPDIR/harness.sh" body
  case "$1" in /*) ;; *) echo "stub must be an ABSOLUTE path ('$1') — see the 127 trap above"; return 9 ;; esac
  [ -x "$1" ] || { echo "stub '$1' is not executable — a 127 would be misread as a block"; return 9; }
  body="$(extract_leg)"
  # If the anchors stop matching, the leg was moved or renamed — that must go RED here rather than
  # silently reduce these four cases to a no-op.
  printf '%s' "$body" | grep -q 'CC_PERMGATE_OWN=' \
    || { echo "could not extract the leg from ship-land.sh — anchors no longer match"; return 9; }
  { printf '%s\n' '#!/bin/bash' 'set -uo pipefail' 'GATE_RED=0' 'range="AAA..BBB"'
    # STUB gate_red — without it cases 22/23 could never pass. The leg does not assign GATE_RED
    # directly; it calls ship-land's gate_red helper (ship-land.sh:223, used by all 27 ratchet
    # arms). Unstubbed that is a command-not-found, swallowed by the 2>/dev/null on the harness
    # run, so the leg still returned 1 while GATE_RED stayed 0 — exactly the "GATE_RED=0 rc=1"
    # both mutations reported. The mutation was not surviving; the harness could not observe it.
    printf '%s\n' 'gate_red() { GATE_RED=1; }'
    # stubbed: this land's diff touches an actuation file, so the leg must build a non-empty own-set
    printf '%s\n' 'git() { printf "%s\n" scripts/deploy-live.sh; }'
    printf 'SHIP_LAND_PERMGATE_LINT=%s\n' "$1"
    printf '%s\n' 'gate() {'
    printf '%s\n' "$body"
    printf '%s\n' '  return 0' '}' 'gate; rc=$?'
    printf '%s\n' 'printf "GATE_RED=%s rc=%s\n" "$GATE_RED" "$rc"'
  } > "$h"
  bash "$h" 2>/dev/null
}

# lint <case> [ratchet-text] — run against a fixture root with an EXPLICIT ratchet. The embedded
# ratchet names real repo paths; under a fixture root those are absent, which is itself a finding
# ("ratcheted but not in the actuation set"), so a fixture must always supply its own.
lint() { run env CC_PERMGATE_RATCHET="${2-}" bash "$LINT" "$FIX/$1"; }

# ── the two controls, lifted verbatim from the real scar and the real fix ─────────────────────────

# 0c393936:scripts/deploy-live.sh — BEFORE the fix. Two unbounded gates; the second is the one that
# produced the 545 refusals. Note the affirmative test and the refusal are 18 lines and four nesting
# levels apart: that distance is why the detector needs a block stack and not a lookback window.
mk_unbounded() {
  mk "$1" scripts/deploy-live.sh 'TARGET=""; UNSTAMPED=0; BANNER=""
if [ ! -d "$STAMPS_DIR" ]; then
  # The verification net is not active yet. Deploying is a decision, not a default.
  if [ "$BOOTSTRAP" -eq 0 ] && [ "$FORCE" -eq 0 ]; then
    if [ "$AUTO" -eq 1 ]; then
      if damp_ok "no-stamps-dir:$STAMPS_DIR"; then
        mkdir -p "$PAGES_DIR" 2>/dev/null || true
        die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active."
      fi
      exit 1   # same refusal, inside the damp window: an honest non-zero, silently
    fi
    die "no stamps dir ($STAMPS_DIR) — Re-run with --bootstrap to deploy origin/main UNSTAMPED."
  fi
  TARGET="$TIP_SHA"
else
  if [ -z "$TARGET" ]; then
    if [ "$AUTO" -eq 1 ] && ! damp_ok "no-green:$STAMPS_DIR"; then exit 1; fi
    die "no GREEN stamp among the newest $SCAN_N commits of origin/main — nothing is safe to deploy"
  fi
fi'
}

# scripts/deploy-live.sh today — AFTER the fix (dcf2f11a), with the bound DECLARED. Same `[ -z
# "$TARGET" ]` predicate, same `die`, same message. Only the budget and its declaration are new.
mk_declared() {
  mk "$1" scripts/deploy-live.sh 'LAG_COMMITS="$(g rev-list --count "$HEAD_SHA..origin/main" 2>/dev/null || echo 0)"
LAG_TRIP=""
if [ "$LAG_COMMITS" -gt "$MAX_LAG_COMMITS" ]; then
  LAG_TRIP="$LAG_COMMITS commit(s) behind trunk (budget $MAX_LAG_COMMITS)"
elif [ "$LAG_HOURS" -gt "$MAX_LAG_HOURS" ]; then
  LAG_TRIP="${LAG_HOURS}h since the live commit was authored (budget ${MAX_LAG_HOURS}h)"
fi

# gate_bounded: CC_DEPLOY_MAX_LAG_COMMITS (25) / CC_DEPLOY_MAX_LAG_HOURS (6) — whichever trips first
# authorises the T2 degraded advance to the newest NOT-RED commit, with a banner naming the clock.
if [ -z "$TARGET" ]; then
  if [ "$LAG_COMMITS" -gt 0 ] && [ -n "$LAG_TRIP" ]; then
    case "$DEGRADE" in
      off|OFF|0|no|NO|false|FALSE) : ;;
      *) TARGET="$(newest_not_red)" ;;
    esac
  fi
  if [ -z "$TARGET" ]; then
    if [ "$AUTO" -eq 1 ] && ! damp_ok "$RKEY"; then exit 1; fi
    die "$RMSG — nothing is safe to deploy (verifier: $POSTLAND_BIN)"
  fi
fi'
}

@test "1: the lint's own --selftest passes, and reports every case it ran" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  # The count is COMPUTED by the selftest, so this asserts the FORM (n/n, all passed) and a floor,
  # rather than a literal that would drift every time a case is added.
  n="$(printf '%s' "$output" | sed -n 's/.*--selftest: \([0-9]*\)\/\([0-9]*\) .*/\1 \2/p')"
  [ -n "$n" ] || { echo "no n/n count in selftest output: $output"; false; }
  ran="${n% *}"; total="${n#* }"
  [ "$ran" = "$total" ] || { echo "selftest reported $ran/$total — not all cases passed"; false; }
  [ "$ran" -ge 25 ] || { echo "selftest shrank to $ran cases — coverage was removed, not added"; false; }
}

@test "2: RED on the REAL pre-fix unbounded green-stamp gate (0c393936 — the 545-refusal scar)" {
  mk_unbounded scar
  lint scar
  [ "$status" -eq 1 ] || { echo "expected rc 1, got $status: $output"; false; }
  printf '%s' "$output" | grep -q 'PERM-GATE' || { echo "no PERM-GATE verdict: $output"; false; }
  # The refusal is four nesting levels below its affirmative test. A lookback-window detector reports
  # neither; this asserts the block stack actually reaches the enclosing gate.
  printf '%s' "$output" | grep -q 'no stamps dir' \
    || { echo "the nested stamps-dir refusal was missed — the enclosing gate is not being found: $output"; false; }
}

@test "3: GREEN on the REAL fix (dcf2f11a) once its bound is DECLARED — same predicate, same die" {
  # THE case that decides whether the rule is worth anything. If this went red the lint would be
  # keying on the presence of a refusal, which would ban gates outright — the un-narrowed §6 F3 law
  # the deploy lane rejected. If case 2 went green the lint would detect nothing at all. Only the
  # pair proves it keys on DECLAREDNESS.
  mk_declared fixed
  lint fixed
  [ "$status" -eq 0 ] || { echo "the declared bound did not suppress: $output"; false; }
}

@test "4: an ordinary comment above the gate does NOT suppress it" {
  # Without this, every commented line in the repo is an exemption — the sibling failure
  # self-path-lint's case j2 exists to prevent.
  mk bare scripts/deploy-x.sh '# The verification net is not active yet, so we refuse.
if [ ! -d "$STAMPS_DIR" ]; then
  die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active."
fi'
  lint bare
  [ "$status" -eq 1 ] || { echo "a bare comment suppressed the finding: $output"; false; }
}

@test "5: a \`gate_bounded:\` with nothing after the colon does NOT suppress — it names no budget" {
  # A marker satisfiable by typing the word is not a contract. The declaration has to say WHAT
  # expires and INTO WHAT, or the next reader learns nothing the code did not already say.
  mk empty scripts/deploy-x.sh '# gate_bounded:
if [ ! -d "$STAMPS_DIR" ]; then
  die "no stamps dir ($STAMPS_DIR) — the post-land verification net is not active."
fi'
  lint empty
  [ "$status" -eq 1 ] || { echo "an empty gate_bounded: suppressed the finding: $output"; false; }
}

@test "6: the declaration is accepted trailing on the refusal AND on the enclosing gate" {
  mk trailing scripts/deploy-x.sh 'if [ ! -d "$STAMPS_DIR" ]; then
  die "no stamps dir"   # gate_bounded: 6h of absence escalates to a page and an unstamped advance
fi'
  lint trailing
  [ "$status" -eq 0 ] || { echo "a trailing marker did not suppress: $output"; false; }

  # One declaration at the GATE must cover every exit leg beneath it — a multi-line gate declares its
  # budget once, where the budget lives, not once per `die`. Three legs here, one marker.
  mk atgate scripts/deploy-x.sh '# gate_bounded: MAX_LAG_HOURS — expiry degrades to an unstamped advance and pages
if [ ! -d "$STAMPS_DIR" ]; then
  if [ "$BOOTSTRAP" -eq 0 ]; then
    if [ "$AUTO" -eq 1 ]; then
      die "no stamps dir — the post-land verification net is not active"
    fi
    exit 1
  fi
  die "no stamps dir — re-run with --bootstrap"
fi'
  lint atgate
  [ "$status" -eq 0 ] || { echo "a declaration at the gate did not cover its nested legs: $output"; false; }
}

@test "7: the scope-outs — exit 2, usage errors, dependency probes and boolean helpers" {
  # Each is a refusal that is NOT a permission gate. If any counts, the lint fires on ordinary error
  # handling, and a lint nobody can keep on is worth zero.
  mk nonverdict scripts/deploy-x.sh 'if [ ! -f "$MANIFEST" ]; then
  echo "cannot read $MANIFEST" >&2
  exit 2
fi'
  lint nonverdict
  [ "$status" -eq 0 ] || { echo "exit 2 — the NON-VERDICT code — was counted as a gate: $output"; false; }

  mk usage scripts/deploy-x.sh 'case "$1" in
  *) printf "deploy-live: unknown arg %s\n" "$1" >&2; exit 1 ;;
esac'
  lint usage
  [ "$status" -eq 0 ] || { echo "an unknown-arg error was counted as a gate: $output"; false; }

  mk depprobe scripts/deploy-x.sh 'command -v jq >/dev/null 2>&1 || die "jq is required and is not on PATH"'
  lint depprobe
  [ "$status" -eq 0 ] || { echo "a dependency probe was counted as a gate: $output"; false; }

  # A boolean helper returning false is that function's FALSE value, not a refusal. Measured: without
  # this scope-out postland-verify.sh alone reported 20 such lines, all of them predicates.
  mk predicate scripts/deploy-x.sh 'is_green() {
  [ -n "$1" ] || return 1
  [ -f "$STAMPS/$1.json" ] || return 1
  return 0
}'
  lint predicate
  [ "$status" -eq 0 ] || { echo "a boolean helper was counted as a gate: $output"; false; }
}

@test "8: jurisdiction — a file outside the actuation set is not scanned" {
  mkdir -p "$FIX/outside/scripts"
  printf '#!/bin/bash\nif [ ! -d "$X" ]; then die "no X"; fi\n' > "$FIX/outside/scripts/render-census.sh"
  # placed beside a real actuation file, so the case cannot pass merely by finding nothing to scan
  printf '#!/bin/bash\ntrue\n' > "$FIX/outside/scripts/deploy-ok.sh"
  lint outside
  [ "$status" -eq 0 ] || { echo "a file outside the actuation set was scanned: $output"; false; }
}

@test "9: a BRAND-NEW deploy script is in scope by glob, with no list to edit" {
  # This is the reproduction mechanism itself: §2.3's class is NEW gates, often in NEW files. A
  # hand-maintained membership list would have to be edited by the very person adding the gate, so
  # membership is by GLOB and a new file arrives already in scope, at count 0.
  mk brandnew scripts/deploy-brand-new.sh 'if [ ! -f "$CURSOR" ]; then
  echo "no green cursor" >&2
  exit 1
fi'
  lint brandnew
  [ "$status" -eq 1 ] || { echo "a brand-new deploy-* file was not in scope: $output"; false; }
  printf '%s' "$output" | grep -q 'deploy-brand-new.sh' || { echo "the new file was not named: $output"; false; }
}

@test "10: the ratchet moves in BOTH directions — exact green, up red, down red" {
  mk_unbounded ratch   # measures 3 undeclared gates
  lint ratch 'scripts/deploy-live.sh 3'
  [ "$status" -eq 0 ] || { echo "the exact count did not go green: $output"; false; }

  lint ratch 'scripts/deploy-live.sh 2'
  [ "$status" -eq 1 ] || { echo "a count ABOVE the ratchet did not go red — a new gate lands unnoticed: $output"; false; }
  printf '%s' "$output" | grep -q 'PERM-GATE' || { echo "the up-direction did not report a gate: $output"; false; }

  # The down half is what stops a ratchet becoming a permanent exemption list: fixing a gate and
  # leaving its allowance behind must fail, exactly as adding one does.
  lint ratch 'scripts/deploy-live.sh 4'
  [ "$status" -eq 1 ] || { echo "a count BELOW the ratchet did not go red — the ratchet is not shrinking: $output"; false; }
  printf '%s' "$output" | grep -q 'RATCHET' || { echo "the down-direction did not report a stale line: $output"; false; }
}

@test "11: a ratchet line for a path outside the actuation set is stale — a rename is not a reset" {
  mk_declared renamed
  lint renamed 'scripts/gone-away.sh 2'
  [ "$status" -eq 1 ] || { echo "a ratchet line for an absent path survived: $output"; false; }
  printf '%s' "$output" | grep -q 'gone-away' || { echo "the stale line was not named: $output"; false; }
}

@test "12: own-scope blocks INSIDE the diff and only ADVISES outside it" {
  # A whole-set block would make every lander answerable for every other lander's file, and because
  # trunk is shared that is a fleet-wide hard stop (memory: whole-tree-lint-is-a-fleet-wide-hard-stop).
  mk_unbounded own
  run env CC_PERMGATE_RATCHET="" CC_PERMGATE_OWN="scripts/deploy-live.sh" bash "$LINT" "$FIX/own"
  [ "$status" -eq 1 ] || { echo "a finding INSIDE the own-set did not block: $output"; false; }

  run env CC_PERMGATE_RATCHET="" CC_PERMGATE_OWN="scripts/other.sh" bash "$LINT" "$FIX/own"
  [ "$status" -eq 0 ] || { echo "a finding OUTSIDE the own-set blocked: $output"; false; }
  printf '%s' "$output" | grep -q 'advisory' || { echo "the outside finding was hidden rather than labelled: $output"; false; }
}

@test "13: own-scope has THREE arity states — unset is strict, set-but-EMPTY blocks nothing" {
  # `${VAR:-}` cannot express this, and collapsing the two reinstates the hard stop for precisely the
  # docs-only land that own-scope exists for. The two runs differ ONLY in whether the var is set.
  mk_unbounded arity
  run env CC_PERMGATE_RATCHET="" bash "$LINT" "$FIX/arity"
  [ "$status" -eq 1 ] || { echo "an ABSENT own-set did not block — the strict default was lost: $output"; false; }

  run env CC_PERMGATE_RATCHET="" CC_PERMGATE_OWN="" bash "$LINT" "$FIX/arity"
  [ "$status" -eq 0 ] || { echo "an EMPTY own-set blocked — set-empty collapsed into unset: $output"; false; }
}

@test "14: an unrunnable detector is a NON-VERDICT (2), with no fabricated finding or ratchet drift" {
  # Shadowing awk reproduces what fork exhaustion does to the detector. The stakes are sharper here
  # than in a boolean lint: a killed detector returns 0 hits, and 0 against a ratchet of 3 is a count
  # that went DOWN — so a silent-green or a rc-1 would send someone to LOWER a real allowance on the
  # strength of a check that never ran (memory: named-failure-vs-no-verdict).
  mk_unbounded dead
  # A stub awk that exits 2, PREPENDED to PATH: the detector is then reached and fails, which is the
  # real shape (fork exhaustion, an unscoped pkill), rather than removed, which would be a different
  # bug. Everything else the lint runs still resolves normally.
  bindir="$BATS_TEST_TMPDIR/deadbin"; mkdir -p "$bindir"
  printf '#!/bin/sh\nexit 2\n' > "$bindir/awk"; chmod +x "$bindir/awk"
  run env PATH="$bindir:$PATH" CC_PERMGATE_RATCHET="scripts/deploy-live.sh 3" \
    bash "$LINT" "$FIX/dead"
  [ "$status" -eq 2 ] || { echo "an unrunnable detector did not exit 2 (got $status): $output"; false; }
  # `if` form, not `|| false`: a grep miss short-circuiting into `|| false` returns 1 on BOTH
  # branches, so the assertion would fail exactly when the detector behaved correctly.
  if printf '%s' "$output" | grep -q 'PERM-GATE'; then
    echo "an unrunnable detector fabricated a finding: $output"; false
  fi
  if printf '%s' "$output" | grep -q 'RATCHET  '; then
    echo "an unrunnable detector reported a ratchet drift — 0 hits is not an improvement: $output"; false
  fi
  printf '%s' "$output" | grep -q 'UNUSABLE' || { echo "the non-verdict was not announced: $output"; false; }
}

@test "15: LOUD (exit 2) on a missing scan root and on a root with no actuation file" {
  run env CC_PERMGATE_RATCHET="" bash "$LINT" "$FIX/does-not-exist"
  [ "$status" -eq 2 ] || { echo "a missing root did not exit 2: $output"; false; }

  # An EMPTY actuation set is a non-verdict, not a clean tree: it means the lint was pointed at
  # something it cannot judge, and answering 0 there is the silent green this repo bans.
  mkdir -p "$FIX/empty/docs"
  run env CC_PERMGATE_RATCHET="" bash "$LINT" "$FIX/empty"
  [ "$status" -eq 2 ] || { echo "a root with no actuation file did not exit 2: $output"; false; }
}

@test "16: the verdict does not depend on the caller's CWD" {
  # A scar from building this lint: the actuation globs were expanded against the CURRENT directory
  # before being joined to the scan root, so from the repo root — the one place a land runs — they
  # became real repo paths, matched nothing under the fixture, and every fixture read as an empty set.
  # Worst available polarity: correct from a worktree, silently unusable at the chokepoint.
  mk_unbounded cwd
  run bash -c "cd '$REPO' && CC_PERMGATE_RATCHET= exec bash '$LINT' '$FIX/cwd'"
  [ "$status" -eq 1 ] || { echo "run from the repo root, a RED fixture did not go RED: $output"; false; }
  run bash -c "cd '$BATS_TEST_TMPDIR' && CC_PERMGATE_RATCHET= exec bash '$LINT' '$FIX/cwd'"
  [ "$status" -eq 1 ] || { echo "run from a neutral directory, a RED fixture did not go RED: $output"; false; }
}

@test "17: GREEN on the real tree with the real ratchet — a lint that ships standing-red is rot" {
  run bash "$LINT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  printf '%s' "$output" | grep -q 'clean' || { echo "no clean verdict on the real tree: $output"; false; }
}

@test "18: the embedded ratchet is a MEASUREMENT — every line matches the tree it names" {
  # The counts are seeded from a real run, so a drift in either direction is caught by case 17. This
  # asserts the other half: that the ratchet contains no line for a path that is not judged at all,
  # which is how a ratchet quietly acquires entries nothing can ever retire.
  run bash "$LINT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  if printf '%s' "$output" | grep -q 'not in the actuation set'; then
    echo "the embedded ratchet names a path outside the actuation set: $output"; false
  fi
}

@test "19: WIRED AT THE CHOKEPOINT — run_gate invokes the lint, its --selftest and an own-set" {
  # Enforcement by this suite alone would be post-hoc DETECTION: gate-select picks suites by the files
  # a land touches, so a land ADDING a gate to a brand-new scripts/deploy-*.sh would never select this
  # file (memory: enforcement-must-live-at-the-chokepoint).
  grep -q 'permission-gate-lint.sh' "$REPO/scripts/ship-land.sh" \
    || { echo "ship-land.sh does not reference the lint — it is detection, not a gate"; false; }
  grep -q 'PERMGATE_LINT.*--selftest' "$REPO/scripts/ship-land.sh" \
    || { echo "the gate runs the lint without its --selftest — an unverified detector's clean verdict means nothing"; false; }
  grep -q 'CC_PERMGATE_OWN=' "$REPO/scripts/ship-land.sh" \
    || { echo "the gate does not pass an own-set — a whole-set block is a fleet-wide hard stop"; false; }
}

@test "20: the lint resolves its OWN \$0 — it must not carry the defect its sibling enforces" {
  # ~/.claude/scripts/ is a directory of per-file symlinks into this checkout. Invoked through the
  # live layer, an unresolved ROOT would land in ~/.claude, find no actuation file, and exit 2
  # forever — a permanent non-verdict wearing a clean lint's name.
  link="$BATS_TEST_TMPDIR/linked-lint.sh"
  ln -s "$LINT" "$link"
  run bash "$link" --selftest
  [ "$status" -eq 0 ] || { echo "the lint failed when invoked through a symlink: $output"; false; }
}

@test "21: the leg is REACHABLE — inside run_gate, with nothing short-circuiting ahead of it" {
  # A leg wired into an unreachable position passes case 19's grep and blocks nothing. Both facts are
  # computed from the real file, so moving the leg out of run_gate or adding an unconditional early
  # return ahead of it turns this red.
  sl="$REPO/scripts/ship-land.sh"
  start="$(awk '/^run_gate\(\)/{print NR; exit}' "$sl")"
  leg="$(awk '/^  PERMGATE_LINT=/{print NR; exit}' "$sl")"
  next="$(awk -v s="$start" 'NR>s && /^[a-zA-Z_][a-zA-Z0-9_]*\(\)/{print NR; exit}' "$sl")"
  if [ -z "$start" ] || [ -z "$leg" ] || [ -z "$next" ]; then
    echo "could not locate run_gate ($start) / the leg ($leg) / the next function ($next)"; false
  fi
  if [ "$leg" -le "$start" ] || [ "$leg" -ge "$next" ]; then
    echo "the leg at $leg is not inside run_gate ($start..$next) — it can never run"; false
  fi
  # An unconditional `return`/`exit` at run_gate's own indent level, ahead of the leg, would make it
  # dead code while every grep-based wiring check still passed.
  early="$(awk -v s="$start" -v l="$leg" 'NR>s && NR<l && /^  (return|exit)[[:space:]]/{print NR": "$0}' "$sl")"
  [ -z "$early" ] || { echo "an unconditional exit precedes the leg, so it is unreachable:"; echo "$early"; false; }
}

@test "22: MUTATION — the leg BLOCKS on a lint violation, and passes when there is none" {
  # THE assertion that makes case 19 non-vacuous: the leg is executed, and its verdict is driven by
  # the lint's exit code. Both directions, because a green that cannot go red proves nothing.
  log="$BATS_TEST_TMPDIR/env.log"; : > "$log"

  mk_stub "$BATS_TEST_TMPDIR/ok.sh"  0 0 "$log"
  out="$(run_leg "$BATS_TEST_TMPDIR/ok.sh")"
  [ "$out" = "GATE_RED=0 rc=0" ] \
    || { echo "control: a CLEAN lint did not leave the gate green (got '$out')"; false; }

  # the mutation: same leg, same harness, lint now reports a violation
  mk_stub "$BATS_TEST_TMPDIR/bad.sh" 0 1 "$log"
  out="$(run_leg "$BATS_TEST_TMPDIR/bad.sh")"
  [ "$out" = "GATE_RED=1 rc=1" ] \
    || { echo "MUTATION SURVIVED: a lint violation did not turn the gate red (got '$out') — the leg is wired but does not block"; false; }
}

@test "23: MUTATION — the leg BLOCKS when --selftest fails, so a blind detector is never trusted" {
  # A detector that no longer discriminates has a meaningless clean verdict, so the leg must refuse
  # on the selftest arm BEFORE it ever reads the scan. Proven by making the selftest fail while the
  # scan would have passed: if the arms were the wrong way round, this returns green.
  log="$BATS_TEST_TMPDIR/env2.log"; : > "$log"
  mk_stub "$BATS_TEST_TMPDIR/blind.sh" 1 0 "$log"
  out="$(run_leg "$BATS_TEST_TMPDIR/blind.sh")"
  [ "$out" = "GATE_RED=1 rc=1" ] \
    || { echo "MUTATION SURVIVED: a FAILING --selftest did not turn the gate red (got '$out')"; false; }
  # …and it short-circuits: the scan must never have been reached, or the selftest gate is decorative.
  [ ! -s "$log" ] \
    || { echo "the scan ran despite a failing --selftest — the guard is not short-circuiting: $(cat "$log")"; false; }
}

@test "24: the leg hands the lint a NON-EMPTY own-set when the land touches an actuation file" {
  # The env-var contract, executed rather than grepped. An UNSET own-set is a whole-set block — a
  # fleet-wide hard stop; a set-but-EMPTY one silently downgrades every finding to advisory, which is
  # the quieter and worse failure. The stub records what it actually received.
  log="$BATS_TEST_TMPDIR/env3.log"; : > "$log"
  mk_stub "$BATS_TEST_TMPDIR/rec.sh" 0 0 "$log"
  run_leg "$BATS_TEST_TMPDIR/rec.sh" >/dev/null
  grep -q 'OWN=\[scripts/deploy-live.sh\]' "$log" \
    || { echo "the leg did not pass the land's own actuation file as the own-set: $(cat "$log")"; false; }
}
