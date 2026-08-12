#!/usr/bin/env bats
# land-gate-cas.bats — the land-gate serialization fix (2026-07-25): the gate runs UNLOCKED
# (parallel across sessions); the landing lock covers ONLY the CAS race window (fetch-compare →
# push → content-verify). RED-proofed against the pre-fix pipeline, which ran the entire gate
# INSIDE the lock:
#   * "gate runs unlocked"      → pre-fix the gate observer records LOCKED, not UNLOCKED.
#   * "stale-gate re-gate"      → pre-fix a sibling land mid-gate ⇒ push non-ff exit 7 (no
#                                 re-gate, land FAILS); post-fix exit 42 → unlocked re-gate
#                                 of the new final tree → land succeeds, nothing dropped.
#   * "dry-run takes no lock"   → pre-fix dry-run held the mutex for the whole gate.
#   * "hold-time collapse"      → pre-fix hold_s ≥ gate duration; post-fix hold_s ≈ 0.
#
# v2 (LAND_PIPELINE_V2 §4.1) ADDS the invariant this suite is now the primary home of: NOTHING
# HEAVY MAY EVER ENTER THE LOCK, in EITHER lane. The 2026-07-25 fix moved the gate out of the
# lock but left TWO paths that could put a corpus back in — the rounds-exhausted fallback and the
# content-drop recovery re-gate — and the first of those produced a 3h36m lock holder while every
# other lander queued behind it, then a multi-day jam when the corpus hung. v2 bans it in
# run_gate, keyed on IN_LAND_LOCK, so no call site can forget. Every in-lock test below therefore
# asserts a bats INVOCATION COUNT of zero, not merely a green outcome: the statics still run under
# the lock (they are milliseconds and the observer records LOCKED for them), so an outcome
# assertion alone cannot tell "statics only" from "statics plus a corpus".
#
# INSTRUMENTATION (durable products, not narration): a PATH-shimmed `shellcheck` appends
# LOCKED/UNLOCKED per gate invocation to $GATE_OBS by testing whether the landing mutex dir
# exists at run time (single-lander tests only — no other holder can exist), and — as the
# deterministic race injector — lands a sibling commit straight onto origin/main from a
# second clone while running UNLOCKED, i.e. exactly inside the gate→lock window. Every
# landing branch carries a .sh file so the shim (the gate's shellcheck step) always fires.
# Scratch bare origin + clones under BATS_TEST_TMPDIR; no real machine state is touched.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SHIPLAND="$REPO/scripts/ship-land.sh"

  ORIGIN="$BATS_TEST_TMPDIR/origin.git"
  WORK="$BATS_TEST_TMPDIR/work"
  SIB="$BATS_TEST_TMPDIR/sib"
  git init -q --bare "$ORIGIN"
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main   # clones of the bare origin land on main
  git clone -q "$ORIGIN" "$WORK"
  cd "$WORK" || exit 1
  git config user.email tester@example.com
  git config user.name tester
  git checkout -q -b main
  echo base > base.txt
  git add base.txt
  git commit -q -m base
  git push -q -u origin main

  # sibling clone: the shim lands its commits directly onto origin/main (a concurrent
  # lander winning the race mid-gate, distilled to its trunk-moving effect).
  git clone -q "$ORIGIN" "$SIB"
  git -C "$SIB" config user.email sib@example.com
  git -C "$SIB" config user.name sib

  export LAND_LOG="$BATS_TEST_TMPDIR/land.log"
  export LAND_LOCK_DIR="$BATS_TEST_TMPDIR/lock"
  export LAND_LOCK_WAIT=30
  export SHIP_LAND_DECISIONS_DIR="$BATS_TEST_TMPDIR/decisions"
  export SHIP_LAND_SHARED_CHECKOUT="$BATS_TEST_TMPDIR/nope"
  export CLAUDE_CODE_SESSION_ID="test-sid-cas"
  export POSTLAND_DIR="$BATS_TEST_TMPDIR/postland"
  export POSTLAND_VERIFY=off                     # never spawn a real post-land child from tests
  # env-bleed immunity (see ship-land.bats setup): an outer gate's tuning must not leak in.
  # SHIP_LAND_LANE is the one that matters most here — an operator landing with the v1 kill switch
  # on would put a corpus inside every fixture pipeline below, i.e. exactly the thing these tests
  # assert cannot happen, and the failure would look like a real regression.
  unset SHIP_LAND_GATE_SCOPE SHIP_LAND_GATE_SCOPE_DEFAULT SHIP_LAND_GATE_POLICY \
        SHIP_LAND_GATE_SELECT SHIP_LAND_FIRST_BASE SHIP_LAND_GATE_EFFECTIVE_FULL \
        SHIP_LAND_SELECTED_N POSTLAND_STALENESS_GUARD \
        SHIP_LAND_LANE SHIP_LAND_SMOKE_BUDGET_S SHIP_LAND_SMOKE_NICE SHIP_LAND_TIMEOUT_BIN \
        SHIP_LAND_SMOKE_STATE SHIP_LAND_SMOKE_N SHIP_LAND_SMOKE_S SHIP_LAND_NET_STATE \
        2>/dev/null || true
  export CC_GATE_MAX_LOAD=0            # never shed: a fixture's smoke must not depend on `uptime`
  # THIS SUITE MEASURES LOCK TOPOLOGY, AND ITS INSTRUMENT IS A shellcheck-INVOCATION COUNTER.
  # The P3 statics memo (scripts/lib/gate-memo.sh) deliberately stops re-invoking shellcheck on a
  # re-round whose files are byte-identical — which is exactly the redundancy it exists to remove,
  # and exactly what would make "gate runs = shim lines" read low here. It also probes
  # `shellcheck --version` once per gate to salt its key, which would read high. Both are correct
  # behaviour and neither is what these tests are about, so the memo is pinned OFF: the observer
  # then counts one line per gate invocation again, as it did when it was written. The memo's own
  # behaviour — carrying, invalidating, and its failure direction — is pinned by
  # tests/land-gate-memo.bats, which owns that question and instruments it separately.
  # (Repo memory: control-calibrated-to-implementation-decays — key the control on the MECHANISM
  # it is testing, not on an implementation detail of a neighbouring one.)
  export SHIP_LAND_MEMO=off

  GATE_OBS="$BATS_TEST_TMPDIR/gate-obs"
  MOVER_ARMED="$BATS_TEST_TMPDIR/mover-armed"    # content = max sibling lands to inject
  MOVER_COUNT="$BATS_TEST_TMPDIR/mover-count"
  SHIMDIR="$BATS_TEST_TMPDIR/shims"
  mkdir -p "$SHIMDIR"
  make_gate_shim 0
  export PATH="$SHIMDIR:$PATH"
}

