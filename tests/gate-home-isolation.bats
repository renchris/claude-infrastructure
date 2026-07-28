#!/usr/bin/env bats
# per-gate $HOME isolation (GATE_ARCHITECTURE_PLAN Phase 2a) — ship-land.sh
#
# THE CONTRACT, in one sentence: the gate's bats children run against an APFS clone of the
# operator's ~/, so a suite can neither be decided by nor mutate what ~40 concurrent sessions are
# doing to the live desk — and if the clone cannot be made, the gate runs EXACTLY as it does today.
#
# WHY IT MATTERS MORE THAN IT LOOKS: 109 of 126 suites are grandfathered non-hermetic. Today the
# cross-talk buys intermittence. Under the Phase 2b proof cache it buys a green that gets KEYED and
# REPLAYED — a transient false green promoted to a durable one. Hence "isolation is a correctness
# PRECONDITION for the cache", and hence GATE_HOME_ISOLATED: a run that fell open must be
# un-cacheable rather than silently inherited.
#
# This suite is hermetic (it fixtures $HOME, per scripts/test-hermeticity-lint.sh) — a suite that
# proves isolation while running against the live ~/ would be self-refuting.
#
# ASSERTION STYLE: `[ ... ]` and `... || false`. A non-final `[[ ]]` or `! cmd` is errexit-EXEMPT
# in bats and cannot fail — a dead assertion. Negatives are written as `[ "$(… | grep -c …)" -eq 0 ]`
# for the same reason.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO/scripts/ship-land.sh"

  # The operator's "live desk state" — what a non-hermetic suite reads and writes today — plus a
  # NON-cloned entry, so the symlink-farm half of the mechanism has something to prove itself on.
  mkdir -p "$HOME/.claude/autonomy" "$HOME/.reso" "$HOME/Development"
  echo LIVE > "$HOME/.claude/autonomy/idl.jsonl"
  echo LEDGER > "$HOME/.reso/ledger"
  echo PRECIOUS > "$HOME/Development/keep.txt"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  git init -q --bare "$ORIGIN"
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK"
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m base
  git push -q -u origin main

  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export LAND_LOCK_WAIT=10
  export SHIP_LAND_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export SHIP_LAND_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/nope"
  export CLAUDE_CODE_SESSION_ID="test-sid-iso"
  export POSTLAND_VERIFY=off
  export CC_GATE_MAX_LOAD=0                                  # never sit in admission control
  # Clones land INSIDE the sandbox — never in the real $TMPDIR, and never inside the fixture $HOME
  # (a clone rooted under its own source is an infinite regress).
  export SHIP_LAND_GATE_HOME_ROOT="$BATS_TEST_TMPDIR/isoroot"; mkdir -p "$SHIP_LAND_GATE_HOME_ROOT"
  # env-bleed immunity: this suite runs INSIDE an outer ship-land gate, whose own scope/tuning must
  # not decide the fixture pipelines below (tests/ship-land.bats setup() documents the same trap).
  unset SHIP_LAND_GATE_SCOPE SHIP_LAND_GATE_SCOPE_DEFAULT SHIP_LAND_GATE_POLICY \
        SHIP_LAND_GATE_SELECT SHIP_LAND_FIRST_BASE SHIP_LAND_GATE_EFFECTIVE_FULL \
        SHIP_LAND_SELECTED_N POSTLAND_STALENESS_GUARD \
        SHIP_LAND_GATE_HOME_CLONE SHIP_LAND_GATE_ROUNDS SHIP_LAND_VERIFY_RETRIES 2>/dev/null || true
  # …EXCEPT this one, which must be FORCED. A ship-land driven from inside bats is a fixture
  # pipeline and skips isolation by default (it would otherwise clone the operator's real 2.1 GB
  # ~/ once per invocation — measured: 115 s → >8 min on tests/ship-land.bats). This suite is the
  # one place that wants the real mechanism, so it opts back in explicitly.
  export SHIP_LAND_GATE_HOME_ISO=on
}

