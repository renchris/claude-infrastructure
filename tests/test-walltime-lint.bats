#!/usr/bin/env bats
# test-walltime-lint — the RATCHET that stops a fixture from seeding a FUTURE absolute date.
#
# The failure it exists for (2026-07-27T00:00Z): cc-relogin-status seeded login_expires_at as an
# absolute stamp annotated "100h"; claude-accounts re-derives the hours from the DATE, so as the
# clock advanced the fixture aged under RELOGIN_ESCALATE_H=48 and four tests began asserting the
# wrong band. Trunk went red with no code change and every lander inherited it. GATE_ARCHITECTURE
# _PLAN §9 files this as the deterministic blocker class that retrying can never clear.
#
# Two properties are proved here and both matter: it DISCRIMINATES (red on a future stamp, green on
# a relative seed, on a far-future sentinel, on a past date and on prose), and it is GREEN on the
# tree as it stands — a lint that ships standing-red is rot, and the nightly runs every
# scripts/*lint*.sh, so a false red here poisons the whole nightly signal.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/test-walltime-lint.sh"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"    # dogfood: this suite obeys the sibling rule
  FIX="$BATS_TEST_TMPDIR/fix"; mkdir -p "$FIX"
  T=20260727                                                # pinned "now" so THIS suite cannot rot
  # In-band future stamps are ASSEMBLED here, never written as literals: a literal would make this
  # very suite a time bomb by its own rule (verified — the lint flags it), and a lint whose own
  # tests violate it is not shippable. Assembling also keeps the suite honest: these are real
  # future dates relative to $T at run time.
  YB=$(( ${T:0:4} + 4 ))                                    # 2030 — comfortably inside the horizon
  BOMB="${YB}-01-01T00:00:00Z"
  REALY="${T:0:4}"; REAL="${REALY}-07-29T00:00:00Z"         # the literal that actually detonated
}

mk() {  # $1=dir  $2=setup-body
  mkdir -p "$FIX/$1"
  printf '#!/usr/bin/env bats\nsetup() {\n  %s\n}\n@test "x" { true; }\n' "$2" > "$FIX/$1/zz-fixture.bats"
}

@test "the real tree is CLEAN — the embedded ratchet matches HEAD, nightly stays green" {
  run bash "$LINT"
  [ "$status" -eq 0 ] || false
  echo "$output" | grep -q 'test-walltime-lint: clean' || false
}

@test "--selftest is GREEN and every discriminating case is exercised" {
  run bash "$LINT" --selftest
  [ "$status" -eq 0 ] || false
}

@test "RED: a future absolute date is a time bomb" {
  mk bomb "exp=\"$BOMB\""
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="" run bash "$LINT" "$FIX/bomb"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'TIMEBOMB' || false
}

# The regression that motivated the whole lint, reproduced with the ACTUAL literal that detonated.
@test "RED: the real relogin seed that detonated is caught while still in the future" {
  mk real "seed_login_expires_at \"$REAL\"   # annotated 100h"
  CC_WALLTIME_TODAY=20260725 CC_WALLTIME_ALLOWLIST="" run bash "$LINT" "$FIX/real"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q "${REALY}-07-29" || false
}

@test "GREEN: a relative seed is the prescribed fix and passes" {
  mk ok 'exp="$(date -u -v+100H +%Y-%m-%dT%H:%M:%SZ)"'
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="" run bash "$LINT" "$FIX/ok"
  [ "$status" -eq 0 ] || false
}

# 2099 is the CORRECT "never expires" idiom and 8 suites use it — a lint that outlawed it would be
# refactoring working code for no safety gain.
@test "GREEN: a far-future sentinel (2099) is an idiom, not a bomb" {
  mk sent 'exp="2099-01-01T00:00:00Z"'   # far-future sentinel: out of band by design, safe as a literal
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="" run bash "$LINT" "$FIX/sent"
  [ "$status" -eq 0 ] || false
}

@test "GREEN: a PAST date and a date in PROSE are both out of scope by design" {
  mk past 'exp="2020-01-01T00:00:00Z"'
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="" run bash "$LINT" "$FIX/past"
  [ "$status" -eq 0 ] || false
  mkdir -p "$FIX/prose"
  printf '#!/usr/bin/env bats\n# observed %s, a bomb in PROSE\nsetup() { true; }\n@test "x" { true; }\n' "${YB}-01-01" > "$FIX/prose/zz-fixture.bats"
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="" run bash "$LINT" "$FIX/prose"
  [ "$status" -eq 0 ] || false
}

@test "the horizon is load-bearing: widen it and the sentinel becomes a bomb" {
  mk sent 'exp="2099-01-01T00:00:00Z"'   # far-future sentinel: out of band by design, safe as a literal
  CC_WALLTIME_TODAY=$T CC_WALLTIME_HORIZON_YEARS=200 CC_WALLTIME_ALLOWLIST="" run bash "$LINT" "$FIX/sent"
  [ "$status" -eq 1 ] || false
}

@test "the ratchet only shrinks: a fixed-but-still-grandfathered suite is RED" {
  mk ok 'exp="$(date -u -v+100H +%Y-%m-%dT%H:%M:%SZ)"'
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="zz-fixture.bats" run bash "$LINT" "$FIX/ok"
  [ "$status" -eq 1 ] || false
  echo "$output" | grep -q 'RATCHET' || false
}

# Own-scope, built in from day one so this lint never becomes the fleet-wide hard stop that §9
# measures. Same three states as the hermeticity ratchet.
@test "own-scope: a bomb OUTSIDE the lander's diff is advisory; INSIDE it blocks" {
  mk bomb "exp=\"$BOMB\""
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="" CC_WALLTIME_OWN="tests/other.bats" run bash "$LINT" "$FIX/bomb"
  [ "$status" -eq 0 ] || false
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="" CC_WALLTIME_OWN="tests/zz-fixture.bats" run bash "$LINT" "$FIX/bomb"
  [ "$status" -eq 1 ] || false
}

@test "own-scope: set-but-EMPTY (a docs-only land) passes; UNSET stays strict" {
  mk bomb "exp=\"$BOMB\""
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="" CC_WALLTIME_OWN="" run bash "$LINT" "$FIX/bomb"
  [ "$status" -eq 0 ] || false
  CC_WALLTIME_TODAY=$T CC_WALLTIME_ALLOWLIST="" run env -u CC_WALLTIME_OWN bash "$LINT" "$FIX/bomb"
  [ "$status" -eq 1 ] || false
}

@test "LOUD: an unusable scan dir exits 2, never a silent green" {
  CC_WALLTIME_TODAY=$T run bash "$LINT" "$FIX/nope"
  [ "$status" -eq 2 ] || false
}

@test "ship-land runs it, own-scoped, with a kill switch" {
  grep -q 'CC_WALLTIME_OWN=' "$REPO/scripts/ship-land.sh" || false
  grep -q 'SHIP_LAND_WALL_OWN_SCOPE' "$REPO/scripts/ship-land.sh" || false
  grep -q 'test-walltime-lint.sh' "$REPO/scripts/ship-land.sh" || false
}

@test "the nightly picks it up automatically (name matches *lint*.sh AND supports --selftest)" {
  case "$(basename "$LINT")" in *lint*.sh) ;; *) false ;; esac
  grep -q -- '--selftest' "$LINT" || false
}