make_gate_shim() {  # $1=sleep-seconds per gate invocation (the synthetic suite duration)
  cat > "$SHIMDIR/shellcheck" <<EOF
#!/bin/bash
# gate observer + race injector (test shim). Lock state is a DURABLE product per invocation.
if [ -d "$LAND_LOCK_DIR/lock.d" ]; then locked=yes; else locked=no; fi
if [ "\$locked" = yes ]; then echo LOCKED >> "$GATE_OBS"; else echo UNLOCKED >> "$GATE_OBS"; fi
if [ "\$locked" = no ] && [ -f "$MOVER_ARMED" ]; then
  n=\$(cat "$MOVER_COUNT" 2>/dev/null || echo 0)
  if [ "\$n" -lt "\$(cat "$MOVER_ARMED")" ]; then
    echo \$(( n + 1 )) > "$MOVER_COUNT"
    git -C "$SIB" pull -q --rebase origin main
    echo "sib-\$n" > "$SIB/sib-\$n.txt"
    git -C "$SIB" add "sib-\$n.txt"
    git -C "$SIB" commit -q -m "sib \$n"
    git -C "$SIB" push -q origin HEAD:main
  fi
fi
sleep "$1"
exit 0
EOF
  chmod +x "$SHIMDIR/shellcheck"
}

our_branch() {  # $1=branch $2=shell-file — a landable commit that always trips the shim
  git checkout -q -b "$1" main
  printf '#!/usr/bin/env bash\necho ok\n' > "$2"
  git add "$2"
  git commit -q -m "feat: $2"
}

@test "CAS fast path: origin unmoved → gate runs ONCE, UNLOCKED; land verified" {
  our_branch feat/fast fast.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "LANDED"
  [[ "$output" != *"STALE GATE"* ]] || false

  # THE core claim, as a durable product: exactly one gate run, and it held NO lock.
  [ "$(wc -l < "$GATE_OBS" | tr -d ' ')" = "1" ]
  [ "$(cat "$GATE_OBS")" = "UNLOCKED" ]

  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- fast.sh)" ]
  grep -q '"verify":"ok"' "$LAND_LOG"
}