# ── fixtures ───────────────────────────────────────────────────────────────────────────────────

iso_fixture() {   # stub `bats` that REPORTS the $HOME it was handed and MUTATES the desk state
  # A stub, because this suite runs inside bats and invoking the real one would recurse — and
  # because the contract is "what environment did the gate hand the suite", which only the child
  # can answer. STUB_RC drives green / real-red / cut from one fixture.
  export PROBE="$BATS_TEST_TMPDIR/probe.txt"; : > "$PROBE"
  export STUB_RC="$BATS_TEST_TMPDIR/stub-rc"; echo 0 > "$STUB_RC"
  SHIMDIR="$BATS_TEST_TMPDIR/shims"; mkdir -p "$SHIMDIR"
  cat > "$SHIMDIR/bats" <<EOF
#!/bin/bash
{ echo "HOME=\$HOME"
  echo "ISO=\${GATE_HOME_ISOLATED-unset}"
  echo "IDL=\$(tr '\n' ',' < "\$HOME/.claude/autonomy/idl.jsonl" 2>/dev/null)"
  echo "RESO=\$(tr '\n' ',' < "\$HOME/.reso/ledger" 2>/dev/null)"
  echo "ARGS=\$*"
} >> "$PROBE"
# The cross-talk this exists to contain: a non-hermetic suite writing the operator's desk state.
echo MUTATION-FROM-GATE >> "\$HOME/.claude/autonomy/idl.jsonl" 2>/dev/null
case "\$(cat "$STUB_RC" 2>/dev/null)" in
  red) echo "1..1"; echo "not ok 1 a genuine failure"; exit 1 ;;   # a REAL red: a not-ok IS present
  cut) exit 1 ;;                                                   # a CUT: rc!=0 with ZERO output
  hang) sleep 120; exit 0 ;;                                       # outlives any sane wall budget
  *)   echo "1..1"; echo "ok 1 fine"; exit 0 ;;
esac
EOF
  chmod +x "$SHIMDIR/bats"
  export PATH="$SHIMDIR:$PATH"
  export SHIP_LAND_GATE_POLICY="$BATS_TEST_TMPDIR/no-such-policy.sh"
  mkdir -p tests
  printf '#!/usr/bin/env bats\n@test "a" { true; }\n' > tests/a.bats
  printf '#!/usr/bin/env bats\n@test "b" { true; }\n' > tests/b.bats
  git add tests && git commit -q -m "seed suites" && git push -q origin HEAD:main
  git fetch -q origin main
  # DEFAULT the selector to a stub naming both suites. v1 left it unset and relied on the FULL
  # tier ignoring selection; v2's smoke IS selection, so unset would mean the REAL gate-select.sh
  # decides — a fixture's clone behaviour keyed on the real repo's suite map. Tests that want a
  # different selection call select_suites again, which simply overwrites this.
  select_suites 'printf "tests/a.bats\ntests/b.bats\n"'
}

landable() {   # $1=branch — a trivial non-shell change (no shellcheck/bash -n in the way)
  # The FILE is keyed to the branch, not just its content. A test that lands twice branches the
  # second time from a stale local `main`; a shared filename then rebases to either "nothing to
  # land" (gate skipped, still exit 0 — a green proving nothing) or an add/add conflict (exit 5).
  local f="payload-${1//\//-}.txt"
  git checkout -q -b "$1" main
  printf '%s\n' "$1" > "$f"
  git add "$f"
  git commit -q -m "feat: payload $1"
}

