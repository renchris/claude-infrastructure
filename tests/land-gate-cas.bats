#!/usr/bin/env bats
# land-gate-cas.bats — the land-gate serialization fix (2026-07-25): the FULL gate runs
# UNLOCKED (parallel across sessions); the landing lock covers ONLY the CAS race window
# (fetch-compare → push → content-verify). RED-proofed against the pre-fix pipeline, which
# ran the entire gate INSIDE the lock:
#   * "gate runs unlocked"      → pre-fix the gate observer records LOCKED, not UNLOCKED.
#   * "stale-gate re-gate"      → pre-fix a sibling land mid-gate ⇒ push non-ff exit 7 (no
#                                 re-gate, land FAILS); post-fix exit 42 → unlocked re-gate
#                                 of the new final tree → land succeeds, nothing dropped.
#   * "dry-run takes no lock"   → pre-fix dry-run held the mutex for the whole gate.
#   * "hold-time collapse"      → pre-fix hold_s ≥ gate duration; post-fix hold_s ≈ 0.
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
  [[ "$output" != *"STALE GATE"* ]]

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

@test "rounds exhausted: sibling lands during EVERY unlocked gate → in-lock full-gate fallback terminates + lands all content" {
  echo 99 > "$MOVER_ARMED"                     # sustained contention: every unlocked gate is invalidated
  our_branch feat/contend contend.sh

  run env SHIP_LAND_GATE_ROUNDS=2 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "falling back to the in-lock full gate"

  # rounds 1+2 unlocked (each invalidated), round 3 = the guaranteed-progress in-lock gate
  # (the shim records LOCKED and — being locked — cannot inject further movement).
  [ "$(cat "$GATE_OBS")" = "UNLOCKED
UNLOCKED
LOCKED" ]

  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- contend.sh)" ]
  [ -n "$(git ls-tree origin/main -- sib-0.txt)" ]   # neither sibling land was dropped
  [ -n "$(git ls-tree origin/main -- sib-1.txt)" ]
  grep -q '"verify":"ok"' "$LAND_LOG"
}

@test "kill switch: SHIP_LAND_GATE_ROUNDS=0 → pre-fix behavior, gate runs IN-LOCK" {
  our_branch feat/legacy legacy.sh

  run env SHIP_LAND_GATE_ROUNDS=0 bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$GATE_OBS" | tr -d ' ')" = "1" ]
  [ "$(cat "$GATE_OBS")" = "LOCKED" ]
  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- legacy.sh)" ]
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

@test "scoped gate: CAS semantics preserved — sibling mid-gate ⇒ stale-gate re-gate, both contents land" {
  # Scoping changes WHICH suites run, never the CAS contract. A sibling landing during the
  # unlocked SCOPED gate must still trip exit 42 inside the lock and force an unlocked RE-gate of
  # the new final tree (2 observations, both UNLOCKED) — and the re-gate must itself be scoped.
  cat > "$SHIMDIR/bats" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/bats-argv"
exit 0
EOF
  chmod +x "$SHIMDIR/bats"
  sel="$BATS_TEST_TMPDIR/gate-select.sh"
  cat > "$sel" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >> "$BATS_TEST_TMPDIR/sel-argv"
case "\$1" in lint) exit 0 ;; --direct) exit 0 ;; esac
echo tests/a.bats
EOF
  chmod +x "$sel"
  mkdir -p tests                                   # the fixture has no suites; the gate needs one
  printf '#!/usr/bin/env bats\n@test "a" { true; }\n' > tests/a.bats
  git add tests && git commit -q -m "seed suite" && git push -q origin HEAD:main
  git fetch -q origin main
  gc="$(git rev-parse --git-common-dir)"; rm -f "$gc/gate-green"

  echo 1 > "$MOVER_ARMED"                          # exactly one sibling land, during our gate
  our_branch feat/scoped-cas scoped-cas.sh

  run env SHIP_LAND_GATE_SCOPE=scoped SHIP_LAND_GATE_SELECT="$sel" bash "$SHIPLAND" --trunk main
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "STALE GATE"                             # CAS fired…
  [ "$(wc -l < "$GATE_OBS" | tr -d ' ')" = "2" ]                    # …and it re-gated…
  [ "$(sort -u "$GATE_OBS")" = "UNLOCKED" ]                         # …still never in the lock
  [ "$(sort -u "$BATS_TEST_TMPDIR/bats-argv")" = "tests/a.bats" ]   # both gates scoped, not full
  [ ! -f "$gc/gate-green" ]                                         # scoped ⇒ marker untouched

  git fetch -q origin main
  [ -n "$(git ls-tree origin/main -- scoped-cas.sh)" ]              # no drop, either side
  [ -n "$(git ls-tree origin/main -- sib-0.txt)" ]
  grep -q '"gate_scope":"scoped"' "$LAND_LOG"

  # UNION SCOPE — the amendment. Round 1 selects on our delta alone; the re-gate must ALSO hand
  # the selector the trunk delta the sibling landed while we gated (FIRST_BASE..new base), or
  # the re-gate is scoped blind to the composed tree's only novelty.
  grep -v -e '^--direct' -e '^lint' "$BATS_TEST_TMPDIR/sel-argv" > "$BATS_TEST_TMPDIR/sel-only"
  [ "$(wc -l < "$BATS_TEST_TMPDIR/sel-only" | tr -d ' ')" = "2" ]                   # two rounds
  [ "$(head -1 "$BATS_TEST_TMPDIR/sel-only" | awk '{print gsub(/\.\./,"")}')" = "1" ]  # r1: 1 range
  [ "$(tail -1 "$BATS_TEST_TMPDIR/sel-only" | awk '{print gsub(/\.\./,"")}')" = "2" ]  # r2: + union
  fb="$(sed 's/\.\..*//' < "$BATS_TEST_TMPDIR/sel-only" | head -1)"                  # round 1's base
  tail -1 "$BATS_TEST_TMPDIR/sel-only" | grep -q " $fb\.\."       # the union range is anchored there
}