@test "stale gate: sibling lands mid-gate → in-lock CAS detects, re-gates UNLOCKED, both contents land (no drop)" {
  echo 1 > "$MOVER_ARMED"                      # exactly one sibling land, injected DURING our gate
  our_branch feat/race race.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "STALE GATE"        # the CAS fired…
  echo "$output" | grep -q "LANDED"

  # …and the re-gate ran (2 gate runs), BOTH unlocked — the delta was re-proven on the
  # new final tree without ever holding the mutex through a suite.
  [ "$(wc -l < "$GATE_OBS" | tr -d ' ')" = "2" ]
  [ "$(sort -u "$GATE_OBS")" = "UNLOCKED" ]

  # no-drop, content-level: OUR change AND the sibling's are both intact on the trunk.
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- race.sh)" ]
  [ -n "$(git ls-tree origin/main -- sib-0.txt)" ]
  [ -z "$(git diff HEAD origin/main -- race.sh)" ]
  grep -q '"verify":"ok"' "$LAND_LOG"
}

@test "re-gate fires IFF origin moved: unmoved → 1 gate run; moved → 2 (the iff, both directions)" {
  # direction 1 (unmoved ⇒ no re-gate) is the fast-path test's 1-line observer file;
  # direction 2 (moved ⇒ re-gate) is the stale-gate test's 2-line one. This test pins the
  # discriminator in ONE place so a regression in either direction reads as a count flip.
  our_branch feat/iff-a iff-a.sh
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$GATE_OBS" | tr -d ' ')" = "1" ]

  : > "$GATE_OBS"; rm -f "$MOVER_COUNT"
  echo 1 > "$MOVER_ARMED"
  our_branch feat/iff-b iff-b.sh
  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$GATE_OBS" | tr -d ' ')" = "2" ]
}

smoke_fixture() {  # seed one suite + a bats shim + a selector whose --direct names it
  # Without this the in-lock tests below cannot fail: a gate with no suite to run trivially runs
  # no bats, so "0 invocations" would be true of a broken build and a correct one alike. Every
  # in-lock assertion is paired with the UNLOCKED control run that proves the smoke DOES fire.
  cat > "$SHIMDIR/bats" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/bats-argv"
echo "1..1"; echo "ok 1 fine"; exit 0
EOF
  chmod +x "$SHIMDIR/bats"
  : > "$BATS_TEST_TMPDIR/bats-argv"
  SEL="$BATS_TEST_TMPDIR/gate-select.sh"
  cat > "$SEL" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/sel-argv"
case "\$1" in lint) exit 0 ;; esac
echo tests/a.bats
EOF
  chmod +x "$SEL"
  export SHIP_LAND_GATE_SELECT="$SEL"
  export SHIP_LAND_GATE_POLICY="$BATS_TEST_TMPDIR/no-such-policy.sh"
  mkdir -p tests
  printf '#!/usr/bin/env bats\n@test "a" { true; }\n' > tests/a.bats
  git add tests && git commit -q -m "seed suite" && git push -q origin HEAD:main
  git fetch -q origin main
}

@test "rounds exhausted: sibling lands during EVERY unlocked gate → in-lock STATICS-only fallback lands all content, runs NO bats" {
  smoke_fixture
  echo 99 > "$MOVER_ARMED"                     # sustained contention: every unlocked gate is invalidated
  our_branch feat/contend contend.sh

  run env SHIP_LAND_GATE_ROUNDS=2 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "in-lock STATICS-only re-gate"

  # rounds 1+2 unlocked (each invalidated), round 3 = the guaranteed-progress in-lock re-gate
  # (the shim records LOCKED and — being locked — cannot inject further movement).
  [ "$(cat "$GATE_OBS")" = "UNLOCKED
UNLOCKED
LOCKED" ]
  # THE v2 INVARIANT. v1 ran the FULL corpus on this exact path — the 3h36m lock holder. The
  # unlocked rounds each smoked (2 invocations); the in-lock round must add NONE.
  echo "$output" | grep -q "no bats inside the land-lock"
  [ "$(grep -c . "$BATS_TEST_TMPDIR/bats-argv")" -eq 2 ]

  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- contend.sh)" ]
  [ -n "$(git ls-tree origin/main -- sib-0.txt)" ]   # neither sibling land was dropped
  [ -n "$(git ls-tree origin/main -- sib-1.txt)" ]
  grep -q '"verify":"ok"' "$LAND_LOG"
}