select_suites() {   # $1=what the selector prints → the suites the SMOKE will run
  # v2: the smoke asks the selector ONLY for `--direct`, so that is the answer that has to carry
  # the list. v1's stub exited 0 with no output there (the plain call decided the tier), which
  # under v2 means "no direct suites" ⇒ no smoke ⇒ no clone — and every clone assertion in this
  # file would have gone vacuously red. Both entry points now print the same list.
  printf '#!/bin/bash\ncase "${1:-}" in lint) exit 0 ;; esac\n%s\n' \
    "$1" > "$BATS_TEST_TMPDIR/select.sh"
  chmod +x "$BATS_TEST_TMPDIR/select.sh"
  export SHIP_LAND_GATE_SELECT="$BATS_TEST_TMPDIR/select.sh"
}

probe_fn() {   # extract the isolation functions and drive them directly (the function-probe idiom)
  { sed -n '/^gate_home_teardown() {/,/^}/p' "$SHIPLAND"
    sed -n '/^gate_home_setup() {/,/^}/p' "$SHIPLAND"
    cat
  } > "$BATS_TEST_TMPDIR/fnprobe.sh"
  # POSITIVE CONTROL: a silent sed miss (function renamed/moved) leaves a probe that passes every
  # assertion vacuously. Require both function bodies to actually be present.
  grep -q 'gate-home.XXXXXX' "$BATS_TEST_TMPDIR/fnprobe.sh" || return 1
  grep -q 'refusing to remove an unrecognized' "$BATS_TEST_TMPDIR/fnprobe.sh" || return 1
  bash "$BATS_TEST_TMPDIR/fnprobe.sh"
}

live_clones() {   # how many isolation dirs are lying around right now
  find "$SHIP_LAND_GATE_HOME_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'gate-home.*' 2>/dev/null \
    | wc -l | tr -d ' '
}

count_in() { printf '%s\n' "$2" | grep -c -- "$1" || true; }   # live negative assertions

# ══ (a) the clone exists and is used ═══════════════════════════════════════════════════════════

@test "(a) SMOKE: bats runs under a CLONED \$HOME that carries the live desk state" {
  iso_fixture
  landable feat/iso-smoke
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ -s "$PROBE" ]                                            # the stub really ran
  # USED: the $HOME handed to bats is one of ours, and is not the operator's
  grep -q "^HOME=$SHIP_LAND_GATE_HOME_ROOT/gate-home\." "$PROBE" || false
  [ "$(count_in "^HOME=$HOME\$" "$(cat "$PROBE")")" -eq 0 ]
  # a CLONE, not an empty sandbox — the distinction that keeps this from manufacturing false REDs:
  # a suite reading the desk's state finds the desk's state.
  grep -q '^IDL=LIVE,$' "$PROBE" || false
  grep -q '^RESO=LEDGER,$' "$PROBE" || false
  grep -q '^ISO=1$' "$PROBE" || false                        # marked cacheable for Phase 2b
  echo "$output" | grep -q 'HOME isolated' || false
  # PER-SUITE, one process each — the shape the smoke runs, and never the deleted `bats tests/`.
  grep -q '^ARGS=tests/a.bats$' "$PROBE" || false
  grep -q '^ARGS=tests/b.bats$' "$PROBE" || false
  [ "$(count_in '^ARGS=tests/$' "$(cat "$PROBE")")" -eq 0 ]
}

@test "(a) the v1 CORPUS lane is isolated too — same chokepoint, both runners" {
  # gate_bats is the single chokepoint, so isolation must cover the kill switch's runner without
  # it knowing about isolation at all. Pinned because an untested kill switch rots.
  iso_fixture
  select_suites 'true'                                       # NO direct suites ⇒ no smoke at all…
  landable feat/iso-v1
  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main    # …but the corpus runs the lot
  [ "$status" -eq 0 ]
  grep -q '^ARGS=tests/a.bats$' "$PROBE" || false
  grep -q '^ARGS=tests/b.bats$' "$PROBE" || false
  grep -q "^HOME=$SHIP_LAND_GATE_HOME_ROOT/gate-home\." "$PROBE" || false
  grep -q '^IDL=LIVE,$' "$PROBE" || false
  [ "$(count_in "^HOME=$HOME\$" "$(cat "$PROBE")")" -eq 0 ]
}