@test "kill switch: SHIP_LAND_GATE_ROUNDS=0 → statics run IN-LOCK, and STILL no bats" {
  smoke_fixture
  our_branch feat/legacy legacy.sh

  run env SHIP_LAND_GATE_ROUNDS=0 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$GATE_OBS" | tr -d ' ')" = "1" ]
  [ "$(cat "$GATE_OBS")" = "LOCKED" ]          # the statics DO run under the lock (milliseconds)
  [ ! -s "$BATS_TEST_TMPDIR/bats-argv" ]       # …and nothing heavy follows them
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- legacy.sh)" ]
}

@test "in-lock POSITIVE CONTROL: the same fixture, unlocked, DOES run the smoke" {
  # Without this the two zero-invocation assertions above pass on any build where the selector,
  # the shim, or the seeded suite is broken — i.e. where NO gate anywhere runs bats.
  smoke_fixture
  our_branch feat/control ctl.sh

  run bash "$SHIPLAND" --trunk main            # default ROUNDS ⇒ the UNLOCKED gate
  [ "$status" -eq 0 ]
  [ "$(cat "$GATE_OBS")" = "UNLOCKED" ]
  [ "$(cat "$BATS_TEST_TMPDIR/bats-argv")" = "tests/a.bats" ]
}

@test "in-lock: the ban binds in the v1 lane too — the kill switch never restores the in-lock corpus" {
  # SHIP_LAND_LANE=v1 buys back the corpus PROOF, never the lock pathology. Pinned because "the
  # kill switch restores v1 behaviour" is the natural reading, and v1 behaviour on this path is
  # precisely the multi-day jam.
  smoke_fixture
  our_branch feat/v1-inlock v1il.sh

  run env SHIP_LAND_GATE_ROUNDS=0 SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(cat "$GATE_OBS")" = "LOCKED" ]
  echo "$output" | grep -q "no bats inside the land-lock, in either lane"
  [ ! -s "$BATS_TEST_TMPDIR/bats-argv" ]       # not even the v1 corpus

  # CONTROL: the same lane, UNLOCKED, really does run the whole corpus — so the zero above is the
  # lock's doing, not the lane's.
  : > "$BATS_TEST_TMPDIR/bats-argv"
  our_branch feat/v1-unlocked v1ul.sh
  run env SHIP_LAND_LANE=v1 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(cat "$BATS_TEST_TMPDIR/bats-argv")" = "tests/a.bats" ]
}

@test "dry-run: gate runs UNLOCKED and the landing mutex is NEVER taken" {
  our_branch feat/dry dry.sh

  run bash "$SHIPLAND" --trunk main --dry-run
  [ "$status" -eq 0 ]
  echo "$output" | grep -qi "dry-run"
  [ "$(cat "$GATE_OBS")" = "UNLOCKED" ]
  [ ! -d "$LAND_LOCK_DIR" ]                    # land-lock.sh mkdirs this on every entry — absence
                                               # proves the lock path never ran (pre-fix: it did)
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- dry.sh)" ]
}

@test "hold-time collapse: a slow gate (3s) no longer inflates lock hold (hold_s ≤ 2)" {
  make_gate_shim 3                              # synthetic suite duration inside the shim
  our_branch feat/slow slow.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]

  # land-lock's telemetry line (the one with wait_s) carries the REAL hold duration.
  hold="$(grep '"wait_s"' "$LAND_LOG" | tail -1 | sed -E 's/.*"hold_s":([0-9]+).*/\1/')"
  [ -n "$hold" ]
  [ "$hold" -le 2 ]                             # pre-fix: ≥ 3 (the gate ran inside the hold)
}

@test "in-lock net is BOUNDED: a hung push ⇒ exit 10 (MACHINE), not a red, and nothing lands" {
  # The other half of "the lock covers the race window and nothing else": the window is a fetch, a
  # push and a verify, and two of those talk to a remote that can simply stop answering. land-lock
  # NEVER reaps a live holder (H2, deliberate), so an unbounded in-lock push hung on an
  # unresponsive remote is not a slow land — it is a machine-wide wedge with no self-recovery, and
  # every other lander on the box queues behind it until a human notices.
  #
  # The verdict matters as much as the bound. A bound firing is the ABSENCE of an answer, so it is
  # evidence about the network, never about the tree: it must be the machine class (exit 10, like
  # the gate's 9), never a red (6). Collapsing a machine fact into a code verdict is what turned a
  # 2026-07-26 load spike into a re-block/retry runaway.
  realgit="$(command -v git)"
  cat > "$SHIMDIR/git" <<EOF
#!/bin/bash
# Everything forwards verbatim; only \`push\` hangs — so the pipeline reaches the lock normally and
# the bound is what stops it, rather than a broken git failing somewhere earlier.
case "\$1" in push) sleep 30 ;; esac
exec "$realgit" "\$@"
EOF
  chmod +x "$SHIMDIR/git"
  export SHIP_LAND_NET_TIMEOUT_S=1

  our_branch feat/hungpush hung.sh
  backup="ship/backup-$(git rev-parse --short HEAD)"

  run bash "$SHIPLAND" --trunk main
  # The shim's hang is 30s, not infinite, deliberately: in production the pre-fix hold lasts as
  # long as the remote sulks, but a fixture that reproduced THAT would wedge the suite instead of
  # failing it. Bounded, a regression lands after 30s and this reads status 0 — measured.
  [ "$status" -eq 10 ]
  echo "$output" | grep -q "MACHINE"
  [[ "$output" != *"GATE RED"* ]] || false          # a bound firing is never a claim about the tree

  rm -f "$SHIMDIR/git"; hash -r                     # real git again (hash -r: bash caches the path)
  grep -q '"exit":10' "$LAND_LOG"
  git fetch -q origin main
  [ -z "$(git ls-tree origin/main -- hung.sh)" ]    # nothing landed…
  git show-ref --verify --quiet "refs/heads/$backup" # …and the rollback point is intact
  [ -z "$(git status --porcelain)" ]                # …on a clean tree
  [ ! -d "$LAND_LOCK_DIR/lock.d" ]                  # …with the mutex RELEASED, not wedged
}