@test "(a) ONE clone serves the whole smoke — not one per suite" {
  iso_fixture
  landable feat/iso-oneclone
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(grep -c '^HOME=' "$PROBE")" -eq 2 ]                                    # two suites ran
  [ "$(grep '^HOME=' "$PROBE" | sort -u | wc -l | tr -d ' ')" -eq 1 ]         # …one clone
  # …and it was a CLONE. Without this the assertion above is vacuously true of the pre-fix binary,
  # where all suites trivially share one $HOME because none of them is isolated.
  grep -q "^HOME=$SHIP_LAND_GATE_HOME_ROOT/gate-home\." "$PROBE" || false
}

@test "(a) a smoke that selects 0 suites pays nothing — no clone is made" {
  # A DIFFERENTIAL, not a bare negative: "no clone happened" is trivially true of any binary that
  # never clones, so the same fixture is run both ways and the two legs must DISAGREE. Guards the
  # cost decision — gate_home_setup sits AFTER the selection check inside run_smoke, never before
  # it, because a lint-only land must keep paying zero for a proof it never runs.
  iso_fixture
  select_suites 'true'
  landable feat/iso-lintonly
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q '0 direct suite' || false
  [ "$(count_in 'HOME isolated' "$output")" -eq 0 ]
  [ "$(live_clones)" -eq 0 ]

  select_suites 'printf "tests/a.bats\n"'                  # the other leg: one suite ⇒ one clone
  landable feat/iso-lintonly-pos
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'HOME isolated' || false
  [ "$(live_clones)" -eq 0 ]
}

@test "(a) v2: an ABSENT selector makes no clone either — no smoke, nothing to isolate" {
  # The clone follows the SELECTION, and v2 answers every uncertainty with "no smoke". A missing
  # selector is the live-symlink case (a brand-new tracked file has no symlink yet), so this is the
  # path a real deploy gap takes — it must cost nothing, not a 2.1 GB clone for a suite list that
  # was never computed.
  iso_fixture
  export SHIP_LAND_GATE_SELECT="$BATS_TEST_TMPDIR/no-such-selector.sh"
  landable feat/iso-nosel
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'missing/not executable' || false
  [ "$(count_in 'HOME isolated' "$output")" -eq 0 ]
  [ ! -s "$PROBE" ]                                        # no suite ran…
  [ "$(live_clones)" -eq 0 ]                               # …so nothing was cloned for one
}

@test "(a) v2: a SHED smoke (load >= ceiling) makes no clone — shedding costs nothing at all" {
  # Shedding is a SKIP, not a wait, and a skip that still paid ~9s for an APFS clone would be a
  # quiet tax on exactly the busy box the shed exists to protect.
  iso_fixture
  landable feat/iso-shed
  run env CC_GATE_MAX_LOAD=0.0001 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'smoke SKIPPED' || false
  [ "$(count_in 'HOME isolated' "$output")" -eq 0 ]
  [ ! -s "$PROBE" ]
  [ "$(live_clones)" -eq 0 ]
}

@test "(a) v2: under the LAND-LOCK the clone is never even reached" {
  # The invariant's cheapest corollary: run_smoke's IN_LAND_LOCK short-circuit sits BEFORE
  # gate_home_setup, so the lock does not pay for a $HOME it will never hand to a suite.
  # gate_home_setup is un-silent by construction (it announces isolation OR that it skipped), so
  # the absence of BOTH lines is proof it was never reached — not merely that isolation was off.
  iso_fixture
  landable feat/iso-inlock
  run env SHIP_LAND_GATE_ROUNDS=0 bash "$SHIPLAND" --trunk main   # straight into the lock
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'no bats inside the land-lock' || false
  [ "$(count_in 'HOME isolated' "$output")" -eq 0 ]
  [ "$(count_in 'isolation skipped' "$output")" -eq 0 ]
  [ ! -s "$PROBE" ]
  [ "$(live_clones)" -eq 0 ]
}