@test "many refs: the hold EXCLUDES the sweep — 640 branches, ~7s of sweep, hold_s ≤ 2" {
  # THE BLIND SPOT THE TEST ABOVE LEAVES, and the reason an 87s median hold survived a suite that
  # asserts hold_s ≤ 2 on every land. "hold-time collapse" runs on a ~2-branch fixture, where
  # stranded-sweep costs milliseconds — so it passed identically whether the sweep was inside the
  # mutex or outside it. It measured the GATE's exclusion and nothing else. In production the same
  # sweep is O(497 refs) at 59-62s and was ~90% of the hold, growing with every branch anyone
  # creates: the assertion was true, the number was small, and the defect was invisible.
  #
  # So this fixture pays the O(refs) cost for real — 600 plain branches plus 40 carrying a file
  # that never landed (the sweep's flagging path, which is the expensive one) ⇒ a ~7s sweep. Built
  # with plumbing, not 640 checkouts: ~120 forks instead of ~1800.
  #
  # TWO assertions, and the second is the one that cannot be argued with:
  #   · hold_s ≤ 2 while the sweep costs ~7s — RED pre-fix, where the hold necessarily EXCEEDS it.
  #   · land.log ORDERING — land-lock writes its line AT RELEASE and ship-land writes its attest
  #     AFTER the sweep, into the same file. Pre-fix the attest is inside the hold, so it lands
  #     FIRST; post-fix the release line does. That is a proof of ordering with no clock in it.
  # No smoke_fixture: this fixture has no tests/, so the smoke is skipped and the ~7s the land
  # spends is the sweep and only the sweep — nothing else can be blamed for the hold.
  main_sha="$(git rev-parse main)"

  # 600 branches pointing at main: cheap for us, one `git cherry` each for the sweep.
  for i in $(seq 1 600); do printf 'create refs/heads/wip/b%s %s\n' "$i" "$main_sha"; done \
    | git update-ref --stdin

  # 40 branches each carrying a commit whose new path is ABSENT from the trunk — the class the
  # sweep actually reports, so this fixture exercises the reporting path and not just the walk.
  # The tree is main's tree PLUS the new file: a tree containing only the new file would show
  # base.txt as deleted, base.txt is present on trunk, and `all_absent` would go 0 — flagging
  # nothing and making the whole fixture vacuous.
  (
    export GIT_INDEX_FILE="$BATS_TEST_TMPDIR/fixture-index"
    git read-tree main
    for i in $(seq 1 40); do
      blob="$(printf 'stranded %s\n' "$i" | git hash-object -w --stdin)"
      git update-index --add --cacheinfo "100644,$blob,stranded-$i.txt"
      tree="$(git write-tree)"
      c="$(git commit-tree "$tree" -p "$main_sha" -m "stranded $i")"
      printf 'create refs/heads/wip/s%s %s\n' "$i" "$c"
    done
  ) | git update-ref --stdin

  [ "$(git for-each-ref --format='%(refname:short)' refs/heads/ | wc -l | tr -d ' ')" -ge 641 ]

  our_branch feat/manyref manyref.sh
  backup="ship/backup-$(git rev-parse --short HEAD)"

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "LANDED"

  # 1. The hold excludes the sweep.
  hold="$(grep '"wait_s"' "$LAND_LOG" | tail -1 | sed -E 's/.*"hold_s":([0-9]+).*/\1/')"
  [ -n "$hold" ]
  [ "$hold" -le 2 ]

  # 2. The ordering, with no clock in it: release BEFORE attest.
  rel="$(grep -n '"wait_s"' "$LAND_LOG" | tail -1 | cut -d: -f1)"
  att="$(grep -n '"tool":"ship-land"' "$LAND_LOG" | grep '"verify":"ok"' | tail -1 | cut -d: -f1)"
  [ -n "$rel" ]                                # both lines must EXIST before comparing them —
  [ -n "$att" ]                                # separate assertions: `&&` absorbs the first's red
  [ "$rel" -lt "$att" ]                        # pre-fix: the attest is INSIDE the hold ⇒ rel > att

  # NON-VACUITY. Every assertion above would also pass if the sweep had silently not run at all —
  # which is precisely how a "we moved it out" change could pass by deleting it instead. The
  # sweep's own verdict line carries BOTH numbers this fixture built, so assert both:
  #   ✗ stranded-sweep: 40 commit(s) hold content not on origin/main, on 40 of 641 local branch(es)
  # The denominator proves the WALK (all ~640 refs); the 40 proves the REPORTING path (the class
  # whose paths are all absent from the trunk) — a sweep that walked nothing can satisfy neither.
  # Wording note: pre-`ec357997b` that line read "…, across 641 branch(es)." and this assertion
  # greped `across 6[0-9][0-9] branch\(es\)`. The 2026-08-12 damping commit re-shaped the
  # un-`--mine` verdict into "on N of M local branch(es)" and did not carry this fixture with it,
  # so the grep went red while the sweep was working perfectly — a stale assertion, not a
  # regression. It is re-pointed at the current text and STRENGTHENED (two numbers, not one)
  # rather than relaxed: relaxing it is the exact defect it exists to prevent.
  echo "$output" | grep -qE 'on 40 of 6[0-9][0-9] local branch\(es\)'  # it really walked the 640…
  echo "$output" | grep -qE '40 commit\(s\) hold content not on'       # …and flagged all 40 strands
  grep -q '"sweep":"review"' "$LAND_LOG"       # …and the attestation field still populates

  # The reap is post-release too, and still discharges the rollback ref.
  run git show-ref --verify --quiet "refs/heads/$backup"
  [ "$status" -ne 0 ]

  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- manyref.sh)" ]
}