# ══ (b) a mutation inside the gate does NOT touch the operator's real ~/ ════════════════════════

@test "(b) a suite that mutates ~/.claude inside the gate leaves the operator's live state intact" {
  # THE test. Pre-fix, the stub's append lands in the operator's real idl.jsonl — precisely the
  # observed defect (404 stray idl.jsonl lines traced to one unfixtured suite).
  iso_fixture
  landable feat/iso-mutate
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  grep -q '^ARGS=' "$PROBE" || false                                   # the mutating stub DID run
  [ "$(cat "$HOME/.claude/autonomy/idl.jsonl")" = LIVE ]
  [ "$(grep -c MUTATION-FROM-GATE "$HOME/.claude/autonomy/idl.jsonl" || true)" -eq 0 ]
}

@test "(b) the write is not swallowed — it lands, inside the clone (positive control)" {
  # Without this, (b) would also pass if writes under the isolated $HOME silently failed: the
  # operator's file would be clean for the wrong reason, and every suite would be running blind.
  run probe_fn <<'P'
gate_home_setup
echo MUT >> "$GATE_HOME/.claude/autonomy/idl.jsonl"
grep -c MUT "$GATE_HOME/.claude/autonomy/idl.jsonl"
gate_home_teardown
P
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx '1' || false
  [ "$(cat "$HOME/.claude/autonomy/idl.jsonl")" = LIVE ]
}

@test "(b) ship-land's OWN ledger still writes to the REAL ~/ (the flake denominator survives)" {
  # Why isolation is applied at gate_bats and not around the whole gate: record_gate_cut and
  # run_scoped_suite append to $HOME/.claude/autonomy/postland/flakes.jsonl from ship-land's own
  # process. Isolating those too would write the ledger into a directory we then delete.
  iso_fixture
  echo cut > "$STUB_RC"                     # first run cuts ⇒ the CUT path calls record_gate_cut
  landable feat/iso-ledger
  run bash "$SHIPLAND" --trunk main
  echo "$output" | grep -q 'CUT, not RED' || false
  # the gate WAS isolated on this run — without this the ledger assertion below is vacuously true
  # of the pre-fix binary (where nothing is isolated and everything writes to the real ~/ anyway)
  grep -q "^HOME=$SHIP_LAND_GATE_HOME_ROOT/gate-home\." "$PROBE" || false
  [ -s "$HOME/.claude/autonomy/postland/flakes.jsonl" ]
  grep -q 'cut-not-red' "$HOME/.claude/autonomy/postland/flakes.jsonl" || false
}

# ══ (c) cleanup happens even on failure ════════════════════════════════════════════════════════
#
# Each of these asserts a clone WAS made before asserting none survives. "0 clones remain" alone is
# true of the pre-fix binary for the uninteresting reason that it never makes one — a dead
# assertion dressed as a cleanup proof.

@test "(c) cleanup on a GREEN land — no clone dir survives the gate" {
  iso_fixture
  landable feat/iso-clean-green
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  grep -q "^HOME=$SHIP_LAND_GATE_HOME_ROOT/gate-home\." "$PROBE" || false   # one was made…
  [ "$(live_clones)" -eq 0 ]                                                # …and removed
}

@test "(c) cleanup on a RED gate — a failing land still tears its clone down" {
  iso_fixture
  echo red > "$STUB_RC"
  landable feat/iso-clean-red
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 6 ]
  echo "$output" | grep -q 'bats RED' || false
  grep -q "^HOME=$SHIP_LAND_GATE_HOME_ROOT/gate-home\." "$PROBE" || false
  [ "$(live_clones)" -eq 0 ]
}