@test "true concurrency: two real landers race → both land, both contents verified, zero drops" {
  # End-to-end (no injected mover): two ship-land processes on one mutex, overlapping gates
  # (2s shim sleep). Whichever loses the CAS re-gates and re-lands. The 2026-07-11 guarantee
  # under REAL concurrency: every commit content-verified on the trunk, none dropped.
  make_gate_shim 2
  WORKB="$BATS_TEST_TMPDIR/workB"
  git clone -q "$ORIGIN" "$WORKB"
  git -C "$WORKB" config user.email b@example.com
  git -C "$WORKB" config user.name b

  our_branch feat/racer-a a.sh                 # in $WORK
  git -C "$WORKB" checkout -q -b feat/racer-b main
  printf '#!/usr/bin/env bash\necho b\n' > "$WORKB/b.sh"
  git -C "$WORKB" add b.sh
  git -C "$WORKB" commit -q -m "feat: b.sh"

  ( cd "$WORK"  && bash "$SHIPLAND" --trunk main > "$BATS_TEST_TMPDIR/a.out" 2>&1; echo $? > "$BATS_TEST_TMPDIR/a.rc" ) &
  ( cd "$WORKB" && bash "$SHIPLAND" --trunk main > "$BATS_TEST_TMPDIR/b.out" 2>&1; echo $? > "$BATS_TEST_TMPDIR/b.rc" ) &
  wait

  [ "$(cat "$BATS_TEST_TMPDIR/a.rc")" = "0" ]
  [ "$(cat "$BATS_TEST_TMPDIR/b.rc")" = "0" ]
  git fetch -q origin main
  git -C "$WORKB" fetch -q origin main
  [ -n "$(git ls-tree origin/main -- a.sh)" ]
  [ -n "$(git ls-tree origin/main -- b.sh)" ]
  [ -z "$(git -C "$WORK"  diff HEAD origin/main -- a.sh)" ]   # content-identical, not just present
  [ -z "$(git -C "$WORKB" diff HEAD origin/main -- b.sh)" ]
  [ "$(grep -c '"verify":"ok"' "$LAND_LOG")" = "2" ]          # BOTH lands content-verified
}

@test "stale-gate re-round runs the SMOKE, never a corpus — and carries the UNION range" {
  # The CAS contract is lane-independent: a sibling landing during the unlocked gate must still
  # trip exit 42 inside the lock and force an unlocked RE-gate of the new final tree (2
  # observations, both UNLOCKED). What v2 changes is the COST of that re-round — it is the smoke
  # again, seconds, not a second 20-53 minute corpus. That is the whole reason the optimistic
  # rounds survive v2 at all (their v1 economics: 26.4h of accumulated lock-wait for 79s of work,
  # ~30% of rounds invalidated, each invalidation paying for a full re-proof).
  smoke_fixture
  gc="$(git rev-parse --git-common-dir)"; rm -f "$gc/gate-green"

  echo 1 > "$MOVER_ARMED"                          # exactly one sibling land, during our gate
  our_branch feat/stale-cas stale-cas.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "STALE GATE"                             # CAS fired…
  [ "$(wc -l < "$GATE_OBS" | tr -d ' ')" = "2" ]                    # …and it re-gated…
  [ "$(sort -u "$GATE_OBS")" = "UNLOCKED" ]                         # …still never in the lock
  # Both rounds ran the SELECTED suite, one process each — never the whole corpus, and never the
  # deleted monolithic `bats tests/` invocation.
  [ "$(sort -u "$BATS_TEST_TMPDIR/bats-argv")" = "tests/a.bats" ]
  [ "$(grep -c . "$BATS_TEST_TMPDIR/bats-argv")" -eq 2 ]            # exactly one per round
  [ "$(grep -cx 'tests/' "$BATS_TEST_TMPDIR/bats-argv")" -eq 0 ]
  [ ! -f "$gc/gate-green" ]                                         # a land never stamps the marker

  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- stale-cas.sh)" ]               # no drop, either side
  [ -n "$(git ls-tree origin/main -- sib-0.txt)" ]
  grep -q '"gate_scope":"fast"' "$LAND_LOG"
  grep -q '"smoke":"green"' "$LAND_LOG"

  # UNION SCOPE, preserved verbatim from v1 and now carried on the ONLY call the smoke makes.
  # Round 1 selects on our delta alone; the re-round must ALSO hand the selector the trunk delta
  # the sibling landed while we gated (FIRST_BASE..new base), or the re-round is blind to the
  # composed tree's only novelty. v2 narrows the surface: the plain (non---direct) selector call
  # and the `lint` call are both GONE, so --direct is where this has to hold.
  grep '^--direct' "$BATS_TEST_TMPDIR/sel-argv" > "$BATS_TEST_TMPDIR/direct-only"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/direct-only" | tr -d ' ')" = "2" ]                    # two rounds
  [ "$(head -1 "$BATS_TEST_TMPDIR/direct-only" | awk '{print gsub(/\.\./,"")}')" = "1" ]  # r1: 1 range
  [ "$(tail -1 "$BATS_TEST_TMPDIR/direct-only" | awk '{print gsub(/\.\./,"")}')" = "2" ]  # r2: + union
  fb="$(sed -E 's/^--direct //; s/\.\..*//' < "$BATS_TEST_TMPDIR/direct-only" | head -1)"  # r1's base
  tail -1 "$BATS_TEST_TMPDIR/direct-only" | grep -q " $fb\.\."     # the union range is anchored there

  # …and the selector's OTHER two entry points are never called at all in the fast lane: the plain
  # selection decided the corpus tier (deleted) and `lint` gated a degrade-to-FULL (deleted).
  [ "$(grep -cv '^--direct' "$BATS_TEST_TMPDIR/sel-argv")" -eq 0 ]
}