@test "(c) cleanup on a CUT smoke — the non-verdict path leaks nothing either" {
  # v2: a smoke cut twice PROCEEDS (smoke:"partial", exit 0) rather than exiting 9 — a non-verdict
  # never blocks a land. The teardown property is what this test is for and it is unchanged; only
  # the exit code the fixture produces moved, so pinning 9 here would now be pinning the v1 lane.
  iso_fixture
  echo cut > "$STUB_RC"                     # cut, then cut again ⇒ no verdict earned
  landable feat/iso-clean-cut
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'GATE-KILLED' || false          # the non-verdict WAS detected…
  echo "$output" | grep -q 'smoke PARTIAL' || false        # …and did not block the land
  grep -q "^HOME=$SHIP_LAND_GATE_HOME_ROOT/gate-home\." "$PROBE" || false
  [ "$(live_clones)" -eq 0 ]
}

@test "(c) cleanup when the smoke BUDGET kills a suite mid-run — the bound tears down too" {
  # New in v2: the wall budget can kill a bats child at any moment (timeout -k 10 on the process
  # group). The clone must still be reaped — a killed CHILD is not a killed ship-land, so the
  # normal teardown path has to cover it, and the 8h reaper is only the backstop for the latter.
  iso_fixture
  echo hang > "$STUB_RC"
  landable feat/iso-clean-budget
  run env SHIP_LAND_SMOKE_BUDGET_S=3 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'smoke PARTIAL' || false
  grep -q "^HOME=$SHIP_LAND_GATE_HOME_ROOT/gate-home\." "$PROBE" || false   # a clone WAS made…
  [ "$(live_clones)" -eq 0 ]                                                # …and removed
}

@test "(c) teardown unlinks symlinks, it does NOT follow them into the real \$HOME" {
  # The clone dir is a symlink FARM over the operator's ~/, so this `rm -rf` on a variable is the
  # most dangerous line in the change. The property gets a test, not a comment.
  run probe_fn <<'P'
gate_home_setup
[ -L "$GATE_HOME/Development" ] || { echo NOT-A-SYMLINK; exit 1; }
gate_home_teardown
P
  [ "$status" -eq 0 ]
  [ -f "$HOME/Development/keep.txt" ]
  [ "$(cat "$HOME/Development/keep.txt")" = PRECIOUS ]
}

@test "(c) teardown REFUSES a GATE_HOME it did not mint (the rm -rf name guard)" {
  export NOT_OURS="$BATS_TEST_TMPDIR/not-ours"
  mkdir -p "$NOT_OURS"; echo keep > "$NOT_OURS/f"
  run probe_fn <<'P'
GATE_HOME="$NOT_OURS"
gate_home_teardown
P
  [ "$status" -eq 0 ]
  [ -f "$NOT_OURS/f" ]
  echo "$output" | grep -q 'refusing to remove' || false
}

@test "(c) the reaper collects clones orphaned by a SIGKILL, and spares live ones" {
  # A killed shell runs no EXIT trap, and kills are 83% of observed gate deaths — the trap alone
  # would leak. Bounded at 8h so a live sibling's clone can never be caught by it.
  mkdir -p "$SHIP_LAND_GATE_HOME_ROOT/gate-home.OLDXXX" "$SHIP_LAND_GATE_HOME_ROOT/gate-home.NEWXXX"
  touch -t 202001010000 "$SHIP_LAND_GATE_HOME_ROOT/gate-home.OLDXXX"
  run probe_fn <<'P'
gate_home_setup
gate_home_teardown
P
  [ "$status" -eq 0 ]
  [ ! -d "$SHIP_LAND_GATE_HOME_ROOT/gate-home.OLDXXX" ]
  [ -d "$SHIP_LAND_GATE_HOME_ROOT/gate-home.NEWXXX" ]
}

# ══ (d) degrades safely — a broken clone NEVER blocks a land ═══════════════════════════════════