@test "P0 exit 42 attests: the stale re-round is a ROW, marked non-terminal, and lands once" {
  # THE STALENESS INSTRUMENT (land-architecture-100p §5 P0, §2.B). P(exit-42 | wait>0) — 49% over
  # 14d rising to 86% over 3d — had to be reconstructed by hand from the LOCK ledger, because the
  # TOOL ledger recorded nothing at all for a stale round. Measured on the live store the day this
  # landed: 14 days of ship-land rows contain ZERO exit-42s, while the lock rows contain 74 stale
  # re-rounds in the last day alone. And the lock ledger can only ever see the rounds that QUEUED,
  # which is precisely the wrong half — §2.B found the WAIT-FREE staleness column to be the rising
  # one (4→6→4→15→21 across 08-06..08-10).
  #
  # stage:"round" is the load-bearing half of the fix. A stale round is an INTERNAL signal — the
  # same land continues — so its row must not enter any rate's denominator; without the marker,
  # adding these rows would have silently DILUTED the gate-red rate by however often siblings
  # happened to move the trunk, i.e. the instrument would have improved its own headline number.
  echo 1 > "$MOVER_ARMED"                                           # one sibling land, mid-gate
  our_branch feat/p0-stale p0stale.sh

  run bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "STALE GATE"

  rounds="$(grep '"tool":"ship-land"' "$LAND_LOG" | grep -c '"stage":"round"')"
  [ "$rounds" -eq 1 ]                                               # RED pre-fix: zero rows existed
  grep '"stage":"round"' "$LAND_LOG" | grep -q '"exit":42'
  # …and exactly one TERMINAL row for the same land, so the two are distinguishable and a reader
  # counting lands does not count this one twice.
  [ "$(grep '"tool":"ship-land"' "$LAND_LOG" | grep -c '"stage":"land"')" -eq 1 ]
  grep '"stage":"land"' "$LAND_LOG" | grep -q '"exit":0'

  # The terminal row's gate_rounds counts BOTH gates — the measurement survives the locked re-exec
  # and the re-round, which is the whole reason it is carried in the environment rather than
  # recomputed. A re-derived counter would have reported 1 here and hidden the second gate's cost.
  grep '"stage":"land"' "$LAND_LOG" | grep -qE '"gate_rounds":2'
}

@test "P0 exit 42: the round row is written with the mutex ALREADY RELEASED" {
  # The constraint P1 paid a whole session for: nothing heavy may enter the lock, and an instrument
  # that bought its visibility inside the mutex would be paying in the currency it measures. The
  # stale-gate exit fires while the lock is HELD, so the row is deliberately written by the outer
  # process after land-lock returns — the locked child adds not one fork to that path.
  #
  # Asserted structurally rather than by timing: the attest call for stage "round" must not appear
  # inside main_locked. A wall-clock assertion here would be a load-dependent test of a 3s hold.
  sl="$REPO/scripts/ship-land.sh"
  ml="$(awk '/^main_locked\(\)/{print NR; exit}' "$sl")"
  nx="$(awk -v s="$ml" 'NR>s && /^[a-z_]+\(\) \{/{print NR; exit}' "$sl")"
  [ -n "$ml" ] && [ -n "$nx" ] || false
  [ "$(awk -v a="$ml" -v b="$nx" 'NR>a && NR<b' "$sl" | grep -c 'attest_land .*"round"')" -eq 0 ]
  # …and it DOES appear in the outer loop, so this is a placement assertion and not a vacuous one.
  [ "$(grep -c 'attest_land .*"round"' "$sl")" -eq 1 ]
}