@test "(d) FAIL OPEN when the isolation dir cannot be created — the land still succeeds" {
  iso_fixture
  export SHIP_LAND_GATE_HOME_ROOT="$BATS_TEST_TMPDIR/no/such/parent"
  landable feat/iso-nomktemp
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]                                      # a land, not a block — the whole point
  grep -q "^HOME=$HOME\$" "$PROBE" || false                # ran against the live ~/, as it does today
  grep -q '^ISO=0$' "$PROBE" || false                      # …and is therefore NOT cacheable
  echo "$output" | grep -q 'fail-open' || false
}

@test "(d) FAIL OPEN when the APFS clone itself fails — and the half-built dir is removed" {
  iso_fixture
  mkdir -p "$HOME/.claude/unreadable"
  chmod 000 "$HOME/.claude/unreadable"                     # cp -Rc exits 1 on this
  landable feat/iso-noclone
  run bash "$SHIPLAND" --trunk main
  chmod 755 "$HOME/.claude/unreadable"
  [ "$status" -eq 0 ]
  grep -q "^HOME=$HOME\$" "$PROBE" || false
  grep -q '^ISO=0$' "$PROBE" || false
  echo "$output" | grep -q 'APFS clone of ~/.claude failed' || false
  echo "$output" | grep -q 'NOT cacheable' || false
  [ "$(live_clones)" -eq 0 ]                               # a PARTIAL clone is never left behind
}

@test "(d) kill switch SHIP_LAND_GATE_HOME_ISO=off restores today's behaviour exactly" {
  iso_fixture
  export SHIP_LAND_GATE_HOME_ISO=off
  landable feat/iso-killswitch
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  grep -q "^HOME=$HOME\$" "$PROBE" || false
  grep -q '^ISO=0$' "$PROBE" || false
  echo "$output" | grep -q 'isolation OFF' || false
  [ "$(live_clones)" -eq 0 ]
}

@test "(d) a FIXTURE pipeline under bats skips isolation — the gate does not pay for a test's sandbox" {
  # The cost rule, and it needs a guard because deleting it is invisible: correctness is unchanged,
  # only the clock moves. tests/ship-land.bats drives 50 nested pipelines and land-gate-cas.bats 11;
  # cloning the operator's real 2.1 GB ~/ for each took ship-land.bats 115 s → >8 min, and would
  # have put ~10 min of pure waste inside every real FULL gate that runs those suites.
  iso_fixture
  unset SHIP_LAND_GATE_HOME_ISO                            # back to the `auto` default
  landable feat/iso-fixture-skip
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'fixture pipeline under bats' || false
  grep -q "^HOME=$HOME\$" "$PROBE" || false
  [ "$(count_in 'HOME isolated' "$output")" -eq 0 ]
  [ "$(live_clones)" -eq 0 ]
}

@test "(d) a \$HOME entry that does not exist is skipped, not fatal" {
  # The bootstrap case (a machine with no ~/.reso yet): an absent clone target must not take
  # isolation down, and must not leave a ghost entry the gate would then read through.
  export SHIP_LAND_GATE_HOME_CLONE=".claude .reso .nope-not-here"
  # if/else, never `[ … ] && echo`: an and-absorbed test is a DEAD assertion
  # (scripts/bats-assert-liveness.py). Each branch prints, so the test body asserts on a value
  # that is always produced — and the ghost check becomes a POSITIVE assertion rather than a
  # negative one, which cannot pass by silence.
  run probe_fn <<'P'
gate_home_setup
echo "ISO=$GATE_HOME_ISOLATED"
if [ -d "$GATE_HOME/.claude" ]; then echo CLAUDE-OK; else echo CLAUDE-MISSING; fi
if [ -e "$GATE_HOME/.nope-not-here" ]; then echo GHOST-ENTRY; else echo NO-GHOST; fi
gate_home_teardown
P
  [ "$status" -eq 0 ]
  echo "$output" | grep -qx 'ISO=1' || false
  echo "$output" | grep -qx 'CLAUDE-OK' || false
  echo "$output" | grep -qx 'NO-GHOST' || false
}
